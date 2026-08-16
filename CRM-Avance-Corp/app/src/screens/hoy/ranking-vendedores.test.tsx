import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  conversionMensualInteligenciaDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
} from '@/lib/demo-inteligencia-comercial'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import type { ResponsableConversionMensual } from '@/lib/conversion-mensual'
import type { ObjetivosPorVendedor } from '@/lib/objetivos'
import { RankingVendedoresPanel } from './ranking-vendedores'

/** Fila mensual sin actividad — el roster real siempre trae UNA fila por analista. */
function filaSinActividad(vendedorId: string): ResponsableConversionMensual {
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
    // El tab de conversión bebe de la MENSUAL: mismo roster que `equipo` (el
    // fail-closed exige una fila por identidad visible, como la RPC real).
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    mensual.responsables.push(filaSinActividad('demo-v7'))
    // Ana arrastra una anulación de julio: su % ya llega NETO del servidor y
    // el descuento se dice al lado — un ranking que «baja solo» no se cree.
    const ana = mensual.responsables.find((fila) => fila.vendedor_id === 'demo-v1')
    if (ana) {
      ana.ajuste = {
        pendiente: 1,
        origenes: [{ periodo: '2026-07', motivo: 'Cierre anulado por gerencia', numerador: 1 }],
      }
    }

    const { rerender } = render(
      <RankingVendedoresPanel
        datos={datos}
        conversionMensual={mensual}
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
    expect(screen.getByText('Cierres del mes (referidos al 15 %) ÷ leads recibidos en el mes')).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Ranking de conversión general' })
    // Columnas de la conversión MENSUAL: recibidos del mes y cierres — no los
    // rótulos del payload viejo (Leads/Clientes medían el rango completo).
    expect(within(tabla).getByRole('columnheader', { name: 'Recibidos' })).toBeInTheDocument()
    expect(within(tabla).getByRole('columnheader', { name: 'Cierres' })).toBeInTheDocument()
    const filas = within(tabla).getAllByRole('row')
    // 1 cabecera + 4 medibles + Fabio (solo arrastre: compite al fondo, sin %).
    expect(filas).toHaveLength(6)
    const filaAna = filas[1]!
    expect(within(filaAna).getByText('Ana Torres')).toBeInTheDocument()
    expect(within(filaAna).getByText('12')).toBeInTheDocument()
    expect(within(filaAna).getByText('5')).toBeInTheDocument()
    // 4.15 ÷ 12 — el numerador pondera el referido al 15 %, no cuenta 5/12.
    expect(within(filaAna).getByText('34.6%')).toBeInTheDocument()
    // El descuento con su porqué, debajo del % que rebaja.
    expect(within(filaAna).getByText('arrastra 1 conversión de anulaciones · julio 2026')).toBeInTheDocument()
    expect(within(filaAna).getByTitle('julio 2026: Cierre anulado por gerencia (−1)')).toBeInTheDocument()
    const filaFabio = filas[5]!
    expect(within(filaFabio).getByText('Fabio León')).toBeInTheDocument()
    expect(within(filaFabio).getByText('—')).toBeInTheDocument()
    expect(within(filaFabio).getByText('Solo cierres de arrastre')).toBeInTheDocument()
    expect(within(tabla).queryByText('Gabriela Soto')).not.toBeInTheDocument()
    expect(within(tabla).queryByText('Sin vendedor asignado')).not.toBeInTheDocument()
    const fueraConversion = screen.getByRole('region', { name: 'Vendedores sin posición en conversión' })
    expect(within(fueraConversion).getByText('Gabriela Soto')).toBeInTheDocument()
    expect(within(fueraConversion).getByText('Sin muestra')).toBeInTheDocument()
    // Elena trabajó (recibió referidos): rótulo PROPIO, jamás «Sin muestra».
    expect(within(fueraConversion).getByText('Elena Vega')).toBeInTheDocument()
    expect(within(fueraConversion).getByText('Solo recibió referidos')).toBeInTheDocument()
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
        conversionMensual={mensual}
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
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
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
    const onReintentar = vi.fn()
    render(
      <RankingVendedoresPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={conversionEquipoDemo()}
        metasVendedores={{ 'demo-v2': todasLasMetas['demo-v2']! }}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        cargando={false}
        error={null}
        onReintentar={onReintentar}
      />,
    )

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))

    expect(screen.getByText(/US\$ aparte: tipo de cambio no disponible/)).toBeInTheDocument()

    // Un fallo AISLADO del TC tiene su propia vía de recuperación (hallazgo Codex).
    fireEvent.click(screen.getByRole('button', { name: /Reintentar tipo de cambio/ }))
    expect(onReintentar).toHaveBeenCalledTimes(1)
    const tabla = screen.getByRole('table', { name: 'Ranking de capital total en soles' })
    const filas = within(tabla).getAllByRole('row')
    // Bruno solo-PEN: 290k vs meta 180k → 161.1%; su US$ va aparte, no dentro del total.
    expect(within(filas[1]!).getByText('Bruno Díaz')).toBeInTheDocument()
    expect(within(filas[1]!).getByText(/161/)).toBeInTheDocument()
    expect(within(filas[1]!).getByText(/S\/ 290,000/)).toBeInTheDocument()
    expect(within(filas[1]!).getByText(/\+ US\$ 16,000 aparte \(sin TC\)/)).toBeInTheDocument()
  })

  it('sin conversión mensual el tab queda «No disponible» — JAMÁS sirve la fórmula vieja', () => {
    // El payload viejo llega COMPLETO (responsables incluidos) a propósito:
    // si el tab lo usara de fallback, aquí habría tabla con puestos. La
    // fórmula del rango bajo el rótulo mensual es la mentira que se elimina.
    render(
      <RankingVendedoresPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={null}
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

  it('mientras la conversión mensual está en consulta muestra carga, no «No disponible»', () => {
    render(
      <RankingVendedoresPanel
        datos={metricasConversionesDemo('2026-08-01', '2026-08-31')}
        conversionMensual={undefined}
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

    expect(screen.queryByText('No disponible')).not.toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'Ranking de conversión general' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Vendedores sin posición en conversión' })).not.toBeInTheDocument()
  })
})
