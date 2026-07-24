import { describe, expect, it } from 'vitest'
import {
  FILTROS_INICIALES,
  contarMarcados,
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
  clasificacion_auto: 'posible_credito', comentario: 'Necesito un préstamo urgente',
})
const NUEVO = lead({
  id: 'nuevo', creado_en: '2026-07-24T09:15:00.000Z', origen: 'landing',
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
})

describe('origenesDeCola / contarMarcados', () => {
  it('origenes únicos presentes y conteo de marcados', () => {
    expect(origenesDeCola(COLA).sort()).toEqual(['formulario', 'landing'].sort())
    expect(contarMarcados(COLA)).toBe(1)
    expect(contarMarcados([])).toBe(0)
  })
})
