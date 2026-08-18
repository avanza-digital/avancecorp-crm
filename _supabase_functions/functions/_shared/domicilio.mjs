export const DOMICILIO_LEGAL_MIN = 5;
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

  const domicilio = (valor ?? "").trim();
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
  return { ok: true, valor: domicilio };
}
