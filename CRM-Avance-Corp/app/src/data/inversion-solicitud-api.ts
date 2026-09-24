import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'
import { ConfirmacionInversionSchema, SolicitudInversionSchema, jsonInversion, type IntentoInversion } from '@/lib/inversion-solicitud'

const Id = v.pipe(v.string(), v.uuid())
const ContextoConversionSchema = v.object({
  solicitud_id: v.nullable(Id), documento_tipo: v.nullable(v.picklist(['DNI','CE','PASAPORTE'])),
  persona: v.object({inversionista_id: Id, perfil_id: v.nullable(Id), nombre: v.string(),
    correo: v.nullable(v.string()), telefono: v.nullable(v.string()),
    responsable_id: v.nullable(Id), responsable_nombre: v.nullable(v.string())}),
  capacidades: v.object({nueva_inversion: v.boolean(), motivo_no_operable: v.nullable(v.string())}),
})
export async function prepararPersonaLeadInversion(lead: string, tipo: string, documento: string, nombre: string) {
  return respuestaInversionistas(v.object({inversionista_id: Id, lead_id: Id, solicitud_id: v.nullable(Id)}),
    await cliente().schema('crm').rpc('preparar_persona_lead_inversion_fn', {
      p_lead: lead, p_tipo_documento: tipo, p_documento: documento, p_nombre: nombre,
    }))
}
export async function obtenerContextoConversionInversion(lead: string, persona: string | undefined, signal: AbortSignal) {
  const r = await cliente().schema('crm').rpc('contexto_conversion_inversion_fn', {p_lead: lead, ...(persona ? {p_persona: persona} : {})}).abortSignal(signal)
  const contexto = respuestaInversionistas(ContextoConversionSchema, r)
  if (persona && contexto.persona.inversionista_id !== persona) throw new CrmApiError('La identidad cambió. Vuelve a abrir el lead.', 'PT409')
  return contexto
}

function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb
}
export async function consultarSolicitudInversion(id: string, signal?: AbortSignal) {
  const q = cliente().schema('crm').rpc('solicitud_inversion_fn', {p_solicitud: id})
  return respuestaInversionistas(SolicitudInversionSchema, await (signal ? q.abortSignal(signal) : q))
}
export async function prepararSolicitudInversion(intento: IntentoInversion) {
  const args = {p_clave: intento.clave, p_datos: jsonInversion(intento.datos)}
  // Venta cruzada: su puerta exige la búsqueda y el motivo en cada envío (el servidor los
  // compara en un reintento con la misma clave).
  const preparada = intento.venta_cruzada
    ? await cliente().schema('crm').rpc('preparar_inversion_cliente_existente_fn', {...args,
      p_busqueda: intento.venta_cruzada.busqueda_id, p_motivo: intento.venta_cruzada.motivo})
    : intento.reinversion_origen_id
      ? await cliente().schema('crm').rpc('preparar_reinversion_fn', {...args, p_fuente: intento.reinversion_origen_id})
      : await cliente().schema('crm').rpc('preparar_inversion_fn', args)
  respuestaInversionistas(SolicitudInversionSchema, preparada)
  return consultarSolicitudInversion(intento.clave)
}
export async function corregirSolicitudInversion(intento: IntentoInversion) {
  if (!intento.correccion) throw new CrmApiError('Falta el contenido de la corrección.', '22023')
  const c = intento.correccion
  respuestaInversionistas(SolicitudInversionSchema, await cliente().schema('crm').rpc('corregir_solicitud_inversion_fn', {
    p_solicitud: intento.clave, p_clave: c.clave, p_revision_datos_esperada: c.revision,
    p_datos: jsonInversion(c.datos), p_motivo: c.motivo,
  }))
  return consultarSolicitudInversion(intento.clave)
}
export async function revisarResponsableInversion(id: string, responsable: string, revision: number, motivo: string) {
  respuestaInversionistas(SolicitudInversionSchema, await cliente().schema('crm').rpc('revisar_solicitud_inversion_fn', {
    p_solicitud: id, p_responsable_revisado: responsable, p_revision_esperada: revision, p_motivo: motivo,
  }))
  return consultarSolicitudInversion(id)
}
export async function confirmarSolicitudInversion(id: string, revision: number) {
  return respuestaInversionistas(ConfirmacionInversionSchema, await cliente().schema('crm').rpc('confirmar_inversion_revisada_fn', {
    p_solicitud: id, p_revision_datos_esperada: revision,
  }))
}
export async function cancelarSolicitudInversion(id: string, revision: number) {
  return respuestaInversionistas(SolicitudInversionSchema, await cliente().schema('crm').rpc('cancelar_solicitud_inversion_fn', {
    p_solicitud: id, p_revision_datos_esperada: revision,
  }))
}
export async function enviarBienvenidaInversion(id: string) {
  const {data,error}=await cliente().functions.invoke('crm-inversion-bienvenida',{body:{solicitud_id:id}})
  if(error)throw new CrmApiError('La inversión está guardada. No pudimos confirmar el envío de bienvenida.', 'BIENVENIDA_PENDIENTE')
  return respuestaInversionistas(v.object({estado:v.picklist(['enviada','no_corresponde','pendiente','en_proceso','verificar_entrega'])}),{data,error:null})
}
export async function completarAccesoInversion(intento: IntentoInversion) {
  const {data, error} = await cliente().functions.invoke('crm-inversion-portal', {
    body: {solicitud_id: intento.clave, token: intento.token},
  })
  if (error) {
    // El token se fija ANTES del envío; una respuesta perdida conserva el claim.
    let mensaje = 'El acceso sigue pendiente. Reintenta esta misma solicitud.'
    if ('context' in error && error.context instanceof Response) {
      try { const body: unknown = await error.context.clone().json()
        const r = v.safeParse(v.object({error: v.string()}), body)
        if (r.success) mensaje = r.output.error
      } catch { /* no registrar cuerpo ni credenciales */ }
    }
    throw new CrmApiError(mensaje, 'ACCESO_PENDIENTE')
  }
  return respuestaInversionistas(v.object({ok: v.literal(true), solicitud_id: v.pipe(v.string(), v.uuid()),
    perfil_id: v.pipe(v.string(), v.uuid())}), {data,error: null})
}
export async function subirComprobanteInversion(ruta: string, archivo: File) {
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(archivo.type) || archivo.size < 1 || archivo.size > 10 * 1024 * 1024) {
    throw new CrmApiError('Usa un PDF, JPG o PNG de hasta 10 MB.', '22023')
  }
  const extension = ruta.split('.').at(-1)?.toLowerCase()
  const formato = archivo.type === 'application/pdf' ? ['pdf'] : archivo.type === 'image/png' ? ['png'] : ['jpg', 'jpeg']
  if (!extension || !formato.includes(extension)) throw new CrmApiError('El comprobante debe conservar el formato del archivo original de esta solicitud.', '22023')
  const storage = cliente().storage.from('f4-comprobantes')
  const {error} = await storage.upload(ruta, archivo, {upsert: false, contentType: archivo.type})
  if (!error) return
  // Una carga con respuesta perdida se recupera solo si sus bytes son iguales.
  if ('statusCode' in error && String(error.statusCode) === '409') {
    const {data, error: fallo} = await storage.download(ruta)
    if (!fallo && data && data.size === archivo.size) {
      const hash = async (b: Blob) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await b.arrayBuffer()))).join(',')
      if (await hash(data) === await hash(archivo)) return
    }
    throw new CrmApiError('Ya existe otro comprobante en esta solicitud. Revisa el archivo original.', 'P0409')
  }
  throw new CrmApiError('No se pudo cargar el comprobante. Reintenta en esta misma solicitud.', 'COMPROBANTE_PENDIENTE')
}
