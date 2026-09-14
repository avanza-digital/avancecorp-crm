---
fecha: 2026-09-14
estado: preparado
tags: [crm, citas, gerencia, ticket, monedas]
---

# Citas Gerencia — ticket unificado en soles

Miguel confirmó «ok conectalo» para incluir todas las monedas en el ticket y mostrarlo en soles. Después recordó que necesita ver el **total de soles y dólares**. Ambas decisiones se conservan: totales nativos separados en una línea compacta; ticket y cierre proyectado convertidos a soles.

Se cuenta una sola vez cada cliente/identidad aunque tenga dos monedas, varios contratos o perfiles vinculados. La fuente sigue siendo capital real de contratos nuevos de conversiones del mes, atribuido al analista del evento. La proyección mensual y las metas internas 1,25 / 70 / 70 mantienen su lógica.

Se reutiliza `useTipoCambio` y `crm-tipo-cambio`, con corte histórico al fin de mes o fecha de consulta actual, fuente y tasa visibles. Si no hay cotización válida, no se inventa un promedio: se conservan los totales PEN/USD y se deja pendiente lo que requiera conversión. Hay reintento y explicación en el CSV.

Implementado en `78a9a77` sobre Main `faa1059`, en copia persistente separada de las otras sesiones. Gate frontend: 3555 tests PASS. Publicación y verificación final pendientes de acta.

Evidencia: `UX-UI-GERENCIA/citas-ticket-soles-2026-09-14/README.md`.
Relacionado: [[Citas Gerencia - decisiones finales para publicar 2026-09-14]], [[Main unico - sincronizacion y publicacion 2026-09-04]].
