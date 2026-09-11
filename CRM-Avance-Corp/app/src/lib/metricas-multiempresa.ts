import * as v from 'valibot'

const Cantidad = v.pipe(v.number(), v.integer(), v.minValue(0), v.maxValue(Number.MAX_SAFE_INTEGER))
const Numero = v.pipe(v.number(), v.finite(), v.minValue(-Number.MAX_SAFE_INTEGER / 100), v.maxValue(Number.MAX_SAFE_INTEGER / 100))
const Capital = v.pipe(Numero, v.minValue(0))
const Fecha = v.pipe(v.string(), v.isoDate())
const Empresa = v.picklist(['avance', 'qorilazo', 'prodelco'])
const Moneda = v.picklist(['PEN', 'USD'])
const base = { empresa: Empresa, moneda: Moneda, operaciones: Cantidad, capital: Capital }
const personasEmpresa = v.object({ empresa: Empresa, personas: Cantidad })

export const EstadoMetricasMultiempresaSchema = v.object({ version: v.literal(1), habilitada: v.boolean() })
export const MetricasMultiempresaSchema = v.object({
  version: v.literal(1), modo: v.literal('sombra'), habilitada: v.literal(true),
  mes: Fecha, hasta: Fecha, hoy: Fecha, generado_en: v.pipe(v.string(), v.isoTimestamp()), mes_sellado: v.boolean(),
  produccion: v.array(v.object({ ...base, primeras: Cantidad, posteriores: Cantidad, sin_identidad: Cantidad })),
  tipos_capital: v.array(v.object({ ...base, tipo_capital: v.string() })),
  atribucion: v.array(v.object({ ...base, analista_id: v.nullable(v.pipe(v.string(), v.uuid())), analista_nombre: v.nullable(v.string()) })),
  personas: v.object({
    total: Cantidad, una_empresa: Cantidad, dos_empresas: Cantidad, tres_empresas: Cantidad,
    por_empresa: v.array(personasEmpresa), fuentes_sin_identidad: Cantidad,
    fuentes_coherentes: Cantidad, fuentes_contradictorias: Cantidad, fuentes_sin_enlace: Cantidad,
  }),
  conversion: v.object({
    factor_referido: Capital, divisor: Cantidad, numerador: Capital, tasa_pct: v.nullable(Capital),
    cierres: Cantidad, renovaciones: Cantidad, upgrades: Cantidad, anulados: Cantidad,
  }),
  vencimientos: v.array(v.object(base)), oportunidades: v.array(personasEmpresa),
  conciliacion: v.array(v.object({
    empresa: Empresa, moneda: Moneda, capital_nucleo: Capital, capital_informe: Capital,
    operaciones_nucleo: Cantidad, operaciones_informe: Cantidad,
    diferencia_capital: Numero, diferencia_operaciones: Numero, diferencia_atribucion: Numero,
  })),
  fuentes_duplicadas: Cantidad,
})
export type MetricasMultiempresa = v.InferOutput<typeof MetricasMultiempresaSchema>
export type EmpresaInforme = v.InferOutput<typeof Empresa>
export const EMPRESA_INFORME: Record<EmpresaInforme, string> = { avance: 'Avance', qorilazo: 'Qorilazo', prodelco: 'Prodelco' }
export const TIPO_CAPITAL: Record<string, string> = {
  contrato_nuevo: 'Contrato nuevo', contrato_renovacion: 'Renovación', contrato_upgrade: 'Upgrade', cooperativa: 'Cooperativa',
}
const clave = (r: { empresa: string; moneda: string }) => `${r.empresa}:${r.moneda}`
const unicos = <T,>(filas: T[], key: (r: T) => string) => new Set(filas.map(key)).size === filas.length
const centimos = (n: number) => Math.round(n * 100)

/** Detecta truncamientos y grupos repetidos; nunca sustituye el cálculo SQL. */
export function informeMultiempresaCompleto(r: MetricasMultiempresa): boolean {
  const p = r.personas
  if (r.mes.slice(8) !== '01' || r.hasta < r.mes || r.hasta > r.hoy || r.hasta.slice(0, 7) !== r.mes.slice(0, 7)) return false
  if (p.una_empresa + p.dos_empresas + p.tres_empresas !== p.total
    || p.fuentes_contradictorias + p.fuentes_sin_enlace !== p.fuentes_sin_identidad) return false
  if (!unicos(r.produccion, clave) || !unicos(r.conciliacion, clave) || !unicos(r.vencimientos, clave)
    || !unicos(r.tipos_capital, x => `${clave(x)}:${x.tipo_capital}`)
    || !unicos(r.atribucion, x => `${clave(x)}:${x.analista_id}`)
    || !unicos(p.por_empresa, x => x.empresa) || !unicos(r.oportunidades, x => x.empresa)) return false
  const grupos = new Set(r.produccion.map(clave))
  if ([...r.atribucion, ...r.tipos_capital].some(x => !grupos.has(clave(x)))) return false
  // Un grupo solo en el núcleo es una diferencia válida del FULL JOIN.
  // Debe llegar con cero explícito en el informe y conservar su diferencia.
  if (r.conciliacion.some(c => {
    if (!grupos.has(clave(c)) && (c.capital_informe !== 0 || c.operaciones_informe !== 0)) return true
    return centimos(c.diferencia_capital) !== centimos(c.capital_informe) - centimos(c.capital_nucleo)
      || c.diferencia_operaciones !== c.operaciones_informe - c.operaciones_nucleo
      || centimos(c.diferencia_atribucion) !== centimos(c.capital_informe) - centimos(c.capital_nucleo)
  })) return false
  return r.produccion.every(f => {
    const c = r.conciliacion.find(x => clave(x) === clave(f))
    if (!c || f.primeras + f.posteriores + f.sin_identidad !== f.operaciones
      || c.operaciones_informe !== f.operaciones || centimos(c.capital_informe) !== centimos(f.capital)) return false
    return [r.atribucion, r.tipos_capital].every(filas => {
      const grupo = filas.filter(x => clave(x) === clave(f))
      return grupo.reduce((n, x) => n + x.operaciones, 0) === f.operaciones
        && grupo.reduce((n, x) => n + centimos(x.capital), 0) === centimos(f.capital)
    })
  })
}

export function estadoConciliacion(r: MetricasMultiempresa): 'sin_movimientos' | 'coincide' | 'diferencias' {
  if (r.fuentes_duplicadas || r.conciliacion.some(c => c.diferencia_capital !== 0 || c.diferencia_operaciones !== 0 || c.diferencia_atribucion !== 0)) return 'diferencias'
  return r.conciliacion.some(c => c.operaciones_nucleo > 0) ? 'coincide' : 'sin_movimientos'
}
