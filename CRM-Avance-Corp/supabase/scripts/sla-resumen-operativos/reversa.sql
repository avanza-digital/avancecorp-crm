-- REVERSA de 20260930002929_crm_sla_resumen_solo_operativos: restaura el adaptador VIVO del 29/09/2026 tal cual, retira el ayudante y vuelve a pasar el
-- guardián del SLA. Se niega si el adaptador no tiene la huella nueva o sus invariantes. NO toca schema_migrations
-- (anotarlo en MIGRACIONES.md el mismo día).
begin;
set local lock_timeout = '10s';
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
  if v_md5 = '7b5f75dfb6ac3e480659bdef3dc5ac0f' and to_regprocedure('private.sla_leads_operativos()') is null then raise notice 'REVERSA: ya está el adaptador vivo del 29/09 (%)', v_md5; return; end if;
  if v_md5 <> 'e9ce617ab0cc33bc5614ef69e877cc71' then raise exception 'REVERSA: huella desconocida del adaptador (%), no se toca', v_md5; end if;
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
  if v_md5 <> '7b5f75dfb6ac3e480659bdef3dc5ac0f' then raise exception 'REVERSA: la huella restaurada no coincide (%)', v_md5; end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres,authenticated=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: tras restaurar, invariantes del adaptador incorrectos (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'REVERSA_SLA_RESUMEN_OK (%)', v_md5;
end $rev$;
commit;
