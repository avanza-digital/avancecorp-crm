// Reglas de documento de identidad (DNI / CE / Pasaporte) — ESPEJO FIEL de
// public_html/js/admin/documento-core.js (la fuente canónica del portal).
//
// Las mismas reglas viven, espejadas a propósito, en:
//   - public_html/js/admin/documento-core.js                → portal (original)
//   - _supabase_functions/functions/_shared/documento.ts    → frontera (edges)
//   - CHECK de dominio en public.perfiles.tipo_documento    → BD
//   - AQUÍ (CRM). El candado anti-drift es src/lib/documento.test.ts, que
//     afirma las regex VERBATIM (y contra el archivo del portal si está junto).
// Si cambias una regla, cambia TODAS las copias.
//
// Las claves ('DNI'|'CE'|'PASAPORTE') son EXACTAMENTE los literales que acepta
// el CHECK de BD y la edge crear-cliente. Agregar un tipo = una entrada aquí +
// sus espejos + ampliar el CHECK.
//
// NOTA: `clasificarBackfill` del original NO se porta — era exclusiva de la
// migración 20260714000001 del portal y el CRM jamás clasifica datos históricos.

export interface ReglaDocumento {
  etiqueta: string
  regex: RegExp
  inputmode: 'numeric' | 'text'
  placeholder: string
  mayusculas: boolean
  regla: string
  error: string
}

// OJO: sin `maxlength` por tipo A PROPÓSITO (hallazgo del portal 2026-07-14):
// un tope de 8 en modo DNI TRUNCA EN SILENCIO un CE de 9–12 pegado sin cambiar
// el selector, y el resultado truncado VALIDA como DNI (documento corrupto).
// El input usa un tope único de 12 y el largo exacto lo atrapa la validación.
export const TIPOS_DOCUMENTO = Object.freeze({
  DNI: Object.freeze<ReglaDocumento>({
    etiqueta: 'DNI',
    regex: /^\d{8}$/,
    inputmode: 'numeric',
    placeholder: '45781234',
    mayusculas: false,
    regla: '8 dígitos exactos.',
    error: 'El DNI debe tener exactamente 8 dígitos.',
  }),
  CE: Object.freeze<ReglaDocumento>({
    etiqueta: 'Carné de Extranjería',
    regex: /^\d{9,12}$/,
    inputmode: 'numeric',
    placeholder: '001234567',
    mayusculas: false,
    regla: 'Entre 9 y 12 dígitos.',
    error: 'El Carné de Extranjería debe tener entre 9 y 12 dígitos.',
  }),
  PASAPORTE: Object.freeze<ReglaDocumento>({
    etiqueta: 'Pasaporte',
    regex: /^[A-Z0-9]{6,12}$/,
    inputmode: 'text',
    placeholder: 'AB123456',
    mayusculas: true,
    regla: 'Entre 6 y 12 letras y/o números.',
    error: 'El Pasaporte debe tener entre 6 y 12 caracteres (solo letras y números).',
  }),
})

export type TipoDocumento = keyof typeof TIPOS_DOCUMENTO

/** Catálogo runtime para poblar selects POR CÓDIGO (nunca <option> a mano). */
export const TIPOS_DOCUMENTO_K = Object.keys(TIPOS_DOCUMENTO) as TipoDocumento[]

// Documento "genérico" 8–12 dígitos: regla HISTÓRICA del sistema; hoy solo
// aplica al documento del BENEFICIARIO bancario (otra persona, sin tipo propio
// todavía). NO usarla para el documento del titular: el titular valida por tipo.
export const RE_DOC_GENERICO = /^[0-9]{8,12}$/

// Callers viejos (o datos sin la columna de tipo) no mandan tipo: el default
// histórico del sistema es DNI. También absorbe basura ('dni', ' ce ').
export function normalizarTipoDocumento(tipo: unknown): TipoDocumento {
  const t = String(tipo ?? '').trim().toUpperCase()
  return t in TIPOS_DOCUMENTO ? (t as TipoDocumento) : 'DNI'
}

// ¿El texto es un tipo reconocido? Para entradas LIBRES: un tipo PRESENTE pero
// desconocido debe dar error explícito, nunca caer en silencio a DNI (hallazgo
// del portal 2026-07-14: "CARNÉ DE EXTRANJERÍA" — la etiqueta misma del select —
// se clasificaba como DNI sin avisar).
export function esTipoDocumento(tipo: unknown): tipo is TipoDocumento {
  return String(tipo ?? '').trim().toUpperCase() in TIPOS_DOCUMENTO
}

// Valor canónico del documento: sin espacios y, para tipos alfanuméricos
// (pasaporte), en MAYÚSCULA — así validación, persistencia y clave temporal
// trabajan siempre sobre el mismo string. Para DNI/CE el uppercase es no-op.
export function normalizarDocumento(tipo: unknown, valor: unknown): string {
  const v = String(valor ?? '').trim()
  return TIPOS_DOCUMENTO[normalizarTipoDocumento(tipo)].mayusculas ? v.toUpperCase() : v
}

export type ResultadoDocumento =
  | { ok: true; valor: string }
  | { ok: false; valor: string; error: string }

// Valida un documento según su tipo. Devuelve siempre el valor ya normalizado:
// { ok:true, valor } o { ok:false, valor, error } con mensaje listo para mostrar.
export function validarDocumento(tipo: unknown, valor: unknown): ResultadoDocumento {
  const t = normalizarTipoDocumento(tipo)
  const regla = TIPOS_DOCUMENTO[t]
  const v = normalizarDocumento(t, valor)
  if (!regla.regex.test(v)) return { ok: false, valor: v, error: regla.error }
  return { ok: true, valor: v }
}

// Clave temporal del primer ingreso = el documento, garantizando el mínimo de 8
// caracteres que exige Supabase Auth. Regla ÚNICA por longitud (sin ramas por
// tipo): un DNI corto por cero perdido en Excel ('1234567') y un pasaporte corto
// ('AB1234') se completan igual, con ceros a la IZQUIERDA → '01234567' / '00AB1234'.
export function claveTemporalDesdeDocumento(documento: unknown): string {
  const doc = String(documento ?? '').trim()
  return doc.length >= 8 ? doc : doc.padStart(8, '0')
}
