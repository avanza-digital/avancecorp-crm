// @vitest-environment node
// F5a de «Bases cargadas» (04/10/2026): la pantalla publicada TOLERA los valores que traerán los contactos de base
// ANTES de que exista el primero. El servidor (B7) estrenará el origen `base_cargada`, el motivo de descarte
// `base_cargada` (E7: el contacto nace descartado en la bandeja del supervisor) y el capital vacío (E8). Con los
// catálogos cerrados, el front descartaba EN SILENCIO esas filas (hallazgo del F0) y la cartera integrada se caía
// entera. Aquí se fija, lector por lector, que una fila así se CONSERVA y se lee bien, y que sin contactos de base
// (ESTADO DE PRODUCCIÓN de hoy) todo devuelve exactamente lo mismo que antes.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  buscarLeadsGlobal,
  descartesRescateDelMes,
  historialDerivaciones,
  leadsDescartados,
  leadsPorRepartir,
  listarCarteraPagina,
  listarLeads,
  listarLeadsSinAsignar,
  obtenerLeadDelAmbitoPorId,
} from './crm-api'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const RUTA_LEADS = 'http://supabase.test/rest/v1/leads'
const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

/** Fila de lead con el shape de `cartera_pagina_fn` (ids no-UUID: no dispara la verificación de gestión). */
function filaLead(i: number, sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: `lead-${String(i).padStart(3, '0')}`,
    nombre_completo: `LEAD ${i}`,
    telefono: `+5198765${String(i).padStart(4, '0')}`,
    correo: null,
    dni: null,
    genero: null,
    fecha_nacimiento: null,
    distrito: null,
    origen: 'landing',
    etapa: 'nuevo',
    motivo_descarte: null,
    monto_estimado: '2000.50',
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: null,
    asignado_supervisor_id: null,
    creado_en: '2026-10-01T12:00:00.000Z',
    tenencia_desde: null,
    convertido_en: null,
    contrato_id: null,
    actualizado_en: new Date(Date.UTC(2026, 9, 3, 12, 0, 0) - i * 60_000).toISOString(),
    activo: true,
    nota: null,
    no_contactar: false,
    ultimo_contacto_en: null,
    ...sobre,
  }
}

/** El contacto de base tal como lo creará B7: dormido, en la bandeja del supervisor, sin capital. */
const DE_BASE = {
  origen: 'base_cargada',
  etapa: 'descartado',
  motivo_descarte: 'base_cargada',
  monto_estimado: null,
  asignado_supervisor_id: 'supervisor-1',
}

describe('F5a · el contacto de base NO se descarta en ningún lector de leads', () => {
  it('cartera por cursor (cartera_pagina_fn): conserva la fila y deja el capital en null, no en 0', async () => {
    server.use(http.post(RPC('cartera_pagina_fn'), () => HttpResponse.json([filaLead(0), filaLead(1, DE_BASE)])))

    const pagina = await listarCarteraPagina({ etapa: 'todas', vendedorId: 'todos', integrada: false }, null)

    expect(pagina.items).toHaveLength(2)
    expect(pagina.items[1]).toMatchObject({
      id: 'lead-001', origen: 'base_cargada', etapa: 'descartado', motivo_descarte: 'base_cargada', monto_estimado: null,
    })
    expect(pagina.items[0]?.monto_estimado).toBe(2000.5)
  })

  it('cartera integrada (cartera_filtrada_fn): un contacto de base ya no tumba la lista entera con ROW_CONTRACT', async () => {
    const payload = {
      version: 1, generado_en: '2026-10-04T12:00:00Z', desde: null, hasta: null,
      items: [
        { ...filaLead(0), recibido_en: null, recepcion_aproximada: null },
        { ...filaLead(1, DE_BASE), recibido_en: null, recepcion_aproximada: null },
      ],
      resumen: {
        totales: { vivos: 2, abiertos: 1, asignados: 0, parkeados: 1, convertidos: 0, descartados: 1, asignados_pen: 0, asignados_usd: 0, reasignados: 0 },
        // sum() del servidor ignora el null: el capital es solo el del lead con capital.
        capital: { asignado: { pen: 0, usd: 0 }, parkeado: { pen: 2000.5, usd: 0 }, ganado: { pen: 0, usd: 0 } },
        embudo: [{ etapa: 'nuevo', n: 1 }, { etapa: 'descartado', n: 1 }],
      },
    }
    server.use(http.post(RPC('cartera_filtrada_fn'), () => HttpResponse.json(payload)))

    const pagina = await listarCarteraPagina({ integrada: true, etapa: 'todas', vendedorId: 'todos' }, null)

    expect(pagina.items.map((l) => l.id)).toEqual(['lead-000', 'lead-001'])
    expect(pagina.items[1]).toMatchObject({ origen: 'base_cargada', motivo_descarte: 'base_cargada', monto_estimado: null })
    expect(pagina.resumen?.capital.parkeado.pen).toBe(2000.5)
  })

  it('bandeja sin analista (la del supervisor, donde nace el contacto de base): lo lista', async () => {
    server.use(http.post(RPC('cartera_pagina_fn'), () => HttpResponse.json([filaLead(0, DE_BASE), filaLead(1, { asignado_supervisor_id: 'supervisor-1' })])))

    const bandeja = await listarLeadsSinAsignar()

    expect(bandeja.map((l) => l.id)).toEqual(['lead-000', 'lead-001'])
    expect(bandeja[0]).toMatchObject({ origen: 'base_cargada', monto_estimado: null })
  })

  it('buscador global: el contacto de base aparece al buscarlo por su teléfono', async () => {
    server.use(http.post(RPC('cartera_pagina_fn'), () => HttpResponse.json([filaLead(7, DE_BASE)])))

    const encontrados = await buscarLeadsGlobal('987650007')

    expect(encontrados).toEqual([expect.objectContaining({ id: 'lead-007', origen: 'base_cargada', monto_estimado: null })])
  })

  it('ficha por id: abre el contacto de base (antes: «no cumple el contrato del CRM»)', async () => {
    server.use(http.get(RUTA_LEADS, () => HttpResponse.json([filaLead(3, { ...DE_BASE, id: 'lead-base' })])))

    const lead = await obtenerLeadDelAmbitoPorId('lead-base')

    expect(lead).toMatchObject({ id: 'lead-base', origen: 'base_cargada', motivo_descarte: 'base_cargada', monto_estimado: null })
  })

  it('listado por página (reserva dormida listarLeads): conserva la fila de base', async () => {
    server.use(http.get(RUTA_LEADS, () => HttpResponse.json([filaLead(0, DE_BASE)], { headers: { 'content-range': '0-0/1' } })))

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items).toEqual([expect.objectContaining({ origen: 'base_cargada', monto_estimado: null })])
  })

  it('cola de reparto, historial de derivaciones y descartados de Coordinación: conservan la fila con capital null', async () => {
    const proyeccion = {
      id: 'lead-1', nombre_completo: 'ROSA QUISPE', distrito: null, origen: 'base_cargada', categoria_interes: null,
      monto_estimado: null, moneda: 'PEN', creado_en: '2026-10-01T12:00:00Z',
    }
    server.use(
      http.post(RPC('leads_por_repartir'), () => HttpResponse.json([proyeccion])),
      http.post(RPC('historial_derivaciones'), () => HttpResponse.json([{
        actividad_id: 'a-1', lead_id: 'lead-1', nombre_completo: 'ROSA QUISPE', distrito: null, origen: 'base_cargada',
        monto_estimado: null, moneda: 'PEN', etapa_actual: 'descartado', movimiento: 'reasignacion',
        derivado_en: '2026-10-02T12:00:00Z', responsable_anterior: 'A', responsable_nuevo: 'B', derivado_por_nombre: 'C',
      }])),
      http.post(RPC('leads_descartados'), () => HttpResponse.json([{
        ...proyeccion, motivo_descarte: 'base_cargada', descartado_en: '2026-10-01T12:00:00Z',
        descartado_por_nombre: 'Sistema', es_mio: false, puede_deshacer: false,
      }])),
    )

    await expect(leadsPorRepartir()).resolves.toEqual([expect.objectContaining({ origen: 'base_cargada', monto_estimado: null })])
    await expect(historialDerivaciones()).resolves.toEqual([expect.objectContaining({ origen: 'base_cargada', monto_estimado: null })])
    await expect(leadsDescartados()).resolves.toEqual([
      expect.objectContaining({ origen: 'base_cargada', motivo_descarte: 'base_cargada', monto_estimado: null }),
    ])
  })

  it('descartes del mes (Base para gestión): el episodio con motivo «base_cargada» llega a su carpeta', async () => {
    server.use(http.post(RPC('rescate_descartes_mes'), () => HttpResponse.json([{
      episodio_id: 'e-1', lead_id: 'lead-1', nombre_completo: 'ROSA QUISPE', distrito: null, origen: 'base_cargada',
      categoria_interes: null, monto_estimado: null, moneda: 'PEN', motivo_descarte: 'base_cargada',
      descartado_en: '2026-10-01T12:00:00Z', asesor_id: 'a-1', asesor_nombre: 'CARMEN', puede_rescatar: true, estado: 'pendiente',
    }])))

    await expect(descartesRescateDelMes('2026-10-01')).resolves.toEqual([
      expect.objectContaining({ episodio_id: 'e-1', origen: 'base_cargada', motivo_descarte: 'base_cargada', monto_estimado: null }),
    ])
  })
})

describe('F5a · ESTADO DE PRODUCCIÓN (sin ningún contacto de base): todo igual que hoy', () => {
  it('la cartera devuelve las mismas filas con el capital numérico de siempre (string → número)', async () => {
    server.use(http.post(RPC('cartera_pagina_fn'), () => HttpResponse.json([filaLead(0), filaLead(1, { monto_estimado: 15000, moneda: 'USD' })])))

    const pagina = await listarCarteraPagina({ etapa: 'todas', vendedorId: 'todos', integrada: false }, null)

    expect(pagina.items.map((l) => [l.id, l.origen, l.monto_estimado, l.moneda])).toEqual([
      ['lead-000', 'landing', 2000.5, 'PEN'],
      ['lead-001', 'landing', 15000, 'USD'],
    ])
  })

  it('el catálogo NO se abrió a cualquier cosa: un origen o motivo desconocido, o un capital 0, se siguen descartando', async () => {
    server.use(http.post(RPC('cartera_pagina_fn'), () => HttpResponse.json([
      filaLead(0, { origen: 'facebook' }),
      filaLead(1, { etapa: 'descartado', motivo_descarte: 'cualquiera' }),
      filaLead(2, { monto_estimado: 0 }),
      filaLead(3),
    ])))

    const pagina = await listarCarteraPagina({ etapa: 'todas', vendedorId: 'todos', integrada: false }, null)

    expect(pagina.items.map((l) => l.id)).toEqual(['lead-003'])
  })

  it('la cola de reparto conserva el capital string → número de siempre', async () => {
    server.use(http.post(RPC('leads_por_repartir'), () => HttpResponse.json([{
      id: 'lead-1', nombre_completo: 'ROSA QUISPE', distrito: null, origen: 'landing', categoria_interes: null,
      monto_estimado: '30000.00', moneda: 'USD', creado_en: '2026-10-01T12:00:00Z',
    }])))

    await expect(leadsPorRepartir()).resolves.toEqual([expect.objectContaining({ origen: 'landing', monto_estimado: 30000 })])
  })
})
