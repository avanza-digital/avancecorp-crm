// Tests del contrato runtime de crm.metricas_agenda_fn: el fixture demo debe
// pasar el MISMO schema que valida la respuesta real (si divergen, el modo
// demo mentiría sobre el contrato) y el schema debe fallar cerrado ante
// payloads malformados.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { MetricasAgendaSchema } from './metricas-agenda'
import { metricasAgendaDemo } from './demo-metricas-agenda'

describe('MetricasAgendaSchema', () => {
  it('acepta el fixture demo completo (mismo contrato que la RPC)', () => {
    const demo = metricasAgendaDemo('2026-07-12', '2026-07-18')
    const resultado = v.safeParse(MetricasAgendaSchema, demo)
    expect(resultado.success).toBe(true)
  })

  it('acepta pct_completadas en null (miembro sin cierres en el periodo)', () => {
    const demo = metricasAgendaDemo('2026-07-12', '2026-07-18')
    const payload = {
      ...demo,
      vendedores: demo.vendedores.map((ven) => ({ ...ven, pct_completadas: null })),
    }
    const resultado = v.safeParse(MetricasAgendaSchema, payload)
    expect(resultado.success).toBe(true)
  })

  it('rechaza un payload cuyo vendedores no es un array', () => {
    const demo = metricasAgendaDemo('2026-07-12', '2026-07-18')
    const payload = { ...demo, vendedores: { esto: 'no es un array' } }
    const resultado = v.safeParse(MetricasAgendaSchema, payload)
    expect(resultado.success).toBe(false)
  })
})
