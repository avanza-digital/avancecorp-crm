import { describe, expect, it } from 'vitest'
import {
  FILTROS_INICIALES,
  contarFiltrosAvanzados,
  contarMarcados,
  distritosDeCola,
  filtrarYOrdenarCola,
  origenesDeCola,
} from './cola-reparto'
import type { ColaLead } from './tipos'

function lead(parcial: Partial<ColaLead> & { id: string; creado_en: string }): ColaLead {
  return {
    nombre_completo: `LEAD ${parcial.id.toUpperCase()}`,
    distrito: null,
    origen: 'otro',
    categoria_interes: null,
    monto_estimado: 1000,
    moneda: 'PEN',
    clasificacion_auto: null,
    comentario: null,
    ...parcial,
  }
}

const VIEJO = lead({ id: 'viejo', creado_en: '2026-07-20T10:00:00.000Z', origen: 'landing' })
const MEDIO = lead({
  id: 'medio', creado_en: '2026-07-22T15:30:00.000Z', origen: 'formulario',
  categoria_interes: 'renovacion', monto_estimado: 15_000, moneda: 'USD',
  distrito: 'Miraflores', clasificacion_auto: 'posible_credito',
  comentario: 'Necesito un préstamo urgente',
})
const NUEVO = lead({
  id: 'nuevo', creado_en: '2026-07-24T09:15:00.000Z', origen: 'landing',
  categoria_interes: 'nuevo', monto_estimado: 50_000,
  distrito: 'San Juan de Lurigancho', comentario: 'Quiero invertir en el plazo fijo',
})
const COLA = [VIEJO, MEDIO, NUEVO] // llega en FIFO (asc), como la RPC

describe('filtrarYOrdenarCola', () => {
  it('default: más recientes primero (lo que pidió Miguel), sin mutar la entrada', () => {
    const filas = filtrarYOrdenarCola(COLA, FILTROS_INICIALES)
    expect(filas.map((l) => l.id)).toEqual(['nuevo', 'medio', 'viejo'])
    // La cola original sigue en FIFO: sort no muta (la usa el estado de React).
    expect(COLA.map((l) => l.id)).toEqual(['viejo', 'medio', 'nuevo'])
  })

  it('orden "antiguos" invierte: el que más esperó, arriba', () => {
    const filas = filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, orden: 'antiguos' })
    expect(filas.map((l) => l.id)).toEqual(['viejo', 'medio', 'nuevo'])
  })

  it('soloMarcados deja únicamente los posible_credito', () => {
    const filas = filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, soloMarcados: true })
    expect(filas.map((l) => l.id)).toEqual(['medio'])
  })

  it('filtra por origen exacto', () => {
    const filas = filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, origen: 'landing' })
    expect(filas.map((l) => l.id)).toEqual(['nuevo', 'viejo'])
  })

  it('la búsqueda matchea nombre, distrito y comentario, sin tildes', () => {
    expect(filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, busqueda: 'lead medio' })
      .map((l) => l.id)).toEqual(['medio'])
    expect(filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, busqueda: 'lurigancho' })
      .map((l) => l.id)).toEqual(['nuevo'])
    // "prestamo" sin tilde encuentra "préstamo" con tilde (y viceversa).
    expect(filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, busqueda: 'prestamo' })
      .map((l) => l.id)).toEqual(['medio'])
    expect(filtrarYOrdenarCola(COLA, { ...FILTROS_INICIALES, busqueda: 'PRÉSTAMO' })
      .map((l) => l.id)).toEqual(['medio'])
  })

  it('los filtros se COMPONEN (marca + búsqueda) y sin coincidencias devuelve vacío', () => {
    expect(filtrarYOrdenarCola(COLA, {
      ...FILTROS_INICIALES, soloMarcados: true, busqueda: 'invertir',
    })).toEqual([])
  })

  it('filtra por categoría, moneda, distrito y capital sin mezclar monedas', () => {
    expect(filtrarYOrdenarCola(COLA, {
      ...FILTROS_INICIALES,
      categoria: 'renovacion',
      moneda: 'USD',
      distrito: 'Miraflores',
      montoMin: '10000',
      montoMax: '20000',
    }).map((l) => l.id)).toEqual(['medio'])
  })

  it('filtra antigüedad con reloj inyectado y presencia de comentario', () => {
    const ahora = Date.parse('2026-07-24T12:00:00.000Z')
    expect(filtrarYOrdenarCola(COLA, {
      ...FILTROS_INICIALES,
      antiguedad: 'tres_mas',
      comentario: 'sin',
    }, ahora).map((l) => l.id)).toEqual(['viejo'])
    expect(filtrarYOrdenarCola(COLA, {
      ...FILTROS_INICIALES,
      antiguedad: 'hoy',
      comentario: 'con',
    }, ahora).map((l) => l.id)).toEqual(['nuevo'])
  })
})

describe('catálogos y conteos de filtros', () => {
  it('origenes únicos presentes y conteo de marcados', () => {
    expect(origenesDeCola(COLA).sort()).toEqual(['formulario', 'landing'].sort())
    expect(contarMarcados(COLA)).toBe(1)
    expect(contarMarcados([])).toBe(0)
  })

  it('lista distritos reales y cuenta solo filtros avanzados activos', () => {
    expect(distritosDeCola(COLA)).toEqual(['Miraflores', 'San Juan de Lurigancho'])
    expect(contarFiltrosAvanzados(FILTROS_INICIALES)).toBe(0)
    expect(contarFiltrosAvanzados({
      ...FILTROS_INICIALES,
      moneda: 'PEN',
      montoMin: '10000',
      comentario: 'con',
    })).toBe(3)
  })
})
