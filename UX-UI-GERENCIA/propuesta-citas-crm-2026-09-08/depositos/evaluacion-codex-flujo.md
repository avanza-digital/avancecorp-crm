# Evaluación de la corrección del flujo — 8 septiembre 2026

Codex PRIMARY, único escritor. Claude SECONDARY_REVIEWER mediante `scripts/claude-review`, sin herramientas ni delegación. Una consulta con código saneado y constancia de que CodeGraph no localiza estos símbolos del prototipo. Alcance: lógica significativa de un ejemplo local; sin ejecución de pagos, datos reales o backend.

El dictamen recibido fue **CHANGES_REQUESTED**. No se solicitó otra revisión para obtener conformidad. La decisión final se basa en el requisito del usuario y en las verificaciones del PRIMARY.

## Hallazgos y decisiones

1. **P2, asistencia solo en el último nodo: aceptado y corregido.** `seguimientoInasistencias` conserva ahora `recorrido`. `depositosDeInasistencias` busca asistencia real válida en toda la cadena. La prueba «conserva la asistencia y el depósito aunque exista una nueva cita posterior» reproduce una asistencia intermedia seguida por una cita pendiente y mantiene 1 → 1 → 1 → 1.
2. **P2, origen dependiente del orden: aceptado parcialmente.** Base y reprogramación tienen desempate por fecha e id; asistencia desempata por instante real, origen e id. La prueba «elige el mismo episodio de cada etapa aunque cambie el orden de las inasistencias» verifica estabilidad. No se obliga a usar el mismo objeto de origen cuando son episodios independientes: cada etapa muestra una cadena que cumple su condición; forzar el primer episodio sin vínculo descartaría recuperaciones válidas de otro episodio filtrado o inventaría un enlace. La unidad común entre etapas es el id del lead.
3. **P3, atribución a primera asistencia: no se cambia la regla de cohorte.** El indicador responde cuántos leads completaron los pasos, no qué cita causó cada depósito. Los movimientos son posteriores a una asistencia válida de una cadena filtrada, hasta el corte. El detalle conserva esa cadena y la guía no afirma causalidad o atribución por ciclo. Una futura atribución por cita requeriría un contrato distinto.
4. **P3, fixture no adjunto: limitación del material revisado, verificada por el PRIMARY.** La prueba del ejemplo importa los fixtures completos y exige 4 → 3 → 1 → 1, base 4, 25%, PEN 35.000 y USD 0. `DEP-002` permanece en los datos pero no califica. La comprobación real en Chrome confirma los mismos valores y Andrea como única depositante del flujo.

## Gate final

- PASS: lint (cuatro advertencias previas en `coverflow-carousel.tsx`), typecheck, suite general (3.098 tests en 216 archivos) y build (avisos previos de chunks y `demo-config.ts`). Se ejecutaron después de las correcciones del review.
- PASS: Chrome, etapas 4 → 3 → 1 → 1, base de conversión visible, filtro Ana 1/1, Diego 0/1, apertura/cierre de ficha y fechas en orden. Sin desbordamiento a 390 y 1.227 px CSS; sin errores de consola capturados. Viewport restablecido.
- NOT RUN: segundo review (no necesario para resolver los hallazgos con evidencia), `check:all`, matriz completa de dispositivos/lector de pantalla y datos reales. Sigue siendo una propuesta local con fixtures.

La corrección de tipos de las pruebas elimina propiedades opcionales con `delete`; no permite `undefined` explícito para evadir `exactOptionalPropertyTypes`.
