# Plan final implementable — seguimiento, compromisos y SLA de etapas

Versión: **SLA-R1 · 2026-09-06**. Sustituye como guía de desarrollo a `spec-prorroga-sla-etapas.md`; la propuesta original y su análisis se conservan como antecedentes. Las fases se identifican SLA-0 a SLA-6 para evitar colisiones con el backlog P-050–P-054.

Estado: **plan de implementación entregado**. Las decisiones siguientes son la configuración inicial recomendada de este plan, no una afirmación de aprobación comercial anterior. No se aplicó SQL ni se publicó código. El inicio del desarrollo debe comprobar los hechos de SLA-0; la aplicación a producción requiere el SQL exacto, sus pruebas y su reversión revisables, conforme a la memoria del proyecto.

**1. Resultado que debe obtener el negocio**

El analista identifica a quién atender y qué compromiso cumplir. Supervisor y Gerencia distinguen la falta de seguimiento del estancamiento de una oportunidad. Agendar una tarea o conversar con el cliente puede justificar tiempo adicional, pero nunca cambia el inicio histórico de la etapa ni convierte una oportunidad estancada en una oportunidad que avanzó.

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

Reloj corrido; presentación en `America/Lima`. Todos los parámetros se almacenan en minutos enteros. Los plazos de seguimiento 1/3/3/5 días se apoyan en los umbrales operativos actuales de cola; las duraciones y techos conservan la propuesta base. Son valores iniciales configurables, no una optimización estadística demostrada. El reloj laboral y los feriados quedan fuera de SLA-R1.

La nueva política será **la siguiente versión disponible**, previsiblemente v6; ningún script debe exigir que su número sea siempre 6. Primera gestión y primer contacto se copian de la configuración vigente comprobada al publicar, sin cambiarlos incidentalmente.

**3.1 Seguimiento: duración y fecha límite separadas**

- Gestión válida: `llamada_realizada`, `llamada_no_contestada`, `whatsapp_enviado`, `whatsapp_recibido`, `reunion_realizada`.
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
mostrar_seguimiento_pendiente = seguimiento_vencido AND NOT cobertura_compromiso
```

`primera_activacion_en` se fija una sola vez y no se reinicia al cambiar política, revertir el modo o reactivar el módulo. Permite aplicar las reglas operativas al stock actual desde la activación sin fabricar incumplimientos de fechas anteriores. No concede un período adicional completo de gracia: los seguimientos que ya requieren atención aparecen al activar.

**3.2 Compromiso: elegir el primero pendiente, incluyendo el atrasado**

Una tarea puede cubrir seguimiento y ampliar el plazo operativo de etapa cuando cumple todos estos criterios:

- Es de ese lead, del ciclo actual, activa y pendiente; tipo `llamada`, `whatsapp` o `reunion`. Una tarea administrativa genérica no concede pausa.
- Su tenencia corresponde a la tenencia actual del lead. Las tareas comerciales pendientes se heredan al nuevo responsable dentro del mismo ciclo, como ya hace el CRM; se muestra que el compromiso fue heredado y se conserva su autoría.
- Tiene fecha válida. Las fechas inválidas no conceden cobertura y deben producir un estado de dato incompleto, sin pintar «al día».
- Se ordenan **todas** las tareas comerciales pendientes elegibles por `vence_en ASC, id ASC` y se elige una. No se filtran previamente las vencidas ni se elige la más lejana.
- Las tareas siguen siendo válidas al avanzar de etapa dentro del mismo ciclo. La reunión que ocasiona entrar a «Reunión agendada» puede justificar la cobertura de esa etapa.
- La tercera reprogramación de la tarea (`reprogramaciones >= 3`) retira su capacidad de conceder cobertura y genera motivo de revisión para el supervisor. La tarea sigue en agenda. Cancelarla y crear otra no reinicia la antigüedad ni el techo del episodio.

```text
compromiso_hasta = min(tarea_elegida.vence_en + margen, techo_operativo_etapa)
cobertura_compromiso = pausa_habilitada
                       AND existe tarea_elegida
                       AND tarea_elegida.reprogramaciones < 3
                       AND ahora < compromiso_hasta
```

Al llegar a la hora de la tarea, el margen continúa. Al llegar exactamente a `compromiso_hasta`, termina la cobertura. Una tarea cuyo margen ya terminó permanece como primera pendiente y evita que otra futura la oculte; se debe completar, cancelar con motivo o reprogramar. Al completar, cancelar o desactivar, se vuelve a elegir la primera pendiente en la siguiente lectura. La interfaz confirma el resultado del servidor y actualiza agenda, cola y ficha juntas.

La agenda conserva su criterio actual de atraso por hora. Que exista margen de SLA no elimina una tarea vencida de agenda. No se utiliza el criterio antiguo «cualquier plan cuyo día de Lima no pasó» como sustituto de esta cobertura; las pantallas que mantienen ese criterio por otros motivos siguen distinguiéndolo expresamente.

**3.3 Prórroga: conversación cerca del vencimiento y presupuesto finito**

Solo `llamada_realizada`, `whatsapp_recibido` y `reunion_realizada`. En esta entrega solo gestiones humanas autenticadas por las puertas actuales autorizadas del CRM. Los writers internos sin identidad humana conservan su comportamiento de registro y avance, pero no conceden prórrogas; una futura integración necesita incorporarse explícitamente a ese contrato.

Se concede automáticamente una prórroga únicamente si:

1. El episodio abierto pertenece a una política que incluye las nuevas reglas y su etapa es Contactado o Propuesta enviada.
2. Era el mismo episodio antes y después del avance automático provocado por esa actividad.
3. Queda presupuesto y la actividad no produjo ya un ajuste en ese episodio.
4. La conversación se registró durante las **últimas 24 horas antes del límite prorrogado**, sin incluir el instante del vencimiento: `limite_prorrogado - 1440 min <= evento_en < limite_prorrogado`.
5. La extensión aumenta realmente el límite sin superar el techo de ese episodio.

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
limite_operativo_etapa = min(max(limite_prorrogado, cobertura_hasta_si_valida), techo_operativo_etapa)
revision_comercial_requerida = ahora >= limite_operativo_etapa
```

Si no hay cobertura válida, `cobertura_hasta_si_valida` se reemplaza por `limite_prorrogado`. Prórroga y cobertura no se suman entre sí: se utiliza el mayor límite y se recorta al techo. El seguimiento tiene su cálculo propio y no se apaga por haber recibido una prórroga.

El pipeline conserva el semáforo original: en plazo antes del límite base; atención desde ese límite; crítico desde el doble de su duración. El indicador adicional «Revisión requerida» permite actuar antes o después de ese segundo escalón según el plazo operativo; ambos valores deben llevar rótulos distintos. Al agotarse el techo, el supervisor recibe la oportunidad para decidir; no se cambia de etapa ni de dueño automáticamente.

**3.5 Cartera actual, políticas nuevas y pasado**

- Seguimiento y cobertura de agenda se aplican a **toda la cartera abierta desde la primera activación**, usando la política operativa vigente. Cambios posteriores de esos parámetros rigen para la operación desde su vigencia y no alteran reportes históricos.
- Una etapa nacida antes de existir las reglas ampliadas conserva `politica_id`, inicio y límite base. No recibe prórrogas automáticas. Para su cobertura prospectiva, el techo es `limite_base_historico + tope_extra_minutos de la regla operativa vigente`.
- Una etapa nacida con reglas ampliadas obtiene parámetros de prórroga y techo de **su política de entrada**: `techo = limite_base + tope_extra_minutos sellado por esa versión`. Publicar otra política no amplía su presupuesto ni su techo. La configuración actual de seguimiento/margen puede variar prospectivamente, pero la cobertura nunca cruza ese techo sellado.
- Los extras iniciales son Nuevo 2 días, Contactado 8, Reunión 3 y Propuesta 7. Se almacenan como duración adicional para que un publicador antiguo que cambie el plazo base conserve una relación coherente.
- Una etapa histórica que ya superó su techo no se maquilla como atendida: queda para revisión de supervisión. Su agenda permanece utilizable.
- Los indicadores históricos de cumplimiento SLA continúan calculándose con los snapshots originales. No se publican métricas históricas de «pausas cumplidas» a partir del estado actual de tareas. Los nuevos conteos de seguimiento/revisión se rotulan como situación actual.

**4. Diseño técnico que implementa las reglas**

**4.1 Modelo aditivo: cuatro tablas nuevas, sin backfill sobre políticas publicadas**

| Objeto | Contenido y garantías |
|---|---|
| `crm.sla_politica_etapas_operacion` | PK `(politica_id, etapa)` y FK compuesta a `sla_politica_etapas(politica_id, etapa)`. Campos: `seguimiento_minutos`, `prorroga_minutos`, `prorroga_max`, `tope_extra_minutos`, `pausa_habilitada`, `pausa_margen_minutos`. Filas inmutables, creadas junto con una política nueva. La ausencia de fila representa una política histórica sin ampliación. |
| `crm.lead_sla_etapa_ajustes` | `id`, `etapa_sla_id`, `origen_actividad_id` obligatorio, `secuencia`, `minutos_reales`, `limite_antes`, `limite_despues`, `creado_por`, `creado_en`. FKs restrictivas; UNIQUE `(etapa_sla_id, origen_actividad_id)` y `(etapa_sla_id, secuencia)`. INSERT-only. Lead y política se obtienen del episodio; no se duplican en la fila. |
| `crm.tarea_sla_contexto` | PK/FK `tarea_id`, `lead_id`, `ciclo_n`, `fuente` (`evento` o `reconstruido`), `registrado_en`; FK `(lead_id,ciclo_n)` al ciclo SLA. Identifica el ciclo causal de la tarea sin modificar su contrato público. Inmutable. |
| `crm.sla_operacion_control` | Fila única: `modo` (`legado`, `observacion`, `activo`), `revision`, `primera_activacion_en`, autor y fecha del cambio. El primer instante de activación es inmutable una vez fijado. Cambios auditados mediante una única RPC de Gerencia con versión esperada. |

Constraints de reglas: seguimiento entero 1–43200; prórroga 0–43200; cantidad 0–5; extra 0–43200; margen 0–10080; cantidad cero si y solo si duración cero; sin prórroga en Nuevo/Reunión; pausa deshabilitada implica margen cero; presupuesto concedible no mayor que el extra. Para ajustes: secuencia positiva, minutos positivos y `limite_despues = limite_antes + minutos_reales * interval '1 minute'`. Autor de la actividad y correspondencia actividad–episodio comprobados en el writer.

La tabla anexa evita el UPDATE bloqueado de políticas antiguas y el default cero incompatible con su máximo. El publicador actual sigue pudiendo funcionar antes de activar la ampliación. La FK aprovecha la unicidad existente por política/etapa, según las reglas de [constraints de PostgreSQL](https://www.postgresql.org/docs/current/ddl-constraints.html).

Todas las tablas nuevas: RLS habilitada, sin policies de acceso humano directo, ACL explícitas; lectura y escritura solo mediante las funciones autorizadas. Las funciones internas no conceden EXECUTE a PUBLIC, anon, authenticated ni service_role. Las RPC públicas conceden solo a authenticated y revalidan usuario activo, rol y ámbito. Directorio conserva lectura, nunca configuración/escritura. El control no puede ampliar permisos sobre leads.

Índices: los UNIQUE de ajustes ya cubren búsquedas por episodio; añadir índice de actividad por FK. Evaluar índice de tareas `(lead_id, vence_en, id)` parcial `activo AND estado='pendiente'` y el de actividades por lead/fecha y conjunto de gestión, reutilizando los existentes cuando cubran la consulta. No crear índices duplicados ni justificar desnormalización por los 827 registros actuales.

**4.2 Contexto de tareas y adopción del stock**

Las tareas nuevas de lead toman su contexto del servidor. Un BEFORE INSERT posterior a los gates existentes obtiene el lock del lead y revalida estado activo/ciclo; debe cubrir también writers internos que pretendan crear tareas comerciales. El AFTER INSERT registra el contexto usando ese mismo ciclo bloqueado. No acepta ciclo ni tenencia elegidos por el cliente. Las tareas de perfil/postventa no participan.

El stock pendiente se incorpora por lotes con locks de leads en orden estable, relectura después del lock y correspondencia de tenencia. Solo se crea contexto reconstruido si el lead tiene ciclo abierto válido y la fecha de creación de la tarea pertenece a ese ciclo. Las tareas cuyo ciclo no pueda demostrarse continúan en agenda y se listan como «contexto por revisar»; no conceden cobertura. No se alteran sus fechas, estados ni autores para hacerlas pasar por válidas.

El poblamiento inicial se realiza dentro de la migración antes de instalar el guard definitivo de la tabla nueva, manteniendo sus privilegios externos revocados desde su creación. Los triggers de captura, los guards y las verificaciones finales quedan instalados antes del commit; las nuevas tablas no se exponen a otros clientes durante esa transacción. Si el volumen o la espera de locks exceden el presupuesto ensayado, dividir el poblamiento en una migración de mantenimiento explícita en modo legado, con writer privado de uso exclusivo por el propietario y retirado al terminar; nunca deshabilitar el guard de políticas existentes ni abrir una RPC de reconstrucción a usuarios. Las tareas ambiguas requieren revisión y, si corresponde, cancelar el compromiso anterior con motivo y agendar uno nuevo del ciclo actual.

Cerrar/reabrir el lead deja fuera los contextos de ciclos anteriores; se mantiene la cancelación de tareas del cierre actual. Reasignar dentro del mismo ciclo conserva el contexto y la sincronización de tenencia. Las pruebas incluyen tareas creadas en la misma transacción que el lead, reuniones que abren etapa, reaperturas y writers internos. Si la auditoría encuentra una puerta que no preserva ese orden, se incorpora al alcance de SLA-1 antes de activar, sin relajar permisos.

**4.3 Conceder la prórroga sin comparar relojes diferentes**

Se amplía el recorrido de `private.trg_actividades_avance_etapa`, conservando el trigger `trg_zz_actividades_avance_etapa` y la semántica actual de avance. No se añade un trigger `zzz` con una comparación de timestamps.

Para una actividad elegible autenticada: obtener/reutilizar el lock del lead, capturar el ID del episodio abierto, ejecutar el avance automático existente y volver a consultar el episodio. Solo llamar a `private.sla_conceder_prorroga` si ambos IDs coinciden. El helper toma `new.creado_en` sellado por el servidor como instante del evento, revalida episodio/política, ventana, unicidad y presupuesto, e inserta la ganancia real. La primera conversación en Nuevo compara dos IDs distintos y no concede ajuste.

Conservar el guard de reentrada del avance y restaurar cualquier setting transaccional al valor previo. El guard de ajustes comprueba valor explícito, profundidad de trigger, inmutabilidad y coherencia; no utiliza `current_setting(...,'on')` como si fuera un permiso. Las funciones nuevas se crean y sus privilegios se restringen en la misma transacción, conforme a [PostgreSQL, funciones SECURITY DEFINER](https://www.postgresql.org/docs/current/sql-createfunction.html).

El lock de la fila del lead serializa todos los writers que sí conceden prórrogas. Los internos sin usuario no conceden ajustes en SLA-R1. Se preserva el orden de locks existente del dominio de identidad antes de lead; el nuevo helper no toma locks de identidad ni de tareas. No se cambia `clock_timestamp()` por `statement_timestamp()` en la gestión serializada.

La idempotencia del ajuste evita un segundo asiento para el mismo evento. El reintento de una actividad debe reutilizar su UUID y confirmar el registro persistido, sin generar otro UUID por un error de transporte. Se revisa la puerta existente de registro/cierre de tarea y se añade la confirmación necesaria en ese borde; no se presenta una violación UNIQUE como éxito al usuario. Un rechazo por falta de presupuesto es un no-op del ajuste, no un rollback de la actividad.

**4.4 Un cálculo operativo y contratos nuevos compatibles**

`private.sla_operacion_leads(p_lead_ids uuid[], p_ahora timestamptz)` concentra seguimiento, tarea elegida, límites y motivos. Solo las RPC autorizadas pueden invocarlo y filtran el ámbito antes de calcular. El instante es único por llamada; no se recibe desde el navegador ni se agregan ajustes de episodios cerrados al episodio vigente.

Contratos externos:

- `crm.estado_sla_leads_v2_fn(p_lead_ids uuid[])`: JSON versionado, máximo 200 IDs únicos por llamada, solo filas visibles. Incluye `version=2`, modo, `calculado_en`, versión operativa, identidad del episodio/ciclo/asignación, estado base, seguimiento, compromiso elegido, prórrogas, techo, límites y motivos. Un lead sin foto válida devuelve estado explícito no evaluable; nunca «al día» por ausencia de datos. El frontend pide IDs de páginas visibles y fragmenta lotes mayores.
- `crm.cola_accion_v2_fn(p_limite integer default 100)`: usa el mismo cálculo para todo el ámbito y aplica límite **después** de clasificar y contar. Devuelve versión, instante, totales sin truncar, items y motivos. El analista recibe acciones; supervisión añade revisiones de etapa. No deriva los contadores globales de una página de 100 items.
- `crm.configuracion_sla_v2_fn()`: configuración completa base/operativa, modo, revisión de control, versión de contrato y `expected_version` de publicación. Hace explícita la diferencia entre última versión publicada y actualmente vigente, para que una publicación futura no se pierda al editar.
- `crm.publicar_politica_sla_v2(...)`: requiere las cuatro reglas completas; valida rangos, listas blancas y coherencia; publica cabecera, bases y anexo operativo en una transacción con el lock/versión esperada actuales. No activa por sí sola el módulo.
- `crm.cambiar_modo_sla_operacion(p_expected_revision, p_modo)`: solo Gerencia activa. Exige política operativa vigente completa para activar y preserva el primer instante de activación. No admite elegir ese timestamp desde el cliente.

Las RPC de lectura v1 conservan firma, envelope y campos exactos. Los esquemas estrictos actuales no reciben campos nuevos. No se hace DROP de `estado_sla_leads_fn` ni se amplía su retorno.

Los publicadores v1 y v2 delegan en un mismo writer privado. V1 conserva exactamente entrada/salida y, al publicar después de una versión con anexo, copia las reglas operativas del predecesor dentro del lock. No puede desactivar accidentalmente pausas/prórrogas por omitir campos que desconoce. Si aún no hay anexo previo, conserva el comportamiento antiguo. Los extras sobre el plazo base se heredan como duración; V2 es la puerta para modificarlos. Versiones futuras y concurrencia entre ambas puertas se prueban expresamente.

En `legado`, la aplicación conserva el flujo v1 y el trigger solo realiza el avance previo. En `observacion`, Gerencia puede comparar resultados v2, pero no se conceden ajustes ni cambia la cola de los analistas. En `activo`, todos los consumidores nuevos usan v2 y los eventos elegibles conceden prórrogas. Los bundles antiguos siguen leyendo sus contratos v1; no se promete que dibujen los nuevos indicadores antes de recargarse.

Antes de la primera activación, el cálculo de observación utiliza el instante consultado como activación hipotética, lo devuelve expresamente y no lo persiste. Los ajustes siguen en cero: la observación sirve para revisar seguimiento y compromisos, mientras el efecto de futuras prórrogas se valida con fixtures y después con eventos reales elegibles. No se atribuye una reducción simulada de alertas a prórrogas que aún no ocurrieron.

**4.5 Propagación en la aplicación y lenguaje visible**

Archivos de entrada a revisar: `app/src/lib/sla-versionado.ts`, `app/src/data/crm-config-api.ts`, `app/src/data/crm-api.ts`, sus queries de configuración y CRM, `app/src/data/use-estado-sla-operativo.ts`, `app/src/lib/inteligencia.ts`, `app/src/lib/plan-lead.ts`, `app/src/lib/estancamiento.ts`, `app/src/lib/alertas.ts`, `app/src/screens/pipeline.tsx`, `app/src/screens/config-sla.tsx`, `app/src/screens/hoy/vendedor.tsx`, `app/src/screens/hoy/prioridades-vendedor.ts` y consumidores de supervisión, campana y ficha de lead.

Crear contrato y validadores v2 separados; claves de caché diferenciadas por versión y ámbito. Registrar actividad, cerrar/reprogramar/cancelar tarea, reasignar, reabrir, cambiar etapa o publicar configuración invalida estado, cola y superficies derivadas. El reloj visual puede actualizar tiempos y detectar vencimientos, pero vuelve a consultar el servidor para cambiar la tarea elegida o la clasificación; no inventa otra lógica comercial. Programar refetch en la frontera relevante y al recuperar foco, con actualización periódica máxima de 60 segundos mientras la pantalla esté visible. No se depende de cron para vencer.

El modo de operación también se revalida al recuperar foco y como máximo cada 60 segundos; una activación o reversión no depende de recargar manualmente toda la aplicación. Las mutaciones leen el modo en servidor dentro de su transacción, aunque el cliente tenga una copia anterior. La interfaz nueva permite identificar un modo legado por reversión; los contratos v1 permanecen disponibles para la recuperación.

Prioridad de acciones del analista: primera atención pendiente → tarea vencida → tarea de hoy → seguimiento pendiente → próximas tareas. Se conserva la prioridad especial de speed-to-lead y el máximo de tres movimientos de «Ahora». Un lead tiene una sola acción dominante; el detalle puede mostrar todos sus motivos y las tareas restantes permanecen accesibles. El estancamiento solo, sin acción de atención pendiente, no vuelve a contaminar la lista del analista como «Sin gestión».

Para supervisor/Gerencia, mantener reparto y primeras atenciones; añadir revisión por límite operativo agotado o tercera reprogramación, y conservar el estancamiento bruto del pipeline. Directorio solo consulta. Reutilizar acciones existentes para la decisión humana; SLA-R1 no añade devoluciones, liberaciones ni mensajes automáticos.

Textos de aceptación: «Última gestión hace 3 días · toca seguimiento», «Compromiso hoy 10:00 · margen hasta mañana 10:00», «Lleva 12 días en Contactado · plazo original 8 días», «Prórroga por conversación · 1 usada de 2», «Revisión requerida: se agotó el plazo». Usar «analista» en etiquetas nuevas. Un error de contrato, permiso o red muestra información no disponible y reintento; no se oculta como ausencia de trabajo ni se cambia silenciosamente a otro criterio. La ausencia comprobada del módulo antes de su instalación es el único fallback automático de capacidad a v1.

El modo demo implementa las mismas reglas a partir de fixtures canónicos de entrada/salida del servidor. La lógica operativa nueva no puede coexistir accidentalmente con la supresión antigua `plan.vigente` sobre el mismo indicador. No modificar cálculos de cartera, conversiones, rentabilidad ni metas.

**5. Fases y condición de salida**

| Fase | Trabajo concreto | Se termina cuando |
|---|---|---|
| **SLA-0 — Contrato y banco de pruebas** | Guardar corte vigente, funciones/ACL/triggers/índices y dependencias; contrastar live/repositorio; comprobar escritor de actividades, cierre de tareas, locks e idempotencia; preparar entorno desechable reproducible con fixtures sintéticos y los invariantes actuales. | Hay manifiesto de base, diferencias resueltas y banco que ejecuta los flujos actuales. Ningún branch obsoleto es una dependencia del plan. |
| **SLA-1 — Modelo compatible** | Crear las cuatro tablas, guards, ACL, auditoría, contexto de tareas y reconstrucción conservadora. Mantener modo legado. | Migración reproducible, originales iguales antes/después, tareas ambiguas identificadas y APIs v1 funcionando. |
| **SLA-2 — Motor y publicación** | Implementar cálculo, helper de prórrogas integrado con avance, lectores v2, publicadores compartidos y control de modo. | Fórmulas y concurrencia verificadas; publicar por v1/v2 es atómico y no pierde reglas; modo legado no concede ajustes. |
| **SLA-3 — Consumidores** | Integrar configuración, Pipeline, Ahora/Después, cola, agenda, campana, ficha y supervisión; textos, accesibilidad y estados de carga/error; demo coherente. | Un mismo lead cuenta la misma historia en cada superficie, con una acción dominante y contratos antiguos intactos. |
| **SLA-4 — Aceptación integral** | Ejecutar matriz de riesgos, pruebas por rol, build y checks exigidos por el repo; revisar escritorio y móvil; ensayar activación y reversión. | Todos los casos críticos aprobados y evidencia reproducible; sin mutaciones productivas durante las pruebas. |
| **SLA-5 — Publicación controlada** | Presentar SQL exacto y reversión; aplicar el artefacto verificado; publicar frontend desde Main sincronizado con `avancecorp/main`; publicar la siguiente política conservando 2h/24h; comparar en observación antes de activar. | Servidor y frontend identificados, observación conciliada y configuración/activación leídas de vuelta. El SQL no se improvisa contra producción. |
| **SLA-6 — Verificación operativa** | Revisar desde la activación a las 24h, 72h y 7 días las alertas, contratos, ajustes y desempeño; atender defectos encontrados. | Cero ajustes indebidos/duplicados, cero plazos sobre techo, tareas vencidas accesibles, v1 íntegro y equipo capaz de interpretar las señales. Una reducción de alertas, por sí sola, no demuestra éxito. |

La observación de SLA-5 exige al menos una jornada operativa y debe incluir tanto analistas como supervisor; no es una dependencia para desarrollar o probar SLA-1–4. Si no aparecen conversaciones dentro de la ventana de prórroga, se declara ausencia de muestra productiva; no se crean gestiones ficticias para completar la medición. Los casos sintéticos deben haber pasado antes.

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
| Más leads que el límite de cola | Totales calculados antes del límite; la paginación no altera prioridades ni cuenta solo lo descargado. |
| Pantalla abierta durante vencimiento | Actualiza estado sin recarga manual, como máximo en 60 segundos, y no duplica alertas. |
| Error de red/contrato | Información parcial explícita y reintento; nunca falso «al día». |
| Reversión a modo legado | V1 y avance automático operativos, cero ajustes nuevos, historial de ajustes preservado. |

Medir latencia de estado y cola con el mismo dataset por rol antes/después, al menos 30 lecturas por escenario tras calentamiento y tamaños de página representativos. Guardar p50/p95 y `EXPLAIN (ANALYZE, BUFFERS)` en el banco. Si p95 de un recorrido aumenta más de 20 %, investigar y corregir o documentar expresamente la causa antes de activar; no extrapolar la muestra pequeña a millones de leads. La evaluación masiva de cola debe limitarse al ámbito autorizado y evitar una consulta por lead desde el navegador.

**7. Activación, medición y reversión**

Orden productivo: servidor en legado → smoke v1 y modelo → frontend compatible → nueva política con reglas → modo observación → jornada y conciliación → modo activo → readback autenticado por rol. No activar si falta la política operativa vigente completa. Si hay una publicación futura pendiente, resolver el orden de vigencias antes de programar la activación, sin sobrescribirla.

Contadores actuales, con denominador y política identificados: etapas fuera de plazo original, seguimientos pendientes, compromisos que cubren, revisiones requeridas, contextos de tareas sin demostrar y ajustes concedidos por motivo/tipo. Comparar también pertenencia de leads y razones, no solo totales. Mantener separadas las señales simultáneas: no sumarlas como si fueran leads diferentes. Los conteos solo son una foto comparable al mismo instante y ámbito.

La reversión operativa es cambiar modo a legado: cesan nuevas prórrogas y se vuelve a las superficies v1, manteniendo el avance automático. Se preservan políticas, tareas y ajustes ya registrados. No borrar tablas, eliminar branch ni reescribir episodios como rollback. El frontend previo se conserva como artefacto de respaldo, pero la primera medida es el control de modo para no reemplazar cambios de otros trabajos. La reactivación posterior conserva el primer instante de activación y los presupuestos ya consumidos.

**8. Entregables de la implementación**

Manifiesto SLA-0 y línea base; migraciones reproducibles; contratos de RPC y schemas v2; fixtures y oráculos de concurrencia/roles; evidencia visual de las superficies; publicación identificada por commit y artefacto; política efectiva leída de vuelta; runbook de modos y reversión; informe de observación/seguimiento. El informe debe distinguir lo probado en el banco de lo observado con usuarios reales.

La definición de terminado es que **el analista pueda atender sin alertas contradictorias, supervisión conserve el estancamiento real y cada plazo adicional tenga una causa verificable**, con los contratos existentes y la historia intactos.
