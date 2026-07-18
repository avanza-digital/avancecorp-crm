/**
 * Frontera pura de atribucion para convertir un lead.
 * Debe ejecutarse antes de dedup, Auth, public.perfiles y correo.
 *
 * @param {{ vendedor_id?: string | null }} lead
 * @param {string} callerId
 * @returns {string | null}
 */
export function errorResponsabilidadConversion(lead, callerId) {
  if (!lead.vendedor_id) {
    return 'Asigna el lead a un analista antes de convertirlo';
  }
  if (lead.vendedor_id !== callerId) {
    return 'La conversión la realiza el analista responsable; reasígnate el lead primero';
  }
  return null;
}
