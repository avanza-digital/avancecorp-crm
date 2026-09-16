# Verificación de la candidata — 16/09/2026

Código integrado `a2243c4e` (funcional `25a0b9da`; remotos hasta `1f9e5f83`).
Después del gate se acortó «Cancelar corrección» a «Cancelar» para que el botón
quede dentro del diálogo móvil. Sus cuatro E2E se repitieron con una aserción de
límites, además de lint/tipos y el build del artefacto final. No equivale a publicación.

| Gate | Resultado |
| --- | --- |
| `npm run check:all` en app, worktree aislado | **PASS**, exit 0: lint, tipos, 3.654 tests / 248 archivos, configuración de release, build, bundle, duplicación, 199 E2E; 26 skips declarados por suites existentes. |
| Cobertura | Líneas 78,64%; statements 75,55%; ramas 72,36%; funciones 72,74%. |
| E2E propios | 4 PASS: contacto y detalle/corrección Avance, 1440/390 px, filtros y foco conservados; sin nueva descarga de cartera. |
| Pruebas UI nuevas | Respuestas perdidas, doble envío/cierre, revocación, error/refresco, precarga, ventana, roles de alta y reintento sin recargar cartera. Incluidas en el gate. |
| `npm run check:scripts` | **PASS** en worktree; incluye preflights F5/F7/F8, Apps Script y mutantes. |
| `npm run seed:preflight`, `npm run test:rls:preflight` | **PASS** offline, con valores dummy y loopback; no abren conexiones. |
| `npm run test:edge-preflight` | **PASS**, fronteras de Edge y notificaciones. |
| `test-http.mjs` | **PASS**, 24 grupos contra Auth/PostgREST/PostgreSQL reales locales. [Recibo](HTTP-LOCAL.json). |
| `test-sql.mjs` | **PASS**, instalación candidata sobre snapshot limpio, reversa, ACL/propietarios, funciones public intactas, guardas; rendimiento e igualdad de IDs con 600 contactos. [Recibo](SQL-LOCAL.json). |
| Tipos de base | **PASS**, Supabase CLI introspecta banco local; `integrar-tipos.mjs --verificar` confirma solo cuatro nodos nuevos. |
| `git diff --check` | **PASS**. |
| Claude | Dos revisiones completadas; dictámenes CHANGES_REQUESTED, evaluados y corregidos con evidencia por PRIMARY. [Evaluación](EVALUACION-REVISION.md). |
| Gate general `gate:realidad` | **NOT RUN** completo: CLI requiere SUPABASE_URL/service key no cargadas; intento termina con falta de variable, sin conexión. Se contrastaron por MCP solo los agregados pertinentes de producción y huellas. No se atribuye PASS global. |
| Rama Supabase/advisors remotos/matriz global remota | **NOT RUN** para esta candidata; requiere banco/presupuesto autorizado. La matriz pertinente local sí se ejecutó, no sustituye aprobación remota. |
| Instalación productiva / recorrido con usuarios reales | **NOT RUN**, pendientes de autorización y release. |

## Incidencias del ensayo resueltas

- El sandbox negó abrir el puerto Vite; el gate final se ejecutó con permiso y
  servidor propio. No se reutilizó un servidor de desarrollo.
- Las dependencias enlazadas desde la carpeta común impedían servir tipografías
  (403). Se copiaron al worktree, sin cambiar la configuración de Vite; todos los
  E2E pasan después.
- Una ejecución simultánea de cobertura y navegador agotó 5 s en dos casos de
  `lead-drawer-convertir`; ejecución posterior y gate final secuencial pasan.
- Un test nuevo usó una opción `exact` propia de Playwright en Testing Library;
  typecheck lo detectó, se corrigió y el gate completo vuelve a pasar.
- La llamada directa al cierre archivado y la omisión de vencimiento histórico
  se incorporaron tras la segunda revisión. No se modificaron permisos Avance
  para que coincidieran artificialmente con una expectativa de test.

La inspección final de PNG a 390 px comprobó contacto y detalle Avance. El texto
del botón Cancelar se acortó porque el anterior sobresalía ligeramente; el nuevo
E2E comprueba ambos bordes de cada botón dentro del diálogo. Oxlint mantiene
avisos previos en `coverflow-carousel.tsx`; no se introdujeron reglas silenciadas.

## Entorno y límites

Banco sintético local, con dos bases exclusivamente propias
`gestion_multiempresa_20260916` y `gestion_multiempresa_20260918`, Auth y
PostgREST con etiqueta `avancecorp.gestion.owner=20260916`, puertos loopback.
**Cerrado:** servidor, dos contenedores y dos bases eliminados al acabar;
`rls_vigente_20260916` y el contenedor compartido original permanecen intactos.
No hubo banco de pago ni coste cloud de esta tarea.

Los recorridos E2E interceptan API loopback y no prueban producción. El ensayo
HTTP sí usa sesiones Auth y RPC reales. El ensayo SQL aplica la migración
candidata sobre un snapshot existente; no se afirma replay de todo el historial.
Los PNG de los cuatro recorridos se generan en `app/test-results/`; se inspeccionó
el diseño móvil. El artefacto local final queda en `CRM-Avance-Corp/releases/`,
con manifiesto verificable. Se reconstruirá desde Main igual a avancecorp/main
antes de cualquier publicación autorizada.
