# F4 etapa 3 — publicación completada, cortes apagados

**Publicada el 22/09/2026, 12:28 Lima, y verificada después de la subida.**
El cliente compatible de F4.3 ya está en [crm.miavance.com](https://crm.miavance.com/).
La política SQL sigue en v1, con `cortes_activos=false`. Esta entrega técnica
no incorpora el pop-up ni activa nuevos avisos; las etapas 4–6 siguen pendientes.
Plan vigente: [GESTION-DIARIA.md](GESTION-DIARIA.md).

## Fuente y artefacto

- Commit: `e22c0cab2db30c5f570adf28f998d4d773fb3ed9` (PR #68 y actualización #69).
- Build servido: `build-20260922T165247339Z`.
- Entrada: `assets/index-DtlRdUFd.js`.
- ZIP: `releases/crm-20260922T165248Z-e22c0cab2db3.zip`, con manifiesto homónimo.
- SHA-256: `58f81cbf903ffdcef6d892dabd38d7f75cf99d4f81d6baae7eb87e3192989098`.

Se reutilizó el artefacto exacto construido y comprobado en la sesión anterior.
La copia limpia `/private/tmp/avancecorp-release.hvdub4/repo` conservaba `main`
y `avancecorp/main` en ese commit, sin cambios. Se hizo fetch y se volvió a
consultar el remoto justo antes de publicar. El taller principal sigue con
dos commits locales, dos remotos por integrar y trabajo ajeno sin confirmar;
no se reseteó, no se creó otro worktree y no se incluyó ese trabajo en el ZIP.

El plan local se reconcilió documentalmente con la versión de `avancecorp/main`,
conservando el checkpoint del SQL productivo y las decisiones ya aprobadas.
Esto no equivale a integrar las ramas Git del taller.

## Hostinger y recuperación

La conexión nativa de la sesión exponía 15 herramientas de Agency Hosting.
El conector oficial de Hosting **ya instalado**, `hostinger-api-mcp` 1.59.0,
ofreció 64 herramientas y autenticó la consulta del sitio exacto. Se utilizó
su transporte stdio y `hosting_deployStaticWebsite`, con el ZIP local y
`removeArchive=false`. Se renovó su sesión OAuth guardada con permiso de
ejecución; no se editaron configuraciones MCP, DNS ni el proveedor.

Se recuperó el sitio anterior completo antes de subir:

- Build anterior: `build-20260921T223103201Z`.
- ZIP de recuperación: `releases/crm-respaldo-live-20260922T172350Z.zip`.
- Manifiesto: `releases/crm-respaldo-live-20260922T172350Z.manifest.json`.
- SHA-256: `7b881ca493f16db24f048618c2ad0d3471df055014dc3a21cc9b1dcf0d635432`.
- Copia privada, inventario y archivos: `releases/private/crm-respaldo-live-20260922T172350Z/`.

**Es una captura verificada del sitio, no el ZIP original extraviado.**
Los 107 archivos se cotejaron byte a byte con una recompilación de
`59dd14805b646e2adb281302b8441265e969d914`, fijando su build ID y la
configuración pública. La fuente reproducible se declara así en el manifiesto;
no se inventa la procedencia del manifiesto original. Ese commit es ancestro
del candidato y el preflight existente pasó sin modificar sus guardas.

Hostinger inventarió todos los archivos y entregó `.htaccess` por MCP. Para
evitar las transformaciones PNG de la CDN, se descargó por HTTPS desde el
origen `147.79.84.218`, obtenido de los registros DNS existentes del CRM, con
el dominio/TLS conservados. No se cambiaron DNS ni opciones de caché. Los
bytes, tamaños e inventario coinciden; `index.html` y `version.json` se
mantuvieron estables durante la captura.

El respaldo permite recuperar sólo el frontend si fuera necesario. Esta
entrega no ejecutó recuperación ni modifica la reversión SQL: el resguardo
de las seis funciones sigue siendo evidencia privada, no una reversa ejecutable.

## Verificaciones

| Comprobación | Resultado y alcance |
|---|---|
| `npm run check` de la copia limpia | PASS previo para el mismo commit, conservado en el checkpoint de preparación; no repetido en esta retoma |
| `release:crm:verify` | PASS repetido; SHA-256 del ZIP original intacto |
| Inventario interno del ZIP | PASS: los 107 archivos coinciden en nombres, tamaños y SHA-256 con el manifiesto |
| Main/copia limpia/remoto | PASS antes de subir; taller principal preservado |
| Preflight de publicación | PASS: versión anterior reproducible, ancestría y Ficha 360 |
| SQL productivo, sólo lectura | PASS: `assert_gestion_diaria_cortes`, `assert_gestion_diaria` y los cuatro gates SLA |
| Política después de publicar | PASS: una sola fila, versión 1, cortes desactivados |
| Archivos publicados en origen | PASS: 107, incluida configuración obtenida por MCP, con SHA-256 del manifiesto |
| Recursos públicos | PASS: 106; bytes exactos salvo PNG transformados por CDN, cuyos originales sí se cotejaron |
| Portada/versionado | PASS: HTTP 200, portada igual a `index.html`, nuevo build ID y entrada correctos |
| Archivos internos | PASS: ZIP 404, `.env` 403, `.git/config` 403, `package.json` 404 |
| Acceso básico en navegador | PASS: login visible, campos y botón Entrar, cero errores JavaScript; captura conservada |
| Recorrido productivo autenticado del supervisor | NOT RUN en esta retoma; pendiente con el negocio |
| Nuevos avisos, reconocimiento y posponer | NOT RUN: aún no implementados, cortes OFF |

El navegador integrado no tenía conexión disponible. La comprobación visual
se ejecutó con Playwright local en un navegador aislado; no se inició sesión
ni se crearon actividades, tareas, usuarios o datos de negocio.

La matriz SQL/RLS/HTTP y el ensayo de compatibilidad anteriores conservan su
alcance en el [acta versionada de F4.3](https://github.com/avanza-digital/avancecorp-crm/blob/e22c0cab2db30c5f570adf28f998d4d773fb3ed9/CRM-Avance-Corp/docs/gestion-diaria/F4-CORTES-JORNADA.md).
No se confunden esas pruebas de banco con una sesión humana en producción.

## Revisión y pendientes

La revisión previa de Claude está en el acta de implementación: su último
dictamen utilizable fue `CHANGES_REQUESTED`, con hallazgos evaluados y resueltos
por el PRIMARY con evidencia. Las consultas adicionales sin dictamen recuperado
**no cuentan como PASS**. En esta retoma no se inició otra revisión.

No se aplicó SQL ni se activaron cortes. Antes de otra publicación de migraciones
por CLI, reconciliar el registro remoto `20260922164159` con el archivo
`20260921214018_crm_gestion_diaria_cortes.sql`, sin reinstalarlo. Los dos avisos
INFO de claves foráneas sin índice quedan para revisión posterior, según el
[linter de Supabase](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

Sigue F4 etapa 4: pop-up agrupado por corte, reconocimiento y aplazamiento
persistentes entre dispositivos, sin interrumpir otra interacción ni duplicar
avisos. El sábado mínimo 3, la exclusión del aviso para cartera vacía y un solo
aplazamiento de una hora sin reaviso al cierre ya están aprobados. Después,
etapa 5 (configuración), etapa 6 (validación y activación futura), F5 y F6.
TypeSafe mantiene su piloto separado y no condiciona esta publicación.

## Evidencia privada conservada

- `releases/private/gd-f4-20260922-frontend-deploy-result.json`.
- `releases/private/gd-f4-20260922-frontend-postflight.json`.
- `releases/private/gd-f4-20260922-sql-y-login.json`.
- `releases/private/gd-f4-20260922-login-publicado.png`.
- `releases/private/crm-respaldo-live-20260922T172350Z/`.

Los artefactos y resguardos permanecen fuera del web root y del contenido Git.
