// Modelo de la malla de Facturación, probado en puro: agregación por día,
// separación de monedas, filtro por equipo/analistas y la conciliación del
// filtro. Es lógica que falla EN SILENCIO — un total que sale mal no revienta,
// solo miente — así que cada regla tiene su caso.
import { describe, expect, it } from 'vitest'
import {
  combinarEnSoles,
  conciliarFiltro,
  ESCALA_FACTURACION,
  construirMalla,
  construirMallaDeDias,
  desgloseDeCelda,
  diasDelPeriodo,
  diasDelMes,
  diasHabilesHasta,
  equiposDeRoster,
  esFinDeSemana,
  etiquetaPeriodo,
  filasComparadas,
  filtrarFilas,
  filtrarRoster,
  filtroInicial,
  filtroVacio,
  letraDia,
  lunesDeLaSemana,
  mesesQueTocan,
  mejorDia,
  mesDesplazado,
  nivelFacturacion,
  numeroDia,
  periodoDesplazado,
  pasoDeEscala,
  primerDiaDelMes,
  rosterDeEquipoYFilas,
  rosterDeFilas,
  SIN_SUPERVISOR_ID,
  SIN_SUPERVISOR_NOMBRE,
  TIPO_CAPITAL_NUEVO,
  TIPO_TODOS,
  totalesUnificados,
  valorCelda,
  type FilaFacturacionDia,
  type FiltroFacturacion,
  type MiembroEquipo,
} from './facturacion'

const MES = '2026-09-01'

/** Una fila con la forma que devuelve el servidor: ya agrupada. */
function fila(parcial: Partial<FilaFacturacionDia> & { id?: string }): FilaFacturacionDia {
  const { id: _id, ...resto } = parcial
  return {
    dia: '2026-09-01',
    tipo: 'contrato_nuevo',
    moneda: 'PEN',
    analistaId: 'a1',
    analistaNombre: 'Ana Uno',
    supervisorId: 's1',
    supervisorNombre: 'Sara Supervisora',
    operaciones: 1,
    capital: 10_000,
    ...resto,
  }
}

/** Dos equipos, tres analistas, cinco contratos: uno en dólares y uno fuera del mes. */
const FILAS: readonly FilaFacturacionDia[] = [
  fila({ id: 'c1', dia: '2026-09-01', capital: 100_000 }),
  fila({ id: 'c2', dia: '2026-09-01', capital: 40_000 }),
  fila({ id: 'c3', dia: '2026-09-03', capital: 250_000, analistaId: 'a2', analistaNombre: 'Beto Dos' }),
  fila({
    id: 'c4',
    dia: '2026-09-03',
    capital: 9_000,
    moneda: 'USD',
    analistaId: 'a3',
    analistaNombre: 'Carla Tres',
    supervisorId: 's2',
    supervisorNombre: 'Sonia Segunda',
  }),
  fila({ id: 'c5', dia: '2026-08-31', capital: 999_999 }),
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
    expect(letraDia('2026-09-01')).toBe('Ma')
    // Martes y miércoles ya no comparten letra: con «M» y «M» había que contar.
    expect(letraDia('2026-09-02')).toBe('Mi')
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
  const malla = construirMalla(FILAS, MES, 'PEN')

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
    const usd = construirMalla(FILAS, MES, 'USD')
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
    const roster = rosterDeFilas(FILAS)
    expect(roster.map((p) => p.nombre)).toEqual(['Ana Uno', 'Beto Dos', 'Carla Tres'])
    expect(roster.find((p) => p.id === 'a3')?.supervisorId).toBe('s2')
  })

  it('el roster ignora la moneda: quien solo vendió en dólares también se puede consultar', () => {
    expect(rosterDeFilas(FILAS).some((p) => p.id === 'a3')).toBe(true)
  })

  it('deduplica los equipos', () => {
    expect(equiposDeRoster(rosterDeFilas(FILAS))).toEqual([
      { id: 's1', nombre: 'Sara Supervisora' },
      { id: 's2', nombre: 'Sonia Segunda' },
    ])
  })
})

describe('filtro', () => {
  it('sin filtro no quita nada', () => {
    expect(filtroVacio(filtroInicial())).toBe(true)
    expect(filtrarFilas(FILAS, filtroInicial())).toHaveLength(FILAS.length)
  })

  it('por equipo deja solo a ese equipo', () => {
    const soloS2 = filtrarFilas(FILAS, { equipo: 's2', analistas: [] })
    expect(soloS2.map((f) => f.analistaId)).toEqual(['a3'])
  })

  it('por un analista lo aísla', () => {
    const soloA2 = filtrarFilas(FILAS, { equipo: '', analistas: ['a2'] })
    expect(soloA2.map((f) => f.capital)).toEqual([250_000])
  })

  it('por varios analistas los compara — se quedan todos los elegidos', () => {
    const dos = filtrarFilas(FILAS, { equipo: '', analistas: ['a1', 'a3'] })
    // Beto (a2) se cae; de a1 quedan sus tres filas y de a3 la suya, en orden.
    expect(dos.map((f) => f.capital)).toEqual([100_000, 40_000, 9_000, 999_999])
  })

  it('equipo y analistas se aplican a la vez (y pueden dejarlo en nada)', () => {
    expect(filtrarFilas(FILAS, { equipo: 's2', analistas: ['a1'] })).toHaveLength(0)
  })

  it('los totales de la malla ya vienen filtrados', () => {
    const filtrada = construirMalla(
      filtrarFilas(FILAS, { equipo: '', analistas: ['a2'] }),
      MES,
      'PEN',
    )
    expect(filtrada.total.capital).toBe(250_000)
  })
})

describe('conciliarFiltro — la guarda que copiamos de Citas', () => {
  const roster = rosterDeFilas(FILAS)

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
    const malla = construirMalla(FILAS, MES, 'PEN')
    const filas = filasComparadas(malla)
    expect(filas.map((f) => f.id)).toEqual(['a2', 'a1'])
    expect(filas[0]?.supervisorNombre).toBe('Sara Supervisora')
  })
})

describe('días hábiles y escala de color', () => {
  it('el domingo no cuenta como día hábil', () => {
    const malla = construirMalla(FILAS, MES, 'PEN')
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

describe('desgloseDeCelda', () => {
  it('devuelve el desglose de esa persona ese día, del mayor al menor', () => {
    const ops = desgloseDeCelda(FILAS, 'a1', '2026-09-01')
    expect(ops.map((f) => f.capital)).toEqual([100_000, 40_000])
  })

  it('con el día en null devuelve el mes entero de esa persona, por fecha', () => {
    const mes = desgloseDeCelda(FILAS, 'a1', null)
    expect(mes.map((f) => f.dia)).toEqual(['2026-08-31', '2026-09-01', '2026-09-01'])
  })

  it('un día sin cierres devuelve la lista vacía', () => {
    expect(desgloseDeCelda(FILAS, 'a1', '2026-09-02')).toHaveLength(0)
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

/* ───────── El analista que no ha vendido (Miguel, 11/09/2026) ─────────
 * «arregla lo de el analista que no ha vendido si quiero que salga». Antes el
 * roster salía de las propias ventas, así que el mes en cero era invisible: no
 * se podía ni preguntar por él. Ahora el organigrama siembra la malla.
 */
describe('roster con el organigrama', () => {
  function miembro(p: Partial<MiembroEquipo> & { id: string }): MiembroEquipo {
    return { nombre: `Nombre ${p.id}`, rol: 'vendedor', supervisorId: 'sup-1', activo: true, ...p }
  }

  const EQUIPO: readonly MiembroEquipo[] = [
    miembro({ id: 'sup-1', nombre: 'Rosa Uno', rol: 'supervisor', supervisorId: null }),
    miembro({ id: 'ana', nombre: 'Ana' }),
    miembro({ id: 'noe', nombre: 'Noe' }),
    miembro({ id: 'baja', nombre: 'Bruno', activo: false }),
    miembro({ id: 'ger', nombre: 'Gerente', rol: 'gerencia', supervisorId: null }),
  ]

  const VENDIO_ANA: readonly FilaFacturacionDia[] = [
    fila({ analistaId: 'ana', analistaNombre: 'Ana', supervisorId: 'sup-1', supervisorNombre: 'Rosa Uno' }),
  ]

  it('añade al analista activo que no vendió, con su supervisor de hoy', () => {
    const roster = rosterDeEquipoYFilas(EQUIPO, VENDIO_ANA)
    const noe = roster.find((p) => p.id === 'noe')
    expect(noe).toEqual({ id: 'noe', nombre: 'Noe', supervisorId: 'sup-1', supervisorNombre: 'Rosa Uno' })
  })

  it('NO añade a quien está dado de baja y no vendió', () => {
    expect(rosterDeEquipoYFilas(EQUIPO, VENDIO_ANA).map((p) => p.id)).not.toContain('baja')
  })

  it('sí conserva a quien está de baja PERO vendió: la venta existió', () => {
    const filas = [...VENDIO_ANA, fila({ analistaId: 'baja', analistaNombre: 'Bruno' })]
    expect(rosterDeEquipoYFilas(EQUIPO, filas).map((p) => p.id)).toContain('baja')
  })

  it('NO añade supervisores ni gerencia: el roster es de analistas', () => {
    const ids = rosterDeEquipoYFilas(EQUIPO, VENDIO_ANA).map((p) => p.id)
    expect(ids).not.toContain('sup-1')
    expect(ids).not.toContain('ger')
  })

  it('el supervisor DE ENTONCES gana al equipo de hoy para quien vendió', () => {
    // El organigrama coloca a Ana con Rosa; su venta es de cuando estaba con
    // Sara. Mover a alguien de equipo no le cambia de sitio el dinero cerrado.
    const filas = [
      fila({ analistaId: 'ana', analistaNombre: 'Ana', supervisorId: 'sup-2', supervisorNombre: 'Sara Dos' }),
    ]
    const ana = rosterDeEquipoYFilas(EQUIPO, filas).find((p) => p.id === 'ana')
    expect(ana?.supervisorNombre).toBe('Sara Dos')
  })

  it('un analista sin supervisor cae en la fila «Sin supervisor», no en una vacía', () => {
    const equipo = [miembro({ id: 'huerfano', nombre: 'Hugo', supervisorId: null })]
    const huerfano = rosterDeEquipoYFilas(equipo, []).find((p) => p.id === 'huerfano')
    expect(huerfano?.supervisorId).toBe(SIN_SUPERVISOR_ID)
    expect(huerfano?.supervisorNombre).toBe(SIN_SUPERVISOR_NOMBRE)
  })

  it('sin organigrama se comporta igual que el roster de siempre', () => {
    expect(rosterDeEquipoYFilas([], VENDIO_ANA)).toEqual(rosterDeFilas(VENDIO_ANA))
  })

  it('la malla le da su fila, en cero, y el total NO se mueve', () => {
    const roster = rosterDeEquipoYFilas(EQUIPO, VENDIO_ANA)
    const sinSembrar = construirMalla(VENDIO_ANA, MES, 'PEN')
    const sembrada = construirMalla(VENDIO_ANA, MES, 'PEN', 'contrato_nuevo', roster)

    const noe = sembrada.grupos.flatMap((g) => g.analistas).find((a) => a.id === 'noe')
    expect(noe).toBeDefined()
    expect(valorCelda(noe?.total ?? { capital: -1, contratos: -1 }, 'capital')).toBe(0)
    // Una fila en cero que moviera el total sería justo el error que más caro
    // sale: un tablero de ventas que suma de la nada.
    expect(valorCelda(sembrada.total, 'capital')).toBe(valorCelda(sinSembrar.total, 'capital'))
  })

  it('en la malla, la FILA manda sobre el roster al colocar el equipo', () => {
    // Precedencia propia de `construirMalla`, aparte de la del roster: si quien
    // llama siembra con el equipo de HOY y la fila trae el de ENTONCES, el
    // dinero se agrupa donde estaba. Sin esta regla, mover a alguien de equipo
    // reescribiría meses ya cerrados.
    const rosterDeHoy = [
      { id: 'ana', nombre: 'Ana', supervisorId: 'sup-1', supervisorNombre: 'Rosa Uno' },
    ]
    const vendioConSara = [
      fila({ analistaId: 'ana', analistaNombre: 'Ana', supervisorId: 'sup-2', supervisorNombre: 'Sara Dos', capital: 90_000 }),
    ]
    const malla = construirMalla(vendioConSara, MES, 'PEN', 'contrato_nuevo', rosterDeHoy)

    expect(malla.grupos.map((g) => g.nombre)).toEqual(['Sara Dos'])
    expect(valorCelda(malla.grupos[0]?.total ?? { capital: -1, contratos: -1 }, 'capital')).toBe(90_000)
  })

  it('filtrarRoster decide con las MISMAS dos condiciones que filtrarFilas', () => {
    const roster = rosterDeEquipoYFilas(EQUIPO, VENDIO_ANA)
    const soloNoe: FiltroFacturacion = { equipo: '', analistas: ['noe'] }
    expect(filtrarRoster(roster, soloNoe).map((p) => p.id)).toEqual(['noe'])
    // Y no arrastra ventas ajenas: Noe no vendió, así que no hay filas.
    expect(filtrarFilas(VENDIO_ANA, soloNoe)).toEqual([])

    const otroEquipo: FiltroFacturacion = { equipo: 'sup-2', analistas: [] }
    expect(filtrarRoster(roster, otroEquipo)).toEqual([])
  })
})

/* ───── El total del día con las dos monedas (Miguel, 11/09/2026) ─────
 * «necesito ver el total de soles y dólares por día». El capital se convierte
 * con el motor ya aprobado (`totalEnSoles`); los contratos se suman tal cual.
 */
describe('total del día con las dos monedas', () => {
  const FILAS_DOS_MONEDAS: readonly FilaFacturacionDia[] = [
    fila({ dia: '2026-09-02', moneda: 'PEN', capital: 300_000, operaciones: 3 }),
    fila({ dia: '2026-09-02', moneda: 'USD', capital: 7_000, operaciones: 1 }),
    fila({ dia: '2026-09-03', moneda: 'PEN', capital: 80_000, operaciones: 1 }),
  ]
  const pen = (): ReturnType<typeof construirMalla> => construirMalla(FILAS_DOS_MONEDAS, MES, 'PEN')
  const usd = (): ReturnType<typeof construirMalla> => construirMalla(FILAS_DOS_MONEDAS, MES, 'USD')
  const indice = (dia: string): number => diasDelMes(MES).indexOf(dia)

  it('convierte el dólar a soles al TC dado y lo suma al del día', () => {
    const t = totalesUnificados(pen(), usd(), 3.75)
    const dia2 = t.porDia[indice('2026-09-02')]
    expect(dia2?.capital.estado).toBe('convertido')
    expect(dia2?.capital.total).toBe(300_000 + 7_000 * 3.75)
    expect(dia2?.capital.tc).toBe(3.75)
  })

  it('sin TC el total NO incluye el dólar, y lo dice', () => {
    const t = totalesUnificados(pen(), usd(), null)
    const dia2 = t.porDia[indice('2026-09-02')]
    expect(dia2?.capital.estado).toBe('solo_pen')
    expect(dia2?.capital.total).toBe(300_000)
    expect(dia2?.capital.usd).toBe(7_000)
  })

  it('un TC inválido no multiplica dinero: 0, negativo o NaN quedan fuera', () => {
    for (const malo of [0, -3.75, Number.NaN]) {
      const t = totalesUnificados(pen(), usd(), malo)
      expect(t.mes.capital.estado).toBe('solo_pen')
      expect(t.mes.capital.tc).toBeNull()
    }
  })

  it('los CONTRATOS se suman tal cual: son cuentas, no dinero', () => {
    const t = totalesUnificados(pen(), usd(), null)
    expect(t.porDia[indice('2026-09-02')]?.contratos).toBe(4)
    expect(t.mes.contratos).toBe(5)
  })

  it('el total del mes cuadra con la suma de sus días', () => {
    const t = totalesUnificados(pen(), usd(), 3.75)
    const sumaDias = t.porDia.reduce((a, d) => a + (d.capital.total ?? 0), 0)
    expect(t.mes.capital.total).toBeCloseTo(sumaDias, 6)
  })

  it('un día sin nada no inventa un total: queda en cero, no en null', () => {
    const t = totalesUnificados(pen(), usd(), 3.75)
    expect(t.porDia[indice('2026-09-20')]?.capital.total).toBe(0)
  })
})

/* ───── Tipos de capital (Miguel, 11/09/2026) ─────
 * Buscó un contrato suyo y no lo encontró: la malla estaba clavada en capital
 * nuevo, así que renovaciones, upgrades y cooperativa no tenían dónde salir.
 * En setiembre eso dejaba fuera S/ 389 300 y US$ 21 000 de dinero real.
 */
describe('tipos de capital', () => {
  const VARIADAS: readonly FilaFacturacionDia[] = [
    fila({ dia: '2026-09-02', tipo: 'contrato_nuevo', capital: 300_000, operaciones: 3 }),
    fila({ dia: '2026-09-02', tipo: 'contrato_renovacion', capital: 10_000, operaciones: 1 }),
    fila({ dia: '2026-09-03', tipo: 'contrato_upgrade', capital: 25_000, operaciones: 1 }),
    fila({ dia: '2026-09-03', tipo: 'cooperativa', capital: 40_000, operaciones: 2 }),
  ]
  const totalDe = (tipo: string): number =>
    valorCelda(construirMalla(VARIADAS, MES, 'PEN', tipo).total, 'capital')

  it('cada tipo enseña lo suyo y nada más', () => {
    expect(totalDe(TIPO_CAPITAL_NUEVO)).toBe(300_000)
    expect(totalDe('contrato_renovacion')).toBe(10_000)
    expect(totalDe('contrato_upgrade')).toBe(25_000)
    expect(totalDe('cooperativa')).toBe(40_000)
  })

  it('«todo» los suma: son capital de la MISMA moneda', () => {
    expect(totalDe(TIPO_TODOS)).toBe(375_000)
  })

  it('«todo» recoge también un tipo que esta pantalla aún no sabe rotular', () => {
    // El servidor puede añadir un tipo mañana. Bajo «todo» tiene que contar: lo
    // contrario sería un total que se llama «todo» y esconde dinero.
    const conFuturo = [...VARIADAS, fila({ dia: '2026-09-04', tipo: 'tipo_del_futuro', capital: 5_000 })]
    expect(valorCelda(construirMalla(conFuturo, MES, 'PEN', TIPO_TODOS).total, 'capital')).toBe(380_000)
    // Pero NO se cuela en ningún tipo concreto.
    expect(valorCelda(construirMalla(conFuturo, MES, 'PEN', TIPO_CAPITAL_NUEVO).total, 'capital')).toBe(300_000)
  })

  it('las monedas NO se mezclan ni siquiera bajo «todo»', () => {
    const conDolares = [...VARIADAS, fila({ dia: '2026-09-02', tipo: 'contrato_renovacion', moneda: 'USD', capital: 10_000 })]
    expect(valorCelda(construirMalla(conDolares, MES, 'PEN', TIPO_TODOS).total, 'capital')).toBe(375_000)
    expect(valorCelda(construirMalla(conDolares, MES, 'USD', TIPO_TODOS).total, 'capital')).toBe(10_000)
  })

  it('el desglose de una celda habla del tipo que se está viendo', () => {
    const soloRenovacion = desgloseDeCelda(VARIADAS, 'a1', '2026-09-02', 'contrato_renovacion')
    expect(soloRenovacion.map((f) => f.tipo)).toEqual(['contrato_renovacion'])
    // Abrir una celda de renovaciones y ver ahí los contratos nuevos
    // contradiría la cifra sobre la que se acaba de pinchar.
    const todo = desgloseDeCelda(VARIADAS, 'a1', '2026-09-02', TIPO_TODOS)
    expect(todo).toHaveLength(2)
  })
})


/* ── Atribución cuando un analista cambia de equipo (auditoría 11/09/2026) ──
 * Era el hallazgo más peligroso: el total de la empresa cuadraba igual, así que
 * ninguna prueba de totales lo habría cazado. El dinero cambiaba de equipo en
 * pantalla y premiaba al supervisor equivocado.
 */
describe('un analista que vendió bajo dos supervisores el mismo mes', () => {
  const CAMBIO: readonly FilaFacturacionDia[] = [
    fila({ dia: '2026-09-02', capital: 100_000, supervisorId: 's1', supervisorNombre: 'Sara Primera' }),
    fila({ dia: '2026-09-20', capital: 60_000, supervisorId: 's2', supervisorNombre: 'Sonia Segunda' }),
  ]

  it('sale en LOS DOS equipos, cada uno con lo suyo', () => {
    const m = construirMalla(CAMBIO, MES, 'PEN')
    const porEquipo = Object.fromEntries(m.grupos.map((g) => [g.nombre, valorCelda(g.total, 'capital')]))
    expect(porEquipo).toEqual({ 'Sara Primera': 100_000, 'Sonia Segunda': 60_000 })
  })

  it('el total de la empresa no se mueve — por eso el fallo era invisible', () => {
    expect(valorCelda(construirMalla(CAMBIO, MES, 'PEN').total, 'capital')).toBe(160_000)
  })

  it('el orden de las filas NO decide a qué equipo va el dinero', () => {
    const alReves = construirMalla([...CAMBIO].reverse(), MES, 'PEN')
    const porEquipo = Object.fromEntries(alReves.grupos.map((g) => [g.nombre, valorCelda(g.total, 'capital')]))
    expect(porEquipo).toEqual({ 'Sara Primera': 100_000, 'Sonia Segunda': 60_000 })
  })

  it('el organigrama de HOY no le añade una fila fantasma en cero', () => {
    // Si hoy está con Sonia, sembrar el roster NO debe crear una tercera fila
    // vacía: ya tiene dos, y las dos con dinero real.
    const rosterHoy = [{ id: 'a1', nombre: 'Ana Uno', supervisorId: 's2', supervisorNombre: 'Sonia Segunda' }]
    const m = construirMalla(CAMBIO, MES, 'PEN', TIPO_CAPITAL_NUEVO, rosterHoy)
    expect(m.grupos.flatMap((g) => g.analistas)).toHaveLength(2)
  })

  it('filtrar por esa persona trae sus DOS equipos, no uno', () => {
    const soloElla: FiltroFacturacion = { equipo: '', analistas: ['a1'] }
    const m = construirMalla(filtrarFilas(CAMBIO, soloElla), MES, 'PEN')
    expect(m.grupos.map((g) => g.nombre).sort()).toEqual(['Sara Primera', 'Sonia Segunda'])
  })

  it('ofrece ambos equipos en el selector y conserva al analista al elegir el segundo', () => {
    const roster = rosterDeEquipoYFilas([], CAMBIO)
    expect(roster.map((p) => p.supervisorId)).toEqual(['s1', 's2'])
    expect(equiposDeRoster(roster).map((e) => e.id)).toEqual(['s1', 's2'])
    expect(conciliarFiltro({ equipo: 's2', analistas: ['a1'] }, roster).analistas).toEqual(['a1'])
    expect(filtrarRoster(roster, { equipo: 's2', analistas: ['a1'] }).map((p) => p.supervisorId)).toEqual(['s2'])
  })

  it('mantiene los dos equipos al cambiar de moneda aunque uno quede en cero', () => {
    const filas = [CAMBIO[0]!, { ...CAMBIO[1]!, moneda: 'USD' as const }]
    const roster = rosterDeEquipoYFilas([], filas)
    const pen = construirMalla(filas, MES, 'PEN', TIPO_CAPITAL_NUEVO, roster)
    const usd = construirMalla(filas, MES, 'USD', TIPO_CAPITAL_NUEVO, roster)
    expect(pen.grupos.map((g) => g.id).sort()).toEqual(['s1', 's2'])
    expect(usd.grupos.map((g) => g.id).sort()).toEqual(['s1', 's2'])
    expect(pen.grupos.find((g) => g.id === 's2')?.total.capital).toBe(0)
    expect(usd.grupos.find((g) => g.id === 's1')?.total.capital).toBe(0)
  })

  it('acota el detalle al equipo y a los días elegidos', () => {
    expect(desgloseDeCelda(CAMBIO, 'a1', null, TIPO_TODOS, undefined, 's2', ['2026-09-20'])
      .map((f) => f.capital)).toEqual([60_000])
    expect(desgloseDeCelda(CAMBIO, 'a1', null, TIPO_TODOS, undefined, 's2', ['2026-09-02']))
      .toHaveLength(0)
  })
})

it('la escala de contratos en Todo S/ usa el máximo de contratos, no el de capital', () => {
  const filas = [
    fila({ dia: '2026-09-02', moneda: 'PEN', capital: 100_000, operaciones: 1 }),
    fila({ dia: '2026-09-03', moneda: 'USD', capital: 100, operaciones: 8 }),
  ]
  const combinada = combinarEnSoles(
    construirMalla(filas, MES, 'PEN'),
    construirMalla(filas, MES, 'USD'),
    3.75,
  )
  expect(combinada?.maxAnalista.contratos).toBe(8)
  expect(combinada?.maxGrupo.contratos).toBe(8)
  expect(combinada?.maxDia.contratos).toBe(8)
  expect(combinada?.maxDia.capital).toBe(100_000)
})

/* ───── Periodo: mes, semana o día (Miguel, 11/09/2026) ───── */
describe('tramo: mes, semana y día', () => {
  it('la semana va de LUNES a domingo', () => {
    // El 10/09/2026 es jueves; su semana empieza el lunes 7.
    expect(lunesDeLaSemana('2026-09-10')).toBe('2026-09-07')
    // Y un domingo pertenece a la semana que ACABA, no a la que empieza.
    expect(lunesDeLaSemana('2026-09-13')).toBe('2026-09-07')
  })

  it('cada tramo trae los días que le tocan', () => {
    expect(diasDelPeriodo('dia', '2026-09-10')).toEqual(['2026-09-10'])
    expect(diasDelPeriodo('semana', '2026-09-10')).toEqual([
      '2026-09-07', '2026-09-08', '2026-09-09', '2026-09-10',
      '2026-09-11', '2026-09-12', '2026-09-13',
    ])
    expect(diasDelPeriodo('mes', '2026-09-10')).toHaveLength(30)
  })

  it('una semana puede cruzar de mes, y no se parte', () => {
    // El 1 de octubre de 2026 es jueves: su semana empieza el 28 de setiembre.
    expect(diasDelPeriodo('semana', '2026-10-01')).toEqual([
      '2026-09-28', '2026-09-29', '2026-09-30',
      '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
    ])
  })

  it('las flechas se mueven en la unidad elegida', () => {
    expect(periodoDesplazado('dia', '2026-09-10', -1)).toBe('2026-09-09')
    expect(periodoDesplazado('semana', '2026-09-10', -1)).toBe('2026-09-03')
    expect(periodoDesplazado('mes', '2026-09-10', -1)).toBe('2026-08-01')
    // Y cruzan el cambio de mes sin tropezar.
    expect(periodoDesplazado('dia', '2026-09-01', -1)).toBe('2026-08-31')
    expect(periodoDesplazado('semana', '2026-10-01', -1)).toBe('2026-09-24')
  })

  it('la malla de un tramo suma SOLO ese tramo', () => {
    const filas = [
      fila({ dia: '2026-09-07', capital: 10_000 }),
      fila({ dia: '2026-09-10', capital: 20_000 }),
      fila({ dia: '2026-09-20', capital: 99_000 }), // fuera de la semana
    ]
    const semana = construirMallaDeDias(filas, diasDelPeriodo('semana', '2026-09-10'), MES, 'PEN')
    expect(valorCelda(semana.total, 'capital')).toBe(30_000)
    expect(semana.dias).toHaveLength(7)

    const dia = construirMallaDeDias(filas, diasDelPeriodo('dia', '2026-09-10'), MES, 'PEN')
    expect(valorCelda(dia.total, 'capital')).toBe(20_000)
    expect(dia.dias).toHaveLength(1)
  })

  it('el rótulo nombra el tramo, no siempre el mes', () => {
    expect(etiquetaPeriodo('mes', '2026-09-10')).toMatch(/setiembre/i)
    expect(etiquetaPeriodo('dia', '2026-09-10')).toMatch(/10/)
    expect(etiquetaPeriodo('semana', '2026-09-10')).toMatch(/al/)
  })
})



describe('qué meses hay que pedirle al servidor', () => {
  it('los del tramo, sin repetir y en orden', () => {
    // Una semana puede cruzar de mes; el servidor entrega un mes por llamada.
    expect(mesesQueTocan(diasDelPeriodo('semana', '2026-10-01'))).toEqual([
      '2026-09-01', '2026-10-01',
    ])
    expect(mesesQueTocan(diasDelPeriodo('mes', '2026-09-10'))).toEqual(['2026-09-01'])
  })
})

// Fase de pantalla del 09/10: el oráculo sigue siendo ESTE modelo, sin modificarlo.
describe('cifras idénticas al proyectar la hoja aprobada', () => {
  it('conserva por analista, día, equipo y titular los mismos importes y operaciones en las tres monedas', async () => {
    const { columnasDeDias, proyectarMalla, columnasDeTipos } = await import('../screens/facturacion/presentacion')
    const dias = diasDelMes(MES)
    const filas = [...FILAS,
      fila({ dia: '2026-09-10', tipo: 'cooperativa', capital: 4_850, analistaId: 'elizabeth', analistaNombre: 'ELIZABETH' }),
      fila({ dia: '2026-09-10', tipo: 'contrato_upgrade', moneda: 'USD', capital: 1_201.53 }),
      fila({ dia: '2026-09-10', tipo: 'contrato_renovacion', capital: 785.35 }),
      // Incluso una fila futura no se pierde al plegar columnas.
      fila({ dia: '2026-09-29', capital: 456.78 }),
    ]
    const roster = rosterDeEquipoYFilas([{ id: 'sin-ventas', nombre: 'Activa sin ventas', rol: 'vendedor', supervisorId: 's1', activo: true }], filas)
    const pen = construirMallaDeDias(filas, dias, MES, 'PEN', TIPO_TODOS, roster)
    const usd = construirMallaDeDias(filas, dias, MES, 'USD', TIPO_TODOS, roster)
    const total = combinarEnSoles(pen, usd, 3.751)!
    for (const original of [pen, usd, total]) {
      const columnas = columnasDeDias(dias, '2026-09-10')
      const hoja = proyectarMalla(original, columnas)
      expect(hoja.total).toBe(original.total)
      for (let i = 0; i < 10; i += 1) expect(hoja.totalPorDia[i]).toEqual(original.totalPorDia[i])
      expect(hoja.totalPorDia.at(-1)).toEqual(original.totalPorDia.slice(10).reduce((s, c) => ({ capital: s.capital + c.capital, contratos: s.contratos + c.contratos }), { capital: 0, contratos: 0 }))
      for (const grupo of original.grupos) {
        const nuevo = hoja.grupos.find((g) => g.id === grupo.id)!
        expect(nuevo.total).toBe(grupo.total)
        for (const analista of grupo.analistas) {
          const nueva = nuevo.analistas.find((a) => a.id === analista.id)!
          expect(nueva.total).toBe(analista.total)
          expect(nueva.dias.slice(0, 10)).toEqual(analista.dias.slice(0, 10))
        }
      }
    }
    // El titular usa exactamente las mismas dos mallas, sin redondeos de la presentación.
    expect(totalesUnificados(proyectarMalla(pen, columnasDeDias(dias, '2026-09-10')), proyectarMalla(usd, columnasDeDias(dias, '2026-09-10')), 3.751).mes)
      .toEqual(totalesUnificados(pen, usd, 3.751).mes)
    for (const vista of ['PEN', 'USD', 'TOTAL'] as const) {
      const d = ['2026-09-10']
      const p = construirMallaDeDias(filas, d, MES, 'PEN', TIPO_TODOS, roster)
      const u = construirMallaDeDias(filas, d, MES, 'USD', TIPO_TODOS, roster)
      const original = vista === 'TOTAL' ? combinarEnSoles(p, u, 3.751)! : vista === 'PEN' ? p : u
      const hoja = proyectarMalla(original, columnasDeTipos(filas, d, MES, TIPO_TODOS, roster, vista, 3.751))
      expect(hoja.total).toEqual(original.total)
      for (const g of hoja.grupos) {
        expect(g.dias.reduce((n, c) => n + c.capital, 0)).toBeCloseTo(g.total.capital, 8)
        for (const a of g.analistas) {
          expect(a.dias.reduce((n, c) => n + c.capital, 0)).toBeCloseTo(a.total.capital, 8)
          expect(a.dias.reduce((n, c) => n + c.contratos, 0)).toBe(a.total.contratos)
        }
      }
    }
  })
})
