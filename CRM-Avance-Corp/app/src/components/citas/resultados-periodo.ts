// Resultados de citas de un PERIODO: qué citas tuvieron su resultado en él, qué
// ventas caen en su fecha comercial y las tasas de entrevistas y de conversión.
// UNA sola implementación para Resultados (`calcularAvanceCitas`, el mes de la
// consulta) y la Proyección (`calcularProyeccion`, su rango Desde–Hasta): «no
// puede haber data distinta» (Miguel, 19/10/2026). El 20/10 la Proyección daba
// otro % Entrev. porque medía las citas CREADAS en el rango: un resultado cuenta
// en el periodo en que ocurrió, no en el que se creó la cita.
import type { GestionMensualCitas } from '@/lib/gestion-citas'
import { reglaDueno, ventaCierraEntrevista } from './atribucion'
import { fechaLocalCitas, ventaComercialDelPeriodo, type PeriodoComercial } from './fecha-comercial'
import type { LeadBaseCitas } from './metas'
import type { CitaEjemplo } from './modelo'

type Control = GestionMensualCitas['control']
export type CitaResultado = Pick<CitaEjemplo, 'leadId' | 'analista' | 'estado' | 'asistioEn' | 'fecha' | 'hora'>
export type PersonaResultado = Pick<GestionMensualCitas['poblacion'][number],
  'analista_origen_id' | 'registro_manual' | 'creado_por' | 'primera_asignacion_en'>
export interface VentaResultado { lead_id: string; analista_id: string | null; fecha_comercial?: string | null | undefined; convertido_en: string }

/** Instante del resultado: la asistencia registrada de una realizada; la hora prevista de una inasistencia. */
export const fechaResultado = (c: CitaResultado) => c.estado === 'realizada' ? c.asistioEn : `${c.fecha}T${c.hora}:00-05:00`

/** Reglas de gestión completas; sin ellas las tasas quedan «sin base». */
export function reglasListas({ version, mes_inicio, configuracion: config }: Control): boolean {
  return version > 0 && mes_inicio !== null && config.mes_inicio !== null
    && config.mes_resultado !== null && config.analista_resultado !== null && config.base_depositos !== null
    && config.base_avance !== null && config.conteo_entrevistas !== null && config.actividad_manuales !== null
}

/**
 * Leads de la base que cuentan para la meta: asignados en el periodo, de la consulta y sin los manuales propios si
 * la regla los excluye. El lector del mes ya trae solo los asignados en el mes; un rango más corto los recorta.
 */
export const asignadosDeLaMeta = <L extends Pick<LeadBaseCitas, 'leadId' | 'manualPropio' | 'asignadoEn'>>(
  base: readonly L[], personas: ReadonlyMap<string, unknown>, control: Control, { desde, hasta }: Pick<PeriodoComercial, 'desde' | 'hasta'>,
) => base.filter(p => {
  const dia = Number.isFinite(Date.parse(p.asignadoEn)) ? fechaLocalCitas(p.asignadoEn) : ''
  return dia >= desde && dia <= hasta && personas.has(p.leadId) && (!control.configuracion.excluir_manuales_base || !p.manualPropio)
})

export interface AnalistaRoster { id: string; nombre: string; supervisor: string; supervisorId: string }
type Fuente<T> = readonly T[] | undefined
/**
 * Analistas con su nombre y supervisor, de todo lo que llega en la consulta. Si
 * un analista aparece en varias fuentes manda la ÚLTIMA: capital, población de
 * origen, base asignada, citas y ventas. El supervisor decide el ámbito.
 */
export function rosterDeAnalistas(f: {
  capital?: Fuente<{ analista_id: string | null; analista_nombre?: string | null | undefined; supervisor_id?: string | null | undefined; supervisor_nombre?: string | null | undefined }>
  poblacion?: Fuente<{ analista_origen_id?: string | null | undefined; analista_origen_nombre?: string | undefined; supervisor_origen_id?: string | null | undefined; supervisor_origen_nombre?: string | undefined }>
  asignaciones?: Fuente<Pick<LeadBaseCitas, 'id' | 'nombre' | 'supervisor' | 'supervisorId'>>
  citas: readonly Pick<CitaEjemplo, 'analista' | 'analistaNombre' | 'supervisor' | 'supervisorId'>[]
  ventas?: Fuente<{ analista_id: string | null; analista_nombre?: string | undefined; supervisor_id?: string | null | undefined; supervisor_nombre?: string | undefined }>
}): Map<string, AnalistaRoster> {
  const fila = (id: string, nombre: string | null | undefined, supervisor: string | null | undefined, supervisorId: string | null | undefined) =>
    [id, { id, nombre: nombre ?? 'Sin analista', supervisor: supervisor ?? 'Sin supervisor', supervisorId: supervisorId ?? 'sin_supervisor' }] as const
  return new Map([
    ...(f.capital ?? []).flatMap(k => k.analista_id ? [fila(k.analista_id, k.analista_nombre, k.supervisor_nombre, k.supervisor_id)] : []),
    ...(f.poblacion ?? []).flatMap(p => p.analista_origen_id ? [fila(p.analista_origen_id, p.analista_origen_nombre, p.supervisor_origen_nombre, p.supervisor_origen_id)] : []),
    ...(f.asignaciones ?? []).map(a => fila(a.id, a.nombre, a.supervisor, a.supervisorId)),
    ...f.citas.map(c => fila(c.analista, c.analistaNombre, c.supervisor, c.supervisorId)),
    ...(f.ventas ?? []).flatMap(c => c.analista_id ? [fila(c.analista_id, c.analista_nombre, c.supervisor_nombre, c.supervisor_id)] : []),
  ])
}

export interface EntradaResultados<C extends CitaResultado, V extends VentaResultado> {
  citas: readonly C[]
  ventas: readonly V[]
  /** Personas (leads) que admite la consulta. */
  personas: ReadonlyMap<string, PersonaResultado>
  /** Identidad de la persona del lead: el cliente cuenta una vez aunque tenga varios leads. */
  identidad: (lead: string) => string
  control: Control
  periodo: PeriodoComercial
  /** Analistas de la consulta (`enAmbito`). */
  ambito: (analista: string | null) => boolean
}

export function resultadosDelPeriodo<C extends CitaResultado, V extends VentaResultado>(e: EntradaResultados<C, V>) {
  const config = e.control.configuracion
  const listas = reglasListas(e.control)
  const corte = Date.parse(e.periodo.corte)
  const dueno = reglaDueno(config.analista_resultado, lead => e.personas.get(lead)?.analista_origen_id)
  const actividad = (lead: string, id: string | null) => {
    const p = e.personas.get(lead)
    return p !== undefined && (config.actividad_manuales === 'incluir' || !p.registro_manual || p.creado_por !== id)
  }
  const enPeriodo = (instante: string) => {
    const dia = fechaLocalCitas(instante)
    return dia >= e.periodo.desde && dia <= e.periodo.hasta
  }
  // «asignacion»: los resultados de los leads asignados por primera vez en el periodo, hasta el corte.
  const delPeriodo = (p: PersonaResultado, fecha: string) => config.mes_resultado === 'asignacion'
    ? p.primera_asignacion_en !== null && enPeriodo(p.primera_asignacion_en) : enPeriodo(fecha)
  const resueltas = e.citas.filter(c => {
    const fecha = fechaResultado(c)
    const suyo = dueno(c.leadId, c.analista)
    return (c.estado === 'realizada' || c.estado === 'no_show') && fecha !== undefined
      && e.personas.has(c.leadId) && e.ambito(suyo) && actividad(c.leadId, suyo)
      && Date.parse(fecha) <= corte && delPeriodo(e.personas.get(c.leadId)!, fecha)
  })
  const entrevistas = resueltas.filter(c => c.estado === 'realizada')
  const cierres = e.ventas.filter(c => e.personas.has(c.lead_id)
    && e.ambito(dueno(c.lead_id, c.analista_id)) && actividad(c.lead_id, dueno(c.lead_id, c.analista_id))
    && ventaComercialDelPeriodo(c, e.periodo))

  /**
   * Tasas de un analista o, sin él, del total del ámbito. `leads`: base de la meta
   * (regla «meta_proyectada»). `duenos` acota las citas del total a esos analistas
   * (filas visibles); las ventas siguen siendo las del ámbito.
   */
  function medir(analista?: string, leads = 0, duenos?: ReadonlySet<string>) {
    const suya = (id: string | null) => analista ? id === analista : !duenos || (id !== null && duenos.has(id))
    const resultado = resueltas.filter(c => suya(dueno(c.leadId, c.analista)))
    const visitas = entrevistas.filter(c => suya(dueno(c.leadId, c.analista)))
    const gente = new Set(visitas.map(c => e.identidad(c.leadId)))
    const ventas = cierres.filter(c => !analista || dueno(c.lead_id, c.analista_id) === analista)
    // Cada fila compara entrevistas propias. El total del ámbito reconoce
    // también la colaboración entre analistas incluidos en la consulta.
    const cierra = (v: C, venta: V) => e.identidad(v.leadId) === e.identidad(venta.lead_id)
      && ventaCierraEntrevista(v.asistioEn, { dueno: dueno(venta.lead_id, venta.analista_id), fecha_comercial: venta.fecha_comercial ?? null }, analista || null)
    const vinculados = ventas.filter(venta => visitas.some(v => cierra(v, venta)))
    const clientes = new Set(vinculados.map(c => e.identidad(c.lead_id))).size
    const nEntrevistas = config.conteo_entrevistas === 'personas_unicas' ? gente.size : visitas.length
    const baseEntrevistas = config.base_avance === 'meta_proyectada' ? leads * config.citas_por_lead : resultado.length
    const baseConversion = config.base_depositos === 'entrevistas' ? visitas.length : gente.size
    return {
      resultado, visitas, gente, ventas, vinculados, clientes, nEntrevistas, baseEntrevistas, baseConversion,
      /** Las entrevistas que cerraron una de esas ventas. */
      visitasVinculadas: visitas.filter(v => vinculados.some(venta => cierra(v, venta))),
      tasaEntrevistas: listas && baseEntrevistas ? nEntrevistas / baseEntrevistas : null,
      conversion: listas && baseConversion ? clientes / baseConversion : null,
    }
  }
  return { listas, dueno, actividad, resueltas, entrevistas, cierres, medir }
}
