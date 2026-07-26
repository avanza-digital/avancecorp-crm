// Contrato del semáforo por etapa de la tarjeta del kanban.
//
// Dos invariantes que valen más que los colores:
//  1. UN SOLO RELOJ — los días que pinta la card tienen que ser LOS MISMOS que
//     calcula la cola de acción para ese lead. Si divergen, Hoy y Pipeline se
//     contradicen sobre el mismo prospecto y el CRM pierde autoridad.
//  2. Es el reloj del ASESOR, no el del cliente: un lead que pasó semanas en la
//     cola de Rosa no puede nacer rojo el día que alguien lo recibe.
import { describe, expect, it } from 'vitest'
import { semaforoEstancamiento, UMBRAL_ETAPA_MS } from './estancamiento'
import { colaDe, indexarUltimoContacto } from './inteligencia'
import { SEMAFORO } from './semaforo'
import type { Actividad, Etapa, Lead } from './tipos'

const DIA_MS = 86_400_000
const AHORA = Date.UTC(2026, 6, 22, 15)
const haceDias = (d: number) => new Date(AHORA - d * DIA_MS).toISOString()

const lead = (cambios: Partial<Lead>): Lead => ({
  id: 'l1',
  nombre_completo: 'CLIENTE PRUEBA',
  telefono: '+51999999999',
  etapa: 'nuevo',
  origen: 'referido',
  monto_estimado: 10_000,
  moneda: 'PEN',
  vendedor_id: 'v1',
  creado_en: haceDias(1),
  activo: true,
  ...cambios,
})

const sinActividad = indexarUltimoContacto([])

describe('UMBRAL_ETAPA_MS — espejo de private.umbral_estancamiento', () => {
  it.each([
    ['nuevo', 24],
    ['contactado', 72],
    ['reunion_agendada', 72],
    ['propuesta_enviada', 120],
  ] as const)('%s vence a las %i h', (etapa, horas) => {
    expect(UMBRAL_ETAPA_MS[etapa]).toBe(horas * 3_600_000)
  })

  it.each(['convertido', 'descartado'] as const)('un lead %s no se estanca', (etapa) => {
    expect(UMBRAL_ETAPA_MS[etapa as Etapa]).toBeUndefined()
    expect(semaforoEstancamiento(lead({ etapa }), sinActividad, AHORA).color).toBeNull()
  })
})

describe('semaforoEstancamiento — cada etapa con SU plazo', () => {
  it('6 días en Nuevo es rojo, pero 6 días en Propuesta enviada sigue azul', () => {
    // El caso que motiva todo: hoy las dos cards se ven idénticas.
    const enNuevo = semaforoEstancamiento(lead({ etapa: 'nuevo', creado_en: haceDias(6) }), sinActividad, AHORA)
    const enPropuesta = semaforoEstancamiento(
      lead({ etapa: 'propuesta_enviada', creado_en: haceDias(4) }),
      sinActividad,
      AHORA,
    )
    expect(enNuevo.color).toBe(SEMAFORO.critico)
    expect(enPropuesta.color).toBe(SEMAFORO.ok)
    expect(enPropuesta.estancado).toBe(false)
  })

  it('dentro de plazo va azul; pasado el umbral, ámbar; al doble, rojo', () => {
    const en = (h: number) =>
      semaforoEstancamiento(
        lead({ etapa: 'contactado', creado_en: new Date(AHORA - h * 3_600_000).toISOString() }),
        sinActividad,
        AHORA,
      ).color
    expect(en(71)).toBe(SEMAFORO.ok)
    expect(en(73)).toBe(SEMAFORO.atencion)
    expect(en(145)).toBe(SEMAFORO.critico)
  })

  it('el reloj es del ASESOR: un lead viejo recién asignado arranca en cero', () => {
    const recien = lead({ etapa: 'nuevo', creado_en: haceDias(30), tenencia_desde: haceDias(0.1) })
    const s = semaforoEstancamiento(recien, sinActividad, AHORA)
    expect(s.dias).toBeCloseTo(0.1, 1)
    expect(s.color).toBe(SEMAFORO.ok)
  })

  it('un CONTACTO REAL reinicia el reloj; una reasignación del sistema NO', () => {
    const l = lead({ etapa: 'contactado', creado_en: haceDias(30), tenencia_desde: haceDias(20) })
    const act = (tipo: Actividad['tipo'], dias: number): Actividad => ({
      id: `a-${tipo}`, lead_id: 'l1', tipo, detalle: null, autor_nombre: 'V', creado_en: haceDias(dias),
    })
    expect(semaforoEstancamiento(l, indexarUltimoContacto([act('llamada_realizada', 1)]), AHORA).color)
      .toBe(SEMAFORO.ok)
    // La `reasignacion` no entra en el índice de contacto → sigue midiendo
    // desde la tenencia (20 días) y el semáforo NO se apaga solo.
    expect(semaforoEstancamiento(l, indexarUltimoContacto([act('reasignacion', 1)]), AHORA).color)
      .toBe(SEMAFORO.critico)
  })
})

describe('UN SOLO RELOJ — kanban y cola no pueden contradecirse', () => {
  it('los días de la card son EXACTAMENTE los que calcula colaDe', () => {
    const l = lead({ etapa: 'propuesta_enviada', creado_en: haceDias(30), tenencia_desde: haceDias(9) })
    const acts: Actividad[] = [
      { id: 'a1', lead_id: 'l1', tipo: 'whatsapp_enviado', detalle: null, autor_nombre: 'V', creado_en: haceDias(7) },
    ]
    const enCola = colaDe([l], acts, AHORA)[0]
    const enCard = semaforoEstancamiento(l, indexarUltimoContacto(acts), AHORA)
    expect(enCola?.dias).toBeCloseTo(enCard.dias, 6)
  })
})
