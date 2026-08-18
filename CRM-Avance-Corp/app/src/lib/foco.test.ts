import { afterEach, describe, expect, it } from 'vitest'
import { esFocoHuerfano } from './foco'

afterEach(() => {
  document.body.innerHTML = ''
})

describe('esFocoHuerfano — rescate sí, robo jamás', () => {
  it('el foco en body es huérfano (un disabled lo soltó)', () => {
    expect(document.activeElement).toBe(document.body)
    expect(esFocoHuerfano()).toBe(true)
  })

  it('el foco en el panel de un Dialog (tabindex -1) es huérfano — FocusScope de Radix', () => {
    document.body.innerHTML = '<div role="dialog" tabindex="-1"></div>'
    const panel = document.querySelector<HTMLElement>('[role="dialog"]')!
    panel.focus()
    expect(esFocoHuerfano()).toBe(true)
  })

  it('el foco en un input ajeno es del USUARIO: no se toca', () => {
    document.body.innerHTML = '<input type="tel" />'
    document.querySelector('input')!.focus()
    expect(esFocoHuerfano()).toBe(false)
  })

  it('el foco retenido en el botón PROPIO (deshabilitado en jsdom) es rescatable', () => {
    document.body.innerHTML = '<button type="button">accionar</button>'
    const boton = document.querySelector('button')!
    boton.focus()
    expect(esFocoHuerfano(boton)).toBe(true)
    // …pero un botón AJENO con foco es el usuario en otra cosa.
    expect(esFocoHuerfano(null)).toBe(false)
  })
})
