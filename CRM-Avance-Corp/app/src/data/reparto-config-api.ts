import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'

const ConfiguracionRepartoSchema = v.object({
  version: v.literal(1),
  coordinacion_libre: v.boolean(),
  revision: v.pipe(v.number(), v.integer(), v.minValue(1)),
  actualizado_en: v.string(),
})

export type ConfiguracionReparto = v.InferOutput<typeof ConfiguracionRepartoSchema>

function parsearConfiguracion(data: unknown): ConfiguracionReparto {
  const resultado = v.safeParse(ConfiguracionRepartoSchema, data)
  if (!resultado.success) {
    throw new CrmApiError('No se pudo comprobar el estado del reparto libre.', 'CONTRATO_REPARTO_INVALIDO')
  }
  return resultado.output
}

export async function obtenerConfiguracionReparto(signal?: AbortSignal): Promise<ConfiguracionReparto> {
  if (!sb) throw new CrmApiError('Sin conexión con el CRM.', 'SIN_CONEXION')
  let consulta = sb.schema('crm').rpc('configuracion_reparto_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError('No se pudo consultar el reparto libre.', error.code)
  return parsearConfiguracion(data)
}

export async function guardarConfiguracionReparto(
  libre: boolean,
  revision: number,
): Promise<ConfiguracionReparto> {
  if (!sb) throw new CrmApiError('Sin conexión con el CRM.', 'SIN_CONEXION')
  const { data, error } = await sb.schema('crm').rpc('guardar_configuracion_reparto_fn', {
    p_libre: libre, p_revision: revision,
  })
  if (error) {
    throw new CrmApiError(error.code === 'PT409'
      ? 'Otra sesión cambió el reparto libre. Revisa el estado actualizado antes de volver a cambiarlo.'
      : 'No se pudo guardar el reparto libre. Comprueba su estado antes de reintentar.', error.code)
  }
  return parsearConfiguracion(data)
}
