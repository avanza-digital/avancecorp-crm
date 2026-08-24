import { describe, expect, it } from 'vitest'
import type { EstancadoCola } from './cola-accion'
import {
  derivarNovedades,
  fotoDeVisita,
  guardarFotoVisita,
  leerFotoVisita,
  resumenNovedades,
} from './visita-sin-movimiento'

const AHORA = Date.UTC(2026, 7, 24, 15)

/** Almacén de mentira determinista: el módulo es inyectable a propósito. */
function almacenFalso(inicial: Record<string, string> = {}) {
  const datos = new Map(Object.entries(inicial))
  return {
    datos,
    getItem: (k: string) => datos.get(k) ?? null,
    setItem: (k: string, v: string) => { datos.set(k, v) },
  }
}

function almacenQueLanza() {
  return {
    getItem: () => { throw new Error('bloqueado') },
    setItem: () => { throw new Error('bloqueado') },
  }
}

function estancado(leadId: string, dias: number): EstancadoCola {
  return { leadId, nombre: `Lead ${leadId}`, vendedorId: 'v1', dias }
}

describe('fotoDeVisita + almacenamiento', () => {
  it('guarda ids→días SIN nombres (sin PII en el navegador) y vuelve intacta', () => {
    const foto = fotoDeVisita([estancado('l1', 5), estancado('l2', 8)], AHORA)
    expect(foto).toEqual({
      vistoEn: '2026-08-24T15:00:00.000Z',
      dias: { l1: 5, l2: 8 },
    })
    expect(JSON.stringify(foto)).not.toContain('Lead')

    const almacen = almacenFalso()
    guardarFotoVisita('s1', foto, almacen)
    expect([...almacen.datos.keys()]).toEqual(['crm:sin-movimiento:visita:s1'])
    expect(leerFotoVisita('s1', almacen)).toEqual(foto)
    // La foto es POR supervisor: otro id no ve nada.
    expect(leerFotoVisita('s2', almacen)).toBeNull()
  })

  it('una foto corrupta o ilegible se descarta a null — jamás rompe ni inventa marcas', () => {
    expect(leerFotoVisita('s1', almacenFalso({ 'crm:sin-movimiento:visita:s1': '{no-json' }))).toBeNull()
    expect(leerFotoVisita('s1', almacenFalso({
      'crm:sin-movimiento:visita:s1': JSON.stringify({ dias: 'no' }),
    }))).toBeNull()
  })

  it('con el storage LANZANDO (Safari privado), leer da null y guardar no revienta', () => {
    expect(leerFotoVisita('s1', almacenQueLanza())).toBeNull()
    expect(() => guardarFotoVisita('s1', fotoDeVisita([], AHORA), almacenQueLanza())).not.toThrow()
  })
})

describe('derivarNovedades', () => {
  const FOTO = fotoDeVisita([estancado('viejo-ambar', 5), estancado('viejo-rojo', 9)], AHORA)

  it('sin foto anterior no marca nada: la primera visita no tiene «desde cuándo»', () => {
    expect(derivarNovedades([estancado('l1', 6)], null)).toBeNull()
  })

  it('marca al que ENTRÓ y al que CRUZÓ a crítico; el paso del tiempo no es novedad', () => {
    const novedades = derivarNovedades([
      estancado('viejo-ambar', 7), // visto en ámbar (5), hoy crítico → cruzó
      estancado('viejo-rojo', 11), // ya era crítico: más días NO es novedad
      estancado('recien', 5), // no estaba en la foto → nuevo
    ], FOTO)
    expect([...novedades!.nuevos]).toEqual(['recien'])
    expect([...novedades!.agravados]).toEqual(['viejo-ambar'])
    expect(novedades!.vistoEn).toBe('2026-08-24T15:00:00.000Z')
  })

  it('un ámbar que sigue en ámbar no cruza (borde: 6 días sigue sin marcar)', () => {
    const novedades = derivarNovedades([estancado('viejo-ambar', 6)], FOTO)
    expect(novedades!.nuevos.size).toBe(0)
    expect(novedades!.agravados.size).toBe(0)
  })

  it('el que SALIÓ de la lista no genera nada: mejorar no hace ruido', () => {
    const novedades = derivarNovedades([], FOTO)
    expect(novedades!.nuevos.size + novedades!.agravados.size).toBe(0)
  })
})

describe('resumenNovedades', () => {
  it('dice solo lo que hay, con plurales honestos — y calla cuando no hay nada', () => {
    expect(resumenNovedades(null)).toBeNull()
    expect(resumenNovedades({ nuevos: new Set(), agravados: new Set(), vistoEn: 'x' })).toBeNull()
    expect(resumenNovedades({ nuevos: new Set(['a']), agravados: new Set(), vistoEn: 'x' }))
      .toBe('Desde tu última visita: 1 nuevo')
    expect(resumenNovedades({
      nuevos: new Set(['a', 'b']),
      agravados: new Set(['c']),
      vistoEn: 'x',
    })).toBe('Desde tu última visita: 2 nuevos · 1 cruzó a crítico')
    expect(resumenNovedades({ nuevos: new Set(), agravados: new Set(['c', 'd']), vistoEn: 'x' }))
      .toBe('Desde tu última visita: 2 cruzaron a crítico')
  })

  it('con la lista RECORTADA al tope confiesa su alcance — pero el silencio sigue siendo silencio', () => {
    expect(resumenNovedades({ nuevos: new Set(['a']), agravados: new Set(), vistoEn: 'x' }, 50))
      .toBe('Desde tu última visita: 1 nuevo · entre los 50 más antiguos')
    // Sin novedades no se dice nada: el «50+» de la pestaña ya cuenta el recorte.
    expect(resumenNovedades({ nuevos: new Set(), agravados: new Set(), vistoEn: 'x' }, 50)).toBeNull()
  })
})
