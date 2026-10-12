# Publicación del filtro Gestionado en Leads — 03/10/2026

Estado: **PUBLICADO Y VERIFICADO** en https://crm.miavance.com. Autorización: Miguel invocó `$release-crm` en Codex. **Integrado en main mediante la PR #174**, fusionada el 03/10 a las 16:39 Lima (`634ba7ad`). Todos los checks de GitHub pasaron.

## Artefacto efectivamente publicado

- Fuente: `8db0d4f1f51dae0e2ecca0bddf19bce28d4e74bb`, árbol limpio, rama `rescue/leads-gestionado-20261003`.
- Build: `build-20261003T192635854Z`.
- ZIP: `CRM-Avance-Corp/releases/crm-20261003T192636Z-8db0d4f1f51d.zip`, 2.400.796 bytes, 130 archivos.
- Manifiesto hermano: `crm-20261003T192636Z-8db0d4f1f51d.manifest.json`.
- SHA-256: `a5719537bf290e159f91771d40a62621f0d6e96c26c43d82b4b1c2ed7e8a9dc6`.
- Publicado por el conector Hostinger, operación `hosting_deploy-static-website`, dominio exacto `crm.miavance.com`, `removeArchive:false`. Subida `success`; despliegue `Request accepted`; finalización acreditada por los archivos servidos.
- Recuperación conservada: `crm-20261002T005155Z-4498582850b1.zip` y manifiesto, SHA-256 `e57c5187a3315b3e42aeaed05a07f0a7dd93da5d1b74dc36116c7b8caf77cdde`. Un rollback requiere la decisión humana indicada por el procedimiento.

## Alcance

Gestionado aparece entre Nuevo y Contactado en Leads y usa `p_etapa=nuevo` + `p_gestion=con_gestion`. La base filtra antes de contar y paginar. Conserva los otros filtros, incluido potencial, y separa caché y cursor. En demo clasifica con el timeline completo y la regla ya publicada del Pipeline. Nuevo conserva el filtro de etapa completa que tenía antes.

Solo seis archivos de frontend/tests cambiaron respecto al main remoto. El soporte API/caché y la regla de gestión ya estaban en esa rama. Sin cambios de SQL, RLS, Edge Functions o configuración de producción.

## Integración del código publicado

Se trabajó en una copia Git independiente, sin worktree y sin modificar el historial ni los cambios ajenos de la carpeta compartida. Base remota: `a2e6a3b90026571114744b0cbd625ca477858c3d`.

El main remoto tenía el código del vivo, pero no su ancestro debido al historial lineal/squash. GitHub rechazó un push directo que contenía un merge: requiere PR, historial lineal y check `verify`. No se cambió la protección.

El candidato lineal limpio `bc8160c3` fue rechazado por el preflight: «no contiene el release vivo 4498582850b1». Conforme a la excepción de `CLAUDE.md`, el rescate partió de `44985828`, integró el main remoto y añadió el filtro. Los tres conflictos eran actas antiguas y una llamada de test: se conservaron las versiones remotas recientes. El árbol tras integrar fue exactamente el remoto; el árbol final `8db0d4f1` es idéntico al código que pasó los gates (`83d928dd`).

PR: https://github.com/avanza-digital/avancecorp-crm/pull/174. Fusionada por squash el 03/10 a las 16:39 Lima: `634ba7ad408b6f0d3e7e190e5e6e1d3756456b60`. Se verificó que el árbol frontend coincide con el publicado; el commit de origen del artefacto sigue siendo `8db0d4f1`.

GitHub rechazó la fusión normal después de pasar los checks con `reviewDecision=REVIEW_REQUIRED`. La regla organizacional `20216285` exige una aprobación y revisión de code owner; no hay revisiones todavía. La fusión automática está deshabilitada. No se usó `--admin`, no se modificaron protecciones ni se fingió una aprobación. Se pidió a Miguel obtener esa revisión para terminar la integración el mismo día. Ese bloqueo inicial quedó resuelto por la fusión posterior, comprobada mediante GitHub.

## Verificación

| Comprobación | Resultado |
|---|---|
| `npm run check` sobre la versión integrada | PASS: 346 archivos, 5.596 tests; lint, tipos, cobertura, build, configuración, bundle y duplicación |
| `e2e/cartera-keyset.spec.ts` en Docker local | PASS: 6/6, incluida búsqueda fuera de la primera página, total 55, segunda página y regreso a Nuevo |
| Revisión independiente `scripts/claude-review` | PASS; mejoras de desacoplamiento y documentación aplicadas; hipótesis de caché resueltas |
| `release:crm` y `release:crm:verify` | PASS; fuente limpia y huella/destino correctos |
| Preflight del artefacto final | PASS: vivo `44985828` → candidato `8db0d4f1` |
| Contrato productivo, solo lectura | PASS: parámetro `p_gestion`, tenencia actual y exclusión de actividades deshechas presentes |
| Postflight HTTPS | PASS: 94/94 archivos JS/CSS/HTML/version, HTTP 200 y SHA-256 idéntico al manifiesto; incluye portada y JS principal |
| Navegador, sesión real de Gerencia | PASS: acceso, Leads, opción Gestionado, total 339 y potencial disponible; sin errores de consola |
| Conteo SQL agregado de control | PASS: 454 nuevos activos, 339 gestionados; coincide con la pantalla en el momento del smoke |
| GitHub Actions de la PR #174 | PASS: `cambios`, `app-check` (7m24s) y `verify`; Supabase Preview omitido |
| ZIP fuera del web root | PASS: su URL pública responde 404 |
| Gate general `gate:realidad` | NOT RUN: faltan variables de servicio; no confundir con la comprobación puntual y el recorrido real anteriores |

Las pruebas del navegador productivo fueron de lectura; no se crearon ni borraron datos reales. Los conteos cambian con la operación diaria y no son una constante del producto. La suite E2E completa no se repitió: se ejecutó la suite correspondiente al cambio; E2E siempre local en Docker.

Evidencia local: `releases/gestionado-leads-20261003/` en la raíz del taller (`check-release.log`, `e2e-release.log`, `release-final.log`, `smoke-publicado.json`, revisión y parche inicial). ZIP/manifiesto conservados fuera del web root.
