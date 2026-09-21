import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import { DetalleAnalista } from './detalle-analista'

const fila = () => filaEquipoPrueba({ marcador: {
  ...filaEquipoPrueba().marcador, llamadas: 6, contestadas: 3, utiles: 6,
  por_hora: [{ hora: 7, llamadas: 1, contestadas: 1 }, { hora: 9, llamadas: 3, contestadas: 2 }, { hora: 23, llamadas: 2, contestadas: 0 }],
} })

describe('Detalle de analista — F4.2', () => {
  it('expone conteos horarios y las llamadas fuera de 08–20 sin recalcular desde el store', () => {
    const abrir = vi.fn()
    render(<DetalleAnalista fila={fila()} dia="2026-09-21" abrirLlamadas={abrir} />)
    const lista = screen.getByRole('list', { name: 'Llamadas por hora de ANA PÉREZ' })
    expect(within(lista).getAllByRole('listitem')).toHaveLength(13)
    expect(within(lista).getByText('De 9:00 a 9:59: 3 llamadas, 2 contestadas').closest('li')).toHaveTextContent('3 / 2')
    expect(within(lista).getByText('De 8:00 a 8:59: 0 llamadas, 0 contestadas')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Llamadas por hora de ANA PÉREZ' })).toHaveAttribute('tabindex', '0')
    expect(screen.getByText(/Fuera de la franja/)).toHaveTextContent('07 h: 1 llamada / 1 contestada; 23 h: 2 llamadas / 0 contestadas')
    expect(screen.getByText(/2026-09-21 · Hora de Lima/)).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Ver llamadas del día de ANA PÉREZ' }))
    expect(abrir).toHaveBeenCalledOnce()
  })

  it('sin llamadas no atribuye ausencia ni oculta el acceso al registro', () => {
    render(<DetalleAnalista fila={filaEquipoPrueba()} dia="2026-09-21" abrirLlamadas={vi.fn()} />)
    expect(screen.getByText(/No hay llamadas registradas/)).toHaveTextContent('no indica ausencia')
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Ver llamadas/ })).toBeEnabled()
  })

  it('todas las llamadas fuera de franja conservan escala finita y sus conteos', () => {
    const f = fila()
    f.marcador.por_hora = [{ hora: 7, llamadas: 6, contestadas: 3 }]
    const { container } = render(<DetalleAnalista fila={f} dia="2026-09-21" abrirLlamadas={vi.fn()} />)
    expect(screen.getByText(/Fuera de la franja/)).toHaveTextContent('07 h: 6 llamadas / 3 contestadas')
    expect(container.innerHTML).not.toContain('NaN')
    expect(container.querySelectorAll('[style="height: 0%;"]')).toHaveLength(26)
  })

  it('explica la diferencia histórica entre contestadas por hora y contacto útil sin ocultar el horario', () => {
    const f = fila()
    f.marcador.utiles = 5
    f.marcador.por_hora = [{ hora: 9, llamadas: 6, contestadas: 4 }]
    render(<DetalleAnalista fila={f} dia="2026-09-21" abrirLlamadas={vi.fn()} />)
    expect(screen.getByRole('list')).toBeInTheDocument()
    expect(screen.getByText(/Las contestadas por hora incluyen registros/)).toHaveTextContent('contacto útil excluye')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it.each([
    [],
    [{ hora: 9, llamadas: 6, contestadas: 2 }],
    [{ hora: 9, llamadas: 6, contestadas: 4 }],
    [{ hora: 9, llamadas: 3, contestadas: 1 }, { hora: 9, llamadas: 3, contestadas: 2 }],
    [{ hora: 24, llamadas: 6, contestadas: 3 }],
    [{ hora: -1, llamadas: 6, contestadas: 3 }],
    [{ hora: 9.5, llamadas: 6, contestadas: 3 }],
    [{ hora: 9, llamadas: 2, contestadas: 3 }, { hora: 10, llamadas: 4, contestadas: 0 }],
  ].map((horas) => ({ horas })))('un desglose inválido no se transforma en ceros ($horas)', ({ horas }) => {
    const f = fila()
    f.marcador.por_hora = horas
    render(<DetalleAnalista fila={f} dia="2026-09-21" abrirLlamadas={vi.fn()} />)
    expect(screen.getByRole('status')).toHaveTextContent('No se pudo confirmar el desglose')
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
  })
})
