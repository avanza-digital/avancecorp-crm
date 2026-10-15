import * as v from 'valibot'
import { describe, expect, it } from 'vitest'
import {
  AVISO_PLAZO_VENCIDO,
  PlazoCargaFijadoSchema,
  PlazosCargaMesSchema,
  accionDelMes,
  codigoDeError,
  conMayuscula,
  conPunto,
  errorUltimoDia,
  estadoDelPlazo,
  fechaMinimaPlazo,
  largoMotivoPlazo,
  lineaDecision,
  lineaDelPlazo,
  mesSinAnio,
  motivoPlazoValido,
  periodoDelMes,
  resumenPlazoFijado,
  type MesPlazoCarga,
  type PlazoCargaFijado,
} from './plazo-carga-mes'

/**
 * El ejemplo del contrato de `crm.plazos_carga_mes_fn` en DISENO.md §2, con
 * valores en lugar de los marcadores («…», «timestamptz», «texto») y con
 * `generado_en`, que el ejemplo no traía y la función SÍ devuelve: la prueba
 * del servidor exige la cabecera exacta `generado_en,hoy,meses,version,zona`
 * (supabase/scripts/plazo-carga-mes/prueba.sql).
 */
const EJEMPLO_DISENO = {
  version: 1,
  generado_en: '2026-10-14T15:05:00.123456+00:00',
  hoy: '2026-10-14',
  zona: 'America/Lima',
  meses: [{
    mes: '2026-09',
    mes_nombre: 'septiembre 2026',
    sellado: false,
    plazo_base_ultimo_dia: '2026-10-10',
    plazo_ultimo_dia: '2026-10-20',
    ampliado: true,
    decision: {
      ultimo_dia: '2026-10-20',
      motivo: 'Los analistas aún cargan ventas de setiembre',
      decidido_por: 'MIGUEL BRICEÑO',
      decidido_en: '2026-10-14T10:05:00-05:00',
    },
    reabrible: false,
    motivo_no_reabrible: 'El mes no está sellado.',
    ultima_reapertura: null,
  }],
}

/**
 * ESTADO DE PRODUCCIÓN el 14/10: setiembre se reabrió por script (sin fila en
 * `crm.reaperturas_mes`), nadie ha decidido su plazo y el base (10/10) ya pasó;
 * octubre está en curso con su plazo normal.
 */
const PRODUCCION_14_OCT = {
  version: 1,
  generado_en: '2026-10-14T15:00:00.123456+00:00',
  hoy: '2026-10-14',
  zona: 'America/Lima',
  meses: [
    {
      mes: '2026-09', mes_nombre: 'setiembre 2026', sellado: false,
      plazo_base_ultimo_dia: '2026-10-10', plazo_ultimo_dia: '2026-10-10', ampliado: false,
      decision: null, reabrible: false, motivo_no_reabrible: null, ultima_reapertura: null,
    },
    {
      mes: '2026-10', mes_nombre: 'octubre 2026', sellado: false,
      plazo_base_ultimo_dia: '2026-11-10', plazo_ultimo_dia: '2026-11-10', ampliado: false,
      decision: null, reabrible: false, motivo_no_reabrible: null, ultima_reapertura: null,
    },
  ],
}

const ACUSE = {
  ok: true,
  mes: '2026-09',
  ultimo_dia: '2026-10-20',
  plazo_hasta: '2026-10-21T05:00:00+00:00',
  reabierto: false,
  reapertura_id: null,
  acreditaciones_reevaluadas: 12,
  conflictos_identidad: 0,
  ventas_devueltas: [],
}

function mes(over: Partial<MesPlazoCarga> = {}): MesPlazoCarga {
  return {
    mes: '2026-09', mes_nombre: 'setiembre 2026', sellado: false,
    plazo_base_ultimo_dia: '2026-10-10', plazo_ultimo_dia: '2026-10-10', ampliado: false,
    decision: null, reabrible: false, motivo_no_reabrible: null, ultima_reapertura: null,
    ...over,
  }
}

describe('contrato de crm.plazos_carga_mes_fn (fail-closed)', () => {
  it('acepta el ejemplo del diseño', () => {
    const r = v.safeParse(PlazosCargaMesSchema, EJEMPLO_DISENO)
    expect(r.success).toBe(true)
  })

  it('acepta el estado de producción: setiembre abierto sin decisión y octubre en curso', () => {
    const plazos = v.parse(PlazosCargaMesSchema, PRODUCCION_14_OCT)
    expect(plazos.meses.map((m) => m.mes)).toEqual(['2026-09', '2026-10'])
  })

  it('acepta un mes sellado y reabrible con su última reapertura', () => {
    const r = v.safeParse(PlazosCargaMesSchema, {
      ...PRODUCCION_14_OCT,
      meses: [{
        ...PRODUCCION_14_OCT.meses[0],
        sellado: true,
        reabrible: true,
        ultima_reapertura: { reabierto_en: '2026-10-14T09:00:00-05:00', decidido_por: 'MIGUEL BRICEÑO' },
      }],
    })
    expect(r.success).toBe(true)
  })

  it.each([
    ['una clave de más en la raíz', { ...EJEMPLO_DISENO, pendiente: null }],
    ['una raíz sin generado_en (la función siempre lo manda)', Object.fromEntries(Object.entries(EJEMPLO_DISENO).filter(([k]) => k !== 'generado_en'))],
    ['un generado_en que no es fecha', { ...EJEMPLO_DISENO, generado_en: 'ayer' }],
    ['una clave de más en el mes', { ...EJEMPLO_DISENO, meses: [{ ...EJEMPLO_DISENO.meses[0], cierra_el: '2026-10-21' }] }],
    ['una clave de más en la decisión', {
      ...EJEMPLO_DISENO,
      meses: [{ ...EJEMPLO_DISENO.meses[0], decision: { ...EJEMPLO_DISENO.meses[0]!.decision, decidido_por_id: 'x' } }],
    }],
    ['una clave que falta en el mes', {
      ...EJEMPLO_DISENO,
      meses: [Object.fromEntries(Object.entries(EJEMPLO_DISENO.meses[0]!).filter(([k]) => k !== 'ampliado'))],
    }],
    ['otra versión', { ...EJEMPLO_DISENO, version: 2 }],
    ['otra zona', { ...EJEMPLO_DISENO, zona: 'UTC' }],
    ['un mes mal escrito', { ...EJEMPLO_DISENO, meses: [{ ...EJEMPLO_DISENO.meses[0], mes: '2026-9' }] }],
    ['un booleano como texto', { ...EJEMPLO_DISENO, meses: [{ ...EJEMPLO_DISENO.meses[0], sellado: 'false' }] }],
    ['una fecha con hora donde va un día', { ...EJEMPLO_DISENO, meses: [{ ...EJEMPLO_DISENO.meses[0], plazo_ultimo_dia: '2026-10-20T00:00:00' }] }],
    ['un mes repetido', { ...PRODUCCION_14_OCT, meses: [PRODUCCION_14_OCT.meses[0], PRODUCCION_14_OCT.meses[0]] }],
  ])('rechaza %s', (_caso, payload) => {
    expect(v.safeParse(PlazosCargaMesSchema, payload).success).toBe(false)
  })
})

describe('acuse de crm.fijar_plazo_carga_mes (fail-closed)', () => {
  it('acepta una ampliación y una reapertura con ventas devueltas (monto como texto numérico)', () => {
    expect(v.safeParse(PlazoCargaFijadoSchema, ACUSE).success).toBe(true)
    const reapertura = v.parse(PlazoCargaFijadoSchema, {
      ...ACUSE,
      reabierto: true,
      reapertura_id: '55555555-5555-4555-8555-555555555555',
      ventas_devueltas: [{ cooperativa: 'qorilazo', monto: '20000.00', moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' }],
    })
    expect(reapertura.ventas_devueltas[0]?.monto).toBe(20000)
  })

  it.each([
    ['una clave de más', { ...ACUSE, detalle: 'extra' }],
    ['ok distinto de true', { ...ACUSE, ok: false }],
    ['reabierto sin fila de reapertura', { ...ACUSE, reabierto: true }],
    ['una reapertura sin reabrir', { ...ACUSE, reapertura_id: '55555555-5555-4555-8555-555555555555' }],
    ['un contador negativo', { ...ACUSE, acreditaciones_reevaluadas: -1 }],
    ['una venta con una clave de más', {
      ...ACUSE,
      ventas_devueltas: [{ cooperativa: 'qorilazo', monto: 1, moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13', lead_id: 'x' }],
    }],
    ['una moneda desconocida', {
      ...ACUSE,
      ventas_devueltas: [{ cooperativa: 'qorilazo', monto: 1, moneda: 'EUR', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' }],
    }],
  ])('rechaza %s', (_caso, payload) => {
    expect(v.safeParse(PlazoCargaFijadoSchema, payload).success).toBe(false)
  })
})

describe('lo que dice cada mes', () => {
  const HOY = '2026-10-14'

  it('abierto con plazo por delante: «se puede cargar hasta el 20 oct.»', () => {
    const m = mes({ plazo_ultimo_dia: '2026-10-20', ampliado: true })
    expect(estadoDelPlazo(m, HOY)).toBe('vigente')
    expect(lineaDelPlazo(m, HOY)).toBe('se puede cargar hasta el 20 oct.')
  })

  it('el último día es hoy: lo dice así', () => {
    expect(lineaDelPlazo(mes({ plazo_ultimo_dia: HOY }), HOY)).toBe('se puede cargar hasta hoy, 14 oct.')
  })

  it('ESTADO DE PRODUCCIÓN: setiembre abierto con el plazo vencido no dice «se puede cargar hasta el 10 oct.»', () => {
    const m = mes()
    expect(estadoDelPlazo(m, HOY)).toBe('vencido')
    expect(lineaDelPlazo(m, HOY)).toBe('el plazo de carga venció el 10 oct.')
    expect(AVISO_PLAZO_VENCIDO).toMatch(/conversión queda fuera de plazo/)
  })

  it('sellado: cerrado, con el plazo que tuvo', () => {
    expect(lineaDelPlazo(mes({ sellado: true }), HOY)).toBe('cerrado · se pudo cargar hasta el 10 oct.')
  })

  it('el nombre lo pone el servidor: solo se sube la primera letra', () => {
    expect(conMayuscula('setiembre 2026')).toBe('Setiembre 2026')
    expect(mesSinAnio('setiembre 2026')).toBe('setiembre')
    expect(mesSinAnio('setiembre')).toBe('setiembre')
    expect(periodoDelMes('2026-09')).toBe('2026-09-01')
  })

  it('quién decidió, en Lima: una decisión de las 20:00 del 14 es del 14 aunque en UTC sea el 15', () => {
    expect(lineaDecision(mes())).toBeNull()
    expect(lineaDecision(mes({
      ampliado: true,
      decision: { ultimo_dia: '2026-10-20', motivo: 'x', decidido_por: 'MIGUEL BRICEÑO', decidido_en: '2026-10-15T01:00:00Z' },
    }))).toBe('Ampliado por MIGUEL BRICEÑO el 14 oct.')
    expect(lineaDecision(mes({
      ampliado: false,
      decision: { ultimo_dia: '2026-10-10', motivo: 'x', decidido_por: 'ANA', decidido_en: '2026-10-14T15:00:00Z' },
      ultima_reapertura: { reabierto_en: '2026-10-14T14:00:00Z', decidido_por: 'ANA' },
    }))).toBe('Reabierto por ANA el 14 oct. · fijado por ANA el 14 oct.')
  })

  it('el botón: ampliar si está abierto, reabrir si el servidor dice que se puede, nada si no', () => {
    expect(accionDelMes(mes())).toEqual({ tipo: 'ampliar', etiqueta: 'Ampliar plazo' })
    expect(accionDelMes(mes({ sellado: true, reabrible: true }))).toEqual({ tipo: 'reabrir', etiqueta: 'Reabrir setiembre' })
    expect(accionDelMes(mes({ sellado: true, reabrible: false, motivo_no_reabrible: 'Solo se reabre el mes anterior.' }))).toBeNull()
  })
})

describe('reglas del formulario', () => {
  it('la fecha mínima es la más tardía entre hoy y el plazo normal', () => {
    expect(fechaMinimaPlazo(mes(), '2026-10-14')).toBe('2026-10-14')
    expect(fechaMinimaPlazo(mes({ plazo_base_ultimo_dia: '2026-11-10' }), '2026-10-14')).toBe('2026-11-10')
  })

  it('la fecha: vacía, inválida, antes del mínimo o aceptada', () => {
    expect(errorUltimoDia('', '2026-10-14')).toBe('Elige el último día para cargar.')
    expect(errorUltimoDia('20/10/2026', '2026-10-14')).toBe('La fecha no es válida.')
    expect(errorUltimoDia('2026-10-13', '2026-10-14')).toBe('Elige un día desde el 14 oct.')
    expect(errorUltimoDia('2026-10-14', '2026-10-14')).toBeNull()
    expect(errorUltimoDia('2027-03-31', '2026-10-14')).toBeNull()
  })

  it('el motivo se cuenta como Postgres (sin espacios de borde, un emoji es uno) y va de 5 a 300', () => {
    expect(largoMotivoPlazo('  hola  ')).toBe(4)
    expect(largoMotivoPlazo('ok 👍')).toBe(4)
    expect(motivoPlazoValido('  hola ')).toBe(false)
    expect(motivoPlazoValido('Carga')).toBe(true)
    expect(motivoPlazoValido('x'.repeat(300))).toBe(true)
    expect(motivoPlazoValido('x'.repeat(301))).toBe(false)
  })
})

describe('el aviso tras guardar', () => {
  const acuse = (over: Partial<PlazoCargaFijado> = {}): PlazoCargaFijado => ({ ...ACUSE, ...over } as PlazoCargaFijado)

  it('ampliar: el plazo que quedó y cuántas conversiones se volvieron a revisar', () => {
    expect(resumenPlazoFijado(acuse(), 'setiembre 2026')).toEqual({
      titulo: 'Setiembre 2026: se puede cargar hasta el 20 oct.',
      lineas: ['Se volvieron a revisar 12 conversiones con el plazo nuevo.'],
    })
    expect(resumenPlazoFijado(acuse({ acreditaciones_reevaluadas: 0 }), 'setiembre 2026').lineas)
      .toEqual(['No había conversiones de este mes que volver a revisar.'])
    expect(resumenPlazoFijado(acuse({ acreditaciones_reevaluadas: 1, conflictos_identidad: 1 }), 'setiembre 2026').lineas).toEqual([
      'Se volvió a revisar 1 conversión con el plazo nuevo.',
      '1 conversión se quedó como estaba: esa persona ya tenía otra conversión acreditada.',
    ])
  })

  it('reabrir: lo dice en el título y nombra cada venta devuelta a su mes', () => {
    const r = resumenPlazoFijado(acuse({
      reabierto: true,
      reapertura_id: '55555555-5555-4555-8555-555555555555',
      acreditaciones_reevaluadas: 3,
      conflictos_identidad: 2,
      ventas_devueltas: [
        { cooperativa: 'qorilazo', monto: 20000, moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' },
        { cooperativa: 'otra', monto: 1500.5, moneda: 'USD', fecha_comercial: '2026-09-30', imputada_antes_a: '2026-10-02' },
      ],
    }), 'setiembre 2026')
    expect(r.titulo).toBe('Setiembre 2026 reabierto: se puede cargar hasta el 20 oct.')
    expect(r.lineas).toEqual([
      'Se volvieron a revisar 3 conversiones con el plazo nuevo.',
      '2 conversiones se quedaron como estaban: esas personas ya tenían otra conversión acreditada.',
      'Venta devuelta a setiembre: COOPAC Qorilazo · S/ 20,000 · del 15 set. (estaba contada el 13 oct.).',
      'Venta devuelta a setiembre: OTRA · US$ 1,500.5 · del 30 set. (estaba contada el 02 oct.).',
    ])
  })
})

it('conPunto no duplica el punto de una abreviatura de mes', () => {
  expect(conPunto('hasta el 20 oct.')).toBe('hasta el 20 oct.')
  expect(conPunto('hasta hoy')).toBe('hasta hoy.')
})

it('codigoDeError lee el código estable sin depender de la clase del error', () => {
  expect(codigoDeError({ code: 'NO_DISPONIBLE' })).toBe('NO_DISPONIBLE')
  expect(codigoDeError(new Error('x'))).toBeNull()
  expect(codigoDeError(null)).toBeNull()
  expect(codigoDeError({ code: 42 })).toBeNull()
})
