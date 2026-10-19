# Entrega, instalación y activación del recorrido

El Goal original terminó con código integrado y ZIP verificable. El frontend ya se publicó, pero el ZIP de la web no instala su backend. El 19/10/2026 Miguel aprobó comenzar la [puesta en marcha integral](../recorrido-activacion-integral/PLAN-Y-ESTADO.md). Esta guía recoge la política corregida; no acredita una instalación ni activación productiva. El estado comprobado está en el nuevo plan.

## Backend requerido

El paquete integral contiene, en este orden, quince archivos de `supabase/migrations/` (los siete últimos corresponden a esta puesta en marcha):

1. `20261019001500_crm_recorrido_evaluacion.sql`
2. `20261019001501_crm_recorrido_evaluacion_hardening.sql`
3. `20261019001600_crm_recorrido_oficina.sql`
4. `20261019001601_crm_recorrido_oficina_hardening.sql`
5. `20261019001700_crm_recorrido_conversion.sql`
6. `20261019001701_crm_recorrido_conversion_hardening.sql`
7. `20261019001702_crm_recorrido_revision_pr.sql`
8. `20261019001703_crm_recorrido_revision_pr_hardening.sql`
9. `20261019061000_crm_recorrido_todos_pendientes.sql`
10. `20261019061001_crm_recorrido_todos_pendientes_hardening.sql`
11. `20261019061002_crm_recorrido_indice_cita.sql`
12. `20261019061003_crm_recorrido_conflicto_http.sql`
13. `20261019061004_crm_recorrido_conflicto_http_hardening.sql`
14. `20261019061005_crm_recorrido_revision_claude.sql`
15. `20261019061006_crm_recorrido_revision_claude_hardening.sql`

Cada bloque contiene preflight/postflight y hardening. Las huellas de las funciones previas deben coincidir: si el backend cambió, detener la instalación, comparar el nuevo contrato y preparar una migración aditiva. No quitar preflights, forzar versiones ni editar migraciones ya comprometidas. No se modifica el esquema `public` y no se requiere desplegar una Edge nueva: el handler existente de acceso ya transmite el rechazo público del servidor.

Los ajustes del ensayo hosted cubren la FK de la cita de oficina con un índice y cambian el conflicto de revisión del control a HTTP 409 (`PT409`). `40001` no es un error de negocio apropiado: PostgREST 14 puede reintentarlo indefinidamente. Se mantiene la revisión optimista, la autorización gerencial y la auditoría. La revisión de Claude extiende PT409 a los tres conflictos deterministas de acceso al portal y rechaza una fecha explícita en observación/apagado: solo se programa al activar exigencia.

Antes de instalar en producción, completar el circuito de `supabase/migrations/LEEME.md`: rama Supabase autorizada, aplicación, matriz RLS, advisors y revisión del merge de base. La validación local usa copias desechables con Auth/PostgREST reales. La rama temporal está autorizada en «AVANCECORP- CRM-PORTAL», hasta 24 horas a US$0.01344/h, con eliminación al terminar. Una autorización de gasto no acredita que el ensayo hosted haya pasado: consultar su evidencia en el plan integral. Presentar el SQL exacto antes de la instalación productiva.

El frontend tolera una RPC de recorrido todavía ausente (`PGRST202`) y no muestra la guía en ese caso. Eso permite una instalación gradual, pero **no acredita que el bloqueo esté instalado**. Una lectura fallida distinta de RPC ausente se muestra como desconocida y nunca como requisitos cumplidos.

Las migraciones 01702/01703 incluyen las correcciones del PR: la gestión sin ciclo se conserva como `sin_ciclo`, sin acreditar asistencia ni entrevista ni inventar un ciclo. El estado `base_sin_ciclo` se mantiene para bases cargadas dormidas. Los cambios de evidencia conservan serialización; confirmar una tarea sin cambiar sus hechos no adquiere ese lock adicional.

## Alcance integral aprobado

| Caso | Tratamiento |
|---|---|
| Instalación inicial | `observacion`; guía informativa, sin bloqueo nuevo. |
| Primera activación futura de exigencia | Corte del servidor al activar, o fecha explícita dentro de las próximas 24 horas. |
| Primera conversión pendiente de un lead antiguo | Exige asistencia y entrevista válida de la misma cita y ciclo. No hay excepción por antigüedad. |
| Primera conversión pendiente de un lead nuevo | Exige los mismos dos hechos. Un ciclo ausente tampoco crea una exención. |
| Hechos anteriores a la activación | Sirven si tienen contexto trazable y corresponden al ciclo vigente y a la misma cita. No se acreditan automáticamente registros ambiguos. |
| Reasignación | Conserva ciclo y hechos; no equivale a un lead nuevo. |
| Reapertura de descartado | Nuevo ciclo; exige sus propios hechos mientras rige el control. |
| Borrador sin evidencia vigente | Puede retomarse, corregirse o cancelarse; no puede confirmar una primera conversión exigible. |
| Inversión ya confirmada | El reintento devuelve el resultado confirmado con los permisos actuales. No crea otra inversión ni recalcula su prueba histórica. |
| Cliente existente | Inversión adicional, renovación y upgrade conservan sus reglas actuales. |

El censo de solo lectura del 19/10/2026 encontró 78 ambiguos y 1.886 incompletos entre 1.964 leads operativos. No son prueba de ausencia de atención. **No fabricar asistencia, fechar hacia atrás ni marcar entrevistas en lote.** Un registro histórico ambiguo queda pendiente de revisión; no se concede una excepción automática. La política de incluir las primeras conversiones antiguas está aprobada. La instalación y la activación concretas se acreditan por separado en el plan integral.

El nombre público `cohorte_desde` se conserva para compatibilidad con el frontend publicado: ahora significa cuándo comienza la exigencia global. Una fecha futura no exige antes de ese momento. La fecha se conserva al revertir o reactivar; no se usa para excluir leads antiguos.

## Observación, activación y reversión

La puerta administrativa es `crm.recorrido_configurar_fn(p_modo, p_motivo, p_revision, p_cohorte_desde default null)`. Solo Gerencia efectiva y activa puede llamarla. Usa la revisión actual del servidor; una revisión obsoleta se rechaza. El cambio y su motivo quedan auditados. No se cambia mediante PATCH de la tabla ni con una clave service_role.

1. **Observar:** instalar con modo inicial `observacion`, capacitar y contrastar casos reales. Medir rechazos de lectura, casos ambiguos, tiempo de respuesta y discrepancias entre citas e historial.
2. **Decidir:** registrar responsable comercial, fecha y autorización de activación del alcance aprobado. Confirmar rama/advisors y revisión del SQL productivo. La autorización de comenzar el plan no se registra como una activación ejecutada.
3. **Exigir:** una vez autorizado, usar la RPC con modo `exigir`, motivo y revisión actuales. Verificar que tanto nuevos como antiguos sin hechos quedan bloqueados, y que una cita válida permite continuar, con cuentas de sus roles y sin fabricar hechos productivos.
4. **Revertir el bloqueo:** ante una incidencia, la misma puerta permite `observacion` con motivo y revisión actuales. La fecha de primera activación permanece fija; reactivar vuelve a exigir a todas las primeras conversiones pendientes. `apagado` también oculta la guía.

No borrar las tablas de evidencia, retirar guards financieros existentes, deshacer inversiones ni hacer down-migrations para revertir el modo. Volver a un ZIP anterior cambia la interfaz, **no apaga por sí solo una exigencia ya activa en servidor**. Una visita confirmada se conserva aunque falle el refresco posterior.

## Capacitación y operación

La regla obligatoria es **asistió a la cita + entrevista realizada y cerrada con resultado, de esa misma cita y ciclo**. Contacto es orientación comercial, no un bloqueo adicional. La persona que atiende declara los hechos; el servidor verifica registro, vínculo y ciclo, no presencia física. Ver [CAPACITACION.md](CAPACITACION.md) y el [FigJam del plan](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=72-190).

No se necesita n8n. Las decisiones, el bloqueo y los recibos idempotentes se resuelven en transacciones del CRM. Una automatización futura de recordatorios puede consumir eventos, pero no debe ser la autoridad que permita convertir.
