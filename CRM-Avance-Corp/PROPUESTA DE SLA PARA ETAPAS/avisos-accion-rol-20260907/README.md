# Avisos por acción y rol — entrega del 7 de septiembre de 2026

Estado: **implementado y validado localmente; no publicado**. Falta confirmar el SQL exacto según `Inicio.md`, aplicar exclusivamente esta migración y verificar el artefacto servido.

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

## Publicación pendiente

1. Confirmar el SQL exacto enlazado arriba; una aprobación anterior no cubre esta migración todavía no mostrada.
2. Comprobar nuevamente fuentes, remoto y Main; construir el artefacto desde el commit limpio coincidente con `avancecorp/main`.
3. Publicar la interfaz compatible, aplicar solo la migración confirmada y verificar huellas/gates/lectores reales/artefacto servido y casos reportados.
4. Registrar cierre productivo, advisory antes/después y versión. Este documento **no acredita un deploy**.
