// Tests del detalle de contrato — foco en los CO-TITULARES (cuentas
// mancomunadas). El bug que fijan: `titulares = … ?? []` colapsaba "no se pudo
// cargar" con "no tiene", y como el bloque estaba condicionado a length > 0, un
// fallo de red se pintaba como "este contrato no es mancomunado". Eso es una
// afirmación FALSA sobre quién es titular legal del capital. Se mockea
// @/data/crm-queries (sin red) y se monta dentro de <Dialog> porque DialogTitle
// (Radix) exige el contexto del diálogo, igual que en la pantalla.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Dialog } from '@/components/ui/dialog'
import { CrmApiError, type AtribucionContrato } from '@/data/crm-api'
import type { ContratoRow, Cuota, Titular } from '@/lib/clientes-tipos'

type Consulta<T> = {
  data: T
  isError: boolean
  isSuccess: boolean
  error: unknown
  refetch: () => void
  isFetching: boolean
}

let TITULARES: Consulta<Titular[] | null> = consulta([])
let CRONOGRAMA: Consulta<Cuota[] | null> = consulta([])
let ATRIBUCION: AtribucionContrato | null = null
let REFETCH_ATRIBUCION = vi.fn()
const MUTACIONES = vi.hoisted(() => ({ reasignar: vi.fn() }))

function consulta<T>(data: T, error: unknown = null): Consulta<T> {
  return {
    data,
    isError: error != null,
    isSuccess: error == null,
    error,
    refetch: vi.fn(),
    isFetching: false,
  }
}

vi.mock('@/data/crm-api', async (importActual) => ({
  ...(await importActual<typeof import('@/data/crm-api')>()),
  reasignarAnalistaContrato: MUTACIONES.reasignar,
}))

const CONTRATO: ContratoRow = {
  id: 'k-1',
  numero_contrato: '2026-01-000123',
  cliente_id: 'c-1',
  cliente_nombre: 'CLIENTE PORTAL UNO',
  capital: 10000,
  moneda: 'PEN',
  tasa_anual: 15,
  modalidad: 'mensual',
  tipo_interes: 'simple',
  categoria: 'nuevo',
  estado: 'activo',
  fecha_inicio: '2026-07-08',
  fecha_vencimiento: '2027-07-08',
  fecha_cierre_comercial: '2026-07-08',
  notas_internas: null,
  creado_por: 'yo',
  creado_en: new Date().toISOString(),
  producto_condicion_id: '10000000-0000-4000-8000-000000000001',
  producto_id: '20000000-0000-4000-8000-000000000001',
  producto_codigo: 'RENTA-BASE',
  producto_version_id: '30000000-0000-4000-8000-000000000001',
  producto_version: 2,
  producto_nombre: 'Plan Base 2026',
  producto_version_estado: 'publicada',
}

vi.mock('@/data/crm-queries', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-queries')>()
  return {
    ...actual,
    useContrato: () => consulta(CONTRATO),
    useCronograma: () => CRONOGRAMA,
    useTitulares: () => TITULARES,
    // P-055 Fase 3: el detalle pregunta de quién es la venta. Sin atribución el
    // bloque no se pinta, que es justo lo que estas pruebas esperan ver.
    useAtribucionContrato: () => ({
      ...consulta(ATRIBUCION),
      refetch: REFETCH_ATRIBUCION,
    }),
  }
})

const { ContratoDetalle } = await import('./contrato-detalle')

beforeEach(() => {
  TITULARES = consulta([])
  CRONOGRAMA = consulta([])
  ATRIBUCION = null
  REFETCH_ATRIBUCION = vi.fn()
  MUTACIONES.reasignar.mockReset().mockResolvedValue(undefined)
})

function montar(
  opciones: {
    puedeEliminar?: boolean
    onEliminar?: () => Promise<void> | void
    analistas?: { perfil_id: string; nombre_completo: string }[]
    puedeReasignar?: boolean
  } = {},
) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return Object.assign(render(
    <QueryClientProvider client={queryClient}>
      <Dialog open onClose={vi.fn()} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId="k-1" onCerrar={vi.fn()} {...opciones} />
      </Dialog>
    </QueryClientProvider>,
  ), { queryClient })
}

describe('ContratoDetalle · co-titulares', () => {
  it('no ofrece hard-delete a quien no recibió la capacidad administrativa', () => {
    TITULARES = consulta([])
    montar()
    expect(screen.queryByRole('button', { name: 'Eliminar contrato' })).not.toBeInTheDocument()
  })

  it('exige una segunda confirmación antes de ejecutar el hard-delete', async () => {
    TITULARES = consulta([])
    const onEliminar = vi.fn().mockResolvedValue(undefined)
    const { default: userEvent } = await import('@testing-library/user-event')
    const user = userEvent.setup()
    montar({ puedeEliminar: true, onEliminar })

    await user.click(screen.getByRole('button', { name: 'Eliminar contrato' }))
    expect(onEliminar).not.toHaveBeenCalled()
    expect(screen.getByRole('alert')).toHaveTextContent(/todas las revisiones del PDF/i)

    await user.click(screen.getByRole('button', { name: /Sí, eliminar contrato y PDF/i }))
    expect(onEliminar).toHaveBeenCalledOnce()
  })

  it('al reasignar refresca la atribución e invalida el núcleo compartido de métricas', async () => {
    ATRIBUCION = {
      contrato_id: 'k-1',
      analista_id: 'v-1',
      analista_nombre: 'ANA UNO',
      es_demo: false,
      registrado_por: 'ANA UNO',
      reasignaciones: [],
    }
    const { default: userEvent } = await import('@testing-library/user-event')
    const user = userEvent.setup()
    const { queryClient } = montar({
      puedeReasignar: true,
      analistas: [
        { perfil_id: 'v-1', nombre_completo: 'ANA UNO' },
        { perfil_id: 'v-2', nombre_completo: 'BRUNO DOS' },
      ],
    })
    const invalidar = vi.spyOn(queryClient, 'invalidateQueries')

    await user.click(screen.getByRole('button', { name: 'Reasignar' }))
    await user.selectOptions(screen.getByLabelText('Pasa a'), 'v-2')
    await user.type(screen.getByLabelText('Motivo'), 'Corrección de atribución')
    await user.click(screen.getByRole('button', { name: 'Reasignar' }))

    await vi.waitFor(() => {
      expect(MUTACIONES.reasignar).toHaveBeenCalledWith(
        'k-1',
        'v-2',
        'Corrección de atribución',
      )
      expect(REFETCH_ATRIBUCION).toHaveBeenCalledOnce()
      expect(invalidar).toHaveBeenCalledWith({ queryKey: ['crm', 'metricas'] })
    })
  })

  it('muestra el producto y la versión contractual de origen', () => {
    TITULARES = consulta([])
    montar()

    expect(screen.getByText('RENTA-BASE · Plan Base 2026')).toBeInTheDocument()
    expect(screen.getByText('v2 · publicada')).toBeInTheDocument()
  })

  it('resume vencimientos, próxima cuota y saldo antes del cronograma', () => {
    CRONOGRAMA = consulta([
      {
        id: 'cuota-pagada',
        numero_cuota: 1,
        fecha_programada: '2026-08-08',
        monto_programado: 300,
        estado: 'pagado',
        tipo: 'cuota',
        fecha_pago_real: '2026-08-08',
        monto_pagado: 300,
      },
      {
        id: 'cuota-vencida',
        numero_cuota: 2,
        fecha_programada: '2026-09-08',
        monto_programado: 400,
        estado: 'vencido',
        tipo: 'cuota',
        fecha_pago_real: null,
        monto_pagado: null,
      },
      {
        id: 'cuota-pendiente',
        numero_cuota: 3,
        fecha_programada: '2026-10-08',
        monto_programado: 500,
        estado: 'pendiente',
        tipo: 'cuota',
        fecha_pago_real: null,
        monto_pagado: null,
      },
      {
        id: 'retorno-pendiente',
        numero_cuota: 4,
        fecha_programada: '2027-07-08',
        monto_programado: 10000,
        estado: 'trasladado',
        tipo: 'retorno',
        fecha_pago_real: null,
        monto_pagado: null,
      },
    ])

    montar()

    const resumen = screen.getByRole('region', { name: 'Resumen del cronograma' })
    expect(resumen).toHaveTextContent(/Cuotas vencidas\s*1/)
    expect(resumen).toHaveTextContent(/Próxima cuota.*S\/ 500/)
    expect(resumen).toHaveTextContent(/Saldo por pagar\s*S\/ 900/)
  })

  it('con co-titulares los lista', () => {
    TITULARES = consulta([{ nombre_completo: 'MARIA CO TITULAR', tipo_documento: 'CE', documento: '001234567', orden: 1,
      },
    ])
    montar()
    expect(screen.getByText('Co-titulares')).toBeInTheDocument()
    expect(screen.getByText('MARIA CO TITULAR')).toBeInTheDocument()
  })

  it('sin co-titulares ([] real) no pinta el bloque NI un aviso de fallo', () => {
    TITULARES = consulta([])
    montar()
    expect(screen.queryByText('Co-titulares')).not.toBeInTheDocument()
    expect(screen.queryByText(/No se sabe si este contrato tiene co-titulares/)).not.toBeInTheDocument()
  })

  it('si la carga FALLA lo dice — y NO afirma que el contrato no tenga co-titulares', () => {
    TITULARES = consulta(null, new CrmApiError('No se pudieron cargar los co-titulares.', 'POSTGREST_ERROR'))
    montar()
    // El bloque existe y admite que el dato no se pudo leer, con reintento.
    expect(screen.getByText('Co-titulares')).toBeInTheDocument()
    expect(screen.getByText('No se pudieron cargar los co-titulares.')).toBeInTheDocument()
    expect(screen.getByText(/NO significa que no los tenga/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Reintentar/ })).toBeInTheDocument()
  })

  it('el reintento del fallo de co-titulares vuelve a pedir las tres lecturas', async () => {
    const fallo = consulta<Titular[] | null>(null, new CrmApiError('Sin conexión.', 'NETWORK'))
    TITULARES = fallo
    const { default: userEvent } = await import('@testing-library/user-event')
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(fallo.refetch).toHaveBeenCalled()
  })

  it('mientras cargan (data null, sin error) no afirma nada: skeleton, no vacío', () => {
    TITULARES = consulta<Titular[] | null>(null)
    montar()
    expect(screen.queryByText('Co-titulares')).not.toBeInTheDocument()
    expect(screen.queryByText(/NO significa que no los tenga/)).not.toBeInTheDocument()
    // El hueco se reserva con un skeleton marcado como ocupado.
    expect(document.querySelectorAll('[aria-busy]').length).toBeGreaterThan(0)
  })
})
