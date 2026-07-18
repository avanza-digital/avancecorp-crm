// Tests de la Fase D: geometría Semana/Mes en Lima, filtros de la Agenda y el
// modo "viernes 13:00" (higiene). Reloj SIEMPRE inyectado — nada de Date.now().
import { describe, expect, it } from 'vitest'
import {
  aplicarFiltros,
  colaHigiene,
  diasDeSemana,
  esViernesDeHigiene,
  FILTROS_APAGADOS,
  hayFiltros,
  rejillaMes,
  siguienteMarJue,
  tareasPorDia,
  tituloSemana,
} from './agenda-vistas'
import type { Lead, Tarea } from './tipos'

// Viernes 2026-07-17 12:00 en Lima = 17:00Z (UTC-5) — misma ancla que
// agenda-derivada.test.ts.
const AHORA = Date.parse('2026-07-17T17:00:00Z')

const tarea = (extra: Partial<Tarea>): Tarea => ({
  id: 't1',
  lead_id: 'l1',
  tipo: 'llamada',
  titulo: 'Llamar a Ana',
  vence_en: '2026-07-17T20:00:00Z', // hoy 15:00 Lima
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-16T15:00:00Z',
  ...extra,
})

const lead = (extra: Partial<Lead>): Lead => ({
  id: 'l1',
  nombre_completo: 'Ana Pérez',
  telefono: '+51999888777',
  etapa: 'contactado',
  origen: 'referido',
  monto_estimado: 50_000,
  moneda: 'PEN',
  vendedor_id: 'v1',
  creado_en: '2026-07-10T15:00:00Z',
  activo: true,
  ...extra,
})

describe('diasDeSemana', () => {
  it('la semana de hoy va Lun→Dom en Lima y marca hoy/mar–jue/pasado', () => {
    const dias = diasDeSemana(AHORA)
    expect(dias.map((d) => d.fecha)).toEqual([
      '2026-07-13', '2026-07-14', '2026-07-15', '2026-07-16', '2026-07-17', '2026-07-18', '2026-07-19',
    ])
    expect(dias.map((d) => d.label)).toEqual(['Lun 13', 'Mar 14', 'Mié 15', 'Jue 16', 'Vie 17', 'Sáb 18', 'Dom 19'])
    expect(dias.map((d) => d.esHoy)).toEqual([false, false, false, false, true, false, false])
    expect(dias.map((d) => d.esMarJue)).toEqual([false, true, true, true, false, false, false])
    expect(dias.map((d) => d.esPasado)).toEqual([true, true, true, true, false, false, false])
  })

  it('offset ±1 desplaza semanas enteras (y el título cruza de mes si toca)', () => {
    expect(diasDeSemana(AHORA, 1)[0]?.fecha).toBe('2026-07-20')
    expect(diasDeSemana(AHORA, -1)[0]?.fecha).toBe('2026-07-06')
    expect(tituloSemana(diasDeSemana(AHORA))).toBe('13 – 19 Jul')
    expect(tituloSemana(diasDeSemana(AHORA, 2))).toBe('27 Jul – 2 Ago') // cruza a agosto
  })

  it('la madrugada UTC sigue siendo el día anterior en Lima (sin corrimiento de semana)', () => {
    // Lunes 2026-07-20 a las 03:00Z = domingo 19 22:00 en Lima → semana del 13.
    expect(diasDeSemana(Date.parse('2026-07-20T03:00:00Z'))[0]?.fecha).toBe('2026-07-13')
  })
})

describe('rejillaMes', () => {
  it('julio 2026 (empieza miércoles): 5 semanas con puntas del mes vecino atenuadas', () => {
    const { titulo, semanas } = rejillaMes(AHORA)
    expect(titulo).toBe('Julio 2026')
    expect(semanas).toHaveLength(5)
    expect(semanas[0]?.map((c) => c.fecha)).toEqual([
      '2026-06-29', '2026-06-30', '2026-07-01', '2026-07-02', '2026-07-03', '2026-07-04', '2026-07-05',
    ])
    expect(semanas[0]?.map((c) => c.delMes)).toEqual([false, false, true, true, true, true, true])
    const ultima = semanas[4]
    expect(ultima?.[0]?.fecha).toBe('2026-07-27')
    expect(ultima?.map((c) => c.delMes)).toEqual([true, true, true, true, true, false, false]) // 1–2 Ago
    // Hoy (Vie 17) está marcado en la tercera semana.
    expect(semanas[2]?.find((c) => c.esHoy)?.fecha).toBe('2026-07-17')
  })

  it('offset navega meses y normaliza el cambio de año', () => {
    expect(rejillaMes(AHORA, 1).titulo).toBe('Agosto 2026')
    expect(rejillaMes(AHORA, -7).titulo).toBe('Diciembre 2025')
  })
})

describe('tareasPorDia', () => {
  it('agrupa por día calendario Lima y conserva el orden de entrada', () => {
    const t1 = tarea({ id: 'a', vence_en: '2026-07-17T13:00:00Z' }) // hoy 08:00
    const t2 = tarea({ id: 'b', vence_en: '2026-07-17T20:00:00Z' }) // hoy 15:00
    const t3 = tarea({ id: 'c', vence_en: '2026-07-18T03:00:00Z' }) // ¡sigue siendo 17 en Lima (22:00)!
    const t4 = tarea({ id: 'd', vence_en: '2026-07-18T15:00:00Z' }) // mañana 10:00
    const porDia = tareasPorDia([t1, t2, t3, t4])
    expect(porDia.get('2026-07-17')?.map((t) => t.id)).toEqual(['a', 'b', 'c'])
    expect(porDia.get('2026-07-18')?.map((t) => t.id)).toEqual(['d'])
  })
})

describe('aplicarFiltros', () => {
  const leads = [
    lead({ id: 'l1', nombre_completo: 'Óscar Núñez', etapa: 'propuesta_enviada' }),
    lead({ id: 'l2', nombre_completo: 'Ana Pérez', etapa: 'contactado' }),
  ]
  const leadDe = (id: string | null) => leads.find((l) => l.id === id)
  const tareas = [
    tarea({ id: 'a', lead_id: 'l1', tipo: 'reunion', titulo: 'Cierre con Óscar', vence_en: '2026-07-18T20:00:00Z' }),
    tarea({ id: 'b', lead_id: 'l2', tipo: 'llamada', titulo: 'Llamar a Ana', vence_en: '2026-07-17T13:00:00Z' }), // vencida
    tarea({ id: 'c', lead_id: 'l2', tipo: 'reunion', titulo: 'Reunión Ana', vence_en: '2026-07-20T15:00:00Z', confirmada_en: '2026-07-17T12:00:00Z' }),
  ]

  it('sin filtros devuelve todo; hayFiltros lo detecta', () => {
    expect(aplicarFiltros(tareas, FILTROS_APAGADOS, AHORA, leadDe)).toHaveLength(3)
    expect(hayFiltros(FILTROS_APAGADOS)).toBe(false)
    expect(hayFiltros({ ...FILTROS_APAGADOS, q: 'ana' })).toBe(true)
  })

  it('busca sin acentos contra título y nombre del lead', () => {
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, q: 'oscar' }, AHORA, leadDe).map((t) => t.id)).toEqual(['a'])
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, q: 'nuñez' }, AHORA, leadDe).map((t) => t.id)).toEqual(['a'])
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, q: 'ana' }, AHORA, leadDe).map((t) => t.id)).toEqual(['b', 'c'])
  })

  it('filtra por tipo, por etapa del lead y por estado derivado', () => {
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, tipo: 'llamada' }, AHORA, leadDe).map((t) => t.id)).toEqual(['b'])
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, etapa: 'propuesta_enviada' }, AHORA, leadDe).map((t) => t.id)).toEqual(['a'])
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, estado: 'vencida' }, AHORA, leadDe).map((t) => t.id)).toEqual(['b'])
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, estado: 'confirmada' }, AHORA, leadDe).map((t) => t.id)).toEqual(['c'])
    // Sin confirmar = reuniones FUTURAS sin confirmada_en (el hueco anti no-show).
    expect(aplicarFiltros(tareas, { ...FILTROS_APAGADOS, estado: 'sin_confirmar' }, AHORA, leadDe).map((t) => t.id)).toEqual(['a'])
  })
})

describe('esViernesDeHigiene', () => {
  it('prende el viernes a las 13:00 Lima en punto, no antes ni otro día', () => {
    expect(esViernesDeHigiene(Date.parse('2026-07-17T17:59:00Z'))).toBe(false) // vie 12:59 Lima
    expect(esViernesDeHigiene(Date.parse('2026-07-17T18:00:00Z'))).toBe(true) // vie 13:00 Lima
    expect(esViernesDeHigiene(Date.parse('2026-07-17T23:30:00Z'))).toBe(true) // vie 18:30 Lima
    expect(esViernesDeHigiene(Date.parse('2026-07-18T18:00:00Z'))).toBe(false) // sábado
    // Viernes 20:00 Lima = sábado 01:00Z — el día se decide en Lima, no en UTC.
    expect(esViernesDeHigiene(Date.parse('2026-07-18T01:00:00Z'))).toBe(true)
  })
})

describe('siguienteMarJue', () => {
  it('desde viernes (o fin de semana) cae en el martes a las 10:00 Lima', () => {
    expect(siguienteMarJue(AHORA)).toBe('2026-07-21T15:00:00.000Z') // mar 21, 10:00 Lima
    expect(siguienteMarJue(Date.parse('2026-07-18T20:00:00Z'))).toBe('2026-07-21T15:00:00.000Z') // desde sábado
  })

  it('entre semana avanza al siguiente día del bloque; desde jueves salta al martes', () => {
    expect(siguienteMarJue(Date.parse('2026-07-21T15:00:00Z'))).toBe('2026-07-22T15:00:00.000Z') // mar → mié
    expect(siguienteMarJue(Date.parse('2026-07-23T15:00:00Z'))).toBe('2026-07-28T15:00:00.000Z') // jue → mar próximo
  })
})

describe('colaHigiene', () => {
  it('ordena vencidas → reagendas de no-show fuera de mar–jue → amarillos (PEN desc)', () => {
    const tareas = [
      tarea({ id: 'venc', lead_id: 'l1', vence_en: '2026-07-17T13:00:00Z' }), // vencida hoy 08:00
      tarea({ id: 'ok', lead_id: 'l2', vence_en: '2026-07-21T15:00:00Z', reagendada_de: 'x1' }), // martes: en ritmo
      tarea({ id: 'mal', lead_id: 'l3', vence_en: '2026-07-20T15:00:00Z', reagendada_de: 'x2' }), // lunes: fuera
      tarea({ id: 'cerrada', lead_id: 'l4', estado: 'completada', vence_en: '2026-07-16T15:00:00Z' }),
    ]
    const leads = [
      lead({ id: 'l1' }),
      lead({ id: 'l2' }),
      lead({ id: 'l3' }),
      lead({ id: 'l5', nombre_completo: 'Rosa Quispe', monto_estimado: 80_000 }), // sin tarea → amarillo
      lead({ id: 'l6', nombre_completo: 'Juan Díaz', monto_estimado: 20_000 }), // sin tarea → amarillo
      lead({ id: 'l7', nombre_completo: 'Parkeado', vendedor_id: null }), // sin vendedor: NO es amarillo
    ]
    const conTarea = new Set(['l1', 'l2', 'l3'])
    const items = colaHigiene(tareas, leads, conTarea, AHORA)
    expect(items.map((i) => (i.k === 'sin_accion' ? `${i.k}:${i.lead.id}` : `${i.k}:${i.tarea.id}`))).toEqual([
      'vencida:venc',
      'no_show_fuera_ritmo:mal',
      'sin_accion:l5', // 80k antes que 20k — capital primero
      'sin_accion:l6',
    ])
  })

  it('una reagenda de no-show YA vencida no se duplica: va solo como vencida', () => {
    const t = tarea({ id: 'dup', vence_en: '2026-07-17T13:00:00Z', reagendada_de: 'x' })
    const items = colaHigiene([t], [], new Set(), AHORA)
    expect(items).toHaveLength(1)
    expect(items[0]?.k).toBe('vencida')
  })
})
