import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Yo } from '@/lib/tipos'
import type {
  ImpactoDesactivacionUsuario,
  UsuarioAdministrable,
} from '@/lib/usuarios-config'

const dobles = vi.hoisted(() => ({
  yo: null as Yo | null,
  consulta: {} as Record<string, unknown>,
  catalogo: {} as Record<string, unknown>,
  crear: vi.fn(),
  editar: vi.fn(),
  asignarRol: vi.fn(),
  jerarquia: vi.fn(),
  impacto: vi.fn(),
  membresia: vi.fn(),
  toastSuccess: vi.fn(),
  toastWarning: vi.fn(),
  toastError: vi.fn(),
}))

vi.mock('sonner', () => ({
  toast: { success: dobles.toastSuccess, warning: dobles.toastWarning, error: dobles.toastError },
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

vi.mock('@/data/crm-config-queries', () => ({
  useUsuariosAdministrables: () => dobles.consulta,
  useCatalogoUsuariosAdministrables: () => dobles.catalogo,
  useCrearCandidatoUsuario: () => ({ mutateAsync: dobles.crear, isPending: false }),
  useActualizarUsuarioAdministrable: () => ({ mutateAsync: dobles.editar, isPending: false }),
  useAsignarRolUsuario: () => ({ mutateAsync: dobles.asignarRol, isPending: false }),
  useActualizarJerarquiaUsuario: () => ({ mutateAsync: dobles.jerarquia, isPending: false }),
  useImpactoDesactivacionUsuario: () => ({ mutateAsync: dobles.impacto, isPending: false }),
  useFijarMembresiaUsuario: () => ({ mutateAsync: dobles.membresia, isPending: false }),
}))

const { ConfigUsuarios } = await import('./config-usuarios')

const ID_VENDEDOR = '10000000-0000-4000-8000-000000000001'
const ID_REEMPLAZO = '10000000-0000-4000-8000-000000000002'
const ID_SUPERVISOR = '20000000-0000-4000-8000-000000000001'
const ID_GERENCIA = '30000000-0000-4000-8000-000000000001'

function identidad(
  rol: Yo['rol'],
  overrides: Partial<Yo> = {},
): Yo {
  return {
    id: '90000000-0000-4000-8000-000000000001',
    nombre_completo: 'USUARIO ACTUAL',
    rol,
    demo: false,
    puede_contratar: false,
    ...overrides,
  }
}

function usuario(overrides: Partial<UsuarioAdministrable> = {}): UsuarioAdministrable {
  return {
    perfil_id: ID_VENDEDOR,
    nombre_completo: 'ANA ANALISTA',
    tipo_documento: 'DNI',
    documento: '45781234',
    correo: 'ana@example.com',
    telefono: '999111222',
    whatsapp: '999111222',
    cargo: 'Analista',
    tipo_cuenta: 'solo_crm',
    estado: 'activo',
    rol_crm: 'vendedor',
    supervisor_id: ID_SUPERVISOR,
    activo_crm: true,
    activo_portal: true,
    version_perfil: '2026-08-07T15:00:00.000Z',
    version_equipo: '2026-08-07T15:00:00.000Z',
    total: 3,
    ...overrides,
  }
}

const SUPERVISOR = usuario({
  perfil_id: ID_SUPERVISOR,
  nombre_completo: 'SUPERVISOR UNO',
  correo: 'supervisor@example.com',
  documento: '45781235',
  rol_crm: 'supervisor',
  supervisor_id: null,
})

const REEMPLAZO = usuario({
  perfil_id: ID_REEMPLAZO,
  nombre_completo: 'BEA ANALISTA',
  correo: 'bea@example.com',
  documento: '45781236',
})

const GERENCIA = usuario({
  perfil_id: ID_GERENCIA,
  nombre_completo: 'GERENTE GENERAL',
  correo: 'gerencia@example.com',
  documento: '45781237',
  rol_crm: 'gerencia',
  supervisor_id: null,
})

function consultaCon(
  data: UsuarioAdministrable[] | undefined,
  overrides: Record<string, unknown> = {},
) {
  return {
    data,
    error: null,
    isPending: false,
    isError: false,
    isSuccess: Boolean(data),
    refetch: vi.fn(),
    ...overrides,
  }
}

beforeEach(() => {
  dobles.yo = identidad('gerencia')
  dobles.consulta = consultaCon([usuario()])
  dobles.catalogo = consultaCon([usuario(), REEMPLAZO, SUPERVISOR, GERENCIA])
  dobles.crear.mockReset().mockResolvedValue({
    estado: 'activo',
    perfil_id: '30000000-0000-4000-8000-000000000001',
  })
  dobles.editar.mockReset().mockResolvedValue({})
  dobles.asignarRol.mockReset().mockResolvedValue({})
  dobles.jerarquia.mockReset().mockResolvedValue({})
  dobles.impacto.mockReset().mockResolvedValue({
    perfil_id: ID_VENDEDOR,
    subordinados_activos: 0,
    leads_abiertos: 4,
    leads_en_bandeja: 0,
    tareas_pendientes: 2,
    clientes_activos: 1,
    requiere_reemplazo: true,
  } satisfies ImpactoDesactivacionUsuario)
  dobles.membresia.mockReset().mockResolvedValue({})
  dobles.toastSuccess.mockReset()
  dobles.toastWarning.mockReset()
  dobles.toastError.mockReset()
})

describe('ConfigUsuarios', () => {
  it('representa carga, error seguro con reintento y búsqueda vacía', async () => {
    dobles.consulta = consultaCon(undefined, { isPending: true })
    const carga = render(<ConfigUsuarios />)
    expect(screen.getByRole('status')).toHaveTextContent('Cargando el directorio autorizado')
    carga.unmount()

    const refetch = vi.fn()
    dobles.consulta = consultaCon(undefined, {
      isError: true,
      error: new Error('detalle SQL privado'),
      refetch,
    })
    const error = render(<ConfigUsuarios />)
    expect(screen.getByText('No se pudo cargar el directorio.')).toBeInTheDocument()
    expect(screen.queryByText(/detalle SQL privado/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(refetch).toHaveBeenCalledOnce()
    error.unmount()

    dobles.consulta = consultaCon([])
    render(<ConfigUsuarios />)
    expect(screen.getByText('No hay usuarios que coincidan con la búsqueda.')).toBeInTheDocument()
    expect(screen.getByText('0 usuarios')).toBeInTheDocument()
  })

  it('separa las capacidades de Gerencia, Superadmin y Directorio', () => {
    const gerencia = render(<ConfigUsuarios />)
    expect(screen.getByRole('button', { name: 'Nuevo usuario' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Datos' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Jerarquía' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Desactivar' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Acceso' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Rol' })).not.toBeInTheDocument()
    gerencia.unmount()

    dobles.yo = identidad('directorio', { rol_portal: 'superadmin' })
    const superadmin = render(<ConfigUsuarios />)
    expect(screen.getByText('Vista mínima autorizada para gobierno de roles.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Rol' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nuevo usuario' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Datos' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Jerarquía' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Desactivar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Acceso' })).not.toBeInTheDocument()
    superadmin.unmount()

    dobles.yo = identidad('directorio')
    render(<ConfigUsuarios />)
    expect(screen.getByText(/Solo lectura: puedes auditar/)).toBeInTheDocument()
    expect(screen.getByText('Auditoría redactada: sin PII, jerarquía ni acciones.')).toBeInTheDocument()
    expect(screen.getByText('Usuario CRM · 00000001')).toBeInTheDocument()
    expect(screen.getByText('Redactada')).toBeInTheDocument()
    expect(screen.getByText('Solo lectura')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Buscar por identificador, rol o estado')).toBeInTheDocument()
    expect(screen.queryByText('ANA ANALISTA')).not.toBeInTheDocument()
    expect(screen.queryByText('ana@example.com')).not.toBeInTheDocument()
    expect(screen.queryByText('45781234')).not.toBeInTheDocument()
    expect(screen.queryByText(/Actualizado/)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nuevo usuario' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Rol' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Datos' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Jerarquía' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Desactivar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Acceso' })).not.toBeInTheDocument()
  })

  it('mantiene a Gerencia demo en solo lectura sin simular escrituras', () => {
    dobles.yo = identidad('gerencia', { demo: true })
    render(<ConfigUsuarios />)

    expect(screen.getByText(/Solo lectura: puedes auditar/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nuevo usuario' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Datos' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Jerarquía' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Desactivar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Acceso' })).not.toBeInTheDocument()
    expect(dobles.crear).not.toHaveBeenCalled()
    expect(dobles.editar).not.toHaveBeenCalled()
    expect(dobles.membresia).not.toHaveBeenCalled()
  })

  it('crea y activa un analista con supervisor y datos normalizados', async () => {
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Nuevo usuario' }))
    const dialogo = screen.getByRole('dialog', { name: 'Nuevo analista CRM' })
    await user.type(within(dialogo).getByLabelText('Nombre completo'), '  Juana Pérez  ')
    await user.type(within(dialogo).getByLabelText('Correo'), '  JUANA@EXAMPLE.COM  ')
    await user.type(within(dialogo).getByLabelText('Documento'), '45781237')
    await user.type(within(dialogo).getByLabelText('Teléfono'), '999222333')
    await user.type(within(dialogo).getByLabelText('Cargo'), 'Ejecutiva comercial')
    await user.selectOptions(within(dialogo).getByLabelText('Supervisor'), ID_SUPERVISOR)
    await user.click(within(dialogo).getByRole('button', { name: 'Crear y activar' }))

    await waitFor(() => expect(dobles.crear).toHaveBeenCalledOnce())
    expect(dobles.crear).toHaveBeenCalledWith({
      correo: 'juana@example.com',
      nombre_completo: 'Juana Pérez',
      tipo_documento: 'DNI',
      documento: '45781237',
      supervisor_id: ID_SUPERVISOR,
      telefono: '999222333',
      whatsapp: undefined,
      cargo: 'Ejecutiva comercial',
    })
    expect(dobles.toastSuccess).toHaveBeenCalledWith(
      'Analista CRM creado y activado. Ya puede ingresar con su documento.',
    )
    expect(screen.queryByRole('dialog', { name: 'Nuevo analista CRM' })).not.toBeInTheDocument()
  })

  it('conserva correo y documento como identidad inmutable al editar datos', async () => {
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Datos' }))
    const dialogo = screen.getByRole('dialog', { name: 'Editar datos del usuario' })
    expect(within(dialogo).getByLabelText('Correo')).toBeDisabled()
    expect(within(dialogo).getByLabelText('Tipo de documento')).toBeDisabled()
    expect(within(dialogo).getByLabelText('Documento')).toBeDisabled()
    expect(within(dialogo).getByLabelText('Nombre completo')).toBeEnabled()
  })

  it('explica y permite reintentar cuando falla el catálogo de supervisores', async () => {
    const refetch = vi.fn()
    dobles.catalogo = consultaCon(undefined, {
      isError: true,
      error: new Error('fallo privado'),
      refetch,
    })
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Nuevo usuario' }))
    const dialogo = screen.getByRole('dialog', { name: 'Nuevo analista CRM' })
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('No se pudieron cargar los supervisores.')
    expect(within(dialogo).queryByText('No hay supervisores activos disponibles.')).not.toBeInTheDocument()
    expect(within(dialogo).getByRole('button', { name: 'Crear y activar' })).toBeDisabled()
    await user.click(within(dialogo).getByRole('button', { name: 'Reintentar supervisores' }))
    expect(refetch).toHaveBeenCalledOnce()
  })

  it('advierte cuando detecta una identidad del Portal y no presenta el no-op como alta', async () => {
    dobles.crear.mockResolvedValue({
      estado: 'candidato_existente',
      perfil_id: ID_VENDEDOR,
    })
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Nuevo usuario' }))
    const dialogo = screen.getByRole('dialog', { name: 'Nuevo analista CRM' })
    await user.type(within(dialogo).getByLabelText('Nombre completo'), 'Analista Portal')
    await user.type(within(dialogo).getByLabelText('Correo'), 'analista@example.com')
    await user.type(within(dialogo).getByLabelText('Documento'), '45781238')
    await user.selectOptions(within(dialogo).getByLabelText('Supervisor'), ID_SUPERVISOR)
    await user.click(within(dialogo).getByRole('button', { name: 'Crear y activar' }))

    await waitFor(() => expect(dobles.toastWarning).toHaveBeenCalledWith(
      'Identidad del Portal detectada: no se cambió su acceso. Superadmin debe asignarle el rol CRM.',
    ))
    expect(dobles.toastSuccess).not.toHaveBeenCalled()
  })

  it('permite a Gerencia completar un candidato CRM pendiente sin administrar otros roles', async () => {
    dobles.consulta = consultaCon([usuario({
      estado: 'pendiente_rol',
      rol_crm: null,
      supervisor_id: null,
      activo_crm: null,
      version_equipo: null,
    })])
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    expect(screen.queryByRole('button', { name: 'Rol' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Completar alta de ANA ANALISTA' }))
    const dialogo = screen.getByRole('dialog', { name: 'Completar alta de ANA ANALISTA' })
    await user.selectOptions(within(dialogo).getByLabelText('Supervisor'), ID_SUPERVISOR)
    await user.click(within(dialogo).getByRole('button', { name: 'Activar analista' }))

    await waitFor(() => expect(dobles.crear).toHaveBeenCalledWith({
      correo: 'ana@example.com',
      nombre_completo: 'ANA ANALISTA',
      tipo_documento: 'DNI',
      documento: '45781234',
      supervisor_id: ID_SUPERVISOR,
      telefono: '999111222',
      whatsapp: '999111222',
      cargo: 'Analista',
    }))
    expect(dobles.toastSuccess).toHaveBeenCalledWith(
      'Alta completada. El analista ya puede ingresar al CRM.',
    )
  })

  it('no ofrece el alta directa a una identidad compartida con el Portal', () => {
    dobles.consulta = consultaCon([usuario({
      tipo_cuenta: 'compartida_portal',
      estado: 'pendiente_rol',
      rol_crm: null,
      supervisor_id: null,
      activo_crm: null,
      version_equipo: null,
    })])
    render(<ConfigUsuarios />)

    expect(screen.queryByRole('button', { name: /Completar alta de/ })).not.toBeInTheDocument()
  })

  it('rechaza un alta inválida antes de invocar la frontera', async () => {
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Nuevo usuario' }))
    const dialogo = screen.getByRole('dialog', { name: 'Nuevo analista CRM' })
    await user.type(within(dialogo).getByLabelText('Nombre completo'), 'A')
    await user.selectOptions(within(dialogo).getByLabelText('Supervisor'), ID_SUPERVISOR)
    await user.click(within(dialogo).getByRole('button', { name: 'Crear y activar' }))

    expect(dobles.toastError).toHaveBeenCalledWith(
      'El nombre completo debe tener entre 2 y 160 caracteres.',
    )
    expect(dobles.crear).not.toHaveBeenCalled()
    expect(screen.getByRole('dialog', { name: 'Nuevo analista CRM' })).toBeInTheDocument()
  })

  it('permite que solo Superadmin confirme el cambio de rol', async () => {
    dobles.yo = identidad('directorio', { rol_portal: 'superadmin' })
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Rol' }))
    const dialogo = screen.getByRole('dialog', { name: 'Rol CRM de ANA ANALISTA' })
    await user.selectOptions(within(dialogo).getByLabelText('Rol CRM'), 'gerencia')
    expect(dobles.asignarRol).not.toHaveBeenCalled()
    await user.click(within(dialogo).getByRole('button', { name: 'Confirmar rol' }))

    await waitFor(() => expect(dobles.asignarRol).toHaveBeenCalledWith({
      perfilId: ID_VENDEDOR,
      rol: 'gerencia',
      versionEquipo: '2026-08-07T15:00:00.000Z',
    }))
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Rol CRM actualizado.')
  })

  it('ofrece a un analista únicamente supervisores compatibles, nunca Gerencia', async () => {
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Jerarquía' }))
    const dialogo = screen.getByRole('dialog', { name: 'Jerarquía de ANA ANALISTA' })
    const selector = within(dialogo).getByLabelText('Supervisor')

    expect(within(selector).getByRole('option', { name: 'SUPERVISOR UNO · Supervisor' })).toBeInTheDocument()
    expect(within(selector).queryByRole('option', { name: /GERENTE GENERAL/ })).not.toBeInTheDocument()
  })

  it('bloquea activar a un analista hasta que tenga supervisor', async () => {
    dobles.consulta = consultaCon([usuario({
      estado: 'inactivo_crm',
      activo_crm: false,
      supervisor_id: null,
    })])
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Activar' }))
    const dialogo = screen.getByRole('dialog', { name: 'Activar membresía CRM' })
    expect(within(dialogo).getByText('Asigna un supervisor activo antes de habilitar a este analista.')).toBeInTheDocument()
    expect(within(dialogo).getByRole('button', { name: 'Activar membresía' })).toBeDisabled()
    expect(dobles.membresia).not.toHaveBeenCalled()
  })

  it('desactiva solo después de evaluar impacto y elegir reemplazo', async () => {
    const user = userEvent.setup()
    render(<ConfigUsuarios />)

    await user.click(screen.getByRole('button', { name: 'Desactivar' }))
    await waitFor(() => expect(dobles.impacto).toHaveBeenCalledWith(ID_VENDEDOR))
    const dialogo = await screen.findByRole('dialog', { name: 'Desactivar membresía CRM' })
    expect(within(dialogo).getByText('4')).toBeInTheDocument()
    expect(within(dialogo).getByText('Leads asignados')).toBeInTheDocument()
    expect(within(dialogo).getByRole('button', { name: 'Desactivar y transferir' })).toBeDisabled()
    expect(dobles.membresia).not.toHaveBeenCalled()

    await user.selectOptions(within(dialogo).getByLabelText('Reemplazo activo del mismo rol'), ID_REEMPLAZO)
    await user.click(within(dialogo).getByRole('button', { name: 'Desactivar y transferir' }))

    await waitFor(() => expect(dobles.membresia).toHaveBeenCalledWith({
      perfilId: ID_VENDEDOR,
      activo: false,
      reemplazoId: ID_REEMPLAZO,
      versionEquipo: '2026-08-07T15:00:00.000Z',
    }))
    expect(dobles.toastSuccess).toHaveBeenCalledWith(
      'Membresía desactivada y responsabilidades transferidas.',
    )
  })
})
