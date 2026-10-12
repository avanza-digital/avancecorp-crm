# Llamadas desde el celular — PR 232 H-WA publicado (09/10/2026)

Miguel autorizó aprobar, fusionar y publicar el PR #232: «oko vmaos hgamos todo», después de recibir el análisis y la recomendación. Se usó el flujo de release-crm desde la copia limpia `/private/tmp/avancecorp-pr190-correcciones-20261006`. El checkout compartido conserva el trabajo ajeno sin confirmar; solo se añadieron copias de los artefactos ignorados en `CRM-Avance-Corp/releases/`.

## Publicación efectiva

- PR: https://github.com/avanza-digital/avancecorp-crm/pull/232
- Cabeza revisada: `f52dbe6afbb836a4821d89a7a066fade73e3ed9d`.
- Aprobación: `5473743209`. Fusión normal, sin bypass, 09/10/2026 13:12:09 Lima.
- Commit publicado: `a078465986e54adf9a4be8f50a1b8893e98b68d9`.
- Árbol fusionado idéntico al revisado; main limpio igual a avancecorp/main antes de construir y reconfirmado antes de subir.
- Sitio: https://crm.miavance.com
- Build servido: `build-20261009T181538004Z`.
- Release: `crm-20261009T181538Z-a078465986e5`.
- ZIP SHA-256: `458c2657a674bd661b5ab800f7ccf2fe4318b695a5634c89ee205c2943946f37`.
- Recuperación conservada: último publicado `crm-20261009T153723Z-0f619b024be9`, SHA-256 `bdcdf60b77a16799ac803157529539fd7a362e1b14e90dd884001fb417dc5863`. Su restauración sigue las reglas de preflight/rollback del proyecto.

## Verificación

- PASS CI exacto del árbol revisado: 6470/6470 tests, 399 archivos, lint, typecheck, cobertura, build, bundle y duplicación. Run `37969372131`, app-check `113951840854`.
- PASS propio antes de fusionar: componente analista 91/91; E2E Docker local 11/11 en 24,1 s, sin reintentos reportados.
- PASS release:crm, release:crm:verify y preflight. Primer intento rechazado por falta de variables VITE en la copia limpia; se reconstruyó tomando únicamente URL y llave pública anon de la configuración productiva, sin imprimirlas. Ese primer intento no se publicó.
- Hostinger aceptó subida y despliegue del ZIP; después se comprobó version.json y el contenido servido.
- PASS postflight: 156 archivos públicos accesibles, 144 idénticos al manifiesto. Los 12 PNG transformados por CDN son idénticos en bytes a los servidos en el release previo y no cambió su fuente. `.htaccess` no se consulta públicamente.
- PASS acceso real Gerencia y Gestión Diaria; script principal `index-D1sTkPuO.js`, sin errores de consola. Aviso inicial de indicadores incompletos en Hoy y warning `[ac-crm] Object`; el aviso desapareció al volver a Hoy. Causa no determinada, sin fallo persistente observado.
- NOT RUN aceptación física H-WA en C1: corresponde a Jhosep.

## Coordinación y pendientes

Comentario consolidado enviado a @jhosepv96:
https://github.com/avanza-digital/avancecorp-crm/pull/232#issuecomment-6086733132

Jhosep debe recargar el frontend y probar un lead propio de prueba cuya fila tenga WhatsApp pendiente: llamar desde C1, registrar «No contestó» sin perder/descartar el lead y confirmar que la encuesta no ofrece cerrar WhatsApp, guarda la llamada y mantiene pendiente WhatsApp. Si hay otra tarea de llamada, tampoco debe cerrarla por sustitución. Registrar hora Lima, build y resultado/captura saneada. No repetir P1–P15.

H-WA corregido, fusionado y publicado; todavía no cerrado por falta de la aceptación física. El plan permanece 44/102, 2/8 según el último tablero versionado; no se marcaron casillas por una aceptación aún no realizada. H-P5/H-P10, piloto y fases restantes conservan su seguimiento. Jev apagado. No se aplicaron SQL ni Edge en esta publicación.

Evidencia local: `/private/tmp/pr232-review-20261009/` (REVISION.md, e2e.log, release.log, postflight-web.json, postflight-png.json y comentario-publicacion.md). Paquete y manifiesto en `CRM-Avance-Corp/releases/` de ambas copias.

Relacionadas: [[Llamadas desde el celular - revision PR 232 H-WA (2026-10-09)]], [[Llamadas desde el celular - segunda revision PR 231 (2026-10-09)]], [[Llamadas desde el celular - P9 publicado y consulta de C1 (2026-10-09)]], [[Inicio]].
