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
  'repartirLeads',      // supervisor: baja leads de su bandeja a sus analistas
  'repartirCola',       // coordinador: reparte la COLA GLOBAL a las bandejas (C1)
  'verPipeline',
  'verLeads',
  'verAgenda',
  'verGestionEquipo',
  'verDerivacionesEquipo', // módulo de reparto propio del supervisor
  'verFacturacion',     // tablero Facturación: Gerencia ve la empresa, Supervisión
                        // SU equipo (Miguel, 16/09/2026); espejo de la verja de
                        // crm.facturacion_diaria_fn, que a los demás les da vacío
  'verAlertas',         // bandeja por destinatario (propia, equipo o ejecutiva)
  'tomarLeadDirecto',   // F2 lead libre: tomar para SÍ un contacto en bolsa o
                        // reutilizable tras verificar — SOLO analista (espejo
                        // del guard de crm.tomar_lead_libre: supervisión
                        // asigna por el reparto, jamás por esta puerta)
  'verCartera',         // pantalla unificada Clientes+Contratos ('mi-cartera')
  'altaDirectaCliente', // «Nuevo cliente» en Mi cartera = alta SIN lead. Cerrada
                        // al analista (decisión de Miguel, 15/09/2026): su
                        // cliente nuevo nace CONVIRTIENDO un lead, para que el
                        // capital del ranking no entre por fuera de la
                        // conversión (caso real: S/ 222 450 en el puesto 1 del
                        // ranking con 0 % de conversión, todo por esta puerta).
                        // Supervisión y Gerencia la conservan: no rankean.
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
  // El analista VE Configuración (no la edita): ahí vive "Mi calendario de
  // Google", la suscripción ICS que lleva SU agenda al celular, y con
  // verConfiguracion:false esa pantalla no existía para él — ni en el nav ni por
  // URL (sanearVista lo expulsaba) — justo para el único rol que trabaja en la
  // calle. No se abre nada más: editarConfiguracion sigue en false (las metas
  // del mes y toda escritura de configuración siguen siendo de gerencia) y la
  // tarjeta ICS pide SIEMPRE el perfil propio (perfil_id = yo.id, espejo de la
  // RLS "cada quien SU fila" en crm.agenda_ics): nadie exporta agenda ajena.
  vendedor: {
    verTodo: false, verEquipo: false, filtrarPorVendedor: false,
    altaDirectaCliente: false,
    reasignar: false, repartirLeads: false, repartirCola: false, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: false,
    verDerivacionesEquipo: false,
    verFacturacion: false,
    verAlertas: true, tomarLeadDirecto: true,
    verConfiguracion: true, editarConfiguracion: false,
    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
  },
  supervisor: {
    verTodo: false, verEquipo: true, filtrarPorVendedor: true,
    altaDirectaCliente: true,
    reasignar: true, repartirLeads: true, repartirCola: false, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    verDerivacionesEquipo: true,
    verFacturacion: true,
    verAlertas: true, tomarLeadDirecto: false,
    verConfiguracion: false, editarConfiguracion: false,
    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
  },
  gerencia: {
    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    altaDirectaCliente: true,
    reasignar: true, repartirLeads: true, repartirCola: true, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    verDerivacionesEquipo: false,
    verFacturacion: true,
    verAlertas: true, tomarLeadDirecto: false,
    verConfiguracion: true, editarConfiguracion: true,
    verReportes: true, editarMetas: true, editarCapacidad: true, soloLecturaTotal: false,
  },
  directorio: {
    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    altaDirectaCliente: false,
    reasignar: false, repartirLeads: false, repartirCola: false, verCartera: true,
    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    verDerivacionesEquipo: false,
    verFacturacion: false,
    verAlertas: false, tomarLeadDirecto: false,
    verConfiguracion: true, editarConfiguracion: false,
    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: true,
  },
  // Coordinador (C1): SOLO reparte la cola global a las bandejas de supervisión.
  // verTodo:false es CRÍTICO — su ámbito de leads es ∅ (espejo exacto de la RLS:
  // private.vendedor_ids_visibles devuelve vacío para este rol). No tiene cartera
  // ni equipo: su único destino es la pantalla "Repartir leads".
  coordinador: {
    verTodo: false, verEquipo: false, filtrarPorVendedor: false,
    altaDirectaCliente: false,
    reasignar: false, repartirLeads: false, repartirCola: true, verCartera: false,
    verPipeline: false, verLeads: false, verAgenda: false, verGestionEquipo: false,
    verDerivacionesEquipo: false,
    verFacturacion: false,
    verAlertas: false, tomarLeadDirecto: false,
    verConfiguracion: false, editarConfiguracion: false,
    verReportes: false, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
  },
}

export const ROL_LABEL: Record<Rol, string> = {
  vendedor: 'Analista',
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
  identidad: IdentidadAdministrativa | null | undefined): boolean {
  return identidad?.capacidades_config?.puede_administrar_usuarios
    ?? identidad?.rol === 'gerencia'
}

/** La jerarquía pertenece exclusivamente a Gerencia. */
export function puedeOrganizarJerarquiaCrm(
  identidad: IdentidadAdministrativa | null | undefined): boolean {
  return identidad?.capacidades_config?.puede_organizar_jerarquia
    ?? identidad?.rol === 'gerencia'
}

/** Superadmin Portal solo asigna o cambia roles CRM. */
export function puedeAdministrarRolesCrm(
  identidad: IdentidadAdministrativa | null | undefined): boolean {
  return identidad?.capacidades_config?.puede_administrar_roles
    ?? identidad?.rol_portal === 'superadmin'
}

/** El hard-delete contractual pertenece solo a Admin/Superadmin del Portal. */
export function puedeEliminarContratos(identidad: IdentidadAdministrativa | null | undefined): boolean {
  return identidad?.rol_portal === 'admin' || identidad?.rol_portal === 'superadmin'
}

/** La correccion auditada del documento pertenece a Admin/Superadmin del Portal. */
export function puedeCorregirDocumentoCliente(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.rol_portal === 'admin' || identidad?.rol_portal === 'superadmin'
}

/**
 * Admin y Superadmin pueden corregir el correo de CLIENTES (15/09/2026).
 *
 * No es un dato de contacto, es la CREDENCIAL DE ACCESO al portal, y vive a la
 * vez en `auth.users`, `auth.identities` y `perfiles.correo`. Un cambio mal
 * hecho deja al cliente sin poder entrar. La Edge revalida el rol activo.
 *
 * Espejo del gate administrativo del servidor: esto no decide nada, solo evita
 * ofrecer un campo que iba a terminar en «no autorizado».
 */
export function puedeCorregirCorreoCliente(
  identidad: IdentidadAdministrativa | null | undefined,
): boolean {
  return identidad?.rol_portal === 'admin' || identidad?.rol_portal === 'superadmin'
}

/** Configura borradores de Citas; la RPC verifica el perfil Superadmin activo. */
export function puedeConfigurarCitas(identidad: IdentidadAdministrativa | null | undefined): boolean {
  return identidad?.rol_portal === 'superadmin'
}

/**
 * Quién puede pasar una venta de un analista a otro (P-055 Fase 3).
 *
 * Es el ESPEJO EXACTO del gate del servidor en
 * `public.reasignar_analista_contrato`: gestor de cartera del portal (admin o
 * superadmin) o gerencia del CRM. No decide nada — el servidor vuelve a
 * comprobarlo y además exige motivo; esto solo evita ofrecer un botón que iba a
 * terminar en «no autorizado».
 */
export function puedeReasignarVenta(identidad: IdentidadAdministrativa | null | undefined): boolean {
  return puedeEliminarContratos(identidad) || identidad?.rol === 'gerencia'
}

/**
 * Superadmin Portal gobierna roles, no hereda por ello la operación comercial.
 * Gerencia + Superadmin sí suma ambas autoridades de forma explícita.
 */
export function administraSoloRolesCrm(
  identidad: IdentidadAdministrativa | null | undefined): boolean {
  return identidad?.rol !== 'gerencia' && puedeAdministrarRolesCrm(identidad)
}

/** Directorio audita; Gerencia administra; Superadmin ve el mínimo para roles. */
export function puedeVerDirectorioUsuariosCrm(
  identidad: IdentidadAdministrativa | null | undefined): boolean {
  return (
    identidad?.capacidades_config?.puede_listar_usuarios
    ?? (
      identidad?.rol === 'gerencia'
      || identidad?.rol === 'directorio'
      || identidad?.rol_portal === 'superadmin'
    )
  )
}
