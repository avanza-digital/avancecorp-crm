// G0: la gerencia demo ve «Toda la operación» con la operación de ejemplo.
// Lo que se prueba es el CONTRATO: cada salida pasa el mismo esquema que la
// respuesta del servidor (sumas aditivas, personas únicas, «fuera» siempre,
// referencia de hasta 7 jornadas con actividad) y el detalle cuadra con el pulso.
import { describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
import { PulsoGerenciaSchema, desplazarDia, type PulsoGerencia } from './gestion-diaria-pulso'
import { HabitosGerenciaSchema } from './gestion-diaria-habitos'
import { DiaEquipoSchema } from './gestion-diaria-equipo'
import { diaEquipoDesdeDemo } from './gestion-diaria-equipo-demo'
import { detalleOperacionDesdeDemo, habitosGerenciaDesdeDemo, pulsoGerenciaDesdeDemo, type MundoDemo } from './gestion-diaria-pulso-demo'
import type { Actividad, Lead, Miembro, Tarea } from './tipos'

// El fixture demo se siembra RELATIVO al reloj: se fija antes de importarlo.
const AHORA = Date.parse('2026-09-24T17:00:00Z') // jueves 24/09, 12:00 en Lima
vi.useFakeTimers()
vi.setSystemTime(AHORA)
const demo = await import('./demo')
vi.useRealTimers()
const HOY = '2026-09-24'
const mundo: MundoDemo = { miembros: demo.EQUIPO_DEMO, leads: demo.LEADS_DEMO, actividades: demo.ACTIVIDADES_DEMO, tareas: demo.TAREAS_DEMO, ahora: AHORA }
const pulso = (dia: string, m = mundo) => v.parse(PulsoGerenciaSchema, pulsoGerenciaDesdeDemo(m, dia))
const grupo = (p: PulsoGerencia, clave: string) => p.equipos.find((e) => e.clave === clave)!
const ids = (p: PulsoGerencia, clave: string) => grupo(p, clave).personas.map((x) => x.analista_id)

describe('Pulso de gerencia en demo', () => {
  it.each([
    [HOY, 'hoy en curso'], ['2026-09-23', 'ayer'], ['2026-09-20', 'domingo con una llamada'],
    ['2026-09-19', 'sábado sin gestiones'], ['2026-09-17', 'día pasado con un supervisor que gestionó'],
    ['2026-06-01', 'día sin actividad ni referencia'], [desplazarDia(HOY, -365), 'límite de 365 días'],
  ])('%s (%s) pasa el contrato del servidor con todos los equipos y «fuera»', (dia) => {
    const p = pulso(dia)
    expect(p.dia).toBe(dia)
    expect(p.equipos.map((e) => e.clave).toSorted()).toEqual(['d-sup1', 'd-sup2', 'fuera'])
    expect(p.actual.analistas_activos).toBe(3)
  })
  it('hoy: cifras del día repartidas por supervisor, pendientes actuales y SLA en observación', () => {
    const p = pulso(HOY)
    expect(p.actual).toEqual({ llamadas: 4, utiles: 4, contestadas: 2, tasa_contacto: 50, leads_unicos: 4, llamadas_por_lead: 1,
      citas_agendadas: 0, analistas_activos: 3, con_actividad: 3, sin_actividad: 0 })
    // La tarea vencida de ANALISTA UNO pone primero a su equipo; «fuera» vacío, pero presente.
    expect(p.equipos.map((e) => e.clave)).toEqual(['d-sup1', 'd-sup2', 'fuera'])
    expect(ids(p, 'd-sup1')).toEqual(['d-v1', 'd-v2'])
    expect(ids(p, 'd-sup2')).toEqual(['d-v3'])
    expect(ids(p, 'fuera')).toEqual([])
    expect(grupo(p, 'd-sup1').metricas).toMatchObject({ llamadas: 3, contestadas: 2, tasa_contacto: 66.7, leads_unicos: 3 })
    expect(grupo(p, 'd-sup1').tareas_vencidas).toBe(1)
    expect(p.vencidas_global).toBe(1)
    expect(p.modo_sla).toBe('observacion')
    expect(p.equipos.every((e) => e.primer_intento_vencido === null)).toBe(true)
    expect(p.ayer).toEqual({ dia: '2026-09-23', metricas: expect.objectContaining({ llamadas: 1, contestadas: 1, con_actividad: 2 }) })
  })
  it('la referencia son las 7 jornadas MÁS RECIENTES con actividad; los días vacíos no cuentan', () => {
    const { referencia } = pulso(HOY)
    // El 19/09 sólo tuvo cambios de etapa: no es jornada con gestiones.
    expect(referencia.dias).toEqual(['2026-09-23', '2026-09-22', '2026-09-21', '2026-09-20', '2026-09-18', '2026-09-17', '2026-09-16'])
    expect(referencia).toMatchObject({ busqueda_desde: '2025-09-24', cantidad: 7 })
    expect(referencia.media.llamadas).toBeGreaterThan(0)
  })
  it('día pasado: quien gestiona fuera del organigrama comercial cae en «fuera» como autor, no como analista', () => {
    const p = pulso('2026-09-17')
    expect(grupo(p, 'fuera').personas).toEqual([expect.objectContaining({
      analista_id: 'd-sup2', nombre_completo: 'SUPERVISOR DOS', activo: false, gestiones: 1, llamadas: 0 })])
    expect(grupo(p, 'fuera').metricas.analistas_activos).toBe(0)
    expect(p.actual).toMatchObject({ llamadas: 1, contestadas: 1, con_actividad: 2, sin_actividad: 1 })
  })
  it('día sin actividad: ceros sin tasa, referencia vacía y pendientes que siguen siendo los de ahora', () => {
    const p = pulso('2026-06-01')
    expect(p.actual).toMatchObject({ llamadas: 0, tasa_contacto: null, leads_unicos: 0, llamadas_por_lead: null, con_actividad: 0, sin_actividad: 3 })
    expect(p.referencia).toMatchObject({ dias: [], cantidad: 0, dias_con_tasa: 0 })
    expect(Object.values(p.referencia.media).every((n) => n === null)).toBe(true)
    expect(p.vencidas_global).toBe(1)
  })
  it('fuera de rango (futuro o más de 365 días) falla como el servidor, sin cifras', () => {
    for (const dia of ['2026-09-25', desplazarDia(HOY, -366), '2026-02-30']) {
      expect(() => pulsoGerenciaDesdeDemo(mundo, dia)).toThrow(RangeError)
      expect(() => detalleOperacionDesdeDemo(mundo, dia)).toThrow(RangeError)
      expect(() => habitosGerenciaDesdeDemo(mundo, dia, 7)).toThrow(RangeError)
    }
  })
})

describe('Detalle de gerencia en demo', () => {
  it('cubre a TODOS los analistas activos (los supervisores no cuelgan de gerencia en el demo)', () => {
    const detalle = v.parse(DiaEquipoSchema, detalleOperacionDesdeDemo(mundo, HOY))
    expect(detalle.supervisor_id).toBeNull()
    expect(detalle.equipo.map((f) => f.analista_id).toSorted()).toEqual(['d-v1', 'd-v2', 'd-v3'])
    // Desde gerencia el recorrido por organigrama no llega a nadie: por eso `null` = operación completa.
    expect(diaEquipoDesdeDemo('d-ger', demo.EQUIPO_DEMO, demo.LEADS_DEMO, demo.ACTIVIDADES_DEMO, demo.TAREAS_DEMO, AHORA, HOY).equipo).toEqual([])
  })
  it('el supervisor demo conserva exactamente su equipo', () => {
    const d = diaEquipoDesdeDemo('d-sup1', demo.EQUIPO_DEMO, demo.LEADS_DEMO, demo.ACTIVIDADES_DEMO, demo.TAREAS_DEMO, AHORA, HOY)
    expect(d.supervisor_id).toBe('d-sup1')
    expect(d.equipo.map((f) => f.analista_id)).toEqual(['d-v1', 'd-v2'])
  })
  it.each([HOY, '2026-09-17', '2026-09-20'])('%s: cada analista del pulso cuadra con su fila del detalle', (dia) => {
    const p = pulso(dia)
    const detalle = detalleOperacionDesdeDemo(mundo, dia)
    for (const persona of p.equipos.flatMap((e) => e.personas).filter((x) => x.activo)) {
      const fila = detalle.equipo.find((f) => f.analista_id === persona.analista_id)!
      expect(persona).toMatchObject({ llamadas: fila.marcador.llamadas, utiles: fila.marcador.utiles, contestadas: fila.marcador.contestadas,
        citas_agendadas: fila.marcador.citas_agendadas, gestiones: fila.gestiones_hoy, leads_tocados: fila.marcador.leads_tocados })
    }
    for (const e of p.equipos.filter((x) => x.clave !== 'fuera')) {
      expect(e.tareas_vencidas).toBe(detalle.equipo.filter((f) => e.personas.some((x) => x.analista_id === f.analista_id))
        .reduce((n, f) => n + f.tareas_vencidas, 0))
    }
  })
})

describe('Hábitos de gerencia en demo', () => {
  it.each([HOY, '2026-09-17', '2026-06-01', desplazarDia(HOY, -365)].flatMap((dia) => ([7, 14, 30] as const).map((dias) => [dia, dias] as const)))(
    'hasta %s, %i días: pasa el contrato con una fila por analista y jornada', (hasta, dias) => {
      const h = v.parse(HabitosGerenciaSchema, habitosGerenciaDesdeDemo(mundo, hasta, dias))
      expect(h).toMatchObject({ hasta, dias_solicitados: dias })
      expect(h.personas.map((p) => p.analista_id).toSorted()).toEqual(['d-v1', 'd-v2', 'd-v3'])
      expect(h.personas.every((p) => p.dias.length === h.dias_incluidos)).toBe(true)
    })
  it('recorta el período al histórico disponible (365 días desde hoy)', () => {
    const h = habitosGerenciaDesdeDemo(mundo, desplazarDia(HOY, -360), 30)
    expect(h).toMatchObject({ desde: desplazarDia(HOY, -365), dias_incluidos: 6 })
  })
  it('jornada en curso con su mayor hueco, domingo no laborable y contacto del equipo', () => {
    const h = habitosGerenciaDesdeDemo(mundo, HOY, 7)
    const uno = h.personas.find((p) => p.analista_id === 'd-v1')!
    const hoy = uno.dias.at(-1)!
    // 09:36 y 11:02:24 dentro de la jornada; se observa hasta ahora (12:00).
    expect(hoy.jornada).toMatchObject({ estado: 'en_curso', silencio_inicio_minutos: 36, silencio_final_minutos: 57.6,
      hueco: expect.objectContaining({ minutos: 86.4 }) })
    const domingo = uno.dias.find((d) => d.dia === '2026-09-20')!
    expect(domingo).toMatchObject({ llamadas: 1, jornada: { estado: 'no_laborable', hueco: null } })
    expect(uno.resumen).toEqual({ llamadas: 4, utiles: 4, contestadas: 3, tasa_contacto: 75 })
    expect(uno.equipo).toEqual({ utiles: 6, contestadas: 4, tasa_contacto: 66.7 })
    // Sin cortes en el espejo: no se evalúa ni se inventa cumplimiento.
    expect(hoy.cortes.estado).toBe('desactivados')
    expect(uno.cumplimiento.evaluables).toBe(0)
    expect(h.operacion).toEqual({ llamadas: 8, utiles: 8, contestadas: 5, tasa_contacto: 62.5 })
  })
  it('la distribución diaria usa sólo días con muestra suficiente, con percentiles interpolados', () => {
    const llamadas = (dia: string, contestadas: number, total: number) => Array.from({ length: total }, (_, i): Actividad => ({
      id: `${dia}-${i}`, lead_id: `l-${i}`, tipo: i < contestadas ? 'llamada_realizada' : 'llamada_no_contestada', detalle: null,
      autor_nombre: 'ANALISTA UNO', creado_en: `${dia}T${String(10 + i).padStart(2, '0')}:00:00-05:00`,
    }))
    const actividades = [...llamadas('2026-09-21', 1, 5), ...llamadas('2026-09-22', 2, 5), ...llamadas('2026-09-23', 4, 5), ...llamadas('2026-09-24', 1, 2)]
    const h = habitosGerenciaDesdeDemo({ ...mundo, actividades }, HOY, 7)
    const uno = h.personas.find((p) => p.analista_id === 'd-v1')!
    expect(uno.distribucion_contacto).toEqual({ dias_validos: 3, minimo: 20, p25: 30, mediana: 40, p75: 60, maximo: 80 })
    expect(v.safeParse(HabitosGerenciaSchema, h).success).toBe(true)
  })
})

describe('Organigrama del espejo', () => {
  const miembros: Miembro[] = [
    { perfil_id: 's1', nombre_completo: 'SUPERVISORA', rol_crm: 'supervisor', activo: true },
    { perfil_id: 's2', nombre_completo: 'PUENTE REVOCADO', rol_crm: 'supervisor', supervisor_id: 's1', activo: false },
    { perfil_id: 's3', nombre_completo: 'ANIDADO', rol_crm: 'supervisor', supervisor_id: 's1', activo: true },
    { perfil_id: 'a1', nombre_completo: 'BAJO PUENTE', rol_crm: 'vendedor', supervisor_id: 's2', activo: true },
    { perfil_id: 'a2', nombre_completo: 'DEL ANIDADO', rol_crm: 'vendedor', supervisor_id: 's3', activo: true },
    { perfil_id: 'a3', nombre_completo: 'EN CICLO', rol_crm: 'vendedor', supervisor_id: 'x1', activo: true },
    { perfil_id: 'x1', nombre_completo: 'CICLO', rol_crm: 'vendedor', supervisor_id: 'a3', activo: false },
    { perfil_id: 'a4', nombre_completo: 'SIN JEFE', rol_crm: 'vendedor', activo: true },
  ]
  const lead = (id: string, vendedor_id: string | null): Lead => ({ ...demo.LEADS_DEMO[0]!, id, vendedor_id, etapa: 'contactado' })
  const act = (id: string, autor_nombre: string, tipo: Actividad['tipo'], local?: true): Actividad => ({
    id, lead_id: 'la', tipo, detalle: null, autor_nombre, creado_en: '2026-09-24T10:00:00-05:00', ...(local ? { local } : {}) })
  const cita = (id: string, lead_id: string, vendedor_id: string | null): Tarea => ({ id, lead_id, vendedor_id, tipo: 'reunion', titulo: 'Cita',
    vence_en: '2026-09-30T15:00:00Z', estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: '2026-09-24T11:00:00-05:00' })
  const m: MundoDemo = {
    miembros, leads: [lead('la', 'a1'), lead('lp', null)], ahora: AHORA,
    actividades: [act('c1', 'BAJO PUENTE', 'llamada_realizada'), act('c2', 'SUPERVISORA', 'llamada_no_contestada'),
      act('n1', 'QUIEN SEA', 'nota'), act('c3', 'BAJO PUENTE', 'llamada_realizada', true), act('e1', 'SUPERVISORA', 'cambio_etapa')],
    tareas: [cita('t1', 'la', 'a1'), cita('t2', 'lp', null)],
  }
  it('asigna el supervisor ACTIVO más cercano, sube por puentes revocados y manda ciclos y huérfanos a «fuera»', () => {
    const p = pulso(HOY, m)
    expect(p.equipos.map((e) => e.clave).toSorted()).toEqual(['fuera', 's1', 's3'])
    expect(ids(p, 's1')).toEqual(['a1'])
    expect(ids(p, 's3')).toEqual(['a2'])
    expect(grupo(p, 'fuera').personas.filter((x) => x.activo).map((x) => x.analista_id)).toEqual(['a3', 'a4'])
  })
  it('autores fuera del organigrama y citas sin analista van a «fuera» sin duplicar lo del detalle', () => {
    const p = pulso(HOY, m)
    const fuera = grupo(p, 'fuera').personas
    // La supervisora que llamó es autora, no analista; el cambio de etapa no es gestión.
    expect(fuera.find((x) => x.analista_id === 's1')).toMatchObject({ activo: false, llamadas: 1, gestiones: 1 })
    // Autor desconocido y cita de un lead sin analista: «sin autor».
    expect(fuera.find((x) => x.analista_id === null)).toMatchObject({ nombre_completo: null, gestiones: 1, citas_agendadas: 1 })
    // La optimista local no cuenta; la cita del lead de a1 es de a1, como en el detalle.
    expect(grupo(p, 's1').personas[0]).toMatchObject({ analista_id: 'a1', llamadas: 1, citas_agendadas: 1 })
    // El mismo lead llamado por dos autores es UN lead distinto de la operación.
    expect(p.actual).toMatchObject({ llamadas: 2, leads_unicos: 1, llamadas_por_lead: 2, citas_agendadas: 2 })
  })
})
