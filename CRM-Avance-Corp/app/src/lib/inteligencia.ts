// lib/inteligencia.ts — Inteligencia comercial por rol (contrato F1c).
// Funciones PURAS sobre (leads, actividades, equipo): sin React, sin store,
// sin efectos. Cada pantalla las alimenta con su ÁMBITO (useStore().ambito),
// así la misma función sirve para vendedor/supervisor/gerencia/directorio.
//
// Semáforos (sin verde en el chrome): azul #2563eb ok · ámbar #d97706 atención
// · rojo #dc2626 crítico — los colores los pone la UI según `sev`.
import { ETAPAS, ORIGENES, type Actividad, type EtapaActiva, type Lead, type Miembro } from './tipos'

const DIA_MS = 86_400_000
const TERMINALES_K = new Set<string>(['convertido', 'descartado'])

/** Lead abierto = activo y en etapa de trabajo (ni convertido ni descartado). */
const esAbierto = (l: Lead) => l.activo && !TERMINALES_K.has(l.etapa)

// ── Semáforo compartido de avance de meta ─────────────────────────────────────

/**
 * Color del avance hacia una meta (pct 0–100, puede exceder 100): azul ≥75
 * en buen camino · ámbar ≥40 atención · rojo <40 crítico. Escala ÚNICA para
 * todos los roles (sin verde; navy queda reservado a ganado/convertido).
 */
export const colorMeta = (pct: number): string =>
  pct >= 75 ? '#2563eb' : pct >= 40 ? '#d97706' : '#dc2626'

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

/** "hace horas" / "hace N días" para los motivos es-PE. */
function haceTexto(dias: number): string {
  if (dias < 1) return 'hace horas'
  const d = Math.floor(dias)
  return d === 1 ? 'hace 1 día' : `hace ${d} días`
}

/** Última actividad (cualquier tipo) registrada para un lead, o undefined. */
export function ultimaActividadDe(leadId: string, acts: Actividad[]): Actividad | undefined {
  let ultima: Actividad | undefined
  for (const a of acts) {
    if (a.lead_id !== leadId) continue
    if (!ultima || a.creado_en > ultima.creado_en) ultima = a
  }
  return ultima
}

/**
 * Días (con fracción) sin actividad: desde la última actividad, o desde
 * creado_en si el lead nunca fue tocado. Nunca negativo.
 */
export function diasSinActividad(lead: Lead, acts: Actividad[]): number {
  const ref = ultimaActividadDe(lead.id, acts)?.creado_en ?? lead.creado_en
  const t = new Date(ref).getTime()
  if (Number.isNaN(t)) return 0
  return Math.max(0, (Date.now() - t) / DIA_MS)
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
export function colaDe(leads: Lead[], acts: Actividad[]): ItemCola[] {
  const items: ItemCola[] = []
  for (const lead of leads) {
    if (!esAbierto(lead)) continue
    const dias = diasSinActividad(lead, acts)
    if (lead.vendedor_id == null) {
      items.push({ lead, bucket: 'por_repartir', sev: 'critica', dias, motivo: `Sin vendedor asignado ${haceTexto(dias)} — hay que repartirlo` })
    } else if (lead.etapa === 'nuevo' && !ultimaActividadDe(lead.id, acts)) {
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
export function metricasPorVendedor(vs: Miembro[], leads: Lead[], acts: Actividad[]): MetricasVendedor[] {
  return vs
    .map((m) => {
      const suyos = leads.filter((l) => l.activo && l.vendedor_id === m.perfil_id)
      const abiertos = suyos.filter(esAbierto)
      const convertidos = suyos.filter((l) => l.etapa === 'convertido').length
      let capitalPEN = 0
      let capitalUSD = 0
      let sinTocar = 0
      let diasMax = 0
      for (const l of abiertos) {
        if (l.moneda === 'USD') capitalUSD += l.monto_estimado ?? 0
        else capitalPEN += l.monto_estimado ?? 0
        if (!ultimaActividadDe(l.id, acts)) sinTocar++
        const d = diasSinActividad(l, acts)
        if (d > diasMax) diasMax = d
      }
      return {
        m,
        activos: abiertos.length,
        capitalPEN,
        capitalUSD,
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
export function estancados(leads: Lead[], acts: Actividad[], dias = 7): Array<{ lead: Lead; dias: number }> {
  return leads
    .filter(esAbierto)
    .map((lead) => ({ lead, dias: diasSinActividad(lead, acts) }))
    .filter((x) => x.dias >= dias)
    .sort((a, b) => b.dias - a.dias)
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
      let capitalPEN = 0
      let capitalUSD = 0
      for (const l of abiertos) {
        if (l.moneda === 'USD') capitalUSD += l.monto_estimado ?? 0
        else capitalPEN += l.monto_estimado ?? 0
      }
      return {
        supervisor,
        vendedores: suyos.length,
        activos: abiertos.length,
        capitalPEN,
        capitalUSD,
        convertidos,
        conversion: asignados.length > 0 ? Math.round((convertidos / asignados.length) * 100) : 0,
        parkeados: vivos.filter((l) => esAbierto(l) && l.vendedor_id == null && l.asignado_supervisor_id === supervisor.perfil_id).length,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN)
}
