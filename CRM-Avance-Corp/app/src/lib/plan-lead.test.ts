// Contrato de "¿este lead tiene plan?".
//
// El agujero que cierra: una tarea PENDIENTE que venció hace dos semanas
// contaba como plan y escondía al lead de la cola — cuanto más se abandonaba,
// más invisible se volvía. Lo que se fija aquí es la frontera exacta entre plan
// vivo y plan muerto, y que las tres vistas (`vigente`, `vencido`, `conTarea`)
// sigan respondiendo preguntas DISTINTAS: mezclarlas duplica avisos.
import { describe, expect, it } from 'vitest'
import { planPorLead } from './plan-lead'
import type { Tarea } from './tipos'

// Miércoles 22/07/2026, 10:00 Lima — a media mañana, con día por delante.
const AHORA = Date.parse('2026-07-22T10:00:00-05:00')

const tarea = (parche: Partial<Tarea> = {}): Tarea => ({
  id: 't1',
  lead_id: 'l1',
  tipo: 'llamada',
  titulo: 'Llamar a Ana',
  vence_en: '2026-07-22T09:00:00-05:00',
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-20T10:00:00-05:00',
  ...parche,
})

describe('planPorLead — plan vivo vs plan muerto', () => {
  it('una tarea que venció MÁS TEMPRANO HOY sigue siendo plan vivo', () => {
    // El plan muere por DÍA, no por hora: la agenda del día se trabaja en el
    // orden que el analista quiera. Matarlo a las 10:01 volvería la cola un eco
    // minuto a minuto de la agenda de al lado.
    const p = planPorLead([tarea({ vence_en: '2026-07-22T08:00:00-05:00' })], AHORA)
    expect(p.vigente.has('l1')).toBe(true)
    expect(p.vencido.has('l1')).toBe(false)
  })

  it('una tarea de MAÑANA es plan vivo', () => {
    const p = planPorLead([tarea({ vence_en: '2026-07-23T09:00:00-05:00' })], AHORA)
    expect(p.vigente.has('l1')).toBe(true)
  })

  it('una tarea de AYER ya no es plan: el lead deja de esconderse', () => {
    const p = planPorLead([tarea({ vence_en: '2026-07-21T09:00:00-05:00' })], AHORA)
    expect(p.vigente.has('l1')).toBe(false)
    expect(p.vencido.get('l1')?.id).toBe('t1')
  })

  it('con varias muertas se queda con la MÁS VIEJA (la que más avergüenza)', () => {
    const p = planPorLead(
      [
        tarea({ id: 'reciente', vence_en: '2026-07-20T09:00:00-05:00' }),
        tarea({ id: 'antigua', vence_en: '2026-07-10T09:00:00-05:00' }),
      ],
      AHORA,
    )
    expect(p.vencido.get('l1')?.id).toBe('antigua')
  })

  it('una muerta y una viva a la vez: el plan VIVE, y la muerta queda anotada', () => {
    const p = planPorLead(
      [
        tarea({ id: 'muerta', vence_en: '2026-07-15T09:00:00-05:00' }),
        tarea({ id: 'viva', vence_en: '2026-07-24T09:00:00-05:00' }),
      ],
      AHORA,
    )
    expect(p.vigente.has('l1')).toBe(true)
    expect(p.vencido.get('l1')?.id).toBe('muerta')
  })

  it.each(['completada', 'cancelada', 'no_show'] as const)(
    'una tarea %s no es plan de nada',
    (estado) => {
      const p = planPorLead([tarea({ estado })], AHORA)
      expect(p.vigente.size).toBe(0)
      expect(p.vencido.size).toBe(0)
      expect(p.conTarea.size).toBe(0)
    },
  )

  it('una tarea desactivada (soft-delete) tampoco', () => {
    expect(planPorLead([tarea({ activo: false })], AHORA).conTarea.size).toBe(0)
  })

  it('las tareas SIN lead (de cliente) no gobiernan la cola de leads', () => {
    expect(planPorLead([tarea({ lead_id: null })], AHORA).conTarea.size).toBe(0)
  })

  it('una fecha corrupta se trata como VIVA — fail-safe hacia no molestar', () => {
    // Que una fila rota inunde la cola de todo el equipo sería peor que
    // dejarla pasar.
    const p = planPorLead([tarea({ vence_en: 'no-es-fecha' })], AHORA)
    expect(p.vigente.has('l1')).toBe(true)
    expect(p.vencido.has('l1')).toBe(false)
  })

  it('`conTarea` incluye viva Y muerta: es otra pregunta ("tiene algo escrito")', () => {
    // La higiene del viernes ya lista todas las vencidas por su cuenta; si se
    // le pasara `vigente`, el mismo lead saldría dos veces en la tarjeta.
    const p = planPorLead([tarea({ vence_en: '2026-07-01T09:00:00-05:00' })], AHORA)
    expect(p.vigente.has('l1')).toBe(false)
    expect(p.conTarea.has('l1')).toBe(true)
  })
})
