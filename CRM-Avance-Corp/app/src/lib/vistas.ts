// Política única de acceso a vistas para la UX. Sidebar y App consumen estas
// funciones; la seguridad real permanece en la RLS del esquema crm.
import { can, esRol, type Accion, type Rol } from '@/lib/roles'
import { esVistaConfiguracion, esVistaGerencia, esVistaLeads, type Vista } from '@/lib/router'

type EstadoGateLeads = 'abierto' | 'cerrado'

/** Landing exhaustiva por rol; no concede acceso a ninguna otra vista. */
const VISTA_BASE_POR_ROL = {
  vendedor: { abierto: 'hoy', cerrado: 'mi-cartera' },
  supervisor: { abierto: 'hoy', cerrado: 'mi-cartera' },
  gerencia: { abierto: 'hoy', cerrado: 'hoy' },
  directorio: { abierto: 'hoy', cerrado: 'mi-cartera' },
  coordinador: { abierto: 'repartir', cerrado: 'repartir' },
} as const satisfies Record<Rol, Record<EstadoGateLeads, Vista>>

/**
 * Capacidad exigida por cada vista. `hoy` conserva su acceso histórico por rol
 * y gate; el contenido interno continúa aplicando sus capacidades específicas.
 */
const CAPACIDAD_POR_VISTA = {
  hoy: null,
  alertas: 'verAlertas',
  conversiones: null,
  'ranking-vendedores': null,
  reuniones: null,
  metas: null,
  rendimiento: null,
  pipeline: 'verPipeline',
  cartera: 'verLeads',
  agenda: 'verAgenda',
  'mi-cartera': 'verCartera',
  repartir: 'repartirCola',
  rescate: 'repartirLeads',
  'rescate-carpeta': 'repartirLeads',
  derivaciones: 'verDerivacionesEquipo',
  equipo: 'verGestionEquipo',
  config: 'verConfiguracion',
  'config-usuarios': null,
  'config-productos': null,
  'config-metas': null,
  'config-sla': null,
} as const satisfies Record<Vista, Accion | null>

/** Dónde aterriza un rol cuando la ruta pedida no existe o no está permitida. */
export function vistaBase(
  rol: Rol | null | undefined,
  leadsVisibles: boolean,
  rolPortal?: string | null,
): Vista {
  // Compatibilidad defensiva: Workspace solo se monta con un perfil enrolado,
  // pero los callers históricos conservan el mismo fallback para un rol ausente.
  if (!esRol(rol)) return leadsVisibles ? 'hoy' : 'mi-cartera'
  // La autoridad Portal para gobernar roles no convierte a Superadmin en un
  // lector/operador CRM. Gerencia + Superadmin conserva la landing de Gerencia.
  if (rolPortal === 'superadmin' && rol !== 'gerencia') return 'config-usuarios'
  const estado: EstadoGateLeads = leadsVisibles ? 'abierto' : 'cerrado'
  return VISTA_BASE_POR_ROL[rol][estado]
}

/**
 * Única decisión de acceso a una vista. Es fail-closed para identidades ajenas
 * al catálogo y mantiene la landing de Gerencia en Hoy aun si el gate se cierra.
 */
export function vistaPermitida(
  vista: Vista,
  rol: Rol | null | undefined,
  leadsVisibles: boolean,
  rolPortal?: string | null,
): boolean {
  if (!esRol(rol)) return false
  if (rolPortal === 'superadmin' && rol !== 'gerencia') {
    return vista === 'config-usuarios'
  }
  if (vista === vistaBase(rol, leadsVisibles, rolPortal)) return true
  // La bandeja es transversal, pero sus fuentes operativas dependen del gate
  // de leads. Gerencia conserva siempre sus alertas ejecutivas agregadas.
  if (vista === 'alertas') {
    return can(rol, 'verAlertas') && (rol === 'gerencia' || leadsVisibles)
  }
  if (esVistaConfiguracion(vista)) {
    if (vista === 'config-usuarios' && rolPortal === 'superadmin') return true
    return rol === 'gerencia' || rol === 'directorio'
  }
  if (esVistaGerencia(vista)) return rol === 'gerencia'
  // El mundo leads se cierra por la llave general y, SIEMPRE, para el
  // coordinador: su ámbito de leads es ∅ y su único destino es «Repartir».
  // «hoy» no exige capacidad, así que sin este corte la llave abierta se la
  // regalaría. Defensa en profundidad: config.ts tampoco la enciende para él.
  if (esVistaLeads(vista) && (!leadsVisibles || rol === 'coordinador')) return false

  const capacidad = CAPACIDAD_POR_VISTA[vista]
  return capacidad === null || can(rol, capacidad)
}

/** Corrige una vista pedida (hash/estado) a una que el rol SÍ puede ver. */
export function sanearVista(
  vista: Vista,
  rol: Rol | null | undefined,
  leadsVisibles: boolean,
  rolPortal?: string | null,
): Vista {
  return vistaPermitida(vista, rol, leadsVisibles, rolPortal)
    ? vista
    : vistaBase(rol, leadsVisibles, rolPortal)
}
