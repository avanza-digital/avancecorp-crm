import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  conversionMensualInteligenciaDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { money, porcentajeConversionCanonica } from '@/lib/format'
import type { ConversionMensual, ResponsableConversionMensual } from '@/lib/conversion-mensual'
import type { MetricasConversiones } from '@/lib/metricas-conversiones'
import type { MetricasReuniones } from '@/lib/metricas-reuniones'
import { agregarObjetivos, objetivosCero } from '@/lib/objetivos'
import { ResumenGerenciaPanel } from './resumen-gerencia'

// TC real para que el consolidado se ejercite en su rama normal.
const TC_TEST = { promedio: 3.5, fuente: 'BCRP · prom. 7d' }
// Instante fijo a mitad de mes: la conversión mensual se deriva contra Lima.
const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

function filaMensualSinActividad(vendedorId: string): ResponsableConversionMensual {
  return {
    vendedor_id: vendedorId,
    supervisor_id: null,
    divisor: 0,
    cierres_no_referidos: 0,
    cierres_referidos: 0,
    cierres_de_arrastre: 0,
    numerador: 0,
    conversion_pct: null,
    estado: 'sin_actividad',
    procedencia: [],
    referidos: { recibidos: 0, cerrados: 0, dados_de_alta: 0, aporta_pct: null },
    cartera: {
      conversiones_clientes: 0,
      conversiones_renovacion: 0,
      conversiones_upgrade: 0,
      capital_renovado_pen: 0,
      capital_renovado_usd: 0,
      capital_adicional_pen: 0,
      capital_adicional_usd: 0,
      renovaciones_sin_desglose: 0,
    },
  }
}

function conversionMensualSinActividad(): ConversionMensual {
  const base = conversionMensualInteligenciaDemo(AHORA)
  return {
    ...base,
    responsables: [],
    total: {
      ...base.total,
      analistas: 0,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 0,
      cierres_de_arrastre: 0,
      referidos_recibidos: 0,
      numerador: 0,
      conversion_pct: null,
      referidos_aporta_pct: null,
    },
  }
}

const META_EQUIPO = agregarObjetivos(Object.values(metasConversionEquipoDemo()))
const CUMPLIMIENTO_EQUIPO = cumplimientoMetasConversionEquipoDemo().gerencia
const META_VACIA = objetivosCero('2026-08-01').gerencia

vi.mock('@/components/gerencia/echart-lazy', () => ({
  GerenciaEChart: ({
    ariaLabel,
    option,
  }: {
    ariaLabel: string
    option: { series?: Array<{ data?: unknown[] }> }
  }) => (
    <div
      role="img"
      aria-label={ariaLabel}
      data-series={JSON.stringify(option.series?.[0]?.data ?? [])}
      data-meta-series={JSON.stringify(option.series?.[1]?.data ?? [])}
    />
  ),
}))

function conOrigenesVerificados(datos: MetricasConversiones): MetricasConversiones {
  return {
    ...datos,
    nucleo: {
      base: 'COHORTE_POR_ASIGNACION_REFERIDOS_PONDERADOS',
      divisor: datos.cohorte.asignados,
      numerador: datos.cohorte.contratos,
      conversion_pct: datos.cohorte.conversion_contratos_pct,
      cierres_no_referidos: datos.cohorte.contratos,
      cierres_referidos: 0,
      referidos_recibidos: 0,
      referidos_cierran_pct: null,
      operaciones_cartera: 0,
      peso_referido: 0.15,
      mes_peso: '2026-08-01',
      incluye_cartera: true,
    },
    sondas: {
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
    },
  }
}

function conversionesSinActividad(): MetricasConversiones {
  const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
  return conOrigenesVerificados({
    ...datos,
    cohorte: {
      leads: 0,
      asignados: 0,
      contactados: 0,
      reuniones_agendadas: 0,
      reuniones_realizadas: 0,
      propuestas: 0,
      clientes: 0,
      contratos: 0,
      descartados: 0,
      conversion_clientes_pct: null,
      conversion_contratos_pct: null,
      conversion_resueltos_pct: null,
    },
    produccion: { clientes: 0, contratos: 0, capital_pen: 0, capital_usd: 0 },
    embudo: datos.embudo.map((paso) => ({
      ...paso,
      cantidad: 0,
      pct_anterior: null,
      pct_total: null,
    })),
    origenes: [],
    categorias: [],
    responsables: [],
  })
}

function reunionesSinActividad(): MetricasReuniones {
  const datos = metricasReunionesDemo('2026-08-01', '2026-08-31')
  return {
    ...datos,
    resumen: {
      pactadas: 0,
      debieron_ocurrir: 0,
      realizadas: 0,
      no_concretadas: 0,
      no_show: 0,
      canceladas: 0,
      canceladas_sistema: 0,
      reprogramadas: 0,
      pendientes_cierre: 0,
      programadas_futuras: 0,
      pct_realizacion: null,
      pct_asistencia: null,
    },
    conversion: {
      leads_reunidos: 0,
      clientes: 0,
      contratos: 0,
      conversion_cliente_pct: null,
      conversion_contrato_pct: null,
      capital_pen: 0,
      capital_usd: 0,
    },
    modalidades: [],
    origenes: [],
    responsables: [],
    resultados: [],
  }
}

describe('ranking general de analistas', () => {
  it('abre la página completa de ranking desde la tarjeta de mejores analistas', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-31')
    conversiones.responsables = [
      ...(conversiones.responsables ?? []),
      {
        vendedor_id: 'demo-v7',
        leads: 0,
        contactados: 0,
        reuniones_realizadas: 0,
        clientes: 0,
        conversion_pct: null,
        capital_pen: 0,
        capital_usd: 0,
        tendencia_semanal: (conversiones.responsables?.[0]?.tendencia_semanal ?? []).map((punto) => ({
          ...punto,
          leads: 0,
          clientes: 0,
          conversion_pct: null,
        })),
      },
    ]
    const equipo = [
      ...conversionEquipoDemo(),
      {
        vendedorId: 'demo-v7',
        nombre: 'Gabriela Soto',
        supervisorNombre: 'María Salazar',
        leads: 0,
        contactados: 0,
        reunionesPactadas: 0,
        reunionesRealizadas: 0,
        clientes: 0,
        descartados: 0,
        conversionPct: null,
      },
      {
        vendedorId: null,
        nombre: 'Sin analista asignado',
        supervisorNombre: 'Sin supervisor',
        leads: 8,
        contactados: 0,
        reunionesPactadas: 0,
        reunionesRealizadas: 0,
        clientes: 0,
        descartados: 0,
        conversionPct: 0,
      },
    ]

    const mensual = conversionMensualInteligenciaDemo(AHORA)
    mensual.responsables.push(filaMensualSinActividad('demo-v7'))

    render(
      <ResumenGerenciaPanel
        conversiones={conversiones}
        conversionMensual={mensual}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={equipo}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.queryByText('Fabio León')).not.toBeInTheDocument()

    const enlace = screen.getByRole('link', { name: 'Ver ranking general de analistas' })
    expect(enlace).toHaveAttribute('href', '#/ranking-vendedores')
    const evolucion = screen.getByRole('img', { name: 'Prospectos por semana de ingreso y resultados' })
    expect(JSON.parse(evolucion.getAttribute('data-series') ?? '[]')).toHaveLength(4)
  })

  it('distingue el detalle RPC indisponible de un equipo sin muestra', () => {
    const conversiones = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete conversiones.responsables

    render(
      <ResumenGerenciaPanel
        conversiones={conversiones}
        conversionMensual={null}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Detalle por analista no disponible')).toBeInTheDocument()
    expect(screen.getByText('Tendencia no disponible')).toBeInTheDocument()
    expect(screen.queryByText('Aún no hay analistas con leads en este período')).not.toBeInTheDocument()
  })
})

describe('estados vacíos del resumen de Gerencia', () => {
  it('usa la base canónica del rango en lugar de la base mensual adelantada', () => {
    const conversiones = conOrigenesVerificados(
      metricasConversionesDemo('2026-09-01', '2026-09-03'),
    )
    conversiones.nucleo = {
      ...conversiones.nucleo!,
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
      <ResumenGerenciaPanel
        conversiones={conversiones}
        conversionMensual={mensual}
        reuniones={metricasReunionesDemo('2026-09-01', '2026-09-03')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'setiembre 2026', comparable: true }}
        cargando={false}
        rangoCargando={false}
        mensualCargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    const titulo = screen.getByText(/Conversión del rango · 01 set\. 2026 al 03 set\. 2026/)
    const heroe = titulo.closest('section')
    expect(heroe).not.toBeNull()
    expect(heroe).toHaveTextContent('3.98%')
    expect(heroe).toHaveTextContent('Base: 176 leads automáticos · 7 cierres')
    expect(heroe).toHaveTextContent('185 prospectos recibidos: 176 automáticos · 8 manuales · 1 referido')
    expect(heroe).not.toHaveTextContent('fuera de la base')
    expect(heroe).not.toHaveTextContent('317')
    expect(heroe).not.toHaveTextContent('3.79%')
  })

  it('no convierte una foto mensual pendiente en cero ni en ausencia de meta', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-09-01', '2026-09-02')}
        conversionMensual={undefined}
        reuniones={metricasReunionesDemo('2026-09-01', '2026-09-02')}
        equipo={conversionEquipoDemo()}
        meta={objetivosCero('2026-09-01').gerencia}
        cumplimiento={null}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'setiembre 2026', comparable: true }}
        cargando
        mensualCargando
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Consultando conversión, capital y meta del mes…')).toBeInTheDocument()
    expect(screen.getAllByText('Consultando…')).toHaveLength(2)
    expect(screen.getByText('Consultando capital y meta…').closest('[data-gi-kpi]')).toHaveTextContent('Calculando…')
    expect(screen.getByLabelText('Consultando ranking mensual')).toBeInTheDocument()
    expect(screen.getByLabelText('Consultando avance de metas')).toBeInTheDocument()
    expect(screen.queryByText('—')).not.toBeInTheDocument()
    expect(screen.queryByText('Sin meta')).not.toBeInTheDocument()
    expect(screen.queryByText('Cumplimiento confirmado no disponible')).not.toBeInTheDocument()
  })

  it('mantiene reuniones y metas visibles aunque la cohorte no tenga leads', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={conversionesSinActividad()}
        conversionMensual={conversionMensualSinActividad()}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={[]}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.queryByText('Aún no hay actividad comercial en este período')).not.toBeInTheDocument()
    expect(screen.getByText('Avance de metas')).toBeInTheDocument()
    // UNA barra de capital, consolidada. Antes eran «Capital PEN» y «Capital
    // USD», y la de dólares no podía tener meta —el editor pacta en soles—, así
    // que decía «Sin meta» para siempre en la primera pantalla de gerencia.
    expect(screen.getAllByText('Capital').length).toBeGreaterThan(0)
    expect(screen.queryByText('Capital PEN')).not.toBeInTheDocument()
    expect(screen.queryByText('Capital USD')).not.toBeInTheDocument()
    expect(screen.getAllByText('Citas realizadas').length).toBeGreaterThan(0)
    expect(screen.getByText('Aún no hay semanas para mostrar')).toBeInTheDocument()
    expect(screen.getByText('Aún no hay analistas medibles este mes')).toBeInTheDocument()
    expect(screen.getByText('Aún no hay orígenes con leads en este período')).toBeInTheDocument()
    // REGRESIÓN del enlace muerto: `produccion.capital_*` viene en 0 (como en
    // producción, donde `crm.leads.contrato_id` jamás se escribió) y aun así
    // el capital que se ENSEÑA es el confirmado del cumplimiento, consolidado
    // al TC: 1.480.000 PEN + 96.000 USD × 3,5 = 1.816.000. Si esto vuelve a
    // decir S/ 0 o «Sin capital confirmado», la tarjeta volvió a la fuente rota.
    expect(screen.getByText('Capital confirmado del mes')).toBeInTheDocument()
    // El KPI lleva la cifra EXACTA; la pastilla del héroe, la compacta
    // (S/ 1.82 M) — un monto de 7 dígitos reventaba el layout (captura 27/08).
    expect(screen.getByText(money(1_816_000, 'PEN'))).toBeInTheDocument()
    expect(screen.getByText('S/ 1.82 M')).toBeInTheDocument()
    expect(screen.queryByText(money(0, 'PEN'))).not.toBeInTheDocument()
    expect(screen.queryByText('Sin capital confirmado este mes')).not.toBeInTheDocument()
  })

  it('sin cumplimiento confirmado, el capital dice «—» — jamás un S/ 0 inventado', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={null}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    const tarjeta = screen.getByText('Capital confirmado del mes').closest('[data-gi-kpi]')
    expect(tarjeta).toHaveTextContent('—')
    expect(tarjeta).toHaveTextContent('Cumplimiento confirmado no disponible')
    expect(screen.queryByText(money(0, 'PEN'))).not.toBeInTheDocument()
  })

  it('con dólares y el tipo de cambio en vuelo, el total espera en vez de afirmar', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={undefined}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    const tarjeta = screen.getByText('Capital confirmado del mes').closest('[data-gi-kpi]')
    expect(tarjeta).toHaveTextContent('Calculando…')
    expect(tarjeta).toHaveTextContent('Consultando el tipo de cambio para consolidar los dólares…')
    expect(screen.getByText('Capital del mes').closest('.gi-hero-metric')).toHaveTextContent('Consultando…')
    // Un total solo-PEN aquí sería afirmar un número que va a cambiar al llegar el TC.
    expect(within(tarjeta as HTMLElement).queryByText(money(1_480_000, 'PEN'))).not.toBeInTheDocument()
  })

  it('si falla el tipo de cambio explica la degradación y conserva una salida de recuperación', () => {
    const onReintentar = vi.fn()
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={null}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={onReintentar}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('Sin tipo de cambio, el total no incluye los dólares.')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar tipo de cambio' }))
    expect(onReintentar).toHaveBeenCalledTimes(1)
  })

  it('conserva los datos disponibles cuando falla una de las métricas', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={undefined}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error="No se pudieron cargar las reuniones."
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las citas.')
    // El héroe y el KPI dicen LA conversión del MES — la del rango vive en Conversiones.
    const pctMes = porcentajeConversionCanonica(
      conversionMensualInteligenciaDemo(AHORA).total.conversion_pct,
    )
    expect(screen.getAllByText(pctMes).length).toBeGreaterThan(0)
    // 11 = 9 no referidos + 2 referidos (los referidos cierran, no dividen).
    // UN SOLO contador de leads a la vista (veto de Miguel 27/08 noche): el
    // héroe solo dice los cierres; los 607 del KPI son la única cuenta de
    // leads visible en el Resumen. La base del núcleo ya no se exhibe.
    expect(screen.getByText('10 cierres este mes')).toBeInTheDocument()
    expect(screen.queryByText(/base del mes/)).not.toBeInTheDocument()
    expect(screen.queryByText(/leads asignados/)).not.toBeInTheDocument()
    expect(screen.getByText('de 184 leads del mes')).toBeInTheDocument()
    const tarjetaReuniones = screen.getByText('Citas realizadas', { selector: '.gi-label' }).closest('[data-gi-kpi]')
    expect(tarjetaReuniones).toHaveTextContent('—')
    expect(tarjetaReuniones).toHaveTextContent('Dato no disponible')
  })

  it('conserva el vacío global cuando no existen datos, metas ni actividad', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={conversionesSinActividad()}
        conversionMensual={null}
        reuniones={reunionesSinActividad()}
        equipo={[]}
        meta={META_VACIA}
        cumplimiento={null}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Aún no hay actividad comercial en este período')).toBeInTheDocument()
    expect(screen.queryByText('Avance de metas')).not.toBeInTheDocument()
  })

  it.each([null, undefined])('una respuesta ausente (%s) no demuestra un rango sin actividad', (conversiones) => {
    const reintentar = vi.fn()
    render(
      <ResumenGerenciaPanel
        conversiones={conversiones}
        conversionMensual={null}
        reuniones={reunionesSinActividad()}
        equipo={[]}
        meta={META_VACIA}
        cumplimiento={null}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={reintentar}
      />,
    )
    expect(screen.getByRole('alert')).toHaveTextContent('Datos del resumen no disponibles')
    expect(screen.queryByText('Aún no hay actividad comercial en este período')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(reintentar).toHaveBeenCalledOnce()
  })
})

describe('meta publicada de conversión en el resumen de Gerencia', () => {
  it('identifica la fuente elegida sin mezclarla con las citas', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado="referido"
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getAllByText(/Aporte de Referido al índice/).length).toBeGreaterThan(0)
    expect(screen.getAllByText('Citas realizadas').length).toBeGreaterThan(0)
  })

  it('no inventa un 15 % cuando todavía no existe una meta publicada', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_VACIA}
        cumplimiento={null}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Sin meta', { selector: '.gi-hero-metric strong' })).toBeInTheDocument()
    expect(screen.queryByText('15%', { selector: '.gi-hero-metric strong' })).not.toBeInTheDocument()
    // F3: la meta mensual ya no se dibuja sobre la curva semanal (H12) — la
    // ausencia del 15 % se vigila en el héroe; la serie 1 ahora son cierres.
    const evolucion = screen.getByRole('img', { name: 'Prospectos por semana de ingreso y resultados' })
    expect(evolucion).toBeInTheDocument()
  })

  it('si la meta no cargó conserva el error y tampoco inventa un porcentaje', () => {
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_VACIA}
        cumplimiento={null}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false, errorCarga: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('No disponible', { selector: '.gi-hero-metric strong' })).toBeInTheDocument()
    expect(screen.getAllByText('No pudimos cargar las metas mensuales de agosto 2026.').length).toBeGreaterThan(0)
    const evolucion = screen.getByRole('img', { name: 'Prospectos por semana de ingreso y resultados' })
    expect(evolucion).toBeInTheDocument()
  })
})

describe('gráfica por origen — publicación fail-closed', () => {
  function montar(conversiones: MetricasConversiones): void {
    render(
      <ResumenGerenciaPanel
        conversiones={conversiones}
        conversionMensual={conversionMensualInteligenciaDemo(AHORA)}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={META_EQUIPO}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )
  }

  function panelOrigenes(): HTMLElement {
    const panel = screen.getByRole('heading', { name: 'Resultados por origen' }).closest('section')
    if (!(panel instanceof HTMLElement)) throw new Error('no se encontró el panel por origen')
    return panel
  }

  it('publica porcentajes del rango cuando núcleo y sondas están verificados', () => {
    montar(conOrigenesVerificados(metricasConversionesDemo('2026-08-01', '2026-08-31')))

    const panel = panelOrigenes()
    expect(within(panel).getByText('13.16%')).toBeInTheDocument()
    expect(within(panel).getByText('11.63%')).toBeInTheDocument()
    expect(within(panel).queryByRole('status')).not.toBeInTheDocument()
  })

  it.each([
    ['núcleo ausente', (datos: MetricasConversiones) => { delete datos.nucleo }],
    ['sondas ausentes', (datos: MetricasConversiones) => { delete datos.sondas }],
    ['sondas en descuadre', (datos: MetricasConversiones) => {
      if (datos.sondas) datos.sondas = { ...datos.sondas, cuadra: false, paridad_nucleo: 1 }
    }],
  ])('oculta cada porcentaje cuando %s', (_caso, degradar) => {
    const datos = conOrigenesVerificados(metricasConversionesDemo('2026-08-01', '2026-08-31'))
    degradar(datos)
    montar(datos)

    const panel = panelOrigenes()
    expect(within(panel).getByRole('status')).toHaveTextContent(
      'Cifras en revisión: los resultados por origen permanecen ocultos.',
    )
    expect(within(panel).queryByText('13.16%')).not.toBeInTheDocument()
    expect(within(panel).queryByText('11.63%')).not.toBeInTheDocument()
    expect(panel.querySelector('.gi-fill')).toBeNull()
    if (datos.nucleo != null) {
      const heroe = screen.getByText(/Conversión del rango ·/).closest('section')
      expect(heroe).toHaveTextContent('Cifras en revisión: falta verificar la conversión del rango.')
      expect(heroe).not.toHaveTextContent('23.06%')
      expect(heroe).not.toHaveTextContent('registros en la base histórica')
    }
  })

  it('una cantidad opcional de altas manuales ausente no se transforma en cero', () => {
    const datos = conOrigenesVerificados(metricasConversionesDemo('2026-08-01', '2026-08-31'))
    datos.nucleo = { ...datos.nucleo!, base: 'llegada_unica', llegadas: 185 }
    delete datos.nucleo.altas_manuales
    montar(datos)
    const heroe = screen.getByText(/Conversión del rango ·/).closest('section')
    expect(heroe).toHaveTextContent('185 prospectos recibidos')
    expect(heroe).toHaveTextContent('altas manuales no disponibles')
    expect(heroe).not.toHaveTextContent('0 manuales')
  })
})

describe('un solo número bajo un solo nombre (conversión del mes)', () => {
  // Las dos fuentes traen A PROPÓSITO números distintos: la conversión mensual
  // servida dice 20 % y el cumplimiento de metas dice 40 % (otra fórmula:
  // convertidos/RESUELTOS, sin ponderar referidos ni arrastre). Con meta 40 %,
  // el avance es 50 % si la barra mide el número que la pantalla ENSEÑA, y
  // 100 % si vuelve a medir el del cumplimiento. Esa diferencia es el test.
  function panelConFuentesDiscrepantes(conversionPct = 20, capitalMeta?: number): void {
    const mensual = conversionMensualInteligenciaDemo(AHORA)
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={{
          ...mensual,
          cobertura: { ...mensual.cobertura, medible: true },
          total: { ...mensual.total, conversion_pct: conversionPct },
        }}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={{ ...META_EQUIPO, conversionObjetivo: 40, ...(capitalMeta == null ? {} : { detalles: [{ ...META_EQUIPO.detalles[0]!, moneda: 'PEN', capitalObjetivo: capitalMeta }] }) }}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )
  }

  it('la barra de meta avanza con la conversión servida, no con la del cumplimiento', () => {
    panelConFuentesDiscrepantes()

    const barra = screen.getByText('Conversión').closest('div')
    expect(barra).not.toBeNull()
    expect(within(barra as HTMLElement).getByText('50%')).toBeInTheDocument()
    expect(within(barra as HTMLElement).queryByText('100%')).not.toBeInTheDocument()
  })

  it('conserva 150% de conversión y 200% de capital; sólo las barras terminan en100', () => {
    panelConFuentesDiscrepantes(60, 908_000)
    const conversion = screen.getByText('Conversión').parentElement
    const capital = screen.getByText('Capital').parentElement
    expect(conversion).toHaveTextContent('150%')
    expect(capital).toHaveTextContent('200%')
    expect(conversion?.parentElement?.querySelector('.gi-fill')).toHaveStyle({ width: '100%' })
    expect(capital?.parentElement?.querySelector('.gi-fill')).toHaveStyle({ width: '100%' })
  })

  it('mes no medible: la barra se calla en vez de avanzar con el otro número', () => {
    // El caso que de verdad separaba las dos fórmulas: el servidor declara que
    // el mes NO es medible (el titular degrada a «—»), pero el cumplimiento
    // sigue trayendo su 40 %. La barra debe callarse; si avanza, está midiendo
    // una conversión que la pantalla no está dispuesta a enseñar.
    const mensual = conversionMensualInteligenciaDemo(AHORA)
    render(
      <ResumenGerenciaPanel
        conversiones={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={{ ...mensual, cobertura: { ...mensual.cobertura, medible: false } }}
        reuniones={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        meta={{ ...META_EQUIPO, conversionObjetivo: 40 }}
        cumplimiento={CUMPLIMIENTO_EQUIPO}
        tc={TC_TEST}
        origenFiltrado={null}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    const barra = screen.getByText('Conversión').closest('div')
    expect(barra).not.toBeNull()
    expect(within(barra as HTMLElement).getByText('Dato no disponible')).toBeInTheDocument()
    expect(within(barra as HTMLElement).queryByText('100%')).not.toBeInTheDocument()
  })
})
