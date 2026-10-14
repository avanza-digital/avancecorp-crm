import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthApiError, createClient, type Session } from '@supabase/supabase-js'
import { crearFetchCrm } from './transporte-crm'

const proyecto = 'https://crm-prueba.supabase.co'
const clave = 'anon-solo-prueba'
const ruta = `${proyecto}/rest/v1/rpc/tareas_pendientes_fn`
const cabeceras = { 'Content-Profile': 'crm', Authorization: `Bearer ${clave}` }

afterEach(() => vi.restoreAllMocks())

describe('transporte CRM ante pérdida de sesión', () => {
  it.each(['GET', 'POST', 'PATCH', 'DELETE', 'HEAD'])('bloquea %s anónimo sin salir a la red', async method => {
    const enviar = vi.fn<typeof fetch>()
    const respuesta = await crearFetchCrm(proyecto, clave, enviar)(ruta, { method, headers: cabeceras })
    expect(respuesta.status).toBe(401)
    expect(await respuesta.json()).toMatchObject({ code: 'CRM_SESSION_UNAVAILABLE' })
    expect(enviar).not.toHaveBeenCalled()
  })

  it('usa las cabeceras efectivas de init y admite claves publishable', async () => {
    const enviar = vi.fn<typeof fetch>().mockResolvedValue(Response.json([]))
    const publica = 'sb_publishable_fixture_sin_sesion'
    const transporte = crearFetchCrm(proyecto, publica, enviar)
    const peticion = new Request(ruta, { headers: { ...cabeceras, Authorization: 'Bearer jwt-viejo' } })
    const respuesta = await transporte(peticion, {
      headers: { ...cabeceras, Authorization: `Bearer ${publica}` },
    })
    expect(respuesta.status).toBe(401)
    expect(enviar).not.toHaveBeenCalled()
  })

  it('bloquea Request, URL, ausencia de Bearer y cabeceras sin importar mayúsculas', async () => {
    const enviar = vi.fn<typeof fetch>()
    const transporte = crearFetchCrm(proyecto, clave, enviar)
    const solicitudes = [
      transporte(new Request(ruta, { headers: { 'accept-profile': 'crm' } })),
      transporte(new URL(ruta), { headers: { 'content-profile': 'crm', authorization: 'Basic ejemplo' } }),
      transporte(ruta, { headers: { 'Accept-Profile': 'crm', Authorization: 'Bearer   ' } }),
    ]
    expect((await Promise.all(solicitudes)).map(r => r.status)).toEqual([401, 401, 401])
    expect(enviar).not.toHaveBeenCalled()
  })

  it('conserva JWT, cuerpo, método y aborto sin alterar la petición autorizada', async () => {
    const enviar = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ ok: true }))
    const opciones = { method: 'POST', body: '{"p_limite":20}', signal: new AbortController().signal,
      headers: { ...cabeceras, Authorization: 'Bearer jwt-de-usuario' } }
    await crearFetchCrm(proyecto, clave, enviar)(ruta, opciones)
    expect(enviar).toHaveBeenCalledExactlyOnceWith(ruta, opciones)
  })

  it('respeta una cancelación previa también cuando falta sesión', async () => {
    const enviar = vi.fn<typeof fetch>()
    const control = new AbortController()
    control.abort()
    await expect(crearFetchCrm(proyecto, clave, enviar)(ruta, {
      headers: cabeceras, signal: control.signal,
    })).rejects.toMatchObject({ name: 'AbortError' })
    expect(enviar).not.toHaveBeenCalled()
  })

  it('permite login, refresh, otros esquemas y otros servicios', async () => {
    const enviar = vi.fn<typeof fetch>().mockImplementation(async () => Response.json({ ok: true }))
    const transporte = crearFetchCrm(proyecto, clave, enviar)
    await transporte(`${proyecto}/auth/v1/token?grant_type=refresh_token`, { method: 'POST' })
    await transporte(`${proyecto}/rest/v1/configuracion`, { headers: { 'Accept-Profile': 'public' } })
    await transporte('https://otro.test/rest/v1/rpc/ejemplo', { headers: cabeceras })
    expect(enviar).toHaveBeenCalledTimes(3)
  })

  it('el SDK real no envía ni reintenta las consultas pendientes sin sesión', async () => {
    const enviar = vi.fn<typeof fetch>()
    const cliente = createClient(proyecto, clave, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: crearFetchCrm(proyecto, clave, enviar) },
    })
    const resultados = await Promise.all([
      cliente.schema('crm').rpc('tareas_pendientes_fn'),
      cliente.schema('crm').rpc('desactivar_push_tasa_fn', { p_id: 'prueba' }),
      cliente.schema('crm').from('tareas').select('id'),
    ])
    for (const r of resultados) expect(r.error?.code).toBe('CRM_SESSION_UNAVAILABLE')
    expect(enviar).not.toHaveBeenCalled()
  })

  it('tolera refresh fallido, se recupera con nuevo JWT y nunca reenvía la escritura bloqueada', async () => {
    const enviar = vi.fn<typeof fetch>().mockImplementation(async () => Response.json([]))
    const cliente = createClient(proyecto, clave, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: crearFetchCrm(proyecto, clave, enviar) },
    })
    const salir = vi.spyOn(cliente.auth, 'signOut')
    const sesion = vi.spyOn(cliente.auth, 'getSession').mockResolvedValue({
      data: { session: null }, error: new AuthApiError('Refresh temporalmente indisponible', 503, 'unexpected_failure'),
    })
    const fallo = await cliente.schema('crm').rpc('registrar_llamada_v4', { p_resultado: 'no_contesto' })
    expect(fallo.error?.code).toBe('CRM_SESSION_UNAVAILABLE')
    expect(enviar).not.toHaveBeenCalled()
    expect(salir).not.toHaveBeenCalled()

    sesion.mockResolvedValue({ data: { session: { access_token: 'jwt-renovado' } as Session }, error: null })
    await cliente.schema('crm').rpc('tareas_pendientes_fn')
    expect(enviar).toHaveBeenCalledTimes(1)
    const [url, opciones] = enviar.mock.calls[0]!
    expect(String(url)).toContain('/tareas_pendientes_fn')
    expect(new Headers(opciones?.headers).get('Authorization')).toBe('Bearer jwt-renovado')

    // Un callback tardío tras SIGNED_OUT tampoco cae al token anónimo.
    sesion.mockResolvedValue({ data: { session: null }, error: null })
    await cliente.schema('crm').rpc('desactivar_push_tasa_fn')
    expect(enviar).toHaveBeenCalledTimes(1)
  })
})
