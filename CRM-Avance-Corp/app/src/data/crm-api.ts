import { DocumentoLeadSchema } from '@/lib/documento-lead'
import { TareaRowSchema } from '@/lib/tarea-schema'
import * as v from 'valibot'
import { ESTADOS_SOLICITUD_TASA_VIVOS } from '@/lib/rentabilidad'
import { sb, type ClienteCrm } from '@/lib/supabase'
import type { Database, Json } from '@/lib/database.types'
import { idCorrelacion, registrarError } from '@/lib/observabilidad'
import type { SenalesLead } from '@/lib/historial-lead'
import {
  CATEGORIAS_INTERES,
  ETAPAS,
  GENEROS,
  MOTIVOS_DESCARTE,
  ORIGENES_TODOS,
  TERMINALES,
  TIPOS_ACTIVIDAD,
  type Actividad,
  type ActividadReciente,
  type AgendaRepartoDiaria,
  type AsignacionAgendaReparto,
  type CategoriaInteres,
  type ColaLead,
  type DestinoAgendaReparto,
  type DiaAgendaReparto,
  type DistribucionAnalista,
  type DistribucionSupervisor,
  type EpisodioRescateDescarte,
  type HistorialDerivacion,
  type Etapa,
  type Lead,
  type LeadDescartado,
  type MesRescateDescartes,
  type Miembro,
  type MotivoDescarte,
  type Origen,
  type Procedencia,
  type PanelDistribucionReparto,
  type SupervisorReparto,
  type Tarea,
  type TipoActividad,
  type ModalidadReunion,
  type MotivoNoRealizada,
  type ResultadoReunion,
  type RespuestaReprogramarReunion,
} from '@/lib/tipos'
import type { CategoriaContrato, CuotaCronograma, ModalidadContrato, TipoInteres } from '@/lib/cronograma'
import { esMoneda, type Moneda } from '@/lib/format'
import { SIN_SUPERVISOR_ID, type FilaFacturacionDia } from '@/lib/facturacion'

// Se re-exporta desde el modelo, que es donde vive el concepto: una sola
// definición para el mapeo de la RPC y para el roster de la pantalla.
export { SIN_SUPERVISOR_ID }
import {
  ESTADOS_CONTRATO,
  ESTADOS_CUOTA,
  type ActividadCliente,
  type ClienteBasico,
  type ClienteDetalle,
  type ClienteFichaComercial,
  type ContratoRow,
  type CuentaBancariaSeleccionable,
  type CuentaPagoContratoInput,
  type Cuota,
  type OperacionCartera,
  type ResumenCarteraClientes,
  type Titular,
  type TitularInput,
} from '@/lib/clientes-tipos'
import { TAMANO_PAGINA_CARTERA, normalizarBusquedaCartera, textoBuscable, type GestionCartera } from '@/lib/cartera-keyset'
import { ConteosPotencialSchema, totalConteosPotencial, type ConteosPotencial, type FiltroPotencial } from '@/lib/potencial'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento, type DocumentoIdentidad, type CorreccionDocumentoLead } from '@/lib/documento'
import { CierresExternosSchema, COOPERATIVAS, type CierresExternos, type Cooperativa } from '@/lib/cierres-externos'
import { CierresEstadoSchema, MAX_LEADS_ESTADO, type CierreEstado } from '@/lib/cierre-estado'
import { ConversionEstadoSchema, type ConversionEstado } from '@/lib/conversion-estado'
import type { SeccionBancariaForm } from '@/lib/cliente-form-logica'
import type { FilaAltasAnalista, FilaCapitalMes, FilaPagosMes, FilaVencimientos } from '@/lib/metricas'
import {
  MetricasDistribucionLeadsV3Schema,
  type MetricasDistribucionLeadsV3,
} from '@/lib/metricas-distribucion'
import { MetricasAgendaSchema, type MetricasAgenda } from '@/lib/metricas-agenda'
import { MetricasConversionesSchema, type MetricasConversiones } from '@/lib/metricas-conversiones'
import { MetricasConversionesEquipoSchema, type MetricasConversionesEquipo } from '@/lib/metricas-conversiones-equipo'
import { ConversionMensualSchema, type ConversionMensual } from '@/lib/conversion-mensual'
import { RankingOrigenVendedorSchema, type RankingOrigenVendedor } from '@/lib/ranking-origen'
import { MetricasReunionesSchema, type MetricasReuniones } from '@/lib/metricas-reuniones'
import { ConfiguracionMetasSchema, type ConfiguracionMetas } from '@/lib/metas-versionadas'
import { CierreMesEstadoSchema, type CierreMesEstadoRpc } from '@/lib/cierre-de-mes'
import { CumplimientoMetasSchema, type CumplimientoMetasRpc } from '@/lib/objetivos'
import {
  DisponibilidadLeadSchema,
  ResultadoCreacionLeadAtomicaSchema,
  ResultadoTomaLeadSchema,
  presentarDisponibilidadLead,
  type DisponibilidadLead,
  type ResultadoCreacionLeadAtomica,
  type ResultadoTomaLead,
} from '@/lib/disponibilidad-lead'
import {
  RecordatorioDisponibilidadSchema,
  RecordatoriosCampanaSchema,
  type RecordatorioCampana,
  type RecordatorioDisponibilidad,
} from '@/lib/recordatorios-disponibilidad'
import {
  AsientosReconocimientoSchema,
  type AccionReconocimiento,
  type AsientoReconocimiento,
} from '@/lib/reconocimientos-alertas'
import type { SeveridadAlerta } from '@/lib/alertas'
import {
  ResumenCarteraSchema,
  VENTANA_CONVERTIDOS_DIAS,
  type ResumenCartera,
} from '@/lib/resumen-cartera'
import { ColaAccionSchema, LIMITE_COLA_ACCION, type ColaAccion } from '@/lib/cola-accion'
import { FilaBaseGestionSchema, type FilaBaseGestion } from '@/lib/base-gestion'
import { MetricasVendedoresSchema, type MetricasVendedoresPayload } from '@/lib/metricas-vendedores'
import {
  ReporteDerivacionesEquipoSchema,
  ResultadoDerivarLeadsEquipoSchema,
  ResultadoRevertirDerivacionEquipoSchema,
  type ReporteDerivacionesEquipo,
  type ResultadoDerivarLeadsEquipo,
  type ResultadoRevertirDerivacionEquipo,
} from '@/lib/reporte-derivaciones-equipo'
import {
  LeadsRecibidosAnalistaSchema,
  leadsRecibidosAnalistaConsistente,
  type LeadsRecibidosAnalista,
} from '@/lib/leads-recibidos-analista'
import {
  ReporteDerivacionesCoordinacionSchema,
  reporteDerivacionesCoordinacionConsistente,
  type ReporteDerivacionesCoordinacion,
} from '@/lib/reporte-derivaciones-coordinacion'
import {
  ConversionCoordinacionSchema,
  conversionCoordinacionConsistente,
  fechasDeConsulta,
  hoyLima,
  motivoConsultaInvalida,
  type ConsultaConversion,
  type ConversionCoordinacion,
} from '@/lib/conversion-coordinacion'
import { ESTADOS_CONTRATO_PDF, type EstadoContratoPdf } from '@/lib/contrato-pdf-archivo'
import { ResumenRepartoSchema, type ResumenReparto } from '@/lib/resumen-reparto'
import { IngresosRepartoMesSchema, inicioDeMes, type IngresosRepartoMes } from '@/lib/ingresos-reparto'
import {
  InicioAyudaVendedorSchema,
  ResultadoConsultaAyudaVendedorSchema,
  type InicioAyudaVendedor,
  type ResultadoConsultaAyudaVendedor,
} from '@/lib/ayuda-vendedor'
import type { Vista } from '@/lib/router'
import { EnteroNoNegativoRpcSchema, FechaSchema } from '@/lib/esquemas-rpc'
import { presentarCitas } from '@/lib/terminologia'
import { conGestionVigente } from './gestion-vigente'

export type { DisponibilidadLead, ResultadoCreacionLeadAtomica, ResultadoTomaLead } from '@/lib/disponibilidad-lead'
export type { RecordatorioDisponibilidad } from '@/lib/recordatorios-disponibilidad'

export const TAMANO_PAGINA_LEADS = 50
const MAX_TAMANO_PAGINA = 100

const COLUMNAS_LEAD = [
  'id',
  'nombre_completo',
  'telefono',
  'telefono_alternativo',
  'telefono_alternativo_crudo',
  'correo',
  'dni',
  'genero',
  'fecha_nacimiento',
  'distrito',
  'origen',
  'etapa',
  'motivo_descarte',
  'monto_estimado',
  'moneda',
  'categoria_interes',
  'vendedor_id',
  'asignado_supervisor_id',
  'creado_en',
  'tenencia_desde',
  // Sello del cierre GANADO (trigger del servidor, inmutable para el cliente
  // API). Sin ella, el "mes de cierre" salía de `actualizado_en` — que CUALQUIER
  // edición reescribe — y corregirle el teléfono a un convertido de agosto lo
  // mudaba al mes de la corrección: un cierre falso en un mes y uno de menos en
  // el real. Ver lib/cierres-del-mes.ts.
  'convertido_en',
  'contrato_id',
  'actualizado_en',
  'activo',
  'nota',
  // Ley 29571 "No Insista": ya tenía GRANT SELECT desde F0, pero nunca se pidió
  // — sin ella el kill-switch legal de motor-siguiente.ts no podía dispararse.
  'no_contactar',
  // Procedencia del alta (ver Lead.procedencia). Las dos columnas tienen GRANT
  // SELECT para authenticated desde el 01/09; el mapper deriva `procedencia` con
  // la MISMA regla que la RPC de la cartera, para que el drawer (que lee el
  // ámbito) y el listado (que lee la RPC) cuenten la misma historia.
  'alta_manual',
  'creado_por',
].join(',')

// Validación en runtime del borde con Supabase (los unions de TS se borran al
// compilar: un dato viejo o una migración a medias entrarían "compilando
// limpio"). Los picklist salen de los MISMOS catálogos de tipos.ts — una sola
// fuente de verdad para el CHECK, el union y el parser.
const MontoEstimadoSchema = v.pipe(
  v.union([v.number(), v.string()]),
  v.check((valor) => Number.isFinite(Number(valor)) && Number(valor) > 0),
)

const LeadRowSchema = v.object({
  id: v.string(),
  nombre_completo: v.string(),
  telefono: v.string(),
  telefono_alternativo: v.optional(v.nullable(v.string())),
  telefono_alternativo_crudo: v.optional(v.nullable(v.string())),
  correo: v.nullable(v.string()),
  dni: v.nullable(v.string()),
  // Mismo catálogo que el CHECK leads_genero_valido y el union Genero.
  // OPCIONALES a propósito (no solo nullable): si el frontend llegara a correr
  // contra una base sin la migración, el lead debe seguir mostrándose sin
  // silueta — jamás desaparecer de la cartera por un campo cosmético.
  genero: v.optional(v.nullable(v.picklist(GENEROS.map((g) => g.k)))),
  fecha_nacimiento: v.optional(v.nullable(v.string())),
  distrito: v.nullable(v.string()),
  origen: v.picklist(ORIGENES_TODOS.map((o) => o.k)),
  // Procedencia: la RPC de la cartera manda `procedencia` + `cargado_por` ya
  // resueltos; el ámbito (select directo) manda las columnas crudas
  // `alta_manual` + `creado_por` y el mapper deriva. Todo opcional: un servidor
  // anterior a la migración no lo devuelve y el lead debe seguir listándose
  // (sin chip) igual.
  procedencia: v.optional(v.nullable(v.picklist(['sistema', 'manual']))),
  reasignado: v.optional(v.boolean()),
  cargado_por: v.optional(v.nullable(v.string())),
  alta_manual: v.optional(v.nullable(v.boolean())),
  creado_por: v.optional(v.nullable(v.string())),
  etapa: v.picklist([...ETAPAS.map((e) => e.k), ...TERMINALES.map((t) => t.k)]),
  motivo_descarte: v.nullable(v.picklist(MOTIVOS_DESCARTE.map((m) => m.k))),
  // numeric con CHECK de rango/2 decimales: PostgREST puede serializarlo como string
  monto_estimado: MontoEstimadoSchema,
  moneda: v.picklist(['PEN', 'USD']),
  categoria_interes: v.nullable(v.picklist(CATEGORIAS_INTERES.map((c) => c.k))),
  vendedor_id: v.nullable(v.string()),
  asignado_supervisor_id: v.nullable(v.string()),
  creado_en: v.string(),
  // OPCIONAL a propósito, igual que `genero`: si el front corriera contra una
  // base sin la migración de tenencia, el lead debe seguir apareciendo en la
  // cartera — la cola degrada a medir por `creado_en`, que es el comportamiento
  // viejo, en vez de vaciarse.
  tenencia_desde: v.optional(v.nullable(v.string())),
  // OPCIONAL por la misma razón que `tenencia_desde`: contra una base sin la
  // columna la cartera debe seguir cargando (el mes de cierre degrada al
  // comportamiento viejo), nunca vaciarse.
  convertido_en: v.optional(v.nullable(v.string())),
  contrato_id: v.optional(v.nullable(v.string())),
  actualizado_en: v.string(),
  activo: v.boolean(),
  nota: v.nullable(v.string()),
  // Opcional por la misma razón que tenencia_desde: una base sin la columna no
  // debe vaciar la cartera. Ausente ⇒ se trata como false (no hay veto legal
  // conocido), que es exactamente el comportamiento previo a esta entrega.
  no_contactar: v.optional(v.nullable(v.boolean())),
})

type LeadRow = v.InferOutput<typeof LeadRowSchema>

export interface FiltrosLeads {
  pagina: number
  tamano?: number
  texto?: string
  etapa?: Etapa | 'todas'
  vendedorId?: string | 'todos' | 'sin_asignar'
  incluirInactivos?: boolean
}

export interface Pagina<T> {
  items: T[]
  pagina: number
  tamano: number
  total: number
  paginas: number
}

export class CrmApiError extends Error {
  readonly code: string
  readonly correlationId: string

  constructor(message: string, code = 'CRM_API_ERROR', correlationId = idCorrelacion()) {
    super(message)
    this.name = 'CrmApiError'
    this.code = code
    this.correlationId = correlationId
  }
}

// ── Alarma de topes (F0 del plan de escalabilidad, 2026-08-08) ────────────────
// Cuando una lectura devuelve EXACTAMENTE su tope, lo más probable es que el
// servidor tenía más filas y el recorte fue MUDO: la pantalla miente por
// omisión (y muerde primero los leads menos tocados — los dormidos). Se avisa
// por registrarError (canal sin PII, llega a Sentry cuando haya DSN) para
// enterarse MESES antes de chocar el techo. Falso positivo posible (exactamente
// N filas reales): aceptado — es alarma de tendencia, no error duro, por eso
// NO lanza ni degrada la respuesta.
function avisarTopeAlcanzado(lectura: string, tope: number, recibidas: number): void {
  if (recibidas < tope) return
  registrarError(
    'crm_api.tope_alcanzado',
    new CrmApiError(`La lectura «${lectura}» devolvió su tope de ${tope} filas.`, 'TOPE_ALCANZADO'),
    { lectura, tope },
  )
}

/**
 * Mensaje MOSTRABLE de un fallo de esta capa: los CrmApiError ya traen su texto
 * es-PE (este módulo los traduce con código estable); cualquier otra cosa
 * (TypeError de red, bug) cae al texto por defecto de la pantalla — jamás un
 * `message` crudo en inglés frente al usuario. La variante del store
 * (`persistir`) sigue LOCAL a propósito: además excluye POSTGREST_ERROR porque
 * su mensaje genérico es de lectura y no sirve como feedback de una mutación.
 */
export function mensajeDeError(e: unknown, porDefecto: string): string {
  return presentarCitas(e instanceof CrmApiError ? e.message : porDefecto)
}

/**
 * PostgREST acepta NULL explícito en CUALQUIER parámetro; los tipos que genera
 * el CLI no lo modelan (un parámetro SIN default se tipa sin `| null`). Este
 * cast documenta esa brecha SIN cambiar el payload: el null SÍ viaja, igual
 * que siempre. Solo para parámetros SIN DEFAULT (verificados contra el
 * catálogo de producción el 16/08, `pg_get_function_arguments`); si el
 * parámetro tiene DEFAULT NULL, lo correcto es `?? undefined` — omitir la
 * clave y dejar que el default haga su trabajo, que es lo mismo que mandarla.
 */
export function nuloExplicito<T>(valor: T | null): T {
  return valor as T
}

/**
 * Quita las claves cuyo valor es `undefined`. Los args opcionales del tipado
 * generado exigen OMITIR la clave bajo `exactOptionalPropertyTypes` (ni null
 * ni undefined explícitos) — y omitirla es EXACTAMENTE lo que JSON.stringify
 * ya hacía en el cable con los undefined: cero cambio de payload; PostgREST
 * resuelve el DEFAULT del parámetro ausente (DEFAULT NULL en los catalogados).
 */
export function sinIndefinidos<T extends Record<string, unknown>>(
  args: T,
): { [K in keyof T]: Exclude<T[K], undefined> } {
  return Object.fromEntries(Object.entries(args).filter(([, valor]) => valor !== undefined)) as {
    [K in keyof T]: Exclude<T[K], undefined>
  }
}

function cliente(): ClienteCrm {
  if (!sb) {
    const error = new CrmApiError('Supabase no está configurado.', 'SUPABASE_NOT_CONFIGURED')
    registrarError('crm.cliente_no_disponible', error)
    throw error
  }
  return sb
}

// ── Centro de ayuda del analista — contenido y decisión solo en servidor ────

function falloContratoAyuda(evento: string): CrmApiError {
  const fallo = new CrmApiError('El servidor devolvió una respuesta de ayuda no reconocida.', 'ROW_CONTRACT')
  registrarError(evento, fallo)
  return fallo
}

/** Preguntas publicadas y ordenadas por la pantalla actual. */
export async function obtenerInicioAyudaVendedor(vista: Vista, signal?: AbortSignal): Promise<InicioAyudaVendedor> {
  let peticion = cliente().schema('crm').rpc('ayuda_vendedor_inicio', {
    p_vista: vista,
  })
  if (signal) peticion = peticion.abortSignal(signal)
  const { data, error } = await peticion
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar las consultas frecuentes.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.ayuda.inicio_fallido', fallo, { vista })
    throw fallo
  }
  const resultado = v.safeParse(InicioAyudaVendedorSchema, data)
  if (!resultado.success) {
    throw falloContratoAyuda('crm.ayuda.inicio_contrato_invalido')
  }
  return resultado.output
}

/**
 * Consulta el manual aprobado. El texto solo viaja a la RPC; nunca se adjunta
 * a observabilidad del navegador, donde podría contener datos de un cliente.
 */
export async function consultarAyudaVendedor(
  consulta: string,
  vista: Vista,
  signal?: AbortSignal,
): Promise<ResultadoConsultaAyudaVendedor> {
  const limpia = consulta.trim()
  if (limpia.length < 2 || limpia.length > 240) {
    throw new CrmApiError('Escribe una consulta de 2 a 240 caracteres.', 'AYUDA_CONSULTA_INVALIDA')
  }

  let peticion = cliente().schema('crm').rpc('consultar_ayuda_vendedor', {
    p_consulta: limpia,
    p_vista: vista,
  })
  if (signal) peticion = peticion.abortSignal(signal)
  const { data, error } = await peticion
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      'No se pudo consultar el manual. Intenta nuevamente.',
      error.code || 'POSTGREST_ERROR',
    )
    registrarError('crm.ayuda.consulta_fallida', fallo, {
      vista,
      longitud: limpia.length,
    })
    throw fallo
  }
  const resultado = v.safeParse(ResultadoConsultaAyudaVendedorSchema, data)
  if (!resultado.success) {
    throw falloContratoAyuda('crm.ayuda.consulta_contrato_invalido')
  }
  return resultado.output
}

function enteroSeguro(valor: number, minimo: number, maximo: number): number {
  if (!Number.isFinite(valor)) return minimo
  return Math.min(maximo, Math.max(minimo, Math.trunc(valor)))
}

/**
 * Normalización del texto de búsqueda de la cartera. Vive en
 * `lib/cartera-keyset` porque desde F2 la comparten TRES sitios que deben
 * coincidir o la pantalla miente: esta capa (que decide si el filtro viaja al
 * servidor), el espejo demo y la RPC. Se conserva el nombre viejo para
 * `listarLeads` —la reserva dormida— y sus tests MSW.
 */
export const normalizarBusquedaPostgrest = normalizarBusquedaCartera

function aNumero(valor: number | string | null): number | null {
  if (valor == null) return null
  const n = typeof valor === 'number' ? valor : Number(valor)
  return Number.isFinite(n) ? n : null
}

/**
 * Procedencia con la MISMA regla que sella `crm.cartera_filtrada_fn`: manual si
 * `alta_manual` (01/09) o tiene autor; sistema si no. Si la fila ya trae
 * `procedencia` (RPC) se respeta; si no trae ni eso ni las columnas crudas
 * (servidor anterior), queda null y el chip no se pinta.
 */
function procedenciaDeFila(fila: Pick<LeadRow, 'procedencia' | 'alta_manual' | 'creado_por'>): Procedencia | null {
  if (fila.procedencia != null) return fila.procedencia
  if (typeof fila.alta_manual !== 'boolean') return null
  return fila.alta_manual || fila.creado_por != null ? 'manual' : 'sistema'
}

function aLead(fila: LeadRow): Lead {
  return {
    id: fila.id,
    nombre_completo: fila.nombre_completo,
    telefono: fila.telefono,
    telefono_alternativo: fila.telefono_alternativo ?? null,
    // El mapper es el eslabón que se olvida (ya van cuatro veces): pedir la
    // columna y declararla en el esquema NO la pone en el navegador.
    telefono_alternativo_crudo: fila.telefono_alternativo_crudo ?? null,
    correo: fila.correo,
    dni: fila.dni,
    genero: fila.genero ?? null,
    fecha_nacimiento: fila.fecha_nacimiento ?? null,
    distrito: fila.distrito,
    origen: fila.origen, // ya validado contra el catálogo por LeadRowSchema
    procedencia: procedenciaDeFila(fila),
    reasignado: fila.reasignado ?? null,
    cargado_por: fila.cargado_por ?? fila.creado_por ?? null,
    etapa: fila.etapa,
    motivo_descarte: fila.motivo_descarte,
    monto_estimado: Number(fila.monto_estimado),
    moneda: fila.moneda,
    categoria_interes: fila.categoria_interes,
    vendedor_id: fila.vendedor_id,
    asignado_supervisor_id: fila.asignado_supervisor_id,
    creado_en: fila.creado_en,
    tenencia_desde: fila.tenencia_desde ?? null,
    // ⚠️ TERCERA vez que este mapper es el eslabón que se olvida (ver el
    // comentario de `actualizado_en` justo abajo): pedir la columna en
    // COLUMNAS_LEAD y declararla en LeadRowSchema NO la pone en el navegador.
    // Sin esta línea, `convertido_en` llega `undefined` a `cierresDelMes` y el
    // mes de cierre cae en silencio al fallback que este cambio viene a matar.
    convertido_en: fila.convertido_en ?? null,
    contrato_id: fila.contrato_id ?? null,
    // Se pedía al servidor y se validaba, pero NO se copiaba: en el navegador
    // llegaba siempre `undefined`. De este campo dependen el "mes de cierre" de
    // la meta del analista y las series de tendencia de gerencia, que sin él caen
    // al fallback `creado_en` y cuentan leads DADOS DE ALTA en el mes en vez de
    // CERRADOS. Con los 324 leads del puente cargados en julio, agosto habría
    // arrancado en cero para todo el equipo (auditoría 2026-07-25).
    actualizado_en: fila.actualizado_en,
    activo: fila.activo,
    nota: fila.nota,
    no_contactar: fila.no_contactar ?? false,
  }
}

/**
 * RESERVA paginada server-side — hoy sin consumidores en la app (los leads se
 * cargan de una vez vía listarLeadsDelAmbito). Reactivar cuando el volumen
 * supere MAX_LEADS_AMBITO=2000: RLS decide el ámbito y el navegador jamás
 * descarga la cartera global para recortarla después. Sus tests MSW
 * (crm-api-msw.test.ts) la mantienen honesta mientras espera.
 */
export async function listarLeads(filtros: FiltrosLeads, signal?: AbortSignal): Promise<Pagina<Lead>> {
  const pagina = enteroSeguro(filtros.pagina, 0, Number.MAX_SAFE_INTEGER)
  const tamano = enteroSeguro(filtros.tamano ?? TAMANO_PAGINA_LEADS, 1, MAX_TAMANO_PAGINA)
  const desde = pagina * tamano
  const hasta = desde + tamano - 1

  let consulta = cliente()
    .schema('crm')
    .from('leads')
    .select(COLUMNAS_LEAD, { count: 'exact' })
    .order('actualizado_en', { ascending: false })
    .order('id', { ascending: true })
    .range(desde, hasta)

  if (!filtros.incluirInactivos) consulta = consulta.eq('activo', true)
  if (filtros.etapa && filtros.etapa !== 'todas') consulta = consulta.eq('etapa', filtros.etapa)

  if (filtros.vendedorId === 'sin_asignar') {
    consulta = consulta.is('vendedor_id', null)
  } else if (filtros.vendedorId && filtros.vendedorId !== 'todos') {
    consulta = consulta.eq('vendedor_id', filtros.vendedorId)
  }

  const busqueda = normalizarBusquedaPostgrest(filtros.texto)
  if (busqueda.texto.length >= 2) {
    const ramas = [`nombre_completo.ilike.%${busqueda.texto}%`]
    if (busqueda.digitos.length >= 3) {
      ramas.push(`telefono.ilike.%${busqueda.digitos}%`, `dni.ilike.%${busqueda.digitos}%`)
    }
    consulta = consulta.or(ramas.join(','))
  }

  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error, count } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    // No se registra el texto ni IDs del filtro: pueden contener PII.
    registrarError('crm.leads.listado_fallido', fallo, {
      pagina,
      tamano,
      etapa: filtros.etapa ?? 'todas',
      incluyeInactivos: filtros.incluirInactivos === true,
      filtraVendedor: Boolean(filtros.vendedorId && filtros.vendedorId !== 'todos'),
      tieneBusqueda: busqueda.texto.length >= 2,
    })
    throw fallo
  }

  // Frontera validada en runtime: una fila que no cumple el contrato (dato
  // viejo, migración a medias) se REGISTRA y se descarta — nunca un cast ciego
  // que reviente la UI río abajo con un union imposible.
  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const resultado = v.safeParse(LeadRowSchema, cruda)
    if (resultado.success) {
      items.push(aLead(resultado.output))
    } else {
      descartadas += 1
    }
  }
  if (descartadas > 0) {
    registrarError(
      'crm.leads.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      {
        descartadas,
        pagina,
      },
    )
  }

  const total = count ?? 0
  return {
    items: await conGestionVigente(cliente(), items, signal),
    pagina,
    tamano,
    total,
    paginas: Math.ceil(total / tamano),
  }
}

// ── La foto del ámbito MURIÓ (Fase 4e «sin topes», 20/09/2026) ─────────────────
// `listarLeadsDelAmbito`, `MAX_LEADS_AMBITO` (5 000), el puente y su alarma de
// tendencia ya no existen: ninguna pantalla depende de bajar todos los leads
// del ámbito. Cada una pide al servidor lo que muestra (`cartera_pagina_fn` /
// `cartera_filtrada_fn` por cursor, bandeja sin analista, cartera propia,
// búsqueda global) y la ficha se relee por id (`obtenerLeadDelAmbitoPorId`).

/** Ficha completa por identidad: la tabla y su RLS siguen siendo la puerta de
 * acceso. La cola resumida nunca se convierte en un Lead parcial. */
export async function obtenerLeadDelAmbitoPorId(id: string, signal?: AbortSignal): Promise<Lead | null> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').from('leads').select(COLUMNAS_LEAD)
    .eq('id', id).eq('activo', true)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta.maybeSingle()
  lanzarAbortSiCorresponde(signal)
  if (error) throw new CrmApiError('No se pudo cargar la ficha del lead.', error.code || 'POSTGREST_ERROR')
  if (data === null) return null
  const resultado = v.safeParse(LeadRowSchema, data)
  if (!resultado.success || resultado.output.id !== id || !resultado.output.activo) {
    throw new CrmApiError('Los datos de esta ficha no cumplen el contrato del CRM. Solicita revisión a Gerencia.', 'ROW_CONTRACT')
  }
  const lead = aLead(resultado.output)
  if (lead.vendedor_id == null) return { ...lead, reasignado: false }
  // La ficha se relee por id al abrirse y no hereda el dato de la página
  // keyset. El mismo historial RLS que usa la RPC permite mostrar la marca
  // aunque se abra el lead desde la búsqueda global o desde otra pantalla.
  let historial = cliente().schema('crm').from('actividades').select('id')
    .eq('lead_id', id).eq('tipo', 'reasignacion')
    .not('metadata->>vendedor_anterior', 'is', null).limit(1)
  if (signal) historial = historial.abortSignal(signal)
  const { data: movimientos, error: errorHistorial } = await historial
  lanzarAbortSiCorresponde(signal)
  // La marca es adicional: si un servidor antiguo no permite esta consulta,
  // la ficha sigue abriéndose y no se inventa un «no reasignado».
  const [conGestion] = await conGestionVigente(cliente(), [lead], signal)
  return { ...conGestion!, reasignado: errorHistorial ? null : (movimientos?.length ?? 0) > 0 }
}

// ── Cartera paginada por CURSOR KEYSET (F2) ───────────────────────────────────
// Sustituye a `listarLeadsDelAmbito` en la pantalla Cartera: nada de `range`
// con `count: 'exact'` (que obliga al servidor a contar la tabla entera en cada
// página) ni de tope mudo. Los filtros viajan TIPADOS a la RPC — el cursor lo
// valida Postgres, no la allowlist de `normalizarBusquedaPostgrest`, que sigue
// aquí solo para normalizar lo que teclea el usuario.

export interface FiltrosCartera {
  etapa?: Etapa | 'todas'
  vendedorId?: string | 'todos' | 'sin_asignar'
  texto?: string
  /** Origen del lead (vigentes e históricos); «todos» es el valor neutro y no viaja. */
  origen?: Origen | 'todos'
  /** Procedencia (sistema/manual); «todas» es el valor neutro y no viaja. */
  procedencia?: Procedencia | 'todas'
  /** Solo leads que ya pasaron por un analista antes del reparto actual. */
  reasignados?: boolean
  /**
   * «Gestión vigente» (ver `GestionCartera`): parte la etapa `nuevo` del
   * Pipeline en «Nuevo» (`sin_gestion`) y «Gestionado» (`con_gestion`). Un
   * resultado de llamada deshecho no cuenta como gestión. Ausente es el valor
   * neutro y no viaja. Solo lo entiende la lista integrada
   * (`cartera_filtrada_fn`); en demo no recorta — ahí lo calcula el Pipeline.
   */
  gestion?: GestionCartera
  /**
   * Potencial del lead: un nivel o «sin marca». Ausente es el valor neutro y no
   * viaja. Solo lo entiende la lista integrada (`cartera_filtrada_fn`) y solo
   * con la bandera del potencial encendida en el servidor.
   */
  potencial?: FiltroPotencial
  integrada?: boolean
  recepcion?: { desde: string; hasta: string } | null
}

/** Posición exacta en el orden `(actualizado_en desc, id asc)`. */
export interface CursorCartera {
  actualizadoEn: string
  id: string
}

export interface PaginaCartera {
  items: Lead[]
  /** `null` = no hay más páginas; nunca se infiere de `items.length`. */
  cursor: CursorCartera | null
  resumen?: ResumenCarteraFiltrada
}

/**
 * Lo que la cartera integrada trae de resumen: los indicadores de siempre y,
 * con el potencial encendido en el servidor, los conteos por nivel.
 */
export type ResumenCarteraFiltrada = Pick<ResumenCartera, 'totales' | 'capital' | 'embudo'> & {
  potencial?: ConteosPotencial
}

const LeadCarteraRowSchema = v.object({
  ...LeadRowSchema.entries,
  ultimo_contacto_en: v.nullable(v.string()),
})

const CarteraFiltradaSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  desde: v.nullable(v.string()),
  hasta: v.nullable(v.string()),
  // Eco del origen filtrado. Opcional a propósito: un servidor anterior a la
  // firma con p_origen no lo devuelve, y sin filtro puesto eso sigue siendo
  // una respuesta válida; con filtro puesto, su ausencia es un desajuste.
  origen: v.optional(v.nullable(v.string())),
  // Eco de la procedencia filtrada, con la misma lógica que `origen`.
  procedencia: v.optional(v.nullable(v.string())),
  // Presente desde la migración de reasignados; un servidor previo no inventa cero.
  reasignados: v.optional(v.boolean()),
  items: v.array(v.object({
    ...LeadCarteraRowSchema.entries,
    recibido_en: v.nullable(v.string()),
    recepcion_aproximada: v.nullable(v.boolean()),
  })),
  resumen: v.object({
    ...v.pick(ResumenCarteraSchema, ['totales', 'capital', 'embudo']).entries,
    // Conteos por potencial: solo con la bandera encendida y un servidor que ya
    // los sirva. Un bloque que este bundle no entiende (un nivel nuevo, p. ej.)
    // NO tumba la lista: se queda en null y la fila de potencial no se pinta.
    // Con el filtro PEDIDO, en cambio, su ausencia sí es un desajuste (abajo).
    potencial: v.optional(v.fallback(v.nullable(ConteosPotencialSchema), null)),
  }),
})

/** Lo MÍNIMO para poder avanzar: si una fila no lo cumple, no hay cursor honesto. */
const CursorRowSchema = v.object({
  id: v.string(),
  actualizado_en: v.string(),
})

export async function listarCarteraPagina(
  filtros: FiltrosCartera,
  cursor: CursorCartera | null,
  signal?: AbortSignal,
): Promise<PaginaCartera> {
  const texto = textoBuscable(filtros.texto)
  // Se pide UNA fila de más: es lo que distingue "hay más" de "justo cabía",
  // sin gastar una petición extra que vuelva vacía al final de la lista.
  const argumentos: Record<string, unknown> = {
    p_limite: TAMANO_PAGINA_CARTERA + 1,
  }
  if (cursor) {
    argumentos.p_antes_de = cursor.actualizadoEn
    argumentos.p_antes_id = cursor.id
  }
  if (filtros.etapa && filtros.etapa !== 'todas') argumentos.p_etapa = filtros.etapa
  if (filtros.vendedorId === 'sin_asignar') {
    argumentos.p_sin_asignar = true
  } else if (filtros.vendedorId && filtros.vendedorId !== 'todos') {
    argumentos.p_vendedor_id = filtros.vendedorId
  }
  // El servidor RECHAZA (22023) un texto por debajo del mínimo: quien decide si
  // el filtro viaja es `textoBuscable`, la MISMA regla que aplica el espejo demo.
  if (texto !== null) argumentos.p_texto = texto
  if (filtros.integrada && filtros.recepcion) {
    argumentos.p_desde = filtros.recepcion.desde
    argumentos.p_hasta = filtros.recepcion.hasta
  }
  // «todos» no viaja: un servidor previo a la firma con p_origen sigue
  // resolviendo la llamada sin él (PGRST202 evitado), igual que en métricas.
  const origenPedido = filtros.integrada && filtros.origen && filtros.origen !== 'todos' ? filtros.origen : null
  if (origenPedido !== null) argumentos.p_origen = origenPedido
  // «todas» tampoco viaja: mismo motivo, misma tolerancia a un servidor previo.
  const procedenciaPedida = filtros.integrada && filtros.procedencia && filtros.procedencia !== 'todas' ? filtros.procedencia : null
  if (procedenciaPedida !== null) argumentos.p_procedencia = procedenciaPedida
  const reasignadosPedidos = filtros.integrada && filtros.reasignados === true
  if (reasignadosPedidos) argumentos.p_reasignados = true
  // La gestión solo viaja cuando recorta, y solo a la lista integrada: sin
  // ella la llamada es idéntica a la de siempre (Leads y las demás columnas no
  // dependen de que el servidor ya conozca `p_gestion`). El servidor NO devuelve
  // eco de este filtro: la forma de la respuesta es la misma con o sin él.
  // Tampoco se comprueba contra las filas: la regla descarta los resultados de
  // llamada deshechos, así que un lead `sin_gestion` puede traer un
  // `ultimo_contacto_en` posterior a su tenencia y estar bien servido.
  const gestionPedida = filtros.integrada && filtros.gestion ? filtros.gestion : null
  if (gestionPedida !== null) argumentos.p_gestion = gestionPedida
  // El potencial solo viaja cuando recorta, y solo a la lista integrada: un
  // servidor anterior a `p_potencial` sigue resolviendo la llamada sin él.
  const potencialPedido = filtros.integrada && filtros.potencial ? filtros.potencial : null
  if (potencialPedido !== null) argumentos.p_potencial = potencialPedido

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc(filtros.integrada ? 'cartera_filtrada_fn' : 'cartera_pagina_fn', argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    // 42501 NO es «se cayó el servidor»: es la guardia de admisión de la RPC
    // diciendo que esta cuenta no pertenece al CRM (P04: revocado ≠ ajeno). Con
    // el mensaje genérico, un offboarding vivido como avería mandaría a alguien
    // a reintentar durante horas.
    // 55000 con el filtro pedido = el potencial se apagó en el servidor mientras
    // la pantalla lo tenía puesto. No es una avería: la pantalla suelta el filtro.
    const fallo =
      error.code === '42501'
        ? new CrmApiError('Tu cuenta no tiene acceso a la cartera del CRM.', '42501')
        : error.code === '55000' && potencialPedido !== null
          ? new CrmApiError('El filtro por potencial no está disponible en este momento.', 'POTENCIAL_APAGADO')
          : new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    // Sin texto ni IDs del filtro: pueden contener PII.
    registrarError('crm.leads.pagina_fallida', fallo, {
      etapa: filtros.etapa ?? 'todas',
      filtraVendedor: Boolean(filtros.vendedorId && filtros.vendedorId !== 'todos'),
      filtraOrigen: origenPedido !== null,
      filtraProcedencia: procedenciaPedida !== null,
      filtraReasignados: reasignadosPedidos,
      filtraGestion: gestionPedida !== null,
      filtraPotencial: potencialPedido !== null,
      tieneBusqueda: texto !== null,
      conCursor: cursor != null,
    })
    throw fallo
  }

  if (filtros.integrada) {
    const resultado = v.safeParse(CarteraFiltradaSchema, data)
    if (!resultado.success) throw new CrmApiError('La cartera y sus indicadores no cumplen el contrato esperado.', 'ROW_CONTRACT')
    const payload = resultado.output
    const total = payload.resumen.totales.vivos
    const { potencial: conteosPotencial = null, ...indicadores } = payload.resumen
    if (payload.desde !== (filtros.recepcion?.desde ?? null)
      || payload.hasta !== (filtros.recepcion?.hasta ?? null)
      // El servidor devuelve el origen que aplicó: si no coincide con el pedido
      // (o no lo aplicó), los indicadores no serían los del filtro en pantalla.
      || (payload.origen ?? null) !== origenPedido
      || (origenPedido !== null && payload.items.some((l) => l.origen !== origenPedido))
      // Misma exigencia para la procedencia: eco y filas coherentes, o nada.
      || (payload.procedencia ?? null) !== procedenciaPedida
      || (procedenciaPedida !== null && payload.items.some((l) => l.procedencia !== procedenciaPedida))
      || (payload.reasignados ?? false) !== reasignadosPedidos
      || (reasignadosPedidos && (payload.resumen.totales.reasignados !== total
        || payload.items.some((l) => l.reasignado !== true)))
      || (payload.resumen.totales.reasignados != null
        && (!Number.isSafeInteger(payload.resumen.totales.reasignados)
          || payload.resumen.totales.reasignados < 0
          || payload.resumen.totales.reasignados > total))
      // Potencial: con el filtro pedido hacen falta el eco y que el total sea el
      // conteo de ese nivel; sin filtro, los cuatro conteos suman el total (el
      // servidor los cuenta antes de aplicar el filtro de potencial).
      || (potencialPedido !== null && (conteosPotencial === null
        || conteosPotencial.filtro !== potencialPedido || conteosPotencial[potencialPedido] !== total))
      || (potencialPedido === null && conteosPotencial !== null
        && (conteosPotencial.filtro !== null || totalConteosPotencial(conteosPotencial) !== total))
      || !Number.isSafeInteger(total) || total < payload.items.length
      || payload.resumen.embudo.reduce((n, e) => n + e.n, 0) !== total
      || payload.items.length > TAMANO_PAGINA_CARTERA + 1
      || new Set(payload.items.map((l) => l.id)).size !== payload.items.length
      || payload.items.some((l) => !l.activo || (filtros.recepcion && !l.recibido_en))) {
      throw new CrmApiError('La cartera y sus indicadores no coinciden con los filtros solicitados.', 'ROW_CONTRACT')
    }
    const hayMas = payload.items.length > TAMANO_PAGINA_CARTERA
    const filas = payload.items.slice(0, TAMANO_PAGINA_CARTERA)
    const ultima = filas.at(-1)
    return {
      items: await conGestionVigente(cliente(), filas.map((l) => ({ ...aLead(l), ultimo_contacto_en: l.ultimo_contacto_en,
        recibido_en: l.recibido_en, recepcion_aproximada: l.recepcion_aproximada })), signal, gestionPedida),
      cursor: hayMas && ultima ? { actualizadoEn: ultima.actualizado_en, id: ultima.id } : null,
      resumen: conteosPotencial ? { ...indicadores, potencial: conteosPotencial } : indicadores,
    }
  }

  const crudas = Array.isArray(data) ? data : []
  const hayMas = crudas.length > TAMANO_PAGINA_CARTERA
  const ventana = hayMas ? crudas.slice(0, TAMANO_PAGINA_CARTERA) : crudas

  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of ventana) {
    const r = v.safeParse(LeadCarteraRowSchema, cruda)
    if (r.success) {
      items.push({
        ...aLead(r.output),
        ultimo_contacto_en: r.output.ultimo_contacto_en,
      })
    } else {
      descartadas += 1
    }
  }
  if (descartadas > 0) {
    registrarError(
      'crm.leads.pagina_filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }

  // El cursor sale de la ÚLTIMA fila CRUDA de la ventana, no de la última
  // válida: si se descartara la de la cola, avanzar desde la anterior repetiría
  // esa fila en la página siguiente — y si se descartaran todas, la lista se
  // cortaría en seco fingiendo que ya no hay nada.
  let siguiente: CursorCartera | null = null
  if (hayMas) {
    const ultima = v.safeParse(CursorRowSchema, ventana.at(-1))
    if (ultima.success) {
      siguiente = {
        actualizadoEn: ultima.output.actualizado_en,
        id: ultima.output.id,
      }
    } else {
      registrarError(
        'crm.leads.pagina_sin_cursor',
        new CrmApiError('La última fila de la página no permite calcular el cursor', 'CURSOR_CONTRACT'),
      )
    }
  }

  return { items: await conGestionVigente(cliente(), items, signal), cursor: siguiente }
}

/**
 * Alarma de TENDENCIA de la bandeja sin analista (Fase 4c): no corta, avisa.
 * Hoy la bandeja tiene 3 leads abiertos sin analista en producción.
 */
const ALARMA_TENDENCIA_BANDEJA = 2000

/**
 * Bandeja de leads SIN analista (Fase 4c «sin topes»): lo que Equipo,
 * Derivaciones y Hoy · Supervisor filtraban de la foto inicial
 * (`vendedor_id == null`). Pide a `crm.cartera_pagina_fn` (INVOKER: la RLS
 * decide qué bandejas ve cada actor: el supervisor la suya, gerencia todas) con
 * `p_sin_asignar` por cursor hasta que no haya más; sin tope en el navegador.
 * Devuelve leads ACTIVOS sin analista (de cualquier etapa): la pantalla decide
 * si quiere solo los abiertos.
 */
export async function listarLeadsSinAsignar(signal?: AbortSignal): Promise<Lead[]> {
  return listarLeadsPorCursor({ etapa: 'todas', vendedorId: 'sin_asignar', integrada: false }, 'bandeja', signal)
}

/**
 * Los leads del PROPIO analista (Fase 4d «sin topes»): lo que Hoy · Analista
 * necesita para su higiene, sus citas y su pulso, sin la foto inicial. Bajo la
 * RLS del analista `cartera_pagina_fn` sin filtro ya es SOLO su cartera; se
 * recorre por cursor hasta agotarla (acotada por su propia cartera).
 */
export async function listarLeadsPropios(signal?: AbortSignal): Promise<Lead[]> {
  return listarLeadsPorCursor({ etapa: 'todas', vendedorId: 'todos', integrada: false }, 'propios', signal)
}

/** Recorre `cartera_pagina_fn` por cursor hasta agotar la lista que pinta el filtro. */
async function listarLeadsPorCursor(filtros: FiltrosCartera, etiqueta: string, signal?: AbortSignal): Promise<Lead[]> {
  const vistos = new Set<string>()
  const items: Lead[] = []
  let cursor: CursorCartera | null = null
  let vueltas = 0
  do {
    const pagina: PaginaCartera = await listarCarteraPagina(filtros, cursor, signal)
    for (const l of pagina.items) {
      if (vistos.has(l.id)) continue
      vistos.add(l.id)
      items.push(l)
    }
    // Avance ESTRICTO del cursor: repetir o retroceder sería un bucle.
    if (pagina.cursor && cursor
      && !(pagina.cursor.actualizadoEn < cursor.actualizadoEn
        || (pagina.cursor.actualizadoEn === cursor.actualizadoEn && pagina.cursor.id > cursor.id))) {
      throw new CrmApiError('La lista no avanza por cursor.', 'ROW_CONTRACT')
    }
    cursor = pagina.cursor
    vueltas += 1
  // Salvaguarda contra un servidor que nunca agota (el avance estricto ya
  // impide ciclar): 2 000 páginas = 100 000 filas, muy por encima de cualquier
  // bandeja o cartera propia (Codex 20/09: 200 era un tope nuevo de 10 000).
  } while (cursor && vueltas < 2000)
  if (cursor) throw new CrmApiError('La lista no termina de paginar.', 'ROW_CONTRACT')
  if (items.length > ALARMA_TENDENCIA_BANDEJA) {
    registrarError(`crm.leads.${etiqueta}_tendencia`,
      new CrmApiError('La lista por cursor supera la alarma de tendencia', 'TENDENCIA'), { filas: items.length })
  }
  return items
}

/** Resultados del buscador global (Fase 4a «sin topes»): los que caben en el desplegable. */
export const TAMANO_BUSQUEDA_GLOBAL = 8

/**
 * Buscador global de la barra (Fase 4a «sin topes»): pide al SERVIDOR los leads
 * del ámbito que casan con el texto, en vez de filtrar la foto inicial en el
 * navegador. Reutiliza `crm.cartera_pagina_fn` (INVOKER: el alcance lo pone la
 * RLS; texto = nombre ILIKE, y teléfono/DNI a partir de 3 dígitos; índices
 * trigram en las tres columnas), ordenada por actualización reciente. Devuelve
 * como máximo `limite` filas: el servidor recorta, el navegador NO.
 *
 * Quien decide si el texto viaja es `textoBuscable` (mismo mínimo que el
 * servidor, que rechaza con 22023 por debajo de 2 caracteres): por debajo del
 * mínimo no hay petición y el resultado es vacío.
 */
export async function buscarLeadsGlobal(
  texto: string,
  signal?: AbortSignal,
  limite: number = TAMANO_BUSQUEDA_GLOBAL,
): Promise<Lead[]> {
  const buscable = textoBuscable(texto)
  if (buscable === null) return []
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('cartera_pagina_fn', { p_limite: limite, p_texto: buscable })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo =
      error.code === '42501'
        ? new CrmApiError('Tu cuenta no tiene acceso a la cartera del CRM.', '42501')
        : new CrmApiError('No se pudo buscar en tus leads.', error.code || 'POSTGREST_ERROR')
    // Sin el texto: puede ser un nombre, un teléfono o un DNI.
    registrarError('crm.leads.busqueda_global_fallida', fallo, { largo: buscable.length })
    throw fallo
  }
  const crudas = Array.isArray(data) ? data : []
  if (crudas.length > limite) {
    throw new CrmApiError('La búsqueda devolvió más filas de las pedidas.', 'ROW_CONTRACT')
  }
  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of crudas) {
    const r = v.safeParse(LeadCarteraRowSchema, cruda)
    if (r.success) items.push({ ...aLead(r.output), ultimo_contacto_en: r.output.ultimo_contacto_en })
    else descartadas += 1
  }
  if (descartadas > 0) {
    registrarError('crm.leads.busqueda_global_filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'), { descartadas })
  }
  if (new Set(items.map((l) => l.id)).size !== items.length) {
    throw new CrmApiError('La búsqueda devolvió leads repetidos.', 'ROW_CONTRACT')
  }
  return conGestionVigente(cliente(), items, signal)
}

// ── Roster del equipo con NOMBRES (RPC SECURITY DEFINER equipo_visible_fn) ─────
// 'coordinador' (C1) es OFF-ROSTER, como 'directorio': equipo_visible_fn no debe
// devolverlo; si alguna vez lo hiciera, el picklist lo descarta A PROPÓSITO en el
// safeParse de abajo (fila fuera de contrato → se ignora, sin romper el roster).
const ROLES_EQUIPO = ['vendedor', 'supervisor', 'gerencia'] as const
const MiembroRowSchema = v.object({
  perfil_id: v.string(),
  nombre_completo: v.string(),
  rol_crm: v.picklist(ROLES_EQUIPO),
  supervisor_id: v.nullable(v.string()),
  activo: v.boolean(),
})

export async function listarEquipo(signal?: AbortSignal): Promise<Miembro[]> {
  let consulta = cliente().schema('crm').rpc('equipo_visible_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el equipo.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.equipo.listado_fallido', fallo)
    throw fallo
  }
  const items: Miembro[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(MiembroRowSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

// ── Metas versionadas y cumplimiento confirmado ─────────────────────────────

function contratoMetasInvalido(evento: string): CrmApiError {
  const fallo = new CrmApiError('El servidor devolvió metas con un formato no reconocido.', 'ROW_CONTRACT')
  registrarError(evento, fallo)
  return fallo
}

/** Fotografía completa del roster y su última revisión mensual publicada. */
export async function obtenerMetasDelMes(periodo: string, signal?: AbortSignal): Promise<ConfiguracionMetas> {
  let consulta = cliente().schema('crm').rpc('configuracion_metas_fn', { p_periodo: periodo })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar las metas del mes.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.metas.configuracion_fallida', fallo)
    throw fallo
  }
  const resultado = v.safeParse(ConfiguracionMetasSchema, data)
  if (!resultado.success) throw contratoMetasInvalido('crm.metas.configuracion_contrato_invalido')
  return resultado.output
}

/**
 * Cumplimiento autoritativo: capital/contratos salen de contratos confirmados
 * y la conversión de leads resueltos. El RPC declara ambas fuentes y conserva
 * categoría/moneda en cada dimensión contractual.
 */
export async function obtenerCumplimientoMetas(periodo: string, signal?: AbortSignal): Promise<CumplimientoMetasRpc> {
  let consulta = cliente().schema('crm').rpc('cumplimiento_metas_fn', { p_periodo: periodo })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo calcular el cumplimiento de metas.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.metas.cumplimiento_fallido', fallo)
    throw fallo
  }
  const resultado = v.safeParse(CumplimientoMetasSchema, data)
  if (!resultado.success) throw contratoMetasInvalido('crm.metas.cumplimiento_contrato_invalido')
  return resultado.output
}

/** Desglose conciliado de capital y tasa mensual por canal de un analista visible. */
export async function obtenerRankingOrigenVendedor(
  periodo: string,
  vendedorId: string,
  signal?: AbortSignal,
): Promise<RankingOrigenVendedor> {
  let consulta = cliente().schema('crm').rpc('ranking_origen_vendedor_v2_fn', {
    p_periodo: periodo,
    p_vendedor_id: vendedorId,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el desglose por origen.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.ranking.origen_fallido', fallo)
    throw fallo
  }
  const resultado = v.safeParse(RankingOrigenVendedorSchema, data)
  if (!resultado.success || resultado.output.periodo !== periodo
    || resultado.output.vendedor_id !== vendedorId) {
    throw new CrmApiError('El desglose por origen no corresponde al analista y mes consultados.', 'RANKING_ORIGEN_CONTRACT')
  }
  return resultado.output
}

/**
 * El estado de la MAQUINARIA del cierre de mes (`crm.cierre_mes_estado_fn`):
 * qué mes pendiente hay y en qué estado (`en_ventana`/`hoy`/`atascado`), y
 * hasta dónde quedó sellado. Sin cifras ni PII: es el reloj, no un período.
 * ⚠️ No confundir con `cierres_estado_fn`, que es de los cierres de VENTA.
 */
export async function obtenerCierreMesEstado(signal?: AbortSignal): Promise<CierreMesEstadoRpc> {
  let consulta = cliente().schema('crm').rpc('cierre_mes_estado_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo leer el estado del cierre de mes.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.cierre_mes.estado_fallido', fallo)
    throw fallo
  }
  const resultado = v.safeParse(CierreMesEstadoSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError('El servidor devolvió un estado del cierre de mes no reconocido.', 'ROW_CONTRACT')
    registrarError('crm.cierre_mes.estado_contrato_invalido', fallo)
    throw fallo
  }
  return resultado.output
}

// ── Reparto de la cola global (C1) — 3 RPC SECURITY DEFINER con gate propio ───
// El coordinador NO ve leads por RLS (ámbito ∅): todo su trabajo pasa por aquí.

const ORIGENES_K = ORIGENES_TODOS.map((o) => o.k) as [Origen, ...Origen[]]
const CATEGORIAS_K = CATEGORIAS_INTERES.map((c) => c.k) as [CategoriaInteres, ...CategoriaInteres[]]
const ETAPAS_TODAS_K = [...ETAPAS.map((e) => e.k), ...TERMINALES.map((e) => e.k)] as [Etapa, ...Etapa[]]

const ColaLeadSchema = v.object({
  id: v.string(),
  nombre_completo: v.string(),
  distrito: v.nullable(v.string()),
  origen: v.picklist(ORIGENES_K),
  categoria_interes: v.nullable(v.picklist(CATEGORIAS_K)),
  monto_estimado: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  moneda: v.picklist(['PEN', 'USD'] as const),
  creado_en: v.string(),
  // C1-bis — OPCIONALES a propósito: si el front corre contra una BD sin la
  // v2 de la cola, la fila degrada a "sin marca, sin comentario" en vez de
  // caerse del parseo (deploy seguro en cualquier orden, BD antes o después).
  clasificacion_auto: v.optional(v.nullable(v.picklist(['posible_credito'] as const)), null),
  comentario: v.optional(v.nullable(v.string()), null),
})

const SupervisorRepartoSchema = v.object({
  perfil_id: v.string(),
  nombre: v.string(),
  activo: v.boolean(),
  bandeja_pendiente: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
})

const HistorialDerivacionSchema = v.object({
  actividad_id: v.string(),
  lead_id: v.string(),
  nombre_completo: v.string(),
  distrito: v.nullable(v.string()),
  origen: v.picklist(ORIGENES_K),
  monto_estimado: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  moneda: v.picklist(['PEN', 'USD'] as const),
  etapa_actual: v.picklist(ETAPAS_TODAS_K),
  movimiento: v.string(),
  derivado_en: v.string(),
  responsable_anterior: v.string(),
  responsable_nuevo: v.string(),
  derivado_por_nombre: v.string(),
})

const DistribucionSupervisorSchema = v.object({
  perfil_id: v.string(),
  nombre: v.string(),
  total_leads: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
})

const DistribucionAnalistaSchema = v.object({
  perfil_id: v.string(),
  nombre: v.string(),
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.string(),
  total_leads: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
})

const PanelDistribucionRepartoSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  total_leads: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  supervisores: v.array(DistribucionSupervisorSchema),
  analistas: v.array(DistribucionAnalistaSchema),
})

const OrigenAgendaRepartoSchema = v.picklist(['landing', 'formulario'] as const)

const DestinoAgendaRepartoSchema = v.object({
  perfil_id: v.string(),
  nombre: v.string(),
  alias: v.string(),
})

const EntregaAgendaRepartoSchema = v.object({
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.string(),
  supervisor_alias: v.nullable(v.string()),
  derivados: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  coincide_turno: v.boolean(),
})

const AsignacionAgendaRepartoSchema = v.object({
  origen: OrigenAgendaRepartoSchema,
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.nullable(v.string()),
  supervisor_alias: v.nullable(v.string()),
  derivados: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  // Opcionales solo para una publicación compatible SQL → UI. La nueva RPC
  // siempre los sirve; el frontend anterior puede ignorarlos sin caerse.
  fuera_turno: v.optional(v.pipe(v.union([v.number(), v.string()]), v.transform(Number))),
  entregas: v.optional(v.array(EntregaAgendaRepartoSchema)),
})

const DiaAgendaRepartoSchema = v.object({
  fecha: v.string(),
  asignaciones: v.array(AsignacionAgendaRepartoSchema),
})

const AgendaRepartoDiariaSchema = v.object({
  version: v.literal(1),
  fecha_desde: v.string(),
  destinos: v.array(DestinoAgendaRepartoSchema),
  dias: v.array(DiaAgendaRepartoSchema),
})

const AgendaRepartoGuardadaSchema = v.object({
  version: v.literal(1),
  fecha: v.string(),
  guardado_en: v.string(),
})

/** La lista queda intencionalmente corta: el historial se navega, no crece. */
export const TAMANO_PAGINA_HISTORIAL_REPARTO = 25

export interface FiltrosAgendaRepartoDiaria {
  desde?: string
  dias?: number
}

export async function leadsPorRepartir(signal?: AbortSignal): Promise<ColaLead[]> {
  let consulta = cliente().schema('crm').rpc('leads_por_repartir')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  // Un fetch ABORTADO (desmontaje, recarga, doble efecto de StrictMode) no es un
  // fallo del servidor. Antes se propagaba como CrmApiError sin reportarlo, lo que
  // dejaba la query en ERROR y podía pintar un aviso de degradación falso al volver
  // a la pantalla; ahora usa la MISMA guarda que el resto de lecturas.
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la cola de leads.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.cola_fallida', fallo)
    throw fallo
  }
  const items: ColaLead[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(ColaLeadSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

/** Página del historial íntegro, entregada por una RPC que no abre RLS directa. */
export async function historialDerivaciones(
  cursor?: Pick<HistorialDerivacion, 'derivado_en' | 'actividad_id'>,
  signal?: AbortSignal,
): Promise<HistorialDerivacion[]> {
  let consulta = cliente()
    .schema('crm')
    .rpc('historial_derivaciones', {
      p_limite: TAMANO_PAGINA_HISTORIAL_REPARTO,
      ...(cursor
        ? {
            p_derivado_antes: cursor.derivado_en,
            p_actividad_antes: cursor.actividad_id,
          }
        : {}),
    })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el historial de derivaciones.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.historial_fallido', fallo)
    throw fallo
  }
  const items: HistorialDerivacion[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(HistorialDerivacionSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

/**
 * Agenda semanal de Rosa: únicamente Landing y Formulario, sus dos destinos
 * habilitados y los conteos reales de entradas a bandeja. No devuelve leads.
 */
export async function agendaRepartoDiaria(
  filtros: FiltrosAgendaRepartoDiaria = {},
  signal?: AbortSignal,
): Promise<AgendaRepartoDiaria> {
  let consulta = cliente()
    .schema('crm')
    .rpc('agenda_reparto_diaria', {
      ...(filtros.desde ? { p_desde: filtros.desde } : {}),
      ...(filtros.dias ? { p_dias: filtros.dias } : {}),
    })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la agenda de reparto.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.agenda_fallida', fallo)
    throw fallo
  }
  const resultado = v.safeParse(AgendaRepartoDiariaSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError('La agenda de reparto no tiene el formato esperado.', 'AGENDA_REPARTO_CONTRACT')
    registrarError('crm.reparto.agenda_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    ...resultado.output,
    destinos: resultado.output.destinos as DestinoAgendaReparto[],
    dias: resultado.output.dias.map((dia) => ({
      ...dia,
      asignaciones: dia.asignaciones as AsignacionAgendaReparto[],
    })) as DiaAgendaReparto[],
  }
}

/** Guarda juntos los dos carriles del día para que nunca quede media agenda. */
export async function guardarAgendaRepartoDiaria(
  fecha: string,
  landingSupervisorId: string,
  formularioSupervisorId: string,
  signal?: AbortSignal,
): Promise<void> {
  let consulta = cliente().schema('crm').rpc('guardar_agenda_reparto_diaria', {
    p_fecha: fecha,
    p_landing: landingSupervisorId,
    p_formulario: formularioSupervisorId,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    // `22023` se reserva en esta RPC para reglas operativas redactadas para
    // Coordinación. Es seguro mostrarla: ayuda a Rosa a corregir el turno sin
    // revelar datos del lead ni detalles internos de permisos/infraestructura.
    const mensaje =
      error.code === '22023' && error.message.trim().length > 0
        ? error.message
        : 'No se pudo guardar la agenda de reparto.'
    const fallo = new CrmApiError(mensaje, error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.agenda_guardado_fallido', fallo)
    throw fallo
  }
  if (!v.safeParse(AgendaRepartoGuardadaSchema, data).success) {
    const fallo = new CrmApiError(
      'La confirmación de la agenda de reparto no tiene el formato esperado.',
      'AGENDA_REPARTO_GUARDADO_CONTRACT',
    )
    registrarError('crm.reparto.agenda_guardado_fuera_de_contrato', fallo)
    throw fallo
  }
}

export interface FiltrosPanelDistribucionReparto {
  supervisorId?: string
  analistaId?: string
  origen?: Origen
}

/**
 * Foto actual de la cartera distribuida, agrupada por supervisor y analista.
 * El RPC no entrega PII ni embudo: solo los conteos que necesita Coordinación.
 * Sin filtros de origen incluye referido, Walking (`oficina`) y el resto de
 * orígenes actuales e históricos.
 */
export async function panelDistribucionReparto(
  filtros: FiltrosPanelDistribucionReparto = {},
  signal?: AbortSignal,
): Promise<PanelDistribucionReparto> {
  const argumentos = {
    p_solo_activos: true,
    ...(filtros.supervisorId ? { p_supervisor: filtros.supervisorId } : {}),
    ...(filtros.analistaId ? { p_analista: filtros.analistaId } : {}),
    ...(filtros.origen ? { p_origen: filtros.origen } : {}),
  }
  let consulta = cliente().schema('crm').rpc('panel_distribucion_reparto', argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el panel de distribución.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.panel_distribucion_fallido', fallo)
    throw fallo
  }
  const resultado = v.safeParse(PanelDistribucionRepartoSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'El panel de distribución no tiene el formato esperado.',
      'PANEL_DISTRIBUCION_CONTRACT',
    )
    registrarError('crm.reparto.panel_distribucion_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    ...resultado.output,
    supervisores: resultado.output.supervisores as DistribucionSupervisor[],
    analistas: resultado.output.analistas as DistribucionAnalista[],
  }
}

export async function supervisoresParaReparto(signal?: AbortSignal): Promise<SupervisorReparto[]> {
  let consulta = cliente().schema('crm').rpc('supervisores_para_reparto')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar los supervisores.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.supervisores_fallida', fallo)
    throw fallo
  }
  const items: SupervisorReparto[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(SupervisorRepartoSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

/**
 * Cuantos leads INGRESARON al CRM durante el mes de Lima, aunque hoy ya esten
 * repartidos o descartados. Es una lectura agregada sin PII exclusiva de la
 * mesa de Coordinacion; no debe confundirse con el tamano actual de la cola.
 */
export async function listarIngresosRepartoMes(mes: string, signal?: AbortSignal): Promise<IngresosRepartoMes> {
  const pMes = inicioDeMes(mes)
  if (pMes == null) {
    throw new CrmApiError('El mes seleccionado no es valido.', 'MES_INVALIDO')
  }

  let consulta = cliente().schema('crm').rpc('ingresos_reparto_mes_fn', { p_mes: pMes })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar los ingresos del mes.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.reparto.ingresos_mes_fallido', fallo)
    throw fallo
  }

  const resultado = v.safeParse(IngresosRepartoMesSchema, data)
  if (!resultado.success || resultado.output.mes !== pMes) {
    const fallo = new CrmApiError('El resumen de ingresos no tiene el formato esperado.', 'INGRESOS_REPARTO_CONTRACT')
    registrarError('crm.reparto.ingresos_mes_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/** Mueve un lead de la cola global a la bandeja de un supervisor (atómico en el
 *  servidor: re-valida no_contactar y usa un UPDATE con predicado anti-carrera). */
export async function repartirLead(leadId: string, supervisorId: string): Promise<void> {
  const { error } = await cliente().schema('crm').rpc('repartir_lead', {
    p_lead: leadId,
    p_supervisor: supervisorId,
  })
  if (error) throw aErrorApi(error, 'crm.reparto.repartir_fallido')
}

// ── C1-bis: descarte de la cola (el código marca, el coordinador cierra) ─────

/** Cierra un lead de la COLA GLOBAL con motivo obligatorio. Idempotente en el
 *  servidor para el mismo actor+motivo (doble clic seguro). La nota se
 *  appendea allá (`· DESCARTE: …`), nunca pisa el comentario del cliente.
 *  Errores: P0002→FUERA_DE_COLA (carrera o ya cerrado), 22023→REGLA_SERVIDOR. */
export async function descartarLead(leadId: string, motivo: MotivoDescarte, nota?: string): Promise<void> {
  const { error } = await cliente()
    .schema('crm')
    .rpc('descartar_lead', {
      p_lead: leadId,
      p_motivo: motivo,
      ...(nota?.trim() ? { p_nota: nota.trim() } : {}),
    })
  if (error) throw aErrorApi(error, 'crm.descarte.descartar_fallido')
}

/** Deshace un descarte PROPIO de las últimas 24 h (el lead vuelve a la cola en
 *  etapa nuevo). El servidor rechaza deshacer descartes ajenos o viejos. */
export async function deshacerDescarte(leadId: string): Promise<void> {
  const { error } = await cliente().schema('crm').rpc('deshacer_descarte', {
    p_lead: leadId,
  })
  if (error) throw aErrorApi(error, 'crm.descarte.deshacer_fallido')
}

// ── C1-ter: la pestaña "Descartados" del coordinador (solo lectura) ──────────
const MOTIVOS_K = MOTIVOS_DESCARTE.map((m) => m.k) as [MotivoDescarte, ...MotivoDescarte[]]
const LeadDescartadoSchema = v.object({
  id: v.string(),
  nombre_completo: v.string(),
  distrito: v.nullable(v.string()),
  origen: v.picklist(ORIGENES_K),
  categoria_interes: v.nullable(v.picklist(CATEGORIAS_K)),
  monto_estimado: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  moneda: v.picklist(['PEN', 'USD'] as const),
  creado_en: v.string(),
  clasificacion_auto: v.optional(v.nullable(v.picklist(['posible_credito'] as const)), null),
  comentario: v.optional(v.nullable(v.string()), null),
  nota_descarte: v.optional(v.nullable(v.string()), null),
  motivo_descarte: v.nullable(v.picklist(MOTIVOS_K)),
  descartado_en: v.string(),
  descartado_por_nombre: v.string(),
  es_mio: v.boolean(),
  puede_deshacer: v.boolean(),
})

/** Lista los descartes recientes de la cola global (últimos 30 días, tope 200,
 *  más nuevos primero). Solo coordinador/gerencia; el servidor filtra alcance,
 *  redacta la PII y marca `puede_deshacer` (que igual re-valida al deshacer). */
export async function leadsDescartados(signal?: AbortSignal): Promise<LeadDescartado[]> {
  let consulta = cliente().schema('crm').rpc('leads_descartados')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la lista de descartados.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.descarte.lista_fallida', fallo)
    throw fallo
  }
  const items: LeadDescartado[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(LeadDescartadoSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

// ── Base para gestión: descartes históricos de supervisión ───────────────────
const EstadoRescateSchema = v.picklist(['pendiente', 'rescatado', 'historial'] as const)
const EpisodioRescateDescarteSchema = v.object({
  episodio_id: v.string(),
  lead_id: v.string(),
  nombre_completo: v.string(),
  distrito: v.nullable(v.string()),
  origen: v.picklist(ORIGENES_K),
  categoria_interes: v.nullable(v.picklist(CATEGORIAS_K)),
  monto_estimado: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
  moneda: v.picklist(['PEN', 'USD'] as const),
  motivo_descarte: v.picklist(MOTIVOS_K),
  descartado_en: v.string(),
  asesor_id: v.string(),
  asesor_nombre: v.string(),
  puede_rescatar: v.boolean(),
  estado: EstadoRescateSchema,
  /** B6 (Miguel, 03/10/2026): seguimiento activo del analista — intento de la base hace 7 días o menos, o rellamada
   *  vigente. Mientras dure, `puede_rescatar` llega en false y la fila se pinta en gris. Opcionales: el servidor sin
   *  B6 no los manda. `en_gestion_hasta` es una fecha 'YYYY-MM-DD' (día de Lima). */
  en_gestion_por: v.optional(v.nullable(v.string()), null),
  en_gestion_hasta: v.optional(v.nullable(v.string()), null),
})
const MesRescateDescartesSchema = v.object({
  mes: v.string(),
  total: EnteroNoNegativoRpcSchema,
  pendientes: EnteroNoNegativoRpcSchema,
})

/** Meses disponibles en el historial de descartes del equipo del supervisor. */
export async function mesesRescateDescartes(signal?: AbortSignal): Promise<MesRescateDescartes[]> {
  let consulta = cliente().schema('crm').rpc('rescate_descartes_meses')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rescate.meses_fallido')
  const items: MesRescateDescartes[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(MesRescateDescartesSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

/** Episodios descartados de un mes. No expone PII de contacto ni notas libres. */
export async function descartesRescateDelMes(mes: string, signal?: AbortSignal): Promise<EpisodioRescateDescarte[]> {
  let consulta = cliente().schema('crm').rpc('rescate_descartes_mes', { p_mes: mes })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rescate.historial_fallido')
  const items: EpisodioRescateDescarte[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(EpisodioRescateDescarteSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

/**
 * Reactiva los descartes vigentes como leads nuevos y los distribuye en ronda
 * entre uno o varios analistas. La base conserva el episodio anterior y abre
 * el nuevo ciclo de gestión; el servidor revalida equipo, estado y No Insista.
 */
export async function rescatarDescartes(
  episodioIds: string[],
  asesoresDestinoIds: string[],
  evitarAsesorOrigen = true,
): Promise<void> {
  const { error } = await cliente().schema('crm').rpc('rescatar_descartes', {
    p_episodios: episodioIds,
    p_analistas_destino: asesoresDestinoIds,
    p_evitar_asesor_origen: evitarAsesorOrigen,
  })
  if (error) throw aErrorApi(error, 'crm.rescate.reparto_fallido')
}

// ── Base para gestión del analista (B3 `crm.obtener_base_gestion`, en producción 02/10/2026) ──────────
/**
 * Los leads descartados que el actor puede volver a gestionar, ya ordenados por el servidor (rellamada de
 * hoy → etapa máxima → menos días desde el descarte). El analista recibe SOLO los suyos; Supervisión y
 * Gerencia, su ámbito o el de un analista (`vendedorId`). Excluye «no contactar» y descanso vigente.
 * Una fila fuera de contrato no se pinta, pero se registra: la lista no se recorta en silencio.
 */
export async function obtenerBaseGestion(vendedorId?: string | null, signal?: AbortSignal): Promise<FilaBaseGestion[]> {
  let consulta = cliente().schema('crm').rpc('obtener_base_gestion', vendedorId ? { p_vendedor_id: vendedorId } : {})
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.base_gestion.lista_fallida')
  const filas: FilaBaseGestion[] = []
  let invalidas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(FilaBaseGestionSchema, cruda)
    if (r.success) filas.push(r.output)
    else invalidas += 1
  }
  if (invalidas > 0) registrarError('crm.base_gestion.filas_fuera_de_contrato', new Error(`${invalidas} filas descartadas`), { invalidas })
  return filas
}

// ── Timeline del ámbito con AUTOR (RPC SECURITY DEFINER actividades_del_ambito_fn)
const TIPOS_ACT = Object.keys(TIPOS_ACTIVIDAD) as [TipoActividad, ...TipoActividad[]]
const ActividadRowSchema = v.object({
  id: v.string(),
  lead_id: v.string(),
  tipo: v.picklist(TIPOS_ACT),
  detalle: v.nullable(v.string()),
  autor_nombre: v.string(),
  creado_en: v.string(),
  // Desde Gestión Diaria F2 el historial trae la metadata (resultado de llamada);
  // las RPC que aún no la mandan siguen validando: opcional.
  metadata: v.optional(v.record(v.string(), v.unknown())),
})

// ── Actividad reciente del ámbito (RPC SECURITY INVOKER crm.actividades_recientes_fn,
// Fase 3 «sin topes»). Sustituye a la descarga del registro entero
// (`actividades_del_ambito_fn`, recortada a 1 000 filas por PostgREST) que el
// arranque hacía para que UNA pantalla pintara 8 filas. Es una bitácora, no una
// página: no hay cursor ni «hay más».
export const TAMANO_BITACORA_RECIENTES = 8

const ActividadRecienteRowSchema = v.object({
  ...ActividadRowSchema.entries,
  // Bajo `leads_select`, co-extensiva con `actividades_select`: viene casi
  // siempre; si no, la pantalla lo rotula, nunca lo inventa.
  lead_nombre: v.nullable(v.string()),
})

const ActividadesRecientesSchema = v.object({
  version: v.literal(1),
  items: v.array(v.unknown()),
})

export async function listarActividadesRecientes(
  limite: number = TAMANO_BITACORA_RECIENTES,
  signal?: AbortSignal,
): Promise<ActividadReciente[]> {
  const argumentos: Database['crm']['Functions']['actividades_recientes_fn']['Args'] = { p_limite: limite }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('actividades_recientes_fn', argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo =
      error.code === '42501'
        ? new CrmApiError('Tu cuenta no tiene acceso a la actividad del CRM.', '42501')
        : new CrmApiError('No se pudo cargar la actividad reciente.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.actividades.recientes_fallido', fallo, { limite })
    throw fallo
  }
  const payload = v.safeParse(ActividadesRecientesSchema, data)
  if (!payload.success) {
    throw new CrmApiError('La actividad reciente no cumple el contrato esperado.', 'ROW_CONTRACT')
  }
  if (payload.output.items.length > limite) {
    throw new CrmApiError('La actividad reciente devolvió más filas de las pedidas.', 'ROW_CONTRACT')
  }
  const items: ActividadReciente[] = []
  let descartadas = 0
  for (const cruda of payload.output.items) {
    const r = v.safeParse(ActividadRecienteRowSchema, cruda)
    if (r.success) items.push(r.output)
    else descartadas += 1
  }
  if (descartadas > 0) {
    // CONTADAS (no en silencio): un tipo nuevo en la base desaparecería de la
    // bitácora de todos sin que nadie se enterara.
    registrarError(
      'crm.actividades.recientes_filas_invalidas',
      new CrmApiError('Filas de la actividad reciente fuera de contrato', 'ROW_CONTRACT'),
      { descartadas, recibidas: payload.output.items.length },
    )
  }
  return items
}

// ── Historial de UN lead (RPC SECURITY INVOKER crm.actividades_de_lead_fn,
//    migración 20260919185718 — Fase 1 del plan «sin topes») ─────────────────
// El historial deja de filtrarse en el navegador de la lista global del ámbito
// (que PostgREST recorta a 1 000 filas y decapitaba a supervisores y gerencia):
// se pide POR LEAD, paginado por cursor keyset (creado_en desc, id asc) y sin
// ventana de fecha. El servidor responde 42501 si el lead no es visible —
// nunca un historial vacío que se confunda con «sin gestiones».
export const TAMANO_PAGINA_HISTORIAL = 100

/** Posición exacta en el orden `(creado_en desc, id asc)`. */
export interface CursorHistorial {
  creadoEn: string
  id: string
}

export interface PaginaHistorial {
  items: Actividad[]
  /** `null` = no hay más páginas; nunca se infiere de `items.length`. */
  cursor: CursorHistorial | null
  /** Señales «alguna vez» sobre TODO el historial (viajan en cada página; valen las de la primera). */
  senales: SenalesLead
}

const HistorialLeadSchema = v.object({
  version: v.literal(1),
  items: v.array(v.unknown()),
  senales: v.object({
    tiene_reunion_realizada: v.boolean(),
    tiene_contacto: v.boolean(),
    ultima_conversacion_en: v.nullable(v.string()),
  }),
})

/** Lo MÍNIMO para poder avanzar: si la última fila cruda no lo cumple, no hay cursor honesto. */
const CursorHistorialRowSchema = v.object({
  id: v.string(),
  creado_en: v.string(),
})

export async function listarActividadesDeLead(
  leadId: string,
  cursor: CursorHistorial | null,
  signal?: AbortSignal,
): Promise<PaginaHistorial> {
  // Se pide UNA fila de más: distingue «hay más» de «justo cabía» sin gastar
  // una petición extra que vuelva vacía al final del historial.
  const argumentos: Database['crm']['Functions']['actividades_de_lead_fn']['Args'] = {
    p_lead_id: leadId,
    p_limite: TAMANO_PAGINA_HISTORIAL + 1,
  }
  if (cursor) {
    argumentos.p_antes_de = cursor.creadoEn
    argumentos.p_antes_id = cursor.id
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('actividades_de_lead_fn', argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    // 42501 NO es «se cayó el servidor»: es la denegación explícita de la
    // puerta (lead fuera del ámbito, borrado o cuenta ajena al CRM).
    const fallo =
      error.code === '42501'
        ? new CrmApiError('Este lead ya no está en tu cartera.', '42501')
        : new CrmApiError('No se pudo cargar el historial del lead.', error.code || 'POSTGREST_ERROR')
    // Sin el id del lead: el canal de observabilidad no lleva identificadores.
    registrarError('crm.actividades.lead_fallido', fallo, { conCursor: cursor != null })
    throw fallo
  }
  const payload = v.safeParse(HistorialLeadSchema, data)
  if (!payload.success) {
    throw new CrmApiError('El historial del lead no cumple el contrato esperado.', 'ROW_CONTRACT')
  }
  const crudas = payload.output.items
  if (crudas.length > TAMANO_PAGINA_HISTORIAL + 1) {
    throw new CrmApiError('El historial del lead devolvió más filas de las pedidas.', 'ROW_CONTRACT')
  }
  const hayMas = crudas.length > TAMANO_PAGINA_HISTORIAL
  const ventana = hayMas ? crudas.slice(0, TAMANO_PAGINA_HISTORIAL) : crudas

  const items: Actividad[] = []
  let descartadas = 0
  for (const cruda of ventana) {
    const r = v.safeParse(ActividadRowSchema, cruda)
    // Una fila de OTRO lead sería un bug del servidor, no un dato: fuera.
    if (r.success && r.output.lead_id === leadId) items.push(r.output)
    else descartadas += 1
  }
  if (descartadas > 0) {
    // A diferencia del listado global (que las tiraba en silencio), aquí una
    // fila fuera de contrato SE CUENTA: un tipo nuevo en la base desaparecería
    // del historial de todos sin que nadie se enterara.
    registrarError(
      'crm.actividades.lead_filas_invalidas',
      new CrmApiError('Filas del historial fuera de contrato', 'ROW_CONTRACT'),
      { descartadas, pagina: ventana.length },
    )
  }

  // El cursor sale de la ÚLTIMA FILA CRUDA de la ventana, no de la última
  // válida: avanzar desde una fila anterior repetiría filas, y anular el cursor
  // cortaría el historial fingiendo que ya no hay nada.
  const ultima = ventana.at(-1)
  const cursorCrudo = ultima !== undefined ? v.safeParse(CursorHistorialRowSchema, ultima) : null
  if (hayMas && !cursorCrudo?.success) {
    throw new CrmApiError('No se puede avanzar en el historial del lead.', 'ROW_CONTRACT')
  }
  const s = payload.output.senales
  return {
    items,
    cursor: hayMas && cursorCrudo?.success
      ? { creadoEn: cursorCrudo.output.creado_en, id: cursorCrudo.output.id }
      : null,
    senales: {
      tieneReunionRealizada: s.tiene_reunion_realizada,
      tieneContacto: s.tiene_contacto,
      ultimaConversacionEn: s.ultima_conversacion_en,
    },
  }
}

/**
 * Precheck consultivo P-048. No reserva ni inserta el contacto: una carrera se
 * resuelve después dentro de crear_lead_si_disponible; los índices únicos son
 * solo la última defensa frente a escritores externos al protocolo.
 */
export async function verificarDisponibilidadLead(
  telefono: string,
  dni?: string | null,
  signal?: AbortSignal,
): Promise<DisponibilidadLead> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente()
    .schema('crm')
    .rpc(
      'verificar_disponibilidad_lead',
      sinIndefinidos({
        p_telefono: telefono,
        p_dni: dni ?? undefined,
      }),
    )
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error, status } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    // PGRST106 = esquema no expuesto; PGRST202 = función ausente del cache.
    // No son una caída transitoria de red y el formulario no debe tratarlos
    // como fail-open: indican que P-048 está mal configurado en ese entorno.
    if (error.code === 'PGRST106' || error.code === 'PGRST202') {
      const fallo = new CrmApiError(
        'La verificación de disponibilidad no está habilitada.',
        'DISPONIBILIDAD_NO_DISPONIBLE',
      )
      registrarError('crm.leads.disponibilidad_no_disponible', fallo, {
        postgrest: error.code,
      })
      throw fallo
    }
    // postgrest-js representa un fetch fallido con status=0; PGRST000–003 son
    // indisponibilidad/conexión/pool de PostgREST. Son los únicos fallos del
    // servidor que P-048 trata como cortesía fail-open. Un HTTP malformado sin
    // code pero con status real NO se confunde con transporte.
    if (status === 0 || ['PGRST000', 'PGRST001', 'PGRST002', 'PGRST003'].includes(error.code)) {
      const fallo = new CrmApiError('No se pudo contactar el servicio de disponibilidad.', 'DISPONIBILIDAD_RED')
      registrarError('crm.leads.disponibilidad_red', fallo, {
        postgrest: error.code || 'sin_codigo',
      })
      throw fallo
    }
    throw aErrorApi(error, 'crm.leads.disponibilidad_fallida')
  }

  const resultado = v.safeParse(DisponibilidadLeadSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'La disponibilidad del contacto no tiene el formato esperado.',
      'DISPONIBILIDAD_CONTRACT',
    )
    registrarError('crm.leads.disponibilidad_fuera_de_contrato', fallo)
    throw fallo
  }

  return resultado.output
}

// ── F3 «Recordar»: crm.recordatorios_disponibilidad ──────────────────────────
// Acceso directo a la tabla: la RLS es owner-only real y el trigger de
// sellado firma autoría, normaliza el teléfono y acota la fecha — el front
// no re-implementa nada de eso, solo valida la FORMA de lo que vuelve.

export async function listarRecordatoriosDisponibilidad(signal?: AbortSignal): Promise<RecordatorioCampana[]> {
  // SIN dni a propósito (minimización §8, F3.1): la campana no lo usa y cada
  // refetch lo paseaba por la red sin ningún consumidor.
  let consulta = cliente()
    .schema('crm')
    .from('recordatorios_disponibilidad')
    .select('id, perfil_id, telefono, recordar_en, creado_en')
    .order('recordar_en', { ascending: true })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.recordatorios.listar_fallido')
  const resultado = v.safeParse(RecordatoriosCampanaSchema, data ?? [])
  if (!resultado.success) {
    const fallo = new CrmApiError('Los recordatorios no tienen el formato esperado.', 'RECORDATORIOS_CONTRACT')
    registrarError('crm.recordatorios.fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Crea O reprograma (upsert por la llave UNIQUE perfil_id+telefono — el
 * trigger BEFORE sella la autoría ANTES de evaluar el conflicto, así que la
 * llave siempre es la del actor). `perfilId` viaja solo porque el tipo
 * generado lo exige (NOT NULL sin default): el servidor lo RE-SELLA con
 * auth.uid() igual — mandar el ajeno no cuela nada. `recordarEn` es ISO;
 * el servidor exige futuro con tope 365 días (22023 si no).
 */
export async function guardarRecordatorioDisponibilidad(
  perfilId: string,
  telefono: string,
  dni: string | null,
  recordarEn: string,
): Promise<RecordatorioDisponibilidad> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('recordatorios_disponibilidad')
    .upsert(
      // `dni` viaja SIEMPRE, null incluido (F3.1): omitirlo hacía que un
      // re-guardado sin DNI CONSERVARA el DNI anterior en el servidor — un
      // vínculo teléfono↔DNI que el analista ya no está afirmando. El dato
      // fresco manda: sin DNI = limpiar el anterior.
      { perfil_id: perfilId, telefono, dni, recordar_en: recordarEn },
      { onConflict: 'perfil_id,telefono' },
    )
    .select('id, perfil_id, telefono, dni, recordar_en, creado_en')
    .single()
  if (error) throw aErrorApi(error, 'crm.recordatorios.guardar_fallido')
  const resultado = v.safeParse(RecordatorioDisponibilidadSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError('El recordatorio guardado no tiene el formato esperado.', 'RECORDATORIOS_CONTRACT')
    registrarError('crm.recordatorios.guardado_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

export async function eliminarRecordatorioDisponibilidad(id: string): Promise<void> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('recordatorios_disponibilidad')
    .delete()
    .eq('id', id)
    .select('id')
  if (error) throw aErrorApi(error, 'crm.recordatorios.eliminar_fallido')
  if (!data || data.length === 0) {
    // La RLS lo ocultó (no es suyo) o ya caducó solo: mismo mensaje neutro.
    throw new CrmApiError('El recordatorio ya no existe.', 'NO_ENCONTRADO')
  }
}

// ── F4 «sin ruido»: crm.alertas_reconocimientos ──────────────────────────────
// El libro INMUTABLE de reconocimientos del supervisor: solo INSERT (el
// trigger sella autoría y fecha, ata el alerta_id al actor y acota posponer
// a 7 días). El front no re-implementa nada de eso: valida la FORMA.

export async function listarReconocimientosAlertas(
  signal?: AbortSignal,
): Promise<AsientoReconocimiento[]> {
  // Se lee la VISTA de vigentes, no la tabla: la vigencia (≤7 días, y el
  // `hasta` de posponer) la corta el reloj de POSTGRES — un dispositivo
  // atrasado no puede alargar un silencio (bloqueante Codex F4.2 #2; la
  // lección de [[prueba-de-fechas-en-tu-propia-zona]]). El tope de filas es
  // holgado para clics humanos sobre ≤4 alertas; si alguna vez se alcanzara,
  // el fallo va en la dirección segura: un asiento que no llega hace SONAR
  // la alerta de más, nunca la calla de menos.
  let consulta = cliente().schema('crm')
    .from('alertas_reconocimientos_vigentes')
    .select('id, alerta_id, accion, miembros, severidad, hasta, creado_en, secuencia')
    .order('secuencia', { ascending: false })
    .limit(1000)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.reconocimientos.listar_fallido')
  const resultado = v.safeParse(AsientosReconocimientoSchema, data ?? [])
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'Los reconocimientos no tienen el formato esperado.',
      'RECONOCIMIENTOS_CONTRACT',
    )
    registrarError('crm.reconocimientos.fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Asienta un reconocimiento («ya lo atiendo») o una posposición con fecha.
 * `perfilId` viaja solo porque el tipo generado lo exige (NOT NULL sin
 * default): el trigger lo RE-SELLA con auth.uid() — mandar el ajeno no cuela
 * nada. El servidor rechaza (42501/22023) alertas ajenas, fotos con ids
 * inválidos y posposiciones pasadas o de más de 7 días.
 */
export async function reconocerAlertaSupervisor(
  perfilId: string,
  alertaId: string,
  accion: AccionReconocimiento,
  miembros: readonly string[],
  severidad: SeveridadAlerta,
  hasta: string | null,
): Promise<void> {
  const { error } = await cliente().schema('crm')
    .from('alertas_reconocimientos')
    .insert({
      perfil_id: perfilId,
      alerta_id: alertaId,
      accion,
      miembros: [...miembros],
      severidad,
      hasta,
    })
  if (error) throw aErrorApi(error, 'crm.reconocimientos.guardar_fallido')
}

/**
 * F2 «Tomar» (spec §5.6/§5.7): toma directa POR CONTACTO contra
 * crm.tomar_lead_libre. Es una MUTACIÓN — a diferencia del precheck
 * consultivo, aquí no existe cortesía fail-open: cualquier fallo se lanza y
 * el formulario lo dice sin fingir nada. La respuesta es o `tomado_ok` o el
 * veredicto fresco de disponibilidad (el servidor jamás roba al perdedor de
 * la carrera; devuelve la verdad del momento para re-presentarla).
 */
export async function tomarLeadLibre(telefono: string, dni?: string | null): Promise<ResultadoTomaLead> {
  const { data, error } = await cliente()
    .schema('crm')
    .rpc(
      'tomar_lead_libre',
      sinIndefinidos({
        p_telefono: telefono,
        p_dni: dni ?? undefined,
      }),
    )
  if (error) throw aErrorApi(error, 'crm.leads.toma_fallida')

  const resultado = v.safeParse(ResultadoTomaLeadSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError('El servidor no confirmó la toma del lead.', 'TOMA_LEAD_CONTRACT')
    registrarError('crm.leads.toma_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

// ── Mutaciones reales (insert/update; RLS + triggers del servidor mandan) ─────
type LeadUpdate = Database['crm']['Tables']['leads']['Update']
type CrearLeadArgs = Database['crm']['Functions']['crear_lead_si_disponible']['Args']

/** DTO de la única vía de alta. Omite a propósito campos gobernados por el
 * servidor (`creado_por`, `asignado_supervisor_id`, flags legales y sellos). */
export interface CrearLeadAtomicoInput {
  id?: NonNullable<CrearLeadArgs['p_id']>
  nombre_completo: CrearLeadArgs['p_nombre_completo']
  telefono: CrearLeadArgs['p_telefono']
  telefono_alternativo?: string | null
  correo?: CrearLeadArgs['p_correo'] | null
  dni?: CrearLeadArgs['p_dni'] | null
  documento?: DocumentoIdentidad
  genero?: CrearLeadArgs['p_genero'] | null
  fecha_nacimiento?: CrearLeadArgs['p_fecha_nacimiento'] | null
  distrito?: CrearLeadArgs['p_distrito'] | null
  origen: CrearLeadArgs['p_origen']
  etapa?: CrearLeadArgs['p_etapa']
  monto_estimado: CrearLeadArgs['p_monto_estimado']
  moneda: CrearLeadArgs['p_moneda']
  categoria_interes?: CrearLeadArgs['p_categoria_interes'] | null
  vendedor_id?: CrearLeadArgs['p_vendedor_id'] | null
  nota?: CrearLeadArgs['p_nota'] | null
}
type ActividadInsert = Database['crm']['Tables']['actividades']['Insert']

/**
 * Traduce un error de PostgREST a un CrmApiError con código estable y mensaje
 * es-PE seguro (nunca el texto crudo de Postgres, salvo los RAISE propios).
 */
function aErrorApi(
  error: {
    code?: string | null
    message?: string | null
    details?: string | null
  },
  contexto: string,
): CrmApiError {
  const codigoPg = error.code ?? ''
  const texto = `${error.message ?? ''} ${error.details ?? ''}`
  let code = 'POSTGREST_ERROR'
  let mensaje = 'No se pudo guardar el cambio.'
  if (codigoPg === '23505') {
    // Índices únicos parciales del dedup GLOBAL (uq_leads_*_vivo): el espejo
    // local solo ve el ámbito; el servidor cubre choques con leads ajenos.
    if (texto.includes('uq_leads_telefono_vivo')) {
      code = 'DUP_TELEFONO'
      mensaje = 'Ese teléfono ya pertenece a otro lead abierto de la empresa'
    } else if (texto.includes('uq_leads_dni_vivo')) {
      code = 'DUP_DNI'
      mensaje = 'Ese DNI ya pertenece a otro lead abierto de la empresa'
    } else if (texto.includes('perfiles_dni')) {
      // Índices parciales del portal (perfiles_dni_cliente_key / _staff_key):
      // corregir el documento de un cliente puede chocar con otro cliente.
      code = 'DUP_DNI_CLIENTE'
      mensaje = 'Ese documento ya pertenece a otro cliente del portal'
    } else if (texto.includes('perfiles_correo')) {
      code = 'DUP_CORREO'
      mensaje = 'Ese correo ya está registrado en el portal'
    }
  } else if (
    (codigoPg === '23502' && texto.includes('monto_estimado')) ||
    (codigoPg === '23514' && texto.includes('leads_monto_estimado_valido'))
  ) {
    code = 'MONTO_INVALIDO'
    mensaje = 'El capital estimado es obligatorio y debe ser mayor que 0'
  } else if (codigoPg === '23514' && texto.includes('datos legales obligatorios')) {
    // El RAISE de private.contrato_pdf_snapshot_v2_base. Caía en el genérico
    // "No se pudo guardar el cambio.", que es lo que de verdad veían los
    // analistas cuando un cliente antiguo no tenía domicilio: un mensaje que
    // no nombra ni el dato ni al culpable, imposible de diagnosticar desde la
    // pantalla. El texto del servidor no lleva PII, pero tampoco dice QUÉ falta.
    code = 'DATOS_LEGALES_INCOMPLETOS'
    mensaje =
      'Faltan datos legales para emitir el contrato: revisa el domicilio, ' +
      'el documento y el correo del cliente, y tu propio celular y correo.'
  } else if (codigoPg === '42501' || codigoPg === 'PGRST301') {
    code = 'SIN_PERMISO'
    mensaje = 'No tienes permiso para esa acción'
  } else if (codigoPg === 'P0429') {
    // Veto LEGAL (Ley 29571 "No Insista") de crm.repartir_lead — código propio,
    // deliberadamente distinto de 42501: no es falta de permiso, es prohibición.
    code = 'NO_INSISTA'
    mensaje = error.message ?? 'Lead marcado No Insista (Ley 29571): no se puede repartir'
  } else if (codigoPg === 'P0002') {
    // El lead salió de la cola (ya tiene dueño, se cerró) o se perdió la carrera.
    code = 'FUERA_DE_COLA'
    mensaje = error.message ?? 'El lead ya no está en la cola por repartir'
  } else if (codigoPg === '55P03') {
    // lock_not_available: otra sesión tiene la fila del cliente y venció el
    // lock_timeout. Sin esta rama caía en el genérico «No se pudo guardar el
    // cambio.», que aquí es directamente falso: no falló, no llegó a intentarlo.
    code = 'REINTENTAR'
    mensaje = 'Otro usuario está editando a este cliente ahora mismo. Vuelve a intentarlo.'
  } else if (codigoPg === '40001') {
    // Carrera bajo aislamiento serializable (defensivo: el default es READ COMMITTED).
    code = 'REINTENTAR'
    mensaje = 'El lead se estaba repartiendo en simultáneo. Vuelve a intentarlo.'
  } else if (codigoPg === '40P01') {
    // Interbloqueo detectado por Postgres (una puerta y la ficha se cruzaron):
    // la transacción entera se deshizo; repetir suele bastar (auditor bloque 4 #9).
    code = 'REINTENTAR'
    mensaje = 'Dos operaciones se cruzaron sobre este lead. Vuelve a intentarlo.'
  } else if (codigoPg === 'P0481') {
    code = 'CONTACTO_NO_DISPONIBLE'
    mensaje = 'Ese teléfono o DNI no está disponible para este lead.'
  } else if (codigoPg === 'P0410') {
    // Rentabilidad R4: el candado del servidor rechazó la tasa. El mensaje ya viene en idioma de negocio
    // («la fija la política: 15%…», «el upgrade debe declarar el contrato que amplía»), sin PII: se muestra tal cual.
    code = 'TASA_FUERA_DE_POLITICA'
    mensaje = error.message ?? 'La tasa de este contrato la fija la política de rentabilidad.'
  } else if (codigoPg === 'P0409' && texto.includes('ya creó el contrato')) {
    // Idempotencia del alta: la misma clave llegó con OTROS datos y el intento
    // anterior SÍ creó el contrato. El servidor no creó otro ni devolvió el viejo
    // como si fuera el nuevo: lo dice, con el número, y el modal decide qué hacer.
    code = 'ALTA_YA_CREADA'
    mensaje = error.message ?? mensaje
  } else if (codigoPg === 'P0409' && texto.includes('fue eliminado después')) {
    // Lápida: el contrato de ese intento fue eliminado a propósito; el reintento
    // tardío no lo recrea. El modal libera la clave y pide volver a pulsar.
    code = 'ALTA_ELIMINADA'
    mensaje = error.message ?? mensaje
  } else if (codigoPg === '55000' && texto.includes('en proceso de eliminación')) {
    // Gerencia preparó la eliminación del contrato de este intento (o del contrato
    // cuyo PDF se pide) y la edge aún no finalizó (migración 20260905234500, m3).
    // No se creó nada. El modal NO libera la clave: cuando el borrado termine, el
    // reintento cae solo en la lápida P0409; si Gerencia se arrepiente, en el replay.
    code = 'CONTRATO_EN_ELIMINACION'
    mensaje = 'Gerencia está eliminando el contrato de tu intento anterior; no se creó otro. Espera a que termine o consúltalo antes de volver a intentar.'
  } else if (codigoPg === 'P0409' && texto.includes('se fija por su puerta')) {
    // Con la identidad encendida, la fila completa que manda la ficha lleva el DNI
    // que el analista VE; si otro usuario lo cambió mientras tanto, el servidor
    // rechaza el UPDATE directo del documento. No editó el DNI: la ficha está vieja.
    code = 'CONFLICTO'
    mensaje = 'La ficha cambió en otra sesión (el documento ya no es el que ves): recarga y vuelve a intentarlo'
  } else if (codigoPg === 'P0409') {
    // Conflicto de ESTADO que levantan nuestras puertas (F2.b: «la persona ya es
    // cliente o ya tiene su lead», «solo lo corrige Gerencia», «conversión en
    // curso», «solo se puede reabrir un descartado»). El texto ya viene en idioma
    // de negocio y sin PII: se muestra tal cual, en vez del genérico que lo tapaba.
    code = 'CONFLICTO'
    if (error.message) mensaje = error.message
  } else if (codigoPg === 'P0001' || codigoPg === '22023') {
    // RAISE EXCEPTION de nuestros propios triggers/RPCs (es-PE, sin PII);
    // 22023 = validaciones de parámetros de las RPC operativas.
    code = 'REGLA_SERVIDOR'
    if (error.message) mensaje = error.message
  }
  const fallo = new CrmApiError(mensaje, code)
  registrarError(contexto, fallo, { pg: codigoPg })
  return fallo
}

function aErrorInsertarLead(error: {
  code?: string | null
  message?: string | null
  details?: string | null
}): CrmApiError {
  if (error.code === '55P03' || error.code === '40P01') {
    const fallo = new CrmApiError(
      'Otro usuario está procesando este contacto. Inténtalo nuevamente.',
      'CONTACTO_EN_PROCESO',
    )
    registrarError('crm.leads.creacion_atomica_en_espera', fallo, {
      pg: error.code,
    })
    return fallo
  }

  if (error.code === 'P0481') {
    try {
      const detalle: unknown = JSON.parse(error.details ?? '')
      const resultado = v.safeParse(DisponibilidadLeadSchema, detalle)
      if (resultado.success) {
        const presentacion = presentarDisponibilidadLead(resultado.output)
        const fallo = new CrmApiError(
          presentacion.mensaje ?? 'Este contacto no está disponible para un nuevo lead',
          'CONTACTO_NO_DISPONIBLE',
        )
        registrarError('crm.leads.creacion_atomica_bloqueada', fallo, {
          estado: resultado.output.estado,
        })
        return fallo
      }
    } catch {
      // Un DETAIL roto no se refleja ni se registra: cae al error genérico.
    }
  }

  const texto = `${error.message ?? ''} ${error.details ?? ''}`
  const esCarreraDelContacto =
    error.code === '23505' && (texto.includes('uq_leads_telefono_vivo') || texto.includes('uq_leads_dni_vivo'))
  if (!esCarreraDelContacto) return aErrorApi(error, 'crm.leads.insert_fallido')

  // La RPC es la autoridad. El índice único queda como última defensa ante un
  // escritor que todavía no comparta el protocolo de candados.
  const fallo = new CrmApiError('Este contacto acaba de ser registrado por otro usuario', 'CONTACTO_RECIEN_REGISTRADO')
  registrarError('crm.leads.insert_fallido', fallo, { pg: '23505' })
  return fallo
}

export async function insertarLead(fila: CrearLeadAtomicoInput): Promise<ResultadoCreacionLeadAtomica> {
  const { documento, dni: _dni, ...datosTipados } = fila
  const { data, error } = documento
    ? await cliente().schema('crm').rpc('crear_lead_documento_fn', {
      p_datos: sinIndefinidos(datosTipados) as Json,
      p_tipo: documento.tipo,
      p_documento: documento.numero ?? '',
    })
    : await cliente()
    .schema('crm')
    .rpc(
      'crear_lead_si_disponible',
      sinIndefinidos({
        p_nombre_completo: fila.nombre_completo,
        p_telefono: fila.telefono,
        p_origen: fila.origen,
        p_monto_estimado: fila.monto_estimado,
        p_moneda: fila.moneda,
        // Todos con DEFAULT NULL en el catálogo (16/08): omitir la clave ≡ null.
        p_id: fila.id ?? undefined,
        p_correo: fila.correo ?? undefined,
        p_dni: fila.dni ?? undefined,
        p_genero: fila.genero ?? undefined,
        p_fecha_nacimiento: fila.fecha_nacimiento ?? undefined,
        p_distrito: fila.distrito ?? undefined,
        p_etapa: fila.etapa ?? 'nuevo',
        p_categoria_interes: fila.categoria_interes ?? undefined,
        p_vendedor_id: fila.vendedor_id ?? undefined,
        p_nota: fila.nota ?? undefined,
        p_telefono_alternativo: fila.telefono_alternativo ?? undefined,
      }),
    )
  if (error) throw aErrorInsertarLead(error)

  const resultado = v.safeParse(ResultadoCreacionLeadAtomicaSchema, data)
  if (!resultado.success || resultado.output.estado === 'libre') {
    const fallo = new CrmApiError('El servidor no confirmó la creación del lead.', 'CREACION_LEAD_CONTRACT')
    registrarError('crm.leads.creacion_atomica_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

export async function actualizarLead(id: string, cambios: LeadUpdate): Promise<void> {
  const { data, error } = await cliente().schema('crm').from('leads').update(cambios).eq('id', id).select('id')
  if (error) throw aErrorApi(error, 'crm.leads.update_fallido')
  if (!data || data.length === 0) {
    // La RLS ocultó el lead (fuera del ámbito) o no existe: mismo mensaje,
    // sin revelar existencia (igual que el espejo del store).
    throw new CrmApiError('Lead no encontrado', 'NO_ENCONTRADO')
  }
}

/**
 * F2.b [D-15]: el botón «Reabrir» (descartado → nuevo) pasa por su puerta SQL en vez
 * de actualizar la fila. Con la identidad unificada apagada es el UPDATE de siempre
 * (mismos triggers, mismos índices de contacto vivo); encendida, el servidor juzga
 * a la PERSONA (P0429 «No insistir»; P0409 otro lead suyo, conversión en curso o ya
 * cliente) y enlaza el lead. El 23505 de un teléfono/DNI ya vivo llega igual que hoy.
 */
export async function reabrirLead(leadId: string): Promise<void> {
  const { error } = await cliente().schema('crm').rpc('reabrir_lead_fn', { p_lead_id: leadId })
  if (error) throw aErrorApi(error, 'crm.leads.reabrir_fallido')
}

/**
 * F2.b [D-15]: la edición de la ficha del lead va por UNA RPC transaccional
 * (`crm.editar_lead_fn`, SECURITY INVOKER: el UPDATE corre con la RLS y los grants
 * por columna de quien edita, solo con las columnas que manda la ficha, como el
 * UPDATE directo de hoy). Con la identidad encendida el DNI pasa antes por su
 * puerta (`fijar_dni_lead_fn`: candados documento → persona → fila, juicio y
 * enlace) DENTRO de la misma transacción: si el resto falla, el DNI tampoco queda
 * y dos ediciones simultáneas no se mezclan (Codex bloque 4 #1). Los rechazos de
 * la puerta llegan con el texto del servidor (P0409 → CONFLICTO, P0429 → NO_INSISTA).
 */
export async function editarLeadFn(leadId: string, cambios: LeadUpdate & {
  documento?: DocumentoIdentidad
  correccion_documento?: CorreccionDocumentoLead
}): Promise<void> {
  const { documento, correccion_documento, dni: _dni, ...resto } = cambios
  const { data, error } = documento
    ? await cliente().schema('crm').rpc('editar_lead_documento_fn', {
      p_lead_id: leadId, p_cambios: resto as Json,
      p_tipo: documento.tipo, p_documento: documento.numero ?? '',
      ...(correccion_documento?.identificador_anterior ? { p_identificador_anterior: correccion_documento.identificador_anterior } : {}),
      ...(correccion_documento?.motivo ? { p_motivo: correccion_documento.motivo } : {}),
    })
    : await cliente()
    .schema('crm')
    .rpc('editar_lead_fn', { p_lead_id: leadId, p_cambios: cambios as Json })
  if (error) throw aErrorApi(error, 'crm.leads.editar_fallido')
  if (documento) {
    const lectura = v.safeParse(DocumentoLeadSchema, data)
    if (!lectura.success || lectura.output.lead_id !== leadId ||
      lectura.output.numero !== (documento.numero?.trim().toUpperCase() || null) ||
      (documento.numero && lectura.output.tipo !== documento.tipo)) {
      throw new CrmApiError('El servidor no confirmó el documento guardado. Recarga la ficha.', 'DOCUMENTO_LEAD_CONTRACT')
    }
  }
}

export async function insertarActividad(fila: ActividadInsert): Promise<void> {
  const { error } = await cliente().schema('crm').from('actividades').insert(fila)
  if (error) throw aErrorApi(error, 'crm.actividades.insert_fallido')
}

// ── Agenda: crm.tareas (Fase A) ───────────────────────────────────────────────
// La tabla es NUEVA (no hay filas legacy): el schema es estricto. La tenencia
// (vendedor_id/asignado_supervisor_id) viene derivada del lead por trigger.

type TareaDatabaseRow = Database['crm']['Tables']['tareas']['Row']

const COLUMNAS_TAREA = (
  [
    'id',
    'lead_id',
    'perfil_id',
    'vendedor_id',
    'asignado_supervisor_id',
    'tipo',
    'titulo',
    'nota',
    'vence_en',
    'duracion_min',
    'estado',
    'modalidad_reunion',
    'ubicacion_reunion',
    'enlace_reunion',
    'resultado_reunion',
    'motivo_no_realizada',
    'detalle_cierre_reunion',
    'confirmada_en',
    'reagendada_de',
    'reprogramaciones',
    'activo',
    'creado_en',
  ] as const satisfies readonly (keyof TareaDatabaseRow)[]
).join(',')



/** Lote por llamada de `crm.tareas_pendientes_fn` (Fase 2 «sin topes»); el front pide `lote + 1`. */
export const TAMANO_LOTE_TAREAS = 500
/**
 * Alarma de TENDENCIA, no tope: la lectura sigue hasta que el servidor dice
 * que no hay más. Si el ámbito supera este volumen suena (es la señal de
 * pasar la agenda a lecturas por ventana, Fase 4), pero no corta nada.
 */
const ALARMA_TENDENCIA_TAREAS = 20000
/**
 * Espejo del `limit 2000` de `crm.postventa_agenda_fn` (20260910150039): esa
 * ruta SÍ tiene tope en el servidor hasta que se pagine, y su alarma se
 * calibra contra ÉL (revisión de Codex del 19/09).
 */
const LIMITE_AGENDA_POSTVENTA = 2000

const TareasPendientesSchema = v.object({
  version: v.literal(1),
  items: v.array(v.unknown()),
})

/** Lo MÍNIMO para poder avanzar: si la última fila cruda no lo cumple, no hay cursor honesto. */
const CursorTareaRowSchema = v.object({
  id: v.string(),
  vence_en: v.string(),
})

/**
 * Orden del servidor (`vence_en asc, id asc`) comparado por UNIDADES DE CÓDIGO,
 * no con `localeCompare`: el servidor serializa `timestamptz` siempre con el
 * mismo desplazamiento (`+00:00`) y con precisión variable, y en ese formato el
 * orden de código es el cronológico; la colación de `localeCompare` pone «.»
 * antes que «+» y ponía `…:00.001+00:00` delante de `…:00+00:00` (revisión de
 * Codex del 19/09). Los ids son uuid en hexadecimal: mismo orden que en Postgres.
 */
export function compararTareasPorVencimiento(
  a: { vence_en: string; id: string },
  b: { vence_en: string; id: string },
): number {
  if (a.vence_en !== b.vence_en) return a.vence_en < b.vence_en ? -1 : 1
  if (a.id !== b.id) return a.id < b.id ? -1 : 1
  return 0
}

/** El cursor debe AVANZAR en sentido estricto; un servidor que devuelve la misma página, retrocede o cicla (A→B→A) se corta. */
function avanzaCursorTarea(previo: { venceEn: string; id: string }, fila: { vence_en: string; id: string }): boolean {
  return compararTareasPorVencimiento(fila, { vence_en: previo.venceEn, id: previo.id }) > 0
}

/** Lectura puntual de Agenda por su puerta RLS; no depende del lote. */
export async function obtenerTareaDelAmbitoPorId(leadId: string, id: string, signal?: AbortSignal): Promise<Tarea | null> {
  let consulta = cliente().schema('crm').from('tareas').select(COLUMNAS_TAREA)
    .eq('id', id).eq('lead_id', leadId).eq('estado', 'pendiente').eq('activo', true)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta.maybeSingle()
  lanzarAbortSiCorresponde(signal)
  if (error) throw new CrmApiError('No se pudo consultar la actividad.', error.code || 'POSTGREST_ERROR')
  if (!data) return null
  const resultado = v.safeParse(TareaRowSchema, data)
  if (!resultado.success || resultado.output.id !== id || resultado.output.lead_id !== leadId
    || resultado.output.estado !== 'pendiente' || !resultado.output.activo) {
    throw new CrmApiError('No se pudo verificar la actividad.', 'ROW_CONTRACT')
  }
  return resultado.output
}

/**
 * Tareas PENDIENTES del ámbito (HOY, Agenda, Citas de gerencia, cerrar tarea y
 * la ficha beben de aquí). Las cerradas no viajan: su historia vive en
 * crm.actividades (historial del lead).
 *
 * Fase 2 «sin topes»: lotes por cursor keyset (vence_en asc, id asc) contra
 * `crm.tareas_pendientes_fn` (INVOKER: devuelve exactamente lo que la RLS ya
 * mostraba en la tabla) hasta que el servidor no devuelve la fila extra. Sin
 * constante de tope: la lectura directa la recortaba PostgREST a 1 000 filas
 * y gerencia perdía las tareas de vencimiento más lejano.
 */
export async function listarTareasDelAmbito(signal?: AbortSignal): Promise<Tarea[]> {
  const crudas: unknown[] = []
  let cursor: { venceEn: string; id: string } | null = null
  for (;;) {
    lanzarAbortSiCorresponde(signal)
    // Se pide UNA fila de más: distingue «hay más» de «justo cabía» sin gastar
    // una petición extra que vuelva vacía al final.
    const argumentos: Database['crm']['Functions']['tareas_pendientes_fn']['Args'] = {
      p_limite: TAMANO_LOTE_TAREAS + 1,
    }
    if (cursor) {
      argumentos.p_despues_de = cursor.venceEn
      argumentos.p_despues_id = cursor.id
    }
    let consulta = cliente().schema('crm').rpc('tareas_pendientes_fn', argumentos)
    if (signal) consulta = consulta.abortSignal(signal)
    const { data, error } = await consulta
    lanzarAbortSiCorresponde(signal)
    if (error) {
      const fallo = new CrmApiError('No se pudo cargar la agenda.', error.code || 'POSTGREST_ERROR')
      registrarError('crm.tareas.ambito_fallido', fallo, { conCursor: cursor != null })
      throw fallo
    }
    const payload = v.safeParse(TareasPendientesSchema, data)
    if (!payload.success) {
      throw new CrmApiError('La agenda recibida no cumple el contrato esperado.', 'ROW_CONTRACT')
    }
    const lote = payload.output.items
    if (lote.length > TAMANO_LOTE_TAREAS + 1) {
      throw new CrmApiError('La agenda devolvió más filas de las pedidas.', 'ROW_CONTRACT')
    }
    const hayMas = lote.length > TAMANO_LOTE_TAREAS
    const ventana = hayMas ? lote.slice(0, TAMANO_LOTE_TAREAS) : lote
    crudas.push(...ventana)
    if (!hayMas) break
    // El cursor sale de la ÚLTIMA FILA CRUDA de la ventana, no de la última
    // válida: avanzar desde una fila anterior repetiría filas, y cortar aquí
    // fingiría que ya no hay más. Y debe avanzar en sentido ESTRICTO: un
    // servidor que repite, retrocede o cicla se corta con error, nunca se gira
    // para siempre.
    const ultima = v.safeParse(CursorTareaRowSchema, ventana.at(-1))
    if (!ultima.success || (cursor !== null && !avanzaCursorTarea(cursor, ultima.output))) {
      throw new CrmApiError('No se pudo continuar la lectura de la agenda.', 'ROW_CONTRACT')
    }
    cursor = { venceEn: ultima.output.vence_en, id: ultima.output.id }
  }
  // Alarma de tendencia: suena semanas antes de que el volumen sea un problema.
  avisarTopeAlcanzado('tareas_del_ambito_tendencia', ALARMA_TENDENCIA_TAREAS, crudas.length)
  const items: Tarea[] = []
  const vistos = new Set<string>()
  let descartadas = 0
  for (const cruda of crudas) {
    const resultado = v.safeParse(TareaRowSchema, cruda)
    // Los lotes no son una transacción de lectura: una tarea reprogramada entre
    // dos lotes no debe aparecer dos veces en la agenda.
    if (resultado.success) {
      if (!vistos.has(resultado.output.id)) { vistos.add(resultado.output.id); items.push(resultado.output) }
    }
    else descartadas += 1
  }
  if (descartadas > 0) {
    registrarError(
      'crm.tareas.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }
  // F6 es compatible con el servidor anterior: solo PGRST202 significa no instalada.
  // Las filas neutrales de los lotes se sustituyen por la respuesta completa.
  const { listarAgendaPostventa } = await import('./postventa-api')
  const neutrales = await listarAgendaPostventa(signal)
  avisarTopeAlcanzado('tareas_postventa', LIMITE_AGENDA_POSTVENTA, neutrales.length)
  const unicas = new Map(items.filter(t => t.lead_id || t.perfil_id).map(t => [t.id, t]))
  for (const tarea of neutrales) unicas.set(tarea.id, tarea)
  return [...unicas.values()].sort(compararTareasPorVencimiento)
}

type TareaInsert = Database['crm']['Tables']['tareas']['Insert']
type TareaUpdate = Database['crm']['Tables']['tareas']['Update']

export async function insertarTarea(fila: TareaInsert): Promise<void> {
  const { error } = await cliente().schema('crm').from('tareas').insert(fila)
  if (error) throw aErrorApi(error, 'crm.tareas.insert_fallido')
}

export async function actualizarTarea(id: string, cambios: TareaUpdate): Promise<void> {
  const { data, error } = await cliente().schema('crm').from('tareas').update(cambios).eq('id', id).select('id')
  if (error) throw aErrorApi(error, 'crm.tareas.update_fallido')
  if (!data || data.length === 0) {
    // RLS la ocultó o no existe: mismo mensaje, sin revelar existencia.
    throw new CrmApiError('Tarea no encontrada', 'NO_ENCONTRADO')
  }
}

// ── Suscripción ICS de la agenda (crm.agenda_ics) ─────────────────────────────
// RLS: cada quien SU fila. El token es el secreto del feed (edge crm-agenda-ics);
// rotarlo invalida el enlace anterior de inmediato.

const AgendaIcsRowSchema = v.object({ token: v.string() })

/** Token ICS propio, o null si el miembro aún no conectó su calendario. */
export async function obtenerTokenIcs(perfilId: string): Promise<string | null> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('agenda_ics')
    .select('token')
    .eq('perfil_id', perfilId)
    .maybeSingle()
  if (error) throw aErrorApi(error, 'crm.agenda_ics.select_fallido')
  if (!data) return null
  const resultado = v.safeParse(AgendaIcsRowSchema, data)
  if (!resultado.success) throw new CrmApiError('Fila fuera de contrato', 'ROW_CONTRACT')
  return resultado.output.token
}

/** Genera el token ICS propio (primera conexión del calendario). */
export async function crearTokenIcs(perfilId: string): Promise<string> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('agenda_ics')
    .insert({ perfil_id: perfilId })
    .select('token')
    .single()
  if (error) throw aErrorApi(error, 'crm.agenda_ics.insert_fallido')
  const resultado = v.safeParse(AgendaIcsRowSchema, data)
  if (!resultado.success) throw new CrmApiError('Fila fuera de contrato', 'ROW_CONTRACT')
  return resultado.output.token
}

/** Rota el token propio: el enlace anterior muere al instante. */
export async function rotarTokenIcs(perfilId: string): Promise<string> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('agenda_ics')
    .update({ token: crypto.randomUUID(), rotado_en: new Date().toISOString() })
    .eq('perfil_id', perfilId)
    .select('token')
    .single()
  if (error) throw aErrorApi(error, 'crm.agenda_ics.update_fallido')
  const resultado = v.safeParse(AgendaIcsRowSchema, data)
  if (!resultado.success) throw new CrmApiError('Fila fuera de contrato', 'ROW_CONTRACT')
  return resultado.output.token
}

export interface CerrarTareaInput {
  tarea_id: string
  estado: 'completada' | 'no_show' | 'cancelada'
  resultado_tipo?: TipoActividad | null
  resultado_detalle?: string | null
  resultado_reunion?: Exclude<ResultadoReunion, 'sin_clasificar'> | null
  motivo_no_realizada?: MotivoNoRealizada | null
  siguiente?: {
    id?: string
    tipo: string
    titulo: string
    nota?: string | null
    vence_en: string
    duracion_min?: number | null
    modalidad_reunion?: ModalidadReunion | null
    ubicacion_reunion?: string | null
    enlace_reunion?: string | null
  } | null
}

/**
 * Cierre atómico por la RPC crm.cerrar_tarea: resultado al log + tarea
 * siguiente en UNA transacción. El UPDATE directo no puede completar (trigger).
 */
export async function cerrarTarea(input: CerrarTareaInput): Promise<{ siguiente_id: string | null }> {
  const { data, error } = await cliente()
    .schema('crm')
    .rpc(
      'cerrar_tarea',
      sinIndefinidos({
        p_tarea_id: input.tarea_id,
        p_estado: input.estado,
        p_resultado_tipo: input.resultado_tipo ?? undefined,
        p_resultado_detalle: input.resultado_detalle ?? undefined,
        p_siguiente: (input.siguiente ?? null) as Json,
        p_resultado_reunion: input.resultado_reunion ?? undefined,
        p_motivo_no_realizada: input.motivo_no_realizada ?? undefined,
      }),
    )
  if (error) throw aErrorApi(error, 'crm.tareas.cierre_fallido')
  const siguiente = (data as { siguiente_id?: string | null } | null)?.siguiente_id ?? null
  return { siguiente_id: siguiente }
}

export interface CerrarReunionInput {
  tarea_id: string
  estado: 'completada' | 'no_show' | 'cancelada'
  resultado_reunion?: Exclude<ResultadoReunion, 'sin_clasificar'> | null
  motivo_no_realizada?: MotivoNoRealizada | null
  detalle?: string | null
  siguiente?: CerrarTareaInput['siguiente']
}

export async function cerrarReunion(input: CerrarReunionInput): Promise<{ siguiente_id: string | null }> {
  const { data, error } = await cliente()
    .schema('crm')
    .rpc(
      'cerrar_reunion',
      sinIndefinidos({
        p_tarea_id: input.tarea_id,
        p_estado: input.estado,
        p_resultado_reunion: input.resultado_reunion ?? undefined,
        p_motivo_no_realizada: input.motivo_no_realizada ?? undefined,
        p_detalle: input.detalle ?? undefined,
        p_siguiente: (input.siguiente ?? null) as Json,
      }),
    )
  if (error) throw aErrorApi(error, 'crm.reuniones.cierre_fallido')
  const siguiente = (data as { siguiente_id?: string | null } | null)?.siguiente_id ?? null
  return { siguiente_id: siguiente }
}

const UuidSchema = v.pipe(v.string(), v.uuid())

const ReprogramarReunionRespuestaSchema = v.object({
  ok: v.literal(true),
  tarea_nueva_id: UuidSchema,
  tarea_anterior_id: UuidSchema,
  reprogramaciones: v.pipe(v.number(), v.integer(), v.minValue(1)),
})

function validarRespuestaReprogramarReunion(
  data: unknown,
  tareaId: string,
  nuevaId: string,
): RespuestaReprogramarReunion {
  const respuesta = v.safeParse(ReprogramarReunionRespuestaSchema, data)
  const idsCoherentes =
    respuesta.success &&
    respuesta.output.tarea_anterior_id === tareaId &&
    respuesta.output.tarea_nueva_id === nuevaId &&
    respuesta.output.tarea_anterior_id !== respuesta.output.tarea_nueva_id

  if (!respuesta.success || !idsCoherentes) {
    const fallo = new CrmApiError('La reprogramación respondió fuera del contrato esperado.', 'ROW_CONTRACT')
    registrarError('crm.reuniones.reprogramacion_respuesta_invalida', fallo, {
      tareaId,
      nuevaId,
    })
    throw fallo
  }

  return respuesta.output
}

export async function reprogramarReunion(
  tareaId: string,
  venceEn: string,
  nuevaId: string,
): Promise<Pick<RespuestaReprogramarReunion, 'tarea_nueva_id'>> {
  const { data, error } = await cliente().schema('crm').rpc('reprogramar_reunion', {
    p_tarea_id: tareaId,
    p_vence_en: venceEn,
    p_nueva_id: nuevaId,
  })
  if (error) throw aErrorApi(error, 'crm.reuniones.reprogramacion_fallida')
  const respuesta = validarRespuestaReprogramarReunion(data, tareaId, nuevaId)
  return { tarea_nueva_id: respuesta.tarea_nueva_id }
}

// ── Conversión lead → cliente (edge crm-convertir-lead: crea el cliente en el
//    portal con service_role + correo de bienvenida + enlaza el lead vía la RPC
//    privilegiada crm.convertir_lead). El navegador nunca crea usuarios ni envía
//    correos: eso vive en el edge. Aquí solo se invoca y se traduce el error. ────
export type TipoDocumentoCliente = 'DNI' | 'CE' | 'PASAPORTE'

export interface ConvertirLeadInput {
  condiciones_tasa?: CondicionesTasaLead
  lead_id: string
  correo: string
  tipo_documento: TipoDocumentoCliente
  documento: string
  nombre_completo: string
  telefono?: string | null
  domicilio: string
  apellidos?: string | null
  nombres?: string | null
  /**
   * Cuentas donde se le depositará el interés. OBLIGATORIO: la edge exige al
   * menos una (soles o dólares) y las escribe en el MISMO INSERT del cliente, así
   * que un cliente nunca nace sin cuenta. Si el documento ya era cliente del
   * portal, la edge las IGNORA (no se pisan las cuentas con las que ya cobra).
   */
  bancarios: BancariosInput
}

/**
 * Las dos secciones bancarias CRUDAS (tal cual salen de los inputs). Van sin
 * pre-procesar a propósito: la validación de verdad es la de la edge
 * (_shared/bancarios.mjs) y el navegador solo la espeja para dar feedback rápido
 * — misma frontera que el documento. Si el front mandara el patch ya armado, la
 * regla volvería a depender de él.
 */
export interface BancariosInput {
  pen: SeccionBancariaForm
  usd: SeccionBancariaForm
}

export interface ConvertirLeadResultado {
  perfil_id: string
  ya_existia: boolean
  domicilio_accion: 'completado' | 'conservado'
  email_enviado: boolean
}

const UUID_CANONICO_CONVERSION_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

// La respuesta de una Edge sigue siendo JSON no confiable aunque el transporte
// haya terminado en 2xx. No se coercionan strings/números a booleanos ni se
// acepta un UUID equivalente con otra escritura: el front solo confirma la
// conversión cuando recibió exactamente el contrato publicado por la Edge.
const ConvertirLeadRespuestaSchema = v.strictObject({
  ok: v.literal(true),
  perfil_id: v.pipe(v.string(), v.regex(UUID_CANONICO_CONVERSION_RE)),
  ya_existia: v.boolean(),
  domicilio_accion: v.picklist(['completado', 'conservado']),
  email_enviado: v.boolean(),
  email_error: v.optional(v.pipe(v.string(), v.minLength(1))),
})

export async function convertirLead(input: ConvertirLeadInput): Promise<ConvertirLeadResultado> {
  const { data, error } = await cliente().functions.invoke('crm-convertir-lead', { body: input })
  if (error) {
    let mensaje = 'No se pudo convertir el lead.'
    // FunctionsHttpError expone la respuesta del edge en `context`: extraemos
    // nuestro { error } es-PE (mensaje seguro que arma el propio edge).
    try {
      const ctx = (error as { context?: Response }).context
      if (ctx && typeof ctx.json === 'function') {
        const cuerpo = await ctx.json()
        if (cuerpo?.error) mensaje = traducirErrorAlta(String(cuerpo.error))
      }
    } catch {
      /* nos quedamos con el mensaje genérico */
    }
    const fallo = new CrmApiError(mensaje, 'CONVERTIR_FALLIDO')
    registrarError('crm.convertir.fallido', fallo)
    throw fallo
  }
  const respuesta = v.safeParse(ConvertirLeadRespuestaSchema, data)
  if (!respuesta.success) {
    const fallo = new CrmApiError('La conversión respondió fuera del contrato esperado.', 'RESPUESTA_INVALIDA')
    registrarError('crm.convertir.respuesta_invalida', fallo)
    throw fallo
  }
  const cuerpo = respuesta.output
  return {
    perfil_id: cuerpo.perfil_id,
    ya_existia: cuerpo.ya_existia,
    domicilio_accion: cuerpo.domicilio_accion,
    email_enviado: cuerpo.email_enviado,
  }
}

// ── Cuenta de pago + contrato del cliente convertido ─────────────────────────
// La lectura y el alta viven en `crm`, pero la RPC atómica delega contrato,
// cronograma y co-titulares a public.crear_contrato (motor del portal). Así se
// conserva una única lógica contractual y se añade el enlace bancario histórico
// sin alterar objetos de public.

const CuentaBancariaSeleccionableRowSchema = v.pipe(
  v.strictObject({
    cuenta_id: v.nullable(v.pipe(v.string(), v.uuid())),
    moneda: v.picklist(['PEN', 'USD']),
    banco: v.pipe(v.string(), v.minLength(1)),
    tipo_cuenta: v.picklist(['ahorros', 'corriente']),
    numero_cuenta: v.pipe(v.string(), v.regex(/^[A-Za-z0-9-]{1,30}$/)),
    cci: v.pipe(v.string(), v.regex(/^\d{20}$/)),
    titular_distinto: v.boolean(),
    beneficiario_nombre: v.nullable(v.string()),
    beneficiario_dni: v.nullable(v.string()),
    origen: v.picklist(['perfil', 'contrato', 'portal']),
    es_cuenta_perfil: v.boolean(),
    creada_en: v.nullable(v.pipe(v.string(), v.isoTimestamp())),
  }),
  v.check(
    (fila) =>
      fila.es_cuenta_perfil
        ? fila.cuenta_id === null && fila.origen === 'perfil' && fila.creada_en === null
        : fila.cuenta_id !== null && fila.creada_en !== null,
    'Origen e identidad de cuenta incoherentes',
  ),
)

export async function listarCuentasBancariasCliente(
  clienteId: string,
  moneda: 'PEN' | 'USD',
  signal?: AbortSignal,
): Promise<CuentaBancariaSeleccionable[]> {
  let consulta = cliente().schema('crm').rpc('cuentas_bancarias_cliente_fn', {
    p_cliente_id: clienteId,
    p_moneda: moneda,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      'No se pudieron cargar las cuentas bancarias del cliente.',
      error.code || 'POSTGREST_ERROR',
    )
    registrarError('crm.cuentas_bancarias.listado_fallido', fallo)
    throw fallo
  }

  const cuentas: CuentaBancariaSeleccionable[] = []
  for (const cruda of data ?? []) {
    const fila = v.safeParse(CuentaBancariaSeleccionableRowSchema, cruda)
    if (!fila.success) {
      const fallo = new CrmApiError('Las cuentas bancarias no tienen el formato esperado.', 'ROW_CONTRACT')
      registrarError('crm.cuentas_bancarias.fila_invalida', fallo)
      // Fail-closed: ocultar una sola fila podría hacer que el analista elija una
      // cuenta distinta creyendo que la autorizada ya no existe.
      throw fallo
    }
    cuentas.push(fila.output)
  }
  return cuentas
}

/** Registra una versión del ledger con la autorización de la cartera. */
export async function registrarCuentaCliente(
  clienteId: string,
  moneda: 'PEN' | 'USD',
  cuenta: SeccionBancariaForm,
): Promise<string> {
  const { data, error } = await cliente().schema('crm').rpc('registrar_cuenta_cliente', {
    p_cliente_id: clienteId,
    p_cuenta: {
      moneda, banco: cuenta.banco, tipo_cuenta: cuenta.tipo_cuenta,
      numero_cuenta: cuenta.numero_cuenta, cci: cuenta.cci,
      titular_distinto: cuenta.titular_distinto,
      beneficiario_nombre: cuenta.beneficiario_nombre,
      beneficiario_dni: cuenta.beneficiario_dni,
    },
  })
  if (error) {
    const fallo = new CrmApiError(
      error.code === '42501'
        ? 'No tienes permiso para registrar esta cuenta.'
        : 'No se pudo registrar la cuenta bancaria. Revisa los datos e intenta de nuevo.',
      error.code || 'CUENTA_NO_REGISTRADA',
    )
    registrarError('crm.cuentas_bancarias.registro_fallido', fallo)
    throw fallo
  }
  if (typeof data !== 'string' || !v.safeParse(v.pipe(v.string(), v.uuid()), data).success) {
    throw new CrmApiError('El registro de la cuenta no quedó confirmado.', 'RESPUESTA_INVALIDA')
  }
  return data
}

export interface CrearContratoInput {
  /** Compatibilidad temporal de callers antiguos; el flujo libre lo omite. */
  producto_condicion_id?: string
  cliente_id: string
  capital: number
  moneda: 'PEN' | 'USD'
  tasa_anual: number
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  categoria: CategoriaContrato
  fecha_inicio: string
  fecha_vencimiento: string
  numero_contrato?: string | null
  notas_internas?: string | null
  /** Solo renovación: contrato que llegó a su fecha fin. */
  contrato_origen_id?: string | null
  /** Solo renovación: parte del capital anterior que continúa invertida. */
  capital_renovado?: number | null
  /** Solo renovación: dinero nuevo. Se reporta aparte y no suma conversión. */
  capital_adicional?: number | null
  /**
   * Co-titulares (cuentas mancomunadas, máx 5): viajan DENTRO de p_contrato —
   * crear_contrato ya los persiste vía _sync_contrato_titulares. Ausente o []
   * en el ALTA es lo mismo: contrato sin co-titulares.
   */
  titulares?: TitularInput[]
  /** Obligatoria en el CRM nuevo; el servidor vuelve a validar dueño y moneda. */
  cuenta_pago: CuentaPagoContratoInput
  /**
   * De quién es la venta (P-055 Fase 3, decisión 2 de Miguel). NO es quien la
   * teclea: eso lo guarda el servidor aparte en `creado_por` y no se pisa.
   * Si se omite, el servidor la deja a nombre de quien registra — que es la
   * misma decisión: «si no corresponde a nadie, lo pone a su nombre».
   */
  analista_cierre_id?: string | null
  /**
   * Clave de idempotencia del alta: un uuid por INTENTO de formulario, el mismo en
   * cada reintento. Viaja DENTRO de `p_contrato` (la firma del RPC no cambia). El
   * wrapper `crear_contrato_con_cuenta_pdf_v2` que la conoce devuelve el MISMO
   * contrato si ya registró un alta con esa clave para este actor; el que no la
   * conoce la ignora (`public.crear_contrato` solo lee sus propias claves).
   */
  clave_idempotencia?: string
}

export interface CrearContratoResultado {
  id: string
  numero_contrato: string
  /**
   * null = la respuesta no trajo un id de cuenta válido. El alta SÍ ocurrió (se
   * registra el rastro); la cuenta se relee desde el ledger, nunca de esta copia.
   */
  cuenta_bancaria_id: string | null
  /**
   * Estado documental al crear: `pendiente` con reserva (régimen nuevo),
   * `sin_reserva` (firmado antes del 19/08: el sistema no emite documento) o el
   * mejor esfuerzo «pendiente y reintentable» si el servidor mandó una forma que
   * el front no reconoce. La fuente de verdad del documento es la edge, no esto.
   */
  pdf: {
    contrato_id: string
    job_id: string | null
    estado: EstadoContratoPdf
    reintentable: boolean
  }
  /** true = el servidor devolvió un alta YA registrada con la misma clave (reintento). */
  idempotente: boolean
  /** Los wrappers catalogados antiguos podían devolver esta fotografía. */
  producto_condicion_id?: string
  producto_id?: string
  producto_revision?: number
  version_id?: string
  version_revision?: number
  numero_version?: number
  version_estado?: 'borrador' | 'publicada' | 'retirada'
  version_nombre?: string
}

const EnteroProductoSchema = v.pipe(v.union([v.number(), v.string()]), v.transform(Number), v.integer(), v.minValue(1))

// ── La respuesta del alta se lee en DOS niveles, y solo el primero puede fallar ──
//
// 1. La PRUEBA del alta: `id` + `numero_contrato`. `public.crear_contrato` solo los
//    devuelve si el contrato quedó escrito (en cualquier otro caso levanta
//    excepción y PostgREST responde 4xx). Sin ellos la respuesta no es un alta.
// 2. Lo accesorio: `cuenta_bancaria_id` y el bloque `pdf`. Se leen con tolerancia
//    y, si no encajan, se DEGRADAN con rastro. Jamás se lanzan.
//
// Por qué así (dos incidentes, misma raíz). Fallar cerrado sobre lo accesorio
// «protege» DESPUÉS de una escritura irreversible: el contrato ya existe en el
// servidor, el front dice «error» y el analista lo crea otra vez.
//   · 19/08: el bundle exigía plantilla v3 y producción emitía v5 → todo alta
//     moría con «El servidor no confirmó completamente el contrato».
//   · 05/09: el esquema exigía la reserva `pendiente` y los contratos firmados
//     antes del 19/08 (régimen documental ANTERIOR: el servidor no emite
//     documento) vuelven con `sin_reserva` y `job_id = null` → 33 altas del
//     régimen anterior desde el 21/08 pasaron por el error falso, y el 05/09 un
//     analista cambió el número y creó el mismo contrato dos veces
//     (2026-01-000025 y 2026-01-000253, 61 s de diferencia).
// La fuente de verdad del documento es la edge (`contrato-pdf-archivo`), que se
// vuelve a consultar al archivar y en el detalle: esta copia solo pinta el primer
// estado, así que degradarla no esconde nada.
const ContratoConfirmadoSchema = v.object({
  id: v.pipe(v.string(), v.uuid()),
  numero_contrato: v.pipe(v.string(), v.minLength(1)),
  cuenta_bancaria_id: v.optional(v.unknown()),
  pdf: v.optional(v.unknown()),
  idempotente: v.optional(v.unknown()),
})
const CuentaBancariaIdSchema = v.pipe(v.string(), v.uuid())
// La forma que emite `private.contrato_pdf_estado_base` en TODAS sus ramas:
// reserva `pendiente`, `sin_reserva`, sellado… `looseObject` porque la rama de
// integridad añade `ok`/`codigo`, y porque una clave nueva del servidor no puede
// volver a convertir un alta en error.
const PdfAltaSchema = v.looseObject({
  contrato_id: v.pipe(v.string(), v.uuid()),
  job_id: v.nullable(v.pipe(v.string(), v.uuid())),
  estado: v.picklist(ESTADOS_CONTRATO_PDF),
  reintentable: v.boolean(),
})

/** Mismo contenido económico en el alta publicada y en la revisión F4. */
export function prepararPayloadContrato(input: CrearContratoInput): Record<string, unknown> {
  const p_contrato: Record<string, unknown> = {
    cliente_id: input.cliente_id,
    capital: input.capital,
    moneda: input.moneda,
    tasa_anual: input.tasa_anual,
    modalidad: input.modalidad,
    tipo_interes: input.tipo_interes,
    categoria: input.categoria,
    fecha_inicio: input.fecha_inicio,
    fecha_vencimiento: input.fecha_vencimiento,
    numero_contrato: input.numero_contrato?.trim() || null,
    notas_internas: input.notas_internas?.trim() || null,
  }
  if (input.categoria === 'renovacion') {
    p_contrato.contrato_origen_id = input.contrato_origen_id ?? null
    p_contrato.capital_renovado = input.capital_renovado ?? null
    p_contrato.capital_adicional = input.capital_adicional ?? 0
  }
  // Rentabilidad D2: el upgrade declara el contrato que amplía (misma huella que la solicitud; la puerta lo usa en R4).
  if (input.categoria === 'upgrade' && input.contrato_origen_id) p_contrato.contrato_origen_id = input.contrato_origen_id
  // En el alta, [] equivale a ausente: solo viajan si de verdad hay co-titulares.
  if (input.titulares && input.titulares.length > 0) p_contrato.titulares = input.titulares
  // Solo viaja si de verdad se eligió a alguien. Ausente ≠ null: ausente deja
  // que el servidor aplique «lo pone a su nombre»; mandar null sería pedirle
  // explícitamente un contrato sin dueño, que no es lo que hace este formulario.
  if (input.analista_cierre_id) p_contrato.analista_cierre_id = input.analista_cierre_id
  // Transporte, no dato del contrato: el wrapper la lee y la quita antes de bajar.
  if (input.clave_idempotencia) p_contrato.clave_idempotencia = input.clave_idempotencia
  return p_contrato
}

export async function crearContrato(
  input: CrearContratoInput,
  cronograma: CuotaCronograma[],
): Promise<CrearContratoResultado> {
  const p_contrato = prepararPayloadContrato(input)
  const p_cronograma = cronograma as unknown as Json[]
  const { data, error } = await cliente()
    .schema('crm')
    .rpc('crear_contrato_con_cuenta_pdf_v2', {
      p_contrato: p_contrato as unknown as Json,
      p_cronograma,
      p_cuenta: input.cuenta_pago as unknown as Json,
    })
  if (error) throw aErrorApi(error, 'crm.contrato.crear_fallido')
  const confirmado = v.safeParse(ContratoConfirmadoSchema, data)
  if (!confirmado.success) {
    // Sin `id` no hay prueba de escritura: esta respuesta NO es un alta.
    const fallo = new CrmApiError('El servidor no confirmó el contrato.', 'ROW_CONTRACT')
    registrarError('crm.contrato.respuesta_invalida', fallo, { respuesta: data })
    throw fallo
  }
  const { id, numero_contrato } = confirmado.output
  // ── De aquí en adelante el contrato EXISTE en el servidor. La única salida es éxito. ──
  const cuenta = v.safeParse(CuentaBancariaIdSchema, confirmado.output.cuenta_bancaria_id)
  if (!cuenta.success) {
    registrarError(
      'crm.contrato.cuenta_no_confirmada',
      new CrmApiError('El servidor no devolvió el id de la cuenta de pago del contrato.', 'ROW_CONTRACT'),
      { id, numero_contrato, cuenta_bancaria_id: confirmado.output.cuenta_bancaria_id },
    )
  }
  const pdfLeido = v.safeParse(PdfAltaSchema, confirmado.output.pdf)
  let pdf: CrearContratoResultado['pdf']
  if (pdfLeido.success && pdfLeido.output.contrato_id === id) {
    pdf = {
      contrato_id: id,
      job_id: pdfLeido.output.job_id,
      estado: pdfLeido.output.estado,
      reintentable: pdfLeido.output.reintentable,
    }
  } else {
    // Mejor esfuerzo honesto: «pendiente y reintentable» hace que la pantalla vuelva
    // a preguntar a la edge. Nunca se inventa un sellado ni un job.
    registrarError(
      'crm.contrato.pdf_respuesta_invalida',
      new CrmApiError('El servidor no describió el estado documental del contrato.', 'ROW_CONTRACT'),
      { id, numero_contrato, pdf: confirmado.output.pdf },
    )
    pdf = { contrato_id: id, job_id: null, estado: 'pendiente', reintentable: true }
  }
  return {
    id,
    numero_contrato,
    cuenta_bancaria_id: cuenta.success ? cuenta.output : null,
    pdf,
    idempotente: confirmado.output.idempotente === true,
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL DEL ANALISTA EN EL CRM — clientes del portal + contratos (traspaso íntegro
// de public_html/admin/analista). El motor (edge crear-cliente v20, RPCs
// public.crear_contrato/actualizar_contrato, RLS con ventana de 5 h) YA está en
// prod y NO se toca: aquí solo se consume, con Valibot en cada frontera.
// ═══════════════════════════════════════════════════════════════════════════════

// Catálogos del portal como picklists runtime (espejo de los CHECK de `public`).
const MODALIDADES_CONTRATO = ['mensual', 'trimestral', 'semestral', 'anual'] as const
const TIPOS_INTERES = ['simple', 'compuesto'] as const
const CATEGORIAS_CONTRATO = ['nuevo', 'renovacion', 'upgrade'] as const
const TIPOS_CUOTA = ['cuota', 'retorno', 'devolucion'] as const

// Transporte, NO métrica: el total exacto y los IDs verifican la descarga.
// Un límite remoto menor que la página no prueba fin de lista. Se avanza por
// filas recibidas; un total cambiante, duplicado o página ausente invalida TODO.
async function leerListadoCarteraCompleto(
  tabla: 'clientes_basicos' | 'contratos_cartera' | 'operaciones_cartera',
  columnas: string,
  signal?: AbortSignal,
): Promise<unknown[]> {
  const filas: unknown[] = []
  const ids = new Set<string>()
  let total: number | null = null
  // Fusible de tráfico, no un total admisible: al alcanzarlo se informa error.
  for (let pagina = 0; pagina < 1000; pagina += 1) {
    lanzarAbortSiCorresponde(signal)
    // Separa las sobrecargas tipadas de tabla (ledger) y vistas; misma lectura.
    let consulta = tabla === 'operaciones_cartera'
      ? cliente().schema('crm').from(tabla).select(columnas, { count: 'exact' })
      : cliente().schema('crm').from(tabla).select(columnas, { count: 'exact' })
    if (tabla === 'operaciones_cartera') consulta = consulta.order('fecha_operacion', { ascending: false })
    consulta = consulta.order('creado_en', { ascending: false }).order('id', { ascending: true })
      .range(filas.length, filas.length + 199)
    if (signal) consulta = consulta.abortSignal(signal)
    const { data, error, count } = await consulta
    lanzarAbortSiCorresponde(signal)
    if (error) throw aErrorApi(error, `crm.${tabla}.listado_fallido`)
    if (!Number.isSafeInteger(count) || count == null || count < 0 || !Array.isArray(data)
      || (total != null && count !== total) || filas.length + data.length > count
      || (data.length === 0 && filas.length !== count)) {
      throw new CrmApiError('No se pudo confirmar el listado completo de Cartera. Vuelve a cargarlo.', 'CARTERA_INCOMPLETA')
    }
    total = count
    for (const fila of data as unknown[]) {
      const id = fila != null && typeof fila === 'object' && 'id' in fila ? fila.id : null
      if (typeof id !== 'string' || id === '' || ids.has(id)) {
        throw new CrmApiError('El listado de Cartera contiene filas inválidas o repetidas. Vuelve a cargarlo.', 'ROW_CONTRACT')
      }
      ids.add(id)
      filas.push(fila)
    }
    if (filas.length === total) return filas
  }
  throw new CrmApiError('No se pudo completar la descarga de Cartera. Vuelve a cargarla.', 'CARTERA_INCOMPLETA')
}

const ConteoCarteraSchema = v.pipe(v.number(), v.safeInteger(), v.minValue(0))
const ImporteCarteraSchema = v.pipe(v.number(), v.finite(), v.minValue(0))
const NumericCarteraSchema = v.pipe(
  v.union([v.number(), v.pipe(v.string(), v.regex(/^\d+(\.\d+)?$/))]),
  v.transform(Number), v.finite(), v.minValue(0),
)
const ResumenCarteraClientesSchema = v.object({
  version: v.literal(1),
  generado_en: v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s)))),
  zona: v.literal('America/Lima'),
  dias_alarma_renovacion: v.literal(30),
  clientes: v.object({ en_gestion: ConteoCarteraSchema, de_baja: ConteoCarteraSchema,
    con_capital: ConteoCarteraSchema, sin_asesor: ConteoCarteraSchema }),
  capital_activo: v.object({ pen: ImporteCarteraSchema, usd: ImporteCarteraSchema }),
  contratos: v.object({ por_estado: v.record(v.string(), ConteoCarteraSchema),
    por_vencer_30: ConteoCarteraSchema, por_vencer_30_de_baja: ConteoCarteraSchema }),
})

/** Sólo valida y transporta la salida existente; no suma la lista ni altera reglas. */
export async function obtenerResumenCarteraClientes(signal?: AbortSignal): Promise<ResumenCarteraClientes> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('resumen_cartera_clientes_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.cartera.resumen_fallido')
  const r = v.safeParse(ResumenCarteraClientesSchema, data)
  if (!r.success || r.output.clientes.con_capital > r.output.clientes.en_gestion
    || r.output.clientes.sin_asesor > r.output.clientes.en_gestion
    || r.output.contratos.por_vencer_30_de_baja > r.output.contratos.por_vencer_30) {
    throw new CrmApiError('El resumen de Cartera no tiene el formato esperado.', 'RESUMEN_CARTERA_CLIENTES_CONTRACT')
  }
  return r.output
}

// ── Clientes: lista (vista crm.clientes_basicos, ya scopeada por rol) ──────────
const COLUMNAS_CLIENTE_BASICO = [
  'id',
  'nombres',
  'apellidos',
  'nombre_completo',
  'tipo_documento',
  'dni',
  'correo',
  'telefono',
  'asesor_perfil_id',
  'creado_por',
  'activo',
  'creado_en',
].join(',')

const ClienteBasicoRowSchema = v.object({
  id: v.string(),
  nombres: v.nullable(v.string()),
  apellidos: v.nullable(v.string()),
  nombre_completo: v.nullable(v.string()),
  // Tolerante A PROPÓSITO: un tipo de documento NUEVO en el portal no tira la
  // fila de la lista — degrada al default histórico 'DNI' (mismo criterio que
  // normalizarTipoDocumento). El detalle (ClienteDetalleRowSchema) sí es
  // estricto: ahí el tipo alimenta la validación del formulario.
  tipo_documento: v.fallback(v.picklist(TIPOS_DOCUMENTO_K), 'DNI'),
  dni: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  telefono: v.nullable(v.string()),
  asesor_perfil_id: v.nullable(v.string()),
  // Junto con asesor_perfil_id decide la regla de cartera POR FILA en la UI
  // (Corregir/+Contrato solo sobre clientes propios — espejo del servidor).
  creado_por: v.nullable(v.string()),
  activo: v.boolean(),
  creado_en: v.string(),
})

export async function listarClientes(signal?: AbortSignal): Promise<ClienteBasico[]> {
  const data = await leerListadoCarteraCompleto('clientes_basicos', COLUMNAS_CLIENTE_BASICO, signal)
  const items: ClienteBasico[] = []
  for (const cruda of data) {
    const r = v.safeParse(ClienteBasicoRowSchema, cruda)
    if (r.success) {
      items.push({
        ...r.output,
        nombre_completo: r.output.nombre_completo ?? '',
      })
    } else {
      throw new CrmApiError('La cartera de clientes contiene una fila con formato inesperado.', 'ROW_CONTRACT')
    }
  }
  return items
}

// ── Cliente: Ficha 360 comercial mínima y scopeada por el servidor ──────────
// Esta frontera es distinta del detalle usado por "Corregir": solo acepta
// identidad y contacto para impedir que domicilio o banca entren por accidente
// a la caché de la ficha comercial.
const ClienteFichaComercialRowSchema = v.strictObject({
  id: v.string(),
  nombres: v.nullable(v.string()),
  apellidos: v.nullable(v.string()),
  nombre_completo: v.nullable(v.string()),
  tipo_documento: v.picklist(TIPOS_DOCUMENTO_K),
  dni: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  telefono: v.nullable(v.string()),
  asesor_perfil_id: v.nullable(v.string()),
  activo: v.boolean(),
  creado_en: v.string(),
})

export async function obtenerClienteFichaComercial(
  id: string,
  signal?: AbortSignal,
): Promise<ClienteFichaComercial> {
  let consulta = cliente().schema('crm').rpc('cliente_ficha_fn', { p_cliente_id: id })
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la ficha del cliente.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.clientes.ficha_comercial_fallida', fallo)
    throw fallo
  }

  const resultado = v.safeParse(v.array(ClienteFichaComercialRowSchema), data)
  if (
    !resultado.success
    || resultado.output.length > 1
    || (resultado.output.length === 1 && resultado.output[0]?.id !== id)
  ) {
    const fallo = new CrmApiError('La ficha del cliente no tiene el formato esperado.', 'ROW_CONTRACT')
    registrarError('crm.clientes.ficha_comercial_fuera_de_contrato', fallo)
    throw fallo
  }
  const fila = resultado.output[0]
  if (!fila) throw new CrmApiError('Cliente no encontrado', 'NO_ENCONTRADO')
  return { ...fila, nombre_completo: fila.nombre_completo ?? '' }
}

// ── Cliente: detalle scopeado y redactado por el servidor ───────────────────
const ClienteDetalleRowSchema = v.object({
  id: v.string(),
  nombre_completo: v.nullable(v.string()),
  nombres: v.nullable(v.string()),
  apellidos: v.nullable(v.string()),
  tipo_documento: v.picklist(TIPOS_DOCUMENTO_K),
  dni: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  telefono: v.nullable(v.string()),
  domicilio: v.nullable(v.string()),
  asesor_perfil_id: v.nullable(v.string()),
  creado_por: v.nullable(v.string()),
  creado_en: v.string(),
  banca_visible: v.boolean(),
  cuentas_bancarias_visibles: v.boolean(),
  banco: v.nullable(v.string()),
  tipo_cuenta: v.nullable(v.string()),
  numero_cuenta: v.nullable(v.string()),
  cci: v.nullable(v.string()),
  titular_distinto: v.boolean(),
  beneficiario_nombre: v.nullable(v.string()),
  beneficiario_dni: v.nullable(v.string()),
  banco_usd: v.nullable(v.string()),
  tipo_cuenta_usd: v.nullable(v.string()),
  numero_cuenta_usd: v.nullable(v.string()),
  cci_usd: v.nullable(v.string()),
  titular_distinto_usd: v.boolean(),
  beneficiario_nombre_usd: v.nullable(v.string()),
  beneficiario_dni_usd: v.nullable(v.string()),
})

/**
 * El segundo número del lead que originó a este cliente.
 *
 * NO se copia a `public.perfiles` a propósito (decisión de Miguel, 2026-08-28):
 * esa tabla la comparte el portal, y duplicar el dato en dos sitios es como
 * acaban divergiendo. Se lee del lead, que sobrevive a la conversión con todos
 * sus datos — así, si el analista lo corrige en la ficha del lead, el cliente lo
 * ve al instante.
 *
 * Devuelve `null` cuando no hay lead que mirar, que es un caso REAL y no un
 * error: los cierres en cooperativa no crean cliente de Avance y por tanto no
 * tienen `perfil_id`. La RLS de `crm.leads` decide qué se ve; si el lead fue de
 * otro analista, aquí no llega nada, y eso es correcto.
 */
export async function obtenerSegundoNumeroDelCliente(
  clienteId: string,
  signal?: AbortSignal,
): Promise<{ telefono_alternativo: string | null; telefono_alternativo_crudo: string | null } | null> {
  let consulta = cliente()
    .schema('crm')
    .from('leads')
    .select('telefono_alternativo, telefono_alternativo_crudo, convertido_en')
    .eq('perfil_id', clienteId)
    // Un cliente puede volver por un segundo depósito: manda el lead más
    // reciente, que es el que tiene el contacto vigente.
    .order('convertido_en', { ascending: false, nullsFirst: false })
    .limit(1)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    // Un fallo aquí NO puede tumbar la ficha del cliente: es un dato de apoyo.
    registrarError('crm.clientes.segundo_numero_fallido', error)
    return null
  }
  const fila = (data ?? [])[0]
  if (!fila) return null
  return {
    telefono_alternativo: fila.telefono_alternativo ?? null,
    telefono_alternativo_crudo: fila.telefono_alternativo_crudo ?? null,
  }
}

/**
 * Detalle comercial para "ver" y "corregir". La RPC conserva una frontera de
 * array: 0 filas significa inexistente o fuera de ámbito, sin revelar cuál.
 */
export async function obtenerClienteDetalle(id: string, signal?: AbortSignal): Promise<ClienteDetalle> {
  let consulta = cliente().schema('crm').rpc('cliente_detalle_fn', { p_cliente_id: id })
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el cliente.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.clientes.detalle_fallido', fallo)
    throw fallo
  }
  const cruda = (data ?? [])[0]
  if (!cruda) {
    // La RPC no devolvió la fila (fuera de tu ámbito) o no existe: mismo mensaje,
    // sin revelar existencia (igual que actualizarLead).
    throw new CrmApiError('Cliente no encontrado', 'NO_ENCONTRADO')
  }
  const r = v.safeParse(ClienteDetalleRowSchema, cruda)
  if (!r.success) {
    const fallo = new CrmApiError('Los datos del cliente no tienen el formato esperado.', 'ROW_CONTRACT')
    registrarError('crm.clientes.detalle_fuera_de_contrato', fallo)
    throw fallo
  }
  return { ...r.output, nombre_completo: r.output.nombre_completo ?? '' }
}

/**
 * ¿ESE cliente del portal está en MI cartera, según el servidor?
 *
 * Pregunta barata (una fila, solo el id, cero PII) que responde EXACTAMENTE lo
 * que va a decidir `public.crear_contrato`, porque las dos reglas son la misma:
 * la policy `perfiles_analista_select` concede al analista los clientes con
 * `asesor_perfil_id = auth.uid()` o (`asesor_perfil_id is null` y
 * `creado_por = auth.uid()`), y ese es literalmente el gate de cartera de la
 * RPC. Si la fila vuelve, el contrato pasará; si no vuelve, lo rechazará.
 *
 * Existe por la rama `ya_existia` de `crm-convertir-lead`: cuando el documento
 * YA era cliente del portal, la edge lo ENLAZA al lead pero no le toca el
 * `asesor_perfil_id`, así que el cliente puede quedar a nombre de otro analista.
 * Sin esta comprobación la ficha solo podía adivinar, y adivinar era prometer.
 *
 * `null` = NO SE PUDO COMPROBAR (red, RLS, servidor). El llamador no debe
 * afirmar ninguna de las dos cosas: no es un `false` disfrazado.
 */
export async function esClienteDeMiCartera(perfilId: string, signal?: AbortSignal): Promise<boolean | null> {
  let consulta = cliente().from('perfiles').select('id').eq('id', perfilId).eq('rol', 'cliente').limit(1)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    registrarError(
      'crm.clientes.cartera_no_verificable',
      new CrmApiError('No se pudo comprobar la cartera del cliente.', error.code || 'POSTGREST_ERROR'),
    )
    return null
  }
  return (data ?? []).length > 0
}

// ── Alta de cliente (edge crear-cliente del portal: Auth + perfil + correo REAL
//    de bienvenida; clave temporal = documento con padStart(8,'0') server-side).
//    Desde 2026-07-27 la edge SÍ acepta los bancarios y los escribe en el mismo
//    INSERT: ya no hay un segundo paso que pueda fallar y dejar al cliente sin la
//    cuenta donde cobra. La clave es opcional en la edge (el portal no la manda y
//    conserva su comportamiento de siempre), pero el CRM la manda SIEMPRE. ───────
export interface CrearClientePortalInput {
  email: string
  /** Opcional: sin password la edge usa la clave temporal (= documento). */
  password?: string | null
  nombre_completo: string
  apellidos: string
  nombres: string
  dni: string
  telefono?: string | null
  domicilio: string
  tipo_documento: TipoDocumentoCliente
  /** Cuentas de depósito. La edge exige al menos una cuando el bloque viaja. */
  bancarios: BancariosInput
}

export interface AltaClienteResultado {
  userId: string
  emailEnviado: boolean
}

// Los fallos de Supabase Auth llegan en inglés crudo desde las edges que crean
// usuarios (solo reenvían createErr.message). Espejo del mapeo del portal
// (analista.js:624-630): el analista lee es-PE, no 'A user with this email…'.
function traducirErrorAlta(mensaje: string): string {
  if (/already.+(registered|exists)/i.test(mensaje)) return 'Este correo ya está registrado.'
  if (/invalid.+email|email.+invalid/i.test(mensaje)) return 'El correo electrónico no es válido.'
  return mensaje
}

export async function crearClientePortal(payload: CrearClientePortalInput): Promise<AltaClienteResultado> {
  const body: Record<string, unknown> = {
    email: payload.email,
    nombre_completo: payload.nombre_completo,
    apellidos: payload.apellidos,
    nombres: payload.nombres,
    dni: payload.dni,
    telefono: payload.telefono ?? null,
    domicilio: payload.domicilio,
    tipo_documento: payload.tipo_documento,
    bancarios: payload.bancarios,
  }
  if (payload.password) body.password = payload.password

  const { data, error } = await cliente().functions.invoke('crear-cliente', {
    body,
  })
  if (error) {
    let mensaje = 'No se pudo crear el cliente.'
    // FunctionsHttpError expone la respuesta del edge en `context`: extraemos
    // nuestro { error } es-PE (mensaje seguro que arma la propia edge).
    try {
      const ctx = (error as { context?: Response }).context
      if (ctx && typeof ctx.json === 'function') {
        const cuerpo = await ctx.json()
        if (cuerpo?.error) mensaje = traducirErrorAlta(String(cuerpo.error))
      }
    } catch {
      /* nos quedamos con el mensaje genérico */
    }
    const fallo = new CrmApiError(mensaje, 'ALTA_CLIENTE_FALLIDA')
    registrarError('crm.clientes.alta_fallida', fallo)
    throw fallo
  }
  const cuerpo = (data ?? {}) as {
    ok?: boolean
    user_id?: string
    email_enviado?: boolean
    error?: string
  }
  if (cuerpo.error) {
    const fallo = new CrmApiError(String(cuerpo.error), 'ALTA_CLIENTE_FALLIDA')
    registrarError('crm.clientes.alta_fallida', fallo)
    throw fallo
  }
  const userId = String(cuerpo.user_id ?? '')
  if (!userId) {
    // Sin id no hay 2º paso de bancarios ni contrato: se reporta como fallo,
    // nunca como éxito silencioso (lección del portal).
    const fallo = new CrmApiError('El alta no devolvió el id del cliente.', 'ALTA_SIN_ID')
    registrarError('crm.clientes.alta_sin_id', fallo)
    throw fallo
  }
  return { userId, emailEnviado: Boolean(cuerpo.email_enviado) }
}

// ── Corrección del cliente (analista: RLS 5 h; Gerencia: RPC acotada) ──────────
export type ClientePortalPatch = Omit<Database['public']['Tables']['perfiles']['Update'],
  | 'banco' | 'tipo_cuenta' | 'numero_cuenta' | 'cci'
  | 'titular_distinto' | 'beneficiario_nombre' | 'beneficiario_dni'
  | 'banco_usd' | 'tipo_cuenta_usd' | 'numero_cuenta_usd' | 'cci_usd'
  | 'titular_distinto_usd' | 'beneficiario_nombre_usd' | 'beneficiario_dni_usd'>

/**
 * Devuelve `true` si el servidor guardó. En el camino del analista, `false`
 * significa que UPDATE tocó 0 filas (ventana RLS vencida). Gerencia usa una RPC
 * con allowlist y sello de tiempo del servidor. Jamás asumir éxito sin confirmación.
 */
export async function actualizarClientePortal(
  id: string,
  patch: ClientePortalPatch,
  comoGerencia = false,
): Promise<boolean> {
  if (comoGerencia) {
    const { data, error } = await cliente()
      .schema('crm')
      .rpc('actualizar_cliente_gerencia_con_domicilio', {
        p_cliente_id: id,
        p_patch: patch as Database['crm']['Functions']['actualizar_cliente_gerencia_con_domicilio']['Args']['p_patch'],
      })
    if (error) throw aErrorApi(error, 'crm.clientes.update_gerencia_fallido')
    return data === true
  }

  const { data, error } = await cliente().from('perfiles').update(patch).eq('id', id).select('id')
  if (error) throw aErrorApi(error, 'crm.clientes.update_fallido')
  return (data?.length ?? 0) > 0
}

/**
 * Corrige tipo y numero de documento por la puerta administrativa auditada.
 * El servidor vuelve a exigir rol Portal admin/superadmin y sincroniza la
 * identidad CRM cuando el cliente ya fue reconocido como persona.
 */
export async function corregirDocumentoClienteAdmin(
  id: string,
  tipo: TipoDocumento,
  documento: string,
  motivo: string,
): Promise<void> {
  const { data, error } = await cliente()
    .schema('crm')
    .rpc('corregir_documento_cliente_admin_fn', {
      p_cliente_id: id,
      p_tipo: tipo,
      p_documento: documento,
      p_motivo: motivo,
    })
  if (error) throw aErrorApi(error, 'crm.clientes.correccion_documento_admin_fallida')

  const respuesta = data as { ok?: unknown } | null
  if (!respuesta || Array.isArray(respuesta) || respuesta.ok !== true) {
    const fallo = new CrmApiError(
      'El servidor no confirmo la correccion del documento.',
      'CORRECCION_DOCUMENTO_SIN_CONFIRMACION',
    )
    registrarError('crm.clientes.correccion_documento_admin_sin_confirmacion', fallo)
    throw fallo
  }
}

/**
 * Corrige el correo de acceso de un cliente como admin o superadmin.
 *
 * Va por una edge y no por una RPC porque el correo vive en TRES sitios que
 * tienen que moverse juntos —`auth.users`, `auth.identities` y
 * `perfiles.correo`— y los dos de `auth` solo se mueven a la vez desde la API
 * de administracion, que necesita la service_role. Cambiar uno solo deja al
 * cliente sin poder entrar al portal SIN NINGUN ERROR VISIBLE.
 *
 * La Edge usa la Admin API; el servidor confirma Auth y perfil en la misma
 * transacción. Antes de responder se comprueban los tres correos.
 */
export async function corregirCorreoClienteAdmin(
  id: string,
  correo: string,
  motivo: string,
): Promise<void> {
  const { data, error } = await cliente().functions.invoke('corregir-correo-cliente', {
    body: { cliente_id: id, correo, motivo },
  })
  if (error) {
    let mensaje = 'No se pudo corregir el correo de acceso.'
    // FunctionsHttpError trae la respuesta del edge en `context`: de ahi sale
    // nuestro { error } en es-PE (incluido el aviso de reversion fallida).
    try {
      const ctx = (error as { context?: Response }).context
      if (ctx && typeof ctx.json === 'function') {
        const cuerpo = await ctx.json()
        if (cuerpo?.error) mensaje = traducirErrorAlta(String(cuerpo.error))
      }
    } catch {
      /* nos quedamos con el mensaje generico */
    }
    const fallo = new CrmApiError(mensaje, 'CORRECCION_CORREO_FALLIDA')
    registrarError('crm.clientes.correccion_correo_fallida', fallo)
    throw fallo
  }

  const cuerpo = (data ?? {}) as { ok?: boolean; error?: string }
  if (cuerpo.error || cuerpo.ok !== true) {
    // Un 200 sin `ok` no es un exito: no se dice «guardado» sin confirmacion.
    const fallo = new CrmApiError(
      cuerpo.error ? traducirErrorAlta(cuerpo.error) : 'El servidor no confirmo la correccion del correo.',
      'CORRECCION_CORREO_SIN_CONFIRMACION',
    )
    registrarError('crm.clientes.correccion_correo_sin_confirmacion', fallo)
    throw fallo
  }
}

// ── Datos legales que el contrato exige ANTES de intentar emitirlo ────────────
// El PDF se reserva dentro de la MISMA transacción del alta, así que un dato
// legal ausente revierte el contrato entero con 'Faltan datos legales
// obligatorios del titular o del analista' — un mensaje que no dice CUÁL falta.
// Preguntarlo antes convierte ese muro en un campo que el analista rellena.

/** Campos del titular que el PDF exige (nombres, nunca valores: no es una vía a la PII). */
export const CAMPOS_LEGALES_CLIENTE = ['nombre_completo', 'tipo_documento', 'documento', 'domicilio', 'correo'] as const
export type CampoLegalCliente = (typeof CAMPOS_LEGALES_CLIENTE)[number]

/** Campos del propio analista que firma el alta (contratos.creado_por = auth.uid()). */
export const CAMPOS_LEGALES_ANALISTA = ['nombre_completo', 'documento', 'telefono', 'correo'] as const
export type CampoLegalAnalista = (typeof CAMPOS_LEGALES_ANALISTA)[number]

export interface DatosLegalesContrato {
  clienteId: string
  /** El único hueco que el analista puede cerrar por su cuenta. */
  faltaDomicilio: boolean
  faltanCliente: CampoLegalCliente[]
  faltanAnalista: CampoLegalAnalista[]
}

const DatosLegalesContratoSchema = v.strictObject({
  version: v.literal(1),
  cliente_id: v.pipe(v.string(), v.uuid()),
  falta_domicilio: v.boolean(),
  faltan_cliente: v.array(v.picklist(CAMPOS_LEGALES_CLIENTE)),
  faltan_analista: v.array(v.picklist(CAMPOS_LEGALES_ANALISTA)),
})

export async function obtenerDatosLegalesContrato(
  clienteId: string,
  signal?: AbortSignal,
): Promise<DatosLegalesContrato> {
  let consulta = cliente().schema('crm').rpc('datos_legales_contrato_fn', {
    p_cliente_id: clienteId,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw aErrorApi(error, 'crm.contrato.datos_legales_fallido')
  const r = v.safeParse(DatosLegalesContratoSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('No se pudo comprobar qué datos legales exige el contrato.', 'RESPUESTA_INVALIDA')
    registrarError('crm.contrato.datos_legales_respuesta_invalida', fallo)
    throw fallo
  }
  return {
    clienteId: r.output.cliente_id,
    faltaDomicilio: r.output.falta_domicilio,
    faltanCliente: [...r.output.faltan_cliente],
    faltanAnalista: [...r.output.faltan_analista],
  }
}

/**
 * `conservado` NO es un fallo: significa que el domicilio ya estaba escrito
 * (otra sesión ganó la carrera) y el servidor lo respetó. Lo que el analista
 * tecleó NO se guardó, y el front no puede darlo por bueno.
 *
 * El servidor NO devuelve el domicilio vigente, a propósito: el alcance de la
 * RPC incluye al supervisor del árbol, que por RLS no puede leer esa columna
 * (`perfiles_analista_select` exige `asesor_perfil_id = auth.uid()`). Devolverlo
 * convertiría una escritura en una vía de lectura de PII. Hallazgo de la
 * auditoría adversaria del 2026-08-19.
 */
export type AccionDomicilio = 'completado' | 'conservado'

export interface DomicilioCompletado {
  accion: AccionDomicilio
}

const DomicilioCompletadoSchema = v.strictObject({
  version: v.literal(1),
  accion: v.picklist(['completado', 'conservado']),
})

export async function completarDomicilioCliente(clienteId: string, domicilio: string): Promise<DomicilioCompletado> {
  const { data, error } = await cliente().schema('crm').rpc('completar_domicilio_cliente', {
    p_cliente_id: clienteId,
    p_domicilio: domicilio,
  })
  if (error) throw aErrorApi(error, 'crm.clientes.domicilio_fallido')
  const r = v.safeParse(DomicilioCompletadoSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('El servidor no confirmó el domicilio legal del cliente.', 'RESPUESTA_INVALIDA')
    registrarError('crm.clientes.domicilio_respuesta_invalida', fallo)
    throw fallo
  }
  return { accion: r.output.accion }
}

// ── Contratos de mi cartera (public.contratos + nombre del cliente embebido) ───
// El embed va DESAMBIGUADO por FK: contratos tiene más de una relación a
// perfiles (cliente_id, cerrado_por) y un hint ausente sería un 300 de PostgREST.
const COLUMNAS_CONTRATO = [
  'id',
  'numero_contrato',
  'cliente_id',
  'capital',
  'moneda',
  'tasa_anual',
  'modalidad',
  'tipo_interes',
  'categoria',
  'estado',
  'fecha_inicio',
  'fecha_vencimiento',
  'fecha_cierre_comercial',
  'notas_internas',
  'creado_por',
  'creado_en',
  'cliente_nombre',
  'producto_condicion_id',
  'producto_id',
  'producto_codigo',
  'producto_version_id',
  'producto_version',
  'producto_nombre',
  'producto_version_estado',
].join(',')

export const ContratoRowSchema = v.object({
  id: v.string(),
  numero_contrato: v.string(),
  cliente_id: v.string(),
  // numeric(12,2): PostgREST puede serializarlo como string
  capital: NumericCarteraSchema,
  moneda: v.picklist(['PEN', 'USD']),
  tasa_anual: NumericCarteraSchema,
  modalidad: v.picklist(MODALIDADES_CONTRATO),
  tipo_interes: v.picklist(TIPOS_INTERES),
  categoria: v.nullable(v.picklist(CATEGORIAS_CONTRATO)),
  estado: v.picklist(ESTADOS_CONTRATO),
  fecha_inicio: v.pipe(v.string(), v.isoDate()),
  fecha_vencimiento: v.pipe(v.string(), v.isoDate()),
  // El mes con el que se le mide la cuota al analista. Va REQUERIDA a
  // propósito: si el servidor dejara de mandarla, es mejor que la fila se
  // rechace la lectura a que la cartera se reparta por un mes inventado.
  fecha_cierre_comercial: v.pipe(v.string(), v.isoDate()),
  notas_internas: v.nullable(v.string()),
  creado_por: v.nullable(v.string()),
  creado_en: v.string(),
  cliente_nombre: v.nullable(v.string()),
  producto_condicion_id: v.pipe(v.string(), v.uuid()),
  producto_id: v.pipe(v.string(), v.uuid()),
  producto_codigo: v.pipe(v.string(), v.minLength(1)),
  producto_version_id: v.pipe(v.string(), v.uuid()),
  producto_version: EnteroProductoSchema,
  producto_nombre: v.pipe(v.string(), v.minLength(1)),
  producto_version_estado: v.picklist(['borrador', 'publicada', 'retirada']),
})

export async function listarMisContratos(signal?: AbortSignal): Promise<ContratoRow[]> {
  // Vista con ámbito del esquema crm (molde clientes_basicos): gerencia ve
  // todo, supervisor su subárbol, analista su cartera. La RLS directa de
  // public.contratos dejaba a gerencia en 0 filas y al supervisor sin su equipo.
  const data = await leerListadoCarteraCompleto('contratos_cartera', COLUMNAS_CONTRATO, signal)
  const items: ContratoRow[] = []
  for (const cruda of data) {
    const r = v.safeParse(ContratoRowSchema, cruda)
    if (!r.success) {
      throw new CrmApiError('La cartera contiene un contrato con formato inesperado.', 'ROW_CONTRACT')
    }
    const fila = r.output
    items.push({
      id: fila.id,
      numero_contrato: fila.numero_contrato,
      cliente_id: fila.cliente_id,
      cliente_nombre: fila.cliente_nombre,
      capital: aNumero(fila.capital) ?? 0,
      moneda: fila.moneda,
      tasa_anual: aNumero(fila.tasa_anual) ?? 0,
      modalidad: fila.modalidad,
      tipo_interes: fila.tipo_interes,
      categoria: fila.categoria,
      estado: fila.estado,
      fecha_inicio: fila.fecha_inicio,
      fecha_vencimiento: fila.fecha_vencimiento,
      fecha_cierre_comercial: fila.fecha_cierre_comercial,
      notas_internas: fila.notas_internas,
      creado_por: fila.creado_por,
      creado_en: fila.creado_en,
      producto_condicion_id: fila.producto_condicion_id,
      producto_id: fila.producto_id,
      producto_codigo: fila.producto_codigo,
      producto_version_id: fila.producto_version_id,
      producto_version: fila.producto_version,
      producto_nombre: fila.producto_nombre,
      producto_version_estado: fila.producto_version_estado,
    })
  }
  return items
}

// ── Operaciones postventa: renovaciones + upgrades, ledger de solo lectura ───
const COLUMNAS_OPERACION_CARTERA = [
  'id',
  'cliente_id',
  'vendedor_id',
  'tipo',
  'contrato_origen_id',
  'contrato_nuevo_id',
  'fecha_operacion',
  'periodo',
  'moneda',
  'capital_renovado',
  'capital_adicional',
  'elegible_conversion',
  'desglose_completo',
  'fuente',
  'creado_por',
  'creado_en',
].join(',')

const OperacionCarteraRowSchema = v.object({
  id: v.string(),
  cliente_id: v.string(),
  vendedor_id: v.string(),
  tipo: v.picklist(['renovacion', 'upgrade']),
  contrato_origen_id: v.nullable(v.string()),
  contrato_nuevo_id: v.string(),
  fecha_operacion: v.string(),
  periodo: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  capital_renovado: v.nullable(NumericCarteraSchema),
  capital_adicional: v.nullable(NumericCarteraSchema),
  elegible_conversion: v.boolean(),
  desglose_completo: v.boolean(),
  fuente: v.picklist(['flujo_cartera', 'backfill_agosto_2026']),
  creado_por: v.string(),
  creado_en: v.string(),
})

export async function listarOperacionesCartera(signal?: AbortSignal): Promise<OperacionCartera[]> {
  const data = await leerListadoCarteraCompleto('operaciones_cartera', COLUMNAS_OPERACION_CARTERA, signal)
  const items: OperacionCartera[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(OperacionCarteraRowSchema, cruda)
    if (!r.success) {
      const fallo = new CrmApiError('El desglose de renovaciones tiene un formato inesperado.', 'ROW_CONTRACT')
      registrarError('crm.operaciones_cartera.fila_invalida', fallo)
      // Fail-closed: omitir una fila haría cuadrar mal renovado + adicional.
      throw fallo
    }
    items.push({
      ...r.output,
      capital_renovado: aNumero(r.output.capital_renovado),
      capital_adicional: aNumero(r.output.capital_adicional),
    })
  }
  return items
}

// ── Historial comercial postventa de un cliente ─────────────────────────────
const MAX_ACTIVIDADES_CLIENTE = 100
const ActividadClienteRowSchema = v.object({
  id: v.string(),
  cliente_id: v.string(),
  vendedor_id: v.string(),
  tarea_id: v.nullable(v.string()),
  tipo: v.picklist([
    'llamada_realizada',
    'llamada_no_contestada',
    'whatsapp_enviado',
    'whatsapp_recibido',
    'reunion_realizada',
    'nota',
  ]),
  detalle: v.nullable(v.string()),
  creado_por: v.nullable(v.string()),
  creado_en: v.string(),
})

export async function listarActividadesCliente(clienteId: string, signal?: AbortSignal): Promise<ActividadCliente[]> {
  let consulta = cliente()
    .schema('crm')
    .from('actividades_cliente')
    .select('id,cliente_id,vendedor_id,tarea_id,tipo,detalle,creado_por,creado_en')
    .eq('cliente_id', clienteId)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_ACTIVIDADES_CLIENTE)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.actividades_cliente.listado_fallido')
  return (data ?? []).map((fila) => {
    const r = v.safeParse(ActividadClienteRowSchema, fila)
    if (!r.success) throw new CrmApiError('Actividad de cliente fuera de contrato', 'ROW_CONTRACT')
    return r.output
  })
}

// ── Cronograma del contrato (solo lectura; RLS fail-closed: ajeno = 0 filas) ───
const COLUMNAS_CUOTA = [
  'id',
  'numero_cuota',
  'fecha_programada',
  'monto_programado',
  'estado',
  'tipo',
  'fecha_pago_real',
  'monto_pagado',
].join(',')

const CuotaRowSchema = v.object({
  id: v.string(),
  numero_cuota: v.number(),
  fecha_programada: v.string(),
  monto_programado: v.union([v.number(), v.string()]),
  estado: v.picklist(ESTADOS_CUOTA),
  tipo: v.picklist(TIPOS_CUOTA),
  fecha_pago_real: v.nullable(v.string()),
  monto_pagado: v.nullable(v.union([v.number(), v.string()])),
})

export async function obtenerCronograma(contratoId: string, signal?: AbortSignal): Promise<Cuota[]> {
  // RPC con ámbito (crm.cronograma_contrato_fn): fuera de ámbito = 0 filas.
  // La lectura directa por RLS dejaba el detalle VACÍO a gerencia/supervisor.
  let consulta = cliente()
    .schema('crm')
    .rpc('cronograma_contrato_fn', { p_contrato_id: contratoId })
    .select(COLUMNAS_CUOTA)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el cronograma.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.cronograma.listado_fallido', fallo)
    throw fallo
  }
  const items: Cuota[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(CuotaRowSchema, cruda)
    if (r.success) {
      items.push({
        ...r.output,
        monto_programado: aNumero(r.output.monto_programado) ?? 0,
        monto_pagado: aNumero(r.output.monto_pagado),
      })
    }
  }
  return items
}

// ── Co-titulares del contrato (cuentas mancomunadas, solo lectura) ─────────────
const TitularRowSchema = v.object({
  nombre_completo: v.string(),
  tipo_documento: v.picklist(TIPOS_DOCUMENTO_K),
  documento: v.string(),
  orden: v.number(),
})

export async function obtenerTitulares(contratoId: string, signal?: AbortSignal): Promise<Titular[]> {
  let consulta = cliente()
    .schema('crm')
    .rpc('titulares_contrato_fn', { p_contrato_id: contratoId })
    .select('nombre_completo, tipo_documento, documento, orden')
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar los co-titulares.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.titulares.listado_fallido', fallo)
    throw fallo
  }
  const items: Titular[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(TitularRowSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
}

// ── Corrección del contrato (wrapper crm → RPC public): conserva la ventana de
// 5 h/cartera/cronograma y evita cambiar la moneda de un contrato cuya cuenta
// de pago histórica ya quedó fijada. ──────────────────────────────────────────
export interface ActualizarContratoInput {
  /** Compatibilidad temporal de callers antiguos; el flujo libre lo omite. */
  producto_condicion_id?: string
  capital: number
  moneda: 'PEN' | 'USD'
  tasa_anual: number
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  categoria: CategoriaContrato
  fecha_inicio: string
  fecha_vencimiento: string
  numero_contrato: string
  /**
   * SIEMPRE cargar el valor vigente antes de abrir el form: si p_contrato no
   * trae esta clave, el servidor BORRA las notas. Por eso aquí NO es opcional.
   */
  notas_internas: string | null
  /**
   * Semántica del servidor: clave AUSENTE = no tocar; PRESENTE (incluso []) =
   * REEMPLAZAR el set completo. Cargar los actuales (obtenerTitulares) antes de
   * mandar, o los co-titulares se borran en silencio.
   */
  titulares?: TitularInput[]
}

export async function actualizarContrato(
  id: string,
  contrato: ActualizarContratoInput,
  cronograma: CuotaCronograma[],
): Promise<void> {
  const p_contrato: Record<string, unknown> = {
    capital: contrato.capital,
    moneda: contrato.moneda,
    tasa_anual: contrato.tasa_anual,
    modalidad: contrato.modalidad,
    tipo_interes: contrato.tipo_interes,
    categoria: contrato.categoria,
    fecha_inicio: contrato.fecha_inicio,
    fecha_vencimiento: contrato.fecha_vencimiento,
    numero_contrato: contrato.numero_contrato,
    notas_internas: contrato.notas_internas, // presente SIEMPRE, aunque sea null
  }
  // `titulares` solo viaja si el caller lo decidió (ver ActualizarContratoInput).
  if (contrato.titulares) p_contrato.titulares = contrato.titulares
  // La variante PDF abre la congelación únicamente dentro de esta transacción,
  // conserva el gate autoritativo de 5 h y reserva la revisión actualizada.
  const { error } = await cliente()
    .schema('crm')
    .rpc('actualizar_contrato_con_cuenta_pdf_v3', {
      p_id: id,
      p_contrato: p_contrato as unknown as Json,
      p_cronograma: cronograma as unknown as Json[],
    })
  // La ventana vencida AQUÍ sí es un error explícito (RAISE P0001 de la RPC),
  // a diferencia del UPDATE a perfiles que se queda callado.
  if (error) throw aErrorApi(error, 'crm.contrato.actualizar_fallido')
}

/**
 * Pasa la venta a otro analista, con motivo (P-055 Fase 3, decisión 2:
 * «debe poder reasignarse»).
 *
 * El motivo NO es burocracia: esto mueve el mérito —y mañana el pago— de una
 * persona a otra, así que el servidor lo exige y lo guarda en
 * `crm.reasignaciones_analista`. La atribución no se puede cambiar por ninguna
 * otra vía: un UPDATE directo a `public.contratos` lo rechaza un trigger.
 */
/** Atribución de una venta: de quién es, si es de prueba, y sus reasignaciones. */
export interface AtribucionContrato {
  contrato_id: string
  analista_id: string | null
  analista_nombre: string | null
  es_demo: boolean
  registrado_por: string | null
  /** ATR-3: quién cobra de verdad; `cadena` = pertenece a una cadena de upgrade. */
  atribucion_efectiva?: {
    cadena: boolean
    adoptada: boolean
    analista_id: string | null
    analista_nombre: string | null
  } | null | undefined
  reasignaciones: {
    cuando: string
    de: string | null
    a: string | null
    motivo: string
    por: string | null
  }[]
}

const AtribucionContratoSchema = v.object({
  contrato_id: v.string(),
  analista_id: v.nullable(v.string()),
  analista_nombre: v.nullable(v.string()),
  es_demo: v.boolean(),
  registrado_por: v.nullable(v.string()),
  // Opcional a propósito: el front no exige la clave hasta que ATR-3a esté publicada.
  atribucion_efectiva: v.optional(v.nullable(v.object({
    cadena: v.boolean(),
    adoptada: v.boolean(),
    analista_id: v.nullable(v.string()),
    analista_nombre: v.nullable(v.string()),
  }))),
  reasignaciones: v.array(
    v.object({
      cuando: v.string(),
      de: v.nullable(v.string()),
      a: v.nullable(v.string()),
      motivo: v.string(),
      por: v.nullable(v.string()),
    }),
  ),
})

/**
 * La RPC devuelve NULL cuando quien pregunta no puede ver ese contrato — la
 * regla la pone la vista `crm.contratos_cartera`, no esta capa. Se traduce a
 * `null` sin inventar un error: no poder verlo no es un fallo.
 */
export async function obtenerAtribucionContrato(
  contratoId: string,
  signal?: AbortSignal,
): Promise<AtribucionContrato | null> {
  let consulta = cliente().schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: contratoId })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.contrato.atribucion_fallida')
  if (data == null) return null
  const r = v.safeParse(AtribucionContratoSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('El servidor devolvió una atribución con formato no reconocido.', 'ROW_CONTRACT')
    registrarError('crm.contrato.atribucion_formato', fallo)
    throw fallo
  }
  return r.output
}

export async function reasignarAnalistaContrato(
  contratoId: string,
  analistaId: string,
  motivo: string,
): Promise<void> {
  const { error } = await cliente().rpc('reasignar_analista_contrato', {
    p_contrato_id: contratoId,
    p_analista_id: analistaId,
    p_motivo: motivo,
  })
  if (error) throw aErrorApi(error, 'crm.contrato.reasignar_fallido')
}

// ═══════════════════════════════════════════════════════════════════════════════
// MÉTRICAS DE GERENCIA — 4 RPCs crm.metricas_*_fn (SECURITY DEFINER, ya en prod).
// El ÁMBITO lo resuelve el servidor (gerencia=todo, supervisor=subárbol,
// analista=él): el navegador jamás recorta ni agrega seguridad. Aquí solo se
// valida cada fila con Valibot y se coerciona numeric/bigint (PostgREST puede
// serializar numeric como string — mismo trato que monto_estimado/capital).
// El pivoteo para las gráficas vive en lib/metricas (helpers puros).
// ═══════════════════════════════════════════════════════════════════════════════

// numeric/bigint del servidor: número o string según el serializador.
const NumericoRpc = v.union([v.number(), v.string()])

const MetricaCapitalRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  // Sin picklist a propósito: una categoría nueva del portal NO debe tirar la
  // fila — lib/metricas ya agrupa lo desconocido como '—' (sin categoría).
  categoria: v.nullable(v.string()),
  contratos: NumericoRpc,
  capital_colocado: NumericoRpc,
})

const MetricaPagosRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  tipo: v.picklist(TIPOS_CUOTA),
  estado: v.picklist(ESTADOS_CUOTA),
  cuotas: NumericoRpc,
  monto_programado: NumericoRpc,
  monto_pagado: NumericoRpc,
})

const MetricaVencimientosRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  contratos_por_vencer: NumericoRpc,
  capital_por_vencer: NumericoRpc,
})

/** Error de RPC de métricas → CrmApiError es-PE + registro (patrón del módulo). */
function falloMetricas(error: { code?: string | null }, contexto: string): CrmApiError {
  const fallo = new CrmApiError('No se pudieron cargar las métricas.', error.code || 'POSTGREST_ERROR')
  registrarError(contexto, fallo)
  return fallo
}

/** Registra (sin PII) cuántas filas de una RPC de métricas quedaron fuera de contrato. */
function registrarFilasMetricasInvalidas(rpc: string, descartadas: number): void {
  if (descartadas === 0) return
  registrarError(
    'crm.metricas.filas_invalidas',
    new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
    { rpc, descartadas },
  )
}

/** Capital colocado por mes/moneda/categoría (default: últimos 12 meses). */
export async function listarMetricasCapitalMes(pMeses = 12, signal?: AbortSignal): Promise<FilaCapitalMes[]> {
  let consulta = cliente().schema('crm').rpc('metricas_capital_mes_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.capital_fallido')
  const items: FilaCapitalMes[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaCapitalRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      moneda: r.output.moneda,
      categoria: r.output.categoria,
      contratos: aNumero(r.output.contratos) ?? 0,
      capital_colocado: aNumero(r.output.capital_colocado) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('capital_mes', descartadas)
  return items
}

// Altas de contratos NUEVOS por el analista que cierra (crm.altas_nuevas_por_analista_fn,
// F7: sustituye a metricas_altas_analista_fn). El servidor ya resolvió el ámbito
// (gerencia ve todo; un vendedor, lo suyo) y excluyó los cierres anulados.
const AltasNuevasRowSchema = v.object({
  mes: v.string(),
  // Puede venir NULL: contratos sin analista de cierre ("Sin analista"), que solo
  // ve gerencia. Se mapea a un id centinela para que el ranking los agrupe.
  analista_id: v.nullable(v.string()),
  analista_nombre: v.string(),
  altas: NumericoRpc,
})

export const SIN_ANALISTA_ID = 'sin-analista'

// ── Facturación diaria (pantalla de Gerencia) ────────────────────────────────
// `crm.facturacion_diaria_fn(p_mes)` ya agrupó por día, tipo, moneda, analista y
// supervisor, y ya resolvió el ámbito y el supervisor de ENTONCES. Aquí solo se
// valida la forma: una fila fuera de contrato se descarta y se cuenta, nunca se
// adivina (misma política que el resto de métricas).
const FacturacionDiaRowSchema = v.object({
  dia: v.string(),
  tipo: v.string(),
  moneda: v.string(),
  // Puede venir NULL: capital sin analista atribuido, que solo ve gerencia.
  analista_id: v.nullable(v.string()),
  analista_nombre: v.string(),
  // NULL cuando de ese analista no consta supervisor por ningún camino.
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.string(),
  operaciones: NumericoRpc,
  capital: NumericoRpc,
})


/** Facturación de UN mes comercial (`p_mes` = 'YYYY-MM-01'). */
/** El array de filas, más cuántas vinieron ilegibles (para poder avisarlo). */
export type FacturacionDelMes = FilaFacturacionDia[] & { descartadas: number }

export async function listarFacturacionDiaria(
  mes: string,
  signal?: AbortSignal,
): Promise<FacturacionDelMes> {
  let consulta = cliente().schema('crm').rpc('facturacion_diaria_fn', { p_mes: mes })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.facturacion_diaria_fallido')
  const items: FilaFacturacionDia[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(FacturacionDiaRowSchema, cruda)
    // La moneda llega como texto libre del servidor; si no es una de las dos que
    // el CRM maneja, la fila no se pinta: sumarla a la columna equivocada sería
    // peor que perderla.
    if (!r.success || !esMoneda(r.output.moneda)) {
      descartadas += 1
      continue
    }
    // UN IMPORTE QUE NO SE ENTIENDE NO ES CERO. Antes `?? 0` convertía cualquier
    // basura numérica en «vendió cero», que es una afirmación falsa y silenciosa
    // sobre dinero. Ahora la fila se descarta y se cuenta. Y el día tiene que
    // ser una fecha de verdad: un 'dia' con formato raro pasaba el esquema y
    // luego desaparecía de la malla sin que nadie llevara la cuenta.
    // (Auditoría de Codex, 11/09/2026.)
    const operaciones = aNumero(r.output.operaciones)
    const capital = aNumero(r.output.capital)
    if (operaciones == null || capital == null || !/^\d{4}-\d{2}-\d{2}$/.test(r.output.dia)) {
      descartadas += 1
      continue
    }
    items.push({
      dia: r.output.dia,
      tipo: r.output.tipo,
      moneda: r.output.moneda,
      analistaId: r.output.analista_id ?? SIN_ANALISTA_ID,
      analistaNombre: r.output.analista_nombre,
      supervisorId: r.output.supervisor_id ?? SIN_SUPERVISOR_ID,
      supervisorNombre: r.output.supervisor_nombre,
      operaciones,
      capital,
    })
  }
  registrarFilasMetricasInvalidas('facturacion_diaria', descartadas)
  // Se DECLARA cuántas filas no se pudieron leer para que la pantalla pueda
  // avisar. Un total al que le faltan cifras sin decirlo es peor que un error.
  return Object.assign(items, { descartadas })
}

/** Altas nuevas por analista y mes (default: últimos 12 meses; el servidor acota 1..60). */
export async function listarAltasNuevasPorAnalista(pMeses = 12, signal?: AbortSignal): Promise<FilaAltasAnalista[]> {
  let consulta = cliente().schema('crm').rpc('altas_nuevas_por_analista_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.altas_nuevas_fallido')
  const items: FilaAltasAnalista[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(AltasNuevasRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      analista_id: r.output.analista_id ?? SIN_ANALISTA_ID,
      analista_nombre: r.output.analista_nombre,
      altas: aNumero(r.output.altas) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('altas_nuevas', descartadas)
  return items
}

// ─── Rentabilidad R2: la tarjeta de observación (crm.observacion_rentabilidad_fn) ───
// El ledger crm.ledger_rentabilidad anota, por cada alta o corrección de tasa, la base
// que dice el núcleo frente a la que quedó. Esta RPC (solo Gerencia/Directorio) agrega
// el periodo: totales, margen cedido/retenido por moneda, por analista, por regla, casos
// sin regla y últimos divergentes. Una sola fuente y una sonda `coherente` del servidor.
const MontoPorMonedaSchema = v.object({ PEN: NumericoRpc, USD: NumericoRpc })
const ObservacionRentabilidadSchema = v.object({
  version: v.literal(1),
  periodo: v.object({ desde: v.string(), hasta: v.string() }),
  politica: v.nullable(v.object({ version: v.number(), modo: v.string(), tasa_base_nueva: NumericoRpc })),
  totales: v.object({
    observados: v.number(),
    contratos: v.optional(v.number()),
    eventos: v.optional(v.number()),
    importe_no_calculable: v.optional(v.number()),
    divergentes: v.number(),
    ceden: v.number(),
    retienen: v.number(),
    sin_regla: v.number(),
    correcciones: v.number(),
    puntos_promedio_cedido: NumericoRpc,
    cedido: MontoPorMonedaSchema,
    retenido: MontoPorMonedaSchema,
  }),
  por_regla: v.array(v.object({
    regla: v.string(),
    contratos: v.optional(v.number()),
    observados: v.optional(v.number()),
    divergentes: v.number(),
    cedido_pen: v.optional(NumericoRpc),
    cedido_usd: v.optional(NumericoRpc),
    retenido_pen: v.optional(NumericoRpc),
    retenido_usd: v.optional(NumericoRpc),
  })),
  por_analista: v.array(v.object({
    analista_id: v.nullable(v.string()),
    analista_nombre: v.string(),
    contratos: v.optional(v.number()),
    observados: v.optional(v.number()),
    divergentes: v.number(),
    puntos_promedio_cedido: NumericoRpc,
    cedido_pen: NumericoRpc,
    cedido_usd: NumericoRpc,
    retenido_pen: v.optional(NumericoRpc),
    retenido_usd: v.optional(NumericoRpc),
  })),
  sin_regla: v.array(v.object({ motivo: v.string(), n: v.number() })),
  ultimos_divergentes: v.array(v.object({
    contrato_id: v.string(),
    numero_contrato: v.string(),
    cliente_nombre: v.nullable(v.string()),
    analista_nombre: v.string(),
    categoria: v.nullable(v.string()),
    regla: v.string(),
    tasa_base: NumericoRpc,
    tasa_final: NumericoRpc,
    puntos: NumericoRpc,
    capital: v.nullable(NumericoRpc),
    moneda: v.nullable(v.string()),
    cedido: v.nullable(NumericoRpc),
    operacion: v.nullable(v.string()),
    registrado_en: v.string(),
  })),
  metodo: v.string(),
  altas_sin_observar: v.number(),
  cobertura: v.optional(v.object({
    observacion_activa_desde: v.nullable(v.string()),
    cobertura_desde: v.nullable(v.string()),
    periodo_sin_cobertura: v.boolean(),
  })),
  sondas: v.optional(v.object({
    consistencia_interna: v.boolean(),
    cobertura_altas: v.boolean(),
    cobertura_correcciones: v.string(),
  })),
  coherente: v.boolean(),
  generado_en: v.string(),
})
export type ObservacionRentabilidadCruda = v.InferOutput<typeof ObservacionRentabilidadSchema>

export interface AnalistaObservacion {
  analista_id: string
  analista_nombre: string
  observados: number
  divergentes: number
  puntos_promedio_cedido: number
  cedido_pen: number
  cedido_usd: number
  retenido_pen: number
  retenido_usd: number
}
export interface ObservacionRentabilidad {
  periodo: { desde: string; hasta: string }
  politica: { version: number; modo: string; tasa_base_nueva: number } | null
  totales: {
    observados: number
    eventos: number
    importe_no_calculable: number
    divergentes: number
    ceden: number
    retienen: number
    sin_regla: number
    correcciones: number
    puntos_promedio_cedido: number
    cedido: { PEN: number; USD: number }
    retenido: { PEN: number; USD: number }
  }
  por_regla: { regla: string; observados: number; divergentes: number }[]
  cobertura: { observacion_activa_desde: string | null; cobertura_desde: string | null; periodo_sin_cobertura: boolean } | null
  sondas: { consistencia_interna: boolean; cobertura_altas: boolean; cobertura_correcciones: string } | null
  por_analista: AnalistaObservacion[]
  sin_regla: { motivo: string; n: number }[]
  ultimos_divergentes: {
    contrato_id: string
    numero_contrato: string
    cliente_nombre: string | null
    analista_nombre: string
    categoria: string | null
    regla: string
    tasa_base: number
    tasa_final: number
    puntos: number
    capital: number | null
    moneda: string | null
    cedido: number | null
    operacion: string | null
    registrado_en: string
  }[]
  metodo: string
  altas_sin_observar: number
  coherente: boolean
}

// ─── Rentabilidad R1/R3: la tasa la decide la política; la excepción, Gerencia ───
type MonedaContrato = 'PEN' | 'USD'
// Núcleo: private.resolver_tasa (una sola definición de «qué tasa base corresponde y por qué»).
// El front NO calcula tasas: pregunta al núcleo (resolver_tasa_fn), pide excepción
// (solicitar_tasa_fn), Gerencia decide (resolver_solicitud_tasa_fn: aprobar | rechazar |
// aprobar_hasta) y el analista responde al tope (responder_tope_tasa_fn). Lecturas R3:
// solicitudes_tasa_fn, historial_tasa_cliente_fn, politica_rentabilidad_fn.
export type EstadoSolicitudTasa =
  | 'pendiente'
  | 'aprobada'
  | 'aprobada_con_tope'
  | 'rechazada'
  | 'aceptada_por_analista'
  | 'declinada_por_analista'
  | 'consumida'
  | 'vencida'
export { ESTADOS_SOLICITUD_TASA_VIVOS, etiquetaReglaTasa } from '@/lib/rentabilidad'

const ReglaTasaSchema = v.picklist(['primera_inversion', 'heredada_renovacion', 'heredada_upgrade', 'historica_legacy', 'sin_regla'])
export type ReglaTasa = v.InferOutput<typeof ReglaTasaSchema>

const ResolucionTasaSchema = v.object({
  observacion_sin_aprobacion: v.optional(v.boolean(), false),
  tasa_base: NumericoRpc,
  tasa_minima_sin_autorizacion: v.optional(NumericoRpc),
  regla: ReglaTasaSchema,
  categoria: v.string(),
  cliente_id: v.nullable(v.string()),
  bloqueo_conversion: v.optional(v.nullable(v.string()), null),
  contrato_origen: v.nullable(v.object({
    id: v.string(),
    numero_contrato: v.string(),
    tasa_anual: NumericoRpc,
    estado: v.string(),
    moneda: v.string(),
    capital: NumericoRpc,
    fecha_vencimiento: v.string(),
  })),
  contratos_previos: v.number(),
  contratos_activos: v.number(),
  prioridad_bandeja: v.boolean(),
  politica: v.object({
    id: v.string(),
    version: v.number(),
    modo: v.string(),
    tasa_base_nueva: NumericoRpc,
    tope_tecnico: NumericoRpc,
    vigencia_solicitud_dias: v.number(),
  }),
})
export interface ResolucionTasa {
  /** Señal del servidor: todos los controles ya respetan el modo observación. */
  observacion_sin_aprobacion?: boolean
  bloqueo_conversion?: string | null
  tasa_base: number
  /** Ausente en servidores anteriores: conservar el mínimo igual a la base. */
  tasa_minima_sin_autorizacion?: number
  regla: ReglaTasa
  contrato_origen: { id: string; numero_contrato: string; tasa_anual: number; estado: string } | null
  contratos_previos: number
  prioridad_bandeja: boolean
  politica: { version: number; modo: string; tasa_base_nueva: number; tope_tecnico: number; vigencia_solicitud_dias: number }
}

export interface IntencionContrato {
  lead_id?: string
  cliente_id: string | null
  categoria: CategoriaContrato
  contrato_origen_id: string | null
  /**
   * Condición de producto DECLARADA. Va null cuando el contrato entra por el puente legacy: su snapshot lo sintetiza
   * el servidor al insertar (y lo recrea al cambiar términos), así que el formulario no puede conocerlo, y el candado
   * de R4 normaliza igual en su orilla. Con un producto de catálogo va su id y la coincidencia es estricta.
   */
  producto_condicion_id?: string | null
  capital: number
  moneda: MonedaContrato
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  fecha_inicio: string
  fecha_vencimiento: string
  /** R4: contrato que se está CORRIGIENDO. Sin él el núcleo rechaza el origen de una renovación por «ya renovado». */
  contrato_id?: string | null
}


export type CondicionesTasaLead = Omit<IntencionContrato, 'cliente_id' | 'lead_id' | 'contrato_id'> & { tasa_anual: number }

/** Pregunta al núcleo qué tasa base corresponde a un contrato en intención (42501 si el cliente no está en el ámbito). */
export async function resolverTasa(
  clienteId: string,
  categoria: CategoriaContrato,
  contratoOrigenId: string | null,
  signal?: AbortSignal,
  leadId?: string,
): Promise<ResolucionTasa> {
  lanzarAbortSiCorresponde(signal)
  let consulta = leadId ? cliente().schema('crm').rpc('resolver_tasa_lead_fn', {
    p_lead_id: leadId, p_categoria: categoria, ...(contratoOrigenId ? { p_contrato_origen_id: contratoOrigenId } : {}),
  }) : cliente().schema('crm').rpc('resolver_tasa_fn', {
    p_cliente_id: clienteId,
    p_categoria: categoria,
    ...(contratoOrigenId ? { p_contrato_origen_id: contratoOrigenId } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rentabilidad.resolver_tasa_fallido')
  const r = v.safeParse(ResolucionTasaSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('La tasa base no tiene el formato esperado.', 'RESOLVER_TASA_CONTRACT')
    registrarError('crm.rentabilidad.resolver_tasa_fuera_de_contrato', fallo)
    throw fallo
  }
  const o = r.output
  const base = numEstricto(o.tasa_base, 'tasa_base')
  const minimo = o.tasa_minima_sin_autorizacion === undefined ? base : numEstricto(o.tasa_minima_sin_autorizacion, 'tasa_minima_sin_autorizacion')
  if (minimo <= 0 || minimo > base || Math.abs(minimo * 100 - Math.round(minimo * 100)) > 1e-8
      || (minimo < base && (o.categoria !== 'nuevo' || o.regla !== 'primera_inversion' || o.contrato_origen !== null))) {
    throw new CrmApiError('El rango de tasa no tiene el formato esperado.', 'RESOLVER_TASA_CONTRACT')
  }
  return {
    bloqueo_conversion: o.bloqueo_conversion,
    observacion_sin_aprobacion: o.observacion_sin_aprobacion,
    tasa_base: base,
    tasa_minima_sin_autorizacion: minimo,
    regla: o.regla,
    contrato_origen: o.contrato_origen
      ? { id: o.contrato_origen.id, numero_contrato: o.contrato_origen.numero_contrato, tasa_anual: aNumero(o.contrato_origen.tasa_anual) ?? 0, estado: o.contrato_origen.estado }
      : null,
    contratos_previos: o.contratos_previos,
    prioridad_bandeja: o.prioridad_bandeja,
    politica: {
      version: o.politica.version,
      modo: o.politica.modo,
      tasa_base_nueva: aNumero(o.politica.tasa_base_nueva) ?? 0,
      tope_tecnico: aNumero(o.politica.tope_tecnico) ?? 50,
      vigencia_solicitud_dias: o.politica.vigencia_solicitud_dias,
    },
  }
}

const SolicitudTasaSchema = v.object({
  id: v.string(),
  estado: v.picklist(['pendiente', 'aprobada', 'aprobada_con_tope', 'rechazada', 'aceptada_por_analista', 'declinada_por_analista', 'consumida', 'vencida']),
  estado_efectivo: v.optional(v.picklist(['pendiente', 'aprobada', 'aprobada_con_tope', 'rechazada', 'aceptada_por_analista', 'declinada_por_analista', 'consumida', 'vencida'])),
  vigente: v.optional(v.boolean()),
  categoria: v.string(),
  cliente_id: v.optional(v.nullable(v.string())),
  lead_id: v.optional(v.nullable(v.string())),
  cliente_nombre: v.optional(v.string()),
  contrato_origen_id: v.nullable(v.string()),
  contrato_origen_numero: v.nullable(v.string()),
  producto_condicion_id: v.optional(v.nullable(v.string())),
  capital: NumericoRpc,
  moneda: v.string(),
  modalidad: v.optional(v.string()),
  tipo_interes: v.optional(v.string()),
  fecha_inicio: v.string(),
  fecha_vencimiento: v.string(),
  tasa_base: NumericoRpc,
  regla_base: ReglaTasaSchema,
  tasa_solicitada: NumericoRpc,
  tasa_maxima_autorizada: v.nullable(NumericoRpc),
  motivo: v.string(),
  motivo_resolucion: v.nullable(v.string()),
  motivo_analista: v.optional(v.nullable(v.string())),
  prioridad_bandeja: v.optional(v.boolean()),
  contratos_previos: v.optional(v.number()),
  solicitada_por: v.string(),
  solicitante_nombre: v.optional(v.string()),
  solicitada_en: v.string(),
  vence_en: v.string(),
  resuelta_por: v.nullable(v.string()),
  resolutor_nombre: v.optional(v.nullable(v.string())),
  resuelta_en: v.nullable(v.string()),
  respondida_por_analista_en: v.optional(v.nullable(v.string())),
  consumida_en: v.optional(v.nullable(v.string())),
  contrato_id: v.nullable(v.string()),
  es_mia: v.optional(v.boolean()),
  puede_resolver: v.optional(v.boolean()),
  puede_responder: v.optional(v.boolean()),
})
export interface SolicitudTasa {
  lead_id?: string | null
  id: string
  estado: EstadoSolicitudTasa
  /** Una viva con vence_en pasado se declara vencida aunque la fila aún no lleve el sello. */
  estado_efectivo: EstadoSolicitudTasa
  vigente: boolean
  categoria: CategoriaContrato
  cliente_id: string | null
  cliente_nombre: string
  contrato_origen_id: string | null
  contrato_origen_numero: string | null
  producto_condicion_id: string | null
  capital: number
  moneda: MonedaContrato
  modalidad: ModalidadContrato | null
  tipo_interes: TipoInteres | null
  fecha_inicio: string
  fecha_vencimiento: string
  tasa_base: number
  regla_base: ReglaTasa
  tasa_solicitada: number
  /** La tasa AUTORIZADA efectiva: = pedida si aprobó tal cual; < pedida si aprobó hasta un tope. */
  tasa_maxima_autorizada: number | null
  motivo: string
  motivo_resolucion: string | null
  motivo_analista: string | null
  prioridad_bandeja: boolean
  contratos_previos: number
  solicitada_por: string
  solicitante_nombre: string
  solicitada_en: string
  vence_en: string
  resuelta_por: string | null
  resolutor_nombre: string | null
  resuelta_en: string | null
  respondida_por_analista_en: string | null
  contrato_id: string | null
  es_mia: boolean
  puede_resolver: boolean
  puede_responder: boolean
}

/** Un numeric del servidor que no se pueda leer NO se convierte en 0: es un contrato roto. */
function numEstricto(x: number | string | null | undefined, campo: string): number {
  const n = x == null ? null : aNumero(x)
  if (n == null || !Number.isFinite(n)) {
    const fallo = new CrmApiError(`El campo ${campo} de rentabilidad no es numérico.`, 'RENTABILIDAD_NUMERO_CONTRACT')
    registrarError('crm.rentabilidad.numero_fuera_de_contrato', fallo, { campo })
    throw fallo
  }
  return n
}

function aSolicitudTasa(o: v.InferOutput<typeof SolicitudTasaSchema>): SolicitudTasa {
  const vivo = ESTADOS_SOLICITUD_TASA_VIVOS.includes(o.estado)
  const vencida = vivo && new Date(o.vence_en).getTime() < Date.now()
  return {
    id: o.id,
    estado: o.estado,
    estado_efectivo: o.estado_efectivo ?? (vencida ? 'vencida' : o.estado),
    vigente: o.vigente ?? (vivo && !vencida),
    categoria: o.categoria as CategoriaContrato,
    cliente_id: o.cliente_id ?? null,
    lead_id: o.lead_id ?? null,
    cliente_nombre: o.cliente_nombre ?? 'Cliente',
    contrato_origen_id: o.contrato_origen_id,
    contrato_origen_numero: o.contrato_origen_numero,
    producto_condicion_id: o.producto_condicion_id ?? null,
    capital: numEstricto(o.capital, 'capital'),
    moneda: o.moneda as MonedaContrato,
    modalidad: (o.modalidad as ModalidadContrato | undefined) ?? null,
    tipo_interes: (o.tipo_interes as TipoInteres | undefined) ?? null,
    fecha_inicio: o.fecha_inicio,
    fecha_vencimiento: o.fecha_vencimiento,
    tasa_base: numEstricto(o.tasa_base, 'tasa_base'),
    regla_base: o.regla_base,
    tasa_solicitada: numEstricto(o.tasa_solicitada, 'tasa_solicitada'),
    tasa_maxima_autorizada: o.tasa_maxima_autorizada == null ? null : numEstricto(o.tasa_maxima_autorizada, 'tasa_maxima_autorizada'),
    motivo: o.motivo,
    motivo_resolucion: o.motivo_resolucion,
    motivo_analista: o.motivo_analista ?? null,
    prioridad_bandeja: o.prioridad_bandeja ?? false,
    contratos_previos: o.contratos_previos ?? 0,
    solicitada_por: o.solicitada_por,
    solicitante_nombre: o.solicitante_nombre ?? 'Sin nombre',
    solicitada_en: o.solicitada_en,
    vence_en: o.vence_en,
    resuelta_por: o.resuelta_por,
    resolutor_nombre: o.resolutor_nombre ?? null,
    resuelta_en: o.resuelta_en,
    respondida_por_analista_en: o.respondida_por_analista_en ?? null,
    contrato_id: o.contrato_id,
    es_mia: o.es_mia ?? false,
    puede_resolver: o.puede_resolver ?? false,
    puede_responder: o.puede_responder ?? false,
  }
}

function parsearSolicitudTasa(data: unknown, contexto: string): SolicitudTasa {
  const r = v.safeParse(SolicitudTasaSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('La solicitud de tasa no tiene el formato esperado.', 'SOLICITUD_TASA_CONTRACT')
    registrarError(contexto, fallo)
    throw fallo
  }
  return aSolicitudTasa(r.output)
}

/** El analista pide una tasa SUPERIOR a la base para un contrato en intención (D4: nunca por debajo). */
export async function solicitarTasa(intencion: IntencionContrato, tasaSolicitada: number, motivo: string): Promise<SolicitudTasa> {
  const { data, error } = await cliente().schema('crm').rpc('solicitar_tasa_fn', {
    p_solicitud: {
      ...(intencion.lead_id ? { lead_id: intencion.lead_id } : { cliente_id: intencion.cliente_id }),
      categoria: intencion.categoria,
      contrato_origen_id: intencion.contrato_origen_id,
      producto_condicion_id: intencion.producto_condicion_id ?? null,
      capital: intencion.capital,
      moneda: intencion.moneda,
      modalidad: intencion.modalidad,
      tipo_interes: intencion.tipo_interes,
      fecha_inicio: intencion.fecha_inicio,
      fecha_vencimiento: intencion.fecha_vencimiento,
      ...(intencion.contrato_id ? { contrato_id: intencion.contrato_id } : {}),
      tasa_solicitada: tasaSolicitada,
      motivo,
    },
  })
  if (error) throw aErrorApi(error, 'crm.rentabilidad.solicitar_fallido')
  return parsearSolicitudTasa(data, 'crm.rentabilidad.solicitar_fuera_de_contrato')
}

export type DecisionSolicitudTasa = 'aprobar' | 'rechazar' | 'aprobar_hasta'

/** Gerencia decide en un clic: aprobar, rechazar o aprobar hasta un tope (D6). Nunca la propia (D3). */
export async function resolverSolicitudTasa(
  solicitudId: string,
  decision: DecisionSolicitudTasa,
  tasaMaxima: number | null,
  motivo: string | null,
): Promise<SolicitudTasa> {
  const { data, error } = await cliente().schema('crm').rpc('resolver_solicitud_tasa_fn', {
    p_solicitud_id: solicitudId,
    p_decision: decision,
    ...(tasaMaxima != null ? { p_tasa_maxima: tasaMaxima } : {}),
    ...(motivo ? { p_motivo: motivo } : {}),
  })
  if (error) throw aErrorApi(error, 'crm.rentabilidad.resolver_solicitud_fallido')
  return parsearSolicitudTasa(data, 'crm.rentabilidad.resolver_fuera_de_contrato')
}

/** Quien pidió acepta el tope (y sigue) o lo declina. */
export async function responderTopeTasa(solicitudId: string, acepta: boolean, motivo: string | null): Promise<SolicitudTasa> {
  const { data, error } = await cliente().schema('crm').rpc('responder_tope_tasa_fn', {
    p_solicitud_id: solicitudId,
    p_acepta: acepta,
    ...(motivo ? { p_motivo: motivo } : {}),
  })
  if (error) throw aErrorApi(error, 'crm.rentabilidad.responder_fallido')
  return parsearSolicitudTasa(data, 'crm.rentabilidad.responder_fuera_de_contrato')
}

export interface OpcionesSolicitudesTasa {
  leadId?: string | null
  /** Solo las que pidió el actor (el formulario y el aviso del analista): el servidor filtra ANTES del límite. */
  soloMias?: boolean
  /** Solo las de este cliente. */
  clienteId?: string | null
  limite?: number
}
/** Solicitudes visibles para el actor (Gerencia: todas; analista: las suyas; supervisor: su subárbol), filtradas en el servidor. */
export async function listarSolicitudesTasa(estados: EstadoSolicitudTasa[] | null, signal?: AbortSignal, opciones: OpcionesSolicitudesTasa = {}): Promise<SolicitudTasa[]> {
  lanzarAbortSiCorresponde(signal)
  let consulta = opciones.leadId ? cliente().schema('crm').rpc('solicitudes_tasa_lead_fn', {
    p_lead_id: opciones.leadId, ...(estados ? { p_estados: estados } : {}), p_limite: opciones.limite ?? 200,
  }) : cliente().schema('crm').rpc('solicitudes_tasa_fn', {
    ...(estados ? { p_estados: estados } : {}),
    p_limite: opciones.limite ?? 200,
    ...(opciones.soloMias ? { p_solo_mias: true } : {}),
    ...(opciones.clienteId ? { p_cliente_id: opciones.clienteId } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rentabilidad.solicitudes_fallido')
  const r = v.safeParse(v.array(SolicitudTasaSchema), data)
  if (!r.success) {
    const fallo = new CrmApiError('Las solicitudes de tasa no tienen el formato esperado.', 'SOLICITUDES_TASA_CONTRACT')
    registrarError('crm.rentabilidad.solicitudes_fuera_de_contrato', fallo)
    throw fallo
  }
  return r.output.map(aSolicitudTasa)
}

export const TAMANO_PAGINA_HISTORIAL_DECISIONES_TASA = 10
export type DecisionHistorialTasa = 'aprobada' | 'aprobada_con_tope' | 'rechazada'
export interface CursorHistorialDecisionesTasa { resueltaEn: string; id: string }
export interface FiltrosHistorialDecisionesTasa { periodoDias: 0 | 7 | 30 | 90; decision: 'todas' | DecisionHistorialTasa; busqueda: string | null }
export interface FilaHistorialDecisionTasa {
  id: string; decision: DecisionHistorialTasa; estado_actual: EstadoSolicitudTasa; categoria: CategoriaContrato; cliente_nombre: string
  contrato_origen_numero: string | null; contrato_numero: string | null; capital: number; moneda: MonedaContrato; modalidad: ModalidadContrato
  tipo_interes: TipoInteres; fecha_inicio: string; fecha_vencimiento: string; tasa_base: number; regla_base: ReglaTasa; tasa_solicitada: number
  tasa_maxima_autorizada: number | null; motivo: string; motivo_resolucion: string | null; solicitante_nombre: string; solicitada_en: string
  vence_en: string; resolutor_nombre: string; resuelta_en: string; respondida_por_analista_en: string | null; consumida_en: string | null; politica_version: number | null
}
export interface PaginaHistorialDecisionesTasa { items: FilaHistorialDecisionTasa[]; total: number; siguienteCursor: CursorHistorialDecisionesTasa | null }

const DecisionHistorialTasaSchema = v.picklist(['aprobada', 'aprobada_con_tope', 'rechazada'])
const EstadoHistorialTasaSchema = v.picklist(['pendiente', 'aprobada', 'aprobada_con_tope', 'rechazada', 'aceptada_por_analista', 'declinada_por_analista', 'consumida', 'vencida'])
const FilaHistorialDecisionTasaSchema = v.object({
  id: v.string(), decision: DecisionHistorialTasaSchema, estado_actual: EstadoHistorialTasaSchema, categoria: v.string(), cliente_nombre: v.string(),
  contrato_origen_numero: v.nullable(v.string()), contrato_numero: v.nullable(v.string()), capital: NumericoRpc, moneda: v.string(), modalidad: v.string(), tipo_interes: v.string(),
  fecha_inicio: v.string(), fecha_vencimiento: v.string(), tasa_base: NumericoRpc, regla_base: ReglaTasaSchema, tasa_solicitada: NumericoRpc, tasa_maxima_autorizada: v.nullable(NumericoRpc),
  motivo: v.string(), motivo_resolucion: v.nullable(v.string()), solicitante_nombre: v.string(), solicitada_en: v.string(), vence_en: v.string(), resolutor_nombre: v.string(),
  resuelta_en: v.string(), respondida_por_analista_en: v.nullable(v.string()), consumida_en: v.nullable(v.string()), politica_version: v.nullable(v.number()),
})
const PaginaHistorialDecisionesTasaSchema = v.object({ version: v.literal(1), total: v.number(), items: v.array(FilaHistorialDecisionTasaSchema), siguiente_cursor: v.nullable(v.object({ resuelta_en: v.string(), id: v.string() })) })

/** Historial completo de las decisiones tomadas por la Gerencia autenticada, paginado por fecha+UUID. */
export async function listarHistorialDecisionesTasaGerencia(filtros: FiltrosHistorialDecisionesTasa, cursor: CursorHistorialDecisionesTasa | null, signal?: AbortSignal): Promise<PaginaHistorialDecisionesTasa> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('historial_decisiones_tasa_gerencia_fn', {
    p_periodo_dias: filtros.periodoDias, p_limite: TAMANO_PAGINA_HISTORIAL_DECISIONES_TASA,
    ...(filtros.decision !== 'todas' ? { p_decision: filtros.decision } : {}), ...(filtros.busqueda ? { p_busqueda: filtros.busqueda } : {}),
    ...(cursor ? { p_cursor_resuelta_en: cursor.resueltaEn, p_cursor_id: cursor.id } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rentabilidad.historial_decisiones_fallido')
  const r = v.safeParse(PaginaHistorialDecisionesTasaSchema, data)
  if (!r.success) { const fallo = new CrmApiError('El historial de decisiones de tasa no tiene el formato esperado.', 'HISTORIAL_DECISIONES_TASA_CONTRACT'); registrarError('crm.rentabilidad.historial_decisiones_fuera_de_contrato', fallo); throw fallo }
  return {
    total: r.output.total,
    siguienteCursor: r.output.siguiente_cursor ? { resueltaEn: r.output.siguiente_cursor.resuelta_en, id: r.output.siguiente_cursor.id } : null,
    items: r.output.items.map((fila) => ({ ...fila, categoria: fila.categoria as CategoriaContrato, capital: numEstricto(fila.capital, 'capital'), moneda: fila.moneda as MonedaContrato, modalidad: fila.modalidad as ModalidadContrato, tipo_interes: fila.tipo_interes as TipoInteres, tasa_base: numEstricto(fila.tasa_base, 'tasa_base'), tasa_solicitada: numEstricto(fila.tasa_solicitada, 'tasa_solicitada'), tasa_maxima_autorizada: fila.tasa_maxima_autorizada == null ? null : numEstricto(fila.tasa_maxima_autorizada, 'tasa_maxima_autorizada') })),
  }
}

const HistorialTasaClienteSchema = v.object({
  version: v.literal(1),
  cliente_id: v.string(),
  contratos: v.array(v.object({
    contrato_id: v.string(),
    numero_contrato: v.string(),
    estado: v.string(),
    categoria: v.nullable(v.string()),
    tasa_anual: NumericoRpc,
    capital: NumericoRpc,
    moneda: v.string(),
    fecha_inicio: v.string(),
    fecha_vencimiento: v.string(),
    es_demo: v.boolean(),
    observacion: v.nullable(v.object({
      regla: ReglaTasaSchema,
      tasa_base: NumericoRpc,
      tasa_final: NumericoRpc,
      divergente: v.boolean(),
      origen: v.string(),
      motivo: v.nullable(v.string()),
      registrado_en: v.string(),
      base_conservada: v.boolean(),
      contrato_origen_id: v.nullable(v.string()),
      solicitud_id: v.nullable(v.string()),
    })),
  })),
  solicitudes: v.array(SolicitudTasaSchema),
})
export interface ObservacionTasaContrato {
  regla: ReglaTasa
  tasa_base: number
  tasa_final: number
  divergente: boolean
  origen: string
  motivo: string | null
  registrado_en: string
  solicitud_id: string | null
  contrato_origen_id: string | null
}
export interface HistorialTasaCliente {
  cliente_id: string
  /** Por contrato: la última fila del ledger (legacy u observación), o null si no hay. */
  contratos: { contrato_id: string; numero_contrato: string; tasa_anual: number; observacion: ObservacionTasaContrato | null }[]
  solicitudes: SolicitudTasa[]
}

/** Historial de tasa del cliente (ficha): ledger por contrato + solicitudes visibles. */
export async function obtenerHistorialTasaCliente(clienteId: string, signal?: AbortSignal): Promise<HistorialTasaCliente> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('historial_tasa_cliente_fn', { p_cliente_id: clienteId })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rentabilidad.historial_fallido')
  const r = v.safeParse(HistorialTasaClienteSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('El historial de tasa no tiene el formato esperado.', 'HISTORIAL_TASA_CONTRACT')
    registrarError('crm.rentabilidad.historial_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    cliente_id: r.output.cliente_id,
    contratos: r.output.contratos.map((c) => ({
      contrato_id: c.contrato_id,
      numero_contrato: c.numero_contrato,
      tasa_anual: aNumero(c.tasa_anual) ?? 0,
      observacion: c.observacion
        ? {
            regla: c.observacion.regla,
            tasa_base: aNumero(c.observacion.tasa_base) ?? 0,
            tasa_final: aNumero(c.observacion.tasa_final) ?? 0,
            divergente: c.observacion.divergente,
            origen: c.observacion.origen,
            motivo: c.observacion.motivo,
            registrado_en: c.observacion.registrado_en,
            solicitud_id: c.observacion.solicitud_id,
            contrato_origen_id: c.observacion.contrato_origen_id,
          }
        : null,
    })),
    solicitudes: r.output.solicitudes.map(aSolicitudTasa),
  }
}

const PoliticaRentabilidadFilaSchema = v.object({
  id: v.string(),
  version: v.number(),
  vigente_desde: v.string(),
  tasa_base_nueva: NumericoRpc,
  regla_renovacion: v.string(),
  regla_upgrade: v.string(),
  tope_tecnico: NumericoRpc,
  vigencia_solicitud_dias: v.number(),
  modo: v.string(),
  nota: v.nullable(v.string()),
  publicada_en: v.string(),
  publicada_por: v.optional(v.nullable(v.string())),
  publicada_por_nombre: v.optional(v.nullable(v.string())),
  es_vigente: v.optional(v.boolean()),
})
const PoliticaRentabilidadSchema = v.object({
  observacion_sin_aprobacion: v.optional(v.boolean(), false),
  version: v.literal(1),
  vigente: v.nullable(PoliticaRentabilidadFilaSchema),
  expected_version: v.number(),
  historial: v.array(PoliticaRentabilidadFilaSchema),
  observacion_activa_desde: v.nullable(v.string()),
  puede_publicar: v.boolean(),
})
export interface PoliticaRentabilidadFila {
  id: string
  version: number
  vigente_desde: string
  tasa_base_nueva: number
  tope_tecnico: number
  vigencia_solicitud_dias: number
  modo: string
  nota: string | null
  publicada_en: string
  publicada_por_nombre: string | null
  es_vigente: boolean
}
export interface PoliticaRentabilidad {
  observacion_sin_aprobacion?: boolean
  vigente: PoliticaRentabilidadFila | null
  expected_version: number
  historial: PoliticaRentabilidadFila[]
  observacion_activa_desde: string | null
  puede_publicar: boolean
}

function aPoliticaFila(f: v.InferOutput<typeof PoliticaRentabilidadFilaSchema>): PoliticaRentabilidadFila {
  return {
    id: f.id,
    version: f.version,
    vigente_desde: f.vigente_desde,
    tasa_base_nueva: aNumero(f.tasa_base_nueva) ?? 0,
    tope_tecnico: aNumero(f.tope_tecnico) ?? 50,
    vigencia_solicitud_dias: f.vigencia_solicitud_dias,
    modo: f.modo,
    nota: f.nota,
    publicada_en: f.publicada_en,
    publicada_por_nombre: f.publicada_por_nombre ?? null,
    es_vigente: f.es_vigente ?? false,
  }
}

/** La política de rentabilidad vigente, su historial y el control optimista para publicar. */
export async function obtenerPoliticaRentabilidad(signal?: AbortSignal): Promise<PoliticaRentabilidad> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('politica_rentabilidad_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw aErrorApi(error, 'crm.rentabilidad.politica_fallido')
  const r = v.safeParse(PoliticaRentabilidadSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('La política de rentabilidad no tiene el formato esperado.', 'POLITICA_RENTABILIDAD_CONTRACT')
    registrarError('crm.rentabilidad.politica_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    vigente: r.output.vigente ? aPoliticaFila(r.output.vigente) : null,
    observacion_sin_aprobacion: r.output.observacion_sin_aprobacion,
    expected_version: r.output.expected_version,
    historial: r.output.historial.map(aPoliticaFila),
    observacion_activa_desde: r.output.observacion_activa_desde,
    puede_publicar: r.output.puede_publicar,
  }
}

/** Modo de la política de rentabilidad: observación (mide) o enforcement (el servidor rechaza, R4). */
export type ModoPoliticaRentabilidad = 'observacion' | 'enforcement'

export interface PublicacionPoliticaRentabilidad {
  expectedVersion: number
  tasaBaseNueva: number
  topeTecnico: number
  vigenciaSolicitudDias: number
  /** R4: «observacion» mide y no bloquea; «enforcement» es el candado del servidor. */
  modo?: ModoPoliticaRentabilidad
  nota: string | null
}

/** Gerencia publica una revisión de la política (control optimista por versión). El `modo` es el interruptor del candado (R4). */
export async function publicarPoliticaRentabilidad(input: PublicacionPoliticaRentabilidad): Promise<PoliticaRentabilidadFila> {
  const { data, error } = await cliente().schema('crm').rpc('publicar_politica_rentabilidad_fn', {
    p_expected_version: input.expectedVersion,
    p_config: {
      tasa_base_nueva: input.tasaBaseNueva,
      tope_tecnico: input.topeTecnico,
      vigencia_solicitud_dias: input.vigenciaSolicitudDias,
      modo: input.modo ?? 'observacion',
      ...(input.nota ? { nota: input.nota } : {}),
    },
  })
  if (error) throw aErrorApi(error, 'crm.rentabilidad.publicar_fallido')
  const r = v.safeParse(PoliticaRentabilidadFilaSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError('La política publicada no tiene el formato esperado.', 'POLITICA_RENTABILIDAD_CONTRACT')
    registrarError('crm.rentabilidad.publicar_fuera_de_contrato', fallo)
    throw fallo
  }
  return aPoliticaFila(r.output)
}

function fechaLimaIso(desplazamientoDias = 0): string {
  const ahora = new Date()
  const lima = new Date(ahora.getTime() - 5 * 60 * 60 * 1000)   // Lima = UTC-5, sin horario de verano
  lima.setUTCDate(lima.getUTCDate() + desplazamientoDias)
  return lima.toISOString().slice(0, 10)
}

/** Observación de rentabilidad de los últimos `dias` (1..366; el servidor valida el periodo). Solo Gerencia/Directorio. */
export async function listarObservacionRentabilidad(dias = 30, signal?: AbortSignal): Promise<ObservacionRentabilidad> {
  lanzarAbortSiCorresponde(signal)
  const hasta = fechaLimaIso(0)
  const desde = fechaLimaIso(-(Math.max(1, Math.min(366, Math.trunc(dias))) - 1))
  let consulta = cliente().schema('crm').rpc('observacion_rentabilidad_fn', { p_desde: desde, p_hasta: hasta })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.observacion_rentabilidad_fallido')
  const r = v.safeParse(ObservacionRentabilidadSchema, data)
  if (!r.success || r.output.periodo.desde !== desde || r.output.periodo.hasta !== hasta) {
    const fallo = new CrmApiError('La observación de rentabilidad no tiene el formato esperado.', 'OBSERVACION_RENTABILIDAD_CONTRACT')
    registrarError('crm.metricas.observacion_rentabilidad_fuera_de_contrato', fallo)
    throw fallo
  }
  const o = r.output
  const n = (x: number | string | null | undefined): number => aNumero(x ?? null) ?? 0
  return {
    periodo: o.periodo,
    politica: o.politica ? { version: o.politica.version, modo: o.politica.modo, tasa_base_nueva: n(o.politica.tasa_base_nueva) } : null,
    totales: {
      observados: o.totales.contratos ?? o.totales.observados,
      eventos: o.totales.eventos ?? o.totales.observados,
      importe_no_calculable: o.totales.importe_no_calculable ?? 0,
      divergentes: o.totales.divergentes,
      ceden: o.totales.ceden,
      retienen: o.totales.retienen,
      sin_regla: o.totales.sin_regla,
      correcciones: o.totales.correcciones,
      puntos_promedio_cedido: n(o.totales.puntos_promedio_cedido),
      cedido: { PEN: n(o.totales.cedido.PEN), USD: n(o.totales.cedido.USD) },
      retenido: { PEN: n(o.totales.retenido.PEN), USD: n(o.totales.retenido.USD) },
    },
    por_regla: o.por_regla.map((r) => ({ regla: r.regla, observados: r.contratos ?? r.observados ?? 0, divergentes: r.divergentes })),
    por_analista: o.por_analista.map((a) => ({
      analista_id: a.analista_id ?? SIN_ANALISTA_ID,
      analista_nombre: a.analista_nombre,
      observados: a.contratos ?? a.observados ?? 0,
      divergentes: a.divergentes,
      puntos_promedio_cedido: n(a.puntos_promedio_cedido),
      cedido_pen: n(a.cedido_pen),
      cedido_usd: n(a.cedido_usd),
      retenido_pen: n(a.retenido_pen),
      retenido_usd: n(a.retenido_usd),
    })),
    cobertura: o.cobertura ?? null,
    sondas: o.sondas ?? null,
    sin_regla: o.sin_regla,
    ultimos_divergentes: o.ultimos_divergentes.map((u) => ({
      ...u,
      tasa_base: n(u.tasa_base),
      tasa_final: n(u.tasa_final),
      puntos: n(u.puntos),
      capital: u.capital == null ? null : n(u.capital),
      cedido: u.cedido == null ? null : n(u.cedido),
    })),
    metodo: o.metodo,
    altas_sin_observar: o.altas_sin_observar,
    coherente: o.coherente,
  }
}

/** Pagos por mes/moneda/tipo/estado (default: últimos 12 meses). */
export async function listarMetricasPagosMes(pMeses = 12, signal?: AbortSignal): Promise<FilaPagosMes[]> {
  let consulta = cliente().schema('crm').rpc('metricas_pagos_mes_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.pagos_fallido')
  const items: FilaPagosMes[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaPagosRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      moneda: r.output.moneda,
      tipo: r.output.tipo,
      estado: r.output.estado,
      cuotas: aNumero(r.output.cuotas) ?? 0,
      monto_programado: aNumero(r.output.monto_programado) ?? 0,
      monto_pagado: aNumero(r.output.monto_pagado) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('pagos_mes', descartadas)
  return items
}

/** Contratos/capital por vencer por mes/moneda dentro de p_dias (default 90). */
export async function listarMetricasVencimientos(pDias = 90, signal?: AbortSignal): Promise<FilaVencimientos[]> {
  let consulta = cliente().schema('crm').rpc('metricas_vencimientos_fn', { p_dias: pDias })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.vencimientos_fallido')
  const items: FilaVencimientos[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaVencimientosRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      moneda: r.output.moneda,
      contratos_por_vencer: aNumero(r.output.contratos_por_vencer) ?? 0,
      capital_por_vencer: aNumero(r.output.capital_por_vencer) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('vencimientos', descartadas)
  return items
}

// ── Distribución y capacidad por capital (JSON V2 sin SLA embebido) ──────────

const FechaMetricaSchema = v.pipe(v.string(), v.isoDate())

const CapacidadActualizadaSchema = v.strictObject({
  perfil_id: v.pipe(v.string(), v.uuid()),
  capacidad_leads_objetivo: v.nullable(
    v.pipe(
      v.union([v.number(), v.string()]),
      v.transform((valor) => Number(valor)),
      v.number(),
      v.finite(),
      v.integer(),
      v.minValue(1),
      v.maxValue(1000),
    ),
  ),
})

export interface CapacidadLeadsObjetivoActualizada {
  analistaId: string
  capacidad: number | null
}

function periodoMetricasValido(desde: string, hasta: string): boolean {
  return (
    v.safeParse(FechaMetricaSchema, desde).success && v.safeParse(FechaMetricaSchema, hasta).success && desde <= hasta
  )
}

/**
 * Guarda de cancelación. Va SIEMPRE entre el `await consulta` y el `if (error)`
 * de toda lectura que acepte `signal`.
 *
 * Por qué (2026-08-10): al cancelarse un fetch, postgrest-js devuelve `code: ''`
 * y nuestro `error.code || 'POSTGREST_ERROR'` lo convertía en un fallo indistinguible
 * de una caída real, que se reportaba a Sentry. Y TanStack CANCELA de oficio: al
 * desmontarse la última pantalla observadora aborta la petición en vuelo. Resultado:
 * cambiar de pantalla generaba «listado_fallido» sin que nada estuviera roto.
 * Lanzar aquí el AbortError deja que TanStack lo trate como lo que es —una
 * cancelación, no un error— y el evento nunca nace.
 */
function lanzarAbortSiCorresponde(signal?: AbortSignal): void {
  if (!signal?.aborted) return
  throw signal.reason instanceof Error ? signal.reason : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

/**
 * Fotografía atómica V3 (F2.3b/F3 de «Conversión única»): la V2 más la
 * puntería SERVIDA (cerrados÷resueltos por analista, rango y resumen — las
 * divisiones que hasta F3 hacía el navegador), la cifra del NÚCLEO y el
 * bloque `sondas` para la red de F3.4. Mismo cierre hermético que la V2: una
 * sola rama inválida invalida el payload completo. Mudada desde
 * `data/metricas-distribucion-v3.ts` al integrarse las ramas (27/08); mismo
 * contrato, mismos códigos de error.
 */
export async function listarMetricasDistribucionLeadsV3(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasDistribucionLeadsV3> {
  if (!periodoMetricasValido(desde, hasta)) {
    const fallo = new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
    registrarError('crm.metricas.distribucion_v3_periodo_invalido', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_distribucion_leads_v3_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.distribucion_v3_fallido')

  const resultado = v.safeParse(MetricasDistribucionLeadsV3Schema, data)
  if (
    !resultado.success ||
    resultado.output.cohorte.desde_inclusivo !== desde ||
    resultado.output.cohorte.hasta_inclusivo !== hasta
  ) {
    const fallo = new CrmApiError(
      'Las métricas de distribución no tienen el formato esperado.',
      'METRICAS_DISTRIBUCION_CONTRACT',
    )
    registrarError('crm.metricas.distribucion_v3_fuera_de_contrato', fallo)
    throw fallo
  }

  return resultado.output
}

/**
 * Fotografía atómica V1 de la agenda del equipo (crm.metricas_agenda_fn):
 * toques, cierres de reuniones del periodo y foto actual de pendientes por
 * miembro. El ámbito lo recorta el SERVIDOR (supervisor ve su subárbol
 * incluyéndose a sí mismo). Igual que en distribución: una sola rama inválida
 * invalida el payload completo — nunca se mezclan semánticas a medias.
 */
export async function listarMetricasAgenda(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasAgenda> {
  if (!periodoMetricasValido(desde, hasta)) {
    const fallo = new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
    registrarError('crm.metricas.agenda_periodo_invalido', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_agenda_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.agenda_fallido')

  const resultado = v.safeParse(MetricasAgendaSchema, data)
  if (!resultado.success || resultado.output.periodo.desde !== desde || resultado.output.periodo.hasta !== hasta) {
    const fallo = new CrmApiError('Las métricas de agenda no tienen el formato esperado.', 'METRICAS_AGENDA_CONTRACT')
    registrarError('crm.metricas.agenda_fuera_de_contrato', fallo)
    throw fallo
  }

  return resultado.output
}

export async function listarMetricasConversiones(
  desde: string,
  hasta: string,
  origen: string | null = null,
  signal?: AbortSignal,
): Promise<MetricasConversiones> {
  if (!periodoMetricasValido(desde, hasta)) {
    throw new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  // p_origen viaja SOLO cuando hay filtro: un servidor previo a la firma de
  // 3 argumentos seguiria resolviendo la llamada de 2 (PGRST202 evitado).
  let consulta = cliente().schema('crm').rpc('metricas_conversiones_fn', {
    p_desde: desde,
    p_hasta: hasta,
    ...(origen != null ? { p_origen: origen } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.conversiones_fallido')
  const resultado = v.safeParse(MetricasConversionesSchema, data)
  // El schema conserva `origen_filtrado` optional para poder inspeccionar un
  // payload legado de forma aislada; este borde HTTP no puede hacerlo: entregar
  // un lote sin saber si el servidor aplicó el filtro rotularía datos ajenos.
  if (
    !resultado.success
    || resultado.output.periodo.desde !== desde
    || resultado.output.periodo.hasta !== hasta
    || resultado.output.origen_filtrado !== origen
  ) {
    const fallo = new CrmApiError(
      'Las métricas de conversión no tienen el formato esperado.',
      'METRICAS_CONVERSIONES_CONTRACT',
    )
    registrarError('crm.metricas.conversiones_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/** Primer día de un mes: la única forma de periodo que la RPC mensual acepta. */
const PERIODO_MENSUAL_RE = /^\d{4}-\d{2}-01$/

/**
 * La conversión mensual ponderada del analista (crm.conversion_mensual_fn) — LA
 * definición acordada, no las cohortes de la pantalla «Conversiones».
 *
 * MENSUAL POR CONTRATO: `periodo` es el PRIMER DÍA del mes ('2026-08-01') y la
 * pregunta «qué devuelve en un rango libre» es inexpresable. El ámbito lo
 * decide el SERVIDOR (analista→su fila, supervisor→su subárbol, gerencia y
 * lector global→empresa) y viaja en `alcance`; el consumidor declara cuál
 * espera y cualquier eco distinto se rechaza. Los denegados reciben 42501
 * duro, jamás un payload de ceros.
 *
 * La verificación de eco compara `periodo.mes` con el MES pedido — el payload
 * no trae `desde/hasta` en fecha-plana como sus hermanas, trae el mes nombrado
 * (copiar aquí el patrón desde/hasta rechazaría el 100 % de las respuestas).
 */
export async function obtenerConversionMensual(
  periodo: string,
  alcanceEsperado: ConversionMensual['alcance'],
  signal?: AbortSignal,
): Promise<ConversionMensual> {
  if (!PERIODO_MENSUAL_RE.test(periodo) || !v.safeParse(FechaMetricaSchema, periodo).success) {
    const fallo = new CrmApiError('El período de la conversión mensual no es válido.', 'PERIODO_METRICAS_INVALIDO')
    // Con registro (patrón agenda, no el de conversiones): un periodo inválido
    // aquí es un bug del front, no del usuario, y sin evento no se detecta.
    registrarError('crm.metricas.conversion_mensual_periodo_invalido', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('conversion_mensual_fn', {
    p_periodo: periodo,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.conversion_mensual_fallido')

  const resultado = v.safeParse(ConversionMensualSchema, data)
  if (
    !resultado.success
    || resultado.output.periodo.mes !== periodo.slice(0, 7)
    || resultado.output.alcance !== alcanceEsperado
  ) {
    const fallo = new CrmApiError('La conversión mensual no tiene el formato esperado.', 'CONVERSION_MENSUAL_CONTRACT')
    registrarError('crm.metricas.conversion_mensual_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Ranking de conversión del EQUIPO del actor (decisión #10, parte b2).
 *
 * Hermana de `listarMetricasConversiones`, pero con su PROPIO esquema: el de
 * gerencia exige cinco agregados de toda la empresa que esta RPC no calcula a
 * propósito —calcularlos sería la fuga que la función existe para evitar—, así
 * que validar este payload con aquel fallaría siempre.
 *
 * El servidor decide el `alcance`: «equipo» para el supervisor, «global» para
 * gerencia y el lector. La superficie declara el esperado y este adaptador
 * exige el eco exacto antes de entregar el ranking.
 */
export async function listarMetricasConversionesEquipo(
  desde: string,
  hasta: string,
  alcanceEsperado: MetricasConversionesEquipo['alcance'],
  signal?: AbortSignal,
): Promise<MetricasConversionesEquipo> {
  if (!periodoMetricasValido(desde, hasta)) {
    throw new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_conversiones_equipo_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.conversiones_equipo_fallido')
  const resultado = v.safeParse(MetricasConversionesEquipoSchema, data)
  if (
    !resultado.success
    || resultado.output.periodo.desde !== desde
    || resultado.output.periodo.hasta !== hasta
    || resultado.output.alcance !== alcanceEsperado
  ) {
    const fallo = new CrmApiError(
      'El ranking de conversión del equipo no tiene el formato esperado.',
      'METRICAS_CONVERSIONES_EQUIPO_CONTRACT',
    )
    registrarError('crm.metricas.conversiones_equipo_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

export async function listarMetricasReuniones(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasReuniones> {
  if (!periodoMetricasValido(desde, hasta)) {
    throw new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_reuniones_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.reuniones_fallido')
  const resultado = v.safeParse(MetricasReunionesSchema, data)
  if (!resultado.success || resultado.output.periodo.desde !== desde || resultado.output.periodo.hasta !== hasta) {
    const fallo = new CrmApiError(
      'Las métricas de citas no tienen el formato esperado.',
      'METRICAS_REUNIONES_CONTRACT',
    )
    registrarError('crm.metricas.reuniones_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Resumen agregado del ámbito operativo (RPC crm.resumen_cartera_fn, F1):
 * los tiles de Cartera/Pipeline dejan de contar filas en el navegador. El
 * payload jsonb version:1 se valida fail-closed y además se CERTIFICA que la
 * ventana de convertidos del servidor sea la misma que aplica
 * `listarLeadsDelAmbito` — dos cortes distintos en la misma pantalla serían
 * números que no cuadran entre tiles y tabla.
 */
export async function listarResumenCartera(signal?: AbortSignal): Promise<ResumenCartera> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('resumen_cartera_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.resumen_cartera_fallido')
  const resultado = v.safeParse(ResumenCarteraSchema, data)
  if (!resultado.success || resultado.output.ventana_convertidos_dias !== VENTANA_CONVERTIDOS_DIAS) {
    const fallo = new CrmApiError('El resumen de cartera no tiene el formato esperado.', 'RESUMEN_CARTERA_CONTRACT')
    registrarError('crm.metricas.resumen_cartera_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Cola de acción servida (RPC crm.cola_accion_fn, F1b): la cascada de buckets,
 * la severidad, los relojes SLA y el plan vigente/muerto los decide el
 * SERVIDOR; aquí solo se valida el contrato fail-closed. El texto del motivo
 * lo redacta el front desde `datos_motivo` (lib/cola-accion). `resumen.total`
 * viene SIN el recorte de p_limite — es el dato del «+N más en cola».
 */
export async function listarColaAccion(pLimite = LIMITE_COLA_ACCION, signal?: AbortSignal): Promise<ColaAccion> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('cola_accion_fn', { p_limite: pLimite })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.cola_accion_fallido')
  const resultado = v.safeParse(ColaAccionSchema, data)
  if (!resultado.success || resultado.output.p_limite !== pLimite) {
    const fallo = new CrmApiError('La cola de acción no tiene el formato esperado.', 'COLA_ACCION_CONTRACT')
    registrarError('crm.metricas.cola_accion_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Métricas por analista + comparativa de equipos (RPC crm.metricas_vendedores_fn,
 * F1b). El payload viaja SIN nombres (el front une con su roster) y con la
 * ventana de convertidos de 45 días, que se CERTIFICA contra la del front —
 * un ranking y unos tiles con cortes distintos en la misma pantalla serían
 * números que se contradicen.
 */
export async function listarMetricasVendedores(
  periodoEsperado: string,
  signal?: AbortSignal,
): Promise<MetricasVendedoresPayload> {
  if (!PERIODO_MENSUAL_RE.test(periodoEsperado) || !v.safeParse(FechaMetricaSchema, periodoEsperado).success) {
    const fallo = new CrmApiError('El período de las métricas por analista no es válido.', 'PERIODO_METRICAS_INVALIDO')
    registrarError('crm.metricas.vendedores_periodo_invalido', fallo)
    throw fallo
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_vendedores_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.vendedores_fallido')
  const resultado = v.safeParse(MetricasVendedoresSchema, data)
  if (
    !resultado.success
    || resultado.output.ventana_convertidos_dias !== VENTANA_CONVERTIDOS_DIAS
    || resultado.output.ventana_metrica !== 'mes_calendario'
    || resultado.output.mes_metrica !== periodoEsperado
  ) {
    const fallo = new CrmApiError(
      'Las métricas por analista no tienen el formato esperado.',
      'METRICAS_VENDEDORES_CONTRACT',
    )
    registrarError('crm.metricas.vendedores_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

// ── Reportes históricos de derivaciones ──────────────────────────────────────

/**
 * Conversión por analista de TODA la empresa para Coordinación
 * (`crm.conversion_divisor_coordinacion_fn`). El divisor es el del núcleo —una
 * llegada por lead, por su alta original, en el primer analista que la
 * recibió— y NO el reporte de entregas, que a propósito deja de sumar la
 * entrega devuelta a la bandeja. El navegador solo pinta lo que el servidor
 * dice; si las sumas del payload no cierran, se rechaza el paquete entero.
 */
export async function conversionCoordinacion(
  consultaPedida: ConsultaConversion,
  signal?: AbortSignal,
): Promise<ConversionCoordinacion> {
  const fechas = fechasDeConsulta(consultaPedida)
  const motivo = motivoConsultaInvalida(consultaPedida, hoyLima())
  if (!fechas || motivo) {
    throw new CrmApiError(motivo ?? 'El período de conversión no es válido.', 'PERIODO_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  const argumentos = consultaPedida.modo === 'mes'
    ? { p_periodo: fechas.desde }
    : { p_desde: fechas.desde, p_hasta: fechas.hasta }
  let consulta = cliente().schema('crm').rpc('conversion_divisor_coordinacion_fn', argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      error.code === '22023'
        ? 'El período de conversión no es válido.'
        : error.code === '42501' || error.code === 'PGRST301'
          ? 'No tienes permiso para consultar la conversión por analista.'
          : 'No se pudo cargar la conversión por analista.',
      error.code || 'POSTGREST_ERROR',
    )
    registrarError('crm.reparto.conversion_coordinacion_fallida', fallo, { pg: error.code ?? '' })
    throw fallo
  }
  const resultado = v.safeParse(ConversionCoordinacionSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'La conversión por analista no tiene el formato esperado.',
      'CONVERSION_COORDINACION_CONTRACT',
    )
    registrarError('crm.reparto.conversion_coordinacion_fuera_de_contrato', fallo)
    throw fallo
  }
  if (!conversionCoordinacionConsistente(resultado.output, fechas.desde, fechas.hasta)) {
    const fallo = new CrmApiError(
      'La conversión por analista no reconcilia con el núcleo y no se mostrará.',
      'CONVERSION_COORDINACION_INCONSISTENTE',
    )
    registrarError('crm.reparto.conversion_coordinacion_inconsistente', fallo)
    throw fallo
  }
  return resultado.output
}

function falloReporteDerivaciones(
  error: { code?: string | null },
  evento: string,
  porDefecto: string,
  sinPermiso = 'No tienes permiso para gestionar las derivaciones de este equipo.',
): CrmApiError {
  const fallo = new CrmApiError(
    error.code === '22023'
      ? 'El rango de fechas de derivaciones no es válido.'
      : error.code === '42501' || error.code === 'PGRST301'
        ? sinPermiso
        : error.code === 'P0429'
          ? 'El lead está marcado No Insista y no se puede derivar.'
          : porDefecto,
    error.code || 'POSTGREST_ERROR',
  )
  registrarError(evento, fallo, { pg: error.code ?? '' })
  return fallo
}

/**
 * Desglose diario y agregado de las derivaciones que cada supervisor entregó
 * a sus analistas, incluido el origen histórico fotografiado en el ledger.
 * Coordinación recibe solo nombres, equipos, orígenes y conteos; la RPC no
 * expone filas de leads ni datos de contacto.
 */
export async function listarReporteDerivacionesCoordinacion(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<ReporteDerivacionesCoordinacion> {
  if (!v.safeParse(FechaSchema, desde).success || !v.safeParse(FechaSchema, hasta).success) {
    throw new CrmApiError('El rango de fechas de derivaciones no es válido.', 'RANGO_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('reporte_derivaciones_coordinacion_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    throw falloReporteDerivaciones(
      error,
      'crm.reparto.reporte_diario_fallido',
      'No se pudo cargar el reporte diario de derivaciones.',
      'No tienes permiso para consultar el reporte diario de derivaciones.',
    )
  }
  const resultado = v.safeParse(ReporteDerivacionesCoordinacionSchema, data)
  if (
    !resultado.success
    || !reporteDerivacionesCoordinacionConsistente(resultado.output, desde, hasta)
  ) {
    const fallo = new CrmApiError(
      'El reporte diario de derivaciones no tiene el formato esperado.',
      'REPORTE_DERIVACIONES_COORDINACION_CONTRACT',
    )
    registrarError('crm.reparto.reporte_diario_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Conteo diario de los episodios que entraron a responsabilidad del analista
 * autenticado. Solo devuelve fechas y cantidades; ningún dato del lead cruza
 * esta frontera.
 */
export async function listarLeadsRecibidosAnalista(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<LeadsRecibidosAnalista> {
  if (
    !v.safeParse(FechaSchema, desde).success
    || !v.safeParse(FechaSchema, hasta).success
    || desde > hasta
  ) {
    throw new CrmApiError('El rango de leads recibidos no es válido.', 'RANGO_INVALIDO')
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('leads_recibidos_analista_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)

  if (error) {
    const fallo = new CrmApiError(
      error.code === '22023'
        ? 'El rango de leads recibidos no es válido.'
        : error.code === '42501' || error.code === 'PGRST301'
          ? 'No tienes permiso para consultar este conteo.'
          : 'No se pudo cargar el conteo de leads recibidos.',
      error.code || 'POSTGREST_ERROR',
    )
    registrarError('crm.cartera.leads_recibidos_fallido', fallo, { pg: error.code ?? '' })
    throw fallo
  }

  const resultado = v.safeParse(LeadsRecibidosAnalistaSchema, data)
  if (
    !resultado.success
    || !leadsRecibidosAnalistaConsistente(resultado.output, desde, hasta)
  ) {
    const fallo = new CrmApiError(
      'El conteo de leads recibidos no tiene el formato esperado.',
      'LEADS_RECIBIDOS_ANALISTA_CONTRACT',
    )
    registrarError('crm.cartera.leads_recibidos_fuera_de_contrato', fallo)
    throw fallo
  }

  return resultado.output
}

/**
 * Foto histórica de las derivaciones hechas desde la bandeja del supervisor.
 * La API certifica que el servidor devuelve el MISMO periodo pedido: una caché
 * cruzada entre fechas haría que los cards parezcan correctos con capitales de
 * otro día.
 */
export async function listarReporteDerivacionesEquipo(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<ReporteDerivacionesEquipo> {
  if (!v.safeParse(FechaSchema, desde).success || !v.safeParse(FechaSchema, hasta).success) {
    throw new CrmApiError('El rango de fechas de derivaciones no es válido.', 'RANGO_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('reporte_derivaciones_equipo_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    throw falloReporteDerivaciones(
      error,
      'crm.derivaciones.reporte_fallido',
      'No se pudo cargar el reporte de derivaciones.',
    )
  }
  const resultado = v.safeParse(ReporteDerivacionesEquipoSchema, data)
  if (!resultado.success || resultado.output.periodo.desde !== desde || resultado.output.periodo.hasta !== hasta) {
    const fallo = new CrmApiError(
      'El reporte de derivaciones no tiene el formato esperado.',
      'REPORTE_DERIVACIONES_CONTRACT',
    )
    registrarError('crm.derivaciones.reporte_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

export interface DerivacionEquipoPendiente {
  leadId: string
  asesorId: string
}

/** Guarda el borrador completo; el servidor valida y aplica todo o nada. */
export async function derivarLeadsEquipo(
  derivaciones: readonly DerivacionEquipoPendiente[],
): Promise<ResultadoDerivarLeadsEquipo> {
  if (
    derivaciones.length < 1 ||
    derivaciones.length > 100 ||
    derivaciones.some(
      (d) => !v.safeParse(UuidSchema, d.leadId).success || !v.safeParse(UuidSchema, d.asesorId).success,
    ) ||
    new Set(derivaciones.map((d) => d.leadId)).size !== derivaciones.length
  ) {
    throw new CrmApiError('El borrador de derivaciones no es válido.', 'BORRADOR_DERIVACIONES_INVALIDO')
  }

  const { data, error } = await cliente()
    .schema('crm')
    .rpc('derivar_leads_equipo_fn', {
      p_lead_ids: derivaciones.map((d) => d.leadId),
      p_asesor_ids: derivaciones.map((d) => d.asesorId),
    })
  if (error) {
    throw falloReporteDerivaciones(
      error,
      'crm.derivaciones.guardar_fallido',
      'No se pudieron guardar las derivaciones. Revisa si algún lead cambió de estado.',
    )
  }
  const resultado = v.safeParse(ResultadoDerivarLeadsEquipoSchema, data)
  if (!resultado.success || resultado.output.derivados !== derivaciones.length) {
    const fallo = new CrmApiError(
      'La confirmación de las derivaciones no tiene el formato esperado.',
      'DERIVACIONES_GUARDAR_CONTRACT',
    )
    registrarError('crm.derivaciones.guardar_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Devuelve a la bandeja propia una derivación de hoy sin actividad posterior.
 * El servidor conserva el episodio cerrado y la actividad de reasignación.
 */
export async function revertirDerivacionEquipo(leadId: string): Promise<ResultadoRevertirDerivacionEquipo> {
  if (!v.safeParse(UuidSchema, leadId).success) {
    throw new CrmApiError('El lead que deseas devolver no es válido.', 'LEAD_INVALIDO')
  }
  const { data, error } = await cliente().schema('crm').rpc('revertir_derivacion_equipo_fn', {
    p_lead_id: leadId,
  })
  if (error) {
    throw falloReporteDerivaciones(
      error,
      'crm.derivaciones.revertir_fallido',
      'No se pudo devolver el lead. Puede que ya haya sido gestionado o cambiado de estado.',
    )
  }
  const resultado = v.safeParse(ResultadoRevertirDerivacionEquipoSchema, data)
  if (!resultado.success || resultado.output.lead_id !== leadId) {
    const fallo = new CrmApiError(
      'La confirmación de la devolución no tiene el formato esperado.',
      'DERIVACIONES_REVERTIR_CONTRACT',
    )
    registrarError('crm.derivaciones.revertir_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Resumen agregado de la cola GLOBAL de reparto (RPC crm.resumen_reparto_fn,
 * F1b tanda 3): el total, el capital por moneda, la espera máxima y los
 * marcados los cuenta el SERVIDOR con el MISMO predicado que
 * `leads_por_repartir`. No hay ventana ni argumento que certificar contra el
 * front (la función no recibe parámetros): el cinturón del contrato es el
 * `version: 1` del schema. El gate de rol vive en el servidor — coordinador o
 * gerencia; para el resto la RPC responde 42501 y la pantalla degrada.
 */
export async function listarResumenReparto(signal?: AbortSignal): Promise<ResumenReparto> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('resumen_reparto_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.reparto.resumen_fallido')
  const resultado = v.safeParse(ResumenRepartoSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError('El resumen de la cola no tiene el formato esperado.', 'RESUMEN_REPARTO_CONTRACT')
    registrarError('crm.reparto.resumen_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/** Gerencia fija o limpia la capacidad objetivo de un analista activo. */
export async function actualizarCapacidadLeadsObjetivo(
  analistaId: string,
  capacidad: number | null,
): Promise<CapacidadLeadsObjetivoActualizada> {
  const idValido = v.safeParse(v.pipe(v.string(), v.uuid()), analistaId).success
  const capacidadValida = capacidad == null || (Number.isInteger(capacidad) && capacidad >= 1 && capacidad <= 1000)
  if (!idValido || !capacidadValida) {
    throw new CrmApiError(
      'La capacidad debe estar entre 1 y 1000 leads, o quedar sin configurar.',
      'CAPACIDAD_INVALIDA',
    )
  }

  const { data, error } = await cliente()
    .schema('crm')
    .rpc('actualizar_capacidad_leads_objetivo', {
      p_analista_id: analistaId,
      // SIN default: el null explícito ES el mensaje («quedar sin configurar»).
      p_capacidad_leads_objetivo: nuloExplicito(capacidad),
    })

  if (error) {
    let fallo: CrmApiError
    if (error.code === '22023') {
      fallo = new CrmApiError(
        'La capacidad debe estar entre 1 y 1000 leads, o quedar sin configurar.',
        'CAPACIDAD_INVALIDA',
      )
    } else if (error.code === 'P0002') {
      fallo = new CrmApiError('Analista activo no encontrado.', 'ANALISTA_NO_ENCONTRADO')
    } else if (error.code === '42501' || error.code === 'PGRST301') {
      fallo = new CrmApiError('No tienes permiso para configurar capacidades.', 'SIN_PERMISO')
    } else {
      fallo = new CrmApiError('No se pudo actualizar la capacidad del analista.', error.code || 'POSTGREST_ERROR')
    }
    registrarError('crm.equipo.capacidad_actualizar_fallido', fallo, {
      pg: error.code ?? '',
    })
    throw fallo
  }

  const respuesta = v.safeParse(v.strictTuple([CapacidadActualizadaSchema]), data)
  if (
    !respuesta.success ||
    respuesta.output[0].perfil_id !== analistaId ||
    respuesta.output[0].capacidad_leads_objetivo !== capacidad
  ) {
    const fallo = new CrmApiError('La capacidad actualizada no tiene el formato esperado.', 'CAPACIDAD_CONTRACT')
    registrarError('crm.equipo.capacidad_fuera_de_contrato', fallo)
    throw fallo
  }

  return {
    analistaId: respuesta.output[0].perfil_id,
    capacidad: respuesta.output[0].capacidad_leads_objetivo,
  }
}

// ─── Cierres externos en cooperativas (Qorilazo / Prodelco) ──────────────────
// Migración 20260812000259: el lead invirtió en una COOPERATIVA. No hay portal,
// no hay correo, no hay contrato — hay una foto inmutable y el lead queda
// convertido por el MISMO cierre de episodio que un cierre Avance.

/** Respuesta de crm.convertir_lead_externo — eco verificado contra lo pedido. */
const CierreExternoCreadoSchema = v.object({
  ok: v.literal(true),
  lead_id: v.pipe(v.string(), v.uuid()),
  cierre_id: v.pipe(v.string(), v.uuid()),
  cooperativa: v.picklist(COOPERATIVAS),
})

export interface ConvertirLeadExternoDatos {
  leadId: string
  cooperativa: Cooperativa
  monto: number
  /** PEN o USD, según lo que admita ESA cooperativa (`crm.empresas.monedas`:
   * Prodelco las dos desde el 17/09/2026, Qorilazo solo soles). Viaja siempre
   * porque el servidor la valida contra su catálogo: una moneda que la
   * cooperativa no admite merece un rechazo claro, no que se la cambien por
   * debajo. */
  moneda: Moneda
  documentoTipo: TipoDocumento
  documento: string
  nombre: string
  /** N.º de operación del depósito: OBLIGATORIO y único por cooperativa. */
  numeroTransaccion: string
  /** Certificado de la coop: opcional, para papeleo. */
  referencia?: string | null
  /** 'YYYY-MM-DD'; el servidor exige fecha futura. */
  venceEn?: string | null
  plazoMeses?: number
  tasaAnual?: number
  nota?: string | null
}

export interface CierreExternoCreado {
  leadId: string
  cierreId: string
  cooperativa: Cooperativa
}

/**
 * Convierte un lead cerrándolo en una COOPERATIVA. La validación de aquí es la
 * del formulario (espejo de la RPC): que un payload inválido muera con mensaje
 * de negocio ANTES de viajar. El servidor revalida todo — esto no es la
 * frontera de seguridad, es la UX del error.
 */
export async function convertirLeadExterno(datos: ConvertirLeadExternoDatos): Promise<CierreExternoCreado> {
  const documento = datos.documento.trim().toUpperCase()
  const nombre = datos.nombre.trim()
  const numeroTransaccion = datos.numeroTransaccion.trim()
  // ⚠️ La igualdad EXACTA no sirve para decidir la escala de un decimal: en
  // coma flotante `10000.03 * 100` da 1000003.0000000001, así que el formulario
  // acusaba tres decimales a un monto perfectamente válido. Se compara con una
  // tolerancia mucho menor que un céntimo: 10000.035 sigue cayendo.
  const montoValido =
    Number.isFinite(datos.monto) &&
    datos.monto > 0 &&
    Math.abs(Math.round(datos.monto * 100) - datos.monto * 100) < 1e-6
  if (!montoValido) {
    throw new CrmApiError(
      'El monto invertido debe ser mayor que cero, con máximo 2 decimales.',
      'CIERRE_EXTERNO_MONTO_INVALIDO',
    )
  }
  if (numeroTransaccion === '') {
    throw new CrmApiError('El número de operación del depósito es obligatorio.', 'CIERRE_EXTERNO_TRANSACCION_INVALIDA')
  }
  if (!TIPOS_DOCUMENTO[datos.documentoTipo].regex.test(documento)) {
    throw new CrmApiError(TIPOS_DOCUMENTO[datos.documentoTipo].error, 'CIERRE_EXTERNO_DOCUMENTO_INVALIDO')
  }
  if (nombre === '') {
    throw new CrmApiError('El nombre completo es obligatorio.', 'CIERRE_EXTERNO_NOMBRE_INVALIDO')
  }

  const { data, error } = await cliente()
    .schema('crm')
    .rpc(
      'convertir_lead_externo',
      sinIndefinidos({
        p_lead_id: datos.leadId,
        p_cooperativa: datos.cooperativa,
        p_monto: datos.monto,
        p_moneda: datos.moneda,
        p_documento_tipo: datos.documentoTipo,
        p_documento: documento,
        p_nombre: nombre,
        p_numero_transaccion: numeroTransaccion,
        p_referencia: datos.referencia?.trim() || undefined,
        p_vence_en: datos.venceEn ?? undefined,
        p_plazo_meses: datos.plazoMeses,
        p_tasa_anual: datos.tasaAnual,
        p_nota: datos.nota?.trim() || undefined,
      }),
    )

  if (error) {
    let fallo: CrmApiError
    if (error.code === '42501' || error.code === 'PGRST301') {
      fallo = new CrmApiError('No tienes permiso para convertir leads.', 'SIN_PERMISO')
    } else if (error.code === '22023') {
      // El servidor ya habla el idioma del formulario (monto, moneda, documento,
      // vencimiento, «asigna el lead»): su mensaje ES el mensaje.
      fallo = new CrmApiError(error.message, 'CIERRE_EXTERNO_INVALIDO')
    } else if (error.code === 'P0409') {
      // Depósito ya registrado, o una conversión Avance en vuelo sobre el mismo
      // lead. Los dos mensajes del servidor ya están en idioma de negocio y
      // ninguno se puede reformular mejor desde aquí: dicen QUÉ pasó y QUÉ hacer.
      fallo = new CrmApiError(error.message, 'CIERRE_EXTERNO_CONFLICTO')
    } else if (/ya esta cerrado/i.test(error.message ?? '')) {
      fallo = new CrmApiError('El lead ya está cerrado.', 'LEAD_YA_CERRADO')
    } else if (/fuera de tu ambito/i.test(error.message ?? '')) {
      fallo = new CrmApiError('El lead no existe o está fuera de tu ámbito.', 'LEAD_FUERA_DE_AMBITO')
    } else {
      fallo = new CrmApiError('No se pudo registrar el cierre en la cooperativa.', error.code || 'POSTGREST_ERROR')
    }
    registrarError('crm.cierres_externos.convertir_fallido', fallo, {
      pg: error.code ?? '',
    })
    throw fallo
  }

  const respuesta = v.safeParse(CierreExternoCreadoSchema, data)
  if (
    !respuesta.success ||
    respuesta.output.lead_id !== datos.leadId ||
    respuesta.output.cooperativa !== datos.cooperativa
  ) {
    const fallo = new CrmApiError(
      'La respuesta del cierre externo no tiene el formato esperado.',
      'CIERRE_EXTERNO_CONTRACT',
    )
    registrarError('crm.cierres_externos.convertir_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    leadId: respuesta.output.lead_id,
    cierreId: respuesta.output.cierre_id,
    cooperativa: respuesta.output.cooperativa,
  }
}

export interface CorregirCierreExternoDatos {
  cierreId: string
  monto: number
  /** PEN o USD, según lo que admita ESA cooperativa (`crm.empresas.monedas`).
   * ⚠️ El formulario que use esto DEBE mandar la moneda ACTUAL del cierre: el
   * servidor acepta la que la cooperativa admita, así que fijar un literal aquí
   * convertiría un cierre en dólares en soles por el mismo importe. */
  moneda: Moneda
  cooperativa: Cooperativa
  /** El n.º de operación se corrige AQUÍ y solo aquí: es la prueba del cierre y
   * quien cobra no reescribe su propia prueba (decisión de Miguel 2026-08-12). */
  numeroTransaccion: string
  /** null LIMPIA el campo — el formulario manda el estado completo. */
  referencia: string | null
  venceEn: string | null
  nota: string | null
}

/** Corrección de gerencia sobre un cierre externo. La identidad del cierre
 * (documento, nombre, quién cobró) es inmutable y NO viaja. */
export async function corregirCierreExterno(datos: CorregirCierreExternoDatos): Promise<{ cierreId: string }> {
  const numeroTransaccion = datos.numeroTransaccion.trim()
  if (numeroTransaccion === '') {
    throw new CrmApiError('El número de operación del depósito es obligatorio.', 'CIERRE_EXTERNO_TRANSACCION_INVALIDA')
  }

  const { data, error } = await cliente()
    .schema('crm')
    .rpc('corregir_cierre_externo', {
      p_cierre_id: datos.cierreId,
      p_monto: datos.monto,
      p_moneda: datos.moneda,
      p_cooperativa: datos.cooperativa,
      p_numero_transaccion: numeroTransaccion,
      // SIN default en el catálogo: la clave es obligatoria y el null explícito
      // significa «limpiar el campo» — debe seguir viajando tal cual.
      p_referencia: nuloExplicito(datos.referencia?.trim() || null),
      p_vence_en: nuloExplicito(datos.venceEn),
      p_nota: nuloExplicito(datos.nota?.trim() || null),
    })

  if (error) {
    let fallo: CrmApiError
    if (error.code === '42501' || error.code === 'PGRST301') {
      fallo = new CrmApiError('Solo gerencia corrige cierres externos.', 'SIN_PERMISO')
    } else if (error.code === '22023') {
      fallo = new CrmApiError(error.message, 'CIERRE_EXTERNO_INVALIDO')
    } else if (error.code === 'P0409') {
      // Depósito repetido, o el cierre ya está anulado (y un anulado no se
      // corrige: no cuenta). El servidor ya lo dice en idioma de negocio.
      fallo = new CrmApiError(error.message, 'CIERRE_EXTERNO_CONFLICTO')
    } else {
      fallo = new CrmApiError('No se pudo corregir el cierre externo.', error.code || 'POSTGREST_ERROR')
    }
    registrarError('crm.cierres_externos.corregir_fallido', fallo, {
      pg: error.code ?? '',
    })
    throw fallo
  }

  const respuesta = v.safeParse(v.object({ ok: v.literal(true), cierre_id: v.pipe(v.string(), v.uuid()) }), data)
  if (!respuesta.success || respuesta.output.cierre_id !== datos.cierreId) {
    const fallo = new CrmApiError(
      'La corrección del cierre externo no tiene el formato esperado.',
      'CIERRE_EXTERNO_CONTRACT',
    )
    registrarError('crm.cierres_externos.corregir_fuera_de_contrato', fallo)
    throw fallo
  }
  return { cierreId: respuesta.output.cierre_id }
}

export interface AnularCierreExternoDatos {
  cierreId: string
  motivo: string
}

/**
 * El freno de emergencia de gerencia contra un cierre falso o mal digitado: el
 * cierre deja de contar en la cuota Y en la conversión del analista.
 *
 * NO borra la fila ni reabre el lead —en el CRM un convertido es terminal por
 * diseño— y es de UNA SOLA DIRECCIÓN: no se des-anula. Por eso el motivo es
 * obligatorio aquí y en el servidor: esto le quita dinero a una persona.
 */
export async function anularCierreExterno(datos: AnularCierreExternoDatos): Promise<{ cierreId: string }> {
  const motivo = datos.motivo.trim()
  if (motivo === '') {
    throw new CrmApiError('Escribe el motivo de la anulación.', 'CIERRE_EXTERNO_MOTIVO_REQUERIDO')
  }

  const { data, error } = await cliente().schema('crm').rpc('anular_cierre_externo', {
    p_cierre_id: datos.cierreId,
    p_motivo: motivo,
  })

  if (error) {
    let fallo: CrmApiError
    if (error.code === '42501' || error.code === 'PGRST301') {
      fallo = new CrmApiError('Solo gerencia anula cierres externos.', 'SIN_PERMISO')
    } else if (error.code === '22023' || error.code === 'P0409') {
      // «Escribe el motivo», «Ese cierre ya estaba anulado»: mensajes de negocio.
      fallo = new CrmApiError(error.message, 'CIERRE_EXTERNO_INVALIDO')
    } else {
      fallo = new CrmApiError('No se pudo anular el cierre externo.', error.code || 'POSTGREST_ERROR')
    }
    registrarError('crm.cierres_externos.anular_fallido', fallo, {
      pg: error.code ?? '',
    })
    throw fallo
  }

  const respuesta = v.safeParse(
    v.object({
      ok: v.literal(true),
      cierre_id: v.pipe(v.string(), v.uuid()),
      lead_id: v.pipe(v.string(), v.uuid()),
    }),
    data,
  )
  if (!respuesta.success || respuesta.output.cierre_id !== datos.cierreId) {
    const fallo = new CrmApiError(
      'La anulación del cierre externo no tiene el formato esperado.',
      'CIERRE_EXTERNO_CONTRACT',
    )
    registrarError('crm.cierres_externos.anular_fuera_de_contrato', fallo)
    throw fallo
  }
  return { cierreId: respuesta.output.cierre_id }
}

export interface AnularCierreAvanceDatos {
  leadId: string
  motivo: string
}

export interface CierreAvanceAnulado {
  leadId: string
  /** Los contratos que dejan de acreditarle al analista. Puede venir VACÍO y
   *  seguir siendo correcto: la conversión baja igual (sale del ledger), pero
   *  no había contrato que descontar. */
  contratosAfectados: string[]
  afectaCuota: boolean
}

/**
 * El freno de gerencia contra un cierre de AVANCE por error de gestión o mala
 * práctica: ese cierre deja de acreditarle al analista en la cuota Y en la
 * conversión.
 *
 * Va por LEAD y no por cierre porque en Avance no hay fila de cierre — el cierre
 * ES el lead convertido, y su capital vive en `public.contratos`.
 *
 * NO mueve dinero real: el contrato y el cliente siguen intactos. NO reabre el
 * lead (un convertido es terminal por diseño) y es de UNA SOLA DIRECCIÓN.
 */
export async function anularCierreAvance(datos: AnularCierreAvanceDatos): Promise<CierreAvanceAnulado> {
  const motivo = datos.motivo.trim()
  if (motivo === '') {
    throw new CrmApiError('Escribe el motivo de la anulación.', 'CIERRE_AVANCE_MOTIVO_REQUERIDO')
  }

  const { data, error } = await cliente().schema('crm').rpc('anular_cierre_avance', {
    p_lead_id: datos.leadId,
    p_motivo: motivo,
  })

  if (error) {
    let fallo: CrmApiError
    if (error.code === '42501' || error.code === 'PGRST301') {
      fallo = new CrmApiError('Solo gerencia anula cierres.', 'SIN_PERMISO')
    } else if (error.code === '22023' || error.code === 'P0409') {
      // Mensajes de negocio que el servidor ya redacta bien y conviene NO
      // traducir: «Ese lead cerró en cooperativa: usa crm.anular_cierre_externo»,
      // «Ese cierre ya estaba anulado», «Ese lead no tiene ningún cierre que
      // anular». Reescribirlos aquí los dejaría desincronizados del servidor.
      fallo = new CrmApiError(error.message, 'CIERRE_AVANCE_INVALIDO')
    } else {
      fallo = new CrmApiError('No se pudo anular el cierre.', error.code || 'POSTGREST_ERROR')
    }
    registrarError('crm.cierres_avance.anular_fallido', fallo, {
      pg: error.code ?? '',
    })
    throw fallo
  }

  const respuesta = v.safeParse(
    v.object({
      ok: v.literal(true),
      lead_id: v.pipe(v.string(), v.uuid()),
      contratos_afectados: v.array(v.pipe(v.string(), v.uuid())),
      afecta_cuota: v.boolean(),
    }),
    data,
  )
  if (!respuesta.success || respuesta.output.lead_id !== datos.leadId) {
    const fallo = new CrmApiError('La anulación del cierre no tiene el formato esperado.', 'CIERRE_AVANCE_CONTRACT')
    registrarError('crm.cierres_avance.anular_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    leadId: respuesta.output.lead_id,
    contratosAfectados: respuesta.output.contratos_afectados,
    afectaCuota: respuesta.output.afecta_cuota,
  }
}

/** Crédito temporal leído de la puerta autorizada, separado del estado de cierre. */
export async function obtenerConversionEstado(leadId: string, signal?: AbortSignal): Promise<ConversionEstado> {
  if (!v.safeParse(UuidSchema, leadId).success) {
    throw new CrmApiError('El identificador del lead no es válido.', 'CONVERSION_LEAD_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('conversion_estado_lead_v1', { p_lead_id: leadId })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.conversion_estado.consulta_fallida')
  const resultado = v.safeParse(ConversionEstadoSchema, data)
  if (!resultado.success || resultado.output.lead_id !== leadId) {
    const fallo = new CrmApiError('No se pudo verificar el estado de conversión.', 'CONVERSION_ESTADO_CONTRACT')
    registrarError('crm.conversion_estado.fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Estado del cierre (`crm.cierres_estado_fn`): canal y anulación. Su tabla es
 * deny-by-default. Devuelve solo leads con algo que decir; la ausencia significa
 * «Avance no anulado», no ausencia de inversión (ver `estadoDelCierre`).
 */
export async function obtenerCierresEstado(leadIds: readonly string[], signal?: AbortSignal): Promise<CierreEstado[]> {
  // Sin ids no hay pregunta: se ahorra un viaje por cada pantalla que todavía
  // no ha cargado sus filas.
  if (leadIds.length === 0) return []

  // El servidor topa cada llamada en 200 (sirve a una página, no a un volcado),
  // y la cartera ACUMULA páginas: con «cargar más» se pasa de 200 sin esfuerzo.
  // Se parte en lotes en vez de recortar porque recortar sería una mentira
  // silenciosa: la fila 201 se pintaría como cierre vigente sin serlo, y nadie
  // tendría forma de notarlo.
  if (leadIds.length > MAX_LEADS_ESTADO) {
    const lotes: string[][] = []
    for (let i = 0; i < leadIds.length; i += MAX_LEADS_ESTADO) {
      lotes.push(leadIds.slice(i, i + MAX_LEADS_ESTADO) as string[])
    }
    const respuestas = await Promise.all(lotes.map((lote) => obtenerCierresEstado(lote, signal)))
    return respuestas.flat()
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente()
    .schema('crm')
    .rpc('cierres_estado_fn', {
      p_lead_ids: leadIds as string[],
    })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.cierres_estado.consulta_fallida')

  const resultado = v.safeParse(CierresEstadoSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError('El estado de los cierres no tiene el formato esperado.', 'CIERRE_ESTADO_CONTRACT')
    registrarError('crm.cierres_estado.fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * La fotografía de cierres externos (crm.cierres_externos_fn): filas para la
 * sección «En cooperativas» de Mi cartera (histórico del ámbito, tope 200),
 * mini-totales por cooperativa×moneda, el desglose «Por empresa» del mes y las
 * filas DEL MES para la revisión de supervisor y gerencia.
 * MENSUAL POR CONTRATO, como la conversión: `periodo` es el primer día del mes.
 */
export async function obtenerCierresExternos(periodo: string, signal?: AbortSignal): Promise<CierresExternos> {
  if (!PERIODO_MENSUAL_RE.test(periodo)) {
    const fallo = new CrmApiError('El período de los cierres externos no es válido.', 'PERIODO_METRICAS_INVALIDO')
    registrarError('crm.cierres_externos.periodo_invalido', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('cierres_externos_fn', {
    p_periodo: periodo,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.cierres_externos.consulta_fallida')

  const resultado = v.safeParse(CierresExternosSchema, data)
  if (!resultado.success || resultado.output.periodo !== periodo) {
    const fallo = new CrmApiError('Los cierres externos no tienen el formato esperado.', 'CIERRES_EXTERNOS_CONTRACT')
    registrarError('crm.cierres_externos.fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}
