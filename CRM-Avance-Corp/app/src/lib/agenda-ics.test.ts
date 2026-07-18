// Tests del enlace de suscripción ICS: forma exacta y sin dobles barras.
import { describe, expect, it } from 'vitest'
import { urlFeedIcs } from './agenda-ics'

describe('urlFeedIcs', () => {
  it('arma la URL de la edge con el token como query', () => {
    expect(urlFeedIcs('https://abc.supabase.co', 'tok-123')).toBe(
      'https://abc.supabase.co/functions/v1/crm-agenda-ics?t=tok-123',
    )
  })

  it('tolera la barra final de la base sin duplicarla', () => {
    expect(urlFeedIcs('https://abc.supabase.co/', 'tok-123')).toBe(
      'https://abc.supabase.co/functions/v1/crm-agenda-ics?t=tok-123',
    )
  })
})
