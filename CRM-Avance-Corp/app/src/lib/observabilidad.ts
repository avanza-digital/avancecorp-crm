// Observabilidad local y segura del CRM.
// No envía datos a terceros: deja eventos estructurados en la consola para
// diagnóstico, siempre después de retirar credenciales y PII conocida.

type Nivel = 'info' | 'warn' | 'error'

const CLAVES_SENSIBLES = /(?:authorization|cookie|token|secret|password|clave|credencial|correo|email|telefono|phone|dni|documento|nombre|apellido|direccion|cuenta|cci|beneficiario|session|user_?id|perfil_?id)/i
const CORREO = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi
const JWT = /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]*)?/g
const BEARER = /Bearer\s+[A-Za-z0-9._~+/-]+=*/gi
const NUMERO_PERSONAL = /\+?\d(?:[\s().-]*\d){6,}/g
const MAX_PROFUNDIDAD = 4
const MAX_ELEMENTOS = 30

function crearIdCorrelacion(): string {
  try {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()
    if (globalThis.crypto?.getRandomValues) {
      const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16))
      return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
    }
  } catch {
    // Algunos navegadores restringen crypto en contextos no seguros.
  }
  return `local-${Date.now().toString(36)}`
}

const ID_CORRELACION = crearIdCorrelacion()

export function idCorrelacion(): string {
  return ID_CORRELACION
}

export function idCorrelacionCorto(): string {
  return ID_CORRELACION.slice(0, 8)
}

export function limpiarTexto(valor: string): string {
  return valor
    .replace(BEARER, 'Bearer [REDACTADO]')
    .replace(JWT, '[JWT REDACTADO]')
    .replace(CORREO, '[CORREO REDACTADO]')
    .replace(NUMERO_PERSONAL, '[NUMERO REDACTADO]')
    .slice(0, 1_000)
}

export function limpiarDato(
  valor: unknown,
  profundidad = 0,
  vistos: WeakSet<object> = new WeakSet(),
): unknown {
  if (valor == null || typeof valor === 'boolean' || typeof valor === 'number') return valor
  if (typeof valor === 'string') return limpiarTexto(valor)
  if (typeof valor === 'bigint') return valor.toString()
  if (typeof valor === 'function' || typeof valor === 'symbol') return `[${typeof valor}]`
  if (profundidad >= MAX_PROFUNDIDAD) return '[TRUNCADO]'

  if (valor instanceof Error) {
    const errorConCodigo = valor as Error & { code?: unknown; status?: unknown }
    return {
      name: limpiarTexto(valor.name),
      message: limpiarTexto(valor.message),
      code: limpiarDato(errorConCodigo.code, profundidad + 1, vistos),
      status: limpiarDato(errorConCodigo.status, profundidad + 1, vistos),
    }
  }

  if (typeof valor !== 'object') return limpiarTexto(String(valor))
  if (vistos.has(valor)) return '[CIRCULAR]'
  vistos.add(valor)

  if (Array.isArray(valor)) {
    return valor.slice(0, MAX_ELEMENTOS).map((item) => limpiarDato(item, profundidad + 1, vistos))
  }

  const limpio: Record<string, unknown> = {}
  for (const [clave, dato] of Object.entries(valor).slice(0, MAX_ELEMENTOS)) {
    limpio[clave] = CLAVES_SENSIBLES.test(clave)
      ? '[REDACTADO]'
      : limpiarDato(dato, profundidad + 1, vistos)
  }
  return limpio
}

export interface EntradaObservabilidad {
  timestamp: string
  nivel: Nivel
  evento: string
  correlationId: string
  datos: unknown
}

// Sumidero opcional (p. ej. Sentry): recibe entradas YA limpias de PII y
// credenciales — jamás datos crudos. Lo conecta lib/sentry.ts si hay DSN.
let sumidero: ((entrada: EntradaObservabilidad) => void) | null = null

export function conectarSumidero(fn: (entrada: EntradaObservabilidad) => void): void {
  sumidero = fn
}

function escribir(nivel: Nivel, evento: string, datos?: unknown): void {
  const entrada: EntradaObservabilidad = {
    timestamp: new Date().toISOString(),
    nivel,
    evento: limpiarTexto(evento).slice(0, 120),
    correlationId: ID_CORRELACION,
    datos: limpiarDato(datos),
  }

  if (nivel === 'error') console.error('[ac-crm]', entrada)
  else if (nivel === 'warn') console.warn('[ac-crm]', entrada)
  else console.info('[ac-crm]', entrada)

  if (nivel !== 'info') {
    try {
      sumidero?.(entrada)
    } catch {
      // Un sumidero roto jamás debe tumbar la app ni el log local.
    }
  }
}

export function registrarInfo(evento: string, datos?: unknown): void {
  escribir('info', evento, datos)
}

export function registrarAviso(evento: string, datos?: unknown): void {
  escribir('warn', evento, datos)
}

export function registrarError(evento: string, error: unknown, contexto?: unknown): void {
  escribir('error', evento, { error, contexto })
}

const MARCA_GLOBAL = Symbol.for('avancecorp.crm.observabilidad.instalada')

/** Instala una sola vez capturas de errores que escapen de React/promesas. */
export function instalarObservabilidadGlobal(): void {
  if (typeof window === 'undefined') return
  const globalMarcado = globalThis as typeof globalThis & { [MARCA_GLOBAL]?: boolean }
  if (globalMarcado[MARCA_GLOBAL]) return
  globalMarcado[MARCA_GLOBAL] = true

  window.addEventListener('error', (evento) => {
    registrarError('runtime.error_no_controlado', evento.error ?? evento.message, {
      archivo: evento.filename,
      linea: evento.lineno,
      columna: evento.colno,
    })
  })
  window.addEventListener('unhandledrejection', (evento) => {
    registrarError('runtime.promesa_no_controlada', evento.reason)
  })
}
