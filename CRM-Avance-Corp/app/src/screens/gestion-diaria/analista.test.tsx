// «Mi día» del analista, layout de DOS PANELES (20/09/2026): «Ahora» con la
// persona que toca y su única acción primaria, y la cola en cuatro pestañas de
// las que solo se ve una lista. El marcador, las horas, el seguimiento y los
// descartes viven en desplegables de segundo nivel. Se comprueba lo que el analista necesita:
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
  contacto: { montajes: [] as string[], onRegistrar: null as null | (() => void), real: false },
  obtenerTarea: vi.fn(async () => null as Record<string, unknown> | null),
  tareas: [] as Array<Record<string, unknown>>,
  // El ámbito tiene que traer TODOS los leads de la cola: «Ahora» necesita el
  // lead para armar el panel, y sin él la pantalla manda a abrir la ficha.
  leads: [] as Array<Record<string, unknown>>,
  asegurarLead: vi.fn(async () => true),
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-20T18:00:00Z') }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: dobles.leads },
    tareasDe: () => dobles.tareas,
    asegurarLead: dobles.asegurarLead,
    obtenerTareaParaRevision: dobles.obtenerTarea,
  }),
  usePanelesActions: () => ({ abrirLead: dobles.abrirLead }),
}))
vi.mock('@/data/gestion-diaria-queries', () => ({
  useDiaAnalista: () => ({ dia: dobles.dia, cargando: false, enVuelo: false, error: dobles.errorDia, recargar: dobles.recargar }),
}))
vi.mock('@/data/sla-operacion-queries', () => ({ useColaSlaPagina: () => dobles.cola }))
vi.mock('@/data/gestion-diaria-api', () => ({ deshacerResultadoLlamada: dobles.deshacer }))
vi.mock('@/components/app/contacto', async () => {
  const { useEffect, useState } = await import('react')
  const real = await vi.importActual<typeof import('@/components/app/contacto')>('@/components/app/contacto')
  return {
    AccionesContacto: (props: Parameters<typeof real.AccionesContacto>[0]) => {
      const { lead, onRegistrarLlamada } = props
      dobles.contacto.onRegistrar = onRegistrarLlamada ?? null
      const [idInicial] = useState(lead.id)
      useEffect(() => { dobles.contacto.montajes.push(idInicial) }, [idInicial])
      if (dobles.contacto.real) return <real.AccionesContacto {...props} />
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

function abrirResultado() {
  fireEvent.click(screen.getByRole('button', { name: /^Más acciones para / }))
  fireEvent.click(screen.getByRole('menuitem', { name: 'Registrar resultado' }))
}

beforeEach(() => {
  vi.clearAllMocks()
  dobles.recargar = vi.fn(async () => {})
  dobles.contacto.montajes = []
  dobles.contacto.onRegistrar = null
  dobles.contacto.real = false
  dobles.yo = { id: 'a1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }
  dobles.dia = DIA_LLENO
  dobles.errorDia = null
  dobles.cola = { data: { items: [itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'), itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z')] }, error: null, refetch: vi.fn(), isFetching: false }
  dobles.panel.props = null
  dobles.asegurarLead = vi.fn(async () => true)
  dobles.obtenerTarea = vi.fn(async () => null)
  dobles.leads = [
    { id: 'l1', nombre_completo: 'NUEVO SIN INTENTO', telefono: '+51999000111', etapa: 'nuevo' },
    ...['l2', 'l3', 'l4', 'l5', 'l6'].map((x) => ({ id: x, nombre_completo: `LEAD ${x}`, telefono: '+51999000222', etapa: 'nuevo' })),
  ]
  dobles.tareas = [
    { id: 't-de-la-fila', tipo: 'llamada', vendedor_id: 'a1', vence_en: '2026-09-20T20:00:00Z', titulo: 'La que dice la fila' },
    { id: 't-otra', tipo: 'llamada', vendedor_id: 'a1', vence_en: '2026-09-20T21:00:00Z', titulo: 'La otra' },
  ]
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
    expect(screen.getAllByRole('list', { name: /\(\d+(–\d+)? de \d+\)$/ })).toHaveLength(1)
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
    abrirResultado()
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
    abrirResultado()
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
    expect(screen.getByRole('button', { name: /Mi actividad/ })).toHaveTextContent('9 llamadas · 63 % contacto (8 útiles) · 1 cita')
  })

  it('el marcador completo vive en el segundo nivel, con su chip de nivel', async () => {
    render(<GestionDiariaAnalista />)
    abrir()
    await waitFor(() => expect(screen.getByRole('heading', { name: /Mi actividad de hoy/ })).toBeInTheDocument())
    expect(screen.getByText('63 % · 8 llamadas')).toBeInTheDocument()
    expect(screen.getAllByText('Bien').length).toBeGreaterThan(0)
    expect(screen.getByText(/Tocaste 7 leads/)).toBeInTheDocument()
  })

  it('sin llamadas útiles no hay chip ni porcentaje inventado', async () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, utiles: 0, tasa_contacto_pct: null, nivel: null } } as DiaAnalista
    render(<GestionDiariaAnalista />)
    abrir()
    await waitFor(() => expect(screen.getByText('—')).toBeInTheDocument())
    expect(screen.queryByText('Bien')).not.toBeInTheDocument()
    expect(screen.getByText(/Se juzga desde 5 llamadas útiles/)).toBeInTheDocument()
  })

  it('el descarte del día se puede deshacer y recarga el día', async () => {
    render(<GestionDiariaAnalista />)
    abrir()
    fireEvent.click(await screen.findByRole('heading', { name: /Descartados hoy/ }))
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
    fireEvent.click(await screen.findByRole('heading', { name: /Descartados hoy/ }))
    expect(await screen.findByText('Sin deshacer')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Deshacer el descarte/ })).not.toBeInTheDocument()
  })

  it('los compromisos de mañana en adelante viven aquí, no en la cola', async () => {
    render(<GestionDiariaAnalista />)
    abrir()
    fireEvent.click(await screen.findByRole('heading', { name: /Mi seguimiento/ }))
    expect(await screen.findByRole('button', { name: 'MARTÍN MUÑOZ' })).toBeInTheDocument()
  })
})

describe('GestionDiariaAnalista · el teléfono del lead elegido', () => {
  it('pide el lead al servidor en cuanto se elige: no hay que abrir la ficha', async () => {
    // El ámbito llega VACÍO, como en «Vencidas»: desde la Fase 4e el store no
    // carga todos los leads. Antes, sin lead no había botón de llamar y el
    // analista tenía que dar un rodeo por la ficha.
    dobles.leads = []
    let contestar: (ok: boolean) => void = () => {}
    dobles.asegurarLead = vi.fn(() => new Promise<boolean>((r) => { contestar = r }))
    render(<GestionDiariaAnalista />)
    await waitFor(() => expect(dobles.asegurarLead).toHaveBeenCalledWith('l1'))
    // Mientras viaja, se DICE que viene; no se le manda a la ficha.
    expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent(/Buscando su número/)
    contestar(true)
  })

  it('no lo pide dos veces aunque el reloj recalcule la fila', async () => {
    dobles.leads = []
    const { rerender } = render(<GestionDiariaAnalista />)
    await waitFor(() => expect(dobles.asegurarLead).toHaveBeenCalledTimes(1))
    rerender(<GestionDiariaAnalista />)
    expect(dobles.asegurarLead).toHaveBeenCalledTimes(1)
  })

  it('si el lead YA está en el ámbito, no se pide nada y el botón está', async () => {
    render(<GestionDiariaAnalista />)
    await waitFor(() => expect(screen.getByTestId('acciones-contacto')).toBeInTheDocument())
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
  })

  it('si no se pudo traer, lo dice y ofrece la ficha, sin prometer una llamada', async () => {
    dobles.leads = []
    dobles.asegurarLead = vi.fn(async () => { throw new Error('sin red') })
    render(<GestionDiariaAnalista />)
    await waitFor(() => {
      expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent(/No se pudo traer su número/)
    })
  })
})

describe('GestionDiariaAnalista · lo que NO está cargado no es lo que NO existe', () => {
  it('la tarea que dice la fila se PIDE si no está en el store, no se adivina otra', async () => {
    dobles.tareas = [{ id: 't-otra', tipo: 'llamada', vendedor_id: 'a1', vence_en: '2026-09-20T21:00:00Z', titulo: 'La otra' }]
    dobles.obtenerTarea = vi.fn(async () => ({ id: 't-de-la-fila', titulo: 'La que manda' }))
    dobles.cola = {
      data: { items: [{ ...itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), tarea_id: 't-de-la-fila' }] },
      error: null, refetch: vi.fn(), isFetching: false,
    }
    render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.obtenerTarea).toHaveBeenCalledWith('l1', 't-de-la-fila'))
    await waitFor(() => expect(dobles.panel.props?.tarea).toMatchObject({ id: 't-de-la-fila' }))
  })

  it('si el servidor tampoco la da, se abre SIN tarea: mejor ninguna que la equivocada', async () => {
    dobles.tareas = [{ id: 't-otra', tipo: 'llamada', vendedor_id: 'a1', vence_en: '2026-09-20T21:00:00Z', titulo: 'La otra' }]
    dobles.obtenerTarea = vi.fn(async () => null)
    dobles.cola = {
      data: { items: [{ ...itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), tarea_id: 't-fantasma' }] },
      error: null, refetch: vi.fn(), isFetching: false,
    }
    render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    expect(dobles.panel.props?.tarea).toBeNull()
  })

  it('sin señal, el historial se dice «no cargado», nunca «sin gestiones»', () => {
    // Un lead que viene de la cola pero no de la cartera del día (tope de 500).
    dobles.dia = { ...DIA_LLENO, cartera: [] } as unknown as DiaAnalista
    render(<GestionDiariaAnalista />)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(ahora).toHaveTextContent(/Historial no cargado/)
    expect(ahora).not.toHaveTextContent(/Sin gestiones previas/)
  })

  it('si la cola se cae, sus grupos dicen «?» y no «0»', () => {
    dobles.cola = { data: undefined, error: new Error('502'), refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    const tabs = screen.getByRole('tablist', { name: 'Grupos de la cola' })
    // Los tres primeros salen de la cola: su conteo es DESCONOCIDO.
    expect(within(tabs).getByRole('tab', { name: /^Vencidas/ })).toHaveTextContent('Vencidas?')
    expect(within(tabs).getByRole('tab', { name: /^Hoy/ })).toHaveTextContent('Hoy?')
    // «Sin conversación» sale del día, que sí llegó: ese conteo es real.
    expect(within(tabs).getByRole('tab', { name: /^Sin conversación/ })).toHaveTextContent('Sin conversación1')
  })
})

describe('GestionDiariaAnalista · dos resultados seguidos (carrera)', () => {
  /** La cola con tres leads del mismo grupo y un `recargar` que se suelta a mano. */
  function tresYControl() {
    const sueltas: Array<() => void> = []
    dobles.recargar = vi.fn(() => new Promise<void>((r) => { sueltas.push(() => { r() }) }))
    dobles.cola = {
      data: { items: ['l1', 'l5', 'l6'].map((x, i) => itemCola(x, 'primera_atencion', `2026-09-20T1${i}:00:00Z`)) },
      error: null, refetch: vi.fn(async () => {}), isFetching: false,
    }
    return sueltas
  }
  const guardarElDeAhora = async () => {
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    const guardado = dobles.panel.props?.onGuardado
    dobles.panel.props = null
    ;(guardado as () => void)()
  }

  it('el segundo guardado NO destapa al primero cuando este termina', async () => {
    const sueltas = tresYControl()
    render(<GestionDiariaAnalista />)

    await guardarElDeAhora()                       // cierra l1
    await waitFor(() => expect(screen.queryAllByText('NUEVO SIN INTENTO')).toHaveLength(0))
    await guardarElDeAhora()                       // cierra l5, con l1 aún en vuelo
    await waitFor(() => expect(screen.queryAllByText('LEAD l5')).toHaveLength(0))

    // Termina el PRIMERO. Su lead puede volver —el servidor aún lo devuelve—,
    // pero el SEGUNDO sigue en vuelo y NO puede destaparse: antes, el `finally`
    // del primero ponía el estado a null y l5 reaparecía con su chip viejo.
    sueltas[0]?.()
    await waitFor(() => expect(screen.getAllByText('NUEVO SIN INTENTO').length).toBeGreaterThan(0))
    expect(screen.queryAllByText('LEAD l5')).toHaveLength(0)

    // Y cuando termina el suyo, l5 vuelve por su cuenta.
    sueltas[1]?.()
    await waitFor(() => expect(screen.getAllByText('LEAD l5').length).toBeGreaterThan(0))
  })

  it('si la recarga falla, no queda un rechazo suelto y el lead vuelve a verse', async () => {
    dobles.recargar = vi.fn(async () => { throw new Error('502') })
    dobles.cola = {
      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z')] },
      error: null, refetch: vi.fn(async () => {}), isFetching: false,
    }
    const alRechazo = vi.fn()
    window.addEventListener('unhandledrejection', alRechazo)
    render(<GestionDiariaAnalista />)
    await guardarElDeAhora()
    // `allSettled`: la otra lectura sigue su curso y el lead se destapa igual.
    await waitFor(() => expect(screen.getAllByText('NUEVO SIN INTENTO').length).toBeGreaterThan(0))
    expect(alRechazo).not.toHaveBeenCalled()
    window.removeEventListener('unhandledrejection', alRechazo)
  })

  it('el panel cierra la tarea que dice la FILA, no la que adivine el caché', async () => {
    dobles.cola = {
      data: { items: [{ ...itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), tarea_id: 't-de-la-fila' }] },
      error: null, refetch: vi.fn(), isFetching: false,
    }
    render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props?.tarea).toMatchObject({ id: 't-de-la-fila' }))
  })
})

describe('GestionDiariaAnalista · abrir una pestaña vacía', () => {
  it('pulsar un grupo sin gente LO ABRE y lo dice, en vez de rebotar a otro', async () => {
    render(<GestionDiariaAnalista />)
    // «Hoy (0)» está vacío en el fixture: pulsarlo tiene que abrirlo.
    fireEvent.click(screen.getByRole('tab', { name: /^Hoy/ }))
    await waitFor(() => {
      expect(screen.getByRole('tab', { name: /^Hoy/ })).toHaveAttribute('aria-selected', 'true')
    })
    expect(screen.getByText(/Nada en este grupo/)).toBeInTheDocument()
  })
})

describe('GestionDiariaAnalista · el foco nunca se pierde', () => {
  it('abrir y cerrar «Mi actividad» conserva foco en su resumen, sin desmontar la cola', async () => {
    render(<GestionDiariaAnalista />)
    const titulo = screen.getByRole('heading', { name: /Mi actividad de hoy/ })
    const plegable = titulo.closest('details')!
    expect(plegable).not.toHaveAttribute('open')
    fireEvent.click(screen.getByRole('button', { name: /Mi actividad/ }))
    await waitFor(() => expect(plegable.querySelector('summary')).toHaveFocus())
    expect(plegable).toHaveAttribute('open')
    expect(screen.getByRole('region', { name: 'Ahora' })).toBeInTheDocument()
    fireEvent.click(titulo)
    expect(plegable).not.toHaveAttribute('open')
    expect(plegable.querySelector('summary')).toHaveFocus()
  })

  it('la paginación usa aria-disabled, no disabled: el botón pulsado conserva el foco', () => {
    dobles.cola = {
      data: { items: Array.from({ length: 7 }, (_, i) => itemCola(`p${i}`, 'primera_atencion', `2026-09-20T1${i}:00:00Z`)) },
      error: null, refetch: vi.fn(), isFetching: false,
    }
    render(<GestionDiariaAnalista />)
    const siguiente = screen.getByRole('button', { name: 'Siguiente' })
    expect(screen.getByRole('button', { name: 'Anterior' })).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByRole('button', { name: 'Anterior' })).not.toBeDisabled()

    siguiente.focus()
    fireEvent.click(siguiente)
    // Segunda página: «Siguiente» se apaga a sí mismo. Con `disabled` el foco
    // se habría ido al body (regla de la casa, boton-guardar.tsx).
    expect(screen.getByRole('button', { name: 'Siguiente' })).toHaveAttribute('aria-disabled', 'true')
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Siguiente' }))
    expect(screen.getByText('6–7 de 7')).toHaveAttribute('aria-live', 'polite')
  })

  it('la fila elegida se marca con aria-current y lo dice también con texto', () => {
    render(<GestionDiariaAnalista />)
    const lista = screen.getByRole('list', { name: /^Sin primer intento/ })
    const fila = within(lista).getByRole('button', { name: /NUEVO SIN INTENTO/ })
    fireEvent.click(fila)
    expect(fila).toHaveAttribute('aria-current', 'true')
    expect(within(fila).getByText('Elegido')).toBeInTheDocument()
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
    expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent(/Nada pendiente ahora/)
    fireEvent.click(screen.getByRole('button', { name: /Mi actividad/ }))
    expect(await screen.findByText('—')).toBeInTheDocument()
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
    expect(screen.getByRole('button', { name: /^Más acciones para NUEVO SIN INTENTO/ })).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Abrir la ficha de NUEVO SIN INTENTO' })).toBeInTheDocument()
    // El nombre lleva el RANGO: prometía el total del grupo y contenía una página.
    expect(screen.getByRole('list', { name: 'Sin primer intento (1–1 de 1)' })).toBeInTheDocument()
  })
})

describe('GestionDiariaAnalista · integración del taller y producción', () => {
  it('cada lead remonta su contacto y guardar la llamada avanza la cola', async () => {
    let soltar: () => void = () => {}
    dobles.recargar = vi.fn(() => new Promise<void>((r) => { soltar = r }))
    render(<GestionDiariaAnalista />)
    expect(dobles.contacto.montajes).toEqual(['l1'])
    expect(typeof dobles.contacto.onRegistrar).toBe('function')
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    expect(dobles.contacto.montajes).toEqual(['l1', 'l2'])
    fireEvent.click(screen.getByRole('tab', { name: /^Sin primer intento/ }))
    dobles.contacto.onRegistrar?.()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    ;(dobles.panel.props!.onGuardado as () => void)()
    await waitFor(() => expect(screen.getByTestId('acciones-contacto')).toHaveAttribute('data-lead', 'l2'))
    expect(screen.queryByText('NUEVO SIN INTENTO')).not.toBeInTheDocument()
    expect(dobles.recargar).toHaveBeenCalled()
    expect(dobles.cola.refetch).toHaveBeenCalled()
    soltar()
  })

  it('al elegir una fila se enfoca el nombre de Ahora', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    fireEvent.click(within(screen.getByRole('list', { name: /^Vencidas/ })).getByRole('button', { name: /LEAD l2/ }))
    await waitFor(() => expect(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Abrir la ficha de LEAD l2' })).toHaveFocus())
  })

  it('los desplegables conservan conteos y no vuelven a cerrarse al recargar', () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    const seguimiento = screen.getByRole('heading', { name: /Mi seguimiento/ })
    expect(seguimiento.closest('details')).not.toHaveAttribute('open')
    expect(seguimiento).toHaveTextContent('1 compromiso desde mañana')
    expect(screen.getByRole('heading', { name: /Descartados hoy/ })).toHaveTextContent('se pueden deshacer 24 h')
    fireEvent.click(seguimiento)
    dobles.dia = { ...DIA_LLENO, compromisos_total: 2 }
    rerender(<GestionDiariaAnalista />)
    expect(screen.getByRole('heading', { name: /Mi seguimiento/ })).toHaveTextContent('2 compromisos')
    expect(seguimiento.closest('details')).toHaveAttribute('open')
  })

  it('una cola aún cargando no propone a alguien de menor prioridad', () => {
    dobles.cola = { data: undefined, error: null, refetch: vi.fn(), isFetching: true }
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('Buscando a quién llamar')
    expect(screen.queryByTestId('acciones-contacto')).not.toBeInTheDocument()
  })

  it('Actualizar en demo no consulta la cola real', () => {
    dobles.yo.demo = true
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
    expect(dobles.recargar).toHaveBeenCalled()
    expect(dobles.cola.refetch).not.toHaveBeenCalled()
  })
})

describe('GestionDiariaAnalista · llamada real y refetch', () => {
  it('Llamar usa la misma tarea autoritativa que el menú y avanza al guardar', async () => {
    dobles.contacto.real = true
    dobles.tareas = []
    dobles.obtenerTarea = vi.fn(async () => ({ id: 't-remota', titulo: 'Tarea remota' }))
    dobles.cola = { data: { items: [
      { ...itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), tarea_id: 't-remota' },
      itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'),
    ] }, error: null, refetch: vi.fn(), isFetching: false }
    let soltar: () => void = () => {}
    dobles.recargar = vi.fn(() => new Promise<void>((r) => { soltar = r }))
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: /^Copiar el número de NUEVO SIN INTENTO/ }))
    await waitFor(() => expect(dobles.obtenerTarea).toHaveBeenCalledWith('l1', 't-remota'))
    await waitFor(() => expect(dobles.panel.props?.tarea).toMatchObject({ id: 't-remota' }))
    ;(dobles.panel.props!.onGuardado as () => void)()
    await waitFor(() => expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('LEAD l2'))
    soltar()
  })

  it('un refetch con datos conserva al lead y su contacto, sin remontarlo', () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    dobles.cola = { ...dobles.cola, isFetching: true }
    rerender(<GestionDiariaAnalista />)
    expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('NUEVO SIN INTENTO')
    expect(dobles.contacto.montajes).toEqual(['l1'])
  })

  it('una validación tardía de un contacto desmontado no abre el resultado del lead anterior', async () => {
    dobles.contacto.real = true
    let responder: (v: boolean) => void = () => {}
    dobles.asegurarLead = vi.fn(() => new Promise<boolean>((r) => { responder = r }))
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: /^Copiar el número de NUEVO SIN INTENTO/ }))
    await waitFor(() => expect(dobles.asegurarLead).toHaveBeenCalledWith('l1'))
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    responder(true)
    await waitFor(() => expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('LEAD l2'))
    expect(dobles.panel.props).toBeNull()
  })
})
