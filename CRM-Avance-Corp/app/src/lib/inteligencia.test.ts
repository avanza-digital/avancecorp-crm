import { describe, expect, it } from 'vitest'
import {
  colaDe,
  colorMeta,
  comparativaEquipos,
  conversionGlobal,
  conversionPorOrigen,
  diasSinActividad,
  embudo,
  estancados,
  indexarUltimaActividad,
  metricasPorVendedor,
  sinProximaAccion,
} from './inteligencia'
import type { Actividad, Lead, Miembro } from './tipos'

const DIA_MS = 86_400_000
const AHORA = Date.UTC(2026, 6, 10, 12)
const haceDias = (dias: number) => new Date(AHORA - dias * DIA_MS).toISOString()

const baseLead: Lead = {
  id: 'lead-base',
  nombre_completo: 'CLIENTE PRUEBA',
  telefono: '+51999999999',
  etapa: 'nuevo',
  origen: 'referido',
  monto_estimado: 10_000,
  moneda: 'PEN',
  vendedor_id: 'v1',
  creado_en: haceDias(1),
  activo: true,
}

const lead = (cambios: Partial<Lead>): Lead => ({ ...baseLead, ...cambios })

const actividad = (
  leadId: string,
  dias: number,
  cambios: Partial<Actividad> = {},
): Actividad => ({
  id: `act-${leadId}-${dias}`,
  lead_id: leadId,
  tipo: 'nota',
  detalle: null,
  autor_nombre: 'VENDEDOR',
  creado_en: haceDias(dias),
  ...cambios,
})

const miembro = (perfilId: string, cambios: Partial<Miembro> = {}): Miembro => ({
  perfil_id: perfilId,
  nombre_completo: perfilId.toUpperCase(),
  rol_crm: 'vendedor',
  activo: true,
  ...cambios,
})

describe('tiempo e índices de actividad', () => {
  it('indexa la última actividad por lead aunque llegue desordenada', () => {
    const anterior = actividad('l1', 4)
    const reciente = actividad('l1', 1)
    const ajena = actividad('l2', 0.5)

    expect(indexarUltimaActividad([reciente, anterior, ajena])).toEqual(
      new Map([
        ['l1', reciente],
        ['l2', ajena],
      ]),
    )
    expect(indexarUltimaActividad([ajena]).get('sin-actividad')).toBeUndefined()
  })

  it('calcula desde la actividad o creación y nunca devuelve días negativos', () => {
    const l1 = lead({ id: 'l1', creado_en: haceDias(5) })
    expect(diasSinActividad(l1, [actividad('l1', 2.5)], AHORA)).toBe(2.5)
    expect(diasSinActividad(l1, [], AHORA)).toBe(5)
    expect(diasSinActividad(lead({ creado_en: 'invalida' }), [], AHORA)).toBe(0)
    expect(diasSinActividad(lead({ creado_en: new Date(AHORA + DIA_MS).toISOString() }), [], AHORA)).toBe(0)
  })
})

describe('señales comerciales', () => {
  it.each([
    [39.9, '#dc2626'],
    [40, '#d97706'],
    [74.9, '#d97706'],
    [75, '#2563eb'],
    [120, '#2563eb'],
  ] as const)('asigna el semáforo de meta para %s%%', (pct, color) => {
    expect(colorMeta(pct)).toBe(color)
  })

  it('clasifica una sola acción por lead y ordena por severidad y antigüedad', () => {
    const leads = [
      lead({ id: 'sin-responder', creado_en: haceDias(2) }),
      lead({ id: 'por-repartir', etapa: 'contactado', vendedor_id: null, creado_en: haceDias(1) }),
      lead({ id: 'propuesta', etapa: 'propuesta_enviada', creado_en: haceDias(8) }),
      lead({ id: 'seguimiento', etapa: 'contactado', creado_en: haceDias(7) }),
      lead({ id: 'fresco', etapa: 'contactado', creado_en: haceDias(2) }),
      lead({ id: 'convertido', etapa: 'convertido', creado_en: haceDias(20) }),
      lead({ id: 'inactivo', activo: false, creado_en: haceDias(20) }),
    ]
    const acts = [
      actividad('propuesta', 6),
      actividad('seguimiento', 4),
      actividad('fresco', 1),
    ]

    const cola = colaDe(leads, acts, AHORA)

    expect(cola.map((item) => [item.lead.id, item.bucket, item.sev])).toEqual([
      ['sin-responder', 'sin_responder', 'critica'],
      ['por-repartir', 'por_repartir', 'critica'],
      ['propuesta', 'propuesta_sin_respuesta', 'media'],
      ['seguimiento', 'seguimiento', 'baja'],
    ])
    expect(cola[0]?.motivo).toContain('hace 2 días')
    expect(cola[1]?.motivo).toContain('hace 1 día')
  })

  it('usa “hace horas” antes de completar el primer día', () => {
    const cola = colaDe([lead({ id: 'horas', creado_en: haceDias(0.25) })], [], AHORA)
    expect(cola[0]).toMatchObject({ bucket: 'sin_responder', sev: 'media' })
    expect(cola[0]?.motivo).toContain('hace horas')
  })
})

describe('agregaciones comerciales', () => {
  it('separa capital por moneda y calcula conversión y abandono por vendedor', () => {
    const vendedores = [miembro('v2'), miembro('v1')]
    const leads = [
      lead({ id: 'pen', vendedor_id: 'v1', monto_estimado: 100, creado_en: haceDias(3) }),
      lead({ id: 'usd', vendedor_id: 'v1', monto_estimado: 50, moneda: 'USD', creado_en: haceDias(4) }),
      lead({ id: 'ganado', vendedor_id: 'v1', etapa: 'convertido', monto_estimado: 999 }),
      lead({ id: 'perdido', vendedor_id: 'v1', etapa: 'descartado' }),
      lead({ id: 'inactivo', vendedor_id: 'v1', activo: false, monto_estimado: 10_000 }),
      lead({ id: 'sin-vendedor', vendedor_id: null, monto_estimado: 10_000 }),
    ]

    const filas = metricasPorVendedor(vendedores, leads, [actividad('pen', 2)], AHORA)

    expect(filas[0]).toMatchObject({
      m: { perfil_id: 'v1' },
      activos: 2,
      capitalPEN: 100,
      capitalUSD: 50,
      convertidos: 1,
      conversion: 25,
      sinTocar: 1,
      diasSinActividadMax: 4,
    })
    expect(filas[1]).toMatchObject({
      m: { perfil_id: 'v2' },
      activos: 0,
      capitalPEN: 0,
      capitalUSD: 0,
      conversion: 0,
    })
  })

  it('mantiene las cuatro etapas del embudo y excluye terminales e inactivos', () => {
    const filas = embudo([
      lead({ id: 'n1' }),
      lead({ id: 'n2' }),
      lead({ id: 'c1', etapa: 'contactado' }),
      lead({ id: 'p1', etapa: 'propuesta_enviada' }),
      lead({ id: 'ganado', etapa: 'convertido' }),
      lead({ id: 'inactivo', etapa: 'reunion_agendada', activo: false }),
    ])

    expect(filas).toEqual([
      { etapa: 'nuevo', n: 2, pctDelTotal: 50 },
      { etapa: 'contactado', n: 1, pctDelTotal: 25 },
      { etapa: 'reunion_agendada', n: 0, pctDelTotal: 0 },
      { etapa: 'propuesta_enviada', n: 1, pctDelTotal: 25 },
    ])
    expect(embudo([]).every((fila) => fila.pctDelTotal === 0)).toBe(true)
  })

  it('ordena conversión por origen y omite datos inactivos o fuera del catálogo', () => {
    const filas = conversionPorOrigen([
      lead({ id: 'r1', origen: 'referido', etapa: 'convertido' }),
      lead({ id: 'r2', origen: 'referido', etapa: 'nuevo' }),
      lead({ id: 'land1', origen: 'landing', etapa: 'convertido' }),
      lead({ id: 'land2', origen: 'landing', etapa: 'nuevo' }),
      lead({ id: 'form1', origen: 'formulario', etapa: 'convertido' }),
      lead({ id: 'web1', origen: 'web', etapa: 'convertido' }),
      lead({ id: 'camp1', origen: 'campania', etapa: 'nuevo' }),
      lead({ id: 'wa1', origen: 'whatsapp', etapa: 'convertido' }),
      lead({ id: 'off', origen: 'oficina', etapa: 'convertido', activo: false }),
      // Simula un dato corrupto que burló la frontera (el union se borra en runtime)
      lead({ id: 'x1', origen: 'fuera-catalogo' as Lead['origen'], etapa: 'convertido' }),
    ])

    expect(filas).toEqual([
      { origen: 'formulario', label: 'FORMULARIO', total: 1, convertidos: 1, pct: 100 },
      { origen: 'web', label: 'Web', total: 1, convertidos: 1, pct: 100 },
      { origen: 'whatsapp', label: 'WhatsApp', total: 1, convertidos: 1, pct: 100 },
      { origen: 'referido', label: 'Referido', total: 2, convertidos: 1, pct: 50 },
      { origen: 'landing', label: 'LANDING', total: 2, convertidos: 1, pct: 50 },
      { origen: 'campania', label: 'Campaña', total: 1, convertidos: 0, pct: 0 },
    ])
  })

  it('calcula la conversión global sobre activos CON vendedor (parkeados fuera de la base)', () => {
    // Misma base que comparativaEquipos y que los tableros Hoy de
    // supervisor/gerencia: los parkeados no cuentan (nadie los trabaja) y los
    // descartados SÍ (histórico del vendedor); los inactivos nunca entran.
    const filas = conversionGlobal([
      lead({ id: 'ganado', etapa: 'convertido' }),
      lead({ id: 'abierto' }),
      lead({ id: 'perdido', etapa: 'descartado' }),
      lead({ id: 'parkeado', vendedor_id: null, etapa: 'convertido' }),
      lead({ id: 'inactivo', activo: false, etapa: 'convertido' }),
    ])

    expect(filas).toEqual({ convertidos: 1, base: 3, pct: 33 })
    expect(conversionGlobal([])).toEqual({ convertidos: 0, base: 0, pct: 0 })
  })

  it('detecta estancados abiertos usando la referencia más reciente', () => {
    const leads = [
      lead({ id: 'diez', etapa: 'contactado', creado_en: haceDias(10) }),
      lead({ id: 'ocho', etapa: 'propuesta_enviada', creado_en: haceDias(12) }),
      lead({ id: 'seis', etapa: 'contactado', creado_en: haceDias(6) }),
      lead({ id: 'terminal', etapa: 'descartado', creado_en: haceDias(30) }),
    ]

    expect(estancados(leads, [actividad('ocho', 8)], 7, AHORA).map((fila) => fila.lead.id)).toEqual([
      'diez',
      'ocho',
    ])
  })

  it('compara equipos con su jerarquía, parqueados y monedas separadas', () => {
    const equipo = [
      miembro('s1', { rol_crm: 'supervisor' }),
      miembro('s2', { rol_crm: 'supervisor' }),
      miembro('v1', { supervisor_id: 's1' }),
      miembro('v2', { supervisor_id: 's1', activo: false }),
    ]
    const leads = [
      lead({ id: 'propio-s1', vendedor_id: 's1', monto_estimado: 50 }),
      lead({ id: 'pen-v1', vendedor_id: 'v1', monto_estimado: 100 }),
      lead({ id: 'usd-v1', vendedor_id: 'v1', monto_estimado: 20, moneda: 'USD' }),
      lead({ id: 'ganado-v1', vendedor_id: 'v1', etapa: 'convertido' }),
      lead({ id: 'vendedor-inactivo', vendedor_id: 'v2', monto_estimado: 1_000 }),
      lead({ id: 'park-s1', vendedor_id: null, asignado_supervisor_id: 's1', monto_estimado: 5_000 }),
      lead({ id: 'park-s2', vendedor_id: null, asignado_supervisor_id: 's2', monto_estimado: 5_000 }),
    ]

    const filas = comparativaEquipos(equipo, leads, [])

    expect(filas[0]).toMatchObject({
      supervisor: { perfil_id: 's1' },
      vendedores: 1,
      activos: 3,
      capitalPEN: 150,
      capitalUSD: 20,
      convertidos: 1,
      conversion: 25,
      parkeados: 1,
    })
    expect(filas[1]).toMatchObject({
      supervisor: { perfil_id: 's2' },
      vendedores: 0,
      activos: 0,
      capitalPEN: 0,
      capitalUSD: 0,
      convertidos: 0,
      conversion: 0,
      parkeados: 1,
    })
  })
})

describe('Fase B — la cola y estancados respetan el PLAN (tareas pendientes)', () => {
  const base = () => [
    lead({ id: 'con-plan', etapa: 'contactado' }),
    lead({ id: 'sin-plan', etapa: 'contactado' }),
    lead({ id: 'nuevo-frio', etapa: 'nuevo' }),
    lead({ id: 'parkeado', vendedor_id: null }),
  ]

  it('lead con tarea pendiente sale del fallback por inactividad; asignación y speed-to-lead se mantienen', () => {
    const ahora = Date.now()
    const conTarea = new Set(['con-plan', 'nuevo-frio', 'parkeado'])
    const cola = colaDe(base(), [], ahora, undefined, conTarea)
    const buckets = new Map(cola.map((i) => [i.lead.id, i.bucket]))
    expect(buckets.has('con-plan')).toBe(false) // tiene plan → su cola es la agenda
    expect(buckets.get('sin-plan')).toBe('seguimiento') // fallback para quien no tiene
    expect(buckets.get('nuevo-frio')).toBe('sin_responder') // speed-to-lead NUNCA se apaga
    expect(buckets.get('parkeado')).toBe('por_repartir') // la tenencia tampoco
  })

  it('estancados excluye leads con tarea futura (el riesgo deja de pelearse con el plan)', () => {
    const ahora = Date.now()
    const alertas = estancados(base(), [], 5, ahora, undefined, new Set(['con-plan']))
    const ids = alertas.map((a) => a.lead.id)
    expect(ids).not.toContain('con-plan')
    expect(ids).toContain('sin-plan')
  })

  it('sinProximaAccion: abiertos CON vendedor y sin plan, capital PEN primero desc', () => {
    const leads = [
      lead({ id: 'usd-grande', moneda: 'USD', monto_estimado: 90_000 }),
      lead({ id: 'pen-chico', moneda: 'PEN', monto_estimado: 10_000 }),
      lead({ id: 'pen-grande', moneda: 'PEN', monto_estimado: 50_000 }),
      lead({ id: 'con-plan', moneda: 'PEN', monto_estimado: 99_000 }),
      lead({ id: 'parkeado', vendedor_id: null }),
      lead({ id: 'cerrado', etapa: 'convertido' }),
    ]
    const ids = sinProximaAccion(leads, new Set(['con-plan'])).map((l) => l.id)
    // PEN desc primero (nunca mezclado con USD), USD después; sin parkeados ni cerrados.
    expect(ids).toEqual(['pen-grande', 'pen-chico', 'usd-grande'])
  })
})
