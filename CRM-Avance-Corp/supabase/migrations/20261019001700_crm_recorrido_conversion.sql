-- Primera conversión por hechos. Instala defensas; no cambia el modo ni el corte.
begin;
set local search_path='';
set local quote_all_identifiers=off;

do $$
declare r record;
begin
  for r in select * from (values
    ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)','b40dded8a923dcd02f028b24bc4de94e'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','68828d0a443160310a3fb2fd82cd7041'),
    ('crm.acceso_inversion_fn(uuid,text,jsonb)','38229cbb9fde4d9b5e23ee55ca6e6784'),
    ('private.conversion_lead_con_inversion()','0edf5180578781961aacbf0e78df242e'),
    ('private.recorrido_control_guard()','8c6f1aa57fc6057b6df165732ce1a078'),
    ('crm.recorrido_configurar_fn(text,text,integer,timestamptz)','caa939fca8a2ebe54455941fd54c7a44'),
    ('crm.recorrido_leads_fn(uuid[])','efcebfe6617167a90ff6f68c6ab6eb20')
  ) as expected(firma,huella) loop
    if to_regprocedure(r.firma) is null or md5(pg_get_functiondef(to_regprocedure(r.firma)))<>r.huella then
      raise exception 'El contrato vivo cambió: revisar % antes de instalar recorrido',r.firma;
    end if;
  end loop;
  perform private.assert_sla_nucleo();
end $$;

alter table crm.inversion_solicitudes add column recorrido_confirmado jsonb
  check (recorrido_confirmado is null or jsonb_typeof(recorrido_confirmado)='object');
comment on column crm.inversion_solicitudes.recorrido_confirmado is
  'Hechos y revisión de la regla al confirmar la primera conversión. Referencias sin PII, calculadas por trigger e inmutables. No backfill histórico.';

create function private.recorrido_exigir(p_lead uuid,p_paso text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare v_l crm.leads%rowtype;v_c crm.recorrido_control%rowtype;v_r jsonb;v_exigible boolean;
  v_tarea uuid;v_asistencia uuid;v_identidad_desde timestamptz;
begin
  -- Las operaciones de clientes existentes conservan el contexto canónico actual.
  if p_lead is null then return null;end if;
  -- Los callers conservan autorización/identidad. El lock protege hechos y
  -- ciclo sin bloquear FK que solo hacen referencia al lead. NOWAIT evita
  -- invertir esperas con rutas que llegaron por otra fila.
  select * into strict v_l from crm.leads where id=p_lead for no key update nowait;
  select * into strict v_c from crm.recorrido_control where id for share;
  if v_c.modo='exigir' and current_setting('transaction_isolation')<>'read committed' then
    raise exception 'Reintenta la operación en una transacción de lectura vigente' using errcode='55000';
  end if;
  select resultado into strict v_r from private.recorrido_evaluar(array[p_lead]);
  v_exigible:=coalesce(v_c.modo='exigir'
    and coalesce((v_r->>'ciclo_inicio')::timestamptz,v_l.creado_en)>=v_c.cohorte_desde
    and (v_r->>'aplica')::boolean,false);
  if v_exigible and not coalesce((v_r->>'habilita_conversion')::boolean,false) then
    raise exception using errcode='P0409',
      message='Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado. Revisa los pasos en la ficha del lead.',
      detail=jsonb_build_object('regla','recorrido_lead','paso',p_paso,'lead_id',p_lead,
        'ciclo_n',v_l.ciclo_actual,'pendiente',v_r->>'pendiente','revision',v_c.revision)::text;
  end if;
  -- Fotografía de LA pareja que acreditó la entrevista, no la última asistencia
  -- de otra cita del mismo lead. En observación puede quedar incompleta.
  v_tarea:=coalesce((v_r#>>'{evidencias,entrevista_tarea_id}')::uuid,
    (v_r#>>'{evidencias,asistencia_tarea_id}')::uuid);
  if v_tarea is not null then
    select resultado_actividad_id into v_asistencia from crm.tareas where id=v_tarea and lead_id=p_lead;
  end if;
  select min(creado_en) into v_identidad_desde from crm.inversionista_leads
    where lead_id=p_lead and inversionista_id=v_l.inversionista_id and rol='canonico';
  return jsonb_build_object('version',1,'lead_id',p_lead,'ciclo_n',v_l.ciclo_actual,
    'ciclo_inicio',v_r->'ciclo_inicio','modo',v_c.modo,'revision',v_c.revision,
    'cohorte_desde',v_c.cohorte_desde,'exigible',v_exigible,'estado',v_r->>'estado',
    'verificado_en',clock_timestamp(),'identidad_vinculada_en',v_identidad_desde,
    'asistencia_tarea_id',v_tarea,'asistencia_id',v_asistencia,
    'entrevista_tarea_id',v_r#>'{evidencias,entrevista_tarea_id}');
end $$;

create function private.recorrido_solicitud_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    if new.recorrido_confirmado is not null then
      raise exception 'El recorrido confirmado lo registra el servidor' using errcode='42501';end if;
    if new.lead_origen_id is not null then
      if new.estado='confirmada' then
        new.recorrido_confirmado:=private.recorrido_exigir(new.lead_origen_id,'insertar_confirmada');end if;
      if new.estado='preparada' then perform private.recorrido_exigir(new.lead_origen_id,'preparar_solicitud');end if;
    end if;
  else
    if new.recorrido_confirmado is distinct from old.recorrido_confirmado then
      raise exception 'La evidencia de conversión confirmada es inmutable' using errcode='42501';end if;
    if old.estado<>'confirmada' and new.estado='confirmada' and new.lead_origen_id is not null then
      new.recorrido_confirmado:=private.recorrido_exigir(new.lead_origen_id,'confirmar_solicitud');
    end if;
  end if;
  return new;
end $$;
create trigger trg_solicitudes_recorrido before insert or update on crm.inversion_solicitudes
  for each row execute function private.recorrido_solicitud_guard();

create function private.recorrido_insert_convertido_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_c crm.recorrido_control%rowtype;
begin
  select * into strict v_c from crm.recorrido_control where id for share;
  -- guard_tenencia ya fijó creado_en con reloj servidor. Un INSERT no puede
  -- tener una asistencia previa vinculada a su nuevo ciclo.
  if v_c.modo='exigir' and new.creado_en>=v_c.cohorte_desde then
    raise exception 'Registra primero el lead, su asistencia y entrevista; después confirma la inversión'
      using errcode='P0409';
  end if;
  return new;
end $$;
create trigger trg_leads_zzzz_recorrido_insert before insert on crm.leads
  for each row when (new.etapa='convertido') execute function private.recorrido_insert_convertido_guard();

revoke all on function private.recorrido_exigir(uuid,text),private.recorrido_solicitud_guard(),
  private.recorrido_insert_convertido_guard() from public,anon,authenticated,service_role;

-- Ajustes de revisión: corte próximo acotado y ausencia de ciclo nuevo no exime.
create or replace function private.recorrido_control_guard() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op<>'UPDATE'
    or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid)
    or current_setting('crm.recorrido_control_writer',true) is distinct from 'on' then
    raise exception 'El modo cambia solo por la puerta del recorrido' using errcode='42501';
  end if;
  if new.id is distinct from old.id or new.revision<>old.revision+1
    or (old.cohorte_desde is not null and new.cohorte_desde is distinct from old.cohorte_desde)
    or (old.cohorte_desde is null and (new.cohorte_desde<statement_timestamp()
      or new.cohorte_desde>clock_timestamp()+interval '24 hours')) then
    raise exception 'Corte inmutable o revision invalida' using errcode='23514';
  end if;
  return new;
end $$;

create or replace function crm.recorrido_configurar_fn(p_modo text,p_motivo text,p_revision integer,p_cohorte_desde timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_control crm.recorrido_control%rowtype;
  v_writer text:=coalesce(current_setting('crm.recorrido_control_writer',true),'off');
begin
  if not private.es_gerencia_crm_activa() then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_modo is null or p_modo not in ('apagado','observacion','exigir')
    or p_motivo is null or length(btrim(p_motivo)) not between 8 and 1000
    or p_revision is null or (p_cohorte_desde is not null and not isfinite(p_cohorte_desde)) then
    raise exception 'Indica modo, motivo y revision validos' using errcode='22023';
  end if;
  select * into strict v_control from crm.recorrido_control where id for update;
  if v_control.revision<>p_revision then raise exception 'El modo cambio; consulta de nuevo' using errcode='40001'; end if;
  if v_control.cohorte_desde is not null and p_cohorte_desde is not null and p_cohorte_desde<>v_control.cohorte_desde then
    raise exception 'El corte de activacion no se reinicia' using errcode='22023';
  end if;
  if v_control.cohorte_desde is null and p_cohorte_desde is not null and p_cohorte_desde<clock_timestamp() then
    raise exception 'La activacion inicial solo admite ciclos nuevos; antiguos requieren politica explicita' using errcode='22023';
  end if;
  if v_control.cohorte_desde is null and p_cohorte_desde>clock_timestamp()+interval '24 hours' then
    raise exception 'Programa la activacion dentro de las proximas 24 horas' using errcode='22023';
  end if;
  perform set_config('crm.recorrido_control_writer','on',true);
  update crm.recorrido_control set modo=p_modo, motivo=btrim(p_motivo), revision=revision+1,
    cohorte_desde=coalesce(cohorte_desde,p_cohorte_desde,case when p_modo='exigir' then clock_timestamp() end),
    actualizado_por=(select auth.uid()),actualizado_en=clock_timestamp()
    where id returning * into v_control;
  perform set_config('crm.recorrido_control_writer',v_writer,true);
  return to_jsonb(v_control)-'id';
end $$;

create or replace function crm.recorrido_leads_fn(p_lead_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_amb record;v_ids uuid[];v_filas jsonb;v_control crm.recorrido_control%rowtype;
begin
  select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,false);
  if p_lead_ids is null or cardinality(p_lead_ids)>100 then
    raise exception 'Consulta entre cero y cien leads por lote' using errcode='22023';end if;
  select array_agg(l.id) into v_ids from crm.leads l where l.id=any(p_lead_ids) and l.activo
    and (v_amb.es_global or l.vendedor_id=any(v_amb.visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id=any(v_amb.visibles)));
  select * into strict v_control from crm.recorrido_control where id;
  select coalesce(jsonb_agg(e.resultado||jsonb_build_object('exigible',coalesce(v_control.modo='exigir'
      and coalesce((e.resultado->>'ciclo_inicio')::timestamptz,l.creado_en)>=v_control.cohorte_desde
      and (e.resultado->>'aplica')::boolean,false)) order by e.lead_id),'[]'::jsonb)
    into v_filas from private.recorrido_evaluar(coalesce(v_ids,'{}'::uuid[])) e join crm.leads l on l.id=e.lead_id;
  return jsonb_build_object('version',1,'modo',v_control.modo,'revision',v_control.revision,
    'cohorte_desde',v_control.cohorte_desde,'filas',v_filas);
end $$;

-- A continuación, cuerpos vigentes íntegros con una llamada puntual al guard.

CREATE OR REPLACE FUNCTION crm.preparar_persona_lead_inversion_fn(p_lead uuid, p_tipo_documento text, p_documento text, p_nombre text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid:=(select auth.uid()); v_rol text;
  v_l crm.leads%rowtype; v_pre crm.leads%rowtype; v_i crm.inversionistas%rowtype;
  v_persona uuid; v_doc text:=upper(btrim(p_documento));
  v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode='42501';
  end if;
  if not private.resolver_en_puertas_bajo_candado() or not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro compartido de inversiones no está habilitado' using errcode='P0409';
  end if;
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_rol:=private.rol_crm(v_uid);
  select * into v_pre from crm.leads where id=p_lead and activo and
    (v_rol='gerencia' or vendedor_id in (select private.vendedor_ids_visibles(v_uid)));
  if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501'; end if;
  if length(btrim(coalesce(p_nombre,''))) not between 2 and 180
    or p_tipo_documento is null or p_tipo_documento not in ('DNI','CE','PASAPORTE')
    or v_doc is null
    or (p_tipo_documento='DNI' and v_doc !~ '^[0-9]{8}$')
    or (p_tipo_documento='CE' and v_doc !~ '^[0-9]{9,12}$')
    or (p_tipo_documento='PASAPORTE' and v_doc !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Completa el nombre y un documento válido' using errcode='22023';
  end if;
  -- La identidad no se corrige al invertir. Esa operación tiene su propia puerta.
  if nullif(btrim(v_pre.dni),'') is not null and v_pre.dni is distinct from v_doc then
    raise exception 'El documento no coincide con el lead; corrige su identidad antes de invertir' using errcode='P0409';
  end if;
  perform private.identidad_bloquear_documento(p_tipo_documento,v_doc);
  v_persona:=private.inversionista_resolver(p_tipo_documento,v_doc,true,'conversion_inversion');
  perform private.identidad_bloquear_documentos_de(array[v_persona]);
  select * into v_i from crm.inversionistas where id=v_persona for update;
  -- NOWAIT: una reasignación que tomó antes el lead no invierte el orden de locks.
  select * into v_l from crm.leads where id=p_lead for update nowait;
  if v_l.activo is not true or not coalesce((v_rol='gerencia' or
    v_l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))),false) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
  end if;
  if v_l.dni is distinct from v_pre.dni or v_l.inversionista_id is distinct from v_pre.inversionista_id then
    raise exception 'La identidad del lead cambió; vuelve a cargarlo' using errcode='PT409';
  end if;
  -- También recupera una confirmación cuyo HTTP se perdió: no se vuelve a
  -- preparar ni se modifica la persona o el lead ya convertido.
  if v_l.etapa='convertido' and v_l.inversionista_id=v_persona and exists(
    select 1 from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada') then
    perform private.inversion_persona_autorizada(v_persona);
    return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
      'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada'));
  end if;
  if v_l.etapa in ('convertido','descartado') then
    raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
  end if;
  -- Retomar es lectura: conserva borradores desde otra sesión/dispositivo.
  -- El contexto vigente sigue verificando actor, identidad y ámbito. Crear
  -- acceso o confirmar vuelven a comprobar los hechos en sus propias puertas.
  if v_l.inversionista_id=v_persona and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=p_lead and inversionista_id=v_persona and estado='preparada') then
    perform private.inversion_persona_contexto(v_persona,p_lead);
    return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
      'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead
        and inversionista_id=v_persona and estado='preparada'));
  end if;
  perform private.recorrido_exigir(p_lead,'preparar_identidad');
  if v_i.estado<>'activo' or v_i.no_contactar then
    raise exception 'La persona no permite nuevas inversiones' using errcode='P0429';
  end if;
  if v_l.no_contactar then raise exception 'El lead tiene No insistir' using errcode='P0429'; end if;
  if v_l.vendedor_id is null or not exists(select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=v_l.vendedor_id and e.activo and p.activo and e.rol_crm in ('vendedor','supervisor')) then
    raise exception 'Asigna el lead a un analista activo antes de invertir' using errcode='P0409';
  end if;
  if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
    or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
      and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
    or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
    or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead) then
    raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
  end if;
  if v_i.responsable_relacion_id is not null and v_i.responsable_relacion_id<>v_l.vendedor_id then
    raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
  end if;
  if exists(select 1 from crm.conversion_reservas r where
    (r.lead_id=p_lead or r.inversionista_id=v_persona) and
    (r.efectos_iniciados_en is not null or r.expira_en>now()) for update) then
    raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de iniciar otra solicitud' using errcode='P0409';
  end if;
  if v_i.responsable_relacion_id is null then
    if exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null) then
      raise exception 'La asignación de la persona requiere conciliación' using errcode='P0409';
    end if;
    insert into crm.inversionista_responsables(inversionista_id,responsable_id,motivo,por)
      values(v_persona,v_l.vendedor_id,'preparar_conversion_inversion',v_uid);
    update crm.inversionistas set responsable_relacion_id=v_l.vendedor_id where id=v_persona;
  end if;
  perform set_config('crm.op_privilegiada','on',true);
  update crm.leads set inversionista_id=v_persona,nombre_completo=btrim(p_nombre),
    dni=case when p_tipo_documento='DNI' then v_doc else dni end where id=p_lead;
  perform set_config('crm.op_privilegiada',v_config,true);
  -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
  perform private.inversion_persona_contexto(v_persona,p_lead);
  return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
    'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead
      and estado in ('preparada','confirmada')));
end $function$;


CREATE OR REPLACE FUNCTION crm.confirmar_inversion_revisada_fn(p_solicitud uuid, p_revision_datos_esperada integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

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
  v_config_conversion text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_origen := v_persona;
  v_ctx := private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='PT409';
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
    raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='PT409';
  end if;
  v_ctx := private.inversion_persona_contexto_para(v_persona,v_s.lead_origen_id,p_solicitud,null::uuid);
  -- Confirmadas devolvieron arriba su recibo. Antes de cualquier hecho financiero,
  -- lectura nueva bajo los candados existentes; no confía en el borrador.
  perform private.recorrido_exigir(v_s.lead_origen_id,'confirmar_inversion');
  if v_s.puerta='cliente_existente' then
    -- Venta cruzada: la venta es del analista congelado y no depende del responsable (D7),
    -- pero ese analista tiene que seguir activo para cerrarla.
    if not coalesce(private.rol_crm(v_s.analista_cierre_id) in ('vendedor','supervisor'),false) then
      raise exception 'El analista de esta venta ya no está activo como vendedor o supervisor; cancela la solicitud y regístrala de nuevo' using errcode='P0409';
    end if;
    v_ctx := v_ctx||jsonb_build_object('analista_cierre_id',v_s.analista_cierre_id,'puerta',v_s.puerta);
  elsif v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
  end if;
  select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
  if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
  if v_e.fuente_capital='cierres_externos' then
    -- Se revalida contra el catálogo VIVO: una solicitud preparada cuando la
    -- cooperativa admitía una moneda no se confirma si entretanto se retiró.
    -- `coalesce` por el mismo motivo que en private.inversion_validar_datos.
    if v_s.datos->>'moneda' is null
       or not (v_s.datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
    end if;
    -- Revalida el contenido guardado, también al retomar una solicitud anterior.
    perform private.inversion_validar_datos(v_s.id,v_s.datos,v_ctx);
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
        inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,
        plazo_meses,tasa_anual)
      values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,v_s.datos->>'moneda',
        v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
        upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
        (v_s.datos->>'vence_en')::date,coalesce(v_s.analista_cierre_id,(v_ctx->>'responsable_id')::uuid),v_uid,v_persona,
        v_ahora,v_s.lead_origen_id is not null,v_fecha,v_imputacion,v_obj.id,
        (v_s.datos->>'plazo_meses')::integer,(v_s.datos->>'tasa_anual')::numeric) returning id into v_cierre;
      -- La reclamación histórica del depósito es global para ambas cooperativas.
      insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
      values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
    exception when unique_violation then
      raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
    end;
    v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
      'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste,
      'plazo_meses',(v_s.datos->>'plazo_meses')::integer,'tasa_anual',(v_s.datos->>'tasa_anual')::numeric,
      'vence_en',(v_s.datos->>'vence_en')::date);
  elsif v_e.clave='avance' then
    if v_ctx->>'perfil_id' is null then
      raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
    end if;
    v_payload_contrato := v_s.datos->'contrato';
    if v_s.puerta='cliente_existente' and coalesce(v_payload_contrato->>'categoria','nuevo') not in ('nuevo','upgrade') then
      raise exception 'La venta cruzada registra una inversión nueva o un upgrade; la renovación es del responsable' using errcode='22023';
    end if;
    if v_s.lead_origen_id is not null then
      if coalesce(v_payload_contrato->>'categoria','nuevo')<>'nuevo' then
        raise exception 'La conversión inicial registra una inversión nueva' using errcode='22023';
      end if;
      perform private.validar_tasa_conversion_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid,v_payload_contrato);
      perform private.enlazar_tasa_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid);
    end if;
    select r.responsable_anterior_id into v_responsable_inicial
      from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
    v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
    if v_payload_contrato->>'cliente_id' is not null
       and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
    end if;
    if v_payload_contrato->>'analista_cierre_id' is not null
       and v_payload_contrato->>'analista_cierre_id' is distinct from coalesce(v_s.analista_cierre_id,v_responsable_inicial)::text then
      raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
    end if;
    -- El contenido original conserva su huella. Una revisión explícita cambia
    -- el responsable con quien se confirma, sin reescribir las condiciones.
    v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
      'analista_cierre_id',coalesce(v_s.analista_cierre_id::text,v_ctx->>'responsable_id'));
    -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
    -- documental y operaciones de cartera. Todo participa de esta transacción.
    -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
    -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
    -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
    -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
    perform pg_catalog.set_config('crm.producto_condicion_id',
      coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
    -- Venta cruzada: el alta Avance puede crear el PDF de ESTE contrato aunque el cliente
    -- no sea de la cartera de quien confirma (private.venta_cruzada_confirma_contrato).
    perform pg_catalog.set_config('crm.venta_cruzada_solicitud',case when v_s.puerta='cliente_existente' then v_s.id::text else '' end,true);
    begin
      v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
        v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
        v_s.datos->'cronograma',v_s.datos->'cuenta');
    exception when others then
      perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
      perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
      raise;
    end;
    perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
    perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
    v_contrato := (v_fuente->>'id')::uuid;
    if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
    select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
    v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
  else
    raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
  end if;
  v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,v_s.lead_origen_id is not null);
  if v_ajuste then
    insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
    values(v_inversion,v_periodo,v_imputacion,v_uid);
  end if;
  insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
  v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
    'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
    'revision_datos',v_s.revision_datos);
  if v_s.puerta='cliente_existente' then
    v_res := v_res||jsonb_build_object('puerta',v_s.puerta,'analista_cierre_id',v_s.analista_cierre_id);
  end if;
  update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
    resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
  if v_s.lead_origen_id is not null then
    -- El escritor contractual puede haber enlazado ya su fuente; se reconoce
    -- ESTA inversión como inicial, conservando un único hecho y titular.
    update crm.inversiones set es_primera_conversion=true where id=v_inversion;
    perform set_config('crm.op_privilegiada','on',true);
    update crm.leads set etapa='convertido',convertido_en=statement_timestamp(),
      perfil_id=case when v_e.clave='avance' then (v_ctx->>'perfil_id')::uuid else perfil_id end,
      contrato_id=coalesce(v_contrato,contrato_id)
      where id=v_s.lead_origen_id;
    perform set_config('crm.op_privilegiada',v_config_conversion,true);
    insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
      values(v_s.lead_origen_id,'conversion','Convertido al confirmar su inversión',
        jsonb_build_object('solicitud_id',v_s.id,'inversion_id',v_inversion,'empresa',v_e.clave,
          'contrato_id',v_contrato,'cierre_externo_id',v_cierre),v_uid);
    if v_e.clave='avance' and v_s.auth_claim_id is not null then
      update crm.inversion_solicitudes set bienvenida=jsonb_build_object(
        'estado','pendiente','correo',v_s.datos->'alta_portal'->>'correo',
        'nombre',v_s.datos->'alta_portal'->>'nombre_completo') where id=v_s.id;
    end if;
  end if;
  return v_res;
end;

exception when serialization_failure or lock_not_available then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;


CREATE OR REPLACE FUNCTION crm.acceso_inversion_fn(p_solicitud uuid, p_paso text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_datos jsonb;
  v_auth_ctx jsonb;
  v_hash_payload jsonb;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_r jsonb;
  v_p public.perfiles%rowtype;
  v_auth uuid;
  v_version integer;
  v_token text;
  v_otras uuid[];
begin
  if p_solicitud is null or p_paso is null or p_paso not in ('reclamar','registrar_auth','crear_perfil','enlazar')
     or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'Solicitud o paso de acceso Avance inválido' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_payload) k where
    k<>'token' and not (p_paso<>'reclamar' and k='version')
    and not (p_paso='registrar_auth' and k='auth_user_id')) then
    raise exception 'El paso de acceso contiene campos no admitidos' using errcode='22023';
  end if;
  v_token:=p_payload->>'token';
  if v_token is not null and v_token !~ '^[a-f0-9]{48}$' then
    raise exception 'Token de recuperación inválido' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  perform private.venta_cruzada_exigir_operador(p_solicitud);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'confirmada' then
    v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
  end if;
  if not exists(select 1 from crm.empresas e where e.id=v_s.empresa_id and e.clave='avance' and e.activa)
     or v_s.estado='cancelada' then
    raise exception 'Esta solicitud no permite completar acceso Avance' using errcode='P0409';
  end if;
  if v_s.estado='preparada' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; corresponde revisar esta solicitud antes de continuar' using errcode='P0409';
  end if;

  -- Un claim terminal conserva su clave de origen después de una fusión.
  -- Los contextos anteriores a esta ampliación usaban la persona de la solicitud.
  select * into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
    case when v_s.auth_claim_id is null then v_persona::text
      else coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text) end;
  if v_s.auth_claim_id is not null and
    (v_saga.clave is null or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text) then
    raise exception 'El proceso de acceso original requiere conciliación' using errcode='P0409';
  end if;
  -- Un enlace concluido se devuelve aunque se perdiera su respuesta. No reinicia
  -- Auth ni reescribe el perfil, su clave o su responsable.
  if v_ctx->>'perfil_id' is not null and
     (v_saga.clave is null or v_saga.resultado->>'estado'='enlazado') then
    if v_saga.clave is not null and v_saga.resultado->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El acceso y la identidad requieren conciliación' using errcode='P0409';
    end if;
    return jsonb_build_object('estado','enlazado','perfil_id',v_ctx->>'perfil_id',
      'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
  end if;
  if v_s.estado='confirmada' then
    raise exception 'El acceso de la inversión confirmada requiere conciliación' using errcode='P0409';
  end if;
  v_datos:=private.inversion_datos_portal(v_s.datos->'alta_portal');
  v_auth_ctx:=coalesce(v_s.auth_contexto,jsonb_build_object('documento_tipo',v_ctx->>'documento_tipo',
    'documento',v_ctx->>'documento','responsable_id',v_ctx->>'responsable_id','inversionista_id',v_persona));
  if v_auth_ctx->>'documento_tipo' is distinct from v_ctx->>'documento_tipo'
     or v_auth_ctx->>'documento' is distinct from v_ctx->>'documento' then
    raise exception 'El documento cambió durante el alta; corresponde revisar el acceso pendiente' using errcode='P0409';
  end if;
  -- Misma proyección que alta_cliente_identidad_fn; los bancos pertenecen a la
  -- cuenta contractual de esta inversión. El responsable inicial fija la huella.
  v_hash_payload:=private.inversion_payload_acceso(v_persona,v_s.datos->'alta_portal',v_auth_ctx->>'responsable_id');

  if p_paso='reclamar' then
    -- Cubre solicitudes anteriores al arreglo e importaciones sin actor. No
    -- cambia una credencial que Auth ya creó aunque se perdiera la respuesta.
    if v_s.lead_origen_id is not null and exists(select 1 from crm.leads l where l.id=v_s.lead_origen_id
      and private.inversion_correo_normalizado(l.correo) is distinct from private.inversion_correo_normalizado(v_datos->>'correo'))
      and v_saga.resultado->>'auth_insertado_id' is null
      and v_saga.resultado->>'auth_user_id' is null
      and not exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
      raise exception 'El correo de la ficha cambió; revisa los datos de acceso antes de continuar' using errcode='P0409';
    end if;
    -- Una segunda solicitud no sustituye un alta pendiente de esta persona.
    -- Incluso "reclamado" puede tener Auth creado con respuesta perdida.
    if v_saga.clave is not null and v_saga.resultado->>'estado'<>'enlazado' then
      if exists(select 1 from crm.inversion_solicitudes s where s.id<>v_s.id
        and s.auth_claim_id=(v_saga.resultado->>'claim_id')::uuid) then
        raise exception 'Completa el acceso pendiente desde su solicitud original' using errcode='P0409';
      end if;
      if v_saga.hash_payload is distinct from private.idem_hash(v_hash_payload) then
        raise exception 'La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales' using errcode='P0409';
      end if;
    end if;
    if v_saga.clave is null then
      select array_agg(p.id order by p.id) into v_otras from public.perfiles p
      where p.rol='cliente' and p.tipo_documento=v_ctx->>'documento_tipo'
        and upper(regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g'))=v_ctx->>'documento';
      if coalesce(cardinality(v_otras),0)>1 then
        raise exception 'Hay varios perfiles con ese documento; requiere conciliación' using errcode='P0409';
      elsif cardinality(v_otras)=1 then
        perform private.asegurar_identidad_perfil(v_otras[1],'f4_acceso_portal');
        v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
        if v_ctx->>'perfil_id' is distinct from v_otras[1]::text then
          raise exception 'El perfil existente no pertenece a esta persona' using errcode='P0409';
        end if;
        return jsonb_build_object('estado','enlazado','perfil_id',v_otras[1],
          'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
      end if;
    end if;
    -- Un claim sin efecto externo no exime. Un Auth ya creado con la marca
    -- de ESTA solicitud se recupera sin repetir el alta; confirmar revalida.
    if v_s.lead_origen_id is not null and not exists(
      select 1 from auth.users u where v_s.auth_claim_id is not null
        and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
        and lower(u.email)=v_datos->>'correo') then
      perform private.recorrido_exigir(v_s.lead_origen_id,'crear_acceso');
    end if;
    v_r:=private.saga_auth_reclamar(v_persona,'alta_cliente',v_hash_payload,null,v_token);
    if v_r->>'estado'='enlazado' and (v_ctx->>'perfil_id' is null
       or v_r->>'perfil_id' is distinct from v_ctx->>'perfil_id') then
      raise exception 'El perfil del acceso requiere conciliación con esta persona' using errcode='P0409';
    end if;
    if v_s.auth_claim_id is not null and v_s.auth_claim_id is distinct from (v_r->>'claim_id')::uuid then
      raise exception 'El proceso de acceso cambió; requiere revisión' using errcode='P0409';
    end if;
    -- El formulario guarda su token ANTES del primer envío. La saga general
    -- emite otro token; aquí conservamos el ya conocido para poder recuperar
    -- también una respuesta perdida del primer reclamo (sin esperar el lease).
    -- saga_auth_reclamar ya verificó el token vigente al retomar. No se altera
    -- el claim, su versión, su dueño ni su huella; las otras puertas no cambian.
    if v_token is not null and v_r->>'estado'<>'enlazado' then
      update crm.multiempresa_idempotencia set resultado=jsonb_set(resultado,'{token_hash}',
        to_jsonb(private.saga_token_hash(v_token)))
        where clave='auth_persona:'||(v_r->>'inversionista_id') and resultado->>'claim_id'=v_r->>'claim_id';
      if not found then
        raise exception 'El proceso de acceso cambió; recupera la solicitud' using errcode='40001';
      end if;
      v_r:=jsonb_set(v_r,'{token}',to_jsonb(v_token));
    end if;
    update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,
      auth_contexto=v_auth_ctx,actualizado_en=statement_timestamp() where id=v_s.id;
    return v_r||jsonb_build_object('solicitud_id',v_s.id,'datos_portal',v_datos,
      'documento_tipo',v_auth_ctx->>'documento_tipo','documento',v_auth_ctx->>'documento');
  end if;

  if v_s.auth_claim_id is null or v_saga.clave is null
     or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text then
    raise exception 'Primero reclama el acceso desde esta solicitud' using errcode='P0409';
  end if;
  -- El perfil y el avance de estado se confirman juntos. Una versión antigua
  -- no puede dejar un perfil insertado ni enlazarlo por fuera de su claim.
  select * into v_saga from crm.multiempresa_idempotencia where clave=v_saga.clave for update;
  if v_token is null or v_saga.resultado->>'token_hash' is distinct from private.saga_token_hash(v_token) then
    raise exception 'Token de recuperación inválido' using errcode='42501';
  end if;
  begin v_version:=(p_payload->>'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Versión del acceso inválida' using errcode='22023';
  end;
  if v_version is null or v_saga.version is distinct from v_version then
    raise exception 'El acceso cambió; vuelve a reclamar con tu token' using errcode='40001';
  end if;
  if p_paso='registrar_auth' then
    begin v_auth:=(p_payload->>'auth_user_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de acceso inválido' using errcode='22023';
    end;
  else
    v_auth:=(v_saga.resultado->>'auth_user_id')::uuid;
  end if;
  if not exists(select 1 from auth.users u where u.id=v_auth
    and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
    and lower(u.email)=v_datos->>'correo') then
    raise exception 'El acceso no pertenece a esta solicitud o a su correo' using errcode='P0409';
  end if;
  if p_paso='registrar_auth' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'auth_creado',v_auth,null,v_version);
  end if;
  if v_saga.resultado->>'estado' not in ('auth_creado','perfil_creado') then
    raise exception 'El estado del acceso no permite este paso' using errcode='P0409';
  end if;
  select * into v_p from public.perfiles where id=v_auth for update;
  if not found and p_paso='crear_perfil' then
    insert into public.perfiles(id,rol,activo,nombre_completo,apellidos,nombres,tipo_documento,dni,
      correo,telefono,domicilio,asesor_perfil_id,creado_por,debe_cambiar_password)
    values(v_auth,'cliente',true,v_datos->>'nombre_completo',v_datos->>'apellidos',v_datos->>'nombres',
      v_auth_ctx->>'documento_tipo',v_auth_ctx->>'documento',v_datos->>'correo',v_datos->>'telefono',
      v_datos->>'domicilio',(v_ctx->>'responsable_id')::uuid,(select auth.uid()),true)
    returning * into v_p;
  end if;
  if v_p.id is null or v_p.rol<>'cliente' or v_p.activo is not true
     or v_p.tipo_documento is distinct from v_auth_ctx->>'documento_tipo'
     or v_p.dni is distinct from v_auth_ctx->>'documento'
     or lower(v_p.correo) is distinct from v_datos->>'correo'
     or v_p.asesor_perfil_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El perfil pendiente requiere conciliación con esta persona y su responsable' using errcode='P0409';
  end if;
  if p_paso='crear_perfil' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'perfil_creado',null,v_auth,v_version);
  end if;
  v_r:=private.asegurar_identidad_perfil(v_auth,'f4_acceso_portal');
  if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from v_persona then
    raise exception 'El perfil no corresponde a la persona de la inversión' using errcode='P0409';
  end if;
  return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'enlazado',null,v_auth,v_version)
    ||jsonb_build_object('solicitud_id',v_s.id);
end;
$function$;


CREATE OR REPLACE FUNCTION private.conversion_lead_con_inversion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.etapa='convertido' and old.etapa<>'convertido' then
    if exists(select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada') then
      raise exception 'Confirma la solicitud de inversión antes de convertir el lead' using errcode='P0409';
    end if;
    if not exists(select 1 from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
      where s.lead_origen_id=new.id and s.estado='confirmada'
        and i.inversionista_id=new.inversionista_id and i.es_primera_conversion and i.estado='vigente') then
      raise exception 'Registra y confirma la inversión desde el formulario compartido antes de convertir' using errcode='P0409';
    end if;
    -- Última defensa también para writers internos; conserva la comprobación
    -- anterior de solicitud confirmada e inversión inicial vigente.
    perform private.recorrido_exigir(new.id,'convertir_lead');
  end if;
  return new;
end $function$;


notify pgrst,'reload schema';
commit;
