-- ENSAYO DESHECHO del ciclo (migración → repetida → NEGATIVOS → reversa → reversa con ayudante huérfano → migración → registrador): cuerpos sin begin/commit; termina en raise y rollback.
begin;
set local lock_timeout = '10s';
do $mig$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del adaptador vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'e9ce617ab0cc33bc5614ef69e877cc71' and to_regprocedure('private.sla_leads_operativos()') is not null then
    -- Ruta «ya aplicada» (Codex r1 P2): exige los MISMOS invariantes y la huella del ayudante, y pasa el
    -- guardián, antes de dar la migración por hecha. Que exista el ayudante no prueba que sea el esperado.
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
    if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes esperados (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
    end if;
    if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene la huella esperada (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
    end if;
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'PREFLIGHT: crm.avisos_sla_resumen_v2_fn() no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  -- 1) el ayudante (idempotente)
  execute $def$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$
$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  execute $c$comment on function private.sla_leads_operativos() is 'Ids de las oportunidades activas en etapa comercial (las cuatro etapas no terminales de private.sla_operacion_leads). Solo para adaptadores del núcleo SLA que cuentan avisos: el núcleo aplica después su propia visibilidad. Sin PII; vacío = {}.'$c$;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedó como se esperaba (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception 'POSTFLIGHT: huella inesperada del ayudante (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;

  -- 2) el adaptador
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'POSTFLIGHT: huella inesperada del adaptador tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del adaptador cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;

  -- 3) el guardián del SLA tiene la última palabra
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'sla_resumen_solo_operativos: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h1', md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure))||' helper='||coalesce(to_regprocedure('private.sla_leads_operativos()')::text,'NO'), true);
do $mig$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del adaptador vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'e9ce617ab0cc33bc5614ef69e877cc71' and to_regprocedure('private.sla_leads_operativos()') is not null then
    -- Ruta «ya aplicada» (Codex r1 P2): exige los MISMOS invariantes y la huella del ayudante, y pasa el
    -- guardián, antes de dar la migración por hecha. Que exista el ayudante no prueba que sea el esperado.
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
    if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes esperados (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
    end if;
    if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene la huella esperada (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
    end if;
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'PREFLIGHT: crm.avisos_sla_resumen_v2_fn() no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  -- 1) el ayudante (idempotente)
  execute $def$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$
$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  execute $c$comment on function private.sla_leads_operativos() is 'Ids de las oportunidades activas en etapa comercial (las cuatro etapas no terminales de private.sla_operacion_leads). Solo para adaptadores del núcleo SLA que cuentan avisos: el núcleo aplica después su propia visibilidad. Sin PII; vacío = {}.'$c$;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedó como se esperaba (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception 'POSTFLIGHT: huella inesperada del ayudante (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;

  -- 2) el adaptador
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'POSTFLIGHT: huella inesperada del adaptador tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del adaptador cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;

  -- 3) el guardián del SLA tiene la última palabra
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'sla_resumen_solo_operativos: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h1b', md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure))||' helper='||coalesce(to_regprocedure('private.sla_leads_operativos()')::text,'NO'), true);

do $neg$ begin
  execute $alt$create or replace function private.sla_leads_operativos() returns uuid[] language sql stable set search_path to '' as 'select ''{}''::uuid[]'$alt$;
  begin execute $x$do $mig$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del adaptador vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'e9ce617ab0cc33bc5614ef69e877cc71' and to_regprocedure('private.sla_leads_operativos()') is not null then
    -- Ruta «ya aplicada» (Codex r1 P2): exige los MISMOS invariantes y la huella del ayudante, y pasa el
    -- guardián, antes de dar la migración por hecha. Que exista el ayudante no prueba que sea el esperado.
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
    if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes esperados (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
    end if;
    if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene la huella esperada (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
    end if;
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'PREFLIGHT: crm.avisos_sla_resumen_v2_fn() no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  -- 1) el ayudante (idempotente)
  execute $def$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$
$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  execute $c$comment on function private.sla_leads_operativos() is 'Ids de las oportunidades activas en etapa comercial (las cuatro etapas no terminales de private.sla_operacion_leads). Solo para adaptadores del núcleo SLA que cuentan avisos: el núcleo aplica después su propia visibilidad. Sin PII; vacío = {}.'$c$;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedó como se esperaba (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception 'POSTFLIGHT: huella inesperada del ayudante (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;

  -- 2) el adaptador
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'POSTFLIGHT: huella inesperada del adaptador tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del adaptador cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;

  -- 3) el guardián del SLA tiene la última palabra
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'sla_resumen_solo_operativos: aplicada (huella %)', v_md5;
end $mig$;$x$; raise exception 'NEG1 FALLO';
  exception when others then if sqlerrm like 'NEG1%%' then raise; end if; perform set_config('ensayo.neg1', left(sqlerrm, 110), true); end;
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
  execute 'grant execute on function private.sla_leads_operativos() to authenticated';
  begin execute $x$do $mig$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del adaptador vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'e9ce617ab0cc33bc5614ef69e877cc71' and to_regprocedure('private.sla_leads_operativos()') is not null then
    -- Ruta «ya aplicada» (Codex r1 P2): exige los MISMOS invariantes y la huella del ayudante, y pasa el
    -- guardián, antes de dar la migración por hecha. Que exista el ayudante no prueba que sea el esperado.
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
    if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes esperados (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
    end if;
    if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene la huella esperada (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
    end if;
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'PREFLIGHT: crm.avisos_sla_resumen_v2_fn() no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  -- 1) el ayudante (idempotente)
  execute $def$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$
$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  execute $c$comment on function private.sla_leads_operativos() is 'Ids de las oportunidades activas en etapa comercial (las cuatro etapas no terminales de private.sla_operacion_leads). Solo para adaptadores del núcleo SLA que cuentan avisos: el núcleo aplica después su propia visibilidad. Sin PII; vacío = {}.'$c$;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedó como se esperaba (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception 'POSTFLIGHT: huella inesperada del ayudante (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;

  -- 2) el adaptador
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'POSTFLIGHT: huella inesperada del adaptador tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del adaptador cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;

  -- 3) el guardián del SLA tiene la última palabra
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'sla_resumen_solo_operativos: aplicada (huella %)', v_md5;
end $mig$;$x$; raise exception 'NEG2 FALLO';
  exception when others then if sqlerrm like 'NEG2%%' then raise; end if; perform set_config('ensayo.neg2', left(sqlerrm, 110), true); end;
  execute 'revoke execute on function private.sla_leads_operativos() from authenticated';
end $neg$;

do $rev$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se toca', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    -- Ya está el adaptador vivo; si quedó un ayudante huérfano (solo alcanzable a mano), se retira (auditor-rls P3-2).
    execute 'drop function if exists private.sla_leads_operativos()';
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'REVERSA: ya está el adaptador vivo del 29/09 (%); ayudante retirado si existía', v_md5; return;
  end if;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then raise exception 'REVERSA: huella desconocida del adaptador (%), no se toca', v_md5; end if;
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  execute 'drop function if exists private.sla_leads_operativos()';
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: tras restaurar, invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'REVERSA_SLA_RESUMEN_OK (%)', v_md5;
end $rev$;
select set_config('ensayo.h2', md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure))||' helper='||coalesce(to_regprocedure('private.sla_leads_operativos()')::text,'NO'), true);
do $orf$ begin execute $def$CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$$def$; end $orf$;
do $rev$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se toca', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    -- Ya está el adaptador vivo; si quedó un ayudante huérfano (solo alcanzable a mano), se retira (auditor-rls P3-2).
    execute 'drop function if exists private.sla_leads_operativos()';
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'REVERSA: ya está el adaptador vivo del 29/09 (%); ayudante retirado si existía', v_md5; return;
  end if;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then raise exception 'REVERSA: huella desconocida del adaptador (%), no se toca', v_md5; end if;
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  execute 'drop function if exists private.sla_leads_operativos()';
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: tras restaurar, invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'REVERSA_SLA_RESUMEN_OK (%)', v_md5;
end $rev$;
select set_config('ensayo.h2b', md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure))||' helper='||coalesce(to_regprocedure('private.sla_leads_operativos()')::text,'NO'), true);
do $mig$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path del adaptador vivo no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'e9ce617ab0cc33bc5614ef69e877cc71' and to_regprocedure('private.sla_leads_operativos()') is not null then
    -- Ruta «ya aplicada» (Codex r1 P2): exige los MISMOS invariantes y la huella del ayudante, y pasa el
    -- guardián, antes de dar la migración por hecha. Que exista el ayudante no prueba que sea el esperado.
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
    if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene los invariantes esperados (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
    end if;
    if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
      raise exception 'PREFLIGHT (ya aplicada): el ayudante no tiene la huella esperada (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
    end if;
    raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 is distinct from '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
    raise exception 'PREFLIGHT: crm.avisos_sla_resumen_v2_fn() no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  -- 1) el ayudante (idempotente)
  execute $def$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$
$def$;
  execute 'revoke all on function private.sla_leads_operativos() from public, anon, authenticated, service_role';
  execute $c$comment on function private.sla_leads_operativos() is 'Ids de las oportunidades activas en etapa comercial (las cuatro etapas no terminales de private.sla_operacion_leads). Solo para adaptadores del núcleo SLA que cuentan avisos: el núcleo aplica después su propia visibilidad. Sin PII; vacío = {}.'$c$;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedó como se esperaba (dueño %, acl %, definer %, vol %, cfg %)', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception 'POSTFLIGHT: huella inesperada del ayudante (%)', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;

  -- 2) el adaptador
  execute $def$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'POSTFLIGHT: huella inesperada del adaptador tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path del adaptador cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;

  -- 3) el guardián del SLA tiene la última palabra
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'sla_resumen_solo_operativos: aplicada (huella %)', v_md5;
end $mig$;
select set_config('ensayo.h3', md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure))||' helper='||coalesce(to_regprocedure('private.sla_leads_operativos()')::text,'NO'), true);
do $chk$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'REGISTRO: el adaptador no tiene la huella nueva (%); aplica primero la migración 20260930002929', v_md5;
  end if;
  -- Invariantes del adaptador que la huella NO cubre: dueño, ACL exacta (postgres + authenticated, que exige
  -- assert_sla_avisos), DEFINER, STABLE y search_path vacío (se guarda como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se registra', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if to_regprocedure('private.sla_leads_operativos()') is null then raise exception 'REGISTRO: falta private.sla_leads_operativos()'; end if;
  select pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into h_owner, h_acl, h_secdef, h_vol, h_cfg from pg_proc p where p.oid = 'private.sla_leads_operativos()'::regprocedure;
  if (h_owner = 'postgres' and h_acl is not null and h_acl = '{postgres=X/postgres}' and h_secdef is false and h_vol = 's'
    and exists (select 1 from unnest(h_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: invariantes del ayudante incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se registra', h_owner, h_acl, h_secdef, h_vol, h_cfg;
  end if;
  if md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception 'REGISTRO: el ayudante no tiene la huella esperada (%); no se registra', md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure));
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930002929' and coalesce(name,'') <> 'crm_sla_resumen_solo_operativos') then
    raise exception 'REGISTRO: la versión 20260930002929 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930002929', 'crm_sla_resumen_solo_operativos', array[$stm$
CREATE OR REPLACE FUNCTION private.sla_leads_operativos()
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
$function$
$stm$, $stm$
CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
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
$function$
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930002929' and name = 'crm_sla_resumen_solo_operativos') then
    raise exception 'REGISTRO: tras el insert, la versión 20260930002929 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_SLA_RESUMEN_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260930002929';
do $$ begin
  raise exception E'CICLO (rollback)\nmig: %\nmig repetida: %\nNEG1: %\nNEG2: %\nreversa: %\nreversa repetida con ayudante huérfano: %\nmig otra vez: %\nregistro: %',
    current_setting('ensayo.h1',true), current_setting('ensayo.h1b',true), current_setting('ensayo.neg1',true), current_setting('ensayo.neg2',true), current_setting('ensayo.h2',true), current_setting('ensayo.h2b',true), current_setting('ensayo.h3',true),
    (select version||' / '||name||' / '||cardinality(statements)||' sentencia(s)' from supabase_migrations.schema_migrations where version='20260930002929');
end $$;
rollback;
