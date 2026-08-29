// F4.4 «Hoy del supervisor, sin ruido»: la TRAZABILIDAD para gerencia de los
// reconocimientos de alertas. La decisión de Miguel (F4.1): reconocer es un
// COMPROMISO con trazabilidad, no un botón de silencio — gerencia ve quién
// reconoció o pospuso qué alerta, cuándo y hasta cuándo rige.
//
// Reglas de la casa que este módulo custodia:
// · Los datos vienen de la vista de VIGENTES (el reloj de Postgres corta la
//   vigencia; gerencia lee todo por RLS). Aquí no se re-decide vigencia: se
//   PRESENTA lo que el servidor dice que aún gobierna.
// · «El último asiento por alerta manda» se resuelve por `secuencia` (nunca
//   por creado_en: empata al microsegundo) — se reutiliza la misma lógica
//   probada del supervisor. Un empate de secuencia es libro corrupto y esa
//   alerta NO se lista como compromiso: mostrar un ganador arbitrario haría
//   creer a gerencia que algo está atendido sin saberse qué.
// · Un alerta_id que no parsea NO se esconde: se lista con etiqueta genérica.
//   Ocultarlo convertiría un dato raro en silencio — y el silencio aquí es
//   «nadie se comprometió», que es mentira.
// · Gerencia NO puede recalcular «reaparece si empeora» (eso exige el estado
//   vivo de los grupos de cada supervisor): la fila lo dice como condición
//   («cede antes si el grupo empeora»), sin fingir un dato que no se tiene.
import type { AsientoReconocimiento } from './reconocimientos-alertas'
import {
  VIGENCIA_RECONOCIMIENTO_DIAS,
  ultimoAsientoPorAlerta,
} from './reconocimientos-alertas'

/** Etiqueta humana Y UNIDAD de la foto por tipo de alerta agrupada (los 4
 *  tipos que el servidor acepta en alerta_id). Estático a propósito: la traza
 *  describe la CLASE de compromiso, no el conteo vivo de aquel momento.
 *  La unidad importa (Codex F4.4): la foto de `sin_proxima_accion` cuenta
 *  ANALISTAS (la decisión del grupo es la conversación con cada uno), las
 *  demás cuentan leads — aplanar todo a «ítems» dejaba a gerencia adivinando. */
export const CATALOGO_TIPO_ALERTA: Record<string, { etiqueta: string; unidad: readonly [string, string] }> = {
  por_repartir: { etiqueta: 'Leads esperando reparto', unidad: ['lead', 'leads'] },
  lead_sin_responder: { etiqueta: 'Leads nuevos sin responder', unidad: ['lead', 'leads'] },
  tarea_vencida: { etiqueta: 'Leads con plazo vencido', unidad: ['lead', 'leads'] },
  sin_proxima_accion: { etiqueta: 'Leads sin próxima acción', unidad: ['analista', 'analistas'] },
}

/** Fallback visible para un alerta_id fuera del catálogo: jamás se oculta. */
export const ETIQUETA_TIPO_DESCONOCIDO = 'Alerta de la campana'
const UNIDAD_DESCONOCIDA: readonly [string, string] = ['ítem', 'ítems']

/** Tope de filas del listado de la API (crm-api.ts). Si el payload lo alcanza,
 *  la tarjeta debe DECIRLO: un recorte silencioso presenta la porción como
 *  total (Codex F4.4 B2). Con la vista de un-asiento-por-alerta llegar aquí
 *  exige ~250 supervisores — es un cinturón, no un camino esperado. */
export const TOPE_LISTADO_RECONOCIMIENTOS = 1000

export interface CompromisoSupervisor {
  /** id del asiento (para keys de UI). */
  id: string
  supervisorId: string
  etiqueta: string
  /** Qué cuenta la foto de este tipo: «3 leads», «2 analistas». */
  cuanto: string
  accion: 'reconocer' | 'posponer'
  severidad: 'critica' | 'atencion'
  creadoEn: number
  /** Hasta cuándo rige COMO MÁXIMO: posponer → su `hasta`; reconocer →
   *  creado_en + 7 días (el candado acotado de F4.1). Siempre el MENOR de
   *  ambos topes. Puede ceder ANTES si la alerta empeora — eso solo lo ve
   *  la campana del supervisor y la tarjeta lo dice como condición. */
  venceEn: number
}

/** `grupo:<tipo>:<id del supervisor>` — tolerante a propósito: el formato
 *  estricto ya lo selló el servidor al escribir; el mundo demo usa ids no
 *  UUID (`d-sup1`) y un tipo nuevo futuro no debe romper la traza. */
function parsearAlertaId(alertaId: string): { tipo: string; supervisorId: string } | null {
  const partes = /^grupo:([a-z_]+):(.+)$/.exec(alertaId)
  if (partes?.[1] == null || partes[2] == null) return null
  return { tipo: partes[1], supervisorId: partes[2] }
}

/**
 * Los compromisos que HOY gobiernan alertas, uno por alerta (el último asiento
 * manda), ordenados del más reciente al más antiguo. Entrada: los asientos de
 * la vista de vigentes tal como llegan (gerencia los ve todos por RLS).
 * `ahora` es el CINTURÓN contra la caché (Codex F4.4): entre refetch y refetch
 * un vencido seguiría en la copia local hasta 60 s — aquí se descarta. Un
 * reloj local adelantado oculta ANTES (nunca finge vigente); uno atrasado no
 * alarga nada: la vista del servidor ya cortó al servir.
 */
export function derivarCompromisos(
  asientos: readonly AsientoReconocimiento[],
  ahora: number,
): CompromisoSupervisor[] {
  const { ultimo, empatadas } = ultimoAsientoPorAlerta(asientos)
  const compromisos: CompromisoSupervisor[] = []
  for (const [alertaId, asiento] of ultimo) {
    if (empatadas.has(alertaId)) continue
    const partes = parsearAlertaId(alertaId)
    const creadoEn = Date.parse(asiento.creado_en)
    const topeCandado = creadoEn + VIGENCIA_RECONOCIMIENTO_DIAS * 86_400_000
    const hasta = asiento.hasta == null ? null : Date.parse(asiento.hasta)
    const venceEn = hasta == null ? topeCandado : Math.min(hasta, topeCandado)
    if (venceEn <= ahora) continue
    const catalogo = partes == null ? undefined : CATALOGO_TIPO_ALERTA[partes.tipo]
    const unidad = catalogo?.unidad ?? UNIDAD_DESCONOCIDA
    const n = asiento.miembros.length
    compromisos.push({
      id: asiento.id,
      supervisorId: partes?.supervisorId ?? '',
      etiqueta: catalogo?.etiqueta ?? ETIQUETA_TIPO_DESCONOCIDO,
      cuanto: `${n} ${n === 1 ? unidad[0] : unidad[1]}`,
      accion: asiento.accion,
      severidad: asiento.severidad,
      creadoEn,
      venceEn,
    })
  }
  return compromisos.sort((a, b) => b.creadoEn - a.creadoEn)
}

/** «3 compromisos · 2 supervisores» — o null sin compromisos (el estado vacío
 *  lo dice la tarjeta con sus palabras, no un contador en cero). Sin
 *  «vigentes»: la tarjeta no puede saber si un compromiso ya cedió por
 *  empeora — no promete lo que no ve (Codex F4.4 B4). Un supervisorId vacío
 *  (id corrupto pero visible) no cuenta como supervisor: inflaría el número. */
export function resumenCompromisos(compromisos: readonly CompromisoSupervisor[]): string | null {
  if (compromisos.length === 0) return null
  const supervisores = new Set(compromisos.map((c) => c.supervisorId).filter((id) => id !== '')).size
  const nCompromisos = `${compromisos.length} ${compromisos.length === 1 ? 'compromiso' : 'compromisos'}`
  if (supervisores === 0) return nCompromisos
  const nSupervisores = `${supervisores} ${supervisores === 1 ? 'supervisor' : 'supervisores'}`
  return `${nCompromisos} · ${nSupervisores}`
}

/** Mundo demo de la traza (gerencia demo o «ver ejemplo»): asientos con la
 *  misma FORMA del contrato, sobre los supervisores del roster demo. */
export function asientosDemoTrazabilidad(ahora: number): AsientoReconocimiento[] {
  const hace = (horas: number) => new Date(ahora - horas * 3_600_000).toISOString()
  return [
    {
      id: '00000000-0000-4000-8000-00000000d001',
      alerta_id: 'grupo:lead_sin_responder:d-sup1',
      accion: 'reconocer',
      miembros: ['l1', 'l2', 'l3'],
      severidad: 'critica',
      hasta: null,
      creado_en: hace(2),
      secuencia: 3,
    },
    {
      id: '00000000-0000-4000-8000-00000000d002',
      alerta_id: 'grupo:por_repartir:d-sup2',
      accion: 'posponer',
      miembros: ['l4', 'l5'],
      severidad: 'atencion',
      hasta: new Date(ahora + 26 * 3_600_000).toISOString(),
      creado_en: hace(20),
      secuencia: 2,
    },
    {
      id: '00000000-0000-4000-8000-00000000d003',
      alerta_id: 'grupo:tarea_vencida:d-sup1',
      accion: 'reconocer',
      miembros: ['l6'],
      severidad: 'atencion',
      hasta: null,
      creado_en: hace(30),
      secuencia: 1,
    },
  ]
}
