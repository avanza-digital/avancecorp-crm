import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  PeriodoGerenciaProvider,
} from './periodo-context'
import { periodoInicialGerencia, validarPeriodoGerencia } from './periodo'
import { usePeriodoGerencia } from './use-periodo-gerencia'

const ANTES_DE_MEDIANOCHE_LIMA = new Date('2026-08-01T04:59:59Z')

function ConsumidorPeriodo(): React.JSX.Element {
  const { periodo, setPeriodo, diaLima } = usePeriodoGerencia()
  return (
    <>
      <output aria-label="Desde aplicado">{periodo.desde}</output>
      <output aria-label="Hasta aplicado">{periodo.hasta}</output>
      <output aria-label="Día de Lima">{diaLima}</output>
      <button
        type="button"
        onClick={() => setPeriodo({ desde: '2026-06-01', hasta: '2026-06-30' })}
      >
        Aplicar rango personalizado
      </button>
      <button type="button" onClick={() => setPeriodo(periodoInicialGerencia())}>
        Volver al período actual
      </button>
    </>
  )
}

function montarProveedor(): void {
  render(
    <PeriodoGerenciaProvider>
      <ConsumidorPeriodo />
    </PeriodoGerenciaProvider>,
  )
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('validarPeriodoGerencia', () => {
  const ahora = new Date('2026-07-15T15:00:00Z').getTime()

  it('acepta hoy en Lima y exactamente 365 días de diferencia', () => {
    expect(validarPeriodoGerencia(
      { desde: '2025-07-15', hasta: '2026-07-15' },
      ahora,
    )).toEqual({ valido: true })
  })

  it.each([
    {
      nombre: 'fechas vacías',
      periodo: { desde: '', hasta: '2026-07-15' },
      codigo: 'fechas_requeridas',
    },
    {
      nombre: 'fecha de calendario inválida',
      periodo: { desde: '2026-02-30', hasta: '2026-07-15' },
      codigo: 'fecha_invalida',
    },
    {
      nombre: 'desde posterior a hasta',
      periodo: { desde: '2026-07-15', hasta: '2026-07-14' },
      codigo: 'orden_invalido',
    },
    {
      nombre: 'hasta futuro en Lima',
      periodo: { desde: '2026-07-01', hasta: '2026-07-16' },
      codigo: 'fecha_futura',
    },
    {
      nombre: 'más de 365 días de diferencia',
      periodo: { desde: '2025-07-14', hasta: '2026-07-15' },
      codigo: 'rango_demasiado_amplio',
    },
  ])('rechaza $nombre', ({ periodo, codigo }) => {
    expect(validarPeriodoGerencia(periodo, ahora)).toMatchObject({ valido: false, codigo })
  })

  it('determina hoy con la fecha de Lima, no con la fecha UTC', () => {
    // UTC ya marca 16 de julio, pero en Lima todavía es 15 de julio.
    const antesDeMedianoche = new Date('2026-07-16T04:59:59Z').getTime()

    expect(validarPeriodoGerencia(
      { desde: '2026-07-01', hasta: '2026-07-16' },
      antesDeMedianoche,
    )).toMatchObject({ valido: false, codigo: 'fecha_futura' })
  })
})

describe('PeriodoGerenciaProvider', () => {
  it('actualiza automáticamente el período por defecto al cruzar medianoche de Lima', () => {
    vi.setSystemTime(ANTES_DE_MEDIANOCHE_LIMA)
    montarProveedor()

    expect(screen.getByLabelText('Desde aplicado')).toHaveTextContent('2026-07-01')
    expect(screen.getByLabelText('Hasta aplicado')).toHaveTextContent('2026-07-31')

    act(() => vi.advanceTimersByTime(1_000))

    expect(screen.getByLabelText('Desde aplicado')).toHaveTextContent('2026-08-01')
    expect(screen.getByLabelText('Hasta aplicado')).toHaveTextContent('2026-08-01')
  })

  it('no pisa un rango personalizado cuando cambia el día en Lima', () => {
    vi.setSystemTime(ANTES_DE_MEDIANOCHE_LIMA)
    montarProveedor()
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar rango personalizado' }))

    act(() => vi.advanceTimersByTime(1_000))

    expect(screen.getByLabelText('Desde aplicado')).toHaveTextContent('2026-06-01')
    expect(screen.getByLabelText('Hasta aplicado')).toHaveTextContent('2026-06-30')
    expect(screen.getByLabelText('Día de Lima')).toHaveTextContent('2026-08-01')
  })

  it('reanuda la actualización automática al volver explícitamente al período actual', () => {
    vi.setSystemTime(ANTES_DE_MEDIANOCHE_LIMA)
    montarProveedor()
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar rango personalizado' }))
    fireEvent.click(screen.getByRole('button', { name: 'Volver al período actual' }))

    act(() => vi.advanceTimersByTime(1_000))

    expect(screen.getByLabelText('Desde aplicado')).toHaveTextContent('2026-08-01')
    expect(screen.getByLabelText('Hasta aplicado')).toHaveTextContent('2026-08-01')
  })
})
