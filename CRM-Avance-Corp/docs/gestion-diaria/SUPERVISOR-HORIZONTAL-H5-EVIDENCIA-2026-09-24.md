# Supervisor horizontal — H5

**Estado: H5 CERRADA con evidencia.** Fecha: 24/09/2026, Lima.
Producto de H5: `788834cc`, sobre H1–H4 en `a0fa70a2`. PR de entrega:
[#87](https://github.com/avanza-digital/avancecorp-crm/pull/87).

H5 verifica el supervisor horizontal aprobado; no implementa las fases F5/F6
históricas. Añade dos escenarios de navegador, dos regresiones unitarias y
correcciones pequeñas de presentación/fiabilidad del banco. La migración H3
permanece inmutable y sin instalar en producción.

## Evidencia por etapa

| Etapa | Resultado y cobertura |
|---|---|
| H5.1 · Estados y datos | PASS. `supervisor.test.tsx`, queries de equipo/pendientes/seguimiento y componentes cubren filtros, orden, selección, pestañas, páginas, ficha y retorno; cero/desconocido/error/vacío; actor/rol/demo/día, revocación, retirada del roster, respuestas tardías y aviso de otra persona. H5 añade la sesión sin avisos y carga inicial sin reintento inútil. |
| H5.2 · Recorridos | PASS. Suite Docker completa: 249 aprobadas, cero fallos y 26 omitidas. El dirigido final de equipo, cortes y H5 dio 14/14 PASS; Pendientes incluye 55 tareas, páginas 25/50/55, filtro de vencidas y tres clases de referencia. |
| H5.3 · Visual y accesibilidad | PASS en Chromium y revisión nativa Chrome: 1512 × 805 diez filas; 1366 × 768 nueve; sin scroll de página ni desbordamiento horizontal, sin texto inferior a 16 px ni controles inferiores a 44 px en las mediciones. 390 px, reflujo equivalente y zoom nativo 200 %, teclado/foco/nombres accesibles, once personas, nombre extenso, 999 pendientes/321 vencidas y varios motivos. |
| H5.4 · Calidad y consultas | PASS del gate de código, SQL/RLS, contrato HTTP, tipos y medición REST. Revisión independiente resuelta con evidencia. |

## Resultados ejecutados

- **PASS:** equivalente exacto a `npm run check`, limitando únicamente la
  cobertura a `--maxWorkers=2`. Lint, TypeScript, 4.274 pruebas/287 archivos,
  release-config 4/4, service worker 8/8, build, bundle y duplicación 0,50 %
  frente al umbral 0,80 %. Cobertura: statements 77,13 %, branches 74,17 %,
  functions 74,21 %, lines 80,19 %. [Log final](evidencias-h5-2026-09-24/check-final.log).
- **PASS:** `check:scripts`, `seed:preflight`, `test:rls:preflight` y
  `test:edge-preflight`. Seed/RLS offline usan exactamente los valores
  ficticios `.invalid` del workflow; no abren conexiones. La primera invocación
  carecía de variables y se corrigió el entorno del comando, sin cambiar archivos.
- **PASS:** ensayo SQL local H3, reversa/reinstalación, paridad antes/después de
  ámbitos, regresiones equipo/calendario/SLA, 1.008 tareas/11 páginas, tres
  anclas, errores, concurrencia y siete mutantes detectados.
- **PASS:** PostgREST 14.5 real en banco sintético: roles ajenos/anon rechazados,
  22023, revocación con mismo JWT, páginas y tipos generados concordantes.
  Consultas locales de 25 tareas: 12,644 / 9,466 / 9,243 / 9,055 / 8,745 ms;
  no son un benchmark de producción.
- **PASS:** 50 pruebas focalizadas y 14 E2E dirigidos después de resolver la
  revisión. **249 E2E aprobadas, 0 fallos y 26 omitidas** en la [suite final completa](evidencias-h5-2026-09-24/e2e-final.log), 10 minutos. Docker local, dos workers, cero retries.
- **NOT RUN:** `gate:realidad` CLI, por variables/credencial ausentes en el
  proceso. Se realizó además una [lectura productiva de agregados](evidencias-h5-2026-09-24/realidad-complementaria.json):
  2.237 leads activos, 15.422 actividades, 1.304 tareas pendientes, 18 analistas
  y tres supervisores activos; ningún analista sin supervisor activo.
  Esta lectura complementa los supuestos pertinentes; no sustituye todas las
  sondas del CLI ni demuestra que una sesión de supervisor real vea todo eso.
- **NOT RUN:** VoiceOver/NVDA humano, Safari, ensayo hosted nuevo y aceptación
  operativa real. [Zoom nativo y teclado](evidencias-h5-2026-09-24/zoom-nativo.md)
  sí se comprobaron en demo local. H6 conserva las verificaciones hosted.

El banco H3 es `gestion_diaria_h3_20260923` en
`supabase_db_avancecorp-f5-bank`; se verificó su marcador sintético. El banco
F4 original y la rama remota ajena `banco-f7` no se modificaron.

## Consultas y estabilidad

El [nuevo E2E](../../app/e2e/gestion-diaria-horizontal-h5.spec.ts) cuenta **todas**
las solicitudes `/rest/v1/`, por método/ruta, con equipos de 1 y 32 personas.
Ambos escenarios tienen el mismo conteo por endpoint al terminar cada etapa
estable: 20 peticiones al entrar/filtrar, 21 al seleccionar/alternar pestañas y
32 al completar actualización/error/recuperación. Se conserva el inventario
[completo](evidencias-h5-2026-09-24/consultas-h5.json).

La lectura principal es una por equipo, no una por fila. Antes de seleccionar:
cero Registro y cero Pendientes. Resumen y Registro comparten una lectura;
el refresco explícito hace la segunda. Pendientes permanece sin cargar hasta
visitarse. Un error del resumen no elimina el panel ni su pestaña. Otra prueba
pagina el registro del equipo a 26 elementos y comprueba que Actualizar vuelve
a 25 con una sola lectura y conserva Llamadas. No se cambió Registro por una
sospecha de doble fetch que la prueba no reprodujo.

## Capturas y diferencias justificadas

- [1512 × 805](evidencias-h5-2026-09-24/horizontal-1512.png),
  [1366 × 768](evidencias-h5-2026-09-24/horizontal-1366.png).
- [390 px](evidencias-h5-2026-09-24/horizontal-movil.png),
  [reflujo 200 %](evidencias-h5-2026-09-24/horizontal-200-por-ciento.png),
  [nombre extenso y cifras grandes](evidencias-h5-2026-09-24/horizontal-nombre-largo.png).
- Medidas [1512](evidencias-h5-2026-09-24/medidas-1512.json) y
  [1366](evidencias-h5-2026-09-24/medidas-1366.json): filas de 44 px.

El panel estrecho se convierte en diálogo y el texto largo aumenta la altura
de su fila; no se fuerza el objetivo de diez filas recortando nombres. Las
capturas contienen datos ficticios y escenarios de error deliberados. El gráfico
real conserva 08–20 y la franja diferencia avisos sin reconocer de la lista
completa. La captura histórica «antes» del PR tiene otro viewport y población;
ilustra la composición anterior, no una medición controlada del mismo conjunto.

## Revisión y trazabilidad

[Claude y resolución del PRIMARY](SUPERVISOR-HORIZONTAL-H5-REVISION-2026-09-24.md):
CHANGES_REQUESTED/MEDIUM, dos P2 y varios P3; correcciones verificadas, sin
segunda consulta. Se mantienen cinco warnings de lint (cuatro del carrusel,
uno en Contacto con texto accesible comprobado); no se desactivaron reglas.

Se conservan los intentos fallidos: selector ambiguo del test nuevo, dos casos
rojos antes del arreglo, diferencia intermedia de una lectura paralela,
typecheck `unknown` corregido y primera suite completa 248/1/26 por la espera
del menú oculto tras el popup. La suite interrumpida durante esa corrección
no cuenta como PASS. La evidencia final sustituye los resultados parciales,
sin borrarlos ni atribuirlos al servidor productivo.

H6 continúa con el mismo PR, integración con `avancecorp/main`, artefacto y
respaldo. F4 real del 24/09 y sábado 26/09 permanece separado; tasa baja OFF,
sin activación de TypeSafe/Jev ni actividad ficticia productiva.
