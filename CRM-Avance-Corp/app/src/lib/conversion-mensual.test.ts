import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ConversionMensualSchema,
  descuentoArrastre,
  lecturaCobertura,
  lineaProcedencia,
  hayTopeReferidos,
  lineaReferidos,
  textoReferidosFormula,
  textoTopeReferidos,
  totalConversionPublicable,
} from './conversion-mensual'

const CARTERA_RESPONSABLE = {
  conversiones_clientes: 4,
  conversiones_renovacion: 3,
  conversiones_upgrade: 1,
  capital_renovado_pen: 125_000.75,
  capital_renovado_usd: 2_500.5,
  capital_adicional_pen: 15_000.25,
  capital_adicional_usd: 300.75,
  renovaciones_sin_desglose: 0,
}

const CARTERA_TOTAL = {
  ...CARTERA_RESPONSABLE,
  operaciones_renovacion: 3,
  operaciones_upgrade: 1,
}

/** Payload realista completo — el caso canónico de Ana (19,78 % ÷ 90). */
function payloadCanonico() {
  return {
    version: 1,
    revision: 7,
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
    cierre: { cerrado: false },
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
      cartera: { ...CARTERA_TOTAL },
    },
    cartera: { ...CARTERA_TOTAL },
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
        cartera: { ...CARTERA_RESPONSABLE },
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

  it('conserva la revisión compartida y tolera que el backend previo aún no la publique', () => {
    const vigente = v.safeParse(ConversionMensualSchema, payloadCanonico())
    expect(vigente.success).toBe(true)
    if (!vigente.success) return
    expect(vigente.output.revision).toBe(7)

    const { revision: _revision, ...legado } = payloadCanonico()
    const anterior = v.safeParse(ConversionMensualSchema, legado)
    expect(anterior.success).toBe(true)
    if (!anterior.success) return
    expect('revision' in anterior.output).toBe(false)
  })

  it.each([-1, 1.5, 'siete'])('rechaza una revisión mensual inválida: %s', (revision) => {
    expect(v.safeParse(ConversionMensualSchema, {
      ...payloadCanonico(),
      revision,
    }).success).toBe(false)
  })

  it('conserva el estado abierto/sellado para alinear las lecturas del mes', () => {
    const payload = {
      ...payloadCanonico(),
      cierre: {
        cerrado: true,
        cerrado_en: '2026-09-10T14:20:00+00:00',
        automatico: true,
      },
    }
    const r = v.safeParse(ConversionMensualSchema, payload)
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.cierre).toEqual(payload.cierre)
  })

  it('estado solo_referidos PARSEA — si faltara en el picklist se caería el payload entero', () => {
    const p = payloadCanonico()
    p.responsables[0] = {
      ...p.responsables[0]!,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 2,
      cierres_de_arrastre: 0,
      numerador: 4.3,
      conversion_pct: null as unknown as number,
      estado: 'solo_referidos',
      procedencia: [
        { mes: '2026-07', mes_nombre: 'julio', anio: 2026, cierres: 2, cierres_referidos: 2 },
      ],
      referidos: { recibidos: 8, cerrados: 2, dados_de_alta: 8, aporta_pct: null as unknown as number },
    }
    ;(p.cobertura as { divisor_por_motivo: Record<string, number> }).divisor_por_motivo = {}
    p.total = {
      ...p.total,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 2,
      cierres_de_arrastre: 0,
      referidos_recibidos: 8,
      numerador: 4.3,
      conversion_pct: null as unknown as number,
      referidos_aporta_pct: null as unknown as number,
    }
    const r = v.safeParse(ConversionMensualSchema, p)
    expect(r.success).toBe(true)
  })

  it('estado solo_arrastre PARSEA con cierres u operaciones y divisor 0', () => {
    const p = payloadCanonico()
    p.responsables[0] = {
      ...p.responsables[0]!,
      divisor: 0,
      conversion_pct: null as unknown as number,
      estado: 'solo_arrastre',
      referidos: { ...p.responsables[0]!.referidos, recibidos: 0, aporta_pct: null as unknown as number },
    }
    ;(p.cobertura as { divisor_por_motivo: Record<string, number> }).divisor_por_motivo = {}
    p.total = {
      ...p.total,
      divisor: 0,
      referidos_recibidos: 0,
      conversion_pct: null as unknown as number,
      referidos_aporta_pct: null as unknown as number,
    }
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
  })

  it('estado sin_actividad PARSEA solo cuando no hay cierres, recibidos ni cartera', () => {
    const p = payloadCanonico()
    const carteraResponsable = {
      ...CARTERA_RESPONSABLE,
      conversiones_clientes: 0,
      conversiones_renovacion: 0,
      conversiones_upgrade: 0,
    }
    const carteraTotal = {
      ...CARTERA_TOTAL,
      ...carteraResponsable,
      operaciones_renovacion: 0,
      operaciones_upgrade: 0,
    }
    p.responsables[0] = {
      ...p.responsables[0]!,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 0,
      cierres_de_arrastre: 0,
      numerador: 0,
      conversion_pct: null as unknown as number,
      estado: 'sin_actividad',
      procedencia: [],
      referidos: { recibidos: 0, cerrados: 0, dados_de_alta: 0, aporta_pct: null as unknown as number },
      cartera: carteraResponsable,
    }
    ;(p.cobertura as { divisor_por_motivo: Record<string, number> }).divisor_por_motivo = {}
    p.cartera = carteraTotal
    p.total = {
      ...p.total,
      divisor: 0,
      cierres_no_referidos: 0,
      cierres_referidos: 0,
      cierres_de_arrastre: 0,
      referidos_recibidos: 0,
      numerador: 0,
      conversion_pct: null as unknown as number,
      referidos_aporta_pct: null as unknown as number,
      cartera: carteraTotal,
    }
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
  })

  it('una conversión del 200 % parsea SIN recorte (la definición supera 100 por diseño)', () => {
    const p = payloadCanonico()
    p.total.numerador = 180
    p.total.conversion_pct = 200
    p.responsables[0]!.numerador = 180
    p.responsables[0]!.conversion_pct = 200
    const r = v.safeParse(ConversionMensualSchema, p)
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.total.conversion_pct).toBe(200)
  })

  it('preserva el desglose de cartera y la precisión numeric en raíz, total y responsable', () => {
    const p = payloadCanonico()
    ;(p.cartera as { capital_renovado_pen: unknown }).capital_renovado_pen = '125000.7501'
    ;(p.total.cartera as { capital_renovado_pen: unknown }).capital_renovado_pen = '125000.7501'
    ;(p.cartera as { capital_adicional_usd: unknown }).capital_adicional_usd = '300.755'
    ;(p.total.cartera as { capital_adicional_usd: unknown }).capital_adicional_usd = '300.755'
    ;(p.responsables[0]!.cartera as { capital_renovado_usd: unknown }).capital_renovado_usd = '2500.505'

    const r = v.safeParse(ConversionMensualSchema, p)
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.cartera.capital_renovado_pen).toBe(125000.7501)
    expect(r.output.total.cartera.capital_adicional_usd).toBe(300.755)
    expect(r.output.responsables[0]!.cartera).toMatchObject({
      conversiones_clientes: 4,
      conversiones_renovacion: 3,
      conversiones_upgrade: 1,
      capital_renovado_usd: 2500.505,
    })
  })

  it.each([
    ['cartera raíz', (p: ReturnType<typeof payloadCanonico>) => { delete (p as { cartera?: unknown }).cartera }],
    ['cartera del total', (p: ReturnType<typeof payloadCanonico>) => { delete (p.total as { cartera?: unknown }).cartera }],
    ['cartera del responsable', (p: ReturnType<typeof payloadCanonico>) => { delete (p.responsables[0] as { cartera?: unknown }).cartera }],
  ])('RECHAZA la ausencia de %s: nunca la degrada a cero', (_caso, quitar) => {
    const p = payloadCanonico()
    quitar(p)
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it.each([
    ['conversiones_upgrade del responsable', (p: ReturnType<typeof payloadCanonico>) => {
      delete (p.responsables[0]!.cartera as { conversiones_upgrade?: unknown }).conversiones_upgrade
    }],
    ['operaciones_upgrade del total', (p: ReturnType<typeof payloadCanonico>) => {
      delete (p.total.cartera as { operaciones_upgrade?: unknown }).operaciones_upgrade
    }],
    ['capital_renovado_pen de la raíz', (p: ReturnType<typeof payloadCanonico>) => {
      delete (p.cartera as { capital_renovado_pen?: unknown }).capital_renovado_pen
    }],
  ])('RECHAZA la ausencia del campo %s: una cartera parcial tampoco equivale a cero', (_caso, quitar) => {
    const p = payloadCanonico()
    quitar(p)
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it('RECHAZA una transición incompleta a llegadas únicas', () => {
    const p = payloadCanonico()
    p.fuentes.divisor = 'crm.leads.creado_en'
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it('admite el contrato de llegadas con renovación ponderada sin romper fotos históricas', () => {
    const anterior = payloadCanonico()
    expect(v.safeParse(ConversionMensualSchema, anterior).success).toBe(true)
    const nuevo = {
      ...anterior,
      fuentes: { ...anterior.fuentes, divisor: 'crm.leads.creado_en', referido: 'crm.leads.origen' },
      ponderacion: { ...anterior.ponderacion, renovacion: anterior.ponderacion.referido },
    }
    expect(v.safeParse(ConversionMensualSchema, nuevo).success).toBe(true)

    // 23/09/2026: la renovación tiene su propio peso en `crm.conversion_pesos`.
    // Antes esta línea ponía `renovacion = 1` y exigía que el paquete se
    // RECHAZARA, porque el contrato obligaba a que los dos pesos fueran
    // iguales. Ya no: un peso de renovación distinto del referido es
    // legítimo, y seguir rechazándolo dejaría inservible la palanca que se
    // acaba de separar.
    nuevo.ponderacion.renovacion = 1
    expect(v.safeParse(ConversionMensualSchema, nuevo).success).toBe(true)
    nuevo.ponderacion.renovacion = 0.4
    expect(v.safeParse(ConversionMensualSchema, nuevo).success).toBe(true)

    // Lo que SÍ se sigue rechazando: un peso fuera de rango…
    nuevo.ponderacion.renovacion = 1.5
    expect(v.safeParse(ConversionMensualSchema, nuevo).success).toBe(false)

    // …y que el núcleo CALLE el peso de la renovación cuando declara que el
    // divisor son las llegadas. Declararlo es la obligación que sustituye a la
    // de que fuera igual.
    const sinRenovacion = {
      ...nuevo,
      ponderacion: { referido: anterior.ponderacion.referido, fuente: anterior.ponderacion.fuente },
    }
    expect(v.safeParse(ConversionMensualSchema, sinRenovacion).success).toBe(false)

    expect(v.safeParse(ConversionMensualSchema, {
      ...anterior, fuentes: { ...anterior.fuentes, divisor: 'crm.leads.actualizado_en' },
    }).success).toBe(false)
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
    p.responsables[0]!.procedencia[2] = {
      mes: null as unknown as string,
      mes_nombre: 'anteriores',
      anio: null as unknown as number,
      cierres: 1,
      cierres_referidos: 0,
    }
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
  })

  it('RECHAZA un período cuyo año o límites no corresponden al mes', () => {
    const anioIncorrecto = payloadCanonico()
    anioIncorrecto.periodo.anio = 2025
    expect(v.safeParse(ConversionMensualSchema, anioIncorrecto).success).toBe(false)

    const hastaIncorrecto = payloadCanonico()
    hastaIncorrecto.periodo.hasta = '2026-08-31T05:00:00+00:00'
    expect(v.safeParse(ConversionMensualSchema, hastaIncorrecto).success).toBe(false)
  })

  it('RECHAZA porcentajes, estados y procedencia que contradicen sus cantidades', () => {
    const porcentaje = payloadCanonico()
    porcentaje.total.conversion_pct = 18
    expect(v.safeParse(ConversionMensualSchema, porcentaje).success).toBe(false)

    const estado = payloadCanonico()
    estado.responsables[0]!.estado = 'sin_actividad'
    expect(v.safeParse(ConversionMensualSchema, estado).success).toBe(false)

    const procedencia = payloadCanonico()
    procedencia.responsables[0]!.procedencia[0]!.cierres = 23
    expect(v.safeParse(ConversionMensualSchema, procedencia).success).toBe(false)
  })

  it('ACEPTA producción fuera_de_roster sin sumarla al contador ni inventar una fila', () => {
    const p = payloadCanonico()
    p.cobertura.fuera_de_roster = { analistas: 2, divisor: 10, cierres: 2, numerador: 1.3 }
    ;(p.cobertura as { divisor_por_motivo: Record<string, number> }).divisor_por_motivo = {
      ingreso: 86,
      reasignado: 4,
      fuera_de_roster: 10,
    }
    p.total = {
      ...p.total,
      // Dos identidades externas aportan al total empresa, pero solo la fila
      // de `responsables` participa del ranking.
      analistas: 1,
      divisor: 100,
      cierres_no_referidos: 18,
      numerador: 19.1,
      conversion_pct: 19.1,
      referidos_aporta_pct: 1.8,
    }
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)

    p.total.analistas = 3
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)

    p.total.analistas = 1
    p.total.divisor = 90
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it('mes parcial conserva un porcentaje publicable y no se confunde con contrato roto', () => {
    const p = payloadCanonico()
    p.cobertura.medible = false
    ;(p.cobertura as { motivo_no_medible: string | null }).motivo_no_medible = 'mes_parcial'
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

  it('un cierre sin episodio oculta todo incluso si el mes era medible', () => {
    const r = lecturaCobertura(cob({
      medible: true,
      motivo_no_medible: null,
      cierres_sin_episodio: 1,
    }))
    expect(r).toEqual({
      mostrar: false,
      aviso: 'Cifras en revisión: 1 cierre no tiene episodio verificable.',
    })
  })

  it('el selector de total aplica la misma sonda y nunca entrega el total crudo', () => {
    const mensual = v.parse(ConversionMensualSchema, payloadCanonico())
    expect(totalConversionPublicable(mensual)).toBe(mensual.total)
    expect(totalConversionPublicable({
      ...mensual,
      cobertura: { ...mensual.cobertura, cierres_sin_episodio: 1 },
    })).toBeNull()
  })

  it('sin cobertura no se muestra nada', () => {
    expect(lecturaCobertura(null)).toEqual({ mostrar: false, aviso: null })
  })
})

describe('el ajuste por meses cerrados y su chip (descuentoArrastre)', () => {
  it('el contrato acepta las DOS formas reales (viva y sellada) y su ausencia (vuelta atrás)', () => {
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

    // La forma SELLADA, VERBATIM de ejecutar la función en el banco (16/08):
    // {aplicado, pendiente: 0, origenes: []}. Sin declarar `aplicado`, Valibot
    // lo descartaba y la foto de un mes cerrado quedaba rebajada sin porqué.
    const sellado = {
      ...base,
      responsables: base.responsables.map((fila, indice) => (indice === 0
        ? { ...fila, ajuste: { aplicado: '1.15', pendiente: 0, origenes: [] } }
        : fila)),
    }
    const conSellado = v.safeParse(ConversionMensualSchema, sellado)
    expect(conSellado.success).toBe(true)
    if (conSellado.success) {
      expect(conSellado.output.responsables[0]!.ajuste?.aplicado).toBe(1.15)
    }

    expect(v.safeParse(ConversionMensualSchema, payloadCanonico()).success).toBe(true)
  })

  it('sin ajuste o con todo en cero no hay chip: «0» no existe', () => {
    expect(descuentoArrastre(undefined)).toBeNull()
    expect(descuentoArrastre({ pendiente: 0, origenes: [] })).toBeNull()
    expect(descuentoArrastre({ pendiente: 0, aplicado: 0, origenes: [] })).toBeNull()
  })

  it('mes VIVO: afirma la DEUDA («arrastra»), no un descuento que quizá no cupo entero', () => {
    // Con bruto 1 y deuda 3 el servidor resta 1 y arrastra 2: un «−3» junto al
    // número mentiría. Lo afirmable con lo que viaja es la deuda (#4).
    const chip = descuentoArrastre({
      pendiente: 2.15,
      origenes: [
        { periodo: '2026-06', motivo: 'Pago no confirmado', numerador: 1 },
        { periodo: '2026-06', motivo: 'Contrato anulado', numerador: 0.15 },
        { periodo: '2026-07', motivo: 'Cierre duplicado', numerador: 1 },
      ],
    })
    expect(chip?.etiqueta).toBe('arrastra 2.15 conversiones de anulaciones · junio 2026 y julio 2026')
    expect(chip?.detalle).toBe(
      'junio 2026: Pago no confirmado (−1)\njunio 2026: Contrato anulado (−0.15)\njulio 2026: Cierre duplicado (−1)',
    )
  })

  it('FOTO SELLADA: el «−N» sí es exacto (se restó al sellar) y no inventa meses', () => {
    expect(descuentoArrastre({ pendiente: 0, aplicado: 1.15, origenes: [] })?.etiqueta)
      .toBe('−1.15 conversiones descontadas al cierre')
    expect(descuentoArrastre({ pendiente: 0, aplicado: 1, origenes: [] })?.etiqueta)
      .toBe('−1 conversión descontada al cierre')
    expect(descuentoArrastre({ pendiente: 0, aplicado: 1, origenes: [] })?.detalle)
      .toBe('Anulaciones de meses cerrados, descontadas al sellar este mes.')
  })

  it('una deuda de 0.001 no se pinta como «0»: gana decimales', () => {
    expect(descuentoArrastre({ pendiente: 0.001, origenes: [] })?.etiqueta)
      .toBe('arrastra 0.001 conversiones de anulaciones')
  })

  it('la unidad concuerda con lo MOSTRADO, no con el número crudo (observación #8)', () => {
    // 1.004 y 0.995 se PINTAN «1»: jamás «1 conversiones».
    expect(descuentoArrastre({ pendiente: 1.004, origenes: [] })?.etiqueta)
      .toBe('arrastra 1 conversión de anulaciones')
    expect(descuentoArrastre({ pendiente: 0.995, origenes: [] })?.etiqueta)
      .toBe('arrastra 1 conversión de anulaciones')
    expect(descuentoArrastre({ pendiente: 0, aplicado: 1.004, origenes: [] })?.etiqueta)
      .toBe('−1 conversión descontada al cierre')
  })

  it('julio 2025 y julio 2026 son DOS meses, no uno', () => {
    const chip = descuentoArrastre({
      pendiente: 2,
      origenes: [
        { periodo: '2025-07', motivo: 'a', numerador: 1 },
        { periodo: '2026-07', motivo: 'b', numerador: 1 },
      ],
    })
    expect(chip?.etiqueta).toBe('arrastra 2 conversiones de anulaciones · julio 2025 y julio 2026')
  })

  it('con una sola conversión habla en singular, y sin orígenes no inventa meses', () => {
    expect(descuentoArrastre({ pendiente: 1, origenes: [] })?.etiqueta)
      .toBe('arrastra 1 conversión de anulaciones')
    expect(descuentoArrastre({ pendiente: 1 })?.detalle)
      .toBe('Anulaciones de meses ya cerrados pendientes de saldar.')
  })
})

/**
 * ESTADO DE OCTUBRE 2026: el referido vale 1 pero todos los referidos de un
 * analista cuentan como máximo el 15 % de sus cierres de leads asignados. 15 cierres
 * asignados + 5 referidos → tope ceil(0,15 × 15) = 3: dos referidos no
 * suman. Numerador 15 + 3 = 18 sobre 90 → 20 %; aporte de referidos
 * 100 × 3 ÷ 90 = 3,33 (SIN tope serían 100 × 1 × 5 ÷ 90 = 5,56).
 */
function payloadOctubreConTope() {
  const p = payloadCanonico()
  p.periodo = {
    mes: '2026-10',
    mes_nombre: 'octubre',
    anio: 2026,
    zona: 'America/Lima',
    desde: '2026-10-01T05:00:00+00:00',
    hasta: '2026-11-01T05:00:00+00:00',
  }
  p.ponderacion = {
    referido: 1,
    renovacion: 1,
    tope_referidos_pct: 15,
    fuente: 'crm.conversion_pesos',
  } as typeof p.ponderacion
  p.total = {
    ...p.total,
    cierres_no_referidos: 15,
    cierres_referidos: 5,
    cierres_de_arrastre: 0,
    numerador: 18,
    conversion_pct: 20,
    referidos_aporta_pct: 3.33,
  }
  p.responsables[0] = {
    ...p.responsables[0]!,
    cierres_no_referidos: 15,
    cierres_referidos: 5,
    cierres_de_arrastre: 0,
    numerador: 18,
    conversion_pct: 20,
    procedencia: [
      { mes: '2026-10', mes_nombre: 'octubre', anio: 2026, cierres: 20, cierres_referidos: 5 },
    ],
    referidos: { recibidos: 8, cerrados: 5, dados_de_alta: 8, aporta_pct: 3.33 },
  }
  return p
}

describe('ConversionMensualSchema — tope de referidos (octubre 2026)', () => {
  it('octubre con tope: 5 referidos cerrados que aportan 3 PARSEA (antes la igualdad lo rechazaba)', () => {
    const r = v.safeParse(ConversionMensualSchema, payloadOctubreConTope())
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.ponderacion.tope_referidos_pct).toBe(15)
    expect(r.output.total.referidos_aporta_pct).toBe(3.33)
    expect(r.output.responsables[0]?.referidos.aporta_pct).toBe(3.33)
  })

  it('con tope, un aporte que SUPERA lo que darían todos los referidos sin recortar se rechaza (total y responsable)', () => {
    const total = payloadOctubreConTope()
    total.total.referidos_aporta_pct = 5.6 // máximo 100 × 1 × 5 ÷ 90 = 5,56
    expect(v.safeParse(ConversionMensualSchema, total).success).toBe(false)

    const fila = payloadOctubreConTope()
    fila.responsables[0]!.referidos.aporta_pct = 5.6
    expect(v.safeParse(ConversionMensualSchema, fila).success).toBe(false)
  })

  it('con tope, el aporte exactamente igual al máximo (nadie recortado) también PARSEA', () => {
    const p = payloadOctubreConTope()
    p.total.referidos_aporta_pct = 5.56
    p.responsables[0]!.referidos.aporta_pct = 5.56
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)
  })

  it('con tope y divisor 0 el aporte sigue siendo null: un número se rechaza', () => {
    const p = payloadOctubreConTope()
    const fila = p.responsables[0]!
    fila.divisor = 0
    fila.estado = 'solo_referidos'
    fila.conversion_pct = null as unknown as number
    fila.referidos.aporta_pct = null as unknown as number
    p.total.divisor = 0
    p.total.conversion_pct = null as unknown as number
    p.total.referidos_aporta_pct = null as unknown as number
    p.cobertura.divisor_por_motivo = { ingreso: 0, reasignado: 0 }
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(true)

    p.responsables[0]!.referidos.aporta_pct = 3 as unknown as number
    expect(v.safeParse(ConversionMensualSchema, p).success).toBe(false)
  })

  it('sin tope (null o ausente) la igualdad exacta sigue: el MISMO aporte recortado se rechaza', () => {
    const conNull = payloadOctubreConTope()
    ;(conNull.ponderacion as { tope_referidos_pct?: number | null }).tope_referidos_pct = null
    expect(v.safeParse(ConversionMensualSchema, conNull).success).toBe(false)

    const ausente = payloadOctubreConTope()
    delete (ausente.ponderacion as { tope_referidos_pct?: number | null }).tope_referidos_pct
    expect(v.safeParse(ConversionMensualSchema, ausente).success).toBe(false)
  })

  it('un tope fuera de 0–100 se rechaza', () => {
    const alto = payloadOctubreConTope()
    ;(alto.ponderacion as { tope_referidos_pct?: number | null }).tope_referidos_pct = 150
    expect(v.safeParse(ConversionMensualSchema, alto).success).toBe(false)

    const negativo = payloadOctubreConTope()
    ;(negativo.ponderacion as { tope_referidos_pct?: number | null }).tope_referidos_pct = -1
    expect(v.safeParse(ConversionMensualSchema, negativo).success).toBe(false)
  })

  it('septiembre (peso 0,15, sin tope) valida EXACTAMENTE igual que antes', () => {
    const sin = payloadCanonico() // referido 0.15, tope ausente, aporta 2
    expect(v.safeParse(ConversionMensualSchema, sin).success).toBe(true)

    const conNull = payloadCanonico()
    ;(conNull.ponderacion as { tope_referidos_pct?: number | null }).tope_referidos_pct = null
    expect(v.safeParse(ConversionMensualSchema, conNull).success).toBe(true)

    const distinto = payloadCanonico()
    distinto.total.referidos_aporta_pct = 1.5 // igualdad estricta: ni menos
    expect(v.safeParse(ConversionMensualSchema, distinto).success).toBe(false)
    const distintoFila = payloadCanonico()
    distintoFila.responsables[0]!.referidos.aporta_pct = 1.5
    expect(v.safeParse(ConversionMensualSchema, distintoFila).success).toBe(false)
  })
})

describe('textos del tope de referidos', () => {
  it('sin tope conserva EXACTO «referidos ×0.15»; con tope explica el 15 % de los cierres de leads asignados', () => {
    expect(hayTopeReferidos({ tope_referidos_pct: null })).toBe(false)
    expect(hayTopeReferidos({})).toBe(false)
    expect(hayTopeReferidos({ tope_referidos_pct: 15 })).toBe(true)
    expect(textoReferidosFormula({ referido: 0.15 })).toBe('referidos ×0.15')
    expect(textoReferidosFormula({ referido: 0.15, tope_referidos_pct: null })).toBe('referidos ×0.15')
    expect(textoReferidosFormula({ referido: 1, tope_referidos_pct: 15 }))
      .toBe('referidos (cuentan hasta el 15 % de los cierres de leads asignados)')
    expect(textoTopeReferidos({})).toBeNull()
    expect(textoTopeReferidos({ tope_referidos_pct: 15 }))
      .toBe('Los referidos cuentan hasta el 15 % de los cierres de leads asignados; los que sobran no suman.')
  })
})
