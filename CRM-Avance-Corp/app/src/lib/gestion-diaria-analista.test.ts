// El día del analista (Fase 3): el ORDEN del día, la presentación de la tasa y
// el espejo demo. Lo que se prueba aquí es lo que la pantalla NO puede
// equivocarse: quién va primero, qué se dice de cada fila y que el % nunca
// aparezca sin su conteo.
import { describe, expect, it } from 'vitest'
import {
  agruparDiaria, barrasPorHora, cuandoLimaDe, detalleDeFila, diaAnalistaDesdeDemo, filasDelFiltro, filasDiariasDemo,
  horaLimaDe, llamadasFueraDeFranja, ordenarColaDiaria, pestanasDiarias, resumenMarcador, siguienteTrasGuardar, textoTasa, tiempoDeFila,
  type FilaDiaria, type ItemColaSla, type SenalCartera,
} from './gestion-diaria-analista'
import { seleccionarPrioridadesVendedor } from '@/screens/hoy/prioridades-vendedor'
import type { ItemCola } from './inteligencia'
import type { Lead } from './tipos'

const senal = (id: string, extra: Partial<SenalCartera> = {}): SenalCartera => ({
  lead_id: id, nombre_completo: `LEAD ${id}`, etapa: 'nuevo', tenencia_desde: '2026-09-18T12:00:00Z',
  ciclo_desde: '2026-09-18T12:00:00Z', llamadas_ciclo: 0, intentos_sin_respuesta: 0,
  ultima_llamada_en: null, ultima_llamada_tipo: null, ultima_llamada_resultado: null,
  ultima_conversacion_en: null, dias_sin_conversacion: 0, sin_conversacion: false,
  numero_errado_detalle: null, numero_errado_en: null, proxima_tarea_en: null, proxima_tarea_tipo: null,
  ...extra,
})

const item = (id: string, bucket: string, referencia: string | null, extra: Partial<ItemColaSla> = {}): ItemColaSla => ({
  lead_id: id, bucket, severidad: 'media', prioridad: 0, referencia_en: referencia, tarea_id: null,
  lead: { id, nombre_completo: `LEAD ${id}`, etapa: 'nuevo', analista_id: 'a1', analista_nombre: 'ANALISTA UNO' },
  ...extra,
} as unknown as ItemColaSla)

describe('ordenarColaDiaria', () => {
  it('pone el lead sin primer intento antes que lo vencido, lo de hoy y lo abandonado', () => {
    const cola = [
      item('hoy', 'tarea_hoy', '2026-09-20T22:00:00Z'),
      item('vencida', 'tarea_vencida', '2026-09-19T15:00:00Z'),
      item('nuevo', 'primera_atencion', '2026-09-20T14:00:00Z'),
    ]
    const cartera = [senal('abandonado', { sin_conversacion: true, dias_sin_conversacion: 12 })]
    expect(ordenarColaDiaria(cola, cartera).map((f) => f.lead_id)).toEqual(['nuevo', 'vencida', 'hoy', 'abandonado'])
  })

  it('dentro de un grupo manda lo más antiguo, y lo que no trae referencia va al final', () => {
    const cola = [
      item('b', 'tarea_vencida', '2026-09-19T15:00:00Z'),
      item('sin', 'tarea_vencida', null),
      item('a', 'tarea_vencida', '2026-09-18T15:00:00Z'),
    ]
    expect(ordenarColaDiaria(cola, []).map((f) => f.lead_id)).toEqual(['a', 'b', 'sin'])
  })

  it('un lead aparece UNA vez, en su grupo más urgente, y los buckets ajenos no entran', () => {
    const cola = [
      item('x', 'primera_atencion', '2026-09-20T14:00:00Z'),
      item('x', 'tarea_vencida', '2026-09-19T14:00:00Z'),
      item('y', 'seguimiento', '2026-09-19T14:00:00Z'),
      item('z', 'por_repartir', null),
    ]
    const filas = ordenarColaDiaria(cola, [senal('x', { sin_conversacion: true })])
    expect(filas.map((f) => f.lead_id)).toEqual(['x'])
    expect(filas[0]?.grupo).toBe('primera_atencion')
  })

  it('pega a cada fila sus señales cuando existen, y aguanta que falten', () => {
    const filas = ordenarColaDiaria([item('con', 'tarea_hoy', null), item('sin', 'tarea_hoy', null)], [senal('con', { llamadas_ciclo: 3 })])
    expect(filas.find((f) => f.lead_id === 'con')?.senal?.llamadas_ciclo).toBe(3)
    expect(filas.find((f) => f.lead_id === 'sin')?.senal).toBeNull()
  })

  it('agruparDiaria devuelve solo los grupos con filas, en el orden del día', () => {
    const filas = ordenarColaDiaria([item('v', 'tarea_vencida', null)], [senal('ab', { sin_conversacion: true })])
    expect(agruparDiaria(filas).map((g) => g.grupo)).toEqual(['tarea_vencida', 'sin_conversacion'])
  })
})

describe('el primer ítem de Hoy es el primero de Gestión Diaria', () => {
  it('el speed-to-lead manda en las dos pantallas', () => {
    const lead = (id: string): Lead => ({
      id, nombre_completo: `LEAD ${id}`, telefono: '+51999000111', etapa: 'nuevo', origen: 'landing',
      monto_estimado: 1000, moneda: 'PEN', creado_en: '2026-09-20T12:00:00Z', activo: true,
    } as Lead)
    // Hoy (cola v1): `sin_responder` gana a una crítica de otro bucket.
    const colaV1: ItemCola[] = [
      { lead: lead('otro'), bucket: 'propuesta_sin_respuesta', motivo: 'sin avance', sev: 'critica', dias: 9 },
      { lead: lead('nuevo'), bucket: 'sin_responder', motivo: 'sin primer intento', sev: 'critica', dias: 0 },
    ]
    expect(seleccionarPrioridadesVendedor([], colaV1)[0]?.leadId).toBe('nuevo')
    // Gestión Diaria (cola v2): su equivalente es `primera_atencion`.
    const colaV2 = [
      item('otro', 'tarea_vencida', '2026-09-18T15:00:00Z', { severidad: 'critica' }),
      item('nuevo', 'primera_atencion', '2026-09-20T14:00:00Z'),
    ]
    expect(ordenarColaDiaria(colaV2, [])[0]?.lead_id).toBe('nuevo')
  })
})

describe('presentación del marcador', () => {
  it('el % viaja SIEMPRE con su conteo, y sin llamadas útiles dice «—»', () => {
    expect(textoTasa({ tasa_contacto_pct: 60, utiles: 5 })).toBe('60 % · 5 llamadas')
    expect(textoTasa({ tasa_contacto_pct: 100, utiles: 1 })).toBe('100 % · 1 llamada')
    expect(textoTasa({ tasa_contacto_pct: null, utiles: 0 })).toBe('—')
  })

  it('las barras cubren 08–20 con el máximo para escalar, y lo de fuera se declara', () => {
    const por_hora = [{ hora: 7, llamadas: 2, contestadas: 1 }, { hora: 9, llamadas: 6, contestadas: 3 }, { hora: 21, llamadas: 1, contestadas: 0 }]
    const barras = barrasPorHora({ por_hora })
    expect(barras).toHaveLength(13)
    expect(barras[0]).toMatchObject({ hora: 8, llamadas: 0, maximo: 6 })
    expect(barras[1]).toMatchObject({ hora: 9, llamadas: 6, contestadas: 3 })
    expect(llamadasFueraDeFranja({ por_hora })).toBe(3)
  })

  it('las horas Lima salen de un instante UTC, y una fecha rota no revienta', () => {
    expect(horaLimaDe('2026-09-20T15:30:00Z')).toBe('10:30')
    expect(horaLimaDe(null)).toBe('—')
    expect(horaLimaDe('mañana')).toBe('—')
    expect(cuandoLimaDe('2026-09-21T15:00:00Z')).toContain('10:00')
    expect(cuandoLimaDe('nunca')).toBe('—')
  })
})

describe('detalleDeFila', () => {
  const fila = (grupo: 'primera_atencion' | 'sin_conversacion' | 'tarea_hoy', s: SenalCartera | null) =>
    ({ lead_id: 'l', nombre_completo: 'L', etapa: 'nuevo', grupo, referencia_en: null, tarea_id: null, severidad: 'media' as const, senal: s })

  it('dice lo que se sabe y nunca inventa', () => {
    expect(detalleDeFila(fila('primera_atencion', null), 7)).toBe('Ningún intento todavía')
    expect(detalleDeFila(fila('tarea_hoy', null), 7)).toBe('Sin señales cargadas')
    expect(detalleDeFila(fila('tarea_hoy', senal('l', { llamadas_ciclo: 4, intentos_sin_respuesta: 3 })), 7))
      .toBe('3 intentos sin respuesta · 4 llamadas en el ciclo')
    expect(detalleDeFila(fila('tarea_hoy', senal('l', { llamadas_ciclo: 1 })), 7)).toBe('1 llamada en el ciclo · ya conversaron')
    expect(detalleDeFila(fila('sin_conversacion', senal('l', { dias_sin_conversacion: 12, sin_conversacion: true })), 7))
      .toBe('Sin conversación hace 12 días (el límite es 7)')
  })

  it('el número errado manda sobre todo lo demás: es lo que hay que resolver', () => {
    expect(detalleDeFila(fila('tarea_hoy', senal('l', { numero_errado_detalle: 'Contesta otra persona', llamadas_ciclo: 2 })), 7))
      .toBe('Número errado: Contesta otra persona')
  })
})

describe('tiempoDeFila', () => {
  const AHORA = Date.parse('2026-09-20T18:00:00Z')
  const fila = (extra: Partial<FilaDiaria> = {}): FilaDiaria =>
    ({ lead_id: 'l', nombre_completo: 'L', etapa: 'nuevo', grupo: 'primera_atencion', referencia_en: null,
      tarea_id: null, severidad: 'media', senal: null, ...extra })

  it('dice el tiempo que QUEDA, nunca una hora suelta ni la sigla', () => {
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-20T19:20:00Z' }), AHORA)).toEqual({ texto: 'Quedan 1 h 20 min', vencido: false })
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-20T18:40:00Z' }), AHORA)).toEqual({ texto: 'Quedan 40 min', vencido: false })
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-20T20:00:00Z' }), AHORA)).toEqual({ texto: 'Quedan 2 h', vencido: false })
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-23T18:00:00Z' }), AHORA)).toEqual({ texto: 'Quedan 3 días', vencido: false })
  })

  it('lo vencido se dice con palabras, que es lo que pinta de rojo', () => {
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-20T17:15:00Z' }), AHORA)).toEqual({ texto: 'Se pasó hace 45 min', vencido: true })
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-19T15:00:00Z' }), AHORA)).toEqual({ texto: 'Se pasó hace 1 día', vencido: true })
  })

  it('por debajo del minuto no dice «0 min»', () => {
    expect(tiempoDeFila(fila({ referencia_en: '2026-09-20T18:00:30Z' }), AHORA).texto).toBe('Quedan menos de 1 min')
  })

  it('`sin_conversacion` no tiene hora límite: se mide en días', () => {
    const s = senal('l', { dias_sin_conversacion: 12, sin_conversacion: true })
    expect(tiempoDeFila(fila({ grupo: 'sin_conversacion', senal: s, referencia_en: '2026-09-08T18:00:00Z' }), AHORA))
      .toEqual({ texto: 'Sin conversación hace 12 días', vencido: false })
    expect(tiempoDeFila(fila({ grupo: 'sin_conversacion', senal: null }), AHORA).texto).toBe('Sin conversación')
  })

  it('sin hora legible no se inventa un reloj, pero la severidad SÍ se dice', () => {
    expect(tiempoDeFila(fila({ referencia_en: null }), AHORA)).toEqual({ texto: 'Sin hora límite', vencido: false })
    expect(tiempoDeFila(fila({ referencia_en: 'no-es-fecha', severidad: 'critica' }), AHORA))
      .toEqual({ texto: 'Crítica, sin hora', vencido: true })
  })
})

describe('resumenMarcador', () => {
  const umbrales = { version: 1 as const, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 }
  const marcador = (extra: Record<string, unknown> = {}) => ({
    llamadas: 9, contestadas: 5, utiles: 8, tasa_contacto_pct: 63, nivel: 'bien' as const, leads_tocados: 7,
    citas_agendadas: 1, primera_llamada_en: null, ultima_llamada_en: null, por_resultado: {}, por_hora: [],
    ...extra,
  })

  it('el % NUNCA va solo: lleva pegado el conteo de útiles sobre el que se calcula', () => {
    expect(resumenMarcador({ marcador: marcador(), umbrales })).toBe('9 llamadas · 63 % contacto (8 útiles) · 1 cita')
  })

  it('sin tasa dice por qué, y no un cero que no es cierto', () => {
    expect(resumenMarcador({ marcador: marcador({ llamadas: 1, utiles: 0, tasa_contacto_pct: null, nivel: null, citas_agendadas: 0 }), umbrales }))
      .toBe('1 llamada · sin tasa aún (desde 5 útiles) · 0 citas')
  })
})

describe('espejo demo', () => {
  const ahora = Date.parse('2026-09-20T18:00:00Z') // 13:00 Lima
  const dia = '2026-09-20'
  const leads = [
    { id: 'l1', nombre_completo: 'NUEVO SIN INTENTO', etapa: 'nuevo', activo: true, vendedor_id: 'a1', creado_en: '2026-09-20T12:00:00Z', tenencia_desde: '2026-09-20T12:00:00Z' },
    { id: 'l2', nombre_completo: 'CON CONVERSACION', etapa: 'contactado', activo: true, vendedor_id: 'a1', creado_en: '2026-09-01T12:00:00Z', tenencia_desde: '2026-09-01T12:00:00Z' },
    { id: 'l3', nombre_completo: 'ABANDONADO', etapa: 'contactado', activo: true, vendedor_id: 'a1', creado_en: '2026-09-01T12:00:00Z', tenencia_desde: '2026-09-01T12:00:00Z' },
    { id: 'ajeno', nombre_completo: 'DE OTRO', etapa: 'nuevo', activo: true, vendedor_id: 'a2', creado_en: '2026-09-20T12:00:00Z' },
  ]
  const actividades = [
    { id: 'a1', lead_id: 'l2', tipo: 'llamada_realizada', creado_en: '2026-09-20T16:00:00Z' },
    { id: 'a2', lead_id: 'l2', tipo: 'llamada_no_contestada', creado_en: '2026-09-20T17:00:00Z' },
    { id: 'a3', lead_id: 'l3', tipo: 'llamada_no_contestada', creado_en: '2026-09-05T16:00:00Z' },
  ]
  const tareas = [
    { id: 't1', lead_id: 'l2', tipo: 'llamada', titulo: 'Volver a llamar', vence_en: '2026-09-21T15:00:00Z', estado: 'pendiente', activo: true, creado_en: '2026-09-20T16:05:00Z' },
    { id: 't2', lead_id: 'l3', tipo: 'llamada', titulo: 'Vencida', vence_en: '2026-09-19T15:00:00Z', estado: 'pendiente', activo: true, creado_en: '2026-09-18T16:00:00Z' },
  ]

  it('arma el día con la misma forma del servidor y solo con los leads del analista', () => {
    const d = diaAnalistaDesdeDemo('a1', leads, actividades, tareas, ahora, dia)
    expect(d.version).toBe(1)
    expect(d.analista_id).toBe('a1')
    expect(d.marcador).toMatchObject({ llamadas: 2, contestadas: 1, utiles: 2, leads_tocados: 1, tasa_contacto_pct: 50 })
    // Menos del mínimo de llamadas útiles: sin chip (decisión #7 de Miguel).
    expect(d.marcador.nivel).toBeNull()
    expect(d.cartera.map((s) => s.lead_id).sort()).toEqual(['l1', 'l2', 'l3'])
    expect(d.cartera.find((s) => s.lead_id === 'l3')?.sin_conversacion).toBe(true)
    expect(d.cartera.find((s) => s.lead_id === 'l2')?.sin_conversacion).toBe(false)
    // El compromiso es el de MAÑANA; la tarea vencida vive en la cola, no aquí.
    expect(d.compromisos.map((c) => c.tarea_id)).toEqual(['t1'])
    expect(d.compromisos_total).toBe(1)
    expect(d.descartados).toEqual([])
  })

  it('las filas del demo respetan el orden del día', () => {
    const d = diaAnalistaDesdeDemo('a1', leads, actividades, tareas, ahora, dia)
    expect(filasDiariasDemo(d.cartera, ahora, dia).map((f) => `${f.grupo}:${f.lead_id}`))
      .toEqual(['primera_atencion:l1', 'tarea_vencida:l3'])
  })
})

describe('filtro «Todo» y el siguiente al guardar (27/09/2026)', () => {
  // Dos sin primer intento, una vencida, ninguna de hoy y una sin conversación.
  const filas = ordenarColaDiaria(
    [item('n1', 'primera_atencion', '2026-09-20T10:00:00Z'), item('n2', 'primera_atencion', '2026-09-20T11:00:00Z'), item('v1', 'tarea_vencida', '2026-09-19T10:00:00Z')],
    [senal('s1', { sin_conversacion: true, dias_sin_conversacion: 9 })],
  )
  const grupos = pestanasDiarias(filas)
  const ids = (fs: readonly FilaDiaria[]) => fs.map((f) => f.lead_id)

  it('«Todo» es la cola entera en el orden de los grupos; un grupo, solo lo suyo', () => {
    expect(ids(filasDelFiltro(grupos, 'todo'))).toEqual(['n1', 'n2', 'v1', 's1'])
    expect(ids(filasDelFiltro(grupos, 'tarea_vencida'))).toEqual(['v1'])
    expect(filasDelFiltro(grupos, 'tarea_hoy')).toEqual([])
  })

  it('al guardar pasa a la que venía DETRÁS en la lista que se miraba', () => {
    expect(siguienteTrasGuardar(grupos, 'todo', 'n1')).toEqual({ filtro: 'todo', lead_id: 'n2' })
    expect(siguienteTrasGuardar(grupos, 'todo', 'v1')).toEqual({ filtro: 'todo', lead_id: 's1' })
  })

  it('si el guardado era el último, pasa al nuevo último de esa lista', () => {
    expect(siguienteTrasGuardar(grupos, 'todo', 's1')).toEqual({ filtro: 'todo', lead_id: 'v1' })
    expect(siguienteTrasGuardar(grupos, 'primera_atencion', 'n2')).toEqual({ filtro: 'primera_atencion', lead_id: 'n1' })
  })

  it('si el grupo se queda vacío, sigue con la cola entera desde el principio', () => {
    expect(siguienteTrasGuardar(grupos, 'tarea_vencida', 'v1')).toEqual({ filtro: 'todo', lead_id: 'n1' })
  })

  it('un guardado que no estaba en la lista mirada deja «Ahora» en la primera de esa lista', () => {
    expect(siguienteTrasGuardar(grupos, 'tarea_vencida', 'n1')).toEqual({ filtro: 'tarea_vencida', lead_id: 'v1' })
  })

  it('con la cola vacía no inventa a nadie', () => {
    expect(siguienteTrasGuardar(pestanasDiarias([]), 'todo', 'x')).toEqual({ filtro: 'todo', lead_id: null })
  })
})
