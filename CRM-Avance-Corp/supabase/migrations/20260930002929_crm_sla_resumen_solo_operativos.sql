-- ============================================================================
-- Resumen de avisos SLA: el adaptador evalúa solo las oportunidades que pueden avisar
-- (crm.avisos_sla_resumen_v2_fn + private.sla_leads_operativos)
-- ============================================================================
-- Paso 4 · fase 1 del refactor por módulos, aprobado por Miguel el 29/09/2026 («DALE»).
-- Nota del vault: «CRM - perfil de carga lectura vs escritura (2026-09-29)».
--
-- Problema medido (29/09, producción, como gerencia): el resumen tarda 1.735–1.749 ms y es la puerta
-- que más tiempo total consume (9.540 llamadas en 4 días). Pide al núcleo TODAS las oportunidades
-- activas (2.583) con `sla_operacion_autorizada(null,true)`: el núcleo evalúa una a una la regla
-- completa y arma su ficha, y el resumen solo cuenta. 1.139 de esas 2.583 están descartadas o
-- convertidas: son «lead_terminal» en `private.sla_operacion_leads` y nunca producen avisos ni
-- «pendientes», así que no aportan nada a las cuatro cifras ni a `proximo_cambio_en`.
--
-- Cambio: el adaptador pasa al núcleo solo los ids de las oportunidades activas en etapa comercial
-- (`private.sla_leads_operativos()`, las mismas cuatro etapas no terminales del núcleo). El núcleo,
-- su autoridad, su reloj y las demás puertas que lo usan NO cambian. El ayudante vive en `private`
-- porque `assert_sla_avisos` prohíbe a los adaptadores `crm.*` leer `crm.leads`; es INVOKER (solo lo
-- llama este adaptador DEFINER, así corre como postgres) y sin ejecutores de la API.
--
-- Prototipo medido en producción (deshecho): resumen IDÉNTICO para gerencia, supervisor con bandeja y
-- dos analistas; gerencia 1.749 → 1.196 ms, supervisor 800 → 629 ms (filas evaluadas 2.583 → 1.444).
--
-- Huellas (md5 de pg_get_functiondef): adaptador vivo 7b5f75dfb6ac3e480659bdef3dc5ac0f → nuevo e9ce617ab0cc33bc5614ef69e877cc71; ayudante 8d478d783e4c591662388ddf7405058a.
-- Idempotente y fail-closed; al final ejecuta private.assert_sla_avisos() (que llama a assert_sla_nucleo):
-- si el guardián del SLA no está conforme, la transacción se deshace.
-- Reversa: supabase/scripts/sla-resumen-operativos/reversa.sql (restaura el adaptador vivo, retira el
-- ayudante y vuelve a pasar el guardián; conserva la fila de schema_migrations).

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

commit;
