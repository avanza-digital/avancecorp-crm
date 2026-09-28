---
fecha: 2026-09-27
estado: publicado-verificado
tags:
  - citas
  - supervision
  - rls
---

# Citas Gerencia — supervisión por equipo

Se preparó la extensión de la vista **Citas Gerencia** para el rol de supervisión.

- Supervisión ve únicamente los datos vinculados a su equipo asignado y a la jerarquía descendente ya resuelta por `private.vendedor_ids_visibles`.
- El alcance se aplica en servidor a citas, tareas, asignaciones, población, conversiones y capital; no depende solo del filtro de interfaz.
- El agregado global `testigo` sigue reservado para Gerencia.
- Las migraciones `20260927172930_crm_vigilante_pre_citas.sql` y `20260927172931_crm_citas_supervisor_equipo.sql` se aplicaron y registraron en producción durante la publicación de Citas.

Publicado en `crm.miavance.com`, fuente `8ec3dd1f67e138a05250f07a35cdec3568bdf1ac`,
build `build-20260927T205509063Z`. Integración de Citas en GitHub: PR #116,
commit `a727bc2ccf6dae0231609fd8c5b81abdb311b2d5`. El build vivo se volvió a
comprobar al cerrar la revalidación E2E del 27/09 y conserva ese identificador.

## Revalidación E2E completa — 27/09/2026

Miguel pidió repetir la suite que había quedado inconclusa. Se ejecutó en una
copia aislada del commit publicado, con Playwright `1.61.1` en Docker, volumen
de dependencias Linux propio y dos workers. No hubo otra suite concurrente.

Resultado final: **279 passed, 26 skipped, 0 failed, 0 flaky**, en **10,4 minutos**.
Se desactivaron los reintentos (`--retries=0`). Las 26 omisiones ya estaban
declaradas en Clientes/Contratos antiguos, retirados en favor de Mi cartera.
Los cinco casos de `citas-gerencia.spec.ts` pasaron dentro de la suite completa.

Se corrigieron únicamente pruebas; `app/src`, dependencias y configuración de
Playwright permanecieron idénticos al commit publicado:

- En la copia del release, dos pruebas de foco buscaban una lista que dejó de
  ser inicial y una clase que sus filas ya no usan. Se comprobaron las mismas
  reglas globales sobre el botón compartido «Nuevo lead», conservando teclado,
  alto contraste y ancho mínimo del outline. Dirigidas: **3/3 PASS**. Main local
  ya contenía una corrección equivalente (`59fceade`, usando «Cola de hoy»), que
  se conservó.
- H5 comparaba conteos de Gestión diaria contaminados por consultas de «Hoy»
  durante el arranque. El escenario ahora entra directamente en
  `/#/gestion-diaria` antes del login. Conserva la comparación estricta de todas
  las consultas y los límites de carga bajo demanda. **10/10 PASS** en cinco
  repeticiones sin reintentos; después PASS en la suite completa. Este ajuste
  quedó guardado en `app/e2e/gestion-diaria-horizontal-h5.spec.ts` del proyecto.
- Lint de ambos archivos: **PASS**, cero errores/advertencias; `git diff --check`:
  **PASS**. No se necesitó cambiar ni volver a publicar la aplicación.

Evidencia local: `CRM-Avance-Corp/app/artifacts/citas-e2e-20260927/` contiene
`cierre.log`, `h5-estabilidad.log`, `foco-final.log`, el parche sobre el release y
las corridas previas (la primera con dos fallos de foco; la segunda con H5
intermitente). [Registro completo aprobado](../../CRM-Avance-Corp/app/artifacts/citas-e2e-20260927/cierre.log).

La ejecución completa de RLS con usuarios de prueba sigue pendiente de una base
local con cuentas y equipos sembrados; los E2E usan backend simulado y no
sustituyen esa matriz. Véase [[E2E del CRM en local con Docker (2026-09-22)]].

Relacionada con [[Citas Gerencia - Métricas, Query y Seguridad]] y [[Gestión Diaria - Permisos y Herramientas por Rol]].
