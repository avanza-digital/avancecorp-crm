// El conteo del botón «GESTIÓN DIARIA»: en sesión real cuenta la MISMA cola que
// abre el destino (ordenada con `ordenarColaDiaria`) y el marcador del día; en
// demo, el espejo. Sin día de HOY entero y sin cola llegada sin error ni
// recorte NO hay cifras (nunca ceros que se lean como «al día»). Y la visita
// del día en localStorage.
import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { diaAnalistaDesdeDemo, type DiaAnalista, type ItemColaDia, type SenalCartera, type TareaClienteDemo } from '@/lib/gestion-diaria-analista'
import type { ColaDiaPagina } from '@/lib/sla-operacion'
import type { Yo } from '@/lib/tipos'

const dobles = vi.hoisted(() => ({
  // Miércoles 2026-09-23, 10:00 en Lima (15:00Z).
  ahora: Date.parse('2026-09-23T15:00:00Z'),
  yo: { id: 'a1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: false, puede_contratar: true } as Yo | null,
  dia: null as DiaAnalista | null,
  diaCargando: false,
  cola: { data: undefined as ColaDiaPagina | undefined, error: null as unknown, isPending: false },
  colaArgs: [] as unknown[],
  // Tareas del ámbito (el store): el espejo DEMO saca de aquí las de clientes.
  tareas: [] as TareaClienteDemo[],
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => dobles.ahora }))
vi.mock('./gestion-diaria-queries', () => ({
  useDiaAnalista: () => ({ dia: dobles.dia, cargando: dobles.diaCargando, enVuelo: false, error: null, recargar: async () => {} }),
}))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ tareas: dobles.tareas }) }))
vi.mock('./sla-operacion-queries', () => ({
  useColaDiaPagina: (...args: unknown[]) => {
    dobles.colaArgs = args
    return dobles.cola
  },
}))
const { claveVisita, conteoDelDia, conteoDelDiaDemo, useConteoGestionDiaria } = await import('./use-conteo-gestion-diaria')
const { FILTROS_COLA_DIA, LIMITE_COLA_DIA } = await import('@/lib/gestion-diaria-analista')

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

/** Ítem de lead de la cola v3 con lo que `ordenarColaDiaria` lee (mismo doble que en lib/gestion-diaria-analista.test.ts). */
const item = (id: string, bucket: string, referencia: string | null): ItemColaDia => ({
  clave: `lead:${id}`, sujeto: { tipo: 'lead', id, nombre: `LEAD ${id}` },
  lead_id: id, bucket, severidad: bucket === 'tarea_vencida' ? 'critica' : 'media', prioridad: 0, referencia_en: referencia, tarea_id: null,
  lead: { id, nombre_completo: `LEAD ${id}`, etapa: 'contactado', analista_id: 'a1', analista_nombre: 'ANALISTA UNO' },
} as unknown as ItemColaDia)

/** Tarea de CLIENTE de la cola v3. */
const cliente = (tarea: string, bucket: 'tarea_vencida' | 'tarea_hoy', vence: string, inversionista = `inv-${tarea}`): ItemColaDia => ({
  clave: `tarea:${tarea}`, tarea_id: tarea, lead_id: null, lead: null, estado: null, bucket,
  severidad: bucket === 'tarea_vencida' ? 'critica' : 'media', prioridad: bucket === 'tarea_vencida' ? 20 : 30, referencia_en: vence,
  senales: { pendientes: bucket === 'tarea_vencida', tareas_vencidas: bucket === 'tarea_vencida', primera_atencion: false,
    seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
  sujeto: { tipo: 'cliente', perfil_id: null, inversionista_id: inversionista, nombre: `CLIENTE ${inversionista}` },
})

/**
 * Un día con la forma del servidor (`crm.gestion_diaria_analista_fn`, versión 1),
 * el mismo contrato que valida `DiaAnalistaSchema`.
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
    senal('nuevo-sin-intento'),
    senal('vencida-hoy', { etapa: 'contactado', llamadas_ciclo: 2, proxima_tarea_en: '2026-09-23T13:00:00Z', proxima_tarea_tipo: 'llamada' }),
    senal('vencida-ayer', { etapa: 'contactado', llamadas_ciclo: 1, proxima_tarea_en: '2026-09-22T20:00:00Z', proxima_tarea_tipo: 'llamada' }),
    senal('hoy', { etapa: 'contactado', llamadas_ciclo: 1, proxima_tarea_en: '2026-09-23T20:00:00Z', proxima_tarea_tipo: 'reunion' }),
    senal('manana', { etapa: 'contactado', llamadas_ciclo: 1, proxima_tarea_en: '2026-09-24T15:00:00Z', proxima_tarea_tipo: 'llamada' }),
    // Doce días sin conversación → lo añade `ordenarColaDiaria` como PENDIENTE (grupo «Sin conversación»).
    senal('abandonado', { etapa: 'contactado', llamadas_ciclo: 3, sin_conversacion: true, dias_sin_conversacion: 12 }),
    // Vencida en la cola Y sin conversación → cuenta UNA vez, como vencida.
    senal('vencida-y-abandonado', {
      etapa: 'propuesta_enviada', llamadas_ciclo: 2, proxima_tarea_en: '2026-09-21T15:00:00Z', proxima_tarea_tipo: 'llamada',
      sin_conversacion: true, dias_sin_conversacion: 9,
    }),
    senal('tranquilo', { etapa: 'contactado', llamadas_ciclo: 2, ultima_conversacion_en: '2026-09-22T18:00:00Z' }),
  ],
  cartera_truncada: false,
  descartados: [],
}

/** La página de la cola v3 tal como la sirve `cola_accion_v3_fn` con `senal: 'todas'` (lo que `ordenarColaDiaria` no lee va abreviado). */
const PAGINA: ColaDiaPagina = {
  version: 3, modo: 'activo', control_revision: 1, calculado_en: '2026-09-23T15:00:00Z',
  filtros: { senal: 'todas', etapa: null, analista_id: null }, limite: 200, total_items: 6, hay_mas: false, cursor_siguiente: null,
  rango: { desde: 1, hasta: 6 },
  // `totales` cuenta SEÑALES de la cola, no los grupos del día: no se usan para las cifras.
  totales: { pendientes: 5, primera_atencion: 1, tareas_vencidas: 3, seguimientos_pendientes: 1, revisiones: 0, datos_incompletos: 0, por_repartir: 0, clientes: 0 },
  items: [
    item('nuevo-sin-intento', 'primera_atencion', '2026-09-23T14:00:00Z'), // → PENDIENTE
    item('vencida-hoy', 'tarea_vencida', '2026-09-23T13:00:00Z'), // → VENCIDA
    item('vencida-ayer', 'tarea_vencida', '2026-09-22T20:00:00Z'), // → VENCIDA
    item('hoy', 'tarea_hoy', '2026-09-23T20:00:00Z'), // → PENDIENTE
    item('vencida-y-abandonado', 'tarea_vencida', '2026-09-21T15:00:00Z'), // → VENCIDA (una sola vez)
    item('seguimiento', 'seguimiento', '2026-09-23T12:00:00Z'), // bucket que no es del día → no cuenta
  ],
} as unknown as ColaDiaPagina

describe('conteoDelDia (sesión real: cola del servidor + marcador)', () => {
  it('hechas = marcador.llamadas; vencidas = filas tarea_vencida; pendientes = sin primer intento + hoy + sin conversación, cada lead una vez', () => {
    expect(conteoDelDia(DIA_REAL, PAGINA)).toEqual({ hechas: 9, vencidas: 3, pendientes: 3 })
  })

  it('las tareas de CLIENTES cuentan como en la pantalla: una por tarea, vencida o pendiente según su bucket', () => {
    const conClientes = { items: [...PAGINA.items,
      cliente('c1', 'tarea_vencida', '2026-09-22T15:00:00Z'), // → VENCIDA
      cliente('c2', 'tarea_hoy', '2026-09-23T21:00:00Z', 'inv-rosa'), // → PENDIENTE
      cliente('c3', 'tarea_hoy', '2026-09-23T22:00:00Z', 'inv-rosa'), // → PENDIENTE (misma persona, otra tarea)
    ] }
    expect(conteoDelDia(DIA_REAL, conClientes)).toEqual({ hechas: 9, vencidas: 4, pendientes: 5 })
  })

  it('con la cola vacía solo quedan los sin conversación de la cartera', () => {
    expect(conteoDelDia(DIA_REAL, { items: [] })).toEqual({ hechas: 9, vencidas: 0, pendientes: 2 })
  })
})

describe('conteoDelDiaDemo (espejo sobre la cartera)', () => {
  it('deriva vencidas y pendientes de proxima_tarea_en, y con el reloj lo de hoy pasa a vencido al dar la hora', () => {
    expect(conteoDelDiaDemo(DIA_REAL, dobles.ahora)).toEqual({ hechas: 9, vencidas: 3, pendientes: 3 })
    const tarde = Date.parse('2026-09-23T20:30:00Z') // 15:30 Lima
    expect(conteoDelDiaDemo(DIA_REAL, tarde)).toEqual({ hechas: 9, vencidas: 4, pendientes: 2 })
  })
})

describe('useConteoGestionDiaria', () => {
  const almacenOriginal = Object.getOwnPropertyDescriptor(window, 'localStorage')

  beforeEach(() => {
    dobles.yo = { id: 'a1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: false, puede_contratar: true }
    dobles.dia = DIA_REAL
    dobles.diaCargando = false
    dobles.cola = { data: PAGINA, error: null, isPending: false }
    dobles.colaArgs = []
    dobles.tareas = []
    window.localStorage.clear()
  })

  afterEach(() => {
    if (almacenOriginal) Object.defineProperty(window, 'localStorage', almacenOriginal)
  })

  it('en sesión real pide la MISMA cola que el destino (filtros, sin cursor, LIMITE_COLA_DIA, habilitada) y cuenta con ella', () => {
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(dobles.colaArgs).toEqual([{ senal: 'todas', etapa: null, analista_id: null }, null, 200, true])
    expect(FILTROS_COLA_DIA).toEqual({ senal: 'todas', etapa: null, analista_id: null })
    // El máximo que admite la v3: con clientes detrás de los leads, 100 los dejaba fuera antes.
    expect(LIMITE_COLA_DIA).toBe(200)
    expect(result.current).toMatchObject({ hechas: 9, vencidas: 3, pendientes: 3, disponible: true, cargando: false, yaVisitoHoy: false })
  })

  it('mientras la cola carga no hay cifras (cargando: true, disponible: false)', () => {
    dobles.cola = { data: undefined, error: null, isPending: true }
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false, cargando: true })
  })

  it('si la cola cayó no hay cifras, aunque TanStack conserve una foto anterior', () => {
    dobles.cola = { data: PAGINA, error: new Error('cola caída'), isPending: false }
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false, cargando: false })
  })

  it('si la página quedó corta (hay_mas) no se inventan cifras con `totales`: sin cifras', () => {
    dobles.cola = { data: { ...PAGINA, hay_mas: true, total_items: 140 }, error: null, isPending: false }
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false })
  })

  it('sin día (cargando o RPC caído) no hay cifras: el botón no debe decir «al día»', () => {
    dobles.dia = null
    dobles.diaCargando = true
    const cargando = renderHook(() => useConteoGestionDiaria())
    expect(cargando.result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false, cargando: true })

    dobles.diaCargando = false // el RPC cayó: el día es fail-closed
    const caido = renderHook(() => useConteoGestionDiaria())
    expect(caido.result.current).toMatchObject({ hechas: 0, vencidas: 0, pendientes: 0, disponible: false, cargando: false })
  })

  it('un día que no es el de HOY en Lima (reloj cruzó la medianoche antes del refetch) no da cifras', () => {
    dobles.dia = { ...DIA_REAL, dia: '2026-09-22' }
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current).toMatchObject({ disponible: false, hechas: 0, vencidas: 0, pendientes: 0 })
  })

  it('con la cartera recortada por el servidor (cartera_truncada) no da cifras', () => {
    dobles.dia = { ...DIA_REAL, cartera_truncada: true }
    const { result } = renderHook(() => useConteoGestionDiaria())
    expect(result.current).toMatchObject({ disponible: false, hechas: 0, vencidas: 0, pendientes: 0 })
  })

  it('en demo la cola va deshabilitada y el espejo del ámbito ya trae cifras: una vencida, cosas de hoy y las llamadas del día', () => {
    dobles.yo = { id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: true, puede_contratar: true }
    dobles.cola = { data: undefined, error: null, isPending: true } // consulta deshabilitada: TanStack la deja «pending»
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
    expect(dobles.colaArgs[3]).toBe(false)
    // hechas: las dos llamadas (el WhatsApp no cuenta) · vencida: l2 · pendientes: l15 sin primer intento y l17 con tarea hoy.
    expect(result.current).toMatchObject({ hechas: 2, vencidas: 1, pendientes: 2, disponible: true, cargando: false })

    // Con tareas de CLIENTES en el ámbito demo: la vencida suma a vencidas, la de hoy a pendientes y la de mañana no entra.
    const base = { lead_id: null, estado: 'pendiente', activo: true, vendedor_id: 'd-v1', titulo: 'Llamar a ROSA' }
    dobles.tareas = [
      { ...base, id: 'c-venc', inversionista_id: 'inv-1', vence_en: iso(dobles.ahora - HORA_MS) },
      { ...base, id: 'c-hoy', inversionista_id: 'inv-1', vence_en: iso(dobles.ahora + HORA_MS) },
      { ...base, id: 'c-manana', inversionista_id: 'inv-1', vence_en: iso(dobles.ahora + DIA_MS) },
      { ...base, id: 'c-ajena', inversionista_id: 'inv-2', vence_en: iso(dobles.ahora - HORA_MS), vendedor_id: 'd-v2' },
    ]
    const conClientes = renderHook(() => useConteoGestionDiaria())
    expect(conClientes.result.current).toMatchObject({ hechas: 2, vencidas: 2, pendientes: 3, disponible: true })
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
