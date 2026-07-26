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
import { avancePorContacto, avancePorReunion } from './avance-automatico'
import type { Etapa, Tarea } from './tipos'

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

  it('el rebote automático tras un no-show NO asciende: plantar al asesor no es progreso', () => {
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
