import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, within, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PropuestaCitasCRM } from './propuesta'
import { CITAS_CRM, seguimientoInasistencias } from './datos'
import { depositosDeInasistencias } from './depositos'
import { FichaRecorrido } from './ficha-recorrido'

afterEach(() => { cleanup(); vi.unstubAllGlobals() })
const tabla = () => screen.getByRole('table', { name: 'Resultados por analista de las citas filtradas' })

describe('tablero horizontal elegido para Citas', () => {
  it('prioriza el flujo, conserva la base de metas al elegir una etapa y permite recuperar columnas opcionales', async () => {
    const usuario = userEvent.setup()
    render(<PropuestaCitasCRM />)
    expect(screen.getByRole('tab', { name: 'Resultados' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.queryByRole('region', { name: 'Resumen de las citas filtradas' })).not.toBeInTheDocument()
    const total = within(tabla()).getByRole('row', { name: /Total de la consulta/ })
    expect(total).toHaveTextContent('40 / 26')
    expect(total).toHaveTextContent('51.3%')
    expect(total).toHaveTextContent('3 de 26')
    await usuario.click(screen.getByRole('button', { name: 'Depositó 1' }))
    expect(within(screen.getByRole('table', { name: 'Personas del flujo de recuperación' })).getAllByRole('row')).toHaveLength(2)
    expect(total).toHaveTextContent('40 / 26')
    await usuario.click(screen.getByText('Columnas', { exact: true }))
    await usuario.click(screen.getByLabelText('Leads con 2+ citas'))
    await usuario.click(screen.getByLabelText('Realizadas'))
    expect(within(tabla()).getByRole('columnheader', { name: 'Leads con 2+ citas' })).toBeInTheDocument()
    expect(within(total).getAllByRole('cell').map(celda => celda.textContent)).toEqual(['40 / 26', '1.54', '51.3%', '3 de 26', '10', '12', '—'])
    await usuario.click(screen.getByRole('button', { name: 'Cómo se calculan las métricas' }))
    expect(screen.getByRole('dialog')).toHaveTextContent('15 citas entre 4 leads')
  })

  it('mantiene la consulta operable con la ficha no modal y la cierra al cambiar su base sin robar el foco', async () => {
    vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: true, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
    const usuario = userEvent.setup()
    render(<PropuestaCitasCRM />)
    await usuario.click(screen.getByRole('button', { name: 'Ver recorrido de Andrea Peralta' }))
    const ficha = screen.getByRole('dialog', { name: 'Andrea Peralta' })
    expect(document.querySelector('[data-slot="sheet-overlay"]')).not.toBeInTheDocument()
    expect(ficha).toHaveTextContent('2 citas · 66.7% de la meta')
    expect(ficha).toHaveTextContent('10:00')
    expect(ficha).toHaveTextContent('10:05 Lima')
    await usuario.click(screen.getByRole('button', { name: 'Mónica Silva' }))
    expect(screen.getByRole('dialog', { name: 'Mónica Silva' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Mónica Silva' })).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByText('Mostrando recorrido de Mónica Silva')).toHaveAttribute('role', 'status')
    expect(screen.getByLabelText('Analista')).toBeVisible()
    await usuario.selectOptions(screen.getByLabelText('Analista'), 'valeria')
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(screen.getByLabelText('Analista')).toHaveFocus()
    expect(within(tabla()).getByRole('row', { name: /Total de la consulta/ })).toHaveTextContent('6 / 4')
    expect(screen.getByRole('region', { name: 'Conversión de inasistencias a depósito' })).toHaveTextContent('0% a depósito0 de 1 leads')
  })

  it.each([true, false])('entrega el foco a la cita vinculada desde un inspector amplio=%s', async amplia => {
    vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: amplia, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
    const usuario = userEvent.setup()
    render(<PropuestaCitasCRM />)
    await usuario.click(screen.getByRole('button', { name: 'Ver recorrido de Andrea Peralta' }))
    expect(Boolean(document.querySelector('[data-slot="sheet-overlay"]'))).toBe(!amplia)
    await usuario.click(screen.getByRole('button', { name: 'Ver cita vinculada' }))
    await screen.findByRole('button', { name: 'Ubicar en agenda' })
    // La ficha de cita conserva el modo modal predeterminado del CRM.
    expect(document.querySelector('[data-slot="sheet-overlay"]')).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('dialog').contains(document.activeElement)).toBe(true))
    await usuario.keyboard('{Tab}')
    expect(screen.getByRole('dialog').contains(document.activeElement)).toBe(true)
  })

  it('no muestra asistencia en el recorrido cuando el registro es anterior a la reprogramación', () => {
    const original = CITAS_CRM[30]!
    const nueva = { ...CITAS_CRM[18]!, asistioEn: '2026-09-01T16:00:00-05:00' }
    const citas = [original, nueva]
    expect(depositosDeInasistencias(citas, [], undefined, citas).recuperadas).toHaveLength(0)
    render(<FichaRecorrido fila={seguimientoInasistencias(citas, citas)[0]!} citas={citas} depositos={[]} onCerrar={() => {}} onCita={() => {}} />)
    expect(screen.queryByRole('heading', { name: 'Asistió' })).not.toBeInTheDocument()
    expect(screen.getByRole('dialog')).toHaveTextContent('Sin asistencia registrada al corte')
  })
})
