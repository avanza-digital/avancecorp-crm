ROLE: SECONDARY_REVIEWER.

Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.

Eres el revisor secundario (LEVEL 2: cambia el cuerpo de UNA función SQL `STABLE STRICT` SECURITY INVOKER de
`private` que solo da forma a un JSON; sin tablas, policies ni grants). Intenta REFUTAR; no confirmes por
cortesía. Sin base ni red: todo está transcrito. Responde con VERDICT (APPROVE / CHANGES_REQUESTED / BLOCK),
SUMMARY, FINDINGS P0–P3 con evidencia citada, RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia.

## Contexto medido (29/09/2026, producción, transacciones deshechas)
La lista de tareas (`crm.tareas_pendientes_fn`, 22 ms) arrastra la agenda de postventa (`crm.postventa_agenda_fn`,
509–532 ms como gerencia) en cada carga de Hoy/agenda (~1.300 veces al día). `postventa_agenda_fn` aplica
`private.postventa_tarea_json(t)` a cada tarea pendiente con `inversionista_id` (16 hoy). De los ~530 ms,
320–338 ms son `postventa_perfil_ids`: por cada tarea se recorren las 565 filas de `crm.inversionistas`
llamando a `private.inversionista_canonica()` (CTE recursiva por `inversionista_canonico_id`, tope 16 saltos)
dos veces por fila. Hoy **0** personas tienen `inversionista_canonico_id` (todas son raíz).

`private.inversionista_canonica(p_id)` (STABLE, viva):
```sql
  with recursive c as (
    select i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i where i.id = p_id
    union all
    select i.id, i.inversionista_canonico_id, c.n + 1
    from c join crm.inversionistas i on i.id = c.inversionista_canonico_id
    where c.n < 16
  )
  select case when p_id is null then null
              else coalesce((select c.id from c where c.inversionista_canonico_id is null order by c.n desc limit 1), p_id) end
```
Consumidores de `postventa_tarea_json`: `crm.postventa_agenda_fn`, `crm.postventa_tarea_fn`, `crm.postventa_agendar_fn`,
`private.tareas_clientes_autorizadas` (cola v3). Ningún sello/assert por md5 la nombra.

## Cambio (diff exacto dentro de `private.postventa_tarea_json(p_t crm.tareas)`; LANGUAGE sql, STABLE STRICT,
SECURITY INVOKER, SET search_path TO '', dueño postgres, ACL {postgres=X/postgres})
ANTES:
```sql
    'postventa_perfil_ids',array(select i.perfil_id from crm.inversionistas i
      where i.perfil_id is not null and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
      order by i.perfil_id),
```
DESPUÉS:
```sql
    'postventa_perfil_ids',(with recursive familia as (
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
```
Argumento de equivalencia: si `canonica(i.id) = v` entonces `i` llega a la raíz `v` subiendo ≤ 15 saltos por
`inversionista_canonico_id`, luego `i` cuelga de `v` bajando ≤ 15 niveles → `i ∈ familia` (tope 16). `familia` es un
SUPERCONJUNTO y se conserva el predicado ORIGINAL sobre ese puñado, así que el resultado es el mismo en todos los
casos (ciclos incluidos: con ciclo, `canonica(x)` devuelve `x` para cada nodo y el predicado original filtra
exactamente igual que antes). `p_t.inversionista_id` NULL: antes y después, vacío. Nada más cambia.

## Oráculo en producción (una transacción deshecha)
md5 de `postventa_tarea_json(t)` para TODAS las tareas con persona (16, como postgres, fila a fila), y como 4 actores
(gerencia, supervisor con bandeja, los 2 responsables con más tareas de postventa): `postventa_agenda_fn()`,
`cola_accion_v3_fn()` y `tareas_pendientes_fn()`: **13 casos iguales, 0 distintos**. Tiempos antes → después:
agenda gerencia 509 → 161 ms, supervisor 418 → 162, responsable1 426 → 161, responsable2 215 → 154; las 16
`tarea_json` 338 → 16 ms. Prototipo previo: equivalencia de `perfil_ids` sobre las 568 personas (0 distintas).
Ciclo migración → repetida (idempotente) → reversa → migración → registrador ensayado en producción con rollback
(huellas bff893c5… → bff893c5… → c29fd1d2… → bff893c5…; fila registrada; después: huella viva c29fd1d2…, 0 registros).

## Migración completa `supabase/migrations/20260930000550_crm_postventa_tarea_json_por_familia.sql`
```sql
-- ============================================================================
-- Agenda de postventa: los perfiles de la persona se buscan en su familia, no en las
-- 565 personas (private.postventa_tarea_json)
-- ============================================================================
-- Paso 3 · fase 1 del refactor por módulos, aprobado por Miguel el 29/09/2026 («dale»).
-- Nota del vault: «CRM - perfil de carga lectura vs escritura (2026-09-29)».
--
-- Problema medido en producción (29/09): la lista de tareas (tareas_pendientes_fn, 22 ms) arrastra
-- la agenda de postventa (postventa_agenda_fn, 532 ms) en cada carga de Hoy/agenda de todos los
-- analistas y supervisores (~1.300 veces al día). De esos 532 ms, 320 ms son `postventa_perfil_ids`:
-- por cada una de las 16 tareas de postventa se recorren las 565 personas llamando a
-- inversionista_canonica() dos veces por fila.
--
-- Cambio: las candidatas salen de la FAMILIA de la persona (su raíz canónica y quienes cuelgan de
-- ella, tope 16 como inversionista_canonica) y sobre ese puñado se aplica el MISMO criterio de antes
-- (`inversionista_canonica(i.id) = inversionista_canonica(p_t.inversionista_id)`). Toda persona con la
-- misma canónica cuelga de esa raíz en ≤ 15 saltos, así que el conjunto es idéntico también con
-- ciclos o cadenas raras; hoy no hay ninguna persona con padre (0). Prototipo medido: 320 ms → 1 ms;
-- equivalencia comprobada sobre las 568 personas (0 distintas). Nada más cambia: misma firma,
-- STABLE STRICT, INVOKER, search_path vacío, dueño y ACL. Ninguna puerta ni el front cambian.
--
-- Huellas (md5 de pg_get_functiondef): viva c29fd1d25ab775ecd63ab2660a847d0e → nueva bff893c533d645be75d884788173bd50.
-- Idempotente y fail-closed. Reversa: supabase/scripts/postventa-tarea-familia/reversa.sql (restaura el
-- cuerpo vivo del 29/09 tal cual; conserva la fila de schema_migrations: anotarlo en el ledger).

begin;
set local lock_timeout = '10s';

do $mig$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función viva no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'bff893c533d645be75d884788173bd50' then
    raise notice 'postventa_tarea_json_por_familia: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> 'c29fd1d25ab775ecd63ab2660a847d0e' then
    raise exception 'PREFLIGHT: private.postventa_tarea_json(crm.tareas) no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'postventa_tarea_json_por_familia: aplicada (huella %)', v_md5;
end $mig$;

commit;
```

## Registrador y reversa: misma plantilla que 20260929230336 (guardas `is not true`, ACL no nula, INVOKER exigido con `v_secdef is false`, relectura de la fila); se abrevian
```sql
-- REGISTRO en supabase_migrations.schema_migrations de 20260930000550_crm_postventa_tarea_json_por_familia.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si la función
-- no tiene la huella nueva o sus invariantes, o si la versión ya está registrada con otro nombre; relee la fila antes de confirmar.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_postventa_tarea_json_por_familia'));
do $chk$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'REGISTRO: la función no tiene la huella nueva (%); aplica primero la migración 20260930000550', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: dueño/ACL/definer/volatilidad/search_path no son los esperados (dueño %, acl %, definer %, vol %, cfg %); no se registra', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930000550' and coalesce(name,'') <> 'crm_postventa_tarea_json_por_familia') then
    raise exception 'REGISTRO: la versión 20260930000550 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930000550', 'crm_postventa_tarea_json_por_familia', array[$stm$
<definición nueva completa>
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930000550' and name = 'crm_postventa_tarea_json_por_familia') then
    raise exception 'REGISTRO: tras el insert, la versión 20260930000550 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_POSTVENTA_TAREA_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260930000550';
commit;

```

## Qué refutar
R1. La equivalencia: ¿algún caso (cadena > 15, ciclo, `inversionista_canonico_id` apuntando a un id inexistente,
`perfil_id` repetido en dos personas, `p_t.inversionista_id` NULL o de persona borrada) donde el array difiera?
R2. Rendimiento: la CTE recursiva por tarea sobre `inversionistas_canonico_idx`; ¿algún plan patológico?
R3. La migración: guardas (`is not true`, ACL no nula, `v_secdef is false`), idempotencia, huella sensible al
formato de `pg_get_functiondef` (falla cerrado).
R4. ¿Debería tratarse como LEVEL 3? La función no decide visibilidad (eso lo hace `private.postventa_visible`
antes de llamarla) y es INVOKER; ¿ves algún camino por el que el cambio amplíe lo que ve un rol?
