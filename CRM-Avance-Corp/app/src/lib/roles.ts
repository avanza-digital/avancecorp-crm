// Fuente única de capacidades por rol (patrón VITANOVA, 4 niveles).
// NO es seguridad (eso vive en la RLS del esquema crm) — es la UX.
// Regla de oro: lo que can() oculta, la RLS también lo niega.

/** Catálogo runtime de roles CRM — fuente única: el tipo `Rol` se deriva de aquí. */
export const ROLES = ['vendedor', 'supervisor', 'gerencia', 'directorio'] as const

export type Rol = (typeof ROLES)[number]

/** Type guard para datos externos (Supabase/JSON): ¿es un rol CRM válido? */
export function esRol(valor: unknown): valor is Rol {
  return typeof valor === 'string' && (ROLES as readonly string[]).includes(valor)
}

export type Accion =
  | 'verTodo'            // ámbito completo de la empresa
  | 'verEquipo'          // ver a otros miembros del equipo
  | 'filtrarPorVendedor'
  | 'reasignar'
  | 'repartirLeads'
  | 'verConfiguracion'
  | 'editarConfiguracion'
  | 'verReportes'
  | 'soloLecturaTotal'   // directorio/auditoría: NO escribe NADA (ni lo propio)

export type Caps = Record<Accion, boolean>

export const CAPS: Record<Rol, Caps> = {
  vendedor: {
    verTodo: false, verEquipo: false, filtrarPorVendedor: false,
    reasignar: false, repartirLeads: false,
    verConfiguracion: false, editarConfiguracion: false,
    verReportes: true, soloLecturaTotal: false,
  },
  supervisor: {
    verTodo: false, verEquipo: true, filtrarPorVendedor: true,
    reasignar: true, repartirLeads: true,
    verConfiguracion: false, editarConfiguracion: false,
    verReportes: true, soloLecturaTotal: false,
  },
  gerencia: {
    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    reasignar: true, repartirLeads: true,
    verConfiguracion: true, editarConfiguracion: true,
    verReportes: true, soloLecturaTotal: false,
  },
  directorio: {
    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    reasignar: false, repartirLeads: false,
    verConfiguracion: true, editarConfiguracion: false,
    verReportes: true, soloLecturaTotal: true,
  },
}

export const ROL_LABEL: Record<Rol, string> = {
  vendedor: 'Vendedor',
  supervisor: 'Supervisor',
  gerencia: 'Gerencia',
  directorio: 'Directorio',
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
