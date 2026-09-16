# Lead propio del supervisor

Miguel autorizó el 2026-09-16 permitir al supervisor crear y convertir sus
propios leads. En **Nuevo lead → Responsable comercial** aparece
**Yo — lead propio**. Debe seleccionarlo explícitamente; Sin asignar continúa
siendo la bandeja de reparto, y se mantienen los analistas de su equipo.

El responsable es `vendedor_id`, no el autor `creado_por`. La sesión proporciona
el id propio aunque el supervisor no tenga analistas a cargo. La ficha muestra
su nombre y permite convertir con la capacidad contractual vigente. El cliente,
contrato y Cartera conservan esa responsabilidad. No se amplía la toma de leads
existentes ni el origen Referido, que sigue reservado al analista.

No hizo falta cambiar SQL ni Edge: el servidor ya autorizaba esta propiedad.
La producción del supervisor se conserva en el total de capital y en el bloque
de Gerencia **Producción fuera del ranking**, sin puesto de analista. Un lead
manual de oficina mantiene aporte cero al KPI de conversión de leads recibidos.

Ver [[Produccion fuera del ranking (decision 2026-09-02)]] y
[[Deploy a Hostinger]]. Evidencia de verificación y alcance en
`CRM-Avance-Corp/supabase/scripts/supervisor-propio/README.md`.

Estado: **PUBLICADO Y VERIFICADO** el 2026-09-16.

## Publicación autorizada

Miguel indicó «ok publica». La [PR #2](https://github.com/avanza-digital/avancecorp-crm/pull/2)
quedó integrada en `avancecorp/main` como `1f9e5f83fa08c371b8e28ef502b89fdb4c135bfc`.
Main local y remoto coincidían antes del envío. Se construyó desde una copia
limpia de ese commit; el árbol es idéntico al `a427ad3f` validado después de
integrar la mejora de contratos de la PR #1.

- Sitio: https://crm.miavance.com/
- Artefacto: `crm-20260916T170732Z-1f9e5f83fa08.zip`.
- SHA-256: `6e37f4aa87db16982776e8b0d034534681bed2b13434c60af256ede541f90263`.
- Build servido: `build-20260916T170731814Z`.
- Hostinger `hosting_deployStaticWebsite`: carga y despliegue aceptados.
- Smoke **PASS**: 95 comprobaciones HTTP; recursos de código comparados por
  SHA-256, imágenes disponibles y `.htaccess` protegido. ZIP y licencia interna
  no accesibles. Portada y pantalla de acceso HTTP 200, cero errores JavaScript
  en un navegador sin sesión. No se creó ni convirtió ningún cliente real.
- GitHub **PASS**: `verify` (3641 pruebas), `e2e` (195; 26 omisiones previas) y
  `preflight`. Check local del árbol integrado también PASS. Banco propio SQL
  8 casos y Edge 32 pruebas ya documentados.
- Recuperación: `crm-20260916T165912Z-a0c47ebc1d4e.zip`, SHA-256
  `58aa3548076ae892d6a564720c87f36bc26bb88aa075e9a2224da9ddb0736534`.

La otra sesión publicó previamente los requisitos de eliminación de contratos.
Antes de este envío se comprobó por lectura: migración registrada como
`20260916170027_crm_eliminacion_auditada_inversion_sin_historial`, cuerpo SQL
`c0ae3e3167c82724b784d73b4f427868` y Edge `crm-contrato-pdf-v2` v20 con JWT,
paquete `e2251eec752da8f22d46e8b5d8f5e19ff77b336143a3225c554721c0b1e1036a`.
Esta tarea de supervisor no instaló SQL ni Edge.

Manifiesto y evidencia HTTP conservados en `CRM-Avance-Corp/releases/` con
el mismo nombre del artefacto (`.manifest.json` y `.smoke.json`). El registro
posterior de esta nota no cambia el commit que originó la publicación.

## Cierre de sesión

Miguel pidió guardar todo y cerrar la sesión. Función terminada y publicada;
no requiere otra instalación ni otro despliegue. Evidencias locales duraderas
en `_DEV_NO_SUBIR/cierre-supervisor-propio-20260916/`; ZIP y manifiesto en
`CRM-Avance-Corp/releases/`. El cierre documental se respalda en la rama
`docs/cierre-supervisor-propio-20260916`; el código publicado está en Main
y conserva el commit de origen indicado arriba.
