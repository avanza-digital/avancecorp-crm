// lib/cola-supervision.ts — cómo lee el SUPERVISOR una fila del seguimiento
// activo (crm.cola_accion_v2_fn) en su pantalla Hoy (27/09/2026).
//
// ACCIONES_SLA habla al analista en imperativo («Contactar al cliente»); el
// supervisor no gestiona el lead, lo revisa con su analista (textoAvisoSla con
// supervision = true). Por eso aquí el bucket se nombra como un ESTADO del
// caso, y el tiempo dice qué significa la fecha de referencia de ese bucket:
// en unos es un plazo (vence / venció), en otros el inicio (desde).
import { DIA_MS, duracionTexto, haceTexto } from './inteligencia'

/** Estado del caso visto desde supervisión, por bucket del seguimiento. */
export const ESTADO_CASO_SUPERVISION: Record<string, string> = {
  primera_atencion: 'Primera gestión pendiente',
  tarea_vencida: 'Actividad vencida',
  tarea_hoy: 'Actividad para hoy',
  seguimiento: 'Seguimiento pendiente',
  revision_comercial: 'Revisión comercial',
  datos_incompletos: 'Datos incompletos',
  proxima_tarea: 'Próxima actividad',
  por_repartir: 'Sin analista asignado',
}

export function estadoCasoSupervision(bucket: string): string {
  return ESTADO_CASO_SUPERVISION[bucket] ?? 'Revisar oportunidad'
}

// En estos buckets `referencia_en` es un PLAZO (private.sla_operacion_leads):
// el límite de la primera gestión, el vencimiento de la actividad o el límite
// del seguimiento. En los demás es el inicio del caso (creado_en, etapa).
const BUCKETS_CON_PLAZO = new Set(['primera_atencion', 'tarea_vencida', 'tarea_hoy', 'seguimiento', 'proxima_tarea'])

/**
 * «venció hace 2 días» / «vence en 3 horas» / «desde hace 5 días».
 * Sin fecha confirmada lo dice: no se inventa un tiempo (referencia_en es nullable).
 */
export function momentoCaso(bucket: string, referenciaEn: string | null, ahora: number): string {
  const ms = referenciaEn == null ? Number.NaN : Date.parse(referenciaEn)
  if (!Number.isFinite(ms)) return 'sin fecha confirmada'
  const dias = (ahora - ms) / DIA_MS
  if (!BUCKETS_CON_PLAZO.has(bucket)) return `desde ${haceTexto(Math.max(0, dias))}`
  return dias >= 0 ? `venció ${haceTexto(dias)}` : `vence en ${duracionTexto(-dias)}`
}
