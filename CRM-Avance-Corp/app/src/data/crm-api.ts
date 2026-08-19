import * as v from 'valibot'
import { sb, type ClienteCrm } from '@/lib/supabase'
import type { Database, Json } from '@/lib/database.types'
import { idCorrelacion, registrarError } from '@/lib/observabilidad'
import {
  CATEGORIAS_INTERES,
  ESTADOS_TAREA,
  ETAPAS,
  GENEROS,
  MODALIDADES_REUNION_TODAS,
  MOTIVOS_DESCARTE,
  MOTIVOS_NO_REALIZADA_TODOS,
  ORIGENES_TODOS,
  RESULTADOS_REUNION_TODOS,
  TERMINALES,
  TIPOS_ACTIVIDAD,
  TIPOS_TAREA,
  type Actividad,
  type AgendaRepartoDiaria,
  type AsignacionAgendaReparto,
  type CategoriaInteres,
  type ColaLead,
  type DestinoAgendaReparto,
  type DiaAgendaReparto,
  type DistribucionAnalista,
  type DistribucionSupervisor,
  type HistorialDerivacion,
  type Etapa,
  type Lead,
  type LeadDescartado,
  type Miembro,
  type MotivoDescarte,
  type Origen,
  type PanelDistribucionReparto,
  type SupervisorReparto,
  type Tarea,
  type TipoActividad,
  type ModalidadReunion,
  type MotivoNoRealizada,
  type ResultadoReunion,
  type RespuestaReprogramarReunion,
} from '@/lib/tipos'
import type {
  CategoriaContrato,
  CuotaCronograma,
  ModalidadContrato,
  TipoInteres,
} from '@/lib/cronograma'
import {
  ESTADOS_CONTRATO,
  ESTADOS_CUOTA,
  type ClienteBasico,
  type ClienteDetalle,
  type ContratoRow,
  type CuentaBancariaSeleccionable,
  type CuentaPagoContratoInput,
  type Cuota,
  type Titular,
  type TitularInput,
} from '@/lib/clientes-tipos'
import {
  TAMANO_PAGINA_CARTERA,
  normalizarBusquedaCartera,
  textoBuscable,
} from '@/lib/cartera-keyset'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import {
  CierresExternosSchema,
  COOPERATIVAS,
  type CierresExternos,
  type Cooperativa,
} from '@/lib/cierres-externos'
import {
  CierresEstadoSchema,
  MAX_LEADS_ESTADO,
  type CierreEstado,
} from '@/lib/cierre-estado'
import type { SeccionBancariaForm } from '@/lib/cliente-form-logica'
import type {
  FilaAltasAnalista,
  FilaCapitalMes,
  FilaPagosMes,
  FilaVencimientos,
} from '@/lib/metricas'
import {
  MetricasDistribucionLeadsSchema,
  type MetricasDistribucionLeads,
} from '@/lib/metricas-distribucion'
import {
  MetricasAgendaSchema,
  type MetricasAgenda,
} from '@/lib/metricas-agenda'
import {
  MetricasConversionesSchema,
  type MetricasConversiones,
} from '@/lib/metricas-conversiones'
import {
  MetricasConversionesEquipoSchema,
  type MetricasConversionesEquipo,
} from '@/lib/metricas-conversiones-equipo'
import {
  ConversionMensualSchema,
  type ConversionMensual,
} from '@/lib/conversion-mensual'
import {
  MetricasReunionesSchema,
  type MetricasReuniones,
} from '@/lib/metricas-reuniones'
import { ConfiguracionMetasSchema, type ConfiguracionMetas } from '@/lib/metas-versionadas'
import { CierreMesEstadoSchema, type CierreMesEstadoRpc } from '@/lib/cierre-de-mes'
import {
  CumplimientoMetasSchema,
  type CumplimientoMetasRpc,
} from '@/lib/objetivos'
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
  ResumenCarteraSchema,
  VENTANA_CONVERTIDOS_MS,
  VENTANA_CONVERTIDOS_DIAS,
  type ResumenCartera,
} from '@/lib/resumen-cartera'
import {
  ColaAccionSchema,
  LIMITE_COLA_ACCION,
  type ColaAccion,
} from '@/lib/cola-accion'
import {
  MetricasVendedoresSchema,
  type MetricasVendedoresPayload,
} from '@/lib/metricas-vendedores'
import type { EstadoContratoPdf } from '@/lib/contrato-pdf-archivo'
import {
  ResumenRepartoSchema,
  type ResumenReparto,
} from '@/lib/resumen-reparto'
import {
  IngresosRepartoMesSchema,
  inicioDeMes,
  type IngresosRepartoMes,
} from '@/lib/ingresos-reparto'
import {
  InicioAyudaVendedorSchema,
  ResultadoConsultaAyudaVendedorSchema,
  type InicioAyudaVendedor,
  type ResultadoConsultaAyudaVendedor,
} from '@/lib/ayuda-vendedor'
import type { Vista } from '@/lib/router'

export type { DisponibilidadLead, ResultadoCreacionLeadAtomica, ResultadoTomaLead } from '@/lib/disponibilidad-lead'
export type { RecordatorioDisponibilidad } from '@/lib/recordatorios-disponibilidad'

export const TAMANO_PAGINA_LEADS = 50
const MAX_TAMANO_PAGINA = 100

const COLUMNAS_LEAD = [
  'id',
  'nombre_completo',
  'telefono',
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
  return e instanceof CrmApiError ? e.message : porDefecto
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
  return Object.fromEntries(
    Object.entries(args).filter(([, valor]) => valor !== undefined),
  ) as { [K in keyof T]: Exclude<T[K], undefined> }
}

function cliente(): ClienteCrm {
  if (!sb) {
    const error = new CrmApiError('Supabase no está configurado.', 'SUPABASE_NOT_CONFIGURED')
    registrarError('crm.cliente_no_disponible', error)
    throw error
  }
  return sb
}

// ── Centro de ayuda del vendedor — contenido y decisión solo en servidor ────

function falloContratoAyuda(evento: string): CrmApiError {
  const fallo = new CrmApiError(
    'El servidor devolvió una respuesta de ayuda no reconocida.',
    'ROW_CONTRACT',
  )
  registrarError(evento, fallo)
  return fallo
}

/** Preguntas publicadas y ordenadas por la pantalla actual. */
export async function obtenerInicioAyudaVendedor(
  vista: Vista,
  signal?: AbortSignal,
): Promise<InicioAyudaVendedor> {
  let peticion = cliente().schema('crm').rpc('ayuda_vendedor_inicio', {
    p_vista: vista,
  })
  if (signal) peticion = peticion.abortSignal(signal)
  const { data, error } = await peticion
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      'No se pudieron cargar las consultas frecuentes.',
      error.code || 'POSTGREST_ERROR',
    )
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
    throw new CrmApiError(
      'Escribe una consulta de 2 a 240 caracteres.',
      'AYUDA_CONSULTA_INVALIDA',
    )
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

function aLead(fila: LeadRow): Lead {
  return {
    id: fila.id,
    nombre_completo: fila.nombre_completo,
    telefono: fila.telefono,
    correo: fila.correo,
    dni: fila.dni,
    genero: fila.genero ?? null,
    fecha_nacimiento: fila.fecha_nacimiento ?? null,
    distrito: fila.distrito,
    origen: fila.origen, // ya validado contra el catálogo por LeadRowSchema
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
    // la meta del asesor y las series de tendencia de gerencia, que sin él caen
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
export async function listarLeads(
  filtros: FiltrosLeads,
  signal?: AbortSignal,
): Promise<Pagina<Lead>> {
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
    registrarError('crm.leads.filas_invalidas', new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'), {
      descartadas,
      pagina,
    })
  }

  const total = count ?? 0
  return {
    items,
    pagina,
    tamano,
    total,
    paginas: Math.ceil(total / tamano),
  }
}

// ── Ámbito completo para el store (lectura NO paginada) ───────────────────────
// El store necesita TODA la cartera del ámbito para los cálculos agregados
// (métricas, embudo, colas). La RLS ya recorta a lo visible; el tope alto es una
// salvaguarda de payload, no seguridad. Con volumen bajo (piloto) sobra.
const MAX_LEADS_AMBITO = 2000

export async function listarLeadsDelAmbito(signal?: AbortSignal): Promise<Lead[]> {
  // Ventana de convertidos (decisión de Miguel 2026-08-08, F1): un convertido
  // con más de 45 días deja de ser lead operativo — MISMO corte que aplican
  // las RPC de métricas del servidor, para que los tiles y las filas cuenten
  // la misma película. El valor va entre comillas: en la mini-sintaxis de
  // `.or()` de PostgREST el literal ISO viaja como valor citado, nunca como
  // parte de la expresión lógica.
  const corteConvertidos = new Date(Date.now() - VENTANA_CONVERTIDOS_MS).toISOString()
  let consulta = cliente()
    .schema('crm')
    .from('leads')
    .select(COLUMNAS_LEAD)
    .or(`etapa.neq.convertido,convertido_en.gte."${corteConvertidos}"`)
    .order('actualizado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_LEADS_AMBITO)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.leads.ambito_fallido', fallo)
    throw fallo
  }
  avisarTopeAlcanzado('leads_del_ambito', MAX_LEADS_AMBITO, (data ?? []).length)
  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(LeadRowSchema, cruda)
    if (r.success) items.push(aLead(r.output))
    else descartadas += 1
  }
  if (descartadas > 0) {
    registrarError(
      'crm.leads.ambito_filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas, limite: MAX_LEADS_AMBITO },
    )
  }
  return items
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
}

const LeadCarteraRowSchema = v.object({
  ...LeadRowSchema.entries,
  ultimo_contacto_en: v.nullable(v.string()),
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
  const argumentos: Record<string, unknown> = { p_limite: TAMANO_PAGINA_CARTERA + 1 }
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

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('cartera_pagina_fn', argumentos)
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    // 42501 NO es «se cayó el servidor»: es la guardia de admisión de la RPC
    // diciendo que esta cuenta no pertenece al CRM (P04: revocado ≠ ajeno). Con
    // el mensaje genérico, un offboarding vivido como avería mandaría a alguien
    // a reintentar durante horas.
    const fallo = error.code === '42501'
      ? new CrmApiError('Tu cuenta no tiene acceso a la cartera del CRM.', '42501')
      : new CrmApiError('No se pudo cargar la cartera.', error.code || 'POSTGREST_ERROR')
    // Sin texto ni IDs del filtro: pueden contener PII.
    registrarError('crm.leads.pagina_fallida', fallo, {
      etapa: filtros.etapa ?? 'todas',
      filtraVendedor: Boolean(filtros.vendedorId && filtros.vendedorId !== 'todos'),
      tieneBusqueda: texto !== null,
      conCursor: cursor != null,
    })
    throw fallo
  }

  const crudas = Array.isArray(data) ? data : []
  const hayMas = crudas.length > TAMANO_PAGINA_CARTERA
  const ventana = hayMas ? crudas.slice(0, TAMANO_PAGINA_CARTERA) : crudas

  const items: Lead[] = []
  let descartadas = 0
  for (const cruda of ventana) {
    const r = v.safeParse(LeadCarteraRowSchema, cruda)
    if (r.success) {
      items.push({ ...aLead(r.output), ultimo_contacto_en: r.output.ultimo_contacto_en })
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
      siguiente = { actualizadoEn: ultima.output.actualizado_en, id: ultima.output.id }
    } else {
      registrarError(
        'crm.leads.pagina_sin_cursor',
        new CrmApiError('La última fila de la página no permite calcular el cursor', 'CURSOR_CONTRACT'),
      )
    }
  }

  return { items, cursor: siguiente }
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
  const fallo = new CrmApiError(
    'El servidor devolvió metas con un formato no reconocido.',
    'ROW_CONTRACT',
  )
  registrarError(evento, fallo)
  return fallo
}

/** Fotografía completa del roster y su última revisión mensual publicada. */
export async function obtenerMetasDelMes(
  periodo: string,
  signal?: AbortSignal,
): Promise<ConfiguracionMetas> {
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
export async function obtenerCumplimientoMetas(
  periodo: string,
  signal?: AbortSignal,
): Promise<CumplimientoMetasRpc> {
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
    const fallo = new CrmApiError(
      'El servidor devolvió un estado del cierre de mes no reconocido.',
      'ROW_CONTRACT',
    )
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

const AsignacionAgendaRepartoSchema = v.object({
  origen: OrigenAgendaRepartoSchema,
  supervisor_id: v.nullable(v.string()),
  supervisor_nombre: v.nullable(v.string()),
  supervisor_alias: v.nullable(v.string()),
  derivados: v.pipe(v.union([v.number(), v.string()]), v.transform(Number)),
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
  let consulta = cliente().schema('crm').rpc('historial_derivaciones', {
    p_limite: TAMANO_PAGINA_HISTORIAL_REPARTO,
    ...(cursor
      ? { p_derivado_antes: cursor.derivado_en, p_actividad_antes: cursor.actividad_id }
      : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      'No se pudo cargar el historial de derivaciones.',
      error.code || 'POSTGREST_ERROR',
    )
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
  let consulta = cliente().schema('crm').rpc('agenda_reparto_diaria', {
    ...(filtros.desde ? { p_desde: filtros.desde } : {}),
    ...(filtros.dias ? { p_dias: filtros.dias } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      'No se pudo cargar la agenda de reparto.',
      error.code || 'POSTGREST_ERROR',
    )
    registrarError('crm.reparto.agenda_fallida', fallo)
    throw fallo
  }
  const resultado = v.safeParse(AgendaRepartoDiariaSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'La agenda de reparto no tiene el formato esperado.',
      'AGENDA_REPARTO_CONTRACT',
    )
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
    const mensaje = error.code === '22023' && error.message.trim().length > 0
      ? error.message
      : 'No se pudo guardar la agenda de reparto.'
    const fallo = new CrmApiError(
      mensaje,
      error.code || 'POSTGREST_ERROR',
    )
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
    const fallo = new CrmApiError(
      'No se pudo cargar el panel de distribución.',
      error.code || 'POSTGREST_ERROR',
    )
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
export async function listarIngresosRepartoMes(
  mes: string,
  signal?: AbortSignal,
): Promise<IngresosRepartoMes> {
  const pMes = inicioDeMes(mes)
  if (pMes == null) {
    throw new CrmApiError('El mes seleccionado no es valido.', 'MES_INVALIDO')
  }

  let consulta = cliente().schema('crm').rpc('ingresos_reparto_mes_fn', { p_mes: pMes })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError(
      'No se pudieron cargar los ingresos del mes.',
      error.code || 'POSTGREST_ERROR',
    )
    registrarError('crm.reparto.ingresos_mes_fallido', fallo)
    throw fallo
  }

  const resultado = v.safeParse(IngresosRepartoMesSchema, data)
  if (!resultado.success || resultado.output.mes !== pMes) {
    const fallo = new CrmApiError(
      'El resumen de ingresos no tiene el formato esperado.',
      'INGRESOS_REPARTO_CONTRACT',
    )
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
export async function descartarLead(
  leadId: string,
  motivo: MotivoDescarte,
  nota?: string,
): Promise<void> {
  const { error } = await cliente().schema('crm').rpc('descartar_lead', {
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

// ── Timeline del ámbito con AUTOR (RPC SECURITY DEFINER actividades_del_ambito_fn)
const TIPOS_ACT = Object.keys(TIPOS_ACTIVIDAD) as [TipoActividad, ...TipoActividad[]]
const ActividadRowSchema = v.object({
  id: v.string(),
  lead_id: v.string(),
  tipo: v.picklist(TIPOS_ACT),
  detalle: v.nullable(v.string()),
  autor_nombre: v.string(),
  creado_en: v.string(),
})

// Espejo del LIMIT de crm.actividades_del_ambito_fn (migración 20260808163638):
// el tope vive en el SERVIDOR; esta constante solo alimenta la alarma de topes.
const LIMITE_ACTIVIDADES_AMBITO = 10000

export async function listarActividadesDelAmbito(signal?: AbortSignal): Promise<Actividad[]> {
  let consulta = cliente().schema('crm').rpc('actividades_del_ambito_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar el historial.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.actividades.listado_fallido', fallo)
    throw fallo
  }
  avisarTopeAlcanzado('actividades_del_ambito', LIMITE_ACTIVIDADES_AMBITO, (data ?? []).length)
  const items: Actividad[] = []
  for (const cruda of data ?? []) {
    const r = v.safeParse(ActividadRowSchema, cruda)
    if (r.success) items.push(r.output)
  }
  return items
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
  let consulta = cliente().schema('crm').rpc('verificar_disponibilidad_lead', sinIndefinidos({
    p_telefono: telefono,
    p_dni: dni ?? undefined,
  }))
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
      registrarError('crm.leads.disponibilidad_no_disponible', fallo, { postgrest: error.code })
      throw fallo
    }
    // postgrest-js representa un fetch fallido con status=0; PGRST000–003 son
    // indisponibilidad/conexión/pool de PostgREST. Son los únicos fallos del
    // servidor que P-048 trata como cortesía fail-open. Un HTTP malformado sin
    // code pero con status real NO se confunde con transporte.
    if (status === 0 || ['PGRST000', 'PGRST001', 'PGRST002', 'PGRST003'].includes(error.code)) {
      const fallo = new CrmApiError(
        'No se pudo contactar el servicio de disponibilidad.',
        'DISPONIBILIDAD_RED',
      )
      registrarError('crm.leads.disponibilidad_red', fallo, { postgrest: error.code || 'sin_codigo' })
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

export async function listarRecordatoriosDisponibilidad(
  signal?: AbortSignal,
): Promise<RecordatorioCampana[]> {
  // SIN dni a propósito (minimización §8, F3.1): la campana no lo usa y cada
  // refetch lo paseaba por la red sin ningún consumidor.
  let consulta = cliente().schema('crm')
    .from('recordatorios_disponibilidad')
    .select('id, perfil_id, telefono, recordar_en, creado_en')
    .order('recordar_en', { ascending: true })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw aErrorApi(error, 'crm.recordatorios.listar_fallido')
  const resultado = v.safeParse(RecordatoriosCampanaSchema, data ?? [])
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'Los recordatorios no tienen el formato esperado.',
      'RECORDATORIOS_CONTRACT',
    )
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
  const { data, error } = await cliente().schema('crm')
    .from('recordatorios_disponibilidad')
    .upsert(
      // `dni` viaja SIEMPRE, null incluido (F3.1): omitirlo hacía que un
      // re-guardado sin DNI CONSERVARA el DNI anterior en el servidor — un
      // vínculo teléfono↔DNI que el vendedor ya no está afirmando. El dato
      // fresco manda: sin DNI = limpiar el anterior.
      { perfil_id: perfilId, telefono, dni, recordar_en: recordarEn },
      { onConflict: 'perfil_id,telefono' },
    )
    .select('id, perfil_id, telefono, dni, recordar_en, creado_en')
    .single()
  if (error) throw aErrorApi(error, 'crm.recordatorios.guardar_fallido')
  const resultado = v.safeParse(RecordatorioDisponibilidadSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'El recordatorio guardado no tiene el formato esperado.',
      'RECORDATORIOS_CONTRACT',
    )
    registrarError('crm.recordatorios.guardado_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

export async function eliminarRecordatorioDisponibilidad(id: string): Promise<void> {
  const { data, error } = await cliente().schema('crm')
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

/**
 * F2 «Tomar» (spec §5.6/§5.7): toma directa POR CONTACTO contra
 * crm.tomar_lead_libre. Es una MUTACIÓN — a diferencia del precheck
 * consultivo, aquí no existe cortesía fail-open: cualquier fallo se lanza y
 * el formulario lo dice sin fingir nada. La respuesta es o `tomado_ok` o el
 * veredicto fresco de disponibilidad (el servidor jamás roba al perdedor de
 * la carrera; devuelve la verdad del momento para re-presentarla).
 */
export async function tomarLeadLibre(
  telefono: string,
  dni?: string | null,
): Promise<ResultadoTomaLead> {
  const { data, error } = await cliente().schema('crm').rpc('tomar_lead_libre', sinIndefinidos({
    p_telefono: telefono,
    p_dni: dni ?? undefined,
  }))
  if (error) throw aErrorApi(error, 'crm.leads.toma_fallida')

  const resultado = v.safeParse(ResultadoTomaLeadSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'El servidor no confirmó la toma del lead.',
      'TOMA_LEAD_CONTRACT',
    )
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
  correo?: CrearLeadArgs['p_correo'] | null
  dni?: CrearLeadArgs['p_dni'] | null
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
  error: { code?: string | null; message?: string | null; details?: string | null },
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
    (codigoPg === '23502' && texto.includes('monto_estimado'))
    || (codigoPg === '23514' && texto.includes('leads_monto_estimado_valido'))
  ) {
    code = 'MONTO_INVALIDO'
    mensaje = 'El capital estimado es obligatorio y debe ser mayor que 0'
  } else if (codigoPg === '23514' && texto.includes('datos legales obligatorios')) {
    // El RAISE de private.contrato_pdf_snapshot_v2_base. Caía en el genérico
    // "No se pudo guardar el cambio.", que es lo que de verdad veían los
    // vendedores cuando un cliente antiguo no tenía domicilio: un mensaje que
    // no nombra ni el dato ni al culpable, imposible de diagnosticar desde la
    // pantalla. El texto del servidor no lleva PII, pero tampoco dice QUÉ falta.
    code = 'DATOS_LEGALES_INCOMPLETOS'
    mensaje = 'Faltan datos legales para emitir el contrato: revisa el domicilio, '
      + 'el documento y el correo del cliente, y tu propio celular y correo.'
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
  } else if (codigoPg === 'P0481') {
    code = 'CONTACTO_NO_DISPONIBLE'
    mensaje = 'Ese teléfono o DNI no está disponible para este lead.'
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

function aErrorInsertarLead(
  error: { code?: string | null; message?: string | null; details?: string | null },
): CrmApiError {
  if (error.code === '55P03' || error.code === '40P01') {
    const fallo = new CrmApiError(
      'Otro usuario está procesando este contacto. Inténtalo nuevamente.',
      'CONTACTO_EN_PROCESO',
    )
    registrarError('crm.leads.creacion_atomica_en_espera', fallo, { pg: error.code })
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
        registrarError('crm.leads.creacion_atomica_bloqueada', fallo, { estado: resultado.output.estado })
        return fallo
      }
    } catch {
      // Un DETAIL roto no se refleja ni se registra: cae al error genérico.
    }
  }

  const texto = `${error.message ?? ''} ${error.details ?? ''}`
  const esCarreraDelContacto = error.code === '23505' && (
    texto.includes('uq_leads_telefono_vivo') || texto.includes('uq_leads_dni_vivo')
  )
  if (!esCarreraDelContacto) return aErrorApi(error, 'crm.leads.insert_fallido')

  // La RPC es la autoridad. El índice único queda como última defensa ante un
  // escritor que todavía no comparta el protocolo de candados.
  const fallo = new CrmApiError(
    'Este contacto acaba de ser registrado por otro usuario',
    'CONTACTO_RECIEN_REGISTRADO',
  )
  registrarError('crm.leads.insert_fallido', fallo, { pg: '23505' })
  return fallo
}

export async function insertarLead(fila: CrearLeadAtomicoInput): Promise<ResultadoCreacionLeadAtomica> {
  const { data, error } = await cliente().schema('crm').rpc('crear_lead_si_disponible', sinIndefinidos({
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
  }))
  if (error) throw aErrorInsertarLead(error)

  const resultado = v.safeParse(ResultadoCreacionLeadAtomicaSchema, data)
  if (!resultado.success || resultado.output.estado === 'libre') {
    const fallo = new CrmApiError(
      'El servidor no confirmó la creación del lead.',
      'CREACION_LEAD_CONTRACT',
    )
    registrarError('crm.leads.creacion_atomica_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

export async function actualizarLead(id: string, cambios: LeadUpdate): Promise<void> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('leads')
    .update(cambios)
    .eq('id', id)
    .select('id')
  if (error) throw aErrorApi(error, 'crm.leads.update_fallido')
  if (!data || data.length === 0) {
    // La RLS ocultó el lead (fuera del ámbito) o no existe: mismo mensaje,
    // sin revelar existencia (igual que el espejo del store).
    throw new CrmApiError('Lead no encontrado', 'NO_ENCONTRADO')
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

const COLUMNAS_TAREA = ([
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
] as const satisfies readonly (keyof TareaDatabaseRow)[]).join(',')

const TareaRowSchema = v.object({
  id: v.string(),
  lead_id: v.nullable(v.string()),
  perfil_id: v.nullable(v.string()),
  vendedor_id: v.nullable(v.string()),
  asignado_supervisor_id: v.nullable(v.string()),
  tipo: v.picklist(TIPOS_TAREA.map((t) => t.k)),
  titulo: v.string(),
  nota: v.nullable(v.string()),
  vence_en: v.string(),
  duracion_min: v.nullable(v.number()),
  estado: v.picklist(ESTADOS_TAREA),
  modalidad_reunion: v.nullable(v.picklist(MODALIDADES_REUNION_TODAS)),
  ubicacion_reunion: v.nullable(v.string()),
  enlace_reunion: v.nullable(v.string()),
  resultado_reunion: v.nullable(v.picklist(RESULTADOS_REUNION_TODOS)),
  motivo_no_realizada: v.nullable(v.picklist(MOTIVOS_NO_REALIZADA_TODOS)),
  detalle_cierre_reunion: v.nullable(v.string()),
  confirmada_en: v.nullable(v.string()),
  reagendada_de: v.nullable(v.string()),
  reprogramaciones: v.number(),
  activo: v.boolean(),
  creado_en: v.string(),
})

// Salvaguarda de payload (no seguridad): la RLS ya recorta al ámbito.
const MAX_TAREAS_AMBITO = 2000

/**
 * Tareas PENDIENTES del ámbito (HOY + Agenda beben de aquí). Las cerradas no
 * viajan: su historia vive en crm.actividades (timeline del lead).
 */
export async function listarTareasDelAmbito(signal?: AbortSignal): Promise<Tarea[]> {
  let consulta = cliente()
    .schema('crm')
    .from('tareas')
    .select(COLUMNAS_TAREA)
    .eq('estado', 'pendiente')
    .eq('activo', true)
    .order('vence_en', { ascending: true })
    .order('id', { ascending: true })
    .limit(MAX_TAREAS_AMBITO)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar la agenda.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.tareas.ambito_fallido', fallo)
    throw fallo
  }
  avisarTopeAlcanzado('tareas_del_ambito', MAX_TAREAS_AMBITO, (data ?? []).length)
  const items: Tarea[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const resultado = v.safeParse(TareaRowSchema, cruda)
    if (resultado.success) items.push(resultado.output)
    else descartadas += 1
  }
  if (descartadas > 0) {
    registrarError(
      'crm.tareas.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }
  return items
}

type TareaInsert = Database['crm']['Tables']['tareas']['Insert']
type TareaUpdate = Database['crm']['Tables']['tareas']['Update']

export async function insertarTarea(fila: TareaInsert): Promise<void> {
  const { error } = await cliente().schema('crm').from('tareas').insert(fila)
  if (error) throw aErrorApi(error, 'crm.tareas.insert_fallido')
}

export async function actualizarTarea(id: string, cambios: TareaUpdate): Promise<void> {
  const { data, error } = await cliente()
    .schema('crm')
    .from('tareas')
    .update(cambios)
    .eq('id', id)
    .select('id')
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
  const { data, error } = await cliente().schema('crm').rpc('cerrar_tarea', sinIndefinidos({
    p_tarea_id: input.tarea_id,
    p_estado: input.estado,
    p_resultado_tipo: input.resultado_tipo ?? undefined,
    p_resultado_detalle: input.resultado_detalle ?? undefined,
    p_siguiente: (input.siguiente ?? null) as Json,
  }))
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

export async function cerrarReunion(
  input: CerrarReunionInput,
): Promise<{ siguiente_id: string | null }> {
  const { data, error } = await cliente().schema('crm').rpc('cerrar_reunion', sinIndefinidos({
    p_tarea_id: input.tarea_id,
    p_estado: input.estado,
    p_resultado_reunion: input.resultado_reunion ?? undefined,
    p_motivo_no_realizada: input.motivo_no_realizada ?? undefined,
    p_detalle: input.detalle ?? undefined,
    p_siguiente: (input.siguiente ?? null) as Json,
  }))
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
  const idsCoherentes = respuesta.success
    && respuesta.output.tarea_anterior_id === tareaId
    && respuesta.output.tarea_nueva_id === nuevaId
    && respuesta.output.tarea_anterior_id !== respuesta.output.tarea_nueva_id

  if (!respuesta.success || !idsCoherentes) {
    const fallo = new CrmApiError(
      'La reprogramación respondió fuera del contrato esperado.',
      'ROW_CONTRACT',
    )
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

const UUID_CANONICO_CONVERSION_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

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
    } catch { /* nos quedamos con el mensaje genérico */ }
    const fallo = new CrmApiError(mensaje, 'CONVERTIR_FALLIDO')
    registrarError('crm.convertir.fallido', fallo)
    throw fallo
  }
  const respuesta = v.safeParse(ConvertirLeadRespuestaSchema, data)
  if (!respuesta.success) {
    const fallo = new CrmApiError(
      'La conversión respondió fuera del contrato esperado.',
      'RESPUESTA_INVALIDA',
    )
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
    origen: v.picklist(['perfil', 'contrato']),
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
      const fallo = new CrmApiError(
        'Las cuentas bancarias no tienen el formato esperado.',
        'ROW_CONTRACT',
      )
      registrarError('crm.cuentas_bancarias.fila_invalida', fallo)
      // Fail-closed: ocultar una sola fila podría hacer que el asesor elija una
      // cuenta distinta creyendo que la autorizada ya no existe.
      throw fallo
    }
    cuentas.push(fila.output)
  }
  return cuentas
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
  /**
   * Co-titulares (cuentas mancomunadas, máx 5): viajan DENTRO de p_contrato —
   * crear_contrato ya los persiste vía _sync_contrato_titulares. Ausente o []
   * en el ALTA es lo mismo: contrato sin co-titulares.
   */
  titulares?: TitularInput[]
  /** Obligatoria en el CRM nuevo; el servidor vuelve a validar dueño y moneda. */
  cuenta_pago: CuentaPagoContratoInput
}

export interface CrearContratoResultado {
  id: string
  numero_contrato: string
  cuenta_bancaria_id: string
  pdf: {
    contrato_id: string
    job_id: string
    estado: EstadoContratoPdf
    reintentable: boolean
  }
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

const EnteroProductoSchema = v.pipe(
  v.union([v.number(), v.string()]),
  v.transform(Number),
  v.integer(),
  v.minValue(1),
)

const CrearContratoResultadoSchema = v.object({
  id: v.pipe(v.string(), v.uuid()),
  numero_contrato: v.pipe(v.string(), v.minLength(1)),
  cuenta_bancaria_id: v.pipe(v.string(), v.uuid()),
  pdf: v.strictObject({
    contrato_id: v.pipe(v.string(), v.uuid()),
    job_id: v.pipe(v.string(), v.uuid()),
    estado: v.literal('pendiente'),
    storage_bucket: v.literal('contratos-generados'),
    storage_path: v.pipe(v.string(), v.minLength(1)),
    nombre_archivo: v.pipe(v.string(), v.minLength(5)),
    // Durante un despliegue escalonado el frontend puede convivir unos minutos
    // con reservas v3/v4 o con la v5 vigente. Todas representan jobs durables;
    // cualquier otra versión sigue fallando cerrado.
    //
    // ⚠️ Esta tolerancia YA existía en el bundle vivo del 33.º release, aplicada
    // sobre el commit SIN commitear. Al reconstruir desde ese commit se perdió,
    // y el front volvió a exigir v3 mientras producción emite v5: TODA creación
    // de contrato moría con «El servidor no confirmó completamente el contrato»
    // aunque el contrato SÍ se había creado. Un parche que solo vive en el
    // artefacto no existe: si no está en un commit, el siguiente release lo pisa.
    template_version: v.picklist([
      'contrato-aep-17-v3',
      'contrato-aep-17-v4',
      'contrato-aep-17-v5',
    ]),
    intentos: v.pipe(v.number(), v.integer(), v.minValue(0)),
    lease_expira_en: v.nullable(v.string()),
    reintentable: v.boolean(),
    sha256: v.nullable(v.pipe(v.string(), v.regex(/^[a-f0-9]{64}$/))),
    bytes: v.nullable(v.pipe(v.number(), v.integer(), v.minValue(1))),
    archivo: v.nullable(v.unknown()),
  }),
})

export async function crearContrato(
  input: CrearContratoInput,
  cronograma: CuotaCronograma[],
): Promise<CrearContratoResultado> {
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
  // En el alta, [] equivale a ausente: solo viajan si de verdad hay co-titulares.
  if (input.titulares && input.titulares.length > 0) p_contrato.titulares = input.titulares
  const p_cronograma = cronograma as unknown as Json[]
  const { data, error } = await cliente().schema('crm').rpc('crear_contrato_con_cuenta_pdf_v2', {
    p_contrato: p_contrato as unknown as Json,
    p_cronograma,
    p_cuenta: input.cuenta_pago as unknown as Json,
  })
  if (error) throw aErrorApi(error, 'crm.contrato.crear_fallido')
  const r = v.safeParse(CrearContratoResultadoSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError(
      'El servidor no confirmó completamente el contrato y su cuenta de pago.',
      'ROW_CONTRACT',
    )
    registrarError('crm.contrato.respuesta_invalida', fallo)
    throw fallo
  }
  if (
    r.output.pdf.contrato_id !== r.output.id ||
    r.output.pdf.estado !== 'pendiente' ||
    r.output.pdf.intentos !== 0 ||
    r.output.pdf.sha256 !== null ||
    r.output.pdf.bytes !== null ||
    r.output.pdf.archivo !== null ||
    r.output.pdf.storage_path !== `${r.output.id}/v2/${r.output.pdf.job_id}/contrato.pdf`
  ) {
    const fallo = new CrmApiError(
      'El servidor no reservó correctamente el PDF contractual.',
      'ROW_CONTRACT',
    )
    registrarError('crm.contrato.pdf_reserva_invalida', fallo)
    throw fallo
  }
  return r.output
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

// Salvaguarda de payload (no seguridad — la vista/RLS ya recortan el ámbito).
const MAX_CLIENTES_CARTERA = 2000
const MAX_CONTRATOS_CARTERA = 2000

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
  let consulta = cliente()
    .schema('crm')
    .from('clientes_basicos')
    .select(COLUMNAS_CLIENTE_BASICO)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_CLIENTES_CARTERA)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudo cargar tu cartera de clientes.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.clientes.listado_fallido', fallo)
    throw fallo
  }
  avisarTopeAlcanzado('clientes_cartera', MAX_CLIENTES_CARTERA, (data ?? []).length)
  const items: ClienteBasico[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(ClienteBasicoRowSchema, cruda)
    if (r.success) {
      items.push({ ...r.output, nombre_completo: r.output.nombre_completo ?? '' })
    } else {
      descartadas += 1
    }
  }
  if (descartadas > 0) {
    registrarError(
      'crm.clientes.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }
  return items
}

// ── Cliente: detalle con las 14 bancarias (public.perfiles vía RLS de cartera) ─
const COLUMNAS_CLIENTE_DETALLE = [
  'id',
  'nombre_completo',
  'nombres',
  'apellidos',
  'tipo_documento',
  'dni',
  'correo',
  'telefono',
  'domicilio',
  'asesor_perfil_id',
  'creado_por',
  'creado_en',
  'banco',
  'tipo_cuenta',
  'numero_cuenta',
  'cci',
  'titular_distinto',
  'beneficiario_nombre',
  'beneficiario_dni',
  'banco_usd',
  'tipo_cuenta_usd',
  'numero_cuenta_usd',
  'cci_usd',
  'titular_distinto_usd',
  'beneficiario_nombre_usd',
  'beneficiario_dni_usd',
].join(',')

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
 * Detalle completo para el modo "corregir". Se usa `.limit(1)` (no `.single()`)
 * a propósito: la frontera HTTP queda SIEMPRE con forma de array — mismos mocks
 * en msw/Playwright y sin el 406 especial de PostgREST.
 */
export async function obtenerClienteDetalle(id: string, signal?: AbortSignal): Promise<ClienteDetalle> {
  let consulta = cliente()
    .from('perfiles')
    .select(COLUMNAS_CLIENTE_DETALLE)
    .eq('id', id)
    .limit(1)
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
    // La RLS ocultó el perfil (fuera de tu cartera) o no existe: mismo mensaje,
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
 * `asesor_perfil_id`, así que el cliente puede quedar a nombre de otro asesor.
 * Sin esta comprobación la ficha solo podía adivinar, y adivinar era prometer.
 *
 * `null` = NO SE PUDO COMPROBAR (red, RLS, servidor). El llamador no debe
 * afirmar ninguna de las dos cosas: no es un `false` disfrazado.
 */
export async function esClienteDeMiCartera(
  perfilId: string,
  signal?: AbortSignal,
): Promise<boolean | null> {
  let consulta = cliente()
    .from('perfiles')
    .select('id')
    .eq('id', perfilId)
    .eq('rol', 'cliente')
    .limit(1)
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

  const { data, error } = await cliente().functions.invoke('crear-cliente', { body })
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
    } catch { /* nos quedamos con el mensaje genérico */ }
    const fallo = new CrmApiError(mensaje, 'ALTA_CLIENTE_FALLIDA')
    registrarError('crm.clientes.alta_fallida', fallo)
    throw fallo
  }
  const cuerpo = (data ?? {}) as { ok?: boolean; user_id?: string; email_enviado?: boolean; error?: string }
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
export type ClientePortalPatch = Database['public']['Tables']['perfiles']['Update']

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

  const { data, error } = await cliente()
    .from('perfiles')
    .update(patch)
    .eq('id', id)
    .select('id')
  if (error) throw aErrorApi(error, 'crm.clientes.update_fallido')
  return (data?.length ?? 0) > 0
}

// ── Datos legales que el contrato exige ANTES de intentar emitirlo ────────────
// El PDF se reserva dentro de la MISMA transacción del alta, así que un dato
// legal ausente revierte el contrato entero con 'Faltan datos legales
// obligatorios del titular o del analista' — un mensaje que no dice CUÁL falta.
// Preguntarlo antes convierte ese muro en un campo que el vendedor rellena.

/** Campos del titular que el PDF exige (nombres, nunca valores: no es una vía a la PII). */
export const CAMPOS_LEGALES_CLIENTE = [
  'nombre_completo',
  'tipo_documento',
  'documento',
  'domicilio',
  'correo',
] as const
export type CampoLegalCliente = (typeof CAMPOS_LEGALES_CLIENTE)[number]

/** Campos del propio analista que firma el alta (contratos.creado_por = auth.uid()). */
export const CAMPOS_LEGALES_ANALISTA = [
  'nombre_completo',
  'documento',
  'telefono',
  'correo',
] as const
export type CampoLegalAnalista = (typeof CAMPOS_LEGALES_ANALISTA)[number]

export interface DatosLegalesContrato {
  clienteId: string
  /** El único hueco que el vendedor puede cerrar por su cuenta. */
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
    const fallo = new CrmApiError(
      'No se pudo comprobar qué datos legales exige el contrato.',
      'RESPUESTA_INVALIDA',
    )
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
 * (otra sesión ganó la carrera) y el servidor lo respetó. Lo que el vendedor
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

export async function completarDomicilioCliente(
  clienteId: string,
  domicilio: string,
): Promise<DomicilioCompletado> {
  const { data, error } = await cliente().schema('crm').rpc('completar_domicilio_cliente', {
    p_cliente_id: clienteId,
    p_domicilio: domicilio,
  })
  if (error) throw aErrorApi(error, 'crm.clientes.domicilio_fallido')
  const r = v.safeParse(DomicilioCompletadoSchema, data)
  if (!r.success) {
    const fallo = new CrmApiError(
      'El servidor no confirmó el domicilio legal del cliente.',
      'RESPUESTA_INVALIDA',
    )
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

const ContratoRowSchema = v.object({
  id: v.string(),
  numero_contrato: v.string(),
  cliente_id: v.string(),
  // numeric(12,2): PostgREST puede serializarlo como string
  capital: v.union([v.number(), v.string()]),
  moneda: v.picklist(['PEN', 'USD']),
  tasa_anual: v.union([v.number(), v.string()]),
  modalidad: v.picklist(MODALIDADES_CONTRATO),
  tipo_interes: v.picklist(TIPOS_INTERES),
  categoria: v.nullable(v.picklist(CATEGORIAS_CONTRATO)),
  estado: v.picklist(ESTADOS_CONTRATO),
  fecha_inicio: v.string(),
  fecha_vencimiento: v.string(),
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
  // todo, supervisor su subárbol, vendedor su cartera. La RLS directa de
  // public.contratos dejaba a gerencia en 0 filas y al supervisor sin su equipo.
  let consulta = cliente()
    .schema('crm')
    .from('contratos_cartera')
    .select(COLUMNAS_CONTRATO)
    .order('creado_en', { ascending: false })
    .order('id', { ascending: true })
    .limit(MAX_CONTRATOS_CARTERA)
  if (signal) consulta = consulta.abortSignal(signal)

  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar tus contratos.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.contratos.listado_fallido', fallo)
    throw fallo
  }
  avisarTopeAlcanzado('contratos_cartera', MAX_CONTRATOS_CARTERA, (data ?? []).length)
  const items: ContratoRow[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(ContratoRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
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
  if (descartadas > 0) {
    registrarError(
      'crm.contratos.filas_invalidas',
      new CrmApiError('Filas fuera de contrato descartadas', 'ROW_CONTRACT'),
      { descartadas },
    )
  }
  return items
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

// ═══════════════════════════════════════════════════════════════════════════════
// MÉTRICAS DE GERENCIA — 4 RPCs crm.metricas_*_fn (SECURITY DEFINER, ya en prod).
// El ÁMBITO lo resuelve el servidor (gerencia=todo, supervisor=subárbol,
// vendedor=él): el navegador jamás recorta ni agrega seguridad. Aquí solo se
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

const MetricaAltasRowSchema = v.object({
  mes: v.string(),
  analista_id: v.string(),
  analista_nombre: v.string(),
  altas: NumericoRpc,
})

const MetricaVencimientosRowSchema = v.object({
  mes: v.string(),
  moneda: v.picklist(['PEN', 'USD']),
  contratos_por_vencer: NumericoRpc,
  capital_por_vencer: NumericoRpc,
})

/** Error de RPC de métricas → CrmApiError es-PE + registro (patrón del módulo). */
function falloMetricas(
  error: { code?: string | null },
  contexto: string,
): CrmApiError {
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
export async function listarMetricasCapitalMes(
  pMeses = 12,
  signal?: AbortSignal,
): Promise<FilaCapitalMes[]> {
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

/** Pagos por mes/moneda/tipo/estado (default: últimos 12 meses). */
export async function listarMetricasPagosMes(
  pMeses = 12,
  signal?: AbortSignal,
): Promise<FilaPagosMes[]> {
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

/** Altas de clientes por analista y mes (default: últimos 12 meses). */
export async function listarMetricasAltasAnalista(
  pMeses = 12,
  signal?: AbortSignal,
): Promise<FilaAltasAnalista[]> {
  let consulta = cliente().schema('crm').rpc('metricas_altas_analista_fn', { p_meses: pMeses })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.altas_fallido')
  const items: FilaAltasAnalista[] = []
  let descartadas = 0
  for (const cruda of data ?? []) {
    const r = v.safeParse(MetricaAltasRowSchema, cruda)
    if (!r.success) {
      descartadas += 1
      continue
    }
    items.push({
      mes: r.output.mes,
      analista_id: r.output.analista_id,
      analista_nombre: r.output.analista_nombre,
      altas: aNumero(r.output.altas) ?? 0,
    })
  }
  registrarFilasMetricasInvalidas('altas_analista', descartadas)
  return items
}

/** Contratos/capital por vencer por mes/moneda dentro de p_dias (default 90). */
export async function listarMetricasVencimientos(
  pDias = 90,
  signal?: AbortSignal,
): Promise<FilaVencimientos[]> {
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
  return v.safeParse(FechaMetricaSchema, desde).success
    && v.safeParse(FechaMetricaSchema, hasta).success
    && desde <= hasta
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
  throw signal.reason instanceof Error
    ? signal.reason
    : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

/**
 * Fotografía atómica V2 de distribución, capacidad y resultados comerciales.
 * El SLA versionado tiene contratos propios y no se mezcla en este payload.
 * A diferencia de las RPC tabulares antiguas, aquí no se descartan ramas
 * inválidas: una sola falla invalida el payload completo para no mezclar
 * denominadores o periodos incompatibles en Gerencia.
 */
export async function listarMetricasDistribucionLeads(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasDistribucionLeads> {
  if (!periodoMetricasValido(desde, hasta)) {
    const fallo = new CrmApiError(
      'El período de métricas no es válido.',
      'PERIODO_METRICAS_INVALIDO',
    )
    registrarError('crm.metricas.distribucion_periodo_invalido', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_distribucion_leads_v2_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.distribucion_fallido')

  const resultado = v.safeParse(MetricasDistribucionLeadsSchema, data)
  if (
    !resultado.success
    || resultado.output.cohorte.desde_inclusivo !== desde
    || resultado.output.cohorte.hasta_inclusivo !== hasta
  ) {
    const fallo = new CrmApiError(
      'Las métricas de distribución no tienen el formato esperado.',
      'METRICAS_DISTRIBUCION_CONTRACT',
    )
    registrarError('crm.metricas.distribucion_fuera_de_contrato', fallo)
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
    const fallo = new CrmApiError(
      'El período de métricas no es válido.',
      'PERIODO_METRICAS_INVALIDO',
    )
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
  if (
    !resultado.success
    || resultado.output.periodo.desde !== desde
    || resultado.output.periodo.hasta !== hasta
  ) {
    const fallo = new CrmApiError(
      'Las métricas de agenda no tienen el formato esperado.',
      'METRICAS_AGENDA_CONTRACT',
    )
    registrarError('crm.metricas.agenda_fuera_de_contrato', fallo)
    throw fallo
  }

  return resultado.output
}

export async function listarMetricasConversiones(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasConversiones> {
  if (!periodoMetricasValido(desde, hasta)) {
    throw new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
  }
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_conversiones_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.conversiones_fallido')
  const resultado = v.safeParse(MetricasConversionesSchema, data)
  if (!resultado.success || resultado.output.periodo.desde !== desde || resultado.output.periodo.hasta !== hasta) {
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
 * La conversión mensual ponderada del asesor (crm.conversion_mensual_fn) — LA
 * definición acordada, no las cohortes de la pantalla «Conversiones».
 *
 * MENSUAL POR CONTRATO: `periodo` es el PRIMER DÍA del mes ('2026-08-01') y la
 * pregunta «qué devuelve en un rango libre» es inexpresable. El ámbito lo
 * decide el SERVIDOR (vendedor→su fila, supervisor→su subárbol, gerencia y
 * lector global→empresa) y viaja en `alcance`; los denegados reciben 42501
 * duro, jamás un payload de ceros.
 *
 * La verificación de eco compara `periodo.mes` con el MES pedido — el payload
 * no trae `desde/hasta` en fecha-plana como sus hermanas, trae el mes nombrado
 * (copiar aquí el patrón desde/hasta rechazaría el 100 % de las respuestas).
 */
export async function obtenerConversionMensual(
  periodo: string,
  signal?: AbortSignal,
): Promise<ConversionMensual> {
  if (!PERIODO_MENSUAL_RE.test(periodo)) {
    const fallo = new CrmApiError(
      'El período de la conversión mensual no es válido.',
      'PERIODO_METRICAS_INVALIDO',
    )
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
  if (!resultado.success || resultado.output.periodo.mes !== periodo.slice(0, 7)) {
    const fallo = new CrmApiError(
      'La conversión mensual no tiene el formato esperado.',
      'CONVERSION_MENSUAL_CONTRACT',
    )
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
 * gerencia y el lector. El front no lo infiere de su propio rol.
 */
export async function listarMetricasConversionesEquipo(
  desde: string,
  hasta: string,
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
      'Las métricas de reuniones no tienen el formato esperado.',
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
  if (
    !resultado.success
    || resultado.output.ventana_convertidos_dias !== VENTANA_CONVERTIDOS_DIAS
  ) {
    const fallo = new CrmApiError(
      'El resumen de cartera no tiene el formato esperado.',
      'RESUMEN_CARTERA_CONTRACT',
    )
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
export async function listarColaAccion(
  pLimite = LIMITE_COLA_ACCION,
  signal?: AbortSignal,
): Promise<ColaAccion> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('cola_accion_fn', { p_limite: pLimite })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.metricas.cola_accion_fallido')
  const resultado = v.safeParse(ColaAccionSchema, data)
  if (!resultado.success || resultado.output.p_limite !== pLimite) {
    const fallo = new CrmApiError(
      'La cola de acción no tiene el formato esperado.',
      'COLA_ACCION_CONTRACT',
    )
    registrarError('crm.metricas.cola_accion_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Métricas por vendedor + comparativa de equipos (RPC crm.metricas_vendedores_fn,
 * F1b). El payload viaja SIN nombres (el front une con su roster) y con la
 * ventana de convertidos de 45 días, que se CERTIFICA contra la del front —
 * un ranking y unos tiles con cortes distintos en la misma pantalla serían
 * números que se contradicen.
 */
export async function listarMetricasVendedores(
  signal?: AbortSignal,
): Promise<MetricasVendedoresPayload> {
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
  ) {
    const fallo = new CrmApiError(
      'Las métricas por vendedor no tienen el formato esperado.',
      'METRICAS_VENDEDORES_CONTRACT',
    )
    registrarError('crm.metricas.vendedores_fuera_de_contrato', fallo)
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
    const fallo = new CrmApiError(
      'El resumen de la cola no tiene el formato esperado.',
      'RESUMEN_REPARTO_CONTRACT',
    )
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
  const capacidadValida = capacidad == null
    || (Number.isInteger(capacidad) && capacidad >= 1 && capacidad <= 1000)
  if (!idValido || !capacidadValida) {
    throw new CrmApiError(
      'La capacidad debe estar entre 1 y 1000 leads, o quedar sin configurar.',
      'CAPACIDAD_INVALIDA',
    )
  }

  const { data, error } = await cliente().schema('crm').rpc(
    'actualizar_capacidad_leads_objetivo',
    {
      p_analista_id: analistaId,
      // SIN default: el null explícito ES el mensaje («quedar sin configurar»).
      p_capacidad_leads_objetivo: nuloExplicito(capacidad),
    },
  )

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
      fallo = new CrmApiError(
        'No se pudo actualizar la capacidad del analista.',
        error.code || 'POSTGREST_ERROR',
      )
    }
    registrarError('crm.equipo.capacidad_actualizar_fallido', fallo, { pg: error.code ?? '' })
    throw fallo
  }

  const respuesta = v.safeParse(v.strictTuple([CapacidadActualizadaSchema]), data)
  if (
    !respuesta.success
    || respuesta.output[0].perfil_id !== analistaId
    || respuesta.output[0].capacidad_leads_objetivo !== capacidad
  ) {
    const fallo = new CrmApiError(
      'La capacidad actualizada no tiene el formato esperado.',
      'CAPACIDAD_CONTRACT',
    )
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
  /** Siempre 'PEN': en cooperativas solo se invierte en soles. Se manda igual
   * porque el servidor lo valida (un bundle viejo con USD merece rechazo claro,
   * no que le cambiemos la moneda por debajo). */
  moneda: 'PEN'
  documentoTipo: TipoDocumento
  documento: string
  nombre: string
  /** N.º de operación del depósito: OBLIGATORIO y único por cooperativa. */
  numeroTransaccion: string
  /** Certificado de la coop: opcional, para papeleo. */
  referencia?: string | null
  /** 'YYYY-MM-DD'; el servidor exige fecha futura. */
  venceEn?: string | null
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
export async function convertirLeadExterno(
  datos: ConvertirLeadExternoDatos,
): Promise<CierreExternoCreado> {
  const documento = datos.documento.trim().toUpperCase()
  const nombre = datos.nombre.trim()
  const numeroTransaccion = datos.numeroTransaccion.trim()
  // ⚠️ La igualdad EXACTA no sirve para decidir la escala de un decimal: en
  // coma flotante `10000.03 * 100` da 1000003.0000000001, así que el formulario
  // acusaba tres decimales a un monto perfectamente válido. Se compara con una
  // tolerancia mucho menor que un céntimo: 10000.035 sigue cayendo.
  const montoValido = Number.isFinite(datos.monto)
    && datos.monto > 0
    && Math.abs(Math.round(datos.monto * 100) - datos.monto * 100) < 1e-6
  if (!montoValido) {
    throw new CrmApiError(
      'El monto invertido debe ser mayor que cero, con máximo 2 decimales.',
      'CIERRE_EXTERNO_MONTO_INVALIDO',
    )
  }
  if (numeroTransaccion === '') {
    throw new CrmApiError(
      'El número de operación del depósito es obligatorio.',
      'CIERRE_EXTERNO_TRANSACCION_INVALIDA',
    )
  }
  if (!TIPOS_DOCUMENTO[datos.documentoTipo].regex.test(documento)) {
    throw new CrmApiError(
      TIPOS_DOCUMENTO[datos.documentoTipo].error,
      'CIERRE_EXTERNO_DOCUMENTO_INVALIDO',
    )
  }
  if (nombre === '') {
    throw new CrmApiError(
      'El nombre completo es obligatorio.',
      'CIERRE_EXTERNO_NOMBRE_INVALIDO',
    )
  }

  const { data, error } = await cliente().schema('crm').rpc('convertir_lead_externo', sinIndefinidos({
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
    p_nota: datos.nota?.trim() || undefined,
  }))

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
      fallo = new CrmApiError(
        'El lead no existe o está fuera de tu ámbito.',
        'LEAD_FUERA_DE_AMBITO',
      )
    } else {
      fallo = new CrmApiError(
        'No se pudo registrar el cierre en la cooperativa.',
        error.code || 'POSTGREST_ERROR',
      )
    }
    registrarError('crm.cierres_externos.convertir_fallido', fallo, { pg: error.code ?? '' })
    throw fallo
  }

  const respuesta = v.safeParse(CierreExternoCreadoSchema, data)
  if (
    !respuesta.success
    || respuesta.output.lead_id !== datos.leadId
    || respuesta.output.cooperativa !== datos.cooperativa
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
  /** Siempre 'PEN' (solo soles en cooperativas). */
  moneda: 'PEN'
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
export async function corregirCierreExterno(
  datos: CorregirCierreExternoDatos,
): Promise<{ cierreId: string }> {
  const numeroTransaccion = datos.numeroTransaccion.trim()
  if (numeroTransaccion === '') {
    throw new CrmApiError(
      'El número de operación del depósito es obligatorio.',
      'CIERRE_EXTERNO_TRANSACCION_INVALIDA',
    )
  }

  const { data, error } = await cliente().schema('crm').rpc('corregir_cierre_externo', {
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
      fallo = new CrmApiError(
        'No se pudo corregir el cierre externo.',
        error.code || 'POSTGREST_ERROR',
      )
    }
    registrarError('crm.cierres_externos.corregir_fallido', fallo, { pg: error.code ?? '' })
    throw fallo
  }

  const respuesta = v.safeParse(
    v.object({ ok: v.literal(true), cierre_id: v.pipe(v.string(), v.uuid()) }),
    data,
  )
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
 * cierre deja de contar en la cuota Y en la conversión del vendedor.
 *
 * NO borra la fila ni reabre el lead —en el CRM un convertido es terminal por
 * diseño— y es de UNA SOLA DIRECCIÓN: no se des-anula. Por eso el motivo es
 * obligatorio aquí y en el servidor: esto le quita dinero a una persona.
 */
export async function anularCierreExterno(
  datos: AnularCierreExternoDatos,
): Promise<{ cierreId: string }> {
  const motivo = datos.motivo.trim()
  if (motivo === '') {
    throw new CrmApiError(
      'Escribe el motivo de la anulación.',
      'CIERRE_EXTERNO_MOTIVO_REQUERIDO',
    )
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
      fallo = new CrmApiError(
        'No se pudo anular el cierre externo.',
        error.code || 'POSTGREST_ERROR',
      )
    }
    registrarError('crm.cierres_externos.anular_fallido', fallo, { pg: error.code ?? '' })
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
  /** Los contratos que dejan de acreditarle al vendedor. Puede venir VACÍO y
   *  seguir siendo correcto: la conversión baja igual (sale del ledger), pero
   *  no había contrato que descontar. */
  contratosAfectados: string[]
  afectaCuota: boolean
}

/**
 * El freno de gerencia contra un cierre de AVANCE por error de gestión o mala
 * práctica: ese cierre deja de acreditarle al vendedor en la cuota Y en la
 * conversión.
 *
 * Va por LEAD y no por cierre porque en Avance no hay fila de cierre — el cierre
 * ES el lead convertido, y su capital vive en `public.contratos`.
 *
 * NO mueve dinero real: el contrato y el cliente siguen intactos. NO reabre el
 * lead (un convertido es terminal por diseño) y es de UNA SOLA DIRECCIÓN.
 */
export async function anularCierreAvance(
  datos: AnularCierreAvanceDatos,
): Promise<CierreAvanceAnulado> {
  const motivo = datos.motivo.trim()
  if (motivo === '') {
    throw new CrmApiError(
      'Escribe el motivo de la anulación.',
      'CIERRE_AVANCE_MOTIVO_REQUERIDO',
    )
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
      fallo = new CrmApiError(
        'No se pudo anular el cierre.',
        error.code || 'POSTGREST_ERROR',
      )
    }
    registrarError('crm.cierres_avance.anular_fallido', fallo, { pg: error.code ?? '' })
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
    const fallo = new CrmApiError(
      'La anulación del cierre no tiene el formato esperado.',
      'CIERRE_AVANCE_CONTRACT',
    )
    registrarError('crm.cierres_avance.anular_fuera_de_contrato', fallo)
    throw fallo
  }
  return {
    leadId: respuesta.output.lead_id,
    contratosAfectados: respuesta.output.contratos_afectados,
    afectaCuota: respuesta.output.afecta_cuota,
  }
}

/**
 * El estado del cierre de unos leads (`crm.cierres_estado_fn`): qué canal y si
 * está anulado. Es la ÚNICA vía por la que el front puede enterarse de una
 * anulación — su tabla es deny-by-default a propósito.
 *
 * Devuelve solo los leads con algo que decir; la ausencia significa «cerró en
 * Avance y no está anulado» (ver `estadoDelCierre`, donde ese default se escribe
 * una vez).
 */
export async function obtenerCierresEstado(
  leadIds: readonly string[],
  signal?: AbortSignal,
): Promise<CierreEstado[]> {
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
    const respuestas = await Promise.all(
      lotes.map((lote) => obtenerCierresEstado(lote, signal)),
    )
    return respuestas.flat()
  }

  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('cierres_estado_fn', {
    p_lead_ids: leadIds as string[],
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw falloMetricas(error, 'crm.cierres_estado.consulta_fallida')

  const resultado = v.safeParse(CierresEstadoSchema, data)
  if (!resultado.success) {
    const fallo = new CrmApiError(
      'El estado de los cierres no tiene el formato esperado.',
      'CIERRE_ESTADO_CONTRACT',
    )
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
export async function obtenerCierresExternos(
  periodo: string,
  signal?: AbortSignal,
): Promise<CierresExternos> {
  if (!PERIODO_MENSUAL_RE.test(periodo)) {
    const fallo = new CrmApiError(
      'El período de los cierres externos no es válido.',
      'PERIODO_METRICAS_INVALIDO',
    )
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
    const fallo = new CrmApiError(
      'Los cierres externos no tienen el formato esperado.',
      'CIERRES_EXTERNOS_CONTRACT',
    )
    registrarError('crm.cierres_externos.fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}
