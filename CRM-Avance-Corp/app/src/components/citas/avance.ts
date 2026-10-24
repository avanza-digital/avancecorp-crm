import { fusionarPersonas, normalizar, type CitaEjemplo, type EstadoAnalista, type FiltrosCitas, type PersonaCitas } from './modelo'
import { baseCitasFiltrada, type GestionCitas } from './metas'
import type { GestionMensualCitasConEstado as GestionMensualCitas } from './gestion-estado'
import { totalEnSoles, tcAplicable } from '@/lib/capital-unificado'
import { fechaLocalCitas, ventaComercialDelMes } from './fecha-comercial'
import { enAmbito } from './atribucion'
import { asignadosDeLaMeta, resultadosDelPeriodo, rosterDeAnalistas } from './resultados-periodo'
export { fechaLocalCitas } from './fecha-comercial'

type Persona = GestionMensualCitas['poblacion'][number]
type Capital = GestionMensualCitas['capital'][number]
const TIPOS_CAPITAL = { contrato_nuevo: 'nuevos', contrato_upgrade: 'upgrades', contrato_renovacion: 'renovaciones', cooperativa: 'cooperativas' } as const
export type OperacionesCapital = Record<(typeof TIPOS_CAPITAL)[keyof typeof TIPOS_CAPITAL], number>
const instanteCita = (c: CitaEjemplo) => Date.parse(`${c.fecha}T${c.hora}:00-05:00`)
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
    && (!f.moneda || f.min === '' || (p.monto_estimado != null && p.monto_estimado >= Number(f.min)))
    && (!f.moneda || f.max === '' || (p.monto_estimado != null && p.monto_estimado <= Number(f.max)))
}

/** Métricas sobre hechos del servidor. No introduce personas ni importes demo. */
export function calcularAvanceCitas(gestion: GestionCitas, todas: CitaEjemplo[], filtros: FiltrosCitas, corte: string, tipoCambio: number | null | undefined) {
  const datos = gestion.avance!
  const valoracion = datos.valoracion
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
  // Nombre y supervisor: la regla compartida con la Proyección (`rosterDeAnalistas`: manda la última fuente).
  // D-53 (bloque 2.14): encima, el estado de hoy del analista. Cada fuente lo trae y la fusión lo conserva aunque una
  // fuente posterior no lo traiga (`fusionarPersonas`); el nombre y el supervisor siguen siendo los del roster compartido.
  const nombres = rosterDeAnalistas({ capital: datos.capital, poblacion: datos.poblacion, asignaciones: gestion.asignaciones, citas: todas, ventas: datos.conversiones })
  const estados: (readonly [string | null, EstadoAnalista | undefined])[] = [
    ...datos.capital.map(k => [k.analista_id, k.analista_estado] as const),
    ...datos.poblacion.map(p => [p.analista_origen_id, p.analista_origen_estado] as const),
    ...gestion.asignaciones.map(a => [a.id, a.estado] as const),
    ...todas.map(c => [c.analista, c.analistaEstado] as const),
    ...datos.conversiones.map(c => [c.analista_id, c.analista_estado] as const),
  ]
  const roster = new Map(fusionarPersonas<PersonaCitas>([
    ...nombres.values(),
    ...estados.flatMap(([id, estado]) => { const a = id ? nombres.get(id) : undefined; return a && estado ? [{ ...a, estado }] : [] }),
  ]).map(p => [p.id, p] as const))
  const alcance = { analistas: filtros.analista ? new Set([filtros.analista]) : null, equipo: filtros.equipo, supervisorDe: (id: string) => roster.get(id)?.supervisorId }
  const ambito = (id: string | null) => enAmbito(id, alcance)
  // Citas con resultado, ventas y tasas del mes: la regla compartida con la Proyección.
  const delPeriodo = { desde: `${filtros.mes}-01`, hasta: `${filtros.mes}-${String(periodo.dias).padStart(2, '0')}`, corte }
  const delMes = resultadosDelPeriodo({ citas: todas, ventas: datos.conversiones, personas, identidad: personaEntrevistada,
    control: datos.control, periodo: delPeriodo, ambito })
  const { dueno: owner, actividad, resueltas, cierres, listas: reglasListas } = delMes
  const asignados = asignadosDeLaMeta(baseCitasFiltrada(gestion.asignaciones, { ...filtros, q: '' }), personas, datos.control, delPeriodo)
  const registradas = todas.filter(c => c.creadoEn && personas.has(c.leadId) && ambito(c.analista)
    && actividad(c.leadId, c.analista) && Date.parse(c.creadoEn) >= periodo.inicio && Date.parse(c.creadoEn) <= periodo.corte)
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
  const resultados = (id?: string) => {
    const base = asignados.filter(p => !id || p.id === id)
    const citas = registradas.filter(c => !id || c.analista === id)
    const leads = new Set(base.map(p => p.leadId)).size
    const { resultado, visitas, gente, ventas: clientesMes, vinculados, clientes, baseEntrevistas, baseConversion, tasaEntrevistas, conversion } = delMes.medir(id, leads)
    const perfilesVinculados = new Set(vinculados.map(c => personaEntrevistada(c.lead_id)))
    const clientesPeriodo = new Set(clientesMes.map(c => personaEntrevistada(c.lead_id))).size
    const fuera = new Set(clientesMes.filter(c => !perfilesVinculados.has(personaEntrevistada(c.lead_id))).map(c => personaEntrevistada(c.lead_id))).size
    // El ticket es mensual aunque el seguimiento esté configurado por cohorte.
    const cierresTicket = datos.conversiones.filter(c => personas.has(c.lead_id) && ambito(c.analista_id)
      && (!id || c.analista_id === id) && actividad(c.lead_id, c.analista_id)
      && ventaComercialDelMes(c, filtros.mes, corte))
    const capital = capitalMes.filter(k => !id || k.analista_id === id)
    const capitalPerfiles = new Set(capital.map(personaCapital))
    const operaciones: OperacionesCapital = { nuevos: 0, upgrades: 0, renovaciones: 0, cooperativas: 0 }
    for (const k of capital) operaciones[TIPOS_CAPITAL[k.tipo ?? 'contrato_nuevo']]++
    // Un cliente convertido sin capital en el mes ya no anula el ticket: se informa aparte.
    const sinContrato = new Set(cierresTicket.map(c => personaEntrevistada(c.lead_id)).filter(p => !conCapital.has(p))).size
    const capitalPen = capital.filter(k => k.moneda === 'PEN').reduce((n, k) => n + k.monto, 0)
    const capitalUsd = capital.filter(k => k.moneda === 'USD').reduce((n, k) => n + k.monto, 0)
    const unificado = valoracion ? null : totalEnSoles(capitalPen, capitalUsd, tipoCambio)
    const faltaTipoCambio = !valoracion && capitalUsd > 0 && unificado?.tc === null
    const capitalPendiente = valoracion !== undefined && (valoracion.corte_id === null
      || capital.some(k => k.equivalente_pen === undefined))
    // Un promedio parcial excluiría dinero de clientes que sí están en el divisor.
    const monto = valoracion ? capitalPendiente ? null
      : capital.reduce((n, k) => n + Math.round(k.equivalente_pen! * 100), 0) / 100
      : faltaTipoCambio ? null : unificado!.total
    const ticket = monto !== null && capitalPerfiles.size ? monto / capitalPerfiles.size : null
    const motivoTicket = capitalPendiente ? 'Pendiente de la primera publicación de capital valorado'
      : faltaTipoCambio ? 'Falta el tipo de cambio para incluir dólares'
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
    const motivoProyeccion = capitalPendiente ? motivoTicket
      : faltaTipoCambio ? 'Falta el tipo de cambio para incluir dólares'
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
      ticket, motivoTicket, capital: monto, capitalPen, capitalUsd, faltaTipoCambio, capitalPendiente,
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
  const diferenciasTestigo = !testigo || !sinFiltros ? [] : [
    { campo: 'Reglas aplicadas', pantalla: reglasListas, servidor: testigo.reglas_listas },
    { campo: 'Entrevistas', pantalla: total.entrevistas, servidor: testigo.entrevistas },
    { campo: 'Personas entrevistadas', pantalla: total.unicas, servidor: testigo.personas_entrevistadas },
    { campo: 'Clientes del mes comercial', pantalla: total.clientesPeriodo, servidor: testigo.clientes_periodo },
    { campo: 'Clientes vinculados a entrevistas', pantalla: total.clientes, servidor: testigo.clientes_vinculados },
    { campo: 'Base del porcentaje', pantalla: total.baseConversion, servidor: testigo.base_conversion },
  ].filter(d => d.pantalla !== d.servidor)
  const testigoCuadra = !testigo || !sinFiltros ? null : diferenciasTestigo.length === 0

  return { filas, total, periodo, config, reglasListas, version: datos.control.version,
    tc: !valoracion && total.capitalUsd > 0 ? tcAplicable(tipoCambio) : null, valoracion, testigoCuadra, diferenciasTestigo }
}
export type AvanceCitas = ReturnType<typeof calcularAvanceCitas>
export type FilaAvanceCitas = AvanceCitas['filas'][number]
