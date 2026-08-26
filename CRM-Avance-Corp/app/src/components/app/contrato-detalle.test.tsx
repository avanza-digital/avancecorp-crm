// Tests del detalle de contrato — foco en los CO-TITULARES (cuentas
// mancomunadas). El bug que fijan: `titulares = … ?? []` colapsaba "no se pudo
// cargar" con "no tiene", y como el bloque estaba condicionado a length > 0, un
// fallo de red se pintaba como "este contrato no es mancomunado". Eso es una
// afirmación FALSA sobre quién es titular legal del capital. Se mockea
// @/data/crm-queries (sin red) y se monta dentro de <Dialog> porque DialogTitle
// (Radix) exige el contexto del diálogo, igual que en la pantalla.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { Dialog } from '@/components/ui/dialog'
import { CrmApiError } from '@/data/crm-api'
import type { ContratoRow, Titular } from '@/lib/clientes-tipos'

type Consulta<T> = {
  data: T
  isError: boolean
  isSuccess: boolean
  error: unknown
  refetch: () => void
  isFetching: boolean
}

let TITULARES: Consulta<Titular[] | null> = consulta([])

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
  notas_internas: null,
  creado_por: 'yo',
  creado_en: new Date().toISOString(),
  revision_contrato: '2026-08-25T15:00:00.000Z',
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
    useCronograma: () => consulta([]),
    useTitulares: () => TITULARES,
  }
})

const { ContratoDetalle } = await import('./contrato-detalle')

function montar(
  opciones: {
    puedeEliminar?: boolean
    onEliminar?: () => Promise<void> | void
  } = {},
) {
  return render(
    <Dialog open onClose={vi.fn()} ariaLabel="Detalle del contrato">
      <ContratoDetalle contratoId="k-1" onCerrar={vi.fn()} {...opciones} />
    </Dialog>,
  )
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
    expect(screen.getByRole('alert')).toHaveTextContent(/todas las versiones archivadas del documento/i)

    await user.click(screen.getByRole('button', { name: /Sí, eliminar contrato y documentos/i }))
    expect(onEliminar).toHaveBeenCalledOnce()
  })

  it('muestra solo el nombre comercial del producto, sin identificadores ni versión técnica', () => {
    TITULARES = consulta([])
    montar()

    expect(screen.getByText('Plan Base 2026')).toBeInTheDocument()
    expect(screen.queryByText(/RENTA-BASE/)).not.toBeInTheDocument()
    expect(screen.queryByText('Versión de producto')).not.toBeInTheDocument()
    expect(screen.queryByText(/publicada/i)).not.toBeInTheDocument()
    expect(screen.queryByText(CONTRATO.producto_condicion_id)).not.toBeInTheDocument()
    expect(document.querySelector(`[title*="${CONTRATO.producto_condicion_id}"]`)).toBeNull()
    expect(screen.getByText('Tipo de inversión')).toBeInTheDocument()
    expect(screen.getByText('Frecuencia de pago de intereses')).toBeInTheDocument()
  })

  it('con co-titulares los lista', () => {
    TITULARES = consulta([
      { nombre_completo: 'MARIA CO TITULAR', tipo_documento: 'CE', documento: '001234567', orden: 1 },
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
