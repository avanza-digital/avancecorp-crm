import type { EstadoSlaLead } from './sla-versionado'
import type { Actividad, Lead } from './tipos'
import { POLITICA_SLA_DEMO } from './demo-config'

const MINUTO_MS = 60_000

const GESTIONES = new Set<Actividad['tipo']>([
  'llamada_realizada',
  'llamada_no_contestada',
  'whatsapp_enviado',
  'whatsapp_recibido',
  'reunion_realizada',
])

const CONTACTOS_EFECTIVOS = new Set<Actividad['tipo']>([
  'llamada_realizada',
  'whatsapp_recibido',
  'reunion_realizada',
])

const MINUTOS_POR_ETAPA = Object.fromEntries(
  POLITICA_SLA_DEMO.etapas.map((regla) => [regla.etapa, regla.maximo_minutos]),
) as Record<(typeof POLITICA_SLA_DEMO.etapas)[number]['etapa'], number>

function isoMasMinutos(base: string, minutos: number): string {
  const inicio = Date.parse(base)
  return new Date(inicio + minutos * MINUTO_MS).toISOString()
}

function primeraActividad(
  actividades: readonly Actividad[],
  tipos: ReadonlySet<Actividad['tipo']>,
): string | null {
  let primera: string | null = null
  for (const actividad of actividades) {
    if (!tipos.has(actividad.tipo) || !Number.isFinite(Date.parse(actividad.creado_en))) continue
    if (primera == null || actividad.creado_en < primera) primera = actividad.creado_en
  }
  return primera
}

function inicioEtapa(lead: Lead, actividades: readonly Actividad[]): string {
  let inicio = lead.creado_en
  for (const actividad of actividades) {
    if (
      actividad.tipo === 'cambio_etapa'
      && Number.isFinite(Date.parse(actividad.creado_en))
      && actividad.creado_en > inicio
    ) {
      inicio = actividad.creado_en
    }
  }
  return inicio
}

function uuidAsignacion(indice: number): string {
  return `00000000-0000-4000-8001-${String(indice + 1).padStart(12, '0')}`
}

/**
 * Fixture explícito para las sesiones demo. No intenta reconstruir producción:
 * marca `aproximado=true` y existe únicamente para que el recorrido sin backend
 * conserve señales temporales coherentes con el modelo versionado.
 */
export function crearEstadosSlaDemo(
  leads: readonly Lead[],
  actividades: readonly Actividad[],
): EstadoSlaLead[] {
  const porLead = new Map<string, Actividad[]>()
  for (const actividad of actividades) {
    const actuales = porLead.get(actividad.lead_id)
    if (actuales) actuales.push(actividad)
    else porLead.set(actividad.lead_id, [actividad])
  }

  return leads
    .filter((lead) => lead.activo)
    .map((lead, indice) => {
      const suyas = porLead.get(lead.id) ?? []
      const primeraGestion = primeraActividad(suyas, GESTIONES)
      const primerContacto = primeraActividad(suyas, CONTACTOS_EFECTIVOS)
      const baseAsignacion = lead.tenencia_desde ?? lead.creado_en
      const esEtapaActiva = lead.etapa in MINUTOS_POR_ETAPA
      const etapa = esEtapaActiva
        ? lead.etapa as keyof typeof MINUTOS_POR_ETAPA
        : null
      const etapaInicio = etapa == null ? null : inicioEtapa(lead, suyas)
      const asignacionId = lead.vendedor_id == null ? null : uuidAsignacion(indice)

      return {
        lead_id: lead.id,
        ciclo_politica_id: POLITICA_SLA_DEMO.id,
        ciclo_politica_version: POLITICA_SLA_DEMO.version,
        primera_gestion_limite_en: isoMasMinutos(
          lead.creado_en,
          POLITICA_SLA_DEMO.primera_gestion_minutos,
        ),
        primera_gestion_en: primeraGestion,
        primer_contacto_limite_en: isoMasMinutos(
          lead.creado_en,
          POLITICA_SLA_DEMO.primer_contacto_minutos,
        ),
        primer_contacto_en: primerContacto,
        ciclo_aproximado: true,
        asignacion_id: asignacionId,
        asignacion_politica_id: asignacionId == null ? null : POLITICA_SLA_DEMO.id,
        asignacion_politica_version: asignacionId == null ? null : POLITICA_SLA_DEMO.version,
        asignacion_primera_gestion_limite_en:
          asignacionId == null
            ? null
            : isoMasMinutos(baseAsignacion, POLITICA_SLA_DEMO.primera_gestion_minutos),
        asignacion_primera_gestion_en: asignacionId == null ? null : primeraGestion,
        asignacion_primer_contacto_limite_en:
          asignacionId == null
            ? null
            : isoMasMinutos(baseAsignacion, POLITICA_SLA_DEMO.primer_contacto_minutos),
        asignacion_primer_contacto_en: asignacionId == null ? null : primerContacto,
        etapa_politica_id: etapa == null ? null : POLITICA_SLA_DEMO.id,
        etapa_politica_version: etapa == null ? null : POLITICA_SLA_DEMO.version,
        etapa,
        etapa_iniciada_en: etapaInicio,
        etapa_limite_en:
          etapa == null || etapaInicio == null
            ? null
            : isoMasMinutos(etapaInicio, MINUTOS_POR_ETAPA[etapa]),
        etapa_objetivo_minutos: etapa == null ? null : MINUTOS_POR_ETAPA[etapa],
        etapa_aproximada: etapa == null ? null : true,
      }
    })
}
