import { fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AlertasCRMContext, type EstadoAlertasCRM } from '@/lib/alertas-context'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { Alertas } from './alertas'
import { avisosFixture } from '@/lib/gestion-diaria-avisos.fixture'
const ancho = vi.hoisted(() => ({ movil: true }))
vi.mock('@/lib/media', () => ({ useEsMovil: () => ancho.movil }))
afterEach(() => { ancho.movil = true })
const estado: EstadoAlertasCRM = {
  alertas: ['José Equipo Norte', 'Ana Equipo Sur'].map((responsable, i) => ({ id: String(i), responsable,
    tipo: 'bajo_meta_conversion', severidad: i ? 'critica' : 'atencion', alcance: 'empresa',
    titulo: `Conversión ${responsable}`, detalle: 'Revisar la meta mensual', responsableId: String(i), valor: 10,
    destino: { vista: 'ranking-vendedores', etiqueta: 'Ver ranking' },
  })), pendientes: 2, pospuestas: 0, rol: 'gerencia', cargando: false, errores: [], generadoEn: null, reintentar: vi.fn(), reconocer: vi.fn(),
}
function Escena({ abierta = true, cuenta = 'uno' }: { abierta?: boolean; cuenta?: string }) {
  return <PeriodoGerenciaProvider key={cuenta}><AlertasCRMContext value={estado}>{abierta ? <Alertas /> : <p>Detalle</p>}</AlertasCRMContext></PeriodoGerenciaProvider>
}
describe('Bandeja móvil de Gerencia', () => {
  it('pliega filtros, conserva la búsqueda sin tildes al volver y permite limpiar sin perder el total', () => {
    const vista = render(<Escena />)
    expect(screen.queryByRole('searchbox')).not.toBeInTheDocument()
    expect(within(screen.getByRole('list', { name: 'Pendientes activos' })).getAllByRole('listitem')[0]).toHaveTextContent('Ana Equipo Sur')
    fireEvent.click(screen.getByRole('button', { name: 'Filtrar' }))
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'jose' } })
    expect(screen.getByText('1 pendiente activo de 2')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /Filtrar · activos/ }))
    expect(screen.queryByRole('searchbox')).not.toBeInTheDocument()
    vista.rerender(<Escena abierta={false} />)
    vista.rerender(<Escena />)
    expect(screen.getByText('1 pendiente activo de 2')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /Filtrar · activos/ }))
    expect(screen.getByRole('searchbox')).toHaveValue('jose')
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar' }))
    expect(screen.getByText('2 pendientes activos')).toBeVisible()
  })
  it('el cambio de cuenta elimina la consulta anterior y la nueva fuente gobierna el estado vacío', () => {
    const vista = render(<Escena />)
    fireEvent.click(screen.getByRole('button', { name: 'Filtrar' }))
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'sin coincidencias' } })
    expect(screen.getByText('Sin coincidencias')).toBeVisible()
    vista.rerender(<Escena cuenta="dos" />)
    expect(screen.getByText('2 pendientes activos')).toBeVisible()
    expect(screen.queryByRole('searchbox')).not.toBeInTheDocument()
  })
  it.each([['gerencia', false], ['supervisor', false], ['supervisor', true]] as const)('mantiene los cortes pospuestos visibles para %s, móvil=%s', (rol, movil) => {
    ancho.movil = movil
    const corte = avisosFixture().alertas[0]!
    const fuente: EstadoAlertasCRM = { ...estado, rol, pendientes: 0, alertas: [{ ...estado.alertas[0]!, tipo: 'corte_manana', titulo: 'Corte pospuesto', corte: { ...corte, estado: 'pospuesto', pospuesto_hasta: corte.fin_jornada } }] }
    render(<PeriodoGerenciaProvider><AlertasCRMContext value={fuente}><Alertas /></AlertasCRMContext></PeriodoGerenciaProvider>)
    expect(screen.getByText('Corte pospuesto')).toBeVisible()
  })
})
