import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  decidir: vi.fn(),
  yo: { id: 'g-1', rol: 'gerencia', demo: false } as { id: string; rol: string; demo: boolean },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/data/crm-queries', () => ({
  useSolicitudesTasa: () => ({ refetch: vi.fn(), ...dobles.consulta }),
  useResolverSolicitudTasa: () => ({ mutateAsync: dobles.decidir, isPending: false }),
}))
const { SolicitudesTasaGerenciaPanel } = await import('./solicitudes-tasa-gerencia')

function solicitud(sobre: Partial<SolicitudTasa> = {}): SolicitudTasa {
  return {
    id: 's-1', estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true, categoria: 'nuevo', cliente_id: 'cli-1', cliente_nombre: 'ANA TORRES',
    contrato_origen_id: null, contrato_origen_numero: null, producto_condicion_id: null, capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple',
    fecha_inicio: '2026-10-01', fecha_vencimiento: '2027-10-01', tasa_base: 15, regla_base: 'primera_inversion', tasa_solicitada: 18,
    tasa_maxima_autorizada: null, motivo: 'Cliente referido con capital fresco', motivo_resolucion: null, motivo_analista: null,
    prioridad_bandeja: true, contratos_previos: 2, solicitada_por: 'v-1', solicitante_nombre: 'LUIS PAREDES',
    solicitada_en: '2026-09-06T10:00:00Z', vence_en: '2026-09-13T10:00:00Z', resuelta_por: null, resolutor_nombre: null, resuelta_en: null,
    respondida_por_analista_en: null, contrato_id: null, es_mia: false, puede_resolver: true, puede_responder: false, ...sobre,
  }
}
const ok = (data: SolicitudTasa[]) => { dobles.consulta = { data, isPending: false, isError: false } }

describe('SolicitudesTasaGerenciaPanel (bandeja R3)', () => {
  beforeEach(() => { dobles.consulta = {}; dobles.decidir.mockReset(); dobles.yo = { id: 'g-1', rol: 'gerencia', demo: false } })

  it('sin pendientes: vacío honesto', () => {
    ok([])
    render(<SolicitudesTasaGerenciaPanel />)
    expect(screen.getByText('Nada por decidir')).toBeInTheDocument()
  })

  it('pinta la solicitud con cliente, analista, base, pedida y motivo; la propia no aparece para decidir', () => {
    ok([solicitud(), solicitud({ id: 's-2', es_mia: true, puede_resolver: false, cliente_nombre: 'PROPIA' })])
    render(<SolicitudesTasaGerenciaPanel />)
    const lista = screen.getByRole('list', { name: 'Solicitudes de tasa pendientes' })
    expect(lista.querySelectorAll('li')).toHaveLength(1)
    expect(lista).toHaveTextContent('ANA TORRES')
    expect(lista).toHaveTextContent('LUIS PAREDES')
    expect(lista).toHaveTextContent('base 15%')
    expect(lista).toHaveTextContent('18%')
    expect(lista).toHaveTextContent('Cliente referido con capital fresco')
    expect(lista).toHaveTextContent(/cliente con 2 contratos/)
    expect(screen.getByText(/Tienes 1 solicitud propia en curso/)).toBeInTheDocument()
  })

  it('Aprobar en un clic llama a la decisión con la tasa pedida', async () => {
    ok([solicitud()])
    dobles.decidir.mockResolvedValue(solicitud({ estado: 'aprobada', tasa_maxima_autorizada: 18 }))
    render(<SolicitudesTasaGerenciaPanel />)
    fireEvent.click(screen.getByRole('button', { name: /Aprobar 18%/ }))
    await waitFor(() => expect(dobles.decidir).toHaveBeenCalledWith({ solicitudId: 's-1', decision: 'aprobar', tasaMaxima: null, motivo: null }))
  })

  it('Rechazar en un clic', async () => {
    ok([solicitud()])
    dobles.decidir.mockResolvedValue(solicitud({ estado: 'rechazada' }))
    render(<SolicitudesTasaGerenciaPanel />)
    fireEvent.click(screen.getByRole('button', { name: /Rechazar/ }))
    await waitFor(() => expect(dobles.decidir).toHaveBeenCalledWith({ solicitudId: 's-1', decision: 'rechazar', tasaMaxima: null, motivo: null }))
  })

  it('muestra y aprueba una solicitud de lead que todavía no tiene cliente', async () => {
    const s = solicitud({ cliente_id: null, lead_id: 'lead-1', cliente_nombre: 'LEAD SIN CLIENTE', prioridad_bandeja: false, contratos_previos: 0 })
    ok([s])
    dobles.decidir.mockResolvedValue({ ...s, estado: 'aprobada', tasa_maxima_autorizada: 18 })
    render(<SolicitudesTasaGerenciaPanel />)
    expect(screen.getByRole('list')).toHaveTextContent('LEAD SIN CLIENTE')
    expect(screen.getByText('Solicitud desde lead')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Aprobar 18%/ }))
    await waitFor(() => expect(dobles.decidir).toHaveBeenCalledWith({ solicitudId: 's-1', decision: 'aprobar', tasaMaxima: null, motivo: null }))
  })

  it('Aprobar hasta X% exige un tope entre la base y lo pedido (D6)', async () => {
    ok([solicitud()])
    dobles.decidir.mockResolvedValue(solicitud({ estado: 'aprobada_con_tope', tasa_maxima_autorizada: 16 }))
    render(<SolicitudesTasaGerenciaPanel />)
    fireEvent.click(screen.getByRole('button', { name: /Aprobar hasta…/ }))
    const tope = screen.getByLabelText('Hasta (%)')
    // a11y: el foco va al campo del tope al abrir
    expect(tope).toHaveFocus()
    // Un tope fuera de rango no deshabilita el botón: al pulsarlo el campo se marca inválido y la ayuda explica el rango.
    fireEvent.change(tope, { target: { value: '15' } })
    fireEvent.click(screen.getByRole('button', { name: /Aprobar hasta …/ }))
    expect(dobles.decidir).not.toHaveBeenCalled()
    expect(tope).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByText(/Escribe un tope mayor que la base \(15%\) y no mayor que lo pedido \(18%\)/)).toBeInTheDocument()
    fireEvent.change(tope, { target: { value: '19' } })
    fireEvent.click(screen.getByRole('button', { name: /Aprobar hasta …/ }))
    expect(dobles.decidir).not.toHaveBeenCalled()
    expect(tope).toHaveAttribute('aria-invalid', 'true')
    fireEvent.change(tope, { target: { value: '16' } })
    expect(tope).not.toHaveAttribute('aria-invalid')
    fireEvent.change(screen.getByLabelText('Motivo (opcional)'), { target: { value: 'Mercado a 16' } })
    fireEvent.click(screen.getByRole('button', { name: /Aprobar hasta 16%/ }))
    await waitFor(() => expect(dobles.decidir).toHaveBeenCalledWith({ solicitudId: 's-1', decision: 'aprobar_hasta', tasaMaxima: 16, motivo: 'Mercado a 16' }))
  })

  it('cargando: skeleton; error: reintentar', () => {
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    const { unmount } = render(<SolicitudesTasaGerenciaPanel />)
    expect(screen.getByRole('status')).toHaveTextContent(/Cargando/)
    unmount()
    const refetch = vi.fn()
    dobles.consulta = { data: undefined, isPending: false, isError: true, refetch }
    render(<SolicitudesTasaGerenciaPanel />)
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(refetch).toHaveBeenCalled()
  })

  it('en demo no consulta y explica el vacío', () => {
    dobles.yo = { ...dobles.yo, demo: true }
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    render(<SolicitudesTasaGerenciaPanel />)
    expect(screen.getByText('La bandeja solo existe en sesión real')).toBeInTheDocument()
  })
})
