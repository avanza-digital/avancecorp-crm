-- ENSAYO DESHECHO del ciclo (migración → repetida → 3 NEGATIVOS → reversa → migración → registrador): cuerpos sin begin/commit; termina en raise y rollback.
begin;
set local lock_timeout = '10s';
do $mig$
declare
  v_md5 text; v_oid oid := 'private.assert_sla_avisos()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño y ACL exacta (nunca NULL); DEFINER, STABLE y search_path vacío (guardado
  -- como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del guardián vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'c90f23b049f1777eef68db925d6b8b57' then
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_vigilante_ayudante: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from 'bf835965ea92cb14265b08b5e5b4f121' then
    raise exception 'PREFLIGHT: private.assert_sla_avisos() no es el cuerpo vivo del 30/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  -- Vigilante del ayudante (30/09/2026, auditor-rls P2-2): existe con su huella, dueño postgres, INVOKER, STABLE,
  -- search_path vacío y sin ejecutores de la API; y el resumen se lo pasa al núcleo (no vuelve a pedir TODAS las
  -- oportunidades). Si el ayudante cambia legítimamente, se resella aquí en la misma migración.
  if to_regprocedure('private.sla_leads_operativos()') is null then
    raise exception 'SLA avisos: falta el ayudante private.sla_leads_operativos()';
  end if;
  if not exists (select 1 from pg_proc p where p.oid='private.sla_leads_operativos()'::regprocedure
      and md5(pg_get_functiondef(p.oid))='8d478d783e4c591662388ddf7405058a'
      and p.proowner='postgres'::regrole and p.prosecdef is false and p.provolatile='s'
      and p.proconfig=array['search_path=""'] and p.proacl::text='{postgres=X/postgres}') then
    raise exception 'SLA avisos: el ayudante sla_leads_operativos no es el esperado (huella, dueño, definer, volatilidad, search_path o permisos)';
  end if;
  select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
    into strict v_cuerpo from pg_proc p where p.oid='crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  if v_cuerpo !~ '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,' then
    raise exception 'SLA avisos: el resumen dejo de evaluar solo las oportunidades operativas';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'c90f23b049f1777eef68db925d6b8b57' then
    raise exception 'POSTFLIGHT: huella inesperada del guardián (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del guardián cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'sla_vigilante_ayudante: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h1', md5(pg_get_functiondef('private.assert_sla_avisos()'::regprocedure)), true);
do $mig$
declare
  v_md5 text; v_oid oid := 'private.assert_sla_avisos()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño y ACL exacta (nunca NULL); DEFINER, STABLE y search_path vacío (guardado
  -- como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del guardián vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'c90f23b049f1777eef68db925d6b8b57' then
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_vigilante_ayudante: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from 'bf835965ea92cb14265b08b5e5b4f121' then
    raise exception 'PREFLIGHT: private.assert_sla_avisos() no es el cuerpo vivo del 30/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  -- Vigilante del ayudante (30/09/2026, auditor-rls P2-2): existe con su huella, dueño postgres, INVOKER, STABLE,
  -- search_path vacío y sin ejecutores de la API; y el resumen se lo pasa al núcleo (no vuelve a pedir TODAS las
  -- oportunidades). Si el ayudante cambia legítimamente, se resella aquí en la misma migración.
  if to_regprocedure('private.sla_leads_operativos()') is null then
    raise exception 'SLA avisos: falta el ayudante private.sla_leads_operativos()';
  end if;
  if not exists (select 1 from pg_proc p where p.oid='private.sla_leads_operativos()'::regprocedure
      and md5(pg_get_functiondef(p.oid))='8d478d783e4c591662388ddf7405058a'
      and p.proowner='postgres'::regrole and p.prosecdef is false and p.provolatile='s'
      and p.proconfig=array['search_path=""'] and p.proacl::text='{postgres=X/postgres}') then
    raise exception 'SLA avisos: el ayudante sla_leads_operativos no es el esperado (huella, dueño, definer, volatilidad, search_path o permisos)';
  end if;
  select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
    into strict v_cuerpo from pg_proc p where p.oid='crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  if v_cuerpo !~ '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,' then
    raise exception 'SLA avisos: el resumen dejo de evaluar solo las oportunidades operativas';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'c90f23b049f1777eef68db925d6b8b57' then
    raise exception 'POSTFLIGHT: huella inesperada del guardián (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del guardián cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'sla_vigilante_ayudante: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h1b', md5(pg_get_functiondef('private.assert_sla_avisos()'::regprocedure)), true);

-- NEGATIVOS: con el guardián ampliado aplicado, cada alteración debe hacerlo saltar (cada una en su subtransacción, deshecha).
do $neg$ declare g text; begin
  -- NEG1: permiso de más al ayudante
  begin
    execute 'grant execute on function private.sla_leads_operativos() to authenticated';
    g := private.assert_sla_avisos();
    raise exception 'NEG1 FALLO: el guardián aceptó un ayudante ejecutable por authenticated';
  exception when others then if sqlerrm like 'NEG1%%' then raise; end if; perform set_config('ensayo.neg1', left(sqlerrm,110), true); end;
  execute 'revoke execute on function private.sla_leads_operativos() from authenticated';
  -- NEG2: cuerpo del ayudante alterado
  begin
    execute $alt$create or replace function private.sla_leads_operativos() returns uuid[] language sql stable set search_path to '' as 'select ''{}''::uuid[]'$alt$;
    g := private.assert_sla_avisos();
    raise exception 'NEG2 FALLO: el guardián aceptó un ayudante con otro cuerpo';
  exception when others then if sqlerrm like 'NEG2%%' then raise; end if; perform set_config('ensayo.neg2', left(sqlerrm,110), true); end;
  execute $def$CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
 RETURNS uuid[]
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- Ids de las oportunidades activas en etapa comercial: las mismas cuatro etapas que
  -- private.sla_operacion_leads considera NO terminales (v_terminal). Sin PII; el núcleo
  -- aplica después su propia visibilidad por actor. Nunca NULL: vacío = '{}'.
  select coalesce(array_agg(l.id order by l.id), '{}'::uuid[])
  from crm.leads l
  where l.activo is true
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
$function$$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  -- NEG3: el resumen vuelve a pedir todas las oportunidades
  begin
    execute $def$CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_datos jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  -- Misma ventana autorizada y mismo instante que ficha y cola. El conteo
  -- incluye toda la cartera visible, sin depender del lote local ni pagina.
  v_datos:=private.sla_operacion_autorizada(null,true);
  with filas as materialized (
    select f.value from jsonb_array_elements(v_datos->'filas') f
    where v_datos->>'modo'='activo' and (f.value#>>'{senales,pendientes}')::boolean
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.value#>'{estado,avisos}') a
  ), grupos as (
    select a.value->>'bucket' as bucket,count(*) as total,
      min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select count(*) from filas),(select count(*) from avisos),
    (select count(*) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_total,v_avisos,v_criticas,v_grupos;
  return (v_datos-'filas'-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
$function$$def$;
    g := private.assert_sla_avisos();
    raise exception 'NEG3 FALLO: el guardián aceptó el resumen sin el ayudante';
  exception when others then if sqlerrm like 'NEG3%%' then raise; end if; perform set_config('ensayo.neg3', left(sqlerrm,110), true); end;
  execute $def$CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_datos jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  -- Misma ventana autorizada y mismo instante que ficha y cola. El conteo
  -- incluye toda la cartera visible, sin depender del lote local ni pagina.
  -- Solo las oportunidades que pueden avisar: activas y en etapa comercial (las descartadas y
  -- convertidas son «lead_terminal» en el núcleo y nunca producen avisos ni «pendientes»; 1.139 de
  -- 2.583 el 29/09/2026). El núcleo, su autoridad y su reloj no cambian; el ayudante vive en
  -- private porque este adaptador no puede leer hechos crudos (assert_sla_avisos).
  v_datos:=private.sla_operacion_autorizada(private.sla_leads_operativos(),true);
  with filas as materialized (
    select f.value from jsonb_array_elements(v_datos->'filas') f
    where v_datos->>'modo'='activo' and (f.value#>>'{senales,pendientes}')::boolean
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.value#>'{estado,avisos}') a
  ), grupos as (
    select a.value->>'bucket' as bucket,count(*) as total,
      min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select count(*) from filas),(select count(*) from avisos),
    (select count(*) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_total,v_avisos,v_criticas,v_grupos;
  return (v_datos-'filas'-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
$function$$def$;
  g := private.assert_sla_avisos();
  perform set_config('ensayo.restaurado', g, true);
end $neg$;

do $rev$
declare
  v_md5 text; v_oid oid := 'private.assert_sla_avisos()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño y ACL exacta (nunca NULL); DEFINER, STABLE y search_path vacío (guardado
  -- como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: invariantes del guardián incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se toca', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'bf835965ea92cb14265b08b5e5b4f121' then
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'REVERSA: ya está el guardián vivo del 30/09 (%)', v_md5; return;
  end if;
  if v_md5 is distinct from 'c90f23b049f1777eef68db925d6b8b57' then raise exception 'REVERSA: huella desconocida (%), no se toca', v_md5; end if;
  execute $def$
CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'bf835965ea92cb14265b08b5e5b4f121' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: tras restaurar, invariantes incorrectos (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'REVERSA_VIGILANTE_OK (%)', v_md5;
end $rev$;
select set_config('ensayo.h2', md5(pg_get_functiondef('private.assert_sla_avisos()'::regprocedure)), true);
do $mig$
declare
  v_md5 text; v_oid oid := 'private.assert_sla_avisos()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño y ACL exacta (nunca NULL); DEFINER, STABLE y search_path vacío (guardado
  -- como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del guardián vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'c90f23b049f1777eef68db925d6b8b57' then
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_vigilante_ayudante: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from 'bf835965ea92cb14265b08b5e5b4f121' then
    raise exception 'PREFLIGHT: private.assert_sla_avisos() no es el cuerpo vivo del 30/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  -- Vigilante del ayudante (30/09/2026, auditor-rls P2-2): existe con su huella, dueño postgres, INVOKER, STABLE,
  -- search_path vacío y sin ejecutores de la API; y el resumen se lo pasa al núcleo (no vuelve a pedir TODAS las
  -- oportunidades). Si el ayudante cambia legítimamente, se resella aquí en la misma migración.
  if to_regprocedure('private.sla_leads_operativos()') is null then
    raise exception 'SLA avisos: falta el ayudante private.sla_leads_operativos()';
  end if;
  if not exists (select 1 from pg_proc p where p.oid='private.sla_leads_operativos()'::regprocedure
      and md5(pg_get_functiondef(p.oid))='8d478d783e4c591662388ddf7405058a'
      and p.proowner='postgres'::regrole and p.prosecdef is false and p.provolatile='s'
      and p.proconfig=array['search_path=""'] and p.proacl::text='{postgres=X/postgres}') then
    raise exception 'SLA avisos: el ayudante sla_leads_operativos no es el esperado (huella, dueño, definer, volatilidad, search_path o permisos)';
  end if;
  select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
    into strict v_cuerpo from pg_proc p where p.oid='crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  if v_cuerpo !~ '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,' then
    raise exception 'SLA avisos: el resumen dejo de evaluar solo las oportunidades operativas';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'c90f23b049f1777eef68db925d6b8b57' then
    raise exception 'POSTFLIGHT: huella inesperada del guardián (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del guardián cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'sla_vigilante_ayudante: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h3', md5(pg_get_functiondef('private.assert_sla_avisos()'::regprocedure)), true);
do $chk$
declare
  v_md5 text; v_oid oid := 'private.assert_sla_avisos()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'c90f23b049f1777eef68db925d6b8b57' then
    raise exception 'REGISTRO: el guardián no tiene la huella nueva (%); aplica primero la migración 20260930154341', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño y ACL exacta (nunca NULL); DEFINER, STABLE y search_path vacío (guardado
  -- como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: invariantes del guardián incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se registra', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930154341' and coalesce(name,'') <> 'crm_sla_vigilante_ayudante') then
    raise exception 'REGISTRO: la versión 20260930154341 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930154341', 'crm_sla_vigilante_ayudante', array[$stm$
CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  -- Vigilante del ayudante (30/09/2026, auditor-rls P2-2): existe con su huella, dueño postgres, INVOKER, STABLE,
  -- search_path vacío y sin ejecutores de la API; y el resumen se lo pasa al núcleo (no vuelve a pedir TODAS las
  -- oportunidades). Si el ayudante cambia legítimamente, se resella aquí en la misma migración.
  if to_regprocedure('private.sla_leads_operativos()') is null then
    raise exception 'SLA avisos: falta el ayudante private.sla_leads_operativos()';
  end if;
  if not exists (select 1 from pg_proc p where p.oid='private.sla_leads_operativos()'::regprocedure
      and md5(pg_get_functiondef(p.oid))='8d478d783e4c591662388ddf7405058a'
      and p.proowner='postgres'::regrole and p.prosecdef is false and p.provolatile='s'
      and p.proconfig=array['search_path=""'] and p.proacl::text='{postgres=X/postgres}') then
    raise exception 'SLA avisos: el ayudante sla_leads_operativos no es el esperado (huella, dueño, definer, volatilidad, search_path o permisos)';
  end if;
  select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
    into strict v_cuerpo from pg_proc p where p.oid='crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  if v_cuerpo !~ '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,' then
    raise exception 'SLA avisos: el resumen dejo de evaluar solo las oportunidades operativas';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930154341' and name = 'crm_sla_vigilante_ayudante') then
    raise exception 'REGISTRO: tras el insert, la versión 20260930154341 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_VIGILANTE_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260930154341';
do $$ begin
  raise exception E'CICLO (rollback)\nmig: % (esperado c90f23b0…)\nmig repetida: %\nNEG1 permiso de más: %\nNEG2 cuerpo alterado: %\nNEG3 resumen sin ayudante: %\nrestaurado: %\nreversa: % (esperado bf835965…)\nmig otra vez: %\nregistro: %',
    current_setting('ensayo.h1',true), current_setting('ensayo.h1b',true), current_setting('ensayo.neg1',true), current_setting('ensayo.neg2',true), current_setting('ensayo.neg3',true), current_setting('ensayo.restaurado',true),
    current_setting('ensayo.h2',true), current_setting('ensayo.h3',true),
    (select version||' / '||name||' / '||cardinality(statements)||' sentencia(s)' from supabase_migrations.schema_migrations where version='20260930154341');
end $$;
rollback;
