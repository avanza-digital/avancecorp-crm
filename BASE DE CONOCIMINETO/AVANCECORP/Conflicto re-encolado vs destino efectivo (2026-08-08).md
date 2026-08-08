---
tags: [crm, bug-potencial, triggers, reparto, sla]
actualizado: 2026-08-08
estado: pendiente-decision
---

# Conflicto re-encolado vs destino efectivo (2026-08-08)

Relacionado con [[Plan de escalabilidad del CRM a data gigante]] y la
configuración operativa versionada (metas/SLA, aplicada a prod 2026-08-08).

## Qué pasa

Dos reglas correctas por separado chocan combinadas — **hoy en producción**:

1. `trg_leads_zz_sync_tareas` (existente): cuando cambia la tenencia de un
   lead, sus tareas **pendientes** espejan al nuevo dueño.
2. `trg_tareas_01_destino_efectivo_*` (nuevo, metas/SLA versionados): una tarea
   pendiente y activa **no puede quedar sin destino** (23514), para nadie —
   ni service_role.

Consecuencia: **devolver a la cola global un lead con tareas pendientes es
imposible** — el sync espeja destino nulo a la tarea y el trigger de destino
aborta TODO el update del lead con `23514 · La tarea pendiente requiere un
destino CRM efectivo`. El re-encolado de gerencia/coordinador falla en ese caso.

## Estado del gate

El gate `test-rls.mjs` tenía un escenario que sembraba ese estado
(«la tarea pendiente sigue al lead re-encolado»). Quedó **inalcanzable por
diseño**; el 2026-08-08 (ciclo F0 de escalabilidad) se reescribió para
**clavar el comportamiento actual**: re-encolar con tarea pendiente → 23514,
bloqueo atómico, la tarea queda intacta en su bandeja. Si un ciclo futuro
cambia este comportamiento, esa sonda pasará a rojo y obligará a re-diseñar
el escenario (consciente, no silencioso).

## Decisión pendiente (de Miguel / del ciclo de configuración operativa)

- **Opción A — es un feature:** re-encolar exige antes cancelar o reasignar
  las tareas pendientes. Habría que hacerlo visible en la UI (hoy el error
  llegaría crudo) y documentarlo como regla comercial.
- **Opción B — es un bug:** el re-encolado debe cancelar (o mover a la bandeja
  del supervisor saliente) las tareas pendientes automáticamente, como ya hace
  el sync con convertido/descartado (`estado='cancelada'` vía
  `crm.cancela_sistema`). Migración pequeña en el sync.

Ninguna de las dos la resuelve F0: se anota aquí para el ciclo dueño de la
regla de destino efectivo.

## Anexo — otros dos impactos del mismo día (descubiertos por el gate F0)

1. **Regresión P04 en la banca (CORREGIDA en F0):** el catálogo de productos
   reescribió `private.puede_gestionar_cuentas_cliente` y perdió la línea
   `and private.puede_acceder_crm()` de P04 — un analista/admin del portal con
   membresía CRM **revocada** recuperaba listar/crear/corregir cuentas
   bancarias. Restaurada en la migración `20260808173537`.
2. **Pagos exige ahora operador con membresía CRM viva (DELIBERADO, revisar
   operación):** desde la redefinición de `es_lector_global`/«rol CRM efectivo»
   («Admin/Superadmin Portal no heredan lectura operativa»), un admin del
   portal SIN membresía CRM ya no puede resolver cuentas para la página de
   Pagos (`cuentas_pago_contratos_fn` → 42501). Si quien opera Pagos en
   producción es un admin de portal puro, esa página dejó de funcionarle el
   2026-08-08. Verificar QUIÉN opera Pagos y, si hace falta, darle membresía
   CRM (gerencia) o revisar la decisión con el ciclo de configuración
   operativa.
