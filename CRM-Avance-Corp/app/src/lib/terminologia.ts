/**
 * Traduce la terminología histórica de reuniones únicamente al presentar texto.
 *
 * Los contratos internos conservan `reunion`, `reunion_agendada`, nombres de
 * campos y RPC. Esta función cubre texto ya persistido o devuelto por el
 * servidor para que también respete el vocabulario vigente del frontend.
 */
function conservarMayusculas(palabra: string, reemplazo: string): string {
  if (palabra === palabra.toLocaleUpperCase('es-PE')) {
    return reemplazo.toLocaleUpperCase('es-PE')
  }
  if (palabra[0] === palabra[0]?.toLocaleUpperCase('es-PE')) {
    return reemplazo[0]?.toLocaleUpperCase('es-PE') + reemplazo.slice(1)
  }
  return reemplazo
}

export function presentarCitas(texto: string): string {
  return texto.replace(/\b(reuniones|reunión|reunion)\b/giu, (palabra) =>
    conservarMayusculas(
      palabra,
      palabra.toLocaleLowerCase('es-PE') === 'reuniones' ? 'citas' : 'cita',
    ))
}

/** Convierte copy nuevo al vocabulario histórico antes de persistir/consultar. */
export function normalizarCitasInternas(texto: string): string {
  return texto.replace(/\b(citas|cita)\b/giu, (palabra) =>
    conservarMayusculas(
      palabra,
      palabra.toLocaleLowerCase('es-PE') === 'citas' ? 'reuniones' : 'reunión',
    ))
}
