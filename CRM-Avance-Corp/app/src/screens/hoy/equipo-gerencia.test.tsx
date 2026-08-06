import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { conversionEquipoDemo, metricasConversionesDemo } from '@/lib/demo-inteligencia-comercial'
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

describe('rendimiento de Gerencia desde responsables de la RPC', () => {
  it('usa el store solo para identidad aunque sus contadores estén en cero', () => {
    render(
      <EquipoGerenciaPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversiones={identidadSinMetricas()}
        miembros={MIEMBROS}
      />,
    )

    expect(screen.getByText('42 leads · 5 clientes')).toBeInTheDocument()
    expect(screen.getByText('37 leads · 4 clientes')).toBeInTheDocument()
    const grafico = screen.getByRole('img', { name: 'Conversión a clientes por vendedor' })
    expect(JSON.parse(grafico.getAttribute('data-series') ?? '[]')).toEqual([
      11.9,
      10.8,
      8.8,
      8.3,
      6.9,
      5.6,
    ])
  })

  it('expone indisponible cuando la RPC no incluye responsables', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete datos.responsables

    render(
      <EquipoGerenciaPanel
        datos={datos}
        conversiones={identidadSinMetricas()}
        miembros={MIEMBROS}
      />,
    )

    expect(screen.queryByRole('img', { name: 'Conversión a clientes por vendedor' })).not.toBeInTheDocument()
    expect(screen.getAllByText('No disponible')).toHaveLength(conversionEquipoDemo().length)
    expect(screen.getAllByText('Datos no disponibles').length).toBeGreaterThan(0)
  })
})
