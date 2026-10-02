ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 3: cambia dos funciones SECURITY DEFINER de `private` que alimentan las
pantallas de Gestión Diaria y RESELLA los dos guardianes que las protegen). Intenta REFUTAR; no confirmes por
cortesía. Sin base ni red: todo transcrito. Responde con VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia citada, RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia.

## Contexto
Ya revisaste (y aprobaste en r2) `20260930002929_crm_sla_resumen_solo_operativos`: el ayudante
`private.sla_leads_operativos()` (ids activos en las 4 etapas comerciales, INVOKER, solo postgres, huella
8d478d78…) y el adaptador del contador. Está EN PROD. Ahora el mismo cambio en las dos consultas de Gestión Diaria
que también pedían `sla_operacion_autorizada(null, true)`:
- `private.gestion_diaria_alertas_sla()` (DEFINER, STABLE, search_path '', ACL {postgres, crm_gestion_diaria_lector}):
  agrupa por bucket los avisos de filas con `senales.pendientes=true` (solo supervisor).
- `private.gestion_diaria_equipo_pendientes()` (DEFINER, STABLE, search_path '', ACL {postgres, authenticated}):
  por analista, cuenta filas con `senales.primera_atencion` y `senales.datos_incompletos`; su salida se une por
  `left join sla s on s.analista_id = r.analista_id` al roster (`gestion_diaria_equipo_core`, que no cambia).
Ambas están selladas: `assert_gestion_diaria_alertas_equipo` exige `md5(p.prosrc)` de alertas_sla =
bca4ff0c… (+ definer, 's', search_path, ACL: EXECUTE para crm_gestion_diaria_lector y NO para
authenticated/anon/service_role); `assert_gestion_diaria_equipo` exige `md5(pg_get_functiondef)` de
equipo_pendientes = 6de28503… (+ definer, 's', EXECUTE authenticated, no anon/service_role) y llama a
`assert_gestion_diaria_analista()` y `assert_sla_avisos()`. El paraguas `private.assert_gestion_diaria()`
concatena las salidas de 11 guardianes (los llama; no sella sus huellas). `assert_gestion_diaria_citas` sella el
paraguas por md5 (no se toca).

## Cambio (diff exacto)
En ambas funciones, una línea:
```
-  v_datos := private.sla_operacion_autorizada(null, true);
+  -- Solo las oportunidades que pueden avisar (activas en etapa comercial): las terminales nunca aportan a
+  -- estas cifras (paso 4 · fase 1 del refactor, 30/09/2026). El núcleo y su visibilidad no cambian.
+  v_datos := private.sla_operacion_autorizada(private.sla_leads_operativos(), true);
```
En los dos guardianes, solo la huella: `bca4ff0c…` → `94bbf61cd1133a1ccca6d0fb5f764455` (md5(prosrc) nuevo de
alertas_sla) y `6de28503…` → `034cbb49d4f0fc4c6b5140a32db86b76` (md5(def) nuevo de equipo_pendientes). Nada más.
Huellas de los guardianes resellados: abb5da73… → 02c9cd9f…; 38f2de1b… → 28f82e7d….

Equivalencia: en el núcleo, `senales.pendientes/primera_atencion/datos_incompletos` exigen `v_usable`, falso para
todo lead terminal; alertas usa solo `pendientes=true`; equipo_pendientes agrupa por analista TODAS las filas con
analista → una fila (analista, 0, 0) desaparece si ese analista solo tenía leads terminales; el consumidor hace
`left join` al roster y `coalesce` de los conteos (oráculo: idéntico).

## Evidencia (producción, transacciones deshechas)
- Oráculo ejecutando la MIGRACIÓN real: gerencia y los 4 supervisores × {`gestion_diaria_avisos_fn()`,
  `gestion_diaria_equipo_fn(hoy, null)`, `gestion_diaria_equipo_fn(hoy, yo)`} sin los campos de reloj
  (`generado_en`, `calculado_en`, `pendientes_al`, `consultado_en`): **15/15 iguales**. Tiempos: equipo de gerencia
  1.804 → 1.215 ms; sup1 avisos 1.002 → 848 y equipo 925 → 760; sup3 876 → 620 y 815 → 547; sup2/sup4 ±20 ms.
- Guardianes tras el cambio: paraguas `assert_gestion_diaria()` OK (57 ms) y `assert_sla_avisos()` OK.
- Ciclo migración → repetida (idempotente: exige las 4 huellas nuevas + invariantes + guardianes) → reversa
  (restaura las 4 vivas, guardianes OK) → migración → registrador (4 sentencias); después: huellas vivas intactas,
  0 registros.

## Migración completa `supabase/migrations/20260930150852_crm_gestion_diaria_solo_operativos.sql`
```sql
-- ============================================================================
-- Gestión Diaria: sus dos consultas al núcleo SLA evalúan solo las oportunidades que pueden avisar
-- (private.gestion_diaria_alertas_sla, private.gestion_diaria_equipo_pendientes) + resellado de sus guardianes
-- ============================================================================
-- Paso 4 · fase «Gestión Diaria» del refactor por módulos, aprobado por Miguel el 30/09/2026 («dale»).
-- Nota del vault: «CRM - perfil de carga lectura vs escritura (2026-09-29)».
--
-- Problema medido (30/09, producción): las vistas de Gestión Diaria de supervisión y gerencia piden al núcleo
-- SLA TODAS las oportunidades activas (`sla_operacion_autorizada(null, true)`): equipo de gerencia 1.853 ms,
-- avisos de supervisor hasta 1.031 ms, equipo de supervisor hasta 953 ms. 1.139 de las 2.583 activas son
-- terminales (descartadas/convertidas) y nunca aportan: `gestion_diaria_alertas_sla` solo usa filas con
-- `senales.pendientes`; `gestion_diaria_equipo_pendientes` cuenta `senales.primera_atencion` y
-- `senales.datos_incompletos`, ambas `v_usable and …`, y su salida se une por `left join` al roster del equipo.
--
-- Cambio: las dos funciones pasan al núcleo `private.sla_leads_operativos()` (ayudante del 29/09, migración
-- 20260930002929) en vez de `null`. Como ambas están selladas por huella en sus guardianes
-- (`assert_gestion_diaria_alertas_equipo` por md5(prosrc) de alertas_sla; `assert_gestion_diaria_equipo` por
-- md5(pg_get_functiondef) de equipo_pendientes), la migración RESELLA esos dos guardianes con las huellas
-- nuevas (solo cambia la huella; el resto de cada guardián queda byte a byte) y al final pasa el paraguas
-- `private.assert_gestion_diaria()` y `private.assert_sla_avisos()`: si algo no cuadra, se deshace todo.
-- Ningún adaptador `crm.*`, ninguna policy, ningún grant ni el núcleo cambian.
--
-- Prototipo medido en producción (deshecho): 15/15 idénticos (gerencia y los 4 supervisores × avisos, equipo(null),
-- equipo(yo)); equipo de gerencia 1.853 → 1.232 ms; sup1 avisos 1.031 → 838 y equipo 953 → 738; sup3 889 → 607 y
-- 812 → 539; supervisores pequeños ±20 ms.
--
-- Huellas: alertas_sla md5(prosrc) bca4ff0c4ee591bb405c2e1bedb3082b → 94bbf61cd1133a1ccca6d0fb5f764455; equipo_pendientes md5(def)
-- 6de28503dd0a32bd98de95d1f5de3532 → 034cbb49d4f0fc4c6b5140a32db86b76; assert_alertas_equipo abb5da739e960117f8e2ad8fa2d323d8 → 02c9cd9fe743b311d23df60a8d335c10;
-- assert_equipo 38f2de1b8226fd97abfb5e4588803e0d → 28f82e7d145d1ef9ff9809a9d485613a. Idempotente y fail-closed.
-- Reversa: supabase/scripts/gestion-diaria-operativos/reversa.sql (restaura las cuatro funciones vivas y pasa los guardianes).

begin;
set local lock_timeout = '10s';

do $mig$
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
end $mig$;

commit;
```

## Reversa (los bloques `$def$` son las cuatro definiciones vivas; se abrevian)
```sql
-- REVERSA de 20260930150852_crm_gestion_diaria_solo_operativos: restaura las CUATRO funciones vivas del 30/09/2026 (las dos consultas y sus dos guardianes) tal
-- cual y vuelve a pasar los guardianes. Se niega si no encuentra las huellas nuevas o sus invariantes. NO toca
-- schema_migrations (anotarlo en MIGRACIONES.md el mismo día). No retira el ayudante sla_leads_operativos: es de 20260930002929.
begin;
set local lock_timeout = '10s';
do $rev$
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
      raise exception '%: dueño/ACL/definer/volatilidad/search_path de % no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', 'REVERSA', r.firma, v_owner, v_acl, v_secdef, v_vol, v_cfg;
    end if;
  end loop;
  if to_regprocedure('private.sla_leads_operativos()') is null or md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception '%: falta el ayudante private.sla_leads_operativos() con la huella del 29/09 (migración 20260930002929)', 'REVERSA';
  end if;
  if h_a = 'bca4ff0c4ee591bb405c2e1bedb3082b' and h_p = '6de28503dd0a32bd98de95d1f5de3532' and h_1 = 'abb5da739e960117f8e2ad8fa2d323d8' and h_2 = '38f2de1b8226fd97abfb5e4588803e0d' then
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
    raise notice 'REVERSA: ya están las cuatro funciones vivas del 30/09'; return;
  end if;
  if h_a is distinct from '94bbf61cd1133a1ccca6d0fb5f764455' or h_p is distinct from '034cbb49d4f0fc4c6b5140a32db86b76'
     or h_1 is distinct from '02c9cd9fe743b311d23df60a8d335c10' or h_2 is distinct from '28f82e7d145d1ef9ff9809a9d485613a' then
    raise exception 'REVERSA: huellas desconocidas (alertas %, pendientes %, assert_alertas %, assert_equipo %); no se toca', h_a, h_p, h_1, h_2;
  end if;
  execute $def$ <definición viva> $def$;
  execute $def$ <definición viva> $def$;
  execute $def$ <definición viva> $def$;
  execute $def$ <definición viva> $def$;
  select md5(p.prosrc) into h_a from pg_proc p where p.oid='private.gestion_diaria_alertas_sla()'::regprocedure;
  h_p := md5(pg_get_functiondef('private.gestion_diaria_equipo_pendientes()'::regprocedure));
  h_1 := md5(pg_get_functiondef('private.assert_gestion_diaria_alertas_equipo()'::regprocedure));
  h_2 := md5(pg_get_functiondef('private.assert_gestion_diaria_equipo()'::regprocedure));
  if h_a is distinct from 'bca4ff0c4ee591bb405c2e1bedb3082b' or h_p is distinct from '6de28503dd0a32bd98de95d1f5de3532'
     or h_1 is distinct from 'abb5da739e960117f8e2ad8fa2d323d8' or h_2 is distinct from '38f2de1b8226fd97abfb5e4588803e0d' then
    raise exception 'REVERSA: las huellas restauradas no coinciden (alertas %, pendientes %, assert_alertas %, assert_equipo %)', h_a, h_p, h_1, h_2;
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
      raise exception '%: dueño/ACL/definer/volatilidad/search_path de % no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', 'REVERSA (tras restaurar)', r.firma, v_owner, v_acl, v_secdef, v_vol, v_cfg;
    end if;
  end loop;
  if to_regprocedure('private.sla_leads_operativos()') is null or md5(pg_get_functiondef('private.sla_leads_operativos()'::regprocedure)) is distinct from '8d478d783e4c591662388ddf7405058a' then
    raise exception '%: falta el ayudante private.sla_leads_operativos() con la huella del 29/09 (migración 20260930002929)', 'REVERSA (tras restaurar)';
  end if;
  raise notice 'assert_gestion_diaria: %', left(private.assert_gestion_diaria(), 60);
  raise notice 'assert_sla_avisos: %', private.assert_sla_avisos();
  raise notice 'REVERSA_GD_OK';
end $rev$;
commit;

```

## Qué refutar
R1. Equivalencia de `equipo_pendientes`: la fila (analista, 0, 0) que desaparece — ¿algún consumidor distinto de
`gestion_diaria_equipo_core` (con `left join`) podría notarlo? Consumidores conocidos: solo el core. ¿Y
`gestion_diaria_alertas_sla` → `gestion_diaria_contexto` → `gestion_diaria_avisos_con_contexto`?
R2. Resellado: ¿cambiar solo la huella dentro de los guardianes deja intacto todo lo demás que vigilan (ACL,
definer, volatilidad, search_path, permisos de anon/service_role)? ¿Algún otro guardián o gate (vigencia,
analítica, `assert_gestion_diaria_pendientes/pulso` que llaman a `assert_gestion_diaria_equipo`) sella por md5 los
dos guardianes resellados o las dos funciones y quedaría roto?
R3. Rol `crm_gestion_diaria_lector`: `alertas_sla` es DEFINER ejecutable por ese rol; el ayudante es INVOKER →
dentro del DEFINER corre como postgres. ¿Algún camino en que el ayudante corra bajo RLS y recorte de más?
R4. Guardas de la migración (huellas con `is distinct from`, invariantes con `is not true`, ayudante exigido con su
huella, ruta idempotente con guardianes), orden de los cuatro `create or replace` y atomicidad.
R5. ¿Merece un negativo ensayado (p. ej. guardián resellado que no coincide → la migración se deshace)? Nota: si la
huella nueva del guardián fuese incorrecta, el postflight `h_1/h_2` la rechaza; si la huella que el guardián
exige de la función fuese incorrecta, el paraguas falla → rollback.
