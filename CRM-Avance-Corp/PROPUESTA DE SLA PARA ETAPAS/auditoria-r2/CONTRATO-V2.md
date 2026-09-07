# Contrato normativo SLA-R2

Este anexo describe los contratos implementados para la primera entrega de SLA-R2: N1 sirve estado y cola, N2 configuración/contexto/prórrogas y N3 gestión confirmada. La instalación y publicación siguen pendientes hasta registrar evidencia en [PUBLICACION-SLA-2026-09-07.md](../PUBLICACION-SLA-2026-09-07.md). Todos dependen del [núcleo y la ventana de SLA](ARQUITECTURA-NUCLEO-SLA.md); las firmas de pantalla no son calculadoras independientes. `UUID` es UUID válido; `Instante` es ISO 8601 con zona y fecha finita; `Entero` es entero JSON, sin números serializados como texto. Los parámetros de negocio solo aceptan las claves indicadas; los campos de auditoría se derivan en servidor. Las formas aspiracionales anteriores a esta primera publicación quedan sustituidas por las descritas aquí.

**1. Estado de leads**

La cola del apartado 2 incorpora el [ajuste de filtros y paginación posterior al contraste](../AJUSTE-LECTURA-COLA-TRAS-CONTRASTE.md). El cálculo de estado permanece en el mismo núcleo; el contrato v1 existente conserva su forma.

Firma: `crm.estado_sla_leads_v2_fn(p_lead_ids uuid[]) RETURNS jsonb`.

Entrada: array obligatorio, sin NULL, máximo 200 elementos; IDs repetidos se normalizan antes de evaluar. Vacío devuelve filas vacías. Un ID fuera de ámbito o inexistente no produce fila ni razón que revele existencia. No se acepta `p_ahora` público.

Envelope: `{version: 2, modo: 'legado'|'observacion'|'activo', control_revision: Entero, calculado_en: Instante, primera_activacion_en: Instante|null, activacion_hipotetica_en: Instante|null, politica_operativa_id: UUID|null, politica_operativa_version: Entero|null, politica_adopcion_id: UUID|null, filas: Estado[]}`. Primera activación y adopción son null hasta activar. La hipotética solo se rellena en observación antes de activar. En legado anterior a reglas ampliadas, política operativa puede ser null; no se fabrican umbrales.

Cada `Estado` contiene exactamente:

- `lead_id: UUID`.
- `base: EstadoSlaLead|null`: el objeto del contrato v1 existente, sin cambiar sus campos. Null cuando no hay foto; no se fabrica una parcialmente válida.
- `etapa_sla_id: UUID|null`, `ciclo_n: Entero|null`, `asignacion_id: UUID|null`.
- `evaluacion: 'completa'|'parcial'|'no_aplica'` y `motivos_datos: string[]` del catálogo cerrado indicado abajo.
- `seguimiento: {referencia_en: Instante|null, ultima_gestion_en: Instante|null, ultima_gestion_tipo: TipoGestion|null, autor_id: UUID|null, autor_nombre: string|null, umbral_minutos: Entero|null, limite_en: Instante|null, vencido: boolean|null, accion_pendiente: boolean|null}`.
- `compromiso: {tarea: TareaCompromiso|null, validez: 'valido'|'sin_tarea'|'datos_incompletos'|'reprogramaciones_agotadas'|'deshabilitado'|'no_aplica', hasta_en: Instante|null, cobertura_activa: boolean|null}`.
- `etapa: {limite_original_en: Instante|null, limite_prorrogado_en: Instante|null, minutos_prorrogados: Entero|null, prorrogas_usadas: Entero|null, prorrogas_restantes: Entero|null, politica_prorroga_id: UUID|null, politica_techo_id: UUID|null, techo_origen: 'episodio'|'adopcion'|null, techo_en: Instante|null, limite_operativo_en: Instante|null, fuera_plazo: boolean|null, episodios_en_ciclo: Entero|null, revision_requerida: boolean|null, motivos_revision: MotivoRevision[]}`.

`TipoGestion`: los cinco tipos de gestión del plan. `TareaCompromiso`: `{id: UUID, lead_id: UUID, tipo: 'llamada'|'whatsapp'|'reunion', titulo: string, vence_en: Instante, reprogramaciones: Entero, responsable_id: UUID|null, autor_id: UUID|null, autor_nombre: string|null, contexto_fuente: 'evento'|'reconstruido'}`. No incluye una marca «heredada» deducida de la autoría. El detalle completo se recupera por ID dentro del ámbito.

Catálogo `motivos_datos`: `sin_foto_sla`, `sin_asignacion`, `sin_episodio_etapa`, `asignacion_sla_incoherente`, `etapa_sla_incoherente`, `referencia_gestion_invalida`, `operacion_no_activada`, `contexto_tarea_ambiguo`, `tarea_ciclo_anterior_pendiente`, `tenencia_tarea_incoherente`, `fecha_tarea_invalida`, `politica_operativa_ausente`, `restriccion_contacto`, `lead_terminal`, `lead_inactivo`. Se devuelve la razón solo para un sujeto visible. `MotivoRevision`: `limite_operativo_agotado`, `reprogramaciones_agotadas`, `reingreso_etapa`.

Booleanos: `false` es una evaluación negativa con datos suficientes; `null` significa no evaluable/no aplicable. Nunca convertir null en «al día». Si no existe ninguna tarea y el conjunto es completo, `validez='sin_tarea'` y cobertura false; si existe una tarea ambigua que podría gobernar el compromiso, validez datos_incompletos y cobertura null. Para priorizar, solo una cobertura true suspende seguimiento; si hay incertidumbre se conserva la acción conocida y se muestra el motivo de dato incompleto. En el pipeline, falta de foto elimina el color SLA, no la agenda.

**2. Cola y agenda**

Firma única (sin overload): `crm.cola_accion_v2_fn(p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas', p_etapa text DEFAULT null, p_analista_id uuid DEFAULT null, p_cursor jsonb DEFAULT null) RETURNS jsonb`. Límite 1–200; UI inicia en 10 y ofrece 10/25/50 con Anterior/Siguiente, sin scroll infinito.

Filtros: `p_senal` es `todas`, `primera_atencion`, `tareas_vencidas`, `seguimientos_pendientes`, `revisiones`, `datos_incompletos` o `por_repartir`. Etapa es una de las cuatro etapas abiertas o null; analista es UUID o null (todos los visibles). Se intersectan con el ámbito resuelto por la ventana; un analista ajeno da cero filas. La señal explícita selecciona su booleano independiente de la acción dominante: las revisiones no requieren `bucket='revision_comercial'`.

Envelope: `{version: 2, modo, control_revision, calculado_en, politica_operativa_id, politica_operativa_version, total_items: Entero, hay_mas: boolean, totales: Totales, items: Item[], filtros: {senal, etapa, analista_id}, limite: Entero, rango: {desde: Entero, hasta: Entero}, cursor_siguiente: Cursor|null}`. `rango` es 0/0 para página vacía; en las restantes informa posiciones 1-based dentro de los filtros. `total_items` cuenta el conjunto filtrado antes del cursor. `hay_mas` indica que quedan resultados posteriores a la página, no que el total supera siempre el límite.

`totales` y `senales` tienen las seis claves `primera_atencion`, `tareas_vencidas`, `seguimientos_pendientes`, `revisiones`, `datos_incompletos`, `por_repartir`: enteros no negativos en totales y booleanos en señales. Los totales se calculan sobre todo el ámbito después de etapa/analista, antes de seleccionar una señal o aplicar cursor/límite. Son conjuntos de leads que pueden solaparse; no se suman como personas distintas. Tareas vencidas cuenta leads con alguna tarea vencida; el total de agenda cuenta tareas.

Item: `{lead_id: UUID, bucket: 'por_repartir'|'primera_atencion'|'tarea_vencida'|'tarea_hoy'|'seguimiento'|'revision_comercial'|'proxima_tarea'|'datos_incompletos', severidad: 'critica'|'media'|'baja', prioridad: Entero, referencia_en: Instante|null, tarea_id: UUID|null, estado: Estado, lead: {id: UUID, nombre_completo: string, etapa: string, analista_id: UUID|null, analista_nombre: string|null}, senales: Senales}`. Nombres y responsable vienen del proveedor autorizado, no de consultas crudas del adaptador. La cola `todas` mantiene la acción de atención o supervisión según capacidad. La consulta explícita de una señal permite inspeccionar también una revisión sin acción propia de atención; no concede ninguna capacidad de escritura.

Orden total: prioridad ascendente, referencia más antigua (null al final), UUID. `Cursor` es opaco para la UI: `{version: 1, contexto: string, prioridad: Entero, referencia_en: Instante|null, lead_id: UUID}`. Se devuelve únicamente cuando existe página siguiente; no se construye en el navegador. Valida forma exacta, versión, tipos y finitud. Su contexto incluye actor/rol/ámbito, filtros, límite, modo, revisión y política. Cambiarlos exige reiniciar; un cursor incompatible devuelve SQLSTATE 22023 con «Cursor incompatible; reinicia la paginacion». No permite elegir reloj ni ampliar autorización. La UI guarda los cursores de páginas previas para Anterior; resetear historial al cambiar filtros, usuario, configuración o tras una mutación.

Cada consulta usa el reloj y los hechos actuales del servidor. Con datos y fronteras temporales estables, el recorrido no duplica ni omite leads; varias páginas no son un snapshot transaccional común. Cambios en datos/tiempo pueden mover posiciones: ofrecer actualizar y reiniciar, conservando el instante de lectura visible. El estado v2 no expone el token interno del ámbito y v1 conserva su contrato.

Agenda mantiene su consulta y ámbito actuales. Integra los comandos confirmados del apartado 4 para tareas de lead; postventa conserva sus puertas existentes. Esta entrega no crea otra RPC de lectura de agenda. La paginación nueva corresponde a la cola operativa y al panel de confirmaciones pendientes, este último con páginas de cinco.

Una lectura directa de detalle por ID usa el selector existente y su ámbito, sin límite global; tarea ya cerrada/ya fuera de ámbito produce refresco y mensaje, nunca acceso ampliado.

**3. Configuración y publicación**

`crm.configuracion_sla_v2_fn() RETURNS jsonb` devuelve `{version: 2, puede_editar: boolean, expected_version: Entero, vigente: PoliticaV2, ultima_publicada: PoliticaV2, control: {modo, revision, primera_activacion_en, politica_adopcion_id}, inicializacion_aprobada: {disponible: boolean, motivo: 'politica_futura'|'ya_publicadas'|'sin_permiso'|null, config: ConfigSlaV2}}`. Control usa los tipos del estado. `PoliticaV2` contiene `base: PoliticaSla` del contrato actual y `operacion: ReglaOperacion[]|null`. Null significa versión histórica sin anexo, nunca arreglo parcial de una o dos etapas. Última publicada y vigente se distinguen incluso cuando hay una programación futura. `ConfigSlaV2` tiene la forma de `p_config` descrita abajo y sirve el resumen comercial sin replicar reglas en el navegador.

`ReglaOperacion`: `{etapa: EtapaActiva, seguimiento_minutos: Entero, prorroga_minutos: Entero, prorroga_max: Entero, tope_extra_minutos: Entero, pausa_habilitada: boolean, pausa_margen_minutos: Entero}`. Exactamente cuatro etapas únicas; rangos y relaciones según SLA-R2.

Firma: `crm.publicar_politica_sla_v2(p_expected_version integer, p_vigente_desde timestamptz, p_config jsonb) RETURNS jsonb`.

`p_config` contiene exactamente los campos base `zona_horaria`, `tipo_reloj`, `primera_gestion_minutos`, `primer_contacto_minutos` y `etapas`. Cada elemento de `etapas` tiene `etapa`, `maximo_minutos` y los seis campos operativos. Respuesta: `{version: 2, politica: PoliticaV2, expected_version: Entero}` con la política recién publicada y expected_version igual a su versión. `p_vigente_desde=null` significa ahora como en la puerta actual; si existe una publicación futura, se rechaza un orden de vigencias inválido. Los nuevos schemas no confunden la versión del envelope con la versión de política.

La inicialización usa `crm.publicar_reglas_sla_aprobadas_v2(p_expected_version integer) RETURNS jsonb`, solo para Gerencia activa y cuando la última política vigente carece de anexo. Publica los plazos aprobados del proveedor privado único `private.sla_config_inicial_aprobada`, preservando primera gestión y primer contacto de la vigente. Devuelve el mismo envelope de publicación v2. Rechaza publicación futura o reinicialización (`22023`); un conflicto de versión usa `P0409`. Comparte el candado y publicador atómico con v1/v2. No activa. La puerta v1 mantiene firma/retorno y hereda el anexo de la versión anterior al publicar otra política.

`crm.cambiar_modo_sla_operacion(p_expected_revision integer, p_modo text)` devuelve `{version: 2, modo, revision, primera_activacion_en, politica_adopcion_id}` después del commit. La nueva revisión aumenta exactamente en uno por cambio efectivo; repetir misma petición con revisión anterior produce conflicto, y el cliente lee control para confirmar el resultado antes de enviar otra. Una solicitud para el mismo modo con revisión vigente no modifica el primer instante ni la política de adopción.

Publicación y modo requieren Gerencia activa. El conflicto de revisión/versión es **`P0409`**; no se usa `40001` para estos comandos porque PostgREST puede reintentarlo durante un periodo prolongado. El cliente relee y permite revisar, sin reemplazar silenciosamente la revisión esperada. Entrar en observación/activo exige una política completa y los hooks del núcleo presentes; primera activación y política de adopción son inmutables incluso tras volver a legado.

**4. Gestión confirmada**

Firmas nuevas, limitadas a gestiones de lead:

```text
registrar_actividad_v2(p_operacion_id uuid, p_lead_id uuid, p_tipo text,
                      p_detalle text DEFAULT null, p_siguiente jsonb DEFAULT null)
cerrar_tarea_v2(p_operacion_id uuid, p_tarea_id uuid, p_estado text,
               p_resultado_tipo text DEFAULT null, p_resultado_detalle text DEFAULT null,
               p_siguiente jsonb DEFAULT null, p_resultado_reunion text DEFAULT null,
               p_motivo_no_realizada text DEFAULT null)
cerrar_reunion_v2(p_operacion_id uuid, p_tarea_id uuid, p_estado text,
                 p_resultado_reunion text DEFAULT null, p_motivo_no_realizada text DEFAULT null,
                 p_detalle text DEFAULT null, p_siguiente jsonb DEFAULT null)
reprogramar_reunion_v2(p_operacion_id uuid, p_tarea_id uuid,
                      p_vence_en timestamptz, p_nueva_id uuid DEFAULT null)
reprogramar_tarea_v2(p_operacion_id uuid, p_tarea_id uuid, p_vence_en timestamptz)
```

Todas en `crm`, RETURNS jsonb. Autorización: actor activo vendedor/supervisor/Gerencia, lead activo dentro de su ámbito; se revalida después de esperar y bajo su lock. Una confirmación anterior solo se devuelve si el sujeto sigue autorizado. Directorio y lectores globales no adquieren permiso de escritura. `reprogramar_tarea_v2` se limita a tareas pendientes que no son reuniones; cambia fecha y deja que el núcleo existente contabilice la reprogramación. Las reuniones conservan el historial de tarea anterior/nueva.

`registrar_actividad_v2` acepta los cinco tipos de gestión o nota, nunca eventos de sistema; autor y fecha provienen del servidor. `p_siguiente` usa el contrato del writer actual `private.crear_siguiente_tarea`: actividad y siguiente tarea pertenecen a una sola transacción. Si la siguiente tarea abre otra etapa, no se concede prórroga al episodio anterior. El ID de la actividad es `p_operacion_id`. El cliente conserva los IDs enviados, incluido `p_nueva_id` o el ID de siguiente tarea, al recuperar un envío.

El servidor conserva JSONB con el comando, sujeto y parámetros normalizados de la puerta (defaults/nulls, detalle recortado y fecha tipada). No usa un hash como único criterio: compara el payload guardado. La estructura de negocio de `p_siguiente` debe conservarse idéntica al reintentar.

Respuesta plana común: `{version: 2, ok: true, operacion_id: UUID, lead_id: UUID, comando: 'registrar_actividad'|'cerrar_tarea'|'cerrar_reunion'|'reprogramar_reunion'|'reprogramar_tarea', ...resultado}`. Campos adicionales según comando:

| Comando | Campos de resultado |
|---|---|
| `registrar_actividad` | `actividad_id`, `creado_en`, `etapa`, `siguiente_id` (nullable) |
| `cerrar_tarea` | `tarea_id`, `actividad_id`, `actividad_cliente_id`, `siguiente_id`, `retroceso`; los no aplicables son null |
| `cerrar_reunion` | `tarea_id`, `actividad_id`, `siguiente_id`, `retroceso`; los no aplicables son null |
| `reprogramar_reunion` | `tarea_anterior_id`, `tarea_nueva_id`, `reprogramaciones` |
| `reprogramar_tarea` | `tarea_id` |

`crm.sla_operacion_recibos` es privada, con PK `(actor_id,operacion_id)`. Guarda payload, respuesta y `confirmado_en`; este último no es un campo del envelope público. Reserva, efectos y confirmación ocurren en la misma transacción; una restricción diferida impide confirmar una fila sin respuesta. Sus FKs son diferidas para evitar locks implícitos sobre el lead antes de reservar la operación. Respuesta confirmada y registros son inmutables. Un reintento autorizado devuelve exactamente la respuesta original, incluida su etapa/fecha original, sin ejecutar otra gestión.

No se anuncia éxito hasta validar la respuesta del servidor. Errores: `42501` autorización, `22023` contrato inválido, `P0409` conflicto operativo, `23505` operación reutilizada con otro payload o colisión de identidad. Las puertas heredadas conservan sus demás códigos; `23505` no se transforma automáticamente en éxito. En legado, los nuevos comandos siguen confirmando gestiones y no conceden ajustes.

**5. Recuperación explícita**

Antes de enviar, la UI guarda operación y payload en `sessionStorage`, particionados por actor y sujeto. Una respuesta de red perdida conserva esa intención incluso tras recargar la pestaña. El panel de confirmaciones pendientes permite reenviar el mismo comando con su UUID y argumentos originales; mientras esté pendiente impide reemplazarlo por otro payload. El servidor resuelve si debe ejecutar o devolver el recibo previo. Un fallo confirmado de SQL revierte esa transacción; una respuesta de transporte incierta no demuestra que no ocurrió. El almacenamiento de la pestaña no es un registro permanente: cerrar sesión/cuenta lo limpia y, si se pierde, se debe revisar historial antes de registrar nuevamente.

La recuperación operativa del módulo empieza por volver a legado con revisión vigente y, si procede, restaurar el ZIP frontend anterior. El control espera los ajustes ya admitidos; al confirmar legado no entran ajustes nuevos hasta reactivar expresamente. Conserva primera activación, política adoptada y presupuesto consumido.

Si se retiran hooks mediante la contingencia `rollback-sla-operacion-hooks.sql`, el gate impide entrar otra vez en observación/activo. Se conservan firmas de N3/v1, autorización, locks y avance automático. La recuperación requiere reinstalación revisada y reconstrucción/verificación del intervalo sin captura; nunca borrar contextos/ajustes/recibos ni reiniciar la primera activación. La reversa del prerrequisito de gobernanza pertenece a una reversa completa separada y devuelve sus controles rojos previos.
