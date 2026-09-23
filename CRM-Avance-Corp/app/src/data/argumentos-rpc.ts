/**
 * Argumentos OPCIONALES de una RPC: se omiten en vez de mandarse en null.
 *
 * El generador de tipos (CLI 2.114.0) declara los argumentos con DEFAULT como
 * `x?: T`, sin `null`, y el proyecto compila con `exactOptionalPropertyTypes`,
 * así que tampoco vale `undefined` explícito: la clave tiene que NO estar.
 * Solo se usa con argumentos cuyo DEFAULT en el servidor es NULL, donde omitir
 * y mandar null dan exactamente el mismo resultado.
 */
export function soloPresentes<T extends Record<string, unknown>>(
  valores: T,
): { [K in keyof T]?: Exclude<T[K], null | undefined> } {
  return Object.fromEntries(
    Object.entries(valores).filter(([, valor]) => valor !== null && valor !== undefined),
  ) as { [K in keyof T]?: Exclude<T[K], null | undefined> }
}
