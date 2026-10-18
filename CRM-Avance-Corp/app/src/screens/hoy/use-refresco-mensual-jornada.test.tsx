import { act, cleanup, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useRefrescoMensualJornada } from './use-refresco-mensual-jornada'

const pasar = async (ms = 300_000) => { await act(async () => { await vi.advanceTimersByTimeAsync(ms) }) }
beforeEach(() => { vi.useFakeTimers(); vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible') })
afterEach(() => { cleanup(); vi.useRealTimers() })

describe('actualización del resultado mensual con Hoy abierto', () => {
  it('refresca al entrar y cada cinco minutos con la función vigente; termina al desmontar', async () => {
    const primera = vi.fn(async () => {}), segunda = vi.fn(async () => {})
    const { rerender, unmount } = renderHook(({ recargar }) => useRefrescoMensualJornada({ actor: 's1', habilitado: true, recargar }), {
      initialProps: { recargar: primera },
    })
    await pasar(0)
    expect(primera).toHaveBeenCalledOnce()
    await pasar(299_999)
    expect(primera).toHaveBeenCalledOnce()
    await pasar(1)
    expect(primera).toHaveBeenCalledTimes(2)
    rerender({ recargar: segunda }); await pasar()
    expect(segunda).toHaveBeenCalledOnce()
    unmount(); await pasar()
    expect(segunda).toHaveBeenCalledOnce()
  })
  it('no consulta oculto, en demo/deshabilitado ni sin actor', async () => {
    const recargar = vi.fn(async () => {})
    const { rerender } = renderHook(({ actor, habilitado }: { actor: string | null; habilitado: boolean }) => useRefrescoMensualJornada({ actor, habilitado, recargar }), {
      initialProps: { actor: 's1' as string | null, habilitado: false },
    })
    await pasar()
    rerender({ actor: null, habilitado: true }); await pasar()
    rerender({ actor: 's1', habilitado: true })
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden'); await pasar()
    expect(recargar).not.toHaveBeenCalled()
  })
  it('no solapa solicitudes y vuelve a intentar en el siguiente intervalo tras un error', async () => {
    let terminar!: () => void
    const recargar = vi.fn().mockImplementationOnce(() => new Promise<void>(resolve => { terminar = resolve }))
      .mockRejectedValueOnce(new Error('Error registrado por la fuente')).mockResolvedValue(undefined)
    renderHook(() => useRefrescoMensualJornada({ actor: 's1', habilitado: true, recargar }))
    await pasar(); await pasar()
    expect(recargar).toHaveBeenCalledOnce()
    await act(async () => { terminar() })
    await pasar(); await pasar()
    expect(recargar).toHaveBeenCalledTimes(3)
  })
})

it('revalida al regresar al módulo y cancela un arranque que ya se desmontó', async () => {
  const recargar = vi.fn(async () => {})
  const montar = () => renderHook(() => useRefrescoMensualJornada({ actor: 's1', habilitado: true, recargar }))
  const anterior = montar(); await pasar(0)
  expect(recargar).toHaveBeenCalledOnce()
  anterior.unmount()
  const abandonado = montar(); abandonado.unmount(); await pasar(0)
  expect(recargar).toHaveBeenCalledOnce()
  montar(); await pasar(0)
  expect(recargar).toHaveBeenCalledTimes(2)
})
