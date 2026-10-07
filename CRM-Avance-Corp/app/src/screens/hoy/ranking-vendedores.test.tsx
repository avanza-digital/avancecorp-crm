import { fireEvent, render as renderConPruebas, screen, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
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
import type { ObjetivosPorVendedor, ProduccionFueraRanking } from '@/lib/objetivos'
import { clasificarRankingCapitalTotal } from '@/lib/conversion-vendedores'
import type { RankingOrigenVendedor } from '@/lib/ranking-origen'
import { RankingVendedoresPanel } from './ranking-vendedores'
import { DetalleCapitalRanking } from './ranking-detalle'

function render(elemento: Parameters<typeof renderConPruebas>[0]) {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return renderConPruebas(elemento, {
    wrapper: ({ children }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>,
  })
}

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

describe('consulta de Ranking F1', () => {
  const datos = () => ({
    conversionMensual: conversionMensualInteligenciaDemo(Date.now()),
    equipo: conversionEquipoDemo(),
    metasVendedores: metasConversionEquipoDemo(),
    cumplimientoVendedores: cumplimientoMetasConversionEquipoDemo().porVendedor,
    metaMensual: { etiqueta: 'setiembre 2026', comparable: true },
    tc: { promedio: 3.751, fuente: 'demo · prom. 7d' },
    ...fuentesRankingSinError(),
  })

  it('permite recorrer las pestañas con teclado y mantiene todos los destinos ARIA', () => {
    render(<RankingVendedoresPanel {...datos()} />)
    const conversion = screen.getByRole('tab', { name: 'Conversión general' })
    const capital = screen.getByRole('tab', { name: 'Capital total' })
    const cosecha = screen.getByRole('tab', { name: 'Resultados de los leads del mes' })
    for (const tab of [conversion, capital, cosecha]) {
      expect(document.getElementById(tab.getAttribute('aria-controls')!)).toBeInTheDocument()
    }
    fireEvent.keyDown(conversion, { key: 'ArrowRight' })
    expect(capital).toHaveFocus()
    expect(capital).toHaveAttribute('aria-selected', 'true')
    expect(conversion).toHaveAttribute('tabindex', '-1')
    fireEvent.keyDown(capital, { key: 'End' })
    expect(cosecha).toHaveFocus()
    fireEvent.keyDown(cosecha, { key: 'Home' })
    expect(conversion).toHaveFocus()
  })

  it('abre el capital de la misma fila y envía la identidad real a Conversiones', () => {
    const props = datos()
    const original = structuredClone(props.cumplimientoVendedores)
    const abrirConversiones = vi.fn()
    render(<RankingVendedoresPanel {...props} tipoSeleccionado="capital-total" onAbrirConversiones={abrirConversiones} />)
    fireEvent.click(screen.getAllByRole('button', { name: 'Ver detalle de Carla Mendoza' })[0]!)
    const detalle = screen.getByRole('dialog', { name: 'Carla Mendoza' })
    const resumen = detalle.querySelector('dl')!
    for (const cifra of ['S/ 317,518', 'S/ 250,024', '127.00%']) {
      expect(within(resumen).getByText(cifra)).toBeInTheDocument()
    }
    const origenes = within(detalle).getByRole('region', { name: 'Vista de ejemplo del capital y conversión por origen' })
    expect(origenes).toHaveTextContent('Ejemplo ficticio')
    expect(origenes).toHaveTextContent('Landing')
    expect(origenes).toHaveTextContent('Formulario')
    expect(origenes).toHaveTextContent('Referido')
    expect(origenes).toHaveTextContent('Walking')
    expect(origenes).toHaveTextContent('Cartera')
    expect(origenes).toHaveTextContent('3.00%')
    expect(within(detalle).getByText(/Mes calendario · setiembre 2026/)).toBeInTheDocument()
    expect(within(detalle).getByText(/TC S\/ 3.751/)).toBeInTheDocument()
    fireEvent.click(within(detalle).getByRole('button', { name: 'Abrir Conversiones' }))
    expect(abrirConversiones).toHaveBeenCalledWith('demo-v3')
    expect(props.cumplimientoVendedores).toEqual(original)
    expect(within(detalle).queryByRole('button', { name: 'Volver a Ranking' })).not.toBeInTheDocument()
    fireEvent.click(within(detalle).getByRole('button', { name: 'Cerrar detalle' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Capital total' })).toHaveAttribute('aria-selected', 'true')
  })

  it('no conserva cifras aparentemente vigentes si falla o cambia la base mensual del detalle', () => {
    const props = datos()
    const view = render(<RankingVendedoresPanel {...props} tipoSeleccionado="capital-total" />)
    fireEvent.click(screen.getAllByRole('button', { name: 'Ver detalle de Carla Mendoza' })[0]!)
    view.rerender(<RankingVendedoresPanel {...props} tipoSeleccionado="capital-total" capitalError="No se pudo consultar capital" />)
    const detalle = screen.getByRole('dialog')
    expect(within(detalle).getByRole('alert')).toHaveTextContent('No se pudo consultar capital')
    expect(within(detalle).queryByText('S/ 317,518')).not.toBeInTheDocument()
    fireEvent.click(within(detalle).getByRole('button', { name: 'Reintentar' }))
    expect(props.onReintentarCapital).toHaveBeenCalledOnce()
    view.rerender(<RankingVendedoresPanel {...props} tipoSeleccionado="capital-total" metaMensual={{ etiqueta: 'otro mes', comparable: false }} />)
    expect(within(screen.getByRole('dialog')).queryByText('S/ 317,518')).not.toBeInTheDocument()
  })

  it('explica US$ aparte cuando no hay tipo de cambio disponible', () => {
    render(<RankingVendedoresPanel {...datos()} tipoSeleccionado="capital-total" tc={null} />)
    fireEvent.click(screen.getAllByRole('button', { name: 'Ver detalle de Carla Mendoza' })[0]!)
    const detalle = screen.getByRole('dialog', { name: 'Carla Mendoza' })
    const resumen = detalle.querySelector('dl')!
    expect(within(resumen).getByText('S/ 250,000')).toBeInTheDocument()
    expect(within(detalle).getByText(/TC no disponible/)).toBeInTheDocument()
    expect(within(resumen).getAllByText(/aparte \(sin TC\)/)).toHaveLength(2)
    expect(within(detalle).queryByText('S/ 317,518')).not.toBeInTheDocument()
  })
})

describe('ficha real de capital por origen', () => {
  const datos = () => {
    const tc = 3.751
    const ranking = clasificarRankingCapitalTotal(
      conversionEquipoDemo(),
      metasConversionEquipoDemo(),
      cumplimientoMetasConversionEquipoDemo().porVendedor,
      tc,
    )
    const original = ranking.conPuesto.find((fila) => fila.vendedor.nombre === 'Carla Mendoza')!
    const vendedorId = '00000000-0000-4000-8000-000000000001'
    const fila = { ...original, vendedor: { ...original.vendedor, vendedorId } }
    const origenes: RankingOrigenVendedor = {
      version: 2, cartera: null, periodo: '2026-09-01', vendedor_id: vendedorId, disponible: true,
      filas: [
        { origen: 'landing', capital_pen: 100000, capital_usd: 5000, contratos: 2, leads: 40, cierres: 4, conversion_pct: 10 },
        { origen: 'formulario', capital_pen: 50000, capital_usd: 4000, contratos: 1, leads: 20, cierres: 2, conversion_pct: 10 },
        { origen: 'referido', capital_pen: 50000, capital_usd: 4000, contratos: 1, leads: 10, cierres: 1, conversion_pct: 1.5 },
        { origen: 'oficina', capital_pen: 50000, capital_usd: 5000, contratos: 1, leads: 0, cierres: 0, conversion_pct: null },
      ],
    }
    return { fila, origenes, tc }
  }

  it('muestra importes y conversión de los cuatro canales, con raya si no hay divisor', () => {
    const { fila, origenes, tc } = datos()
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={tc}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const ficha = screen.getByRole('dialog')
    const desglose = within(ficha).getByRole('region', { name: 'Capital y conversión por origen' })
    for (const canal of ['Landing', 'Formulario', 'Referido', 'Walking']) {
      expect(within(desglose).getByText(canal)).toBeInTheDocument()
    }
    expect(desglose).toHaveTextContent('1.50%')
    expect(within(desglose).getAllByText('Conversión')).toHaveLength(4)
    expect(desglose).toHaveTextContent('—')
    expect(within(desglose).getByText('S/ 317,518')).toBeInTheDocument()
    expect(within(ficha).queryByText('Ejemplo ficticio')).not.toBeInTheDocument()
  })

  it('oculta todos los canales si el total en alguna moneda no concilia', () => {
    const { fila, origenes, tc } = datos()
    origenes.filas[0]!.capital_usd += 1
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={tc}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const ficha = screen.getByRole('dialog')
    expect(within(ficha).getByText('Desglose no disponible')).toBeInTheDocument()
    expect(within(ficha).queryByText('Landing')).not.toBeInTheDocument()
  })

  it('desglosa los S/ 90,000 de la captura sin sumar dos veces cartera al total', () => {
    const { fila, origenes } = datos()
    Object.assign(fila, {
      capitalPen: 287500, capitalUsd: 25000, capitalTotal: 371940,
      cartera: [{ categoria: 'renovacion', pen: 10000, usd: 0 }, { categoria: 'upgrade', pen: 80000, usd: 0 }],
    })
    origenes.filas = [
      { origen: 'formulario', capital_pen: 137500, capital_usd: 0, contratos: 2, leads: 35, cierres: 2, conversion_pct: 5.71 },
      { origen: 'referido', capital_pen: 15000, capital_usd: 0, contratos: 1, leads: 2, cierres: 1, conversion_pct: 7.5 },
      { origen: 'oficina', capital_pen: 0, capital_usd: 25000, contratos: 1, leads: 1, cierres: 1, conversion_pct: 100 },
      { origen: 'cartera', capital_pen: 90000, capital_usd: 0, contratos: 3, leads: 0, cierres: 0, conversion_pct: null },
      { origen: 'sin_origen', capital_pen: 45000, capital_usd: 0, contratos: 2, leads: 0, cierres: 0, conversion_pct: null },
    ]
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={3.3776}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const desglose = screen.getByRole('group', { name: 'Desglose de cartera' })
    expect(desglose).toHaveTextContent('RenovaciónS/ 10,000')
    expect(desglose).toHaveTextContent('UpgradeS/ 80,000')
    expect(desglose).not.toHaveTextContent('Conversión')
    expect(screen.getAllByText('S/ 371,940')).toHaveLength(2)
  })

  it('usa el desglose del registro de cartera aunque cumplimiento conserve nuevo', () => {
    const { fila, origenes } = datos()
    Object.assign(fila, { capitalPen: 577554, capitalUsd: 40000, capitalTotal: 712658,
      cartera: [{ categoria: 'renovacion', pen: 0, usd: 0 }, { categoria: 'upgrade', pen: 0, usd: 40000 }] })
    origenes.filas = [{ origen: 'cartera', capital_pen: 577554, capital_usd: 40000,
      contratos: 3, leads: 0, cierres: 0, conversion_pct: null }]
    origenes.cartera = [
      { categoria: 'renovacion', pen: 0, usd: 0 },
      { categoria: 'upgrade', pen: 577554, usd: 40000 },
      { categoria: 'nuevo', pen: 0, usd: 0 }, { categoria: 'sin_clasificar', pen: 0, usd: 0 },
    ]
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={3.3776}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const desglose = screen.getByRole('group', { name: 'Desglose de cartera' })
    expect(desglose).toHaveTextContent('RenovaciónS/ 0')
    expect(desglose).toHaveTextContent('UpgradeS/ 712,658')
    expect(desglose).toHaveTextContent('S/ 577,554 + US$ 40,000')
    expect(desglose).not.toHaveTextContent('Sin clasificación')
    expect(screen.queryByText('Desglose de renovación y upgrade no disponible')).not.toBeInTheDocument()
  })

  it('mantiene visible la parte sin clasificación sin atribuirla a renovación o upgrade', () => {
    const { fila, origenes, tc } = datos()
    origenes.filas[0]!.origen = 'cartera'
    origenes.cartera = [
      { categoria: 'renovacion', pen: 0, usd: 0 },
      { categoria: 'upgrade', pen: 50000, usd: 5000 },
      { categoria: 'nuevo', pen: 0, usd: 0 }, { categoria: 'sin_clasificar', pen: 50000, usd: 0 },
    ]
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={tc}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    expect(screen.getByRole('group', { name: 'Desglose de cartera' })).toHaveTextContent('Sin clasificaciónS/ 50,000')
  })

  it('no inventa un reparto para cartera legada cuya categoría financiera sigue siendo nuevo', () => {
    const { fila, origenes, tc } = datos()
    origenes.filas[0]!.origen = 'cartera'
    fila.cartera = [{ categoria: 'renovacion', pen: 10000, usd: 0 }, { categoria: 'upgrade', pen: 20000, usd: 0 }]
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={tc}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    expect(screen.getByText('Desglose de renovación y upgrade no disponible')).toBeInTheDocument()
    expect(screen.queryByRole('group', { name: 'Desglose de cartera' })).not.toBeInTheDocument()
    expect(screen.getByText('Cartera')).toBeInTheDocument()
  })

  it('conserva USD separado en las categorías de cartera cuando no hay TC', () => {
    const { fila, origenes } = datos()
    origenes.filas[0]!.origen = 'cartera'
    fila.capitalTotal = fila.capitalPen
    fila.cartera = [{ categoria: 'renovacion', pen: 40000, usd: 3000 }, { categoria: 'upgrade', pen: 60000, usd: 2000 }]
    render(<DetalleCapitalRanking abierto fila={fila} periodo="setiembre 2026" tc={null}
      cargando={false} error={null} origenes={origenes} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const desglose = screen.getByRole('group', { name: 'Desglose de cartera' })
    expect(desglose).toHaveTextContent('US$ 3,000 aparte (sin TC)')
    expect(desglose).toHaveTextContent('US$ 2,000 aparte (sin TC)')
  })

  it('conserva el ajuste del capital neto en meses sin desglose histórico', () => {
    const { fila, tc } = datos()
    fila.capitalAjustePen = 100
    fila.capitalAjusteUsd = 20
    render(<DetalleCapitalRanking abierto fila={fila} periodo="agosto 2026" tc={tc}
      cargando={false} error={null} onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    expect(screen.getByText(/Ajustes de cierre descontados/)).toHaveTextContent('S/ 100')
    expect(screen.getByText(/Ajustes de cierre descontados/)).toHaveTextContent('US$ 20')
    expect(screen.getByText('Desglose no disponible')).toBeInTheDocument()
  })
})

describe('ranking general de analistas', () => {
  it('mantiene el aporte de Upgrade con la misma base y el mismo peso comercial', () => {
    render(<RankingVendedoresPanel
      conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
      fuenteConversion="upgrade"
      lecturaFuente={{
        periodo: { desde: '2026-08-01', hasta: '2026-08-31' }, cierres: 0, operaciones: 2,
        fuente: 'upgrade', etiqueta: 'Upgrade', familia: 'cartera', divisor: 298,
        numerador: 2, porcentaje: 0.67, resultados: 2, peso: 1,
        porVendedor: new Map([['demo-v1', { divisor: 10, numerador: 1, porcentaje: 10, resultados: 1, cierres: 0, operaciones: 1 }]]),
      }}
      equipo={conversionEquipoDemo()}
      metasVendedores={metasConversionEquipoDemo()}
      cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
      metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
      tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
      {...fuentesRankingSinError()}
    />)

    expect(screen.getByRole('tab', { name: 'Aporte: Upgrade' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('columnheader', { name: 'Operaciones' })).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: 'Aporte al índice' })).toBeInTheDocument()
    expect(screen.getByText(/Upgrade aporta ×1 por resultado/)).toBeInTheDocument()
    expect(screen.queryByRole('complementary', { name: 'Producción fuera del ranking' })).not.toBeInTheDocument()
  })

  it('octubre con tope: la fuente Referido se rotula con el tope, no con «×1 por resultado»', () => {
    render(<RankingVendedoresPanel
      conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
      fuenteConversion="referido"
      lecturaFuente={{
        periodo: { desde: '2026-10-01', hasta: '2026-10-31' }, cierres: 5, operaciones: 0,
        fuente: 'referido', etiqueta: 'Referido', familia: 'prospectos', divisor: 298,
        numerador: 3, porcentaje: 1.01, resultados: 5, peso: 1, topeReferidosPct: 15,
        porVendedor: new Map([['demo-v1', { divisor: 10, numerador: 3, porcentaje: 30, resultados: 5, cierres: 5, operaciones: 0 }]]),
      }}
      equipo={conversionEquipoDemo()}
      metasVendedores={metasConversionEquipoDemo()}
      cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
      metaMensual={{ etiqueta: 'octubre 2026', comparable: true }}
      tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
      {...fuentesRankingSinError()}
    />)

    expect(screen.getByText(/Referido aporta 1 por resultado, con tope: los referidos cuentan hasta el 15 % de los cierres de leads asignados de cada analista, y se divide/)).toBeInTheDocument()
    expect(screen.queryByText(/×1 por resultado/)).not.toBeInTheDocument()
  })

  it('la fórmula del mes dice el tope con palabras; sin tope conserva «referidos ×0.15»', () => {
    const conTope = conversionMensualInteligenciaDemo(Date.now())
    conTope.fuentes.divisor = 'crm.leads.creado_en'
    conTope.fuentes.referido = 'crm.leads.origen'
    conTope.ponderacion = { referido: 1, renovacion: 1, tope_referidos_pct: 15, fuente: 'crm.conversion_pesos' }
    const montar = (mensual: typeof conTope) => render(<RankingVendedoresPanel
      conversionMensual={mensual}
      equipo={conversionEquipoDemo()}
      metasVendedores={metasConversionEquipoDemo()}
      cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
      metaMensual={{ etiqueta: 'octubre 2026', comparable: true }}
      tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
      {...fuentesRankingSinError()}
    />)
    const { unmount } = montar(conTope)
    expect(screen.getByText(/Cierres Landing\/Formulario \+ referidos \(cuentan hasta el 15 % de los cierres de leads asignados\) \+ renovaciones ×1/)).toBeInTheDocument()
    unmount()

    const sinTope = structuredClone(conTope)
    sinTope.ponderacion = { referido: 0.15, renovacion: 0.15, fuente: 'crm.conversion_pesos' }
    montar(sinTope)
    expect(screen.getByText(/Cierres Landing\/Formulario \+ referidos ×0\.15 \+ renovaciones ×0\.15/)).toBeInTheDocument()
  })

  it('rotula la base legacy como histórica sin cambiar la foto ni los números del ranking', () => {
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    mensual.fuentes.divisor = 'crm.lead_asignaciones.asignado_en'
    const original = structuredClone(mensual)
    render(<RankingVendedoresPanel
      conversionMensual={mensual}
      equipo={conversionEquipoDemo()}
      metasVendedores={metasConversionEquipoDemo()}
      cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
      metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
      estadoFotoMensual="sellada"
      tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
      {...fuentesRankingSinError()}
    />)

    expect(screen.getByRole('columnheader', { name: 'Base histórica' })).toBeInTheDocument()
    expect(screen.getByText('Base histórica: 10')).toBeInTheDocument()
    expect(screen.getByText(/no equivale a prospectos recibidos/i)).toBeInTheDocument()
    expect(screen.getByText('Foto sellada')).toBeInTheDocument()
    expect(screen.queryByRole('columnheader', { name: 'Recibidos' })).not.toBeInTheDocument()
    expect(mensual).toEqual(original)
  })

  it('muestra la producción no analista aparte sin concederle puesto', () => {
    const cumplimiento = cumplimientoMetasConversionEquipoDemo()
    const base = cumplimiento.porVendedor['demo-v1']!
    const fueraRanking: ProduccionFueraRanking[] = [{
      personaId: 'supervisor-produccion-propia',
      nombre: 'Supervisor con inversión propia',
      rolCrm: 'supervisor',
      motivo: 'supervisor',
      conversion: {
        divisor: 4,
        divisorAproximado: 0,
        divisorPorMotivo: { asignacion: 4 },
        cierresNoReferidos: 1,
        cierresReferidos: 0,
        cierresDeArrastre: 0,
        referidosRecibidos: 0,
        numerador: 1,
      },
      detalles: base.detalles.map((detalle, indice) => ({
        ...detalle,
        capitalObjetivo: 0,
        capitalReal: indice === 0 ? 70_000 : indice === 1 ? 1_000 : 0,
        capitalCumplimientoPct: null,
        contratosObjetivo: 0,
        contratosReal: indice < 2 ? 1 : 0,
        contratosCumplimientoPct: null,
      })),
      cartera: {
        conversionesClientes: 1,
        conversionesRenovacion: 1,
        conversionesUpgrade: 0,
        operacionesRenovacion: 1,
        operacionesUpgrade: 0,
        capitalRenovadoPen: 5_000,
        capitalRenovadoUsd: 0,
        capitalAdicionalPen: 0,
        capitalAdicionalUsd: 0,
        renovacionesSinDesglose: 0,
      },
    }]

    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        cosecha={undefined}
        equipo={conversionEquipoDemo()}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimiento.porVendedor}
        fueraRanking={fueraRanking}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('6 analistas')).toBeInTheDocument()
    const bloque = screen.getByRole('complementary', { name: 'Producción fuera del ranking' })
    expect(within(bloque).getByText('Supervisor con inversión propia')).toBeInTheDocument()
    expect(within(bloque).getByText('Producción atribuida a supervisor')).toBeInTheDocument()
    expect(within(bloque).getByText('No suma al ranking')).toBeInTheDocument()
    expect(within(bloque).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
    expect(within(bloque).getByText('2 contratos')).toBeInTheDocument()
  })

  it('no promete una foto sellada en Cosecha, que continúa madurando', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        cosecha={undefined}
        equipo={conversionEquipoDemo()}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
        estadoFotoMensual="sellada"
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('Foto sellada')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Resultados de los leads del mes' }))
    expect(screen.queryByText('Foto sellada')).not.toBeInTheDocument()
    expect(screen.getByText('Leads del mes')).toHaveAttribute(
      'title',
      expect.stringContaining('pueden convertirse después'),
    )
  })

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
    cumplimientos['demo-v2']!.ajuste = {
      pendiente: 0,
      aplicado: 1,
      aplicadoPen: 40_000,
      aplicadoUsd: 150,
      contratosAplicados: 2,
    }

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

    expect(screen.getByText('7 analistas')).toBeInTheDocument()
    expect(screen.getByText('Mes calendario · agosto 2026')).toBeInTheDocument()
    expect(screen.getByText(/renovaciones ×0.15.*prospectos automáticos de Landing\/Formulario/)).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Ranking de conversión general' })
    // Columnas de la conversión MENSUAL: base automática y cierres — no los
    // rótulos del payload viejo (Leads/Clientes medían el rango completo).
    expect(within(tabla).getByRole('columnheader', { name: 'Base automática' })).toBeInTheDocument()
    expect(within(tabla).queryByRole('columnheader', { name: 'Recibidos' })).not.toBeInTheDocument()
    expect(within(tabla).getByRole('columnheader', { name: 'Cierres' })).toBeInTheDocument()
    const filas = within(tabla).getAllByRole('row')
    // 1 cabecera + 4 medibles + Fabio (solo arrastre: compite al fondo, sin %).
    expect(filas).toHaveLength(6)
    const filaAna = filas[1]!
    expect(within(filaAna).getByText('Ana Torres')).toBeInTheDocument()
    expect(within(filaAna).getByText('10')).toBeInTheDocument()
    expect(within(filaAna).getByText('4')).toBeInTheDocument()
    // 4.15 ÷ 12 — el numerador pondera el referido al 15 %, no cuenta 5/12.
    expect(within(filaAna).getByText('31.50%')).toBeInTheDocument()
    // El descuento con su porqué, debajo del % que rebaja.
    expect(within(filaAna).getByText('arrastra 1 conversión de anulaciones · julio 2026')).toBeInTheDocument()
    expect(within(filaAna).getByTitle('julio 2026: Cierre anulado por gerencia (−1)')).toBeInTheDocument()
    const filaFabio = filas[5]!
    expect(within(filaFabio).getByText('Fabio León')).toBeInTheDocument()
    expect(within(filaFabio).getByText('—')).toBeInTheDocument()
    expect(within(filaFabio).getByText('Cerró sin base del mes')).toBeInTheDocument()
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
    expect(within(filasCapital[1]!).getByText(
      /Neto tras ajuste de cierre · −S\/ 40,000 · −US\$ 150 · −2 contratos/,
    )).toBeInTheDocument()
    expect(within(filasCapital[1]!).getByTitle(
      'El capital confirmado ya es neto: estos importes y contratos se descontaron al cerrar el mes.',
    )).toBeInTheDocument()
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
    expect(screen.getByText('— analistas')).toBeInTheDocument()
    expect(screen.queryByText('Sin meta')).not.toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'Ranking de capital total en soles' })).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Conversión general' }))
    expect(screen.getByText('Consultando identidad, metas y capital del mes…')).toBeInTheDocument()
    expect(screen.queryByText('Analista no identificado')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Resultados de los leads del mes' }))
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

    for (const tab of ['Conversión general', 'Capital total', 'Resultados de los leads del mes']) {
      fireEvent.click(screen.getByRole('tab', { name: tab }))
      expect(screen.getByRole('alert')).toHaveTextContent('No se pudo cargar la foto mensual.')
      fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    }
    expect(screen.getByText('— analistas')).toBeInTheDocument()
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
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    mensual.responsables.push(filaSinActividad('fuera-del-roster'))
    const cosecha: MetricasConversionesEquipo = {
      version: 1,
      generado_en: '2026-09-02T12:00:00Z',
      alcance: 'global',
      periodo: { desde: '2026-08-01', hasta: '2026-08-31' },
      responsables: [
        { vendedor_id: 'demo-v1', leads: 38, clientes: 5, conversion_pct: 13.2 },
        { vendedor_id: 'demo-v7', leads: 4, clientes: 1, conversion_pct: 25 },
        { vendedor_id: 'fuera-del-roster', leads: 7, clientes: 2, conversion_pct: 28.57 },
      ],
      sondas: {
        cuadra: true,
        paridad_nucleo: 0,
        paridad_filas: 3,
        divisor_fuera_del_roster: 7,
        numerador_fuera_del_roster: 2,
        cierres_anulados: 0,
        clientes_acreditados_a_otro_dueno: 0,
      },
    }
    render(
      <RankingVendedoresPanel
        conversionMensual={mensual}
        cosecha={cosecha}
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
      .toHaveTextContent('31.50%')

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))
    expect(screen.queryByText('Alta de setiembre')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Resultados de los leads del mes' }))
    const listaCosecha = screen.getByRole('list', { name: 'Resultados de los leads del mes por analista' })
    expect(within(listaCosecha).getAllByRole('listitem')).toHaveLength(Object.keys(cumplimiento).length)
    expect(within(listaCosecha).getByText('Ana Torres')).toBeInTheDocument()
    expect(within(listaCosecha).queryByText('Nombre actual')).not.toBeInTheDocument()
    expect(within(listaCosecha).queryByText('Alta de setiembre')).not.toBeInTheDocument()
    expect(within(listaCosecha).queryByText('Analista no identificado')).not.toBeInTheDocument()
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

  it('en el mes vigente ninguna fuente de medidas agrega identidades fuera del roster vivo', () => {
    const altaVigente: ConversionEquipoVendedor = {
      vendedorId: 'alta-vigente-sin-foto',
      nombre: 'Alta vigente sin foto',
      supervisorNombre: 'Equipo actual',
      leads: 0,
      contactados: 0,
      reunionesPactadas: 0,
      reunionesRealizadas: 0,
      clientes: 0,
      descartados: 0,
      conversionPct: null,
    }
    const equipoVivo = [conversionEquipoDemo()[0]!, altaVigente]
    const mensual = conversionMensualInteligenciaDemo(Date.now())
    mensual.responsables.push(
      filaSinActividad('alta-vigente-sin-foto'),
      filaSinActividad('fuera-del-roster'),
    )
    const cosecha: MetricasConversionesEquipo = {
      version: 1,
      generado_en: '2026-09-02T12:00:00Z',
      alcance: 'global',
      periodo: { desde: '2026-09-01', hasta: '2026-09-02' },
      responsables: [
        { vendedor_id: 'demo-v1', leads: 3, clientes: 1, conversion_pct: 33.33 },
        { vendedor_id: 'fuera-del-roster', leads: 9, clientes: 4, conversion_pct: 44.44 },
      ],
      sondas: {
        cuadra: true,
        paridad_nucleo: 0,
        paridad_filas: 2,
        divisor_fuera_del_roster: 9,
        numerador_fuera_del_roster: 4,
        cierres_anulados: 0,
        clientes_acreditados_a_otro_dueno: 0,
      },
    }

    render(
      <RankingVendedoresPanel
        conversionMensual={mensual}
        cosecha={cosecha}
        equipo={equipoVivo}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'setiembre 2026', comparable: true }}
        usarIdentidadSnapshot={false}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('2 analistas')).toBeInTheDocument()
    expect(screen.queryByText('Bruno Díaz')).not.toBeInTheDocument()
    expect(screen.queryByText('Analista no identificado')).not.toBeInTheDocument()
    const fueraConversion = screen.getByRole('region', { name: 'Analistas sin posición en conversión' })
    expect(within(fueraConversion).getByText('Alta vigente sin foto')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))
    const altaCapital = screen.getByText('Alta vigente sin foto').closest('li')
    expect(altaCapital).not.toBeNull()
    expect(within(altaCapital!).getByText('Capital no disponible')).toBeInTheDocument()
    expect(within(altaCapital!).getByText('No disponible')).toBeInTheDocument()
    expect(within(altaCapital!).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
    expect(screen.queryByText('Bruno Díaz')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('tab', { name: 'Resultados de los leads del mes' }))
    const listaCosecha = screen.getByRole('list', { name: 'Resultados de los leads del mes por analista' })
    expect(within(listaCosecha).getAllByRole('listitem')).toHaveLength(2)
    expect(within(listaCosecha).getByText('Ana Torres')).toBeInTheDocument()
    expect(within(listaCosecha).getByText('Alta vigente sin foto')).toBeInTheDocument()
    expect(within(listaCosecha).getByText('Seguimiento no disponible')).toBeInTheDocument()
    expect(within(listaCosecha).queryByText('Analista no identificado')).not.toBeInTheDocument()
  })

  it('en el mes vigente un roster vacío no revive analistas desde cumplimiento al abrir Capital', () => {
    render(
      <RankingVendedoresPanel
        conversionMensual={conversionMensualInteligenciaDemo(Date.now())}
        equipo={[]}
        metasVendedores={metasConversionEquipoDemo()}
        cumplimientoVendedores={cumplimientoMetasConversionEquipoDemo().porVendedor}
        metaMensual={{ etiqueta: 'setiembre 2026', comparable: true }}
        usarIdentidadSnapshot={false}
        tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
        {...fuentesRankingSinError()}
      />,
    )

    expect(screen.getByText('0 analistas')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Capital total' }))
    expect(screen.getByText('Aún no hay analistas para mostrar')).toBeInTheDocument()
    expect(screen.queryByText('Ana Torres')).not.toBeInTheDocument()
    expect(screen.queryByText('Analista no identificado')).not.toBeInTheDocument()
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
        cosechaError="No se pudieron cargar los resultados de los leads del mes."
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

    fireEvent.click(screen.getByRole('tab', { name: 'Resultados de los leads del mes' }))
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar los resultados de los leads del mes.')
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

  const abrirCosecha = () => fireEvent.click(screen.getByRole('tab', { name: 'Resultados de los leads del mes' }))

  it('vive en SU pestaña, no en las filas del ranking (pedido de Miguel: dos relojes juntos eran ruido)', () => {
    montar(cosechaDemo())
    // En el tab de conversión NO hay ni rastro de la cosecha…
    expect(within(screen.getByRole('tabpanel')).queryByText(/De sus \d+ leads del mes/)).not.toBeInTheDocument()
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
    expect(screen.getByText('Resultados de los leads del mes no disponibles por ahora.')).toBeInTheDocument()
    expect(within(screen.getByRole('tabpanel')).queryByText(/De sus \d+ leads del mes/)).not.toBeInTheDocument()
  })

  it('mientras consulta la cosecha mantiene carga y no afirma que está indisponible', () => {
    montar(undefined, true)
    abrirCosecha()
    expect(screen.getByText('Consultando los resultados de los leads del mes…')).toBeInTheDocument()
    expect(screen.queryByText('Resultados de los leads del mes no disponibles por ahora.')).not.toBeInTheDocument()
  })

  it('F3.4: con la sonda en falso la pestaña entera se OCULTA y se avisa', () => {
    montar(cosechaDemo(false))
    abrirCosecha()
    expect(within(screen.getByRole('tabpanel')).queryByText(/De sus \d+ leads del mes/)).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Resultados de los leads del mes en revisión')
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
    expect(within(screen.getByRole('tabpanel')).queryByText(/De sus \d+ leads del mes/)).not.toBeInTheDocument()
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
