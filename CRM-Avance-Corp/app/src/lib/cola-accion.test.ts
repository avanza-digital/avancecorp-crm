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

// La foto del RPC congela TODOS los relojes en su generado_en; la deriva la
// pone el llamador contra su reloj LOCAL (use-cola-accion-operativa) para que
// el desfase servidor↔navegador no infle los números. Mutantes que deben morir
// aquí: quitar `+ deriva` de los items, y quitar el clamp de la negativa.
describe('mapearColaAccion — la foto envejece con la deriva local', () => {
  const fotoConDosMinutos = () => payload({
    resumen: { total: 1, por_bucket: { sin_responder: 1 }, por_sev: { media: 1 } },
    items: [itemPayload({
      dias: 2 / 1440, // el servidor midió 2 minutos al tomar la foto
      datos_motivo: { espera_cliente_dias: 2 / 1440, gestion_vencida: false, contacto_vencido: false },
    })],
    estancados: {
      umbral_dias: 5,
      tope: 50,
      items: [{ lead_id: 'l-9', nombre_completo: 'PEDRO QUISPE', vendedor_id: null, dias: 6 }],
    },
  })

  it('40 minutos después sin refetch, el motivo y los días avanzaron juntos', () => {
    const mapeada = mapearColaAccion(fotoConDosMinutos(), () => undefined, 40 / 1440)
    expect(mapeada.items[0]?.motivo).toContain('hace 42 minutos')
    expect(mapeada.items[0]?.dias).toBeCloseTo(42 / 1440)
    expect(mapeada.estancados[0]?.dias).toBeCloseTo(6 + 40 / 1440)
  })

  it('sin deriva (u omitida) es la foto tal cual llegó', () => {
    const mapeada = mapearColaAccion(fotoConDosMinutos(), () => undefined)
    expect(mapeada.items[0]?.motivo).toContain('hace 2 minutos')
    expect(mapeada.estancados[0]?.dias).toBe(6)
  })

  it('una deriva negativa o NaN cuenta como 0: jamás rejuvenece ni envenena', () => {
    const atras = mapearColaAccion(fotoConDosMinutos(), () => undefined, -5 / 1440)
    expect(atras.items[0]?.motivo).toContain('hace 2 minutos')
    const rota = mapearColaAccion(fotoConDosMinutos(), () => undefined, Number.NaN)
    expect(rota.items[0]?.motivo).toContain('hace 2 minutos')
    expect(Number.isFinite(rota.items[0]?.dias)).toBe(true)
  })

  it('los TRES relojes de datos_motivo envejecen (espera del cliente, etapa, último intento)', () => {
    // espera_cliente 6.99 d + deriva 0.02 cruza a «hace 7 días»: si la deriva
    // solo moviera `dias`, aquí seguiría diciendo 6 (mutante por reloj).
    const cruzaElDia = payload({
      resumen: { total: 1, por_bucket: { sin_responder: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({
        dias: 2,
        datos_motivo: { espera_cliente_dias: 6.99, gestion_vencida: false, contacto_vencido: false },
      }, { tenencia_desde: iso(AHORA - DIA * 2) })],
    })
    expect(mapearColaAccion(cruzaElDia, () => undefined, 0.02).items[0]?.motivo)
      .toContain('el cliente escribió hace 7 días')

    const enEtapa = payload({
      resumen: { total: 1, por_bucket: { sin_avance: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({
        bucket: 'sin_avance',
        dias: 2 / 1440,
        datos_motivo: { dias_en_etapa: 2 / 1440, etapa_politica_version: 3 },
      }, { etapa: 'contactado' })],
    })
    expect(mapearColaAccion(enEtapa, () => undefined, 40 / 1440).items[0]?.motivo)
      .toContain('Lleva 42 minutos en')

    const intento = payload({
      resumen: { total: 1, por_bucket: { insistir: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({
        bucket: 'insistir',
        dias: 1,
        datos_motivo: { ultimo_intento_dias: 2 / 1440, hablo: false, dos_relojes: true },
      })],
    })
    expect(mapearColaAccion(intento, () => undefined, 40 / 1440).items[0]?.motivo)
      .toContain('último intento hace 42 minutos')
  })

  it('los dos relojes envejecen JUNTOS: la frase de dos relojes no se descuadra', () => {
    const conDosRelojes = payload({
      resumen: { total: 1, por_bucket: { sin_responder: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({
        dias: 2,
        datos_motivo: { espera_cliente_dias: 6, gestion_vencida: false, contacto_vencido: false },
      }, { tenencia_desde: iso(AHORA - DIA * 2) })],
    })
    const mapeada = mapearColaAccion(conDosRelojes, () => undefined, 40 / 1440)
    expect(mapeada.items[0]?.motivo).toContain('Asignado hace 2 días')
    expect(mapeada.items[0]?.motivo).toContain('el cliente escribió hace 6 días')
  })
})

// F5a «Bases cargadas»: la cola se valida ENTERA. Un lead de base sin capital (si alguna vía lo saca del descarte
// antes de que el servidor exija capital) no puede apagar la cola ni rotularse «Otro».
describe('F5a · lead de base cargada en la cola de acción', () => {
  it('capital null y origen base_cargada: la cola parsea y el lead mínimo conserva ambos', () => {
    const conBase = payload({
      resumen: { total: 1, por_bucket: { sin_responder: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({}, { origen: 'base_cargada', monto_estimado: null })],
    })
    const mapeada = mapearColaAccion(conBase, () => undefined)
    expect(mapeada.items[0]?.lead).toMatchObject({ origen: 'base_cargada', monto_estimado: null })
  })

  it('ESTADO DE PRODUCCIÓN: un origen desconocido sigue cayendo a «otro» y el capital numérico pasa igual', () => {
    const mapeada = mapearColaAccion(payload({
      resumen: { total: 1, por_bucket: { sin_responder: 1 }, por_sev: { media: 1 } },
      items: [itemPayload({}, { origen: 'facebook', monto_estimado: 12_000 })],
    }), () => undefined)
    expect(mapeada.items[0]?.lead).toMatchObject({ origen: 'otro', monto_estimado: 12_000 })
  })
})
