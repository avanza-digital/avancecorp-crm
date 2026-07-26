// lib/telefono.ts — el teléfono del lead convertido en algo marcable.
//
// Vive fuera de `contacto.tsx` por `react(only-export-components)`, y porque el
// criterio estaba DUPLICADO Y DIVERGENTE: `contacto.tsx` armaba el enlace de
// WhatsApp con `replace('+','')` —que deja espacios y guiones DENTRO de la URL
// de wa.me— mientras `recordatorio.ts` usaba `replace(/\D/g,'')` con un
// comentario que afirmaba ser "el mismo criterio que AccionesContacto". No lo
// era. Una sola fuente.

/** Solo los dígitos: quita `+`, espacios, guiones y paréntesis. */
export function soloDigitos(tel: string | null | undefined): string {
  return (tel ?? '').replace(/\D/g, '')
}

/**
 * Enlace `tel:` para el marcador del celular, o `null` si el número no sirve.
 *
 * ⚠️ EL `+` NO SE INVENTA. En la base hay números guardados sin código de país
 * (`999888777`): anteponerles `+` los convertiría en `+999…`, que no es Perú y
 * marcaría a otro lado. Sin `+`, la propia red del celular lo resuelve como
 * número local, que es lo que queremos. Aquí no se añade el `51` a nadie.
 *
 * El mínimo de 7 dígitos deja fuera basura y campos a medio llenar sin
 * inventar reglas de numeración: ni un fijo de Lima baja de ahí.
 */
export function enlaceTel(tel: string | null | undefined): string | null {
  const digitos = soloDigitos(tel)
  if (digitos.length < 7) return null
  return `tel:${(tel ?? '').trim().startsWith('+') ? '+' : ''}${digitos}`
}

/**
 * Número para `wa.me`, que exige dígitos SIN `+` y sin separadores.
 * `null` si no hay número utilizable (mismo mínimo que `enlaceTel`).
 */
export function numeroWhatsapp(tel: string | null | undefined): string | null {
  const digitos = soloDigitos(tel)
  return digitos.length >= 7 ? digitos : null
}
