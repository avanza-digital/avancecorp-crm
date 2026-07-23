---
estado: "📋 PLAN BUILD-READY (2026-07-21) — C1 del reparto en el CRM (rol coordinador). Verificado por workflow de 15 agentes / 5 lentes: la lente RLS dio no-go (fuga de PII de clientes) → CORREGIDO en la misma migración. SIN construir; espera go de Miguel."
checkpoint: DL-01
fecha: 2026-07-21
confianza: alta
---

# Plan FINAL build-ready — C1: Reparto de la cola de leads desde el CRM (rol `coordinador`)

## ▶ ESTADO DE LA CONSTRUCCIÓN (2026-07-22)

Miguel dio el **go** y C1 se construyó completo. **Verde en branch, bloqueado antes del merge.**

| Etapa | Estado |
|---|---|
| Migración `20260721120000_crm_reparto_coordinador_c1.sql` | ✅ aplicada al branch `crm-reparto-c1` (ref `luwckkinaazzswmevlnj`) |
| Oráculo `supabase/scripts/test-reparto.sql` | ✅ **REPARTO_TX_OK** (R01–R27 a la primera) |
| Advisors (security + performance) del branch | ✅ **sin clases nuevas** (solo las 3 RPC en la clase WARN ya aceptada) |
| Frontend (§3/§4) | ✅ completo — rol off-roster, `screens/repartir.tsx`, guards en `lib/vistas.ts` (movidos fuera de `App.tsx` por fast-refresh), `database.types.ts`, store sin `listarEquipo` para el coordinador |
| E2E `e2e/repartir.spec.ts` | ✅ **8/8** por la RUTA REAL (sesión con rol `coordinador`, todo Supabase interceptado): aterrizaje en Repartir, nav reducido, expulsión de `#/mi-cartera`, PEN/USD separados, reparto con argumentos correctos + bandeja +1, veto legal `P0429` sin mover la fila, `P0002`, y los dos vacíos. El arnés `_helpers.ts` ganó las 3 RPC de reparto. Verlo en vivo: `npx playwright test e2e/repartir.spec.ts --headed` |
| Tests | ✅ **597/597** + typecheck + lint limpios (nuevos: `vistas.test.ts`, `crm-api-reparto-msw.test.ts`, `repartir.test.tsx`, ampliados `roles`/`router`/`auth-demo-sincronia`) |
| Suite `testReparto` del gate RLS | ✅ escrita y registrada en `main()`; fixtures `coordinador` validados en preflight |
| **Gate RLS vivo** | ✅ **`RLS OK — 283 aserciones; gate aprobado`** (eran 232 antes de C1). Requirió la `service_role` del branch, que Miguel entregó y se borró del disco tras usarla |
| Regresión de `metricas_agenda_fn` | ✅ probada por **hash**: quitando SOLO la línea del gate, el cuerpo del branch es idéntico al de prod (`f6ca9bbc…`) → cierra el riesgo residual de transcribir 190 líneas. Además oráculo `AGENDA_GATE_OK`: vendedor se ve a sí mismo, supervisor ve su subárbol, gerencia y lector global OK, coordinador y no-miembro bloqueados, validación de periodo intacta |
| Merge a prod · enrolar a Rosa · deploy FE | ⏸️ no ejecutados — esperan el visto bueno de Miguel (y saber quién es Rosa) |
| Build | `index-PURCREDK.js` md5 `4f49eab4375049eee761c872f0f1ae91` — construido, **NO desplegado** |

**Para desbloquear:** exportar `SUPABASE_URL=https://luwckkinaazzswmevlnj.supabase.co`, la anon key y la **service_role del branch** (`CRM_DEMO_PASSWORD` ya está en el `.env`) y correr `npm run seed:demo && npm run test:rls` desde `CRM-Avance-Corp/`. Luego: merge → enrolar a Rosa (§7) → deploy con hash vivo (§6) → **borrar el branch** (cuesta US$0.01344/h).

### ⚠️ Corrección al plan, verificada contra producción

**§2f.1 (`clientes_basicos_fn`) era una FALSA ALARMA y NO se aplicó.** El plan citó el cuerpo de la migración `20260711000003`, pero la definición **viva en prod** es la de `20260711000004`: scopeada **por cartera** (`asesor_perfil_id ∈ vendedor_ids_visibles`) y con 2 columnas añadidas después (`tipo_documento`, `creado_por`). Aplicar el SQL del plan habría (a) fallado por cambio de tipo de retorno y (b) de pasar, **revertido el scoping de cartera** — exactamente la fuga masiva de PII que la `000004` cerró. Con la definición real el coordinador ya obtiene 0 filas (no es lector global, no es gerencia, y su `vendedor_ids_visibles` es ∅). Quedó como **aserción del gate**, no como cambio de SQL. Las otras tres superficies (§2f.2 `existe_cliente_por_dni`, §2f.3 `objetivos_select`, §2f.4 `metricas_agenda_fn`) **sí** estaban abiertas y se endurecieron a allowlist; `metricas_agenda_fn` se re-creó con el cuerpo **verbatim leído de prod**, no del plan.

### Hallazgos de la re-revisión (2026-07-22, tras el gate)

Un barrido del catálogo de prod buscando **todo lo que ramifica por `rol_crm`** (24 funciones + 9 policies) confirmó que ninguna superficie más se abre con el rol nuevo, pero destapó **huecos de cobertura en el propio gate**, ya cerrados:
- `crm.contratos_cartera` (capital + nombre de cliente) — misma clase de PII que `clientes_basicos` y no estaba aseverada.
- `crm.convertir_lead` — tiene allowlist propia (`vendedor|supervisor`), así que el coordinador **no puede dar de alta clientes**; ahora se asevera para blindar ese candado.
- `crm.cerrar_tarea`, `crm.tareas` (insert) y las **4 RPC de métricas comerciales** — todas devuelven ∅ o bloquean; aseveradas.
- El nombre `metricas_distribucion_leads_autorizada` del plan **no existe como RPC**: es el helper `private.*`. Las expuestas son `metricas_distribucion_leads_fn` / `_v2_fn`, que enrutan por él (gate gerencia/lector) → el coordinador queda bloqueado igual.

El E2E además destapó un defecto real de la pantalla: con `StrictMode` (y en cualquier desmontaje) el fetch abortado se reportaba a observabilidad como `crm.reparto.cola_fallida`. Un fetch **abortado no es un fallo**: los dos lectores nuevos ya no lo reportan (se sigue propagando para que el llamador lo descarte). Sin ese arreglo, cada visita a la pantalla habría ensuciado Sentry con errores fantasma.

Dos bugs propios del código de test (no de la migración) corregidos en el camino: el nombre de RPC anterior, y sembrar sin `no_contactar` explícito — en un insert **por lotes** PostgREST normaliza las columnas del lote y las filas que lo omiten viajan con `null` explícito, violando el `NOT NULL` en vez de usar el default.

**Otro dato de realidad:** `crm.leads` ya no está en 0 — hay **1 lead real de prueba de Miguel** ("PRUEBA miguel", origen landing, USD 30 000, 2026-07-21) esperando en la cola global. Es la primera fila que verá la pantalla.

---

> Alcance: SOLO C1 (reparto de la COLA global de leads nuevos sin dueño → bandeja de un supervisor, iniciado por Rosa con rol `coordinador` desde dentro del CRM). C2 (base fría) queda fuera salvo notas de dependencia (§9). Todos los `archivo:línea` fueron verificados contra el árbol esta sesión.
>
> **Cambios vs. el plan base (integración de las 5 lentes):** (1) **[BLOQUEANTE]** la misma migración endurece 4 superficies adyacentes que el nuevo rol destapa al dejar de ser `rol_crm NULL` — `crm.clientes_basicos_fn`, `existe_cliente_por_dni`, `objetivos_select`, `metricas_agenda_fn` (§2f); (2) el veto legal usa **SQLSTATE propio `P0429`** (no 42501) para que su test no pueda pasar en falso (§2e/§5); (3) el `UPDATE` de reparto es **CAS auto-defendido** + se documenta READ COMMITTED (§2e); (4) el modelo de Rosa se fija **off-roster** de punta a punta, resolviendo la contradicción del plan base (§3); (5) el store **omite `listarEquipo` para el coordinador** para no tumbar su boot (§4); (6) tests nuevos: candado legal exacto + oráculo de estado, concurrencia real, superficies adyacentes, `sync_tareas` re-encolado, `ACCIONES` (§5).

---

## 1) Resumen + decisiones fijadas

**Qué construye C1.** Rosa (rol nuevo `coordinador`, mínimo privilegio) ve la cola de leads recién nacidos (los que entran por la hoja con `vendedor_id NULL AND asignado_supervisor_id NULL`) y los reparte a la **bandeja de un supervisor** (setea `asignado_supervisor_id`, deja `vendedor_id NULL`). El supervisor luego los baja a sus vendedores (fuera de C1).

**Por qué TODO pasa por RPCs SECURITY DEFINER (no por RLS ni por UPDATE de cliente).** Verificado:
- Un `coordinador` tiene visibilidad **∅** sobre `crm.leads`: `private.vendedor_ids_visibles` cae al `else -- vendedor` devolviéndose a sí mismo (`cimientos:106-108`), y como no posee leads, ninguna rama de `leads_select` (`cimientos:412-422`) lo deja ver la cola (la cola `ambos-null` solo la ve `gerencia` o `es_lector_global`).
- El `WITH CHECK` de `leads_update` (`cimientos:452-456`) exige que el supervisor destino ∈ `vendedor_ids_visibles(uid)` = `{self}` para coordinador → **cualquier** supervisor destino lo viola.
- Espejo FE: con `CAPS.coordinador.verTodo=false` y `rol!=='supervisor'`, `ambito.leads = []` (`store.tsx`); `actualizarLead` (`crm-api.ts:500-513`) devuelve `NO_ENCONTRADO` para coordinador.

Conclusión de diseño (intencional — mínimo privilegio): **NO tocar ninguna policy de `crm.leads`; NO añadir rama `coordinador` a `leads_select`/`leads_update`/`es_lector_global`; NO reusar `actualizarLead`/`store.reasignar`.** El reparto vive 100% en RPCs SECURITY DEFINER.

**⚠️ Corolario nuevo (lente RLS, BLOQUEANTE).** El aislamiento por `leads` NO basta: enrolar a Rosa hace que `private.rol_crm(uid)` deje de ser `NULL`, y hay **4 superficies gateadas por `rol_crm IS NOT NULL`** que la admitirían sin que ninguna policy de leads intervenga: `crm.clientes_basicos` (dni+correo+telefono+nombres de TODOS los clientes — PII más sensible que la propia cola), `existe_cliente_por_dni` (oráculo de enumeración de DNIs), `crm.objetivos` (metas de gerencia) y `metricas_agenda_fn` (agregados de agenda de todo el equipo). C1 **debe** endurecerlas en su misma migración (§2f). Sin esto el "gate NNN/NNN" pasa VERDE con la puerta de PII de clientes abierta (falsa seguridad).

**Decisiones fijadas por Miguel (2026-07-21):**
1. Rol de Rosa = `coordinador` **acotado** (mínimo privilegio; NO gerencia) → requiere ALTER del CHECK `equipo_rol_crm_check`.
2. Construir C1 YA, probando con **leads SEMILLA** (`crm.leads=0` hoy).
3. TODO el reparto dentro del CRM (nada en hoja/Apps Script/edge).
4. Legal (Ley 29571 "No Insista"): al repartir se re-valida la COLUMNA `no_contactar=false` server-side.

**Decisión de modelo de Rosa (fijada aquí para resolver la contradicción del plan base):** **`coordinador` es OFF-ROSTER, exactamente como `directorio`.** No es miembro de `crm.equipo` a efectos de roster/ámbito: `Miembro.rol_crm = Exclude<Rol,'directorio'|'coordinador'>`, no entra en `EQUIPO_DEMO`, y `RolCrmDb`/`ROLES_EQUIPO` no lo incluyen (se documenta el descarte). SÍ existe como identidad (`Yo.rol` lo incluye) y como fila real en `crm.equipo` (para que la RPC la gatee), pero jamás como fila de roster visible.

**Invariantes de BD que C1 obtiene GRATIS (ground-truth verificado):**
- CHECK `leads_tenencia_exclusiva`: nunca `vendedor_id` y `asignado_supervisor_id` a la vez.
- Guard `private.trg_leads_guard_tenencia` (`20260717212639:329-347`): al setear `asignado_supervisor_id`, el destino DEBE ser `crm.equipo.rol_crm='supervisor' AND activo`, o lanza *"La bandeja destino no pertenece a un supervisor activo"* (RAISE sin errcode → **P0001**). La rama "solo Gerencia deja el lead en cola global" (`:349-362`) **no** se dispara en C1.
- `trg_leads_reasignacion` (`20260717212639:435-513`) **auto-inserta** la actividad `reasignacion`/`entra_bandeja` con `creado_por=auth.uid()` (Rosa) → **la RPC NO inserta actividad manual**.
- El ledger `crm.lead_asignaciones` **no abre episodio** al parquear a bandeja (`v_new_debe_tener` exige `vendedor_id NOT NULL`) → consistente sin trabajo extra.
- `audit_log` deja fila con `usuario_id=Rosa`.

**Inventario COMPLETO de triggers que corren en el UPDATE de C1 (corrige "tareas: no-op" del plan base — lente de efectos colaterales).** El UPDATE de C1 cambia `asignado_supervisor_id` (null→sup); cada trigger de `crm.leads` es benigno:
| Trigger | Efecto en C1 | Por qué es benigno |
|---|---|---|
| `trg_leads_00_guard_tenencia` (BEFORE) | valida destino=supervisor activo | no toca cola-global (seteamos supervisor, no ambos-null) |
| `trg_leads_01_sla_global` (BEFORE) | preserva SLA; `ciclo_actual` no cambia | no reapertura |
| `trg_leads_before_update` (BEFORE) | `actualizado_en`; conserva inmutables | — |
| `trg_leads_bloquear_reasignacion` (BEFORE) | no-op | `vendedor_id` no cambia y el actor no es vendedor |
| `trg_leads_cambio_etapa` (BEFORE) | no-op | la etapa no cambia |
| `trg_leads_reasignacion` (BEFORE) | inserta actividad `entra_bandeja`, autor=Rosa | traza correcta |
| `trg_leads_asignaciones` (AFTER, ledger) | **sin episodio** | el parqueo a bandeja no abre episodio (por diseño) |
| **`trg_leads_zz_sync_tareas` (AFTER)** | **re-apunta tareas `pendiente` a la bandeja destino** | **matchea 0 filas para leads nuevos; N filas para un lead re-encolado por gerencia con pendientes → las tareas SIGUEN al lead (correcto)**. `trg_tareas_00_before_update` solo bloquea tareas ya cerradas; `pendiente` es editable (`20260718180001:157-159,205-210,224-225`) |
| `trg_audit_leads` (AFTER) | fila `usuario_id=Rosa` | traza correcta |

> **Camino alcanzable no cubierto por el plan base:** un lead que gerencia devolvió a la cola global (`vendedor→null`) conserva tareas `pendiente` y SÍ aparece en `leads_por_repartir`. Al repartirlo, `sync_tareas` re-apunta esas pendientes a la bandeja destino. Es seguro, pero hay que **probarlo** (§5, caso re-encolado) porque semillas/gate solo sembraban leads nuevos sin tareas.

**Nota de aislamiento (lente atomicidad).** La correctitud anti-carrera de `repartir_lead` asume **READ COMMITTED** (default de PostgREST/Supabase): el perdedor re-evalúa el `WHERE` al desbloquear (EvalPlanQual) → no encuentra fila → `P0002`. Bajo REPEATABLE READ/SERIALIZABLE el perdedor recibe `40001` (también seguro, sin doble-asignación). Ambos mapeados en el frontend (§4).

---

## 2) BD — migración con SQL concreto

**Archivo nuevo:** `CRM-Avance-Corp/supabase/migrations/20260721120000_crm_reparto_coordinador_c1.sql` (timestamp > `20260719120000`, el más reciente). Solo toca `crm`/`private` (respeta "ninguna migración del CRM altera `public`", `MIGRACIONES.md:6`). **Toda la migración va en UN solo `begin;…commit;`** (DDL transaccional): el `commit;` final está tras §2f, no tras §2e. Registrar la fila en `MIGRACIONES.md`.

### (a) ALTER del CHECK de rol (+ nota sobre el CHECK de capacidad)

```sql
begin;
set local lock_timeout = '10s';

-- 1) Rol 'coordinador' acotado en el CHECK de crm.equipo (net-new; hoy solo
--    vendedor|supervisor|gerencia — cimientos_crm.sql:42). Drop defensivo por si
--    el auto-nombre difiere en prod.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'equipo_rol_crm_check' and conrelid = 'crm.equipo'::regclass
  ) then
    alter table crm.equipo drop constraint equipo_rol_crm_check;
  end if;
end $$;

alter table crm.equipo add constraint equipo_rol_crm_check
  check (rol_crm in ('vendedor','supervisor','gerencia','coordinador'));
-- CHECK equipo_capacidad_leads_solo_analista (20260717215535:15-19) NO se toca:
-- la fila de Rosa nace con capacidad_leads_objetivo = NULL (satisface el CHECK).
```

> **PRERREQUISITO BLOQUEANTE**: sin este ALTER, `private.rol_crm` nunca devuelve `'coordinador'`, el gate de las RPC falla 100% y el enrolamiento de Rosa viola el CHECK (`23514`). Va **antes** de todo lo demás.

### (b) Parche a `private.vendedor_ids_visibles` — rama `coordinador` explícita (→ ∅)

Reproducción fiel de `cimientos:76-110` + rama nueva. Endurece la intención (∅ en vez del "self" implícito del `else`).

```sql
create or replace function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid
language plpgsql stable security definer
set search_path = crm, public
as $$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  select rol_crm into v_rol
  from crm.equipo where perfil_id = p_perfil_id and activo = true;

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select perfil_id from crm.equipo;
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select perfil_id from crm.equipo where perfil_id = p_perfil_id
        union
        select e.perfil_id from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select perfil_id from subarbol;
  elsif v_rol = 'coordinador' then
    return; -- ∅: el coordinador NO posee cartera ni ve leads por RLS;
            -- su reparto vive SOLO en RPCs SECURITY DEFINER (mínimo privilegio).
  else -- vendedor
    return next p_perfil_id;
  end if;
end;
$$;
```

### (c) Policies RLS de `crm.leads` — SIN CAMBIOS (decisión, no omisión)

`leads_select`/`leads_insert`/`leads_update` (`cimientos:412-459`) y `equipo_select` (`cimientos:143-149`) quedan **intactas**. Añadir `coordinador` filtraría la PII de la cola sin el shaping de la RPC. (Comentario en la migración: *"NO añadir coordinador a las policies de leads; su acceso es por RPC SECURITY DEFINER"*.)

> **Nota de defensa en profundidad (lente RLS, baja #5):** el `WITH CHECK` de `leads_insert` (`cimientos:429-435`) NO niega por sí solo al coordinador (`rol_crm IS NOT NULL` + `vendedor_id = auth.uid()` lo satisface); lo que impide que Rosa se auto-inserte un lead es **el trigger `trg_leads_guard_tenencia`** (destino vendedor debe ser vendedor|supervisor activo). Se sostiene, pero el bloqueo real recae en el trigger → **se prueba** en §5 (coordinador `insert (vendedor_id=self)` y `(ambos-null)` → ambos bloqueados), para detectar una regresión futura del guard.

### (d) RPC lectora — `crm.leads_por_repartir()`

Columnas verificadas (`cimientos:154-179`). Proyección **sin PII de contacto** (Rosa enruta, no contacta). Gate `coordinador|gerencia`.

```sql
create or replace function crm.leads_por_repartir()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric(12,2), moneda text,
  creado_en timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver la cola de leads por repartir'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en
  from crm.leads l
  where l.activo = true
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                       -- cola global (sin dueño)
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false                                 -- Ley 29571: nunca listar 'No Insista'
  order by l.creado_en asc;                                    -- FIFO justo
end;
$$;

comment on function crm.leads_por_repartir() is
  'Cola de leads nuevos sin dueño (vendedor_id y asignado_supervisor_id null) que el coordinador reparte. Excluye no_contactar=true (Ley 29571). Solo coordinador/gerencia activos.';

revoke all on function crm.leads_por_repartir() from public, anon;
grant execute on function crm.leads_por_repartir() to authenticated;
-- WARN authenticated_security_definer_function_executable: clase ACEPTADA/documentada.
```

> Opcional (enhancement): si se confirma `sla_global_iniciado_en` (`20260718152741`), proyectarla y ordenar `order by sla_global_iniciado_en asc nulls last, creado_en asc`.

### (d-bis) RPC compañera — `crm.supervisores_para_reparto()` (destino + carga)

**Necesaria**: el coordinador NO puede listar supervisores (`equipo_select` solo lo muestra a sí mismo). MVP = supervisores activos + `bandeja_pendiente`.

```sql
create or replace function crm.supervisores_para_reparto()
returns table (perfil_id uuid, nombre text, activo boolean, bandeja_pendiente integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver los supervisores de reparto'
      using errcode = '42501';
  end if;

  return query
  select e.perfil_id, p.nombre_completo, e.activo,
         (select count(*)::int from crm.leads l
           where l.asignado_supervisor_id = e.perfil_id
             and l.vendedor_id is null and l.activo = true
             and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
         ) as bandeja_pendiente
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'supervisor' and e.activo = true and p.activo = true
  order by p.nombre_completo;
end;
$$;

revoke all on function crm.supervisores_para_reparto() from public, anon;
grant execute on function crm.supervisores_para_reparto() to authenticated;
```

> **Enhancement (fase C1.1, opcional)** — cupos por equipo: añadir `capacidad_equipo` (Σ `capacidad_leads_objetivo` del supervisor + su subárbol recursivo sobre `crm.equipo.supervisor_id`) y `carga_activa_equipo` (Σ episodios abiertos del ledger con `finalizado_en IS NULL`). El subárbol se escribe **inline** (NO reusar `private.vendedor_ids_visibles(supervisor_id)`: su guard devuelve ∅ cuando `p_perfil_id != auth.uid()` y el actor no es lector global).

### (e) RPC de escritura — `crm.repartir_lead(p_lead uuid, p_supervisor uuid)` — [MODIFICADA: legal `P0429` + UPDATE CAS]

```sql
create or replace function crm.repartir_lead(p_lead uuid, p_supervisor uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor      uuid := (select auth.uid());
  v_lead       crm.leads%rowtype;
  v_sup_nombre text;
begin
  -- 1) Gate: coordinador|gerencia activos con perfil de portal activo.
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads' using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios' using errcode = '22023';
  end if;

  -- 2) Destino: supervisor ACTIVO (mensaje humano antes de tocar la fila; el
  --    guard BEFORE lo revalida con la MISMA frase — defensa en profundidad).
  select p.nombre_completo into v_sup_nombre
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_supervisor
    and e.rol_crm = 'supervisor' and e.activo = true and p.activo = true;
  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  -- 3) Toma el lead de la COLA GLOBAL y bloquéalo (FOR UPDATE) en la MISMA tx.
  --    Necesario para (a) leer no_contactar sobre la fila bloqueada y (b) dar el
  --    P0002 con mensaje humano. Bajo READ COMMITTED (default de PostgREST) el
  --    perdedor de una carrera re-evalúa el WHERE al desbloquear (EvalPlanQual)
  --    y NO encuentra fila → P0002. (Bajo aislamiento mayor: 40001.)
  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
  for update;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  -- 4) Re-validación legal server-side (Ley 29571 'No Insista') — Decisión #4.
  --    SQLSTATE PROPIO 'P0429' (NUNCA 42501): así el candado de test NO se
  --    satisface con un 42501 accidental de autorización, y el frontend distingue
  --    "veto legal" de "sin permiso". El RAISE revierte toda la tx.
  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;

  -- 5) UPDATE con CANDADO CAS: el predicado de tenencia va TAMBIÉN aquí (no solo
  --    en el SELECT del paso 3) → la mutación se auto-defiende de la carrera
  --    aunque un refactor futuro debilite el FOR UPDATE. Si otra tx ganó, afecta
  --    0 filas → P0002. Los triggers hacen la actividad ('entra_bandeja',
  --    autor=Rosa) y la auditoría; NO insertar actividad manual ni escribir ledger.
  update crm.leads
     set asignado_supervisor_id = p_supervisor
   where id = p_lead and activo = true
     and vendedor_id is null and asignado_supervisor_id is null;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'lead_id', p_lead, 'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre, 'repartido_por', v_actor,
    'repartido_en', statement_timestamp());
end;
$$;

comment on function crm.repartir_lead(uuid, uuid) is
  'El coordinador mueve un lead de la cola global a la bandeja de un supervisor activo (asignado_supervisor_id, vendedor_id sigue null). Re-valida no_contactar (Ley 29571) con SQLSTATE propio P0429. UPDATE con predicado CAS anti-carrera. Actividad y auditoría por trigger. Solo coordinador/gerencia activos. Asume READ COMMITTED.';

revoke all on function crm.repartir_lead(uuid, uuid) from public, anon;
grant execute on function crm.repartir_lead(uuid, uuid) to authenticated;
```

### (f) Endurecimiento de superficies ADYACENTES — [NUEVO, cierra 1 BLOQUEANTE + 1 ALTA + 2 MEDIAS de la lente RLS]

> Todas pasan de `rol_crm IS NOT NULL` a la **allowlist operativa** `IN ('vendedor','supervisor','gerencia')` (deny-by-default: coordinador y cualquier rol futuro no-operativo quedan excluidos). **Regresión CERO** para vendedor/supervisor/gerencia/lector (siguen admitidos) y para service_role (su comportamiento actual — 0 filas / RAISE — no cambia). Verificado contra los cuerpos actuales.

```sql
-- f.1 [BLOQUEANTE] crm.clientes_basicos_fn (20260711000003:15-33): sin esto Rosa
--     leería dni+correo+telefono+nombres de TODOS los clientes por Data API
--     (.from('clientes_basicos')). La vista invoker crm.clientes_basicos NO cambia.
create or replace function crm.clientes_basicos_fn()
returns table (
  id uuid, nombres text, apellidos text, nombre_completo text, dni text,
  correo text, telefono text, asesor_perfil_id uuid, activo boolean, creado_en timestamptz)
language sql stable security definer set search_path = private, public
as $$
  select p.id, p.nombres, p.apellidos, p.nombre_completo, p.dni, p.correo,
         p.telefono, p.asesor_perfil_id, p.activo, p.creado_en
  from public.perfiles p
  where p.rol = 'cliente'
    and (
      coalesce((select private.rol_crm((select auth.uid())))
               in ('vendedor','supervisor','gerencia'), false)
      or (select private.es_lector_global())
    );
$$;
-- ACL preservada por CREATE OR REPLACE.

-- f.2 [ALTA] crm.existe_cliente_por_dni (cimientos:519-533): oráculo de
--     enumeración de DNIs. Gate → allowlist + errcode ESTABLE 42501 (antes RAISE
--     sin errcode → P0001). Coalesce para que rol_crm NULL siga bloqueado (3VL).
create or replace function crm.existe_cliente_por_dni(p_dni text)
returns boolean
language plpgsql stable security definer set search_path = private, public
as $$
begin
  if not (
    coalesce(private.rol_crm((select auth.uid()))
             in ('vendedor','supervisor','gerencia'), false)
    or private.es_lector_global()
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  return exists (
    select 1 from public.perfiles
    where dni = p_dni and rol = 'cliente' and activo = true
  );
end;
$$;

-- f.3 [MEDIA] crm.objetivos: metas comerciales. Policy → allowlist (ALTER; NO
--     tocar la RPC de escritura crm.fijar_objetivos ni los grants). Fuente:
--     20260719120000:67-72.
alter policy objetivos_select on crm.objetivos
  using (
    coalesce((select private.rol_crm((select auth.uid())))
             in ('vendedor','supervisor','gerencia'), false)
    or (select private.es_lector_global())
  );

-- f.4 [MEDIA] crm.metricas_agenda_fn(date,date): agregados de agenda de TODO el
--     equipo. Se re-crea con CREATE OR REPLACE COPIANDO EL CUERPO VERBATIM de
--     20260719013000_crm_metricas_agenda_fn.sql (líneas 36-232, TODOS los CTEs
--     visibles/toques/cierres/creadas/movidas/foto/sin_accion/payload + grants +
--     comment) y sustituyendo SOLO el bloque de gate de miembro activo (:60-65):
--
--        select exists (
--          select 1 from crm.equipo e
--          join public.perfiles p on p.id = e.perfil_id
--          where e.perfil_id = v_uid and e.activo and p.activo
--            and e.rol_crm in ('vendedor','supervisor','gerencia')  -- excluye coordinador
--        ) into v_miembro_activo;
--
--     El resto del cuerpo NO cambia (el recorte por vendedor_ids_visibles ya deja
--     ∅ al coordinador aunque pasara el gate; esto lo bloquea de raíz). ACL
--     preservada por CREATE OR REPLACE — no hace falta re-grant.
--     (crm.metricas_distribucion_leads_autorizada YA es gerencia/lector-gated,
--     20260718152741:550-563 → coordinador ya bloqueado; sin cambio SQL, solo
--     aserción de gate en §5.)

commit;   -- ← ÚNICO commit de la migración, tras §2f.
```

### Mensajes de error (SQLSTATE) — tabla de contrato para gate + frontend

| SQLSTATE | Origen | Frontend (`aErrorApi`) |
|---|---|---|
| `42501` | gate de rol de las 3 RPCs; `clientes_basicos_fn`/`existe_cliente_por_dni` denegados | `SIN_PERMISO` |
| `22023` | args nulos; destino no-supervisor (pre-check paso 2) | `REGLA_SERVIDOR` (surfacea el mensaje) |
| `P0002` | lead fuera de cola (SELECT..FOR UPDATE) **o** carrera perdida (CAS UPDATE) | `FUERA_DE_COLA` |
| **`P0429`** | **veto legal No Insista (NUEVO, no-auth)** | **`NO_INSISTA`** |
| `P0001` | guard `trg_leads_guard_tenencia` (carrera de desactivación de supervisor entre paso 2 y 5) | `REGLA_SERVIDOR` (surfacea "La bandeja destino…") — **ya cubierto** |
| `40001` | carrera bajo aislamiento serializable (defensivo) | `REINTENTAR` |

---

## 3) Propagación del rol `coordinador` — archivos a tocar (backend + frontend)

> Dos vocabularios SIN fuente única: SQL (CHECK + literales) y FE (`lib/roles.ts`). Los `Record<Rol,…>` son una red de seguridad: al añadir `coordinador` a `ROLES`, TypeScript **obliga** (no compila) a completar `CAPS`, `ROL_LABEL`, `DEMO_YO`, `DEMO_SUB`.

**SQL (en la migración de §2):**
| Punto | Cambio | Riesgo si se omite |
|---|---|---|
| `cimientos:42` CHECK rol | ALTER +`coordinador` (§2a) | No se enrola a Rosa (23514); `rol_crm` nunca devuelve `coordinador` |
| `cimientos:76-110` `vendedor_ids_visibles` | rama `coordinador`→∅ (§2b) | (Defensivo) evita que alguien lo "arregle" ampliando visibilidad |
| **Superficies adyacentes** (`clientes_basicos_fn`, `existe_cliente_por_dni`, `objetivos_select`, `metricas_agenda_fn`) | **allowlist (§2f)** | **BLOQUEANTE/ALTA/MEDIA: fuga de PII de clientes / oráculo DNI / metas / agenda** |
| Policies `leads_*`, `equipo_select`, `es_lector_global`, capacidad CHECK | **NO tocar** | Añadir `coordinador` = fuga masiva de PII de la cola |

**Frontend — `lib/roles.ts`:**
- `roles.ts:6` `ROLES` → añadir `'coordinador'` **al final**: `['vendedor','supervisor','gerencia','directorio','coordinador']`. **Load-bearing**: `esRol` (`:11`) se deriva de aquí; `auth.tsx` hace `esRol(miembro.rol_crm)`; sin esto Rosa degrada a `no_enrolado`.
- `roles.ts:15-24` `type Accion` → añadir **`'repartirCola'`** (gate de la pantalla, distinta de `'repartirLeads'`) y **`'verCartera'`** (para ocultar/expulsar "Mi cartera" a Rosa). Pasa de 9 a **11** acciones.
- `roles.ts:28-53` `CAPS` (`Record<Rol,Caps>`, compile-forced):
  - Fila nueva `coordinador` **al final** (para que `Object.keys(CAPS)` termine en `'coordinador'`, coherente con el `toEqual` del test): `verTodo:false` (**CRÍTICO**), `verEquipo:false`, `filtrarPorVendedor:false`, `reasignar:false`, `repartirLeads:false`, `repartirCola:true`, `verConfiguracion:false`, `editarConfiguracion:false`, `verReportes:false`, `soloLecturaTotal:false`, `verCartera:false`.
  - En las 4 filas existentes añadir las 2 claves nuevas: `verCartera:true` (todas) y `repartirCola:` → `true` solo en `gerencia`, `false` en `vendedor/supervisor/directorio`.
- `roles.ts:55-60` `ROL_LABEL` → `coordinador: 'Coordinador'`.

**Frontend — resto de `Record<Rol>` / demo / tipos (modelo OFF-ROSTER — resuelve la contradicción del plan base):**
| Archivo:línea | Cambio | Nota |
|---|---|---|
| `lib/auth-demo.ts:10-15` `DEMO_YO` (`Record<Rol>`, compile-forced) | `coordinador: { id: 'demo-coordinador', nombre_completo: 'COORDINADOR (DEMO)' }` — **id sintético off-roster**, espejo de `directorio` (`:14`) | NO literal de `EQUIPO_DEMO` |
| `screens/login.tsx:13-18` `DEMO_SUB` (`Record<Rol>`, compile-forced; el grid itera `ROL_LABEL`) | `coordinador: 'reparte la cola de leads nuevos'` | Botón demo aparece solo |
| `lib/demo.ts` `EQUIPO_DEMO` | **NO añadir miembro** `coordinador` | **CORRIGE el plan base** (que pedía añadirlo): Rosa es off-roster; añadirlo rompería el modelo y contradiría `Miembro.rol_crm` |
| `lib/tipos.ts:230` `Miembro.rol_crm` | **`Exclude<Rol,'directorio'|'coordinador'>`** | Rosa NO es miembro del roster (igual que directorio) |
| `data/crm-api.ts:353` `ROLES_EQUIPO` + `:354-360` `MiembroRowSchema` | **NO tocar**; añadir comentario en `:353`: *"'coordinador' es off-roster (como 'directorio'): equipo_visible_fn no debe devolverlo; si lo hiciera, el picklist lo descarta a propósito (safeParse, :373-375)"* | Descarte silencioso **intencional y documentado** |
| `lib/database.types.ts:14` `RolCrmDb` | **NO tocar** (queda `vendedor|supervisor|gerencia`) + comentario: *"coordinador existe en el CHECK pero es off-roster; type-lie conocido y aceptado"* | `equipo.Row.rol_crm` no lo declara; no rompe build (validación en runtime por `esRol`) |

> **`Yo` (tipos.ts:235-239)** SÍ incluye `coordinador` (`rol: Rol`) — es la identidad logueada, no una fila de roster. `auth.tsx` la arma vía `esRol(rol_crm)`. Consistente.

---

## 4) Frontend — pantalla `Repartir leads`

**Ruteo/menú/gating (doble defensa: el nav oculta, el guard expulsa, la RPC niega).**

- `lib/router.ts:9` `VISTAS` → añadir `'repartir'`. **NO** a `VISTAS_LEADS` (`:17`) — o el gate de leads (cerrado para coordinador) la ocultaría a quien debe verla.
- `components/app/topbar.tsx:25-33` `TITULOS` → `repartir: { t: 'Repartir leads', s: 'Reparte la cola de leads nuevos a los supervisores' }`.
- `components/app/sidebar.tsx:2-5` importar icono (`Split`/`Shuffle`); `:21-30` `NAV` → `{ id: 'repartir', label: 'Repartir leads', icon: Split, cap: 'repartirCola' }`; y a `mi-cartera` añadir `cap: 'verCartera'`. El filtro `:158` `(leadsVisibles || !esVistaLeads(n.id)) && (!n.cap || can(rol, n.cap))` lo resuelve.
- `App.tsx` (import): `const Repartir = lazy(() => import('@/screens/repartir').then((m) => ({ default: m.Repartir })))`; asegurar `import { can, type Rol } from '@/lib/roles'` (can ya se usa en `:144`).

**App.tsx — helper + guards [CORREGIDO a la firma REAL de `sanearVista`, que toma booleans, no `rol`].** La función real es `sanearVista(vista, puedeConfig, puedeEquipo, leadsVisibles)` con `base` hardcodeado a `'mi-cartera'`/`'hoy'`. Se reemplaza por un `vistaBase` capability-driven (aterriza al coordinador en `repartir`) y `sanearVista` pasa a recibir `rol`:

```ts
function vistaBase(rol: Rol | null | undefined, leadsVisibles: boolean): Vista {
  // Coordinador (reparte la cola, sin cartera) aterriza en 'repartir'.
  if (can(rol, 'repartirCola') && !can(rol, 'verCartera')) return 'repartir'
  return leadsVisibles ? 'hoy' : 'mi-cartera'
}

function sanearVista(vista: Vista, rol: Rol | null | undefined, leadsVisibles: boolean): Vista {
  const base = vistaBase(rol, leadsVisibles)
  if (!leadsVisibles && esVistaLeads(vista)) return base
  if (vista === 'config'     && !can(rol, 'verConfiguracion')) return base
  if (vista === 'equipo'     && !can(rol, 'verEquipo'))        return base
  if (vista === 'repartir'   && !can(rol, 'repartirCola'))     return base
  if (vista === 'mi-cartera' && !can(rol, 'verCartera'))       return base // [lens4-baja] cierra #/mi-cartera por URL
  return vista
}
```

Aplicar `vistaBase`/`rol` en los sitios donde hoy están los booleans hardcodeados:
- **`useState` inicial (`:141-148`)**: `sanearVista(leerHash().vista ?? vistaBase(rol, leadsVisibles), rol, leadsVisibles)`.
- **listener hashchange (`:164-169`)**: `sanearVista(leido.vista ?? vistaBase(ctx.rol, ctx.leadsVisibles), ctx.rol, ctx.leadsVisibles)`.
- **efecto de expulsión (`:212-217`)**: `const base = vistaBase(rol, leadsVisibles)`; conservar las 3 reglas actuales y **añadir**: `if (vista === 'repartir' && !can(rol,'repartirCola')) setVista(base)` y `if (vista === 'mi-cartera' && !can(rol,'verCartera')) setVista(base)`.
- **switch de render (`:228-234`)**: añadir `{vista === 'repartir' && <Repartir />}`.

**Store — boot del coordinador [CORRIGE Riesgo #9 del plan base: `listarEquipo` es INCONDICIONAL y puede tumbar la sesión].** `cargarReal` (`store.tsx:427-453`) hace `Promise.all([... listarEquipo(signal) ...])` sin `.catch`; si `equipo_visible_fn` (prod-only) hace `raise` para un llamador `coordinador`, el `Promise.all` rechaza → `catch` (`:524-533`) → `setErrorReal(true)` → Rosa nunca llega a `Repartir`. Fix auto-suficiente (NO depende del comportamiento desconocido de la RPC): **omitir `listarEquipo` para el coordinador** (su pantalla usa `supervisores_para_reparto`, no `ambito.equipo`, y no tiene leads que nombrar):

```ts
const cargarReal = useCallback(async (signal?: AbortSignal) => {
  const esCoordinador = yo?.rol === 'coordinador'
  const [leads, miembros, actividades, tareasAmbito, filasObjetivos] = await Promise.all([
    listarLeadsDelAmbito(signal),
    // Coordinador off-roster: sin cartera ni panel de equipo; listarEquipo→
    // equipo_visible_fn podría RAISE para su rol (prod-only) y tumbar el boot.
    esCoordinador ? Promise.resolve([] as Miembro[]) : listarEquipo(signal),
    listarActividadesDelAmbito(signal),
    listarTareasDelAmbito(signal),
    listarObjetivos(periodoLima(Date.now()), signal).catch((error: unknown) => {
      registrarError('crm.objetivos.boot_degradado', error); return []
    }),
  ])
  // …resto igual…
}, [yo?.rol])   // ← dep nueva; el efecto de :542 ya incluye cargarReal
```

> Los demás fetches del `Promise.all` son seguros para coordinador: `listarLeadsDelAmbito`/`listarActividadesDelAmbito`/`listarTareasDelAmbito` leen por RLS ∅ → `[]` (RLS **filtra**, no lanza); `listarObjetivos` lee `crm.objetivos` por RLS (tras §2f, coordinador ∉ allowlist → 0 filas, no error) y además ya está envuelto en `.catch`. El ÚNICO riesgo de boot era `listarEquipo` (RPC que puede RAISE) → resuelto. (Importar el tipo `Miembro` en `store.tsx` si no está.)

**`data/crm-api.ts` — nuevas funciones (frontera Valibot como el resto):**
- `leadsPorRepartir(signal?): Promise<ColaLead[]>` → `.schema('crm').rpc('leads_por_repartir')`, `safeParse` por fila.
- `supervisoresParaReparto(signal?): Promise<SupervisorReparto[]>` → `.rpc('supervisores_para_reparto')`.
- `repartirLead(leadId, supervisorId): Promise<void>` → `.rpc('repartir_lead', { p_lead: leadId, p_supervisor: supervisorId })`; mapear error con `aErrorApi`.

**`data/crm-api.ts` — `aErrorApi` (`:449-493`): añadir ramas al else-if (antes de la rama final `P0001||22023`):**
```ts
} else if (codigoPg === 'P0429') {         // veto legal Ley 29571 (No Insista) — código propio, no auth
  code = 'NO_INSISTA'
  mensaje = error.message ?? 'Lead marcado No Insista (Ley 29571): no se puede repartir'
} else if (codigoPg === 'P0002') {         // lead fuera de la cola (dueño/cerrado) o carrera perdida
  code = 'FUERA_DE_COLA'
  mensaje = error.message ?? 'El lead ya no está en la cola por repartir'
} else if (codigoPg === '40001') {         // carrera bajo aislamiento serializable (defensivo)
  code = 'REINTENTAR'
  mensaje = 'El lead se estaba repartiendo en simultáneo. Vuelve a intentarlo.'
}
```
> `42501`→`SIN_PERMISO` (gate) y `22023`/`P0001`→`REGLA_SERVIDOR` (surfacea el mensaje del destino/guard) **ya existen** (`:481-489`) → la carrera de desactivación de supervisor (P0001) ya muestra "La bandeja destino no pertenece a un supervisor activo". No requiere cambio.

**`lib/tipos.ts`:** `ColaLead` (`id, nombre_completo, distrito, origen, categoria_interes, monto_estimado, moneda, creado_en`) y `SupervisorReparto` (`perfil_id, nombre, activo, bandeja_pendiente` [+cupos opcional]).

**`screens/repartir.tsx` (`export function Repartir()`):** hook local `useReparto()` con estado `{ cola, supervisores, cargando, error, enviandoId }`; en montaje `Promise.all([leadsPorRepartir(sig), supervisoresParaReparto(sig)])`; `repartir(leadId, supId)`: `setEnviando` → `await repartirLead` → éxito: quita la fila de `cola` (optimista) + `toast.success` + refetch de `supervisores`; error: `toast.error(mensaje)`. Cabecera con conteo de cola + **capital PEN/USD separado** (jamás sumados). `PanelVacio` que encamina a la acción cuando la cola está vacía. Sin XState (estado React; XState solo en auth).

**Componentes a reusar** (lenguaje visual existente): card de lead (`equipo.tsx:240-257` + `moneyK` moneda-aware `format.ts:13-22`); chip capital PEN protagonista + USD aparte (`equipo.tsx:75-83`); Select "Asignar a…" (`components/ui/select`, patrón `equipo.tsx:258-276`) poblado con `supervisoresParaReparto()` mostrando `bandeja_pendiente`; estados `estado-panel` (`PanelVacio/Cargando/Error`), `SectionHead/StatStrip`.

**Landing del coordinador**: `vistaBase` lo aterriza en `repartir`; su nav se reduce a `[Repartir leads]`. **Demo**: en modo demo no hay RPC; `useReparto` lee una cola demo de fixtures o muestra vacío (enhancement no bloqueante — la validación real es §7).

---

## 5) Tests / gate

**Gate RLS `supabase/scripts/test-rls.mjs` (sesiones reales; rehúsa prod). Tres capas:**

1. `scripts/fixtures.mjs`:
   - `USERS` (`:8-129`): `{ key:'coordinador', email:'coordinador.crm@demo.avancecorp.pe', name:'COORDINADOR DEMO', portalRole:'comercial', crmRole:'coordinador', supervisorKey:null, portalActive:true, crmActive:true }`. **PRECONDICIÓN DURA (lente RLS baja #6): `portalRole` ∈ {`comercial`,`analista`} y NUNCA {`directorio`,`admin`,`superadmin`}** — un rol de portal lector-global colapsaría el modelo ∅.
   - `EXPECTED_LEAD_NAMES.coordinador = []` y `EXPECTED_TAREA_TITULOS.coordinador = []` (`validateFixtureModel` exige ambas matrices completas o aborta en preflight).
2. `scripts/seed-demo.mjs` `ensureTeam` (`:215-230`): upsertea `rol_crm=crmRole` automáticamente — pero **la migración del CHECK (§2a) debe estar aplicada al branch ANTES** del seed (o el upsert de Rosa falla `23514`).
3. `test-rls.mjs`: nueva suite `testReparto(sessions, seed)` + registrarla en `main()` (`:1769-1780`, tras `testObjetivos`). Molde: `testObjetivos`. **Recordar la trampa `expectBlockedMutation` (`:261-287`): auto-aprueba CUALQUIER `42501` (`isAuthorizationError`, `:174`); los demás códigos DEBEN ir en `allowedErrorCodes`.**

   **(A) Aislamiento del coordinador — superficies adyacentes (cierra bloqueante/alta/medias):**
   - `expectHidden('coordinador clientes_basicos → 0 filas', coordinador.schema('crm').from('clientes_basicos').select('id'))`.
   - `expectBlockedMutation('coordinador existe_cliente_por_dni', coordinador.schema('crm').rpc('existe_cliente_por_dni',{p_dni:'99999999'}))` — 42501 (auto-ok, es auth genuina).
   - `expectHidden('coordinador objetivos → 0 filas', coordinador.schema('crm').from('objetivos').select('id'))`.
   - `expectBlockedMutation('coordinador metricas_agenda', coordinador.schema('crm').rpc('metricas_agenda_fn',{p_desde,p_hasta}))` — 42501.
   - `expectBlockedMutation('coordinador metricas_distribucion', coordinador.schema('crm').rpc('metricas_distribucion_leads_autorizada',{...}))` — 42501 (ya gerencia-gated).
   - **Control de acceso de las 3 RPCs nuevas**: para cada una `positive('coordinador…')`, `positive('gerencia…')`, `expectBlockedMutation('vend1/sup1/directorio…', ['42501'])`; anon en `testAnon` (`:1708-1746`).
   - **leads_insert (defensa del guard, baja #5)**: `expectBlockedMutation('coordinador insert lead vendedor=self', coordinador.schema('crm').from('leads').insert({...vendedor_id:coordId...}))` y `expectBlockedMutation('coordinador insert lead ambos-null', …)` — declarar `allowedErrorCodes` con el/los códigos del guard (`['P0001','42501']`) según cómo caiga.

   **(B) Semillas** (service_role, `TRANSIENT_IDS`, patrón `:1059-1069`): en la cola global (`vendedor_id NULL, asignado_supervisor_id NULL, activo, etapa 'nuevo'`, teléfonos distintos por `uq_leads_telefono_vivo`): un lead **contactable** (`no_contactar=false`), un lead **`no_contactar=true`**, y un **lead re-encolado con tarea pendiente** (lead ambos-null + fila `crm.tareas` `estado='pendiente'`, `vendedor_id NULL`, `asignado_supervisor_id NULL`, `lead_id`=ese lead).

   **(C) `repartir_lead` — reglas de negocio + oráculos de estado:**
   - **Éxito** (`positive`): coordinador reparte el contactable a `sup1` → relectura service_role (`:1395-1405`): `check(row.asignado_supervisor_id===sup1 && row.vendedor_id===null, 'quedó en bandeja, nunca ambos')`.
   - **[CANDADO LEGAL — reemplaza `expectBlockedMutation` por aserción de código EXACTO]**: el `no_contactar` NO usa `expectBlockedMutation` (tragaría un 42501 accidental). En su lugar:
     ```js
     const rLegal = await coordinador.schema('crm').rpc('repartir_lead',{p_lead:idNoContactar,p_supervisor:sup1})
     check(!!rLegal.error && String(rLegal.error.code)==='P0429',
       'no_contactar: bloqueado con código LEGAL P0429 (no auth 42501)', errorText(rLegal.error))
     // Oráculo de ESTADO (service_role): el lead permaneció en la cola, sin bandeja.
     const row = await service.schema('crm').from('leads').select('asignado_supervisor_id,vendedor_id').eq('id',idNoContactar).single()
     check(row.data?.asignado_supervisor_id===null && row.data?.vendedor_id===null,
       'no_contactar: permaneció en la cola global (sin bandeja)')
     // Y NUNCA aparece en la cola que ve el coordinador.
     const cola = await coordinador.schema('crm').rpc('leads_por_repartir')
     check(Array.isArray(cola.data) && !cola.data.some(l=>l.id===idNoContactar),
       'no_contactar: nunca listado en leads_por_repartir')
     ```
     Este candado falla si (a) se elimina el `if v_lead.no_contactar` (la mutación tendría éxito → `row` cambia), o (b) se cambia el código legal a 42501/otro. Cierra el falso-verde del plan base.
   - **Destino no-supervisor** (`expectBlockedMutation`, destino=`vend1`/`gerencia`/coordinador) → `allowedErrorCodes: ['22023']`.
   - **Lead ya con dueño / fuera de cola** (`expectBlockedMutation`) → `['P0002']`.
   - **[CONCURRENCIA — invariante central, antes SIN cobertura]**: dos sesiones reales disparan `repartir_lead` sobre el MISMO lead **en paralelo** (NO secuencial):
     ```js
     const [a,b] = await Promise.allSettled([
       coordinador.schema('crm').rpc('repartir_lead',{p_lead:idCarrera,p_supervisor:sup1}),
       gerencia.schema('crm').rpc('repartir_lead',{p_lead:idCarrera,p_supervisor:sup2}),
     ])
     const oks = [a,b].filter(r=>r.status==='fulfilled' && !r.value.error)
     const errs= [a,b].filter(r=>r.status==='fulfilled' &&  r.value.error)
     check(oks.length===1 && errs.length===1, 'carrera: exactamente uno gana')
     check(['P0002','40001'].includes(String(errs[0]?.value.error.code)),
       'carrera: el perdedor recibe P0002 (o 40001 si el aislamiento es mayor)')
     const row = await service.schema('crm').from('leads').select('asignado_supervisor_id,vendedor_id').eq('id',idCarrera).single()
     check([sup1,sup2].includes(row.data?.asignado_supervisor_id) && row.data?.vendedor_id===null,
       'carrera: un solo supervisor asignado, vendedor null')
     ```
   - **[SYNC_TAREAS re-encolado — único camino con filas reales]**: coordinador reparte el lead re-encolado a `sup1`; relectura service_role de la tarea: `check(t.asignado_supervisor_id===sup1 && t.vendedor_id===null && t.estado==='pendiente', 'la pendiente siguió al lead a la bandeja, sin bloqueo')`.
   - El conteo del gate sube según las aserciones (`:1809-1814`) → "gate NNN/NNN" crece.
   - **Oráculo SQL `scripts/test-reparto.sql`** (patrón 4A-4C, token `REPARTO_TX_OK`, `SET request.jwt.claims` simulando coordinador): complementa el gate; incluir un bloque de concurrencia con `dblink`/dos sesiones si se quiere el escenario de lock a nivel SQL (el de Node ya lo cubre).

**Frontend (Vitest + MSW):**
- `lib/roles.test.ts`: **[dos ediciones, no una]** (1) `ACCIONES` (`:4-14`) → añadir `'repartirCola'` y `'verCartera'` (si no, `expect(Object.keys(CAPS[rol]).sort()).toEqual([...ACCIONES].sort())` en `:22` falla para TODOS los roles → gate ROJO); (2) `toEqual` de `roles` (`:20`) → `['vendedor','supervisor','gerencia','directorio','coordinador']` (orden = inserción en `CAPS`). Añadir aserciones: `can('coordinador','repartirCola')===true`, `can('coordinador','verTodo')===false`, `can('coordinador','verCartera')===false`, `can('supervisor','repartirCola')===false`, `can('gerencia','repartirCola')===true`.
- `lib/auth-demo-sincronia.test.ts`: **[CORRIGE el plan base]** NO añadir `'coordinador'` al `it.each` (`:11`) — es off-roster y no existe en `EQUIPO_DEMO`. En su lugar, extender el bloque "FUERA del organigrama" (`:23-26`) para cubrir también `DEMO_YO.coordinador.id` (mismo assert que `directorio`): `expect(idsEquipo.has(DEMO_YO.coordinador.id)).toBe(false)`.
- `lib/router.test.ts` — `#/repartir` resuelve; `vistaBase('coordinador', false)==='repartir'`; un `#/hoy` para coordinador se reescribe a `repartir`; `#/mi-cartera` para coordinador se reescribe a `repartir` (nuevo guard).
- `data/crm-api` MSW — `leadsPorRepartir`/`supervisoresParaReparto`/`repartirLead`: happy path + mapeo de error (`P0429`→`NO_INSISTA`, `P0002`→`FUERA_DE_COLA`, `22023`/`P0001`→`REGLA_SERVIDOR`, `42501`→`SIN_PERMISO`).
- `screens/repartir.tsx` — test de componente (MSW): carga cola+supervisores, asigna, remoción optimista de la fila, toast de error en rechazo (incl. `NO_INSISTA`), `PanelVacio` con cola vacía.

---

## 6) Runbook de despliegue

> Regla de árbol compartido (memoria): Miguel corre varias sesiones de IA sobre el mismo working tree. Antes de git/deploy: `git status` (hay un `.gs` modificado y una nota de vault sin trackear — **no** barrerlos al commit de C1), staging **selectivo**, hash **vivo** antes/después, contrastar contra el ledger de deploys del vault.

**Fase BD (ciclo obligatorio `MIGRACIONES.md:4`):**
1. `git status` — aislar los archivos de C1.
2. **Branch de Supabase** (`create_branch`) — nunca `apply_migration` directo a prod.
3. Aplicar `20260721120000_crm_reparto_coordinador_c1.sql` al branch (incluye §2a CHECK, §2b visibilidad, §2d/d-bis/e RPCs y **§2f endurecimiento de superficies adyacentes**).
4. (Opcional) `scripts/test-reparto.sql` contra el branch → esperar `REPARTO_TX_OK`.
5. Fixtures del coordinador (§5) + **gate**: `node scripts/test-rls.mjs` con `SUPABASE_URL`=URL del **branch**. Exigir `RLS OK — N aserciones; gate aprobado`, **incluyendo** las nuevas aserciones de superficies adyacentes (clientes_basicos=0, existe_cliente_por_dni bloqueado, objetivos=0, metricas_agenda bloqueado), el candado legal `P0429` + oráculo de estado, la concurrencia y `sync_tareas`.
6. `get_advisors(security)` + `get_advisors(performance)` sobre el branch. Aceptar el WARN `authenticated_security_definer_function_executable` (clase documentada). **Rechazar** clases NUEVAS. (Las funciones de §2f son CREATE OR REPLACE de funciones ya existentes → no deberían introducir clases nuevas.)
7. `merge_branch` → `list_migrations` para confirmar en prod.
8. **(Defensa en profundidad, ya no bloqueante)** Verificar en prod que `equipo_visible_fn` para un llamador `coordinador` **devuelve conjunto vacío** (no `raise`). *El store ya no depende de esto* (§4 omite `listarEquipo` para coordinador), pero deja constancia del comportamiento real en el vault.
9. **Enrolar a Rosa** (post-merge, §7).

**Fase Frontend (deploy a `crm.miavance.com`):**
1. `git status` de nuevo.
2. `cd CRM-Avance-Corp/app && npm run build`.
3. Hash del artefacto **ANTES**: `md5`/`sha256` de `dist/assets/index-*.js` (anotar el nombre).
4. Desplegar estático (Hostinger MCP `hosting_deployStaticWebsite` o ruta establecida).
5. Verificar **hash servido = hash construido** (curl del `index-*.js` en prod). Registrar en el ledger de deploys del vault.
6. Commit **selectivo** (branch primero; nunca a `main` directo): migración + `MIGRACIONES.md` + FE de §3/§4 + tests. Verificar con `git hash-object`/worktree que solo entra lo de C1. Push a `avancecorp`.

**Orden de coordinación:** BD (CHECK+RPCs+**§2f**) merge → enrolar Rosa → deploy FE → prueba visual/seed de Miguel. Si el FE saliera antes que el CHECK, enrolar a Rosa fallaría en el servidor; si el CHECK sale sin el FE, Rosa entra pero `esRol` la degrada.

---

## 7) Plan de SEMILLAS (E2E de C1 sin leads reales)

1. **Crear al coordinador Rosa:**
   - Portal: `public.perfiles` para Rosa con **`rol` ∈ {`comercial`,`analista`}, `activo=true` — NUNCA `directorio`/`admin`/`superadmin`** (precondición dura: un rol lector-global le abriría `leads_select`/`clientes_basicos`/todas las métricas por `es_lector_global`, saltándose el modelo ∅). Si se crea `auth.users` por SQL, **setear las columnas `*_token` a `''`** (memoria: NULL → login 500).
   - Enrolar: `insert into crm.equipo (perfil_id, rol_crm, activo, supervisor_id) values ('<uuid Rosa>','coordinador',true,null);` (`capacidad_leads_objetivo` NULL). Requiere el CHECK ya mergeado.
2. **Sembrar la cola** (service_role, para entrar `ambos-null` sin disparar la rama gerencia del guard): varios leads con `vendedor_id=null, asignado_supervisor_id=null, activo=true, etapa='nuevo'`, `monto_estimado`/`moneda` variados (PEN y USD), `nombre_completo` con prefijo centinela **`'SEMILLA C1 …'`**, teléfonos distintos (`uq_leads_telefono_vivo`). Incluir **uno con `no_contactar=true`** (debe quedar excluido) y **uno re-encolado con tarea pendiente** (lead ambos-null + `crm.tareas` `pendiente` ligada) para ejercitar `sync_tareas`.
3. **Repartir**: login como Rosa → `Repartir leads` → asignar cada semilla a un supervisor. Verificar que sale de la cola.
4. **Verificar bandeja** (como supervisor destino / gerencia / service_role): `asignado_supervisor_id` seteado, `vendedor_id` null; actividad `reasignacion`/`entra_bandeja` con `creado_por=Rosa`; fila en `public.audit_log` con `usuario_id=Rosa`; ledger `crm.lead_asignaciones` sin episodio nuevo; **la tarea pendiente del lead re-encolado quedó `asignado_supervisor_id=sup`, `vendedor_id=null`, `estado='pendiente'`**.
5. **Verificar legal**: el lead `no_contactar=true` nunca apareció en la cola y `repartir_lead` sobre él devuelve **`P0429`** (frontend: "Lead marcado No Insista"); relectura confirma que **permaneció en la cola** (sin bandeja).
6. **Verificar aislamiento adyacente** (como Rosa, prueba manual): `.from('clientes_basicos')` → 0 filas; `.from('objetivos')` → 0 filas; `rpc('existe_cliente_por_dni')`/`rpc('metricas_agenda_fn')` → error de permiso.
7. **Limpiar** (mantener baseline `crm.leads=0`): `delete from crm.leads where nombre_completo like 'SEMILLA C1 %'` (cascada a `actividades`; borrar también las tareas centinela); conservar a Rosa enrolada para la prueba visual de Miguel. Preferir sembrar en el **branch** para el gate; en prod solo un puñado centinela, borrado tras la aprobación visual.

---

## 8) Riesgos y mitigaciones

1. **[NUEVO — BLOQUEANTE] Superficies adyacentes gateadas por `rol_crm IS NOT NULL`** → al enrolar a Rosa se abren `clientes_basicos` (PII), `existe_cliente_por_dni` (oráculo DNI), `objetivos`, `metricas_agenda`. → **§2f** las lleva a allowlist en la misma migración; §5(A) lo asevera (el gate ya no pasa verde con la puerta abierta).
2. **[NUEVO] El test legal no podía fallar** (42501 auto-aprobado) → una regresión que borre el bloqueo `no_contactar` pasaría inadvertida. → veto legal con **`P0429`** + **aserción de código exacto** + **oráculo de estado** (§2e/§5).
3. **[NUEVO] Carrera de doble-reparto sin cobertura** + UPDATE ciego. → **UPDATE CAS auto-defendido** (§2e paso 5) + **test de concurrencia en paralelo** (§5) + READ COMMITTED documentado (§1/§2e); `40001` mapeado (§4).
4. **[NUEVO] Boot del coordinador tumbado por `listarEquipo`** (RPC incondicional que puede RAISE). → el store **omite `listarEquipo` para coordinador** (§4), auto-suficiente; verificación de prod como defensa en profundidad (§6.8).
5. **[NUEVO] Contradicción del modelo de Rosa** (off-roster vs. miembro demo) → build roto / ámbito incoherente. → modelo **off-roster** fijado de punta a punta (§3): `Miembro Exclude`, sin miembro en `EQUIPO_DEMO`, `auth-demo-sincronia` extiende la aserción FUERA-del-organigrama.
6. **[NUEVO] `ACCIONES` del test sin actualizar** → `roles.test.ts:22` ROJO para todos los roles. → añadir `repartirCola`/`verCartera` a `ACCIONES` (§5).
7. **Desync vocabulario BD↔FE** (add a `ROLES` sin CHECK, o viceversa) → `no_enrolado` o `23514`. → release coordinado (§6); enrolar tras el merge del CHECK.
8. **Alguien "arregla" la visibilidad** añadiendo `coordinador` a `leads_select`/`vendedor_ids_visibles`/`es_lector_global` → fuga masiva de PII de la cola. → rama `coordinador`→∅ + comentarios "NO añadir aquí".
9. **Reusar `repartirLeads`** como cap → filtra la pantalla a supervisores. → `repartirCola` (nueva), `true` solo en coordinador+gerencia.
10. **`expectBlockedMutation` sin `allowedErrorCodes`** para `22023`/`P0002`/`P0429` → falso-negativo o falso-positivo. → declararlos por caso; el legal usa aserción de código exacto.
11. **`verCartera` solo en el nav, no en el guard** → `#/mi-cartera` alcanzable por URL. → regla simétrica en `sanearVista` + efecto de expulsión (§4).
12. **Semillas olvidadas en prod** → contaminan baseline `0 leads`. → centinela `SEMILLA C1` + limpieza; gate sobre branch.
13. **Carrera de deploy en árbol compartido** → artefacto equivocado. → `git status` + staging selectivo + hash vivo + ledger.
14. **Sin "deshacer reparto"**: devolver a cola global exige `gerencia` (`20260717212639:349-362`). → fuera de C1 (C2/rollback).
15. **[Compliance, baja] Intentos rechazados de repartir un No Insista no dejan rastro** (RAISE → rollback total). → **deuda de compliance documentada** (§9); si INDECOPI exige patrón de reincidencia, registrar fuera de la tx (edge/app o tabla append-only vía `pg_background`).

---

## 9) Dependencias con C2 (qué queda preparado, no construido)

- **Sustrato reutilizable por C2**: el rol `coordinador` + CHECK + visibilidad ∅ + el **patrón de RPC SECURITY DEFINER gated** (gate `crm.equipo`⋈`perfiles`, `search_path=''`, `revoke public/anon`+`grant authenticated`) + **el patrón de allowlist de §2f** son exactamente lo que C2 clona.
- **Columnas que C2 necesita y C1 NO añade**: `descartado_en`, `reactivado_en`, `reactivado_por` (AUSENTES hoy). C1 no las toca.
- **`supervisores_para_reparto` (carga/cupos)**: base del tablero de distribución de C2.
- **Costura del guard**: "solo gerencia devuelve a la cola global" queda intacta; punto que C2 extiende si los fríos vuelven a un pool compartido.
- **Pantalla + hooks de reparto**: `screens/repartir.tsx` + funciones de `crm-api` son la plantilla de la pantalla de distribución de fríos de C2.
- **Métrica "tiempo en bandeja"**: no hay episodio de ledger para el parqueo (por diseño); si C2 la necesita, derivarla de `crm.actividades` (`entra_bandeja`)/`actualizado_en`, no del ledger.
- **[NUEVO — continuidad legal aguas abajo]** C1 re-valida `no_contactar` al parquear a bandeja, pero el guard `trg_leads_guard_tenencia` **NO** re-valida `no_contactar` al setear `vendedor_id` (`20260717212639:303-347`). Ventana: lead repartido con `no_contactar=false` → se marca `true` mientras espera en bandeja → el supervisor lo baja a un vendedor sin freno. **Dependencia de C2/handoff**: la RPC/flow bandeja→vendedor DEBE re-validar `no_contactar=false` en su misma tx. **Fix robusto recomendado** (cierra TODAS las rutas de una vez): añadir la comprobación de `no_contactar` dentro del propio guard cuando se setea `vendedor_id` (evaluar en C2 para no ampliar el alcance de C1).
- **[NUEVO — compliance]** Trazabilidad de intentos rechazados a un No Insista: hoy solo se traza el reparto EXITOSO. Si se requiere evidencia de reincidencia ante INDECOPI, C2 puede añadir un log append-only fuera de la tx que revierte.

---

## Anexo — issues resueltas por la verificación adversarial

- LENTE RLS · BLOQUEANTE (clientes_basicos_fn): VERIFICADO en 20260711000003:28 el gate `rol_crm IS NOT NULL OR es_lector_global`. RESUELTO en §2f.1: CREATE OR REPLACE del fn con gate a allowlist `IN ('vendedor','supervisor','gerencia')` (+coalesce por 3VL), en la MISMA migración de C1; ACL preservada; regresión cero para roles operativos/lector/service_role. §5(A) asevera coordinador→0 filas.
- LENTE RLS · ALTA (existe_cliente_por_dni oráculo DNI): VERIFICADO cimientos:525 (RAISE sin errcode→P0001). RESUELTO en §2f.2: gate a allowlist + errcode ESTABLE 42501; §5(A) asevera coordinador bloqueado.
- LENTE RLS · MEDIA (objetivos_select): VERIFICADO 20260719120000:70. RESUELTO en §2f.3 vía ALTER POLICY a allowlist (one-liner, sin tocar la RPC de escritura ni grants). Nota: RLS filtra (no lanza) → no rompe el boot (listarObjetivos ya va en .catch). §5(A) asevera coordinador→0 filas.
- LENTE RLS · MEDIA (metricas_agenda_fn gate abierto a cualquier miembro activo): VERIFICADO 20260719013000:60-71. RESUELTO en §2f.4: CREATE OR REPLACE copiando el cuerpo verbatim y cambiando SOLO el gate a `... and e.rol_crm in ('vendedor','supervisor','gerencia')` (excluir coordinador SIN romper vendedor/supervisor — el fix del reviewer 'alinear a gerencia/lector' se descartó por over-restrictivo). §5(A) asevera bloqueado.
- LENTE RLS · BAJA (leads_insert no niega por policy al coordinador; recae en el guard): VERIFICADO cimientos:429-435. RESUELTO como aserción de gate en §5(A): coordinador insert (vendedor=self) y (ambos-null) → ambos bloqueados, para detectar regresiones del guard. Documentado en §2c.
- LENTE RLS · BAJA (aislamiento depende del rol de PORTAL no-lector-global): VERIFICADO cimientos:124-135. RESUELTO como precondición dura en §5 (fixture portalRole∈{comercial,analista}) y §7 paso 1; se asevera que el coordinador NO es lector global.
- LENTE ATOMICIDAD · MEDIA (sin test de concurrencia): RESUELTO en §5(C) con test de 2 sesiones en PARALELO (Promise.allSettled coordinador+gerencia sobre el mismo lead) asegurando exactamente-uno-gana + relectura service_role; el perdedor recibe P0002 (o 40001).
- LENTE ATOMICIDAD · MEDIA (UPDATE ciego): RESUELTO en §2e paso 5: el UPDATE ahora repite el predicado de tenencia (CAS) + `if not found raise P0002` → la mutación se auto-defiende aunque se debilite el FOR UPDATE; se conserva el SELECT..FOR UPDATE para inspeccionar no_contactar. Documentado en comentario.
- LENTE ATOMICIDAD · BAJA (dependencia READ COMMITTED no declarada): RESUELTO: documentado en §1 (nota de aislamiento), en el comentario de la función §2e y en §8; 40001 mapeado en aErrorApi (§4).
- LENTE ATOMICIDAD · BAJA (carrera desactivación-supervisor → P0001 no mapeado): VERIFICADO que aErrorApi crm-api.ts:484 YA mapea P0001→REGLA_SERVIDOR surfaceando error.message ('La bandeja destino no pertenece a un supervisor activo'). RESUELTO sin cambio de código; documentado en la tabla SQLSTATE (§2) y §4 como ya-cubierto.
- LENTE LEGAL · ALTA (el test legal no podía fallar porque el bloqueo usaba 42501 y expectBlockedMutation lo auto-aprueba): VERIFICADO test-rls.mjs:174 (isAuthorizationError) y :272. RESUELTO en §2e paso 4 con SQLSTATE PROPIO 'P0429' (fuera de {42501,42503}, mensaje sin match del regex de auth, sin prefijos PT/PGRST) + §5(C) usa aserción de código EXACTO (no expectBlockedMutation) que además detecta un cambio de vuelta a 42501; aErrorApi mapea P0429→NO_INSISTA (§4).
- LENTE LEGAL · MEDIA (falta oráculo de estado en el caso negativo): RESUELTO en §5(C): tras el bloqueo legal, relectura service_role asevera asignado_supervisor_id/vendedor_id null (permaneció en cola) + re-query de leads_por_repartir asevera que nunca aparece.
- LENTE LEGAL · BAJA (intentos rechazados no dejan rastro por rollback): DIFERIDO con justificación en §8(15) y §9 como deuda de compliance (no bloqueante para C1; requeriría log fuera de la tx que revierte).
- LENTE LEGAL · BAJA (handoff bandeja→vendedor no re-valida no_contactar): VERIFICADO 20260717212639:303-347. DIFERIDO a C2 y documentado en §9 como dependencia explícita, con fix robusto recomendado (añadir la comprobación al propio guard).
- LENTE COMPLETITUD · ALTA (contradicción modelo de Rosa off-roster vs miembro demo vs it.each): VERIFICADO tipos.ts:230, auth-demo.ts:14, auth-demo-sincronia.test.ts:11/23-26. RESUELTO fijando el modelo OFF-ROSTER (como directorio) de punta a punta en §3: Miembro.rol_crm=Exclude<Rol,'directorio'|'coordinador'>; NO añadir miembro a EQUIPO_DEMO (corrige el plan base); DEMO_YO con id sintético 'demo-coordinador'; auth-demo-sincronia NO toca it.each y extiende la aserción FUERA-del-organigrama (§5).
- LENTE COMPLETITUD · ALTA (array ACCIONES de roles.test.ts no actualizado): VERIFICADO roles.test.ts:4-14 y :22. RESUELTO en §5: añadir 'repartirCola' y 'verCartera' a ACCIONES además del toEqual de ROLES (:20), con orden coherente (coordinador al final de CAPS).
- LENTE COMPLETITUD · ALTA (store llama listarEquipo incondicional → boot de Rosa cae si equipo_visible_fn RAISE): VERIFICADO store.tsx:428-434/524-533 y crm-api.ts:362-375. RESUELTO en §4: cargarReal omite listarEquipo para coordinador (Promise.resolve([])), auto-suficiente sin depender del comportamiento prod-only; la verificación de prod queda como defensa en profundidad (§6.8, ya no bloqueante).
- LENTE COMPLETITUD · MEDIA (RolCrmDb/ROLES_EQUIPO type-lie y descarte silencioso): VERIFICADO database.types.ts:14, crm-api.ts:353-375. RESUELTO como decisión explícita coherente con off-roster (§3): NO tocar ninguno; documentar el descarte silencioso como intencional (comentario en crm-api.ts:353) y el type-lie de RolCrmDb como conocido/aceptado.
- LENTE COMPLETITUD · BAJA (verCartera solo en nav, no en guard → #/mi-cartera por URL): VERIFICADO App.tsx:121-127/212-217. RESUELTO en §4 añadiendo la regla simétrica `vista==='mi-cartera' && !can(rol,'verCartera') → base` en sanearVista y en el efecto de expulsión; además se corrigió la firma REAL de sanearVista (booleans, no rol) que el plan base describía mal.
- LENTE TRIGGERS · BAJA (etiqueta 'tareas: no-op' imprecisa + camino sync_tareas re-encolado sin cubrir): VERIFICADO 20260718180001:157-159/205-210/224-225. RESUELTO en §1 con el inventario COMPLETO de los 9 triggers del UPDATE (incl. trg_leads_zz_sync_tareas re-apuntando pendientes) y en §5/§7 con un caso de gate + semilla de lead re-encolado con tarea pendiente que verifica que la tarea sigue al lead a la bandeja sin bloqueo.

### Riesgos residuales

- `equipo_visible_fn` es prod-only: no pude leer su definición esta sesión. El plan lo NEUTRALIZA en el frontend (el store omite listarEquipo para coordinador), así que su comportamiento ya no afecta el boot; queda solo como verificación informativa en el runbook (§6.8). Si esa función devolviera filas de coordinador a OTROS llamadores, el picklist las descarta (documentado), sin fuga.
- El candado legal P0429 (§5C) detecta la eliminación del check no_contactar (la mutación tendría éxito → oráculo de estado falla) y un cambio de código a cualquier valor != P0429; el oráculo de estado cubre además el caso de un cambio a 42501. Persiste una vía teórica: si alguien cambiara SIMULTÁNEAMENTE el código a 42501 Y el oráculo de estado se borrara del test — mitigado porque son dos ediciones separadas y ambas visibles en revisión.
- El HTTP status con que PostgREST envuelve el SQLSTATE custom P0429 no se validó en vivo (depende de la versión de PostgREST/Supabase). No es load-bearing: tanto el gate (supabase-js lee error.code del body) como el frontend (aErrorApi mapea por code) son status-agnósticos. Conviene confirmarlo en el smoke de §7 paso 5.
- §2f.4 reescribe metricas_agenda_fn como CREATE OR REPLACE copiando ~187 líneas verbatim con un único cambio de gate: riesgo de transcripción al implementar. Mitigado dando la instrucción quirúrgica (copiar de 20260719013000, cambiar SOLO el bloque :60-65) en vez de duplicar el cuerpo en el plan; el gate de §5(A) detecta si el fn quedó roto (coordinador debe salir bloqueado y los demás roles seguir funcionando).
- El test de concurrencia (§5C) usa Promise.allSettled de dos sesiones reales; bajo un scheduler muy determinista podría, en teoría, serializarse de facto y no ejercitar el lock. Mitigado con el oráculo SQL opcional test-reparto.sql (dos sesiones/dblink) como respaldo y porque el UPDATE CAS garantiza la corrección aun sin colisión temporal.
- El fix del handoff legal bandeja→vendedor (no_contactar) queda DIFERIDO a C2: entre el reparto a bandeja y la bajada a vendedor existe una ventana en la que un lead marcado No Insista podría llegar a un vendedor si C2 no re-valida. Documentado como dependencia dura en §9; C1 no lo cierra por alcance.
- La validación real de C1 sigue pendiente de leads reales (crm.leads=0): todo el E2E corre con semillas centinela. Riesgo residual bajo, asumido por Decisión #2 de Miguel.

### Confianza

alta — cada issue bloqueante/alta se verificó contra el archivo:línea citado (clientes_basicos_fn, existe_cliente_por_dni, objetivos_select, metricas_agenda_fn, isAuthorizationError/expectBlockedMutation, store.cargarReal, la firma real de App.sanearVista, roles.ts/roles.test.ts y el patrón off-roster de directorio), y las correcciones son cambios acotados y regresión-cero; el único elemento no verificable (equipo_visible_fn prod-only) quedó neutralizado por diseño

### Veredictos por lente

- **RLS y fuga de privilegios del rol `coordinador` (¿ve/toca leads o PII que no debe? ¿la RPC filtra bien?)** → `no-go` (6 issues)
- **Atomicidad y carrera en repartir_lead (dos coordinadores reparten el mismo lead; FOR UPDATE; doble-asignación)** → `revisar` (4 issues)
- **Legal/consentimiento (no_contactar re-validado server-side en la MISMA tx) y trazabilidad del reparto (ledger/actividad)** → `revisar` (4 issues)
- **Completitud de la propagación del rol `coordinador` (BD + frontend + tipos generados + tests): puntos omitidos que rompen build o abren huecos** → `revisar` (5 issues)
- **Efectos colaterales de triggers en el UPDATE de C1: que no se bloquee ni deje estado inconsistente (tareas/SLA/ledger/bloquear_reasignacion)** → `go` (1 issues)

## Relacionadas
[[Distribución de leads y base fría (plan revisado)]] · [[Acceso y roles del CRM]] · [[CRM conexión a datos reales]]
