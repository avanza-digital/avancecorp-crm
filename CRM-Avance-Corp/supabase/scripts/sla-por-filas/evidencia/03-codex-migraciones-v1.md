**VERDICT: CHANGES_REQUESTED**

**SUMMARY:**

Los cuerpos corrigen los tres P1 del plan anterior: conservan la ruta `false`/`NULL`, producen cabecera con cero filas y adaptan los guardianes en el paso correspondiente. No encuentro una fuga de autorización demostrada en las funciones nuevas transcritas.

Sí encuentro contraejemplos en la selección de funciones, la reversa y el historial de migraciones. Además, la equivalencia de la cola depende de una unicidad que el muestreo del banco no demuestra.

**Puede abrirse un PR como borrador; todavía no recomendaría solicitar el «!» de producción.**

Revisión estática exclusivamente: **checks ejecutados por mí: NOT RUN**. Los PASS del banco son resultados informados. No se proporcionaron números de línea; las referencias identifican bloques y símbolos.

**FINDINGS:**

**[P1] La reaplicación después de reversas registradas puede dejar el esquema incompatible con su historial.**

**File:** M1–M3; `registrar-indice.sql`; `LEEME.md`, «Si hay que revertir».

**Lines:** precondiciones de las migraciones; bucle `INSERT … ON CONFLICT DO NOTHING` del registrador.

**Problem / Evidence:** Las migraciones deciden si están aplicadas mirando las funciones vivas, sin consultar el índice. El registrador acepta una fila anterior cuando coincide su contenido.

Contraejemplo deducido del SQL:

1. Aplicar y registrar M1–M3.
2. Revertirlas mediante migraciones nuevas y registrar esas reversas, como indica el procedimiento.
3. Reaplicar los archivos originales: las reversas restituyeron exactamente sus precondiciones, por lo que pasan.
4. Ejecutar el registrador: encuentra las tres filas originales iguales y termina correctamente.

El esquema queda en M3, pero reproducir el historial cronológico termina en ANTES: no hay una migración posterior que represente la reaplicación.

Existe otro caso: una versión ya ocupada por contenido diferente no impide que la migración modifique y confirme el esquema; el conflicto aparece **después**, al registrar.

**Impact:** Historial inconsistente o cambio confirmado que no puede registrarse con su versión.

**Recommendation:** Rechazar versiones ya registradas **antes del DDL**. Una reaplicación posterior a reversas registradas necesita versiones nuevas. Documentar también la recuperación de «commit confirmado, registro pendiente», sin volver a ejecutar el DDL.

---

**[P2] `_filas(null)` no fija la firma cuyo cuerpo se verificó.**

**File:** [M3](/Users/usuario/dev/avancecorp-crm-foto-sla/CRM-Avance-Corp/supabase/migrations/20261017054427_crm_sla_cola_por_filas.sql), `crm.cola_accion_v3_fn`; M1, preflight y guardián.

**Lines:** CTE `f`: `private.sla_operacion_autorizada_filas(null)`.

**Problem / Evidence:** El argumento es un literal de tipo inicialmente desconocido. Si existe también una sobrecarga:

```text
private.sla_operacion_autorizada_filas(text)
```

PostgreSQL puede seleccionar la variante `text`, por la preferencia de la categoría de cadenas al resolver argumentos desconocidos.

Las comprobaciones de huella identifican exclusivamente `uuid[]`. Una sobrecarga `text` con propietario, ACL, volatilidad y configuración permitidos pasa el bucle de propiedades por `proname`; sus dependencias y cuerpo no se verifican. Incluso una variante cuyo cuerpo simplemente lance una excepción demostraría que la cola ejecuta código distinto del ensayado, sin cambiar su propio sello.

**Impact:** La huella de la puerta no garantiza qué función ejecutará esa llamada. Una sobrecarga con otra regla de ámbito también podría cambiar la autorización.

**Recommendation:** Usar `null::uuid[]` y añadir este mutante al ensayo.

**Clasificación:** Contraejemplo de resolución y estado, deducido estáticamente. **No demuestra que `authenticated` pueda crear esa sobrecarga** ni que exista actualmente.

---

**[P2] La reversa M1 puede borrar funciones que todavía tienen consumidores PL/pgSQL.**

**File:** [reversa-m1.sql](/Users/usuario/dev/avancecorp-crm-foto-sla/CRM-Avance-Corp/supabase/scripts/sla-por-filas/reversa-m1.sql).

**Lines:** guarda sobre `p.prosrc ~ '\msla_operacion_(autorizada_filas|ambito)\M'`.

**Problem / Evidence:** La expresión regular distingue mayúsculas. Este consumidor es válido:

```sql
PERFORM private.SLA_OPERACION_AUTORIZADA_FILAS(NULL::uuid[]);
```

PostgreSQL resuelve el identificador sin comillas en minúsculas, pero `prosrc` conserva la escritura original y la guarda no encuentra la llamada.

Además, las referencias dentro del cuerpo textual de una función PL/pgSQL no constituyen dependencias persistentes que hagan suficiente el `DROP FUNCTION … RESTRICT` implícito.

**Impact:** La reversa puede confirmar y dejar ese consumidor fallando con `42883`. Las funciones vigiladas pueden volver exactamente a ANTES mientras queda otra función rota.

**Recommendation:** Cubrir como mínimo identificadores sin comillas en cualquier combinación de mayúsculas, añadir el mutante y combinar el análisis de consumidores con dependencias registradas. No presentar una búsqueda textual como prueba completa de ausencia de llamadas dinámicas.

---

**[P2] Los tres guardianes pueden permanecer en OK sin `sla_operacion_ambito`.**

**File:** [M1](/Users/usuario/dev/avancecorp-crm-foto-sla/CRM-Avance-Corp/supabase/migrations/20261017054425_crm_sla_ventana_por_filas.sql), modificación de `assert_sla_nucleo`.

**Lines:** lista de dependencias y bucle de propiedades por `proname`.

**Problem / Evidence:** El guardián exige que los cuerpos del envoltorio y `_filas` contengan una llamada al ámbito. Pero nunca inspecciona el ámbito como `firma` de origen ni exige expresamente que exista su firma.

Si se elimina `private.sla_operacion_ambito(uuid[],boolean)`:

- las cadenas de llamadas siguen presentes en los cuerpos;
- el bucle de propiedades encuentra cero filas para esa función;
- las comprobaciones propias de avisos y cola siguen intactas.

Por lectura de los tres guardianes, ninguno detecta específicamente esa ausencia.

**Impact:** Los guardianes pueden declarar OK mientras las puertas fallan al resolver su autoridad. Las poscondiciones de instalación sí detectan la ausencia; el defecto es del control posterior.

**Recommendation:** Exigir explícitamente la existencia de cada firma obligatoria antes de inspeccionar sus propiedades. Añadir el mutante «eliminar únicamente el ámbito».

El nuevo control de propietario, `proowner <> 'postgres'::regrole::oid`, **sí es correcto**.

---

**[P2] M2 permite continuar con un productor diferente del ensayado.**

**File:** [M2](/Users/usuario/dev/avancecorp-crm-foto-sla/CRM-Avance-Corp/supabase/migrations/20261017054426_crm_sla_avisos_por_filas.sql).

**Lines:** manifiestos `esperado_preflight_m2` y `esperado_postflight_m2`.

**Problem / Evidence:** Ambos omiten `private.sla_operacion_leads`, aunque M1 y M3 sí exigen su huella.

Después de M1, un cambio en una decisión del productor que conserve sus propiedades y la referencia a `sla_hechos_actuales` pasa los guardianes estructurales. M2 puede entonces instalarse y confirmar sobre ese productor modificado.

`verificar.sql` mostraría una familia diferente, por lo que una operación manual cuidadosa puede detenerlo; **la propia migración no rechaza ese estado**.

**Impact:** La afirmación de que M2 exige el estado ensayado completo es más fuerte que su comprobación real.

**Recommendation:** Incluir el productor en ambos manifiestos de M2 y ensayar un cambio funcional que conserve las dependencias textuales. Alinear también las dependencias verificadas por el registrador con el estado que pretende certificar.

---

**[P2, condicionado] La reconstrucción de la página multiplica filas si `lead_id` no es único.**

**File:** M3, `crm.cola_accion_v3_fn`.

**Lines:** construcción de `v_items_leads`:

```sql
from pagina p join d on d.lead_id = p.lead_id
```

**Problem / Evidence:** Si `d` contiene dos filas para un lead y ambas entran en `pagina`, el join produce cuatro combinaciones. La versión anterior conserva las dos candidatas originales. Si las dos filas difieren, también puede combinar la acción de una con el estado de la otra.

El informe demuestra ausencia de duplicados en 23.071 filas observadas. No aporta las restricciones que garantizan unicidad en todos los joins de `sla_hechos_actuales` y `sla_operacion_leads`.

**Impact:** Duplicación de ítems, combinaciones incorrectas y discrepancias entre página, totales y rango.

**Recommendation:** Acreditar la unicidad mediante las restricciones del esquema completo, o transportar una identidad por fila —por ejemplo, ordinalidad— para reconstruir la candidata exacta.

**Clasificación:** La multiplicación es deducible del SQL; **la posibilidad de producir duplicados con el esquema vigente sigue siendo una hipótesis**, porque faltan sus restricciones. No afirmo que ocurra en producción.

**TEST GAPS:**

- Ejecutar el `test:rls` integral con fixtures y `CRM_RLS_EXIGE_SLA_FILAS=1`. Actualmente está **NOT RUN**. El bloque nuevo comprueba forma de respuestas; por sí solo no demuestra exclusión de registros ajenos.
- Exigir explícitamente el estado final **M3** en el gate de la serie completa. Con solo M1 instalada, las comprobaciones nuevas pueden pasar usando las puertas antiguas.
- Añadir los contraejemplos anteriores: sobrecarga `text`, consumidor con identificadores en mayúsculas, eliminación del ámbito, productor alterado antes de M2 y reaplicación con reversas presentes en el índice.
- Ensayar el ciclo de historial completo conservando las filas originales **y las de reversión**. Crear y borrar una tabla temporal equivalente no acredita ese ciclo.
- Resolver «pendiente sin acción», empates con claves nulas y multiplicidad mediante fixtures alcanzables o invariantes demostrados por código y restricciones.
- Conservar el arnés y sus resultados saneados como evidencia reproducible del PR. Los informes indican que parte de esos archivos está sin versionar.
- Ejecutar carga concurrente representativa, incluyendo Gestión Diaria y llamadas mezcladas, con configuración de producción.

**RISKS:**

**Equivalencia funcional.** La cabecera discriminada está correctamente excluida de los agregados y existe con cero leads. La salida temprana `false` se conserva. `coalesce(columna,'null'::jsonb)` reproduce la conversión de SQL NULL realizada por el objeto anterior. La fórmula de `string_agg` conserva delimitadores, elementos JSON, vacío y orden textual; no encuentro un contraejemplo intrínseco a esa sustitución.

La reducción a una página de leads antes de mezclar clientes es válida con el mismo orden total y sin multiplicaciones al reconstruirla. Ahí importan la unicidad y los empates señalados.

**Errores.** La prelectura conserva el orden de los casts y difiere los errores ordinarios hasta después de forma y contexto del cursor. No encuentro una diferencia funcional demostrada con los tipos que fabrica el núcleo actual. La advertencia sobre acciones con tipos corruptos no demuestra un caso alcanzable. La promesa de «mismos errores» debe distinguir errores funcionales de agotamiento de recursos, cancelaciones y `CONTEXT`, cuya equivalencia no está acreditada.

**Seguridad.** La cadena DEFINER → INVOKER conserva el usuario efectivo y la lectura de claims. Los nuevos helpers no reciben el ámbito del cliente. Crear y revocar dentro de la misma transacción no abre una ventana de EXECUTE para otras sesiones. Las puertas conservan sus ACL mediante `CREATE OR REPLACE` y las verificaciones posteriores.

Los guardianes siguen teniendo límites heredados: la detección de `auth.` en `assert_sla_nucleo` usa `~` sobre el texto original, por lo que `AUTH.uid()` evita esa comprobación; encontrar llamadas mediante regex tampoco prueba que su resultado gobierne el ámbito. No son fugas demostradas de esta implementación ni debilitamientos exclusivos del cambio, pero los once mutantes no prueban protección exhaustiva.

**Atomicidad y registro.** Las migraciones y reversas transcritas son transaccionales y sus comparaciones de huellas rechazan NULL mediante `IS DISTINCT FROM`. Las guardas finales también rechazan un retorno NULL del guardián. No observo un camino de error ordinario que confirme solo parte de una migración.

El registrador no sobrescribe filas y revierte sus inserciones si encuentra contenido incompatible. Eso no resuelve el problema de historial del P1 ni hace atómicos el DDL y su registro. El candado consultivo coordina únicamente procesos que lo respetan; no excluye DDL administrativo concurrente ajeno.

`verificar.sql` es un informe de lectura que termina en excepción, **no un gate distinguible por exit code exitoso**. El procedimiento debe reconocer el informe esperado y detenerse ante cualquier otro error. `READ ONLY` protege contra escrituras ordinarias persistentes; la afirmación «cualquier escritura escondida falla» es demasiado absoluta, entre otras cosas por las excepciones para objetos temporales.

**Rendimiento — Q5.** El aumento de Gestión Diaria equivale a **1.288 bloques, unos 10,1 MiB adicionales escritos por llamada**, además del aumento de lecturas. No bloquea abrir el PR. Tampoco las tres mediciones en reposo demuestran ausencia de regresión bajo carga. Por el antecedente de caída y el objetivo de esta intervención, medir concurrencia debe preceder al «!»: latencias, errores, temporales, memoria total y swap, incluyendo consumidores que conservan el envoltorio.

**RECOMMENDED NEXT ACTIONS:**

1. Corregir los controles de historial, fijar la firma de `_filas` y cerrar las omisiones de reversa, existencia del ámbito y productor en M2.
2. Resolver el invariante de unicidad y repetir los casos afectados, regenerando huellas, reversas y el texto embebido del registrador.
3. Ensayar instalación, registro, reversión registrada y recuperación tras interrupciones sobre el artefacto final.
4. Ejecutar RLS integral y carga concurrente; presentar los tres guardianes ajenos que ya fallan como **FAIL preexistentes**, con evidencia comparable antes/después.
5. Abrir el PR con estos pendientes visibles. Solicitar el «!» cuando estén resueltos y el commit revisado tenga evidencia reproducible, incluidos los sellos/censo correspondientes.

**CONFIDENCE: HIGH** en los contraejemplos estáticos de historial, resolución de sobrecargas, reversa y guardianes; **MEDIUM** en la equivalencia universal y el comportamiento bajo carga, pendientes de restricciones del esquema y ejecución.
