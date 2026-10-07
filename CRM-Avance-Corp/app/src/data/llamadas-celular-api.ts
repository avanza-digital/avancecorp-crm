import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { BandejaSchema, ResueltasHoySchema, type Bandeja, type ResueltasHoy, type MotivoDescarte } from '@/lib/llamadas-celular'
import {
  AsignacionesCelularSchema, CelularesSaludSchema, CierreCelularSchema, CredencialCelularSchema,
  type AsignacionCelular, type CelularSalud, type CredencialCelular, type MotivoCierre,
} from '@/lib/celulares'
import { CrmApiError } from './crm-api'

export const llamadasCelularKeys = {
  raiz: ['llamadas-celular'] as const,
  pendientes: (actor: string) => ['llamadas-celular', actor, 'pendientes'] as const,
  hoy: (actor: string) => ['llamadas-celular', actor, 'hoy'] as const,
}

// ── Celulares (F4-c): las cinco puertas de gerencia ─────────────────────────────────────────────────────────────────
// Los textos de 22023 y 23505 son mensajes de negocio del servidor, sin datos personales: la pantalla los muestra tal
// cual (p. ej. «C1 ya está asignado: ciérralo o rota su credencial»). La credencial no pasa por ningún registro.

export const celularesKeys = {
  raiz: ['celulares'] as const,
  salud: ['celulares', 'salud'] as const,
  asignaciones: ['celulares', 'asignaciones'] as const,
}

function confirmarForma<S extends v.GenericSchema>(schema: S, data: unknown, texto: string): v.InferOutput<S> {
  const parsed = v.safeParse(schema, data)
  if (!parsed.success) throw new CrmApiError(texto, 'CELULARES_CONTRACT')
  return parsed.output
}

export async function listarSaludCelulares(signal?: AbortSignal): Promise<CelularSalud[]> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('celulares_salud_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  return confirmarForma(CelularesSaludSchema, data, 'No se pudo confirmar la salud de los celulares. Actualiza e inténtalo de nuevo.')
}

export async function listarAsignacionesCelulares(signal?: AbortSignal): Promise<AsignacionCelular[]> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('celulares_asignaciones_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  return confirmarForma(AsignacionesCelularSchema, data, 'No se pudo confirmar el historial de celulares. Actualiza e inténtalo de nuevo.')
}

const CLAVE_RARA = 'La clave no llegó con la forma esperada y no se usó. Rota el celular para generar otra.'
function credencialDe(data: unknown, etiqueta: string): CredencialCelular {
  const credencial = confirmarForma(CredencialCelularSchema, data, CLAVE_RARA)
  // Una clave de otro celular no se entrega: la macro quedaría mandando con la identidad equivocada.
  if (credencial.etiqueta !== etiqueta) throw new CrmApiError(CLAVE_RARA, 'CELULARES_CONTRACT')
  return credencial
}

/** Solo gerencia. Devuelve la clave UNA vez; la base guarda solo su huella. */
export async function asignarCelular(etiqueta: string, analistaId: string): Promise<CredencialCelular> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = await sb.schema('crm').rpc('asignar_celular', { p_etiqueta: etiqueta, p_analista_id: analistaId })
  if (error) throw new CrmApiError(error.message, error.code)
  return credencialDe(data, etiqueta)
}

/** Cierra la asignación vigente con motivo «rotacion» y abre otra con clave nueva; la vieja muere al instante. */
export async function rotarCredencialCelular(etiqueta: string): Promise<CredencialCelular> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = await sb.schema('crm').rpc('rotar_credencial_celular', { p_etiqueta: etiqueta })
  if (error) throw new CrmApiError(error.message, error.code)
  return credencialDe(data, etiqueta)
}

export async function cerrarAsignacionCelular(asignacionId: string, motivo: MotivoCierre): Promise<void> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = await sb.schema('crm').rpc('cerrar_asignacion_celular', { p_asignacion_id: asignacionId, p_motivo: motivo })
  if (error) throw new CrmApiError(error.message, error.code)
  const cierre = confirmarForma(CierreCelularSchema, data, 'No se pudo confirmar el cierre. Actualiza la lista antes de reintentarlo.')
  if (cierre.asignacion_id !== asignacionId) {
    throw new CrmApiError('No se pudo confirmar el cierre. Actualiza la lista antes de reintentarlo.', 'CELULARES_CONTRACT')
  }
}

export async function listarLlamadasCelular(cursor: Bandeja['siguiente'], signal?: AbortSignal): Promise<Bandeja> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('llamadas_celular_bandeja_fn', {
    p_limite: 50,
    ...(cursor ? { p_antes_id: cursor.evento_id, p_antes_recibido_en: cursor.recibido_en } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(BandejaSchema, data)
  // Sin origen no se puede registrar el resultado exacto: no presentar una integración incompleta como operativa.
  if (!parsed.success || parsed.output.filas.some((f) => !f.evento_origen_id)) {
    throw new CrmApiError('No se pudo confirmar la lista de llamadas. Actualiza e inténtalo de nuevo.', 'LLAMADAS_CONTRACT')
  }
  return parsed.output
}

export async function listarResueltasCelular(cursor: ResueltasHoy['siguiente'], signal?: AbortSignal): Promise<ResueltasHoy> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('llamadas_celular_resueltas_hoy_fn', {
    p_limite: 50,
    ...(cursor ? { p_antes_id: cursor.evento_id, p_antes_resuelto_en: cursor.resuelto_en } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ResueltasHoySchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo confirmar lo resuelto hoy.', 'LLAMADAS_CONTRACT')
  return parsed.output
}

const ConfirmacionAccionSchema = v.object({ evento_id: v.string(), repetido: v.boolean() })
export async function cambiarLlamadaCelular(evento: string, accion:
  { lead: string } | { motivo: MotivoDescarte; detalle: string | null }): Promise<void> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = 'lead' in accion
    ? await sb.schema('crm').rpc('asociar_llamada_celular', { p_evento_id: evento, p_lead_id: accion.lead })
    : await sb.schema('crm').rpc('descartar_llamada_celular', {
      p_evento_id: evento, p_motivo: accion.motivo, ...(accion.detalle ? { p_detalle: accion.detalle } : {}),
    })
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ConfirmacionAccionSchema, data)
  if (!parsed.success || parsed.output.evento_id !== evento) {
    throw new CrmApiError('No se pudo confirmar el cambio. Actualiza la lista antes de reintentarlo.', 'LLAMADAS_CONTRACT')
  }
}
