---
tags: [crm, hoy, supervisor, release, produccion]
actualizado: 2026-10-18
estado: publicado-con-smoke-publico-verificado
---

# Hoy supervisor - publicado y verificado (2026-10-18)

Miguel invocó `$release-crm`. Codex publicó el frontend en https://crm.miavance.com/ el 18/10/2026 a las 15:07 Lima mediante el conector Hostinger existente. La nueva versión quedó confirmada por HTTP; hubo un solo despliegue.

Fuente: Main limpio `2686f755fb600fee5c8c659a80cd15d043fa431a`, igual a `avancecorp/main` y al remoto antes de publicar. Build **`build-20261018T200426345Z`**. ZIP **`crm-20261018T200427Z-2686f755fb60.zip`**, 2.602.659 bytes; SHA-256 **`ea010b53c3a819f1e881c7fe451743816ae62251e7915b76b88a8cb782f97ca7`**. Los ZIP de las 18:41 y 19:35 UTC eran entregas preparadas; este es el publicado.

PASS: `npm run check` en CI sobre ese commit, build y verificador oficial, integridad de 166 archivos del ZIP y preflight contra el vivo anterior. QA del mismo árbol: 7.262 unitarios, 467 E2E en Docker con 26 SKIP y cero fallos, 19 comprobaciones de datos reales anonimizados y cuatro recorridos visuales. CodeRabbit sin comentarios accionables y Claude PASS. El PR #329 sigue siendo solo para revisión, no se fusionó.

Después de publicar: portada y versión correctas, 127/127 JS/CSS con hashes exactos y 165/165 archivos públicos HTTP 200. Acceso público en escritorio y móvil PASS, sin errores de JavaScript. **Recorrido autenticado productivo NOT RUN**, por falta de sesión; no confundirlo con las pruebas locales y la conciliación anterior.

La auditoría binaria de todos los archivos públicos conserva FAIL (153/165): doce PNG entregados por `hcdn` difieren del ZIP. Siete tienen píxeles idénticos; cinco logos se redimensionan de 3508×3253 a 1600×1484. Los doce originales son idénticos a los del release anterior y el patrón ya estaba registrado el 08/10; evidencia compatible con optimización del CDN. No se cambió su configuración ni se afirmó igualdad de píxeles de los cinco redimensionados. No afecta a la coincidencia verificada de JS/CSS.

Recuperación conservada: anterior publicado `crm-20261018T070707Z-f25942197d84.zip` y manifiesto, build `build-20261018T070707022Z`, SHA-256 `9fae31c00e6eb960cfb281993239bd2f91549bfb969b883c9c1d92ab219b7e80`. No se restauró. No se aplicó SQL/Edge ni se modificaron datos reales, credenciales, DNS o ajustes del proveedor. La migración 20261018053228 ya constaba aplicada en su acta.

Artefacto: `CRM-Avance-Corp/releases/crm-20261018T200427Z-2686f755fb60.zip`.
Acta y evidencia: `CRM-Avance-Corp/releases/hoy-supervisor-2026-10-18/publicacion-2026-10-18/PUBLICACION.md`, con manifiesto, hashes, solicitud/respuesta de Hostinger, smoke, capturas y copia de recuperación.

[[Hoy supervisor - QA previo al release y correccion de pendientes (2026-10-18)]] · [[Hoy supervisor - ZIP verificado sin publicar (2026-10-18)]] · [[Hoy supervisor - resultados diarios y plan por fases con Claude (2026-10-18)]] · [[Tope de referidos y publicar Facturación - RETOMAR (2026-10-08)]] · [[Reemplazar inversion - Fase 4 cooperativas construida (2026-10-18)]] · [[Inicio]]
