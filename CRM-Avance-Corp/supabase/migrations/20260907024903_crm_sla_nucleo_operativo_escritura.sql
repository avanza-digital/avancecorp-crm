-- SLA-R2 N2: comandos gobernados, configuracion, contexto causal y prorrogas.
-- Instalacion compatible: no publica politica, reconstruye stock ni activa modo.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
declare v record;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('private.trg_actividades_avance_etapa()','6b6fba1240e2d6e47bcf3c52e667770e'),
    ('private.trg_tareas_before_insert()','253bb296466a485de9c15680d4e52f6f'),
    ('crm.publicar_politica_sla(integer,timestamp with time zone,jsonb)','01ef37ba4638fbf46851bc4639d9d612')
  ) d(firma,huella) loop
    if md5(pg_get_functiondef(v.firma::regprocedure))<>v.huella then
      raise exception 'SLA N2: fuente cambio %, reconciliar antes de instalar',v.firma;
    end if;
  end loop;
end;
$preflight$;

create function private.sla_reglas_operacion_validas(p_reglas jsonb)
returns boolean language plpgsql immutable security invoker set search_path=''
as $function$
declare r jsonb;k text;n numeric;v_etapas text[]:='{}';
begin
  if jsonb_typeof(p_reglas) is distinct from 'array' then return false;end if;
  if jsonb_array_length(p_reglas)<>4 then return false;end if;
  for r in select value from jsonb_array_elements(p_reglas) loop
    if jsonb_typeof(r) is distinct from 'object'
       or not(r ?& array['etapa','seguimiento_minutos','prorroga_minutos','prorroga_max',
         'tope_extra_minutos','pausa_habilitada','pausa_margen_minutos'])
       or (r-array['etapa','seguimiento_minutos','prorroga_minutos','prorroga_max',
         'tope_extra_minutos','pausa_habilitada','pausa_margen_minutos'])<>'{}'::jsonb
       or jsonb_typeof(r->'etapa') is distinct from 'string'
       or r->>'etapa' not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
       or (r->>'etapa')=any(v_etapas)
       or jsonb_typeof(r->'pausa_habilitada') is distinct from 'boolean' then return false;end if;
    v_etapas:=array_append(v_etapas,r->>'etapa');
    foreach k in array array['seguimiento_minutos','prorroga_minutos','prorroga_max',
      'tope_extra_minutos','pausa_margen_minutos'] loop
      if jsonb_typeof(r->k) is distinct from 'number' then return false;end if;
      n:=(r->>k)::numeric;
      if n<>trunc(n) or n<0 or n>43200 then return false;end if;
    end loop;
    if (r->>'seguimiento_minutos')::integer<1
      or ((r->>'prorroga_minutos')::integer between 1 and 1440)
      or (r->>'prorroga_max')::integer>5
      or (r->>'pausa_margen_minutos')::integer>10080
      or (((r->>'prorroga_minutos')::integer=0)<>((r->>'prorroga_max')::integer=0))
      or ((r->>'prorroga_max')::integer>0 and (r->>'tope_extra_minutos')::integer=0)
      or (r->>'etapa' in ('nuevo','reunion_agendada') and (r->>'prorroga_max')::integer<>0)
      or (not (r->>'pausa_habilitada')::boolean and (r->>'pausa_margen_minutos')::integer<>0)
    then return false;end if;
  end loop;
  return true;
end;
$function$;
revoke all on function private.sla_reglas_operacion_validas(jsonb) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.sla_publicar_politica_core(p_expected_version integer, p_vigente_desde timestamp with time zone, p_config jsonb, p_operacion jsonb)
 RETURNS SETOF crm.sla_politicas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_actual integer;
  v_anterior uuid;
  v_ultimo_desde timestamptz;
  v_desde timestamptz := coalesce(p_vigente_desde,statement_timestamp());
  v_id uuid;
  v_gestion numeric;
  v_contacto numeric;
  v_regla record;
  v_etapa text;
  v_maximo numeric;
  v_operacion jsonb := p_operacion;
  v_config_previo text := coalesce(current_setting('crm.sla_config_writer',true),'off');
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede publicar politicas SLA' using errcode='42501';
  end if;
  if p_expected_version is null or p_expected_version<1 then
    raise exception 'expected_version invalido' using errcode='22023';
  end if;
  if p_config is null or jsonb_typeof(p_config)<>'object'
    or not (p_config ?& array['zona_horaria','tipo_reloj','primera_gestion_minutos','primer_contacto_minutos','etapas'])
    or (p_config-array['zona_horaria','tipo_reloj','primera_gestion_minutos','primer_contacto_minutos','etapas'])<>'{}'::jsonb
    or jsonb_typeof(p_config->'zona_horaria') is distinct from 'string'
    or jsonb_typeof(p_config->'tipo_reloj') is distinct from 'string'
    or jsonb_typeof(p_config->'primera_gestion_minutos') is distinct from 'number'
    or jsonb_typeof(p_config->'primer_contacto_minutos') is distinct from 'number'
    or jsonb_typeof(p_config->'etapas') is distinct from 'array'
    or jsonb_array_length(p_config->'etapas')<>4 then
    raise exception 'Formato SLA invalido' using errcode='22023';
  end if;
  if p_config->>'zona_horaria'<>'America/Lima' or p_config->>'tipo_reloj'<>'corrido' then
    raise exception 'Solo America/Lima y reloj corrido' using errcode='22023';
  end if;
  v_gestion := (p_config->>'primera_gestion_minutos')::numeric;
  v_contacto := (p_config->>'primer_contacto_minutos')::numeric;
  if trunc(v_gestion)<>v_gestion or trunc(v_contacto)<>v_contacto
    or v_gestion<1 or v_gestion>43200
    or v_contacto<v_gestion or v_contacto>43200 then
    raise exception 'Plazos SLA fuera de rango' using errcode='22023';
  end if;
  if not isfinite(v_desde) or v_desde<statement_timestamp() then
    raise exception 'La vigencia debe iniciar ahora o en el futuro' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.sla_politicas'),1);
  select p.id,p.version,p.vigente_desde into v_anterior,v_actual,v_ultimo_desde
  from crm.sla_politicas p order by p.version desc limit 1;
  if p_expected_version<>v_actual then
    raise exception 'Conflicto de version SLA: esperada %, vigente %',p_expected_version,v_actual
      using errcode='P0409';
  end if;
  if v_desde<=v_ultimo_desde then
    raise exception 'La vigencia debe ser posterior a la ultima politica' using errcode='22023';
  end if;

  if v_operacion is null then
    select jsonb_agg(to_jsonb(r)-'politica_id' order by r.etapa) into v_operacion
    from crm.sla_politica_etapas_operacion r where r.politica_id=v_anterior;
  end if;
  if v_operacion is not null and not private.sla_reglas_operacion_validas(v_operacion) then
    raise exception 'Reglas operativas SLA incompletas o invalidas' using errcode='22023';
  end if;
  if v_operacion is null and exists(select 1 from crm.sla_operacion_control where primera_activacion_en is not null) then
    raise exception 'Una politica posterior a la activacion requiere anexo operativo' using errcode='22023';
  end if;
  perform set_config('crm.sla_config_writer','on',true);

  insert into crm.sla_politicas(
    version,version_anterior_id,vigente_desde,zona_horaria,tipo_reloj,
    primera_gestion_minutos,primer_contacto_minutos,publicada_por
  ) values (v_actual+1,v_anterior,v_desde,'America/Lima','corrido',
    v_gestion::integer,v_contacto::integer,v_uid) returning id into v_id;

  for v_regla in select value from jsonb_array_elements(p_config->'etapas') loop
    if jsonb_typeof(v_regla.value)<>'object'
      or not (v_regla.value ?& array['etapa','maximo_minutos'])
      or (v_regla.value-array['etapa','maximo_minutos'])<>'{}'::jsonb
      or jsonb_typeof(v_regla.value->'etapa') is distinct from 'string'
      or jsonb_typeof(v_regla.value->'maximo_minutos') is distinct from 'number' then
      raise exception 'Regla SLA invalida' using errcode='22023';
    end if;
    v_etapa:=v_regla.value->>'etapa'; v_maximo:=(v_regla.value->>'maximo_minutos')::numeric;
    if v_etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
      or trunc(v_maximo)<>v_maximo or v_maximo<1 or v_maximo>43200 then
      raise exception 'Regla SLA fuera de rango' using errcode='22023';
    end if;
    begin
      insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
      values(v_id,v_etapa,v_maximo::integer);
    exception when unique_violation then
      raise exception 'Etapa SLA repetida: %',v_etapa using errcode='22023';
    end;
  end loop;
  if v_operacion is not null then
    insert into crm.sla_politica_etapas_operacion
    select v_id,r.* from jsonb_to_recordset(v_operacion) as r(etapa text,
      seguimiento_minutos integer,prorroga_minutos integer,prorroga_max integer,
      tope_extra_minutos integer,pausa_habilitada boolean,pausa_margen_minutos integer);
  end if;
  perform set_config('crm.sla_config_writer',v_config_previo,true);
  return query select p.* from crm.sla_politicas p where p.id=v_id;
end;
$function$;

revoke all on function private.sla_publicar_politica_core(integer,timestamptz,jsonb,jsonb) from public,anon,authenticated,service_role;

-- Las puertas v1 y v2 comparten la publicacion atomica y el mismo lock.
create or replace function crm.publicar_politica_sla(p_expected_version integer,
  p_vigente_desde timestamptz,p_config jsonb)
returns setof crm.sla_politicas language sql security definer set search_path=''
as $function$
  select * from private.sla_publicar_politica_core(p_expected_version,p_vigente_desde,p_config,null);
$function$;
revoke all on function crm.publicar_politica_sla(integer,timestamptz,jsonb) from public,anon,authenticated,service_role;
grant execute on function crm.publicar_politica_sla(integer,timestamptz,jsonb) to authenticated;

create function private.sla_politica_payload(p_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $function$
  select jsonb_build_object('base',jsonb_build_object(
    'id',p.id,'version',p.version,'version_anterior_id',p.version_anterior_id,
    'vigente_desde',p.vigente_desde,'zona_horaria',p.zona_horaria,'tipo_reloj',p.tipo_reloj,
    'primera_gestion_minutos',p.primera_gestion_minutos,'primer_contacto_minutos',p.primer_contacto_minutos,
    'publicada_por',p.publicada_por,'publicada_por_nombre',perfil.nombre_completo,'publicada_en',p.publicada_en,
    'etapas',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'maximo_minutos',e.maximo_minutos)
      order by array_position(array['nuevo','contactado','reunion_agendada','propuesta_enviada'],e.etapa))
      from crm.sla_politica_etapas e where e.politica_id=p.id)),
    'operacion',(select jsonb_agg(to_jsonb(r)-'politica_id'
      order by array_position(array['nuevo','contactado','reunion_agendada','propuesta_enviada'],r.etapa))
      from crm.sla_politica_etapas_operacion r where r.politica_id=p.id))
  from crm.sla_politicas p left join public.perfiles perfil on perfil.id=p.publicada_por where p.id=p_id;
$function$;
revoke all on function private.sla_politica_payload(uuid) from public,anon,authenticated,service_role;

create function crm.publicar_politica_sla_v2(p_expected_version integer,
  p_vigente_desde timestamptz,p_config jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_base jsonb;v_operacion jsonb;v_publicada crm.sla_politicas%rowtype;r jsonb;
begin
  if auth.uid() is null or private.rol_crm(auth.uid()) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede publicar politicas SLA' using errcode='42501';
  end if;
  if jsonb_typeof(p_config) is distinct from 'object' then
    raise exception 'Formato SLA invalido' using errcode='22023';end if;
  if jsonb_typeof(p_config->'etapas') is distinct from 'array' then
    raise exception 'Formato de etapas SLA invalido' using errcode='22023';end if;
  v_base:=p_config;v_operacion:='[]';
  for r in select value from jsonb_array_elements(p_config->'etapas') loop
    if jsonb_typeof(r) is distinct from 'object' or not(r ?& array['etapa','maximo_minutos',
      'seguimiento_minutos','prorroga_minutos','prorroga_max','tope_extra_minutos','pausa_habilitada','pausa_margen_minutos'])
      or (r-array['etapa','maximo_minutos','seguimiento_minutos','prorroga_minutos','prorroga_max',
        'tope_extra_minutos','pausa_habilitada','pausa_margen_minutos'])<>'{}'::jsonb then
      raise exception 'Regla operativa SLA invalida' using errcode='22023';end if;
    v_operacion:=v_operacion||jsonb_build_array(r-'maximo_minutos');
  end loop;
  select jsonb_set(v_base,'{etapas}',coalesce(jsonb_agg(jsonb_build_object(
    'etapa',x.value->'etapa','maximo_minutos',x.value->'maximo_minutos')),'[]'::jsonb)) into v_base
  from jsonb_array_elements(p_config->'etapas') x(value);
  select * into strict v_publicada from private.sla_publicar_politica_core(
    p_expected_version,p_vigente_desde,v_base,v_operacion);
  return jsonb_build_object('version',2,'politica',private.sla_politica_payload(v_publicada.id),
    'expected_version',v_publicada.version);
end;
$function$;
revoke all on function crm.publicar_politica_sla_v2(integer,timestamptz,jsonb) from public,anon,authenticated,service_role;
grant execute on function crm.publicar_politica_sla_v2(integer,timestamptz,jsonb) to authenticated;

-- Proveedor unico de la decision comercial aprobada. La interfaz recibe este
-- mismo documento y no replica constantes ni fabrica una politica.
create function private.sla_config_inicial_aprobada(p_politica_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $function$
  select jsonb_build_object('zona_horaria','America/Lima','tipo_reloj','corrido',
    'primera_gestion_minutos',p.primera_gestion_minutos,'primer_contacto_minutos',p.primer_contacto_minutos,
    'etapas',(select jsonb_agg(jsonb_build_object('etapa',r.etapa,'maximo_minutos',r.maximo_minutos,
      'seguimiento_minutos',r.seguimiento_minutos,'prorroga_minutos',r.prorroga_minutos,
      'prorroga_max',r.prorroga_max,'tope_extra_minutos',r.tope_extra_minutos,
      'pausa_habilitada',true,'pausa_margen_minutos',r.pausa_margen_minutos) order by r.orden)
      from (values
        (1,'nuevo',1440,1440,0,0,2880,240),
        (2,'contactado',11520,4320,5760,2,11520,1440),
        (3,'reunion_agendada',21600,4320,0,0,4320,2880),
        (4,'propuesta_enviada',28800,7200,10080,1,10080,1440)
      ) r(orden,etapa,maximo_minutos,seguimiento_minutos,prorroga_minutos,prorroga_max,tope_extra_minutos,pausa_margen_minutos)))
  from crm.sla_politicas p where p.id=p_politica_id;
$function$;
revoke all on function private.sla_config_inicial_aprobada(uuid) from public,anon,authenticated,service_role;

create function crm.publicar_reglas_sla_aprobadas_v2(p_expected_version integer)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s'
as $function$
declare v_ultima crm.sla_politicas%rowtype;v_vigente uuid;
begin
  if auth.uid() is null or private.rol_crm(auth.uid()) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede publicar politicas SLA' using errcode='42501';end if;
  if p_expected_version is null or p_expected_version<1 then
    raise exception 'expected_version invalido' using errcode='22023';end if;
  -- Mismo candado de todos los publicadores, desde antes de leer precondiciones.
  perform pg_advisory_xact_lock(hashtext('crm.sla_politicas'),1);
  select * into strict v_ultima from crm.sla_politicas order by version desc limit 1;
  if p_expected_version<>v_ultima.version then
    raise exception 'Conflicto de version SLA' using errcode='P0409';end if;
  v_vigente:=private.sla_politica_vigente(statement_timestamp());
  if v_ultima.id is distinct from v_vigente then
    raise exception 'Existe una politica futura; revisar su vigencia antes de inicializar' using errcode='22023';end if;
  if exists(select 1 from crm.sla_politica_etapas_operacion where politica_id=v_ultima.id) then
    raise exception 'Las reglas operativas ya fueron publicadas; no se reinicializan' using errcode='22023';end if;
  return crm.publicar_politica_sla_v2(p_expected_version,null,private.sla_config_inicial_aprobada(v_vigente));
end;
$function$;
revoke all on function crm.publicar_reglas_sla_aprobadas_v2(integer) from public,anon,authenticated,service_role;
grant execute on function crm.publicar_reglas_sla_aprobadas_v2(integer) to authenticated;

create function crm.configuracion_sla_v2_fn()
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid();v_ultima crm.sla_politicas%rowtype;v_control crm.sla_operacion_control%rowtype;
  v_vigente uuid;v_motivo text;
begin
  if v_uid is null or (private.rol_crm(v_uid) is null and not coalesce(private.es_lector_global(),false)) then
    raise exception 'No autorizado' using errcode='42501';end if;
  select * into strict v_ultima from crm.sla_politicas order by version desc limit 1;
  select * into strict v_control from crm.sla_operacion_control where id;
  v_vigente:=private.sla_politica_vigente(statement_timestamp());
  v_motivo:=case when v_ultima.id is distinct from v_vigente then 'politica_futura'
    when exists(select 1 from crm.sla_politica_etapas_operacion where politica_id=v_ultima.id) then 'ya_publicadas'
    when private.rol_crm(v_uid) is distinct from 'gerencia' then 'sin_permiso' else null end;
  return jsonb_build_object('version',2,'puede_editar',coalesce(private.rol_crm(v_uid)='gerencia',false),
    'expected_version',v_ultima.version,
    'vigente',private.sla_politica_payload(v_vigente),
    'ultima_publicada',private.sla_politica_payload(v_ultima.id),
    'inicializacion_aprobada',jsonb_build_object('disponible',v_motivo is null,'motivo',v_motivo,
      'config',private.sla_config_inicial_aprobada(v_vigente)),
    'control',jsonb_build_object('modo',v_control.modo,'revision',v_control.revision,
      'primera_activacion_en',v_control.primera_activacion_en,'politica_adopcion_id',v_control.politica_adopcion_id));
end;
$function$;
revoke all on function crm.configuracion_sla_v2_fn() from public,anon,authenticated,service_role;
grant execute on function crm.configuracion_sla_v2_fn() to authenticated;

create function crm.cambiar_modo_sla_operacion(p_expected_revision integer,p_modo text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s'
as $function$
declare v_uid uuid:=auth.uid();v_control crm.sla_operacion_control%rowtype;
  v_ahora timestamptz;v_politica uuid;v_previo text:=coalesce(current_setting('crm.sla_control_writer',true),'off');
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede cambiar el modo SLA' using errcode='42501';end if;
  if p_expected_revision is null or p_expected_revision<0 or p_modo is null
    or p_modo not in ('legado','observacion','activo') then
    raise exception 'Revision o modo SLA invalido' using errcode='22023';end if;
  -- Ultima dependencia: no bloquear leads, tareas o identidades desde aqui.
  select * into strict v_control from crm.sla_operacion_control where id for update;
  if v_control.revision<>p_expected_revision then
    raise exception 'Conflicto de revision de modo SLA' using errcode='P0409';end if;
  if v_control.modo<>p_modo then
    v_ahora:=clock_timestamp();
    if p_modo in ('observacion','activo') then
      -- Una contingencia que retire captura/ajuste no puede reactivarse hasta
      -- reinstalar sus hooks y resolver el intervalo sin contexto.
      perform private.assert_sla_operacion();
      select politica_id into v_politica from private.sla_politica_operativa(v_ahora);
      if v_politica is null then raise exception 'Publica cuatro reglas operativas antes de cambiar modo' using errcode='22023';end if;
    end if;
    perform set_config('crm.sla_control_writer','on',true);
    update crm.sla_operacion_control set modo=p_modo,revision=revision+1,
      primera_activacion_en=case when p_modo='activo' then coalesce(primera_activacion_en,v_ahora) else primera_activacion_en end,
      politica_adopcion_id=case when p_modo='activo' then coalesce(politica_adopcion_id,v_politica) else politica_adopcion_id end,
      cambiado_por=v_uid,cambiado_en=v_ahora where id returning * into v_control;
    perform set_config('crm.sla_control_writer',v_previo,true);
  end if;
  return jsonb_build_object('version',2,'modo',v_control.modo,'revision',v_control.revision,
    'primera_activacion_en',v_control.primera_activacion_en,'politica_adopcion_id',v_control.politica_adopcion_id);
end;
$function$;
revoke all on function crm.cambiar_modo_sla_operacion(integer,text) from public,anon,authenticated,service_role;
grant execute on function crm.cambiar_modo_sla_operacion(integer,text) to authenticated;

-- Los settings identifican una ruta interna; no conceden permiso. Las ACL
-- cerradas, el propietario efectivo y la profundidad del trigger son obligatorios.
create or replace function private.trg_sla_nucleo_entrada_guard()
returns trigger language plpgsql security invoker set search_path=''
as $function$
declare v_lead uuid;v_evento crm.actividades%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_hechos record;v_control crm.sla_operacion_control%rowtype;v_decision record;
begin
  if tg_op in ('DELETE','TRUNCATE') then raise exception 'Los hechos SLA no se borran' using errcode='55000';end if;
  if current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
    raise exception 'Solo el nucleo escribe entradas SLA' using errcode='42501';end if;
  if tg_table_name='sla_operacion_control' then
    if tg_op<>'UPDATE' or current_setting('crm.sla_control_writer',true) is distinct from 'on' then
      raise exception 'El modo solo cambia por su comando' using errcode='55000';end if;
    if (old.primera_activacion_en is not null and
       (new.primera_activacion_en is distinct from old.primera_activacion_en
        or new.politica_adopcion_id is distinct from old.politica_adopcion_id))
      or new.revision<>old.revision+1 then
      raise exception 'Adopcion inmutable o revision invalida' using errcode='55000';end if;
    if new.politica_adopcion_id is not null and not private.sla_reglas_operacion_validas(
      (select jsonb_agg(to_jsonb(r)-'politica_id') from crm.sla_politica_etapas_operacion r where r.politica_id=new.politica_adopcion_id)) then
      raise exception 'La adopcion requiere cuatro reglas completas' using errcode='23514';end if;
  elsif tg_op='UPDATE' then
    raise exception 'Entrada SLA inmutable' using errcode='55000';
  elsif tg_table_name='sla_politica_etapas_operacion' then
    if current_setting('crm.sla_config_writer',true) is distinct from 'on'
      or exists(select 1 from crm.lead_sla_etapas e where e.politica_id=new.politica_id) then
      raise exception 'Reglas solo durante publicacion, nunca sobre episodios existentes' using errcode='55000';end if;
  elsif tg_table_name='tarea_sla_contexto' then
    if ((new.fuente='evento' and pg_trigger_depth()>=2
               and current_setting('crm.sla_contexto_writer',true)='evento')
         or (new.fuente='reconstruido' and current_setting('crm.sla_contexto_writer',true)='reconstruido')) is distinct from true then
      raise exception 'Contexto solo por captura o reconstruccion privada' using errcode='55000';end if;
    select lead_id into v_lead from crm.tareas where id=new.tarea_id;
    if v_lead is distinct from new.lead_id then
      raise exception 'Contexto ajeno a tarea' using errcode='23514';end if;
  elsif tg_table_name='lead_sla_etapa_ajustes' then
    if (pg_trigger_depth()<2 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on')
      or current_setting('crm.sla_ajuste_writer',true) is distinct from 'on' then
      raise exception 'Ajuste solo desde evento de gestion' using errcode='55000';end if;
    select * into strict v_evento from crm.actividades where id=new.origen_actividad_id;
    select * into strict v_etapa from crm.lead_sla_etapas where id=new.etapa_sla_id;
    select * into strict v_regla from crm.sla_politica_etapas_operacion
      where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
    select * into strict v_control from crm.sla_operacion_control where id;
    select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_etapa.lead_id,v_etapa.ciclo_n,v_etapa.etapa);
    select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
      v_etapa.finalizado_en is null,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
      v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
      v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
    if v_evento.lead_id<>v_etapa.lead_id or v_evento.creado_por is distinct from new.creado_por
      or auth.uid() is distinct from new.creado_por or not v_decision.elegible
      or new.secuencia<>v_hechos.usadas+1 or new.minutos_reales<>v_decision.minutos_reales
      or new.limite_antes<>v_etapa.limite_en+v_hechos.minutos*interval '1 minute'
      or new.limite_despues<>v_decision.limite_despues then
      raise exception 'Ajuste fuera de causa, secuencia o presupuesto' using errcode='23514';end if;
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_sla_nucleo_entrada_guard() from public,anon,authenticated,service_role;

create function private.trg_sla_tarea_contexto()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_lead crm.leads%rowtype;v_anterior text:=coalesce(current_setting('crm.sla_contexto_writer',true),'off');
begin
  if new.lead_id is null then return null;end if;
  -- Reutiliza el lock fuerte adquirido en BEFORE INSERT, incluso con auth NULL.
  select * into strict v_lead from crm.leads where id=new.lead_id for update;
  if not exists(select 1 from crm.lead_sla_ciclos where lead_id=new.lead_id and ciclo_n=v_lead.ciclo_actual) then
    raise exception 'Falta ciclo causal para tarea nueva' using errcode='23514';end if;
  perform set_config('crm.sla_contexto_writer','evento',true);
  insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente)
    values(new.id,new.lead_id,v_lead.ciclo_actual,'evento');
  perform set_config('crm.sla_contexto_writer',v_anterior,true);
  return null;
end;
$function$;
revoke all on function private.trg_sla_tarea_contexto() from public,anon,authenticated,service_role;
create trigger trg_tareas_03_sla_contexto after insert on crm.tareas
for each row when(new.lead_id is not null) execute function private.trg_sla_tarea_contexto();

create function private.sla_conceder_prorroga(p_actividad_id uuid,p_episodio_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_evento crm.actividades%rowtype;v_lead crm.leads%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_control crm.sla_operacion_control%rowtype;
  v_hechos record;v_decision record;v_id uuid;v_previo text:=coalesce(current_setting('crm.sla_ajuste_writer',true),'off');
begin
  if pg_trigger_depth()<1 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on' then
    raise exception 'La prorroga requiere un evento de gestion' using errcode='55000';end if;
  if auth.uid() is null then return null;end if;
  select * into strict v_evento from crm.actividades where id=p_actividad_id;
  if v_evento.creado_por is distinct from auth.uid() then return null;end if;
  select * into strict v_lead from crm.leads where id=v_evento.lead_id for update;
  if not v_lead.activo or private.persona_vetada(v_lead.id) then return null;end if;
  select * into v_etapa from crm.lead_sla_etapas where id=p_episodio_id and lead_id=v_lead.id
    and ciclo_n=v_lead.ciclo_actual and etapa=v_lead.etapa and finalizado_en is null for update;
  if not found then return null;end if;
  select * into v_regla from crm.sla_politica_etapas_operacion
    where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
  if not found then return null;end if;
  select id into v_id from crm.lead_sla_etapa_ajustes where etapa_sla_id=p_episodio_id and origen_actividad_id=p_actividad_id;
  if found then return v_id;end if;
  select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_lead.id,v_lead.ciclo_actual,v_etapa.etapa);
  -- Barrera de apagado: ultima dependencia de bloqueo; conservada hasta commit.
  select * into strict v_control from crm.sla_operacion_control where id for share;
  select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
    true,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
    v_etapa.limite_en+v_hechos.minutos*interval '1 minute',
    v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
    v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
  if not v_decision.elegible then return null;end if;
  perform set_config('crm.sla_ajuste_writer','on',true);
  insert into crm.lead_sla_etapa_ajustes(etapa_sla_id,origen_actividad_id,secuencia,minutos_reales,
    limite_antes,limite_despues,creado_por)
  values(v_etapa.id,v_evento.id,v_hechos.usadas+1,v_decision.minutos_reales,
    v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_decision.limite_despues,v_evento.creado_por)
  returning id into v_id;
  perform set_config('crm.sla_ajuste_writer',v_previo,true);
  return v_id;
end;
$function$;
revoke all on function private.sla_conceder_prorroga(uuid,uuid) from public,anon,authenticated,service_role;

-- Una gestion compuesta (conversacion + siguiente tarea) se decide al finalizar
-- TODO el gesto. Una reunion siguiente puede cambiar el episodio despues de
-- insertar la actividad; no se concede una prorroga a ese episodio abandonado.
create function private.sla_gesto_abrir(p_lead_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_episodio uuid;v_previo text:=coalesce(current_setting('crm.sla_gesto_diferido',true),'off');
begin
  if p_lead_id is null then return null;end if;
  perform 1 from crm.leads where id=p_lead_id for update;
  if not found then raise exception 'Lead no encontrado' using errcode='P0002';end if;
  select id into v_episodio from crm.lead_sla_etapas where lead_id=p_lead_id and finalizado_en is null;
  perform set_config('crm.sla_gesto_diferido','on',true);
  return jsonb_build_object('lead_id',p_lead_id,'episodio_id',v_episodio,'diferido_previo',v_previo);
end;
$function$;
revoke all on function private.sla_gesto_abrir(uuid) from public,anon,authenticated,service_role;

create function private.sla_gesto_cerrar(p_actividad_id uuid,p_contexto jsonb)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_previo text;v_final_previo text:=coalesce(current_setting('crm.sla_finalizando_gesto',true),'off');
  v_episodio uuid;v_id uuid;
begin
  if p_contexto is null then return null;end if;
  if jsonb_typeof(p_contexto) is distinct from 'object'
    or not(p_contexto ?& array['lead_id','episodio_id','diferido_previo'])
    or jsonb_typeof(p_contexto->'diferido_previo') is distinct from 'string' then
    raise exception 'Contexto interno de gesto invalido' using errcode='22023';end if;
  v_previo:=p_contexto->>'diferido_previo';
  perform set_config('crm.sla_gesto_diferido',v_previo,true);
  if v_previo='on' or p_actividad_id is null or p_contexto->>'episodio_id' is null then return null;end if;
  select id into v_episodio from crm.lead_sla_etapas where lead_id=(p_contexto->>'lead_id')::uuid and finalizado_en is null;
  if v_episodio is distinct from (p_contexto->>'episodio_id')::uuid then return null;end if;
  if not exists(select 1 from crm.actividades where id=p_actividad_id and lead_id=(p_contexto->>'lead_id')::uuid) then
    raise exception 'Actividad ajena al gesto' using errcode='23514';end if;
  perform set_config('crm.sla_finalizando_gesto','on',true);
  v_id:=private.sla_conceder_prorroga(p_actividad_id,v_episodio);
  perform set_config('crm.sla_finalizando_gesto',v_final_previo,true);
  return v_id;
end;
$function$;
revoke all on function private.sla_gesto_cerrar(uuid,jsonb) from public,anon,authenticated,service_role;

create or replace function private.trg_actividades_avance_etapa()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
declare v_previo text:=coalesce(current_setting('crm.avance_auto',true),'off');
  v_antes uuid;v_despues uuid;
begin
  if v_previo='on' then return null;end if;
  if new.lead_id is null or new.tipo not in ('llamada_realizada','whatsapp_recibido','reunion_realizada') then return null;end if;
  perform 1 from crm.leads where id=new.lead_id for update;
  select id into v_antes from crm.lead_sla_etapas where lead_id=new.lead_id and finalizado_en is null;
  perform set_config('crm.avance_auto','on',true);
  -- Misma transicion automatica vigente; el evento que avanza no se premia.
  update crm.leads set etapa='contactado' where id=new.lead_id and activo and etapa='nuevo';
  perform set_config('crm.avance_auto',v_previo,true);
  select id into v_despues from crm.lead_sla_etapas where lead_id=new.lead_id and finalizado_en is null;
  if v_antes is not null and v_antes=v_despues
    and current_setting('crm.sla_gesto_diferido',true) is distinct from 'on' then
    perform private.sla_conceder_prorroga(new.id,v_antes);
  end if;
  return null;
end;
$function$;
revoke all on function private.trg_actividades_avance_etapa() from public,anon,authenticated,service_role;

-- Solo cambia la primera adquisicion del lead; postventa conserva FOR SHARE.
CREATE OR REPLACE FUNCTION private.trg_tareas_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads%rowtype;
  v_cliente public.perfiles%rowtype;
  v_equipo crm.equipo%rowtype;
begin
  if new.lead_id is not null then
    -- El mismo row-lock serializa alta de tarea contra cierre/reasignación. Sin
    -- él, ambos commits podían dejar la tarea en el árbol anterior.
    select * into v_lead from crm.leads where id = new.lead_id for update;
    if not found then raise exception 'El lead de la tarea no existe'; end if;
    if v_lead.activo = false or v_lead.etapa in ('convertido','descartado') then
      raise exception 'El lead está cerrado: no admite tareas nuevas';
    end if;
    new.vendedor_id := v_lead.vendedor_id;
    new.asignado_supervisor_id := v_lead.asignado_supervisor_id;
  elsif new.perfil_id is not null then
    select * into v_cliente from public.perfiles p
    where p.id = new.perfil_id and p.rol = 'cliente'
    for share;
    if not found then raise exception 'El cliente de la tarea no existe'; end if;
    if not v_cliente.activo then
      raise exception 'El cliente está inactivo: no admite tareas comerciales nuevas';
    end if;
    if v_cliente.asesor_perfil_id is null then
      raise exception 'Asigna un Analista al cliente antes de agendar una gestión';
    end if;
    select * into v_equipo from crm.equipo e
    where e.perfil_id = v_cliente.asesor_perfil_id and e.activo
    for share;
    if not found or v_equipo.rol_crm not in ('vendedor','supervisor') then
      raise exception 'El Analista de la cartera no está activo en el CRM';
    end if;
    new.vendedor_id := v_cliente.asesor_perfil_id;
    new.asignado_supervisor_id := case
      when v_equipo.rol_crm = 'vendedor' then v_equipo.supervisor_id
      else null
    end;
  end if;

  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por una RPC de agenda'
      using errcode = '22023';
  end if;
  if new.tipo = 'reunion' then
    new.modalidad_reunion := coalesce(new.modalidad_reunion, 'sin_clasificar');
  else
    new.modalidad_reunion := null;
    new.ubicacion_reunion := null;
    new.enlace_reunion := null;
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  if new.estado = 'pendiente' then
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  new.cancelada_por_id := null;
  return new;
end;
$function$;

revoke all on function private.trg_tareas_before_insert() from public,anon,authenticated,service_role;

-- Auxiliares TRANSITORIOS: solo propietario, retirados despues del stock.
create function private.sla_cadena_tarea_reconstruible(p_tarea uuid,p_lead uuid,p_inicio timestamptz)
returns boolean language plpgsql stable security invoker set search_path=''
as $function$
declare v_actual crm.tareas%rowtype;v_padre crm.tareas%rowtype;v_visitados uuid[]:='{}';
begin
  select * into v_actual from crm.tareas where id=p_tarea;
  if not found then return false;end if;
  loop
    if v_actual.id=any(v_visitados) or cardinality(v_visitados)>=64
      or v_actual.lead_id is distinct from p_lead or not isfinite(v_actual.creado_en)
      or v_actual.creado_en<p_inicio then return false;end if;
    v_visitados:=array_append(v_visitados,v_actual.id);
    if v_actual.reagendada_de is null then return true;end if;
    select * into v_padre from crm.tareas where id=v_actual.reagendada_de;
    if not found or v_padre.estado not in ('no_show','reprogramada')
      or v_padre.creado_en>v_actual.creado_en
      or (v_padre.estado='reprogramada' and v_actual.reprogramaciones<v_padre.reprogramaciones+1)
    then return false;end if;
    v_actual:=v_padre;
  end loop;
end;
$function$;
revoke all on function private.sla_cadena_tarea_reconstruible(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;

create function private.sla_reconstruir_contextos_lote(p_lead_ids uuid[])
returns table(tarea_id uuid,lead_id uuid,ciclo_n integer,resultado text)
language plpgsql security definer set search_path='' set lock_timeout='5s'
as $function$
declare t crm.tareas%rowtype;l crm.leads%rowtype;c crm.lead_sla_ciclos%rowtype;
  v_audit_ts timestamptz;v_contexto crm.tarea_sla_contexto%rowtype;v_modo text;
  v_ahora timestamptz:=clock_timestamp();v_previo text:=coalesce(current_setting('crm.sla_contexto_writer',true),'off');
begin
  if p_lead_ids is null or cardinality(p_lead_ids) not between 1 and 200
    or array_position(p_lead_ids,null) is not null then
    raise exception 'Reconstruccion admite de 1 a 200 leads' using errcode='22023';end if;
  -- Cada llamada es un lote. El operador confirma cada transaccion por separado.
  perform 1 from crm.leads x where x.id=any(p_lead_ids) order by x.id for update;
  perform 1 from crm.tareas x where x.lead_id=any(p_lead_ids) and x.activo and x.estado='pendiente'
    order by x.id for update;
  select modo into strict v_modo from crm.sla_operacion_control where id for share;
  if v_modo<>'legado' then raise exception 'Reconstruir antes de activar o bajo legado' using errcode='55000';end if;
  perform set_config('crm.sla_contexto_writer','reconstruido',true);
  for t in select x.* from crm.tareas x where x.lead_id=any(p_lead_ids) and x.activo and x.estado='pendiente' order by x.id loop
    tarea_id:=t.id;lead_id:=t.lead_id;ciclo_n:=null;resultado:=null;
    select * into v_contexto from crm.tarea_sla_contexto x where x.tarea_id=t.id;
    if found then
      ciclo_n:=v_contexto.ciclo_n;
      resultado:=case when v_contexto.lead_id=t.lead_id then 'existente' else 'conflicto_contexto' end;
      return next;continue;
    end if;
    select * into strict l from crm.leads x where x.id=t.lead_id;
    select * into c from crm.lead_sla_ciclos x where x.lead_id=l.id and x.ciclo_n=l.ciclo_actual;
    if not found or c.aproximado or not isfinite(c.iniciado_en) or c.iniciado_en>v_ahora then
      resultado:='ciclo_no_demostrable';
    elsif not l.activo or l.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then
      resultado:='lead_no_abierto';
    elsif not isfinite(t.creado_en) or t.creado_en<c.iniciado_en or t.creado_en>v_ahora then
      resultado:='creacion_fuera_ciclo';
    elsif t.vendedor_id is distinct from l.vendedor_id or t.asignado_supervisor_id is distinct from l.asignado_supervisor_id then
      resultado:='tenencia_incoherente';
    elsif not private.sla_cadena_tarea_reconstruible(t.id,l.id,c.iniciado_en) then
      resultado:='cadena_no_demostrable';
    else
      select a.ts into v_audit_ts from public.audit_log a
      where a.tabla='crm.tareas' and a.operacion='INSERT' and a.fila_id=t.id::text
        and a.usuario_id=t.creado_por and t.creado_por is not null
        and a.ts>=c.iniciado_en and a.ts<=v_ahora
        -- Rango utilizable por idx_audit_log_tabla_ts, sin funcion sobre ts.
        and a.ts between t.creado_en-interval '60 seconds' and t.creado_en+interval '60 seconds'
        and (a.data_despues->>'creado_en')::timestamptz=t.creado_en
        and a.data_despues->>'lead_id'=t.lead_id::text
        and a.data_despues->>'creado_por'=t.creado_por::text
      order by a.ts limit 1;
      if not found then resultado:='alta_humana_no_demostrable';
      elsif exists(select 1 from public.audit_log a
        where a.tabla='crm.leads' and a.operacion='UPDATE' and a.fila_id=l.id::text and a.ts>=v_audit_ts
          and ((a.data_antes->>'activo'='true' and a.data_despues->>'activo'='false')
            or (a.data_antes->>'etapa' in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
                and a.data_despues->>'etapa' in ('convertido','descartado'))
            or ((a.data_antes->>'vendedor_id' is not null or a.data_antes->>'asignado_supervisor_id' is not null)
                and a.data_despues->>'vendedor_id' is null and a.data_despues->>'asignado_supervisor_id' is null))) then
        resultado:='barrera_de_cancelacion';
      else
        insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente)
          values(t.id,l.id,c.ciclo_n,'reconstruido');
        ciclo_n:=c.ciclo_n;resultado:='reconstruido';
      end if;
    end if;
    return next;
  end loop;
  perform set_config('crm.sla_contexto_writer',v_previo,true);
end;
$function$;
revoke all on function private.sla_reconstruir_contextos_lote(uuid[]) from public,anon,authenticated,service_role;

create function private.assert_sla_operacion()
returns text language plpgsql stable security definer set search_path=''
as $function$
declare v record;v_text text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.publicar_politica_sla(integer,timestamptz,jsonb)','sla_publicar_politica_core'),
    ('crm.publicar_politica_sla_v2(integer,timestamptz,jsonb)','sla_publicar_politica_core'),
    ('private.trg_actividades_avance_etapa()','sla_conceder_prorroga'),
    ('private.sla_conceder_prorroga(uuid,uuid)','sla_evaluar_prorroga'),
    ('private.sla_gesto_cerrar(uuid,jsonb)','sla_conceder_prorroga')
  ) d(firma,dependencia) loop
    select prosrc into strict v_text from pg_proc where oid=v.firma::regprocedure;
    if strpos(v_text,'private.'||v.dependencia||'(')=0 then raise exception 'Dependencia SLA ausente: %',v.firma;end if;
  end loop;
  if not exists(select 1 from pg_trigger where tgrelid='crm.tareas'::regclass
      and tgfoid='private.trg_sla_tarea_contexto()'::regprocedure and tgenabled='O') then
    raise exception 'Captura de contexto SLA ausente';end if;
  for v in select p.oid,p.proowner,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in ('sla_reglas_operacion_validas','sla_publicar_politica_core',
      'sla_politica_payload','sla_config_inicial_aprobada','trg_sla_tarea_contexto','sla_conceder_prorroga','sla_gesto_abrir','sla_gesto_cerrar',
      'sla_reconstruir_contextos_lote','sla_cadena_tarea_reconstruible') loop
    if exists(select 1 from aclexplode(coalesce(v.proacl,acldefault('f',v.proowner))) a where a.grantee<>v.proowner) then
      raise exception 'Privilegio externo sobre nucleo escritor %',v.oid::regprocedure;end if;
  end loop;
  return 'OK: publicacion atomica, captura y prorroga gobernadas por SLA';
end;
$function$;
revoke all on function private.assert_sla_operacion() from public,anon,authenticated,service_role;

comment on function private.sla_reconstruir_contextos_lote(uuid[]) is 'TRANSITORIO SLA: propietario, lotes de hasta 200 leads, solo legado; no reescribe tarea ni presume contexto. Retirar al cerrar reconstruccion.';
comment on function private.sla_conceder_prorroga(uuid,uuid) is 'Writer SLA: causa humana, mismo episodio, lead bloqueado, barrera de modo al final, regla compartida N1 y asiento inmutable.';
comment on function crm.publicar_politica_sla_v2(integer,timestamptz,jsonb) is 'Publica base y cuatro reglas operativas atomicas; Gerencia, revision esperada, sin activar ni alterar episodios historicos.';

do $postflight$
declare v_gate text;
begin
  perform private.assert_sla_operacion();
  foreach v_gate in array array['assert_analitica_leads_citas','assert_auditoria','assert_analista_vigencia','assert_f7_piezas_cerradas'] loop
    if to_regprocedure('private.'||v_gate||'()') is not null then execute format('select private.%I()',v_gate);end if;
  end loop;
end;
$postflight$;
commit;
