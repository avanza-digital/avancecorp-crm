import { render, screen, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
import abierto from '@/lib/__fixtures__/capital-valorado/activo.json'
import pendiente from '@/lib/__fixtures__/capital-valorado/pendiente.json'
import sellado from '@/lib/__fixtures__/capital-valorado/sellado.json'
import detalleSellado from '@/lib/__fixtures__/capital-valorado/detalle-sellado.json'
import parcial from '../../../test-fixtures/capital-pendientes/pendiente.json'
import detalleParcial from '../../../test-fixtures/capital-pendientes/detalle-pendiente.json'
import { CapitalOperacionesSchema } from '@/lib/capital-valorado'
import { CumplimientoMetasV2Schema } from '@/lib/objetivos'
import { clasificarRankingCapitalTotal } from '@/lib/conversion-vendedores'
import { RankingVendedoresPanel } from './ranking-vendedores'
import { DetalleCapitalRanking } from './ranking-detalle'

function propsCapital(fixture: unknown = abierto) {
  const datos = v.parse(CumplimientoMetasV2Schema, fixture)
  return {
    conversionMensual: null, conversionError: null, onReintentarConversion: vi.fn(),
    cosechaCargando: false, cosechaError: null, onReintentarCosecha: vi.fn(),
    equipo: [], metasVendedores: {}, cumplimientoVendedores: {},
    metaMensual: { etiqueta: 'octubre 2026', comparable: true },
    capitalError: null, onReintentarCapital: vi.fn(),
    tc: undefined, tabInicial: 'capital-total' as const,
    valoracionCapital: datos.capital_valoracion,
  }
}

function proveedor() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
}

describe('capital publicado en las pantallas', () => {
  it('el ranking y el detalle muestran ambos PEN del día mientras el USD espera TC', () => {
    const datos = v.parse(CumplimientoMetasV2Schema, parcial)
    const ranking = clasificarRankingCapitalTotal([], {}, {}, null, datos.capital_valoracion!)
    const { unmount } = render(<RankingVendedoresPanel {...propsCapital(parcial)} />, { wrapper: proveedor() })
    expect(screen.getAllByText('S/ 6,000').length).toBeGreaterThan(0)
    expect(screen.getByText(/US\$ 20,000 pendiente de tipo de cambio\. No incluido/)).toBeInTheDocument()
    unmount()
    render(<DetalleCapitalRanking abierto fila={ranking.conPuesto[0]!} periodo="octubre 2026" tc={null}
      cargando={false} error={null} valorado operaciones={v.parse(CapitalOperacionesSchema, detalleParcial)}
      onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const ventas = screen.getByRole('region', { name: 'Ventas con tipo de cambio fijado' })
    expect(ventas).toHaveTextContent('PENDIENTES-PEN-10')
    expect(ventas).toHaveTextContent('PENDIENTES-PEN-12')
    expect(ventas).toHaveTextContent('US$ 20,000 pendiente de tipo de cambio · Contrato · 23/10/2026')
    expect(ventas).not.toHaveTextContent('S/ 68,000')
  })
  it('conserva el bloque publicado de ventas propias de supervisores con capital fijo', () => {
    const props = propsCapital()
    const valoracion = { ...props.valoracionCapital!, personas: props.valoracionCapital!.personas.map(p => ({ ...p, en_ranking: false, rol_crm: 'supervisor' })) }
    const { rerender } = render(<RankingVendedoresPanel {...props} valoracionCapital={valoracion} tc={{ promedio: 3.1, fuente: 'BCRP' }} />, { wrapper: proveedor() })
    const bloque = screen.getByRole('complementary', { name: 'Ventas propias de supervisores' })
    expect(bloque).toHaveTextContent('S/ 74,000')
    rerender(<RankingVendedoresPanel {...props} valoracionCapital={valoracion} tc={{ promedio: 3.8, fuente: 'BCRP' }} />)
    expect(bloque).toHaveTextContent('S/ 74,000')
    expect(screen.queryByRole('complementary', { name: 'Producción fuera del ranking' })).not.toBeInTheDocument()
  })

  it('la producción fuera del ranking conserva el corte completo cuando cambia la cotización', () => {
    const props = propsCapital()
    const valoracion = { ...props.valoracionCapital!, personas: props.valoracionCapital!.personas.map((p) => ({ ...p, en_ranking: false })) }
    const { rerender } = render(<RankingVendedoresPanel {...props} valoracionCapital={valoracion} tc={{ promedio: 3.1, fuente: 'BCRP' }} />, { wrapper: proveedor() })
    const bloque = screen.getByRole('complementary', { name: 'Producción fuera del ranking' })
    expect(bloque).toHaveTextContent('S/ 74,000')
    expect(bloque).toHaveTextContent(`${valoracion.personas[0]!.capital_valorado.contratos} operaciones`)
    expect(bloque).not.toHaveTextContent('sin TC')
    rerender(<RankingVendedoresPanel {...props} valoracionCapital={valoracion} tc={{ promedio: 3.8, fuente: 'BCRP' }} />)
    expect(bloque).toHaveTextContent('S/ 74,000')
    expect(within(bloque).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
  })

  it('muestra el equivalente con BCRP caído y lo conserva al cambiar la cotización', () => {
    const props = propsCapital()
    const { rerender } = render(<RankingVendedoresPanel {...props} />, { wrapper: proveedor() })
    expect(screen.getAllByText('S/ 74,000')).toHaveLength(2)
    expect(screen.getByText(/Capital en soles con TC fijado por venta/)).toBeInTheDocument()
    rerender(<RankingVendedoresPanel {...props} tc={{ promedio: 3.1, fuente: 'BCRP' }} />)
    expect(screen.getAllByText('S/ 74,000')).toHaveLength(2)
    expect(screen.queryByText(/aparte \(sin TC\)/)).not.toBeInTheDocument()
  })

  it('muestra el capital valorado y anuncia el USD pendiente por separado', () => {
    render(<RankingVendedoresPanel {...propsCapital(pendiente)} />, { wrapper: proveedor() })
    expect(screen.getAllByText('S/ 74,000')).toHaveLength(2)
    expect(screen.getByText(/1 venta pendiente de valoración/)).toBeInTheDocument()
    expect(screen.getByText(/US\$ 20,000 pendiente de tipo de cambio\. No incluido/)).toBeInTheDocument()
  })

  it('no presenta puestos ni un cero confirmado si aún falta el primer corte', () => {
    const props = propsCapital(pendiente)
    const valoracion = props.valoracionCapital!
    render(<RankingVendedoresPanel {...props} valoracionCapital={{ ...valoracion, corte_id: null, personas: [],
      cobertura: { ...valoracion.cobertura, corte: null, estado: 'sin_corte' } }} />, { wrapper: proveedor() })
    expect(screen.getByText(/Aún no se ha publicado un corte/)).toBeInTheDocument()
    expect(screen.queryByText('S/ 0')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Ver detalle de/ })).not.toBeInTheDocument()
  })

  it('el detalle sellado muestra la venta US$ 20 000 con TC 3,4000 y S/ 68 000', () => {
    const valoracion = v.parse(CumplimientoMetasV2Schema, sellado).capital_valoracion!
    const ranking = clasificarRankingCapitalTotal([], {}, {}, 3.1, valoracion)
    render(<DetalleCapitalRanking abierto fila={ranking.conPuesto[0]!} periodo="octubre 2026" tc={null}
      cargando={false} error={null} valorado operaciones={v.parse(CapitalOperacionesSchema, detalleSellado)}
      onCerrar={vi.fn()} onReintentar={vi.fn()} />)
    const ventas = screen.getByRole('region', { name: 'Ventas con tipo de cambio fijado' })
    expect(within(ventas).getByText('S/ 68,000')).toBeInTheDocument()
    expect(within(ventas).getByText(/US\$ 20,000 · TC S\/ 3.4000/)).toBeInTheDocument()
    expect(screen.queryByText(/TC no disponible/)).not.toBeInTheDocument()
  })
})
