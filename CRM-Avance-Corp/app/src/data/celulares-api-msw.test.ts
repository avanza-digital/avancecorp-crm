// @vitest-environment node
// Celulares (F4-c): el cliente Supabase real contra HTTP simulado. Cada puerta manda exactamente sus argumentos, la
// respuesta se valida antes de usarse y los códigos del servidor (42501, 22023, 23505) llegan tal cual a la pantalla.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse, type JsonBodyType } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError } from './crm-api'
import {
  asignarCelular, cerrarAsignacionCelular, listarAsignacionesCelulares, listarSaludCelulares, rotarCredencialCelular,
} from './llamadas-celular-api'

const BASE = 'http://supabase.test/rest/v1/rpc/'
const ANALISTA = '11111111-1111-4111-8111-111111111111'
const ASIGNACION = '22222222-2222-4222-8222-222222222222'
const ANTERIOR = '33333333-3333-4333-8333-333333333333'
const HEX = '0123456789abcdef'.repeat(4)
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

function rpc(nombre: string, responder: (cuerpo: unknown) => JsonBodyType | Response, recibidos: unknown[] = []) {
  server.use(http.post(`${BASE}${nombre}`, async ({ request }) => {
    expect(request.headers.get('content-profile')).toBe('crm')
    const cuerpo = await request.json().catch(() => null)
    recibidos.push(cuerpo)
    const r = responder(cuerpo)
    return r instanceof Response ? r : HttpResponse.json(r)
  }))
  return recibidos
}

const salud = {
  asignacion_id: ASIGNACION, etiqueta: 'C1', analista_id: ANALISTA, analista_nombre: 'ANA TORRES', vigente_desde: '2026-10-07T13:00:00Z',
  estado_latido: 'al_dia', horas_sin_latido: 0, reloj_desfasado: false, version_macro: 'llamadas-v3', eventos_en_cola: 0,
}

describe('lecturas', () => {
  it('la salud llega sin horas exactas; una fila con la hora del latido no se usa', async () => {
    rpc('celulares_salud_fn', () => [salud])
    await expect(listarSaludCelulares()).resolves.toEqual([salud])
    server.resetHandlers()
    rpc('celulares_salud_fn', () => [{ ...salud, ultimo_latido_en: '2026-10-07T12:00:00Z' }])
    await expect(listarSaludCelulares()).rejects.toMatchObject({ code: 'CELULARES_CONTRACT' })
  })
  it('el historial llega sin el hash de la credencial', async () => {
    const fila = { asignacion_id: ANTERIOR, etiqueta: 'C1', analista_id: ANALISTA, analista_nombre: 'ANA TORRES',
      vigente_desde: '2026-09-29T13:00:00Z', vigente_hasta: '2026-10-07T13:00:00Z', motivo_cierre: 'rotacion' }
    rpc('celulares_asignaciones_fn', () => [fila])
    await expect(listarAsignacionesCelulares()).resolves.toEqual([fila])
    server.resetHandlers()
    rpc('celulares_asignaciones_fn', () => [{ ...fila, credencial_hash: 'x' }])
    await expect(listarAsignacionesCelulares()).rejects.toMatchObject({ code: 'CELULARES_CONTRACT' })
  })
  it('42501 llega con su código: la pantalla lo dice como falta de permiso', async () => {
    rpc('celulares_salud_fn', () => HttpResponse.json({ code: '42501', message: 'No autorizado' }, { status: 403 }))
    const e = await listarSaludCelulares().catch((x) => x)
    expect(e).toBeInstanceOf(CrmApiError)
    expect(e).toMatchObject({ code: '42501' })
  })
})

describe('asignar', () => {
  it('manda la etiqueta y el analista, y devuelve la clave una vez', async () => {
    const recibidos = rpc('asignar_celular', () => ({ asignacion_id: ASIGNACION, etiqueta: 'C2', analista_id: ANALISTA, credencial: HEX }))
    await expect(asignarCelular('C2', ANALISTA)).resolves.toEqual({ asignacion_id: ASIGNACION, etiqueta: 'C2', analista_id: ANALISTA, credencial: HEX })
    expect(recibidos).toEqual([{ p_etiqueta: 'C2', p_analista_id: ANALISTA }])
  })
  it('una clave que no es hexadecimal de 64, o de otro celular, no se entrega', async () => {
    rpc('asignar_celular', () => ({ asignacion_id: ASIGNACION, etiqueta: 'C2', analista_id: ANALISTA, credencial: 'demo' + 'a'.repeat(60) }))
    await expect(asignarCelular('C2', ANALISTA)).rejects.toMatchObject({ code: 'CELULARES_CONTRACT' })
    server.resetHandlers()
    rpc('asignar_celular', () => ({ asignacion_id: ASIGNACION, etiqueta: 'C9', analista_id: ANALISTA, credencial: HEX }))
    await expect(asignarCelular('C2', ANALISTA)).rejects.toMatchObject({ code: 'CELULARES_CONTRACT' })
  })
  it('23505 y 22023 pasan con el texto del servidor: la pantalla ofrece Rotar o explica', async () => {
    rpc('asignar_celular', () => HttpResponse.json({ code: '23505', message: 'C1 ya está asignado: ciérralo o rota su credencial' }, { status: 409 }))
    await expect(asignarCelular('C1', ANALISTA)).rejects.toMatchObject({ code: '23505', message: 'C1 ya está asignado: ciérralo o rota su credencial' })
    server.resetHandlers()
    rpc('asignar_celular', () => HttpResponse.json({ code: '22023', message: 'El celular se asigna a un analista o supervisor activo' }, { status: 400 }))
    await expect(asignarCelular('C1', ANALISTA)).rejects.toMatchObject({ code: '22023' })
  })
})

describe('rotar y cerrar', () => {
  it('rotar manda solo la etiqueta y devuelve la clave nueva con la asignación cerrada', async () => {
    const recibidos = rpc('rotar_credencial_celular', () => ({ asignacion_id: ASIGNACION, etiqueta: 'C1', analista_id: ANALISTA, credencial: HEX, anterior_id: ANTERIOR }))
    await expect(rotarCredencialCelular('C1')).resolves.toMatchObject({ credencial: HEX, anterior_id: ANTERIOR })
    expect(recibidos).toEqual([{ p_etiqueta: 'C1' }])
  })
  it('cerrar manda la asignación y el motivo, y exige que el servidor confirme la misma asignación', async () => {
    const recibidos = rpc('cerrar_asignacion_celular', () => ({ asignacion_id: ASIGNACION, repetido: false }))
    await expect(cerrarAsignacionCelular(ASIGNACION, 'extravio')).resolves.toBeUndefined()
    expect(recibidos).toEqual([{ p_asignacion_id: ASIGNACION, p_motivo: 'extravio' }])
    server.resetHandlers()
    rpc('cerrar_asignacion_celular', () => ({ asignacion_id: ANTERIOR, repetido: false }))
    await expect(cerrarAsignacionCelular(ASIGNACION, 'otro')).rejects.toMatchObject({ code: 'CELULARES_CONTRACT' })
  })
})
