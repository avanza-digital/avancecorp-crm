// Parseo de montos escritos a mano (capital, tasa) — fuente única.
//
// Por qué existe: `Number('125,000'.replace(',', '.'))` = 125. Un capital
// escrito con coma de MILES (formato es-PE que hasta nuestros mensajes de error
// sugieren: "entre 100 y 100,000,000") pasaba todas las validaciones y creaba
// un contrato 1000 veces menor, en silencio (hallazgo ALTA, revisión 2026-07-16).
//
// Regla: solo dígitos con UN separador decimal opcional (coma o punto) de 1-2
// decimales. Todo lo demás — separador de miles, dos separadores, letras — se
// rechaza con null para que el formulario lo diga en voz alta, nunca adivine.
const RE_MONTO = /^\d+(?:[.,]\d{1,2})?$/

export function parseMonto(texto: string): number | null {
  const t = texto.trim()
  if (!RE_MONTO.test(t)) return null
  const n = Number(t.replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

/** Mensaje único para un monto ilegible (reusado por capital y tasa). */
export const ERROR_MONTO = 'Escribe el monto solo con números, sin separador de miles (usa coma o punto únicamente para decimales, ej. 125000 o 125000.50)'
