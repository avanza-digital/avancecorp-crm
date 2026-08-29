// lib/validacion.ts — Validación compartida de campos de lead (fuente única).
// La usan crearLead y editarLead del store (antes: dos copias divergentes) y
// los formularios; cuando lleguen las mutaciones reales de Supabase, será la
// TERCERA consumidora del mismo contrato — sin strings que sincronizar a mano.
import { esMoneda, type Moneda } from './format'
import { esGenero, esOrigen, type Genero, type Origen } from './tipos'

/**
 * LA REGLA DEL TELÉFONO en el front. Gemela EXACTA de `telefonos.ts` del
 * conector (supabase/functions/crm-importar-leads) y del CHECK
 * `leads_telefono_alternativo_formato`. Si una de las tres se mueve sin las
 * otras, un número entra por un lado y se pierde por el otro sin que nadie lo
 * vea — que es exactamente cómo se perdían los segundos números.
 *
 * Decisiones de Miguel (2026-08-26): el CRM reconoce fijos peruanos y números
 * de cualquier país, y basta UN número bueno para que el lead exista.
 *
 * Sin libphonenumber a propósito: la misma regla tiene que caber en un CHECK de
 * Postgres y en el Apps Script del puente. Se usa E.164, que es el estándar que
 * define qué es un número de teléfono en el planeta.
 */
export type ClaseTelefono = 'celular_pe' | 'fijo_pe' | 'internacional'

export interface TelefonoReconocido {
  /** Canónico E.164: `+` y solo dígitos. Es lo que se guarda. */
  e164: string
  clase: ClaseTelefono
  /** Sirve para WhatsApp. Un fijo, no. */
  movil: boolean
}

const E164_MIN = 8
const E164_MAX = 15

export function reconocerTelefono(valor: string | null | undefined): TelefonoReconocido | null {
  const bruto = (valor ?? '').trim()
  if (!bruto) return null
  // Un correo en la casilla del teléfono es otro dato en el sitio equivocado,
  // no un número roto.
  if (bruto.includes('@')) return null

  const digitos = bruto.replace(/\D/g, '')
  if (!digitos) return null

  const marcadoInternacional = bruto.startsWith('+') || digitos.startsWith('00')
  const sinSalida = digitos.replace(/^00/, '')

  // Todo lo que dice ser peruano se juzga con la vara peruana: si no tiene la
  // forma exacta NO se cuela por la puerta internacional. Sin esto,
  // `+51123456789` entraría como «internacional válido» y nadie podría llamarlo.
  const nacional = sinSalida.startsWith('51') ? sinSalida.slice(2) : sinSalida
  const declaraPeru = sinSalida.startsWith('51') && nacional.length >= 8

  if (declaraPeru || !marcadoInternacional) {
    const n = declaraPeru ? nacional : sinSalida
    if (/^9\d{8}$/.test(n)) return { e164: `+51${n}`, clase: 'celular_pe', movil: true }
    // ⚠️ UN FIJO EXIGE MARCA. El nacional de un fijo peruano tiene ocho dígitos
    // (Lima 1 + siete, provincias 84 + seis)… y el DNI peruano TAMBIÉN tiene
    // ocho. Aceptar ocho dígitos pelados convertía todo DNI en un teléfono: el
    // buscador ofrecía «verificar disponibilidad» sobre un documento. Un fijo
    // solo se reconoce MARCADO: con `+51`/`0051`, o con el 0 de larga distancia
    // con el que la gente escribe su fijo de verdad (014457890).
    const marcaDeFijo = declaraPeru || n.startsWith('0')
    const sinCero = n.startsWith('0') ? n.slice(1) : n
    if (marcaDeFijo && /^[1-8]\d{7}$/.test(sinCero)) {
      return { e164: `+51${sinCero}`, clase: 'fijo_pe', movil: false }
    }
    if (declaraPeru) return null
    if (!marcadoInternacional) return null // sin `+` no hay país que suponer
  }

  if (sinSalida.length >= E164_MIN && sinSalida.length <= E164_MAX && /^[1-9]\d*$/.test(sinSalida)) {
    // Móvil o fijo es indecidible fuera de Perú sin libphonenumber. Se asume
    // móvil: equivocarse hacia «se puede escribir por WhatsApp» ofrece un botón
    // que quizá no responda; al revés escondería el único canal que hay.
    return { e164: `+${sinSalida}`, clase: 'internacional', movil: true }
  }
  return null
}

/**
 * El teléfono del lead, canónico, o `null`.
 *
 * Acepta también fijos: un lead al que solo se puede llamar sigue siendo un
 * lead, y hasta hoy el CRM lo rechazaba. Quien necesite saber si el número
 * responde WhatsApp tiene `reconocerTelefono(...).movil`.
 */
export function normalizarTelefono(valor: string): string | null {
  return reconocerTelefono(valor)?.e164 ?? null
}

/** Correo razonable (no RFC completo — espejo del CHECK laxo del esquema). */
export const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/
export const MONTO_ESTIMADO_MAX = 9_999_999_999.99

/**
 * Edad mínima para ser lead: se invierte capital, no hay producto para menores.
 * Vive AQUÍ y no en un CHECK porque la base tendría que comparar contra la
 * fecha de hoy y PostgreSQL solo admite expresiones IMMUTABLE en un CHECK. La
 * base guarda el rango de cordura (1900 ≤ fecha < 2100); el resto es esta capa.
 */
export const EDAD_MINIMA = 18
const FECHA_NACIMIENTO_MIN = '1900-01-01'
const ISO_FECHA_RE = /^\d{4}-\d{2}-\d{2}$/

// ── Errores estructurados ─────────────────────────────────────────────────────
// La UI ancla el error a su campo por `campo` (nunca adivinando por regex
// sobre el texto del mensaje) y decide el wording final con `error`.

export type CampoLead =
  | 'nombre_completo'
  | 'telefono'
  | 'telefono_alternativo'
  | 'dni'
  | 'correo'
  | 'origen'
  | 'monto_estimado'
  | 'moneda'
  | 'genero'
  | 'fecha_nacimiento'

export type CodigoValidacion =
  | 'nombre_obligatorio'
  | 'telefono_invalido'
  | 'telefono_alternativo_invalido'
  | 'dni_invalido'
  | 'correo_invalido'
  | 'origen_invalido'
  | 'monto_invalido'
  | 'moneda_invalida'
  | 'genero_invalido'
  | 'fecha_nacimiento_invalida'
  | 'menor_de_edad'

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
  telefono_alternativo?: string | null
  dni?: string | null
  correo?: string | null
  origen?: string
  monto_estimado?: number | null
  moneda?: string
  genero?: string | null
  fecha_nacimiento?: string | null
}

/** Valores ya normalizados (teléfono +51…, strings vacíos → null). */
export interface ValoresLead {
  nombre_completo?: string
  telefono?: string
  telefono_alternativo?: string | null
  dni?: string | null
  correo?: string | null
  origen?: Origen
  monto_estimado?: number
  moneda?: Moneda
  genero?: Genero | null
  fecha_nacimiento?: string | null
}

/**
 * Valida y normaliza los campos PRESENTES de un lead. Espejo de los CHECK de
 * crm.leads (teléfono, DNI, origen, monto, género) MÁS la regla de edad mínima,
 * que la base no puede expresar. Primer error gana (misma UX que los
 * formularios: un error por vez, anclado a su campo).
 *
 * `hoy` es inyectable solo para que los tests de edad no dependan del reloj.
 */
export function validarCamposLead(
  campos: CamposLead,
  hoy: Date = new Date(),
): { ok: true; valores: ValoresLead } | ErrorValidacion {
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
        error: 'Teléfono inválido — celular peruano 9########, fijo peruano, o internacional con +código de país',
      }
    }
    valores.telefono = telefono
  }

  if (campos.telefono_alternativo !== undefined) {
    const bruto = (campos.telefono_alternativo ?? '').trim()
    if (!bruto) {
      // Vaciarlo es una acción legítima: el analista descubre que el segundo
      // número era del vecino y lo borra. NULL, nunca '' — «no hay dato» se
      // escribe de UNA sola forma o la ficha acaba comprobando las dos.
      valores.telefono_alternativo = null
    } else {
      const alternativo = normalizarTelefono(bruto)
      if (!alternativo) {
        return {
          ok: false,
          codigo: 'telefono_alternativo_invalido',
          campo: 'telefono_alternativo',
          error: 'Segundo teléfono inválido — celular peruano 9########, fijo peruano (014457890), o internacional con +código de país',
        }
      }
      // A diferencia de lo que llega del origen, aquí NO hay columna cruda: lo
      // que teclea una persona se corrige en el momento, no se guarda a medias.
      // El texto sin validar existe para el dato que ya venía escrito así.
      valores.telefono_alternativo = alternativo
    }
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
    if (campos.monto_estimado == null || !Number.isFinite(campos.monto_estimado) || campos.monto_estimado <= 0) {
      return {
        ok: false,
        codigo: 'monto_invalido',
        campo: 'monto_estimado',
        error: 'El capital estimado es obligatorio y debe ser mayor que 0',
      }
    }
    if (campos.monto_estimado > MONTO_ESTIMADO_MAX) {
      return {
        ok: false,
        codigo: 'monto_invalido',
        campo: 'monto_estimado',
        error: 'El capital estimado excede el máximo permitido',
      }
    }
    // crm.leads conserva el rango de numeric(12,2) mediante CHECK explícito.
    // Rechazar, no redondear: cambiar 5000.999 a 5001.00 en el servidor puede
    // mover silenciosamente el lead de rango.
    if (Math.round(campos.monto_estimado * 100) / 100 !== campos.monto_estimado) {
      return {
        ok: false,
        codigo: 'monto_invalido',
        campo: 'monto_estimado',
        error: 'El capital estimado admite como máximo 2 decimales',
      }
    }
    valores.monto_estimado = campos.monto_estimado
  }

  if (campos.moneda !== undefined) {
    if (!esMoneda(campos.moneda)) {
      return {
        ok: false,
        codigo: 'moneda_invalida',
        campo: 'moneda',
        error: 'Selecciona una moneda válida (PEN o USD)',
      }
    }
    valores.moneda = campos.moneda
  }

  if (campos.genero !== undefined) {
    const genero = (campos.genero ?? '').trim()
    if (!genero) {
      valores.genero = null // vacío = "sin dato", opción legítima (avatar → iniciales)
    } else if (!esGenero(genero)) {
      return { ok: false, codigo: 'genero_invalido', campo: 'genero', error: 'Género inválido' }
    } else {
      valores.genero = genero
    }
  }

  if (campos.fecha_nacimiento !== undefined) {
    const fecha = (campos.fecha_nacimiento ?? '').trim()
    if (fecha) {
      // El <input type="date"> ya entrega ISO, pero por aquí también pasan
      // datos de importación y del store: se valida la forma Y el calendario
      // (2026-02-30 pasa la regex y no existe).
      if (!ISO_FECHA_RE.test(fecha) || !esFechaReal(fecha) || fecha < FECHA_NACIMIENTO_MIN) {
        return {
          ok: false,
          codigo: 'fecha_nacimiento_invalida',
          campo: 'fecha_nacimiento',
          error: 'Fecha de nacimiento inválida',
        }
      }
      if (edadCumplida(fecha, hoy) < EDAD_MINIMA) {
        return {
          ok: false,
          codigo: 'menor_de_edad',
          campo: 'fecha_nacimiento',
          error: `El lead debe tener al menos ${EDAD_MINIMA} años`,
        }
      }
    }
    valores.fecha_nacimiento = fecha || null
  }

  return { ok: true, valores }
}

/**
 * Partes de una fecha ISO 'YYYY-MM-DD'. Una sola lectura con captura explícita:
 * `split('-').map(Number)` desestructurado daría `number | undefined` bajo
 * noUncheckedIndexedAccess.
 */
function partesFecha(iso: string): { anio: number; mes: number; dia: number } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  if (!m) return null
  return { anio: Number(m[1]), mes: Number(m[2]), dia: Number(m[3]) }
}

/** 'YYYY-MM-DD' que además EXISTE en el calendario (descarta 2026-02-30). */
function esFechaReal(iso: string): boolean {
  const p = partesFecha(iso)
  if (!p) return false
  const d = new Date(Date.UTC(p.anio, p.mes - 1, p.dia))
  return d.getUTCFullYear() === p.anio && d.getUTCMonth() === p.mes - 1 && d.getUTCDate() === p.dia
}

/**
 * Años cumplidos a la fecha `hoy`. Se compara sobre las PARTES de la fecha (no
 * sobre milisegundos) para que el resultado no dependa de la zona horaria ni de
 * los años bisiestos. Exportada para que el formulario muestre el error ANTES
 * de llamar al store, sin una segunda copia de la aritmética. Con una fecha que
 * no tiene forma ISO devuelve -1 (nunca alcanza la edad mínima): quien llama ya
 * rechazó la forma antes, y así este helper no puede colar un mayor de edad.
 */
export function edadCumplida(iso: string, hoy: Date = new Date()): number {
  const p = partesFecha(iso)
  if (!p) return -1
  let edad = hoy.getFullYear() - p.anio
  const mesHoy = hoy.getMonth() + 1
  const cumplioEsteAnio = mesHoy > p.mes || (mesHoy === p.mes && hoy.getDate() >= p.dia)
  if (!cumplioEsteAnio) edad -= 1
  return edad
}
