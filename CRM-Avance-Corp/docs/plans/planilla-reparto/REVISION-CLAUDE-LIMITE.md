VERDICT:
PASS

SUMMARY:
El límite por origen es correcto. `disponibilidad` divide `cola` por origen, y `cola` ya está filtrada por `origenes` y por fechas de ingreso. Por eso la suma de los topes por origen nunca supera `cola.length`; el total de 90 queda garantizado sin un tope global aparte. `maximoCantidadReparto` excluye la propia celda, así que reducir o vaciar libera cupo y aumentar la propia celda reutiliza lo que ya tenía. La relectura y `prepararReparto` en `revisar()` siguen igual y continúan validando cambios externos. No encontré cambios obligatorios. Los hallazgos son P2/P3 y la mayoría son huecos de test.

FINDINGS:

[P2] Falta cubrir el caso en que la cola baja después de preparar
File:
`CRM-Avance-Corp/app/src/components/app/planilla-reparto.tsx` (`cambiarCantidad`, atributo `max`, `errorPlan`)
Lines:
hunk `@@ -101,6 +101,15 @@` y hunk del `<Input ... max=...>`
Problem:
"Actualizar" y el cambio de la prop `revision` vuelven a cargar `datos` pero no limpian `borrador`. Si la cola baja de 90 a 50 con Ana=60 y Beto=30:
- Ana queda con `max=20` y `value=60`.
- `prepararReparto` lanza error, aparece `errorPlan` y "Revisar" queda deshabilitado. Esto está bien y viene de antes.
- Al editar Ana, cualquier valor mayor que 20 se ajusta a 20. Por ejemplo, si cambia el 6 por 5 ("50"), queda en 20 con el aviso. Es coherente con la regla, pero puede sorprender.
- Beto también queda por encima de su nuevo tope (máximo 0) y solo se puede bajar.
Evidence:
`maximoCantidadReparto` devuelve `Math.max(0, disponibles - preparadosEnOtros)`. El efecto de carga no llama a `limpiarPreparacion`. Ningún test nuevo cambia `datos.cola` después de preparar.
Impact:
No hay riesgo de sobre-reparto, porque el bloqueo de `errorPlan` y la relectura en `revisar()` lo impiden. Sí es un camino de recuperación sin cobertura, y es justo el escenario de "cambios externos" del requisito.
Recommendation:
Agregar un test unitario que haga lo siguiente:
1. Preparar 60 + 30.
2. Reducir `datos.cola` a 50 y pulsar Actualizar.
3. Comprobar el mensaje de alerta, "Revisar" deshabilitado y `max` de Ana = 20.
4. Reducir Ana a 20 y comprobar que "Revisar" se habilita.

No hace falta cambiar código, salvo que se prefiera avisar explícitamente: "la disponibilidad cambió; ajusta las cantidades".

[P3] La entrada parcial "-" en un campo numérico se trata como vaciar la celda
File:
`planilla-reparto.tsx`, `cambiarCantidad`
Problem:
En Chromium, un `<input type=number>` con una entrada parcial no válida (`-`, `1.`, `e`) informa `value === ''`. El handler toma `''` como "vaciar": guarda `''` y libera el cupo, pero el DOM sigue mostrando `-`. React no reescribe el valor porque `'' == ''`.
Evidence:
`texto === '' ? '' : ...`. El test `it.each(['-1','1.5','1e2'])` usa `fireEvent.change` con valores completos y no cubre el estado intermedio.
Impact:
Es cosmético y ya ocurría antes del cambio. Se pierde el valor anterior de la celda en vez de mostrarse "cantidad entera", y el total baja. No permite superar el tope.
Recommendation:
Opcional: si `e.target.validity.badInput` es verdadero, mostrar el aviso de entero y no tocar el estado. Puede quedar como nota.

[P3] `maximoCantidadReparto` interpreta los valores con menos rigor que el resto del módulo
File:
`CRM-Avance-Corp/app/src/lib/planilla-reparto.ts`, `maximoCantidadReparto`
Problem:
Usa `Number(cantidades[origen]) || 0`, mientras que `cantidadFila` y `prepararReparto` exigen `/^\d+$/` y `isSafeInteger`. Con el handler nuevo no pueden entrar valores no enteros en `borrador`, pero la función es exportada y pública.
Impact:
Bajo. Un valor como "1e2" o "-5" que llegue al `borrador` por otra vía daría topes incoherentes con lo que muestra "Por enviar".
Recommendation:
Reutilizar la misma interpretación que `cantidadFila`; conviene extraer un helper `cantidadValida(texto)`.

[P3] Ajustar a 0 deja "0" en lugar de una celda vacía
File:
`planilla-reparto.tsx`, `cambiarCantidad`
Evidence:
`String(Math.min(Number('1'), 0))` da `"0"`. E2E: `carla.fill('1')` produce `toHaveValue('0')`.
Impact:
Solo visual. `prepararReparto` ignora `'0'` y los totales no cambian.
Recommendation:
Opcional: guardar `''` cuando el resultado ajustado sea 0 y el máximo sea 0. Si se mantiene así, documentarlo en el test como decisión.

TEST GAPS:
- La disponibilidad baja después de preparar (P2 anterior): `max` menor que el valor, `errorPlan` y recuperación al reducir.
- El filtro de supervisores combinado con el límite. Hoy `limpiarPreparacion` garantiza que `borrador` solo contenga destinos visibles, y `maximoCantidadReparto` suma todo `borrador` (incluidas filas ocultas). Ese invariante sostiene la coherencia entre `max`, "sin preparar" y `totalPreparado`. Un test o un comentario que lo fije evitaría una regresión si algún día se deja de limpiar al filtrar.
- El texto "X sin preparar" por origen no se verifica en los tests unitarios ni en E2E.

ARCHITECTURE RISKS:
- La regla de tope vive solo en la UI. El backend asigna lead a lead mediante `repartirLead`, y la protección real frente a un doble reparto sigue siendo la RPC atómica, que puede devolver `FUERA_DE_COLA`. Es correcto que no haya cambios en el backend; el límite es una ayuda de UX, no una garantía.

SECURITY RISKS:
- Ninguno dentro del alcance: el cambio es solo de cliente y no altera permisos.

REGRESSION RISKS:
- Bajos. Antes `onChange` guardaba el texto tal cual. Ahora rechaza textos no enteros sin tocar el estado y ajusta los excesos. La validación de `prepararReparto` y de `revisar()` no cambia.

RECOMMENDED NEXT ACTIONS:
1. Añadir el test de la cola que baja tras Actualizar (P2).
2. Opcional: unificar la interpretación de cantidades en un helper que compartan `maximoCantidadReparto`, `cantidadFila` y `prepararReparto`.
3. Reportar el resultado de la suite completa y del E2E en Docker antes de dar la tarea por terminada.

CONFIDENCE:
HIGH sobre la corrección del límite. MEDIUM sobre el comportamiento de `type=number` en distintos navegadores (P3 de entrada parcial), que es una hipótesis basada en el comportamiento conocido de Chromium y no está reproducida aquí.
