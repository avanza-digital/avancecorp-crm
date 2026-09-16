// @vitest-environment node
// Cliente Supabase real contra HTTP simulado: solo la ausencia de la RPC de
// capacidad permite conservar la cartera anterior, siempre con F5 apagada.
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError } from './crm-api'
import { listarInversionistas, obtenerEstadoCarteraInversionistas } from './inversionistas-api'
import { FILTROS_INVERSIONISTAS_INICIALES } from '@/lib/inversionistas'
import {carteraF5, ACTOR_F5} from '@/test/fixtures/f5'

const RPC = 'http://supabase.test/rest/v1/rpc/cartera_inversionistas_estado_fn'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

it('RPC de capacidad ausente conserva la cartera anterior sin permitir escritura F5', async () => {
  server.use(http.post(RPC, () => HttpResponse.json({ code: 'PGRST202', message: 'RPC ausente' }, { status: 404 })))
  await expect(obtenerEstadoCarteraInversionistas(new AbortController().signal)).resolves.toEqual({
    version: 1, habilitada: false, escritura_habilitada: false, motivo: null,
  })
})

it.each([{ code: '42501', status: 403 }, { code: 'PGRST000', status: 503 }])(
  'el error $code no se disimula como F5 deshabilitada', async ({ code, status }) => {
    server.use(http.post(RPC, () => HttpResponse.json({ code, message: 'Consulta rechazada' }, { status })))
    const error = await obtenerEstadoCarteraInversionistas(new AbortController().signal).catch(e => e)
    expect(error).toBeInstanceOf(CrmApiError)
    expect(error).toMatchObject({ code })
  },
)

it('la ausencia de la RPC de listado sigue siendo un error', async () => {
  server.use(http.post('http://supabase.test/rest/v1/rpc/cartera_inversionistas_filtrada_fn', () =>
    HttpResponse.json({ code: 'PGRST202', message: 'RPC de listado ausente' }, { status: 404 })))
  await expect(listarInversionistas(FILTROS_INVERSIONISTAS_INICIALES, new AbortController().signal))
    .rejects.toMatchObject({ code: 'PGRST202' })
})

it('envía todos los filtros al servidor y exige respuesta v2 completa',async () => {
  let recibidos:unknown
  server.use(http.post('http://supabase.test/rest/v1/rpc/cartera_inversionistas_filtrada_fn',async ({request}) => {
    recibidos=await request.json()
    expect(request.headers.get('content-profile')).toBe('crm')
    return HttpResponse.json(carteraF5)
  }))
  const d=await listarInversionistas({...FILTROS_INVERSIONISTAS_INICIALES,empresa:'avance',mes:'2026-08',moneda:'USD',
    estado:'vigente',contacto:'no_contactar',responsable:ACTOR_F5,porVencer:true,texto:'  referencia  '},new AbortController().signal)
  expect(recibidos).toEqual({p_pagina:1,p_tamano:25,p_texto:'referencia',p_empresa:'avance',p_mes:'2026-08',p_moneda:'USD',
    p_estado:'vigente',p_contacto:'no_contactar',p_responsable:ACTOR_F5,p_sin_responsable:false,p_por_vencer:true})
  expect(d).toEqual(carteraF5)
})

it.each([{...carteraF5,version:1},{...carteraF5,opciones_meses:undefined},{...carteraF5,total:2},
  {...carteraF5,filas:[{...carteraF5.filas[0],resumen:undefined}]}])('rechaza respuesta que no acredita el contrato de filtros',async data => {
  server.use(http.post('http://supabase.test/rest/v1/rpc/cartera_inversionistas_filtrada_fn',() => HttpResponse.json(data)))
  await expect(listarInversionistas(FILTROS_INVERSIONISTAS_INICIALES,new AbortController().signal)).rejects.toMatchObject({code:'RESPUESTA_INCOMPLETA'})
})
