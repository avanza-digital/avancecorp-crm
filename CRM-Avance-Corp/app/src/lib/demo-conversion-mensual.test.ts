import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ConversionMensualSchema } from './conversion-mensual'
import { conversionMensualDemo } from './demo-conversion-mensual'
import { conversionMensualInteligenciaDemo } from './demo-inteligencia-comercial'

// Un instante fijo A MITAD de mes: el fixture es relativo al mes de Lima y un
// instante del día 1 o del 31 probaría bordes que aquí no tocan.
const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

describe('conversionMensualDemo — la demo cuenta igual que producción', () => {
  it('cumple el MISMO contrato que el servidor (parsea con el esquema real)', () => {
    // Los ids demo ('d-v1') no son UUID y el contrato real los exige: se
    // mapean a UUIDs deterministas y TODO LO DEMÁS —literales, picklists,
    // estados, números— se valida contra el esquema de producción tal cual.
    const UUIDS: Record<string, string> = {
      'd-v1': '00000000-0000-4000-8000-0000000000d1',
      'd-v2': '00000000-0000-4000-8000-0000000000d2',
      'd-v3': '00000000-0000-4000-8000-0000000000d3',
      'd-sup1': '00000000-0000-4000-8000-0000000000a1',
      'd-sup2': '00000000-0000-4000-8000-0000000000a2',
    }
    const payload = conversionMensualDemo(AHORA, { alcance: 'global' })
    const conUuids = {
      ...payload,
      responsables: payload.responsables.map((fila) => ({
        ...fila,
        vendedor_id: UUIDS[fila.vendedor_id] ?? fila.vendedor_id,
        supervisor_id: fila.supervisor_id === null
          ? null
          : (UUIDS[fila.supervisor_id] ?? fila.supervisor_id),
      })),
    }
    const r = v.safeParse(ConversionMensualSchema, conUuids)
    expect(r.success).toBe(true)
    expect(payload.periodo).toMatchObject({
      desde: '2026-08-01T05:00:00.000Z',
      hasta: '2026-09-01T05:00:00.000Z',
    })
  })

  it('ANALISTA UNO: divisor 8 (los 2 referidos FUERA), numerador 2.15, 26.88 %', () => {
    // A mano, con la regla: recibió 8 no referidos (l2 l8 l9 l12 l15 l16 l17
    // l20) + 2 referidos que NO ocupan sitio (l1, l21). Cierra en el mes: l16
    // (no-ref del mes) + la1 (no-ref de ARRASTRE) + l21 (referido al 15 %).
    //   numerador = 2 + 0.15×1 = 2.15 · conversión = 100×2.15÷8 = 26.88 %
    const fila = conversionMensualDemo(AHORA, { alcance: 'propio', actorId: 'd-v1' }).responsables[0]
    expect(fila).toMatchObject({
      vendedor_id: 'd-v1',
      divisor: 8,
      cierres_no_referidos: 2,
      cierres_referidos: 1,
      cierres_de_arrastre: 1,
      numerador: 2.15,
      conversion_pct: 26.88,
      estado: 'medible',
    })
    expect(fila?.referidos).toMatchObject({ recibidos: 2, cerrados: 1 })
    // aporta = 100×0.15×1÷8 = 1.88 puntos — nunca 0: el caso existe para eso.
    expect(fila?.referidos.aporta_pct).toBe(1.88)
  })

  it('el TRASPASO A→B: al divisor de los dos, al numerador solo de quien cerró', () => {
    const global = conversionMensualDemo(AHORA, { alcance: 'global' })
    const uno = global.responsables.find((fila) => fila.vendedor_id === 'd-v1')
    const dos = global.responsables.find((fila) => fila.vendedor_id === 'd-v2')
    // l20 está en el divisor de ambos (8 incluye a l20; 6 incluye a l20)…
    expect(uno?.divisor).toBe(8)
    expect(dos?.divisor).toBe(6)
    // …pero el cierre es SOLO de DOS: soltar un lead no limpia el expediente.
    expect(dos?.cierres_no_referidos).toBe(1)
    expect(dos?.conversion_pct).toBe(16.67)
  })

  it('ANALISTA TRES vive de arrastre: divisor 0, % NULL, estado solo_arrastre', () => {
    const fila = conversionMensualDemo(AHORA, { alcance: 'global' })
      .responsables.find((f) => f.vendedor_id === 'd-v3')
    expect(fila).toMatchObject({
      divisor: 0,
      conversion_pct: null,
      cierres_no_referidos: 1,
      estado: 'solo_arrastre',
    })
  })

  it('el alcance recorta: el supervisor UNO ve a sus dos, y el total se RECALCULA', () => {
    const equipo = conversionMensualDemo(AHORA, { alcance: 'equipo', actorId: 'd-sup1' })
    expect(equipo.responsables.map((fila) => fila.vendedor_id).sort()).toEqual(['d-v1', 'd-v2'])
    // total = (2.15 + 1) ÷ (8 + 6) — la suma, no la media de porcentajes.
    expect(equipo.total.divisor).toBe(14)
    expect(equipo.total.numerador).toBe(3.15)
    expect(equipo.total.conversion_pct).toBe(22.5)
  })

  it('la procedencia dice de qué mes venía cada cierre, en conteos enteros', () => {
    const fila = conversionMensualDemo(AHORA, { alcance: 'propio', actorId: 'd-v1' }).responsables[0]
    const suma = (fila?.procedencia ?? []).reduce((total, tramo) => total + tramo.cierres, 0)
    expect(suma).toBe((fila?.cierres_no_referidos ?? 0) + (fila?.cierres_referidos ?? 0))
    // agosto de 2026 con un cierre asignado en julio: dos tramos.
    expect(fila?.procedencia.map((tramo) => tramo.mes_nombre)).toEqual(['agosto', 'julio'])
  })
})

describe('conversionMensualInteligenciaDemo — el mundo demo-v* cuenta con la MISMA regla', () => {
  it('cumple el contrato del servidor (parsea con el esquema real)', () => {
    const UUIDS: Record<string, string> = Object.fromEntries([
      ...[1, 2, 3, 4, 5, 6].map((n) => [`demo-v${n}`, `00000000-0000-4000-8000-0000000000b${n}`]),
      ['demo-s1', '00000000-0000-4000-8000-0000000000c1'],
      ['demo-s2', '00000000-0000-4000-8000-0000000000c2'],
    ])
    const payload = conversionMensualInteligenciaDemo(AHORA)
    const conUuids = {
      ...payload,
      responsables: payload.responsables.map((fila) => ({
        ...fila,
        vendedor_id: UUIDS[fila.vendedor_id] ?? fila.vendedor_id,
        supervisor_id: fila.supervisor_id === null
          ? null
          : (UUIDS[fila.supervisor_id] ?? fila.supervisor_id),
      })),
    }
    expect(v.safeParse(ConversionMensualSchema, conUuids).success).toBe(true)
  })

  it('Ana 4.15÷12 = 34.58 % · total 9.30÷39 = 23.85 % · Elena y Fabio en sus estados', () => {
    const payload = conversionMensualInteligenciaDemo(AHORA)
    const ana = payload.responsables.find((fila) => fila.vendedor_id === 'demo-v1')
    expect(ana).toMatchObject({
      divisor: 12,
      cierres_no_referidos: 4,
      cierres_referidos: 1,
      cierres_de_arrastre: 1,
      numerador: 4.15,
      conversion_pct: 34.58,
      estado: 'medible',
    })
    expect(ana?.referidos).toMatchObject({ recibidos: 2, cerrados: 1, aporta_pct: 1.25 })
    const estados = Object.fromEntries(payload.responsables.map((fila) => [fila.vendedor_id, fila.estado]))
    expect(estados['demo-v5']).toBe('solo_referidos')
    expect(estados['demo-v6']).toBe('solo_arrastre')
    expect(payload.total).toMatchObject({ divisor: 39, numerador: 9.3, conversion_pct: 23.85 })
  })
})
