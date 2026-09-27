// La franja de cifras (diseño de Gestión Diaria, 27/09/2026): cada cifra con su
// etiqueta como par término/definición, el «—» dicho con palabras al lector de
// pantalla, el rojo SOLO cuando se pide y una columna por cifra desde tablet.
import { describe, expect, it } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { FranjaCifras } from './franja-cifras'

describe('FranjaCifras', () => {
  it('pinta cada cifra como término y definición, con su apoyo', () => {
    render(<FranjaCifras etiqueta="Tu día en cifras" cifras={[
      { etiqueta: 'Llamadas', valor: '18', apoyo: 'hoy' },
      { etiqueta: 'Contestaron', valor: '11', apoyo: 'de 18' },
    ]} />)
    const franja = screen.getByRole('group', { name: 'Tu día en cifras' })
    const terminos = within(franja).getAllByRole('term').map((t) => t.textContent)
    expect(terminos).toEqual(['Llamadas', 'Contestaron'])
    expect(within(franja).getAllByRole('definition')[1]).toHaveTextContent('11de 18')
  })

  it('un «—» se OYE como «sin dato», no como silencio ni como cero', () => {
    render(<FranjaCifras etiqueta="Cifras" cifras={[{ etiqueta: 'Contacto', valor: '—', valorAccesible: 'sin dato' }]} />)
    expect(screen.getByText('—')).toHaveAttribute('aria-hidden', 'true')
    expect(screen.getByText('sin dato')).toHaveClass('sr-only')
  })

  it('el tono de alerta usa el rojo de TEXTO y el normal el navy', () => {
    render(<FranjaCifras etiqueta="Cifras" cifras={[
      { etiqueta: 'Necesitan atención', valor: '4', tono: 'alerta' },
      { etiqueta: 'Analistas', valor: '5' },
    ]} />)
    expect(screen.getByText('4')).toHaveClass('text-[var(--destructive-text)]')
    expect(screen.getByText('5')).toHaveClass('text-primary')
  })

  it('una columna por cifra desde tablet; dos en el celular', () => {
    const { container } = render(<FranjaCifras etiqueta="Cifras" cifras={[1, 2, 3, 4, 5].map((n) => ({ etiqueta: `C${n}`, valor: String(n) }))} />)
    const lista = container.querySelector('dl')!
    expect(lista).toHaveClass('grid-cols-2', 'sm:grid-cols-5')
  })

  it('un apoyo que no es texto (un chip) se pinta tal cual', () => {
    render(<FranjaCifras etiqueta="Cifras" cifras={[{ etiqueta: 'Contacto', valor: '69 %', apoyo: <span data-testid="chip">Bien</span> }]} />)
    expect(screen.getByTestId('chip')).toHaveTextContent('Bien')
  })
})

describe('FranjaCifras en línea (supervisor, 27/09/2026)', () => {
  it('pinta número y etiqueta en una línea SIN cambiar el orden término → definición', () => {
    const { container } = render(<FranjaCifras etiqueta="Resumen del equipo" disposicion="en-linea" cifras={[{ etiqueta: 'Analistas', valor: '5' }]} />)
    const celda = container.querySelector('dl > div')!
    expect(celda).toHaveClass('flex-row-reverse')
    expect(celda.firstElementChild?.tagName).toBe('DT')
  })
  it('el tono de aviso usa el ámbar de TEXTO: «Necesitan atención» no es un vencimiento', () => {
    render(<FranjaCifras etiqueta="Cifras" cifras={[{ etiqueta: 'Necesitan atención', valor: '4', tono: 'aviso' }]} />)
    expect(screen.getByText('4')).toHaveClass('text-[var(--warning-text)]')
  })
})
