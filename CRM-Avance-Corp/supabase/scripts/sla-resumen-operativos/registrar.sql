-- REGISTRO en supabase_migrations.schema_migrations de 20260930002929_crm_sla_resumen_solo_operativos.
-- Correr DESPUÉS de aplicar. Idempotente; se niega si el adaptador no tiene la huella nueva o sus invariantes,
-- si falta el ayudante, o si la versión ya está registrada con otro nombre; relee la fila antes de confirmar.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_sla_resumen_solo_operativos'));
do $chk$
declare
  v_md5 text; v_oid oid := 'crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  h_owner text; h_acl text; h_secdef boolean; h_vol "char"; h_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'e9ce617ab0cc33bc5614ef69e877cc71' then
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
commit;
