import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { CortesJornadaSchema, type CortesJornada } from './gestion-diaria-cortes'
import { DiaEquipoSchema, filtrarOrdenarEquipo, presentarEquipo } from './gestion-diaria-equipo'
import { diaEquipoPrueba } from './gestion-diaria-equipo.fixture'

function cortes(): CortesJornada {
  return {
    version: 1, politica_version: 2, estado: 'activo', cartera_referencia: 'consulta_actual',
    inicio_jornada: '2026-09-21T09:00:00-05:00', fin_jornada: '2026-09-21T18:00:00-05:00',
    primer_corte_en: '2026-09-21T11:30:00-05:00', segundo_corte_en: '2026-09-21T16:00:00-05:00',
    equipo: [{ analista_id: 'a1', cartera_abierta: true,
      primer_corte: { estado: 'recuperado', llamadas: 1, objetivo: 3, base: 1,
        llamadas_recuperacion: 3, aviso_pendiente: false, puede_avisar: false },
      segundo_corte: { estado: 'incumplido', llamadas: 3, objetivo: 8, base: 1,
        llamadas_recuperacion: null, aviso_pendiente: true, puede_avisar: true },
    }],
  }
}
function dia(c = cortes()) {
  const d = diaEquipoPrueba()
  return { ...d, umbrales: { ...d.umbrales, politica_version: c.politica_version }, cortes: c }
}
describe('Contrato aditivo de cortes F4.3', () => {
  it('incluye el corte incumplido en el filtro aunque haya actividad reciente, sin modificar la foto', () => {
    const d = dia()
    expect(d.equipo[0]!.requiere_atencion).toBe(false)
    const presentadas = presentarEquipo(d)
    expect(presentadas[0]!.motivos_atencion).toEqual(['corte_tarde'])
    expect(filtrarOrdenarEquipo(presentadas, { busqueda: '', soloProblemas: true,
      orden: 'atencion', ascendente: false })).toHaveLength(1)
    expect(d.equipo[0]!.motivos_atencion).toEqual([])
  })
  it('conserva pendientes después del cierre y sustituye la inactividad duplicada por el corte', () => {
    const d = dia()
    d.equipo[0]!.motivos_atencion = ['tarea_vencida', 'sin_llamar_2h']
    d.equipo[0]!.requiere_atencion = true
    d.cortes.equipo[0]!.segundo_corte!.puede_avisar = false
    expect(presentarEquipo(d)[0]!.motivos_atencion).toEqual(['tarea_vencida', 'corte_tarde'])
    d.cortes.equipo[0]!.segundo_corte!.aviso_pendiente = false
    expect(presentarEquipo(d)[0]!.motivos_atencion).toEqual(['tarea_vencida', 'sin_llamar_2h'])
  })
  it('sin cortes confirmados conserva los motivos existentes, sin inferir incumplimientos', () => {
    const d = diaEquipoPrueba()
    expect(presentarEquipo(d)).toEqual(d.equipo)
  })
  it('admite servidor antiguo sin simular evaluación ni cero', () => {
    const d = v.parse(DiaEquipoSchema, diaEquipoPrueba())
    expect(d).not.toHaveProperty('cortes')
    expect(d.umbrales).not.toHaveProperty('politica_version')
  })
  it('conserva el resultado del servidor, la base fija y versión de política', () => {
    expect(v.parse(DiaEquipoSchema, dia()).cortes).toEqual(cortes())
    const c = cortes(); c.politica_version = 7
    expect(v.safeParse(DiaEquipoSchema, dia(c)).success).toBe(true)
  })
  it.each(['desactivados', 'no_laborable'] as const)('no inventa filas con estado %s', (estado) => {
    const c: CortesJornada = { ...cortes(), estado, equipo: [], inicio_jornada: null,
      fin_jornada: null, primer_corte_en: null, segundo_corte_en: null }
    expect(v.safeParse(DiaEquipoSchema, dia(c)).success).toBe(true)
    c.equipo = cortes().equipo
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(false)
  })
  it('admite cortes futuros con datos nulos, no con conteos evaluados', () => {
    const c = cortes(), f = c.equipo[0]!
    f.primer_corte = { estado: 'pendiente', llamadas: null, objetivo: 3, base: null,
      llamadas_recuperacion: null, aviso_pendiente: false, puede_avisar: false }
    f.segundo_corte = { ...f.primer_corte, objetivo: null }
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(true)
    f.primer_corte.llamadas = 0
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(false)
  })
  it('sábado tiene sólo primer corte y fin a las 13; ningún aviso después del cierre', () => {
    const c = cortes(); c.segundo_corte_en = null; c.fin_jornada = '2026-09-21T13:00:00-05:00'
    c.equipo[0]!.segundo_corte = null
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(true)
    // El estado de pendiente es distinto de la posibilidad actual de mostrarlo.
    const p = c.equipo[0]!.primer_corte
    p.estado = 'incumplido'; p.aviso_pendiente = true; p.puede_avisar = false
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(true)
  })
  it('admite cartera vacía con datos o sin ellos, sin aviso', () => {
    const c = cortes(), f = c.equipo[0]!
    f.cartera_abierta = false; f.primer_corte.estado = 'sin_cartera'
    f.segundo_corte = { ...f.segundo_corte!, estado: 'sin_cartera', aviso_pendiente: false, puede_avisar: false }
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(true)
    f.segundo_corte.aviso_pendiente = true
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(false)
  })
  it('rechaza cortes de otro roster, duplicados, parcialidad y distinta política', () => {
    const c = cortes(); c.equipo[0]!.analista_id = 'ajeno'
    expect(v.safeParse(DiaEquipoSchema, dia(c)).success).toBe(false)
    const repetido = cortes(); repetido.equipo.push(repetido.equipo[0]!)
    expect(v.safeParse(CortesJornadaSchema, repetido).success).toBe(false)
    const parcial = cortes(); parcial.equipo = []
    expect(v.safeParse(DiaEquipoSchema, dia(parcial)).success).toBe(false)
    const d = dia(); d.umbrales.politica_version = 1
    expect(v.safeParse(DiaEquipoSchema, d).success).toBe(false)
  })
  it.each([
    (c: CortesJornada) => { c.equipo[0]!.primer_corte.llamadas = -1 },
    (c: CortesJornada) => { c.equipo[0]!.primer_corte.objetivo = 0 },
    (c: CortesJornada) => { c.equipo[0]!.primer_corte.base = 1.5 },
    (c: CortesJornada) => { c.equipo[0]!.primer_corte.llamadas_recuperacion = null },
    (c: CortesJornada) => { c.equipo[0]!.primer_corte.puede_avisar = true },
    (c: CortesJornada) => { c.equipo[0]!.segundo_corte!.estado = 'recuperado' },
    (c: CortesJornada) => { c.equipo[0]!.segundo_corte!.llamadas = null },
    (c: CortesJornada) => { c.equipo[0]!.segundo_corte!.base = 2 },
    (c: CortesJornada) => { c.equipo[0]!.segundo_corte = null },
    (c: CortesJornada) => { c.equipo[0]!.cartera_abierta = false },
    (c: CortesJornada) => { c.inicio_jornada = null },
    (c: CortesJornada) => { c.fin_jornada = 'infinito' },
    (c: CortesJornada) => { c.primer_corte_en = c.inicio_jornada },
    (c: CortesJornada) => { c.segundo_corte_en = c.fin_jornada },
  ])('rechaza incoherencia estructural %# sin recalcular el objetivo en cliente', (mutar) => {
    const c = cortes(); mutar(c)
    expect(v.safeParse(CortesJornadaSchema, c).success).toBe(false)
  })
})
