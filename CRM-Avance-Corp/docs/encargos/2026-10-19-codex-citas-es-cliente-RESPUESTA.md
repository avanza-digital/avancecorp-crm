**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** La transacción y el reemplazo anclado protegen contra una instalación parcial. No encuentro una ampliación demostrada de privilegios. La objeción principal es semántica: la auxiliar usa el estado **vigente hoy** para decidir si alguien era cliente **cuando se creó la cita**. Esas condiciones pueden producir resultados distintos.

Revisión estática de la transcripción; los contraejemplos siguientes no son incidencias verificadas en producción.

**FINDINGS**

**[P1] Las anulaciones posteriores pueden reclasificar citas históricas.**  
Archivo: [20261019170214_crm_citas_es_cliente_por_cita.sql:79](/Users/usuario/dev/avancecorp-crm-proyeccion-citas/supabase/migrations/20261019170214_crm_citas_es_cliente_por_cita.sql:79), líneas 79–85.

La primera rama exige `etapa = 'convertido'` y `not private.cierre_anulado(...)` **actuales**. La segunda exige `ce.anulado_en is null`, sin comparar la anulación con `p_antes`.

Contraejemplo: único cierre externo creado el 1/10, cita generada el 5/10 y cierre anulado el 10/10. Al consultar después del 10/10, devuelve `false`; el cierre estaba vigente cuando se generó la cita. La categoría histórica cambia por una actuación posterior.

También existe el problema inverso si rehabilitar borra `anulado_en`: cierre anterior, anulación antes de la cita y rehabilitación después. Recupera `true` usando la creación original, aunque el cierre estuviera anulado cuando se generó la cita.

**Impacto:** Proyección puede mover citas antiguas entre Clientes y Leads sin cambiar esas citas.

**Recomendación:** resolver explícitamente si las anulaciones deben tener efecto retroactivo. Para el contrato literal entregado, hace falta evidencia de vigencia en el instante de creación; los predicados actuales no la reconstruyen. Si se pretende «cierre anterior que sigue vigente hoy», debe quedar aprobado como una definición diferente.

**[P3] El supuesto retorno inmediato sin persona enlazada no existe.**  
Archivo: [SQL:45](/Users/usuario/dev/avancecorp-crm-proyeccion-citas/supabase/migrations/20261019170214_crm_citas_es_cliente_por_cita.sql:45), líneas 45–46 y 69–85.

`leads_persona` incluye incondicionalmente `select p_lead`. Aunque `persona` y `miembros` estén vacíos, ambas ramas pueden consultar el lead original y sus cierres externos. Un cierre propio anterior y no anulado puede producir `true` sin ninguna identidad enlazada.

**Impacto:** el comentario describe un contrato y un ahorro de lecturas que el SQL no garantiza.

**Recomendación:** decidir si ese resultado es correcto para el negocio y corregir la documentación o el comportamiento correspondiente. No añadir una exclusión de clientes sin persona únicamente para satisfacer el comentario.

**RISKS / TEST GAPS — respuestas concretas**

1. **Atomicidad y conservación de atributos.**  
   `BEGIN`–`COMMIT` engloba auxiliar, ambos reemplazos, huellas y sello. No hay captura de excepciones que permita continuar: un fallo en `_corte`, un timeout o el `assert` final aborta toda la transacción.

   En PostgreSQL 15/17, `pg_get_functiondef` reconstruye un `CREATE OR REPLACE FUNCTION` con los atributos de definición, incluidos `SECURITY DEFINER`, volatilidad y configuración. Owner y ACL se conservan por la semántica de **reemplazar el objeto existente**; no porque aparezcan como órdenes en esa definición. No se reinician los permisos a sus valores predeterminados.

   Con las huellas y anclas aportadas, el cambio textual queda limitado a la clave añadida. Queda un riesgo condicionado a **DDL concurrente**: el preflight y la lectura de `pg_get_functiondef` son operaciones separadas; bloquear las tablas del censo no bloquea una modificación independiente de las funciones. Los `strpos` del postflight no sustituyen una comparación completa frente a ese escenario.

2. **Auxiliar INVOKER y acceso de `authenticated`.**  
   Funciona desde los lectores DEFINER: durante su ejecución, el usuario efectivo es `postgres`, y la auxiliar INVOKER utiliza ese contexto.

   La creación y las revocaciones son transaccionales: no hay una ventana pública entre ambas. Con los permisos descritos, `authenticated` no puede invocarla directamente. El postflight también detectaría concesiones explícitas inesperadas procedentes de privilegios predeterminados.

   La inspección de ACL no demuestra por sí sola ausencia de privilegios **heredados mediante membresías**. Conviene comprobar `has_function_privilege` para `authenticated`, `anon` y `service_role` sobre la auxiliar instalada.

   La auxiliar devuelve un booleano. Sí incorpora información de cierres de la misma persona que pueden quedar fuera de los vendedores visibles del supervisor, porque internamente no aplica `v_visibles`. Eso parece corresponder a la clasificación solicitada; no amplía las filas de Citas devueltas.

3. **Otros casos semánticos.**

   | Caso | Resultado y evaluación |
   |---|---|
   | Lead convertido **después** de generar la cita | Su propia conversión no la marca. Los 70 leads actualmente enlazados a personas no implican 70 citas cliente. |
   | Lead convertido **antes**, con citas generadas posteriormente | Devuelve `true` si la conversión sigue vigente. Corresponde al requisito, aunque sea el mismo lead. |
   | Identidades fusionadas | Recorrer raíz y descendientes permite reconocer clientes de otra identidad de la misma persona. Una fusión posterior no es necesariamente un error: puede corregir una duplicidad histórica. |
   | Relaciones `inversionista_leads` terminadas | Se ignoran `desde` y `hasta` en líneas 60–61 y 74. **Hipótesis:** si puede existir un enlace histórico terminado hacia otra persona distinta de la actual, se mezclan ambas historias y puede aparecer un falso positivo. Falta acreditar la invariante de esos enlaces. |
   | `convertido_en = creado_en` | Devuelve `false` por `<`. Es coherente con «estrictamente antes». Si ambos usan `now()` dentro de una misma transacción, timestamps iguales no permiten deducir el orden causal. Hace falta fijar esa convención. |
   | `t.perfil_id` presente | La línea 102 fuerza `true`, sin comprobar antigüedad. **Hipótesis:** si el perfil puede asignarse después de crear la cita, una conversión posterior puede reclasificarla. Debe acreditarse que ese campo implica cliente previo desde el alta de la tarea. |
   | Tarea con perfil y sin lead | Sigue fuera de `historial`, según la evidencia aportada. Esta migración no hace aparecer esas citas. |
   | Cierre externo registrado retrospectivamente | Se compara `creado_en`. Si la fecha real de adquisición del cliente puede ser anterior al registro, habrá falsos negativos. Ese contrato temporal no está aportado. |

   La rama externa tampoco consulta `cierre_anulado(ce.lead_id)`. **No lo considero un defecto probado:** un cierre externo independiente podría seguir siendo válido. Hay que probar qué ocurre cuando una anulación general afecta precisamente al cierre externo que permanece con `anulado_en IS NULL`.

4. **Censo y declaración de la auxiliar.**  
   No puede determinarse si entra en `contadores_crudos_leads_citas()` sin su definición. La ausencia de `count(` no demuestra exclusión de un detector desconocido.

   Si entra, el `assert` final debe rechazar la migración completa; no deja instalado un censo inconsistente.

   Su declaración correspondería a **clase `analitica`**, con razón explícita, huella normalizada y el tipo utilizado por el detector. El `objeto` debe coincidir exactamente con la firma que emita el censo: no asumir que conservará el alias `timestamptz` en lugar de `timestamp with time zone`. Después se recalcula el sello y se ejecuta el `assert`.

5. **Actualizar solamente `huella`.**  
   Según la fórmula entregada, es suficiente si la razón sigue siendo válida y se conserva la clase. `declarado_en` no participa en el sello; `razon` participa, pero puede conservarse.

   No se está relajando `clase = 'analitica'`. Sin el cuerpo de `trg_analitica_lc_clase_solo_aprieta`, no puedo certificar que carezca de otras restricciones. Su nombre no basta para aprobar ese punto.

6. **Coste y bloqueos.**  
   `SHARE ROW EXCLUSIVE` permite las lecturas ordinarias con `ACCESS SHARE`; bloquea escrituras y operaciones incompatibles sobre las tablas del censo. No impone ese bloqueo a las tablas de Citas.

   Los locks duran hasta terminar la transacción. `statement_timeout = 90s` limita cada sentencia, **no la duración total de la migración**.

   Los 151 ms respaldan únicamente la consulta medida. La auxiliar con `SET search_path` no se incorpora al llamador mediante inlining; deben medirse los lectores reales para incluir el coste de las llamadas y sus planes. Además, sin persona enlazada siguen existiendo las consultas señaladas en P3. No hay evidencia suficiente para afirmar una regresión de rendimiento.

7. **Reversión.**  
   La cabecera sirve como orientación, pero no como procedimiento probado. La reversión debe, en una transacción:

   - Validar las versiones instaladas para no sobrescribir cambios posteriores.
   - Restaurar ambos cuerpos mediante reemplazo inverso único y comprobar sus MD5 originales.
   - Actualizar las **huellas normalizadas** de las exenciones. Los MD5 crudos de cabecera no son esas huellas.
   - Retirar la declaración de la auxiliar si finalmente se añadió, siguiendo las reglas del censo.
   - Eliminar la auxiliar después de restaurar los lectores, recalcular el sello y ejecutar el `assert`.

   Recalcular solamente el sello dejaría las huellas individuales desactualizadas.

8. **Prueba necesaria antes de instalar.**  
   El banco Docker con esquema de producción es el lugar adecuado. Una rama vacía no demuestra la clasificación, y el preflight exige además los cuerpos exactos esperados.

   Faltan ejecución completa de migración y reversión, fixtures temporales y de identidad, comprobación efectiva de permisos y medición de los lectores reales. **Estado de esas verificaciones: NOT RUN.**

**NEXT ACTIONS**

1. Resolver P1 y acreditar las invariantes de `perfil_id`, relaciones históricas e interpretación de cierres externos.
2. Inspeccionar detector y trigger del censo; ejecutar migración y reversión completas en Docker, conservando evidencia de huellas, atributos, ACL y `assert`.
3. Probar ambos lectores y las rutas de v2 con y sin corte. Comparar el JSON antes/después eliminando únicamente `es_cliente`: deben conservarse población, valores, totales y alcance por rol. Incluir fixtures positivos, anulaciones/rehabilitaciones, igualdad temporal y fusiones; los 608 resultados negativos no cubren esos comportamientos.

**CONFIDENCE: MEDIUM.** Alta en la atomicidad y los contraejemplos deducibles del SQL; limitada para el censo, el trigger y las invariantes de negocio no transcritas.
