---
tags: [crm, incidente, rendimiento, tasas, auditoria]
actualizado: 2026-10-20
---

# CRM — bucle de tasas de Coordinación y errores del servidor (2026-10-19)

**CORRECCIÓN PUBLICADA Y VERIFICADA el 20/10/2026 a las 00:33 Lima.** Miguel pidió analizar los errores, revisar los loops y contrastar con Claude; después autorizó aplicar la solución y expresamente integrar y publicar con permiso administrativo ante la exigencia de aprobación externa de GitHub. PR #344 integrada; no se cambiaron las reglas de protección.

**Decisión de negocio confirmada por Miguel:** Coordinación no debe ver el apartado de condiciones ni solicitudes de tasa, tampoco en modo de solo lectura. Respondió «no debe ver eso» al consultar ese alcance. La corrección publicada impide tanto el montaje del panel como sus consultas para Coordinación, además de romper el bucle de reintentos. Se mantiene la lectura de los cuatro roles autorizados sin ampliar permisos de servidor.

Ventana: 19/10/2026 00:00–23:29 Lima. Supabase registró 1.757 HTTP 403 de `solicitudes_tasa_lead_fn` desde una sola sesión de Coordinación entre 12:08 y 12:33, máximo 153/min; 86,3 % de los 2.036 errores HTTP con origen CRM. PostgreSQL registró por separado 2.089 «No autorizado» en `private.solicitudes_tasa_impl`; no sumar ambas fuentes.

**Causa reproducida:** la ficha monta el panel de tasa sin capacidad de lectura. El servidor rechaza correctamente. En modo `observacion`, padre e hijo consultan la misma clave; error → montar hijo → retryOnMount → pendiente → desmontar hijo → error. `retry:false` global no evita ese reintento. Prueba sobre Main `a980bb719bdefa8939f8ff4fe205395edc62c4d7`: 12 llamadas en 299 ms. Controles `retryOnMount:false` y enforcement: una llamada cada uno. Tres pruebas diagnósticas PASS; sin llamadas ni escrituras productivas desde la prueba.

**Estado previo a corregir:** cadena relevante idéntica desde `6479402d`; lockfile exacto React 19.2.7 / TanStack 5.101.2. Portada y cinco JS publicados idénticos al ZIP/manifiesto de `a980bb71`, build `build-20261020T035759531Z`. No hubo nuevos 403 de ese patrón tras 12:33 en la ventana; eso no demuestra que esté arreglado.

**Solución contrastada con Claude e implementada:** estabilizar padre/hijo y acotar `retryOnMount:false` a la consulta; comprobar capacidad de lectura antes de montar/consultar; 403 estable sin polling indefinido; preservar lectura de Directorio y operación de roles autorizados. No ampliar permisos ni cambiar políticas de tasas. Corrección frontend focalizada, consultas reales con respuestas simuladas y roles, E2E Docker local y release autorizado con comprobación de versión y hashes HTTP. Los rechazos de permiso detienen las consultas automáticas; los errores transitorios conservan la recuperación y el borrador. Se conserva el código original PGRST301 para que un JWT vencido no se inmovilice como un 403; retryOnMount se limita al contexto de lead.

En la revisión del diagnóstico, Claude entregó `CHANGES_REQUESTED`, confianza alta en causa/solución. Pidió completar evidencia de versión y cadena; Codex la completó mediante comparación de fragmentos, lockfile resuelto y hashes HTTP. Dos intentos previos sin dictamen válido, sin eludir el wrapper ni cambiar configuración. Codex rechazó como solución completa dejar reintentándose un 403 cada minuto.

Otros hallazgos separados: 123 POST 404 de recorrido hasta 09:39, compatibles con desfase de publicación; validaciones de conversión `P0409` clasificadas HTTP 500 (corregir contrato aparte); 14 respuestas 502 de tipo de cambio con causa pendiente; cron `notificar-pagos` 09:00 y `ciclo-contratos` 09:10 devolvieron HTTP 401 desde pg_net aunque la fase SQL figura exitosa. No declarar cron sano de punta a punta. Tres errores de pool fueron contraseña de `cli_login_postgres`.

Foto de base 23:29: ACTIVE_HEALTHY, 26/120 conexiones, sin esperas por bloqueo, PostgreSQL iniciado el 14/10. Sin series históricas CPU/RAM ni logs de Hostinger. No acredita salud durante todo el día.

La revisión de implementación de Claude también entregó `CHANGES_REQUESTED`; se corrigieron sus hallazgos de distinción JWT/permiso y recuperación de bandejas, y se reforzaron las pruebas. No hubo una tercera consulta ni se le atribuye un PASS posterior.

**Fuente publicada:** Main local = `avancecorp/main` = `1a7c8d8ad7db35bf6a54ad408b52e73b53a12f7b`; árbol idéntico al commit probado `7eee8f6c`. Build `build-20261020T053148110Z`. Artefacto `crm-20261020T053148Z-1a7c8d8ad7db.zip`, SHA-256 `ea0965e76be2aded95d96b211891de8040fcc3d2d19b7791ad14f18cdecce84b`. Se conserva en `CRM-Avance-Corp/releases/` junto al manifiesto y al paquete anterior `crm-20261020T035800Z-a980bb719bde.zip`.

**Verificación:** npm run check PASS (464 archivos / 7.479 pruebas), focales 105/105, E2E Docker local 21/21, checks GitHub PASS. Fuente limpia, artefacto y preflight PASS. Hostinger aceptó el despliegue; 129/129 archivos (portada, versión y todos los JS/CSS) HTTP 200 y hashes idénticos. Gate administrativo completo de realidad NOT RUN por HTTP 401 de la credencial local; sesión personal productiva y VoiceOver NOT RUN. La prueba 401→200 comprueba recuperación de la consulta, no el intercambio completo de renovación real del token. No se tocaron datos, permisos de servidor, SQL ni configuración.

**Operación:** recargar las pestañas abiertas para usar la corrección. No se afirma que desaparecieron los demás errores de cron/tipo de cambio/conversión ni se sustituye la monitorización de un día productivo. En observación, recuperar un error transitorio puede esperar hasta 60 segundos; enforcement conserva el reintento explícito.

Informe y evidencia: `CRM-Avance-Corp/docs/auditorias/servidor-loops-2026-10-19/INFORME.md`. Implementación: `CORRECCION.md`. Estado definitivo, autorización, revisión automática y despliegue: `PUBLICACION.md`; hashes en `correccion-publicada-http.json`.

Relacionadas: [[Interruptor integral de rentabilidad - preparado 2026-09-18]] · [[Conversion - exigencia activa en produccion (2026-10-19)]] · [[Conversion - ficha compacta publicada (2026-10-19)]].


## Limpieza de la sesión — 20/10/2026

Miguel pidió retirar lo que ya no hacía falta después de publicar. Se eliminaron 29 entradas temporales (1.181 archivos, 15.225.779 bytes) de análisis, reproducción, revisión, pruebas y herramientas auxiliares. Se retiró la rama remota `crm/corregir-bucle-tasas-20261020`, cuya PR #344 ya estaba integrada, y su referencia local de seguimiento.

Se conservaron código, pruebas, actas, revisiones finales, evidencia HTTP y los ZIP/manifiestos publicado y anterior, con sus hashes comprobados. El control negativo quedó conservado en `control-sin-parche.log`. Ningún worktree, dependencia compartida, contenedor o dato de negocio fue eliminado. La copia existente de Main recibió durante la revisión el cambio de otra tarea `c7c150f3` (descendiente del arreglo); por ello se conservó íntegra, incluidas sus salidas de trabajo compartidas. La limpieza no implicó otro despliegue.

Detalle de lo retirado: `CRM-Avance-Corp/docs/auditorias/servidor-loops-2026-10-19/LIMPIEZA.json`. Los errores separados de cron, tipo de cambio y clasificación de conversiones siguen pendientes.
