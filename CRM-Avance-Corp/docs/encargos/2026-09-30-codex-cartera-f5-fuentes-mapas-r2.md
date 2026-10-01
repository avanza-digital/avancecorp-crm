ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Segunda ronda (r2) sobre la migración `20260930172255_crm_cartera_f5_fuentes_mapas` (LEVEL 2–3). En r1 pediste dos cambios;
aquí va la respuesta del PRIMARY con evidencia nueva y los SCRIPTS COMPLETOS que pediste ver. Intenta REFUTAR; responde con
VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia, RISKS / TEST GAPS, NEXT ACTIONS,
CONFIDENCE. Sin hallazgo sin evidencia. Sin base ni red: todo está transcrito.

## Respuesta a r1
- **P2-1 (empates a igual nivel) → RECHAZADO con evidencia del esquema:** `crm.operaciones_cartera.contrato_nuevo_id` tiene
  restricción UNIQUE (`operaciones_cartera_contrato_nuevo_id_key`, migración `20260824231133`). La cadena parte de la raíz y
  en cada paso busca `o.contrato_nuevo_id = contrato_id`: como mucho UNA operación por contrato, así que el paseo es una lista
  (un contrato por nivel) y no puede haber dos candidatos «upgrade» al mismo nivel. Prueba empírica en el banco Docker
  (esquema de producción): sembrar dos operaciones con el mismo `contrato_nuevo_id` falla con `duplicate key value violates
  unique constraint "operaciones_cartera_contrato_nuevo_id_key"`. Se ensayó igualmente un desempate delegado a
  `analista_atribuido_cadena` y se RETIRÓ: complicaba el cuerpo para un caso imposible. El cuerpo final es byte a byte el
  validado en producción (huella `fa15f7765d0892c790c7a4b6822e756e`: 726/726 filas md5 igual; 33/33 salidas idénticas).
- **P2-2 (huellas de las dependencias) → ACEPTADO:** preflight de la migración (antes de la ruta idempotente) y del registro
  exigen `md5(pg_get_functiondef)` de `private.inversionista_canonica(uuid)` = `34702897135078893b7d3a726b0c1816` y de
  `private.analista_atribuido_cadena(uuid)` = `3c9cec305b014ad8c933df25057d3e8b` (medidas en producción y en el banco, que
  tiene paridad de cuerpos crm 278 / private 536 con el mismo md5 que prod). Negativo probado en el banco: con
  `inversionista_canonica` sustituida, migración y registro rechazan. La reversa NO las exige (restaura un cuerpo que las llama,
  no las copia).
- Fixture de 17 nodos: tenías razón en la descripción; ahora la prueba sintética lleva expectativas explícitas por caso
  (el nodo 1 de la cadena C10→…→C26 queda como su propia canónica; el nodo 2 llega a la raíz C26 en su nodo 16).
- Tope 100/101 de la cadena: idéntico en ambos cuerpos (`cd.nivel < 100`, visitados); no se sembró (riesgo aceptado).
- Además, el auditor de RLS de la casa (PASS) pidió y se aplicó: REPEATABLE READ en la migración (las dos lecturas del oráculo
  con el mismo snapshot), la reversa restaura el COMMENT previo (NULL), el registro guarda 2 sentencias (función + comentario)
  y rechaza otro nombre u otro contenido, censo de llamadores = 11 (9 DEFINER, 2 INVOKER, incluida la envoltura
  `cartera_f5_fuentes_reales`), y un caso de identidad incoherente en la sintética.

## Resultado del banco Docker (imagen supabase/postgres 17.6.1.105, esquema de prod)
migración → repetida («ya aplicada») → reversa (comentario vuelve a NULL) → repetida → migración → registrar → repetido
(fila `20260930172255 / crm_cartera_f5_fuentes_mapas`, 2 sentencias); negativos: cuerpo ajeno (migración y reversa lo
rechazan) y `inversionista_canonica` alterada (migración y registro lo rechazan). Prueba sintética: **13 fuentes idénticas**
entre cuerpo vivo y nuevo y foto esperada exacta:
`SINT-1→01/31 SINT-13→26/- SINT-14→01/-! SINT-2→01/32 SINT-3→01/33 SINT-4→01/33 SINT-5→27/35 SINT-6→28/35 SINT-7→29/- SINT-8→-/38! SINT-9→10/- TX-1→01/31 TX-2→27/31`
(fuente → persona canónica / analista atribuido; «!» = identidad_coherente false).

## Migración completa
```sql
-- ============================================================================
-- Cartera F5: la canónica de cada persona y el analista atribuido de cada contrato se calculan
-- UNA vez por llamada, no por fila (private.cartera_f5_fuentes)
-- ============================================================================
-- Refactor por módulos, aprobado por Miguel el 30/09/2026 (objetivo fijado con /goal tras el plan por fases).
-- Nota del vault: «CRM - auditoria de indices (2026-09-30)». Ensayos: supabase/scripts/ensayo-cartera-f5-fuentes-mapas/.
--
-- Problema medido en producción (30/09, `track_functions` en transacción deshecha): la ficha de inversionista
-- (crm.inversionista_ficha_fn, 490–535 ms, 1.575 llamadas en 4 días) calcula la cartera entera
-- (private.cartera_f5_fuentes, 726 fuentes) SIETE veces por llamada = 291 ms; y cada cálculo llama por FILA a
-- private.inversionista_canonica() (~1.900 veces, CTE recursiva) y a private.analista_atribuido_cadena()
-- (~685 veces, CTE recursiva): 13.408 + 4.795 llamadas por ficha (218 + 123 ms). Hoy 0 personas tienen padre
-- (inversionista_canonico_id) y operaciones_cartera tiene 3 filas.
--
-- Cambio: el MISMO cuerpo, con dos mapas jsonb calculados una vez por llamada (`canon_map`: id → canónica con el
-- mismo paseo hacia la raíz, tope 16, y sin raíz el propio id; `atrib_map`: contrato → analista del primer ancestro
-- «upgrade» por operaciones_cartera, con visitados y tope 100) leídos con `->>`. La cadena es LINEAL porque
-- operaciones_cartera.contrato_nuevo_id es UNIQUE (20260824231133): no puede haber dos ancestros «upgrade» al mismo
-- nivel (Codex r1 P2 refutado con esa evidencia). inversionista_canonica y analista_atribuido_cadena NO cambian; el
-- preflight exige sus huellas del 30/09 (si cambian, revisar los mapas; Codex r1 P2 aceptado).
-- Medido: 42 → 11 ms por llamada, 726/726 filas con el mismo md5;
-- punta a punta (reemplazo deshecho): 33/33 salidas idénticas (29 fichas, agenda, estado, cartera, postventa_estado);
-- ficha 509 → 284 ms, agenda de postventa 164 → 97, cartera de inversionistas 193 → 126, estado 52 → 19.
-- Nada más cambia: misma firma, STABLE, SECURITY DEFINER (como estaba), search_path vacío, dueño y ACL.
-- Ninguna puerta ni el front cambian; la nombran 11 funciones (9 DEFINER y 2 INVOKER, incluida la envoltura
-- cartera_f5_fuentes_reales): ficha, gestion, documento, personas_visibles, listar, estado, postventa_fuente,
-- postventa_vencimientos, metricas_f7_fuentes, trg_piloto_f8_control_validar y la envoltura.
--
-- Huellas (md5 de pg_get_functiondef, medidas en la base): viva 94fa33cfcca657f70a1a94f98c3bf482 → nueva fa15f7765d0892c790c7a4b6822e756e.
-- Idempotente y fail-closed. Reversa: supabase/scripts/cartera-f5-fuentes-mapas/reversa.sql (restaura el cuerpo
-- vivo del 30/09 tal cual; conserva la fila de schema_migrations: anotarlo en el ledger).

begin;
-- REPEATABLE READ: las dos lecturas del oráculo ven el mismo snapshot (auditor-rls P3-1); sin él, un commit ajeno entre
-- ambas daría un falso POSTFLIGHT (fail-closed, sin daño, pero obligaría a reintentar).
set transaction isolation level repeatable read;
set local lock_timeout = '10s';

do $mig$
declare
  v_md5 text; v_oid oid := 'private.cartera_f5_fuentes()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
  v_antes text; v_despues text; v_n_antes int; v_n_despues int;
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  -- Las dos funciones cuyo criterio copian los mapas deben ser las del 30/09/2026 (Codex P2): si cambian, hay que revisar
  -- los mapas antes de aplicar o registrar. Se evalúa con IS NOT TRUE para que un NULL (función ausente) también rechace.
  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) = '34702897135078893b7d3a726b0c1816'
      and (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.analista_atribuido_cadena(uuid)')) = '3c9cec305b014ad8c933df25057d3e8b') is not true then
    raise exception 'PREFLIGHT: private.inversionista_canonica(uuid) o private.analista_atribuido_cadena(uuid) no son las del 30/09/2026 (huellas esperadas 34702897135078893b7d3a726b0c1816 y 3c9cec305b014ad8c933df25057d3e8b); revisar los mapas de cartera_f5_fuentes antes de seguir';
  end if;
  if v_md5 = 'fa15f7765d0892c790c7a4b6822e756e' then
    raise notice 'crm_cartera_f5_fuentes_mapas: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> '94fa33cfcca657f70a1a94f98c3bf482' then
    raise exception 'PREFLIGHT: private.cartera_f5_fuentes() no es el cuerpo vivo del 30/09/2026 (huella %)', v_md5;
  end if;
  -- Oráculo dentro de la misma transacción: las MISMAS filas (texto de la fila, con multiplicidad, en orden estable)
  -- antes y después; si difieren, se deshace todo.
  select count(*), md5(coalesce(string_agg(f::text, '|' order by f::text), '')) into v_n_antes, v_antes from private.cartera_f5_fuentes() f;

  execute $def$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$def$;

  select count(*), md5(coalesce(string_agg(f::text, '|' order by f::text), '')) into v_n_despues, v_despues from private.cartera_f5_fuentes() f;
  if v_n_antes <> v_n_despues or v_antes <> v_despues then
    raise exception 'POSTFLIGHT: la cartera cambió de forma (antes % filas md5 %, después % filas md5 %); se deshace', v_n_antes, v_antes, v_n_despues, v_despues;
  end if;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'crm_cartera_f5_fuentes_mapas: aplicada (huella %, % fuentes idénticas)', v_md5, v_n_despues;
end $mig$;

comment on function private.cartera_f5_fuentes() is
  'Cartera F5: una fila por fuente (contrato Avance o cierre externo) con su persona canónica y su analista atribuido. '
  'Canónica y atribución se calculan una vez por llamada (mapas jsonb) con el mismo criterio que inversionista_canonica y '
  'analista_atribuido_cadena (30/09/2026). SECURITY DEFINER: solo la llaman funciones de private/crm.';

commit;

```

## Reversa completa
```sql
-- REVERSA de 20260930172255_crm_cartera_f5_fuentes_mapas: restaura el cuerpo VIVO del 30/09/2026 de private.cartera_f5_fuentes() tal cual.
-- Se niega si la función no tiene la huella nueva o sus invariantes. NO toca schema_migrations: si se revierte,
-- anotarlo en MIGRACIONES.md el mismo día. Restaura también el COMMENT previo (no había: NULL; auditor-rls P3-2). No exige
-- las huellas de inversionista_canonica / analista_atribuido_cadena: el cuerpo vivo las llama, no las copia.
begin;
set local lock_timeout = '10s';
do $rev$
declare
  v_md5 text; v_oid oid := 'private.cartera_f5_fuentes()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = '94fa33cfcca657f70a1a94f98c3bf482' then raise notice 'REVERSA: ya está el cuerpo vivo del 30/09 (%)', v_md5; return; end if;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then raise exception 'REVERSA: huella desconocida (%), no se toca', v_md5; end if;
  execute $def$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce(private.analista_atribuido_cadena(c.id),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$def$;
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> '94fa33cfcca657f70a1a94f98c3bf482' then raise exception 'REVERSA: huella inesperada tras restaurar (%)', v_md5; end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REVERSA-POST: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'REVERSA: cuerpo vivo del 30/09 restaurado (%)', v_md5;
end $rev$;
comment on function private.cartera_f5_fuentes() is null;
commit;

```

## Registro completo
```sql
-- REGISTRO en supabase_migrations.schema_migrations de 20260930172255_crm_cartera_f5_fuentes_mapas.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si la función
-- no tiene la huella nueva, sus invariantes o las huellas de las dos funciones copiadas, o si la versión ya está
-- registrada con otro nombre u otro contenido; relee la fila antes de confirmar.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_cartera_f5_fuentes_mapas'));
do $chk$
declare
  v_md5 text; v_oid oid := 'private.cartera_f5_fuentes()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then
    raise exception 'REGISTRO: la función no tiene la huella nueva (%); aplica primero la migración 20260930172255', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), SECURITY DEFINER (así estaba y así sigue), STABLE y
  -- search_path vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: dueño/ACL/definer/volatilidad/search_path de la función no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  -- Las dos funciones cuyo criterio copian los mapas deben ser las del 30/09/2026 (Codex P2): si cambian, hay que revisar
  -- los mapas antes de aplicar o registrar. Se evalúa con IS NOT TRUE para que un NULL (función ausente) también rechace.
  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) = '34702897135078893b7d3a726b0c1816'
      and (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.analista_atribuido_cadena(uuid)')) = '3c9cec305b014ad8c933df25057d3e8b') is not true then
    raise exception 'REGISTRO: private.inversionista_canonica(uuid) o private.analista_atribuido_cadena(uuid) no son las del 30/09/2026 (huellas esperadas 34702897135078893b7d3a726b0c1816 y 3c9cec305b014ad8c933df25057d3e8b); revisar los mapas de cartera_f5_fuentes antes de seguir';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930172255' and (coalesce(name,'') <> 'crm_cartera_f5_fuentes_mapas' or statements is distinct from array[$stm$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$stm$, $stm$
comment on function private.cartera_f5_fuentes() is
  'Cartera F5: una fila por fuente (contrato Avance o cierre externo) con su persona canónica y su analista atribuido. '
  'Canónica y atribución se calculan una vez por llamada (mapas jsonb) con el mismo criterio que inversionista_canonica y '
  'analista_atribuido_cadena (30/09/2026). SECURITY DEFINER: solo la llaman funciones de private/crm.'
$stm$])) then
    raise exception 'REGISTRO: la versión 20260930172255 ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930172255', 'crm_cartera_f5_fuentes_mapas', array[$stm$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$stm$, $stm$
comment on function private.cartera_f5_fuentes() is
  'Cartera F5: una fila por fuente (contrato Avance o cierre externo) con su persona canónica y su analista atribuido. '
  'Canónica y atribución se calculan una vez por llamada (mapas jsonb) con el mismo criterio que inversionista_canonica y '
  'analista_atribuido_cadena (30/09/2026). SECURITY DEFINER: solo la llaman funciones de private/crm.'
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260930172255' and name = 'crm_cartera_f5_fuentes_mapas' and cardinality(statements) = 2
                 and md5(statements[1]) = md5($stm$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$stm$) and md5(statements[2]) = md5($stm$
comment on function private.cartera_f5_fuentes() is
  'Cartera F5: una fila por fuente (contrato Avance o cierre externo) con su persona canónica y su analista atribuido. '
  'Canónica y atribución se calculan una vez por llamada (mapas jsonb) con el mismo criterio que inversionista_canonica y '
  'analista_atribuido_cadena (30/09/2026). SECURITY DEFINER: solo la llaman funciones de private/crm.'
$stm$)) then
    raise exception 'REGISTRO: la fila 20260930172255 / crm_cartera_f5_fuentes_mapas no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20260930172255 / crm_cartera_f5_fuentes_mapas (2 sentencias: función + comentario)';
end $post$;
commit;

```

## Prueba sintética completa (banco, supabase_admin, todo deshecho)
```sql
-- PRUEBA SINTÉTICA (banco Docker, como supabase_admin, todo deshecho al final): el cuerpo VIVO y el NUEVO de
-- private.cartera_f5_fuentes() deben dar las MISMAS filas sobre grafos que producción no tiene hoy (0 fusiones,
-- 3 operaciones): hijos y nietos fusionados, cadena de 17 (supera el tope 16), ciclo A↔B, padre inexistente,
-- auto-padre, upgrades encadenados, renovación tras upgrade, ciclo de operaciones y analista nulo.
-- Casos: SINT-3 (nieto fusionado → canónica 01) · SINT-9 (cliente 10, cadena de 17 → él mismo) · SINT-13 (cliente 11 → raíz 26 en el nodo 16)
-- · SINT-5/6 (ciclo A↔B → cada uno él mismo) · SINT-7 (padre inexistente → él mismo; upgrade con analista NULL) · SINT-8 (perfil sin
-- persona; renovación de un upgrade sin analista → su propio analista) · SINT-4 (renovación tras upgrade → analista del upgrade)
-- · SINT-14 (identidad incoherente: perfil de la persona 01 e inversión de la 27 → identidad_coherente=false) · TX-1/TX-2 (cierres externos).
-- Requiere el cuerpo NUEVO instalado (la migración aplicada en el banco). Triggers y FKs apagados con
-- session_replication_role = replica para sembrar filas mínimas; los CHECK siguen vivos.
begin;
set local session_replication_role = replica;
set local search_path = '';
CREATE OR REPLACE FUNCTION pg_temp.cartera_f5_fuentes_vieja()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce(private.analista_atribuido_cadena(c.id),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct private.inversionista_canonica(x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$;

-- Actores mínimos
insert into public.perfiles (id, nombre_completo) select ('00000000-0000-4000-8000-0000000000'||lpad(g::text,2,'0'))::uuid, 'Sintético '||g from generate_series(1,40) g;
-- Personas: P01 raíz · P02→P01 · P03→P02 · cadena C10→C11→…→C26 raíz (17 nodos: C10 no llega a la raíz dentro del tope 16 y queda como su propia canónica; C11 sí llega, en su nodo 16) · A↔B (27,28) · D→inexistente (29) · el auto-padre lo prohíbe el CHECK inversionistas_no_autofusion (no se siembra) · perfil 30 sin persona
insert into crm.inversionistas (id, perfil_id, inversionista_canonico_id) values
  ('00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8000-000000000001', null),
  ('00000000-0000-4000-8000-000000000002'::uuid, '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000003'::uuid, '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000027'::uuid, '00000000-0000-4000-8000-000000000027', '00000000-0000-4000-8000-000000000028'),
  ('00000000-0000-4000-8000-000000000028'::uuid, '00000000-0000-4000-8000-000000000028', '00000000-0000-4000-8000-000000000027'),
  ('00000000-0000-4000-8000-000000000029'::uuid, '00000000-0000-4000-8000-000000000029', '00000000-0000-4000-8000-000000000099');
insert into crm.inversionistas (id, perfil_id, inversionista_canonico_id)
  select ('00000000-0000-4000-8000-0000000000'||g)::uuid, ('00000000-0000-4000-8000-0000000000'||g)::uuid,
         case when g < 26 then ('00000000-0000-4000-8000-0000000000'||(g+1))::uuid end from generate_series(10,26) g;

-- Contratos: K1 nueva (a1) · K2 upgrade de K1 (a2) · K3 upgrade de K2 (a3) · K4 renovación de K3 · K5↔K6 ciclo · K7 upgrade con analista nulo, K8 renovación de K7
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, modalidad, fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial, categoria, analista_cierre_id, estado, es_demo)
select ('00000000-0000-4000-8000-00000000c0'||lpad(k::text,2,'0'))::uuid, 'SINT-'||k, ('00000000-0000-4000-8000-0000000000'||lpad(cli::text,2,'0'))::uuid, 1000, 'PEN', 'mensual', date '2026-01-01', date '2027-01-01', gen_random_uuid(), date '2026-01-01', cat, an, 'activo', false
from (values
  (1, 1, 'nuevo',      '00000000-0000-4000-8000-000000000031'::uuid),
  (2, 2, 'upgrade',    '00000000-0000-4000-8000-000000000032'::uuid),
  (3, 3, 'upgrade',    '00000000-0000-4000-8000-000000000033'::uuid),
  (4, 3, 'renovacion', '00000000-0000-4000-8000-000000000034'::uuid),
  (5, 27,'upgrade',    '00000000-0000-4000-8000-000000000035'::uuid),
  (6, 28,'renovacion', '00000000-0000-4000-8000-000000000036'::uuid),
  (7, 29,'upgrade',    null::uuid),
  (8, 30,'renovacion', '00000000-0000-4000-8000-000000000038'::uuid),
  (9, 10,'nuevo',      null::uuid),
  (13, 11,'nuevo',     null::uuid),
  (14, 1,'nuevo',      null::uuid)) v(k, cli, cat, an);
-- (El EMPATE de dos orígenes «upgrade» al mismo nivel NO puede sembrarse: operaciones_cartera.contrato_nuevo_id es UNIQUE,
--  la cadena es lineal. Codex r1 P2 refutado con esa evidencia; el intento de sembrarlo lo confirmó: duplicate key.)
-- Las operaciones que enlazan origen→nuevo son RENOVACIONES (el CHECK operaciones_cartera_forma exige contrato_origen_id
-- NULL en los upgrades); la cadena sube por ellas hasta el primer contrato con categoria = 'upgrade'.
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, contrato_origen_id, fecha_operacion, periodo, moneda, elegible_conversion, fuente, creado_por, desglose_completo, capital_renovado, capital_adicional)
select ('00000000-0000-4000-8000-000000000001')::uuid, ('00000000-0000-4000-8000-000000000031')::uuid, 'renovacion', ('00000000-0000-4000-8000-00000000c0'||lpad(n::text,2,'0'))::uuid, ('00000000-0000-4000-8000-00000000c0'||lpad(o::text,2,'0'))::uuid, date '2026-02-01', date '2026-02-01', 'PEN', true, 'flujo_cartera', ('00000000-0000-4000-8000-000000000031')::uuid, true, 1000, 0
from (values (2,1),(3,2),(4,3),(5,6),(6,5),(8,7)) v(n,o);
-- Inversiones que enlazan contrato→persona (rama iv.inversionista_id) y cierres externos con persona/lead
insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id) values
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000003', gen_random_uuid(), '00000000-0000-4000-8000-00000000c001'),
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000010', gen_random_uuid(), '00000000-0000-4000-8000-00000000c009'),
  -- identidad INCOHERENTE (auditor-rls P3-5): K14 es del perfil 01 (persona 01) y su inversión apunta a la persona 27 (ciclo A↔B)
  (gen_random_uuid(), '00000000-0000-4000-8000-000000000027', gen_random_uuid(), '00000000-0000-4000-8000-00000000c014');
insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion, vendedor_id, creado_por, inversionista_id, vence_en, es_cierre_inicial, fecha_comercial, fecha_imputacion, comprobante_objeto_id, referencia_externa)
values ('00000000-0000-4000-8000-00000000ce01', 'qorilazo', 500, 'PEN', 'DNI', '00000001', 'Sintético CE', 'TX-1', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000003', date '2027-01-01', false, date '2026-01-01', date '2026-01-02', gen_random_uuid(), 'TX-1'),
       ('00000000-0000-4000-8000-00000000ce02', 'prodelco', 500, 'PEN', 'DNI', '00000002', 'Sintético CE2', 'TX-2', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000031', '00000000-0000-4000-8000-000000000027', date '2025-01-01', false, date '2026-01-01', date '2026-01-02', gen_random_uuid(), 'TX-2');

do $p$
declare v_vieja text; v_nueva text; n_v int; n_n int; v_foto text; v_md5 text; v_esp text; v_real text;
begin
  select md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure)) into v_md5;
  if v_md5 <> 'fa15f7765d0892c790c7a4b6822e756e' then raise exception 'la prueba exige el cuerpo NUEVO instalado (huella %)', v_md5; end if;
  select count(*), md5(string_agg(f::text, '|' order by f::text)) into n_v, v_vieja from pg_temp.cartera_f5_fuentes_vieja() f;
  select count(*), md5(string_agg(f::text, '|' order by f::text)) into n_n, v_nueva from private.cartera_f5_fuentes() f;
  -- foto legible: fuente → persona canónica / analista atribuido (según el cuerpo nuevo)
  select string_agg(f.numero||'→'||coalesce(right(f.inversionista_id::text,2),'-')||'/'||coalesce(right(f.analista_origen_id::text,2),'-')||case when f.identidad_coherente then '' else '!' end, ' ' order by f.numero) into v_foto
    from private.cartera_f5_fuentes() f where f.numero like 'SINT-%' or f.numero like 'TX-%';
  if n_v <> n_n or v_vieja <> v_nueva then
    raise exception 'SINTETICA: DISTINTAS (vieja % filas md5 %, nueva % filas md5 %) · nueva: %', n_v, v_vieja, n_n, v_nueva, v_foto;
  end if;
  -- Expectativas EXPLÍCITAS (además de la igualdad vieja = nueva): canónica y atribución esperadas por caso.
  -- «!» = identidad_coherente false (dos canónicas distintas: personas[1] es la menor por array_agg(distinct), igual en ambos cuerpos)
  v_esp := 'SINT-1→01/31 SINT-13→26/- SINT-14→01/-! SINT-2→01/32 SINT-3→01/33 SINT-4→01/33 SINT-5→27/35 SINT-6→28/35 SINT-7→29/- SINT-8→-/38! SINT-9→10/- TX-1→01/31 TX-2→27/31';  -- SINT-8: perfil sin persona → sin canónica → incoherente, en ambos cuerpos
  if v_foto <> v_esp then
    raise exception 'SINTETICA: la foto no es la esperada. esperada: % · real: %', v_esp, v_foto;
  end if;
  raise exception 'SINTETICA OK (rollback): % filas idénticas entre cuerpo vivo y nuevo · expectativas explícitas OK · fuente→persona canónica/analista atribuido: %', n_n, v_foto;
end $p$;
rollback;

```

## Tu r1, para referencia
**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

La transformación conserva los casos deterministas descritos. No detecto diferencias en canónicas, NULL, ciclos, límites de recorrido, contratos demo ni cálculo de fechas.

La equivalencia exacta de `analista_origen_id` no está garantizada cuando existen empates. Además, el preflight transcrito no protege las definiciones de las dos funciones cuya lógica se copia.

**FINDINGS**

**P2 — Los empates permiten elegir un analista diferente.**

Evidencia: `analista_atribuido_cadena` selecciona con `ORDER BY cd.nivel ASC LIMIT 1`; `atrib` usa `DISTINCT ON (cd.raiz) ORDER BY cd.raiz, cd.nivel ASC`. Ninguna desempata dentro de una raíz.

Contraejemplo permitido por las restricciones aportadas:

- Una renovación `R` tiene dos operaciones con `contrato_nuevo_id = R`.
- Sus respectivos orígenes son `U1` y `U2`, ambos contratos `upgrade`.
- Sus analistas son `A` y `B`, con `A <> B`.

Ambos candidatos están en nivel 1. La consulta original puede escoger `A` y la nueva `B`: sus planes y ordenaciones son independientes. El CHECK exige un origen por operación, pero no una operación por contrato nuevo.

Esto **no introduce la ambigüedad**, que ya existe; sí impide garantizar resultados idénticos entre implementaciones. No afirmo una divergencia ejecutada: es un contraejemplo a la garantía SQL, compatible con el esquema descrito. Las pruebas sobre el árbol actual no lo cubren.

Para conservar el alcance de una sola función, una solución conservadora es recurrir a `private.analista_atribuido_cadena(c.id)` únicamente para raíces con varios candidatos al menor nivel. Añadir un desempate solo al mapa tampoco asegura equivalencia con la función original.

**P2 — El preflight descrito no verifica las dependencias copiadas.**

Evidencia: las guardas transcritas comprueban la huella de `cartera_f5_fuentes` y sus atributos, pero no las huellas aportadas de `inversionista_canonica` y `analista_atribuido_cadena`.

Ejemplo concreto: cambiar previamente el límite de canónica de 16 a 32 no modifica la huella de `cartera_f5_fuentes`. Con **cero personas fusionadas**, el oráculo de filas seguiría pasando; después del reemplazo, una cadena futura seguiría resolviéndose con el límite copiado de 16.

Es un riesgo del despliegue, no una discrepancia entre los cuerpos aportados. El preflight de migración y reversa debería comprobar esas dos definiciones. Si el script completo ya lo hace, ese fragmento resuelve el hallazgo. Las futuras modificaciones de esas funciones también deberán considerar la copia.

**RISKS / TEST GAPS**

- **Canónicas y mapas:** `canon` agrupa por origen y `atrib` deja una fila por raíz; por tanto, no hay claves repetidas en los agregados JSONB bajo las claves de identidad descritas. El recorrido, los identificadores inexistentes, los valores NULL y la conversión UUID → texto → UUID conservan el comportamiento. `es_demo` no modifica ninguno de los recorridos.
- **Reevaluación del mapa:** `(SELECT m FROM canon_map)` no está correlacionado; la correlación aparece después, en la clave `x.id`. Para los casos deterministas, reevaluarlo puede cambiar el coste, no el resultado: las lecturas comparten el snapshot de la sentencia. El número efectivo de evaluaciones requiere el plan.
- **Fechas:** `statement_timestamp()` permanece constante durante la sentencia, aunque esta atraviese medianoche. No cambia el cálculo de `estado`. Dos comprobaciones ejecutadas en sentencias distintas alrededor de medianoche pueden diferir con cualquiera de los cuerpos.
- **Fixture de 17 nodos:** “cada nodo es su propia canónica” no describe una cadena lineal terminada en NULL. Para `P1 → … → P17 → NULL`, `P1` devuelve `P1`, pero `P2` devuelve `P17`: alcanza la raíz en su nodo 16. Esto cuestiona la explicación del ensayo, no demuestra un fallo del código. Conviene comprobar sus expectativas explícitas.
- No se aporta ensayo del empate anterior ni de los límites 100/101 de atribución.
- Con el esqueleto no puedo certificar el patrón de la casa: faltan el oráculo literal, el orden de las guardas en la ruta idempotente y el tratamiento de una versión de registro ya existente con contenido diferente. Deben verificarse orden y multiplicidad en el oráculo, invariantes también al salir por “ya aplicada” y rechazo de registros incompatibles.

**NEXT ACTIONS**

1. Resolver conservadoramente las raíces empatadas y añadir el caso al banco.
2. Verificar las huellas de ambas dependencias en migración y reversa.
3. Corregir o aclarar el fixture de 17 nodos y revisar los fragmentos de guardas y registro indicados.

**CONFIDENCE**

Alta en el análisis de los cuerpos SQL; limitada para los scripts completos, no aportados. Pruebas transcritas: **PASS reportado**. Ejecución independiente: **NOT RUN**, conforme al alcance sin base ni red.

