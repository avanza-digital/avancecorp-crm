import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { metricasReunionesDemo } from '@/lib/demo-inteligencia-comercial'
import { ReunionesGerenciaPanel } from './reuniones-gerencia'

vi.mock('@/components/gerencia/echart-lazy', () => ({
  GerenciaEChart: ({ ariaLabel }: { ariaLabel: string }) => (
    <div role="img" aria-label={ariaLabel} />
  ),
}))

describe('resumen de reuniones de Gerencia', () => {
  it('no mezcla un error inicial con el mensaje de reuniones vacías', () => {
    render(
      <ReunionesGerenciaPanel
        datos={undefined}
        cargando={false}
        error="No se pudieron cargar las reuniones."
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las citas.')
    expect(screen.queryByText('Aún no hay citas en este período')).not.toBeInTheDocument()
  })

  it('muestra la asistencia real y no el porcentaje de realización', () => {
    render(
      <ReunionesGerenciaPanel
        datos={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        cargando={false}
        error={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    const tarjetaAsistencia = screen.getByText('Asistencia').parentElement
    expect(tarjetaAsistencia).not.toBeNull()
    expect(within(tarjetaAsistencia as HTMLElement).getByText('87.9%')).toBeInTheDocument()
    expect(within(tarjetaAsistencia as HTMLElement).queryByText('79.5%')).not.toBeInTheDocument()
  })
})
