import { sb } from './supabase'

export interface EstadoPushTasa {
  configurado: boolean
  clavePublica: string
  dispositivo: { id: string; activo: boolean } | null
}

const CUENTA = 'crm.push-tasa.cuenta'
const DISPOSITIVO = 'crm.push-tasa.dispositivo'
const REVOCACIONES = 'crm.push-tasa.revocaciones'
const CONTROL = 'crm-push-tasa-control-v1'
let cuentaActual: string | null = null
let generacion = 0
let limpiezaPendiente: Promise<void> = Promise.resolve()
let escrituraControl: Promise<void> = Promise.resolve()

/** Solo un interruptor local, sin datos del CRM. También funciona sin conexión. */
function permitirAvisos(permitido: boolean): Promise<void> {
  escrituraControl = escrituraControl.catch(() => {}).then(async () => {
    const cache = await caches.open(CONTROL)
    await cache.put('/__crm_push_habilitado', new Response(permitido ? '1' : '0'))
  })
  return escrituraControl
}

type Revocacion = { id: string; cuenta: string }
function pendientesRevocacion(): Revocacion[] {
  try {
    const datos: unknown = JSON.parse(leerLocal(REVOCACIONES) ?? '[]')
    return Array.isArray(datos) ? datos.filter((v): v is Revocacion => typeof v?.id === 'string' && typeof v?.cuenta === 'string').slice(-100) : []
  } catch { return [] }
}
function guardarRevocaciones(pendientes: Revocacion[]): void {
  try { localStorage.setItem(REVOCACIONES, JSON.stringify(pendientes)) } catch { /* La baja local del SW es independiente. */ }
}
async function reintentarRevocaciones(): Promise<void> {
  if (!sb || !cuentaActual) return
  const cuenta = cuentaActual
  for (const pendiente of pendientesRevocacion().filter(v => v.cuenta === cuenta)) {
    if (cuenta !== cuentaActual) break
    try {
      const { error } = await sb.schema('crm').rpc('desactivar_push_tasa_fn', { p_dispositivo_id: pendiente.id }).abortSignal(AbortSignal.timeout(8000))
      if (!error && cuenta === cuentaActual) guardarRevocaciones(pendientesRevocacion().filter(v => v.id !== pendiente.id))
    } catch { /* Conserva el ID para el siguiente inicio o consulta. */ }
  }
}

export function soportePushTasa(): 'disponible' | 'instalar' | 'incompatible' {
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  const instalada = window.matchMedia?.('(display-mode: standalone)').matches
    || (navigator as Navigator & { standalone?: boolean }).standalone === true
  if (ios && !instalada) return 'instalar'
  return window.isSecureContext && 'serviceWorker' in navigator && 'PushManager' in window
    && 'Notification' in window && 'caches' in window ? 'disponible' : 'incompatible'
}

function leerLocal(clave: string): string | null {
  try { return localStorage.getItem(clave) } catch { return null }
}

export function vincularCuentaPushTasa(cuenta: string | null): void {
  if (cuentaActual === cuenta) return
  generacion++
  cuentaActual = cuenta
  const anterior = leerLocal(CUENTA)
  if (anterior && anterior !== cuenta) void limpiarPushTasaAlSalir()
  if (cuenta) limpiezaPendiente = limpiezaPendiente.then(reintentarRevocaciones)
}

async function registroActual(): Promise<ServiceWorkerRegistration | undefined> {
  return 'serviceWorker' in navigator ? navigator.serviceWorker.getRegistration('/sw-crm.js') : undefined
}

export async function consultarPushTasa(): Promise<EstadoPushTasa> {
  if (!sb) throw new Error('Inicia sesión para activar los avisos.')
  await limpiezaPendiente
  await reintentarRevocaciones()
  const registro = await registroActual()
  const suscripcion = await registro?.pushManager.getSubscription()
  const { data, error } = await sb.functions.invoke('crm-notificaciones-tasa', {
    body: { accion: 'configuracion', endpoint: suscripcion?.endpoint ?? null },
  })
  if (error || !data || typeof data.configurado !== 'boolean' || typeof data.clavePublica !== 'string') {
    throw new Error('No pudimos consultar los avisos. Intenta nuevamente.')
  }
  if (data.dispositivo !== null && (typeof data.dispositivo?.id !== 'string' || typeof data.dispositivo?.activo !== 'boolean')) {
    throw new Error('No pudimos comprobar este dispositivo.')
  }
  return data as EstadoPushTasa
}

function claveBytes(texto: string): Uint8Array<ArrayBuffer> {
  const base = texto.replace(/-/g, '+').replace(/_/g, '/')
  return Uint8Array.from(atob(base.padEnd(Math.ceil(base.length / 4) * 4, '=')), c => c.charCodeAt(0))
}

async function esperarActivo(registro: ServiceWorkerRegistration): Promise<void> {
  if (registro.active) return
  const worker = registro.installing ?? registro.waiting
  if (!worker) throw new Error('No pudimos preparar los avisos. Recarga e intenta nuevamente.')
  await new Promise<void>((resolve, reject) => {
    const limpiar = () => { clearTimeout(reloj); worker.removeEventListener('statechange', cambio) }
    const cambio = () => {
      if (worker.state === 'activated') { limpiar(); resolve() }
      else if (worker.state === 'redundant') { limpiar(); reject(new Error('No pudimos preparar los avisos.')) }
    }
    const reloj = setTimeout(() => { limpiar(); reject(new Error('La activación tardó demasiado. Intenta nuevamente.')) }, 10_000)
    worker.addEventListener('statechange', cambio)
    cambio()
  })
}

/** Se invoca directamente desde el clic: iOS exige el permiso dentro del gesto. */
export async function activarPushTasa(cuenta: string, estado: EstadoPushTasa): Promise<string> {
  if (!sb || !estado.configurado || soportePushTasa() !== 'disponible') throw new Error('Los avisos no están disponibles en este dispositivo.')
  const version = generacion
  const vigente = () => {
    if (version !== generacion || cuentaActual !== cuenta) throw new Error('La sesión cambió. Vuelve a iniciar sesión.')
  }
  vigente()
  // Ningún await previo a requestPermission: conserva la interacción directa.
  const permiso = Notification.permission === 'granted' ? 'granted' : await Notification.requestPermission()
  if (permiso !== 'granted') throw new Error('Permite las notificaciones para recibir solicitudes de tasa.')
  await limpiezaPendiente
  vigente()
  const registro = await navigator.serviceWorker.register('/sw-crm.js', { scope: '/', updateViaCache: 'none' })
  await esperarActivo(registro)
  vigente()
  let suscripcion = await registro.pushManager.getSubscription()
  const clave = claveBytes(estado.clavePublica)
  const anterior = suscripcion?.options.applicationServerKey
  if (suscripcion && anterior && (new Uint8Array(anterior).length !== clave.length || new Uint8Array(anterior).some((v, i) => v !== clave[i]))) {
    await suscripcion.unsubscribe()
    suscripcion = null
  }
  vigente()
  suscripcion ??= await registro.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: clave })
  try {
    vigente()
    const json = suscripcion.toJSON()
    if (!json.keys?.p256dh || !json.keys.auth) throw new Error('El teléfono no devolvió una suscripción válida.')
    const { data, error } = await sb.schema('crm').rpc('registrar_push_tasa_fn', {
      p_endpoint: suscripcion.endpoint, p_p256dh: json.keys.p256dh.replace(/=+$/, ''), p_auth: json.keys.auth.replace(/=+$/, ''),
    })
    if (error || typeof data !== 'string') throw new Error('No pudimos guardar la activación. Intenta nuevamente.')
    vigente()
    localStorage.setItem(CUENTA, cuenta)
    localStorage.setItem(DISPOSITIVO, data)
    await permitirAvisos(true)
    vigente()
    return data
  } catch (error) {
    if (version === generacion) await permitirAvisos(false).catch(() => {})
    await suscripcion.unsubscribe().catch(() => false)
    throw error
  }
}

export async function desactivarPushTasa(id?: string): Promise<{ pendiente: boolean }> {
  const pendiente = await revocarDispositivo(id ?? leerLocal(DISPOSITIVO), leerLocal(CUENTA) ?? cuentaActual)
  localStorage.removeItem(CUENTA)
  localStorage.removeItem(DISPOSITIVO)
  return { pendiente }
}

async function revocarDispositivo(dispositivo: string | null, cuenta: string | null): Promise<boolean> {
  if (dispositivo && cuenta) guardarRevocaciones([
    ...pendientesRevocacion().filter(v => v.id !== dispositivo), { id: dispositivo, cuenta },
  ])
  // Las tres barreras se intentan independientemente: un fallo de red no impide
  // desactivar el SW, y un fallo del proveedor no impide revocar en el servidor.
  const resultados = await Promise.allSettled([
    permitirAvisos(false),
    (async () => {
      const registro = await registroActual()
      const avisos = await registro?.getNotifications()
      avisos?.forEach(aviso => aviso.close())
      const suscripcion = await registro?.pushManager.getSubscription()
      if (suscripcion && !await suscripcion.unsubscribe()) throw new Error('No pudimos retirar la suscripción.')
    })(),
    (async () => {
      if (!dispositivo || !sb || cuenta !== cuentaActual) return false
      const { error } = await sb.schema('crm').rpc('desactivar_push_tasa_fn', { p_dispositivo_id: dispositivo }).abortSignal(AbortSignal.timeout(8000))
      if (error) throw error
      if (cuenta === cuentaActual) guardarRevocaciones(pendientesRevocacion().filter(v => v.id !== dispositivo))
      return true
    })(),
  ])
  if (resultados[0].status === 'rejected' && resultados[1].status === 'rejected'
      && (resultados[2].status === 'rejected' || resultados[2].value !== true)) throw new Error('No pudimos desactivar los avisos. Intenta nuevamente.')
  return resultados[2].status === 'rejected'
}

/** Invalida activaciones en vuelo antes de que Auth quite el token. */
export async function limpiarPushTasaAlSalir(): Promise<void> {
  generacion++
  // No espera una baja remota anterior para bloquear el contenido de este teléfono.
  void permitirAvisos(false).catch(() => {})
  const id = leerLocal(DISPOSITIVO)
  const cuenta = leerLocal(CUENTA) ?? cuentaActual
  if (id && cuenta) guardarRevocaciones([...pendientesRevocacion().filter(v => v.id !== id), { id, cuenta }])
  try { localStorage.removeItem(CUENTA); localStorage.removeItem(DISPOSITIVO) } catch { /* Almacenamiento restringido. */ }
  limpiezaPendiente = limpiezaPendiente.catch(() => {}).then(async () => { await revocarDispositivo(id, cuenta) }).catch(() => {})
  await limpiezaPendiente
}

export async function probarPushTasa(dispositivoId: string): Promise<void> {
  if (!sb) throw new Error('Inicia sesión para probar los avisos.')
  const { data, error } = await sb.functions.invoke('crm-notificaciones-tasa', { body: { accion: 'prueba', dispositivoId } })
  if (error || data?.enviado !== true) throw new Error('No pudimos enviar la prueba. Espera un minuto e intenta nuevamente.')
}
