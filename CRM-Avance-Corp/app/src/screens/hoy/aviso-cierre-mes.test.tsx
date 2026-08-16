import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const dobles = vi.hoisted(() => ({
  cierreEstado: {} as Record<string, unknown>,
}))

vi.mock('@/data/crm-queries', () => ({
  useCierreMesEstado: () => dobles.cierreEstado,
}))

const { AvisoCierreMesPanel } = await import('./aviso-cierre-mes')

/** Payloads VERBATIM del generador de fixtures (los mismos de cierre-de-mes.test.ts). */
function estado(pendiente: Record<string, unknown> | null) {
  return {
    data: {
      hoy: '2026-08-15',
      zona: 'America/Lima',
      version: 1,
      pendiente,
      generado_en: '2026-08-15T20:34:50.843856-05:00',
      mes_en_curso: { mes: '2026-08', cierra_el: '2026-09-10', mes_nombre: 'agosto' },
      ultimo_cerrado: null,
    },
    isError: false,
  }
}

beforeEach(() => {
  dobles.cierreEstado = estado(null)
})

describe('AvisoCierreMesPanel', () => {
  it('sin mes pendiente no pinta nada', () => {
    const { container } = render(<AvisoCierreMesPanel />)
    expect(container).toBeEmptyDOMElement()
  })

  it('en ventana: el aviso, sin rol de alarma', () => {
    dobles.cierreEstado = estado({
      mes: '2026-07',
      estado: 'en_ventana',
      cierra_el: '2026-08-10',
      mes_nombre: 'julio',
      dias_para_cierre: 5,
    })
    render(<AvisoCierreMesPanel />)

    expect(screen.getByText('julio se cierra el 10 ago. 2026')).toBeInTheDocument()
    expect(screen.getByText(/Quedan 5 días de ajuste/)).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('atascado: ALARMA con role="alert" — sin ella un cron roto es invisible', () => {
    dobles.cierreEstado = estado({
      mes: '2026-06',
      estado: 'atascado',
      cierra_el: '2026-07-10',
      mes_nombre: 'junio',
      dias_para_cierre: 0,
    })
    render(<AvisoCierreMesPanel />)

    const alarma = screen.getByRole('alert')
    expect(alarma).toHaveTextContent('El cierre de junio está atascado')
    expect(alarma).toHaveTextContent(/Debió sellarse el 10 jul\. 2026/)
  })

  it('si el estado no responde, no hay banner (advisory, fail-open)', () => {
    dobles.cierreEstado = { data: undefined, isError: true }
    const { container } = render(<AvisoCierreMesPanel />)
    expect(container).toBeEmptyDOMElement()
  })
})
