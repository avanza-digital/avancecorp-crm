// Tests de integración de la pantalla "Cartera" (fusión Clientes+Contratos):
// render, colapsado por defecto, expandir, moneda USD-only (dólares principal) y
// gating por fila. Mockea auth/store/datos (sin red) y usa un QueryClient limpio
// (MiCartera pide useQueryClient para las invalidaciones). Ruta REAL (demo=false):
// no hay import() dinámico de fixtures.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ClienteBasico, ClienteDetalle, ContratoRow } from '@/lib/clientes-tipos'

// `yo`, clientes y contratos se pisan antes de cada montaje; los mocks los leen
// en cada llamada (no capturan el valor al definirse).
let YO: { id: string; rol: string; puede_contratar: boolean; demo: boolean } | null = null
let CLIENTES: ClienteBasico[] = []
let CONTRATOS: ContratoRow[] = []
let EQUIPO: Array<{ perfil_id: string; nombre_completo: string; activo: boolean }> = []
let DETALLE: ClienteDetalle | null = null

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ equipo: EQUIPO, ambito: { vendedores: [], esGlobal: false, leads: [] } }),
}))
vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  const q = <T,>(data: T) => ({
    data,
    isPending: false,
    isSuccess: true,
    isError: false,
    error: null,
    refetch: vi.fn(),
    isFetching: false,
    isFetchedAfterMount: true,
  })
  return {
    ...actual, // conserva crmQueryKeys real
    useClientes: () => q(CLIENTES),
    useContratos: () => q(CONTRATOS),
    useClienteDetalle: vi.fn(() => q(DETALLE)),
    // ContratoDetalle usa estos tres; con data null pinta skeletons (no red, no crash).
    useContrato: () => q(null),
    useCronograma: () => q(null),
    useTitulares: () => q(null),
  }
})

const { useClienteDetalle } = await import('@/data/crm-queries')
const useClienteDetalleMock = vi.mocked(useClienteDetalle)
const { MiCartera } = await import('./mi-cartera')

function cliente(over: Partial<ClienteBasico> = {}): ClienteBasico {
  return {
    id: 'c-1',
    nombres: null,
    apellidos: null,
    nombre_completo: 'CLIENTE UNO',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: null,
    telefono: null,
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    activo: true,
    creado_en: new Date().toISOString(),
    ...over,
  }
}

function contrato(over: Partial<ContratoRow> = {}): ContratoRow {
  return {
    id: 'k-1',
    numero_contrato: '2026-01-000001',
    cliente_id: 'c-1',
    cliente_nombre: 'CLIENTE UNO',
    capital: 10000,
    moneda: 'PEN',
    tasa_anual: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2026-01-01',
    fecha_vencimiento: '2027-01-01',
    notas_internas: null,
    creado_por: 'yo',
    creado_en: new Date().toISOString(),
    ...over,
  }
}

function detalle(over: Partial<ClienteDetalle> = {}): ClienteDetalle {
  return {
    id: 'c-1',
    nombre_completo: 'CLIENTE UNO',
    nombres: 'UNO',
    apellidos: 'CLIENTE',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente@avance.pe',
    telefono: '+51999888777',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: '2026-07-15T12:00:00.000Z',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '2003001234567',
    cci_usd: '00320030012345678901',
    titular_distinto_usd: true,
    beneficiario_nombre_usd: 'JUANA PEREZ',
    beneficiario_dni_usd: '87654321',
    ...over,
  }
}

function montar(
  over: {
    yo?: typeof YO
    clientes?: ClienteBasico[]
    contratos?: ContratoRow[]
    detalle?: ClienteDetalle | null
    equipo?: Array<{ perfil_id: string; nombre_completo: string; activo: boolean }>
  } = {},
) {
  YO = over.yo ?? { id: 'yo', rol: 'vendedor', puede_contratar: true, demo: false }
  CLIENTES = over.clientes ?? [cliente()]
  CONTRATOS = over.contratos ?? [contrato()]
  EQUIPO = over.equipo ?? []
  // `null` es un caso de prueba válido (skeleton/error); solo `undefined`
  // significa "usa la ficha por defecto".
  DETALLE = over.detalle === undefined ? detalle() : over.detalle
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MiCartera />
    </QueryClientProvider>,
  )
}

describe('MiCartera (pantalla)', () => {
  it('pinta la fila del cliente y arranca COLAPSADA (sin sub-filas de contrato)', () => {
    montar()
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    // El N° de contrato NO está en el DOM hasta expandir el grupo.
    expect(screen.queryByText('2026-01-000001')).not.toBeInTheDocument()
  })

  it('expandir el cliente monta su sub-fila de contrato', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(screen.getByText('2026-01-000001')).toBeInTheDocument()
  })

  it('USD-only: muestra la tarjeta de Dólares y NO la de Soles (dólares principal)', () => {
    montar({
      clientes: [cliente({ id: 'c-usd' })],
      contratos: [contrato({ id: 'k-usd', cliente_id: 'c-usd', moneda: 'USD', capital: 50000 })],
    })
    expect(screen.getByText('Capital invertido · Dólares')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
  })

  it('gating: la fila propia ofrece "+ Contrato"', () => {
    montar()
    expect(screen.getByRole('button', { name: /\+ Contrato/ })).toBeInTheDocument()
  })

  it('gating: una fila AJENA no ofrece acciones', () => {
    montar({
      clientes: [cliente({ id: 'c-ajeno', asesor_perfil_id: 'otro', creado_por: 'otro' })],
      contratos: [contrato({ id: 'k-ajeno', cliente_id: 'c-ajeno', creado_por: 'otro' })],
    })
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /\+ Contrato/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Ver detalle' })).not.toBeInTheDocument()
  })

  it('muestra todos los datos del cliente propio, aun con la ventana de corrección vencida', async () => {
    const user = userEvent.setup()
    montar({ clientes: [cliente({ creado_en: '2020-01-01T00:00:00.000Z' })] })

    await user.click(screen.getByRole('button', { name: 'Ver detalle' }))

    expect(screen.getByRole('dialog', { name: 'CLIENTE UNO' })).toBeInTheDocument()
    expect(screen.getByText('Datos personales')).toBeInTheDocument()
    expect(screen.getByText('cliente@avance.pe')).toBeInTheDocument()
    expect(screen.getByText('Cuenta para depósitos en soles')).toBeInTheDocument()
    expect(screen.getByText('00219112345678901234')).toBeInTheDocument()
    expect(screen.getByText('Cuenta para depósitos en dólares')).toBeInTheDocument()
    expect(screen.getByText('JUANA PEREZ')).toBeInTheDocument()
  })

  it('con filtro activo el grupo se auto-expande y AÚN se puede colapsar (botón real)', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(screen.getByRole('textbox', { name: /Buscar en la cartera/ }), '000001')
    // Auto-expandido por coincidencia de N° de contrato → la sub-fila es visible.
    expect(screen.getByText('2026-01-000001')).toBeInTheDocument()
    // El botón dice "Colapsar" y de verdad colapsa (no es un override que mienta).
    await user.click(screen.getByRole('button', { name: /Colapsar los contratos de\s*CLIENTE UNO/ }))
    expect(screen.queryByText('2026-01-000001')).not.toBeInTheDocument()
  })

  // Devuelve la <tr> de la sub-fila del contrato (para acotar el gating a ella).
  function subFilaDe(numero: string): HTMLElement {
    const celda = screen.getByText(numero).closest('tr')
    if (!celda) throw new Error(`sub-fila del contrato ${numero} no encontrada`)
    return celda
  }

  it('Corregir del contrato: PRESENTE si es mío y con ventana viva', async () => {
    const user = userEvent.setup()
    montar() // contrato creado_por 'yo', creado_en reciente → ventana viva
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(within(subFilaDe('2026-01-000001')).getByRole('button', { name: /Corregir/ })).toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si la ventana de 5 h ya venció', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ creado_en: '2020-01-01T00:00:00.000Z' })] })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(within(subFilaDe('2026-01-000001')).queryByRole('button', { name: /Corregir/ })).not.toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si es de otro asesor (creado_por ≠ yo)', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ creado_por: 'otro' })] })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(within(subFilaDe('2026-01-000001')).queryByRole('button', { name: /Corregir/ })).not.toBeInTheDocument()
  })

  it('tarjetas de moneda — solo PEN: Soles presente, Dólares ausente', () => {
    montar() // contrato en PEN
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Dólares')).not.toBeInTheDocument()
  })

  it('tarjetas de moneda — PEN y USD: ambas presentes', () => {
    montar({
      clientes: [cliente({ id: 'a' }), cliente({ id: 'b' })],
      contratos: [
        contrato({ id: 'kp', cliente_id: 'a', moneda: 'PEN', capital: 10000 }),
        contrato({ id: 'ku', cliente_id: 'b', moneda: 'USD', capital: 5000 }),
      ],
    })
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.getByText('Capital invertido · Dólares')).toBeInTheDocument()
  })

  it('tarjetas de moneda — sin capital activo: tarjeta neutra, sin desglose por moneda', () => {
    montar({ contratos: [contrato({ estado: 'vencido' })] }) // ningún contrato activo
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Dólares')).not.toBeInTheDocument()
  })
})

describe('MiCartera (demo aislada)', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('abre la ficha ficticia precargada y deshabilita la consulta a Supabase', async () => {
    const user = userEvent.setup()
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    montar({
      yo: { id: 'd-v1', rol: 'vendedor', puede_contratar: true, demo: true },
      clientes: [],
      contratos: [],
    })

    const nombre = await screen.findByText('ROSA MERCEDES AGUILAR VENTURA')
    const fila = nombre.closest('tr')
    if (!fila) throw new Error('fila del cliente demo no encontrada')
    useClienteDetalleMock.mockClear()

    await user.click(within(fila).getByRole('button', { name: 'Ver detalle' }))

    expect(screen.getByRole('dialog', { name: 'ROSA MERCEDES AGUILAR VENTURA' })).toBeInTheDocument()
    expect(screen.getByText('rosa.aguilar@correo.pe')).toBeInTheDocument()
    expect(screen.getByText('19100000001234')).toBeInTheDocument()
    expect(screen.getByText('00219100000000123456')).toBeInTheDocument()
    // El hook conserva su orden estable, pero recibe enabled=false: el fixture
    // es la única fuente y obtenerClienteDetalle nunca puede ejecutarse.
    expect(useClienteDetalleMock).toHaveBeenCalledWith('dc-cli-1', false)
  })
})

// —— Clientes DADOS DE BAJA en el portal (perfiles.activo=false). Decisión:
// se muestran MARCADOS pero salen de todos los totales — esconderlos borraría
// del CRM contratos que siguen existiendo; contarlos infla una cartera que el
// asesor ya no gestiona.
describe('MiCartera — cliente desactivado en el portal', () => {
  const clienteBaja = (over: Partial<ClienteBasico> = {}) =>
    cliente({ id: 'c-baja', nombre_completo: 'CLIENTE DE BAJA', activo: false, ...over })

  it('sigue en la lista pero MARCADO como inactivo (visible y anunciado)', () => {
    montar({ clientes: [clienteBaja()], contratos: [contrato({ cliente_id: 'c-baja' })] })
    expect(screen.getByText('CLIENTE DE BAJA')).toBeInTheDocument()
    expect(screen.getByText('inactivo')).toBeInTheDocument()
    // La marca entra en el nombre accesible del toggle (no es solo un color).
    expect(screen.getByRole('button', { name: /CLIENTE DE BAJA.*inactivo/s }).tagName).toBe('BUTTON')
    // Y se explica en texto, no solo con un tooltip.
    expect(screen.getByText(/no suman a los totales/)).toBeInTheDocument()
  })

  it('su capital NO cuenta en los KPIs', () => {
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja', capital: 40000, estado: 'activo' })],
    })
    // Sin cartera en gestión: tarjeta neutra, no "S/ 40,000".
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    // La cifra propia de SU fila sí se sigue viendo (el dato del cliente es real).
    expect(screen.getByText('S/ 40,000')).toBeInTheDocument()
  })

  it('el capital del cliente activo queda intacto y el conteo separa a los de baja', () => {
    montar({
      clientes: [cliente({ id: 'c-viva', nombre_completo: 'CLIENTE VIVA' }), clienteBaja()],
      contratos: [
        contrato({ id: 'k-viva', cliente_id: 'c-viva', capital: 10000 }),
        contrato({ id: 'k-baja', cliente_id: 'c-baja', capital: 40000 }),
      ],
    })
    // Solo el capital en gestión (10k), nunca 50k.
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.getByText('S/ 10k')).toBeInTheDocument()
    expect(screen.queryByText('S/ 50k')).not.toBeInTheDocument()
    // El encabezado cuadra con las filas: 1 en gestión + 1 inactivo (2 filas).
    expect(screen.getByText('1 cliente · 1 inactivo')).toBeInTheDocument()
  })

  it('"Sin asesor" (supervisión) no cuenta a los dados de baja', () => {
    montar({
      yo: { id: 'sup', rol: 'supervisor', puede_contratar: true, demo: false },
      equipo: [{ perfil_id: 'ase-1', nombre_completo: 'ASESOR UNO', activo: true }],
      clientes: [
        cliente({ id: 'c-a', nombre_completo: 'CLIENTE ALFA', asesor_perfil_id: 'ase-1', creado_por: 'ase-1' }),
        clienteBaja({ asesor_perfil_id: null, creado_por: null }),
      ],
      contratos: [],
    })
    // El único sin dueño está de baja → no hay nada que repartir.
    expect(screen.getByText(/Toda la cartera tiene dueño/)).toBeInTheDocument()
    expect(screen.queryByText(/Repártelos/)).not.toBeInTheDocument()
  })
})

// —— ALARMA DE RENOVACIÓN («Por vencer ≤30 d»). Es un AVISO, no un total: se
// calcula sobre TODA la cartera, incluidos los clientes dados de baja en el
// portal. Un contrato activo que vence en ≤30 d hay que renovarlo aunque su
// titular ya no sea cliente activo, y este chip es el único radar de renovación
// del CRM (la tabla filtra por estado de CONTRATO, no por vencimiento). Regresión
// fijada: la pasada del 2026-07-25 sacó a esos clientes de TODOS los agregados y
// el chip decía «0 · nada por vencer» con contratos venciendo esta semana.
describe('MiCartera — alarma de renovación (por vencer ≤30 d)', () => {
  /** Fecha YYYY-MM-DD a N días de HOY en hora local (TZ Lima, como la pantalla). */
  function enDias(n: number): string {
    const d = new Date()
    d.setDate(d.getDate() + n)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  /** El chip del StatStrip que rotula `label` (la Card con la clase ac-lift). */
  function chipDe(label: string): HTMLElement {
    const card = screen.getByText(label).closest('.ac-lift')
    if (!card) throw new Error(`chip “${label}” no encontrado`)
    return card as HTMLElement
  }

  const clienteBaja = (over: Partial<ClienteBasico> = {}) =>
    cliente({ id: 'c-baja', nombre_completo: 'CLIENTE DE BAJA', activo: false, ...over })

  it('cuenta el contrato por vencer de un cliente DADO DE BAJA (no dice “nada por vencer”)', () => {
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja', capital: 40000, fecha_vencimiento: enDias(10) })],
    })
    const chip = chipDe('Por vencer ≤30 d')
    expect(within(chip).getByText('1')).toBeInTheDocument()
    expect(screen.queryByText('nada por vencer')).not.toBeInTheDocument()
    // Y lo DICE: el desglose evita que la cifra parezca un descuadre.
    expect(within(chip).getByText('1 es de un cliente dado de baja')).toBeInTheDocument()
  })

  it('el dinero NO cambia: su capital sigue fuera de los totales aunque la alarma avise', () => {
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja', capital: 40000, fecha_vencimiento: enDias(10) })],
    })
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    expect(within(chipDe('Por vencer ≤30 d')).getByText('1')).toBeInTheDocument()
  })

  it('con clientes en gestión y de baja, el conteo los suma y desglosa los de baja', () => {
    montar({
      clientes: [cliente({ id: 'c-viva', nombre_completo: 'CLIENTE VIVA' }), clienteBaja()],
      contratos: [
        contrato({ id: 'k-viva', cliente_id: 'c-viva', fecha_vencimiento: enDias(20) }),
        contrato({ id: 'k-baja', cliente_id: 'c-baja', fecha_vencimiento: enDias(5) }),
      ],
    })
    const chip = chipDe('Por vencer ≤30 d')
    expect(within(chip).getByText('2')).toBeInTheDocument()
    expect(within(chip).getByText('1 es de un cliente dado de baja')).toBeInTheDocument()
  })

  it('sin nada por vencer: chip en 0 y SIN botón de filtro (no hay a dónde ir)', () => {
    montar({ contratos: [contrato({ fecha_vencimiento: enDias(200) })] })
    const chip = chipDe('Por vencer ≤30 d')
    expect(within(chip).getByText('0')).toBeInTheDocument()
    expect(within(chip).getByText('nada por vencer')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Por vencer/ })).not.toBeInTheDocument()
  })

  it('el filtro «Por vencer» deja SOLO las filas que vencen — incluida la del cliente de baja', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [cliente({ id: 'c-viva', nombre_completo: 'CLIENTE VIVA' }), clienteBaja()],
      contratos: [
        contrato({ id: 'k-viva', cliente_id: 'c-viva', fecha_vencimiento: enDias(200) }), // fuera de ventana
        contrato({ id: 'k-baja', cliente_id: 'c-baja', numero_contrato: '2026-07-000099', fecha_vencimiento: enDias(10) }),
      ],
    })
    const boton = screen.getByRole('button', { name: /Por vencer/ })
    expect(boton).toHaveAttribute('aria-pressed', 'false')
    await user.click(boton)
    expect(screen.getByRole('button', { name: /Por vencer/ })).toHaveAttribute('aria-pressed', 'true')
    // La fila que vence es la del cliente DE BAJA: sin este filtro era inalcanzable.
    expect(screen.getByText('CLIENTE DE BAJA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE VIVA')).not.toBeInTheDocument()
    // Y se auto-expande con SU contrato marcado «renovar» (palabra, no solo color).
    const sub = screen.getByText('2026-07-000099').closest('tr') as HTMLElement
    expect(within(sub).getAllByText(/· renovar/).length).toBeGreaterThan(0)
  })

  it('el filtro se puede desactivar y la cartera completa vuelve', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [cliente({ id: 'c-viva', nombre_completo: 'CLIENTE VIVA' }), clienteBaja()],
      contratos: [
        contrato({ id: 'k-viva', cliente_id: 'c-viva', fecha_vencimiento: enDias(200) }),
        contrato({ id: 'k-baja', cliente_id: 'c-baja', fecha_vencimiento: enDias(10) }),
      ],
    })
    await user.click(screen.getByRole('button', { name: /Por vencer/ }))
    expect(screen.queryByText('CLIENTE VIVA')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Por vencer/ }))
    expect(screen.getByText('CLIENTE VIVA')).toBeInTheDocument()
    expect(screen.getByText('CLIENTE DE BAJA')).toBeInTheDocument()
  })

  it('«Por vencer» + estado se componen en AND (vacío con mensaje neutral)', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja', fecha_vencimiento: enDias(10) })], // activo
    })
    await user.click(screen.getByRole('button', { name: /Por vencer/ }))
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por estado de contrato/ }), 'vencido')
    expect(screen.getByText('Ningún cliente coincide con los filtros aplicados.')).toBeInTheDocument()
  })
})

// —— Supervisión (verEquipo): filtro por asesor + indicador "Sin asesor",
// portados de la pantalla Clientes retirada en Fase 6 (parity de supervisión).
describe('MiCartera — supervisión (filtro por asesor + Sin asesor)', () => {
  const YO_SUP = { id: 'sup', rol: 'supervisor', puede_contratar: true, demo: false }
  const EQUIPO_SUP = [
    { perfil_id: 'ase-1', nombre_completo: 'ASESOR UNO', activo: true },
    { perfil_id: 'ase-2', nombre_completo: 'ASESOR DOS', activo: true },
  ]
  // Alfa→ase-1, Beta→ase-2, y DOS variantes de "Sin asesor": dueño null y dueño
  // FUERA del roster visible ('ase-fantasma', p.ej. alta de un admin del portal).
  // Ambas cuentan como sin asesor — la columna Asesor pinta '—' para las dos.
  const CLIENTES_SUP = [
    cliente({ id: 'c-a', nombre_completo: 'CLIENTE ALFA', asesor_perfil_id: 'ase-1', creado_por: 'ase-1' }),
    cliente({ id: 'c-b', nombre_completo: 'CLIENTE BETA', asesor_perfil_id: 'ase-2', creado_por: 'ase-2' }),
    cliente({ id: 'c-c', nombre_completo: 'CLIENTE SIN DUENO', asesor_perfil_id: null, creado_por: null }),
    cliente({ id: 'c-d', nombre_completo: 'CLIENTE FANTASMA', asesor_perfil_id: 'ase-fantasma', creado_por: 'ase-fantasma' }),
  ]
  const montarSup = () => montar({ yo: YO_SUP, equipo: EQUIPO_SUP, clientes: CLIENTES_SUP, contratos: [] })

  it('el chip "Sin asesor" cuenta dueño null Y dueño fuera del roster (2)', () => {
    montarSup()
    expect(screen.getByRole('combobox', { name: /Filtrar por asesor/ })).toBeInTheDocument()
    // El sub-texto "Repártelos…" es único del chip (evita chocar con la opción del Select).
    expect(screen.getByText(/Repártelos/)).toBeInTheDocument()
    // Conteo del chip = mismo criterio que el filtro: null + fuera-de-roster = 2.
    // (AnimatedValue arranca en el useState(value) inicial; su rAF no avanza en jsdom.)
    // Se ancla por el sub-texto "Repártelos" (único del chip; "Sin asesor" también
    // es una <option> del Select de asesor).
    const chip = screen.getByText(/Repártelos/).closest('.ac-lift') as HTMLElement
    expect(chip).not.toBeNull()
    expect(within(chip).getByText('2')).toBeInTheDocument()
  })

  it('filtrar por un asesor deja solo sus clientes', async () => {
    const user = userEvent.setup()
    montarSup()
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por asesor/ }), 'ase-1')
    expect(screen.getByText('CLIENTE ALFA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE BETA')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE SIN DUENO')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE FANTASMA')).not.toBeInTheDocument()
  })

  it('filtro "Sin asesor" aísla dueño null Y dueño fuera del roster', async () => {
    const user = userEvent.setup()
    montarSup()
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por asesor/ }), 'sin_asesor')
    expect(screen.getByText('CLIENTE SIN DUENO')).toBeInTheDocument()
    expect(screen.getByText('CLIENTE FANTASMA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE ALFA')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE BETA')).not.toBeInTheDocument()
  })

  it('el vendedor NO ve el filtro por asesor ni el chip "Sin asesor"', () => {
    montar() // rol vendedor por defecto
    expect(screen.queryByRole('combobox', { name: /Filtrar por asesor/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/Repártelos/)).not.toBeInTheDocument()
  })

  it('con capital en PEN Y USD, "Sin asesor" reemplaza una métrica → 4 tarjetas, no 5', () => {
    // Dos chips de capital + Por vencer + Clientes con capital = 4; sin el fix,
    // "Sin asesor" sería el 5º y rompería el grid de 4. El fix descarta la última
    // métrica NO monetaria (Clientes con capital), nunca los chips de capital.
    montar({
      yo: YO_SUP,
      equipo: EQUIPO_SUP,
      clientes: [cliente({ id: 'c-a', nombre_completo: 'CLIENTE ALFA', asesor_perfil_id: 'ase-1', creado_por: 'ase-1' })],
      contratos: [
        contrato({ cliente_id: 'c-a', moneda: 'PEN', capital: 10000, estado: 'activo' }),
        contrato({ cliente_id: 'c-a', numero_contrato: '2026-01-000002', moneda: 'USD', capital: 5000, estado: 'activo' }),
      ],
    })
    // Chips de capital intactos + Sin asesor presente; Clientes con capital cede el sitio.
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.getByText('Capital invertido · Dólares')).toBeInTheDocument()
    // 'span' distingue el label del chip de la <option> homónima del Select.
    expect(screen.getByText('Sin asesor', { selector: 'span' })).toBeInTheDocument()
    expect(screen.queryByText('Clientes con capital')).not.toBeInTheDocument()
  })

  it('vacío por asesor + estado combinados usa un mensaje neutral (no afirma "toda la cartera tiene dueño")', async () => {
    const user = userEvent.setup()
    montarSup() // hay clientes sin asesor, pero sin contratos → cualquier estado los vacía
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por asesor/ }), 'sin_asesor')
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por estado de contrato/ }), 'activo')
    expect(screen.getByText('Ningún cliente coincide con los filtros aplicados.')).toBeInTheDocument()
    expect(screen.queryByText(/toda la cartera tiene dueño/)).not.toBeInTheDocument()
  })
})

// —— Vista MÓVIL (< 768 px): la tabla se vuelve card-stack. En jsdom no hay
// matchMedia, así que estos tests lo stubbean a matches:true; los de arriba lo
// dejan undefined y por eso ven la tabla. Se restaura tras cada test.
describe('MiCartera (móvil, card-stack)', () => {
  function activarMovil() {
    vi.stubGlobal(
      'matchMedia',
      vi.fn().mockImplementation((query: string) => ({
        matches: true, // cualquier consulta "coincide" → useEsMovil = true
        media: query,
        onchange: null,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(),
      })),
    )
  }

  afterEach(() => {
    vi.unstubAllGlobals() // que el móvil no se filtre a los tests de tabla
  })

  it('pinta un card-stack (role=list) y NO la tabla', () => {
    activarMovil()
    montar()
    expect(screen.getByRole('list', { name: 'Mi cartera' })).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
  })

  it('arranca colapsada; el mismo botón expande la sub-tarjeta del contrato', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar()
    expect(screen.queryByText('2026-01-000001')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(screen.getByText('2026-01-000001')).toBeInTheDocument()
  })

  it('gating: una fila AJENA no ofrece "+ Contrato"', () => {
    activarMovil()
    montar({
      clientes: [cliente({ id: 'c-ajeno', asesor_perfil_id: 'otro', creado_por: 'otro' })],
      contratos: [contrato({ id: 'k-ajeno', cliente_id: 'c-ajeno', creado_por: 'otro' })],
    })
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /\+ Contrato/ })).not.toBeInTheDocument()
  })

  it('Ver detalle abre en móvil la ficha completa aun con la ventana vencida', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar({ clientes: [cliente({ creado_en: '2020-01-01T00:00:00.000Z' })] })

    await user.click(screen.getByRole('button', { name: 'Ver detalle' }))

    expect(screen.getByRole('dialog', { name: 'CLIENTE UNO' })).toBeInTheDocument()
    expect(screen.getByText('cliente@avance.pe')).toBeInTheDocument()
    expect(screen.getByText('00219112345678901234')).toBeInTheDocument()
    expect(screen.getByText('JUANA PEREZ')).toBeInTheDocument()
  })

  it('capital por cliente: muestra soles Y dólares del mismo cliente (jamás sumados)', () => {
    activarMovil()
    montar({
      contratos: [
        contrato({ id: 'kp', moneda: 'PEN', capital: 10000 }),
        contrato({ id: 'ku', moneda: 'USD', capital: 5000 }),
      ],
    })
    // Ambas cifras conviven en la cabecera de la tarjeta del cliente.
    expect(screen.getByText('S/ 10,000')).toBeInTheDocument()
    expect(screen.getByText('US$ 5,000')).toBeInTheDocument()
  })

  // El "Corregir cliente" de la tarjeta y el "Corregir" del contrato conviven,
  // así que se busca por nombre EXACTO 'Corregir' (no matchea "Corregir cliente").
  it('Corregir del contrato: PRESENTE si es mío y con ventana viva', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar() // contrato creado_por 'yo', reciente → ventana viva
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(screen.getByRole('button', { name: 'Corregir' })).toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si es de otro asesor (creado_por ≠ yo)', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar({ contratos: [contrato({ creado_por: 'otro' })] })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si la ventana de 5 h ya venció', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar({ contratos: [contrato({ creado_en: '2020-01-01T00:00:00.000Z' })] })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
  })

  it('la sub-tarjeta abre el detalle con un <button> NATIVO (accesible por teclado)', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar()
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    // Control de detalle = button real (no un div con role); el gating a11y del Medium.
    expect(screen.getByRole('button', { name: /Abrir detalle del contrato\s*2026-01-000001/ })).toBeInTheDocument()
  })

  it('USD-only: el capital principal del cliente es en dólares, sin "S/ 0" líder', () => {
    activarMovil()
    montar({
      clientes: [cliente({ id: 'c-usd' })],
      contratos: [contrato({ id: 'k-usd', cliente_id: 'c-usd', moneda: 'USD', capital: 50000 })],
    })
    expect(screen.getByText('US$ 50,000')).toBeInTheDocument()
    expect(screen.queryByText('S/ 0')).not.toBeInTheDocument()
  })

  it('reactivo: si el viewport cruza a móvil en caliente, la tabla se vuelve card-stack', () => {
    // matchMedia controlable: arranca desktop (no coincide) y luego "cruza" a móvil.
    let coincide = false
    const listeners = new Set<() => void>()
    vi.stubGlobal('matchMedia', () => ({
      get matches() {
        return coincide
      },
      media: '',
      onchange: null,
      addEventListener: (_: string, cb: () => void) => listeners.add(cb),
      removeEventListener: (_: string, cb: () => void) => listeners.delete(cb),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }))
    montar()
    // Desktop: hay tabla, no hay card-stack.
    expect(screen.getByRole('table')).toBeInTheDocument()
    expect(screen.queryByRole('list', { name: 'Mi cartera' })).not.toBeInTheDocument()
    // Cruza a móvil → los listeners del hook re-renderizan.
    act(() => {
      coincide = true
      for (const cb of listeners) cb()
    })
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.getByRole('list', { name: 'Mi cartera' })).toBeInTheDocument()
  })

  it('teclado: Enter en la sub-tarjeta de detalle abre el diálogo del contrato', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar()
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    const detalle = screen.getByRole('button', { name: /Abrir detalle del contrato\s*2026-01-000001/ })
    detalle.focus()
    await user.keyboard('{Enter}') // botón NATIVO → Enter dispara el clic
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  it('Corregir cliente: PRESENTE si es mío y con ventana viva', () => {
    activarMovil()
    montar() // cliente creado_por 'yo', creado_en reciente → ventana viva
    expect(screen.getByRole('button', { name: 'Corregir cliente' })).toBeInTheDocument()
  })

  it('Corregir cliente: AUSENTE si la ventana del cliente ya venció', () => {
    activarMovil()
    montar({ clientes: [cliente({ creado_en: '2020-01-01T00:00:00.000Z' })] })
    expect(screen.queryByRole('button', { name: 'Corregir cliente' })).not.toBeInTheDocument()
    // sigue siendo mío → "+ Contrato" continúa disponible.
    expect(screen.getByRole('button', { name: /\+ Contrato/ })).toBeInTheDocument()
  })

  it('Corregir cliente: AUSENTE si el cliente es de otro asesor', () => {
    activarMovil()
    montar({ clientes: [cliente({ asesor_perfil_id: 'otro', creado_por: 'otro' })] })
    expect(screen.queryByRole('button', { name: 'Corregir cliente' })).not.toBeInTheDocument()
  })
})
