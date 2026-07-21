// Tests de integración de la pantalla "Cartera" (fusión Clientes+Contratos):
// render, colapsado por defecto, expandir, moneda USD-only (dólares principal) y
// gating por fila. Mockea auth/store/datos (sin red) y usa un QueryClient limpio
// (MiCartera pide useQueryClient para las invalidaciones). Ruta REAL (demo=false):
// no hay import() dinámico de fixtures.
import { describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ClienteBasico, ContratoRow } from '@/lib/clientes-tipos'

// `yo`, clientes y contratos se pisan antes de cada montaje; los mocks los leen
// en cada llamada (no capturan el valor al definirse).
let YO: { id: string; rol: string; puede_contratar: boolean; demo: boolean } | null = null
let CLIENTES: ClienteBasico[] = []
let CONTRATOS: ContratoRow[] = []

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ equipo: [], ambito: { vendedores: [], esGlobal: false, leads: [] } }),
}))
vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  const q = <T,>(data: T) => ({ data, isPending: false, isError: false, error: null, refetch: vi.fn(), isFetching: false })
  return {
    ...actual, // conserva crmQueryKeys real
    useClientes: () => q(CLIENTES),
    useContratos: () => q(CONTRATOS),
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

function montar(over: { yo?: typeof YO; clientes?: ClienteBasico[]; contratos?: ContratoRow[] } = {}) {
  YO = over.yo ?? { id: 'yo', rol: 'vendedor', puede_contratar: true, demo: false }
  CLIENTES = over.clientes ?? [cliente()]
  CONTRATOS = over.contratos ?? [contrato()]
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
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de CLIENTE UNO/ }))
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
    await user.click(screen.getByRole('button', { name: /Colapsar los contratos de CLIENTE UNO/ }))
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
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de CLIENTE UNO/ }))
    expect(within(subFilaDe('2026-01-000001')).getByRole('button', { name: /Corregir/ })).toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si la ventana de 5 h ya venció', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ creado_en: '2020-01-01T00:00:00.000Z' })] })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de CLIENTE UNO/ }))
    expect(within(subFilaDe('2026-01-000001')).queryByRole('button', { name: /Corregir/ })).not.toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si es de otro asesor (creado_por ≠ yo)', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ creado_por: 'otro' })] })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de CLIENTE UNO/ }))
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
