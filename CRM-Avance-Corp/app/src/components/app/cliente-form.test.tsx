// Tests del componente ClienteForm (alta atómica + corregir con ventana de
// 5 h). La capa @/data/crm-api se mockea (sin red); CrmApiError se conserva
// real para el instanceof del catch. Se monta dentro de <Dialog> porque el
// DialogTitle (Radix) exige el contexto del dialog — igual que en la pantalla —
// y dentro de un QueryClientProvider limpio por test porque la precarga de
// corregir va por useClienteDetalle (retry:false, espejo de lib/query-client:
// con el retry por defecto de TanStack el test de error reintentaría solo).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Dialog } from '@/components/ui/dialog'
import type { ClienteDetalle, CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import type { Rol } from '@/lib/roles'
import * as crmApi from '@/data/crm-api'
import { crmQueryKeys } from '@/data/crm-queries'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real
    crearClientePortal: vi.fn(),
    actualizarClientePortal: vi.fn(),
    corregirDocumentoClienteAdmin: vi.fn(),
    obtenerClienteDetalle: vi.fn(),
    listarCuentasBancariasCliente: vi.fn(),
  }
})

const { ClienteForm } = await import('./cliente-form')
const { CrmApiError } = crmApi

const crearCliente = vi.mocked(crmApi.crearClientePortal)
const actualizarCliente = vi.mocked(crmApi.actualizarClientePortal)
const corregirDocumento = vi.mocked(crmApi.corregirDocumentoClienteAdmin)
const obtenerDetalle = vi.mocked(crmApi.obtenerClienteDetalle)
const listarCuentas = vi.mocked(crmApi.listarCuentasBancariasCliente)

// clearMocks corre antes de cada test: este default deja el ledger VACÍO salvo
// que el test lo pueble — la precarga clásica (casillas del perfil) manda.
beforeEach(() => {
  listarCuentas.mockResolvedValue([])
})

function cuentaLedger(over: Partial<CuentaBancariaSeleccionable> = {}): CuentaBancariaSeleccionable {
  return {
    cuenta_id: 'cta-1',
    moneda: 'USD',
    banco: 'BBVA',
    tipo_cuenta: 'corriente',
    numero_cuenta: '72728282828282',
    cci: '27273827282828282828',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    origen: 'contrato',
    es_cuenta_perfil: false,
    creada_en: '2026-08-11T19:36:47.000Z',
    ...over,
  }
}

function detalleBase(over: Partial<ClienteDetalle> = {}): ClienteDetalle {
  return {
    id: 'cli-1',
    nombre_completo: 'PORTAL UNO CLIENTE',
    nombres: 'CLIENTE',
    apellidos: 'PORTAL UNO',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente1@correo.pe',
    telefono: '999111222',
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: new Date().toISOString(), // recién creado → ventana viva
    banca_visible: true,
    cuentas_bancarias_visibles: true,
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: null,
    tipo_cuenta_usd: null,
    numero_cuenta_usd: null,
    cci_usd: null,
    titular_distinto_usd: false,
    beneficiario_nombre_usd: null,
    beneficiario_dni_usd: null,
    ...over,
  }
}

interface PropsParciales {
  modo?: 'crear' | 'corregir'
  clienteId?: string
  rol?: Rol
  rolPortal?: string
  queryClient?: QueryClient
}

function montar(props: PropsParciales = {}) {
  const onListo = vi.fn()
  const onCerrar = vi.fn()
  // QueryClient NUEVO por montaje: caché aislada entre tests (la precarga de
  // corregir usa la clave clienteDetalle(id) y no debe sobrevivir de un test a otro).
  const queryClient = props.queryClient ?? new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const rol = props.rol ?? 'vendedor'
  const auth: AuthContextValue = {
    fase: 'listo',
    yo: {
      id: rol === 'gerencia' ? 'gerencia' : 'yo',
      nombre_completo: rol === 'gerencia' ? 'GERENCIA' : 'ANALISTA',
      rol,
      ...(props.rolPortal ? { rol_portal: props.rolPortal } : {}),
      demo: false,
      puede_contratar: true,
    },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
  // exactOptionalPropertyTypes: clienteId solo se pasa cuando existe.
  render(
    <AuthContext.Provider value={auth}>
      <QueryClientProvider client={queryClient}>
        <Dialog open onClose={() => undefined}>
          {props.clienteId !== undefined
            ? (
                <ClienteForm
                  modo={props.modo ?? 'corregir'}
                  clienteId={props.clienteId}
                  onListo={onListo}
                  onCerrar={onCerrar}
                />
              )
            : <ClienteForm modo={props.modo ?? 'crear'} onListo={onListo} onCerrar={onCerrar} />}
        </Dialog>
      </QueryClientProvider>
    </AuthContext.Provider>,
  )
  return { onListo, onCerrar, queryClient }
}

/** Llena identidad + cuenta PEN completa (el mínimo del alta feliz). */
async function llenarAltaMinima(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Apellidos *'), 'diaz huayta')
  await user.type(screen.getByLabelText('Nombres *'), 'hugo gualberto')
  await user.type(screen.getByLabelText('Documento *'), '45781234')
  await user.type(screen.getByLabelText('Correo electrónico *'), 'hugo@correo.pe')
  await user.type(screen.getByLabelText('Domicilio legal completo *'), 'Av. Javier Prado Este 123, San Isidro, Lima')
  const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
  await user.selectOptions(within(pen).getByLabelText('Banco'), 'BCP')
  await user.selectOptions(within(pen).getByLabelText('Tipo de cuenta'), 'ahorros')
  await user.type(within(pen).getByLabelText('N° de cuenta'), '19112345678901')
  await user.type(within(pen).getByLabelText(/CCI/), '00219112345678901234')
}

describe('ClienteForm — modo crear (alta atómica)', () => {
  it('muestra el aviso de la clave temporal (espejo del portal)', () => {
    montar()
    expect(screen.getByText(/La clave temporal será el/)).toBeInTheDocument()
    expect(screen.getByText(/00AB1234/)).toBeInTheDocument()
  })

  it('alta feliz: UNA sola llamada con identidad + bancarios, y onListo(userId)', async () => {
    const user = userEvent.setup()
    crearCliente.mockResolvedValue({ userId: 'nuevo-1', emailEnviado: true })
    const { onListo } = montar()

    await llenarAltaMinima(user)
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('nuevo-1'))
    // La edge recibe la identidad normalizada (APELLIDOS primero) Y las cuentas
    // en el MISMO envío: el cliente nace con su cuenta o no nace.
    expect(crearCliente).toHaveBeenCalledWith({
      email: 'hugo@correo.pe',
      nombre_completo: 'DIAZ HUAYTA HUGO GUALBERTO',
      apellidos: 'DIAZ HUAYTA',
      nombres: 'HUGO GUALBERTO',
      dni: '45781234',
      telefono: null,
      domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
      tipo_documento: 'DNI',
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
    expect(toast.success).toHaveBeenCalledWith('Cliente "DIAZ HUAYTA HUGO GUALBERTO" creado. Ahora crea su contrato.')
  })

  it('validación local: sin datos no toca el servidor y muestra el mensaje del portal', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Completa los apellidos y nombres del cliente.')
    expect(crearCliente).not.toHaveBeenCalled()
  })

  it('regla bancaria: identidad completa pero sin ninguna cuenta → error local', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(screen.getByLabelText('Apellidos *'), 'qa')
    await user.type(screen.getByLabelText('Nombres *'), 'uno')
    await user.type(screen.getByLabelText('Documento *'), '45781234')
    await user.type(screen.getByLabelText('Correo electrónico *'), 'qa@correo.pe')
    await user.type(screen.getByLabelText('Domicilio legal completo *'), 'Av. Javier Prado Este 123, San Isidro, Lima')
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    )
    expect(crearCliente).not.toHaveBeenCalled()
  })

  it('si el servidor rechaza los bancarios NO queda cliente a medias: error y re-submit posible', async () => {
    // Sustituye a los dos casos viejos de "paso 2 fallido". Ese estado ya no
    // puede existir: la edge valida las cuentas ANTES de crear nada, así que el
    // rechazo llega como error normal y el analista puede corregir y reintentar.
    const user = userEvent.setup()
    crearCliente.mockRejectedValue(
      new CrmApiError(
        'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
        'ALTA_CLIENTE_FALLIDA',
      ),
    )
    const { onListo } = montar()

    await llenarAltaMinima(user)
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    )
    expect(onListo).not.toHaveBeenCalled() // NO se encadena al contrato
    expect(toast.success).not.toHaveBeenCalled()
    expect(actualizarCliente).not.toHaveBeenCalled()
    // Reintentable: el BotonGuardar queda en su estado de error ofreciendo el
    // reintento en el mismo botón (no se creó nada en el servidor).
    expect(screen.getByRole('button', { name: /No se pudo guardar/ })).toBeEnabled()
  })

  it('la edge rechaza (409 documento duplicado): muestra su mensaje tal cual', async () => {
    const user = userEvent.setup()
    crearCliente.mockRejectedValue(
      new CrmApiError('Este documento ya está registrado para otro cliente.', 'ALTA_CLIENTE_FALLIDA'),
    )
    const { onListo } = montar()

    await llenarAltaMinima(user)
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))

    expect(await screen.findByRole('alert'))
      .toHaveTextContent('Este documento ya está registrado para otro cliente.')
    expect(actualizarCliente).not.toHaveBeenCalled()
    expect(onListo).not.toHaveBeenCalled()
  })
})

describe('ClienteForm — modo corregir (ventana de 5 h)', () => {
  it('precarga TODO, bloquea el correo (cuenta de acceso) y guarda el patch completo', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    actualizarCliente.mockResolvedValue(true)
    const { onListo } = montar({ modo: 'corregir', clienteId: 'cli-1' })

    const correo = await screen.findByLabelText('Correo electrónico *')
    expect(correo).toHaveValue('cliente1@correo.pe')
    expect(correo).toBeDisabled()
    expect(screen.getByText(/cuenta de acceso/)).toBeInTheDocument()
    expect(screen.getByLabelText('Apellidos *')).toHaveValue('PORTAL UNO')
    expect(screen.getByLabelText('Tipo de documento *')).toBeDisabled()
    expect(screen.getByLabelText('Documento *')).toBeDisabled()
    const domicilio = screen.getByLabelText('Domicilio legal completo *')
    expect(domicilio).toHaveValue('Av. Javier Prado Este 123, San Isidro, Lima')
    expect(screen.getByText(/solo a contratos futuros/)).toBeInTheDocument()
    // Bancarios precargados (PEN del detalle).
    const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    expect(within(pen).getByLabelText('Banco')).toHaveValue('BCP')
    // Cuenta regresiva de la ventana (recién creado → vigente).
    expect(screen.getByText(/Ventana de corrección: Quedan/)).toBeInTheDocument()

    const tel = screen.getByLabelText('Teléfono')
    await user.clear(tel)
    await user.type(tel, '988777666')
    await user.clear(domicilio)
    await user.type(domicilio, 'Jr. Los Cedros 456, Miraflores, Lima')
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('cli-1'))
    expect(actualizarCliente).toHaveBeenCalledTimes(1)
    const [id, patch] = actualizarCliente.mock.calls[0]!
    expect(id).toBe('cli-1')
    expect(patch).toMatchObject({
      nombre_completo: 'PORTAL UNO CLIENTE',
      telefono: '988777666',
      domicilio: 'Jr. Los Cedros 456, Miraflores, Lima',
      banco: 'BCP',
      cci: '00219112345678901234',
      banco_usd: null,
    })
    expect(patch).not.toHaveProperty('tipo_documento')
    expect(patch).not.toHaveProperty('dni')
    expect(corregirDocumento).not.toHaveBeenCalled()
    expect(toast.success).toHaveBeenCalledWith('Datos del cliente corregidos.')
  })

  it('una capacidad bancaria cacheada antes del mount no dispara el ledger si el detalle fresco la revoca', async () => {
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ cuentas_bancarias_visibles: true }),
    )
    queryClient.setQueryData(
      crmQueryKeys.cuentasBancarias('cli-1', 'USD'),
      [cuentaLedger({ numero_cuenta: 'CACHE-NO-AUTORIZADA' })],
    )
    obtenerDetalle.mockResolvedValue(detalleBase({
      banca_visible: false,
      cuentas_bancarias_visibles: false,
      // Respuesta deliberadamente incoherente: aun si un backend defectuoso
      // olvidara nullear estos valores, el flag cerrado manda en la UI.
      numero_cuenta: 'SERVIDOR-NO-DEBE-PINTARSE',
    }))

    montar({ modo: 'corregir', clienteId: 'cli-1', queryClient })

    expect(await screen.findByLabelText('Correo electrónico *')).toHaveValue('cliente1@correo.pe')
    expect(listarCuentas).not.toHaveBeenCalled()
    expect(screen.queryByText(/CACHE-NO-AUTORIZADA/)).not.toBeInTheDocument()
    expect(screen.queryByDisplayValue('SERVIDOR-NO-DEBE-PINTARSE')).not.toBeInTheDocument()
    const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    expect(within(pen).getByLabelText('Banco')).toHaveValue('')
    expect(screen.queryByText('Cuentas registradas en contratos')).not.toBeInTheDocument()
  })

  it('una cuenta cacheada antes del mount no se pinta ni desbloquea la validación mientras el refresh está pendiente', async () => {
    const user = userEvent.setup()
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    queryClient.setQueryData(
      crmQueryKeys.cuentasBancarias('cli-1', 'USD'),
      [cuentaLedger({ numero_cuenta: 'CACHE-NO-CONFIRMADA' })],
    )
    obtenerDetalle.mockResolvedValue(detalleBase({
      banco: null,
      tipo_cuenta: null,
      numero_cuenta: null,
      cci: null,
      banco_usd: null,
      tipo_cuenta_usd: null,
      numero_cuenta_usd: null,
      cci_usd: null,
    }))
    listarCuentas.mockImplementation(() => new Promise<CuentaBancariaSeleccionable[]>(() => undefined))

    montar({ modo: 'corregir', clienteId: 'cli-1', queryClient })

    await screen.findByLabelText('Correo electrónico *')
    expect(screen.queryByText(/CACHE-NO-CONFIRMADA/)).not.toBeInTheDocument()
    expect(screen.getByText('Validando las cuentas registradas antes de guardar…')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Guardar corrección/ })).toBeDisabled()
    // Ni siquiera userEvent puede saltar el disabled nativo.
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))
    expect(actualizarCliente).not.toHaveBeenCalled()
  })

  it('ESTADO DE PRODUCCIÓN: la cuenta USD que vive solo en el ledger se MUESTRA (solo lectura) sin sembrar las casillas', async () => {
    // Réplica del caso ORMESINDA JULCA: cuenta USD registrada al crear un
    // contrato → vive SOLO en crm.cuentas_bancarias. Antes el formulario la
    // escondía por completo. OJO: NO se siembra en los inputs — al guardar iría
    // a perfiles y el fallback perfil_legacy de Pagos la usaría para contratos
    // viejos sin vínculo (veto Codex 2026-08-11 a esa convergencia).
    obtenerDetalle.mockResolvedValue(detalleBase()) // banco_usd null (fixture)
    // Payload FIEL de la RPC: para PEN devuelve la casilla del perfil como fila
    // es_cuenta_perfil (así la sintetiza cuentas_bancarias_cliente_fn), no [].
    listarCuentas.mockImplementation(async (_id, moneda) =>
      moneda === 'USD'
        ? [cuentaLedger()]
        : [cuentaLedger({
            cuenta_id: null,
            moneda: 'PEN',
            banco: 'BCP',
            tipo_cuenta: 'ahorros',
            numero_cuenta: '19112345678901',
            cci: '00219112345678901234',
            origen: 'perfil',
            es_cuenta_perfil: true,
            creada_en: null,
          })])
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    // El bloque informativo lista la cuenta del contrato…
    expect(await screen.findByText('Cuentas registradas en contratos')).toBeInTheDocument()
    expect(screen.getByText(/BBVA · corriente · 72728282828282 — dólares/)).toBeInTheDocument()
    // …pero la casilla USD editable queda VACÍA (nada del ledger se siembra).
    const usd = screen.getByRole('group', { name: 'Cuenta bancaria en Dólares (USD)' })
    expect(within(usd).getByLabelText('Banco')).toHaveValue('')
    expect(within(usd).getByLabelText('N° de cuenta')).toHaveValue('')
    // La casilla PEN del perfil se precarga como siempre, y su copia histórica
    // en el ledger (fila origen 'perfil') NO se lista como cuenta de contrato.
    const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    expect(within(pen).getByLabelText('Banco')).toHaveValue('BCP')
    expect(screen.queryByText(/BCP · ahorros/)).not.toBeInTheDocument()
  })

  it('una cuenta que solo vive en el ledger DESBLOQUEA la corrección SIN copiarse jamás a perfiles', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase({
      banco: null,
      tipo_cuenta: null,
      numero_cuenta: null,
      cci: null,
    })) // ambas casillas del perfil vacías
    listarCuentas.mockImplementation(async (_id, moneda) =>
      moneda === 'USD' ? [cuentaLedger()] : [])
    actualizarCliente.mockResolvedValue(true)
    const { onListo } = montar({ modo: 'corregir', clienteId: 'cli-1' })

    // Esperar el bloque informativo garantiza que el flag del ledger ya llegó.
    await screen.findByText('Cuentas registradas en contratos')
    const tel = screen.getByLabelText('Teléfono')
    await user.clear(tel)
    await user.type(tel, '999111222')
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('cli-1'))
    const [, patch] = actualizarCliente.mock.calls[0]!
    // LA aserción anti-backfill: el teléfono viaja, las 14 bancarias van null
    // (idempotente sobre un perfil que ya estaba vacío) y la cuenta del ledger
    // NO aparece por ningún lado del patch.
    expect(patch).toMatchObject({
      telefono: '999111222',
      banco: null,
      numero_cuenta: null,
      cci: null,
      banco_usd: null,
      numero_cuenta_usd: null,
      cci_usd: null,
    })
    expect(JSON.stringify(patch)).not.toContain('BBVA')
    expect(screen.queryByText(/Registra al menos una cuenta/)).not.toBeInTheDocument()
  })

  // GUARDA del comportamiento nuevo (pasa también sobre el código viejo, que
  // jamás llamaba la RPC): fija que el fallo del ledger no bloquea corregir.
  // Los detectores del FIX son los dos tests de arriba (bloque informativo y
  // desbloqueo sin backfill).
  it('si la RPC de cuentas falla, corregir sigue operable con las casillas del perfil y AVISA con su Reintentar', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    listarCuentas
      .mockRejectedValueOnce(new CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'POSTGREST_ERROR'))
      .mockRejectedValueOnce(new CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'POSTGREST_ERROR'))
      .mockImplementation(async (_id, moneda) => (moneda === 'USD' ? [cuentaLedger()] : []))
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    const pen = await screen.findByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    expect(within(pen).getByLabelText('Banco')).toHaveValue('BCP')
    expect(screen.getByRole('button', { name: /Guardar corrección/ })).toBeEnabled()
    // La degradación NO es muda: sin esto el analista no distingue «no tiene
    // cuentas en contratos» de «no se pudo leer el ledger».
    const aviso = await screen.findByRole('status')
    expect(aviso).toHaveTextContent(/No se pudieron consultar las cuentas registradas en contratos/)

    // Su Reintentar repara las consultas del ledger: aparece el bloque
    // informativo y el aviso se limpia solo (derivado en vivo).
    await user.click(within(aviso).getByRole('button', { name: /Reintentar/ }))
    expect(await screen.findByText('Cuentas registradas en contratos')).toBeInTheDocument()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('cuando el ledger responde sin cuentas de contrato no hay aviso ni bloque informativo', async () => {
    obtenerDetalle.mockResolvedValue(detalleBase())
    montar({ modo: 'corregir', clienteId: 'cli-1' }) // default: ledger []

    await screen.findByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(screen.queryByText('Cuentas registradas en contratos')).not.toBeInTheDocument()
  })

  it('Reintentar del ERROR DE CARGA obtiene primero la autorización y recién entonces consulta el ledger', async () => {
    const user = userEvent.setup()
    const sinRed = new CrmApiError('Sin conexión.', 'SIN_RED')
    obtenerDetalle
      .mockRejectedValueOnce(sinRed)
      .mockResolvedValue(detalleBase()) // banco_usd null: la USD vive en el ledger
    listarCuentas.mockImplementation(async (_id, moneda) => (moneda === 'USD' ? [cuentaLedger()] : []))
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    const reintentar = await screen.findByRole('button', { name: /Reintentar/ })
    // El detalle falló antes de autorizar banca: no se sondean sus RPC.
    expect(listarCuentas).not.toHaveBeenCalled()
    await user.click(reintentar)

    // Con la red sana el detalle confirma banca_visible y habilita PEN/USD: el
    // bloque informativo trae la cuenta sin una llamada bancaria prematura.
    expect(await screen.findByText('Cuentas registradas en contratos')).toBeInTheDocument()
    expect(screen.getByText(/BBVA · corriente/)).toBeInTheDocument()
    expect(listarCuentas).toHaveBeenCalledTimes(2)
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  // GUARDA (también verde sobre el código viejo): fija que el flag `enabled`
  // impide llamar la RPC con clienteId '' en el alta.
  it('el alta (modo crear) no consulta el ledger de cuentas', async () => {
    montar()
    await screen.findByLabelText('Apellidos *')
    expect(listarCuentas).not.toHaveBeenCalled()
  })

  it('ventana vencida (0 filas): mensaje honesto de NO guardado, sin onListo', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    actualizarCliente.mockResolvedValue(false) // el servidor se quedó callado
    const { onListo } = montar({ modo: 'corregir', clienteId: 'cli-1' })

    await screen.findByLabelText('Apellidos *')
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'La ventana de corrección venció: los cambios NO se guardaron. Pide el cambio a administración.',
    )
    expect(onListo).not.toHaveBeenCalled()
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('Gerencia corrige sin ventana y activa el camino RPC de la capa de datos', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(
      detalleBase({
        asesor_perfil_id: 'otro',
        creado_por: 'otro',
        creado_en: '2020-01-01T00:00:00.000Z',
      }),
    )
    actualizarCliente.mockResolvedValue(true)
    const { onListo } = montar({ modo: 'corregir', clienteId: 'cli-1', rol: 'gerencia' })

    expect(await screen.findByText('Corrección autorizada por Gerencia')).toBeInTheDocument()
    expect(screen.queryByText(/Ventana de corrección:/)).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('cli-1'))
    expect(actualizarCliente).toHaveBeenCalledWith(
      'cli-1',
      expect.not.objectContaining({ dni: expect.anything() }),
      true,
    )
    expect(corregirDocumento).not.toHaveBeenCalled()
  })

  it('Admin corrige el documento desde el CRM con motivo y RPC auditada', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    actualizarCliente.mockResolvedValue(true)
    corregirDocumento.mockResolvedValue(undefined)
    const { onListo } = montar({
      modo: 'corregir',
      clienteId: 'cli-1',
      rol: 'gerencia',
      rolPortal: 'admin',
    })

    expect(await screen.findByText('Corrección administrativa auditada')).toBeInTheDocument()
    expect(screen.getByLabelText('Tipo de documento *')).toBeEnabled()
    const documento = screen.getByLabelText('Documento *')
    expect(documento).toBeEnabled()
    await user.clear(documento)
    await user.type(documento, '87654321')
    await user.type(screen.getByLabelText('Motivo de la corrección *'), 'Error de digitación')
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('cli-1'))
    const [, patch] = actualizarCliente.mock.calls[0]!
    expect(patch).not.toHaveProperty('tipo_documento')
    expect(patch).not.toHaveProperty('dni')
    expect(corregirDocumento).toHaveBeenCalledWith(
      'cli-1',
      'DNI',
      '87654321',
      'Error de digitación',
    )
  })

  it('cliente LEGACY sin separar: muestra el nombre original y permite guardar sin apellidos/nombres', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(
      detalleBase({ apellidos: null, nombres: null, nombre_completo: 'NOMBRE VIEJO JUNTO' }),
    )
    actualizarCliente.mockResolvedValue(true)
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    expect(await screen.findByText(/Nombre registrado anteriormente:/)).toBeInTheDocument()
    expect(screen.getByText('NOMBRE VIEJO JUNTO')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(actualizarCliente).toHaveBeenCalledTimes(1))
    const [, patch] = actualizarCliente.mock.calls[0]!
    // Conserva su nombre original; apellidos/nombres viajan null (no se inventan).
    expect(patch).toMatchObject({ nombre_completo: 'NOMBRE VIEJO JUNTO', apellidos: null, nombres: null })
  })

  it('si el detalle no carga: error con Reintentar (y el reintento recarga)', async () => {
    const user = userEvent.setup()
    obtenerDetalle
      .mockRejectedValueOnce(new CrmApiError('No se pudo cargar el cliente.'))
      .mockResolvedValueOnce(detalleBase())
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo cargar el cliente.')
    await user.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(await screen.findByLabelText('Apellidos *')).toHaveValue('PORTAL UNO')
    expect(obtenerDetalle).toHaveBeenCalledTimes(2)
  })
})
