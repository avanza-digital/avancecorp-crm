// «Toda la operación» (27/09/2026) contra la respuesta SQL sintética real de F5:
// cifras autoritativas del pulso, atención por analistas distintos, «fuera»
// siempre al final y barras que dicen qué llamadas no dibujan.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import fixture from './gestion-diaria-f5.test.fixture.json'
import { PulsoGerenciaSchema } from './gestion-diaria-pulso'
import { DiaEquipoSchema, presentarEquipo } from './gestion-diaria-equipo'
import {
  atencionEquipo, barrasEquipo, filasOperacion, filtrarOrdenarOperacion, nivelEquipo, personasSinRegistro, totalOperacion,
  type FiltrosOperacion, type OrdenOperacion,
} from './gestion-diaria-operacion'

const pulso = v.parse(PulsoGerenciaSchema, fixture.pulso)
const detalle = presentarEquipo(v.parse(DiaEquipoSchema, fixture.equipo))
const equipo = (nombre: string) => pulso.equipos.find((e) => e.nombre === nombre)!
const BASE: FiltrosOperacion = { busqueda: '', estado: 'todos', orden: 'atencion', ascendente: false }

describe('filasOperacion', () => {
  it('una fila por equipo con las cifras autoritativas del pulso, «fuera» incluido', () => {
    const filas = filasOperacion(pulso, null)
    expect(filas).toHaveLength(pulso.equipos.length)
    expect(filas.reduce((n, f) => n + f.llamadas, 0)).toBe(pulso.actual.llamadas)
    expect(filas.reduce((n, f) => n + f.sinRegistro, 0)).toBe(pulso.actual.sin_actividad)
    expect(filas.find((f) => f.fuera)?.nombre).toBe('Fuera de equipos comerciales')
    // Sin detalle todavía: atención desconocida, nunca un cero inventado.
    expect(filas.every((f) => f.atencion === null)).toBe(true)
  })
  it('atención = analistas ACTIVOS distintos del equipo que la necesitan', () => {
    const filas = filasOperacion(pulso, detalle)
    expect(filas.find((f) => f.nombre === 'SUPERVISOR DOS')?.atencion).toBe(1)
    // En «fuera» solo cuenta ANALISTA DOS: los autores inactivos y sin autor no son analistas del equipo.
    expect(filas.find((f) => f.fuera)?.atencion).toBe(1)
  })
})

describe('filtrarOrdenarOperacion', () => {
  it('«fuera» queda al final en cualquier orden y sentido', () => {
    const filas = filasOperacion(pulso, detalle)
    for (const orden of ['nombre', 'llamadas', 'contacto', 'citas', 'vencidas', 'atencion', 'primer_intento', 'dispersion'] as OrdenOperacion[]) {
      for (const ascendente of [true, false]) expect(filtrarOrdenarOperacion(filas, { ...BASE, orden, ascendente }).at(-1)?.fuera).toBe(true)
    }
  })
  it('sin dato al final, búsqueda sin tildes y las pastillas «Con atención» y «Con vencidas»', () => {
    const filas = filasOperacion(pulso, detalle)
    const porContacto = filtrarOrdenarOperacion(filas, { ...BASE, orden: 'contacto', ascendente: true }).filter((f) => !f.fuera)
    const primeroSinDato = porContacto.findIndex((f) => f.tasaContacto === null)
    if (primeroSinDato >= 0) expect(porContacto.slice(primeroSinDato).every((f) => f.tasaContacto === null)).toBe(true)
    expect(filtrarOrdenarOperacion(filas, { ...BASE, busqueda: 'anidádo' }).map((f) => f.nombre)).toEqual(['SUPERVISOR ANIDADO'])
    expect(filtrarOrdenarOperacion(filas, { ...BASE, estado: 'atencion' }).every((f) => (f.atencion ?? 0) > 0)).toBe(true)
    const conVencidas = filtrarOrdenarOperacion(filas, { ...BASE, estado: 'vencidas' })
    expect(conVencidas.length).toBe(filas.filter((f) => f.vencidas > 0).length)
    expect(conVencidas.every((f) => f.vencidas > 0)).toBe(true)
  })
})

describe('personasSinRegistro', () => {
  it('son los activos con cero gestiones: la misma cuenta que «Sin registro»', () => {
    const lista = personasSinRegistro(pulso)
    expect(lista).toHaveLength(pulso.actual.sin_actividad)
    expect(lista.map((p) => p.nombre).toSorted()).toEqual(['ANALISTA ANIDADO', 'ANALISTA CUATRO'])
  })
})

describe('atencionEquipo y barrasEquipo', () => {
  it('atención solo del equipo, el más grave primero', () => {
    expect(atencionEquipo(detalle, equipo('SUPERVISOR DOS')).map((f) => f.nombre_completo)).toEqual(['ANALISTA TRES'])
  })
  it('las barras suman a los activos y dicen cuántas llamadas son de otros autores', () => {
    const fuera = barrasEquipo(detalle, equipo('Fuera de equipos comerciales'))!
    expect(fuera.analistas).toBe(1)
    // Los otros autores salen del pulso: inactivos y sin autor de «fuera».
    expect(fuera.otros).toBe(equipo('Fuera de equipos comerciales').personas.filter((p) => !p.activo || p.analista_id === null).reduce((n, p) => n + p.llamadas, 0))
    const dos = barrasEquipo(detalle, equipo('SUPERVISOR DOS'))!
    const esperado = detalle.filter((f) => ['ANALISTA TRES', 'ANALISTA CUATRO'].includes(f.nombre_completo)).reduce((n, f) => n + f.marcador.llamadas, 0)
    expect(dos.porHora.reduce((n, h) => n + h.llamadas, 0)).toBe(esperado)
    expect(dos.otros).toBe(0)
  })
  it('si falta un activo en el detalle, no se dibuja', () => {
    expect(barrasEquipo(detalle.filter((f) => f.nombre_completo !== 'ANALISTA CUATRO'), equipo('SUPERVISOR DOS'))).toBeNull()
  })
})

describe('totalOperacion', () => {
  it('«Toda la operación» suma lo mismo que el pulso y la atención de los equipos', () => {
    const filas = filasOperacion(pulso, detalle)
    const total = totalOperacion(pulso, filas)
    expect(total).toMatchObject({ clave: 'total', llamadas: pulso.actual.llamadas, utiles: pulso.actual.utiles, tasaContacto: pulso.actual.tasa_contacto,
      citas: pulso.actual.citas_agendadas, vencidas: pulso.vencidas_global, analistas: pulso.actual.analistas_activos, sinRegistro: pulso.actual.sin_actividad })
    expect(total.atencion).toBe(filas.reduce((n, f) => n + (f.atencion ?? 0), 0))
    const conMuestra = pulso.equipos.filter((e) => e.dispersion.personas > 0)
    if (conMuestra.length) expect(total.dispersion.minimo).toBe(Math.min(...conMuestra.map((e) => e.dispersion.minimo!)))
    // Sin detalle, la atención de la operación es desconocida, no cero.
    expect(totalOperacion(pulso, filasOperacion(pulso, null)).atencion).toBeNull()
  })
})

describe('nivelEquipo', () => {
  const umbrales = { version: 1 as const, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 }
  it('usa los umbrales del servidor y dice «sin muestra» por debajo del mínimo de útiles', () => {
    expect(nivelEquipo({ tasaContacto: 50, utiles: 10 }, umbrales)).toEqual({ estado: 'evaluado', nivel: 'bien' })
    expect(nivelEquipo({ tasaContacto: 30, utiles: 10 }, umbrales)).toEqual({ estado: 'evaluado', nivel: 'atencion' })
    expect(nivelEquipo({ tasaContacto: 10, utiles: 10 }, umbrales)).toEqual({ estado: 'evaluado', nivel: 'bajo' })
    expect(nivelEquipo({ tasaContacto: 80, utiles: 4 }, umbrales)).toEqual({ estado: 'sin_muestra', utiles: 4, minimo: 5 })
    expect(nivelEquipo({ tasaContacto: null, utiles: 0 }, umbrales)).toEqual({ estado: 'sin_dato' })
    expect(nivelEquipo({ tasaContacto: 50, utiles: 10 }, null)).toEqual({ estado: 'sin_dato' })
  })
})

