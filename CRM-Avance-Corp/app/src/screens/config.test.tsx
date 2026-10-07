import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Clock, Users } from 'lucide-react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  catalogoUsuariosAdministrablesDemo,
  configuracionMetasDemo,
  configuracionProductosDemo,
  configuracionSlaDemo,
} from '@/lib/demo-config'
import type { Yo } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({
  yo: null as Yo | null,
  habilitaciones: {
    usuarios: [] as boolean[],
    productos: [] as boolean[],
    metas: [] as boolean[],
    sla: [] as boolean[],
  },
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

vi.mock('@/components/app/calendario-google', () => ({
  CalendarioGoogle: () => <div>Calendario personal</div>,
}))

vi.mock('@/components/config/reparto-libre', () => ({
  RepartoLibre: () => <div>Control de reparto libre</div>,
}))

function consulta<T>(data: T) {
  return {
    data,
    isPending: false,
    isError: false,
    refetch: vi.fn(),
  }
}

vi.mock('@/data/crm-config-queries', () => ({
  useCatalogoUsuariosAdministrables: (habilitada: boolean) => {
    dobles.habilitaciones.usuarios.push(habilitada)
    return consulta(catalogoUsuariosAdministrablesDemo())
  },
  useConfiguracionProductos: (habilitada: boolean) => {
    dobles.habilitaciones.productos.push(habilitada)
    return consulta(configuracionProductosDemo())
  },
  useConfiguracionMetas: (_periodo: string, habilitada: boolean) => {
    dobles.habilitaciones.metas.push(habilitada)
    return consulta(configuracionMetasDemo('2026-08-01'))
  },
  useConfiguracionSla: (habilitada: boolean) => {
    dobles.habilitaciones.sla.push(habilitada)
    return consulta(configuracionSlaDemo())
  },
}))

const { Config, RielEstadoConfiguracion } = await import('./config')

function identidad(overrides: Partial<Yo> = {}): Yo {
  return {
    id: '90000000-0000-4000-8000-000000000001',
    nombre_completo: 'GERENCIA DEMO',
    rol: 'gerencia',
    demo: true,
    puede_contratar: true,
    ...overrides,
  }
}

beforeEach(() => {
  dobles.yo = identidad()
  dobles.habilitaciones.usuarios.length = 0
  dobles.habilitaciones.productos.length = 0
  dobles.habilitaciones.metas.length = 0
  dobles.habilitaciones.sla.length = 0
})

describe('Configuración y riel operativo', () => {
  it.each(['gerencia', 'supervisor', 'vendedor', 'directorio', 'coordinador'] as const)('solo Gerencia real ve el control de reparto: %s', (rol) => {
    dobles.yo = identidad({ rol, demo: false })
    render(<Config />)
    expect(screen.queryByText('Control de reparto libre') !== null).toBe(rol === 'gerencia')
  })

  it('Gerencia demo no muestra un control real de reparto', () => {
    render(<Config />)
    expect(screen.queryByText('Control de reparto libre')).not.toBeInTheDocument()
  })
  it('muestra a Gerencia demo los cuatro estados coherentes, todos en solo lectura', () => {
    render(<Config />)

    expect(screen.getByText(/Demostración de solo lectura/)).toBeInTheDocument()
    const riel = screen.getByRole('list', { name: 'Estado operativo de la configuración' })
    expect(within(riel).getAllByRole('listitem')).toHaveLength(4)
    expect(within(riel).getByText('8 de 9 habilitadas')).toBeInTheDocument()
    expect(within(riel).getByText('2 productos · revisión 6')).toBeInTheDocument()
    expect(within(riel).getByText('4 analistas · revisión 5')).toBeInTheDocument()
    expect(within(riel).getByText('v3 · gestión 2 horas')).toBeInTheDocument()
    // Siete tarjetas para Gerencia: las seis de siempre y «Celulares» (F4-c, 07/10/2026).
    expect(screen.getAllByText('Solo lectura')).toHaveLength(7)

    expect(dobles.habilitaciones).toEqual({
      usuarios: [true],
      productos: [true],
      metas: [true],
      sla: [true],
    })
  })

  it('ofrece Control de Citas al Superadmin sin habilitar lecturas comerciales', () => {
    dobles.yo = identidad({
      // Proyección real de `administrador_roles`: sin rol CRM en el RPC y con
      // Directorio únicamente como compatibilidad interna del tipo `Yo`.
      rol: 'directorio',
      rol_portal: 'superadmin',
      capacidades_config: {
        puede_listar_usuarios: true,
        puede_administrar_usuarios: false,
        puede_organizar_jerarquia: false,
        puede_administrar_roles: true,
      },
      demo: false,
      puede_contratar: false,
    })
    render(<Config />)

    const riel = screen.getByRole('list', { name: 'Estado operativo de la configuración' })
    expect(within(riel).getAllByRole('listitem')).toHaveLength(1)
    expect(screen.getByText('Usuarios y jerarquía')).toBeInTheDocument()
    expect(screen.queryByText('Productos de inversión')).not.toBeInTheDocument()
    expect(screen.getAllByText('Administración')).toHaveLength(2)
    expect(screen.getByRole('heading', { name: 'Control de Citas' })).toBeInTheDocument()
    expect(screen.getAllByRole('link').find(enlace => enlace.getAttribute('href') === '#/config-citas')).toBeDefined()
    expect(screen.getByText(/Gobierno de roles/)).toBeInTheDocument()
    expect(screen.queryByText('Calendario personal')).not.toBeInTheDocument()
    expect(dobles.habilitaciones).toEqual({
      usuarios: [true],
      productos: [false],
      metas: [false],
      sla: [false],
    })
  })

  it('representa carga y error por tramo, con reintento accesible', async () => {
    const recargar = vi.fn()
    render(<RielEstadoConfiguracion pasos={[
      {
        vista: 'config-usuarios',
        icono: Users,
        etiqueta: 'Personas activas',
        detalle: '',
        cargando: true,
        error: false,
        recargar: vi.fn(),
      },
      {
        vista: 'config-sla',
        icono: Clock,
        etiqueta: 'SLA vigente',
        detalle: '',
        cargando: false,
        error: true,
        recargar,
      },
    ]} />)

    expect(screen.getByRole('status')).toHaveTextContent('Verificando')
    expect(screen.getByText('Lectura no disponible')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar SLA vigente' }))
    expect(recargar).toHaveBeenCalledOnce()
    expect(screen.getByRole('link', { name: 'Abrir SLA vigente' })).toHaveAttribute('href', '#/config-sla')
  })
})
