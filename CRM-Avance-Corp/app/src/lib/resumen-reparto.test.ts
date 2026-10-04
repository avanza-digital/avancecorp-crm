// Espejo de crm.resumen_reparto_fn: mismas reglas que el servidor (USD
// estricto, PEN y USD jamás sumados, espera en días ENTEROS nunca negativos y
// por_origen ordenado por n desc con desempate alfabético) y el shape EXACTO
// del payload version:1.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ResumenRepartoSchema, resumenRepartoDesdeCola } from './resumen-reparto'
import type { ColaLead } from './tipos'

const AHORA = Date.parse('2026-08-09T15:00:00Z')
const DIA = 86_400_000

const iso = (ms: number): string => new Date(ms).toISOString()

function fila(over: Partial<ColaLead> = {}): ColaLead {
  return {
    id: `c-${Math.random().toString(36).slice(2, 8)}`,
    nombre_completo: 'ROSA QUISPE',
    distrito: 'Miraflores',
    origen: 'landing',
    categoria_interes: 'nuevo',
    monto_estimado: 10_000,
    moneda: 'PEN',
    creado_en: iso(AHORA - DIA),
    clasificacion_auto: null,
    comentario: null,
    ...over,
  }
}

describe('resumenRepartoDesdeCola — contrato', () => {
  it('el payload que produce cumple el MISMO contrato Valibot que valida al RPC', () => {
    const resumen = resumenRepartoDesdeCola(
      [fila(), fila({ moneda: 'USD', origen: 'referido', clasificacion_auto: 'posible_credito' })],
      AHORA,
    )
    expect(v.safeParse(ResumenRepartoSchema, resumen).success).toBe(true)
    expect(resumen.version).toBe(1)
  })

  it('con la cola vacía todo queda en cero y por_origen vacío (el front pinta el vacío)', () => {
    const resumen = resumenRepartoDesdeCola([], AHORA)
    expect(resumen.cola).toMatchObject({
      total: 0,
      capital: { pen: 0, usd: 0 },
      espera_max_dias: 0,
      posible_credito: 0,
      por_origen: [],
    })
  })
})

describe('resumenRepartoDesdeCola — dinero', () => {
  it('NUNCA suma PEN y USD: cada moneda va por su lado', () => {
    const resumen = resumenRepartoDesdeCola(
      [fila({ monto_estimado: 12_000, moneda: 'PEN' }), fila({ monto_estimado: 30_000, moneda: 'USD' })],
      AHORA,
    )
    expect(resumen.cola.capital).toEqual({ pen: 12_000, usd: 30_000 })
    expect(resumen.cola.total).toBe(2)
  })

  it('un monto no finito cuenta como 0 y no contamina la moneda', () => {
    const resumen = resumenRepartoDesdeCola(
      [fila({ monto_estimado: Number.NaN }), fila({ monto_estimado: 5_000 })],
      AHORA,
    )
    expect(resumen.cola.capital.pen).toBe(5_000)
  })
})

describe('resumenRepartoDesdeCola — espera', () => {
  it('toma los días ENTEROS del lead más antiguo (floor, como el servidor)', () => {
    const resumen = resumenRepartoDesdeCola(
      [
        fila({ creado_en: iso(AHORA - DIA * 3 - 1000) }),
        fila({ creado_en: iso(AHORA - DIA * 1.9) }),
      ],
      AHORA,
    )
    expect(resumen.cola.espera_max_dias).toBe(3)
  })

  it('un creado_en futuro (reloj desalineado) no produce días negativos', () => {
    const resumen = resumenRepartoDesdeCola([fila({ creado_en: iso(AHORA + DIA) })], AHORA)
    expect(resumen.cola.espera_max_dias).toBe(0)
  })

  it('una fecha ilegible no rompe el agregado ni resta espera', () => {
    const resumen = resumenRepartoDesdeCola(
      [fila({ creado_en: 'no-es-fecha' }), fila({ creado_en: iso(AHORA - DIA * 2) })],
      AHORA,
    )
    expect(resumen.cola.espera_max_dias).toBe(2)
    expect(resumen.cola.total).toBe(2)
  })
})

describe('resumenRepartoDesdeCola — marcas y orígenes', () => {
  it('posible_credito cuenta SOLO a los que marcó el clasificador', () => {
    const resumen = resumenRepartoDesdeCola(
      [
        fila({ clasificacion_auto: 'posible_credito' }),
        fila({ clasificacion_auto: null }),
        fila({ clasificacion_auto: 'posible_credito' }),
      ],
      AHORA,
    )
    expect(resumen.cola.posible_credito).toBe(2)
  })

  it('por_origen va por cantidad descendente y desempata alfabéticamente', () => {
    const resumen = resumenRepartoDesdeCola(
      [
        fila({ origen: 'referido' }),
        fila({ origen: 'landing' }),
        fila({ origen: 'landing' }),
        fila({ origen: 'formulario' }),
      ],
      AHORA,
    )
    expect(resumen.cola.por_origen).toEqual([
      { origen: 'landing', n: 2 },
      { origen: 'formulario', n: 1 },
      { origen: 'referido', n: 1 },
    ])
  })
})

// F5a «Bases cargadas»: el capital vacío (null) no suma ni vuelve NaN el total de la cola.
describe('F5a · capital vacío en el resumen de la cola', () => {
  it('lo ignora en el capital y lo cuenta en el total y por origen', () => {
    const resumen = resumenRepartoDesdeCola([fila(), fila({ origen: 'base_cargada', monto_estimado: null })], AHORA)
    expect(resumen.cola).toMatchObject({ total: 2, capital: { pen: 10_000, usd: 0 } })
    expect(v.safeParse(ResumenRepartoSchema, resumen).success).toBe(true)
  })
})
