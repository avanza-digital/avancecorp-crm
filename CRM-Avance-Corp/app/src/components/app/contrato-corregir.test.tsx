// Tests de ContratoCorregir. Fijan los dos bugs de DINERO de la auditoría
// 2026-07-25:
//  1) el guard del cronograma era `length === 0` — imposible de disparar (el
//     generador siempre empuja la fila del retorno del capital) → se podía dejar
//     un contrato sin UNA sola cuota de interés;
//  2) el select de plazo caía a '12' cuando el plazo real no era preset y
//     cualquier cambio de la fecha de inicio RECORTABA el vencimiento pactado en
//     silencio (18 meses → 12, sin aviso y sin vuelta atrás desde Corregir).
// @/data/crm-api se mockea (sin red) conservando CrmApiError; el form precarga
// los co-titulares por TanStack Query, así que va dentro de un QueryClient limpio.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Dialog } from '@/components/ui/dialog'
import type { ContratoRow } from '@/lib/clientes-tipos'
import * as crmApi from '@/data/crm-api'
import * as contratoPdf from '@/lib/contrato-pdf-archivo'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, actualizarContrato: vi.fn(), obtenerTitulares: vi.fn() }
})

// `esContratoRegimenAnterior` se queda REAL: decide si tras corregir hay o no
// documento que actualizar, y doblarla convertiría estas pruebas en un espejo.
vi.mock('@/lib/contrato-pdf-archivo', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/contrato-pdf-archivo')>()),
  asegurarContratoPdfActualizado: vi.fn(),
}))

const { ContratoCorregir } = await import('./contrato-corregir')
const actualizarContrato = vi.mocked(crmApi.actualizarContrato)
const obtenerTitulares = vi.mocked(crmApi.obtenerTitulares)

const asegurarContratoPdfActualizado = vi.mocked(contratoPdf.asegurarContratoPdfActualizado)

/** Rentabilidad R3: solicitudes de tasa que «devuelve el servidor» al bloque de tasa (vacías salvo en el test de caducidad). */
const rentabilidadDobles = vi.hoisted(() => ({ solicitudes: [] as unknown[] }))
const productosEstado = vi.hoisted(() => ({
  data: [] as import('@/lib/productos-inversion').ProductoCondicionSeleccion[],
  error: false,
  pending: false,
  fetching: false,
  refetch: vi.fn(),
}))

const CONDICION_VIGENTE: import('@/lib/productos-inversion').ProductoCondicionSeleccion = {
  condicion_id: '10000000-0000-4000-8000-000000000010',
  producto_id: '20000000-0000-4000-8000-000000000010',
  producto_codigo: 'RENTA-12',
  producto_revision: 2,
  version_id: '30000000-0000-4000-8000-000000000010',
  numero_version: 2,
  version_nombre: 'Renta 12 meses',
  vigente_desde: '2026-01-01',
  vigente_hasta: null,
  categoria: 'renovacion',
  moneda: 'PEN',
  plazo_meses: 12,
  modalidad: 'trimestral',
  tipo_interes: 'simple',
  capital_minimo: 5_000,
  capital_maximo: 50_000,
  tasa_referencia: 16,
  tasa_minima: 14,
  tasa_maxima: 18,
}

vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  return {
    ...actual,
    // Rentabilidad R3: en corrección la base es la tasa vigente; sin solicitudes en estos escenarios.
    useResolucionTasa: () => ({ data: undefined, isPending: false, isError: false, refetch: vi.fn() }),
    useSolicitudesTasa: () => ({ data: rentabilidadDobles.solicitudes, isPending: false, isError: false, refetch: vi.fn() }),
    useSolicitarTasa: () => ({ mutateAsync: vi.fn(), isPending: false }),
    useResponderTopeTasa: () => ({ mutateAsync: vi.fn(), isPending: false }),
    useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: vi.fn() }),
  }
})

vi.mock('@/data/crm-config-queries', () => ({
  useProductosSeleccionables: () => ({
    data: productosEstado.data,
    isError: productosEstado.error,
    isPending: productosEstado.pending,
    isFetching: productosEstado.fetching,
    refetch: productosEstado.refetch,
  }),
}))

function contratoBase(over: Partial<ContratoRow> = {}): ContratoRow {
  return {
    id: 'ctr-1',
    numero_contrato: '2026-01-000123',
    cliente_id: 'cli-1',
    cliente_nombre: 'CLIENTE PORTAL UNO',
    capital: 10000,
    moneda: 'PEN',
    tasa_anual: 15,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2026-01-15',
    fecha_vencimiento: '2027-01-15',
    fecha_cierre_comercial: '2026-01-15',
    notas_internas: null,
    creado_por: 'yo',
    creado_en: new Date().toISOString(), // ventana de 5 h viva
    producto_condicion_id: '10000000-0000-4000-8000-000000000001',
    producto_id: '20000000-0000-4000-8000-000000000001',
    producto_codigo: 'HISTORICO-SIN-CATALOGO',
    producto_version_id: '30000000-0000-4000-8000-000000000001',
    producto_version: 1,
    producto_nombre: 'Snapshot histórico 2026-01-000123',
    producto_version_estado: 'retirada',
    ...over,
  }
}

/** Monta el form y espera a que los co-titulares terminen de precargarse. */
async function montar(over: Partial<ContratoRow> = {}) {
  obtenerTitulares.mockResolvedValue([])
  const onGuardado = vi.fn()
  const onCerrar = vi.fn()
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } },
  })
  render(
    <QueryClientProvider client={queryClient}>
      <Dialog open onClose={() => undefined}>
        <ContratoCorregir contrato={contratoBase(over)} onGuardado={onGuardado} onCerrar={onCerrar} />
      </Dialog>
    </QueryClientProvider>,
  )
  // Hasta que la precarga acabe el guardado está bloqueado (borraría co-titulares).
  await screen.findByText('Sin co-titulares.')
  return { onGuardado, onCerrar }
}

const guardar = () => screen.getByRole('button', { name: /Guardar corrección/ })
const plazoSelect = () => screen.getByLabelText('Plazo')

/** Los <input type="date"> ya vienen con valor: fireEvent.change es la vía fiable
 *  (user.type teclea SOBRE sistema de segmentos del date input). */
function escribirFecha(etiqueta: string, valor: string) {
  fireEvent.change(screen.getByLabelText(etiqueta), { target: { value: valor },
  })
}

beforeEach(() => {
    rentabilidadDobles.solicitudes = []
  productosEstado.data = []
  productosEstado.error = false
  productosEstado.pending = false
  productosEstado.fetching = false
  productosEstado.refetch.mockReset()
  actualizarContrato.mockReset()
  obtenerTitulares.mockReset()
  asegurarContratoPdfActualizado.mockReset()
  asegurarContratoPdfActualizado.mockResolvedValue({
    contratoId: 'ctr-1',
    jobId: 'job-2',
    estado: 'sellado',
    intentos: 1,
    leaseExpiraEn: null,
    reintentable: false,
    sha256: 'a'.repeat(64),
    bytes: 1024,
    archivo: null,
  })
})

describe('ContratoCorregir — el plazo REAL no se falsea ni se recorta', () => {
  it('plazo de 18 meses (no preset): el select dice Personalizado (18 meses), no "1 año"', async () => {
    await montar({ fecha_vencimiento: '2027-07-15' }) // 2026-01-15 + 18 meses

    expect(plazoSelect()).toHaveValue('personalizado')
    expect(screen.getByRole('option', { name: 'Personalizado (18 meses)' })).toBeInTheDocument()
    // Y el vencimiento pactado se ve tal cual, editable.
    expect(screen.getByLabelText('Fecha de vencimiento')).toHaveValue('2027-07-15')
  })

  it('con plazo personalizado, cambiar la fecha de inicio NO recorta el vencimiento', async () => {
    const user = userEvent.setup()
    actualizarContrato.mockResolvedValue()
    const { onGuardado } = await montar({ fecha_vencimiento: '2027-07-15' })

    escribirFecha('Fecha de inicio', '2026-02-15')

    // El vencimiento pactado sigue intacto (antes pasaba a 2027-02-15 en silencio).
    expect(screen.getByLabelText('Fecha de vencimiento')).toHaveValue('2027-07-15')
    expect(screen.getByText(/NO se recalcula al cambiar la fecha de inicio/)).toBeInTheDocument()

    await user.click(guardar())
    await waitFor(() => expect(onGuardado).toHaveBeenCalled())
    // Firma en febrero de 2026: régimen documental ANTERIOR, no hay documento
    // del sistema que actualizar. La corrección se guarda igual.
    expect(asegurarContratoPdfActualizado).not.toHaveBeenCalled()
    const [id, input] = actualizarContrato.mock.calls[0]!
    expect(id).toBe('ctr-1')
    expect(input).toMatchObject({ fecha_inicio: '2026-02-15', fecha_vencimiento: '2027-07-15',
    })
  })

  it('si el render PDF falla después del commit, conserva la corrección y permite reintentar al abrirlo', async () => {
    const user = userEvent.setup()
    actualizarContrato.mockResolvedValue()
    asegurarContratoPdfActualizado.mockRejectedValue(new Error('Storage temporalmente no disponible'))
    // Firmado ya en el régimen nuevo: es el único en el que existe documento y,
    // por tanto, el único en el que este fallo puede ocurrir.
    const { onGuardado } = await montar({
      fecha_inicio: '2026-08-19', fecha_vencimiento: '2027-08-19',
    })

    await user.click(guardar())

    await waitFor(() => expect(onGuardado).toHaveBeenCalledOnce())
    expect(actualizarContrato).toHaveBeenCalledOnce()
    expect(asegurarContratoPdfActualizado).toHaveBeenCalledWith('ctr-1')
  })

  it('un contrato del formato anterior se corrige sin tocar documento alguno', async () => {
    const user = userEvent.setup()
    actualizarContrato.mockResolvedValue()
    // 18/08/2026: un solo día antes de la frontera. Si alguien afloja la regla
    // —un `<=`, otra fecha, mirar la carga en vez de la firma— este caso lo caza.
    const { onGuardado } = await montar({
      fecha_inicio: '2026-08-18', fecha_vencimiento: '2027-08-18',
    })

    await user.click(guardar())

    await waitFor(() => expect(onGuardado).toHaveBeenCalledOnce())
    expect(actualizarContrato).toHaveBeenCalledOnce()
    expect(asegurarContratoPdfActualizado).not.toHaveBeenCalled()
  })

  it('con plazo personalizado se puede mover el vencimiento a mano (y es lo que viaja)', async () => {
    const user = userEvent.setup()
    actualizarContrato.mockResolvedValue()
    await montar({ fecha_vencimiento: '2027-07-15' })

    escribirFecha('Fecha de vencimiento', '2027-10-15')
    await user.click(guardar())

    await waitFor(() => expect(actualizarContrato).toHaveBeenCalledTimes(1))
    expect(actualizarContrato.mock.calls[0]![1]).toMatchObject({ fecha_vencimiento: '2027-10-15',
    })
  })

  it('plazo que SÍ es preset: se muestra el preset y cambiar el inicio lo recalcula (explícito)', async () => {
    const user = userEvent.setup()
    actualizarContrato.mockResolvedValue()
    await montar() // 2026-01-15 → 2027-01-15 = 1 año exacto

    expect(plazoSelect()).toHaveValue('12')
    expect(screen.queryByLabelText('Fecha de vencimiento')).not.toBeInTheDocument()

    // Con preset elegido no hay campo de vencimiento: se recalcula y viaja así.
    escribirFecha('Fecha de inicio', '2026-02-15')
    expect(screen.queryByLabelText('Fecha de vencimiento')).not.toBeInTheDocument()

    await user.click(guardar())
    await waitFor(() => expect(actualizarContrato).toHaveBeenCalledTimes(1))
    expect(actualizarContrato.mock.calls[0]![1]).toMatchObject({ fecha_vencimiento: '2027-02-15',
    })
  })
})

describe('ContratoCorregir — producto versionado', () => {
  // ESTADO DE PRODUCCIÓN (2026-08-11): gerencia no publicó el catálogo, así que
  // los 349 contratos llevan condiciones propias. Explicárselo al analista en
  // CADA corrección era ruido —y jerga de base de datos— sobre una elección que
  // no existe: sin catálogo no hay nada que elegir.
  it('sin catálogo publicado no explica nada del origen y la opción está en idioma de analista', async () => {
    await montar() // beforeEach deja productosEstado.data = []

    expect(screen.getByRole('option', { name: 'Mantener las condiciones con las que se firmó',
      }),
    )
      .toBeInTheDocument()
    expect(screen.queryByText(/snapshot/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/catálogo/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/mantiene las condiciones con las que se firmó/i)).not.toBeInTheDocument()
  })

  it('con catálogo publicado SÍ explica la elección, sin jerga', async () => {
    productosEstado.data = [CONDICION_VIGENTE] // el contrato sigue con las suyas
    await montar()

    expect(screen.getByText(/Este contrato mantiene las condiciones con las que se firmó/))
      .toBeInTheDocument()
    expect(screen.queryByText(/snapshot/i)).not.toBeInTheDocument()
  })

  it('una condición vigente fija los términos estructurales y limita la tasa efectiva', async () => {
    const user = userEvent.setup()
    productosEstado.data = [CONDICION_VIGENTE]
    await montar({
      producto_condicion_id: CONDICION_VIGENTE.condicion_id,
      producto_id: CONDICION_VIGENTE.producto_id,
      producto_codigo: CONDICION_VIGENTE.producto_codigo,
      producto_version_id: CONDICION_VIGENTE.version_id,
      producto_version: CONDICION_VIGENTE.numero_version,
      producto_nombre: CONDICION_VIGENTE.version_nombre,
      producto_version_estado: 'publicada',
      categoria: CONDICION_VIGENTE.categoria,
      modalidad: CONDICION_VIGENTE.modalidad,
      tasa_anual: 16,
    })

    expect(screen.getByLabelText('Categoría')).toBeDisabled()
    expect(screen.getByLabelText('Tipo de interés')).toBeDisabled()
    expect(screen.getByLabelText('Modalidad de pago')).toBeDisabled()
    expect(screen.getByLabelText('Moneda')).toBeDisabled()
    expect(screen.getByLabelText('Plazo')).toBeDisabled()

    // Rentabilidad R3: la tasa vigente (16%) queda bloqueada aunque el producto de catálogo admita 14–18%:
    // cambiarla exige autorización de Gerencia. Guardar conserva el 16%.
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByText(/Tasa vigente del contrato: 16%/)).toBeInTheDocument()
    await user.click(guardar())

    await waitFor(() => expect(actualizarContrato).toHaveBeenCalledTimes(1))
    expect(actualizarContrato.mock.calls[0]![1]).toMatchObject({ tasa_anual: 16 })
  })

  it('una autorización que caduca entre dos ticks del reloj no deja guardar por encima de la tasa vigente (Codex R3 ronda 2 #4)', async () => {
    const user = userEvent.setup()
    // Misma huella que el contrato del fixture (capital, moneda, fechas, modalidad, tipo, condición); vence en 1,5 s.
    rentabilidadDobles.solicitudes = [{
      id: 's-exp', estado: 'aprobada', estado_efectivo: 'aprobada', vigente: true, categoria: 'nuevo', cliente_id: 'cli-1', cliente_nombre: 'CLIENTE PORTAL UNO',
      // La condición va NULL: el contrato lleva el snapshot legacy del puente, que el formulario no puede declarar
      // (lo sintetiza el servidor al guardar), y el candado de R4 normaliza igual en su orilla.
      contrato_origen_id: null, contrato_origen_numero: null, producto_condicion_id: null,
      capital: 10000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple', fecha_inicio: '2026-01-15', fecha_vencimiento: '2027-01-15',
      tasa_base: 15, regla_base: 'primera_inversion', tasa_solicitada: 17, tasa_maxima_autorizada: 17, motivo: 'Referido', motivo_resolucion: null, motivo_analista: null,
      prioridad_bandeja: false, contratos_previos: 0, solicitada_por: 'yo', solicitante_nombre: 'YO', solicitada_en: '2026-09-06T10:00:00Z',
      vence_en: new Date(Date.now() + 1500).toISOString(), resuelta_por: 'g', resolutor_nombre: 'GERENCIA', resuelta_en: '2026-09-06T11:00:00Z',
      respondida_por_analista_en: null, contrato_id: null, es_mia: true, puede_resolver: false, puede_responder: false,
    }]
    await montar()
    const input = screen.getByLabelText('Tasa anual (%)') as HTMLInputElement
    // Con la autorización viva el campo se habilita entre 15 y 17 (y conserva el 15 persistido); el analista escribe 17…
    await waitFor(() => expect(input).toBeEnabled())
    expect(input).not.toHaveAttribute('readonly')
    expect(input.value).toBe('15')
    fireEvent.change(input, { target: { value: '17' } })
    // …pero la autorización vence antes de guardar y el reloj del bloque solo refresca cada minuto.
    await new Promise((r) => setTimeout(r, 1700))
    await user.click(guardar())
    expect(await screen.findByRole('alert')).toHaveTextContent(/La autorización de Gerencia venció/)
    expect(actualizarContrato).not.toHaveBeenCalled()
  })

  it('una condición vigente puede precargar los términos de la corrección', async () => {
    const user = userEvent.setup()
    productosEstado.data = [CONDICION_VIGENTE]
    actualizarContrato.mockResolvedValue()
    await montar()

    await user.selectOptions(screen.getByLabelText('Producto de inversión'), CONDICION_VIGENTE.condicion_id)
    expect(screen.getByLabelText('Categoría')).toHaveValue('renovacion')
    expect(screen.getByLabelText('Modalidad de pago')).toHaveValue('trimestral')
    expect(screen.getByLabelText('Plazo')).toHaveValue('12 meses')

    // Rentabilidad R3: la condición precarga categoría, modalidad y plazo, pero NO la tasa: la vigente del contrato
    // (15%) se mantiene hasta que Gerencia autorice otra.
    expect((screen.getByLabelText('Tasa anual (%)') as HTMLInputElement).value).toBe('15')
    await user.click(guardar())
    await waitFor(() => expect(actualizarContrato).toHaveBeenCalledTimes(1))
    expect(actualizarContrato.mock.calls[0]![1]).toMatchObject({
      categoria: 'renovacion',
      modalidad: 'trimestral',
      tasa_anual: 15,
    })
  })
})

describe('ContratoCorregir — no se guarda una corrección sin cuotas de interés', () => {
  it('bajar a 6 meses con modalidad anual deja el cronograma sin interés: corte ANTES del servidor', async () => {
    const user = userEvent.setup()
    await montar()

    await user.selectOptions(screen.getByLabelText('Modalidad de pago'), 'anual')
    await user.selectOptions(plazoSelect(), '6')

    // El cronograma NO está vacío: trae la fila del retorno del capital (por eso
    // el guard viejo `length === 0` no podía dispararse nunca).
    expect(screen.queryByText(/Completa capital, tasa y fechas/)).not.toBeInTheDocument()

    await user.click(guardar())
    expect(await screen.findByRole('alert')).toHaveTextContent(/no tiene NINGUNA cuota de interés/)
    expect(actualizarContrato).not.toHaveBeenCalled()
  })
})
