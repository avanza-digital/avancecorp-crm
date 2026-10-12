# Revisión PR #232 — H-WA — 09/10/2026

## VERDICT: PASS

Revisado `f52dbe6afbb836a4821d89a7a066fade73e3ed9d`, base `918a97cb3b7d922ff7f7eadcaa13e23305c142ce`. PR https://github.com/avanza-digital/avancecorp-crm/pull/232 . Seis archivos: una pantalla, sus pruebas y cuatro documentos. Cambio funcional: una guarda de tipo/estado en `abrirRegistro`.

## Resumen y evidencia

Sin hallazgos P0–P2 ni cambios obligatorios. El arreglo aplica la recomendación del #231:

- `app/src/screens/gestion-diaria/analista.tsx:342–366`: respeta la tarea autoritativa de la fila, cargada localmente o pedida por ID. La nueva guarda en línea 360 conserva únicamente una tarea de tipo llamada y estado pendiente. Para WhatsApp/reunión/tarea terminada pasa null; no cae al cálculo que escogería otra tarea del mismo lead. La comprobación de sesión vigente y la protección contra respuestas tardías se conservan.
- La rama sin tarea autoritativa sigue usando `tareaQueCierra`; `store.tareasDe` ya entrega solo pendientes activas, y el helper restringe tipo, dueño y fecha. Sin cambio en ese circuito.
- `registrar-resultado.tsx:203/446` traduce tarea null a `tarea_id: null` y oculta la casilla de cierre. `store.tsx:3180–3185` conserva la validación que rechaza tareas incompatibles. No se modifica servidor, RLS, SQL ni Edge.
- Cuatro pruebas nuevas comprueban WhatsApp/reunión locales, WhatsApp remota y llamada ya completada; los dobles de llamada válida ahora incorporan tipo/estado. Se conserva la cobertura de cierre de la tarea correcta, carga por ID y no sustitución.
- Los documentos distinguen arreglo en código de publicación y prueba física pendientes. Las casillas siguen 44/102, 2/8; no se declara cerrado el piloto.

## Verificación

- **PASS propio:** `npm run test:run -- src/screens/gestion-diaria/analista.test.tsx --maxWorkers=2`: 91/91, un archivo, 3,10 s, exit 0.
- **PASS propio:** Docker local, imagen Playwright v1.61.1-noble, `gestion-diaria-analista.spec.ts` + `llamadas-celular.spec.ts`, dos workers: 11/11 en 24,1 s, sin reintentos reportados, exit 0. Log: `/private/tmp/pr232-review-20261009/e2e.log`.
- **PASS de CI corroborado en el log exacto de la cabeza:** 399 archivos, 6470/6470 tests; lint, typecheck, cobertura, build, verificación de bundle y duplicación. app-check job 113951840854, run 37969372131. Los checks preflight, cambios, app-check y verify terminaron success; Supabase Preview omitido por no haber SQL.
- **PASS:** `git diff --check`; parseo de estado.json; regeneración aislada de PLAN.md/AVANCE.md idénticos byte a byte; casillas iguales a main.
- **NOT RUN físico C1:** corresponde después de publicar. Los E2E ejecutados son regresión general del circuito y no reproducen específicamente una fila WhatsApp con la macro real. El caso H-WA está cubierto por las unitarias nuevas; la aceptación física sigue pendiente.
- La afirmación de que las cuatro pruebas fallan sin el arreglo es evidencia reportada por Jhosep; no se volvió a ejecutar ese mutante.
- Riesgo LEVEL 1: corrección local sencilla, causa y solución ya determinadas. No se pidió un segundo agente solo para confirmar el guard.

## Qué hacer

1. Aprobar y fusionar #232 por el flujo normal. No hace falta pedir otro commit ni repetir P1–P15.
2. Construir/publicar el frontend desde main sincronizado con avancecorp/main, verificando que contiene esta corrección y los demás cambios remotos. No se necesitan migraciones ni despliegue de Edge.
3. Después de publicar, Jhosep prueba solo H-WA en C1: lead de prueba propio cuya fila tenga un WhatsApp pendiente; llamar y registrar un resultado que conserve el lead (por ejemplo «No contestó» sin marcar perdido). Debe faltar «Cerrar también WhatsApp», guardarse la llamada y seguir pendiente el WhatsApp. Si existe otra tarea de llamada, tampoco debe cerrarse en su lugar.
4. Registrar esa evidencia y cerrar H-WA. H-P5/H-P10 y las fases/piloto restantes mantienen su seguimiento; Jev apagado.

Esta tarea pidió analizar y recomendar. No se envió aprobación/comentario en GitHub ni se fusionó/publicó el #232. Revisión realizada con HEAD detached en la copia limpia de /private/tmp; el checkout compartido no se modificó. Al terminar se restituye main en la copia limpia.

CONFIDENCE: alta para el cambio y sus regresiones; aceptación física pendiente tras publicación.

Relacionadas: [[Llamadas desde el celular - segunda revision PR 231 (2026-10-09)]], [[Llamadas desde el celular - revision PR 231 y P9 corroborada (2026-10-09)]], [[Inicio]].
