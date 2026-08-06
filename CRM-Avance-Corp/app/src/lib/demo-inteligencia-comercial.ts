import type { MetricasConversiones } from './metricas-conversiones'
import type { MetricasReuniones } from './metricas-reuniones'
import type { ConversionEquipoVendedor } from './conversion-equipo'
import type { ObjetivosPorVendedor } from './objetivos'
import type { SeriesComerciales } from './series-comerciales'

type PeriodoDemo = MetricasConversiones['periodo']

const MILISEGUNDOS_POR_DIA = 86_400_000
const ZONA_LIMA = 'America/Lima' as const

function diasPeriodo(desde: string, hasta: string): number {
  const diferencia = Date.parse(`${hasta}T00:00:00Z`) - Date.parse(`${desde}T00:00:00Z`)
  return Math.max(1, Math.round(diferencia / MILISEGUNDOS_POR_DIA) + 1)
}

function crearPeriodoDemo(desde: string, hasta: string): PeriodoDemo {
  return { desde, hasta, dias: diasPeriodo(desde, hasta), zona: ZONA_LIMA }
}

function tendenciaDemo(
  desde: string,
  hasta: string,
  puntos: ReadonlyArray<readonly [leads: number, clientes: number]>,
): NonNullable<MetricasConversiones['responsables']>[number]['tendencia_semanal'] {
  const inicioMs = Date.parse(`${desde}T00:00:00Z`)
  const totalDias = diasPeriodo(desde, hasta)
  return puntos.map(([leads, clientes], indice) => {
    const inicio = Math.floor((totalDias * indice) / puntos.length)
    const fin = Math.max(inicio, Math.floor((totalDias * (indice + 1)) / puntos.length) - 1)
    return {
      semana: indice + 1,
      desde: new Date(inicioMs + inicio * MILISEGUNDOS_POR_DIA).toISOString().slice(0, 10),
      hasta: new Date(inicioMs + fin * MILISEGUNDOS_POR_DIA).toISOString().slice(0, 10),
      leads,
      clientes,
      conversion_pct: leads > 0 ? Math.round((1000 * clientes) / leads) / 10 : null,
    }
  })
}

export function metricasConversionesDemo(
  desde: string,
  hasta: string,
): MetricasConversiones {
  const periodo = crearPeriodoDemo(desde, hasta)
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    periodo,
    cohorte: {
      leads: 184,
      asignados: 176,
      contactados: 139,
      reuniones_agendadas: 82,
      reuniones_realizadas: 58,
      propuestas: 37,
      clientes: 17,
      contratos: 17,
      descartados: 63,
      conversion_clientes_pct: 9.24,
      conversion_contratos_pct: 9.24,
      conversion_resueltos_pct: 27.59,
    },
    produccion: { clientes: 21, contratos: 21, capital_pen: 1_480_000, capital_usd: 96_000 },
    embudo: [
      { etapa: 'leads', cantidad: 184, pct_anterior: 100, pct_total: 100 },
      { etapa: 'contactados', cantidad: 139, pct_anterior: 75.54, pct_total: 75.54 },
      { etapa: 'reuniones_agendadas', cantidad: 82, pct_anterior: 58.99, pct_total: 44.57 },
      { etapa: 'reuniones_realizadas', cantidad: 58, pct_anterior: 70.73, pct_total: 31.52 },
      { etapa: 'propuestas', cantidad: 37, pct_anterior: 63.79, pct_total: 20.11 },
      { etapa: 'clientes', cantidad: 17, pct_anterior: 45.95, pct_total: 9.24 },
      { etapa: 'contratos', cantidad: 17, pct_anterior: 100, pct_total: 9.24 },
    ],
    origenes: [
      { origen: 'Meta Ads', leads: 76, contactados: 61, reuniones_agendadas: 38, reuniones_realizadas: 28, clientes: 10, contratos: 10, descartados: 24, conversion_clientes_pct: 13.16, conversion_contratos_pct: 13.16, conversion_resueltos_pct: 35.14, capital_pen: 720_000, capital_usd: 36_000 },
      { origen: 'Referido', leads: 43, contactados: 37, reuniones_agendadas: 24, reuniones_realizadas: 19, clientes: 5, contratos: 5, descartados: 12, conversion_clientes_pct: 11.63, conversion_contratos_pct: 11.63, conversion_resueltos_pct: 40, capital_pen: 460_000, capital_usd: 60_000 },
      { origen: 'Web', leads: 65, contactados: 41, reuniones_agendadas: 20, reuniones_realizadas: 11, clientes: 2, contratos: 2, descartados: 27, conversion_clientes_pct: 3.08, conversion_contratos_pct: 3.08, conversion_resueltos_pct: 10, capital_pen: 300_000, capital_usd: 0 },
    ],
    categorias: [
      { categoria: 'Capital de trabajo', leads: 92, clientes: 10, contratos: 10, descartados: 31, conversion_pct: 10.87 },
      { categoria: 'Inversión', leads: 58, clientes: 6, contratos: 6, descartados: 19, conversion_pct: 10.34 },
      { categoria: 'Ahorro', leads: 34, clientes: 1, contratos: 1, descartados: 13, conversion_pct: 2.94 },
    ],
    responsables: [
      { vendedor_id: 'demo-v1', leads: 42, contactados: 35, reuniones_realizadas: 18, clientes: 5, conversion_pct: 11.9, capital_pen: 360_000, capital_usd: 20_000, tendencia_semanal: tendenciaDemo(desde, hasta, [[11, 1], [10, 1], [11, 1], [10, 2]]) },
      { vendedor_id: 'demo-v2', leads: 37, contactados: 30, reuniones_realizadas: 14, clientes: 4, conversion_pct: 10.8, capital_pen: 290_000, capital_usd: 16_000, tendencia_semanal: tendenciaDemo(desde, hasta, [[10, 1], [9, 1], [9, 1], [9, 1]]) },
      { vendedor_id: 'demo-v3', leads: 34, contactados: 27, reuniones_realizadas: 12, clientes: 3, conversion_pct: 8.8, capital_pen: 250_000, capital_usd: 18_000, tendencia_semanal: tendenciaDemo(desde, hasta, [[9, 1], [8, 0], [9, 1], [8, 1]]) },
      { vendedor_id: 'demo-v4', leads: 29, contactados: 20, reuniones_realizadas: 7, clientes: 2, conversion_pct: 6.9, capital_pen: 210_000, capital_usd: 14_000, tendencia_semanal: tendenciaDemo(desde, hasta, [[8, 0], [7, 1], [7, 0], [7, 1]]) },
      { vendedor_id: 'demo-v5', leads: 24, contactados: 17, reuniones_realizadas: 5, clientes: 2, conversion_pct: 8.3, capital_pen: 200_000, capital_usd: 16_000, tendencia_semanal: tendenciaDemo(desde, hasta, [[6, 0], [6, 1], [6, 0], [6, 1]]) },
      { vendedor_id: 'demo-v6', leads: 18, contactados: 10, reuniones_realizadas: 2, clientes: 1, conversion_pct: 5.6, capital_pen: 170_000, capital_usd: 12_000, tendencia_semanal: tendenciaDemo(desde, hasta, [[5, 0], [4, 0], [5, 1], [4, 0]]) },
    ],
  }
}

export function seriesComercialesDemo(): SeriesComerciales {
  return {
    capital: [620_000, 710_000, 890_000, 960_000, 1_210_000, 1_480_000],
    leads: [142, 151, 159, 168, 176, 184],
    cierres: [10, 11, 12, 14, 16, 17],
    conversion: [7, 7.3, 7.5, 8.3, 9.1, 9.2],
  }
}

export function conversionEquipoDemo(): ConversionEquipoVendedor[] {
  return [
    { vendedorId: 'demo-v1', nombre: 'Ana Torres', supervisorNombre: 'María Salazar', leads: 42, contactados: 35, reunionesPactadas: 23, reunionesRealizadas: 18, clientes: 5, descartados: 14, conversionPct: 11.9 },
    { vendedorId: 'demo-v2', nombre: 'Bruno Díaz', supervisorNombre: 'María Salazar', leads: 37, contactados: 30, reunionesPactadas: 18, reunionesRealizadas: 14, clientes: 4, descartados: 12, conversionPct: 10.8 },
    { vendedorId: 'demo-v3', nombre: 'Carla Mendoza', supervisorNombre: 'José Rivas', leads: 34, contactados: 27, reunionesPactadas: 17, reunionesRealizadas: 12, clientes: 3, descartados: 13, conversionPct: 8.8 },
    { vendedorId: 'demo-v4', nombre: 'Diego Ramos', supervisorNombre: 'José Rivas', leads: 29, contactados: 20, reunionesPactadas: 11, reunionesRealizadas: 7, clientes: 2, descartados: 12, conversionPct: 6.9 },
    { vendedorId: 'demo-v5', nombre: 'Elena Vega', supervisorNombre: 'María Salazar', leads: 24, contactados: 17, reunionesPactadas: 8, reunionesRealizadas: 5, clientes: 2, descartados: 8, conversionPct: 8.3 },
    { vendedorId: 'demo-v6', nombre: 'Fabio León', supervisorNombre: 'José Rivas', leads: 18, contactados: 10, reunionesPactadas: 5, reunionesRealizadas: 2, clientes: 1, descartados: 4, conversionPct: 5.6 },
  ]
}

/**
 * Metas del mismo universo ficticio que `responsables`/`conversionEquipoDemo`.
 * Sus totales coinciden con la meta demo de Gerencia (S/ 1 MM y 27.67% en
 * promedio); no se reutilizan las metas operativas `d-v*`, porque pertenecen a
 * otro roster de demostración.
 */
export function metasConversionEquipoDemo(): ObjetivosPorVendedor {
  const metas = [
    ['demo-v1', 'demo-s1', 250_000, 25],
    ['demo-v2', 'demo-s1', 180_000, 28],
    ['demo-v3', 'demo-s2', 160_000, 30],
    ['demo-v4', 'demo-s2', 150_000, 27],
    ['demo-v5', 'demo-s1', 140_000, 28],
    ['demo-v6', 'demo-s2', 120_000, 28],
  ] as const
  return Object.fromEntries(metas.map(([vendedorId, supervisorId, capitalObjetivo, conversionObjetivo]) => [
    vendedorId,
    {
      vendedorId,
      supervisorId,
      capitalObjetivo,
      ventasObjetivo: 0,
      conversionObjetivo,
    },
  ]))
}

export function metricasReunionesDemo(desde: string, hasta: string): MetricasReuniones {
  const periodo = crearPeriodoDemo(desde, hasta)
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    periodo,
    resumen: {
      pactadas: 82,
      debieron_ocurrir: 73,
      realizadas: 58,
      no_concretadas: 15,
      no_show: 8,
      canceladas: 7,
      canceladas_sistema: 2,
      reprogramadas: 11,
      pendientes_cierre: 3,
      programadas_futuras: 9,
      pct_realizacion: 79.45,
      pct_asistencia: 87.88,
    },
    conversion: { leads_reunidos: 58, clientes: 17, contratos: 17, conversion_cliente_pct: 29.31, conversion_contrato_pct: 29.31, capital_pen: 1_180_000, capital_usd: 76_000 },
    modalidades: [
      { modalidad: 'virtual', pactadas: 49, debieron_ocurrir: 44, realizadas: 37, no_concretadas: 7, no_show: 4, canceladas: 3, reprogramadas: 6, pendientes_cierre: 1, pct_realizacion: 84.09, pct_asistencia: 90.24, leads_reunidos: 37, clientes: 11, contratos: 11, conversion_cliente_pct: 29.73, conversion_contrato_pct: 29.73, capital_pen: 690_000, capital_usd: 46_000 },
      { modalidad: 'presencial', pactadas: 33, debieron_ocurrir: 29, realizadas: 21, no_concretadas: 8, no_show: 4, canceladas: 4, reprogramadas: 5, pendientes_cierre: 2, pct_realizacion: 72.41, pct_asistencia: 84, leads_reunidos: 21, clientes: 6, contratos: 6, conversion_cliente_pct: 28.57, conversion_contrato_pct: 28.57, capital_pen: 490_000, capital_usd: 30_000 },
    ],
    origenes: [
      { origen: 'Meta Ads', pactadas: 38, realizadas: 28, no_show: 5, canceladas: 3, pct_realizacion: 77.78, leads_reunidos: 28, clientes: 10, contratos: 10, conversion_contrato_pct: 35.71 },
      { origen: 'Referido', pactadas: 24, realizadas: 19, no_show: 1, canceladas: 2, pct_realizacion: 86.36, leads_reunidos: 19, clientes: 5, contratos: 5, conversion_contrato_pct: 26.32 },
      { origen: 'Web', pactadas: 20, realizadas: 11, no_show: 2, canceladas: 2, pct_realizacion: 73.33, leads_reunidos: 11, clientes: 2, contratos: 2, conversion_contrato_pct: 18.18 },
    ],
    responsables: [
      { responsable_id: 'demo-1', nombre: 'Andrea Salas', rol: 'vendedor', supervisor_id: 'demo-s1', supervisor_nombre: 'Equipo Norte', pactadas: 29, realizadas: 23, no_show: 3, canceladas: 2, reprogramadas: 4, pendientes_cierre: 1, pct_realizacion: 82.14 },
      { responsable_id: 'demo-2', nombre: 'Luis Mendoza', rol: 'vendedor', supervisor_id: 'demo-s1', supervisor_nombre: 'Equipo Norte', pactadas: 27, realizadas: 20, no_show: 2, canceladas: 3, reprogramadas: 3, pendientes_cierre: 1, pct_realizacion: 80 },
      { responsable_id: 'demo-3', nombre: 'Camila Rojas', rol: 'vendedor', supervisor_id: 'demo-s2', supervisor_nombre: 'Equipo Sur', pactadas: 26, realizadas: 15, no_show: 3, canceladas: 2, reprogramadas: 4, pendientes_cierre: 1, pct_realizacion: 68.18 },
    ],
    resultados: [
      { resultado: 'Interesado', cantidad: 18 },
      { resultado: 'Seguimiento', cantidad: 15 },
      { resultado: 'Propuesta', cantidad: 13 },
      { resultado: 'Inicia registro', cantidad: 8 },
      { resultado: 'No interesado', cantidad: 4 },
    ],
  }
}
