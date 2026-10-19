import { describe, expect, it } from 'vitest'
import { defaults, type CitaEjemplo, type FiltrosCitas } from './modelo'
import {
  calcularProyeccion, csvCitasProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas, opcionesPersonas,
  periodoProyeccion, type ConversionProyeccion, type FiltrosColumnas, type FuenteProyeccion, type PersonaProyeccion,
} from './proyeccion'
import { atajosRango, errorRango, mesesDelRango, rangoInicial, rotuloRango, type RangoProyeccion } from './proyeccion-rango'

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
    // Cliente DESPUÉS de su entrevista (a1): cuenta en la conversión de Ana.
    { lead_id: 'lead-1', perfil_id: 'perfil-1', convertido_en: '2026-10-08T15:00:00Z' },
    // Ya era cliente cuando Diego le creó la cita (d1): va a Clientes y no convierte.
    { lead_id: 'lead-5', perfil_id: 'perfil-5', convertido_en: '2026-10-01T15:00:00Z' },
  ]
  const fuente: FuenteProyeccion = { citas, filtros: defaults('2026-10'), rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones }
  return { citas, conversiones, fuente }
}
const fila = (hoja: ReturnType<typeof calcularProyeccion>, id: string) => hoja.filas.find(f => f.id === id)
const ids = (lista: { cita: CitaEjemplo }[]) => lista.map(c => c.cita.id).sort()
const con = (fuente: FuenteProyeccion, filtros: Partial<FiltrosCitas>): FuenteProyeccion => ({ ...fuente, filtros: { ...fuente.filtros, ...filtros } })
const en = (fuente: FuenteProyeccion, desde: string, hasta: string): FuenteProyeccion => ({ ...fuente, rango: { desde, hasta } })

describe('Proyección de citas: cohorte y columnas', () => {
  it('mes lleno: agrupa por equipo, ordena por citas y calcula cada columna con su regla', () => {
    const hoja = calcularProyeccion(mesLleno().fuente)
    expect(hoja.bandas.map(b => [b.nombre, b.filas.map(f => f.id), b.citas])).toEqual([
      ['Claudia Ríos', ['ana', 'luis'], 5], ['Javier Vega', ['diego'], 2],
    ])
    const ana = fila(hoja, 'ana')!
    expect(ana.citas).toHaveLength(4)
    // 30 000 PEN + 2 000 USD × 3,75; la cita sin monto no suma pero sí divide el ticket.
    expect(ana).toMatchObject({ montoPen: 30_000, montoUsd: 2_000, monto: 37_500, ticket: 9_375, pctEntrevistas: 50, pctConversion: 50, pendienteTc: false })
    expect(ids(ana.conMonto)).toEqual(['a1', 'a2', 'a3'])
    expect(ids(ana.convertidas)).toEqual(['a1'])
    // Ritmo: 4 citas en 19 de 31 días → 124/19 citas esperadas × 50 % × 50 % × S/ 9 375.
    expect(ana.citasEsperadas).toBeCloseTo(124 / 19, 10)
    expect(ana.proyectado).toBeCloseTo(124 / 19 * 0.5 * 0.5 * 9_375, 6)
    expect([ana.referidos.length, ana.clientes.length, ana.leads.length]).toEqual([1, 0, 3])
    const diego = fila(hoja, 'diego')!
    expect(diego).toMatchObject({ monto: 80_000, ticket: 40_000, pctEntrevistas: 50, pctConversion: 0, proyectado: 0 })
    expect([ids(diego.referidos), ids(diego.clientes), ids(diego.leads)]).toEqual([['d2'], ['d1'], []])
    // Sin entrevistas no hay base para proyectar.
    expect(fila(hoja, 'luis')).toMatchObject({ pctEntrevistas: 0, pctConversion: null, proyectado: null, ticket: 5_000 })
  })

  it('el total recalcula sobre todas las citas, suma proyectados con base y nunca promedia tasas ni tickets', () => {
    const { total, filas } = calcularProyeccion(mesLleno().fuente)
    expect(total.citas).toHaveLength(7)
    expect(total).toMatchObject({ monto: 122_500, ticket: 17_500, personasEntrevistadas: 3, personasClientes: 1 })
    expect(total.pctEntrevistas).toBeCloseTo(300 / 7, 10)
    expect(total.pctConversion).toBeCloseTo(100 / 3, 10)
    expect(total.proyectado).toBeCloseTo(filas.reduce((n, f) => n + (f.proyectado ?? 0), 0), 6)
    expect(total.referidos.length + total.clientes.length + total.leads.length).toBe(total.citas.length)
  })

  it('mes vacío (estado de producción hoy): sin filas, total en cero y tasas sin base', () => {
    const hoja = calcularProyeccion({ citas: [], filtros: defaults('2026-10'), rango: rangoInicial('2026-10', '2026-10-19'), corte: HOY, tipoCambio: null, conversiones: [] })
    expect(hoja.filas).toEqual([])
    expect(hoja.bandas).toEqual([])
    expect(hoja.requiereTc).toBe(false)
    expect(hoja.total).toMatchObject({ monto: 0, ticket: null, pctEntrevistas: null, pctConversion: null, proyectado: null, pendienteTc: false })
    expect(hoja.total.citas).toEqual([])
    expect(csvProyeccion(hoja, 'Octubre 2026').split('\r\n')).toEqual([
      '﻿"Periodo","Equipo","Analista","Citas","Monto S/","Ticket S/","% Entrev.","% Conv.","Proyectado S/","Referidos","Clientes","Leads"',
      '"Octubre 2026","","Total · 0 analistas","0","0","","","","","0","0","0"',
    ])
  })

  it('sin tipo de cambio, el monto con dólares queda pendiente y el ticket y el proyectado sin base', () => {
    const hoja = calcularProyeccion({ ...mesLleno().fuente, tipoCambio: null })
    expect(hoja.requiereTc).toBe(true)
    expect(fila(hoja, 'ana')).toMatchObject({ pendienteTc: true, monto: null, ticket: null, proyectado: null, pctEntrevistas: 50 })
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
    expect(fila(hoja, 'ana')).toMatchObject({ citasEsperadas: 4, proyectado: 4 * 0.5 * 0.5 * 9_375 })
  })

  it('la cohorte es por fecha de creación: el analista cuya cita se creó en otro mes no tiene fila', () => {
    const { fuente } = mesLleno()
    expect(fila(calcularProyeccion(fuente), 'mateo')).toBeUndefined()
    expect(calcularProyeccion(con(fuente, { analista: 'mateo' })).filas).toEqual([])
    // Semana y día de arriba no aplican: manda el rango.
    expect(calcularProyeccion(con(fuente, { semana: '1', dia: '2026-10-02' })).total.citas).toHaveLength(7)
    // Equipo y búsqueda de la consulta.
    expect(calcularProyeccion(con(fuente, { equipo: 'sup-2' })).filas.map(f => f.id)).toEqual(['diego'])
    expect(calcularProyeccion(con(fuente, { q: 'persona d2' })).total.citas.map(c => c.cita.id)).toEqual(['d2'])
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
    expect(hoja.bandas.map(b => b.nombre)).toEqual(['Claudia Ríos', 'Javier Vega'])
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
    expect(vacio.bandas.map(b => b.nombre)).toEqual(['Claudia Ríos'])
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
    expect(calcularProyeccion(fuente, { analistas: ['luis', 'diego'] }).filas.map(f => f.id)).toEqual(['luis', 'diego'])
    expect(calcularProyeccion(fuente, { rangos: { citas: { min: 2 } } }).filas.map(f => f.id)).toEqual(['ana', 'diego'])
    // Una fila sin base no cumple ningún rango.
    expect(calcularProyeccion(fuente, { rangos: { conversion: { max: 10 } } }).filas.map(f => f.id)).toEqual(['diego'])
    expect(calcularProyeccion(fuente, { rangos: { monto: { min: 10_000, max: 50_000 } } }).filas.map(f => f.id)).toEqual(['ana'])
    expect(calcularProyeccion(fuente, {}, { columna: 'analista', direccion: 'desc' }).bandas[0]!.filas.map(f => f.id)).toEqual(['luis', 'ana'])
    for (const direccion of ['asc', 'desc'] as const) {
      expect(calcularProyeccion(fuente, {}, { columna: 'proyectado', direccion }).bandas[0]!.filas.map(f => f.id)).toEqual(['ana', 'luis'])
    }
    expect(calcularProyeccion(fuente, {}, { columna: 'ticket', direccion: 'asc' }).bandas[0]!.filas.map(f => f.id)).toEqual(['luis', 'ana'])
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
    const conversiones = [{ lead_id: 'lead-y', perfil_id: 'perfil-y', convertido_en: '2026-10-10T15:00:00Z' }]
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
      conversiones: [{ lead_id: 'lead-r4', convertido_en: '2026-10-01T15:00:00Z' }] })
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

  it('el CSV de la hoja lleva el ticket y el total; el de la lista, el monto original y en soles', () => {
    const hoja = calcularProyeccion(mesLleno().fuente)
    const lineas = csvProyeccion(hoja, 'Octubre 2026').split('\r\n')
    expect(lineas[1]).toBe('"Octubre 2026","Claudia Ríos","Ana Torres","4","37500","9375","50","50","15296.05","1","0","3"')
    expect(lineas.at(-1)).toBe('"Octubre 2026","","Total · 3 analistas","7","122500","17500","42.9","33.3","15296.05","2","1","4"')
    const lista = csvCitasProyeccion(fila(hoja, 'ana')!.conMonto.filter(c => c.cita.id === 'a2'))
    expect(lista.split('\r\n')[1]).toBe('"a2","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
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
