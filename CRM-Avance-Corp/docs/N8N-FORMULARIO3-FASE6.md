# Formulario 3 — carga y activación

15/10/2026. Estado: **COMPLETADA; integración activa y comprobada cada cinco minutos**. Cierre operativo: 15/10/2026, 08:51 Lima (13:51 UTC). Codex PRIMARY; Miguel opera las pantallas. No se rediseñó Supervisores de Coordinación: quedó diferido por Miguel hasta después del plan principal.

## Resultado de la carga

La foto inicial tenía 127 filas y 127 huellas distintas. La confirmación de fase 5 se conservó intacta. Se procesaron las otras 126 filas en seis lotes, con el cron apagado.

| Ejecución | Filas | Altas | Duplicados | Clientes reconocidos | Rechazos | Pendientes |
|---|---:|---:|---:|---:|---:|---:|
| 57 | 25 | 23 | 2 | 0 | 0 | 0 |
| 58 | 25 | 15 | 10 | 0 | 0 | 0 |
| 59 | 25 | 23 | 2 | 0 | 0 | 0 |
| 60 | 25 | 12 | 13 | 0 | 0 | 0 |
| 61 | 25 | 21 | 4 | 0 | 0 | 0 |
| 62 | 1 | 0 | 1 | 0 | 0 | 0 |
| **Fase 6** | **126** | **94** | **32** | **0** | **0** | **0** |

Con el piloto de fase 5: **95 leads de campaña y 127 recibos definitivos**. CRM: 3.688 → 3.782. Las altas se cotejaron contra el CRM, no solo contra la respuesta HTTP. Veinte campos/invariantes por alta correctos, sin asignación de supervisor/vendedor ni episodios de reparto creados. La consulta de Coordinación bajo rol SQL authenticated devuelve 95, con origen formulario, importe y comentario de campaña. Esto acredita el lector y sus permisos; no representa un nuevo login de navegador ni una captura humana.

La primera conciliación se detuvo porque comparaba todos los históricos de un teléfono como si fueran leads abiertos. Se apagó el envío antes del segundo lote. El índice vivo `uq_leads_telefono_vivo` exige unicidad solo cuando `activo=true` y la etapa no es convertido/descartado. Los tres casos de ese lote conservaban su histórico cerrado; cada alta nueva pasó los veinte controles. Se corrigió la medición para distinguir históricos y leads abiertos, sin cambiar código comercial ni datos. Los registros previos conservaron su huella completa y responsables después de cada lote. No se observó más de un lead abierto por teléfono.

**63 — repetición completa:** mismas 127 filas/huellas, cero pendientes, HTTP no ejecutado y ningún recibo escrito. Se compararon los recibos completos y las huellas de las filas CRM antes/después: idénticos.

## Configuración y evidencia de operación

- Flujo: `BjI5m1PKVWhO0NDb`. Publicado para revisar cada cinco minutos; lote máximo 25 pendientes, uno por uno.
- Publicación inicial de fase 6: `e2f62a7e-7675-414d-a7b0-b617e2528c72`, 06:17:47 UTC. Guardado exitoso temporal durante la observación; restaurado a `none` a las 13:51:20 UTC. La modificación exclusiva de ajustes conservó versionId/activeVersionId; ambos siguen coincidiendo con esa versión. Relectura y gate completo PASS.
- Tabla de recibos productiva conservada: `1foRUzITWOnUJsNf`. SHA-256 sobre contenido estable; mover una fila no cambia su huella, editarla sí. Coincidencias entre pendientes se deduplican antes de seleccionar el lote.
- Timeout 180 s, intervalo 300 s; se deja de iniciar otra fila tras 100 s. HTTP: 20 s por intento, hasta tres intentos, espera de 1 s. Margen nominal restante: 18 s para confirmar y escribir recibo. Un corte excepcional puede causar reenvío; la puerta del CRM evita duplicar un lead abierto. No se presenta como entrega exactamente una vez.
- No se configuró un límite de concurrencia por flujo: el MCP no lo expone. No ejecutar manualmente mientras opere el cron. Recibos de resultados definitivos dentro del bucle; fallos temporales quedan pendientes; rechazos generan error después de preservar sus recibos.
- Alertas: flujo `4jfthNhVJLiZUeIo` activo, enlazado como `errorWorkflow`, Gmail habilitado y destinatario `miguel@miavance.com`. La ejecución productiva 52 de fase 4 sigue mostrando SUCCESS y etiqueta SENT. El ensayo automático de fase 3 está documentado en su evidencia histórica; no se provocó un fallo productivo nuevo durante fase 6.
- Retención del VPS aplicada por Miguel en fase 5: poda true, 144 h y buffer de 1 h. El cambio posterior a `saveDataSuccessExecution=none` no borra las ejecuciones ya guardadas. Ciclo efectivo de poda: NOT RUN hasta que envejezcan. No se promete borrado forense.

## Fuente reproducible y revisiones

La definición operativa se obtiene con `cargarDefinicionOperativa()` de [formulario3.fase6.mjs](../scripts/n8n/formulario3.fase6.mjs). La función `cargarDefinicion()` del generador previo se conserva como base histórica para las pruebas de fases 1–5. No volver a publicar esa base sin las operaciones de fase 6. Ningún generador publica por sí mismo.

`operacionesFase6` comprueba el grafo completo y los parámetros/credenciales/estados de cada nodo, normalizando únicamente defaults conocidos que omite n8n 2.43.5. `verificarFase6` comprueba la relectura posterior a la escritura. `restaurarRetencion` exige la misma versión activa verificada y emite solo ajustes completos; se vuelve a verificar después de republicar.

Claude: revisión 1 CHANGES_REQUESTED; revisión 2 PASS tras reforzar comparación de nodos, ajustes completos, gate posterior y restauración de retención. Las dudas sobre mapeo inválido y variantes de fase 5 se contrastaron con el código real y pruebas. Se preservó la rama de rechazo en vez de bloquear toda la selección por una fila inválida. La mejora de generador operativo evita reutilizar la base histórica como versión final.

Validación SDK MCP: 22 nodos PASS. 41 pruebas locales específicas, sintaxis y diff: PASS. No hay cambios en frontend, esquema o Edge; no se repitieron build/E2E de producto ni se publicó otro artefacto CRM.

## Recuperación y seguimiento

Ante un fallo, despublicar este flujo para detener nuevos disparos y comprobar la ejecución en curso. Apagar `enviar_crm` y el nodo HTTP antes de otra ejecución manual. Conservar leads, recibos y sus IDs. Investigar con lectura del CRM; reintentar solo las huellas pendientes. No vaciar la tabla de recibos ni borrar contactos para repetir toda la carga.

Las notificaciones dependen de n8n y Gmail; no detectan por sí solas la caída completa del VPS. Se agrupan por hora, sin exclusión atómica. La campaña original no se sustituye en un duplicado existente. El origen comercial y turno siguen siendo FORMULARIO.

## Funcionamiento automático comprobado

- **64 / 06:20:11 UTC** y **65 / 06:25:11 UTC**: modo trigger, SUCCESS, disparador Cada 5 minutos ejecutado. 127 filas, cero pendientes, cero POST y cero recibos reescritos. Intervalo observado: 299,988 s.
- **153 / 13:45:11 UTC**: misma foto y resultado, sin reenvíos.
- Historial observado hasta **154 / 13:50 UTC**: **91 ejecuciones programadas SUCCESS**, sin fallos en ese intervalo. Se consultaron metadatos de las 91 y datos detallados de 64, 65, 153 y 154; no se atribuye revisión detallada a todas.
- **154** detectó **25 filas nuevas** incorporadas después de la foto inicial: **21 altas y 4 duplicados**. Se comprobaron veinte campos por alta, fecha de creación dentro de esa ejecución, un solo lead abierto por teléfono y cuatro duplicados existentes desde antes. Los registros y 127 recibos iniciales permanecen intactos.
- Foto actual: **152 filas y recibos, 116 leads de campaña, 36 duplicados, cero rechazos/pendientes**. Coordinación ve los 116 con origen formulario y comentario de campaña. La cifra global de CRM no se usa para atribuir estas últimas altas: hay otras operaciones de negocio fuera del alcance, y aquí se comprobaron las identidades/fechas concretas.
- Al cierre, ambos workflows siguen activos, con los mismos nodos/credenciales y destinatario. Éxitos `none`, errores `all`, manuales `true`, timeout 180 s y zona America/Lima. Las ejecuciones ya guardadas no se borraron; siguen bajo la poda configurada de 144 h más buffer.

[Evidencia sin datos personales](N8N-FORMULARIO3-FASE6-EVIDENCIA.json). [Plan en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34), actualizado y revisado visualmente. Plan principal completado. Sigue el trabajo diferido de Supervisores dentro de Coordinación.
