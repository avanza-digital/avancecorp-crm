---
estado: 🔀 GIRO 2026-07-21 — Miguel decidió que TODO el reparto va DENTRO del CRM (no la hoja). Fase A (vía-hoja) DESCARTADA y revertida. Plan vigente = Fase C build-ready (ver sección al final).
checkpoint: DL-01
fecha: 2026-07-21
---

# Distribución de leads y base fría (plan revisado)

> ## ▶ RETOMA AQUÍ — Checkpoint **DL-01** (actualizado 2026-07-21, noche)
> **Estado:** el reparto va **DENTRO del CRM** (vía-hoja/Fase A DESCARTADA y revertida
> sin commitear; hoja = puro intake, edge en v5, **árbol de código 100% limpio**).
> Decisiones fijadas: rol de Rosa = **`coordinador` acotado** · **construir C1 YA con
> semillas** (crm.leads=0).
>
> **Lo hecho hoy:** el **plan de C1 quedó BUILD-READY y verificado** por un workflow de
> 15 agentes / 5 lentes adversariales → nota dedicada **[[Fase C1 — Reparto de la cola
> (plan build-ready)]]** (SQL de las 2 RPCs, ALTER del rol, propagación completa BD+FE,
> frontend, gate, runbook, semillas). La lente RLS dio **no-go** por un bloqueante
> (enrolar al coordinador abre 4 superficies gateadas por `rol_crm IS NOT NULL`, incl.
> la PII de `clientes_basicos`) → **corregido en la misma migración**. **NADA construido aún.**
>
> **PRÓXIMO PASO (mañana) → CONSTRUIR C1** siguiendo esa nota, en este orden: (1) migración
> `20260721120000_crm_reparto_coordinador_c1.sql` (CHECK rol + `vendedor_ids_visibles` +
> 3 RPCs + **§2f endurecimiento de superficies adyacentes**) por branch→gate→advisors→merge;
> (2) propagación del rol + pantalla `Repartir leads` en el frontend; (3) tests/gate;
> (4) semillas + prueba E2E. Miguel aún NO dio el go final a construir — confirmarlo al retomar.
>
> **Frase para retomar:** _"retomemos DL-01"_ / _"construyamos C1"_.

---

## Qué es esto

Lógica de **derivación de leads + base fría** para el CRM. Nació de una conversación
de diseño con Miguel y se sometió a una **evaluación adversarial multi-agente**
(11 agentes: 4 leyeron el código real, 4 atacaron el plan, 2 diseñaron alternativas,
1 sintetizó). Veredicto: **REVISAR** — el modelo de negocio es correcto, las Fases A
y B son sólidas, pero la Fase C original (sync bidireccional hoja↔CRM) era el
mecanismo equivocado y escondía un **defecto legal crítico**. Se corrigió.

## Las 5 reglas de gobierno (validadas contra el código, se mantienen)

1. **Un lead = un dueño a la vez.** Reasignar lo mueve de mano; nunca crea copias.
   (Ya blindado en BD: CHECK `leads_tenencia_exclusiva` + trigger guard.)
2. **Solo lo DESCARTADO es repartible por la empresa.** Lo que el vendedor trabaja
   (en agenda) es intocable — Rosa ni lo ve.
3. **Reposo antes de enfriar** (número a confirmar, ver decisiones): un descartado
   solo entra a la base fría de EMPRESA tras N días sin movimiento. Antes, solo del
   vendedor dueño.
4. **"Reactivado" es una MARCA/columna, NO una etapa.** El lead sigue su pipeline
   normal. (Meterlo como etapa habría roto el CHECK de 6 valores + índices únicos +
   métricas.)
5. **Trazabilidad total.** Carlos ve quién descartó, quién reactivó, cuándo.

## El plan APROBADO — "La hoja para lo que NACE, el CRM para lo que se MUEVE"

### FASE A 🟢 (chica, ~1-2 días) — Rosa reparte leads NUEVOS a supervisores DESDE LA HOJA
- **Hoja de captura:** nueva columna "Supervisor asignado" con desplegable cerrado de
  **solo supervisores**, alimentado del CRM. **AJUSTE:** refrescar el desplegable en
  CADA importación (no una sola vez en `configurar()`), para que un supervisor
  nuevo/inactivo no ensucie la asignación.
- **Conector edge `crm-importar-leads`:** resuelve el supervisor → su **bandeja**
  (`asignado_supervisor_id`), reutilizando el resolver correo→perfiles→equipo que ya
  existe. Precedencia: supervisor > vendedor directo > cola global.
- **Es UNIDIRECCIONAL (append-only)** → aquí la hoja SÍ encaja, bajo riesgo. Respeta
  el deseo de Miguel de que Rosa trabaje en hojas.
- **BD:** ninguno (la bandeja de supervisor ya existe).

### FASE B 🟡→🟢 (chica, ~2-3 días) — Base fría PERSONAL del vendedor, DENTRO del CRM
- **CRM front:** sección "Leads gestionados" con SUS descartados (`vendedor_id=yo AND
  etapa='descartado'`) + fecha + motivo + botón **Reabrir** (reutiliza `reabrir()` del
  store con su `conflictoDedup`). Reabrir aquí = SUYO, NO cuenta como "reactivado".
- **2 ajustes que la salvan de ser inútil:**
  1. **Reposo 7-14 días** (no 3): la gente entra ~1x/semana; con 3 días perdería sus
     propios descartes antes de volver.
  2. **No nacer como pantalla aislada:** superficiar "tienes N descartes por reabrir,
     se liberan el DD/MM" en el **héroe de la agenda** Y en el **correo semanal** (el
     canal que de verdad decide la adopción).
- **BD:** añadir aquí la columna `descartado_en` (que la C también necesita).

### FASE C 🔴→🟡 (mediana, ~4-6 días) — Base fría de EMPRESA + reparto DENTRO del CRM
**CAMBIO CLAVE vs el plan original: el reparto NO se hace de ida-y-vuelta con la hoja,
sino desde UNA pantalla del CRM.** Diferir hasta tener 2-4 semanas de leads reales.

- **BD (por branch→gate RLS→advisors→merge):**
  1. `descartado_en` (set por trigger al entrar a 'descartado', NULL al reabrir) →
     corte de "frío" O(1), determinista y **NO gameable por notas**.
     `reactivado_en` / `reactivado_por` (columnas aditivas).
  2. RPC `crm.base_fria_empresa()` SECURITY DEFINER: lista descartados fríos filtrando
     por la **COLUMNA `no_contactar=false`** (flag legal duro) + `activo=true` +
     motivos permitidos; gateado a coordinador/gerencia.
  3. RPC `crm.reactivar_lead(lead, supervisor)` SECURITY DEFINER, **ATÓMICO**:
     `SELECT ... FOR UPDATE`, re-valida en la MISMA transacción que sigue descartado +
     frío + `no_contactar=false` + activo + supervisor activo; **UN SOLO UPDATE** que
     mueve vendedor→bandeja (`vendedor_id=NULL`, `asignado_supervisor_id=sup` a la vez),
     `etapa='nuevo'`, marca reactivado; maneja el choque del índice único parcial
     (teléfono/DNI) devolviendo mensaje humano; EXECUTE revocado a authenticated/anon.
  4. Rol **`coordinador`** de mínimo privilegio para Rosa (`vendedor_ids_visibles=∅` →
     no ve NINGÚN lead salvo por los 2 RPCs) — o atajo Rosa=gerencia solo para pilotar.
- **Front:** pantalla "Base fría (empresa)" (reutiliza el shape del componente Bandeja)
  + badge "Reactivado" + carga/cupos por supervisor + "disponible desde" + motivo legible.
- **Notificación:** incluir reactivados y nuevos-en-bandeja en el **correo semanal**
  ("N leads sin trabajar, capital en juego X") — el CRM NO tiene notificaciones y sin
  empujón el reactivado muere olvidado.
- **Edge y Apps Script: CERO cambios nuevos en la C** (desaparecen los 2 flujos y la
  pestaña "Base de datos").

## Por qué cambió la Fase C (lo que la evaluación destapó)

- **🔴 LEGAL (linchpin):** el plan original decía "excluir *No contactar*" tratándolo
  como un **motivo de descarte**, pero ese valor NO existe (el enum es
  sin_interes/sin_fondos/competencia/no_responde/datos_invalidos/otro). "No contactar"
  es una **columna booleana aparte** (`crm.leads.no_contactar`). Filtrar por motivo
  sería un **NO-OP** → se re-contacta a quien pidió no serlo → **Ley 29571 "No Insista",
  INDECOPI, hasta 450 UIT**. Además la hoja es copia stale: el vendedor puede prender
  el flag DESPUÉS de exportar y ANTES de repartir. **Fix: filtrar la columna
  `no_contactar=false`, server-side, RE-VALIDADO atómicamente en el instante del reparto.**
- **Fragilidad del sync:** la hoja pasaría a ser la "llave" que cambia el dueño de un
  lead. Ancla por teléfono editable, escritura por fila absoluta (se desalinea al
  reordenar/borrar), `onEdit` re-dispara una fila ya repartida, foto stale de 5 min,
  UPDATE no idempotente.
- **Minimización de datos:** exportar DNI + teléfono + capital + nombre a un Google
  Sheet sin RLS = sobre-recolección (Ley 29733) + almacén sombra fuera del CRM +
  lectura GLOBAL vía service_role que salta la RLS jerárquica.
- **Trazabilidad:** el ledger de episodios NO registra un episodio cuando el destino es
  una bandeja (`vendedor_id null`); "reactivado" en el ledger YA significa otra cosa
  (activo false→true). Por eso la marca de EMPRESA vive en `reactivado_en/por` +
  una actividad propia, NO en el ledger.

## Decisiones

**Resueltas (2026-07-21):**
- ✅ **La grande:** Rosa reparte los fríos **DENTRO del CRM**, no en la hoja. La hoja se
  queda para el intake de NUEVOS (Fase A).
- ✅ Orden: **A → B → C**. C diferida hasta tener leads reales.
- ✅ Desplegable de supervisores: automático desde el CRM (con refresco en cada corrida).

**Pendientes de confirmar (no bloquean Fase A; se cierran al llegar a B/C):**
- ⏳ **Reposo exacto:** ¿7, 10 o 14 días? (recomendado 7-14). Default de trabajo: **10**.
- ⏳ **Repartibles:** excluir siempre `no_contactar`, `datos_invalidos` y `sin_interes`;
  repartibles = `sin_fondos`, `competencia`, `no_responde`. ¿`sin_interes` entra solo
  si hay motivo nuevo documentado?
- ⏳ **Rol de Rosa:** rol `coordinador` acotado (recomendado, deja su nombre) vs atajo
  Rosa=gerencia (solo piloto).
- ⏳ Autorizar el correo semanal como vehículo de descubrimiento/notificación de B y C.

## Referencia técnica

- Evaluación completa (síntesis + 4 críticas + 2 alternativas + grounding con
  evidencia archivo:línea): output del workflow `wf_1d6873c8-ec1`
  (`.../tasks/w7wocw9gf.output`) — 35 hallazgos, veredicto "revisar".
- Anclas de código citadas: `cimientos_crm.sql` (enum etapa 165-166, RLS 76-110,
  índices únicos 190-193), `ledger.sql` (guard tenencia 303-305, poblador episodios
  597-599/717-723), `20260718180001` (columna `no_contactar` 402-406),
  `motor-siguiente.ts:12` (kill-switch legal), `store.tsx` (reabrir 1127-1144,
  conflictoDedup 311-347).

## ▶ Plan de Fase C — Reparto DENTRO del CRM (build-ready, 2026-07-21)

> **C1 tiene su propia nota build-ready detallada** (SQL de las 2 RPCs, ALTER del rol,
> propagación completa, frontend, gate, runbook, semillas), verificada por un workflow
> de 15 agentes / 5 lentes adversariales: **[[Fase C1 — Reparto de la cola (plan build-ready)]]**.
> La lente RLS dio **no-go** por un bloqueante que el diseño base no vio (enrolar al
> coordinador abre 4 superficies gateadas por `rol_crm IS NOT NULL` — incl. la PII de
> `clientes_basicos`) → corregido en la misma migración. Lo de abajo es el resumen.

Reemplaza a Fase A y absorbe el reparto de fríos. **Cero hoja, cero Apps Script,
cero cambios en el edge** (el edge ya deja los leads sin dueño en la cola global).
Todo el trabajo es **BD + frontend del CRM**. Aterrizado contra prod esta sesión.

### Se parte en dos sub-fases
- **C1 — Reparto de la COLA (leads nuevos sin dueño).** Reemplazo directo de la
  vía-hoja. **Construible YA** (no depende de columnas nuevas ni de leads fríos).
  Hoy esos leads (importados sin `vendedor_correo`) caen a cola global y **solo
  gerencia los ve** → C1 es lo que le da a Rosa el poder de repartirlos sin ser gerencia.
- **C2 — BASE FRÍA (descartados que reposaron).** Diferida: necesita columnas nuevas
  + Fase B (base fría personal) + 2-4 semanas de leads reales para calibrar reposo.

### Rol de Rosa (decidir)
- **Opción A (recomendada):** rol nuevo **`coordinador`** de mínimo privilegio.
  Requiere `ALTER` del CHECK `equipo_rol_crm_check` (hoy solo `vendedor|supervisor|
  gerencia`). No es lector global; ve/reparte **solo por los RPCs** `SECURITY DEFINER`.
  El CHECK `equipo_capacidad_leads_solo_analista` ya excluye capacidad para no-analistas → OK.
- **Opción B (atajo piloto):** Rosa = gerencia temporal. Rápido pero visibilidad total.

### BD — C1 (branch → gate RLS → advisors → merge)
1. **Rol `coordinador`**: `ALTER` del CHECK de rol. Rama **explícita** en
   `private.vendedor_ids_visibles` para `coordinador` → `return` (∅). *(Hoy caería al
   `else`=sí mismo, que da ∅ para Rosa porque no posee leads; se hace explícito para
   que un cambio futuro no le abra visibilidad por accidente.)*
2. **RPC `crm.leads_por_repartir()`** `SECURITY DEFINER`: lista la cola
   (`vendedor_id IS NULL AND asignado_supervisor_id IS NULL AND activo AND etapa NOT IN
   ('convertido','descartado')`) con nombre/capital/moneda/origen/creado_en; gate a
   `coordinador|gerencia`; `EXECUTE` revocado a anon/authenticated, grant explícito.
3. **RPC `crm.repartir_lead(p_lead uuid, p_supervisor uuid)`** `SECURITY DEFINER`
   **ATÓMICO**: `SELECT ... FOR UPDATE`; re-valida en la MISMA tx que el lead sigue en
   cola + supervisor activo (`rol_crm='supervisor'`) + `no_contactar=false`; **UN solo
   UPDATE** que setea `asignado_supervisor_id` (deja `vendedor_id` null → respeta
   `leads_tenencia_exclusiva` y el guard `trg_leads_guard_tenencia`). Registra actividad.
   Maneja la carrera de dos coordinadores con `FOR UPDATE`. `EXECUTE` revocado a
   authenticated/anon.

### BD — C2 (diferida; añade sobre C1)
4. Columnas **`descartado_en`** (set por trigger al entrar a `descartado`, NULL al
   reabrir → corte de "frío" O(1), no gameable por notas), **`reactivado_en`**,
   **`reactivado_por`** (aditivas). *(NINGUNA existe hoy.)*
5. **RPC `crm.base_fria_empresa()`**: descartados fríos (`descartado_en < now()-N días`)
   filtrando la **COLUMNA `no_contactar=false`** (flag legal duro) + `activo` + motivos
   repartibles; gate `coordinador|gerencia`.
6. **RPC `crm.reactivar_lead(p_lead, p_supervisor)`** `SECURITY DEFINER` **ATÓMICO**:
   `FOR UPDATE`; revalida sigue descartado + frío + `no_contactar=false` + activo +
   supervisor activo; **UN UPDATE** que mueve a bandeja (`asignado_supervisor_id=sup`,
   `vendedor_id=null`), `etapa='nuevo'`, `ciclo_actual+1`, marca reactivado; maneja el
   choque del índice único parcial (teléfono/DNI) con mensaje humano.

### Frontend (CRM) — pantalla "Repartir leads" (coordinador|gerencia)
- Tab **"Por repartir"** (cola global) → C1. Tab **"Base fría"** (reactivables) → C2.
- Reusa el shape del componente **Bandeja**; capital PEN/USD **separados** (nunca sumados);
  carga/cupos por supervisor; badge "Reactivado" en C2; entradas de menú solo a coord./gerencia.

### Notificación
- Correo semanal: "N leads sin repartir / reactivados, capital en juego X" (el CRM no
  tiene push; sin empujón el lead sin repartir muere olvidado).

### Orden recomendado
**C1 primero** (desbloquea a Rosa en el CRM apenas entren leads) → **C2 después** (con
Fase B + leads reales). Nota: `crm.leads=0` hoy → C1 se **construye y prueba con leads
semilla**, pero la validación "con datos reales" espera a que entren leads.

### Decisiones abiertas para Miguel
- Rol de Rosa: `coordinador` acotado (recomendado) vs Rosa=gerencia piloto.
- ¿Construir **C1 ya** (con semillas) o esperar leads reales?
- (C2, no bloquean C1) Reposo 7/10/14 días (default 10) · motivos repartibles
  (`sin_fondos|competencia|no_responde` sí; `no_contactar|datos_invalidos|sin_interes` no) ·
  autorizar el correo semanal.

## Relacionadas
[[Carga de leads desde hoja de Google]] · [[Distribución de leads por capital y trazabilidad CRM]] · [[Acceso y roles del CRM]] · [[CRM conexión a datos reales]] · [[Agenda comercial del CRM (plan v2)]]
