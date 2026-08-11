import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  conversionMensualInteligenciaDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import { numero } from '@/lib/format'
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

function conversionesSinActividad(): MetricasConversiones {
  const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
  return {
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
  }
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

describe('ranking general de vendedores', () => {
  it('abre la página completa de ranking desde la tarjeta de mejores vendedores', () => {
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
        nombre: 'Sin vendedor asignado',
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
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.queryByText('Fabio León')).not.toBeInTheDocument()

    const enlace = screen.getByRole('link', { name: 'Ver ranking general de vendedores' })
    expect(enlace).toHaveAttribute('href', '#/ranking-vendedores')
    const evolucion = screen.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' })
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
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Detalle por vendedor no disponible')).toBeInTheDocument()
    expect(screen.getByText('Tendencia no disponible')).toBeInTheDocument()
    expect(screen.queryByText('Aún no hay vendedores con leads en este período')).not.toBeInTheDocument()
  })
})

describe('estados vacíos del resumen de Gerencia', () => {
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
    expect(screen.getAllByText('Reuniones realizadas').length).toBeGreaterThan(0)
    expect(screen.getByText('Aún no hay conversiones para mostrar')).toBeInTheDocument()
    expect(screen.getByText('Aún no hay vendedores medibles este mes')).toBeInTheDocument()
    expect(screen.getByText('Aún no hay orígenes con leads en este período')).toBeInTheDocument()
    expect(screen.getByText('Sin capital confirmado')).toBeInTheDocument()
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
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error="No se pudieron cargar las reuniones."
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las reuniones.')
    // El héroe y el KPI dicen LA conversión del MES — la del rango vive en Conversiones.
    const pctMes = `${numero(conversionMensualInteligenciaDemo(AHORA).total.conversion_pct!, 1)}%`
    expect(screen.getAllByText(pctMes).length).toBeGreaterThan(0)
    // 11 = 9 no referidos + 2 referidos (los referidos cierran, no dividen).
    expect(screen.getByText('11 cierres de 39 recibidos este mes')).toBeInTheDocument()
    const tarjetaReuniones = screen.getByText('Reuniones realizadas').closest('[data-gi-kpi]')
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
})

describe('meta publicada de conversión en el resumen de Gerencia', () => {
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
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('Sin meta', { selector: '.gi-hero-metric strong' })).toBeInTheDocument()
    expect(screen.queryByText('15%', { selector: '.gi-hero-metric strong' })).not.toBeInTheDocument()
    const evolucion = screen.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' })
    expect(JSON.parse(evolucion.getAttribute('data-meta-series') ?? '[]')).toEqual([])
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
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false, errorCarga: true }}
        cargando={false}
        error={null}
        modoDemo={false}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('No disponible', { selector: '.gi-hero-metric strong' })).toBeInTheDocument()
    expect(screen.getAllByText('No pudimos cargar las metas mensuales de agosto 2026.').length).toBeGreaterThan(0)
    const evolucion = screen.getByRole('img', { name: 'Evolución semanal de la conversión a clientes en el rango aplicado' })
    expect(JSON.parse(evolucion.getAttribute('data-meta-series') ?? '[]')).toEqual([])
  })
})
