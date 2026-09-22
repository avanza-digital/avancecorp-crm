import { normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
import { baseCitasFiltrada, type GestionCitas } from './metas'
import type { GestionMensualCitas } from '@/lib/gestion-citas'
import { totalEnSoles, tcAplicable } from '@/lib/capital-unificado'

type Persona = GestionMensualCitas['poblacion'][number]
type Capital = GestionMensualCitas['capital'][number]
const TIPOS_CAPITAL = { contrato_nuevo: 'nuevos', contrato_upgrade: 'upgrades', contrato_renovacion: 'renovaciones', cooperativa: 'cooperativas' } as const
export type OperacionesCapital = Record<(typeof TIPOS_CAPITAL)[keyof typeof TIPOS_CAPITAL], number>
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
export function calcularAvanceCitas(gestion: GestionCitas, todas: CitaEjemplo[], filtros: FiltrosCitas, corte: string, tipoCambio: number | null | undefined) {
  const datos = gestion.avance!
  const config = datos.control.configuracion
  const perfiles = new Map(datos.conversiones.map(c => [c.lead_id, c.perfil_id]))
  const identidades = new Map(datos.poblacion.map(p => [p.lead_id,
    p.identidad_persona ?? (perfiles.has(p.lead_id) ? `perfil:${perfiles.get(p.lead_id)}` : `lead:${p.lead_id}`)]))
  const personaEntrevistada = (lead: string) => identidades.get(lead) ?? `lead:${lead}`
  // El capital se cuenta por persona: identidad canónica del servidor o, si falta,
  // la del lead vinculado, el perfil cliente o el cierre externo.
  const personaCapital = (k: Capital) => k.identidad_persona ?? (k.lead_id && identidades.has(k.lead_id) ? identidades.get(k.lead_id)!
    : k.perfil_id ? `perfil:${k.perfil_id}` : k.lead_id ? `lead:${k.lead_id}` : `externo:${k.cierre_externo_id}`)
  const periodo = periodoAvance(filtros.mes, corte)
  const personas = new Map(datos.poblacion.filter(p => coincidePersona(p, filtros, todas)).map(p => [p.lead_id, p]))
  const roster = new Map([
    ...datos.capital.filter(k => k.analista_id).map(k => [k.analista_id!, {
      id: k.analista_id!, nombre: k.analista_nombre ?? 'Sin analista',
      supervisor: k.supervisor_nombre ?? 'Sin supervisor', supervisorId: k.supervisor_id ?? 'sin_supervisor',
    }] as const),
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
  // Todo el capital del mes cuenta para el ticket: contratos nuevos, upgrades,
  // renovaciones y cooperativas, atribuidos al analista del núcleo (Miguel,
  // 15/09/2026: «nada debe quedar fuera»). No exige que el cliente venga de un
  // lead. Los filtros de persona, origen, registro y moneda estimada acotan el
  // capital a los leads que los cumplen; sin ellos entra todo lo cerrado.
  const acotaPersonas = Boolean(normalizar(filtros.q) || filtros.leadId || filtros.origen || filtros.registro || filtros.moneda)
  const capitalPeriodo = datos.capital.filter(k => (!acotaPersonas || (k.lead_id !== null && personas.has(k.lead_id)))
    && Date.parse(k.fecha) >= periodo.inicio && Date.parse(k.fecha) <= periodo.fin)
  const capitalMes = capitalPeriodo.filter(k => ambito(k.analista_id))
  // Personas con capital en el mes, antes del recorte por analista o equipo: un
  // cliente convertido por Ana cuyo contrato firmó Luis no «carece» de capital.
  const conCapital = new Set(capitalPeriodo.map(personaCapital))
  const reglasListas = datos.control.version > 0 && datos.control.mes_inicio !== null && config.mes_inicio !== null
    && config.mes_resultado !== null && config.analista_resultado !== null && config.base_depositos !== null
    && config.base_avance !== null && config.conteo_entrevistas !== null && config.actividad_manuales !== null
  const resultados = (id?: string) => {
    const base = asignados.filter(p => !id || p.id === id)
    const citas = registradas.filter(c => !id || c.analista === id)
    const resultado = resueltas.filter(c => !id || owner(c.leadId, c.analista) === id)
    const visitas = entrevistas.filter(c => !id || owner(c.leadId, c.analista) === id)
    const gente = new Set(visitas.map(c => personaEntrevistada(c.leadId)))
    const clientesMes = cierres.filter(c => !id || owner(c.lead_id, c.analista_id) === id)
    // Cada fila compara entrevistas propias. El total del ámbito reconoce
    // también la colaboración entre analistas incluidos en la consulta.
    const vinculados = clientesMes.filter(c => visitas.some(v => personaEntrevistada(v.leadId) === personaEntrevistada(c.lead_id)
      && (!id || owner(v.leadId, v.analista) === owner(c.lead_id, c.analista_id))
      && instanteEntrevista(v) <= Date.parse(c.convertido_en)))
    const perfilesVinculados = new Set(vinculados.map(c => personaEntrevistada(c.lead_id)))
    const clientes = perfilesVinculados.size
    const clientesPeriodo = new Set(clientesMes.map(c => personaEntrevistada(c.lead_id))).size
    const fuera = new Set(clientesMes.filter(c => !perfilesVinculados.has(personaEntrevistada(c.lead_id))).map(c => personaEntrevistada(c.lead_id))).size
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
    const capital = capitalMes.filter(k => !id || k.analista_id === id)
    const capitalPerfiles = new Set(capital.map(personaCapital))
    const operaciones: OperacionesCapital = { nuevos: 0, upgrades: 0, renovaciones: 0, cooperativas: 0 }
    for (const k of capital) operaciones[TIPOS_CAPITAL[k.tipo ?? 'contrato_nuevo']]++
    // Un cliente convertido sin capital en el mes ya no anula el ticket: se informa aparte.
    const sinContrato = new Set(cierresTicket.map(c => personaEntrevistada(c.lead_id)).filter(p => !conCapital.has(p))).size
    const capitalPen = capital.filter(k => k.moneda === 'PEN').reduce((n, k) => n + k.monto, 0)
    const capitalUsd = capital.filter(k => k.moneda === 'USD').reduce((n, k) => n + k.monto, 0)
    const unificado = totalEnSoles(capitalPen, capitalUsd, tipoCambio)
    const faltaTipoCambio = capitalUsd > 0 && unificado.tc === null
    // Un promedio parcial excluiría dinero de clientes que sí están en el divisor.
    const monto = faltaTipoCambio ? null : unificado.total
    const ticket = monto !== null && capitalPerfiles.size ? monto / capitalPerfiles.size : null
    const motivoTicket = faltaTipoCambio ? 'Falta el tipo de cambio para incluir dólares'
      : ticket === null ? 'Sin capital cerrado en el mes' : null
    const tasaObservada = resultado.length ? visitas.length / resultado.length : null
    const clientesReales = new Set(cierresTicket.map(c => personaEntrevistada(c.lead_id))).size
    // Generar una cita para otro mes suma cumplimiento, pero no acelera este cierre.
    const citasDelCierre = citas.filter(c => instanteCita(c) >= periodo.inicio && instanteCita(c) <= periodo.fin)
    const poblacion = new Set([...citasDelCierre.map(c => c.leadId), ...visitas.map(v => v.leadId), ...cierresTicket.map(c => c.lead_id)].map(personaEntrevistada))
    const citasEsperadas = periodo.transcurridos ? citasDelCierre.length / periodo.transcurridos * periodo.dias : null
    const entrevistasEsperadas = citasEsperadas !== null && tasaObservada !== null ? citasEsperadas * tasaObservada : null
    const personasEsperadas = entrevistasEsperadas !== null && visitas.length
      ? Math.min(poblacion.size, entrevistasEsperadas * gente.size / visitas.length) : null
    const clientesEsperados = conversion !== null && personasEsperadas !== null && entrevistasEsperadas !== null
      ? Math.max(clientesReales, clientes, Math.min(personasEsperadas, (config.base_depositos === 'entrevistas' ? entrevistasEsperadas : personasEsperadas) * conversion)) : null
    // Cierre proyectado = capital ya cerrado + clientes que aún se esperan del flujo
    // de citas × ticket. En un mes cerrado es el capital realizado, con o sin
    // entrevistas: el dinero conocido no depende de la base para pronosticar.
    const motivoProyeccion = faltaTipoCambio ? 'Falta el tipo de cambio para incluir dólares'
      : periodo.cerrado ? null
        : !reglasListas ? 'Completa las reglas de gestión'
          : ticket === null ? 'Sin capital cerrado en el mes'
            : clientesEsperados === null ? 'Sin base de entrevistas' : null
    const proyeccion = monto === null || motivoProyeccion !== null ? null
      : periodo.cerrado ? monto
        : monto + Math.max(0, clientesEsperados! - clientesReales) * ticket!
    return { leads, citas: citas.length, promedio: leads ? citas.length / leads : null,
      cumplimiento: leads ? citas.length / (leads * config.citas_por_lead) * 100 : null,
      entrevistas: visitas.length, unicas: gente.size, resueltas: resultado.length, baseEntrevistas,
      tasaEntrevistas, conversion, clientes, clientesPeriodo, clientesFueraCohorte: fuera, baseConversion,
      ticket, motivoTicket, capital: monto, capitalPen, capitalUsd, faltaTipoCambio,
      clientesTicket: capitalPerfiles.size, sinContrato, operaciones, proyeccion, clientesEsperados, motivoProyeccion,
      manuales: base.filter(p => p.registroManual ?? p.manualPropio).length,
      sinCita: base.filter(p => !citas.some(c => c.leadId === p.leadId)),
      base, actividad: citas, visitas, vinculados, cierres: clientesMes, reglasListas }
  }
  // Un analista con capital en el mes tiene fila aunque no tenga leads ni citas.
  const ids = new Set([...asignados.map(p => p.id), ...registradas.map(c => c.analista),
    ...resueltas.map(c => owner(c.leadId, c.analista)), ...cierres.map(c => owner(c.lead_id, c.analista_id)),
    ...capitalMes.map(k => k.analista_id)])
  const filas = [...roster.values()].filter(a => ids.has(a.id) && ambito(a.id))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')).map(a => ({ ...a, ...resultados(a.id) }))
  const calculables = filas.filter(f => f.proyeccion !== null)
  const total = { ...resultados(), proyeccion: calculables.length ? calculables.reduce((n, f) => n + f.proyeccion!, 0) : null,
    parciales: calculables.length, analistas: filas.length }
  // TESTIGO (F2, 21/09/2026). Sin ningún filtro puesto, el total de arriba tiene
  // que coincidir con lo que el servidor calculó por su cuenta. `null` = no
  // aplica (hay filtros, o el servidor aún no manda testigo). `false` = las
  // dos contabilidades discrepan: el número no se publica.
  const sinFiltros = !normalizar(filtros.q) && !filtros.leadId && !filtros.origen && !filtros.registro
    && !filtros.moneda && !filtros.analista && !filtros.equipo
  const testigo = gestion.testigo
  const testigoCuadra = !testigo || !sinFiltros ? null
    : testigo.reglas_listas === reglasListas
      && testigo.entrevistas === total.entrevistas
      && testigo.personas_entrevistadas === total.unicas
      && testigo.clientes_periodo === total.clientesPeriodo
      && testigo.clientes_vinculados === total.clientes
      && testigo.base_conversion === total.baseConversion
  return { filas, total, periodo, config, reglasListas, version: datos.control.version,
    tc: total.capitalUsd > 0 ? tcAplicable(tipoCambio) : null, testigoCuadra }
}
export type AvanceCitas = ReturnType<typeof calcularAvanceCitas>
export type FilaAvanceCitas = AvanceCitas['filas'][number]
