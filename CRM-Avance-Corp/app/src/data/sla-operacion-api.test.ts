// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { cambiarModoSla, listarColaSla, obtenerEstadosSlaV2 } from './sla-operacion-api'
const server = setupServer()
const rpc = (nombre: string) => `http://supabase.test/rest/v1/rpc/${nombre}`
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
const filtros = { senal: 'revisiones' as const, etapa: 'contactado', analista_id: 'analista' }
const pagina = { version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-07T10:00:00Z',
  filtros, limite: 10, rango: { desde: 0, hasta: 0 }, total_items: 0, hay_mas: false, cursor_siguiente: null, items: [],
  totales: { primera_atencion: 4, tareas_vencidas: 9, seguimientos_pendientes: 2, revisiones: 0, datos_incompletos: 0, por_repartir: 0 } }
describe('contrato HTTP de lecturas SLA', () => {
  it('informa un conflicto de revisión P0409 sin repetir el cambio', async () => {
    const cambiar = vi.fn(() => HttpResponse.json({ code: 'P0409', message: 'Revisión obsoleta' }, { status: 409 }))
    server.use(http.post(rpc('cambiar_modo_sla_operacion'), cambiar))
    await expect(cambiarModoSla(1, 'activo')).rejects.toMatchObject({ code: 'P0409', message: expect.stringContaining('Revisa los valores actualizados') })
    expect(cambiar).toHaveBeenCalledTimes(1)
  })
  it('envía filtros, límite y cursor opaco sin reconstruirlo en el navegador', async () => {
    const cursor = { version: 1, contexto: 'opaco', prioridad: 10, referencia_en: null, lead_id: 'lead' }
    let cuerpo: unknown
    server.use(http.post(rpc('cola_accion_v2_fn'), async ({ request }) => {
      cuerpo = await request.json(); expect(request.headers.get('content-profile')).toBe('crm')
      return HttpResponse.json(pagina)
    }))
    const resultado = await listarColaSla(filtros, cursor, 10)
    expect(cuerpo).toEqual({ p_limite: 10, p_senal: 'revisiones', p_etapa: 'contactado', p_analista_id: 'analista', p_cursor: cursor })
    expect(resultado.totales.tareas_vencidas).toBe(9)
  })
  it.each([
    { filtros: { ...filtros, etapa: 'nuevo' } }, { limite: 25 }, { totales: {} }, { hay_mas: true, cursor_siguiente: null }, { version: 1 },
  ])('rechaza respuesta incompatible sin mostrar ceros: %j', async (cambio) => {
    server.use(http.post(rpc('cola_accion_v2_fn'), () => HttpResponse.json({ ...pagina, ...cambio })))
    await expect(listarColaSla(filtros, null, 10)).rejects.toMatchObject({ code: 'SLA_CONTRACT' })
  })
  it('conserva el error de cursor para reiniciar la página y no hace fallback a v1', async () => {
    server.use(http.post(rpc('cola_accion_v2_fn'), () => HttpResponse.json({ code: '22023', message: 'Cursor incompatible; reinicia la paginacion' }, { status: 400 })))
    await expect(listarColaSla(filtros, null, 10)).rejects.toMatchObject({ code: '22023' })
  })
  it('consulta el modo con lista vacía sin cargar cartera ni consultar v1', async () => {
    let cuerpo: unknown
    server.use(http.post(rpc('estado_sla_leads_v2_fn'), async ({ request }) => {
      cuerpo = await request.json(); return HttpResponse.json({ version: 2, modo: 'legado', control_revision: 0, calculado_en: '2026-09-07T10:00:00Z', filas: [] })
    }))
    expect((await obtenerEstadosSlaV2([])).modo).toBe('legado')
    expect(cuerpo).toEqual({ p_lead_ids: [] })
  })
})
