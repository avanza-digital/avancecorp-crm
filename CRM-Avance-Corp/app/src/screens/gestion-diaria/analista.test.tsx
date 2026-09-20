// «Mi día» del analista, layout de DOS PANELES (20/09/2026): «Ahora» con la
// persona que toca y su única acción primaria, y la cola en cuatro pestañas de
// las que solo se ve una lista. El marcador, las horas, el seguimiento y los
// descartes viven en «Mi actividad». Se comprueba lo que el analista necesita:
// a quién llamar, que el tiempo se diga en palabras (nunca «SLA»), que al
// registrar no le vuelvan a proponer al que acaba de cerrar, y el ESTADO DE
// PRODUCCIÓN (un día sin llamadas ni cola). Fail-closed: si el servidor cae,
// se dice, no se pinta.
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
  useCRMData: () => ({
    ambito: { leads: [{ id: 'l1', nombre_completo: 'NUEVO SIN INTENTO', telefono: '+51999000111', etapa: 'nuevo' }] },
    tareasDe: () => [],
    asegurarLead: async () => true,
  }),
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


describe('GestionDiariaAnalista · a quién llamo ahora', () => {
  it('«Ahora» propone al primero del grupo que manda: el lead sin primer intento', () => {
    render(<GestionDiariaAnalista />)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
  })

  it('las cuatro pestañas están, con su conteo, aunque solo se vea una lista', () => {
    render(<GestionDiariaAnalista />)
    const tablist = screen.getByRole('tablist', { name: 'Grupos de la cola' })
    expect(within(tablist).getAllByRole('tab').map((t) => t.textContent)).toEqual([
      'Sin primer intento1', 'Vencidas1', 'Hoy0', 'Sin conversación1',
    ])
    // Una sola lista a la vista: la del grupo activo.
    expect(screen.getAllByRole('list', { name: /\(\d+\)$/ })).toHaveLength(1)
  })

  it('el tiempo se DICE en palabras y nunca aparece la sigla SLA', () => {
    render(<GestionDiariaAnalista />)
    // l1 vence a las 14:00 y el reloj del test son las 18:00 (cuatro horas).
    expect(screen.getAllByText('Se pasó hace 4 h').length).toBeGreaterThan(0)
    expect(screen.queryByText(/SLA/)).not.toBeInTheDocument()
  })

  it('cambiar de pestaña cambia la lista y a quién propone «Ahora»', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: /Sin conversación/ }))
    await waitFor(() => {
      expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l3')).toBeInTheDocument()
    })
    // El mismo texto sale en «Ahora» y en su fila: es la misma persona.
    expect(screen.getAllByText('Sin conversación hace 12 días')).toHaveLength(2)
  })

  it('elegir una fila de la lista la lleva a «Ahora»', async () => {
    dobles.cola = {
      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l5', 'primera_atencion', '2026-09-20T17:00:00Z')] },
      error: null, refetch: vi.fn(), isFetching: false,
    }
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: /LEAD l5/ }))
    await waitFor(() => {
      expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l5')).toBeInTheDocument()
    })
  })

  it('hay UNA sola acción primaria: «Registrar resultado» abre el panel de la Fase 2', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: 'Registrar resultado de NUEVO SIN INTENTO' }))
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' }))
  })

  it('tras registrar, «Ahora» NO vuelve a proponer al que se acaba de cerrar', async () => {
    let soltar: () => void = () => {}
    dobles.recargar = vi.fn(() => new Promise<void>((r) => { soltar = () => { r() } }))
    dobles.cola = {
      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l5', 'primera_atencion', '2026-09-20T17:00:00Z')] },
      error: null, refetch: vi.fn(async () => {}), isFetching: false,
    }
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: 'Registrar resultado de NUEVO SIN INTENTO' }))
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    const guardado = dobles.panel.props?.onGuardado
    expect(typeof guardado).toBe('function')
    ;(guardado as () => void)()
    // Mientras el servidor no contesta, el cerrado desaparece de la vista: si
    // no, el analista volvería a llamar al mismo.
    await waitFor(() => {
      expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l5')).toBeInTheDocument()
    })
    expect(screen.queryByText('NUEVO SIN INTENTO')).not.toBeInTheDocument()
    soltar()
  })

  it('mientras la cola no llega dice «cargando», no «no tienes nada pendiente»', () => {
    dobles.cola = { data: undefined, error: null, refetch: vi.fn(), isFetching: true }
    render(<GestionDiariaAnalista />)
    expect(document.querySelector('[aria-busy]')).not.toBeNull()
    expect(screen.queryByText(/No tienes nada pendiente/)).not.toBeInTheDocument()
    expect(screen.queryByRole('tablist', { name: 'Grupos de la cola' })).not.toBeInTheDocument()
  })

  it('si la cola se cae lo dice, y el aviso se ve también desde «Mi actividad»', async () => {
    dobles.cola = { data: undefined, error: new Error('502'), refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('alert')).toHaveTextContent(/No se pudo leer la cola del servidor/)
    fireEvent.click(screen.getByRole('button', { name: /Mi actividad/ }))
    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument())
  })
})

describe('GestionDiariaAnalista · Mi actividad', () => {
  const abrir = () => { fireEvent.click(screen.getByRole('button', { name: /Mi actividad/ })) }

  it('la cabecera resume el día sin ocupar la pantalla', () => {
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('button', { name: /Mi actividad/ })).toHaveTextContent('9 llamadas · 63 % · 8 llamadas')
  })

  it('el marcador completo vive en el segundo nivel, con su chip de nivel', async () => {
    render(<GestionDiariaAnalista />)
    abrir()
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Mi actividad de hoy' })).toBeInTheDocument())
    expect(screen.getByText('63 % · 8 llamadas')).toBeInTheDocument()
    expect(screen.getByText('Bien')).toBeInTheDocument()
    expect(screen.getByText('Leads tocados')).toBeInTheDocument()
  })

  it('sin llamadas útiles no hay chip ni porcentaje inventado', async () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, utiles: 0, tasa_contacto_pct: null, nivel: null } } as DiaAnalista
    render(<GestionDiariaAnalista />)
    abrir()
    await waitFor(() => expect(screen.getByText('—')).toBeInTheDocument())
    expect(screen.queryByText('Bien')).not.toBeInTheDocument()
    expect(screen.getByText(/El nivel se juzga desde 5 llamadas útiles/)).toBeInTheDocument()
  })

  it('el descarte del día se puede deshacer y recarga el día', async () => {
    render(<GestionDiariaAnalista />)
    abrir()
    fireEvent.click(await screen.findByRole('tab', { name: /Descartados hoy/ }))
    fireEvent.click(await screen.findByRole('button', { name: 'Deshacer el descarte de ELENA VARGAS' }))
    await waitFor(() => expect(dobles.deshacer).toHaveBeenCalledWith('act1'))
    expect(dobles.recargar).toHaveBeenCalled()
  })

  it('un descarte que ya no se puede deshacer lo dice, sin botón', async () => {
    dobles.dia = {
      ...DIA_LLENO,
      descartados: [{ ...DIA_LLENO.descartados[0], puede_deshacer: false, deshecho: true }],
    } as DiaAnalista
    render(<GestionDiariaAnalista />)
    abrir()
    fireEvent.click(await screen.findByRole('tab', { name: /Descartados hoy/ }))
    expect(await screen.findByText('Sin deshacer')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Deshacer el descarte/ })).not.toBeInTheDocument()
  })

  it('los compromisos de mañana en adelante viven aquí, no en la cola', async () => {
    render(<GestionDiariaAnalista />)
    abrir()
    fireEvent.click(await screen.findByRole('tab', { name: /Mi seguimiento/ }))
    expect(await screen.findByRole('button', { name: 'MARTÍN MUÑOZ' })).toBeInTheDocument()
  })
})

describe('GestionDiariaAnalista · estados que hoy se ven en producción', () => {
  it('ESTADO DE PRODUCCIÓN: sin cola y sin llamadas, lo dice y no fabrica nada', async () => {
    dobles.dia = {
      ...DIA_LLENO,
      marcador: { ...DIA_LLENO.marcador, llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, leads_tocados: 0, citas_agendadas: 0, primera_llamada_en: null, ultima_llamada_en: null, por_hora: [] },
      compromisos: [], compromisos_total: 0, cartera: [], descartados: [],
    } as unknown as DiaAnalista
    dobles.cola = { data: { items: [] }, error: null, refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    expect(screen.getByText('No tienes nada pendiente ahora')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent(/No queda nadie por llamar/)
    fireEvent.click(screen.getByRole('button', { name: /Mi actividad/ }))
    expect(await screen.findByText('—')).toBeInTheDocument()
    fireEvent.click(await screen.findByRole('tab', { name: /Llamadas por hora/ }))
    expect(await screen.findByText(/Todavía no has marcado hoy/)).toBeInTheDocument()
  })

  it('si el día no carga, se dice y no se pinta una cola a medias', () => {
    dobles.dia = null
    dobles.errorDia = new Error('500')
    render(<GestionDiariaAnalista />)
    expect(screen.getByText(/No se pudo cargar tu día/)).toBeInTheDocument()
    expect(screen.queryByRole('tablist', { name: 'Grupos de la cola' })).not.toBeInTheDocument()
  })

  it('cada acción dice sobre qué lead actúa y las listas llevan role explícito', () => {
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('button', { name: 'Registrar resultado de NUEVO SIN INTENTO' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Abrir la ficha de NUEVO SIN INTENTO' })).toBeInTheDocument()
    expect(screen.getByRole('list', { name: 'Sin primer intento (1)' })).toBeInTheDocument()
  })
})
