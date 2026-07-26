import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { instalarLimpiezaCacheAutenticacion, queryClient } from './query-client'
import { AUTH_CLEARED_EVENT } from './seguridad'

describe('modo de red', () => {
  // Con el default ('online') TanStack ni lanza la petición sin conexión: la
  // query se queda `pending`/`paused` para siempre y la pantalla pinta un
  // skeleton eterno. El CRM prefiere intentar y, si falla, decirlo.
  it('las lecturas SALEN aunque el navegador se declare offline', () => {
    expect(queryClient.getDefaultOptions().queries?.networkMode).toBe('offlineFirst')
  })

  it('las escrituras tampoco se pausan en silencio (parecería que guardó)', () => {
    expect(queryClient.getDefaultOptions().mutations?.networkMode).toBe('offlineFirst')
  })

  it('al volver la red se refresca solo', () => {
    expect(queryClient.getDefaultOptions().queries?.refetchOnReconnect).toBe(true)
  })
})

describe('caché autenticada', () => {
  let desinstalar: () => void = () => undefined

  beforeEach(() => queryClient.clear())
  afterEach(() => {
    desinstalar()
    queryClient.clear()
  })

  it('elimina inmediatamente los datos cuando Auth pierde o cambia acceso', () => {
    queryClient.setQueryData(['crm', 'lead', 'sensible'], { nombre: 'DATO PRIVADO' })
    desinstalar = instalarLimpiezaCacheAutenticacion()

    window.dispatchEvent(new Event(AUTH_CLEARED_EVENT))

    expect(queryClient.getQueryData(['crm', 'lead', 'sensible'])).toBeUndefined()
  })
})
