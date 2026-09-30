VERDICT: CHANGES_REQUESTED

SUMMARY:
El snapshot ofrece un lugar adecuado para congelar la elección al reservar el PDF, pero el plan aún permite perder una elección durante el despliegue, no define cómo conservarla en una corrección y deja ambigua la reversa de trabajos v10 con anexo.

Con el OK explícito de Miguel para tocar `public`, **prefiero la opción B**. El snapshot ya lee `public.contratos%rowtype`, `public.crear_contrato` inserta los términos y `proteger_contrato_documental` enumera los campos congelados. Una columna evita la tabla lateral, su `upsert`, un trigger y una ruta adicional para consultar la elección. Si Miguel elige A, los controles señalados abajo son necesarios.

FINDINGS:

**[P1] El orden de publicación pierde elecciones y contradice la regla de publicación.**  
Evidencia: D7 admite que, tras publicar el front primero, «un contrato creado en el hueco con la casilla marcada saldría SIN anexo». También coloca «commit en `main`, push `avancecorp main`» después del despliegue; las instrucciones del proyecto exigen publicar un artefacto construido desde el commit verificado de `avancecorp/main`.  
Impacto: puede quedar sellado un PDF contrario a lo elegido y el artefacto publicado carecer de la procedencia exigida.  
Acción: verificar y publicar el commit antes del despliegue; mantener las altas detenidas durante la transición de edge y SQL, y habilitar la casilla solo cuando ambos estén listos.

**[P1] La reversa no preserva necesariamente los PDF v10 pendientes.**  
Evidencia: D5 propone una «edge de reversa (constante v9 que siga LEYENDO v10)»; D4 define el anexo como variante de la plantilla v10. *Hipótesis condicionada:* si esa edge vuelve a renderizar como v9, podrá leer un job v10 con `anexoCronograma:true` y sellarlo sin anexo. Leer `opciones` no garantiza aplicarla. Además, una corrección recalcula el snapshot desde las tablas, según los hechos del sistema.  
Impacto: la misma versión y el mismo snapshot podrían producir bytes distintos tras la reversa.  
Acción: especificar y probar qué hace la reversa con cada job v10 pendiente, incluidos los que llevan anexo; conservar un renderer compatible o bloquear esos trabajos explícitamente. Definir también cómo se preserva la opción al corregir después de revertir.

**[P1] La corrección confunde «clave ausente» con «desmarcar».**  
Evidencia: D1 emite `anexo_cronograma` «SOLO cuando el analista la marca»; D2 propone en corrección `coalesce((p_contrato->>'anexo_cronograma')::boolean,false)`. D6 menciona la pantalla de corrección, pero no una lectura autorizada de la opción almacenada en `private`.  
Impacto: si se permite cambiar la elección, una corrección que omita la clave puede convertir un `true` previo en `false` sin intención del analista.  
Acción: definir **ausente = conservar**, `false` explícito = desmarcar, `true` = marcar; proporcionar a la pantalla el valor persistido. Si Miguel no autoriza cambiarlo, no hacer `upsert` en corrección.

**[P1] La regla propuesta clasifica una devolución como liquidación parcial.**  
Evidencia: el código transcrito usa `cronograma.filter((cuota) => cuota.tipo !== "retorno")`; D4 indica que el compuesto contiene una fila `devolucion` al vencimiento. Por tanto, esa fila entra en `parciales`. Cuando no hay `retorno`, el código también toma capital y vencimiento como liquidación final. La duplicación visible del capital es una *hipótesis*, pues falta el cuerpo completo del anexo.  
Impacto: el anexo puede describir incorrectamente un flujo contractual.  
Acción: fijar con Miguel las reglas por tipo y modalidad, la fecha final y el tratamiento del compuesto; probar el texto y los importes resultantes antes de escribir SQL. Resolver asimismo la consulta al abogado sobre «Participación» y la cláusula 3.9.

**[P1, hipótesis] El `upsert` de A puede romper un reintento idempotente.**  
Evidencia: D2 coloca un `upsert` después de `crm.crear_contrato_con_cuenta`; el trigger propuesto rechaza `UPDATE` una vez congelado el contrato, y la creación reserva un job. No se transcribió el cuerpo completo de `crm.crear_contrato_con_cuenta_pdf_v2`, por lo que podría existir una salida temprana que evite el problema.  
Impacto: si un reintento con la misma clave llega al `DO UPDATE` tras la reserva, puede recibir `55000` en vez de recuperar el contrato creado.  
Acción: definir la ruta idempotente sin UPDATE innecesario y probar el mismo pedido antes y después de reservar y sellar.

**[P2] A no protege el primer INSERT tardío de una opción.**  
Evidencia: D2 propone rechazar solo `UPDATE/DELETE`; los contratos del portal no tendrán fila y D3 interpreta su ausencia como `false`. *Hipótesis:* una escritura privilegiada posterior podría insertar `true` cuando ya existe una reserva, sin pasar por la regla de congelamiento.  
Impacto: la tabla dejaría de garantizar por sí misma que la elección cambia únicamente mediante revisión autorizada.  
Acción: proteger también INSERT sobre contratos congelados, permitiendo la creación inicial antes del job y la corrección autorizada.

**[P2] El plan deja una reversa de venta cruzada potencialmente inutilizable.**  
Evidencia: D5 dice que el postflight guarda huellas de `pdf_v2` y `crear_job`, que `scripts/venta-cruzada/reversa-fase3.sql` «exige las mismas», y ofrece «actualizar ese script o documentar que ya no aplica».  
Impacto: documentar la incompatibilidad no hace ejecutable una reversa que siga disponible.  
Acción: fijar el nuevo contrato de huellas y comprobar en Docker el postflight y la reversa afectada; si se retira esa reversa, sustituirla por un procedimiento operativo concreto.

**[P2] La verificación de producción está definida de dos maneras incompatibles.**  
Evidencia: D7 la llama «solo lectura» y, en la misma lista, exige «alta nueva con casilla ⇒ PDF con anexo».  
Acción: hacer las altas de prueba en Docker; en producción, observar contratos reales posteriores al despliegue o definir expresamente una operación de prueba autorizada.

TEST GAPS:
- Alta repetida con la misma clave de idempotencia; opción ausente, `false` y `true`.
- Corrección que conserva `true`, cambio explícito `true→false`, corrección fuera de las 5 horas y lectura inicial del valor en la UI.
- F4 con borrador preparado antes del cambio y con `datos.contrato.anexo_cronograma:true`.
- Reversa con job v10 pendiente **con anexo**, reserva v9 reestampada sin `opciones`, v9 con bytes y v9 sellado.
- Anexo para cada tipo de fila y modalidad, con conciliación de fechas e importes; validación estricta de `opciones` cuando está presente.
- Gates F7, postflights de venta cruzada, oráculos y E2E locales en Docker tras la migración real.

REGRESSION RISKS:
- D6 reconoce que la plantilla demo «ya diverge en texto legal» y propone duplicar allí el anexo: la vista previa puede diferir del PDF legal. Conviene contrastar ambas salidas con los mismos casos.
- La compatibilidad de snapshots v9 sin `opciones` es necesaria para el reestampado; debe verificarse en el renderer real, además del golden sin anexo.

RECOMMENDED NEXT ACTIONS:

1. Cerrar las decisiones de Miguel sobre corrección, fecha final, compuesto y estado inicial de la casilla, y obtener la decisión jurídica sobre los importes mostrados.
2. Solicitar el OK explícito para B. Si se mantiene A, completar lectura autorizada, semántica de ausencia, protección de INSERT e idempotencia antes de escribir la migración.
3. Rediseñar publicación y reversa alrededor de jobs v10 con `anexoCronograma:true`, y ejecutar los gates documentales y de venta cruzada con el SQL final.

CONFIDENCE: MEDIUM. Los conflictos de publicación y clasificación de `devolucion` se desprenden directamente del encargo; los riesgos de `upsert` y reversa dependen de cuerpos y SQL aún no presentados.
