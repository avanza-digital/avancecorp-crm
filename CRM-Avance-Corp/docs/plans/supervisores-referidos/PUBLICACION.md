# Publicación: referidos propios de supervisores

**PUBLICADO Y VERIFICADO el 16/10/2026**, 18:51 UTC / 13:51 Lima,
en [crm.miavance.com](https://crm.miavance.com).

Supervisión puede registrar un lead con origen Referido. Al crearlo, queda a
cargo del supervisor que lo registra. El formulario fija su nombre como
responsable y la RPC rechaza cualquier responsable ajeno. Para verlo en una
sesión abierta antes de la publicación, actualizar el CRM.

## Fuente y paquete

[PR #309](https://github.com/avanza-digital/avancecorp-crm/pull/309), integrado
con `preflight`, `app-check`, `cambios` y `verify` PASS. Se usó la excepción de
administrador autorizada por Miguel, después de todos los controles, sin cambiar
la protección del repositorio. Se mantuvieron sus autorizaciones previas de
publicación, copia aislada y rama Supabase temporal con eliminación al terminar.

- Commit publicado: `0d6aa930fe3bba7aa2bb64b9ff2d2c642b2e6e87`.
- HEAD, main local y `avancecorp/main` coincidían al construir y antes de subir.
- Árbol idéntico al candidato verificado `3f27b1086d3a5d60a0ac8de70d8ce1f2e33430e4`; copia limpia.
- ZIP: `releases/crm-20261016T184742Z-0d6aa930fe3b.zip`.
- SHA-256: `595bc1deeb84014b7813699b761e3346f34fdb317dd395dba2ff5f5f8c1d79be`.
- Manifiesto: `releases/crm-20261016T184742Z-0d6aa930fe3b.manifest.json`.
- Build servido: `build-20261016T184742062Z`.

`release:crm`, `release:crm:verify` y preflight PASS contra el vivo anterior
`3a0fa7075296` / `build-20261016T164622488Z`. Publicación por el MCP oficial de
Hostinger, operación `hosting_deploy-static-website`, con dominio y ZIP exactos.
Se conservan el ZIP y manifiesto anteriores: `crm-20261016T164623Z-3a0fa7075296`,
SHA-256 `230c099c69121d3954d1800d0934f3f4fd1989ef13a4cb24eefa7dc2872ef457`.
Esta acta posterior no cambia el commit del paquete ni requiere republicar.

## Backend y verificación

Primero se promovió la migración
`20261016183308_crm_supervisores_referidos_propios.sql` por `merge_branch`;
después se publicó el frontend. Producción quedó
`FUNCTIONS_DEPLOYED / ACTIVE_HEALTHY`.

Las 1110 funciones coinciden con el banco validado; solo cambia
`crm.crear_lead_si_disponible(...)` frente al baseline productivo. Su MD5 de cuerpo
es `145b30a30e69807a1838c1b960a0675d`. Owner y ACL intactos. Los 485 registros
anteriores de migración permanecen idénticos. El nuevo registro tiene cuatro
sentencias: al reponer sus delimitadores, el SQL coincide exactamente con el
archivo probado. Las 23 Edge Functions conservan toda su metadata, versión,
SHA-256 y verify_jwt. [Cotejo de catálogo](produccion/catalogo.json).

| Comprobación | Resultado |
|---|---|
| Frontend completo | PASS, 6994 tests y gates estáticos/build |
| E2E local Docker completo | PASS, 439 passed / 26 skipped / 0 failed |
| SQL local y rama Supabase | PASS, 67 aserciones en cada entorno |
| Auth/PostgREST en rama | PASS, 28 comprobaciones, 11 JWT reales |
| Smoke SQL productivo, transacción de solo lectura | PASS, 6 comprobaciones |
| Advisors productivos | Seguridad 381 → 381, rendimiento 192 → 192; cero nuevos |
| Rama temporal | ELIMINADA; ausencia confirmada y otras ramas conservadas |

La prueba SQL productiva comprueba huella y denegaciones para Supervisor,
Analista, Gerencia y anónimo. El alta positiva se probó en la rama con datos
sintéticos. No se crearon datos de negocio ni identidades de prueba en producción.
[Smoke SQL](produccion/smoke-sql.log), [consulta](produccion/smoke-sql.sql),
[advisors y limpieza](produccion/advisors-y-limpieza.json).

La revisión de Claude, adjudicación de hallazgos, contexto JEV y límites del banco
están en [VERIFICACION.md](VERIFICACION.md). Los consumidores de Referido y las
pruebas de conversión/capital están en [CONSUMIDORES.md](CONSUMIDORES.md).

## Sitio servido

Chromium en Docker: **PASS**, portada HTTP 200, login visible y habilitado,
build esperado y cero errores JavaScript. [Smoke web](produccion/smoke-web.json).
El primer intento del contenedor falló al montar un archivo nuevo sobre una
carpeta de solo lectura; se corrigió el montaje aislado y la ejecución pasó.

Se descargaron 161 archivos públicos. **149 coinciden byte a byte**, incluidos
todos los JS/CSS, HTML y versión. La comparación binaria completa conserva FAIL
para 12 PNG: sus fuentes en ambos ZIP son idénticas y sus bytes HTTP son también
idénticos a los del release anterior. Corresponden a las transformaciones de
entrega ya documentadas en la [publicación previa](../supervisores-metas/PUBLICACION.md).
No se modificaron imágenes ni configuración CDN. `.htaccess` no se solicita por
HTTP. [Descargas](produccion/assets-http.json) y
[comparación con el release anterior](produccion/assets-adjudicacion.json).
