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
import type { ProductoCondicionSeleccion } from '@/lib/productos-inversion'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, crearContrato: vi.fn() }
})

const productosEstado = vi.hoisted(() => ({
  data: [] as ProductoCondicionSeleccion[],
  error: false,
  pending: false,
  fetching: false,
  refetch: vi.fn(),
}))

vi.mock('@/data/crm-config-queries', () => ({
  useProductosSeleccionables: () => ({
    data: productosEstado.data,
    isError: productosEstado.error,
    isPending: productosEstado.pending,
    isFetching: productosEstado.fetching,
    refetch: productosEstado.refetch,
  }),
}))

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

const CONDICION_BASE: ProductoCondicionSeleccion = {
  condicion_id: '10000000-0000-4000-8000-000000000001',
  producto_id: '20000000-0000-4000-8000-000000000001',
  producto_codigo: 'RENTA-BASE',
  producto_revision: 2,
  version_id: '30000000-0000-4000-8000-000000000001',
  numero_version: 1,
  version_nombre: 'Plan base 2026',
  vigente_desde: '2026-01-01',
  vigente_hasta: null,
  categoria: 'nuevo',
  moneda: 'PEN',
  plazo_meses: 12,
  modalidad: 'mensual',
  tipo_interes: 'simple',
  capital_minimo: 100,
  capital_maximo: 100_000,
  tasa_referencia: 15,
  tasa_minima: 10,
  tasa_maxima: 20,
}

const CONDICION_ANUAL_6: ProductoCondicionSeleccion = {
  ...CONDICION_BASE,
  condicion_id: '10000000-0000-4000-8000-000000000002',
  plazo_meses: 6,
  modalidad: 'anual',
}

const CONDICION_MENSUAL_6: ProductoCondicionSeleccion = {
  ...CONDICION_BASE,
  condicion_id: '10000000-0000-4000-8000-000000000003',
  plazo_meses: 6,
}

const CONDICION_USD: ProductoCondicionSeleccion = {
  ...CONDICION_BASE,
  condicion_id: '10000000-0000-4000-8000-000000000004',
  moneda: 'USD',
  capital_maximo: 50_000,
}

const RESULTADO_CONTRATO: crmApi.CrearContratoResultado = {
  id: '40000000-0000-4000-8000-000000000001',
  numero_contrato: '2026-01-000777',
  cuenta_bancaria_id: '50000000-0000-4000-8000-000000000001',
  producto_condicion_id: CONDICION_BASE.condicion_id,
  producto_id: CONDICION_BASE.producto_id,
  producto_revision: 2,
  version_id: CONDICION_BASE.version_id,
  version_revision: 1,
  numero_version: 1,
  version_estado: 'publicada',
  version_nombre: CONDICION_BASE.version_nombre,
}

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

/** Mínimo válido: condición publicada + capital + N° de 6 dígitos. */
async function llenarBase(
  user: ReturnType<typeof userEvent.setup>,
  condicion = CONDICION_BASE,
) {
  await user.selectOptions(screen.getByLabelText('Producto de inversión'), condicion.condicion_id)
  await user.clear(screen.getByLabelText('Capital'))
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
    productosEstado.data = [CONDICION_BASE, CONDICION_ANUAL_6, CONDICION_MENSUAL_6, CONDICION_USD]
    productosEstado.error = false
    productosEstado.pending = false
    productosEstado.fetching = false
    productosEstado.refetch.mockReset()
    crearContrato.mockReset()
  })

  it('6 meses con modalidad anual: el cronograma NO está vacío (trae el retorno) y aun así se bloquea', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user, CONDICION_ANUAL_6)
    // La 1ª cuota anual caería a los 12 meses, después del vencimiento a los 6:
    // cero cuotas de interés y solo la fila del retorno del capital.
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
    crearContrato.mockResolvedValue({ ...RESULTADO_CONTRATO, producto_condicion_id: CONDICION_MENSUAL_6.condicion_id })
    const { onCreado } = montar()
    await llenarBase(user, CONDICION_MENSUAL_6)

    expect(screen.queryByText(/NINGUNA cuota de interés/)).not.toBeInTheDocument()
    expect(boton()).toBeEnabled()
    await user.click(boton())

    expect(crearContrato).toHaveBeenCalledTimes(1)
    const [input, cronograma] = crearContrato.mock.calls[0]!
    expect(input.producto_condicion_id).toBe(CONDICION_MENSUAL_6.condicion_id)
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
    await user.selectOptions(screen.getByLabelText('Producto de inversión'), CONDICION_USD.condicion_id)
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
    crearContrato.mockResolvedValue(RESULTADO_CONTRATO)
    montar()
    await llenarBase(user)

    screen.getByLabelText('N° de contrato').focus()
    await user.keyboard('{Enter}')

    expect(crearContrato).toHaveBeenCalledTimes(1)
  })

  it('no habilita altas sin una condición publicada', () => {
    montar()

    expect(screen.getByLabelText('Categoría')).toBeDisabled()
    expect(screen.getByLabelText('Moneda')).toBeDisabled()
    expect(boton()).toBeDisabled()
    expect(crearContrato).not.toHaveBeenCalled()
  })

  it('falla cerrado si el catálogo no se puede revalidar', async () => {
    const user = userEvent.setup()
    productosEstado.error = true
    productosEstado.data = []
    montar()

    expect(screen.getByText(/No se pudo cargar el catálogo/)).toBeInTheDocument()
    expect(boton()).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(productosEstado.refetch).toHaveBeenCalledTimes(1)
    expect(crearContrato).not.toHaveBeenCalled()
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

  it('bloquea una tasa fuera del rango de la condición publicada', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)
    await user.clear(screen.getByLabelText('Tasa anual (%)'))
    await user.type(screen.getByLabelText('Tasa anual (%)'), '21')

    await user.click(boton())
    expect(await screen.findByRole('alert')).toHaveTextContent(/entre 10% y 20%/)
    expect(crearContrato).not.toHaveBeenCalled()
  })

  it('cambiar PEN→USD limpia la selección y permite registrar la nueva cuenta inline', async () => {
    const user = userEvent.setup()
    crearContrato.mockResolvedValue({ ...RESULTADO_CONTRATO, producto_condicion_id: CONDICION_USD.condicion_id })
    montar()
    await llenarBase(user)

    await user.selectOptions(screen.getByLabelText('Producto de inversión'), CONDICION_USD.condicion_id)
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
