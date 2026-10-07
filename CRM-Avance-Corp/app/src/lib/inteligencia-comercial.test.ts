import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  conversionEquipoDemo,
  cumplimientoMetasConversionEquipoDemo,
  metasConversionEquipoDemo,
  metricasConversionesDemo,
  metricasReunionesDemo,
  seriesComercialesDemo,
} from './demo-inteligencia-comercial'
import { MetricasConversionesSchema } from './metricas-conversiones'
import { MetricasReunionesSchema } from './metricas-reuniones'

describe('contratos de inteligencia comercial', () => {
  it('conserva ausencia y null de N1/N3/N4 sin fabricar bloques o ceros', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    const { citas_reales, conversion_operaciones, cierres_por_semana, ...anterior } = demo
    expect(citas_reales).toBeDefined()
    expect(conversion_operaciones).toBeDefined()
    expect(cierres_por_semana).toBeDefined()
    const lecturaAnterior = v.safeParse(MetricasConversionesSchema, anterior)
    expect(lecturaAnterior.success).toBe(true)
    if (lecturaAnterior.success) expect(lecturaAnterior.output.citas_reales).toBeUndefined()
    const lecturaNula = v.safeParse(MetricasConversionesSchema, {
      ...anterior, citas_reales: null, conversion_operaciones: null, cierres_por_semana: null,
    })
    expect(lecturaNula.success).toBe(true)
    if (lecturaNula.success) expect(lecturaNula.output.conversion_operaciones).toBeNull()
  })

  it.each([-1, 1.5, '4', Infinity, NaN])('rechaza el conteo N1 inválido %s', (cantidad) => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    expect(v.safeParse(MetricasConversionesSchema, {
      ...demo, citas_reales: { ...demo.citas_reales, leads_con_cita_real: cantidad },
    }).success).toBe(false)
  })

  it('rechaza citas de más leads que la base y no acepta persona_id como unidad', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    expect(v.safeParse(MetricasConversionesSchema, {
      ...demo, citas_reales: { ...demo.citas_reales, leads_base: 2 },
    }).success).toBe(false)
    expect(v.safeParse(MetricasConversionesSchema, {
      ...demo, citas_reales: { ...demo.citas_reales, unidad: 'persona_id' },
    }).success).toBe(false)
  })

  it('conserva una operación seleccionada con aporte cero', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    const resultado = v.safeParse(MetricasConversionesSchema, {
      ...demo,
      conversion_operaciones: {
        ...demo.conversion_operaciones,
        cantidad: 1, aporte_total: 0,
        detalle: [{ ...demo.conversion_operaciones?.detalle[0], aporte_numerador: 0 }],
      },
    })
    expect(resultado.success).toBe(true)
    if (resultado.success) expect(resultado.output.conversion_operaciones?.detalle[0]?.aporte_numerador).toBe(0)
  })

  it('acepta citas anteriores al alta excluidas aunque no haya ninguna realizada computable', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    const resultado = v.safeParse(MetricasConversionesSchema, {
      ...demo, citas_reales: {
        ...demo.citas_reales, leads_con_cita_real: 0, citas_realizadas: 0,
        citas_anteriores_al_alta: 3, pct_llegadas_con_cita_real: 0,
      },
    })
    expect(resultado.success).toBe(true)
  })

  it('rechaza un mapa de operaciones truncado o con identidades duplicadas', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    expect(v.safeParse(MetricasConversionesSchema, {
      ...demo, conversion_operaciones: { ...demo.conversion_operaciones, cantidad: 3 },
    }).success).toBe(false)
    const primera = demo.conversion_operaciones!.detalle[0]
    expect(v.safeParse(MetricasConversionesSchema, {
      ...demo, conversion_operaciones: { ...demo.conversion_operaciones, detalle: [primera, primera] },
    }).success).toBe(false)
  })

  it('rechaza fotos históricas fingidas como aporte vivo y semanas que incluyan Cartera', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-04')
    expect(v.safeParse(MetricasConversionesSchema, { ...demo, conversion_operaciones: { ...demo.conversion_operaciones, lectura: 'sellada' } }).success).toBe(false)
    expect(v.safeParse(MetricasConversionesSchema, { ...demo, cierres_por_semana: { ...demo.cierres_por_semana, incluye_operaciones_cartera: true } }).success).toBe(false)
  })

  it('el ejemplo separa la maduración del lote, citas reales y cierres por fecha', () => {
    const demo = metricasConversionesDemo('2026-09-02', '2026-09-11')
    expect(demo.citas_reales).toMatchObject({ leads_con_cita_real: 38, citas_realizadas: 46 })
    expect(demo.cohorte.reuniones_realizadas).toBe(58)
    expect(demo.cierres_por_semana?.semanas).toEqual([
      { semana: 1, desde: '2026-09-02', hasta: '2026-09-08', cierres: 21, aporte_cierres: 21, cierres_fuera_del_roster: 0, aporte_cierres_fuera_del_roster: 0 },
      { semana: 2, desde: '2026-09-09', hasta: '2026-09-11', cierres: 0, aporte_cierres: 0, cierres_fuera_del_roster: 0, aporte_cierres_fuera_del_roster: 0 },
    ])
    expect(demo.cohorte.contratos).toBe(17)
  })

  it('el ejemplo de modalidades entrega la base y las exclusiones N2 explícitas', () => {
    const demo = metricasReunionesDemo('2026-09-01', '2026-09-04')
    expect(demo.modalidades[0]).toMatchObject({ divisor_realizacion: 44, canceladas_sistema_vencidas: 1, reprogramadas_vencidas: 1, realizadas: 37, pct_realizacion: 84.09 })
    expect(demo.modalidades[1]).toMatchObject({ divisor_realizacion: 28, canceladas_sistema_vencidas: 1, reprogramadas_vencidas: 1, realizadas: 21, pct_realizacion: 75 })
    expect(demo.modalidades.reduce((total, fila) => total + fila.reprogramadas, 0)).toBe(demo.resumen.reprogramadas)
    for (const fila of demo.modalidades) {
      expect(fila.reprogramadas - (fila.reprogramadas_vencidas ?? 0)).toBeLessThanOrEqual(
        fila.pactadas - fila.debieron_ocurrir,
      )
    }
  })

  it('rechaza semanas N4 fuera del rango, invertidas, repetidas o inexistentes', () => {
    const crear = () => metricasConversionesDemo('2026-09-01', '2026-09-10')
    const fuera = crear()
    Object.assign(fuera.cierres_por_semana!.semanas[0]!, { desde: '2026-08-01', hasta: '2026-08-07' })
    expect(v.safeParse(MetricasConversionesSchema, fuera).success).toBe(false)

    const invertida = crear()
    Object.assign(invertida.cierres_por_semana!.semanas[0]!, { desde: '2026-09-07', hasta: '2026-09-01' })
    expect(v.safeParse(MetricasConversionesSchema, invertida).success).toBe(false)

    const repetida = crear()
    repetida.cierres_por_semana!.semanas[1]!.semana = 1
    expect(v.safeParse(MetricasConversionesSchema, repetida).success).toBe(false)

    const inexistente = crear()
    inexistente.cierres_por_semana!.semanas[0]!.desde = '2026-02-31'
    expect(v.safeParse(MetricasConversionesSchema, inexistente).success).toBe(false)
  })

  it('rechaza también semanas N4 incompatibles dentro del detalle por analista', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-10')
    demo.responsables![0]!.cierres_por_semana![0]!.desde = '2026-08-25'
    expect(v.safeParse(MetricasConversionesSchema, demo).success).toBe(false)
  })

  it('mantiene los demos bajo el mismo contrato que las RPC', () => {
    expect(v.safeParse(
      MetricasConversionesSchema,
      metricasConversionesDemo('2026-06-01', '2026-08-05'),
    ).success).toBe(true)
    expect(v.safeParse(
      MetricasReunionesSchema,
      metricasReunionesDemo('2026-06-01', '2026-08-05'),
    ).success).toBe(true)
  })

  it('rechaza conversiones sin embudo atómico', () => {
    const demo = metricasConversionesDemo('2026-06-01', '2026-08-05')
    expect(v.safeParse(MetricasConversionesSchema, { ...demo, embudo: null }).success).toBe(false)
  })

  it('incluye un equipo demo suficiente para comparar y abrir detalle', () => {
    const equipo = conversionEquipoDemo()
    const detalle = metricasConversionesDemo('2026-08-01', '2026-08-31').responsables
    expect(equipo).toHaveLength(6)
    expect(equipo[0]).toMatchObject({ nombre: 'Ana Torres', leads: 42, conversionPct: 11.9 })
    expect(equipo.reduce((total, fila) => total + fila.leads, 0)).toBe(184)
    expect(equipo.reduce((total, fila) => total + fila.clientes, 0)).toBe(17)
    expect(seriesComercialesDemo().conversion).toHaveLength(6)
    expect(detalle).toHaveLength(6)
    expect(detalle?.[0]).toMatchObject({ vendedor_id: 'demo-v1', capital_pen: 360_000 })
    expect(detalle?.[0]?.tendencia_semanal).toHaveLength(4)
  })

  it('mantiene las metas demo explícitas y el cumplimiento confirmado separado del pipeline', () => {
    const metas = metasConversionEquipoDemo()
    const cumplimiento = cumplimientoMetasConversionEquipoDemo()

    expect(metas['demo-v1']?.conversionObjetivo).toBe(25)
    expect(cumplimiento.fuentesReales).toEqual({
      capitalYContratos: 'contratos_confirmados',
      conversion: 'leads_resueltos',
    })
    expect(cumplimiento.porVendedor['demo-v1']?.detalles).toEqual(expect.arrayContaining([
      expect.objectContaining({ moneda: 'PEN', capitalReal: 360_000, contratosReal: 3 }),
      expect.objectContaining({ moneda: 'USD', capitalReal: 20_000, contratosReal: 1 }),
    ]))
    expect(cumplimiento.porVendedor['demo-v1']).toMatchObject({
      convertidos: 5,
      resueltos: 42,
    })
  })

  it('rechaza reuniones con modalidad desconocida', () => {
    const demo = metricasReunionesDemo('2026-06-01', '2026-08-05')
    const payload = {
      ...demo,
      modalidades: [{ ...demo.modalidades[0], modalidad: 'telefonica' }],
    }
    expect(v.safeParse(MetricasReunionesSchema, payload).success).toBe(false)
  })
})

describe('tope de referidos en el núcleo de conversiones (octubre 2026)', () => {
  const nucleo = {
    base: 'llegada_unica', divisor: 100, numerador: 18, conversion_pct: 18,
    cierres_no_referidos: 15, cierres_referidos: 5, referidos_recibidos: 8, referidos_cierran_pct: 62.5,
    operaciones_cartera: 0, peso_referido: 1, mes_peso: '2026-10-01', incluye_cartera: true,
  }
  const con = (extra: Record<string, unknown>) => v.safeParse(MetricasConversionesSchema, {
    ...metricasConversionesDemo('2026-10-01', '2026-10-04'),
    nucleo: { ...nucleo, ...extra },
  })

  it('CONSERVA tope_referidos_pct (el esquema laxo borraría la clave y la pantalla no vería el tope)', () => {
    const r = con({ tope_referidos_pct: 15 })
    expect(r.success).toBe(true)
    if (r.success) expect(r.output.nucleo?.tope_referidos_pct).toBe(15)
  })

  it('el mes sin tope llega como null o ausente y sigue siendo válido', () => {
    const nulo = con({ tope_referidos_pct: null })
    expect(nulo.success).toBe(true)
    if (nulo.success) expect(nulo.output.nucleo?.tope_referidos_pct).toBeNull()
    const ausente = con({})
    expect(ausente.success).toBe(true)
    if (ausente.success) expect(ausente.output.nucleo?.tope_referidos_pct).toBeUndefined()
  })

  it('un tope fuera de 0–100 se rechaza', () => {
    expect(con({ tope_referidos_pct: 150 }).success).toBe(false)
    expect(con({ tope_referidos_pct: -5 }).success).toBe(false)
  })
})
