/** Campaña opcional: el canal sigue gobernando reparto y conversión. */
export function interpretarCampania(
  valor: unknown,
  canal: string,
): { ok: true; valor: string | null } | { ok: false; error: string } {
  if (valor === undefined || valor === null) return { ok: true, valor: null };
  if (typeof valor !== "string") {
    return { ok: false, error: "campaña debe ser texto" };
  }
  // Recorte de espacios exteriores; los controles se rechazan, no se ocultan.
  const campania = valor.replace(/^ +| +$/g, "");
  if (
    [...campania].length < 1 || [...campania].length > 80 ||
    /[\u0000-\u001f\u007f-\u009f]/.test(campania)
  ) {
    return {
      ok: false,
      error: "campaña debe tener de 1 a 80 caracteres sin controles",
    };
  }
  if (campania.toLowerCase() === "formulario 3") {
    if (canal !== "formulario") {
      return { ok: false, error: "Formulario 3 requiere el canal FORMULARIO" };
    }
    return { ok: true, valor: "Formulario 3" };
  }
  return { ok: true, valor: campania };
}
