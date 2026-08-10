import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { DesgloseMonedas } from './desglose-monedas'

describe('DesgloseMonedas', () => {
  it('con TC muestra las dos monedas por separado bajo el total', () => {
    const { container } = render(<DesgloseMonedas pen={100_000} usd={20_000} tc={3.3947} />)

    expect(container.textContent).toContain('S/ 100,000')
    expect(container.textContent).toContain('US$ 20,000')
  })

  it('SIN TC avisa de que el dólar quedó fuera del total', () => {
    const { container } = render(<DesgloseMonedas pen={100_000} usd={20_000} tc={null} />)

    expect(container.textContent).toContain('aparte (sin TC)')
    expect(container.textContent).toContain('US$ 20,000')
  })

  it('sin TC el texto NO va en gris flojo: es cuando más importa leerlo', () => {
    const { container } = render(<DesgloseMonedas pen={100_000} usd={20_000} tc={null} />)
    const linea = container.querySelector('span')

    expect(linea?.className).toContain('text-foreground')
    expect(linea?.className).not.toContain('text-muted-foreground')
  })

  it('sin dólares NO pinta nada (repetir «+ US$ 0» sería ruido)', () => {
    const { container } = render(<DesgloseMonedas pen={100_000} usd={0} tc={3.3947} />)

    expect(container).toBeEmptyDOMElement()
  })

  it('compacto abrevia los miles para las filas densas', () => {
    const { container } = render(<DesgloseMonedas pen={113_000} usd={20_000} tc={3.3947} compacto />)

    expect(container.textContent).toContain('k')
    expect(container.textContent).not.toContain('113,000')
  })

  it('el tono «gerencia» usa los tokens --gi-*, que solo resuelven en ese panel', () => {
    const { container } = render(<DesgloseMonedas pen={1} usd={2} tc={3.39} tono="gerencia" />)

    expect(container.querySelector('span')?.className).toContain('--gi-muted')
  })

  it('se anuncia como desglose para quien usa lector de pantalla', () => {
    render(<DesgloseMonedas pen={100_000} usd={20_000} tc={3.3947} />)

    expect(screen.getByText('Desglose:')).toBeInTheDocument()
  })
})
