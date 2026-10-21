# Gerencia - Resumen sin Por empresa (2026-10-20)

Relacionado con [[Gerencia - Resumen compacto y publicación (2026-10-20)]] y [[Auditoria del Resumen de Gerencia - metricas (2026-09-24)]].

Miguel pidió retirar también «Por empresa» del resumen de gerencia por considerarlo innecesario. Se eliminó su montaje en `app/src/screens/hoy/gerencia.tsx`, su import y el cálculo usado únicamente para ese bloque. El resumen deja de cargar la consulta de cierres externos de ese componente.

El componente compartido permanece en las pantallas de supervisión. No se modificaron datos de cierres, cálculos financieros, permisos ni backend.

## Estado

**Publicado y verificado en producción** el 20/10/2026. Se conservó la actualización de Citas de la PR #346 (`4086bbf0e9a9`), publicada después del ajuste anterior del resumen.

El cambio se integró mediante la PR #347 desde la copia limpia `/private/tmp/crm-resumen-publicar-20261020`. Solo modifica `gerencia.tsx` y la prueba existente en `gerencia.test.tsx`, que conserva la validación del mes de cumplimiento y comprueba que ya no se consulta el desglose. El checkout original conserva los demás trabajos previos.

## Publicación efectiva

- Sitio: https://crm.miavance.com/#/hoy
- PR: https://github.com/avanza-digital/avancecorp-crm/pull/347
- Fuente: `f9f755c0efcdd35eb8b7059303f394b8dc1b8369`.
- Main local, `avancecorp/main` y artefacto coincidieron antes de publicar; fuente limpia.
- ZIP: `CRM-Avance-Corp/releases/crm-20261020T200552Z-f9f755c0efcd.zip`.
- Manifiesto: `CRM-Avance-Corp/releases/crm-20261020T200552Z-f9f755c0efcd.manifest.json`.
- SHA-256: `3c634cc1d2f6326df20887d63d8b734a91e54fda305f075ea62e962ff7802db8`.
- Tamaño: 2.595.665 bytes.
- Build servido: `build-20261020T200552096Z`.
- Hostinger: subida y despliegue exitosos mediante `hosting_deployStaticWebsite`, con la sesión existente del conector oficial.
- Comprobación HTTP: 20/10/2026, 15:06:53 Lima, 131/131 archivos de aplicación con HTTP 200 y hashes/bytes coincidentes.
- Recuperación: se conserva el ZIP anterior `crm-20261020T181718Z-4086bbf0e9a9.zip` y su manifiesto.

La fusión normal fue bloqueada por la aprobación requerida de Main. Miguel autorizó expresamente «Autorizar fusión administrativa de #347» y se utilizó únicamente para esa PR, después del preflight obligatorio. No se cambiaron las reglas del repositorio.

## Validación

- `npm run check` sobre Main actualizado con #346: PASS, 464 archivos / 7.493 pruebas; lint, tipos, cobertura, build y validación del bundle.
- Playwright local Docker: PASS, 4 passed / 0 failed, specs `resumen-gerencia-compacto` y `resumen-gerencia-movil`.
- `git diff --check`: PASS.
- El árbol de aplicación del commit fusionado coincide con `215a3bf215b7928bf16c33bf9be869b21b3fd9ae`, que pasó los checks.
- `release:crm` y `release:crm:verify`: PASS.
- Preflight de publicación: PASS, vivo `4086bbf0e9a9` / `build-20261020T181717473Z`, candidato `f9f755c0efcd`.
- Smoke autenticado en Chrome: PASS. Indicadores cargados; cero encabezados «Por empresa» y cero botones «Ver cierres del mes». «Compromisos de supervisores» continúa después de los indicadores. No se crearon ni eliminaron datos reales; se verificó desde una pestaña separada.
- GitHub: preflight y detección de cambios SUCCESS; `app-check` y CodeRabbit seguían en curso en la última consulta. No se atribuye PASS a estos dos; el check integral local del mismo código sí pasó. Supabase Preview SKIPPED.
- Nivel 1: no requiere revisión secundaria.
- El entorno Docker reutiliza las dependencias mediante enlace simbólico y emite avisos de fuentes fuera del directorio de Vite; los cuatro recorridos funcionales pasan. La revisión visual final se realizó sobre producción con sus fuentes publicadas.

Diff, logs, recibo saneado de Hostinger, verificación HTTP y captura `resumen-publicado.jpg` conservados en `CRM-Avance-Corp/output/resumen-sin-empresa/`.
