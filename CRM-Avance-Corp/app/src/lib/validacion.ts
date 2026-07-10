// lib/validacion.ts — Validación compartida de campos de lead (fuente única).
// La usan crearLead y editarLead del store (antes: dos copias divergentes) y
// los formularios; cuando lleguen las mutaciones reales de Supabase, será la
// TERCERA consumidora del mismo contrato — sin strings que sincronizar a mano.
import { esOrigen, type Origen } from './tipos'

/** Normaliza un celular peruano a +519######## (o null si no es válido). */
export function normalizarTelefono(valor: string): string | null {
  const limpio = valor.replace(/[\s().-]/g, '')
  const sinMas = limpio.startsWith('+') ? limpio.slice(1) : limpio
  if (/^9\d{8}$/.test(sinMas)) return `+51${sinMas}`
  if (/^519\d{8}$/.test(sinMas)) return `+${sinMas}`
  return null
}

/** Correo razonable (no RFC completo — espejo del CHECK laxo del esquema). */
export const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/

// ── Errores estructurados ─────────────────────────────────────────────────────
// La UI ancla el error a su campo por `campo` (nunca adivinando por regex
// sobre el texto del mensaje) y decide el wording final con `error`.

export type CampoLead = 'nombre_completo' | 'telefono' | 'dni' | 'correo' | 'origen' | 'monto_estimado'

export type CodigoValidacion =
  | 'nombre_obligatorio'
  | 'telefono_invalido'
  | 'dni_invalido'
  | 'correo_invalido'
  | 'origen_invalido'
  | 'monto_invalido'

export interface ErrorValidacion {
  ok: false
  codigo: CodigoValidacion
  campo: CampoLead
  error: string // mensaje es-PE listo para mostrar
}

/** Campos aceptados: solo se validan/normalizan los presentes (!== undefined). */
export interface CamposLead {
  nombre_completo?: string
  telefono?: string
  dni?: string | null
  correo?: string | null
  origen?: string
  monto_estimado?: number | null
}

/** Valores ya normalizados (teléfono +51…, strings vacíos → null). */
export interface ValoresLead {
  nombre_completo?: string
  telefono?: string
  dni?: string | null
  correo?: string | null
  origen?: Origen
  monto_estimado?: number | null
}

/**
 * Valida y normaliza los campos PRESENTES de un lead. Espejo de los CHECK de
 * crm.leads (teléfono, DNI, origen, monto). Primer error gana (misma UX que
 * los formularios: un error por vez, anclado a su campo).
 */
export function validarCamposLead(campos: CamposLead): { ok: true; valores: ValoresLead } | ErrorValidacion {
  const valores: ValoresLead = {}

  if (campos.nombre_completo !== undefined) {
    const nombre = campos.nombre_completo.trim()
    if (!nombre) {
      return { ok: false, codigo: 'nombre_obligatorio', campo: 'nombre_completo', error: 'El nombre es obligatorio' }
    }
    valores.nombre_completo = nombre
  }

  if (campos.telefono !== undefined) {
    const telefono = normalizarTelefono(campos.telefono)
    if (!telefono) {
      return {
        ok: false,
        codigo: 'telefono_invalido',
        campo: 'telefono',
        error: 'Teléfono inválido — usa un celular peruano 9######## (se guarda como +51…)',
      }
    }
    valores.telefono = telefono
  }

  if (campos.dni !== undefined) {
    const dni = (campos.dni ?? '').trim()
    if (dni && !/^\d{8}$/.test(dni)) {
      return { ok: false, codigo: 'dni_invalido', campo: 'dni', error: 'El DNI debe tener exactamente 8 dígitos' }
    }
    valores.dni = dni || null
  }

  if (campos.correo !== undefined) {
    const correo = (campos.correo ?? '').trim()
    if (correo && !CORREO_RE.test(correo)) {
      return { ok: false, codigo: 'correo_invalido', campo: 'correo', error: 'Correo electrónico inválido' }
    }
    valores.correo = correo || null
  }

  if (campos.origen !== undefined) {
    if (!esOrigen(campos.origen)) {
      return { ok: false, codigo: 'origen_invalido', campo: 'origen', error: 'Origen inválido' }
    }
    valores.origen = campos.origen
  }

  if (campos.monto_estimado !== undefined) {
    if (campos.monto_estimado != null && (!Number.isFinite(campos.monto_estimado) || campos.monto_estimado < 0)) {
      return {
        ok: false,
        codigo: 'monto_invalido',
        campo: 'monto_estimado',
        error: 'El monto estimado debe ser un número mayor o igual a 0',
      }
    }
    valores.monto_estimado = campos.monto_estimado ?? null
  }

  return { ok: true, valores }
}
