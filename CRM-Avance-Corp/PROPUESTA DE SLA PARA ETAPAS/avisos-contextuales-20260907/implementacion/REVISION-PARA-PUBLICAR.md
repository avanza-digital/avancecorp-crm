# Avisos de seguimiento: revisión para publicar

Estado: **IMPLEMENTADO Y VERIFICADO LOCALMENTE; SQL PRODUCTIVO PENDIENTE DE CONFIRMACIÓN**.
Miguel aprobó el 07/09/2026 reemplazar la explicación permanente por avisos según el momento y el rol.

## Resultado

- Sin una acción requerida por el servidor, la ficha solo ofrece **Ver plazos**, cerrado inicialmente.
- Al llegar la hora de una actividad pendiente: **Revisa la actividad pendiente → Revisar actividad**.
- Seguimiento requerido: **Retoma el contacto y registra el resultado → Registrar gestión**.
- Supervisor/Gerencia con revisión requerida: **Revisa el caso y define el siguiente paso → Revisar caso**.
- Una actividad vencida no queda oculta por cobertura de seguimiento ni por otra prioridad. Las revisiones son independientes.
- Fechas breves de Lima; tope de ampliaciones disponible solo en el detalle de supervisión.
- Campana agrupada con conteos de toda la cartera autorizada, que abre Seguimiento en **Para atender ahora**. Paginación explícita conservada.
- La lectura del aviso no lo resuelve. Se retira cuando el servidor confirma que ya no corresponde. No se ofrece reconocer/posponer los nuevos avisos.
- La consulta puntual de la actividad usa la puerta RLS de Agenda y la incorpora al store antes del diálogo existente; funciona fuera del lote de 2.000 tareas y descarta respuestas de una sesión anterior.
- Se mantienen recordatorios de contactos y avisos gerenciales. El libro de reconocimientos no se modifica; sigue aplicándose al modo legado.
- Se mantiene retirado Seguimiento comercial de Hoy del Analista.

## Backend y SQL a aprobar

[SQL exacto](../../../supabase/migrations/20260907155813_crm_sla_avisos_contextuales.sql).

Amplía cuatro lectores del núcleo existente y agrega un resumen autorizado y su control de arquitectura. **No agrega tablas, no cambia políticas/plazos, no modifica tareas, gestiones, cartera ni reconocimientos.** La primera atención solo produce aviso al agotarse su plazo; las actividades futuras quedan en Agenda y pueden consultarse en Todas las acciones.

Las condiciones salen de `private.sla_operacion_leads`; `private.sla_operacion_autorizada` filtra los destinatarios. Ficha, cola y resumen no calculan fechas en el navegador. No hay un núcleo comercial nuevo ni un sistema paralelo de notificaciones.

Las huellas de las cuatro fuentes productivas se consultaron antes de preparar el SQL. La migración aborta si alguna cambió y ejecuta los controles de SLA, comandos, auditoría, analítica, vigencia de roles y piezas cerradas antes de confirmar.

## Validación

- 56 pruebas PostgreSQL 16: regresión del núcleo, fronteras exactas, actividad cubierta, revisión independiente, roles, lectura no autorizada, filtros y recorrido de más de 200 filas sin duplicados.
- PostgreSQL 17, copia local del esquema completo: migración, reversión y reaplicación; controles de arquitectura y permisos aprobados. Actores y oportunidad sintéticos.
- 2.952 pruebas de interfaz/datos; 10 pruebas de navegador, incluidos permisos al abrir ficha y actividad fuera del lote.
- TypeScript y compilación comprobados. Lint sin errores; conserva cuatro avisos previos en coverflow-carousel, ajenos al cambio.
- Capturas de escritorio/móvil inspeccionadas. Esto no sustituye una prueba de comprensión con usuarios reales.

[Analista móvil](analista-movil.png) · [Supervisor móvil](supervisor-movil.png).

Los avisos se consultan cada 60 segundos mientras se usa el CRM y al recuperar foco; no se implementa entrega con el CRM cerrado ni temporizador exacto al segundo.

## Publicación pendiente

La nota `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md` indica: «Cambios de base de datos: mostrar el SQL primero y esperar confirmación». Esta entrega deja preparado el SQL concreto para esa aprobación.

Tras confirmarlo: verificar otra vez las huellas remotas, aplicar la migración, verificar permisos/lecturas por rol, construir desde el commit idéntico de Main y avancecorp/main, publicar únicamente ese artefacto y comprobar la versión servida.

[Reversión SQL](../../../supabase/scripts/rollback-sla-avisos-contextuales.sql): publicar primero el frontend anterior compatible y después restaurar los lectores. El script comprueba las huellas nuevas antes de revertir. Conserva hechos y configuración.
