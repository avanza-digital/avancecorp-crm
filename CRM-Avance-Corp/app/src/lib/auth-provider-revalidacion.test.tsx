import { act, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AuthProvider, INTERVALO_REVALIDACION_ACCESO_MS } from './auth'
import { useAuth } from './auth-context'

const dobles = vi.hoisted(() => ({
  getUser: vi.fn(),
  rpc: vi.fn(),
  onAuthStateChange: vi.fn(),
  unsubscribe: vi.fn(),
}))

vi.mock('./supabase', () => ({
  sb: {
    auth: {
      getUser: dobles.getUser,
      onAuthStateChange: dobles.onAuthStateChange,
      signInWithPassword: vi.fn(),
      signOut: vi.fn(),
    },
    schema: () => ({ rpc: dobles.rpc }),
  },
}))

vi.mock('./observabilidad', () => ({
  registrarAviso: vi.fn(),
  registrarError: vi.fn(),
}))

function EstadoAcceso() {
  const { fase } = useAuth()
  return <span>{fase}</span>
}

async function drenarPromesas() {
  await act(async () => {
    for (let paso = 0; paso < 8; paso += 1) await Promise.resolve()
  })
}

describe('AuthProvider — actualización automática de permisos', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-08-25T15:00:00-05:00'))
    window.sessionStorage.clear()
    dobles.getUser.mockResolvedValue({
      data: { user: { id: 'asesor-1' } },
      error: null,
    })
    dobles.rpc.mockResolvedValue({
      data: {
        estado: 'miembro',
        perfil_id: 'asesor-1',
        rol_crm: 'vendedor',
        rol_portal: 'asesor',
        nombre_completo: 'Asesor Comercial',
        puede_listar_usuarios: false,
        puede_administrar_usuarios: false,
        puede_organizar_jerarquia: false,
        puede_administrar_roles: false,
      },
      error: null,
    })
    dobles.onAuthStateChange.mockReturnValue({
      data: { subscription: { unsubscribe: dobles.unsubscribe } },
    })
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('revalida cada 60 segundos solo con la pestaña visible y cancela el ciclo al desmontar', async () => {
    const visibilidad = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
    const setIntervalEspia = vi.spyOn(window, 'setInterval')
    const clearIntervalEspia = vi.spyOn(window, 'clearInterval')

    const vista = render(
      <AuthProvider>
        <EstadoAcceso />
      </AuthProvider>,
    )

    await drenarPromesas()
    expect(screen.getByText('listo')).toBeInTheDocument()
    expect(dobles.getUser).toHaveBeenCalledTimes(1)

    const indiceIntervalo = setIntervalEspia.mock.calls.findIndex(
      ([, espera]) => espera === INTERVALO_REVALIDACION_ACCESO_MS,
    )
    expect(indiceIntervalo).toBeGreaterThanOrEqual(0)
    const idIntervalo = setIntervalEspia.mock.results[indiceIntervalo]?.value

    await act(async () => {
      vi.advanceTimersByTime(INTERVALO_REVALIDACION_ACCESO_MS)
    })
    await drenarPromesas()
    expect(dobles.getUser).toHaveBeenCalledTimes(2)

    visibilidad.mockReturnValue('hidden')
    await act(async () => {
      vi.advanceTimersByTime(INTERVALO_REVALIDACION_ACCESO_MS)
    })
    await drenarPromesas()
    expect(dobles.getUser).toHaveBeenCalledTimes(2)

    visibilidad.mockReturnValue('visible')
    await act(async () => {
      vi.advanceTimersByTime(INTERVALO_REVALIDACION_ACCESO_MS)
    })
    await drenarPromesas()
    expect(dobles.getUser).toHaveBeenCalledTimes(3)

    vista.unmount()
    expect(clearIntervalEspia).toHaveBeenCalledWith(idIntervalo)
    expect(dobles.unsubscribe).toHaveBeenCalledOnce()

    await act(async () => {
      vi.advanceTimersByTime(INTERVALO_REVALIDACION_ACCESO_MS * 3)
    })
    expect(dobles.getUser).toHaveBeenCalledTimes(3)
  })
})
