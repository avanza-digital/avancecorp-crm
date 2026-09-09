import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { conversionEquipoDemo, conversionMensualInteligenciaDemo } from '@/lib/demo-inteligencia-comercial'
import { adaptarConversionMensual } from '@/lib/conversion-vendedores'
import { ComparacionAnalistas } from './comparacion-analistas'

const AHORA = Date.parse('2026-09-05T12:00:00-05:00')
const base = () => conversionMensualInteligenciaDemo(AHORA)
const equipo = conversionEquipoDemo()
const props = (datos = base()) => ({ datos, adaptada: adaptarConversionMensual(datos, equipo), cargando: false, error: null, mesEsperado: '2026-09', idsConDetalle: equipo.flatMap((f) => f.vendedorId == null ? [] : [f.vendedorId]), onAbrirDetalle: vi.fn() })
function elegir() {
  fireEvent.click(screen.getByRole('button', { name: 'Comparar dos analistas' }))
  fireEvent.change(screen.getByRole('combobox', { name: 'Primer analista' }), { target: { value: 'demo-v3' } })
  fireEvent.change(screen.getByRole('combobox', { name: 'Segundo analista' }), { target: { value: 'demo-v2' } })
}
describe('comparación mensual de dos analistas', () => {
  it('usa las cifras canónicas y mantiene el destino individual sin agregar las filas', () => {
    const p = props()
    const antes = structuredClone(p.datos)
    render(<ComparacionAnalistas {...p} />)
    elegir()
    const tabla = screen.getByRole('table', { name: 'Comparación mensual de Carla Mendoza y Bruno Díaz' })
    expect(within(tabla).getByRole('row', { name: 'Conversión 12.78% 22.22%' })).toBeInTheDocument()
    expect(within(tabla).getByRole('row', { name: 'Base automática 9 9' })).toBeInTheDocument()
    expect(within(tabla).getByRole('row', { name: 'Aporte ponderado 1.15 2' })).toBeInTheDocument()
    expect(within(tabla).queryByText('Total')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalle de Carla' }))
    expect(p.onAbrirDetalle).toHaveBeenCalledWith('demo-v3')
    expect(p.datos).toEqual(antes)
  })
  it.each(['carga', 'error', 'mes distinto', 'colección parcial'] as const)('retira la comparación durante %s y conserva la selección', (caso) => {
    const p = props()
    const { rerender } = render(<ComparacionAnalistas {...p} />)
    elegir()
    const nuevos = { ...p }
    if (caso === 'carga') nuevos.cargando = true
    if (caso === 'error') Object.assign(nuevos, { error: 'Fallo al consultar' })
    if (caso === 'mes distinto') nuevos.mesEsperado = '2026-08'
    if (caso === 'colección parcial') nuevos.adaptada = adaptarConversionMensual({ ...p.datos, responsables: p.datos.responsables.slice(0, 3) }, equipo)
    rerender(<ComparacionAnalistas {...nuevos} />)
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'Primer analista' })).toHaveValue('demo-v3')
    expect(screen.getByRole('combobox', { name: 'Segundo analista' })).toHaveValue('demo-v2')
    expect(screen.queryByText('12.78%')).not.toBeInTheDocument()
  })
  it('no convierte sólo arrastre ni sólo referidos en un porcentaje comparable', () => {
    render(<ComparacionAnalistas {...props()} />)
    elegir()
    for (const id of ['demo-v5', 'demo-v6']) {
      fireEvent.change(screen.getByRole('combobox', { name: 'Segundo analista' }), { target: { value: id } })
      expect(screen.getByRole('status')).toHaveTextContent('Esta selección no es comparable')
      expect(screen.queryByRole('table')).not.toBeInTheDocument()
      expect(screen.queryByText('0%')).not.toBeInTheDocument()
    }
  })
})
