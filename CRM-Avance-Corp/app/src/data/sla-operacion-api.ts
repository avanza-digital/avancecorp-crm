import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import type { Json } from '@/lib/database.types'
import { soloPresentes } from './argumentos-rpc'
import { CrmApiError } from './crm-api'
import { ConfiguracionSlaV2Schema, ResultadoPublicacionSlaV2Schema, ResultadoModoSlaSchema, ColaDiaPaginaSchema, ColaSlaPaginaSchema, EstadosSlaV2Schema, ResumenAvisosSlaSchema, type CursorSla, type FiltrosSla } from '@/lib/sla-operacion'

export async function obtenerResumenAvisosSla(signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('avisos_sla_resumen_v2_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ResumenAvisosSlaSchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudieron confirmar los avisos de seguimiento.', 'SLA_CONTRACT')
  return parsed.output
}

export async function listarColaSla(filtros: FiltrosSla, cursor: CursorSla | null, limite: number, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('cola_accion_v2_fn', {
    p_limite: limite, p_senal: filtros.senal, p_cursor: cursor as Json | null,
    // Opcionales omitidos en vez de null: en el servidor valen NULL por defecto.
    ...soloPresentes({ p_etapa: filtros.etapa, p_analista_id: filtros.analista_id }),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ColaSlaPaginaSchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo verificar la cola de seguimiento.', 'SLA_CONTRACT')
  return comprobarPagina(parsed.output, filtros, limite)
}

/**
 * La cola del DÍA (v3): leads de la ventana SLA + tareas de clientes del día,
 * en una sola paginación. Mismas comprobaciones de contrato que la v2: el
 * servidor devuelve el eco de los filtros y del límite, y `hay_mas` va con su
 * cursor. Solo la leen Gestión diaria del analista y el botón de «Hoy».
 */
export async function listarColaDia(filtros: FiltrosSla, cursor: CursorSla | null, limite: number, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('cola_accion_v3_fn', {
    p_limite: limite, p_senal: filtros.senal, p_cursor: cursor as Json | null,
    ...soloPresentes({ p_etapa: filtros.etapa, p_analista_id: filtros.analista_id }),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ColaDiaPaginaSchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo verificar la cola del día.', 'SLA_CONTRACT')
  return comprobarPagina(parsed.output, filtros, limite)
}

function comprobarPagina<P extends { limite: number; filtros: { senal: string; etapa: string | null; analista_id: string | null }; items: readonly unknown[]; hay_mas: boolean; cursor_siguiente: unknown }>(
  pagina: P, filtros: FiltrosSla, limite: number,
): P {
  if (pagina.limite !== limite || pagina.filtros.senal !== filtros.senal || pagina.filtros.etapa !== filtros.etapa
    || pagina.filtros.analista_id !== filtros.analista_id || pagina.items.length > limite
    || pagina.hay_mas !== (pagina.cursor_siguiente !== null)) {
    throw new CrmApiError('La página recibida no corresponde a los filtros.', 'SLA_CONTRACT')
  }
  return pagina
}
export async function obtenerEstadosSlaV2(ids: string[], signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('estado_sla_leads_v2_fn', { p_lead_ids: ids })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(EstadosSlaV2Schema, data)
  if (!parsed.success || parsed.output.filas.some((fila) => !ids.includes(fila.lead_id))) {
    throw new CrmApiError('No se pudo verificar el estado de seguimiento.', 'SLA_CONTRACT')
  }
  return parsed.output
}

export async function obtenerConfiguracionSlaV2(signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('configuracion_sla_v2_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ConfiguracionSlaV2Schema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo verificar la configuración del seguimiento.', 'SLA_CONTRACT')
  return parsed.output
}
export async function cambiarModoSla(revision: number, modo: 'activo' | 'legado') {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = await sb.schema('crm').rpc('cambiar_modo_sla_operacion', { p_expected_revision: revision, p_modo: modo })
  if (error) throw new CrmApiError(error.code === 'P0409' || error.code === '40001' ? 'La configuración cambió en otra sesión. Revisa los valores actualizados antes de reintentar.' : error.message, error.code)
  const parsed = v.safeParse(ResultadoModoSlaSchema, data)
  if (!parsed.success || parsed.output.modo !== modo) throw new CrmApiError('El cambio de modo no está confirmado. Actualiza para comprobarlo.', 'SLA_CONTRACT')
  return parsed.output
}

export async function publicarReglasSlaAprobadas(version: number) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = await sb.schema('crm').rpc('publicar_reglas_sla_aprobadas_v2', { p_expected_version: version })
  if (error) throw new CrmApiError(error.code === 'P0409' ? 'La configuración cambió en otra sesión. Revisa los valores actualizados antes de reintentar.' : error.message, error.code)
  const parsed = v.safeParse(ResultadoPublicacionSlaV2Schema, data)
  if (!parsed.success || parsed.output.expected_version !== version + 1 || parsed.output.politica.base.version !== version + 1 || !parsed.output.politica.operacion) {
    throw new CrmApiError('La publicación no está confirmada. Actualiza para comprobarla.', 'SLA_CONTRACT')
  }
  return parsed.output
}
