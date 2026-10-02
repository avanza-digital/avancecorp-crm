**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** La lógica del filtro, los conteos sobre `previa` y la compatibilidad con los consumidores descritos son coherentes. Solicito cambios por dos falsos verdes en la verificación. No encuentro una fuga demostrada fuera del ámbito de cartera elegido; sí una exposición de potencial fuera de `leads_select` para el coordinador, que debe describirse explícitamente.

**FINDINGS**

1. **P2 — El postflight no verifica la identidad del ayudante que establece el ámbito.**

   Evidencia: en el `$postflight$` de la [migración](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/migrations/20261001212341_crm_cartera_filtro_potencial.sql), el cuerpo del ayudante solo se examina mediante:

   ```sql
   p.prosrc !~* '(count|sum)\s*\('
   ```

   Las comprobaciones de dueño, ACL y `proconfig` son sólidas, pero no verifican el predicado de ámbito, la bandera ni el gate del CRM. La llamada sin sesión tampoco los verifica: termina en la primera guarda.

   Por inspección, una variante que conserve la guarda de sesión y quite el predicado de ámbito pasaría este postflight. El mutante `m-ayu-todo-global` demuestra que esa modificación importa: produce cuatro fallos funcionales, pero no está cubierta por la identidad exigida al publicar.

   **Cambio solicitado:** fijar también la huella del ayudante ensayado y añadir un mutante de publicación que quite el ámbito conservando las guardas iniciales. Esto es un hueco del verificador; el cuerpo entregado sí contiene el predicado correcto.

2. **P2 — La comprobación conjunta de conteos puede aceptar respuestas de error.**

   Evidencia: en [prueba-filtro.sql](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/potencial-lead/prueba-filtro.sql), el caso «los cuatro conteos suman el total … API y envoltorio» detecta fallos mediante:

   ```sql
   suma_de_los_cuatro_conteos
     is distinct from (x.r #>> '{totales,vivos}')::int
   ```

   Si `pg_temp.envoltorio()` devuelve `{"error":"42501"}`, ambas expresiones son NULL. `NULL IS DISTINCT FROM NULL` es falso: esa respuesta **no cuenta como fallo**. Las comprobaciones individuales del envoltorio cubren C, V1 y G, pero no los otros siete actores de esa matriz.

   Hay una normalización similar en [test-rls.mjs](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/test-rls.mjs): `idsDe()` convierte una respuesta sin `data` en `[]`. Las aserciones manuales que esperan vacío pueden aceptar un error. El bucle anterior detectaría un fallo persistente, pero esas aserciones siguen siendo ambiguas.

   **Cambio solicitado:** exigir respuesta exitosa y campos presentes antes de comparar sumas o listas vacías. Añadir una prueba del propio verificador con una respuesta de error.

**Riesgos y respuestas a–g**

- **a. Ámbito y fuga.** En la cartera INVOKER, los conteos salen de `previa`, cuya lectura de `crm.leads` está sometida a RLS. Los UUID y fechas del cursor solo comparan contra esa base; no consultan el lead indicado por el cursor. No veo una inferencia de marcas ajenas por esa vía. Un `v_global` NULL tampoco concede acceso: una condición de ámbito debe resultar verdadera.

  **El envoltorio sí entrega información adicional fuera de RLS.** El caso 115 exige para C `E0 T1 F1 S2 v=4`, aunque su RLS no vea esa bandeja. Saber que hay cuatro leads no equivale a saber sus niveles. Si la bandeja contuviera un único lead, los conteos revelarían exactamente su potencial.

  Esto cumple el ámbito de reparto elegido en la decisión 3; por ello no lo clasifico automáticamente como una violación de ese contrato. Pero la garantía correcta no puede ser «todo potencial publicado corresponde a leads visibles por RLS». El coordinador recibe agregados de un ámbito mayor, con posibilidad de inferencia individual.

- **b. Ayudante DEFINER.** Es aceptable bajo ese contrato de ámbito y la superficie API descrita. `private` sin exposición impide la llamada RPC directa por PostgREST; **no impide la ejecución SQL**, que `authenticated` tiene expresamente concedida. No aparece en la evidencia una función expuesta que permita ejecutar SQL arbitrario, pero tampoco hay un inventario que permita descartar todas esas vías.

  No sustituiría el predicado por el espejo de `leads_select` manteniendo intacto el envoltorio: produciría los falsos «sin marca» identificados. Si se quisiera restringir también los agregados a RLS, habría que ajustar conjuntamente qué publica el envoltorio.

- **c. Compatibilidad.** Con los esquemas `v.object` descritos, la clave adicional se descarta sin romper validación. Los argumentos anteriores siguen resolviendo con el nuevo argumento opcional y una sola firma. El orden servidor → pantalla es correcto. Antes de publicar la pantalla nueva falta comprobar una llamada real por PostgREST después de recargar su caché; el catálogo SQL no acredita esa resolución.

- **d. Preflight y postflight.** No identifico un falso rojo concreto de `format_type` con las condiciones fijadas. Normalizar `search_path` y `quote_all_identifiers` es pertinente. Las huellas de `pg_get_functiondef` siguen dependiendo de la representación del servidor, y comparar `proacl` literalmente puede rechazar ACL semánticamente equivalentes con distinto orden. Serían rechazos conservadores, no aperturas de permisos.

  El postflight del ayudante sí cierra los huecos preguntados de ACL, opción de concesión, dueño y configuración adicional. Su carencia demostrable es la identidad del cuerpo del hallazgo 1.

- **e. Semántica y concurrencia.** Incluir cerrados activos es consistente con la base existente. Los conteos clasifican el inventario, no solamente los abiertos. El nivel seleccionado y `totales.vivos` se calculan sobre la misma `previa` materializada; no hay una carrera interna entre esas dos cifras. STABLE también conserva la instantánea de lectura. Entre solicitudes o páginas distintas sí pueden cambiar las marcas.

- **f. Rendimiento.** La materialización sin índice no implica por sí misma un problema: el equijoin permite un hash join. El riesgo concreto es que el ayudante obtiene todas las marcas activas del ámbito antes de aplicar etapa, búsqueda, recepción y ventana operativa. Puede incluir muchos convertidos antiguos que luego se descartan. Además, `base NOT MATERIALIZED` permite repetir el filtro en los distintos recorridos de `previa`. Los tiempos aportados respaldan el tamaño ensayado, no volúmenes mucho mayores ni planes genéricos.

- **g. Reversa.** El orden B → gestión es correcto. La reversa conserva datos y devuelve firma y declaración analítica; mantener `schema_migrations` está expresamente documentado. No identifico residuos imprevistos en lo transcrito. El cuerpo restaurado está omitido: su exactitud queda respaldada por el ciclo y el md5 aportados, no por una inspección independiente de esas 183 líneas.

**Test gaps — h**

Además de corregir el hallazgo 2, faltan casos especialmente útiles:

- Coordinador con **una única marca en una bandeja invisible por RLS**, para dejar inequívoco el contrato de información del envoltorio.
- Convertidos y descartados **sin marca**; convertido antiguo excluido sin fechas y recuperado mediante una recepción válida.
- Combinaciones no vacías de potencial con recepción, reasignación y gestión efectiva. Los fixtures transcritos no siembran asignaciones ni actividades que ejerciten positivamente esas ramas.
- Cursor con empate en `actualizado_en` y cursor construido con un UUID ajeno.
- Preflight de unicidad de `lead_potencial.lead_id`: la forma comprobada no incluye esa restricción, aunque el nuevo join depende de una fila por lead. No hay evidencia de que falte actualmente.
- Ejecución real del gate con `CRM_RLS_EXIGE_POTENCIAL=1`, incluyendo rechazo HTTP del esquema privado.

**NEXT ACTIONS**

1. Sellar la identidad del ayudante y comprobar el mutante de ámbito contra el postflight.
2. Hacer fallar explícitamente los verificadores ante errores o respuestas incompletas.
3. Incorporar los casos anteriores y precisar que el envoltorio autoriza al coordinador agregados de potencial sobre la bandeja de reparto.
4. Ejecutar el gate PostgREST antes de declarar verificado el contrato API.

**CONFIDENCE:** Alta en los dos falsos verdes y en el flujo SQL descrito; limitada respecto de superficies API no transcritas. Los resultados del banco son **PASS reportados**. PostgREST y advisors: **NOT RUN**. Esta revisión fue estática; no ejecuté comprobaciones.
