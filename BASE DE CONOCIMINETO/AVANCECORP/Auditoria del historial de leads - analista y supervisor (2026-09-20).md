---
tags: [crm, auditoria, historial, leads, supervisor, analista]
fecha: 2026-09-20
estado: auditoria cerrada; recorte corregido; limite de refresco documentado
---

# Auditoría del historial de leads — analista y supervisor

Relacionado con [[Historial por lead sin topes - Fase 1 (2026-09-19)]],
[[Leads sin foto inicial - Fase 4 del plan sin topes (2026-09-20)]],
[[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] e [[Inicio]].

## Conclusión

La causa del reclamo original está corregida en producción: la ficha consulta
`crm.actividades_de_lead_fn` para el lead abierto. Ya no filtra su historial desde
las primeras 1 000 actividades del ámbito. Analista, supervisor y Gerencia usan
la misma ficha y la misma lectura; los permisos de actividades acompañan al
acceso al lead, sin restringirse al autor de cada gestión.

No se encontraron gestiones faltantes entre las filas autorizadas de las cuentas
evaluadas y el historial almacenado. Sí se confirmó una limitación de actualización:
una ficha que permanece abierta no recibe automáticamente las gestiones nuevas
de otra sesión. Recuperar el foco de la ventana o recargar vuelve a consultar y
las muestra. Es una diferencia temporal de pantalla, distinta del recorte anterior.

Alcance solicitado: análisis y verificación. No se modificó código de producto,
no se publicaron cambios y no se escribieron datos de negocio en producción.

## Evidencia de producción — PASS

Consulta del 20/09/2026, transacción `REPEATABLE READ READ ONLY` y `ROLLBACK`:

- 1 983 leads activos; 1 974 con historial; 13 646 actividades. Máximo actual:
  39 actividades en un lead.
- 23 identidades comerciales activas: 18 analistas, 3 supervisores y 2 Gerencia.
  Cada lectura se ejecutó como `authenticated` con el `sub` de la cuenta.
  No son consultas de usuario realizadas con `service_role`.
- 7 915 pares lead/cuenta visibles comparados contra el conjunto de IDs ordenados
  almacenado: **0 diferencias**. La comparación de todos los pares se realizó
  sobre las tablas bajo RLS; la RPC se verificó con la muestra descrita abajo.
- Dos supervisores tienen 1 000 y 980 leads visibles, con 5 620 y 8 026 gestiones;
  el tercero tiene ámbito vacío. El historial completo no depende del volumen
  de actividades del equipo.
- 110 lecturas completas por RPC: los cinco historiales más largos de cada
  cuenta con leads. Esas mismas lecturas se recorrieron en **341 páginas de
  siete filas**, con idénticos IDs y orden, sin omisiones ni duplicados.
- Lead inexistente: denegación explícita `42501` en las 23 identidades.
- `private.assert_actividades_de_lead()` PASS: funciones INVOKER, permisos,
  grants por columna y huellas de políticas válidos.
- `version.json` publicado: `build-20260920T074546386Z`, correspondiente al
  release documentado de `dbfa9d6b`. Las siete fuentes que gobiernan este flujo
  no tienen diferencias contra ese commit. HEAD local al auditar:
  `f876a4ca63b8557597daa5b5abc906e06cd8b0c2`.

## Limitación P3 — una ficha abierta no recibe gestiones de otra sesión

Evidencia de código:

- `app/src/data/crm-queries.ts:628–643`: `useHistorialLead` no configura
  actualización periódica; su comentario delega el refresco a las mutaciones.
- `app/src/lib/store.tsx:1133–1141`: las mutaciones de la propia sesión cancelan
  e invalidan el historial.
- `app/src/lib/store.tsx:1371–1399`: recuperación al recibir `focus`,
  `visibilitychange` u `online`, con enfriamiento de 20 segundos.
- `app/src/lib/query-client.ts:26–40`: `staleTime: 30_000` permite releer una
  consulta vieja cuando hay un disparador; no programa una lectura a los 30 s.
- La publicación Realtime de producción no incluye tablas del esquema `crm`.

Reproducción local con Chromium y HTTP de Supabase simulado, tanto para
`vendedor` como para `supervisor`: abrir una ficha sin gestiones, añadir una nota
a la respuesta del servidor como si la hubiera escrito otra sesión y esperar
35 segundos. No se produce otra consulta ni aparece la nota. Al emitir `focus`,
se consulta y aparece. **Ambas reproducciones confirmadas.** No se usaron
credenciales reales ni se creó una gestión productiva.

Consecuencia: el usuario que registra una gestión la ve y otra persona con la
ficha abierta puede seguir viendo el estado anterior. No hay pérdida demostrada
de datos ni un fallo actual de permisos. El refresco por foco es el comportamiento
documentado del código; sin un requisito explícito de sincronización en vivo,
se clasifica como limitación de frescura, no como regresión de la corrección.

Siguiente mejora recomendada: refrescar automáticamente el historial mientras
la ficha permanezca visible, conservando RLS y suspendiendo consultas al cerrarla.
Añadir una prueba de dos sesiones si se adopta esa mejora. Requiere elegir la
frecuencia y el coste de las consultas; no se implementó en esta auditoría.

## Verificación local

- **PASS — 97 pruebas** en cinco archivos: `historial-lead.test.ts`,
  `timeline-lead.test.ts`, `use-actividades-de-lead.test.tsx`,
  `crm-api-msw.test.ts` y `timeline-historial.test.tsx`.
- **PASS — 2 E2E existentes**, `e2e/historial-lead.spec.ts`: lectura por lead
  con lista global vacía, persistencia tras recargar y apertura por ID fuera
  de la foto inicial. Usan HTTP simulado.
- **CONFIRMADO — 2 E2E de caracterización** del refresco, analista y supervisor.
  El archivo temporal se retiró de la suite; su copia queda como evidencia.
- **NOT RUN:** dos sesiones reales simultáneas en navegador con escritura de
  datos productivos. Las lecturas SQL reales y los E2E simulados son pruebas
  distintas, no sustituyen esa aceptación de negocio.
- **NOT RUN:** build, lint, typecheck y suite integral: no hay cambios de producto.
- **Límite de cobertura:** ningún lead real supera las 100 actividades actualmente.
  El límite de 100 filas más una de anticipación sí está cubierto con 101 filas
  sintéticas en `crm-api-msw.test.ts:426–455`; el recorrido SQL real usó páginas
  de siete filas. No se atribuye a producción una prueba con un historial de 101.

## Evidencia reproducible

En `CRM-Avance-Corp/docs/auditorias/historial-leads-2026-09-20/`:

- `auditoria.sql`: consulta de solo lectura, sin identidades codificadas.
- `resultado-produccion.json`: agregados sin nombres, contactos ni IDs personales.
- `fuentes-sha256.txt`: huellas de las siete fuentes revisadas.
- `verificacion.txt`: comandos, resultados y límites.
- `reproduccion-refresco.spec.ts.txt`: prueba temporal; para repetirla, copiar a
  `app/e2e/historial-auditoria-temporal.spec.ts` y ejecutar
  `npm run test:e2e -- e2e/historial-auditoria-temporal.spec.ts` desde `app/`.

## Revisión independiente y decisión del PRIMARY

Claude, mediante `scripts/claude-review`, emitió **CHANGES_REQUESTED** sobre
la clasificación y el alcance del informe. La primera ejecución no produjo un
dictamen válido; la segunda, más focalizada e incluyendo la nueva reproducción,
sí entregó el informe. No hubo cambios de producto por parte del reviewer.

- Aceptado: distinguir la integridad del historial del refresco de una ficha
  abierta; reclasificada la observación P2 como limitación P3.
- Aceptado: mantener explícito que los 7 915 pares validan RLS sobre tablas,
  mientras las 110 lecturas y 341 páginas validan una muestra de la RPC.
- Aceptado parcialmente: falta una frontera de 101 filas con datos reales;
  existe cobertura sintética en el MSW citado, ya ejecutada con PASS.
- No elevado a hallazgo: posible desaparición transitoria de una fila optimista.
  El reviewer lo marcó como hipótesis sin fuente suficiente. El PRIMARY revisó
  `historial-lead.ts:99–127` y la cancelación e invalidación posterior a la
  escritura (`store.tsx:1133–1141`); no hay reproducción que permita afirmar
  una pérdida persistente. No se solicita otra revisión para obtener un PASS.

Dictamen del PRIMARY: causa original corregida dentro del alcance verificado;
limitación de actualización entre sesiones documentada. Informe del reviewer
y evaluación conservados en la carpeta de evidencia.
