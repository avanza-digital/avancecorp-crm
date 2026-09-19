// Contrato del avance automático de etapa (pedido de Miguel, 2026-07-25).
//
// Estas funciones son el ESPEJO de dos triggers de producción
// (trg_zz_actividades_avance_etapa y trg_zz_tareas_avance_etapa). Si un test de
// aquí cambia, la migración tiene que cambiar en la misma entrega — si no, el
// optimismo del store empieza a mentir hasta el resync.
//
// La mitad de los casos son NEGATIVOS a propósito: el riesgo real de un
// automatismo de embudo no es que se quede corto, es que afirme cosas que no
// pasaron. Un embudo que se infla solo es peor que uno que no se mueve.
import { describe, expect, it } from 'vitest'
import { avancePorContacto, avancePorEntrevista, avancePorReunion, retrocesoPorAnularReunion } from './avance-automatico'
import { senalesDesdeActividades } from './historial-lead'
import type { Etapa, Tarea, TipoActividad } from './tipos'

const AHORA = Date.parse('2026-07-25T15:00:00-05:00')

const lead = (etapa: Etapa, activo = true) => ({
  etapa,
  activo,
  vendedor_id: 'vend-1',
  asignado_supervisor_id: null,
})

const tarea = (parche: Partial<Tarea> = {}): Tarea => ({
  id: 't1',
  lead_id: 'l1',
  tipo: 'reunion',
  titulo: 'Reunión con Ana',
  vence_en: new Date(AHORA + 2 * 86_400_000).toISOString(),
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: new Date(AHORA).toISOString(),
  ...parche,
})

describe('avancePorContacto — la conversación sube el lead a Contactado', () => {
  it.each(['llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'])(
    'CONVERSACIÓN (%s) sobre un lead nuevo → contactado',
    (tipo) => {
      expect(avancePorContacto(lead('nuevo'), tipo)).toBe('contactado')
    },
  )

  it.each(['llamada_no_contestada', 'whatsapp_enviado', 'nota'])(
    'INTENTO (%s) no mueve nada — nadie habló con el cliente',
    (tipo) => {
      expect(avancePorContacto(lead('nuevo'), tipo)).toBeNull()
    },
  )

  it.each(['cambio_etapa', 'reasignacion', 'conversion'])(
    'lo que emite el SISTEMA (%s) jamás avanza — aquí se corta la recursión',
    (tipo) => {
      expect(avancePorContacto(lead('nuevo'), tipo)).toBeNull()
    },
  )

  it.each(['contactado', 'reunion_agendada', 'propuesta_enviada'] as const)(
    'desde %s no adivina etapas más adelante del embudo',
    (etapa) => {
      expect(avancePorContacto(lead(etapa), 'llamada_realizada')).toBeNull()
    },
  )

  it.each(['convertido', 'descartado'] as const)('un lead %s no revive por una llamada', (etapa) => {
    expect(avancePorContacto(lead(etapa), 'llamada_realizada')).toBeNull()
  })

  it('un lead inactivo (soft-delete) no avanza', () => {
    expect(avancePorContacto(lead('nuevo', false), 'llamada_realizada')).toBeNull()
  })
})

describe('avancePorReunion — agendar una reunión sube el lead', () => {
  it.each(['nuevo', 'contactado'] as const)('desde %s con contacto previo → reunion_agendada', (etapa) => {
    expect(avancePorReunion(lead(etapa), tarea(), true, AHORA)).toBe('reunion_agendada')
  })

  it('sin NINGÚN contacto registrado no se afirma que hay reunión con nadie', () => {
    expect(avancePorReunion(lead('contactado'), tarea(), false, AHORA)).toBeNull()
  })

  it('el rebote automático tras un no-show NO asciende: plantar al analista no es progreso', () => {
    // La guarda que más importa. `motor-siguiente` reagenda solo tras un
    // no-show; sin esto, el plantón sería la mentira más fácil de fabricar.
    expect(avancePorReunion(lead('contactado'), tarea({ reagendada_de: 't0' }), true, AHORA)).toBeNull()
  })

  it('agendar en el pasado no es agendar (seeds, backfills, imports)', () => {
    const vencida = tarea({ vence_en: new Date(AHORA - 86_400_000).toISOString() })
    expect(avancePorReunion(lead('contactado'), vencida, true, AHORA)).toBeNull()
  })

  it.each(['llamada', 'whatsapp', 'tarea'] as const)('una tarea de tipo %s no mueve el embudo', (tipo) => {
    expect(avancePorReunion(lead('contactado'), tarea({ tipo }), true, AHORA)).toBeNull()
  })

  it('una tarea que nace cerrada no mueve el embudo', () => {
    expect(avancePorReunion(lead('contactado'), tarea({ estado: 'completada' }), true, AHORA)).toBeNull()
  })

  it('desde propuesta_enviada NO retrocede (reiniciaría el SLA de 120h a 72h)', () => {
    expect(avancePorReunion(lead('propuesta_enviada'), tarea(), true, AHORA)).toBeNull()
  })

  it.each(['convertido', 'descartado'] as const)('un lead %s no se mueve', (etapa) => {
    expect(avancePorReunion(lead(etapa), tarea(), true, AHORA)).toBeNull()
  })

  it('una fecha corrupta degrada a "no avanzar", no a romper la agenda', () => {
    expect(avancePorReunion(lead('contactado'), tarea({ vence_en: 'no-es-fecha' }), true, AHORA)).toBeNull()
  })

  // Espejo del gate de ámbito que la auditoría (C1) obligó a añadir en el
  // servidor: un lead de la cola global no tiene reunión con nadie. Sin esta
  // rama el front pintaría un avance optimista que el trigger no hace.
  it('un lead de la COLA GLOBAL (sin analista y sin bandeja) no asciende', () => {
    const sinDuenio = { etapa: 'nuevo' as const, activo: true, vendedor_id: null, asignado_supervisor_id: null }
    expect(avancePorReunion(sinDuenio, tarea(), true, AHORA)).toBeNull()
  })

  it('un lead parkeado en la BANDEJA de un supervisor sí asciende (tiene dueño)', () => {
    const enBandeja = {
      etapa: 'contactado' as const,
      activo: true,
      vendedor_id: null,
      asignado_supervisor_id: 'sup-1',
    }
    expect(avancePorReunion(enBandeja, tarea(), true, AHORA)).toBe('reunion_agendada')
  })
})

describe('avancePorEntrevista — la cita ATENDIDA es la entrevista', () => {
  // Pedido de Miguel (2026-09-18) y espejo de `private.entrevista_registrar`.
  it.each(['nuevo', 'contactado', 'reunion_agendada'] as const)(
    'una cita atendida sobre un lead en %s → Entrevista realizada',
    (etapa) => {
      expect(avancePorEntrevista(lead(etapa))).toBe('propuesta_enviada')
    },
  )

  it('el que YA estaba en Entrevista realizada no se mueve (una 2a entrevista no es un avance)', () => {
    expect(avancePorEntrevista(lead('propuesta_enviada'))).toBeNull()
  })

  it.each(['convertido', 'descartado'] as const)('un lead %s no tiene etapa que subir', (etapa) => {
    expect(avancePorEntrevista(lead(etapa))).toBeNull()
  })

  it('un lead inactivo no avanza', () => {
    expect(avancePorEntrevista(lead('contactado', false))).toBeNull()
  })
})

describe('retrocesoPorAnularReunion — anular la última reunión devuelve la etapa', () => {
  // Pedido de Miguel (2026-07-26): «si se anula la reu y no se reagenda una en
  // ese mismo momento, debería bajar de etapa». Es la ÚNICA regla que baja, y
  // los casos negativos importan más que los positivos: bajar de etapa borra
  // progreso comercial, así que ante la duda no debe bajar.
  const reunion = (parche: Partial<Tarea> = {}) => tarea({ tipo: 'reunion', ...parche })
  // Desde la Fase 1 «sin topes» la función recibe las SEÑALES «alguna vez» del
  // historial (no una página de él); aquí se derivan de los tipos con el mismo
  // helper que usa el modo demo.
  const acts = (...tipos: TipoActividad[]) =>
    senalesDesdeActividades(tipos.map((tipo) => ({ tipo, creado_en: '2026-07-01T12:00:00.000Z' })))
  const CONTACTO = acts('llamada_realizada')

  it('EL CASO DE MIGUEL: anular la única reunión baja el lead a Contactado', () => {
    expect(
      retrocesoPorAnularReunion(lead('reunion_agendada'), reunion(), [reunion()], CONTACTO),
    ).toBe('contactado')
  })

  it('sin NINGÚN contacto real en el timeline baja hasta Nuevo, no a Contactado', () => {
    // Lead subido a mano desde el kanban sin trabajarlo: el retroceso no puede
    // inventar hacia abajo un contacto que no está en el historial.
    expect(retrocesoPorAnularReunion(lead('reunion_agendada'), reunion(), [reunion()], acts())).toBe('nuevo')
  })

  it('un intento sin respuesta ya cuenta como contacto (los 5 tipos, no los 3)', () => {
    expect(
      retrocesoPorAnularReunion(
        lead('reunion_agendada'), reunion(), [reunion()], acts('llamada_no_contestada'),
      ),
    ).toBe('contactado')
  })

  it('SI QUEDA OTRA REUNIÓN VIVA no baja: es el «y no se reagenda» del pedido', () => {
    const otra = reunion({ id: 't2' })
    expect(
      retrocesoPorAnularReunion(lead('reunion_agendada'), reunion(), [reunion(), otra], CONTACTO),
    ).toBeNull()
  })

  it('otra reunión ya CERRADA o inactiva no cuenta como reunión viva → sí baja', () => {
    const cerrada = reunion({ id: 't2', estado: 'completada' })
    const inactiva = reunion({ id: 't3', activo: false })
    expect(
      retrocesoPorAnularReunion(
        lead('reunion_agendada'), reunion(), [reunion(), cerrada, inactiva], CONTACTO,
      ),
    ).toBe('contactado')
  })

  it('una LLAMADA pendiente no frena el retroceso: la etapa la sostiene la reunión', () => {
    const llamada = reunion({ id: 't2', tipo: 'llamada' })
    expect(
      retrocesoPorAnularReunion(lead('reunion_agendada'), reunion(), [reunion(), llamada], CONTACTO),
    ).toBe('contactado')
  })

  it('si la reunión LLEGÓ A OCURRIR no baja: borraría el hito más caro del embudo', () => {
    expect(
      retrocesoPorAnularReunion(
        lead('reunion_agendada'), reunion(), [reunion()], acts('llamada_realizada', 'reunion_realizada'),
      ),
    ).toBeNull()
  })

  it('anular una LLAMADA no mueve ninguna etapa', () => {
    const llamada = reunion({ tipo: 'llamada' })
    expect(
      retrocesoPorAnularReunion(lead('reunion_agendada'), llamada, [llamada], CONTACTO),
    ).toBeNull()
  })

  it('desde PROPUESTA ENVIADA no baja: ahí la etapa ya no la sostiene la reunión', () => {
    expect(
      retrocesoPorAnularReunion(lead('propuesta_enviada'), reunion(), [reunion()], CONTACTO),
    ).toBeNull()
  })

  it.each(['nuevo', 'contactado'] as const)('desde %s no hay nada que bajar', (etapa) => {
    expect(retrocesoPorAnularReunion(lead(etapa), reunion(), [reunion()], CONTACTO)).toBeNull()
  })

  it.each(['convertido', 'descartado'] as const)('un lead %s es terminal: intocable', (etapa) => {
    expect(retrocesoPorAnularReunion(lead(etapa), reunion(), [reunion()], CONTACTO)).toBeNull()
  })

  it('un lead INACTIVO no se toca', () => {
    expect(
      retrocesoPorAnularReunion(lead('reunion_agendada', false), reunion(), [reunion()], CONTACTO),
    ).toBeNull()
  })

  it('un lead de la COLA GLOBAL (sin dueño) no baja — espejo del gate de ámbito', () => {
    const sinDuenio = {
      etapa: 'reunion_agendada' as const,
      activo: true,
      vendedor_id: null,
      asignado_supervisor_id: null,
    }
    expect(retrocesoPorAnularReunion(sinDuenio, reunion(), [reunion()], CONTACTO)).toBeNull()
  })

  it('SUBIR y BAJAR se componen: reagendar en el mismo gesto deja la etapa donde estaba', () => {
    // Es lo que hace el servidor cuando la RPC encadena una reunión nueva: el
    // trigger de retroceso baja a `contactado` y el de subida la devuelve a
    // `reunion_agendada` un statement después. Neto cero, sin caso especial.
    const atras = retrocesoPorAnularReunion(lead('reunion_agendada'), reunion(), [reunion()], CONTACTO)
    expect(atras).toBe('contactado')
    const nueva = reunion({ id: 't9' })
    expect(avancePorReunion(lead(atras ?? 'nuevo'), nueva, true, AHORA)).toBe('reunion_agendada')
  })
})
