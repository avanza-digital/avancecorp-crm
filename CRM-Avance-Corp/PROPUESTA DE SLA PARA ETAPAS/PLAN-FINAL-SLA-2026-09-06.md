# Plan final implementable — seguimiento, compromisos y SLA de etapas

Versión: **SLA-R2 · 2026-09-06 · corregida tras auditoría**. Sustituye SLA-R1 y `spec-prorroga-sla-etapas.md` como guía de desarrollo. La copia exacta de R1, la evidencia y los hallazgos están en `auditoria-r2/`. Las fases se identifican SLA-0 a SLA-6 para evitar colisiones con el backlog P-050–P-054.

Estado: **plan corregido; núcleo N1 implementado en código y probado localmente (44/44); integración y activación pendientes**. Ver [entrega N1](NUCLEO-IMPLEMENTADO-N1.md). La auditoría incluyó código, funciones y núcleos leídos en producción, contraejemplos de fórmulas y pruebas reducidas en PostgreSQL desechable: 27 comprobaciones aprobadas. Estas 27 comprobaciones pertenecen a la auditoría del plan; las 44 pruebas nuevas de N1 están documentadas por separado y tampoco certifican la integración completa. No se ejecutaron mutaciones en la base del CRM ni se publicó código. El usuario aprobó posteriormente los plazos de seguimiento recurrente 1/3/3/5 días corridos para Nuevo/Contactado/Reunión agendada/Propuesta enviada. También aprobó las cinco gestiones que reinician seguimiento, incluidos los intentos sin respuesta (apartado 4). Además aprobó la pausa del aviso de seguimiento por una tarea comercial pendiente con fecha, hasta su vencimiento más margen y dentro del tope, conservando el atraso de agenda desde la hora de vencimiento. Aprobó los márgenes corridos posteriores al vencimiento: Nuevo 4 horas, Contactado 1 día, Reunión agendada 2 días y Propuesta enviada 1 día, sujetos al tope. Aprobó también los plazos base/topes por entrada a etapa: Nuevo 1/3 días, Contactado 8/16, Reunión agendada 15/18 y Propuesta enviada 20/27, corridos. Aprobó las prórrogas automáticas por llamada atendida, WhatsApp recibido o reunión realizada en las últimas 24 horas antes del vencimiento del plazo base o de una prórroga vigente, manteniendo la misma etapa: Contactado +4 días hasta 2 veces; Propuesta enviada +7 días una vez; Nuevo/Reunión sin prórrogas, siempre respetando topes. Aprobó la revisión comercial para supervisor/Gerencia ante cualquiera de estos hechos: vencimiento operativo con ampliaciones válidas, tercera reprogramación del compromiso (que deja de pausar seguimiento) o tercer ingreso a la misma etapa en el mismo ciclo; ellos deciden la acción. Aprobó aplicar seguimiento a los leads existentes desde la activación, conservando historial y plazo original; los ya vencidos sin cobertura aparecen pendientes desde ese primer día, y las prórrogas corresponden a nuevas entradas en etapas bajo la nueva política. El usuario pidió contrastar primero contra la cartera existente y prefiere activación conjunta si la evidencia es correcta, sin exigir una jornada en observación; este contraste no activa el módulo. La aplicación a producción requiere el SQL exacto, sus pruebas y su reversión revisables, conforme a la memoria del proyecto.

**1. Resultado que debe obtener el negocio**

El analista identifica a quién atender y qué compromiso cumplir. Supervisor y Gerencia distinguen la falta de seguimiento del estancamiento de una oportunidad. La cobertura y los ajustes no modifican el snapshot original. Los avances y retrocesos reales del CRM sí pueden cerrar un episodio y abrir otro; se conservan ambos en la historia. Esta versión no introduce un techo global del lead ni impide reinicios legítimos por cambio de episodio.

| Señal | Pregunta | Destinatario y efecto |
|---|---|---|
| Seguimiento pendiente | ¿Pasó demasiado tiempo sin gestión durante la responsabilidad actual? | Analista: acción concreta, salvo cobertura válida de agenda. |
| Próximo compromiso / compromiso vencido | ¿Qué tarea hay que cumplir y cuándo? | Analista: agenda, conservando las tareas atrasadas. |
| Etapa fuera de plazo | ¿El episodio superó su duración original? | Supervisor/Gerencia: salud del pipeline; visible aunque haya prórroga o compromiso. |
| Revisión comercial requerida | ¿Se agotó el plazo operativo adicional permitido? | Supervisor: decidir con el analista. Sin descarte, liberación o reasignación automática. |

La primera gestión y el primer contacto conservan sus SLA existentes. Una pausa de etapa o de seguimiento no modifica esos hitos.

Las señales accionables conservan los filtros actuales de lead activo/abierto y el veto canónico de la persona («No insistir»), además del ámbito. Una restricción de contacto no puede transformarse en una sugerencia de llamar por haber vencido un plazo. Los datos históricos pueden seguir consultándose donde el rol tenga permiso, con estado operativo no accionable. Se reutiliza el resolver vigente del veto; no se reconstruye solo con un booleano local potencialmente desactualizado.

**2. Punto de partida comprobado**

Consulta de solo lectura a `dctqcbznekcyxhjujuci`, **2026-09-06 17:34:44, hora de Lima**:

- Política vigente y última publicada: **v5**, vigente desde 2026-08-27.
- Primera gestión: **120 minutos**. Primer contacto: **1440 minutos**.
- Etapas: Nuevo 1 día; Contactado 8 días; Reunión agendada 15 días; Propuesta enviada 20 días.
- **827 etapas abiertas; 492 vencidas por su límite original**. Son conteos de filas de SLA; no una nueva medición de alertas visibles por rol ni un objetivo de aceptación.
- Existe el índice UNIQUE que impide más de una etapa abierta por lead.
- No existen `crm.lead_sla_etapa_ajustes` ni la tabla anexa de reglas operativas propuesta aquí.
- El branch `irzyttvonpboyaxyuxvc` no aparece en la lista actual. El branch no predeterminado listado es `banco-f7`, con estado de migraciones `MIGRATIONS_FAILED`; no se reutiliza como banco de pruebas sin diagnóstico. El estado de migraciones reportado por la API no implica por sí solo que la aplicación productiva esté caída.

Los contratos y recorridos de código se contrastaron con el repositorio local. SLA-0 debe comparar sus definiciones con las funciones vivas antes de generar la migración final. Las 277 etapas del documento original ya no son la línea base actual.

**3. Reglas comerciales cerradas para esta primera versión**

| Etapa | Plazo original de la nueva política | Seguimiento sin gestión | Prórroga por conversación | Cantidad máxima | Techo desde inicio de etapa | Margen de compromiso |
|---|---:|---:|---:|---:|---:|---:|
| Nuevo | 1 día | 1 día | Ninguna | 0 | 3 días | 4 horas |
| Contactado | 8 días | 3 días | 4 días | 2 | 16 días | 1 día |
| Reunión agendada | 15 días | 3 días | Ninguna | 0 | 18 días | 2 días |
| Propuesta enviada | 20 días | 5 días | 7 días | 1 | 27 días | 1 día |

Reloj corrido; presentación en `America/Lima`. Todos los parámetros se almacenan en minutos enteros. Los plazos de seguimiento 1/3/3/5 días fueron aprobados por el usuario y se apoyan en los umbrales operativos actuales de cola; las duraciones y techos conservan la propuesta base. Son valores iniciales configurables, no una optimización estadística demostrada. El reloj laboral y los feriados quedan fuera de SLA-R2.

La nueva política será **la siguiente versión disponible**, previsiblemente v6; ningún script debe exigir que su número sea siempre 6. Primera gestión y primer contacto se copian de la configuración vigente comprobada al publicar, sin cambiarlos incidentalmente.

**3.1 Seguimiento: duración y fecha límite separadas**

- Gestión válida: `llamada_realizada`, `llamada_no_contestada`, `whatsapp_enviado`, `whatsapp_recibido`, `reunion_realizada`. **Lista aprobada por el usuario** para reiniciar seguimiento, incluidos los intentos sin respuesta.
- Notas, reasignaciones y cambios de etapa no reinician seguimiento.
- Se toma la última gestión válida del lead ocurrida dentro del ciclo y de la asignación actualmente abiertos. Se incluyen las ayudas de un supervisor autorizado y se devuelve el autor real; este indicador mide atención al lead, no productividad individual ni atribución del trabajo al analista propietario.
- Referencia inicial: la mayor entre inicio del ciclo e inicio de la asignación abierta. Sin gestiones posteriores, se utiliza esa referencia. Sin asignación a analista, se trata como trabajo de reparto/bandeja y se conserva la ruta actual de supervisión; no se inventa un analista incumplido.
- Una actividad con fecha posterior al instante de evaluación o inválida no participa. Se devuelve `ultima_gestion_en` nullable, autor y referencia; nunca se inventa una conversación para cubrir un dato ausente.
- El umbral proviene de la regla operativa vigente para la etapa actual. Un cambio de etapa no inventa una gestión nueva. Una reasignación abre la referencia de la nueva responsabilidad y conserva la historia previa para consulta.

Fórmula, con `ahora` tomado una sola vez en servidor por evaluación:

```text
referencia_gestion = max(inicio_ciclo, inicio_asignacion, ultima_gestion_valida)
limite_seguimiento = max(referencia_gestion + seguimiento_minutos, primera_activacion_en)
seguimiento_vencido = ahora >= limite_seguimiento
mostrar_seguimiento_pendiente = seguimiento_vencido AND (cobertura_compromiso IS DISTINCT FROM true)
```

`primera_activacion_en` se fija una sola vez y no se reinicia al cambiar política, revertir el modo o reactivar el módulo. Permite aplicar las reglas operativas al stock actual desde la activación sin fabricar incumplimientos de fechas anteriores. No concede un período adicional completo de gracia: los seguimientos que ya requieren atención aparecen al activar. Las fórmulas se evalúan solo con sus datos requeridos; si falta la referencia o la regla, el seguimiento es no evaluable. Una cobertura desconocida no suspende un seguimiento vencido que sí pudo comprobarse.

**3.2 Compromiso: elegir el primero pendiente, incluyendo el atrasado**

Una tarea puede cubrir seguimiento y ampliar el plazo operativo de etapa cuando cumple todos estos criterios:

- Es de ese lead, del ciclo actual, activa y pendiente; tipo `llamada`, `whatsapp` o `reunion`. Una tarea administrativa genérica no concede pausa.
- Su tenencia corresponde a la tenencia actual del lead. Las tareas comerciales pendientes se heredan al nuevo responsable dentro del mismo ciclo, como ya hace el CRM. Se muestran el responsable actual y el autor real si está disponible; no se deduce que fue «heredada» únicamente porque autor y responsable sean distintos.
- Tiene fecha válida. Las fechas inválidas no conceden cobertura y deben producir un estado de dato incompleto, sin pintar «al día».
- Primero se inspeccionan todas las tareas comerciales activas y pendientes del lead. Si alguna tiene contexto de ciclo no demostrable, tenencia incoherente o fecha inválida, la cobertura queda bloqueada por `datos_compromiso_incompletos`; no se descarta esa fila para usar otra futura. Una tarea cuyo contexto demuestra que pertenece a un ciclo anterior no cubre y se reporta como inconsistencia de cierre, conservándola visible en agenda. Resueltas esas condiciones, se ordenan las del ciclo actual por `vence_en ASC, id ASC` y se elige una. No se filtran previamente vencidas ni reprogramaciones >= 3: ambas deben poder bloquear la cobertura de tareas posteriores.
- Las tareas siguen siendo válidas al avanzar de etapa dentro del mismo ciclo. La reunión que ocasiona entrar a «Reunión agendada» puede justificar la cobertura de esa etapa.
- La tercera reprogramación de la tarea (`reprogramaciones >= 3`) retira su capacidad de conceder cobertura y genera motivo de revisión para el supervisor. En reuniones, la RPC cierra una fila como `reprogramada`, crea otra y arrastra el contador: ambas conservan contexto del mismo ciclo. No basta con invalidar un UPDATE sobre la fila vieja.

```text
compromiso_estructural_valido = pausa_habilitada
                               AND datos_compromiso_completos
                               AND existe tarea_elegida
                               AND tarea_elegida.reprogramaciones < 3
compromiso_hasta = min(tarea_elegida.vence_en + margen, techo_operativo_etapa)
                  si compromiso_estructural_valido; null en otro caso
cobertura_compromiso = null si faltan datos requeridos
                      compromiso_hasta IS NOT NULL AND ahora < compromiso_hasta en otro caso
```

Al llegar a la hora de la tarea, el margen continúa. Al llegar exactamente a `compromiso_hasta`, termina la cobertura, pero esa fecha no se borra del cálculo mientras la tarea siga pendiente y estructuralmente válida. Una tarea cuyo margen ya terminó permanece como primera pendiente y evita que otra futura la oculte. Se debe completar, cancelar por la puerta actual o reprogramar; se conserva el motivo obligatorio existente para reuniones, sin inventar ese campo obligatorio para otras tareas.

Al completar, cancelar o desactivar, se vuelve a elegir la primera pendiente. Reprogramar una reunión sustituye la fila y puede mantener cobertura si el contador lo permite. Cancelar la última reunión puede provocar el retroceso de etapa que ya existe en el CRM: cerrar un episodio y abrir otro sí cambia el reloj del episodio activo. Esto se registra como transición real, no como prórroga. El techo protege cada episodio, no toda la vida del lead. El historial debe mostrar esos movimientos para supervisión. La interfaz confirma el resultado del servidor y actualiza agenda, cola, etapa y ficha juntas.

La agenda conserva su criterio actual de atraso por hora. Que exista margen de SLA no elimina una tarea vencida de agenda. No se utiliza el criterio antiguo «cualquier plan cuyo día de Lima no pasó» como sustituto de esta cobertura; las pantallas que mantienen ese criterio por otros motivos siguen distinguiéndolo expresamente.

**3.3 Prórroga: conversación cerca del vencimiento y presupuesto finito**

Solo `llamada_realizada`, `whatsapp_recibido` y `reunion_realizada`. En esta entrega solo gestiones humanas autenticadas por las puertas actuales autorizadas del CRM. Los writers internos sin identidad humana conservan su comportamiento de registro y avance, pero no conceden prórrogas; una futura integración necesita incorporarse explícitamente a ese contrato.

Se concede automáticamente una prórroga únicamente si:

1. El episodio abierto pertenece a una política que incluye las nuevas reglas y su etapa es Contactado o Propuesta enviada.
2. Era el mismo episodio antes y después del avance automático provocado por esa actividad.
3. Queda presupuesto y la actividad no produjo ya un ajuste en ese episodio.
4. La conversación se registró durante las **últimas 24 horas antes del límite prorrogado**, sin incluir el instante del vencimiento: `limite_prorrogado - 1440 min <= evento_en < limite_prorrogado`.
5. La extensión aumenta realmente el límite sin superar el techo de ese episodio.

El modo debe ser activo al admitir el ajuste bajo el lock de control y `evento_en >= primera_activacion_en`. Un evento registrado antes de la primera activación no gana una prórroga porque su transacción termine después. Tras una reversión, la garantía de cero ajustes nuevos se mantiene mientras no se vuelva a activar expresamente.

Las conversaciones tempranas no se acumulan como créditos. Una conversación después del vencimiento no borra el incumplimiento ni concede prórroga retroactiva. Registrar una actividad válida nunca debe fallar solo porque no queda presupuesto: se guarda la gestión y se omite el ajuste con motivo comprobable.

```text
limite_prorrogado = limite_original + sum(ajustes.minutos_reales)
limite_nuevo = min(limite_prorrogado + prorroga_minutos, techo_del_episodio)
minutos_reales = (limite_nuevo - limite_prorrogado) en minutos enteros
```

Dos conversaciones simultáneas no consumen la misma posición. Después de conceder 4 días, otra conversación inmediata queda fuera de la ventana de 24 horas y no consume otra prórroga. La gestión que abre Contactado desde Nuevo concede **cero** ajustes.

**3.4 Antigüedad histórica y plazo operativo de revisión**

```text
etapa_fuera_plazo = ahora >= e.limite_en
limite_operativo_etapa = min(max(limite_prorrogado, coalesce(compromiso_hasta, limite_prorrogado)), techo_operativo_etapa)
revision_por_limite = ahora >= limite_operativo_etapa
revision_comercial_requerida = revision_por_limite
                              OR tarea_elegida.reprogramaciones >= 3
                              OR episodios_de_esta_etapa_en_ciclo >= 3
```

La fórmula del límite operativo requiere conocer si existe compromiso válido: `coalesce` solo sustituye una ausencia comprobada, no un dato desconocido. Si falta ese dato, límite operativo y revisión por límite son null; si ya se alcanzó el techo conocido, la revisión por límite sí es true porque ninguna cobertura podría ampliarlo. La ausencia comprobada de tarea aporta false al motivo de reprogramación; la ausencia de datos requeridos aporta null, según el contrato. Un motivo comprobado true basta para requerir revisión. No se confunde una fecha histórica conocida con un plazo operativo no evaluable.

La validez estructural del compromiso y su vigencia temporal son datos diferentes. Al vencer el margen, `cobertura_compromiso` pasa a false, pero el límite de revisión conserva esa frontera; no vuelve al límite base y fabrica días de atraso. Al resolver/cancelar una tarea o cambiar parámetros operativos sí puede cambiar el límite derivado por un evento real: la UI dice «Revisión requerida ahora» y su motivo; no atribuye retrospectivamente incumplimientos a partir de esa nueva foto. Prórroga y compromiso no se suman: se usa el mayor límite y se recorta al techo. El seguimiento conserva su cálculo propio.

El pipeline conserva el semáforo original: en plazo antes del límite base; atención desde ese límite; crítico desde el doble de su duración. El indicador adicional «Revisión requerida» permite actuar antes o después de ese segundo escalón según el plazo operativo; ambos valores deben llevar rótulos distintos. Al agotarse el techo, el supervisor recibe la oportunidad para decidir; no se cambia de etapa ni de dueño automáticamente.

Para que un recorrido repetido de agendar/cancelar no se esconda detrás de episodios nuevos, devolver `episodios_de_esta_etapa_en_ciclo` desde el ledger. Desde el tercer ingreso a la misma etapa en un ciclo se añade el motivo `reingreso_etapa` a la revisión de supervisión, aunque el límite del episodio recién abierto no haya vencido. Es una revisión de la oportunidad, no una imputación al analista recién asignado. No se impide una transición válida ni se cambia la métrica histórica. La revisión agregada es: límite operativo agotado OR tercera reprogramación de la tarea elegida OR tercer ingreso a esa etapa en el ciclo; se devuelven los motivos por separado.

**3.5 Cartera actual, políticas nuevas y pasado**

- Seguimiento y cobertura de agenda se aplican a **toda la cartera abierta desde la primera activación**, usando la política operativa vigente. Cambios posteriores de esos parámetros rigen para la operación desde su vigencia y no alteran reportes históricos.
- Una etapa sin reglas ampliadas conserva `politica_id`, inicio y límite base y no recibe prórrogas. Para su cobertura prospectiva, el techo es `limite_base_historico + tope_extra_minutos de politica_adopcion_id`. Esa política se fija una sola vez en el control al activar por primera vez, con FK e inmutabilidad. Publicar otra política no mueve tampoco el techo de los episodios históricos.
- Una etapa nacida con reglas ampliadas obtiene parámetros de prórroga y techo de **su política de entrada**: `techo = limite_base + tope_extra_minutos sellado por esa versión`. Publicar otra política no amplía su presupuesto ni su techo. La configuración actual de seguimiento/margen puede variar prospectivamente, pero la cobertura nunca cruza ese techo sellado.
- Los extras iniciales son Nuevo 2 días, Contactado 8, Reunión 3 y Propuesta 7. Se almacenan como duración adicional para que un publicador antiguo que cambie el plazo base conserve una relación coherente.
- Una etapa histórica que ya superó su techo no se maquilla como atendida: queda para revisión de supervisión. Su agenda permanece utilizable.
- Los indicadores históricos de cumplimiento SLA continúan calculándose con los snapshots originales. No se publican métricas históricas de «pausas cumplidas» a partir del estado actual de tareas. Los nuevos conteos de seguimiento/revisión se rotulan como situación actual.

**4. Diseño técnico que implementa las reglas**

**4.0 Núcleo rector del backend y reutilización**

Instrucción expresa del usuario durante la auditoría: usar los núcleos existentes para obtener información y organizar cualquier cálculo nuevo bajo un núcleo de backend, sin calculadoras independientes por función o pantalla. **Este alcance requiere un núcleo operativo de SLA nuevo dentro del dominio SLA existente.** `private.metricas_sla_global_core` responde una pregunta agregada de primera atención; `crm.estado_sla_leads_fn` expone snapshots. Ninguno calcula todavía seguimiento continuo, compromiso dominante y prórrogas. No se reemplazan sus significados por uno distinto.

El diseño normativo está en `auditoria-r2/ARQUITECTURA-NUCLEO-SLA.md`: fuentes canónicas → núcleo privado de hechos/reglas → ventana autorizada común → RPC de presentación. La misma familia gobierna la decisión de prórroga que aplica el writer transaccional. Las funciones auxiliares pertenecen a ese núcleo, con contrato, dependencias y consumidores declarados. Las pantallas reciben hechos y decisiones; solo formatean, muestran e invocan acciones.

Reutilizar políticas y snapshots SLA, autoridad/ámbito y escritores de agenda actuales. Citas, conversión y capital conservan sus núcleos para las preguntas que ya gobiernan; ninguna nueva salida de SLA recalcula esas métricas. La semántica de cumplimiento histórico permanece intacta. SLA-0 debe inventariar los consumidores y las declaraciones/huellas de gobernanza afectadas; SLA-4 verifica paridad, dependencias y controles arquitectónicos, además de resultados.

**4.1 Modelo aditivo: cinco tablas nuevas, sin backfill sobre políticas publicadas**

| Objeto | Contenido y garantías |
|---|---|
| `crm.sla_politica_etapas_operacion` | PK `(politica_id, etapa)` y FK compuesta a `sla_politica_etapas(politica_id, etapa)`. Campos: `seguimiento_minutos`, `prorroga_minutos`, `prorroga_max`, `tope_extra_minutos`, `pausa_habilitada`, `pausa_margen_minutos`. Filas inmutables, creadas junto con una política nueva. La ausencia de fila representa una política histórica sin ampliación. |
| `crm.lead_sla_etapa_ajustes` | `id`, `etapa_sla_id`, `origen_actividad_id` obligatorio, `secuencia`, `minutos_reales`, `limite_antes`, `limite_despues`, `creado_por`, `creado_en`. FKs restrictivas; UNIQUE `(etapa_sla_id, origen_actividad_id)` y `(etapa_sla_id, secuencia)`. INSERT-only. Lead y política se obtienen del episodio; no se duplican en la fila. |
| `crm.tarea_sla_contexto` | PK/FK `tarea_id`, `lead_id`, `ciclo_n`, `fuente` (`evento` o `reconstruido`), `registrado_en`; FK `(lead_id,ciclo_n)` al ciclo SLA. Identifica el ciclo causal de la tarea sin modificar su contrato público. Inmutable. |
| `crm.sla_operacion_control` | Fila única: `modo` (`legado`, `observacion`, `activo`), `revision`, `primera_activacion_en`, `politica_adopcion_id` con FK, autor y fecha del cambio. Instante y política de adopción se fijan juntos una sola vez. Cambios de modo auditados mediante la única RPC de Gerencia con revisión esperada. |
| `crm.solicitudes_gestion_lead` | PK `(actor_id, operacion_id)`, tipo de operación, sujeto, payload normalizado, respuesta y fecha. Reserva y finalización ocurren en la misma transacción de negocio; nada puede quedar confirmado sin respuesta. Una fila finalizada es inmutable. Permite confirmar reintentos de actividad/cierre/reprogramación sin volver a ejecutar sus efectos. Sin acceso directo desde el cliente. |

Constraints de reglas: todos NOT NULL y enteros; seguimiento 1–43200; prórroga cero o 1441–43200 (mayor que la ventana fija de 1440); cantidad 0–5; extra 0–43200; margen 0–10080; cantidad cero si y solo si duración cero; prórroga habilitada exige extra positivo; sin prórroga en Nuevo/Reunión; pausa deshabilitada implica margen cero. No se exige `cantidad * prorroga <= extra`: el techo puede recortar la última extensión, como requiere el caso de techo parcial. Para ajustes: secuencia positiva, minutos positivos y `limite_despues = limite_antes + minutos_reales * interval '1 minute'`. El writer impone cantidad, ganancia restante, autor y correspondencia actividad–episodio. Ningún presupuesto configurable permite sobrepasar el techo.

La tabla anexa evita el UPDATE bloqueado de políticas antiguas y el default cero incompatible con su máximo. El publicador actual sigue pudiendo funcionar antes de activar la ampliación. La FK aprovecha la unicidad existente por política/etapa, según las reglas de [constraints de PostgreSQL](https://www.postgresql.org/docs/current/ddl-constraints.html).

Todas las tablas nuevas: RLS habilitada, sin policies de acceso humano directo, ACL explícitas; lectura y escritura solo mediante las funciones autorizadas. Las funciones internas no conceden EXECUTE a PUBLIC, anon, authenticated ni service_role. Las RPC públicas conceden solo a authenticated y revalidan usuario activo, rol y ámbito. Directorio conserva lectura, nunca configuración/escritura. El control no puede ampliar permisos sobre leads.

Índices: los UNIQUE de ajustes ya cubren búsquedas por episodio; añadir índice de actividad por FK. Evaluar índice de tareas `(lead_id, vence_en, id)` parcial `activo AND estado='pendiente'` y el de actividades por lead/fecha y conjunto de gestión, reutilizando los existentes cuando cubran la consulta. No crear índices duplicados ni justificar desnormalización por los 827 registros actuales.

**4.2 Contexto de tareas y adopción del stock**

Las tareas nuevas de lead toman su contexto del servidor. La auditoría comprobó que el BEFORE INSERT actual ya obtiene `FOR SHARE` y otro trigger posterior lo eleva a `FOR UPDATE`: dos altas simultáneas pueden bloquearse entre sí. SLA-1 corrige el primer lock del lead a `FOR UPDATE`, desde la primera adquisición y solo en la rama de tareas de lead; el trigger posterior reutiliza el lock. No se agrega otro lock tardío. El AFTER INSERT registra contexto del ciclo bloqueado, incluyendo writers internos. No acepta ciclo ni tenencia elegidos por el cliente. Las ramas de tareas de perfil/postventa conservan su comportamiento.

También se corrige la rama lead de `crm.cerrar_tarea`: actualmente bloquea tarea y luego lead, mientras reasignación y sincronización hacen lead y luego tareas. Leer primero el lead de la tarea sin bloquearla, obtener lead `FOR UPDATE`, volver a leer/bloquear tarea y revalidar sujeto, pendiente, actor y ámbito después de cualquier espera. `cerrar_reunion` y `reprogramar_reunion` ya empiezan por lead, pero deben usar el mismo modo fuerte si después la inserción de una actividad requerirá `FOR UPDATE`. El cierre puede invocarse a través de puertas v1: la corrección compartida debe proteger también ese camino. Estos son cambios obligatorios de SLA-1, no una investigación indefinida para después.

El stock pendiente se incorpora por lotes con locks de leads en orden estable, relectura después del lock y correspondencia de tenencia. Solo se crea contexto reconstruido si el lead tiene ciclo abierto válido y la fecha de creación de la tarea pertenece a ese ciclo. Las tareas cuyo ciclo no pueda demostrarse continúan en agenda y se listan como «contexto por revisar»; no conceden cobertura. No se alteran sus fechas, estados ni autores para hacerlas pasar por válidas.

La instalación de triggers/guards y el poblamiento se separan. Primero instalar el modelo y la captura de tareas nuevas, con ACL cerradas y modo legado, en una migración breve. Después reconstruir el stock mediante un helper privado transitorio, ejecutable solo por el propietario de migración, en lotes de hasta 200 leads con commits independientes. Cada lote bloquea leads por ID, relee tareas/ciclo y hace INSERT idempotente de contextos coherentes. El guard permite expresamente esa ruta privada además de la captura por trigger; no hay UPDATE de contextos ni guard desactivado. La reserva de locks de un lote no persiste hasta terminar todo el stock. Al terminar, retirar el helper en una migración de cierre y guardar pendientes ambiguos. Si un lote supera `lock_timeout=5s` o `statement_timeout=30s`, revierte ese lote y conserva modo legado; no se eleva el timeout sin revisar la causa. No se cancela ninguna tarea como parte de esta reconstrucción.

Cerrar/reabrir el lead deja fuera los contextos de ciclos anteriores; se mantiene la cancelación de tareas del cierre actual. Reasignar dentro del mismo ciclo conserva el contexto y la sincronización de tenencia. Las pruebas incluyen tareas creadas en la misma transacción que el lead, reuniones que abren etapa, reaperturas y writers internos. Si la auditoría encuentra una puerta que no preserva ese orden, se incorpora al alcance de SLA-1 antes de activar, sin relajar permisos.

**4.3 Conceder la prórroga sin comparar relojes diferentes**

Se amplía el recorrido de `private.trg_actividades_avance_etapa`, conservando el trigger `trg_zz_actividades_avance_etapa` y la semántica actual de avance. No se añade un trigger `zzz` con una comparación de timestamps.

Para una actividad elegible autenticada: obtener/reutilizar el lock del lead, capturar el ID del episodio abierto, ejecutar el avance automático existente y volver a consultar el episodio. Solo llamar a `private.sla_conceder_prorroga` si ambos IDs coinciden. El helper toma `new.creado_en` sellado por el servidor como instante del evento, revalida episodio/política, ventana, unicidad y presupuesto, e inserta la ganancia real. La primera conversación en Nuevo compara dos IDs distintos y no concede ajuste.

Conservar el guard de reentrada del avance y restaurar cualquier setting transaccional al valor previo. El guard de ajustes comprueba valor explícito, profundidad de trigger, inmutabilidad y coherencia; no utiliza `current_setting(...,'on')` como si fuera un permiso. Las funciones nuevas se crean y sus privilegios se restringen en la misma transacción, conforme a [PostgreSQL, funciones SECURITY DEFINER](https://www.postgresql.org/docs/current/sql-createfunction.html).

El lock de la fila del lead serializa los writers que conceden prórrogas. Los internos sin usuario no conceden ajustes en SLA-R2. Orden obligatorio: reserva idempotente si la puerta es v2 → locks de identidad ya requeridos por esa operación, sin inventar otros → todos los leads por ID, con modo fuerte desde el inicio → tareas por ID → control de modo al conceder el ajuste. Después de tomar control no se solicita otro lead ni otra identidad. El helper de prórroga no toma locks de tareas. No se cambia el sello `clock_timestamp()` de gestión serializada.

La auditoría comprobó que el frontend actual no envía el UUID de su actividad optimista y anuncia `ok` antes de la persistencia; los cierres tampoco confirman un reintento sobre una tarea ya cerrada. SLA-2 incorpora estas puertas nuevas: `registrar_actividad_v2(p_operacion_id uuid, p_lead_id uuid, p_tipo text, p_detalle text default null)`; `cerrar_tarea_v2`, `cerrar_reunion_v2` y `reprogramar_reunion_v2`, cada una con `p_operacion_id uuid` obligatorio añadido a los argumentos exactos de su puerta actual, conservando sus nombres y tipos restantes. Las dos puertas de cierre se limitan a tareas de lead en este alcance; postventa conserva las actuales. El DTO de actividad no acepta autor ni fecha: se derivan del servidor; admite los cinco tipos de gestión y nota, nunca tipos de sistema. El ID de la actividad manual es el ID estable de la operación.

Protocolo: autenticar y comprobar acceso al sujeto → reservar `(actor_id, operacion_id)` con payload normalizado y clase de operación → si existe, verificar igualdad de todo el payload y revalidar acceso vigente; devolver la misma respuesta sin exigir que la tarea siga pendiente → si es nueva, tomar locks y revalidar, ejecutar el writer compartido y guardar respuesta antes del commit. Una constraint trigger diferida impide confirmar reservas sin respuesta. Un error revierte también la reserva. Misma llave con operación, sujeto o payload distintos es conflicto y no devuelve datos previos. Si el actor perdió acceso, se deniega la confirmación sin revelar el resultado y no se reintenta como una operación nueva. La reserva precede a los locks de dominio para evitar que un reintento bloquee al writer que espera.

El frontend crea la llave y el payload una sola vez, los conserva por usuario durante un resultado incierto, y muestra «Guardando»/«Confirmación pendiente» hasta obtener el recibo. Para reprogramar, conserva también `p_nueva_id`; para cerrar con siguiente tarea, se repite el mismo `p_siguiente` y se recupera el `siguiente_id` ya generado. Guardar esta intención en el mecanismo local de persistencia de sesión, particionado por usuario y limpiado al confirmar o cerrar sesión; no crear una nueva llave automáticamente tras timeout. Todos los accesos de gestión de lead, incluidos atajos, migran a esta confirmación. El contrato de reintento exacto corresponde a estas puertas v2; los bundles antiguos mantienen su comportamiento previo y no adquieren una garantía que su payload no permite ofrecer.

Una ausencia de presupuesto produce no-op del ajuste, no rollback de la actividad. Una inconsistencia real de integridad sigue siendo un error visible; no se oculta con `ON CONFLICT DO NOTHING` genérico. La unicidad del ajuste se reserva para el mismo episodio y actividad, no para deduplicar conversaciones distintas por parecido de texto.

**4.4 Un cálculo operativo y contratos nuevos compatibles**

`private.sla_operacion_leads(p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamptz)` es el núcleo operativo: concentra seguimiento, tarea elegida, límites, motivos y acción dominante para atención y para supervisión. Recibe ámbito ya resuelto; no identifica al usuario ni concede permisos. `private.sla_operacion_autorizada` es su ventana común: resuelve identidad/rol/ámbito con los helpers existentes, fija el instante y llama al núcleo con entradas explícitas; selecciona la perspectiva permitida. Los límites públicos y las formas JSON pertenecen a los adaptadores RPC. El instante no se recibe desde el navegador ni se agregan ajustes de episodios cerrados al episodio vigente. El contrato interno y la reutilización del estado base v1 se detallan en el anexo de arquitectura.

El contrato normativo de argumentos, campos, nulls, estados y paginación está en `auditoria-r2/CONTRATO-V2.md`. El [contraste real terminado](CONTRASTE-CARTERA-2026-09-06.md) añade un [ajuste obligatorio de filtros y paginación de cola](AJUSTE-LECTURA-COLA-TRAS-CONTRASTE.md): N1 no está publicado y se debe cerrar esta ampliación antes de su primer release. Ese contrato y esta versión del plan se desarrollan juntos; no basta con añadir nombres de RPC sin definir cómo los consumen los validadores estrictos.

Contratos externos:

- `crm.estado_sla_leads_v2_fn(p_lead_ids uuid[])`: JSON versionado, máximo 200 elementos de entrada por llamada; normaliza IDs repetidos y devuelve solo filas visibles. Incluye `version=2`, modo, `calculado_en`, versión operativa, identidad del episodio/ciclo/asignación, estado base, seguimiento, compromiso elegido, prórrogas, techo, límites y motivos. Un lead sin foto válida devuelve estado explícito no evaluable; nunca «al día» por ausencia de datos. El frontend pide IDs de páginas visibles y fragmenta lotes mayores.
- `crm.cola_accion_v2_fn`: N1 implementa solo `p_limite integer default 100`; antes de publicar, ampliar la lectura con filtro por señal y cursor según el ajuste del contraste. Usa el mismo cálculo para todo el ámbito y aplica filtro/cursor/límite **después** de clasificar y contar. El filtro de revisión selecciona la señal, aunque otra acción sea dominante. Devuelve versión, instante, totales del ámbito, total filtrado, página y siguiente cursor. No deriva contadores globales de una página ni deja inaccesibles los elementos posteriores al máximo 200. Las firmas, grants, validadores, gate y reversa deben evolucionar juntos.
- `crm.configuracion_sla_v2_fn()`: configuración completa base/operativa, modo, revisión de control, versión de contrato y `expected_version` de publicación. Hace explícita la diferencia entre última versión publicada y actualmente vigente, para que una publicación futura no se pierda al editar.
- `crm.publicar_politica_sla_v2(...)`: requiere las cuatro reglas completas; valida rangos, listas blancas y coherencia; publica cabecera, bases y anexo operativo en una transacción con el lock/versión esperada actuales. No activa por sí sola el módulo.
- `crm.cambiar_modo_sla_operacion(p_expected_revision integer, p_modo text)`: solo Gerencia activa. Exige política operativa vigente completa para observación o activación. Al primer activo fija juntos el instante y `politica_adopcion_id`; no admite elegirlos desde cliente. Bloquea el control para actualizar, pero no toma locks de leads/tareas.

Las RPC de lectura v1 conservan firma, envelope y campos exactos. Los esquemas estrictos actuales no reciben campos nuevos. No se hace DROP de `estado_sla_leads_fn` ni se amplía su retorno.

Los publicadores v1 y v2 delegan en un mismo writer privado. V1 conserva exactamente entrada/salida y, al publicar después de una versión con anexo, copia las reglas operativas del predecesor dentro del lock. No puede desactivar accidentalmente pausas/prórrogas por omitir campos que desconoce. Si aún no hay anexo previo, conserva el comportamiento antiguo. Los extras sobre el plazo base se heredan como duración; V2 es la puerta para modificarlos. Versiones futuras y concurrencia entre ambas puertas se prueban expresamente.

En `legado`, la aplicación conserva el flujo v1 y el trigger solo realiza el avance previo. En `observacion`, Gerencia puede comparar resultados v2, pero no se conceden ajustes ni cambia la cola de los analistas. En `activo`, todos los consumidores nuevos usan v2 y los eventos elegibles conceden prórrogas. Los bundles antiguos siguen leyendo sus contratos v1; no se promete que dibujen los nuevos indicadores antes de recargarse.

Antes de la primera activación, el cálculo de observación utiliza el instante consultado como activación hipotética y la política operativa vigente como adopción hipotética; devuelve ambas hipótesis y no las persiste en el control. Por ello `politica_adopcion_id` sigue null, pero el `politica_techo_id` de una etapa legacy identifica la versión usada en la simulación. En modo legado anterior a la activación no se fabrican estos límites nuevos. La observación inicial mantiene los ajustes en cero: sirve para revisar seguimiento y compromisos, mientras el efecto de futuras prórrogas se valida con fixtures y después con eventos reales elegibles. Tras una activación previa, observación conserva la adopción y los ajustes ya concedidos, sin conceder otros. No se atribuye una reducción simulada de alertas a prórrogas que aún no ocurrieron.

La lectura simple de modo no es una barrera de apagado. Antes de insertar un ajuste, el writer toma `SELECT ... FOR SHARE` sobre la fila de control, relee modo y mantiene ese lock hasta commit. El cambio de modo usa UPDATE de esa misma fila y espera a los writers ya admitidos. Al responder «legado», todos esos ajustes han terminado y los siguientes verán legado. Un timeout del cambio no devuelve éxito ni cambia la revisión. La fila de control es siempre la última dependencia de bloqueo; la RPC de modo no adopta leads ni publica políticas dentro de ese lock. Las lecturas de estado usan un snapshot y devuelven modo/revisión/instante juntos.

**4.5 Propagación en la aplicación y lenguaje visible**

Archivos de entrada a revisar: `app/src/lib/sla-versionado.ts`, `app/src/data/crm-config-api.ts`, `app/src/data/crm-api.ts`, sus queries de configuración y CRM, `app/src/data/use-estado-sla-operativo.ts`, `app/src/lib/inteligencia.ts`, `app/src/lib/plan-lead.ts`, `app/src/lib/estancamiento.ts`, `app/src/lib/alertas.ts`, `app/src/screens/pipeline.tsx`, `app/src/screens/config-sla.tsx`, `app/src/screens/hoy/vendedor.tsx`, `app/src/screens/hoy/prioridades-vendedor.ts` y consumidores de supervisión, campana y ficha de lead.

Crear contrato y validadores v2 separados; claves de caché diferenciadas por versión y ámbito. Registrar actividad, cerrar/reprogramar/cancelar tarea, reasignar, reabrir, cambiar etapa o publicar configuración invalida estado, cola y superficies derivadas. El reloj visual puede actualizar tiempos y detectar vencimientos, pero vuelve a consultar el servidor para cambiar la tarea elegida o la clasificación; no inventa otra lógica comercial. Programar refetch en la frontera relevante y al recuperar foco, con actualización periódica máxima de 60 segundos mientras la pantalla esté visible. No se depende de cron para vencer.

El modo de operación también se revalida al recuperar foco y con refetch programado cada 60 segundos mientras la pantalla sea visible. En conexión normal se comprueban los cambios en ese intervalo; con red caída, latencia o pestaña suspendida no se garantiza respuesta antes de 60 segundos: se muestra el instante de la última lectura y el estado desactualizado. Las mutaciones usan la barrera de servidor aunque el cliente tenga una copia anterior. La interfaz nueva permite identificar un modo legado por reversión; los contratos v1 permanecen disponibles para recuperar la operación.

No se resuelve el compromiso elegido buscando solo en las tareas ya descargadas: `listarTareasDelAmbito` tiene un límite local de 2000 y puede estar sujeto a límites REST menores. V2 devuelve el resumen mínimo de la tarea elegida y el detalle se consulta por ID y ámbito al abrirla. Añadir `crm.agenda_tareas_v2_fn` con paginación por `(vence_en,id)`, rango opcional `[desde,hasta)`, límite 1–200 y total autorizado antes de paginar. El cursor conserva los filtros. La agenda permite cargar siguientes páginas y rotula carga parcial; jamás afirma que no hay pendientes a partir de la primera página. El estado/cola conservan un cálculo completo de su ámbito, aunque la agenda no se haya descargado completa.

Prioridad de acciones del analista: primera atención pendiente → tarea vencida → tarea de hoy → seguimiento pendiente → próximas tareas. Se conserva la prioridad especial de speed-to-lead y el máximo de tres movimientos de «Ahora». Un lead tiene una sola acción dominante; el detalle puede mostrar todos sus motivos y las tareas restantes permanecen accesibles. El estancamiento solo, sin acción de atención pendiente, no vuelve a contaminar la lista del analista como «Sin gestión».

Para supervisor/Gerencia, mantener reparto y primeras atenciones; añadir revisión por límite operativo agotado, tercera reprogramación o tercer ingreso a la misma etapa en el ciclo, y conservar el estancamiento bruto del pipeline. Directorio solo consulta. Reutilizar acciones existentes para la decisión humana; SLA-R2 no añade devoluciones, liberaciones ni mensajes automáticos.

Textos de aceptación: «Última gestión hace 3 días · toca seguimiento», «Compromiso hoy 10:00 · margen hasta mañana 10:00», «Lleva 12 días en Contactado · plazo original 8 días», «Prórroga por conversación · 1 usada de 2», «Revisión requerida: se agotó el plazo». Usar «analista» en etiquetas nuevas. Un error de contrato, permiso o red muestra información no disponible y reintento; no se oculta como ausencia de trabajo ni se cambia silenciosamente a otro criterio. La ausencia comprobada del módulo antes de su instalación es el único fallback automático de capacidad a v1.

El modo demo implementa las mismas reglas a partir de fixtures canónicos de entrada/salida del servidor. La lógica operativa nueva no puede coexistir accidentalmente con la supresión antigua `plan.vigente` sobre el mismo indicador. No modificar cálculos de cartera, conversiones, rentabilidad ni metas.

**5. Fases y condición de salida**

| Fase | Trabajo concreto | Se termina cuando |
|---|---|---|
| **SLA-0 — Contrato y banco de pruebas** | Guardar corte vigente, funciones/ACL/triggers/índices, núcleos, ventanas, consumidores y declaraciones de gobernanza; contrastar live/repositorio; comprobar escritor de actividades, cierre de tareas, locks e idempotencia; preparar entorno reproducible con fixtures sintéticos e invariantes actuales. | Hay manifiesto de base, contrato del núcleo, diferencias resueltas y banco que ejecuta los flujos actuales. Ningún branch obsoleto es una dependencia del plan. |
| **SLA-1 — Modelo compatible** | Crear cinco tablas, guards, ACL y auditoría; corregir orden/modos de locks en altas y cierres de tareas de lead; captura y reconstrucción por lotes con commits. Mantener legado. | Migraciones reproducibles, snapshots originales intactos, locks ensayados, tareas ambiguas identificadas y APIs v1 funcionando. |
| **SLA-2 — Motor y publicación** | Implementar núcleo operativo y ventana autorizada, extracción compatible de hechos base, prórrogas integradas con avance, recibos y puertas v2, lectores/agenda v2, publicadores compartidos y barrera de modo. | Fórmulas/concurrencia/confirmación verificadas; cada consumidor nuevo depende del núcleo; v1/v2 atómicos; apagar espera writers en vuelo; legado no concede ajustes nuevos. |
| **SLA-3 — Consumidores** | Integrar configuración, Pipeline, Ahora/Después, cola, agenda, campana, ficha y supervisión; textos, accesibilidad y estados de carga/error; demo coherente. | Un mismo lead cuenta la misma historia en cada superficie, con una acción dominante y contratos antiguos intactos. |
| **SLA-4 — Aceptación integral** | Ejecutar matriz de riesgos, pruebas por rol, build y checks exigidos por el repo; revisar escritorio y móvil; ensayar activación y reversión. | Todos los casos críticos aprobados y evidencia reproducible; sin mutaciones productivas durante las pruebas. |
| **SLA-5 — Publicación controlada** | Contrastar primero contra la cartera existente; completar integración y pruebas; aplicar el artefacto verificado; publicar frontend desde Main sincronizado con `avancecorp/main`; publicar la siguiente política conservando 2h/24h. El usuario prefiere activación conjunta si la evidencia es correcta. | Servidor y frontend identificados, contraste conciliado y configuración/activación leídas de vuelta. El SQL no se improvisa contra producción. |
| **SLA-6 — Verificación operativa** | Revisar desde la activación a las 24h, 72h y 7 días las alertas, contratos, ajustes y desempeño; atender defectos encontrados. | Cero ajustes indebidos/duplicados, cero plazos sobre techo, tareas vencidas accesibles, v1 íntegro y equipo capaz de interpretar las señales. Una reducción de alertas, por sí sola, no demuestra éxito. |

Decisión posterior del usuario: contrastar las reglas con la cartera existente antes de evaluar una activación conjunta. Se retira la exigencia de una jornada previa en observación. El modo observación sigue disponible como herramienta, sin imponerlo como fase comercial. El contraste histórico no demuestra futuras concesiones de prórroga: sus writers y concurrencia requieren pruebas antes de activar; no se crean gestiones productivas ficticias para completar una muestra.

SLA-0 a SLA-4 son la ruta de construcción. Las migraciones se generan con el flujo vigente de Supabase y se versionan en `supabase/migrations`, junto con la actualización de `MIGRACIONES.md`, oráculos y reversión. El archivo final de SQL debe poder reconstruirse y ensayarse sin desactivar todos los triggers con `session_replication_role=replica` como sustituto de probar los caminos reales.

Antes de publicar, integrar cambios remotos sin sobrescribir trabajo existente, comprobar igualdad de Main local y `avancecorp/main`, y construir exclusivamente desde ese commit. Usar un checkout aislado para este desarrollo si el árbol compartido contiene trabajo en curso. No crear ramas de release ni usar force push. Conservar la evidencia del artefacto y el corte vivo para evitar reintroducir una versión anterior del CRM.

**6. Matriz mínima de aceptación**

| Caso | Resultado exigido |
|---|---|
| Primera gestión/primer contacto | Límites y cumplimiento previos idénticos; tareas/prórrogas no los suspenden. |
| Intento sin respuesta | Reinicia seguimiento; no avanza etapa ni concede prórroga. |
| Nota/reasignación/cambio de etapa | No inventa una gestión; la reasignación utiliza la referencia de responsabilidad nueva. |
| Ayuda de supervisor | Cuenta como atención durante el episodio actual y muestra el autor real. |
| Sin gestión / sin asignación / sin foto | Fallback definido por contrato; ninguno fabrica una atención ni un estado «al día». |
| Dos conversaciones tempranas | Cero prórrogas; el seguimiento puede volver a vencer aunque la etapa siga dentro de su plazo. |
| Conversación dentro de últimas 24h | Un ajuste de ganancia real, con política/episodio correctos. |
| Conversación exactamente al vencer o después | Gestión guardada, cero prórrogas retroactivas. |
| Nuevo → Contactado | Avance preservado; cero ajustes en la etapa nueva, tanto desde actividad como desde cierre de tarea. |
| Dos actividades concurrentes | Serialización real con sesiones separadas; presupuesto y ventana respetados. |
| Reintento por transporte | UUID reutilizado y confirmación del evento; sin actividad ni ajuste duplicados. |
| Writer interno sin usuario | Conserva actividad/avance autorizado; no concede prórroga. |
| Techo parcial / presupuesto agotado | Se registra solo la ganancia restante o ningún ajuste; la actividad sigue guardándose. |
| Cita antes de su hora, en su hora y durante margen | Cobertura continua hasta su frontera; agenda mantiene su propio atraso. |
| Exactamente al terminar margen o alcanzar techo | Cobertura terminada; nunca se muestra una pausa posterior al techo. |
| Tarea atrasada y otra futura | La atrasada domina; la futura no la oculta. |
| Completar/cancelar/desactivar/reprogramar | Selección y estados se actualizan de forma consistente; no se conserva una pausa fantasma. |
| Tercera reprogramación | Tarea permanece visible, cobertura retirada y revisión informada. |
| Reunión que abre etapa | Contexto válido dentro del mismo ciclo; puede cubrir la nueva etapa. |
| Cambio de dueño / reapertura | Se heredan tareas del mismo ciclo; las del ciclo anterior no cubren. |
| Tarea heredada sin contexto demostrable | Agenda conservada, sin cobertura, dato pendiente de revisión. |
| Stock anterior a activación | Historial intacto; señales operativas desde activación; cero prórrogas retrospectivas. |
| Política posterior / vuelta a activo | No reinicia primera activación, presupuesto ni techo de episodios ya sellados. |
| Publicador v1 tras política ampliada | Conserva reglas operativas y su respuesta estricta antigua. |
| Publicaciones concurrentes / vigencia futura | Una versión gana; conflicto controlado; nunca queda política con solo parte de las cuatro reglas. |
| Contratos v1/v2 y bundles antiguos | Lectores antiguos parsean exactamente; nuevos aplican v2 solo en modo activo. |
| Analista/supervisor/Gerencia/Directorio/inactivo/anon | Visibilidad y capacidades iguales al ámbito autorizado; IDs ajenos no amplían lectura. |
| Persona con «No insistir» / lead cerrado o inactivo | Ninguna alerta nueva sugiere contactar; historial visible solo con el permiso ya existente. |
| Más leads que el límite de cola | Totales calculados antes del límite; la selección conserva prioridades y anuncia hay_mas. Agenda y listas permiten acceder al resto. |
| Pantalla abierta durante vencimiento | Refetch en la frontera y cada 60 segundos como máximo mientras esté visible; sin alertas duplicadas. Red/suspensión se rotulan como lectura desactualizada, sin prometer una respuesta puntual. |
| Error de red/contrato | Información parcial explícita y reintento; nunca falso «al día». |
| Reversión a modo legado | V1 y avance automático operativos, cero ajustes nuevos, historial de ajustes preservado. |

Casos adicionales obligatorios surgidos de la auditoría R2:

| Caso | Resultado exigido |
|---|---|
| Cambiar extra de política con etapa legacy abierta | Su techo sigue usando la política de adopción inicial. |
| Vencer margen sin resolver tarea | La cobertura termina, pero el límite operativo no salta al plazo base. |
| Tarea ambigua anterior a otra futura válida | Sin cobertura; la ambigua sigue visible y se informa el dato incompleto. |
| Dos altas de tareas en el mismo lead | Lock fuerte desde la primera lectura; sin deadlock por upgrade de SHARE. |
| Cerrar tarea frente a reasignar/reprogramar | Orden lead → tarea, revalidación después de esperar y sin deadlock. |
| Misma llave con payload/operación distintos | Conflicto; cero nuevo efecto y sin devolución del recibo ajeno. |
| Cierre confirmado cuya respuesta se pierde | Reintento devuelve el mismo recibo y siguiente_id; no exige que la tarea siga pendiente. |
| Apagar mientras una prórroga está en vuelo | El cambio espera su commit; tras confirmar legado no aparece otro ajuste nuevo. |
| Prórroga configurada <= 24 horas | Rechazo de configuración; no permite consumir varias por conversaciones inmediatas. |
| Extra 6 días / prórroga 4 días / cantidad 2 | Configuración válida; ajustes 4 días y 2 días como máximo. |
| Cancelar la última reunión | Se conserva el retroceso real y el cierre/apertura de episodios, sin fingir una prórroga. |
| Tercer ingreso a la misma etapa en el ciclo | Revisión por recorrido repetido aunque el episodio recién abierto esté en plazo. |
| Más de 2000 tareas / límite REST inferior | Tarea elegida accesible por ID, agenda paginada y estado de carga parcial correcto. |
| Fallo de captura que no se resuelve con modo legado | Migración de contingencia ensayada; hueco de contexto identificado antes de reactivar. |
| Misma regla en estado, cola, ficha, Pipeline y campana | Todos consumen el mismo hecho del núcleo; sin fórmulas propias ni elección local de compromiso. |
| Mutante aislado de una decisión del núcleo | Falla la paridad de cada consumidor de esa decisión; ningún consumidor sigue dando el valor anterior por una copia local. |
| Gobernanza de funciones modificadas/nuevas | Declaraciones y huellas vigentes; sin elevar topes, omitir censos ni alterar núcleos ajenos para pasar controles. |

Medir latencia de estado y cola con el mismo dataset por rol antes/después, al menos 30 lecturas por escenario tras calentamiento y tamaños de página representativos. Guardar p50/p95 y `EXPLAIN (ANALYZE, BUFFERS)` en el banco. Si p95 de un recorrido aumenta más de 20 %, investigar y corregir o documentar expresamente la causa antes de activar; no extrapolar la muestra pequeña a millones de leads. La evaluación masiva de cola debe limitarse al ámbito autorizado y evitar una consulta por lead desde el navegador.

**7. Activación, medición y reversión**

Orden productivo: contraste local de cartera real → integración y pruebas completas → servidor en legado → smoke v1 y modelo → frontend compatible → nueva política con reglas → activación conjunta evaluada con el usuario → readback autenticado por rol. El trabajo de contraste no activa producción. No activar si falta la política operativa vigente completa. Si hay una publicación futura pendiente, resolver el orden de vigencias antes de programar la activación, sin sobrescribirla.

Contadores actuales, con denominador y política identificados: etapas fuera de plazo original, seguimientos pendientes, compromisos que cubren, revisiones requeridas, contextos de tareas sin demostrar y ajustes concedidos por motivo/tipo. Comparar también pertenencia de leads y razones, no solo totales. Mantener separadas las señales simultáneas: no sumarlas como si fueran leads diferentes. Los conteos solo son una foto comparable al mismo instante y ámbito.

La reversión operativa es cambiar modo a legado con la barrera descrita: se esperan los ajustes admitidos, cesan nuevos ajustes y el cliente vuelve a superficies v1 al revalidar. Se preservan políticas, tareas, solicitudes confirmadas y ajustes. La captura de contexto y los escritores compartidos siguen instalados: el modo no revierte DDL ni puede resolver cualquier fallo estructural.

Por ello el entregable incluye también una migración de contingencia ensayada que restaura los cuerpos compatibles afectados y retira únicamente los hooks nuevos que causen el fallo, manteniendo los arreglos de locks y el avance automático probado. Se ejecuta solo si el control de modo no basta, con SQL revisado y sin borrar registros. Si se interrumpe la captura, las tareas del intervalo quedan sin cobertura hasta completar reconstrucción/verificación; no se reactiva el módulo ignorando ese hueco. Nunca se eliminan tablas o branches ni se reescriben episodios como rollback. El frontend previo se conserva como respaldo, evitando sobreescribir trabajos ajenos. Reactivar conserva instante, política de adopción y presupuestos consumidos.

**8. Entregables de la implementación**

Manifiesto SLA-0 y línea base; ficha del núcleo, ventana y consumidores; migraciones reproducibles; contratos de RPC y schemas v2; fixtures y oráculos de concurrencia/roles/paridad arquitectónica; evidencia visual de las superficies; publicación identificada por commit y artefacto; política efectiva leída de vuelta; runbook de modos y reversión; informe de observación/seguimiento. El informe debe distinguir lo probado en el banco de lo observado con usuarios reales.

La definición de terminado es que **el analista pueda atender sin alertas contradictorias, supervisión conserve el estancamiento real y cada plazo adicional tenga una causa verificable**, con los contratos existentes y la historia intactos.
