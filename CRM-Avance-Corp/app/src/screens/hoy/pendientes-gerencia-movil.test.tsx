import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AlertasCRMContext, type EstadoAlertasCRM } from '@/lib/alertas-context'
import { alertasActivas } from '@/lib/alertas-presentacion'
import type { AlertaCRM } from '@/lib/alertas'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { usePeriodoGerencia } from '@/components/gerencia/use-periodo-gerencia'
import { PendientesGerenciaMovil } from './pendientes-gerencia-movil'

const aviso = (id: string, severidad: AlertaCRM['severidad'] = 'atencion'): AlertaCRM => ({
  id, severidad, tipo: 'bajo_meta_conversion', alcance: 'empresa', titulo: `Revisar ${id}`,
  detalle: 'Conversión por debajo de la meta evaluable.', responsableId: null, responsable: null, valor: 10,
  destino: { vista: 'ranking-vendedores', etiqueta: 'Ver ranking', periodo: { desde: '2026-09-01', hasta: '2026-09-30' } },
})
function montar(cambios: Partial<EstadoAlertasCRM> = {}) {
  const estado: EstadoAlertasCRM = { alertas: [], pendientes: 0, pospuestas: 0, cargando: false,
    rol: 'gerencia', errores: [], generadoEn: '2026-10-05T15:00:00Z', reintentar: vi.fn(), reconocer: vi.fn(), ...cambios }
  const renderizar = (s: EstadoAlertasCRM) => <PeriodoGerenciaProvider><AlertasCRMContext value={s}><PendientesGerenciaMovil /><Sonda /></AlertasCRMContext></PeriodoGerenciaProvider>
  const vista = render(renderizar(estado))
  return { estado, cambiar: (c: Partial<EstadoAlertasCRM>) => vista.rerender(renderizar({ ...estado, ...c })) }
}
function Sonda() { const { periodo } = usePeriodoGerencia(); return <output aria-label="Período">{periodo.desde} / {periodo.hasta}</output> }
afterEach(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, value: true }) })

describe('Pendientes de gestión en Resumen', () => {
  it('prioriza críticas, conserva empates y fuente, muestra tres y cuenta los mismos avisos que la campana', () => {
    const avisos = [aviso('atención-1'), aviso('crítica-1', 'critica'), aviso('atención-2'), aviso('crítica-2', 'critica')]
    const foto = JSON.stringify(avisos)
    montar({ alertas: avisos, pendientes: 4 })
    expect(screen.getByRole('link', { name: /Ver todos/ })).toHaveTextContent('(4)')
    const tarjetas = within(screen.getByRole('list', { name: 'Pendientes prioritarios' })).getAllByRole('listitem')
    expect(tarjetas).toHaveLength(3)
    expect(tarjetas.map(t => within(t).getByRole('link').textContent)).toEqual([
      expect.stringContaining('crítica-1'), expect.stringContaining('crítica-2'), expect.stringContaining('atención-1'),
    ])
    expect(JSON.stringify(avisos)).toBe(foto)
    expect(screen.queryByText(/Responsable:/)).not.toBeInTheDocument()
    fireEvent.click(within(tarjetas[0]!).getByRole('link'))
    expect(screen.getByLabelText('Período')).toHaveTextContent('2026-09-01 / 2026-09-30')
  })
  it('no anuncia cero durante primera carga; muestra vacío honesto al terminar', () => {
    const vista = montar({ cargando: true })
    expect(screen.getByText('Cargando pendientes…')).toBeVisible()
    expect(screen.queryByRole('link', { name: /Ver todos/ })).not.toBeInTheDocument()
    vista.cambiar({ cargando: false })
    expect(screen.getByText(/Puede faltar un corte/)).toBeVisible()
  })
  it('conserva los datos parciales y permite reintentar sin confundirlos con evaluación completa', () => {
    const { estado } = montar({ alertas: [aviso('uno')], pendientes: 1, errores: ['No se pudo leer una fuente.'] })
    expect(screen.getByRole('alert')).toHaveTextContent('Información incompleta')
    expect(screen.getByRole('listitem')).toHaveTextContent('Revisar uno')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(estado.reintentar).toHaveBeenCalledOnce()
  })
  it('explica reconocidas y pospuestas sin tratarlas como activas', () => {
    const reconocida = { ...aviso('reconocida'), reconocimiento: { accion: 'reconocer', creadoEn: '2026-10-05T00:00:00Z', venceEn: Date.parse('2026-10-10T00:00:00Z') } } as AlertaCRM
    montar({ alertas: [reconocida], pendientes: 0, pospuestas: 2 })
    expect(screen.queryByRole('listitem')).not.toBeInTheDocument()
    expect(screen.getByText('1 reconocidas · 2 pospuestas hasta su fecha')).toBeVisible()
    expect(alertasActivas([reconocida, aviso('activa')]).map(a => a.id)).toEqual(['activa'])
  })
  it('señala pérdida de conexión y retira el aviso al recuperarla sin iniciar un sondeo propio', () => {
    const { estado } = montar({ alertas: [aviso('uno')], pendientes: 1 })
    act(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, value: false }); window.dispatchEvent(new Event('offline')) })
    expect(screen.getByText(/Sin conexión/)).toBeVisible()
    act(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, value: true }); window.dispatchEvent(new Event('online')) })
    expect(screen.queryByText(/Sin conexión/)).not.toBeInTheDocument()
    expect(estado.reintentar).not.toHaveBeenCalled()
  })
})
