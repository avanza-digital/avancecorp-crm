import { afterEach, expect, it, vi } from 'vitest'

afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
  vi.resetModules()
})

it('el cliente compartido real impide RPC anónimas con la configuración normalizada', async () => {
  vi.resetModules()
  vi.stubEnv('VITE_SUPABASE_URL', ' https://cliente-compartido.supabase.co/ ')
  vi.stubEnv('VITE_SUPABASE_ANON_KEY', ' sb_publishable_fixture_compartido ')
  const enviar = vi.fn<typeof fetch>()
  vi.stubGlobal('fetch', enviar)
  const { sb } = await import('./supabase')
  expect(sb).not.toBeNull()
  if (!sb) throw new Error('El cliente compartido debe estar configurado')
  sb.auth.stopAutoRefresh()
  vi.spyOn(sb.auth, 'getSession').mockResolvedValue({ data: { session: null }, error: null })
  const respuesta = await sb.schema('crm').rpc('cola_accion_v3_fn')
  expect(respuesta.error?.code).toBe('CRM_SESSION_UNAVAILABLE')
  expect(enviar).not.toHaveBeenCalled()
})
