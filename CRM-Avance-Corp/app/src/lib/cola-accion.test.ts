// Contrato y paridad de la cola servida (crm.cola_accion_fn): el mapper debe
// redactar EXACTAMENTE los motivos de colaDe (misma función de redacción) y el
// espejo demo debe producir el mismo shape operativo que el mapper.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ColaAccionSchema,
  colaAccionDesdeAmbito,
  mapearColaAccion,
  type ColaAccion,
} from './cola-accion'
import { colaDe } from './inteligencia'
import type { Actividad, Lead, Tarea } from './tipos'

const AHORA = Date.parse('2026-08-09T15:00:00Z')
const DIA = 86_400_000
const iso = (ms: number): string => new Date(ms).toISOString()

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'l-1',
    nombre_completo: 'ANA TORRES',
    telefono: '+51987654321',
    etapa: 'nuevo',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: iso(AHORA - DIA * 2),
    activo: true,
    ...over,
  }
}

function itemPayload(over: Record<string, unknown> = {}, leadOver: Record<string, unknown> = {}) {
  return {
    lead_id: 'l-1',
    bucket: 'sin_responder',
    sev: 'media',
    dias: 2,
    ultimo_contacto_en: null,
    datos_motivo: {},
    lead: {
      nombre_completo: 'ANA TORRES',
      telefono: '+51987654321',
      correo: null,
      genero: null,
      no_contactar: false,
      etapa: 'nuevo',
      origen: 'referido',
      categoria_interes: null,
      monto_estimado: 10_000,
      moneda: 'PEN',
      creado_en: iso(AHORA - DIA * 2),
      tenencia_desde: null,
      vendedor_id: 'v-1',
      asignado_supervisor_id: null,
      motivo_descarte: null,
      ...leadOver,
    },
    ...over,
  }
}

function payload(over: Record<string, unknown> = {}): ColaAccion {
  const crudo: Record<string, unknown> = {
    version: 1,
    generado_en: iso(AHORA),
    p_limite: 100,
    resumen: { total: 0, por_bucket: {}, por_sev: {} },
    items: [],
    estancados: { umbral_dias: 5, tope: 50, items: [] },
    ...over,
  }
  const r = v.safeParse(ColaAccionSchema, crudo)
  if (!r.success) throw new Error('payload de prueba fuera de contrato')
  return r.output
}

describe('mapearColaAccion — paridad de motivos con colaDe', () => {
  // La prueba de fuego de la tanda: un MISMO escenario, calculado por colaDe
  // (cliente/demo) y llegado como ingredientes del RPC, debe redactar el
  // MISMO motivo palabra por palabra.
  it('sin_responder con dos relojes: el motivo del mapper es EL de colaDe', () => {
    const elLead = lead({
      creado_en: iso(AHORA - DIA * 6),
      tenencia_desde: iso(AHORA - DIA * 2),
    })
    const [deColaDe] = colaDe([elLead], [], AHORA)
    const conIngredientes = payload({
      resumen: { total: 1, por_bucket: { sin_responder: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({
        dias: 2,
        datos_motivo: { espera_cliente_dias: 6, gestion_vencida: false, contacto_vencido: false },
      }, { tenencia_desde: iso(AHORA - DIA * 2) })],
    })
    const mapeada = mapearColaAccion(conIngredientes, () => elLead)
    expect(deColaDe?.motivo).toBeTruthy()
    expect(mapeada.items[0]?.motivo).toBe(deColaDe?.motivo)
    expect(mapeada.items[0]?.lead).toBe(elLead) // re-unido con el Lead COMPLETO
  })

  it('insistir (habló) y plan_vencido redactan las variantes exactas', () => {
    const conVariantes = payload({
      resumen: { total: 2, por_bucket: { insistir: 1, plan_vencido: 1 }, por_sev: { media: 1, baja: 1 } },
      items: [
        itemPayload({
          bucket: 'insistir',
          dias: 3,
          datos_motivo: { ultimo_intento_dias: 3.2, hablo: true, dos_relojes: false },
        }),
        itemPayload({
          lead_id: 'l-2',
          bucket: 'plan_vencido',
          sev: 'baja',
          dias: 4,
          datos_motivo: { tarea_titulo: 'Llamar al cliente', tarea_vence_en: iso(AHORA - DIA * 4) },
        }, { nombre_completo: 'JUAN PEREZ' }),
      ],
    })
    const mapeada = mapearColaAccion(conVariantes, () => undefined)
    expect(mapeada.items[0]?.motivo).toBe('Ya hablaron hace 3 días pero sigue en Nuevo — muévelo de etapa')
    expect(mapeada.items[1]?.motivo).toBe('«Llamar al cliente» venció hace 4 días y sigue abierta — ciérrala o reprográmala')
  })

  it('sin lead en el ámbito construye uno mínimo VÁLIDO desde el payload (caso borde del tope)', () => {
    const conForaneo = payload({
      resumen: { total: 1, por_bucket: { seguimiento: 1 }, por_sev: { baja: 1 } },
      items: [itemPayload({
        bucket: 'seguimiento',
        sev: 'baja',
        dias: 3.5,
      }, { etapa: 'contactado', origen: 'origen-desconocido', moneda: null, telefono: null })],
    })
    const mapeada = mapearColaAccion(conForaneo, () => undefined)
    const construido = mapeada.items[0]?.lead
    expect(construido?.id).toBe('l-1')
    expect(construido?.origen).toBe('otro') // origen fuera de catálogo degrada, no revienta
    expect(construido?.moneda).toBe('PEN') // USD estricto: lo no-USD cae a PEN
    expect(construido?.activo).toBe(true)
  })

  it('respeta el ORDEN del servidor y expone total/porBucket/porSev sin recorte', () => {
    const conTotales = payload({
      resumen: { total: 7, por_bucket: { sin_responder: 5, seguimiento: 2 }, por_sev: { critica: 5, baja: 2 } },
      items: [
        itemPayload({ lead_id: 'l-b', bucket: 'seguimiento', sev: 'baja', dias: 9 }, { etapa: 'contactado' }),
        itemPayload({ lead_id: 'l-a', dias: 1 }),
      ],
    })
    const mapeada = mapearColaAccion(conTotales, () => undefined)
    // El payload llega en un orden deliberado (desempate por id en el server):
    // el mapper NO lo reordena aunque la severidad sugiera otra cosa.
    expect(mapeada.items.map((i) => i.lead.id)).toEqual(['l-b', 'l-a'])
    expect(mapeada.total).toBe(7)
    expect(mapeada.porBucket).toEqual({ sin_responder: 5, seguimiento: 2 })
    expect(mapeada.porSev).toEqual({ critica: 5, baja: 2 })
  })
})

describe('colaAccionDesdeAmbito — espejo demo', () => {
  it('produce el mismo shape operativo con la cola viva y los estancados topados', () => {
    const leads = [
      lead({ id: 'l-nuevo', creado_en: iso(AHORA - DIA * 2) }),
      lead({ id: 'l-parkeado', vendedor_id: null, asignado_supervisor_id: 's-1' }),
      lead({ id: 'l-estancado', etapa: 'contactado', creado_en: iso(AHORA - DIA * 9) }),
    ]
    const actividades: Actividad[] = []
    const tareas: Tarea[] = []
    const espejo = colaAccionDesdeAmbito(leads, actividades, tareas, AHORA)
    expect(espejo.total).toBe(espejo.items.length)
    expect(espejo.porBucket.por_repartir).toBe(1)
    expect(espejo.porBucket.sin_responder).toBe(1) // l-nuevo (etapa nuevo sin contacto)
    expect(espejo.porBucket.seguimiento).toBe(1) // l-estancado (contactado, 9 d sin actividad)
    expect(espejo.estancados.some((e) => e.leadId === 'l-estancado')).toBe(true)
    // porSev suma lo mismo que items
    const totalSev = Object.values(espejo.porSev).reduce((a, b) => a + (b ?? 0), 0)
    expect(totalSev).toBe(espejo.items.length)
  })

  it('un lead con plan VIGENTE no aparece en cola ni en estancados (mismo salto que el servidor)', () => {
    const conPlan = lead({ id: 'l-plan', etapa: 'contactado', creado_en: iso(AHORA - DIA * 30) })
    const tarea: Tarea = {
      id: 't-1',
      lead_id: 'l-plan',
      tipo: 'llamada',
      titulo: 'Llamar',
      vence_en: iso(AHORA + DIA),
      estado: 'pendiente',
      reprogramaciones: 0,
      activo: true,
      creado_en: iso(AHORA - DIA),
    }
    const espejo = colaAccionDesdeAmbito([conPlan], [], [tarea], AHORA)
    expect(espejo.items).toHaveLength(0)
    expect(espejo.estancados).toHaveLength(0)
  })
})
