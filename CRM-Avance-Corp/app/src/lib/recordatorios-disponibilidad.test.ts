import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  RecordatorioDisponibilidadSchema,
  RecordatoriosDisponibilidadSchema,
  aInstanteRevision,
  contactoRecordable,
  derivarAlertasRecordatorios,
  fechaMaximaRevision,
  fechaMinimaRevision,
  sugerirFechaRevision,
  telefonoLegible,
} from './recordatorios-disponibilidad'

// La forma REAL que sirve PostgREST desde crm.recordatorios_disponibilidad.
const FILA = {
  id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
  perfil_id: 'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
  telefono: '+51987654321',
  dni: null,
  recordar_en: '2026-08-25T14:00:00+00:00',
  creado_en: '2026-08-18T05:00:00+00:00',
} as const

describe('el contrato de la fila', () => {
  it('la forma real parsea; una clave extra es error (strict)', () => {
    expect(v.parse(RecordatorioDisponibilidadSchema, FILA).id).toBe(FILA.id)
    expect(v.safeParse(RecordatorioDisponibilidadSchema, {
      ...FILA,
      sorpresa: 1,
    }).success).toBe(false)
  })

  it('la lista valida en bloque', () => {
    expect(v.parse(RecordatoriosDisponibilidadSchema, [FILA])).toHaveLength(1)
    expect(v.safeParse(RecordatoriosDisponibilidadSchema, [{ id: 'x' }]).success).toBe(false)
  })
})

describe('telefonoLegible', () => {
  it('el normalizado se lee como se dicta', () => {
    expect(telefonoLegible('+51987654321')).toBe('987 654 321')
  })
  it('lo raro se devuelve tal cual, jamás se inventa', () => {
    expect(telefonoLegible('987')).toBe('987')
  })
})

describe('derivarAlertasRecordatorios — la campana (§5.4)', () => {
  const ahora = Date.parse('2026-08-26T12:00:00Z')

  it('SOLO los vencidos suenan; los vigentes todavía no recuerdan nada', () => {
    const alertas = derivarAlertasRecordatorios([
      FILA, // recordar_en 25/08 < ahora 26/08 → suena
      { ...FILA, id: '6c073c2a-f22a-4979-8ea4-8921f746ef23', telefono: '+51911111111', recordar_en: '2026-09-01T14:00:00+00:00' },
    ], ahora)

    expect(alertas).toHaveLength(1)
    const alerta = alertas[0]!
    expect(alerta.tipo).toBe('revisar_contacto')
    expect(alerta.severidad).toBe('atencion')
    expect(alerta.alcance).toBe('personal')
    expect(alerta.detalle).toContain('987 654 321')
    expect(alerta.contacto).toEqual({
      telefono: '+51987654321',
      recordatorioId: FILA.id,
    })
    expect(alerta.destino.etiqueta).toBe('Verificar disponibilidad')
  })

  it('la campana JAMÁS carga veredictos: solo contacto y fecha (regla del plan)', () => {
    const alerta = derivarAlertasRecordatorios([FILA], ahora)[0]!
    const serializada = JSON.stringify(alerta)
    expect(serializada).not.toContain('estado')
    expect(serializada).not.toContain('veredicto')
  })

  it('una fecha corrupta no suena ni revienta', () => {
    expect(derivarAlertasRecordatorios([
      { ...FILA, recordar_en: 'no-es-fecha' as never },
    ], ahora)).toHaveLength(0)
  })
})

describe('sugerirFechaRevision — fecha SOLO donde hay regla real', () => {
  const ahora = Date.parse('2026-08-18T15:00:00Z')

  it('enfriamiento: el día en que se libera (la única regla real hoy)', () => {
    expect(sugerirFechaRevision({
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      disponible_desde: '2026-09-10T05:00:00Z',
      descartado_por: null,
    }, ahora)).toBe('2026-09-10')
  })

  it('tomado: sin motor hasta F4 — default +7 días, nota personal', () => {
    expect(sugerirFechaRevision({
      estado: 'tomado',
      vendedor: 'ANA',
      tenencia_desde: null,
    }, ahora)).toBe('2026-08-25')
  })

  it('una liberación que quedó ATRÁS cae a mañana, nunca al pasado', () => {
    expect(sugerirFechaRevision({
      estado: 'enfriamiento',
      motivo_descarte: 'no_responde',
      disponible_desde: '2026-08-01T05:00:00Z',
      descartado_por: null,
    }, ahora)).toBe('2026-08-19')
  })
})

describe('contactoRecordable — solo ocupados SIN puerta', () => {
  it.each([
    [{ estado: 'tomado', vendedor: null, tenencia_desde: null } as const, true],
    [{ estado: 'enfriamiento', motivo_descarte: 'otro', disponible_desde: '2026-09-01T05:00:00Z', descartado_por: null } as const, true],
    [{ estado: 'libre' } as const, false],
    [{ estado: 'en_bolsa' } as const, false],
    [{ estado: 'ya_es_cliente', asesor: 'X' } as const, false],
    [{ estado: 'no_contactar' } as const, false],
  ])('%o → %s', (resultado, esperado) => {
    expect(contactoRecordable(resultado)).toBe(esperado)
  })
})

describe('las fechas del formulario', () => {
  it('el mínimo es mañana en Lima', () => {
    // 2026-08-19T03:00Z todavía es 18/08 22:00 en Lima → mañana = 19/08.
    expect(fechaMinimaRevision(Date.parse('2026-08-19T03:00:00Z'))).toBe('2026-08-19')
  })
  it('el máximo es hoy+364 en Lima: el último día que cabe a CUALQUIER hora', () => {
    // El servidor rechaza >365 días desde el instante de guardar y el instante
    // viaja a las 09:00 de Lima: hoy+365 elegido de madrugada ya rebasaría.
    expect(fechaMaximaRevision(Date.parse('2026-08-18T17:00:00Z'))).toBe('2027-08-17')
  })
  it('el máximo respeta la fecha de Lima, no la UTC', () => {
    // 2026-08-19T03:00Z todavía es 18/08 en Lima → mismo máximo que arriba.
    expect(fechaMaximaRevision(Date.parse('2026-08-19T03:00:00Z'))).toBe('2027-08-17')
  })
  it('el instante de revisión es a las 09:00 de Lima', () => {
    expect(aInstanteRevision('2026-08-25')).toBe('2026-08-25T09:00:00-05:00')
  })
})
