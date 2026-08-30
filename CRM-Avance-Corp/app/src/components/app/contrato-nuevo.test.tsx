// Tests de ContratoNuevo centrados en el guard de DINERO: un contrato SIN
// cuotas de interés no puede crearse. El bug que fijan (auditoría 2026-07-25):
// el guard era `cronograma.length === 0`, pero generarCronograma SIEMPRE empuja
// la fila del RETORNO del capital → la longitud nunca es 0 y el guard no podía
// dispararse jamás. Se mockea @/data/crm-api (sin red) conservando CrmApiError.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Dialog } from '@/components/ui/dialog'
import * as crmApi from '@/data/crm-api'
import { CUENTAS_CLIENTES_DEMO, DATOS_PDF_DEMO } from '@/lib/demo-clientes'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, crearContrato: vi.fn(), completarDomicilioCliente: vi.fn() }
})

const archivoPdf = vi.hoisted(() => ({
  archivar: vi.fn(),
  archivarDemo: vi.fn(),
  descargar: vi.fn(),
  ver: vi.fn(),
}))

// La frontera del régimen documental (`esContratoRegimenAnterior`) NO se dobla:
// es lógica pura y decide si sale la ventana del domicilio. Mockearla haría que
// estas pruebas aprobaran una regla inventada por la propia prueba.
vi.mock('@/lib/contrato-pdf-archivo', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/contrato-pdf-archivo')>()),
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

// Pre-vuelo legal: qué le falta al cliente (o al propio analista) para emitir.
const legalesEstado = vi.hoisted(() => ({
  faltaDomicilio: false,
  faltanCliente: [] as string[],
  faltanAnalista: [] as string[],
  error: false,
  refetch: vi.fn(),
}))

vi.mock('@/data/crm-queries', () => ({
  // ATR-3: el aviso de cadena de upgrade no aplica en estos escenarios — sin dato.
  useAtribucionContrato: vi.fn(() => ({ data: null, isPending: false, isError: false })),
  useDatosLegalesContrato: vi.fn((clienteId: string) => ({
    data: legalesEstado.error
      ? undefined
      : {
          clienteId,
          faltaDomicilio: legalesEstado.faltaDomicilio,
          faltanCliente: legalesEstado.faltanCliente,
          faltanAnalista: legalesEstado.faltanAnalista,
        },
    isPending: false,
    isError: legalesEstado.error,
    isFetching: false,
    refetch: legalesEstado.refetch,
  })),
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
const crmQueries = await import('@/data/crm-queries')
const crearContrato = vi.mocked(crmApi.crearContrato)
const completarDomicilio = vi.mocked(crmApi.completarDomicilioCliente)

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
    legalesEstado.faltaDomicilio = false
    legalesEstado.faltanCliente = []
    legalesEstado.faltanAnalista = []
    legalesEstado.error = false
    legalesEstado.refetch.mockReset()
    completarDomicilio.mockReset()
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

  it('en demo archiva una sola versión con el número escrito por el analista', async () => {
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

// ── El domicilio legal faltante (2026-08-19) ─────────────────────────────────
// El bug real: crear_contrato_con_cuenta_pdf_v2 reserva el PDF en la MISMA
// transacción y private.contrato_pdf_snapshot_v2_base exige el domicilio del
// titular. Sin él, el raise revertía el contrato ENTERO con un mensaje que no
// decía cuál era el dato ausente. 313 de los 319 clientes con contrato de
// producción estaban así, y el analista tampoco podía escribirlo: la policy
// perfiles_analista_update solo le abre 5 h desde que él creó al cliente.
describe('ContratoNuevo — el domicilio legal que falta', () => {
  beforeEach(() => {
    cuentasEstado.error = false
    cuentasEstado.pending = false
    cuentasEstado.fetching = false
    cuentasEstado.ocultarPen = false
    legalesEstado.faltaDomicilio = false
    legalesEstado.faltanCliente = []
    legalesEstado.faltanAnalista = []
    legalesEstado.error = false
    legalesEstado.refetch.mockReset()
    completarDomicilio.mockReset()
    crearContrato.mockReset()
    crearContrato.mockResolvedValue({
      id: 'ctr-1',
      numero_contrato: '2026-01-000777',
      cuenta_bancaria_id: null,
      pdf: { estado: 'pendiente' },
    } as never)
    archivoPdf.archivar.mockResolvedValue({
      contratoId: 'ctr-1',
      storagePath: 'ctr-1/contrato.pdf',
      nombreArchivo: 'Contrato.pdf',
      sha256: 'a'.repeat(64),
      bytes: 123,
      blob: new Blob(['%PDF']),
    })
  })

  it('sin domicilio: sale la ventana, el alta queda frenada y NO se intenta crear el contrato', async () => {
    const user = userEvent.setup()
    legalesEstado.faltaDomicilio = true
    legalesEstado.faltanCliente = ['domicilio']
    montar()
    await llenarBase(user)

    expect(screen.getByText(/Falta el domicilio legal de CLIENTE PORTAL UNO/)).toBeInTheDocument()
    expect(boton()).toBeDisabled()

    await user.click(boton())
    expect(crearContrato).not.toHaveBeenCalled()
  })

  // El disabled del botón y el guard de guardar() son DOS defensas: si solo se
  // probara el botón, quitar el guard dejaría el test en verde. Este submit
  // directo al <form> se salta el botón y solo puede pararlo el guard.
  it('el guard de guardar() para el alta aunque el botón no estuviera bloqueado', async () => {
    legalesEstado.faltaDomicilio = true
    legalesEstado.faltanCliente = ['domicilio']
    montar()
    // El Dialog vive en un portal: el <form> no cuelga del container de render.
    const formulario = boton().closest('form')!

    fireEvent.submit(formulario)
    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent(/Falta el domicilio legal del cliente/)
    })
    expect(crearContrato).not.toHaveBeenCalled()
  })

  it('al guardarlo se desbloquea el alta y el contrato ya se crea', async () => {
    const user = userEvent.setup()
    legalesEstado.faltaDomicilio = true
    legalesEstado.faltanCliente = ['domicilio']
    completarDomicilio.mockImplementation(async () => {
      legalesEstado.faltaDomicilio = false
      legalesEstado.faltanCliente = []
      return { accion: 'completado' as const }
    })
    montar()
    await llenarBase(user)

    await user.type(
      screen.getByLabelText('Domicilio legal completo'),
      'Av. Los Alamos 123, San Isidro, Lima, Lima',
    )
    await user.click(screen.getByRole('button', { name: /Guardar domicilio/ }))

    expect(completarDomicilio).toHaveBeenCalledWith(
      'cli-1',
      'Av. Los Alamos 123, San Isidro, Lima, Lima',
    )
    expect(screen.queryByText(/Falta el domicilio legal/)).not.toBeInTheDocument()
    expect(boton()).toBeEnabled()

    // El bloque solo puede cerrarse porque se volvió a PREGUNTAR al servidor.
    // Sin este refresco, la caché seguiría diciendo "falta domicilio" y el
    // analista quedaría atrapado justo después de haberlo rellenado — un fallo
    // que el mock no puede reproducir por sí solo (no es una caché de verdad).
    expect(legalesEstado.refetch).toHaveBeenCalledTimes(1)

    await user.click(boton())
    expect(crearContrato).toHaveBeenCalledTimes(1)
  })

  it('un domicilio demasiado corto se rechaza en el navegador, sin llamar al servidor', async () => {
    const user = userEvent.setup()
    legalesEstado.faltaDomicilio = true
    legalesEstado.faltanCliente = ['domicilio']
    montar()

    await user.type(screen.getByLabelText('Domicilio legal completo'), 'Av.')
    await user.click(screen.getByRole('button', { name: /Guardar domicilio/ }))

    expect(completarDomicilio).not.toHaveBeenCalled()
    expect(screen.getByRole('alert')).toHaveTextContent(/entre 15 y 240 caracteres/)
    expect(boton()).toBeDisabled()
  })

  it('"conservado": muestra el domicilio que GANÓ, no el que se tecleó', async () => {
    const user = userEvent.setup()
    legalesEstado.faltaDomicilio = true
    legalesEstado.faltanCliente = ['domicilio']
    completarDomicilio.mockImplementation(async () => {
      legalesEstado.faltaDomicilio = false
      legalesEstado.faltanCliente = []
      return { accion: 'conservado' as const }
    })
    montar()

    await user.type(
      screen.getByLabelText('Domicilio legal completo'),
      'Av. Los Alamos 123, San Isidro, Lima, Lima',
    )
    await user.click(screen.getByRole('button', { name: /Guardar domicilio/ }))

    // Se dice sin rodeos que lo tecleado NO se guardó, y el aviso sobrevive al
    // cierre del bloque. El domicilio ganador NO viaja: el servidor no lo manda.
    expect(screen.getByText(/lo que escribiste aquí NO se guardó/)).toBeInTheDocument()
    expect(screen.queryByText(/Av. Los Alamos 123/)).not.toBeInTheDocument()
  })

  it('si la relectura falla tras guardar, NO deja bloqueado al analista', async () => {
    const user = userEvent.setup()
    legalesEstado.faltaDomicilio = true
    legalesEstado.faltanCliente = ['domicilio']
    // El servidor confirma la escritura, pero la caché se queda como estaba.
    completarDomicilio.mockResolvedValue({ accion: 'completado' })
    legalesEstado.refetch.mockRejectedValue(new Error('sin red'))
    montar()
    await llenarBase(user)

    await user.type(
      screen.getByLabelText('Domicilio legal completo'),
      'Av. Los Alamos 123, San Isidro, Lima, Lima',
    )
    await user.click(screen.getByRole('button', { name: /Guardar domicilio/ }))

    expect(screen.queryByText(/Falta el domicilio legal/)).not.toBeInTheDocument()
    expect(boton()).toBeEnabled()
    await user.click(boton())
    expect(crearContrato).toHaveBeenCalledTimes(1)
  })

  it('si el pre-vuelo FALLA no se bloquea nada: el servidor sigue siendo la puerta', async () => {
    const user = userEvent.setup()
    legalesEstado.error = true
    montar()
    await llenarBase(user)

    expect(screen.queryByText(/Falta el domicilio legal/)).not.toBeInTheDocument()
    expect(boton()).toBeEnabled()
    await user.click(boton())
    expect(crearContrato).toHaveBeenCalledTimes(1)
  })

  it('lo que el analista NO puede arreglar se frena nombrando el dato y a quién acudir', async () => {
    const user = userEvent.setup()
    legalesEstado.faltanCliente = ['correo']
    legalesEstado.faltanAnalista = ['telefono']
    montar()
    await llenarBase(user)

    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent(/Al cliente le falta correo/)
    expect(aviso).toHaveTextContent(/A tu propio perfil le falta celular/)
    expect(aviso).toHaveTextContent(/Gerencia/)
    expect(screen.queryByLabelText('Domicilio legal completo')).not.toBeInTheDocument()
    expect(boton()).toBeDisabled()

    await user.click(boton())
    expect(crearContrato).not.toHaveBeenCalled()
  })
})

describe('ContratoNuevo — el aviso de la cadena de upgrade (ATR-3)', () => {
  it('POSITIVO: renovando un contrato de una cadena, avisa a quién cuenta', async () => {
    vi.mocked(crmQueries.useAtribucionContrato).mockReturnValueOnce({
      data: {
        contrato_id: 'origen-1',
        analista_id: 'x-1',
        analista_nombre: 'MARIA UPGRADE',
        es_demo: false,
        registrado_por: null,
        atribucion_efectiva: {
          cadena: true,
          adoptada: false,
          analista_id: 'x-1',
          analista_nombre: 'MARIA UPGRADE',
        },
        reasignaciones: [],
      },
      isPending: false,
      isError: false,
    } as never)
    render(
      <Dialog open onClose={() => undefined}>
        <ContratoNuevo
          clienteId="cli-1"
          clienteNombre="CLIENTE PORTAL UNO"
          categoriaFija="renovacion"
          renovacionOrigen={{
            id: 'origen-1',
            numeroContrato: '000123',
            capital: 10000,
            moneda: 'PEN',
            fechaVencimiento: '2026-12-01',
          }}
          analistas={[{ perfil_id: 'x-1', nombre_completo: 'MARIA UPGRADE' }]}
          onConfirmado={vi.fn()}
          onEnviandoCambio={vi.fn()}
          onCreado={vi.fn()}
          onOmitir={vi.fn()}
        />
      </Dialog>,
    )
    expect(
      screen.getByText(/Esta renovación cuenta al analista del upgrade: MARIA UPGRADE/),
    ).toBeInTheDocument()
  })

  it('NEGATIVO: sin cadena en el origen, el aviso no existe', () => {
    render(
      <Dialog open onClose={() => undefined}>
        <ContratoNuevo
          clienteId="cli-1"
          clienteNombre="CLIENTE PORTAL UNO"
          categoriaFija="renovacion"
          renovacionOrigen={{
            id: 'origen-2',
            numeroContrato: '000124',
            capital: 10000,
            moneda: 'PEN',
            fechaVencimiento: '2026-12-01',
          }}
          onConfirmado={vi.fn()}
          onEnviandoCambio={vi.fn()}
          onCreado={vi.fn()}
          onOmitir={vi.fn()}
        />
      </Dialog>,
    )
    expect(screen.queryByText(/cuenta al analista del upgrade/)).not.toBeInTheDocument()
  })
})
