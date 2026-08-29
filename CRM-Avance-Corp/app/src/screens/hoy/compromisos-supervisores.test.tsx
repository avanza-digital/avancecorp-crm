// Tests del panel de trazabilidad para gerencia (F4.4): qué alertas
// reconocieron o pospusieron los supervisores y hasta cuándo rigen.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import type { AsientoReconocimiento } from '@/lib/reconocimientos-alertas'
import { TOPE_LISTADO_RECONOCIMIENTOS } from '@/lib/trazabilidad-reconocimientos'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const AHORA = new Date('2026-07-15T15:00:00Z')

let ASIENTOS: AsientoReconocimiento[] = []
let ERROR: unknown = null
let PENDIENTE = false
let HABILITADA: boolean | undefined
const refetch = vi.fn()
vi.mock('@/data/crm-queries', () => ({
  useReconocimientosAlertas: (habilitada: boolean) => {
    HABILITADA = habilitada
    return {
      data: PENDIENTE ? undefined : ASIENTOS,
      error: ERROR,
      isPending: PENDIENTE,
      refetch,
    }
  },
}))

const { CompromisosSupervisoresPanel } = await import('./compromisos-supervisores')

const NOMBRES = new Map([
  ['11111111-1111-4111-8111-111111111111', 'SUPERVISOR REAL UNO'],
  ['d-sup1', 'SUPERVISOR UNO'],
  ['d-sup2', 'SUPERVISOR DOS'],
])

function asiento(over: Partial<AsientoReconocimiento> = {}): AsientoReconocimiento {
  return {
    id: '00000000-0000-4000-8000-000000000001',
    alerta_id: 'grupo:lead_sin_responder:11111111-1111-4111-8111-111111111111',
    accion: 'reconocer',
    miembros: ['l1', 'l2', 'l3'],
    severidad: 'critica',
    hasta: null,
    creado_en: '2026-07-15T13:00:00Z',
    secuencia: 1,
    ...over,
  }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(AHORA)
  ASIENTOS = []
  ERROR = null
  PENDIENTE = false
  HABILITADA = undefined
  refetch.mockClear()
})

afterEach(() => {
  cleanup()
  vi.useRealTimers()
})

describe('CompromisosSupervisoresPanel', () => {
  it('lista cada compromiso con supervisor, verbo, etiqueta, unidad, severidad y hasta cuándo (con hora de Lima)', () => {
    ASIENTOS = [
      asiento(), // reconocer crítica hace 2 h → rige hasta creado + 7 días
      asiento({
        id: '00000000-0000-4000-8000-000000000002',
        alerta_id: 'grupo:sin_proxima_accion:11111111-1111-4111-8111-111111111111',
        accion: 'posponer',
        severidad: 'atencion',
        miembros: ['v-9'],
        hasta: '2026-07-16T15:00:00Z',
        creado_en: '2026-07-15T14:00:00Z',
        secuencia: 2,
      }),
    ]
    render(<CompromisosSupervisoresPanel demo={false} nombrePorId={NOMBRES} />)

    expect(HABILITADA).toBe(true)
    expect(screen.getByText('2 compromisos · 1 supervisor')).toBeInTheDocument()
    const filas = screen.getAllByRole('listitem')
    expect(filas).toHaveLength(2)
    // Más reciente primero: la posposición, con su UNIDAD real (analistas).
    expect(filas[0]).toHaveTextContent('SUPERVISOR REAL UNO')
    expect(filas[0]).toHaveTextContent('pospuso «Leads sin próxima acción» (1 analista)')
    expect(filas[0]).toHaveTextContent('severidad de atención · hace 1 h · se reactiva el 16 de julio a las 10:00')
    expect(filas[1]).toHaveTextContent('reconoció «Leads nuevos sin responder» (3 leads)')
    expect(filas[1]).toHaveTextContent('severidad crítica · hace 2 h · rige como máximo hasta el 22 de julio a las 08:00')
    // El límite de la tarjeta se dice en llano: empeorar la anula antes.
    expect(screen.getByText(/vuelve a sonar en la campana del supervisor antes de su fecha/)).toBeInTheDocument()
  })

  it('con la caché fría NO inventa un vacío: dice que está consultando', () => {
    PENDIENTE = true
    render(<CompromisosSupervisoresPanel demo={false} nombrePorId={NOMBRES} />)
    expect(screen.getByText('Consultando los compromisos…')).toBeInTheDocument()
    expect(screen.queryByText(/Ningún compromiso/)).not.toBeInTheDocument()
  })

  it('sin compromisos DICE el vacío: la ausencia es la información que gerencia audita', () => {
    render(<CompromisosSupervisoresPanel demo={false} nombrePorId={NOMBRES} />)
    expect(screen.getByText(/Ningún compromiso en curso/)).toBeInTheDocument()
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
  })

  it('con la consulta caída no inventa: lo dice y ofrece reintentar', () => {
    ERROR = new Error('cayó')
    ASIENTOS = [asiento()]
    render(<CompromisosSupervisoresPanel demo={false} nombrePorId={NOMBRES} />)

    expect(screen.getByText(/No se pudieron cargar los compromisos/)).toBeInTheDocument()
    expect(screen.queryByRole('listitem')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(refetch).toHaveBeenCalledTimes(1)
  })

  it('al llegar al tope del listado lo CONFIESA: puede faltar trazabilidad', () => {
    ASIENTOS = Array.from({ length: TOPE_LISTADO_RECONOCIMIENTOS }, (_, i) => asiento({
      id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
      alerta_id: `grupo:por_repartir:11111111-1111-4111-8111-${String(i).padStart(12, '1')}`,
      secuencia: i + 1,
    }))
    render(<CompromisosSupervisoresPanel demo={false} nombrePorId={NOMBRES} />)
    expect(screen.getByText(/llegó al tope de 1000 registros/)).toBeInTheDocument()
  })

  it('en demo enseña el espejo local y NO consulta al servidor', () => {
    render(<CompromisosSupervisoresPanel demo nombrePorId={NOMBRES} />)

    expect(HABILITADA).toBe(false)
    expect(screen.getByText('3 compromisos · 2 supervisores')).toBeInTheDocument()
    const texto = screen.getAllByRole('listitem').map((li) => li.textContent).join('\n')
    expect(texto).toContain('SUPERVISOR UNO')
    expect(texto).toContain('SUPERVISOR DOS')
  })

  it('un supervisor fuera del roster no rompe la traza: se dice, sin ocultar la fila', () => {
    ASIENTOS = [asiento({ alerta_id: 'grupo:tarea_vencida:99999999-9999-4999-8999-999999999999' })]
    render(<CompromisosSupervisoresPanel demo={false} nombrePorId={NOMBRES} />)
    expect(screen.getByRole('listitem'))
      .toHaveTextContent('Un supervisor ya fuera del equipo reconoció «Leads con plazo vencido»')
  })
})
