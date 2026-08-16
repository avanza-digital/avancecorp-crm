import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ConversionMensualSchema,
  descuentoArrastre,
  lecturaCobertura,
  lineaProcedencia,
  lineaReferidos,
} from './conversion-mensual'

/** Payload realista completo — el caso canónico de Ana (19,78 % ÷ 90). */
function payloadCanonico() {
  return {
    version: 1,
    generado_en: '2026-08-11T21:00:00+00:00',
    alcance: 'global',
    periodo: {
      mes: '2026-08',
      mes_nombre: 'agosto',
      anio: 2026,
      zona: 'America/Lima',
      desde: '2026-08-01T05:00:00+00:00',
      hasta: '2026-09-01T05:00:00+00:00',
    },
    ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
    fuentes: {
      divisor: 'crm.lead_asignaciones.asignado_en',
      numerador: 'crm.lead_asignaciones.resultado_en',
      referido: 'crm.lead_asignaciones.origen',
    },
    cobertura: {
      medible: true,
      suelo_historico: '2026-08-05T18:19:55+00:00',
      motivo_no_medible: null,
      divisor_aproximado: 0,
      divisor_por_motivo: { ingreso: 86, reasignado: 4 },
      cierres_sin_episodio: 0,
      fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
    },
    total: {
      analistas: 1,
      divisor: 90,
      cierres_no_referidos: 16,
      cierres_referidos: 12,
      cierres_de_arrastre: 4,
      referidos_recibidos: 20,
      numerador: 17.8,
      conversion_pct: 19.78,
      referidos_aporta_pct: 2,
    },
    responsables: [
      {
        vendedor_id: '40000000-0000-4000-8000-000000000007',
        supervisor_id: '40000000-0000-4000-8000-000000000001',
        divisor: 90,
        cierres_no_referidos: 16,
        cierres_referidos: 12,
        cierres_de_arrastre: 4,
        numerador: 17.8,
        conversion_pct: 19.78,
        estado: 'medible',
        procedencia: [
          { mes: '2026-08', mes_nombre: 'agosto', anio: 2026, cierres: 24, cierres_referidos: 12 },
          { mes: '2026-07', mes_nombre: 'julio', anio: 2026, cierres: 3, cierres_referidos: 0 },
          { mes: '2026-06', mes_nombre: 'junio', anio: 2026, cierres: 1, cierres_referidos: 0 },
        ],
        referidos: { recibidos: 20, cerrados: 12, dados_de_alta: 20, aporta_pct: 2 },
      },
    ],
  }
}

describe('ConversionMensualSchema — el contrato', () => {
  it('parsea el caso canónico de Ana con sus tipos', () => {
    const r = v.safeParse(ConversionMensualSchema, payloadCanonico())
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.total.numerador).toBe(17.8)
    expect(r.output.total.conversion_pct).toBe(19.78)
    expect(r.output.responsables[0]?.estado).toBe('medible')
  })

  it('el ALCANCE sobrevive al parseo (lo decide el servidor y el front lo necesita)', () => {
    const r = v.safeParse(ConversionMensualSchema, payloadCanonico())
    expect(r.success).toBe(true)
    if (!r.success) return
    // Con v.object laxo, una clave NO declarada se BORRA en silencio de la
    // salida tipada: esta aserción impide que `alcance` se caiga del esquema.
    expect(r.output.alcance).toBe('global')
  })

  it('estado solo_referidos PARSEA — si faltara en el picklist se caería el payload entero', () => {
    const p = payloadCanonico()
    p.responsables[0] = {
      ...p.responsables[0]!,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 2,
      cierres_de_arrastre: 0,
      numerador: 0.3,
      conversion_pct: null as unknown as number,
      estado: 'solo_referidos',
      procedencia: [],
      referidos: { recibidos: 8, cerrados: 2, dados_de_alta: 8, aporta_pct: null as unknown as number },
    }
    const r = v.safeParse(ConversionMensualSchema, p)
    expect(r.success).toBe(true)
  })

  it('los otros dos estados con divisor 0 también parsean', () => {
    for (const estado of ['solo_arrastre', 'sin_actividad'] as const) {
      const p = payloadCanonico()
      p.responsables[0] = {
        ...p.responsables[0]!,
        divisor: 0,
        conversion_pct: null as unknown as number,
        estado,
      }
      expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
    }
  })

  it('una conversión del 200 % parsea SIN recorte (la definición supera 100 por diseño)', () => {
    const p = payloadCanonico()
    p.total.conversion_pct = 200
    p.responsables[0]!.conversion_pct = 200
    const r = v.safeParse(ConversionMensualSchema, p)
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.total.conversion_pct).toBe(200)
  })

  it('RECHAZA un divisor con otra definición (fail-closed del contrato)', () => {
    const p = payloadCanonico()
    p.fuentes.divisor = 'crm.leads.creado_en'
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it('RECHAZA un estado desconocido del servidor', () => {
    const p = payloadCanonico()
    ;(p.responsables[0] as { estado: string }).estado = 'en_racha'
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it('tolera una clave NUEVA del servidor (v.object laxo a propósito)', () => {
    const p = payloadCanonico() as Record<string, unknown>
    p['nueva_clave_del_futuro'] = { lo: 'que sea' }
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
  })

  it('el numerador acepta el numeric de PostgREST servido como string', () => {
    const p = payloadCanonico()
    ;(p.total as { numerador: unknown }).numerador = '17.80'
    const r = v.safeParse(ConversionMensualSchema, p)
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.total.numerador).toBe(17.8)
  })

  it('el cubo `anteriores` parsea con mes y año en null', () => {
    const p = payloadCanonico()
    p.responsables[0]!.procedencia.push({
      mes: null as unknown as string,
      mes_nombre: 'anteriores',
      anio: null as unknown as number,
      cierres: 2,
      cierres_referidos: 0,
    })
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
  })
})

describe('lineaProcedencia — «de qué mes venía cada cierre»', () => {
  it('nombra los meses sin año cuando es el año del periodo', () => {
    const p = payloadCanonico().responsables[0]!.procedencia
    expect(lineaProcedencia(p, 2026)).toBe('de agosto 24, de julio 3, de junio 1')
  })

  it('escribe el año SOLO cuando difiere del año del periodo', () => {
    expect(
      lineaProcedencia(
        [
          { mes: '2026-01', mes_nombre: 'enero', anio: 2026, cierres: 2, cierres_referidos: 0 },
          { mes: '2025-12', mes_nombre: 'diciembre', anio: 2025, cierres: 1, cierres_referidos: 0 },
        ],
        2026,
      ),
    ).toBe('de enero 2, de diciembre 2025 1')
  })

  it('rotula el cubo de más de 11 meses como «de meses anteriores»', () => {
    expect(
      lineaProcedencia(
        [{ mes: null, mes_nombre: 'anteriores', anio: null, cierres: 3, cierres_referidos: 1 }],
        2026,
      ),
    ).toBe('de meses anteriores 3')
  })

  it('omite tramos sin cierres y devuelve vacío sin ninguno', () => {
    expect(
      lineaProcedencia(
        [{ mes: '2026-08', mes_nombre: 'agosto', anio: 2026, cierres: 0, cierres_referidos: 0 }],
        2026,
      ),
    ).toBe('')
  })
})

describe('lineaReferidos — el bloque de referidos', () => {
  it('rinde exactamente «20 registrados · 12 cerrados · aporta 2.0 %» (es-PE: punto decimal)', () => {
    expect(
      lineaReferidos({ recibidos: 20, cerrados: 12, dados_de_alta: 20, aporta_pct: 2 }),
    ).toBe('20 registrados · 12 cerrados · aporta 2.0 %')
  })

  it('omite el aporte cuando no existe (divisor 0, solo_referidos)', () => {
    expect(
      lineaReferidos({ recibidos: 8, cerrados: 2, dados_de_alta: 8, aporta_pct: null }),
    ).toBe('8 registrados · 2 cerrados')
  })
})

describe('lecturaCobertura — un mes incompleto SE VE', () => {
  const cob = (over: Record<string, unknown> = {}) => ({
    medible: false,
    suelo_historico: '2026-08-05T18:19:55+00:00',
    motivo_no_medible: 'mes_parcial',
    divisor_aproximado: 0,
    divisor_por_motivo: {},
    cierres_sin_episodio: 0,
    fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 },
    ...over,
  }) as unknown as Parameters<typeof lecturaCobertura>[0]

  it('un mes medible se enseña sin aviso', () => {
    expect(lecturaCobertura(cob({ medible: true, motivo_no_medible: null })))
      .toEqual({ mostrar: true, aviso: null })
  })

  // EL CASO. Decisión de Miguel 2026-08-14: agosto tiene 3 recibidos y un
  // cierre; decir «sin datos» es falso. Se enseña, marcado como provisional.
  it('mes_parcial SE MUESTRA y dice desde cuándo hay registro', () => {
    const r = lecturaCobertura(cob())
    expect(r.mostrar).toBe(true)
    expect(r.aviso).toMatch(/Provisional/)
    // La fecha del suelo, con el formato de la casa («05 ago 2026»).
    expect(r.aviso).toMatch(/05 ago\.? 2026/i)
  })

  it('sin el suelo, mes_parcial sigue mostrándose y no inventa una fecha', () => {
    const r = lecturaCobertura(cob({ suelo_historico: null }))
    expect(r.mostrar).toBe(true)
    expect(r.aviso).toBe('Provisional: al mes le faltan días de registro')
  })

  // Estos dos SÍ significan «no hay nada»: ahí la frase vieja era correcta y la
  // cifra se sigue ocultando.
  it('sin_ledger y anterior_al_ledger se ocultan', () => {
    expect(lecturaCobertura(cob({ motivo_no_medible: 'sin_ledger' })).mostrar).toBe(false)
    expect(lecturaCobertura(cob({ motivo_no_medible: 'anterior_al_ledger' })).mostrar).toBe(false)
  })

  it('un motivo de roster se comporta como antes (oculto), sin frase inventada', () => {
    const r = lecturaCobertura(cob({ motivo_no_medible: 'sin_supervisor' }))
    expect(r.mostrar).toBe(false)
    expect(r.aviso).toBe('Sin datos de asignación para este mes')
  })

  it('sin cobertura no se muestra nada', () => {
    expect(lecturaCobertura(null)).toEqual({ mostrar: false, aviso: null })
  })
})

describe('el ajuste por meses cerrados y su chip (descuentoArrastre)', () => {
  it('el contrato acepta la clave nueva con su forma real, y su ausencia (vuelta atrás)', () => {
    const base = payloadCanonico()
    const p = {
      ...base,
      responsables: base.responsables.map((fila, indice) => (indice === 0
        ? {
          ...fila,
          ajuste: {
            pendiente: '1.15',
            origenes: [{ periodo: '2026-07', motivo: 'Cierre anulado por gerencia', numerador: '1.15' }],
          },
        }
        : fila)),
    }
    const conAjuste = v.safeParse(ConversionMensualSchema, p)
    expect(conAjuste.success).toBe(true)
    if (conAjuste.success) {
      // numeric de Postgres puede viajar como string: el pipe lo normaliza.
      expect(conAjuste.output.responsables[0]!.ajuste?.pendiente).toBe(1.15)
    }
    expect(v.safeParse(ConversionMensualSchema, payloadCanonico()).success).toBe(true)
  })

  it('sin ajuste o en cero no hay chip: −0 no existe', () => {
    expect(descuentoArrastre(undefined)).toBeNull()
    expect(descuentoArrastre({ pendiente: 0, origenes: [] })).toBeNull()
  })

  it('nombra el descuento y sus meses, sin repetirlos', () => {
    const chip = descuentoArrastre({
      pendiente: 2.15,
      origenes: [
        { periodo: '2026-06', motivo: 'Pago no confirmado', numerador: 1 },
        { periodo: '2026-06', motivo: 'Contrato anulado', numerador: 0.15 },
        { periodo: '2026-07', motivo: 'Cierre duplicado', numerador: 1 },
      ],
    })
    expect(chip?.etiqueta).toBe('−2.15 conversiones · arrastre de junio y julio')
    expect(chip?.detalle).toBe(
      'junio: Pago no confirmado (−1)\njunio: Contrato anulado (−0.15)\njulio: Cierre duplicado (−1)',
    )
  })

  it('con una sola conversión habla en singular, y sin orígenes no inventa meses', () => {
    expect(descuentoArrastre({ pendiente: 1, origenes: [] })?.etiqueta)
      .toBe('−1 conversión · arrastre de meses cerrados')
    expect(descuentoArrastre({ pendiente: 1 })?.detalle)
      .toBe('Anulaciones de meses ya cerrados pendientes de saldar.')
  })
})
