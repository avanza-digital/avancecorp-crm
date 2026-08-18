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

// ── Gate del mundo leads (Miguel: cerrado el 2026-07-16, ABIERTO el 2026-08-18) ─
// El pipeline de leads y los paneles Hoy/Agenda/Cartera salieron a producción
// OCULTOS para las cuentas reales: el CRM arrancó solo con Clientes y Contratos
// (el panel del analista traspasado del portal). Miguel aprobó abrirlos a toda
// la fuerza de ventas el 2026-08-18, con el circuito de lead libre ya vivo en
// producción (verificar → tomar → recordar) y probado durante un mes en el
// piloto de su propia cuenta, que por eso desaparece de aquí.
// Cerrarlo otra vez = poner false (no hay más interruptores que este).
export const FUNCIONES_LEADS_APROBADAS: boolean = true

/**
 * ¿Se muestran las vistas de leads (Hoy/Pipeline/Cartera/Agenda)?
 * En modo DEMO siempre — el demo es el escaparate del CRM completo.
 * En sesiones reales: gerencia y directorio siempre (aprobación parcial del
 * 2026-07-16) y la FUERZA DE VENTAS (vendedor/supervisor) según la llave.
 * La lista es cerrada a propósito — quien no está, no ve:
 *  · el COORDINADOR nunca entra al mundo leads, ni con la llave abierta: su
 *    ámbito de leads es ∅ (espejo exacto de la RLS
 *    `private.vendedor_ids_visibles`) y su único destino es «Repartir leads».
 *    Sin este corte, abrir la llave le pintaría «Hoy» —la única vista de leads
 *    que no exige capacidad— y un buscador de leads que nunca encuentra nada.
 *  · un rol ausente o desconocido tampoco: mínimo privilegio.
 *
 * ⚠️ Esto NO es un permiso: es solo qué PINTA el navegador. El ámbito de datos
 * lo sigue decidiendo la RLS, que para cada rol devuelve lo mismo que ayer.
 */
export function funcionesLeadsVisibles(esDemo: boolean, rol?: string | null): boolean {
  if (esDemo) return true
  if (rol === 'gerencia' || rol === 'directorio') return true
  if (rol === 'vendedor' || rol === 'supervisor') return FUNCIONES_LEADS_APROBADAS
  // Coordinador, rol ausente o desconocido: mínimo privilegio, la llave no les toca.
  return false
}
