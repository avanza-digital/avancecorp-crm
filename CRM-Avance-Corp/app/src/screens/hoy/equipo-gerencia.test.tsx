import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { conversionEquipoDemo, conversionMensualInteligenciaDemo } from '@/lib/demo-inteligencia-comercial'
import type { Miembro } from '@/lib/tipos'
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

const MIEMBROS: Miembro[] = [
  { perfil_id: 'demo-s1', nombre_completo: 'María Salazar', rol_crm: 'supervisor', activo: true },
  { perfil_id: 'demo-s2', nombre_completo: 'José Rivas', rol_crm: 'supervisor', activo: true },
]

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
  it('usa el store solo para identidad y TODOS los números vienen de la RPC mensual', () => {
    render(
      <EquipoGerenciaPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        conversiones={identidadSinMetricas()}
        miembros={MIEMBROS}
      />,
    )

    // Tarjetas por vendedor: recibidos/cierres del MES (identidad en cero no pisa nada).
    expect(screen.getByText('12 recibidos · 5 cierres')).toBeInTheDocument()
    expect(screen.getByText('10 recibidos · 2 cierres')).toBeInTheDocument()
    // KPIs servidos: divisor y cierres de la empresa, sin divisiones en cliente.
    expect(screen.getByText('Recibidos del mes')).toBeInTheDocument()
    expect(screen.getByText('39')).toBeInTheDocument()
    expect(screen.getByText('Cierres del mes')).toBeInTheDocument()
    // La gráfica compara solo a los MEDIBLES, ordenados por % del mes.
    const grafico = screen.getByRole('img', { name: 'Conversión a clientes por vendedor' })
    expect(JSON.parse(grafico.getAttribute('data-series') ?? '[]')).toEqual([
      34.58,
      20,
      12.78,
      12.5,
    ])
    // F3: el grupo ya NO divide en el navegador — la cabecera enseña los
    // enteros servidos (cierres protagonista, recibidos al lado). El % por
    // grupo volverá el día que lo sirva el servidor, no antes.
    const maria = screen.getByText('María Salazar').closest('section')!
    expect(within(maria).queryByText('28%')).not.toBeInTheDocument()
    expect(within(maria).getByText('7')).toBeInTheDocument()
    expect(within(maria).getByText('cierres del mes · 22 recibidos')).toBeInTheDocument()
    const jose = screen.getByText('José Rivas').closest('section')!
    expect(within(jose).queryByText('18.5%')).not.toBeInTheDocument()
    expect(within(jose).getByText('cierres del mes · 17 recibidos')).toBeInTheDocument()
    // Los estados sin % llevan rótulo, jamás un «0 %» inventado.
    expect(within(maria).getByText('Solo referidos')).toBeInTheDocument()
    expect(within(jose).getByText('Solo arrastre')).toBeInTheDocument()
  })

  it('sin conversión mensual expone indisponible — no rescata la fórmula vieja', () => {
    render(
      <EquipoGerenciaPanel
        conversionMensual={null}
        conversiones={identidadSinMetricas()}
        miembros={MIEMBROS}
      />,
    )

    expect(screen.queryByRole('img', { name: 'Conversión a clientes por vendedor' })).not.toBeInTheDocument()
    expect(screen.getAllByText('No disponible')).toHaveLength(conversionEquipoDemo().length)
    expect(screen.getAllByText('Datos no disponibles').length).toBeGreaterThan(0)
    // Los KPIs del mes degradan a «—», nunca a cero.
    expect(screen.getAllByText('—').length).toBeGreaterThan(0)
  })
})
