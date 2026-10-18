# Resolución de la revisión de fase 3

Codex PRIMARY. Primer review: `revision-claude.txt`, CHANGES_REQUESTED, sin P0/P1. Se aceptan los hallazgos respaldados por evidencia; no se cambia el producto para alterar las reglas comerciales.

| Hallazgo | Decisión y comprobación |
|---|---|
| P2: recibo importado → duplicado tras confirmación perdida | Aceptado y documentado. Ejecuciones 49/50 prueban ausencia de doble alta. Las cifras de altas de campaña salen de CRM, no de sumar recibos `importado`. |
| P2: falta estado productivo n8n | Aceptado. Exportación e historial en `n8n-estados.json`. Se encontró selección temporal en el principal y se restauró la referencia original. Diff final vacío frente a versión anterior. Flujo apagado y recibos 0. |
| P2: errorWorkflow fuera del generador | Corregido en el generador de ensayo, mediante modo `preparado`, con ID y cron utilizados. Comparación real: 22 nodos, 26 conexiones y ajustes PASS; el modo predeterminado mantiene HTTP deshabilitado. No publica automáticamente. |
| P2: conversión solo divisor | Completado. Seis casos HTTP/Auth/Storage reales; dos cierres por la puerta vigente `preparar_inversion_fn` + `confirmar_inversion_revisada_fn`. Cada uno aporta numerador 1/divisor 1. Evidencia `conversion-real.json` y `conversion-numerador.json`. |
| P3: límite de avisos | Documentado como agrupación por hora de reloj, sin promesa de exclusión atómica o ventana móvil. No se añadió un canal alternativo que el usuario no pidió. |
| P3: rechazos ante cambios de parser | Procedimiento documentado: exportar/revisar/retirar solo rechazos afectados, con envío parado, y reintentar. |
| P3: reintentos 4xx | Sin cambio obligatorio; comportamiento ya probado y acotado. |

Gaps: se agregó reconocimiento/reingreso por HTTP real para ambas variantes; solicitud de cliente sin ficha viva y ficha cerrada/viva quedan respaldadas por los bloques SQL exactos y sus logs remotos (36 + 1). No se afirma ensayo remoto del 5xx/timeout específico ni Error Trigger causado por fallo de recibo; son límites explícitos y no impiden acreditar la recuperación y el aviso automático del objetivo mediante los casos ejecutados.

Seguridad y limpieza: archivo de secretos retirado; rama eliminada, hoja/tablas eliminadas y flujos archivados. La entrada de credencial temporal queda inservible y fuera del principal; no hay herramienta MCP de borrado. Los JSON de usuarios/respuestas se revisaron: contienen únicamente fixtures, sin valores privados. Retención productiva de errores se fija antes de activar.

Gate de realidad: permanece FAIL original, con complemento SQL de solo lectura para ambas mediciones. El reviewer confirmó que no invalida el ensayo aislado. Reparación/enmienda formal requerida para fase 4. Las divergencias de datos ajenas no se modifican.

Una segunda revisión dirigida se justifica por la nueva evidencia de credencial en el principal y su restauración, más la conversión real añadida. No se repite la pregunta inicial buscando un PASS. Se adjuntan estados/diffs y logs, no solo prosa.

## Segunda revisión dirigida y decisión final

`revision-cierre-claude.txt`: CHANGES_REQUESTED, sin P0/P1. Se conserva el dictamen tal como fue emitido; las resoluciones siguientes son del PRIMARY, sin una tercera consulta.

| Hallazgo | Resolución y límites |
|---|---|
| P2: línea base autosalvada sin comparación nominal | Se agregó el diff completo `cbc1ce82 → 95f649de` y la definición de Schedule Trigger: 21 nodos con omisiones de parámetros/objetos vacíos del autosave, sin cambios de credenciales ni conexiones; el intervalo omitido conserva su valor predeterminado de 5 minutos. No se llama vacío a ese diff. Los settings históricos no están expuestos por el MCP: se acredita igualdad de los actuales con la captura previa a restaurar y se declara el límite. `n8n-cierre.json`. |
| P2: historial posterior a restauración | Se volvió a leer: `95f649de` es la última versión; original asignada, envío deshabilitado y flujo inactivo. Se indicó recargar/cerrar pestañas antiguas. Volver a verificar historial, credencial y ajustes es condición expresa de fase 4; no se presume observación del navegador. |
| P2: primer reingreso Legacy ya existente | Fue una corrida parcial anterior: preparó la persona y anotó el reingreso; luego falló porque el fixture omitía la referencia obligatoria del certificado. Se repitió tras corregir ese fixture conservando el lead. LEEME explica la asimetría y la sobrescritura del primer artefacto. El script ahora registra resultados de alta para futuras ejecuciones; la evidencia histórica no se rellena retrospectivamente. |
| P3: procedencia de la consulta del numerador | Se añadió `conversion-numerador.sql`, equivalente reconstruida a partir de la respuesta y las fuentes. Se indica que no es transcripción exacta ni nueva ejecución tras el retiro. La respuesta conservada demuestra numerador/divisor 1/1 en ambas variantes. |
| P3: IDs retirados en modo preparado | Aviso en generador y LEEME: son IDs históricos para auditar la configuración; repetir requiere recursos nuevos. |
| P3: nombre antiguo del aviso productivo | Añadido a fase 4: probar su trigger y guardar una versión nominal con nombre actualizado; no se modifica ahora el flujo de avisos productivo. |

Decisión: objetivo de fase 3 acreditado por recorrido, fallos, recuperación, aviso automático, roles y paridad comercial. Se cierra el ensayo aislado con los límites anteriores. El gate de publicación permanece FAIL original; cierre de fase 3 no equivale a aprobación de despliegue. La eliminación de la entrada inerte de credencial se registra conforme al resultado de la comprobación, sin convertir la confirmación de pantalla en evidencia API de ausencia.


## Cierre posterior de la credencial

Miguel borró la entrada temporal y su ausencia se verificó por MCP. Se materializó el riesgo del autosave que Claude había señalado: versión UI `907688a7` volvió a referenciar la temporal. Tras confirmar el cierre de pestañas, Codex repuso exclusivamente la original; versión `29940eb5-d36c-49c7-bf7f-686b66cc3f76`, diff vacío y ajustes iguales frente a la primera restauración, con los tres controles de envío cerrados. `cierre-credencial.json` documenta el resultado. Se aplica la recomendación previa, sin una tercera revisión ni cambios funcionales.
