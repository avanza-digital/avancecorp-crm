create or replace function private.inversion_vincular_fuente(
  p_persona uuid,p_contrato uuid,p_cierre uuid,p_por uuid,p_inicial boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_empresa uuid;
  v_fecha date;
  v_estado text;
  v_identidad uuid;
  v_i crm.inversiones%rowtype;
begin
  if ((p_contrato is not null)::integer+(p_cierre is not null)::integer)<>1 then
    raise exception 'La inversión requiere exactamente una fuente económica' using errcode='22023';
  end if;
  if p_cierre is not null then
    select e.id,coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
      case when ce.anulado_en is null then 'vigente' else 'anulada' end,
      private.inversionista_canonica(ce.inversionista_id)
    into v_empresa,v_fecha,v_estado,v_identidad
    from crm.cierres_externos ce join crm.empresas e on e.clave=ce.cooperativa
    where ce.id=p_cierre for share of ce;
  else
    select e.id,c.fecha_cierre_comercial,'vigente',private.inversionista_canonica(p.id)
    into v_empresa,v_fecha,v_estado,v_identidad
    from public.contratos c join crm.inversionistas p on p.perfil_id=c.cliente_id and p.estado<>'fusionado'
    cross join crm.empresas e where c.id=p_contrato and e.clave='avance' for share of c;
  end if;
  if v_empresa is null or v_identidad is distinct from p_persona then
    raise exception 'La fuente económica no corresponde a esta persona' using errcode='P0409';
  end if;
  -- También protege una vinculación histórica: si el borrado se preparó antes
  -- de obtener el candado contractual, no añadir una relación a esa fuente.
  if p_contrato is not null and private.contrato_en_eliminacion(p_contrato) then
    raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
  end if;
  select * into v_i from crm.inversiones
  where contrato_id=p_contrato or cierre_externo_id=p_cierre for update;
  if found then
    if v_i.inversionista_id<>p_persona or v_i.empresa_id<>v_empresa then
      raise exception 'La fuente ya está vinculada a otra persona o empresa' using errcode='P0409';
    end if;
  else
    insert into crm.inversiones(inversionista_id,empresa_id,contrato_id,cierre_externo_id,
      estado,fecha_comercial,es_primera_conversion,creado_por)
    values(p_persona,v_empresa,p_contrato,p_cierre,v_estado,v_fecha,p_inicial,p_por)
    returning * into v_i;
  end if;
  if exists (select 1 from crm.inversion_titulares it
             where it.inversion_id=v_i.id and it.rol='principal' and it.inversionista_id<>p_persona) then
    raise exception 'El titular principal requiere conciliación' using errcode='P0409';
  end if;
  insert into crm.inversion_titulares(inversion_id,inversionista_id,rol,creado_por)
  select v_i.id,p_persona,'principal',p_por where not exists (
    select 1 from crm.inversion_titulares it where it.inversion_id=v_i.id and it.rol='principal');
  return v_i.id;
end;
$$;
revoke all on function private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)
  from public,anon,authenticated,service_role;

create or replace function crm.confirmar_inversion_revisada_fn(p_solicitud uuid,p_revision_datos_esperada integer)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_uid uuid := (select auth.uid());
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_e crm.empresas%rowtype;
  v_obj storage.objects%rowtype;
  v_cierre uuid;
  v_contrato uuid;
  v_inversion uuid;
  v_fecha date;
  v_imputacion date;
  v_periodo date;
  v_ahora timestamptz := statement_timestamp();
  v_ajuste boolean := false;
  v_fuente jsonb;
  v_payload_contrato jsonb;
  v_condicion uuid;
  v_config_producto text := current_setting('crm.producto_condicion_id',true);
  v_responsable_inicial uuid;
  v_res jsonb;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_origen := v_persona;
  v_ctx := private.inversion_persona_autorizada(v_persona);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado='confirmada' then
    v_res:=v_s.resultado;
    select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
    if v_contrato is not null then
      if private.contrato_en_eliminacion(v_contrato) then
        raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
      end if;
      v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
    end if;
    return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
  end if;
  if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
  if p_revision_datos_esperada is distinct from v_s.revision_datos then
    raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='40001';
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona);
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
  end if;
  select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
  if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
  if v_e.fuente_capital='cierres_externos' then
    if v_s.datos->>'moneda' is distinct from 'PEN' or not ('PEN'=any(v_e.monedas)) then
      raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
    end if;
    select * into v_obj from storage.objects
    where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
    if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
      raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
    end if;
    v_fecha := (v_s.datos->>'fecha_comercial')::date;
    v_periodo := date_trunc('month',v_fecha)::date;
    -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
    -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
    v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
    if v_ajuste then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
        (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
      if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
        raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
      end if;
    end if;
    begin
      insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
        nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
        inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id)
      values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,'PEN',
        v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
        upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
        (v_s.datos->>'vence_en')::date,(v_ctx->>'responsable_id')::uuid,v_uid,v_persona,
        v_ahora,false,v_fecha,v_imputacion,v_obj.id) returning id into v_cierre;
      -- La reclamación histórica del depósito es global para ambas cooperativas.
      insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
      values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
    exception when unique_violation then
      raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
    end;
    v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
      'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste);
  elsif v_e.clave='avance' then
    if v_ctx->>'perfil_id' is null then
      raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
    end if;
    v_payload_contrato := v_s.datos->'contrato';
    select r.responsable_anterior_id into v_responsable_inicial
      from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
    v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
    if v_payload_contrato->>'cliente_id' is not null
       and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
    end if;
    if v_payload_contrato->>'analista_cierre_id' is not null
       and v_payload_contrato->>'analista_cierre_id' is distinct from v_responsable_inicial::text then
      raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
    end if;
    -- El contenido original conserva su huella. Una revisión explícita cambia
    -- el responsable con quien se confirma, sin reescribir las condiciones.
    v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
      'analista_cierre_id',v_ctx->>'responsable_id');
    -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
    -- documental y operaciones de cartera. Todo participa de esta transacción.
    -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
    -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
    -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
    -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
    perform pg_catalog.set_config('crm.producto_condicion_id',
      coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
    begin
      v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
        v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
        v_s.datos->'cronograma',v_s.datos->'cuenta');
    exception when others then
      perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
      raise;
    end;
    perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
    v_contrato := (v_fuente->>'id')::uuid;
    if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
    select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
    v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
  else
    raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
  end if;
  v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,false);
  if v_ajuste then
    insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
    values(v_inversion,v_periodo,v_imputacion,v_uid);
  end if;
  insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
  v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
    'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
    'revision_datos',v_s.revision_datos);
  update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
    resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
  return v_res;
end;
$$;
revoke all on function crm.confirmar_inversion_revisada_fn(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function crm.confirmar_inversion_revisada_fn(uuid,integer) to authenticated;

-- Compatibilidad: una pantalla antigua sólo confirma solicitudes sin corrección.
-- Una confirmada conserva su replay de lectura con cualquier revisión enviada.
create or replace function crm.confirmar_inversion_fn(p_solicitud uuid)
returns jsonb language sql security definer set search_path='' as $$
  select crm.confirmar_inversion_revisada_fn(p_solicitud,0);
$$;
revoke all on function crm.confirmar_inversion_fn(uuid) from public,anon,authenticated,service_role;
grant execute on function crm.confirmar_inversion_fn(uuid) to authenticated;


create or replace function private.f4_comprobante_visible(p_ruta text)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia') and exists (
    select 1 from crm.inversion_solicitudes s join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    where s.datos#>>'{evidencia,ruta}'=p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
    )
  ),false);
$$;
revoke all on function private.f4_comprobante_visible(text) from public,anon,authenticated,service_role;
grant execute on function private.f4_comprobante_visible(text) to authenticated;
create policy f4_comprobante_select on storage.objects for select to authenticated
  using(bucket_id='f4-comprobantes' and private.f4_comprobante_visible(name));
-- Las políticas RESTRICTIVE impiden que una política permisiva legacy de otro
-- bucket abra accidentalmente comprobantes F4 o permita sustituir sus bytes.
create policy f4_comprobante_insert_frontera on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'f4-comprobantes' or private.f4_comprobante_autorizado(name));
create policy f4_comprobante_select_frontera on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'f4-comprobantes' or private.f4_comprobante_visible(name));
create policy f4_comprobante_update_frontera on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'f4-comprobantes') with check(bucket_id<>'f4-comprobantes');
create policy f4_comprobante_delete_frontera on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'f4-comprobantes');
