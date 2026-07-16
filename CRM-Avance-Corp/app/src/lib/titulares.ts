// Núcleo puro de los CO-TITULARES de un contrato (cuentas mancomunadas) —
// ESPEJO FIEL de public_html/js/admin/titulares-core.js (la fuente canónica del
// portal). Patrón documento-core ↔ documento.ts: cero DOM/Supabase → testeable.
// Reusa las reglas de documento de lib/documento (única fuente en el CRM), NO
// reimplementa regex. Si cambia una regla en el portal, cambiar AMBAS copias.
//
// El titular PRINCIPAL del contrato NO vive aquí: es contratos.cliente_id.
// Estos son los co-titulares ADICIONALES (dato informativo del contrato) que
// viajan DENTRO de p_contrato como 'titulares' (la RPC crear_contrato /
// actualizar_contrato ya los procesa vía _sync_contrato_titulares).
import { normalizarTipoDocumento, validarDocumento, type TipoDocumento } from './documento'
import { MAX_TITULARES, type TitularInput } from './clientes-tipos'

// Re-export para que editor/pantalla hablen con un solo módulo de titulares.
export { MAX_TITULARES }

/** Fila CRUDA del editor (sin validar): la validación vive en normalizarTitulares. */
export interface TitularBorrador {
  tipo_documento: TipoDocumento
  documento: string
  nombre_completo: string
}

/** Fila nueva del editor (el default DNI es el histórico del sistema). */
export function titularVacio(): TitularBorrador {
  return { tipo_documento: 'DNI', documento: '', nombre_completo: '' }
}

/**
 * Etiqueta corta del documento para SOLO LECTURA (espejo del portal):
 *   DNI → '12345678' · CE → 'CE 001234567' · PASAPORTE → 'PASAPORTE AB123456'
 */
export function etiquetaDocumento(tipo: unknown, documento: unknown): string {
  const t = normalizarTipoDocumento(tipo)
  const doc = String(documento ?? '')
  return t === 'DNI' ? doc : `${t} ${doc}`
}

export type ResultadoTitular =
  | { ok: true; valor: TitularInput }
  | { ok: false; error: string }

/**
 * Valida y NORMALIZA un co-titular crudo del formulario: nombre en MAYÚSCULA
 * con espacios colapsados (misma norma que perfiles) y documento por su tipo.
 */
export function normalizarTitular(raw: Partial<TitularBorrador> | null | undefined): ResultadoTitular {
  const nombre = String(raw?.nombre_completo ?? '').trim().replace(/\s+/g, ' ').toUpperCase()
  if (!nombre) return { ok: false, error: 'Escribe el nombre completo del co-titular.' }
  const tipo = normalizarTipoDocumento(raw?.tipo_documento)
  const v = validarDocumento(tipo, raw?.documento)
  if (!v.ok) return { ok: false, error: v.error }
  return { ok: true, valor: { nombre_completo: nombre, tipo_documento: tipo, documento: v.valor } }
}

export type ResultadoTitulares =
  | { ok: true; titulares: TitularInput[] }
  | { ok: false; error: string; index?: number }

/**
 * Valida una LISTA de co-titulares crudos. Las filas COMPLETAMENTE vacías (el
 * usuario agregó una fila y no la llenó) se ignoran en silencio; una a medio
 * llenar da error explícito con su posición (base 1, como el portal).
 *
 * Regla EXTRA del CRM (no está en titulares-core.js): documentos DUPLICADOS
 * entre filas se rechazan — la misma persona dos veces es siempre un error de
 * tipeo y el servidor lo aceptaría sin chistar.
 */
export function normalizarTitulares(
  rawArr: ReadonlyArray<Partial<TitularBorrador> | null | undefined>,
): ResultadoTitulares {
  const arr = Array.isArray(rawArr) ? rawArr : []
  const out: TitularInput[] = []
  const vistos = new Set<string>()
  for (let i = 0; i < arr.length; i++) {
    const r = arr[i] ?? {}
    const vacia = !String(r.nombre_completo ?? '').trim() && !String(r.documento ?? '').trim()
    if (vacia) continue
    const n = normalizarTitular(r)
    if (!n.ok) return { ok: false, error: `Co-titular ${i + 1}: ${n.error}`, index: i }
    // La clave incluye el tipo: un DNI '87654321' y un pasaporte '87654321'
    // son documentos distintos (personas distintas), no un duplicado.
    const clave = `${n.valor.tipo_documento}:${n.valor.documento}`
    if (vistos.has(clave)) {
      return { ok: false, error: `Co-titular ${i + 1}: el documento ${n.valor.documento} está repetido.`, index: i }
    }
    vistos.add(clave)
    out.push(n.valor)
  }
  if (out.length > MAX_TITULARES) {
    return { ok: false, error: `Máximo ${MAX_TITULARES} co-titulares por contrato.` }
  }
  return { ok: true, titulares: out }
}
