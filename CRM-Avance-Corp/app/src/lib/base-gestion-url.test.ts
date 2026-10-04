// Estado de la vista del supervisor (F4) en la URL: `?rescate_vista=gestion&rescate_analista=…`, con el patrón de la
// carpeta del Centro de rescate. Lo que no se reconoce no se usa; «Descartes del mes» no deja parámetros.
import { describe, expect, it } from 'vitest'
import { estadoSupervisionDe, hrefConEstadoSupervision } from './base-gestion-url'

describe('estado de la vista del supervisor en la URL', () => {
  const ANA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  it('sin parámetros: «Descartes del mes»', () => {
    expect(estadoSupervisionDe('https://crm.test/#/rescate')).toEqual({ vista: 'descartes', analista: null })
  })
  it('lee la pestaña y un analista válido (uuid, demo o la bandeja); lo demás no se usa', () => {
    expect(estadoSupervisionDe(`https://crm.test/?rescate_vista=gestion&rescate_analista=${ANA}#/rescate`)).toEqual({ vista: 'gestion', analista: ANA })
    expect(estadoSupervisionDe('https://crm.test/?rescate_vista=gestion&rescate_analista=d-v1#/rescate').analista).toBe('d-v1')
    expect(estadoSupervisionDe('https://crm.test/?rescate_vista=gestion&rescate_analista=sin-analista#/rescate').analista).toBe('sin-analista')
    expect(estadoSupervisionDe('https://crm.test/?rescate_vista=gestion&rescate_analista=x%27or#/rescate').analista).toBeNull()
    // El analista sin la pestaña de gestión no se usa.
    expect(estadoSupervisionDe(`https://crm.test/?rescate_analista=${ANA}#/rescate`)).toEqual({ vista: 'descartes', analista: null })
  })
  it('escribe solo lo suyo: conserva el hash y los demás parámetros; «Descartes» no deja nada', () => {
    const href = 'https://crm.test/?otro=1#/rescate'
    expect(hrefConEstadoSupervision(href, { vista: 'gestion', analista: ANA })).toBe(`https://crm.test/?otro=1&rescate_vista=gestion&rescate_analista=${ANA}#/rescate`)
    expect(hrefConEstadoSupervision(`https://crm.test/?otro=1&rescate_vista=gestion&rescate_analista=${ANA}#/rescate`, { vista: 'descartes', analista: ANA })).toBe(href)
  })
})
