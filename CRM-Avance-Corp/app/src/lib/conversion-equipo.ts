import type { Miembro } from './tipos'

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

// `conversionesEquipo` (el agregador viejo que recorría leads+actividades+tareas
// en el navegador) se ELIMINÓ en F1b tanda 2: no tenía ni un solo caller —
// Gerencia migró a crm.metricas_conversiones_fn — y dejarlo vivo invitaba a
// re-cablearlo y reintroducir el escaneo O(leads) en cliente. El terreno que
// cubría lo sirven metricas_conversiones_fn y metricas_vendedores_fn.
