# F4-b · Pantalla del analista — plan corto (borrador para el OK de Jhosep y de Miguel)

Escrito el 05/10/2026. Sigue a `F4-PLAN-CORTO.md` (§2 y §3, hallazgos 1 y 3) y al prototipo que le gustó a Miguel
(https://claude.ai/artifact/NcXoy3g69AVv7vTWxD5mgv). **Solo análisis: las dos lecturas nuevas de la base necesitan OK
antes de escribir SQL.**

## En una línea

El analista ve en su Gestión Diaria las llamadas del celular que quedaron sin resultado, las resuelve desde ahí, y la
encuesta que se abre al colgar queda unida a su llamada exacta.

## Qué ya está (parte A: PR #193, borrador, rama `crm/llamadas-f4b-20261005`, sin publicar)

- El enlace de la macro acepta el id de la llamada: `#/gestion-diaria/llamada/<número>/<id>` (`lib/router.ts`). Las URL
  sin id siguen funcionando igual (F1 no cambia).
- El receptor lo pasa a la intención de contacto, también cuando el lead se elige a mano (`receptor-llamada.tsx`,
  `lib/intencion-contacto.ts`).
- La encuesta dice «Llamada del celular de las 10:42» (hora sacada del propio id, en Lima; `lib/origen-llamada.ts`). Dirá
  «Quedará unida…» recién cuando llame a la v5: antes sería falso.
- Verificado: pruebas unitarias y en el navegador con la demo (con id muestra la línea; sin id, nada cambia).

## Qué falta, y de qué depende

| Paso | Qué | Depende de |
| --- | --- | --- |
| B1 | **Tipos** de las puertas de llamadas en `database.types.ts` | Miguel: generarlos desde su banco con las siete aplicadas (pedido en el #190). Nunca a mano (estándar de 4 capas) |
| B2 | **Octava migración: dos lecturas** (abajo) | Tu OK y el de Miguel a este plan |
| B3 | **Módulo de datos** `data/llamadas-celular-api.ts`: bandeja, detalle, asociar, enlazar, descartar y las dos lecturas nuevas, con su rama de demo | B1 (y B2 para las lecturas nuevas) |
| B4 | **La encuesta llama a la v5** cuando la intención trae id: `p_evento_origen_id` + vía (`al_colgar` desde el enlace, `pestana` desde la pestaña). Sin id, sigue la v4 tal cual. Comando con recibo nuevo (`registrar_llamada_v5` en `data/sla-operacion-comandos.ts`, para que un reintento no duplique). El aviso dice lo que pasó: unida, o «no se pudo unir» y por qué | B1 |
| B5 | **Pestaña «Llamadas del celular · N»** en «Tu cola y tu actividad» (`screens/gestion-diaria/analista.tsx`): «Pendientes» (registrar, elegir el lead de su cartera, descartar con motivo), «Qué pasó hoy» y el detalle (ya registrada, descartada, «no está disponible», reintento) | B3, B4 |
| B6 | **Marca «Celular C1»** en «¿Qué hice hoy?» (`components/gestion-diaria/registro-actividad.tsx`) | B3 |
| B7 | «¿Es este su resultado?» para resultados ya guardados sin enlazar (F4.2.4): un toque llama a `crm.enlazar_llamada_celular`; nunca solo | B3 |
| B8 | Pruebas unitarias, E2E en Docker con la demo, revisor de accesibilidad | Todo lo anterior |

## B2 · Las dos lecturas nuevas (octava migración, para tu OK)

Las dos son **puertas de solo lectura** en `crm` (DEFINER, con `search_path` vacío; EXECUTE solo `authenticated`) que
delegan en un núcleo INVOKER de `private`. El ámbito lo decide el servidor con la misma regla de la bandeja
(`private.llamada_celular_visible`: lead activo y del ámbito del actor, gerencia incluida). Sin tablas nuevas.

1. **`crm.llamadas_celular_resueltas_hoy_fn(p_limite)`** — «Qué pasó hoy» (hallazgo 1): las llamadas del día (en Lima)
   que ya no están pendientes, con su resultado (de la actividad enlazada: resultado y si se deshizo) o su motivo de
   descarte, y la vía del enlace. Paginada como la bandeja.
2. **`crm.actividades_con_llamada_celular_fn(p_actividad_ids uuid[])`** — la marca «Celular» (hallazgo 3): de una
   lista de gestiones que la pantalla ya tiene, cuáles están unidas a una llamada del celular, con la etiqueta (C1) y la
   vía. Tope de ids por llamada. **No se toca `crm.registro_actividad_fn`**: cambiar su salida sería un cambio de
   contrato de una puerta que ya usan otras pantallas.

Cada una con su oráculo en el banco reducido (ámbito por rol, lead dado de baja, otro equipo), su reversa y su
registrador, como las siete.

## Decisiones (recomendación de Claude)

| # | Decisión | Recomendación | Alternativa |
| --- | --- | --- | --- |
| 1 | ¿La v5 reemplaza a la v4 en todas las encuestas? | **Solo cuando la intención trae id**; sin id, la v4 de siempre | Siempre la v5: un solo camino, pero toca todas las encuestas a la vez |
| 2 | Marca «Celular» | **Puerta aparte (lectura 2)** | Añadir el campo a `registro_actividad_fn`: un viaje menos, pero cambia una puerta usada por otras pantallas |
| 3 | «Qué pasó hoy» | **Solo el día de hoy (Lima)** | Un rango de días: más útil para revisar, más carga |

## Verificación prevista

- Banco reducido: oráculos de las dos lecturas y mutantes.
- App: `npm run check` (lint, typecheck, cobertura, build).
- E2E en Docker con la demo: enlace con id → encuesta unida; pestaña con pendientes; descartar; «Qué pasó hoy»; marca.
- Revisor de accesibilidad sobre la pestaña.
- En C1, recién con F4-d (ahí se activa el celular).

## En llano

La parte del celular que lleva el id hasta la encuesta ya está hecha y probada. Para el resto hacen falta dos cosas: que
Miguel genere los tipos desde su banco (no se pueden escribir a mano) y dos lecturas nuevas en la base, una para «qué
pasó hoy» y otra para marcar en «¿Qué hice hoy?» lo que vino del celular. Esas dos lecturas esperan tu OK.
