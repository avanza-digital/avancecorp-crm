import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Yo } from '@/lib/tipos'
import { controlCitasInicial } from '@/lib/control-citas'

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), yo: null as Yo | null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: mocks.yo }) }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: mocks.rpc }) } }))
import { ConfigCitas } from '@/screens/config-citas'
import { guardarControlCitas } from './control-citas'

const vacia = { version_actual: 0, ultimo: null, historial: [] }
const identidad = (patch: Partial<Yo> = {}): Yo => ({ id: '90000000-0000-4000-8000-000000000001', nombre_completo: 'SUPERADMIN', rol: 'directorio', rol_portal: 'superadmin', demo: false, puede_contratar: false, ...patch })
function respuesta(data: unknown, error: unknown = null) {
  return { abortSignal: () => {}, then: (resolver: (r: unknown) => unknown) => Promise.resolve({ data, error }).then(resolver) }
}
function montar() {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 }, mutations: { retry: false } } })}><ConfigCitas /></QueryClientProvider>)
}
beforeEach(() => { vi.clearAllMocks(); mocks.yo = identidad(); mocks.rpc.mockReturnValue(respuesta(vacia)) })

describe('Control de Citas: acceso y persistencia', () => {
  it.each(['gerencia', 'supervisor', 'vendedor', 'directorio', 'coordinador'] as const)('no consulta para %s sin Superadmin', rol => {
    mocks.yo = identidad({ rol, rol_portal: 'analista' })
    montar()
    expect(screen.getByRole('alert')).toHaveTextContent('únicamente para Superadmin')
    expect(mocks.rpc).not.toHaveBeenCalled()
  })
  it('no usa el servidor desde una identidad demo ni desde Admin', () => {
    mocks.yo = identidad({ demo: true })
    const vista = montar()
    expect(screen.getByText(/sesión real de Superadmin/)).toBeInTheDocument()
    expect(mocks.rpc).not.toHaveBeenCalled()
    vista.unmount()
    mocks.yo = identidad({ rol_portal: 'admin' }); montar()
    expect(mocks.rpc).not.toHaveBeenCalled()
  })
  it('consulta y guarda un borrador con la revisión que el usuario editó', async () => {
    mocks.rpc.mockImplementation((nombre: string, args?: { p_configuracion: unknown }) => {
      if (nombre === 'control_citas_configuracion_fn') return respuesta(vacia)
      const ultimo = { version: 1, configuracion: args!.p_configuracion, guardado_en: '2026-09-11T21:00:00Z', guardado_por: identidad().id, nota: null, estado: 'borrador' }
      return respuesta({ version_actual: 1, ultimo, historial: [ultimo] })
    })
    montar()
    await userEvent.click(await screen.findByRole('button', { name: 'Guardar borrador' }))
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Borrador guardado'))
    expect(mocks.rpc).toHaveBeenCalledWith('guardar_control_citas_fn', {
      p_version_esperada: 0, p_configuracion: controlCitasInicial(), p_nota: '',
    })
    expect(screen.getByRole('status')).toHaveTextContent('Todavía no está aplicado')
  })
  it.each(['PGRST202', '42501', 'XX000'])('no fabrica una configuración cuando la consulta falla: %s', async code => {
    mocks.rpc.mockReturnValue(respuesta(null, { code, message: 'detalle interno sensible' }))
    montar()
    expect(await screen.findByRole('alert')).not.toHaveTextContent('detalle interno')
    expect(screen.queryByRole('button', { name: 'Guardar borrador' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
  })
  it('rechaza una respuesta parcial y un falso guardado', async () => {
    mocks.rpc.mockReturnValue(respuesta(vacia))
    await expect(guardarControlCitas({ versionEsperada: 0, configuracion: controlCitasInicial(), nota: '' })).rejects.toThrow('verificar el guardado')
    mocks.rpc.mockReturnValue(respuesta({ version_actual: 1, ultimo: null, historial: [] }))
    montar()
    expect(await screen.findByRole('alert')).toHaveTextContent('incompleta')
  })
  it('rechaza entradas inválidas antes de enviar al servidor', async () => {
    await expect(guardarControlCitas({ versionEsperada: -1, configuracion: controlCitasInicial(), nota: '' })).rejects.toThrow('Revisa')
    expect(mocks.rpc).not.toHaveBeenCalled()
  })
  it.each(['PT409', '23505'])('conserva la edición cuando falla la actualización después de un conflicto %s', async codigo => {
    let lecturas = 0
    mocks.rpc.mockImplementation((nombre: string) => {
      if (nombre === 'guardar_control_citas_fn') return respuesta(null, { code: codigo })
      lecturas += 1
      return lecturas === 1 ? respuesta(vacia) : respuesta(null, { code: 'XX000' })
    })
    montar()
    const campo = await screen.findByLabelText('Citas por lead')
    await userEvent.clear(campo); await userEvent.type(campo, '1,50')
    await userEvent.click(screen.getByRole('button', { name: 'Guardar borrador' }))
    await screen.findByRole('button', { name: 'Reintentar actualización' })
    expect(campo).toBeInTheDocument()
    expect(campo).toHaveValue('1,50')
  })
})
