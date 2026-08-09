// @vitest-environment node
// C1 — las 3 RPCs de reparto contra un Supabase SIMULADO con msw: contrato HTTP
// real (POST /rpc/*), coerción numeric string→number, descarte de filas fuera de
// contrato y — lo importante — el MAPEO DE ERRORES: el veto legal P0429 debe
// llegar al frontend como NO_INSISTA y jamás confundirse con SIN_PERMISO.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  descartarLead,
  deshacerDescarte,
  leadsPorRepartir,
  listarResumenReparto,
  repartirLead,
  supervisoresParaReparto,
} from './crm-api'
import { resumenRepartoDesdeCola } from '@/lib/resumen-reparto'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

const FILA_COLA = {
  id: 'lead-1',
  nombre_completo: 'ROSA QUISPE',
  distrito: 'Miraflores',
  origen: 'landing',
  categoria_interes: 'nuevo',
  monto_estimado: '30000.00',
  moneda: 'USD',
  creado_en: '2026-07-21T20:33:33Z',
}

describe('leadsPorRepartir (msw)', () => {
  it('coerciona el monto numeric string→number y conserva distrito null', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json([
          FILA_COLA,
          { ...FILA_COLA, id: 'lead-2', distrito: null, categoria_interes: null, monto_estimado: 4500, moneda: 'PEN' },
        ]),
      ),
    )

    const filas = await leadsPorRepartir()

    expect(filas).toHaveLength(2)
    expect(filas[0]).toMatchObject({ id: 'lead-1', monto_estimado: 30000, moneda: 'USD' })
    expect(filas[1]).toMatchObject({ distrito: null, categoria_interes: null, monto_estimado: 4500 })
  })

  it('descarta filas fuera de contrato sin tumbar las válidas', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json([
          { ...FILA_COLA, id: 'zombie', moneda: 'EUR' },
          { ...FILA_COLA, id: 'buena' },
        ]),
      ),
    )

    const filas = await leadsPorRepartir()

    expect(filas).toHaveLength(1)
    expect(filas[0]?.id).toBe('buena')
  })

  // C1-bis — contrato v2: la marca del clasificador y el comentario redactado
  // viajan; una RPC v1 (sin esas claves) degrada a null en vez de tumbar filas.
  it('v2: proyecta clasificacion_auto y comentario; sin ellas degrada a null', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json([
          {
            ...FILA_COLA,
            clasificacion_auto: 'posible_credito',
            comentario: 'Quiero un [teléfono oculto] préstamo urgente',
          },
          { ...FILA_COLA, id: 'lead-v1' }, // RPC vieja: sin claves nuevas
          { ...FILA_COLA, id: 'lead-limpio', clasificacion_auto: null, comentario: null },
        ]),
      ),
    )

    const filas = await leadsPorRepartir()

    expect(filas).toHaveLength(3)
    expect(filas[0]).toMatchObject({
      clasificacion_auto: 'posible_credito',
      comentario: 'Quiero un [teléfono oculto] préstamo urgente',
    })
    expect(filas[1]).toMatchObject({ id: 'lead-v1', clasificacion_auto: null, comentario: null })
    expect(filas[2]).toMatchObject({ id: 'lead-limpio', clasificacion_auto: null, comentario: null })
  })

  it('un rechazo de permisos sube como CrmApiError', async () => {
    server.use(
      http.post(RPC('leads_por_repartir'), () =>
        HttpResponse.json({ code: '42501', message: 'Solo el coordinador puede ver la cola' }, { status: 403 }),
      ),
    )

    await expect(leadsPorRepartir()).rejects.toBeInstanceOf(CrmApiError)
  })
})

describe('supervisoresParaReparto (msw)', () => {
  it('devuelve destinos con el conteo de bandeja coercionado', async () => {
    server.use(
      http.post(RPC('supervisores_para_reparto'), () =>
        HttpResponse.json([
          { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: '3' },
          { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
        ]),
      ),
    )

    const filas = await supervisoresParaReparto()

    expect(filas).toEqual([
      { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 3 },
      { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
    ])
  })
})

describe('repartirLead (msw) — mapeo de errores del servidor', () => {
  it('manda los parámetros con el nombre exacto de la RPC', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('repartir_lead'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ lead_id: 'lead-1', asignado_supervisor_id: 'sup-1' })
      }),
    )

    await repartirLead('lead-1', 'sup-1')

    expect(cuerpo).toEqual({ p_lead: 'lead-1', p_supervisor: 'sup-1' })
  })

  it.each([
    ['P0429', 'NO_INSISTA', 'Lead marcado No Insista (Ley 29571): no se puede repartir'],
    ['P0002', 'FUERA_DE_COLA', 'El lead ya no está en la cola por repartir'],
    ['40001', 'REINTENTAR', 'conflicto de serializacion'],
    ['42501', 'SIN_PERMISO', 'permission denied'],
    ['22023', 'REGLA_SERVIDOR', 'La bandeja destino no pertenece a un supervisor activo'],
    ['P0001', 'REGLA_SERVIDOR', 'La bandeja destino no pertenece a un supervisor activo'],
  ])('el SQLSTATE %s se traduce a %s', async (pg, code, message) => {
    server.use(
      http.post(RPC('repartir_lead'), () =>
        HttpResponse.json({ code: pg, message }, { status: 400 }),
      ),
    )

    await expect(repartirLead('lead-1', 'sup-1')).rejects.toMatchObject({ code })
  })

  it('el veto legal NUNCA se degrada a SIN_PERMISO (candado del contrato)', async () => {
    // Si alguien cambiara el errcode del servidor a 42501, este test seguiría
    // pasando — por eso el candado REAL vive en el gate RLS (código exacto
    // P0429 + oráculo de estado). Aquí se fija el lado del cliente: mientras
    // llegue P0429, el mensaje legal se surfacea tal cual y no como permisos.
    server.use(
      http.post(RPC('repartir_lead'), () =>
        HttpResponse.json(
          { code: 'P0429', message: 'Lead marcado No Insista (Ley 29571): no se puede repartir' },
          { status: 400 },
        ),
      ),
    )

    await expect(repartirLead('lead-1', 'sup-1')).rejects.toMatchObject({
      code: 'NO_INSISTA',
      message: 'Lead marcado No Insista (Ley 29571): no se puede repartir',
    })
  })
})

// ── C1-bis: descartar y deshacer (msw) ───────────────────────────────────────
describe('descartarLead (msw)', () => {
  it('manda p_lead y p_motivo exactos, y OMITE p_nota cuando no hay nota', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('descartar_lead'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ lead_id: 'lead-1', motivo_descarte: 'pide_credito', ya_estaba: false })
      }),
    )

    await descartarLead('lead-1', 'pide_credito')

    expect(cuerpo).toEqual({ p_lead: 'lead-1', p_motivo: 'pide_credito' })
  })

  it('la nota viaja recortada como p_nota cuando existe', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('descartar_lead'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ ya_estaba: false })
      }),
    )

    await descartarLead('lead-1', 'otro', '  confirmado por teléfono  ')

    expect(cuerpo).toEqual({
      p_lead: 'lead-1',
      p_motivo: 'otro',
      p_nota: 'confirmado por teléfono',
    })
  })

  it.each([
    ['P0002', 'FUERA_DE_COLA', 'El lead ya fue descartado con otro motivo o por otra persona'],
    ['22023', 'REGLA_SERVIDOR', 'Motivo de descarte inválido'],
    ['42501', 'SIN_PERMISO', 'permission denied'],
    ['40001', 'REINTENTAR', 'conflicto de serializacion'],
  ])('el SQLSTATE %s se traduce a %s', async (pg, code, message) => {
    server.use(
      http.post(RPC('descartar_lead'), () =>
        HttpResponse.json({ code: pg, message }, { status: 400 }),
      ),
    )

    await expect(descartarLead('lead-1', 'sin_interes')).rejects.toMatchObject({ code })
  })
})

describe('deshacerDescarte (msw)', () => {
  it('manda p_lead exacto', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('deshacer_descarte'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ lead_id: 'lead-1', etapa: 'nuevo', ciclo_actual: 2 })
      }),
    )

    await deshacerDescarte('lead-1')

    expect(cuerpo).toEqual({ p_lead: 'lead-1' })
  })

  it('fuera de ventana o ajeno sube como FUERA_DE_COLA (P0002)', async () => {
    server.use(
      http.post(RPC('deshacer_descarte'), () =>
        HttpResponse.json(
          { code: 'P0002', message: 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño' },
          { status: 400 },
        ),
      ),
    )

    await expect(deshacerDescarte('lead-1')).rejects.toMatchObject({ code: 'FUERA_DE_COLA' })
  })

  it('el choque de reapertura (índice único vivo) llega como REGLA_SERVIDOR con mensaje humano', async () => {
    server.use(
      http.post(RPC('deshacer_descarte'), () =>
        HttpResponse.json(
          { code: '22023', message: 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir' },
          { status: 400 },
        ),
      ),
    )

    await expect(deshacerDescarte('lead-1')).rejects.toMatchObject({
      code: 'REGLA_SERVIDOR',
      message: 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir',
    })
  })
})

// ── F1b tanda 3: el resumen agregado de la cola (crm.resumen_reparto_fn) ──────
describe('listarResumenReparto (msw)', () => {
  // El espejo de lib/resumen-reparto produce el shape EXACTO del RPC: usarlo
  // como generador evita que el fixture y el contrato se separen con el tiempo.
  const payloadValido = () =>
    resumenRepartoDesdeCola(
      [
        {
          id: 'lead-1',
          nombre_completo: 'ROSA QUISPE',
          distrito: 'Miraflores',
          origen: 'landing',
          categoria_interes: 'nuevo',
          monto_estimado: 30000,
          moneda: 'USD',
          creado_en: '2026-08-08T15:00:00Z',
        },
        {
          id: 'lead-2',
          nombre_completo: 'JUAN PEREZ',
          distrito: null,
          origen: 'referido',
          categoria_interes: null,
          monto_estimado: 120000,
          moneda: 'PEN',
          creado_en: '2026-08-07T15:00:00Z',
        },
      ],
      Date.parse('2026-08-09T15:00:00Z'),
    )

  it('valida y devuelve el payload version:1 con el capital por moneda separado', async () => {
    server.use(http.post(RPC('resumen_reparto_fn'), () => HttpResponse.json(payloadValido())))

    const resumen = await listarResumenReparto()

    expect(resumen.version).toBe(1)
    expect(resumen.cola.total).toBe(2)
    expect(resumen.cola.capital).toEqual({ pen: 120000, usd: 30000 })
  })

  it('fail-closed: si falta una clave del contrato, NO devuelve un agregado a medias', async () => {
    const { cola: _omitida, ...roto } = payloadValido()
    server.use(http.post(RPC('resumen_reparto_fn'), () => HttpResponse.json(roto)))

    await expect(listarResumenReparto()).rejects.toMatchObject({ code: 'RESUMEN_REPARTO_CONTRACT' })
  })

  it('una versión de payload distinta se rechaza (el cinturón es version:1)', async () => {
    server.use(
      http.post(RPC('resumen_reparto_fn'), () => HttpResponse.json({ ...payloadValido(), version: 2 })),
    )

    await expect(listarResumenReparto()).rejects.toMatchObject({ code: 'RESUMEN_REPARTO_CONTRACT' })
  })

  it('el gate de rol del servidor (42501) sube con su código, no como "sin formato"', async () => {
    server.use(
      http.post(RPC('resumen_reparto_fn'), () =>
        HttpResponse.json(
          { code: '42501', message: 'Solo Coordinacion o Gerencia puede ver el resumen de reparto' },
          { status: 403 },
        ),
      ),
    )

    const fallo = await listarResumenReparto().catch((e: unknown) => e)
    expect(fallo).toBeInstanceOf(CrmApiError)
    expect(fallo).toMatchObject({ code: '42501' })
  })
})
