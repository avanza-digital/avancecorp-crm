// 15, no 5. Decidido con los 19 domicilios reales de producción (2026-08-19):
// el más corto tiene 28 caracteres y el 100 % lleva número. Con 5 pasaban
// «LIMA.», «no tiene» y «PENDIENTE», que se imprimen tal cual en el contrato.
export const DOMICILIO_LEGAL_MIN = 15;
export const DOMICILIO_LEGAL_MAX = 240;

/**
 * Valida la dirección que se copiará literalmente al contrato.
 *
 * `requerido:false` existe únicamente para callers legacy del portal que aún
 * no capturan domicilio. Los flujos modernos del CRM siempre usan true y la
 * fotografía contractual vuelve a fallar cerrado si un perfil legacy sigue
 * sin el dato.
 */
export function validarDomicilioLegal(valor, { requerido = true } = {}) {
  if (valor !== null && valor !== undefined && typeof valor !== "string") {
    return {
      ok: false,
      error: "El domicilio legal debe ser texto.",
    };
  }

  // Espacios Unicode que ocupan sitio → espacio normal, y se colapsa. Sin esto
  // el servidor (btrim, solo U+0020) y este validador medían cosas distintas.
  const domicilio = (valor ?? "")
    .replace(/[\u0085\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!domicilio) {
    return requerido
      ? { ok: false, error: "Completa el domicilio legal del cliente." }
      : { ok: true, valor: null };
  }
  if (
    [...domicilio].length < DOMICILIO_LEGAL_MIN ||
    [...domicilio].length > DOMICILIO_LEGAL_MAX
  ) {
    return {
      ok: false,
      error:
        `El domicilio legal debe tener entre ${DOMICILIO_LEGAL_MIN} y ${DOMICILIO_LEGAL_MAX} caracteres.`,
    };
  }
  if (/[\u0000-\u001f\u007f-\u009f]/u.test(domicilio)) {
    return {
      ok: false,
      error: "El domicilio legal contiene caracteres no permitidos.",
    };
  }
  // Invisibles de ancho CERO: pasaban TODOS los controles, se imprimen en el
  // contrato como NADA («con domicilio en , a quien…») y cierran el hueco para
  // siempre, porque el domicilio no se puede volver a vaciar.
  if (/[\u00AD\u180E\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2064\uFEFF]/u.test(domicilio)) {
    return {
      ok: false,
      error:
        "El domicilio legal contiene caracteres invisibles que no se imprimirían en el contrato.",
    };
  }
  // Al menos un dígito: separa una dirección de un relleno, y lo cumplen los 19
  // domicilios reales de producción sin una sola excepción.
  if (!/[0-9]/.test(domicilio)) {
    return {
      ok: false,
      error:
        "El domicilio legal necesita el número de la calle, el lote o la manzana.",
    };
  }
  const soloAlfanum = domicilio
    .replace(/[^0-9a-zA-ZÁÉÍÓÚÜÑáéíóúüñ]/g, "")
    .toLowerCase();
  if (soloAlfanum.length > 0 && new Set(soloAlfanum).size === 1) {
    return {
      ok: false,
      error: "El domicilio legal no puede ser un solo carácter repetido.",
    };
  }
  // La dirección de la PROPIA Avance Corp: el contrato dejaría a las dos partes
  // domiciliadas en el mismo sitio, y la cláusula 14.ª manda ahí todas las
  // notificaciones.
  const plano = domicilio
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase().replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ");
  if (plano.includes("republica de panama") && plano.includes("3635")) {
    return {
      ok: false,
      error:
        "Esa es la dirección de Avance Corp, no la del cliente: el contrato dejaría a las dos partes domiciliadas en el mismo sitio.",
    };
  }
  return { ok: true, valor: domicilio };
}
