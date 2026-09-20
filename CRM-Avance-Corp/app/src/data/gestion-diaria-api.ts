// Capa de datos de Gestión Diaria: la única que habla con `crm.registro_actividad_fn`.
// Valida la respuesta en la frontera (Valibot) y exige que el servidor haga eco
// de la ventana y el límite pedidos: una página que no corresponde a lo pedido
// se rechaza, nunca se pinta.
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import {
  RegistroPaginaSchema,
  limiteConSonda,
  tiposDePestana,
  type CursorRegistro,
  type FiltrosRegistro,
  type RegistroPagina,
} from '@/lib/gestion-diaria'

const DeshacerResultadoSchema = v.object({
  ok: v.literal(true),
  actividad_id: v.string(),
  lead_id: v.string(),
  tarea_cancelada: v.boolean(),
  descarte_revertido: v.boolean(),
  cita_no_restaurada: v.boolean(),
  ciclo_nuevo: v.boolean(),
  etapa: v.string(),
})
export type DeshacerResultado = v.InferOutput<typeof DeshacerResultadoSchema>

/** Deshace los EFECTOS de un resultado de llamada (≤ 24 h, solo el autor):
 *  cancela la tarea creada y revierte el descarte si sigue vigente. La llamada
 *  queda en el historial. El servidor rechaza con SQLSTATE y texto humano. */
export async function deshacerResultadoLlamada(actividadId: string): Promise<DeshacerResultado> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = await sb.schema('crm').rpc('deshacer_resultado_llamada', { p_actividad_id: actividadId })
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(DeshacerResultadoSchema, data)
  if (!parsed.success) throw new CrmApiError('El servidor no confirmó el deshacer.', 'GESTION_DIARIA_CONTRACT')
  return parsed.output
}

export async function listarRegistroActividad(
  filtros: FiltrosRegistro,
  cursor: CursorRegistro | null,
  limite: number,
  signal?: AbortSignal,
): Promise<RegistroPagina> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const tipos = tiposDePestana(filtros.pestana)
  let consulta = sb.schema('crm').rpc('registro_actividad_fn', {
    p_desde: filtros.dia,
    p_hasta: filtros.dia,
    p_analista_ids: filtros.analistaIds === null ? null : [...filtros.analistaIds],
    p_tipos: tipos === null ? null : [...tipos],
    p_etapa: filtros.etapa,
    p_limite: limiteConSonda(limite),
    p_antes_de: cursor?.antes_de ?? null,
    p_antes_id: cursor?.antes_id ?? null,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(RegistroPaginaSchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo confirmar el registro de actividad.', 'GESTION_DIARIA_CONTRACT')
  const pagina = parsed.output
  if (pagina.desde !== filtros.dia || pagina.hasta !== filtros.dia || pagina.limite !== limiteConSonda(limite)
    || pagina.items.length > limiteConSonda(limite)) {
    throw new CrmApiError('La página recibida no corresponde a lo pedido.', 'GESTION_DIARIA_CONTRACT')
  }
  return pagina
}
