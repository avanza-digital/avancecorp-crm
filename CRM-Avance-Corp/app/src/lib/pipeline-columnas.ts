// lib/pipeline-columnas.ts — las COLUMNAS del tablero (Pipeline), que no son
// lo mismo que las etapas.
//
// Pedido de los analistas (01/10/2026): entre «Nuevo» y «Contactado» faltaba el
// sitio de los leads que YA se intentaron contactar (llamada sin respuesta,
// WhatsApp enviado) y cuyo cliente todavía no respondió. Esa columna,
// «Gestionado», NO es una etapa guardada: por dentro el lead sigue con
// `etapa = 'nuevo'`. Por eso vive aquí y no en `ETAPAS` (lib/tipos.ts), que es
// el espejo del CHECK de la base y de él dependen plazos, cola, embudo y
// configuración. El lead llega a «Gestionado» SOLO, al registrar el intento;
// nadie lo arrastra hasta ahí.
//
// ⚠️ LA FUENTE DE VERDAD ES EL SERVIDOR. En sesión real cada columna es una
// lista servida por `crm.cartera_filtrada_fn`, y qué mitad de `nuevo` le toca
// lo decide su parámetro `p_gestion`. Las funciones de abajo son el ESPEJO de
// esa regla para el modo demo (sin Supabase): si la regla cambia allá, cambia
// aquí EN LA MISMA ENTREGA, o la demo enseña un tablero que no existe.
//
// La regla («gestión vigente»):
//   · el lead tiene titular (`vendedor_id`) — sin titular no hay gestión;
//   · y hay una actividad de CONTACTO (los cinco de TIPOS_CONTACTO; una `nota`
//     no cuenta) registrada desde que ese titular recibió el lead;
//   · y esa actividad NO está deshecha: un resultado de llamada deshecho
//     (`metadata.deshecho_en`) «no ocurrió» y devuelve el lead a «Nuevo».
// Decisión de Miguel: un lead REASIGNADO que el analista anterior ya intentó es
// «Nuevo» para el analista actual. Solo cuenta lo gestionado en la tenencia
// vigente — la que el servidor sella en `crm.leads.tenencia_desde` y reinicia
// al cambiar de dueño y al reabrir un descartado.
import type { GestionCartera } from './cartera-keyset'
import { ETAPA_INFO, ETAPAS, TIPOS_CONTACTO_K, type Actividad, type EtapaActiva, type Lead } from './tipos'

/** Clave de columna: una etapa activa o la columna calculada «Gestionado». */
export type ClaveColumna = EtapaActiva | 'gestionado'

export interface ColumnaTablero {
  /** Identidad de la columna en pantalla (lista servida, páginas, arrastre). */
  k: ClaveColumna
  label: string
  color: string
  /** Etapa GUARDADA de los leads que muestra: lo único que la base persiste. */
  etapa: EtapaActiva
  /** Mitad de la etapa que le toca (`p_gestion`). Ausente = la etapa entera, y no viaja. */
  gestion?: GestionCartera
  /**
   * ¿Se puede LLEVAR un lead a esta columna (arrastre, menú «Mover a», alta)?
   * Una columna calculada no es destino: se llena sola.
   */
  esDestino: boolean
}

/**
 * Color propio de «Gestionado»: turquesa oscuro (azul petróleo).
 *
 * Es el cuarto color categórico que el CRM ya tiene (`--chart-4`, #0891b2), un
 * paso más oscuro: el original da 3,5:1 sobre el fondo y este se usa también
 * como TEXTO (el capital de la cabecera), donde hace falta 4,5:1 — mide 5,0:1
 * sobre el fondo de la página y 4,7:1 sobre el carril de la columna.
 * Se distingue del gris de «Nuevo», el azul de «Contactado», el morado de
 * «Cita agendada» y el ámbar de «Entrevista realizada», y no toca rojo ni ámbar
 * (reservados a la urgencia) ni verde (el CRM no lo usa).
 */
export const COLOR_GESTIONADO = '#0e7490'

/**
 * Columnas del tablero, en orden. Las etapas reales salen de `ETAPAS` (fuente
 * única de rótulo y color); solo `nuevo` se parte en dos mitades que el
 * servidor distingue por la gestión vigente.
 */
export const COLUMNAS_TABLERO: readonly ColumnaTablero[] = ETAPAS.flatMap((e): ColumnaTablero[] =>
  e.k === 'nuevo'
    ? [
        { k: 'nuevo', label: e.label, color: e.color, etapa: 'nuevo', gestion: 'sin_gestion', esDestino: true },
        { k: 'gestionado', label: 'Gestionado', color: COLOR_GESTIONADO, etapa: 'nuevo', gestion: 'con_gestion', esDestino: false },
      ]
    : [{ k: e.k, label: e.label, color: e.color, etapa: e.k, esDestino: true }],
)

const ETAPAS_ACTIVAS_K: ReadonlySet<string> = new Set(ETAPAS.map((e) => e.k))
const esEtapaActiva = (etapa: string): etapa is EtapaActiva => ETAPAS_ACTIVAS_K.has(etapa)

type LeadDeTenencia = Pick<Lead, 'id' | 'creado_en' | 'tenencia_desde'>
type ActividadDeGestion = Pick<Actividad, 'lead_id' | 'tipo' | 'creado_en'> & Partial<Pick<Actividad, 'detalle' | 'metadata'>>

/**
 * ¿Es un resultado de llamada DESHECHO? Lo deshecho «no ocurrió»: el servidor
 * lo descarta con `not (metadata ? 'deshecho_en')` y el store demo estampa esa
 * misma clave al deshacer. Como el `?` de jsonb, basta con que la clave exista
 * (también con valor nulo); una clave `undefined` no viaja en JSON y no cuenta.
 */
function estaDeshecha(a: ActividadDeGestion): boolean {
  return a.metadata != null && a.metadata.deshecho_en !== undefined
}

// Cómo deja el store demo una REAPERTURA en el timeline: un `cambio_etapa` cuyo
// detalle empieza por la etapa «Descartado» (`reabrir` y el deshacer de un
// descarte, en lib/store.tsx, lo arman con este mismo rótulo de ETAPA_INFO).
const PREFIJO_REAPERTURA = `${ETAPA_INFO.descartado.label} → `

/**
 * ¿Esta fila del timeline abre un episodio de tenencia? El servidor reinicia
 * `tenencia_desde` al cambiar de dueño y al reabrir un descartado
 * (`private.trg_leads_tenencia_desde`); en demo esos dos hechos solo quedan
 * escritos como actividades del sistema.
 */
function abreTenencia(a: ActividadDeGestion): boolean {
  if (a.tipo === 'reasignacion') return true
  return a.tipo === 'cambio_etapa' && typeof a.detalle === 'string' && a.detalle.startsWith(PREFIJO_REAPERTURA)
}

/**
 * Instante (epoch ms) desde el que el titular ACTUAL tiene el lead. `NaN` si no
 * hay ninguna fecha confiable de la que partir.
 *
 * En sesión real ese instante es `tenencia_desde`, que sella el servidor. El
 * modo demo NO lo trae (y su store tampoco lo escribe al reasignar ni al
 * reabrir), así que se reconstruye con lo que el demo sí tiene. Tres casos, y
 * no son intercambiables:
 *   · campo AUSENTE (`undefined`: los leads demo): respaldo `creado_en` — el
 *     mismo que usan los demás espejos demo (`demo-sla`,
 *     `leads-recibidos-analista`, `gestion-diaria-analista`), y lo que el
 *     servidor sella cuando un lead nace ya con su analista;
 *   · NULO EXPLÍCITO: es el servidor diciendo que no hay tenencia (sin dueño,
 *     cerrado o dado de baja). Conserva su significado de contrato: sin
 *     tenencia no hay gestión, y ni `creado_en` ni el timeline la inventan;
 *   · sello presente: manda él. Si es ilegible no se sustituye por otra fecha.
 * Sobre el campo ausente o el sello, gana el ÚLTIMO hecho del timeline que abre
 * una tenencia (una `reasignacion` o una reapertura) si es posterior. Sin este
 * paso, reasignar un lead en la demo le dejaría al analista nuevo los intentos
 * del anterior — lo contrario de la regla. El reloj del titular actual nunca
 * corre hacia atrás (misma idea que `referenciaEspera` en lib/inteligencia).
 *
 * DIVERGENCIA CONOCIDA con el servidor, y aceptada: allí la tenencia también se
 * reinicia al REACTIVAR un lead dado de baja, y el demo no tiene ese flujo.
 */
export function inicioTenencia(lead: LeadDeTenencia, actividades: readonly ActividadDeGestion[]): number {
  if (lead.tenencia_desde === null) return Number.NaN
  let inicio = Date.parse(lead.tenencia_desde ?? lead.creado_en)
  for (const a of actividades) {
    if (a.lead_id !== lead.id || !abreTenencia(a)) continue
    const movimiento = Date.parse(a.creado_en)
    // `!(x <= inicio)` y no `x > inicio`: con `inicio` NaN también entra.
    if (Number.isFinite(movimiento) && !(movimiento <= inicio)) inicio = movimiento
  }
  return inicio
}

/**
 * ¿El titular actual ya intentó contactar a este lead? Espejo de la «gestión
 * vigente» de `crm.cartera_filtrada_fn` (`p_gestion = 'con_gestion'`).
 *
 * Recibe el lead y SUS actividades; si llega el timeline de más leads, las
 * ajenas se ignoran. Las fechas se comparan como INSTANTES (`Date.parse`), no
 * como texto: el servidor mezcla offsets (`-05:00`, `Z`) y comparar cadenas
 * daría por posterior una gestión que fue anterior.
 *
 * OJO con `ultimo_contacto_en`: NO sirve para deducir esto. Un lead puede
 * traer un último contacto posterior a su tenencia y no tener gestión vigente
 * (esa llamada se deshizo). Por eso aquí se mira cada actividad, no un sello.
 *
 * PRECISIÓN: compara en MILISEGUNDOS, que es lo que da `Date`. Basta porque este
 * espejo solo ve fechas que sella el propio demo con `Date` (el fixture y el
 * store demo). El servidor compara con microsegundos, y en sesión real decide
 * él: esta función NO se usa para repartir filas del servidor — dos sellos
 * separados por menos de un milisegundo se le harían simultáneos.
 */
export function tieneGestionVigente(
  lead: LeadDeTenencia & Pick<Lead, 'vendedor_id'>,
  actividades: readonly ActividadDeGestion[],
): boolean {
  if (lead.vendedor_id == null) return false
  const desde = inicioTenencia(lead, actividades)
  // Sin reloj de tenencia no se afirma una gestión que no se puede fechar.
  if (!Number.isFinite(desde)) return false
  return actividades.some(
    (a) => a.lead_id === lead.id && TIPOS_CONTACTO_K.has(a.tipo) && !estaDeshecha(a) && Date.parse(a.creado_en) >= desde,
  )
}

/**
 * Columna del tablero en la que cae un lead, o `null` si no va en el tablero
 * (cerrado o dado de baja). Función PURA: es la que pinta el modo demo.
 */
export function columnaDeLead(
  lead: LeadDeTenencia & Pick<Lead, 'vendedor_id' | 'etapa' | 'activo'>,
  actividades: readonly ActividadDeGestion[],
): ClaveColumna | null {
  if (!lead.activo || !esEtapaActiva(lead.etapa)) return null
  if (lead.etapa !== 'nuevo') return lead.etapa
  return tieneGestionVigente(lead, actividades) ? 'gestionado' : 'nuevo'
}

/**
 * Reparte los leads del tablero demo en sus columnas, de una pasada: indexa el
 * timeline por lead UNA vez en lugar de recorrerlo entero por cada tarjeta.
 * Cada lead cae en una sola columna y conserva el orden en que llegó.
 */
export function agruparPorColumna<L extends LeadDeTenencia & Pick<Lead, 'vendedor_id' | 'etapa' | 'activo'>>(
  leads: readonly L[],
  actividades: readonly ActividadDeGestion[],
): Record<ClaveColumna, L[]> {
  const porLead = new Map<string, ActividadDeGestion[]>()
  for (const a of actividades) {
    const suyas = porLead.get(a.lead_id)
    if (suyas) suyas.push(a)
    else porLead.set(a.lead_id, [a])
  }
  const columnas = Object.fromEntries(
    COLUMNAS_TABLERO.map((c) => [c.k, [] as L[]]),
  ) as Record<ClaveColumna, L[]>
  for (const lead of leads) {
    const k = columnaDeLead(lead, porLead.get(lead.id) ?? [])
    if (k) columnas[k].push(lead)
  }
  return columnas
}

/**
 * Etapa a la que pasa un lead al soltarlo (o «moverlo») en una columna; `null`
 * si ahí no pasa nada. Dos motivos para el `null`, y los dos importan:
 *   · la columna no es destino («Gestionado» se llena sola);
 *   · el lead YA está en esa etapa: «Nuevo» y «Gestionado» comparten la etapa
 *     `nuevo`, así que soltar de una a la otra no es un cambio de etapa y no
 *     debe llegar al servidor.
 */
export function etapaAlSoltar(
  lead: Pick<Lead, 'etapa'>,
  columna: Pick<ColumnaTablero, 'etapa' | 'esDestino'>,
): EtapaActiva | null {
  if (!columna.esDestino || lead.etapa === columna.etapa) return null
  return columna.etapa
}

/** Columnas que el menú «Mover a» ofrece para un lead: nunca la suya ni una calculada. */
export function destinosDeMovimiento(lead: Pick<Lead, 'etapa'>): ColumnaTablero[] {
  return COLUMNAS_TABLERO.filter((c) => etapaAlSoltar(lead, c) !== null)
}
