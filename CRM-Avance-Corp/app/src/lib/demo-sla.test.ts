import { describe, expect, it } from 'vitest'
import { crearEstadosSlaDemo } from './demo-sla'
import { configuracionSlaDemo, metricasSlaDemo } from './demo-config'
import type { Actividad, Lead } from './tipos'

const lead = (cambios: Partial<Lead> = {}): Lead => ({
  id: 'demo-lead',
  nombre_completo: 'CLIENTE DEMO',
  telefono: '+51999999999',
  etapa: 'contactado',
  origen: 'referido',
  monto_estimado: 10_000,
  moneda: 'PEN',
  vendedor_id: 'demo-vendedor',
  creado_en: '2026-08-01T10:00:00.000Z',
  tenencia_desde: '2026-08-01T11:00:00.000Z',
  activo: true,
  ...cambios,
})

const actividad = (
  id: string,
  tipo: Actividad['tipo'],
  creadoEn: string,
): Actividad => ({
  id,
  lead_id: 'demo-lead',
  tipo,
  detalle: null,
  autor_nombre: 'ANALISTA DEMO',
  creado_en: creadoEn,
})

describe('crearEstadosSlaDemo', () => {
  it('distingue primera gestión, contacto efectivo e inicio de etapa', () => {
    const [estado] = crearEstadosSlaDemo([lead()], [
      actividad('a1', 'llamada_no_contestada', '2026-08-01T11:30:00.000Z'),
      actividad('a2', 'whatsapp_recibido', '2026-08-01T12:00:00.000Z'),
      actividad('a3', 'cambio_etapa', '2026-08-01T13:00:00.000Z'),
    ])

    expect(estado).toMatchObject({
      primera_gestion_en: '2026-08-01T11:30:00.000Z',
      primer_contacto_en: '2026-08-01T12:00:00.000Z',
      asignacion_primera_gestion_en: '2026-08-01T11:30:00.000Z',
      asignacion_primer_contacto_en: '2026-08-01T12:00:00.000Z',
      etapa: 'contactado',
      etapa_iniciada_en: '2026-08-01T13:00:00.000Z',
      etapa_objetivo_minutos: 4_320,
      ciclo_aproximado: true,
      etapa_aproximada: true,
    })
  })

  it('sella la asignación desde tenencia, no desde la creación', () => {
    const [estado] = crearEstadosSlaDemo([lead()], [])
    expect(estado?.asignacion_primera_gestion_limite_en).toBe('2026-08-01T13:00:00.000Z')
    expect(estado?.primera_gestion_limite_en).toBe('2026-08-01T12:00:00.000Z')
    expect(estado?.asignacion_primer_contacto_limite_en).toBe('2026-08-02T11:00:00.000Z')
    expect(estado?.primer_contacto_limite_en).toBe('2026-08-02T10:00:00.000Z')
  })

  it('usa la misma política v3 en Config, métricas y estados de leads', () => {
    const configuracion = configuracionSlaDemo()
    const metricas = metricasSlaDemo('2026-08-01', '2026-08-31')
    const [estado] = crearEstadosSlaDemo([lead()], [])
    const politica = configuracion.politica

    expect(estado).toMatchObject({
      ciclo_politica_id: politica.id,
      ciclo_politica_version: politica.version,
      asignacion_politica_id: politica.id,
      asignacion_politica_version: politica.version,
      etapa_politica_id: politica.id,
      etapa_politica_version: politica.version,
    })
    expect(metricas.ciclos.primera_gestion[0]).toMatchObject({
      politica_id: politica.id,
      politica_version: politica.version,
      objetivo_minutos: politica.primera_gestion_minutos,
    })
    expect(metricas.ciclos.primer_contacto[0]?.objetivo_minutos).toBe(
      politica.primer_contacto_minutos,
    )
    expect(Object.fromEntries(
      metricas.etapas.map((grupo) => [grupo.etapa, grupo.objetivo_minutos]),
    )).toEqual(Object.fromEntries(
      politica.etapas.map((regla) => [regla.etapa, regla.maximo_minutos]),
    ))
  })

  it('un lead sin analista conserva ciclo y etapa pero no inventa asignación', () => {
    const [estado] = crearEstadosSlaDemo([lead({ vendedor_id: null })], [])
    expect(estado).toMatchObject({
      asignacion_id: null,
      asignacion_politica_id: null,
      asignacion_primera_gestion_limite_en: null,
      etapa: 'contactado',
    })
  })

  it('las etapas terminales no reciben un plazo de etapa y los inactivos se omiten', () => {
    const estados = crearEstadosSlaDemo([
      lead({ id: 'terminal', etapa: 'convertido' }),
      lead({ id: 'inactivo', activo: false }),
    ], [])
    expect(estados).toHaveLength(1)
    expect(estados[0]).toMatchObject({
      lead_id: 'terminal',
      etapa: null,
      etapa_limite_en: null,
      etapa_objetivo_minutos: null,
    })
  })
})
