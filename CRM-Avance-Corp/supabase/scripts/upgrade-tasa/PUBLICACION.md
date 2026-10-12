# Publicación de tasa del upgrade — 07/10/2026

**PUBLICADO y comprobado en https://crm.miavance.com el 07/10/2026.**
El usuario autorizó «publiquemos» y «Sí, probar y publicar», incluido el costo
de la rama temporal Supabase y su eliminación al terminar.

## Versión efectivamente publicada

- PR: https://github.com/avanza-digital/avancecorp-crm/pull/218 (fusionada).
- Commit: `ab361d4f6c6d2b9db2e36c5a6ece71894725398d`.
- Build: `build-20261007T191820053Z`.
- Artefacto: `releases/crm-20261007T191820Z-ab361d4f6c6d.zip`, 2.530.784 bytes.
- SHA-256 del ZIP: `0c8fe83fba846b7c33b7745aee3362a169638e7823cff2656428606e14f7f8dc`.
- Respaldo anterior conservado: `crm-20261007T152928Z-e511d30504f2.zip`
  y su manifiesto, SHA-256
  `44e46cc985a251a6d51d04bfd5b942e85443a2504fd7d9bab063f1df63846cf9`.

El artefacto se construyó desde una copia limpia: Main local y `avancecorp/main`
coincidían en ese commit. El squash de la PR conserva exactamente el árbol de
código validado. PASS: `release:crm`, `release:crm:verify` y preflight de Hostinger
inmediatamente antes de desplegar. Hostinger respondió éxito; no se repitió el
despliegue. Esta acta posterior no cambia el commit fuente del manifiesto.

## Base de datos publicada

- Producción: `dctqcbznekcyxhjujuci` (PortalAvanceCorp).
- Migración única: `20261007180108_crm_upgrade_tasa_flexible.sql`.
- SHA-256 del SQL: `725975473de374c3159ae5795a443418cd1a24f5c1c43f6c871f8f16255bd2b0`.
- Se fusionó la rama de ensayo autorizada `upgrade-tasa-20261007`
  (`ezemlzywbtzrbunsbeza`) mediante `merge_branch`, tras los ensayos.
- Postflight PASS: los ocho statements registrados coinciden literalmente con
  el SQL ensayado; las tres funciones tienen las huellas y permisos esperados.
  Las 436 migraciones anteriores conservan su huella
  `4ae4108911ff43ecb9f35c324ea36282`; las 22 Edge Functions no cambiaron.
- La rama temporal se eliminó y se confirmó su ausencia. No se tocaron otras ramas.

La configuración productiva permanece en **observación v18**, solicitudes
desactivadas, base 15 y tope 25. Al registrar un upgrade permite una tasa menor
o mayor dentro de los límites vigentes, sin solicitud. Al activar solicitudes,
una tasa superior a la del origen requiere aprobación de Gerencia. El contrato
anterior conserva sus condiciones. No se activó enforcement.

## Verificación

- PASS: `npm run check`, 6.364 tests en 396 archivos; lint, tipos, cobertura,
  build, bundle, configuración de release, service worker y duplicación 0.44 %.
- PASS: E2E completo en Docker local, **383 pasaron, 26 omitidos, 0 fallos**,
  sin retries (15,8 minutos). El intento inicial falló por rutas de fuentes del
  node_modules enlazado; se corrigió el entorno antes de la corrida completa.
- PASS: SQL autenticado local y remoto con rollback, reglas ON/OFF, tasa menor,
  aprobación y consumo único, origen intacto, topes, reversa y concurrencia.
- PASS: `check:scripts`, `test:edge-preflight`, `seed:preflight` y
  `test:rls:preflight`. GitHub: app-check, verify, preflight y cambios.
- RLS remoto: primera corrida completa **3.074/3.075**, con un fallo por faltar
  la fila inicial de configuración de Reparto en la rama reconstruida solo con
  esquema. Se restauró el fixture sintético y el valor inicial de su migración;
  repetición íntegra del bloque Reparto: **117/117 PASS**. Se conserva el fallo
  original en la evidencia; no se presenta como una corrida 3.075/3.075.
- PASS del smoke obligatorio: portada HTTP 200 y bytes exactos; **118 archivos
  de JS/CSS, index y versión coinciden exactamente** con el manifiesto.
  Acceso autenticado al Resumen comprobado en Chrome, sin crear datos reales.

El cotejo adicional de todos los recursos dio 142/154 coincidencias binarias:
los 12 restantes son PNG sin cambios respecto al ZIP anterior, servidos por
`hcdn`. Se comprobaron también con URL nueva: siete conservan píxeles idénticos;
cinco logos pasan de 3508×3253 a 1600×1484. Esta transformación de imágenes queda
registrada; el cotejo binario total no se declara PASS. No afecta al cotejo
exacto de código y estilos exigido para el release.

## Evidencia y límites

Manifiesto y comprobaciones: junto al ZIP, sufijos `.manifest.json`,
`.smoke.json` y `.smoke-cierre.json`. El segundo smoke registra el cotejo
adicional de imágenes; su campo `pass=false` corresponde a píxeles redimensionados,
con `runtime_exact=true` y `home_exact=true`.

Logs y auditoría SQL: `output/upgrade-tasa-20261007/`, incluido `postmerge.json`.
Advisors sin nuevos avisos SQL atribuibles al cambio; advertencia de protección
de contraseñas filtradas preexistente, también en producción. El gate de realidad
no pudo leer `periodos_cerrados` con service_role; la consulta equivalente de solo
lectura confirmó 0 metas bajo el sello. Persisten 275 clientes sin domicilio legal,
dato preexistente exigido al registrar un contrato. No se relajó esa validación.

La reversa SQL preparada se niega después del primer upgrade inferior bajo
enforcement y ante deriva de funciones. No se ejecutó reversa en producción.
El ZIP anterior se conserva como respaldo, no se volvió a publicar.

## Limpieza de la sesión

Completada el 07/10/2026 a petición del usuario. Se eliminaron la copia temporal
de publicación, los dumps y scripts auxiliares, los archivos temporales de
pruebas, las capturas del ensayo y los logs intermedios redundantes. Se retiró
exclusivamente la base Docker `upgrade_tasa_20261007` (identidad comprobada,
sin conexiones activas) y la rama GitHub `fix/upgrade-tasa-configurable`, después
de confirmar que la PR #218 estaba fusionada. La rama Supabase y la pestaña
temporal de verificación ya no existían.

Se conservaron código, migración, pruebas reutilizables, reversa, acta, vault,
ZIP publicado, ZIP de recuperación, manifiestos y evidencia final de los checks.
Los contenedores compartidos y los trabajos de otras sesiones se conservaron.
Inventario de lo retirado: `output/upgrade-tasa-20261007/limpieza.json`.
