import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  PeriodoGerenciaProvider,
} from './periodo-context'
import {
  periodoInicialGerencia,
  periodoMesCalendario,
  semanticaMetaMensual,
  validarPeriodoGerencia,
} from './periodo'
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

describe('periodo mensual de rankings', () => {
  const ahora = new Date('2026-09-02T15:00:00Z').getTime()

  it('normaliza un mes histórico a todo su calendario', () => {
    expect(periodoMesCalendario('2026-08', ahora)).toEqual({
      desde: '2026-08-01',
      hasta: '2026-08-31',
    })
  })

  it('corta el mes vigente al día de hoy en Lima', () => {
    expect(periodoMesCalendario('2026-09', ahora)).toEqual({
      desde: '2026-09-01',
      hasta: '2026-09-02',
    })
  })

  it('respeta el último día real de un febrero bisiesto', () => {
    expect(periodoMesCalendario('2024-02', ahora)).toEqual({
      desde: '2024-02-01',
      hasta: '2024-02-29',
    })
  })

  it('rotula y compara la meta contra el mes elegido por el ranking', () => {
    const agosto = periodoMesCalendario('2026-08', ahora)
    expect(semanticaMetaMensual(agosto, ahora, agosto)).toEqual({
      etiqueta: 'agosto 2026',
      comparable: true,
    })
  })

  it('conserva por defecto la protección del store contra rangos libres', () => {
    expect(semanticaMetaMensual({ desde: '2026-08-01', hasta: '2026-08-31' }, ahora))
      .toEqual({ etiqueta: 'setiembre 2026', comparable: false })
  })
})

describe('PeriodoGerenciaProvider', () => {
  it('sincroniza el mes al volver a una PWA suspendida, conservando un período histórico manual', () => {
    vi.setSystemTime(ANTES_DE_MEDIANOCHE_LIMA)
    montarProveedor()
    vi.setSystemTime(new Date('2026-08-02T15:00:00Z'))
    fireEvent(window, new Event('focus'))
    expect(screen.getByLabelText('Desde aplicado')).toHaveTextContent('2026-08-01')
    expect(screen.getByLabelText('Día de Lima')).toHaveTextContent('2026-08-02')
    fireEvent.click(screen.getByRole('button', { name: 'Aplicar rango personalizado' }))
    vi.setSystemTime(new Date('2026-09-01T15:00:00Z'))
    fireEvent(document, new Event('visibilitychange'))
    expect(screen.getByLabelText('Desde aplicado')).toHaveTextContent('2026-06-01')
    expect(screen.getByLabelText('Día de Lima')).toHaveTextContent('2026-09-01')
  })
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
