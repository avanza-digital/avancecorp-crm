---
estado: 🟡 PREPARADA, SIN PUBLICAR — espera el visto bueno de Miguel
fecha: 2026-10-21
---

# n8n — Formulario 3 fase 8: la fila a medio escribir

**Qué pasó.** El 21/10 a las 08:30 (Lima) el importador «Avance Corp — Formulario 3 → CRM» (`BjI5m1PKVWhO0NDb`, ejecución 1883) avisó «Revisar filas de la hoja: 277–281 (rechazadas)». Las cinco filas tenían **solo la fecha**: la hoja FORMULARIO 3 se escribe por tandas y la vuelta la leyó a medias (la hoja terminó de escribirse a las 08:32). A las 08:35 la vuelta siguiente las leyó completas y **las cinco entraron al CRM**. Nada se perdió; quedaron cinco recibos `rechazado` sin lead detrás, inofensivos.

**Por qué pasa.** El recibo se liga a la huella del contenido leído; una fila que cambia se procesa como nueva. Eso es lo que salvó los leads, pero el rechazo y el correo de la primera lectura eran una falsa alarma.

**Qué cambia (fase 8).** Una fila con solo la fecha, legible y a menos de 48 h de la hora de la vuelta, se omite esa vuelta sin recibo y se juzga en la siguiente; si pasado el margen sigue igual, se rechaza y avisa como siempre. Con cualquier otro dato, una celda rara o una fecha ilegible, la regla de la fase 7 sigue mandando. Solo cambia el código de «Preparar leads».

**Evidencia.** 63/63 tests (`node --test 'scripts/n8n/*.test.mjs'`), 13/13 mutantes muertos, `check:scripts` PASS. Codex (LEVEL 2) pidió un cambio y se hizo: la fila a medio escribir llega sin las demás claves y una lectura hecha solo de ellas frenaba con «Faltan columnas»; ahora la cabecera se valida sobre las filas que no están en escritura. Acta técnica y pasos de publicación: [Acta de fase 8](../../CRM-Avance-Corp/docs/N8N-FORMULARIO3-FASE8.md).

**Aparte.** El 20/10 por la tarde hubo tres `ETIMEDOUT` de la API de Google Sheets en «Leer leads filtrados» (sin `Retry on Fail`). No se toca en esta fase.

Relacionado: [[n8n - auditoria del flujo Formulario 3 (2026-10-15)]] · [[Formulario 3 - fase 6 carga y activación (2026-10-15)]] · [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]] · [[Carga de leads desde hoja de Google]].
