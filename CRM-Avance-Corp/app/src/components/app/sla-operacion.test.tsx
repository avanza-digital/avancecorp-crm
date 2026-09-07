import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ColaSlaPanel, DetalleSla, SlaOperacionBoundary } from './sla-operacion'
import { fechaSla, type ColaSlaPagina, type EstadoSlaV2 } from '@/lib/sla-operacion'
import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
const abrir = vi.fn()
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'actor', rol: 'supervisor', demo: false } }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ equipo: [
    { perfil_id: 'analista', nombre_completo: 'Analista Uno', rol_crm: 'vendedor', activo: true },
    { perfil_id: 'supervisor', nombre_completo: 'Supervisor del Equipo', rol_crm: 'supervisor', activo: true },
    { perfil_id: 'gerencia', nombre_completo: 'Gerente Comercial', rol_crm: 'gerencia', activo: true },
    { perfil_id: 'inactivo', nombre_completo: 'Analista Inactivo', rol_crm: 'vendedor', activo: false },
  ] }),
  usePanelesActions: () => ({ abrirLead: abrir }),
}))
vi.mock('@/data/sla-operacion-queries', () => ({
  slaOperacionKeys: { raiz: () => ['crm', 'metricas-ambito', 'sla-v2'] },
  useColaSlaPagina: vi.fn(), useModoSla: vi.fn(), useEstadosSlaV2: vi.fn(),
}))
const consulta = vi.mocked(useColaSlaPagina)
const modo = vi.mocked(useModoSla)
const estado: EstadoSlaV2 = {
  lead_id: 'l1', evaluacion: 'completa', motivos_datos: [],
  seguimiento: { referencia_en: null, ultima_gestion_en: null, limite_en: '2026-09-07T10:00:00Z', vencido: true, accion_pendiente: true },
  compromiso: { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
  etapa: { limite_original_en: '2026-09-07T10:00:00Z', limite_prorrogado_en: '2026-09-07T10:00:00Z', limite_operativo_en: '2026-09-07T10:00:00Z', techo_en: '2026-09-09T10:00:00Z', prorrogas_usadas: 0, prorrogas_restantes: 2, revision_requerida: true, motivos_revision: ['limite_operativo_agotado'] },
}
const primera: ColaSlaPagina = {
  version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-07T10:00:00Z', filtros: { senal: 'todas', etapa: null, analista_id: null },
  limite: 10, total_items: 455, hay_mas: true, rango: { desde: 1, hasta: 10 }, cursor_siguiente: { token: 'pagina2' },
  totales: { primera_atencion: 527, tareas_vencidas: 538, seguimientos_pendientes: 527, revisiones: 455, datos_incompletos: 0, por_repartir: 3 },
  items: [{ lead_id: 'l1', bucket: 'primera_atencion', severidad: 'critica', prioridad: 10, referencia_en: '2026-09-07T10:00:00Z', tarea_id: null,
    lead: { id: 'l1', nombre_completo: 'Oportunidad Uno', etapa: 'contactado', analista_id: 'analista', analista_nombre: 'Analista Uno' },
    senales: { primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: true, revisiones: true, datos_incompletos: false, por_repartir: false }, estado }],
}
const segunda: ColaSlaPagina = { ...primera, rango: { desde: 11, hasta: 11 }, hay_mas: false, cursor_siguiente: null, items: [{ ...primera.items[0]!, lead_id: 'l2', lead: { ...primera.items[0]!.lead, id: 'l2', nombre_completo: 'Oportunidad Dos' } }] }
function resultado(data: ColaSlaPagina | undefined, error: Error | null = null, isFetching = false) {
  return { data, error, isFetching, refetch: vi.fn() } as unknown as ReturnType<typeof useColaSlaPagina>
}
function montar(elemento = <ColaSlaPanel />) {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return { ...render(<QueryClientProvider client={cliente}>{elemento}</QueryClientProvider>), cliente }
}
beforeEach(() => {
  vi.clearAllMocks()
  abrir.mockReset().mockResolvedValue(true)
  consulta.mockImplementation((_filtros, cursor) => resultado(cursor ? segunda : primera))
  modo.mockReturnValue({ legado: false, activo: true, error: null, data: { control_revision: 1 } } as ReturnType<typeof useModoSla>)
})
describe('cola SLA con páginas explícitas', () => {
  it('reemplaza las filas al avanzar y recupera la anterior sin acumular scroll', async () => {
    const usuario = userEvent.setup(); montar()
    expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    expect(screen.getByText(/1–10 de 455/)).toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    expect(screen.queryByText('Oportunidad Uno')).not.toBeInTheDocument()
    expect(screen.getByText('Oportunidad Dos')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Siguiente' })).toBeDisabled()
    await usuario.click(screen.getByRole('button', { name: 'Anterior' }))
    expect(screen.getByText('Oportunidad Uno')).toBeInTheDocument()
    expect(screen.queryByText('Oportunidad Dos')).not.toBeInTheDocument()
  })
  it('cada filtro y el tamaño de página vuelven al primer cursor', async () => {
    const usuario = userEvent.setup(); montar()
    for (const [campo, valor] of [['Mostrar', 'revisiones'], ['Etapa', 'contactado'], ['Analista', 'analista'], ['Por página', '25']] as const) {
      await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
      await usuario.selectOptions(screen.getByRole('combobox', { name: campo }), valor!)
      expect(consulta.mock.lastCall?.[1]).toBeNull()
      expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    }
    expect(consulta.mock.lastCall?.[0]).toEqual({ senal: 'revisiones', etapa: 'contactado', analista_id: 'analista' })
    expect(consulta.mock.lastCall?.[2]).toBe(25)
  })
  it('una prioridad de escritorio selecciona la misma señal móvil y reinicia el cursor', async () => {
    const usuario = userEvent.setup(); montar()
    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    expect(consulta.mock.lastCall?.[1]).toEqual(primera.cursor_siguiente)
    const prioridades = screen.getByRole('group', { name: 'Prioridades de seguimiento' })
    const revision = within(prioridades).getByRole('button', { name: 'Revisión comercial 455' })
    expect(revision).toHaveAttribute('aria-pressed', 'false')

    await usuario.click(revision)

    expect(consulta.mock.lastCall?.[0]).toEqual({ senal: 'revisiones', etapa: null, analista_id: null })
    expect(consulta.mock.lastCall?.[1]).toBeNull()
    expect(revision).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Todas las acciones' })).toHaveAttribute('aria-pressed', 'false')
    expect(screen.getByRole('combobox', { name: 'Mostrar' })).toHaveValue('revisiones')
    expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    expect(screen.getByText('Oportunidad Uno')).toBeInTheDocument()
    expect(screen.queryByText('Oportunidad Dos')).not.toBeInTheDocument()
  })
  it('Limpiar filtros elimina señal, etapa y analista, y vuelve a la primera página', async () => {
    const usuario = userEvent.setup(); montar()
    await usuario.selectOptions(screen.getByRole('combobox', { name: 'Mostrar' }), 'revisiones')
    await usuario.selectOptions(screen.getByRole('combobox', { name: 'Etapa' }), 'contactado')
    await usuario.selectOptions(screen.getByRole('combobox', { name: 'Analista' }), 'analista')
    await usuario.selectOptions(screen.getByRole('combobox', { name: 'Por página' }), '25')
    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))

    await usuario.click(screen.getByRole('button', { name: 'Limpiar filtros' }))

    expect(consulta.mock.lastCall?.slice(0, 3)).toEqual([
      { senal: 'todas', etapa: null, analista_id: null }, null, 25,
    ])
    expect(screen.getByRole('combobox', { name: 'Mostrar' })).toHaveValue('todas')
    expect(screen.getByRole('combobox', { name: 'Etapa' })).toHaveValue('')
    expect(screen.getByRole('combobox', { name: 'Analista' })).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Todas las acciones' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Limpiar filtros' })).not.toBeInTheDocument()
  })
  it('conserva los conteos solapados del servidor y el total único de la lista filtrada', async () => {
    consulta.mockImplementation((filtros) => resultado({
      ...primera, filtros,
      // Una oportunidad puede tener más de una señal. Al filtrar por señal,
      // cambia la población de la lista, pero no se suman las otras tarjetas.
      total_items: filtros.senal === 'revisiones' ? 455 : 815,
    }))
    const usuario = userEvent.setup(); montar()
    const prioridades = screen.getByRole('group', { name: 'Prioridades de seguimiento' })
    expect(within(prioridades).getByRole('button', { name: 'Primera atención 527' })).toBeInTheDocument()
    expect(within(prioridades).getByRole('button', { name: 'Tareas vencidas 538' })).toBeInTheDocument()
    expect(within(prioridades).getByRole('button', { name: 'Seguimiento pendiente 527' })).toBeInTheDocument()
    expect(within(prioridades).getByRole('button', { name: 'Revisión comercial 455' })).toBeInTheDocument()
    expect(screen.getByText(/1–10 de 815 oportunidades/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Todas las acciones' })).toHaveTextContent(/^Todas las acciones$/)

    await usuario.click(within(prioridades).getByRole('button', { name: 'Revisión comercial 455' }))

    expect(screen.getByText(/1–10 de 455 oportunidades/)).toBeInTheDocument()
    expect(within(prioridades).getByRole('button', { name: 'Tareas vencidas 538' })).toBeInTheDocument()
    expect(screen.queryByText(/de 2[.,]?050 oportunidades/)).not.toBeInTheDocument()
    expect(screen.getByText(/Una oportunidad puede tener varios pendientes/)).toBeInTheDocument()
  })
  it('muestra la revisión aunque primera atención tenga prioridad y usa totales completos', async () => {
    const usuario = userEvent.setup(); montar()
    const lista = screen.getByRole('list', { name: 'Oportunidades de esta página' })
    expect(within(lista).getByText('Primera atención')).toBeInTheDocument()
    expect(within(lista).getByText('Revisión comercial')).toBeInTheDocument()
    expect(within(lista).getByText('Analista Uno')).toBeInTheDocument()
    expect(within(lista).getByText('Contactado')).toBeInTheDocument()
    expect(within(lista).getByText('Referencia')).toBeInTheDocument()
    expect(within(lista).getByText(fechaSla(primera.items[0]!.referencia_en))).toBeInTheDocument()
    expect(within(lista).getByText('Abrir ficha')).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Revisión comercial (455)' })).toBeInTheDocument()
    await usuario.click(within(lista).getByRole('button'))
    expect(abrir).toHaveBeenCalledWith('l1')
  })
  it('no conserva filas antiguas ni afirma al día cuando falla un refetch', () => {
    consulta.mockReturnValue(resultado(primera, new Error('Conexión')))
    montar()
    expect(screen.getByRole('alert')).toHaveTextContent('pendientes todavía no están confirmados')
    expect(screen.queryByText('Oportunidad Uno')).not.toBeInTheDocument()
    expect(screen.queryByText(/de 455/)).not.toBeInTheDocument()
    expect(screen.queryByRole('option', { name: 'Revisión comercial (455)' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Revisión comercial.*455/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/No hay oportunidades con estos filtros/)).not.toBeInTheDocument()
  })

  it('el filtro Analista ofrece solo vendedores activos del roster autorizado', () => {
    montar()
    const filtro = screen.getByRole('combobox', { name: 'Analista' })

    expect(within(filtro).getAllByRole('option').map((opcion) => opcion.textContent)).toEqual([
      'Todos los analistas', 'Analista Uno',
    ])
    expect(within(filtro).queryByRole('option', { name: 'Supervisor del Equipo' })).not.toBeInTheDocument()
    expect(within(filtro).queryByRole('option', { name: 'Gerente Comercial' })).not.toBeInTheDocument()
    expect(within(filtro).queryByRole('option', { name: 'Analista Inactivo' })).not.toBeInTheDocument()
  })

  it('muestra la apertura pendiente, evita duplicar la petición y hace visible un resultado false', async () => {
    let terminar!: (abierta: boolean) => void
    abrir.mockReturnValueOnce(new Promise<boolean>((resolve) => { terminar = resolve }))
    const usuario = userEvent.setup(); montar()
    const lista = screen.getByRole('list', { name: 'Oportunidades de esta página' })
    const ficha = within(lista).getByRole('button')

    await usuario.click(ficha)

    expect(screen.getByText('Abriendo ficha…')).toHaveAttribute('role', 'status')
    expect(ficha).toBeDisabled()
    await usuario.click(ficha)
    expect(abrir).toHaveBeenCalledTimes(1)
    await act(async () => { terminar(false) })

    expect(screen.queryByText('Abriendo ficha…')).not.toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo abrir la ficha')
    expect(ficha).toBeEnabled()
    // Una segunda intención puede recuperarse sin arrastrar el error anterior.
    await usuario.click(ficha)
    expect(abrir).toHaveBeenCalledTimes(2)
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
  it('deshabilita navegación mientras consulta y distingue un filtro vacío', () => {
    consulta.mockReturnValue(resultado({ ...primera, items: [], total_items: 0, rango: { desde: 0, hasta: 0 }, hay_mas: false, cursor_siguiente: null }, null, true))
    montar()
    expect(screen.getByText(/No hay oportunidades con estos filtros/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Siguiente' })).toBeDisabled()
  })
  it('el error del modo nunca cae silenciosamente a reglas antiguas', () => {
    modo.mockReturnValue({ legado: false, activo: false, error: new Error('Modo no disponible'), refetch: vi.fn() } as unknown as ReturnType<typeof useModoSla>)
    montar(<SlaOperacionBoundary legado={<p>Cola antigua</p>}><p>Cola nueva</p></SlaOperacionBoundary>)
    expect(screen.getByRole('alert')).toBeInTheDocument()
    expect(screen.queryByText('Cola antigua')).not.toBeInTheDocument()
    expect(screen.queryByText('Cola nueva')).not.toBeInTheDocument()
  })
  it('la ficha distingue compromiso cubierto y vencimiento de agenda', () => {
    montar(<DetalleSla estado={{ ...estado,
      seguimiento: { ...estado.seguimiento, limite_en: '2026-09-10T10:00:00Z', vencido: false, accion_pendiente: false },
      compromiso: { tarea: { id: 't1', tipo: 'llamada', vence_en: '2026-09-07T10:00:00Z', reprogramaciones: 0 }, validez: 'valido', cobertura_activa: true, hasta_en: '2026-09-08T10:00:00Z' },
      etapa: { ...estado.etapa, motivos_revision: ['reingreso_etapa'] },
    }} />)
    expect(screen.getByText('En espera por una actividad programada')).toBeInTheDocument()
    // La cobertura puede terminar antes del próximo plazo habitual. No lo sustituye.
    expect(screen.getByText(fechaSla('2026-09-10T10:00:00Z', 'completa'))).toBeInTheDocument()
    expect(screen.getByText(fechaSla('2026-09-08T10:00:00Z', 'completa'))).toBeInTheDocument()
    expect(screen.getByText(/La actividad conserva su fecha y hora de Agenda/)).toBeInTheDocument()
    // Esperar por una actividad no elimina una revisión de etapa independiente.
    expect(screen.getByText('Este caso necesita una decisión')).toBeInTheDocument()
    expect(screen.getByText('La oportunidad ingresó a esta etapa tres veces o más en este proceso comercial')).toBeInTheDocument()
    expect(screen.queryByText('Seguimiento vencido')).not.toBeInTheDocument()
  })
  it('los datos sin confirmar no se presentan como permiso de espera rechazado', () => {
    montar(<DetalleSla estado={{ ...estado, evaluacion: 'parcial',
      seguimiento: { ...estado.seguimiento, limite_en: null, vencido: null, accion_pendiente: null },
      compromiso: { tarea: { id: 't1', tipo: 'llamada', vence_en: '2026-09-07T10:00:00Z', reprogramaciones: 0 }, validez: 'datos_incompletos', cobertura_activa: null, hasta_en: null },
      etapa: { ...estado.etapa, revision_requerida: null, motivos_revision: [], prorrogas_usadas: 1, prorrogas_restantes: null },
    }} />)
    expect(screen.getByText('Seguimiento por confirmar')).toBeInTheDocument()
    expect(screen.getByText(/Faltan datos para confirmar si esta actividad permite esperar/)).toBeInTheDocument()
    expect(screen.getByText(/Disponibles: Por confirmar/)).toBeInTheDocument()
    expect(screen.queryByText('Seguimiento vencido')).not.toBeInTheDocument()
    expect(screen.queryByText(/Esta actividad no permite aplazar/)).not.toBeInTheDocument()
  })
})
