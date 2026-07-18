import type {
  MetricaDistribucionAnalista,
  MetricasDistribucionLeads,
  MetricasPorRepartir,
  RangoDistribucionAnalista,
} from './metricas-distribucion'

const RANGOS = [
  ['pen_0_1000', 'Hasta S/ 1 mil', 0, 1000],
  ['pen_1000_5000', 'S/ 1 mil a 5 mil', 1000, 5000],
  ['pen_5000_10000', 'S/ 5 mil a 10 mil', 5000, 10000],
  ['pen_10000_20000', 'S/ 10 mil a 20 mil', 10000, 20000],
  ['pen_20000_50000', 'S/ 20 mil a 50 mil', 20000, 50000],
  ['pen_50000_100000', 'S/ 50 mil a 100 mil', 50000, 100000],
  ['pen_mas_100000', 'Más de S/ 100 mil', 100000, null],
  ['sin_monto', 'Sin monto válido', null, null],
] as const

type RangoCola = MetricasPorRepartir['total']['pen']['rangos'][number]

function rangosAnalista(
  destacados: Record<
    string,
    {
      cartera: number
      capital: number
      convertidos: number
      descartados: number
      recibidos?: number
    }
  > = {},
): RangoDistribucionAnalista[] {
  return RANGOS.map(([rangoId]) => {
    const dato = destacados[rangoId] ?? {
      cartera: 0,
      capital: 0,
      convertidos: 0,
      descartados: 0,
    }
    const recibidos = dato.recibidos ?? dato.convertidos + dato.descartados
    return {
      rango_id: rangoId,
      cartera_actual: { episodios: dato.cartera, capital: dato.capital },
      cohorte: {
        episodios_recibidos: recibidos,
        leads_unicos_recibidos: recibidos,
        convertidos: dato.convertidos,
        descartados: dato.descartados,
        leads_unicos_resueltos: dato.convertidos + dato.descartados,
      },
    }
  })
}

function rangosCola(
  destacados: Record<string, { cantidad: number; capital: number }> = {},
): RangoCola[] {
  return RANGOS.map(([rangoId]) => ({
    rango_id: rangoId,
    cantidad: destacados[rangoId]?.cantidad ?? 0,
    capital: destacados[rangoId]?.capital ?? 0,
  }))
}

const ANA: MetricaDistribucionAnalista = {
  analista_id: '11111111-1111-4111-8111-111111111111',
  nombre: 'Ana Torres',
  rol: 'vendedor',
  supervisor_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  supervisor_nombre: 'César Ruiz',
  activo: true,
  disponible_para_recibir: true,
  capacidad: { objetivo: 20, carga_activa: 14, carga_pen: 12, carga_usd: 2 },
  pen: {
    cartera_actual: { episodios: 12, capital: 78_000 },
    cohorte: {
      episodios_recibidos: 22,
      leads_unicos_recibidos: 21,
      convertidos: 10,
      descartados: 4,
      ciclos_resueltos: 14,
      leads_unicos_resueltos: 14,
    },
    rangos: rangosAnalista({
      pen_0_1000: { cartera: 2, capital: 1_500, convertidos: 1, descartados: 1, recibidos: 3 },
      pen_1000_5000: { cartera: 4, capital: 12_000, convertidos: 4, descartados: 1, recibidos: 7 },
      pen_5000_10000: { cartera: 3, capital: 24_000, convertidos: 3, descartados: 1, recibidos: 5 },
      pen_10000_20000: { cartera: 2, capital: 30_000, convertidos: 1, descartados: 1, recibidos: 4 },
      pen_20000_50000: { cartera: 1, capital: 10_500, convertidos: 1, descartados: 0, recibidos: 3 },
    }),
  },
  usd_no_segmentado: {
    cartera_actual_episodios: 2,
    cartera_actual_capital: 18_000,
    cohorte_episodios_recibidos: 4,
    cohorte_leads_unicos: 4,
    convertidos: 2,
    descartados: 1,
  },
  operacion: {
    cohorte_episodios: 22,
    contactos_asignacion: 19,
    sla_asignacion_evaluables: 18,
    sla_asignacion_en_24h: 15,
    primer_contacto_asignacion_mediana_minutos: 175,
    transferidos: 2,
    parqueados: 1,
    desactivados: 0,
    sin_tocar_actual: 1,
    estancados_actual: 2,
  },
}

const BRUNO: MetricaDistribucionAnalista = {
  ...ANA,
  analista_id: '22222222-2222-4222-8222-222222222222',
  nombre: 'Bruno Díaz',
  capacidad: { objetivo: 18, carga_activa: 9, carga_pen: 8, carga_usd: 1 },
  pen: {
    cartera_actual: { episodios: 8, capital: 55_000 },
    cohorte: {
      episodios_recibidos: 18,
      leads_unicos_recibidos: 17,
      convertidos: 7,
      descartados: 5,
      ciclos_resueltos: 12,
      leads_unicos_resueltos: 11,
    },
    rangos: rangosAnalista({
      pen_1000_5000: { cartera: 3, capital: 10_000, convertidos: 2, descartados: 2, recibidos: 6 },
      pen_5000_10000: { cartera: 2, capital: 15_000, convertidos: 2, descartados: 1, recibidos: 5 },
      pen_10000_20000: { cartera: 2, capital: 25_000, convertidos: 2, descartados: 1, recibidos: 4 },
      pen_20000_50000: { cartera: 1, capital: 5_000, convertidos: 1, descartados: 1, recibidos: 3 },
    }),
  },
  usd_no_segmentado: {
    cartera_actual_episodios: 1,
    cartera_actual_capital: 9_000,
    cohorte_episodios_recibidos: 3,
    cohorte_leads_unicos: 3,
    convertidos: 1,
    descartados: 1,
  },
  operacion: {
    cohorte_episodios: 18,
    contactos_asignacion: 15,
    sla_asignacion_evaluables: 15,
    sla_asignacion_en_24h: 11,
    primer_contacto_asignacion_mediana_minutos: 285,
    transferidos: 2,
    parqueados: 0,
    desactivados: 0,
    sin_tocar_actual: 2,
    estancados_actual: 2,
  },
}

const CAMILA: MetricaDistribucionAnalista = {
  ...ANA,
  analista_id: '33333333-3333-4333-8333-333333333333',
  nombre: 'Camila Rojas',
  capacidad: { objetivo: 16, carga_activa: 4, carga_pen: 3, carga_usd: 1 },
  pen: {
    cartera_actual: { episodios: 3, capital: 29_500 },
    cohorte: {
      episodios_recibidos: 16,
      leads_unicos_recibidos: 15,
      convertidos: 5,
      descartados: 6,
      ciclos_resueltos: 11,
      leads_unicos_resueltos: 10,
    },
    rangos: rangosAnalista({
      pen_5000_10000: { cartera: 1, capital: 7_500, convertidos: 2, descartados: 2, recibidos: 6 },
      pen_10000_20000: { cartera: 1, capital: 12_000, convertidos: 2, descartados: 2, recibidos: 5 },
      pen_20000_50000: { cartera: 1, capital: 10_000, convertidos: 1, descartados: 2, recibidos: 5 },
    }),
  },
  usd_no_segmentado: {
    cartera_actual_episodios: 1,
    cartera_actual_capital: 11_000,
    cohorte_episodios_recibidos: 2,
    cohorte_leads_unicos: 2,
    convertidos: 0,
    descartados: 1,
  },
  operacion: {
    cohorte_episodios: 16,
    contactos_asignacion: 11,
    sla_asignacion_evaluables: 13,
    sla_asignacion_en_24h: 7,
    primer_contacto_asignacion_mediana_minutos: 510,
    transferidos: 3,
    parqueados: 1,
    desactivados: 0,
    sin_tocar_actual: 2,
    estancados_actual: 3,
  },
}

const DIEGO: MetricaDistribucionAnalista = {
  ...ANA,
  analista_id: '44444444-4444-4444-8444-444444444444',
  nombre: 'Diego Vega',
  capacidad: { objetivo: 12, carga_activa: 5, carga_pen: 4, carga_usd: 1 },
  pen: {
    cartera_actual: { episodios: 4, capital: 35_000 },
    cohorte: {
      episodios_recibidos: 17,
      leads_unicos_recibidos: 15,
      convertidos: 4,
      descartados: 8,
      ciclos_resueltos: 12,
      leads_unicos_resueltos: 11,
    },
    rangos: rangosAnalista({
      pen_1000_5000: { cartera: 1, capital: 3_500, convertidos: 1, descartados: 2, recibidos: 5 },
      pen_5000_10000: { cartera: 1, capital: 7_500, convertidos: 1, descartados: 2, recibidos: 4 },
      pen_10000_20000: { cartera: 1, capital: 14_000, convertidos: 1, descartados: 2, recibidos: 4 },
      pen_20000_50000: { cartera: 1, capital: 10_000, convertidos: 1, descartados: 2, recibidos: 4 },
    }),
  },
  usd_no_segmentado: {
    cartera_actual_episodios: 1,
    cartera_actual_capital: 8_000,
    cohorte_episodios_recibidos: 2,
    cohorte_leads_unicos: 2,
    convertidos: 0,
    descartados: 1,
  },
  operacion: {
    cohorte_episodios: 17,
    contactos_asignacion: 10,
    sla_asignacion_evaluables: 14,
    sla_asignacion_en_24h: 6,
    primer_contacto_asignacion_mediana_minutos: 780,
    transferidos: 2,
    parqueados: 2,
    desactivados: 0,
    sin_tocar_actual: 3,
    estancados_actual: 4,
  },
}

function fechaSiguiente(fecha: string): string {
  const valor = new Date(`${fecha}T00:00:00Z`)
  valor.setUTCDate(valor.getUTCDate() + 1)
  return valor.toISOString().slice(0, 10)
}

export function metricasDistribucionDemo(
  desde: string,
  hasta: string,
): MetricasDistribucionLeads {
  return {
    version: 2,
    generado_en: new Date().toISOString(),
    cohorte: {
      desde_inclusivo: desde,
      hasta_inclusivo: hasta,
      hasta_exclusivo: fechaSiguiente(hasta),
      criterio: 'episodio_asignado_en',
      criterio_sla_global: 'ciclo_sla_global_iniciado_en',
      politica_pausas: 'SIN_DESCUENTO',
      zona_horaria: 'America/Lima',
    },
    alcances: {
      matriz: 'PEN',
      capacidad: 'TODAS_LAS_MONEDAS',
      montos: 'SEPARADOS_SIN_CONVERSION',
      sla_principal: 'GLOBAL_POR_CICLO',
      sla_operativo: 'POR_EPISODIO_DE_ASIGNACION',
    },
    rangos: RANGOS.map(([id, etiqueta, desdeExclusivo, hastaInclusivo], indice) => ({
      id,
      orden: indice + 1,
      etiqueta,
      desde_exclusivo: desdeExclusivo,
      hasta_inclusivo: hastaInclusivo,
    })),
    resumen: {
      leads_operativos_actuales: 37,
      asignados_actuales: 32,
      por_repartir_actuales: 5,
      capital_pen_asignado_actual: 197_500,
      capital_usd_asignado_actual: 46_000,
      cohorte_episodios: 73,
      cohorte_leads_unicos: 68,
      convertidos_pen: 26,
      descartados_pen: 23,
      sla_global_ciclos_cohorte: 68,
      sla_global_leads_unicos_cohorte: 64,
      sla_global_contactos: 58,
      sla_global_evaluables: 60,
      sla_global_en_24h: 43,
      primer_contacto_global_mediana_minutos: 320,
      sla_global_sin_contacto_vencidos_actuales: 7,
      reasignaciones_cohorte: 9,
    },
    analistas: [ANA, BRUNO, CAMILA, DIEGO],
    por_repartir: {
      total: {
        carga_total: 5,
        pen: {
          cantidad: 4,
          capital: 45_000,
          rangos: rangosCola({
            pen_1000_5000: { cantidad: 1, capital: 4_000 },
            pen_5000_10000: { cantidad: 1, capital: 8_000 },
            pen_10000_20000: { cantidad: 1, capital: 15_000 },
            pen_20000_50000: { cantidad: 1, capital: 18_000 },
          }),
        },
        usd: { cantidad: 1, capital: 7_500 },
      },
      global: {
        responsabilidad: 'gerencia',
        carga_total: 2,
        pen: {
          cantidad: 2,
          capital: 12_000,
          rangos: rangosCola({
            pen_1000_5000: { cantidad: 1, capital: 4_000 },
            pen_5000_10000: { cantidad: 1, capital: 8_000 },
          }),
        },
        usd: { cantidad: 0, capital: 0 },
      },
      bandejas: [
        {
          supervisor_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          supervisor_nombre: 'César Ruiz',
          supervisor_activo: true,
          carga_total: 3,
          pen: {
            cantidad: 2,
            capital: 33_000,
            rangos: rangosCola({
              pen_10000_20000: { cantidad: 1, capital: 15_000 },
              pen_20000_50000: { cantidad: 1, capital: 18_000 },
            }),
          },
          usd: { cantidad: 1, capital: 7_500 },
        },
      ],
    },
    calidad: {
      episodios_aproximados_actuales: 0,
      episodios_aproximados_cohorte: 2,
      episodios_sin_monto_actuales: 0,
      episodios_sin_monto_cohorte: 0,
      ciclos_sla_global_aproximados_cohorte: 2,
    },
  }
}
