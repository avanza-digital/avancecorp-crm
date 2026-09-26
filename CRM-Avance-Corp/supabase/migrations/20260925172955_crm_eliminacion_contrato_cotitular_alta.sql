-- Admin y Superadmin conservan su permiso permanente en CRM y portal.
-- El origen de cotitular creado en el alta es parte del contrato, no historial
-- posterior. Se archiva íntegro antes de retirarlo en la misma transacción.
-- Instalar esta migración NO elimina contratos. Conserva PDF, identidades,
-- solicitudes/revisiones, períodos cerrados y protecciones de historial posterior.
begin;
set local lock_timeout='5s';
do $guarda$ begin
  if (select md5(prosrc) from pg_proc where oid='crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure)
      is distinct from '4afcb3d1300f6e8bdcc64ede6eb57987'
    or (select md5(prosrc) from pg_proc where oid='private.f4_fuente_inmutable()'::regprocedure)
      is distinct from '875118833ce96aac81356e8f63049695'
    or (select md5(prosrc) from pg_proc where oid='private.f4_proteger_origen_cotitular()'::regprocedure)
      is distinct from 'bb5588148b3c530a7e7d03d85c187190' then
    raise exception 'La base de eliminación cambió; revisar antes de instalar';
  end if;
end $guarda$;

create or replace function private.f4_proteger_origen_cotitular()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- Traslado exacto a la auditoría: sólo dentro de la reserva privada, con actor
  -- verificado. Las correcciones y las eliminaciones directas siguen prohibidas.
  if tg_table_schema='crm' and tg_table_name='inversion_cotitular_origenes' and tg_op='DELETE' then
    if old.origen_registro='alta' and exists (
      select 1 from crm.contratos_eliminados_auditoria a
      join private.contrato_eliminaciones r on r.contrato_id=a.contrato_id
      where r.token::text=current_setting('crm.contrato_registro_eliminacion',true)
        and r.solicitado_por=(select auth.uid()) and a.eliminado_por=r.solicitado_por
        and a.snapshot->>'version'='4'
        and a.snapshot#>>'{inversion,id}'=old.inversion_id::text
        and a.contrato_id::text=old.fuente_snapshot->>'contrato_id'
        and exists(select 1 from jsonb_array_elements(a.snapshot->'inversion_cotitular_origenes') e
          where e=to_jsonb(old))
    ) then return old; end if;
  end if;
  if tg_table_schema='crm' then
    raise exception 'La procedencia del cotitular conserva su registro original' using errcode='P0409';
  end if;
  if tg_op='UPDATE' and to_jsonb(new)=to_jsonb(old) then return new; end if;
  if exists(select 1 from crm.inversion_cotitular_origenes where contrato_titular_id=old.id) then
    raise exception 'El titular documental tiene procedencia neutral; conserva el documento original' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.f4_proteger_origen_cotitular() from public,anon,authenticated,service_role;

create or replace function private.f4_fuente_inmutable()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_schema='crm' and tg_table_name='inversion_eventos' and tg_op='DELETE' then
    if old.tipo='registro' and exists (
      select 1 from crm.contratos_eliminados_auditoria a
      join private.contrato_eliminaciones r on r.contrato_id=a.contrato_id
      where r.token::text=current_setting('crm.contrato_registro_eliminacion',true)
        and r.solicitado_por=(select auth.uid()) and a.eliminado_por=r.solicitado_por
        and a.snapshot->>'version' in ('3','4')
        and a.snapshot#>>'{inversion,id}'=old.inversion_id::text
        and a.snapshot->'inversion_eventos' @> jsonb_build_array(to_jsonb(old))
    ) then return old; end if;
  end if;
  if tg_table_name in ('inversion_ajustes_mes_cerrado','inversion_eventos','inversion_solicitud_revisiones','inversion_solicitud_correcciones') then
    raise exception 'El historial de una inversión no se modifica ni se elimina' using errcode='P0409';
  end if;
  if new.es_cierre_inicial is distinct from old.es_cierre_inicial
     or new.fecha_comercial is distinct from old.fecha_comercial
     or new.fecha_imputacion is distinct from old.fecha_imputacion
     or new.comprobante_objeto_id is distinct from old.comprobante_objeto_id then
    raise exception 'La clase, las fechas y el comprobante del cierre conservan su registro original' using errcode='P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.f4_fuente_inmutable() from public,anon,authenticated,service_role;

create or replace function crm.contrato_eliminar_auditado(p_contrato_id uuid, p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_rol text;
  v_contrato public.contratos%rowtype;
  v_inversion crm.inversiones%rowtype;
  v_auditoria crm.contratos_eliminados_auditoria%rowtype;
  v_objetos jsonb;
  v_token uuid;
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_registro_token_anterior text := current_setting('crm.contrato_registro_eliminacion', true);
begin
  -- Identidad verificada por la Edge. Se bloquea el perfil para que una baja o
  -- un cambio de rol no pueda intercalarse entre autorización y eliminación.
  select p.rol into v_rol from public.perfiles p
    where p.id=p_actor_id and p.activo for share;
  if v_rol is null or v_rol not in ('admin','superadmin') then
    raise exception 'Solo Admin o Superadmin puede eliminar contratos' using errcode='42501';
  end if;
  if p_contrato_id is null then
    raise exception 'Contrato no encontrado' using errcode='P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('contrato_eliminar_auditado:'||p_contrato_id::text,0));
  select * into v_auditoria from crm.contratos_eliminados_auditoria a where a.contrato_id=p_contrato_id;
  if found then
    if exists(select 1 from public.contratos where id=p_contrato_id) then
      raise exception 'El identificador del contrato ya tiene una eliminación auditada y requiere revisión' using errcode='55000';
    end if;
    return jsonb_build_object('ok',true,'contrato_id',p_contrato_id,
      'auditoria_id',v_auditoria.id,'archivos_conservados',jsonb_array_length(v_auditoria.archivos));
  end if;
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  select * into strict v_contrato from public.contratos where id=p_contrato_id;
  -- Fallar cerrado si una ampliación del esquema agrega dependencias que la
  -- copia versionada todavía no cubre (incluye descendientes del CASCADE).
  if exists (
    with recursive cascadas(relid) as (
      select 'public.contratos'::regclass::oid
      union
      select c.conrelid from pg_constraint c join cascadas x on x.relid=c.confrelid
        where c.contype='f' and c.confdeltype='c'
    )
    select 1 from pg_constraint c join cascadas x on x.relid=c.confrelid
    where c.contype='f' and c.confdeltype in ('c','n','d') and not (
      c.confrelid='public.contratos'::regclass and (
        (c.confdeltype='c' and c.conrelid in (
          'public.cronograma_pagos'::regclass,'public.documentos'::regclass,
          'public.contrato_titulares'::regclass,'crm.contrato_cuentas_pago'::regclass
        )) or (c.confdeltype='n' and c.conrelid in (
          'crm.leads'::regclass,'private.contrato_altas_idempotentes'::regclass
        ))
      )
      and c.conkey=array[(select attnum from pg_attribute
        where attrelid=c.conrelid and attname='contrato_id')]::smallint[]
    )
  ) then
    raise exception 'El contrato tiene dependencias nuevas; requiere revisión antes de eliminarlo' using errcode='55000';
  end if;
  -- Inversión multiempresa nacida de este contrato (a lo sumo una: índice único
  -- parcial sobre contrato_id). Se bloquea, se archiva y se retira con el contrato.
  select * into v_inversion from crm.inversiones i where i.contrato_id=p_contrato_id for update;
  if v_inversion.id is not null then
    -- Se eliminan explícitamente inversión y titulares. Ninguna relación nueva
    -- ni cambio de columnas/acción puede borrar o alterar evidencia sin archivar.
    if (select count(distinct c.conrelid) from pg_constraint c
          where c.contype='f' and c.confrelid='crm.inversiones'::regclass)<>5 or exists (
      select 1 from pg_constraint c
      where c.contype='f' and c.confrelid in ('crm.inversiones'::regclass,'crm.inversion_titulares'::regclass)
        and not (c.confrelid='crm.inversiones'::regclass and c.conrelid in (
          'crm.inversion_titulares'::regclass,'crm.inversion_eventos'::regclass,
          'crm.inversion_solicitudes'::regclass,'crm.inversion_ajustes_mes_cerrado'::regclass,
          'crm.inversion_cotitular_origenes'::regclass
        ) and c.confdeltype='a' and not c.condeferrable
        and c.conkey=array[(select attnum from pg_attribute
          where attrelid=c.conrelid and attname='inversion_id')]::smallint[]
        and c.confkey=array[(select attnum from pg_attribute
          where attrelid=c.confrelid and attname='id')]::smallint[])
    ) then
      raise exception 'La inversión del contrato tiene dependencias nuevas; requiere revisión antes de eliminarla' using errcode='55000';
    end if;
    -- El alta unificada siempre genera registro + solicitud confirmada. Son
    -- antecedentes del alta, no una operación posterior que impida archivarla.
    -- Bloquear filas antes de evaluar y copiar; la inversión bloqueada impide
    -- nuevas referencias concurrentes. Las revisiones de la solicitud se conservan.
    perform 1 from crm.inversion_eventos where inversion_id=v_inversion.id order by id for update;
    perform 1 from crm.inversion_solicitudes where inversion_id=v_inversion.id order by id for update;
    if exists(select 1 from pg_constraint where contype='f'
      and confrelid in ('crm.inversion_eventos'::regclass,'crm.inversion_cotitular_origenes'::regclass)) then
      raise exception 'La inversión del contrato tiene dependencias nuevas; requiere revisión antes de eliminarla' using errcode='55000';
    end if;
    perform 1 from crm.inversion_cotitular_origenes where inversion_id=v_inversion.id order by id for update;
    if exists(select 1 from crm.inversion_eventos e where e.inversion_id=v_inversion.id and e.tipo<>'registro')
      or exists(select 1 from crm.inversion_solicitudes s where s.inversion_id=v_inversion.id
        and (s.estado<>'confirmada'
          or s.resultado#>>'{fuente,id}' is distinct from p_contrato_id::text
          or s.inversionista_id is distinct from v_inversion.inversionista_id
          or s.empresa_id is distinct from v_inversion.empresa_id))
      or exists(select 1 from crm.inversion_ajustes_mes_cerrado a where a.inversion_id=v_inversion.id)
      or exists(select 1 from crm.inversion_cotitular_origenes o where o.inversion_id=v_inversion.id
        and (o.origen_registro<>'alta' or not exists (
          select 1 from public.contrato_titulares t
          where t.id=o.contrato_titular_id and t.contrato_id=p_contrato_id
            and o.fuente_snapshot=to_jsonb(t)
            and o.hash_fuente=private.idem_hash(to_jsonb(t))
        ))) then
      raise exception 'La inversión de este contrato ya tiene historial propio (eventos, solicitudes, ajustes o vínculos históricos de cotitulares) y se conserva; requiere revisión antes de eliminarla' using errcode='55000';
    end if;
    perform 1 from crm.inversion_titulares where inversion_id=v_inversion.id order by id for update;
  end if;
  if exists(select 1 from private.contrato_eliminaciones e where e.contrato_id=p_contrato_id) then
    raise exception 'El contrato tiene una eliminación anterior pendiente; requiere revisión antes de archivarlo' using errcode='55000';
  end if;
  if exists(select 1 from private.contrato_pdf_jobs j where j.contrato_id=p_contrato_id
    and j.estado in ('procesando','subido_verificado') and j.lease_expira_en>statement_timestamp()) then
    raise exception 'El PDF se está generando; reintenta la eliminación en unos minutos' using errcode='55000';
  end if;
  -- El lock contractual es el mismo de escritores/PDF. Los pagos existentes
  -- se bloquean también: una cuota que se edita en paralelo no queda fuera de la copia.
  perform 1 from public.cronograma_pagos where contrato_id=p_contrato_id order by id for update;
  perform 1 from public.documentos where contrato_id=p_contrato_id order by id for update;
  perform 1 from public.contrato_titulares where contrato_id=p_contrato_id order by id for update;
  perform 1 from crm.contrato_cuentas_pago where contrato_id=p_contrato_id order by id for update;

  select coalesce(jsonb_agg(x order by x->>'bucket',x->>'path'),'[]'::jsonb) into v_objetos
  from (
    select jsonb_build_object('bucket','contratos-generados','path',storage_path) as x
      from private.contrato_pdfs where contrato_id=p_contrato_id and storage_path is not null
    union
    select jsonb_build_object('bucket','contratos-generados','path',storage_path)
      from private.contrato_pdf_jobs where contrato_id=p_contrato_id and storage_path is not null
    union
    select jsonb_build_object('bucket','documentos','path',storage_path)
      from public.documentos where contrato_id=p_contrato_id and storage_path is not null
  ) objetos;
  perform set_config('request.jwt.claim.sub',p_actor_id::text,true);
  insert into crm.contratos_eliminados_auditoria(contrato_id,eliminado_por,snapshot,archivos)
  values(p_contrato_id,p_actor_id,jsonb_build_object(
    'version',4,'contrato',to_jsonb(v_contrato),
    'cliente', (select to_jsonb(p) from public.perfiles p where p.id=v_contrato.cliente_id),
    'actor',jsonb_build_object('id',p_actor_id,'rol',v_rol),
    'cronograma',coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from public.cronograma_pagos c where c.contrato_id=p_contrato_id),'[]'::jsonb),
    'documentos',coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from public.documentos d where d.contrato_id=p_contrato_id),'[]'::jsonb),
    'titulares',coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.contrato_titulares t where t.contrato_id=p_contrato_id),'[]'::jsonb),
    'cuentas_pago',coalesce((select jsonb_agg(to_jsonb(c)) from crm.contrato_cuentas_pago c where c.contrato_id=p_contrato_id),'[]'::jsonb),
    'pdfs',coalesce((select jsonb_agg(to_jsonb(p)) from private.contrato_pdfs p where p.contrato_id=p_contrato_id),'[]'::jsonb),
    'pdf_jobs',coalesce((select jsonb_agg(to_jsonb(j)-'lease_token') from private.contrato_pdf_jobs j where j.contrato_id=p_contrato_id),'[]'::jsonb),
    'operaciones',coalesce((select jsonb_agg(to_jsonb(o)) from crm.operaciones_cartera o where o.contrato_nuevo_id=p_contrato_id or o.contrato_origen_id=p_contrato_id),'[]'::jsonb),
    'altas_idempotentes',coalesce((select jsonb_agg(to_jsonb(a)) from private.contrato_altas_idempotentes a where a.contrato_id=p_contrato_id),'[]'::jsonb),
    'leads_referencias',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'contrato_id',l.contrato_id,'etapa',l.etapa)) from crm.leads l where l.contrato_id=p_contrato_id),'[]'::jsonb),
    'inversion',case when v_inversion.id is null then null else to_jsonb(v_inversion) end,
    'inversion_titulares',coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from crm.inversion_titulares t where t.inversion_id=v_inversion.id),'[]'::jsonb),
    'inversion_cotitular_origenes',coalesce((select jsonb_agg(to_jsonb(o) order by o.id) from crm.inversion_cotitular_origenes o where o.inversion_id=v_inversion.id),'[]'::jsonb),
    'inversion_eventos',coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from crm.inversion_eventos e where e.inversion_id=v_inversion.id),'[]'::jsonb),
    'inversion_solicitudes',coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from crm.inversion_solicitudes s where s.inversion_id=v_inversion.id),'[]'::jsonb)
  ),v_objetos) returning * into v_auditoria;

  -- Reserva y finalización en la MISMA transacción: si falla una dependencia,
  -- se revierten tanto la copia como el borrado. Ninguna llamada a Storage.
  insert into private.contrato_eliminaciones(contrato_id,solicitado_por,objetos)
    values(p_contrato_id,p_actor_id,v_objetos) returning token into v_token;
  -- La inversión sale antes que el contrato (FK RESTRICT); queda auditada al actor.
  if v_inversion.id is not null then
    -- La excepción del trigger exige el token privado de ESTA reserva, el actor
    -- y la copia exacta del evento. No basta un flag enviado por el cliente.
    perform set_config('crm.contrato_registro_eliminacion',v_token::text,true);
    delete from crm.inversion_cotitular_origenes o where o.inversion_id=v_inversion.id;
    delete from crm.inversion_eventos e where e.inversion_id=v_inversion.id;
    perform set_config('crm.contrato_registro_eliminacion',coalesce(v_registro_token_anterior,''),true);
    -- Se conserva la solicitud y todos sus antecedentes. Cancelarla cierra el
    -- replay de confirmar_inversion_fn y futuros envíos de bienvenida.
    update crm.inversion_solicitudes set estado='cancelada',inversion_id=null,
      actualizado_en=statement_timestamp()
      where inversion_id=v_inversion.id;
    delete from crm.inversion_titulares t where t.inversion_id=v_inversion.id;
    delete from crm.inversiones i where i.id=v_inversion.id;
  end if;
  perform crm.contrato_eliminacion_finalizar(p_contrato_id,v_token,p_actor_id);
  perform set_config('request.jwt.claim.sub',coalesce(v_sub_anterior,''),true);
  return jsonb_build_object('ok',true,'contrato_id',p_contrato_id,
    'auditoria_id',v_auditoria.id,'archivos_conservados',jsonb_array_length(v_objetos));
exception when others then
  perform set_config('crm.contrato_registro_eliminacion',coalesce(v_registro_token_anterior,''),true);
  perform set_config('request.jwt.claim.sub',coalesce(v_sub_anterior,''),true);
  raise;
end;
$$;
revoke all on function crm.contrato_eliminar_auditado(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function crm.contrato_eliminar_auditado(uuid,uuid) to service_role;
comment on function crm.contrato_eliminar_auditado(uuid,uuid) is
  'Permiso permanente de Admin/Superadmin activo: archiva y elimina contratos con pagos, registro inicial y cotitulares del alta. Conserva PDF privados y solicitudes canceladas con sus revisiones; rechaza historial posterior y meses cerrados. Solo Edge.';
do $guarda$ begin
  if (select md5(prosrc) from pg_proc where oid='crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure) is distinct from '7fe0fb64bb800c810ac8e1db40c0073b'
    or (select md5(prosrc) from pg_proc where oid='private.f4_fuente_inmutable()'::regprocedure) is distinct from 'cea16fb9c74787b6cbcbf64527899c17'
    or (select md5(prosrc) from pg_proc where oid='private.f4_proteger_origen_cotitular()'::regprocedure) is distinct from '54aa7353f56859cd80d3d751271256a8'
    or not has_function_privilege('service_role','crm.contrato_eliminar_auditado(uuid,uuid)','execute')
    or exists(select 1 from pg_proc p where p.oid in
      ('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure,'private.f4_fuente_inmutable()'::regprocedure,
       'private.f4_proteger_origen_cotitular()'::regprocedure)
      and (p.proacl is null or not p.prosecdef or not coalesce(p.proconfig @> array['search_path=""'],false)))
    or (select count(*) from pg_trigger where tgfoid='private.f4_proteger_origen_cotitular()'::regprocedure
      and tgrelid in ('crm.inversion_cotitular_origenes'::regclass,'public.contrato_titulares'::regclass)
      and tgenabled='O' and tgtype=27)<>2
    or exists(select 1 from pg_proc p, lateral aclexplode(p.proacl) a
      where p.oid in ('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure,
        'private.f4_fuente_inmutable()'::regprocedure,'private.f4_proteger_origen_cotitular()'::regprocedure)
      and a.grantee<>p.proowner
      and not (p.oid='crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure
        and a.grantee='service_role'::regrole and a.privilege_type='EXECUTE' and not a.is_grantable)) then
    raise exception 'La eliminación o sus permisos no coinciden con la versión verificada';
  end if;
end $guarda$;
notify pgrst,'reload schema';
commit;
