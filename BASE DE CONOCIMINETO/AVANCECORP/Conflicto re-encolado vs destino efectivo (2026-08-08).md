---
tags: [crm, bug-potencial, triggers, reparto, sla]
actualizado: 2026-08-09
estado: resuelto
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

## Decisión: opción B (Miguel, 2026-08-09) — es un bug

Re-encolar cancela las tareas pendientes automáticamente, con el mismo
mecanismo que el sync ya usa en convertido/descartado (`estado='cancelada'` vía
`crm.cancela_sistema`, sellada `cancelada_por='sistema'` sin actor humano). Se
descartó la opción A: obligar a cancelar a mano antes de devolver un lead no es
una regla comercial que nadie defienda, es el error crudo disfrazado de norma.

**Y una segunda mitad que no estaba en ninguna de las dos opciones.** La
auditoría encontró que cancelar sin más devolvía el lead a la cola con
`etapa='reunion_agendada'` y cero reuniones vivas. Eso es exactamente lo que la
doctrina de [[Anular reunión y retroceso de etapa]] llama el hecho falso más
caro: el coordinador repartiría un lead que AFIRMA tener cita, el nuevo dueño
heredaría el dato falso, el SLA usaría la ventana equivocada y el embudo lo
contaría como reunión viva. Así que la etapa retrocede con la MISMA regla que
ya usa anular una reunión — `contactado` si hubo contacto en el ciclo, `nuevo`
si no — y **no** retrocede si la reunión ya se realizó, porque ahí la etapa se
sostiene en un hecho verdadero.

No se pudo reutilizar la función de retroceso que ya existía: solo la llaman
las RPC humanas (cerrar tarea / cerrar reunión), así que una cancelación por
trigger se la salta, y además exige que el lead tenga dueño — que es justo lo
que deja de tener al re-encolarse.

Migración `20260809024942_crm_reencolar_cancela_tareas.sql`.

## Lo que enseñó este ciclo

**Un fixture puede dar verde sin probar nada.** La sonda del gate usaba una
tarea suelta sobre un lead en etapa `nuevo`: el retroceso no se ejercitaba
NUNCA. Con esa semilla el gate habría certificado media corrección. Ahora son
cuatro semillas —`nuevo`, `contactado`, la abstención por reunión ya realizada
y la no-regresión de la reasignación— y cada una asevera su **estado previo**
antes de actuar, para que ninguna pueda volver a pasar por la razón equivocada.

**Construir el estado por el camino real destapa las reglas.** Al sembrar las
citas con fecha pasada, la etapa no subía: el trigger de ascenso exige
`vence_en > now()` («agendar en el pasado no es agendar») y contacto previo
registrado. Forzar la etapa a mano lo habría ocultado.

**Un hallazgo bloqueante de la auditoría era falso, y verificarlo importó.**
Se afirmó que cancelar una reunión violaría su CHECK de cierre por dejar el
motivo en NULL, y que eso era además un bug latente en producción. No: en SQL
`NULL = ANY(...)` da NULL, y un CHECK **solo rechaza cuando evalúa a FALSE**.
Comprobado en el branch y aritméticamente. Haberlo aceptado habría metido un
cambio de semántica en tres rutas de cancelación que hoy funcionan.

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
