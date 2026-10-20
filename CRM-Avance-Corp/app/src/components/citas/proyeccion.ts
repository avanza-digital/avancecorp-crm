// Proyección de citas por analista (Gerencia y Supervisión). Módulo PURO: sin
// React ni red, para que cada cifra de la hoja se pruebe con datos fijos.
//
// Cohorte: las citas cuya FECHA DE CREACIÓN (día de Lima) cae en el rango
// Desde–Hasta de la pestaña y, si se eligió, del supervisor de su barra. El
// analista se acota con el embudo de su columna. Las citas llegan del servidor por
// mes de su fecha prevista; la pantalla carga cada mes del rango y los fusiona
// antes de llegar aquí. La cohorte decide Citas, Monto, Ticket cita, las columnas
// de tiempo y el ritmo del Proyectado.
//
// «No puede haber data distinta» (Miguel, 19 y 20/10/2026): % Entrev. y % Conv.
// son los de Resultados, calculados por el MISMO código (`resultados-periodo.ts`)
// con el rango como periodo: cuentan las citas cuyo RESULTADO cae en el rango
// (aunque se crearan antes) y las ventas con fecha comercial en él. Con el rango
// de un mes, cada analista y el total dan lo mismo que Resultados de ese mes.
//
// Reuniones con CLIENTES sin lead (Fase 0b, decisión de Miguel 19/10/2026): son
// citas de origen Cliente. Cuentan en Citas, Clientes y las columnas de tiempo;
// no tienen monto, no son de Resultados ni se «convierten»: Monto, Ticket cita,
// % Entrev., % Conv. y Proyectado no las usan (Miguel, 20/10/2026).
import type { GestionMensualCitas } from '@/lib/gestion-citas'
import { tcAplicable } from '@/lib/capital-unificado'
import { usdAPen } from '@/lib/tipo-cambio'
import { enAmbito, type AmbitoAnalistas } from './atribucion'
import { fechaLocalCitas } from './fecha-comercial'
import type { LeadBaseCitas } from './metas'
import { asignadosDeLaMeta, resultadosDelPeriodo, rosterDeAnalistas, type AnalistaRoster } from './resultados-periodo'
import { ESTADOS, normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
import { diasEntre, errorRango, tramosDelRango, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion } from './proyeccion-rango'

/** Una cita cuenta en una sola de las tres: Referidos + Clientes + Leads = Citas. */
export type OrigenCita = 'referido' | 'cliente' | 'lead'
export type Moneda = 'PEN' | 'USD'
export type ColumnaProyeccion = 'analista' | 'citas' | 'monto' | 'ticket' | 'entrevistas' | 'conversion' | 'proyectado'
  | 'referidos' | 'clientes' | 'leads'
export type ColumnaNumerica = Exclude<ColumnaProyeccion, 'analista'>
export const ORIGENES: readonly OrigenCita[] = ['referido', 'cliente', 'lead']
export const COLUMNA_DE_ORIGEN: Record<OrigenCita, 'referidos' | 'clientes' | 'leads'> = { referido: 'referidos', cliente: 'clientes', lead: 'leads' }

export interface ConversionProyeccion {
  lead_id: string; perfil_id?: string | null; convertido_en: string
  /** Día comercial de la venta; null (renovación, fuente retirada…): no se vincula a ninguna entrevista. */
  fecha_comercial?: string | null | undefined
  /** Analista de la venta (dueño con la regla «evento»); sin dueño, la venta no cierra ninguna entrevista. */
  analista_id: string | null
  /** Su supervisor: decide si la venta entra en el ámbito del supervisor elegido. */
  supervisor_id?: string | null | undefined
  analista_nombre?: string | undefined; supervisor_nombre?: string | undefined
}
type Persona = GestionMensualCitas['poblacion'][number]
/** Persona de la población del avance: solo las que admite Resultados tienen resultados y ventas. */
export type PersonaProyeccion = Pick<Persona, 'lead_id' | 'analista_origen_id' | 'registro_manual' | 'creado_por' | 'primera_asignacion_en'>
  & Partial<Pick<Persona, 'identidad_persona' | 'supervisor_origen_id' | 'analista_origen_nombre' | 'supervisor_origen_nombre'>>
/**
 * Reunión con un cliente que no tiene lead (lector `crm.citas_clientes_proyeccion_fn`): sin lead, monto ni moneda.
 * Analista y supervisor son los del lector; el estado, el de Citas (`ESTADOS`).
 */
export interface ReunionClienteProyeccion extends Pick<CitaEjemplo, 'id' | 'nombre' | 'analista' | 'analistaNombre' | 'supervisor'
  | 'supervisorId' | 'fecha' | 'hora' | 'estado' | 'asistioEn' | 'creadoEn'> {
  leadId: null; moneda: null; monto: null
  /** `identidad_persona` del servidor (`oculta:<id>` si no es visible). Nunca decide ventas ni entrevistas de los leads. */
  persona: string
}
/** Una cita de la hoja: del lector de Citas (con lead) o una reunión con un cliente sin lead. */
export type CitaHoja = CitaEjemplo | ReunionClienteProyeccion

export interface FuenteProyeccion {
  citas: readonly CitaEjemplo[]
  /** Reuniones con clientes sin lead del rango; sin ellas, solo las citas con lead. */
  reunionesClientes?: readonly ReunionClienteProyeccion[] | undefined
  /** Solo el supervisor: los demás filtros de la consulta de arriba no aplican aquí. */
  filtros: Pick<FiltrosCitas, 'equipo'>
  rango: RangoProyeccion
  /** Columnas de tiempo; sin ellas («mes»), la hoja no reparte las citas. */
  tiempo?: TiempoProyeccion | undefined
  /** Instante de la consulta («hoy» de la proyección). */
  corte: string
  tipoCambio?: number | null | undefined
  /** null: el servidor no envió conversiones; la conversión queda sin base, nunca en 0 %. */
  conversiones: readonly ConversionProyeccion[] | null
  /** Lo que usa Resultados para sus tasas, del lector del avance; sin control ni población, % Entrev. y % Conv. quedan sin base. */
  poblacion?: readonly PersonaProyeccion[] | undefined
  control?: GestionMensualCitas['control'] | undefined
  /** Base asignada: la meta de la regla «meta_proyectada». */
  asignaciones?: readonly LeadBaseCitas[] | undefined
  /** Capital del avance: solo aporta analistas y supervisores, como en Resultados. */
  capital?: GestionMensualCitas['capital'] | undefined
}

export interface CitaProyectada {
  cita: CitaHoja
  /** Día de Lima en que se creó la cita (la cohorte y los tramos se cortan por él); '' si no lo trae (solo de un resultado). */
  creada: string
  /** Identidad de la persona (misma regla que el avance mensual). */
  persona: string
  origen: OrigenCita
  /** Monto en soles; null si la cita no trae monto o está en dólares sin tipo de cambio. */
  enSoles: number | null
}
/** Cita del lector de Citas: solo estas cuentan en Monto, Ticket cita, % Conv. y Proyectado. */
export const conLead = (c: CitaProyectada): boolean => c.cita.leadId !== null

export interface PeriodoProyeccion { desde: string; hasta: string; hoy: string; dias: number; transcurridos: number; cerrado: boolean }

export interface MetricasProyeccion {
  citas: CitaProyectada[]; conMonto: CitaProyectada[]
  /** Las citas con lead de la cohorte: la base de Monto, Ticket cita y el ritmo del Proyectado. */
  citasConLead: CitaProyectada[]
  /** Las de Resultados en el rango: citas con lead cuyo resultado (realizada o no asistió) cae en él, sean de cuando sean. */
  resueltas: CitaProyectada[]
  entrevistas: CitaProyectada[]
  /**
   * Entrevistas del rango vinculadas a una venta del rango con la regla de Resultados: fecha comercial no anterior al
   * día de la entrevista y venta del analista de la fila (en el total, de un analista del ámbito).
   */
  convertidas: CitaProyectada[]
  referidos: CitaProyectada[]; clientes: CitaProyectada[]; leads: CitaProyectada[]
  montoPen: number; montoUsd: number; pendienteTc: boolean
  /** «Ticket cita»: monto en citas ÷ citas con lead. No es el «Ticket del mes» de Resultados (capital real ÷ clientes). */
  monto: number | null; ticket: number | null
  /** Las tasas de Resultados (`tasaEntrevistas` y `conversion`) en porcentaje, con sus bases según las reglas de gestión. */
  pctEntrevistas: number | null; pctConversion: number | null
  baseEntrevistas: number; baseConversion: number
  /** Personas distintas entrevistadas en el rango y las que cerraron cliente. */
  personasEntrevistadas: number; personasClientes: number
  /** Citas con lead esperadas al cierre del rango. */
  citasEsperadas: number | null; proyectado: number | null
  /** Las citas de cada columna de tiempo, en el orden de `HojaProyeccion.tramos`. */
  porTramo: CitaProyectada[][]
}
export interface FilaProyeccion extends MetricasProyeccion { id: string; nombre: string; supervisor: string; supervisorId: string }

export interface RangoColumna { min?: number | undefined; max?: number | undefined }
export interface FiltrosColumnas {
  analistas?: readonly string[] | undefined
  monedas?: readonly Moneda[] | undefined
  /** Por origen: las personas marcadas. Recorta SOLO las citas de ese origen. */
  personas?: Partial<Record<OrigenCita, readonly string[] | undefined>> | undefined
  /** Mín/Máx por fila; el monto, en soles y los porcentajes, de 0 a 100. */
  rangos?: Partial<Record<ColumnaNumerica, RangoColumna | undefined>> | undefined
}
export interface OrdenProyeccion { columna: ColumnaProyeccion; direccion: 'asc' | 'desc' }
export const ORDEN_INICIAL: OrdenProyeccion = { columna: 'citas', direccion: 'desc' }

export interface HojaProyeccion {
  periodo: PeriodoProyeccion | null
  tc: number | null
  /** La cohorte antes de los embudos de columna. */
  cohorte: CitaProyectada[]
  /** Hay citas en dólares con monto: la hoja necesita tipo de cambio. */
  requiereTc: boolean
  /** Columnas de tiempo (semanas o días); vacío en la vista del mes. */
  tramos: TramoProyeccion[]
  /** Una fila por analista, en el orden elegido (la numeración # es continua). */
  filas: FilaProyeccion[]
  /** El proyectado del total SUMA el de cada analista con base; nunca promedia tasas. */
  total: MetricasProyeccion
  /** Analistas con resultados (o base de meta) en el rango, sin el embudo de Analista: también son opciones de ese embudo. */
  conResultados: AnalistaRoster[]
}

/** Días del rango, días ya transcurridos hasta hoy y si el rango ya terminó. */
export function periodoProyeccion(rango: RangoProyeccion, corte: string): PeriodoProyeccion | null {
  if (errorRango(rango) || !Number.isFinite(Date.parse(corte))) return null
  const { desde, hasta } = rango
  const hoy = fechaLocalCitas(corte)
  const dias = diasEntre(desde, hasta) + 1
  const cerrado = hoy > hasta
  const transcurridos = hoy < desde ? 0 : cerrado ? dias : diasEntre(desde, hoy) + 1
  return { desde, hasta, hoy, dias, transcurridos, cerrado }
}

const esReferido = (origen: string) => normalizar(origen).replace(/[\s_-]+/g, ' ') === 'referido'

interface Contexto {
  periodo: PeriodoProyeccion | null
  tramos: TramoProyeccion[]
  tc: number | null
  conocidas: boolean
  /** Conversiones de la persona: el respaldo de «cliente» mira `convertido_en`. */
  conversionesDe: (persona: string) => readonly ConversionProyeccion[]
}

function prepararContexto(fuente: FuenteProyeccion) {
  // Misma identidad que el avance mensual: la del servidor; si falta, el perfil
  // cliente del lead convertido; si no, el propio lead.
  const conversiones = fuente.conversiones ?? []
  const perfiles = new Map(conversiones.filter(c => c.perfil_id).map(c => [c.lead_id, c.perfil_id!]))
  const identidades = new Map((fuente.poblacion ?? []).map(p => [p.lead_id,
    p.identidad_persona ?? (perfiles.has(p.lead_id) ? `perfil:${perfiles.get(p.lead_id)}` : `lead:${p.lead_id}`)]))
  const persona = (lead: string) => identidades.get(lead) ?? `lead:${lead}`
  const periodo = periodoProyeccion(fuente.rango, fuente.corte)
  const porPersona = new Map<string, ConversionProyeccion[]>()
  for (const c of conversiones) {
    const suyas = porPersona.get(persona(c.lead_id))
    if (suyas) suyas.push(c)
    else porPersona.set(persona(c.lead_id), [c])
  }
  const contexto: Contexto = {
    periodo, tramos: periodo ? tramosDelRango(fuente.rango, fuente.tiempo ?? 'mes', periodo.hoy) : [], tc: tcAplicable(fuente.tipoCambio),
    conocidas: fuente.conversiones !== null, conversionesDe: clave => porPersona.get(clave) ?? [],
  }
  // Analistas y supervisores con las fuentes y la precedencia de Resultados: el supervisor decide el ámbito.
  const roster = rosterDeAnalistas({ capital: fuente.capital, poblacion: fuente.poblacion, asignaciones: fuente.asignaciones, citas: fuente.citas, ventas: conversiones })
  return { contexto, persona, roster }
}

function proyectar(cita: CitaEjemplo, creada: string, persona: string, contexto: Contexto): CitaProyectada {
  // RESPALDO hasta la Fase 0: mientras el servidor no mande `es_cliente`, una cita
  // es de cliente si su persona ya se había convertido ANTES de crearse la cita.
  // Cuando el campo llegue, manda el servidor y este respaldo deja de usarse.
  const instanteCreada = Date.parse(cita.creadoEn ?? '')
  const esCliente = cita.esCliente ?? contexto.conversionesDe(persona).some(c => Date.parse(c.convertido_en) < instanteCreada)
  const origen: OrigenCita = esCliente ? 'cliente' : esReferido(cita.origen) ? 'referido' : 'lead'
  const enSoles = cita.monto == null ? null : cita.moneda === 'PEN' ? cita.monto
    : contexto.tc === null ? null : usdAPen(cita.monto, contexto.tc)
  return { cita, creada, persona, origen, enSoles }
}

/** Día de Lima en que se creó la cita; '' si no trae una fecha válida. */
const diaDeCreacion = (c: CitaHoja) => c.creadoEn && Number.isFinite(Date.parse(c.creadoEn)) ? fechaLocalCitas(c.creadoEn) : ''

/**
 * % Entrev. y % Conv. de la hoja: `resultadosDelPeriodo` (el código de Resultados) con el rango como periodo,
 * sobre las citas con lead que dejan los embudos de moneda y personas. El de Analista entra en el ámbito
 * (por dueño del resultado, como el filtro de analista de Resultados); sin `analistas`, no se aplica.
 */
function resultadosDelRango(fuente: FuenteProyeccion, contexto: Contexto, persona: (lead: string) => string, roster: ReadonlyMap<string, AnalistaRoster>,
  delLector: readonly CitaProyectada[], columnas: FiltrosColumnas, analistas: readonly string[] | undefined) {
  const { periodo } = contexto
  if (!periodo || !fuente.control) return null
  const control = fuente.control
  const proyectadas = new Map(delLector.map(c => [c.cita.id, c]))
  const citas = recortar(delLector, columnas, 'analistas').map(c => c.cita as CitaEjemplo)
  const personas = new Map((fuente.poblacion ?? []).map(p => [p.lead_id, p]))
  const elegidos = analistas ? new Set(analistas) : null
  const { equipo } = fuente.filtros
  const ambito: AmbitoAnalistas = { analistas: elegidos, equipo, supervisorDe: id => roster.get(id)?.supervisorId }
  const resultados = resultadosDelPeriodo({
    citas, ventas: fuente.conversiones ?? [], personas, identidad: persona, control,
    periodo: { desde: periodo.desde, hasta: periodo.hasta, corte: fuente.corte }, ambito: id => enAmbito(id, ambito),
  })
  // La base de la meta («meta_proyectada»): asignados en el rango, con el supervisor y los analistas de la consulta, como en Resultados.
  const asignados = asignadosDeLaMeta((fuente.asignaciones ?? []).filter(l => (!equipo || l.supervisorId === equipo)
    && (!elegidos || elegidos.has(l.id))), personas, control, periodo)
  const leads = (analista?: string, duenos?: ReadonlySet<string>) =>
    new Set(asignados.filter(l => analista ? l.id === analista : !duenos || duenos.has(l.id)).map(l => l.leadId)).size
  return {
    dueno: resultados.dueno,
    resueltas: resultados.resueltas,
    /**
     * Con la regla «meta_proyectada», los analistas con base en el rango y dentro del ámbito (su supervisor es el del
     * roster, no el de la asignación): su % Entrev. existe (0 % sin entrevistas), como en Resultados.
     */
    conMeta: control.configuracion.base_avance === 'meta_proyectada' ? [...new Set(asignados.map(l => l.id))].filter(id => enAmbito(id, ambito)) : [],
    medir: (analista?: string, duenos?: ReadonlySet<string>): ResultadosDeFila => ({
      medida: resultados.medir(analista, leads(analista, duenos), duenos), de: c => proyectadas.get(c.id)!,
    }),
  }
}
type MedidaResultados = ReturnType<ReturnType<typeof resultadosDelPeriodo<CitaEjemplo, ConversionProyeccion>>['medir']>
/** Lo que Resultados mide para una fila (o el total) y cómo volver de sus citas a las de la hoja. */
interface ResultadosDeFila { medida: MedidaResultados; de: (cita: CitaEjemplo) => CitaProyectada }

function cohorte(fuente: FuenteProyeccion, persona: (lead: string) => string, contexto: Contexto): CitaProyectada[] {
  const periodo = contexto.periodo
  if (!periodo) return []
  const { equipo } = fuente.filtros
  /** Día de creación si la cita entra en la cohorte (rango y supervisor); si no, null. */
  const creadaEnRango = (c: CitaHoja) => {
    if (!c.creadoEn || !Number.isFinite(Date.parse(c.creadoEn)) || (equipo && c.supervisorId !== equipo)) return null
    const creada = fechaLocalCitas(c.creadoEn)
    return creada >= periodo.desde && creada <= periodo.hasta ? creada : null
  }
  const lista: CitaProyectada[] = []
  for (const c of fuente.citas) {
    const creada = creadaEnRango(c)
    if (creada) lista.push(proyectar(c, creada, persona(c.leadId), contexto))
  }
  // Las reuniones con clientes sin lead son de origen Cliente y no tienen monto.
  for (const r of fuente.reunionesClientes ?? []) {
    const creada = creadaEnRango(r)
    if (creada) lista.push({ cita: r, creada, persona: r.persona, origen: 'cliente', enSoles: null })
  }
  return lista
}

/** Reparte las citas en las columnas de tiempo por su día de creación; las de un rango ya cortado suman la lista entera. */
export function repartirEnTramos(lista: readonly CitaProyectada[], tramos: readonly RangoProyeccion[]): CitaProyectada[][] {
  const porTramo = tramos.map(() => [] as CitaProyectada[])
  for (const c of lista) {
    const i = tramos.findIndex(t => c.creada >= t.desde && c.creada <= t.hasta)
    if (i >= 0) porTramo[i]!.push(c)
  }
  return porTramo
}

const suma = (lista: readonly CitaProyectada[], moneda: Moneda) =>
  lista.reduce((n, c) => n + (c.cita.moneda === moneda && c.cita.monto != null ? c.cita.monto : 0), 0)

/** `resultados`: lo que Resultados mide para la fila o el total; null sin reglas de gestión ni periodo válido. */
function medir(lista: CitaProyectada[], contexto: Contexto, resultados: ResultadosDeFila | null): MetricasProyeccion {
  // Métricas de prospectos: solo las citas con lead (las reuniones con clientes sin lead no tienen monto ni se convierten).
  const citasConLead = lista.filter(conLead)
  const n = citasConLead.length
  const conMonto = citasConLead.filter(c => c.cita.monto != null)
  const montoPen = suma(citasConLead, 'PEN')
  const montoUsd = suma(citasConLead, 'USD')
  const pendienteTc = montoUsd > 0 && contexto.tc === null
  const monto = pendienteTc ? null : montoPen + (contexto.tc === null ? 0 : usdAPen(montoUsd, contexto.tc))
  const ticket = monto !== null && n ? monto / n : null
  // % Entrev. y % Conv.: los de Resultados en el rango, medidos por su código, no recalculados aquí.
  const r = resultados?.medida
  const deLaHoja = (citas: readonly CitaEjemplo[] | undefined) => resultados ? (citas ?? []).map(resultados.de) : []
  const pctEntrevistas = r?.tasaEntrevistas == null ? null : r.tasaEntrevistas * 100
  const pctConversion = contexto.conocidas && r?.conversion != null ? r.conversion * 100 : null
  const periodo = contexto.periodo
  const hastaHoy = periodo ? citasConLead.filter(c => c.creada <= periodo.hoy).length : n
  // Citas esperadas al cierre: el ritmo de los días transcurridos llevado al periodo entero.
  const citasEsperadas = !n || !periodo ? null : periodo.cerrado || !periodo.transcurridos ? n
    : Math.max(n, hastaHoy / periodo.transcurridos * periodo.dias)
  // Como el cierre proyectado de Resultados: la tasa OBSERVADA de entrevistas (realizadas ÷ citas con resultado,
  // sea cual sea la regla de conteo del % Entrev.) × conversión × ticket cita. Sin base, «sin base», nunca 0.
  const tasaObservada = r?.resultado.length ? r.visitas.length / r.resultado.length : null
  const proyectado = citasEsperadas !== null && tasaObservada !== null && pctConversion !== null && ticket !== null
    ? citasEsperadas * tasaObservada * (pctConversion / 100) * ticket : null
  return {
    citas: lista, citasConLead, conMonto, entrevistas: deLaHoja(r?.visitas), resueltas: deLaHoja(r?.resultado), convertidas: deLaHoja(r?.visitasVinculadas),
    referidos: lista.filter(c => c.origen === 'referido'), clientes: lista.filter(c => c.origen === 'cliente'),
    leads: lista.filter(c => c.origen === 'lead'),
    montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctConversion,
    baseEntrevistas: r?.baseEntrevistas ?? 0, baseConversion: r?.baseConversion ?? 0,
    personasEntrevistadas: r?.gente.size ?? 0, personasClientes: r?.clientes ?? 0,
    citasEsperadas, proyectado, porTramo: repartirEnTramos(lista, contexto.tramos),
  }
}

type Corte = 'analistas' | 'monedas' | OrigenCita
/** Embudos que quitan citas (analista, moneda y personas). `ignorar` deja fuera el del menú abierto. */
function recortar(lista: readonly CitaProyectada[], columnas: FiltrosColumnas, ignorar?: Corte) {
  const analistas = ignorar === 'analistas' || !columnas.analistas ? null : new Set(columnas.analistas)
  const monedas = ignorar === 'monedas' || !columnas.monedas ? null : new Set(columnas.monedas)
  const personas = new Map(ORIGENES.filter(o => o !== ignorar && columnas.personas?.[o]).map(o => [o, new Set(columnas.personas![o])]))
  // Una reunión con un cliente sin lead no tiene moneda: un filtro de moneda la deja fuera.
  return lista.filter(c => (!analistas || analistas.has(c.cita.analista)) && (!monedas || (c.cita.moneda !== null && monedas.has(c.cita.moneda)))
    && (!personas.has(c.origen) || personas.get(c.origen)!.has(c.persona)))
}

export function valorColumna(fila: MetricasProyeccion & { nombre?: string }, columna: ColumnaProyeccion): number | string | null {
  switch (columna) {
    case 'analista': return fila.nombre ?? ''
    case 'citas': return fila.citas.length
    case 'monto': return fila.monto
    case 'ticket': return fila.ticket
    case 'entrevistas': return fila.pctEntrevistas
    case 'conversion': return fila.pctConversion
    case 'proyectado': return fila.proyectado
    case 'referidos': return fila.referidos.length
    case 'clientes': return fila.clientes.length
    case 'leads': return fila.leads.length
  }
}

function dentroDeRangos(fila: FilaProyeccion, rangos: FiltrosColumnas['rangos']) {
  return Object.entries(rangos ?? {}).every(([columna, r]) => {
    if (!r || (r.min === undefined && r.max === undefined)) return true
    const valor = valorColumna(fila, columna as ColumnaNumerica)
    return typeof valor === 'number' && (r.min === undefined || valor >= r.min) && (r.max === undefined || valor <= r.max)
  })
}

/** Ordena; el «—» (sin base) va siempre al final, en ambos sentidos. */
function comparar(orden: OrdenProyeccion) {
  return (a: FilaProyeccion, b: FilaProyeccion) => {
    const x = valorColumna(a, orden.columna), y = valorColumna(b, orden.columna)
    if (x === null || y === null) return x === y ? a.nombre.localeCompare(b.nombre, 'es') : x === null ? 1 : -1
    const r = typeof x === 'string' || typeof y === 'string' ? String(x).localeCompare(String(y), 'es') : x - y
    return (orden.direccion === 'asc' ? r : -r) || a.nombre.localeCompare(b.nombre, 'es')
  }
}

export function calcularProyeccion(fuente: FuenteProyeccion, columnas: FiltrosColumnas = {}, orden: OrdenProyeccion = ORDEN_INICIAL): HojaProyeccion {
  const { contexto, persona, roster } = prepararContexto(fuente)
  const base = cohorte(fuente, persona, contexto)
  const visibles = recortar(base, columnas)
  // Todas las citas del lector como citas de la hoja: de ellas salen los resultados del rango.
  const delLector = contexto.periodo && fuente.control ? fuente.citas.map(c => proyectar(c, diaDeCreacion(c), persona(c.leadId), contexto)) : []
  const delRango = resultadosDelRango(fuente, contexto, persona, roster, delLector, columnas, columnas.analistas)
  const porAnalista = new Map<string, CitaProyectada[]>()
  for (const c of visibles) {
    const suyas = porAnalista.get(c.cita.analista)
    if (suyas) suyas.push(c)
    else porAnalista.set(c.cita.analista, [c])
  }
  // Un analista con resultados en el rango (o con base de meta) tiene fila aunque no haya creado citas en él: Resultados también la tiene.
  const duenos = (resultados: ReturnType<typeof resultadosDelRango>) => resultados === null ? []
    : [...new Set([...resultados.resueltas.flatMap(c => resultados.dueno(c.leadId, c.analista) ?? []), ...resultados.conMeta])]
  for (const id of duenos(delRango)) if (!porAnalista.has(id)) porAnalista.set(id, [])
  const quien = (id: string): AnalistaRoster => roster.get(id) ?? { id, nombre: 'Sin analista', supervisor: 'Sin supervisor', supervisorId: 'sin_supervisor' }
  const filas: FilaProyeccion[] = [...porAnalista].map(([id, lista]) => {
    const { analistaNombre: nombre, supervisor, supervisorId } = lista[0]?.cita ?? { ...quien(id), analistaNombre: quien(id).nombre }
    return { id, nombre, supervisor, supervisorId, ...medir(lista, contexto, delRango?.medir(id) ?? null) }
  }).filter(f => dentroDeRangos(f, columnas.rangos)).sort(comparar(orden))
  // Con Mín/Máx, el total mide solo las filas que quedan; sin ellos, todo el ámbito, como el total de Resultados.
  const hayRangos = Object.values(columnas.rangos ?? {}).some(r => r && (r.min !== undefined || r.max !== undefined))
  const conBase = filas.filter(f => f.proyectado !== null)
  const total = { ...medir(filas.flatMap(f => f.citas), contexto, delRango?.medir(undefined, hayRangos ? new Set(filas.map(f => f.id)) : undefined) ?? null),
    proyectado: conBase.length ? conBase.reduce((n, f) => n + f.proyectado!, 0) : null }
  const sinEmbudo = columnas.analistas ? resultadosDelRango(fuente, contexto, persona, roster, delLector, columnas, undefined) : delRango
  return {
    periodo: contexto.periodo, tc: contexto.tc, cohorte: base, tramos: contexto.tramos, filas, total,
    requiereTc: base.some(c => c.cita.moneda === 'USD' && (c.cita.monto ?? 0) > 0),
    conResultados: duenos(sinEmbudo).map(quien),
  }
}

export interface OpcionEmbudo { id: string; nombre: string; citas: number }
const ordenarOpciones = (opciones: Map<string, OpcionEmbudo>) => [...opciones.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es') || a.id.localeCompare(b.id))
function contar(lista: readonly CitaProyectada[], clave: (c: CitaProyectada) => [string, string]) {
  const opciones = new Map<string, OpcionEmbudo>()
  for (const c of lista) {
    const [id, nombre] = clave(c)
    const actual = opciones.get(id)
    opciones.set(id, { id, nombre: actual?.nombre ?? nombre, citas: (actual?.citas ?? 0) + 1 })
  }
  return ordenarOpciones(opciones)
}
/** Analistas de la cohorte con su n.º de citas (respetando los demás embudos) y, con 0, los que solo tienen resultados en el rango. */
export function opcionesAnalistas(hoja: HojaProyeccion, columnas: FiltrosColumnas): OpcionEmbudo[] {
  const opciones = new Map(contar(recortar(hoja.cohorte, columnas, 'analistas'), c => [c.cita.analista, c.cita.analistaNombre]).map(o => [o.id, o]))
  for (const a of hoja.conResultados) if (!opciones.has(a.id)) opciones.set(a.id, { id: a.id, nombre: a.nombre, citas: 0 })
  return ordenarOpciones(opciones)
}
/** Personas de un origen (id = identidad) con su n.º de citas. */
export function opcionesPersonas(hoja: HojaProyeccion, columnas: FiltrosColumnas, origen: OrigenCita): OpcionEmbudo[] {
  return contar(recortar(hoja.cohorte, columnas, origen).filter(c => c.origen === origen), c => [c.persona, c.cita.nombre])
}
/** Citas y monto original por moneda (respetando los demás embudos). */
export function opcionesMonedas(hoja: HojaProyeccion, columnas: FiltrosColumnas): Record<Moneda, { citas: number; monto: number }> {
  const lista = recortar(hoja.cohorte, columnas, 'monedas')
  const de = (moneda: Moneda) => ({ citas: lista.filter(c => c.cita.moneda === moneda).length, monto: suma(lista, moneda) })
  return { PEN: de('PEN'), USD: de('USD') }
}

// ───────── CSV ─────────
const celdaCsv = (valor: unknown) => '"' + String(valor ?? '').replace(/^[\s=+@-]/, m => `'${m}`).replaceAll('"', '""') + '"'
const archivoCsv = (filas: unknown[][]) => '﻿' + filas.map(fila => fila.map(celdaCsv).join(',')).join('\r\n')
const redondeo = (valor: number | null, decimales = 2) => valor === null ? '' : Math.round(valor * 10 ** decimales) / 10 ** decimales
export const ROTULO_ORIGEN: Record<OrigenCita, string> = { referido: 'Referido', cliente: 'Cliente', lead: 'Lead' }

/** En Semanas o Días, una columna por tramo después de «Analista». */
export function csvProyeccion(hoja: HojaProyeccion, rotulo: string): string {
  const fila = (f: MetricasProyeccion, equipo: string, analista: string) => [rotulo, equipo, analista, ...f.porTramo.map(l => l.length), f.citas.length,
    f.pendienteTc ? 'Pendiente de TC' : redondeo(f.monto), redondeo(f.ticket), redondeo(f.pctEntrevistas, 1), redondeo(f.pctConversion, 1),
    redondeo(f.proyectado), f.referidos.length, f.clientes.length, f.leads.length]
  return archivoCsv([
    ['Periodo', 'Equipo', 'Analista', ...hoja.tramos.map(t => t.nombre), 'Citas', 'Monto S/', 'Ticket cita S/', '% Entrev.', '% Conv.', 'Proyectado citas S/', 'Referidos', 'Clientes', 'Leads'],
    ...hoja.filas.map(f => fila(f, f.supervisor, f.nombre)),
    fila(hoja.total, '', `Total · ${hoja.filas.length} analistas`),
  ])
}

/** Cada cita con lo que la ubica en la hoja: el día (de Lima) en que se creó decide su periodo y su columna de tiempo. */
export function csvCitasProyeccion(lista: readonly CitaProyectada[]): string {
  return archivoCsv([
    ['Código de cita', 'Creada', 'Fecha', 'Hora', 'Persona', 'Analista', 'Supervisor', 'Estado', 'Moneda', 'Monto', 'Monto S/', 'Origen'],
    ...lista.map(({ cita, creada, enSoles, origen }) => [cita.id, creada, cita.fecha, cita.hora, cita.nombre, cita.analistaNombre, cita.supervisor,
      ESTADOS[cita.estado].label, cita.moneda, cita.monto ?? '', redondeo(enSoles), ROTULO_ORIGEN[origen]]),
  ])
}
