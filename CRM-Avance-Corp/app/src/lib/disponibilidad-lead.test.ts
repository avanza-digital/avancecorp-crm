import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import type { DisponibilidadLead } from '@/data/crm-api'
import {
  DisponibilidadLeadSchema,
  presentarDisponibilidadLead,
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

  it('ya_es_cliente consume el asesor y no conserva la respuesta', () => {
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

  it('ya_es_cliente no presenta el sentinel de P-047 como nombre de asesor', () => {
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

  it('el estado futuro «reutilizable» se tolera con cualquier forma y bloquea seguro', () => {
    const r = v.parse(DisponibilidadLeadSchema, {
      estado: 'reutilizable',
      forma_que_decidira_la_fase_2: true,
    })
    const p = presentarDisponibilidadLead(r)
    expect(p.bloquea).toBe(true)
    expect(p.mensaje).toEqual(expect.any(String))
    expect(tarjetaDisponibilidadLead(r)).toBeNull()
  })
})

describe('tarjetaDisponibilidadLead — la tarjeta §5.2', () => {
  it('tomado de HOY (sin claves nuevas): asesor limpio y desde cuándo, en fecha de Lima', () => {
    expect(tarjetaDisponibilidadLead({
      estado: 'tomado',
      vendedor: '  ANA    PÉREZ  ',
      tenencia_desde: '2026-08-03T16:00:00Z',
    })).toEqual({
      titulo: 'Seguimiento activo',
      lineas: [
        { etiqueta: 'Asesor', valor: 'ANA PÉREZ' },
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

  it('los estados sin seguimiento no tienen tarjeta', () => {
    expect(tarjetaDisponibilidadLead({ estado: 'libre' })).toBeNull()
    expect(tarjetaDisponibilidadLead({ estado: 'en_bolsa' })).toBeNull()
    expect(tarjetaDisponibilidadLead({ estado: 'no_contactar' })).toBeNull()
  })
})
