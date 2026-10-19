// Proyección de citas por analista (Gerencia y Supervisión). Módulo PURO: sin
// React ni red, para que cada cifra de la hoja se pruebe con datos fijos.
//
// Cohorte: las citas cuya FECHA DE CREACIÓN (día de Lima) cae en el rango
// Desde–Hasta de la pestaña, con el supervisor, el analista y la búsqueda de la
// consulta de arriba (su semana y su día no aplican aquí: manda el rango). Las
// citas llegan del servidor por mes de su fecha prevista; la pantalla carga cada
// mes del rango y los fusiona antes de llegar aquí.
import { tcAplicable } from '@/lib/capital-unificado'
import { usdAPen } from '@/lib/tipo-cambio'
import { fechaLocalCitas } from './fecha-comercial'
import { ESTADOS, coincideBusqueda, normalizar, type CitaEjemplo, type FiltrosCitas } from './modelo'
import { diasEntre, errorRango, type RangoProyeccion } from './proyeccion-rango'

/** Una cita cuenta en una sola de las tres: Referidos + Clientes + Leads = Citas. */
export type OrigenCita = 'referido' | 'cliente' | 'lead'
export type Moneda = 'PEN' | 'USD'
export type ColumnaProyeccion = 'analista' | 'citas' | 'monto' | 'ticket' | 'entrevistas' | 'conversion' | 'proyectado'
  | 'referidos' | 'clientes' | 'leads'
export type ColumnaNumerica = Exclude<ColumnaProyeccion, 'analista'>
export const ORIGENES: readonly OrigenCita[] = ['referido', 'cliente', 'lead']
export const COLUMNA_DE_ORIGEN: Record<OrigenCita, 'referidos' | 'clientes' | 'leads'> = { referido: 'referidos', cliente: 'clientes', lead: 'leads' }

export interface ConversionProyeccion { lead_id: string; perfil_id?: string | null; convertido_en: string }
export interface PersonaProyeccion { lead_id: string; identidad_persona?: string | undefined }
export interface FuenteProyeccion {
  citas: readonly CitaEjemplo[]
  /** De la consulta de arriba solo cuentan supervisor, analista y búsqueda. */
  filtros: Pick<FiltrosCitas, 'q' | 'equipo' | 'analista'>
  rango: RangoProyeccion
  /** Instante de la consulta («hoy» de la proyección). */
  corte: string
  tipoCambio?: number | null | undefined
  /** null: el servidor no envió conversiones; la conversión queda sin base, nunca en 0 %. */
  conversiones: readonly ConversionProyeccion[] | null
  poblacion?: readonly PersonaProyeccion[] | undefined
}

export interface CitaProyectada {
  cita: CitaEjemplo
  /** Identidad de la persona (misma regla que el avance mensual). */
  persona: string
  origen: OrigenCita
  /** Monto en soles; null si la cita no trae monto o está en dólares sin tipo de cambio. */
  enSoles: number | null
}

export interface PeriodoProyeccion { desde: string; hasta: string; hoy: string; dias: number; transcurridos: number; cerrado: boolean }

export interface MetricasProyeccion {
  citas: CitaProyectada[]; conMonto: CitaProyectada[]; entrevistas: CitaProyectada[]
  /** Entrevistas de personas que se convirtieron en cliente después (o en el mismo instante). */
  convertidas: CitaProyectada[]
  referidos: CitaProyectada[]; clientes: CitaProyectada[]; leads: CitaProyectada[]
  montoPen: number; montoUsd: number; pendienteTc: boolean
  monto: number | null; ticket: number | null
  pctEntrevistas: number | null; pctConversion: number | null
  personasEntrevistadas: number; personasClientes: number
  citasEsperadas: number | null; proyectado: number | null
}
export interface FilaProyeccion extends MetricasProyeccion { id: string; nombre: string; supervisor: string; supervisorId: string }
export interface BandaProyeccion { id: string; nombre: string; filas: FilaProyeccion[]; citas: number }

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
  bandas: BandaProyeccion[]
  /** Filas visibles en el orden de las bandas (la numeración # es continua). */
  filas: FilaProyeccion[]
  /** El proyectado del total SUMA el de cada analista con base; nunca promedia tasas. */
  total: MetricasProyeccion
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
  tc: number | null
  conocidas: boolean
  conversionesDe: (persona: string) => readonly number[]
}

function prepararContexto(fuente: FuenteProyeccion) {
  // Misma identidad que el avance mensual: la del servidor; si falta, el perfil
  // cliente del lead convertido; si no, el propio lead.
  const conversiones = fuente.conversiones ?? []
  const perfiles = new Map(conversiones.filter(c => c.perfil_id).map(c => [c.lead_id, c.perfil_id!]))
  const identidades = new Map((fuente.poblacion ?? []).map(p => [p.lead_id,
    p.identidad_persona ?? (perfiles.has(p.lead_id) ? `perfil:${perfiles.get(p.lead_id)}` : `lead:${p.lead_id}`)]))
  const persona = (lead: string) => identidades.get(lead) ?? `lead:${lead}`
  const porPersona = new Map<string, number[]>()
  for (const c of conversiones) {
    const instante = Date.parse(c.convertido_en)
    if (!Number.isFinite(instante)) continue
    const clave = persona(c.lead_id)
    porPersona.set(clave, [...(porPersona.get(clave) ?? []), instante])
  }
  const contexto: Contexto = {
    periodo: periodoProyeccion(fuente.rango, fuente.corte), tc: tcAplicable(fuente.tipoCambio),
    conocidas: fuente.conversiones !== null, conversionesDe: clave => porPersona.get(clave) ?? [],
  }
  return { contexto, persona }
}

function proyectar(cita: CitaEjemplo, persona: string, contexto: Contexto): CitaProyectada {
  // RESPALDO hasta la Fase 0: mientras el servidor no mande `es_cliente`, una cita
  // es de cliente si su persona ya se había convertido ANTES de crearse la cita.
  // Cuando el campo llegue, manda el servidor y este respaldo deja de usarse.
  const creada = Date.parse(cita.creadoEn ?? '')
  const esCliente = cita.esCliente ?? contexto.conversionesDe(persona).some(instante => instante < creada)
  const origen: OrigenCita = esCliente ? 'cliente' : esReferido(cita.origen) ? 'referido' : 'lead'
  const enSoles = cita.monto == null ? null : cita.moneda === 'PEN' ? cita.monto
    : contexto.tc === null ? null : usdAPen(cita.monto, contexto.tc)
  return { cita, persona, origen, enSoles }
}

function cohorte(fuente: FuenteProyeccion, persona: (lead: string) => string, contexto: Contexto): CitaProyectada[] {
  const periodo = contexto.periodo
  if (!periodo) return []
  const { q, equipo, analista } = fuente.filtros
  return fuente.citas.filter(c => {
    if (!c.creadoEn || !Number.isFinite(Date.parse(c.creadoEn))) return false
    const creada = fechaLocalCitas(c.creadoEn)
    return creada >= periodo.desde && creada <= periodo.hasta && coincideBusqueda(c, q)
      && (!equipo || c.supervisorId === equipo) && (!analista || c.analista === analista)
  }).map(c => proyectar(c, persona(c.leadId), contexto))
}

const suma = (lista: readonly CitaProyectada[], moneda: Moneda) =>
  lista.reduce((n, c) => n + (c.cita.moneda === moneda && c.cita.monto != null ? c.cita.monto : 0), 0)

function medir(lista: CitaProyectada[], contexto: Contexto): MetricasProyeccion {
  const n = lista.length
  const conMonto = lista.filter(c => c.cita.monto != null)
  const montoPen = suma(lista, 'PEN')
  const montoUsd = suma(lista, 'USD')
  const pendienteTc = montoUsd > 0 && contexto.tc === null
  const monto = pendienteTc ? null : montoPen + (contexto.tc === null ? 0 : usdAPen(montoUsd, contexto.tc))
  const ticket = monto !== null && n ? monto / n : null
  const entrevistas = lista.filter(c => c.cita.estado === 'realizada')
  // Vínculo entrevista → cliente: la conversión es posterior o igual a la asistencia.
  const convertidas = entrevistas.filter(c => {
    const asistio = Date.parse(c.cita.asistioEn ?? '')
    return Number.isFinite(asistio) && contexto.conversionesDe(c.persona).some(instante => asistio <= instante)
  })
  const personasEntrevistadas = new Set(entrevistas.map(c => c.persona)).size
  const personasClientes = new Set(convertidas.map(c => c.persona)).size
  const pctEntrevistas = n ? entrevistas.length / n * 100 : null
  const pctConversion = contexto.conocidas && personasEntrevistadas ? personasClientes / personasEntrevistadas * 100 : null
  const periodo = contexto.periodo
  const hastaHoy = periodo ? lista.filter(c => fechaLocalCitas(c.cita.creadoEn!) <= periodo.hoy).length : n
  // Citas esperadas al cierre: el ritmo de los días transcurridos llevado al periodo entero.
  const citasEsperadas = !n || !periodo ? null : periodo.cerrado || !periodo.transcurridos ? n
    : Math.max(n, hastaHoy / periodo.transcurridos * periodo.dias)
  // Con citas pero sin entrevistas el proyectado es 0 (hay base), no «sin base».
  const proyectado = citasEsperadas !== null && pctEntrevistas !== null && pctConversion !== null && ticket !== null
    ? citasEsperadas * (pctEntrevistas / 100) * (pctConversion / 100) * ticket : null
  return {
    citas: lista, conMonto, entrevistas, convertidas,
    referidos: lista.filter(c => c.origen === 'referido'), clientes: lista.filter(c => c.origen === 'cliente'),
    leads: lista.filter(c => c.origen === 'lead'),
    montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctConversion,
    personasEntrevistadas, personasClientes, citasEsperadas, proyectado,
  }
}

type Corte = 'analistas' | 'monedas' | OrigenCita
/** Embudos que quitan citas (analista, moneda y personas). `ignorar` deja fuera el del menú abierto. */
function recortar(lista: readonly CitaProyectada[], columnas: FiltrosColumnas, ignorar?: Corte) {
  const analistas = ignorar === 'analistas' || !columnas.analistas ? null : new Set(columnas.analistas)
  const monedas = ignorar === 'monedas' || !columnas.monedas ? null : new Set(columnas.monedas)
  const personas = new Map(ORIGENES.filter(o => o !== ignorar && columnas.personas?.[o]).map(o => [o, new Set(columnas.personas![o])]))
  return lista.filter(c => (!analistas || analistas.has(c.cita.analista)) && (!monedas || monedas.has(c.cita.moneda))
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
  const { contexto, persona } = prepararContexto(fuente)
  const base = cohorte(fuente, persona, contexto)
  const visibles = recortar(base, columnas)
  const porAnalista = new Map<string, CitaProyectada[]>()
  for (const c of visibles) porAnalista.set(c.cita.analista, [...(porAnalista.get(c.cita.analista) ?? []), c])
  const filas: FilaProyeccion[] = [...porAnalista.values()].map(lista => {
    const { analista: id, analistaNombre: nombre, supervisor, supervisorId } = lista[0]!.cita
    return { id, nombre, supervisor, supervisorId, ...medir(lista, contexto) }
  }).filter(f => dentroDeRangos(f, columnas.rangos))
  const equipos = new Map<string, FilaProyeccion[]>()
  for (const f of filas) equipos.set(f.supervisorId, [...(equipos.get(f.supervisorId) ?? []), f])
  const bandas = [...equipos.entries()].map(([id, del]) => ({
    id, nombre: del[0]!.supervisor, filas: del.sort(comparar(orden)), citas: del.reduce((n, f) => n + f.citas.length, 0),
  })).sort((a, b) => Number(a.id === 'sin_supervisor') - Number(b.id === 'sin_supervisor') || a.nombre.localeCompare(b.nombre, 'es'))
  const ordenadas = bandas.flatMap(b => b.filas)
  const conBase = ordenadas.filter(f => f.proyectado !== null)
  const total = { ...medir(ordenadas.flatMap(f => f.citas), contexto),
    proyectado: conBase.length ? conBase.reduce((n, f) => n + f.proyectado!, 0) : null }
  return {
    periodo: contexto.periodo, tc: contexto.tc, cohorte: base, bandas, filas: ordenadas, total,
    requiereTc: base.some(c => c.cita.moneda === 'USD' && (c.cita.monto ?? 0) > 0),
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
/** Analistas de la cohorte con su n.º de citas (respetando los demás embudos). */
export function opcionesAnalistas(hoja: HojaProyeccion, columnas: FiltrosColumnas): OpcionEmbudo[] {
  return contar(recortar(hoja.cohorte, columnas, 'analistas'), c => [c.cita.analista, c.cita.analistaNombre])
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

export function csvProyeccion(hoja: HojaProyeccion, rotulo: string): string {
  const fila = (f: MetricasProyeccion, equipo: string, analista: string) => [rotulo, equipo, analista, f.citas.length,
    f.pendienteTc ? 'Pendiente de TC' : redondeo(f.monto), redondeo(f.ticket), redondeo(f.pctEntrevistas, 1), redondeo(f.pctConversion, 1),
    redondeo(f.proyectado), f.referidos.length, f.clientes.length, f.leads.length]
  return archivoCsv([
    ['Periodo', 'Equipo', 'Analista', 'Citas', 'Monto S/', 'Ticket S/', '% Entrev.', '% Conv.', 'Proyectado S/', 'Referidos', 'Clientes', 'Leads'],
    ...hoja.filas.map(f => fila(f, f.supervisor, f.nombre)),
    fila(hoja.total, '', `Total · ${hoja.filas.length} analistas`),
  ])
}

export function csvCitasProyeccion(lista: readonly CitaProyectada[]): string {
  return archivoCsv([
    ['Código de cita', 'Fecha', 'Hora', 'Persona', 'Analista', 'Supervisor', 'Estado', 'Moneda', 'Monto', 'Monto S/', 'Origen'],
    ...lista.map(({ cita, enSoles, origen }) => [cita.id, cita.fecha, cita.hora, cita.nombre, cita.analistaNombre, cita.supervisor,
      ESTADOS[cita.estado].label, cita.moneda, cita.monto ?? '', redondeo(enSoles), ROTULO_ORIGEN[origen]]),
  ])
}
