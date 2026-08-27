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
      data-meta-series={JSON.stringify(option.series?.[1]?.data ?? [])}
    />
  ),
}))

// Instante fijo a mitad de mes: la procedencia nombra meses reales de Lima y
// un Date.now() haría rotar el texto esperado cada mes.
const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

// Capital confirmado del mes: la fuente que el panel ENSEÑA (ver prop cumplimiento).
const CUMPLIMIENTO_PANEL = cumplimientoMetasConversionEquipoDemo().gerencia

describe('detalle de conversión por vendedor', () => {
  it('no mezcla un error inicial con el mensaje de datos vacíos', () => {
    render(
      <InteligenciaComercialPanel
        datos={undefined}
        conversionMensual={null}
        cumplimiento={CUMPLIMIENTO_PANEL}
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
        cumplimiento={CUMPLIMIENTO_PANEL}
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

    fireEvent.click(contenido.getByRole('button', { name: 'Cerrar detalle de vendedor' }))
    expect(screen.queryByRole('dialog', { name: 'Ana Torres' })).not.toBeInTheDocument()
  })

  it('la ficha explica el arrastre igual que el ranking: el porqué no desaparece al abrir el detalle', () => {
    // Hallazgo #6 de la revisión adversaria: gerencia veía el chip en el
    // ranking, abría al MISMO vendedor y el % neto quedaba sin explicación.
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
    const contenido = within(screen.getByRole('dialog', { name: 'Ana Torres' }))
    const chip = contenido.getByText('arrastra 1 conversión de anulaciones · julio 2026')
    expect(chip).toHaveAttribute('title', 'julio 2026: Cierre anulado por gerencia (−1)')
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
        cumplimiento={CUMPLIMIENTO_PANEL}
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
        cumplimiento={CUMPLIMIENTO_PANEL}
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

  it('grafica las semanas históricas con los enteros servidos; el % por vendedor sigue en su sheet', () => {
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

  it('no convierte en cero el detalle ausente de una RPC antigua', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete datos.responsables

    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={null}
        cumplimiento={CUMPLIMIENTO_PANEL}
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
        cumplimiento={CUMPLIMIENTO_PANEL}
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
        cumplimiento={CUMPLIMIENTO_PANEL}
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
  const SONDAS = {
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
    perfiles_con_leads_de_varios_vendedores: 0 as number | undefined,
  }

  function montarConNucleo(sondas: typeof SONDAS, origenReferido = false) {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    datos.nucleo = { ...NUCLEO }
    datos.cosecha = { ...COSECHA }
    datos.sondas = sondas
    if (origenReferido) {
      const referido = datos.origenes.find((fila) => fila.origen.toLowerCase() === 'referido')
      if (referido) {
        referido.fuera_del_divisor_del_nucleo = true
        referido.peso_en_nucleo = 0.15
      }
    }
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )
  }

  it('con sonda verificada, el héroe pinta el NÚCLEO con su desglose y la cosecha aparte', () => {
    montarConNucleo({ ...SONDAS })
    // «Conversión del mes» aparece en héroe y KPI: ambos con la MISMA cifra.
    expect(screen.getAllByText('Conversión del mes').length).toBeGreaterThan(0)
    expect(screen.getAllByText('7.2%').length).toBeGreaterThan(0)
    // H1: el desglose legible dice de qué está hecho el numerador.
    expect(screen.getByText(/14 cierres \+ 3 referidos ×0.15 \+ 29 de cartera = 38.75 sobre 537 recibidos/)).toBeInTheDocument()
    expect(screen.getByText(/Por cosecha: de 545 leads que entraron al rango, cerraron 14/)).toBeInTheDocument()
  })

  it('F3.4: con la sonda en falso, la cifra SE OCULTA y el banner ámbar lo dice', () => {
    montarConNucleo({ ...SONDAS, cuadra: false, paridad_nucleo: 2 })
    expect(screen.queryByText('7.2%')).not.toBeInTheDocument()
    expect(screen.getAllByText(/Cifras en revisión/).length).toBeGreaterThan(0)
  })

  it('D6: el origen fuera de la base (Referido) se rotula bajo la gráfica', () => {
    montarConNucleo({ ...SONDAS }, true)
    expect(screen.getByText(/queda fuera de la base de la conversión del mes/)).toBeInTheDocument()
  })

  it('origen ficha≠ledger avisa sin ocultar la cifra', () => {
    montarConNucleo({ ...SONDAS, origen_ficha_distinto_del_ledger: 2 })
    expect(screen.getAllByText('7.2%').length).toBeGreaterThan(0)
    expect(screen.getByText(/origen distinto entre su ficha y el/)).toBeInTheDocument()
  })

  it('F1.3b: la sonda de perfiles compartidos avisa que el desglose puede sumar de más', () => {
    montarConNucleo({ ...SONDAS, perfiles_con_leads_de_varios_vendedores: 2 })
    expect(screen.getAllByText('7.2%').length).toBeGreaterThan(0)
    expect(screen.getByText(/2 clientes tienen leads de más de un vendedor/)).toBeInTheDocument()
    expect(screen.getByText(/puede sumar más que el total/)).toBeInTheDocument()
  })

  it('F1.3b: con la sonda en 0 (o ausente, servidor previo) no hay aviso', () => {
    montarConNucleo({ ...SONDAS })
    expect(screen.queryByText(/leads de más de un vendedor/)).not.toBeInTheDocument()
  })
})

describe('F1.3: capital por leads del rango en el héroe', () => {
  function montarConProduccion(produccion: Partial<ReturnType<typeof metricasConversionesDemo>['produccion']>) {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    datos.produccion = { ...datos.produccion, ...produccion }
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )
  }

  it('pinta la lectura por leads con su desglose y declara los sin rastro', () => {
    // Estado real de prod tras la migración F1.3 (medido 27/08): portal + coops
    // y UN convertido sin perfil ni cierre externo — el hueco se dice.
    montarConProduccion({ contratos: 9, capital_pen: 113_000, capital_usd: 123_000, sin_rastro: 1 })
    expect(screen.getByText(/Capital por leads del rango:/)).toBeInTheDocument()
    expect(screen.getByText(/9 cierres/)).toBeInTheDocument()
    expect(screen.getByText(/1 convertido sin capital rastreable/)).toBeInTheDocument()
  })

  it('sin producción en el rango, la línea no aparece (cero honesto, sin ruido)', () => {
    montarConProduccion({ clientes: 0, contratos: 0, capital_pen: 0, capital_usd: 0, sin_rastro: 0 })
    expect(screen.queryByText(/Capital por leads del rango:/)).not.toBeInTheDocument()
  })

  it('con servidor previo (sin sin_rastro), la línea vive y no rotula huecos', () => {
    montarConProduccion({ contratos: 5, capital_pen: 50_000, capital_usd: 0, sin_rastro: undefined })
    expect(screen.getByText(/Capital por leads del rango:/)).toBeInTheDocument()
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
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText(/Capital producido por origen/)).toBeInTheDocument()
    const bloque = screen.getByText(/Capital producido por origen/).closest('div')
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
        equipo={conversionEquipoDemo()}
        metaConversion={25}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.queryByText(/Capital producido por origen/)).not.toBeInTheDocument()
  })
})
