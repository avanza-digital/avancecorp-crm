import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { SenalMetrica } from './senal-resultado'

// Gerencia lee el avance de citas en bruto (110.5% frente a la meta de 125%):
// la barra llena sigue siendo la meta y la marca del ritmo no se desplaza.
describe('SenalMetrica con la cifra en bruto', () => {
  it('muestra 110.5% frente a 125% sin cambiar el color ni la barra del avance', () => {
    const { container } = render(<SenalMetrica valor={110.5} objetivo={125} ritmo={51.6 * 1.25} etiqueta="Avance de citas" barra />)
    expect(screen.getByText('110.5%')).toBeInTheDocument()
    expect(container.querySelector('[data-senal]')).toHaveAttribute('data-senal', 'ritmo')
    expect(parseFloat(container.querySelector<HTMLElement>('.cm-progreso > span')!.style.width)).toBeCloseTo(88.4, 5)
    expect(parseFloat(container.querySelector<HTMLElement>('.cm-progreso > i')!.style.left)).toBeCloseTo(51.6, 5)
  })

  it('pinta en rojo el avance bajo la mitad del ritmo y llena la barra al pasar la meta', () => {
    const bajo = render(<SenalMetrica valor={27} objetivo={125} ritmo={64.5} etiqueta="Avance de citas" barra />)
    expect(bajo.container.querySelector('[data-senal]')).toHaveAttribute('data-senal', 'prioridad')
    const alto = render(<SenalMetrica valor={140} objetivo={125} ritmo={64.5} etiqueta="Avance de citas" barra />)
    expect(alto.container.querySelector('[data-senal]')).toHaveAttribute('data-senal', 'cumplida')
    expect(alto.container.querySelector<HTMLElement>('.cm-progreso > span')!.style.width).toBe('100%')
  })
})
