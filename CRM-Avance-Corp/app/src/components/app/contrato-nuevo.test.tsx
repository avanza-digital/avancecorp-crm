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
import { CUENTAS_CLIENTES_DEMO, DATOS_PDF_DEMO } from '@/lib/demo-clientes'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, crearContrato: vi.fn() }
})

const archivoPdf = vi.hoisted(() => ({
  archivar: vi.fn(),
  archivarDemo: vi.fn(),
  descargar: vi.fn(),
  ver: vi.fn(),
}))

vi.mock('@/lib/contrato-pdf-archivo', () => ({
  archivarContratoPdfConfirmado: archivoPdf.archivar,
  ContratoPdfNoSelladoError: class ContratoPdfNoSelladoError extends Error {},
  descargarArchivoContratoPdf: archivoPdf.descargar,
  etiquetaEstadoContratoPdf: (estado: string) => estado,
  verArchivoContratoPdf: archivoPdf.ver,
}))

vi.mock('@/lib/contrato-pdf-demo-loader', () => ({
  archivarContratoPdfDemoHabilitado: archivoPdf.archivarDemo,
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

function montar(
  pdfDatosDemo = undefined as (typeof DATOS_PDF_DEMO)[string] | undefined,
  opciones: {
    validarNumero?: (numero: string) => string | null
  } = {},
) {
  const onCreado = vi.fn()
  const onOmitir = vi.fn()
  const onConfirmado = vi.fn()
  const onEnviandoCambio = vi.fn()
  const vista = render(
    <Dialog open onClose={() => undefined}>
      <ContratoNuevo
        clienteId="cli-1"
        clienteNombre="CLIENTE PORTAL UNO"
        pdfDatosDemo={pdfDatosDemo}
        cuentasDemo={pdfDatosDemo ? CUENTAS_CLIENTES_DEMO['dc-cli-1'] : undefined}
        {...(opciones.validarNumero ? { validarNumero: opciones.validarNumero } : {})}
        onConfirmado={onConfirmado}
        onEnviandoCambio={onEnviandoCambio}
        onCreado={onCreado}
        onOmitir={onOmitir}
      />
    </Dialog>,
  )
  return { ...vista, onCreado, onOmitir, onConfirmado, onEnviandoCambio }
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
    archivoPdf.archivar.mockReset()
    archivoPdf.archivarDemo.mockReset()
    archivoPdf.descargar.mockReset()
    archivoPdf.ver.mockReset()
    archivoPdf.archivar.mockResolvedValue({
      contratoId: 'ctr-1',
      storagePath: 'ctr-1/contrato.pdf',
      nombreArchivo: 'Contrato-2026-01-000777-CLIENTE-PORTAL-UNO.pdf',
      sha256: 'a'.repeat(64),
      bytes: 123,
      blob: new Blob(['%PDF']),
    })
    archivoPdf.archivarDemo.mockImplementation(async (contratoId: string) => ({
      contratoId,
      storagePath: `${contratoId}/contrato.pdf`,
      nombreArchivo: 'Contrato-2026-01-000777-CLIENTE-PORTAL-UNO.pdf',
      sha256: 'b'.repeat(64),
      bytes: 123,
      blob: new Blob(['%PDF']),
    }))
  })

  it('6 meses con modalidad anual: el cronograma NO está vacío (trae el retorno) y aun así se bloquea', async () => {
    const user = userEvent.setup()
    montar()
    await llenarBase(user)
    await user.selectOptions(screen.getByLabelText('Modalidad de pago'), 'anual')
    await user.selectOptions(screen.getByLabelText('Plazo'), '6')
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
    crearContrato.mockResolvedValue({
      id: 'ctr-1',
      numero_contrato: '2026-01-000777',
      cuenta_bancaria_id: 'cb-1',
      pdf: { contrato_id: 'ctr-1', job_id: 'job-1', estado: 'pendiente', reintentable: true },
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
    expect(archivoPdf.archivar).toHaveBeenCalledWith('ctr-1')
    expect(await screen.findByText('Contrato 2026-01-000777 creado')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver contrato PDF' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Descargar contrato PDF' })).toBeEnabled()
    expect(onCreado).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: 'Finalizar' }))
    expect(onCreado).toHaveBeenCalledWith('2026-01-000777')
  })

  it('en demo archiva una sola versión con el número escrito por el vendedor', async () => {
    const user = userEvent.setup()
    const { onConfirmado, onEnviandoCambio } = montar(DATOS_PDF_DEMO['dc-ct-a'])
    await llenarBase(user)
    await user.selectOptions(screen.getByLabelText('Plazo'), '12')

    await user.click(boton())

    expect(crearContrato).not.toHaveBeenCalled()
    expect(archivoPdf.archivarDemo).toHaveBeenCalledWith(
      expect.stringMatching(/^demo-/),
      expect.objectContaining({
        contrato: expect.objectContaining({ numero: '2026-01-000777', capital: 10_000 }),
      }),
    )
    expect(await screen.findByText('Contrato 2026-01-000777 creado')).toBeInTheDocument()
    const idCreado = archivoPdf.archivarDemo.mock.calls[0]?.[0]
    expect(onConfirmado).toHaveBeenCalledTimes(1)
    expect(onConfirmado).toHaveBeenCalledWith(
      '2026-01-000777',
      expect.objectContaining({ id: idCreado }),
    )
    expect(onEnviandoCambio.mock.calls.map(([estado]) => estado)).toEqual([true, false])
  })

  it('genera identidades demo distintas aunque cliente y número se repitan', async () => {
    const user = userEvent.setup()
    const primera = montar(DATOS_PDF_DEMO['dc-ct-a'])
    await llenarBase(user)
    await user.click(boton())
    await screen.findByText('Contrato 2026-01-000777 creado')
    const primerId = archivoPdf.archivarDemo.mock.calls[0]?.[0]
    primera.unmount()

    montar(DATOS_PDF_DEMO['dc-ct-a'])
    await llenarBase(user)
    await user.click(boton())
    await screen.findByText('Contrato 2026-01-000777 creado')
    const segundoId = archivoPdf.archivarDemo.mock.calls[1]?.[0]

    expect(primerId).toMatch(/^demo-/)
    expect(segundoId).toMatch(/^demo-/)
    expect(segundoId).not.toBe(primerId)
  })

  it('rechaza un número duplicado antes de crear identidad o tocar la caché PDF', async () => {
    const user = userEvent.setup()
    const validarNumero = vi.fn(() => 'Ya existe el contrato demo 2026-01-000777.')
    const { onConfirmado, onEnviandoCambio } = montar(
      DATOS_PDF_DEMO['dc-ct-a'],
      { validarNumero },
    )
    await llenarBase(user)

    await user.click(boton())

    expect(await screen.findByRole('alert')).toHaveTextContent(/ya existe el contrato demo/i)
    expect(validarNumero).toHaveBeenCalledWith('2026-01-000777')
    expect(archivoPdf.archivarDemo).not.toHaveBeenCalled()
    expect(onConfirmado).not.toHaveBeenCalled()
    expect(onEnviandoCambio).not.toHaveBeenCalled()
  })

  it('si el archivo demo falla, reintenta la misma foto sin crear otro contrato', async () => {
    const user = userEvent.setup()
    archivoPdf.archivarDemo.mockRejectedValueOnce(new Error('fallo temporal'))
    const { onCreado } = montar(DATOS_PDF_DEMO['dc-ct-a'])
    await llenarBase(user)

    await user.click(boton())

    await vi.waitFor(() => expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1))
    expect(await screen.findByRole('alert')).toHaveTextContent(/quedó creado.*PDF local no pudo generarse/i)
    expect(crearContrato).not.toHaveBeenCalled()
    expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1)
    const [idInicial, fotoInicial] = archivoPdf.archivarDemo.mock.calls[0]!

    await user.click(screen.getByRole('button', { name: 'Reintentar PDF' }))

    expect(await screen.findByText(/PDF privado archivado correctamente/)).toBeInTheDocument()
    expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(2)
    expect(archivoPdf.archivar).not.toHaveBeenCalled()
    expect(archivoPdf.archivarDemo.mock.calls[1]?.[0]).toBe(idInicial)
    expect(archivoPdf.archivarDemo.mock.calls[1]?.[1]).toBe(fotoInicial)

    expect(onCreado).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Finalizar' }))
    expect(onCreado).toHaveBeenCalledWith(
      '2026-01-000777',
      expect.objectContaining({
        id: idInicial,
        pdfDatos: fotoInicial,
      }),
    )
  })

  it('permite finalizar un contrato confirmado aunque el PDF siga pendiente', async () => {
    const user = userEvent.setup()
    archivoPdf.archivarDemo.mockRejectedValue(new Error('fallo persistente'))
    const { onCreado } = montar(DATOS_PDF_DEMO['dc-ct-a'])
    await llenarBase(user)

    await user.click(boton())

    await vi.waitFor(() => expect(archivoPdf.archivarDemo).toHaveBeenCalledTimes(1))
    expect(await screen.findByRole('alert')).toHaveTextContent(/quedó creado.*PDF local no pudo generarse/i)
    const finalizar = screen.getByRole('button', { name: 'Finalizar' })
    expect(finalizar).toBeEnabled()
    await user.click(finalizar)

    expect(onCreado).toHaveBeenCalledWith(
      '2026-01-000777',
      expect.objectContaining({ id: expect.stringMatching(/^demo-/) }),
    )
    expect(crearContrato).not.toHaveBeenCalled()
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
      pdf: { contrato_id: 'ctr-enter', job_id: 'job-enter', estado: 'pendiente', reintentable: true },
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
      pdf: { contrato_id: 'ctr-2', job_id: 'job-2', estado: 'pendiente', reintentable: true },
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
