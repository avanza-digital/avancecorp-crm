-- Gestión Diaria F4.5. Puertas gerenciales y control de emergencia.
-- Publicar esta migración no crea una política activa ni cambia la jornada.
begin;
do $preflight$ begin
  perform private.assert_gestion_diaria();
  if to_regprocedure('crm.gestion_diaria_avisos_fn()') is null then
    raise exception 'Falta la etapa 4 de Gestión Diaria';
  end if;
end $preflight$;

create function private.politica_gestion_diaria_json(p crm.politica_gestion_diaria) returns jsonb
language sql stable security invoker set search_path = '' as $function$
  select jsonb_build_object('version', p.version, 'vigente_desde', p.vigente_desde,
    'creado_en', p.creado_en, 'creado_por', p.creado_por, 'motivo', p.motivo,
    'configuracion', jsonb_build_object('cortes_activos', p.cortes_activos,
      'corte_1_hora', left(p.corte_1_hora::text, 5), 'corte_1_minimo', p.corte_1_minimo,
      'corte_2_hora', left(p.corte_2_hora::text, 5), 'corte_2_incremento_pct', p.corte_2_incremento_pct,
      'corte_2_piso', p.corte_2_piso, 'corte_2_techo', p.corte_2_techo,
      'sabado_minimo', p.sabado_minimo, 'bien_min_pct', p.bien_min_pct,
      'atencion_min_pct', p.atencion_min_pct, 'minimo_llamadas_utiles', p.minimo_llamadas_utiles,
      'tasa_baja_diferencia_pp', p.tasa_baja_diferencia_pp));
$function$;
revoke all on function private.politica_gestion_diaria_json(crm.politica_gestion_diaria)
  from public, anon, authenticated, service_role;

-- DEFINER solo para metadatos de configuración que no se exponen en la tabla.
create function crm.configuracion_gestion_diaria_fn() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_vigente crm.politica_gestion_diaria; v_control crm.gestion_diaria_control_avisos;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or not (coalesce(private.rol_crm(auth.uid()) = 'gerencia', false) or private.es_lector_global()) then
    raise exception 'Configuración disponible para gerencia y lectura global autorizada' using errcode = '42501';
  end if;
  select p.* into strict v_vigente from crm.politica_gestion_diaria p
    join private.politica_gestion_diaria_vigente(v_hoy::timestamp at time zone 'America/Lima') v on v.id = p.id;
  select * into strict v_control from crm.gestion_diaria_control_avisos order by version desc limit 1;
  return jsonb_build_object('version', 1, 'dia', v_hoy, 'zona', 'America/Lima',
    'puede_editar', coalesce(private.rol_crm(auth.uid()) = 'gerencia', false),
    'expected_version', (select max(version) from crm.politica_gestion_diaria),
    'vigente', private.politica_gestion_diaria_json(v_vigente),
    'revisiones_pendientes', (select coalesce(jsonb_agg(private.politica_gestion_diaria_json(p)
      order by p.vigente_desde, p.version), '[]') from crm.politica_gestion_diaria p
      where p.vigente_desde > v_hoy::timestamp at time zone 'America/Lima'),
    'historial', (select jsonb_agg(private.politica_gestion_diaria_json(p) order by p.version desc)
      from crm.politica_gestion_diaria p),
    'control_avisos', to_jsonb(v_control));
end $function$;
revoke all on function crm.configuracion_gestion_diaria_fn() from public, anon, authenticated, service_role;
grant execute on function crm.configuracion_gestion_diaria_fn() to authenticated;

create function crm.publicar_politica_gestion_diaria(p_expected_version integer,
  p_vigente_desde timestamptz, p_config jsonb, p_motivo text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $function$
declare v_ultima crm.politica_gestion_diaria; v_clave text; v_tipo text;
  v_claves text[] := array['cortes_activos','corte_1_hora','corte_1_minimo','corte_2_hora',
    'corte_2_incremento_pct','corte_2_piso','corte_2_techo','sabado_minimo',
    'bien_min_pct','atencion_min_pct','minimo_llamadas_utiles','tasa_baja_diferencia_pp'];
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'gerencia' then
    raise exception 'Solo gerencia publica reglas de Gestión Diaria' using errcode = '42501';
  end if;
  if p_expected_version is null or p_vigente_desde is null or not isfinite(p_vigente_desde)
    or p_motivo is null or length(btrim(p_motivo)) not between 3 and 500
    or p_config is null or jsonb_typeof(p_config) <> 'object'
    or not p_config ?& v_claves or p_config - v_claves <> '{}'::jsonb then
    raise exception 'Publicación incompleta o con campos desconocidos' using errcode = '22023';
  end if;
  -- Miguel confirmó el 22/09: la tasa muy baja permanece apagada hasta F5.
  if p_config->'tasa_baja_diferencia_pp' <> 'null'::jsonb then
    raise exception 'La alerta de tasa muy baja permanece apagada hasta F5' using errcode = '22023';
  end if;
  foreach v_clave in array v_claves loop
    v_tipo := jsonb_typeof(p_config->v_clave);
    if v_clave = 'cortes_activos' then
      if v_tipo <> 'boolean' then raise exception 'Activación inválida' using errcode = '22023'; end if;
    elsif v_clave in ('corte_1_hora','corte_2_hora') then
      if v_tipo <> 'string' or (p_config->>v_clave) collate "C" !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'La hora debe tener formato HH:MM' using errcode = '22023';
      end if;
    elsif not (v_clave = 'tasa_baja_diferencia_pp' and v_tipo = 'null') then
      if v_tipo <> 'number' then raise exception 'Parámetro numérico inválido' using errcode = '22023'; end if;
      if v_clave in ('corte_1_minimo','corte_2_piso','corte_2_techo','sabado_minimo','minimo_llamadas_utiles')
        and (p_config->>v_clave)::numeric <> trunc((p_config->>v_clave)::numeric) then
        raise exception 'Las cantidades deben ser enteras' using errcode = '22023';
      end if;
    end if;
  end loop;
  if p_vigente_desde > (((clock_timestamp() at time zone 'America/Lima')::date + 90)::timestamp at time zone 'America/Lima') then
    raise exception 'Programa la vigencia dentro de los próximos 90 días' using errcode = '22023';
  end if;
  -- El trigger publicado conserva cadena, jornada futura y monotonicidad.
  -- Usar su mismo candado evita carreras con otros escritores administrativos.
  perform pg_advisory_xact_lock(194203, 43);
  select * into strict v_ultima from crm.politica_gestion_diaria order by version desc limit 1;
  if p_expected_version <> v_ultima.version then
    raise exception 'Otra persona publicó cambios; vuelve a cargar la configuración' using errcode = '40001';
  end if;
  insert into crm.politica_gestion_diaria(version,version_anterior_id,vigente_desde,creado_por,motivo,
    cortes_activos,corte_1_hora,corte_1_minimo,corte_2_hora,corte_2_incremento_pct,corte_2_piso,corte_2_techo,
    sabado_minimo,bien_min_pct,atencion_min_pct,minimo_llamadas_utiles,tasa_baja_diferencia_pp)
  values (v_ultima.version+1,v_ultima.id,p_vigente_desde,auth.uid(),btrim(p_motivo),
    (p_config->>'cortes_activos')::boolean,(p_config->>'corte_1_hora')::time,(p_config->>'corte_1_minimo')::numeric::integer,
    (p_config->>'corte_2_hora')::time,(p_config->>'corte_2_incremento_pct')::numeric,
    (p_config->>'corte_2_piso')::numeric::integer,(p_config->>'corte_2_techo')::numeric::integer,(p_config->>'sabado_minimo')::numeric::integer,
    (p_config->>'bien_min_pct')::numeric,(p_config->>'atencion_min_pct')::numeric,
    (p_config->>'minimo_llamadas_utiles')::numeric::integer,(p_config->>'tasa_baja_diferencia_pp')::numeric);
  return crm.configuracion_gestion_diaria_fn();
end $function$;
revoke all on function crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text) to authenticated;

create function crm.controlar_avisos_gestion_diaria(p_expected_version integer, p_habilitados boolean, p_motivo text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_version integer;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'gerencia' then
    raise exception 'Solo gerencia controla el canal de avisos' using errcode = '42501';
  end if;
  if p_expected_version is null or p_habilitados is null or p_motivo is null
    or length(btrim(p_motivo)) not between 3 and 500 then
    raise exception 'Indica la versión, el estado y el motivo' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(194203, 44);
  select max(version) into v_version from crm.gestion_diaria_control_avisos;
  if p_expected_version <> v_version then
    raise exception 'El control de avisos cambió; vuelve a cargarlo' using errcode = '40001';
  end if;
  insert into crm.gestion_diaria_control_avisos(version,habilitados,motivo,creado_por)
    values(v_version+1,p_habilitados,btrim(p_motivo),auth.uid());
  return crm.configuracion_gestion_diaria_fn();
end $function$;
revoke all on function crm.controlar_avisos_gestion_diaria(integer,boolean,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.controlar_avisos_gestion_diaria(integer,boolean,text) to authenticated;

comment on function crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text) is
  'F4: solo gerencia. Configuración estricta y versión esperada; inserta política inmutable para jornada futura Lima. No modifica días anteriores.';
comment on function crm.controlar_avisos_gestion_diaria(integer,boolean,text) is
  'F4: apagado/reanudación inmediata del canal de avisos por gerencia, con motivo y versión. No cambia cálculos, reconocimientos ni política del día.';
create function private.assert_gestion_diaria_configuracion() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare f record;
begin
  for f in select * from (values
    ('private.politica_gestion_diaria_json(crm.politica_gestion_diaria)','79d50756ef3498a4a4827e8358dca64b',false,'s',false),
    ('crm.configuracion_gestion_diaria_fn()','3effc94401cbc4d5e713efdc19ef19f7',true,'s',true),
    ('crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text)','7b56e17b707e86ec577092ba372bf854',true,'v',true),
    ('crm.controlar_avisos_gestion_diaria(integer,boolean,text)','e499268b4f3985887ff98d2f261e67ef',true,'v',true)
  ) firmas(firma,huella,definer,volatilidad,api) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f.firma)
      and md5(p.prosrc)=f.huella and p.proowner='postgres'::regrole
      and p.prosecdef=f.definer and p.provolatile=f.volatilidad::"char"
      and p.proconfig=array['search_path=""']
      and has_function_privilege('authenticated',p.oid,'EXECUTE')=f.api
      and not has_function_privilege('anon',p.oid,'EXECUTE')
      and not has_function_privilege('service_role',p.oid,'EXECUTE')) then
      raise exception 'F4.5: cuerpo, propietario o permisos alterados en %',f.firma;
    end if;
  end loop;
  return 'OK: configuración gerencial estricta, versionada y futura; control de avisos auditado';
end $function$;
revoke all on function private.assert_gestion_diaria_configuracion() from public,anon,authenticated,service_role;

create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
begin
  return 'OK: Gestion Diaria [' || private.assert_gestion_diaria_registro()
    || '] [' || private.assert_gestion_diaria_resultado()
    || '] [' || private.assert_gestion_diaria_analista()
    || '] [' || private.assert_gestion_diaria_equipo()
    || '] [' || private.assert_gestion_diaria_cortes()
    || '] [' || private.assert_gestion_diaria_avisos()
    || '] [' || private.assert_gestion_diaria_configuracion() || ']';
end $function$;

do $postflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;
