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
import type { MetricasConversiones } from '@/lib/metricas-conversiones'
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
      data-meta-series={JSON.stringify(option.series?.[1]?.data ?? [])}
    />
  ),
}))

// Instante fijo a mitad de mes: la procedencia nombra meses reales de Lima y
// un Date.now() haría rotar el texto esperado cada mes.
const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

// Capital confirmado del mes: la fuente que el panel ENSEÑA (ver prop cumplimiento).
const CUMPLIMIENTO_PANEL = cumplimientoMetasConversionEquipoDemo().gerencia

describe('detalle de conversión por analista', () => {
  it('mantiene el héroe mensual cuando falla la lectura secundaria del rango', () => {
    const onReintentarMensual = vi.fn()
    const onReintentarRango = vi.fn()
    render(
      <InteligenciaComercialPanel
        datos={undefined}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError="No se pudieron cargar las conversiones del rango."
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={onReintentarMensual}
        onReintentarRango={onReintentarRango}
      />,
    )

    const heroe = within(screen.getByRole('region', { name: 'Conversión mensual canónica' }))
    expect(heroe.getByText('Conversión del mes · agosto 2026')).toBeInTheDocument()
    expect(heroe.getByText('23.85%')).toBeInTheDocument()
    expect(heroe.getByText('No disponible')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las conversiones del rango.')
    expect(screen.queryByRole('img', { name: 'Cosecha del período por analista' })).not.toBeInTheDocument()
    expect(screen.queryByText('Aún no hay leads para analizar')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(onReintentarRango).toHaveBeenCalledTimes(1)
    expect(onReintentarMensual).not.toHaveBeenCalled()
  })

  it('mantiene los paneles del rango cuando falla el núcleo mensual', () => {
    const onReintentarMensual = vi.fn()
    const onReintentarRango = vi.fn()
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={null}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError="No se pudo calcular la conversión mensual."
        rangoCargando={false}
        rangoError={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={onReintentarMensual}
        onReintentarRango={onReintentarRango}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo calcular la conversión mensual.')
    expect(screen.getByRole('region', { name: 'Conversión mensual canónica' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Cosecha del período por analista' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Conversión a clientes por origen del lead' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(onReintentarMensual).toHaveBeenCalledTimes(1)
    expect(onReintentarRango).not.toHaveBeenCalled()
  })

  it('muestra toda la foto mensual en carga sin tapar la Cosecha ni fingir ausencia', () => {
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={undefined}
        cumplimiento={null}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    const heroe = screen.getByRole('region', { name: 'Conversión mensual canónica' })
    expect(heroe).toHaveAttribute('aria-busy', 'true')
    expect(within(heroe).getByText('Calculando…')).toBeInTheDocument()
    expect(within(heroe).getAllByText('Consultando…')).toHaveLength(2)
    expect(within(heroe).queryByText('Sin meta')).not.toBeInTheDocument()
    expect(within(heroe).queryByText('—')).not.toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Cosecha del período por analista' })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getByText('Consultando la conversión, las metas y el capital confirmado del mes…')).toBeInTheDocument()
    expect(detalle.queryByText('Conversión del mes no disponible')).not.toBeInTheDocument()
  })

  it('abre una ficha compacta y muestra el capital PEN y USD por separado', () => {
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))

    const detalle = screen.getByRole('dialog', { name: 'Ana Torres' })
    expect(detalle).toHaveClass('max-w-[560px]')
    expect(detalle).not.toHaveClass('max-w-[780px]')

    const contenido = within(detalle)
    // El número grande es LA conversión del MES (4.15÷12), no la del rango.
    expect(contenido.getByText('conversión del mes')).toBeInTheDocument()
    expect(contenido.getByText('34.58%')).toBeInTheDocument()
    expect(contenido.getByText('Recibidos 12 · cierres 5')).toBeInTheDocument()
    // Procedencia y referidos con la letra corregida del plan.
    expect(contenido.getByText('de agosto 4, de julio 1')).toBeInTheDocument()
    expect(contenido.getByText(/2 registrados · 1 cerrados/)).toBeInTheDocument()
    expect(contenido.getByText('Fórmula: (cierres no referidos + referidos ×0.15 + operaciones de cartera) ÷ leads no referidos recibidos en el mes.')).toBeInTheDocument()
    // F1.3b: la ficha dice de QUÉ es el capital — el que produjeron SUS leads
    // (el rótulo «confirmado» era del cumplimiento, otra pregunta, y la
    // fuente vieja lo dejaba en S/ 0 eterno).
    expect(contenido.getByText('Capital por sus leads (PEN)')).toBeInTheDocument()
    expect(contenido.getByText('Capital por sus leads (USD)')).toBeInTheDocument()
    expect(contenido.queryByText('Capital confirmado PEN')).not.toBeInTheDocument()
    expect(contenido.getByText(money(360_000, 'PEN'))).toBeInTheDocument()
    expect(contenido.getByText(money(20_000, 'USD'))).toBeInTheDocument()
    expect(contenido.getByText('Capital en PEN')).toBeInTheDocument()
    expect(contenido.getByText(/de 25%/)).toBeInTheDocument()

    fireEvent.click(contenido.getByRole('button', { name: 'Cerrar detalle de analista' }))
    expect(screen.queryByRole('dialog', { name: 'Ana Torres' })).not.toBeInTheDocument()
  })

  it('la ficha explica el arrastre igual que el ranking: el porqué no desaparece al abrir el detalle', () => {
    // Hallazgo #6 de la revisión adversaria: gerencia veía el chip en el
    // ranking, abría al MISMO analista y el % neto quedaba sin explicación.
    const mensual = conversionMensualInteligenciaDemo(AHORA)
    const ana = mensual.responsables.find((fila) => fila.vendedor_id === 'demo-v1')
    if (ana) {
      ana.ajuste = {
        pendiente: 1,
        origenes: [{ periodo: '2026-07', motivo: 'Cierre anulado por gerencia', numerador: 1 }],
      }
    }
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={mensual}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const contenido = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    const chip = contenido.getByText('arrastra 1 conversión de anulaciones · julio 2026')
    expect(chip).toHaveAttribute('title', 'julio 2026: Cierre anulado por gerencia (−1)')
  })

  it('mide la meta con la conversión del mes, no con la del cumplimiento', () => {
    // Las dos fuentes discrepan A PROPÓSITO: la conversión del mes de Ana es
    // 34.58 % (la que enseña su número grande) y el cumplimiento de metas dice
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
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={40}
        metasVendedores={{ ...metas, 'demo-v1': { ...metaAna, conversionObjetivo: 40 } }}
        cumplimientoVendedores={{
          ...cumplimientos,
          'demo-v1': { ...cumplimientoAna, conversionReal: 40 },
        }}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getByText('34.58% de 40%')).toBeInTheDocument()
    expect(detalle.queryByText('40% de 40%')).not.toBeInTheDocument()
    // Y el veredicto de estado sale del mismo número: 34.58 < 40.
    expect(detalle.getByText('Por alcanzar')).toBeInTheDocument()
  })

  it('no presenta avance contra la meta mensual para un rango histórico', () => {
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-07-01', '2026-07-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={0}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    expect(screen.getByText('No comparable')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))

    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getAllByText('La meta mensual de agosto 2026 no es comparable con el rango aplicado.').length).toBeGreaterThan(0)
    expect(detalle.queryAllByRole('progressbar')).toHaveLength(0)
    expect(detalle.queryByText(/de 15%/)).not.toBeInTheDocument()
  })

  it('grafica las semanas históricas con los enteros servidos; el % por analista sigue en su sheet', () => {
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
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={[conversionEquipoDemo()[0]!]}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    const evolucion = screen.getByRole('img', { name: 'Leads recibidos y cierres por semana del rango aplicado' })
    expect(JSON.parse(evolucion.getAttribute('data-x-axis') ?? '[]')).toEqual([
      '2026-06-03 – 2026-06-09',
      '2026-06-10 – 2026-06-16',
    ])
    // F3 (H12): la curva del equipo pinta enteros servidos — serie 0 recibidos,
    // serie 1 cierres. El % semanal del equipo ya no se fabrica en el cliente.
    expect(JSON.parse(evolucion.getAttribute('data-series') ?? '[]')).toEqual([0, 2])
    expect(JSON.parse(evolucion.getAttribute('data-meta-series') ?? '[]')).toEqual([0, 1])

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const tendencia = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
      .getByRole('img', { name: 'Tendencia semanal de conversión de Ana Torres' })
    expect(JSON.parse(tendencia.getAttribute('data-x-axis') ?? '[]')).toEqual([
      '2026-06-03 – 2026-06-09',
      '2026-06-10 – 2026-06-16',
    ])
    expect(JSON.parse(tendencia.getAttribute('data-series') ?? '[]')).toEqual([null, 50])
  })

  it('con núcleo verificado no convierte en cero el detalle mensual ausente', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete datos.responsables
    datos.nucleo = {
      base: 'COHORTE_POR_ASIGNACION_REFERIDOS_PONDERADOS',
      divisor: 10,
      numerador: 1,
      conversion_pct: 10,
      cierres_no_referidos: 1,
      cierres_referidos: 0,
      referidos_recibidos: 0,
      referidos_cierran_pct: null,
      operaciones_cartera: 0,
      peso_referido: 0.15,
      mes_peso: '2026-08-01',
      incluye_cartera: true,
    }
    datos.sondas = {
      cuadra: true,
      paridad_nucleo: 0,
      paridad_filas: 1,
      divisor_fuera_del_roster: 0,
      numerador_fuera_del_roster: 0,
      cierres_sin_ficha_convertida: 0,
      cohorte_convertidos_sin_cierre_elegible: 0,
      cartera_fuera_del_rango: 0,
      cierres_anulados: 0,
      episodios_sin_origen: 0,
      origen_ficha_distinto_del_ledger: 0,
    }

    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={null}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={[conversionEquipoDemo()[0]!]}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    expect(screen.getByText('Tendencia no disponible')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))

    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getByText('Conversión del mes no disponible')).toBeInTheDocument()
    expect(detalle.getAllByText('—').length).toBeGreaterThan(0)
    expect(detalle.queryByText(money(360_000, 'PEN'))).not.toBeInTheDocument()
    expect(detalle.queryByText('Tendencia no disponible')).not.toBeInTheDocument()
  })

  it('la ficha falla cerrada ante cierres mensuales sin episodio, pero conserva el capital del rango', () => {
    const mensual = conversionMensualInteligenciaDemo(AHORA)
    mensual.cobertura = { ...mensual.cobertura, cierres_sin_episodio: 1 }

    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={mensual}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const detalle = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(detalle.getByText('Conversión del mes no disponible')).toBeInTheDocument()
    expect(detalle.getByText(/1 cierre no tiene episodio verificable/)).toBeInTheDocument()
    expect(detalle.queryByText('34.58%')).not.toBeInTheDocument()
    expect(detalle.queryByText('Recibidos 12 · cierres 5')).not.toBeInTheDocument()
    expect(detalle.queryByRole('img', { name: 'Tendencia semanal de conversión de Ana Torres' })).not.toBeInTheDocument()
    expect(detalle.getByText(money(360_000, 'PEN'))).toBeInTheDocument()
    expect(detalle.getByText(money(20_000, 'USD'))).toBeInTheDocument()
  })

  it('la ficha rotula solo referidos y publica un mes parcial con aviso provisional', () => {
    const { unmount } = render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    fireEvent.change(screen.getByRole('combobox', { name: 'Analista para abrir detalle' }), {
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
    sinDatos.cobertura = {
      ...sinDatos.cobertura,
      medible: false,
      motivo_no_medible: 'mes_parcial',
      suelo_historico: '2026-08-17',
    }
    render(
      <InteligenciaComercialPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={sinDatos}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const ana = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(ana.getByText('34.58%')).toBeInTheDocument()
    expect(ana.getByText(/Provisional: el registro empieza/)).toBeInTheDocument()
    expect(ana.queryByText('Sin datos del mes')).not.toBeInTheDocument()
  })
})

describe('cifra del núcleo en Conversiones (F3.1/D2 + F3.4)', () => {
  const NUCLEO = {
    base: 'COHORTE_POR_ASIGNACION_REFERIDOS_PONDERADOS',
    divisor: 537,
    numerador: 38.75,
    conversion_pct: 7.22,
    cierres_no_referidos: 14,
    cierres_referidos: 3,
    referidos_recibidos: 20,
    referidos_cierran_pct: 15,
    operaciones_cartera: 29,
    peso_referido: 0.15,
    mes_peso: '2026-08-01',
    incluye_cartera: true,
  }
  const COSECHA = {
    base: 'ALTAS_DEL_RANGO',
    leads: 545,
    cerraron: 14,
    conversion_pct: 2.6,
    madura_hasta: '2026-08-27',
  }
  const SONDAS: NonNullable<MetricasConversiones['sondas']> = {
    cuadra: true as boolean | null,
    paridad_nucleo: 0 as number | null,
    paridad_filas: 16,
    divisor_fuera_del_roster: 0,
    numerador_fuera_del_roster: 0,
    cierres_sin_ficha_convertida: 0,
    cohorte_convertidos_sin_cierre_elegible: 0,
    cartera_fuera_del_rango: 0,
    cierres_anulados: 0,
    episodios_sin_origen: 0,
    origen_ficha_distinto_del_ledger: 0,
    // F1.3b: opcional en el contrato; el fixture la lleva en 0 (estado sano).
    perfiles_con_leads_de_varios_vendedores: 0,
  }

  function montarConNucleo(
    sondas: NonNullable<MetricasConversiones['sondas']> | undefined,
    origenReferido = false,
    incluirNucleo = true,
    modoDemo = true,
  ) {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    if (incluirNucleo) datos.nucleo = { ...NUCLEO }
    datos.cosecha = { ...COSECHA }
    if (sondas !== undefined) datos.sondas = sondas
    if (origenReferido) {
      const referido = datos.origenes.find((fila) => fila.origen.toLowerCase() === 'referido')
      if (referido) {
        referido.fuera_del_divisor_del_nucleo = true
        referido.peso_en_nucleo = 0.15
      }
    }
    return render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo={modoDemo}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )
  }

  it('el héroe muestra la conversión mensual canónica y deja Cosecha como lectura del rango', () => {
    montarConNucleo({ ...SONDAS })
    expect(screen.getByText('Conversión del mes · agosto 2026')).toBeInTheDocument()
    expect(screen.getByText('23.85%')).toBeInTheDocument()
    expect(screen.getAllByText('Cosecha del período').length).toBeGreaterThan(0)
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    expect(screen.getByText('17 cierres de 184')).toBeInTheDocument()
    expect(screen.queryByText('7.2%')).not.toBeInTheDocument()
    expect(screen.queryByText(/×0.15/)).not.toBeInTheDocument()
    expect(screen.queryByText(/puntos de/)).not.toBeInTheDocument()
    expect(screen.queryByText(/base del mes/)).not.toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Cosecha del período por analista' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Conversión a clientes por origen del lead' })).toBeInTheDocument()
  })

  it('la paridad del núcleo ya no gobierna esta pantalla: el BRUTO se pinta igual', () => {
    // Antes (F3.4) el descuadre ocultaba la cifra del mes. La cifra de aquí
    // es la cosecha bruta y la paridad no la toca — sin cifra oculta y sin
    // banner de «Cifras en revisión» (HOY/Metas/Ranking conservan el suyo).
    montarConNucleo({ ...SONDAS, cuadra: false, paridad_nucleo: 2 })
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    expect(screen.queryByText(/Cifras en revisión/)).not.toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Cosecha del período por analista' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Conversión a clientes por origen del lead' })).toBeInTheDocument()
  })

  it('D6: el origen fuera de la base (Referido) se rotula bajo la gráfica', () => {
    montarConNucleo({ ...SONDAS }, true)
    expect(screen.getByText(/queda fuera de la base de la conversión del mes/)).toBeInTheDocument()
  })

  it('origen ficha≠ledger avisa sin ocultar la cifra', () => {
    montarConNucleo({ ...SONDAS, origen_ficha_distinto_del_ledger: 2 })
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    expect(screen.getByText(/origen distinto entre su ficha y el/)).toBeInTheDocument()
  })

  it('F1.3b: la sonda de perfiles compartidos avisa que el desglose puede sumar de más', () => {
    montarConNucleo({ ...SONDAS, perfiles_con_leads_de_varios_vendedores: 2 })
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    expect(screen.getByText(/2 clientes tienen leads de más de un analista/)).toBeInTheDocument()
    expect(screen.getByText(/puede sumar más que el total/)).toBeInTheDocument()
  })

  it('F1.3b: el warning convive con la cosecha bruta y el capital', () => {
    montarConNucleo({
      ...SONDAS,
      cuadra: false,
      paridad_nucleo: 2,
      perfiles_con_leads_de_varios_vendedores: 2,
    })

    expect(screen.getByText(/2 clientes tienen leads de más de un analista/)).toBeInTheDocument()
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    expect(screen.getByRole('img', { name: 'Cosecha del período por analista' })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Capital producido por origen' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const capitalVendedor = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    expect(capitalVendedor.getByText(money(360_000, 'PEN'))).toBeInTheDocument()
  })

  it('F1.3b: con el probe en 0 o realmente ausente (servidor previo) no hay aviso', () => {
    const vistaConCero = montarConNucleo({ ...SONDAS })
    expect(screen.queryByText(/leads de más de un analista/)).not.toBeInTheDocument()
    vistaConCero.unmount()

    const { perfiles_con_leads_de_varios_vendedores: _omitido, ...sondasServidorPrevio } = SONDAS
    montarConNucleo(sondasServidorPrevio)
    expect(screen.queryByText(/leads de más de un analista/)).not.toBeInTheDocument()
  })
})

describe('F1.3: capital por leads (veto de Miguel 27/08: fuera del héroe)', () => {
  it('el héroe jamás pinta la línea de capital por leads, ni con producción viva', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    datos.produccion = { ...datos.produccion, contratos: 9, capital_pen: 113_000, capital_usd: 133_000, sin_rastro: 1 }
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    expect(screen.queryByText(/Capital por leads del rango/)).not.toBeInTheDocument()
    expect(screen.queryByText(/sin capital rastreable/)).not.toBeInTheDocument()
  })
})

describe('F1.3b: capital producido por origen', () => {
  it('lista cada origen con su capital PEN/USD por separado, solo los que producen', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    // Web queda sin nada para probar que un origen sin capital NO se lista.
    datos.origenes = datos.origenes.map((fila) => fila.origen === 'Web'
      ? { ...fila, capital_pen: 0, capital_usd: 0 }
      : fila)
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    expect(screen.getByText(/Capital producido por origen/)).toBeInTheDocument()
    const bloque = screen.getByRole('region', { name: 'Capital producido por origen' })
    expect(within(bloque as HTMLElement).getByText('Meta Ads')).toBeInTheDocument()
    // PEN y USD por separado, jamás sumados (no hay TC en este panel).
    expect(within(bloque as HTMLElement).getByText(`${money(720_000, 'PEN')} + ${money(36_000, 'USD')}`)).toBeInTheDocument()
    // Web produjo 0: no aparece en la lista de capital.
    expect(within(bloque as HTMLElement).queryByText('Web')).not.toBeInTheDocument()
  })

  it('sin capital en ningún origen, el bloque entero no existe (sin ruido)', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    datos.origenes = datos.origenes.map((fila) => ({ ...fila, capital_pen: 0, capital_usd: 0 }))
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )

    expect(screen.queryByText(/Capital producido por origen/)).not.toBeInTheDocument()
  })
})

describe('filtro de origen en Conversiones (27/08)', () => {
  function montarConOrigen(origenFiltrado: string | null) {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    if (origenFiltrado != null) {
      datos.origen_filtrado = origenFiltrado
      datos.origenes = datos.origenes.filter((fila) => fila.origen === 'Referido')
    }
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={origenFiltrado}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        mensualCargando={false}
        mensualError={null}
        rangoCargando={false}
        rangoError={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={vi.fn()}
      />,
    )
  }

  it('con filtro, las cifras de EMPRESA se retiran y entra el capital del LOTE', () => {
    montarConOrigen('referido')
    // El héroe rotula el origen y el lote reemplaza al capital/meta de empresa.
    expect(screen.getByText(/Cosecha del rango · Referido/)).toBeInTheDocument()
    expect(screen.queryByText('Capital del mes')).not.toBeInTheDocument()
    expect(screen.queryByText(/Meta mensual ·/)).not.toBeInTheDocument()
    expect(screen.queryByText('Capital confirmado del mes')).not.toBeInTheDocument()
    // Capital del lote = origenes[] (Referido demo: 460.000 PEN + 60.000 USD).
    expect(screen.getByText('Capital del lote (hasta hoy)')).toBeInTheDocument()
    expect(screen.getAllByText(money(460_000, 'PEN')).length).toBeGreaterThan(0)
    expect(screen.getByText(money(60_000, 'USD'))).toBeInTheDocument()
  })

  it('sin filtro, todo queda como siempre (empresa completa)', () => {
    montarConOrigen(null)
    expect(screen.getByText('Capital del mes')).toBeInTheDocument()
    expect(screen.getByText('Capital confirmado del mes')).toBeInTheDocument()
    expect(screen.queryByText(/Capital del lote/)).not.toBeInTheDocument()
    expect(screen.queryByText(/origen: /)).not.toBeInTheDocument()
  })
})
