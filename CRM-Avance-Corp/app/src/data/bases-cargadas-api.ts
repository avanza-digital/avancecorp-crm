// «Bases cargadas» (F5): las puertas del servidor. Contrato FIJO en `BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md`.
//  · B8 (en producción 04/10): crm.crear_base, crm.cargar_base_lote (lote ≤ 100, base ≤ 5000), crm.armar_base_crm (≤ 2000).
//  · B9 (por llegar): crm.repartir_base, crm.recoger_de_base, crm.contactos_de_base.
//  · B10 (por llegar): crm.seguimiento_bases, crm.seguimiento_base, crm.seguimiento_base_detalle.
// Mientras B9/B10 no estén aplicadas, PostgREST responde PGRST202 (función desconocida): las LECTURAS devuelven `null`
// («disponible pronto», nunca una lista vacía que mienta) y las ESCRITURAS lanzan `NO_DISPONIBLE`. Sus tipos aún no salen de
// `gen:types`: se llaman con `rpcDelContrato` y la respuesta se valida con valibot (al aplicarse, se tipan solas).
// Todas las escrituras son idempotentes por `p_operacion_id` (el replay devuelve la misma respuesta): la pantalla fija el
// id de cada envío y lo repite en un reintento.
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import type { Json } from '@/lib/database.types'
import { registrarError } from '@/lib/observabilidad'
import { CrmApiError } from './crm-api'
import {
  ContactoBaseSchema,
  FilaDetalleSeguimientoSchema,
  FilaSeguimientoBaseSchema,
  FilaSeguimientoBasesSchema,
  RespuestaArmarBaseSchema,
  RespuestaCargarLoteSchema,
  RespuestaCrearBaseSchema,
  RespuestaRecogerSchema,
  RechazadoRepartoSchema,
  RespuestaRepartirSchema,
  type ContactoBase,
  type CifraSeguimiento,
  type EstadoContactos,
  type FilaDetalleSeguimiento,
  type FilaEnvio,
  type FilaSeguimientoBase,
  type FilaSeguimientoBases,
  type RepartoBase,
  type RespuestaArmarBase,
  type RespuestaCargarLote,
  type RespuestaCrearBase,
  type RespuestaRecoger,
  type RespuestaRepartir,
} from '@/lib/bases-cargadas'

/** Un fallo de las puertas de bases con el detalle que la pantalla necesita (disponibles, excluidos por motivo). */
export class ErrorBases extends CrmApiError {
  readonly detalle: unknown
  constructor(mensaje: string, code: string, detalle: unknown = null) {
    super(mensaje, code)
    this.name = 'ErrorBases'
    this.detalle = detalle
  }
}

/** Códigos que la pantalla trata distinto. */
export const CODIGO_NO_DISPONIBLE = 'NO_DISPONIBLE'
export const CODIGO_RED = 'RED'
export const CODIGO_OCUPADO = 'OCUPADO'

type ErrorPostgrest = { code?: string | null; message?: string | null; details?: string | null }
type RespuestaRpc = { data: unknown; error: ErrorPostgrest | null }
interface ConsultaRpc extends PromiseLike<RespuestaRpc> {
  abortSignal(signal: AbortSignal): ConsultaRpc
}

function cliente() {
  if (!sb) throw new ErrorBases('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  return sb
}

/**
 * Llamada a una puerta del CONTRATO que todavía no está en los tipos generados (B9/B10). El cuerpo viaja igual que con
 * `.rpc()` tipado; la respuesta se valida siempre con su esquema. Se retira cuando `gen:types` las conozca.
 */
function rpcDelContrato(nombre: string, args: Record<string, unknown>, signal?: AbortSignal): ConsultaRpc {
  const crm = cliente().schema('crm') as unknown as { rpc: (fn: string, a: Record<string, unknown>) => ConsultaRpc }
  const consulta = crm.rpc(nombre, args)
  return signal ? consulta.abortSignal(signal) : consulta
}

/** Una consulta cancelada es una cancelación, no un fallo que reportar. */
function lanzarSiCancelada(signal?: AbortSignal): void {
  if (!signal?.aborted) return
  throw signal.reason instanceof Error ? signal.reason : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

/** El `detail` de un 22023 del servidor (texto JSON o número); null si no se entiende. */
function detalleDe(error: ErrorPostgrest): unknown {
  const crudo = error.details?.trim()
  if (!crudo) return null
  try { return JSON.parse(crudo) as unknown } catch { return crudo }
}

/**
 * Traduce un fallo de las puertas de bases a un mensaje que se puede mostrar. Los textos del servidor ya vienen en
 * español y sin datos personales (22023, 23505, P0002): se muestran tal cual. Sin código (la red se cortó) → `RED`,
 * que la pantalla ofrece reintentar con el MISMO id de operación.
 */
export function aErrorBases(error: ErrorPostgrest, contexto: string): ErrorBases {
  const codigo = error.code ?? ''
  const mensajeServidor = error.message?.trim() || null
  let fallo: ErrorBases
  if (codigo === 'PGRST202') {
    fallo = new ErrorBases('Esta parte de «Bases» llega con la próxima actualización del servidor: disponible pronto.', CODIGO_NO_DISPONIBLE)
  } else if (codigo === '') {
    fallo = new ErrorBases('Se cortó la conexión. Revisa tu internet y vuelve a intentarlo: no se repite nada de lo ya hecho.', CODIGO_RED)
  } else if (codigo === '55P03') {
    fallo = new ErrorBases(mensajeServidor ?? 'Hay otra operación en curso sobre esta base; reintenta.', CODIGO_OCUPADO)
  } else if (codigo === '42501' || codigo === 'PGRST301') {
    fallo = new ErrorBases(mensajeServidor ?? 'No tienes permiso para esta acción.', 'SIN_PERMISO')
  } else if (codigo === 'P0002') {
    fallo = new ErrorBases(mensajeServidor ?? 'La base no existe o está fuera de tu ámbito.', 'FUERA_DE_AMBITO')
  } else if (codigo === '23505') {
    fallo = new ErrorBases(mensajeServidor ?? 'Ya hay una base viva con ese nombre.', 'NOMBRE_REPETIDO')
  } else if (codigo === '22023' || codigo === 'P0001') {
    fallo = new ErrorBases(mensajeServidor ?? 'El servidor rechazó el pedido.', 'REGLA_SERVIDOR', detalleDe(error))
  } else if (codigo === '40001' || codigo === '40P01' || codigo === '57014') {
    fallo = new ErrorBases('El servidor estaba ocupado y no terminó; vuelve a intentarlo (no se repite nada de lo ya hecho).', CODIGO_OCUPADO)
  } else {
    fallo = new ErrorBases('No se pudo completar la operación. Vuelve a intentarlo.', 'POSTGREST_ERROR')
  }
  registrarError(contexto, fallo, { pg: codigo })
  return fallo
}

function falloDeContrato(contexto: string, mensaje: string): ErrorBases {
  const fallo = new ErrorBases(mensaje, 'BASES_CONTRACT')
  registrarError(contexto, fallo)
  return fallo
}

/** Valida cada fila: una fuera de contrato no se pinta, pero se registra (la lista no se recorta en silencio). */
function filasValidas<T>(esquema: v.GenericSchema<unknown, T>, datos: unknown, contexto: string): T[] {
  const filas: T[] = []
  let invalidas = 0
  for (const cruda of Array.isArray(datos) ? datos : []) {
    const r = v.safeParse(esquema, cruda)
    if (r.success) filas.push(r.output)
    else invalidas += 1
  }
  if (invalidas > 0) registrarError(contexto, new Error(`${invalidas} filas descartadas`), { invalidas })
  return filas
}

/** Una lectura de B9/B10: `null` si el servidor aún no la tiene (PGRST202). */
async function leerDelContrato<T>(nombre: string, args: Record<string, unknown>, esquema: v.GenericSchema<unknown, T>, signal?: AbortSignal): Promise<T[] | null> {
  const { data, error } = await rpcDelContrato(nombre, args, signal)
  lanzarSiCancelada(signal)
  if (error?.code === 'PGRST202') return null
  if (error) throw aErrorBases(error, `crm.bases.${nombre}_fallido`)
  return filasValidas(esquema, data, `crm.bases.${nombre}_fuera_de_contrato`)
}

// ── B8 · cargar y armar (en producción) ────────────────────────────────────────────────────────────────────────
export interface CrearBaseEntrada {
  operacionId: string
  nombre: string
  /** Gerencia elige el supervisor dueño (E11); Supervisión no lo manda (la base es suya). */
  supervisorId?: string | null
  archivoNombre: string
}

/** Crea la base de un archivo (origen «archivo»). Devuelve su id y su supervisor dueño. */
export async function crearBase(entrada: CrearBaseEntrada): Promise<RespuestaCrearBase> {
  const { data, error } = await cliente().schema('crm').rpc('crear_base', {
    p_operacion_id: entrada.operacionId,
    p_nombre: entrada.nombre.trim(),
    p_origen: 'archivo',
    p_archivo_nombre: entrada.archivoNombre,
    ...(entrada.supervisorId ? { p_supervisor_id: entrada.supervisorId } : {}),
  })
  if (error) throw aErrorBases(error, 'crm.bases.crear_fallido')
  const r = v.safeParse(RespuestaCrearBaseSchema, data)
  if (!r.success) throw falloDeContrato('crm.bases.crear_fuera_de_contrato', 'El servidor no confirmó la base.')
  return r.output
}

/** Carga UN lote (≤ 100 filas). Cada fila vuelve con su veredicto; sin datos de otros leads. */
export async function cargarBaseLote(entrada: { operacionId: string; baseId: string; filas: readonly FilaEnvio[] }): Promise<RespuestaCargarLote> {
  const { data, error } = await cliente().schema('crm').rpc('cargar_base_lote', {
    p_operacion_id: entrada.operacionId,
    p_base_id: entrada.baseId,
    p_filas: entrada.filas as unknown as Json,
  })
  if (error) throw aErrorBases(error, 'crm.bases.cargar_lote_fallido')
  const r = v.safeParse(RespuestaCargarLoteSchema, data)
  if (!r.success) throw falloDeContrato('crm.bases.cargar_lote_fuera_de_contrato', 'El servidor no confirmó el lote.')
  return r.output
}

export interface ArmarBaseEntrada {
  operacionId: string
  nombre: string
  supervisorId?: string | null
  leadIds: readonly string[]
}

/**
 * Arma una base con descartados ELEGIBLES del CRM (E12). Si ninguno lo es, el servidor no crea nada (22023) y su
 * `detail` trae los excluidos por motivo: llega en `ErrorBases.detalle` con el código `SIN_ELEGIBLES`.
 */
export async function armarBaseCrm(entrada: ArmarBaseEntrada): Promise<RespuestaArmarBase> {
  const { data, error } = await cliente().schema('crm').rpc('armar_base_crm', {
    p_operacion_id: entrada.operacionId,
    p_nombre: entrada.nombre.trim(),
    p_lead_ids: [...entrada.leadIds],
    ...(entrada.supervisorId ? { p_supervisor_id: entrada.supervisorId } : {}),
  })
  if (error) {
    const fallo = aErrorBases(error, 'crm.bases.armar_fallido')
    const detalle = fallo.detalle as { excluidos_por_motivo?: unknown } | null
    if (error.code === '22023' && detalle && typeof detalle === 'object' && detalle.excluidos_por_motivo) {
      throw new ErrorBases(fallo.message, 'SIN_ELEGIBLES', detalle.excluidos_por_motivo)
    }
    throw fallo
  }
  const r = v.safeParse(RespuestaArmarBaseSchema, data)
  if (!r.success) throw falloDeContrato('crm.bases.armar_fuera_de_contrato', 'El servidor no confirmó la base armada.')
  return r.output
}

// ── B10 · seguimiento (lecturas; `null` = aún no en el servidor) ──────────────────────────────────────────────────
export function seguimientoBases(signal?: AbortSignal): Promise<FilaSeguimientoBases[] | null> {
  return leerDelContrato('seguimiento_bases', {}, FilaSeguimientoBasesSchema, signal)
}

export function seguimientoBase(baseId: string, signal?: AbortSignal): Promise<FilaSeguimientoBase[] | null> {
  return leerDelContrato('seguimiento_base', { p_base_id: baseId }, FilaSeguimientoBaseSchema, signal)
}

/** Lo que hay detrás de una cifra (de la base entera con `analistaId` null, o de un analista). */
export function seguimientoBaseDetalle(baseId: string, analistaId: string | null, cifra: CifraSeguimiento, signal?: AbortSignal): Promise<FilaDetalleSeguimiento[] | null> {
  return leerDelContrato('seguimiento_base_detalle', {
    p_base_id: baseId,
    ...(analistaId ? { p_analista_id: analistaId } : {}),
    p_cifra: cifra,
  }, FilaDetalleSeguimientoSchema, signal)
}

// ── B9 · repartir y recoger ──────────────────────────────────────────────────────────────────────────────────────
export function contactosDeBase(baseId: string, estado: EstadoContactos = 'sin_repartir', signal?: AbortSignal): Promise<ContactoBase[] | null> {
  return leerDelContrato('contactos_de_base', { p_base_id: baseId, p_estado: estado }, ContactoBaseSchema, signal)
}

/**
 * Reparte la base (todo o nada, hasta 500 contactos y 100 analistas por operación): en bloque («Ana 40 · Luis 30») o
 * individual. En bloque, si no alcanzan los disponibles, el servidor rechaza TODO (22023) con los disponibles en el `detail`
 * (el número en texto): llegan en `ErrorBases.detalle` (`SIN_DISPONIBLES`). En individual, si un contacto no es elegible,
 * tampoco reparte ninguno (22023, `detail = {"rechazados": [{lead_id, motivo}]}`): llegan en `detalle` (`RECHAZADOS`).
 */
export async function repartirBase(entrada: { operacionId: string; baseId: string; reparto: RepartoBase }): Promise<RespuestaRepartir> {
  const { data, error } = await rpcDelContrato('repartir_base', {
    p_operacion_id: entrada.operacionId,
    p_base_id: entrada.baseId,
    p_reparto: entrada.reparto,
  })
  if (error) {
    const fallo = aErrorBases(error, 'crm.bases.repartir_fallido')
    const disponibles = typeof fallo.detalle === 'number' ? fallo.detalle
      : typeof fallo.detalle === 'string' && /^\d+$/.test(fallo.detalle) ? Number(fallo.detalle)
        : typeof (fallo.detalle as { disponibles?: unknown } | null)?.disponibles === 'number' ? (fallo.detalle as { disponibles: number }).disponibles
          : null
    if (error.code === '22023' && disponibles !== null && entrada.reparto.modo === 'bloque') {
      throw new ErrorBases(`No alcanzan: hay ${disponibles} ${disponibles === 1 ? 'contacto disponible' : 'contactos disponibles'} para repartir (los que tienen seguimiento activo, veto o descanso no se reparten). No se repartió ninguno.`, 'SIN_DISPONIBLES', disponibles)
    }
    const rechazados = v.safeParse(v.object({ rechazados: v.array(RechazadoRepartoSchema) }), fallo.detalle)
    if (error.code === '22023' && rechazados.success && rechazados.output.rechazados.length > 0) {
      const n = rechazados.output.rechazados.length
      throw new ErrorBases(`${n === 1 ? 'Un contacto no se puede' : `${n} contactos no se pueden`} repartir ahora: no se repartió ninguno. Quítalos de la selección y vuelve a asignar.`, 'RECHAZADOS', rechazados.output.rechazados)
    }
    throw fallo
  }
  const r = v.safeParse(RespuestaRepartirSchema, data)
  if (!r.success) throw falloDeContrato('crm.bases.repartir_fuera_de_contrato', 'El servidor no confirmó el reparto.')
  return r.output
}

/** Devuelve a «sin repartir» lo que ese analista no tocó (sin intento y sin seguimiento activo). */
export async function recogerDeBase(entrada: { operacionId: string; baseId: string; analistaId: string }): Promise<RespuestaRecoger> {
  const { data, error } = await rpcDelContrato('recoger_de_base', {
    p_operacion_id: entrada.operacionId,
    p_base_id: entrada.baseId,
    p_analista_id: entrada.analistaId,
  })
  if (error) throw aErrorBases(error, 'crm.bases.recoger_fallido')
  const r = v.safeParse(RespuestaRecogerSchema, data)
  if (!r.success) throw falloDeContrato('crm.bases.recoger_fuera_de_contrato', 'El servidor no confirmó lo recogido.')
  return r.output
}
