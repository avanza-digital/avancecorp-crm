import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { PulsoGerenciaSchema } from '@/lib/gestion-diaria-pulso'
import { HabitosGerenciaSchema } from '@/lib/gestion-diaria-habitos'
import { CrmApiError } from './crm-api'

async function consultar(nombre: 'gestion_diaria_pulso_fn' | 'gestion_diaria_habitos_fn',
  argumentos: { p_dia?: string; p_hasta?: string; p_dias?: number }, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc(nombre, argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  return data
}
export async function obtenerPulsoGerencia(dia: string, signal?: AbortSignal) {
  const resultado = v.safeParse(PulsoGerenciaSchema, await consultar('gestion_diaria_pulso_fn', { p_dia: dia }, signal))
  if (!resultado.success || resultado.output.dia !== dia) {
    throw new CrmApiError('No se pudo confirmar el pulso y el día solicitados.', 'GESTION_DIARIA_CONTRACT')
  }
  return resultado.output
}
export async function obtenerHabitosGerencia(hasta: string, dias: 7 | 14 | 30, signal?: AbortSignal) {
  const resultado = v.safeParse(HabitosGerenciaSchema, await consultar('gestion_diaria_habitos_fn', { p_hasta: hasta, p_dias: dias }, signal))
  if (!resultado.success || resultado.output.hasta !== hasta || resultado.output.dias_solicitados !== dias) {
    throw new CrmApiError('No se pudo confirmar el período de hábitos solicitado.', 'GESTION_DIARIA_CONTRACT')
  }
  return resultado.output
}
