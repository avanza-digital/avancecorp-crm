# Entrega, instalación y activación del recorrido

El Goal termina con código integrado y ZIP verificable. **No autoriza publicar el frontend, aplicar migraciones a producción ni activar exigencia.** El ZIP de la web no instala su backend. Esta guía define los requisitos para una publicación posterior; sus comandos productivos no se ejecutaron durante el Goal.

## Backend requerido

Aplicar, en este orden, los seis archivos versionados de `supabase/migrations/`:

1. `20261019001500_crm_recorrido_evaluacion.sql`
2. `20261019001501_crm_recorrido_evaluacion_hardening.sql`
3. `20261019001600_crm_recorrido_oficina.sql`
4. `20261019001601_crm_recorrido_oficina_hardening.sql`
5. `20261019001700_crm_recorrido_conversion.sql`
6. `20261019001701_crm_recorrido_conversion_hardening.sql`

Cada bloque contiene preflight/postflight y hardening. Las huellas de las funciones previas deben coincidir: si el backend cambió, detener la instalación, comparar el nuevo contrato y preparar una migración aditiva. No quitar preflights, forzar versiones ni editar migraciones ya comprometidas. No se modifica el esquema `public` y no se requiere desplegar una Edge nueva: el handler existente de acceso ya transmite el rechazo público del servidor.

Antes de instalar en producción, completar el circuito de `supabase/migrations/LEEME.md`: rama Supabase autorizada, aplicación, matriz RLS, advisors y revisión del merge de base. La validación de este Goal usó un banco Supabase local y copias desechables con Auth/PostgREST reales. La validación hosted y sus advisors se reportan separadamente como NOT RUN mientras no exista rama autorizada; no se sustituyen por un preflight offline. La consulta sobre organización/costo está pendiente y no se ha aceptado ningún gasto.

El frontend tolera una RPC de recorrido todavía ausente (`PGRST202`) y no muestra la guía en ese caso. Eso permite una instalación gradual, pero **no acredita que el bloqueo esté instalado**. Una lectura fallida distinta de RPC ausente se muestra como desconocida y nunca como requisitos cumplidos.

## Política de cohortes propuesta y ensayada

| Caso | Tratamiento |
|---|---|
| Instalación inicial | `observacion`; guía informativa, sin bloqueo nuevo. |
| Primera activación futura de exigencia | Corte del servidor al activar, o fecha explícita dentro de las próximas 24 horas. |
| Ciclo vigente anterior al corte | No queda bloqueado automáticamente. Se conserva la advertencia de datos incompletos/ambiguos. |
| Ciclo iniciado desde el corte | Exige asistencia y entrevista válida de una misma cita. Si falta el ciclo por un dato inconsistente, un lead creado desde el corte no recibe una exención. |
| Reasignación | Conserva ciclo y hechos; no equivale a un lead nuevo. |
| Reapertura de descartado | Nuevo ciclo; si empieza desde el corte, exige sus propios hechos. |
| Borrador sin evidencia vigente | Puede retomarse, corregirse o cancelarse; no puede confirmar una primera conversión exigible. |
| Inversión ya confirmada | El reintento devuelve el resultado confirmado con los permisos actuales. No crea otra inversión ni recalcula su prueba histórica. |
| Cliente existente | Inversión adicional, renovación y upgrade conservan sus reglas actuales. |

El censo inicial de solo lectura encontró 78 ambiguos y 1.887 incompletos entre 1.965 leads operativos. Son registros sin evidencia suficiente bajo el contrato nuevo; no demuestran ausencia de atención. **No fabricar asistencia, fechar hacia atrás ni marcar entrevistas en lote para resolverlos.** La decisión comercial sobre históricos y el visto bueno del corte deben quedar registrados antes de una activación productiva. Este documento propone el tratamiento; no registra una aprobación comercial que el usuario no ha dado.

## Observación, activación y reversión

La puerta administrativa es `crm.recorrido_configurar_fn(p_modo, p_motivo, p_revision, p_cohorte_desde default null)`. Solo Gerencia efectiva y activa puede llamarla. Usa la revisión actual del servidor; una revisión obsoleta se rechaza. El cambio y su motivo quedan auditados. No se cambia mediante PATCH de la tabla ni con una clave service_role.

1. **Observar:** instalar con modo inicial `observacion`, capacitar y contrastar casos reales. Medir rechazos de lectura, casos ambiguos, tiempo de respuesta y discrepancias entre citas e historial.
2. **Decidir:** registrar política histórica, responsable comercial, corte y autorización de activación. Confirmar rama/advisors y los gates de publicación vigentes. Esta decisión está pendiente.
3. **Exigir:** una vez autorizado, usar la RPC con modo `exigir`, motivo y revisión actuales. Verificar un caso dentro del corte y otro anterior con cuentas de sus roles, sin fabricar hechos en datos productivos.
4. **Revertir el bloqueo:** ante una incidencia, la misma puerta permite `observacion` con motivo y revisión actuales. El corte permanece fijo para que apagar y encender no exima por accidente a otra cohorte. `apagado` también oculta la guía.

No borrar las tablas de evidencia, retirar guards financieros existentes, deshacer inversiones ni hacer down-migrations para revertir el modo. Volver a un ZIP anterior cambia la interfaz, **no apaga por sí solo una exigencia ya activa en servidor**. Una visita confirmada se conserva aunque falle el refresco posterior.

## Capacitación y operación

La regla obligatoria es **asistió a la cita + entrevista realizada y cerrada con resultado, de esa misma cita y ciclo**. Contacto es orientación comercial, no un bloqueo adicional. La persona que atiende declara los hechos; el servidor verifica registro, vínculo y ciclo, no presencia física. Ver [CAPACITACION.md](CAPACITACION.md) y el [FigJam del plan](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=46-190).

No se necesita n8n. Las decisiones, el bloqueo y los recibos idempotentes se resuelven en transacciones del CRM. Una automatización futura de recordatorios puede consumir eventos, pero no debe ser la autoridad que permita convertir.
