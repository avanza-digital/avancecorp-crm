import { fireEvent, render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { metricasMultiempresaDemo } from '@/lib/demo-metricas-multiempresa'
import { CrmApiError } from '@/data/crm-api'

const doble = vi.hoisted(() => ({ demo: false, rol: 'gerencia', habilitada: true, error: null as Error | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'g1', rol: doble.rol, demo: doble.demo } }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-11T17:00:00Z') }))
vi.mock('@/data/metricas-multiempresa', () => ({ useMetricasMultiempresa: () => ({
  estado: { data: { habilitada: doble.habilitada }, isPending: false, error: null, refetch: vi.fn() },
  informe: { data: metricasMultiempresaDemo('2026-09-01', '2026-09-11'), error: doble.error, refetch: vi.fn() },
}) }))
const { ContenidoInforme, MetricasMultiempresa } = await import('./metricas-multiempresa')
beforeEach(() => { doble.demo = false; doble.rol = 'gerencia'; doble.habilitada = true; doble.error = null })

describe('Informe por empresa del CRM', () => {
  it('filtra importes por moneda sin alterar la cobertura de personas', () => {
    render(<ContenidoInforme datos={metricasMultiempresaDemo('2026-09-01', '2026-09-11')} />)
    fireEvent.change(screen.getByLabelText('Moneda'), { target: { value: 'USD' } })
    const tabla = screen.getByRole('table', { name: 'Capital por empresa y moneda' })
    expect(within(tabla).getAllByRole('row')).toHaveLength(2)
    expect(within(tabla).getByText('Avance')).toBeInTheDocument()
    expect(within(tabla).queryByText('Qorilazo')).not.toBeInTheDocument()
    expect(screen.getByText('En tres empresas')).toBeInTheDocument()
  })
  it('avisa mes sellado y cobertura incompleta sin ocultar capital', () => {
    const r = metricasMultiempresaDemo('2026-08-01', '2026-09-11'); r.personas.fuentes_sin_identidad = 2
    render(<ContenidoInforme datos={r} />)
    expect(screen.getByText(/cierre firmado conserva sus cifras originales/)).toBeInTheDocument()
    expect(screen.getByText(/2 inversiones necesitan revisar/)).toBeInTheDocument()
    expect(screen.getByRole('table', { name: 'Capital por empresa y moneda' })).toBeInTheDocument()
  })
  it('no presenta falta de divisor como cero por ciento', () => {
    const r = metricasMultiempresaDemo('2026-09-01', '2026-09-11'); r.conversion.divisor = 0; r.conversion.tasa_pct = null
    render(<ContenidoInforme datos={r} />)
    expect(screen.getByText('Sin base de cálculo')).toBeInTheDocument()
  })
  it('conserva los decimales de conversión y del aporte ponderado', () => {
    render(<ContenidoInforme datos={metricasMultiempresaDemo('2026-09-01', '2026-09-11')} />)
    expect(screen.getByText('15.75%')).toBeInTheDocument()
    expect(screen.getByText('3.15')).toBeInTheDocument()
  })
  it('oculta datos todavía almacenados cuando el informe se apaga', () => {
    doble.habilitada = false; render(<MetricasMultiempresa />)
    expect(screen.getByText('Informe en preparación')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
  it('un apagado durante la consulta muestra preparación, sin confundirlo con falta de permiso', () => {
    doble.error = new CrmApiError('En preparación', 'P0409'); render(<MetricasMultiempresa />)
    expect(screen.getByText('Informe en preparación')).toBeInTheDocument()
    expect(screen.queryByText('Tu acceso actual no permite consultar este informe.')).not.toBeInTheDocument()
  })
  it('expone el detalle de una diferencia y el número de inversiones repetidas', () => {
    const r = metricasMultiempresaDemo('2026-09-01', '2026-09-11')
    r.fuentes_duplicadas = 1; r.conciliacion[0]!.diferencia_capital = -0.01
    render(<ContenidoInforme datos={r} />)
    expect(screen.getByRole('alert')).toHaveTextContent('1 inversión aparece repetida')
    fireEvent.click(screen.getByText('Ver detalle de la comparación'))
    expect(screen.getByRole('table', { name: 'Comparación de cifras' })).toHaveTextContent('S/ -0.01')
  })
  it.each(['42501', 'P0409', 'RESPUESTA_NO_RECIBIDA'])('oculta el payload previo ante %s', code => {
    doble.error = new CrmApiError('Error del ensayo', code); render(<MetricasMultiempresa />)
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
  it('ni Directorio ni vendedor obtienen un informe global aunque haya caché', () => {
    doble.rol = 'directorio'; render(<MetricasMultiempresa />)
    expect(screen.getByText('Informe no disponible')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
  it('identifica la demostración expresamente', () => {
    doble.demo = true; render(<MetricasMultiempresa />)
    expect(screen.getByText(/todas estas cifras son ficticias/)).toBeInTheDocument()
  })
})
