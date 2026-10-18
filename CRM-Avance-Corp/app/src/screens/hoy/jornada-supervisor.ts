import type { CitaEjemplo } from '@/components/citas/modelo'
import { capitalComercialEnSoles, metaComercialEnSoles, type CapitalUnificado } from '@/lib/capital-unificado'
import type { CapitalResumen } from '@/lib/capital-valorado'
import type { FilaFacturacionDia } from '@/lib/facturacion'
import { lecturaCobertura, type ConversionMensual } from '@/lib/conversion-mensual'
import { presentarEquipo, type DiaEquipo } from '@/lib/gestion-diaria-equipo'
import { capitalObjetivo, capitalReal, type CumplimientoAgregado, type CumplimientoMetasJerarquico, type ObjetivosJerarquicos } from '@/lib/objetivos'

/** Una foto completa del equipo; nunca sumar las filas paginadas del seguimiento. */
export function resumirJornada(dia: DiaEquipo | null) {
  if (!dia) return null
  const equipo = presentarEquipo(dia)
  const sumar = (valor: (fila: typeof equipo[number]) => number) => equipo.reduce((total, fila) => total + valor(fila), 0)
  const utiles = sumar(f => f.marcador.utiles)
  const contestadas = sumar(f => f.marcador.contestadas)
  return {
    llamadas: sumar(f => f.marcador.llamadas), utiles, contestadas,
    // No promediar tasas ni deducir personas únicas a partir de llamadas.
    contacto: utiles > 0 ? 100 * contestadas / utiles : null,
    muestraSuficiente: utiles >= dia.umbrales.minimo_llamadas_utiles,
    primeras: equipo.every(f => f.primer_intento_vencido !== null)
      ? sumar(f => f.primer_intento_vencido!) : null,
    vencidas: sumar(f => f.tareas_vencidas),
    pendientes: sumar(f => f.tareas_pendientes),
    conActividad: equipo.filter(f => f.gestiones_hoy > 0).length,
    requierenApoyo: equipo.filter(f => f.requiere_atencion).length,
  }
}

/** Fecha PREVISTA de la cita. Crear una cita hoy no implica que se celebre hoy. */
export function resumirCitasHoy(citas: readonly CitaEjemplo[] | null, hoy: string) {
  if (citas === null) return null
  const filas = citas.filter(c => c.fecha === hoy)
  const contar = (estado: CitaEjemplo['estado']) => filas.filter(c => c.estado === estado).length
  return {
    total: filas.length, realizadas: contar('realizada'), programadas: contar('programada'),
    vencidas: contar('vencida'), noAsistio: contar('no_show'),
    canceladas: contar('cancelada') + contar('sistema'), reprogramadas: contar('reprogramada'),
  }
}

/** Filas del ámbito YA autorizado por Facturación; conserva subárbol y atribución histórica. */
export function resumirResultadosHoy(filas: readonly FilaFacturacionDia[] | null, hoy: string) {
  if (filas === null) return null
  const personas = new Map<string, { id: string; nombre: string; operaciones: number; pen: number; usd: number }>()
  for (const fila of filas) {
    if (fila.dia !== hoy) continue
    const persona = personas.get(fila.analistaId) ?? { id: fila.analistaId, nombre: fila.analistaNombre, operaciones: 0, pen: 0, usd: 0 }
    persona.operaciones += fila.operaciones
    if (fila.moneda === 'PEN') persona.pen += fila.capital
    else persona.usd += fila.capital
    personas.set(fila.analistaId, persona)
  }
  const analistas = [...personas.values()].sort((a, b) => b.operaciones - a.operaciones || a.nombre.localeCompare(b.nombre, 'es'))
  return { analistas,
    operaciones: analistas.reduce((n, fila) => n + fila.operaciones, 0),
    pen: analistas.reduce((n, fila) => n + fila.pen, 0),
    usd: analistas.reduce((n, fila) => n + fila.usd, 0),
  }
}

export function capitalComparable(capital: CapitalUnificado): boolean {
  return capital.total !== null && (capital.estado === 'convertido' || capital.usd === 0)
}

export function avanceCapital(capital: CapitalUnificado, meta: CapitalUnificado) {
  if (!capitalComparable(capital) || !capitalComparable(meta) || !meta.total || meta.total <= 0) return null
  return { porcentaje: 100 * capital.total! / meta.total, brecha: Math.max(0, meta.total - capital.total!) }
}

export function operacionesConfirmadas(cumplimiento: CumplimientoAgregado | null): number | null {
  if (!cumplimiento || cumplimiento.capitalValorado === null) return null
  return cumplimiento.capitalValorado
    ? cumplimiento.capitalValorado.detalles.reduce((total, d) => total + d.contratos_real, 0)
    : cumplimiento.detalles.reduce((total, d) => total + d.contratosReal, 0)
}

export interface FilaMensualJornada {
  esSupervisor: boolean
  id: string
  nombre: string
  capital: CapitalUnificado
  meta: CapitalUnificado
  operaciones: number | null
  conversion: number | null
  recibidos: number | null
}

/** La atribución del MES viene del snapshot oficial, no del equipo operativo de hoy.
 * En v2, la publicación valorada conserva personas que cambiaron en la foto viva. */
export function filasMensualesJornada({ cumplimiento, objetivos, conversion, supervisorId, tc, nombres = new Map() }: {
  cumplimiento: CumplimientoMetasJerarquico | null
  objetivos: ObjetivosJerarquicos | null
  conversion: ConversionMensual | null | undefined
  supervisorId: string
  tc: number | null | undefined
  nombres?: ReadonlyMap<string, string>
}): FilaMensualJornada[] {
  const identidades = new Map<string, string>()
  const reales = new Map(Object.values(cumplimiento?.porVendedor ?? {})
    .filter(f => f.supervisorId === supervisorId).map(f => [f.vendedorId, f]))
  // Desde octubre, Main incorpora la venta propia al total del equipo sin
  // añadir una meta individual. Conservarla también en su desglose.
  const propias = new Map((cumplimiento?.supervisores ?? [])
    .filter(f => f.personaId === supervisorId)
    .map(f => [f.personaId, { ...f, conversionObjetivo: 0 }]))
  for (const f of propias.values()) identidades.set(f.personaId, f.nombre)
  const metas = new Map(Object.values(objetivos?.porVendedor ?? {})
    .filter(f => f.supervisorId === supervisorId).map(f => [f.vendedorId, f]))
  for (const f of metas.values()) identidades.set(f.vendedorId, f.nombre)
  for (const f of reales.values()) identidades.set(f.vendedorId, f.nombre)
  const valorados = new Map<string, CapitalResumen>()
  for (const f of cumplimiento?.valoracionCapital?.personas ?? []) {
    if (!(f.en_ranking && f.supervisor_id === supervisorId)
      && !(f.vendedor_id === supervisorId && f.rol_crm === 'supervisor')) continue
    identidades.set(f.vendedor_id, f.nombre)
    valorados.set(f.vendedor_id, f.capital_valorado)
  }
  // La conversión puede tener responsables sin meta. Nunca inventarles una venta o una meta.
  for (const f of conversion?.responsables ?? []) {
    if (f.supervisor_id === supervisorId && !identidades.has(f.vendedor_id)) identidades.set(f.vendedor_id, nombres.get(f.vendedor_id) ?? 'Analista sin nombre en la foto mensual')
  }
  // El contrato RPC ya verifica que responsables + fuera de roster cuadren con el total.
  // La población de capital puede diferir de la de conversión: una meta sin fila
  // de conversión no debe apagar las cifras confirmadas de los demás analistas.
  const conversiones = new Map(lecturaCobertura(conversion?.cobertura).mostrar
    ? (conversion?.responsables ?? []).filter(f => f.supervisor_id === supervisorId).map(f => [f.vendedor_id, f]) : [])
  return [...identidades].map(([id, nombre]) => {
    const esSupervisor = id === supervisorId
    const real = reales.get(id) ?? propias.get(id)
    const objetivo = objetivos && !esSupervisor ? real ?? metas.get(id) : undefined
    const valorado = cumplimiento?.valoracionCapital ? valorados.get(id) ?? null : real?.capitalValorado
    const capital = capitalComercialEnSoles(real ? capitalReal(real, 'PEN') : null, real ? capitalReal(real, 'USD') : null, tc, valorado)
    const meta = metaComercialEnSoles(objetivo ? capitalObjetivo(objetivo, 'PEN') : null, objetivo ? capitalObjetivo(objetivo, 'USD') : null, tc,
      objetivos && !esSupervisor ? valorado : undefined)
    const detalle = conversiones.get(id)
    return { id, nombre, esSupervisor, capital, meta,
      operaciones: valorado ? valorado.detalles.reduce((s, d) => s + d.contratos_real, 0) : valorado === null ? null : operacionesConfirmadas(real ?? null),
      conversion: detalle?.conversion_pct ?? null, recibidos: detalle?.divisor ?? null,
    }
  }).sort((a, b) => (capitalComparable(b.capital) ? b.capital.total! : -1)
    - (capitalComparable(a.capital) ? a.capital.total! : -1) || a.nombre.localeCompare(b.nombre, 'es'))
}
