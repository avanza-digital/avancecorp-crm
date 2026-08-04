import { describe, expect, it } from 'vitest'
import type { DisponibilidadLead } from '@/data/crm-api'
import { presentarDisponibilidadLead } from './disponibilidad-lead'

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
