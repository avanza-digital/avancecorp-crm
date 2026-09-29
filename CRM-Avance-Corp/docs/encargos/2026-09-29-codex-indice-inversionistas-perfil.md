ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 2: migración de rendimiento, sin cambios de permisos ni de
funciones). Intenta REFUTAR; no confirmes por cortesía. No tienes base ni red ni shell: todo lo
que necesitas está transcrito abajo. Responde con: VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK),
SUMMARY, FINDINGS P0–P3 (cada uno con evidencia citada de este encargo: archivo/línea, plan o
cifra; distingue hipótesis de hecho), RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.
Sin hallazgo sin evidencia.

## Contexto

CRM Supabase/Postgres (esquema `crm`, helpers en `private`). El dueño (Miguel) aprobó la
migración. Medición en producción (bloques DO de solo lectura que terminan en raise):
`crm.inversionistas` (565 filas, ~70 escrituras en 4 días) se recorrió entera 22,6 M veces en
~97 h = 95 % de las filas leídas del esquema. Causa: `private.cartera_f5_fuentes()` (cuerpo
abajo) hace, por cada contrato de `public.contratos` (679), un lateral con
`select i.id from crm.inversionistas i where i.perfil_id = c.cliente_id`. Índices actuales:

```
CREATE UNIQUE INDEX inversionistas_pkey ON crm.inversionistas USING btree (id)
CREATE UNIQUE INDEX inversionistas_perfil_uidx ON crm.inversionistas USING btree (perfil_id) WHERE ((perfil_id IS NOT NULL) AND (estado <> 'fusionado'::text))
CREATE INDEX inversionistas_responsable_idx ON crm.inversionistas USING btree (responsable_relacion_id)
CREATE INDEX inversionistas_canonico_idx ON crm.inversionistas USING btree (inversionista_canonico_id)
CREATE INDEX inversionistas_estado_idx ON crm.inversionistas USING btree (estado)
```

Plan actual de la búsqueda: `Seq Scan on inversionistas i (cost=0.00..22.06 rows=1) Filter: (perfil_id = '…'::uuid)`.
La alcanzan 11 puertas (postventa_agenda/estado/ficha, cartera_inversionistas_estado,
inversionista_ficha/gestion/cuentas, contexto_conversion_inversion, solicitud_inversion,
acceso_inversion, preparar_persona_lead_inversion). Muestreo en vivo 6 min: 189.728 recorridos,
≈1.530 por llamada a esas puertas (≈2,25 llamadas a fuentes por puerta × 679).
Hay otras 18 funciones con `crm.inversionistas i ... where i.perfil_id = X` sin la condición
del índice parcial (p. ej. private.citas_gerencia_consulta, private.citas_testigo_mes).
Datos hoy: 0 perfiles con >1 persona, 0 perfiles con alguna persona fusionada.

## Ensayo en producción (transacción deshecha: DO que crea el índice, mide y termina en raise)

```
filas=719
ANTES:   seq=679 idx=715  tiempo=91 ms
DESPUES: seq=0   idx=1394 tiempo=43 ms
mismas filas: t (md5 de string_agg(f::text order by fuente_id): beff0bf2 antes y después)
PLAN perfil_id: Index Scan using inversionistas_perfil_idx (cost=0.28..2.49 rows=1) Index Cond: (perfil_id = …)
```
Comprobado después: el índice no quedó en producción (0 filas en pg_indexes).
Otro ensayo deshecho: pg_get_indexdef = `CREATE INDEX inversionistas_perfil_idx ON crm.inversionistas USING btree (perfil_id)` (coincide con lo que exige el registrador).

## Cuerpo vivo de las funciones afectadas (sin cambios en esta migración)

```sql
-- private.cartera_f5_fuentes_reales (vol=s) CUERPO VIVO 29/09

  select * from private.cartera_f5_fuentes() f where f.es_demo is not true;


-- private.cartera_f5_fuentes (vol=s) CUERPO VIVO 29/09

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


```

## Migración `supabase/migrations/20260929220021_crm_indice_inversionistas_perfil.sql`
```sql
-- ============================================================================
-- Índice crm.inversionistas(perfil_id) — la cartera deja de recorrer la tabla
-- entera por cada contrato
-- ============================================================================
-- Aprobado por Miguel el 2026-09-29 («ok vamos con la migracion»). Medido en
-- producción el mismo día con bloques de solo lectura que terminan en raise
-- (nota del vault «CRM - perfil de carga lectura vs escritura (2026-09-29)»):
--
--   crm.inversionistas se recorrió entera 22,6 M veces en ~97 h (12.462 M
--   filas, el 95 % de todo lo que lee el esquema crm). La causa es
--   private.cartera_f5_fuentes(): su lateral por contrato
--     select i.id from crm.inversionistas i where i.perfil_id = c.cliente_id
--   no puede usar el único índice de perfil_id, inversionistas_perfil_uidx,
--   porque es PARCIAL (perfil_id is not null and estado <> 'fusionado') y la
--   consulta no repite esa condición → 679 recorridos completos por llamada
--   (uno por contrato), ~90 ms. La alcanzan 11 puertas (postventa, cartera de
--   inversionistas, fichas, contexto y solicitud de inversión).
--
-- Un índice normal sobre perfil_id sirve esa búsqueda (y la de otras 18
-- funciones con el mismo patrón, p. ej. citas_gerencia_consulta y
-- citas_testigo_mes) SIN tocar ninguna función: mismas filas, mismo orden de
-- evaluación, solo cambia el plan. El índice único parcial se queda: es la
-- regla «un perfil, una persona viva», no un acelerador.
--
-- Sin CONCURRENTLY a propósito: la tabla tiene ~565 filas y casi no se escribe
-- (70 escrituras en 4 días); el candado dura milisegundos.
--
-- Reversa (sin pérdida de datos):
--   drop index if exists crm.inversionistas_perfil_idx;

begin;
set local lock_timeout = '10s';

create index if not exists inversionistas_perfil_idx
  on crm.inversionistas (perfil_id);

comment on index crm.inversionistas_perfil_idx is
  'Búsqueda de personas por perfil sin la condición del índice único parcial (inversionistas_perfil_uidx). La usa el lateral por contrato de private.cartera_f5_fuentes; antes recorría la tabla entera por cada contrato (medido 29/09/2026).';

commit;
```

## Registrador `supabase/scripts/indice-inversionistas-perfil/registrar.sql` (se corre DESPUÉS de aplicar)
```sql
-- REGISTRO en supabase_migrations.schema_migrations de 20260929220021_crm_indice_inversionistas_perfil.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega
-- si el índice no existe, no es válido o tiene otra definición, o si la versión ya está registrada con otro nombre.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_indice_inversionistas_perfil'));
do $chk$
declare
  v_def text;
  v_valido boolean;
begin
  select pg_get_indexdef(x.indexrelid), x.indisvalid and x.indisready into v_def, v_valido
  from pg_index x
  where x.indexrelid = to_regclass('crm.inversionistas_perfil_idx');
  if v_def is null then
    raise exception 'REGISTRO: crm.inversionistas_perfil_idx no existe; aplica primero la migración 20260929220021';
  end if;
  if v_def <> 'CREATE INDEX inversionistas_perfil_idx ON crm.inversionistas USING btree (perfil_id)' then
    raise exception 'REGISTRO: crm.inversionistas_perfil_idx tiene otra definición: %', v_def;
  end if;
  if not v_valido then
    raise exception 'REGISTRO: crm.inversionistas_perfil_idx existe pero no es válido';
  end if;
  if exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260929220021' and coalesce(name, '') <> 'crm_indice_inversionistas_perfil'
  ) then
    raise exception 'REGISTRO: la versión 20260929220021 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260929220021', 'crm_indice_inversionistas_perfil',
        array['create index if not exists inversionistas_perfil_idx on crm.inversionistas (perfil_id);'])
on conflict (version) do nothing;
select version, name from supabase_migrations.schema_migrations where version = '20260929220021';
commit;
```

## Verificación `supabase/scripts/indice-inversionistas-perfil/verificar.sql` (solo lectura)
```sql
-- VERIFICACIÓN tras aplicar 20260929220021 (solo lectura; termina SIEMPRE en raise).
-- Esperado: indice=valido, cartera_f5_fuentes con seq=0 y el plan de perfil_id por el índice nuevo.
do $$
declare
  r oid := 'crm.inversionistas'::regclass;
  s0 bigint; i0 bigint; s1 bigint; i1 bigint; t0 timestamptz; t1 timestamptz;
  v_valido boolean; plan text := ''; l text;
begin
  set local transaction read only;
  select x.indisvalid and x.indisready into v_valido
  from pg_index x where x.indexrelid = to_regclass('crm.inversionistas_perfil_idx');
  select seq_scan, idx_scan into s0, i0 from pg_stat_xact_user_tables where relid = r;
  t0 := clock_timestamp(); perform count(*) from private.cartera_f5_fuentes(); t1 := clock_timestamp();
  select seq_scan, idx_scan into s1, i1 from pg_stat_xact_user_tables where relid = r;
  for l in execute $q$explain select i.id from crm.inversionistas i where i.perfil_id = '00000000-0000-0000-0000-000000000000'::uuid$q$
  loop plan := plan || l || E'\n'; end loop;
  raise exception E'VERIFICACION (solo lectura)\nindice=%\ncartera_f5_fuentes: seq=% idx=% tiempo=% ms (antes: seq=679, ~91 ms)\nPLAN perfil_id:\n%',
    case when v_valido then 'valido' when v_valido is null then 'NO EXISTE' else 'INVALIDO' end,
    s1-s0, i1-i0, round(extract(epoch from t1-t0)*1000), plan;
end $$;
```

Método de aplicación (lo lanza el dueño con `!`): `supabase db query --linked --file <migración>`
(el CLI envía el archivo tal cual; la migración trae su propio begin/commit) → registrar.sql →
verificar.sql → advisors de Supabase. Reversa: `drop index if exists crm.inversionistas_perfil_idx;`.

## Lo que debes intentar refutar

R1. Resultados idénticos: un índice no cambia filas; ¿hay algún camino (orden no determinista,
`array_agg(distinct …)`, `personas[1]`, `limit 1` sin orden en las otras 18 funciones) donde
cambiar el plan cambie el RESULTADO visible? El md5 cubre cartera_f5_fuentes; las otras 18 no
se midieron.
R2. Regresión de plan: ¿alguna consulta que hoy usa `inversionistas_perfil_uidx` (con
`estado <> 'fusionado'`) podría pasar a un plan peor con el índice nuevo? ¿Algún caso donde
el planner elija mal por estadísticas?
R3. Aplicación: `create index` NO concurrente con `lock_timeout 10s` dentro de begin/commit en
producción con ~65–550 lecturas/s: ¿riesgo de bloqueo en cola (lectores detrás del ShareLock
esperando)? ¿`db query --file` con begin/commit propio es seguro?
R4. Registrador: ¿puede registrar en falso o fallar abierto? ¿La comparación literal de
pg_get_indexdef es frágil (p. ej. si otra sesión crea un índice con el mismo nombre)?
R5. ¿El arreglo correcto sería otro (p. ej. reescribir el lateral para calcular el mapa
perfil→persona una vez)? Ten en cuenta que añadir `and estado <> 'fusionado'` en la función
cambiaría la semántica (hoy entran las fusionadas, que `inversionista_canonica` resuelve a su canónica).
R6. Advisors: ¿el índice nuevo dispararía «duplicate index» u otro aviso por solaparse con el
único parcial?
