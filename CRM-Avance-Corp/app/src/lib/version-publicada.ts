export const INTERVALO_VERSION_PUBLICADA_MS = 60_000

/** Parámetro con el que la recarga salta la copia cacheada de index.html. */
const PARAMETRO_VERSION = 'crm_version'

export interface VersionPublicada {
  schema: 1
  buildId: string
}

type FetchVersion = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Pick<Response, 'ok' | 'json'>>

function esVersionPublicada(valor: unknown): valor is VersionPublicada {
  if (!valor || typeof valor !== 'object') return false
  const version = valor as Record<string, unknown>
  return version.schema === 1
    && typeof version.buildId === 'string'
    && /^[A-Za-z0-9._:-]{1,128}$/.test(version.buildId)
}

/**
 * Consulta el marcador que acompaña al deploy. El query único y `no-store`
 * evitan que el navegador o un CDN intermedio respondan con el marcador viejo.
 * Un fallo de red es silencioso: nunca debe interrumpir el trabajo comercial.
 */
export async function consultarVersionPublicada({
  baseUrl,
  fetchVersion = globalThis.fetch,
  ahora = Date.now(),
  signal,
}: {
  baseUrl: string
  fetchVersion?: FetchVersion
  ahora?: number
  signal?: AbortSignal
}): Promise<VersionPublicada | null> {
  try {
    const url = new URL('version.json', baseUrl)
    url.searchParams.set('_version', String(ahora))
    const opciones: RequestInit = {
      cache: 'no-store',
      credentials: 'same-origin',
      headers: { Accept: 'application/json' },
    }
    if (signal) opciones.signal = signal
    const respuesta = await fetchVersion(url, opciones)
    if (!respuesta.ok) return null
    const valor: unknown = await respuesta.json()
    return esVersionPublicada(valor) ? valor : null
  } catch {
    return null
  }
}

export function hayVersionNueva(actual: string, publicada: VersionPublicada | null): boolean {
  return Boolean(publicada && publicada.buildId !== actual)
}

/**
 * Conserva la ruta hash actual y agrega una llave al documento HTML. Así el
 * botón de actualización no depende de una copia cacheada de index.html.
 * La llave se retira al arrancar (`limpiarMarcaDeVersion`): solo sirve para
 * cruzar la caché, no para quedarse en la barra de direcciones.
 */
export function urlParaActualizar(urlActual: string, buildId: string): string {
  const url = new URL(urlActual)
  url.searchParams.set(PARAMETRO_VERSION, buildId)
  return url.toString()
}

/**
 * Inversa de `urlParaActualizar`: la misma URL sin la llave `crm_version`,
 * conservando la ruta hash y el resto de parámetros. Sin otros parámetros no
 * queda un `?` suelto. Devuelve `null` si no había nada que limpiar o la URL
 * no se puede leer; nunca lanza, porque corre en el arranque.
 */
export function urlSinMarcaDeVersion(urlActual: string): string | null {
  let url: URL
  try {
    url = new URL(urlActual)
  } catch {
    return null
  }
  if (!url.searchParams.has(PARAMETRO_VERSION)) return null
  url.searchParams.delete(PARAMETRO_VERSION)
  if (!url.searchParams.toString()) url.search = ''
  return url.toString()
}

/**
 * Retira la llave de la barra de direcciones tras la recarga, sin recargar ni
 * tocar la ruta hash. Se llama UNA vez al arrancar, antes de que el router lea
 * la URL: `replaceState` no dispara `hashchange` ni añade historial. Devuelve
 * si limpió algo. Nunca lanza: un entorno sin `history` o una URL rara no
 * deben impedir el arranque.
 */
export function limpiarMarcaDeVersion(): boolean {
  try {
    const limpia = urlSinMarcaDeVersion(window.location.href)
    if (!limpia) return false
    window.history.replaceState(window.history.state, '', limpia)
    return true
  } catch {
    return false
  }
}
