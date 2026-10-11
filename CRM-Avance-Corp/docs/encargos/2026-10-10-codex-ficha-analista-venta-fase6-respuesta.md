VERDICT: **CHANGES_REQUESTED**

SUMMARY:
El lateral conserva las filas y el cambio SQL mantiene los filtros y cálculos anteriores. Sin embargo, la pantalla puede presentar la atribución como vendedor cuando el vendedor es desconocido, y las salidas de idempotencia omiten guardas importantes. El ensayo tampoco garantiza terminar en error cuando la migración ya está aplicada.

FINDINGS:

**[P2] Vendedor nulo: la pantalla muestra otra persona como quien vendió**

- **Archivo:** `app/src/components/app/inversionista-ficha.tsx`, `analistasDeLaOperacion`, líneas añadidas junto a la 27.
- **Evidencia:** la condición empieza con `i.analista_venta_id &&`. Si el servidor nuevo devuelve `analista_venta_id: null`, entra en la rama que muestra `analista_origen_nombre`.
- **Reproducción:** contrato importado con `analista_cierre_id = null`, atribución efectiva a Ana. La pantalla muestra «Analista de la operación: Ana», aunque no consta que Ana vendiera.
- **Impacto:** confunde vendedor desconocido con atribución conocida. El esquema admite ese nulo y el SQL lo conserva.
- **Recomendación:** distinguir claves ausentes —servidor antiguo— de vendedor explícitamente nulo. Con servidor nuevo, mostrar vendedor «Sin información»; definir con Miguel cómo presentar la atribución cuando no puede determinarse si son personas distintas.

**[P2] La idempotencia acepta permisos o dueño distintos de los esperados**

- **Archivos:** migración y `reversa.sql`; primeras ramas de retorno de sus bloques `DO`.
- **Evidencia:** la migración retorna con huella nueva y comentario esperado **antes** de comprobar ACL y dueño. La reversa retorna con huella anterior y comentario nulo antes de esas mismas comprobaciones.
- **Reproducción:** aplicar, conceder `EXECUTE` a `anon` y repetir la migración. La huella y el comentario siguen coincidiendo: informa «ya aplicada» sin rechazar la ACL modificada. Cambiar el dueño tampoco cambia `pg_get_functiondef`.
- **Impacto:** el éxito no acredita el estado de seguridad declarado. No introduce el permiso incorrecto, pero deja de detectar esa desviación.
- **Recomendación:** comprobar ACL, dueño y modo antes de cualquier retorno idempotente. El registro también debe comprobarlos si pretende certificar el estado instalado.

**[P2] El ensayo puede terminar correctamente y ejecutar `COMMIT`**

- **Archivo:** migración y `generar.py`, `MIGRACION_PLANTILLA`.
- **Evidencia:** el retorno «ya aplicada» precede a la comprobación de `crm.ficha_analista_venta_ensayo`. El ensayo contiene después `commit;`.
- **Reproducción:** ejecutar `ensayo-produccion.sql` sobre la función ya aplicada con el comentario esperado. El bloque retorna y la transacción termina correctamente.
- **Impacto:** contradice el contrato «acaba SIEMPRE en error». En esta ruta no hay cambios propios que deshacer, pero desaparece la garantía operativa y no se obtiene el resultado esperado del ensayo.
- **Recomendación:** hacer que también esa ruta termine en una excepción explícita cuando esté activado el ensayo. Añadir la prueba sobre estado ya aplicado.

**[P2] La reversa puede borrar un comentario ajeno posterior**

- **Archivo:** `reversa.sql`, entre la lectura de `v_comentario` y `comment ... is null`.
- **Evidencia:** con cuerpo nuevo y permisos esperados, no comprueba el comentario actual antes de eliminarlo.
- **Reproducción:** aplicar la migración, cambiar únicamente el comentario por una documentación posterior y ejecutar la reversa. La reversa acepta el estado y borra esa documentación.
- **Impacto:** sobrescribe un cambio ajeno pese a disponer de evidencia para detectarlo.
- **Recomendación:** exigir el comentario nuevo esperado antes de revertir; rechazar otros comentarios para revisión manual.

RISKS / TEST GAPS:

- **Visibilidad:** sí se revela una identidad adicional: el vendedor original puede ser distinto del analista que antes veía el lector. Eso coincide con la decisión descrita; no demuestra una fuga indebida. No se aporta una regla independiente que restrinja esos nombres para Directorio o inversiones demo.
- **Filas y empresas:** el lateral contiene un `SELECT` sin `FROM` y produce una fila, incluso con resultado nulo. No multiplica ni elimina inversiones. Las subconsultas escalares fallarían si encontraran múltiples registros; las restricciones de unicidad no están transcritas. El filtro de Directorio permanece limitado a Avance.
- **Definición de vendedor:** el SQL obtiene exactamente los campos acordados. No permite acreditar quién vendió originalmente una cadena completa: en renovaciones y upgrades identifica al vendedor registrado en **esa fila**. Falta evidencia específica de esos casos y de contratos importados sin vendedor.
- **Frontend:** compara UUID, por lo que dos personas homónimas siguen generando dos líneas correctamente. Para IDs iguales usa el nombre de atribución; con los subselects actuales ambos nombres proceden del mismo perfil. Los pares `<dt>/<dd>` agrupados en `<div>` dentro del `<dl>` no muestran un problema de accesibilidad.
- **Banco:** compara solo la primera página y sustituye el estado operativo por un doble con escritura deshabilitada. Es evidencia sólida del cambio acotado, pero no cubre páginas posteriores ni el recorrido operativo real.
- **Verificación:** banco y checks frontend **PASS según la salida aportada**. Ejecución independiente y ensayo en producción: **NOT RUN en esta revisión**.

NEXT ACTIONS:

1. Corregir la distinción entre vendedor nulo y servidor antiguo; probarla pasando por el esquema real.
2. Probar ACL y dueño modificados en ambas rutas idempotentes.
3. Probar ensayo sobre estado ya aplicado y reversa con comentario ajeno.
4. Añadir casos identificables de renovación, upgrade y vendedor nulo; verificar una segunda página.

CONFIDENCE: **HIGH** para los contraejemplos señalados; **MEDIUM** para la exactitud histórica del vendedor, que depende de datos y reglas no transcritos.
