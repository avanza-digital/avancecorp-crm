export type AutorizacionContactoHoja =
  | { ok: true; registrarConsentimiento: boolean }
  | { ok: false; error: string };

/**
 * La respuesta de la hoja es informativa para el registro de consentimiento.
 * Por decisión operativa, nunca activa `no_contactar`: todo lead importado debe
 * quedar visible y repartible. El bloqueo "No Insista", si se usa, se gestiona
 * exclusivamente dentro del CRM y no se hereda desde esta integración.
 */
export function interpretarAutorizacionContacto(
  valor: string | undefined,
): AutorizacionContactoHoja {
  const normalizado = (valor ?? "").trim().toUpperCase();

  if (normalizado === "") {
    return { ok: true, registrarConsentimiento: false };
  }
  if (
    normalizado === "SI" || normalizado === "SÍ" || normalizado === "S"
  ) {
    return { ok: true, registrarConsentimiento: true };
  }
  if (normalizado === "NO" || normalizado === "N") {
    return { ok: true, registrarConsentimiento: false };
  }

  return {
    ok: false,
    error:
      "¿Autorizó contacto? debe ser SI o NO (vacío = sin registrar consentimiento)",
  };
}
