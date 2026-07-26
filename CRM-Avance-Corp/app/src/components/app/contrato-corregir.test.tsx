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
import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Dialog } from '@/components/ui/dialog'
import type { ContratoRow } from '@/lib/clientes-tipos'
import * as crmApi from '@/data/crm-api'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, actualizarContrato: vi.fn(), obtenerTitulares: vi.fn() }
})

const { ContratoCorregir } = await import('./contrato-corregir')
const actualizarContrato = vi.mocked(crmApi.actualizarContrato)
const obtenerTitulares = vi.mocked(crmApi.obtenerTitulares)

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
    notas_internas: null,
    creado_por: 'yo',
    creado_en: new Date().toISOString(), // ventana de 5 h viva
    ...over,
  }
}

/** Monta el form y espera a que los co-titulares terminen de precargarse. */
async function montar(over: Partial<ContratoRow> = {}) {
  obtenerTitulares.mockResolvedValue([])
  const onGuardado = vi.fn()
  const onCerrar = vi.fn()
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
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
  fireEvent.change(screen.getByLabelText(etiqueta), { target: { value: valor } })
}

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
    const [id, input] = actualizarContrato.mock.calls[0]!
    expect(id).toBe('ctr-1')
    expect(input).toMatchObject({ fecha_inicio: '2026-02-15', fecha_vencimiento: '2027-07-15' })
  })

  it('con plazo personalizado se puede mover el vencimiento a mano (y es lo que viaja)', async () => {
    const user = userEvent.setup()
    actualizarContrato.mockResolvedValue()
    await montar({ fecha_vencimiento: '2027-07-15' })

    escribirFecha('Fecha de vencimiento', '2027-10-15')
    await user.click(guardar())

    await waitFor(() => expect(actualizarContrato).toHaveBeenCalledTimes(1))
    expect(actualizarContrato.mock.calls[0]![1]).toMatchObject({ fecha_vencimiento: '2027-10-15' })
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
    expect(actualizarContrato.mock.calls[0]![1]).toMatchObject({ fecha_vencimiento: '2027-02-15' })
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
