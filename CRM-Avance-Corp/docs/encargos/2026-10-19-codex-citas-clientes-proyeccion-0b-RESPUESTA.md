**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

Encontré dos P2 y un P3. No demostré una fuga entre roles ni de PII: los filtros coinciden con las dependencias adjuntas y `identidad_persona` usa únicamente identificadores autorizados.

La segunda aplicación aborta deliberadamente; no duplica objetos. La reversión es transaccional y no usa `CASCADE`. No encuentro un defecto concreto en esos mecanismos.

Revisión estática; las líneas citadas corresponden al SQL adjunto.

**FINDINGS**

**P2 — El preflight acepta un cambio de dependencia que desactiva la validación.**

En la [migración, línea 82](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/supabase/migrations/20261019213516_crm_citas_clientes_proyeccion.sql:82), sólo se compara `md5(prosrc)`. Este contraejemplo modifica comportamiento sin modificar ese hash:

```sql
ALTER FUNCTION private.gestiones_validar(date,date,uuid[]) STRICT;
```

La llamada de L109 pasa explícitamente `NULL` como tercer argumento. Con `STRICT`, PostgreSQL devuelve NULL **sin ejecutar el cuerpo**, omitiendo los controles de sesión, rango y rol. La llamada de `gestiones_clientes_identidades` también recibe ese argumento como NULL mediante su valor predeterminado.

Caso concreto: con un usuario gerencia válido, un rango invertido puede devolver una lista vacía en vez del `22023` exigido. El preflight acepta la dependencia modificada. Esto demuestra una insuficiencia del control de deriva; **no demuestra que producción tenga actualmente ese atributo**.

Acción: verificar también los atributos relevantes de las dependencias, especialmente `proisstrict`, seguridad, propietario, configuración y volatilidad. Incorporar este mutante al ensayo.

**P2 — Una respuesta válida del SQL puede ser rechazada por el consumidor preparado.**

[L102](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/supabase/migrations/20261019213516_crm_citas_clientes_proyeccion.sql:102) fija `v_ahora := now()`, que representa el inicio de la transacción. L122–123 filtran únicamente por el rango solicitado; no exigen `creado_en <= v_ahora`. L183 devuelve ese instante como `generado_en`.

Contraejemplo con dos sesiones en `READ COMMITTED`:

1. A inicia su transacción en T0.
2. B crea una reunión autorizada en T1 y confirma.
3. A consulta el lector en T2.

La respuesta incluye la reunión con `creado_en = T1`, pero devuelve `generado_en = T0`. El borrador `citasClientesProyeccionCoherentes` exige `creado_en <= generado_en`, por lo que rechaza todo el payload con `CITAS_CONTRATO`. También es posible durante una RPC: las consultas internas de una función `VOLATILE` pueden observar confirmaciones posteriores al inicio de la transacción.

Acción: acordar el significado temporal de `generado_en` y alinear SQL y validador. Si representa un corte, aplicarlo a la cohorte; si representa cuándo se produjo la respuesta, no usar automáticamente el inicio de la transacción. Añadir el caso con dos sesiones antes de conectar la pantalla.

**P3 — La batería muestra fallos, pero no hace fallar su ejecución.**

En el tramo final, `select n, case … 'FAIL' …` y `select 'TOTAL ' …` sólo imprimen resultados. `ON_ERROR_STOP` no convierte una comparación fallida en error SQL.

Además, el ensayo de 10 001 filas imprime cualquier `p->>'error'`: no exige mediante una aserción que sea `54000`. Un error distinto también permite terminar el script normalmente.

Esto no invalida un resultado inspeccionado manualmente de 48/48, pero impide tratar una salida exitosa del proceso como prueba de aprobación.

Acción: lanzar una excepción ante cualquier discrepancia y comprobar expresamente los dos resultados del tope.

**TEST GAPS**

- **Coste:** las 10 000 reuniones usan el mismo perfil `…c3`; `gestiones_clientes_identidades` las reduce a un único sujeto distinto. Ese ensayo no valida 10 000 clientes diferentes ni el coste de resolver personas F6. Faltan esa distribución, planes y concurrencia; no afirmo un timeout sin medirlo.
- **Exclusión de leads:** d7/d9 tienen `perfil_id` e `inversionista_id` nulos. Quedarían fuera incluso eliminando `lead_id is null`. La prueba no aísla ese predicado. Verificar si una restricción impide referencias mixtas; si no, ensayar una.
- **Paridad y bloqueos:** no se adjuntaron los cuerpos de `citas_gerencia_consulta` ni `postventa_estado_fn`. Las dos comparaciones de atribución aportadas no permiten certificar todos sus casos ni evaluar los candados.
- **NOT RUN por este reviewer:** banco, 48 casos, mutantes, rendimiento y reversión. Sus resultados son evidencia reportada por el PRIMARY.

**NEXT ACTIONS**

Corregir los dos P2, ensayar el mutante `STRICT` y la concurrencia temporal, y convertir la batería en un control que falle ante discrepancias. Ampliar la medición a clientes distintos.

**CONFIDENCE**

Alta en los contraejemplos estáticos; media en la evaluación global por falta de ejecución y de las dependencias completas.
