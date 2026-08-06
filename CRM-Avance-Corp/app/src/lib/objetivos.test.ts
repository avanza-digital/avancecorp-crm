import { describe, expect, it } from 'vitest'
import {
  aObjetivosPorRol,
  aPayloadObjetivos,
  agregarObjetivos,
  metaConversionAplicable,
  validarObjetivos,
  type ObjetivosPorVendedor,
} from './objetivos'

const FILAS = [
  { vendedor_id: 'v1', supervisor_id: 's1', capital_objetivo: 100_000, ventas_objetivo: 2, conversion_objetivo: 20 },
  { vendedor_id: 'v2', supervisor_id: 's1', capital_objetivo: 150_000, ventas_objetivo: 3, conversion_objetivo: 30 },
  { vendedor_id: 'v3', supervisor_id: 's2', capital_objetivo: 250_000, ventas_objetivo: 5, conversion_objetivo: 40 },
]

describe('objetivos individuales y jerarquía', () => {
  it('aplica 15 % solo cuando no existe meta guardada y la lectura fue válida', () => {
    expect(metaConversionAplicable(0)).toBe(15)
    expect(metaConversionAplicable(27)).toBe(27)
    expect(metaConversionAplicable(0, true)).toBeNull()
  })

  it('entrega al vendedor únicamente su meta y suma su supervisor', () => {
    const objetivos = aObjetivosPorRol(FILAS, 'v2')
    expect(objetivos.vendedor).toEqual({
      capitalObjetivo: 150_000,
      ventasObjetivo: 0,
      conversionObjetivo: 30,
    })
    expect(objetivos.supervisor).toEqual({ capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 })

    const supervisor = aObjetivosPorRol(FILAS, 's1')
    expect(supervisor.supervisor.capitalObjetivo).toBe(250_000)
    expect(supervisor.supervisor.ventasObjetivo).toBe(0)
    expect(supervisor.supervisor.conversionObjetivo).toBe(25)
  })

  it('calcula la empresa desde todas las metas de vendedores', () => {
    const objetivos = aObjetivosPorRol(FILAS, 'gerencia')
    expect(objetivos.gerencia.capitalObjetivo).toBe(500_000)
    expect(objetivos.gerencia.ventasObjetivo).toBe(0)
    expect(objetivos.gerencia.conversionObjetivo).toBe(30)
  })

  it('incluye 15 % para vendedores activos que aún no tienen fila guardada', () => {
    const objetivos = aObjetivosPorRol(
      [FILAS[0]!],
      'gerencia',
      [
        { vendedorId: 'v1', supervisorId: 's1' },
        { vendedorId: 'v-nuevo', supervisorId: 's1' },
      ],
    )

    expect(objetivos.porVendedor['v-nuevo']).toMatchObject({
      capitalObjetivo: 0,
      conversionObjetivo: 15,
    })
    expect(objetivos.gerencia.conversionObjetivo).toBe(17.5)
  })

  it('nunca suma porcentajes; promedia las metas de conversión definidas', () => {
    expect(agregarObjetivos([
      { capitalObjetivo: 1, ventasObjetivo: 1, conversionObjetivo: 10 },
      { capitalObjetivo: 1, ventasObjetivo: 3, conversionObjetivo: 30 },
    ]).conversionObjetivo).toBe(20)
  })

  it('genera un payload únicamente por vendedor, sin metas por rol', () => {
    const metas = aObjetivosPorRol(FILAS, 'gerencia').porVendedor
    expect(aPayloadObjetivos(metas)).toEqual({
      v1: { capital_objetivo: 100_000, ventas_objetivo: 0, conversion_objetivo: 20 },
      v2: { capital_objetivo: 150_000, ventas_objetivo: 0, conversion_objetivo: 30 },
      v3: { capital_objetivo: 250_000, ventas_objetivo: 0, conversion_objetivo: 40 },
    })
  })

  it('rechaza vendedores sin supervisor y valores fuera de rango', () => {
    const metas: ObjetivosPorVendedor = {
      v1: {
        vendedorId: 'v1',
        supervisorId: null,
        capitalObjetivo: 100,
        ventasObjetivo: 1,
        conversionObjetivo: 20,
      },
    }
    expect(validarObjetivos(metas)).toContain('supervisor activo')
    const meta = metas.v1
    if (!meta) throw new Error('fixture inválido')
    meta.supervisorId = 's1'
    meta.conversionObjetivo = 101
    expect(validarObjetivos(metas)).toContain('0 a 100')
  })
})
