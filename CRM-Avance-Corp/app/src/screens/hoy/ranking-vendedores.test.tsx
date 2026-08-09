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
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
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

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))

    // TC visible y auditable en el sub-encabezado del tab.
    expect(screen.getByText(/TC S\/ 3.5 \(SBS · prom\. 7d\)/)).toBeInTheDocument()
    const tablaCapital = screen.getByRole('table', { name: 'Ranking de capital total en soles' })
    const filasCapital = within(tablaCapital).getAllByRole('row')
    expect(filasCapital).toHaveLength(3)
    // Bruno: total 290k + 16k×3.5 = 346k vs meta 180k + 30k×3.5 = 285k → 121.4% (> Ana 110.3%).
    expect(within(filasCapital[1]!).getByText('Bruno Díaz')).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByText(/121/)).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByText(/S\/ 346,000/)).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByText(/S\/ 290,000 \+ US\$ 16,000/)).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByText(/S\/ 285,000/)).toBeInTheDocument()
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
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        cargando={false}
        error={null}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.queryByRole('table', { name: 'Ranking de capital total en soles' })).not.toBeInTheDocument()
    expect(screen.queryByText(/121/)).not.toBeInTheDocument()
    expect(screen.getByText('La meta mensual de agosto 2026 no es comparable con el rango aplicado.')).toBeInTheDocument()
  })

  it('mientras el TC está en consulta muestra carga — nunca afirma «no disponible»', () => {
    render(
      <RankingVendedoresPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={undefined}
        cargando={false}
        error={null}
        onReintentar={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))

    expect(screen.getByText(/consultando tipo de cambio/)).toBeInTheDocument()
    expect(screen.queryByText(/tipo de cambio no disponible/)).not.toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'Ranking de capital total en soles' })).not.toBeInTheDocument()
  })

  it('sin tipo de cambio degrada a solo PEN con el US$ rotulado aparte', () => {
    const todasLasMetas = metasConversionEquipoDemo()
    render(
      <RankingVendedoresPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        equipo={conversionEquipoDemo()}
        metasVendedores={{ 'demo-v2': todasLasMetas['demo-v2']! }}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        cargando={false}
        error={null}
        onReintentar={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))

    expect(screen.getByText(/US\$ aparte: tipo de cambio no disponible/)).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Ranking de capital total en soles' })
    const filas = within(tabla).getAllByRole('row')
    // Bruno solo-PEN: 290k vs meta 180k → 161.1%; su US$ va aparte, no dentro del total.
    expect(within(filas[1]!).getByText('Bruno Díaz')).toBeInTheDocument()
    expect(within(filas[1]!).getByText(/161/)).toBeInTheDocument()
    expect(within(filas[1]!).getByText(/S\/ 290,000/)).toBeInTheDocument()
    expect(within(filas[1]!).getByText(/\+ US\$ 16,000 aparte \(sin TC\)/)).toBeInTheDocument()
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
        tc={null}
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
