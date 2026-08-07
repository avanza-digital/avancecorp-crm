import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import type { ObjetivosPorVendedor } from '@/lib/objetivos'
import { RankingVendedoresPanel } from './ranking-vendedores'

describe('ranking general de vendedores', () => {
  it('muestra cualquier cantidad de vendedores, incluidos los que aún no tienen leads', () => {
    const sinLeads: ConversionEquipoVendedor = {
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
    }
    const sinAsignar: ConversionEquipoVendedor = {
      ...sinLeads,
      vendedorId: null,
      nombre: 'Sin vendedor asignado',
      leads: 8,
      conversionPct: 0,
    }
    const todasLasMetas = metasConversionEquipoDemo()
    const metas: ObjetivosPorVendedor = {
      'demo-v1': todasLasMetas['demo-v1']!,
      'demo-v2': todasLasMetas['demo-v2']!,
    }
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor

    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    datos.responsables?.push({
      vendedor_id: 'demo-v7',
      leads: 0,
      contactados: 0,
      reuniones_realizadas: 0,
      clientes: 0,
      conversion_pct: null,
      capital_pen: 0,
      capital_usd: 0,
      tendencia_semanal: [],
    })

    const { rerender } = render(
      <RankingVendedoresPanel
        datos={datos}
        equipo={[...conversionEquipoDemo(), sinLeads, sinAsignar]}
        metasVendedores={metas}
        cumplimientoVendedores={cumplimientos}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByText('7 vendedores · sin límite fijo de participantes')).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Ranking de conversión general' })
    const filas = within(tabla).getAllByRole('row')
    expect(filas).toHaveLength(7)
    expect(within(filas[1]!).getByText('Ana Torres')).toBeInTheDocument()
    expect(within(tabla).queryByText('Gabriela Soto')).not.toBeInTheDocument()
    expect(within(tabla).queryByText('Sin vendedor asignado')).not.toBeInTheDocument()
    const fueraConversion = screen.getByRole('region', { name: 'Vendedores sin posición en conversión' })
    expect(within(fueraConversion).getByText('Gabriela Soto')).toBeInTheDocument()
    expect(within(fueraConversion).getByText('Sin muestra')).toBeInTheDocument()
    expect(within(fueraConversion).queryByLabelText(/Puesto/)).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Capital PEN' }))

    const tablaCapital = screen.getByRole('table', { name: 'Ranking de meta de capital PEN' })
    const filasCapital = within(tablaCapital).getAllByRole('row')
    expect(filasCapital).toHaveLength(3)
    expect(within(filasCapital[1]!).getByText('Bruno Díaz')).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByText(/161/)).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByText(/S\/ 290,000/)).toBeInTheDocument()
    expect(within(tablaCapital).queryByText('Gabriela Soto')).not.toBeInTheDocument()
    expect(within(tablaCapital).queryByText('Sin vendedor asignado')).not.toBeInTheDocument()
    const fueraCapital = screen.getByRole('region', { name: 'Vendedores sin posición en capital' })
    expect(within(fueraCapital).getByText('Gabriela Soto')).toBeInTheDocument()
    expect(within(fueraCapital).getAllByText('Sin meta').length).toBeGreaterThan(0)
    expect(within(fueraCapital).queryByLabelText(/Puesto/)).not.toBeInTheDocument()

    rerender(
      <RankingVendedoresPanel
        datos={metricasConversionesDemo('2026-07-01', '2026-07-31')}
        equipo={[...conversionEquipoDemo(), sinLeads, sinAsignar]}
        metasVendedores={metas}
        cumplimientoVendedores={cumplimientos}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false }}
        cargando={false}
        error={null}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.queryByRole('table', { name: 'Ranking de meta de capital PEN' })).not.toBeInTheDocument()
    expect(screen.queryByText(/161/)).not.toBeInTheDocument()
    expect(screen.getByText('La meta mensual de agosto 2026 no es comparable con el rango aplicado.')).toBeInTheDocument()
  })

  it('no sustituye una RPC sin responsables con los contadores operativos del equipo', () => {
    const datos = metricasConversionesDemo('2026-08-01', '2026-08-31')
    delete datos.responsables

    render(
      <RankingVendedoresPanel
        datos={datos}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        cargando={false}
        error={null}
        onReintentar={vi.fn()}
      />,
    )

    const tabla = screen.getByRole('table', { name: 'Ranking de conversión general' })
    expect(within(tabla).getAllByRole('row')).toHaveLength(1)
    const fuera = screen.getByRole('region', { name: 'Vendedores sin posición en conversión' })
    expect(within(fuera).getAllByText('No disponible')).toHaveLength(conversionEquipoDemo().length)
    expect(within(fuera).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
  })
})
