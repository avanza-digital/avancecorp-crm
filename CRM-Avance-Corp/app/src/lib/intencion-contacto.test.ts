// Coordinador de la intención de contacto (F1.1.1): una cola por pestaña que
// sobrevive al remount y a la recarga, no interrumpe un registro abierto y se
// vacía al salir de la cuenta.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook } from '@testing-library/react'

const T0 = Date.parse('2026-09-30T15:00:00Z')
const LLAVE = 'crm.intencion-contacto.v1'

/** Cada import es «otra carga de la página»: nueva identidad, misma sessionStorage. */
async function cargarPagina() {
  vi.resetModules()
  return await import('./intencion-contacto')
}

beforeEach(() => {
  sessionStorage.clear()
})

describe('coordinador de la intención de contacto', () => {
  it('arma, ofrece por actor y lead, y no la ofrece a otra cuenta ni a otro lead', async () => {
    const m = await cargarPagina()
    const i = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(i).toMatchObject({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla', numero: null, ts: T0, caduca: T0 + m.CADUCIDAD_MS, abierta: false })
    expect(m.intencionDe('v1', 'l1', T0)).toBe(i)
    expect(m.intencionDe('v1', undefined, T0)).toBe(i)
    expect(m.intencionDe('v2', 'l1', T0)).toBeNull()
    expect(m.intencionDe('v1', 'l2', T0)).toBeNull()
    expect(m.intencionDe(null, 'l1', T0)).toBeNull()
    expect(m.listarIntenciones('v1', T0)).toEqual([i])
  })

  it('un tap está listo a los 4 s; un enlace, de inmediato', async () => {
    const m = await cargarPagina()
    const tap = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(m.estaLista(tap, T0 + m.ESPERA_MS - 1)).toBe(false)
    expect(m.estaLista(tap, T0 + m.ESPERA_MS)).toBe(true)
    const enlace = m.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'enlace', numero: '+51999888777' }, T0)
    expect(m.estaLista(enlace, T0)).toBe(true)
    expect(enlace.numero).toBe('+51999888777')
  })

  it('reclamar la marca abierta una sola vez; cerrar la retira; cada cambio avisa', async () => {
    const m = await cargarPagina()
    const aviso = vi.fn()
    const dejar = m.suscribirIntenciones(aviso)
    const i = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(aviso).toHaveBeenCalledTimes(1)
    expect(m.reclamarIntencion(i.id, T0)).toBe(true)
    expect(aviso).toHaveBeenCalledTimes(2)
    expect(m.intencionDe('v1', 'l1', T0)).toMatchObject({ id: i.id, abierta: true })
    expect(m.reclamarIntencion(i.id, T0)).toBe(false)
    expect(m.reclamarIntencion('otra', T0)).toBe(false)
    expect(aviso).toHaveBeenCalledTimes(2)
    m.cerrarIntencion(i.id)
    expect(m.intencionDe('v1', 'l1', T0)).toBeNull()
    expect(aviso).toHaveBeenCalledTimes(3)
    m.cerrarIntencion(i.id) // ya no está: no avisa de nuevo
    expect(aviso).toHaveBeenCalledTimes(3)
    dejar()
    m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(aviso).toHaveBeenCalledTimes(3)
  })

  it('mientras la cabeza está abierta la siguiente espera sin ofrecerse; al cerrar pasa a cabeza', async () => {
    const m = await cargarPagina()
    const x = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(m.reclamarIntencion(x.id, T0)).toBe(true)
    const y = m.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'enlace', numero: '+51988877766' }, T0 + 1_000)
    expect(m.intencionDe('v1', 'l2', T0 + 1_000)).toBeNull()
    expect(m.intencionDe('v1', undefined, T0 + 1_000)).toMatchObject({ id: x.id, abierta: true })
    expect(m.reclamarIntencion(y.id, T0 + 1_000)).toBe(false)
    m.cerrarIntencion(x.id)
    expect(m.intencionDe('v1', 'l2', T0 + 1_000)).toBe(y)
    expect(m.listarIntenciones('v1', T0 + 1_000)).toEqual([y])
  })

  it('si la del lead ya está abierta, otra llamada al mismo lead no se encola: se devuelve la abierta sin avisar', async () => {
    const m = await cargarPagina()
    const aviso = vi.fn()
    m.suscribirIntenciones(aviso)
    const x = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    m.reclamarIntencion(x.id, T0)
    const avisos = aviso.mock.calls.length
    const otra = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', numero: '+51999888777' }, T0 + 5_000)
    expect(otra.id).toBe(x.id)
    expect(m.listarIntenciones('v1', T0 + 5_000)).toHaveLength(1)
    expect(aviso).toHaveBeenCalledTimes(avisos)
    // Otro lead sí espera detrás.
    m.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'enlace', numero: '+51988877766' }, T0 + 6_000)
    expect(m.listarIntenciones('v1', T0 + 6_000)).toHaveLength(2)
  })

  it('un segundo tap al mismo lead y canal renueva la pendiente en vez de duplicarla', async () => {
    const m = await cargarPagina()
    const a = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla', instancia: 'i1' }, T0)
    const b = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla', instancia: 'i2' }, T0 + 10_000)
    expect(b.id).not.toBe(a.id)
    expect(m.listarIntenciones('v1', T0 + 10_000)).toEqual([b])
    expect(m.intencionDe('v1', 'l1', T0 + 10_000)).toMatchObject({ ts: T0 + 10_000, instancia: 'i2' })
    // Otro canal al mismo lead es otro contacto.
    m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'wa', origen: 'pantalla' }, T0 + 11_000)
    expect(m.listarIntenciones('v1', T0 + 11_000)).toHaveLength(2)
  })

  it('cerrarIntencionesDe termina las del lead (abiertas o no) y deja pasar a la siguiente', async () => {
    const m = await cargarPagina()
    const aviso = vi.fn()
    m.suscribirIntenciones(aviso)
    const x = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    m.reclamarIntencion(x.id, T0)
    const y = m.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'enlace', numero: '+51999888777' }, T0)
    expect(m.intencionDe('v1', 'l2', T0)).toBeNull()
    m.cerrarIntencionesDe('v1', 'l1')
    expect(m.intencionDe('v1', 'l2', T0)).toBe(y)
    // Otro actor o un lead sin intenciones no tocan nada ni avisan.
    const avisos = aviso.mock.calls.length
    m.cerrarIntencionesDe('v2', 'l2')
    m.cerrarIntencionesDe('v1', 'l9')
    m.cerrarIntencionesDe(null, 'l2')
    expect(aviso).toHaveBeenCalledTimes(avisos)
    expect(m.intencionDe('v1', 'l2', T0)).toBe(y)
  })

  it('caduca: pasada su vigencia desaparece también del almacenamiento', async () => {
    const m = await cargarPagina()
    m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(sessionStorage.getItem(LLAVE)).not.toBeNull()
    expect(m.intencionDe('v1', 'l1', T0 + m.CADUCIDAD_MS - 1)).not.toBeNull()
    expect(m.intencionDe('v1', 'l1', T0 + m.CADUCIDAD_MS)).toBeNull()
    expect(m.listarIntenciones('v1', T0 + m.CADUCIDAD_MS)).toEqual([])
    expect(sessionStorage.getItem(LLAVE)).toBeNull()
  })

  it('sobrevive a la recarga de la página, y lo que la página anterior dejó abierto se vuelve a ofrecer', async () => {
    const antes = await cargarPagina()
    const i = antes.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', numero: '+51999888777' }, T0)
    expect(antes.reclamarIntencion(i.id, T0)).toBe(true)
    const despues = await cargarPagina()
    const j = despues.intencionDe('v1', 'l1', T0 + 1_000)
    expect(j).toMatchObject({ id: i.id, numero: '+51999888777', abierta: false })
    expect(j?.abiertaEn).toBeUndefined()
    expect(despues.reclamarIntencion(i.id, T0 + 1_000)).toBe(true)
    // La misma página que la abrió sí la ve abierta al releer.
    expect(despues.intencionDe('v1', 'l1', T0 + 1_000)).toMatchObject({ abierta: true })
  })

  // F4-b: el id de la llamada que mandó el celular viaja con la intención del enlace hasta la encuesta.
  it('guarda el id de la llamada del enlace, sobrevive a la recarga y no lo acepta de un tap ni sin la forma de la base', async () => {
    const antes = await cargarPagina()
    const i = antes.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', numero: '+51999888777', origenLlamada: 'C1-1790980958' }, T0)
    expect(i.origenLlamada).toBe('C1-1790980958')
    const despues = await cargarPagina()
    expect(despues.intencionDe('v1', 'l1', T0 + 1_000)).toMatchObject({ id: i.id, origenLlamada: 'C1-1790980958' })
    const tap = despues.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'pantalla', origenLlamada: 'C1-1790980958' }, T0)
    expect(tap.origenLlamada).toBeUndefined()
    const raro = despues.armarIntencion({ actor: 'v1', leadId: 'l3', canal: 'tel', origen: 'enlace', origenLlamada: 'C1-123' }, T0)
    expect(raro.origenLlamada).toBeUndefined()
    // Un id que no tiene la forma de la base en el almacenamiento invalida esa entrada (dato ajeno).
    sessionStorage.setItem(LLAVE, JSON.stringify([{ ...i, origenLlamada: '<script>' }]))
    const otra = await cargarPagina()
    expect(otra.listarIntenciones('v1', T0)).toEqual([])
  })

  it('la vía de la llamada viaja con su id: al colgar por defecto, «pestana» desde la pestaña; sin id no hay vía', async () => {
    const m = await cargarPagina()
    const colgar = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', origenLlamada: 'C1-1790980958' }, T0)
    expect(colgar).toMatchObject({ origenLlamada: 'C1-1790980958', viaLlamada: 'al_colgar' })
    const pestana = m.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'enlace', origenLlamada: 'C1-1790980959', viaLlamada: 'pestana' }, T0)
    expect(pestana.viaLlamada).toBe('pestana')
    const sinId = m.armarIntencion({ actor: 'v1', leadId: 'l3', canal: 'tel', origen: 'enlace', viaLlamada: 'pestana' }, T0)
    expect(sinId.viaLlamada).toBeUndefined()
    sessionStorage.setItem(LLAVE, JSON.stringify([{ ...colgar, viaLlamada: 'adivinada' }]))
    const otra = await cargarPagina()
    expect(otra.listarIntenciones('v1', T0)).toEqual([])
  })

  it('un dato corrupto o ajeno en el almacenamiento no rompe nada: se empieza limpio', async () => {
    sessionStorage.setItem(LLAVE, '{no es json')
    const m1 = await cargarPagina()
    expect(m1.intencionDe('v1', undefined, T0)).toBeNull()
    sessionStorage.setItem(LLAVE, JSON.stringify([{ id: 'x', actor: 'v1' }, { basura: true }]))
    const m2 = await cargarPagina()
    expect(m2.listarIntenciones('v1', T0)).toEqual([])
  })

  it('sin almacenamiento sigue funcionando en memoria', async () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('lleno') })
    const m = await cargarPagina()
    const i = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    expect(m.intencionDe('v1', 'l1', T0)).toBe(i)
    expect(m.reclamarIntencion(i.id, T0)).toBe(true)
  })

  it('salir de la cuenta vacía la cola y avisa', async () => {
    const m = await cargarPagina()
    const aviso = vi.fn()
    m.suscribirIntenciones(aviso)
    m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
    m.armarIntencion({ actor: 'v1', leadId: 'l2', canal: 'tel', origen: 'enlace', numero: '+51999888777' }, T0)
    m.limpiarIntencionesContacto()
    expect(m.intencionDe('v1', undefined, T0)).toBeNull()
    expect(m.listarIntenciones('v1', T0)).toEqual([])
    expect(sessionStorage.getItem(LLAVE)).toBeNull()
    expect(aviso).toHaveBeenCalledTimes(3)
  })

  it('el hook entrega la cabeza del lead y reacciona a los cambios', async () => {
    const m = await cargarPagina()
    const { result } = renderHook(() => m.useIntencionContacto('v1', 'l1'))
    expect(result.current).toBeNull()
    let id = ''
    act(() => { id = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', numero: '+51999888777' }).id })
    expect(result.current).toMatchObject({ id, abierta: false })
    act(() => { m.reclamarIntencion(id) })
    expect(result.current).toMatchObject({ id, abierta: true })
    act(() => { m.cerrarIntencion(id) })
    expect(result.current).toBeNull()
  })
})


it('el enlace al colgar completa la encuesta abierta por el tap y conserva su identidad al recargar', async () => {
  const m = await cargarPagina()
  const tap = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'pantalla' }, T0)
  m.reclamarIntencion(tap.id, T0)
  const completa = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', origenLlamada: 'C1-1790980958' }, T0 + 1000)
  expect(completa).toMatchObject({ id: tap.id, abierta: true, origenLlamada: 'C1-1790980958', viaLlamada: 'al_colgar' })
  const otra = m.armarIntencion({ actor: 'v1', leadId: 'l1', canal: 'tel', origen: 'enlace', origenLlamada: 'C1-1790980999' }, T0 + 2000)
  expect(otra.origenLlamada).toBe('C1-1790980958')
  const recarga = await cargarPagina()
  expect(recarga.intencionDe('v1', 'l1', T0 + 3000)).toMatchObject({ id: tap.id, origenLlamada: 'C1-1790980958' })
})
