// Potencial del lead (Frío · Tibio · Estrella) — el CONTRATO del front con
// `crm.potencial_leads_fn` y los textos de la ficha.
//
// Por qué una lectura aparte: la marca vive en `crm.lead_potencial`, una tabla
// sin permisos para la Data API (se lee por su puerta), y las cuatro vistas que
// la pintan salen de tres fuentes distintas (cartera, ficha y cola del día).
// Meterla en cada fila obligaría a tocar las tres; así llega por ids, como el
// estado de los cierres (`lib/cierre-estado.ts`).
//
// Decisiones de contrato que NO son estilo:
// - `v.object` (no strict): una clave nueva del servidor no rompe un bundle viejo.
// - `nivel` y `origen` SÍ son picklist: un nivel nuevo cambia qué se pinta y eso
//   exige tocar este archivo en el MISMO release.
// - `habilitada: false` = la bandera del servidor está apagada: la pantalla no
//   pinta NADA del potencial. Es un estado, no un error.
// - Un ítem por cada lead pedido que la persona puede ver; `nivel: null` es
//   «sin marca», no «desconocido».
import * as v from 'valibot'
import { FechaHoraSchema, FechaSchema, UuidSchema } from './esquemas-rpc'

export const NIVELES_POTENCIAL = ['frio', 'tibio', 'estrella'] as const
export type NivelPotencial = (typeof NIVELES_POTENCIAL)[number]

/** Nombre comercial de cada nivel (decisión de Miguel, 30/09/2026). */
export const ETIQUETA_POTENCIAL: Record<NivelPotencial, string> = {
  frio: 'Frío',
  tibio: 'Tibio',
  estrella: 'Estrella',
}

const NivelSchema = v.picklist(NIVELES_POTENCIAL)

// ── Filtro de Leads por potencial ────────────────────────────────────────────

/**
 * Los cuatro valores de `p_potencial` de `crm.cartera_filtrada_fn`: un nivel o
 * «sin marca». En el orden en que se pintan: la escala de la ficha y, al final,
 * lo que falta clasificar.
 */
export const FILTROS_POTENCIAL = ['frio', 'tibio', 'estrella', 'sin_marca'] as const
export type FiltroPotencial = (typeof FILTROS_POTENCIAL)[number]

export const ETIQUETA_FILTRO_POTENCIAL: Record<FiltroPotencial, string> = {
  ...ETIQUETA_POTENCIAL,
  sin_marca: 'Sin marcar',
}

const ConteoSchema = v.pipe(v.number(), v.safeInteger(), v.minValue(0))

/**
 * `resumen.potencial` de la cartera: cuántos leads hay de cada nivel con los
 * DEMÁS filtros puestos. El servidor los cuenta ANTES de aplicar el filtro de
 * potencial, así que no cambian al elegir un nivel; `filtro` es el eco del
 * pedido. Solo viaja con la bandera del potencial encendida.
 */
export const ConteosPotencialSchema = v.object({
  filtro: v.nullable(v.picklist(FILTROS_POTENCIAL)),
  estrella: ConteoSchema,
  tibio: ConteoSchema,
  frio: ConteoSchema,
  sin_marca: ConteoSchema,
})
export type ConteosPotencial = v.InferOutput<typeof ConteosPotencialSchema>

/** Los cuatro conteos sumados: el total de la lista SIN el filtro de potencial. */
export function totalConteosPotencial(conteos: ConteosPotencial): number {
  return conteos.estrella + conteos.tibio + conteos.frio + conteos.sin_marca
}

/** Conteos por nivel de un conjunto de leads (espejo demo de `resumen.potencial`). */
export function contarPotencial(
  leadIds: readonly string[],
  nivelDe: (leadId: string) => NivelPotencial | null | undefined,
  filtro: FiltroPotencial | null,
): ConteosPotencial {
  const conteos: ConteosPotencial = { filtro, estrella: 0, tibio: 0, frio: 0, sin_marca: 0 }
  for (const id of leadIds) conteos[nivelDe(id) ?? 'sin_marca'] += 1
  return conteos
}

export const PotencialLeadSchema = v.object({
  lead_id: UuidSchema,
  /** null = el lead no tiene marca. */
  nivel: v.nullable(NivelSchema),
  /** 'caducidad' = la marca bajó sola por días sin gestión. */
  origen: v.nullable(v.picklist(['manual', 'caducidad'])),
  /** El último nivel que puso una persona (para «bajó sola de X a Y»). */
  nivel_marcado: v.nullable(NivelSchema),
  marcado_en: v.nullable(FechaHoraSchema),
  /** Días completos de lunes a sábado sin gestión. */
  dias_sin_gestion: v.nullable(v.pipe(v.number(), v.integer(), v.minValue(0))),
  /**
   * El nivel que tendrá el día de `baja_el`; null si es frío, no hay marca o el
   * lead está cerrado. Lo dice el SERVIDOR y no se deduce del nivel: una
   * Estrella con muchos días sin gestión puede llegar con `baja_a: 'frio'`.
   */
  baja_a: v.nullable(v.picklist(['tibio', 'frio'])),
  /**
   * Día (Lima) en que bajará si no hay gestión, contado desde la PRÓXIMA pasada
   * de la tarea (05:10 y 05:40 Lima): una marca ya vencida trae el día de hoy
   * antes de las 05:40 y el de mañana después.
   */
  baja_el: v.nullable(FechaSchema),
  puede_marcar: v.boolean(),
})

export const PotencialLeadsSchema = v.object({
  version: v.literal(1),
  habilitada: v.boolean(),
  items: v.array(PotencialLeadSchema),
})

export type PotencialLead = v.InferOutput<typeof PotencialLeadSchema>
export type PotencialLeads = v.InferOutput<typeof PotencialLeadsSchema>

/** El tope de ids que acepta `crm.potencial_leads_fn` por llamada. */
export const MAX_LEADS_POTENCIAL = 200

/** Bandera apagada (o servidor anterior a la puerta): nada que pintar. */
export const POTENCIAL_APAGADO: PotencialLeads = { version: 1, habilitada: false, items: [] }

/** Índice por lead, para cruzar contra las filas que hay en pantalla. */
export function indexarPotencial(items: readonly PotencialLead[]): Map<string, PotencialLead> {
  return new Map(items.map((item) => [item.lead_id, item]))
}

// ── Fechas de calendario ─────────────────────────────────────────────────────

const MS_DIA = 86_400_000

function aDiaUtc(fecha: string): number {
  const [anio, mes, dia] = fecha.split('-').map(Number)
  return Date.UTC(anio ?? 0, (mes ?? 1) - 1, dia ?? 1)
}

/** 'YYYY-MM-DD' desplazada N días (aritmética de calendario, sin zona). */
export function sumarDiasFecha(fecha: string, dias: number): string {
  return new Date(aDiaUtc(fecha) + dias * MS_DIA).toISOString().slice(0, 10)
}

// ── El instante optimista ────────────────────────────────────────────────────

/**
 * El ítem tal como queda en el instante en que la persona marca, ANTES de que
 * el servidor conteste: lo único que se sabe con certeza es el nivel que puso y
 * que el reloj vuelve a cero.
 *
 * NO predice cuándo ni a qué nivel bajará (`baja_a` y `baja_el` quedan en
 * null): esa regla vive solo en el servidor y aquí no se copia. Si un día
 * cambian los umbrales, la pantalla no miente ni un instante: mientras la marca
 * viaja la ficha dice «Guardando la marca…» y al terminar pinta lo que diga la
 * relectura.
 */
export function potencialRecienMarcado(
  base: Pick<PotencialLead, 'lead_id' | 'puede_marcar'>,
  nivel: NivelPotencial,
  ahora: number,
): PotencialLead {
  return {
    lead_id: base.lead_id,
    nivel,
    origen: 'manual',
    nivel_marcado: nivel,
    marcado_en: new Date(ahora).toISOString(),
    dias_sin_gestion: 0,
    baja_a: null,
    baja_el: null,
    puede_marcar: base.puede_marcar,
  }
}

// ── Textos de la ficha ───────────────────────────────────────────────────────

const DIAS_SEMANA = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'] as const
const MESES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
] as const

/** «lunes 6 de octubre» a partir de 'YYYY-MM-DD' (sin zona: es un día de calendario). */
export function diaEnPalabras(fecha: string): string {
  const d = new Date(aDiaUtc(fecha))
  return `${DIAS_SEMANA[d.getUTCDay()]} ${d.getUTCDate()} de ${MESES[d.getUTCMonth()]}`
}

function diasEnPalabras(dias: number): string {
  return dias === 1 ? '1 día' : `${dias} días`
}

/**
 * La nota que acompaña a la marca en la ficha: qué pasó con ella o qué le va a
 * pasar. `hoy` es el día de Lima ('YYYY-MM-DD'); `cerrado`, que el lead está
 * convertido o descartado (ahí la marca queda congelada).
 *
 * A qué nivel baja y qué día salen SIEMPRE de `baja_a` y `baja_el` del
 * servidor; aquí no se deduce nada del nivel.
 */
export function notaPotencial(item: PotencialLead, contexto: { cerrado: boolean; hoy: string }): string {
  const { nivel } = item
  if (nivel == null) {
    return item.puede_marcar && !contexto.cerrado
      ? 'Sin marcar. La cambian el analista del lead y su supervisor.'
      : 'Sin marcar.'
  }
  if (contexto.cerrado) return 'Lead cerrado: la marca ya no cambia.'
  if (item.origen === 'caducidad' && item.nivel_marcado != null && item.nivel_marcado !== nivel) {
    const tramo = `Bajó sola de ${ETIQUETA_POTENCIAL[item.nivel_marcado]} a ${ETIQUETA_POTENCIAL[nivel]}`
    return item.dias_sin_gestion == null ? `${tramo}.` : `${tramo}: ${diasEnPalabras(item.dias_sin_gestion)} sin gestión.`
  }
  if (nivel === 'frio') return 'Frío no baja más. Solo cambia si lo cambian el analista o su supervisor.'
  if (item.baja_a == null) return `Marcado como ${ETIQUETA_POTENCIAL[nivel]}.`
  const destino = ETIQUETA_POTENCIAL[item.baja_a]
  if (item.baja_el == null) return `Baja a ${destino} si no se gestiona (cuentan lunes a sábado).`
  if (item.baja_el <= contexto.hoy) return `Baja a ${destino} en la próxima madrugada si no se gestiona.`
  if (item.baja_el === sumarDiasFecha(contexto.hoy, 1)) return `Baja a ${destino} mañana si no se gestiona.`
  return `Baja a ${destino} el ${diaEnPalabras(item.baja_el)} si no se gestiona (cuentan lunes a sábado).`
}
