// Modelo de la malla de Facturación, probado en puro: agregación por día,
// separación de monedas, filtro por equipo/analistas y la conciliación del
// filtro. Es lógica que falla EN SILENCIO — un total que sale mal no revienta,
// solo miente — así que cada regla tiene su caso.
import { describe, expect, it } from 'vitest'
import {
  conciliarFiltro,
  ESCALA_FACTURACION,
  construirMalla,
  contratosDeCelda,
  diasDelMes,
  diasHabilesHasta,
  equiposDeRoster,
  esFinDeSemana,
  filasComparadas,
  filtrarContratos,
  filtroInicial,
  filtroVacio,
  letraDia,
  mejorDia,
  mesDesplazado,
  nivelFacturacion,
  numeroDia,
  pasoDeEscala,
  primerDiaDelMes,
  rosterDeContratos,
  valorCelda,
  type ContratoFacturado,
  type FiltroFacturacion,
} from './facturacion'

const MES = '2026-09-01'

function contrato(parcial: Partial<ContratoFacturado> & { id: string }): ContratoFacturado {
  return {
    numero: '000001',
    cliente: 'Cliente de prueba',
    producto: 'Renta Fija 12 meses',
    tasaAnual: 14,
    moneda: 'PEN',
    capital: 10_000,
    dia: '2026-09-01',
    analistaId: 'a1',
    analistaNombre: 'Ana Uno',
    supervisorId: 's1',
    supervisorNombre: 'Sara Supervisora',
    ...parcial,
  }
}

/** Dos equipos, tres analistas, cinco contratos: uno en dólares y uno fuera del mes. */
const CONTRATOS: readonly ContratoFacturado[] = [
  contrato({ id: 'c1', dia: '2026-09-01', capital: 100_000 }),
  contrato({ id: 'c2', dia: '2026-09-01', capital: 40_000 }),
  contrato({ id: 'c3', dia: '2026-09-03', capital: 250_000, analistaId: 'a2', analistaNombre: 'Beto Dos' }),
  contrato({
    id: 'c4',
    dia: '2026-09-03',
    capital: 9_000,
    moneda: 'USD',
    analistaId: 'a3',
    analistaNombre: 'Carla Tres',
    supervisorId: 's2',
    supervisorNombre: 'Sonia Segunda',
  }),
  contrato({ id: 'c5', dia: '2026-08-31', capital: 999_999 }),
]

describe('días del mes — el footgun de las fechas', () => {
  it('no se lleva el día 1 al mes anterior ni pierde el último', () => {
    const dias = diasDelMes(MES)
    expect(dias).toHaveLength(30)
    expect(dias[0]).toBe('2026-09-01')
    expect(dias.at(-1)).toBe('2026-09-30')
  })

  it('respeta febrero y los años bisiestos', () => {
    expect(diasDelMes('2026-02-01')).toHaveLength(28)
    expect(diasDelMes('2028-02-01')).toHaveLength(29)
  })

  it('lee el día de la semana en local: el 1 de setiembre de 2026 es martes', () => {
    expect(letraDia('2026-09-01')).toBe('M')
    expect(numeroDia('2026-09-01')).toBe(1)
    expect(esFinDeSemana('2026-09-06')).toBe(true) // domingo
    expect(esFinDeSemana('2026-09-05')).toBe(true) // sábado
    expect(esFinDeSemana('2026-09-04')).toBe(false)
  })

  it('navega entre meses sin desbordar el año', () => {
    expect(mesDesplazado(MES, -1)).toBe('2026-08-01')
    expect(mesDesplazado('2026-01-01', -1)).toBe('2025-12-01')
    expect(mesDesplazado('2026-12-01', 1)).toBe('2027-01-01')
    expect(primerDiaDelMes('2026-09-17')).toBe(MES)
  })
})

describe('construirMalla', () => {
  const malla = construirMalla(CONTRATOS, MES, 'PEN')

  it('agrupa por supervisor y solo trae la moneda pedida', () => {
    // El contrato en dólares (c4) es el único de Sonia: en soles su equipo no existe.
    expect(malla.grupos.map((g) => g.id)).toEqual(['s1'])
    expect(malla.total.capital).toBe(390_000)
    expect(malla.total.contratos).toBe(3)
  })

  it('deja fuera lo que no cae en el mes', () => {
    // c5 es del 31 de agosto: 999.999 no aparecen por ningún lado, y sobre todo
    // NO se cuelan en el día 1 (el desbordamiento clásico al bucketear fechas).
    expect(malla.total.capital).toBe(390_000)
    expect(valorCelda(malla.totalPorDia[0], 'capital')).toBe(140_000)
    const ana = malla.grupos[0]?.analistas.find((a) => a.id === 'a1')
    expect(ana?.total.capital).toBe(140_000)
  })

  it('suma varios contratos del mismo analista en el mismo día', () => {
    const ana = malla.grupos[0]?.analistas.find((a) => a.id === 'a1')
    expect(valorCelda(ana?.dias[0], 'capital')).toBe(140_000)
    expect(valorCelda(ana?.dias[0], 'contratos')).toBe(2)
  })

  it('el total por día cuadra con la suma de las filas', () => {
    expect(valorCelda(malla.totalPorDia[0], 'capital')).toBe(140_000)
    expect(valorCelda(malla.totalPorDia[2], 'capital')).toBe(250_000)
    expect(valorCelda(malla.totalPorDia[1], 'capital')).toBe(0)
  })

  it('la malla de dólares es otra malla — PEN y USD jamás se suman', () => {
    const usd = construirMalla(CONTRATOS, MES, 'USD')
    expect(usd.total.capital).toBe(9_000)
    expect(usd.grupos.map((g) => g.id)).toEqual(['s2'])
  })

  it('un mes sin nada devuelve una malla vacía, no un error', () => {
    const vacia = construirMalla([], MES, 'PEN')
    expect(vacia.grupos).toHaveLength(0)
    expect(vacia.total).toEqual({ capital: 0, contratos: 0 })
    expect(vacia.dias).toHaveLength(30)
    expect(mejorDia(vacia, 'capital')).toBeNull()
  })

  it('el mejor día es el de más capital', () => {
    expect(mejorDia(malla, 'capital')).toEqual({ dia: '2026-09-03', valor: 250_000 })
    // Por número de contratos gana el otro día: dos cierres pesan más que uno.
    expect(mejorDia(malla, 'contratos')).toEqual({ dia: '2026-09-01', valor: 2 })
  })
})

describe('roster y equipos', () => {
  it('saca a cada persona una sola vez y las ordena por nombre', () => {
    const roster = rosterDeContratos(CONTRATOS)
    expect(roster.map((p) => p.nombre)).toEqual(['Ana Uno', 'Beto Dos', 'Carla Tres'])
    expect(roster.find((p) => p.id === 'a3')?.supervisorId).toBe('s2')
  })

  it('el roster ignora la moneda: quien solo vendió en dólares también se puede consultar', () => {
    expect(rosterDeContratos(CONTRATOS).some((p) => p.id === 'a3')).toBe(true)
  })

  it('deduplica los equipos', () => {
    expect(equiposDeRoster(rosterDeContratos(CONTRATOS))).toEqual([
      { id: 's1', nombre: 'Sara Supervisora' },
      { id: 's2', nombre: 'Sonia Segunda' },
    ])
  })
})

describe('filtro', () => {
  it('sin filtro no quita nada', () => {
    expect(filtroVacio(filtroInicial())).toBe(true)
    expect(filtrarContratos(CONTRATOS, filtroInicial())).toHaveLength(CONTRATOS.length)
  })

  it('por equipo deja solo a ese equipo', () => {
    const soloS2 = filtrarContratos(CONTRATOS, { equipo: 's2', analistas: [] })
    expect(soloS2.map((c) => c.id)).toEqual(['c4'])
  })

  it('por un analista lo aísla', () => {
    const soloA2 = filtrarContratos(CONTRATOS, { equipo: '', analistas: ['a2'] })
    expect(soloA2.map((c) => c.id)).toEqual(['c3'])
  })

  it('por varios analistas los compara — se quedan todos los elegidos', () => {
    const dos = filtrarContratos(CONTRATOS, { equipo: '', analistas: ['a1', 'a3'] })
    expect(dos.map((c) => c.id)).toEqual(['c1', 'c2', 'c4', 'c5'])
  })

  it('equipo y analistas se aplican a la vez (y pueden dejarlo en nada)', () => {
    expect(filtrarContratos(CONTRATOS, { equipo: 's2', analistas: ['a1'] })).toHaveLength(0)
  })

  it('los totales de la malla ya vienen filtrados', () => {
    const filtrada = construirMalla(
      filtrarContratos(CONTRATOS, { equipo: '', analistas: ['a2'] }),
      MES,
      'PEN',
    )
    expect(filtrada.total.capital).toBe(250_000)
  })
})

describe('conciliarFiltro — la guarda que copiamos de Citas', () => {
  const roster = rosterDeContratos(CONTRATOS)

  it('al elegir un equipo se caen los analistas que no son suyos', () => {
    const filtro: FiltroFacturacion = { equipo: 's1', analistas: ['a1', 'a3'] }
    expect(conciliarFiltro(filtro, roster).analistas).toEqual(['a1'])
  })

  it('deja intacto lo que sí pertenece al equipo', () => {
    const filtro: FiltroFacturacion = { equipo: 's1', analistas: ['a1', 'a2'] }
    expect(conciliarFiltro(filtro, roster)).toBe(filtro)
  })

  it('QUITAR el equipo no te cuesta la selección de analistas', () => {
    const filtro: FiltroFacturacion = { equipo: '', analistas: ['a1', 'a3'] }
    expect(conciliarFiltro(filtro, roster).analistas).toEqual(['a1', 'a3'])
  })

  it('un analista que ya no está en el roster se cae en vez de filtrar a nadie', () => {
    const filtro: FiltroFacturacion = { equipo: 's1', analistas: ['a1', 'fantasma'] }
    expect(conciliarFiltro(filtro, roster).analistas).toEqual(['a1'])
  })
})

describe('comparación', () => {
  it('aplana las filas y las ordena por capital, de mayor a menor', () => {
    const malla = construirMalla(CONTRATOS, MES, 'PEN')
    const filas = filasComparadas(malla)
    expect(filas.map((f) => f.id)).toEqual(['a2', 'a1'])
    expect(filas[0]?.supervisorNombre).toBe('Sara Supervisora')
  })
})

describe('días hábiles y escala de color', () => {
  it('el domingo no cuenta como día hábil', () => {
    const malla = construirMalla(CONTRATOS, MES, 'PEN')
    // Del 1 al 7 de setiembre de 2026 hay un domingo (el 6): seis hábiles.
    expect(diasHabilesHasta(malla, '2026-09-07')).toBe(6)
    // El mes entero: 30 días menos cuatro domingos.
    expect(diasHabilesHasta(malla, '2026-09-30')).toBe(26)
  })

  it('el cero es su propio paso: «no vendió» no es «vendió poco»', () => {
    expect(nivelFacturacion(0, 100)).toBe(0)
    expect(nivelFacturacion(1, 100)).toBe(1)
    expect(nivelFacturacion(100, 100)).toBe(6)
  })

  it('sin máximo no inventa color', () => {
    expect(nivelFacturacion(50, 0)).toBe(0)
  })
})

describe('contratosDeCelda', () => {
  it('devuelve los contratos de esa persona ese día, del mayor al menor', () => {
    const ops = contratosDeCelda(CONTRATOS, 'a1', '2026-09-01')
    expect(ops.map((c) => c.id)).toEqual(['c1', 'c2'])
  })

  it('un día sin cierres devuelve la lista vacía', () => {
    expect(contratosDeCelda(CONTRATOS, 'a1', '2026-09-02')).toHaveLength(0)
  })
})

/* ─────────────────────────── escala de color ───────────────────────────
 * Esta prueba nació de un fallo: el paso del 66 % llevaba texto BLANCO y daba
 * 2.83:1 sobre su propio fondo — muy por debajo del 4.5:1 de la WCAG, y justo
 * en el escalón que más se mira. Aquí se mide, no se opina.
 */

/** Luminancia relativa de un hexadecimal (WCAG 2.x). */
function luminancia(hex: string): number {
  const canales = [1, 3, 5].map((i) => {
    const c = Number.parseInt(hex.slice(i, i + 2), 16) / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })
  const [r = 0, v = 0, a = 0] = canales
  return 0.2126 * r + 0.7152 * v + 0.0722 * a
}

function contraste(fondo: string, texto: string): number {
  const a = luminancia(fondo)
  const b = luminancia(texto)
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

describe('escala de color de la malla', () => {
  it('el helper de contraste mide bien los extremos conocidos', () => {
    expect(contraste('#ffffff', '#000000')).toBeCloseTo(21, 1)
    expect(contraste('#ffffff', '#ffffff')).toBeCloseTo(1, 5)
  })

  it('TODOS los pasos pasan el 4.5:1 de la WCAG para texto normal', () => {
    const medidos = ESCALA_FACTURACION.map((paso) => ({
      fondo: paso.bgHex,
      ratio: Number(contraste(paso.bgHex, paso.fgHex).toFixed(2)),
    }))
    // Se afirma la tabla ENTERA: si alguien retoca un paso, se ve cuál y cuánto.
    for (const paso of medidos) expect(paso).toMatchObject({ ratio: expect.any(Number) })
    expect(medidos.filter((p) => p.ratio < 4.5)).toEqual([])
  })

  it('el blanco solo entra cuando el fondo ya es acento pleno o navy', () => {
    // La regla que dejó el fallo del 66 %: por debajo de eso, tinta oscura.
    const claros = ESCALA_FACTURACION.filter((p) => p.fgHex.toLowerCase() === '#ffffff')
    expect(claros.map((p) => p.bgHex)).toEqual(['#2563eb', '#111e3d'])
  })

  it('son siete pasos y el 0 es el fondo de la tarjeta', () => {
    expect(ESCALA_FACTURACION).toHaveLength(7)
    expect(ESCALA_FACTURACION[0]?.bg).toBe('transparent')
  })

  it('pasoDeEscala nunca devuelve undefined, ni con un máximo en cero', () => {
    expect(pasoDeEscala(0, 0).bg).toBe('transparent')
    expect(pasoDeEscala(100, 100)).toBe(ESCALA_FACTURACION[6])
    expect(pasoDeEscala(1, 100)).toBe(ESCALA_FACTURACION[1])
  })
})
