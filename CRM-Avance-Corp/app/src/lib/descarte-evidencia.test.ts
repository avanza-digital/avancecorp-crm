// Contrato de «No responde»: es una AFIRMACIÓN DE HECHO sobre el cliente, no
// una opinión del analista. Sin intentos registrados es falsa — y contamina la
// métrica con la que se decide de dónde traer leads (un origen bueno aparece
// como "no responde" cuando en realidad nadie lo trabajó).
//
// Fail-closed en todo: ante la duda, NO hay evidencia.
import { describe, expect, it } from 'vitest'
import { evidenciaNoResponde, INTENTOS_MIN_NO_RESPONDE, vetoNoResponde } from './descarte-evidencia'
import type { Actividad, TipoActividad } from './tipos'

const act = (tipo: TipoActividad, iso: string): Actividad => ({
  id: `${tipo}-${iso}`,
  lead_id: 'l1',
  tipo,
  detalle: null,
  autor_nombre: 'ANALISTA UNO',
  creado_en: iso,
})

const D = (dia: number) => `2026-07-${String(dia).padStart(2, '0')}T15:00:00.000Z`

describe('evidenciaNoResponde — qué cuenta como intento', () => {
  it.each(['llamada_no_contestada', 'whatsapp_enviado'] as const)('%s SÍ es un intento', (tipo) => {
    expect(evidenciaNoResponde([act(tipo, D(1))]).intentos).toBe(1)
  })

  it.each(['llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'] as const)(
    '%s NO es un intento: el cliente respondió',
    (tipo) => {
      expect(evidenciaNoResponde([act(tipo, D(1))]).intentos).toBe(0)
    },
  )

  it('una NOTA no es haber llamado — escribir "llamé y no contestó" no cuenta', () => {
    expect(evidenciaNoResponde([act('nota', D(1))]).intentos).toBe(0)
  })

  it.each(['reasignacion', 'cambio_etapa'] as const)(
    'lo que emite el SISTEMA (%s) no cuenta: si no, todo lead repartido pasaría el corte',
    (tipo) => {
      expect(evidenciaNoResponde([act(tipo, D(1))]).intentos).toBe(0)
    },
  )

  it('solo cuenta lo POSTERIOR a la última conversación', () => {
    // Dos intentos viejos + el cliente respondió ayer: no se puede afirmar que
    // no responde. El contador vuelve a cero desde la conversación.
    const acts = [
      act('llamada_no_contestada', D(1)),
      act('whatsapp_enviado', D(2)),
      act('whatsapp_recibido', D(3)),
    ]
    expect(evidenciaNoResponde(acts)).toMatchObject({ intentos: 0, huboConversacion: true })
  })

  it('tras la conversación, los intentos NUEVOS sí cuentan', () => {
    const acts = [
      act('whatsapp_recibido', D(3)),
      act('llamada_no_contestada', D(4)),
      act('whatsapp_enviado', D(5)),
    ]
    expect(evidenciaNoResponde(acts)).toMatchObject({ intentos: 2, huboConversacion: true, desde: D(4) })
  })

  it('no depende del ORDEN de entrada (el store antepone las optimistas)', () => {
    const acts = [act('whatsapp_enviado', D(5)), act('whatsapp_recibido', D(3)), act('llamada_no_contestada', D(4))]
    expect(evidenciaNoResponde(acts).intentos).toBe(2)
  })

  it('una fecha corrupta NO cuenta: fail-closed, jamás inventa evidencia', () => {
    expect(evidenciaNoResponde([act('llamada_no_contestada', 'no-es-fecha')]).intentos).toBe(0)
  })

  it('un timeline vacío no sostiene nada', () => {
    expect(evidenciaNoResponde([])).toEqual({ intentos: 0, huboConversacion: false, desde: null })
  })
})

describe('vetoNoResponde — la razón que ve el analista', () => {
  it('con los intentos suficientes, no hay veto', () => {
    const acts = Array.from({ length: INTENTOS_MIN_NO_RESPONDE }, (_, i) =>
      act('llamada_no_contestada', D(i + 1)),
    )
    expect(vetoNoResponde(acts)).toBeNull()
  })

  it('sin ningún intento dice exactamente qué falta', () => {
    const veto = vetoNoResponde([])
    expect(veto).toContain('no tiene ningún intento de contacto registrado')
    expect(veto).toContain('Registra 2 intentos')
  })

  it('con intentos a medias lleva la cuenta y pide SOLO lo que falta', () => {
    const veto = vetoNoResponde([act('llamada_no_contestada', D(1))])
    expect(veto).toContain('llevas 1 de 2')
    expect(veto).toContain('Registra 1 intento más')
  })

  it('si el cliente respondió, lo dice — es otra historia, no "faltan intentos"', () => {
    const veto = vetoNoResponde([act('whatsapp_recibido', D(3))])
    expect(veto).toContain('el cliente SÍ respondió')
  })
})
