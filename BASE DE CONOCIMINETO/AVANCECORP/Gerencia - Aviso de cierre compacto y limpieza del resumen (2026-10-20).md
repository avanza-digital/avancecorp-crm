# Resumen de Gerencia: aviso compacto (20/10/2026)

**Publicado y verificado por HTTP el 20/10/2026, 16:49 Lima.** Miguel aprobó la vista local y pidió publicarla. La PR #348 se integró en Main y el artefacto se construyó desde una copia limpia del commit fusionado en `/private/tmp/crm-resumen-publicar-20261020`.

## Alcance

- Aviso de cierre normal como texto de 13 px a la derecha, debajo de las fechas.
- Detalle al pulsar; cierre con ×, Escape o clic fuera y retorno de foco por teclado.
- Alarmas de ciclo atascado visibles; misma consulta, permisos y reglas de cierre.
- Se elimina «Rango: … · Meta mensual: …» solo del Resumen.
- Se elimina la descripción junto a «Resultados por semana de ingreso» del Resumen.
- Los controles de comparación y notas de la maqueta nunca entran al producto.

## Preparación verificada

- PR: https://github.com/avanza-digital/avancecorp-crm/pull/348
- Commit candidato: `898669daf722410542b2841f2e9de87a3d09103f`.
- `npm run check`: PASS, 464 archivos / 7.496 pruebas, lint, tipos, cobertura, build y bundle.
- E2E Docker: tres pruebas de `resumen-gerencia-movil` PASS y una de `resumen-gerencia-compacto` PASS. El primer intento de esta última falló por una expectativa nueva incorrecta sobre el encabezado del fixture mensual; corregida solo esa expectativa y repetido el recorrido completo, PASS.
- Se comprobaron teclado, cierre fuera del detalle, filtros, ausencia de los textos retirados y límites del detalle en móvil.
- Docker emite avisos preexistentes de fuentes fuera de la raíz al reutilizar node_modules por enlace; las capturas finales deben verificarse con el build de producción.
- `git diff --check`: PASS. Nivel 1, sin revisión secundaria.
- `gate:realidad`: NOT RUN, falta entorno `SUPABASE_URL`/credenciales administrativas. No se alteran datos o cálculos; pruebas de UI con el estado observado del cierre de setiembre, estado sin respuesta y alarma.
- ZIP candidato: `crm-20261020T213050Z-898669daf722.zip` y manifiesto homónimo.
- SHA-256 candidato: `ee44d6db70963185dcfe69833b12c8ecfbd8536f314df841e8fb9c2471c74078`.
- `release:crm:verify`: PASS.
- Preflight del artefacto: PASS, vivo `f9f755c0efcd` / `build-20261020T200552096Z`, candidato `898669daf722`.

## Publicación efectiva

- Sitio: https://crm.miavance.com/#/hoy
- Fuente: `46d1505b4b36aaf0680b00b872c5d61278790abd`.
- PR #348 integrada el 20/10/2026 a las 16:41:51 Lima. La fusión normal anterior fue rechazada y se pidió autorización administrativa; tras el mensaje de Miguel «ya esta el pr» se comprobó que ya estaba fusionada. Codex no ejecutó una fusión administrativa en esta publicación.
- Main del clon, Main del worktree local existente y `avancecorp/main` coinciden. El checkout original con trabajos previos se preservó.
- El árbol `CRM-Avance-Corp/app` del commit fusionado es idéntico al candidato probado `898669daf722410542b2841f2e9de87a3d09103f` (`git diff --exit-code` PASS). Se reutiliza esa evidencia y se reconstruye el artefacto desde Main.
- GitHub: `preflight`, `app-check`, `verify`, `cambios` y CodeRabbit SUCCESS; Supabase Preview SKIPPED.
- ZIP publicado: `CRM-Avance-Corp/releases/crm-20261020T214658Z-46d1505b4b36.zip`.
- Manifiesto: `crm-20261020T214658Z-46d1505b4b36.manifest.json`.
- SHA-256: `b2466d567f450d09d7c9dd49066415aa255d11984db735ee6713975f274b3ab2`.
- Tamaño: 2.596.647 bytes.
- Build: `build-20261020T214658124Z`.
- `release:crm`, `release:crm:verify` y preflight desde Main: PASS; vivo anterior `f9f755c0efcd`, candidato `46d1505b4b36`.
- Hostinger: subida y despliegue aceptados mediante `hosting_deployStaticWebsite` del conector oficial, sin cambios de configuración ni credenciales.
- HTTP: PASS, 131/131 archivos (portada, versión y JS/CSS), todos HTTP 200 con bytes y SHA-256 del manifiesto. Verificado a las 16:49:24 Lima.
- Recuperación: ZIP publicado anterior `crm-20261020T200552Z-f9f755c0efcd.zip` y su manifiesto conservados.

## Comprobación visual y límites

- Acceso básico autenticado al CRM publicado: PASS. Se abrió una pestaña separada, sin crear o modificar datos.
- Resumen de Gerencia con sesión real en producción: **NOT RUN**, la sesión disponible cambió a analista; muestra «Hoy» y no permite acceder a Gerencia. No se cerró ni cambió la sesión del usuario.
- El aviso compacto y su interacción se comprobaron antes de publicar en los E2E locales Docker; las pruebas del mismo código son PASS.
- `gate:realidad` permanece NOT RUN por falta de entorno administrativo, como consta arriba.

Evidencia guardada en esta carpeta: logs de check y E2E, diff, recibo saneado de Hostinger, verificación HTTP y acta. Se copiaron el ZIP, manifiesto y evidencias al workspace original y esta nota al vault.

Relacionado: [[Gerencia - Resumen compacto y publicación (2026-10-20)]] · [[Gerencia - Resumen sin Por empresa (2026-10-20)]] · [[Cierre de mes - plazo de carga por mes decidido por Gerencia (2026-10-14)]].
