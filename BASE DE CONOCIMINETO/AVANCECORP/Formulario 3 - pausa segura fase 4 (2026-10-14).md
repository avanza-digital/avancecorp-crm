# Formulario 3 — pausa segura de fase 4

Pausa solicitada expresamente por Miguel el 14/10/2026. **No reanudar, fusionar ni publicar hasta que Miguel lo indique.**

## Estado guardado

- CRM de producción sin cambios de esta fase: no se aplicó SQL, no se desplegó Edge ni frontend. Última versión viva comprobada `build-20261014T031546721Z`, commit `e791502ff6961a9ef71b434bdb50a1748e744331`.
- Código y evidencia en [PR 280](https://github.com/avanza-digital/avancecorp-crm/pull/280), rama `feat/formulario3-campania-20261014`, commit `6beebac957286eebd6512cf12a9e178e96bb1c37`. PR abierta, sin auto-merge. GitHub rechazó el push directo por reglas; se respetó la vía PR. Preflight aprobado; app-check seguía ejecutándose al pausar. Sus controles no despliegan nada.
- Clon de trabajo: `/private/tmp/formulario3-fase4-publicacion`. Main local contiene el candidato; remoto seguía en `2cf798a2ff6df438afeac86eea842436153c3eee`. NO construir release hasta fusionar PR y volver a igualar Main/remoto. El árbol original con trabajo ajeno se conservó.
- Pruebas PASS: 420 archivos / 6707 tests, lint/tipos/build, scripts/preflights, 3 E2E Docker Formulario 3, 25 tests n8n, 6 del gate SQL; 98 SQL y 18 HTTP/Auth en rama. ZIP anterior contra esquema nuevo: 2 E2E reales Vendedor/Gerencia aprobados. Claude revisó y sus observaciones se resolvieron con evidencia en fase4/revision-resolucion.md. Dos advertencias históricas del gate siguen documentadas; no se alteraron datos comerciales para ocultarlas.
- Rama temporal `formulario3-fase4-20261014`, ref `oemmpccapplmiygcpvxr`, ID `e21928a2-725f-4f9a-aeaa-f749a0c69185`: **eliminada**, ausencia confirmada por list_branches. El intento inicial vacío también estaba eliminado. No queda una rama de esta tarea cobrando por hora. No se tocaron banco-f7 ni plan-backend-fase4.
- Credenciales locales de esa rama retiradas. No reutilizar sus referencias ni intentar fusionarla: ya no existe. Los scripts de ensayo con esa ref son evidencia histórica, no un entorno activo.
- n8n principal `BjI5m1PKVWhO0NDb`, versión `29940eb5-d36c-49c7-bf7f-686b66cc3f76`: active=false, activeVersionId=null, enviar_crm=false e Importar en CRM deshabilitado. Credencial original conservada. Aviso por Gmail probado con ejecución 52; no se cargaron filas reales.
- Figma actualizado a EN PAUSA: https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34.

## Al reanudar

1. Leer este punto y la evidencia `CRM-Avance-Corp/supabase/scripts/formulario3-fase4/` del commit/PR. Consultar estado final de los controles de PR 280, resolver fallos si aparecen y fusionar por la vía normal, sin --admin ni push forzado. Fetch e integración limpia en Main.
2. Revalidar las siete huellas SQL vivas y el historial (476 previas, hash `353c7845bdb37b3440aae5956eb20e03` al último control). Publicar solo `20261014210146_crm_formulario3_campania_origen.sql` y `20261014215453_crm_formulario3_cartera.sql` con versiones exactas; el workspace aislado `/private/tmp/formulario3-fase4-migraciones` conserva el historial remoto y esas dos. Revisar destino y dry-run antes de cualquier escritura. No hacer db push general desde el repositorio con diferencias históricas. Si se necesita otra rama de pago, requiere autorización específica; no recrearla durante la pausa.
3. Verificar columna, ACL, firma única de 15 argumentos y caché PostgREST; después publicar únicamente crm-importar-leads con verify_jwt=true; finalmente frontend. Las 44 huellas de código de fases anteriores siguen iguales.
4. Usar release-crm: build limpio desde Main igual a avancecorp/main, verificar manifiesto y preflight obligatorio. Conector registrado hostinger-hosting, operación hosting_deploy-static-website; bridge preparado en `/private/tmp/formulario3-fase4/hostinger-deploy.mjs`, sin ejecutarse. No cambiar configuración MCP ni buscar tokens. Scripts http-produccion.mjs y verificar-publicacion.mjs están preparados, aún no ejecutados. Conservar ZIP anterior como recuperación, no desplegarlo automáticamente.
5. Actualizar ledger, acta, vault y Figma con estado real. Fase 5 será una sola fila real, con cron apagado; fase 6 carga supervisada y activación. Antes de primera fila, verificar poda de errores del VPS (política 7 días) o desactivar almacenamiento del contenido fallido; no se da por configurada.

Relacionado: [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]] · [[Formulario 3 - fase 3 integrada y validada sin publicar (2026-10-14)]].
