-- Admin/Superadmin: eliminar contratos incluso con pagos conservando evidencia.
-- Los PDF privados se conservan en sus rutas originales: NO se borra Storage.
-- No altera las reglas de historial F4, meses cerrados ni renovaciones del portal.
begin;

create table crm.contratos_eliminados_auditoria (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null unique,
  eliminado_por uuid not null,
  eliminado_en timestamptz not null default statement_timestamp(),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  archivos jsonb not null check (jsonb_typeof(archivos) = 'array')
);
alter table crm.contratos_eliminados_auditoria enable row level security;
revoke all on crm.contratos_eliminados_auditoria from public, anon, authenticated, service_role;
comment on table crm.contratos_eliminados_auditoria is
  'Copia privada inmutable del contrato, cuotas (incluidos pagos), titulares, cuentas, PDF y relaciones al eliminar. Sin FK al contrato eliminado. Los archivos privados referenciados se conservan; no son objetos huérfanos para limpieza.';

create function private.proteger_auditoria_contrato_eliminado()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  raise exception 'La copia de auditoría de un contrato eliminado es inmutable'
    using errcode='42501';
end;
$$;
revoke all on function private.proteger_auditoria_contrato_eliminado() from public, anon, authenticated, service_role;
create trigger trg_contratos_eliminados_inmutables
  before update or delete on crm.contratos_eliminados_auditoria
  for each row execute function private.proteger_auditoria_contrato_eliminado();
create trigger trg_contratos_eliminados_no_truncate before truncate on crm.contratos_eliminados_auditoria
  for each statement execute function private.proteger_auditoria_contrato_eliminado();
create trigger trg_audit_contratos_eliminados after insert on crm.contratos_eliminados_auditoria
  for each row execute function private.log_audit_sin_secretos('snapshot','archivos');

create function crm.contrato_eliminar_auditado(p_contrato_id uuid, p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_rol text;
  v_contrato public.contratos%rowtype;
  v_auditoria crm.contratos_eliminados_auditoria%rowtype;
  v_objetos jsonb;
  v_token uuid;
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
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
      c.confrelid='public.contratos'::regclass and c.conrelid in (
        'public.cronograma_pagos'::regclass,'public.documentos'::regclass,
        'public.contrato_titulares'::regclass,'crm.contrato_cuentas_pago'::regclass,
        'crm.leads'::regclass,'private.contrato_altas_idempotentes'::regclass
      )
      and c.conkey=array[(select attnum from pg_attribute
        where attrelid=c.conrelid and attname='contrato_id')]::smallint[]
    )
  ) then
    raise exception 'El contrato tiene dependencias nuevas; requiere revisión antes de eliminarlo' using errcode='55000';
  end if;
  if exists(select 1 from crm.inversiones i where i.contrato_id=p_contrato_id) then
    raise exception 'El contrato forma parte del historial de inversiones; conserva el registro y utiliza la anulación comercial que corresponda' using errcode='55000';
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
    'version',1,'contrato',to_jsonb(v_contrato),
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
    'leads_referencias',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'contrato_id',l.contrato_id,'etapa',l.etapa)) from crm.leads l where l.contrato_id=p_contrato_id),'[]'::jsonb)
  ),v_objetos) returning * into v_auditoria;

  -- Reserva y finalización en la MISMA transacción: si falla una dependencia,
  -- se revierten tanto la copia como el borrado. Ninguna llamada a Storage.
  insert into private.contrato_eliminaciones(contrato_id,solicitado_por,objetos)
    values(p_contrato_id,p_actor_id,v_objetos) returning token into v_token;
  perform crm.contrato_eliminacion_finalizar(p_contrato_id,v_token,p_actor_id);
  perform set_config('request.jwt.claim.sub',coalesce(v_sub_anterior,''),true);
  return jsonb_build_object('ok',true,'contrato_id',p_contrato_id,
    'auditoria_id',v_auditoria.id,'archivos_conservados',jsonb_array_length(v_objetos));
exception when others then
  perform set_config('request.jwt.claim.sub',coalesce(v_sub_anterior,''),true);
  raise;
end;
$$;
revoke all on function crm.contrato_eliminar_auditado(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function crm.contrato_eliminar_auditado(uuid,uuid) to service_role;
comment on function crm.contrato_eliminar_auditado(uuid,uuid) is
  'Solo Edge: verifica Admin/Superadmin activo, archiva datos y elimina el contrato en una transacción; conserva PDF privados y bloqueos del historial. Admite contratos con pagos.';

-- La Edge antigua falla cerrada durante la actualización; ya no puede preparar
-- rutas para borrar Storage ni finalizar por fuera de la copia auditada.
revoke all on function crm.contrato_eliminacion_preparar(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;
