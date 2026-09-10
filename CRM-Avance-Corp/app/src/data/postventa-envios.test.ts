import {beforeEach, describe, expect, it, vi} from 'vitest'
import {CrmApiError} from './crm-api'
import {ejecutarEnvioPostventa} from './postventa-envios'
import {leerEnvioPostventa, guardarEnvioPostventa} from '@/lib/postventa-envios'
const api = vi.hoisted(() => ({sesion: vi.fn(), recibo: vi.fn(), agendar: vi.fn(), tarea: vi.fn(), veto: vi.fn(), solicitar: vi.fn(), revisar: vi.fn()}))
vi.mock('@/lib/supabase', () => ({sb: {auth: {getSession: api.sesion}, schema: () => ({rpc: api.recibo})}}))
vi.mock('./postventa-api', () => ({agendarPostventa: api.agendar, gestionarTareaPostventa: api.tarea,
  cambiarVetoPostventa: api.veto, solicitarRetiroPostventa: api.solicitar, revisarRetiroPostventa: api.revisar}))
const actor = '11111111-1111-4111-8111-111111111111', persona = '22222222-2222-4222-8222-222222222222'
const parametros = {p_inversionista: persona, p_datos: {tipo: 'llamada', titulo: 'Revisar el vencimiento', vence_en: '2027-01-01T15:00:00Z'}}
beforeEach(() => {
  vi.resetAllMocks(); sessionStorage.clear()
  api.sesion.mockResolvedValue({data: {session: {user: {id: actor}}}, error: null})
  api.recibo.mockResolvedValue({data: {registrada: false}, error: null})
  api.agendar.mockResolvedValue({ok: true})
})
describe('recuperación F6', () => {
  it('tras perder la respuesta reenvía exactamente el mismo UUID y contenido', async () => {
    api.agendar.mockRejectedValueOnce(new Error('Red interrumpida'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    const pendiente = leerEnvioPostventa(actor, 'agendar', persona)!
    expect(pendiente.intentos).toBe(1)
    await ejecutarEnvioPostventa(actor, 'agendar', persona)
    expect(api.agendar).toHaveBeenNthCalledWith(2, {...parametros, p_clave: pendiente.clave, p_actor: actor})
    expect(leerEnvioPostventa(actor, 'agendar', persona)).toBeNull()
  })
  it('un recibo propio confirmado recupera el envío sin repetir la escritura, incluso con F6 OFF', async () => {
    api.agendar.mockRejectedValueOnce(new Error('Corte'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    api.recibo.mockResolvedValueOnce({data: {registrada: true}, error: null})
    await ejecutarEnvioPostventa(actor, 'agendar', persona)
    expect(api.agendar).toHaveBeenCalledTimes(1)
    expect(leerEnvioPostventa(actor, 'agendar', persona)).toBeNull()
  })
  it('OFF o rechazo posterior al corte conserva la clave: no demuestra que el primer envío falló', async () => {
    api.agendar.mockRejectedValueOnce(new Error('Corte')).mockRejectedValueOnce(new CrmApiError('F6 OFF', 'P0409'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    const clave = leerEnvioPostventa(actor, 'agendar', persona)!.clave
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona)).rejects.toThrow()
    expect(leerEnvioPostventa(actor, 'agendar', persona)?.clave).toBe(clave)
  })
  it('un rechazo SQL explícito en el primer intento permite corregir los datos', async () => {
    api.agendar.mockRejectedValueOnce(new CrmApiError('Fecha pasada', '22023'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    expect(leerEnvioPostventa(actor, 'agendar', persona)).toBeNull()
  })
  it('un conflicto HTTP 409 del primer intento permite reintentar con datos nuevos', async () => {
    api.agendar.mockRejectedValueOnce(new CrmApiError('Vuelve a intentarlo', 'PT409'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    expect(leerEnvioPostventa(actor, 'agendar', persona)).toBeNull()
    await ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)
    expect(api.agendar).toHaveBeenCalledTimes(2)
  })
  it('un conflicto HTTP 409 tras un corte conserva la clave del resultado desconocido', async () => {
    api.agendar.mockRejectedValueOnce(new Error('Corte')).mockRejectedValueOnce(new CrmApiError('Vuelve a intentarlo', 'PT409'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    const clave = leerEnvioPostventa(actor, 'agendar', persona)!.clave
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona)).rejects.toThrow()
    expect(leerEnvioPostventa(actor, 'agendar', persona)?.clave).toBe(clave)
  })
  it('otro formulario no sustituye ni repite a ciegas un envío con diferente contenido', async () => {
    api.agendar.mockRejectedValueOnce(new Error('Corte'))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow()
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, {...parametros, p_datos: {...parametros.p_datos, titulo: 'Otra gestión'}})).rejects.toThrow('gestión anterior')
    expect(api.agendar).toHaveBeenCalledTimes(1); expect(api.recibo).not.toHaveBeenCalled()
  })
  it('dos clics simultáneos producen un solo envío', async () => {
    let terminar!: () => void
    api.agendar.mockImplementationOnce(() => new Promise<void>(r => {terminar = r}))
    const primero = ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)
    await vi.waitFor(() => expect(api.agendar).toHaveBeenCalledTimes(1))
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow('ya se está enviando')
    terminar(); await primero
    expect(api.agendar).toHaveBeenCalledTimes(1)
  })
  it('al cambiar la cuenta no envía un borrador de la cuenta anterior', async () => {
    api.sesion.mockResolvedValue({data: {session: {user: {id: persona}}}, error: null})
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow('sesión cambió')
    expect(api.agendar).not.toHaveBeenCalled()
  })
  it('no envía si no puede persistir la recuperación o el contenido es ilegible', async () => {
    vi.stubGlobal('sessionStorage', {getItem: () => null, setItem: () => {throw new Error('Almacenamiento bloqueado')}})
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow('Almacenamiento')
    expect(api.agendar).not.toHaveBeenCalled(); vi.unstubAllGlobals()
    sessionStorage.setItem(`crm:f6:envio:${actor}:agendar:${persona}`, '{truncado')
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona, parametros)).rejects.toThrow('leer el envío')
    expect(api.agendar).not.toHaveBeenCalled()
  })
  it('un recibo no consultable no libera la referencia ni crea un nuevo envío', async () => {
    guardarEnvioPostventa({version: 1, actor, sujeto: persona, comando: 'agendar', clave: crypto.randomUUID(), parametros, intentos: 1})
    api.recibo.mockResolvedValue({data: null, error: {code: '42501', message: 'Sin acceso'}})
    await expect(ejecutarEnvioPostventa(actor, 'agendar', persona)).rejects.toThrow()
    expect(api.agendar).not.toHaveBeenCalled(); expect(leerEnvioPostventa(actor, 'agendar', persona)).not.toBeNull()
  })
})
