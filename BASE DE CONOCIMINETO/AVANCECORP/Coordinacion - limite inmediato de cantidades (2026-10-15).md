# Coordinación — límite inmediato de cantidades

Miguel pidió impedir escribir cantidades que excedan los pendientes disponibles: si hay 90 y ya preparó 60, el resto de destinos comparte los 30 restantes.

La planilla descuenta lo preparado para otros supervisores del mismo origen y limita la celda editada al saldo. El aviso explica el ajuste; no cambia las otras celdas. Reducir o vaciar libera cupo. Landing, Formulario y Formulario 3 mantienen disponibilidades independientes, respetando las fechas de ingreso seleccionadas. Se muestra también el saldo sin preparar por origen.

El borrador no reserva leads en el servidor. Si otra persona reparte y se actualiza la cola, se conservan las cantidades para corregirlas y se bloquea la revisión mientras excedan el nuevo saldo. Permanecen la relectura previa, la confirmación explícita y las validaciones atómicas de la RPC.

Estado: corrección preparada y verificada, pendiente de integrar/publicar. La versión publicada de la planilla sigue siendo PR #296, commit 875054a2; la corrección no está todavía en producción. No se modifican asignaciones, n8n, SQL ni permisos.

Validación: gate integral PASS (6.952 tests, lint, TypeScript, cobertura, build y bundle); después se agregó una regresión de reducción externa de disponibilidad y pasaron 24/24 pruebas focalizadas. Docker E2E: 5/5, incluyendo escritura y flechas con 90 pendientes entre tres supervisores y dos orígenes. Suite E2E completa del CRM NOT RUN; alcance de planilla ejecutado. Se reutilizó el gate de realidad de solo lectura del mismo día (22:09 UTC, 0 errores; divergencias preexistentes ajenas al reparto).

Claude: PASS. Se incorporaron las recomendaciones de cobertura para disponibilidad reducida externamente, filtros de supervisor y saldo por origen. Se mantiene el cero explícito al no quedar cupo, y la interpretación de borradores locales válidos; no se amplía el cambio a entradas numéricas parciales propias del navegador, que no permiten sobre-reparto. El reviewer Codex recomendó el límite calculado desde el borrador vigente; aplicado dentro de la actualización funcional.

Figma actualizado y verificado visualmente: [Planilla](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=52-34). Evidencia técnica en `CRM-Avance-Corp/docs/plans/planilla-reparto/LIMITE-CANTIDADES.md`.

Relacionados: [[Coordinacion - planilla de reparto y equilibrio por fechas (2026-10-15)]], [[Reparto de Leads]].

## PR299 fusionada; paquete preparado, dependencia pendiente

Comprobación 15/10/2026 23:48–23:51 UTC: PR299 fusionada en `81480ebb475fc61b4a19f5b2cb17f30da88df815`; Main local y remoto iguales al construir. La PR298 ya estaba fusionada (`05c19efc`, 23:34 UTC) y viene incluida. El código de la planilla es idéntico al revisado; los cambios de PR298 requieren backend previo.

Main combinado: `npm run check` PASS, 433 archivos / 6.966 tests; E2E Docker de planilla, reparto, Coordinación-reportes y cartera/categoría 44/44 PASS. Artefacto verificado y preflight de ascendencia PASS: `crm-20261015T234847Z-81480ebb475f.zip`, SHA-256 `b59f6a93a29ebc245dd967dc2de2395e53920de58b8095ecfb3be2f0904ca2fe`. Esto NO acredita compatibilidad de backend ni publicación.

Consulta productiva READ ONLY: ninguna de las migraciones `20261015211217`, `20261015212939`, `20261015224848` está en el ledger; tampoco existen `crm.correcciones_categoria_contrato`, `private.es_coordinacion_consulta()` ni `private.operaciones_cartera_clasificadas()`. Las actas de PR298 las declaran pendientes, junto con matriz HTTP/Auth y gate de realidad. Reviewer Codex confirmó dependencia real sin feature flag.

**NO publicado.** Sigue vivo `build-20261015T225912394Z` / `875054a2`. No se tocó Hostinger ni se ejecutó SQL de escritura. Se conserva el paquete anterior y el candidato. Hace falta completar el ciclo backend autorizado de PR298 antes de desplegar Main; no publicar una rama alternativa ni omitir los cambios fusionados. Miguel indicó que no veía PR298; se le pasó enlace y se explicó que está entre fusionadas. Figma actualizado con este estado.

Relacionado: [[Coordinacion - cartera, leads y correccion de categoria (2026-10-15)]].
