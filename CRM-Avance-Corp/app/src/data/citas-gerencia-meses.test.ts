import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ConsultaCitasSchema, fusionarConsultasCitas } from './citas-gerencia'
import { controlCitasInicial } from '@/lib/control-citas'

const id = (n: number) => `86000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const persona = (lead: number, mes: string, nombre: string) => ({
  lead_id: id(lead), nombre, telefono: '900000000', origen: 'referido', moneda: 'PEN', monto_estimado: 1000, registro_manual: false,
  creado_por: id(20), analista_origen_id: id(20), primera_asignacion_en: `${mes}-01T15:00:00Z`, analista_origen_nombre: 'ANA',
  supervisor_origen_id: id(30), supervisor_origen_nombre: 'SUPERVISORA',
})
const cita = (n: number, lead: number, mes: string, cambios: Record<string, unknown> = {}) => ({
  id: id(n), lead_id: id(lead), nombre: `PERSONA ${lead}`, telefono: '900000000', analista_id: id(20), analista_nombre: 'ANA',
  supervisor_id: id(30), supervisor_nombre: 'SUPERVISORA', vence_en: `${mes}-10T15:00:00Z`, estado: 'pendiente', estado_comercial: 'programada',
  cancelada_por: null, modalidad: 'virtual', origen: 'referido', moneda: 'PEN', monto_estimado: 1000, resultado: 'sin_clasificar', nota: '',
  reagendada_de: null, creado_en: `${mes}-05T15:00:00Z`, asistencia_registrada_en: null, cierre_posterior: false, manual_propio: false,
  registro_manual: false, ...cambios,
})
function consulta(mes: string, generado: string, citas: unknown[], poblacion: unknown[], conversiones: unknown[], porcentaje: number) {
  const configuracion = { ...controlCitasInicial(), mes_inicio: mes, entrevistas_porcentaje: porcentaje }
  return v.parse(ConsultaCitasSchema, {
    version: 2, periodo: { desde: `${mes}-01`, hasta: `${mes}-${mes === '2026-09' ? '30' : '31'}` }, generado_en: generado, citas, citas_clientes: 0,
    disponibilidad_depositos: 'conversion_cliente', criterio_depositos: 'fecha_comercial', conversiones: [],
    gestion: { version: 2, citas_por_lead: 1.25, entrevistas_porcentaje: porcentaje, depositos_porcentaje: 70, actividad_manuales: 'incluir',
      control: { version: 1, mes_inicio: mes, configuracion }, capital: [], poblacion, conversiones,
      asignaciones: (poblacion as { lead_id: string; nombre: string }[]).map(p => ({ lead_id: p.lead_id, analista_id: id(20), analista_nombre: 'ANA',
        supervisor_id: id(30), supervisor_nombre: 'SUPERVISORA', asignado_en: `${mes}-01T15:00:00Z`, manual_propio: false, registro_manual: false,
        nombre: p.nombre, telefono: '900000000', origen: 'referido', moneda: 'PEN', monto_estimado: 1000 })) },
  })
}
const conversion = (lead: number, instante: string) => ({ lead_id: id(lead), perfil_id: id(lead + 500), convertido_en: instante,
  fecha_comercial: instante.slice(0, 10), analista_id: id(20), analista_nombre: 'ANA', supervisor_id: id(30), supervisor_nombre: 'SUPERVISORA', contrato_id: null })

describe('Proyección: fusión de meses completos para un rango que los cruza', () => {
  const septiembre = consulta('2026-09', '2026-10-19T17:00:00Z',
    [cita(1, 101, '2026-09'), cita(2, 102, '2026-09')],
    [persona(101, '2026-09', 'NOMBRE DE SEPTIEMBRE'), persona(102, '2026-09', 'SOLO SEPTIEMBRE')],
    [conversion(101, '2026-09-20T15:00:00Z')], 60)
  const octubre = consulta('2026-10', '2026-10-19T17:05:00Z',
    // La 2 se repite (reprogramada de un mes al otro): cuenta una sola vez, con su dato más reciente.
    [cita(2, 102, '2026-10', { estado_comercial: 'realizada', estado: 'completada' }), cita(3, 101, '2026-10')],
    [persona(101, '2026-10', 'NOMBRE DE OCTUBRE')],
    [conversion(101, '2026-10-02T15:00:00Z')], 80)

  it('concatena las citas sin repetir, deduplica por lead con el mes más reciente y toma la configuración del último', () => {
    const { citas, gestion, corte } = fusionarConsultasCitas([septiembre, octubre])
    expect(citas.map(c => [c.id.slice(-1), c.estado])).toEqual([['1', 'programada'], ['2', 'realizada'], ['3', 'programada']])
    expect(gestion!.avance!.poblacion.map(p => p.nombre)).toEqual(['NOMBRE DE OCTUBRE', 'SOLO SEPTIEMBRE'])
    expect(gestion!.avance!.conversiones).toHaveLength(1)
    expect(gestion!.avance!.conversiones[0]!.convertido_en).toBe('2026-10-02T15:00:00Z')
    expect(gestion!.asignaciones.map(a => a.nombreLead)).toEqual(['NOMBRE DE OCTUBRE', 'SOLO SEPTIEMBRE'])
    expect(gestion!.avance!.control.configuracion.entrevistas_porcentaje).toBe(80)
    expect(gestion!.entrevistasPorcentaje).toBe(80)
    expect(corte).toBe('2026-10-19T17:05:00Z')
  })

  it('un solo mes queda igual y sin gestión no inventa una', () => {
    const solo = fusionarConsultasCitas([octubre])
    expect(solo.citas).toHaveLength(2)
    expect(solo.gestion!.avance!.poblacion).toHaveLength(1)
    const sinGestion = v.parse(ConsultaCitasSchema, { ...octubre, gestion: undefined })
    expect(fusionarConsultasCitas([sinGestion]).gestion).toBeUndefined()
  })
})
