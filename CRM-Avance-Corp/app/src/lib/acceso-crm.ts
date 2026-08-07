import { esRol, type Rol } from './roles'

const ROLES_MIEMBRO = new Set<Rol>([
  'vendedor',
  'supervisor',
  'gerencia',
  'directorio',
  'coordinador',
])
const ROLES_PORTAL_QUE_CONTRATAN = new Set(['analista', 'admin', 'superadmin'])

type AccesoCrmInterpretado =
  | {
      tipo: 'acceso'
      perfilId: string
      rol: Rol
      rolPortal: string
      capacidadesConfig: {
        puedeListarUsuarios: boolean
        puedeAdministrarUsuarios: boolean
        puedeOrganizarJerarquia: boolean
        puedeAdministrarRoles: boolean
      }
      nombre: string
      puedeContratar: boolean
    }
  | { tipo: 'sin_acceso'; perfilId: string }

function esRegistro(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === 'object' && valor !== null && !Array.isArray(valor)
}

/** Valida en runtime el jsonb de crm.mi_acceso_fn antes de convertirlo en UX. */
export function interpretarMiAcceso(valor: unknown): AccesoCrmInterpretado {
  if (!esRegistro(valor) || typeof valor.estado !== 'string') {
    throw new TypeError('Respuesta de acceso CRM inválida')
  }
  if (typeof valor.perfil_id !== 'string' || valor.perfil_id.length === 0) {
    throw new TypeError('Identidad de acceso CRM inválida')
  }

  if (valor.estado === 'revocado' || valor.estado === 'no_enrolado') {
    return { tipo: 'sin_acceso', perfilId: valor.perfil_id }
  }

  if (
    valor.estado !== 'miembro'
    && valor.estado !== 'global'
    && valor.estado !== 'administrador_roles'
  ) {
    throw new TypeError('Estado de acceso CRM desconocido')
  }
  if (typeof valor.rol_portal !== 'string') {
    throw new TypeError('Rol de portal inválido')
  }
  if (valor.nombre_completo !== null && typeof valor.nombre_completo !== 'string') {
    throw new TypeError('Nombre de perfil inválido')
  }
  for (const clave of [
    'puede_listar_usuarios',
    'puede_administrar_usuarios',
    'puede_organizar_jerarquia',
    'puede_administrar_roles',
  ] as const) {
    if (typeof valor[clave] !== 'boolean') {
      throw new TypeError('Capacidades de configuración inválidas')
    }
  }

  if (valor.estado === 'administrador_roles') {
    if (
      Object.hasOwn(valor, 'rol_crm')
      || valor.rol_portal !== 'superadmin'
      || valor.puede_listar_usuarios !== true
      || valor.puede_administrar_usuarios !== false
      || valor.puede_organizar_jerarquia !== false
      || valor.puede_administrar_roles !== true
    ) {
      throw new TypeError('Autoridad de roles inválida')
    }
    return {
      tipo: 'acceso',
      perfilId: valor.perfil_id,
      // `Yo` conserva un Rol para no ensanchar toda la app; la capacidad viva
      // de roles activa el guard que reduce navegación y datos a Usuarios.
      rol: 'directorio',
      rolPortal: valor.rol_portal,
      capacidadesConfig: {
        puedeListarUsuarios: true,
        puedeAdministrarUsuarios: false,
        puedeOrganizarJerarquia: false,
        puedeAdministrarRoles: true,
      },
      nombre: valor.nombre_completo ?? '',
      puedeContratar: false,
    }
  }

  if (!esRol(valor.rol_crm)) {
    throw new TypeError('Rol CRM inválido')
  }
  if (
    valor.estado === 'global'
    && (valor.rol_crm !== 'directorio' || valor.rol_portal !== 'directorio')
  ) {
    throw new TypeError('Fallback global inválido')
  }
  if (valor.estado === 'miembro' && !ROLES_MIEMBRO.has(valor.rol_crm)) {
    throw new TypeError('Rol de membresía CRM inválido')
  }
  if (valor.estado === 'miembro' && valor.rol_portal === 'superadmin' && valor.rol_crm !== 'gerencia') {
    throw new TypeError('Superadmin operativo inválido')
  }

  return {
    tipo: 'acceso',
    perfilId: valor.perfil_id,
    rol: valor.rol_crm,
    // Algunas capacidades administrativas pertenecen al Portal (superadmin),
    // no al rol operativo CRM. La frontera real se valida otra vez en servidor.
    rolPortal: valor.rol_portal,
    capacidadesConfig: {
      puedeListarUsuarios: valor.puede_listar_usuarios as boolean,
      puedeAdministrarUsuarios: valor.puede_administrar_usuarios as boolean,
      puedeOrganizarJerarquia: valor.puede_organizar_jerarquia as boolean,
      puedeAdministrarRoles: valor.puede_administrar_roles as boolean,
    },
    nombre: valor.nombre_completo ?? '',
    // Gerencia opera el CRM completo sin convertirse en admin del portal. Las
    // edges/RPC vuelven a comprobar la membresía activa en el servidor.
    puedeContratar:
      valor.rol_crm === 'gerencia' || ROLES_PORTAL_QUE_CONTRATAN.has(valor.rol_portal),
  }
}

/** Liga la respuesta al getUser() que inició la verificación; una carrera de sesión falla cerrada. */
export function interpretarMiAccesoParaUsuario(
  valor: unknown,
  perfilEsperado: string,
): AccesoCrmInterpretado {
  const acceso = interpretarMiAcceso(valor)
  if (acceso.perfilId !== perfilEsperado) {
    throw new TypeError('La identidad cambió durante la resolución de acceso')
  }
  return acceso
}
