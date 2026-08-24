// F4.2 «Hoy del supervisor, sin ruido»: la lectura del LIBRO de
// reconocimientos (crm.alertas_reconocimientos, F4.1 en prod) y la lógica
// pura de «reconocer atenúa · posponer oculta · AMBOS ceden si empeora».
//
// Contratos que hereda del servidor (COMMENT de la tabla y MIGRACIONES.md):
//  · NINGÚN reconocimiento vige más de 7 DÍAS desde su creado_en — que sella
//    el servidor y el cliente no puede fechar. Es el CANDADO ACOTADO al
//    bloqueante de Codex F4.1 #1: el servidor valida la FORMA de la foto,
//    no su verdad; la vigencia corta hace inservible cualquier foto en falso.
//  · «El último asiento manda» se lee por `secuencia` (orden total del
//    libro), nunca por creado_en — clock_timestamp() empata al microsegundo.
//  · La foto de `miembros` son IDS (leads o vendedores), jamás nombres: la
//    comparación de «empeoró» es por conjunto de ids + severidad.
import * as v from 'valibot'
import type { AlertaCRM, SeveridadAlerta } from './alertas'

export const VIGENCIA_RECONOCIMIENTO_DIAS = 7

const VIGENCIA_MS = VIGENCIA_RECONOCIMIENTO_DIAS * 86_400_000

export type AccionReconocimiento = 'reconocer' | 'posponer'

/** Asiento del libro tal como lo sirve PostgREST. Estricto: la RLS ya acota
 *  al dueño supervisor; una clave inesperada es un bug de contrato. */
export const AsientoReconocimientoSchema = v.strictObject({
  id: v.pipe(v.string(), v.uuid()),
  alerta_id: v.string(),
  accion: v.picklist(['reconocer', 'posponer']),
  miembros: v.array(v.string()),
  severidad: v.picklist(['critica', 'atencion']),
  hasta: v.nullable(v.pipe(v.string(), v.isoTimestamp())),
  creado_en: v.pipe(v.string(), v.isoTimestamp()),
  secuencia: v.number(),
})

export const AsientosReconocimientoSchema = v.array(AsientoReconocimientoSchema)

export type AsientoReconocimiento = v.InferOutput<typeof AsientoReconocimientoSchema>

/** El reconocimiento que HOY gobierna una alerta, ya validado y con su
 *  vencimiento calculado — lo que la fila atenuada muestra como traza. */
export interface ReconocimientoVigente {
  accion: AccionReconocimiento
  creadoEn: string
  /** Cuándo deja de regir: min(creado_en + 7 días, hasta si es posposición). */
  venceEn: number
}

export interface LibroPorAlerta {
  ultimo: Map<string, AsientoReconocimiento>
  /** Alertas cuyo asiento GANADOR está empatado en secuencia con otro
   *  distinto: eso es imposible por la identity del servidor, así que es un
   *  libro corrupto (restauración, doble carga) — fail-loud: esas alertas
   *  SUENAN en vez de degradar a un ganador arbitrario (Codex F4.2 #6). */
  empatadas: Set<string>
}

/** El último asiento POR alerta según `secuencia` — el único que manda.
 *  Nunca por creado_en: puede empatar al microsegundo (contrato F4.1). */
export function ultimoAsientoPorAlerta(
  asientos: readonly AsientoReconocimiento[],
): LibroPorAlerta {
  const ultimo = new Map<string, AsientoReconocimiento>()
  const empatadas = new Set<string>()
  for (const asiento of asientos) {
    const actual = ultimo.get(asiento.alerta_id)
    if (!actual || asiento.secuencia > actual.secuencia) {
      ultimo.set(asiento.alerta_id, asiento)
      empatadas.delete(asiento.alerta_id)
    } else if (asiento.secuencia === actual.secuencia && asiento.id !== actual.id) {
      empatadas.add(asiento.alerta_id)
    }
  }
  return { ultimo, empatadas }
}

const PESO_SEVERIDAD: Record<SeveridadAlerta, number> = { atencion: 0, critica: 1 }

/**
 * ¿Este asiento todavía gobierna esta alerta? Null = la alerta suena entera.
 * Cede — a propósito y en este orden de baratura — cuando:
 *  1. caducó (creado_en + 7 días quedó atrás, el candado acotado);
 *  2. era posposición y su `hasta` ya pasó;
 *  3. EMPEORÓ: la severidad actual supera la reconocida, o el grupo tiene
 *     un miembro que no estaba en la foto. Un miembro que SALIÓ no revive
 *     nada (mejorar no despierta alertas); uno nuevo siempre sí.
 * Una fecha ilegible en el asiento también lo anula: un dato corrupto jamás
 * se convierte en silencio (misma regla que las alertas de tiempo).
 */
export function reconocimientoVigente(
  alerta: Pick<AlertaCRM, 'severidad' | 'miembros'>,
  asiento: AsientoReconocimiento | undefined,
  ahora: number,
): ReconocimientoVigente | null {
  if (!asiento || !Number.isFinite(ahora)) return null
  // Solo las alertas AGRUPADAS (con foto de miembros) participan del libro.
  if (alerta.miembros == null) return null

  const creado = Date.parse(asiento.creado_en)
  if (!Number.isFinite(creado)) return null
  const caduca = creado + VIGENCIA_MS
  if (caduca <= ahora) return null

  let venceEn = caduca
  if (asiento.accion === 'posponer') {
    const hasta = asiento.hasta == null ? Number.NaN : Date.parse(asiento.hasta)
    if (!Number.isFinite(hasta) || hasta <= ahora) return null
    venceEn = Math.min(caduca, hasta)
  }

  if (PESO_SEVERIDAD[alerta.severidad] > PESO_SEVERIDAD[asiento.severidad]) return null
  const foto = new Set(asiento.miembros)
  if (alerta.miembros.some((miembro) => !foto.has(miembro))) return null

  return { accion: asiento.accion, creadoEn: asiento.creado_en, venceEn }
}

export interface AlertasConReconocimientos {
  /** Lo que la pantalla PINTA: activas primero, reconocidas atenuadas al
   *  final (reconocer nunca borra — deja rastro). Las pospuestas no están:
   *  posponer oculta hasta su fecha. */
  visibles: AlertaCRM[]
  /** Lo que la campana CUENTA: solo las que piden acción hoy. */
  pendientes: number
  /** Cuántas alertas están OCULTAS por posposición vigente: la pantalla lo
   *  dice en una línea — un vacío que calla una pospuesta afirma algo falso
   *  (Codex F4.2 #7). */
  pospuestas: number
}

/**
 * Aplica el libro a las alertas derivadas. Con el libro vacío (o caído: el
 * caller pasa [] — degradación honesta, un fallo de lectura enseña TODO en
 * vez de ocultar de más) devuelve las alertas tal cual.
 */
export function aplicarReconocimientos(
  alertas: readonly AlertaCRM[],
  asientos: readonly AsientoReconocimiento[],
  ahora: number,
): AlertasConReconocimientos {
  const { ultimo, empatadas } = ultimoAsientoPorAlerta(asientos)
  const activas: AlertaCRM[] = []
  const atenuadas: AlertaCRM[] = []
  let pospuestas = 0
  for (const alerta of alertas) {
    const vigente = empatadas.has(alerta.id)
      ? null // libro corrupto para ESTA alerta: suena, no se adivina.
      : reconocimientoVigente(alerta, ultimo.get(alerta.id), ahora)
    if (vigente == null) activas.push(alerta)
    else if (vigente.accion === 'reconocer') atenuadas.push({ ...alerta, reconocimiento: vigente })
    // posponer vigente: oculta — ni lista ni campana hasta su fecha.
    else pospuestas += 1
  }
  return { visibles: [...activas, ...atenuadas], pendientes: activas.length, pospuestas }
}

/** «Se reactiva el 30 de agosto» / «reaparece si empeora» — la traza de la
 *  fila atenuada. Fecha en Lima, como todo lo que lee un humano en el CRM. */
export function textoVencimiento(venceEn: number): string {
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    day: 'numeric',
    month: 'long',
  }).format(venceEn)
}
