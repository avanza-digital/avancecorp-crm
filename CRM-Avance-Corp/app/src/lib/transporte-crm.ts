/** Evita que una consulta pendiente use la clave pública al perder el JWT.
 * Supabase ya resolvió/refrescó la sesión antes de llegar a este transporte.
 * El servidor sigue siendo quien autoriza: esta guarda solo evita tráfico anónimo.
 */
export function crearFetchCrm(
  proyecto: string,
  clavePublica: string,
  enviar: typeof fetch = (...argumentos) => globalThis.fetch(...argumentos),
): typeof fetch {
  const origen = new URL(proyecto).origin
  return async (entrada, opciones) => {
    const peticion = entrada instanceof Request ? entrada : null
    const url = new URL(peticion ? peticion.url : String(entrada), proyecto)
    const cabeceras = new Headers(opciones?.headers ?? peticion?.headers)
    const esCrm = url.origin === origen && url.pathname.startsWith('/rest/v1/')
      && (cabeceras.get('Accept-Profile') === 'crm' || cabeceras.get('Content-Profile') === 'crm')
    const token = cabeceras.get('Authorization')?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim()
    if (esCrm && (!token || token === clavePublica)) {
      const senal = opciones?.signal ?? peticion?.signal
      senal?.throwIfAborted()
      // Un error de red dispararía reintentos del SDK. El 401 local es terminal.
      // No cerrar Auth: también puede faltar token durante un fallo de refresh.
      return Response.json({
        code: 'CRM_SESSION_UNAVAILABLE',
        message: 'No hay una sesión disponible. Vuelve a iniciar sesión o reintenta cuando se recupere la conexión.',
        details: null,
        hint: null,
      }, { status: 401 })
    }
    return enviar(entrada, opciones)
  }
}
