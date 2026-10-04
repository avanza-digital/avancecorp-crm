import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import type { DisponibilidadLead } from '@/data/crm-api'
import {
  DisponibilidadLeadSchema,
  ResultadoTomaLeadSchema,
  contactoTomable,
  presentarDisponibilidadLead,
  presentarResultadoToma,
  tarjetaDisponibilidadLead,
} from './disponibilidad-lead'

describe('presentarDisponibilidadLead', () => {
  it('libre habilita el alta y no muestra mensaje', () => {
    expect(presentarDisponibilidadLead({ estado: 'libre' })).toEqual({
      mensaje: null,
      bloquea: false,
    })
  })

  it.each<DisponibilidadLead>([
    { estado: 'en_bolsa' },
    { estado: 'tomado', vendedor: null, tenencia_desde: null },
    {
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      disponible_desde: 'fecha-invalida',
      descartado_por: null,
    },
    { estado: 'ya_es_cliente', asesor: '' },
    { estado: 'no_contactar' },
    { estado: 'error', detalle: 'telefono_invalido' },
  ])('$estado bloquea con un mensaje seguro', (resultado) => {
    const presentacion = presentarDisponibilidadLead(resultado)
    expect(presentacion.bloquea).toBe(true)
    expect(presentacion.mensaje).toEqual(expect.any(String))
    expect(presentacion.mensaje).not.toBe('')
  })

  it('tomado consume y limpia el nombre sin retener los campos del JSON', () => {
    const presentacion = presentarDisponibilidadLead({
      estado: 'tomado',
      vendedor: '  ANA\u0000   PÉREZ  ',
      tenencia_desde: '2026-08-03T16:00:00Z',
    })

    expect(presentacion).toEqual({
      mensaje: 'Este contacto ya está asignado a ANA PÉREZ.',
      bloquea: true,
    })
    expect(Object.keys(presentacion).sort()).toEqual(['bloquea', 'mensaje'])
    expect(presentacion).not.toHaveProperty('estado')
    expect(presentacion).not.toHaveProperty('vendedor')
    expect(presentacion).not.toHaveProperty('tenencia_desde')
  })

  it('enfriamiento traduce el motivo y expresa la fecha en America/Lima', () => {
    const presentacion = presentarDisponibilidadLead({
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      // En UTC ya es 11/08; en Lima todavía es 10/08.
      disponible_desde: '2026-08-11T04:30:00Z',
      descartado_por: 'SUPERVISOR UNO',
    })

    expect(presentacion).toEqual({
      mensaje: 'Este contacto está en periodo de enfriamiento por «No responde» hasta el 10 de agosto de 2026.',
      bloquea: true,
    })
    expect(presentacion).not.toHaveProperty('motivo_descarte')
    expect(presentacion).not.toHaveProperty('disponible_desde')
    expect(presentacion).not.toHaveProperty('descartado_por')
  })

  it('una fecha corrupta nunca se muestra ni desbloquea el contacto', () => {
    const presentacion = presentarDisponibilidadLead({
      estado: 'enfriamiento',
      motivo_descarte: 'datos_invalidos',
      disponible_desde: 'no-es-fecha',
      descartado_por: null,
    })

    expect(presentacion).toEqual({
      mensaje: 'Este contacto todavía está en periodo de enfriamiento por «Datos inválidos».',
      bloquea: true,
    })
  })

  it('ya_es_cliente consume el campo legacy `asesor` y no conserva la respuesta', () => {
    const presentacion = presentarDisponibilidadLead({
      estado: 'ya_es_cliente',
      asesor: '  ROSA   DÍAZ  ',
    })

    expect(presentacion).toEqual({
      mensaje: 'Esta persona ya es cliente y está a cargo de ROSA DÍAZ.',
      bloquea: true,
    })
    expect(Object.keys(presentacion).sort()).toEqual(['bloquea', 'mensaje'])
  })

  it('ya_es_cliente no presenta el sentinel de P-047 como nombre de analista', () => {
    expect(presentarDisponibilidadLead({
      estado: 'ya_es_cliente',
      asesor: 'sin asesor asignado',
    })).toEqual({
      mensaje: 'Esta persona ya es cliente de Avance Corp.',
      bloquea: true,
    })
  })

  it('error traduce el detalle técnico y nunca lo expone', () => {
    const presentacion = presentarDisponibilidadLead({
      estado: 'error',
      detalle: 'telefono_invalido',
    })

    expect(presentacion).toEqual({
      mensaje: 'Ingresa un teléfono válido para verificar su disponibilidad.',
      bloquea: true,
    })
    expect(presentacion.mensaje).not.toContain('telefono_invalido')
  })
})

// ── Fase 1 del plan «lead libre» (2026-08-16) ────────────────────────────────
// El contrato debe tolerar al servidor de MAÑANA sin aflojarse hoy. Mutantes
// que deben morir aquí: quitar las claves opcionales del schema (el payload
// enriquecido dejaría de parsear) y aflojar 'tomado' a looseObject (la clave
// desconocida pasaría). Lección del 2026-08-15: front primero, siempre.
describe('contrato tolerante — las claves de las fases siguientes', () => {
  it('acepta las claves nuevas de «tomado» y la presentación no cambia ni un byte', () => {
    const enriquecido = v.parse(DisponibilidadLeadSchema, {
      estado: 'tomado',
      vendedor: 'ANA PÉREZ',
      tenencia_desde: '2026-08-03T16:00:00Z',
      ultima_conversacion_en: '2026-08-10T05:00:00Z',
      fecha_estimada: '2026-08-30T05:00:00Z',
    })
    expect(presentarDisponibilidadLead(enriquecido)).toEqual({
      mensaje: 'Este contacto ya está asignado a ANA PÉREZ.',
      bloquea: true,
    })
  })

  it('una clave NO declarada sigue siendo error: el strict no se aflojó', () => {
    const resultado = v.safeParse(DisponibilidadLeadSchema, {
      estado: 'tomado',
      vendedor: null,
      tenencia_desde: null,
      sorpresa: 1,
    })
    expect(resultado.success).toBe(false)
  })

  // La forma REAL que emite el servidor (migración 20260817164745, en prod):
  // claves siempre presentes, fechas como las serializa Postgres en jsonb
  // (microsegundos y offset +00:00 — no la Z de conveniencia).
  const REUTILIZABLE_SERVIDOR = {
    estado: 'reutilizable',
    motivo_descarte: 'no_responde',
    descartado_en: '2026-08-01T15:00:00.123456+00:00',
    quedo_libre_en: '2026-08-08T15:00:00.123456+00:00',
    descartado_por: 'SUPERVISOR UNO',
    ultima_conversacion_en: '2026-07-30T22:00:00.654321+00:00',
  } as const

  it('«reutilizable» con la forma real del servidor parsea y bloquea el alta', () => {
    const r = v.parse(DisponibilidadLeadSchema, REUTILIZABLE_SERVIDOR)
    const p = presentarDisponibilidadLead(r)
    expect(p.bloquea).toBe(true)
    expect(p.mensaje).toEqual(expect.any(String))
    expect(p.mensaje).not.toBe('')
  })

  it('«reutilizable» acepta los dos nulos legales (LEFT JOIN y max() sin filas)', () => {
    const r = v.parse(DisponibilidadLeadSchema, {
      ...REUTILIZABLE_SERVIDOR,
      descartado_por: null,
      ultima_conversacion_en: null,
    })
    expect(r.estado).toBe('reutilizable')
  })

  it('«reutilizable» ya NO tolera cualquier forma: clave extra es error', () => {
    const resultado = v.safeParse(DisponibilidadLeadSchema, {
      ...REUTILIZABLE_SERVIDOR,
      forma_que_decidira_la_fase_2: true,
    })
    expect(resultado.success).toBe(false)
  })

  it.each(['motivo_descarte', 'descartado_en', 'quedo_libre_en', 'descartado_por', 'ultima_conversacion_en'] as const)(
    '«reutilizable» sin la clave %s es error: el contrato exige las 5',
    (clave) => {
      const { [clave]: _omitida, ...incompleto } = REUTILIZABLE_SERVIDOR
      expect(v.safeParse(DisponibilidadLeadSchema, incompleto).success).toBe(false)
    },
  )

  it('«reutilizable» con un motivo fuera del catálogo es error (espejo 7/7 del CHECK)', () => {
    const resultado = v.safeParse(DisponibilidadLeadSchema, {
      ...REUTILIZABLE_SERVIDOR,
      motivo_descarte: 'motivo_que_no_existe',
    })
    expect(resultado.success).toBe(false)
  })

  // Refutación de Codex (auditoría F1 front, 2026-08-17): PG17 admite
  // 'infinity'::timestamptz y crm.actividades.creado_en no tiene CHECK de
  // finitud — un asiento envenenado llegaría al max() del payload como
  // "infinity". El contrato lo RECHAZA a propósito: fail-closed (bloqueo +
  // telemetría), nunca pintar basura. El arreglo de raíz (CHECK de finitud,
  // hermano del anti-NaN) es deuda del SERVIDOR, anotada para F3.
  it('«infinity» de Postgres NO pasa por fecha: el contrato cierra, no pinta basura', () => {
    expect(v.safeParse(DisponibilidadLeadSchema, {
      ...REUTILIZABLE_SERVIDOR,
      ultima_conversacion_en: 'infinity',
    }).success).toBe(false)
    expect(v.safeParse(DisponibilidadLeadSchema, {
      estado: 'tomado',
      vendedor: null,
      tenencia_desde: null,
      ultima_conversacion_en: 'infinity',
    }).success).toBe(false)
  })
})

describe('tarjetaDisponibilidadLead — la tarjeta §5.2', () => {
  it('tomado de HOY (sin claves nuevas): analista limpio y desde cuándo, en fecha de Lima', () => {
    expect(tarjetaDisponibilidadLead({
      estado: 'tomado',
      vendedor: '  ANA    PÉREZ  ',
      tenencia_desde: '2026-08-03T16:00:00Z',
    })).toEqual({
      titulo: 'Seguimiento activo',
      lineas: [
        { etiqueta: 'Analista', valor: 'ANA PÉREZ' },
        { etiqueta: 'En seguimiento desde', valor: '3 de agosto de 2026' },
      ],
    })
  })

  it('enriquecido añade última conversación y fecha estimada — zona Lima, no la del equipo', () => {
    const tarjeta = tarjetaDisponibilidadLead({
      estado: 'tomado',
      vendedor: null,
      tenencia_desde: null,
      // En UTC ya es 10/08; en Lima todavía es 9/08.
      ultima_conversacion_en: '2026-08-10T03:00:00Z',
      fecha_estimada: '2026-08-30T05:00:00Z',
    })
    expect(tarjeta?.lineas).toEqual([
      { etiqueta: 'Última conversación', valor: '9 de agosto de 2026' },
      { etiqueta: 'Revisable desde (estimado)', valor: '30 de agosto de 2026' },
    ])
  })

  it('enfriamiento: motivo y fecha, sin quién lo descartó (minimización §8)', () => {
    const tarjeta = tarjetaDisponibilidadLead({
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      disponible_desde: '2026-08-11T04:30:00Z',
      descartado_por: 'SUPERVISOR UNO',
    })
    expect(tarjeta?.titulo).toBe('En enfriamiento')
    expect(JSON.stringify(tarjeta)).not.toContain('SUPERVISOR UNO')
    expect(tarjeta?.lineas).toEqual([
      { etiqueta: 'Motivo del descarte', valor: 'No responde' },
      { etiqueta: 'Disponible desde', valor: '10 de agosto de 2026' },
    ])
  })

  it('reutilizable: la historia mínima en fecha de Lima, sin quién lo descartó (§8)', () => {
    const tarjeta = tarjetaDisponibilidadLead({
      estado: 'reutilizable',
      motivo_descarte: 'no_responde',
      // En UTC ya es 02/08 y 09/08; en Lima todavía es 01/08 y 08/08.
      descartado_en: '2026-08-02T04:30:00Z',
      quedo_libre_en: '2026-08-09T04:30:00Z',
      descartado_por: 'SUPERVISOR UNO',
      ultima_conversacion_en: '2026-07-31T03:00:00Z',
    })
    expect(tarjeta?.titulo).toBe('Seguimiento anterior disponible')
    // Minimización §8: el servidor manda quién descartó, la tarjeta NO lo pinta.
    expect(JSON.stringify(tarjeta)).not.toContain('SUPERVISOR UNO')
    expect(tarjeta?.lineas).toEqual([
      { etiqueta: 'Motivo del descarte', valor: 'No responde' },
      { etiqueta: 'Descartado el', valor: '1 de agosto de 2026' },
      { etiqueta: 'Libre desde', valor: '8 de agosto de 2026' },
      { etiqueta: 'Última conversación', valor: '30 de julio de 2026' },
    ])
  })

  it('reutilizable sin conversación jamás registrada: la línea se omite, no se inventa', () => {
    const tarjeta = tarjetaDisponibilidadLead({
      estado: 'reutilizable',
      motivo_descarte: 'pide_credito',
      descartado_en: '2026-08-02T04:30:00Z',
      quedo_libre_en: '2026-08-03T04:30:00Z',
      descartado_por: null,
      ultima_conversacion_en: null,
    })
    expect(tarjeta?.lineas.map((l) => l.etiqueta)).toEqual([
      'Motivo del descarte',
      'Descartado el',
      'Libre desde',
    ])
  })

  it('los estados sin seguimiento no tienen tarjeta', () => {
    expect(tarjetaDisponibilidadLead({ estado: 'libre' })).toBeNull()
    expect(tarjetaDisponibilidadLead({ estado: 'en_bolsa' })).toBeNull()
    expect(tarjetaDisponibilidadLead({ estado: 'no_contactar' })).toBeNull()
  })
})

// ── F2 «Tomar»: la puerta, el contrato de la toma y su presentación ──────────

describe('contactoTomable — la puerta del botón (espejo de los dos CAS)', () => {
  it('en_bolsa y reutilizable son los ÚNICOS veredictos con puerta', () => {
    expect(contactoTomable({ estado: 'en_bolsa' })).toBe('bolsa')
    expect(contactoTomable(v.parse(DisponibilidadLeadSchema, {
      estado: 'reutilizable',
      motivo_descarte: 'no_responde',
      descartado_en: '2026-08-01T15:00:00+00:00',
      quedo_libre_en: '2026-08-08T15:00:00+00:00',
      descartado_por: null,
      ultima_conversacion_en: null,
    }))).toBe('reutilizable')
  })

  it('libre NO es tomable (no hay nada que tomar: el camino es crear)', () => {
    expect(contactoTomable({ estado: 'libre' })).toBeNull()
  })

  it.each<DisponibilidadLead>([
    { estado: 'tomado', vendedor: 'ANA', tenencia_desde: null },
    {
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      disponible_desde: '2026-09-01T05:00:00Z',
      descartado_por: null,
    },
    { estado: 'ya_es_cliente', asesor: 'PEDRO' },
    { estado: 'no_contactar' },
    { estado: 'error', detalle: 'telefono_invalido' },
  ])('$estado jamás abre la puerta', (resultado) => {
    expect(contactoTomable(resultado)).toBeNull()
  })
})

describe('ResultadoTomaLeadSchema — el contrato de crm.tomar_lead_libre', () => {
  // La forma REAL del retorno tomado_ok (migración 20260817164745): 6 claves.
  const TOMADO_OK_SERVIDOR = {
    estado: 'tomado_ok',
    lead_id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
    modo: 'reutilizable',
    etapa: 'nuevo',
    ciclo_actual: 2,
    tenencia_desde: '2026-08-17T21:10:00.123456+00:00',
  } as const

  it('tomado_ok con la forma real del servidor parsea', () => {
    const r = v.parse(ResultadoTomaLeadSchema, TOMADO_OK_SERVIDOR)
    expect(r.estado).toBe('tomado_ok')
  })

  it('tomado_ok es estricto: clave extra es error', () => {
    expect(v.safeParse(ResultadoTomaLeadSchema, {
      ...TOMADO_OK_SERVIDOR,
      sorpresa: true,
    }).success).toBe(false)
  })

  it('un modo desconocido o una etapa terminal rompen el contrato', () => {
    expect(v.safeParse(ResultadoTomaLeadSchema, {
      ...TOMADO_OK_SERVIDOR,
      modo: 'robo',
    }).success).toBe(false)
    // Tras una toma el lead JAMÁS está en etapa terminal: si el servidor
    // dijera eso, algo está muy roto y el contrato debe gritar.
    expect(v.safeParse(ResultadoTomaLeadSchema, {
      ...TOMADO_OK_SERVIDOR,
      etapa: 'descartado',
    }).success).toBe(false)
  })

  it('el perdedor de la carrera recibe el veredicto fresco por la misma unión', () => {
    const r = v.parse(ResultadoTomaLeadSchema, {
      estado: 'tomado',
      vendedor: 'ANA PÉREZ',
      tenencia_desde: '2026-08-17T21:10:00+00:00',
    })
    expect(r.estado).toBe('tomado')
  })
})

describe('presentarResultadoToma — §5.7: el que pierde recibe la verdad', () => {
  it('un veredicto bloqueante gana el aviso de cambio', () => {
    const p = presentarResultadoToma({
      estado: 'tomado',
      vendedor: 'ANA PÉREZ',
      tenencia_desde: null,
    })
    expect(p.bloquea).toBe(true)
    expect(p.mensaje).toBe(
      'La disponibilidad acaba de cambiar. Este contacto ya está asignado a ANA PÉREZ.',
    )
  })

  it('un libre fresco NO lleva aviso: el alta se habilita y crear es el camino', () => {
    expect(presentarResultadoToma({ estado: 'libre' })).toEqual({
      mensaje: null,
      bloquea: false,
    })
  })
})

describe('el mensaje de reutilizable tras F2', () => {
  it('ya no promete una toma «no habilitada»: el botón existe', () => {
    const p = presentarDisponibilidadLead(v.parse(DisponibilidadLeadSchema, {
      estado: 'reutilizable',
      motivo_descarte: 'sin_interes',
      descartado_en: '2026-08-01T15:00:00+00:00',
      quedo_libre_en: '2026-08-08T15:00:00+00:00',
      descartado_por: null,
      ultima_conversacion_en: null,
    }))
    expect(p.bloquea).toBe(true)
    expect(p.mensaje).not.toMatch(/no está habilitada/i)
    expect(p.mensaje).toMatch(/puede retomarse/i)
  })
})

describe('ya_es_cliente vía identidad (multiempresa)', () => {
  it('acepta la clave opcional `via` y sigue rechazando claves desconocidas', () => {
    expect(v.safeParse(DisponibilidadLeadSchema, { estado: 'ya_es_cliente', asesor: 'ROSA', via: 'identidad' }).success).toBe(true)
    expect(v.safeParse(DisponibilidadLeadSchema, { estado: 'ya_es_cliente', asesor: 'ROSA' }).success).toBe(true)
    expect(v.safeParse(DisponibilidadLeadSchema, { estado: 'ya_es_cliente', asesor: 'ROSA', via: 'otra' }).success).toBe(false)
    expect(v.safeParse(DisponibilidadLeadSchema, { estado: 'ya_es_cliente', asesor: 'ROSA', lead_id: 'x' }).success).toBe(false)
  })
})

// F5a «Bases cargadas»: el contacto de base nace descartado con motivo `base_cargada` (E7). Si alguien da de alta el
// mismo teléfono, el veredicto puede volver como enfriamiento o reutilizable con ese motivo: con el catálogo cerrado,
// la respuesta entera fallaba y el alta quedaba sin veredicto.
describe('F5a · veredicto sobre un contacto de base cargada', () => {
  const REUTILIZABLE = {
    estado: 'reutilizable',
    motivo_descarte: 'no_responde',
    descartado_en: '2026-10-01T15:00:00.123456+00:00',
    quedo_libre_en: '2026-10-02T15:00:00.123456+00:00',
    descartado_por: null,
    ultima_conversacion_en: null,
  } as const

  it('«enfriamiento» con motivo base_cargada parsea y se redacta con «Base cargada»', () => {
    const r = v.parse(DisponibilidadLeadSchema, {
      estado: 'enfriamiento', motivo_descarte: 'base_cargada',
      disponible_desde: '2026-10-10T15:00:00Z', descartado_por: null,
    })
    const p = presentarDisponibilidadLead(r)
    expect(p.bloquea).toBe(true)
    expect(p.mensaje).toContain('«Base cargada»')
  })

  it('«reutilizable» con motivo base_cargada parsea (alta y toma comparten el contrato)', () => {
    const reutilizable = { ...REUTILIZABLE, motivo_descarte: 'base_cargada' }
    expect(v.parse(DisponibilidadLeadSchema, reutilizable).estado).toBe('reutilizable')
    expect(v.safeParse(ResultadoTomaLeadSchema, reutilizable).success).toBe(true)
  })

  it('ESTADO DE PRODUCCIÓN: un motivo fuera del catálogo de lectura sigue siendo error', () => {
    expect(v.safeParse(DisponibilidadLeadSchema, { ...REUTILIZABLE, motivo_descarte: 'cualquiera' }).success).toBe(false)
  })
})
