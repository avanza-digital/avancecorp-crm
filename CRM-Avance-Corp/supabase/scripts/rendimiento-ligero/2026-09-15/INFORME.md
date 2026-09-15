# Prueba ligera de rendimiento — 15/09/2026

La mejora prioritaria es reducir el tiempo de la ficha multiempresa de Gerencia. Tres muestras dieron **2,66–2,89 s** de ejecución dentro de PostgreSQL. El contraste con la misma persona dio **2,72 s en Gerencia y 0,84 s en Analista**. Los importes y datos comerciales no se modificaron.

Miguel autorizó la prueba ligera y, ante la ausencia de navegador conectado, eligió expresamente **seguir con servidor y consultas**. No se implementó ni publicó una optimización.

## Resultados de consultas reales

Medianas de las tres muestras `base_1`–`base_3` (`resumen_base` en el JSON). `resumen` agrega todas las fases por operación y muestra sus fases y cantidades. Son tiempos de la función SQL, sin red del usuario ni renderizado.

| Operación | Gerencia | Analista | Muestras por rol |
|---|---:|---:|---:|
| Listar Cartera | 1,249 s | 0,320 s | 3 |
| Buscar «MARIA» | 1,221 s | 0,289 s | 3 |
| Abrir ficha | 2,723 s | 0,820 s | 3 |

Gerencia ve 492 personas y recibe 25 filas por página; Vladimir ve 21 y recibe 21. «MARIA» devuelve 15 resultados a Gerencia y ninguno a Vladimir: las búsquedas no tienen igual selectividad. La búsqueda adicional «a» coincidió con todo el conjunto visible (492/21), en 1,330 s y 0,295 s; no prueba una búsqueda parcialmente selectiva para ambos roles. Los parámetros figuran en el JSON. Las fichas de la muestra base tienen una inversión cada una. El contraste de la misma persona devuelve 2.072 bytes de JSON en ambos roles.

Las consultas exploratorias que alimentan Hoy (resumen/cola/agenda postventa, conversión mensual, metas, reuniones y conversiones del mes, según el rol) midieron **0,022–0,500 s**, con una o dos muestras por consulta; esto no representa la carga completa de Hoy. Estado y postventa de la ficha: aproximadamente 0,09–0,10 s.

**39 invocaciones de funciones completadas sin error SQL**, además de dos diagnósticos con EXPLAIN. Son dos sondas iniciales con CTE materializados (respuesta exitosa con tiempos y filas) y 37 invocaciones medidas en bloques DO. Las sondas iniciales no exportaron sus marcas absolutas de inicio/fin: se conservan como `null`, no se reconstruyen. No hubo timeouts en estas mediciones.

## Hallazgo e hipótesis de causa

**Observado:** el núcleo `private.cartera_f5_personas_visibles()` tardó 1,216 s para Gerencia (492 filas, 23.225 bloques encontrados en memoria) y 0,153 s para Analista (21 filas, 18.859 bloques encontrados en memoria). Es una muestra diagnóstica por rol, ejecutada como propietario de la función con identidad local. Ambos planes muestran cero bloques leídos de disco y cero temporales; no demuestra ausencia de presión de CPU ni de otros problemas fuera de la muestra.

La ficha llama ese núcleo al entrar y al salir:
- `20260914213928_crm_coopac_condiciones_anuales.sql:799`.
- `20260914213928_crm_coopac_condiciones_anuales.sql:910`.

**Inferencia:** generar de nuevo el conjunto visible para abrir una sola persona contribuye de manera importante a la demora de Gerencia. Los planes externos y la lectura de código no desglosan todos los costes internos; no se atribuye el 100 % del tiempo a esa función.

Como orientación, dos invocaciones de 1,216 s sumarían 2,432 s frente a los 2,722 s de la ficha. En Analista, dos de 0,153 s sumarían 0,306 s frente a 0,840 s, dejando unos 0,534 s sin atribuir. Son estimaciones a partir de muestras distintas y contextos de ejecución diferentes, no un porcentaje causal demostrado ni una promesa de reducción. Un perfil interno en banco aislado debe confirmar la distribución del coste.

**Siguiente mejora propuesta:** hacer eficiente la comprobación y lectura de una persona dentro del núcleo canónico existente. Conservar la revalidación de acceso, la resolución de fusiones, la exclusión demo y el alcance por rol; no sustituirlos por una caché de permisos ni por cálculos financieros paralelos. Ensayar la futura corrección en banco aislado, contrastar igualdad de datos/capacidades y volver a medir.

Esta propuesta atiende primero la ficha. No se presupone una reducción de Cartera ni de búsqueda por el mismo cambio. La generación de detalles de las filas paginadas es un candidato posterior, conservando la semántica de totales y visibilidad del núcleo.

El frontend revalida Cartera/ficha cada 15 segundos (`inversionistas-queries.ts:14–17`). Eso puede repetir trabajo mientras la pantalla está abierta; es evidencia de configuración, no una medición de saturación. No se cambió esa política.

## Servidor web y simultaneidad

**Rendimiento HTTP del CRM: NOT RUN.** Las tres peticiones de diagnóstico devolvieron 403 con el desafío JavaScript de Hostinger/hcdn («Checking your browser before accessing»). Se midió la respuesta del desafío, no la entrega del CRM. No se desactivó la protección ni se incrementó la carga HTTP. Esto no demuestra una caída para usuarios con navegador.

**Carga simultánea: NOT RUN.** Se enviaron dos llamadas juntas. Las marcas de tiempo del servidor muestran que Gerencia terminó a las 16:36:07,908 UTC y Analista comenzó a las 16:36:11,819 UTC: cero solapamiento. El canal de ejecución no permitió acreditar concurrencia real, por lo que no se intentaron tres ni se declara capacidad para dos/tres usuarios.

**Navegación, login real, Data API y tiempos de pantalla: NOT RUN**, conforme al alcance reducido elegido por Miguel.

## Método, límites y estado final

Cada lote utilizó `BEGIN READ COMMITTED`, rol SQL `authenticated`, identidad local y `ROLLBACK`. Se invocaron los RPC/núcleos del producto; no se recrearon cálculos financieros. Los registros transitorios de auditoría se revierten con el lote. `statement_timeout=8s` limita el bloque completo; `lock_timeout=1s` e `idle_in_transaction_session_timeout=10s`. La regla de parada del muestreo fue error o más de 3 s por invocación. Ninguna la superó. No se limpiaron cachés.

La ficha llama a `inversion_persona_contexto`, que puede tomar su bloqueo operativo existente sobre una persona real y mantenerlo hasta el `ROLLBACK`. No se midió cuánto duró ese bloqueo ni si otros usuarios esperaron durante los lotes. El límite de un segundo solo limita la adquisición de locks por la prueba; no limita la espera de otros usuarios. El DO estuvo limitado a ocho segundos, pero ese límite no acredita ausencia de impacto ni mide la retención exacta. En futuras mediciones, ejecutar una sola ficha por transacción o usar banco aislado. No se afirma ausencia total de efectos sobre contadores o secuencias.

`clock_timestamp()` se tomó antes y después de invocar cada función. Los dos planes de diagnóstico usaron `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)` y transacción de solo lectura: [documentación oficial](https://www.postgresql.org/docs/17/sql-explain.html). No se confundió la duración del transporte MCP con la ejecución SQL.

Salud inicial/final: cero sesiones esperando locks en ambos cortes, cero sesiones inactivas en transacción y cero deadlocks acumulados; al terminar, cero sesiones de esta prueba. Son fotografías, no monitoreo continuo ni medición de CPU/memoria. El proyecto respondió `ACTIVE_HEALTHY`.

La muestra no estima p95/p99, throughput ni capacidad máxima. No cierra G7/F8. El build web vigente no pudo releerse por el desafío; el último frontend documentado es `d93d805`. El repositorio recibió commits ajenos durante la medición; solo se guarda esta evidencia propia.

## Evidencia y revisión

- [Mediciones, planes y salud saneados](MEDICIONES.json).
- [Plantilla de una medición](MEDIR.sql), para conexión administrativa autorizada y UUID por parámetros.
- [Revisión independiente de Claude](REVISION-CLAUDE.md): `CHANGES_REQUESTED`, sin P0/P1. Consideró proporcionado el método y respaldó la prioridad de la ficha; pidió precisiones documentales.

El PRIMARY incorporó los límites de bloqueos operativos, separó el agregado completo del de las muestras base, identificó las dos sondas iniciales, añadió parámetros de búsqueda y acotó la atribución y alcance de la mejora. No adoptó la estimación porcentual como un techo demostrado. No hubo segunda revisión ni se declara un PASS final de Claude.

**Verificación documental PASS:** JSON parseado, 39 mediciones comprobadas, medianas recalculadas, ausencia de UUID de clientes/claves y referencias locales revisadas. **Plantilla psql literal NOT RUN**; el método CTE equivalente sí se ejecutó mediante la conexión administrada. Gates de producto NOT RUN porque solo se añadieron documentación y evidencia, sin cambios de runtime.
