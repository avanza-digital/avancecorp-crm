// Tests de integración de la pantalla "Cartera" (fusión Clientes+Contratos):
// render, colapsado por defecto, expandir, moneda USD-only (dólares principal) y
// gating por fila. Mockea auth/store/datos (sin red) y usa un QueryClient limpio
// (MiCartera pide useQueryClient para las invalidaciones). Ruta REAL (demo=false):
// no hay import() dinámico de fixtures.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { fechaLima } from '../lib/agenda-derivada'
import { MES_TODOS } from '../lib/cartera-meses'
import { agruparCartera, resumenCartera } from '../lib/cartera-vista'
import { periodoMesCalendario } from '../components/gerencia/periodo'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type {
  ClienteBasico,
  ClienteDetalle,
  ClienteFichaComercial,
  ContratoRow,
  CuentaBancariaSeleccionable,
  OperacionCartera,
  ResumenCarteraClientes,
} from '@/lib/clientes-tipos'

// `yo`, clientes y contratos se pisan antes de cada montaje; los mocks los leen
// en cada llamada (no capturan el valor al definirse).
let YO: {
  id: string
  rol: string
  rol_portal?: string | null
  puede_contratar: boolean
  demo: boolean
} | null = null
// `null` = la lectura nunca trajo datos (primera carga). Es distinto de `[]`
// (cartera vacía) y distingue el PanelError del aviso de datos rancios.
let CLIENTES: ClienteBasico[] | null = []
let CONTRATOS: ContratoRow[] | null = []
let OPERACIONES: OperacionCartera[] = []
let RESUMEN: ResumenCarteraClientes | undefined
let ERROR_RESUMEN: Error | null = null
let REFETCH_RESUMEN = vi.fn()
const lecturaResumen = vi.hoisted(() => vi.fn())
let EQUIPO: Array<{
  perfil_id: string
  nombre_completo: string
  activo: boolean
}> = []
let DETALLE: ClienteDetalle | null = null
let FICHA_COMERCIAL: ClienteFichaComercial | null = null
// Cuentas que "devuelve la RPC" en la ficha, derivadas del fixture DETALLE en
// montar(): una por moneda desde las casillas embebidas (como el perfil real).
let CUENTAS: {
  PEN: CuentaBancariaSeleccionable[]
  USD: CuentaBancariaSeleccionable[]
} = { PEN: [], USD: [] }

function cuentasDesdeDetalle(d: ClienteDetalle | null): typeof CUENTAS {
  if (d == null) return { PEN: [], USD: [] }
  const porMoneda = (moneda: 'PEN' | 'USD'): CuentaBancariaSeleccionable[] => {
    const c =
      moneda === 'USD'
        ? {
            banco: d.banco_usd,
            tipo_cuenta: d.tipo_cuenta_usd,
            numero_cuenta: d.numero_cuenta_usd,
            cci: d.cci_usd,
            titular_distinto: d.titular_distinto_usd,
            beneficiario_nombre: d.beneficiario_nombre_usd,
            beneficiario_dni: d.beneficiario_dni_usd,
          }
        : {
            banco: d.banco,
            tipo_cuenta: d.tipo_cuenta,
            numero_cuenta: d.numero_cuenta,
            cci: d.cci,
            titular_distinto: d.titular_distinto,
            beneficiario_nombre: d.beneficiario_nombre,
            beneficiario_dni: d.beneficiario_dni,
          }
    if (![c.banco, c.tipo_cuenta, c.numero_cuenta, c.cci].some((dato) => dato?.trim())) return []
    return [
      {
        cuenta_id: null,
        moneda,
        origen: 'perfil',
        es_cuenta_perfil: true,
        creada_en: null,
        banco: c.banco ?? '',
        tipo_cuenta: (c.tipo_cuenta ?? 'ahorros') as CuentaBancariaSeleccionable['tipo_cuenta'],
        numero_cuenta: c.numero_cuenta ?? '',
        cci: c.cci ?? '',
        titular_distinto: c.titular_distinto,
        beneficiario_nombre: c.beneficiario_nombre,
        beneficiario_dni: c.beneficiario_dni,
      },
    ]
  }
  return { PEN: porMoneda('PEN'), USD: porMoneda('USD') }
}
// Fallo de las lecturas CON data ya servida: es el caso que TanStack conserva
// (al fallar un refetch mantiene `data`) y el que dejaba la cartera muda.
let ERROR_CLIENTES: Error | null = null
let ERROR_CONTRATOS: Error | null = null
let ERROR_OPERACIONES: Error | null = null
let REFETCH_CLIENTES = vi.fn()
let REFETCH_CONTRATOS = vi.fn()
let REFETCH_OPERACIONES = vi.fn()

type FotoOperacionesNucleo = {
  conversion_operaciones?: {
    version: 1
    lectura: 'viva'
    completo: boolean
    desde: string
    hasta: string
    zona: 'America/Lima'
    origen_filtrado: null
    cantidad: number
    aporte_total: number
    detalle: Array<{
      operacion_id: string
      analista_id: string | null
      categoria: 'renovacion' | 'upgrade'
      periodo: string
      fecha_numerador: string
      aporte_numerador: number
    }>
  } | null
}

let METRICAS_CONVERSIONES: FotoOperacionesNucleo | undefined
let ERROR_METRICAS_CONVERSIONES: Error | null = null
const lecturaMetricasConversiones = vi.hoisted(() => vi.fn())

const cuentasHook = vi.hoisted(() => ({ llamadas: vi.fn() }))
const archivoPdf = vi.hoisted(() => ({
  abrir: vi.fn(() => ({ close: vi.fn() })),
  archivar: vi.fn(),
  archivarDemo: vi.fn(),
  asegurar: vi.fn(),
  consultar: vi.fn(),
  eliminar: vi.fn(),
  obtener: vi.fn(),
  descargar: vi.fn(),
  ver: vi.fn(),
}))

// La frontera del régimen documental se queda REAL: es lógica pura y decide qué
// ofrece el detalle del contrato que abre esta pantalla.
vi.mock('@/lib/contrato-pdf-archivo', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/contrato-pdf-archivo')>()),
  abrirVentanaContratoPdf: archivoPdf.abrir,
  archivarContratoPdfConfirmado: archivoPdf.archivar,
  asegurarContratoPdfActualizado: archivoPdf.asegurar,
  consultarEstadoContratoPdf: archivoPdf.consultar,
  ContratoPdfNoSelladoError: class ContratoPdfNoSelladoError extends Error {},
  eliminarContratoConPdf: archivoPdf.eliminar,
  obtenerContratoPdfArchivado: archivoPdf.obtener,
  descargarArchivoContratoPdf: archivoPdf.descargar,
  etiquetaEstadoContratoPdf: (estado: string) => estado,
  verArchivoContratoPdf: archivoPdf.ver,
}))

vi.mock('@/lib/contrato-pdf-demo-loader', () => ({
  archivarContratoPdfDemoHabilitado: archivoPdf.archivarDemo,
}))

// El formulario tiene su propia suite. Aquí solo ejercemos el callback con el
// que MiCartera cierra el diálogo e invalida sus dos familias de caché.
vi.mock('@/components/app/contrato-corregir', () => ({
  ContratoCorregir: ({ onGuardado }: { onGuardado: () => void }) => (
    <button type="button" onClick={onGuardado}>Confirmar corrección simulada</button>
  ),
}))

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    equipo: EQUIPO,
    ambito: { vendedores: [], esGlobal: false, leads: [] },
  }),
}))
vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  const q = <T,>(data: T, error: Error | null = null, refetch = vi.fn()) => ({
    data,
    isPending: false,
    isSuccess: error == null,
    isError: error != null,
    error,
    refetch,
    isFetching: false,
    isFetchedAfterMount: true,
  })
  return {
    ...actual, // conserva crmQueryKeys real
    useClientes: () => q(CLIENTES, ERROR_CLIENTES, REFETCH_CLIENTES),
    // Sin QueryClient en este harness: el hook real de cierres reventaría al
    // montarse. Sin datos, la sección «En cooperativas» se oculta sola.
    useCierresExternos: () => q(undefined),
    useContratos: () => q(CONTRATOS, ERROR_CONTRATOS, REFETCH_CONTRATOS),
    useOperacionesCartera: () => q(OPERACIONES, ERROR_OPERACIONES, REFETCH_OPERACIONES),
    useMetricasConversiones: (habilitada: boolean, desde: string, hasta: string, origen?: string | null) => {
      lecturaMetricasConversiones(habilitada, desde, hasta, origen)
      return q(METRICAS_CONVERSIONES, ERROR_METRICAS_CONVERSIONES)
    },
    useResumenCarteraClientes: (habilitada: boolean, actor: string) => {
      lecturaResumen(habilitada, actor)
      return q(RESUMEN, ERROR_RESUMEN, REFETCH_RESUMEN)
    },
    useClienteDetalle: vi.fn(() => q(DETALLE)),
    useClienteFichaComercial: vi.fn(() => q(FICHA_COMERCIAL)),
    useActividadesCliente: () => q([]),
    useDatosLegalesContrato: (clienteId: string) =>
      q({
        clienteId,
        faltaDomicilio: false,
        faltanCliente: [],
        faltanAnalista: [],
      }),
    // La ficha lee las cuentas del ledger vía la RPC; aquí se sirven desde
    // CUENTAS (calculado en montar() a partir del fixture DETALLE). La
    // referencia debe ser ESTABLE entre renders: el efecto de confirmación de
    // la ficha depende de `data`, y un array nuevo por render lo vuelve bucle.
    useCuentasBancariasCliente: (clienteId: string, moneda: 'PEN' | 'USD', habilitada = true) => {
      cuentasHook.llamadas(clienteId, moneda, habilitada)
      return q(CUENTAS[moneda])
    },
    // ContratoDetalle recibe la misma fila ya visible; no hay red en el harness.
    useContrato: (id: string) => q(CONTRATOS?.find((item) => item.id === id) ?? null),
    useCronograma: () => q(null),
    useTitulares: () => q([]),
  }
})

const { crmQueryKeys, useClienteDetalle } = await import('@/data/crm-queries')
const useClienteDetalleMock = vi.mocked(useClienteDetalle)
const { MiCartera } = await import('./mi-cartera')

describe('Gerencia — indicadores del resumen existente del servidor', () => {
  const yo = { id: 'g-1', rol: 'gerencia', puede_contratar: true, demo: false }
  const resumen: ResumenCarteraClientes = {
    version: 1, generado_en: new Date().toISOString(), zona: 'America/Lima', dias_alarma_renovacion: 30,
    clientes: { en_gestion: 20, de_baja: 0, con_capital: 13, sin_asesor: 4 },
    capital_activo: { pen: 777000, usd: 7000 },
    contratos: { por_estado: { activo: 17 }, por_vencer_30: 3, por_vencer_30_de_baja: 0 },
  }
  it('saldo viene del servidor; el mes sigue usando cierres y filtros, no ese saldo', async () => {
    const user = userEvent.setup()
    montar({ yo, resumen })
    expect(screen.queryByText('S/ 777k')).not.toBeInTheDocument()
    await verTodosLosMeses(user)
    expect(screen.getByText('S/ 777k')).toBeInTheDocument()
    expect(screen.getByText('US$ 7k')).toBeInTheDocument()
    expect(screen.getByText('20 clientes')).toBeInTheDocument()
    const sinAnalista = screen.getByText('Sin analista', { selector: 'span' }).closest('.ac-lift')!
    expect(within(sinAnalista as HTMLElement).getByText('1')).toBeInTheDocument()
    expect(within(sinAnalista as HTMLElement).queryByText('4')).not.toBeInTheDocument()
    expect(lecturaResumen).toHaveBeenLastCalledWith(true, 'g-1')
  })
  it('error sin resumen no muestra ceros ni bloquea la lista confirmada', () => {
    montar({ yo, resumen: null, errorResumen: new Error('sin red') })
    expect(screen.getByText(/Los indicadores de Cartera no están disponibles/)).toBeInTheDocument()
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.queryByText('sin capital vigente aún')).not.toBeInTheDocument()
    expect(screen.queryByText('Clientes que cerraron')).not.toBeInTheDocument()
  })
  it('carga sin resumen es espera, no un saldo cero', () => {
    montar({ yo, resumen: null })
    expect(screen.getByText('Consultando los indicadores de Cartera…')).toHaveAttribute('role', 'status')
    expect(screen.queryByText('Clientes que cerraron')).not.toBeInTheDocument()
  })
  it('fallo de refresco conserva el último resumen, avisa y ofrece reintento', async () => {
    const user = userEvent.setup()
    montar({ yo, resumen, errorResumen: new Error('falló refresco') })
    await verTodosLosMeses(user)
    expect(screen.getByText('S/ 777k')).toBeInTheDocument()
    expect(screen.getByText(/Se muestra el último resumen confirmado/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /indicadores de Cartera/i }))
    expect(REFETCH_RESUMEN).toHaveBeenCalledOnce()
  })
  it('no oculta contratos cuyo cliente no llegó en la otra lectura', () => {
    montar({ yo, resumen, clientes: [], contratos: [contrato()] })
    expect(screen.getByText(/Los clientes y contratos no forman una lectura completa/)).toBeInTheDocument()
    expect(screen.queryByText('Clientes que cerraron')).not.toBeInTheDocument()
  })
  it('no conecta el resumen global a la cartera de un analista', () => {
    montar()
    expect(lecturaResumen).toHaveBeenLastCalledWith(false, 'yo')
  })
  it('un resumen confirmado vacío sí muestra cero clientes', () => {
    montar({ yo, clientes: [], contratos: [], resumen: {
      ...resumen, clientes: { en_gestion: 0, de_baja: 0, con_capital: 0, sin_asesor: 0 },
      capital_activo: { pen: 0, usd: 0 },
      contratos: { por_estado: {}, por_vencer_30: 0, por_vencer_30_de_baja: 0 },
    } })
    expect(screen.getByText('0 clientes')).toBeInTheDocument()
    expect(screen.getByText('Aún no hay clientes en la cartera.')).toBeInTheDocument()
    expect(screen.queryByText(/no están disponibles/)).not.toBeInTheDocument()
  })
  it('si desaparece el resumen, el filtro de vencimientos no inventa cero y permite salir', async () => {
    const user = userEvent.setup()
    const vista = montar({ yo, resumen })
    const filtro = screen.getByRole('button', { name: 'Por vencer ≤30 d (3)' })
    await user.click(filtro)
    RESUMEN = undefined
    vista.rerender(<QueryClientProvider client={vista.queryClient}><MiCartera /></QueryClientProvider>)
    expect(filtro).toHaveTextContent('Por vencer ≤30 d (—)')
    expect(filtro).toBeEnabled()
    await user.click(filtro)
    expect(filtro).toHaveAttribute('aria-pressed', 'false')
    expect(filtro).toBeDisabled()
  })
})

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

/** Fecha de cierre por defecto: el día (Lima) en que se registró. Un `creado_en`
 *  ilegible se copia tal cual, para que el contrato caiga en el cubo «sin fecha»
 *  en vez de reventar el fixture. */
function cierrePorDefecto(creadoEn: string): string {
  const ms = Date.parse(creadoEn)
  return Number.isNaN(ms) ? creadoEn : fechaLima(ms)
}

function contrato(over: Partial<ContratoRow> = {}): ContratoRow {
  // Por defecto el contrato se cierra el día en que se registra (Lima): es el
  // caso corriente, y así los tests que mueven `creado_en` para colocar un
  // contrato en un mes siguen diciendo lo mismo ahora que el bloque va por
  // fecha de CIERRE. Quien quiera separarlas pasa `fecha_cierre_comercial`.
  const creadoEn = over.creado_en ?? new Date().toISOString()
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
    fecha_cierre_comercial: cierrePorDefecto(creadoEn),
    notas_internas: null,
    creado_por: 'yo',
    creado_en: creadoEn,
    producto_condicion_id: '10000000-0000-4000-8000-000000000001',
    producto_id: '20000000-0000-4000-8000-000000000001',
    producto_codigo: 'RENTA-BASE',
    producto_version_id: '30000000-0000-4000-8000-000000000001',
    producto_version: 1,
    producto_nombre: 'Plan base',
    producto_version_estado: 'publicada',
    ...over,
  }
}

function operacion(over: Partial<OperacionCartera> = {}): OperacionCartera {
  return {
    id: 'op-1',
    cliente_id: 'c-1',
    vendedor_id: 'yo',
    tipo: 'renovacion',
    contrato_origen_id: 'k-origen',
    contrato_nuevo_id: 'k-renovado',
    fecha_operacion: '2026-08-24',
    periodo: '2026-08-01',
    moneda: 'PEN',
    capital_renovado: 50_000,
    capital_adicional: 10_000,
    elegible_conversion: true,
    desglose_completo: true,
    fuente: 'flujo_cartera',
    creado_por: 'yo',
    creado_en: '2026-08-24T15:00:00.000Z',
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
    telefono: '999111222',
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: '2026-07-15T12:00:00.000Z',
    banca_visible: true,
    cuentas_bancarias_visibles: true,
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
    clientes?: ClienteBasico[] | null
    contratos?: ContratoRow[] | null
    operaciones?: OperacionCartera[]
    detalle?: ClienteDetalle | null
    equipo?: Array<{
      perfil_id: string
      nombre_completo: string
      activo: boolean
    }>
    errorClientes?: Error | null
    errorContratos?: Error | null
    errorOperaciones?: Error | null
    metricasConversiones?: FotoOperacionesNucleo | null
    errorMetricasConversiones?: Error | null
    resumen?: ResumenCarteraClientes | null
    errorResumen?: Error | null
  } = {},
) {
  YO = over.yo ?? {
    id: 'yo',
    rol: 'vendedor',
    puede_contratar: true,
    demo: false,
  }
  CLIENTES = over.clientes === undefined ? [cliente()] : over.clientes
  CONTRATOS = over.contratos === undefined ? [contrato()] : over.contratos
  OPERACIONES = over.operaciones ?? []
  ERROR_CLIENTES = over.errorClientes ?? null
  ERROR_CONTRATOS = over.errorContratos ?? null
  ERROR_OPERACIONES = over.errorOperaciones ?? null
  METRICAS_CONVERSIONES = over.metricasConversiones === null ? undefined : over.metricasConversiones
  ERROR_METRICAS_CONVERSIONES = over.errorMetricasConversiones ?? null
  lecturaMetricasConversiones.mockClear()
  ERROR_RESUMEN = over.errorResumen ?? null
  // Sólo fixture del servidor para las pruebas heredadas; producción no usa
  // este cálculo. Los casos nuevos inyectan respuestas distintas del listado.
  const base = resumenCartera(agruparCartera(CLIENTES ?? [], CONTRATOS ?? []))
  RESUMEN = over.resumen === null ? undefined : over.resumen ?? {
    version: 1, generado_en: new Date().toISOString(), zona: 'America/Lima', dias_alarma_renovacion: 30,
    clientes: { en_gestion: base.totalClientes, de_baja: (CLIENTES?.length ?? 0) - base.totalClientes,
      con_capital: base.clientesConCapital, sin_asesor: 0 },
    capital_activo: { pen: base.capitalActivoPen, usd: base.capitalActivoUsd },
    contratos: { por_estado: {}, por_vencer_30: base.porVencer30, por_vencer_30_de_baja: base.porVencer30DeBaja },
  }
  REFETCH_RESUMEN = vi.fn()
  REFETCH_CLIENTES = vi.fn()
  REFETCH_CONTRATOS = vi.fn()
  REFETCH_OPERACIONES = vi.fn()
  EQUIPO = over.equipo ?? []
  // `null` es un caso de prueba válido (skeleton/error); solo `undefined`
  // significa "usa la ficha por defecto".
  DETALLE = over.detalle === undefined ? detalle() : over.detalle
  FICHA_COMERCIAL =
    DETALLE == null
      ? null
      : {
          ...DETALLE,
          activo: CLIENTES?.find((cliente) => cliente.id === DETALLE?.id)?.activo ?? true,
        }
  CUENTAS = cuentasDesdeDetalle(DETALLE)
  archivoPdf.consultar.mockReset().mockResolvedValue({ estado: 'sellado' })
  archivoPdf.asegurar.mockReset().mockResolvedValue({ estado: 'sellado' })
  archivoPdf.eliminar.mockReset().mockResolvedValue({
    contratoId: CONTRATOS?.[0]?.id ?? 'k-1',
    archivosEliminados: 2,
  })
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return Object.assign(render(
    <QueryClientProvider client={qc}>
      <MiCartera />
    </QueryClientProvider>,
  ), { queryClient: qc })
}

/**
 * La pantalla arranca filtrada por el MES EN CURSO, así que un contrato de otro
 * mes no está en la lista hasta pedir la cartera entera. Es exactamente lo que
 * tiene que hacer una persona, y por eso los tests de contratos viejos pasan
 * por aquí en vez de relajar la aserción.
 */
async function verTodosLosMeses(user: ReturnType<typeof userEvent.setup>) {
  await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por mes/ }), 'todos')
}

function diferida<T>() {
  let resolver!: (valor: T) => void
  const promesa = new Promise<T>((resolve) => {
    resolver = resolve
  })
  return { promesa, resolver }
}

async function abrirAltaContratoDemo(user: ReturnType<typeof userEvent.setup>) {
  // La pantalla arranca en el MES EN CURSO y los bloques van por fecha de
  // CIERRE: el contrato de ROSA se cerró hace meses (aunque se registrara hace
  // dos horas), así que hay que abrir la cartera entera para verla. Es
  // exactamente lo que haría el analista, y por eso el paso vive aquí.
  await user.selectOptions(await screen.findByLabelText('Filtrar por mes de cierre'), MES_TODOS)
  const nombre = await screen.findByText('ROSA MERCEDES AGUILAR VENTURA')
  const filaCliente = nombre.closest('tr')
  if (!filaCliente) throw new Error('fila del cliente demo no encontrada')
  await user.click(within(filaCliente).getByRole('button', { name: 'Registrar nueva inversión' }))
  expect(screen.getByRole('dialog', { name: /Crear contrato de ROSA MERCEDES/ })).toBeInTheDocument()
}

async function completarAltaContratoDemo(user: ReturnType<typeof userEvent.setup>, sufijo: string) {
  await user.selectOptions(screen.getByLabelText('Categoría'), 'nuevo')
  await user.type(screen.getByLabelText('Capital'), '10000')
  await user.type(screen.getByLabelText('N° de contrato'), sufijo)
  await user.click(screen.getByRole('radio', { name: /BCP/ }))
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
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(screen.getByText('2026-01-000001')).toBeInTheDocument()
  })

  it('USD-only: muestra la tarjeta de Dólares y NO la de Soles (dólares principal)', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [cliente({ id: 'c-usd' })],
      contratos: [
        contrato({
          id: 'k-usd',
          cliente_id: 'c-usd',
          moneda: 'USD',
          capital: 50000,
        }),
      ],
    })
    // Las tarjetas de dinero solo miden capital VIVO en la vista global; con un
    // mes puesto miden lo CERRADO y cambian de rótulo.
    await verTodosLosMeses(user)
    expect(screen.getByText('Capital invertido · Dólares')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
  })

  it('gating: la fila propia ofrece "Registrar nueva inversión"', () => {
    montar()
    expect(screen.getByRole('button', { name: 'Registrar nueva inversión' })).toBeInTheDocument()
  })

  it('permite iniciar una gestión comercial directamente sobre el cliente', async () => {
    const user = userEvent.setup()
    montar()

    await user.click(screen.getByRole('button', { name: 'Gestionar' }))

    expect(screen.getByRole('dialog', { name: 'Gestionar a CLIENTE UNO' })).toBeInTheDocument()
    expect(screen.getByText(/llamada, WhatsApp, cita u otra tarea comercial/i)).toBeInTheDocument()
  })

  it('Gestionar depende de escritura y cartera propia, no de puede_contratar', async () => {
    const user = userEvent.setup()
    montar({
      yo: {
        id: 'yo',
        rol: 'vendedor',
        puede_contratar: false,
        demo: false,
      },
      contratos: [contrato({ fecha_vencimiento: '2000-01-01' })],
    })

    expect(screen.getByRole('button', { name: 'Gestionar' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver detalle' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nuevo cliente' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aumentar inversión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()

    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    const filaContrato = screen.getByLabelText('Abrir detalle del contrato 2026-01-000001').closest('tr')!
    expect(within(filaContrato).queryByRole('button', { name: 'Renovar' })).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Gestionar' }))
    expect(screen.getByRole('dialog', { name: 'Gestionar a CLIENTE UNO' })).toBeInTheDocument()
  })

  it('abre el alta de upgrade con la categoría fija', async () => {
    const user = userEvent.setup()
    montar()

    await user.click(screen.getByRole('button', { name: 'Aumentar inversión' }))

    expect(screen.getByRole('dialog', { name: 'Registrar upgrade de CLIENTE UNO' })).toBeInTheDocument()
    expect(screen.getAllByText('Upgrade').length).toBeGreaterThan(0)
    expect(screen.queryByRole('option', { name: 'Renovación' })).not.toBeInTheDocument()
  })

  it('habilita Renovar solo al llegar la fecha fin y abre el puente de capital', async () => {
    const user = userEvent.setup()
    montar({
      contratos: [
        contrato({
          fecha_vencimiento: '2000-01-01',
          capital: 50_000,
        }),
      ],
    })
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )

    await user.click(
      within(subFilaDe('2026-01-000001')).getByRole('button', {
        name: 'Renovar',
      }),
    )

    expect(screen.getByRole('dialog', { name: 'Renovar 2026-01-000001' })).toBeInTheDocument()
    expect(screen.getByText(/Puente de capital/)).toBeInTheDocument()
    expect(screen.getByLabelText('Contrato anterior')).toHaveValue('50000')
    expect(screen.getByLabelText('Capital renovado')).toHaveValue('50000')
    expect(screen.getByLabelText('Capital adicional')).toHaveValue('0')
    expect(screen.getByText(/el adicional queda separado/i)).toBeInTheDocument()
  })

  it('no permite renovar anticipadamente un contrato cuya fecha fin aún no llega', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ fecha_vencimiento: '2099-12-31' })] })
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )

    expect(
      within(subFilaDe('2026-01-000001')).queryByRole('button', {
        name: 'Renovar',
      }),
    ).not.toBeInTheDocument()
  })

  it('muestra renovado + adicional sin prometer una conversión por cada registro', async () => {
    const user = userEvent.setup()
    montar({
      contratos: [
        contrato({
          id: 'k-origen',
          numero_contrato: '2025-01-000010',
          capital: 50_000,
          estado: 'renovado',
        }),
        contrato({
          id: 'k-renovado',
          numero_contrato: '2026-01-000011',
          capital: 60_000,
          categoria: 'renovacion',
        }),
      ],
      operaciones: [operacion()],
    })
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )

    const fila = subFilaDe('2026-01-000011')
    expect(within(fila).getByText(/renovado/)).toBeInTheDocument()
    expect(within(fila).getByText(/adicional/)).toBeInTheDocument()
    expect(within(fila).getByText(/renovación registrada/)).toBeInTheDocument()
    expect(within(fila).queryByText(/1 conversión/)).not.toBeInTheDocument()
  })

  it.each([true, false])('un upgrade elegible=%s informa elegibilidad sin certificar aporte efectivo', async (elegible) => {
    const user = userEvent.setup()
    montar({
      contratos: [contrato({ id: 'k-upgrade' })],
      operaciones: [operacion({
        tipo: 'upgrade',
        contrato_nuevo_id: 'k-upgrade',
        elegible_conversion: elegible,
      })],
    })
    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))
    const fila = subFilaDe('2026-01-000001')
    expect(within(fila).getByText(elegible
      ? 'Upgrade · elegible para conversión · aporte sujeto al núcleo'
      : 'Upgrade · no elegible para conversión')).toBeInTheDocument()
    expect(within(fila).queryByText(/suma conversión|1 conversión/)).not.toBeInTheDocument()
    expect(lecturaMetricasConversiones).toHaveBeenLastCalledWith(false, expect.any(String), expect.any(String), undefined)
  })

  it('Gerencia muestra el aporte exacto de una renovación seleccionada por el núcleo vivo', async () => {
    const user = userEvent.setup()
    const hoy = fechaLima(Date.now())
    const mes = hoy.slice(0, 7)
    const periodo = periodoMesCalendario(mes, Date.now())
    montar({
      yo: { id: 'gerencia', rol: 'gerencia', puede_contratar: true, demo: false },
      contratos: [contrato({
        id: 'k-renovado',
        numero_contrato: '2026-09-000015',
        categoria: 'renovacion',
        capital: 60_000,
        fecha_cierre_comercial: hoy,
      })],
      operaciones: [operacion({
        id: 'op-renovacion-seleccionada',
        contrato_nuevo_id: 'k-renovado',
        periodo: periodo.desde,
        fecha_operacion: hoy,
      })],
      metricasConversiones: {
        conversion_operaciones: {
          version: 1,
          lectura: 'viva',
          completo: true,
          desde: periodo.desde,
          hasta: periodo.hasta,
          zona: 'America/Lima',
          origen_filtrado: null,
          cantidad: 1,
          aporte_total: 0.15,
          detalle: [{
            operacion_id: 'op-renovacion-seleccionada',
            analista_id: 'yo',
            categoria: 'renovacion',
            periodo: periodo.desde,
            fecha_numerador: hoy,
            aporte_numerador: 0.15,
          }],
        },
      },
    })

    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))

    expect(within(subFilaDe('2026-09-000015')).getByText('Aportó ×0.15 al núcleo vivo')).toBeInTheDocument()
    expect(lecturaMetricasConversiones).toHaveBeenLastCalledWith(
      true,
      periodo.desde,
      periodo.hasta,
      undefined,
    )
  })

  it('Gerencia distingue una operación ausente de un mapa N3 completo', async () => {
    const user = userEvent.setup()
    const hoy = fechaLima(Date.now())
    const mes = hoy.slice(0, 7)
    const periodo = periodoMesCalendario(mes, Date.now())
    montar({
      yo: { id: 'gerencia', rol: 'gerencia', puede_contratar: true, demo: false },
      contratos: [contrato({
        id: 'k-upgrade-no-seleccionado',
        numero_contrato: '2026-09-000016',
        fecha_cierre_comercial: hoy,
      })],
      operaciones: [operacion({
        id: 'op-upgrade-no-seleccionado',
        tipo: 'upgrade',
        contrato_origen_id: null,
        contrato_nuevo_id: 'k-upgrade-no-seleccionado',
        periodo: periodo.desde,
        fecha_operacion: hoy,
      })],
      metricasConversiones: {
        conversion_operaciones: {
          version: 1,
          lectura: 'viva',
          completo: true,
          desde: periodo.desde,
          hasta: periodo.hasta,
          zona: 'America/Lima',
          origen_filtrado: null,
          cantidad: 0,
          aporte_total: 0,
          detalle: [],
        },
      },
    })

    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))

    expect(within(subFilaDe('2026-09-000016')).getByText(
      'Upgrade · No aportó: el núcleo no la seleccionó',
    )).toBeInTheDocument()
  })

  it('un mapa N3 completo conserva la causa explícita de una operación no elegible', async () => {
    const user = userEvent.setup()
    const hoy = fechaLima(Date.now())
    const mes = hoy.slice(0, 7)
    const periodo = periodoMesCalendario(mes, Date.now())
    montar({
      yo: { id: 'gerencia', rol: 'gerencia', puede_contratar: true, demo: false },
      contratos: [contrato({
        id: 'k-upgrade-no-elegible',
        numero_contrato: '2026-09-000018',
        fecha_cierre_comercial: hoy,
      })],
      operaciones: [operacion({
        id: 'op-upgrade-no-elegible',
        tipo: 'upgrade',
        contrato_origen_id: null,
        contrato_nuevo_id: 'k-upgrade-no-elegible',
        periodo: periodo.desde,
        fecha_operacion: hoy,
        elegible_conversion: false,
      })],
      metricasConversiones: {
        conversion_operaciones: {
          version: 1,
          lectura: 'viva',
          completo: true,
          desde: periodo.desde,
          hasta: periodo.hasta,
          zona: 'America/Lima',
          origen_filtrado: null,
          cantidad: 0,
          aporte_total: 0,
          detalle: [],
        },
      },
    })

    await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))

    const fila = subFilaDe('2026-09-000018')
    expect(within(fila).getByText('Upgrade · no elegible para conversión')).toBeInTheDocument()
    expect(within(fila).queryByText(/No aportó:/)).not.toBeInTheDocument()
  })

  it.each(['sin_bloque', 'error', 'rango_distinto', 'incompleto', 'otro_periodo'] as const)(
    'Gerencia conserva el estado neutral cuando N3 queda desconocido: %s',
    async (caso) => {
      const user = userEvent.setup()
      const hoy = fechaLima(Date.now())
      const mes = hoy.slice(0, 7)
      const periodo = periodoMesCalendario(mes, Date.now())
      const operacionId = `op-neutral-${caso}`
      const foto: FotoOperacionesNucleo = {
        conversion_operaciones: {
          version: 1,
          lectura: 'viva',
          completo: caso !== 'incompleto',
          desde: periodo.desde,
          hasta: caso === 'rango_distinto' ? '1999-01-31' : periodo.hasta,
          zona: 'America/Lima',
          origen_filtrado: null,
          cantidad: 1,
          aporte_total: 1,
          detalle: [{
            operacion_id: operacionId,
            analista_id: 'yo',
            categoria: 'upgrade',
            periodo: periodo.desde,
            fecha_numerador: hoy,
            aporte_numerador: 1,
          }],
        },
      }
      montar({
        yo: { id: 'gerencia', rol: 'gerencia', puede_contratar: true, demo: false },
        contratos: [contrato({
          id: `k-${caso}`,
          numero_contrato: '2026-09-000017',
          fecha_cierre_comercial: hoy,
        })],
        operaciones: [operacion({
          id: operacionId,
          tipo: 'upgrade',
          contrato_origen_id: null,
          contrato_nuevo_id: `k-${caso}`,
          periodo: caso === 'otro_periodo' ? '2000-01-01' : periodo.desde,
          fecha_operacion: hoy,
        })],
        metricasConversiones: caso === 'sin_bloque' ? null : foto,
        errorMetricasConversiones: caso === 'error' ? new Error('sin red') : null,
      })

      await user.click(screen.getByRole('button', { name: /Expandir los contratos de\s*CLIENTE UNO/ }))

      const fila = subFilaDe('2026-09-000017')
      expect(within(fila).getByText('Upgrade · elegible para conversión · aporte sujeto al núcleo')).toBeInTheDocument()
      expect(within(fila).queryByText(/Aportó ×|No aportó:/)).not.toBeInTheDocument()
    },
  )

  it('explica a Gerencia qué indicadores siguen los filtros y cuáles mantienen toda la cartera', async () => {
    const user = userEvent.setup()
    montar({ yo: { id: 'gerencia', rol: 'gerencia', puede_contratar: true, demo: false } })
    expect(screen.getByText('Capital y clientes que cerraron: mes y filtros seleccionados. Por vencer y Sin analista: toda la cartera.')).toBeInTheDocument()

    await verTodosLosMeses(user)
    expect(screen.getByText('Los indicadores muestran toda la cartera. Los filtros sólo cambian el listado.')).toBeInTheDocument()
    expect(screen.queryByText(/Capital y clientes que cerraron: mes y filtros/)).not.toBeInTheDocument()
  })

  it('no inventa el desglose de una renovación histórica', async () => {
    const user = userEvent.setup()
    montar({
      contratos: [contrato({ id: 'k-renovado', categoria: 'renovacion' })],
      operaciones: [
        operacion({
          contrato_origen_id: null,
          capital_renovado: null,
          capital_adicional: null,
          desglose_completo: false,
          fuente: 'backfill_agosto_2026',
        }),
      ],
    })
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )

    expect(screen.getByText('Renovación histórica · desglose pendiente')).toBeInTheDocument()
  })

  it('gating: una fila AJENA no ofrece acciones', () => {
    montar({
      clientes: [
        cliente({
          id: 'c-ajeno',
          asesor_perfil_id: 'otro',
          creado_por: 'otro',
        }),
      ],
      contratos: [contrato({ id: 'k-ajeno', cliente_id: 'c-ajeno', creado_por: 'otro' })],
    })
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Gestionar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Ver detalle' })).not.toBeInTheDocument()
  })

  it('Gerencia opera clientes y contratos ajenos aunque su ventana haya vencido', async () => {
    const user = userEvent.setup()
    montar({
      yo: {
        id: 'gerencia',
        rol: 'gerencia',
        puede_contratar: true,
        demo: false,
      },
      clientes: [
        cliente({
          id: 'c-ajeno',
          asesor_perfil_id: 'asesor-1',
          creado_por: 'asesor-1',
          creado_en: '2020-01-01T00:00:00.000Z',
        }),
      ],
      contratos: [
        contrato({
          id: 'k-ajeno',
          cliente_id: 'c-ajeno',
          creado_por: 'asesor-1',
          creado_en: '2020-01-01T00:00:00.000Z',
        }),
      ],
      equipo: [{ perfil_id: 'asesor-1', nombre_completo: 'ANALISTA UNO', activo: true }],
    })
    await verTodosLosMeses(user) // el contrato es de 2020

    expect(screen.getByRole('button', { name: 'Nuevo cliente' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver detalle' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Corregir' })).toHaveAttribute(
      'title',
      'Corregir datos del cliente · autorización global de Gerencia',
    )
    expect(screen.getByRole('button', { name: 'Registrar nueva inversión' })).toBeInTheDocument()

    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(
      within(subFilaDe('2026-01-000001')).getByRole('button', {
        name: 'Corregir',
      }),
    ).toBeInTheDocument()
    expect(screen.queryByText('Bloqueado')).not.toBeInTheDocument()
  })

  it('Gerencia conserva la gestión global sin puede_contratar, pero no las acciones contractuales', async () => {
    const user = userEvent.setup()
    montar({
      yo: {
        id: 'gerencia',
        rol: 'gerencia',
        puede_contratar: false,
        demo: false,
      },
      clientes: [
        cliente({
          id: 'c-ajeno',
          asesor_perfil_id: 'asesor-1',
          creado_por: 'asesor-1',
        }),
      ],
      contratos: [contrato({ id: 'k-ajeno', cliente_id: 'c-ajeno', creado_por: 'asesor-1' })],
      equipo: [{ perfil_id: 'asesor-1', nombre_completo: 'ANALISTA UNO', activo: true }],
    })

    expect(screen.getByRole('button', { name: 'Gestionar' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver detalle' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nuevo cliente' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aumentar inversión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Gestionar' }))
    expect(screen.getByRole('dialog', { name: 'Gestionar a CLIENTE UNO' })).toBeInTheDocument()
  })

  it('Directorio conserva Ver detalle pero ninguna escritura aunque un dato externo diga que puede contratar', () => {
    montar({
      yo: {
        id: 'directorio',
        rol: 'directorio',
        puede_contratar: true,
        demo: false,
      },
      clientes: [cliente({ asesor_perfil_id: 'otro', creado_por: 'otro' })],
    })

    expect(screen.queryByRole('button', { name: 'Nuevo cliente' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver detalle' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Gestionar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Corregir cliente' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aumentar inversión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()
    const encabezados = screen.getAllByRole('columnheader')
    expect(within(encabezados.at(-1)!).getByText('Acciones')).toBeInTheDocument()
    const fila = screen.getByText('CLIENTE UNO').closest('tr')!
    expect(within(fila).getAllByRole('cell')).toHaveLength(encabezados.length)
  })

  it('muestra todos los datos del cliente propio, aun con la ventana de corrección vencida', async () => {
    const user = userEvent.setup()
    montar({ clientes: [cliente({ creado_en: '2020-01-01T00:00:00.000Z' })] })

    await user.click(screen.getByRole('button', { name: 'Ver detalle' }))

    expect(screen.getByRole('dialog', { name: 'CLIENTE UNO' })).toBeInTheDocument()
    expect(screen.getByText('Capital vigente')).toBeInTheDocument()
    expect(screen.getByText('Inversiones y contratos')).toBeInTheDocument()
    expect(screen.getByText('Historial de gestiones')).toBeInTheDocument()
    expect(screen.getByText('Información del cliente')).toBeInTheDocument()
    expect(screen.getByText('cliente@avance.pe')).toBeInTheDocument()
    expect(screen.getByText('Cuenta para recibir pagos en soles')).toBeInTheDocument()
    expect(screen.getByText('00219112345678901234')).toBeInTheDocument()
    expect(screen.getByText('Cuenta para recibir pagos en dólares')).toBeInTheDocument()
    expect(screen.getByText('JUANA PEREZ')).toBeInTheDocument()
  })

  it('vuelve de Gestionar a la misma Ficha 360 y enfoca Seguimiento', async () => {
    const user = userEvent.setup()
    montar()

    await user.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const ficha = screen.getByRole('dialog', { name: 'CLIENTE UNO' })
    await user.click(within(ficha).getByRole('button', { name: 'Agendar seguimiento' }))
    await user.click(screen.getByRole('button', { name: 'Cancelar' }))

    expect(screen.getByRole('dialog', { name: 'CLIENTE UNO' })).toBeInTheDocument()
    const siguienteContacto = screen.getByRole('heading', { name: 'Seguimiento' }).closest('section')
    expect(siguienteContacto).not.toBeNull()
    await waitFor(() => expect(siguienteContacto).toHaveFocus())
  })

  it('vuelve del detalle de contrato a la misma Ficha 360 y al contrato de origen', async () => {
    const user = userEvent.setup()
    montar()

    await user.click(screen.getByRole('button', { name: 'Ver detalle' }))
    const ficha = screen.getByRole('dialog', { name: 'CLIENTE UNO' })
    await user.click(within(ficha).getByRole('button', { name: 'Ver contrato 2026-01-000001' }))
    const detalleContrato = screen.getByRole('dialog', { name: 'Contrato 2026-01-000001' })
    await user.click(within(detalleContrato).getByRole('button', { name: 'Cerrar' }))

    expect(screen.getByRole('dialog', { name: 'CLIENTE UNO' })).toBeInTheDocument()
    const contratoOrigen = screen.getByRole('button', { name: 'Ver contrato 2026-01-000001' })
    await waitFor(() => expect(contratoOrigen).toHaveFocus())
  })

  it('con filtro activo el grupo se auto-expande y AÚN se puede colapsar (botón real)', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(screen.getByRole('textbox', { name: /Buscar en la cartera/ }), '000001')
    // Auto-expandido por coincidencia de N° de contrato → la sub-fila es visible.
    expect(screen.getByText('2026-01-000001')).toBeInTheDocument()
    // El botón dice "Colapsar" y de verdad colapsa (no es un override que mienta).
    await user.click(
      screen.getByRole('button', {
        name: /Colapsar los contratos de\s*CLIENTE UNO/,
      }),
    )
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
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(
      within(subFilaDe('2026-01-000001')).getByRole('button', {
        name: /Corregir/,
      }),
    ).toBeInTheDocument()
  })

  it('abre la corrección aunque ya exista PDF: el servidor creará una nueva revisión', async () => {
    const user = userEvent.setup()
    const { queryClient } = montar()
    const invalidar = vi.spyOn(queryClient, 'invalidateQueries')
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    await user.click(
      within(subFilaDe('2026-01-000001')).getByRole('button', {
        name: /Corregir/,
      }),
    )

    expect(
      await screen.findByRole('dialog', {
        name: 'Corregir contrato 2026-01-000001',
      }),
    ).toBeInTheDocument()
    expect(archivoPdf.consultar).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: 'Confirmar corrección simulada' }))
    await waitFor(() => {
      expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.contratos() })
      expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.metricas() })
    })
  })

  it('Admin elimina desde el detalle solo tras doble confirmación y por la Edge', async () => {
    const user = userEvent.setup()
    const { queryClient } = montar({
      yo: {
        id: 'admin',
        rol: 'gerencia',
        rol_portal: 'admin',
        puede_contratar: true,
        demo: false,
      },
    })
    const invalidar = vi.spyOn(queryClient, 'invalidateQueries')
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    await user.click(screen.getByText('2026-01-000001'))
    await user.click(await screen.findByRole('button', { name: 'Eliminar contrato' }))

    expect(archivoPdf.eliminar).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: /Sí, eliminar contrato y PDF/i }))

    await vi.waitFor(() => expect(archivoPdf.eliminar).toHaveBeenCalledWith('k-1'))
    expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.contratos() })
    expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.metricas() })
  })

  it('Corregir del contrato: AUSENTE si la ventana de 5 h ya venció', async () => {
    const user = userEvent.setup()
    montar({
      contratos: [contrato({ creado_en: '2020-01-01T00:00:00.000Z' })],
    })
    await verTodosLosMeses(user) // el contrato es de 2020
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(
      within(subFilaDe('2026-01-000001')).queryByRole('button', {
        name: /Corregir/,
      }),
    ).not.toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si es de otro analista (creado_por ≠ yo)', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ creado_por: 'otro' })] })
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(
      within(subFilaDe('2026-01-000001')).queryByRole('button', {
        name: /Corregir/,
      }),
    ).not.toBeInTheDocument()
  })

  it('tarjetas de moneda — solo PEN: Soles presente, Dólares ausente', async () => {
    const user = userEvent.setup()
    montar() // contrato en PEN
    await verTodosLosMeses(user)
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Dólares')).not.toBeInTheDocument()
  })

  it('tarjetas de moneda — PEN y USD: ambas presentes', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [cliente({ id: 'a' }), cliente({ id: 'b' })],
      contratos: [
        contrato({ id: 'kp', cliente_id: 'a', moneda: 'PEN', capital: 10000 }),
        contrato({ id: 'ku', cliente_id: 'b', moneda: 'USD', capital: 5000 }),
      ],
    })
    await verTodosLosMeses(user)
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.getByText('Capital invertido · Dólares')).toBeInTheDocument()
  })

  it('tarjetas de moneda — sin capital activo: tarjeta neutra, sin desglose por moneda', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ estado: 'vencido' })] }) // ningún contrato activo
    // Global: el vencido no es capital vivo. (Con un mes puesto SÍ contaría: ahí
    // la pregunta es qué se cerró, y un contrato vencido se cerró igual.)
    await verTodosLosMeses(user)
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Dólares')).not.toBeInTheDocument()
  })
})

describe('MiCartera — recarga fallida CON datos en pantalla', () => {
  // El defecto que cierran: `hayError` exigía `grupos == null`, así que un refetch
  // caído (TanStack conserva la data anterior) dejaba la cartera EXACTAMENTE igual
  // que si estuviera al día. El analista decidía sobre datos viejos sin saberlo.
  it('avisa de que los datos pueden estar desactualizados y NO borra la cartera', () => {
    montar({ errorClientes: new Error('red caída') })
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.getByText(/pueden estar desactualizados/i)).toBeInTheDocument()
  })

  it('el fallo de CONTRATOS también avisa (no solo el de clientes)', () => {
    montar({ errorContratos: new Error('red caída') })
    expect(screen.getByText(/pueden estar desactualizados/i)).toBeInTheDocument()
  })

  it('la pantalla sigue OPERABLE: no se sustituye por el panel de error', () => {
    montar({ errorClientes: new Error('red caída') })
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.queryByText(/No se pudo cargar tu cartera/i)).not.toBeInTheDocument()
  })

  it('«Reintentar» del aviso recarga clientes Y contratos', async () => {
    const user = userEvent.setup()
    montar({ errorClientes: new Error('red caída') })
    await user.click(
      screen.getByRole('button', {
        name: /Reintentar la carga de tu cartera/i,
      }),
    )
    expect(REFETCH_CLIENTES).toHaveBeenCalledTimes(1)
    expect(REFETCH_CONTRATOS).toHaveBeenCalledTimes(1)
  })

  it('sin fallo NO hay aviso (no se alarma a nadie sin motivo)', () => {
    montar()
    expect(screen.queryByText(/pueden estar desactualizados/i)).not.toBeInTheDocument()
  })

  it('primera carga caída (sin datos): panel de error, NO el aviso de rancio', () => {
    montar({ clientes: null, errorClientes: new Error('red caída') })
    // Un solo mensaje de error, no dos compitiendo.
    expect(screen.queryByText(/pueden estar desactualizados/i)).not.toBeInTheDocument()
    expect(screen.getByText(/No se pudo cargar tu cartera/i)).toBeInTheDocument()
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

    // Bloques por fecha de CIERRE: el contrato de ROSA se cerró hace meses,
    // así que la cartera entera es donde se la ve (ver abrirAltaContratoDemo).
    await user.selectOptions(await screen.findByLabelText('Filtrar por mes de cierre'), MES_TODOS)
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

  it('Directorio demo conserva la ficha comercial sin domicilio ni banca', async () => {
    const user = userEvent.setup()
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    montar({
      // El id coincide con el dueño del fixture para que el harness, cuyo
      // ámbito demo es local, exponga una fila sin fingir un alcance global.
      yo: { id: 'd-v1', rol: 'directorio', puede_contratar: true, demo: true },
      clientes: [],
      contratos: [],
    })

    // Bloques por fecha de CIERRE: el contrato de ROSA se cerró hace meses,
    // así que la cartera entera es donde se la ve (ver abrirAltaContratoDemo).
    await user.selectOptions(await screen.findByLabelText('Filtrar por mes de cierre'), MES_TODOS)
    const nombre = await screen.findByText('ROSA MERCEDES AGUILAR VENTURA')
    const fila = nombre.closest('tr')!
    await user.click(within(fila).getByRole('button', { name: 'Ver detalle' }))

    const ficha = screen.getByRole('dialog', { name: 'ROSA MERCEDES AGUILAR VENTURA' })
    expect(within(ficha).getByText('rosa.aguilar@correo.pe')).toBeInTheDocument()
    expect(within(ficha).getByText('Domicilio legal')).toBeInTheDocument()
    expect(within(ficha).queryByText('Av. Javier Prado Este 123, San Isidro, Lima')).not.toBeInTheDocument()
    expect(within(ficha).getByText('Información bancaria restringida')).toBeInTheDocument()
    expect(within(ficha).queryByText('19100000001234')).not.toBeInTheDocument()
    expect(within(ficha).queryByText('00219100000000123456')).not.toBeInTheDocument()
  })

  it('crea desde Mi cartera y vuelve a descargar exactamente el archivo demo congelado', async () => {
    const user = userEvent.setup()
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    cuentasHook.llamadas.mockClear()
    archivoPdf.archivar.mockReset()
    archivoPdf.archivarDemo.mockReset()
    archivoPdf.consultar.mockReset().mockResolvedValue({ estado: 'sellado' })
    archivoPdf.obtener.mockReset()
    archivoPdf.descargar.mockReset()
    archivoPdf.ver.mockReset()
    const archivo = {
      contratoId: 'demo-2026-01-000777',
      storagePath: 'demo-2026-01-000777/contrato.pdf',
      nombreArchivo: 'Contrato-2026-01-000777-ROSA-MERCEDES-AGUILAR-VENTURA.pdf',
      sha256: 'a'.repeat(64),
      bytes: 24,
      blob: new Blob(['%PDF-1.7\narchivo demo'], { type: 'application/pdf' }),
    }
    archivoPdf.archivarDemo.mockImplementation(async (contratoId: string) => ({
      ...archivo,
      contratoId,
      storagePath: `${contratoId}/contrato.pdf`,
    }))
    montar({
      yo: { id: 'd-v1', rol: 'vendedor', puede_contratar: true, demo: true },
      clientes: [],
      contratos: [],
    })

    // Bloques por fecha de CIERRE: el contrato de ROSA se cerró hace meses,
    // así que la cartera entera es donde se la ve (ver abrirAltaContratoDemo).
    await user.selectOptions(await screen.findByLabelText('Filtrar por mes de cierre'), MES_TODOS)
    const nombre = await screen.findByText('ROSA MERCEDES AGUILAR VENTURA')
    const filaCliente = nombre.closest('tr')
    if (!filaCliente) throw new Error('fila del cliente demo no encontrada')
    await user.click(within(filaCliente).getByRole('button', { name: 'Registrar nueva inversión' }))

    expect(screen.getByRole('dialog', { name: /Crear contrato de ROSA MERCEDES/ })).toBeInTheDocument()
    await user.selectOptions(screen.getByLabelText('Categoría'), 'nuevo')
    await user.type(screen.getByLabelText('Capital'), '10000')
    await user.type(screen.getByLabelText('N° de contrato'), '000777')
    await user.click(screen.getByRole('radio', { name: /BCP/ }))
    await user.click(screen.getByRole('button', { name: 'Crear contrato' }))

    expect(await screen.findByText('Contrato 2026-01-000777 creado')).toBeInTheDocument()
    expect(cuentasHook.llamadas).toHaveBeenCalledWith('dc-cli-1', 'PEN', false)
    expect(archivoPdf.archivar).not.toHaveBeenCalled()
    expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1)
    const idConfirmado = archivoPdf.archivarDemo.mock.calls[0]?.[0]
    expect(idConfirmado).toMatch(/^demo-/)
    const fotoConfirmada = archivoPdf.archivarDemo.mock.calls[0]?.[1]
    expect(fotoConfirmada).toEqual(
      expect.objectContaining({
        contrato: expect.objectContaining({
          numero: '2026-01-000777',
          capital: 10_000,
        }),
        titular: expect.objectContaining({
          domicilio: expect.stringContaining('Lima'),
        }),
      }),
    )

    // Hasta Finalizar el callback no materializa una segunda fila en Mi cartera.
    expect(screen.queryByLabelText('Abrir detalle del contrato 2026-01-000777')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Finalizar' }))

    await user.click(
      await screen.findByRole('button', {
        name: /Expandir los contratos de\s*ROSA MERCEDES AGUILAR VENTURA/,
      }),
    )
    const filaContrato = await screen.findByLabelText('Abrir detalle del contrato 2026-01-000777')
    await user.click(filaContrato)
    await user.click(screen.getByRole('button', { name: 'Descargar contrato PDF' }))

    expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(2)
    expect(archivoPdf.archivarDemo.mock.calls[1]?.[0]).toBe(idConfirmado)
    expect(archivoPdf.archivarDemo.mock.calls[1]?.[1]).toBe(fotoConfirmada)
    expect(archivoPdf.descargar).toHaveBeenCalledWith(
      expect.objectContaining({
        contratoId: idConfirmado,
        storagePath: `${idConfirmado}/contrato.pdf`,
      }),
    )
    expect(archivoPdf.obtener).not.toHaveBeenCalled()
  })

  it('rechaza un número demo existente antes de archivar y conserva la fila original', async () => {
    const user = userEvent.setup()
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    archivoPdf.archivarDemo.mockReset()
    montar({
      yo: { id: 'd-v1', rol: 'vendedor', puede_contratar: true, demo: true },
      clientes: [],
      contratos: [],
    })
    await abrirAltaContratoDemo(user)
    await completarAltaContratoDemo(user, '000901')

    await user.click(screen.getByRole('button', { name: 'Crear contrato' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/ya existe el contrato demo 2026-01-000901/i)
    expect(archivoPdf.archivarDemo).not.toHaveBeenCalled()
    await user.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: /Crear contrato de ROSA/ })).not.toBeInTheDocument()

    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*ROSA MERCEDES AGUILAR VENTURA/,
      }),
    )
    expect(screen.getAllByLabelText('Abrir detalle del contrato 2026-01-000901')).toHaveLength(1)
  })

  it('bloquea Escape y overlay mientras archiva; al terminar Escape materializa una sola vez', async () => {
    const user = userEvent.setup()
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    archivoPdf.archivarDemo.mockReset()
    const pendiente = diferida<{
      contratoId: string
      storagePath: string
      nombreArchivo: string
      sha256: string
      bytes: number
      blob: Blob
    }>()
    archivoPdf.archivarDemo.mockReturnValueOnce(pendiente.promesa)
    montar({
      yo: { id: 'd-v1', rol: 'vendedor', puede_contratar: true, demo: true },
      clientes: [],
      contratos: [],
    })
    await abrirAltaContratoDemo(user)
    await completarAltaContratoDemo(user, '000778')
    await user.click(screen.getByRole('button', { name: 'Crear contrato' }))
    await vi.waitFor(() => expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1))

    await user.keyboard('{Escape}')
    expect(screen.getByRole('dialog', { name: /Contrato 2026-01-000778 creado/ })).toBeInTheDocument()
    const overlay = document.querySelector<HTMLElement>('[data-slot="dialog-overlay"]')
    if (!overlay) throw new Error('overlay del contrato demo no encontrado')
    await user.click(overlay)
    expect(screen.getByRole('dialog', { name: /Contrato 2026-01-000778 creado/ })).toBeInTheDocument()

    const contratoId = archivoPdf.archivarDemo.mock.calls[0]?.[0] as string
    pendiente.resolver({
      contratoId,
      storagePath: `${contratoId}/contrato.pdf`,
      nombreArchivo: 'Contrato-2026-01-000778-ROSA.pdf',
      sha256: 'c'.repeat(64),
      bytes: 24,
      blob: new Blob(['%PDF-1.7\narchivo demo'], { type: 'application/pdf' }),
    })
    expect(await screen.findByText(/PDF privado archivado correctamente/)).toBeInTheDocument()

    await user.keyboard('{Escape}')
    await vi.waitFor(() =>
      expect(screen.queryByRole('dialog', { name: /Crear contrato de ROSA/ })).not.toBeInTheDocument(),
    )
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*ROSA MERCEDES AGUILAR VENTURA/,
      }),
    )
    expect(screen.getAllByLabelText('Abrir detalle del contrato 2026-01-000778')).toHaveLength(1)
    expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1)
  })

  it('el click en overlay después de confirmar equivale a Finalizar', async () => {
    const user = userEvent.setup()
    vi.stubEnv('VITE_ENABLE_DEMO', 'true')
    archivoPdf.archivarDemo.mockReset().mockImplementation(async (contratoId: string) => ({
      contratoId,
      storagePath: `${contratoId}/contrato.pdf`,
      nombreArchivo: 'Contrato-2026-01-000779-ROSA.pdf',
      sha256: 'd'.repeat(64),
      bytes: 24,
      blob: new Blob(['%PDF-1.7\narchivo demo'], { type: 'application/pdf' }),
    }))
    montar({
      yo: { id: 'd-v1', rol: 'vendedor', puede_contratar: true, demo: true },
      clientes: [],
      contratos: [],
    })
    await abrirAltaContratoDemo(user)
    await completarAltaContratoDemo(user, '000779')
    await user.click(screen.getByRole('button', { name: 'Crear contrato' }))
    expect(await screen.findByText(/PDF privado archivado correctamente/)).toBeInTheDocument()

    const overlay = document.querySelector<HTMLElement>('[data-slot="dialog-overlay"]')
    if (!overlay) throw new Error('overlay del contrato demo no encontrado')
    await user.click(overlay)

    await vi.waitFor(() =>
      expect(screen.queryByRole('dialog', { name: /Crear contrato de ROSA/ })).not.toBeInTheDocument(),
    )
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*ROSA MERCEDES AGUILAR VENTURA/,
      }),
    )
    expect(screen.getAllByLabelText('Abrir detalle del contrato 2026-01-000779')).toHaveLength(1)
    expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1)
  })
})

// —— Clientes DADOS DE BAJA en el portal (perfiles.activo=false). Decisión:
// se muestran MARCADOS pero salen de todos los totales — esconderlos borraría
// del CRM contratos que siguen existiendo; contarlos infla una cartera que el
// analista ya no gestiona.
describe('MiCartera — cliente desactivado en el portal', () => {
  const clienteBaja = (over: Partial<ClienteBasico> = {}) =>
    cliente({
      id: 'c-baja',
      nombre_completo: 'CLIENTE DE BAJA',
      activo: false,
      ...over,
    })

  it('sigue en la lista pero MARCADO como inactivo (visible y anunciado)', () => {
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja' })],
    })
    expect(screen.getByText('CLIENTE DE BAJA')).toBeInTheDocument()
    expect(screen.getByText('inactivo')).toBeInTheDocument()
    // La marca entra en el nombre accesible del toggle (no es solo un color).
    expect(screen.getByRole('button', { name: /CLIENTE DE BAJA.*inactivo/s }).tagName).toBe('BUTTON')
    // Y se explica en texto, no solo con un tooltip.
    expect(screen.getByText(/no suman a los totales/)).toBeInTheDocument()
  })

  it('conserva detalle e historial, pero no ofrece escrituras que el servidor rechaza', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja', fecha_vencimiento: '2000-01-01' })],
      detalle: detalle({ id: 'c-baja', nombre_completo: 'CLIENTE DE BAJA' }),
    })

    expect(screen.getByRole('button', { name: 'Ver detalle' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Gestionar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aumentar inversión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()

    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE DE BAJA/,
      }),
    )
    const filaContrato = screen.getByLabelText('Abrir detalle del contrato 2026-01-000001').closest('tr')!
    expect(within(filaContrato).queryByRole('button', { name: 'Renovar' })).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Ver detalle' }))
    expect(screen.getByRole('dialog', { name: /CLIENTE DE BAJA/ })).toBeInTheDocument()
  })

  it('su capital NO cuenta en los KPIs', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [clienteBaja()],
      contratos: [contrato({ cliente_id: 'c-baja', capital: 40000, estado: 'activo' })],
    })
    // La regla de las bajas rige el capital VIVO, que es la vista global.
    await verTodosLosMeses(user)
    // Sin cartera en gestión: tarjeta neutra, no "S/ 40,000".
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    // La cifra propia de SU fila sí se sigue viendo (el dato del cliente es
    // real). Se acota a la fila: la cabecera del bloque de mes muestra el mismo
    // importe —lo cerrado en el mes— y son dos cifras distintas por definición.
    const fila = screen.getByText('CLIENTE DE BAJA').closest('tr')!
    expect(within(fila).getByText('S/ 40,000')).toBeInTheDocument()
  })

  it('el capital del cliente activo queda intacto y el conteo separa a los de baja', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [cliente({ id: 'c-viva', nombre_completo: 'CLIENTE VIVA' }), clienteBaja()],
      contratos: [
        contrato({ id: 'k-viva', cliente_id: 'c-viva', capital: 10000 }),
        contrato({ id: 'k-baja', cliente_id: 'c-baja', capital: 40000 }),
      ],
    })
    await verTodosLosMeses(user)
    // La tarjeta del capital VIVO está y es la de Soles.
    //
    // ⚠️ El VALOR no se asevera aquí. Tras un cambio de filtro lo pinta
    // AnimatedValue contando hasta el número nuevo con requestAnimationFrame, y
    // bajo la carga de la suite completa no siempre termina a tiempo: una
    // aserción así pasa aislada y tumba el gate en verde de otro (medido
    // 2026-08-14, dos veces). La CIFRA —que el cliente de baja no suma— está
    // probada de forma determinista en cartera-vista.test.ts
    // («el capital de un cliente de baja no entra: 10000, jamás 50000»).
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    // El encabezado cuadra con las filas: 1 en gestión + 1 inactivo (2 filas).
    expect(screen.getByText('1 cliente · 1 inactivo')).toBeInTheDocument()
  })

  it('"Sin analista" (supervisión) no cuenta a los dados de baja', () => {
    montar({
      yo: { id: 'sup', rol: 'supervisor', puede_contratar: true, demo: false },
      equipo: [{ perfil_id: 'ase-1', nombre_completo: 'ANALISTA UNO', activo: true }],
      clientes: [
        cliente({
          id: 'c-a',
          nombre_completo: 'CLIENTE ALFA',
          asesor_perfil_id: 'ase-1',
          creado_por: 'ase-1',
        }),
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
    cliente({
      id: 'c-baja',
      nombre_completo: 'CLIENTE DE BAJA',
      activo: false,
      ...over,
    })

  it('cuenta el contrato por vencer de un cliente DADO DE BAJA (no dice “nada por vencer”)', () => {
    montar({
      clientes: [clienteBaja()],
      contratos: [
        contrato({
          cliente_id: 'c-baja',
          capital: 40000,
          fecha_vencimiento: enDias(10),
        }),
      ],
    })
    const chip = chipDe('Por vencer ≤30 d')
    expect(within(chip).getByText('1')).toBeInTheDocument()
    expect(screen.queryByText('nada por vencer')).not.toBeInTheDocument()
    // Y lo DICE: el desglose evita que la cifra parezca un descuadre.
    expect(within(chip).getByText('1 es de un cliente dado de baja')).toBeInTheDocument()
  })

  it('el dinero NO cambia: su capital sigue fuera de los totales aunque la alarma avise', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [clienteBaja()],
      contratos: [
        contrato({
          cliente_id: 'c-baja',
          capital: 40000,
          fecha_vencimiento: enDias(10),
        }),
      ],
    })
    await verTodosLosMeses(user)
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    // La alarma sigue en pie —su tarjeta existe y no está en el estado «nada por
    // vencer»—, que es lo que esta prueba vigila: que el dinero se vaya SIN
    // llevarse el aviso. El conteo exacto (1, y 1 de baja) vive en
    // cartera-vista.test.ts; aquí no se asevera por AnimatedValue (ver la nota
    // de la prueba de los 10k).
    expect(chipDe('Por vencer ≤30 d')).toBeInTheDocument()
    expect(screen.queryByText('nada por vencer')).not.toBeInTheDocument()
  })

  it('con clientes en gestión y de baja, el conteo los suma y desglosa los de baja', () => {
    montar({
      clientes: [cliente({ id: 'c-viva', nombre_completo: 'CLIENTE VIVA' }), clienteBaja()],
      contratos: [
        contrato({
          id: 'k-viva',
          cliente_id: 'c-viva',
          fecha_vencimiento: enDias(20),
        }),
        contrato({
          id: 'k-baja',
          cliente_id: 'c-baja',
          fecha_vencimiento: enDias(5),
        }),
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
        contrato({
          id: 'k-viva',
          cliente_id: 'c-viva',
          fecha_vencimiento: enDias(200),
        }), // fuera de ventana
        contrato({
          id: 'k-baja',
          cliente_id: 'c-baja',
          numero_contrato: '2026-07-000099',
          fecha_vencimiento: enDias(10),
        }),
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
        contrato({
          id: 'k-viva',
          cliente_id: 'c-viva',
          fecha_vencimiento: enDias(200),
        }),
        contrato({
          id: 'k-baja',
          cliente_id: 'c-baja',
          fecha_vencimiento: enDias(10),
        }),
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

// —— Supervisión (verEquipo): filtro por analista + indicador "Sin analista",
// portados de la pantalla Clientes retirada en Fase 6 (parity de supervisión).
describe('MiCartera — supervisión (filtro por analista + Sin analista)', () => {
  const YO_SUP = {
    id: 'sup',
    rol: 'supervisor',
    puede_contratar: true,
    demo: false,
  }
  const EQUIPO_SUP = [
    { perfil_id: 'ase-1', nombre_completo: 'ANALISTA UNO', activo: true },
    { perfil_id: 'ase-2', nombre_completo: 'ANALISTA DOS', activo: true },
  ]
  // Alfa→ase-1, Beta→ase-2, y DOS variantes de "Sin analista": dueño null y dueño
  // FUERA del roster visible ('ase-fantasma', p.ej. alta de un admin del portal).
  // Ambas cuentan como sin analista — la columna Analista pinta '—' para las dos.
  const CLIENTES_SUP = [
    cliente({
      id: 'c-a',
      nombre_completo: 'CLIENTE ALFA',
      asesor_perfil_id: 'ase-1',
      creado_por: 'ase-1',
    }),
    cliente({
      id: 'c-b',
      nombre_completo: 'CLIENTE BETA',
      asesor_perfil_id: 'ase-2',
      creado_por: 'ase-2',
    }),
    cliente({
      id: 'c-c',
      nombre_completo: 'CLIENTE SIN DUENO',
      asesor_perfil_id: null,
      creado_por: null,
    }),
    cliente({
      id: 'c-d',
      nombre_completo: 'CLIENTE FANTASMA',
      asesor_perfil_id: 'ase-fantasma',
      creado_por: 'ase-fantasma',
    }),
  ]
  const montarSup = () =>
    montar({
      yo: YO_SUP,
      equipo: EQUIPO_SUP,
      clientes: CLIENTES_SUP,
      contratos: [],
    })

  it('puede operar clientes de su equipo, igual que vendedor_ids_visibles del servidor', async () => {
    const user = userEvent.setup()
    montar({
      yo: YO_SUP,
      equipo: EQUIPO_SUP,
      clientes: [CLIENTES_SUP[0]!],
      contratos: [
        contrato({
          cliente_id: 'c-a',
          creado_por: 'ase-1',
          fecha_vencimiento: '2000-01-01',
        }),
      ],
    })

    expect(screen.getByRole('button', { name: 'Gestionar' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver detalle' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Aumentar inversión' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Registrar nueva inversión' })).toBeInTheDocument()
    // Supervisar el roster habilita gestión y contratos, no el PATCH del
    // perfil: esa corrección sigue siendo solo del dueño (o de Gerencia).
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()

    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE ALFA/,
      }),
    )
    const filaContrato = screen.getByLabelText('Abrir detalle del contrato 2026-01-000001').closest('tr')!
    expect(within(filaContrato).getByRole('button', { name: 'Renovar' })).toBeInTheDocument()
    expect(within(filaContrato).queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
  })

  it('sí permite al supervisor corregir su propio cliente dentro de la ventana', () => {
    montar({
      yo: YO_SUP,
      equipo: EQUIPO_SUP,
      clientes: [cliente({ asesor_perfil_id: 'sup', creado_por: 'sup' })],
      contratos: [],
    })

    expect(screen.getByRole('button', { name: 'Corregir' })).toBeInTheDocument()
  })

  it('no amplía acciones a un dueño fuera del roster visible', () => {
    montar({
      yo: YO_SUP,
      equipo: EQUIPO_SUP,
      clientes: [CLIENTES_SUP[3]!],
      contratos: [],
    })

    expect(screen.getByText('CLIENTE FANTASMA')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Gestionar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Ver detalle' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar primera inversión' })).not.toBeInTheDocument()
    const encabezados = screen.getAllByRole('columnheader')
    const fila = screen.getByText('CLIENTE FANTASMA').closest('tr')!
    expect(within(fila).getAllByRole('cell')).toHaveLength(encabezados.length)
  })

  it('el chip "Sin analista" cuenta dueño null Y dueño fuera del roster (2)', () => {
    montarSup()
    expect(screen.getByRole('combobox', { name: /Filtrar por analista/ })).toBeInTheDocument()
    // El sub-texto "Repártelos…" es único del chip (evita chocar con la opción del Select).
    expect(screen.getByText(/Repártelos/)).toBeInTheDocument()
    // Conteo del chip = mismo criterio que el filtro: null + fuera-de-roster = 2.
    // (AnimatedValue arranca en el useState(value) inicial; su rAF no avanza en jsdom.)
    // Se ancla por el sub-texto "Repártelos" (único del chip; "Sin analista" también
    // es una <option> del Select de analista).
    const chip = screen.getByText(/Repártelos/).closest('.ac-lift') as HTMLElement
    expect(chip).not.toBeNull()
    expect(within(chip).getByText('2')).toBeInTheDocument()
  })

  it('filtrar por un analista deja solo sus clientes', async () => {
    const user = userEvent.setup()
    montarSup()
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por analista/ }), 'ase-1')
    expect(screen.getByText('CLIENTE ALFA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE BETA')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE SIN DUENO')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE FANTASMA')).not.toBeInTheDocument()
  })

  it('filtro "Sin analista" aísla dueño null Y dueño fuera del roster', async () => {
    const user = userEvent.setup()
    montarSup()
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por analista/ }), 'sin_asesor')
    expect(screen.getByText('CLIENTE SIN DUENO')).toBeInTheDocument()
    expect(screen.getByText('CLIENTE FANTASMA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE ALFA')).not.toBeInTheDocument()
    expect(screen.queryByText('CLIENTE BETA')).not.toBeInTheDocument()
  })

  it('el analista NO ve el filtro por analista ni el chip "Sin analista"', () => {
    montar() // rol analista por defecto
    expect(screen.queryByRole('combobox', { name: /Filtrar por analista/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/Repártelos/)).not.toBeInTheDocument()
  })

  it('con capital en PEN Y USD, "Sin analista" reemplaza una métrica → 4 tarjetas, no 5', async () => {
    const user = userEvent.setup()
    // Dos chips de capital + Por vencer + Clientes con capital = 4; sin el fix,
    // "Sin analista" sería el 5º y rompería el grid de 4. El fix descarta la última
    // métrica NO monetaria (Clientes con capital), nunca los chips de capital.
    montar({
      yo: YO_SUP,
      equipo: EQUIPO_SUP,
      clientes: [
        cliente({
          id: 'c-a',
          nombre_completo: 'CLIENTE ALFA',
          asesor_perfil_id: 'ase-1',
          creado_por: 'ase-1',
        }),
      ],
      contratos: [
        contrato({
          cliente_id: 'c-a',
          moneda: 'PEN',
          capital: 10000,
          estado: 'activo',
        }),
        contrato({
          cliente_id: 'c-a',
          numero_contrato: '2026-01-000002',
          moneda: 'USD',
          capital: 5000,
          estado: 'activo',
        }),
      ],
    })
    await verTodosLosMeses(user)
    // Chips de capital intactos + Sin analista presente; Clientes con capital cede el sitio.
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.getByText('Capital invertido · Dólares')).toBeInTheDocument()
    // 'span' distingue el label del chip de la <option> homónima del Select.
    expect(screen.getByText('Sin analista', { selector: 'span' })).toBeInTheDocument()
    expect(screen.queryByText('Clientes con capital')).not.toBeInTheDocument()
  })

  it('vacío por analista + estado combinados usa un mensaje neutral (no afirma "toda la cartera tiene dueño")', async () => {
    const user = userEvent.setup()
    montarSup() // hay clientes sin analista, pero sin contratos → cualquier estado los vacía
    await user.selectOptions(screen.getByRole('combobox', { name: /Filtrar por analista/ }), 'sin_asesor')
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
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(screen.getByText('2026-01-000001')).toBeInTheDocument()
  })

  it('gating: una fila AJENA no ofrece "Registrar nueva inversión"', () => {
    activarMovil()
    montar({
      clientes: [
        cliente({
          id: 'c-ajeno',
          asesor_perfil_id: 'otro',
          creado_por: 'otro',
        }),
      ],
      contratos: [contrato({ id: 'k-ajeno', cliente_id: 'c-ajeno', creado_por: 'otro' })],
    })
    expect(screen.getByText('CLIENTE UNO')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Gestionar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()
  })

  it('en móvil mantiene Gestionar para cartera propia sin permiso contractual', () => {
    activarMovil()
    montar({
      yo: {
        id: 'yo',
        rol: 'vendedor',
        puede_contratar: false,
        demo: false,
      },
    })

    expect(screen.getByRole('button', { name: 'Gestionar' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aumentar inversión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar nueva inversión' })).not.toBeInTheDocument()
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
    // Ambas cifras conviven en la cabecera de la tarjeta del cliente (acotado
    // a la tarjeta: el bloque de mes repite los mismos importes arriba).
    const tarjeta = within(screen.getByRole('listitem'))
    expect(tarjeta.getByText('S/ 10,000')).toBeInTheDocument()
    expect(tarjeta.getByText('US$ 5,000')).toBeInTheDocument()
  })

  // El "Corregir cliente" de la tarjeta y el "Corregir" del contrato conviven,
  // así que se busca por nombre EXACTO 'Corregir' (no matchea "Corregir cliente").
  it('Corregir del contrato: PRESENTE si es mío y con ventana viva', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar() // contrato creado_por 'yo', reciente → ventana viva
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(screen.getByRole('button', { name: 'Corregir' })).toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si es de otro analista (creado_por ≠ yo)', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar({ contratos: [contrato({ creado_por: 'otro' })] })
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
  })

  it('Corregir del contrato: AUSENTE si la ventana de 5 h ya venció', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar({
      contratos: [contrato({ creado_en: '2020-01-01T00:00:00.000Z' })],
    })
    await verTodosLosMeses(user) // el contrato es de 2020
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
  })

  it('la sub-tarjeta abre el detalle con un <button> NATIVO (accesible por teclado)', async () => {
    const user = userEvent.setup()
    activarMovil()
    montar()
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    // Control de detalle = button real (no un div con role); el gating a11y del Medium.
    expect(
      screen.getByRole('button', {
        name: /Abrir detalle del contrato\s*2026-01-000001/,
      }),
    ).toBeInTheDocument()
  })

  it('USD-only: el capital principal del cliente es en dólares, sin "S/ 0" líder', () => {
    activarMovil()
    montar({
      clientes: [cliente({ id: 'c-usd' })],
      contratos: [
        contrato({
          id: 'k-usd',
          cliente_id: 'c-usd',
          moneda: 'USD',
          capital: 50000,
        }),
      ],
    })
    expect(within(screen.getByRole('listitem')).getByText('US$ 50,000')).toBeInTheDocument()
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
    await user.click(
      screen.getByRole('button', {
        name: /Expandir los contratos de\s*CLIENTE UNO/,
      }),
    )
    const detalle = screen.getByRole('button', {
      name: /Abrir detalle del contrato\s*2026-01-000001/,
    })
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
    // sigue siendo mío → "Registrar nueva inversión" continúa disponible.
    expect(screen.getByRole('button', { name: 'Registrar nueva inversión' })).toBeInTheDocument()
  })

  it('Corregir cliente: AUSENTE si el cliente es de otro analista', () => {
    activarMovil()
    montar({
      clientes: [cliente({ asesor_perfil_id: 'otro', creado_por: 'otro' })],
    })
    expect(screen.queryByRole('button', { name: 'Corregir cliente' })).not.toBeInTheDocument()
  })
})

// ————————————————————————————————————————————————————————————————————————
// FILTRO DE MES DE CIERRE (pedido de Miguel, 2026-08-14): el analista abre y ve
// lo que lleva cerrado ESTE mes, sin listas de meses que recorrer. La
// agrupación pura se prueba en lib/cartera-meses.test.ts; aquí se prueba lo que
// la PANTALLA hace con ella.
// ————————————————————————————————————————————————————————————————————————
describe('MiCartera — filtro por mes de cierre', () => {
  /** ISO de un contrato del mes en curso (11:00 de Lima del día 10). */
  const esteMes = () => {
    const hoy = new Date()
    return new Date(Date.UTC(hoy.getFullYear(), hoy.getMonth(), 10, 16, 0, 0)).toISOString()
  }
  /** Nombre corto del mes en curso, tal y como lo rotula la pantalla. */
  const mesEnCurso = () =>
    [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ][new Date().getMonth()]!
  /** La tarjeta del StatStrip que lleva ese rótulo. */
  const tarjeta = (label: string): HTMLElement => {
    const card = screen.getByText(label).closest('.ac-lift')
    if (!card) throw new Error(`tarjeta “${label}” no encontrada`)
    return card as HTMLElement
  }
  /** ISO de hace ~3 meses, seguro fuera del mes en curso. */
  const haceMeses = (n: number) => {
    const hoy = new Date()
    return new Date(Date.UTC(hoy.getFullYear(), hoy.getMonth() - n, 10, 16, 0, 0)).toISOString()
  }

  const conDosMeses = () =>
    montar({
      clientes: [
        cliente({ id: 'c-a', nombre_completo: 'CLIENTA DE AHORA' }),
        cliente({ id: 'c-v', nombre_completo: 'CLIENTE DE ANTES' }),
      ],
      contratos: [
        contrato({
          id: 'k-a',
          cliente_id: 'c-a',
          capital: 20000,
          creado_en: esteMes(),
        }),
        contrato({
          id: 'k-v',
          cliente_id: 'c-v',
          capital: 5000,
          creado_en: haceMeses(3),
        }),
      ],
    })

  it('arranca en el mes en curso: solo se ve lo cerrado este mes', () => {
    conDosMeses()
    expect(screen.getByText('CLIENTA DE AHORA')).toBeInTheDocument()
    expect(screen.queryByText('CLIENTE DE ANTES')).not.toBeInTheDocument()
  })

  it('«Todos los meses» devuelve la cartera entera', async () => {
    const user = userEvent.setup()
    conDosMeses()
    await verTodosLosMeses(user)
    expect(screen.getByText('CLIENTA DE AHORA')).toBeInTheDocument()
    expect(screen.getByText('CLIENTE DE ANTES')).toBeInTheDocument()
  })

  it('el desplegable ofrece los meses con cierres, del más reciente al más viejo', () => {
    conDosMeses()
    const opciones = within(screen.getByRole('combobox', { name: /Filtrar por mes/ }))
      .getAllByRole('option')
      .map((o) => o.textContent)
    expect(opciones[0]).toBe('Todos los meses')
    // El mes en curso manda sobre el viejo, y el cubo de sin-contrato no está
    // (aquí todos los clientes tienen contrato).
    expect(opciones).toHaveLength(3)
    expect(opciones).not.toContain('Clientes sin contrato')
  })

  it('las tarjetas de dinero pasan a decir lo CERRADO en el mes, y lo dicen en el rótulo', () => {
    montar({
      clientes: [cliente({ id: 'c-1' })],
      contratos: [
        contrato({
          id: 'k-pen',
          capital: 20000,
          moneda: 'PEN',
          creado_en: esteMes(),
        }),
        contrato({
          id: 'k-usd',
          capital: 7000,
          moneda: 'USD',
          creado_en: esteMes(),
        }),
      ],
    })
    // Una tarjeta que cambia de significado sin cambiar de nombre es una mentira:
    // el rótulo se mueve con la cifra.
    const mes = mesEnCurso()
    expect(screen.getByText(`Cerrado en ${mes} · Soles`)).toBeInTheDocument()
    expect(screen.getByText(`Cerrado en ${mes} · Dólares`)).toBeInTheDocument()
    expect(screen.queryByText('Capital invertido · Soles')).not.toBeInTheDocument()
    expect(within(tarjeta(`Cerrado en ${mes} · Soles`)).getByText('S/ 20k')).toBeInTheDocument()
    expect(within(tarjeta(`Cerrado en ${mes} · Dólares`)).getByText('US$ 7k')).toBeInTheDocument()
    // Y la línea se queda con el conteo, sin repetir los importes.
    expect(screen.getByText(/2 contratos cerrados en/)).toBeInTheDocument()
  })

  // El total cuenta TODO contrato de sus clientes (decisión de Miguel), pero la
  // cuota le paga por los que registró ÉL. Cuando el mes mezcla ambos se dice, o
  // el analista vería un capital aquí y otro en Hoy sin explicación.
  it('avisa cuando el mes incluye un contrato registrado por otra persona', () => {
    montar({
      clientes: [cliente({ id: 'c-1', asesor_perfil_id: 'yo', creado_por: 'yo' })],
      contratos: [
        contrato({ id: 'k-mio', creado_por: 'yo', creado_en: esteMes() }),
        contrato({ id: 'k-ajeno', creado_por: 'carlos', creado_en: esteMes() }),
      ],
    })
    expect(screen.getByText('incluye 1 registrado por otra persona')).toBeInTheDocument()
  })

  it('no avisa de nada cuando todo el mes lo registró el propio analista', () => {
    montar({ contratos: [contrato({ creado_en: esteMes() })] })
    expect(screen.queryByText(/registrado.? por otra persona/)).not.toBeInTheDocument()
  })

  // ESTADO DE PRODUCCIÓN (gate de realidad): un analista que aún no ha cerrado
  // nada este mes es lo PRIMERO que ve al abrir. No puede quedarse mirando un
  // vacío sin salida.
  it('sin cierres este mes lo dice y ofrece ver toda la cartera', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [cliente({ id: 'c-v', nombre_completo: 'CLIENTE DE ANTES' })],
      contratos: [contrato({ id: 'k-v', cliente_id: 'c-v', creado_en: haceMeses(3) })],
    })
    expect(screen.getByText(/Sin cierres en/)).toBeInTheDocument()
    expect(screen.getByText(/Tus clientes siguen ahí/)).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Ver toda la cartera' }))
    expect(screen.getByText('CLIENTE DE ANTES')).toBeInTheDocument()
  })

  // Los clientes sin contrato NO son historia de otro mes: son trabajo
  // pendiente, y esta es la pantalla desde la que se les crea el contrato.
  it('los clientes sin ningún contrato acompañan al mes elegido', () => {
    montar({
      clientes: [
        cliente({ id: 'c-a', nombre_completo: 'CLIENTA DE AHORA' }),
        cliente({ id: 'c-n', nombre_completo: 'RECIEN CAPTADO' }),
      ],
      contratos: [contrato({ id: 'k-a', cliente_id: 'c-a', creado_en: esteMes() })],
    })
    expect(screen.getByText('CLIENTA DE AHORA')).toBeInTheDocument()
    expect(screen.getByText('RECIEN CAPTADO')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Registrar primera inversión' })).toBeInTheDocument()
  })

  it('con «Todos los meses» los rótulos vuelven a los de siempre', async () => {
    const user = userEvent.setup()
    montar({ contratos: [contrato({ creado_en: esteMes() })] })
    expect(screen.getByText(`Cerrado en ${mesEnCurso()} · Soles`)).toBeInTheDocument()
    await verTodosLosMeses(user)
    expect(screen.getByText('Capital invertido · Soles')).toBeInTheDocument()
    expect(screen.queryByText(`Cerrado en ${mesEnCurso()} · Soles`)).not.toBeInTheDocument()
  })

  // «Cerrado» cuenta CUALQUIER estado: un contrato que ya venció se cerró igual.
  // Es justo lo contrario de «Capital invertido», que solo cuenta lo vivo — y por
  // eso las dos tarjetas no pueden llamarse igual.
  it('lo cerrado incluye contratos ya vencidos; el capital vivo no', async () => {
    const user = userEvent.setup()
    montar({
      contratos: [contrato({ capital: 30000, estado: 'vencido', creado_en: esteMes() })],
    })
    expect(within(tarjeta(`Cerrado en ${mesEnCurso()} · Soles`)).getByText('S/ 30k')).toBeInTheDocument()
    await verTodosLosMeses(user)
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
  })

  // BORDE que destapó el análisis: la regla «los clientes dados de baja no suman
  // al dinero» protege el capital que se puede TRABAJAR. Lo cerrado en un mes es
  // un hecho histórico y sí los cuenta — además, ese cliente está listado debajo
  // (marcado «inactivo»), así que la tarjeta cuadra con lo que se ve.
  it('lo cerrado SÍ cuenta a un cliente dado de baja; el capital vivo NO', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [
        cliente({
          id: 'c-baja',
          nombre_completo: 'CLIENTE DE BAJA',
          activo: false,
        }),
      ],
      contratos: [
        contrato({
          cliente_id: 'c-baja',
          capital: 40000,
          creado_en: esteMes(),
        }),
      ],
    })
    expect(within(tarjeta(`Cerrado en ${mesEnCurso()} · Soles`)).getByText('S/ 40k')).toBeInTheDocument()
    await verTodosLosMeses(user)
    expect(screen.getByText('sin capital vigente aún')).toBeInTheDocument()
  })

  it('cuenta a cuántos clientes les cerró ese mes', () => {
    montar({
      clientes: [
        cliente({ id: 'c-a', nombre_completo: 'CLIENTA A' }),
        cliente({ id: 'c-b', nombre_completo: 'CLIENTE B' }),
      ],
      contratos: [
        contrato({ id: 'k-a', cliente_id: 'c-a', creado_en: esteMes() }),
        contrato({ id: 'k-b', cliente_id: 'c-b', creado_en: esteMes() }),
      ],
    })
    expect(within(tarjeta('Clientes que cerraron')).getByText('2')).toBeInTheDocument()
  })

  // Los otros filtros siguen vivos y recortan también el mes. Si no se dijera, la
  // tarjeta parecería el total del mes cuando es el total de lo buscado.
  it('la tarjeta declara cuando hay otro filtro recortándola', async () => {
    const user = userEvent.setup()
    montar({
      clientes: [
        cliente({ id: 'c-a', nombre_completo: 'CLIENTA ALFA' }),
        cliente({ id: 'c-b', nombre_completo: 'CLIENTE BETA' }),
      ],
      contratos: [
        contrato({
          id: 'k-a',
          cliente_id: 'c-a',
          capital: 20000,
          creado_en: esteMes(),
        }),
        contrato({
          id: 'k-b',
          cliente_id: 'c-b',
          capital: 5000,
          creado_en: esteMes(),
        }),
      ],
    })
    expect(screen.getByText(`cerrado en ${mesEnCurso()}`)).toBeInTheDocument()
    await user.type(screen.getByLabelText('Buscar en la cartera'), 'ALFA')
    expect(screen.getByText('de lo que estás filtrando')).toBeInTheDocument()
    // El VALOR no se asevera tras interactuar: lo pinta AnimatedValue, cuyo rAF
    // no avanza en jsdom (se queda en el useState inicial). Lo que se prueba es
    // que la tarjeta DECLARA el recorte, que es lo que evita leerla como el
    // total del mes.
  })

  // ESTADO DE PRODUCCIÓN: un analista sin cierres este mes. La tarjeta lo dice sin
  // rodeos, y «Contratos activos» sigue de testigo de que la cartera está viva.
  it('sin cierres este mes, la tarjeta lo dice y queda un testigo global', () => {
    montar({
      clientes: [cliente({ id: 'c-v', nombre_completo: 'CLIENTE DE ANTES' })],
      contratos: [contrato({ id: 'k-v', cliente_id: 'c-v', creado_en: haceMeses(3) })],
    })
    expect(screen.getByText(`Cerrado en ${mesEnCurso()}`)).toBeInTheDocument()
    expect(screen.getByText('sin cierres este mes')).toBeInTheDocument()
    expect(within(tarjeta('Contratos activos')).getByText('1')).toBeInTheDocument()
  })

  // El aviso de renovación es el ÚNICO radar del CRM: con un mes puesto, un
  // contrato que vence pero se cerró en otro mes no lo vería nadie.
  it('activar «Por vencer» quita el filtro de mes', async () => {
    const user = userEvent.setup()
    const dentro = new Date(Date.now() + 10 * 86_400_000).toISOString().slice(0, 10)
    montar({
      clientes: [cliente({ id: 'c-v', nombre_completo: 'CLIENTE DE ANTES' })],
      contratos: [
        contrato({
          id: 'k-v',
          cliente_id: 'c-v',
          creado_en: haceMeses(3),
          fecha_vencimiento: dentro,
        }),
      ],
    })
    expect(screen.queryByText('CLIENTE DE ANTES')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: /Por vencer/ }))
    expect(screen.getByRole('combobox', { name: /Filtrar por mes/ })).toHaveValue('todos')
    expect(screen.getByText('CLIENTE DE ANTES')).toBeInTheDocument()
  })
})
