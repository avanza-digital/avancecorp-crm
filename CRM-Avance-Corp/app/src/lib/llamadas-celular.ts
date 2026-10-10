// Llamadas desde el celular (F4-b) — contrato de las puertas de la pestaña «Llamadas del celular» y sus textos.
// Fuentes: crm.llamadas_celular_bandeja_fn (20261001212258, con la atención efectiva), crm.llamada_celular_detalle_fn
// (20261001160219), crm.llamadas_celular_resueltas_hoy_fn (20261005224330: paginada y por la hora de resolución),
// crm.actividades_con_llamada_celular_fn (20261005201010) y
// el `enlace` de crm.registrar_llamada_v5 (20261005155914 + 20261005182227). Aquí se valida la FORMA en la frontera y se
// arman los textos; el ámbito, la elegibilidad y el enlace los decide el servidor.
import * as v from 'valibot'
import { fechaLima, horaLima } from './agenda-derivada'
import { etiquetaResultado } from './resultado-llamada'

export const ATENCIONES = ['por_revisar', 'requiere_resultado', 'requiere_devolucion', 'registrado', 'descartado_con_motivo'] as const
export type Atencion = (typeof ATENCIONES)[number]
const IDENTIFICACIONES = ['identificado', 'ambiguo', 'sin_identificar'] as const
const VIAS = ['al_colgar', 'pestana', 'manual'] as const
export type ViaEnlace = (typeof VIAS)[number]

/** Lista cerrada del servidor (private.llamada_celular_descartar); «otro» exige escribir el motivo (≥ 3 caracteres). */
export const MOTIVOS_DESCARTE = [
  { clave: 'personal', etiqueta: 'Llamada personal' },
  { clave: 'no_comercial', etiqueta: 'No era comercial' },
  { clave: 'numero_de_prueba', etiqueta: 'Número de prueba' },
  { clave: 'error_captura', etiqueta: 'Error de captura' },
  { clave: 'otro', etiqueta: 'Otro motivo' },
] as const
export type MotivoDescarte = (typeof MOTIVOS_DESCARTE)[number]['clave']

export const FilaBandejaSchema = v.object({
  evento_id: v.string(),
  /**
   * El id que puso el celular (`C1-1790980958`). Lo agrega la décima (20261006150154): con él, registrar desde la
   * pestaña llama a la v5 y la llamada queda unida. Sin la décima no llega y la llamada sigue pendiente (se une con
   * «¿Es este su resultado?»). Opcional para que la pantalla funcione antes y después de aplicarla.
   */
  evento_origen_id: v.optional(v.string()),
  recibido_en: v.string(),
  /** Hora del reloj del celular; null si no la mandó. */
  ocurrio_en: v.nullable(v.string()),
  /** null = número oculto. */
  numero: v.nullable(v.string()),
  direccion: v.string(),
  estado_tecnico: v.string(),
  duracion_seg: v.nullable(v.number()),
  identificacion: v.picklist(IDENTIFICACIONES),
  /** La atención EFECTIVA para quien mira (private.llamada_celular_atencion_efectiva). */
  atencion: v.picklist(ATENCIONES),
  lead_id: v.nullable(v.string()),
  lead_nombre: v.nullable(v.string()),
  analista_id: v.string(),
  es_propia: v.boolean(),
})
export type FilaBandeja = v.InferOutput<typeof FilaBandejaSchema>

export const BandejaSchema = v.object({
  filas: v.array(FilaBandejaSchema),
  siguiente: v.nullable(v.object({ recibido_en: v.string(), evento_id: v.string() })),
})
export type Bandeja = v.InferOutput<typeof BandejaSchema>

export const DetalleLlamadaSchema = v.object({
  evento_id: v.string(),
  /** El id que puso el celular; lo agrega la décima (20261006150154), como en la bandeja. */
  evento_origen_id: v.optional(v.string()),
  recibido_en: v.string(),
  ocurrio_en: v.nullable(v.string()),
  numero: v.nullable(v.string()),
  direccion: v.string(),
  estado_tecnico: v.string(),
  duracion_seg: v.nullable(v.number()),
  calidad: v.unknown(),
  identificacion: v.picklist(IDENTIFICACIONES),
  atencion: v.picklist(ATENCIONES),
  lead_id: v.nullable(v.string()),
  metodo_asociacion: v.nullable(v.string()),
  analista_id: v.string(),
  motivo_descarte: v.nullable(v.string()),
  motivo_descarte_detalle: v.nullable(v.string()),
  actividad_id: v.nullable(v.string()),
  /** El resultado unido se deshizo: sus efectos no cuentan (decisión 4: el enlace no se borra). */
  efectos_anulados: v.boolean(),
})
export type DetalleLlamada = v.InferOutput<typeof DetalleLlamadaSchema>

export const ResueltaHoySchema = v.object({
  evento_id: v.string(),
  evento_origen_id: v.optional(v.string()),
  /** Cuándo se resolvió (el enlace al resultado o el descarte): «hoy» es lo resuelto hoy en Lima, aunque la llamada sea de ayer. */
  resuelto_en: v.string(),
  recibido_en: v.string(),
  ocurrio_en: v.nullable(v.string()),
  numero: v.nullable(v.string()),
  atencion: v.picklist(['registrado', 'descartado_con_motivo']),
  lead_id: v.nullable(v.string()),
  lead_nombre: v.nullable(v.string()),
  analista_id: v.string(),
  es_propia: v.boolean(),
  etiqueta: v.nullable(v.string()),
  actividad_id: v.nullable(v.string()),
  resultado: v.nullable(v.string()),
  deshecho: v.boolean(),
  via: v.nullable(v.picklist(VIAS)),
  motivo_descarte: v.nullable(v.string()),
  motivo_descarte_detalle: v.nullable(v.string()),
})
export type ResueltaHoy = v.InferOutput<typeof ResueltaHoySchema>
/** Paginada como la bandeja: el cursor se devuelve TAL CUAL (texto con microsegundos; pasarlo por Date pierde filas empatadas). */
export const ResueltasHoySchema = v.object({
  filas: v.array(ResueltaHoySchema),
  siguiente: v.nullable(v.object({ resuelto_en: v.string(), evento_id: v.string() })),
})
export type ResueltasHoy = v.InferOutput<typeof ResueltasHoySchema>

export const MarcaCelularSchema = v.array(v.object({
  actividad_id: v.string(),
  evento_id: v.string(),
  evento_origen_id: v.optional(v.string()),
  etiqueta: v.nullable(v.string()),
  via: v.picklist(VIAS),
}))
export type MarcaCelular = v.InferOutput<typeof MarcaCelularSchema>[number]

/** `enlace` de la v5: null sin id; si no se pudo unir, el resultado se guardó IGUAL (decisión de Jhosep, 05/10). */
export const EnlaceV5Schema = v.nullable(v.union([
  v.object({ estado: v.picklist(['enlazado', 'movido', 'repetido', 'pendiente']) }),
  v.object({ estado: v.literal('no_enlazado'), motivo: v.string() }),
]))
export type EnlaceV5 = v.InferOutput<typeof EnlaceV5Schema>

// ── Textos ──────────────────────────────────────────────────────────────────────────────────

/** El momento de la llamada: el reloj del celular si lo mandó; si no, cuando llegó el aviso. */
export function momentoDeLlamada(fila: { ocurrio_en: string | null; recibido_en: string }): number {
  return Date.parse(fila.ocurrio_en ?? fila.recibido_en)
}

/** «a las 10:42», «ayer a las 18:05» o «el 03/10 a las 18:05», en Lima. */
export function cuandoFue(ms: number, ahora: number): string {
  const dia = fechaLima(ms)
  if (dia === fechaLima(ahora)) return `a las ${horaLima(ms)}`
  if (dia === fechaLima(ahora - 86_400_000)) return `ayer a las ${horaLima(ms)}`
  return `el ${dia.slice(8, 10)}/${dia.slice(5, 7)} a las ${horaLima(ms)}`
}

/** «hace 16 min», «hace 2 h», «hace 3 días» (nunca negativo: un reloj adelantado dice «hace un momento»). */
export function haceCuanto(ms: number, ahora: number): string {
  const min = Math.floor((ahora - ms) / 60_000)
  if (min < 1) return 'hace un momento'
  if (min < 60) return `hace ${min} min`
  const h = Math.floor(min / 60)
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  return d === 1 ? 'hace 1 día' : `hace ${d} días`
}

/** El número como se lee en Perú (+51 987 654 322); oculto si no llegó. */
export function numeroLegible(numero: string | null): string {
  if (!numero) return 'número oculto'
  const m = /^\+51(9\d{2})(\d{3})(\d{3})$/.exec(numero)
  return m ? `+51 ${m[1]} ${m[2]} ${m[3]}` : numero
}

/** Qué pide la fila pendiente, dicho al analista. */
export function estadoPendiente(atencion: Atencion): string {
  switch (atencion) {
    case 'requiere_resultado': return 'Pide resultado'
    case 'requiere_devolucion': return 'Devolver la llamada'
    default: return 'Por revisar'
  }
}

/** Qué se puede hacer con una pendiente: con lead identificado se registra; sin él, se elige el lead. Siempre se puede descartar. */
export function accionPrincipal(fila: Pick<FilaBandeja, 'identificacion' | 'lead_id'>): 'registrar' | 'elegir' {
  return fila.identificacion === 'identificado' && fila.lead_id !== null ? 'registrar' : 'elegir'
}

// ── Unir a mano (F4.2.4, B7): «¿Es este su resultado?» ──────────────────────────────────────────
// La puerta crm.enlazar_llamada_celular (núcleo en 20261005143843) une una pendiente a un resultado que el analista
// ya guardó en ese lead (desde la ficha, desde la PC o porque la unión automática falló). Nunca se une sola y nunca
// crea otra gestión. Aquí vive el espejo de sus reglas, para no ofrecer nada que la puerta vaya a rechazar.

/** Margen del servidor: un resultado guardado más de 10 min ANTES de la llamada no es de esa llamada (22023). */
export const MARGEN_UNION_MS = 10 * 60_000

/** Un resultado de llamada ya guardado en el lead, como lo trae el historial (crm.actividades_de_lead_fn). */
export interface ResultadoGuardado {
  id: string
  lead_id: string
  tipo: string
  creado_en: string
  autor_nombre: string
  metadata?: Record<string, unknown> | undefined
  /** Fila optimista del store que todavía no llegó al servidor: en real no se puede unir (su id no existe allá). */
  local?: boolean | undefined
}

/** Solo una pendiente con lead identificado se puede unir: la misma condición que «Registrar resultado». */
export function puedeUnir(fila: Pick<FilaBandeja, 'identificacion' | 'lead_id'>): boolean {
  return accionPrincipal(fila) === 'registrar'
}

/**
 * Espejo del filtro del servidor: mismo lead, resultado de llamada registrado en la encuesta (`metadata.evento`), no
 * deshecho (la clave `deshecho_en` no existe, como el `?` de jsonb), no anterior a la llamada por más de 10 min, y sin
 * unir ya a otra llamada (`unidas`). El servidor no exige que lo haya guardado el mismo analista: se muestra quién lo
 * guardó. Los más recientes primero.
 */
export function resultadosParaUnir(
  fila: Pick<FilaBandeja, 'lead_id' | 'ocurrio_en' | 'recibido_en'>,
  actividades: readonly ResultadoGuardado[],
  unidas: ReadonlySet<string>,
  opciones: { conLocales?: boolean } = {},
): ResultadoGuardado[] {
  const desde = momentoDeLlamada(fila) - MARGEN_UNION_MS
  return actividades
    .filter((a) => a.lead_id === fila.lead_id
      && (a.tipo === 'llamada_realizada' || a.tipo === 'llamada_no_contestada')
      && a.metadata?.evento === 'resultado_llamada'
      && !('deshecho_en' in a.metadata)
      && Date.parse(a.creado_en) >= desde
      && !unidas.has(a.id)
      && (opciones.conLocales === true || a.local !== true))
    .sort((a, b) => Date.parse(b.creado_en) - Date.parse(a.creado_en))
}

/** «No contestó · guardado a las 10:42 · por Ana». */
export function lineaResultadoGuardado(r: ResultadoGuardado, ahora: number): string {
  const resultado = typeof r.metadata?.resultado === 'string' ? etiquetaResultado(r.metadata.resultado) : 'Resultado de llamada'
  return `${resultado} · guardado ${cuandoFue(Date.parse(r.creado_en), ahora)} · por ${r.autor_nombre}`
}

/**
 * Hallazgo de P9 (F4-d, 07/10): tras «Deshacer», la llamada quedaba «· deshecho» sin ninguna acción y no había cómo unirla
 * al resultado corregido. La v5 ya mueve el enlace cuando el anterior se deshizo (20261005182227: estado «movido»), pero
 * solo si la llamada es del analista que registra (si no, «celular_ajeno»): por eso el botón sale solo en las propias
 * registradas, deshechas, con lead y con el id que necesita la encuesta.
 */
export function puedeRegistrarCorregido(
  r: Pick<ResueltaHoy, 'atencion' | 'deshecho' | 'es_propia' | 'lead_id' | 'evento_origen_id'>,
): boolean {
  return r.atencion === 'registrado' && r.deshecho && r.es_propia && r.lead_id !== null && !!r.evento_origen_id
}

/**
 * La línea de una pendiente: cuándo, hace cuánto y con quién. Una ambigua NO dice cuántos leads tienen el número: la
 * base no lo guarda (fallo 4 de la revisión del 02/10).
 */
export function lineaPendiente(fila: FilaBandeja, ahora: number): string {
  const ms = momentoDeLlamada(fila)
  const base = `Llamaste ${cuandoFue(ms, ahora)} · ${haceCuanto(ms, ahora)}`
  if (fila.identificacion === 'ambiguo') return `${base} · más de un lead podría tener este número`
  if (fila.identificacion === 'sin_identificar') return `${base} · ningún lead de tu cartera tiene este número`
  return `${base} · ${numeroLegible(fila.numero)}`
}

/** El aviso llegó mucho después de la llamada (el celular sin señal): se dice, para que no parezca de hoy. */
export function llegoTarde(fila: Pick<FilaBandeja, 'ocurrio_en' | 'recibido_en'>): boolean {
  return fila.ocurrio_en !== null && Date.parse(fila.recibido_en) - Date.parse(fila.ocurrio_en) > 60 * 60_000
}

/** «Lleva 16 h» si una pendiente pasa de 4 h sin resultado; si no, null. */
export function retrasoPendiente(fila: FilaBandeja, ahora: number): string | null {
  const h = Math.floor((ahora - momentoDeLlamada(fila)) / 3_600_000)
  return h >= 4 ? `Lleva ${h} h` : null
}

export function etiquetaMotivoDescarte(clave: string | null, detalle?: string | null): string {
  if (clave === 'otro') return detalle?.trim() ? detalle.trim() : 'Otro motivo'
  return MOTIVOS_DESCARTE.find((m) => m.clave === clave)?.etiqueta ?? (clave ?? 'Sin motivo')
}

/** El estado de una resuelta de hoy: su resultado (y si se deshizo) o su motivo. */
export function estadoResuelta(r: ResueltaHoy): string {
  if (r.atencion === 'descartado_con_motivo') return `Descartada · ${etiquetaMotivoDescarte(r.motivo_descarte, r.motivo_descarte_detalle)}`
  const resultado = r.resultado ? etiquetaResultado(r.resultado) : 'Registrada'
  return r.deshecho ? `${resultado} · deshecho` : resultado
}

/** Cómo se resolvió: la cifra «encuesta abierta al colgar» por celular sale de aquí. */
export function comoSeResolvio(r: ResueltaHoy): string {
  if (r.atencion === 'descartado_con_motivo') return 'Descartada desde «Llamadas del celular»'
  switch (r.via) {
    case 'al_colgar': return 'Registrada al colgar: el celular abrió la encuesta'
    case 'pestana': return 'Registrada desde «Llamadas del celular»'
    case 'manual': return 'Unida a un resultado que ya estaba guardado'
    default: return 'Registrada'
  }
}

const TEXTO_NO_ENLAZADO: Record<string, string> = {
  id_invalido: 'el enlace del celular no traía un id válido',
  celular_ajeno: 'la llamada es de otro celular',
  otro_lead: 'la llamada es de otro lead',
  descartada: 'esa llamada ya estaba descartada',
  ya_tiene_resultado: 'esa llamada ya tenía otro resultado',
  resultado_ya_enlazado: 'ese resultado ya está unido a otra llamada',
  sin_llamada: 'ese número no es de un lead de tu cartera, así que la llamada no se guardó',
  resultado_deshecho: 'el resultado se deshizo',
  resultado_en_uso: 'el resultado se estaba deshaciendo en ese momento',
}
/** Motivos en los que la llamada sigue pendiente en la pestaña (las demás no están ahí: de otro celular, ya resueltas…). */
const SIGUE_EN_LA_PESTANA = new Set<string>(['otro_lead', 'resultado_ya_enlazado', 'resultado_deshecho', 'resultado_en_uso'])

/** Lo que se le dice al analista después de guardar con el id de la llamada (null = no hubo id). */
export function textoEnlace(enlace: EnlaceV5, cuando: string): string | null {
  if (enlace === null) return null
  switch (enlace.estado) {
    case 'enlazado':
    case 'movido':
    case 'repetido':
      return `Quedó unido a tu llamada del celular ${cuando}.`
    case 'pendiente':
      return `Quedará unido a tu llamada del celular ${cuando} en cuanto llegue su aviso.`
    case 'no_enlazado':
      return `Resultado guardado, pero no se unió a la llamada del celular: ${TEXTO_NO_ENLAZADO[enlace.motivo] ?? 'no se pudo confirmar el enlace; revisa las llamadas pendientes'}.`
        + (SIGUE_EN_LA_PESTANA.has(enlace.motivo) ? ' La llamada sigue en «Llamadas del celular».' : '')
  }
}
