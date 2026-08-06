import { fechaLima } from './agenda-derivada'
import {
  TIPOS_CONVERSACION,
  type Actividad,
  type Lead,
  type Miembro,
  type Tarea,
} from './tipos'

export interface ConversionEquipoVendedor {
  vendedorId: string | null
  nombre: string
  supervisorNombre: string
  leads: number
  contactados: number
  reunionesPactadas: number
  reunionesRealizadas: number
  clientes: number
  descartados: number
  conversionPct: number | null
}

/**
 * Ranking exclusivo de personas vendedoras. La fila técnica de leads sin
 * asignar no compite y quienes aún no recibieron leads quedan al final.
 */
export function rankingConversionEquipo(
  equipo: readonly ConversionEquipoVendedor[],
): ConversionEquipoVendedor[] {
  return equipo
    .filter((fila) => fila.vendedorId != null)
    .sort((a, b) => {
      const aTieneDatos = a.leads > 0
      const bTieneDatos = b.leads > 0
      if (aTieneDatos !== bTieneDatos) return aTieneDatos ? -1 : 1
      return (b.conversionPct ?? -1) - (a.conversionPct ?? -1)
        || b.clientes - a.clientes
        || b.leads - a.leads
        || a.nombre.localeCompare(b.nombre, 'es')
    })
}

interface ConversionEquipoInput {
  vendedores: Miembro[]
  equipo: Miembro[]
  leads: Lead[]
  actividades: Actividad[]
  tareas: Tarea[]
  desde: string
  hasta: string
}

const SIN_VENDEDOR = '__sin_vendedor__'

function porcentaje(parte: number, total: number): number | null {
  return total > 0 ? Math.round((1000 * parte) / total) / 10 : null
}

function perteneceAlPeriodo(iso: string, desde: string, hasta: string): boolean {
  const instante = Date.parse(iso)
  if (!Number.isFinite(instante)) return false
  const fecha = fechaLima(instante)
  return fecha >= desde && fecha <= hasta
}

function filaVacia(
  vendedorId: string | null,
  nombre: string,
  supervisorNombre: string,
): ConversionEquipoVendedor {
  return {
    vendedorId,
    nombre,
    supervisorNombre,
    leads: 0,
    contactados: 0,
    reunionesPactadas: 0,
    reunionesRealizadas: 0,
    clientes: 0,
    descartados: 0,
    conversionPct: null,
  }
}

/**
 * Devuelve únicamente la identidad visible del equipo comercial. Los paneles
 * que reciben sus métricas desde la RPC usan esta lista para poner nombres y
 * supervisores sin reconstruir contadores desde leads operativos locales.
 */
export function identidadesEquipoConversion(
  vendedores: readonly Miembro[],
  equipo: readonly Miembro[],
): ConversionEquipoVendedor[] {
  const nombreSupervisor = new Map(
    equipo
      .filter((miembro) => miembro.activo && miembro.rol_crm === 'supervisor')
      .map((miembro) => [miembro.perfil_id, miembro.nombre_completo]),
  )

  return vendedores
    .filter((vendedor) => vendedor.activo && vendedor.rol_crm === 'vendedor')
    .map((vendedor) => filaVacia(
      vendedor.perfil_id,
      vendedor.nombre_completo,
      vendedor.supervisor_id
        ? (nombreSupervisor.get(vendedor.supervisor_id) ?? 'Sin supervisor')
        : 'Sin supervisor',
    ))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es') || (a.vendedorId ?? '').localeCompare(b.vendedorId ?? ''))
}

/**
 * Vista por vendedor construida con la información que Gerencia ya tiene en
 * memoria. Respeta el mismo período del tablero y no crea datos ni hace otra
 * petición. La conversión visible es cliente ganado / lead recibido.
 */
export function conversionesEquipo({
  vendedores,
  equipo,
  leads,
  actividades,
  tareas,
  desde,
  hasta,
}: ConversionEquipoInput): ConversionEquipoVendedor[] {
  const nombreSupervisor = new Map(
    equipo
      .filter((miembro) => miembro.activo && miembro.rol_crm === 'supervisor')
      .map((miembro) => [miembro.perfil_id, miembro.nombre_completo]),
  )
  const filas = new Map(
    identidadesEquipoConversion(vendedores, equipo)
      .map((fila) => [fila.vendedorId as string, fila]),
  )

  const contactoReal = new Set(
    actividades
      .filter((actividad) => TIPOS_CONVERSACION.includes(
        actividad.tipo as (typeof TIPOS_CONVERSACION)[number],
      ))
      .map((actividad) => actividad.lead_id),
  )
  const reunionRealizada = new Set(
    actividades
      .filter((actividad) => actividad.tipo === 'reunion_realizada')
      .map((actividad) => actividad.lead_id),
  )
  const reunionPactada = new Set<string>()
  for (const tarea of tareas) {
    if (tarea.tipo !== 'reunion' || !tarea.lead_id) continue
    reunionPactada.add(tarea.lead_id)
    if (tarea.estado === 'completada') reunionRealizada.add(tarea.lead_id)
  }

  for (const lead of leads) {
    if (!lead.activo || !perteneceAlPeriodo(lead.creado_en, desde, hasta)) continue
    const clave = lead.vendedor_id ?? SIN_VENDEDOR
    let fila = filas.get(clave)
    if (!fila) {
      fila = filaVacia(
        lead.vendedor_id ?? null,
        lead.vendedor_id ? (lead.vendedor_nombre ?? 'Vendedor no disponible') : 'Sin vendedor asignado',
        lead.asignado_supervisor_id
          ? (nombreSupervisor.get(lead.asignado_supervisor_id) ?? 'Sin supervisor')
          : 'Sin supervisor',
      )
      filas.set(clave, fila)
    }

    // Solo una inversión formalizada cuenta como cliente. Un perfil convertido
    // sin contrato puede seguir siendo parte del seguimiento comercial.
    const esCliente = lead.contrato_id != null
    const llegoAReunion = lead.etapa === 'reunion_agendada'
      || lead.etapa === 'propuesta_enviada'
      || reunionPactada.has(lead.id)
    const fueContactado = esCliente
      || lead.etapa === 'convertido'
      || lead.etapa === 'contactado'
      || llegoAReunion
      || contactoReal.has(lead.id)

    fila.leads += 1
    if (fueContactado) fila.contactados += 1
    if (llegoAReunion) fila.reunionesPactadas += 1
    if (reunionRealizada.has(lead.id)) fila.reunionesRealizadas += 1
    if (esCliente) fila.clientes += 1
    if (lead.etapa === 'descartado') fila.descartados += 1
  }

  return [...filas.values()]
    .map((fila) => ({ ...fila, conversionPct: porcentaje(fila.clientes, fila.leads) }))
    .sort((a, b) => {
      if ((a.leads > 0) !== (b.leads > 0)) return a.leads > 0 ? -1 : 1
      return (b.conversionPct ?? -1) - (a.conversionPct ?? -1)
        || b.clientes - a.clientes
        || b.leads - a.leads
        || a.nombre.localeCompare(b.nombre, 'es')
    })
}
