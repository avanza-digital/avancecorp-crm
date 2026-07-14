// ============================================================================
// Reglas de documento de identidad (DNI / CE / Pasaporte) — FRONTERA (edges).
//
// ÚNICA fuente de verdad para las edge functions `crear-cliente` e
// `importar-clientes` (ambas la importan con ../_shared/documento.ts y la
// incluyen en su deploy). ESPEJO deliberado del núcleo del frontend:
//   public_html/js/admin/documento-core.js
// El test public_html/tests/documento-core.test.mjs afirma que las regex de los
// dos archivos son idénticas VERBATIM: si cambias una regla aquí, cambia también
// el core del frontend (y viceversa) o el test falla.
//
// Las claves ('DNI'|'CE'|'PASAPORTE') son EXACTAMENTE los literales del CHECK
// perfiles_tipo_documento_check en BD.
// ============================================================================

export type TipoDocumento = "DNI" | "CE" | "PASAPORTE";

interface ReglaDocumento {
  etiqueta: string;
  regex: RegExp;
  mayusculas: boolean;
  error: string;
}

export const TIPOS_DOCUMENTO: Record<TipoDocumento, ReglaDocumento> = {
  DNI: {
    etiqueta: "DNI",
    regex: /^\d{8}$/,
    mayusculas: false,
    error: "El DNI debe tener exactamente 8 dígitos.",
  },
  CE: {
    etiqueta: "Carné de Extranjería",
    regex: /^\d{9,12}$/,
    mayusculas: false,
    error: "El Carné de Extranjería debe tener entre 9 y 12 dígitos.",
  },
  PASAPORTE: {
    etiqueta: "Pasaporte",
    regex: /^[A-Z0-9]{6,12}$/,
    mayusculas: true,
    error: "El Pasaporte debe tener entre 6 y 12 caracteres (solo letras y números).",
  },
};

// Documento "genérico" 8–12 dígitos: regla HISTÓRICA que hoy solo aplica al
// documento del BENEFICIARIO bancario (otra persona, aún sin tipo propio).
// NO usarla para el titular: el titular valida por tipo.
export const RE_DOC_GENERICO = /^[0-9]{8,12}$/;

// Callers viejos (frontend en producción, Excel sin columna de tipo) no mandan
// tipo: el default histórico del sistema es DNI. Absorbe basura ('dni', ' ce ').
export function normalizarTipoDocumento(tipo: unknown): TipoDocumento {
  const t = String(tipo ?? "").trim().toUpperCase();
  return t in TIPOS_DOCUMENTO ? (t as TipoDocumento) : "DNI";
}

// ¿El texto es un tipo reconocido? Para entradas LIBRES (columna del Excel,
// body de la API): un tipo PRESENTE pero desconocido debe dar error explícito,
// nunca caer en silencio a DNI (hallazgo de revisión 2026-07-14).
export function esTipoDocumento(tipo: unknown): boolean {
  return String(tipo ?? "").trim().toUpperCase() in TIPOS_DOCUMENTO;
}

// Valor canónico: sin espacios y en MAYÚSCULA para tipos alfanuméricos
// (pasaporte), para que validación, persistencia y clave temporal usen siempre
// el mismo string. Para DNI/CE el uppercase es no-op.
export function normalizarDocumento(tipo: TipoDocumento, valor: unknown): string {
  const v = String(valor ?? "").trim();
  return TIPOS_DOCUMENTO[tipo].mayusculas ? v.toUpperCase() : v;
}

// Valida por tipo. Devuelve null si es válido, o el mensaje de error listo para
// responder 400 (el valor debe venir ya normalizado con normalizarDocumento).
export function validarDocumento(tipo: TipoDocumento, valor: string): string | null {
  return TIPOS_DOCUMENTO[tipo].regex.test(valor) ? null : TIPOS_DOCUMENTO[tipo].error;
}

// Clave temporal del primer ingreso = el documento, garantizando el mínimo de 8
// caracteres que exige Supabase Auth. Regla ÚNICA por longitud (sin ramas por
// tipo): '1234567' → '01234567', 'AB1234' → '00AB1234'.
export function claveTemporalDesdeDocumento(documento: string): string {
  const doc = String(documento ?? "").trim();
  return doc.length >= 8 ? doc : doc.padStart(8, "0");
}
