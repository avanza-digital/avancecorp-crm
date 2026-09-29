import * as v from 'valibot'
import type { Rol } from './roles'

const fecha = v.nullable(v.string())
const indicador = v.nullable(v.boolean())
const numero = v.nullable(v.number())
const tarea = v.nullable(v.object({ id: v.string(), tipo: v.string(), vence_en: v.string(), reprogramaciones: v.number() }))
export const TipoAvisoSlaSchema = v.picklist(['primera_atencion', 'tarea_vencida', 'seguimiento', 'revision_comercial', 'datos_incompletos', 'por_repartir'])
export const AvisoSlaSchema = v.object({ id: v.string(), bucket: TipoAvisoSlaSchema, severidad: v.picklist(['critica', 'media']),
  referencia_en: fecha, tarea_id: v.nullable(v.string()) })
export type AvisoSla = v.InferOutput<typeof AvisoSlaSchema>
export const EstadoSlaV2Schema = v.pipe(v.object({
  lead_id: v.string(), evaluacion: v.picklist(['completa', 'parcial', 'no_aplica']), motivos_datos: v.array(v.string()),
  avisos: v.array(AvisoSlaSchema),
  avisos_mostrados: v.optional(v.array(AvisoSlaSchema)),
  operacion: v.optional(v.object({ modelo: v.literal(3), aviso_principal: v.nullable(AvisoSlaSchema),
    proxima_accion: v.nullable(v.object({ id: v.string(), tipo: v.string(), titulo: v.string(), vence_en: v.string() })),
    proximo_cambio_en: fecha })),
  seguimiento: v.object({ referencia_en: fecha, ultima_gestion_en: fecha, limite_en: fecha, vencido: indicador, accion_pendiente: indicador }),
  compromiso: v.object({ tarea, validez: v.string(), hasta_en: fecha, cobertura_activa: indicador }),
  etapa: v.object({ limite_original_en: fecha, limite_prorrogado_en: fecha, limite_operativo_en: fecha, techo_en: fecha,
    prorrogas_usadas: numero, prorrogas_restantes: numero, revision_requerida: indicador, motivos_revision: v.array(v.string()) }),
}), v.check((estado) => !estado.operacion || (estado.avisos_mostrados !== undefined
  && estado.avisos_mostrados.every((aviso) => estado.avisos.some((causa) => causa.id === aviso.id)))))
export type EstadoSlaV2 = v.InferOutput<typeof EstadoSlaV2Schema>
export const ModoSlaSchema = v.picklist(['legado', 'observacion', 'activo'])
const sobre = { modelo_avisos: v.optional(v.literal(3)), proximo_cambio_en: v.optional(fecha), version: v.literal(2), modo: ModoSlaSchema, control_revision: v.number(), calculado_en: v.string() }
export const EstadosSlaV2Schema = v.object({ ...sobre, filas: v.array(EstadoSlaV2Schema) })
const conteo = v.pipe(v.number(), v.integer(), v.minValue(0))
export const ResumenAvisosSlaSchema = v.pipe(v.object({ ...sobre,
  total_oportunidades: conteo, total_avisos: conteo, criticas: conteo,
  grupos: v.pipe(v.array(v.object({ bucket: TipoAvisoSlaSchema, total: v.pipe(conteo, v.minValue(1)) })), v.maxLength(6)),
}), v.check((r) => r.total_oportunidades <= r.total_avisos && r.criticas <= r.total_avisos
  && r.grupos.reduce((total, g) => total + g.total, 0) === r.total_avisos
  && new Set(r.grupos.map((g) => g.bucket)).size === r.grupos.length
  && (r.total_oportunidades > 0 || r.total_avisos === 0)))
export type ResumenAvisosSla = v.InferOutput<typeof ResumenAvisosSlaSchema>
export const SENALES_SLA = [
  ['pendientes', 'Para atender ahora'], ['todas', 'Todas las acciones'], ['primera_atencion', 'Primera atención'], ['tareas_vencidas', 'Tareas vencidas'],
  ['seguimientos_pendientes', 'Seguimiento pendiente'], ['revisiones', 'Revisión comercial'],
  ['datos_incompletos', 'Datos incompletos'], ['por_repartir', 'Por repartir'],
] as const
export type SenalSla = typeof SENALES_SLA[number][0]
export type FiltrosSla = { senal: SenalSla; etapa: string | null; analista_id: string | null }
export type CursorSla = Record<string, unknown>
const senales = v.object({ pendientes: v.boolean(), primera_atencion: v.boolean(), tareas_vencidas: v.boolean(), seguimientos_pendientes: v.boolean(),
  revisiones: v.boolean(), datos_incompletos: v.boolean(), por_repartir: v.boolean() })
const cursor = v.nullable(v.record(v.string(), v.unknown()))
const paginacion = {
  filtros: v.object({ senal: v.string(), etapa: v.nullable(v.string()), analista_id: v.nullable(v.string()) }),
  limite: v.number(), total_items: v.number(), hay_mas: v.boolean(), cursor_siguiente: cursor,
  rango: v.object({ desde: v.number(), hasta: v.number() }),
}
const totalesSenales = { pendientes: v.number(), primera_atencion: v.number(), tareas_vencidas: v.number(), seguimientos_pendientes: v.number(), revisiones: v.number(), datos_incompletos: v.number(), por_repartir: v.number() }
const itemLead = {
  lead_id: v.string(), bucket: v.string(), severidad: v.picklist(['critica', 'media', 'baja']),
  prioridad: v.number(), referencia_en: fecha, tarea_id: v.nullable(v.string()),
  lead: v.object({ id: v.string(), nombre_completo: v.string(), etapa: v.string(), analista_id: v.nullable(v.string()), analista_nombre: v.nullable(v.string()) }),
  senales, estado: EstadoSlaV2Schema,
}
export const ColaSlaPaginaSchema = v.object({ ...sobre, ...paginacion,
  totales: v.object(totalesSenales),
  items: v.array(v.object(itemLead)),
})
export type ColaSlaPagina = v.InferOutput<typeof ColaSlaPaginaSchema>

// ── Cola del DÍA v3 (`crm.cola_accion_v3_fn`, migración 20260929004455) ──────
// Una sola cola con los leads de la ventana SLA (idénticos a la v2) y las
// tareas de CLIENTES del día (vencidas o de hoy). Cada ítem lleva su identidad
// TIPADA en `clave` (`lead:<uuid>` | `tarea:<uuid>`): un cliente con dos tareas
// son dos filas. Los ítems de cliente no traen teléfono ni lead ni estado SLA.
// El contrato se comprueba entero: si la forma no cuadra, la cola no se pinta.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
export const ItemColaDiaLeadSchema = v.pipe(v.object({ ...itemLead,
  clave: v.string(),
  sujeto: v.object({ tipo: v.literal('lead'), id: v.string(), nombre: v.string() }),
}), v.check((i) => i.clave === `lead:${i.lead_id}` && i.lead.id === i.lead_id && i.sujeto.id === i.lead_id,
  'El ítem de lead no corresponde a su clave'))
export const ItemColaDiaClienteSchema = v.pipe(v.object({
  clave: v.string(), tarea_id: v.pipe(v.string(), v.regex(UUID)),
  lead_id: v.null(), lead: v.null(), estado: v.null(),
  bucket: v.picklist(['tarea_vencida', 'tarea_hoy']), severidad: v.picklist(['critica', 'media']),
  prioridad: v.picklist([20, 30]), referencia_en: v.string(), senales,
  sujeto: v.object({ tipo: v.literal('cliente'), perfil_id: v.nullable(v.string()), inversionista_id: v.nullable(v.string()), nombre: v.string() }),
}), v.check((i) => i.clave === `tarea:${i.tarea_id}`
  // Un solo sujeto (CHECK tareas_un_solo_sujeto) y el bucket, la severidad, la
  // prioridad y las señales cuentan lo mismo: vencida = crítica = pendiente.
  && (i.sujeto.perfil_id === null) !== (i.sujeto.inversionista_id === null)
  && (i.bucket === 'tarea_vencida') === (i.severidad === 'critica')
  && (i.bucket === 'tarea_vencida') === (i.prioridad === 20)
  && i.senales.pendientes === (i.bucket === 'tarea_vencida') && i.senales.tareas_vencidas === i.senales.pendientes
  && Number.isFinite(Date.parse(i.referencia_en)), 'El ítem de cliente no es coherente'))
export const ItemColaDiaSchema = v.union([ItemColaDiaLeadSchema, ItemColaDiaClienteSchema])
export const ColaDiaPaginaSchema = v.pipe(v.object({ ...sobre, ...paginacion, version: v.literal(3),
  totales: v.object({ ...totalesSenales, clientes: v.pipe(v.number(), v.integer(), v.minValue(0)) }),
  items: v.array(ItemColaDiaSchema),
}), v.check((p) => new Set(p.items.map((i) => i.clave)).size === p.items.length, 'La cola trae claves repetidas'))
export type ColaDiaPagina = v.InferOutput<typeof ColaDiaPaginaSchema>
export type ItemColaDia = ColaDiaPagina['items'][number]
export type ItemColaDiaCliente = v.InferOutput<typeof ItemColaDiaClienteSchema>
/**
 * La acción de una tarea de CLIENTE en las colas (v3). Vale para cualquier rol:
 * un cliente no tiene lead, etapa ni analista en el payload, así que la fila
 * dice qué es y cuándo, sin fingir un dueño.
 */
export const ACCIONES_CLIENTE_SLA: Record<ItemColaDiaCliente['bucket'], string> = {
  tarea_vencida: 'Gestión con cliente vencida',
  tarea_hoy: 'Gestión con cliente para hoy',
}
/**
 * El id con el que se abre la ficha de un cliente de la cola: el inversionista
 * que trae la COLA, que es fresco (se relee cada minuto). No se prefiere una
 * canónica guardada en el store: podría ser vieja (Codex, 29/09/2026), y la
 * ficha ya resuelve la canónica y el ámbito en el servidor. Un cliente solo del
 * portal (sin inversionista) no tiene ficha: null, y la fila no ofrece abrirla.
 */
export function idFichaCliente(item: Pick<ItemColaDiaCliente, 'sujeto'>): string | null {
  return item.sujeto.inversionista_id
}
export const ACCIONES_SLA: Record<string, string> = {
  primera_atencion: 'Contactar al cliente', tarea_vencida: 'Revisar actividad pendiente', tarea_hoy: 'Actividad de hoy',
  seguimiento: 'Retomar el contacto', revision_comercial: 'Definir el siguiente paso', datos_incompletos: 'Revisar datos',
  proxima_tarea: 'Próxima tarea', por_repartir: 'Asignar analista',
}
/**
 * La gestión manual desde la ficha pertenece al analista asignado. Supervisión
 * y Gerencia revisan el seguimiento, pero no deben registrar una actividad como
 * si la hubieran realizado ellas. Es una regla de interfaz, no autorización.
 */
export function puedeRegistrarGestionSla(rol: Rol | null | undefined): boolean {
  return rol === 'vendedor'
}

// Solo presentación: el servidor decide qué avisos corresponden al actor y cuándo.
// `boton: null` hace inseparables el texto de revisión de supervisión y la
// ausencia de una acción que fingiría una gestión del analista.
export function textoAvisoSla(aviso: AvisoSla, supervision: boolean, modelo?: number) {
  if (modelo === 3 && aviso.bucket === 'primera_atencion') return {
    titulo: supervision ? 'Revisa la primera gestión con el analista' : 'Realiza el primer intento y registra el resultado', boton: supervision ? null : 'Registrar gestión',
  }
  if (modelo === 3 && aviso.bucket === 'seguimiento') return {
    titulo: supervision ? 'Revisa el seguimiento con el analista' : 'Retoma el seguimiento', boton: supervision ? null : 'Registrar gestión',
  }
  switch (aviso.bucket) {
    case 'tarea_vencida': return { titulo: 'Revisa la actividad pendiente', boton: 'Revisar actividad' }
    case 'primera_atencion': return { titulo: supervision ? 'Revisa el contacto inicial con el cliente' : 'Contacta al cliente y registra el resultado', boton: supervision ? null : 'Registrar gestión' }
    case 'seguimiento': return { titulo: supervision ? 'Revisa el seguimiento con el analista' : 'Retoma el contacto y registra el resultado', boton: supervision ? null : 'Registrar gestión' }
    case 'revision_comercial': return { titulo: 'Revisa el caso y define el siguiente paso', boton: 'Revisar caso' }
    case 'por_repartir': return { titulo: 'Asigna un analista a esta oportunidad', boton: 'Ver asignación' }
    case 'datos_incompletos': return { titulo: supervision ? 'Revisa los datos de esta oportunidad' : 'Pide al supervisor revisar los datos', boton: 'Ver datos' }
  }
}
export const MOTIVOS_REVISION_SLA: Record<string, string> = {
  limite_operativo_agotado: 'Se venció el plazo de esta etapa',
  reprogramaciones_agotadas: 'La actividad se reprogramó tres veces o más',
  reingreso_etapa: 'La oportunidad ingresó a esta etapa tres veces o más en este proceso comercial',
}
export function fechaSla(valor: string | null, formato: 'breve' | 'completa' = 'breve'): string {
  if (!valor || !Number.isFinite(Date.parse(valor))) return 'Sin fecha confirmada'
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima', day: formato === 'completa' ? 'numeric' : '2-digit',
    month: formato === 'completa' ? 'long' : 'short', ...(formato === 'completa' ? { year: 'numeric' as const } : {}),
    hour: '2-digit', minute: '2-digit',
  }).format(new Date(valor))
}

const reglaOperacion = v.object({ etapa: v.picklist(['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']),
  seguimiento_minutos: v.number(), prorroga_minutos: v.number(), prorroga_max: v.number(),
  tope_extra_minutos: v.number(), pausa_habilitada: v.boolean(), pausa_margen_minutos: v.number() })
const politicaOperacion = v.object({ base: v.object({ version: v.number() }), operacion: v.nullable(v.pipe(v.array(reglaOperacion), v.length(4), v.check((reglas) => new Set(reglas.map((r) => r.etapa)).size === 4))) })
export const ControlSlaSchema = v.object({ modo: ModoSlaSchema, revision: v.number(), primera_activacion_en: fecha, politica_adopcion_id: v.nullable(v.string()) })
export const ConfiguracionSlaV2Schema = v.object({ version: v.literal(2), puede_editar: v.boolean(), expected_version: v.number(),
  vigente: politicaOperacion, ultima_publicada: politicaOperacion, control: ControlSlaSchema,
  inicializacion_aprobada: v.optional(v.object({ disponible: v.boolean(), motivo: v.nullable(v.string()),
    config: v.object({ zona_horaria: v.string(), tipo_reloj: v.string(), primera_gestion_minutos: v.number(), primer_contacto_minutos: v.number(),
      etapas: v.pipe(v.array(v.object({ ...reglaOperacion.entries, maximo_minutos: v.number() })), v.length(4), v.check((reglas) => new Set(reglas.map((r) => r.etapa)).size === 4)),
    }),
  })),
})
export const ResultadoModoSlaSchema = v.object({ version: v.literal(2), ...ControlSlaSchema.entries })
export const ResultadoPublicacionSlaV2Schema = v.object({ version: v.literal(2), politica: politicaOperacion, expected_version: v.number() })
