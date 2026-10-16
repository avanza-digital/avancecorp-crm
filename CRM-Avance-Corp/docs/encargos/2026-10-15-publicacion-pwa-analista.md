# Publicación de PWA para Analista

**Publicado y verificado en https://crm.miavance.com/**. Verificación final: 15/10/2026, 21:33 (Lima), 16/10/2026, 02:33 UTC.

Analista dispone de **Mi día · Gestión Diaria · Agenda · Más**, pendientes propios, filtros conservados y las mejoras de teclado, márgenes seguros, desconexión y actualización aplazable. Se aplicó ECC `frontend-patterns` y el procedimiento `release-crm`.

## Fuente y artefacto

| Dato | Valor |
| --- | --- |
| PR integrado por Miguel | [#305](https://github.com/avanza-digital/avancecorp-crm/pull/305) |
| Commit publicado | `94ef6886b50d0734a29fff57c10d268680aaed9d` |
| Build servido | `build-20261016T023049819Z` |
| ZIP | [crm-20261016T023050Z-94ef6886b50d.zip](../../releases/crm-20261016T023050Z-94ef6886b50d.zip) |
| Manifiesto | [crm-20261016T023050Z-94ef6886b50d.manifest.json](../../releases/crm-20261016T023050Z-94ef6886b50d.manifest.json) |
| SHA-256 del ZIP | `ee4c53b5783645ea764a710eefab563770a5c94a0729e75c1eabff7520b557f9` |
| Tamaño del ZIP | 2.584.824 bytes |

Se construyó desde una copia limpia de Main. Main local, la copia de construcción y `avancecorp/main` coincidían en el commit publicado antes de subir. El árbol integrado es idéntico al commit de implementación `eac8480271e0393824aa272847044215a4b503fa` que pasó las pruebas. El árbol original conserva los trabajos de otras tareas.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run check` integrado | PASS: 434 archivos, 6976 pruebas, cobertura, lint, typecheck, configuración, build y bundle. |
| Repetición con dependencias del lockfile | PASS: 6976 pruebas; lint y typecheck PASS, seis advertencias de lint preexistentes. |
| E2E completos, Docker local | PASS: **436 passed / 0 failed / 26 skipped**, dos workers, cero reintentos, 18,8 min. |
| Controles GitHub | PASS: `app-check`, `verify` y `preflight`; Supabase Preview omitido. |
| `release:crm` y `release:crm:verify` | PASS; fuente limpia y configuración de Supabase verificada. |
| Preflight contra la versión viva | PASS: `d1796dd4cf8c` → `94ef6886b50d`; conserva lo publicado. |
| Hostinger MCP oficial | Subida correcta y despliegue aceptado; comprobado después por HTTPS. |
| Verificación HTTP y SHA-256 | PASS: **126 archivos**, incluidos portada, versión, manifiesto y todos los JS/CSS del paquete; cero diferencias. |
| Navegador limpio contra producción | PASS: acceso a login a 390×844 y 1440×900, HTTP 200, sin errores de JavaScript ni desbordamiento horizontal. Capturas inspeccionadas. |
| Analista instalado en Android/iPhone físicos | NOT RUN. Pendiente de comprobación en los teléfonos. |

Evidencia en `output/pwa-analista-20261015/`: `publicacion-check.log`, `publicacion-unitarias-lock.log`, `publicacion-e2e-completo.log`, `publicacion-pr305.json`, `publicacion-release.log`, `publicacion-hostinger.json`, `publicacion-http.json`, `publicacion-navegador.json` y capturas `publicacion-login-*.png`.

El smoke público comprueba el acceso a la aplicación sin iniciar sesión ni escribir datos. Los flujos autenticados se validaron en Docker con fixtures. La prueba de teclado fue simulada; la confirmación física anterior del usuario correspondía a Gerencia. Los límites del gate de realidad administrativo se conservan en [la entrega de implementación](2026-10-15-pwa-analista.md).

## Versión anterior conservada

Build anterior: `build-20261016T002734754Z`, commit `d1796dd4cf8c771d7b35f3db608d536a99d51a9c`.

ZIP y manifiesto conservados en `releases/crm-20261016T002735Z-d1796dd4cf8c.*`. SHA-256 comprobado: `956e504ee7790ab912cf789a27a7e1ae36697dd2507e1c3c043d549a2d2d3cc6`. No se realizó rollback.

## Guardado y retoma de la sesión

Miguel solicitó guardar la entrega y retirar los temporales de esta sesión. El código está integrado en Main mediante el PR #305; estas notas registran lo que se publicó después de ese merge. La publicación sigue teniendo como fuente `94ef6886`, aunque se integren actas posteriores.

Evidencia y registro de limpieza: `output/pwa-analista-20261015/`. Respaldo local de cierre: `output/pwa-analista-20261015-respaldo-cierre.tar.gz`, con inventario y huellas en el archivo `.manifest.json` contiguo. Conserva las notas, el parche de implementación, los resultados y capturas, y los ZIP/manifiestos de la versión publicada y la anterior. Los archivos de entorno y las dependencias quedan fuera del respaldo.

El resultado exacto de los temporales retirados y la comprobación de trabajos ajenos se guarda en `output/pwa-analista-20261015/cierre-limpieza.json`. Para retomar la PWA, la comprobación pendiente es abrirla instalada como Analista en Android e iPhone. Los cambios locales de otras tareas permanecen en su árbol original.
