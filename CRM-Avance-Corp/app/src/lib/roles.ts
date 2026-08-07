// Fuente única de capacidades por rol (patrón VITANOVA, 4 niveles).
// NO es seguridad (eso vive en la RLS del esquema crm) — es la UX.
// Regla de oro: lo que can() oculta, la RLS también lo niega.

/** Catálogo runtime de roles CRM — fuente única: el tipo `Rol` se deriva de aquí.
 * `coordinador` (C1, 2026-07-22) es OFF-ROSTER como `directorio`: existe como
 * identidad y como fila real de crm.equipo (para que las RPC lo gateen), pero
 * NUNCA como fila de roster visible (ver Miembro.rol_crm en tipos.ts). */
export const ROLES = ['vendedor', 'supervisor', 'gerencia', 'directorio', 'coordinador'] as const

export type Rol = (typeof ROLES)[number]

/** Type guard para datos externos (Supabase/JSON): ¿es un rol CRM válido? */
export function esRol(valor: unknown): valor is Rol {
  return typeof valor === 'string' && (ROLES as readonly string[]).includes(valor)
}

/** Catálogo runtime de capacidades. El tipo y las pruebas se derivan de aquí. */
export const ACCIONES = [
  'verTodo',            // ámbito completo de la empresa
  'verEquipo',          // ver a otros miembros del equipo
  'filtrarPorVendedor',
  'reasignar',
  'repartirLeads',      // supervisor: baja leads de su bandeja a sus vendedores
  'repartirCola',       // coordinador: reparte la COLA GLOBAL a las bandejas (C1)
  'verPipeline',
  'verLeads',
  'verAgenda',
  'verGestionEquipo',
  'verAlertas',         // bandeja por destinatario (propia, equipo o ejecutiva)
  'verCartera',         // pantalla unificada Clientes+Contratos ('mi-cartera')
  'verConfiguracion',   // pantalla 'config' — incluye la suscripción ICS PROPIA
  'editarConfiguracion',
  'verReportes',
  'editarMetas',
  'editarCapacidad',
  'soloLecturaTotal',   // directorio/auditoría: NO escribe NADA (ni lo propio)
] as const

export type Accion = (typeof ACCIONES)[number]

export type Caps = Record<Accion, boolean>

export const CAPS: Record<Rol, Caps> = {
  // El vendedor VE Configuración (no la edita): ahí vive "Mi calendario de
  // Google", la suscripción ICS que lleva SU agenda al celular, y con
  // verConfiguracion:false esa pantalla no existía para él — ni en el nav ni por
  // URL (sanearVista lo expulsaba) — justo para el único rol que trabaja en la
  // calle. No se abre nada más: editarConfiguracion sigue en false (las metas
  // del mes y toda escritura de configuración siguen siendo de gerencia) y la
  // tarjeta ICS pide SIEMPRE el perfil propio (perfil_id = yo.id, espejo de la
  // RLS "cada quien SU fila" en crm.agenda_ics): nadie exporta agenda ajena.
  vendedor: {
    verTodo: false, verEquipo: false, filtrarPorVendedor: false,
    reasignar: false, repartirLeads: false, repartirCola: false, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: false,
    verAlertas: true,
    verConfiguracion: true, editarConfiguracion: false,
    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
  },
  supervisor: {
    verTodo: false, verEquipo: true, filtrarPorVendedor: true,
    reasignar: true, repartirLeads: true, repartirCola: false, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    verAlertas: true,
    verConfiguracion: false, editarConfiguracion: false,
    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
  },
  gerencia: {
    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    reasignar: true, repartirLeads: true, repartirCola: true, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    verAlertas: true,
    verConfiguracion: true, editarConfiguracion: true,
    verReportes: true, editarMetas: true, editarCapacidad: true, soloLecturaTotal: false,
  },
  directorio: {
    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    reasignar: false, repartirLeads: false, repartirCola: false, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    verAlertas: false,
    verConfiguracion: true, editarConfiguracion: false,
    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: true,
  },
  // Coordinador (C1): SOLO reparte la cola global a las bandejas de supervisión.
  // verTodo:false es CRÍTICO — su ámbito de leads es ∅ (espejo exacto de la RLS:
  // private.vendedor_ids_visibles devuelve vacío para este rol). No tiene cartera
  // ni equipo: su único destino es la pantalla "Repartir leads".
  coordinador: {
    verTodo: false, verEquipo: false, filtrarPorVendedor: false,
    reasignar: false, repartirLeads: false, repartirCola: true, verCartera: false,
    verPipeline: false, verLeads: false, verAgenda: false, verGestionEquipo: false,
    verAlertas: false,
    verConfiguracion: false, editarConfiguracion: false,
    verReportes: false, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
  },
}

export const ROL_LABEL: Record<Rol, string> = {
  vendedor: 'Vendedor',
  supervisor: 'Supervisor',
  gerencia: 'Gerencia',
  directorio: 'Directorio',
  coordinador: 'Coordinador',
}

/**
 * can(rol, accion) — rol nulo o desconocido degrada a SOLO LECTURA TOTAL
 * (mínimo privilegio de escritura: jamás un default escritor).
 */
export function can(rol: Rol | null | undefined, accion: Accion): boolean {
  const c = rol ? CAPS[rol] : undefined
  if (!c) return accion === 'soloLecturaTotal'
  return !!c[accion]
}

/** ¿El rol puede escribir en general? (directorio nunca) */
export function puedeEscribir(rol: Rol | null | undefined): boolean {
  return !can(rol, 'soloLecturaTotal')
}

/** Identidad mínima para capacidades que cruzan la frontera Portal ↔ CRM. */
export interface IdentidadAdministrativa {
  rol?: Rol | null
  rol_portal?: string | null
  capacidades_config?: {
    puede_listar_usuarios: boolean
    puede_administrar_usuarios: boolean
    puede_organizar_jerarquia: boolean
    puede_administrar_roles: boolean
  }
}

/** Gerencia administra las personas y el estado de su membresía CRM. */
export function puedeAdministrarUsuariosCrm(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.capacidades_config?.puede_administrar_usuarios
    ?? identidad?.rol === 'gerencia'
}

/** La jerarquía pertenece exclusivamente a Gerencia. */
export function puedeOrganizarJerarquiaCrm(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.capacidades_config?.puede_organizar_jerarquia
    ?? identidad?.rol === 'gerencia'
}

/** Superadmin Portal solo asigna o cambia roles CRM. */
export function puedeAdministrarRolesCrm(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.capacidades_config?.puede_administrar_roles
    ?? identidad?.rol_portal === 'superadmin'
}

/**
 * Superadmin Portal gobierna roles, no hereda por ello la operación comercial.
 * Gerencia + Superadmin sí suma ambas autoridades de forma explícita.
 */
export function administraSoloRolesCrm(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.rol !== 'gerencia' && puedeAdministrarRolesCrm(identidad)
}

/** Directorio audita; Gerencia administra; Superadmin ve el mínimo para roles. */
export function puedeVerDirectorioUsuariosCrm(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.capacidades_config?.puede_listar_usuarios
    ?? (
      identidad?.rol === 'gerencia'
      || identidad?.rol === 'directorio'
      || identidad?.rol_portal === 'superadmin'
    )
}
