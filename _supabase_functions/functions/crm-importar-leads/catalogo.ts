// Catálogos de la hoja (canal, interés): la etiqueta se busca SOLO entre las claves
// PROPIAS. «Constructor» o «__proto__» escritos en la hoja no deben caer en el
// prototipo del objeto (Codex v5 #5: `origen` acababa siendo una función, JSON la
// omitía al serializar y la fila cambiaba de categoría entre el INSERT directo —que
// tomaba el DEFAULT— y la puerta —que recibía NULL—).

export function etiquetaPropia(
  catalogo: Record<string, string>,
  clave: string,
): string | undefined {
  return Object.hasOwn(catalogo, clave) ? catalogo[clave] : undefined;
}
