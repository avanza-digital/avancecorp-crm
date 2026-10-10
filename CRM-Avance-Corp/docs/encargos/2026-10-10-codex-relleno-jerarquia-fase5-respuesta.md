**VERDICT: CHANGES_REQUESTED**

**SUMMARY:**

Con el estado transcrito, el relleno produce la atribución esperada: no encuentro un error en el emparejamiento ni en la fecha del evento. Hay una omisión demostrable en la reversa. Además, el oráculo valida una instantánea, sin garantizar que sus precondiciones sigan vigentes al commit frente a escritores concurrentes. El registro de la migración no puede verificarse sin su SQL.

**FINDINGS:**

**[P2] La reversa acepta eventos cuya transición fue alterada**

Archivo: `supabase/scripts/jerarquia-relleno/reversa.sql`.  
Fragmentos: validación `if v_n <> 2 ...` y `delete from crm.usuario_eventos`.

Problema y evidencia: comprueba actor, acción, objetivo, idempotencia, hora y `via`, pero omite `supervisor_anterior` y `supervisor_nuevo`. El `DELETE` filtra únicamente actor, acción e idempotencias.

Contraejemplo: conservar todos los campos comprobados y cambiar `detalle.supervisor_nuevo` por otro UUID. Ambos conteos siguen dando dos y la reversa borra los eventos. Contradice su contrato: «se niega si encuentra […] alguno distinto».

Impacto: puede borrar una transición diferente de la que pretende deshacer. La prueba negativa «evento alterado» reportada no acredita protección frente a esta mutación concreta.

Recomendación: validar también ambos supervisores, proteger las filas contra modificaciones entre validación y borrado y comprobar el número realmente eliminado.

**[P2] Las precondiciones y el resultado del oráculo pueden quedar desactualizados antes del commit**

Archivo: migración transcrita, bloques 2–5.  
Evidencia: `set transaction isolation level repeatable read`, lecturas ordinarias del preflight y ambas fotografías; no aparece exclusión de escritores concurrentes.

Contraejemplo condicionado a que se permitan escrituras históricas concurrentes:

1. La migración obtiene su instantánea con las 821 operaciones.
2. Otra transacción inserta y confirma una venta de Jorge fechada en septiembre.
3. El oráculo no la ve: ambas fotografías siguen mostrando las nueve operaciones aprobadas.
4. La migración confirma. La nueva venta también queda atribuida a Administrador, ampliando el conjunto histórico respecto del aprobado.

Una actualización concurrente de jerarquía también puede invalidar la condición «ningún evento posterior» sin que el preflight la detecte.

Impacto: `PASS` demuestra el cambio dentro de la instantánea; no demuestra que el estado visible al commit conserve exactamente las condiciones aprobadas. **No hay evidencia de que esta carrera haya ocurrido**, ni de que exista una exclusión operativa que la impida.

Recomendación: si se exige esa garantía al commit, acreditar una pausa efectiva de las escrituras relevantes o protegerlas mediante bloqueos adquiridos antes de obtener la instantánea de validación.

**RESPUESTAS A LOS DEMÁS PUNTOS:**

- **Emparejamiento y NULL:** el emparejamiento es correcto para el lector mostrado. Dentro de cada partición repetida, analista y día determinan el mismo supervisor; el orden arbitrario de `row_number()` no altera el resultado. La igualdad de conteos y el emparejamiento completo comprueban multiplicidades. El guardia `NOT (...)` admite resultados `UNKNOWN`, pero no encuentro un contraejemplo alcanzable con estas precondiciones: para los dos objetivos desde el cambio, el supervisor previo necesariamente es Carlos.
- **Hora e identity:** correctos. El instante coincide con auditoría y determina el 29/08 en Lima. Aplicar el nuevo supervisor a todo ese día cumple el contrato del lector; además, no había ventas anteriores a la hora del cambio dentro del intervalo indicado. Un identity mayor no desplaza el evento detrás de otros posteriores: primero se ordena por `creado_en`.
- **Base vacía:** no puede activar ese retorno con el estado de producción aportado. Para hacerlo tendrían que faltar las cuatro personas comprobadas en `crm.equipo` **y** las dos filas de auditoría. El código no oculta una ausencia parcial.
- **Idempotencia del relleno:** cubre repetición y estado parcial, y verifica los campos que determinan la atribución. La restricción única evita duplicados del mismo actor, acción e idempotencia. Una ejecución concurrente podría abortar por conflicto; no dejaría un solo evento confirmado.
- **Ventas nuevas y anuladas:** la aceptación de cualquier cantidad fechada desde el corte es explícita. No equivale a comprobar cuándo se registraron. El oráculo incluye todas las filas devueltas por la función, sin filtrar `anulado`; la cobertura concreta de anuladas no puede establecerse sin el cuerpo de `capital_episodios` o casos específicos.
- **Actor, lectores y replays:** no identifico una incompatibilidad demostrada. El actor coincide con el sistema, la acción está permitida y `via` vive dentro del JSON. Las claves fijas son distintas y los replays descritos buscan por actor e idempotencia. La búsqueda textual en `pg_proc` no demuestra ausencia de consumidores externos, pero tampoco hay evidencia de alguno afectado.
- **Bloqueos y tiempo:** 286 ms es evidencia favorable. Los timeouts y la transacción limitan esperas y evitan escrituras parciales si hay un error. No sustituyen la exclusión de concurrencia del hallazgo anterior.

**TEST GAPS Y REGISTRO:**

- Pruebas Docker y ensayo de producción: **PASS reportado por PRIMARY**. Ejecución independiente: **NOT RUN**.
- Falta probar la reversa alterando únicamente cada campo de supervisor.
- Falta una prueba con dos sesiones para las carreras descritas.
- `registrar.sql`: **NO VERIFICADO**, porque no está transcrito. Ejecutarlo después de confirmar el relleno permite un estado aplicado pero sin registrar si hay una interrupción. Falta comprobar cómo recupera ese estado, cómo rechaza una versión existente con otro hash y cómo vincula el registro al texto realmente ejecutado.

**NEXT ACTIONS:**

1. Completar la validación y el borrado protegido de la reversa.
2. Resolver o delimitar expresamente la garantía frente a concurrencia.
3. Revisar el SQL concreto del registro y su recuperación ante interrupciones.

**CONFIDENCE: HIGH** para el análisis estático del SQL mostrado; limitada respecto de concurrencia operativa, consumidores no transcritos y registro.
