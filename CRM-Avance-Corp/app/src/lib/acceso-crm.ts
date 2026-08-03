import { esRol, type Rol } from './roles'

const ROLES_MIEMBRO = new Set<Rol>(['vendedor', 'supervisor', 'gerencia', 'coordinador'])
const ROLES_PORTAL_QUE_CONTRATAN = new Set(['analista', 'admin', 'superadmin'])

type AccesoCrmInterpretado =
  | { tipo: 'acceso'; perfilId: string; rol: Rol; nombre: string; puedeContratar: boolean }
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

  if (valor.estado !== 'miembro' && valor.estado !== 'global') {
    throw new TypeError('Estado de acceso CRM desconocido')
  }
  if (!esRol(valor.rol_crm)) {
    throw new TypeError('Rol CRM inválido')
  }
  if (valor.estado === 'global' && valor.rol_crm !== 'directorio') {
    throw new TypeError('Fallback global inválido')
  }
  if (valor.estado === 'miembro' && !ROLES_MIEMBRO.has(valor.rol_crm)) {
    throw new TypeError('Rol de membresía CRM inválido')
  }
  if (typeof valor.rol_portal !== 'string') {
    throw new TypeError('Rol de portal inválido')
  }
  if (valor.nombre_completo !== null && typeof valor.nombre_completo !== 'string') {
    throw new TypeError('Nombre de perfil inválido')
  }

  return {
    tipo: 'acceso',
    perfilId: valor.perfil_id,
    rol: valor.rol_crm,
    nombre: valor.nombre_completo ?? '',
    puedeContratar: ROLES_PORTAL_QUE_CONTRATAN.has(valor.rol_portal),
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
