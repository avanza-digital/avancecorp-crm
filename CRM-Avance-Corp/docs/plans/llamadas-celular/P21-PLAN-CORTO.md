# Propuesta #21 — Registrar varias pendientes del mismo lead de una vez: plan corto (13/10/2026, solo análisis)

> **En pausa desde el 13/10 (tarde):** la propuesta #23 («Gestión Diaria unificada», fila 23 de `PROPUESTAS-DE-AJUSTE.md`) decide
> dónde vive el botón de la #21 («Llamadas sin cerrar encuesta», no una pestaña aparte). La puerta descrita abajo ya está
> escrita y probada en local (rama local sin subir); se retoma cuando Miguel responda la #23.

Para el OK de Jhosep y el contrato con Miguel. Sin código hasta los dos OK. Sigue a
`docs/encargos/2026-10-12-codex-cierre-en-lote-propuesta-21.md` (análisis verificado contra el código el 12/10) y a los
reparos a–e de Miguel del 13/10 (`docs/encargos/2026-10-13-f4e-aplicacion-y-propuesta21.md`), con el alcance que Jhosep
aclaró el 13/10 (#270, comentario 6154718149).

## En una línea

Cuando un lead acumula varias llamadas del celular sin resultado, el analista las registra **todas como «No contestó»
con una sola confirmación**; el CRM las registra **una por una** por detrás, cada llamada queda unida a su propia
gestión y conserva su hora. Lo que cambia es solo la fricción de llenar N encuestas iguales.

## Qué queda fijo (del contrato con Miguel)

| Reparo | Qué significa aquí |
| --- | --- |
| **a** Hora de la gestión | La de la confirmación, sin retrofechar (la v4 no recibe fecha y es núcleo sellado). La hora real de cada llamada sigue en el evento y F4-e la cuenta por ahí |
| **b** Estado técnico | **No aplica:** el resultado lo elige el analista, como en cada encuesta de hoy. La macro de salientes no manda estado técnico ni duración (`macrodroid.md` §3, verificado el 29/09): todo sale «desconocido» y no es un dato que falte capturar |
| **c** De a una, idempotente, con garantía en el servidor | Una puerta pequeña que registra **una** pendiente de forma atómica: si la llamada ya no está pendiente (otra pestaña la cerró), **no crea la gestión**. Hoy la v5 guarda la gestión aunque el enlace falle (`no_enlazado`): esa es la carrera que Miguel quiere cerrada |
| **d** «No responde» | Fuera de la primera versión: el lote nunca descarta. Si el analista quiere descartar, lo hace después en la última llamada, como hoy |
| **e** Prioridad | F4-e ya está aceptada (13/10). #21 va después de que Miguel decida los tres hallazgos de pantalla de F4-e o en paralelo si él quiere |

Decisiones de Jhosep que se asumen: solo `no_contesto` (número errado y «no es la persona» son hechos distintos, uno por
llamada); mismo lead y mismo analista; la tarea «siguiente» es opcional y, si se pide, va **una sola vez**, en la última
llamada del lote; la vía del enlace sigue siendo `pestana` (una vía nueva rompería las cubetas de F4-e por vía).

## Qué se construye

### 1. Puerta nueva (migración pequeña, LEVEL 3): `crm.registrar_llamada_pendiente_fn`

- **Firma:** `(p_operacion_id uuid, p_evento_id uuid, p_resultado text, p_submotivo text default null,
  p_detalle text default null, p_siguiente jsonb default null, p_tarea_id uuid default null)` → `jsonb`.
  DEFINER con `search_path = ''`, EXECUTE solo para `authenticated`; mismos roles que la v5.
- **Qué hace, en una transacción:**
  1. Bloquea la fila del evento (`select … for update`) y comprueba que **sigue pendiente**: `atencion =
     'requiere_resultado'`, `identificacion = 'identificado'`, `lead_id` no nulo, `analista_id = auth.uid()`, dirección
     saliente, y **sin enlace vigente**. Si no: `22023` con mensaje de negocio («Esta llamada ya tiene resultado» /
     «Esta llamada no es tuya») y **no se crea ninguna gestión**.
  2. Solo `p_resultado = 'no_contesto'` en esta versión (`22023` si no).
  3. Llama al núcleo sellado `private.llamada_registrar_v4` con el `lead_id` **del evento** (no viene del cliente) y
     `p_descartar = false`, `p_no_insista = false`.
  4. Enlaza con `private.llamada_celular_enlazar_exacto(…, p_via = 'pestana')`. Si el enlace no queda en `enlazado`
     (ni `repetido` con la misma actividad), **lanza** y la transacción entera se deshace: nunca una gestión sin su
     llamada.
  5. Devuelve lo mismo que la v5 (`actividad_id`, `replay`, `enlace`).
- **Idempotencia:** por `p_operacion_id`, igual que la v4 (recibo: el reintento devuelve la respuesta original con
  `replay: true`). La pantalla fija un `p_operacion_id` **por llamada** derivado del lote (`uuid v5(lote_id, evento_id)`),
  así un reintento tras un corte de red repite exactamente la misma operación.
- **Reversa:** `drop function` (sin datos). **Registrador:** como las anteriores (huella del archivo y `prosrc`).
- **Lo que NO toca:** la v4 y la v5 (selladas), tablas, RLS, políticas, F4-e. Una función y su EXECUTE.

### 2. Pantalla (solo analista): `components/gestion-diaria/llamadas-celular.tsx` y `data/use-llamadas-celular.ts`

- En «Pendientes», las filas ya traen `lead_id`, `evento_id`, `evento_origen_id` y `ocurrio_en`. Se agrupan por lead:
  cuando un lead tiene **2 o más** pendientes identificadas, aparece bajo su primera fila el botón
  **«Registrar las N como No contestó»** (con N real).
- Al pulsarlo, un cuadro corto: «Vas a registrar N llamadas a {lead} como No contestó. Cada una queda con su hora.»
  Opcional: «Programar un seguimiento» (una sola tarea, en la última). Botón «Registrar las N».
- Ejecución **en serie**: una llamada a la puerta por fila, esperando la confirmación (`sla-operacion-comandos`
  guarda una intención por lead y rechaza un segundo guardado distinto mientras no confirme: por eso de a una).
  Progreso visible «3 de 5». Si una falla: se detiene, dice cuáles quedaron («2 sin registrar: Reintentar») y
  **no inicia otra operación con id nuevo**: el reintento usa los mismos ids. Si la falla es «ya tiene resultado»
  (otra pestaña), esa fila se salta con aviso y sigue.
- Al terminar: la bandeja se relee, las registradas pasan a «Qué pasó hoy» con vía «desde la pestaña», el foco vuelve
  al título como en los flujos de hoy. Gestión guardada y enlace confirmado se muestran por separado (reparo c).
- Demo: `demo-llamadas-celular.ts` gana dos pendientes más del mismo lead para que el botón exista en la demo.

### 3. Lo que ve supervisor y gerencia

Nada nuevo: F4-e ya cuenta estas gestiones en `resultados_hoy.desde_pestana` y cada llamada sale de «sin resultado».
«Llamadas por hora» del pulso seguirá contando por la hora de la gestión (reparo a); si Miguel quiere la hora real
ahí, es un cambio de F6 sobre los eventos enlazados, no de #21.

## Mapa de reuso

| Qué hace falta | Qué existe | ¿Se reutiliza? |
| --- | --- | --- |
| Registrar una gestión de llamada | `private.llamada_registrar_v4` (núcleo sellado) | Sí, tal cual (la puerta nueva lo llama) |
| Unir la gestión con su llamada | `private.llamada_celular_enlazar_exacto` | Sí, tal cual, exigiendo `enlazado` |
| Saber si la llamada sigue pendiente | `crm.llamadas_celular_eventos` (`atencion`, `lead_id`, `analista_id`) + `crm.llamadas_celular_enlaces` | Sí: lectura con bloqueo de fila dentro de la puerta |
| Idempotencia por operación | Recibo de la v4 por `p_operacion_id` | Sí, tal cual |
| Puerta por llamada hoy | `crm.registrar_llamada_v5` | No se modifica; la nueva es su variante «solo si sigue pendiente» |
| Agrupar pendientes por lead | `FilaBandeja.lead_id` en `lib/llamadas-celular.ts` | Sí; una función nueva `lotesPorLead(pendientes)` |
| Serializar guardados | `data/sla-operacion-comandos.ts` (una intención por lead) | Sí, tal cual: obliga al «de a una» |
| Encuesta de resultado | `registrar-resultado.tsx` | No: el lote no abre la encuesta; un cuadro propio de dos líneas |
| Pruebas de la puerta | `test:llamadas:local` (banco reducido, oráculo, mutantes), gate `test-rls.mjs` con bandera | Sí, el molde de F4-e |

## Pruebas previstas

- **Banco reducido (oráculo + mutantes):** registra una pendiente y la enlaza (`enlazado`); el reintento con el mismo
  `p_operacion_id` devuelve `replay` y no crea otra gestión; evento ya enlazado → `22023` y **cero gestiones nuevas**;
  evento de otro analista → `42501` sin revelar; lead cerrado o vetado → lo que diga la v4; `p_resultado` distinto de
  `no_contesto` → `22023`; `p_siguiente` solo crea la tarea cuando se pide; mutante «guardar aunque el enlace falle»
  rechazado; mutante «lead del cliente en vez del evento» rechazado.
- **Gate (`test-rls.mjs`, bandera nueva `CRM_RLS_EXIGE_LLAMADAS_P21`):** roles, aislamiento entre analistas, y que
  F4-e cuente el lote en `desde_pestana`.
- **Pantalla:** unitarias del agrupado y de la serie (progreso, parada en la primera falla, reintento con los mismos
  ids, salto de «ya tiene resultado»); E2E en Docker con la demo; `revisor-a11y`; navegador en demo.
- **Aceptación en C1:** 3 llamadas al lead de prueba cerrando la encuesta sin guardar → botón «Registrar las 3» →
  «Qué pasó hoy» con las 3 a la hora de confirmación y vía «desde la pestaña»; F4-e: `sin resultado` 0, `resultados_hoy
  .desde_pestana` +3; segunda pestaña abierta con el lote a medias → ninguna gestión duplicada.

## Orden

1. OK de Jhosep a este plan → OK de Miguel al contrato (este archivo es el contrato; sus cambios se anotan aquí).
2. Migración + reversa + registrador + oráculo + mutantes + bloque del gate (Claude) → `auditor-rls` → PR.
3. Miguel: banco, gate con la bandera, advisors, aplicar, registrar, `gen:types`.
4. Pantalla en PR aparte (o en el mismo si Miguel prefiere menos PR) → publicar → aceptación en C1.

## En llano

Hoy, si llamaste cinco veces a alguien que no contesta, llenas cinco encuestas iguales. Con esto llenas una: el CRM
guarda las cinco por detrás, cada una con su hora, y si algo se corta a la mitad te dice cuáles faltan y las reintenta
sin duplicar. Lo único que hace falta en la base es una puerta pequeña que registre una llamada **solo si todavía está
pendiente**, para que dos pestañas abiertas no guarden dos veces. El celular no puede decir si contestaron o no, así que
esa decisión sigue siendo tuya, como ahora.
