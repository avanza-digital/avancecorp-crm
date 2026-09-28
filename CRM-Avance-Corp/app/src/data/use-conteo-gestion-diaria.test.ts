// El conteo del botón «GESTIÓN DIARIA»: qué campo del día alimenta cada cifra
// (sobre un día con la forma REAL del servidor), que sin día no se lea «al
// día», que el demo muestre algo, y la visita del día en localStorage.
import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { diaAnalistaDesdeDemo, type DiaAnalista, type SenalCartera } from '@/lib/gestion-diaria-analista'
import type { Yo } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({
  // Miércoles 2026-09-23, 10:00 en Lima (15:00Z).
  ahora: Date.parse('2026-09-23T15:00:00Z'),
  yo: { id: 'a1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: false, puede_contratar: true } as Yo | null,
  dia: null as DiaAnalista | null,
  cargando: false,
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => dobles.ahora }))
vi.mock('./gestion-diaria-queries', () => ({
  useDiaAnalista: () => ({ dia: dobles.dia, cargando: dobles.cargando, enVuelo: false, error: null, recargar: async () => {} }),
}))
const { claveVisita, conteoDelDia, useConteoGestionDiaria } = await import('./use-conteo-gestion-diaria')

const HORA_MS = 3_600_000
const DIA_MS = 24 * HORA_MS
const iso = (ms: number) => new Date(ms).toISOString()

const senal = (id: string, extra: Partial<SenalCartera> = {}): SenalCartera => ({
  lead_id: id, nombre_completo: `LEAD ${id}`, etapa: 'nuevo', tenencia_desde: '2026-09-22T12:00:00Z',
  ciclo_desde: '2026-09-22T12:00:00Z', llamadas_ciclo: 0, intentos_sin_respuesta: 0,
  ultima_llamada_en: null, ultima_llamada_tipo: null, ultima_llamada_resultado: null,
  ultima_conversacion_en: null, dias_sin_conversacion: 0, sin_conversacion: false,
  numero_errado_detalle: null, numero_errado_en: null, proxima_tarea_en: null, proxima_tarea_tipo: null,
  ...extra,
})

/**
 * Un día con la forma del servidor (`crm.gestion_diaria_analista_fn`, versión 1),
 * el mismo contrato que valida `DiaAnalistaSchema`. Cada señal de la cartera
 * documenta a qué cifra va (o por qué no va a ninguna).
 */
const DIA_REAL: DiaAnalista = {
  version: 1, generado_en: '2026-09-23T15:00:00Z', dia: '2026-09-23', zona: 'America/Lima', analista_id: 'a1',
  umbrales: { version: 1, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 },
  sin_conversacion_dias: 7,
  marcador: {
    // hechas = llamadas registradas hoy (contestadas + no contestadas).
    llamadas: 9, contestadas: 5, utiles: 8, tasa_contacto_pct: 63, nivel: 'bien', leads_tocados: 7,
    citas_agendadas: 1, primera_llamada_en: '2026-09-23T13:05:00Z', ultima_llamada_en: '2026-09-23T14:50:00Z',
    por_resultado: { volver_a_llamar: 3, no_contesto: 4, conversacion: 2 },
    por_hora: [{ hora: 8, llamadas: 4, contestadas: 2 }, { hora: 9, llamadas: 5, contestadas: 3 }],
  },
  // Los compromisos empiezan MAÑANA: no entran en el conteo de hoy.
  compromisos: [{
    tarea_id: 't-m', lead_id: 'manana', lead_nombre: 'LEAD manana', lead_etapa: 'contactado', tipo: 'llamada',
    titulo: 'Volver a llamar', vence_en: '2026-09-24T15:00:00Z', modalidad_reunion: null,
  }],
  compromisos_total: 1,
  cartera: [
    // Sin primer intento (etapa nuevo y 0 llamadas) → PENDIENTE.
    senal('nuevo-sin-intento'),
    // Nuevo pero ya llamado y sin tarea → no está en la cola.
    senal('nuevo-ya-llamado', { llamadas_ciclo: 1 }),
    // Tarea de hoy a las 08:00 Lima, ya pasó → VENCIDA.
    senal('vencida-hoy', { etapa: 'contactado', llamadas_ciclo: 2, proxima_tarea_en: '2026-09-23T13:00:00Z', proxima_tarea_tipo: 'llamada' }),
    // Tarea de ayer → VENCIDA.
    senal('vencida-ayer', { etapa: 'contactado', llamadas_ciclo: 1, proxima_tarea_en: '2026-09-22T20:00:00Z', proxima_tarea_tipo: 'llamada' }),
    // Tarea hoy a las 15:00 Lima, todavía no llega → PENDIENTE.
    senal('hoy', { etapa: 'contactado', llamadas_ciclo: 1, proxima_tarea_en: '2026-09-23T20:00:00Z', proxima_tarea_tipo: 'reunion' }),
    // Tarea mañana → no es de hoy.
    senal('manana', { etapa: 'contactado', llamadas_ciclo: 1, proxima_tarea_en: '2026-09-24T15:00:00Z', proxima_tarea_tipo: 'llamada' }),
    // Doce días sin conversación → PENDIENTE (grupo «Sin conversación»).
    senal('abandonado', { etapa: 'contactado', llamadas_ciclo: 3, sin_conversacion: true, dias_sin_conversacion: 12 }),
    // Vencida Y sin conversación → cuenta UNA vez, como vencida.
    senal('vencida-y-abandonado', {
      etapa: 'propuesta_enviada', llamadas_ciclo: 2, proxima_tarea_en: '2026-09-21T15:00:00Z', proxima_tarea_tipo: 'llamada',
      sin_conversacion: true, dias_sin_conversacion: 9,
    }),
    // Con conversación reciente y sin tarea → no está en la cola.
    senal('tranquilo', { etapa: 'contactado', llamadas_ciclo: 2, ultima_conversacion_en: '2026-09-22T18:00:00Z' }),
  ],
  cartera_truncada: false,
  descartados: [],
}

describe('conteoDelDia (función pura sobre el día del servidor)', () => {
  it('hechas = marcador.llamadas; vencidas = proxima_tarea_en pasada; pendientes = sin primer intento + hoy + sin conversación, cada lead una vez', () => {
    expect(conteoDelDia(DIA_REAL, dobles.ahora)).toEqual({ hechas: 9, vencidas: 3, pendientes: 3 })
  })

  it('ni los compromisos (desde mañana) ni los leads tranquilos cuentan', () => {
    const quieto = { ...DIA_REAL, cartera: DIA_REAL.cartera.filter((s) => s.lead_id === 'manana' || s.lead_id === 'tranquilo') }
    expect(conteoDelDia(quieto, dobles.ahora)).toEqual({ hechas: 9, vencidas: 0, pendientes: 0 })
  })

  it('con el reloj, lo acordado para hoy pasa a vencido al dar la hora', () => {
    const tarde = Date.parse('2026-09-23T20:30:00Z') // 15:30 Lima
    expect(conteoDelDia(DIA_REAL, tarde)).toEqual({ hechas: 9, vencidas: 4, pendientes: 2 })
  })
})

describe('useConteoGestionDiaria', () => {
  const almacenOriginal = Object.getOwnPropertyDescriptor(window, 'localStorage')

  beforeEach(() => {
    dobles.yo = { id: 'a1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: false, puede_contratar: true }
    dobles.dia = DIA_REAL
    dobles.cargando = false
    window.localStorage.clear()
  })

  afterEach(() => {
    if (almacenOriginal) Object.defineProperty(window, 'localStorage', almacenOriginal)
  })

  it('en sesión real cuenta el día del servidor y lo declara disponible', () => {
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current).toMatchObject({ hechas: 9, vencidas: 3, pendientes: 3, disponible: true, cargando: false, yaVisitoHoy: false })
  })

  it('sin día (cargando o RPC caído) las cifras van a 0 pero NO está disponible: el botón no debe decir «al día»', () => {
    dobles.dia = null
    dobles.cargando = true
    const cargando = renderHook(() => useConteoGestionDiaria())
    expect(cargando.result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false, cargando: true })

    dobles.cargando = false // el RPC cayó: el día es fail-closed
    const caido = renderHook(() => useConteoGestionDiaria())
    expect(caido.result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false, cargando: false })
  })

  it('en demo el espejo del ámbito ya trae cifras: una vencida, cosas de hoy y las llamadas del día', () => {
    dobles.yo = { id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: true, puede_contratar: true }
    const hace = (dias: number) => iso(dobles.ahora - dias * DIA_MS)
    const leads = [
      { id: 'l1', nombre_completo: 'JUAN PÉREZ', etapa: 'nuevo', activo: true, vendedor_id: 'd-v1', creado_en: hace(0.3) },
      { id: 'l2', nombre_completo: 'MARÍA LÓPEZ', etapa: 'contactado', activo: true, vendedor_id: 'd-v1', creado_en: hace(2) },
      { id: 'l15', nombre_completo: 'TERESA GONZALES', etapa: 'nuevo', activo: true, vendedor_id: 'd-v1', creado_en: hace(1.4) },
      { id: 'l17', nombre_completo: 'GLORIA NAVARRO', etapa: 'propuesta_enviada', activo: true, vendedor_id: 'd-v1', creado_en: hace(9) },
    ]
    const actividades = [
      { id: 'act44', lead_id: 'l2', tipo: 'llamada_realizada', creado_en: iso(dobles.ahora - HORA_MS) },
      { id: 'act45', lead_id: 'l1', tipo: 'llamada_no_contestada', creado_en: iso(dobles.ahora - 2 * HORA_MS) },
      { id: 'act46', lead_id: 'l2', tipo: 'whatsapp_enviado', creado_en: iso(dobles.ahora - HORA_MS / 2) },
    ]
    const tareas = [
      { id: 't-d1', lead_id: 'l2', tipo: 'whatsapp', titulo: 'WhatsApp', vence_en: iso(dobles.ahora - 3 * HORA_MS), estado: 'pendiente', activo: true, creado_en: hace(2) },
      { id: 't-d4', lead_id: 'l17', tipo: 'llamada', titulo: 'Responder propuesta', vence_en: iso(dobles.ahora + 2 * HORA_MS), estado: 'pendiente', activo: true, creado_en: hace(1) },
    ]
    dobles.dia = diaAnalistaDesdeDemo('d-v1', leads, actividades, tareas, dobles.ahora, '2026-09-23')
    const { result } = renderHook(() => useConteoGestionDiaria())
    // hechas: las dos llamadas (el WhatsApp no cuenta) · vencida: l2 · pendientes: l15 sin primer intento y l17 con tarea hoy.
    expect(result.current).toMatchObject({ hechas: 2, vencidas: 1, pendientes: 2, disponible: true, cargando: false })
  })

  it('marcarVisita escribe crm:gd-visita:<id> con el día Lima y yaVisitoHoy pasa a true', () => {
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current.yaVisitoHoy).toBe(false)
    act(() => result.current.marcarVisita())
    expect(window.localStorage.getItem(claveVisita('a1'))).toBe('2026-09-23')
    expect(result.current.yaVisitoHoy).toBe(true)
  })

  it('lee la visita guardada: la de hoy calma el botón, la de ayer no, y la de otro analista tampoco', () => {
    window.localStorage.setItem(claveVisita('a1'), '2026-09-22')
    expect(renderHook(() => useConteoGestionDiaria()).result.current.yaVisitoHoy).toBe(false)
    window.localStorage.setItem(claveVisita('a1'), '2026-09-23')
    expect(renderHook(() => useConteoGestionDiaria()).result.current.yaVisitoHoy).toBe(true)
    window.localStorage.clear()
    window.localStorage.setItem(claveVisita('otro'), '2026-09-23')
    expect(renderHook(() => useConteoGestionDiaria()).result.current.yaVisitoHoy).toBe(false)
  })

  it('sin almacenamiento (leer y escribir revientan) no se rompe: insiste como la primera vez y la visita queda en memoria', () => {
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      value: {
        getItem() {
          throw new Error('bloqueado')
        },
        setItem() {
          throw new Error('bloqueado')
        },
      },
    })
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current.yaVisitoHoy).toBe(false)
    expect(() => act(() => result.current.marcarVisita())).not.toThrow()
    expect(result.current.yaVisitoHoy).toBe(true)
  })

  it('sin sesión no hay clave: ni lee ni escribe, y nada revienta', () => {
    dobles.yo = null
    window.localStorage.setItem('crm:gd-visita:null', '2026-09-23')
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current.yaVisitoHoy).toBe(false)
    act(() => result.current.marcarVisita())
    expect(window.localStorage.length).toBe(1)
  })
})
