# Planilla de reparto publicada — 15/10/2026

Publicada en [crm.miavance.com](https://crm.miavance.com/) y verificada el 15/10 a las 18:05 Lima. Se abre en **Repartir → Coordinación → supervisores**. Reparte cantidades por origen y supervisor, con fechas independientes de ingreso al CRM y reparto, acumulado semanal, rangos y días específicos. La agenda anterior sigue como acceso secundario.

## Fuente y artefacto

- PR #296 integrada: `875054a2d630cb8d8786fe02e870000d5dfdba07`.
- Main local = `avancecorp/main`, fuente limpia antes de construir y de subir.
- Árbol completo `4dc276ad1b6b56067686646ee2b3136696129c9d`, idéntico a `dc21d434` probado. Se reutilizó su evidencia conforme a `release-crm`: 6.946 tests y 41 escenarios distintos E2E de reparto en Docker. Suite E2E completa del CRM: NOT RUN; alcance afectado PASS.
- Build: `build-20261015T225912394Z`.
- ZIP: `crm-20261015T225913Z-875054a2d630.zip`; 2.583.264 bytes, 162 archivos.
- SHA256: `ee39c7162300b1f005727cf352858e8098c782c21e5ed3ac11eb7f6aea2af63e`.
- Manifiesto: `releases/crm-20261015T225913Z-875054a2d630.manifest.json`.

## Verificación y alcance

Build, manifiesto, CRC/hashes y preflight obligatorio: **PASS**. El candidato contiene la versión anterior `597cab1c`. El conector oficial Hostinger confirmó el dominio exacto y aceptó el ZIP. Se resolvió una sesión OAuth vencida mediante la reconexión oficial solicitada por Miguel; no se cambiaron MCP, proveedor ni paquetes.

**126 comprobaciones HTTP PASS**, a las 23:05:11 UTC: portada, index, versión y todos los JS/CSS coinciden por bytes y SHA256 con el manifiesto; el entrypoint apunta a los assets esperados. Smoke público en Chromium/Docker: HTTP 200, campos de acceso visibles y cero errores JavaScript. No incluye login Auth humano.

**Permiso productivo PASS**, solo lectura: identidad real activa de Coordinación (no superadmin), claims locales y `SET LOCAL ROLE authenticated`; `crm.agenda_reparto_diaria(hoy Lima,1)` devuelve `rol_crm=coordinador`, `reparto_libre=true`, fecha `2026-10-15`, un día. Transacción READ ONLY y ROLLBACK. No se asignó ningún lead para probar.

Esta publicación es solo frontend. No aplica migraciones ni Edge, no cambia el control de reparto libre ni modifica n8n. No redistribuye leads ya asignados. La revisión de cantidades requiere confirmación explícita dentro del CRM; los envíos son secuenciales y el lote no es atómico. Los detalles y límites están en [VALIDACION.md](VALIDACION.md).

## Recuperación y registro

Se conserva el ZIP anterior `crm-20261015T212301Z-597cab1cbfe6.zip` y su manifiesto, verificados. SHA256: `7fd053eda9631665791c6a72959ea60e0959e1e73c99b13833a83f7ecea1bbd8`. Una eventual reversión requiere seguir el procedimiento del proyecto; no se ejecutó.

[Figma actualizado](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=52-34). Las actas posteriores no cambian el commit fuente publicado ni requieren otra publicación.
