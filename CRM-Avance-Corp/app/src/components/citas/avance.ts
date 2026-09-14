import { normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
import { baseCitasFiltrada, type GestionCitas } from './metas'
import type { GestionMensualCitas } from '@/lib/gestion-citas'

type Persona = GestionMensualCitas['poblacion'][number]
const instanteCita = (c: CitaEjemplo) => Date.parse(`${c.fecha}T${c.hora}:00-05:00`)
// El registro de entrevista acredita la relación; la fecha prevista sola no.
const instanteEntrevista = (c: CitaEjemplo) => c.asistioEn ? Date.parse(c.asistioEn) : Number.POSITIVE_INFINITY
const fechaResultado = (c: CitaEjemplo) => c.estado === 'realizada' ? c.asistioEn : `${c.fecha}T${c.hora}:00-05:00`
export const fechaLocalCitas = (fecha: string) => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date(fecha))
export function periodoAvance(mes: string, corte: string) {
  const [anio, numero] = mes.split('-').map(Number)
  const dias = new Date(Date.UTC(anio!, numero!, 0)).getUTCDate()
  const inicio = Date.parse(`${mes}-01T00:00:00-05:00`)
  const fin = Date.parse(`${mes}-${dias}T23:59:59.999-05:00`)
  const ahora = Date.parse(corte)
  const transcurridos = ahora < inicio ? 0 : ahora > fin ? dias : Number(fechaLocalCitas(corte).slice(8))
  return { inicio, fin, corte: Math.min(ahora, fin), dias, transcurridos, cerrado: ahora > fin,
    ritmo: transcurridos ? transcurridos / dias * 100 : null }
}

/** Filtros de población; un estado de cita nunca recorta el divisor de una tasa. */
function coincidePersona(p: Persona, f: FiltrosCitas, todas: CitaEjemplo[]) {
  const q = normalizar(f.q)
  const texto = normalizar(`${p.nombre} ${p.telefono} ${p.lead_id}`)
  const codigoCita = q && todas.some(c => c.leadId === p.lead_id && normalizar(c.id) === q)
  const busqueda = !q || q.split(/\s+/).every(parte => texto.includes(parte)) || codigoCita
    || (/^[\d\s+()-]+$/.test(f.q) && f.q.replace(/\D/g, '').length > 2 && p.telefono.replace(/\D/g, '').includes(f.q.replace(/\D/g, '')))
  return busqueda && (!f.leadId || f.leadId === p.lead_id)
    && (!f.origen || normalizar(p.origen.replaceAll('_', ' ')) === normalizar(f.origen))
    && (!f.registro || p.registro_manual === (f.registro === 'manual'))
    && (!f.moneda || f.moneda === p.moneda)
    && (!f.moneda || f.min === '' || p.monto_estimado >= Number(f.min))
    && (!f.moneda || f.max === '' || p.monto_estimado <= Number(f.max))
}

/** Métricas sobre hechos del servidor. No introduce personas ni importes demo. */
export function calcularAvanceCitas(gestion: GestionCitas, todas: CitaEjemplo[], filtros: FiltrosCitas, corte: string, moneda: 'PEN' | 'USD') {
  const datos = gestion.avance!
  const config = datos.control.configuracion
  const periodo = periodoAvance(filtros.mes, corte)
  const personas = new Map(datos.poblacion.filter(p => coincidePersona(p, filtros, todas)).map(p => [p.lead_id, p]))
  const roster = new Map([
    ...datos.poblacion.filter(p => p.analista_origen_id).map(p => [p.analista_origen_id!, {
      id: p.analista_origen_id!, nombre: p.analista_origen_nombre,
      supervisor: p.supervisor_origen_nombre, supervisorId: p.supervisor_origen_id ?? 'sin_supervisor',
    }] as const),
    ...gestion.asignaciones.map(a => [a.id, { id: a.id, nombre: a.nombre, supervisor: a.supervisor, supervisorId: a.supervisorId }] as const),
    ...todas.map(c => [c.analista, { id: c.analista, nombre: c.analistaNombre, supervisor: c.supervisor, supervisorId: c.supervisorId }] as const),
    ...datos.conversiones.filter(c => c.analista_id).map(c => [c.analista_id!, { id: c.analista_id!, nombre: c.analista_nombre, supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor' }] as const),
  ])
  const ambito = (id: string | null) => id !== null && (!filtros.analista || id === filtros.analista)
    && (!filtros.equipo || roster.get(id)?.supervisorId === filtros.equipo)
  const owner = (lead: string, evento: string | null) => config.analista_resultado === 'asignacion'
    ? personas.get(lead)?.analista_origen_id ?? null : evento
  const mesResultado = (p: Persona, fecha: string) => config.mes_resultado === 'asignacion'
    ? p.primera_asignacion_en !== null && fechaLocalCitas(p.primera_asignacion_en).startsWith(filtros.mes)
    : fechaLocalCitas(fecha).startsWith(filtros.mes)
  const limiteResultado = config.mes_resultado === 'asignacion' ? Date.parse(corte) : periodo.corte
  const actividad = (lead: string, id: string | null) => {
    const p = personas.get(lead)
    return p && (config.actividad_manuales === 'incluir' || !p.registro_manual || p.creado_por !== id)
  }
  const asignados = baseCitasFiltrada(gestion.asignaciones, { ...filtros, q: '' })
    .filter(p => personas.has(p.leadId) && (!config.excluir_manuales_base || !p.manualPropio))
  const registradas = todas.filter(c => c.creadoEn && personas.has(c.leadId) && ambito(c.analista)
    && actividad(c.leadId, c.analista) && Date.parse(c.creadoEn) >= periodo.inicio && Date.parse(c.creadoEn) <= periodo.corte)
  const resueltas = todas.filter(c => ['realizada', 'no_show'].includes(c.estado) && fechaResultado(c)
    && personas.has(c.leadId) && ambito(owner(c.leadId, c.analista)) && actividad(c.leadId, owner(c.leadId, c.analista))
    && Date.parse(fechaResultado(c)!) <= limiteResultado && mesResultado(personas.get(c.leadId)!, fechaResultado(c)!))
  const entrevistas = resueltas.filter(c => c.estado === 'realizada')
  const cierres = datos.conversiones.filter(c => personas.has(c.lead_id)
    && ambito(owner(c.lead_id, c.analista_id)) && actividad(c.lead_id, owner(c.lead_id, c.analista_id))
    && Date.parse(c.convertido_en) <= limiteResultado && mesResultado(personas.get(c.lead_id)!, c.convertido_en))
  const reglasListas = config.mes_resultado !== null && config.analista_resultado !== null && config.base_depositos !== null
    && config.base_avance !== null && config.conteo_entrevistas !== null && config.actividad_manuales !== null
  const resultados = (id?: string) => {
    const base = asignados.filter(p => !id || p.id === id)
    const citas = registradas.filter(c => !id || c.analista === id)
    const resultado = resueltas.filter(c => !id || owner(c.leadId, c.analista) === id)
    const visitas = entrevistas.filter(c => !id || owner(c.leadId, c.analista) === id)
    const gente = new Set(visitas.map(c => c.leadId))
    const clientesMes = cierres.filter(c => !id || owner(c.lead_id, c.analista_id) === id)
    // Relación verificable con las entrevistas del mismo responsable. Un
    // cierre transferido sin entrevista propia conserva su cantidad aparte.
    const vinculados = clientesMes.filter(c => visitas.some(v => v.leadId === c.lead_id
      && owner(v.leadId, v.analista) === owner(c.lead_id, c.analista_id)
      && instanteEntrevista(v) <= Date.parse(c.convertido_en)))
    const clientes = new Set(vinculados.map(c => c.perfil_id)).size
    const fuera = new Set(clientesMes.filter(c => !vinculados.includes(c)).map(c => c.perfil_id)).size
    const leads = new Set(base.map(p => p.leadId)).size
    const nEntrevistas = config.conteo_entrevistas === 'personas_unicas' ? gente.size : visitas.length
    const baseEntrevistas = config.base_avance === 'meta_proyectada' ? leads * config.citas_por_lead : resultado.length
    const baseConversion = config.base_depositos === 'entrevistas' ? visitas.length : gente.size
    const tasaEntrevistas = reglasListas && baseEntrevistas ? nEntrevistas / baseEntrevistas : null
    const conversion = reglasListas && baseConversion ? clientes / baseConversion : null
    // El ticket es mensual aunque el seguimiento esté configurado por cohorte.
    const cierresTicket = datos.conversiones.filter(c => personas.has(c.lead_id) && ambito(c.analista_id)
      && (!id || c.analista_id === id) && actividad(c.lead_id, c.analista_id)
      && Date.parse(c.convertido_en) >= periodo.inicio && Date.parse(c.convertido_en) <= periodo.corte)
    const capital = datos.capital.filter(k => k.moneda === moneda && (!id || k.analista_id === id)
      && cierresTicket.some(c => c.perfil_id === k.perfil_id && c.analista_id === k.analista_id))
    const capitalPerfiles = new Set(capital.map(k => k.perfil_id))
    const sinImporte = new Set(cierresTicket.filter(c => !datos.capital.some(k => k.perfil_id === c.perfil_id)).map(c => c.perfil_id)).size
    const atribucionPendiente = new Set(cierresTicket.filter(c => datos.capital.some(k => k.perfil_id === c.perfil_id && k.analista_id !== c.analista_id)).map(c => c.perfil_id)).size
    const otraMoneda = cierresTicket.some(c => datos.capital.some(k => k.perfil_id === c.perfil_id && k.moneda !== moneda))
    const monto = capital.reduce((n, k) => n + k.monto, 0)
    const ticket = capitalPerfiles.size && !sinImporte && !atribucionPendiente ? monto / capitalPerfiles.size : null
    const tasaObservada = resultado.length ? visitas.length / resultado.length : null
    const clientesReales = new Set(cierresTicket.map(c => c.perfil_id)).size
    // Generar una cita para otro mes suma cumplimiento, pero no acelera este cierre.
    const citasDelCierre = citas.filter(c => instanteCita(c) >= periodo.inicio && instanteCita(c) <= periodo.fin)
    const poblacion = new Set([...citasDelCierre.map(c => c.leadId), ...visitas.map(v => v.leadId), ...cierresTicket.map(c => c.lead_id)])
    const citasEsperadas = periodo.transcurridos ? citasDelCierre.length / periodo.transcurridos * periodo.dias : null
    const entrevistasEsperadas = citasEsperadas !== null && tasaObservada !== null ? citasEsperadas * tasaObservada : null
    const personasEsperadas = entrevistasEsperadas !== null && visitas.length
      ? Math.min(poblacion.size, entrevistasEsperadas * gente.size / visitas.length) : null
    const clientesEsperados = conversion !== null && personasEsperadas !== null && entrevistasEsperadas !== null
      ? Math.max(clientesReales, clientes, Math.min(personasEsperadas, (config.base_depositos === 'entrevistas' ? entrevistasEsperadas : personasEsperadas) * conversion)) : null
    const motivoProyeccion = !reglasListas ? 'Completa las reglas de gestión'
      : otraMoneda ? 'Hay clientes que invirtieron en otra moneda' : sinImporte ? 'Faltan importes reales del mes'
        : atribucionPendiente ? 'Revisa la atribución de capital al analista'
        : ticket === null ? 'Sin clientes con importe en el mes' : clientesEsperados === null ? 'Sin base de entrevistas' : null
    const proyeccion = motivoProyeccion === null && ticket !== null && clientesEsperados !== null
      ? periodo.cerrado ? monto : Math.max(monto, clientesEsperados * ticket) : null
    return { leads, citas: citas.length, promedio: leads ? citas.length / leads : null,
      cumplimiento: leads ? citas.length / (leads * config.citas_por_lead) * 100 : null,
      entrevistas: visitas.length, unicas: gente.size, resueltas: resultado.length, baseEntrevistas,
      tasaEntrevistas, conversion, clientes, clientesFueraCohorte: fuera, baseConversion,
      ticket, capital: monto, clientesTicket: capitalPerfiles.size, sinImporte, atribucionPendiente, proyeccion, clientesEsperados, motivoProyeccion,
      manuales: base.filter(p => p.registroManual ?? p.manualPropio).length,
      sinCita: base.filter(p => !citas.some(c => c.leadId === p.leadId)),
      base, actividad: citas, visitas, vinculados, reglasListas }
  }
  const ids = new Set([...asignados.map(p => p.id), ...registradas.map(c => c.analista),
    ...resueltas.map(c => owner(c.leadId, c.analista)), ...cierres.map(c => owner(c.lead_id, c.analista_id))])
  const filas = [...roster.values()].filter(a => ids.has(a.id) && ambito(a.id))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')).map(a => ({ ...a, ...resultados(a.id) }))
  const calculables = filas.filter(f => f.proyeccion !== null)
  const total = { ...resultados(), proyeccion: calculables.length ? calculables.reduce((n, f) => n + f.proyeccion!, 0) : null,
    parciales: calculables.length, analistas: filas.length }
  return { filas, total, periodo, config, reglasListas, version: datos.control.version }
}
export type AvanceCitas = ReturnType<typeof calcularAvanceCitas>
export type FilaAvanceCitas = AvanceCitas['filas'][number]
