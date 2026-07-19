import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  FilaObjetivoSchema,
  aObjetivosPorRol,
  aPayloadObjetivos,
  objetivosCero,
  periodoLima,
  validarObjetivos,
  type FilaObjetivo,
} from './objetivos'

describe('aObjetivosPorRol', () => {
  it('mapea filas del servidor al mapa por rol', () => {
    const filas: FilaObjetivo[] = [
      { rol: 'vendedor', capital_objetivo: 250_000, ventas_objetivo: 3, conversion_objetivo: 25 },
      { rol: 'gerencia', capital_objetivo: 1_000_000, ventas_objetivo: 12, conversion_objetivo: 28 },
    ]
    const metas = aObjetivosPorRol(filas)
    expect(metas.vendedor.capitalObjetivo).toBe(250_000)
    expect(metas.gerencia.ventasObjetivo).toBe(12)
    // rol sin fila → cero (vacío honesto, jamás undefined)
    expect(metas.supervisor).toEqual({ capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 })
  })

  it('sin filas devuelve el mapa en cero', () => {
    expect(aObjetivosPorRol([])).toEqual(objetivosCero())
  })
})

describe('FilaObjetivoSchema (borde PostgREST)', () => {
  it('acepta numeric como string y lo normaliza a número', () => {
    const r = v.safeParse(FilaObjetivoSchema, {
      rol: 'vendedor',
      capital_objetivo: '250000.00',
      ventas_objetivo: 3,
      conversion_objetivo: '25.50',
    })
    expect(r.success).toBe(true)
    if (r.success) {
      expect(r.output.capital_objetivo).toBe(250_000)
      expect(r.output.conversion_objetivo).toBe(25.5)
    }
  })

  it('rechaza basura no numérica y roles desconocidos', () => {
    expect(v.safeParse(FilaObjetivoSchema, {
      rol: 'vendedor', capital_objetivo: 'abc', ventas_objetivo: 0, conversion_objetivo: 0,
    }).success).toBe(false)
    expect(v.safeParse(FilaObjetivoSchema, {
      rol: 'analista', capital_objetivo: 1, ventas_objetivo: 0, conversion_objetivo: 0,
    }).success).toBe(false)
  })
})

describe('periodoLima', () => {
  it('la madrugada UTC del día 1 sigue siendo el mes anterior en Lima (UTC-5)', () => {
    // 2026-08-01 03:00Z = 2026-07-31 22:00 en Lima → periodo julio.
    expect(periodoLima(Date.UTC(2026, 7, 1, 3, 0))).toBe('2026-07-01')
    // 2026-08-01 06:00Z = 2026-08-01 01:00 en Lima → periodo agosto.
    expect(periodoLima(Date.UTC(2026, 7, 1, 6, 0))).toBe('2026-08-01')
  })
})

describe('aPayloadObjetivos', () => {
  it('convierte el mapa por rol al snake_case de la RPC', () => {
    const metas = objetivosCero()
    metas.vendedor = { capitalObjetivo: 250_000, ventasObjetivo: 3, conversionObjetivo: 25 }
    const payload = aPayloadObjetivos(metas)
    expect(payload['vendedor']).toEqual({
      capital_objetivo: 250_000,
      ventas_objetivo: 3,
      conversion_objetivo: 25,
    })
    expect(Object.keys(payload)).toEqual(['vendedor', 'supervisor', 'gerencia'])
  })
})

describe('validarObjetivos (espejo del CHECK del servidor)', () => {
  it('acepta ceros (meta por definir) y valores válidos', () => {
    expect(validarObjetivos(objetivosCero())).toBeNull()
    const metas = objetivosCero()
    metas.gerencia = { capitalObjetivo: 1_000_000, ventasObjetivo: 12, conversionObjetivo: 28 }
    expect(validarObjetivos(metas)).toBeNull()
  })

  it('rechaza negativos, no-finitos, decimales en cierres y porcentajes imposibles', () => {
    const casos: Array<[Partial<ReturnType<typeof objetivosCero>['vendedor']>, RegExp]> = [
      [{ capitalObjetivo: -1 }, /positivos/],
      [{ capitalObjetivo: Number.NaN }, /positivos/],
      [{ capitalObjetivo: 200_000_000 }, /100 millones/],
      [{ ventasObjetivo: 3.5 }, /entero/],
      [{ ventasObjetivo: 2000 }, /1000/],
      [{ conversionObjetivo: 120 }, /porcentaje/],
    ]
    for (const [parche, esperado] of casos) {
      const metas = objetivosCero()
      metas.vendedor = { ...metas.vendedor, ...parche }
      expect(validarObjetivos(metas)).toMatch(esperado)
    }
  })
})
