// F4-e: el espejo del jsonb de «la operación de hoy» y lo que la pantalla deriva de él.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { EQUIPO_DEMO } from './demo'
import { operacionCelularDesdeDemo } from './llamadas-celular-operacion-demo'
import {
  FILTROS_CELULAR, LlamadasHoySchema, OperacionCelularHoySchema, PendientesSchema, detallePendientes, detalleVias, filasEquiposCelular,
  filtrarOrdenarCelular, motivosAtencion, porcentaje,
} from './llamadas-celular-operacion'

const AHORA = Date.parse('2026-10-13T15:00:00Z')
const gerencia = () => operacionCelularDesdeDemo(EQUIPO_DEMO, AHORA, 'd-ger', 'gerencia')
const supervisor = () => operacionCelularDesdeDemo(EQUIPO_DEMO, AHORA, 'd-sup1', 'supervisor')

describe('La demo de F4-e pasa por el mismo contrato que la respuesta real', () => {
  it('gerencia ve toda la operación: dos equipos, tres analistas, sumas que cuadran y sin celular propio', () => {
    const datos = gerencia()
    expect(v.safeParse(OperacionCelularHoySchema, datos).success).toBe(true)
    expect(datos.alcance).toBe('operacion')
    expect(datos.dia).toBe('2026-10-13')
    expect(datos.equipos.map((e) => e.supervisor_nombre)).toEqual(['SUPERVISOR DOS', 'SUPERVISOR UNO'])
    expect(datos.analistas.map((a) => a.nombre)).toEqual(['ANALISTA DOS', 'ANALISTA TRES', 'ANALISTA UNO'])
    expect(datos.totales.llamadas_hoy.total).toBe(14)
    expect(datos.totales.pendientes).toEqual({ total: 4, de_hoy: 3, anteriores: 1, mas_antigua_dias: 1, deshechas_sin_corregir: 1 })
    expect(datos.totales).toMatchObject({ celulares_vigentes: 3, celulares_sin_latido: 2, analistas_sin_dato: 1 })
    expect(datos.analistas.find((a) => a.analista_id === 'd-v3')).toMatchObject({ sin_dato: true, celulares: [{ etiqueta: 'C3', estado_latido: 'nunca' }] })
    expect(datos.su_celular).toBeNull()
  })
  it('el supervisor ve solo su subárbol y su propio celular aparte', () => {
    const datos = supervisor()
    expect(v.safeParse(OperacionCelularHoySchema, datos).success).toBe(true)
    expect(datos.alcance).toBe('equipo')
    expect(datos.equipos).toHaveLength(1)
    expect(datos.equipos[0]).toMatchObject({ supervisor_id: 'd-sup1', analistas: 2, celulares_vigentes: 2, celulares_sin_latido: 1 })
    expect(datos.analistas.map((a) => a.analista_id)).toEqual(['d-v2', 'd-v1'])
    expect(datos.su_celular).toEqual([expect.objectContaining({ etiqueta: 'C4', estado_latido: 'al_dia' })])
  })
  it('un supervisor sin analistas tiene la operación vacía y ningún celular propio', () => {
    const datos = operacionCelularDesdeDemo(EQUIPO_DEMO, AHORA, 'd-otro', 'supervisor')
    expect(v.safeParse(OperacionCelularHoySchema, datos).success).toBe(true)
    expect(datos.equipos).toEqual([])
    expect(datos.totales.llamadas_hoy.total).toBe(0)
    expect(datos.su_celular).toEqual([])
  })
})

describe('El contrato rechaza lo que no cuadra', () => {
  it('las cubetas de «llamadas de hoy» tienen que sumar el total', () => {
    const base = gerencia().analistas[0]!.llamadas_hoy
    expect(v.safeParse(LlamadasHoySchema, base).success).toBe(true)
    expect(v.safeParse(LlamadasHoySchema, { ...base, total: base.total + 1 }).success).toBe(false)
  })
  it('«sin resultado» dice la más antigua exactamente cuando hay pendientes', () => {
    expect(v.safeParse(PendientesSchema, { total: 0, de_hoy: 0, anteriores: 0, mas_antigua_dias: 1, deshechas_sin_corregir: 0 }).success).toBe(false)
    expect(v.safeParse(PendientesSchema, { total: 2, de_hoy: 1, anteriores: 1, mas_antigua_dias: null, deshechas_sin_corregir: 0 }).success).toBe(false)
    expect(v.safeParse(PendientesSchema, { total: 2, de_hoy: 1, anteriores: 2, mas_antigua_dias: 1, deshechas_sin_corregir: 0 }).success).toBe(false)
  })
  it('los totales y los equipos son la suma de sus analistas; «sin dato» sigue D1', () => {
    const datos = gerencia()
    const totalesRotos = structuredClone(datos)
    totalesRotos.totales.llamadas_hoy.total += 1
    totalesRotos.totales.llamadas_hoy.con_resultado += 1
    expect(v.safeParse(OperacionCelularHoySchema, totalesRotos).success).toBe(false)
    const equipoRoto = structuredClone(datos)
    equipoRoto.equipos[0]!.analistas += 1
    expect(v.safeParse(OperacionCelularHoySchema, equipoRoto).success).toBe(false)
    const sinDatoRoto = structuredClone(datos)
    const tres = sinDatoRoto.analistas.find((a) => a.analista_id === 'd-v3')!
    tres.sin_dato = false
    sinDatoRoto.totales.analistas_sin_dato -= 1
    sinDatoRoto.equipos.find((e) => e.supervisor_id === 'd-sup2')!.analistas_sin_dato -= 1
    expect(v.safeParse(OperacionCelularHoySchema, sinDatoRoto).success).toBe(false)
  })
})

describe('Lo que la pantalla deriva', () => {
  it('los porcentajes salen de pares de la misma cohorte y sin denominador son «—»', () => {
    expect(porcentaje(5, 8)).toBe(63)
    expect(porcentaje(0, 0)).toBeNull()
    expect(porcentaje(0, 4)).toBe(0)
  })
  it('las filas por equipo se filtran por pastilla y se ordenan por «sin resultado» de más a menos', () => {
    const filas = filasEquiposCelular(gerencia())
    expect(filtrarOrdenarCelular(filas, FILTROS_CELULAR).map((f) => f.nombre)).toEqual(['SUPERVISOR UNO', 'SUPERVISOR DOS'])
    expect(filtrarOrdenarCelular(filas, { ...FILTROS_CELULAR, orden: 'nombre', ascendente: true }).map((f) => f.nombre)).toEqual(['SUPERVISOR DOS', 'SUPERVISOR UNO'])
    // «Sin latido» cuenta también al que nunca habló (C3 de Supervisor Dos), como celulares_sin_latido.
    expect(filtrarOrdenarCelular(filas, { ...FILTROS_CELULAR, estado: 'sin_latido' }).map((f) => f.nombre)).toEqual(['SUPERVISOR UNO', 'SUPERVISOR DOS'])
    expect(filtrarOrdenarCelular(filas, { ...FILTROS_CELULAR, estado: 'por_revisar' }).map((f) => f.nombre)).toEqual(['SUPERVISOR UNO'])
    expect(filtrarOrdenarCelular(filas, { ...FILTROS_CELULAR, busqueda: 'dós' }).map((f) => f.nombre)).toEqual(['SUPERVISOR DOS'])
    expect(filas.find((f) => f.nombre === 'SUPERVISOR UNO')).toMatchObject({ clave: 'd-sup1', fuera: false, conAtencion: 2 })
    expect(filas.find((f) => f.nombre === 'SUPERVISOR DOS')).toMatchObject({ conAtencion: 1 })
  })
  it('los motivos de atención se dicen en orden: pendientes, deshechas, por revisar, celular, sin dato', () => {
    const datos = gerencia()
    const uno = datos.analistas.find((a) => a.analista_id === 'd-v1')!
    const dos = datos.analistas.find((a) => a.analista_id === 'd-v2')!
    const tres = datos.analistas.find((a) => a.analista_id === 'd-v3')!
    expect(motivosAtencion(uno)).toEqual(['2 llamadas sin resultado', '1 deshecha sin corregir', '1 llamada por revisar'])
    expect(motivosAtencion(dos)).toEqual(['2 llamadas sin resultado', 'C2 sin latido · 9 h', 'C2 con 3 avisos en cola'])
    expect(motivosAtencion(tres)).toEqual(['C3 nunca habló', 'sin dato del celular'])
  })
  it('los detalles bajo las cifras solo dicen lo que existe', () => {
    expect(detallePendientes({ total: 0, de_hoy: 0, anteriores: 0, mas_antigua_dias: null, deshechas_sin_corregir: 0 })).toBe('')
    expect(detallePendientes({ total: 2, de_hoy: 1, anteriores: 1, mas_antigua_dias: 1, deshechas_sin_corregir: 0 })).toBe('1 de hoy · 1 anterior · la más antigua hace 1 día')
    expect(detallePendientes({ total: 2, de_hoy: 2, anteriores: 0, mas_antigua_dias: 0, deshechas_sin_corregir: 0 })).toBe('2 de hoy')
    expect(detalleVias({ total: 7, al_colgar: 5, desde_pestana: 1, a_mano: 1 })).toBe('5 al colgar · 1 desde la pestaña · 1 a mano')
    expect(detalleVias({ total: 0, al_colgar: 0, desde_pestana: 0, a_mano: 0 })).toBe('')
  })
})
