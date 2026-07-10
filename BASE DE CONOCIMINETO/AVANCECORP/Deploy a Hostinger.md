# Deploy a Hostinger

Desde el **2026-06-10** el deploy del portal ya **no es manual**: Claude puede desplegar directo con el **MCP de Hostinger** (Miguel instaló el token de la API).

## Procedimiento (vía MCP)

1. Armar un ZIP de **todo** `public_html/` (fuente única) **excluyendo los 5 archivos locales**: `CLAUDE.md`, `.git/`, `.claude/`, `.gitignore`, `.DS_Store` (y artifacts `_*` si aparecieran).
2. Desplegar con la herramienta `hosting_deployStaticWebsite` al dominio **miavance.com** (root: `/home/u318796122/domains/miavance.com/public_html`).
3. Verificar en vivo:
   - `curl https://miavance.com/service-worker.js` → `CACHE_VERSION` debe ser la versión nueva.
   - Spot-check de los archivos cambiados (HTTP 200).
   - Confirmar que el ZIP **no** quedó accesible públicamente (debe dar 404).

## CRM (crm.miavance.com)

Mismo mecanismo, dominio distinto (**2026-07-10**, primer update por esta vía):

1. `npm run build` en `CRM-Avance-Corp/app/` (lee `.env` local; el demo queda fuera del bundle de producción).
2. ZIP del **contenido** de `dist/` (index.html en la raíz del zip, `.htaccess` incluido).
3. `HOSTINGER_API_TOKEN="$(cat ~/.hostinger_token)" node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs deploy crm.miavance.com <zip>` — la tool resuelve el usuario del subdominio sola.
4. Verificar: HTML en vivo referencia los hashes del build nuevo · asset nuevo responde 200 · el ZIP da 404 en `crm.miavance.com/` y en `miavance.com/` · smoke visual (login carga, sin errores de consola).

- El **token** vive en `~/.hostinger_token` (chmod 600, fuera del repo). Si se rota en hPanel, actualizar ese archivo.
- El CRM **no usa service worker**: no hay `CACHE_VERSION` que bumpear; el cache-busting lo hacen los hashes de Vite.

## Notas

- **Truco de verificación fuerte (2026-07-10):** comparar `md5 -q archivo` local vs `curl -s https://miavance.com/archivo | md5 -q` — confirma byte a byte que prod = local. Ojo: `.htaccess` NO se puede comparar así (Apache lo bloquea con 403, que es lo correcto); el "diff" que da es la página de error.
- **Re-verificación 2026-07-10 (noche):** ambos deploys sanos — CRM en vivo sirve los hashes exactos del build local, portal con SW v93 y 6 archivos clave idénticos por md5, ZIPs 404 en ambos dominios, `.htaccess` 403.
- El primer deploy por esta vía fue el **2026-06-10** (SW v89: mejoras de contratos/analista/pagos/dashboard/inversión + crono-timeline). Funcionó completo: 107 archivos, verificado en vivo.
- El flujo manual viejo (File Manager / FTP) sigue documentado en `public_html/CLAUDE.md` §14 como respaldo.
- Siempre **bumpear `CACHE_VERSION`** en `service-worker.js` antes de desplegar para que el SW limpie el caché de los clientes (ver [[Arquitectura del portal]]).
