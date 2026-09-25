import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ObservacionRentabilidad } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  habilitada: undefined as boolean | undefined,
  dias: undefined as number | undefined,
  refetch: vi.fn(),
  yo: { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: false } as { id: string; rol: string; demo: boolean },
}))

vi.mock('@/data/crm-queries', () => ({
  useObservacionRentabilidad: (habilitada: boolean, dias: number) => {
    dobles.habilitada = habilitada
    dobles.dias = dias
    return { refetch: dobles.refetch, ...dobles.consulta }
  },
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

const { ObservacionRentabilidadPanel } = await import('./observacion-rentabilidad')
const { motivoSinRegla } = await import('@/lib/rentabilidad')

function payload(sobre: Partial<ObservacionRentabilidad> = {}): ObservacionRentabilidad {
  return {
    periodo: { desde: '2026-08-08', hasta: '2026-09-06' },
    politica: { version: 1, modo: 'observacion', tasa_base_nueva: 15 },
    totales: {
      observados: 12, eventos: 13, importe_no_calculable: 0, divergentes: 5, ceden: 4, retienen: 1, sin_regla: 2, correcciones: 1,
      puntos_promedio_cedido: 2.5,
      cedido: { PEN: 1840.5, USD: 0 }, retenido: { PEN: 120, USD: 0 },
    },
    por_regla: [{ regla: 'primera_inversion', observados: 9, divergentes: 4 }, { regla: 'heredada_renovacion', observados: 1, divergentes: 1 }, { regla: 'sin_regla', observados: 2, divergentes: 0 }],
    por_analista: [
      { analista_id: 'a-ana', analista_nombre: 'Ana Torres', observados: 6, divergentes: 3, puntos_promedio_cedido: 3, cedido_pen: 1200, cedido_usd: 0, retenido_pen: 0, retenido_usd: 0 },
      { analista_id: 'a-luis', analista_nombre: 'Luis Paredes', observados: 4, divergentes: 2, puntos_promedio_cedido: 1.5, cedido_pen: 640.5, cedido_usd: 0, retenido_pen: 120, retenido_usd: 0 },
      { analista_id: 'sin-analista', analista_nombre: 'Sin analista', observados: 2, divergentes: 0, puntos_promedio_cedido: 0, cedido_pen: 0, cedido_usd: 0, retenido_pen: 0, retenido_usd: 0 },
    ],
    sin_regla: [{ motivo: 'upgrade_origen_ambiguo', n: 2 }],
    ultimos_divergentes: [],
    metodo: 'simple_sobre_plazo_revision_efectiva',
    altas_sin_observar: 0,
    cobertura: { observacion_activa_desde: '2026-09-06T21:30:00+00:00', cobertura_desde: '2026-09-06T21:30:00+00:00', periodo_sin_cobertura: true },
    sondas: { consistencia_interna: true, cobertura_altas: true, cobertura_correcciones: 'desconocida' },
    coherente: true,
    ...sobre,
  }
}

function ok(data: ObservacionRentabilidad) {
  dobles.consulta = { data, isPending: false, isError: false, isFetching: false }
}

describe('ObservacionRentabilidadPanel (Rentabilidad R2)', () => {
  beforeEach(() => {
    dobles.consulta = {}
    dobles.habilitada = undefined
    dobles.dias = undefined
    dobles.refetch.mockReset()
    dobles.yo = { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: false }
  })

  it('sin observaciones en el horizonte → vacío honesto, con la RPC habilitada a 30 días', () => {
    ok(payload({ totales: { ...payload().totales, observados: 0, divergentes: 0, ceden: 0, retienen: 0, sin_regla: 0, correcciones: 0 }, por_analista: [], sin_regla: [] }))
    render(<ObservacionRentabilidadPanel />)
    expect(dobles.habilitada).toBe(true)
    expect(dobles.dias).toBe(30)
    expect(screen.getByText('Sin altas observadas en los últimos 30 días')).toBeInTheDocument()
    // La región viva redacta distinto al PanelVacio (no duplica el texto visible).
    expect(screen.getByRole('status')).toHaveTextContent(/Sin contratos observados/)
  })

  it('con datos: tiles, ranking de quién cede margen y casos sin regla traducidos', () => {
    ok(payload())
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByText('Observados')).toBeInTheDocument()
    expect(screen.getByText('12')).toBeInTheDocument()
    expect(screen.getByText('5')).toBeInTheDocument()
    expect(screen.getAllByText(/S\/ 1,840\.5/).length).toBeGreaterThan(0)
    const ranking = screen.getByRole('list', { name: 'Margen cedido por analista' })
    const filas = ranking.querySelectorAll('li')
    expect(filas).toHaveLength(2) // «Sin analista» no cede: no aparece
    expect(filas[0]).toHaveTextContent('Ana Torres')
    expect(filas[0]).toHaveTextContent('S/ 1,200')
    expect(filas[1]).toHaveTextContent('Luis Paredes')
    const casos = screen.getByRole('list', { name: 'Casos sin regla por motivo' })
    expect(casos).toHaveTextContent(/Upgrade sin contrato origen claro/)
    expect(casos).toHaveTextContent(/2 casos/)
    expect(screen.getByText(/política v1: base 15%, Observación/)).toBeInTheDocument()
    expect(screen.getByText(/Hoy la política no bloquea/)).toBeInTheDocument()
  })

  it('si el servidor declara incoherencia, la tarjeta lo dice con un alert y la región viva no lee cifras', () => {
    ok(payload({ coherente: false }))
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByRole('alert')).toHaveTextContent(/no cuadran entre sí/)
    expect(screen.getByRole('status')).toHaveTextContent(/en revisión/)
    expect(screen.getByRole('status')).not.toHaveTextContent(/fuera de la base/)
  })

  it('si hubo altas sin observar, el alert lo dice con el número', () => {
    ok(payload({ coherente: false, altas_sin_observar: 3 }))
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByRole('alert')).toHaveTextContent(/3 altas del periodo quedaron sin observar/)
  })

  it('con 0 observados pero altas sin observar, manda la alarma y no el vacío (Codex #27)', () => {
    ok(payload({ coherente: false, altas_sin_observar: 3, totales: { ...payload().totales, observados: 0, divergentes: 0, ceden: 0, retienen: 0, sin_regla: 0, correcciones: 0 }, por_analista: [], sin_regla: [] }))
    render(<ObservacionRentabilidadPanel />)
    expect(screen.queryByText(/Sin altas observadas/)).toBeNull()
    expect(screen.getByRole('alert')).toHaveTextContent(/3 altas del periodo quedaron sin observar/)
    expect(screen.getByRole('status')).toHaveTextContent(/en revisión/)
  })

  it('coherente → sin alert', () => {
    ok(payload())
    render(<ObservacionRentabilidadPanel />)
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('cargando (sin datos previos): skeleton', () => {
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByRole('status')).toHaveTextContent(/Cargando/)
    expect(screen.queryByText('Observados')).toBeNull()
  })

  it('error: mensaje y Reintentar dispara refetch', () => {
    dobles.consulta = { data: undefined, isPending: false, isError: true }
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByText(/Revisa tu conexión y vuelve a intentarlo/)).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent(/No se pudo cargar/)
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(dobles.refetch).toHaveBeenCalledTimes(1)
  })

  it('el selector de horizonte re-consulta con los días elegidos', () => {
    ok(payload())
    render(<ObservacionRentabilidadPanel />)
    fireEvent.click(screen.getByRole('button', { name: '7 días' }))
    expect(dobles.dias).toBe(7)
    expect(screen.getByRole('button', { name: '7 días' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('al cambiar de horizonte, la región viva re-anuncia la carga sin mover el foco', () => {
    ok(payload())
    const { rerender } = render(<ObservacionRentabilidadPanel />)
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    fireEvent.click(screen.getByRole('button', { name: '90 días' }))
    rerender(<ObservacionRentabilidadPanel />)
    expect(screen.getByRole('status')).toHaveTextContent(/Cargando/)
  })

  it('la región viva anuncia el resultado', () => {
    ok(payload())
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByRole('status')).toHaveTextContent(/5 de 12 contratos fuera de la base/)
  })

  it('en DEMO la RPC queda inerte (enabled=false) y se explica el vacío', () => {
    dobles.yo = { ...dobles.yo, demo: true }
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    render(<ObservacionRentabilidadPanel />)
    expect(dobles.habilitada).toBe(false)
    expect(screen.getByText('La observación solo existe en sesión real')).toBeInTheDocument()
  })

  it('si el registro empezó dentro del horizonte, el pie dice desde cuándo observa', () => {
    ok(payload())
    const { container } = render(<ObservacionRentabilidadPanel />)
    expect(screen.getAllByText(/Observación desde el 06 set\.? 2026, cuando empezó el registro/).length).toBeGreaterThan(0)
    expect(screen.queryByText(/Observación de los últimos 30 días/)).toBeNull()
    // La región viva lo anuncia igual, y sin paréntesis anidados.
    const estado = container.querySelector('p[role="status"].sr-only')
    expect(estado).toHaveTextContent(/fuera de la base · Observación desde el 06 set/)
    expect(estado?.textContent ?? '').not.toContain('))')
  })

  it('con el registro más antiguo que el horizonte, el pie dice «últimos N días»', () => {
    ok(payload({ cobertura: { observacion_activa_desde: '2026-06-01T00:00:00+00:00', cobertura_desde: '2026-08-08T05:00:00+00:00', periodo_sin_cobertura: false } }))
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getAllByText(/Observación de los últimos 30 días/).length).toBeGreaterThan(0)
    expect(screen.queryByText(/cuando empezó el registro/)).toBeNull()
  })

  it('motivoSinRegla traduce los motivos técnicos del observador', () => {
    expect(motivoSinRegla('upgrade_origen_ambiguo')).toBe('Upgrade sin contrato origen claro')
    expect(motivoSinRegla('upgrade_sin_contrato_activo_previo')).toBe('Upgrade sin contrato activo previo')
    expect(motivoSinRegla('resolver:P0409:El cliente está inactivo')).toBe('Cliente inactivo o contrato origen cerrado')
    expect(motivoSinRegla('resolver:22023:Selecciona la categoría')).toBe('Contrato sin categoría o sin origen')
    expect(motivoSinRegla('resolver:XX000:raro')).toBe('El núcleo no pudo decidir')
    expect(motivoSinRegla('otro')).toBe('otro')
  })

  it('R4: con el candado activo, la tarjeta lo dice y ya no promete que nada se bloquea', () => {
    ok(payload({ politica: { version: 2, modo: 'enforcement', tasa_base_nueva: 15 } }))
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByText(/política v2: base 15%, Candado activo/)).toBeInTheDocument()
    expect(screen.getByText(/solo puede venir de una autorización de Gerencia/)).toBeInTheDocument()
    expect(screen.queryByText(/Hoy la política no bloquea/)).toBeNull()
  })

  it('sin política legible no se afirma si el servidor bloquea', () => {
    ok(payload({ politica: null }))
    render(<ObservacionRentabilidadPanel />)
    expect(screen.getByText(/No se pudo leer el modo de la política/)).toBeInTheDocument()
    expect(screen.queryByText(/Hoy la política no bloquea/)).toBeNull()
  })
})
