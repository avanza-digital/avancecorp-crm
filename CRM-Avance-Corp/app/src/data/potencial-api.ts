// Potencial del lead: las dos puertas del servidor.
//  · `crm.potencial_leads_fn(uuid[])` — LECTURA por lote de la marca de los leads
//    que hay en pantalla (molde: `obtenerCierresEstado`).
//  · `crm.marcar_potencial_lead_fn(uuid, nivel)` — ESCRITURA: la marca manual.
// La tabla de las marcas no tiene permisos para la Data API: no hay otra vía.
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { registrarError } from '@/lib/observabilidad'
import {
  MAX_LEADS_POTENCIAL, POTENCIAL_APAGADO, PotencialLeadsSchema,
  type NivelPotencial, type PotencialLeads,
} from '@/lib/potencial'
import { CrmApiError } from './crm-api'

function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb
}

/** Una consulta cancelada es una cancelación, no un fallo que reportar. */
function lanzarSiCancelada(signal?: AbortSignal): void {
  if (!signal?.aborted) return
  throw signal.reason instanceof Error ? signal.reason : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

function falloDeContrato(): CrmApiError {
  const fallo = new CrmApiError('El potencial de los leads no tiene el formato esperado.', 'POTENCIAL_CONTRACT')
  registrarError('crm.potencial.fuera_de_contrato', fallo)
  return fallo
}

/**
 * La marca de potencial de los leads pedidos. Devuelve un ítem por cada lead
 * que la persona puede ver (con `nivel: null` si no tiene marca).
 *
 * `habilitada: false` es un estado, no un error: la bandera está apagada, o el
 * servidor todavía no tiene la puerta (PGRST202) — en los dos casos la pantalla
 * no pinta nada del potencial.
 */
export async function obtenerPotencialLeads(leadIds: readonly string[], signal?: AbortSignal): Promise<PotencialLeads> {
  // Sin ids no hay pregunta (y sin pregunta no se sabe si está encendido).
  if (leadIds.length === 0) return POTENCIAL_APAGADO

  // El servidor topa cada llamada en 200 ids y la cartera ACUMULA páginas. Se
  // parte en lotes en vez de recortar: recortar dejaría leads marcados sin su
  // marca sin que nadie pudiera notarlo.
  if (leadIds.length > MAX_LEADS_POTENCIAL) {
    const lotes: string[][] = []
    for (let i = 0; i < leadIds.length; i += MAX_LEADS_POTENCIAL) {
      lotes.push(leadIds.slice(i, i + MAX_LEADS_POTENCIAL))
    }
    const respuestas = await Promise.all(lotes.map((lote) => obtenerPotencialLeads(lote, signal)))
    // La bandera es una sola: si algún lote la vio apagada, está apagada.
    if (respuestas.some((r) => !r.habilitada)) return POTENCIAL_APAGADO
    return { version: 1, habilitada: true, items: respuestas.flatMap((r) => r.items) }
  }

  lanzarSiCancelada(signal)
  let consulta = cliente().schema('crm').rpc('potencial_leads_fn', { p_lead_ids: [...leadIds] })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarSiCancelada(signal)
  if (error) {
    if (error.code === 'PGRST202') return POTENCIAL_APAGADO
    const fallo = new CrmApiError('No se pudo leer el potencial de los leads.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.potencial.consulta_fallida', fallo)
    throw fallo
  }

  const resultado = v.safeParse(PotencialLeadsSchema, data)
  if (!resultado.success) throw falloDeContrato()
  if (!resultado.output.habilitada) return POTENCIAL_APAGADO
  // Solo se acepta lo que se pidió, y una vez: un lead ajeno o repetido en la
  // respuesta es una respuesta de otra pregunta.
  const pedidos = new Set(leadIds)
  const vistos = new Set<string>()
  for (const item of resultado.output.items) {
    if (!pedidos.has(item.lead_id) || vistos.has(item.lead_id)) throw falloDeContrato()
    vistos.add(item.lead_id)
  }
  return resultado.output
}

/**
 * Traduce el rechazo de la puerta de marcar a un mensaje es-PE estable. No usa
 * el texto crudo de Postgres salvo en 22023, que solo levantan nuestros propios
 * RAISE (sin datos personales).
 */
function aErrorMarcar(error: { code?: string | null; message?: string | null }): CrmApiError {
  const pg = error.code ?? ''
  let code = 'POSTGREST_ERROR'
  let mensaje = 'No se pudo guardar la marca de potencial.'
  if (pg === '55000') {
    code = 'POTENCIAL_APAGADO'
    mensaje = 'La marca de potencial todavía no está activada.'
  } else if (pg === '42501' || pg === 'PGRST301') {
    code = 'SIN_PERMISO'
    mensaje = 'Solo el analista del lead o su supervisor pueden marcar su potencial.'
  } else if (pg === 'P0002') {
    code = 'FUERA_DE_AMBITO'
    mensaje = 'Este lead ya no está a tu cargo. Actualiza la lista.'
  } else if (pg === '22023') {
    code = 'REGLA_SERVIDOR'
    if (error.message) mensaje = error.message
  } else if (pg === '55P03' || pg === '40P01' || pg === '40001') {
    code = 'REINTENTAR'
    mensaje = 'Otra operación está usando este lead ahora mismo. Vuelve a intentarlo.'
  } else if (pg === '') {
    // Fallo de transporte: no prueba que la marca no se guardara.
    code = 'RESPUESTA_NO_RECIBIDA'
    mensaje = 'No se pudo recibir la respuesta del servidor. Comprueba tu conexión.'
  }
  const fallo = new CrmApiError(mensaje, code)
  registrarError('crm.potencial.marcar_fallido', fallo, { pg })
  return fallo
}

/**
 * Marca el potencial de un lead. La autorización (analista del lead o su
 * supervisor, lead abierto, bandera encendida) la decide el servidor.
 */
export async function marcarPotencialLead(leadId: string, nivel: NivelPotencial): Promise<void> {
  const { error } = await cliente().schema('crm').rpc('marcar_potencial_lead_fn', { p_lead_id: leadId, p_nivel: nivel })
  if (error) throw aErrorMarcar(error)
}
