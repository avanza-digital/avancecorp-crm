/**
 * Interpreta la capacidad canónica devuelta por crm.mi_acceso_fn().
 * La autorización se resuelve en PostgreSQL; las edges solo ligan la respuesta
 * a la sesión verificada y fallan cerradas ante un contrato incompleto.
 *
 * @param {unknown} valor
 * @param {string} callerId
 * @returns {{ rolCrm: string } | null}
 */
export function contextoContratacionDesdeAcceso(valor, callerId) {
  if (!valor || typeof valor !== 'object' || Array.isArray(valor)) return null;

  const acceso = /** @type {Record<string, unknown>} */ (valor);
  if (
    acceso.estado !== 'miembro'
    || acceso.perfil_id !== callerId
    || acceso.puede_contratar !== true
    || typeof acceso.rol_crm !== 'string'
    || acceso.rol_crm.trim().length === 0
  ) {
    return null;
  }

  return { rolCrm: acceso.rol_crm };
}
