// Tests de integración de la pantalla "Cartera" (fusión Clientes+Contratos):
// render, colapsado por defecto, expandir, moneda USD-only (dólares principal) y
// gating por fila. Mockea auth/store/datos (sin red) y usa un QueryClient limpio
// (MiCartera pide useQueryClient para las invalidaciones). Ruta REAL (demo=false):
// no hay import() dinámico de fixtures.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ClienteBasico, ContratoRow } from '@/lib/clientes-tipos'

// `yo`, clientes y contratos se pisan antes de cada montaje; los mocks los leen
// en cada llamada (no capturan el valor al definirse).
let YO: { id: string; rol: string; puede_contratar: boolean; demo: boolean } | null = null
let CLIENTES: ClienteBasico[] = []
let CONTRATOS: ContratoRow[] = []
let EQUIPO: Array<{ perfil_id: string; nombre_completo: string; activo: boolean }> = []

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ equipo: EQUIPO, ambito: { vendedores: [], esGlobal: false, leads: [] } }),
}))
vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  const q = <T,>(data: T) => ({ data, isPending: false, isError: false, error: null, refetch: vi.fn(), isFetching: false })
  return {
    ...actual, // conserva crmQueryKeys real
    useClientes: () => q(CLIENTES),
    useContratos: () => q(CONTRATOS),
    // ContratoDetalle usa estos tres; con data null pinta skeletons (no red, no crash).
    useContrato: () => q(null),
    useCronograma: () => q(null),
    useTitulares: () => q(null),
  }
})

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

function montar(
  over: {
    yo?: typeof YO
    clientes?: ClienteBasico[]
    contratos?: ContratoRow[]
    equipo?: Array<{ perfil_id: string; nombre_completo: string; activo: boolean }>
  } = {},
) {
  YO = over.yo ?? { id: 'yo', rol: 'vendedor', puede_contratar: true, demo: false }
  CLIENTES = over.clientes ?? [cliente()]
  CONTRATOS = over.contratos ?? [contrato()]
  EQUIPO = over.equipo ?? []
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

// —— Supervisión (verEquipo): filtro por asesor + indicador "Sin asesor",
// portados de la pantalla Clientes retirada en Fase 6 (parity de supervisión).
describe('MiCartera — supervisión (filtro por asesor + Sin asesor)', () => {
  const YO_SUP = { id: 'sup', rol: 'supervisor', puede_contratar: true, demo: false }
  const EQUIPO_SUP = [
    { perfil_id: 'ase-1', nombre_completo: 'ASESOR UNO', activo: true },
    { perfil_id: 'ase-2', nombre_completo: 'ASESOR DOS', activo: true },
  ]
  // Alfa→ase-1, Beta→ase-2, y uno SIN dueño (dueño null → cuenta como "Sin asesor").
  const CLIENTES_SUP = [
    cliente({ id: 'c-a', nombre_completo: 'CLIENTE ALFA', asesor_perfil_id: 'ase-1', creado_por: 'ase-1' }),
    cliente({ id: 'c-b', nombre_completo: 'CLIENTE BETA', asesor_perfil_id: 'ase-2', creado_por: 'ase-2' }),
    cliente({ id: 'c-c', nombre_completo: 'CLIENTE SIN DUENO', asesor_perfil_id: null, creado_por: null }),
  ]
  const montarSup = () => montar({ yo: YO_SUP, equipo: EQUIPO_SUP, clientes: CLIENTES_SUP, contratos: [] })

  it('aparece el filtro por asesor y el chip "Sin asesor" con su CTA (1 sin dueño)', () => {
    montarSup()
    expect(screen.getByRole('combobox', { name: /Filtrar por asesor/ })).toBeInTheDocument()
    // El sub-texto "Repártelos…" es único del chip (evita chocar con la opción del Select).
    expect(screen.getByText(/Repártelos/)).toBeInTheDocument()
  })

  it('filtrar por un asesor deja solo sus clientes', async () => {
    const user = userEvent.setup()
    montarSup()
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por asesor/ }), 'ase-1')
    expect(screen.getByText('CLIENTE ALFA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE BETA')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE SIN DUENO')).not.toBeInTheDocument()
  })

  it('filtro "Sin asesor" aísla los clientes sin dueño', async () => {
    const user = userEvent.setup()
    montarSup()
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por asesor/ }), 'sin_asesor')
    expect(screen.getByText('CLIENTE SIN DUENO')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE ALFA')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE BETA')).not.toBeInTheDocument()
  })

  it('el vendedor NO ve el filtro por asesor ni el chip "Sin asesor"', () => {
    montar() // rol vendedor por defecto
    expect(screen.queryByRole('combobox', { name: /Filtrar por asesor/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/Repártelos/)).not.toBeInTheDocument()
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
