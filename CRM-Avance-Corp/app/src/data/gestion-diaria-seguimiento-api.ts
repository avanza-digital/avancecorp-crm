import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { AvisosCortesSchema, PresentacionCorteSchema } from '@/lib/gestion-diaria-avisos'
import { ConfiguracionGestionDiariaSchema, PoliticaGestionDiariaSchema, type PoliticaGestionDiaria } from '@/lib/politica-gestion-diaria'

function cliente() {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  return sb.schema('crm')
}
function contrato(): never {
  throw new CrmApiError('No se pudo confirmar la respuesta de Gestión Diaria.', 'GESTION_DIARIA_CONTRACT')
}
function avisos(data: unknown, supervisor: string) {
  const r = v.safeParse(AvisosCortesSchema, data)
  if (!r.success || r.output.supervisor_id !== supervisor) return contrato()
  return r.output
}
function configuracion(data: unknown) {
  const r = v.safeParse(ConfiguracionGestionDiariaSchema, data)
  if (!r.success) return contrato()
  return r.output
}
export async function obtenerAvisosCortes(supervisor: string, signal?: AbortSignal) {
  let q = cliente().rpc('gestion_diaria_avisos_fn')
  if (signal) q = q.abortSignal(signal)
  const { data, error } = await q
  if (signal?.aborted) throw new DOMException('Consulta cancelada', 'AbortError')
  if (error) throw new CrmApiError(error.message, error.code)
  return avisos(data, supervisor)
}
export async function presentarCorte(alertaId: string, solicitudId: string) {
  const { data, error } = await cliente().rpc('gestion_diaria_presentar_corte', {
    p_alerta_id: alertaId, p_solicitud_id: solicitudId,
  }).abortSignal(AbortSignal.timeout(30_000))
  if (error) throw new CrmApiError(error.message, error.code)
  const r = v.safeParse(PresentacionCorteSchema, data)
  if (!r.success || r.output.solicitud_id !== solicitudId
    || (r.output.aviso !== null && r.output.aviso.id !== alertaId)) return contrato()
  return r.output.aviso
}
export async function reconocerCorte(supervisor: string, alertaId: string,
  accion: 'reconocer' | 'posponer', solicitudId: string) {
  const { data, error } = await cliente().rpc('gestion_diaria_reconocer_corte', {
    p_alerta_id: alertaId, p_accion: accion, p_solicitud_id: solicitudId,
  })
  if (error) throw new CrmApiError(error.message, error.code)
  return avisos(data, supervisor)
}
export async function obtenerConfiguracionGestionDiaria(signal?: AbortSignal) {
  let q = cliente().rpc('configuracion_gestion_diaria_fn')
  if (signal) q = q.abortSignal(signal)
  const { data, error } = await q
  if (signal?.aborted) throw new DOMException('Consulta cancelada', 'AbortError')
  if (error) throw new CrmApiError(error.message, error.code)
  return configuracion(data)
}

export interface PublicacionGestionDiaria {
  version: number
  vigenteDesde: string
  configuracion: PoliticaGestionDiaria
  motivo: string
}
export async function publicarGestionDiaria(p: PublicacionGestionDiaria) {
  const validacion = v.safeParse(PoliticaGestionDiariaSchema, p.configuracion)
  if (!validacion.success) throw new CrmApiError('Revisa los parámetros de los cortes.', 'REGLA_CLIENTE')
  const { data, error } = await cliente().rpc('publicar_politica_gestion_diaria', {
    p_expected_version: p.version, p_vigente_desde: p.vigenteDesde,
    p_config: validacion.output, p_motivo: p.motivo.trim(),
  })
  if (error) throw new CrmApiError(error.message, error.code)
  const respuesta = configuracion(data)
  const eco = respuesta.historial.find((r) => r.version === p.version + 1)
  if (!eco || Date.parse(eco.vigente_desde) !== Date.parse(p.vigenteDesde)
    || eco.motivo !== p.motivo.trim()
    || Object.keys(validacion.output).some((k) => {
      const campo = k as keyof PoliticaGestionDiaria
      return eco.configuracion[campo] !== validacion.output[campo]
    })) return contrato()
  return respuesta
}
export async function controlarAvisosGestionDiaria(p: { version: number; habilitados: boolean; motivo: string }) {
  const { data, error } = await cliente().rpc('controlar_avisos_gestion_diaria', {
    p_expected_version: p.version, p_habilitados: p.habilitados, p_motivo: p.motivo.trim(),
  })
  if (error) throw new CrmApiError(error.message, error.code)
  const respuesta = configuracion(data)
  if (respuesta.control_avisos.version !== p.version + 1
    || respuesta.control_avisos.habilitados !== p.habilitados
    || respuesta.control_avisos.motivo !== p.motivo.trim()) return contrato()
  return respuesta
}
