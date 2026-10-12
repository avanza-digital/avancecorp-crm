# Saludo personalizado de Gerencia publicado — 6 de octubre de 2026

Publicado y verificado en https://crm.miavance.com el 6 de octubre a las 10:30 Lima. El Resumen móvil presenta **«Bienvenido, Carlos»** para la sesión real de Carlos. El saludo usa el primer nombre de cada usuario; si falta, muestra «Bienvenido».

## Fuente y autorización

Miguel autorizó «publica pues», aplazó la revisión y retomó con «ya esta el pr». [PR #203](https://github.com/avanza-digital/avancecorp-crm/pull/203) integrado a las 15:27:23 UTC; cambios, app-check, verify y preflight de GitHub PASS.

- Main publicado: `33694da631ac0b073c0b8887dbb62f953130c270`.
- Main original, Main de la copia limpia y `avancecorp/main` iguales al publicar y al cerrar.
- Árbol completo idéntico al candidato probado `f9a29bfa5d32834243c29aa61973fa73d8310f07`; squash cambió la identidad del commit, sin cambios de código.
- WIP ajeno preservado; alineación original sin modificar archivos de trabajo ni conservar cambios staged.
- Alcance: dos archivos del frontend/E2E. Se reutiliza `primerNombre(yo?.nombre_completo)`; no se agregan consultas ni cambios de backend.

## Paquete publicado

- Build: `build-20261006T152938176Z`.
- ZIP: `releases/crm-20261006T152939Z-33694da631ac.zip` (2,483,169 bytes).
- SHA-256: `10490092405e959fdbe4a5f879654b40f46e1ad0b333a01c237f376de2011be1`.
- Manifiesto: `releases/crm-20261006T152939Z-33694da631ac.manifest.json`.
- Fuente limpia; destino `crm.miavance.com`.
- Respaldo de la versión anterior conservado y revalidado: `crm-20261006T140146Z-ea3b6ed22a9b.zip`, SHA-256 `10995f86d0958020362e5dd012eee4b78d52bd1492d98aadd3ef70ba092adda6`. No se ejecutó rollback.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run check` del código idéntico publicado | PASS: 385 archivos, 6.187 pruebas; lint, tipos, cobertura, build, bundle y duplicación |
| E2E local en Docker, `resumen-gerencia-movil.spec.ts` | PASS: 3 pruebas, 0 reintentos |
| `release:crm` y `release:crm:verify` desde Main limpio | PASS |
| Preflight obligatorio contra versión viva | PASS |
| Hostinger | PASS: una única publicación aceptada a las 2026-10-06T15:30:56.903Z |
| HTTPS | PASS: 153 archivos, 139 con bytes/SHA exactos, 13 imágenes disponibles y `.htaccess` protegido |
| Portada, JavaScript principal y versión | PASS: HTTP 200 y coincidencia con el paquete |
| ZIP en URL pública | PASS: HTTP 404 |
| Smoke Gerencia real | PASS: saludo «Bienvenido, Carlos», fecha, subtítulo, indicadores y navegación visibles |
| PWA instalada en teléfono físico | NOT RUN: sin dispositivo; se verificó en navegador a 390 × 844 |

La evidencia local de check/E2E se reutiliza por equivalencia exacta del árbol; no se presenta como una ejecución nueva tras el squash. El smoke fue de lectura, sin crear ni modificar operaciones reales. Se restauró el viewport del navegador.

Evidencia: `output/saludo-gerencia-local/deploy/`, incluidos `equivalencia-main.json`, `release-build.log`, `release-verify.log`, `preflight.log`, `hostinger-recibo.json`, `postflight-https.json`, `smoke-produccion.json` y `saludo-publicado-movil.jpg`. No quedan pasos de publicación pendientes para este saludo.
