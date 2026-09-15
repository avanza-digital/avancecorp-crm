/**
 * Frontera pura de atribucion para convertir un lead.
 * Debe ejecutarse antes de dedup, Auth, public.perfiles y correo.
 *
 * No repite el chequeo de ámbito: `index.ts` ya leyó `lead` con el cliente del
 * caller, y la RLS `leads_select` (vendedor_id in vendedor_ids_visibles(...))
 * es la MISMA función que da el ámbito de gerencia y supervisor en
 * `crm.convertir_lead`/`convertir_lead_externo` — si `lead` llegó aquí, ya
 * está dentro del ámbito de quien llama. Esta función solo decide, dentro de
 * ese ámbito ya garantizado, si el rol puede cerrar la venta de OTRO analista.
 *
 * @param {{ vendedor_id?: string | null }} lead
 * @param {string} callerId
 * @param {string} rolCrm
 * @returns {string | null}
 */
export function errorResponsabilidadConversion(lead, callerId, rolCrm = 'vendedor') {
  if (!lead.vendedor_id) {
    return 'Asigna el lead a un analista antes de convertirlo';
  }
  // Gerencia y supervisor cierran la operación sin apropiarse de la cartera:
  // el vendedor ya asignado permanece como asesor del cliente nuevo. Para
  // supervisor el ámbito (su equipo) ya lo garantizó la RLS al leer `lead`.
  if (rolCrm === 'gerencia' || rolCrm === 'supervisor') return null;
  if (lead.vendedor_id !== callerId) {
    return 'La conversión la realiza el analista responsable; reasígnate el lead primero';
  }
  return null;
}
