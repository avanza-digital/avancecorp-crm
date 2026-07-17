// lib/inteligencia.ts — Inteligencia comercial por rol (contrato F1c).
// Funciones PURAS sobre (leads, actividades, equipo): sin React, sin store,
// sin efectos. Cada pantalla las alimenta con su ÁMBITO (useCRMData().ambito),
// así la misma función sirve para vendedor/supervisor/gerencia/directorio.
//
// Los colores salen de lib/semaforo.ts (paleta única, sin verde en el chrome).
import { ETAPAS, ORIGENES, TERMINALES_K, type Actividad, type EtapaActiva, type Lead, type Miembro } from './tipos'
import { SEMAFORO } from './semaforo'

export const DIA_MS = 86_400_000

/** Lead abierto = activo y en etapa de trabajo (ni convertido ni descartado). */
export const esAbierto = (l: Lead): boolean => l.activo && !TERMINALES_K.has(l.etapa)

// ── Capital por moneda ────────────────────────────────────────────────────────

/**
 * Capital estimado por moneda de los leads RECIBIDOS (el caller decide el
 * subconjunto — típicamente abiertos). Regla central del negocio: PEN y USD
 * JAMÁS se suman entre sí. Fuente única (antes reimplementado en 8 sitios).
 */
export function capitalPorMoneda(leads: Lead[]): { pen: number; usd: number } {
  let pen = 0
  let usd = 0
  for (const l of leads) {
    if (l.moneda === 'USD') usd += l.monto_estimado ?? 0
    else pen += l.monto_estimado ?? 0
  }
  return { pen, usd }
}

// ── Semáforo compartido de avance de meta ─────────────────────────────────────

/**
 * Color del avance hacia una meta (pct 0–100, puede exceder 100): azul ≥75
 * en buen camino · ámbar ≥40 atención · rojo <40 crítico. Escala ÚNICA para
 * todos los roles (sin verde; navy queda reservado a ganado/convertido).
 */
export const colorMeta = (pct: number): string =>
  pct >= 75 ? SEMAFORO.ok : pct >= 40 ? SEMAFORO.atencion : SEMAFORO.critico

/** Semáforo de un valor contra su objetivo: llega azul · a medias ámbar · lejos rojo. */
export function colorVsObjetivo(valor: number, objetivo: number): string {
  if (objetivo <= 0 || valor >= objetivo) return SEMAFORO.ok
  if (valor >= objetivo / 2) return SEMAFORO.atencion
  return SEMAFORO.critico
}

/** % de avance hacia el objetivo (la UI recorta a 0–100 al pintar la barra). */
export const pctMeta = (actual: number, objetivo: number): number =>
  objetivo > 0 ? (actual / objetivo) * 100 : 0

/**
 * Chip de tendencia "▲ +13%" desde una serie (últimos 2 puntos). Con
 * `mostrarCero` el 0% devuelve "— 0%" (dashboards ejecutivos); sin él,
 * undefined (sin chip). Semántica unificada — antes divergía por copia.
 *
 * @deprecated Sin consumidores desde el Sprint A (A3, honestidad): el chip de
 * tendencia dejó de dibujarse porque sus series eran de demostración. NO
 * borrar — gerencia planea reactivar tendencias cuando existan series reales.
 */
export function tendenciaDe(serie: number[], opts?: { mostrarCero?: boolean }): string | undefined {
  if (serie.length < 2) return undefined
  const [prev, ult] = serie.slice(-2)
  if (prev == null || ult == null || prev === 0) return undefined
  const pct = Math.round(((ult - prev) / prev) * 100)
  if (pct === 0) return opts?.mostrarCero ? '— 0%' : undefined
  return pct > 0 ? `▲ +${pct}%` : `▼ −${Math.abs(pct)}%`
}

// ── Cola de acción ────────────────────────────────────────────────────────────

export type BucketCola = 'sin_responder' | 'propuesta_sin_respuesta' | 'seguimiento' | 'por_repartir'

export interface ItemCola {
  lead: Lead
  bucket: BucketCola
  motivo: string
  sev: 'critica' | 'media' | 'baja'
  dias: number
}

/** Orden de severidad para la cola (crítica primero). */
const PESO_SEV: Record<ItemCola['sev'], number> = { critica: 0, media: 1, baja: 2 }

/** Labels es-PE de los buckets de la cola (antes copiado en vendedor y supervisor). */
export const BUCKET_LABEL: Record<BucketCola, string> = {
  sin_responder: 'Sin responder',
  propuesta_sin_respuesta: 'Propuesta sin respuesta',
  seguimiento: 'Seguimiento',
  por_repartir: 'Por repartir',
}

/** "hace horas" / "hace N días" para motivos y timestamps es-PE — fuente única. */
export function haceTexto(dias: number): string {
  if (dias < 1) return 'hace horas'
  const d = Math.floor(dias)
  return d === 1 ? 'hace 1 día' : `hace ${d} días`
}

/** "hoy" / "N d" compacto para columnas de días (dias viene con fracción). */
export const diasTxt = (d: number): string => (d < 1 ? 'hoy' : `${Math.floor(d)} d`)

export type IndiceUltimaActividad = ReadonlyMap<string, Actividad>

/**
 * Índice O(actividades) reutilizable por todos los cálculos de una pantalla.
 * Evita volver a recorrer el timeline completo por cada lead.
 */
export function indexarUltimaActividad(acts: Actividad[]): IndiceUltimaActividad {
  const indice = new Map<string, Actividad>()
  for (const actividad of acts) {
    const anterior = indice.get(actividad.lead_id)
    if (!anterior || actividad.creado_en > anterior.creado_en) {
      indice.set(actividad.lead_id, actividad)
    }
  }
  return indice
}

/**
 * Días (con fracción, nunca negativos) desde un ISO hasta `ahora` (epoch ms).
 * Pasa el reloj vivo de useAhora() como `ahora` para que el valor refresque
 * solo — NUNCA re-derivar con Date.now() en render (queda congelado).
 */
export function diasDesdeReferencia(creadoEn: string, ahora: number): number {
  const t = new Date(creadoEn).getTime()
  if (Number.isNaN(t)) return 0
  return Math.max(0, (ahora - t) / DIA_MS)
}

function diasSinActividadIndexado(
  lead: Lead,
  indice: IndiceUltimaActividad,
  ahora: number,
): number {
  return diasDesdeReferencia(indice.get(lead.id)?.creado_en ?? lead.creado_en, ahora)
}

/**
 * Días (con fracción) sin actividad: desde la última actividad, o desde
 * creado_en si el lead nunca fue tocado. Nunca negativo.
 * `ahora` (epoch ms, default Date.now()) permite un reloj vivo (useAhora)
 * o fechas fijas en tests; la firma sigue siendo retro-compatible.
 */
export function diasSinActividad(lead: Lead, acts: Actividad[], ahora: number = Date.now(), indice?: IndiceUltimaActividad): number {
  return diasSinActividadIndexado(lead, indice ?? indexarUltimaActividad(acts), ahora)
}

/**
 * Cola de acción — SOLO leads abiertos; a lo sumo UN bucket por lead
 * (el más urgente gana). Orden: severidad desc, luego días desc.
 * Reglas (contrato F1c):
 *  - vendedor_id null → por_repartir (crítica) — solo la ven supervisor/gerencia
 *    porque el ámbito del vendedor nunca incluye parkeados.
 *  - nuevo SIN ninguna actividad → sin_responder (crítica si ≥1 día; media antes).
 *  - propuesta_enviada sin actividad ≥5 días → propuesta_sin_respuesta (media).
 *  - contactado/reunion_agendada sin actividad ≥3 días → seguimiento (baja).
 */
export function colaDe(leads: Lead[], acts: Actividad[], ahora: number = Date.now(), indicePrevio?: IndiceUltimaActividad): ItemCola[] {
  const items: ItemCola[] = []
  const indice = indicePrevio ?? indexarUltimaActividad(acts)
  for (const lead of leads) {
    if (!esAbierto(lead)) continue
    const ultima = indice.get(lead.id)
    const dias = diasSinActividadIndexado(lead, indice, ahora)
    if (lead.vendedor_id == null) {
      items.push({ lead, bucket: 'por_repartir', sev: 'critica', dias, motivo: `Sin vendedor asignado ${haceTexto(dias)} — hay que repartirlo` })
    } else if (lead.etapa === 'nuevo' && !ultima) {
      items.push({ lead, bucket: 'sin_responder', sev: dias >= 1 ? 'critica' : 'media', dias, motivo: `Entró ${haceTexto(dias)} y nadie lo ha contactado` })
    } else if (lead.etapa === 'propuesta_enviada' && dias >= 5) {
      items.push({ lead, bucket: 'propuesta_sin_respuesta', sev: 'media', dias, motivo: `Propuesta enviada sin movimiento ${haceTexto(dias)}` })
    } else if ((lead.etapa === 'contactado' || lead.etapa === 'reunion_agendada') && dias >= 3) {
      items.push({ lead, bucket: 'seguimiento', sev: 'baja', dias, motivo: `Sin actividad ${haceTexto(dias)} — toca retomar el seguimiento` })
    }
  }
  return items.sort((a, b) => PESO_SEV[a.sev] - PESO_SEV[b.sev] || b.dias - a.dias)
}

// ── Métricas por vendedor (ranking) ──────────────────────────────────────────

export interface MetricasVendedor {
  m: Miembro
  activos: number
  capitalPEN: number // capital en proceso de sus leads abiertos en PEN
  capitalUSD: number // ídem en USD — JAMÁS se suma con el PEN
  convertidos: number
  conversion: number // 0-100: convertidos / total de sus leads
  sinTocar: number // abiertos sin NINGUNA actividad registrada
  diasSinActividadMax: number // el abierto más abandonado (0 si no tiene abiertos)
}

/**
 * Métricas de captación por vendedor sobre el ámbito recibido.
 * Orden: capitalPEN desc (el ranking por capital captado en proceso).
 */
export function metricasPorVendedor(vs: Miembro[], leads: Lead[], acts: Actividad[], ahora: number = Date.now(), indicePrevio?: IndiceUltimaActividad): MetricasVendedor[] {
  const indice = indicePrevio ?? indexarUltimaActividad(acts)
  const porVendedor = new Map<string, Lead[]>()
  for (const lead of leads) {
    if (!lead.activo || !lead.vendedor_id) continue
    const actuales = porVendedor.get(lead.vendedor_id)
    if (actuales) actuales.push(lead)
    else porVendedor.set(lead.vendedor_id, [lead])
  }

  return vs
    .map((m) => {
      const suyos = porVendedor.get(m.perfil_id) ?? []
      const abiertos = suyos.filter(esAbierto)
      const convertidos = suyos.filter((l) => l.etapa === 'convertido').length
      const capital = capitalPorMoneda(abiertos)
      let sinTocar = 0
      let diasMax = 0
      for (const l of abiertos) {
        if (!indice.has(l.id)) sinTocar++
        const d = diasSinActividadIndexado(l, indice, ahora)
        if (d > diasMax) diasMax = d
      }
      return {
        m,
        activos: abiertos.length,
        capitalPEN: capital.pen,
        capitalUSD: capital.usd,
        convertidos,
        conversion: suyos.length > 0 ? Math.round((convertidos / suyos.length) * 100) : 0,
        sinTocar,
        diasSinActividadMax: diasMax,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN)
}

// ── Embudo y conversión ───────────────────────────────────────────────────────

/**
 * Embudo por etapa activa sobre los leads ABIERTOS del ámbito.
 * Devuelve SIEMPRE las 4 etapas en orden de pipeline (n puede ser 0);
 * pctDelTotal es sobre el total de abiertos (0 si no hay ninguno).
 */
export function embudo(leads: Lead[]): Array<{ etapa: EtapaActiva; n: number; pctDelTotal: number }> {
  const abiertos = leads.filter(esAbierto)
  const total = abiertos.length
  return ETAPAS.map((e) => {
    const n = abiertos.filter((l) => l.etapa === e.k).length
    return { etapa: e.k, n, pctDelTotal: total > 0 ? Math.round((n / total) * 100) : 0 }
  })
}

/**
 * Conversión por origen (histórico completo del ámbito, terminales incluidos).
 * Solo orígenes con al menos un lead; label es-PE del catálogo ORIGENES.
 * Orden: % de conversión desc, luego volumen desc.
 */
export function conversionPorOrigen(leads: Lead[]): Array<{ origen: string; label: string; total: number; convertidos: number; pct: number }> {
  const vivos = leads.filter((l) => l.activo)
  const filas: Array<{ origen: string; label: string; total: number; convertidos: number; pct: number }> = []
  for (const o of ORIGENES) {
    const del = vivos.filter((l) => l.origen === o.k)
    if (del.length === 0) continue
    const convertidos = del.filter((l) => l.etapa === 'convertido').length
    filas.push({ origen: o.k, label: o.label, total: del.length, convertidos, pct: Math.round((convertidos / del.length) * 100) })
  }
  return filas.sort((a, b) => b.pct - a.pct || b.total - a.total)
}

// ── Estancados (capital en riesgo) ────────────────────────────────────────────

/**
 * Leads ABIERTOS sin actividad hace `dias` o más (default 7).
 * Orden: días desc (el más abandonado primero). `dias` va con fracción;
 * la UI decide cómo redondear.
 */
export function estancados(leads: Lead[], acts: Actividad[], dias = 7, ahora: number = Date.now(), indicePrevio?: IndiceUltimaActividad): Array<{ lead: Lead; dias: number }> {
  const indice = indicePrevio ?? indexarUltimaActividad(acts)
  return leads
    .filter(esAbierto)
    .map((lead) => ({ lead, dias: diasSinActividadIndexado(lead, indice, ahora) }))
    .filter((x) => x.dias >= dias)
    .sort((a, b) => b.dias - a.dias)
}

// ── Conversión global del ámbito ──────────────────────────────────────────────

/**
 * Conversión del ámbito: convertidos / leads activos CON vendedor (misma base
 * que comparativaEquipos — los parkeados no cuentan porque nadie los trabaja).
 * Fuente única (antes copiado con comentarios gemelos en supervisor y gerencia).
 */
export function conversionGlobal(leads: Lead[]): { convertidos: number; base: number; pct: number } {
  const asignados = leads.filter((l) => l.activo && l.vendedor_id != null)
  const convertidos = asignados.filter((l) => l.etapa === 'convertido').length
  return {
    convertidos,
    base: asignados.length,
    pct: asignados.length > 0 ? Math.round((convertidos / asignados.length) * 100) : 0,
  }
}

// ── Comparativa de equipos (gerencia / directorio) ────────────────────────────

/**
 * Una fila por SUPERVISOR activo del equipo. El universo de cada fila es el
 * mismo que el ámbito de ese supervisor: sus leads propios + los de sus
 * vendedores (métricas de activos/capital/conversión) MÁS sus parkeados
 * (vendedor_id null asignados a su bandeja), que se cuentan aparte en
 * `parkeados` y NO suman al capital (aún no tienen dueño trabajándolos).
 */
export function comparativaEquipos(equipo: Miembro[], leads: Lead[], acts: Actividad[]):
  Array<{ supervisor: Miembro; vendedores: number; activos: number; capitalPEN: number; capitalUSD: number; convertidos: number; conversion: number; parkeados: number }> {
  void acts // reservado: SLA/semaforización por equipo llega en F2 sin romper la firma
  const vivos = leads.filter((l) => l.activo)
  return equipo
    .filter((m) => m.rol_crm === 'supervisor' && m.activo)
    .map((supervisor) => {
      const suyos = equipo.filter((m) => m.supervisor_id === supervisor.perfil_id && m.activo)
      const ids = new Set<string>([supervisor.perfil_id, ...suyos.map((v) => v.perfil_id)])
      const asignados = vivos.filter((l) => l.vendedor_id != null && ids.has(l.vendedor_id))
      const abiertos = asignados.filter(esAbierto)
      const convertidos = asignados.filter((l) => l.etapa === 'convertido').length
      const capital = capitalPorMoneda(abiertos)
      return {
        supervisor,
        vendedores: suyos.length,
        activos: abiertos.length,
        capitalPEN: capital.pen,
        capitalUSD: capital.usd,
        convertidos,
        conversion: asignados.length > 0 ? Math.round((convertidos / asignados.length) * 100) : 0,
        parkeados: vivos.filter((l) => esAbierto(l) && l.vendedor_id == null && l.asignado_supervisor_id === supervisor.perfil_id).length,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN)
}
