// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { createClient } from '@supabase/supabase-js'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import type { Database } from '@/lib/database.types'
import type { Lead } from '@/lib/tipos'
import { conGestionVigente } from './gestion-vigente'

const cliente = createClient<Database>('http://gestion.test', 'anon-fake')
const RUTA = 'http://gestion.test/rest/v1/rpc/gestion_vigente_fn'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => { server.resetHandlers(); vi.restoreAllMocks() })
afterAll(() => server.close())
const lead = (n = 1, cambios: Partial<Lead> = {}): Lead => ({
  id: `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, '0')}`, nombre_completo: 'PERSONA SINTÉTICA',
  telefono: '999999999', etapa: 'nuevo', origen: 'landing', monto_estimado: 1000, moneda: 'PEN',
  vendedor_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', activo: true,
  creado_en: '2026-10-01T10:00:00Z', tenencia_desde: '2026-10-02T10:00:00.000123-05:00', ...cambios,
})
const item = (l: Lead, gestion_vigente = false) => ({ lead_id: l.id, vendedor_id: l.vendedor_id,
  tenencia_desde: l.tenencia_desde, gestion_vigente })
const respuesta = (items: unknown[]) => HttpResponse.json({ version: 1, items })

describe('gestión vigente por página', () => {
  it('consulta solo ids por RPC y compara la tenencia con precisión de microsegundos', async () => {
    server.use(http.post(RUTA, async ({ request }) => {
      expect(request.headers.get('content-profile')).toBe('crm')
      expect(await request.json()).toEqual({ p_lead_ids: [lead().id, lead(2).id] })
      return respuesta([{ ...item(lead(), true), tenencia_desde: '2026-10-02T15:00:00.000123+00:00' }, item(lead(2))])
    }))
    expect((await conGestionVigente(cliente, [lead(), lead(2)])).map((l) => l.gestion_vigente)).toEqual([true, false])
  })
  it('acota a 100 ids por petición sin descargar historiales', async () => {
    const leads = Array.from({ length: 101 }, (_, i) => lead(i))
    const lotes: number[] = []
    server.use(http.post(RUTA, async ({ request }) => {
      const { p_lead_ids: ids } = await request.json() as { p_lead_ids: string[] }
      lotes.push(ids.length)
      return respuesta(leads.filter((l) => ids.includes(l.id)).map((l) => item(l)))
    }))
    expect((await conGestionVigente(cliente, leads)).every((l) => l.gestion_vigente === false)).toBe(true)
    expect(lotes).toEqual([100, 1])
  })
  it.each(['ausente', 'titular', 'microsegundo', 'fecha inválida'])(
    'una lectura distinta de la página queda sin verificar: %s', async (caso) => {
      server.use(http.post(RUTA, () => respuesta(caso === 'ausente' ? [] : [{ ...item(lead(), true),
        ...(caso === 'titular' ? { vendedor_id: lead(2, { vendedor_id: 'otro' }).vendedor_id } : {}),
        ...(caso === 'microsegundo' ? { tenencia_desde: '2026-10-02T15:00:00.000124Z' } : {}),
        ...(caso === 'fecha inválida' ? { tenencia_desde: 'ayer' } : {}),
      }])))
      expect((await conGestionVigente(cliente, [lead()]))[0]?.gestion_vigente).toBeNull()
    })
  it.each(['caída', 'ajena', 'duplicada', 'contrato', 'versión'])('no inventa «Nuevo» cuando la lectura falla: %s', async (caso) => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    server.use(http.post(RUTA, () => {
      if (caso === 'caída') return HttpResponse.json({ message: 'no disponible' }, { status: 403 })
      if (caso === 'ajena') return respuesta([item(lead(2))])
      if (caso === 'duplicada') return respuesta([item(lead()), item(lead())])
      if (caso === 'versión') return HttpResponse.json({ version: 2, items: [] })
      return respuesta([{ ...item(lead()), gestion_vigente: null }])
    }))
    expect((await conGestionVigente(cliente, [lead()]))[0]?.gestion_vigente).toBeNull()
  })
  it('no consulta otras etapas, inactivos, sin titular o sin tenencia', async () => {
    const sinTenencia = lead(5)
    delete sinTenencia.tenencia_desde
    const filas = await conGestionVigente(cliente, [lead(1, { etapa: 'contactado' }), lead(2, { activo: false }),
      lead(3, { vendedor_id: null }), lead(4, { tenencia_desde: null }), sinTenencia])
    expect(filas.every((l) => l.gestion_vigente === false)).toBe(true)
    expect(await conGestionVigente(cliente, [])).toEqual([])
  })
  it('reutiliza la clasificación de la RPC cuando la página se pidió con filtro de gestión', async () => {
    expect((await conGestionVigente(cliente, [lead()], undefined, 'con_gestion'))[0]?.gestion_vigente).toBe(true)
    expect((await conGestionVigente(cliente, [lead()], undefined, 'sin_gestion'))[0]?.gestion_vigente).toBe(false)
  })
  it('no envía identificadores ni fechas corruptos', async () => {
    const filas = await conGestionVigente(cliente, [lead(1, { id: 'id,or()' }), lead(2, { tenencia_desde: 'ayer)' }),
      lead(3, { vendedor_id: 'vendedor)' })])
    expect(filas.every((l) => l.gestion_vigente === null)).toBe(true)
  })
  it('deduplica ids sin alterar el orden de salida', async () => {
    server.use(http.post(RUTA, async ({ request }) => {
      expect(await request.json()).toEqual({ p_lead_ids: [lead().id] })
      return respuesta([item(lead(), true)])
    }))
    expect((await conGestionVigente(cliente, [lead(), lead()])).map((l) => l.gestion_vigente)).toEqual([true, true])
  })
  it('propaga la cancelación sin servir un estado del actor anterior', async () => {
    const control = new AbortController()
    control.abort()
    await expect(conGestionVigente(cliente, [lead()], control.signal)).rejects.toMatchObject({ name: 'AbortError' })
  })
})
