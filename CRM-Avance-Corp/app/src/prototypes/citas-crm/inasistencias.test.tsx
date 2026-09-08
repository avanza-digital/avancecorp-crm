import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, screen, within, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PropuestaCitasCRM } from './propuesta'

afterEach(cleanup)

describe('consulta de depósitos desde las inasistencias', () => {
  it('muestra conversión y montos, abre el detalle y conserva el seguimiento existente', async () => {
    const usuario = userEvent.setup()
    render(<PropuestaCitasCRM />)
    await usuario.click(screen.getByRole('tab', { name: 'Resultados' }))
    const seguimiento = screen.getByRole('region', { name: 'Seguimiento de inasistencias' })
    const conversion = within(seguimiento).getByRole('region', { name: 'Conversión de inasistencias a depósito' })
    expect(conversion).toHaveTextContent('2 de 4 leads que faltaron depositaron (50%)')
    expect(conversion).toHaveTextContent('S/ 35,000')
    expect(conversion).toHaveTextContent('US$ 5,000')
    await usuario.click(within(seguimiento).getByRole('button', { name: /Leads que depositaron/ }))
    const depositantes = within(seguimiento).getByRole('list', { name: 'Leads que depositaron' })
    expect(within(depositantes).getAllByRole('listitem')).toHaveLength(2)
    const abrir = within(depositantes).getByRole('button', { name: 'Ver depósitos de Andrea Peralta' })
    await usuario.click(abrir)
    const detalle = screen.getByRole('dialog', { name: 'Depósitos de Andrea Peralta' })
    expect(detalle).toHaveTextContent('DEP-001')
    expect(detalle).toHaveTextContent('04 set. 2026')
    expect(detalle).toHaveTextContent('10:05 Lima')
    await usuario.keyboard('{Escape}')
    await waitFor(() => expect(abrir).toHaveFocus())
    await usuario.click(within(seguimiento).getByRole('button', { name: 'Sin nueva cita 1' }))
    expect(within(seguimiento).getByRole('list', { name: 'Detalle de inasistencias' })).toHaveTextContent('Esteban Duarte')
    await usuario.click(within(seguimiento).getByRole('button', { name: /Se reprogramaron/ }))
    expect(within(within(seguimiento).getByRole('list', { name: 'Detalle de inasistencias' })).getAllByRole('listitem')).toHaveLength(3)
  })

  it('aplica asesor y semana a la cohorte y distingue cero depósitos de ninguna inasistencia', async () => {
    const usuario = userEvent.setup()
    render(<PropuestaCitasCRM />)
    await usuario.click(screen.getByRole('tab', { name: 'Resultados' }))
    await usuario.click(screen.getByRole('button', { name: /Leads que depositaron/ }))
    await usuario.selectOptions(screen.getByLabelText('Analista'), 'valeria')
    expect(screen.getByRole('region', { name: 'Conversión de inasistencias a depósito' })).toHaveTextContent('0 de 1 leads que faltaron depositaron (0%)')
    expect(screen.getByText('Ningún lead de estas inasistencias tiene un depósito confirmado posterior.')).toBeInTheDocument()
    await usuario.selectOptions(screen.getByLabelText('Analista'), 'diego')
    expect(screen.getByRole('region', { name: 'Conversión de inasistencias a depósito' })).toHaveTextContent('1 de 1 leads que faltaron depositaron (100%)')
    expect(screen.getByRole('list', { name: 'Leads que depositaron' })).toHaveTextContent('Esteban Duarte')
    await usuario.selectOptions(screen.getByLabelText('Semana'), '2')
    expect(screen.getByText(/No hay inasistencias con estos filtros/)).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Conversión de inasistencias a depósito' })).not.toBeInTheDocument()
  })
})
