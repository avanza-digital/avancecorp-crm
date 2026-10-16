# Publicación: ventas propias de supervisores

**PUBLICADO Y VERIFICADO el 16/10/2026**, 16:48 UTC / 11:48 Lima,
en [crm.miavance.com](https://crm.miavance.com).
Desde octubre de 2026, las ventas propias conservan su atribución al supervisor
y aportan a su equipo. Supervisión aparece después de todos los analistas.

## Fuente, autorización y paquete

Miguel autorizó la publicación, la copia aislada, la rama temporal de pago y la
excepción de administrador para integrar después de todos los controles.
[PR #307](https://github.com/avanza-digital/avancecorp-crm/pull/307) integrado con
`preflight`, `verify` y `app-check` PASS, sin modificar reglas de protección.

- Commit publicado: `3a0fa7075296149fa45c646cbb48beca3fbdbe41`.
- HEAD, main local y `avancecorp/main` idénticos al construir y antes de subir.
- Árbol completo idéntico a `cab50cdc8369c58086867958aa70ea2f96d9431d`, candidato probado. Copia limpia.
- ZIP: `releases/crm-20261016T164623Z-3a0fa7075296.zip`.
- SHA-256: `230c099c69121d3954d1800d0934f3f4fd1989ef13a4cb24eefa7dc2872ef457`.
- Manifiesto: `releases/crm-20261016T164623Z-3a0fa7075296.manifest.json`.
- Build servido: `build-20261016T164622488Z`.
- Preflight PASS contra el vivo anterior `94ef6886b50d` / `build-20261016T023049819Z`.

`npm run release:crm` y `release:crm:verify` PASS. Publicación mediante el MCP de
Hostinger, operación real `hosting_deploy-static-website`, dominio y ZIP exactos.
Se conservó el ZIP anterior `crm-20261016T023050Z-94ef6886b50d.zip`, SHA-256
`ee4c53b5783645ea764a710eefab563770a5c94a0729e75c1eabff7520b557f9` y su manifiesto.
Esta acta posterior no cambia el commit que originó el paquete ni exige republicar.

## Backend y pruebas

Migración `20261016162937_crm_supervisores_ventas_equipo.sql`, promovida por
`merge_branch`, después del banco SQL/Auth y advisors. Producción terminó
`FUNCTIONS_DEPLOYED / ACTIVE_HEALTHY`.

Las 1.110 funciones coinciden con el banco en definición, propietario y ACL;
solo `crm.cumplimiento_metas_fn(date)` difiere del estado productivo previo.
Su MD5 de cuerpo es `b1b3661f98745096d4a7d584981b19a2`. Las 23 Edge Functions
conservan versión, SHA-256, JWT, import map y estado. Los 484 registros históricos
de migración permanecen iguales. El nuevo registro contiene cinco sentencias:
su contenido coincide exactamente con el archivo al reponer los delimitadores
que el promotor separa; no se exige igualdad binaria de la serialización.

| Comprobación | Resultado |
| --- | --- |
| SQL local y cloud | PASS, 59 aserciones en cada entorno |
| Auth/PostgREST cloud | PASS, 37 aserciones y JWT humanos reales |
| Frontend completo | PASS, 6.984 tests; lint, tipos, cobertura, build y bundle |
| E2E Docker local completo | PASS, 438 passed / 26 skipped / 0 failed |
| Lecturas productivas antes/después | PASS, 14; roles activos, septiembre y octubre |
| Ventas propias de los cuatro supervisores | PASS, aislamiento y coincidencia con Gerencia; tres con actividad y uno sin ella |
| Datos de negocio | PASS, huellas idénticas de 820 contratos, 165 operaciones y un sello |
| Advisors productivos | PASS, seguridad 381 → 381, rendimiento 192 → 192, cero nuevos |
| Rama temporal | ELIMINADA; ausencia confirmada, otras ramas conservadas |

No se crearon datos de negocio en producción para comprobar la publicación.
El ensayo cloud sí utilizó identidades y contratos ficticios. Los límites del
replay, del escritor de cierre y de las pruebas están en [VERIFICACION.md](VERIFICACION.md).
Claude y JEV participaron según la adjudicación documentada allí.

## Comprobación del sitio publicado

Smoke Chromium en Docker: **PASS**, portada HTTP 200, formulario de acceso
visible y habilitado, build esperado y cero errores JavaScript. [Evidencia](produccion/smoke-web.json).

Se descargaron 161 archivos públicos: **149 coinciden byte a byte** con el
manifiesto, incluidos todos los JS/CSS, HTML y versión. `.htaccess` no se solicita
por HTTP. Los 12 PNG restantes no cambiaron en el ZIP respecto al release anterior:
siete conservan todos sus píxeles RGBA y cinco logos de 3508 × 3253 se sirven a
1600 × 1484. La comparación binaria completa devuelve FAIL para esos 12 PNG;
se conserva ese resultado, sin atribuirles una igualdad de bytes que no tienen.

Las respuestas incluyen `server: hcdn` y `x-hcdn-request-id`. Inferencia: las
diferencias corresponden a la optimización de imágenes de la capa de entrega,
compatible con la [documentación de Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/).
No se modificaron imágenes ni la configuración CDN para esta publicación.
[Comprobaciones HTTP](produccion/assets-http.json) y
[comparación de imágenes](produccion/imagenes-publicadas.json).
