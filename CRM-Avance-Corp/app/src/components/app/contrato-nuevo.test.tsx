// Tests de ContratoNuevo centrados en el guard de DINERO: un contrato SIN
// cuotas de interés no puede crearse. El bug que fijan (auditoría 2026-07-25):
// el guard era `cronograma.length === 0`, pero generarCronograma SIEMPRE empuja
// la fila del RETORNO del capital → la longitud nunca es 0 y el guard no podía
// dispararse jamás. Se mockea @/data/crm-api (sin red) conservando CrmApiError.
import { beforeEach, describe, expect, it, vi } from 'vitest'
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

const cuentasEstado = vi.hoisted(() => ({
  error: false,
  pending: false,
  fetching: false,
  ocultarPen: false,
  refetch: vi.fn(),
}))

vi.mock('@/data/crm-queries', () => ({
  useCuentasBancariasCliente: vi.fn((_clienteId: string, moneda: 'PEN' | 'USD') => ({
    data: moneda === 'PEN' && !cuentasEstado.ocultarPen
      ? [{
          cuenta_id: null,
          moneda: 'PEN',
          banco: 'BCP',
          tipo_cuenta: 'ahorros',
          numero_cuenta: '191000001234',
          cci: '00112233445566778899',
          titular_distinto: false,
          beneficiario_nombre: null,
          beneficiario_dni: null,
          origen: 'perfil',
          es_cuenta_perfil: true,
          creada_en: null,
        }]
      : [],
    isPending: cuentasEstado.pending,
    isError: cuentasEstado.error,
    isFetching: cuentasEstado.fetching,
    refetch: cuentasEstado.refetch,
  })),
}))

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
  await user.click(screen.getByRole('radio', { name: /BCP/ }))
}

const boton = () => screen.getByRole('button', { name: /Crear contrato/ })

describe('ContratoNuevo — un contrato SIN cuotas de interés no se crea', () => {
  beforeEach(() => {
    cuentasEstado.error = false
    cuentasEstado.pending = false
    cuentasEstado.fetching = false
    cuentasEstado.ocultarPen = false
    cuentasEstado.refetch.mockReset()
    crearContrato.mockReset()
  })

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
    crearContrato.mockResolvedValue({
      id: 'ctr-1',
      numero_contrato: '2026-01-000777',
      cuenta_bancaria_id: 'cb-1',
    })
    const { onCreado } = montar()
    await llenarBase(user)
    await user.selectOptions(screen.getByLabelText('Plazo'), '6')

    expect(screen.queryByText(/NINGUNA cuota de interés/)).not.toBeInTheDocument()
    expect(boton()).toBeEnabled()
    await user.click(boton())

    expect(crearContrato).toHaveBeenCalledTimes(1)
    const [input, cronograma] = crearContrato.mock.calls[0]!
    expect(input.cuenta_pago).toEqual({
      tipo: 'perfil',
      cuenta_esperada: {
        banco: 'BCP',
        tipo_cuenta: 'ahorros',
        numero_cuenta: '191000001234',
        cci: '00112233445566778899',
        titular_distinto: false,
        beneficiario_nombre: null,
        beneficiario_dni: null,
      },
    })
    expect(cronograma.filter((c) => c.tipo === 'cuota')).toHaveLength(6)
    expect(cronograma.filter((c) => c.tipo === 'retorno')).toHaveLength(1)
    expect(onCreado).toHaveBeenCalledWith('2026-01-000777')
  })

  it('anuncia y enfoca el resumen cuando una validación bloquea el envío', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)
    await user.clear(screen.getByLabelText('N° de contrato'))

    await user.click(boton())

    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent(/exactamente 6 dígitos/)
    await vi.waitFor(() => expect(alerta).toHaveFocus())
  })

  it('asocia el error bancario al campo exacto, lo enfoca y lo retira al corregir', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)
    await user.selectOptions(screen.getByLabelText('Moneda'), 'USD')
    await user.click(screen.getByRole('radio', { name: /Añadir una cuenta nueva/ }))
    await user.selectOptions(screen.getByLabelText('Banco'), 'BBVA')
    await user.selectOptions(screen.getByLabelText('Tipo de cuenta'), 'corriente')
    await user.type(screen.getByLabelText('N° de cuenta'), 'USD-778899')
    const cci = screen.getByLabelText('CCI — Código Interbancario')
    await user.type(cci, '123')

    await user.click(boton())

    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent(/exactamente 20 dígitos/)
    expect(cci).toHaveAttribute('aria-invalid', 'true')
    expect(cci).toHaveAttribute('aria-describedby', expect.stringContaining('ct-error-resumen'))
    await vi.waitFor(() => expect(cci).toHaveFocus())

    await user.type(cci, '45678901234567890')
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(cci).not.toHaveAttribute('aria-invalid')
  })

  it('envía el formulario con Enter cuando todos los datos son válidos', async () => {
    const user = userEvent.setup()
    crearContrato.mockResolvedValue({
      id: 'ctr-enter',
      numero_contrato: '2026-01-000777',
      cuenta_bancaria_id: 'cb-enter',
    })
    montar()
    await llenarBase(user)

    screen.getByLabelText('N° de contrato').focus()
    await user.keyboard('{Enter}')

    expect(crearContrato).toHaveBeenCalledTimes(1)
  })

  it('avisa y exige otra elección si una revalidación retira la cuenta seleccionada', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)

    cuentasEstado.ocultarPen = true
    await user.type(screen.getByLabelText('Notas internas (opcional)'), 'x')

    const aviso = await screen.findByText(/cambió o ya no está disponible/)
    expect(aviso).toHaveAttribute('role', 'status')
    expect(boton()).toBeDisabled()
    expect(screen.getByRole('radio', { name: /Añadir una cuenta nueva/ })).not.toBeChecked()
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

  it('cambiar PEN→USD limpia la selección y permite registrar la nueva cuenta inline', async () => {
    const user = userEvent.setup()
    crearContrato.mockResolvedValue({
      id: 'ctr-2',
      numero_contrato: '2026-01-000777',
      cuenta_bancaria_id: 'cb-2',
    })
    montar()
    await llenarBase(user)

    await user.selectOptions(screen.getByLabelText('Moneda'), 'USD')
    expect(boton()).toBeDisabled()
    expect(screen.getByText(/todavía no tiene una cuenta completa/)).toBeInTheDocument()

    await user.click(screen.getByRole('radio', { name: /Añadir una cuenta nueva/ }))
    await user.selectOptions(screen.getByLabelText('Banco'), 'BBVA')
    await user.selectOptions(screen.getByLabelText('Tipo de cuenta'), 'corriente')
    await user.type(screen.getByLabelText('N° de cuenta'), 'USD-778899')
    await user.type(screen.getByLabelText('CCI — Código Interbancario'), '12345678901234567890')
    await user.click(boton())

    const [input] = crearContrato.mock.calls[0]!
    expect(input.moneda).toBe('USD')
    expect(input.cuenta_pago).toEqual({
      tipo: 'nueva',
      banco: 'BBVA',
      tipo_cuenta: 'corriente',
      numero_cuenta: 'USD-778899',
      cci: '12345678901234567890',
      titular_distinto: false,
      beneficiario_nombre: null,
      beneficiario_dni: null,
    })
  })
})
