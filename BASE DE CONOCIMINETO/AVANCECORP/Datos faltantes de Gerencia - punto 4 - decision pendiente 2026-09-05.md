---
tags: [crm, gerencia, metricas, requerimiento, decision]
requerimiento: REQ-GER-MET-001
punto: 4
fecha: 2026-09-05
estado: alcance-n1-a-n4-aprobado-sql-exacto-pendiente
---

# Datos faltantes de Gerencia — punto 4

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]], [[Inventario de indicadores de Gerencia - Contrato de lectura]] y [[Publicacion frontend metricas Gerencia 2026-09-04]].

## Mandato, aprobación y siguiente puerta

Miguel pidió desarrollar y auditar los puntos 4–5 y, al terminar, hacer commit de todo. La solicitud **no incluye otro deploy**. Se revisó Main `9b09efa`, inicialmente limpio, y el servidor real; no se ha aplicado SQL ni modificado ningún núcleo.

Después de recibir la explicación comercial de N1–N4, Miguel respondió el 5 de septiembre: «ok GO, como lo haras dame el plan por fase, y el objetivo final de esto para decir que ya quedo al 100%». **El alcance de las cuatro ampliaciones está aprobado; no volver a pedir esa aprobación conceptual.** Las propuestas que siguen quedan como alcance aceptado, pendiente de concretar y verificar técnicamente. Una aprobación conceptual no sustituye mostrar el SQL exacto y recibir confirmación antes de aplicarlo, ni autoriza por sí sola otro deploy. Plan y definición de cierre: [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]]. Se conserva el nombre histórico de esta nota para no romper enlaces.

## N1 · Personas recibidas que realmente tuvieron cita

- **Pregunta comercial:** de los leads que llegaron en el rango, ¿cuántos tuvieron al menos una cita registrada como realizada, hasta el momento consultado?
- **Dato actual insuficiente:** `metricas_conversiones_fn.cohorte.reuniones_realizadas` es avance inferido: propuesta o cierre también activan esa señal. `metricas_reuniones_fn` cuenta eventos por fecha prevista y no está recortada por el lote de llegada.
- **Evidencia real:** lote 1–4 de septiembre: 243 llegadas y 25 señales de reunión/avance. Una sonda de sólo lectura que cruza las llegadas de `private.conversion_episodios` con las citas clasificadas de `private.citas_episodios` encontró **4 personas con cita real (4 eventos)** hasta el corte `2026-09-05 05:07:19 UTC`. Las 5 citas realizadas de la pantalla Citas pertenecen a otra población. No sustituir 25 por 5.
- **Necesidad técnica:** una proyección de los dos conjuntos canónicos, por `lead_id`, con deduplicación de personas; llegada atribuida al primer analista y asistencia basada exclusivamente en la bandera del núcleo de citas. No inferirla de la etapa ni reconstruirla a partir del listado parcial del navegador.
- **Propuesta si se aprueba:** añadir un bloque explícito a la respuesta existente de Conversiones, separado del embudo inferido: alcance de llegada, corte de seguimiento, leads con cita real y detalle por el mismo primer analista/origen. No cambiar los campos existentes ni el porcentaje principal. El número de eventos debe quedar separado del de personas.
- **Alternativa sin ampliación:** conservar «Reunión o avance posterior» en Conversiones y usar Citas para los eventos reales, con sus fechas declaradas. Es la alternativa ya publicada; no contesta la pregunta nueva.
- **Impacto/aprobación:** ampliación de respuesta y consumidores, sin cambios de núcleos ni permisos. Acordar primero el dato y su corte; después SQL exacto, prueba aislada y confirmación.

## N2 · Fracción correcta de realización por modalidad

- **Pregunta comercial:** ¿cuántas citas se realizaron de las que realmente se computan para ese porcentaje?
- **Dato actual insuficiente:** la modalidad contiene `debieron_ocurrir` bruto y el porcentaje correcto, pero no todas las exclusiones vencidas que forman su divisor. No se puede imprimir el bruto como denominador ni deducir un entero dividiendo un porcentaje redondeado.
- **Evidencia real del 1–4 de septiembre:** virtual: 21 pactadas/vencidas, 4 realizadas, 4 canceladas por sistema vencidas y ninguna reprogramada vencida; divisor **17**, porcentaje servido **23,5 %**. Presencial: 7 computables y 1 realizada, **14,3 %**. Las canceladas siguen dentro de pactadas. Asistencia y realización no son el mismo porcentaje.
- **Necesidad técnica:** `private.metricas_reuniones_implementacion` ya calcula `canceladas_sistema_vencidas` y `reprogramadas_vencidas` en `modalidad_base`, pero no las proyecta al JSON de cada modalidad. La fachada `crm.metricas_reuniones_fn` sólo autoriza y filtra el desglose de responsables; no las añade.
- **Propuesta si se aprueba:** exponer el divisor ya calculado y sus exclusiones en la respuesta existente, conservando los porcentajes del servidor. No crear otra fórmula ni volver a contar estados en el frontend. Si se modifica el agregador existente, sólo su proyección JSON; el núcleo `private.citas_episodios` permanece idéntico.
- **Alternativa sin ampliación:** porcentaje servido y explicación de sus exclusiones, sin «4 de 21». Es la alternativa publicada; no proporciona la fracción completa.
- **Impacto/aprobación:** contrato aditivo con compatibilidad frente a la respuesta anterior; faltante no significa cero. Requiere aprobación de ampliación y SQL exacto antes de aplicarse.

## N3 · Qué operación aportó realmente a la conversión

- **Pregunta comercial:** ¿cuál renovación o upgrade fue contabilizado y cuánto aportó?
- **Dato actual insuficiente:** `operaciones_cartera.elegible_conversion` informa elegibilidad, no elección. El núcleo elige antes de recortar por rango o analista. Un segundo registro elegible no recibe otro aporte por aparecer solo en un filtro.
- **Evidencia real:** entre el 1 de agosto y el 4 de septiembre, seis combinaciones cliente/mes tienen varias operaciones elegibles; existen siete registros elegibles adicionales. Son cifras de ese rango, no una reproducción del corte histórico más amplio del informe inicial.
- **Necesidad técnica:** `private.conversion_episodios` ya devuelve `operacion_id`, `analista_id`, `fecha_numerador` y `aporte_numerador` para la operación elegida. Ninguna respuesta actual del listado de Cartera entrega esa selección por operación. Renovación usa el peso canónico del referido; upgrade conserva 1.
- **Propuesta si se aprueba:** proyectar la identidad y aporte efectivo desde los episodios en una respuesta existente apropiada, declarando período y atribución. Unir esos resultados al listado por ID, sin repetir en la pantalla `row_number`, pesos ni reglas de elegibilidad. Diferenciar «no elegida en el período» de «información de aporte no disponible» y no confundir lectura viva con fotografía mensual sellada.
- **Alternativa sin ampliación:** «operación registrada/elegible» y regla general, sin prometer aporte individual. Ya está publicada; no contesta cuál fue elegida.
- **Impacto/aprobación:** respuesta aditiva dentro del ámbito ya autorizado. No exponer el núcleo privado al navegador ni ensanchar visibilidad por unir IDs. Requiere acuerdo y SQL exacto.

## N4 · Cierres por la semana en que ocurrieron

- **Pregunta comercial:** ¿cuántos cierres consiguió el equipo cada semana, aunque esos leads hayan llegado antes?
- **Dato actual insuficiente:** `responsables[].tendencia_semanal` agrupa por semana de llegada y sigue sus resultados hasta hoy. `crm.series_comerciales_fn` sí usa la fecha del episodio de cierre, pero sólo publica meses y tiene otro ámbito (leads activos y canales operativos); no entrega una serie semanal comercial equivalente.
- **Necesidad técnica:** la fecha real ya existe en `private.conversion_episodios.fecha_numerador`; no hay una respuesta semanal adecuada que pueda conectarse directamente. Reagrupar los cierres del núcleo por esa fecha es una proyección, pero es nueva y debe acordarse. No repartir un total mensual entre semanas ni fecharlo con el alta del lead.
- **Propuesta si se aprueba:** añadir a una respuesta existente de Conversiones una serie por bloques semanales del rango, indicando sus límites, autor del cierre y fuentes comerciales. Separar el número de cierres de leads del aporte ponderado y de operaciones de Cartera; no reemplazar la serie de maduración por llegada ni reabrir fotos selladas.
- **Alternativa sin ampliación:** «Resultados por semana de llegada · cerraron hasta hoy». Es correcto y está publicado, pero no mide productividad por semana de cierre.
- **Impacto/aprobación:** contrato aditivo y gráfico rotulado sin calculadora nueva; requiere acuerdo del alcance temporal y SQL exacto antes de aplicar.

## Evidencia y límites

- Catálogo y definiciones reales leídos en transacciones `begin read only` / `rollback`, con límite de 15–20 s; sin datos personales, semillas, cambios de Auth ni escrituras comerciales.
- Se inspeccionaron las fachadas reales, sus agregadores, `series_comerciales_fn`, el núcleo de llegada/cierre/operaciones y el núcleo de citas. Los contratos frontend actuales tampoco declaran estos cuatro resultados exactos.
- Las sondas N1–N3 son consultas de auditoría, **no nuevas fuentes para la aplicación** ni calculadoras persistentes. Sus cifras son evidencia de su corte y no valores que deban codificarse en una pantalla.
- La auditoría del contrato previo ya se ejecutó. El cierre integral con indicadores ampliados debe verificar su implementación; el alcance ya está aprobado, pero todavía no hay SQL exacto confirmado ni campos nuevos implementados que certificar.
