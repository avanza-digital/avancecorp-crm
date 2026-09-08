# Avisos por acción y rol — entrega del 7 de septiembre de 2026

Estado: **publicado y verificado en producción, con el pendiente previo de Citas cerrado**. Miguel confirmó el SQL exacto con «sii haz deploy» y retomó la publicación con «sigue» después de su pausa. Los siete controles ejecutados y el cierre de reconstrucción están aprobados. La incidencia de Citas y su resolución posterior se documentan al final; esto acredita los controles concretos ejecutados.

## Comportamiento

- Primera gestión pendiente significa que falta el intento reconocido de la asignación actual. No exige respuesta del cliente. Agendar sin gestionar conserva el vencimiento inicial.
- Una gestión reconocida y una tarea comercial futura válida mantienen la próxima actividad, incluso con tope de etapa agotado o tres reprogramaciones.
- Una actividad vencida es la acción principal, aunque exista otra futura o primera gestión sin hacer. Sus causas siguen disponibles en filtros; la ficha evita órdenes duplicadas.
- Sin próxima tarea comercial, se retoma seguimiento al vencer la cadencia; cancelar no inventa una gestión ni regresa a primera atención.
- Supervisor/Gerencia reciben además la revisión comercial correspondiente. No se cambian plazos, presupuestos, writers, hechos históricos, métricas v1 ni permisos.
- La ficha pide al servidor la tarea exacta para abrir su cierre, incluido su tipo real. Puede recuperarla fuera del lote local; el título libre no determina el tipo.
- La interfaz no afirma que no hay próxima actividad mientras la lectura está sin confirmar. En el modelo nuevo no utiliza el tamaño del lote local como total de Agenda.

## SQL y contrato

Migración: [`20260907212612_crm_sla_avisos_por_accion_y_rol.sql`](../../supabase/migrations/20260907212612_crm_sla_avisos_por_accion_y_rol.sql).
Reversión: [`rollback-sla-accion-rol.sql`](../../supabase/scripts/rollback-sla-accion-rol.sql). Huellas exactas en `entrega.json`.

Se reemplazan tres cuerpos dentro del núcleo existente: decisión, ventana autorizada y cola. Preflight de ocho fuentes publicadas, `lock_timeout=5s`, `statement_timeout=30s`, gate del núcleo y transacción completa. No crea funciones nuevas, tablas, políticas, permisos ni cron.

Los RPC mantienen `version: 2`; añaden `modelo_avisos: 3` y `proximo_cambio_en`. Cada estado incorpora `operacion` (modelo, aviso principal, próxima acción y frontera temporal) y `avisos_mostrados` autorizados. `avisos` conserva las causas para filtros y conteos; `avisos_mostrados` presenta una acción de atención y las revisiones de supervisión. La respuesta nueva es compatible con consumidores anteriores; la UI nueva conserva textos anteriores cuando falta el identificador del modelo.

El cursor incluye modelo y una huella del orden/causas de la ventana autorizada. Cambios de cartera o de vencimiento invalidan una posición anterior; la UI vuelve a la primera página. Se conservan 10/25/50 por página y módulos separados. La vista Hoy del analista no recibe nuevamente Seguimiento comercial.

## Verificación

- Regresión previa: 9 grupos de escenarios nuevos fallan con la definición publicada (incluyen verificaciones de contrato aún inexistente). Evidencia `regresion-anterior.json`.
- Núcleo: 66 pruebas correctas en PostgreSQL 17, con fixtures reducidos y dobles de autoridad declarados. Incluyen cuatro etapas, primera gestión y sus fronteras, contactos sin respuesta, tareas múltiples/administrativas/ambiguas, cancelación y reprogramaciones, asignaciones incoherentes, modos, restricciones, paginación y cursor anterior.
- Integración: 29 pruebas correctas sobre esquema completo restaurado, autoridades, RLS, writers, triggers y recibos reales. Incluyen cierre y sucesora atómicos, rechazo y retry, reasignación, descarte/reapertura, permisos de distintos equipos, límites, reversión y reaplicación. Cron se restaura como metadata: no existe worker administrado ni HTTP en el banco; no se simulan sus ejecuciones.
- Frontend: `npm run check` y suite E2E de SLA; resultado final y capturas en `verificacion-frontend.json`. Las pruebas de navegador interceptan el backend en loopback; no escriben en producción.
- La prueba con QueryClient real comprueba frontera con reloj local desfasado, vuelta de foco, reconexión y fallo conservando datos sin confirmarlos. Una lectura fallida usa el respaldo de un minuto y no produce una consulta cada segundo.
- En Chromium activo el aviso temporal apareció a menos de dos segundos de la frontera simulada, sin acción del usuario. No garantiza puntualidad en pestañas suspendidas o sin conexión; se revalida al regresar.
- El gate de duplicación fallaba también en el commit base: contaba el JSON de evidencia SQL como código de aplicación. Se renombró a `*.test.fixture.json` y actualizaron sus dos imports de pruebas; contenido idéntico, umbral intacto. Duplicación de líneas: 0,64%, por debajo del 0,8%.
- Las cuatro advertencias de accesibilidad existentes de `coverflow-carousel.tsx` permanecen fuera del alcance de esta entrega; lint no reporta errores nuevos.

## Contraste consistente de cartera

Foto única: 7 de septiembre, 16:45:17 Lima. **1.272 oportunidades y 863 tareas**. Se ejecutaron los dos cuerpos reales con la misma foto normalizada de los proveedores y el mismo reloj, en una base local independiente. Los proveedores de esta comparación son dobles explícitos de hechos; la autoridad se prueba separadamente con el esquema completo. La foto con IDs se conserva solo en almacenamiento temporal privado; el repositorio recibe agregados.

| Causa | Publicado | Candidato |
|---|---:|---:|
| Primera gestión/atención pendiente | 319 | 121 |
| Seguimiento pendiente | 500 | 419 |
| Tareas vencidas | 459 | 459 |
| Revisiones comerciales | 438 | 438 |
| Oportunidades pendientes para analistas, agregadas | 609 | 581 |
| Oportunidades pendientes para supervisión global | 634 | 634 |

Los grupos por causa se solapan y no deben sumarse como oportunidades. Cambian 248 acciones principales: 214 pasan de primera atención a la tarea vencida, 17 a próxima tarea, 6 a seguimiento y 11 de seguimiento a próxima tarea. Todas las transiciones se explican y verifican; no se pierden tareas vencidas ni revisiones. Los campos históricos, compromiso, seguimiento de política y etapa son iguales antes/después. Los dos patrones reportados conservan su próxima tarea: la etapa agotada mantiene revisión de supervisión y la etapa vigente no la inventa.

## Publicación verificada

Fuente limpia `1e580d77f95efb014199ad3e7acbd45e0b514a76`, idéntica a Main y `avancecorp/main` antes de construir. Release `crm-20260907T231539Z-1e580d77f95e`, build `build-20260907T231539249Z`, ZIP SHA-256 `84d71bd5f91bf4a1f023d60581e298f91a4d3efeec7dd9e0cc0c30e18fe8d3f6`. Se preservan los cambios de trabajo ajenos y la ascendencia del release anterior de Citas `431e926e6d8d`.

La interfaz compatible se publicó primero. Después de la pausa se purgó caché y verificaron 78 archivos (65 hashes exactos, 12 imágenes optimizadas y configuración protegida), ZIP 404 en CRM/portal y tres lecturas estables de versión, sin fallos. Evidencia: [produccion-http.json](produccion-http.json).

SQL aplicado el 07/09 a las 19:26:39 Lima, con cuerpo exacto. MCP asignó `20260908002639`; se alineó únicamente su versión de ledger a `20260907212612`, comprobando nombre, SHA, origen único, destino libre y demás campos intactos. No se reaplicaron efectos. Se verificaron tres fuentes nuevas, cinco protegidas, autoridad, política y control activo/revisión 1.

Cuatro lecturas autenticadas reales (dos analistas, supervisión y Gerencia) concilian ficha, cola y campana. Los dos patrones reportados conservan la próxima tarea sin aviso de contacto inmediato; la etapa agotada mantiene solo la revisión autorizada para Gerencia. La lectura de otro analista devuelve cero filas. Páginas 1–10 y 11–20 sin duplicados y con total concordante. Los conteos son del instante observado. La sesión disponible de Gerencia permitió comprobar ambas fichas en Chrome; no se ingresaron credenciales ni se realizaron gestiones de prueba.

En la verificación inicial pasaron los seis controles de vigencia, auditoría, F7 y SLA, más el cierre de reconstrucción. Advisors de seguridad: 210 antes y después, sin altas/bajas ni errores. El control ampliado `assert_analitica_leads_citas` fallaba por una huella de excepción desactualizada del agregador de Citas: su cuerpo coincidía con la migración de Citas ya publicada antes de esta entrega. Se conservó el rechazo y se registró el pendiente separado en el vault. El banco integral usado para SLA contenía la versión anterior de ese agregador, por lo que no acreditaba paridad de todas las funciones productivas.

El pendiente de Citas se corrigió después, el 07/09 a las 21:03:47 Lima, mediante `20260908020020_crm_citas_repara_huella_control.sql`, con revisión independiente y confirmación del usuario. Se actualizó únicamente la huella y el sello del registro, conservando cuerpos, permisos, otras excepciones y tope. Ahora pasan los siete controles y el cierre de reconstrucción. La comprobación posterior de Gerencia concilia los dos cortes mensuales revisados. [Cierre y evidencia de Citas](../../supabase/scripts/citas-control-20260907/README.md). Los JSON de la publicación inicial se conservan como evidencia histórica.

Evidencia completa y límites: [produccion-verificacion.json](produccion-verificacion.json). Reversión de esta entrega: aplicar primero el rollback SQL guardado y después recuperar el frontend anterior `crm-20260907T195955Z-431e926e6d8d.zip`. El commit de cierre solo documenta esta publicación y su reconciliación de metadata; no altera el artefacto.
