---
tags: [crm, leads, gestionado, filtros]
actualizado: 2026-10-03
estado: publicado
---

# Leads - filtro Gestionado

Miguel pidió añadir «Gestionado» al selector de etapas de Leads y autorizó la publicación mediante `$release-crm`. **PUBLICADO y verificado el 03/10/2026**, build `build-20261003T192635854Z`, fuente limpia `8db0d4f1f51dae0e2ecca0bddf19bce28d4e74bb`. Relacionado con [[Pipeline - columna Gestionado (2026-10-01)]] y [[Inicio]].

## Publicación

En `https://crm.miavance.com`, la sesión real de Gerencia muestra **Gestionado 339**, coincidente con el conteo SQL de solo lectura. El selector conserva el resto de etapas y el filtro de potencial. Consola sin errores y **94/94 archivos JS/CSS/HTML/version** idénticos al manifiesto por SHA-256.

El código vigente integrado pasó `npm run check`: **5.596 tests / 346 archivos**, y **6/6 E2E en Docker**. La evidencia inicial de 5.023 tests de abajo corresponde a la copia de trabajo anterior, no al artefacto publicado.

Paquete: `CRM-Avance-Corp/releases/crm-20261003T192636Z-8db0d4f1f51d.zip`; SHA-256 `a5719537bf290e159f91771d40a62621f0d6e96c26c43d82b4b1c2ed7e8a9dc6`. Acta: `CRM-Avance-Corp/docs/publicaciones/gestionado-leads-2026-10-03.md`. PR de integración: https://github.com/avanza-digital/avancecorp-crm/pull/174 — **MERGED el 03/10 a las 16:39 Lima**, commit `634ba7ad408b6f0d3e7e190e5e6e1d3756456b60`, árbol frontend idéntico al publicado. El bloqueo inicial por code owner quedó resuelto; no se modificaron protecciones.

## Comportamiento

- Nueva opción entre «Nuevo» y «Contactado», con contador y etiqueta Gestionado al seleccionarla.
- Reutiliza la regla publicada del Pipeline: lead con etapa almacenada `nuevo`, analista asignado y contacto válido desde `tenencia_desde`. Cuentan llamadas realizadas/no contestadas, WhatsApp enviado/recibido y reunión realizada. No cuentan notas, gestiones anteriores a la tenencia actual ni actividades con `metadata.deshecho_en`.
- «Nuevo» conserva su filtro anterior de etapa completa; «Gestionado» es un subconjunto. En Pipeline las dos columnas sí son excluyentes. No se cambió el significado del filtro existente al añadir esta opción.
- En sesión real se envían `p_etapa='nuevo'` y `p_gestion='con_gestion'` a `crm.cartera_filtrada_fn`. El servidor filtra antes de contar/paginar; nunca se deduce de las primeras filas cargadas ni de `ultimo_contacto_en`.
- El filtro forma parte de la clave de caché, mantiene su propio cursor y se combina con origen, analista, procedencia, reasignados y fechas. Al elegir otra etapa se retira `p_gestion`.
- En demo la pantalla clasifica con el timeline completo antes de contar/paginar. Este contrato queda explicado en `useCarteraPaginada`.

## Evidencia y revisión

- `npm run check`: **PASS**, 322 archivos / 5.023 tests, tipos, lint, cobertura, build, configuración de release, service worker, bundle y duplicación. Advertencias previas de accesibilidad en `coverflow-carousel.tsx`.
- Suites focalizadas de pantalla, API, caché y regla de gestión: **153/153 PASS**. Repetidas tras los ajustes finales, junto a tipos y lint.
- Docker local, `e2e/cartera-keyset.spec.ts`: **6/6 PASS**. Caso nuevo: los 55 gestionados están fuera de las primeras 50 filas sin filtro; selección, total, segunda página y regreso a Nuevo correctos. Backend HTTP simulado; no es una prueba de usuarios reales en producción.
- Contrato productivo verificado mediante SQL de solo lectura: `cartera_filtrada_fn` ya acepta `p_gestion` y aplica el predicado antes de página/resumen. No hacen falta migraciones.
- `npm run gate:realidad`: **NOT RUN**, falta `SUPABASE_URL` en el entorno del gate. La inspección puntual anterior no sustituye este gate.
- Revisión independiente con `scripts/claude-review`: **PASS**, sin hallazgos obligatorios. Se desacopló la lista de opciones de las columnas del Pipeline y se documentó el contrato demo. La diferencia de «Nuevo» queda explícita arriba.
- Hipótesis de caché revisadas: `useCarteraInfinita` y `query-client.ts` no conservan datos anteriores como placeholder. `registrarActividad` y `deshacerResultadoLlamada` usan `persistir` → `resincronizarReal`, que invalida el prefijo `crmQueryKeys.leads()` y también esta lista.

## Preparación e integración

La copia local tiene muchos cambios previos y diverge de `avancecorp/main` (292 commits locales / 31 remotos al cierre; local `42de3256`, referencia remota `b6c4e3b4`). Estas referencias cambiaron durante la sesión: verificarlas de nuevo al publicar. No se descartó ni integró trabajo ajeno y no se creó un commit mezclado.

Los archivos `pipeline-columnas.ts` y su test se recuperaron idénticos desde `avancecorp/main`: allí ya existen, al igual que buena parte del soporte `gestion` de API/caché. Al integrar, conservar también el filtro remoto `potencial`. No sustituir archivos completos remotos por la copia local.

El parche exclusivo de esta tarea, calculado contra el estado inicial de los nueve archivos existentes, y los logs se guardaron en `releases/gestionado-leads-20261003/`. **Es evidencia local, no un artefacto publicable.**

Se usó una copia limpia en `/private/tmp/avancecorp-gestionado-release-20261003`. GitHub exige PR e historial lineal, y rechazó la primera propuesta de enlace mediante merge. El preflight rechazó el candidato lineal `bc8160c3` porque no contenía el ancestro vivo `44985828`. Se siguió la excepción de rescate: rama `rescue/leads-gestionado-20261003` desde ese commit vivo, integración del main remoto `a2e6a3b9` conservando su árbol exacto y aplicación del filtro. El árbol final es idéntico al ya verificado; preflight final PASS. No se aplicaron SQL, Edge Functions ni cambios de configuración.

La copia original compartida y sus cambios ajenos se conservaron. La PR #174 devuelve el cambio publicado al main remoto mediante squash conforme a la protección de GitHub; no reescribir ni forzar los historiales para ocultar esa diferencia de ancestría.
