import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ColaSlaPanel, DetalleSla, SlaOperacionBoundary } from './sla-operacion'
import { CrmApiError } from '@/data/crm-api'
import { fechaSla, puedeRegistrarGestionSla, type ColaDiaPagina, type EstadoSlaV2 } from '@/lib/sla-operacion'
import { useColaDiaPagina, useModoSla } from '@/data/sla-operacion-queries'
const abrir = vi.fn()
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'actor', rol: 'supervisor', demo: false } }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true, equipo: [
    { perfil_id: 'analista', nombre_completo: 'Analista Uno', rol_crm: 'vendedor', activo: true },
    { perfil_id: 'supervisor', nombre_completo: 'Supervisor del Equipo', rol_crm: 'supervisor', activo: true },
    { perfil_id: 'gerencia', nombre_completo: 'Gerente Comercial', rol_crm: 'gerencia', activo: true },
    { perfil_id: 'inactivo', nombre_completo: 'Analista Inactivo', rol_crm: 'vendedor', activo: false },
  ] }),
  usePanelesActions: () => ({ abrirLead: abrir }),
}))
vi.mock('@/data/sla-operacion-queries', () => ({
  slaOperacionKeys: { raiz: () => ['crm', 'metricas-ambito', 'sla-v2'] },
  useColaDiaPagina: vi.fn(), useModoSla: vi.fn(), useEstadosSlaV2: vi.fn(),
}))
const consulta = vi.mocked(useColaDiaPagina)
const modo = vi.mocked(useModoSla)
const estado: EstadoSlaV2 = {
  lead_id: 'l1', avisos: [], evaluacion: 'completa', motivos_datos: [],
  seguimiento: { referencia_en: null, ultima_gestion_en: null, limite_en: '2026-09-07T10:00:00Z', vencido: true, accion_pendiente: true },
  compromiso: { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
  etapa: { limite_original_en: '2026-09-07T10:00:00Z', limite_prorrogado_en: '2026-09-07T10:00:00Z', limite_operativo_en: '2026-09-07T10:00:00Z', techo_en: '2026-09-09T10:00:00Z', prorrogas_usadas: 0, prorrogas_restantes: 2, revision_requerida: true, motivos_revision: ['limite_operativo_agotado'] },
}
const primera: ColaDiaPagina = {
  version: 3, modo: 'activo', control_revision: 1, calculado_en: '2026-09-07T10:00:00Z', filtros: { senal: 'todas', etapa: null, analista_id: null },
  limite: 10, total_items: 455, hay_mas: true, rango: { desde: 1, hasta: 10 }, cursor_siguiente: { token: 'pagina2' },
  totales: { pendientes: 455, primera_atencion: 527, tareas_vencidas: 538, seguimientos_pendientes: 527, revisiones: 455, datos_incompletos: 0, por_repartir: 3, clientes: 0 },
  items: [{ clave: 'lead:l1', sujeto: { tipo: 'lead', id: 'l1', nombre: 'Oportunidad Uno' }, lead_id: 'l1', bucket: 'primera_atencion', severidad: 'critica', prioridad: 10, referencia_en: '2026-09-07T10:00:00Z', tarea_id: null,
    lead: { id: 'l1', nombre_completo: 'Oportunidad Uno', etapa: 'contactado', analista_id: 'analista', analista_nombre: 'Analista Uno' },
    senales: { pendientes: true, primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: true, revisiones: true, datos_incompletos: false, por_repartir: false }, estado }],
}
const segunda: ColaDiaPagina = { ...primera, rango: { desde: 11, hasta: 11 }, hay_mas: false, cursor_siguiente: null, items: [{ ...(primera.items[0] as Extract<ColaDiaPagina['items'][number], { lead_id: string }>), clave: 'lead:l2', sujeto: { tipo: 'lead', id: 'l2', nombre: 'Oportunidad Dos' }, lead_id: 'l2', lead: { ...(primera.items[0] as Extract<ColaDiaPagina['items'][number], { lead_id: string }>).lead, id: 'l2', nombre_completo: 'Oportunidad Dos' } }] }
function resultado(data: ColaDiaPagina | undefined, error: Error | null = null, isFetching = false) {
  return { data, error, isFetching, refetch: vi.fn() } as unknown as ReturnType<typeof useColaDiaPagina>
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
      { senal: 'pendientes', etapa: null, analista_id: null }, null, 25,
    ])
    expect(screen.getByRole('combobox', { name: 'Mostrar' })).toHaveValue('pendientes')
    expect(screen.getByRole('combobox', { name: 'Etapa' })).toHaveValue('')
    expect(screen.getByRole('combobox', { name: 'Analista' })).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Para atender ahora' })).toHaveAttribute('aria-pressed', 'true')
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
    expect(within(lista).getByText('Contactar al cliente')).toBeInTheDocument()
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
  it('una actividad vencida y una revisión se muestran sin explicar la cobertura', async () => {
    const actuar = vi.fn()
    const tarea = { id: 'av-tarea', bucket: 'tarea_vencida' as const, severidad: 'critica' as const, referencia_en: '2026-09-07T10:00:00Z', tarea_id: 't1' }
    montar(<DetalleSla supervision onActuar={actuar} estado={{ ...estado,
      avisos: [tarea, { ...tarea, id: 'av-revision', bucket: 'revision_comercial', tarea_id: null }],
      seguimiento: { ...estado.seguimiento, accion_pendiente: false },
      compromiso: { tarea: { id: 't1', tipo: 'llamada', vence_en: '2026-09-07T10:00:00Z', reprogramaciones: 0 }, validez: 'valido', cobertura_activa: true, hasta_en: '2026-09-08T10:00:00Z' },
    }} />)
    expect(screen.getByText('Revisa la actividad pendiente')).toBeVisible()
    expect(screen.getByText('Revisa el caso y define el siguiente paso')).toBeVisible()
    expect(screen.queryByText(/En espera por/)).not.toBeInTheDocument()
    expect(screen.getByText('Plazo actual de etapa')).not.toBeVisible()
    await userEvent.click(screen.getByRole('button', { name: 'Revisar actividad' }))
    expect(actuar).toHaveBeenCalledWith(tarea)
    await userEvent.click(screen.getByText('Ver plazos'))
    expect(screen.getByText('Plazo actual de etapa')).toBeVisible()
    expect(screen.getByText('Retomar seguimiento desde')).toBeVisible()
  })
  it('sin avisos solo ofrece Ver plazos, y el analista no ve el tope de ampliaciones', async () => {
    montar(<DetalleSla estado={estado} />)
    expect(screen.queryByRole('list', { name: 'Acciones pendientes' })).not.toBeInTheDocument()
    expect(screen.getByText('Ver plazos')).toBeVisible()
    expect(screen.queryByText('Tope para ampliaciones')).not.toBeInTheDocument()
    expect(screen.getByText('Fechas y horas de Lima.')).not.toBeVisible()
    await userEvent.click(screen.getByText('Ver plazos'))
    expect(screen.getByText('Fechas y horas de Lima.')).toBeVisible()
  })
  it('los datos sin confirmar piden una revisión sin inventar fechas', async () => {
    montar(<DetalleSla estado={{ ...estado, evaluacion: 'parcial',
      avisos: [{ id: 'datos', bucket: 'datos_incompletos', severidad: 'media', referencia_en: null, tarea_id: null }],
      seguimiento: { ...estado.seguimiento, limite_en: null, vencido: null, accion_pendiente: null },
    }} />)
    expect(screen.getByText('Pide al supervisor revisar los datos')).toBeVisible()
    await userEvent.click(screen.getByText('Ver plazos'))
    expect(screen.getByText('Sin fecha confirmada')).toBeVisible()
  })
})

describe('modelo de acción principal y perspectiva autorizada', () => {
  const tarea = { id: 'av-tarea', bucket: 'tarea_vencida' as const, severidad: 'critica' as const, referencia_en: '2026-09-07T15:00Z', tarea_id: 'tarea-real' }
  const inicial = { ...tarea, id: 'av-inicial', bucket: 'primera_atencion' as const, tarea_id: null }
  const revision = { ...tarea, id: 'av-revision', bucket: 'revision_comercial' as const, tarea_id: null }
  const programada = { id: 'tarea-real', tipo: 'llamada', titulo: 'Próximo intento', vence_en: '2026-09-08T15:00Z' }
  const estadoNuevo: EstadoSlaV2 = { ...estado, operacion: { modelo: 3, aviso_principal: tarea, proxima_accion: programada, proximo_cambio_en: programada.vence_en }, avisos: [inicial, tarea], avisos_mostrados: [tarea] }
  it('dirige a la tarea vencida y conserva una sola orden aunque haya primera gestión pendiente', async () => {
    const actuar = vi.fn(); const usuario = userEvent.setup()
    render(<DetalleSla estado={estadoNuevo} onActuar={actuar} />)
    expect(screen.getAllByRole('listitem')).toHaveLength(1)
    expect(screen.queryByText(/Realiza el primer intento/)).not.toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: /Revisar actividad/ }))
    expect(actuar).toHaveBeenCalledWith(tarea)
  })
  it('permite la revisión independiente que autorizó el servidor para supervisión', () => {
    render(<DetalleSla estado={{ ...estadoNuevo, avisos: [inicial, tarea, revision], avisos_mostrados: [tarea, revision] }} supervision />)
    expect(screen.getAllByRole('listitem')).toHaveLength(2)
    expect(screen.getByText('Se venció el plazo de esta etapa')).toBeInTheDocument()
  })
  it('supervisión conserva los avisos de gestión como información, sin botón para registrar actividad', () => {
    const actuar = vi.fn()
    const seguimiento = { ...inicial, id: 'av-seguimiento', bucket: 'seguimiento' as const }
    render(<DetalleSla estado={{ ...estado, avisos: [inicial, seguimiento] }} supervision onActuar={actuar} />)

    expect(screen.getByText('Revisa el contacto inicial con el cliente')).toBeVisible()
    expect(screen.getByText('Revisa el seguimiento con el analista')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Registrar gestión' })).not.toBeInTheDocument()
    expect(actuar).not.toHaveBeenCalled()
  })
  it('el analista conserva Registrar gestión y el aviso llega al callback', async () => {
    const actuar = vi.fn(); const usuario = userEvent.setup()
    const seguimiento = { ...inicial, id: 'av-seguimiento', bucket: 'seguimiento' as const }
    render(<DetalleSla estado={{ ...estado, avisos: [seguimiento] }} onActuar={actuar} />)

    await usuario.click(screen.getByRole('button', { name: 'Registrar gestión' }))
    expect(actuar).toHaveBeenCalledWith(seguimiento)
  })
  it('solo el rol analista puede registrar una gestión SLA desde la ficha', () => {
    expect(puedeRegistrarGestionSla('vendedor')).toBe(true)
    expect(puedeRegistrarGestionSla('supervisor')).toBe(false)
    expect(puedeRegistrarGestionSla('gerencia')).toBe(false)
    expect(puedeRegistrarGestionSla('directorio')).toBe(false)
    expect(puedeRegistrarGestionSla('coordinador')).toBe(false)
    expect(puedeRegistrarGestionSla(undefined)).toBe(false)
  })
  it('no anticipa contacto por cobertura agotada cuando el servidor indicó próxima acción', () => {
    render(<DetalleSla estado={{ ...estadoNuevo, avisos: [], avisos_mostrados: [], operacion: { ...estadoNuevo.operacion!, aviso_principal: null } }} />)
    expect(screen.queryByRole('list', { name: 'Acciones pendientes' })).not.toBeInTheDocument()
    expect(screen.queryByText(/Retomar seguimiento desde|Próxima gestión: límite/)).not.toBeInTheDocument()
    expect(screen.getByText(fechaSla(programada.vence_en))).toBeInTheDocument()
  })
  it('usa el significado nuevo solo cuando lo confirma el servidor', async () => {
    consulta.mockImplementation(() => resultado({ ...primera, modelo_avisos: 3 }))
    montar()
    expect(screen.getByRole('button', { name: 'Primera gestión pendiente 527' })).toBeInTheDocument()
    expect(screen.getByText('Realizar la primera gestión')).toBeInTheDocument()
  })
})

it('reinicia automáticamente la página cuando el servidor invalida su posición', async () => {
  const usuario = userEvent.setup()
  consulta.mockImplementation((_filtros, cursor) => cursor
    ? resultado(undefined, new CrmApiError('Cursor incompatible', '22023')) : resultado(primera))
  montar()
  await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
  expect(consulta.mock.lastCall?.[1]).toBeNull()
  expect(screen.getByText('Oportunidad Uno')).toBeInTheDocument()
})

// Cola v3 (F3, 29/09/2026): las tareas de CLIENTES del día entran en el
// «Seguimiento comercial». Sin lead, etapa ni analista: la fila dice qué es y
// cuándo, y ENLAZA a la ficha de «Mi cartera» solo si el cliente tiene una.
describe('cola SLA v3: tareas de clientes', () => {
  const INV = 'dddddddd-0000-4000-8000-0000000000a1'
  const senalesCliente = (vencida: boolean) => ({ pendientes: vencida, tareas_vencidas: vencida, primera_atencion: false,
    seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false })
  const cliente = (tarea: string, bucket: 'tarea_vencida' | 'tarea_hoy', sujeto: { perfil_id: string | null; inversionista_id: string | null; nombre: string }) => ({
    clave: `tarea:${tarea}`, tarea_id: tarea, lead_id: null, lead: null, estado: null, bucket,
    severidad: bucket === 'tarea_vencida' ? 'critica' as const : 'media' as const, prioridad: bucket === 'tarea_vencida' ? 20 as const : 30 as const,
    referencia_en: '2026-09-07T15:00:00Z', senales: senalesCliente(bucket === 'tarea_vencida'), sujeto: { tipo: 'cliente' as const, ...sujeto },
  })
  const rosa = cliente('t-inv', 'tarea_vencida', { perfil_id: null, inversionista_id: INV, nombre: 'Rosa Cliente' })
  const portal = cliente('t-portal', 'tarea_hoy', { perfil_id: 'p-1', inversionista_id: null, nombre: 'Luis Portal' })
  // Como el SERVIDOR: con «Para atender ahora» solo entra la vencida; la de hoy, en «Todas».
  // `totales.clientes` cuenta TODAS las del ámbito (3), sin la señal elegida.
  const paginaDe = (senal: string): ColaDiaPagina => {
    const clientes = senal === 'todas' ? [rosa, portal] : [rosa]
    return { ...primera, hay_mas: false, cursor_siguiente: null, total_items: 1 + clientes.length, rango: { desde: 1, hasta: 1 + clientes.length },
      filtros: { senal, etapa: null, analista_id: null }, totales: { ...primera.totales, clientes: 3 }, items: [primera.items[0]!, ...clientes] }
  }
  beforeEach(() => {
    consulta.mockImplementation((filtros) => resultado(paginaDe(filtros.senal)))
  })

  it('ESTADO DE PRODUCCIÓN: pinta la tarea del cliente sin fingir analista ni etapa, y cuenta las de ESTA página (no totales.clientes)', () => {
    montar()
    const lista = screen.getByRole('list', { name: 'Oportunidades de esta página' })
    const fila = within(lista).getByRole('link', { name: /Rosa Cliente/ })
    expect(fila).toHaveTextContent('Cliente de la cartera')
    expect(fila).toHaveTextContent('Gestión con cliente vencida')
    expect(fila).toHaveTextContent('Ver en Mi cartera')
    expect(fila).not.toHaveTextContent('Sin analista')
    expect(screen.getByRole('status')).toHaveTextContent('1 gestión con un cliente en esta página')
    expect(screen.getByRole('status')).not.toHaveTextContent('3')
  })

  it('enlaza a la ficha del cliente con el id que trae la cola (fresco), no a la de un lead', () => {
    montar()
    const fila = within(screen.getByRole('list', { name: 'Oportunidades de esta página' })).getByRole('link', { name: /Rosa Cliente/ })
    expect(fila).toHaveAttribute('href', `#/mi-cartera/inversionista/${INV}`)
    expect(abrir).not.toHaveBeenCalled()
  })

  it('una página calculada con OTRA revisión de reglas (caché) no se pinta mientras llega la vigente', () => {
    consulta.mockImplementation((filtros) => resultado({ ...paginaDe(filtros.senal), control_revision: 2 }))
    montar()
    expect(screen.queryByRole('list', { name: 'Oportunidades de esta página' })).toBeNull()
    expect(screen.getByText('Cargando oportunidades…')).toBeInTheDocument()
  })

  it('un cliente solo del portal (en «Todas») se lee, dice por qué no se abre y no ofrece una ficha que no existe', async () => {
    const usuario = userEvent.setup(); montar()
    expect(screen.queryByText('Luis Portal')).toBeNull()
    await usuario.click(screen.getByRole('button', { name: /Todas las acciones/ }))
    const lista = screen.getByRole('list', { name: 'Oportunidades de esta página' })
    expect(within(lista).queryByRole('link', { name: /Luis Portal/ })).toBeNull()
    expect(within(lista).queryByRole('button', { name: /Luis Portal/ })).toBeNull()
    const fila = within(lista).getByText('Luis Portal').closest('li')!
    expect(fila).toHaveTextContent('Cliente del portal')
    expect(fila).toHaveTextContent('Sin ficha en la cartera')
    expect(fila).toHaveTextContent('Gestión con cliente para hoy')
    expect(screen.getByRole('status')).toHaveTextContent('2 gestiones con clientes en esta página')
  })
})
