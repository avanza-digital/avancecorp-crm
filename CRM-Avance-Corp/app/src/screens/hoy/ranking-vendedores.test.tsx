import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import {
  conversionEquipoDemo,
  conversionMensualInteligenciaDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
} from '@/lib/demo-inteligencia-comercial'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import type { ResponsableConversionMensual } from '@/lib/conversion-mensual'
import type { MetricasConversionesEquipo } from '@/lib/metricas-conversiones-equipo'
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

function fuentesRankingSinError() {
  return {
    conversionError: null,
    onReintentarConversion: vi.fn(),
    cosechaCargando: false,
    cosechaError: null,
    onReintentarCosecha: vi.fn(),
    capitalError: null,
    onReintentarCapital: vi.fn(),
  }
}

describe('ranking general de analistas', () => {
  it('muestra cualquier cantidad de analistas, incluidos los que aún no tienen leads', () => {
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
      nombre: 'Sin analista asignado',
      leads: 8,
      conversionPct: 0,
    }
    const todasLasMetas = metasConversionEquipoDemo()
    const metas: ObjetivosPorVendedor = {
      'demo-v1': todasLasMetas['demo-v1']!,
      'demo-v2': todasLasMetas['demo-v2']!,
    }
    const cumplimientos = cumplimientoMetasConversionEquipoDemo().porVendedor

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
        conversionMensual={mensual}
        equipo={[...conversionEquipoDemo(), sinLeads, sinAsignar]}
        metasVendedores={metas}
        cumplimientoVendedores={cumplimientos}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('7 analistas · sin límite fijo de participantes')).toBeInTheDocument()
    expect(screen.getByText('Mes calendario · agosto 2026')).toBeInTheDocument()
    expect(screen.getByText('(Cierres no referidos + referidos ×0.15 + operaciones de cartera) ÷ leads no referidos recibidos en el mes')).toBeInTheDocument()
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
    expect(within(filaAna).getByText('34.58%')).toBeInTheDocument()
    // El descuento con su porqué, debajo del % que rebaja.
    expect(within(filaAna).getByText('arrastra 1 conversión de anulaciones · julio 2026')).toBeInTheDocument()
    expect(within(filaAna).getByTitle('julio 2026: Cierre anulado por gerencia (−1)')).toBeInTheDocument()
    const filaFabio = filas[5]!
    expect(within(filaFabio).getByText('Fabio León')).toBeInTheDocument()
    expect(within(filaFabio).getByText('—')).toBeInTheDocument()
    expect(within(filaFabio).getByText('Solo cierres de arrastre')).toBeInTheDocument()
    expect(within(tabla).queryByText('Gabriela Soto')).not.toBeInTheDocument()
    expect(within(tabla).queryByText('Sin analista asignado')).not.toBeInTheDocument()
    const fueraConversion = screen.getByRole('region', { name: 'Analistas sin posición en conversión' })
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
    expect(within(tablaCapital).queryByText('Sin analista asignado')).not.toBeInTheDocument()
    const fueraCapital = screen.getByRole('region', { name: 'Analistas sin posición en capital' })
    expect(within(fueraCapital).getByText('Gabriela Soto')).toBeInTheDocument()
    expect(within(fueraCapital).getAllByText('Sin meta').length).toBeGreaterThan(0)
    expect(within(fueraCapital).queryByLabelText(/Puesto/)).not.toBeInTheDocument()

    rerender(
      <RankingVendedoresPanel
        conversionMensual={mensual}
        equipo={[...conversionEquipoDemo(), sinLeads, sinAsignar]}
        metasVendedores={metas}
        cumplimientoVendedores={cumplimientos}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false }}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.queryByRole('table', { name: 'Ranking de capital total en soles' })).not.toBeInTheDocument()
    expect(screen.queryByText(/121/)).not.toBeInTheDocument()
    expect(screen.getByText('La meta mensual de agosto 2026 no es comparable con el rango aplicado.')).toBeInTheDocument()
  })

  it('mientras el TC está en consulta muestra carga — nunca afirma «no disponible»', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={conversionEquipoDemo()}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={undefined}
        {...fuentesRankingSinError()}
      />,
    )

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))

    expect(screen.getByText(/consultando tipo de cambio/)).toBeInTheDocument()
    expect(screen.queryByText(/tipo de cambio no disponible/)).not.toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'Ranking de capital total en soles' })).not.toBeInTheDocument()
  })

  it('mientras llega la foto mensual bloquea las tres pestañas, sin identidades ni ceros falsos', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        fotoMensualCargando
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        tabInicial="capital-total"
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('Consultando identidad, metas y capital del mes…')).toBeInTheDocument()
    expect(screen.getByText('— analistas · sin límite fijo de participantes')).toBeInTheDocument()
    expect(screen.queryByText('Sin meta')).not.toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'Ranking de capital total en soles' })).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Conversión general' }))
    expect(screen.getByText('Consultando identidad, metas y capital del mes…')).toBeInTheDocument()
    expect(screen.queryByText('Analista no identificado')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Cosecha del lote' }))
    expect(screen.getByText('Consultando identidad, metas y capital del mes…')).toBeInTheDocument()
    expect(screen.queryByText('Analista no identificado')).not.toBeInTheDocument()
  })

  it('si falla la foto mensual, las tres pestañas fallan cerradas y reintentan esa misma fuente', () => {
    const reintentarFoto = vi.fn()
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: false, errorCarga: true }}
        fotoMensualError="No se pudo cargar la foto mensual."
        onReintentarFotoMensual={reintentarFoto}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    for (const tab of ['Conversión general', 'Capital total', 'Cosecha del lote']) {
      fireEvent.click(screen.getByRole('tab', { name: tab }))
      expect(screen.getByRole('alert')).toHaveTextContent('No se pudo cargar la foto mensual.')
      fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    }
    expect(screen.getByText('— analistas · sin límite fijo de participantes')).toBeInTheDocument()
    expect(reintentarFoto).toHaveBeenCalledTimes(3)
  })

  it('en un mes cerrado usa la identidad de la foto aunque el roster vivo haya cambiado', () => {
    const cumplimiento = cumplimientoMetasConversionEquipoDemo().porVendedor
    const altaPosterior: ConversionEquipoVendedor = {
      vendedorId: 'demo-v7',
      nombre: 'Alta de setiembre',
      supervisorNombre: 'Equipo actual',
      leads: 0,
      contactados: 0,
      reunionesPactadas: 0,
      reunionesRealizadas: 0,
      clientes: 0,
      descartados: 0,
      conversionPct: null,
    }
    const rosterVivo = [
      ...conversionEquipoDemo().map((fila) => (
        fila.vendedorId === 'demo-v1'
          ? { ...fila, nombre: 'Nombre actual', supervisorNombre: 'Equipo actual' }
          : fila
      )),
      altaPosterior,
    ]
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={rosterVivo}
        metasVendedores={cumplimiento}
        cumplimientoVendedores={cumplimiento}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        usarIdentidadSnapshot
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByRole('table', { name: 'Ranking de conversión general' }))
      .toHaveTextContent('Ana Torres')
    expect(screen.queryByText('Nombre actual')).not.toBeInTheDocument()
    expect(screen.queryByText('Alta de setiembre')).not.toBeInTheDocument()
    expect(screen.getByRole('table', { name: 'Ranking de conversión general' }))
      .toHaveTextContent('34.58%')

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))
    expect(screen.queryByText('Alta de setiembre')).not.toBeInTheDocument()
  })

  it('en el mes vigente conserva un alta del roster aunque todavía no tenga meta ni capital', () => {
    const altaVigente: ConversionEquipoVendedor = {
      vendedorId: 'alta-vigente',
      nombre: 'Alta vigente',
      supervisorNombre: 'Equipo actual',
      leads: 0,
      contactados: 0,
      reunionesPactadas: 0,
      reunionesRealizadas: 0,
      clientes: 0,
      descartados: 0,
      conversionPct: null,
    }
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    mensual.responsables.push(filaSinActividad('alta-vigente'))

    render(
      <RankingVendedoresPanel
        conversionMensual={mensual}
        equipo={[...conversionEquipoDemo(), altaVigente]}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'setiembre 2026', comparable: true }}
        usarIdentidadSnapshot={false}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    const fueraConversion = screen.getByRole('region', { name: 'Analistas sin posición en conversión' })
    const altaConversion = within(fueraConversion).getByText('Alta vigente').closest('li')
    expect(altaConversion).not.toBeNull()
    expect(within(altaConversion!).getByText('Sin muestra')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))

    const altaCapital = screen.getByText('Alta vigente').closest('li')
    expect(altaCapital).not.toBeNull()
    expect(within(altaCapital!).getByText('Capital no disponible')).toBeInTheDocument()
    expect(within(altaCapital!).getByText('No disponible')).toBeInTheDocument()
    expect(within(altaCapital!).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
  })

  it('sin tipo de cambio degrada a solo PEN con el US$ rotulado aparte', () => {
    const todasLasMetas = metasConversionEquipoDemo()
    const onReintentar = vi.fn()
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={conversionEquipoDemo()}
        metasVendedores={{ 'demo-v2': todasLasMetas['demo-v2']! }}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        {...fuentesRankingSinError()}
        onReintentarCapital={onReintentar}
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
    // Sin el payload mensual no existe fallback: la fórmula del rango bajo el
    // rótulo mensual sería una mentira.
    render(
      <RankingVendedoresPanel
        conversionMensual={null}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        {...fuentesRankingSinError()}
      />,
    )

    const tabla = screen.getByRole('table', { name: 'Ranking de conversión general' })
    expect(within(tabla).getAllByRole('row')).toHaveLength(1)
    const fuera = screen.getByRole('region', { name: 'Analistas sin posición en conversión' })
    expect(within(fuera).getAllByText('No disponible')).toHaveLength(conversionEquipoDemo().length)
    expect(within(fuera).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
  })

  it('mientras la conversión mensual está en consulta muestra carga, no «No disponible»', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={undefined}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.queryByText('No disponible')).not.toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'Ranking de conversión general' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Analistas sin posición en conversión' })).not.toBeInTheDocument()
  })

  it('con el roster aún vacío mantiene el estado de carga en vez de afirmar que no hay analistas', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={undefined}
        equipo={[]}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('Consultando la conversión del mes…')).toBeInTheDocument()
    expect(screen.queryByText('Aún no hay analistas para mostrar')).not.toBeInTheDocument()
  })
})

describe('aislamiento de las fuentes del ranking', () => {
  it('si falla conversión, Capital total sigue operativo y el reintento llama solo a conversión', () => {
    const reintentarConversion = vi.fn()
    const reintentarCapital = vi.fn()

    render(
      <RankingVendedoresPanel
        conversionMensual={undefined}
        conversionError="No se pudo calcular la conversión mensual."
        onReintentarConversion={reintentarConversion}
        cosecha={undefined}
        cosechaCargando={false}
        cosechaError={null}
        onReintentarCosecha={vi.fn()}
        equipo={conversionEquipoDemo()}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        capitalError={null}
        onReintentarCapital={reintentarCapital}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        tabInicial="capital-total"
      />,
    )

    expect(screen.getByRole('table', { name: 'Ranking de capital total en soles' })).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Conversión general' }))
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo calcular la conversión mensual.')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(reintentarConversion).toHaveBeenCalledTimes(1)
    expect(reintentarCapital).not.toHaveBeenCalled()
  })

  it('si falla Capital total, la conversión del núcleo sigue visible', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        conversionError={null}
        onReintentarConversion={vi.fn()}
        cosecha={undefined}
        cosechaCargando={false}
        cosechaError={null}
        onReintentarCosecha={vi.fn()}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        capitalError="No se pudo calcular el capital confirmado."
        onReintentarCapital={vi.fn()}
        tc={null}
      />,
    )

    expect(screen.getByRole('table', { name: 'Ranking de conversión general' })).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo calcular el capital confirmado.')
  })

  it('si falla Cosecha, las otras pestañas siguen operativas y su reintento es exclusivo', () => {
    const reintentarCosecha = vi.fn()
    const reintentarConversion = vi.fn()

    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        conversionError={null}
        onReintentarConversion={reintentarConversion}
        cosecha={undefined}
        cosechaCargando={false}
        cosechaError="No se pudo calcular la cosecha del lote."
        onReintentarCosecha={reintentarCosecha}
        equipo={conversionEquipoDemo()}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        capitalError={null}
        onReintentarCapital={vi.fn()}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
      />,
    )

    expect(screen.getByRole('table', { name: 'Ranking de conversión general' })).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Cosecha del lote' }))
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo calcular la cosecha del lote.')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(reintentarCosecha).toHaveBeenCalledTimes(1)
    expect(reintentarConversion).not.toHaveBeenCalled()
  })
})

describe('la relación pestaña↔panel sobrevive a error y a vacío (observación #6)', () => {
  const base = {
    conversionMensual: null,
    equipo: [],
    metasVendedores: {},
    cumplimientoVendedores: {},
    metaMensual: { etiqueta: 'agosto 2026', comparable: true as const },
    tc: null,
    ...fuentesRankingSinError(),
  }

  it('en ERROR, el tabpanel que los tabs prometen sigue existiendo', () => {
    render(<RankingVendedoresPanel {...base} conversionError="No se pudo calcular la conversión mensual." />)

    const panel = screen.getByRole('tabpanel')
    expect(panel).toHaveAttribute('id', 'panel-ranking-conversion')
    expect(panel).toHaveAttribute('aria-labelledby', 'tab-ranking-conversion')
    expect(within(panel).getByRole('alert')).toHaveTextContent('No se pudo calcular la conversión mensual.')
  })

  it('en VACÍO también — y con el id de la pestaña ACTIVA', () => {
    render(<RankingVendedoresPanel {...base} tabInicial="capital-total" />)

    const panel = screen.getByRole('tabpanel')
    expect(panel).toHaveAttribute('id', 'panel-ranking-capital')
    expect(panel).toHaveAttribute('aria-labelledby', 'tab-ranking-capital-total')
    expect(within(panel).getByText('Aún no hay analistas para mostrar')).toBeInTheDocument()
  })
})

describe('la lectura por cosecha del ranking (F2.2/D2 — metricas_conversiones_equipo_fn)', () => {
  function cosechaDemo(
    cuadra: boolean | null = true,
    paridadNucleo: number | null = cuadra === false ? 2.5 : 0,
  ): MetricasConversionesEquipo {
    return {
      version: 1 as const,
      generado_en: '2026-08-27T12:00:00Z',
      alcance: 'global' as const,
      periodo: { desde: '2026-08-01', hasta: '2026-08-27' },
      responsables: [
        { vendedor_id: 'demo-v1', leads: 38, clientes: 5, conversion_pct: 13.2 },
      ],
      nucleo: { base: 'asignacion', incluye_cartera: true, peso_referido: 0.15, mes_peso: '2026-08-01' },
      sondas: {
        cuadra,
        paridad_nucleo: paridadNucleo,
        paridad_filas: 9,
        divisor_fuera_del_roster: 0,
        numerador_fuera_del_roster: 0,
        cierres_anulados: 0,
        clientes_acreditados_a_otro_dueno: 0,
      },
    }
  }

  function montar(
    cosecha: MetricasConversionesEquipo | null | undefined,
    cosechaCargando = false,
  ) {
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        cosecha={cosecha}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        {...fuentesRankingSinError()}
        cosechaCargando={cosechaCargando}
      />,
    )
  }

  const abrirCosecha = () => fireEvent.click(screen.getByRole('tab', { name: 'Cosecha del lote' }))

  it('vive en SU pestaña, no en las filas del ranking (pedido de Miguel: dos relojes juntos eran ruido)', () => {
    montar(cosechaDemo())
    // En el tab de conversión NO hay ni rastro de la cosecha…
    expect(screen.queryByText(/leads del mes/)).not.toBeInTheDocument()
    // …y en su pestaña sí, en idioma de negocio, SOLO para quien tiene fila.
    abrirCosecha()
    const panel = screen.getByRole('tabpanel')
    expect(within(panel).getByText('De sus 38 leads del mes, 5 ya son clientes (13.20%)')).toBeInTheDocument()
    expect(within(panel).queryAllByText(/leads del mes, ninguno/)).toHaveLength(0)
  })

  it('con cero cierres lo dice con palabras («ninguno es cliente todavía»), sin un (0%) que estorbe', () => {
    const cosecha = cosechaDemo()
    cosecha.responsables = [{ vendedor_id: 'demo-v1', leads: 41, clientes: 0, conversion_pct: 0 }]
    montar(cosecha)
    abrirCosecha()
    expect(screen.getByText('De sus 41 leads del mes, ninguno es cliente todavía')).toBeInTheDocument()
  })

  it('sin payload la pestaña lo DICE («no disponible por ahora») — jamás un cero fabricado', () => {
    montar(undefined)
    abrirCosecha()
    expect(screen.getByText('Seguimiento del lote no disponible por ahora.')).toBeInTheDocument()
    expect(screen.queryByText(/leads del mes/)).not.toBeInTheDocument()
  })

  it('mientras consulta la cosecha mantiene carga y no afirma que está indisponible', () => {
    montar(undefined, true)
    abrirCosecha()
    expect(screen.getByText('Consultando la cosecha del lote…')).toBeInTheDocument()
    expect(screen.queryByText('Seguimiento del lote no disponible por ahora.')).not.toBeInTheDocument()
  })

  it('F3.4: con la sonda en falso la pestaña entera se OCULTA y se avisa', () => {
    montar(cosechaDemo(false))
    abrirCosecha()
    expect(screen.queryByText(/leads del mes/)).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Lectura por cosecha en revisión')
  })

  it.each([
    ['cuadra=true pero paridad_nucleo!=0', () => cosechaDemo(true, 0.01)],
    ['cuadra=null', () => cosechaDemo(null, 0)],
    ['paridad_nucleo=null', () => cosechaDemo(true, null)],
    ['sondas ausentes', () => {
      const { sondas: _omitidas, ...sinSondas } = cosechaDemo()
      return sinSondas
    }],
  ])('F3.4 fail-closed: %s no deja publicar la cosecha', (_caso, crear) => {
    montar(crear())
    abrirCosecha()
    expect(screen.queryByText(/leads del mes/)).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('verificación interna no está confirmada')
  })
})

describe('el desglose de cartera por fila (hallazgo de Grecia, 27/08)', () => {
  it('un % positivo con cero cierres DICE que los puntos vienen de cartera', () => {
    // El caso real: 0 cierres de leads, 4 upgrades de cartera, 9,3 %.
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    const primera = mensual.responsables[0]!
    primera.cierres_no_referidos = 0
    primera.cierres_referidos = 0
    primera.numerador = 4
    primera.conversion_pct = 9.3
    primera.cartera = {
      conversiones_clientes: 4,
      conversiones_renovacion: 0,
      conversiones_upgrade: 4,
      capital_renovado_pen: 0,
      capital_renovado_usd: 0,
      capital_adicional_pen: 0,
      capital_adicional_usd: 0,
      renovaciones_sin_desglose: 0,
    }

    render(
      <RankingVendedoresPanel
        conversionMensual={mensual}
        equipo={conversionEquipoDemo()}
        metasVendedores={{}}
        cumplimientoVendedores={{}}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={null}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getAllByText('0 cierres + 4 de cartera').length).toBeGreaterThanOrEqual(1)
    expect(screen.getAllByText('9.30%').length).toBeGreaterThanOrEqual(1)
    // Las filas SIN operaciones de cartera no ganan la línea: sin ruido.
    expect(screen.queryByText(/\+ 0 de cartera/)).not.toBeInTheDocument()
  })
})
