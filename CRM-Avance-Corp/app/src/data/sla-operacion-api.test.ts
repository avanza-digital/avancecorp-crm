// @vitest-environment node
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
import { cambiarModoSla, listarColaDia, obtenerEstadosSlaV2 } from './sla-operacion-api'
const server = setupServer()
const rpc = (nombre: string) => `http://supabase.test/rest/v1/rpc/${nombre}`
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
const filtros = { senal: 'revisiones' as const, etapa: 'contactado', analista_id: 'analista' }
const pagina = { version: 3, modo: 'activo', control_revision: 1, calculado_en: '2026-09-07T10:00:00Z',
  filtros, limite: 10, rango: { desde: 0, hasta: 0 }, total_items: 0, hay_mas: false, cursor_siguiente: null, items: [],
  totales: { pendientes: 9, primera_atencion: 4, tareas_vencidas: 9, seguimientos_pendientes: 2, revisiones: 0, datos_incompletos: 0, por_repartir: 0, clientes: 0 } }
describe('contrato HTTP de lecturas SLA', () => {
  it('informa un conflicto de revisión P0409 sin repetir el cambio', async () => {
    const cambiar = vi.fn(() => HttpResponse.json({ code: 'P0409', message: 'Revisión obsoleta' }, { status: 409 }))
    server.use(http.post(rpc('cambiar_modo_sla_operacion'), cambiar))
    await expect(cambiarModoSla(1, 'activo')).rejects.toMatchObject({ code: 'P0409', message: expect.stringContaining('Revisa los valores actualizados') })
    expect(cambiar).toHaveBeenCalledTimes(1)
  })
  it('envía filtros, límite y cursor opaco a la v3 sin reconstruirlo en el navegador (Seguimiento comercial)', async () => {
    const cursor = { version: 2, contexto: 'opaco', prioridad: 10, referencia_en: null, clave: 'lead:lead' }
    let cuerpo: unknown
    server.use(http.post(rpc('cola_accion_v3_fn'), async ({ request }) => {
      cuerpo = await request.json(); expect(request.headers.get('content-profile')).toBe('crm')
      return HttpResponse.json(pagina)
    }))
    const resultado = await listarColaDia(filtros, cursor, 10)
    expect(cuerpo).toEqual({ p_limite: 10, p_senal: 'revisiones', p_etapa: 'contactado', p_analista_id: 'analista', p_cursor: cursor })
    expect(resultado.totales.tareas_vencidas).toBe(9)
  })
  it.each([
    { filtros: { ...filtros, etapa: 'nuevo' } }, { limite: 25 }, { totales: {} }, { hay_mas: true, cursor_siguiente: null }, { version: 2 },
  ])('rechaza respuesta incompatible sin mostrar ceros: %j', async (cambio) => {
    server.use(http.post(rpc('cola_accion_v3_fn'), () => HttpResponse.json({ ...pagina, ...cambio })))
    await expect(listarColaDia(filtros, null, 10)).rejects.toMatchObject({ code: 'SLA_CONTRACT' })
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

// Cola del DÍA v3 (`cola_accion_v3_fn`): leads + tareas de clientes, clave tipada.
const T1 = '11111111-1111-4111-8111-111111111111'
const T2 = '22222222-2222-4222-8222-222222222222'
const senalesCliente = (vencida: boolean) => ({ pendientes: vencida, tareas_vencidas: vencida, primera_atencion: false,
  seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false })
const itemCliente = (tarea: string, bucket: 'tarea_vencida' | 'tarea_hoy', extra: Record<string, unknown> = {}) => ({
  clave: `tarea:${tarea}`, tarea_id: tarea, lead_id: null, lead: null, estado: null, bucket,
  severidad: bucket === 'tarea_vencida' ? 'critica' : 'media', prioridad: bucket === 'tarea_vencida' ? 20 : 30,
  referencia_en: '2026-09-29T15:00:00Z', senales: senalesCliente(bucket === 'tarea_vencida'),
  sujeto: { tipo: 'cliente', perfil_id: null, inversionista_id: 'inv-1', nombre: 'ROSA CLIENTE' }, ...extra,
})
const todas = { senal: 'todas' as const, etapa: null, analista_id: null }
const paginaDia = { ...pagina, version: 3, filtros: todas, limite: 100, total_items: 2, rango: { desde: 1, hasta: 2 },
  totales: { ...pagina.totales, clientes: 2 }, items: [itemCliente(T1, 'tarea_vencida'), itemCliente(T2, 'tarea_hoy')] }
describe('contrato HTTP de la cola del día v3', () => {
  it('llama a la v3 (nunca a la v2) con los filtros del día y acepta las tareas de clientes', async () => {
    let cuerpo: unknown
    server.use(http.post(rpc('cola_accion_v3_fn'), async ({ request }) => {
      cuerpo = await request.json(); expect(request.headers.get('content-profile')).toBe('crm')
      return HttpResponse.json(paginaDia)
    }))
    const resultado = await listarColaDia(todas, null, 100)
    // Opcionales nulos OMITIDOS: el servidor los toma como NULL por defecto.
    expect(cuerpo).toEqual({ p_limite: 100, p_senal: 'todas', p_cursor: null })
    expect(resultado.items.map((i) => i.clave)).toEqual([`tarea:${T1}`, `tarea:${T2}`])
    expect(resultado.totales.clientes).toBe(2)
  })
  it.each([
    ['versión de la v2', { version: 2 }],
    ['sin totales.clientes', { totales: { pendientes: 9, primera_atencion: 4, tareas_vencidas: 9, seguimientos_pendientes: 2, revisiones: 0, datos_incompletos: 0, por_repartir: 0 } }],
    ['claves repetidas', { items: [itemCliente(T1, 'tarea_vencida'), itemCliente(T1, 'tarea_vencida')] }],
    ['clave que no es la de su tarea', { items: [itemCliente(T1, 'tarea_vencida', { clave: `tarea:${T2}` })] }],
    ['cliente con dos sujetos', { items: [itemCliente(T1, 'tarea_hoy', { sujeto: { tipo: 'cliente', perfil_id: 'p', inversionista_id: 'i', nombre: 'X' } })] }],
    ['cliente sin sujeto', { items: [itemCliente(T1, 'tarea_hoy', { sujeto: { tipo: 'cliente', perfil_id: null, inversionista_id: null, nombre: 'X' } })] }],
    ['cliente con un bucket de lead', { items: [itemCliente(T1, 'tarea_hoy', { bucket: 'primera_atencion' })] }],
    ['vencida que no es crítica', { items: [itemCliente(T1, 'tarea_vencida', { severidad: 'media' })] }],
    ['de hoy marcada pendiente', { items: [itemCliente(T1, 'tarea_hoy', { senales: senalesCliente(true) })] }],
    ['cliente con teléfono y lead', { items: [itemCliente(T1, 'tarea_hoy', { lead_id: 'l1' })] }],
    ['cliente sin fecha', { items: [itemCliente(T1, 'tarea_hoy', { referencia_en: 'mañana' })] }],
    ['lead sin clave', { items: [{ ...itemCliente(T1, 'tarea_hoy'), clave: undefined }] }],
    ['eco de filtros distinto', { filtros: { ...todas, etapa: 'nuevo' } }],
    ['hay_mas sin cursor', { hay_mas: true, cursor_siguiente: null }],
  ])('rechaza la página sin pintar nada: %s', async (_caso, cambio) => {
    server.use(http.post(rpc('cola_accion_v3_fn'), () => HttpResponse.json({ ...paginaDia, ...cambio })))
    await expect(listarColaDia(todas, null, 100)).rejects.toMatchObject({ code: 'SLA_CONTRACT' })
  })
  it('conserva el error del servidor (cursor de la v2 rechazado → 22023)', async () => {
    server.use(http.post(rpc('cola_accion_v3_fn'), () => HttpResponse.json({ code: '22023', message: 'Cursor SLA invalido' }, { status: 400 })))
    await expect(listarColaDia(todas, { version: 1 }, 100)).rejects.toMatchObject({ code: '22023' })
  })
})
