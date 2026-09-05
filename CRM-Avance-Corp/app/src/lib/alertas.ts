import {
  colaDe,
  diasSinActividad,
  esAbierto,
  haceTexto,
  indexarUltimaActividad,
  sinProximaAccion,
  type ItemCola,
} from './inteligencia'
import { planPorLead } from './plan-lead'
import type { ReconocimientoVigente } from './reconocimientos-alertas'
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
  // F3 lead libre (§5.4): recordatorio personal vencido — «verifica si ya
  // está libre». Lo deriva lib/recordatorios-disponibilidad, no este módulo.
  | 'revisar_contacto'

export interface DestinoAlerta {
  vista: Vista
  leadId?: string | null
  etiqueta: string
  /** Rango ya consultado para una alerta gerencial; se conserva al navegar. */
  periodo?: { desde: string; hasta: string }
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
  /** SOLO tipo 'revisar_contacto' (F3): la pantalla verifica BAJO DEMANDA
   *  abriendo el alta con este teléfono, y puede quitar el recordatorio. */
  contacto?: {
    telefono: string
    recordatorioId: string
  }
  /** SOLO grupos del supervisor (F4): la FOTO de ids —de leads, o de
   *  analistas en el grupo por analista— que el libro de reconocimientos
   *  guarda y compara para el «reaparece si empeora». Nunca nombres (sin
   *  PII, contrato del servidor). Sin miembros no hay botón de reconocer. */
  miembros?: readonly string[]
  /** Lo añade el PROVIDER cuando un asiento vigente del libro atenúa esta
   *  alerta (reconocer deja rastro; posponer directamente la oculta). */
  reconocimiento?: ReconocimientoVigente
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
  // El recordatorio vencido va PRIMERO: es la acción más barata y con
  // ventana (otro analista puede tomar el contacto mientras tanto).
  revisar_contacto: 0,
  por_repartir: 1,
  tarea_vencida: 2,
  lead_sin_responder: 3,
  sin_proxima_accion: 4,
  bajo_meta_conversion: 5,
  caida_conversion: 6,
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

// Deja de ser una segunda escala: la misma pregunta («¿hace cuánto?») con una
// sola respuesta — su mitad ≥ 24 h era copia byte a byte de haceTexto, y su
// suelo «hace menos de una hora» convivía en la MISMA lista con motivos que ya
// dicen los minutos. Recibe HORAS porque así la llama `horasVencida`.
function textoRetraso(horas: number): string {
  return haceTexto(horas / 24)
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
  // eliminó los leads de otros analistas.
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
  // únicamente analistas activos y se admite su cartera propia, que forma
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
  const indiceActividad = indexarUltimaActividad(actividadesAmbito)
  const usadas = new Set<string>()
  const alertas: AlertaCRM[] = []

  // UNA ALERTA POR DECISIÓN, NO POR REGISTRO (decisión de Miguel 2026-08-23).
  // Antes cada lead parkeado, cada tarea vencida y cada lead crítico emitía
  // su propia alerta: con la bandeja llena la campana marcaba «99+» y la
  // tarea vencida de verdad quedaba enterrada. Ahora cada bloque de abajo
  // produce a lo sumo UN grupo; el lead sigue contando una sola vez (`usadas`)
  // y la severidad del grupo es la MÁS ALTA de sus miembros — agrupar nunca
  // rebaja lo que ya era crítico.

  // La bandeja es responsabilidad directa del supervisor y tiene prioridad
  // sobre cualquier otra señal que accidentalmente comparta el mismo lead.
  // Miembros ordenados por rezago y luego por id: el detalle del grupo no
  // puede depender del orden en que llegaron los leads (la prueba de orden
  // estable lo cazó a la primera).
  const bandeja = confiables
    .filter((lead) => lead.vendedor_id == null && lead.asignado_supervisor_id === supervisorId)
    .map((lead) => ({ lead, dias: diasSinActividad(lead, actividadesAmbito, ahora, indiceActividad) }))
    .sort((a, b) => b.dias - a.dias || a.lead.id.localeCompare(b.lead.id))
  if (bandeja.length > 0) {
    for (const { lead } of bandeja) usadas.add(lead.id)
    const rezagoMaximo = bandeja[0]?.dias ?? 0
    // Estar parkeado se redefinió a ámbar (decisión de Miguel 2026-08-23: es
    // trabajo de la semana, la interrupción es el lead NUEVO sin responder).
    // Pero una señal crítica INDEPENDIENTE no se traga: si un miembro además
    // arrastra una tarea vencida de más de un día, el grupo entero sube a
    // crítica — agrupar nunca rebaja (hallazgo BLOQUEANTE de Codex).
    const conPlazoVencido = bandeja.some(
      ({ lead }) => (vencidas.get(lead.id)?.horas ?? 0) >= 24,
    )
    alertas.push({
      id: `grupo:por_repartir:${supervisorId}`,
      tipo: 'por_repartir',
      severidad: conPlazoVencido ? 'critica' : 'atencion',
      alcance: 'equipo',
      titulo: `${bandeja.length} ${bandeja.length === 1 ? 'lead esperando' : 'leads esperando'} reparto`,
      detalle: `${nombresResumidos(bandeja.map(({ lead }) => lead.nombre_completo))}. El más rezagado espera ${haceTexto(rezagoMaximo)}.`,
      responsableId: supervisorId,
      responsable: null,
      valor: bandeja.length,
      miembros: bandeja.map(({ lead }) => lead.id),
      destino: {
        vista: 'derivaciones',
        leadId: null,
        etiqueta: 'Repartir',
      },
    })
  }

  // Plazos vencidos desde ayer: la tarea que ya lleva un día completo vencida
  // (antes sigue siendo una corrección personal del analista) y la cola
  // crítica que ya cumplió un día. Un solo grupo: la decisión es la misma —
  // sentarse con el equipo sobre lo que venció — aunque el reloj sea distinto.
  const conTareaVencida = confiables
    .filter((lead) => !usadas.has(lead.id) && (vencidas.get(lead.id)?.horas ?? 0) >= 24)
    .sort((a, b) => (
      (vencidas.get(b.id)?.horas ?? 0) - (vencidas.get(a.id)?.horas ?? 0)
      || a.id.localeCompare(b.id)
    ))
  for (const lead of conTareaVencida) usadas.add(lead.id)

  const sinResponder: ItemCola[] = []
  const relojCumplido: ItemCola[] = []
  for (const item of colaDe(confiables, actividadesAmbito, ahora, plan, estadosSla)) {
    if (
      usadas.has(item.lead.id)
      || item.bucket === 'por_repartir'
      || item.sev !== 'critica'
      || item.dias < 1
    ) continue
    ;(item.bucket === 'sin_responder' ? sinResponder : relojCumplido).push(item)
    usadas.add(item.lead.id)
  }

  // Nuevos sin responder: es la interrupción del día (un lead nuevo se enfría
  // por horas), así que va en su propio grupo y no se mezcla con los plazos.
  if (sinResponder.length > 0) {
    alertas.push({
      id: `grupo:lead_sin_responder:${supervisorId}`,
      tipo: 'lead_sin_responder',
      severidad: 'critica',
      alcance: 'equipo',
      titulo: `${sinResponder.length} ${sinResponder.length === 1 ? 'lead nuevo' : 'leads nuevos'} sin responder`,
      // «Un día o más», no «más de un día»: el umbral incluye las 24 h justas.
      detalle: `${nombresResumidos(sinResponder.map((item) => item.lead.nombre_completo))}. Sin primer contacto desde hace un día o más.`,
      responsableId: null,
      responsable: null,
      valor: sinResponder.length,
      miembros: sinResponder.map((item) => item.lead.id),
      destino: { vista: 'hoy', leadId: null, etiqueta: 'Ver la cola' },
    })
  }

  const plazosVencidos = conTareaVencida.length + relojCumplido.length
  if (plazosVencidos > 0) {
    const partes: string[] = []
    if (conTareaVencida.length > 0) {
      partes.push(`${conTareaVencida.length} ${conTareaVencida.length === 1 ? 'tarea vencida' : 'tareas vencidas'}`)
    }
    if (relojCumplido.length > 0) {
      partes.push(`${relojCumplido.length} con el reloj de gestión cumplido`)
    }
    alertas.push({
      id: `grupo:tarea_vencida:${supervisorId}`,
      tipo: 'tarea_vencida',
      // Todos los miembros ya eran críticos por separado (≥ 24 h): el grupo
      // hereda esa severidad, no la promedia.
      severidad: 'critica',
      alcance: 'equipo',
      titulo: `${plazosVencidos} ${plazosVencidos === 1 ? 'lead con plazo vencido' : 'leads con plazo vencido'} desde ayer`,
      detalle: `${partes.join(' · ')}: ${nombresResumidos([
        ...conTareaVencida.map((lead) => lead.nombre_completo),
        ...relojCumplido.map((item) => item.lead.nombre_completo),
      ])}.`,
      responsableId: null,
      responsable: null,
      valor: plazosVencidos,
      miembros: [
        ...conTareaVencida.map((lead) => lead.id),
        ...relojCumplido.map((item) => item.lead.id),
      ],
      // Con tareas vencidas dentro, el destino es la AGENDA: un lead con la
      // tarea vencida Y otra futura tiene plan vivo y NO aparece en la cola
      // (hallazgo de Codex — el enlace «Ver la cola» moría en una pantalla
      // sin el caso). La agenda lista toda tarea pendiente, vencida incluida.
      destino: conTareaVencida.length > 0
        ? { vista: 'agenda', leadId: null, etiqueta: 'Abrir en Agenda' }
        : { vista: 'hoy', leadId: null, etiqueta: 'Ver la cola' },
    })
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

  // Analistas con 3+ leads sin próxima acción: un solo grupo ordenado por
  // carga (la conversación es con cada uno, pero la decisión —revisar cómo
  // planifica el equipo— es una). Con un solo analista conserva su nombre
  // como responsable, igual que antes.
  const vendedoresSinAccion = [...sinAccionPorVendedor]
    .filter(([, leadsSinAccion]) => leadsSinAccion.length >= 3)
    .map(([vendedorId, leadsSinAccion]) => ({
      vendedorId,
      nombre: nombrePorId.get(vendedorId) ?? 'El analista',
      cantidad: leadsSinAccion.length,
    }))
    // El id remata el desempate: dos nombres canónicamente equivalentes en
    // Unicode («Ána» precompuesto y descompuesto) comparan 0 en localeCompare
    // y sin esto el orden dependería del orden de entrada.
    .sort((a, b) => (
      b.cantidad - a.cantidad
      || a.nombre.localeCompare(b.nombre, 'es')
      || a.vendedorId.localeCompare(b.vendedorId)
    ))
  if (vendedoresSinAccion.length > 0) {
    const unico = vendedoresSinAccion.length === 1 ? vendedoresSinAccion[0] : undefined
    const totalLeads = vendedoresSinAccion.reduce((suma, v) => suma + v.cantidad, 0)
    alertas.push({
      id: `grupo:sin_proxima_accion:${supervisorId}`,
      tipo: 'sin_proxima_accion',
      severidad: vendedoresSinAccion.some((v) => v.cantidad >= 5) ? 'critica' : 'atencion',
      alcance: 'equipo',
      titulo: unico
        ? `${unico.nombre} tiene ${unico.cantidad} leads sin próxima acción`
        : `${vendedoresSinAccion.length} analistas con leads sin próxima acción`,
      detalle: unico
        ? `${unico.cantidad} leads sin una próxima acción registrada.`
        : vendedoresSinAccion.map((v) => `${v.nombre} ${v.cantidad}`).join(' · '),
      responsableId: unico?.vendedorId ?? null,
      responsable: unico?.nombre ?? null,
      valor: totalLeads,
      // La foto es de ANALISTAS, no de leads: la decisión del grupo es la
      // conversación con cada analista. Un analista NUEVO en aprietos revive
      // la alerta; el mismo analista pasando de 3 a 4 leads no (la
      // conversación pendiente es la misma) — hasta que cruce a crítica (≥5),
      // donde revive por severidad.
      miembros: vendedoresSinAccion.map((vendedor) => vendedor.vendedorId),
      destino: {
        vista: 'equipo',
        leadId: null,
        etiqueta: 'Ver equipo',
      },
    })
  }

  return ordenarAlertas(alertas)
}

/** Los tres primeros nombres y «y N más»: el detalle de un grupo cabe en una línea. */
function nombresResumidos(nombres: string[], tope = 3): string {
  if (nombres.length <= tope) return nombres.join(', ')
  const resto = nombres.length - tope
  return `${nombres.slice(0, tope).join(', ')} y ${resto} más`
}
