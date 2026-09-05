import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { metricasReunionesDemo } from '@/lib/demo-inteligencia-comercial'
import { ReunionesGerenciaPanel } from './reuniones-gerencia'

const opcionesGraficos = vi.hoisted(() => new Map<string, { series: { data: unknown[] }[] }>())
vi.mock('@/components/gerencia/echart-lazy', () => ({
  GerenciaEChart: ({ ariaLabel, option }: { ariaLabel: string; option: { series: { data: unknown[] }[] } }) => {
    opcionesGraficos.set(ariaLabel, option)
    return <div role="img" aria-label={ariaLabel} />
  },
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

  it('expone cancelaciones de asesor y sistema sin recomponer los totales servidos', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    datos.resumen = { ...datos.resumen, pactadas: 28, realizadas: 5, no_concretadas: 17, no_show: 16, canceladas: 1, canceladas_sistema: 4, pct_realizacion: 20.8, pct_asistencia: 23.8 }
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const sistema = screen.getByText('Canceladas por sistema').closest('[data-gi-kpi]') as HTMLElement
    expect(within(sistema).getByText('4')).toBeInTheDocument()
    expect(screen.getByText('16 no asistieron · canceladas por asesor: 1')).toBeInTheDocument()
    expect(screen.getByText('20.8% de realización')).toBeInTheDocument()
    expect(screen.getByText('23.8%')).toBeInTheDocument()
    expect(screen.getByText(/las pactadas incluyen las canceladas/i)).toBeInTheDocument()
  })

  it('muestra el porcentaje servido por modalidad sin la fracción de vencidas brutas', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    const modalidad = datos.modalidades.find((fila) => fila.modalidad === 'virtual')!
    Object.assign(modalidad, { realizadas: 4, debieron_ocurrir: 21, pct_realizacion: 23.5 })
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const virtual = screen.getByText('Virtual').closest('section') as HTMLElement
    expect(within(virtual).getByText('23.5%')).toBeInTheDocument()
    expect(within(virtual).getByText('4 realizadas')).toBeInTheDocument()
    expect(within(virtual).queryByText('4 de 21')).not.toBeInTheDocument()
    expect(screen.getByText(/Realización: realizadas sobre citas vencidas/)).toBeInTheDocument()
  })

  it('conserva null en el gráfico y distingue ausencia de base de cero real', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    datos.origenes = [
      { ...datos.origenes[0]!, origen: 'Sin muestra', conversion_contrato_pct: null },
      { ...datos.origenes[0]!, origen: 'Cero real', conversion_contrato_pct: 0 },
    ]
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    expect(opcionesGraficos.get('Conversión de citas a clientes por origen')?.series[0]?.data).toEqual([0, null])
    expect(screen.getByText('Sin muestra: — (sin base para calcular)')).toBeInTheDocument()
    expect(screen.queryByText('Cero real: — (sin base para calcular)')).not.toBeInTheDocument()
  })
})
