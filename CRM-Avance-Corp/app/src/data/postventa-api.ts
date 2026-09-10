import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import type { Database, Json } from '@/lib/database.types'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'
import { EstadoPostventaSchema, TareaPostventaSchema, ResultadoAgendaPostventaSchema,
  FichaPostventaSchema, RetiroPostventaSchema, VencimientosPostventaSchema } from '@/lib/postventa'
import type { EmpresaInversion } from '@/lib/inversionistas'

type Funciones = Database['crm']['Functions']
function cliente() {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb
}
export async function estadoPostventa(signal?: AbortSignal) {
  const q = cliente().schema('crm').rpc('postventa_estado_fn')
  const r = await (signal ? q.abortSignal(signal) : q)
  if (r.error?.code === 'PGRST202') return {version: 1 as const, habilitada: false}
  return respuestaInversionistas(EstadoPostventaSchema, r)
}
export async function listarAgendaPostventa(signal?: AbortSignal) {
  const q = cliente().schema('crm').rpc('postventa_agenda_fn')
  const r = await (signal ? q.abortSignal(signal) : q)
  if (r.error?.code === 'PGRST202') return []
  const tareas = respuestaInversionistas(v.array(TareaPostventaSchema), r)
  if (new Set(tareas.map(t => t.id)).size !== tareas.length || tareas.some(t => t.lead_id || t.perfil_id || !t.activo || t.estado !== 'pendiente')) {
    throw new CrmApiError('No se pudo verificar la agenda de postventa.', 'RESPUESTA_INCOMPLETA')
  }
  return tareas
}
export async function personaDePerfil(perfil: string, signal?: AbortSignal) {
  const q = cliente().schema('crm').rpc('postventa_perfil_fn', {p_perfil: perfil})
  const r = await (signal ? q.abortSignal(signal) : q)
  if (r.error?.code === 'PGRST202') return {habilitada: false, inversionista_id: null}
  return respuestaInversionistas(v.object({habilitada: v.boolean(), inversionista_id: v.nullable(v.pipe(v.string(), v.uuid()))}), r)
}
export async function fichaPostventa(persona: string, signal?: AbortSignal) {
  const q = cliente().schema('crm').rpc('postventa_ficha_fn', {p_inversionista: persona})
  const r = await (signal ? q.abortSignal(signal) : q)
  if (r.error?.code === 'PGRST202') return {version: 1 as const, habilitada: false, retiros: []}
  return respuestaInversionistas(FichaPostventaSchema, r)
}
export async function vencimientosPostventa(empresa: EmpresaInversion | '', pagina: number, signal: AbortSignal) {
  const r = await cliente().schema('crm').rpc('postventa_vencimientos_fn', {p_pagina: pagina,
    ...(empresa ? {p_empresa: empresa} : {}),
  }).abortSignal(signal)
  if (r.error?.code === 'PGRST202') return {version: 1 as const, habilitada: false, pagina: 1, tamano: 25 as const, total: 0, filas: []}
  const resultado = respuestaInversionistas(VencimientosPostventaSchema, r)
  if (resultado.filas.length !== Math.max(0, Math.min(25, resultado.total - (pagina - 1) * 25))
    || new Set(resultado.filas.map(f => `${f.empresa}:${f.fuente_id}`)).size !== resultado.filas.length) {
    throw new CrmApiError('Los vencimientos llegaron incompletos.', 'RESPUESTA_INCOMPLETA')
  }
  return resultado
}
export async function agendarPostventa(args: Funciones['postventa_agendar_fn']['Args']) {
  return respuestaInversionistas(ResultadoAgendaPostventaSchema, await cliente().schema('crm').rpc('postventa_agendar_fn', args))
}
export async function gestionarTareaPostventa(args: Funciones['postventa_tarea_fn']['Args']) {
  return respuestaInversionistas(ResultadoAgendaPostventaSchema, await cliente().schema('crm').rpc('postventa_tarea_fn', args))
}
export async function cambiarVetoPostventa(args: Funciones['postventa_veto_fn']['Args']) {
  return respuestaInversionistas(v.object({ok: v.literal(true), no_contactar: v.boolean()}), await cliente().schema('crm').rpc('postventa_veto_fn', args))
}
export async function solicitarRetiroPostventa(args: Funciones['postventa_solicitar_retiro_fn']['Args']) {
  return respuestaInversionistas(v.object({ok: v.literal(true), retiro: RetiroPostventaSchema}), await cliente().schema('crm').rpc('postventa_solicitar_retiro_fn', args))
}
export async function revisarRetiroPostventa(args: Funciones['postventa_revisar_retiro_fn']['Args']) {
  return respuestaInversionistas(v.object({ok: v.literal(true), retiro: RetiroPostventaSchema}), await cliente().schema('crm').rpc('postventa_revisar_retiro_fn', args))
}
export async function asignarResponsablePostventa(persona: string, responsable: string, motivo: string) {
  return respuestaInversionistas(v.looseObject({ok: v.literal(true)}), await cliente().schema('crm').rpc('reasignar_responsable_relacion_fn', {
    p_inversionista: persona, p_nuevo_responsable: responsable, p_motivo: motivo,
  }))
}
export type DatosAgendaPostventa = Exclude<Json, null | string | number | boolean | Json[]>
