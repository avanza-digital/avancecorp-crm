import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { CITAS_CRM } from '@/prototypes/citas-crm/datos'
import { totalEnSoles } from '@/lib/capital-unificado'
import { hashDe, leerHash } from '@/lib/router'
import { mesConsultaCitas } from '@/lib/enlace-citas'
import { consultaInicial, consultarCitas, rangoConsulta } from '@/components/citas/datos'
import type { Miembro } from '@/lib/tipos'
import { resumirCitasDia } from './resumen-gerencia-movil-modelo'
import { ResumenGerenciaMovil } from './resumen-gerencia-movil'

const consultas = vi.hoisted(() => ({
  citas: { isError: false, isPending: false, refetch: vi.fn() },
  solicitudes: { data: [{ puede_resolver: true }, { puede_resolver: false }], isError: false, isPending: false, refetch: vi.fn() },
}))
const miembros: Miembro[] = [
  { perfil_id: 'd-sup1', nombre_completo: 'Ana', rol_crm: 'supervisor', activo: true },
  { perfil_id: 'd-sup2', nombre_completo: 'Luis', rol_crm: 'supervisor', activo: true },
]
const citas = [
  { ...CITAS_CRM[0]!, id: 'c1', fecha: '2026-10-05', supervisorId: 'd-sup1', supervisor: 'Ana', estado: 'realizada' as const },
  { ...CITAS_CRM[0]!, id: 'c2', fecha: '2026-10-05', supervisorId: 'd-sup1', supervisor: 'Ana', estado: 'cancelada' as const },
  { ...CITAS_CRM[0]!, id: 'c3', fecha: '2026-10-05', supervisorId: 'sin_supervisor', supervisor: 'Sin supervisor' },
  { ...CITAS_CRM[0]!, id: 'c4', fecha: '2026-10-04', supervisorId: 'd-sup1' },
  { ...CITAS_CRM[0]!, id: 'c5', fecha: '2026-10-06', supervisorId: 'd-sup2' },
]
vi.mock('./use-datos-citas-gerencia', () => ({ useDatosCitasGerencia: () => ({ yo: { id: 'gerencia', demo: false }, datos: {}, citas, equipo: miembros, consulta: consultas.citas }) }))
vi.mock('@/data/crm-queries', () => ({ useSolicitudesTasa: () => consultas.solicitudes }))
vi.mock('./solicitudes-tasa-gerencia', () => ({ SolicitudesTasaGerenciaPanel: () => <p>Bandeja existente</p> }))
const props = () => ({ dia: '2026-10-05', mes: 'octubre 2026', capital: totalEnSoles(100, 10, 3.5), meta: totalEnSoles(200, 20, 3.5), fuenteTc: 'BCRP', cargando: false, error: null, onReintentar: vi.fn(), onActualizar: vi.fn(), onMetas: vi.fn(), onCompleto: vi.fn(), aviso: null })

beforeEach(() => {
  window.history.replaceState(null, '', '#/hoy')
  consultas.citas.isError = consultas.citas.isPending = false
  consultas.solicitudes.isError = consultas.solicitudes.isPending = false
  vi.clearAllMocks()
})

describe('Resumen móvil de Gerencia', () => {
  it('incluye todos los estados, los equipos sin citas y el grupo sin supervisor; cada enlace devuelve su total', () => {
    const resumen = resumirCitasDia(citas, '2026-10-05', miembros)
    expect(resumen.total).toBe(3)
    expect(resumen.realizadas).toBe(1)
    expect(resumen.equipos.map(g => g.total)).toEqual([2, 0, 1])
    expect(resumen.equipos.reduce((s, g) => s + g.total, 0)).toBe(resumen.total)
    for (const grupo of resumen.equipos) {
      window.history.replaceState(null, '', hashDe('reuniones', null, undefined, undefined, undefined, undefined, { dia: '2026-10-05', equipo: grupo.id }))
      const enlace = leerHash().consultaCitas!
      expect(consultarCitas({ ...consultaInicial(mesConsultaCitas(enlace)), ...enlace, equipo: enlace.equipo! }, citas)).toHaveLength(grupo.total)
    }
    expect(rangoConsulta({ ...consultaInicial('2026-10'), dia: '2026-09-30' })).toEqual(['', ''])
  })

  it('muestra el capital convertido, la meta y solo las solicitudes que el actor puede resolver', () => {
    const p = props()
    render(<PeriodoGerenciaProvider><ResumenGerenciaMovil {...p} /></PeriodoGerenciaProvider>)
    expect(screen.getByRole('button', { name: /Capital confirmado/ })).toHaveTextContent('S/ 135')
    expect(screen.getByRole('button', { name: /Meta de capital/ })).toHaveTextContent('50%')
    expect(screen.getByRole('button', { name: /Solicitudes/ })).toHaveTextContent('1')
    fireEvent.click(screen.getByRole('button', { name: /Capital confirmado/ }))
    expect(p.onMetas).toHaveBeenCalledOnce()
    fireEvent.click(screen.getByRole('button', { name: /Solicitudes/ }))
    expect(within(screen.getByRole('dialog')).getByText('Bandeja existente')).toBeVisible()
  })

  it('sin TC deja el USD separado y no calcula un porcentaje; sin meta no inventa cumplimiento', () => {
    const p = props()
    const vista = render(<PeriodoGerenciaProvider><ResumenGerenciaMovil {...p} capital={totalEnSoles(100, 10, null)} meta={totalEnSoles(200, 20, null)} /></PeriodoGerenciaProvider>)
    expect(screen.getByRole('button', { name: /Capital confirmado/ })).toHaveTextContent('S/ 100')
    expect(screen.getByText(/US\$ 10 sin convertir/)).toBeVisible()
    expect(screen.getByRole('button', { name: /Meta de capital/ })).not.toHaveTextContent('%')
    vista.rerender(<PeriodoGerenciaProvider><ResumenGerenciaMovil {...p} meta={totalEnSoles(0, 0, 3.5)} /></PeriodoGerenciaProvider>)
    expect(screen.getByText('Sin meta de capital configurada')).toBeVisible()
  })

  it('oculta cifras anteriores al fallar la actualización y permite reintentar', () => {
    consultas.citas.isError = consultas.solicitudes.isError = true
    const p = props()
    render(<PeriodoGerenciaProvider><ResumenGerenciaMovil {...p} error="No se pudo actualizar el capital." /></PeriodoGerenciaProvider>)
    expect(screen.getByRole('button', { name: /Capital confirmado/ })).not.toHaveTextContent('S/ 135')
    expect(screen.getByRole('link', { name: /Citas de hoy/ })).toHaveTextContent('—')
    expect(screen.queryByRole('link', { name: /Equipo de Ana/ })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Solicitudes/ })).toHaveTextContent('—')
    fireEvent.click(within(screen.getByText('No se pudieron actualizar las citas.').parentElement!).getByRole('button'))
    expect(consultas.citas.refetch).toHaveBeenCalledOnce()
  })

  it('abre el enlace de una solicitud y revalida al recuperar el foco', () => {
    window.history.replaceState(null, '', '#/hoy/solicitud-tasa/10000000-0000-4000-8000-000000000001')
    const p = props()
    render(<PeriodoGerenciaProvider><ResumenGerenciaMovil {...p} /></PeriodoGerenciaProvider>)
    expect(screen.getByRole('dialog', { name: 'Solicitudes de tasa' })).toBeVisible()
    act(() => window.dispatchEvent(new Event('focus')))
    expect(p.onActualizar).toHaveBeenCalledOnce()
    expect(consultas.citas.refetch).not.toHaveBeenCalled()
    const historial = window.history.length
    fireEvent.click(screen.getByRole('button', { name: 'Volver al resumen' }))
    expect(window.location.hash).toBe('#/hoy')
    expect(window.history.length).toBe(historial)
  })
})
