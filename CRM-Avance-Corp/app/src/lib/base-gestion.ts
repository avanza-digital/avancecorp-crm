// lib/base-gestion.ts — contrato y textos de la «Base para gestión» del analista (B1–B3b, en producción
// desde el 02/10/2026). El SERVIDOR decide qué leads entran (descartados vivos, sin «no contactar», sin
// descanso vigente), en qué orden (rellamada de hoy → etapa máxima → menos días) y aplica las reglas
// (3 intentos → 30 días de descanso; rellamada como máximo a 10 días). Aquí solo se valida la forma de
// cada fila y se redacta lo que la pantalla muestra.
import * as v from 'valibot'
import { DIAS, MESES, fechaLima, horaLima } from './agenda-derivada'
import { etiquetaDeMes, mesLima } from './cartera-meses'
import { EnteroNoNegativoRpcSchema, NumeroRpcSchema } from './esquemas-rpc'
import { isoDeCampos } from './campos-siguiente'
import { normalizar } from './clientes-vista'
import { etiquetaResultado } from './resultado-llamada'
import { ETAPA_INFO, MOTIVOS_DESCARTE, TIPOS_ACTIVIDAD, origenLabel, type Actividad, type Lead } from './tipos'

/** Espejo de `private.base_gestion_constantes()`: solo para redactar; el servidor manda. */
export const MAX_INTENTOS_BASE = 3
export const DIAS_DESCANSO_BASE = 30
export const DIAS_MAX_RELLAMADA = 10

/** Etapa más avanzada que alcanzó el lead en su ciclo vigente (deducida del historial, D6). */
export const ETAPAS_MAXIMAS = ['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada', 'convertido', 'sin_datos'] as const
export type EtapaMaxima = (typeof ETAPAS_MAXIMAS)[number]

const TextoONulo = v.nullable(v.string())

/** Una fila de `crm.obtener_base_gestion`. Los campos de presentación aceptan valores nuevos del catálogo
 *  (se muestran tal cual); los que gobiernan la pantalla (etapa, intentos, rellamada) son estrictos. */
export const FilaBaseGestionSchema = v.object({
  lead_id: v.string(),
  nombre_completo: v.string(),
  telefono: TextoONulo,
  distrito: TextoONulo,
  origen: TextoONulo,
  categoria_interes: TextoONulo,
  monto_estimado: v.nullable(NumeroRpcSchema),
  moneda: v.nullable(v.picklist(['PEN', 'USD'] as const)),
  motivo_descarte: TextoONulo,
  descartado_en: TextoONulo,
  dias_desde_descarte: v.nullable(EnteroNoNegativoRpcSchema),
  etapa_maxima: v.picklist(ETAPAS_MAXIMAS),
  intentos: EnteroNoNegativoRpcSchema,
  ultimo_resultado: TextoONulo,
  ultimo_intento_en: TextoONulo,
  proxima_llamada_en: TextoONulo,
  rellamada_hoy: v.boolean(),
  enfriado_hasta: TextoONulo,
  ciclo_n: v.nullable(EnteroNoNegativoRpcSchema),
  vendedor_id: TextoONulo,
  gestiona: TextoONulo,
  /** Cuándo le llegó el lead al analista (`coalesce(tenencia_desde, creado_en)`): el MES por el que se organiza
   *  (Miguel, 02/10/2026). Lo añade la migración B5; opcional para que la pantalla sirva antes y después de ella. */
  recibido_en: v.optional(TextoONulo, null),
})
export type FilaBaseGestion = v.InferOutput<typeof FilaBaseGestionSchema>

/** «Cita agendada», «Entrevista realizada»… con los mismos nombres que el pipeline. */
export function etiquetaEtapaMaxima(etapa: EtapaMaxima): string {
  return etapa === 'sin_datos' ? 'Sin historial' : ETAPA_INFO[etapa].label
}

/** Color de la etapa máxima: el del pipeline, o gris si no hay historial (el punto de la hoja y el chip de la ficha). */
export function colorEtapaMaxima(etapa: EtapaMaxima): string {
  return etapa === 'sin_datos' ? '#94a3b8' : ETAPA_INFO[etapa].color
}

export function etiquetaMotivoDescarte(motivo: string | null): string {
  if (!motivo) return 'Sin motivo'
  return MOTIVOS_DESCARTE.find((m) => m.k === motivo)?.label ?? motivo
}

export function etiquetaOrigen(origen: string | null): string {
  return origen ? origenLabel(origen) : 'Sin origen'
}

export function etiquetaUltimoResultado(resultado: string | null): string {
  return resultado ? etiquetaResultado(resultado) : 'Sin intentos'
}

/** «Hoy», «Ayer», «Hace 12 días». */
export function etiquetaDiasDescarte(dias: number | null): string {
  if (dias === null) return 'Sin fecha'
  if (dias === 0) return 'Hoy'
  if (dias === 1) return 'Ayer'
  return `Hace ${dias} días`
}

/** «2 de 3»: los intentos de la ventana vigente frente al tope que pone a descansar al lead. Con una
 *  rellamada agendada el 3.º no lo pone a descansar (D12), así que puede haber más: «4 intentos». */
export function etiquetaIntentos(intentos: number): string {
  return intentos <= MAX_INTENTOS_BASE ? `${intentos} de ${MAX_INTENTOS_BASE}` : `${intentos} intentos`
}

export type EstadoRellamada = 'vencida' | 'hoy' | 'futura'

/** Cuándo toca la rellamada agendada, en días calendario de Lima. */
export function estadoRellamada(iso: string, ahora: number = Date.now()): EstadoRellamada {
  const dia = fechaLima(Date.parse(iso))
  const hoy = fechaLima(ahora)
  if (dia < hoy) return 'vencida'
  return dia === hoy ? 'hoy' : 'futura'
}

/** Un momento pasado en Lima: «Hoy, 15:30», «Ayer, 10:00» o «Vie 9 Oct, 10:00». */
export function etiquetaMomento(iso: string, ahora: number = Date.now()): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return 'Sin fecha'
  const dia = fechaLima(ms)
  const hora = horaLima(ms)
  if (dia === fechaLima(ahora)) return `Hoy, ${hora}`
  if (dia === fechaLima(ahora - 86_400_000)) return `Ayer, ${hora}`
  const d = new Date(`${dia}T12:00:00Z`)
  return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} ${MESES[d.getUTCMonth()]}, ${hora}`
}

/** «Hoy, 15:30», «Mañana, 10:00», «Vie 9 Oct, 10:00»; con «Vencida» si quedó atrás. */
export function etiquetaRellamada(iso: string, ahora: number = Date.now()): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return 'Sin fecha'
  const hora = horaLima(ms)
  const estado = estadoRellamada(iso, ahora)
  if (estado === 'hoy') return `Hoy, ${hora}`
  const d = new Date(`${fechaLima(ms)}T12:00:00Z`)
  const fecha = `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} ${MESES[d.getUTCMonth()]}`
  if (estado === 'vencida') return `Vencida: ${fecha}, ${hora}`
  const manana = fechaLima(ahora + 86_400_000) === fechaLima(ms)
  return manana ? `Mañana, ${hora}` : `${fecha}, ${hora}`
}

/**
 * Espejo DEMO (sin red): los descartados vivos del propio analista en el store, sin «no contactar», con la
 * misma forma que la RPC. En demo no hay historial de intentos: todo arranca en 0 y «Sin historial».
 */
export function filasDemoBaseGestion(leads: readonly Lead[], analistaId: string, ahora: number = Date.now()): FilaBaseGestion[] {
  const hoy = fechaLima(ahora)
  return leads
    .filter((l) => l.etapa === 'descartado' && l.vendedor_id === analistaId && l.no_contactar !== true)
    .map((l) => {
      const descartadoEn = l.actualizado_en ?? l.creado_en
      const dias = Math.max(0, Math.round((Date.parse(`${hoy}T12:00:00Z`) - Date.parse(`${fechaLima(Date.parse(descartadoEn))}T12:00:00Z`)) / 86_400_000))
      return {
        lead_id: l.id, nombre_completo: l.nombre_completo, telefono: l.telefono, distrito: l.distrito ?? null,
        origen: l.origen, categoria_interes: l.categoria_interes ?? null, monto_estimado: l.monto_estimado, moneda: l.moneda,
        motivo_descarte: l.motivo_descarte ?? null, descartado_en: descartadoEn, dias_desde_descarte: dias,
        etapa_maxima: 'sin_datos' as const, intentos: 0, ultimo_resultado: null, ultimo_intento_en: null,
        proxima_llamada_en: null, rellamada_hoy: false, enfriado_hasta: null, ciclo_n: null,
        vendedor_id: analistaId, gestiona: l.vendedor_nombre ?? null,
        recibido_en: l.tenencia_desde ?? l.creado_en,
      }
    })
    .sort((a, b) => (a.dias_desde_descarte ?? 0) - (b.dias_desde_descarte ?? 0))
}

// ── El MES del lead: «mis leads de enero, de marzo, de agosto» (Miguel, 02/10/2026) ──────────────────────────
/** Valor del selector que apaga el recorte por mes. */
export const MES_TODOS = 'todos'

/** 'YYYY-MM' en Lima del mes en que le llegó el lead al analista; null si el servidor aún no lo manda. */
export function mesDelLead(fila: FilaBaseGestion): string | null {
  return mesLima(fila.recibido_en)
}

/** 'Agosto 2026' (rótulo largo de la casa, el de los bloques de «Mi cartera»). */
export function etiquetaMesLead(clave: string): string {
  return etiquetaDeMes(clave)
}

export interface MesDeLaBase {
  clave: string
  etiqueta: string
  leads: number
}

/** Los meses presentes en la base con su conteo, del más reciente al más antiguo. Vacío si ninguna fila trae el mes. */
export function mesesDeLaBase(filas: readonly FilaBaseGestion[]): MesDeLaBase[] {
  const conteo = new Map<string, number>()
  for (const f of filas) {
    const mes = mesDelLead(f)
    if (mes) conteo.set(mes, (conteo.get(mes) ?? 0) + 1)
  }
  return [...conteo.entries()]
    .sort(([a], [b]) => (a < b ? 1 : a > b ? -1 : 0))
    .map(([clave, leads]) => ({ clave, etiqueta: etiquetaMesLead(clave), leads }))
}

/** Las filas del mes elegido (o todas). Una fila sin mes solo aparece en «todos». */
export function filasDelMes(filas: readonly FilaBaseGestion[], mes: string): FilaBaseGestion[] {
  if (mes === MES_TODOS) return [...filas]
  return filas.filter((f) => mesDelLead(f) === mes)
}

// ── La ficha del lead de la base (F2) ─────────────────────────────────────────────────────────────────────
/** «Volver a llamar» exige fecha y hora: futura y como máximo a {@link DIAS_MAX_RELLAMADA} días. La pantalla avisa
 *  antes de enviar; la puerta vuelve a validar (manda ella). Devuelve el instante ISO o el motivo para no enviarlo. */
export function validarRellamada(fecha: string, hora: string, ahora: number = Date.now()): { iso: string } | { error: string } {
  const iso = isoDeCampos({ tipo: 'llamada', titulo: '', fecha, hora })
  if (!iso) return { error: 'Elige la fecha y la hora de la próxima llamada.' }
  const ms = Date.parse(iso)
  if (ms <= ahora) return { error: 'La próxima llamada tiene que ser más adelante que ahora.' }
  if (ms > ahora + DIAS_MAX_RELLAMADA * 86_400_000) return { error: `La próxima llamada puede agendarse como máximo a ${DIAS_MAX_RELLAMADA} días.` }
  return { iso }
}

/** Lo que se envía con un intento, como texto estable: el MISMO contenido reusa su `p_operacion_id` (un doble clic o
 *  un reintento tras un corte devuelven la respuesta original); otro contenido lleva un id nuevo (si no, 23505). */
export function firmaIntento(entrada: { resultado: string; nota: string; proximaLlamada: string | null }): string {
  return JSON.stringify([entrada.resultado, entrada.nota.trim(), entrada.proximaLlamada])
}

/** Cómo se lee una actividad en el historial de la base: los intentos, la reactivación y el «No contactar» dicen lo
 *  que fueron (el servidor los guarda como `nota` con el evento en la metadata; sin esto se leerían «Nota»). */
export function etiquetaActividadBase(a: Actividad): string {
  const meta = a.metadata ?? {}
  if (meta.evento === 'intento_base') {
    const n = typeof meta.intento_n === 'number' ? meta.intento_n : Number(meta.intento_n)
    const resultado = typeof meta.resultado === 'string' ? etiquetaResultado(meta.resultado) : 'Intento'
    return Number.isFinite(n) && n > 0 ? `Intento ${n} · ${resultado}` : resultado
  }
  if (meta.evento === 'reactivacion_base') return 'Reactivado desde la base'
  if (meta.evento === 'no_contactar') {
    // `accion` la escriben crm.marcar_no_contactar ('marcar') y crm.levantar_no_contactar ('levantar').
    if (meta.accion === 'marcar') return 'Marcado «No contactar»'
    if (meta.accion === 'levantar') return 'Levantado «No contactar»'
    return 'No contactar'
  }
  return TIPOS_ACTIVIDAD[a.tipo] ?? 'Actividad'
}

/** Buscador del historial: sin mayúsculas ni tildes, sobre lo que el analista lee (qué pasó, nota y quién). */
export function filtrarHistorial(items: readonly Actividad[], texto: string): Actividad[] {
  const buscado = normalizar(texto.trim())
  if (!buscado) return [...items]
  return items.filter((a) => normalizar(`${etiquetaActividadBase(a)} ${a.detalle ?? ''} ${a.autor_nombre}`).includes(buscado))
}

