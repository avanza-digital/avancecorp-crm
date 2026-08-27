// Mapper y espejo demo de crm.metricas_vendedores_fn: join con el roster (el
// payload no trae nombres por diseño), ceros para el miembro sin fila, y la
// ventana operativa de 45 días aplicada también en demo.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  MetricasVendedoresSchema,
  mapearMetricasVendedores,
  metricasVendedoresDesdeAmbito,
  textoConversionOperativa,
  ventanaConversionEnPalabras,
  type MetricasVendedoresPayload,
} from './metricas-vendedores'
import { derivarConversionMensual } from './demo-conversion-mensual'
import type { Lead, Miembro } from './tipos'

const AHORA = Date.parse('2026-08-09T15:00:00Z')
const DIA = 86_400_000
const iso = (ms: number): string => new Date(ms).toISOString()

const VEND1: Miembro = { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', supervisor_id: 's-1', activo: true }
const VEND2: Miembro = { perfil_id: 'v-2', nombre_completo: 'JUAN PEREZ', rol_crm: 'vendedor', supervisor_id: 's-1', activo: true }
const SUP: Miembro = { perfil_id: 's-1', nombre_completo: 'SUPERVISORA UNO', rol_crm: 'supervisor', supervisor_id: null, activo: true }
const EQUIPO = [SUP, VEND1, VEND2]

function payload(over: Record<string, unknown> = {}): MetricasVendedoresPayload {
  const r = v.safeParse(MetricasVendedoresSchema, {
    version: 1,
    generado_en: iso(AHORA),
    ventana_convertidos_dias: 45,
    peso_referido: 0.15,
    vendedores: [],
    equipos: [],
    ...over,
  })
  if (!r.success) throw new Error('payload de prueba fuera de contrato')
  return r.output
}

function fila(over: Record<string, unknown> = {}) {
  return {
    vendedor_id: 'v-1',
    rol_crm: 'vendedor',
    activo: true,
    activos: 3,
    capital_pen: 30_000,
    capital_usd: 0,
    convertidos: 1,
    conversion_pct: 25,
    operaciones_cartera: 0,
    nucleo_divisor: 4,
    nucleo_numerador: 1,
    nucleo_conversion_pct: 25,
    sin_tocar: 2,
    dias_sin_actividad_max: 4.5,
    ...over,
  }
}

function filaEquipo(over: Record<string, unknown> = {}) {
  return {
    supervisor_id: 's-1',
    vendedores: 2,
    activos: 5,
    capital_pen: 50_000,
    capital_usd: 1_000,
    convertidos: 2,
    conversion_pct: 25,
    operaciones_cartera: 0,
    nucleo_divisor: 4,
    nucleo_numerador: 1,
    nucleo_conversion_pct: 25,
    parkeados: 3,
    ...over,
  }
}

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: `l-${Math.random().toString(36).slice(2, 8)}`,
    nombre_completo: 'LEAD DEMO',
    telefono: '+51987654321',
    etapa: 'contactado',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: iso(AHORA - DIA * 3),
    activo: true,
    ...over,
  }
}

describe('mapearMetricasVendedores', () => {
  it('une por id con el roster, rellena en ceros al que no tiene fila y ordena por capital PEN', () => {
    const conFilas = payload({
      vendedores: [fila({ vendedor_id: 'v-1', capital_pen: 30_000 })],
    })
    const { filas } = mapearMetricasVendedores(conFilas, [VEND2, VEND1], EQUIPO)
    expect(filas.map((f) => f.m.perfil_id)).toEqual(['v-1', 'v-2'])
    expect(filas[0]).toMatchObject({ capitalPEN: 30_000, conversion: 25, conversionDisponible: true, sinTocar: 2 })
    expect(filas[1]).toMatchObject({
      activos: 0,
      capitalPEN: 0,
      conversion: null,
      conversionDisponible: false,
      operacionesCartera: null,
      divisorConversion: null,
      numeradorConversion: null,
      diasSinActividadMax: 0,
    })
    expect(filas[1]?.m.nombre_completo).toBe('JUAN PEREZ') // el nombre sale del roster, no del payload
  })

  it('usa el porcentaje EXACTO del núcleo: preserva NULL, decimales, cartera y >100', () => {
    const exacta = payload({
      vendedores: [fila({
        conversion_pct: 138,
        operaciones_cartera: '4',
        nucleo_divisor: '8',
        nucleo_numerador: '11.0104',
        nucleo_conversion_pct: '137.63',
      })],
    })
    const mapeada = mapearMetricasVendedores(exacta, [VEND1], EQUIPO).filas[0]
    expect(mapeada).toMatchObject({
      conversion: 137.63,
      operacionesCartera: 4,
      divisorConversion: 8,
      numeradorConversion: 11.0104,
    })
    expect(textoConversionOperativa(mapeada?.conversion ?? null)).toBe('137.63%')

    const sinDivisor = payload({
      vendedores: [fila({
        conversion_pct: 0,
        nucleo_divisor: 0,
        nucleo_numerador: 4,
        nucleo_conversion_pct: null,
        operaciones_cartera: 4,
      })],
    })
    const nula = mapearMetricasVendedores(sinDivisor, [VEND1], EQUIPO).filas[0]
    expect(nula?.conversion).toBeNull()
    expect(nula?.operacionesCartera).toBe(4)
    expect(textoConversionOperativa(nula?.conversion ?? null)).toBe('—')
  })

  it('no infiere la muestra desde activos: divisor 0 con activos es NULL y divisor >0 sin activos conserva 9.3%', () => {
    const matriz = payload({
      vendedores: [
        fila({
          vendedor_id: 'v-1',
          activos: 3,
          operaciones_cartera: 4,
          nucleo_divisor: 0,
          nucleo_numerador: 4,
          nucleo_conversion_pct: null,
        }),
        fila({
          vendedor_id: 'v-2',
          activos: 0,
          operaciones_cartera: 0,
          nucleo_divisor: 10,
          nucleo_numerador: 0.93,
          nucleo_conversion_pct: 9.3,
        }),
      ],
    })
    const porId = new Map(
      mapearMetricasVendedores(matriz, [VEND1, VEND2], EQUIPO).filas
        .map((f) => [f.m.perfil_id, f]),
    )
    expect(porId.get('v-1')).toMatchObject({ activos: 3, divisorConversion: 0, conversion: null })
    expect(porId.get('v-2')).toMatchObject({ activos: 0, divisorConversion: 10, conversion: 9.3 })
    expect(textoConversionOperativa(porId.get('v-2')?.conversion ?? null)).toBe('9.30%')
  })

  it('rechaza ids duplicados antes del Map: ninguna fila puede ganar por orden', () => {
    const base = {
      version: 1,
      generado_en: iso(AHORA),
      ventana_convertidos_dias: 45,
      peso_referido: 0.15,
    }
    expect(v.safeParse(MetricasVendedoresSchema, {
      ...base,
      vendedores: [fila(), fila({ capital_pen: 99_000 })],
      equipos: [],
    }).success).toBe(false)
    expect(v.safeParse(MetricasVendedoresSchema, {
      ...base,
      vendedores: [],
      equipos: [filaEquipo(), filaEquipo({ capital_pen: 99_000 })],
    }).success).toBe(false)
  })

  it('valida la coherencia exacta divisor/numerador/pct y admite NULL solo con divisor 0', () => {
    const parsea = (lectura: Record<string, unknown>) => v.safeParse(MetricasVendedoresSchema, {
      version: 1,
      generado_en: iso(AHORA),
      ventana_convertidos_dias: 45,
      vendedores: [fila(lectura)],
      equipos: [],
    }).success

    expect(parsea({ nucleo_divisor: 0, nucleo_numerador: 4, nucleo_conversion_pct: null })).toBe(true)
    expect(parsea({ nucleo_divisor: 0, nucleo_numerador: 4, nucleo_conversion_pct: 0 })).toBe(false)
    expect(parsea({ nucleo_divisor: 10, nucleo_numerador: 0.93, nucleo_conversion_pct: 9.3 })).toBe(true)
    expect(parsea({ nucleo_divisor: 10, nucleo_numerador: 0.1005, nucleo_conversion_pct: 1.01 })).toBe(true)
    expect(parsea({ nucleo_divisor: 8, nucleo_numerador: 11.0104, nucleo_conversion_pct: 137.63 })).toBe(true)
    expect(parsea({ nucleo_divisor: 8, nucleo_numerador: 11.0104, nucleo_conversion_pct: 137.6 })).toBe(false)
    expect(parsea({ nucleo_divisor: 8, nucleo_numerador: 11.0104, nucleo_conversion_pct: null })).toBe(false)

    expect(v.safeParse(MetricasVendedoresSchema, {
      version: 1,
      generado_en: iso(AHORA),
      ventana_convertidos_dias: 45,
      vendedores: [],
      equipos: [filaEquipo({
        nucleo_divisor: 8,
        nucleo_numerador: 11.0104,
        nucleo_conversion_pct: 137.6,
      })],
    }).success).toBe(false)
  })

  it('acepta colecciones parciales y campos futuros, pero no fabrica equipos ni conversiones ausentes', () => {
    const parcial = payload({
      clave_futura: 'compatible',
      vendedores: [fila({ vendedor_id: 'fuera-del-roster', clave_futura: 1 })],
      equipos: [],
    })
    const mapeada = mapearMetricasVendedores(parcial, [VEND1], EQUIPO)
    expect(mapeada.equipos).toEqual([])
    expect(mapeada.filas[0]).toMatchObject({
      conversion: null,
      conversionDisponible: false,
      operacionesCartera: null,
      divisorConversion: null,
      numeradorConversion: null,
    })
    expect(payload({ vendedores: [], equipos: [] })).toBeDefined()
  })

  it('rechaza una fila sin los campos exactos del núcleo en vez de usar el entero heredado', () => {
    const { operaciones_cartera: _operaciones, nucleo_divisor: _divisor,
      nucleo_numerador: _numerador, nucleo_conversion_pct: _pct, ...vieja } = fila()
    expect(v.safeParse(MetricasVendedoresSchema, {
      version: 1,
      generado_en: iso(AHORA),
      ventana_convertidos_dias: 45,
      peso_referido: 0.15,
      vendedores: [vieja],
      equipos: [],
    }).success).toBe(false)
  })

  it('la deriva local envejece el reloj de actividad — y el centinela del sin-abiertos NO', () => {
    // «Última actividad hace X» sale de esta cifra congelada en la foto del
    // RPC; sin deriva se queda clavada entre refetches (y en segundo plano el
    // intervalo ni corre). Mutantes que deben morir aquí: quitar `+ deriva`,
    // y envejecer también al que no tiene abiertos (su 0 significa «sin reloj
    // que mirar» — la UI dice 'Sin leads abiertos', no un instante).
    const conFilas = payload({
      vendedores: [
        fila({ vendedor_id: 'v-1', activos: 3, dias_sin_actividad_max: 2 / 1440 }),
        fila({ vendedor_id: 'v-2', capital_pen: 0, activos: 0, dias_sin_actividad_max: 0 }),
      ],
    })
    const { filas } = mapearMetricasVendedores(conFilas, [VEND1, VEND2], EQUIPO, 40 / 1440)
    expect(filas[0]?.diasSinActividadMax).toBeCloseTo(42 / 1440)
    expect(filas[1]?.diasSinActividadMax).toBe(0)

    const sinDeriva = mapearMetricasVendedores(conFilas, [VEND1], EQUIPO)
    expect(sinDeriva.filas[0]?.diasSinActividadMax).toBeCloseTo(2 / 1440)
    const negativa = mapearMetricasVendedores(conFilas, [VEND1], EQUIPO, -1)
    expect(negativa.filas[0]?.diasSinActividadMax).toBeCloseTo(2 / 1440)
  })

  it('la comparativa une supervisores con el roster completo y descarta filas sin miembro', () => {
    const conEquipos = payload({
      equipos: [
        {
          supervisor_id: 's-1', vendedores: 2, activos: 5,
          capital_pen: 50_000, capital_usd: 1_000, convertidos: 2,
          conversion_pct: 29,
          operaciones_cartera: '4', nucleo_divisor: '8',
          nucleo_numerador: '11.0104', nucleo_conversion_pct: '137.63',
          parkeados: 3,
        },
        {
          supervisor_id: 's-fantasma', vendedores: 1, activos: 1,
          capital_pen: 99_000, capital_usd: 0, convertidos: 0,
          conversion_pct: 0,
          operaciones_cartera: 0, nucleo_divisor: 0,
          nucleo_numerador: 0, nucleo_conversion_pct: null,
          parkeados: 0,
        },
      ],
    })
    const { equipos } = mapearMetricasVendedores(conEquipos, [], EQUIPO)
    expect(equipos).toHaveLength(1)
    expect(equipos[0]).toMatchObject({
      vendedores: 2,
      activos: 5,
      capitalPEN: 50_000,
      capitalUSD: 1_000,
      conversion: 137.63,
      conversionDisponible: true,
      operacionesCartera: 4,
      divisorConversion: 8,
      numeradorConversion: 11.0104,
      parkeados: 3,
    })
    expect(equipos[0]?.supervisor.nombre_completo).toBe('SUPERVISORA UNO')
  })

  it('la comparativa preserva NULL y rechaza equipos sin el núcleo exacto', () => {
    const nula = payload({
      equipos: [{
        supervisor_id: 's-1', vendedores: 2, activos: 0,
        capital_pen: 0, capital_usd: 0, convertidos: 0,
        conversion_pct: 0,
        operaciones_cartera: 4, nucleo_divisor: 0,
        nucleo_numerador: 4, nucleo_conversion_pct: null,
        parkeados: 0,
      }],
    })
    expect(mapearMetricasVendedores(nula, [], EQUIPO).equipos[0]).toMatchObject({
      conversion: null,
      operacionesCartera: 4,
    })

    expect(v.safeParse(MetricasVendedoresSchema, {
      version: 1,
      generado_en: iso(AHORA),
      ventana_convertidos_dias: 45,
      vendedores: [],
      equipos: [{
        supervisor_id: 's-1', vendedores: 2, activos: 0,
        capital_pen: 0, capital_usd: 0, convertidos: 0,
        conversion_pct: 0, parkeados: 0,
      }],
    }).success).toBe(false)
  })
})

describe('metricasVendedoresDesdeAmbito — foto operativa + núcleo demo mensual', () => {
  it('sin espejo mensual conserva la foto operativa, pero no publica la vieja conversión de 45 días', () => {
    const leads = [
      lead({ id: 'l-abierto' }),
      lead({ id: 'l-cierre-nuevo', etapa: 'convertido', convertido_en: iso(AHORA - DIA * 10) }),
      lead({ id: 'l-cierre-viejo', etapa: 'convertido', convertido_en: iso(AHORA - DIA * 60) }),
    ]
    const espejo = metricasVendedoresDesdeAmbito([VEND1], EQUIPO, leads, [], AHORA)
    expect(espejo.filas[0]).toMatchObject({
      convertidos: 1,
      conversion: null,
      conversionDisponible: false,
      operacionesCartera: null,
      divisorConversion: null,
      activos: 1,
    })
    expect(espejo.equipos[0]).toMatchObject({
      convertidos: 1,
      conversion: null,
      conversionDisponible: false,
    })
    expect(espejo.mesMetrica).toBeNull()
  })

  it('consume el espejo mensual canónico y no recalcula la tasa con los leads locales', () => {
    const mensual = derivarConversionMensual(
      AHORA,
      { alcance: 'equipo', actorId: 's-1' },
      [{
        leadId: 'episodio-canonico',
        analistaId: 'v-1',
        asignadoHaceMeses: 0,
        origen: 'landing',
        resultado: 'convertido',
        resultadoHaceMeses: 0,
      }],
      [
        { analistaId: 'v-1', supervisorId: 's-1' },
        { analistaId: 'v-2', supervisorId: 's-1' },
      ],
    )
    // La foto local contiene tres leads y por tanto daría 33 % con la fórmula
    // retirada. El mensual canónico dice 1/1 = 100.00 % y debe ganar.
    const espejo = metricasVendedoresDesdeAmbito(
      [VEND1],
      EQUIPO,
      [lead(), lead({ id: 'l-2' }), lead({ id: 'l-3', etapa: 'convertido' })],
      [],
      AHORA,
      mensual,
    )
    expect(espejo.filas[0]).toMatchObject({
      convertidos: 1,
      conversion: 100,
      conversionDisponible: true,
      operacionesCartera: 0,
      divisorConversion: 1,
      numeradorConversion: 1,
    })
    expect(espejo.equipos[0]).toMatchObject({
      convertidos: 1,
      conversion: 100,
      conversionDisponible: true,
      operacionesCartera: 0,
      divisorConversion: 1,
      numeradorConversion: 1,
    })
    expect(espejo.mesMetrica).toBe('2026-08-01')
  })

  it('un mensual parcial o con extras no se publica como total del equipo', () => {
    const parcial = derivarConversionMensual(
      AHORA,
      { alcance: 'equipo', actorId: 's-1' },
      [{
        leadId: 'solo-v1',
        analistaId: 'v-1',
        asignadoHaceMeses: 0,
        origen: 'landing',
        resultado: 'convertido',
        resultadoHaceMeses: 0,
      }],
      [{ analistaId: 'v-1', supervisorId: 's-1' }],
    )
    const espejo = metricasVendedoresDesdeAmbito(
      [VEND1, VEND2],
      EQUIPO,
      [],
      [],
      AHORA,
      parcial,
    )

    expect(espejo.filas.find((fila) => fila.m.perfil_id === 'v-1')).toMatchObject({
      conversionDisponible: true,
      conversion: 100,
    })
    expect(espejo.filas.find((fila) => fila.m.perfil_id === 'v-2')).toMatchObject({
      conversionDisponible: false,
      conversion: null,
      operacionesCartera: null,
    })
    expect(espejo.equipos[0]).toMatchObject({
      conversionDisponible: false,
      conversion: null,
      operacionesCartera: null,
      divisorConversion: null,
      numeradorConversion: null,
    })
  })

  it('capital por moneda jamás se suma y los parkeados van aparte', () => {
    const leads = [
      lead({ monto_estimado: 1_000 }),
      lead({ id: 'l-usd', monto_estimado: 500, moneda: 'USD' }),
      lead({ id: 'l-parkeado', vendedor_id: null, asignado_supervisor_id: 's-1', monto_estimado: 700 }),
    ]
    const espejo = metricasVendedoresDesdeAmbito([VEND1], EQUIPO, leads, [], AHORA)
    expect(espejo.filas[0]).toMatchObject({ capitalPEN: 1_000, capitalUSD: 500 })
    expect(espejo.equipos[0]).toMatchObject({ capitalPEN: 1_000, capitalUSD: 500, parkeados: 1 })
  })
})

describe('ventanaConversionEnPalabras (F3, H9/D1)', () => {
  it('nombra el MES cuando el servidor declara mes_calendario — el rótulo dice lo que la cifra mide', () => {
    expect(ventanaConversionEnPalabras('2026-08-01')).toBe('agosto de 2026')
    expect(ventanaConversionEnPalabras('2026-01-01')).toBe('enero de 2026')
  })

  it('conserva «45 días» sin declaración (espejo demo o servidor previo a F2.4): esa sigue siendo SU verdad', () => {
    expect(ventanaConversionEnPalabras(null)).toBe('45 días')
  })

  it('el mapper solo afirma el mes con la declaración completa — media declaración no es declaración', () => {
    const base = payload()
    expect(mapearMetricasVendedores({ ...base, ventana_metrica: 'mes_calendario', mes_metrica: '2026-08-01' }, [VEND1], EQUIPO).mesMetrica).toBe('2026-08-01')
    expect(mapearMetricasVendedores({ ...base, ventana_metrica: 'mes_calendario' }, [VEND1], EQUIPO).mesMetrica).toBeNull()
    expect(mapearMetricasVendedores(base, [VEND1], EQUIPO).mesMetrica).toBeNull()
  })
})
