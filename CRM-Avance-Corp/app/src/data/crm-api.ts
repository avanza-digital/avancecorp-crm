import type { SupabaseClient } from '@supabase/supabase-js'
import { sb } from '@/lib/supabase'
import { idCorrelacion, registrarError } from '@/lib/observabilidad'
import { esOrigen, type Etapa, type Lead, type MotivoDescarte } from '@/lib/tipos'
import type { Moneda } from '@/lib/format'

export const TAMANO_PAGINA_LEADS = 50
const MAX_TAMANO_PAGINA = 100
const MAX_BUSQUEDA = 80

const COLUMNAS_LEAD = [
  'id',
  'nombre_completo',
  'telefono',
  'correo',
  'dni',
  'distrito',
  'origen',
  'etapa',
  'motivo_descarte',
  'monto_estimado',
  'moneda',
  'categoria_interes',
  'vendedor_id',
  'asignado_supervisor_id',
  'creado_en',
  'actualizado_en',
  'activo',
].join(',')

interface LeadRow {
  id: string
  nombre_completo: string
  telefono: string
  correo: string | null
  dni: string | null
  distrito: string | null
  origen: string
  etapa: Etapa
  motivo_descarte: MotivoDescarte | null
  monto_estimado: number | string | null
  moneda: Moneda
  categoria_interes: 'nuevo' | 'renovacion' | 'upgrade' | null
  vendedor_id: string | null
  asignado_supervisor_id: string | null
  creado_en: string
  actualizado_en: string
  activo: boolean
}

export interface FiltrosLeads {
  pagina: number
  tamano?: number
  texto?: string
  etapa?: Etapa | 'todas'
  vendedorId?: string | 'todos' | 'sin_asignar'
  incluirInactivos?: boolean
}

export interface Pagina<T> {
  items: T[]
  pagina: number
  tamano: number
  total: number
  paginas: number
}

export class CrmApiError extends Error {
  readonly code: string
  readonly correlationId: string

  constructor(message: string, code = 'CRM_API_ERROR', correlationId = idCorrelacion()) {
    super(message)
    this.name = 'CrmApiError'
    this.code = code
    this.correlationId = correlationId
  }
}

function cliente(): SupabaseClient {
  if (!sb) {
    const error = new CrmApiError('Supabase no está configurado.', 'SUPABASE_NOT_CONFIGURED')
    registrarError('crm.cliente_no_disponible', error)
    throw error
  }
  return sb
}

function enteroSeguro(valor: number, minimo: number, maximo: number): number {
  if (!Number.isFinite(valor)) return minimo
  return Math.min(maximo, Math.max(minimo, Math.trunc(valor)))
}

/**
 * PostgREST `.or()` recibe una mini-sintaxis, no parámetros independientes.
 * Usamos una allowlist pequeña (letras, números, espacios y guiones) para que
 * el texto del usuario solo pueda ser un patrón ILIKE, nunca parte de la
 * expresión lógica. Los dígitos se conservan aparte para teléfono/DNI.
 */
export function normalizarBusquedaPostgrest(valor: string | undefined): {
  texto: string
  digitos: string
} {
  const crudo = (valor ?? '').normalize('NFKC').trim().slice(0, MAX_BUSQUEDA)
  const texto = crudo
    .replace(/[^\p{L}\p{N}\s-]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const digitos = crudo.replace(/\D/g, '').slice(0, 15)
  return { texto, digitos }
}

function aNumero(valor: number | string | null): number | null {
  if (valor == null) return null
  const n = typeof valor === 'number' ? valor : Number(valor)
  return Number.isFinite(n) ? n : null
}

function aLead(fila: LeadRow): Lead {
  return {
    id: fila.id,
    nombre_completo: fila.nombre_completo,
    telefono: fila.telefono,
    correo: fila.correo,
    dni: fila.dni,
    distrito: fila.distrito,
    // Frontera: un origen fuera del catálogo (dato viejo/migración) degrada a
    // 'otro' en vez de romper los unions del dominio río abajo.
    origen: esOrigen(fila.origen) ? fila.origen : 'otro',
    etapa: fila.etapa,
    motivo_descarte: fila.motivo_descarte,
    monto_estimado: aNumero(fila.monto_estimado),
    moneda: fila.moneda,
    categoria_interes: fila.categoria_interes,
    vendedor_id: fila.vendedor_id,
    asignado_supervisor_id: fila.asignado_supervisor_id,
    creado_en: fila.creado_en,
    activo: fila.activo,
  }
}

/**
 * Lectura paginada lista para activarse cuando el esquema CRM esté aplicado.
 * RLS decide el ámbito; el navegador jamás descarga la cartera global para
 * recortarla después.
 */
export async function listarLeads(
  filtros: FiltrosLeads,
  signal?: AbortSignal,
): Promise<Pagina<Lead>> {
  const pagina = enteroSeguro(filtros.pagina, 0, Number.MAX_SAFE_INTEGER)
  const tamano = enteroSeguro(filtros.tamano ?? TAMANO_PAGINA_LEADS, 1, MAX_TAMANO_PAGINA)
  const desde = pagina * tamano
  const hasta = desde + tamano - 1

  let consulta = cliente()
    .schema('crm')
    .from('leads')
    .select(COLUMNAS_LEAD, { count: 'exact' })
    .order('actualizado_en', { ascending: false })
    .order('id', { ascending: true })
    .range(desde, hasta)

  if (!filtros.incluirInactivos) consulta = consulta.eq('activo', true)
  if (filtros.etapa && filtros.etapa !== 'todas') consulta = consulta.eq('etapa', filtros.etapa)

  if (filtros.vendedorId === 'sin_asignar') {
    consulta = consulta.is('vendedor_id', null)
  } else if (filtros.vendedorId && filtros.vendedorId !== 'todos') {
    consulta = consulta.eq('vendedor_id', filtros.vendedorId)
  }

  const busqueda = normalizarBusquedaPostgrest(filtros.texto)
  if (busqueda.texto.length >= 2) {
    const ramas = [`nombre_completo.ilike.%${busqueda.texto}%`]
    if (busqueda.digitos.length >= 3) {
      ramas.push(`telefono.ilike.%${busqueda.digitos}%`, `dni.ilike.%${busqueda.digitos}%`)
    }
    consulta = consulta.or(ramas.join(','))
  }

  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error, count } = await consulta
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    // No se registra el texto ni IDs del filtro: pueden contener PII.
    registrarError('crm.leads.listado_fallido', fallo, {
      pagina,
      tamano,
      etapa: filtros.etapa ?? 'todas',
      incluyeInactivos: filtros.incluirInactivos === true,
      filtraVendedor: Boolean(filtros.vendedorId && filtros.vendedorId !== 'todos'),
      tieneBusqueda: busqueda.texto.length >= 2,
    })
    throw fallo
  }

  const total = count ?? 0
  return {
    items: ((data ?? []) as unknown as LeadRow[]).map(aLead),
    pagina,
    tamano,
    total,
    paginas: Math.ceil(total / tamano),
  }
}
