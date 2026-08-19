// Tests del DialogConvertir REAL (conversión lead → cliente del portal en una
// operación atómica, encadenando después el contrato).
// La capa @/data/crm-api se mockea (sin red); CrmApiError se conserva real para
// el instanceof del catch. Los contextos se proveen a mano: el diálogo solo
// consume { convertir, recargar } del store y `yo` del auth.
// NOTA de cobertura: la E2E real de convertir (acciones-real.spec.ts) está
// SKIPPED por el gate FUNCIONES_LEADS_APROBADAS — esta suite es hoy la única
// que ejercita el flujo real con bancarios de punta a punta (backend mockeado).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import * as crmApi from '@/data/crm-api'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real
    convertirLead: vi.fn(),
    actualizarClientePortal: vi.fn(),
    esClienteDeMiCartera: vi.fn(),
  }
})

// Este archivo prueba la conversión; el transporte de cuentas tiene su suite
// propia (queries + MSW + E2E). Aislamos aquí el hook para que ContratoNuevo
// pueda montarse sin convertir este test en otro harness de QueryClient.
// `mutarCierreExterno` es el mutateAsync del cierre en cooperativa: hoisted
// porque el mock de módulo se evalúa antes que el cuerpo del archivo.
const { mutarCierreExterno } = vi.hoisted(() => ({
  mutarCierreExterno: vi.fn(),
}))

vi.mock('@/data/crm-queries', () => ({
  useCuentasBancariasCliente: vi.fn((_clienteId: string, moneda: 'PEN' | 'USD') => ({
    data: moneda === 'PEN'
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
    isPending: false,
    isError: false,
    isFetching: false,
    refetch: vi.fn(),
  })),
  useConvertirLeadExterno: vi.fn(() => ({ mutateAsync: mutarCierreExterno })),
  // Pre-vuelo legal del contrato. Aquí el cliente ACABA de nacer con su
  // domicilio (la conversión lo captura), así que no falta nada: este camino no
  // debe ver nunca el bloque que pide el domicilio.
  useDatosLegalesContrato: vi.fn((clienteId: string) => ({
    data: { clienteId, faltaDomicilio: false, faltanCliente: [], faltanAnalista: [] },
    isPending: false,
    isError: false,
    isFetching: false,
    refetch: vi.fn(),
  })),
}))

// El catálogo versionado tiene sus pruebas propias. Este diálogo solo necesita
// que el paso contractual pueda montarse sin una frontera remota ni QueryClient.
vi.mock('@/data/crm-config-queries', () => ({
  useProductosSeleccionables: () => ({
    data: [],
    isPending: false,
    isError: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
}))

const { DialogConvertir } = await import('./lead-drawer')
const { CrmApiError } = crmApi

const convertirEdge = vi.mocked(crmApi.convertirLead)
const actualizarCliente = vi.mocked(crmApi.actualizarClientePortal)
const enMiCartera = vi.mocked(crmApi.esClienteDeMiCartera)

function leadBase(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'JUAN PEREZ ROJAS',
    telefono: '+51999888777',
    correo: null,
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 50_000,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: 'u-v1',
    vendedor_nombre: 'Vendedor Real',
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T00:00:00.000Z',
    activo: true,
    dni: null,
    distrito: null,
    nota: null,
    motivo_descarte: null,
    ...over,
  }
}

function sesion(demo: boolean, rol: 'vendedor' | 'supervisor' = 'vendedor'): AuthContextValue {
  return {
    fase: 'listo',
    yo: { id: 'u-v1', nombre_completo: 'Vendedor Real', rol, demo, puede_contratar: true },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

function montar({
  demo = false,
  lead = {},
  rol = 'vendedor',
  recargaOk = true,
}: { demo?: boolean; lead?: Partial<Lead>; rol?: 'vendedor' | 'supervisor'; recargaOk?: boolean } = {}) {
  const onClose = vi.fn()
  const recargar = vi.fn().mockResolvedValue(recargaOk)
  const convertirExterno = vi.fn(() => ({ ok: true }))
  // Stub mínimo del store: DialogConvertir solo usa convertir/convertirExterno
  // (demo) y recargar.
  const api = {
    convertir: vi.fn(() => ({ ok: true })),
    convertirExterno,
    recargar,
  } as unknown as StoreDataApi
  render(
    <AuthContext.Provider value={sesion(demo, rol)}>
      <StoreDataContext.Provider value={api}>
        <DialogConvertir l={leadBase(lead)} onClose={onClose} />
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )
  return { onClose, recargar, convertirExterno }
}

/** El flujo arranca en «¿Dónde invirtió?»: esta variante lo pasa eligiendo
 *  Avance Corp, que es donde vive todo el flujo histórico de esta suite. */
async function montarEnAvance(
  opts: { demo?: boolean; lead?: Partial<Lead>; rol?: 'vendedor' | 'supervisor'; recargaOk?: boolean } = {},
) {
  const res = montar(opts)
  await userEvent.setup().click(screen.getByRole('button', { name: /Avance Corp/ }))
  return res
}

/** La variante COOPERATIVA del mismo arranque. */
async function montarEnCoop(
  opts: { demo?: boolean; lead?: Partial<Lead>; rol?: 'vendedor' | 'supervisor' } = {},
  coop: 'Qorilazo' | 'Prodelco' = 'Qorilazo',
) {
  const res = montar(opts)
  await userEvent.setup().click(screen.getByRole('button', { name: new RegExp(`COOPAC ${coop}`) }))
  return res
}

/** Identidad legal mínima válida del paso convertir. */
async function llenarIdentidad(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Correo del cliente'), 'juan@correo.pe')
  await user.type(screen.getByLabelText('N° de documento'), '45781234')
  await user.type(
    screen.getByLabelText('Domicilio legal completo'),
    'Av. Los Inversionistas 245, San Isidro, Lima',
  )
}

/** Cuenta PEN completa (el mínimo que exige la regla "al menos una"). */
async function llenarPenCompleta(user: ReturnType<typeof userEvent.setup>) {
  const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
  await user.selectOptions(within(pen).getByLabelText('Banco'), 'BCP')
  await user.selectOptions(within(pen).getByLabelText('Tipo de cuenta'), 'ahorros')
  await user.type(within(pen).getByLabelText('N° de cuenta'), '19112345678901')
  await user.type(within(pen).getByLabelText(/CCI/), '00219112345678901234')
}

describe('DialogConvertir — alta atómica con bancarios + contrato', () => {
  beforeEach(() => vi.clearAllMocks())

  it('un lead sin analista se bloquea antes de tocar Edge, Auth o portal', async () => {
    const user = userEvent.setup()
    await montarEnAvance({ lead: { vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'u-v1' } })

    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Asigna el lead a un analista antes de convertirlo',
    )
    expect(convertirEdge).not.toHaveBeenCalled()
    expect(actualizarCliente).not.toHaveBeenCalled()
  })

  it('pinta las DOS secciones bancarias del portal (ids cv-*, sin chocar con cf-*)', async () => {
    await montarEnAvance()
    expect(screen.getByLabelText('Domicilio legal completo')).toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })).toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Cuenta bancaria en Dólares (USD)' })).toBeInTheDocument()
    expect(document.getElementById('cv-pen-banco')).not.toBeNull()
    expect(document.getElementById('cf-pen-banco')).toBeNull()
  })

  it('sin domicilio legal no toca Edge, Auth ni portal', async () => {
    const user = userEvent.setup()
    await montarEnAvance()
    await user.type(screen.getByLabelText('Correo del cliente'), 'juan@correo.pe')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await llenarPenCompleta(user)

    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Completa el domicilio legal del cliente.',
    )
    expect(convertirEdge).not.toHaveBeenCalled()
  })

  it.each([
    // El listón subió de 5 a 15 caracteres + al menos un número (2026-08-19),
    // decidido con los 19 domicilios reales de producción. U+0085 salió de la
    // lista de controles: los tres lados lo tratan como espacio y lo colapsan.
    ['catorce puntos Unicode', 'Av. Lima 123 😀', 'El domicilio legal debe tener entre 15 y 240 caracteres.'],
    ['241 puntos Unicode', `Av. Lima 123 ${'x'.repeat(227)}😀`, 'El domicilio legal debe tener entre 15 y 240 caracteres.'],
    ['un control C0 de verdad', 'Av. Lima 123\u0007 San Isidro', 'El domicilio legal contiene caracteres no permitidos.'],
    ['un invisible de ancho cero', 'Av. Lima\u200B 123, San Isidro', 'El domicilio legal contiene caracteres invisibles que no se imprimirían en el contrato.'],
    ['una dirección sin número', 'Avenida sin numero, San Isidro', 'El domicilio legal necesita el número de la calle, el lote o la manzana.'],
    ['la dirección de la propia empresa', 'Av. República de Panamá 3635, San Isidro', 'Esa es la dirección de Avance Corp, no la del cliente: el contrato dejaría a las dos partes domiciliadas en el mismo sitio.'],
  ])('rechaza %s antes de tocar la Edge', async (_caso, valor, mensaje) => {
    const user = userEvent.setup()
    await montarEnAvance()
    await user.type(screen.getByLabelText('Correo del cliente'), 'juan@correo.pe')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    fireEvent.change(screen.getByLabelText('Domicilio legal completo'), { target: { value: valor } })
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(mensaje)
    expect(convertirEdge).not.toHaveBeenCalled()
  })

  it.each([
    ['quince puntos Unicode', 'Av. Lima 123 A😀'],
    ['240 puntos Unicode', `Av. Lima 123 ${'x'.repeat(226)}😀`],
  ])('acepta exactamente %s y conserva los caracteres astrales', async (_caso, valor) => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({
      perfil_id: 'perfil-9',
      ya_existia: false,
      domicilio_accion: 'completado',
      email_enviado: false,
    })
    await montarEnAvance()
    await llenarIdentidad(user)
    fireEvent.change(screen.getByLabelText('Domicilio legal completo'), { target: { value: valor } })
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    await waitFor(() => expect(convertirEdge).toHaveBeenCalledWith(expect.objectContaining({ domicilio: valor })))
  })

  it('regla "al menos una cuenta" AL CONVERTIR: sin bancarios NO toca el servidor', async () => {
    const user = userEvent.setup()
    await montarEnAvance()
    await llenarIdentidad(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    )
    expect(convertirEdge).not.toHaveBeenCalled()
    expect(actualizarCliente).not.toHaveBeenCalled()
  })

  it('sección a medias: el error sube con su moneda y tampoco toca el servidor', async () => {
    const user = userEvent.setup()
    await montarEnAvance()
    await llenarIdentidad(user)
    const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    await user.selectOptions(within(pen).getByLabelText('Banco'), 'BCP')
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('El N° de cuenta (Soles) es obligatorio.')
    expect(convertirEdge).not.toHaveBeenCalled()
  })

  it('feliz: UNA sola llamada con identidad + bancarios, y encadena el contrato', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({
      perfil_id: 'perfil-9',
      ya_existia: false,
      domicilio_accion: 'completado',
      email_enviado: true,
    })
    const { recargar } = await montarEnAvance()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    // Encadena el paso contrato sin salir del CRM.
    expect(await screen.findByRole('dialog', { name: /Crear contrato de JUAN PEREZ ROJAS/ })).toBeInTheDocument()
    // La edge recibe la identidad confirmada del lead Y las cuentas de depósito
    // en el MISMO envío: el cliente nace con su cuenta o no nace.
    expect(convertirEdge).toHaveBeenCalledWith({
      lead_id: 'lead-1',
      correo: 'juan@correo.pe',
      tipo_documento: 'DNI',
      documento: '45781234',
      nombre_completo: 'JUAN PEREZ ROJAS',
      telefono: '+51999888777',
      domicilio: 'Av. Los Inversionistas 245, San Isidro, Lima',
      bancarios: {
        pen: expect.objectContaining({
          banco: 'BCP',
          tipo_cuenta: 'ahorros',
          numero_cuenta: '19112345678901',
          cci: '00219112345678901234',
          titular_distinto: false,
        }),
        usd: expect.objectContaining({ banco: '', cci: '', titular_distinto: false }),
      },
    })
    // Y NO queda ningún segundo paso que pueda fallar y dejar al cliente sin cuenta.
    expect(actualizarCliente).not.toHaveBeenCalled()
    expect(recargar).toHaveBeenCalled()
    expect(toast.success).toHaveBeenCalledWith('JUAN PEREZ ROJAS ahora es cliente — correo de bienvenida enviado')
  })

  it('si la recarga falla después del commit, informa que la conversión sí quedó confirmada', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({
      perfil_id: 'perfil-9',
      ya_existia: false,
      domicilio_accion: 'completado',
      email_enviado: false,
    })
    await montarEnAvance({ recargaOk: false })

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('dialog', { name: /Crear contrato de JUAN PEREZ ROJAS/ })).toBeInTheDocument()
    expect(toast.warning).toHaveBeenCalledWith(expect.stringMatching(/conversión quedó confirmada/))
  })

  it('dedup ya_existia CON el cliente en mi cartera: no pisa bancarios, LO DICE y el contrato sigue vivo', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({
      perfil_id: 'perfil-7',
      ya_existia: true,
      domicilio_accion: 'conservado',
      email_enviado: false,
    })
    // El caso legítimo y frecuente (renovación): el DNI ya era cliente… mío.
    enMiCartera.mockResolvedValue(true)
    await montarEnAvance()

    await llenarIdentidad(user)
    await llenarPenCompleta(user) // el vendedor no puede saber que ya existía
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    // Un PATCH ciego sobreescribiría las cuentas con las que YA cobra: no viaja.
    expect(actualizarCliente).not.toHaveBeenCalled()
    // La atribución se PREGUNTA al servidor, no se adivina.
    expect(enMiCartera).toHaveBeenCalledWith('perfil-7')
    // …y el asesor se entera de que manda la cuenta YA registrada, en vez de
    // creer que acaba de registrar dónde se le depositan los intereses.
    const aviso = await screen.findByRole('alert')
    expect(aviso).toHaveTextContent(/ya tenía cuenta en el portal/)
    expect(aviso).toHaveTextContent(
      /se conservaron las cuentas bancarias que el cliente ya tenía registradas/,
    )
    expect(aviso).toHaveTextContent(/También se conservó el domicilio legal/)
    // Siendo suyo, NO se le acusa de haber perdido la cartera.
    expect(aviso).not.toHaveTextContent(/NO pasó a tu cartera/)
    // La ruta de corrección se enuncia CONDICIONADA a la ventana de 5 h, no como
    // una promesa ni como una negación absoluta: tras un 409 de la RPC el
    // reintento cae aquí con un cliente que el propio asesor acaba de crear, y
    // decirle "ya no se pueden cambiar, pídeselo a Gerencia" sería falso.
    expect(screen.getByText(/menos de 5 horas/)).toBeInTheDocument()
    expect(screen.getByText(/pídeselo a\s+Gerencia/)).toBeInTheDocument()
    // El foco entra AL AVISO: al enviar cayó a <body> (el botón se deshabilitó)
    // y una advertencia que hay que leer no puede depender de que Radix lo rescate.
    expect(aviso).toHaveFocus()
    // Un toast de éxito aquí sería justo la mentira que este aviso viene a matar.
    expect(toast.success).not.toHaveBeenCalled()
    // El aviso NO es terminal: el contrato sigue siendo el paso lógico.
    expect(screen.queryByRole('dialog', { name: /Crear contrato de JUAN PEREZ ROJAS/ })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Continuar al contrato' }))
    expect(await screen.findByRole('dialog', { name: /Crear contrato de JUAN PEREZ ROJAS/ })).toBeInTheDocument()
  })

  it('dedup ya_existia con el cliente de OTRO asesor: no se ofrece un contrato que la RPC rechazaría', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({
      perfil_id: 'perfil-8',
      ya_existia: true,
      domicilio_accion: 'conservado',
      email_enviado: false,
    })
    // La edge NO le cambia el asesor_perfil_id al cliente existente: sigue
    // siendo de quien lo tenía, y `public.crear_contrato` exige cartera propia.
    enMiCartera.mockResolvedValue(false)
    await montarEnAvance()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    const aviso = await screen.findByRole('alert')
    expect(aviso).toHaveTextContent(/NO pasó a tu cartera/)
    // La verdad completa: ni lo verá en su pantalla ni podrá contratarle.
    expect(screen.getByText(/no lo verás en/)).toBeInTheDocument()
    expect(screen.getByText(/te lo reasigne en el portal/)).toBeInTheDocument()
    // Y el callejón sin salida se retira: el botón llevaba a un formulario
    // largo que terminaba en un rechazo del servidor.
    expect(screen.queryByRole('button', { name: /contrato/i })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Entendido' })).toBeInTheDocument()
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('dedup ya_existia sin poder comprobar la cartera: se dice que no se sabe, no se afirma', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({
      perfil_id: 'perfil-8',
      ya_existia: true,
      domicilio_accion: 'completado',
      email_enviado: false,
    })
    enMiCartera.mockResolvedValue(null) // red caída / RLS: NO es un "false"
    await montarEnAvance()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    const aviso = await screen.findByRole('alert')
    expect(aviso).not.toHaveTextContent(/NO pasó a tu cartera/)
    expect(aviso).toHaveTextContent(/domicilio estaba vacío y se completó con el que ingresaste/)
    expect(screen.getByText(/No pudimos comprobar si el cliente quedó en tu cartera/)).toBeInTheDocument()
    // Se ofrece el intento (puede ser suyo), rotulado como intento y no como promesa.
    expect(screen.getByRole('button', { name: 'Intentar el contrato' })).toBeInTheDocument()
  })

  it('si el servidor rechaza los bancarios NO queda lead convertido a medias', async () => {
    // Sustituye a los tres casos viejos de "paso 2 fallido". Ese estado ya no
    // puede existir: la edge valida las cuentas ANTES de crear la cuenta, mandar
    // el correo y cerrar el lead, así que un rechazo no deja nada tocado.
    const user = userEvent.setup()
    convertirEdge.mockRejectedValue(
      new CrmApiError(
        'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
        'CONVERTIR_FALLIDO',
      ),
    )
    const { recargar } = await montarEnAvance()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    )
    expect(screen.queryByRole('dialog', { name: /Crear contrato de JUAN PEREZ ROJAS/ })).not.toBeInTheDocument()
    expect(toast.success).not.toHaveBeenCalled()
    expect(actualizarCliente).not.toHaveBeenCalled()
    expect(recargar).not.toHaveBeenCalled() // el lead no se movió
    // Reintentable: no se creó nada en el servidor.
    expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
  })

  it('la edge rechaza: muestra su mensaje es-PE, sin PATCH y sin estado terminal', async () => {
    const user = userEvent.setup()
    convertirEdge.mockRejectedValue(new CrmApiError('Este correo ya está registrado.', 'CONVERTIR_FALLIDO'))
    await montarEnAvance()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Este correo ya está registrado.')
    expect(actualizarCliente).not.toHaveBeenCalled()
    // El form sigue vivo para corregir y reintentar (no es el estado terminal).
    expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Entendido' })).not.toBeInTheDocument()
  })

  it('demo: el diálogo simulado NO pide bancarios (nada real que guardar)', async () => {
    await montarEnAvance({ demo: true })
    expect(screen.queryByRole('group', { name: /Cuenta bancaria/ })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Convertir (demo)' })).toBeInTheDocument()
  })
})

describe('DialogConvertir — «¿Dónde invirtió?» y el cierre en COOPERATIVA', () => {
  beforeEach(() => vi.clearAllMocks())

  it('el flujo arranca preguntando el destino, con las TRES empresas a la vista', () => {
    montar()
    expect(screen.getByRole('dialog', { name: '¿Dónde invirtió?' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Avance Corp/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /COOPAC Qorilazo/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /COOPAC Prodelco/ })).toBeInTheDocument()
    // Ni una llamada por mirar el menú.
    expect(convertirEdge).not.toHaveBeenCalled()
    expect(mutarCierreExterno).not.toHaveBeenCalled()
  })

  it('el formulario coop NO pide correo ni bancarios: no hay portal que crear', async () => {
    await montarEnCoop()
    expect(screen.getByLabelText('Monto REAL invertido (S/)')).toBeInTheDocument()
    expect(screen.queryByLabelText('Correo del cliente')).not.toBeInTheDocument()
    expect(screen.queryByRole('group', { name: /Cuenta bancaria/ })).not.toBeInTheDocument()
    // El nombre llega precargado del lead.
    expect(screen.getByLabelText('Nombre completo')).toHaveValue('JUAN PEREZ ROJAS')
  })

  it('NO se pregunta la moneda: en cooperativas solo se invierte en soles', async () => {
    await montarEnCoop()
    // Ofrecer una decisión que no existe (y que el servidor rechazaría) es peor
    // que no ofrecerla: el rótulo del monto dice la moneda.
    expect(screen.queryByLabelText('Moneda')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Monto REAL invertido (S/)')).toBeInTheDocument()
  })

  it('sin N.° de operación no viaja nada: es la prueba del cierre', async () => {
    const user = userEvent.setup()
    await montarEnCoop()
    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '10000')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/N.° de operación del depósito/)
    expect(mutarCierreExterno).not.toHaveBeenCalled()
  })

  it('un monto de 2 decimales como 10000.03 SÍ se acepta (coma flotante)', async () => {
    // `10000.03 * 100` da 1000003.0000000001 en JavaScript, así que la
    // comparación exacta acusaba tres decimales a un monto perfectamente
    // válido y el vendedor no podía registrar su cierre.
    const user = userEvent.setup()
    mutarCierreExterno.mockResolvedValue({ leadId: 'lead-1', cierreId: 'c-1', cooperativa: 'qorilazo' })
    await montarEnCoop()
    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '10000.03')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.type(screen.getByLabelText('N.° de operación del depósito'), 'OP-DEC')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(mutarCierreExterno).toHaveBeenCalledWith(
      expect.objectContaining({ monto: 10000.03 }),
    )
  })

  it('tres decimales de verdad siguen rechazándose', async () => {
    const user = userEvent.setup()
    await montarEnCoop()
    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '10000.035')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.type(screen.getByLabelText('N.° de operación del depósito'), 'OP-DEC3')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent('máximo 2 decimales')
    expect(mutarCierreExterno).not.toHaveBeenCalled()
  })

  it('si el depósito ya estaba registrado, se muestra el mensaje del servidor', async () => {
    const user = userEvent.setup()
    mutarCierreExterno.mockRejectedValue(
      new CrmApiError(
        'Ese numero de operacion ya esta registrado en esa cooperativa',
        'CIERRE_EXTERNO_CONFLICTO',
      ),
    )
    const { onClose } = await montarEnCoop()

    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '10000')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.type(screen.getByLabelText('N.° de operación del depósito'), 'OP-REPETIDA')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/ya esta registrado/)
    expect(onClose).not.toHaveBeenCalled()
  })

  it('sin monto REAL no viaja nada: es lo que suma a la cuota', async () => {
    const user = userEvent.setup()
    await montarEnCoop()
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/monto REAL invertido/)
    expect(mutarCierreExterno).not.toHaveBeenCalled()
  })

  it('documento inválido para el tipo: el error habla el idioma del formulario', async () => {
    const user = userEvent.setup()
    await montarEnCoop()
    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '10000')
    await user.type(screen.getByLabelText('N° de documento'), '123')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent('El DNI debe tener 8 dígitos')
    expect(mutarCierreExterno).not.toHaveBeenCalled()
  })

  it('un lead sin analista tampoco se cierra en coop (misma regla que Avance)', async () => {
    const user = userEvent.setup()
    await montarEnCoop({ lead: { vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'u-v1' } })
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Asigna el lead a un analista antes de convertirlo',
    )
    expect(mutarCierreExterno).not.toHaveBeenCalled()
  })

  it('feliz: la RPC recibe la foto completa, se recarga el pipeline y se cierra', async () => {
    const user = userEvent.setup()
    mutarCierreExterno.mockResolvedValue({ leadId: 'lead-1', cierreId: 'cierre-1', cooperativa: 'prodelco' })
    const { onClose, recargar } = await montarEnCoop({}, 'Prodelco')

    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '12500.50')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.type(screen.getByLabelText('N.° de operación del depósito'), 'OP-2026-9')
    await user.type(screen.getByLabelText('Certificado de la coop (opcional)'), 'PRO-2026-9')
    await user.click(screen.getByRole('button', { name: /Cerrar en PRODELCO/ }))

    expect(mutarCierreExterno).toHaveBeenCalledWith({
      leadId: 'lead-1',
      cooperativa: 'prodelco',
      monto: 12500.5,
      moneda: 'PEN',
      documentoTipo: 'DNI',
      documento: '45781234',
      nombre: 'JUAN PEREZ ROJAS',
      numeroTransaccion: 'OP-2026-9',
      referencia: 'PRO-2026-9',
      venceEn: null,
      nota: null,
    })
    // El lead quedó convertido en el servidor: el pipeline se refresca y NO
    // se encadena contrato alguno (no hay portal detrás).
    expect(recargar).toHaveBeenCalled()
    expect(onClose).toHaveBeenCalled()
    expect(toast.success).toHaveBeenCalledWith(
      'JUAN PEREZ ROJAS cerrado en COOPAC Prodelco — ya cuenta en tu cuota y conversión',
    )
    expect(screen.queryByRole('dialog', { name: /Crear contrato/ })).not.toBeInTheDocument()
  })

  it('el servidor rechaza (p. ej. doble cierre): su mensaje se muestra y nada se cierra', async () => {
    const user = userEvent.setup()
    mutarCierreExterno.mockRejectedValue(new CrmApiError('El lead ya está cerrado.', 'LEAD_YA_CERRADO'))
    const { onClose, recargar } = await montarEnCoop()

    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '1000')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.type(screen.getByLabelText('N.° de operación del depósito'), 'OP-1')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent('El lead ya está cerrado.')
    expect(recargar).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()
  })

  it('demo: el cierre coop va al store (convertirExterno), jamás a la RPC', async () => {
    const user = userEvent.setup()
    const { onClose, convertirExterno } = await montarEnCoop({ demo: true })

    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '8000')
    await user.type(screen.getByLabelText('N° de documento'), '45781234')
    await user.type(screen.getByLabelText('N.° de operación del depósito'), 'OP-DEMO')
    await user.click(screen.getByRole('button', { name: /Cerrar en QORILAZO/ }))

    expect(convertirExterno).toHaveBeenCalledWith('lead-1', {
      cooperativa: 'qorilazo',
      monto: 8000,
      numeroTransaccion: 'OP-DEMO',
    })
    expect(mutarCierreExterno).not.toHaveBeenCalled()
    expect(onClose).toHaveBeenCalled()
  })

  it('«Volver» regresa al destino sin perder el diálogo', async () => {
    const user = userEvent.setup()
    await montarEnCoop()
    await user.click(screen.getByRole('button', { name: 'Volver' }))
    expect(screen.getByRole('dialog', { name: '¿Dónde invirtió?' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Avance Corp/ })).toBeInTheDocument()
  })

  it('tras «Volver», el foco NO se queda sobre el botón que ahora dice «Cancelar»', async () => {
    // Los dos pasos tienen un <Button> en la misma posición del footer: sin
    // `key` distintas React reutiliza el MISMO nodo del DOM, el foco no se
    // mueve, y el botón bajo el dedo pasa a llamarse «Cancelar» y a cerrar el
    // diálogo entero. Un segundo Enter —el de quien no oyó nada— se llevaba el
    // monto, el documento y el N.° de operación ya escritos. Mismo bug que
    // cerrar-tarea.tsx ya documentó (WCAG 4.1.2).
    const user = userEvent.setup()
    const { onClose } = await montarEnCoop()
    await user.type(screen.getByLabelText('Monto REAL invertido (S/)'), '10000')
    await user.click(screen.getByRole('button', { name: 'Volver' }))

    const cancelar = screen.getByRole('button', { name: 'Cancelar' })
    expect(document.activeElement).not.toBe(cancelar)
    // Y el foco vuelve a la tarjeta de la cooperativa de donde se salió (el
    // rescate va en un requestAnimationFrame, de ahí el waitFor).
    await waitFor(() => {
      expect(document.activeElement).toBe(
        screen.getByRole('button', { name: /COOPAC Qorilazo/ }),
      )
    })
    // El segundo Enter ya no cierra nada: reabre el formulario.
    await user.keyboard('{Enter}')
    expect(onClose).not.toHaveBeenCalled()
    expect(screen.getByLabelText('Monto REAL invertido (S/)')).toBeInTheDocument()
  })
})
