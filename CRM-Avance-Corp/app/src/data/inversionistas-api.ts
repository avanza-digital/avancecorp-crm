import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import {
  CarteraInversionistasSchema, EstadoCarteraInversionistasSchema, FichaInversionistaSchema,
  validarPaginaInversionistas, type EstadoCarteraInversionistas, type FiltrosInversionistas,
} from '@/lib/inversionistas'

function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb
}
export function respuestaInversionistas<T>(schema: v.GenericSchema<unknown, T>, respuesta: {
  data: unknown
  error: {code?: string; message: string} | null
}): T {
  if (respuesta.error) {
    const {code, message} = respuesta.error
    // Supabase devuelve los fallos de transporte con código vacío. No son
    // mensajes de negocio traducidos ni prueban que una escritura fallara.
    if (!code) throw new CrmApiError('No se pudo recibir la respuesta del servidor. Comprueba tu conexión.', 'RESPUESTA_NO_RECIBIDA')
    throw new CrmApiError(code === '42501' ? 'Ya no tienes acceso a esta información.' : message, code)
  }
  const resultado = v.safeParse(schema, respuesta.data)
  if (!resultado.success) {
    // No enviar el payload ni los issues del validador a telemetría: contienen PII.
    throw new CrmApiError('La respuesta está incompleta. Vuelve a consultar.', 'RESPUESTA_INCOMPLETA')
  }
  return resultado.output
}
export async function obtenerEstadoCarteraInversionistas(signal: AbortSignal): Promise<EstadoCarteraInversionistas> {
  const r = await cliente().schema('crm').rpc('cartera_inversionistas_estado_fn').abortSignal(signal)
  // Antes de instalar F5, la ausencia de su RPC es un estado compatible.
  // Guardarlo como dato evita pasar de error a pendiente cada 15 s y desmontar
  // la cartera Avance. Los errores de acceso/red siguen su tratamiento normal.
  if (r.error?.code === 'PGRST202') {
    return { version: 1, habilitada: false, escritura_habilitada: false, motivo: null }
  }
  return respuestaInversionistas(EstadoCarteraInversionistasSchema, r)
}
export async function listarInversionistas(filtros: FiltrosInversionistas, signal: AbortSignal) {
  const r = await cliente().schema('crm').rpc('cartera_inversionistas_filtrada_fn', {
    p_pagina: filtros.pagina, p_tamano: filtros.tamano, p_texto: filtros.texto.trim(),
    ...(filtros.empresa ? {p_empresa: filtros.empresa} : {}),
    ...(filtros.responsable && filtros.responsable !== 'sin_responsable' ? {p_responsable: filtros.responsable} : {}),
    p_sin_responsable: filtros.responsable === 'sin_responsable',
    ...(filtros.mes ? {p_mes: filtros.mes} : {}),
    ...(filtros.moneda ? {p_moneda: filtros.moneda} : {}),
    ...(filtros.estado ? {p_estado: filtros.estado} : {}),
    ...(filtros.contacto ? {p_contacto: filtros.contacto} : {}),
    p_por_vencer: filtros.porVencer,
  }).abortSignal(signal)
  const pagina = respuestaInversionistas(CarteraInversionistasSchema, r)
  if (!validarPaginaInversionistas(pagina)) {
    throw new CrmApiError('La cartera llegó incompleta. Vuelve a consultar.', 'RESPUESTA_INCOMPLETA')
  }
  return pagina
}
export async function obtenerFichaInversionista(id: string, paginaInversiones: number, paginaHistorial: number, signal: AbortSignal) {
  const r = await cliente().schema('crm').rpc('inversionista_ficha_fn', {
    p_inversionista: id, p_pagina_inversiones: paginaInversiones, p_pagina_historial: paginaHistorial,
  }).abortSignal(signal)
  const ficha = respuestaInversionistas(v.nullable(FichaInversionistaSchema), r)
  if (!ficha) throw new CrmApiError('Esta persona ya no está disponible en tu cartera.', '42501')
  if (ficha.inversiones.length !== Math.max(0, Math.min(25, ficha.inversiones_total - (paginaInversiones - 1) * 25))
    || new Set(ficha.inversiones.map(i => `${i.empresa}:${i.fuente_id}`)).size !== ficha.inversiones.length) {
    throw new CrmApiError('La ficha llegó incompleta. Vuelve a consultar.', 'RESPUESTA_INCOMPLETA')
  }
  return ficha
}

const CuentaSchema = v.object({
  cuenta_id: v.nullable(v.string()), moneda: v.picklist(['PEN', 'USD']), origen: v.picklist(['perfil', 'contrato']),
  es_cuenta_perfil: v.boolean(), creada_en: v.nullable(v.string()), banco: v.string(),
  tipo_cuenta: v.picklist(['ahorros', 'corriente']), numero_cuenta: v.string(), cci: v.string(),
  titular_distinto: v.boolean(), beneficiario_nombre: v.nullable(v.string()), beneficiario_dni: v.nullable(v.string()),
})
export async function obtenerCuentasInversionista(id: string, perfilId: string, moneda: 'PEN' | 'USD', signal: AbortSignal) {
  const r = await cliente().schema('crm').rpc('inversionista_cuentas_fn', {
    p_inversionista: id, p_perfil: perfilId, p_moneda: moneda,
  }).abortSignal(signal)
  return respuestaInversionistas(v.array(CuentaSchema), r)
}

export async function descargarDocumentoInversionista(persona: string, fuente: string, documento: string, signal: AbortSignal) {
  const {data, error, response} = await cliente().functions.invoke<Blob>('crm-inversion-documento', {
    body: {inversionista_id: persona, fuente_id: fuente, documento_id: documento}, signal,
  })
  signal.throwIfAborted()
  if (error) throw new CrmApiError('No se pudo abrir el documento con tu acceso actual. Vuelve a consultar.',
    response?.status === 401 || response?.status === 403 ? '42501' : 'DOCUMENTO_NO_DISPONIBLE')
  if (!(data instanceof Blob) || !data.size) throw new CrmApiError('El archivo está incompleto.', 'DOCUMENTO_INCOMPLETO')
  const esperado = response?.headers.get('X-Document-Sha256')
  const sha = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await data.arrayBuffer())), b => b.toString(16).padStart(2, '0')).join('')
  if (!esperado || esperado !== sha) throw new CrmApiError('La integridad del archivo requiere revisión.', 'DOCUMENTO_INCOMPLETO')
  signal.throwIfAborted()
  const url = URL.createObjectURL(data)
  try {
    const a = document.createElement('a')
    a.href = url; a.download = decodeURIComponent(response?.headers.get('X-Document-Name') ?? 'Documento')
    a.click()
  } finally {setTimeout(() => URL.revokeObjectURL(url), 1000)}
}
