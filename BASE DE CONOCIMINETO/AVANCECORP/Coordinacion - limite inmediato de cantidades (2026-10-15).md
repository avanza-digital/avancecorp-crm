# Coordinación — límite inmediato de cantidades

Miguel pidió impedir escribir cantidades que excedan los pendientes disponibles: si hay 90 y ya preparó 60, el resto de destinos comparte los 30 restantes.

La planilla descuenta lo preparado para otros supervisores del mismo origen y limita la celda editada al saldo. El aviso explica el ajuste; no cambia las otras celdas. Reducir o vaciar libera cupo. Landing, Formulario y Formulario 3 mantienen disponibilidades independientes, respetando las fechas de ingreso seleccionadas. Se muestra también el saldo sin preparar por origen.

El borrador no reserva leads en el servidor. Si otra persona reparte y se actualiza la cola, se conservan las cantidades para corregirlas y se bloquea la revisión mientras excedan el nuevo saldo. Permanecen la relectura previa, la confirmación explícita y las validaciones atómicas de la RPC.

Estado: corrección preparada y verificada, pendiente de integrar/publicar. La versión publicada de la planilla sigue siendo PR #296, commit 875054a2; la corrección no está todavía en producción. No se modifican asignaciones, n8n, SQL ni permisos.

Validación: gate integral PASS (6.952 tests, lint, TypeScript, cobertura, build y bundle); después se agregó una regresión de reducción externa de disponibilidad y pasaron 24/24 pruebas focalizadas. Docker E2E: 5/5, incluyendo escritura y flechas con 90 pendientes entre tres supervisores y dos orígenes. Suite E2E completa del CRM NOT RUN; alcance de planilla ejecutado. Se reutilizó el gate de realidad de solo lectura del mismo día (22:09 UTC, 0 errores; divergencias preexistentes ajenas al reparto).

Claude: PASS. Se incorporaron las recomendaciones de cobertura para disponibilidad reducida externamente, filtros de supervisor y saldo por origen. Se mantiene el cero explícito al no quedar cupo, y la interpretación de borradores locales válidos; no se amplía el cambio a entradas numéricas parciales propias del navegador, que no permiten sobre-reparto. El reviewer Codex recomendó el límite calculado desde el borrador vigente; aplicado dentro de la actualización funcional.

Figma actualizado y verificado visualmente: [Planilla](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=52-34). Evidencia técnica en `CRM-Avance-Corp/docs/plans/planilla-reparto/LIMITE-CANTIDADES.md`.

Relacionados: [[Coordinacion - planilla de reparto y equilibrio por fechas (2026-10-15)]], [[Reparto de Leads]].
