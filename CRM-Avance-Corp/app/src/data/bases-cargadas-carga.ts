// La carga de un archivo en lotes (F5): `crear_base` y después `cargar_base_lote` de 100 en 100, en orden. Cada envío
// lleva un `p_operacion_id` FIJO desde que se arma el plan: si la red se corta después de que el servidor guardó un lote,
// repetirlo devuelve la MISMA respuesta (replay) y nunca carga dos veces. Dos reglas de reintento:
//  · 55P03 (otro lote de la misma base en curso: el servidor no espera, NOWAIT) y los transitorios → se reintenta SOLO,
//    con espera creciente, hasta {@link MAX_REINTENTOS_OCUPADO} veces;
//  · cualquier otro fallo (la red, una regla del servidor) → la carga se PAUSA en ese lote y quien carga decide
//    «Reintentar» (mismo id) o cerrar: lo cargado se queda en la base.
// Lógica sin React: la pantalla le pasa las puertas y un `esperar` (las pruebas, uno instantáneo).
import { ErrorBases, CODIGO_OCUPADO, esFalloIncierto, esRechazoDefinitivo } from './bases-cargadas-api'
import type { FilaEnvio, ResultadoFila, RespuestaCargarLote, RespuestaCrearBase } from '@/lib/bases-cargadas'
import type { CrearBaseEntrada } from './bases-cargadas-api'
import { CrmApiError } from './crm-api'

export const MAX_REINTENTOS_OCUPADO = 5
/** Espera antes del reintento n (1, 2, 3…): 1,5 s · 3 s · 4,5 s… */
export const esperaReintento = (n: number): number => 1500 * n

export interface PlanCarga {
  crear: CrearBaseEntrada
  lotes: { operacionId: string; filas: FilaEnvio[] }[]
}

export interface AvanceCarga {
  baseId: string | null
  /** Lotes ya confirmados por el servidor (el siguiente por enviar es este índice). */
  lotesHechos: number
  filasHechas: number
  /** Los veredictos del servidor, fila a fila, en el orden en que llegaron. */
  resultados: ResultadoFila[]
  /** Reintentos automáticos del lote en curso (para decirlo en pantalla). */
  reintento: number
  /**
   * El paso en curso (crear la base o el lote `lotesHechos`) se ENVIÓ alguna vez sin respuesta: pudo hacerse. Solo lo
   * resuelve la respuesta del servidor para ESE id (éxito o replay del recibo) o un rechazo definitivo; un «otra operación
   * en curso» o un corte posterior lo dejan incierto (Codex F5 r2).
   */
  incierto: boolean
}

export const AVANCE_INICIAL: AvanceCarga = { baseId: null, lotesHechos: 0, filasHechas: 0, resultados: [], reintento: 0, incierto: false }

/** Cómo queda la incertidumbre del paso en curso tras un fallo: se enciende con lo incierto, se apaga SOLO con un rechazo
 *  definitivo y, con lo transitorio (55P03…), se conserva la que había. */
function inciertoTras(error: CrmApiError, antes: boolean): boolean {
  if (esFalloIncierto(error)) return true
  if (esRechazoDefinitivo(error)) return false
  return antes
}

export interface PuertasCarga {
  crearBase: (entrada: CrearBaseEntrada) => Promise<RespuestaCrearBase>
  cargarBaseLote: (entrada: { operacionId: string; baseId: string; filas: readonly FilaEnvio[] }) => Promise<RespuestaCargarLote>
  esperar: (ms: number) => Promise<void>
  /** Cada paso confirmado (y cada reintento automático), para pintar el progreso. */
  alAvanzar: (avance: AvanceCarga) => void
}

export type FinCarga =
  | { tipo: 'completa'; avance: AvanceCarga }
  | { tipo: 'pausada'; avance: AvanceCarga; error: CrmApiError }

function comoErrorBases(causa: unknown): CrmApiError {
  if (causa instanceof CrmApiError) return causa
  return new ErrorBases('No se pudo completar la carga. Vuelve a intentarlo: no se repite nada de lo ya hecho.', 'DESCONOCIDO')
}

/** ¿Se reintenta solo? Solo lo que el servidor dice que es pasajero (otra carga en curso, ocupado). */
function esPasajero(error: CrmApiError): boolean {
  return error.code === CODIGO_OCUPADO
}

/**
 * Antes de terminar una carga pausada con el lote `avance.lotesHechos` INCIERTO (`avance.incierto`: se envió y no hubo
 * respuesta): pudo quedar guardado. Se repite con su MISMO id (si ya estaba, el servidor devuelve su recibo). Resuelve:
 * el éxito (`confirmado`, con sus filas) o un rechazo definitivo (`confirmado`: no se guardó; queda «sin enviar»). Un
 * «otra operación en curso» o un corte NO resuelven (`confirmado: false`): la pantalla lo marca «sin confirmar».
 */
export async function confirmarLoteIncierto(plan: PlanCarga, avance: AvanceCarga, puertas: PuertasCarga): Promise<{ avance: AvanceCarga; confirmado: boolean }> {
  const lote = plan.lotes[avance.lotesHechos]
  if (!lote || avance.baseId === null || !avance.incierto) return { avance, confirmado: true }
  const baseId = avance.baseId
  const enviado = await conReintentos(() => puertas.cargarBaseLote({ operacionId: lote.operacionId, baseId, filas: lote.filas }), avance, puertas)
  if (!enviado.ok) {
    const resuelto = esRechazoDefinitivo(enviado.error)
    return { avance: { ...avance, reintento: 0, incierto: !resuelto }, confirmado: resuelto }
  }
  const nuevo: AvanceCarga = {
    baseId, lotesHechos: avance.lotesHechos + 1, filasHechas: avance.filasHechas + lote.filas.length,
    resultados: [...avance.resultados, ...enviado.valor.filas.map((f) => ({ fila: f.fila, veredicto: f.veredicto, motivo: f.motivo ?? null }))],
    reintento: 0, incierto: false,
  }
  puertas.alAvanzar(nuevo)
  return { avance: nuevo, confirmado: true }
}

/** Ejecuta una operación con los reintentos automáticos de lo pasajero. */
async function conReintentos<T>(operacion: () => Promise<T>, avance: AvanceCarga, puertas: PuertasCarga): Promise<{ ok: true; valor: T } | { ok: false; error: CrmApiError }> {
  for (let intento = 0; ; intento += 1) {
    try {
      return { ok: true, valor: await operacion() }
    } catch (causa: unknown) {
      const error = comoErrorBases(causa)
      if (!esPasajero(error) || intento >= MAX_REINTENTOS_OCUPADO) return { ok: false, error }
      puertas.alAvanzar({ ...avance, reintento: intento + 1 })
      await puertas.esperar(esperaReintento(intento + 1))
    }
  }
}

/**
 * Sigue la carga desde donde quedó (`desde`): crea la base si aún no existe y envía los lotes que faltan, en orden.
 * Devuelve el avance final: completa, o pausada en el lote que falló (para reintentarlo con el mismo id).
 */
export async function ejecutarCarga(plan: PlanCarga, desde: AvanceCarga, puertas: PuertasCarga): Promise<FinCarga> {
  let avance: AvanceCarga = { ...desde, reintento: 0 }
  if (avance.baseId === null) {
    const creada = await conReintentos(() => puertas.crearBase(plan.crear), avance, puertas)
    if (!creada.ok) return { tipo: 'pausada', avance: { ...avance, reintento: 0, incierto: inciertoTras(creada.error, avance.incierto) }, error: creada.error }
    avance = { ...avance, baseId: creada.valor.base_id, reintento: 0, incierto: false }
    puertas.alAvanzar(avance)
  }
  const baseId = avance.baseId as string
  for (let i = avance.lotesHechos; i < plan.lotes.length; i += 1) {
    const lote = plan.lotes[i]
    if (!lote) break
    const enviado = await conReintentos(() => puertas.cargarBaseLote({ operacionId: lote.operacionId, baseId, filas: lote.filas }), avance, puertas)
    if (!enviado.ok) return { tipo: 'pausada', avance: { ...avance, reintento: 0, incierto: inciertoTras(enviado.error, avance.incierto) }, error: enviado.error }
    avance = {
      baseId,
      lotesHechos: i + 1,
      filasHechas: avance.filasHechas + lote.filas.length,
      resultados: [...avance.resultados, ...enviado.valor.filas.map((f) => ({ fila: f.fila, veredicto: f.veredicto, motivo: f.motivo ?? null }))],
      reintento: 0,
      incierto: false,
    }
    puertas.alAvanzar(avance)
  }
  return { tipo: 'completa', avance }
}
