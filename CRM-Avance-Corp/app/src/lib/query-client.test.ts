import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { instalarLimpiezaCacheAutenticacion, queryClient } from './query-client'
import { AUTH_CLEARED_EVENT } from './seguridad'

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
