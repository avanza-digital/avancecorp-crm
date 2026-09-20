// «Mi día» del analista: la cola agrupada en el orden que manda, el marcador
// con su tasa y su conteo, los compromisos, los descartes con Deshacer, y el
// ESTADO DE PRODUCCIÓN (un día sin llamadas ni cola) que es lo que hoy vería
// un analista real. Fail-closed: si el servidor cae, se dice, no se pinta.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import type { DiaAnalista } from '@/lib/gestion-diaria-analista'

const dobles = vi.hoisted(() => ({
  yo: { id: 'a1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' },
  dia: null as DiaAnalista | null,
  errorDia: null as unknown,
  recargar: vi.fn(async () => {}),
  cola: { data: undefined as unknown, error: null as unknown, refetch: vi.fn(), isFetching: false },
  abrirLead: vi.fn(),
  deshacer: vi.fn(async () => ({ ok: true })),
  panel: { props: null as Record<string, unknown> | null },
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-20T18:00:00Z') }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: [{ id: 'l1', nombre_completo: 'NUEVO SIN INTENTO', telefono: '+51999000111', etapa: 'nuevo' }] }, tareasDe: () => [] }),
  usePanelesActions: () => ({ abrirLead: dobles.abrirLead }),
}))
vi.mock('@/data/gestion-diaria-queries', () => ({
  useDiaAnalista: () => ({ dia: dobles.dia, cargando: false, enVuelo: false, error: dobles.errorDia, recargar: dobles.recargar }),
}))
vi.mock('@/data/sla-operacion-queries', () => ({ useColaSlaPagina: () => dobles.cola }))
vi.mock('@/data/gestion-diaria-api', () => ({ deshacerResultadoLlamada: dobles.deshacer }))
vi.mock('@/components/app/contacto', () => ({ AccionesContacto: () => <span data-testid="acciones-contacto" /> }))
vi.mock('@/components/gestion-diaria/registrar-resultado', () => ({
  RegistrarResultado: (props: Record<string, unknown>) => { dobles.panel.props = props; return <div role="dialog" aria-label="Resultado (mock)" /> },
}))
const { GestionDiariaAnalista } = await import('./analista')

const senal = (id: string, extra: Record<string, unknown> = {}) => ({
  lead_id: id, nombre_completo: `LEAD ${id}`, etapa: 'nuevo', tenencia_desde: '2026-09-20T12:00:00Z',
  ciclo_desde: '2026-09-20T12:00:00Z', llamadas_ciclo: 0, intentos_sin_respuesta: 0, ultima_llamada_en: null,
  ultima_llamada_tipo: null, ultima_llamada_resultado: null, ultima_conversacion_en: null,
  dias_sin_conversacion: 0, sin_conversacion: false, numero_errado_detalle: null, numero_errado_en: null,
  proxima_tarea_en: null, proxima_tarea_tipo: null, ...extra,
})

const DIA_LLENO = {
  version: 1, generado_en: '2026-09-20T18:00:00Z', dia: '2026-09-20', zona: 'America/Lima', analista_id: 'a1',
  umbrales: { version: 1, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 },
  sin_conversacion_dias: 7,
  marcador: {
    llamadas: 9, contestadas: 5, utiles: 8, tasa_contacto_pct: 63, nivel: 'bien', leads_tocados: 7,
    citas_agendadas: 1, primera_llamada_en: '2026-09-20T14:00:00Z', ultima_llamada_en: '2026-09-20T17:30:00Z',
    por_resultado: { volver_a_llamar: 3, no_contesto: 4 },
    por_hora: [{ hora: 9, llamadas: 4, contestadas: 2 }, { hora: 12, llamadas: 5, contestadas: 3 }],
  },
  compromisos: [{ tarea_id: 't1', lead_id: 'l9', lead_nombre: 'MARTÍN MUÑOZ', lead_etapa: 'contactado', tipo: 'llamada', titulo: 'Volver a llamar', vence_en: '2026-09-21T15:00:00Z', modalidad_reunion: null }],
  compromisos_total: 1,
  cartera: [senal('l1'), senal('l3', { sin_conversacion: true, dias_sin_conversacion: 12, etapa: 'contactado' })],
  cartera_truncada: false,
  descartados: [{ actividad_id: 'act1', lead_id: 'l4', lead_nombre: 'ELENA VARGAS', lead_etapa: 'descartado', resultado: 'no_interesado', submotivo: 'desconfianza', motivo_descarte: 'sin_interes', creado_en: '2026-09-20T16:00:00Z', deshecho: false, vigente: true, no_insista: false, puede_deshacer: true }],
} as unknown as DiaAnalista

const itemCola = (id: string, bucket: string, referencia: string | null) => ({
  lead_id: id, bucket, severidad: 'media', prioridad: 0, referencia_en: referencia, tarea_id: null,
  lead: { id, nombre_completo: id === 'l1' ? 'NUEVO SIN INTENTO' : `LEAD ${id}`, etapa: 'nuevo', analista_id: 'a1', analista_nombre: 'ANALISTA UNO' },
})

beforeEach(() => {
  vi.clearAllMocks()
  dobles.yo = { id: 'a1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }
  dobles.dia = DIA_LLENO
  dobles.errorDia = null
  dobles.cola = { data: { items: [itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'), itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z')] }, error: null, refetch: vi.fn(), isFetching: false }
  dobles.panel.props = null
})

describe('GestionDiariaAnalista', () => {
  it('agrupa la cola con el lead sin primer intento ARRIBA de lo vencido', () => {
    render(<GestionDiariaAnalista />)
    // El gráfico por hora también es una lista, pero se nombra por su encabezado.
    const grupos = screen.getAllByRole('list').map((l) => l.getAttribute('aria-label')).filter((n) => n !== null)
    expect(grupos.slice(0, 3)).toEqual(['Sin primer intento (1)', 'Vencidas (1)', 'Sin conversación (1)'])
    const primero = screen.getByRole('list', { name: 'Sin primer intento (1)' })
    expect(within(primero).getByRole('button', { name: 'NUEVO SIN INTENTO' })).toBeInTheDocument()
    expect(within(primero).getByText('Ningún intento todavía')).toBeInTheDocument()
  })

  it('el marcador lleva el % con su conteo y el chip de nivel', () => {
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('63 % · 8 llamadas')).toBeInTheDocument()
    expect(screen.getAllByText('Bien').length).toBeGreaterThan(0)
    expect(screen.getByText(/No incluye WhatsApp ni citas/)).toBeInTheDocument()
  })

  it('sin llamadas útiles no hay chip ni porcentaje inventado', () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, por_hora: [] } } as DiaAnalista
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.getByText(/Se juzga desde 5 llamadas útiles/)).toBeInTheDocument()
    expect(screen.queryByText('Bien')).not.toBeInTheDocument()
  })

  it('«Registrar resultado» abre el panel de la Fase 2 con el lead de la fila', () => {
    render(<GestionDiariaAnalista />)
    const primero = screen.getByRole('list', { name: 'Sin primer intento (1)' })
    fireEvent.click(within(primero).getByRole('button', { name: /Registrar resultado/ }))
    expect(screen.getByRole('dialog', { name: 'Resultado (mock)' })).toBeInTheDocument()
    const props = dobles.panel.props ?? {}
    expect((props['lead'] as { id: string }).id).toBe('l1')
    expect(typeof props['onGuardado']).toBe('function')
  })

  it('el descarte del día se puede deshacer y recarga el día', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: /Deshacer/ }))
    await waitFor(() => expect(dobles.deshacer).toHaveBeenCalledWith('act1'))
    expect(dobles.recargar).toHaveBeenCalled()
  })

  it('un descarte que ya no se puede deshacer lo dice, sin botón', () => {
    dobles.dia = { ...DIA_LLENO, descartados: [{ ...DIA_LLENO.descartados[0]!, deshecho: true, puede_deshacer: false }] } as DiaAnalista
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('Sin deshacer')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Deshacer/ })).not.toBeInTheDocument()
  })

  it('si el servidor cae, se dice; no se pinta un día vacío', () => {
    dobles.dia = null
    dobles.errorDia = new Error('caído')
    render(<GestionDiariaAnalista />)
    expect(screen.getByText(/no está confirmado/)).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: /Sin primer intento/ })).not.toBeInTheDocument()
  })

  it('si cae SOLO la cola, se avisa y quedan los leads sin conversación', () => {
    dobles.cola = { data: undefined, error: new Error('caído'), refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('alert')).toHaveTextContent(/solo se muestran los leads sin conversación/)
    expect(screen.getByRole('list', { name: 'Sin conversación (1)' })).toBeInTheDocument()
  })

  it('mientras la cola no llega dice «cargando», no «no tienes nada pendiente»', () => {
    dobles.cola = { data: undefined, error: null, refetch: vi.fn(), isFetching: true }
    render(<GestionDiariaAnalista />)
    expect(screen.queryByText('No tienes nada pendiente ahora')).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 3, name: /Tu cola de hoy/ })).toHaveTextContent('cargando…')
  })

  it('las listas llevan role explícito y cada acción dice sobre qué lead actúa', () => {
    render(<GestionDiariaAnalista />)
    const primero = screen.getByRole('list', { name: 'Sin primer intento (1)' })
    expect(primero.tagName).toBe('OL')
    expect(primero).toHaveAttribute('role', 'list')
    expect(within(primero).getByRole('button', { name: 'Registrar resultado de NUEVO SIN INTENTO' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Deshacer el descarte de ELENA VARGAS' })).toBeInTheDocument()
  })

  it('la severidad crítica se DICE, no solo se pinta', () => {
    dobles.cola = { data: { items: [{ ...itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), severidad: 'critica' }] }, error: null, refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('Crítica')).toBeInTheDocument()
  })

  it('ESTADO DE PRODUCCIÓN: sin cola y sin llamadas, lo dice y no fabrica nada', () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, por_hora: [] }, cartera: [], compromisos: [], compromisos_total: 0, descartados: [] } as DiaAnalista
    dobles.cola = { data: { items: [] }, error: null, refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('No tienes nada pendiente ahora')).toBeInTheDocument()
    expect(screen.getByText('Sin compromisos a partir de mañana')).toBeInTheDocument()
    expect(screen.queryByText(/Descartados hoy/)).not.toBeInTheDocument()
  })
})
