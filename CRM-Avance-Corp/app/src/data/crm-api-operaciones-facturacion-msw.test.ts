// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { listarOperacionesFacturacion, parsearListaOperacionesFacturacion } from './crm-api'
import { operacion, oculta, respuesta } from '@/test/operaciones-facturacion'
const RPC = 'http://supabase.test/rest/v1/rpc/listar_operaciones_facturacion_v2_fn'
const servidor = setupServer()
beforeAll(() => servidor.listen({ onUnhandledRequest: 'error' }))
afterEach(() => servidor.resetHandlers())
afterAll(() => servidor.close())
const params = { p_desde: '2026-10-01', p_hasta: '2026-10-31', p_dias: ['2026-10-05'], p_analistas: ['ana'], p_sin_analista: false,
  p_equipo: 'sup', p_sin_equipo: false, p_tipos: ['contrato_nuevo', 'cooperativa'], p_moneda: 'PEN', p_pagina: 1, p_tamano: 25 }
describe('lista de operaciones: frontera HTTP y contrato entero', () => {
  it('envía todos los argumentos exactos al esquema crm, conserva la anulada y no añade ids a la enmascarada', async () => {
    let cuerpo: unknown
    let esquema: string | null = null
    const esperado = respuesta([{ ...operacion, anulado: true }, oculta])
    servidor.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json(); esquema = request.headers.get('content-profile')
      return HttpResponse.json(esperado)
    }))
    const lista = await listarOperacionesFacturacion(params)
    expect(cuerpo).toEqual(params); expect(esquema).toBe('crm')
    expect(lista).toEqual(esperado)
    expect(Object.keys(lista.filas[1]!)).toEqual(Object.keys(oculta))
    expect(lista.filas[1]).not.toHaveProperty('numero_contrato')
  })
  it('cooperativa visible con lead nulo y nombre disponible', () => {
    const coop = { ...oculta, n: 1, visible: true as const, tipo: 'cooperativa' as const, cliente_nombre: 'Ejemplo', estado: 'vigente', cierre_externo_id: 'cierre', cooperativa: 'Horizonte', lead_id: null }
    expect(parsearListaOperacionesFacturacion(respuesta([coop])).filas[0]).toEqual(coop)
  })
  it('v2 permite nombres de contratos y cooperativas sin permiso de ficha ni identificadores', async () => {
    const esperado = { ...respuesta([
      { ...oculta, n: 1, tipo: 'contrato_nuevo' as const, nombre_visible: true as const, cliente_nombre: 'Cliente del reporte' },
      { ...oculta, n: 2, nombre_visible: true as const, cliente_nombre: 'Cliente de cooperativa' },
      { ...oculta, n: 3, nombre_visible: true as const, cliente_nombre: null },
    ]), version: 2 as const }
    servidor.use(http.post(RPC, () => HttpResponse.json(esperado)))
    const lista = await listarOperacionesFacturacion(params)
    expect(lista).toEqual(esperado)
    for (const fila of lista.filas) {
      expect(fila.visible).toBe(false)
      for (const clave of ['cliente_id', 'contrato_id', 'numero_contrato', 'lead_id', 'cierre_externo_id', 'telefono', 'correo', 'dni']) {
        expect(fila).not.toHaveProperty(clave)
      }
    }
  })
  it.each([
    ['versión desconocida', { ...respuesta(), version: 3 }],
    ['fila incompleta', { ...respuesta(), filas: [{}] }],
    ['no es una lista', null],
    ['ids en fila oculta', respuesta([{ ...oculta, n: 1, numero_contrato: 'privado' } as typeof oculta])],
    ['nombre expuesto en fila oculta', respuesta([{ ...oculta, n: 1, cliente_nombre: 'No debe mostrarse' } as unknown as typeof oculta])],
    ['nombre de reporte en v1', { ...respuesta([{ ...oculta, n: 1, nombre_visible: true, cliente_nombre: 'Cliente del reporte' }]), version: 1 }],
    ['identificador en reporte v2', { ...respuesta([{ ...oculta, n: 1, nombre_visible: true, cliente_nombre: 'Cliente del reporte', cliente_id: 'privado' } as unknown as typeof oculta]), version: 2 }],
    ['contacto en reporte v2', { ...respuesta([{ ...oculta, n: 1, nombre_visible: true, cliente_nombre: 'Cliente del reporte', telefono: '+51999999999' } as unknown as typeof oculta]), version: 2 }],
    ['permiso de nombre falso', { ...respuesta([{ ...oculta, n: 1, nombre_visible: false, cliente_nombre: 'Cliente del reporte' } as unknown as typeof oculta]), version: 2 }],
    ['moneda ajena', { ...respuesta(), totales: [{ moneda: 'EUR', monto: 25000, operaciones: 1 }] }],
    ['número roto', { ...respuesta(), total: NaN }],
    ['hueco en numeración', respuesta([{ ...operacion, n: 2 }])],
    ['totales duplicados', { ...respuesta(), total: 2, totales: [...respuesta().totales, ...respuesta().totales] }],
    ['suma incorrecta', { ...respuesta(), totales: [{ moneda: 'PEN', monto: 1, operaciones: 1 }] }],
    ['página incompleta', { ...respuesta(), total: 2 }],
  ])('rechaza %s sin pintar datos a medias', (_caso, datos) => {
    expect(() => parsearListaOperacionesFacturacion(datos)).toThrow(/formato o una versión/)
  })
  it('mes sin operaciones', async () => {
    servidor.use(http.post(RPC, () => HttpResponse.json(respuesta([]))))
    expect(await listarOperacionesFacturacion(params)).toEqual(respuesta([]))
  })
  it('el endpoint v2 rechaza una respuesta de versión 1', async () => {
    servidor.use(http.post(RPC, () => HttpResponse.json({ ...respuesta(), version: 1 })))
    await expect(listarOperacionesFacturacion(params)).rejects.toThrow(/versión no compatible/)
  })
  it('el parser conserva el contrato v1 enmascarado', () => {
    const anterior = { ...respuesta([{ ...oculta, n: 1 }]), version: 1 }
    expect(parsearListaOperacionesFacturacion(anterior)).toEqual(anterior)
  })
  it.each(['22023', '42501', 'XX000'])('error %s en palabras', async (code) => {
    servidor.use(http.post(RPC, () => HttpResponse.json({ code, message: 'detalle SQL privado' }, { status: 400 })))
    await expect(listarOperacionesFacturacion(params)).rejects.toThrow(code === '22023' ? /31 días/ : /No se pudo cargar la lista/)
  })
  it('rechaza la página equivocada', async () => {
    servidor.use(http.post(RPC, () => HttpResponse.json({ ...respuesta([]), pagina: 2 })))
    await expect(listarOperacionesFacturacion(params)).rejects.toThrow(/página recibida/)
  })
})
