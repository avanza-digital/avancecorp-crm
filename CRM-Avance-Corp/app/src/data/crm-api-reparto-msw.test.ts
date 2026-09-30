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
  agendaRepartoDiaria,
  conversionCoordinacion,
  CrmApiError,
  descartarLead,
  deshacerDescarte,
  guardarAgendaRepartoDiaria,
  historialDerivaciones,
  leadsPorRepartir,
  listarReporteDerivacionesCoordinacion,
  listarResumenReparto,
  panelDistribucionReparto,
  repartirLead,
  supervisoresParaReparto,
} from './crm-api'
import { resumenRepartoDesdeCola } from '@/lib/resumen-reparto'
import { payloadValido as conversionValida } from '@/lib/conversion-coordinacion.test'

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

const FILA_HISTORIAL = {
  actividad_id: 'actividad-1',
  lead_id: 'lead-1',
  nombre_completo: 'ROSA QUISPE',
  distrito: 'Miraflores',
  origen: 'landing',
  monto_estimado: '30000.00',
  moneda: 'USD',
  etapa_actual: 'contactado',
  movimiento: 'asignado',
  derivado_en: '2026-08-19T20:33:33Z',
  responsable_anterior: 'Bandeja de SUPERVISOR UNO',
  responsable_nuevo: 'ANALISTA UNO',
  derivado_por_nombre: 'SUPERVISOR UNO',
}

const PANEL_DISTRIBUCION = {
  version: 1,
  generado_en: '2026-08-19T20:33:33Z',
  total_leads: '7',
  supervisores: [{ perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', total_leads: '5' }],
  analistas: [{
    perfil_id: 'vend-1', nombre: 'ANALISTA UNO', supervisor_id: 'sup-1',
    supervisor_nombre: 'SUPERVISOR UNO', total_leads: 2,
  }],
}

const AGENDA_REPARTO = {
  version: 1,
  fecha_desde: '2026-08-17',
  destinos: [
    { perfil_id: 'sup-carmen', nombre: 'CARMEN JARAMILLO', alias: 'Carmen' },
    { perfil_id: 'sup-jor', nombre: 'JORGE MARZANO', alias: 'Jor' },
  ],
  dias: [{
    fecha: '2026-08-19',
    asignaciones: [
      {
        origen: 'landing', supervisor_id: 'sup-carmen', supervisor_nombre: 'CARMEN JARAMILLO',
        supervisor_alias: 'Carmen', derivados: '12', fuera_turno: '2',
        entregas: [
          { supervisor_id: 'sup-carmen', supervisor_nombre: 'CARMEN JARAMILLO', supervisor_alias: 'Carmen', derivados: '10', coincide_turno: true },
          { supervisor_id: 'sup-jor', supervisor_nombre: 'JORGE MARZANO', supervisor_alias: 'Jor', derivados: 2, coincide_turno: false },
        ],
      },
      {
        origen: 'formulario', supervisor_id: 'sup-jor', supervisor_nombre: 'JORGE MARZANO',
        supervisor_alias: 'Jor', derivados: 8, fuera_turno: 0,
        entregas: [{ supervisor_id: 'sup-jor', supervisor_nombre: 'JORGE MARZANO', supervisor_alias: 'Jor', derivados: 8, coincide_turno: true }],
      },
    ],
  }],
}

const REPORTE_DERIVACIONES_COORDINACION = {
  version: 1,
  generado_en: '2026-09-04T15:00:00Z',
  periodo: { desde: '2026-09-02', hasta: '2026-09-03', dias: '2', zona: 'America/Lima' },
  total_derivados: '3',
  dias: [
    {
      fecha: '2026-09-03',
      total_derivados: '3',
      analistas: [{
        analista_id: '00000000-0000-4000-8000-000000000001',
        analista_nombre: 'ANALISTA UNO',
        supervisor_id: '00000000-0000-4000-8000-000000000002',
        supervisor_nombre: 'SUPERVISOR UNO',
        derivados: '3',
      }],
      entregas: [
        {
          analista_id: '00000000-0000-4000-8000-000000000001',
          analista_nombre: 'ANALISTA UNO',
          supervisor_id: '00000000-0000-4000-8000-000000000002',
          supervisor_nombre: 'SUPERVISOR UNO',
          origen: 'landing',
          derivados: '2',
        },
        {
          analista_id: '00000000-0000-4000-8000-000000000001',
          analista_nombre: 'ANALISTA UNO',
          supervisor_id: '00000000-0000-4000-8000-000000000002',
          supervisor_nombre: 'SUPERVISOR UNO',
          origen: 'referido',
          derivados: '1',
        },
      ],
    },
    { fecha: '2026-09-02', total_derivados: 0, analistas: [], entregas: [] },
  ],
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

describe('historialDerivaciones (msw)', () => {
  it('pide la primera página, valida las etapas y transforma montos numeric', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('historial_derivaciones'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([
          FILA_HISTORIAL,
          { ...FILA_HISTORIAL, actividad_id: 'corrupta', etapa_actual: 'desconocida' },
        ])
      }),
    )

    await expect(historialDerivaciones()).resolves.toEqual([
      expect.objectContaining({ actividad_id: 'actividad-1', monto_estimado: 30000, etapa_actual: 'contactado' }),
    ])
    expect(cuerpo).toEqual({ p_limite: 25 })
  })

  it('envía el cursor compuesto al pedir la página siguiente', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('historial_derivaciones'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json([])
      }),
    )

    await historialDerivaciones({ actividad_id: 'actividad-9', derivado_en: '2026-08-18T10:00:00Z' })
    expect(cuerpo).toEqual({
      p_limite: 25,
      p_derivado_antes: '2026-08-18T10:00:00Z',
      p_actividad_antes: 'actividad-9',
    })
  })
})

describe('panelDistribucionReparto (msw)', () => {
  it('pide una foto agregada, transforma conteos y no solicita filas de leads', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('panel_distribucion_reparto'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(PANEL_DISTRIBUCION)
      }),
    )

    await expect(panelDistribucionReparto()).resolves.toMatchObject({
      version: 1,
      total_leads: 7,
      supervisores: [{ perfil_id: 'sup-1', total_leads: 5 }],
      analistas: [{ perfil_id: 'vend-1', total_leads: 2 }],
    })
    expect(cuerpo).toEqual({ p_solo_activos: true })
  })

  it('envía los filtros elegidos al servidor', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('panel_distribucion_reparto'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(PANEL_DISTRIBUCION)
      }),
    )

    await panelDistribucionReparto({ supervisorId: 'sup-1', analistaId: 'vend-1', origen: 'referido' })
    expect(cuerpo).toEqual({
      p_solo_activos: true,
      p_supervisor: 'sup-1',
      p_analista: 'vend-1',
      p_origen: 'referido',
    })
  })

  it('rechaza una respuesta de panel fuera de contrato', async () => {
    server.use(
      http.post(RPC('panel_distribucion_reparto'), () =>
        HttpResponse.json({ ...PANEL_DISTRIBUCION, version: 2 }),
      ),
    )

    await expect(panelDistribucionReparto()).rejects.toMatchObject({ code: 'PANEL_DISTRIBUCION_CONTRACT' })
  })
})

describe('listarReporteDerivacionesCoordinacion (msw)', () => {
  it('envía el rango, normaliza conteos y conserva el desglose diario', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('reporte_derivaciones_coordinacion_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(REPORTE_DERIVACIONES_COORDINACION)
      }),
    )

    await expect(
      listarReporteDerivacionesCoordinacion('2026-09-02', '2026-09-03'),
    ).resolves.toMatchObject({
      total_derivados: 3,
      dias: [
        {
          fecha: '2026-09-03',
          total_derivados: 3,
          analistas: [{ derivados: 3 }],
          entregas: [{ origen: 'landing', derivados: 2 }, { origen: 'referido', derivados: 1 }],
        },
        { fecha: '2026-09-02', total_derivados: 0, analistas: [], entregas: [] },
      ],
    })
    expect(cuerpo).toEqual({ p_desde: '2026-09-02', p_hasta: '2026-09-03' })
  })

  it('rechaza un payload cuyos totales no reconcilian', async () => {
    server.use(
      http.post(RPC('reporte_derivaciones_coordinacion_fn'), () =>
        HttpResponse.json({ ...REPORTE_DERIVACIONES_COORDINACION, total_derivados: 8 }),
      ),
    )

    await expect(
      listarReporteDerivacionesCoordinacion('2026-09-02', '2026-09-03'),
    ).rejects.toMatchObject({ code: 'REPORTE_DERIVACIONES_COORDINACION_CONTRACT' })
  })

  it('explica el bloqueo de rol como permiso de consulta del reporte', async () => {
    server.use(
      http.post(RPC('reporte_derivaciones_coordinacion_fn'), () =>
        HttpResponse.json({ code: '42501', message: 'Solo Coordinación activa' }, { status: 403 }),
      ),
    )

    await expect(
      listarReporteDerivacionesCoordinacion('2026-09-02', '2026-09-03'),
    ).rejects.toMatchObject({
      code: '42501',
      message: 'No tienes permiso para consultar el reporte diario de derivaciones.',
    })
  })
})

describe('agendaRepartoDiaria (msw)', () => {
  it('carga solo los turnos Landing/Formulario, sus destinos y conteos', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('agenda_reparto_diaria'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json(AGENDA_REPARTO)
      }),
    )

    await expect(agendaRepartoDiaria({ desde: '2026-08-17', dias: 7 })).resolves.toMatchObject({
      version: 1,
      destinos: [{ alias: 'Carmen' }, { alias: 'Jor' }],
      dias: [{
        fecha: '2026-08-19',
        asignaciones: [
          {
            origen: 'landing', derivados: 12, fuera_turno: 2,
            entregas: [
              { supervisor_alias: 'Carmen', derivados: 10, coincide_turno: true },
              { supervisor_alias: 'Jor', derivados: 2, coincide_turno: false },
            ],
          },
          { origen: 'formulario', derivados: 8, fuera_turno: 0 },
        ],
      }],
    })
    expect(cuerpo).toEqual({ p_desde: '2026-08-17', p_dias: 7 })
  })

  it('guarda ambos carriles juntos y rechaza una confirmación fuera de contrato', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('guardar_agenda_reparto_diaria'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({ version: 1, fecha: '2026-08-19', guardado_en: '2026-08-19T10:00:00Z' })
      }),
    )

    await expect(guardarAgendaRepartoDiaria('2026-08-19', 'sup-carmen', 'sup-jor')).resolves.toBeUndefined()
    expect(cuerpo).toEqual({ p_fecha: '2026-08-19', p_landing: 'sup-carmen', p_formulario: 'sup-jor' })

    server.use(
      http.post(RPC('guardar_agenda_reparto_diaria'), () => HttpResponse.json({ version: 2 })),
    )
    await expect(guardarAgendaRepartoDiaria('2026-08-19', 'sup-carmen', 'sup-jor'))
      .rejects.toMatchObject({ code: 'AGENDA_REPARTO_GUARDADO_CONTRACT' })
  })

  it('muestra una regla operativa del servidor en vez de un aviso genérico', async () => {
    server.use(
      http.post(RPC('guardar_agenda_reparto_diaria'), () =>
        HttpResponse.json(
          { code: '22023', message: 'Landing ya tiene derivaciones hoy; su plan quedó registrado' },
          { status: 400 },
        ),
      ),
    )

    await expect(guardarAgendaRepartoDiaria('2026-08-19', 'sup-carmen', 'sup-jor'))
      .rejects.toMatchObject({
        code: '22023',
        message: 'Landing ya tiene derivaciones hoy; su plan quedó registrado',
      })
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

describe('conversionCoordinacion (crm.conversion_divisor_coordinacion_fn)', () => {
  it('manda el primer día del mes, acepta numéricos como texto y devuelve el payload parseado', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), async ({ request }) => {
      cuerpo = await request.json()
      const datos = conversionValida()
      return HttpResponse.json({
        ...datos,
        empresa: { ...datos.empresa, numerador: '20.15', divisor: '205' },
      })
    }))

    const datos = await conversionCoordinacion({ modo: 'mes', mes: '2026-09' })
    expect(cuerpo).toEqual({ p_periodo: '2026-09-01' })
    expect(datos.empresa.divisor).toBe(205)
    expect(datos.empresa.numerador).toBe(20.15)
    expect(datos.analistas[0]).toMatchObject({ divisor: 115, divisor_formulario: 65, divisor_landing: 50, conversion_pct: 9.7 })
  })

  it('rechaza un mes mal formado y un rango cruzado sin tocar la red', async () => {
    await expect(conversionCoordinacion({ modo: 'mes', mes: '2026-09-15' })).rejects.toMatchObject({ code: 'PERIODO_INVALIDO' })
    await expect(conversionCoordinacion({ modo: 'rango', desde: '2026-09-16', hasta: '2026-09-15' })).rejects.toMatchObject({ code: 'PERIODO_INVALIDO' })
  })

  it('en modo rango manda p_desde/p_hasta y exige que el servidor eco-e el rango inclusivo', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), async ({ request }) => {
      cuerpo = await request.json()
      const datos = conversionValida()
      return HttpResponse.json({
        ...datos,
        periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: '2026-09-01', hasta: '2026-09-15', dias: '15' },
      })
    }))
    const datos = await conversionCoordinacion({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })
    expect(cuerpo).toEqual({ p_desde: '2026-09-01', p_hasta: '2026-09-15' })
    expect(datos.periodo).toMatchObject({ modo: 'rango', dias: 15 })

    // Si el servidor devolviera el mes entero para un rango pedido, se rechaza.
    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(conversionValida())))
    await expect(conversionCoordinacion({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' })).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_INCONSISTENTE' })
  })

  it('fail-closed: un payload fuera de contrato no se devuelve a medias', async () => {
    const { analistas: _fuera, ...roto } = conversionValida()
    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(roto)))
    await expect(conversionCoordinacion({ modo: 'mes', mes: '2026-09' })).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_CONTRACT' })
  })

  it('PARIDAD: si formulario + landing no suman el divisor (el 62 del reporte), el paquete se rechaza entero', async () => {
    const datos = conversionValida()
    datos.analistas[0] = { ...datos.analistas[0]!, divisor_formulario: 62 }
    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () => HttpResponse.json(datos)))
    await expect(conversionCoordinacion({ modo: 'mes', mes: '2026-09' })).rejects.toMatchObject({ code: 'CONVERSION_COORDINACION_INCONSISTENTE' })
  })

  it('el gate de rol (42501) sube con su código y un mensaje entendible', async () => {
    server.use(http.post(RPC('conversion_divisor_coordinacion_fn'), () =>
      HttpResponse.json({ code: '42501', message: 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista' }, { status: 403 })))
    const fallo = await conversionCoordinacion({ modo: 'mes', mes: '2026-09' }).catch((e: unknown) => e)
    expect(fallo).toBeInstanceOf(CrmApiError)
    expect(fallo).toMatchObject({ code: '42501', message: 'No tienes permiso para consultar la conversión por analista.' })
  })
})
