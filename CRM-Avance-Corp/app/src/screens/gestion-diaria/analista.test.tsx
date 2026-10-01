// «Mi día» del analista con el diseño del 27/09/2026: franja de 4 cifras,
// «Ahora» con la persona que toca y su única acción primaria, y una tarjeta con
// pestañas —«Cola de hoy» (filtros en pastilla con «Todo» primero), «Mi
// actividad» y «Mi seguimiento»— donde antes había plegables apilados. Se
// comprueba lo que el analista necesita:
// a quién llamar, que el tiempo se diga en palabras (nunca «SLA»), que al
// registrar no le vuelvan a proponer al que acaba de cerrar, y el ESTADO DE
// PRODUCCIÓN (un día sin llamadas ni cola). Fail-closed: si el servidor cae,
// se dice, no se pinta.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import type { DiaAnalista } from '@/lib/gestion-diaria-analista'

const dobles = vi.hoisted(() => ({
  yo: { id: 'a1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' },
  dia: null as DiaAnalista | null,
  errorDia: null as unknown,
  gestionadas: [] as string[],
  recargar: vi.fn(async () => {}),
  cola: { data: undefined as unknown, error: null as unknown, refetch: vi.fn(), isFetching: false },
  abrirLead: vi.fn(),
  deshacer: vi.fn(async () => ({ ok: true })),
  panel: { props: null as Record<string, unknown> | null },
  contacto: { montajes: [] as string[], onRegistrar: null as null | (() => void), onLlamar: null as null | (() => void), real: false },
  obtenerTarea: vi.fn(async () => null as Record<string, unknown> | null),
  tareas: [] as Array<Record<string, unknown>>,
  // Tareas del ámbito completo (el store): de aquí sale la tarea de un CLIENTE.
  tareasAmbito: [] as Array<Record<string, unknown>>,
  contactoCliente: { data: undefined as undefined | { telefono: string | null; contactar: boolean }, error: null as unknown, isPending: false, pedidos: [] as string[] },
  cierre: { tarea: null as Record<string, unknown> | null, onCerrar: null as null | (() => void) },
  abrirInversionista: vi.fn(),
  // El ámbito tiene que traer TODOS los leads de la cola: «Ahora» necesita el
  // lead para armar el panel, y sin él la pantalla manda a abrir la ficha.
  leads: [] as Array<Record<string, unknown>>,
  asegurarLead: vi.fn(async () => true),
  historial: { items: [] as Array<Record<string, unknown>>, cargando: false, error: null as unknown, reintentar: vi.fn(), pedidos: [] as Array<string | null> },
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-20T18:00:00Z') }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: dobles.leads },
    tareas: dobles.tareasAmbito,
    tareasDe: () => dobles.tareas,
    asegurarLead: dobles.asegurarLead,
    obtenerTareaParaRevision: dobles.obtenerTarea,
  }),
  usePanelesActions: () => ({ abrirLead: dobles.abrirLead }),
}))
vi.mock('@/data/gestion-diaria-queries', () => ({
  useDiaAnalista: () => ({ dia: dobles.dia, cargando: false, enVuelo: false, error: dobles.errorDia, recargar: dobles.recargar }),
}))
vi.mock('@/data/gestion-diaria-cola-queries', async () => {
  const { ordenarColaDiaria } = await import('@/lib/gestion-diaria-analista')
  const { paginarTrabajoDemo } = await import('@/lib/gestion-diaria-cola-demo')
  return { useColaTrabajo: (pedido: import('@/lib/gestion-diaria-cola').PedidoColaTrabajo, dia: string) => {
    const raw = dobles.cola.data as { items: import('@/lib/sla-operacion').ItemColaDia[] } | undefined
    const filas = ordenarColaDiaria(raw?.items ?? [], dobles.dia?.cartera ?? []).map((f) => ({ ...f,
      estado_trabajo: dobles.gestionadas.includes(f.clave) ? 'gestionado' : 'pendiente',
      ultima_gestion: dobles.gestionadas.includes(f.clave) ? { actividad_id: 'act', resultado: 'no_contesto', en: '2026-09-20T18:00:00Z', tarea_id: null, etapa_anterior: 'nuevo' } : null, proxima_tarea: null,
    })) as import('@/lib/gestion-diaria-cola').FilaTrabajo[]
    return { ...dobles.cola, data: raw && !dobles.cola.error
      ? paginarTrabajoDemo(filas, pedido, dobles.yo.id, dia, Date.parse('2026-09-20T18:00:00Z')) : undefined }
  } }
})
// El teléfono de un cliente sale de su ficha autorizada; aquí se prueba qué se pinta con él.
vi.mock('@/data/inversionistas-queries', () => ({
  useContactoInversionista: (_actor: string, id: string) => {
    dobles.contactoCliente.pedidos.push(id)
    return id === '' ? { data: undefined, error: null, isPending: true } : dobles.contactoCliente
  },
}))
// El cierre de tarea tiene sus pruebas: aquí, a QUÉ tarea se abre y qué pasa al cerrarlo.
vi.mock('@/components/app/cerrar-tarea', () => ({
  CerrarTareaDialog: (props: { tarea: Record<string, unknown> | null; onCerrar: () => void }) => {
    dobles.cierre.tarea = props.tarea
    dobles.cierre.onCerrar = props.onCerrar
    return props.tarea ? <div role="dialog" aria-label="Cerrar tarea (mock)" /> : null
  },
}))
vi.mock('@/lib/router', async () => ({
  ...await vi.importActual<typeof import('@/lib/router')>('@/lib/router'),
  abrirInversionista: dobles.abrirInversionista,
}))
vi.mock('@/data/gestion-diaria-api', () => ({ deshacerResultadoLlamada: dobles.deshacer }))
// «Lo último con este lead» (27/09/2026): el historial por lead tiene sus
// pruebas; aquí se prueba QUÉ se pinta con él y que se pide por el lead de «Ahora».
vi.mock('@/data/use-actividades-de-lead', () => ({
  useActividadesDeLead: (leadId: string | null) => {
    dobles.historial.pedidos.push(leadId)
    return { ...dobles.historial, senales: {}, hayMas: false, cargandoMas: false, cargarMas: () => {} }
  },
}))
vi.mock('@/components/app/contacto', async () => {
  const { useEffect, useState } = await import('react')
  const real = await vi.importActual<typeof import('@/components/app/contacto')>('@/components/app/contacto')
  return {
    AccionesContacto: (props: Parameters<typeof real.AccionesContacto>[0]) => {
      const { lead, onRegistrarLlamada, onLlamar } = props
      dobles.contacto.onRegistrar = onRegistrarLlamada ?? null
      dobles.contacto.onLlamar = onLlamar ?? null
      const [idInicial] = useState(lead.id)
      useEffect(() => { dobles.contacto.montajes.push(idInicial) }, [idInicial])
      if (dobles.contacto.real) return <real.AccionesContacto {...props} />
      return <span data-testid="acciones-contacto" data-lead={lead.id} />
    },
  }
})
// Etapa 3 (27/09/2026): el resultado se registra DENTRO de «Ahora». La lógica
// del formulario tiene sus pruebas; aquí se prueba a QUIÉN se le abre y qué
// pasa al cerrar o guardar.
vi.mock('@/components/gestion-diaria/registrar-resultado', () => ({
  RegistroResultadoTarjeta: (props: Record<string, unknown>) => { dobles.panel.props = props; return <section aria-label="Resultado en la tarjeta (mock)" /> },
}))
// El registro del día (pestaña «Mi actividad») tiene sus propias pruebas.
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({
  RegistroActividad: (props: Record<string, unknown>) => <section aria-label="Registro del día (mock)" data-compacto={String(props['compacto'])} />,
}))
const { GestionDiariaAnalista } = await import('./analista')
// El coordinador real (plan «Llamadas desde el celular», F1.1.3): la tarjeta debe
// cerrar la intención que la abrió para que la siguiente llamada pueda ofrecerse.
const { armarIntencion, intencionDe, limpiarIntencionesContacto, reclamarIntencion } = await import('@/lib/intencion-contacto')

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
  clave: `lead:${id}`, sujeto: { tipo: 'lead', id, nombre: id === 'l1' ? 'NUEVO SIN INTENTO' : `LEAD ${id}` },
  lead_id: id, bucket, severidad: 'media', prioridad: 0, referencia_en: referencia, tarea_id: null,
  lead: { id, nombre_completo: id === 'l1' ? 'NUEVO SIN INTENTO' : `LEAD ${id}`, etapa: 'nuevo', analista_id: 'a1', analista_nombre: 'ANALISTA UNO' },
})

/** Abre una pestaña de la tarjeta derecha («Cola de hoy», «Mi actividad», «Mi seguimiento»). */
function verPestana(nombre: RegExp) {
  fireEvent.click(within(screen.getByRole('tablist', { name: 'Qué ver' })).getByRole('tab', { name: nombre }))
}

/** Lo que hace el formulario real al confirmar el servidor: cierra y LUEGO avisa. */
function guardarDelPanel() {
  const props = dobles.panel.props
  if (!props) throw new Error('el resultado no está abierto')
  dobles.panel.props = null
  dobles.gestionadas.push(`lead:${(props['lead'] as { id: string }).id}`)
  ;(props['onClose'] as () => void)()
  ;(props['onGuardado'] as () => void)()
}

function abrirResultado() {
  fireEvent.click(screen.getByRole('button', { name: /^Más acciones para / }))
  fireEvent.click(screen.getByRole('menuitem', { name: 'Registrar resultado' }))
}

beforeEach(() => {
  sessionStorage.clear()
  dobles.gestionadas = []
  vi.clearAllMocks()
  dobles.recargar = vi.fn(async () => {})
  dobles.contacto.montajes = []
  dobles.contacto.onRegistrar = null
  dobles.contacto.onLlamar = null
  dobles.contacto.real = false
  dobles.yo = { id: 'a1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }
  dobles.dia = DIA_LLENO
  dobles.errorDia = null
  dobles.cola = { data: { items: [itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'), itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z')] }, error: null, refetch: vi.fn(), isFetching: false }
  dobles.panel.props = null
  dobles.asegurarLead = vi.fn(async () => true)
  dobles.obtenerTarea = vi.fn(async () => null)
  dobles.historial = { items: [], cargando: false, error: null, reintentar: vi.fn(), pedidos: [] }
  dobles.leads = [
    { id: 'l1', nombre_completo: 'NUEVO SIN INTENTO', telefono: '+51999000111', etapa: 'nuevo' },
    ...['l2', 'l3', 'l4', 'l5', 'l6'].map((x) => ({ id: x, nombre_completo: `LEAD ${x}`, telefono: '+51999000222', etapa: 'nuevo' })),
  ]
  dobles.tareas = [
    { id: 't-de-la-fila', tipo: 'llamada', vendedor_id: 'a1', vence_en: '2026-09-20T20:00:00Z', titulo: 'La que dice la fila' },
    { id: 't-otra', tipo: 'llamada', vendedor_id: 'a1', vence_en: '2026-09-20T21:00:00Z', titulo: 'La otra' },
  ]
  dobles.tareasAmbito = []
  dobles.contactoCliente = { data: undefined, error: null, isPending: false, pedidos: [] }
  dobles.cierre = { tarea: null, onCerrar: null }
})


describe('GestionDiariaAnalista · a quién llamo ahora', () => {
  it('«Ahora» propone al primero del grupo que manda: el lead sin primer intento', () => {
    render(<GestionDiariaAnalista />)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
  })

  it('«Todo» y los cuatro grupos están, con su conteo, aunque solo se vea una lista', () => {
    render(<GestionDiariaAnalista />)
    const tablist = screen.getByRole('tablist', { name: 'Grupos de la cola' })
    expect(within(tablist).getAllByRole('tab').map((t) => t.textContent)).toEqual([
      'Todo3', 'Sin primer intento1', 'Vencidas1', 'Hoy0', 'Sin conversación1',
    ])
    expect(within(tablist).getByRole('tab', { name: /^Todo/ })).toHaveAttribute('aria-selected', 'true')
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
    expect(typeof dobles.panel.props?.onGuardado).toBe('function')
    guardarDelPanel()
    // La cola confirmada lo mantiene al final, incluso si las cifras del día
    // aún se están recargando; «Ahora» propone al siguiente pendiente.
    await waitFor(() => {
      expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l5')).toBeInTheDocument()
    })
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button').at(-1)).toHaveTextContent('NUEVO SIN INTENTO')
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
    verPestana(/^Mi actividad/)
    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument())
  })
})

describe('GestionDiariaAnalista · la franja y «Mi actividad»', () => {
  it('la franja resume el día en 4 cifras, con el % pegado a sus útiles y su nivel', () => {
    render(<GestionDiariaAnalista />)
    const franja = screen.getByRole('group', { name: 'Tu día en cifras' })
    expect(within(franja).getAllByRole('term').map((x) => x.textContent)).toEqual(['Llamadas', 'Contestaron', 'Contacto', 'Citas agendadas'])
    const valores = within(franja).getAllByRole('definition').map((x) => x.textContent)
    expect(valores).toEqual(['9hoy', '5de 9', '63 %Bien · de 8 útiles', '1hoy'])
  })

  it('«Mi actividad» trae las barras por hora, cómo se cuenta y el registro compacto del día', async () => {
    render(<GestionDiariaAnalista />)
    verPestana(/^Mi actividad/)
    expect(await screen.findByRole('heading', { name: 'Llamadas por hora' })).toBeInTheDocument()
    expect(screen.getByText(/Tocaste 7 leads/)).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Registro del día (mock)' })).toHaveAttribute('data-compacto', 'true')
    // «Ahora» sigue en pantalla: la pestaña cambia solo la tarjeta de la derecha.
    expect(screen.getByRole('region', { name: 'Ahora' })).toBeInTheDocument()
  })

  it('sin llamadas útiles no hay chip ni porcentaje inventado', () => {
    dobles.dia = { ...DIA_LLENO, marcador: { ...DIA_LLENO.marcador, utiles: 0, tasa_contacto_pct: null, nivel: null } } as DiaAnalista
    render(<GestionDiariaAnalista />)
    const franja = screen.getByRole('group', { name: 'Tu día en cifras' })
    expect(within(franja).getByText('—')).toHaveAttribute('aria-hidden', 'true')
    expect(within(franja).getByText('sin dato')).toBeInTheDocument()
    expect(within(franja).getByText(/se juzga desde 5 llamadas útiles/)).toBeInTheDocument()
    expect(screen.queryByText(/^Bien/)).not.toBeInTheDocument()
  })

  it('el descarte del día se puede deshacer y recarga el día', async () => {
    render(<GestionDiariaAnalista />)
    verPestana(/^Mi actividad/)
    expect(await screen.findByRole('heading', { name: /Descartados hoy/ })).toHaveTextContent('se pueden deshacer 24 h')
    fireEvent.click(screen.getByRole('button', { name: 'Deshacer el descarte de ELENA VARGAS' }))
    await waitFor(() => expect(dobles.deshacer).toHaveBeenCalledWith('act1'))
    expect(dobles.recargar).toHaveBeenCalled()
  })

  it('un descarte que ya no se puede deshacer lo dice, sin botón', async () => {
    dobles.dia = {
      ...DIA_LLENO,
      descartados: [{ ...DIA_LLENO.descartados[0], puede_deshacer: false, deshecho: true }],
    } as DiaAnalista
    render(<GestionDiariaAnalista />)
    verPestana(/^Mi actividad/)
    expect(await screen.findByText('Sin deshacer')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Deshacer el descarte/ })).not.toBeInTheDocument()
  })

  it('los compromisos de mañana en adelante viven en «Mi seguimiento», no en la cola', async () => {
    render(<GestionDiariaAnalista />)
    verPestana(/^Mi seguimiento/)
    expect(await screen.findByRole('button', { name: 'MARTÍN MUÑOZ' })).toBeInTheDocument()
    expect(screen.queryByRole('tablist', { name: 'Grupos de la cola' })).not.toBeInTheDocument()
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
    // Toda la cola viene de una única foto; ningún conteo parcial sustituye el fallo.
    expect(within(tabs).getByRole('tab', { name: /^Sin conversación/ })).toHaveTextContent('Sin conversación?')
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
    guardarDelPanel()
  }

  it('dos guardados conservan ambos al final y las recargas tardías no retroceden «Ahora»', async () => {
    const sueltas = tresYControl()
    render(<GestionDiariaAnalista />)

    const ahora = screen.getByRole('region', { name: 'Ahora' })
    await guardarElDeAhora()
    await waitFor(() => expect(ahora).toHaveTextContent('LEAD l5'))
    await guardarElDeAhora()
    await waitFor(() => expect(ahora).toHaveTextContent('LEAD l6'))
    const ultimas = within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button').slice(-2)
    expect(ultimas[0]).toHaveTextContent('NUEVO SIN INTENTO')
    expect(ultimas[1]).toHaveTextContent('LEAD l5')
    for (const soltar of sueltas) {
      await act(async () => { soltar() })
      expect(ahora).toHaveTextContent('LEAD l6')
    }
  })

  it('si la recarga de cifras falla, no queda un rechazo suelto y la gestión sigue visible', async () => {
    dobles.recargar = vi.fn(async () => { throw new Error('502') })
    dobles.cola = {
      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z')] },
      error: null, refetch: vi.fn(async () => {}), isFetching: false,
    }
    const alRechazo = vi.fn()
    window.addEventListener('unhandledrejection', alRechazo)
    render(<GestionDiariaAnalista />)
    await guardarElDeAhora()
    // `allSettled`: el fallo de las cifras no borra la cola confirmada.
    await waitFor(() => expect(screen.getAllByText('NUEVO SIN INTENTO').length).toBeGreaterThan(0))
    expect(alRechazo).not.toHaveBeenCalled()
    window.removeEventListener('unhandledrejection', alRechazo)
  })

  it('deshacer desde otra vista devuelve el lead a pendientes y permite elegirlo en la misma sesión', async () => {
    tresYControl()
    const { rerender } = render(<GestionDiariaAnalista />)
    await guardarElDeAhora()
    await waitFor(() => expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('LEAD l5'))
    // La lectura nueva acredita el deshacer externo; no pasó por el botón de
    // esta pantalla y no debe depender de retirar una marca local.
    dobles.gestionadas = []
    rerender(<GestionDiariaAnalista />)
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getByRole('button', { name: /NUEVO SIN INTENTO/ }))
    await waitFor(() => expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('NUEVO SIN INTENTO'))
    expect(screen.getByTestId('acciones-contacto')).toHaveAttribute('data-lead', 'l1')
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
  it('las pestañas de la tarjeta se recorren con el teclado y no desmontan «Ahora»', async () => {
    render(<GestionDiariaAnalista />)
    const cola = within(screen.getByRole('tablist', { name: 'Qué ver' })).getByRole('tab', { name: /^Cola de hoy/ })
    expect(cola).toHaveAttribute('aria-selected', 'true')
    cola.focus()
    fireEvent.keyDown(cola, { key: 'ArrowRight' })
    const actividad = within(screen.getByRole('tablist', { name: 'Qué ver' })).getByRole('tab', { name: /^Mi actividad/ })
    await waitFor(() => expect(actividad).toHaveFocus())
    expect(actividad).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('NUEVO SIN INTENTO')
  })

  it('la paginación usa aria-disabled, no disabled: el botón pulsado conserva el foco', () => {
    dobles.cola = {
      data: { items: Array.from({ length: 10 }, (_, i) => itemCola(`p${i}`, 'primera_atencion', `2026-09-20T${String(10 + i).padStart(2, '0')}:00:00Z`)) },
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
    expect(screen.getByText(/^9–11 de 11/)).toHaveAttribute('aria-live', 'polite')
  })

  it('la fila elegida se marca con aria-current y lo dice también con texto', () => {
    render(<GestionDiariaAnalista />)
    const lista = screen.getByRole('list', { name: /^Todo/ })
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
    expect(within(screen.getByRole('group', { name: 'Tu día en cifras' })).getByText('sin dato')).toBeInTheDocument()
    verPestana(/^Mi actividad/)
    expect(await screen.findByText('Todavía no hay llamadas hoy.')).toBeInTheDocument()
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
    expect(screen.getByRole('list', { name: 'Todo (1–3 de 3)' })).toBeInTheDocument()
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
    guardarDelPanel()
    await waitFor(() => expect(screen.getByRole('region', { name: 'Ahora' })).toHaveTextContent('Vuelta completada'))
    fireEvent.click(screen.getByRole('tab', { name: /^Todo/ }))
    await waitFor(() => expect(screen.getByTestId('acciones-contacto')).toHaveAttribute('data-lead', 'l2'))
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button').at(-1)).toHaveTextContent('NUEVO SIN INTENTO')
    expect(dobles.recargar).toHaveBeenCalled()
    expect(dobles.cola.refetch).not.toHaveBeenCalled()
    soltar()
  })

  it('al cerrar o guardar el resultado de la tarjeta termina la intención de contacto que la abrió (la siguiente llamada deja de esperar)', async () => {
    limpiarIntencionesContacto()
    // Lo que deja AccionesContacto al delegar en «Mi día»: la intención del lead de «Ahora», abierta.
    const abierta = armarIntencion({ actor: 'a1', leadId: 'l1', canal: 'tel', origen: 'enlace', numero: '+51999000111' })
    reclamarIntencion(abierta.id)
    const enCola = armarIntencion({ actor: 'a1', leadId: 'l2', canal: 'tel', origen: 'enlace', numero: '+51999000222' })
    render(<GestionDiariaAnalista />)
    dobles.contacto.onRegistrar?.()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    expect(intencionDe('a1', 'l2')).toBeNull() // espera detrás de la abierta
    guardarDelPanel()
    expect(intencionDe('a1', 'l1')).toBeNull()
    expect(intencionDe('a1', 'l2')).toMatchObject({ id: enCola.id, abierta: false })
    limpiarIntencionesContacto()
  })

  it('si la pantalla se va con la sesión de la tarjeta viva, libera su intención para no atascar la cola', async () => {
    limpiarIntencionesContacto()
    const abierta = armarIntencion({ actor: 'a1', leadId: 'l1', canal: 'tel', origen: 'enlace', numero: '+51999000111' })
    reclamarIntencion(abierta.id)
    const { unmount } = render(<GestionDiariaAnalista />)
    dobles.contacto.onRegistrar?.()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    expect(intencionDe('a1', 'l1')).toMatchObject({ abierta: true })
    unmount()
    expect(intencionDe('a1', 'l1')).toBeNull()
    limpiarIntencionesContacto()
  })

  it('al elegir una fila se enfoca el nombre de Ahora', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    fireEvent.click(within(screen.getByRole('list', { name: /^Vencidas/ })).getByRole('button', { name: /LEAD l2/ }))
    await waitFor(() => expect(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Abrir la ficha de LEAD l2' })).toHaveFocus())
  })

  it('la pestaña elegida y su conteo sobreviven a una recarga', () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    const tab = () => within(screen.getByRole('tablist', { name: 'Qué ver' })).getByRole('tab', { name: /^Mi seguimiento/ })
    expect(tab()).toHaveTextContent('Mi seguimiento· 1')
    fireEvent.click(tab())
    dobles.dia = { ...DIA_LLENO, compromisos_total: 2 }
    rerender(<GestionDiariaAnalista />)
    expect(tab()).toHaveTextContent('Mi seguimiento· 2')
    expect(tab()).toHaveAttribute('aria-selected', 'true')
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
    guardarDelPanel()
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

  it('tras «Llamar», cambiar de grupo NO cambia la persona: el resultado se abre para quien se llamó', async () => {
    dobles.contacto.real = true
    let responder: (v: boolean) => void = () => {}
    dobles.asegurarLead = vi.fn(() => new Promise<boolean>((r) => { responder = r }))
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: /^Copiar el número de NUEVO SIN INTENTO/ }))
    await waitFor(() => expect(dobles.asegurarLead).toHaveBeenCalledWith('l1'))
    // Mira otro grupo mientras marca: la lista cambia, la tarjeta no.
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    responder(true)
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' }))
    expect(screen.getByRole('region', { name: 'Resultado en la tarjeta (mock)' })).toBeInTheDocument()
  })
})

describe('GestionDiariaAnalista · «Todo», el siguiente y la persona fija (27/09/2026)', () => {
  it('elegir a alguien desde «Todo» NO cambia el filtro a su grupo', async () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getByRole('button', { name: /LEAD l2/ }))
    await waitFor(() => expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l2')).toBeInTheDocument())
    expect(within(screen.getByRole('tablist', { name: 'Grupos de la cola' })).getByRole('tab', { name: /^Todo/ })).toHaveAttribute('aria-selected', 'true')
  })

  it('con un GRUPO a la vista, si el refresco mueve al elegido de grupo, la vista lo sigue', async () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    fireEvent.click(within(screen.getByRole('list', { name: /^Vencidas/ })).getByRole('button', { name: /LEAD l2/ }))
    dobles.cola = { ...dobles.cola, data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l2', 'tarea_hoy', '2026-09-20T22:00:00Z')] } }
    rerender(<GestionDiariaAnalista />)
    await waitFor(() => expect(screen.getByRole('tab', { name: /^Hoy/ })).toHaveAttribute('aria-selected', 'true'))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l2')).toBeInTheDocument()
  })

  it('al guardar pasa a la persona que venía DETRÁS en la lista mirada, no a la primera', async () => {
    let soltar: () => void = () => {}
    dobles.recargar = vi.fn(() => new Promise<void>((r) => { soltar = () => { r() } }))
    render(<GestionDiariaAnalista />)
    // «Todo» = l1 (sin primer intento), l2 (vencida), l3 (sin conversación).
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getByRole('button', { name: /LEAD l2/ }))
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l2' }))
    guardarDelPanel()
    await waitFor(() => expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l3')).toBeInTheDocument())
    soltar()
  })

  it('«Llamar» FIJA a la persona: un lead más urgente que entra durante la llamada no la cambia', async () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    expect(typeof dobles.contacto.onLlamar).toBe('function')
    dobles.contacto.onLlamar?.()
    // Entra l9, sin primer intento y más antiguo: sin la fijación, pasaría a «Ahora».
    dobles.leads = [...dobles.leads, { id: 'l9', nombre_completo: 'LEAD l9', telefono: '+51999000999', etapa: 'nuevo' }]
    dobles.cola = { ...dobles.cola, data: { items: [itemCola('l9', 'primera_atencion', '2026-09-20T09:00:00Z'), ...((dobles.cola.data as { items: unknown[] }).items)] } }
    rerender(<GestionDiariaAnalista />)
    await waitFor(() => expect(screen.getAllByText('LEAD l9').length).toBeGreaterThan(0))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    expect(dobles.contacto.montajes).toEqual(['l1'])
  })

  it('el botón REAL «Llamar» avisa al pulsarlo y la persona queda fija aunque la cola cambie', async () => {
    dobles.contacto.real = true
    const { rerender } = render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: /^Copiar el número de NUEVO SIN INTENTO/ }))
    dobles.leads = [...dobles.leads, { id: 'l9', nombre_completo: 'LEAD l9', telefono: '+51999000999', etapa: 'nuevo' }]
    dobles.cola = { ...dobles.cola, data: { items: [itemCola('l9', 'primera_atencion', '2026-09-20T09:00:00Z'), ...((dobles.cola.data as { items: unknown[] }).items)] } }
    rerender(<GestionDiariaAnalista />)
    await waitFor(() => expect(screen.getAllByText('LEAD l9').length).toBeGreaterThan(0))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
  })
})

describe('GestionDiariaAnalista · el resultado DENTRO de «Ahora» (etapa 3)', () => {
  it('abierto el resultado, un refresco que trae a alguien más urgente NO cambia la tarjeta ni la persona', async () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' }))
    dobles.leads = [...dobles.leads, { id: 'l9', nombre_completo: 'LEAD l9', telefono: '+51999000999', etapa: 'nuevo' }]
    dobles.cola = { ...dobles.cola, data: { items: [itemCola('l9', 'primera_atencion', '2026-09-20T09:00:00Z'), ...((dobles.cola.data as { items: unknown[] }).items)] } }
    rerender(<GestionDiariaAnalista />)
    await waitFor(() => expect(screen.getAllByText('LEAD l9').length).toBeGreaterThan(0))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' })
  })

  it('abierto el resultado, elegir otra fila no cambia de persona: avisa', async () => {
    const { toast } = await import('sonner')
    const aviso = vi.spyOn(toast, 'info')
    render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' }))
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getByRole('button', { name: /LEAD l2/ }))
    expect(aviso).toHaveBeenCalledWith(expect.stringMatching(/Primero guarda o cierra el resultado/))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
  })

  it('«Cerrar sin registrar» vuelve a la tarjeta normal de la MISMA persona', async () => {
    render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    const props = dobles.panel.props!
    dobles.panel.props = null
    ;(props['onClose'] as () => void)()
    await waitFor(() => expect(screen.queryByRole('region', { name: 'Resultado en la tarjeta (mock)' })).not.toBeInTheDocument())
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    expect(screen.getByTestId('acciones-contacto')).toHaveAttribute('data-lead', 'l1')
  })

  it('una tarea que llega TARDE de una llamada ya abandonada no abre el resultado', async () => {
    let entregar: (t: Record<string, unknown> | null) => void = () => {}
    dobles.tareas = []
    dobles.obtenerTarea = vi.fn(() => new Promise<Record<string, unknown> | null>((r) => { entregar = r }))
    dobles.cola = { ...dobles.cola, data: { items: [{ ...itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), tarea_id: 't-lenta' }, itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z')] } }
    render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.obtenerTarea).toHaveBeenCalledWith('l1', 't-lenta'))
    // Mientras la tarea viaja, elige a otra persona: la llamada fijada se abandona.
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getByRole('button', { name: /LEAD l2/ }))
    await waitFor(() => expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('LEAD l2')).toBeInTheDocument())
    entregar({ id: 't-lenta', titulo: 'Tarde' })
    await new Promise((r) => setTimeout(r, 0))
    expect(dobles.panel.props).toBeNull()
    expect(screen.queryByRole('region', { name: 'Resultado en la tarjeta (mock)' })).not.toBeInTheDocument()
  })

  it('llamar a A, mirar otro grupo y cerrar sin registrar: la tarjeta y el foco vuelven a A (Codex, 27/09)', async () => {
    render(<GestionDiariaAnalista />)
    dobles.contacto.onLlamar?.()
    fireEvent.click(screen.getByRole('tab', { name: /^Vencidas/ }))
    // La tarjeta sigue en A mientras se mira otro grupo.
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    dobles.contacto.onRegistrar?.()
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' }))
    const props = dobles.panel.props!
    dobles.panel.props = null
    ;(props['onClose'] as () => void)()
    await waitFor(() => expect(screen.queryByRole('region', { name: 'Resultado en la tarjeta (mock)' })).not.toBeInTheDocument())
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    expect(screen.getByTestId('acciones-contacto')).toHaveAttribute('data-lead', 'l1')
  })

  it('con una llamada en curso, un refresco del día que FALLA no desmonta «Ahora» ni el resultado', async () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props?.lead).toMatchObject({ id: 'l1' }))
    dobles.dia = null
    dobles.errorDia = new Error('502')
    rerender(<GestionDiariaAnalista />)
    expect(screen.getByRole('alert')).toHaveTextContent(/No se pudo actualizar tu día. Termina de registrar a Nuevo/)
    expect(screen.getByRole('region', { name: 'Resultado en la tarjeta (mock)' })).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
    // Fail-closed: con el día caído no se pintan cifras ni cola sin confirmar.
    expect(screen.queryByRole('group', { name: 'Tu día en cifras' })).not.toBeInTheDocument()
    expect(screen.queryByRole('tablist', { name: 'Grupos de la cola' })).not.toBeInTheDocument()
  })

  it('con el foco dentro de «Ahora», un refresco no le cambia la persona a quien la lee', async () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    fireEvent.focus(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Abrir la ficha de NUEVO SIN INTENTO' }))
    dobles.leads = [...dobles.leads, { id: 'l9', nombre_completo: 'LEAD l9', telefono: '+51999000999', etapa: 'nuevo' }]
    dobles.cola = { ...dobles.cola, data: { items: [itemCola('l9', 'primera_atencion', '2026-09-20T09:00:00Z'), ...((dobles.cola.data as { items: unknown[] }).items)] } }
    rerender(<GestionDiariaAnalista />)
    await waitFor(() => expect(screen.getAllByText('LEAD l9').length).toBeGreaterThan(0))
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('NUEVO SIN INTENTO')).toBeInTheDocument()
  })
})

describe('«Lo último con este lead» en «Ahora» (Miguel, 27/09/2026)', () => {
  const gestion = (id: string, tipo: string, creado_en: string, detalle: string, metadata?: Record<string, unknown>) =>
    ({ id, lead_id: 'l1', tipo, detalle, autor_nombre: 'ANALISTA UNO', creado_en, ...(metadata ? { metadata } : {}) })

  it('muestra las 2 últimas GESTIONES del lead de «Ahora», sin los movimientos del sistema', () => {
    dobles.historial.items = [
      gestion('x1', 'cambio_etapa', '2026-09-20T17:50:00Z', 'Pasó a contactado'),
      gestion('x2', 'llamada_realizada', '2026-09-20T17:00:00Z', 'Contestó: pide que la llamen el lunes', { resultado: 'volver_a_llamar' }),
      gestion('x3', 'whatsapp_enviado', '2026-09-20T13:00:00Z', 'Le envié la dirección'),
      gestion('x4', 'nota', '2026-09-18T13:00:00Z', 'Nota vieja'),
    ]
    render(<GestionDiariaAnalista />)
    const bloque = within(screen.getByRole('region', { name: 'Ahora' })).getByRole('region', { name: 'Lo último con este lead' })
    const filas = within(bloque).getAllByRole('listitem')
    expect(filas).toHaveLength(2)
    expect(filas[0]).toHaveTextContent('Llamada realizada · Volver a llamar')
    expect(filas[0]).toHaveTextContent('Contestó: pide que la llamen el lunes')
    expect(filas[0]).toHaveTextContent('hace 1 h')
    expect(filas[1]).toHaveTextContent('WhatsApp enviado')
    expect(bloque).not.toHaveTextContent('Pasó a contactado')
    expect(bloque).not.toHaveTextContent('Nota vieja')
    // Se pide por el lead que está en «Ahora».
    expect(dobles.historial.pedidos.at(-1)).toBe('l1')
  })

  it('mientras carga lo dice, si falla ofrece reintentar y sin gestiones no inventa nada', () => {
    dobles.historial.cargando = true
    const { rerender } = render(<GestionDiariaAnalista />)
    const bloque = () => screen.getByRole('region', { name: 'Lo último con este lead' })
    expect(bloque()).toHaveTextContent('Cargando sus últimas gestiones…')
    expect(bloque()).not.toHaveTextContent('Sin gestiones')

    dobles.historial.cargando = false
    dobles.historial.error = new Error('502')
    rerender(<GestionDiariaAnalista />)
    expect(bloque()).toHaveTextContent('No se pudo cargar su historial.')
    fireEvent.click(within(bloque()).getByRole('button', { name: 'Reintentar' }))
    expect(dobles.historial.reintentar).toHaveBeenCalledTimes(1)

    dobles.historial.error = null
    rerender(<GestionDiariaAnalista />)
    expect(bloque()).toHaveTextContent('Sin gestiones todavía: esta llamada será la primera.')
  })

  it('«Ver todo» abre la ficha del lead de «Ahora»', () => {
    render(<GestionDiariaAnalista />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver todo el historial de NUEVO SIN INTENTO' }))
    expect(dobles.abrirLead).toHaveBeenCalledWith('l1')
  })

  it('con el resultado abierto, «Lo último» deja su sitio al formulario', async () => {
    render(<GestionDiariaAnalista />)
    expect(screen.getByRole('region', { name: 'Lo último con este lead' })).toBeInTheDocument()
    abrirResultado()
    await waitFor(() => expect(dobles.panel.props).not.toBeNull())
    expect(screen.queryByRole('region', { name: 'Lo último con este lead' })).not.toBeInTheDocument()
  })
})

// ── CLIENTES en la cola del día (v3, 29/09/2026) ─────────────────────────────
// Una tarea de un cliente de la cartera es una fila más, con su clave
// `tarea:<uuid>`. Sin lead: no hay sesión de llamada ni «Lo último con este
// lead»; su resultado va al cierre de tarea de siempre, sobre la tarea del
// ámbito, y el teléfono solo aparece si la ficha autorizada lo da.
const itemCliente = (tarea: string, bucket: 'tarea_vencida' | 'tarea_hoy', vence: string, sujeto: { perfil_id?: string; inversionista_id?: string; nombre: string }) => ({
  clave: `tarea:${tarea}`, tarea_id: tarea, lead_id: null, lead: null, estado: null, bucket,
  severidad: bucket === 'tarea_vencida' ? 'critica' : 'media', prioridad: bucket === 'tarea_vencida' ? 20 : 30, referencia_en: vence,
  senales: { pendientes: bucket === 'tarea_vencida', tareas_vencidas: bucket === 'tarea_vencida', primera_atencion: false,
    seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
  sujeto: { tipo: 'cliente', perfil_id: sujeto.perfil_id ?? null, inversionista_id: sujeto.inversionista_id ?? null, nombre: sujeto.nombre },
})
const tareaCliente = (id: string, extra: Record<string, unknown> = {}) => ({
  id, lead_id: null, inversionista_id: 'inv-rosa', inversionista_canonico_id: 'inv-rosa-canon', vendedor_id: 'a1', tipo: 'llamada',
  titulo: `Seguimiento ${id}`, vence_en: '2026-09-20T17:00:00Z', estado: 'pendiente', activo: true, reprogramaciones: 0, creado_en: '2026-09-19T12:00:00Z', ...extra,
})

describe('GestionDiariaAnalista · tareas de CLIENTES (cola v3)', () => {
  beforeEach(() => {
    dobles.cola = { data: { items: [
      itemCliente('c-venc', 'tarea_vencida', '2026-09-20T17:00:00Z', { inversionista_id: 'inv-rosa', nombre: 'ROSA CLIENTE' }),
      itemCliente('c-hoy', 'tarea_hoy', '2026-09-20T22:00:00Z', { inversionista_id: 'inv-rosa', nombre: 'ROSA CLIENTE' }),
      itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'),
    ] }, error: null, refetch: vi.fn(), isFetching: false }
    dobles.tareasAmbito = [tareaCliente('c-venc'), tareaCliente('c-hoy', { vence_en: '2026-09-20T22:00:00Z', titulo: 'Confirmar renovación' })]
    dobles.contactoCliente = { data: { telefono: '+51 988 777 666', contactar: true }, error: null, isPending: false, pedidos: [] }
  })

  function elegirCliente(nombre: RegExp) {
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button', { name: nombre })[0]!)
  }

  it('cada tarea es una fila (la misma persona dos veces) y cuenta en la cola', () => {
    render(<GestionDiariaAnalista />)
    const lista = screen.getByRole('list', { name: /^Todo/ })
    expect(within(lista).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(2)
    expect(within(lista).getAllByText(/Cliente de tu cartera · gestión agendada/)).toHaveLength(2)
    // Vencidas: la del cliente (hoy 12:00 Lima) va DETRÁS de la de ayer del lead.
    expect(within(screen.getByRole('tablist', { name: 'Grupos de la cola' })).getByRole('tab', { name: /Vencidas/ })).toHaveTextContent('2')
  })

  it('«Ahora» con un cliente: su nombre, su tarea, su teléfono de la ficha y «Registrar resultado»; sin lead ni historial de lead', () => {
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).getByRole('button', { name: 'Abrir la ficha de ROSA CLIENTE' })).toBeInTheDocument()
    expect(within(ahora).getByText('Cliente de tu cartera')).toBeInTheDocument()
    expect(within(ahora).getByText('Llamada · Seguimiento c-venc')).toBeInTheDocument()
    expect(within(ahora).getByText('+51 988 777 666')).toBeInTheDocument()
    // En la laptop no hay radio: «Llamar» copia el número y abre el registro, como el de un lead.
    expect(within(ahora).getByRole('button', { name: 'Llamar a ROSA CLIENTE: copia su número y abre el registro' })).toBeInTheDocument()
    expect(within(ahora).queryByRole('link', { name: /Llamar/ })).toBeNull()
    // El teléfono se pide por la CANÓNICA del cliente, la misma que abre su ficha.
    expect(dobles.contactoCliente.pedidos).toContain('inv-rosa-canon')
    expect(within(ahora).queryByText('Lo último con este lead')).toBeNull()
    expect(screen.queryByTestId('acciones-contacto')).toBeNull()
    // Una fila de cliente no pide leads al store.
    expect(dobles.asegurarLead).not.toHaveBeenCalledWith('c-venc')
  })

  it('«Registrar resultado» abre el cierre de tarea con la tarea del ámbito, no con otra', () => {
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    expect(dobles.cierre.tarea).toMatchObject({ id: 'c-venc', inversionista_id: 'inv-rosa' })
    expect(screen.getByRole('dialog', { name: 'Cerrar tarea (mock)' })).toBeInTheDocument()
  })

  it('en la laptop «Llamar» abre YA el cierre de ESA tarea y copia el número, sin esperar al portapapeles', () => {
    // Un portapapeles que no contesta nunca: el registro no puede quedar esperándolo.
    const copiar = vi.fn(() => new Promise<void>(() => {}))
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: copiar } })
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: /^Llamar a ROSA CLIENTE/ }))
    expect(dobles.cierre.tarea).toMatchObject({ id: 'c-venc' })
    expect(copiar).toHaveBeenCalledWith('+51 988 777 666')
  })

  it('en el celular «Llamar» es un enlace tel: con el número de la fuente única (sin espacios)', () => {
    const original = window.matchMedia
    window.matchMedia = ((q: string) => ({ matches: q.includes('pointer: coarse') || q.includes('prefers-reduced-motion'), media: q, onchange: null,
      addEventListener: () => {}, removeEventListener: () => {}, addListener: () => {}, removeListener: () => {}, dispatchEvent: () => false })) as typeof window.matchMedia
    try {
      render(<GestionDiariaAnalista />)
      elegirCliente(/ROSA CLIENTE/)
      expect(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('link', { name: 'Llamar a ROSA CLIENTE' })).toHaveAttribute('href', 'tel:+51988777666')
    } finally {
      window.matchMedia = original
    }
  })

  it('un número que no sirve para marcar no se ofrece', () => {
    dobles.contactoCliente = { data: { telefono: '12-34', contactar: true }, error: null, isPending: false, pedidos: [] }
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).queryByRole('button', { name: /^Llamar a/ })).toBeNull()
    expect(within(ahora).queryByText('12-34')).toBeNull()
    expect(within(ahora).getByRole('status')).toHaveTextContent('Su ficha no tiene un número válido.')
  })

  it('si la relectura del contacto FALLA no se pinta el número de antes (fail-closed)', () => {
    dobles.contactoCliente = { data: { telefono: '+51 988 777 666', contactar: true }, error: new Error('ficha caída'), isPending: false, pedidos: [] }
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).queryByText('+51 988 777 666')).toBeNull()
    expect(within(ahora).queryByRole('button', { name: /^Llamar a/ })).toBeNull()
    expect(within(ahora).getByRole('status')).toHaveTextContent('No se pudo traer su número. Ábrelo en su ficha.')
  })

  /** Lo que hace el store al confirmar el servidor el cierre: la tarea deja de estar pendiente. */
  function cerrarEnElStore(id: string) {
    dobles.tareasAmbito = dobles.tareasAmbito.map((t) => (t['id'] === id ? { ...t, estado: 'completada' } : t))
  }
  const colaSinLaCerrada = () => ({ items: [
    itemCliente('c-hoy', 'tarea_hoy', '2026-09-20T22:00:00Z', { inversionista_id: 'inv-rosa', nombre: 'ROSA CLIENTE' }),
    itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'),
  ] })

  it('al guardar (el store ya no la tiene pendiente) «Ahora» pasa a la fila de DETRÁS —la otra tarea de la misma persona— y el foco no se pierde', async () => {
    dobles.cola.refetch = vi.fn(async () => { dobles.cola.data = colaSinLaCerrada(); return dobles.cola })
    render(<GestionDiariaAnalista />)
    // «Todo»: vencida del lead l2 (ayer), vencida de ROSA (hoy), de hoy de ROSA, sin conversación l3.
    elegirCliente(/ROSA CLIENTE/)
    const registrar = within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' })
    fireEvent.click(registrar)
    cerrarEnElStore('c-venc')
    registrar.focus()
    act(() => { dobles.cierre.onCerrar?.() })
    // La que venía detrás en «Todo»: la de hoy de la misma persona (su OTRA tarea), sin esperar a la red.
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).getByText('Llamada · Confirmar renovación')).toBeInTheDocument()
    // La cerrada se tapa ya en la lista, aunque la cola todavía no se haya releído.
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(1)
    await waitFor(() => expect(within(ahora).getByRole('button', { name: 'Abrir la ficha de ROSA CLIENTE' })).toHaveFocus())
    await waitFor(() => expect(dobles.cola.refetch).toHaveBeenCalledTimes(1))
    expect(dobles.recargar).toHaveBeenCalled()
  })

  it('si se cerró el diálogo sin guardar (la tarea sigue pendiente en el store), «Ahora» no cambia y no se relee nada', () => {
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    act(() => { dobles.cierre.onCerrar?.() })
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('Llamada · Seguimiento c-venc')).toBeInTheDocument()
    expect(screen.queryByRole('dialog', { name: 'Cerrar tarea (mock)' })).toBeNull()
    expect(dobles.cola.refetch).not.toHaveBeenCalled()
  })

  it('si el store aplica el cierre DESPUÉS del aviso (commit posterior), también cuenta', () => {
    const { rerender } = render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    act(() => { dobles.cierre.onCerrar?.() })
    // Todavía nada: el store no lo refleja aún.
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('Llamada · Seguimiento c-venc')).toBeInTheDocument()
    cerrarEnElStore('c-venc')
    rerender(<GestionDiariaAnalista />)
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('Llamada · Confirmar renovación')).toBeInTheDocument()
  })

  it('reprogramada a OTRO día: sale de la cola del día y «Ahora» pasa a la siguiente', () => {
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    dobles.tareasAmbito = dobles.tareasAmbito.map((t) => (t['id'] === 'c-venc' ? { ...t, vence_en: '2099-01-02T15:00:00Z' } : t))
    act(() => { dobles.cierre.onCerrar?.() })
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('Llamada · Confirmar renovación')).toBeInTheDocument()
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(1)
    expect(dobles.cola.refetch).toHaveBeenCalledTimes(1)
  })

  it('reprogramada DENTRO de hoy: sigue en su sitio, «Ahora» no cambia y se relee su hora', () => {
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    // Una hora más tarde que la que tenía (el 20/09, antes del final del día de hoy).
    dobles.tareasAmbito = dobles.tareasAmbito.map((t) => (t['id'] === 'c-venc' ? { ...t, vence_en: '2026-09-20T18:00:00Z' } : t))
    act(() => { dobles.cierre.onCerrar?.() })
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Abrir la ficha de ROSA CLIENTE' })).toBeInTheDocument()
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(2)
    expect(dobles.cola.refetch).toHaveBeenCalledTimes(1)
    expect(dobles.recargar).not.toHaveBeenCalled()
  })

  it('una relectura FALLIDA no destapa la cerrada, ni una cola vieja al volver; una lectura nueva sin ella retira la máscara', async () => {
    const vieja = dobles.cola.data
    dobles.cola.refetch = vi.fn(async () => { dobles.cola.error = new Error('cola caída'); return dobles.cola })
    const { rerender } = render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    cerrarEnElStore('c-venc')
    await act(async () => { dobles.cierre.onCerrar?.() })
    rerender(<GestionDiariaAnalista />)
    // Cola caída: no se pinta nada de ella (fail-closed).
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo leer la cola del servidor')
    // Vuelve la cola con la foto VIEJA (aún trae la cerrada): sigue tapada.
    dobles.cola.error = null
    dobles.cola.data = { ...(vieja as object) }
    rerender(<GestionDiariaAnalista />)
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(1)
    // Lectura nueva sin ella: la máscara ya no hace falta y la lista cuadra sola.
    dobles.cola.data = colaSinLaCerrada()
    rerender(<GestionDiariaAnalista />)
    expect(within(screen.getByRole('list', { name: /^Todo/ })).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(1)
  })

  it('un doble aviso del diálogo cuenta UNA vez: no salta a la primera de la lista', () => {
    dobles.cola.refetch = vi.fn(async () => { dobles.cola.data = colaSinLaCerrada(); return dobles.cola })
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    cerrarEnElStore('c-venc')
    const aviso = dobles.cierre.onCerrar
    act(() => { aviso?.(); aviso?.() })
    act(() => { aviso?.() })
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('Llamada · Confirmar renovación')).toBeInTheDocument()
    expect(dobles.cola.refetch).toHaveBeenCalledTimes(1)
  })

  it('una relectura lenta de un cierre anterior no pisa la persona que el analista eligió después', async () => {
    let soltar: (() => void) | null = null
    dobles.cola.refetch = vi.fn(() => new Promise((resolver) => { soltar = () => resolver(dobles.cola) }))
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    cerrarEnElStore('c-venc')
    act(() => { dobles.cierre.onCerrar?.() })
    // Mientras la cola se relee, el analista elige a otra persona.
    fireEvent.click(within(screen.getByRole('list', { name: /^Todo/ })).getByRole('button', { name: /LEAD l2/ }))
    await act(async () => { soltar?.() })
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Abrir la ficha de LEAD l2' })).toBeInTheDocument()
  })

  it('si la tarea todavía no está en el ámbito, lo dice y no abre otra', async () => {
    dobles.tareasAmbito = []
    const { toast } = await import('sonner')
    const aviso = vi.spyOn(toast, 'error')
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).getByText('No encontramos esta gestión en tu agenda. Recarga la página para verla.')).toBeInTheDocument()
    fireEvent.click(within(ahora).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' }))
    expect(aviso).toHaveBeenCalledWith(expect.stringContaining('No encontramos esta gestión pendiente'))
    expect(dobles.cierre.tarea).toBeNull()
  })

  it('la ficha del cliente se abre por su canónica', () => {
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    fireEvent.click(within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Ver la ficha del cliente ROSA CLIENTE' }))
    expect(dobles.abrirInversionista).toHaveBeenCalledWith('inv-rosa-canon')
    expect(dobles.abrirLead).not.toHaveBeenCalled()
  })

  it('cliente SOLO del portal (perfil): sin ficha, sin teléfono y sin enlaces falsos', () => {
    dobles.cola = { data: { items: [itemCliente('c-portal', 'tarea_hoy', '2026-09-20T22:00:00Z', { perfil_id: 'p-1', nombre: 'LUIS PORTAL' })] }, error: null, refetch: vi.fn(), isFetching: false }
    dobles.tareasAmbito = [tareaCliente('c-portal', { inversionista_id: null, inversionista_canonico_id: null, perfil_id: 'p-1', titulo: 'Escribir a LUIS PORTAL' })]
    render(<GestionDiariaAnalista />)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    const nombre = within(ahora).getByRole('button', { name: 'LUIS PORTAL, sin ficha en tu cartera' })
    expect(nombre).toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(nombre)
    expect(dobles.abrirInversionista).not.toHaveBeenCalled()
    expect(within(ahora).getByText(/aún no tiene ficha en tu cartera/)).toBeInTheDocument()
    expect(within(ahora).queryByRole('link', { name: /Llamar/ })).toBeNull()
    expect(within(ahora).queryByRole('button', { name: /^Ver la ficha del cliente/ })).toBeNull()
    // Lo fijo no se anuncia como región viva: el nombre enfocado ya lo dice.
    expect(within(ahora).queryByRole('status')).toBeNull()
    expect(dobles.contactoCliente.pedidos.every((id) => id === '')).toBe(true)
  })

  it('un cliente que no se puede contactar no ofrece «Llamar»', () => {
    dobles.contactoCliente = { data: { telefono: '+51 988 777 666', contactar: false }, error: null, isPending: false, pedidos: [] }
    render(<GestionDiariaAnalista />)
    elegirCliente(/ROSA CLIENTE/)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).queryByText('+51 988 777 666')).toBeNull()
    expect(within(ahora).queryByRole('link', { name: /Llamar/ })).toBeNull()
    expect(within(ahora).getByText(/no se puede contactar ahora/)).toBeInTheDocument()
  })

  it('ESTADO DE PRODUCCIÓN: cola solo con clientes y el día vacío; «Ahora» los propone igual', () => {
    dobles.dia = { ...DIA_LLENO, cartera: [], compromisos: [], compromisos_total: 0, descartados: [],
      marcador: { ...DIA_LLENO.marcador, llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, leads_tocados: 0, citas_agendadas: 0, por_resultado: {}, por_hora: [] } } as unknown as DiaAnalista
    dobles.cola = { data: { items: [itemCliente('c-venc', 'tarea_vencida', '2026-09-20T17:00:00Z', { inversionista_id: 'inv-rosa', nombre: 'ROSA CLIENTE' })] }, error: null, refetch: vi.fn(), isFetching: false }
    render(<GestionDiariaAnalista />)
    const ahora = screen.getByRole('region', { name: 'Ahora' })
    expect(within(ahora).getByRole('button', { name: 'Abrir la ficha de ROSA CLIENTE' })).toBeInTheDocument()
    expect(within(ahora).getByText(/Se pasó hace 1 h/)).toBeInTheDocument()
  })

  it('en DEMO los clientes salen de las tareas del ámbito con la regla del servidor', () => {
    dobles.yo = { id: 'a1', rol: 'vendedor', demo: true, nombre_completo: 'ANALISTA UNO' }
    dobles.dia = { ...DIA_LLENO, cartera: [] } as unknown as DiaAnalista
    dobles.tareasAmbito = [
      tareaCliente('d-venc', { titulo: 'Llamar a ROSA DEMO' }),
      tareaCliente('d-manana', { titulo: 'Llamar a MAÑANA', vence_en: '2026-09-21T15:00:00Z' }),
      tareaCliente('d-ajena', { titulo: 'Llamar a AJENA', vendedor_id: 'otro' }),
    ]
    render(<GestionDiariaAnalista />)
    const lista = screen.getByRole('list', { name: /^Todo/ })
    expect(within(lista).getByRole('button', { name: /ROSA DEMO/ })).toBeInTheDocument()
    expect(within(lista).queryByRole('button', { name: /MAÑANA|AJENA/ })).toBeNull()
    // En demo no se consulta la ficha del cliente.
    expect(dobles.contactoCliente.pedidos.every((id) => id === '')).toBe(true)
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText('Su número está en su ficha.')).toBeInTheDocument()
  })

  it('en DEMO, al guardar el cliente (el store demo lo cierra) y no quedar nadie, el foco va al título', async () => {
    dobles.yo = { id: 'a1', rol: 'vendedor', demo: true, nombre_completo: 'ANALISTA UNO' }
    dobles.dia = { ...DIA_LLENO, cartera: [] } as unknown as DiaAnalista
    dobles.tareasAmbito = [tareaCliente('d-venc', { titulo: 'Llamar a ROSA DEMO' })]
    render(<GestionDiariaAnalista />)
    const registrar = within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA DEMO' })
    fireEvent.click(registrar)
    cerrarEnElStore('d-venc')
    registrar.focus()
    act(() => { dobles.cierre.onCerrar?.() })
    expect(within(screen.getByRole('region', { name: 'Ahora' })).getByText(/Nada pendiente ahora/)).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('heading', { level: 2, name: '¿A quién llamo ahora?' })).toHaveFocus())
    expect(dobles.cola.refetch).not.toHaveBeenCalled()
  })
})
