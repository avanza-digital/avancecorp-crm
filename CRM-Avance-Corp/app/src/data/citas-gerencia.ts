import * as v from 'valibot'
import { useQuery } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import { crmQueryKeys } from './crm-queries'
import { CrmApiError } from './crm-api'
import { defaults, rango } from '@/components/citas/modelo'
import type { CitaConLead } from '@/components/citas/datos'
import type { DepositoEjemplo } from '@/components/citas/depositos'
import { horaLima } from '@/components/citas/contexto'

const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Id = v.pipe(v.string(), v.uuid())
const CitaSchema = v.object({
  id: Id, lead_id: Id, nombre: v.string(), telefono: v.string(),
  analista_id: v.nullable(Id), analista_nombre: v.string(), supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
  vence_en: Instante, estado: v.picklist(['pendiente','completada','no_show','cancelada','reprogramada']),
  cancelada_por: v.nullable(v.string()), modalidad: v.string(), origen: v.string(),
  moneda: v.picklist(['PEN','USD']), monto_estimado: v.pipe(v.number(),v.finite(),v.minValue(0)),
  resultado: v.string(), nota: v.string(), reagendada_de: v.nullable(Id), creado_en: Instante,
  asistencia_registrada_en: v.nullable(Instante), cierre_posterior: v.boolean(),
})
const CamposConsulta = {
  periodo: v.object({ desde: v.string(), hasta: v.string() }), generado_en: Instante,
  citas: v.pipe(v.array(CitaSchema),v.maxLength(10000)),
  citas_clientes: v.pipe(v.number(),v.integer(),v.minValue(0)),
}
export const ConsultaCitasSchema = v.variant('version',[
  v.object({ ...CamposConsulta, version:v.literal(1), disponibilidad_depositos:v.literal('sin_registro'), depositos:v.pipe(v.array(v.unknown()),v.length(0)) }),
  v.object({ ...CamposConsulta, version:v.literal(2), disponibilidad_depositos:v.literal('conversion_cliente'),
    conversiones:v.pipe(v.array(v.object({lead_id:Id,perfil_id:Id,convertido_en:Instante})),v.maxLength(10000)) }),
])
export type ConsultaCitasRpc = v.InferOutput<typeof ConsultaCitasSchema>
export function adaptarDepositos(datos: ConsultaCitasRpc): DepositoEjemplo[] {
  return datos.version===2 ? datos.conversiones.map(c => ({
    id:`conversion-${c.lead_id}`,leadId:c.lead_id,fuente:'conversion_cliente',
    depositadoEn:c.convertido_en,confirmadoEn:c.convertido_en,monto:null,moneda:null,
  })) : []
}
const fechaLima = (fecha: string) => new Intl.DateTimeFormat('en-CA', {timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(fecha))
const rotulo = (valor: string) => valor === 'sin_clasificar' ? 'Sin clasificar' : valor.replaceAll('_',' ').replace(/^./,c => c.toUpperCase())

export function adaptarCitas(datos: ConsultaCitasRpc): CitaConLead[] {
  const sucesoras = new Map<string, ConsultaCitasRpc['citas'][number]>()
  for (const cita of datos.citas) {
    if (!cita.reagendada_de) continue
    const clave = `${cita.reagendada_de}|${cita.lead_id}`
    if (!sucesoras.has(clave)) sucesoras.set(clave,cita)
  }
  return datos.citas.map(c => ({
    id:c.id,leadId:c.lead_id,nombre:c.nombre,telefono:c.telefono,analista:c.analista_id ?? 'sin_analista',
    analistaNombre:c.analista_nombre,supervisor:c.supervisor_nombre,supervisorId:c.supervisor_id ?? 'sin_supervisor',
    fecha:fechaLima(c.vence_en),hora:horaLima(c.vence_en),
    estado:c.estado==='pendiente' ? Date.parse(c.vence_en)<=Date.parse(datos.generado_en) ? 'vencida' : 'programada'
      : c.estado==='completada' ? 'realizada' : c.estado==='cancelada' && c.cancelada_por!=='asesor' ? 'sistema' : c.estado,
    modalidad:rotulo(c.modalidad),origen:rotulo(c.origen),moneda:c.moneda,monto:c.monto_estimado,
    resultado:rotulo(c.resultado),nota:c.nota,cerrado:c.cierre_posterior,
    seguimiento:c.estado==='completada' && !c.cierre_posterior,
    nuevaFecha:(() => { const siguiente = sucesoras.get(`${c.id}|${c.lead_id}`); return siguiente ? fechaLima(siguiente.vence_en) : null })(),
    ...(c.reagendada_de ? {citaAnteriorId:c.reagendada_de,reprogramadaEn:c.creado_en} : {}),
    ...(c.asistencia_registrada_en ? {asistioEn:c.asistencia_registrada_en} : {}),
  }))
}

export async function cargarCitasGerencia(mes: string, signal?: AbortSignal): Promise<ConsultaCitasRpc> {
  const [desde,hasta] = rango(defaults(mes))
  if (!desde) throw new CrmApiError('Selecciona un mes válido.','CITAS_PERIODO')
  if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.','CITAS_SIN_CONEXION')
  const peticion = sb.schema('crm').rpc('citas_gerencia_consulta_fn', {p_desde:desde,p_hasta:hasta})
  if (signal) peticion.abortSignal(signal)
  const {data,error} = await peticion
  if (error) throw new CrmApiError(error.code==='PGRST202'
    ? 'La consulta detallada de citas aún no está habilitada en este servidor.'
    : 'No se pudieron cargar las citas. Reintenta la consulta.',error.code)
  const resultado = v.safeParse(ConsultaCitasSchema,data)
  if (!resultado.success || resultado.output.periodo.desde!==desde || resultado.output.periodo.hasta!==hasta
    || new Set(resultado.output.citas.map(c => c.id)).size!==resultado.output.citas.length) {
    throw new CrmApiError('La respuesta de citas está incompleta o no corresponde a este mes.','CITAS_CONTRATO')
  }
  const datos=resultado.output
  if (datos.version===2) {
    const leads=new Set(datos.citas.map(c=>c.lead_id))
    if (new Set(datos.conversiones.map(c=>c.lead_id)).size!==datos.conversiones.length
      || datos.conversiones.some(c=>!leads.has(c.lead_id) || Date.parse(c.convertido_en)>Date.parse(datos.generado_en))) {
      throw new CrmApiError('La respuesta de conversiones no corresponde a esta consulta.','CITAS_CONTRATO')
    }
  }
  return resultado.output
}

export function useCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
  // Clave por actor/mes y sin placeholderData: nunca presenta otro período.
  return useQuery({
    queryKey:[...crmQueryKeys.metricas(),'citas-detalle',actorId,mes],
    queryFn:({signal}) => cargarCitasGerencia(mes,signal),
    enabled:habilitada && Boolean(actorId) && Boolean(rango(defaults(mes))[0]),
    staleTime:30_000,
    retry:1,
  })
}
