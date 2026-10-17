**VERDICT: CHANGES_REQUESTED**

**SUMMARY:**

La v2 corrige los contraejemplos principales de equivalencia y autorización señalados en v1. No encuentro una diferencia nueva de `jsonb` demostrada con el productor transcrito, ni una ampliación de acceso demostrada.

Persisten problemas de historial y aparecen límites concretos en la reversa. Además, la carga sigue en **NO PASA**, falta Gestión Diaria bajo concurrencia y el RLS integral continúa **NOT RUN**.

**Puede abrirse un PR como borrador. No recomendaría todavía el «!» de producción.**

Revisión exclusivamente estática: **checks ejecutados por mí: NOT RUN**. Los resultados del banco son evidencia informada. Las referencias siguientes identifican bloques y símbolos; la transcripción no trae números de línea.

**FINDINGS:**

**[P1] Los registradores confunden un estado funcional con la ejecución de una versión concreta.**

**File:** `registrar-indice.sql`; `registrar-reversa-m1/m2/m3.sql`.

**Lines:** selección de `v_serie`, `v_archivos`, comprobación de la migración original e `INSERT … ON CONFLICT`.

**Problem:** Las mismas huellas representan todas las generaciones de estas migraciones. Comprobarlas no permite identificar qué versión produjo ese estado.

**Evidence — dos contraejemplos deducibles del SQL:**

1. Aplicar y registrar las originales; revertirlas y registrar las reversas; reaplicar con versiones nuevas. Ejecutar entonces el **registrador original**. Encuentra M3, encuentra las tres filas originales con contenido idéntico y termina correctamente. No registra las versiones nuevas: el esquema está en M3 mientras el historial sigue terminando en las reversas.
2. Revertir M3 y registrar esa reversa con versión R. Sin ejecutar otra reversa, cambiar únicamente `v_version` del registrador a R2, posterior y libre. El registrador acepta: sigue viendo M2 y la original registrada. Inserta una segunda reversa que **no se ejecutó**. Al reproducir el historial, esa segunda reversa falla porque exige M3.

La comprobación nueva de las migraciones originales sí impide **reaplicar esas versiones originales**. Ese hallazgo específico de v1 está corregido; estos caminos pasan por los registradores.

**Impact:** Registro falsamente exitoso, versiones omitidas o ficticias e historial no reproducible.

**Recommendation:** Validar la generación y la transición previa del historial, no solo el estado final. Si se pretende acreditar qué archivo se ejecutó, vincular versión y hash al DDL en la misma transacción mediante un mecanismo ensayado. La idempotencia debe reconocer el mismo evento, no cualquier estado funcionalmente idéntico.

---

**[P1] Las reversas no protegen su versión antes del DDL y el ciclo ensayado tiene un orden histórico incorrecto.**

**File:** `reversa-m1/m2/m3.sql`; sus registradores; adjunto 5, «Reversas, ciclo de historial y reaplicación».

**Lines:** inicio de `DO $reversa$`; validación de `v_version`; tabla del ciclo.

**Problem:** Las reversas no conocen ni comprueban su versión de publicación. Sus registradores solo exigen catorce dígitos y que la versión no coincida con las tres originales.

**Evidence:**

- Una versión de reversa ocupada por otro contenido no impide confirmar el DDL. El conflicto se descubre después, al registrar.
- Una reversa ya registrada puede ejecutarse nuevamente cuando una reaplicación restaura su precondición. Registrar después con la versión antigua puede devolver éxito idempotente, dejando sin representar esta segunda reversión.
- El ensayo registró R3 como `20261017990003`, R2 como `20261017990002` y R1 como `20261017990001`. Al reproducir por versión ascendente, **R1 se ejecuta primero**, cuando sigue vivo M3, y falla su preflight. Las 24 operaciones manuales no acreditan la reproducción cronológica.
- También existe un callejón operativo: M3 confirma, se pierde la conexión antes del registro y se ejecuta su reversa. Ahora `registrar-indice.sql` en M2 no registra M3; `registrar-reversa-m3.sql` exige que M3 esté registrada. El procedimiento documenta registrar primero, pero la reversa no impone esa precondición.

**Impact:** Una reversión puede quedar confirmada sin un registro válido o producir un historial que no reproduce el esquema.

**Recommendation:** Generar la reversa con su identidad concreta y comprobarla antes del DDL; exigir el orden correcto de sus versiones y resolver explícitamente el registro pendiente antes de revertir. Ensayar una **reproducción completa por versión ascendente**, además de la secuencia manual.

---

**[P2] La reversa M1 todavía puede omitir consumidores estáticos con identificadores Unicode escapados.**

**File:** `reversa-m1.sql`.

**Lines:** búsqueda `prosrc ~* '\msla_operacion_(autorizada_filas|ambito)\M'` y consulta de `pg_depend`.

**Problem:** `~*` corrige las mayúsculas, pero el texto del identificador puede diferir de su nombre resuelto sin utilizar SQL dinámico.

**Evidence:** Este cuerpo PL/pgSQL contiene una llamada estática válida:

```sql
BEGIN
  PERFORM 1
  FROM private.U&"sla_operacion_autorizada_\0066ilas"(NULL::uuid[]);
END;
```

`\0066` representa `f`. PostgreSQL resuelve `_filas`, pero `prosrc` no contiene el nombre literal buscado. Las referencias SQL dentro del cuerpo textual PL/pgSQL tampoco quedan protegidas por una dependencia persistente que necesariamente impida el `DROP`.

Por tanto, la reversa puede eliminar `_filas` y dejar ese consumidor fallando posteriormente.

**Impact:** Consumidor roto después de una reversión aparentemente correcta.

**Recommendation:** Añadir este mutante. Normalizar esa sintaxis mediante análisis SQL o detener conservadoramente la reversa ante cuerpos que requieran esa inspección. Documentar que el límite incluye identificadores escapados, además de SQL dinámico.

**Clasificación:** Contraejemplo estático; no ejecutado aquí ni observado en producción. **El mutante de mayúsculas de v1 sí está corregido.**

---

**[P2] El resumen de carga generaliza una reducción de temporales que no ocurre en el escenario «peor».**

**File:** `carga-3a/INFORME.md`; `comparacion-peor-20261017-1316.md`.

**Lines:** «Temporales: por ronda, −55 %» frente a la tabla del escenario «peor».

**Evidence:**

| Métrica, escenario «peor» | A | B |
|---|---:|---:|
| Temporales por ronda | 445,2 MiB | 598,9 MiB |
| Temporales totales | 5.342,4 MiB | 7.186,3 MiB |
| Llamadas completadas | 483 | 692 |

Los temporales por ronda aumentan **aproximadamente 34,5 %**. El −6,11 % corresponde a dividir por llamadas completadas, con distinta composición y distinto número de cancelaciones.

El +267,68 % de temporales por llamada completada de cola tampoco demuestra por sí solo una regresión intrínseca: en B terminan muchas más consultas, posiblemente las más grandes. Ambos cocientes requieren reconocer ese sesgo.

**Impact:** La explicación para autorizar producción subestima el volumen de E/S del escenario de sobrecarga.

**Recommendation:** Corregir el informe distinguiendo volumen total, coste por trabajo equivalente y coste entre consultas que terminaron. Conservar el criterio previamente establecido, pero acompañarlo de E/S absoluta y composición por rol. No presentar «temporales mejoran en ambos escenarios» sin esa precisión.

---

**Correcciones de v1 — Q1:**

| Hallazgo anterior | Evaluación de v2 |
|---|---|
| Historial de las migraciones originales | **Corregido en M1–M3:** `to_regclass` más consulta parametrizada antes del DDL. El ciclo completo sigue incompleto por los dos P1 anteriores. |
| `_filas(null)` resuelve otra sobrecarga | **Corregido:** `null::uuid[]` y prohibición de sobrecargas. |
| Reversa M1 omite mayúsculas | **Corregido para ese caso:** `~*` y `pg_depend`. Subsiste el contraejemplo Unicode indicado. |
| Ámbito ausente deja guardianes verdes | **Corregido:** existencia explícita de la firma obligatoria. |
| M2 no exige el productor | **Corregido:** aparece en ambos manifiestos con cuerpo, metadatos y atributos. |
| Reconstrucción multiplica por `lead_id` | **Corregido:** ordinalidad de `f` materializado y unión por `fila`. |
| H1, «pendiente sin acción» | **Corrección coherente:** reconstruye candidatas y usa la paginación anterior. Los ensayos informados cubren el contraejemplo original. |
| H2, mutantes de autoridad | **Corregido para las piezas indicadas:** sellos de ámbito, `_filas` y envoltorio; también del resumen. |
| Auditor: denegados y ámbito absoluto | **Implementado**, incluidos C/D/E independientes de la conexión fuera de banda. **Validación integral pendiente.** |
| Auditor: llamadas privadas permitidas | **Corregido para los cuerpos finales:** listas permitidas más sellos. |
| Auditor: errores de acceso por API | **Corregido:** se exigen los códigos indicados. |
| Auditor: registradores de reversas | **Añadidos, pero incompletos:** P1 anteriores. |
| Verificador: comentarios, ACL y cifras | Comentarios y cobertura de ACL corregidos; cifras de memoria alineadas. El informe posterior de carga necesita la corrección indicada. |
| `AUTH.` en mayúsculas | **Corregido para ese patrón** mediante `~*`. |
| Exigir M3 y comparar censo | M3 se exige como estado final; censo comparado en el banco e informativo en producción. No debe fijarse al valor antiguo después de #317–#319. |

**TEST GAPS:**

- **RLS integral con fixtures y `CRM_RLS_EXIGE_SLA_FILAS=1`: NOT RUN.** El código añadido no sustituye su ejecución.
- **71 cadenas: NOT RUN.** Completar las 69 RC2g y dos RC3g antes de declarar cerrada la batería.
- **Gestión Diaria concurrente: NOT RUN en la evidencia adjunta.** La carga solo incluye avisos, cola y estado. Este requisito anterior sigue abierto.
- Añadir los contraejemplos de registro: registrador de otra generación, segunda reversa registrada sin ejecutarla, versión ocupada antes de revertir y pérdida de conexión antes del registro.
- Reproducir el historial completo en orden de versión. Conservar las filas originales, reversas y reaplicaciones; no basta con insertarlas y comprobar el estado vivo.
- En las pruebas de ámbito de cola, acreditar que las comprobaciones no pasan con conjuntos vacíos y que los fixtures caben en la primera página examinada, o cubrir también el resto.
- **Transporte real de `verificar.sql`: pendiente.** En una única petición SQL, el `RAISE` interrumpe la ejecución y el `ROLLBACK` posterior no se alcanza. Si la conexión se reutiliza sin limpieza, queda abortada y la siguiente petición puede recibir `25P02`. El comportamiento del servicio al devolver o descartar esa conexión **no está demostrado** por `psql -f`; ensayar la vía exacta o emitir el informe sin interrumpir el cierre transaccional.

**RISKS:**

**Equivalencia y guardianes — Q2.** No encuentro un nuevo contraejemplo funcional alcanzable con el productor mostrado. La cabecera única, los SQL NULL convertidos a JSON null, los conteos y la identidad por ordinalidad son coherentes. El fallback H1 conserva el comportamiento anterior, incluido su cursor problemático cuando termina en un ítem sin acción; eso es heredado.

Las listas por regex no constituyen un analizador SQL completo. En resumen y cola, los sellos adicionales impiden que una modificación del cuerpo pase simplemente usando otra escritura de una llamada. Los sellos no certifican transitivamente toda función de la que dependen.

No veo un bloqueo irreversible por los sellos: una modificación legítima exige actualizar conscientemente el guardián. Sí obliga a regenerar las reversas correspondientes cuando cambia cualquiera de las piezas que estas exigen exactamente. El kit actual deja de ser una reversa utilizable después de esa evolución.

Los registradores de reversas calculan `v_exigidas_ok`, pero **no utilizan su resultado**. Esa comprobación no debe presentarse como una condición efectiva de aceptación. Si se omite deliberadamente para permitir una recuperación pese a cambios ajenos, conviene expresarlo y reportar la discrepancia.

**Atomicidad y producción — Q3.** Bajo la premisa de ejecución SQL normal, `BEGIN … DO … COMMIT` protege cada archivo: un fallo de sus comprobaciones o un `lock_timeout` no confirma parte de su DDL. Los guardianes se ejecutan antes del commit. No encuentro un camino ordinario que confirme media M1, M2 o M3.

Eso no hace atómica la serie completa ni su registro posterior. El candado consultivo coordina únicamente participantes que lo toman; tampoco impide DDL administrativo concurrente ajeno. Una pérdida de respuesta después del commit requiere inspeccionar el estado y recuperar el registro correcto, sin repetir ciegamente la migración.

La línea `GATE SERIE COMPLETA: OK` de `verificar.sql` solo comprueba M3 y las tres piezas exigidas. **Puede coexistir con un guardián fallando**, por ejemplo tras desactivar RLS en una tabla vigilada. Debe leerse como identificación del estado de la serie, no como aprobación global.

**Carga — Q4.** Refuto la conclusión categórica «`estado` no hace más trabajo». Las mediciones aisladas demuestran latencias parecidas; no demuestran igualdad de CPU, instrucciones ni esperas bajo concurrencia.

M1 sí incorpora capas adicionales: llamada a `_filas`, llamada al ámbito y materialización de filas. **No duplica la resolución de autoridad en la ruta `true`:** el envoltorio llama a `_filas`, que llama una vez al ámbito. Con `'{}'`, ese trabajo adicional puede ser pequeño, pero no se ha separado de la contención.

La explicación de mayor competencia por CPU es plausible y está correctamente etiquetada como hipótesis. Agrupar por solape medio no la demuestra: también cambian roles, tamaño y fase de ejecución de las consultas concurrentes.

La medición que lo resolvería es un experimento factorial:

| Sonda `estado` | Carga pesada fija |
|---|---|
| Antigua | Antigua |
| Nueva | Antigua |
| Antigua | Nueva |
| Nueva | Nueva |

Mantener actores, argumentos y patrón de llegada; usar una conexión dedicada para la sonda y medir separadamente espera de pool, tiempo transcurrido, CPU consumida y espera de planificación del backend. Correlacionar con `wait_event`, temporales y estrangulamiento del contenedor. `pg_stat_statements.total_exec_time` por sí solo tampoco mide CPU. Comparar por rondas/réplicas, con incertidumbre de los percentiles.

Ese diseño distingue el efecto de cambiar la sonda del efecto de cambiar su competencia. El ensayo aislado actual no lo permite.

**El NO PASA bloquea mi recomendación del «!»**, aunque finalmente la causa sea contención. Los resultados de punta a punta son favorables para avisos y cola, pero no sustituyen retrospectivamente el criterio acordado; el +9,8 % de `estado` tampoco tiene margen demostrado considerando la incertidumbre.

La memoria medida sí pasa: no hay evidencia de otro bloqueo por OOM o swap. En «peor», los 64 cortes de B son una mejora frente a 273, pero mantienen censurados los p95 de avisos y cola. No equivalen a una prueba de servicio satisfactorio. La ausencia de Gestión Diaria concurrente y su aumento observado de **1.301 bloques por llamada** impiden extender la conclusión de memoria/E/S a la mezcla solicitada.

**RECOMMENDED NEXT ACTIONS:**

1. Corregir la vinculación entre versión, transición y registro; proteger también las reversas antes del DDL y ensayar reproducción cronológica.
2. Añadir el consumidor Unicode al ensayo de reversa y resolver el transporte de `verificar.sql` como una sola petición.
3. Ejecutar RLS integral, completar las 71 cadenas y medir la mezcla con Gestión Diaria.
4. Separar coste propio y contención de `estado` con el experimento indicado; corregir el informe de temporales y mantener visible el **NO PASA**.
5. Integrar el tronco vigente y adjuntar al PR los artefactos finales, hashes y resultados reproducibles. El borrador puede abrirse ahora; la solicitud del «!» debe esperar al cierre de estos puntos.

**CONFIDENCE: HIGH** en los contraejemplos estáticos de historial y detección textual, y en la discrepancia del informe de temporales. **MEDIUM** en equivalencia universal y diagnóstico de rendimiento: no ejecuté los archivos y quedan pruebas relevantes pendientes.
