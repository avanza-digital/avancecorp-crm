// Contrato del reloj de ETAPA (distinto del de inactividad).
//
// Lo delicado es el parseo: el mismo hecho se escribe en DOS formatos según
// quién lo emita —el servidor guarda claves crudas, el store y el demo guardan
// labels es-PE, y el descarte añade sufijo—. Si el parser solo entendiera uno,
// la señal se apagaría en silencio justo para la mitad de los leads.
import { describe, expect, it } from 'vitest'
import { entradaEnEtapa, etapaDestino } from './antiguedad-etapa'
import type { Actividad, Lead } from './tipos'

const lead = (cambios: Partial<Lead> = {}): Lead => ({
  id: 'l1',
  nombre_completo: 'CLIENTE PRUEBA',
  telefono: '+51999999999',
  etapa: 'contactado',
  origen: 'referido',
  monto_estimado: 1000,
  moneda: 'PEN',
  vendedor_id: 'v1',
  creado_en: '2026-06-01T15:00:00.000Z',
  activo: true,
  ...cambios,
})

const cambio = (detalle: string, iso: string, leadId = 'l1'): Actividad => ({
  id: `c-${iso}`,
  lead_id: leadId,
  tipo: 'cambio_etapa',
  detalle,
  autor_nombre: 'ANALISTA UNO',
  creado_en: iso,
})

describe('etapaDestino — los DOS formatos que existen en producción', () => {
  it('claves crudas, que es lo que escribe el servidor', () => {
    expect(etapaDestino('nuevo → contactado')).toBe('contactado')
    expect(etapaDestino('contactado → reunion_agendada')).toBe('reunion_agendada')
  })

  it('labels es-PE, que es lo que escriben el store optimista y el demo', () => {
    expect(etapaDestino('Nuevo → Contactado')).toBe('contactado')
    expect(etapaDestino('Contactado → Reunión agendada')).toBe('reunion_agendada')
  })

  it('el descarte trae sufijo y NO debe confundir al parser', () => {
    expect(etapaDestino('Contactado → Descartado · Motivo: Sin fondos — no tiene liquidez'))
      .toBe('descartado')
  })

  it.each([null, undefined, '', 'sin flecha', 'Nuevo → Etapa Inventada'])(
    'un detalle que no se entiende (%p) devuelve null en vez de adivinar',
    (d) => {
      expect(etapaDestino(d)).toBeNull()
    },
  )
})

describe('entradaEnEtapa — desde cuándo está clavado', () => {
  it('toma el cambio MÁS RECIENTE hacia su etapa actual', () => {
    // Un lead que fue a `contactado`, retrocedió y volvió: manda la vuelta.
    const acts = [
      cambio('Nuevo → Contactado', '2026-07-01T15:00:00.000Z'),
      cambio('Contactado → Nuevo', '2026-07-05T15:00:00.000Z'),
      cambio('Nuevo → Contactado', '2026-07-10T15:00:00.000Z'),
    ]
    expect(entradaEnEtapa(lead(), acts)).toBe('2026-07-10T15:00:00.000Z')
  })

  it('ignora los cambios hacia OTRAS etapas', () => {
    const acts = [
      cambio('Nuevo → Contactado', '2026-07-01T15:00:00.000Z'),
      cambio('Contactado → Reunión agendada', '2026-07-08T15:00:00.000Z'),
    ]
    expect(entradaEnEtapa(lead({ etapa: 'contactado' }), acts)).toBe('2026-07-01T15:00:00.000Z')
  })

  it('ignora las actividades de OTROS leads', () => {
    expect(entradaEnEtapa(lead(), [cambio('Nuevo → Contactado', '2026-07-01T15:00:00.000Z', 'otro')]))
      .toBeNull()
  })

  it('sin el cambio en el timeline devuelve null — NO cae a creado_en', () => {
    // Caer a `creado_en` diría "3 meses en esta etapa" sobre un lead que entró
    // ayer. Sin dato no se afirma nada; el consumidor decide qué hacer.
    expect(entradaEnEtapa(lead(), [])).toBeNull()
  })

  it('una fecha corrupta no cuenta', () => {
    expect(entradaEnEtapa(lead(), [cambio('Nuevo → Contactado', 'no-es-fecha')])).toBeNull()
  })

  it('mezcla de formatos en el mismo timeline (servidor + optimista) funciona', () => {
    const acts = [
      cambio('nuevo → contactado', '2026-07-01T15:00:00.000Z'),
      cambio('Nuevo → Contactado', '2026-07-12T15:00:00.000Z'),
    ]
    expect(entradaEnEtapa(lead(), acts)).toBe('2026-07-12T15:00:00.000Z')
  })
})
