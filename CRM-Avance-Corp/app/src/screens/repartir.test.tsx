// Tests de integración de la pantalla "Repartir leads" (C1): carga de cola +
// supervisores, capital PEN/USD SEPARADO, reparto con salida optimista de la
// fila, y los dos rechazos que importan — el veto legal (NO_INSISTA) y la fila
// que ya salió de la cola (FUERA_DE_COLA) — que además fuerzan una relectura.
// Se mockea la capa de datos (sin red).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { StrictMode } from 'react'
import type { AgendaRepartoDiaria, ColaLead, HistorialDerivacion, PanelDistribucionReparto, SupervisorReparto } from '@/lib/tipos'
import type { ReporteDerivacionesCoordinacion } from '@/lib/reporte-derivaciones-coordinacion'
import { payloadValido as payloadConversionValido } from '@/lib/conversion-coordinacion.test'

const toastSuccess = vi.fn()
const toastError = vi.fn()
vi.mock('sonner', () => ({ toast: { success: toastSuccess, error: toastError } }))

const authState = vi.hoisted(() => ({ esAdministrador: false }))
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({
    yo: {
      id: 'actor-reparto',
      nombre_completo: authState.esAdministrador ? 'ADMINISTRADOR' : 'COORDINADORA',
      rol: authState.esAdministrador ? 'gerencia' : 'coordinador',
      rol_portal: authState.esAdministrador ? 'superadmin' : 'comercial',
      demo: false,
      puede_contratar: false,
    },
  }),
}))

let COLA: ColaLead[] = []
let SUPERVISORES: SupervisorReparto[] = []
let HISTORIAL: HistorialDerivacion[] = []
let PANEL: PanelDistribucionReparto = {
  version: 1,
  generado_en: '2026-08-19T10:00:00Z',
  total_leads: 3,
  supervisores: [{ perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', total_leads: 3 }],
  analistas: [{ perfil_id: 'vend-1', nombre: 'ANALISTA UNO', supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', total_leads: 2 }],
}
const repartirMock = vi.fn<(lead: string, sup: string) => Promise<void>>()
const colaMock = vi.fn(async () => COLA)
const supervisoresMock = vi.fn(async () => SUPERVISORES)
const historialMock = vi.fn(async () => HISTORIAL)
const panelMock = vi.fn(async () => PANEL)
const partesHoyLima = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
}).formatToParts(new Date())
const parteHoyLima = (tipo: Intl.DateTimeFormatPartTypes) => (
  partesHoyLima.find((parte) => parte.type === tipo)?.value ?? ''
)
const fechaHoyLima = `${parteHoyLima('year')}-${parteHoyLima('month')}-${parteHoyLima('day')}`
const fechaAyerLima = (() => {
  const fecha = new Date(Date.UTC(
    Number(parteHoyLima('year')),
    Number(parteHoyLima('month')) - 1,
    Number(parteHoyLima('day')) - 1,
  ))
  return fecha.toISOString().slice(0, 10)
})()
let REPORTE_DIARIO: ReporteDerivacionesCoordinacion = {
  version: 1,
  generado_en: '2026-09-04T15:00:00Z',
  periodo: { desde: fechaAyerLima, hasta: fechaAyerLima, dias: 1, zona: 'America/Lima' },
  total_derivados: 3,
  dias: [{
    fecha: fechaAyerLima,
    total_derivados: 3,
    analistas: [{
      analista_id: '00000000-0000-4000-8000-000000000001',
      analista_nombre: 'ANALISTA REPORTE',
      supervisor_id: '00000000-0000-4000-8000-000000000002',
      supervisor_nombre: 'SUPERVISOR REPORTE',
      derivados: 3,
    }],
    entregas: [{
      analista_id: '00000000-0000-4000-8000-000000000001',
      analista_nombre: 'ANALISTA REPORTE',
      supervisor_id: '00000000-0000-4000-8000-000000000002',
      supervisor_nombre: 'SUPERVISOR REPORTE',
      origen: 'landing',
      derivados: 3,
    }],
  }],
}
const reporteDiarioMock = vi.fn(async (_desde: string, _hasta: string) => REPORTE_DIARIO)
const conversionMock = vi.fn(async (consulta: { modo: 'mes'; mes: string } | { modo: 'rango'; desde: string; hasta: string }) => {
  const base = payloadConversionValido()
  if (consulta.modo === 'rango') {
    return { ...base, fuente: { ...base.fuente, modo: 'rango_vivo' as const }, periodo: { modo: 'rango' as const, mes: null, mes_nombre: null, anio: null, zona: 'America/Lima' as const, desde: consulta.desde, hasta: consulta.hasta, dias: 1, cruza_meses_sellados: false } }
  }
  const [anio, mesNum] = consulta.mes.split('-').map(Number) as [number, number]
  const hasta = new Date(Date.UTC(anio, mesNum, 0)).toISOString().slice(0, 10)
  return { ...base, periodo: { ...base.periodo, mes: consulta.mes, desde: `${consulta.mes}-01`, hasta, dias: Number(hasta.slice(8)) } }
})
let AGENDA: AgendaRepartoDiaria = {
  version: 1,
  fecha_desde: fechaHoyLima,
  destinos: [
    { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', alias: 'Supervisora uno' },
    { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', alias: 'Supervisora dos' },
  ],
  dias: [{
    fecha: fechaHoyLima,
    asignaciones: [
      { origen: 'landing', supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', supervisor_alias: 'Supervisora uno', derivados: 0, fuera_turno: 0, entregas: [] },
      { origen: 'formulario', supervisor_id: 'sup-2', supervisor_nombre: 'SUPERVISOR DOS', supervisor_alias: 'Supervisora dos', derivados: 0, fuera_turno: 0, entregas: [] },
    ],
  }],
}
const agendaMock = vi.fn(async () => AGENDA)
const guardarAgendaMock = vi.fn<(fecha: string, landing: string, formulario: string) => Promise<void>>(async () => {})

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real (la pantalla hace instanceof)
    leadsPorRepartir: () => colaMock(),
    supervisoresParaReparto: () => supervisoresMock(),
    repartirLead: (lead: string, sup: string) => repartirMock(lead, sup),
    historialDerivaciones: () => historialMock(),
    panelDistribucionReparto: () => panelMock(),
    listarReporteDerivacionesCoordinacion: (desde: string, hasta: string) => reporteDiarioMock(desde, hasta),
    conversionCoordinacion: (consulta: Parameters<typeof conversionMock>[0]) => conversionMock(consulta),
    agendaRepartoDiaria: () => agendaMock(),
    guardarAgendaRepartoDiaria: (fecha: string, landing: string, formulario: string) => guardarAgendaMock(fecha, landing, formulario),
  }
})

// F1b tanda 3: los tiles ya NO los cuenta la pantalla, se los sirve el RPC. Se
// mockea el hook de fuente con el ESPEJO PURO sobre la misma cola del test —
// números derivados de verdad, sin red ni QueryClientProvider — y con un
// conmutador para el caso «RPC caído».
let RESUMEN_CAIDO = false
const recargarResumenMock = vi.fn(async () => {})

vi.mock('@/data/use-resumen-reparto-operativo', async () => {
  const { resumenRepartoDesdeCola } = await import('@/lib/resumen-reparto')
  return {
    useResumenRepartoOperativo: () => ({
      resumen: RESUMEN_CAIDO ? null : resumenRepartoDesdeCola(COLA, Date.now()),
      cargando: false,
      error: RESUMEN_CAIDO ? new Error('resumen caído') : null,
      recargar: recargarResumenMock,
    }),
  }
})

const { Repartir } = await import('./repartir')
const { CrmApiError } = await import('@/data/crm-api')

it('la agenda termina de cargar al remontar los efectos en StrictMode', async () => {
  render(<StrictMode><Repartir /></StrictMode>)
  expect(await screen.findByLabelText('Asignar Landing a una supervisora')).toBeInTheDocument()
  expect(screen.queryByText('Cargando agenda…')).not.toBeInTheDocument()
})

function lead(over: Partial<ColaLead> = {}): ColaLead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    distrito: 'Miraflores',
    origen: 'landing',
    categoria_interes: 'nuevo',
    monto_estimado: 12000,
    moneda: 'PEN',
    creado_en: new Date().toISOString(),
    ...over,
  }
}

const SUP: SupervisorReparto[] = [
  { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 2 },
  { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
]

beforeEach(() => {
  authState.esAdministrador = false
  COLA = []
  SUPERVISORES = SUP
  HISTORIAL = []
  AGENDA = {
    version: 1,
    fecha_desde: fechaHoyLima,
    destinos: [
      { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', alias: 'Supervisora uno' },
      { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', alias: 'Supervisora dos' },
    ],
    dias: [{
      fecha: fechaHoyLima,
      asignaciones: [
        { origen: 'landing', supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', supervisor_alias: 'Supervisora uno', derivados: 0, fuera_turno: 0, entregas: [] },
        { origen: 'formulario', supervisor_id: 'sup-2', supervisor_nombre: 'SUPERVISOR DOS', supervisor_alias: 'Supervisora dos', derivados: 0, fuera_turno: 0, entregas: [] },
      ],
    }],
  }
  PANEL = {
    version: 1,
    generado_en: '2026-08-19T10:00:00Z',
    total_leads: 3,
    supervisores: [{ perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', total_leads: 3 }],
    analistas: [{ perfil_id: 'vend-1', nombre: 'ANALISTA UNO', supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', total_leads: 2 }],
  }
  REPORTE_DIARIO = {
    version: 1,
    generado_en: '2026-09-04T15:00:00Z',
    periodo: { desde: fechaAyerLima, hasta: fechaAyerLima, dias: 1, zona: 'America/Lima' },
    total_derivados: 3,
    dias: [{
      fecha: fechaAyerLima,
      total_derivados: 3,
      analistas: [{
        analista_id: '00000000-0000-4000-8000-000000000001',
        analista_nombre: 'ANALISTA REPORTE',
        supervisor_id: '00000000-0000-4000-8000-000000000002',
        supervisor_nombre: 'SUPERVISOR REPORTE',
        derivados: 3,
      }],
      entregas: [{
        analista_id: '00000000-0000-4000-8000-000000000001',
        analista_nombre: 'ANALISTA REPORTE',
        supervisor_id: '00000000-0000-4000-8000-000000000002',
        supervisor_nombre: 'SUPERVISOR REPORTE',
        origen: 'landing',
        derivados: 3,
      }],
    }],
  }
  RESUMEN_CAIDO = false
  recargarResumenMock.mockClear()
  repartirMock.mockReset().mockResolvedValue(undefined)
  colaMock.mockClear()
  supervisoresMock.mockClear()
  historialMock.mockClear()
  panelMock.mockClear()
  reporteDiarioMock.mockClear()
  agendaMock.mockClear()
  guardarAgendaMock.mockReset().mockResolvedValue(undefined)
  toastSuccess.mockClear()
  toastError.mockClear()
})

afterEach(() => {
  vi.useRealTimers()
  vi.clearAllMocks()
})

/** El mini-KPI (Card `.ac-lift` del StatStrip) que lleva esa etiqueta. */
function tile(etiqueta: string): HTMLElement {
  const card = screen.getByText(etiqueta).closest('.ac-lift')
  if (!(card instanceof HTMLElement)) throw new Error(`Sin tile para «${etiqueta}»`)
  return card
}

/**
 * Espera el valor YA ASENTADO de un tile. Los KPIs pasan por `AnimatedValue`,
 * que cuenta de 0 al objetivo durante 700 ms con requestAnimationFrame: el
 * timeout por defecto de findBy* (1 s) se queda corto bajo cobertura y el test
 * ve una cifra intermedia. Aquí solo importa el número final.
 */
async function valorDelTile(etiqueta: string, esperado: string): Promise<void> {
  await waitFor(
    () => expect(tile(etiqueta)).toHaveTextContent(esperado),
    { timeout: 4000 },
  )
}

async function abrirCola(usuario = userEvent.setup()): Promise<void> {
  await usuario.click(screen.getByRole('tab', { name: 'Cola de nuevos' }))
}

describe('pantalla Repartir leads', () => {
  it('abre con Coordinación → supervisores y separa la segunda etapa', async () => {
    const usuario = userEvent.setup()
    render(<Repartir />)

    expect(await screen.findByRole('heading', { name: 'Coordinación → supervisores' })).toBeInTheDocument()
    expect(screen.getByText(/No depende de que Supervisión lo reparta después/)).toBeInTheDocument()
    expect(panelMock).not.toHaveBeenCalled()

    await usuario.click(screen.getByRole('tab', { name: 'Supervisión → analistas' }))
    expect(await screen.findByRole('heading', { name: 'Supervisión → analistas' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Cartera activa actual' })).toBeInTheDocument()
    expect(await screen.findByText('Leads por supervisor')).toBeInTheDocument()
    expect(screen.getByText('Leads por analista')).toBeInTheDocument()
    expect(screen.getByText(/Esta foto no reemplaza el historial de entregas/)).toBeInTheDocument()
    expect(panelMock).toHaveBeenCalledTimes(1)
  })

  it('muestra de inmediato el destino real aunque una entrega histórica contradiga el turno', async () => {
    AGENDA = {
      ...AGENDA,
      dias: [{
        fecha: fechaHoyLima,
        asignaciones: [
          {
            origen: 'landing',
            supervisor_id: 'sup-2',
            supervisor_nombre: 'SUPERVISOR DOS',
            supervisor_alias: 'Supervisora dos',
            derivados: 22,
            fuera_turno: 20,
            entregas: [
              { supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', supervisor_alias: 'Supervisora uno', derivados: 20, coincide_turno: false },
              { supervisor_id: 'sup-2', supervisor_nombre: 'SUPERVISOR DOS', supervisor_alias: 'Supervisora dos', derivados: 2, coincide_turno: true },
            ],
          },
          { origen: 'formulario', supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', supervisor_alias: 'Supervisora uno', derivados: 30, fuera_turno: 0, entregas: [] },
        ],
      }],
    }
    AGENDA.dias[0]!.origenes = [{ origen: 'landing', turno: 'landing', derivados: 22, fuera_turno: 20,
      entregas: AGENDA.dias[0]!.asignaciones[0]!.entregas! }]
    render(<Repartir />)
    const tabla = await screen.findByRole('table', { name: 'Entregas por origen y supervisora' })
    expect(within(tabla).getByRole('row', { name: /Supervisora uno 20 20/ })).toBeInTheDocument()
    expect(within(tabla).getByRole('row', { name: /Supervisora dos 2 0/ })).toBeInTheDocument()
    expect(screen.getByText('22 entregados · 20 fuera de turno')).toBeInTheDocument()
  })

  it('muestra a Coordinación el conteo diario por analista y aplica el rango elegido', async () => {
    const usuario = userEvent.setup()
    render(<Repartir />)
    await usuario.click(screen.getByRole('tab', { name: 'Supervisión → analistas' }))

    const tabla = await screen.findByRole('table', { name: 'Entregas por fecha, analista y origen' })
    expect(within(tabla).getByText('ANALISTA REPORTE')).toBeInTheDocument()
    expect(within(tabla).getByText('SUPERVISOR REPORTE')).toBeInTheDocument()
    expect(within(tabla).getByText('LANDING')).toBeInTheDocument()
    expect(within(tabla).getByText('3')).toBeInTheDocument()
    expect(reporteDiarioMock).toHaveBeenCalledWith(fechaAyerLima, fechaAyerLima)

    fireEvent.click(screen.getByRole('button', { name: 'Rango' }))
    fireEvent.change(screen.getByLabelText('Fecha inicial del reporte de derivaciones'), {
      target: { value: '2026-08-01' },
    })
    fireEvent.change(screen.getByLabelText('Fecha final del reporte de derivaciones'), {
      target: { value: '2026-08-10' },
    })

    await waitFor(() => {
      expect(reporteDiarioMock).toHaveBeenCalledWith('2026-08-01', '2026-08-10')
    })
  })

  it('combina supervisor, analista y origen y restablece los filtros del reporte', async () => {
    const SUPERVISOR_DOS = '00000000-0000-4000-8000-000000000003'
    const ANALISTA_DOS = '00000000-0000-4000-8000-000000000004'
    const dia = REPORTE_DIARIO.dias[0]!
    REPORTE_DIARIO = {
      ...REPORTE_DIARIO,
      total_derivados: 7,
      dias: [{
        ...dia,
        total_derivados: 7,
        analistas: [
          { ...dia.analistas[0]!, derivados: 3 },
          {
            analista_id: ANALISTA_DOS,
            analista_nombre: 'BETO REPORTE',
            supervisor_id: SUPERVISOR_DOS,
            supervisor_nombre: 'SUPERVISOR DOS',
            derivados: 4,
          },
        ],
        entregas: [
          { ...dia.entregas[0]!, origen: 'landing', derivados: 2 },
          { ...dia.entregas[0]!, origen: 'referido', derivados: 1 },
          {
            analista_id: ANALISTA_DOS,
            analista_nombre: 'BETO REPORTE',
            supervisor_id: SUPERVISOR_DOS,
            supervisor_nombre: 'SUPERVISOR DOS',
            origen: 'formulario',
            derivados: 4,
          },
        ],
      }],
    }
    const usuario = userEvent.setup()
    render(<Repartir />)
    await usuario.click(screen.getByRole('tab', { name: 'Supervisión → analistas' }))

    const tabla = await screen.findByRole('table', { name: 'Entregas por fecha, analista y origen' })
    const supervisor = screen.getByLabelText('Filtrar entregas por supervisor')
    const analista = screen.getByLabelText('Filtrar entregas por analista')
    const origen = screen.getByLabelText('Filtrar entregas por origen')

    await usuario.selectOptions(supervisor, '00000000-0000-4000-8000-000000000002')
    expect(within(analista).queryByRole('option', { name: 'BETO REPORTE' })).not.toBeInTheDocument()
    await usuario.selectOptions(analista, '00000000-0000-4000-8000-000000000001')
    await usuario.selectOptions(origen, 'landing')

    expect(within(tabla).getByText('ANALISTA REPORTE')).toBeInTheDocument()
    expect(within(tabla).getByText('LANDING')).toBeInTheDocument()
    expect(within(tabla).getByText('2')).toBeInTheDocument()
    expect(within(tabla).queryByText('Referido')).not.toBeInTheDocument()
    expect(within(tabla).queryByText('BETO REPORTE')).not.toBeInTheDocument()

    await usuario.click(screen.getByRole('button', { name: 'Restablecer' }))
    expect(supervisor).toHaveValue('')
    expect(analista).toHaveValue('')
    expect(origen).toHaveValue('')
    expect(within(tabla).getByText('BETO REPORTE')).toBeInTheDocument()
  })

  it('da a Coordinación el historial de distribución sin abrir la ficha del lead', async () => {
    HISTORIAL = [{
      actividad_id: 'hist-1', lead_id: 'lead-1', nombre_completo: 'MARÍA PÉREZ', distrito: 'Piura',
      origen: 'referido', monto_estimado: 5000, moneda: 'PEN', etapa_actual: 'contactado',
      movimiento: 'asignado', derivado_en: '2026-08-19T10:00:00Z',
      responsable_anterior: 'Bandeja de SUPERVISOR UNO', responsable_nuevo: 'ANALISTA UNO',
      derivado_por_nombre: 'SUPERVISOR UNO',
    }]
    const usuario = userEvent.setup()
    render(<Repartir />)

    await usuario.click(screen.getByRole('tab', { name: 'Historial' }))
    expect(await screen.findByText('MARÍA PÉREZ')).toBeInTheDocument()
    expect(screen.getByText('Bandeja de SUPERVISOR UNO')).toBeInTheDocument()
    expect(historialMock).toHaveBeenCalledTimes(1)
    expect(screen.getByText(/No incluye teléfono, correo ni DNI/)).toBeInTheDocument()
  })

  it('agenda Landing y Formulario para Carmen y Jor desde la vista de Coordinación', async () => {
    AGENDA = {
      version: 1,
      fecha_desde: fechaHoyLima,
      destinos: [
        { perfil_id: 'sup-carmen', nombre: 'CARMEN JARAMILLO', alias: 'Carmen' },
        { perfil_id: 'sup-jor', nombre: 'JORGE MARZANO', alias: 'Jor' },
      ],
      dias: [{
        fecha: fechaHoyLima,
        asignaciones: [
          { origen: 'landing', supervisor_id: null, supervisor_nombre: null, supervisor_alias: null, derivados: 0, fuera_turno: 0, entregas: [] },
          { origen: 'formulario', supervisor_id: null, supervisor_nombre: null, supervisor_alias: null, derivados: 0, fuera_turno: 0, entregas: [] },
        ],
      }],
    }
    const usuario = userEvent.setup()
    render(<Repartir />)

    expect(await screen.findByRole('heading', { name: 'Coordinación → supervisores' })).toBeInTheDocument()
    await usuario.selectOptions(screen.getByLabelText('Asignar Landing a una supervisora'), 'sup-carmen')
    await usuario.selectOptions(screen.getByLabelText('Asignar Formulario a una supervisora'), 'sup-jor')
    await usuario.click(screen.getByRole('button', { name: 'Guardar turno' }))

    await waitFor(() => expect(guardarAgendaMock).toHaveBeenCalledWith(fechaHoyLima, 'sup-carmen', 'sup-jor'))
    expect(agendaMock).toHaveBeenCalled()
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('Turno del'))
  })

  it('pagina la cola en vez de acumular filas en una pantalla interminable', async () => {
    COLA = Array.from({ length: 21 }, (_, indice) => lead({
      id: `lead-${indice + 1}`,
      nombre_completo: `LEAD ${indice + 1}`,
      creado_en: '2026-08-01T12:00:00Z',
    }))
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)

    expect(await screen.findByText('LEAD 1')).toBeInTheDocument()
    expect(screen.queryByText('LEAD 21')).not.toBeInTheDocument()
    expect(screen.getByText('Página 1 de 2 · 21 registros')).toBeInTheDocument()

    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    expect(await screen.findByText('LEAD 21')).toBeInTheDocument()
    expect(screen.queryByText('LEAD 1')).not.toBeInTheDocument()
  })

  it('muestra una tabla de entregas por origen y conserva exactamente dos turnos', async () => {
    const entrega = { supervisor_id: 'sup-2', supervisor_nombre: 'SUPERVISOR DOS', supervisor_alias: 'Supervisora dos', derivados: 10, coincide_turno: true }
    const fuera = { supervisor_id: 'sup-1', supervisor_nombre: 'SUPERVISOR UNO', supervisor_alias: 'Supervisora uno', derivados: 2, coincide_turno: false }
    AGENDA.dias[0]!.origenes = [
      { origen: 'formulario_3', turno: 'formulario', derivados: 12, fuera_turno: 2, entregas: [entrega, fuera] },
      { origen: 'formulario', turno: 'formulario', derivados: 18, fuera_turno: 0, entregas: [{ ...entrega, derivados: 18 }] },
      { origen: 'referido', turno: null, derivados: 1, fuera_turno: null, entregas: [{ ...entrega, derivados: 1 }] },
    ]
    const usuario = userEvent.setup()
    render(<Repartir />)
    expect(await screen.findByText('31 entregados · 2 fuera de turno')).toBeInTheDocument()
    expect(colaMock).not.toHaveBeenCalled()
    expect(screen.getAllByLabelText(/^Asignar .* a una supervisora$/)).toHaveLength(2)
    expect(screen.getAllByRole('table')).toHaveLength(1)
    expect(screen.getByText('No aplica')).toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Invertir' }))
    await usuario.selectOptions(screen.getByLabelText('Filtrar entregas a supervisoras por origen'), 'formulario_3')
    expect(screen.getByText('12 entregados · 2 fuera de turno')).toBeInTheDocument()
    expect(screen.getByLabelText('Asignar Landing a una supervisora')).toHaveValue('sup-2')
    await usuario.click(screen.getByRole('tab', { name: 'Cola de nuevos' }))
    await usuario.click(screen.getByRole('tab', { name: 'Coordinación → supervisores' }))
    expect(screen.getByLabelText('Asignar Landing a una supervisora')).toHaveValue('sup-2')
    await usuario.click(screen.getByRole('button', { name: 'Guardar turno' }))
    await waitFor(() => expect(guardarAgendaMock).toHaveBeenCalledWith(fechaHoyLima, 'sup-2', 'sup-1'))
  })

  it('distingue un desglose ausente de un día sin entregas', async () => {
    render(<Repartir />)
    expect(await screen.findByText(/Desglose por origen no disponible/)).toBeInTheDocument()
    expect(screen.getByLabelText('Filtrar entregas a supervisoras por origen')).toBeDisabled()
    expect(screen.queryByText('0 entregados · 0 fuera de turno')).not.toBeInTheDocument()
  })

  it('conserva el turno confirmado cuando falla la relectura posterior al guardado', async () => {
    const usuario = userEvent.setup()
    render(<Repartir />)
    await screen.findByLabelText('Asignar Landing a una supervisora')
    await usuario.click(screen.getByRole('button', { name: 'Invertir' }))
    agendaMock.mockRejectedValueOnce(new Error('Sin conexión temporal'))
    await usuario.click(screen.getByRole('button', { name: 'Guardar turno' }))
    expect(await screen.findByText('Sin conexión temporal')).toBeInTheDocument()
    expect(screen.getByLabelText('Asignar Landing a una supervisora')).toHaveValue('sup-2')
    expect(screen.getByLabelText('Asignar Formulario a una supervisora')).toHaveValue('sup-1')
    expect(screen.getByText('Turno guardado.')).toBeInTheDocument()
  })

  it('al regresar a Coordinación recarga los conteos sin requerir foco del navegador', async () => {
    const usuario = userEvent.setup()
    render(<Repartir />)
    await screen.findByLabelText('Asignar Landing a una supervisora')
    await abrirCola(usuario)
    const lecturas = agendaMock.mock.calls.length
    await usuario.click(screen.getByRole('tab', { name: 'Coordinación → supervisores' }))
    await waitFor(() => expect(agendaMock).toHaveBeenCalledTimes(lecturas + 1))
  })

  it('recupera la lectura aplazada al volver con borrador y deshacerlo', async () => {
    const usuario = userEvent.setup()
    render(<Repartir />)
    await screen.findByLabelText('Asignar Landing a una supervisora')
    await usuario.click(screen.getByRole('button', { name: 'Invertir' }))
    await abrirCola(usuario)
    const lecturas = agendaMock.mock.calls.length
    await usuario.click(screen.getByRole('tab', { name: 'Coordinación → supervisores' }))
    expect(agendaMock).toHaveBeenCalledTimes(lecturas)
    await usuario.click(screen.getByRole('button', { name: 'Invertir' }))
    await waitFor(() => expect(agendaMock).toHaveBeenCalledTimes(lecturas + 1))
  })

  it('un guardado fallido no deja la agenda cargando después de abortar su lectura', async () => {
    const usuario = userEvent.setup()
    let resolver!: (datos: AgendaRepartoDiaria) => void
    render(<Repartir />)
    await screen.findByLabelText('Asignar Landing a una supervisora')
    agendaMock.mockImplementationOnce(() => new Promise((r) => { resolver = r }))
    await usuario.click(screen.getByRole('button', { name: 'Actualizar' }))
    await usuario.click(screen.getByRole('button', { name: 'Invertir' }))
    guardarAgendaMock.mockRejectedValueOnce(new Error('Guardado interrumpido'))
    await usuario.click(screen.getByRole('button', { name: 'Guardar turno' }))
    await waitFor(() => expect(toastError).toHaveBeenCalledWith('Guardado interrumpido'))
    await usuario.click(screen.getByRole('button', { name: 'Invertir' }))
    expect(screen.getByRole('button', { name: 'Actualizar' })).toBeEnabled()
    await act(async () => resolver(AGENDA))
    expect(screen.getByRole('button', { name: 'Actualizar' })).toBeEnabled()
  })

  it('no lee la cola al volver durante un reparto y reconcilia al finalizar', async () => {
    COLA = [lead()]
    let resolver!: () => void
    repartirMock.mockImplementation(() => new Promise<void>((r) => { resolver = r }))
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    await usuario.click(await screen.findByRole('button', { name: 'Repartir a ROSA QUISPE' }))
    const lecturas = colaMock.mock.calls.length
    await usuario.click(screen.getByRole('tab', { name: 'Coordinación → supervisores' }))
    await abrirCola(usuario)
    expect(colaMock).toHaveBeenCalledTimes(lecturas)
    COLA = []
    await act(async () => resolver())
    await waitFor(() => expect(colaMock).toHaveBeenCalledTimes(lecturas + 1))
    expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument()
  })

  it('un desglose vacío explícito sí informa cero entregas', async () => {
    AGENDA.dias[0]!.origenes = []
    render(<Repartir />)
    expect(await screen.findByText('0 entregados · 0 fuera de turno')).toBeInTheDocument()
    expect(screen.getByText('No hay entregas con estos filtros en el día seleccionado.')).toBeInTheDocument()
  })

  it('filtra Formulario 3 en toda la cola y conserva filtro y turno después del reparto', async () => {
    COLA = Array.from({ length: 25 }, (_, indice) => lead({
      id: `camp-${indice}`, nombre_completo: `CONTACTO ${indice}`, origen: indice === 24 ? 'formulario_3' : 'formulario',
      creado_en: '2026-08-01T12:00:00Z', campania_origen: indice === 24 ? 'Formulario 3' : null,
      comentario: indice === 0 ? 'Campaña: Formulario 3' : null,
    }))
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    expect(screen.queryByText('CONTACTO 24')).not.toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    await usuario.selectOptions(screen.getByLabelText('Filtrar por origen del lead'), 'formulario_3')
    expect(screen.getByText('CONTACTO 24')).toBeInTheDocument()
    expect(screen.queryByText('CONTACTO 0')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Siguiente' })).not.toBeInTheDocument()
    expect(screen.queryByText('Campaña de origen: Formulario 3')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Asignar CONTACTO 24 a un supervisor')).toHaveValue('sup-2')
    expect(screen.getByLabelText('Asignar CONTACTO 24 a un supervisor')).toBeDisabled()
    await usuario.click(screen.getByRole('button', { name: 'Repartir a CONTACTO 24' }))
    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('camp-24', 'sup-2'))
    expect(await screen.findByText('Ningún lead coincide con la búsqueda o los filtros')).toBeInTheDocument()
    expect(screen.getByLabelText('Filtrar por origen del lead')).toHaveValue('formulario_3')
    await usuario.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(screen.getByText('CONTACTO 0')).toBeInTheDocument()
  })

  it('Formulario 3 conserva el reparto libre y el destino elegido entre pestañas', async () => {
    AGENDA.reparto_libre = true
    COLA = [lead({ origen: 'formulario_3' }), lead({ id: 'anterior', nombre_completo: 'ANTERIOR' })]
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    await usuario.selectOptions(screen.getByLabelText('Asignar ROSA QUISPE a un supervisor'), 'sup-1')
    await usuario.click(screen.getByRole('tab', { name: 'Coordinación → supervisores' }))
    await abrirCola(usuario)
    expect(screen.getByLabelText('Asignar ROSA QUISPE a un supervisor')).toHaveValue('sup-1')
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))
    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('lead-1', 'sup-1'))
    expect(screen.getByText('ANTERIOR')).toBeInTheDocument()
  })

  it('navega el historial por páginas de 25 sin anexar tarjetas previas', async () => {
    HISTORIAL = Array.from({ length: 25 }, (_, indice) => ({
      actividad_id: `hist-${indice + 1}`,
      lead_id: `lead-${indice + 1}`,
      nombre_completo: `HISTORIAL ${indice + 1}`,
      distrito: null,
      origen: 'referido' as const,
      monto_estimado: 5000,
      moneda: 'PEN' as const,
      etapa_actual: 'contactado' as const,
      movimiento: 'asignado',
      derivado_en: '2026-08-19T10:00:00Z',
      responsable_anterior: 'Bandeja de SUPERVISOR UNO',
      responsable_nuevo: 'ANALISTA UNO',
      derivado_por_nombre: 'SUPERVISOR UNO',
    }))
    const usuario = userEvent.setup()
    render(<Repartir />)
    await usuario.click(screen.getByRole('tab', { name: 'Historial' }))

    expect(await screen.findByText('HISTORIAL 1')).toBeInTheDocument()
    expect(screen.getByText('Página 1 · hasta 25 movimientos')).toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    expect(await screen.findByText('Página 2 · hasta 25 movimientos')).toBeInTheDocument()
    expect(screen.getAllByText('HISTORIAL 1')).toHaveLength(1)
    expect(historialMock).toHaveBeenCalledTimes(2)
  })

  it('pinta un vacío honesto cuando no hay nada por repartir', async () => {
    render(<Repartir />)
    await abrirCola()
    expect(await screen.findByText('No hay leads por repartir')).toBeInTheDocument()
  })

  it('NUNCA suma PEN y USD: muestra el capital en juego por separado', async () => {
    COLA = [
      lead({ id: 'l-pen', monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'l-usd', monto_estimado: 30000, moneda: 'USD', nombre_completo: 'JUAN PEREZ' }),
    ]
    render(<Repartir />)
    await abrirCola()

    await screen.findByText('ROSA QUISPE')
    // Cada cifra acotada a SU tile: "S/ 12k" también aparece —con razón— en la
    // fila del lead, y un selector global sería ambiguo, no una falla de UI.
    await valorDelTile('Capital en juego (PEN)', 'S/ 12k')
    await valorDelTile('Capital en juego (USD)', 'US$ 30k')
    // El total mezclado (42k) no debe existir en ninguna moneda.
    expect(screen.queryByText(/42k/)).not.toBeInTheDocument()
  })

  it('los tiles los sirve el resumen del servidor, no el conteo de filas', async () => {
    COLA = [
      lead({ id: 'l-1', monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'l-2', monto_estimado: 30000, moneda: 'USD', nombre_completo: 'JUAN PEREZ' }),
    ]
    render(<Repartir />)
    await abrirCola()

    await screen.findByText('ROSA QUISPE')
    await valorDelTile('Por repartir', '2')
  })

  it('sin cola, la espera más larga se muestra como «—» (no como "hoy")', async () => {
    render(<Repartir />)
    await abrirCola()

    await screen.findByText('No hay leads por repartir')
    expect(within(tile('Espera más larga')).getByText('—')).toBeInTheDocument()
  })

  it('si el resumen del servidor cae: tiles a «—» con aviso, y la cola sigue repartible', async () => {
    RESUMEN_CAIDO = true
    COLA = [lead({ monto_estimado: 12000, moneda: 'PEN' })]
    render(<Repartir />)
    await abrirCola()

    // La lista tiene su propia fuente: no se cae con el resumen.
    await screen.findByText('ROSA QUISPE')
    expect(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' })).toBeInTheDocument()

    // Y ningún tile inventa una cifra: cuatro guiones, ni un "0" ni un "S/ 0".
    for (const etiqueta of ['Por repartir', 'Capital en juego (PEN)', 'Capital en juego (USD)', 'Espera más larga']) {
      expect(within(tile(etiqueta)).getByText('—')).toBeInTheDocument()
    }
    expect(within(tile('Capital en juego (PEN)')).queryByText('S/ 0')).not.toBeInTheDocument()

    // `status` y no `alert`: la pantalla queda operable con «—» y no hay nada
    // urgente que justifique interrumpir la lectura en curso.
    const aviso = screen.getByRole('status')
    expect(aviso).toHaveTextContent(/No se pudieron cargar los indicadores de la cola/)
    // Nombre accesible distinguible del OTRO «Reintentar» (el del PanelError).
    const reintentar = within(aviso).getByRole('button', {
      name: 'Reintentar la carga de los indicadores de la cola',
    })
    await userEvent.setup().click(reintentar)
    expect(recargarResumenMock).toHaveBeenCalledTimes(1)
  })

  it('reparte a un supervisor, saca la fila de la cola y sube su bandeja', async () => {
    COLA = [lead()]
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)

    await screen.findByText('ROSA QUISPE')
    expect(screen.getByLabelText('Asignar ROSA QUISPE a un supervisor')).toBeDisabled()
    expect(screen.getByLabelText('Asignar ROSA QUISPE a un supervisor')).toHaveValue('sup-1')
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('lead-1', 'sup-1'))
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('SUPERVISOR UNO'))
    // La fila sale de la cola sin releerla entera.
    await waitFor(() => expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument())
    expect(screen.getByText('No hay leads por repartir')).toBeInTheDocument()
    expect(screen.getByText('1 entregado hoy por Coordinación')).toBeInTheDocument()
    expect(colaMock).toHaveBeenCalledTimes(1)
  })

  it('permite al administrador apartarse del turno y conserva el destino real', async () => {
    authState.esAdministrador = true
    COLA = [lead()]
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)

    const selector = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(selector).toBeEnabled()
    expect(selector).toHaveValue('sup-1')
    expect(screen.getByText(/Puedes elegir cualquier supervisor activo/)).toBeInTheDocument()

    await usuario.selectOptions(selector, 'sup-2')
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('lead-1', 'sup-2'))
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('SUPERVISOR DOS'))
    expect(screen.getByText('1 entregado hoy por Coordinación')).toBeInTheDocument()
  })

  it.each(['landing', 'formulario'] as const)('Coordinación con permiso elige otro supervisor para %s', async (origen) => {
    COLA = [lead({ origen })]
    AGENDA.reparto_libre = true
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    const selector = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(selector).toBeEnabled()
    const otro = origen === 'landing' ? 'sup-2' : 'sup-1'
    await usuario.selectOptions(selector, otro)
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))
    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('lead-1', otro))
  })

  it('Coordinación con permiso puede repartir sin agenda guardada', async () => {
    COLA = [lead()]
    AGENDA = { ...AGENDA, reparto_libre: true, dias: [] }
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    const selector = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(selector).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' })).toBeDisabled()
    await usuario.selectOptions(selector, 'sup-2')
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))
    await waitFor(() => expect(repartirMock).toHaveBeenCalledWith('lead-1', 'sup-2'))
  })

  it('recupera el turno si Gerencia apaga el permiso con la pantalla abierta', async () => {
    COLA = [lead()]
    AGENDA.reparto_libre = true
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    const selector = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    await usuario.selectOptions(selector, 'sup-2')
    AGENDA = { ...AGENDA, reparto_libre: false }
    repartirMock.mockRejectedValue(new CrmApiError('Según el turno de hoy, Landing corresponde a Supervisora uno.', 'REGLA_SERVIDOR'))
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))
    await waitFor(() => expect(colaMock).toHaveBeenCalledTimes(2))
    const actualizado = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(actualizado).toBeDisabled()
    expect(actualizado).toHaveValue('sup-1')
    expect(screen.getByText('ROSA QUISPE')).toBeInTheDocument()
    expect(toastSuccess).not.toHaveBeenCalled()
  })

  it('al volver actualiza cola y permiso sin perder el destino elegido', async () => {
    COLA = [lead()]
    AGENDA.reparto_libre = false
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)
    const selector = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    const lecturas = agendaMock.mock.calls.length
    expect(selector).toBeDisabled()
    vi.useFakeTimers()
    AGENDA = { ...AGENDA, reparto_libre: true }
    fireEvent.focus(window)
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(selector).toBeEnabled()
    fireEvent.change(selector, { target: { value: 'sup-2' } })
    fireEvent.focus(window)
    fireEvent.focus(window)
    fireEvent.focus(window)
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(agendaMock).toHaveBeenCalledTimes(lecturas + 2)
    expect(colaMock).toHaveBeenCalledTimes(3)
    expect(supervisoresMock).toHaveBeenCalledTimes(3)
    expect(screen.getByLabelText('Asignar ROSA QUISPE a un supervisor')).toBe(selector)
    expect(selector).toHaveValue('sup-2')
    AGENDA = { ...AGENDA, reparto_libre: false }
    fireEvent.focus(window)
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(selector).toBeDisabled()
    expect(selector).toHaveValue('sup-1')
  })

  it('no refresca el permiso durante un envío ni pisa los contadores confirmados', async () => {
    COLA = [lead(), lead({ id: 'lead-2', nombre_completo: 'OTRO LEAD' })]
    AGENDA.reparto_libre = true
    let resolver!: () => void
    repartirMock.mockImplementation(() => new Promise<void>((resolve) => { resolver = resolve }))
    render(<Repartir />)
    await abrirCola()
    const boton = await screen.findByRole('button', { name: 'Repartir a ROSA QUISPE' })
    const lecturas = agendaMock.mock.calls.length
    vi.useFakeTimers()
    fireEvent.click(boton)
    fireEvent.focus(window)
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(agendaMock).toHaveBeenCalledTimes(lecturas)
    expect(boton).toHaveTextContent('Enviando…')
    COLA = COLA.filter((fila) => fila.nombre_completo !== 'ROSA QUISPE')
    AGENDA.dias[0]!.asignaciones[0]!.derivados = 1
    await act(async () => resolver())
    fireEvent.focus(window)
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(agendaMock).toHaveBeenCalledTimes(lecturas + 1)
    expect(screen.getByText('1 entregado hoy por Coordinación')).toBeInTheDocument()
    expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument()
    expect(colaMock).toHaveBeenCalledTimes(2)
  })

  it('cancela la recarga pendiente y retira el listener al salir de la pantalla', async () => {
    COLA = [lead()]
    const vista = render(<Repartir />)
    await abrirCola()
    await screen.findByText('ROSA QUISPE')
    const lecturas = agendaMock.mock.calls.length
    vi.useFakeTimers()
    fireEvent.focus(window)
    vista.unmount()
    fireEvent.focus(window)
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(agendaMock).toHaveBeenCalledTimes(lecturas)
  })

  it('mantiene cada fila bloqueada hasta que termine su propia petición', async () => {
    COLA = [
      lead({ id: 'lead-a', nombre_completo: 'LEAD A' }),
      lead({ id: 'lead-b', nombre_completo: 'LEAD B' }),
    ]
    let resolverA!: () => void
    let resolverB!: () => void
    repartirMock.mockImplementation((leadId) => new Promise<void>((resolve) => {
      if (leadId === 'lead-a') resolverA = resolve
      else resolverB = resolve
    }))
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)

    const botonA = await screen.findByRole('button', { name: 'Repartir a LEAD A' })
    const botonB = screen.getByRole('button', { name: 'Repartir a LEAD B' })
    fireEvent.click(botonA)
    fireEvent.click(botonA)
    fireEvent.click(botonB)

    expect(repartirMock.mock.calls.filter(([leadId]) => leadId === 'lead-a')).toHaveLength(1)
    expect(repartirMock.mock.calls.filter(([leadId]) => leadId === 'lead-b')).toHaveLength(1)

    await act(async () => resolverB())
    await waitFor(() => expect(screen.queryByText('LEAD B')).not.toBeInTheDocument())
    expect(screen.getByRole('button', { name: 'Repartir a LEAD A' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Repartir a LEAD A' })).toHaveTextContent('Enviando…')

    await act(async () => resolverA())
    await waitFor(() => expect(screen.queryByText('LEAD A')).not.toBeInTheDocument())
  })

  it('el veto legal (No Insista) avisa, NO mueve la fila y relee la cola', async () => {
    COLA = [lead()]
    repartirMock.mockRejectedValue(
      new CrmApiError('Lead marcado No Insista (Ley 29571): no se puede repartir', 'NO_INSISTA'),
    )
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)

    await screen.findByText('ROSA QUISPE')
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() =>
      expect(toastError).toHaveBeenCalledWith(
        'Lead marcado No Insista (Ley 29571): no se puede repartir',
      ),
    )
    expect(toastSuccess).not.toHaveBeenCalled()
    // La cola local estaba desfasada respecto del servidor → se relee.
    await waitFor(() => expect(colaMock).toHaveBeenCalledTimes(2))
  })

  it('si el lead ya salió de la cola avisa y resincroniza', async () => {
    COLA = [lead()]
    repartirMock.mockRejectedValue(
      new CrmApiError('El lead ya no está en la cola por repartir', 'FUERA_DE_COLA'),
    )
    const usuario = userEvent.setup()
    render(<Repartir />)
    await abrirCola(usuario)

    await screen.findByText('ROSA QUISPE')
    await usuario.click(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' }))

    await waitFor(() => expect(toastError).toHaveBeenCalled())
    await waitFor(() => expect(colaMock).toHaveBeenCalledTimes(2))
  })

  it('sin supervisores activos no se puede repartir y lo dice', async () => {
    COLA = [lead()]
    SUPERVISORES = []
    render(<Repartir />)
    await abrirCola()

    expect(await screen.findByText('No hay supervisores activos')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Repartir a / })).not.toBeInTheDocument()
  })

  it('el destino muestra la carga de cada bandeja (para repartir con criterio)', async () => {
    COLA = [lead({ origen: 'referido' })]
    render(<Repartir />)
    await abrirCola()

    const select = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(within(select).getByText('SUPERVISOR UNO (2 en bandeja)')).toBeInTheDocument()
    expect(within(select).getByText('SUPERVISOR DOS (0 en bandeja)')).toBeInTheDocument()
  })

  it('bloquea Landing si el turno de hoy todavía no fue guardado', async () => {
    COLA = [lead()]
    AGENDA = {
      ...AGENDA,
      dias: [{
        fecha: fechaHoyLima,
        asignaciones: [
          { origen: 'landing', supervisor_id: null, supervisor_nombre: null, supervisor_alias: null, derivados: 0, fuera_turno: 0, entregas: [] },
          { origen: 'formulario', supervisor_id: 'sup-2', supervisor_nombre: 'SUPERVISOR DOS', supervisor_alias: 'Supervisora dos', derivados: 0, fuera_turno: 0, entregas: [] },
        ],
      }],
    }
    render(<Repartir />)
    await abrirCola()

    const select = await screen.findByLabelText('Asignar ROSA QUISPE a un supervisor')
    expect(select).toBeDisabled()
    expect(select).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Repartir a ROSA QUISPE' })).toBeDisabled()
    expect(screen.getByText('Guarda primero el turno en Coordinación → supervisores.')).toBeInTheDocument()
    expect(repartirMock).not.toHaveBeenCalled()
  })

  it('la pestaña Conversiones pide el divisor del núcleo al servidor y lo pinta tal cual', async () => {
    const usuario = userEvent.setup()
    render(<Repartir />)
    expect(await screen.findByRole('heading', { name: 'Coordinación → supervisores' })).toBeInTheDocument()
    expect(conversionMock).not.toHaveBeenCalled()

    await usuario.click(screen.getByRole('tab', { name: 'Conversiones' }))
    expect(await screen.findByRole('heading', { name: 'Conversiones' })).toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledTimes(1)
    expect(conversionMock.mock.calls[0]?.[0]).toEqual({ modo: 'mes', mes: expect.stringMatching(/^\d{4}-\d{2}$/) })

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    const celdas = within(astrid).getAllByRole('cell').map((celda) => celda.textContent ?? '')
    expect(celdas[0]).toBe('ASTRID CENTENAROVer cierres')
    expect(within(astrid).getByRole('button', { name: 'Ver cierres de ASTRID CENTENARO' })).toBeEnabled()
    expect(celdas.slice(2, 6)).toEqual(['65', '—desglose de Formulario 3 no disponible', '50', '115'])            // llegadas: formulario, landing, total
    expect(celdas[9]).toBe('0')                                          // base cargada (B11)
    expect(celdas[10]).toContain('1 · 0.15')                              // referidos: cantidad · aporte
    expect(celdas[12]).toBe('4')                                         // upgrade
    expect(celdas[14]).toBe('11.15')                                     // cierres ponderados
    expect(celdas[15]).toBe('9.70%')
    expect(screen.getByText(/Este conteo es distinto del reporte de entregas/)).toBeInTheDocument()
  })
})

// F5a «Bases cargadas»: una fila de la cola con origen `base_cargada` y capital vacío se rotula «Base cargada · Sin
// capital» y no suma al capital en juego (sin «S/ 0» inventado).
describe('Repartir · F5a contacto de base cargada', () => {
  it('rotula «Base cargada · Sin capital» y el tile de capital solo suma los que lo tienen', async () => {
    COLA = [
      lead({ id: 'l-pen', monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'l-base', origen: 'base_cargada', monto_estimado: null, moneda: 'PEN', nombre_completo: 'CONTACTO DE BASE' }),
    ]
    render(<Repartir />)
    await abrirCola()

    expect(await screen.findByText('CONTACTO DE BASE')).toBeInTheDocument()
    expect(screen.getAllByText('Sin capital').length).toBeGreaterThan(0)
    expect(screen.getAllByText(/Base cargada/).length).toBeGreaterThan(0)
    await valorDelTile('Capital en juego (PEN)', 'S/ 12k')
  })
})
