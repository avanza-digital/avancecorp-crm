import { describe, expect, it } from 'vitest'
import { defaults, type CitaEjemplo, type FiltrosCitas } from './modelo'
import {
  calcularProyeccion, csvCitasProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas, opcionesPersonas,
  periodoProyeccion, repartirEnTramos, type ConversionProyeccion, type FiltrosColumnas, type FuenteProyeccion, type PersonaProyeccion,
  type ReunionClienteProyeccion,
} from './proyeccion'
import {
  atajosRango, diasPermitidos, errorRango, mesesDelRango, rangoInicial, rotuloRango, tiempoEfectivo, tramosDelRango, type RangoProyeccion,
} from './proyeccion-rango'

// Hoy: lunes 19/10/2026, 12:00 de Lima. Octubre tiene 31 días; van 19.
const HOY = '2026-10-19T17:00:00Z'
const OCTUBRE: RangoProyeccion = { desde: '2026-10-01', hasta: '2026-10-31' }
const TC = 3.75
const EQUIPOS = { ana: ['Ana Torres', 'sup-1', 'Claudia Ríos'], luis: ['Luis Vega', 'sup-1', 'Claudia Ríos'], diego: ['Diego Salas', 'sup-2', 'Javier Vega'], mateo: ['Mateo Paredes', 'sup-2', 'Javier Vega'] } as const

function cita(id: string, analista: keyof typeof EQUIPOS, cambios: Partial<CitaEjemplo>): CitaEjemplo {
  const [analistaNombre, supervisorId, supervisor] = EQUIPOS[analista]
  return {
    id, leadId: `lead-${id}`, nombre: `Persona ${id}`, telefono: '900000000', analista, analistaNombre, supervisor, supervisorId,
    fecha: '2026-10-10', hora: '10:00', estado: 'programada', modalidad: 'Virtual', origen: 'Formulario', moneda: 'PEN', monto: 10_000,
    resultado: 'Sin resultado registrado', cerrado: false, seguimiento: false, nuevaFecha: null, nota: '', creadoEn: '2026-10-05T15:00:00Z',
    ...cambios,
  }
}

/** Mes lleno: 3 analistas con citas en octubre en dos equipos y uno (Mateo) con su única cita creada en septiembre. */
function mesLleno() {
  const citas: CitaEjemplo[] = [
    cita('a1', 'ana', { leadId: 'lead-1', estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z', creadoEn: '2026-10-02T15:00:00Z' }),
    cita('a2', 'ana', { leadId: 'lead-2', estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z', moneda: 'USD', monto: 2_000, creadoEn: '2026-10-03T15:00:00Z' }),
    cita('a3', 'ana', { leadId: 'lead-3', estado: 'no_show', monto: 20_000, origen: 'Referido', creadoEn: '2026-10-04T15:00:00Z' }),
    cita('a4', 'ana', { leadId: 'lead-4', monto: null, creadoEn: '2026-10-12T15:00:00Z' }),
    cita('l1', 'luis', { leadId: 'lead-7', monto: 5_000, creadoEn: '2026-10-18T15:00:00Z' }),
    cita('d1', 'diego', { leadId: 'lead-5', estado: 'realizada', asistioEn: '2026-10-09T16:00:00Z', monto: 50_000, creadoEn: '2026-10-08T15:00:00Z' }),
    cita('d2', 'diego', { leadId: 'lead-6', estado: 'cancelada', monto: 30_000, origen: 'referido', creadoEn: '2026-10-15T15:00:00Z' }),
    cita('m1', 'mateo', { leadId: 'lead-8', fecha: '2026-10-02', creadoEn: '2026-09-28T15:00:00Z' }),
  ]
  const conversiones: ConversionProyeccion[] = [
    // Venta con fecha comercial posterior a su entrevista (a1): cuenta en la conversión de Ana.
    { lead_id: 'lead-1', perfil_id: 'perfil-1', convertido_en: '2026-10-08T15:00:00Z', fecha_comercial: '2026-10-08', analista_id: 'ana', supervisor_id: 'sup-1' },
    // Ya era cliente cuando Diego le creó la cita (d1): va a Clientes y no convierte.
    { lead_id: 'lead-5', perfil_id: 'perfil-5', convertido_en: '2026-10-01T15:00:00Z', fecha_comercial: '2026-10-01', analista_id: 'diego', supervisor_id: 'sup-2' },
  ]
  const fuente: FuenteProyeccion = { citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones }
  return { citas, conversiones, fuente }
}
const fila = (hoja: ReturnType<typeof calcularProyeccion>, id: string) => hoja.filas.find(f => f.id === id)
const ids = (lista: readonly { cita: { id: string } }[]) => lista.map(c => c.cita.id).sort()
const con = (fuente: FuenteProyeccion, filtros: Partial<FiltrosCitas>): FuenteProyeccion => ({ ...fuente, filtros: { ...fuente.filtros, ...filtros } })
const en = (fuente: FuenteProyeccion, desde: string, hasta: string): FuenteProyeccion => ({ ...fuente, rango: { desde, hasta } })

describe('Proyección de citas: cohorte y columnas', () => {
  it('mes lleno: hoja plana, una fila por analista ordenada por citas, y cada columna con su regla (% Entrev. sobre citas resueltas)', () => {
    const hoja = calcularProyeccion(mesLleno().fuente)
    // Sin bandas por equipo: el orden es global, aunque mezcle equipos.
    expect(hoja.filas.map(f => [f.id, f.supervisor, f.citas.length])).toEqual([
      ['ana', 'Claudia Ríos', 4], ['diego', 'Javier Vega', 2], ['luis', 'Claudia Ríos', 1],
    ])
    expect(hoja.tramos).toEqual([])
    const ana = fila(hoja, 'ana')!
    expect(ana.citas).toHaveLength(4)
    // 30 000 PEN + 2 000 USD × 3,75; la cita sin monto no suma pero sí divide el ticket.
    expect(ana).toMatchObject({ montoPen: 30_000, montoUsd: 2_000, monto: 37_500, ticket: 9_375, pctConversion: 50, pendienteTc: false })
    // % Entrev.: 2 realizadas ÷ 3 resueltas (a3 no asistió); la programada a4 no es base.
    expect(ids(ana.resueltas)).toEqual(['a1', 'a2', 'a3'])
    expect(ana.pctEntrevistas).toBeCloseTo(200 / 3, 10)
    expect(ids(ana.conMonto)).toEqual(['a1', 'a2', 'a3'])
    expect(ids(ana.convertidas)).toEqual(['a1'])
    // Ritmo: 4 citas en 19 de 31 días → 124/19 citas esperadas × 2/3 × 50 % × S/ 9 375.
    expect(ana.citasEsperadas).toBeCloseTo(124 / 19, 10)
    expect(ana.proyectado).toBeCloseTo(124 / 19 * (2 / 3) * 0.5 * 9_375, 6)
    expect([ana.referidos.length, ana.clientes.length, ana.leads.length]).toEqual([1, 0, 3])
    const diego = fila(hoja, 'diego')!
    // d2 cancelada no es base: 1 realizada ÷ 1 resuelta.
    expect(diego).toMatchObject({ monto: 80_000, ticket: 40_000, pctEntrevistas: 100, pctConversion: 0, proyectado: 0 })
    expect([ids(diego.referidos), ids(diego.clientes), ids(diego.leads)]).toEqual([['d2'], ['d1'], []])
    // Sin citas resueltas no hay base: ni % Entrev. ni proyectado (nunca 0 %).
    expect(fila(hoja, 'luis')).toMatchObject({ pctEntrevistas: null, pctConversion: null, proyectado: null, ticket: 5_000 })
  })

  it('el total recalcula sobre todas las citas, suma proyectados con base y nunca promedia tasas ni tickets', () => {
    const { total, filas } = calcularProyeccion(mesLleno().fuente)
    expect(total.citas).toHaveLength(7)
    expect(total).toMatchObject({ monto: 122_500, ticket: 17_500, personasEntrevistadas: 3, personasClientes: 1 })
    // 3 realizadas ÷ 4 resueltas de todas las citas: no es el promedio de 66,7 % y 100 %.
    expect(total.pctEntrevistas).toBe(75)
    expect(total.pctConversion).toBeCloseTo(100 / 3, 10)
    expect(total.proyectado).toBeCloseTo(filas.reduce((n, f) => n + (f.proyectado ?? 0), 0), 6)
    expect(total.referidos.length + total.clientes.length + total.leads.length).toBe(total.citas.length)
  })

  it('mes vacío (estado de producción hoy): sin filas, total en cero y tasas sin base', () => {
    const hoja = calcularProyeccion({ citas: [], filtros: defaults('2026-10'), rango: rangoInicial('2026-10', '2026-10-19'), corte: HOY, tipoCambio: null, conversiones: [] })
    expect(hoja.filas).toEqual([])
    expect(hoja.requiereTc).toBe(false)
    expect(hoja.total).toMatchObject({ monto: 0, ticket: null, pctEntrevistas: null, pctConversion: null, proyectado: null, pendienteTc: false })
    expect(hoja.total.citas).toEqual([])
    expect(csvProyeccion(hoja, 'Octubre 2026').split('\r\n')).toEqual([
      '﻿"Periodo","Equipo","Analista","Citas","Monto S/","Ticket cita S/","% Entrev.","% Conv.","Proyectado citas S/","Referidos","Clientes","Leads"',
      '"Octubre 2026","","Total · 0 analistas","0","0","","","","","0","0","0"',
    ])
  })

  it('sin tipo de cambio, el monto con dólares queda pendiente y el ticket y el proyectado sin base', () => {
    const hoja = calcularProyeccion({ ...mesLleno().fuente, tipoCambio: null })
    expect(hoja.requiereTc).toBe(true)
    expect(fila(hoja, 'ana')).toMatchObject({ pendienteTc: true, monto: null, ticket: null, proyectado: null, pctConversion: 50 })
    // Un analista solo en soles sigue calculándose.
    expect(fila(hoja, 'diego')).toMatchObject({ pendienteTc: false, monto: 80_000, ticket: 40_000, proyectado: 0 })
    expect(hoja.total).toMatchObject({ pendienteTc: true, monto: null, ticket: null, proyectado: 0 })
    const csv = csvProyeccion(hoja, 'Octubre 2026')
    expect(csv).toContain('"Octubre 2026","Claudia Ríos","Ana Torres","4","Pendiente de TC",""')
    expect(csv).toContain('"Total · 3 analistas","7","Pendiente de TC",""')
    expect(hoja.cohorte.find(c => c.cita.id === 'a2')!.enSoles).toBeNull()
  })

  it('periodo cerrado: las citas esperadas son las registradas', () => {
    const hoja = calcularProyeccion({ ...mesLleno().fuente, corte: '2026-11-03T15:00:00Z' })
    expect(hoja.periodo).toMatchObject({ cerrado: true, dias: 31, transcurridos: 31 })
    expect(fila(hoja, 'ana')).toMatchObject({ citasEsperadas: 4 })
    expect(fila(hoja, 'ana')!.proyectado).toBeCloseTo(4 * (2 / 3) * 0.5 * 9_375, 6)
  })

  it('la cohorte es por fecha de creación: el analista cuya cita se creó en otro mes no tiene fila', () => {
    const { fuente } = mesLleno()
    expect(fila(calcularProyeccion(fuente), 'mateo')).toBeUndefined()
    // De la consulta de arriba solo cuenta el supervisor: semana, día, analista y búsqueda
    // (ocultos en la Proyección) no recortan nada; el analista se acota con su embudo.
    expect(calcularProyeccion(con(fuente, { semana: '1', dia: '2026-10-02', analista: 'mateo', q: 'persona d2' })).total.citas).toHaveLength(7)
    expect(calcularProyeccion(con(fuente, { equipo: 'sup-2' })).filas.map(f => f.id)).toEqual(['diego'])
  })
})

describe('Proyección de citas: rango Desde–Hasta', () => {
  it('rango dentro del mes: solo las citas creadas entre esas fechas y el ritmo sobre sus días', () => {
    const hoja = calcularProyeccion(en(mesLleno().fuente, '2026-10-03', '2026-10-12'))
    expect(hoja.total.citas.map(c => c.cita.id).sort()).toEqual(['a2', 'a3', 'a4', 'd1'])
    expect(hoja.periodo).toMatchObject({ dias: 10, transcurridos: 10, cerrado: true })
    // Rango cerrado: las citas esperadas son las registradas.
    expect(fila(hoja, 'ana')!.citasEsperadas).toBe(3)
    // Rango abierto (1–25 con hoy 19): 4 citas de Ana en 19 de 25 días.
    const abierto = calcularProyeccion(en(mesLleno().fuente, '2026-10-01', '2026-10-25'))
    expect(fila(abierto, 'ana')!.citasEsperadas).toBeCloseTo(4 / 19 * 25, 10)
  })

  it('rango que cruza dos meses: entran las citas creadas a fines del mes anterior', () => {
    const hoja = calcularProyeccion(en(mesLleno().fuente, '2026-09-25', '2026-10-05'))
    expect(hoja.filas.map(f => [f.id, f.citas.map(c => c.cita.id)])).toEqual([['ana', ['a1', 'a2', 'a3']], ['mateo', ['m1']]])
  })

  it('rango futuro: sin citas, sin filas y sin proyección', () => {
    const hoja = calcularProyeccion(en(mesLleno().fuente, '2026-10-22', '2026-10-31'))
    expect(hoja.filas).toEqual([])
    expect(hoja.periodo).toMatchObject({ transcurridos: 0, cerrado: false })
    expect(hoja.total).toMatchObject({ proyectado: null, ticket: null, pctEntrevistas: null })
  })

  it('valor inicial, meses, validación y rótulo', () => {
    expect(rangoInicial('2026-10', '2026-10-19')).toEqual({ desde: '2026-10-01', hasta: '2026-10-19' })
    expect(rangoInicial('2026-09', '2026-10-19')).toEqual({ desde: '2026-09-01', hasta: '2026-09-30' })
    expect(rangoInicial('2026-11', '2026-10-19')).toEqual({ desde: '2026-11-01', hasta: '2026-11-30' })
    expect(rangoInicial('2028-02', '2026-10-19')).toEqual({ desde: '2028-02-01', hasta: '2028-02-29' })
    expect(mesesDelRango({ desde: '2026-11-20', hasta: '2027-02-03' })).toEqual(['2026-11', '2026-12', '2027-01', '2027-02'])
    expect(errorRango({ desde: '2026-05-01', hasta: '2026-10-31' })).toBe('')
    expect(errorRango({ desde: '2026-04-30', hasta: '2026-10-01' })).toBe('El rango admite hasta 6 meses.')
    expect(errorRango({ desde: '2026-10-05', hasta: '2026-10-04' })).toBe('«Desde» debe ser anterior o igual a «Hasta».')
    expect(errorRango({ desde: '', hasta: '2026-10-04' })).toBe('Introduce fechas válidas.')
    expect(rotuloRango({ desde: '2026-10-01', hasta: '2026-10-19' })).toBe('1–19 oct 2026')
    expect(rotuloRango({ desde: '2026-10-19', hasta: '2026-10-19' })).toBe('19 oct 2026')
    expect(rotuloRango({ desde: '2026-09-28', hasta: '2026-10-03' })).toBe('28 set – 3 oct 2026')
    expect(rotuloRango({ desde: '2025-12-28', hasta: '2026-01-03' })).toBe('28 dic 2025 – 3 ene 2026')
    expect(rotuloRango({ desde: '2026-13-01', hasta: '2026-10-03' })).toBe('Periodo no válido')
  })

  it('atajos: hoy, semana desde el lunes, mes, mes pasado y semanas comerciales del mes de «Hasta»', () => {
    // Miércoles 21/10/2026; «Hasta» en febrero de 2028 (bisiesto).
    const atajos = Object.fromEntries(atajosRango('2026-10-21', '2028-02-10').map(a => [a.etiqueta, `${a.rango.desde}/${a.rango.hasta}`]))
    expect(atajos).toEqual({
      Hoy: '2026-10-21/2026-10-21', 'Esta semana': '2026-10-19/2026-10-21', Mes: '2026-10-01/2026-10-21', 'Mes pasado': '2026-09-01/2026-09-30',
      S1: '2028-02-01/2028-02-07', S2: '2028-02-08/2028-02-14', S3: '2028-02-15/2028-02-21', S4: '2028-02-22/2028-02-29',
    })
    // Lunes: la semana es solo hoy. Domingo: desde el lunes anterior. Enero: el mes pasado es diciembre del año anterior.
    expect(atajosRango('2026-10-19', '2026-10-19')[1]!.rango).toEqual({ desde: '2026-10-19', hasta: '2026-10-19' })
    expect(atajosRango('2026-10-25', '2026-10-25')[1]!.rango).toEqual({ desde: '2026-10-19', hasta: '2026-10-25' })
    expect(atajosRango('2027-01-05', '2027-01-05')[3]!.rango).toEqual({ desde: '2026-12-01', hasta: '2026-12-31' })
  })
})

describe('Proyección de citas: embudos de columna', () => {
  it('el filtro de personas en Clientes recorta solo las citas de clientes y un analista vacío desaparece', () => {
    const { fuente } = mesLleno()
    const base = calcularProyeccion(fuente)
    expect(opcionesPersonas(base, {}, 'cliente')).toEqual([{ id: 'lead:lead-5', nombre: 'Persona d1', citas: 1 }])
    const sinClientes = calcularProyeccion(fuente, { personas: { cliente: [] } })
    expect(fila(sinClientes, 'diego')!.citas.map(c => c.cita.id)).toEqual(['d2'])
    expect(fila(sinClientes, 'ana')!.citas).toHaveLength(4)
    const vacio = calcularProyeccion(fuente, { personas: { cliente: [], referido: [] } })
    expect(fila(vacio, 'diego')).toBeUndefined()
    expect(vacio.filas.map(f => f.id)).toEqual(['ana', 'luis'])
    // La lista de personas de un origen ignora su propio embudo para poder volver a marcar.
    expect(opcionesPersonas(vacio, { personas: { cliente: [], referido: [] } }, 'cliente')).toHaveLength(1)
  })

  it('Solo dólares deja las citas en USD y cuenta cada moneda con su monto original', () => {
    const { fuente } = mesLleno()
    const hoja = calcularProyeccion(fuente, { monedas: ['USD'] })
    expect(hoja.filas.map(f => [f.id, f.citas.length])).toEqual([['ana', 1]])
    expect(hoja.total).toMatchObject({ monto: 7_500, ticket: 7_500 })
    expect(opcionesMonedas(hoja, { monedas: ['USD'] })).toEqual({ PEN: { citas: 6, monto: 115_000 }, USD: { citas: 1, monto: 2_000 } })
  })

  it('analistas con conteo, Mín/Máx por fila y orden con «—» al final', () => {
    const { fuente } = mesLleno()
    const base = calcularProyeccion(fuente)
    expect(opcionesAnalistas(base, {})).toEqual([
      { id: 'ana', nombre: 'Ana Torres', citas: 4 }, { id: 'diego', nombre: 'Diego Salas', citas: 2 }, { id: 'luis', nombre: 'Luis Vega', citas: 1 },
    ])
    expect(calcularProyeccion(fuente, { analistas: ['luis', 'diego'] }).filas.map(f => f.id)).toEqual(['diego', 'luis'])
    expect(calcularProyeccion(fuente, { rangos: { citas: { min: 2 } } }).filas.map(f => f.id)).toEqual(['ana', 'diego'])
    // Una fila sin base no cumple ningún rango.
    expect(calcularProyeccion(fuente, { rangos: { conversion: { max: 10 } } }).filas.map(f => f.id)).toEqual(['diego'])
    expect(calcularProyeccion(fuente, { rangos: { monto: { min: 10_000, max: 50_000 } } }).filas.map(f => f.id)).toEqual(['ana'])
    const ordenar = (columna: 'analista' | 'proyectado' | 'ticket', direccion: 'asc' | 'desc') => calcularProyeccion(fuente, {}, { columna, direccion }).filas.map(f => f.id)
    expect(ordenar('analista', 'desc')).toEqual(['luis', 'diego', 'ana'])
    // Luis no tiene base: su «—» va al final en los dos sentidos.
    expect(ordenar('proyectado', 'asc')).toEqual(['diego', 'ana', 'luis'])
    expect(ordenar('proyectado', 'desc')).toEqual(['ana', 'diego', 'luis'])
    expect(ordenar('ticket', 'asc')).toEqual(['luis', 'ana', 'diego'])
  })
})

describe('Proyección de citas: identidad y clientes', () => {
  it('dos leads de la misma persona cuentan como una persona entrevistada y como cliente', () => {
    const persona = 'persona:00000000-0000-4000-8000-000000000001'
    const poblacion: PersonaProyeccion[] = [{ lead_id: 'lead-x', identidad_persona: persona }, { lead_id: 'lead-y', identidad_persona: persona }]
    const citas = [
      cita('x1', 'ana', { leadId: 'lead-x', estado: 'realizada', asistioEn: '2026-10-05T16:00:00Z', creadoEn: '2026-10-03T15:00:00Z' }),
      cita('y1', 'ana', { leadId: 'lead-y', estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z', creadoEn: '2026-10-04T15:00:00Z' }),
      // Creada después de que la persona se convirtiera (por el otro lead): ya es cliente.
      cita('x2', 'ana', { leadId: 'lead-x', creadoEn: '2026-10-12T15:00:00Z' }),
    ]
    const conversiones = [{ lead_id: 'lead-y', perfil_id: 'perfil-y', convertido_en: '2026-10-10T15:00:00Z', fecha_comercial: '2026-10-10', analista_id: 'ana' }]
    const ana = calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones, poblacion }).filas[0]!
    expect(ana).toMatchObject({ personasEntrevistadas: 1, personasClientes: 1, pctConversion: 100 })
    expect(ids(ana.convertidas)).toEqual(['x1', 'y1'])
    expect(ids(ana.clientes)).toEqual(['x2'])
    // Sin la identidad común, son dos personas y solo una se convirtió.
    const separados = calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones }).filas[0]!
    expect(separados).toMatchObject({ personasEntrevistadas: 2, personasClientes: 1, pctConversion: 50 })
    expect(separados.clientes).toEqual([])
  })

  it('respaldo de esCliente: sin el campo, decide la conversión anterior a la creación; con el campo, manda el servidor', () => {
    const { fuente, citas } = mesLleno()
    const marcar = (id: string, esCliente: boolean) => citas.map(c => c.id === id ? { ...c, esCliente } : c)
    expect(calcularProyeccion(fuente).cohorte.find(c => c.cita.id === 'd1')!.origen).toBe('cliente')
    expect(calcularProyeccion({ ...fuente, citas: marcar('d1', false) }).cohorte.find(c => c.cita.id === 'd1')!.origen).toBe('lead')
    // El servidor puede saber que es cliente aunque la conversión no venga en la consulta.
    expect(calcularProyeccion({ ...fuente, citas: marcar('a3', true) }).cohorte.find(c => c.cita.id === 'a3')!.origen).toBe('cliente')
    // Sin conversiones del servidor: nadie es cliente por respaldo y la conversión queda sin base (no 0 %).
    const sinDatos = calcularProyeccion({ ...fuente, conversiones: null })
    expect(sinDatos.total.clientes).toEqual([])
    expect(fila(sinDatos, 'ana')).toMatchObject({ pctConversion: null, proyectado: null })
  })

  it('Referidos reconoce el origen con cualquier escritura y un referido que ya es cliente cuenta como cliente', () => {
    const citas = ['Referido', 'referido', ' REFERIDO ', 'Formulario', 'Referido'].map((origen, i) =>
      cita(`r${i}`, 'ana', { leadId: `lead-r${i}`, origen, creadoEn: '2026-10-05T15:00:00Z' }))
    const hoja = calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC,
      // El respaldo de «cliente» no mira al dueño de la venta.
      conversiones: [{ lead_id: 'lead-r4', convertido_en: '2026-10-01T15:00:00Z', analista_id: null }] })
    expect([ids(hoja.total.referidos), ids(hoja.total.clientes), ids(hoja.total.leads)]).toEqual([['r0', 'r1', 'r2'], ['r4'], ['r3']])
  })
})

describe('Proyección de citas: periodo y CSV', () => {
  it('periodo del rango: días, transcurridos y cierre', () => {
    expect(periodoProyeccion({ desde: '2026-10-22', hasta: '2026-10-31' }, HOY)).toMatchObject({ dias: 10, transcurridos: 0, cerrado: false })
    expect(periodoProyeccion({ desde: '2026-10-15', hasta: '2026-10-21' }, HOY)).toMatchObject({ dias: 7, transcurridos: 5, cerrado: false })
    expect(periodoProyeccion({ desde: '2026-10-19', hasta: '2026-10-19' }, HOY)).toMatchObject({ dias: 1, transcurridos: 1, cerrado: false })
    expect(periodoProyeccion({ desde: '2026-09-25', hasta: '2026-10-05' }, HOY)).toMatchObject({ dias: 11, transcurridos: 11, cerrado: true })
    expect(periodoProyeccion({ desde: '2026-10-05', hasta: '2026-10-01' }, HOY)).toBeNull()
    expect(periodoProyeccion(OCTUBRE, 'no es fecha')).toBeNull()
  })

  it('el CSV de la hoja lleva el ticket por cita y el total; el de la lista, el monto original y en soles', () => {
    const hoja = calcularProyeccion(mesLleno().fuente)
    const lineas = csvProyeccion(hoja, 'Octubre 2026').split('\r\n')
    expect(lineas[0]).toContain('"Monto S/","Ticket cita S/","% Entrev."')
    // Ana: 124/19 × 2/3 × 50 % × 9 375 = 20 394,74.
    expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","4","37500","9375","66.7","50","20394.74","1","0","3"')
    expect(lineas.at(-1)).toBe('"Octubre 2026","","Total · 3 analistas","7","122500","17500","75","33.3","20394.74","2","1","4"')
    const lista = csvCitasProyeccion(fila(hoja, 'ana')!.conMonto.filter(c => c.cita.id === 'a2')).split('\r\n')
    // Autosuficiente: el día de creación (Lima) decide su periodo y su columna de tiempo.
    expect(lista[0]).toBe('\uFEFF"Código de cita","Creada","Fecha","Hora","Persona","Analista","Supervisor","Estado","Moneda","Monto","Monto S/","Origen"')
    expect(lista[1]).toBe('"a2","2026-10-03","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
  })

  it('las columnas de origen suman las citas en cada fila', () => {
    const columnas: FiltrosColumnas[] = [{}, { monedas: ['PEN'] }, { personas: { lead: [] } }]
    for (const filtro of columnas) {
      for (const f of calcularProyeccion(mesLleno().fuente, filtro).filas) {
        expect(f.referidos.length + f.clientes.length + f.leads.length).toBe(f.citas.length)
      }
    }
  })
})

describe('Proyección de citas: columnas de tiempo', () => {
  const HOY_LIMA = '2026-10-19'
  const vista = (tramos: ReturnType<typeof tramosDelRango>) => tramos.map(t => `${t.titulo}|${t.detalle}|${t.desde}/${t.hasta}|${t.rotulo}`)

  it('semanas de un mes: las cuatro comerciales recortadas al rango', () => {
    expect(vista(tramosDelRango({ desde: '2026-10-03', hasta: '2026-10-19' }, 'semanas', HOY_LIMA))).toEqual([
      'S1|3–7|2026-10-03/2026-10-07|S1 3–7 oct', 'S2|8–14|2026-10-08/2026-10-14|S2 8–14 oct', 'S3|15–19|2026-10-15/2026-10-19|S3 15–19 oct',
    ])
    // Mes entero: la cuarta llega al último día; la que aún no empieza queda como futura.
    const octubre = tramosDelRango(OCTUBRE, 'semanas', HOY_LIMA)
    expect(vista(octubre).at(-1)).toBe('S4|22–31|2026-10-22/2026-10-31|S4 22–31 oct')
    expect(octubre.map(t => t.futuro)).toEqual([false, false, false, true])
    // Un tramo de un solo día se rotula con ese día.
    expect(vista(tramosDelRango({ desde: '2026-10-07', hasta: '2026-10-08' }, 'semanas', HOY_LIMA))).toEqual([
      'S1|7|2026-10-07/2026-10-07|S1 7 oct', 'S2|8|2026-10-08/2026-10-08|S2 8 oct',
    ])
    expect(tramosDelRango(OCTUBRE, 'mes', HOY_LIMA)).toEqual([])
  })

  it('semanas de un rango que cruza meses (y años): el detalle lleva el mes', () => {
    expect(vista(tramosDelRango({ desde: '2026-09-25', hasta: '2026-10-05' }, 'semanas', HOY_LIMA))).toEqual([
      'S4|25–30 set|2026-09-25/2026-09-30|S4 25–30 set', 'S1|1–5 oct|2026-10-01/2026-10-05|S1 1–5 oct',
    ])
    const anio = tramosDelRango({ desde: '2025-12-28', hasta: '2026-01-03' }, 'semanas', HOY_LIMA)
    expect(vista(anio)).toEqual(['S4|28–31 dic|2025-12-28/2025-12-31|S4 28–31 dic', 'S1|1–3 ene|2026-01-01/2026-01-03|S1 1–3 ene'])
    expect(new Set(anio.map(t => t.id)).size).toBe(2)
  })

  it('días: número y día corto; el mes en la primera columna y en el día 1; domingo, hoy y futuros marcados', () => {
    const dias = tramosDelRango({ desde: '2026-10-17', hasta: '2026-10-21' }, 'dias', HOY_LIMA)
    expect(dias.map(t => [t.titulo, t.detalle, t.rotulo, t.nombre])).toEqual([
      ['17 oct', 'sáb', '17 oct', 'sáb 17 oct'], ['18', 'dom', '18 oct', 'dom 18 oct'], ['19', 'lun', '19 oct', 'lun 19 oct'],
      ['20', 'mar', '20 oct', 'mar 20 oct'], ['21', 'mié', '21 oct', 'mié 21 oct'],
    ])
    expect(dias.map(t => [t.domingo, t.hoy, t.futuro])).toEqual([
      [false, false, false], [true, false, false], [false, true, false], [false, false, true], [false, false, true],
    ])
    expect(tramosDelRango({ desde: '2026-10-30', hasta: '2026-11-02' }, 'dias', HOY_LIMA).map(t => `${t.titulo} ${t.detalle}`)).toEqual([
      '30 oct vie', '31 sáb', '1 nov dom', '2 lun',
    ])
  })

  it('tope de 31 días: con más, «Días» cae a «Semanas»; un rango inválido no tiene columnas', () => {
    expect(diasPermitidos(OCTUBRE)).toBe(true)
    expect(tramosDelRango(OCTUBRE, 'dias', HOY_LIMA)).toHaveLength(31)
    const largo = { desde: '2026-10-01', hasta: '2026-11-01' }
    expect(diasPermitidos(largo)).toBe(false)
    expect(tiempoEfectivo('dias', largo)).toBe('semanas')
    expect(tiempoEfectivo('mes', largo)).toBe('mes')
    expect(tramosDelRango(largo, 'dias', HOY_LIMA).map(t => t.titulo)).toEqual(['S1', 'S2', 'S3', 'S4', 'S1'])
    expect(diasPermitidos({ desde: '2026-10-05', hasta: '2026-10-01' })).toBe(false)
    expect(tramosDelRango({ desde: '2026-10-05', hasta: '2026-10-01' }, 'semanas', HOY_LIMA)).toEqual([])
  })

  it('cada fila reparte sus citas por día de creación y la suma de sus tramos es su columna Citas', () => {
    const { fuente } = mesLleno()
    const semanas = calcularProyeccion({ ...fuente, tiempo: 'semanas' })
    const conteo = (m: { porTramo: unknown[][] }) => m.porTramo.map(l => l.length)
    expect(conteo(fila(semanas, 'ana')!)).toEqual([3, 1, 0, 0])
    expect(conteo(fila(semanas, 'diego')!)).toEqual([0, 1, 1, 0])
    expect(conteo(semanas.total)).toEqual([3, 2, 2, 0])
    expect(ids(fila(semanas, 'diego')!.porTramo[2]!)).toEqual(['d2'])
    const dias = calcularProyeccion({ ...fuente, tiempo: 'dias' })
    expect(dias.tramos).toHaveLength(31)
    expect(ids(fila(dias, 'ana')!.porTramo[1]!)).toEqual(['a1'])
    // Con cualquier vista, rango y embudo: suma de tramos = citas, por fila y en el total.
    for (const tiempo of ['semanas', 'dias'] as const) {
      for (const rango of [OCTUBRE, { desde: '2026-09-25', hasta: '2026-10-05' }, { desde: '2026-10-03', hasta: '2026-10-19' }]) {
        for (const columnas of [{}, { monedas: ['PEN'] }, { personas: { lead: [] } }] as FiltrosColumnas[]) {
          const hoja = calcularProyeccion({ ...fuente, tiempo, rango }, columnas)
          for (const m of [...hoja.filas, hoja.total]) expect(conteo(m).reduce((n, x) => n + x, 0)).toBe(m.citas.length)
        }
      }
    }
    // Sin columnas de tiempo no se reparte nada; fuera de todo tramo, una cita no se cuenta.
    expect(fila(calcularProyeccion(fuente), 'ana')!.porTramo).toEqual([])
    expect(repartirEnTramos(fila(semanas, 'ana')!.citas, [{ desde: '2026-10-02', hasta: '2026-10-02' }]).map(l => l.length)).toEqual([1])
  })

  it('el CSV en Semanas o Días añade una columna por tramo después de «Analista»', () => {
    const lineas = csvProyeccion(calcularProyeccion({ ...mesLleno().fuente, tiempo: 'semanas' }), 'Octubre 2026').split('\r\n')
    expect(lineas[0]).toBe('\uFEFF"Periodo","Equipo","Analista","S1 1–7 oct","S2 8–14 oct","S3 15–21 oct","S4 22–31 oct","Citas","Monto S/","Ticket cita S/","% Entrev.","% Conv.","Proyectado citas S/","Referidos","Clientes","Leads"')
    expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","3","1","0","0","4","37500","9375","66.7","50","20394.74","1","0","3"')
    expect(lineas.at(-1)).toMatch(/^"Octubre 2026","","Total · 3 analistas","3","2","2","0","7",/)
    const dias = csvProyeccion(calcularProyeccion({ ...mesLleno().fuente, tiempo: 'dias', rango: { desde: '2026-10-17', hasta: '2026-10-19' } }), 'x').split('\r\n')
    expect(dias[0]).toContain('"Analista","sáb 17 oct","dom 18 oct","lun 19 oct","Citas"')
  })
})

describe('Proyección de citas: % Entrev. y % Conv. con las reglas de Resultados', () => {
  const sinVentas = (citas: CitaEjemplo[]) => calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones: [] })

  it('% Entrev. = realizadas ÷ (realizadas + no asistió): programadas, futuras, vencidas y canceladas no son base', () => {
    const citas = [
      cita('e1', 'ana', { estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z' }),
      cita('e2', 'ana', { estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z' }),
      cita('e3', 'ana', { estado: 'no_show' }),
      cita('e4', 'ana', { fecha: '2026-10-28' }),
      cita('e5', 'ana', { fecha: '2026-11-04' }),
      cita('e6', 'ana', { estado: 'vencida' }),
      cita('e7', 'ana', { estado: 'cancelada' }),
    ]
    const ana = sinVentas(citas).filas[0]!
    // Antes: 2 ÷ 7 = 28,6 % (las futuras contaban como no asistidas). Ahora: 2 ÷ 3.
    expect(ids(ana.resueltas)).toEqual(['e1', 'e2', 'e3'])
    expect(ids(ana.entrevistas)).toEqual(['e1', 'e2'])
    expect(ana.pctEntrevistas).toBeCloseTo(200 / 3, 10)
    // Todas resueltas sin asistencia: 0 % con base; ninguna resuelta: sin base, nunca 0 %.
    expect(sinVentas(citas.filter(c => c.id === 'e3')).filas[0]!.pctEntrevistas).toBe(0)
    expect(sinVentas(citas.filter(c => !['e1', 'e2', 'e3'].includes(c.id))).filas[0]!.pctEntrevistas).toBeNull()
  })

  it('% Conv. vincula como Resultados: venta con fecha comercial el día de la entrevista o después, hasta el corte y sin recortarla al mes', () => {
    const realizada = (id: string) => cita(id, 'ana', { leadId: `lead-${id}`, estado: 'realizada', asistioEn: '2026-10-06T20:00:00Z', creadoEn: '2026-10-02T15:00:00Z' })
    const venta = (lead: string, convertidoEn: string, fechaComercial: string | null): ConversionProyeccion =>
      ({ lead_id: lead, perfil_id: `perfil-${lead}`, convertido_en: convertidoEn, fecha_comercial: fechaComercial, analista_id: 'ana' })
    const citas = ['v1', 'v2', 'v3', 'v4', 'v5', 'v6'].map(realizada)
    const conversiones = [
      // Mismo día de Lima aunque se registró antes de la hora de la entrevista: la fecha comercial no ordena dentro del día.
      venta('lead-v1', '2026-10-06T14:00:00Z', '2026-10-06'),
      // Registrada después, pero con la venta ANTERIOR al día de la entrevista: la regla vieja la contaba.
      venta('lead-v2', '2026-10-09T15:00:00Z', '2026-10-05'),
      // Sin hecho comercial (renovación, fuente retirada): la regla vieja también la contaba.
      venta('lead-v3', '2026-10-09T15:00:00Z', null),
      // Venta del mes siguiente: la Proyección sigue su cohorte hasta el corte.
      venta('lead-v4', '2026-11-10T15:00:00Z', '2026-11-10'),
      // Venta posterior al corte: aún no existe para la consulta.
      venta('lead-v5', '2026-11-25T15:00:00Z', '2026-11-25'),
    ]
    const hoja = calcularProyeccion({ citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: '2026-11-20T17:00:00Z', tipoCambio: TC, conversiones })
    const ana = hoja.filas[0]!
    expect(ids(ana.convertidas)).toEqual(['v1', 'v4'])
    expect(ana).toMatchObject({ personasEntrevistadas: 6, personasClientes: 2 })
    expect(ana.pctConversion).toBeCloseTo(100 / 3, 10)
    // Una realizada sin hora de asistencia no se vincula a ninguna venta.
    const sinHora = cita('v1', 'ana', { leadId: 'lead-v1', estado: 'realizada', creadoEn: '2026-10-02T15:00:00Z' })
    const sinAsistencia = calcularProyeccion({ citas: [sinHora], filtros: defaults('2026-10'), rango: OCTUBRE,
      corte: HOY, tipoCambio: TC, conversiones: [venta('lead-v1', '2026-10-06T14:00:00Z', '2026-10-06')] })
    expect(sinAsistencia.filas[0]).toMatchObject({ personasEntrevistadas: 1, personasClientes: 0, pctConversion: 0 })
  })
})

// Fase 0b (decisión de Miguel, 19/10/2026): las reuniones con CLIENTES sin lead son
// citas de origen Cliente. Cuentan en Citas, Clientes, columnas de tiempo y % Entrev.;
// Monto, Ticket cita, % Conv. y Proyectado siguen siendo los de las citas con lead.
describe('Proyección de citas: reuniones con clientes sin lead', () => {
  function reunion(id: string, analista: keyof typeof EQUIPOS, cambios: Partial<ReunionClienteProyeccion>): ReunionClienteProyeccion {
    const [analistaNombre, supervisorId, supervisor] = EQUIPOS[analista]
    return { id, leadId: null, moneda: null, monto: null, persona: `persona:${id}`, nombre: `CLIENTE ${id.toUpperCase()}`, analista, analistaNombre,
      supervisor, supervisorId, fecha: '2026-10-12', hora: '11:00', estado: 'programada', creadoEn: '2026-10-08T15:00:00Z', ...cambios }
  }
  /** Ana: 3 citas con lead (2 entrevistas, 1 no asistió, una venta) y 2 reuniones con clientes (1 entrevista, 1 no asistió). */
  function ejemplo(reuniones = true) {
    const citas = [
      cita('a1', 'ana', { leadId: 'lead-1', estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z', monto: 10_000, creadoEn: '2026-10-02T15:00:00Z' }),
      cita('a2', 'ana', { leadId: 'lead-2', estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z', monto: 20_000, creadoEn: '2026-10-03T15:00:00Z' }),
      cita('a3', 'ana', { leadId: 'lead-3', estado: 'no_show', monto: 30_000, creadoEn: '2026-10-04T15:00:00Z' }),
    ]
    const reunionesClientes = reuniones ? [
      reunion('r1', 'ana', { estado: 'realizada', asistioEn: '2026-10-09T16:00:00Z', creadoEn: '2026-10-08T15:00:00Z' }),
      reunion('r2', 'ana', { estado: 'no_show', persona: 'oculta:r2', nombre: 'Cliente fuera de tu cartera', creadoEn: '2026-10-11T15:00:00Z' }),
    ] : []
    const conversiones: ConversionProyeccion[] = [{ lead_id: 'lead-1', perfil_id: 'perfil-1', convertido_en: '2026-10-08T15:00:00Z', fecha_comercial: '2026-10-08', analista_id: 'ana', supervisor_id: 'sup-1' }]
    return { citas, reunionesClientes, filtros: { equipo: '' }, rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones } satisfies FuenteProyeccion
  }

  it('ejemplo: 3 citas con lead + 2 reuniones con clientes → 5 citas y 60 % Entrev.; Monto, Ticket, % Conv. y Proyectado de las 3 con lead', () => {
    const ana = fila(calcularProyeccion(ejemplo()), 'ana')!
    expect(ids(ana.citas)).toEqual(['a1', 'a2', 'a3', 'r1', 'r2'])
    expect(ids(ana.citasConLead)).toEqual(['a1', 'a2', 'a3'])
    expect([ana.referidos.length, ana.clientes.length, ana.leads.length]).toEqual([0, 2, 3])
    // Monto 60 000 entre las 3 citas con lead (no entre 5): Ticket cita 20 000.
    expect(ana).toMatchObject({ montoPen: 60_000, monto: 60_000, ticket: 20_000, personasEntrevistadas: 2, personasClientes: 1, pctConversion: 50 })
    expect(ids(ana.conMonto)).toEqual(['a1', 'a2', 'a3'])
    // % Entrev. de la hoja: (2 + 1) entrevistas ÷ (3 + 2) resueltas. El que proyecta: 2 ÷ 3.
    expect(ids(ana.entrevistas)).toEqual(['a1', 'a2', 'r1'])
    expect(ids(ana.resueltas)).toEqual(['a1', 'a2', 'a3', 'r1', 'r2'])
    expect(ana.pctEntrevistas).toBeCloseTo(60, 10)
    expect(ana.pctEntrevistasConLead).toBeCloseTo(200 / 3, 10)
    expect(ids(ana.convertidas)).toEqual(['a1'])
    // Ritmo de las 3 con lead: 3 en 19 de 31 días → 93/19 × 2/3 × 50 % × S/ 20 000 = S/ 32 631,58.
    expect(ana.citasEsperadas).toBeCloseTo(93 / 19, 10)
    expect(ana.proyectado).toBeCloseTo(93 / 19 * (2 / 3) * 0.5 * 20_000, 6)
    expect(Math.round(ana.proyectado! * 100) / 100).toBe(32_631.58)
    // Sin las reuniones, lo único que cambia es Citas, Clientes y % Entrev.
    const sin = fila(calcularProyeccion(ejemplo(false)), 'ana')!
    expect(sin).toMatchObject({ monto: ana.monto, ticket: ana.ticket, pctConversion: ana.pctConversion, proyectado: ana.proyectado, citasEsperadas: ana.citasEsperadas })
    expect([sin.citas.length, sin.clientes.length, sin.pctEntrevistas]).toEqual([3, 0, ana.pctEntrevistasConLead])
  })

  it('un analista con solo reuniones con clientes tiene fila, sin monto, ticket, conversión ni proyectado; el total no cambia su proyectado', () => {
    const fuente: FuenteProyeccion = { ...mesLleno().fuente, reunionesClientes: [reunion('m2', 'mateo', { estado: 'realizada', asistioEn: '2026-10-09T16:00:00Z' })] }
    const con = calcularProyeccion(fuente)
    const mateo = fila(con, 'mateo')!
    expect(mateo).toMatchObject({ ticket: null, pctEntrevistas: 100, pctEntrevistasConLead: null, pctConversion: null, citasEsperadas: null, proyectado: null })
    expect([mateo.citas.length, mateo.clientes.length, mateo.conMonto.length, mateo.citasConLead.length]).toEqual([1, 1, 0, 0])
    const sin = calcularProyeccion(mesLleno().fuente)
    expect(con.total).toMatchObject({ proyectado: sin.total.proyectado, monto: sin.total.monto, ticket: sin.total.ticket, pctConversion: sin.total.pctConversion })
    expect(con.total.citas.length).toBe(sin.total.citas.length + 1)
  })

  it('el Supervisor, el embudo de Analista y el de Clientes las recortan como a las demás; un filtro de moneda las deja fuera', () => {
    const fuente: FuenteProyeccion = { ...mesLleno().fuente, reunionesClientes: [
      reunion('r1', 'ana', {}), reunion('r2', 'ana', { persona: 'persona:r1' }), reunion('r3', 'diego', { persona: 'oculta:r3', nombre: 'Cliente fuera de tu cartera' }),
      reunion('r4', 'luis', { creadoEn: '2026-09-30T15:00:00Z' }), // creada fuera del rango: no entra
    ] }
    const hoja = calcularProyeccion(fuente)
    expect(ids(hoja.cohorte.filter(c => c.cita.leadId === null))).toEqual(['r1', 'r2', 'r3'])
    expect(ids(fila(calcularProyeccion(con(fuente, { equipo: 'sup-2' })), 'diego')!.clientes)).toEqual(['d1', 'r3'])
    expect(calcularProyeccion(con(fuente, { equipo: 'sup-2' })).cohorte.some(c => c.cita.id === 'r1')).toBe(false)
    expect(opcionesAnalistas(hoja, {}).map(o => [o.id, o.citas])).toEqual([['ana', 6], ['diego', 3], ['luis', 1]])
    // Embudo de Clientes: por persona (las dos reuniones de r1 juntas); la redactada con el texto del servidor.
    expect(opcionesPersonas(hoja, {}, 'cliente').map(o => [o.id, o.nombre, o.citas])).toEqual([
      ['oculta:r3', 'Cliente fuera de tu cartera', 1], ['persona:r1', 'CLIENTE R1', 2], ['lead:lead-5', 'Persona d1', 1],
    ])
    const soloR1 = calcularProyeccion(fuente, { personas: { cliente: ['persona:r1'] } })
    expect(ids(soloR1.total.clientes)).toEqual(['r1', 'r2'])
    expect(soloR1.total.leads.length).toBe(hoja.total.leads.length)
    // Sin moneda: un filtro de moneda las deja fuera, y no cuentan en las monedas del embudo.
    expect(calcularProyeccion(fuente, { monedas: ['PEN'] }).cohorte.some(c => c.cita.leadId === null)).toBe(true)
    expect(calcularProyeccion(fuente, { monedas: ['PEN'] }).total.citas.some(c => c.cita.leadId === null)).toBe(false)
    expect(opcionesMonedas(hoja, {})).toEqual(opcionesMonedas(calcularProyeccion(mesLleno().fuente), {}))
  })

  it('una clave de persona igual a la de un lead no las empareja: la venta del lead no cierra la reunión', () => {
    const base = ejemplo(false)
    const poblacion: PersonaProyeccion[] = [{ lead_id: 'lead-1', identidad_persona: 'persona:p1' }]
    const misma = reunion('r1', 'ana', { persona: 'persona:p1', estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z' })
    const con = fila(calcularProyeccion({ ...base, poblacion, reunionesClientes: [misma] }), 'ana')!
    const sin = fila(calcularProyeccion({ ...base, poblacion }), 'ana')!
    expect(ids(con.convertidas)).toEqual(['a1'])
    expect([con.personasEntrevistadas, con.personasClientes, con.pctConversion, con.proyectado]).toEqual([sin.personasEntrevistadas, sin.personasClientes, sin.pctConversion, sin.proyectado])
  })

  it('columnas de tiempo por su día de creación; la lista y su CSV llevan la fila sin monto ni moneda y con origen Cliente', () => {
    const hoja = calcularProyeccion({ ...ejemplo(), tiempo: 'semanas' })
    const ana = fila(hoja, 'ana')!
    // S1 1–7: a1 a2 a3 · S2 8–14: r1 r2 · S3 · S4.
    expect(ana.porTramo.map(ids)).toEqual([['a1', 'a2', 'a3'], ['r1', 'r2'], [], []])
    const csv = csvCitasProyeccion(ana.clientes).split('\r\n')
    expect(csv[1]).toBe('"r1","2026-10-08","2026-10-12","11:00","CLIENTE R1","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
    expect(csv[2]).toBe('"r2","2026-10-11","2026-10-12","11:00","Cliente fuera de tu cartera","Ana Torres","Claudia Ríos","No asistió","","","","Cliente"')
    const hojaCsv = csvProyeccion(calcularProyeccion(ejemplo()), 'Octubre').split('\r\n')
    // Citas 5 · Monto 60 000 · Ticket 20 000 · % Entrev. 60 · % Conv. 50 · Proyectado · Referidos 0 · Clientes 2 · Leads 3.
    expect(hojaCsv[1]).toBe('"Octubre","Claudia Ríos","Ana Torres","5","60000","20000","60","50","32631.58","0","2","3"')
  })
})
