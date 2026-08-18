import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { AlertaCRM } from '@/lib/alertas'
import type { EstadoAlertasCRM } from '@/lib/alertas-context'
import type { Rol } from '@/lib/roles'

const reintentar = vi.fn()
let ESTADO: EstadoAlertasCRM = {
  alertas: [],
  rol: 'vendedor',
  cargando: false,
  errores: [],
  generadoEn: '2026-08-06T17:35:00.000Z',
  reintentar,
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
    responsable: 'Ana Vendedora',
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
}: {
  rol?: Rol
  alertas?: AlertaCRM[]
  cargando?: boolean
  errores?: string[]
} = {}) {
  reintentar.mockReset()
  ESTADO = {
    alertas,
    rol,
    cargando,
    errores,
    generadoEn: '2026-08-06T17:35:00.000Z',
    reintentar,
  }
  return render(<Alertas />)
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
    expect(screen.getByText('Responsable: Ana Vendedora')).toBeVisible()
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
          titulo: 'Vendedor con leads sin próxima acción',
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
    expect(screen.getByRole('heading', { name: 'Vendedor con leads sin próxima acción' })).toBeVisible()
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
    ESTADO = {
      alertas,
      rol: 'vendedor',
      cargando: false,
      errores: [],
      generadoEn: '2026-08-06T17:35:00.000Z',
      reintentar,
    }
    render(
      <QueryClientProvider client={clienteConsultas}>
        <PanelActionsContext.Provider value={actions}>
          <Alertas />
        </PanelActionsContext.Provider>
      </QueryClientProvider>,
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
