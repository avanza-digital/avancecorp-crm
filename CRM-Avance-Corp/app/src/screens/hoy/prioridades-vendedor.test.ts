import { describe, expect, it } from 'vitest'
import { seleccionarPrioridadesVendedor } from './prioridades-vendedor'
import type { EventoAgenda } from '@/lib/agenda-derivada'
import type { ItemCola } from '@/lib/inteligencia'
import type { Lead } from '@/lib/tipos'

function lead(id: string): Lead {
  return {
    id,
    nombre_completo: `Lead ${id}`,
    telefono: '999999999',
    dni: null,
    correo: null,
    etapa: 'nuevo',
    origen: 'referido',
    categoria_interes: 'nuevo',
    moneda: 'PEN',
    monto_estimado: 10_000,
    vendedor_id: 'v-1',
    asignado_supervisor_id: 's-1',
    activo: true,
    creado_en: '2026-08-23T12:00:00.000Z',
  }
}

function item(id: string, sev: ItemCola['sev'], bucket: ItemCola['bucket']): ItemCola {
  return {
    lead: lead(id),
    sev,
    bucket,
    dias: 2,
    motivo: 'Necesita una acción',
  }
}

function evento(id: string, leadId: string, vencida: boolean): EventoAgenda {
  return {
    id,
    lead_id: leadId,
    titulo: `Tarea ${id}`,
    tipo: 'llamada',
    vence_en: vencida ? '2026-08-22T12:00:00.000Z' : '2026-08-23T18:00:00.000Z',
    cuando: vencida ? 'Ayer · 12:00' : 'Hoy · 18:00',
    vencida,
    color: vencida ? '#d97706' : '#2563eb',
  }
}

describe('seleccionarPrioridadesVendedor', () => {
  it('limita a tres decisiones y conserva un único ítem por lead', () => {
    const cola = [
      item('a', 'critica', 'sin_responder'),
      item('b', 'critica', 'sin_responder'),
      item('c', 'media', 'seguimiento'),
      item('d', 'baja', 'seguimiento'),
    ]
    const agenda = [evento('t-a', 'a', true), evento('t-e', 'e', false)]

    const resultado = seleccionarPrioridadesVendedor(agenda, cola)

    expect(resultado).toHaveLength(3)
    expect(new Set(resultado.map((x) => x.leadId)).size).toBe(3)
  })

  it('prioriza speed-to-lead crítico, luego vencida y después cita de hoy', () => {
    const resultado = seleccionarPrioridadesVendedor(
      [evento('t-vencida', 'b', true), evento('t-hoy', 'c', false)],
      [item('a', 'critica', 'sin_responder'), item('d', 'media', 'seguimiento')],
    )

    expect(resultado.map((x) => x.leadId)).toEqual(['a', 'b', 'c'])
    expect(resultado.map((x) => x.fuente)).toEqual(['cola', 'agenda', 'agenda'])
  })

  it('prefiere el speed-to-lead aunque su severidad aún sea baja y el mismo lead esté vencido', () => {
    const resultado = seleccionarPrioridadesVendedor(
      [evento('t-a', 'a', true)],
      [item('a', 'baja', 'sin_responder')],
    )

    expect(resultado).toHaveLength(1)
    expect(resultado[0]?.fuente).toBe('cola')
  })
})
