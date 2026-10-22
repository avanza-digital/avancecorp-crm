import * as v from 'valibot'
import { useQuery } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import { crmQueryKeys } from './crm-queries'
import { CrmApiError } from './crm-api'
import { defaults, rango, type EstadoCita } from '@/components/citas/modelo'
import type { CitaConLead } from '@/components/citas/datos'
import type { DepositoEjemplo } from '@/components/citas/depositos'
import type { GestionCitas } from '@/components/citas/metas'
import { entrevistaCompatibleConVenta } from '@/components/citas/fecha-comercial'
import { horaLima } from '@/components/citas/contexto'
import { TestigoComercialCitasSchema } from '@/lib/gestion-citas'
import { FechaSchema } from '@/lib/esquemas-rpc'
import { CamposGestionMensualConEstado, EstadoAnalistaSchema } from '@/components/citas/gestion-estado'

const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Id = v.pipe(v.string(), v.uuid())
// Capital estimado del LEAD: null es un valor posible del servidor (base cargada sin capital, F5a). Este contrato
// se valida ENTERO: un solo null fuera de contrato apagaría todo el módulo de citas.
const MontoLead = v.nullable(v.pipe(v.number(),v.finite(),v.minValue(0)))
const CitaSchema = v.object({
  id: Id, lead_id: Id, nombre: v.string(), telefono: v.string(),
  analista_id: v.nullable(Id), analista_nombre: v.string(), supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
  vence_en: Instante, estado: v.picklist(['pendiente','completada','no_show','cancelada','reprogramada']),
  estado_comercial: v.optional(v.picklist(['vencida','programada','realizada','no_show','cancelada','reprogramada','sistema'])),
  cancelada_por: v.nullable(v.string()), modalidad: v.string(), origen: v.string(),
  moneda: v.picklist(['PEN','USD']), monto_estimado: MontoLead,
  resultado: v.string(), nota: v.string(), reagendada_de: v.nullable(Id), creado_en: Instante,
  asistencia_registrada_en: v.nullable(Instante), cierre_posterior: v.boolean(),
  manual_propio: v.optional(v.boolean()),
  registro_manual: v.optional(v.boolean()),
  // D-53 (bloque 2.14): el estado de hoy del analista responsable; opcional para leer también al servidor anterior.
  analista_estado: EstadoAnalistaSchema,
  // Fase 0 de la Proyección: opcional para leer también al servidor que aún no lo envía.
  es_cliente: v.optional(v.boolean()),
})
const CamposGestion = {
  citas_por_lead: v.pipe(v.number(),v.finite(),v.minValue(0.01),v.maxValue(10)),
  entrevistas_porcentaje: v.pipe(v.number(),v.finite(),v.minValue(1),v.maxValue(100)),
  depositos_porcentaje: v.pipe(v.number(),v.finite(),v.minValue(1),v.maxValue(100)),
  actividad_manuales: v.optional(v.picklist(['excluir','incluir'])),
  asignaciones: v.pipe(v.array(v.object({
    lead_id: Id, analista_id: Id, analista_nombre: v.string(), analista_estado: EstadoAnalistaSchema,
    supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
    asignado_en: Instante, manual_propio: v.boolean(),
    registro_manual: v.optional(v.boolean()),
    nombre: v.string(), telefono: v.string(), origen: v.string(),
    moneda: v.picklist(['PEN','USD']), monto_estimado: MontoLead,
  })),v.maxLength(10000)),
}
const GestionCitasSchema = v.variant('version', [
  v.object({ ...CamposGestion, version: v.literal(1) }),
  v.object({ ...CamposGestion, ...CamposGestionMensualConEstado, version: v.literal(2) }),
])
const CamposConsulta = {
  periodo: v.object({ desde: v.string(), hasta: v.string() }), generado_en: Instante,
  citas: v.pipe(v.array(CitaSchema),v.maxLength(10000)),
  citas_clientes: v.pipe(v.number(),v.integer(),v.minValue(0)),
  gestion: v.optional(GestionCitasSchema),
  // F2: clave nueva en la respuesta; opcional para leer también al servidor anterior.
  testigo: v.optional(TestigoComercialCitasSchema),
}
export const ConsultaCitasSchema = v.variant('version',[
  v.object({ ...CamposConsulta, version:v.literal(1), disponibilidad_depositos:v.literal('sin_registro'), depositos:v.pipe(v.array(v.unknown()),v.length(0)) }),
  v.object({ ...CamposConsulta, version:v.literal(2), disponibilidad_depositos:v.literal('conversion_cliente'), criterio_depositos:v.literal('fecha_comercial'),
    conversiones:v.pipe(v.array(v.object({lead_id:Id,perfil_id:Id,convertido_en:Instante,fecha_comercial:v.nullable(FechaSchema)})),v.maxLength(10000)) }),
])
export type ConsultaCitasRpc = v.InferOutput<typeof ConsultaCitasSchema>
type TareaCita = v.InferOutput<typeof CitaSchema>
export function adaptarDepositos(datos: ConsultaCitasRpc): DepositoEjemplo[] {
  return datos.version===2 ? datos.conversiones.filter(c => c.fecha_comercial !== null).map(c => ({
    id:`conversion-${c.lead_id}`,leadId:c.lead_id,fuente:'conversion_cliente',
    depositadoEn:c.convertido_en,confirmadoEn:c.convertido_en,fechaComercial:c.fecha_comercial!,monto:null,moneda:null,
  })) : []
}
export const fechaLima = (fecha: string) => new Intl.DateTimeFormat('en-CA', {timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(fecha))
const rotulo = (valor: string) => valor === 'sin_clasificar' ? 'Sin clasificar' : valor.replaceAll('_',' ').replace(/^./,c => c.toUpperCase())

export function adaptarGestion(datos: ConsultaCitasRpc): GestionCitas | undefined {
  const g = datos.gestion
  if (!g) return undefined
  return {
    citasPorLead:g.citas_por_lead,entrevistasPorcentaje:g.entrevistas_porcentaje,
    depositosPorcentaje:g.depositos_porcentaje,
    ...(g.actividad_manuales ? {actividadManuales:g.actividad_manuales} : {}),
    ...(g.version === 2 ? { avance: g, excluirManualesBase: g.control.configuracion.excluir_manuales_base } : {}),
    ...(datos.testigo ? { testigo: datos.testigo.comercial } : {}),
    asignaciones:g.asignaciones.map(l => ({
      id:l.analista_id,nombre:l.analista_nombre,supervisor:l.supervisor_nombre,
      supervisorId:l.supervisor_id ?? 'sin_supervisor',leadId:l.lead_id,nombreLead:l.nombre,
      telefono:l.telefono,asignadoEn:l.asignado_en,manualPropio:l.manual_propio,
      registroManual:l.registro_manual ?? l.manual_propio,
      origen:rotulo(l.origen),moneda:l.moneda,monto:l.monto_estimado,
      ...(l.analista_estado ? {estado:l.analista_estado} : {}),
    })),
  }
}

/** Estado de la tarea en el vocabulario de Citas (`ESTADOS`): una pendiente ya vencida al corte es «vencida» y
 * una cancelada que no canceló el asesor es «sistema». Lo comparten las citas con lead y las reuniones con
 * clientes sin lead de la Proyección (Fase 0b). */
export function estadoDeCita(c: { estado: TareaCita['estado']; vence_en: string; cancelada_por: string | null }, generadoEn: string): EstadoCita {
  return c.estado==='pendiente' ? Date.parse(c.vence_en)<=Date.parse(generadoEn) ? 'vencida' : 'programada'
    : c.estado==='completada' ? 'realizada' : c.estado==='cancelada' && c.cancelada_por!=='asesor' ? 'sistema' : c.estado
}

export function adaptarCitas(datos: ConsultaCitasRpc): CitaConLead[] {
  const comerciales = new Map(datos.version === 2 ? datos.conversiones.map(c => [c.lead_id, c.fecha_comercial]) : [])
  // La marca heredada comparaba el último cierre con vence_en por instante.
  // V2 conserva ese campo para clientes anteriores, pero aquí usa el día de la
  // asistencia (o de la cita pendiente), con las mismas exclusiones del servidor.
  const cierreCompatible = (c: ConsultaCitasRpc['citas'][number]) => datos.version === 2
    ? entrevistaCompatibleConVenta(c.asistencia_registrada_en ?? c.vence_en, comerciales.get(c.lead_id) ?? null)
    : c.cierre_posterior
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
    estado:c.estado_comercial ?? estadoDeCita(c,datos.generado_en),
    modalidad:rotulo(c.modalidad),origen:rotulo(c.origen),moneda:c.moneda,monto:c.monto_estimado,
    resultado:rotulo(c.resultado),nota:c.nota,cerrado:cierreCompatible(c),
    seguimiento:c.estado==='completada' && !cierreCompatible(c),
    nuevaFecha:(() => { const siguiente = sucesoras.get(`${c.id}|${c.lead_id}`); return siguiente ? fechaLima(siguiente.vence_en) : null })(),
    ...(c.reagendada_de ? {citaAnteriorId:c.reagendada_de,reprogramadaEn:c.creado_en} : {}),
    ...(c.asistencia_registrada_en ? {asistioEn:c.asistencia_registrada_en} : {}),
    ...(c.manual_propio !== undefined ? {manualPropio:c.manual_propio} : {}),
    creadoEn:c.creado_en,registroManual:c.registro_manual ?? c.manual_propio ?? false,
    ...(c.analista_estado ? {analistaEstado:c.analista_estado} : {}),
    ...(c.es_cliente !== undefined ? {esCliente:c.es_cliente} : {}),
  }))
}

export async function cargarCitasGerencia(mes: string, signal?: AbortSignal): Promise<ConsultaCitasRpc> {
  const [desde,hasta] = rango(defaults(mes))
  if (!desde) throw new CrmApiError('Selecciona un mes válido.','CITAS_PERIODO')
  if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.','CITAS_SIN_CONEXION')
  const parametros = {p_desde:desde,p_hasta:hasta}
  const consultar = (nombre: 'citas_gerencia_consulta_fn' | 'citas_gerencia_consulta_v2_fn') => {
    const peticion = sb!.schema('crm').rpc(nombre, parametros)
    if (signal) peticion.abortSignal(signal)
    return peticion
  }
  let {data,error} = await consultar('citas_gerencia_consulta_v2_fn')
  if (error?.code === 'PGRST202') ({data,error} = await consultar('citas_gerencia_consulta_fn'))
  if (error) throw new CrmApiError(error.code==='PGRST202'
    ? 'La consulta detallada de citas aún no está habilitada en este servidor.'
    : 'No se pudieron cargar las citas. Reintenta la consulta.',error.code)
  const resultado = v.safeParse(ConsultaCitasSchema,data)
  if (!resultado.success || resultado.output.periodo.desde!==desde || resultado.output.periodo.hasta!==hasta
    || new Set(resultado.output.citas.map(c => c.id)).size!==resultado.output.citas.length) {
    throw new CrmApiError('La respuesta de citas está incompleta o no corresponde a este mes.','CITAS_CONTRATO')
  }
  const datos=resultado.output
  if (datos.gestion) {
    const base=datos.gestion.asignaciones
    if (new Set(base.map(l=>`${l.lead_id}|${l.analista_id}`)).size!==base.length
      || base.some(l=>fechaLima(l.asignado_en)<desde || fechaLima(l.asignado_en)>hasta || Date.parse(l.asignado_en)>Date.parse(datos.generado_en))
      || datos.citas.some(c=>c.manual_propio===undefined)) {
      throw new CrmApiError('La base de leads asignados está incompleta o no corresponde a este mes.','CITAS_CONTRATO')
    }
    const g=datos.gestion
    if (g.version===2) {
      const valoracion = g.valoracion
      if (valoracion && (desde<'2026-10-01'
        || (valoracion.corte_id===null)!==(valoracion.cobertura.corte===null)
        || (valoracion.sellado && (valoracion.corte_id===null || valoracion.cobertura.estado!=='completo'))
        || (valoracion.corte_id===null && g.capital.length>0)
        || g.capital.some(k=>k.equivalente_pen===undefined || k.tasa===undefined || k.fecha_comercial===undefined
          || k.fecha_tc===undefined || k.politica_tc===undefined
          || Math.abs(k.monto*k.tasa-k.equivalente_pen)>0.00500001))) {
        throw new CrmApiError('El capital de Citas no corresponde a una valoración completa. Actualiza para reintentar.','CITAS_CONTRATO')
      }
      const poblacion=new Set(g.poblacion.map(p=>p.lead_id))
      const cierres=new Map(g.conversiones.map(c=>[c.lead_id,c]))
      const cfg=g.control.configuracion
      if (poblacion.size!==g.poblacion.length || cierres.size!==g.conversiones.length
        // Cada episodio de capital es un contrato O un cierre externo, una sola vez.
        || g.capital.some(k=>(k.contrato_id==null)===(k.cierre_externo_id==null))
        || new Set(g.capital.map(k=>k.contrato_id ?? k.cierre_externo_id)).size!==g.capital.length
        || g.asignaciones.some(p=>!poblacion.has(p.lead_id))
        || datos.citas.some(c=>!poblacion.has(c.lead_id) || c.registro_manual===undefined)
        || g.conversiones.some(c=>!poblacion.has(c.lead_id) || Date.parse(c.convertido_en)>Date.parse(datos.generado_en))
        // El capital del mes no exige lead; si lo trae y ese lead se convirtió,
        // el perfil cliente tiene que coincidir.
        || g.capital.some(k=>(k.lead_id!==null && k.perfil_id!==null && cierres.has(k.lead_id) && cierres.get(k.lead_id)!.perfil_id!==k.perfil_id)
          || fechaLima(k.fecha)<desde || fechaLima(k.fecha)>hasta || Date.parse(k.fecha)>Date.parse(datos.generado_en))
        || cfg.citas_por_lead!==g.citas_por_lead || cfg.entrevistas_porcentaje!==g.entrevistas_porcentaje
        || cfg.depositos_porcentaje!==g.depositos_porcentaje) {
        throw new CrmApiError('Las fuentes de gestión no corresponden a la consulta. Actualiza para reintentar.','CITAS_CONTRATO')
      }
    }
  }
  if (datos.version===2) {
    const leads=new Set(datos.citas.map(c=>c.lead_id))
    if (new Set(datos.conversiones.map(c=>c.lead_id)).size!==datos.conversiones.length
      || datos.conversiones.some(c=>!leads.has(c.lead_id) || Date.parse(c.convertido_en)>Date.parse(datos.generado_en))) {
      throw new CrmApiError('La respuesta de conversiones no corresponde a esta consulta.','CITAS_CONTRATO')
    }
  }
  return resultado.output
}

/** Cadencia y caché de las lecturas de Citas; la comparten las reuniones con clientes de la Proyección. */
export const CADENCIA_CITAS = {
  staleTime:30_000,
  // Incluye cambios de otros analistas y el paso de programada a vencida.
  refetchInterval:60_000,
  refetchIntervalInBackground:false,
  refetchOnWindowFocus:true,
  refetchOnReconnect:true,
} as const

/** Opciones de la consulta mensual: las comparten el mes de la pantalla y los meses del rango de Proyección. */
export function opcionesCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
  // Clave por actor/mes y sin placeholderData: nunca presenta otro período.
  return {
    queryKey:crmQueryKeys.citasGerencia(actorId,mes),
    queryFn:({signal}: {signal: AbortSignal}) => cargarCitasGerencia(mes,signal),
    enabled:habilitada && Boolean(actorId) && Boolean(rango(defaults(mes))[0]),
    ...CADENCIA_CITAS,
    retry:1,
  }
}

export function useCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
  return useQuery(opcionesCitasGerencia(mes, actorId, habilitada))
}

const ultimoPorLead = <T,>(listas: T[][], clave: (fila: T) => string) => [...new Map(listas.flat().map(fila => [clave(fila), fila])).values()]

/** Fusiona meses completos (en orden) para un rango que cruza meses. Las citas se
 * concatenan sin repetir id; población, conversiones y asignaciones se deduplican
 * por lead (gana el mes más reciente); la configuración es la del último mes. */
export function fusionarConsultasCitas(consultas: ConsultaCitasRpc[]): { citas: CitaConLead[]; gestion: GestionCitas | undefined; corte: string } {
  const citas = [...new Map(consultas.flatMap(adaptarCitas).map(c => [c.id, c])).values()]
  const corte = consultas.map(c => c.generado_en).reduce((a, b) => Date.parse(b) > Date.parse(a) ? b : a, consultas[0]?.generado_en ?? new Date(0).toISOString())
  const gestiones = consultas.map(adaptarGestion).filter((g): g is GestionCitas => g !== undefined)
  const ultima = gestiones.at(-1)
  if (!ultima) return { citas, gestion: undefined, corte }
  const avances = gestiones.flatMap(g => g.avance ? [g.avance] : [])
  const gestion: GestionCitas = {
    ...ultima,
    asignaciones: ultimoPorLead(gestiones.map(g => g.asignaciones), l => l.leadId),
    ...(ultima.avance ? { avance: {
      ...ultima.avance,
      poblacion: ultimoPorLead(avances.map(a => a.poblacion), p => p.lead_id),
      conversiones: ultimoPorLead(avances.map(a => a.conversiones), c => c.lead_id),
      capital: ultimoPorLead(avances.map(a => a.capital), k => k.contrato_id ?? k.cierre_externo_id ?? `${k.lead_id}|${k.fecha}`),
    } } : {}),
  }
  return { citas, gestion, corte }
}
