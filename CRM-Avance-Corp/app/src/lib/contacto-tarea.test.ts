// Contrato del emparejamiento contacto → tarea (pedido de Miguel, 2026-07-25).
//
// Cerrar una tarea es IRREVERSIBLE (no hay "deshacer"), y esto lo dispara un
// diálogo que a veces aparece SOLO —al volver de WhatsApp Web—, así que casi
// todo lo que se prueba aquí es cuándo NO emparejar. Falso negativo = el
// vendedor cierra la tarea a mano, como hasta hoy. Falso positivo = el sistema
// da por cumplido un compromiso que quizá no lo estaba.
import { describe, expect, it } from 'vitest'
import { tareaQueCierra } from './contacto-tarea'
import type { Tarea } from './tipos'

const YO = 'vend-1'
const OTRO = 'vend-2'
// Miércoles 2026-07-22, 10:00 Lima — a media mañana, con día por delante.
const AHORA = Date.parse('2026-07-22T10:00:00-05:00')

const tarea = (parche: Partial<Tarea> = {}): Tarea => ({
  id: 't1',
  lead_id: 'l1',
  vendedor_id: YO,
  tipo: 'llamada',
  titulo: 'Llamar a Ana',
  vence_en: '2026-07-22T09:00:00-05:00', // hoy, ya vencida
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-20T10:00:00-05:00',
  ...parche,
})

describe('tareaQueCierra — qué cierra el contacto, y sobre todo qué no', () => {
  it('empareja la llamada de hoy cuando contacto por teléfono', () => {
    expect(tareaQueCierra([tarea()], 'tel', YO, AHORA)?.id).toBe('t1')
  })

  it('empareja el WhatsApp de hoy cuando contacto por WhatsApp', () => {
    expect(tareaQueCierra([tarea({ tipo: 'whatsapp' })], 'wa', YO, AHORA)?.id).toBe('t1')
  })

  it('el canal NO cae en fallback: una llamada no cierra la tarea de WhatsApp', () => {
    expect(tareaQueCierra([tarea({ tipo: 'whatsapp' })], 'tel', YO, AHORA)).toBeNull()
    expect(tareaQueCierra([tarea({ tipo: 'llamada' })], 'wa', YO, AHORA)).toBeNull()
  })

  it.each(['reunion', 'tarea'] as const)(
    'jamás toca una tarea de tipo %s — ahí está la mentira gorda (la reunión fantasma)',
    (tipo) => {
      expect(tareaQueCierra([tarea({ tipo })], 'tel', YO, AHORA)).toBeNull()
      expect(tareaQueCierra([tarea({ tipo })], 'wa', YO, AHORA)).toBeNull()
    },
  )

  it('nunca cierra la tarea de OTRO: el supervisor que llama desde la cola solo registra', () => {
    expect(tareaQueCierra([tarea({ vendedor_id: OTRO })], 'tel', YO, AHORA)).toBeNull()
  })

  it('sin sesión identificada no empareja nada', () => {
    expect(tareaQueCierra([tarea()], 'tel', null, AHORA)).toBeNull()
    expect(tareaQueCierra([tarea()], 'tel', undefined, AHORA)).toBeNull()
  })

  it('una tarea que vence MÁS TARDE HOY sí se cierra (la agenda del día se trabaja en cualquier orden)', () => {
    expect(tareaQueCierra([tarea({ vence_en: '2026-07-22T18:00:00-05:00' })], 'tel', YO, AHORA)?.id).toBe('t1')
  })

  it('una tarea de MAÑANA no se toca: es un compromiso futuro, no lo que motivó esta llamada', () => {
    expect(tareaQueCierra([tarea({ vence_en: '2026-07-23T09:00:00-05:00' })], 'tel', YO, AHORA)).toBeNull()
  })

  it('una VENCIDA de días atrás sí se cierra (es justo la que estaba mintiendo en la agenda)', () => {
    expect(tareaQueCierra([tarea({ vence_en: '2026-07-19T09:00:00-05:00' })], 'tel', YO, AHORA)?.id).toBe('t1')
  })

  it('con DOS candidatas del mismo canal no adivina: no cierra ninguna', () => {
    const dos = [tarea({ id: 'a' }), tarea({ id: 'b', vence_en: '2026-07-22T16:00:00-05:00' })]
    expect(tareaQueCierra(dos, 'tel', YO, AHORA)).toBeNull()
  })

  it('dos candidatas de canales DISTINTOS no se estorban: cada una cierra la suya', () => {
    const mixtas = [tarea({ id: 'a', tipo: 'llamada' }), tarea({ id: 'b', tipo: 'whatsapp' })]
    expect(tareaQueCierra(mixtas, 'tel', YO, AHORA)?.id).toBe('a')
    expect(tareaQueCierra(mixtas, 'wa', YO, AHORA)?.id).toBe('b')
  })

  it('sin tareas pendientes no hay nada que cerrar', () => {
    expect(tareaQueCierra([], 'tel', YO, AHORA)).toBeNull()
  })
})
