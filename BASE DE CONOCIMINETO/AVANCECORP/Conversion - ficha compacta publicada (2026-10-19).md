---
tags: [crm, conversion, interfaz, publicacion]
actualizado: 2026-10-19
---

# Conversión — ficha compacta publicada

**19/10/2026, verificación final 11:56 Lima: PUBLICADA en https://crm.miavance.com/.** Los PR #335 y #336 están fusionados. Fuente: Main limpio y sincronizado con `avancecorp/main`, commit `6479402d63b22b5c254aef65abad2e2666ad0ab5`. Versión servida: `ficha-compacta-6479402d-20261019`.

**Revalidación de `$release-crm`, 19/10 12:01 Lima:** fetch de Main sin commits nuevos; fuente limpia y Main local/remoto iguales. ZIP/manifiesto/SHA, portada, versión, JS principal y CSS servido: PASS, idénticos al artefacto publicado. Se reutiliza la evidencia integral del mismo código; no se reconstruyó ni se publicó de nuevo. Evidencia: `Downloads/CRM-ficha-compacta-publicada-20261019/REVALIDACION-RELEASE.json`.

La ficha «Antes de convertir a cliente» tiene menos relleno y separación. Se retiraron los dos párrafos solicitados y se oculta el subtítulo «Agendar una cita» cuando existe el botón para agendar. Se conservan las indicaciones necesarias, como «Asignar un analista», el anuncio accesible de actualización y el tamaño táctil del refresco también en equipos híbridos. El despliegue solo contiene el ajuste del componente y la adaptación de sus pruebas; no cambia los requisitos comerciales ni el backend.

## Artefacto y verificaciones

- ZIP publicado: `crm-20261019T164913Z-6479402d63b2.zip` y manifiesto del mismo nombre.
- SHA-256: `3768c25a8961f634d0650ccdbe5ebf1b12409dc243dcc94025f91b22bef37dbe`.
- Copia y acta: `/Users/usuario/Downloads/CRM-ficha-compacta-publicada-20261019/`. Otra copia del ZIP y manifiesto está en `CRM-Avance-Corp/releases/` del repositorio original.
- `npm run check`: PASS, 456 archivos y 7.316 pruebas, más lint, tipos, cobertura, configuración, build, bundle y duplicación. Main tiene el árbol completo idéntico al commit probado `17130503`.
- E2E Docker local: PASS, 7/7 (17,8 segundos). Ninguna prueba escribe en producción.
- Build de Main, manifiesto, SHA y preflight de compatibilidad con la versión viva: PASS. Hostinger confirmó subida y aceptación del despliegue; la versión servida se verificó por HTTP.
- HTTP: 167 archivos comprobados, portada y 128 JS/CSS idénticos al paquete; 154 archivos exactos, 12 imágenes transformadas por hcdn e idénticas a las servidas antes, `.htaccess` protegido (403). ZIP no accesible públicamente (404).
- El comprobador inicial marcó FAIL en cinco PNG por asumir dimensiones originales. Diagnóstico: hcdn ya los servía a 1600 × 1484 en la publicación anterior, y sus huellas servidas y fuente siguen iguales. Se conservan `http-smoke.json`, `diagnostico-imagenes.json` y `http-smoke-final.json` para distinguir el resultado inicial de la verificación complementaria. No se repitió el despliegue ni se purgó caché.
- CodeRabbit y comprobaciones de #336: SUCCESS. Sus dos correcciones funcionales de #335 quedaron integradas; ambos hilos resueltos. La revisión de #336 dejó solo una sugerencia opcional de aserciones de clases CSS en pruebas, sin fallo funcional reportado.
- Navegador manual, sesión real y VoiceOver: NOT RUN; trabajo local y HTTP según la preferencia de Miguel. `gate:realidad` completo: NOT RUN por falta de credenciales en la CLI; el modo productivo había sido contrastado por el conector (`exigir`, revisión 2). Este despliegue no modifica backend.

Recuperación conservada: `CRM-Avance-Corp/releases/crm-20261019T050553Z-3797e6affbed.zip` y manifiesto, SHA `5b1be05038c3cf444d962d9fe5ec88793dbc5c9bdde0218ac3bfd3bf3b4b96f4`. La candidata de revisión `71330d70` no es el paquete publicado.

Fuente aislada usada: `/private/tmp/hoy-supervisor-goal-20261018/candidato-main`. Evidencia operativa: `/private/tmp/ficha-conversion-compacta-20261019/`; copia duradera del acta, manifiesto y verificaciones en la carpeta de Descargas indicada.

Esta publicación no cerró por sí misma la aceptación comercial del plan. En una validación posterior del 19/10 a las 12:14 Lima se acreditó **8.2** con dos conversiones productivas y pruebas de servidor en Docker; ver [[Conversion - primeras conversiones reales validadas (2026-10-19)]]. A las 15:30 se documentó la conformidad de Miguel para **8.6**: plan al **100 %** y recursos temporales retirados, según [[Conversion - cierre y limpieza de sesion (2026-10-19)]]. No hubo un nuevo despliegue por esa validación o cierre.

Relacionadas: [[Conversion - ficha compacta preparada PR 335 (2026-10-19)]] · [[Conversion - exigencia activa en produccion (2026-10-19)]] · [[GitHub - checks ajenos retirados del CRM (2026-10-19)]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
