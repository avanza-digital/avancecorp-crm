import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake', { auth: { persistSession: false } }) }
})
import { ejecutarComandoSla, limpiarIntencionesSla, tareaConConfirmacionPendiente, listarPendientesSla, confirmarPendienteSla, hayLlamadaV3Pendiente } from './sla-operacion-comandos'
import type { Tarea } from '@/lib/tipos'

const servidor = setupServer()
const ruta = 'http://supabase.test/rest/v1/rpc/:comando'
const args = { p_lead_id: 'lead', p_tipo: 'llamada_realizada', p_detalle: 'Conversación' }
const ejecutar = () => ejecutarComandoSla('actor', 'registrar_actividad_v2', 'lead', args)
const recibo = (cuerpo: Record<string, unknown>) => HttpResponse.json({
  ok: true, version: 2, operacion_id: cuerpo.p_operacion_id, lead_id: 'lead',
  comando: 'registrar_actividad',
})
beforeAll(() => servidor.listen({ onUnhandledRequest: 'error' }))
beforeEach(() => sessionStorage.clear())
afterEach(() => { servidor.resetHandlers(); vi.restoreAllMocks(); vi.unstubAllGlobals() })
afterAll(() => servidor.close())

describe('recibos de gestiones SLA', () => {
  const entradaLlamada = { p_lead_id: 'lead', p_resultado: 'no_interesado', p_submotivo: 'otro', p_descartar: false }
  const sobreLlamada = (cuerpo: Record<string, unknown>) => ({
    ok: true, version: 2, operacion_id: cuerpo.p_operacion_id, lead_id: 'lead',
    comando: 'registrar_llamada', actividad_id: cuerpo.p_tarea_id ? 'actividad-cierre' : cuerpo.p_operacion_id,
    resultado: cuerpo.p_resultado, descartado: cuerpo.p_descartar === true, no_insista: cuerpo.p_no_insista === true,
    siguiente_id: cuerpo.p_siguiente ? 'siguiente' : null,
  })

  it('v4 recupera la respuesta perdida sin reinterpretar resultado ni descarte', async () => {
    const cuerpos: Record<string, unknown>[] = []
    servidor.use(http.post(ruta, async ({ request, params }) => {
      expect(params.comando).toBe('registrar_llamada_v4')
      const cuerpo = await request.json() as Record<string, unknown>; cuerpos.push(cuerpo)
      return cuerpos.length === 1 ? HttpResponse.error() : HttpResponse.json(sobreLlamada(cuerpo))
    }))
    const args = { ...entradaLlamada, p_siguiente: { tipo: 'tarea', titulo: 'Informar', vence_en: '2026-10-01T15:00:00Z' } }
    await expect(ejecutarComandoSla('actor', 'registrar_llamada_v4', 'lead', args)).rejects.toMatchObject({ code: 'SLA_CONFIRMACION_PENDIENTE' })
    const pendiente = listarPendientesSla('actor')[0]!
    expect(pendiente.comando).toBe('registrar_llamada_v4')
    await confirmarPendienteSla('actor', pendiente.operacion)
    expect(cuerpos[1]).toEqual(cuerpos[0])
    expect(listarPendientesSla('actor')).toEqual([])
  })

  it('un pendiente v3 bloquea v4 y se recupera con la puerta y el UUID originales', async () => {
    const cuerpos: Record<string, unknown>[] = []
    const puertas: unknown[] = []
    servidor.use(http.post(ruta, async ({ request, params }) => {
      const cuerpo = await request.json() as Record<string, unknown>
      cuerpos.push(cuerpo); puertas.push(params.comando)
      return cuerpos.length === 1 ? HttpResponse.error() : HttpResponse.json({
        ...sobreLlamada(cuerpo), descartado: params.comando === 'registrar_llamada_v3',
      })
    }))
    await expect(ejecutarComandoSla('actor', 'registrar_llamada_v3', 'lead', entradaLlamada)).rejects.toBeDefined()
    expect(hayLlamadaV3Pendiente('actor', 'lead')).toBe(true)
    expect(hayLlamadaV3Pendiente('otro', 'lead')).toBe(false)
    await expect(ejecutarComandoSla('actor', 'registrar_llamada_v4', 'lead', entradaLlamada)).rejects.toMatchObject({ code: 'SLA_CONFIRMACION_PENDIENTE' })
    expect(cuerpos).toHaveLength(1)
    await confirmarPendienteSla('actor', listarPendientesSla('actor')[0]!.operacion)
    expect(cuerpos[1]).toEqual(cuerpos[0])
    expect(hayLlamadaV3Pendiente('actor', 'lead')).toBe(false)
    await ejecutarComandoSla('actor', 'registrar_llamada_v4', 'lead', entradaLlamada)
    expect(puertas).toEqual(['registrar_llamada_v3', 'registrar_llamada_v3', 'registrar_llamada_v4'])
    expect(cuerpos[2]!.p_operacion_id).not.toBe(cuerpos[0]!.p_operacion_id)
  })

  it.each([
    { resultado: 'no_contesto' }, { descartado: true }, { no_insista: true },
    { actividad_id: 'otra' }, { siguiente_id: 'no-pedida' },
  ])('v4 conserva el recibo si HTTP 200 confirma efectos distintos: %j', async (parche) => {
    servidor.use(http.post(ruta, async ({ request }) => {
      const cuerpo = await request.json() as Record<string, unknown>
      return HttpResponse.json({ ...sobreLlamada(cuerpo), ...parche })
    }))
    await expect(ejecutarComandoSla('actor', 'registrar_llamada_v4', 'lead', entradaLlamada))
      .rejects.toMatchObject({ code: 'SLA_CONFIRMACION_PENDIENTE' })
    expect(listarPendientesSla('actor')).toHaveLength(1)
  })

  it('v4 mantiene protegida la tarea cerrada hasta confirmar', async () => {
    const tarea = { id: 'tarea', lead_id: 'lead', tipo: 'llamada', estado: 'pendiente', activo: true } as Tarea
    servidor.use(http.post(ruta, () => HttpResponse.error()))
    await expect(ejecutarComandoSla('actor', 'registrar_llamada_v4', 'lead', { ...entradaLlamada, p_tarea_id: tarea.id }, tarea)).rejects.toBeDefined()
    expect(tareaConConfirmacionPendiente('actor', 'tarea')).toEqual(tarea)
  })

  it('recupera una respuesta perdida con exactamente el mismo UUID y payload', async () => {
    const cuerpos: Record<string, unknown>[] = []
    servidor.use(http.post(ruta, async ({ request }) => {
      const cuerpo = await request.json() as Record<string, unknown>; cuerpos.push(cuerpo)
      expect(request.headers.get('content-profile')).toBe('crm')
      return cuerpos.length === 1 ? HttpResponse.error() : recibo(cuerpo)
    }))
    await expect(ejecutar()).rejects.toMatchObject({ code: 'SLA_CONFIRMACION_PENDIENTE' })
    expect(sessionStorage.length).toBe(1)
    await ejecutar()
    expect(cuerpos).toHaveLength(2)
    expect(cuerpos[1]).toEqual(cuerpos[0])
    expect(sessionStorage.length).toBe(0)
  })

  it('conserva IDs de siguiente tarea al regenerarse el espejo optimista', async () => {
    const cuerpos: Record<string, unknown>[] = []
    servidor.use(http.post(ruta, async ({ request }) => {
      const cuerpo = await request.json() as Record<string, unknown>; cuerpos.push(cuerpo)
      return cuerpos.length === 1 ? HttpResponse.error() : recibo(cuerpo)
    }))
    const siguiente = { id: 'primero', tipo: 'llamada', titulo: 'Seguimiento', vence_en: '2026-09-10T15:00:00Z' }
    await expect(ejecutarComandoSla('actor', 'registrar_actividad_v2', 'lead', { ...args, p_siguiente: siguiente })).rejects.toBeDefined()
    await ejecutarComandoSla('actor', 'registrar_actividad_v2', 'lead', { ...args, p_siguiente: { ...siguiente, id: 'nuevo' } })
    expect(cuerpos[1]).toEqual(cuerpos[0])
  })

  it('bloquea otro contenido mientras el resultado anterior sea incierto', async () => {
    const peticiones = vi.fn(() => HttpResponse.error())
    servidor.use(http.post(ruta, peticiones))
    await expect(ejecutar()).rejects.toBeDefined()
    await expect(ejecutarComandoSla('actor', 'registrar_actividad_v2', 'lead', { ...args, p_tipo: 'whatsapp_recibido' }))
      .rejects.toMatchObject({ code: 'SLA_CONFIRMACION_PENDIENTE' })
    expect(peticiones).toHaveBeenCalledTimes(1)
  })

  it('une dos clics simultáneos en una única petición', async () => {
    let liberar!: () => void
    const espera = new Promise<void>((r) => { liberar = r })
    const peticiones = vi.fn(async ({ request }: { request: Request }) => {
      const cuerpo = await request.json() as Record<string, unknown>
      await espera; return recibo(cuerpo)
    })
    servidor.use(http.post(ruta, peticiones))
    const uno = ejecutar(); const dos = ejecutar()
    liberar(); await Promise.all([uno, dos])
    expect(peticiones).toHaveBeenCalledTimes(1)
  })

  it('una gestión nueva después de confirmar recibe otro UUID', async () => {
    const ids: unknown[] = []
    servidor.use(http.post(ruta, async ({ request }) => {
      const cuerpo = await request.json() as Record<string, unknown>; ids.push(cuerpo.p_operacion_id)
      return recibo(cuerpo)
    }))
    await ejecutar(); await ejecutar()
    expect(new Set(ids).size).toBe(2)
  })

  it('no olvida el recibo si un reintento pierde permisos después de una respuesta incierta', async () => {
    let n = 0
    servidor.use(http.post(ruta, () => ++n === 1 ? HttpResponse.error()
      : HttpResponse.json({ code: '42501', message: 'Fuera de ámbito' }, { status: 403 })))
    await expect(ejecutar()).rejects.toBeDefined()
    const anterior = sessionStorage.getItem(sessionStorage.key(0)!)
    await expect(ejecutar()).rejects.toBeDefined()
    expect(sessionStorage.getItem(sessionStorage.key(0)!)).toEqual(anterior)
  })

  it('permite corregir un rechazo SQL confirmado del primer envío', async () => {
    servidor.use(http.post(ruta, () => HttpResponse.json({ code: '22023', message: 'Fecha inválida' }, { status: 400 })))
    await expect(ejecutar()).rejects.toMatchObject({ code: '22023' })
    expect(sessionStorage.length).toBe(0)
  })

  it('no envía nada si no puede guardar primero la identidad de la operación', async () => {
    const peticiones = vi.fn(() => HttpResponse.error())
    servidor.use(http.post(ruta, peticiones))
    vi.stubGlobal('sessionStorage', { getItem: () => null, setItem: () => { throw new Error('quota') } })
    await expect(ejecutar()).rejects.toMatchObject({ code: 'SLA_ALMACENAMIENTO' })
    expect(peticiones).not.toHaveBeenCalled()
  })

  it('exige confirmación del recibo correcto, no basta con HTTP 200', async () => {
    servidor.use(http.post(ruta, () => HttpResponse.json({ ok: true, version: 2, operacion_id: 'otro' })))
    await expect(ejecutar()).rejects.toMatchObject({ code: 'SLA_CONFIRMACION_PENDIENTE' })
    expect(sessionStorage.length).toBe(1)
  })

  it('recupera contexto de tarea solo para el actor original y lo limpia al salir', async () => {
    const tarea = { id: 'tarea', lead_id: 'lead', tipo: 'llamada', estado: 'pendiente', activo: true } as Tarea
    servidor.use(http.post(ruta, () => HttpResponse.error()))
    await expect(ejecutarComandoSla('actor', 'cerrar_tarea_v2', 'tarea', { p_tarea_id: 'tarea', p_estado: 'completada' }, tarea)).rejects.toBeDefined()
    expect(tareaConConfirmacionPendiente('actor', 'tarea')).toEqual(tarea)
    expect(tareaConConfirmacionPendiente('otro', 'tarea')).toBeUndefined()
    sessionStorage.setItem('otra-preferencia', 'sí')
    limpiarIntencionesSla()
    expect(tareaConConfirmacionPendiente('actor', 'tarea')).toBeUndefined()
    expect(sessionStorage.getItem('otra-preferencia')).toBe('sí')
  })

  it('permite confirmar explícitamente tras perder el formulario sin reconstruir el payload', async () => {
    const cuerpos: Record<string, unknown>[] = []
    servidor.use(http.post(ruta, async ({ request }) => {
      const cuerpo = await request.json() as Record<string, unknown>; cuerpos.push(cuerpo)
      return cuerpos.length === 1 ? HttpResponse.error() : recibo(cuerpo)
    }))
    await expect(ejecutar()).rejects.toBeDefined()
    const pendiente = listarPendientesSla('actor')[0]!
    expect(pendiente).toEqual({ operacion: cuerpos[0]!.p_operacion_id, comando: 'registrar_actividad_v2', enCurso: false })
    expect(listarPendientesSla('otro')).toEqual([])
    await expect(confirmarPendienteSla('otro', pendiente.operacion)).rejects.toMatchObject({ code: 'SLA_SIN_PENDIENTE' })
    await confirmarPendienteSla('actor', pendiente.operacion)
    expect(cuerpos[1]).toEqual(cuerpos[0])
    expect(listarPendientesSla('actor')).toEqual([])
  })

  it('salir y volver no reutiliza la promesa anterior ni pierde el vuelo nuevo', async () => {
    const liberadores: Array<() => void> = []
    const cuerpos: Record<string, unknown>[] = []
    servidor.use(http.post(ruta, async ({ request }) => {
      const cuerpo = await request.json() as Record<string, unknown>; cuerpos.push(cuerpo)
      await new Promise<void>((r) => liberadores.push(r))
      return recibo(cuerpo)
    }))
    const anterior = ejecutar()
    await vi.waitFor(() => expect(cuerpos).toHaveLength(1))
    limpiarIntencionesSla()
    const nuevo = ejecutarComandoSla('actor', 'registrar_actividad_v2', 'lead', { ...args, p_detalle: 'Otra gestión' })
    await vi.waitFor(() => expect(cuerpos).toHaveLength(2))
    expect(cuerpos[0]!.p_operacion_id).not.toBe(cuerpos[1]!.p_operacion_id)
    liberadores[0]!(); await anterior
    expect(listarPendientesSla('actor')).toEqual([{ operacion: cuerpos[1]!.p_operacion_id, comando: 'registrar_actividad_v2', enCurso: true }])
    liberadores[1]!(); await nuevo
    expect(listarPendientesSla('actor')).toEqual([])
  })
})
