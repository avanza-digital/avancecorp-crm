// Llamadas por hora (08–20 Lima): el dibujo es decorativo y el dato viaja en
// una lista para el lector de pantalla; las horas sin llamadas no se leen; lo
// que cae fuera de la franja se DICE; y un día sin llamadas no dibuja nada.
import { describe, expect, it } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { BarrasPorHora } from './barras-por-hora'

describe('BarrasPorHora', () => {
  it('el lector oye solo las horas con llamadas, con sus contestadas', () => {
    render(<BarrasPorHora titulo="Llamadas por hora" porHora={[{ hora: 9, llamadas: 4, contestadas: 2 }, { hora: 12, llamadas: 1, contestadas: 1 }]} />)
    const lista = screen.getByRole('list', { name: 'Llamadas por hora' })
    expect(within(lista).getAllByRole('listitem').map((i) => i.textContent)).toEqual([
      '9:00 — 4 llamadas, 2 contestadas',
      '12:00 — 1 llamada, 1 contestada',
    ])
  })

  it('dibuja las 13 horas de la franja, con leyenda y sin texto fuera de franja si no lo hay', () => {
    const { container } = render(<BarrasPorHora titulo="Llamadas por hora" apoyo="Última llamada 16:05" porHora={[{ hora: 9, llamadas: 4, contestadas: 2 }]} />)
    const dibujo = container.querySelector('[aria-hidden="true"]')!
    expect(dibujo.children).toHaveLength(13)
    expect(screen.getByText('Contestaron')).toBeInTheDocument()
    expect(screen.getByText('No contestaron')).toBeInTheDocument()
    expect(screen.getByText('Última llamada 16:05')).toBeInTheDocument()
    expect(screen.queryByText(/fuera de la franja/)).not.toBeInTheDocument()
  })

  it('lo que cae fuera de 08–20 se dice, no se esconde', () => {
    render(<BarrasPorHora titulo="Llamadas por hora" porHora={[{ hora: 9, llamadas: 1, contestadas: 0 }, { hora: 21, llamadas: 2, contestadas: 1 }]} />)
    expect(screen.getByText('2 llamadas fuera de la franja 08–20.')).toBeInTheDocument()
  })

  it('sin llamadas no dibuja barras vacías: lo dice', () => {
    const { container } = render(<BarrasPorHora titulo="Llamadas por hora" porHora={[]} />)
    expect(screen.getByText('Todavía no hay llamadas hoy.')).toBeInTheDocument()
    expect(container.querySelector('[aria-hidden="true"]')).toBeNull()
  })

  it('si solo hubo llamadas fuera de la franja, no dice «todavía no hay»', () => {
    render(<BarrasPorHora titulo="Llamadas por hora" porHora={[{ hora: 7, llamadas: 1, contestadas: 1 }]} />)
    expect(screen.getByText('Sin llamadas entre las 08 y las 20; 1 llamada fuera de esa franja.')).toBeInTheDocument()
  })
})
