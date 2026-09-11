import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const dobles = vi.hoisted(() => ({ rpc: vi.fn(), invoke: vi.fn() }))
vi.mock('./supabase', () => ({ sb: { schema: () => ({ rpc: (...argumentos: unknown[]) => {
  const respuesta = dobles.rpc(...argumentos)
  return { then: respuesta.then.bind(respuesta), abortSignal: () => respuesta }
} }), functions: { invoke: dobles.invoke } } }))
const cuenta = 'd7100000-0000-4000-8000-000000000001'
const id = 'd7100000-0000-4000-8000-000000000002'
const clave = 'B'.repeat(87)
let modulo: typeof import('./notificaciones-tasa')
let suscripcion: { endpoint: string; options: object; toJSON: () => object; unsubscribe: ReturnType<typeof vi.fn> }
let registro: { active: object; pushManager: { getSubscription: ReturnType<typeof vi.fn>; subscribe: ReturnType<typeof vi.fn> }; getNotifications: ReturnType<typeof vi.fn> }
let register: ReturnType<typeof vi.fn>
let permiso: ReturnType<typeof vi.fn>
let control: Map<string, Response>

beforeEach(async () => {
  vi.resetModules()
  localStorage.clear()
  dobles.rpc.mockReset().mockResolvedValue({ data: id, error: null })
  dobles.invoke.mockReset().mockResolvedValue({ data: { configurado: true, clavePublica: clave, dispositivo: null }, error: null })
  suscripcion = { endpoint: 'https://fcm.googleapis.com/fcm/send/sintetico', options: {}, toJSON: () => ({ keys: { p256dh: clave, auth: 'a'.repeat(22) } }), unsubscribe: vi.fn().mockResolvedValue(true) }
  registro = { active: {}, pushManager: { getSubscription: vi.fn().mockResolvedValue(null), subscribe: vi.fn().mockResolvedValue(suscripcion) }, getNotifications: vi.fn().mockResolvedValue([]) }
  register = vi.fn().mockResolvedValue(registro)
  permiso = vi.fn().mockResolvedValue('granted')
  control = new Map()
  vi.stubGlobal('caches', { open: async () => ({ put: async (clave: string, valor: Response) => { control.set(clave, valor) } }) })
  vi.stubGlobal('navigator', { userAgent: 'Android', platform: 'Linux', maxTouchPoints: 0, serviceWorker: { register, getRegistration: vi.fn().mockResolvedValue(registro) } })
  vi.stubGlobal('isSecureContext', true)
  vi.stubGlobal('PushManager', class {})
  vi.stubGlobal('Notification', { permission: 'default', requestPermission: permiso })
  modulo = await import('./notificaciones-tasa')
  modulo.vincularCuentaPushTasa(cuenta)
})
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); localStorage.clear() })

describe('Activación y aislamiento de las notificaciones de tasa', () => {
  it('solicita permiso dentro del clic y solo después prepara la suscripción', async () => {
    let permitir!: (valor: string) => void
    permiso.mockReturnValue(new Promise(resolve => { permitir = resolve }))
    const tarea = modulo.activarPushTasa(cuenta, { configurado: true, clavePublica: clave, dispositivo: null })
    expect(permiso).toHaveBeenCalledOnce()
    expect(register).not.toHaveBeenCalled()
    permitir('granted')
    expect(await tarea).toBe(id)
    expect(register).toHaveBeenCalledWith('/sw-crm.js', { scope: '/', updateViaCache: 'none' })
    expect(dobles.rpc).toHaveBeenCalledWith('registrar_push_tasa_fn', { p_endpoint: suscripcion.endpoint, p_p256dh: clave, p_auth: 'a'.repeat(22) })
    expect(localStorage.getItem('crm.push-tasa.cuenta')).toBe(cuenta)
  })
  it('si se deniega el permiso no crea una suscripción ni escribe en servidor', async () => {
    permiso.mockResolvedValue('denied')
    await expect(modulo.activarPushTasa(cuenta, { configurado: true, clavePublica: clave, dispositivo: null })).rejects.toThrow(/Permite/)
    expect(register).not.toHaveBeenCalled(); expect(dobles.rpc).not.toHaveBeenCalled()
  })
  it('el fallo del registro en servidor retira la suscripción y no muestra activación', async () => {
    dobles.rpc.mockResolvedValue({ data: null, error: { code: '42501' } })
    await expect(modulo.activarPushTasa(cuenta, { configurado: true, clavePublica: clave, dispositivo: null })).rejects.toThrow(/guardar/)
    expect(suscripcion.unsubscribe).toHaveBeenCalledOnce()
    expect(localStorage.getItem('crm.push-tasa.dispositivo')).toBeNull()
  })
  it('un endpoint de otra cuenta se retira y el siguiente intento registra uno nuevo', async () => {
    registro.pushManager.getSubscription.mockResolvedValueOnce(suscripcion).mockResolvedValue(null)
    const nueva = { ...suscripcion, endpoint: 'https://fcm.googleapis.com/fcm/send/nuevo-dispositivo' }
    registro.pushManager.subscribe.mockResolvedValue(nueva)
    dobles.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } }).mockResolvedValue({ data: id, error: null })
    const estado = { configurado: true, clavePublica: clave, dispositivo: null }
    await expect(modulo.activarPushTasa(cuenta, estado)).rejects.toThrow(/guardar/)
    expect(suscripcion.unsubscribe).toHaveBeenCalledOnce()
    expect(await modulo.activarPushTasa(cuenta, estado)).toBe(id)
    expect(dobles.rpc).toHaveBeenLastCalledWith('registrar_push_tasa_fn', expect.objectContaining({ p_endpoint: nueva.endpoint }))
  })
  it('salir mientras se guarda impide que una respuesta tardía reactive el dispositivo', async () => {
    let completar!: (valor: unknown) => void
    dobles.rpc.mockReturnValue(new Promise(resolve => { completar = resolve }))
    const tarea = modulo.activarPushTasa(cuenta, { configurado: true, clavePublica: clave, dispositivo: null })
    const rechazo = expect(tarea).rejects.toThrow(/sesión cambió/)
    await vi.waitFor(() => expect(dobles.rpc).toHaveBeenCalled())
    await modulo.limpiarPushTasaAlSalir()
    completar({ data: id, error: null })
    await rechazo
    expect(suscripcion.unsubscribe).toHaveBeenCalledOnce()
    expect(localStorage.getItem('crm.push-tasa.cuenta')).toBeNull()
  })
  it('desactivar revoca solo este dispositivo y cierra los avisos existentes', async () => {
    registro.pushManager.getSubscription.mockResolvedValue(suscripcion)
    const close = vi.fn(); registro.getNotifications.mockResolvedValue([{ close }])
    await modulo.desactivarPushTasa(id)
    expect(suscripcion.unsubscribe).toHaveBeenCalledOnce(); expect(close).toHaveBeenCalledOnce()
    expect(dobles.rpc).toHaveBeenCalledWith('desactivar_push_tasa_fn', { p_dispositivo_id: id })
  })
  it('iPhone requiere abrir la aplicación instalada; un navegador compatible queda disponible', () => {
    vi.stubGlobal('navigator', { userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 1, serviceWorker: {}, standalone: false })
    expect(modulo.soportePushTasa()).toBe('instalar')
    vi.stubGlobal('navigator', { userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 1, serviceWorker: {}, standalone: true })
    expect(modulo.soportePushTasa()).toBe('disponible')
  })
  it('una respuesta incompleta no se interpreta como una activación válida', async () => {
    dobles.invoke.mockResolvedValue({ data: { configurado: true }, error: null })
    await expect(modulo.consultarPushTasa()).rejects.toThrow(/consultar/)
  })
  it('una prueba fallida se informa como fallida', async () => {
    dobles.invoke.mockResolvedValue({ data: null, error: {} })
    await expect(modulo.probarPushTasa(id)).rejects.toThrow(/enviar/)
  })
  it('un cierre sin red bloquea el worker y conserva la baja para el siguiente inicio', async () => {
    localStorage.setItem('crm.push-tasa.cuenta', cuenta)
    localStorage.setItem('crm.push-tasa.dispositivo', id)
    registro.pushManager.getSubscription.mockResolvedValue(suscripcion)
    suscripcion.unsubscribe.mockRejectedValue(new Error('sin red'))
    dobles.rpc.mockRejectedValue(new Error('sin red'))
    await modulo.limpiarPushTasaAlSalir()
    expect(await control.get('/__crm_push_habilitado')?.text()).toBe('0')
    expect(localStorage.getItem('crm.push-tasa.dispositivo')).toBeNull()
    expect(JSON.parse(localStorage.getItem('crm.push-tasa.revocaciones')!)).toEqual([{ id, cuenta }])
    dobles.rpc.mockResolvedValue({ data: null, error: null })
    vi.resetModules()
    modulo = await import('./notificaciones-tasa')
    modulo.vincularCuentaPushTasa(cuenta)
    await modulo.consultarPushTasa()
    expect(dobles.rpc).toHaveBeenLastCalledWith('desactivar_push_tasa_fn', { p_dispositivo_id: id })
    expect(JSON.parse(localStorage.getItem('crm.push-tasa.revocaciones')!)).toEqual([])
  })
  it('el fallo del proveedor no impide intentar la baja en el servidor', async () => {
    registro.pushManager.getSubscription.mockResolvedValue(suscripcion)
    suscripcion.unsubscribe.mockRejectedValue(new Error('proveedor caído'))
    await modulo.desactivarPushTasa(id)
    expect(dobles.rpc).toHaveBeenCalledWith('desactivar_push_tasa_fn', { p_dispositivo_id: id })
    expect(await control.get('/__crm_push_habilitado')?.text()).toBe('0')
  })
  it('no intenta revocar el dispositivo de otra cuenta con el token nuevo', async () => {
    localStorage.setItem('crm.push-tasa.revocaciones', JSON.stringify([{ id, cuenta: 'otra-cuenta' }]))
    await modulo.consultarPushTasa()
    expect(dobles.rpc).not.toHaveBeenCalled()
    expect(JSON.parse(localStorage.getItem('crm.push-tasa.revocaciones')!)).toHaveLength(1)
  })
  it('un inicio de sesión reintenta las bajas propias sin visitar Configuración', async () => {
    localStorage.setItem('crm.push-tasa.revocaciones', JSON.stringify([{ id, cuenta }]))
    vi.resetModules()
    modulo = await import('./notificaciones-tasa')
    modulo.vincularCuentaPushTasa(cuenta)
    await vi.waitFor(() => expect(dobles.rpc).toHaveBeenCalledWith('desactivar_push_tasa_fn', { p_dispositivo_id: id }))
    await vi.waitFor(() => expect(JSON.parse(localStorage.getItem('crm.push-tasa.revocaciones')!)).toEqual([]))
  })
})
