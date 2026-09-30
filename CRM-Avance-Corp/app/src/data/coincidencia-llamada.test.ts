// Qué se le pide al servidor por el número del celular y cómo se lee lo que
// devuelve (F1.3.2): dígitos nacionales, página grande para saber si se vio
// todo, error operativo separado de «sin coincidencia», y la demo sin servidor.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Lead } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({ buscar: vi.fn() }))
vi.mock('./crm-api', async () => ({
  ...await vi.importActual<typeof import('./crm-api')>('./crm-api'),
  buscarLeadsGlobal: (...args: unknown[]) => dobles.buscar(...args),
}))
const { CrmApiError } = await import('./crm-api')
const { buscarLeadsManual, resolverNumeroLlamada, TOPE_BUSQUEDA_MANUAL, TOPE_CANDIDATOS } = await import('./coincidencia-llamada')

const lead = (id: string, telefono: string, extra: Partial<Lead> = {}): Lead =>
  ({ id, nombre_completo: `LEAD ${id}`, telefono, telefono_alternativo: null, etapa: 'nuevo', activo: true, vendedor_id: 'v1', dni: null, ...extra }) as unknown as Lead

beforeEach(() => {
  dobles.buscar.mockResolvedValue([])
})

describe('resolverNumeroLlamada', () => {
  it('pide los dígitos NACIONALES con la página grande y clasifica lo que vuelve', async () => {
    dobles.buscar.mockResolvedValue([lead('L1', '+51999888777')])
    const control = new AbortController()
    const r = await resolverNumeroLlamada('+51 999 888 777', { demo: false, leadsLocales: [], signal: control.signal })
    expect(dobles.buscar).toHaveBeenCalledWith('999888777', control.signal, TOPE_CANDIDATOS)
    expect(r).toMatchObject({ estado: 'unico', lead: { id: 'L1' }, numero: '+51999888777' })
  })

  it('un fijo se pide sin el 0 y sin el 51, para que salgan las dos formas guardadas', async () => {
    dobles.buscar.mockResolvedValue([lead('L3', '+51014457890')])
    const r = await resolverNumeroLlamada('014457890', { demo: false, leadsLocales: [] })
    expect(dobles.buscar).toHaveBeenCalledWith('14457890', undefined, TOPE_CANDIDATOS)
    expect(r).toMatchObject({ estado: 'unico', lead: { id: 'L3' } })
  })

  it('una página llena no demuestra unicidad: incompleto', async () => {
    const pagina = [lead('L1', '+51999888777'), ...Array.from({ length: TOPE_CANDIDATOS - 1 }, (_, i) => lead(`P${i}`, `+519998887${String(i).padStart(3, '0')}`))]
    dobles.buscar.mockResolvedValue(pagina)
    expect(await resolverNumeroLlamada('999888777', { demo: false, leadsLocales: [] })).toMatchObject({ estado: 'incompleto', leads: [{ id: 'L1' }] })
  })

  it('sin dígitos suficientes no consulta: inválido', async () => {
    expect(await resolverNumeroLlamada('12', { demo: false, leadsLocales: [] })).toEqual({ estado: 'invalido', numero: '+12' })
    expect(dobles.buscar).not.toHaveBeenCalled()
  })

  it('un fallo del servidor es error operativo con su mensaje, no «sin coincidencia»', async () => {
    dobles.buscar.mockRejectedValue(new CrmApiError('Tu cuenta no tiene acceso a la cartera del CRM.', '42501'))
    expect(await resolverNumeroLlamada('999888777', { demo: false, leadsLocales: [] })).toEqual({
      estado: 'error', numero: '+51999888777', mensaje: 'Tu cuenta no tiene acceso a la cartera del CRM.',
    })
    dobles.buscar.mockRejectedValue(new TypeError('Failed to fetch'))
    expect(await resolverNumeroLlamada('999888777', { demo: false, leadsLocales: [] })).toMatchObject({ estado: 'error', mensaje: 'No se pudo buscar el número en tus leads. Revisa tu conexión.' })
  })

  it('una consulta abortada no se disfraza de error: se propaga', async () => {
    const control = new AbortController()
    dobles.buscar.mockImplementation(async () => { control.abort(); throw new DOMException('abortada', 'AbortError') })
    await expect(resolverNumeroLlamada('999888777', { demo: false, leadsLocales: [], signal: control.signal })).rejects.toThrow('abortada')
  })

  it('en la demo compara contra el ámbito local sin tocar el servidor', async () => {
    const locales = [lead('D1', '+51999888777'), lead('D2', '+51911111111')]
    expect(await resolverNumeroLlamada('999888777', { demo: true, leadsLocales: locales })).toMatchObject({ estado: 'unico', lead: { id: 'D1' } })
    expect(dobles.buscar).not.toHaveBeenCalled()
  })
})

describe('buscarLeadsManual', () => {
  it('usa la misma puerta que la barra, con su tope, y no consulta por debajo del mínimo', async () => {
    dobles.buscar.mockResolvedValue([lead('L1', '+51999888777')])
    expect(await buscarLeadsManual('maría', { demo: false, leadsLocales: [] })).toHaveLength(1)
    expect(dobles.buscar).toHaveBeenCalledWith('maría', undefined, TOPE_BUSQUEDA_MANUAL)
    expect(await buscarLeadsManual('m', { demo: false, leadsLocales: [] })).toEqual([])
    expect(dobles.buscar).toHaveBeenCalledTimes(1)
  })

  it('en la demo filtra el ámbito local por nombre o dígitos, solo activos', async () => {
    const locales = [lead('D1', '+51999888777'), lead('D2', '+51911111111', { nombre_completo: 'ROSA MARÍA' }), lead('D3', '+51999888000', { activo: false })]
    expect((await buscarLeadsManual('999888', { demo: true, leadsLocales: locales })).map((l) => l.id)).toEqual(['D1'])
    expect((await buscarLeadsManual('rosa', { demo: true, leadsLocales: locales })).map((l) => l.id)).toEqual(['D2'])
    expect(dobles.buscar).not.toHaveBeenCalled()
  })
})
