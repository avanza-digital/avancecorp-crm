---
fecha: 2026-09-14
estado: publicado-verificado
tags: [crm, citas, gerencia, ticket, monedas]
---

# Citas Gerencia — ticket unificado en soles

Miguel confirmó «ok conectalo» para incluir todas las monedas en el ticket y mostrarlo en soles. Después recordó que necesita ver el **total de soles y dólares**. Ambas decisiones se conservan: totales nativos separados en una línea compacta; ticket y cierre proyectado convertidos a soles.

Se cuenta una sola vez cada cliente/identidad aunque tenga dos monedas, varios contratos o perfiles vinculados. La fuente sigue siendo capital real de contratos nuevos de conversiones del mes, atribuido al analista del evento. La proyección mensual y las metas internas 1,25 / 70 / 70 mantienen su lógica.

Se reutiliza `useTipoCambio` y `crm-tipo-cambio`, con corte histórico al fin de mes o fecha de consulta actual, fuente y tasa visibles. Si no hay cotización válida, no se inventa un promedio: se conservan los totales PEN/USD y se deja pendiente lo que requiera conversión. Hay reintento y explicación en el CSV.

Implementado en `78a9a77` sobre Main `faa1059`, en copia persistente separada de las otras sesiones. Gate frontend: 3555 tests PASS. 7 E2E PASS. Publicado y verificado: build `build-20260914T211412536Z`, artefacto de Main `32d57b5`, 67/67 recursos ejecutables y documentos coincidentes por HTTP. Se conserva como reversa inmediata la entrega de Tasas `faa1059`, publicada justo antes. Acta: `UX-UI-GERENCIA/citas-ticket-soles-2026-09-14/PUBLICACION.md`.

Evidencia: `UX-UI-GERENCIA/citas-ticket-soles-2026-09-14/README.md`.
Relacionado: [[Citas Gerencia - decisiones finales para publicar 2026-09-14]], [[Main unico - sincronizacion y publicacion 2026-09-04]].

## Cierre de sesión — 14/09/2026

Miguel pidió «ok guarda todo y cierra sesion». El trabajo de Citas queda terminado,
publicado y guardado: implementación `78a9a77`, verificación `32d57b5` y acta
`57883a4`. Se integró también el cierre documental de Tasas `82fc98d`, que conserva
la versión publicada de Citas. No hay cambios propios de código pendientes ni
pruebas o despliegues de esta tarea en curso.

El ZIP publicado, su manifiesto y la reversa inmediata permanecen en
`CRM-Avance-Corp/releases/`; la copia persistente y los logs de esta sesión están
en `_dev_artifacts/citas-ticket-soles/`. Se conservan sin incorporar los cambios
de F8/COOPAC y los archivos ajenos presentes en la carpeta compartida. Al retomar,
consultar Main/remoto y esta nota antes de hacer nuevos cambios.
