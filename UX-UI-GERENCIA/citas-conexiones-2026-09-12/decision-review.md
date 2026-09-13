# Evaluación de las dos revisiones

Ambos dictámenes de Claude fueron **CHANGES_REQUESTED**, no PASS. Codex evaluó sus observaciones y corrigió las pertinentes; la versión final se verificó con pruebas, sin una tercera consulta ni aprobación independiente de despliegue.

| Observación | Resolución del PRIMARY |
| --- | --- |
| Materialización global en el lector | Se extrajeron cierres compartidos y se acotó Citas por IDs. Una sola definición de estados y cierres. La selección usa subconsulta de pertenencia para evitar recorrer una lista grande por cada fila. |
| Coste de las firmas anteriores | Medido anterior/nuevo, global/propio y período nulo/fijo. Conversión: 454–520 ms anterior frente a 456–530 ms nuevo en el último banco. Citas global: 21,7 frente a 37,1 ms para 60.040 filas. Son costes locales explícitos; deben verificarse en rama, incluidos consumidores antiguos. |
| Dos EXISTS sobre historial/cierres | Sustituidos por joins y último cierre agrupado por lead. Igualdad completa del JSON contra el original. Ensayo de 10.000 citas/2.500 leads con cierres y reagendas: aproximadamente 774 ms nuevo, 552 ms anterior en la última corrida. No se promete mejora de latencia frente al lector crudo; se preserva su resultado centralizando las reglas. |
| Selección no vacía | EXCEPT ALL en ambos sentidos para citas y cierres, con IDs reales, uno inexistente, duplicado y NULL, además de ámbito vacío. PASS. |
| ACL y consumidor no declarado | Preflight contra permisos observados; helpers nuevos sólo postgres. El gate vigila sus ACL y exige declaración a consumidores de `conversion_cierres`. Se probó un GRANT indebido y un consumidor sintético no registrado. Ambos rechazados. |
| Estado comercial nulo | Campo ausente permite compatibilidad; null sigue siendo error. El servidor rechaza explícitamente un estado no clasificable. El CHECK real `tareas_estado_valido` ya limita los cinco estados; se conserva defensa ante cambios futuros. |
| Fan-out de equipo | Descartado con catálogo real: `crm.equipo` tiene `PRIMARY KEY (perfil_id)`. Evidencia en `restricciones-remotas.json`. |
| Dependencia implícita de invalidación | El detalle se invalida explícitamente. Sus ancestros lo excluyen de su refetch para evitar peticiones duplicadas. |
| Carrera en recargas sucesivas | No reproducida con QueryClient real: respuestas 0/1 tardías no sustituyen a 2; termina sin invalidación pendiente. Se conserva la actualización después de editar datos o atribución del lead. |
| Precedencia servidor/cliente | El test ya existía, no se adjuntó en la primera consulta. Verifica precedencia, fallback por ausencia y rechazo de null/estado desconocido. |
| Huellas y reejecución | Se preserva la convención BEGIN/COMMIT de la migración previa de Citas. El preflight de ejecución única bloquea firmas inesperadas; no se hace un upsert ciego. Las otras dos candidatas locales inspeccionadas (Control de Citas y leads recibidos) no fijan las huellas de estos núcleos. Reconfirmar catálogo y ledger antes de instalar. |

El censo global sigue pendiente por los cuatro lectores ajenos y el techo 30 frente a 34 contadores. El ensayo de gobernanza habilita temporalmente dobles declarados únicamente en una transacción local que termina en rollback; no concede excepciones a producción.

Quedan NOT RUN la matriz real de Supabase/PostgREST, los advisors, replay/planes sobre esquema completo y publicación. Las mediciones no sustituyen esos gates. Los valores exactos, planes y buffers están en `planes-volumen-local.json`; tienen variación con la carga local.
