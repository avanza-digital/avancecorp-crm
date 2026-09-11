import type { MetricasMultiempresa } from './metricas-multiempresa'

/** Ejemplo explícito: nunca se mezcla con la consulta de una sesión real. */
export function metricasMultiempresaDemo(mes: string, hoy: string): MetricasMultiempresa {
  const ultimo = new Date(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)), 0).getDate()
  const fin = `${mes.slice(0, 8)}${ultimo}`
  const produccion: MetricasMultiempresa['produccion'] = [
    { empresa: 'avance', moneda: 'PEN', operaciones: 1, capital: 10000, primeras: 1, posteriores: 0, sin_identidad: 0 },
    { empresa: 'avance', moneda: 'USD', operaciones: 1, capital: 2000, primeras: 1, posteriores: 0, sin_identidad: 0 },
    { empresa: 'qorilazo', moneda: 'PEN', operaciones: 2, capital: 12000, primeras: 1, posteriores: 1, sin_identidad: 0 },
    { empresa: 'prodelco', moneda: 'PEN', operaciones: 1, capital: 8000, primeras: 0, posteriores: 1, sin_identidad: 0 },
  ]
  return {
    version: 1, modo: 'sombra', habilitada: true, mes, hasta: fin > hoy ? hoy : fin, hoy,
    generado_en: `${hoy}T12:00:00Z`, mes_sellado: mes.slice(0, 7) < hoy.slice(0, 7),
    produccion,
    tipos_capital: produccion.map(r => ({ ...r, tipo_capital: r.empresa === 'avance' ? 'contrato_nuevo' : 'cooperativa' })),
    atribucion: produccion.map(r => ({ ...r, analista_id: 'a0000000-0000-4000-8000-000000000001', analista_nombre: 'Analista de ejemplo' })),
    personas: { total: 3, una_empresa: 1, dos_empresas: 1, tres_empresas: 1, fuentes_sin_identidad: 0,
      fuentes_coherentes: 5, fuentes_contradictorias: 0, fuentes_sin_enlace: 0,
      por_empresa: [{ empresa: 'avance', personas: 2 }, { empresa: 'qorilazo', personas: 2 }, { empresa: 'prodelco', personas: 2 }],
    },
    conversion: { divisor: 20, numerador: 3.15, tasa_pct: 15.75, factor_referido: 0.15, cierres: 3, renovaciones: 1, upgrades: 0, anulados: 0 },
    vencimientos: [{ empresa: 'qorilazo', moneda: 'PEN', operaciones: 1, capital: 6000 }],
    oportunidades: [{ empresa: 'avance', personas: 1 }, { empresa: 'qorilazo', personas: 1 }, { empresa: 'prodelco', personas: 1 }],
    conciliacion: produccion.map(r => ({ empresa: r.empresa, moneda: r.moneda,
      capital_nucleo: r.capital, capital_informe: r.capital, operaciones_nucleo: r.operaciones, operaciones_informe: r.operaciones,
      diferencia_capital: 0, diferencia_operaciones: 0, diferencia_atribucion: 0,
    })), fuentes_duplicadas: 0,
  }
}
