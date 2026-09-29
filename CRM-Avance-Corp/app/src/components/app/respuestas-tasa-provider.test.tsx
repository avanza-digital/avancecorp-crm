import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'
import { AUTH_CLEARED_EVENT } from '@/lib/seguridad'
import { guardarRegistroRespuestas, leerRegistroRespuestas } from '@/lib/respuestas-tasa'
import { useRespuestasTasa } from '@/lib/respuestas-tasa-context'

const dobles = vi.hoisted(() => ({
  yo: { id: 'v-provider', rol: 'vendedor', demo: false },
  consulta: { data: [] as SolicitudTasa[], isSuccess: true, isFetchedAfterMount: true, isError: false, isPending: false, dataUpdatedAt: 1, refetch: vi.fn() },
  query: vi.fn(), toast: vi.fn(() => 'aviso-1'), dismiss: vi.fn(),
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/data/crm-queries', () => ({ crmQueryKeys: { rentabilidad: () => ['crm', 'rentabilidad'] } }))
vi.mock('@tanstack/react-query', () => ({ useQuery: (opciones: unknown) => { dobles.query(opciones); return dobles.consulta } }))
vi.mock('sonner', () => ({ toast: Object.assign(dobles.toast, { dismiss: dobles.dismiss }) }))

const { RespuestasTasaProvider } = await import('./respuestas-tasa-provider')

function Probe() {
  const a = useRespuestasTasa()
  return <><p>{a.habilitado ? 'Alertas habilitadas' : 'Sin alertas'}</p><p>Sin leer: {a.sinLeer}</p>
    <button onClick={() => void a.activar()}>Activar</button><button onClick={a.abrirBandeja}>Bandeja</button></>
}
function respuesta(sobre: Partial<SolicitudTasa> = {}): SolicitudTasa {
  return { id: 's-provider', es_mia: true, solicitada_por: 'v-provider', resuelta_por: 'g-1', resuelta_en: '2026-09-11T15:00:00Z',
    estado: 'aprobada', estado_efectivo: 'aprobada', tasa_solicitada: 18, tasa_maxima_autorizada: 18, cliente_nombre: 'CLIENTE PROPIO', ...sobre } as SolicitudTasa
}

describe('ciclo de sesión de las respuestas del analista', () => {
  beforeEach(() => {
    localStorage.clear()
    window.location.hash = '#/hoy'
    dobles.yo = { id: 'v-provider', rol: 'vendedor', demo: false }
    dobles.consulta = { ...dobles.consulta, data: [], isSuccess: true, isFetchedAfterMount: true, isError: false, isPending: false, dataUpdatedAt: 1 }
    guardarRegistroRespuestas('v-provider', { ...leerRegistroRespuestas('v-provider'), iniciado: true })
    vi.spyOn(document, 'hasFocus').mockReturnValue(true)
  })
  afterEach(() => vi.unstubAllGlobals())

  it('no monta consultas ni controles en demo, Gerencia o Directorio', () => {
    for (const cuenta of [{ ...dobles.yo, demo: true }, { ...dobles.yo, rol: 'gerencia' }, { ...dobles.yo, rol: 'directorio' }]) {
      dobles.yo = cuenta
      const vista = render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
      expect(screen.getByText('Sin alertas')).toBeVisible()
      vista.unmount()
    }
    expect(dobles.query).not.toHaveBeenCalled()
  })

  it('consulta por cuenta, no anuncia caché antes de una lectura nueva y filtra al dueño', async () => {
    dobles.consulta = { ...dobles.consulta, isFetchedAfterMount: false, data: [respuesta()] }
    const vista = render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    expect(dobles.query).toHaveBeenCalledWith(expect.objectContaining({ queryKey: ['crm', 'rentabilidad', 'respuestas-analista', 'v-provider'], refetchIntervalInBackground: true }))
    // Ritmo adaptativo: 2 min en reposo; 15 s solo con una solicitud propia pendiente de Gerencia.
    const opciones = dobles.query.mock.calls.at(-1)![0] as { refetchInterval: (q: { state: { data?: SolicitudTasa[] | undefined } }) => number }
    expect(opciones.refetchInterval({ state: { data: [respuesta()] } })).toBe(120_000)
    expect(opciones.refetchInterval({ state: { data: undefined } })).toBe(120_000)
    expect(opciones.refetchInterval({ state: { data: [respuesta({ estado: 'pendiente', estado_efectivo: 'pendiente', resuelta_por: null, resuelta_en: null })] } })).toBe(15_000)
    expect(opciones.refetchInterval({ state: { data: [respuesta({ estado: 'pendiente', estado_efectivo: 'pendiente', solicitada_por: 'v-otro' })] } })).toBe(120_000)
    expect(dobles.toast).not.toHaveBeenCalled()
    dobles.consulta = { ...dobles.consulta, isFetchedAfterMount: true, dataUpdatedAt: 2,
      data: [respuesta(), respuesta({ id: 'ajena', solicitada_por: 'v-otro', cliente_nombre: 'NO REVELAR' })] }
    vista.rerender(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    await waitFor(() => expect(screen.getByText('Sin leer: 1')).toBeVisible())
    expect(dobles.toast).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(dobles.toast.mock.calls)).not.toContain('NO REVELAR')
  })

  it('una respuesta esperando el bloqueo no se muestra ni se guarda si la sesión termina', async () => {
    let ejecutar: (() => unknown) | undefined
    vi.stubGlobal('navigator', { locks: { request: (_: string, fn: () => unknown) => new Promise(resolve => { ejecutar = () => resolve(fn()) }) } })
    dobles.consulta = { ...dobles.consulta, data: [respuesta()] }
    render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    act(() => window.dispatchEvent(new Event(AUTH_CLEARED_EVENT)))
    await act(async () => { ejecutar?.() })
    expect(screen.getByText('Sin alertas')).toBeVisible()
    expect(dobles.toast).not.toHaveBeenCalled()
    expect(leerRegistroRespuestas('v-provider').respuestas).toEqual({})
  })

  it('una pestaña de fondo sin audio ni permiso no consume el aviso de otra pestaña', async () => {
    vi.spyOn(document, 'hasFocus').mockReturnValue(false)
    vi.stubGlobal('navigator', { locks: { request: async (_: string, fn: () => unknown) => fn() } })
    dobles.consulta = { ...dobles.consulta, data: [respuesta()] }
    const vista = render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    await act(async () => {})
    expect(dobles.toast).not.toHaveBeenCalled()
    expect(leerRegistroRespuestas('v-provider').respuestas).toEqual({})
    vi.spyOn(document, 'hasFocus').mockReturnValue(true)
    dobles.consulta = { ...dobles.consulta, dataUpdatedAt: 2 }
    vista.rerender(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    await waitFor(() => expect(dobles.toast).toHaveBeenCalledOnce())
    expect(screen.getByText('Sin leer: 1')).toBeVisible()
  })

  it('el resultado tardío del permiso no activa otra sesión y cierra el audio', async () => {
    let responder: ((valor: string) => void) | undefined
    const close = vi.fn(async () => {})
    vi.stubGlobal('AudioContext', class { state = 'running'; resume = async () => {}; close = close })
    vi.stubGlobal('Notification', class {
      static permission = 'default'
      static requestPermission = () => new Promise(resolve => { responder = resolve })
    })
    render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    fireEvent.click(screen.getByRole('button', { name: 'Activar' }))
    act(() => window.dispatchEvent(new Event(AUTH_CLEARED_EVENT)))
    await act(async () => { responder?.('granted') })
    expect(leerRegistroRespuestas('v-provider').configurado).toBe(false)
    expect(close).toHaveBeenCalled()
    expect(screen.getByText('Sin alertas')).toBeVisible()
  })

  it('una acción de un aviso antiguo no abre una solicitud después de salir', async () => {
    dobles.consulta = { ...dobles.consulta, data: [respuesta()] }
    render(<RespuestasTasaProvider><Probe /></RespuestasTasaProvider>)
    await waitFor(() => expect(dobles.toast).toHaveBeenCalledOnce())
    const opciones = (dobles.toast.mock.calls[0] as unknown as [string, { action: { onClick: () => void } }])[1]
    act(() => window.dispatchEvent(new Event(AUTH_CLEARED_EVENT)))
    act(() => opciones.action.onClick())
    expect(window.location.hash).toBe('#/hoy')
    expect(dobles.dismiss).toHaveBeenCalledWith('aviso-1')
  })
})
