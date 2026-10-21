# Gerencia - Resumen compacto y publicación (2026-10-20)

Relacionado con [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]], [[Auditoria del Resumen de Gerencia - metricas (2026-09-24)]] y [[Deploy a Hostinger]].

## Decisión y alcance

Miguel pidió retirar del resumen los bloques «Gestión de leads y clientes» y «Capital en soles con TC fijado por venta», y reducir el espacio de los filtros. El resumen de gerencia muestra fechas pequeñas alineadas a la derecha y un botón «Fuentes» que despliega los orígenes. El botón indica la cantidad cuando existe selección parcial. Se mantienen el filtrado y el acceso móvil al resumen completo.

Es un cambio de presentación del frontend. No modifica cálculos, contratos, permisos, base de datos ni funciones Edge. La gestión diaria permanece en su módulo y la cobertura de capital permanece disponible en Ranking.

## Publicación efectiva

- Sitio: https://crm.miavance.com/#/hoy
- PR: https://github.com/avanza-digital/avancecorp-crm/pull/345
- Commit fuente: `c84109d8d106d77dfbff0a664c7b39a32920d678`.
- Main local y `avancecorp/main` coincidieron antes de construir y publicar.
- Copia limpia: `/private/tmp/crm-resumen-publicar-20261020`.
- Artefacto: `CRM-Avance-Corp/releases/crm-20261020T164304Z-c84109d8d106.zip`.
- Manifiesto: `CRM-Avance-Corp/releases/crm-20261020T164304Z-c84109d8d106.manifest.json`.
- SHA-256: `91e3b95a2c6ff36e87ead5142b77a72aa5a2893faa11a16dc12a7aeb5a04fb00`.
- Tamaño: 2.597.893 bytes.
- Build publicado: `build-20261020T164303230Z`.
- Publicado mediante `hosting_deployStaticWebsite` del conector oficial de Hostinger; recibo de subida y despliegue exitosos.
- Verificación HTTP completada el 20/10/2026 a las 12:55:55 de Lima.

GitHub bloqueó la fusión ordinaria por la aprobación requerida de Main. Miguel autorizó expresamente «Autorizar fusión administrativa de #345». Se integró exclusivamente esa PR, con el preflight obligatorio en PASS. No se alteraron las reglas del repositorio.

## Evidencia y verificaciones

- `npm run check`: PASS, 464 archivos y 7.481 pruebas. Incluye lint, tipos, cobertura, build y validación de bundle.
- Hook pre-push: PASS, 7.481 pruebas.
- Playwright local Docker: PASS, 6 passed / 0 failed en los recorridos de resumen compacto, resumen móvil, coherencia y cierre de postventa.
- La primera ejecución del navegador, simultánea con cobertura y compilación inicial, agotó tiempos de carga en cuatro pruebas. La repetición aislada pasó las seis.
- El clon reutilizó las dependencias existentes mediante enlace simbólico; Vite emitió avisos de fuentes fuera de su directorio permitido durante los E2E. La comprobación visual final se hizo sobre producción con sus fuentes publicadas.
- `git diff --check`: PASS.
- El árbol de la aplicación integrada es idéntico al que pasó los checks locales.
- `npm run release:crm` y `release:crm:verify`: PASS; fuente limpia.
- Preflight de publicación: PASS, candidato descendiente del vivo `c7c150f37dbb`, build anterior `build-20261020T060525358Z`.
- HTTP: PASS, 131/131 archivos de aplicación (HTML principal, versión y todos los JS/CSS del manifiesto), HTTP 200, bytes y SHA-256 coincidentes.
- Smoke autenticado en Chrome: PASS; carga de indicadores, fechas a la derecha, Fuentes abre/cierra y ambos bloques retirados ausentes. No se crearon ni eliminaron datos reales.
- GitHub PR #345: `preflight`, `cambios`, `app-check` y `verify` SUCCESS; Supabase Preview SKIPPED.
- Gate de realidad por CLI: NOT RUN por falta de `SUPABASE_URL` en ese entorno. No se requirieron cambios de backend; el smoke autenticado anterior sí se completó.

Evidencia local en `CRM-Avance-Corp/output/resumen-gerencia-publicacion/`: logs, recibo saneado de Hostinger, verificación HTTP y captura `resumen-publicado.jpg`.

Se conserva el paquete anterior `crm-20261020T060526Z-c7c150f37dbb.zip` y su manifiesto para recuperación conforme al procedimiento de publicación. El trabajo previo no relacionado del checkout original se preservó; solo el delta de esta tarea se integró desde la copia limpia.
