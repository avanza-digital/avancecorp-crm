// Contrato del semáforo SLA de las cards del kanban.
//
// Los plazos no se derivan de la política vigente: llegan sellados por episodio
// desde `crm.estado_sla_leads_fn`. Si esa fotografía falta, la UI falla cerrada
// y omite el color en lugar de fabricar una urgencia retroactiva.
import { describe, expect, it } from 'vitest'
import { semaforoEstancamiento } from './estancamiento'
import { colaDe, indexarUltimoContacto } from './inteligencia'
import { SEMAFORO } from './semaforo'
import type { EstadoSlaLead } from './sla-versionado'
import type { Actividad, Lead } from './tipos'

const DIA_MS = 86_400_000
const HORA_MS = 3_600_000
const AHORA = Date.UTC(2026, 6, 22, 15)
const haceDias = (dias: number) => new Date(AHORA - dias * DIA_MS).toISOString()
const haceHoras = (horas: number) => new Date(AHORA - horas * HORA_MS).toISOString()

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

const estado = (cambios: Partial<EstadoSlaLead> = {}): EstadoSlaLead => ({
  lead_id: 'l1',
  ciclo_politica_id: '00000000-0000-4000-8000-000000000001',
  ciclo_politica_version: 1,
  primera_gestion_limite_en: haceHoras(23),
  primera_gestion_en: null,
  primer_contacto_limite_en: haceHoras(22),
  primer_contacto_en: null,
  ciclo_aproximado: false,
  asignacion_id: '00000000-0000-4000-8000-000000000002',
  asignacion_politica_id: '00000000-0000-4000-8000-000000000001',
  asignacion_politica_version: 1,
  asignacion_primera_gestion_limite_en: haceHoras(23),
  asignacion_primera_gestion_en: null,
  asignacion_primer_contacto_limite_en: haceHoras(22),
  asignacion_primer_contacto_en: null,
  etapa_politica_id: '00000000-0000-4000-8000-000000000001',
  etapa_politica_version: 1,
  etapa: 'nuevo',
  etapa_iniciada_en: haceDias(1),
  etapa_limite_en: new Date(AHORA).toISOString(),
  etapa_objetivo_minutos: 1_440,
  etapa_aproximada: false,
  ...cambios,
})

const sinContacto = indexarUltimoContacto([])

describe('semaforoEstancamiento — fotografía versionada', () => {
  it('sin fotografía SLA omite el color y conserva solo una referencia neutra', () => {
    const resultado = semaforoEstancamiento(
      lead({ creado_en: haceDias(30), tenencia_desde: haceDias(0.1) }),
      sinContacto,
      AHORA,
    )
    expect(resultado).toMatchObject({
      dias: 0.1,
      color: null,
      estancado: false,
      objetivoMinutos: null,
      politicaVersion: null,
    })
  })

  it('un episodio terminal, incompleto o de otra etapa tampoco inventa plazo', () => {
    const terminal = estado({
      etapa: null,
      etapa_politica_id: null,
      etapa_politica_version: null,
      etapa_iniciada_en: null,
      etapa_limite_en: null,
      etapa_objetivo_minutos: null,
      etapa_aproximada: null,
    })
    expect(
      semaforoEstancamiento(lead({ etapa: 'convertido' }), sinContacto, AHORA, terminal),
    ).toMatchObject({ color: null, estancado: false })
  })

  it('cada episodio usa SU plazo sellado: Nuevo está rojo y Propuesta sigue azul', () => {
    const nuevo = semaforoEstancamiento(
      lead({ etapa: 'nuevo' }),
      sinContacto,
      AHORA,
      estado({
        etapa: 'nuevo',
        etapa_iniciada_en: haceDias(6),
        etapa_limite_en: haceDias(5),
        etapa_objetivo_minutos: 1_440,
      }),
    )
    const propuesta = semaforoEstancamiento(
      lead({ etapa: 'propuesta_enviada' }),
      sinContacto,
      AHORA,
      estado({
        etapa: 'propuesta_enviada',
        etapa_iniciada_en: haceDias(4),
        etapa_limite_en: new Date(AHORA + DIA_MS).toISOString(),
        etapa_objetivo_minutos: 7_200,
      }),
    )
    expect(nuevo.color).toBe(SEMAFORO.critico)
    expect(propuesta).toMatchObject({ color: SEMAFORO.ok, estancado: false })
  })

  it('dentro del plazo va azul, vencido ámbar y al doble rojo', () => {
    const en = (horas: number) => semaforoEstancamiento(
      lead({ etapa: 'contactado' }),
      sinContacto,
      AHORA,
      estado({
        etapa: 'contactado',
        etapa_iniciada_en: haceHoras(horas),
        etapa_limite_en: new Date(AHORA + (72 - horas) * HORA_MS).toISOString(),
        etapa_objetivo_minutos: 4_320,
      }),
    ).color

    expect(en(71)).toBe(SEMAFORO.ok)
    expect(en(73)).toBe(SEMAFORO.atencion)
    expect(en(145)).toBe(SEMAFORO.critico)
  })

  it('una transferencia o un contacto no reescribe el episodio de etapa', () => {
    const l = lead({
      etapa: 'contactado',
      creado_en: haceDias(30),
      tenencia_desde: haceDias(0.1),
    })
    const actividad: Actividad = {
      id: 'a1',
      lead_id: 'l1',
      tipo: 'llamada_realizada',
      detalle: null,
      autor_nombre: 'V',
      creado_en: haceHoras(1),
    }
    const fotografia = estado({
      etapa: 'contactado',
      etapa_iniciada_en: haceDias(8),
      etapa_limite_en: haceDias(5),
      etapa_objetivo_minutos: 4_320,
      etapa_politica_version: 3,
    })
    const resultado = semaforoEstancamiento(
      l,
      indexarUltimoContacto([actividad]),
      AHORA,
      fotografia,
    )
    expect(resultado).toMatchObject({
      dias: 8,
      color: SEMAFORO.critico,
      politicaVersion: 3,
    })
  })

  it('cambiar el número de versión no altera un deadline histórico ya sellado', () => {
    const base = {
      etapa: 'contactado' as const,
      etapa_iniciada_en: haceHoras(73),
      etapa_limite_en: haceHoras(1),
      etapa_objetivo_minutos: 4_320,
    }
    const anterior = semaforoEstancamiento(
      lead({ etapa: 'contactado' }),
      sinContacto,
      AHORA,
      estado({ ...base, etapa_politica_version: 1 }),
    )
    const rotuladaNueva = semaforoEstancamiento(
      lead({ etapa: 'contactado' }),
      sinContacto,
      AHORA,
      estado({ ...base, etapa_politica_version: 9 }),
    )
    expect(rotuladaNueva.color).toBe(anterior.color)
    expect(rotuladaNueva.dias).toBe(anterior.dias)
  })
})

describe('UN SOLO EPISODIO — Pipeline y cola no se contradicen', () => {
  it('el bucket sin_avance usa los mismos días y la misma versión que la card', () => {
    const l = lead({ etapa: 'contactado', creado_en: haceDias(20) })
    const actividades: Actividad[] = [{
      id: 'a1',
      lead_id: 'l1',
      tipo: 'llamada_realizada',
      detalle: null,
      autor_nombre: 'V',
      creado_en: haceDias(1),
    }]
    const fotografia = estado({
      etapa: 'contactado',
      etapa_iniciada_en: haceDias(7),
      etapa_limite_en: haceDias(4),
      etapa_objetivo_minutos: 4_320,
      etapa_politica_version: 2,
    })
    const estados = new Map([['l1', fotografia]])
    const enCola = colaDe([l], actividades, AHORA, undefined, estados)[0]
    const enCard = semaforoEstancamiento(
      l,
      indexarUltimoContacto(actividades),
      AHORA,
      fotografia,
    )

    expect(enCola).toMatchObject({ bucket: 'sin_avance', dias: enCard.dias })
    expect(enCola?.motivo).toContain('SLA v2')
    expect(enCard).toMatchObject({ color: SEMAFORO.critico, politicaVersion: 2 })
  })
})
