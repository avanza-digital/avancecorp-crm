// «Mi día» del analista: DOS paneles hermanos —«Ahora» (a quién llamo y con qué
// botón) y «Cola de hoy» (los cuatro grupos en pestañas)—, el marcador en una
// línea arriba, los compromisos, los descartes con Deshacer, y el ESTADO DE
// PRODUCCIÓN (un día sin llamadas ni cola) que es lo que hoy vería un analista
// real. Fail-closed: si el servidor cae, se dice, no se pinta.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
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
  // Cada MONTAJE de la caja de contacto, con su lead: así se ve que hay una
  // instancia POR LEAD y no una sola que cambia de destinatario.
  contacto: { montajes: [] as string[], onGuardado: null as null | (() => void) },
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
vi.mock('@/components/app/contacto', async () => {
  const { useEffect } = await import('react')
  return {
    AccionesContacto: ({ lead, onGuardado }: { lead: { id: string }; onGuardado?: (() => void) | undefined }) => {
      dobles.contacto.onGuardado = onGuardado ?? null
      useEffect(() => { dobles.contacto.montajes.push(lead.id) }, [lead.id])
      return <span data-testid="acciones-contacto" data-lead={lead.id} />
    },
  }
})
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

/** El salto de foco usa DOS `requestAnimationFrame` anidados. */
const dosCuadros = () => new Promise<void>((listo) => {
  requestAnimationFrame(() => { requestAnimationFrame(() => { listo() }) })
})

/** El panel «Ahora»: lo que el analista tiene delante. */
const panelAhora = () => screen.getByRole('region', { name: 'Ahora' })

beforeEach(() => {
  vi.clearAllMocks()
  dobles.yo = { id: 'a1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }
  dobles.dia = DIA_LLENO
  dobles.errorDia = null
  // l1 todavía tiene tiempo (19:20 > 18:00) y l2 se pasó ayer: las dos caras del chip.
  dobles.cola = { data: { items: [itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'), itemCola('l1', 'primera_atencion', '2026-09-20T19:20:00Z')] }, error: null, refetch: vi.fn(), isFetching: false }
  dobles.panel.props = null
  dobles.contacto.montajes = []
  dobles.contacto.onGuardado = null
})

describe('GestionDiariaAnalista', () => {
  it('los grupos son pestañas y la primera es la del lead sin primer intento', () => {
    render(<GestionDiariaAnalista />)
    const pestanas = screen.getAllByRole('tab').map((t) => t.textContent)
    expect(pestanas).toEqual(['Sin primer intento (1)', 'Vencidas (1)', 'Sin conversación (1)'])
    expect(screen.getByRole('tab', { name: 'Sin primer intento (1)' })).toHaveAttribute('aria-selected', 'true')
    // Y el panel «Ahora» arranca en el primero de esa pestaña, sin tocar nada.
    expect(within(panelAhora()).getByRole('button', { name: 'NUEVO SIN INTENTO' })).toBeInTheDocument()
  })

  it('el tiempo se dice en palabras: lo que queda y lo que se pasó', () => {
    render(<GestionDiariaAnalista />)
    // El que todavía tiene tiempo, en el panel y en su fila.
    expect(within(panelAhora()).getByText('Quedan 1 h 20 min')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Vencidas (1)' }))
    expect(within(panelAhora()).getByText('Se pasó hace 1 día')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Sin conversación (1)' }))
    expect(within(panelAhora()).getByText('Sin conversación hace 12 días')).toBeInTheDocument()
  })

  it('al elegir una fila, el panel «Ahora» pasa a ese lead', () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Vencidas (1)' }))
    const lista = screen.getByRole('list', { name: 'Vencidas (1)' })
    const fila = within(lista).getByRole('button', { name: /LEAD l2/ })
    fireEvent.click(fila)
    expect(fila).toHaveAttribute('aria-current', 'true')
    expect(within(panelAhora()).getByRole('button', { name: 'LEAD l2' })).toBeInTheDocument()
  })

  it('el marcador vive en la cabecera, en una línea, con el % y su conteo', () => {
    render(<GestionDiariaAnalista />)
    const resumen = screen.getByRole('button', { name: /Mi actividad/ })
    expect(resumen).toHaveTextContent('9 llamadas · 63 % contacto (8 útiles) · 1 cita')
    expect(resumen).toHaveTextContent('Bien')
  })

  it('el marcador de la cabecera despliega «Mi actividad de hoy»', () => {
    render(<GestionDiariaAnalista />)
    const titulo = screen.getByRole('heading', { name: /Mi actividad de hoy/ })
    expect(titulo.closest('details')).not.toHaveAttribute('open')
    fireEvent.click(screen.getByRole('button', { name: /Mi actividad/ }))
    expect(titulo.closest('details')).toHaveAttribute('open')
    expect(screen.getByText('63 % · 8 llamadas')).toBeInTheDocument()
    expect(screen.getByText(/No incluye WhatsApp ni citas/)).toBeInTheDocument()
  })

  it('sin llamadas útiles no hay chip ni porcentaje inventado', () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, por_hora: [] } } as DiaAnalista
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('button', { name: /Mi actividad/ })).toHaveTextContent('sin tasa aún (desde 5 útiles)')
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.getByText(/Se juzga desde 5 llamadas útiles/)).toBeInTheDocument()
    expect(screen.queryByText('Bien')).not.toBeInTheDocument()
  })

  it('«Registrar resultado» vive tras «···» y abre el panel de la Fase 2', () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(within(panelAhora()).getByRole('button', { name: /Más acciones para NUEVO SIN INTENTO/ }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Registrar resultado' }))
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
    expect(screen.queryByRole('tab')).not.toBeInTheDocument()
  })

  it('si cae SOLO la cola, se avisa y quedan los leads sin conversación', () => {
    dobles.cola = { data: undefined, error: new Error('caído'), refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('alert')).toHaveTextContent(/solo se muestran los leads sin conversación/)
    expect(screen.getByRole('tab', { name: 'Sin conversación (1)' })).toBeInTheDocument()
  })

  it('mientras la cola no llega dice «cargando», no «no tienes nada pendiente»', () => {
    dobles.cola = { data: undefined, error: null, refetch: vi.fn(), isFetching: true }
    render(<GestionDiariaAnalista />)
    expect(screen.queryByText('No tienes nada pendiente ahora')).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Cola de hoy' })).toHaveTextContent('cargando…')
    expect(panelAhora()).toHaveTextContent('Buscando a quién llamar…')
  })

  it('las listas llevan role explícito y cada acción dice sobre qué lead actúa', () => {
    render(<GestionDiariaAnalista />)
    const lista = screen.getByRole('list', { name: 'Sin primer intento (1)' })
    expect(lista.tagName).toBe('OL')
    expect(lista).toHaveAttribute('role', 'list')
    expect(within(panelAhora()).getByRole('button', { name: /Más acciones para NUEVO SIN INTENTO/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Deshacer el descarte de ELENA VARGAS' })).toBeInTheDocument()
  })

  it('la fila lleva DOS datos: el nombre y el tiempo, sin botones sueltos', () => {
    render(<GestionDiariaAnalista />)
    const lista = screen.getByRole('list', { name: 'Sin primer intento (1)' })
    // Un solo control por fila: la fila ENTERA (quien actúa es el panel «Ahora»).
    expect(within(lista).getAllByRole('button')).toHaveLength(1)
    expect(within(lista).getByRole('button')).toHaveTextContent('NUEVO SIN INTENTOQuedan 1 h 20 min')
  })

  // ── Lo que encontró la revisión de Codex (20/09/2026) ────────────────

  it('el lead elegido se sigue aunque el refresco lo cambie de grupo', () => {
    dobles.cola = { data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T19:20:00Z'),
      itemCola('l2', 'tarea_hoy', '2026-09-20T21:00:00Z'), itemCola('l5', 'tarea_hoy', '2026-09-20T22:00:00Z')] },
      error: null, refetch: vi.fn(), isFetching: false }
    const { rerender } = render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Hoy (2)' }))
    fireEvent.click(within(screen.getByRole('list', { name: 'Hoy (2)' })).getByRole('button', { name: /LEAD l2/ }))
    expect(within(panelAhora()).getByRole('button', { name: 'LEAD l2' })).toBeInTheDocument()
    // El minuto siguiente: la tarea de l2 vence y cambia de grupo; l5 sigue en «Hoy».
    dobles.cola = { data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T19:20:00Z'),
      itemCola('l2', 'tarea_vencida', '2026-09-20T17:00:00Z'), itemCola('l5', 'tarea_hoy', '2026-09-20T22:00:00Z')] },
      error: null, refetch: vi.fn(), isFetching: false }
    rerender(<GestionDiariaAnalista />)
    // Sigue siendo la MISMA persona, y la pestaña la sigue a ella.
    expect(within(panelAhora()).getByRole('button', { name: 'LEAD l2' })).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Vencidas (1)' })).toHaveAttribute('aria-selected', 'true')
  })

  it('cada lead estrena su caja de contacto: el resultado no puede cambiar de destinatario', () => {
    render(<GestionDiariaAnalista />)
    expect(dobles.contacto.montajes).toEqual(['l1'])
    expect(screen.getByTestId('acciones-contacto')).toHaveAttribute('data-lead', 'l1')
    // Y el camino primario («Llamar») sí avanza la cola: recibe su aviso.
    expect(typeof dobles.contacto.onGuardado).toBe('function')
  })

  it('una cola que NO se pudo leer no se cuenta como cola vacía', () => {
    dobles.dia = { ...DIA_LLENO, cartera: [] } as DiaAnalista
    dobles.cola = { data: undefined, error: new Error('caído'), refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.queryByText('No tienes nada pendiente ahora')).not.toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Cola de hoy' })).getByText('No se pudo leer tu cola')).toBeInTheDocument()
    expect(panelAhora()).toHaveTextContent(/No se pudo leer tu cola/)
  })

  it('elegir una fila lleva el foco al panel que actúa', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Vencidas (1)' }))
    fireEvent.click(within(screen.getByRole('list', { name: 'Vencidas (1)' })).getByRole('button', { name: /LEAD l2/ }))
    await act(async () => { await dosCuadros() })
    // Desde ahí, «Llamar» está a UN tabulador; antes había que desandar la lista.
    expect(within(panelAhora()).getByRole('button', { name: 'LEAD l2' })).toHaveFocus()
  })

  it('tras guardar, el foco cae en el nombre del SIGUIENTE lead', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(within(panelAhora()).getByRole('button', { name: /Más acciones para NUEVO SIN INTENTO/ }))
    fireEvent.click(screen.getByRole('menuitem', { name: 'Registrar resultado' }))
    const guardado = dobles.panel.props?.['onGuardado'] as () => void
    await act(async () => { guardado(); await dosCuadros() })
    const siguiente = within(panelAhora()).getByRole('button', { name: 'LEAD l2' })
    expect(siguiente).toHaveFocus()
  })

  // ── Densidad (20/09/2026) ─────────────────────────────────────────────
  // Lo secundario se pliega, pero su CONTEO se lee sin abrir y su título sigue
  // siendo un encabezado de verdad: en jsdom el contenido de un <details>
  // cerrado sigue en el DOM, así que sin estas pruebas la suite no notaría que
  // el plegable dejó de funcionar.
  it('lo secundario arranca plegado, con el conteo a la vista', () => {
    render(<GestionDiariaAnalista />)
    const seguimiento = screen.getByRole('heading', { name: /Mi seguimiento/ })
    const descartes = screen.getByRole('heading', { name: /Descartados hoy/ })
    expect(seguimiento.closest('details')).not.toHaveAttribute('open')
    expect(descartes.closest('details')).not.toHaveAttribute('open')
    // El dato accionable NO se esconde: cuántos hay y hasta cuándo se deshacen.
    expect(seguimiento).toHaveTextContent('1 compromiso desde mañana')
    expect(descartes).toHaveTextContent('se pueden deshacer 24 h')
  })

  it('los títulos plegados siguen en el índice de encabezados', () => {
    render(<GestionDiariaAnalista />)
    const titulos = screen.getAllByRole('heading').map((h) => h.textContent ?? '')
    expect(titulos.some((t) => t.includes('Mi seguimiento'))).toBe(true)
    expect(titulos.some((t) => t.includes('Descartados hoy'))).toBe(true)
    expect(titulos.some((t) => t.includes('Mi actividad de hoy'))).toBe(true)
  })

  it('al pulsar el título se despliega la sección', () => {
    render(<GestionDiariaAnalista />)
    const titulo = screen.getByRole('heading', { name: /Mi seguimiento/ })
    const detalle = titulo.closest('details')!
    fireEvent.click(titulo)
    expect(detalle).toHaveAttribute('open')
  })

  it('ESTADO DE PRODUCCIÓN: sin cola y sin llamadas, lo dice y no fabrica nada', () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, por_hora: [] }, cartera: [], compromisos: [], compromisos_total: 0, descartados: [] } as DiaAnalista
    dobles.cola = { data: { items: [] }, error: null, refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('No tienes nada pendiente ahora')).toBeInTheDocument()
    expect(panelAhora()).toHaveTextContent('Nada pendiente ahora')
    expect(screen.getByText('Sin compromisos a partir de mañana')).toBeInTheDocument()
    expect(screen.queryByText(/Descartados hoy/)).not.toBeInTheDocument()
  })
})
