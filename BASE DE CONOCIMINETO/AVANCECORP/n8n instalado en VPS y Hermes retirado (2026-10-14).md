# n8n instalado en VPS y Hermes retirado

**Actualización del 14/10:** Google Sheets y el importador ya están autenticados; el flujo está construido y probado, todavía inactivo a la espera de la campaña visible en el CRM. Ver [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]]. El estado pendiente de esta nota corresponde al cierre de la instalación inicial.

El 14 de octubre de 2026, Miguel eligió n8n en su VPS para llevar al CRM los leads después del filtrado de la empresa. La fuente es la hoja `1Hb0M75zErSydv8j6AQqV0ka-E9Uw_CpW0QWT_X4jVws`, pestaña `gid=0`. Miguel se encarga de habilitar el acceso; la cuenta `miguel@miavance.com` mostró «Necesitas acceso» al revisarla.

## Instalación

- VPS Hostinger `srv1906432.hstgr.cloud`, IP `2.25.109.128`, Ubuntu 24.04.4, plan KVM 2.
- Acceso utilizado: consola web del panel. SSH como root rechazó el acceso automático; no se añadieron claves ni se cambiaron contraseñas del VPS.
- Hermes: proyecto Docker `hermes-agent-2gun`, eliminado desde Hostinger con confirmación explícita de Miguel. No se crearon copias. Se verificó que su contenedor y `/docker/hermes-agent-2gun` ya no existen.
- n8n: proyecto `n8n-t27j`, contenedor `n8n-t27j-n8n-1`, imagen `docker.n8n.io/n8nio/n8n:2.43.5`.
- Dirección: https://n8n-t27j.srv1906432.hstgr.cloud/
- Archivo del VPS: `/docker/n8n-t27j/docker-compose.yml`. Está guardado como JSON válido para Docker Compose. Se conserva el volumen de datos montado en `/home/node/.n8n`.
- El Traefik existente permanece en red de host. n8n publica únicamente `127.0.0.1:5678:5678`, con reinicio `unless-stopped`.

## Ajustes aplicados

La plantilla del catálogo traía imagen sin versión, puerto en todas las interfaces y `N8N_SECURE_COOKIE=false`. Se fijó la versión estable 2.43.5 y se ajustaron:

- `TZ` y `GENERIC_TIMEZONE`: `America/Lima`.
- `N8N_SECURE_COOKIE=true`, `N8N_PROXY_HOPS=1`, `N8N_PROTOCOL=https`.
- `N8N_HOST=n8n-t27j.srv1906432.hstgr.cloud`.
- `N8N_EDITOR_BASE_URL` y `N8N_WEBHOOK_URL`: la dirección HTTPS pública.
- Se retiró `WEBHOOK_URL`: la [documentación vigente de n8n](https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/configuration-examples/configure-webhook-urls-with-reverse-proxy.md) indica su reemplazo por `N8N_WEBHOOK_URL` desde 2.35.0.

Después de actualizar o volver a desplegar desde Hostinger, revisar que conserve estos ajustes.

## Comprobaciones al cerrar la instalación (estado histórico)

PASS: Compose valida; contenedor ejecutándose con la imagen fijada; configuración efectiva y puerto limitado a localhost verificados; `/healthz` y `/healthz/readiness` públicos responden `{"status":"ok"}` por HTTPS; la conexión externa al puerto 5678 no respondió; la pantalla de creación de propietario abre por HTTPS.

Pendiente: Miguel debe crear personalmente la cuenta administradora en `/setup`. Antes de añadir credenciales, confirmar que pertenece a Miguel. La integración Google Sheets → CRM aún no está construida ni activada; faltan acceso a la hoja, inspección de columnas y credenciales de Google y del importador.

La revisión independiente de Claude se recibió como CHANGES_REQUESTED. La exposición HTTP se corrigió y el acceso HTTPS se comprobó después de recrear n8n. La objeción al nombre `N8N_WEBHOOK_URL` se descartó con la documentación oficial actual. La conservación y recuperación del volumen de n8n debe definirse antes de agregar credenciales; la orden de no copiar datos correspondía a Hermes.

Relacionado: [[Carga de leads desde hoja de Google]] · [[Canales de origen de leads CRM]] · [[Deploy a Hostinger]].
