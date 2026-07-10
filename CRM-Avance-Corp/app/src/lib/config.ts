// Config del cliente. NUNCA el service_role acá (solo la publishable/anon key).
// Las variables se validan antes de crear el cliente: una configuración parcial,
// una URL insegura o una key privilegiada dejan Supabase deshabilitado (fail-closed).

export type ProblemaConfig =
  | 'supabase_config_parcial'
  | 'supabase_url_invalida'
  | 'supabase_url_insegura'
  | 'supabase_key_invalida'
  | 'supabase_key_privilegiada'

const problemas: ProblemaConfig[] = []

function leerVariable(nombre: 'VITE_SUPABASE_URL' | 'VITE_SUPABASE_ANON_KEY'): string | undefined {
  const valor = import.meta.env[nombre]
  if (typeof valor !== 'string') return undefined
  const limpio = valor.trim()
  return limpio || undefined
}

function urlSupabaseSegura(valor: string | undefined): string | undefined {
  if (!valor) return undefined
  try {
    const url = new URL(valor)
    const hostLocal = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
    const protocoloSeguro = url.protocol === 'https:'
      || (import.meta.env.DEV && hostLocal && url.protocol === 'http:')
    if (!protocoloSeguro) {
      problemas.push('supabase_url_insegura')
      return undefined
    }
    if (url.username || url.password || url.search || url.hash || !['', '/'].includes(url.pathname)) {
      problemas.push('supabase_url_invalida')
      return undefined
    }
    return url.origin
  } catch {
    problemas.push('supabase_url_invalida')
    return undefined
  }
}

function rolDeJwt(valor: string): string | null {
  if (!valor.startsWith('eyJ')) return null
  try {
    const segmento = valor.split('.')[1]
    if (!segmento) return null
    const base64 = segmento.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(Math.ceil(segmento.length / 4) * 4, '=')
    const payload = JSON.parse(globalThis.atob(base64)) as { role?: unknown }
    return typeof payload.role === 'string' ? payload.role : null
  } catch {
    return null
  }
}

function keyPublicaSegura(valor: string | undefined): string | undefined {
  if (!valor) return undefined
  if (/^sb_secret_/i.test(valor) || /service[_-]?role/i.test(valor) || rolDeJwt(valor) === 'service_role') {
    problemas.push('supabase_key_privilegiada')
    return undefined
  }
  if (valor.length < 20 || /\s/.test(valor)) {
    problemas.push('supabase_key_invalida')
    return undefined
  }
  return valor
}

const urlOriginal = leerVariable('VITE_SUPABASE_URL')
const keyOriginal = leerVariable('VITE_SUPABASE_ANON_KEY')
if (Boolean(urlOriginal) !== Boolean(keyOriginal)) problemas.push('supabase_config_parcial')

const SUPABASE_URL = urlSupabaseSegura(urlOriginal)
const SUPABASE_ANON_KEY = keyPublicaSegura(keyOriginal)

export const CONFIG = Object.freeze({
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  MARCA: 'Avance Corp',
  MARCA_SUB: 'CRM Comercial',
})

export const PROBLEMAS_CONFIG: readonly ProblemaConfig[] = Object.freeze([...new Set(problemas)])
export const HAY_SUPABASE = Boolean(
  CONFIG.SUPABASE_URL
  && CONFIG.SUPABASE_ANON_KEY
  && PROBLEMAS_CONFIG.length === 0,
)

// El demo requiere opt-in literal y jamás entra en un build de producción.
export const DEMO_HABILITADO = import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true'
