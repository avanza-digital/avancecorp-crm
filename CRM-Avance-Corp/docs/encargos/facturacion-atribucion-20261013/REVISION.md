# Evaluación de la revisión independiente

13/10/2026. Codex PRIMARY; Claude SECONDARY_REVIEWER, sin herramientas, mediante el wrapper del repositorio. Una revisión válida recibida, después de un fallo de ejecución y un intento interrumpido. Dictamen: CHANGES_REQUESTED, confianza MEDIA. Se revisaron diagnóstico y arquitectura propuesta, no una migración implementada.

## Incorporado con evidencia

- **Origen de la atribución:** investigación adicional confirmó la solicitud por `cartera`, responsable esperado Fiorella y vendedor independiente NULL. La función viva confirma al responsable como vendedor; `inversion-nueva.tsx:518-520` presenta ese responsable. Se añade prevención en el alta, conservando las reglas de venta cruzada.
- **Desgloses:** la rama `desglose` de `capital_episodios` usa el vendedor de `operaciones_cartera`; la de stock usa el vendedor contractual. Se añade un caso de regresión y un rechazo ante resultado no explicado. 001595 tiene cero operaciones de cartera y no se encontraron discrepancias efectivas de este tipo en octubre. No se declara como fallo productivo demostrado.
- **Dos fuentes de atención:** confirmado que contratos heredan desde el asesor del perfil y cooperativas desde la persona. El censo demuestra el caso 001546 desalineado; la vista previa debe usar el núcleo real y el traslado completo debe definir sus postcondiciones.
- **Permisos del portal:** consulta posterior confirmó que Gabriel es admin del portal sin membresía CRM. La nueva operación no puede concederle efectos de Gerencia silenciosamente. Se añade decisión explícita y candado de servidor para la vía directa.
- **Concurrencia:** membresía, jerarquía, persona canónica, tramo, perfil y cadena completa forman parte del estado esperado. Las dos acciones siguen separadas; no se propone una tercera que encadene escrituras del frontend.
- **Corrección puntual:** independiente del rediseño. Existe una puerta auditada, pero no se ejecuta sin autorización para esa escritura productiva.
- **Cooperativas:** se explicita que la puerta de reasignación contractual no corrige sus vendedores.

## Ajustes a recomendaciones del reviewer

- Una diferencia entre registrador y vendedor no demuestra una venta incorrecta ni justifica una alarma automática: son conceptos distintos por contrato de negocio. Se muestra y confirma, no se corrige por heurística.
- No se usará el texto libre del motivo como orden o prueba suficiente para mover ventas. En 001595 existe además la declaración expresa del usuario.
- No se afirmará que un traslado de atención nunca cambia cifras: la herencia de un analista dado de baja puede cambiar la atribución efectiva. Debe aparecer en la vista previa.
- La divergencia del caso 001595 duró aproximadamente **21 horas y 16 minutos**, no 16 horas como calculó el reviewer: 12/10 16:44 → 13/10 13:59 Lima.
- No se actualizará sin más `operaciones_cartera.vendedor_id`: puede ser autoría histórica y exige comprobar el contrato comercial. Primero se valida qué debe seguir a la corrección y se prueba cada rama del núcleo.

## Segunda revisión: implementación

Después de las aprobaciones explícitas del usuario se implementó la candidata y se consultó de nuevo al reviewer mediante el wrapper del repositorio. Segundo dictamen válido: **CHANGES_REQUESTED**, confianza MEDIA; evidencia limitada a los extractos adjuntos, sin acceso a archivos ni herramientas. No se solicitó un tercer review. Codex evaluó los hallazgos y ejecutó los checks; no se interpreta el dictamen como un PASS posterior.

| Observación del reviewer | Decisión y evidencia del PRIMARY |
| --- | --- |
| Inventario incompleto de escritores externos | Aceptada. Revisadas las Edge Functions `crear-cliente`, `crm-convertir-lead`, `importar-clientes` y todo `public_html/js`: las primeras usan RPC de alta; la asignación/edición directa del portal se cambió a las nuevas puertas. Los escritores SQL existentes de baja/F4 conservan su ejecución privilegiada |
| Un GUC no debe ser una capacidad de autorización | Aceptada. `private.atencion_perfil_permitida` comprueba actor activo, destino y alineación real persona/tramo. IF anidados impiden evaluar el helper privado desde un UPDATE authenticated. Prueba de GUC falsificado y ambas columnas de asesor PASS |
| Congelación silenciosa del asesor legado | Aceptada. El núcleo limpia `asesor_id`, la excepción autorizada del trigger lo permite y la postcondición exige NULL. Caso Gerencia con rol de portal analista PASS |
| Alcance/compatibilidad de desgloses | Parcialmente aceptada. Se conserva el rechazo previsto en el plan aprobado cuando stock y desglose quedarían inconsistentes. Caso upgrade y descendiente PASS, sin reescribir autoría del ledger. La firma antigua rechaza alcance ampliado que no pudo mostrar |
| Actor inactivo o destino histórico inactivo | Actor: hipótesis no confirmada, `private.rol_crm` exige equipo y perfil activos; revocación probada. Destino de atención sí debe estar activo. Destino de una corrección histórica conserva la política previa; la herencia se muestra y no se permite éxito sin el cambio efectivo anunciado |
| Candado de actor/destino fuera del bloque de conflicto | Aceptada. Movido al bloque NOWAIT. Dos sesiones PostgreSQL y dos confirmaciones HTTP reales PASS |
| Token incluye todo el equipo | Se conserva como decisión conservadora: puede pedir revisar de nuevo ante un cambio ajeno, sin permitir escrituras desactualizadas. Limitación declarada |

La prueba HTTP posterior encontró un problema adicional verificable que no había cubierto el review: reintentos de PostgREST 14.5 con `40001`. Las puertas ahora traducen el conflicto a `PT409`; se repitió la concurrencia real con éxito. Además se añadió rastro de motivo/autor para atención de un perfil sin persona y se cubrieron foto sellada y cooperativas.

## Estado actualizado del alcance ampliado

Miguel autorizó los cuatro pasos posteriores. Duplicados conservados y gate integral PASS; F4 y baja real PASS; RLS 3.933 PASS; focal local/remoto 83 PASS. La venta real ya fue corregida y verificada. El review de cierre y su evaluación están en [EVALUACION-CIERRE.md](EVALUACION-CIERRE.md); el dictamen de Claude no se convierte en PASS por inferencia.
