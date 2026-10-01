// @vitest-environment node
// Las dos puertas del potencial contra un Supabase SIMULADO: qué viaja, qué se
// acepta de vuelta y cómo se traduce cada rechazo. El cliente supabase-js es el
// de verdad; lo simulado es la red.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { marcarPotencialLead, obtenerPotencialLeads } from './potencial-api'
import { POTENCIAL_APAGADO } from '@/lib/potencial'

const LEER = 'http://supabase.test/rest/v1/rpc/potencial_leads_fn'
const MARCAR = 'http://supabase.test/rest/v1/rpc/marcar_potencial_lead_fn'
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => { vi.spyOn(console, 'error').mockImplementation(() => {}) })

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`

function item(leadId: string, sobre: Record<string, unknown> = {}) {
  return {
    lead_id: leadId, nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella',
    marcado_en: '2026-09-29T15:00:00Z', dias_sin_gestion: 1, baja_a: 'tibio', baja_el: '2026-10-06',
    puede_marcar: true, ...sobre,
  }
}
const sinMarca = (leadId: string) => item(leadId, {
  nivel: null, origen: null, nivel_marcado: null, marcado_en: null, dias_sin_gestion: null, baja_a: null, baja_el: null,
})

describe('obtenerPotencialLeads', () => {
  it('pregunta por los ids en pantalla y devuelve un ítem por lead visible', async () => {
    let cuerpo: unknown
    server.use(http.post(LEER, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ version: 1, habilitada: true, items: [item(id(1)), sinMarca(id(2))] })
    }))
    const respuesta = await obtenerPotencialLeads([id(1), id(2), id(3)])
    expect(cuerpo).toEqual({ p_lead_ids: [id(1), id(2), id(3)] })
    expect(respuesta.habilitada).toBe(true)
    // id(3) no viajó: la persona no lo ve. No es un error.
    expect(respuesta.items.map((i) => [i.lead_id, i.nivel])).toEqual([[id(1), 'estrella'], [id(2), null]])
  })

  it('sin ids no llama al servidor', async () => {
    // Sin handler: una llamada rompería la prueba (onUnhandledRequest: 'error').
    await expect(obtenerPotencialLeads([])).resolves.toEqual(POTENCIAL_APAGADO)
  })

  it('parte en lotes de 200 en vez de recortar', async () => {
    const lotes: string[][] = []
    server.use(http.post(LEER, async ({ request }) => {
      const { p_lead_ids } = await request.json() as { p_lead_ids: string[] }
      lotes.push(p_lead_ids)
      return HttpResponse.json({ version: 1, habilitada: true, items: p_lead_ids.map((x) => sinMarca(x)) })
    }))
    const ids = Array.from({ length: 450 }, (_, i) => id(i))
    const respuesta = await obtenerPotencialLeads(ids)
    expect(lotes.map((l) => l.length).sort((a, b) => b - a)).toEqual([200, 200, 50])
    expect(new Set(lotes.flat())).toEqual(new Set(ids))
    expect(respuesta.items).toHaveLength(450)
  })

  it('si un lote ve la bandera apagada, el potencial está apagado', async () => {
    let llamada = 0
    server.use(http.post(LEER, async ({ request }) => {
      const { p_lead_ids } = await request.json() as { p_lead_ids: string[] }
      llamada += 1
      return HttpResponse.json(llamada === 1
        ? { version: 1, habilitada: true, items: p_lead_ids.map((x) => sinMarca(x)) }
        : { version: 1, habilitada: false, items: [] })
    }))
    await expect(obtenerPotencialLeads(Array.from({ length: 201 }, (_, i) => id(i)))).resolves.toEqual(POTENCIAL_APAGADO)
  })

  it('bandera apagada: estado, no error', async () => {
    server.use(http.post(LEER, () => HttpResponse.json({ version: 1, habilitada: false, items: [] })))
    await expect(obtenerPotencialLeads([id(1)])).resolves.toEqual(POTENCIAL_APAGADO)
  })

  it('servidor sin la puerta todavía (PGRST202) = apagado', async () => {
    server.use(http.post(LEER, () => HttpResponse.json(
      { code: 'PGRST202', message: 'Could not find the function crm.potencial_leads_fn(p_lead_ids) in the schema cache', details: null, hint: null },
      { status: 404 },
    )))
    await expect(obtenerPotencialLeads([id(1)])).resolves.toEqual(POTENCIAL_APAGADO)
  })

  it.each([
    ['nulo', null],
    ['otra versión', { version: 2, habilitada: true, items: [] }],
    ['un nivel desconocido', { version: 1, habilitada: true, items: [item(id(1), { nivel: 'caliente' })] }],
    ['un lead que no se pidió', { version: 1, habilitada: true, items: [item(id(9))] }],
    ['un lead repetido', { version: 1, habilitada: true, items: [item(id(1)), item(id(1))] }],
  ])('rechaza un payload fuera de contrato: %s', async (_caso, payload) => {
    server.use(http.post(LEER, () => HttpResponse.json(payload)))
    await expect(obtenerPotencialLeads([id(1)])).rejects.toMatchObject({ code: 'POTENCIAL_CONTRACT' })
  })

  it('un rechazo del servidor es un error con su código, sin texto crudo', async () => {
    server.use(http.post(LEER, () => HttpResponse.json({ code: '42501', message: 'No autorizado' }, { status: 403 })))
    await expect(obtenerPotencialLeads([id(1)])).rejects.toMatchObject({
      code: '42501', message: 'No se pudo leer el potencial de los leads.',
    })
  })

  it('una consulta cancelada se cancela: no es un fallo', async () => {
    const control = new AbortController()
    control.abort()
    await expect(obtenerPotencialLeads([id(1)], control.signal)).rejects.toMatchObject({ name: 'AbortError' })
  })
})

describe('marcarPotencialLead', () => {
  it('manda el lead y el nivel a la puerta', async () => {
    let cuerpo: unknown
    server.use(http.post(MARCAR, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ lead_id: id(1), nivel: 'estrella', origen: 'manual', marcado_por: id(7), marcado_en: '2026-10-01T15:00:00Z' })
    }))
    await expect(marcarPotencialLead(id(1), 'estrella')).resolves.toBeUndefined()
    expect(cuerpo).toEqual({ p_lead_id: id(1), p_nivel: 'estrella' })
  })

  it.each([
    ['55000', 'La marca de potencial todavía no está activada', 'POTENCIAL_APAGADO', 'La marca de potencial todavía no está activada.'],
    ['42501', 'Solo el analista del lead o su supervisor pueden marcar su potencial', 'SIN_PERMISO', 'Solo el analista del lead o su supervisor pueden marcar su potencial.'],
    ['42501', 'permission denied for function marcar_potencial_lead_fn', 'SIN_PERMISO', 'Solo el analista del lead o su supervisor pueden marcar su potencial.'],
    ['P0002', 'Lead no encontrado o fuera de tu ámbito', 'FUERA_DE_AMBITO', 'Este lead ya no está a tu cargo. Actualiza la lista.'],
    ['22023', 'Un lead convertido o descartado no lleva marca de potencial', 'REGLA_SERVIDOR', 'Un lead convertido o descartado no lleva marca de potencial'],
    ['55P03', 'canceling statement due to lock timeout', 'REINTENTAR', 'Otra operación está usando este lead ahora mismo. Vuelve a intentarlo.'],
    ['XX000', 'internal error', 'POSTGREST_ERROR', 'No se pudo guardar la marca de potencial.'],
  ])('traduce el rechazo %s («%s»)', async (pg, textoServidor, codigo, mensaje) => {
    server.use(http.post(MARCAR, () => HttpResponse.json({ code: pg, message: textoServidor }, { status: 400 })))
    await expect(marcarPotencialLead(id(1), 'tibio')).rejects.toMatchObject({ code: codigo, message: mensaje })
  })

  it('sin respuesta del servidor no afirma que la marca falló', async () => {
    server.use(http.post(MARCAR, () => HttpResponse.error()))
    await expect(marcarPotencialLead(id(1), 'frio')).rejects.toMatchObject({ code: 'RESPUESTA_NO_RECIBIDA' })
  })
})
