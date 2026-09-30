-- ENSAYO DESHECHO: oráculo de igualdad antes/después ejecutando la MIGRACIÓN real; 5 actores × 3 vistas. Termina en raise.
do $do$
declare sups uuid[]; ger uuid; a int; fase int; v jsonb; t0 timestamptz; res jsonb[]:=array['{}'::jsonb,'{}'::jsonb]; dur jsonb[]:=array['{}'::jsonb,'{}'::jsonb];
  k text; iguales int:=0; distintos text[]:='{}'; hoy date:=(now() at time zone 'America/Lima')::date; actores uuid[]; nombres text[];
begin
  set local statement_timeout='170s';
  select e.perfil_id into ger from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  select array_agg(e.perfil_id order by e.perfil_id) into sups from crm.equipo e where e.rol_crm='supervisor' and e.activo;
  actores:=ger||sups; nombres:=array['gerencia']||array(select 'sup'||g from generate_series(1,cardinality(sups)) g);
  for fase in 1..2 loop
    if fase=2 then
      execute $x$do $mig$
declare
  h_a text; h_p text; h_1 text; h_2 text; r record; p_etapa text;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(p.prosrc) into h_a from pg_proc p where p.oid='private.gestion_diaria_alertas_sla()'::regprocedure;
  h_p := md5(pg_get_functiondef('private.gestion_diaria_equipo_pendientes()'::regprocedure));
  h_1 := md5(pg_get_functiondef('private.assert_gestion_diaria_alertas_equipo()'::regprocedure));
  h_2 := md5(pg_get_functiondef('private.assert_gestion_diaria_equipo()'::regprocedure));
  -- Invariantes que las huellas no cubren (dueño y ACL exacta; DEFINER, STABLE y search_path vacío también se exigen).
  -- IS NOT TRUE: un NULL rechaza. search_path vacío se guarda como search_path="".
  for r in select * from (values
      ('private.gestion_diaria_alertas_sla()', '{postgres=X/postgres,crm_gestion_diaria_lector=X/postgres}'),
      ('private.gestion_diaria_equipo_pendientes()', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.assert_gestion_diaria_alertas_equipo()', '{postgres=X/postgres}'),
      ('private.assert_gestion_diaria_equipo()', '{postgres=X/postgres}')) t(firma, acl) loop
    select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
      into v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = r.firma::regprocedure;
    if (v_owner = 'postgres' and v_acl is not null and v_acl = r.acl and v_secdef is true and v_vol = 's'
        and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception '%: dueño/ACL/definer/volatilidad/search_path de % no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', 'PREFLIGHT', r.firma, v_owner, v_acl, v_secdef, v_vol, v_cfg;
    end if;
  end loop;
  if to_regprocedure('private.sla_leads_operativos()') is null or md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception '%: falta el ayudante private.sla_leads_operativos() con la huella del 29/09 (migración 20260930002929)', 'PREFLIGHT';
  end if;
  if h_a = '94bbf61cd1133a1ccca6d0fb5f764455' and h_p = '034cbb49d4f0fc4c6b5140a32db86b76' and h_1 = '02c9cd9fe743b311d23df60a8d335c10' and h_2 = '28f82e7d145d1ef9ff9809a9d485613a' then
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'gestion_diaria_solo_operativos: ya aplicada';
    return;
  end if;
  if h_a is distinct from 'bca4ff0c4ee591bb405c2e1bedb3082b' or h_p is distinct from '6de28503dd0a32bd98de95d1f5de3532'
     or h_1 is distinct from 'abb5da739e960117f8e2ad8fa2d323d8' or h_2 is distinct from '38f2de1b8226fd97abfb5e4588803e0d' then
    raise exception 'PREFLIGHT: alguna de las cuatro funciones no es la viva del 30/09/2026 (alertas %, pendientes %, assert_alertas %, assert_equipo %)', h_a, h_p, h_1, h_2;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.gestion_diaria_alertas_sla()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_datos jsonb; v_grupos jsonb;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'supervisor' then
    raise exception 'Solo el supervisor consulta sus pendientes' using errcode='42501';
  end if;
  v_datos := -- Solo las oportunidades que pueden avisar (activas en etapa comercial): las terminales nunca aportan a
  -- estas cifras (paso 4 · fase 1 del refactor, 30/09/2026). El núcleo y su visibilidad no cambian.
  private.sla_operacion_autorizada(private.sla_leads_operativos(), true);
  with avisos as (
    select f.value #>> '{lead,id}' as lead_id, a.value->>'bucket' as tipo,
      a.value->>'severidad' as severidad, (a.value->>'prioridad')::integer as prioridad
    from jsonb_array_elements(v_datos->'filas') f
    cross join lateral jsonb_array_elements(f.value #> '{estado,avisos}') a
    where v_datos->>'modo'='activo' and (f.value #>> '{senales,pendientes}')::boolean
  ), grupos as (
    select tipo, jsonb_agg(distinct lead_id order by lead_id) miembros,
      case when bool_or(severidad='critica') then 'critica' else 'atencion' end severidad,
      min(prioridad) prioridad
    from avisos group by tipo
  ) select coalesce(jsonb_agg(jsonb_build_object(
      'id','grupo:'||tipo||':'||auth.uid(), 'tipo',tipo, 'severidad',severidad,
      'miembros',miembros, 'total',jsonb_array_length(miembros)) order by prioridad,tipo),'[]')
    into v_grupos from grupos;
  return jsonb_build_object('modo_sla',v_datos->'modo','alertas',v_grupos);
end $function$
$def$;
  execute $def$
CREATE OR REPLACE FUNCTION private.gestion_diaria_equipo_pendientes()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_datos jsonb;
  v_filas jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm()
    or not (coalesce(private.rol_crm(v_uid) in ('supervisor', 'gerencia'), false)
      or private.es_lector_global()) then
    raise exception 'No autorizado para consultar el equipo' using errcode = '42501';
  end if;
  v_datos := -- Solo las oportunidades que pueden avisar (activas en etapa comercial): las terminales nunca aportan a
  -- estas cifras (paso 4 · fase 1 del refactor, 30/09/2026). El núcleo y su visibilidad no cambian.
  private.sla_operacion_autorizada(private.sla_leads_operativos(), true);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_filas
  from (
    select (f.value #>> '{lead,analista_id}')::uuid as analista_id,
      coalesce(cardinality(array_agg(f.value #>> '{lead,id}') filter
        (where (f.value #>> '{senales,primera_atencion}')::boolean)), 0) as primer_intento_vencido,
      coalesce(cardinality(array_agg(f.value #>> '{lead,id}') filter
        (where (f.value #>> '{senales,datos_incompletos}')::boolean)), 0) as datos_incompletos
    from jsonb_array_elements(v_datos->'filas') f
    where f.value #>> '{lead,analista_id}' is not null
    group by f.value #>> '{lead,analista_id}'
  ) x;
  return jsonb_build_object('modo', v_datos->'modo', 'filas', v_filas);
end;
$function$
$def$;
  execute $def$
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_alertas_equipo()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f record;
begin
  for f in select * from (values
    ('private.gestion_diaria_alertas_sla()','94bbf61cd1133a1ccca6d0fb5f764455',true,'s'),
    ('private.gestion_diaria_contexto(uuid[],timestamptz,jsonb)','d13024e306a1fad6e22c4b592029b8d0',false,'v')
  ) funciones(firma,huella,definer,volatilidad) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f.firma)
      and md5(p.prosrc)=f.huella and p.proowner='postgres'::regrole
      and p.prosecdef=f.definer and p.provolatile=f.volatilidad::"char" and p.proconfig=array['search_path=""']
      and has_function_privilege('crm_gestion_diaria_lector',p.oid,'EXECUTE')
      and not has_function_privilege('authenticated',p.oid,'EXECUTE')
      and not has_function_privilege('anon',p.oid,'EXECUTE')
      and not has_function_privilege('service_role',p.oid,'EXECUTE')) then
      raise exception 'F4: contexto o adaptador de pendientes alterado en %',f.firma;
    end if;
  end loop;
  return 'OK: pendientes SLA agrupados y contexto de llamadas bajo RLS; tasa baja OFF';
end $function$
$def$;
  execute $def$
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_equipo()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_firma text; v_definer boolean;
begin
  foreach v_firma in array array['crm.gestion_diaria_equipo_fn(date,uuid)',
    'private.gestion_diaria_equipo_core(date,uuid)', 'private.gestion_diaria_equipo_pendientes()'] loop
    v_definer := v_firma = 'private.gestion_diaria_equipo_pendientes()';
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and p.prosecdef = v_definer and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')) then
      raise exception 'F4: contrato de permisos alterado en %', v_firma;
    end if;
  end loop;
  if md5(pg_get_functiondef('crm.gestion_diaria_equipo_fn(date,uuid)'::regprocedure)) <> '6fee13c7191e5fc17647f9b684a3630c'
    or md5(pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure)) <> '2628ad9f6805c6944c2773b2f0f2125f'
    or md5(pg_get_functiondef('private.gestion_diaria_equipo_pendientes()'::regprocedure)) <> '034cbb49d4f0fc4c6b5140a32db86b76' then
    raise exception 'F4: cambió el cuerpo de la vista del equipo';
  end if;
  perform private.assert_gestion_diaria_analista();
  perform private.assert_sla_avisos();
  return 'OK: equipo completo, agregado canónico y acceso por identidad';
end;
$function$
$def$;

  select md5(p.prosrc) into h_a from pg_proc p where p.oid='private.gestion_diaria_alertas_sla()'::regprocedure;
  h_p := md5(pg_get_functiondef('private.gestion_diaria_equipo_pendientes()'::regprocedure));
  h_1 := md5(pg_get_functiondef('private.assert_gestion_diaria_alertas_equipo()'::regprocedure));
  h_2 := md5(pg_get_functiondef('private.assert_gestion_diaria_equipo()'::regprocedure));
  if h_a is distinct from '94bbf61cd1133a1ccca6d0fb5f764455' or h_p is distinct from '034cbb49d4f0fc4c6b5140a32db86b76'
     or h_1 is distinct from '02c9cd9fe743b311d23df60a8d335c10' or h_2 is distinct from '28f82e7d145d1ef9ff9809a9d485613a' then
    raise exception 'POSTFLIGHT: huellas inesperadas tras el cambio (alertas %, pendientes %, assert_alertas %, assert_equipo %)', h_a, h_p, h_1, h_2;
  end if;
  -- Invariantes que las huellas no cubren (dueño y ACL exacta; DEFINER, STABLE y search_path vacío también se exigen).
  -- IS NOT TRUE: un NULL rechaza. search_path vacío se guarda como search_path="".
  for r in select * from (values
      ('private.gestion_diaria_alertas_sla()', '{postgres=X/postgres,crm_gestion_diaria_lector=X/postgres}'),
      ('private.gestion_diaria_equipo_pendientes()', '{postgres=X/postgres,authenticated=X/postgres}'),
      ('private.assert_gestion_diaria_alertas_equipo()', '{postgres=X/postgres}'),
      ('private.assert_gestion_diaria_equipo()', '{postgres=X/postgres}')) t(firma, acl) loop
    select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
      into v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = r.firma::regprocedure;
    if (v_owner = 'postgres' and v_acl is not null and v_acl = r.acl and v_secdef is true and v_vol = 's'
        and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception '%: dueño/ACL/definer/volatilidad/search_path de % no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', 'POSTFLIGHT', r.firma, v_owner, v_acl, v_secdef, v_vol, v_cfg;
    end if;
  end loop;
  if to_regprocedure('private.sla_leads_operativos()') is null or md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception '%: falta el ayudante private.sla_leads_operativos() con la huella del 29/09 (migración 20260930002929)', 'POSTFLIGHT';
  end if;
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'gestion_diaria_solo_operativos: aplicada';
end $mig$;$x$;
    end if;
    for a in 1..cardinality(actores) loop
      perform set_config('request.jwt.claim.sub', actores[a]::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', actores[a], 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      t0:=clock_timestamp();
      begin v:=crm.gestion_diaria_avisos_fn(); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,50)); end;
      dur[fase]:=dur[fase]||jsonb_build_object(nombres[a]||':avisos', round(extract(epoch from clock_timestamp()-t0)*1000));
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':avisos', md5((case when jsonb_typeof(v)='object' then v - 'generado_en' - 'calculado_en' - 'pendientes_al' - 'consultado_en' else v end)::text));
      t0:=clock_timestamp();
      begin v:=crm.gestion_diaria_equipo_fn(hoy, null); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,50)); end;
      dur[fase]:=dur[fase]||jsonb_build_object(nombres[a]||':equipo_null', round(extract(epoch from clock_timestamp()-t0)*1000));
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':equipo_null', md5((case when jsonb_typeof(v)='object' then v - 'generado_en' - 'calculado_en' - 'pendientes_al' - 'consultado_en' else v end)::text));
      begin v:=crm.gestion_diaria_equipo_fn(hoy, actores[a]); exception when others then v:=to_jsonb('ERROR '||sqlstate||' '||left(sqlerrm,50)); end;
      res[fase]:=res[fase]||jsonb_build_object(nombres[a]||':equipo_yo', md5((case when jsonb_typeof(v)='object' then v - 'generado_en' - 'calculado_en' - 'pendientes_al' - 'consultado_en' else v end)::text));
    end loop;
  end loop;
  for k in select jsonb_object_keys(res[1]) loop
    if res[1]->>k = res[2]->>k then iguales:=iguales+1; else distintos:=distintos||(k||' antes='||(res[1]->>k)||' despues='||coalesce(res[2]->>k,'(sin valor)')); end if;
  end loop;
  raise exception E'ENSAYO DESHECHO (rollback)\ncasos iguales: % · distintos: %\n%\nDURACIONES antes: %\nDURACIONES despues: %',
    iguales, cardinality(distintos), array_to_string(distintos,E'\n'), dur[1]::text, dur[2]::text;
end $do$;
