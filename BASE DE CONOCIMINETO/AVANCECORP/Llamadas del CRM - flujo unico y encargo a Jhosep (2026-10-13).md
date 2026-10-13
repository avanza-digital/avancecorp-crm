---
fecha: 2026-10-13
tags: [crm, llamadas, decisiones, coordinacion]
---

# Llamadas del CRM: un solo flujo

Miguel aclaró que las llamadas siempre se hicieron desde el celular. La novedad es mostrar allí la encuesta del
CRM para marcar el resultado. El 13/10 confirmó integrar las pantallas y exigió unificar también registro,
lecturas y conteo, sin un circuito comercial alternativo «desde celular».

F4-e fue publicada y aceptada en C1 por Jhosep con gerencia/supervisor (acta en el #270). Esa aceptación no acredita
todavía la nueva unificación de la propuesta #23.

Codex revisó el código y el plan de #21, corrigió el planteamiento y dejó el contrato de implementación en
`CRM-Avance-Corp/docs/encargos/2026-10-13-llamadas-crm-unificadas.md`. Jhosep/Claude mantiene la escritura de su plan
y de la implementación; Codex valida su entrega. La encuesta ya comparte el núcleo comercial v4: se conserva.

Condiciones: identidad de llamada distinta de id de operación, vínculo exacto o conciliación explícita; reintento
idempotente antes de rechazar una llamada resuelta; orden de bloqueos compatible; contador único sin sumar
captura y actividad ni elegir fuente según el dispositivo. Conservar las fechas de llamada y resultado.
La falta de captura integrada no demuestra falta de llamadas, de teléfono o de trabajo.

Se corrige la recomendación previa de #21: «No contestó» lo declara el analista; no depende de un estado técnico
que la macro actual no entrega. Persisten las exigencias de concurrencia, reintentos, un resultado por llamada,
seguimiento una vez y sin descarte automático al comienzo.

No se modificó ni desplegó código de producto con esta entrega. La definición de contacto conserva sus
exclusiones/cohorte; cambiarla requiere explicar el efecto, no asumir que fue aprobado al quitar una pestaña.

Relacionado: [[Llamadas desde el celular - F4-e aplicada y entrega de pantallas (2026-10-13)]] y
[[Llamadas desde el celular - F4-e migracion preparada (2026-10-12)]].
