import type { ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Yo } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({
  yo: {
    id: 'demo-gerencia',
    nombre_completo: 'GERENCIA DEMO',
    rol: 'gerencia',
    demo: true,
    puede_contratar: true,
  } as Yo,
  listarUsuarios: vi.fn(),
  listarCatalogoUsuarios: vi.fn(),
  obtenerProductos: vi.fn(),
  listarProductos: vi.fn(),
  obtenerMetas: vi.fn(),
  obtenerSla: vi.fn(),
  obtenerMetricasSla: vi.fn(),
  crearUsuario: vi.fn(),
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

vi.mock('./crm-config-api', async () => {
  const real = await vi.importActual<typeof import('./crm-config-api')>('./crm-config-api')
  return {
    ...real,
    listarUsuariosAdministrables: dobles.listarUsuarios,
    listarCatalogoUsuariosAdministrables: dobles.listarCatalogoUsuarios,
    obtenerConfiguracionProductos: dobles.obtenerProductos,
    listarProductosSeleccionables: dobles.listarProductos,
    obtenerConfiguracionMetas: dobles.obtenerMetas,
    obtenerConfiguracionSla: dobles.obtenerSla,
    obtenerMetricasSla: dobles.obtenerMetricasSla,
    crearCandidatoUsuario: dobles.crearUsuario,
  }
})

const {
  useCatalogoUsuariosAdministrables,
  useConfiguracionMetas,
  useConfiguracionProductos,
  useConfiguracionSla,
  useCrearCandidatoUsuario,
  useMetricasSla,
  useProductosSeleccionables,
  useUsuariosAdministrables,
} = await import('./crm-config-queries')

function crearWrapper() {
  const cliente = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
  }
}

beforeEach(() => {
  dobles.yo = {
    id: 'demo-gerencia',
    nombre_completo: 'GERENCIA DEMO',
    rol: 'gerencia',
    demo: true,
    puede_contratar: true,
  }
  for (const doble of [
    dobles.listarUsuarios,
    dobles.listarCatalogoUsuarios,
    dobles.obtenerProductos,
    dobles.listarProductos,
    dobles.obtenerMetas,
    dobles.obtenerSla,
    dobles.obtenerMetricasSla,
    dobles.crearUsuario,
  ]) doble.mockReset()
})

describe('crm-config-queries en modo demo', () => {
  it('resuelve los cuatro módulos y el selector sin tocar la API real', async () => {
    const { result } = renderHook(() => ({
      usuarios: useUsuariosAdministrables('', 25, 0),
      catalogoUsuarios: useCatalogoUsuariosAdministrables(),
      productos: useConfiguracionProductos(),
      selector: useProductosSeleccionables(),
      metas: useConfiguracionMetas('2026-08-01'),
      sla: useConfiguracionSla(),
      metricas: useMetricasSla('2026-08-01', '2026-08-31'),
    }), { wrapper: crearWrapper() })

    await waitFor(() => {
      expect(result.current.usuarios.isSuccess).toBe(true)
      expect(result.current.catalogoUsuarios.isSuccess).toBe(true)
      expect(result.current.productos.isSuccess).toBe(true)
      expect(result.current.selector.isSuccess).toBe(true)
      expect(result.current.metas.isSuccess).toBe(true)
      expect(result.current.sla.isSuccess).toBe(true)
      expect(result.current.metricas.isSuccess).toBe(true)
    })

    expect(result.current.usuarios.data).toHaveLength(9)
    expect(result.current.productos.data?.productos).toHaveLength(2)
    expect(result.current.selector.data).toHaveLength(6)
    expect(result.current.metas.data?.vendedores).toHaveLength(4)
    expect(result.current.sla.data?.politica.version).toBe(3)
    expect(result.current.metricas.data?.ciclos.primera_gestion[0]?.total).toBe(48)

    expect(dobles.listarUsuarios).not.toHaveBeenCalled()
    expect(dobles.listarCatalogoUsuarios).not.toHaveBeenCalled()
    expect(dobles.obtenerProductos).not.toHaveBeenCalled()
    expect(dobles.listarProductos).not.toHaveBeenCalled()
    expect(dobles.obtenerMetas).not.toHaveBeenCalled()
    expect(dobles.obtenerSla).not.toHaveBeenCalled()
    expect(dobles.obtenerMetricasSla).not.toHaveBeenCalled()
  })

  it('rechaza una mutación demo antes de invocar Supabase', async () => {
    const { result } = renderHook(() => useCrearCandidatoUsuario(), {
      wrapper: crearWrapper(),
    })

    await act(async () => {
      await expect(result.current.mutateAsync({
        correo: 'persona@demo.avance.test',
        nombre_completo: 'PERSONA DEMO',
        tipo_documento: 'DNI',
        documento: '70000010',
        supervisor_id: '20000000-0000-4000-8000-000000000001',
      })).rejects.toMatchObject({ code: 'DEMO_SOLO_LECTURA' })
    })
    expect(dobles.crearUsuario).not.toHaveBeenCalled()
  })
})
