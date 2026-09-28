// G4b: la lista exacta de «Citas agendadas». La frontera rechaza cualquier página que no
// se pueda confirmar entera, y en demo la lista cuadra con la cifra del pulso y del detalle.
import { describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
import { PulsoGerenciaSchema } from './gestion-diaria-pulso'
import { detalleOperacionDesdeDemo, pulsoGerenciaDesdeDemo, type MundoDemo } from './gestion-diaria-pulso-demo'
import { citasDesdeDemo, unirPaginasCitas, validarPaginaCitas, type CitaAgendada, type PaginaCitas, type PedidoCitas } from './gestion-diaria-citas'
import type { Tarea } from './tipos'

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const cita = (n: number, creado: string, extra: Partial<CitaAgendada> = {}): CitaAgendada => ({
  id: id(n), vendedor_id: id(90), vendedor_nombre: 'ANALISTA', lead_id: id(200 + n), lead_nombre: `LEAD ${n}`,
  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', creado_en: creado, ...extra,
})
const pedido: PedidoCitas = { dia: '2026-09-24', ambito: 'analista', id: id(90), limite: 2, cursor: null }
const pagina = (items: CitaAgendada[], extra: Partial<PaginaCitas> = {}): PaginaCitas => ({
  version: 1, zona: 'America/Lima', dia: '2026-09-24', ambito: 'analista', id: id(90), generado_en: '2026-09-24T17:00:00.000Z',
  limite: 2, resumen: { total: items.length }, items, hay_mas: false, siguiente_cursor: null, ...extra,
})

describe('validarPaginaCitas', () => {
  const a = cita(1, '2026-09-24T05:00:00.000Z') // primer instante del día Lima
  const b = cita(2, '2026-09-25T04:59:59.999999Z') // último
  it('acepta una página completa, en orden y dentro del día Lima', () => {
    expect(validarPaginaCitas(pagina([a, b]), pedido)).not.toBeNull()
  })
  it.each([
    ['otro día', pagina([a, b], { dia: '2026-09-23' })],
    ['otro ámbito', pagina([a, b], { ambito: 'equipo' })],
    ['otro id', pagina([a, b], { id: id(91) })],
    ['otro límite', pagina([a, b], { limite: 3 })],
    ['clave desconocida', { ...pagina([a, b]), extra: 1 }],
    ['fuera del día (antes)', pagina([cita(3, '2026-09-24T04:59:59.999Z'), b])],
    ['fuera del día (después)', pagina([a, cita(4, '2026-09-25T05:00:00.000Z')])],
    ['desordenada', pagina([b, a])],
    ['repetida', pagina([a, a], { resumen: { total: 2 } })],
    ['de otro analista en su ámbito', pagina([a, cita(5, '2026-09-24T06:00:00.000Z', { vendedor_id: id(91) })])],
    ['lead sin nombre', pagina([cita(6, '2026-09-24T06:00:00.000Z', { lead_nombre: null })])],
    ['total que no cuadra sin más páginas', pagina([a, b], { resumen: { total: 3 } })],
    ['hay_mas sin cursor', pagina([a, b], { hay_mas: true, resumen: { total: 3 } })],
    ['cursor que no es la última fila', pagina([a, b], { hay_mas: true, resumen: { total: 3 }, siguiente_cursor: { despues_de: a.creado_en, despues_id: a.id } })],
    ['estado desconocido', pagina([{ ...a, estado: 'borrada' as never }])],
  ])('rechaza: %s', (_, valor) => {
    expect(validarPaginaCitas(valor, pedido)).toBeNull()
  })
  it('una segunda página debe seguir al cursor pedido', () => {
    const primera = pagina([a, b], { hay_mas: true, resumen: { total: 3 }, siguiente_cursor: { despues_de: b.creado_en, despues_id: b.id } })
    expect(validarPaginaCitas(primera, pedido)).not.toBeNull()
    const c = cita(7, '2026-09-24T06:00:00.000Z')
    const conCursor = { ...pedido, cursor: { despues_de: b.creado_en, despues_id: b.id } }
    // Anterior al cursor: no es la continuación.
    expect(validarPaginaCitas(pagina([c], { resumen: { total: 3 } }), conCursor)).toBeNull()
    // Sola, la primera es coherente: dice 3 y trae 2 porque faltan páginas.
    expect(unirPaginasCitas([primera])).toEqual({ items: [a, b], total: 3 })
  })
  it('en «operación» y «fuera» las filas son de cualquier autor, también sin autor', () => {
    const libre = { ...pedido, ambito: 'fuera' as const, id: null }
    expect(validarPaginaCitas(pagina([cita(8, '2026-09-24T06:00:00.000Z', { vendedor_id: null, vendedor_nombre: null })], { ambito: 'fuera', id: null }), libre)).not.toBeNull()
  })
})

describe('unirPaginasCitas: la secuencia de páginas ES la lista (Codex P1)', () => {
  const x1 = cita(11, '2026-09-24T06:00:00.000Z'), x2 = cita(12, '2026-09-24T07:00:00.000Z')
  const x3 = cita(13, '2026-09-24T08:00:00.000Z'), x4 = cita(14, '2026-09-24T09:00:00.000Z')
  const primera = (total: number) => pagina([x1, x2], { resumen: { total }, hay_mas: true, siguiente_cursor: { despues_de: x2.creado_en, despues_id: x2.id } })
  const siguiente = (total: number, items: CitaAgendada[]) => pagina(items, { resumen: { total } })
  it('dos páginas coherentes: todas las filas, en orden, y su total', () => {
    expect(unirPaginasCitas([primera(3), siguiente(3, [x3])])).toEqual({ items: [x1, x2, x3], total: 3 })
  })
  it('se creó una cita entre páginas: la segunda dice otro total y la secuencia no vale', () => {
    // Antes: «3 citas» anunciadas y 4 filas mostradas, sin aviso.
    expect(unirPaginasCitas([primera(3), siguiente(4, [x3, x4])])).toBeNull()
  })
  it('se retiró una cita entre páginas: tampoco vale', () => {
    expect(unirPaginasCitas([primera(3), siguiente(2, [])])).toBeNull()
  })
  it('mismo total pero una fila repetida entre páginas', () => {
    expect(unirPaginasCitas([primera(3), siguiente(3, [x2])])).toBeNull()
  })
  it('terminada con menos filas que su total', () => {
    expect(unirPaginasCitas([primera(4), siguiente(4, [x3])])).toBeNull()
  })
  it('con páginas por venir, las filas cargadas no alcanzan el total', () => {
    expect(unirPaginasCitas([primera(2)])).toBeNull()
  })
  it('sin páginas: lista vacía y total desconocido', () => {
    expect(unirPaginasCitas([])).toEqual({ items: [], total: null })
  })
})

// El mundo demo se siembra RELATIVO al reloj: se fija antes de importarlo.
const AHORA = Date.parse('2026-09-24T17:00:00Z')
vi.useFakeTimers()
vi.setSystemTime(AHORA)
const demo = await import('./demo')
vi.useRealTimers()
const HOY = '2026-09-24'
const reunion = (n: number, lead_id: string | null, vendedor_id: string | null, creado_en: string): Tarea => ({
  id: id(500 + n), lead_id, perfil_id: lead_id ? null : 'd-ger', vendedor_id, tipo: 'reunion', titulo: `Cita ${n}`,
  vence_en: '2026-09-26T15:00:00.000Z', estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en,
})

describe('citas en demo: la lista ES la cifra', () => {
  const lead = (vendedor: string) => demo.LEADS_DEMO.find((l) => l.activo && l.vendedor_id === vendedor)!
  const sinDueno = demo.LEADS_DEMO.find((l) => !l.vendedor_id)
  const extra: Tarea[] = [
    reunion(1, lead('d-v1').id, 'd-v1', '2026-09-24T05:00:00.000Z'),
    reunion(2, lead('d-v1').id, 'd-v1', '2026-09-24T14:00:00.000Z'),
    reunion(3, lead('d-v3').id, 'd-v3', '2026-09-24T15:00:00.000Z'),
    reunion(4, null, null, '2026-09-24T16:00:00.000Z'),
    reunion(5, lead('d-v1').id, 'd-v1', '2026-09-23T12:00:00.000Z'),
    ...(sinDueno ? [reunion(6, sinDueno.id, null, '2026-09-24T16:30:00.000Z')] : []),
  ]
  const mundo: MundoDemo = { miembros: demo.EQUIPO_DEMO, leads: demo.LEADS_DEMO, actividades: demo.ACTIVIDADES_DEMO, tareas: [...demo.TAREAS_DEMO, ...extra], ahora: AHORA }
  const pulso = v.parse(PulsoGerenciaSchema, pulsoGerenciaDesdeDemo(mundo, HOY))
  const lista = (ambito: PedidoCitas['ambito'], clave: string | null) => citasDesdeDemo({ dia: HOY, ambito, id: clave, limite: 100, cursor: null }, mundo)
  it('cada equipo y «fuera» son su cifra del pulso, y juntos son la operación sin solaparse', () => {
    const porEquipo = pulso.equipos.map((e) => ({ e, p: lista(e.clave === 'fuera' ? 'fuera' : 'equipo', e.clave === 'fuera' ? null : e.clave) }))
    for (const { e, p } of porEquipo) expect(p.resumen.total).toBe(e.metricas.citas_agendadas)
    const operacion = lista('operacion', null)
    expect(operacion.resumen.total).toBe(pulso.actual.citas_agendadas)
    expect(operacion.resumen.total).toBeGreaterThan(0)
    const union = porEquipo.flatMap(({ p }) => p.items.map((x) => x.id))
    expect(new Set(union).size).toBe(union.length)
    expect(union.toSorted()).toEqual(operacion.items.map((x) => x.id).toSorted())
  })
  it('cada analista es su cifra del detalle; el día anterior no entra', () => {
    const detalle = detalleOperacionDesdeDemo(mundo, HOY)
    for (const f of detalle.equipo) expect(lista('analista', f.analista_id).resumen.total).toBe(f.marcador.citas_agendadas)
    expect(lista('analista', 'd-v1').items.map((x) => x.id)).toEqual([id(501), id(502)])
    expect(lista('fuera', null).items.map((x) => x.id)).toContain(id(504))
  })
  it('pagina con cursor sin repetir ni saltar', () => {
    const primera = citasDesdeDemo({ dia: HOY, ambito: 'operacion', id: null, limite: 2, cursor: null }, mundo)
    expect(primera.hay_mas).toBe(primera.resumen.total > 2)
    if (primera.siguiente_cursor) {
      const segunda = citasDesdeDemo({ dia: HOY, ambito: 'operacion', id: null, limite: 2, cursor: primera.siguiente_cursor }, mundo)
      expect(segunda.items.some((x) => primera.items.some((y) => y.id === x.id))).toBe(false)
      // Los ids demo no son UUID (el demo no pasa por la frontera): se comprueba la semántica del cursor.
      expect([...primera.items, ...segunda.items].length).toBe(Math.min(4, primera.resumen.total))
    }
  })
})
