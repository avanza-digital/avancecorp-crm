VERDICT:
CHANGES_REQUESTED

SUMMARY:
El método es proporcionado al alcance ligero. Las cifras del informe coinciden con `MEDICIONES.json`. Recalculé medianas, rangos, el recuento de 39 invocaciones, el contraste y el solapamiento cero. Las etapas NOT RUN (HTTP, concurrencia, navegador) están declaradas con honestidad y no hay afirmaciones de p95, throughput ni capacidad. La prioridad de la lectura canónica por persona está justificada, y la aritmética de la evidencia la sostiene más de lo que el informe dice. Pido cambios solo en el informe:
- falta declarar que la ficha medida toma un bloqueo operativo en producción;
- el resumen del JSON es inconsistente con las medidas;
- faltan algunas precisiones de alcance.

No hay P0 ni P1.

FINDINGS:

[P2] La medición de la ficha toma un bloqueo operativo real en producción y el informe no lo declara
File:
`20260914213928_crm_coopac_condiciones_anuales.sql` (evidencia de `pg_get_functiondef` adjunta)
Lines:
812, 913
Problem:
El informe dice que los importes y datos comerciales no se modificaron y que la auditoría se revierte. No menciona que `inversion_persona_contexto(v_id)` adquiere un bloqueo operativo sobre una persona real. Ese bloqueo se mantiene hasta el `ROLLBACK` del lote.
Evidence:
- Línea 812: `perform private.inversion_persona_contexto(v_id); -- existing operational lock`.
- Cada lote corre en una transacción `READ COMMITTED` que termina en `ROLLBACK`. Con varias invocaciones por lote, el bloqueo pudo durar varios segundos (ficha de hasta 2,894 s dentro de un bloque con límite de 8 s).
- `lock_timeout=1s` solo protege a la prueba al adquirir bloqueos. No protege a usuarios reales que esperan el bloqueo que la prueba ya tiene.
- La salud se tomó en cortes a las 16:29, 16:36 y 16:37. No hay corte durante los lotes `base_*` ni `contraste`.
Impact:
Un usuario que operara sobre esas personas durante el lote pudo esperar. Probablemente no ocurrió, pero la evidencia no lo excluye. El informe transmite un "sin efectos" más fuerte de lo demostrado. Además, el `ROLLBACK` no revierte el consumo de secuencias si la tabla de auditoría usa `identity`/`serial` (hipótesis: no se adjuntó su esquema).
Recommendation:
Añadir en "Método, límites y estado final" que la ficha toma el bloqueo operativo existente hasta el `ROLLBACK`. Indicar su duración máxima posible y que no se monitorizaron esperas durante los lotes. En futuras mediciones, hacer un lote por invocación de ficha para acortar la retención, o medir en banco aislado.

[P2] El `resumen` de `MEDICIONES.json` no coincide con `medidas`
File:
`MEDICIONES.json`
Lines:
`resumen` frente a `medidas`, fase `hoy_1`
Problem:
El agregado omite medidas existentes y reporta un `n` incorrecto.
Evidence:
- `resumen["gerencia/conversion_mensual"]` dice `n: 1`, mediana 109.774. En `medidas` hay dos muestras: 109.774 (`base_1`) y 137.209 (`hoy_1`).
- `gerencia/cumplimiento_metas` (202.122), `gerencia/reuniones_mes` (100.115) y `gerencia/conversiones_mes` (499.745) no aparecen en `resumen`. Tampoco aparecen `busqueda_con_resultado` de ambos roles ni `ficha_misma_persona`.
- El rango "0,022–0,500 s" del informe es correcto solo usando `medidas`, porque su máximo (499.745) no está en `resumen`.
- Las dos entradas `fase: "primera"` no tienen `inicio_utc`, `fin_utc`, `error_codigo` ni `presente`. Cuentan en las 39 invocaciones, pero no se puede verificar que fueran "sin error SQL" con el mismo método.
Impact:
Quien lea solo el resumen verá datos distintos a los que sostienen el informe, y la trazabilidad del artefacto baja.
Recommendation:
Regenerar `resumen` desde `medidas` con todas las operaciones y `n` correctos. Completar los campos de las entradas `primera` o excluirlas del recuento y decirlo.

[P3] La búsqueda «a» no tiene selectividad; equivale a Cartera completa
File:
`MEDICIONES.json` (`busqueda_con_resultado`) e informe, sección "Resultados"
Lines:
—
Problem:
El informe dice que «a» "devolvió resultados a ambos". En la práctica devolvió el conjunto visible entero.
Evidence:
- Gerencia: `total 492, filas 25, bytes_json 12044`, idéntico a `cartera`.
- Analista: `total 21, bytes_json 10173`, idéntico a `cartera`.
- `p_texto` no se registra en las medidas, así que tampoco se puede verificar que el filtro llegara a la llamada.
- Las dos muestras son de fases distintas (`hoy_1` y `contraste`).
Impact:
Ninguna búsqueda compara a los dos roles con resultados no vacíos y selectividad parcial. La afirmación es literalmente cierta, pero puede malinterpretarse.
Recommendation:
Precisar "coincidió con todo el conjunto visible (492/21)" y registrar `p_texto` en las medidas.

[P3] Afirmación sin evidencia adjunta
File:
Informe, sección "Hallazgo e hipótesis de causa"
Lines:
"El último ajuste de F8 resolvió el timeout anterior"
Problem:
Nada de lo adjunto muestra el timeout previo ni su resolución.
Evidence:
Solo aparece como texto. Los commits `d96ed0a`/`d93d805` se mencionan en otro contexto, sin medición previa.
Impact:
Es una afirmación de mejora no respaldada por este artefacto.
Recommendation:
Enlazar la evidencia de F8 que la respalda, o eliminar la frase.

[P3] Reforzar y acotar la justificación de la prioridad
File:
Informe; `20260914213634_crm_f8_cartera_lectura_eficiente.sql:19-126`; `inversionistas-queries.ts:14-17`
Problem:
La inferencia es sólida, pero el informe no muestra su aritmética. Tampoco aclara qué no mejorará la corrección propuesta.
Evidence:
- Gerencia: 2 × 1216 ms del núcleo ≈ 2432 ms de 2722 ms en el contraste, un techo aproximado del 89 %.
- Analista: 2 × 153 ≈ 306 de 840 ms, aproximadamente el 36 %. El resto no atribuido es mayor en Analista (~534 ms) que en Gerencia (~290 ms) para la misma persona. Hay otro coste dependiente del rol fuera del núcleo, o el `EXPLAIN` como propietario no reproduce exactamente el coste dentro de la ficha.
- Los bloques leídos son parecidos (23.225 frente a 18.859, ×1,23), pero el tiempo es 8 veces mayor (1216 frente a 153 ms). Hipótesis: domina el trabajo por fila autorizada (laterales de identidad, contacto y vínculos), no los scans base. Un filtro por persona aplicado antes de esos laterales atacaría justo ese coste.
- Cartera y búsqueda de Gerencia (~1,25 s) también son casi solo el núcleo, y también se revalidan cada 15 s. Una optimización limitada a la lectura por persona no las reduce.
Impact:
Sin esta precisión se puede esperar que la corrección mejore todo Gerencia, o que baje la ficha de Analista en proporción.
Recommendation:
- Añadir las cuentas anteriores, marcadas como estimación.
- Declarar que la mejora propuesta afecta a la ficha y no a Cartera ni búsqueda.
- Dejar como candidato posterior aplicar los laterales solo a la página devuelta.
- Advertir que en Analista queda ~0,5 s sin explicar.

TEST GAPS:
- No hay prueba de equivalencia para la futura lectura filtrada. Debe comprobar, por actor (Gerencia, Supervisor con bandeja, Analista, lector), que el resultado de la versión filtrada para una persona `p` es igual a `(select … from private.cartera_f5_personas_visibles() where inversionista_id = p)`.
  - Casos: persona fusionada consultada por id no canónico, persona demo, fuera de alcance, sin responsable e inexistente.
  - El filtro debe aplicarse sobre el id canónico, después del mapeo de `identidades`. Si se aplica sobre `crm.inversionistas.id` crudo, se pierden alias fusionados.
- No hay desglose interno medido. En banco aislado, usar `auto_explain.log_nested_statements` o `pg_stat_statements` con `track = all` para separar núcleo, `postventa_visible`, `inversion_persona_contexto` y `cartera_f5_registrar`, y explicar los ~0,5 s restantes de Analista. Revisar también si hay JIT en las sentencias internas (hipótesis de baja confianza).
- Hay una sola muestra de contraste por rol. Es aceptable por su coherencia con `base_*`; conviene repetirla en la medición posterior a la corrección.

SECURITY RISKS:
- La corrección debe conservar las dos revalidaciones de acceso (entrada, línea 799, y salida, línea 910), además de `cartera_f5_exigir()`, la exclusión demo y el alcance por rol. No debe crearse un camino que cambie el orden entre resolver la identidad canónica y comprobar la visibilidad.
- La plantilla `MEDIR.sql` es correcta en cuanto a secretos (UUID por parámetro, sin claves). Se ejecuta con conexión administrativa: dejar claro que no debe usarse con UUID de clientes en documentos versionados.

REGRESSION RISKS:
- Sin cambios de producto en esta tarea, no hay regresión directa.
- Riesgo futuro: un parámetro de persona en el núcleo `SECURITY DEFINER` con `search_path` vacío debe mantener esas propiedades y los permisos `EXECUTE`.

RECOMMENDED NEXT ACTIONS:
1. Declarar en el informe el bloqueo operativo de la ficha y su retención hasta el `ROLLBACK`, y matizar la ausencia de efectos (P2).
2. Regenerar `resumen` desde `medidas`, completar o excluir las entradas `primera` y registrar `p_texto` (P2/P3).
3. Añadir la aritmética núcleo/ficha, el alcance real de la mejora (ficha, no Cartera) y el resto no atribuido de Analista. Eliminar o respaldar la frase sobre el timeout de F8.
4. Actualizar la línea "Revisión independiente de Claude: pendiente" con el resultado de este review.

CONFIDENCE:
HIGH en la verificación numérica y en la honestidad de los NOT RUN. MEDIUM en la atribución de causa y en el impacto real del bloqueo, porque no se adjuntaron el cuerpo de `inversion_persona_contexto` ni el esquema de auditoría.
