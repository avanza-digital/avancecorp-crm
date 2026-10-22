// @vitest-environment node
// Contrato HTTP de `crm.registro_actividad_v2_fn`: los ocho argumentos viajan con
// sus nombres y nulabilidad, la sonda pide limite+1, y una página que no
// corresponde a lo pedido (eco de desde/hasta/limite, o más filas que la sonda)
// NUNCA se pinta: se rechaza con GESTION_DIARIA_CONTRACT.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
// Bloque 2.16: el registro se espía para fijar que «deshacer una llamada» sigue sin registrar sus rechazos, como hoy.
vi.mock('@/lib/observabilidad', async (importActual) => ({
  ...await importActual<typeof import('@/lib/observabilidad')>(),
  registrarError: vi.fn(),
}))

import { registrarError } from '@/lib/observabilidad'
import { CrmApiError } from './crm-api'
import { deshacerResultadoLlamada, listarRegistroActividad } from './gestion-diaria-api'

const RPC = 'http://supabase.test/rest/v1/rpc/registro_actividad_v2_fn'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const FILTROS = { dia: '2026-09-19', analistaIds: ['u1'] as const, pestana: 'llamadas' as const, etapa: null }
const ITEM = {
  origen: 'lead', sujeto_tipo: 'lead', sujeto_id: 'l1', sujeto_nombre: 'LEAD UNO', identidad_visible: true, inversionista_id: null, perfil_id: null,
  id: 'a1', lead_id: 'l1', lead_nombre: 'LEAD UNO', lead_etapa: 'contactado', etapa_en_ese_momento: 'nuevo',
  tipo: 'llamada_realizada', detalle: 'Contestó', metadata: { resultado: 'volver_a_llamar' }, creado_por: 'u1',
  autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-19T15:01:00+00:00',
}
const pagina = (extra: Record<string, unknown> = {}) => ({
  version: 2, generado_en: '2026-09-19T18:00:00+00:00', desde: '2026-09-19', hasta: '2026-09-19', zona: 'America/Lima', limite: 26, items: [ITEM], ...extra,
})

describe('registro_actividad_v2_fn (msw)', () => {
  it('manda los argumentos presentes con la sonda limite+1 y devuelve la página validada', async () => {
    let cuerpo: Record<string, unknown> | null = null
    server.use(http.post(RPC, async ({ request }) => { cuerpo = (await request.json()) as Record<string, unknown>; return HttpResponse.json(pagina()) }))
    const r = await listarRegistroActividad(FILTROS, { antes_de: '2026-09-19T15:02:00Z', antes_id: 'a9' }, 25)
    // Sin etapa, `p_etapa` NO viaja: en el servidor vale NULL por defecto.
    expect(cuerpo).toEqual({
      p_desde: '2026-09-19', p_hasta: '2026-09-19', p_analista_ids: ['u1'], p_tipos: ['llamada_realizada', 'llamada_no_contestada'],
      p_limite: 26, p_antes_de: '2026-09-19T15:02:00Z', p_antes_id: 'a9', p_antes_origen: 'lead',
    })
    expect(r.items).toHaveLength(1)
    expect(r.items[0]?.metadata).toEqual({ resultado: 'volver_a_llamar' })
  })

  it('«todo» no manda tipos y sin cursor omite los opcionales (NULL por defecto en el servidor)', async () => {
    let cuerpo: Record<string, unknown> | null = null
    server.use(http.post(RPC, async ({ request }) => { cuerpo = (await request.json()) as Record<string, unknown>; return HttpResponse.json(pagina()) }))
    await listarRegistroActividad({ ...FILTROS, pestana: 'todo', analistaIds: null }, null, 25)
    expect(cuerpo).toEqual({ p_desde: '2026-09-19', p_hasta: '2026-09-19', p_limite: 26 })
  })

  it.each([
    ['eco de límite distinto', pagina({ limite: 50 })],
    ['eco de día distinto', pagina({ desde: '2026-09-18', hasta: '2026-09-18' })],
    ['más filas que la sonda', pagina({ items: Array.from({ length: 27 }, (_, i) => ({ ...ITEM, id: `a${i}` })) })],
    ['tipo fuera del catálogo', pagina({ items: [{ ...ITEM, tipo: 'fax' }] })],
    ['zona que no es Lima', pagina({ zona: 'UTC' })],
  ])('rechaza %s con GESTION_DIARIA_CONTRACT', async (_n, payload) => {
    server.use(http.post(RPC, () => HttpResponse.json(payload)))
    await expect(listarRegistroActividad(FILTROS, null, 25)).rejects.toMatchObject({ code: 'GESTION_DIARIA_CONTRACT' })
  })

  it('un 42501 del servidor llega como CrmApiError con su código', async () => {
    server.use(http.post(RPC, () => HttpResponse.json({ code: '42501', message: 'Solo puedes filtrar por analistas activos de tu equipo', details: null, hint: null }, { status: 403 })))
    const error = await listarRegistroActividad(FILTROS, null, 25).catch((e: unknown) => e)
    expect(error).toBeInstanceOf(CrmApiError)
    expect((error as CrmApiError).code).toBe('42501')
  })
})

// Bloque 2.16 (D-62, D-69) — «Deshacer» un resultado de llamada revierte el descarte llamando a `crm.reabrir_lead_fn`: si el lead
// conserva el contacto de un cliente, el servidor rechaza el deshacer ENTERO con el `P0481` de reabrir y el veredicto del alta en
// el DETAIL. La pantalla lo presenta como el alta («Esta persona ya es cliente y está a cargo de X.», CONTACTO_NO_DISPONIBLE); el
// veto (`no_contactar`), un detalle ilegible y los demás errores siguen como hoy: el mensaje y el código del servidor, sin registro.
describe('deshacer_resultado_llamada (msw) — el P0481 con veredicto (bloque 2.16)', () => {
  const RPC_DESHACER = 'http://supabase.test/rest/v1/rpc/deshacer_resultado_llamada'
  const p0481 = (details: string | null) =>
    HttpResponse.json({ code: 'P0481', message: 'Contacto no disponible', details, hint: null }, { status: 400 })
  async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
    try {
      await p
    } catch (e) {
      if (e instanceof CrmApiError) return e
      throw e
    }
    throw new Error('no falló')
  }

  it('manda p_actividad_id y devuelve el deshacer validado (sin cambio)', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC_DESHACER, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ ok: true, actividad_id: 'a1', lead_id: 'l1', tarea_cancelada: true, descarte_revertido: true,
        cita_no_restaurada: false, ciclo_nuevo: false, etapa: 'nuevo' })
    }))
    await expect(deshacerResultadoLlamada('a1')).resolves.toMatchObject({ ok: true, descarte_revertido: true, etapa: 'nuevo' })
    expect(cuerpo).toEqual({ p_actividad_id: 'a1' })
  })

  it.each([
    ['ya_es_cliente con su asesor', { estado: 'ya_es_cliente', asesor: 'Ana' }, 'Esta persona ya es cliente y está a cargo de Ana.'],
    ['ya_es_cliente por identidad (via)', { estado: 'ya_es_cliente', asesor: 'Ana', via: 'identidad' },
      'Esta persona ya es cliente y está a cargo de Ana.'],
    ['ya_es_cliente «sin asesor asignado»', { estado: 'ya_es_cliente', asesor: 'sin asesor asignado' },
      'Esta persona ya es cliente de Avance Corp.'],
  ])('%s → el mensaje del alta y CONTACTO_NO_DISPONIBLE', async (_caso, veredicto, mensaje) => {
    server.use(http.post(RPC_DESHACER, () => p0481(JSON.stringify(veredicto))))
    const e = await fallo(deshacerResultadoLlamada('a1'))
    expect(e.message).toBe(mensaje)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).not.toHaveBeenCalled()
  })

  it.each([
    ['no_contactar', JSON.stringify({ estado: 'no_contactar' })],
    ['estado desconocido', JSON.stringify({ estado: 'ya_es_socio', asesor: 'Ana' })],
    ['ya_es_cliente sin asesor (fuera de contrato)', JSON.stringify({ estado: 'ya_es_cliente' })],
    ['detalle vacío', ''],
    ['sin detalle (null)', null],
    ['detalle que no es JSON', 'Key (telefono)=(+51911222333) ya es de Ana'],
  ])('%s → como hoy: el mensaje y el código del servidor', async (_caso, details) => {
    server.use(http.post(RPC_DESHACER, () => p0481(details)))
    const e = await fallo(deshacerResultadoLlamada('a1'))
    expect({ code: e.code, message: e.message }).toEqual({ code: 'P0481', message: 'Contacto no disponible' })
    expect(registrarError).not.toHaveBeenCalled()
  })

  it.each([
    ['22023 (más de 24 horas)', '22023', 'Solo puedes deshacer un resultado de las últimas 24 horas', 400],
    ['P0409 (la persona ya tiene su lead), aun con un veredicto en el detalle', 'P0409', 'La persona ya es cliente o ya tiene su lead: no se puede reabrir', 400],
    ['P0429 («No insistir»)', 'P0429', 'La persona tiene la restricción «No insistir»', 400],
    ['42501 (no es el autor)', '42501', 'Solo el autor puede deshacer este resultado', 403],
  ])('un error que no es P0481 sigue igual: %s', async (_caso, code, message, status) => {
    server.use(http.post(RPC_DESHACER, () => HttpResponse.json(
      { code, message, details: JSON.stringify({ estado: 'ya_es_cliente', asesor: 'Ana' }), hint: null }, { status })))
    const e = await fallo(deshacerResultadoLlamada('a1'))
    expect({ code: e.code, message: e.message }).toEqual({ code, message })
    expect(registrarError).not.toHaveBeenCalled()
  })
})
