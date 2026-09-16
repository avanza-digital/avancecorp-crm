# Verificación de gestión integral publicada — 16/09/2026

Fuente publicada `14be1e0581d8`, árbol completo idéntico a `bd4ab4cd`, cuyo CI
final tiene verify, e2e y preflight PASS. [Acta](PUBLICACION.json).
La evidencia local siguiente conserva sus commits y condiciones originales.

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
| Rama Supabase y matriz remota | **PASS**: 1.866 aserciones RLS y 24 grupos Auth/HTTP/SQL. Advisors revisados con avisos documentados en [REMOTO.md](REMOTO.md). Rama eliminada. |
| Instalación productiva | **PASS**: SQL aprobado instalado; datos/permisos previos intactos y lecturas de 23 cuentas verificadas. [Recibo](PRODUCCION.json). |
| Artefacto y publicación web | **PASS**: fuente limpia de Main igual al remoto; 95 comprobaciones HTTP y acceso sin errores JavaScript. [Acta](PUBLICACION.json). |
| Recorrido autenticado con usuarios humanos productivos | **NOT RUN**; no se escribieron datos de negocio para probar. |

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
Esa fase local no tuvo coste cloud. Después se autorizó un banco remoto hasta
US$0,10: eliminado y con coste estimado de US$0,009353; no es una factura.

Los recorridos E2E interceptan API loopback y no prueban producción. El ensayo
HTTP sí usa sesiones Auth y RPC reales. El ensayo SQL aplica la migración
candidata sobre un snapshot existente; no se afirma replay de todo el historial.
Los PNG de los cuatro recorridos se generan en `app/test-results/`; se inspeccionó
el diseño móvil. El artefacto local final queda en `CRM-Avance-Corp/releases/`,
con manifiesto verificable. La publicación posterior se construyó desde Main
limpio e idéntico a `avancecorp/main`; su fuente y huella constan en el acta.
