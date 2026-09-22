import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { alertaDiariaAAlertaCRM, type GrupoDiario } from './gestion-diaria-alertas'
import { AvisosCortesSchema } from './gestion-diaria-avisos'
import { avisosFixture } from './gestion-diaria-avisos.fixture'

const id = '00000000-0000-4000-8000-000000000033'
function completa() {
  const r = avisosFixture()
  r.diarias = { modo_sla: 'activo', alertas: [{ id: `grupo:parado_2h:${r.supervisor_id}`,
    tipo: 'parado_2h', severidad: 'atencion', miembros: [id], total: 1 }] }
  r.contexto = { en_jornada: true, analistas: 1, con_llamadas: 0,
    equipo: [{ analista_id: id, nombre: 'Analista sin llamadas', llamadas: 0, primera_llamada_en: null, sin_llamar_2h: true }] }
  return r
}
describe('avisos diarios de la fuente compartida', () => {
  it('acepta grupos de problemas distintos y contexto explícito', () => {
    expect(v.safeParse(AvisosCortesSchema, completa()).success).toBe(true)
  })
  it.each(['ajeno', 'sin contexto', 'conteo falso', 'duplicado', 'fuera de jornada', 'doble corte', 'SLA apagado', 'primera falsa'])
  ('rechaza %s', (caso) => {
    const r = completa(), g = r.diarias!.alertas[0]!, c = r.contexto!
    if (caso === 'ajeno') g.id = 'grupo:parado_2h:otro'
    if (caso === 'sin contexto') delete r.contexto
    if (caso === 'conteo falso') g.total = 2
    if (caso === 'duplicado') r.diarias!.alertas.push({ ...g })
    if (caso === 'fuera de jornada') c.en_jornada = false
    if (caso === 'doble corte') r.alertas[0]!.miembros[0]!.analista_id = id
    if (caso === 'SLA apagado') {
      r.diarias!.modo_sla = 'legado'; g.tipo = 'tarea_vencida'; g.id = `grupo:tarea_vencida:${r.supervisor_id}`
    }
    if (caso === 'primera falsa') c.equipo[0]!.primera_llamada_en = r.generado_en
    expect(v.safeParse(AvisosCortesSchema, r).success).toBe(false)
  })
  it.each(['tarea_vencida', 'por_repartir', 'parado_2h', 'primera_atencion', 'seguimiento', 'datos_incompletos', 'revision_comercial'] as const)
  ('solo conserva reconocimiento para tareas y reparto: %s', (tipo) => {
    const grupo: GrupoDiario = { id: `grupo:${tipo}:supervisor`, tipo, severidad: 'atencion', miembros: [id], total: 1 }
    const a = alertaDiariaAAlertaCRM(grupo, 'supervisor', completa().contexto)
    expect(a.diaria).toBe(true)
    expect(a.miembros).toEqual(['tarea_vencida', 'por_repartir'].includes(tipo) ? [id] : undefined)
    expect(a.destino.vista).toBe(tipo === 'parado_2h' ? 'gestion-diaria' : 'seguimiento')
  })
})
