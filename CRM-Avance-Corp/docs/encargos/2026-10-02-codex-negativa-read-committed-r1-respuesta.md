**VERDICT: APPROVE_WITH_NITS**

**SUMMARY:** La guarda cumple el objetivo acotado: rechaza cualquier aislamiento distinto de READ COMMITTED con `0A000`, antes de comprobar administración y ejecutar el resto del cuerpo. Los resultados aportados respaldan su propagación por ambas puertas y la conservación del comportamiento probado en READ COMMITTED. No encuentro un defecto bloqueante demostrado en el bloque añadido.

**FINDINGS P0–P3**

Sin hallazgos P0–P2 confirmados.

- **P3 — El caso de READ COMMITTED depende del valor predeterminado de la sesión.** Evidencia: en `test-negativa.sql`, esa sección utiliza `begin;`, mientras las otras especifican el aislamiento. Con un valor predeterminado distinto, obtendría `0A000` y señalaría un fallo aunque la guarda funcionase correctamente. Conviene usar `begin isolation level read committed;`.

- **P3 — La reversa del comentario no es exacta para cualquier comentario anterior.** Evidencia: la aplicación usa `rtrim(coalesce(..., ''))` y la reversa utiliza `rtrim(replace(...))`. Esto pierde espacios finales y convierte un comentario originalmente `NULL` en una cadena vacía. Además, `replace` elimina todas las coincidencias de la frase, no exclusivamente el sufijo añadido. **No es un fallo observado con los comentarios actuales:** el banco reporta su restauración. Con la frase intacta no quedan restos; si alguien modifica esa frase posteriormente, podría quedar texto sin retirar porque las huellas no protegen comentarios.

**RIESGOS / TEST GAPS**

1. **Orden de ejecución y puertas.** Los diffs demuestran que la guarda es la primera instrucción tras `BEGIN`. No permiten afirmar literalmente «antes de cualquier lectura»: faltan las declaraciones completas —cuyos inicializadores se ejecutan antes— y los cuerpos de las puertas. El banco sí demuestra que ambas puertas llegan a la guarda en REPEATABLE READ. No se aportan pruebas de las puertas en SERIALIZABLE o READ COMMITTED.

2. **Consumidores legítimos.** Bajo el contrato aportado de que PostgREST siempre usa READ COMMITTED, sus llamadas conservan el comportamiento. No hay evidencia suficiente para certificar el aislamiento de jobs, conexiones directas, edge que use SQL directo o sesiones de Studio. La afirmación «solo alcanzable con SQL lanzado a mano» es demasiado amplia: un proceso automático también puede seleccionar otro aislamiento. No se ha identificado aquí ningún consumidor legítimo afectado.

3. **Alcance del pre/postflight.** Las huellas verifican `prosrc`; los otros predicados verifican invariantes concretos. No prueban igualdad completa de metadatos: `proconfig @> array['search_path=""']` admite configuraciones adicionales, y la ACL comprobada no compara otorgantes ni opciones de concesión. Tampoco se compara `proleakproof`. Con `CREATE OR REPLACE`, dueño y ACL se conservan, por lo que **omitir una comparación de `proowner` no constituye por sí solo una regresión**. Para afirmar igualdad total, haría falta una comparación del catálogo antes/después; no basta con MD5 del cuerpo.

4. **Atomicidad pendiente de acreditar.** La migración principal transcrita no contiene `BEGIN/COMMIT`; la reversa sí. Si el ejecutor aplica todo en una transacción, los rechazos del postflight revierten el conjunto. Si ejecuta cada sentencia con autocommit, pueden quedar cambios parciales y el mensaje «no se toca nada» sería incorrecto. Falta el comando o contrato del ejecutor para resolverlo; no afirmo que actualmente se aplique sin transacción.

5. **Mutante y cobertura funcional.** El ciclo sin guarda → fallo de seis casos → aplicación → 8/8 → reversa → fallo es una prueba útil del cambio. Un administrador real en RR/SERIALIZABLE aportaría cobertura adicional, pero la guarda es incondicional y no depende del actor. También falta READ UNCOMMITTED si se quiere probar literalmente «cualquier otro modo».

6. **Fallo de «Cambiar».** El mismo error en la línea 551 antes y después respalda que ese fallo es previo al cambio. No demuestra por sí solo que su causa sea «banco sin datos» ni valida las comprobaciones posteriores que quedaron sin ejecutar. Puede ocultar fallos posteriores, aunque no aporta evidencia de una regresión causada por esta guarda.

**NEXT ACTIONS**

- Acreditar que el ejecutor aplica la migración atómicamente.
- Hacer explícito READ COMMITTED en el test y documentar las limitaciones del comentario.
- Precisar qué comprobaciones de «Cambiar» terminaron antes de la línea 551 y completar las pendientes con el entorno necesario.
- Adjuntar el resultado obligatorio de `auditor-rls`, no aportado aquí.

Estado según la evidencia: **PASS** negativa, retiro y ciclo de reversa; **FAIL** banco completo de cambio, reproducido también sin migración. Checks propios de este reviewer: **NOT RUN**.

**CONFIDENCE:** Alta sobre la guarda; media sobre las garantías operativas completas, por los cuerpos omitidos, el ejecutor no descrito y la cobertura funcional pendiente.
