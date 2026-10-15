# Límite de cantidades al preparar reparto — 15/10/2026

El `onChange` permitía introducir un exceso y solo la validación posterior impedía revisar. Ahora el máximo de cada celda es la disponibilidad filtrada de su origen menos lo preparado para otros supervisores. Se aplica en la actualización funcional, además del atributo `max`; escribir, pegar o aumentar con flechas no acumula más de la cola disponible. La propia cantidad anterior queda excluida del descuento para poder editarla. Un ajuste muestra aviso y deja los demás destinos intactos.

Las cantidades siguen siendo un borrador local: no hay reservas ni asignaciones hasta confirmar. Se conservan relectura, validación del plan y rechazos atómicos del backend frente a cambios concurrentes. Si una actualización reduce la cola, el borrador permanece visible y se bloquea revisar hasta corregirlo.

## Verificación

- PASS: `npm run check`: 432 archivos, 6.952 tests, lint/TypeScript/cobertura/build/bundle/duplicación.
- PASS después de ampliar regresiones sugeridas por Claude: 24/24 focalizadas (componente y lib).
- PASS: `npm run test:e2e:docker -- e2e/planilla-reparto.spec.ts --workers=2`: 5/5. Incluye saldo 90, independencia de origen, conservación de otras celdas, flechas del campo, liberación al reducir y revisión de 90 IDs sin ejecutar RPC de reparto.
- PASS: regresiones de pegado, valores negativos/decimales/exponentes, número enorme, fechas, cero disponible, borrado, filtro de supervisores, disponibilidad reducida externamente.
- PASS: Figma actualizado, revisión visual sin recortes.
- NOT RUN: E2E completo del CRM; se ejecutó el banco afectado.

## Revisión independiente

Claude PASS, con recomendación P2 de ampliar la cobertura de recuperación tras reducir la cola: aplicada. También se verifican saldo por origen y máximo después del filtro de supervisores. Las recomendaciones P3 opcionales de mostrar vacío en lugar de cero o normalizar borradores por otra vía no cambian este contrato: el único editor exige enteros, los borradores no se persisten y la validación final se mantiene. Las entradas parciales de `type=number` son un comportamiento preexistente del navegador; no habilitan sobre-reparto.

Dictamen íntegro en `REVISION-CLAUDE-LIMITE.md`. Agente Codex read-only revisó los casos límite; PRIMARY implementó y verificó. Sin cambios de backend, permisos ni leads de producción.
