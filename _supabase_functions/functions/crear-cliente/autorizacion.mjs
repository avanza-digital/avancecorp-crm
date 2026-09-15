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
 * Una revocación CRM explícita gana sobre el fallback Portal.
 *
 * 15/09/2026 (decisión de Miguel): el ANALISTA del CRM (`rol_crm = vendedor`)
 * NO da de alta clientes sin lead — su cliente nuevo nace convirtiendo un lead
 * (crm-convertir-lead), para que el capital del ranking no entre por fuera de
 * la conversión. El veto se evalúa ANTES de la compatibilidad del Portal porque
 * la mayoría de los analistas conserva el rol Portal legacy `analista`, que
 * hasta hoy los autorizaba por esa vía. Supervisión, Gerencia y los roles
 * administrativos del Portal no cambian.
 *
 * @param {unknown} perfil
 * @param {unknown} acceso
 * @param {string} callerId
 * @returns {{ asesorId: string | null, via: 'portal' | 'crm' } | null}
 */
/** @param {unknown} rolCrm */
function esVendedorCrm(rolCrm) {
  return typeof rolCrm === 'string' && rolCrm.trim().toLowerCase() === 'vendedor';
}

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

  // Veto del analista: cualquier contrato que lo identifique como vendedor del
  // CRM cierra la puerta, sea cual sea su rol Portal (fail-closed). Se compara
  // normalizado para no depender de que la RPC entregue el literal exacto.
  if (esVendedorCrm(accesoSeguro.rol_crm)) return null;

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
