// F4-e: «la operación de hoy» de las llamadas del celular para supervisión y gerencia (F4E-CONTRATO.md §5–§6).
// Espejo en pantalla del jsonb que devuelve `crm.llamadas_celular_operacion_hoy_fn` (decimotercera migración,
// 20261012192500): el esquema confirma la forma Y las sumas (las cubetas suman el total; los equipos y los totales son
// la suma de sus analistas), porque la pantalla calcula los porcentajes de cada par de la misma cohorte y nunca los
// recibe. Tres relojes, cada uno con su rótulo dentro de la respuesta: la pantalla los muestra tal cual (condición de
// Miguel: cada cifra dice qué fecha usa).
import * as v from 'valibot'
import { ESTADOS_LATIDO, VERSION_MACRO_VIGENTE } from './celulares'
import { FechaF5, InstanteF5, NaturalF5 } from './gestion-diaria-pulso'

// ── Forma del jsonb (§6) ─────────────────────────────────────────────────────────────────────────────────────────────

/** 5.1: cohorte «llamadas de hoy», por el momento de la llamada. Seis cubetas disjuntas; `requiere_devolucion` no debe
 * aparecer (entrantes bloqueadas) pero el servidor la cuenta aparte para que el total cierre igual. */
export const LlamadasHoySchema = v.pipe(v.object({
  total: NaturalF5, con_resultado: NaturalF5, deshechas_sin_corregir: NaturalF5, sin_resultado: NaturalF5,
  cerradas_despues: NaturalF5, descartadas: NaturalF5, por_revisar: NaturalF5, requiere_devolucion: NaturalF5,
}), v.check((c) => c.total === c.con_resultado + c.deshechas_sin_corregir + c.sin_resultado + c.cerradas_despues
  + c.descartadas + c.por_revisar + c.requiere_devolucion, 'las cubetas no suman el total'))
export type LlamadasHoy = v.InferOutput<typeof LlamadasHoySchema>

/** 5.2: cohorte «resultados de hoy», por la fecha del resultado, partida por vía. */
export const ResultadosHoySchema = v.pipe(v.object({
  total: NaturalF5, al_colgar: NaturalF5, desde_pestana: NaturalF5, a_mano: NaturalF5,
}), v.check((r) => r.total === r.al_colgar + r.desde_pestana + r.a_mano, 'las vías no suman el total'))
export type ResultadosHoy = v.InferOutput<typeof ResultadosHoySchema>

/** 5.3: foto de ahora. `mas_antigua_dias` existe exactamente cuando hay pendientes. */
export const PendientesSchema = v.pipe(v.object({
  total: NaturalF5, de_hoy: NaturalF5, anteriores: NaturalF5, mas_antigua_dias: v.nullable(NaturalF5), deshechas_sin_corregir: NaturalF5,
}), v.check((p) => p.total === p.de_hoy + p.anteriores && (p.total === 0) === (p.mas_antigua_dias === null), 'pendientes incoherentes'))
export type Pendientes = v.InferOutput<typeof PendientesSchema>

const camposCifras = { llamadas_hoy: LlamadasHoySchema, resultados_hoy: ResultadosHoySchema, pendientes: PendientesSchema, por_revisar: NaturalF5 }
export const CifrasCelularSchema = v.object(camposCifras)
export type CifrasCelular = v.InferOutput<typeof CifrasCelularSchema>

/** 5.4: lo que el contrato publica de cada celular (sin asignación, nombre ni horas exactas de latido). */
export const CelularOperacionSchema = v.object({
  etiqueta: v.string(), estado_latido: v.picklist(ESTADOS_LATIDO), horas_sin_latido: v.nullable(NaturalF5),
  reloj_desfasado: v.boolean(), eventos_en_cola: v.nullable(NaturalF5), version_macro: v.nullable(v.string()),
})
export type CelularOperacion = v.InferOutput<typeof CelularOperacionSchema>

export const AnalistaCelularSchema = v.pipe(v.object({
  ...camposCifras, analista_id: v.string(), nombre: v.string(), supervisor_id: v.nullable(v.string()),
  sin_dato: v.boolean(), celulares: v.array(CelularOperacionSchema),
  // D1: «sin dato» = 0 llamadas Y ningún celular al día. Un celular al día con 0 llamadas muestra «0».
}), v.check((a) => a.sin_dato === (a.llamadas_hoy.total === 0 && !a.celulares.some((c) => c.estado_latido === 'al_dia')), 'sin_dato no sigue D1'))
export type AnalistaCelular = v.InferOutput<typeof AnalistaCelularSchema>

const camposSuma = { celulares_vigentes: NaturalF5, celulares_sin_latido: NaturalF5, analistas_sin_dato: NaturalF5 }
export const EquipoCelularSchema = v.object({
  ...camposCifras, ...camposSuma, supervisor_id: v.nullable(v.string()), supervisor_nombre: v.string(), analistas: NaturalF5,
})
export type EquipoCelular = v.InferOutput<typeof EquipoCelularSchema>
export const TotalesCelularSchema = v.object({ ...camposCifras, ...camposSuma })
export type TotalesCelular = v.InferOutput<typeof TotalesCelularSchema>

/** 5.5: los equipos y los totales son SUMAS de sus analistas; los porcentajes se recalculan de las sumas. */
export function sumarCifras(items: readonly CifrasCelular[]): CifrasCelular {
  const suma = (f: (c: CifrasCelular) => number) => items.reduce((n, c) => n + f(c), 0)
  const antiguas = items.flatMap((c) => c.pendientes.mas_antigua_dias === null ? [] : [c.pendientes.mas_antigua_dias])
  return {
    llamadas_hoy: {
      total: suma((c) => c.llamadas_hoy.total), con_resultado: suma((c) => c.llamadas_hoy.con_resultado),
      deshechas_sin_corregir: suma((c) => c.llamadas_hoy.deshechas_sin_corregir), sin_resultado: suma((c) => c.llamadas_hoy.sin_resultado),
      cerradas_despues: suma((c) => c.llamadas_hoy.cerradas_despues), descartadas: suma((c) => c.llamadas_hoy.descartadas),
      por_revisar: suma((c) => c.llamadas_hoy.por_revisar), requiere_devolucion: suma((c) => c.llamadas_hoy.requiere_devolucion),
    },
    resultados_hoy: {
      total: suma((c) => c.resultados_hoy.total), al_colgar: suma((c) => c.resultados_hoy.al_colgar),
      desde_pestana: suma((c) => c.resultados_hoy.desde_pestana), a_mano: suma((c) => c.resultados_hoy.a_mano),
    },
    pendientes: {
      total: suma((c) => c.pendientes.total), de_hoy: suma((c) => c.pendientes.de_hoy), anteriores: suma((c) => c.pendientes.anteriores),
      mas_antigua_dias: antiguas.length ? Math.max(...antiguas) : null, deshechas_sin_corregir: suma((c) => c.pendientes.deshechas_sin_corregir),
    },
    por_revisar: suma((c) => c.por_revisar),
  }
}
export interface SumaCelulares { celulares_vigentes: number; celulares_sin_latido: number; analistas_sin_dato: number }
export function sumarCelulares(analistas: readonly AnalistaCelular[]): SumaCelulares {
  return {
    celulares_vigentes: analistas.reduce((n, a) => n + a.celulares.length, 0),
    celulares_sin_latido: analistas.reduce((n, a) => n + a.celulares.filter((c) => c.estado_latido !== 'al_dia').length, 0),
    analistas_sin_dato: analistas.filter((a) => a.sin_dato).length,
  }
}
const cifrasDe = (c: CifrasCelular): CifrasCelular => ({ llamadas_hoy: c.llamadas_hoy, resultados_hoy: c.resultados_hoy, pendientes: c.pendientes, por_revisar: c.por_revisar })
const mismasCifras = (a: CifrasCelular, b: CifrasCelular) => JSON.stringify(cifrasDe(a)) === JSON.stringify(cifrasDe(b))
const mismasSumas = (a: SumaCelulares, b: SumaCelulares) =>
  a.celulares_vigentes === b.celulares_vigentes && a.celulares_sin_latido === b.celulares_sin_latido && a.analistas_sin_dato === b.analistas_sin_dato

export const OperacionCelularHoySchema = v.pipe(v.object({
  dia: FechaF5, generado_en: InstanteF5, alcance: v.picklist(['operacion', 'equipo']),
  rotulos: v.object({ llamadas_hoy: v.string(), resultados_hoy: v.string(), pendientes: v.string() }),
  totales: TotalesCelularSchema, equipos: v.array(EquipoCelularSchema), analistas: v.array(AnalistaCelularSchema),
  /** A7: el celular del supervisor, fuera de la tabla y sin sumar al equipo. Gerencia: nulo. */
  su_celular: v.nullable(v.array(CelularOperacionSchema)),
}), v.check((d) => {
  if (new Set(d.analistas.map((a) => a.analista_id)).size !== d.analistas.length) return false
  if (new Set(d.equipos.map((e) => e.supervisor_id)).size !== d.equipos.length) return false
  if (!d.analistas.every((a) => d.equipos.some((e) => e.supervisor_id === a.supervisor_id))) return false
  for (const e of d.equipos) {
    const suyos = d.analistas.filter((a) => a.supervisor_id === e.supervisor_id)
    if (suyos.length !== e.analistas || !mismasCifras(e, sumarCifras(suyos)) || !mismasSumas(e, sumarCelulares(suyos))) return false
  }
  return mismasCifras(d.totales, sumarCifras(d.analistas)) && mismasSumas(d.totales, sumarCelulares(d.analistas))
}, 'los equipos o los totales no son la suma de sus analistas'))
export type OperacionCelularHoy = v.InferOutput<typeof OperacionCelularHoySchema>

// ── Lo que la pantalla deriva (nunca viaja en el jsonb) ───────────────────────────────────────────────────────────────

/** Porcentaje entero de un par de la MISMA cohorte; sin denominador, nulo (la pantalla dice «—»). */
export const porcentaje = (parte: number, total: number): number | null => total > 0 ? Math.round(100 * parte / total) : null
export const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`

/** La clave del equipo es la del pulso de «Actividad del día»: el id del supervisor, o «fuera». */
export const claveEquipoCelular = (supervisorId: string | null) => supervisorId ?? 'fuera'

export interface FilaEquipoCelular {
  clave: string
  /** El nombre visible (el del supervisor). Sin supervisor se ve el rótulo del servidor y no se antepone «Equipo de». */
  nombre: string
  fuera: boolean
  equipo: EquipoCelular
  analistas: AnalistaCelular[]
  /** Analistas con algo que mirar (sin resultado, sin latido, por revisar, sin dato, deshechas, cola). */
  conAtencion: number
}

export function filasEquiposCelular(datos: OperacionCelularHoy): FilaEquipoCelular[] {
  return datos.equipos.map((e) => {
    const analistas = datos.analistas.filter((a) => a.supervisor_id === e.supervisor_id)
    return { clave: claveEquipoCelular(e.supervisor_id), nombre: e.supervisor_nombre, fuera: e.supervisor_id === null, equipo: e, analistas,
      conAtencion: analistas.filter((a) => motivosAtencion(a).length > 0).length }
  })
}

/** Por qué un analista necesita atención en el celular, en el orden en que se dicen. Vacío = nada que mirar. */
export function motivosAtencion(a: AnalistaCelular): string[] {
  const motivos: string[] = []
  if (a.pendientes.total > 0) motivos.push(`${plural(a.pendientes.total, 'llamada sin resultado', 'llamadas sin resultado')}`)
  if (a.pendientes.deshechas_sin_corregir > 0) motivos.push(`${plural(a.pendientes.deshechas_sin_corregir, 'deshecha sin corregir', 'deshechas sin corregir')}`)
  if (a.por_revisar > 0) motivos.push(`${plural(a.por_revisar, 'llamada por revisar', 'llamadas por revisar')}`)
  for (const c of a.celulares) {
    if (c.estado_latido === 'sin_latido') motivos.push(`${c.etiqueta} sin latido · ${c.horas_sin_latido ?? '?'} h`)
    else if (c.estado_latido === 'nunca') motivos.push(`${c.etiqueta} nunca habló`)
    if (c.eventos_en_cola !== null && c.eventos_en_cola > 0) motivos.push(`${c.etiqueta} con ${plural(c.eventos_en_cola, 'aviso en cola', 'avisos en cola')}`)
    if (c.reloj_desfasado) motivos.push(`${c.etiqueta} con el reloj desfasado`)
    if (c.version_macro !== null && c.version_macro !== VERSION_MACRO_VIGENTE) motivos.push(`${c.etiqueta} con la macro vieja`)
  }
  if (a.sin_dato) motivos.push('sin dato del celular')
  return motivos
}

export type EstadoCelular = 'todos' | 'sin_resultado' | 'sin_latido' | 'por_revisar'
export type OrdenCelular = 'nombre' | 'en_celular' | 'con_resultado' | 'al_colgar' | 'descartadas' | 'sin_resultado' | 'por_revisar' | 'celulares'
export interface FiltrosCelular { busqueda: string; estado: EstadoCelular; orden: OrdenCelular; ascendente: boolean }
export const FILTROS_CELULAR: FiltrosCelular = { busqueda: '', estado: 'todos', orden: 'sin_resultado', ascendente: false }

export const cumpleEstadoCelular = (f: FilaEquipoCelular, estado: EstadoCelular) =>
  estado === 'todos' ? true : estado === 'sin_resultado' ? f.equipo.pendientes.total > 0
    : estado === 'sin_latido' ? f.equipo.celulares_sin_latido > 0 : f.equipo.por_revisar > 0

const valorOrden = (f: FilaEquipoCelular, orden: OrdenCelular): number => {
  const e = f.equipo
  switch (orden) {
    case 'en_celular': return e.llamadas_hoy.total
    case 'con_resultado': return e.llamadas_hoy.con_resultado
    case 'al_colgar': return e.resultados_hoy.al_colgar
    case 'descartadas': return e.llamadas_hoy.descartadas
    case 'sin_resultado': return e.pendientes.total
    case 'por_revisar': return e.por_revisar
    case 'celulares': return e.celulares_vigentes
    default: return 0
  }
}
const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLocaleLowerCase('es')

export function filtrarOrdenarCelular(filas: readonly FilaEquipoCelular[], filtros: FiltrosCelular): FilaEquipoCelular[] {
  const texto = normalizar(filtros.busqueda.trim())
  const signo = filtros.ascendente ? 1 : -1
  return filas
    .filter((f) => cumpleEstadoCelular(f, filtros.estado) && (!texto || normalizar(f.nombre).includes(texto)))
    .toSorted((a, b) => {
      const porNombre = a.nombre.localeCompare(b.nombre, 'es')
      if (filtros.orden === 'nombre') return signo * porNombre
      return signo * (valorOrden(a, filtros.orden) - valorOrden(b, filtros.orden)) || porNombre
    })
}

/** «1 de hoy · 1 anterior» bajo «Sin resultado»; vacío sin pendientes. En la tabla no cabe la antigüedad: va en la ficha. */
export function detallePendientes(p: Pendientes, conAntiguedad = true): string {
  if (p.total === 0) return ''
  const partes = [p.de_hoy > 0 && `${p.de_hoy} de hoy`, p.anteriores > 0 && `${p.anteriores === 1 ? '1 anterior' : `${p.anteriores} anteriores`}`].filter(Boolean)
  const antigua = conAntiguedad && p.mas_antigua_dias !== null && p.mas_antigua_dias > 0 ? ` · la más antigua hace ${plural(p.mas_antigua_dias, 'día', 'días')}` : ''
  return partes.join(' · ') + antigua
}

/** «9 al colgar · 1 desde la pestaña · 1 a mano», solo las vías con algo. */
export function detalleVias(r: ResultadosHoy): string {
  return [r.al_colgar > 0 && `${r.al_colgar} al colgar`, r.desde_pestana > 0 && `${r.desde_pestana} desde la pestaña`, r.a_mano > 0 && `${r.a_mano} a mano`]
    .filter(Boolean).join(' · ')
}
