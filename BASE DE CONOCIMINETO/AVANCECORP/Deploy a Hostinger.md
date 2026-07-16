# Deploy a Hostinger

Desde el **2026-06-10** el deploy del portal ya **no es manual**: Claude puede desplegar directo con el **MCP de Hostinger** (Miguel instaló el token de la API).

## Procedimiento (vía MCP)

1. Armar un ZIP de **todo** `public_html/` (fuente única) excluyendo contenido local: `CLAUDE.md`, `.git/`, `.claude/`, `.codegraph/`, `.gitignore`, `.DS_Store`, `tests/`, `node_modules/` y artifacts que empiecen con `_` **solo en la raíz**.
   - En `rsync`, usar `--exclude='/_*'`, con la `/` inicial. **Nunca** `--exclude='_*'`: ese patrón también elimina `js/admin/_helpers.js` y rompe los módulos administrativos en una sesión sin caché.
   - Antes de comprimir, exigir `test -f "$stage/js/admin/_helpers.js"`; después, confirmar con `zipinfo` que el ZIP contiene `js/admin/_helpers.js`.
2. Desplegar con la herramienta `hosting_deployStaticWebsite` al dominio **miavance.com** (root: `/home/u318796122/domains/miavance.com/public_html`).
3. Verificar en vivo:
   - `curl https://miavance.com/service-worker.js` → `CACHE_VERSION` debe ser la versión nueva.
   - Spot-check de los archivos cambiados (HTTP 200).
   - Confirmar que el ZIP **no** quedó accesible públicamente (debe dar 404).

## ⚠️ Regla del `?v=` — OBLIGATORIA al cambiar cualquier JS del portal

Los módulos del portal se importan con query de versión (`auth.js?v=20`, `login.js?v=22`…) y los
navegadores cachean por URL COMPLETA. **Cambiar el contenido de un JS sin subir su `?v=` = los
usuarios siguen con la copia vieja** aunque el server ya sirva la nueva. Ya mordió 2 veces
(2026-05-07 con `auth.js?v=7`, y 2026-07-16 con el cierre de la puerta del analista).

Al cambiar un JS: (1) subir el `?v=` en TODOS sus importadores (otros JS **y** los `<script>` de
los HTML — el import es en cadena: HTML→page.js→auth.js, cada eslabón cachea); (2) usar un número
VIRGEN (nunca reutilizar uno ya publicado); (3) bump del `CACHE_VERSION` del SW; (4) tras el
deploy, purgar la caché del hosting (`hosting_clearWebsiteCacheV1` — LiteSpeed sirve versiones
mezcladas hasta la purga) y verificar con 3 lecturas consecutivas del sha.

## CRM (crm.miavance.com)

Mismo mecanismo, dominio distinto (**2026-07-10**, primer update por esta vía):

1. `npm run build` en `CRM-Avance-Corp/app/` (lee `.env` local; el demo queda fuera del bundle de producción).
2. ZIP del **contenido** de `dist/` (index.html en la raíz del zip, `.htaccess` incluido).
3. `HOSTINGER_API_TOKEN="$(cat ~/.hostinger_token)" node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs deploy crm.miavance.com <zip>` — la tool resuelve el usuario del subdominio sola.
4. Verificar: HTML en vivo referencia los hashes del build nuevo · asset nuevo responde 200 · el ZIP da 404 en `crm.miavance.com/` y en `miavance.com/` · smoke visual (login carga, sin errores de consola).

- El **token** vive en `~/.hostinger_token` (chmod 600, fuera del repo). Si se rota en hPanel, actualizar ese archivo.
- El CRM **no usa service worker**: no hay `CACHE_VERSION` que bumpear; el cache-busting lo hacen los hashes de Vite.

## Notas

- **Deploy 2026-07-15 — CRM `crm.miavance.com`: acciones reales HABILITADAS (bloque 5):** build `index-CKrhWMgO.js`, ZIP con index.html+`.htaccess` en la raíz. Verificado en vivo: HTML sirve el hash nuevo, JS/CSS 200, ZIP 404 en ambos dominios, asset viejo `index-CnJyAL0E.js` 404, CSP/HSTS intactos, apunta a `dctqcbznekcyxhjujuci`, sin fixtures ni botón demo. El CRM pasó de solo-consulta a permitir crear/editar/mover/descartar/reabrir/actividad/reasignar (convertir sigue vetado hasta bloque 6). Falta prueba visual de Miguel con cuentas QA. Ver [[CRM conexión a datos reales]] §Bloque 5.
- **Deploy 2026-07-15 — corrección Fecha contrato del Excel / SW `avance-v100`:** el Reporte completo ahora lee **Fecha contrato (Excel)** desde la columna `FECHA CONTRATO` de la base adjuntada; reemplaza la versión v99, que había usado incorrectamente `contratos.fecha_inicio`. Se desplegó un ZIP filtrado de 95 archivos, con `conciliacion.js?v=5` y `conciliacion-core.js?v=4`. Página, módulos y `service-worker.js` quedaron idénticos byte a byte a producción; el ZIP responde 404.
- **Deploy 2026-07-14 — matriz de estado Excel v3 / SW `avance-v98`:** la vista inicial de conciliación quedó como `Estado de base`, con columnas explícitas `Cliente en sistema` y `Contrato cargado` para cada fila de la base maestra. Se mantuvieron las bandejas operativas y los dos entregables. Paquete filtrado de 83 archivos con `js/admin/_helpers.js`; página, JS, CSS, núcleo, `_helpers.js` y SW idénticos byte a byte en producción; texto visible confirmado; ZIP/pruebas/`CLAUDE.md` → 404 y `.htaccess` → 403.
- **Deploy 2026-07-13 — conciliación v2 / SW `avance-v97`:** se desplegó el paquete consolidado de 83 archivos con `conciliacion.css/js/core ?v=2`, bandejas de trabajo y dos entregables. El staging usó `--exclude='/_*'` y restauró `js/admin/_helpers.js`, que el deploy v96 había omitido por usar el patrón recursivo `--exclude='_*'` (producción daba 404). Verificación posterior: página/CSS/JS/core/SW/Clientes/`_helpers.js` idénticos byte a byte; SW v97; ZIP, pruebas y `CLAUDE.md` → 404; `.htaccess` y `graphify-out/` → 403.
- **Deploy 2026-07-13:** portal actualizado a SW `avance-v96` para publicar [[Conciliación de clientes]]. Se desplegó un ZIP filtrado de 90 archivos. Página, CSS, JS, enlace desde Clientes y service worker quedaron idénticos byte a byte entre local y producción; ZIP, pruebas y `CLAUDE.md` respondieron 404 y `.htaccess` 403.
- **Truco de verificación fuerte (2026-07-10):** comparar `md5 -q archivo` local vs `curl -s https://miavance.com/archivo | md5 -q` — confirma byte a byte que prod = local. Ojo: `.htaccess` NO se puede comparar así (Apache lo bloquea con 403, que es lo correcto); el "diff" que da es la página de error.
- **Re-verificación 2026-07-10 (noche):** ambos deploys sanos — CRM en vivo sirve los hashes exactos del build local, portal con SW v93 y 6 archivos clave idénticos por md5, ZIPs 404 en ambos dominios, `.htaccess` 403.
- El primer deploy por esta vía fue el **2026-06-10** (SW v89: mejoras de contratos/analista/pagos/dashboard/inversión + crono-timeline). Funcionó completo: 107 archivos, verificado en vivo.
- El flujo manual viejo (File Manager / FTP) sigue documentado en `public_html/CLAUDE.md` §14 como respaldo.
- Siempre **bumpear `CACHE_VERSION`** en `service-worker.js` antes de desplegar para que el SW limpie el caché de los clientes (ver [[Arquitectura del portal]]).
