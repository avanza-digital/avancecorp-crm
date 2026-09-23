// Capa de datos de Gestión Diaria: la única que habla con `crm.registro_actividad_fn`
// y `crm.gestion_diaria_analista_fn`.
// Valida la respuesta en la frontera (Valibot) y exige que el servidor haga eco
// de la ventana y el límite pedidos: una página que no corresponde a lo pedido
// se rechaza, nunca se pinta.
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { soloPresentes } from './argumentos-rpc'
import { CrmApiError } from './crm-api'
import {
  RegistroPaginaSchema,
  limiteConSonda,
  tiposDePestana,
  type CursorRegistro,
  type FiltrosRegistro,
  type RegistroPagina,
} from '@/lib/gestion-diaria'
import { DiaAnalistaSchema, type DiaAnalista } from '@/lib/gestion-diaria-analista'
import { DiaEquipoSchema, type DiaEquipo } from '@/lib/gestion-diaria-equipo'

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
  // Los opcionales se OMITEN en vez de mandarse en null: en el servidor todos
  // valen NULL por defecto (mismo resultado) y el tipo generado los declara `x?: T`.
  let consulta = sb.schema('crm').rpc('registro_actividad_fn', {
    p_desde: filtros.dia,
    p_hasta: filtros.dia,
    p_limite: limiteConSonda(limite),
    ...soloPresentes({
      p_analista_ids: filtros.analistaIds === null ? null : [...filtros.analistaIds],
      p_tipos: tipos === null ? null : [...tipos],
      p_etapa: filtros.etapa,
      p_antes_de: cursor?.antes_de,
      p_antes_id: cursor?.antes_id,
    }),
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

/** El día de un analista (Fase 3): marcador, compromisos, señales de cartera y
 *  descartes con su «Deshacer». `p_analista_id` null = el actor; un analista
 *  solo puede pedir el suyo (el servidor responde 42501, no un día vacío).
 *  Se exige ECO del día y del analista pedidos: una respuesta que no
 *  corresponde a lo pedido se rechaza, nunca se pinta. */
export async function obtenerDiaAnalista(
  dia: string | null,
  analistaId: string | null,
  signal?: AbortSignal,
): Promise<DiaAnalista> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('gestion_diaria_analista_fn',
    soloPresentes({ p_dia: dia, p_analista_id: analistaId }))
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(DiaAnalistaSchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo confirmar el día del analista.', 'GESTION_DIARIA_CONTRACT')
  const respuesta = parsed.output
  if ((dia !== null && respuesta.dia !== dia) || (analistaId !== null && respuesta.analista_id !== analistaId)) {
    throw new CrmApiError('El día recibido no corresponde a lo pedido.', 'GESTION_DIARIA_CONTRACT')
  }
  return respuesta
}

/** Foto completa del equipo: el eco de día y supervisor evita mezclar ámbitos. */
export async function obtenerDiaEquipo(dia: string, supervisorId: string, signal?: AbortSignal): Promise<DiaEquipo> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('gestion_diaria_equipo_fn', { p_dia: dia, p_supervisor_id: supervisorId })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const resultado = v.safeParse(DiaEquipoSchema, data)
  if (!resultado.success || resultado.output.dia !== dia || resultado.output.supervisor_id !== supervisorId) {
    throw new CrmApiError('No se pudo confirmar el equipo y el día solicitados.', 'GESTION_DIARIA_CONTRACT')
  }
  return resultado.output
}
