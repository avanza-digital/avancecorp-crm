import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { conversionEquipoDemo, conversionMensualInteligenciaDemo } from '@/lib/demo-inteligencia-comercial'
import { EquipoGerenciaPanel } from './equipo-gerencia'

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
    />
  ),
}))

function identidadSinMetricas() {
  return conversionEquipoDemo().map((fila) => ({
    ...fila,
    leads: 0,
    contactados: 0,
    reunionesPactadas: 0,
    reunionesRealizadas: 0,
    clientes: 0,
    descartados: 0,
    conversionPct: null,
  }))
}

describe('rendimiento de Gerencia desde la conversión mensual', () => {
  it('con fuentes combinadas conserva dos cierres y un upgrade en el total y en los equipos', () => {
    const mensual = conversionMensualInteligenciaDemo(Date.parse('2026-09-07T15:00:00Z'))
    render(<EquipoGerenciaPanel
      conversionMensual={mensual}
      conversiones={identidadSinMetricas()}
      fuenteConversion={['landing', 'upgrade']}
      lecturaFuente={{
        fuente: ['landing', 'upgrade'], etiqueta: 'Landing + Upgrade', familia: 'todos',
        periodo: { desde: '2026-09-01', hasta: '2026-09-07' },
        divisor: 36, numerador: 3, porcentaje: 8.33, resultados: 3, cierres: 2, operaciones: 1, peso: null,
        porVendedor: new Map(mensual.responsables.map((fila, indice) => [fila.vendedor_id, {
          divisor: fila.divisor, numerador: indice === 0 ? 3 : 0, porcentaje: indice === 0 ? 30 : 0,
          resultados: indice === 0 ? 3 : 0, cierres: indice === 0 ? 2 : 0, operaciones: indice === 0 ? 1 : 0,
        }])),
      }}
    />)
    const tarjeta = screen.getByText('Cierres del mes').closest('[data-gi-kpi]') as HTMLElement
    expect(within(tarjeta).getByText('2', { exact: true })).toBeInTheDocument()
    expect(within(tarjeta).getByText('+ 1 operaciones de cartera')).toBeInTheDocument()
    const maria = screen.getByText('María Salazar').closest('section')!
    expect(within(maria).getByText('2', { exact: true })).toBeInTheDocument()
    expect(within(maria).getByText('Base automática: 10 · 2 cierres + 1 operaciones')).toBeInTheDocument()
  })

  it('usa el store solo para identidad y TODOS los números vienen de la RPC mensual', () => {
    render(
      <EquipoGerenciaPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        conversiones={identidadSinMetricas()}
      />,
    )

    // Tarjetas por analista: base automática/cierres del MES, no todas las llegadas.
    expect(screen.getByText('Base automática: 10 · 4 cierres')).toBeInTheDocument()
    expect(screen.getAllByText('Base automática: 9 · 2 cierres')).toHaveLength(2)
    // KPIs servidos: divisor y cierres de la empresa, sin divisiones en cliente.
    expect(screen.getByText('Base automática')).toBeInTheDocument()
    expect(screen.getByText(/prospectos recibidos desde Landing\/Formulario/i)).toBeInTheDocument()
    expect(screen.getByText('36')).toBeInTheDocument()
    expect(screen.getByText('Cierres del mes')).toBeInTheDocument()
    // La gráfica compara solo a los MEDIBLES, ordenados por % del mes.
    const grafico = screen.getByRole('img', { name: 'Conversión por analista' })
    expect(JSON.parse(grafico.getAttribute('data-series') ?? '[]')).toEqual([
      31.5,
      22.22,
      12.78,
      12.5,
    ])
    // F3: el grupo ya NO divide en el navegador — la cabecera enseña los
    // enteros servidos (cierres protagonista, recibidos al lado). El % por
    // grupo volverá el día que lo sirva el servidor, no antes.
    const maria = screen.getByText('María Salazar').closest('section')!
    expect(within(maria).queryByText('28%')).not.toBeInTheDocument()
    expect(within(maria).getByText('6')).toBeInTheDocument()
    expect(within(maria).getByText('cierres del mes · base automática: 19')).toBeInTheDocument()
    const jose = screen.getByText('José Rivas').closest('section')!
    expect(within(jose).queryByText('18.5%')).not.toBeInTheDocument()
    expect(within(jose).getByText('cierres del mes · base automática: 17')).toBeInTheDocument()
    // Los estados sin % llevan rótulo, jamás un «0 %» inventado.
    expect(within(maria).getByText('Solo referidos')).toBeInTheDocument()
    expect(within(jose).getByText('Solo arrastre')).toBeInTheDocument()
  })

  it('sin conversión mensual expone indisponible — no rescata la fórmula vieja', () => {
    render(
      <EquipoGerenciaPanel
        conversionMensual={null}
        conversiones={identidadSinMetricas()}
      />,
    )

    expect(screen.queryByRole('img', { name: 'Conversión por analista' })).not.toBeInTheDocument()
    expect(screen.getAllByText('No disponible')).toHaveLength(conversionEquipoDemo().length)
    expect(screen.getAllByText('Datos no disponibles').length).toBeGreaterThan(0)
    // Los KPIs del mes degradan a «—», nunca a cero.
    expect(screen.getAllByText('—').length).toBeGreaterThan(0)
  })

  it('mantiene separados dos equipos aunque sus supervisores tengan el mismo nombre', () => {
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    const ids = new Set(mensual.responsables.slice(0, 2).map((fila) => fila.vendedor_id))
    const identidades = identidadSinMetricas()
      .filter((fila) => fila.vendedorId != null && ids.has(fila.vendedorId))
      .map((fila, indice) => ({
        ...fila,
        supervisorId: `supervisor-${indice + 1}`,
        supervisorNombre: 'SUPERVISIÓN HOMÓNIMA',
      }))

    render(
      <EquipoGerenciaPanel
        conversionMensual={{
          ...mensual,
          responsables: mensual.responsables.filter((fila) => ids.has(fila.vendedor_id)),
        }}
        conversiones={identidades}
      />,
    )

    const tarjeta = screen.getByText('Supervisores').closest('[data-gi-kpi]')
    expect(tarjeta).not.toBeNull()
    expect(within(tarjeta as HTMLElement).getByText('2')).toBeInTheDocument()
    expect(screen.getAllByText('SUPERVISIÓN HOMÓNIMA')).toHaveLength(2)
  })

  it('una sonda rota oculta también los KPIs globales, no solo las filas', () => {
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    render(
      <EquipoGerenciaPanel
        conversionMensual={{
          ...mensual,
          cobertura: { ...mensual.cobertura, cierres_sin_episodio: 1 },
        }}
        conversiones={identidadSinMetricas()}
      />,
    )

    for (const etiqueta of [
      'Base automática',
      'Cierres del mes',
      'Conversión del mes',
    ]) {
      const tarjeta = screen.getByText(etiqueta).closest('[data-gi-kpi]')
      expect(tarjeta).not.toBeNull()
      expect(within(tarjeta as HTMLElement).getByText('—')).toBeInTheDocument()
    }
    expect(screen.queryByRole('img', { name: 'Conversión por analista' }))
      .not.toBeInTheDocument()
    expect(screen.getAllByText('No disponible'))
      .toHaveLength(conversionEquipoDemo().length)
  })

  it('conserva la base de una foto legacy sin presentarla como llegadas automáticas', () => {
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    mensual.fuentes.divisor = 'crm.lead_asignaciones.asignado_en'
    const original = structuredClone(mensual)
    render(<EquipoGerenciaPanel conversionMensual={mensual} conversiones={identidadSinMetricas()} />)

    expect(screen.getByText('Base histórica')).toBeInTheDocument()
    expect(screen.getByText('Base histórica: 10 · 4 cierres')).toBeInTheDocument()
    expect(screen.getByText(/no equivale a prospectos recibidos/i)).toBeInTheDocument()
    expect(screen.queryByText('Base automática')).not.toBeInTheDocument()
    expect(mensual).toEqual(original)
  })
})
