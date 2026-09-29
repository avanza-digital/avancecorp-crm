// El día del analista (Fase 3): el ORDEN del día, la presentación de la tasa y
// el espejo demo. Lo que se prueba aquí es lo que la pantalla NO puede
// equivocarse: quién va primero, qué se dice de cada fila y que el % nunca
// aparezca sin su conteo.
import { describe, expect, it } from 'vitest'
import {
  agruparDiaria, barrasPorHora, cuandoLimaDe, detalleDeFila, diaAnalistaDesdeDemo, filasDelFiltro, filasDiariasDemo, finDelDiaLima,
  horaLimaDe, llamadasFueraDeFranja, ordenarColaDiaria, pestanasDiarias, resumenMarcador, siguienteTrasGuardar, textoTasa, tiempoDeFila,
  type FilaDiaria, type FilaLead, type ItemColaDia, type SenalCartera,
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

const item = (id: string, bucket: string, referencia: string | null, extra: Record<string, unknown> = {}): ItemColaDia => ({
  clave: `lead:${id}`, sujeto: { tipo: 'lead', id, nombre: `LEAD ${id}` },
  lead_id: id, bucket, severidad: 'media', prioridad: 0, referencia_en: referencia, tarea_id: null,
  lead: { id, nombre_completo: `LEAD ${id}`, etapa: 'nuevo', analista_id: 'a1', analista_nombre: 'ANALISTA UNO' },
  ...extra,
} as unknown as ItemColaDia)

/** Una tarea de CLIENTE de la cola v3 (sin lead, sin estado, sin teléfono). */
const cliente = (tarea: string, bucket: 'tarea_vencida' | 'tarea_hoy', vence: string, sujeto: { perfil_id?: string; inversionista_id?: string; nombre?: string } = {}): ItemColaDia => ({
  clave: `tarea:${tarea}`, tarea_id: tarea, lead_id: null, lead: null, estado: null, bucket,
  severidad: bucket === 'tarea_vencida' ? 'critica' : 'media', prioridad: bucket === 'tarea_vencida' ? 20 : 30, referencia_en: vence,
  senales: { pendientes: bucket === 'tarea_vencida', tareas_vencidas: bucket === 'tarea_vencida', primera_atencion: false,
    seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
  sujeto: { tipo: 'cliente', perfil_id: sujeto.perfil_id ?? null, inversionista_id: sujeto.perfil_id ? null : sujeto.inversionista_id ?? `inv-${tarea}`, nombre: sujeto.nombre ?? `CLIENTE ${tarea}` },
})

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

  it('las tareas de CLIENTES entran en «Vencidas» u «Hoy», una fila por tarea y ordenadas con los leads', () => {
    const cola = [
      item('nuevo', 'primera_atencion', '2026-09-20T14:00:00Z'),
      item('lv', 'tarea_vencida', '2026-09-19T15:00:00Z'),
      cliente('c-venc', 'tarea_vencida', '2026-09-18T15:00:00Z', { inversionista_id: 'inv-1', nombre: 'ROSA CLIENTE' }),
      cliente('c-hoy-1', 'tarea_hoy', '2026-09-20T22:00:00Z', { inversionista_id: 'inv-1', nombre: 'ROSA CLIENTE' }),
      cliente('c-hoy-2', 'tarea_hoy', '2026-09-20T20:00:00Z', { perfil_id: 'p-1', nombre: 'SOLO PORTAL' }),
    ]
    const filas = ordenarColaDiaria(cola, [])
    expect(filas.map((f) => `${f.grupo}:${f.clave}`)).toEqual([
      'primera_atencion:lead:nuevo', 'tarea_vencida:tarea:c-venc', 'tarea_vencida:lead:lv', 'tarea_hoy:tarea:c-hoy-2', 'tarea_hoy:tarea:c-hoy-1',
    ])
    // La misma persona con dos tareas = dos filas, cada una con su tarea.
    const rosa = filas.filter((f) => f.nombre_completo === 'ROSA CLIENTE')
    expect(rosa.map((f) => f.tarea_id)).toEqual(['c-venc', 'c-hoy-1'])
    expect(rosa.every((f) => f.tipo === 'cliente' && f.lead_id === null && f.etapa === null && f.senal === null && f.inversionista_id === 'inv-1')).toBe(true)
    const portal = filas.find((f) => f.clave === 'tarea:c-hoy-2')
    expect(portal).toMatchObject({ tipo: 'cliente', perfil_id: 'p-1', inversionista_id: null, severidad: 'media' })
  })

  it('una clave repetida entra UNA vez (el servidor no las repite, pero la pantalla no se fía)', () => {
    const filas = ordenarColaDiaria([cliente('t1', 'tarea_hoy', '2026-09-20T20:00:00Z'), cliente('t1', 'tarea_hoy', '2026-09-20T20:00:00Z')], [])
    expect(filas.map((f) => f.clave)).toEqual(['tarea:t1'])
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
  const fila = (grupo: 'primera_atencion' | 'sin_conversacion' | 'tarea_hoy', s: SenalCartera | null): FilaDiaria =>
    ({ tipo: 'lead', clave: 'lead:l', lead_id: 'l', nombre_completo: 'L', etapa: 'nuevo', grupo, referencia_en: null, tarea_id: null, severidad: 'media' as const, senal: s })

  it('dice lo que se sabe y nunca inventa', () => {
    expect(detalleDeFila(fila('primera_atencion', null), 7)).toBe('Ningún intento todavía')
    expect(detalleDeFila(fila('tarea_hoy', null), 7)).toBe('Sin señales cargadas')
    expect(detalleDeFila(fila('tarea_hoy', senal('l', { llamadas_ciclo: 4, intentos_sin_respuesta: 3 })), 7))
      .toBe('3 intentos sin respuesta · 4 llamadas en el ciclo')
    expect(detalleDeFila(fila('tarea_hoy', senal('l', { llamadas_ciclo: 1 })), 7)).toBe('1 llamada en el ciclo · ya conversaron')
    expect(detalleDeFila(fila('sin_conversacion', senal('l', { dias_sin_conversacion: 12, sin_conversacion: true })), 7))
      .toBe('Sin conversación hace 12 días (el límite es 7)')
  })

  it('una tarea de cliente dice que es de la cartera, sin inventar señales de lead', () => {
    const [f] = ordenarColaDiaria([cliente('t1', 'tarea_vencida', '2026-09-19T15:00:00Z')], [])
    expect(detalleDeFila(f!, 7)).toBe('Cliente de tu cartera · gestión agendada')
  })

  it('el número errado manda sobre todo lo demás: es lo que hay que resolver', () => {
    expect(detalleDeFila(fila('tarea_hoy', senal('l', { numero_errado_detalle: 'Contesta otra persona', llamadas_ciclo: 2 })), 7))
      .toBe('Número errado: Contesta otra persona')
  })
})

describe('tiempoDeFila', () => {
  const AHORA = Date.parse('2026-09-20T18:00:00Z')
  const fila = (extra: Partial<FilaLead> = {}): FilaDiaria =>
    ({ tipo: 'lead', clave: 'lead:l', lead_id: 'l', nombre_completo: 'L', etapa: 'nuevo', grupo: 'primera_atencion', referencia_en: null,
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
    expect(filasDiariasDemo(d.cartera, ahora, dia).map((f) => `${f.grupo}:${f.clave}`))
      .toEqual(['primera_atencion:lead:l1', 'tarea_vencida:lead:l3'])
  })

  it('los CLIENTES del demo siguen la regla del servidor: del analista, pendientes, vencidas o de hoy', () => {
    const d = diaAnalistaDesdeDemo('a1', leads, actividades, tareas, ahora, dia)
    const base = { lead_id: null, estado: 'pendiente', activo: true, vendedor_id: 'a1' }
    const deClientes = [
      { ...base, id: 'cv', inversionista_id: 'inv-1', titulo: 'Llamar a ROSA DÍAZ', vence_en: '2026-09-19T10:00:00Z' },
      { ...base, id: 'ch1', inversionista_id: 'inv-1', titulo: 'Llamar a ROSA DÍAZ', vence_en: '2026-09-20T20:00:00Z' },
      { ...base, id: 'ch2', perfil_id: 'p-1', titulo: 'Escribir a LUIS PORTAL', vence_en: '2026-09-21T04:59:00Z' }, // 23:59 Lima
      { ...base, id: 'manana', inversionista_id: 'inv-2', titulo: 'Llamar a MAÑANA', vence_en: '2026-09-21T05:00:00Z' }, // 00:00 Lima del 21
      { ...base, id: 'ajena', inversionista_id: 'inv-3', titulo: 'Llamar a AJENA', vence_en: '2026-09-19T15:00:00Z', vendedor_id: 'a2' },
      { ...base, id: 'hecha', inversionista_id: 'inv-4', titulo: 'Llamar a HECHA', vence_en: '2026-09-19T15:00:00Z', estado: 'completada' },
      { ...base, id: 'inactiva', inversionista_id: 'inv-5', titulo: 'Llamar a INACTIVA', vence_en: '2026-09-19T15:00:00Z', activo: false },
      { ...base, id: 'de-lead', lead_id: 'l2', titulo: 'Llamar a LEAD', vence_en: '2026-09-19T15:00:00Z' },
      { ...base, id: 'dos-sujetos', perfil_id: 'p-2', inversionista_id: 'inv-6', titulo: 'Llamar a ROTA', vence_en: '2026-09-19T15:00:00Z' },
    ]
    const filas = filasDiariasDemo(d.cartera, ahora, dia, deClientes, 'a1')
    expect(filas.map((f) => `${f.grupo}:${f.clave}`)).toEqual([
      'primera_atencion:lead:l1', 'tarea_vencida:tarea:cv', 'tarea_vencida:lead:l3', 'tarea_hoy:tarea:ch1', 'tarea_hoy:tarea:ch2',
    ])
    expect(filas.filter((f) => f.tipo === 'cliente').map((f) => f.nombre_completo)).toEqual(['ROSA DÍAZ', 'ROSA DÍAZ', 'LUIS PORTAL'])
  })
})

describe('finDelDiaLima', () => {
  it('es la próxima medianoche de Lima (05:00 UTC), también a última hora del día', () => {
    expect(new Date(finDelDiaLima(Date.parse('2026-09-20T18:00:00Z'))).toISOString()).toBe('2026-09-21T05:00:00.000Z')
    // 23:59 de Lima del 20 = 04:59Z del 21: sigue siendo el día 20.
    expect(new Date(finDelDiaLima(Date.parse('2026-09-21T04:59:00Z'))).toISOString()).toBe('2026-09-21T05:00:00.000Z')
    // 00:00 de Lima del 21: ya es el día siguiente.
    expect(new Date(finDelDiaLima(Date.parse('2026-09-21T05:00:00Z'))).toISOString()).toBe('2026-09-22T05:00:00.000Z')
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
  const L = (id: string) => `lead:${id}`

  it('«Todo» es la cola entera en el orden de los grupos; un grupo, solo lo suyo', () => {
    expect(ids(filasDelFiltro(grupos, 'todo'))).toEqual(['n1', 'n2', 'v1', 's1'])
    expect(ids(filasDelFiltro(grupos, 'tarea_vencida'))).toEqual(['v1'])
    expect(filasDelFiltro(grupos, 'tarea_hoy')).toEqual([])
  })

  it('al guardar pasa a la que venía DETRÁS en la lista que se miraba', () => {
    expect(siguienteTrasGuardar(grupos, 'todo', L('n1'))).toEqual({ filtro: 'todo', clave: L('n2') })
    expect(siguienteTrasGuardar(grupos, 'todo', L('v1'))).toEqual({ filtro: 'todo', clave: L('s1') })
  })

  it('si el guardado era el último, pasa al nuevo último de esa lista', () => {
    expect(siguienteTrasGuardar(grupos, 'todo', L('s1'))).toEqual({ filtro: 'todo', clave: L('v1') })
    expect(siguienteTrasGuardar(grupos, 'primera_atencion', L('n2'))).toEqual({ filtro: 'primera_atencion', clave: L('n1') })
  })

  it('si el grupo se queda vacío, sigue con la cola entera desde el principio', () => {
    expect(siguienteTrasGuardar(grupos, 'tarea_vencida', L('v1'))).toEqual({ filtro: 'todo', clave: L('n1') })
  })

  it('un guardado que no estaba en la lista mirada deja «Ahora» en la primera de esa lista', () => {
    expect(siguienteTrasGuardar(grupos, 'tarea_vencida', L('n1'))).toEqual({ filtro: 'tarea_vencida', clave: L('v1') })
  })

  it('con dos tareas de un mismo cliente, guardar una pasa a la OTRA, no salta a la persona', () => {
    const conCliente = pestanasDiarias(ordenarColaDiaria([
      cliente('t1', 'tarea_vencida', '2026-09-18T10:00:00Z', { inversionista_id: 'inv-1' }),
      cliente('t2', 'tarea_vencida', '2026-09-19T10:00:00Z', { inversionista_id: 'inv-1' }),
      item('v9', 'tarea_vencida', '2026-09-19T11:00:00Z'),
    ], []))
    expect(siguienteTrasGuardar(conCliente, 'tarea_vencida', 'tarea:t1')).toEqual({ filtro: 'tarea_vencida', clave: 'tarea:t2' })
    expect(siguienteTrasGuardar(conCliente, 'tarea_vencida', 'tarea:t2')).toEqual({ filtro: 'tarea_vencida', clave: 'lead:v9' })
  })

  it('con la cola vacía no inventa a nadie', () => {
    expect(siguienteTrasGuardar(pestanasDiarias([]), 'todo', 'lead:x')).toEqual({ filtro: 'todo', clave: null })
  })
})
