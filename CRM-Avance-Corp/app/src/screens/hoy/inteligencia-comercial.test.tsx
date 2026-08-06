import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  metricasConversionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { money } from '@/lib/format'
import { InteligenciaComercialPanel } from './inteligencia-comercial'

vi.mock('@/components/gerencia/echart-lazy', () => ({
  GerenciaEChart: ({
    ariaLabel,
    option,
  }: {
    ariaLabel: string
    option: {
      xAxis?: { data?: unknown[] }
      series?: Array<{ data?: unknown[] }>
    }
  }) => (
    <div
      role="img"
      aria-label={ariaLabel}
      data-x-axis={JSON.stringify(option.xAxis?.data ?? [])}
      data-series={JSON.stringify(option.series?.[0]?.data ?? [])}
    />
  ),
}))

describe('detalle de conversión por vendedor', () => {
  it('no mezcla un error inicial con el mensaje de datos vacíos', () => {
    render(
      <InteligenciaComercialPanel
        datos={undefined}
        equipo={conversionEquipoDemo()}
        metaConversion={15}
        metasVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error="No se pudieron cargar las conversiones."
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las conversiones.')
    expect(screen.queryByText('Aún no hay leads para analizar')).not.toBeInTheDocument()
  })

  it('abre una ficha compacta y muestra el capital PEN y USD por separado', () => {
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        metaConversion={0}
        metasVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))

    const detalle = screen.getByRole('dialog', { name: 'Ana Torres' })
    expect(detalle).toHaveClass('max-w-[560px]')
    expect(detalle).not.toHaveClass('max-w-[780px]')

    const contenido = within(detalle)
    expect(contenido.getByText('Capital confirmado PEN')).toBeInTheDocument()
    expect(contenido.getByText('Capital confirmado USD')).toBeInTheDocument()
    expect(contenido.getByText(money(360_000, 'PEN'))).toBeInTheDocument()
    expect(contenido.getByText(money(20_000, 'USD'))).toBeInTheDocument()
    expect(contenido.getByText('Meta de capital en PEN')).toBeInTheDocument()
    expect(contenido.getByText(/de 15%/)).toBeInTheDocument()

    fireEvent.click(contenido.getByRole('button', { name: 'Cerrar detalle de vendedor' }))
    expect(screen.queryByRole('dialog', { name: 'Ana Torres' })).not.toBeInTheDocument()
  })

  it('no presenta avance contra la meta mensual para un rango histórico', () => {
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-07-01', '2026-07-31')}
        equipo={conversionEquipoDemo()}
        metaConversion={0}
        metasVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('No comparable')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))

    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getAllByText('La meta mensual de agosto 2026 no es comparable con el rango aplicado.').length).toBeGreaterThan(0)
    expect(detalle.queryAllByRole('progressbar')).toHaveLength(0)
    expect(detalle.queryByText(/de 15%/)).not.toBeInTheDocument()
  })

  it('grafica las semanas históricas de la RPC y conserva la ausencia de muestra como null', () => {
    const datos = metricasConversionesDemo('2026-06-03', '2026-06-16')
    datos.responsables = [{
      ...datos.responsables![0]!,
      leads: 2,
      clientes: 1,
      conversion_pct: 50,
      tendencia_semanal: [
        { semana: 1, desde: '2026-06-03', hasta: '2026-06-09', leads: 0, clientes: 0, conversion_pct: null },
        { semana: 2, desde: '2026-06-10', hasta: '2026-06-16', leads: 2, clientes: 1, conversion_pct: 50 },
      ],
    }]

    render(
      <InteligenciaComercialPanel
        datos={datos}
        equipo={[conversionEquipoDemo()[0]!]}
        metaConversion={15}
        metasVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    const evolucion = screen.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' })
    expect(JSON.parse(evolucion.getAttribute('data-x-axis') ?? '[]')).toEqual([
      '2026-06-03 – 2026-06-09',
      '2026-06-10 – 2026-06-16',
    ])
    expect(JSON.parse(evolucion.getAttribute('data-series') ?? '[]')).toEqual([null, 50])

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const tendencia = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
      .getByRole('img', { name: 'Tendencia semanal de conversión de Ana Torres' })
    expect(JSON.parse(tendencia.getAttribute('data-x-axis') ?? '[]')).toEqual([
      '2026-06-03 – 2026-06-09',
      '2026-06-10 – 2026-06-16',
    ])
    expect(JSON.parse(tendencia.getAttribute('data-series') ?? '[]')).toEqual([null, 50])
  })

  it('no convierte en cero el detalle ausente de una RPC antigua', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete datos.responsables

    render(
      <InteligenciaComercialPanel
        datos={datos}
        equipo={[conversionEquipoDemo()[0]!]}
        metaConversion={15}
        metasVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Tendencia no disponible')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))

    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getByText('No disponible')).toBeInTheDocument()
    expect(detalle.getAllByText('—').length).toBeGreaterThan(0)
    expect(detalle.queryByText(money(360_000, 'PEN'))).not.toBeInTheDocument()
    expect(detalle.getByText('Tendencia no disponible')).toBeInTheDocument()
  })
})
