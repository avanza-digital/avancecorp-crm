---
fecha: 2026-10-19
tags: [crm, leads, release, hostinger]
estado: frontend publicado; backend del recorrido pendiente
---

# Recorrido del lead · frontend publicado

Miguel invocó `$release-crm` después de integrar el PR #331. Se publicó únicamente el frontend en https://crm.miavance.com mediante el conector oficial Hostinger de la sesión existente, sin cambiar configuración ni credenciales.

- Fuente: Main local = avancecorp/main `3797e6affbed6e97d7ceae00ce0bdc01ae4f2248`, limpio al construir/subir. Árbol idéntico al commit revisado `04d284fd`; gate de 7.316 tests y siete E2E finales reutilizado con esa evidencia.
- Build servido: `recorrido-3797e6affbed-20261019T050539Z`.
- ZIP efectivamente publicado: `crm-20261019T050553Z-3797e6affbed.zip`.
- SHA-256: `5b1be05038c3cf444d962d9fe5ec88793dbc5c9bdde0218ac3bfd3bf3b4b96f4`.
- ZIP y manifiesto conservados en `CRM-Avance-Corp/releases/`; entrega con evidencia en `/Users/usuario/Downloads/CRM-publicacion-20261019-recorrido/`.

## Verificación

Build, manifiesto y preflight PASS. Portada/versión HTTP 200 y hash de índice correcto; 128 JS/CSS idénticos. Del total de 167 archivos, 154 coinciden al byte, doce PNG son transformados por hcdn y `.htaccess` permanece protegido con 403. Los cinco PNG grandes se sirven a 1600×1484 conservando proporción; imágenes fuente iguales al release anterior. Diagnóstico conservado; sin nueva publicación ni purga para forzar una coincidencia falsa.

Acceso sin sesión en escritorio y móvil PASS con Chromium headless en Docker local: Correo/Contraseña visibles, Entrar habilitado, sin errores runtime ni desborde. ZIP público 404 en CRM y portal. No se enviaron credenciales ni se crearon/eliminaron datos reales.

## Límite comercial vigente

**El frontend publicado todavía no impide convertir leads sin cita/entrevista.** Una lectura de producción confirmó `recorrido_control` ausente, RPC evaluadora ausente y cero de las ocho migraciones nuevas aplicadas. La guía permanece oculta ante `PGRST202`, según el contrato de instalación gradual probado.

Faltan autorización e instalación del backend por su circuito de rama/RLS/advisors, política comercial de antiguos y activación de exigencia. `$release-crm` no autorizó SQL ni cambios de modo. No se modificó n8n ni el portal.

Rollback conservado: `crm-20261018T231940Z-6ace3d441bd8.zip`, SHA-256 `d86eee8f9a799ff93b5d6bc6a5cceeb4fef92cba67351d2b524b2060d1ab906d`. No saltar el preflight para recuperarlo: Miguel decide si hace falta.

Acta completa: `/Users/usuario/Downloads/CRM-publicacion-20261019-recorrido/ACTA-PUBLICACION.md`.

Relacionado: [[Recorrido del lead por asistencia y entrevista - preparado 2026-10-18]] · [[Hostinger - publicar con la sesion de VS Code]] · [[Deploy a Hostinger]] · [[Inicio]].
