export const INTERVALO_VERSION_PUBLICADA_MS = 60_000

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
 */
export function urlParaActualizar(urlActual: string, buildId: string): string {
  const url = new URL(urlActual)
  url.searchParams.set('crm_version', buildId)
  return url.toString()
}
