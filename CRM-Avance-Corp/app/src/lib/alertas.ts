import {
  colaDe,
  esAbierto,
  sinProximaAccion,
  type ItemCola,
} from './inteligencia'
import { planPorLead } from './plan-lead'
import type { Vista } from './router'
import type { EstadoSlaLead } from './sla-versionado'
import type { Actividad, Lead, Miembro, Tarea } from './tipos'

export type SeveridadAlerta = 'critica' | 'atencion'
export type AlcanceAlerta = 'personal' | 'equipo' | 'empresa'

export type TipoAlerta =
  | 'tarea_vencida'
  | 'lead_sin_responder'
  | 'sin_proxima_accion'
  | 'por_repartir'
  | 'bajo_meta_conversion'
  | 'caida_conversion'

export interface DestinoAlerta {
  vista: Vista
  leadId?: string | null
  etiqueta: string
}

export interface AlertaCRM {
  id: string
  tipo: TipoAlerta
  severidad: SeveridadAlerta
  alcance: AlcanceAlerta
  titulo: string
  detalle: string
  responsableId: string | null
  responsable: string | null
  valor: number | null
  destino: DestinoAlerta
}

export interface DerivarAlertasVendedorInput {
  vendedorId: string
  leads: readonly Lead[]
  actividades: readonly Actividad[]
  tareas: readonly Tarea[]
  ahora: number
  estadosSla?: ReadonlyMap<string, EstadoSlaLead>
}

export interface DerivarAlertasSupervisorInput {
  supervisorId: string
  leads: readonly Lead[]
  actividades: readonly Actividad[]
  tareas: readonly Tarea[]
  vendedores: readonly Miembro[]
  ahora: number
  estadosSla?: ReadonlyMap<string, EstadoSlaLead>
}

const HORA_MS = 3_600_000

const PESO_SEVERIDAD: Record<SeveridadAlerta, number> = {
  critica: 0,
  atencion: 1,
}

const PESO_TIPO: Record<TipoAlerta, number> = {
  por_repartir: 0,
  tarea_vencida: 1,
  lead_sin_responder: 2,
  sin_proxima_accion: 3,
  bajo_meta_conversion: 4,
  caida_conversion: 5,
}

function instanteConfiable(valor: string | null | undefined, ahora: number): boolean {
  if (valor == null) return true
  const ms = Date.parse(valor)
  return Number.isFinite(ms) && ms <= ahora
}

/**
 * Las alertas de tiempo nunca adivinan antigüedad. Una fecha base corrupta o
 * futura saca al lead de esta derivación hasta que la fuente vuelva a ser
 * consistente; un dato inválido no se transforma en una urgencia inventada.
 */
function leadConTiempoConfiable(lead: Lead, ahora: number): boolean {
  return instanteConfiable(lead.creado_en, ahora)
    && instanteConfiable(lead.tenencia_desde, ahora)
}

function nombreResponsable(
  lead: Lead,
  nombrePorId?: ReadonlyMap<string, string>,
): string | null {
  if (!lead.vendedor_id) return null
  return nombrePorId?.get(lead.vendedor_id) ?? lead.vendedor_nombre ?? null
}

function horasVencida(tarea: Tarea, ahora: number): number | null {
  if (tarea.estado !== 'pendiente' || !tarea.activo) return null
  const vence = Date.parse(tarea.vence_en)
  if (!Number.isFinite(vence) || vence >= ahora) return null
  return (ahora - vence) / HORA_MS
}

function textoRetraso(horas: number): string {
  if (horas < 1) return 'hace menos de una hora'
  if (horas < 24) {
    const n = Math.floor(horas)
    return n === 1 ? 'hace 1 hora' : `hace ${n} horas`
  }
  const dias = Math.floor(horas / 24)
  return dias === 1 ? 'hace 1 día' : `hace ${dias} días`
}

interface TareaVencidaElegida {
  tarea: Tarea
  horas: number
}

/** Una sola vencida por lead: gana la más antigua y el id rompe empates. */
function tareasVencidasPorLead(
  tareas: readonly Tarea[],
  idsLead: ReadonlySet<string>,
  ahora: number,
): Map<string, TareaVencidaElegida> {
  const resultado = new Map<string, TareaVencidaElegida>()
  for (const tarea of tareas) {
    const leadId = tarea.lead_id
    if (!leadId || !idsLead.has(leadId)) continue
    const horas = horasVencida(tarea, ahora)
    if (horas == null) continue

    const anterior = resultado.get(leadId)
    if (
      !anterior
      || horas > anterior.horas
      || (horas === anterior.horas && tarea.id.localeCompare(anterior.tarea.id) < 0)
    ) {
      resultado.set(leadId, { tarea, horas })
    }
  }
  return resultado
}

function alertaTareaVencida(
  lead: Lead,
  elegida: TareaVencidaElegida,
  alcance: Extract<AlcanceAlerta, 'personal' | 'equipo'>,
  responsable: string | null,
): AlertaCRM {
  return {
    id: `tarea_vencida:${lead.id}`,
    tipo: 'tarea_vencida',
    severidad: elegida.horas >= 24 ? 'critica' : 'atencion',
    alcance,
    titulo: 'Tarea vencida',
    detalle: `«${elegida.tarea.titulo}» venció ${textoRetraso(elegida.horas)}.`,
    responsableId: lead.vendedor_id ?? null,
    responsable,
    valor: Math.round(elegida.horas * 10) / 10,
    destino: {
      vista: 'agenda',
      leadId: lead.id,
      etiqueta: 'Abrir en Agenda',
    },
  }
}

function alertaDesdeCola(
  item: ItemCola,
  alcance: Extract<AlcanceAlerta, 'personal' | 'equipo'>,
  responsable: string | null,
): AlertaCRM {
  const sinResponder = item.bucket === 'sin_responder'
  return {
    id: `${sinResponder ? 'lead_sin_responder' : 'sin_proxima_accion'}:${item.lead.id}`,
    tipo: sinResponder ? 'lead_sin_responder' : 'sin_proxima_accion',
    severidad: item.sev === 'critica' ? 'critica' : 'atencion',
    alcance,
    titulo: sinResponder ? 'Lead sin responder' : 'Lead requiere una acción',
    detalle: item.motivo,
    responsableId: item.lead.vendedor_id ?? null,
    responsable,
    valor: Math.round(item.dias * 10) / 10,
    destino: {
      vista: 'cartera',
      leadId: item.lead.id,
      etiqueta: 'Abrir lead',
    },
  }
}

function alertaSinProximaAccion(
  lead: Lead,
  alcance: Extract<AlcanceAlerta, 'personal' | 'equipo'>,
  responsable: string | null,
): AlertaCRM {
  return {
    id: `sin_proxima_accion:${lead.id}`,
    tipo: 'sin_proxima_accion',
    severidad: 'atencion',
    alcance,
    titulo: 'Lead sin próxima acción',
    detalle: `${lead.nombre_completo} no tiene una tarea pendiente.`,
    responsableId: lead.vendedor_id ?? null,
    responsable,
    valor: 1,
    destino: {
      vista: 'cartera',
      leadId: lead.id,
      etiqueta: 'Abrir lead',
    },
  }
}

function ordenarAlertas(alertas: AlertaCRM[]): AlertaCRM[] {
  return alertas.sort((a, b) => (
    PESO_SEVERIDAD[a.severidad] - PESO_SEVERIDAD[b.severidad]
    || PESO_TIPO[a.tipo] - PESO_TIPO[b.tipo]
    || (a.responsable ?? '').localeCompare(b.responsable ?? '', 'es')
    || a.id.localeCompare(b.id, 'es')
  ))
}

function actividadesDelAmbito(
  actividades: readonly Actividad[],
  idsLead: ReadonlySet<string>,
): Actividad[] {
  return actividades.filter((actividad) => idsLead.has(actividad.lead_id))
}

function idsConActividadInvalida(
  actividades: readonly Actividad[],
  ahora: number,
): Set<string> {
  const ids = new Set<string>()
  for (const actividad of actividades) {
    if (!instanteConfiable(actividad.creado_en, ahora)) ids.add(actividad.lead_id)
  }
  return ids
}

function idsConTareaInvalida(tareas: readonly Tarea[]): Set<string> {
  const ids = new Set<string>()
  for (const tarea of tareas) {
    if (
      tarea.lead_id
      && tarea.estado === 'pendiente'
      && tarea.activo
      && !Number.isFinite(Date.parse(tarea.vence_en))
    ) {
      ids.add(tarea.lead_id)
    }
  }
  return ids
}

export function derivarAlertasVendedor({
  vendedorId,
  leads,
  actividades,
  tareas,
  ahora,
  estadosSla,
}: DerivarAlertasVendedorInput): AlertaCRM[] {
  if (!vendedorId || !Number.isFinite(ahora)) return []

  // Defensa adicional al ámbito del store: jamás confiar en que el caller
  // eliminó los leads de otros vendedores.
  const propios = leads.filter(
    (lead) => lead.vendedor_id === vendedorId && esAbierto(lead),
  )
  const idsPropios = new Set(propios.map((lead) => lead.id))
  const actividadesPropias = actividadesDelAmbito(actividades, idsPropios)
  const tareasPropias = tareas.filter(
    (tarea) => tarea.lead_id != null && idsPropios.has(tarea.lead_id),
  )
  const actividadInvalida = idsConActividadInvalida(actividadesPropias, ahora)
  const tareaInvalida = idsConTareaInvalida(tareasPropias)
  const confiables = propios.filter(
    (lead) => (
      leadConTiempoConfiable(lead, ahora)
      && !actividadInvalida.has(lead.id)
      && !tareaInvalida.has(lead.id)
    ),
  )
  const idsConfiables = new Set(confiables.map((lead) => lead.id))
  const plan = planPorLead(tareasPropias, ahora)
  const vencidas = tareasVencidasPorLead(tareasPropias, idsConfiables, ahora)
  const usadas = new Set<string>()
  const alertas: AlertaCRM[] = []

  for (const lead of confiables) {
    const elegida = vencidas.get(lead.id)
    if (!elegida) continue
    alertas.push(
      alertaTareaVencida(lead, elegida, 'personal', nombreResponsable(lead)),
    )
    usadas.add(lead.id)
  }

  for (const item of colaDe(confiables, actividadesPropias, ahora, plan, estadosSla)) {
    if (usadas.has(item.lead.id) || item.bucket === 'por_repartir') continue
    alertas.push(
      alertaDesdeCola(item, 'personal', nombreResponsable(item.lead)),
    )
    usadas.add(item.lead.id)
  }

  for (const lead of sinProximaAccion(confiables, plan.conTarea)) {
    if (usadas.has(lead.id)) continue
    alertas.push(
      alertaSinProximaAccion(lead, 'personal', nombreResponsable(lead)),
    )
    usadas.add(lead.id)
  }

  return ordenarAlertas(alertas)
}

export function derivarAlertasSupervisor({
  supervisorId,
  leads,
  actividades,
  tareas,
  vendedores,
  ahora,
  estadosSla,
}: DerivarAlertasSupervisorInput): AlertaCRM[] {
  if (!supervisorId || !Number.isFinite(ahora)) return []

  // `vendedores` ya es el roster visible del supervisor. Aun así se toman
  // únicamente vendedores activos y se admite su cartera propia, que forma
  // parte del ámbito real del supervisor.
  const vendedoresVisibles = vendedores.filter(
    (miembro) => miembro.activo && miembro.rol_crm === 'vendedor',
  )
  const nombrePorId = new Map(
    vendedoresVisibles.map((miembro) => [miembro.perfil_id, miembro.nombre_completo]),
  )
  const responsablesVisibles = new Set<string>([
    supervisorId,
    ...nombrePorId.keys(),
  ])
  const delAmbito = leads.filter((lead) => (
    esAbierto(lead)
    && (
      (lead.vendedor_id != null && responsablesVisibles.has(lead.vendedor_id))
      || (
        lead.vendedor_id == null
        && lead.asignado_supervisor_id === supervisorId
      )
    )
  ))
  const idsAmbito = new Set(delAmbito.map((lead) => lead.id))
  const actividadesAmbito = actividadesDelAmbito(actividades, idsAmbito)
  const tareasAmbito = tareas.filter(
    (tarea) => tarea.lead_id != null && idsAmbito.has(tarea.lead_id),
  )
  const actividadInvalida = idsConActividadInvalida(actividadesAmbito, ahora)
  const tareaInvalida = idsConTareaInvalida(tareasAmbito)
  const confiables = delAmbito.filter(
    (lead) => (
      leadConTiempoConfiable(lead, ahora)
      && !actividadInvalida.has(lead.id)
      && !tareaInvalida.has(lead.id)
    ),
  )
  const idsConfiables = new Set(confiables.map((lead) => lead.id))
  const plan = planPorLead(tareasAmbito, ahora)
  const vencidas = tareasVencidasPorLead(tareasAmbito, idsConfiables, ahora)
  const usadas = new Set<string>()
  const alertas: AlertaCRM[] = []

  // La bandeja es responsabilidad directa del supervisor y tiene prioridad
  // sobre cualquier otra señal que accidentalmente comparta el mismo lead.
  for (const lead of confiables) {
    if (lead.vendedor_id != null || lead.asignado_supervisor_id !== supervisorId) continue
    alertas.push({
      id: `por_repartir:${lead.id}`,
      tipo: 'por_repartir',
      severidad: 'critica',
      alcance: 'equipo',
      titulo: 'Lead por repartir',
      detalle: `${lead.nombre_completo} sigue en tu bandeja sin vendedor.`,
      responsableId: supervisorId,
      responsable: null,
      valor: 1,
      destino: {
        vista: 'hoy',
        leadId: lead.id,
        etiqueta: 'Repartir lead',
      },
    })
    usadas.add(lead.id)
  }

  // El supervisor interviene cuando la tarea ya lleva un día completo vencida;
  // antes sigue siendo una corrección personal del vendedor.
  for (const lead of confiables) {
    if (usadas.has(lead.id)) continue
    const elegida = vencidas.get(lead.id)
    if (!elegida || elegida.horas < 24) continue
    alertas.push(
      alertaTareaVencida(
        lead,
        elegida,
        'equipo',
        nombreResponsable(lead, nombrePorId),
      ),
    )
    usadas.add(lead.id)
  }

  // Solo escala la cola crítica que ya cumplió un día. Los recordatorios
  // normales permanecen en la bandeja personal del vendedor.
  for (const item of colaDe(confiables, actividadesAmbito, ahora, plan, estadosSla)) {
    if (
      usadas.has(item.lead.id)
      || item.bucket === 'por_repartir'
      || item.sev !== 'critica'
      || item.dias < 1
    ) continue
    alertas.push(
      alertaDesdeCola(
        item,
        'equipo',
        nombreResponsable(item.lead, nombrePorId),
      ),
    )
    usadas.add(item.lead.id)
  }

  const sinAccionPorVendedor = new Map<string, Lead[]>()
  for (const lead of sinProximaAccion(confiables, plan.conTarea)) {
    const vendedorId = lead.vendedor_id
    if (
      usadas.has(lead.id)
      || !vendedorId
      || vendedorId === supervisorId
      || !nombrePorId.has(vendedorId)
    ) continue
    const actuales = sinAccionPorVendedor.get(vendedorId)
    if (actuales) actuales.push(lead)
    else sinAccionPorVendedor.set(vendedorId, [lead])
  }

  for (const [vendedorId, leadsSinAccion] of sinAccionPorVendedor) {
    if (leadsSinAccion.length < 3) continue
    const responsable = nombrePorId.get(vendedorId) ?? null
    alertas.push({
      id: `sin_proxima_accion:vendedor:${vendedorId}`,
      tipo: 'sin_proxima_accion',
      severidad: leadsSinAccion.length >= 5 ? 'critica' : 'atencion',
      alcance: 'equipo',
      titulo: 'Vendedor con leads sin próxima acción',
      detalle: `${responsable ?? 'El vendedor'} tiene ${leadsSinAccion.length} leads sin una próxima acción registrada.`,
      responsableId: vendedorId,
      responsable,
      valor: leadsSinAccion.length,
      destino: {
        vista: 'equipo',
        leadId: null,
        etiqueta: 'Ver equipo',
      },
    })
  }

  return ordenarAlertas(alertas)
}
