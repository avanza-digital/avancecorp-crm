// Tests del DialogConvertir REAL (conversión lead → cliente del portal en 2
// pasos: edge crm-convertir-lead + bancarios por RLS, encadenando el contrato).
// La capa @/data/crm-api se mockea (sin red); CrmApiError se conserva real para
// el instanceof del catch. Los contextos se proveen a mano: el diálogo solo
// consume { convertir, recargar } del store y `yo` del auth.
// NOTA de cobertura: la E2E real de convertir (acciones-real.spec.ts) está
// SKIPPED por el gate FUNCIONES_LEADS_APROBADAS — esta suite es hoy la única
// que ejercita el flujo real con bancarios de punta a punta (backend mockeado).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
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
}: { demo?: boolean; lead?: Partial<Lead>; rol?: 'vendedor' | 'supervisor' } = {}) {
  const onClose = vi.fn()
  const recargar = vi.fn().mockResolvedValue(true)
  // Stub mínimo del store: DialogConvertir solo usa convertir (demo) y recargar.
  const api = { convertir: vi.fn(() => ({ ok: true })), recargar } as unknown as StoreDataApi
  render(
    <AuthContext.Provider value={sesion(demo, rol)}>
      <StoreDataContext.Provider value={api}>
        <DialogConvertir l={leadBase(lead)} onClose={onClose} />
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )
  return { onClose, recargar }
}

/** Identidad mínima válida del paso convertir (correo + DNI de 8). */
async function llenarIdentidad(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Correo del cliente'), 'juan@correo.pe')
  await user.type(screen.getByLabelText('N° de documento'), '45781234')
}

/** Cuenta PEN completa (el mínimo que exige la regla "al menos una"). */
async function llenarPenCompleta(user: ReturnType<typeof userEvent.setup>) {
  const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
  await user.selectOptions(within(pen).getByLabelText('Banco'), 'BCP')
  await user.selectOptions(within(pen).getByLabelText('Tipo de cuenta'), 'ahorros')
  await user.type(within(pen).getByLabelText('N° de cuenta'), '19112345678901')
  await user.type(within(pen).getByLabelText(/CCI/), '00219112345678901234')
}

describe('DialogConvertir — conversión real con bancarios (2 pasos + contrato)', () => {
  beforeEach(() => vi.clearAllMocks())

  it('un lead sin analista se bloquea antes de tocar Edge, Auth o portal', async () => {
    const user = userEvent.setup()
    montar({ lead: { vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'u-v1' } })

    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Asigna el lead a un analista antes de convertirlo',
    )
    expect(convertirEdge).not.toHaveBeenCalled()
    expect(actualizarCliente).not.toHaveBeenCalled()
  })

  it('pinta las DOS secciones bancarias del portal (ids cv-*, sin chocar con cf-*)', () => {
    montar()
    expect(screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })).toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Cuenta bancaria en Dólares (USD)' })).toBeInTheDocument()
    expect(document.getElementById('cv-pen-banco')).not.toBeNull()
    expect(document.getElementById('cf-pen-banco')).toBeNull()
  })

  it('regla "al menos una cuenta" AL CONVERTIR: sin bancarios NO toca el servidor', async () => {
    const user = userEvent.setup()
    montar()
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
    montar()
    await llenarIdentidad(user)
    const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    await user.selectOptions(within(pen).getByLabelText('Banco'), 'BCP')
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('El N° de cuenta (Soles) es obligatorio.')
    expect(convertirEdge).not.toHaveBeenCalled()
  })

  it('feliz: UNA sola llamada con identidad + bancarios, y encadena el contrato', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({ perfil_id: 'perfil-9', ya_existia: false, email_enviado: true })
    const { recargar } = montar()

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

  it('dedup ya_existia CON el cliente en mi cartera: no pisa bancarios, LO DICE y el contrato sigue vivo', async () => {
    const user = userEvent.setup()
    convertirEdge.mockResolvedValue({ perfil_id: 'perfil-7', ya_existia: true, email_enviado: false })
    // El caso legítimo y frecuente (renovación): el DNI ya era cliente… mío.
    enMiCartera.mockResolvedValue(true)
    montar()

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
    expect(aviso).toHaveTextContent(/se conservaron las cuentas bancarias que el cliente ya tenía/)
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
    convertirEdge.mockResolvedValue({ perfil_id: 'perfil-8', ya_existia: true, email_enviado: false })
    // La edge NO le cambia el asesor_perfil_id al cliente existente: sigue
    // siendo de quien lo tenía, y `public.crear_contrato` exige cartera propia.
    enMiCartera.mockResolvedValue(false)
    montar()

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
    convertirEdge.mockResolvedValue({ perfil_id: 'perfil-8', ya_existia: true, email_enviado: false })
    enMiCartera.mockResolvedValue(null) // red caída / RLS: NO es un "false"
    montar()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).not.toHaveTextContent(/NO pasó a tu cartera/)
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
    const { recargar } = montar()

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
    montar()

    await llenarIdentidad(user)
    await llenarPenCompleta(user)
    await user.click(screen.getByRole('button', { name: 'Convertir a cliente' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Este correo ya está registrado.')
    expect(actualizarCliente).not.toHaveBeenCalled()
    // El form sigue vivo para corregir y reintentar (no es el estado terminal).
    expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Entendido' })).not.toBeInTheDocument()
  })

  it('demo: el diálogo simulado NO pide bancarios (nada real que guardar)', () => {
    montar({ demo: true })
    expect(screen.queryByRole('group', { name: /Cuenta bancaria/ })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Convertir (demo)' })).toBeInTheDocument()
  })
})
