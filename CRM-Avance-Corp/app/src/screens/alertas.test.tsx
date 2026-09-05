import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { AlertaCRM } from '@/lib/alertas'
import type { EstadoAlertasCRM } from '@/lib/alertas-context'
import type { Rol } from '@/lib/roles'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { usePeriodoGerencia } from '@/components/gerencia/use-periodo-gerencia'

const reintentar = vi.fn()
const reconocer = vi.fn<EstadoAlertasCRM['reconocer']>().mockResolvedValue(undefined)
let ESTADO: EstadoAlertasCRM = {
  alertas: [],
  pendientes: 0,
  pospuestas: 0,
  rol: 'vendedor',
  cargando: false,
  errores: [],
  generadoEn: '2026-08-06T17:35:00.000Z',
  reintentar,
  reconocer,
}

vi.mock('@/lib/alertas-context', () => ({
  useAlertasCRM: () => ESTADO,
}))

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

const { Alertas } = await import('./alertas')

function alerta(over: Partial<AlertaCRM> = {}): AlertaCRM {
  return {
    id: 'tarea_vencida:lead-1',
    tipo: 'tarea_vencida',
    severidad: 'critica',
    alcance: 'personal',
    titulo: 'Tarea vencida',
    detalle: '«Llamar al cliente» venció hace 1 día.',
    responsableId: 'v1',
    responsable: 'Ana Analista',
    valor: 24,
    destino: {
      vista: 'agenda',
      leadId: 'lead-1',
      etiqueta: 'Abrir en Agenda',
    },
    ...over,
  }
}

function montar({
  rol = 'vendedor',
  alertas = [],
  cargando = false,
  errores = [],
  pospuestas = 0,
  conSondaPeriodo = false,
}: {
  rol?: Rol
  alertas?: AlertaCRM[]
  cargando?: boolean
  errores?: string[]
  pospuestas?: number
  conSondaPeriodo?: boolean
} = {}) {
  reintentar.mockReset()
  reconocer.mockClear()
  ESTADO = {
    alertas,
    // Como en el provider real: lo reconocido no cuenta como pendiente.
    pendientes: alertas.filter((fila) => fila.reconocimiento == null).length,
    pospuestas,
    rol,
    cargando,
    errores,
    generadoEn: '2026-08-06T17:35:00.000Z',
    reintentar,
    reconocer,
  }
  return render(<PeriodoGerenciaProvider><Alertas />{conSondaPeriodo && <SondaPeriodo />}</PeriodoGerenciaProvider>)
}

function SondaPeriodo() {
  const { periodo, setPeriodo, origenFiltrado, setOrigenFiltrado } = usePeriodoGerencia()
  return <><button onClick={() => { setPeriodo({ desde: '2026-07-01', hasta: '2026-07-15' }); setOrigenFiltrado('landing') }}>Elegir período anterior de prueba</button><output data-testid="periodo-de-prueba">{JSON.stringify({ periodo, origenFiltrado })}</output></>
}

describe('Alertas — responsabilidad por rol', () => {
  it.each([
    ['vendedor', 'Mis pendientes actuales', 'Tu acción'],
    ['supervisor', 'Excepciones del equipo', 'Tu intervención'],
    ['gerencia', 'Señales de gestión', 'Tu decisión'],
  ] as const)('presenta a %s únicamente su nivel de responsabilidad', (rol, titulo, alcance) => {
    montar({ rol })

    expect(screen.getByRole('heading', { name: titulo })).toBeVisible()
    expect(screen.getByText(alcance)).toBeVisible()
  })

  it('lleva cada pendiente al caso exacto que lo resuelve', () => {
    montar({ alertas: [alerta()] })

    expect(screen.getByRole('link', { name: 'Abrir en Agenda: Tarea vencida' })).toHaveAttribute(
      'href',
      '#/agenda/lead/lead-1',
    )
    expect(screen.getByText('Responsable: Ana Analista')).toBeVisible()
  })

  it('filtra por prioridad, tipo y texto sin perder el total activo', async () => {
    const user = userEvent.setup()
    montar({
      rol: 'supervisor',
      alertas: [
        alerta(),
        alerta({
          id: 'sin_proxima_accion:vendedor:v2',
          tipo: 'sin_proxima_accion',
          severidad: 'atencion',
          alcance: 'equipo',
          titulo: 'Analista con leads sin próxima acción',
          detalle: 'Bruno tiene 3 leads sin una próxima acción registrada.',
          responsableId: 'v2',
          responsable: 'Bruno Supervisor',
          valor: 3,
          destino: { vista: 'equipo', etiqueta: 'Ver equipo' },
        }),
      ],
    })

    await user.click(screen.getByRole('button', { name: 'Atención: 1' }))
    expect(screen.queryByRole('heading', { name: 'Tarea vencida' })).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Analista con leads sin próxima acción' })).toBeVisible()
    expect(screen.getByRole('status')).toHaveTextContent('1 pendiente activo de 2')

    await user.selectOptions(screen.getByRole('combobox', { name: 'Filtrar por tipo' }), 'sin_proxima_accion')
    await user.type(screen.getByRole('searchbox', { name: 'Buscar pendiente' }), 'bruno')
    const lista = screen.getByRole('list', { name: 'Pendientes activos' })
    expect(within(lista).getAllByRole('listitem')).toHaveLength(1)
  })

  it('distingue carga, error y ausencia real de pendientes', () => {
    const carga = montar({ cargando: true })
    expect(screen.getByRole('status', { name: 'Cargando pendientes' })).toBeInTheDocument()
    carga.unmount()

    const error = montar({ errores: ['No se pudo calcular la conversión actual.'] })
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo calcular la conversión actual.')
    error.unmount()

    montar({ rol: 'supervisor' })
    expect(screen.getByText('Nada pendiente')).toBeVisible()
    expect(screen.getByText('Tu equipo no tiene excepciones que requieran intervención.')).toBeVisible()
  })

  it('Gerencia no interpreta ausencia de avisos como evaluación completa', () => {
    montar({ rol: 'gerencia' })

    expect(screen.getByText('Sin avisos generados')).toBeVisible()
    expect(screen.getByText(/puede faltar el corte de revisión, una meta, muestra suficiente o verificación/)).toBeVisible()
    expect(screen.queryByText('Nada pendiente')).not.toBeInTheDocument()
    expect(screen.queryByText('No hay desviaciones estratégicas que requieran una decisión.')).not.toBeInTheDocument()
    expect(screen.getByText(/Señales del mes en curso/)).toBeVisible()
  })

  it('abre la señal de Gerencia con su rango consultado y sin un filtro de origen anterior', async () => {
    const usuario = userEvent.setup()
    const periodo = { desde: '2026-09-01', hasta: '2026-09-04' }
    montar({ rol: 'gerencia', conSondaPeriodo: true, alertas: [alerta({
      id: 'caida_conversion:global', tipo: 'caida_conversion', alcance: 'empresa',
      titulo: 'Caída de conversión', destino: { vista: 'ranking-vendedores', etiqueta: 'Ver ranking', periodo },
    })] })
    await usuario.click(screen.getByRole('button', { name: 'Elegir período anterior de prueba' }))
    expect(screen.getByTestId('periodo-de-prueba')).toHaveTextContent('2026-07-01')
    expect(screen.getByTestId('periodo-de-prueba')).toHaveTextContent('landing')

    fireEvent.click(screen.getByRole('link', { name: 'Ver ranking: Caída de conversión' }))

    expect(screen.getByTestId('periodo-de-prueba')).toHaveTextContent(JSON.stringify({ periodo, origenFiltrado: null }))
  })

  it('un enlace operativo sin rango no altera el período de Gerencia', async () => {
    const usuario = userEvent.setup()
    montar({ conSondaPeriodo: true, alertas: [alerta()] })
    await usuario.click(screen.getByRole('button', { name: 'Elegir período anterior de prueba' }))
    fireEvent.click(screen.getByRole('link', { name: 'Abrir en Agenda: Tarea vencida' }))

    expect(screen.getByTestId('periodo-de-prueba')).toHaveTextContent('2026-07-01')
    expect(screen.getByTestId('periodo-de-prueba')).toHaveTextContent('landing')
  })
})

// ── F3 «Recordar»: la alerta de contacto verifica BAJO DEMANDA ───────────────
// Mutantes que deben morir aquí: quitar la rama especial (volvería el <a>
// genérico), Verificar sin teléfono precargado, y Quitar sin invalidar.
describe('Alertas — revisar contacto (F3)', () => {
  const alertaContacto = (): AlertaCRM => alerta({
    id: 'revisar-contacto-r1',
    tipo: 'revisar_contacto',
    severidad: 'atencion',
    titulo: 'Revisar contacto',
    detalle: 'Programaste verificar si 987 654 321 ya está libre.',
    responsable: null,
    valor: null,
    destino: { vista: 'alertas', etiqueta: 'Verificar disponibilidad' },
    contacto: { telefono: '+51987654321', recordatorioId: 'r1' },
  })

  async function montarConProviders(alertas: AlertaCRM[]) {
    const { QueryClient, QueryClientProvider } = await import('@tanstack/react-query')
    const { PanelActionsContext } = await import('@/lib/store-context')
    const abrirNuevoLead = vi.fn()
    const actions = { abrirLead: vi.fn(), abrirNuevoLead, cerrarPaneles: vi.fn() }
    // Codex R6: el refresco de la campana se asevera sobre el MISMO cliente
    // que ve el componente — un mutante sin invalidateQueries muere aquí.
    const clienteConsultas = new QueryClient()
    const invalidar = vi.spyOn(clienteConsultas, 'invalidateQueries')
    reintentar.mockReset()
    reconocer.mockClear()
    ESTADO = {
      alertas,
      pendientes: alertas.length,
      pospuestas: 0,
      rol: 'vendedor',
      cargando: false,
      errores: [],
      generadoEn: '2026-08-06T17:35:00.000Z',
      reintentar,
      reconocer,
    }
    render(
      <PeriodoGerenciaProvider><QueryClientProvider client={clienteConsultas}>
        <PanelActionsContext.Provider value={actions}>
          <Alertas />
        </PanelActionsContext.Provider>
      </QueryClientProvider></PeriodoGerenciaProvider>,
    )
    return { abrirNuevoLead, invalidar, clienteConsultas }
  }

  it('Verificar abre el alta con el TELÉFONO precargado — el circuito F1/F2 entero', async () => {
    const user = userEvent.setup()
    const { abrirNuevoLead } = await montarConProviders([alertaContacto()])

    await user.click(screen.getByRole('button', { name: /Verificar disponibilidad/ }))

    expect(abrirNuevoLead).toHaveBeenCalledWith(undefined, '+51987654321')
  })

  it('Quitar elimina el recordatorio, refresca la campana y el foco sigue al DATO desaparecido', async () => {
    const api = await import('@/data/crm-api')
    const { crmQueryKeys } = await import('@/data/crm-queries')
    const eliminar = vi.spyOn(api, 'eliminarRecordatorioDisponibilidad').mockResolvedValue()
    const user = userEvent.setup()
    const { invalidar, clienteConsultas } = await montarConProviders([alertaContacto()])
    // El cache post-refetch ya no trae la fila: es la realidad que decide.
    clienteConsultas.setQueryData(crmQueryKeys.recordatoriosDisponibilidad(), [])

    await user.click(screen.getByRole('button', { name: /Quitar recordatorio/ }))

    expect(eliminar).toHaveBeenCalledWith('r1')
    // Codex R6: sin la invalidación la campana quedaría rancia.
    await waitFor(() => expect(invalidar).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.recordatoriosDisponibilidad(),
    }))
    // a11y M4: el dato ya no existe → la fila se va → el foco aterriza en el
    // contador, que además anuncia el nuevo total.
    await waitFor(() => expect(document.getElementById('alertas-contador')).toHaveFocus())
    eliminar.mockRestore()
  })

  it('M4 (Codex): borrado OK pero refetch caído — el dato SIGUE y el foco no salta', async () => {
    const api = await import('@/data/crm-api')
    const { crmQueryKeys } = await import('@/data/crm-queries')
    const eliminar = vi.spyOn(api, 'eliminarRecordatorioDisponibilidad').mockResolvedValue()
    const user = userEvent.setup()
    const { clienteConsultas } = await montarConProviders([alertaContacto()])
    // Un refetch caído CONSERVA el dato viejo en cache: la fila sigue pintada.
    clienteConsultas.setQueryData(crmQueryKeys.recordatoriosDisponibilidad(), [
      { id: 'r1', perfil_id: 'v1', telefono: '+51987654321', dni: null, recordar_en: '2026-08-05T14:00:00+00:00', creado_en: '2026-08-01T14:00:00+00:00' },
    ])

    const boton = screen.getByRole('button', { name: /Quitar recordatorio/ })
    await user.click(boton)

    // El foco NO va al contador (la fila sigue siendo el lugar del usuario):
    // este era exactamente el mutante que el diseño «por intención» no mataba.
    await waitFor(() => expect(boton).toBeEnabled())
    expect(document.getElementById('alertas-contador')).not.toHaveFocus()
    expect(boton).toHaveFocus()
    eliminar.mockRestore()
  })

  it('si Quitar falla DE VERDAD la fila sigue viva y el foco vuelve al botón', async () => {
    const api = await import('@/data/crm-api')
    const { crmQueryKeys } = await import('@/data/crm-queries')
    const { toast } = await import('sonner')
    const eliminar = vi.spyOn(api, 'eliminarRecordatorioDisponibilidad')
      .mockRejectedValue(new api.CrmApiError('Sin conexión con el servidor.', 'RED'))
    const { clienteConsultas } = await montarConProviders([alertaContacto()])
    clienteConsultas.setQueryData(crmQueryKeys.recordatoriosDisponibilidad(), [
      { id: 'r1', perfil_id: 'v1', telefono: '+51987654321', dni: null, recordar_en: '2026-08-05T14:00:00+00:00', creado_en: '2026-08-01T14:00:00+00:00' },
    ])

    const boton = screen.getByRole('button', { name: /Quitar recordatorio/ })
    boton.focus()
    fireEvent.click(boton)
    // El navegador REAL suelta el foco de un botón deshabilitado. En jsdom
    // blur() sobre un disabled es NO-OP y body.focus() también (body no es
    // focusable sin tabindex) — el foco huérfano se simula así. Sin esto, la
    // aserción pasaba aunque el rescate se borrara (mutante superviviente).
    document.body.tabIndex = -1
    document.body.focus()

    await waitFor(() => expect(vi.mocked(toast.error)).toHaveBeenCalled())
    // Al re-habilitarse, el rescate devuelve el foco huérfano — nunca al contador.
    await waitFor(() => expect(boton).toBeEnabled())
    await waitFor(() => expect(boton).toHaveFocus())
    expect(document.getElementById('alertas-contador')).not.toHaveFocus()
    eliminar.mockRestore()
  })

  it('T2: «ya no existía» (caducó/otra pestaña) NO grita, refresca y mueve el foco', async () => {
    const api = await import('@/data/crm-api')
    const { crmQueryKeys } = await import('@/data/crm-queries')
    const { toast } = await import('sonner')
    vi.mocked(toast.error).mockClear()
    const eliminar = vi.spyOn(api, 'eliminarRecordatorioDisponibilidad')
      .mockRejectedValue(new api.CrmApiError('El recordatorio ya no existe.', 'NO_ENCONTRADO'))
    const user = userEvent.setup()
    const { invalidar, clienteConsultas } = await montarConProviders([alertaContacto()])
    clienteConsultas.setQueryData(crmQueryKeys.recordatoriosDisponibilidad(), [])

    await user.click(screen.getByRole('button', { name: /Quitar recordatorio/ }))

    expect(vi.mocked(toast.error)).not.toHaveBeenCalled()
    await waitFor(() => expect(invalidar).toHaveBeenCalled())
    await waitFor(() => expect(document.getElementById('alertas-contador')).toHaveFocus())
    eliminar.mockRestore()
  })

  it('si era la ÚLTIMA alerta y el contador se fue, el foco cae al encabezado', async () => {
    const api = await import('@/data/crm-api')
    const { crmQueryKeys } = await import('@/data/crm-queries')
    const eliminar = vi.spyOn(api, 'eliminarRecordatorioDisponibilidad').mockResolvedValue()
    const user = userEvent.setup()
    const { clienteConsultas } = await montarConProviders([alertaContacto()])
    clienteConsultas.setQueryData(crmQueryKeys.recordatoriosDisponibilidad(), [])
    // El arnés pinta con ESTADO estático: se simula la retirada del contador
    // (en producción desaparece junto con la lista vacía).
    document.getElementById('alertas-contador')?.remove()

    await user.click(screen.getByRole('button', { name: /Quitar recordatorio/ }))

    await waitFor(() => expect(document.getElementById('alertas-encabezado')).toHaveFocus())
    eliminar.mockRestore()
  })

  it('a11y N1: los aria-label dictan el teléfono legible, no el +51 crudo', async () => {
    await montarConProviders([alertaContacto()])
    expect(screen.getByRole('button', { name: 'Verificar disponibilidad de 987 654 321' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Quitar recordatorio de 987 654 321' })).toBeInTheDocument()
  })

  it('las alertas SIN contacto conservan su enlace de siempre', async () => {
    await montarConProviders([alerta()])
    expect(screen.getByRole('link', { name: /Abrir en Agenda/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Verificar disponibilidad/ })).not.toBeInTheDocument()
  })
})

describe('Alertas — reconocer y posponer (F4)', () => {
  const AHORA = Date.UTC(2026, 7, 23, 15)

  function grupo(over: Partial<AlertaCRM> = {}): AlertaCRM {
    return alerta({
      id: 'grupo:por_repartir:s1',
      tipo: 'por_repartir',
      severidad: 'atencion',
      alcance: 'equipo',
      titulo: '2 leads esperando reparto',
      detalle: 'A, B. El más rezagado espera hace 4 días.',
      responsableId: 's1',
      responsable: null,
      valor: 2,
      miembros: ['lead-1', 'lead-2'],
      destino: { vista: 'derivaciones', leadId: null, etiqueta: 'Repartir' },
      ...over,
    })
  }

  it('solo las alertas AGRUPADAS (con foto de miembros) ofrecen los botones', () => {
    montar({ rol: 'supervisor', alertas: [grupo(), alerta()] })

    expect(screen.getAllByRole('button', { name: /la estoy atendiendo/ })).toHaveLength(1)
    expect(screen.getAllByRole('button', { name: /^Posponer/ })).toHaveLength(1)
    // La no agrupada conserva su enlace y nada más.
    expect(screen.getByRole('link', { name: /Abrir en Agenda/ })).toBeInTheDocument()
  })

  it('«Lo estoy atendiendo» asienta reconocer SIN fecha y el foco aterriza en el contador', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    await user.click(screen.getByRole('button', { name: 'Reconocer «2 leads esperando reparto»: la estoy atendiendo' }))

    expect(reconocer).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'grupo:por_repartir:s1' }),
      'reconocer',
      null,
    )
    // El botón desaparece con el asiento: el foco no puede quedar huérfano.
    await waitFor(() => expect(document.getElementById('alertas-contador')).toHaveFocus())
  })

  it('Posponer abre los tres plazos y «Mañana» manda un hasta futuro de un día', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    await user.click(screen.getByRole('button', { name: 'Posponer «2 leads esperando reparto»' }))
    const plazos = screen.getByRole('group', { name: 'Posponer «2 leads esperando reparto» hasta' })
    expect(within(plazos).getByRole('button', { name: 'En 3 días' })).toBeVisible()
    expect(within(plazos).getByRole('button', { name: 'En 7 días' })).toBeVisible()

    const antes = Date.now()
    await user.click(within(plazos).getByRole('button', { name: 'Mañana' }))
    const llamada = reconocer.mock.calls[0]
    expect(llamada?.[1]).toBe('posponer')
    const hasta = Date.parse(String(llamada?.[2]))
    expect(hasta - antes).toBeGreaterThan(23.9 * 3_600_000)
    expect(hasta - antes).toBeLessThanOrEqual(24 * 3_600_000 + 1_000)
  })

  it('«En 7 días» va con colchón BAJO el tope del servidor (jamás lo roza)', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    await user.click(screen.getByRole('button', { name: /^Posponer/ }))
    const antes = Date.now()
    await user.click(screen.getByRole('button', { name: 'En 7 días' }))
    const hasta = Date.parse(String(reconocer.mock.calls[0]?.[2]))
    // Estrictamente por debajo de 7 días: el trigger mide con SU reloj.
    expect(hasta - antes).toBeLessThan(7 * 86_400_000)
    expect(hasta - antes).toBeGreaterThan(7 * 86_400_000 - 2_100_000)
  })

  it('Cancelar cierra los plazos sin asentar nada', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    await user.click(screen.getByRole('button', { name: /^Posponer/ }))
    await user.click(screen.getByRole('button', { name: 'Cancelar posposición' }))

    expect(reconocer).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: /la estoy atendiendo/ })).toBeVisible()
  })

  it('la fila reconocida se ATENÚA: badge gris, traza completa, sin botones — y el contador la separa', () => {
    montar({
      rol: 'supervisor',
      alertas: [
        grupo({
          id: 'grupo:tarea_vencida:s1',
          titulo: '1 lead con plazo vencido desde ayer',
          severidad: 'critica',
          reconocimiento: {
            accion: 'reconocer',
            creadoEn: new Date(AHORA).toISOString(),
            venceEn: AHORA + 6 * 86_400_000,
          },
        }),
        grupo(),
      ],
    })

    expect(screen.getByText('Reconocida')).toBeVisible()
    expect(screen.getByText(/La estás atendiendo · reaparece si empeora · se reactiva el/)).toBeVisible()
    // La reconocida NO vuelve a ofrecer botones; la activa sí.
    expect(screen.getAllByRole('button', { name: /la estoy atendiendo/ })).toHaveLength(1)
    // El contador dice la verdad de la campana con palabras.
    expect(screen.getByRole('status')).toHaveTextContent('1 pendiente activo · 1 reconocida')
  })

  it('un fallo al asentar SE DICE, los botones se quedan y el foco se RESCATA', async () => {
    const { toast } = await import('sonner')
    reconocer.mockRejectedValueOnce(new Error('red caída'))
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    const boton = screen.getByRole('button', { name: /la estoy atendiendo/ })
    await user.click(boton)

    await waitFor(() => expect(toast.error).toHaveBeenCalledWith('No se pudo asentar el reconocimiento.'))
    expect(boton).toBeEnabled()
    // Rescate por efecto (lección F2: en el finally el botón aún está disabled).
    await waitFor(() => expect(boton).toHaveFocus())
  })

  it('a11y F4: Posponer es un disclosure REAL — persiste, foco al primer plazo al abrir y de vuelta al cerrar', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    const posponer = screen.getByRole('button', { name: 'Posponer «2 leads esperando reparto»' })
    expect(posponer).toHaveAttribute('aria-expanded', 'false')
    await user.click(posponer)
    expect(posponer).toHaveAttribute('aria-expanded', 'true')
    // El botón NO desaparece al expandirse (bloqueante del revisor a11y) y
    // el foco entra al grupo que controla.
    await waitFor(() => expect(screen.getByRole('button', { name: 'Mañana' })).toHaveFocus())

    await user.click(screen.getByRole('button', { name: 'Cancelar posposición' }))
    expect(
      screen.queryByRole('group', { name: 'Posponer «2 leads esperando reparto» hasta' }),
    ).not.toBeInTheDocument()
    await waitFor(() => expect(posponer).toHaveFocus())
  })

  it('a11y F4: un fallo al posponer deja los plazos ABIERTOS para reintentar donde estaba', async () => {
    reconocer.mockRejectedValueOnce(new Error('red caída'))
    const user = userEvent.setup()
    montar({ rol: 'supervisor', alertas: [grupo()] })

    await user.click(screen.getByRole('button', { name: /^Posponer/ }))
    await user.click(screen.getByRole('button', { name: 'Mañana' }))

    await waitFor(() => expect(screen.getByRole('button', { name: 'Mañana' })).toBeEnabled())
    expect(screen.getByRole('group', { name: 'Posponer «2 leads esperando reparto» hasta' })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: 'Mañana' })).toHaveFocus())
  })
})
