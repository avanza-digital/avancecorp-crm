import * as v from 'valibot'
import { describe, expect, it } from 'vitest'
import type { ConfiguracionMetas, DetalleMeta } from './metas-versionadas'
import {
  agregarCumplimientos,
  capitalObjetivo,
  capitalReal,
  contratosObjetivo,
  CumplimientoMetasSchema,
  cumplimientoDesdeRpc,
  metaConversionAplicable,
  objetivosDesdeConfiguracion,
  type CumplimientoMetasRpc,
} from './objetivos'

const V1 = '00000000-0000-4000-8000-000000000001'
const V2 = '00000000-0000-4000-8000-000000000002'
const S1 = '00000000-0000-4000-8000-000000000011'

function detalles(capitalPen: number, capitalUsd: number): DetalleMeta[] {
  return [
    { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: capitalPen, contratos_objetivo: 2 },
    { categoria: 'nuevo', moneda: 'USD', capital_objetivo: capitalUsd, contratos_objetivo: 1 },
    { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: capitalPen / 2, contratos_objetivo: 1 },
    { categoria: 'renovacion', moneda: 'USD', capital_objetivo: capitalUsd / 2, contratos_objetivo: 1 },
    { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: capitalPen / 4, contratos_objetivo: 1 },
    { categoria: 'upgrade', moneda: 'USD', capital_objetivo: capitalUsd / 4, contratos_objetivo: 1 },
  ]
}

const CONFIGURACION: ConfiguracionMetas = {
  version: 1,
  periodo: '2026-08-01',
  revision: 3,
  publicada_en: '2026-08-01T15:00:00Z',
  publicada_por: null,
  publicada_por_nombre: null,
  puede_editar: false,
  vendedores: [
    {
      vendedor_id: V1,
      nombre: 'Ana Torres',
      supervisor_id: S1,
      supervisor_nombre: 'Supervisora Norte',
      conversion_objetivo: 20,
      detalles: detalles(100_000, 10_000),
    },
    {
      vendedor_id: V2,
      nombre: 'Luis Vega',
      supervisor_id: S1,
      supervisor_nombre: 'Supervisora Norte',
      conversion_objetivo: 30,
      detalles: detalles(200_000, 20_000),
    },
  ],
}

function respuestaCumplimiento(): CumplimientoMetasRpc {
  return {
    version: 1,
    periodo: '2026-08-01',
    revision: 3,
    publicada_en: '2026-08-01T15:00:00Z',
    fuentes_reales: {
      capital_y_contratos: 'contratos_confirmados',
      conversion: 'leads_resueltos',
    },
    vendedores: CONFIGURACION.vendedores.map((meta, indice) => ({
      vendedor_id: meta.vendedor_id,
      nombre: meta.nombre,
      supervisor_id: meta.supervisor_id,
      supervisor_nombre: meta.supervisor_nombre,
      conversion_objetivo: meta.conversion_objetivo,
      conversion_real: indice === 0 ? 50 : 25,
      convertidos: indice === 0 ? 2 : 1,
      resueltos: 4,
      detalles: meta.detalles.map((detalle) => ({
        ...detalle,
        capital_real: detalle.capital_objetivo / (indice + 2),
        capital_cumplimiento_pct: 100 / (indice + 2),
        contratos_real: 1,
        contratos_cumplimiento_pct: detalle.contratos_objetivo > 0
          ? 100 / detalle.contratos_objetivo
          : null,
      })),
    })),
  }
}

describe('metas versionadas y jerarquía', () => {
  it('no inventa una meta de conversión cuando no existe o falló la lectura', () => {
    expect(metaConversionAplicable(0)).toBeNull()
    expect(metaConversionAplicable(27)).toBe(27)
    expect(metaConversionAplicable(27, true)).toBeNull()
  })

  it('deriva vendedor, supervisor y empresa desde metas individuales', () => {
    const objetivosVendedor = objetivosDesdeConfiguracion(CONFIGURACION, V1)
    expect(capitalObjetivo(objetivosVendedor.vendedor, 'PEN')).toBe(175_000)
    expect(capitalObjetivo(objetivosVendedor.vendedor, 'USD')).toBe(17_500)
    expect(objetivosVendedor.vendedor.conversionObjetivo).toBe(20)

    const objetivosSupervisor = objetivosDesdeConfiguracion(CONFIGURACION, S1)
    expect(capitalObjetivo(objetivosSupervisor.supervisor, 'PEN')).toBe(525_000)
    expect(capitalObjetivo(objetivosSupervisor.supervisor, 'USD')).toBe(52_500)
    expect(objetivosSupervisor.supervisor.conversionObjetivo).toBe(25)
    expect(objetivosSupervisor.gerencia).toEqual(objetivosSupervisor.supervisor)
  })

  it('conserva moneda y categoría sin convertir ni mezclar capitales', () => {
    const objetivos = objetivosDesdeConfiguracion(CONFIGURACION)
    expect(capitalObjetivo(objetivos.gerencia, 'PEN', 'nuevo')).toBe(300_000)
    expect(capitalObjetivo(objetivos.gerencia, 'USD', 'nuevo')).toBe(30_000)
    expect(contratosObjetivo(objetivos.gerencia, 'PEN', 'nuevo')).toBe(4)
    expect(contratosObjetivo(objetivos.gerencia, 'USD', 'nuevo')).toBe(2)
  })

  it('acepta únicamente las dos fuentes autoritativas declaradas por separado', () => {
    const valido = respuestaCumplimiento()
    expect(v.parse(CumplimientoMetasSchema, valido)).toEqual(valido)

    expect(v.safeParse(CumplimientoMetasSchema, {
      ...valido,
      fuentes_reales: {
        ...valido.fuentes_reales,
        capital_y_contratos: 'pipeline_abierto',
      },
    }).success).toBe(false)
    expect(v.safeParse(CumplimientoMetasSchema, {
      ...valido,
      fuente_reales: 'contratos_confirmados',
    }).success).toBe(false)
    expect(v.safeParse(CumplimientoMetasSchema, {
      ...valido,
      campo_no_versionado: true,
    }).success).toBe(false)
    expect(v.safeParse(CumplimientoMetasSchema, {
      ...valido,
      vendedores: [{ ...valido.vendedores[0]!, detalles: valido.vendedores[0]!.detalles.slice(0, 5) }],
    }).success).toBe(false)
  })

  it('agrega cumplimiento confirmado y pondera conversión por casos resueltos', () => {
    const cumplimiento = cumplimientoDesdeRpc(respuestaCumplimiento(), S1)
    expect(cumplimiento.fuentesReales).toEqual({
      capitalYContratos: 'contratos_confirmados',
      conversion: 'leads_resueltos',
    })
    expect(cumplimiento.supervisor?.convertidos).toBe(3)
    expect(cumplimiento.supervisor?.resueltos).toBe(8)
    expect(cumplimiento.supervisor?.conversionReal).toBe(37.5)
    expect(capitalReal(cumplimiento.supervisor!, 'PEN')).toBeCloseTo(204_166.67, 1)
    expect(capitalReal(cumplimiento.supervisor!, 'USD')).toBeCloseTo(20_416.67, 1)
  })

  it('mantiene conversión real desconocida cuando no hay casos resueltos', () => {
    const fila = cumplimientoDesdeRpc(respuestaCumplimiento(), V1).vendedor
    expect(fila).not.toBeNull()
    const sinMuestra = agregarCumplimientos([{ ...fila!, convertidos: 0, resueltos: 0, conversionReal: null }])
    expect(sinMuestra?.conversionReal).toBeNull()
  })
})
