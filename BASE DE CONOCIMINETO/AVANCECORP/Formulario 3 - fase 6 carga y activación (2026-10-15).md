# Formulario 3 — fase 6, carga y activación

15/10/2026. Estado: **COMPLETADA; carga conciliada y programación activa cada cinco minutos**.

Relacionado: [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]] · [[Formulario 3 - fase 4 publicada y verificada (2026-10-14)]] · [[Canales de origen de leads CRM]] · [[Carga de leads desde hoja de Google]].

Se procesaron 126 pendientes: 94 altas y 32 duplicados. Con el piloto, hay 95 altas y 127 recibos. CRM 3.688 → 3.782; veinte comprobaciones por alta, sin asignación humana, y 95 visibles para Coordinación mediante su lector SQL autorizado. No hubo rechazos ni pendientes. La repetición 63 no hizo POST ni cambió recibos o leads.

Seis contactos tenían registros históricos cerrados (descartados/convertidos). La puerta vigente admite una nueva entrada en esos casos; el índice único afecta únicamente a leads abiertos. Se conservaron los históricos y sus responsables, sin reclasificar contactos existentes. Hubo una pausa de conciliación tras el primer lote para distinguir correctamente estas entradas.

Ciclos programados 64 y 65, 06:20/06:25 UTC, SUCCESS: 127 filas, cero pendientes y cero POST. La observación se prolongó: historial de 91 ciclos SUCCESS hasta 13:50 UTC. La ejecución 153 aún reconoció las mismas 127; 154 detectó 25 nuevas y produjo 21 altas y 4 duplicados. Foto actual: 152 recibos, 116 altas de campaña, 36 duplicados, cero pendientes/rechazos. Los datos y recibos iniciales no cambiaron. Veinte controles por cada alta adicional también PASS. Coordinación ve los 116. Retención de éxitos restaurada a none a las 13:51 UTC; mismo código y versión activa. 41 tests y validación MCP PASS.

Claude revisó dos veces; se aplicaron controles de configuración y relectura. Revisión final PASS. El generador operativo es cargarDefinicionOperativa() de formulario3.fase6.mjs; no volver al generador histórico sin aplicar fase 6.

[Acta técnica y procedimiento de recuperación](../../CRM-Avance-Corp/docs/N8N-FORMULARIO3-FASE6.md). [Plan en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).

Siguiente, terminado el plan principal: adaptar Supervisores dentro de Coordinación, sin cambiar el turno FORMULARIO. Miguel lo difirió expresamente hasta terminar el plan principal.
