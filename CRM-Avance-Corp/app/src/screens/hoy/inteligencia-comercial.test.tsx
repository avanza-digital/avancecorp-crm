import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  conversionMensualInteligenciaDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
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

// Instante fijo a mitad de mes: la procedencia nombra meses reales de Lima y
// un Date.now() haría rotar el texto esperado cada mes.
const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

describe('detalle de conversión por vendedor', () => {
  it('no mezcla un error inicial con el mensaje de datos vacíos', () => {
    render(
      <InteligenciaComercialPanel
        datos={undefined}
        conversionMensual={null}
        equipo={conversionEquipoDemo()}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
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
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
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
    // El número grande es LA conversión del MES (4.15÷12), no la del rango.
    expect(contenido.getByText('conversión del mes')).toBeInTheDocument()
    expect(contenido.getByText('34.6%')).toBeInTheDocument()
    expect(contenido.getByText('Recibidos 12 · cierres 5')).toBeInTheDocument()
    // Procedencia y referidos con la letra corregida del plan.
    expect(contenido.getByText('de agosto 4, de julio 1')).toBeInTheDocument()
    expect(contenido.getByText(/2 registrados · 1 cerrados/)).toBeInTheDocument()
    expect(contenido.getByText('Los referidos no entran al divisor: cada cierre aporta 0.15 al numerador.')).toBeInTheDocument()
    expect(contenido.getByText('Capital confirmado PEN')).toBeInTheDocument()
    expect(contenido.getByText('Capital confirmado USD')).toBeInTheDocument()
    expect(contenido.getByText(money(360_000, 'PEN'))).toBeInTheDocument()
    expect(contenido.getByText(money(20_000, 'USD'))).toBeInTheDocument()
    expect(contenido.getByText('Capital en PEN')).toBeInTheDocument()
    expect(contenido.getByText(/de 25%/)).toBeInTheDocument()

    fireEvent.click(contenido.getByRole('button', { name: 'Cerrar detalle de vendedor' }))
    expect(screen.queryByRole('dialog', { name: 'Ana Torres' })).not.toBeInTheDocument()
  })

  it('mide la meta con la conversión del mes, no con la del cumplimiento', () => {
    // Las dos fuentes discrepan A PROPÓSITO: la conversión del mes de Ana es
    // 34.6 % (la que enseña su número grande) y el cumplimiento de metas dice
    // 40 %, que es otra fórmula. Con meta 40 %, la leyenda de la barra delata
    // cuál de las dos se está midiendo.
    const metas = metasConversionEquipoDemo()
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor
    const metaAna = metas['demo-v1']
    const cumplimientoAna = cumplimientos['demo-v1']
    if (!metaAna || !cumplimientoAna) throw new Error('El demo dejó de traer a Ana Torres')
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        equipo={conversionEquipoDemo()}
        metaConversion={40}
        metasVendedores={{ ...metas, 'demo-v1': { ...metaAna, conversionObjetivo: 40 } }}
        cumplimientoVendedores={{
          ...cumplimientos,
          'demo-v1': { ...cumplimientoAna, conversionReal: 40 },
        }}
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
    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getByText('34.6% de 40%')).toBeInTheDocument()
    expect(detalle.queryByText('40% de 40%')).not.toBeInTheDocument()
    // Y el veredicto de estado sale del mismo número: 34.6 < 40.
    expect(detalle.getByText('Por alcanzar')).toBeInTheDocument()
  })

  it('no presenta avance contra la meta mensual para un rango histórico', () => {
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-07-01', '2026-07-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        equipo={conversionEquipoDemo()}
        metaConversion={0}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
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
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        equipo={[conversionEquipoDemo()[0]!]}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
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
        conversionMensual={null}
        equipo={[conversionEquipoDemo()[0]!]}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
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

  it('la ficha rotula los estados del mes: Elena solo referidos, y el mes no medible', () => {
    const { unmount } = render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    fireEvent.change(screen.getByRole('combobox', { name: 'Vendedor para abrir detalle' }), {
      target: { value: 'demo-v5' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const elena = within(screen.getByRole('dialog', { name: 'Elena Vega' }))
    // Trabajó (recibió 2 referidos): rótulo propio, jamás «Sin muestra» ni «0 %».
    expect(elena.getByText('Solo recibió referidos')).toBeInTheDocument()
    expect(elena.getByText('—')).toBeInTheDocument()
    expect(elena.getByText(/2 registrados · 0 cerrados/)).toBeInTheDocument()
    unmount()

    const sinDatos = conversionMensualInteligenciaDemo(AHORA)
    sinDatos.cobertura = { ...sinDatos.cobertura, medible: false }
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={sinDatos}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
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
    const ana = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    // El servidor declara el mes no medible: la ficha lo dice, no inventa %.
    expect(ana.getByText('Sin datos del mes')).toBeInTheDocument()
  })
})
