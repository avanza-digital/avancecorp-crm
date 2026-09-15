---
fecha: 2026-09-15
estado: local-verificado-sin-publicar
tags: [crm, citas, gerencia, deposito]
---

# Citas Gerencia — nombre de la etapa Depósito

Miguel pidió que la etapa posterior a Entrevistas se llame **Depósito**. Se actualizan el encabezado del avance mensual, sus etiquetas accesibles, el detalle por analista, la ayuda y la columna «Depósito %» del CSV.

Es un cambio de presentación: el depósito se sigue identificando cuando la persona se convierte en cliente. Se conservan las metas, fórmulas, fuentes, atribución y datos existentes; no se modifica SQL ni se publica en esta tarea.

Verificación: `npm run check` PASS (3605 pruebas, lint, tipos, build y gates incluidos); los tres recorridos existentes de `citas-avance-mensual.spec.ts` PASS, con sus selectores actualizados al nombre nuevo. Captura de escritorio inspeccionada. LEVEL 1: sin revisión secundaria. Verificación de producción NOT RUN: cambio local de textos. Logs en `_dev_artifacts/citas-ticket-soles/deposito-{check,e2e}-20260915.log`.

Relacionado: [[Citas Gerencia - decisiones finales para publicar 2026-09-14]], [[Citas Gerencia - ticket con todo el capital del mes 2026-09-15]], [[Citas Gerencia - ticket unificado en soles 2026-09-14]].
