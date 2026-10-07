import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  AsignacionCelularSchema, CelularSaludSchema, CredencialCelularSchema, ETIQUETA_CELULAR, etiquetaMotivoCierre,
  fechaCortaLima, presentarSalud, resumenVigentes, type CelularSalud,
} from './celulares'

const alDia: CelularSalud = {
  asignacion_id: 'a1', etiqueta: 'C1', analista_id: 'u1', analista_nombre: 'ANA TORRES', vigente_desde: '2026-10-07T13:00:00Z',
  estado_latido: 'al_dia', horas_sin_latido: 0, reloj_desfasado: false, version_macro: 'llamadas-v3', eventos_en_cola: 0,
}

describe('presentarSalud: los seis estados de la tarjeta', () => {
  it('al día: un solo chip, sin avisos ni pista, y Rotar disponible', () => {
    const s = presentarSalud(alDia, true)
    expect(s.principal).toEqual({ texto: 'Al día', tono: 'bien' })
    expect(s.extras).toEqual([])
    expect(s.pista).toBeNull()
    expect(s).toMatchObject({ macroTexto: 'llamadas-v3', colaTexto: '0', colaAviso: false, rotable: true })
  })
  it('sin latido: las horas enteras y la cola atascada en ámbar', () => {
    const s = presentarSalud({ ...alDia, estado_latido: 'sin_latido', horas_sin_latido: 9, eventos_en_cola: 3 }, true)
    expect(s.principal).toEqual({ texto: 'Sin latido · 9 h', tono: 'aviso' })
    expect(s).toMatchObject({ colaTexto: '3', colaAviso: true, rotable: true })
  })
  it('nunca habló: sin dato se dice «—», nunca 0', () => {
    const s = presentarSalud({ ...alDia, estado_latido: 'nunca', horas_sin_latido: null, version_macro: null, eventos_en_cola: null }, true)
    expect(s.principal).toEqual({ texto: 'Nunca habló', tono: 'quieto' })
    expect(s).toMatchObject({ macroTexto: '—', colaTexto: '—', colaAviso: false })
    expect(s.pista).toBe('Esperando el primer latido de la macro.')
  })
  it('reloj desfasado y macro vieja se suman a «Al día», no lo reemplazan', () => {
    const s = presentarSalud({ ...alDia, reloj_desfasado: true, version_macro: 'llamadas-v2' }, true)
    expect(s.principal.texto).toBe('Al día')
    expect(s.extras).toEqual([{ texto: 'Reloj desfasado', tono: 'aviso' }, { texto: 'Macro vieja', tono: 'aviso' }])
    expect(s.pista).toMatch(/reloj del celular/)
  })
  it('macro vieja sola: la pista dice a qué versión pasar', () => {
    const s = presentarSalud({ ...alDia, version_macro: 'llamadas-v2' }, true)
    expect(s.extras).toEqual([{ texto: 'Macro vieja', tono: 'aviso' }])
    expect(s.pista).toBe('Falta cambiar el texto del latido a llamadas-v3.')
  })
  it('analista de baja manda sobre todo lo demás y quita Rotar (el servidor lo niega con 22023)', () => {
    const s = presentarSalud({ ...alDia, estado_latido: 'sin_latido', horas_sin_latido: 31, reloj_desfasado: true, eventos_en_cola: 12 }, false)
    expect(s.principal).toEqual({ texto: 'Analista de baja', tono: 'mal' })
    expect(s.extras).toEqual([])
    expect(s.pista).toBe('Sin rotación: ciérralo y asígnalo a otro analista.')
    expect(s).toMatchObject({ rotable: false, colaAviso: true })
  })
  it('sin catálogo (null) se confía en el servidor: Rotar sigue disponible', () => {
    expect(presentarSalud(alDia, null).rotable).toBe(true)
  })
})

describe('etiqueta, esquemas y textos', () => {
  it('la etiqueta es la misma regla que el servidor: C1 … C999', () => {
    for (const ok of ['C1', 'C9', 'C10', 'C999']) expect(ETIQUETA_CELULAR.test(ok)).toBe(true)
    for (const mal of ['C0', 'C01', 'C1000', 'c1', 'C', 'C1 ', '1']) expect(ETIQUETA_CELULAR.test(mal)).toBe(false)
  })
  it('la credencial es hexadecimal de 64: otra cosa no se usa', () => {
    const hex = 'a'.repeat(64)
    const base = { asignacion_id: 'a1', etiqueta: 'C1', analista_id: 'u1' }
    expect(v.safeParse(CredencialCelularSchema, { ...base, credencial: hex }).success).toBe(true)
    expect(v.safeParse(CredencialCelularSchema, { ...base, credencial: hex, anterior_id: 'a0' }).success).toBe(true)
    expect(v.safeParse(CredencialCelularSchema, { ...base, credencial: 'a'.repeat(63) }).success).toBe(false)
    expect(v.safeParse(CredencialCelularSchema, { ...base, credencial: 'A'.repeat(64) }).success).toBe(false)
    expect(v.safeParse(CredencialCelularSchema, { ...base, credencial: 'demo' + 'a'.repeat(60) }).success).toBe(false)
  })
  it('la salud es estricta: si volviera la hora exacta del latido, se nota', () => {
    expect(v.safeParse(CelularSaludSchema, alDia).success).toBe(true)
    expect(v.safeParse(CelularSaludSchema, { ...alDia, ultimo_latido_en: '2026-10-07T12:00:00Z' }).success).toBe(false)
    expect(v.safeParse(CelularSaludSchema, { ...alDia, estado_latido: 'dormido' }).success).toBe(false)
  })
  it('las asignaciones vienen sin el hash', () => {
    const fila = { asignacion_id: 'a1', etiqueta: 'C1', analista_id: 'u1', analista_nombre: null, vigente_desde: '2026-10-01T13:00:00Z', vigente_hasta: null, motivo_cierre: null }
    expect(v.safeParse(AsignacionCelularSchema, fila).success).toBe(true)
    expect(v.safeParse(AsignacionCelularSchema, { ...fila, credencial_hash: 'x' }).success).toBe(false)
  })
  it('los motivos de cierre se dicen en llano; uno desconocido se muestra tal cual', () => {
    expect(etiquetaMotivoCierre('rotacion')).toBe('Rotación de clave')
    expect(etiquetaMotivoCierre('baja_analista')).toBe('Baja del analista')
    expect(etiquetaMotivoCierre('otro')).toBe('Otro')
    expect(etiquetaMotivoCierre(null)).toBe('—')
    expect(etiquetaMotivoCierre('nuevo_motivo')).toBe('nuevo_motivo')
  })
  it('la fecha corta va en hora de Lima y nunca dice «Invalid Date»', () => {
    expect(fechaCortaLima('2026-10-07T03:30:00Z')).toMatch(/^6 oct\.? 2026$/)
    expect(fechaCortaLima('no-es-fecha')).toBe('no-es-fecha')
  })
})

describe('resumenVigentes: la cabecera de la tarjeta', () => {
  it('sin celulares', () => {
    expect(resumenVigentes([], () => true)).toEqual({ etiqueta: 'Sin celulares', detalle: 'Ningún celular asignado todavía.' })
  })
  it('cuenta lo que necesita atención; el analista de baja no se cuenta dos veces', () => {
    const filas: CelularSalud[] = [
      alDia,
      { ...alDia, asignacion_id: 'a2', etiqueta: 'C2', analista_id: 'u2', estado_latido: 'sin_latido', horas_sin_latido: 9 },
      { ...alDia, asignacion_id: 'a3', etiqueta: 'C3', analista_id: 'u3', estado_latido: 'nunca', horas_sin_latido: null },
      { ...alDia, asignacion_id: 'a5', etiqueta: 'C5', analista_id: 'u5', estado_latido: 'sin_latido', horas_sin_latido: 31 },
    ]
    expect(resumenVigentes(filas, (id) => id !== 'u5')).toEqual({ etiqueta: '4 vigentes', detalle: '1 sin latido · 1 nunca habló · 1 con analista de baja' })
  })
  it('todos al día', () => {
    expect(resumenVigentes([alDia], () => null)).toEqual({ etiqueta: '1 vigente', detalle: 'Todos al día.' })
  })
})
