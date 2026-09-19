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
