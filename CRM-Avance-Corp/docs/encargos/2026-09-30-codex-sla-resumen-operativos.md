ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 3: toca el adaptador del núcleo SLA `crm.avisos_sla_resumen_v2_fn` —
SECURITY DEFINER, ejecutable por `authenticated`— y añade un ayudante en `private`; no cambia el núcleo ni
policies ni grants de tablas). Intenta REFUTAR; no confirmes por cortesía. Sin base ni red: todo transcrito.
Responde con VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia citada,
RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia.

## Contexto medido (29/09/2026, producción, transacciones deshechas)
`crm.avisos_sla_resumen_v2_fn()` (contador de avisos de Hoy) tarda 1.735–1.792 ms como gerencia y 800–813 ms
como supervisor; es la puerta con más tiempo total (9.540 llamadas/4 días). Llama a
`private.sla_operacion_autorizada(null,true)`: el núcleo (`private.sla_operacion_leads`) evalúa la regla
completa y arma la ficha JSON de TODAS las oportunidades activas visibles (2.583 para gerencia) y el
adaptador solo cuenta. Desglose: bucle plpgsql ≈1.000 ms, SELECT del bucle 174 ms, post-proceso JSON ≈550 ms.
Leads activos por etapa: descartado 986, contactado 841, nuevo 395, reunion_agendada 158, convertido 153,
propuesta_enviada 50 → 1.444 en etapa comercial, 1.139 terminales.

En el núcleo (`private.sla_operacion_leads`, cuerpo vivo; NO se toca):
```
    v_terminal:=h.etapa_actual not in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
    ...
    if v_terminal then v_motivos:=array_append(v_motivos,'lead_terminal'); end if;
    v_usable:=h.activo is true and not v_terminal and not v_vetado;
    ... (todo aviso, señal «pendientes», proximo_cambio_en y acción exigen v_usable) ...
```
`private.sla_hechos_actuales(p_lead_ids,p_global,p_visibles)`: `where (l.activo is true or p_lead_ids is not null)
and (p_lead_ids is null or l.id=any(p_lead_ids)) and (p_global is true or l.vendedor_id=any(p_visibles) or
(l.vendedor_id is null and l.asignado_supervisor_id=any(p_visibles)))`.
`private.sla_operacion_autorizada(p_lead_ids uuid[], p_incluir_operacion boolean)` (DEFINER): resuelve actor,
rol, lector global y `v_visibles`; valida `array_position(p_lead_ids,null) is not null` → 22023; devuelve
`{version, modelo_avisos, proximo_cambio_en = min(filas.estado.operacion.proximo_cambio_en), modo,
control_revision, calculado_en, primera_activacion_en, activacion_hipotetica_en, politica_operativa_id,
politica_operativa_version, politica_adopcion_id, filas, contexto_ambito = md5(actor,rol,global,visibles)}`.

Adaptador vivo (plpgsql, STABLE, DEFINER, search_path '', ACL {postgres=X/postgres,authenticated=X/postgres}):
```sql
declare v_datos jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  v_datos:=private.sla_operacion_autorizada(null,true);
  with filas as materialized (
    select f.value from jsonb_array_elements(v_datos->'filas') f
    where v_datos->>'modo'='activo' and (f.value#>>'{senales,pendientes}')::boolean
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.value#>'{estado,avisos}') a
  ), grupos as (
    select a.value->>'bucket' as bucket,count(*) as total, min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select count(*) from filas),(select count(*) from avisos),
    (select count(*) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_total,v_avisos,v_criticas,v_grupos;
  return (v_datos-'filas'-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
```
Guardián vivo `private.assert_sla_avisos()` (llama a `assert_sla_nucleo()`): exige que el adaptador consuma
`private.sla_operacion_autorizada(`, que su cuerpo NO contenga `crm.(leads|tareas|actividades|lead_sla_etapas)`
(«adaptador lee hechos crudos»), y que `anon`/`service_role` no tengan EXECUTE y `authenticated` sí.

## Cambio
Adaptador: la única línea que cambia es
```sql
-  v_datos:=private.sla_operacion_autorizada(null,true);
+  v_datos:=private.sla_operacion_autorizada(private.sla_leads_operativos(),true);
```
Ayudante nuevo (INVOKER, STABLE, search_path '', ACL solo postgres tras revoke a public/anon/authenticated/service_role):
```sql
CREATE OR REPLACE FUNCTION private.sla_leads_operativos() RETURNS uuid[] LANGUAGE sql STABLE SET search_path TO '' AS $$
  select coalesce(array_agg(l.id order by l.id), '{}'::uuid[])
  from crm.leads l
  where l.activo is true
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');
$$;
```
Argumento de equivalencia: el resumen solo usa filas con `senales.pendientes=true`, sus `estado.avisos`, y
`proximo_cambio_en` (mínimo sobre filas); en el núcleo las tres cosas exigen `v_usable`, que es falso para todo
lead terminal (`v_terminal` con las MISMAS cuatro etapas). Las claves restantes de `v_datos` (modo, control,
políticas, calculado_en, activación) no dependen de las filas. Con ids explícitos, `sla_hechos_actuales` aplica
la misma visibilidad por actor; solo excluye leads activos terminales, que nunca aportan. Array vacío → 0 filas
→ mismas cifras 0 que antes. Corre como postgres (el adaptador es DEFINER), así que el ayudante ve todos los
leads y el núcleo recorta por actor, como antes.

## Oráculo en producción (una transacción deshecha)
4 actores (gerencia, supervisor con bandeja, 2 analistas con más leads operativos): md5 del resumen (sin
`calculado_en`) + controles `estado_sla_leads_v2_fn(5 ids)` y `cola_accion_v3_fn()`: **12/12 iguales**;
`assert_sla_avisos()` tras el cambio: «OK: avisos derivados del nucleo, con autoridad y resumen completo».
Tiempos: gerencia 1.792 → 1.130 ms; supervisor 813 → 633; analistas 109 → 118 (el ayudante cuesta ~8 ms;
para ellos el núcleo ya evaluaba pocas filas). Prototipo previo con las cifras: idéntico en 4 roles.
Ciclo migración → repetida (idempotente) → reversa (restaura adaptador, drop del ayudante, guardián OK) →
migración → registrador, ensayado en producción con rollback; después: huella viva 7b5f75df…, sin ayudante,
0 registros.

## Migración completa `supabase/migrations/20260930002929_crm_sla_resumen_solo_operativos.sql`
```sql
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
-- Huellas (md5 de pg_get_functiondef del adaptador): viva 7b5f75dfb6ac3e480659bdef3dc5ac0f → nueva e9ce617ab0cc33bc5614ef69e877cc71.
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
    raise notice 'sla_resumen_solo_operativos: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> '7b5f75dfb6ac3e480659bdef3dc5ac0f' then
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
  if v_md5 <> 'e9ce617ab0cc33bc5614ef69e877cc71' then
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
```

## Reversa completa `supabase/scripts/sla-resumen-operativos/reversa.sql` (el bloque `$def$` es el adaptador vivo de arriba)
```sql
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
<adaptador vivo completo>
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

```

## Qué refutar
R1. Equivalencia: ¿algún camino por el que un lead activo en etapa terminal aporte a `total_oportunidades`,
`total_avisos`, `criticas`, `grupos` o `proximo_cambio_en`? ¿Y `activacion_hipotetica_en`/`modo`/`control_revision`?
R2. Rol y visibilidad: al pasar ids explícitos, `sla_hechos_actuales` deja de exigir `l.activo` («or p_lead_ids
is not null»); el ayudante solo devuelve activos. ¿Algún actor (lector global/directorio, supervisor con bandeja,
coordinador) ve distinto? ¿El ayudante INVOKER podría correr alguna vez bajo RLS de `crm.leads` y devolver un
subconjunto (¿quién más podría llamarlo?)?
R3. Guardián y seguridad: el adaptador sigue DEFINER con ACL exacta (el postflight la exige); el ayudante sin
ejecutores de la API; `assert_sla_nucleo` comprueba propiedades solo de sus funciones listadas. ¿Falta alguna
comprobación o revoke? ¿El `revoke ... from public` dentro del DO cubre el default `EXECUTE` a PUBLIC?
R4. Migración/reversa/registro: guardas `is not true`, ACL no nula, ruta idempotente (huella nueva Y ayudante
presente), postflight + guardián; reversa: `drop function if exists` del ayudante y guardián; ¿algún orden que
deje el sistema a medias si algo falla?
R5. ¿Tiene sentido aplicar lo mismo a `private.gestion_diaria_alertas_sla` y `gestion_diaria_equipo_pendientes`
(también `sla_operacion_autorizada(null,true)`, 1,2 y 1,6 s)? Están sellados por md5 en
`assert_gestion_diaria_alertas_equipo` / `assert_gestion_diaria_equipo`; se dejan para una fase aparte.
