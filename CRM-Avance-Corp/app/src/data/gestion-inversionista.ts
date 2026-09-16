import * as v from 'valibot'
import { useQuery, type QueryClient } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import type { Json } from '@/lib/database.types'
import { ContratoRowSchema, CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'
import { inversionistasKeys } from './inversionistas-queries'
import { postventaKeys } from './postventa-queries'
import { crmQueryKeys } from './crm-queries'

const Id = v.pipe(v.string(), v.uuid())
const Texto = v.nullable(v.string())
const Numero = v.pipe(v.number(), v.finite())
const Contrato = v.pipe(ContratoRowSchema, v.transform(c => ({...c, capital:Number(c.capital), tasa_anual:Number(c.tasa_anual)})))
export const GestionInversionistaSchema = v.object({
  version: v.literal(1), inversionista_id: Id,
  perfiles: v.array(v.object({id:Id, nombre:Texto, creado_en:v.string(), sin_limite:v.boolean(), puede_corregir:v.boolean(), domicilio:Texto})),
  contacto: v.object({nombre_completo:v.string(), telefono:Texto, domicilio:Texto, revision:Texto,
    creado_en:v.string(), sin_limite:v.boolean(), puede_corregir:v.boolean()}),
  documento: v.object({id:v.nullable(Id), tipo:Texto, numero:Texto, puede_corregir:v.boolean()}),
  inversion: v.nullable(v.object({
    empresa:v.picklist(['avance','qorilazo','prodelco']), fuente_id:Id,
    puede_corregir:v.boolean(), sin_limite:v.boolean(), puede_reasignar:v.boolean(),
    contrato:v.nullable(Contrato),
    coopac:v.nullable(v.object({monto:Numero, moneda:v.literal('PEN'), numero_transaccion:v.string(),
      referencia:Texto, vence_en:Texto, nota:Texto, creado_en:v.string(), fecha_comercial:Texto,
      anulado_en:Texto, motivo_anulacion:Texto, plazo_meses:v.nullable(Numero), tasa_anual:v.nullable(Numero), revision:v.string()})),
    operaciones:v.array(v.object({id:Id, tipo:v.picklist(['renovacion','upgrade']), moneda:v.picklist(['PEN','USD']),
      capital_anterior:v.nullable(Numero), capital_renovado:v.nullable(Numero), capital_adicional:v.nullable(Numero),
      numero_origen:Texto, numero_nuevo:Texto, desglose_completo:v.boolean(), elegible_conversion:v.boolean()})),
  })),
})
export type GestionInversionista = v.InferOutput<typeof GestionInversionistaSchema>
export type GestionInversion = NonNullable<GestionInversionista['inversion']>
export type DatosContacto = {nombre_completo:string; telefono:string|null; domicilio:string|null}
export type DatosCorreccionCoopac = {monto:number; numero_transaccion:string; referencia:string|null; nota:string|null;
  plazo_meses:number|null; tasa_anual:number|null; vence_en:string|null}

function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb.schema('crm')
}
export async function obtenerGestionInversionista(persona:string, fuente:string|null, signal:AbortSignal) {
  const r = await cliente().rpc('inversionista_gestion_fn', {p_inversionista:persona, ...(fuente ? {p_fuente:fuente} : {})}).abortSignal(signal)
  const datos = respuestaInversionistas(GestionInversionistaSchema, r)
  if (datos.inversionista_id !== persona || (datos.inversion?.fuente_id ?? null) !== fuente
    || (datos.inversion && (datos.inversion.empresa === 'avance' ? !datos.inversion.contrato || datos.inversion.coopac !== null : !datos.inversion.coopac || datos.inversion.contrato !== null))) {
    throw new CrmApiError('La identidad o la inversión cambió. Vuelve a abrir la ficha.', 'PT409')
  }
  return datos
}
export function useGestionInversionista(actor:string, persona:string, fuente:string|null) {
  return useQuery({queryKey:[...inversionistasKeys.actor(actor),'persona',persona,'gestion',fuente],
    queryFn:({signal}) => obtenerGestionInversionista(persona,fuente,signal), enabled:Boolean(actor && persona),
    staleTime:0, gcTime:0, retry:false, refetchOnMount:'always', refetchInterval:15_000,
    refetchOnWindowFocus:'always', refetchOnReconnect:'always'})
}
const Confirmacion = v.object({ok:v.literal(true), inversionista_id:Id})
export async function corregirContactoInversionista(persona:string, clave:string, revision:string, datos:DatosContacto) {
  const r = await cliente().rpc('inversionista_corregir_contacto_fn', {
    p_inversionista:persona,p_clave:clave,p_revision:revision,p_datos:datos as Json,
  })
  const confirmado = respuestaInversionistas(Confirmacion,r)
  if (confirmado.inversionista_id !== persona) throw new CrmApiError('No se confirmó la corrección de esta persona.', 'RESPUESTA_INCOMPLETA')
}
export async function corregirCoopacInversionista(persona:string, fuente:string, clave:string, revision:string, datos:DatosCorreccionCoopac) {
  const r = await cliente().rpc('inversionista_corregir_coopac_fn', {
    p_inversionista:persona,p_fuente:fuente,p_clave:clave,p_revision:revision,p_datos:datos as Json,
  })
  const confirmado = respuestaInversionistas(v.object({...Confirmacion.entries,fuente_id:Id}),r)
  if (confirmado.inversionista_id !== persona || confirmado.fuente_id !== fuente) throw new CrmApiError('No se confirmó la corrección de esta inversión.', 'RESPUESTA_INCOMPLETA')
}
export async function corregirDocumentoInversionista(persona:string, documento:GestionInversionista['documento'], tipo:string, numero:string, motivo:string) {
  const r = await cliente().rpc('corregir_documento_inversionista_fn', {
    p_inversionista:persona,p_tipo:tipo,p_documento:numero,p_motivo:motivo,
    ...(documento.id ? {p_identificador_anterior:documento.id} : {}),
  })
  respuestaInversionistas(v.object({ok:v.literal(true)}),r)
}
/** Cancela lecturas anteriores al guardado antes de pedir la nueva fotografía. */
export async function refrescarGestionInversionista(qc:QueryClient,actor:string) {
  const claves = [inversionistasKeys.actor(actor),postventaKeys.actor(actor),crmQueryKeys.clientes(),
    crmQueryKeys.contratos(),crmQueryKeys.operacionesCartera(),crmQueryKeys.metricas(),
    crmQueryKeys.metricasAmbito(),crmQueryKeys.leads(),crmQueryKeys.rentabilidad()]
  await Promise.all(claves.map(queryKey => qc.cancelQueries({queryKey})))
  await Promise.all(claves.map(queryKey => qc.invalidateQueries({queryKey})))
}
