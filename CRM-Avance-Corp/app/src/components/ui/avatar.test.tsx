// Tests del Avatar: modo silueta (con género) vs iniciales (sin género), y que
// el peinado por hash del nombre sea determinista y F≠M.
import { describe, expect, it } from 'vitest'
import { render } from '@testing-library/react'
import { Avatar } from './avatar'

const svgHTML = (c: HTMLElement): string | null => c.querySelector('svg')?.innerHTML ?? null

describe('Avatar', () => {
  it('sin prop género → iniciales, sin silueta (equipo/analista)', () => {
    const { container } = render(<Avatar nombre="Juan Pérez" />)
    expect(container.querySelector('svg')).toBeNull()
    expect((container.textContent ?? '').length).toBeGreaterThan(0)
  })

  it('con género → silueta (svg) y sin texto de iniciales', () => {
    const { container } = render(<Avatar nombre="Juan Pérez" genero="M" />)
    expect(container.querySelector('svg')).not.toBeNull()
    expect(container.textContent).toBe('')
  })

  it('género null → iniciales (distinguible cuando no hay dato), sin silueta', () => {
    const { container } = render(<Avatar nombre="Quien sea" genero={null} />)
    expect(container.querySelector('svg')).toBeNull()
    expect((container.textContent ?? '').length).toBeGreaterThan(0)
  })

  it('mismo nombre + mismo género → el MISMO peinado (determinista)', () => {
    const a = render(<Avatar nombre="María López Castro" genero="F" />)
    const b = render(<Avatar nombre="María López Castro" genero="F" />)
    expect(svgHTML(a.container)).toBe(svgHTML(b.container))
  })

  it('el mismo nombre en F y en M da siluetas distintas', () => {
    const f = render(<Avatar nombre="Alex" genero="F" />)
    const m = render(<Avatar nombre="Alex" genero="M" />)
    expect(svgHTML(f.container)).not.toBe(svgHTML(m.container))
  })

  it('relleno: iniciales en blanco sobre el color pleno (fila elegida)', () => {
    const { container } = render(<Avatar nombre="Luz Acuña" color="rgb(29, 78, 216)" relleno />)
    const pastilla = container.firstElementChild as HTMLElement
    expect(pastilla.textContent).toBe('LA')
    expect(pastilla.style.background).toBe('rgb(29, 78, 216)')
    expect(pastilla.style.color).toBe('rgb(255, 255, 255)')
  })
})
