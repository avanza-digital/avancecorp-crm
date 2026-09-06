import { fireEvent, render, screen, within } from '@testing-library/react'
import type { ComponentProps } from 'react'
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

function renderAmpliaciones(datos: MetricasConversiones, props: Partial<ComponentProps<typeof InteligenciaComercialPanel>> = {}) {
  return render(<InteligenciaComercialPanel
    datos={datos}
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
    rangoError={null}
    modoDemo
    puedeAlternarEjemplo={false}
    onAlternarEjemplo={vi.fn()}
    onReintentarMensual={vi.fn()}
    onReintentarRango={vi.fn()}
    {...props}
  />)
}

describe('citas y cierres conservados al simplificar Conversiones', () => {
  it('conserva el indicador de citas sin los dos bloques explicativos retirados', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    renderAmpliaciones(datos)
    expect(screen.queryByRole('region', { name: 'Llegadas con cita realizada' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Operaciones elegidas para conversión' })).not.toBeInTheDocument()
    expect(screen.getAllByText('Llegadas con cita realizada').find((elemento) => elemento.closest('[data-gi-kpi]'))?.closest('[data-gi-kpi]')).toHaveTextContent('38')
    expect(screen.getByText('46 citas registradas como realizadas · de 184 llegadas')).toBeInTheDocument()
    expect(screen.queryByText('Reunión o avance posterior')).not.toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Señales de avance inferido de las llegadas del rango' })).toBeInTheDocument()
  })

  it('pinta las semanas servidas por fecha de cierre sin sustituir las de llegada', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    renderAmpliaciones(datos)
    expect(screen.getByRole('img', { name: 'Cierres ocurridos por semana de cierre' })).toHaveAttribute('data-series', '[21,0,0,0,0]')
    expect(screen.getByRole('img', { name: 'Leads por semana de llegada y resultados' })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Cierres por fecha de cierre' })).toHaveTextContent('21 cierres')
    expect(screen.getByText('Leads del mes que cerraron').closest('[data-gi-kpi]')).toHaveTextContent('17')
  })

  it('conserva aportes pequeños y explica cierres fuera del roster sin redondearlos a cero', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-07')
    Object.assign(datos.cierres_por_semana!, {
      cierres: 1,
      aporte_cierres: 0.004,
      cierres_fuera_del_roster: 1,
      aporte_cierres_fuera_del_roster: 0.004,
    })
    Object.assign(datos.cierres_por_semana!.semanas[0]!, {
      cierres: 1,
      aporte_cierres: 0.004,
      cierres_fuera_del_roster: 1,
      aporte_cierres_fuera_del_roster: 0.004,
    })
    datos.responsables![0]!.cierres_por_semana![0]!.aporte_cierres = 0.004

    renderAmpliaciones(datos)
    const cierres = screen.getByRole('region', { name: 'Cierres por fecha de cierre' })
    expect(cierres).toHaveTextContent('1 cierre · aporte de cierres 0.004')
    expect(cierres).toHaveTextContent('Fuera del roster activo: 1 cierre · aporte 0.004')
    expect(within(cierres).getAllByRole('row')[1]).toHaveTextContent('0.004')

    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    expect(within(screen.getByRole('region', { name: 'Cierres semanales del analista' })).getAllByRole('row')[1]).toHaveTextContent('0.004')
  })

  it('conserva el cero real del indicador sin sumar citas anteriores al alta', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.citas_reales = { ...datos.citas_reales!, leads_con_cita_real: 0, citas_realizadas: 0, citas_anteriores_al_alta: 3, pct_llegadas_con_cita_real: 0 }
    renderAmpliaciones(datos)
    const indicador = screen.getByText('Llegadas con cita realizada').closest('[data-gi-kpi]')
    expect(indicador).toHaveTextContent('0 citas registradas como realizadas')
    expect(indicador).not.toHaveTextContent('3 citas')
  })

  it('conserva cierres aunque no hayan llegado leads nuevos', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.cohorte.leads = 0
    datos.citas_reales = { ...datos.citas_reales!, leads_base: 0, leads_con_cita_real: 0, citas_realizadas: 0, pct_llegadas_con_cita_real: null }
    renderAmpliaciones(datos)
    expect(screen.getByText('Aún no hay leads para analizar')).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Cierres ocurridos por semana de cierre' })).toHaveAttribute('data-series', '[21,0,0,0,0]')
  })

  it.each([null, undefined])('un servidor anterior (%s) no se interpreta como cero citas o cierres', (valor) => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.citas_reales = valor
    datos.conversion_operaciones = valor
    datos.cierres_por_semana = valor
    renderAmpliaciones(datos)
    expect(screen.getByText('Reunión o avance posterior').closest('[data-gi-kpi]')).toHaveTextContent('58')
    expect(screen.getByText('Semanas por fecha de cierre no disponibles o no verificables.')).toBeInTheDocument()
    expect(screen.queryByRole('img', { name: 'Cierres ocurridos por semana de cierre' })).not.toBeInTheDocument()
  })

  it('bloquea respuestas parciales o con otro rango/origen sin tocar el avance inferido', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.citas_reales!.origen_filtrado = 'referido'
    datos.cierres_por_semana!.hasta = '2026-08-20'
    renderAmpliaciones(datos)
    expect(screen.getByText('Reunión o avance posterior').closest('[data-gi-kpi]')).toHaveTextContent('58')
    expect(screen.getByText('Semanas por fecha de cierre no disponibles o no verificables.')).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Señales de avance inferido de las llegadas del rango' })).toBeInTheDocument()
  })

  it('las citas reales son independientes de la paridad del índice; los cierres se protegen', () => {
    renderAmpliaciones(metricasConversionesDemo('2026-08-01', '2026-08-31'), { modoDemo: false })
    expect(screen.getByText('Llegadas con cita realizada').closest('[data-gi-kpi]')).toHaveTextContent('38')
    expect(screen.queryByRole('img', { name: 'Cierres ocurridos por semana de cierre' })).not.toBeInTheDocument()
  })

  it('el detalle separa citas de sus llegadas y cierres conseguidos por el analista', () => {
    renderAmpliaciones(metricasConversionesDemo('2026-08-01', '2026-08-31'))
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle' }))
    expect(screen.getByRole('region', { name: 'Citas reales del analista' })).toHaveTextContent('11 leads · 13 citas registradas como realizadas')
    const cierres = screen.getByRole('region', { name: 'Cierres semanales del analista' })
    expect(cierres).toHaveTextContent('aunque la llegada pertenezca a otro')
    expect(within(cierres).getAllByRole('row')[1]).toHaveTextContent('6')
    expect(screen.getByRole('img', { name: 'Resultados por semana de llegada de Ana Torres' })).toBeInTheDocument()
  })
})

describe('detalle de conversión por analista', () => {
  it.each([null, undefined])('una lectura ausente (%s) no se presenta como cero leads', (datos) => {
    const reintentar = vi.fn()
    render(
      <InteligenciaComercialPanel
        datos={datos}
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
        rangoError={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentarMensual={vi.fn()}
        onReintentarRango={reintentar}
      />,
    )
    expect(screen.getByRole('alert')).toHaveTextContent('Resultados del rango no disponibles')
    expect(screen.queryByText('Aún no hay leads para analizar')).not.toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Conversión mensual canónica' })).getByText('23.06%')).toBeInTheDocument()
    expect(screen.getByText('Capital del mes').closest('.gi-hero-metric')).not.toHaveTextContent('—')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(reintentar).toHaveBeenCalledOnce()
  })

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
    expect(heroe.getByText('23.06%')).toBeInTheDocument()
    expect(heroe.getByText('No disponible')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las conversiones del rango.')
    expect(screen.queryByRole('img', { name: 'Resultados de los leads del mes por analista' })).not.toBeInTheDocument()
    expect(screen.queryByText('Aún no hay leads para analizar')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(onReintentarRango).toHaveBeenCalledTimes(1)
    expect(onReintentarMensual).not.toHaveBeenCalled()
  })

  it('una cohorte válida vacía conserva su vacío sin ocultar el capital y el índice mensual', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.cohorte = {
      leads: 0, asignados: 0, contactados: 0, reuniones_agendadas: 0,
      reuniones_realizadas: 0, propuestas: 0, clientes: 0, contratos: 0,
      descartados: 0, conversion_clientes_pct: null,
      conversion_contratos_pct: null, conversion_resueltos_pct: null,
    }
    datos.embudo = []
    datos.origenes = []
    datos.responsables = []
    datos.produccion = { clientes: 0, contratos: 0, capital_pen: 0, capital_usd: 0 }
    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={[]}
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
    expect(screen.getByText('Aún no hay leads para analizar')).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Conversión mensual canónica' })).getByText('23.06%')).toBeInTheDocument()
    expect(screen.getByText('Capital del mes').closest('.gi-hero-metric')).not.toHaveTextContent('—')
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
    expect(screen.getByRole('img', { name: 'Resultados de los leads del mes por analista' })).toBeInTheDocument()
    expect(screen.queryByRole('img', { name: 'Resultados de los leads del mes por origen' })).not.toBeInTheDocument()
    expect(screen.getByText('Cifras en revisión: los resultados por origen permanecen ocultos.')).toBeInTheDocument()
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
    expect(screen.getByRole('img', { name: 'Resultados de los leads del mes por analista' })).toBeInTheDocument()

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
    expect(contenido.getByText('31.50%')).toBeInTheDocument()
    expect(contenido.getByText('Base automática 10 · cierres del mes 4')).toBeInTheDocument()
    const semanal = contenido.getByRole('img', { name: 'Resultados por semana de llegada de Ana Torres' })
    expect(semanal).toHaveAttribute('data-meta-series', '[]')
    expect(contenido.getByText(/No se compara con la meta mensual ponderada/)).toBeInTheDocument()
    expect(contenido.queryByText('Citas')).not.toBeInTheDocument()
    expect(contenido.getByText(/no confirma asistencia/)).toBeInTheDocument()
    // Procedencia y referidos con la letra corregida del plan.
    expect(contenido.getByText('de agosto 3, de julio 1')).toBeInTheDocument()
    expect(contenido.getByText(/2 registrados · 1 cerrados/)).toBeInTheDocument()
    expect(contenido.getByText(/Fórmula:.*renovaciones ×0.15.*llegadas automáticas Landing\/Formulario/)).toBeInTheDocument()
    // F1.3b: la ficha dice de QUÉ es el capital — el que produjeron SUS leads
    // (el rótulo «confirmado» era del cumplimiento, otra pregunta, y la
    // fuente vieja lo dejaba en S/ 0 eterno).
    expect(contenido.getByText('Capital atribuido (PEN)')).toBeInTheDocument()
    expect(contenido.getByText('Capital atribuido (USD)')).toBeInTheDocument()
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
    expect(detalle.getByText('31.50% de 40%')).toBeInTheDocument()
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

    const evolucion = screen.getByRole('img', { name: 'Leads por semana de llegada y resultados' })
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
      .getByRole('img', { name: 'Resultados por semana de llegada de Ana Torres' })
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
    expect(detalle.queryByText('31.50%')).not.toBeInTheDocument()
    expect(detalle.queryByText('Base automática 10 · cierres del mes 4')).not.toBeInTheDocument()
    expect(detalle.queryByRole('img', { name: 'Resultados por semana de llegada de Ana Torres' })).not.toBeInTheDocument()
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
    expect(ana.getByText('31.50%')).toBeInTheDocument()
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
    nucleoExtra: Partial<NonNullable<MetricasConversiones['nucleo']>> = {},
  ) {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-27')
    // Estos casos ejercitan el contrato anterior y su avance inferido.
    delete datos.citas_reales
    if (incluirNucleo) datos.nucleo = { ...NUCLEO, ...nucleoExtra }
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

  it('el héroe usa el núcleo canónico del rango y deja Cosecha como segunda lectura', () => {
    montarConNucleo({ ...SONDAS })
    const heroeRegion = screen.getByRole('region', { name: 'Conversión canónica del rango' })
    const heroe = within(heroeRegion)
    expect(heroe.getByText(/Conversión del rango · 01 ago\. 2026 al 27 ago\. 2026/)).toBeInTheDocument()
    expect(heroe.getByText('7.22%')).toBeInTheDocument()
    expect(heroe.getByText(/537 registros en la base histórica/)).toBeInTheDocument()
    expect(heroe.queryByText('23.06%')).not.toBeInTheDocument()
    expect(screen.getAllByText('Resultados de los leads del mes').length).toBeGreaterThan(0)
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    expect(screen.getByText('17 cerrados de 184 leads')).toBeInTheDocument()
    expect(screen.queryByText(/×0.15/)).not.toBeInTheDocument()
    expect(screen.queryByText(/puntos de/)).not.toBeInTheDocument()
    expect(screen.queryByText(/base del mes/)).not.toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Resultados de los leads del mes por analista' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Resultados de los leads del mes por origen' })).toBeInTheDocument()
  })

  it('01–03 no vuelve a mostrar la base mensual que ya incluye el día 04', () => {
    const datos = metricasConversionesDemo('2026-09-01', '2026-09-03')
    datos.sondas = { ...SONDAS }
    datos.nucleo = {
      ...NUCLEO,
      base: 'llegada_unica',
      llegadas: 185,
      altas_manuales: 8,
      referidos_recibidos: 1,
      peso_renovacion: 0.15,
      divisor: 176,
      numerador: 7,
      conversion_pct: 3.98,
      cierres_no_referidos: 7,
      cierres_referidos: 0,
      operaciones_cartera: 0,
      mes_peso: '2026-09-01',
      incluye_cartera: true,
    }
    const mensual = conversionMensualInteligenciaDemo(AHORA)
    mensual.total = {
      ...mensual.total,
      divisor: 317,
      conversion_pct: 3.79,
    }

    render(
      <InteligenciaComercialPanel
        datos={datos}
        conversionMensual={mensual}
        cumplimiento={CUMPLIMIENTO_PANEL}
        origenFiltrado={null}
        equipo={conversionEquipoDemo()}
        metaConversion={15}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'setiembre 2026', comparable: true }}
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

    const heroeRegion = screen.getByRole('region', { name: 'Conversión canónica del rango' })
    const heroe = within(heroeRegion)
    expect(heroe.getByText(/Conversión del rango · 01 set\. 2026 al 03 set\. 2026/)).toBeInTheDocument()
    expect(heroe.getByText('3.98%')).toBeInTheDocument()
    expect(heroe.getByText(/Base: 176 leads automáticos · 7 cierres/)).toBeInTheDocument()
    expect(heroeRegion).not.toHaveTextContent('317')
    expect(heroeRegion).not.toHaveTextContent('3.79%')
    expect(heroe.queryByText(/no incluye operaciones de cartera/)).not.toBeInTheDocument()
    expect(heroe.getByText('185 llegadas únicas: 176 automáticas · 8 manuales · 1 referido')).toBeInTheDocument()
    expect(heroe.getByText(/Peso: referidos y renovaciones ×0.15 · Upgrades ×1/)).toBeInTheDocument()
    expect(heroeRegion).not.toHaveTextContent('fuera de la base')
    expect(heroeRegion).not.toHaveTextContent('Cosecha del rango')
    expect(heroe.queryByText(/asignaciones contabilizadas/)).not.toBeInTheDocument()
  })

  it('el descuadre oculta núcleo y resultados por origen sin disfrazarlos con el mensual', () => {
    montarConNucleo({ ...SONDAS, cuadra: false, paridad_nucleo: 2 })
    expect(screen.getAllByText('9.2%').length).toBeGreaterThan(0)
    const heroe = within(screen.getByRole('region', { name: 'Conversión canónica del rango' }))
    expect(heroe.getByText('Cifras en revisión: falta verificar la conversión del rango.')).toBeInTheDocument()
    expect(heroe.queryByText('7.22%')).not.toBeInTheDocument()
    expect(heroe.queryByText('23.06%')).not.toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Resultados de los leads del mes por analista' })).toBeInTheDocument()
    expect(screen.queryByRole('img', { name: 'Resultados de los leads del mes por origen' })).not.toBeInTheDocument()
  })

  it.each([
    ['sondas ausentes', undefined],
    ['verificación no ejecutada', { ...SONDAS, cuadra: null, paridad_nucleo: null }],
    ['sin filas verificadas', { ...SONDAS, paridad_filas: 0 }],
  ])('no publica el núcleo con %s', (_caso, sondas) => {
    montarConNucleo(sondas)
    const heroe = within(screen.getByRole('region', { name: 'Conversión canónica del rango' }))
    expect(heroe.getByText('Cifras en revisión: falta verificar la conversión del rango.')).toBeInTheDocument()
    expect(heroe.queryByText('7.22%')).not.toBeInTheDocument()
    expect(heroe.queryByText('23.06%')).not.toBeInTheDocument()
    expect(screen.queryByRole('img', { name: 'Resultados de los leads del mes por origen' })).not.toBeInTheDocument()
  })

  it('mantiene el avance inferido sin presentarlo como citas o asistencia real', () => {
    montarConNucleo({ ...SONDAS })
    const tarjeta = screen.getByText('Reunión o avance posterior').closest('[data-gi-kpi]')
    expect(tarjeta).toHaveTextContent('58')
    expect(tarjeta).toHaveTextContent('82 con señal de agenda o avance posterior · no confirma asistencia')
    expect(screen.getByRole('heading', { name: 'Avance comercial inferido' })).toBeInTheDocument()
    expect(screen.queryByText('Leads que llegaron a cita')).not.toBeInTheDocument()
    expect(screen.queryByText('Citas realizadas')).not.toBeInTheDocument()
    const avance = screen.getByRole('img', { name: 'Señales de avance inferido de las llegadas del rango' })
    expect(JSON.parse(avance.getAttribute('data-series') ?? '[]')).toEqual([184, 139, 82, 58, 37, 17])
  })

  it('preserva null sin base y no lo sustituye por cero ni por el porcentaje mensual', () => {
    montarConNucleo({ ...SONDAS }, false, true, false, { divisor: 0, numerador: 0, conversion_pct: null })
    const heroe = within(screen.getByRole('region', { name: 'Conversión canónica del rango' }))
    expect(heroe.getByText('—')).toBeInTheDocument()
    expect(heroe.queryByText('0.00%')).not.toBeInTheDocument()
    expect(heroe.queryByText('23.06%')).not.toBeInTheDocument()
  })

  it('mantiene el porcentaje canónico servido por encima de100', () => {
    montarConNucleo({ ...SONDAS }, false, true, false, { divisor: 10, numerador: 15, conversion_pct: 150 })
    const heroe = within(screen.getByRole('region', { name: 'Conversión canónica del rango' }))
    expect(heroe.getByText('150.00%')).toBeInTheDocument()
    expect(heroe.queryByText('100.00%')).not.toBeInTheDocument()
  })

  it('D6: el origen fuera de la base (Referido) se rotula bajo la gráfica', () => {
    montarConNucleo({ ...SONDAS }, true)
    expect(screen.getByText(/sus llegadas no aumentan la base automática/)).toBeInTheDocument()
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
    expect(screen.getByRole('img', { name: 'Resultados de los leads del mes por analista' })).toBeInTheDocument()
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

    expect(screen.getByText(/Capital vinculado por origen/)).toBeInTheDocument()
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

    expect(screen.queryByText(/Capital vinculado por origen/)).not.toBeInTheDocument()
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
    expect(screen.getByText(/Resultados de los leads del mes · Referido/)).toBeInTheDocument()
    expect(screen.queryByText('Capital del mes')).not.toBeInTheDocument()
    expect(screen.queryByText(/Meta mensual ·/)).not.toBeInTheDocument()
    expect(screen.queryByText('Capital confirmado del mes')).not.toBeInTheDocument()
    // Capital del lote = origenes[] (Referido demo: 460.000 PEN + 60.000 USD).
    expect(screen.getAllByText('Capital vinculado a las llegadas')[0]).toBeInTheDocument()
    expect(screen.getAllByText(money(460_000, 'PEN')).length).toBeGreaterThan(0)
    expect(screen.getByText(money(60_000, 'USD'))).toBeInTheDocument()
  })

  it('sin filtro, todo queda como siempre (empresa completa)', () => {
    montarConOrigen(null)
    expect(screen.getByText('Capital del mes')).toBeInTheDocument()
    expect(screen.getByText('Capital confirmado del mes')).toBeInTheDocument()
    expect(screen.queryByText(/Capital vinculado a las llegadas/)).not.toBeInTheDocument()
    expect(screen.queryByText(/origen: /)).not.toBeInTheDocument()
  })
})
