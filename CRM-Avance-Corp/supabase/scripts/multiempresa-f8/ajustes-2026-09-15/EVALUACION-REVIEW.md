# Evaluación de Claude por el PRIMARY

## Publicación

- Merge: se acepta exigir evidencia. El [contrato MCP](https://github.com/supabase-community/supabase-mcp/blob/f36c421225515296076fb86bb8a729e5432eedca/docs/production.md#merge-to-production) establece aplicación incremental. Su implementación llama POST /merge con cuerpo vacío; el Dashboard calcula diff y registra una migración aparte. Se usa exclusivamente merge directo y comparación de historial.
- Historial: el merge F8 anterior recibió un elemento con SQL completo y lo segmentó en 43/10 sentencias. Las ocho últimas migraciones observadas conservan BEGIN/COMMIT. Se rechaza renumerar o reparar historia ajena: los mapeos fuente/registro ya son el convenio documentado; se preservan las 288 filas del padre.
- Destino CLI: `--linked --project-ref` tiene prioridad explícita. Prueba independiente: rama con 15 Auth ficticios, 289 filas y dos columnas nuevas frente al padre original con 502 Auth, 287 filas y cero columnas. Se corrigió el rótulo del helper de advisors.
- Edge: el gate detectó el PDF v16 publicado por otra tarea. Se actualizó la rama. Su bundle se recompiló; nueve archivos completos y configuración coinciden con padre/repositorio, mientras las otras 18 Edge conservan la misma huella. Se limita la aceptación a ese par concreto de hashes.
- Compatibilidad: los once argumentos HTTP antiguos y reintentos pasaron. Las columnas nuevas son nullable; no hay backfill. La reversa frontend no exige borrar columnas.
- Oracle: se explicita que las 37 fichas cabían en una página. El vencimiento mantiene la regla de la ficha anterior. No se declara cobertura multipágina HTTP ni tiempos productivos a partir del banco.
- Limpieza: eliminar la rama propia y sus credenciales privadas al terminar.

## Corrección PT409

La prueba HTTP expuso un fallo real: PostgREST 14.5 reintenta 40001 aun cuando representa una revisión que nunca será válida. [Código 14.5](https://github.com/PostgREST/postgrest/blob/v14.5/src/PostgREST/MainTx.hs#L89), [incidente upstream](https://github.com/PostgREST/postgrest/issues/3673), [corrección upstream](https://github.com/PostgREST/postgrest/pull/4222).

Se acepta el PASS de Claude respaldado por HTTP, SQL y pruebas de guardas. Se fijó search_path vacío y se verificaron las cuatro sustituciones exactas, sin capturar fallos reales de serialización. Ambos retornos son jsonb y todos los argumentos son tipos pg_catalog. Propietarios y ACL permanecen intactos.

La recomendación de esperar PT409 en la segunda confirmación simultánea no corresponde al contrato: repetir la misma operación confirmada debe devolver éxito idempotente. El ensayo real verifica una única inversión y exactamente un reintento.

El intento explícito de cambiar empresa se rechaza antes con 22023. Se mantiene esa validación. La rama de empresa modificada en catálogo y la carrera de identidad no se fuerzan modificando datos operativos; el delta exacto garantiza que sólo cambia el código de sus rechazos.

El inventario global de otros 40001 se documenta por separado: no se modifican masivamente otras funciones ni el portal dentro de este arreglo.
