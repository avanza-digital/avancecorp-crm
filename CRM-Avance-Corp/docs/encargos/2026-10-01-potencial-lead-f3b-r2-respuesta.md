**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** El nuevo ámbito del ayudante coincide con la policy transcrita. Encontré falsos verdes adicionales en las comprobaciones y una omisión en la guarda de reversa. Los hallazgos siguientes proceden de revisión estática; las ejecuciones del banco son evidencia aportada.

**FINDINGS:**

1. **P2 — El verificador de sumas todavía acepta un resumen incompleto.**  
   En [prueba-filtro.sql](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/potencial-lead/prueba-filtro.sql), la comprobación de «18 respuestas, 0 malas» acepta:
   ```sql
   x.r = '{"potencial":{}}'::jsonb
   ```
   La respuesta existe, no contiene `error` y tiene la clave `potencial`. Sin embargo, tanto la suma como `totales.vivos` producen SQL NULL; `NULL IS DISTINCT FROM NULL` devuelve false. Esa respuesta cuenta como buena.

   **Corrección:** exigir los cuatro conteos y el total, y comprobar la igualdad mediante una condición positiva con `IS NOT TRUE` para rechazar cualquier resultado desconocido. Añadir este contraejemplo al ensayo del propio verificador.

2. **P2 — «Ayudante ⊆ RLS» puede aprobar cuando falla su oráculo.**  
   En el mismo archivo, `pg_temp.ve_rls` devuelve NULL ante cualquier excepción. La aserción evalúa:
   ```sql
   where not (
     pg_temp.l(...) = any(pg_temp.ve_rls(...))
   )
   ```
   Con ese NULL, la condición resulta desconocida para todas las filas: no cuenta ninguna infracción y devuelve el `0` esperado. Asimismo, un texto `error ...` del ayudante se transforma mediante `pg_temp.l` en NULL y puede desaparecer de la comprobación para actores con filas visibles.

   **Corrección:** comprobar primero que ambas lecturas terminaron correctamente y después comparar UUID directamente. La conversión del ayudante a nombres mediante `join lds` también descarta cualquier ID desconocido antes de verificarlo. Estos son falsos verdes de esa aserción; otras pruebas pueden detectar algunos de esos fallos.

3. **P2 — La reversa omite formas válidas de pasar el argumento nuevo.**  
   En [reversa-filtro.sql](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/potencial-lead/reversa-filtro.sql), la búsqueda:
   ```sql
   p.prosrc ~* 'p_potencial\s*=>'
   ```
   no detecta un consumidor PL/pgSQL que use:
   ```sql
   crm.cartera_filtrada_fn(p_potencial := 'estrella')
   ```
   ni una llamada posicional con 14 argumentos. Ese consumidor puede incorporarse después de la publicación; la guarda lo acepta y el `DROP` no tiene por qué detectar la dependencia textual de PL/pgSQL. La reversa puede terminar correctamente y dejarlo fallando al ejecutarse.

   **Corrección:** reutilizar en la reversa el censo estricto de consumidores y la huella del envoltorio permitido. Añadir mutantes con `:=` y con 14 argumentos posicionales. No hay evidencia de que actualmente exista uno de esos consumidores.

4. **P3 — La comprobación HTTP de `private` acepta cualquier error.**  
   En [test-rls.mjs](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/test-rls.mjs), `Boolean(error) && data == null` también acepta errores de transporte, de ejecución o `PGRST202`. Eso no acredita que el esquema esté fuera de la API.

   **Corrección:** exigir el rechazo específico de esquema no expuesto, `PGRST106`. Los demás errores deben dejar esa comprobación fallida o inconclusa.

**Respuestas sobre el diseño y las guardas:**

- **a. Espejo y NULL:** sí, el predicado transcrito es equivalente. `IN (subconsulta)` y `= ANY(array(subconsulta))` conservan aquí la semántica de coincidencias, conjuntos vacíos y NULL. Un NULL no concede acceso; otra rama verdadera sí puede concederlo, exactamente como en la policy. El gate del ayudante usa correctamente `IS NOT TRUE`.

- **b. Habilitación del potencial:** no hay un falso negativo derivable de esa expresión: si la policy admite una fila, existe una rama global verdadera o una coincidencia con algún ID visible. `array(select …)` vacío produce `{}` y su `cardinality` es **0**, no NULL. Una matriz compuesta únicamente por NULL habilitaría el bloque sin aportar coincidencias; falta el cuerpo de `vendedor_ids_visibles` para descartar formalmente ese resultado. No hay evidencia de que ocurra. Tener ámbito tampoco exige tener leads actualmente.

- **c. Ejecución del ayudante:** no encuentro un contraejemplo concreto para esta consulta. El booleano independiente de las filas permite un filtro de ejecución única antes del `Function Scan`; un plan genérico conserva el parámetro y lo evalúa en cada ejecución. `MATERIALIZED` por sí solo no garantiza esa omisión. Falta un ensayo explícito con `plan_cache_mode = force_generic_plan`. Conviene hacerlo también mediante el envoltorio de coordinación: su base tiene cuatro filas, mientras que la API de coordinación está vacía y podría no demandar el ayudante incluso sin la guarda.

- **d. Huellas:** `search_path` vacío y `quote_all_identifiers = off` resuelven las variaciones de sesión identificadas. Las huellas del texto descompilado pueden cambiar entre versiones de PostgreSQL o si cambia el cuerpo, incluidos comentarios. No veo una causa nueva de falso rojo con el mismo servidor y las mismas definiciones. Repetir el ciclo sobre el volcado nuevo sigue siendo necesario para el envoltorio y el censo.

- **e. Guard 7:** sí, un comentario dentro de `prosrc` puede provocar rechazo. Lo dejaría como guarda conservadora para esta migración. Su carácter textual debe quedar explícito; no constituye un análisis completo de dependencias.

**Riesgos y test gaps:** el ciclo figura como **PASS según la salida aportada**. `test-rls.mjs` sigue **NOT RUN**; también quedan pendientes el banco con volcado nuevo y la sonda HTTP de publicación. No ejecuté comprobaciones adicionales.

**NEXT ACTIONS:** corregir las comprobaciones anteriores, añadir los contraejemplos como pruebas o mutantes y repetir el ciclo previsto. Incorporar el ensayo forzado de plan genérico con coordinación a través del envoltorio.

**CONFIDENCE:** alta en los hallazgos estáticos y en la equivalencia del predicado; media sobre el comportamiento operativo pendiente de ejecutar.
