import { contextoContratacionDesdeAcceso } from '../_shared/acceso-crm.mjs';

const ROLES_PORTAL_ALTA_CLIENTE = new Set([
  'admin',
  'superadmin',
  'analista',
  'operaciones',
]);
const ESTADOS_ACCESO_CONOCIDOS = new Set([
  'miembro',
  'global',
  'administrador_roles',
  'revocado',
  'no_enrolado',
]);

/**
 * Une las dos autoridades legítimas de esta edge:
 * - compatibilidad del Portal para sus roles históricos;
 * - capacidad operativa CRM publicada por crm.mi_acceso_fn().
 *
 * Una revocación CRM explícita gana sobre el fallback Portal. Los usuarios
 * `comercial + vendedor` quedan autoasignados igual que un Analista legacy.
 *
 * @param {unknown} perfil
 * @param {unknown} acceso
 * @param {string} callerId
 * @returns {{ asesorId: string | null, via: 'portal' | 'crm' } | null}
 */
export function resolverAutorizacionAltaCliente(perfil, acceso, callerId) {
  if (!perfil || typeof perfil !== 'object' || Array.isArray(perfil)) return null;
  const perfilSeguro = /** @type {Record<string, unknown>} */ (perfil);
  if (perfilSeguro.activo !== true || typeof perfilSeguro.rol !== 'string') return null;

  if (!acceso || typeof acceso !== 'object' || Array.isArray(acceso)) return null;
  const accesoSeguro = /** @type {Record<string, unknown>} */ (acceso);
  if (
    accesoSeguro.perfil_id !== callerId
    || !ESTADOS_ACCESO_CONOCIDOS.has(String(accesoSeguro.estado))
    || typeof accesoSeguro.puede_contratar !== 'boolean'
    || accesoSeguro.estado === 'revocado'
  ) return null;

  if (ROLES_PORTAL_ALTA_CLIENTE.has(perfilSeguro.rol)) {
    return {
      asesorId: perfilSeguro.rol === 'analista' ? callerId : null,
      via: 'portal',
    };
  }

  const contextoCrm = contextoContratacionDesdeAcceso(accesoSeguro, callerId);
  if (!contextoCrm) return null;

  return {
    asesorId: contextoCrm.rolCrm === 'vendedor' ? callerId : null,
    via: 'crm',
  };
}
