/** Normaliza un celular peruano a +519######## (o null si no es válido). */
export function normalizarTelefono(valor: string): string | null {
  const limpio = valor.replace(/[\s().-]/g, '')
  const sinMas = limpio.startsWith('+') ? limpio.slice(1) : limpio
  if (/^9\d{8}$/.test(sinMas)) return `+51${sinMas}`
  if (/^519\d{8}$/.test(sinMas)) return `+${sinMas}`
  return null
}
