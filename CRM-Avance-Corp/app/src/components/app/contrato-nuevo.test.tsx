// Tests de ContratoNuevo centrados en el guard de DINERO: un contrato SIN
// cuotas de interés no puede crearse. El bug que fijan (auditoría 2026-07-25):
// el guard era `cronograma.length === 0`, pero generarCronograma SIEMPRE empuja
// la fila del RETORNO del capital → la longitud nunca es 0 y el guard no podía
// dispararse jamás. Se mockea @/data/crm-api (sin red) conservando CrmApiError.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Dialog } from '@/components/ui/dialog'
import * as crmApi from '@/data/crm-api'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, crearContrato: vi.fn() }
})

const { ContratoNuevo } = await import('./contrato-nuevo')
const crearContrato = vi.mocked(crmApi.crearContrato)

function montar() {
  const onCreado = vi.fn()
  const onOmitir = vi.fn()
  render(
    <Dialog open onClose={() => undefined}>
      <ContratoNuevo
        clienteId="cli-1"
        clienteNombre="CLIENTE PORTAL UNO"
        onCreado={onCreado}
        onOmitir={onOmitir}
      />
    </Dialog>,
  )
  return { onCreado, onOmitir }
}

/** Mínimo válido: categoría manual + capital + N° de 6 dígitos (tasa ya viene 15). */
async function llenarBase(user: ReturnType<typeof userEvent.setup>) {
  await user.selectOptions(screen.getByLabelText('Categoría'), 'nuevo')
  await user.type(screen.getByLabelText('Capital'), '10000')
  await user.type(screen.getByLabelText('N° de contrato'), '000777')
}

const boton = () => screen.getByRole('button', { name: /Crear contrato/ })

describe('ContratoNuevo — un contrato SIN cuotas de interés no se crea', () => {
  it('6 meses con modalidad anual: el cronograma NO está vacío (trae el retorno) y aun así se bloquea', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)
    // La 1ª cuota anual caería a los 12 meses, después del vencimiento a los 6:
    // cero cuotas de interés y solo la fila del retorno del capital.
    await user.selectOptions(screen.getByLabelText('Modalidad de pago'), 'anual')
    await user.selectOptions(screen.getByLabelText('Plazo'), '6')

    // Prueba de que el guard viejo era imposible: hay cronograma (la vista previa
    // dejó de pedir datos), pero ninguna cuota de interés.
    expect(screen.queryByText(/Completa capital, tasa y fechas/)).not.toBeInTheDocument()
    expect(screen.getByText(/no tiene NINGUNA cuota de interés/)).toBeInTheDocument()
    expect(boton()).toBeDisabled()

    await user.click(boton())
    expect(crearContrato).not.toHaveBeenCalled()
  })

  it('el mismo plazo de 6 meses en modalidad mensual sí paga interés: se crea', async () => {
    const user = userEvent.setup()
    crearContrato.mockResolvedValue({ id: 'ctr-1', numero_contrato: '2026-01-000777' })
    const { onCreado } = montar()
    await llenarBase(user)
    await user.selectOptions(screen.getByLabelText('Plazo'), '6')

    expect(screen.queryByText(/NINGUNA cuota de interés/)).not.toBeInTheDocument()
    expect(boton()).toBeEnabled()
    await user.click(boton())

    expect(crearContrato).toHaveBeenCalledTimes(1)
    const [, cronograma] = crearContrato.mock.calls[0]!
    expect(cronograma.filter((c) => c.tipo === 'cuota')).toHaveLength(6)
    expect(cronograma.filter((c) => c.tipo === 'retorno')).toHaveLength(1)
    expect(onCreado).toHaveBeenCalledWith('2026-01-000777')
  })

  it('vencimiento personalizado más corto que un periodo: mismo bloqueo', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)
    await user.selectOptions(screen.getByLabelText('Plazo'), 'personalizado')
    // Inicio = hoy; un vencimiento a ~20 días no alcanza ni la 1ª cuota mensual.
    const inicio = (screen.getByLabelText('Fecha de inicio') as HTMLInputElement).value
    const venc = new Date(inicio.replace(/-/g, '/'))
    venc.setDate(venc.getDate() + 20)
    await user.type(
      screen.getByLabelText('Fecha de vencimiento'),
      `${venc.getFullYear()}-${String(venc.getMonth() + 1).padStart(2, '0')}-${String(venc.getDate()).padStart(2, '0')}`,
    )

    expect(screen.getByText(/no tiene NINGUNA cuota de interés/)).toBeInTheDocument()
    expect(boton()).toBeDisabled()
    await user.click(boton())
    expect(crearContrato).not.toHaveBeenCalled()
  })
})
