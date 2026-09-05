// Tests de lib/metricas — helpers PUROS de pivoteo de las gráficas de gerencia.
// Sin Date ni TZ: todo es texto 'YYYY-MM', así los casos son deterministas.
import { describe, expect, it } from 'vitest'
import {
  claveMes,
  etiquetaMes,
  mesesContinuos,
  monedasConDatos,
  pivotCapitalPorMes,
  pivotPagosPorMes,
  pivotVencimientosPorMes,
  topAltasPorAnalista,
  inicioHorizonte,
  SIN_CATEGORIA,
  type FilaAltasAnalista,
  type FilaCapitalMes,
  type FilaPagosMes,
  type FilaVencimientos,
} from './metricas'

// ── builders mínimos (shape de las RPCs ya coercionado por crm-api) ────────────
function fCapital(sobre: Partial<FilaCapitalMes> = {}): FilaCapitalMes {
  return {
    mes: '2026-05-01',
    moneda: 'PEN',
    categoria: 'nuevo',
    contratos: 1,
    capital_colocado: 10_000,
    ...sobre,
  }
}

function fPagos(sobre: Partial<FilaPagosMes> = {}): FilaPagosMes {
  return {
    mes: '2026-05-01',
    moneda: 'PEN',
    tipo: 'cuota',
    estado: 'pagado',
    cuotas: 1,
    monto_programado: 500,
    monto_pagado: 500,
    ...sobre,
  }
}

function fAltas(sobre: Partial<FilaAltasAnalista> = {}): FilaAltasAnalista {
  return {
    mes: '2026-05-01',
    analista_id: 'a1',
    analista_nombre: 'LINDA QA',
    altas: 1,
    ...sobre,
  }
}

function fVenc(sobre: Partial<FilaVencimientos> = {}): FilaVencimientos {
  return {
    mes: '2026-08-01',
    moneda: 'PEN',
    contratos_por_vencer: 1,
    capital_por_vencer: 20_000,
    ...sobre,
  }
}

describe('claveMes', () => {
  it('extrae YYYY-MM de un date y de un timestamp ISO', () => {
    expect(claveMes('2026-07-01')).toBe('2026-07')
    expect(claveMes('2026-07-15T13:45:00.000Z')).toBe('2026-07')
  })

  it('rechaza basura y meses imposibles', () => {
    expect(claveMes('no-es-fecha')).toBeNull()
    expect(claveMes('2026-13-01')).toBeNull()
    expect(claveMes('2026-00-01')).toBeNull()
    expect(claveMes('')).toBeNull()
  })
})

describe('etiquetaMes', () => {
  it('formatea es-PE corto: mes en minúscula + año de 2 dígitos', () => {
    expect(etiquetaMes('2026-01')).toBe('ene 26')
    expect(etiquetaMes('2026-12')).toBe('dic 26')
    expect(etiquetaMes('2025-07')).toBe('jul 25')
  })

  it('una clave rara se devuelve tal cual (nunca revienta el eje)', () => {
    expect(etiquetaMes('zzz')).toBe('zzz')
  })
})

describe('mesesContinuos', () => {
  it('rellena los huecos entre el primer y el último mes, ordenado', () => {
    expect(mesesContinuos(['2026-05', '2026-02'])).toEqual(['2026-02', '2026-03', '2026-04', '2026-05'])
  })

  it('cruza el año sin perderse meses', () => {
    expect(mesesContinuos(['2025-11', '2026-02'])).toEqual(['2025-11', '2025-12', '2026-01', '2026-02'])
  })

  it('vacío → vacío; claves inválidas se ignoran', () => {
    expect(mesesContinuos([])).toEqual([])
    expect(mesesContinuos(['basura', '2026-03'])).toEqual(['2026-03'])
  })

  it('un rango absurdo (fecha basura de siglos) NO fabrica miles de meses', () => {
    const meses = mesesContinuos(['0201-01', '2026-07'])
    // Sin relleno: solo los meses presentes (honesto y sin bomba de memoria).
    expect(meses).toEqual(['0201-01', '2026-07'])
  })
})

describe('monedasConDatos', () => {
  it('devuelve solo las monedas presentes, siempre PEN antes que USD', () => {
    expect(monedasConDatos([{ moneda: 'USD' }, { moneda: 'PEN' }])).toEqual(['PEN', 'USD'])
    expect(monedasConDatos([{ moneda: 'USD' }])).toEqual(['USD'])
    expect(monedasConDatos([])).toEqual([])
  })
})

describe('pivotCapitalPorMes', () => {
  it('apila por categoría dentro del mes y JAMÁS mezcla monedas', () => {
    const filas = [
      fCapital({ capital_colocado: 30_000, categoria: 'nuevo' }),
      fCapital({ capital_colocado: 20_000, categoria: 'renovacion' }),
      fCapital({ moneda: 'USD', capital_colocado: 50_000, categoria: 'nuevo' }),
    ]
    const pen = pivotCapitalPorMes(filas, 'PEN')
    expect(pen).toHaveLength(1)
    expect(pen[0]).toMatchObject({ mes: '2026-05', nuevo: 30_000, renovacion: 20_000, upgrade: 0 })
    // El USD vive en SU propia serie: nada del PEN se le cuela ni al revés.
    const usd = pivotCapitalPorMes(filas, 'USD')
    expect(usd).toHaveLength(1)
    expect(usd[0]).toMatchObject({ nuevo: 50_000, renovacion: 0 })
  })

  it("categoria null (o desconocida) cae en el bucket '—' (sin_categoria)", () => {
    const filas = [
      fCapital({ categoria: null, capital_colocado: 7_000 }),
      fCapital({ categoria: 'promo_2099', capital_colocado: 3_000 }),
    ]
    const puntos = pivotCapitalPorMes(filas, 'PEN')
    expect(puntos[0]?.[SIN_CATEGORIA]).toBe(10_000)
  })

  it('rellena con 0 los meses sin datos (eje continuo) y etiqueta es-PE', () => {
    const filas = [
      fCapital({ mes: '2026-02-01', capital_colocado: 10_000 }),
      fCapital({ mes: '2026-04-01', capital_colocado: 5_000 }),
    ]
    const puntos = pivotCapitalPorMes(filas, 'PEN')
    expect(puntos.map((p) => p.mes)).toEqual(['2026-02', '2026-03', '2026-04'])
    expect(puntos[1]).toMatchObject({ etiqueta: 'mar 26', nuevo: 0, renovacion: 0, upgrade: 0, sin_categoria: 0 })
  })

  it('una fila con mes ilegible se descarta sin tumbar el resto', () => {
    const puntos = pivotCapitalPorMes([fCapital(), fCapital({ mes: 'basura' })], 'PEN')
    expect(puntos).toHaveLength(1)
    // Solo suma la fila legible: la de mes 'basura' se descarta, no se acumula.
    expect(puntos[0]?.nuevo).toBe(10_000)
  })
})

describe('pivotPagosPorMes', () => {
  // El retorno devuelve el CAPITAL: no es pagos de intereses y su monto
  // aplasta la escala (hallazgo de revisión 2026-07-16). La devolución
  // (interés compuesto al vencimiento) SÍ es interés y SÍ entra.
  it('excluye el retorno de capital de ambas series; la devolución sí entra', () => {
    const filas = [
      fPagos({ tipo: 'cuota', estado: 'pagado', monto_pagado: 2_000, monto_programado: 2_000 }),
      fPagos({ tipo: 'retorno', estado: 'pagado', monto_pagado: 80_000, monto_programado: 80_000 }),
      fPagos({ tipo: 'retorno', estado: 'vencido', monto_pagado: 0, monto_programado: 50_000 }),
      fPagos({ tipo: 'devolucion', estado: 'pagado', monto_pagado: 1_500, monto_programado: 1_500 }),
    ]
    const puntos = pivotPagosPorMes(filas, 'PEN')
    expect(puntos).toHaveLength(1)
    expect(puntos[0]!.pagado).toBe(3_500) // 2000 cuota + 1500 devolución; sin los 80k
    expect(puntos[0]!.vencido).toBe(0) // el retorno vencido tampoco infla la serie
  })

  it('pagado = estado pagado → monto_pagado y vencido = vencido.monto_programado', () => {
    const filas = [
      fPagos({ estado: 'pagado', monto_pagado: 800, monto_programado: 1_000 }),
      fPagos({ estado: 'vencido', monto_pagado: 0, monto_programado: 600 }),
      // pendiente/trasladado NO son pagos del mes: se ignoran.
      fPagos({ estado: 'pendiente', monto_programado: 9_999 }),
      fPagos({ estado: 'trasladado', monto_programado: 9_999 }),
    ]
    const puntos = pivotPagosPorMes(filas, 'PEN')
    expect(puntos).toHaveLength(1)
    expect(puntos[0]).toMatchObject({ pagado: 800, vencido: 600 })
  })

  it('filtra por moneda y rellena huecos con 0', () => {
    const filas = [
      fPagos({ mes: '2026-01-01', estado: 'pagado', monto_pagado: 100 }),
      fPagos({ mes: '2026-03-01', estado: 'vencido', monto_programado: 50 }),
      fPagos({ mes: '2026-02-01', moneda: 'USD', estado: 'pagado', monto_pagado: 999 }),
    ]
    const pen = pivotPagosPorMes(filas, 'PEN')
    expect(pen.map((p) => p.mes)).toEqual(['2026-01', '2026-02', '2026-03'])
    expect(pen[1]).toMatchObject({ pagado: 0, vencido: 0 })
  })
})

describe('topAltasPorAnalista', () => {
  it('suma los meses por analista y ordena descendente (empate: alfabético)', () => {
    const filas = [
      fAltas({ mes: '2026-04-01', analista_id: 'a1', analista_nombre: 'LINDA QA', altas: 2 }),
      fAltas({ mes: '2026-05-01', analista_id: 'a1', analista_nombre: 'LINDA QA', altas: 3 }),
      fAltas({ analista_id: 'a2', analista_nombre: 'ASTRID QA', altas: 5 }),
      fAltas({ analista_id: 'a3', analista_nombre: 'CARMEN QA', altas: 1 }),
    ]
    const top = topAltasPorAnalista(filas)
    expect(top.map((a) => a.nombre)).toEqual(['ASTRID QA', 'LINDA QA', 'CARMEN QA'])
    expect(top[1]?.altas).toBe(5) // 2 + 3 de los dos meses de LINDA
  })

  it('recorta al top-N pedido', () => {
    const filas = ['a', 'b', 'c'].map((id, i) =>
      fAltas({ analista_id: id, analista_nombre: id.toUpperCase(), altas: i + 1 }),
    )
    expect(topAltasPorAnalista(filas, 2)).toHaveLength(2)
    expect(topAltasPorAnalista(filas, 0)).toHaveLength(0)
  })
})

describe('pivotVencimientosPorMes', () => {
  it('suma capital y contratos por mes, por moneda, con huecos en 0', () => {
    const filas = [
      fVenc({ mes: '2026-08-01', capital_por_vencer: 20_000, contratos_por_vencer: 1 }),
      fVenc({ mes: '2026-08-01', capital_por_vencer: 10_000, contratos_por_vencer: 2 }),
      fVenc({ mes: '2026-10-01', capital_por_vencer: 5_000 }),
      fVenc({ mes: '2026-09-01', moneda: 'USD', capital_por_vencer: 50_000 }),
    ]
    const pen = pivotVencimientosPorMes(filas, 'PEN')
    expect(pen.map((p) => p.mes)).toEqual(['2026-08', '2026-09', '2026-10'])
    expect(pen[0]).toMatchObject({ capital: 30_000, contratos: 3 })
    expect(pen[1]).toMatchObject({ capital: 0, contratos: 0 })
    const usd = pivotVencimientosPorMes(filas, 'USD')
    expect(usd).toHaveLength(1)
    expect(usd[0]).toMatchObject({ mes: '2026-09', capital: 50_000, contratos: 1 })
  })
})

describe('inicioHorizonte', () => {
  // Texto + aritmética entera: el resultado no depende de la zona horaria.
  const hoy = new Date(2026, 8, 15) // 15 sep 2026 (mes 0-based)

  it('1 mes = el mes actual; N meses retrocede N-1', () => {
    expect(inicioHorizonte(1, hoy)).toBe('2026-09-01')
    expect(inicioHorizonte(3, hoy)).toBe('2026-07-01')
    expect(inicioHorizonte(6, hoy)).toBe('2026-04-01')
  })

  it('cruza el año hacia atrás sin perder el mes', () => {
    expect(inicioHorizonte(12, hoy)).toBe('2025-10-01')
    expect(inicioHorizonte(3, new Date(2026, 0, 10))).toBe('2025-11-01')
  })

  it('un horizonte inválido (0, negativo, decimal) se acota a 1 mes / se trunca', () => {
    expect(inicioHorizonte(0, hoy)).toBe('2026-09-01')
    expect(inicioHorizonte(-4, hoy)).toBe('2026-09-01')
    expect(inicioHorizonte(2.9, hoy)).toBe('2026-08-01')
  })
})
