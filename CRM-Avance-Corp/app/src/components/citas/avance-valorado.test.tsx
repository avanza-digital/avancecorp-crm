import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import * as v from 'valibot'
import activo from '../../../test-fixtures/capital-valorado/citas-activo.json'
import pendiente from '../../../test-fixtures/capital-valorado/citas-pendiente.json'
import sellado from '../../../test-fixtures/capital-valorado/citas-sellado.json'
import sinCorte from '../../../test-fixtures/capital-valorado/citas-sin-corte.json'
import { adaptarCitas, adaptarGestion, ConsultaCitasSchema } from '@/data/citas-gerencia'
import { calcularAvanceCitas } from './avance'
import { csvAvanceCitas } from './avance-csv'
import { AvanceMensualCitas } from './avance-mensual'
import { ContextoCitas } from './contexto'
import { TableroCitas } from './propuesta'
import { defaults } from './modelo'

const cotizacion = vi.hoisted(() => ({ promedio: 3.1, hook: vi.fn() }))
vi.mock('@/lib/tipo-cambio', async importOriginal => ({ ...await importOriginal<typeof import('@/lib/tipo-cambio')>(), useTipoCambio: (...args: unknown[]) => {
  cotizacion.hook(...args)
  return { tc: { promedio: cotizacion.promedio, fuente: 'Fuente de consulta' }, recargar: vi.fn() }
} }))
afterEach(cleanup)
const filtros = defaults('2026-10')
function datos(payload: unknown) {
  const rpc = v.parse(ConsultaCitasSchema, payload)
  return { gestion: adaptarGestion(rpc)!, citas: adaptarCitas(rpc), corte: rpc.generado_en }
}
function calcular(payload: unknown, tc: number | null = 3.1) {
  const d = datos(payload)
  return calcularAvanceCitas(d.gestion, d.citas, filtros, d.corte, tc)
}
function leerCsv(texto: string) {
  const [cabecera, ...filas] = texto.slice(1).split('\r\n').map(linea =>
    [...linea.matchAll(/"((?:""|[^"])*)"(?:,|$)/g)].map(m => m[1]!.replaceAll('""', '"')))
  return filas.map(fila => Object.fromEntries(cabecera!.map((clave, i) => [clave, fila[i]])))
}

describe('ticket y CSV de Citas con valores guardados por operación', () => {
  it.each([activo, pendiente, sellado])('acepta un corte ejecutado en SQL y no lo reconvierte con TC actual', payload => {
    const a = calcular(payload, 3.1)
    const b = calcular(payload, 3.8)
    const suma = payload.gestion.capital.reduce((n, k) => n + k.equivalente_pen * 100, 0) / 100
    expect(a.total.capital).toBe(suma)
    expect(b.total.capital).toBe(suma)
    expect(a.total.ticket).toBe(b.total.ticket)
    expect(a.tc).toBeNull()
    expect(csvAvanceCitas(a, '2026-10', 'CRM', 'Fuente A', '2026-10-16'))
      .toBe(csvAvanceCitas(b, '2026-10', 'CRM', 'Fuente B', '2026-10-30'))
  })
  it('conserva S/ 68 000 de USD 20 000 y reconoce una persona aunque firme varias operaciones', () => {
    const d = datos(sellado)
    const fila = calcular(sellado).filas.find(f => f.id.endsWith('000002'))!
    expect(d.gestion.avance!.capital.find(k => k.monto === 20000)).toMatchObject({ tasa: 3.4, equivalente_pen: 68000 })
    expect(fila).toMatchObject({ capital: 76000, clientesTicket: 1, ticket: 76000, capitalUsd: 20000, capitalPen: 8000 })
  })
  it('sin primer corte deja ticket y proyección pendientes incluso si se dispone de cotización', () => {
    expect(calcular(sinCorte).total).toMatchObject({ capital: null, ticket: null, proyeccion: null, capitalPendiente: true, faltaTipoCambio: false })
    const d = datos(sinCorte)
    d.gestion.avance!.capital = datos(activo).gestion.avance!.capital
    // Defensa del modelo: tampoco convertiría fuentes vivas si un consumidor
    // interno mezclara por error una lista con una referencia de corte nula.
    expect(calcularAvanceCitas(d.gestion, d.citas, filtros, d.corte, 3.8).total.capital).toBeNull()
  })
  it('el CSV identifica importe, corte y cobertura y no anuncia una tasa única para octubre', () => {
    const resumen = calcular(pendiente)
    const filas = leerCsv(csvAvanceCitas(resumen, '2026-10', 'CRM', 'Cotización actual', '2026-10-31'))
    expect(filas).toHaveLength(resumen.filas.length)
    expect(filas[0]).toMatchObject({ 'TC USD a PEN': '', 'Corte del TC': '', 'Régimen del capital': 'TC fijado por venta',
      'Referencia del corte de capital': pendiente.gestion.valoracion.corte_id, 'Cobertura del ámbito CRM': 'pendiente',
      'Ventas pendientes del ámbito CRM': '2', 'Capital confirmado en soles': String(resumen.filas[0]!.capital) })
    resumen.filas[0]!.nombre = '=SUM(1+1)'
    expect(leerCsv(csvAvanceCitas(resumen, '2026-10', 'CRM', undefined, '2026-10-16'))[0]!.Analista).toBe("'=SUM(1+1)")
  })
  it('mantiene el CSV mensual legado con sus columnas de tasa y fecha', () => {
    const d = datos(activo)
    delete d.gestion.avance!.valoracion
    const resumen = calcularAvanceCitas(d.gestion, d.citas, filtros, d.corte, 3.5)
    const filaUsd = leerCsv(csvAvanceCitas(resumen, '2026-09', 'CRM', 'BCRP', '2026-09-30')).find(f => f['Capital real USD'] !== '0')!
    expect(filaUsd).toMatchObject({ 'TC USD a PEN': '3.5', 'Fuente del TC': 'BCRP', 'Corte del TC': '2026-09-30', 'Régimen del capital': 'TC mensual legado' })
  })
  it('la interfaz muestra corte y pendientes sin solicitar otra cotización', () => {
    const d = datos(pendiente)
    const vista = render(<ContextoCitas value={{ ...d, depositos: [], depositosDisponibles: true, mesInicial: '2026-10', modoDemo: false, meses: [] }}>
      <AvanceMensualCitas filtros={filtros} onAnalista={vi.fn()} />
    </ContextoCitas>)
    expect(cotizacion.hook).toHaveBeenLastCalledWith(false, expect.any(String))
    expect(screen.getByText(/Capital en soles con TC fijado por venta/)).toBeVisible()
    expect(screen.getByText(/US\$ 22,000 pendiente de tipo de cambio/)).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Reintentar tipo de cambio' })).not.toBeInTheDocument()
    const tabla = screen.getByRole('table')
    const ticket = within(tabla).getByRole('row', { name: /Persona sintética 2/ }).textContent
    cotizacion.promedio = 3.8
    vista.rerender(<ContextoCitas value={{ ...d, depositos: [], depositosDisponibles: true, mesInicial: '2026-10', modoDemo: false, meses: [] }}>
      <AvanceMensualCitas filtros={filtros} onAnalista={vi.fn()} />
    </ContextoCitas>)
    expect(within(screen.getByRole('table')).getByRole('row', { name: /Persona sintética 2/ }).textContent).toBe(ticket)
    fireEvent.click(screen.getByRole('button', { name: 'Cómo se calcula el avance mensual' }))
    expect(screen.getByRole('dialog')).toHaveTextContent('suma los equivalentes en soles guardados por operación')
  })
  it.each([sellado, sinCorte])('el módulo completo muestra el avance sin citas ni asignaciones cuando existe consulta mensual', payload => {
    window.history.replaceState(null, '', '#/reuniones/mes/2026-10')
    const d = datos(payload)
    expect(d.citas).toHaveLength(0)
    expect(d.gestion.asignaciones).toHaveLength(0)
    render(<ContextoCitas value={{ ...d, depositos: [], depositosDisponibles: true, mesInicial: '2026-10', modoDemo: false, meses: [] }}>
      <TableroCitas />
    </ContextoCitas>)
    expect(screen.getByRole('tab', { name: 'Agenda' })).toHaveAttribute('aria-selected', 'true')
    fireEvent.click(screen.getByRole('tab', { name: 'Resultados' }))
    expect(screen.getByRole('heading', { name: 'Avance mensual por analista' })).toBeVisible()
    expect(screen.getByText(/Capital en soles con TC fijado por venta/)).toBeVisible()
  })
})
