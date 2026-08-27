// lib/metricas-vendedores.ts — contrato, mapper y espejo demo de
// crm.metricas_vendedores_fn (F1b). El payload viaja SIN nombres de personas
// (precedente metricas_conversiones_fn): el front une por id con su roster —
// ese join vive aquí, una sola vez. En demo el MISMO shape se calcula del
// estado vivo con metricasPorVendedor/comparativaEquipos sobre el ámbito
// recortado a la ventana operativa de 45 días (espejo del corte del servidor).
import * as v from 'valibot'
import {
  comparativaEquipos,
  metricasPorVendedor,
  type MetricasVendedor,
} from './inteligencia'
import { enVentanaOperativa, VENTANA_CONVERTIDOS_DIAS } from './resumen-cartera'
import type { Actividad, Lead, Miembro } from './tipos'

export const MetricasVendedoresSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  ventana_convertidos_dias: v.number(),
  // F2.4 (decisión D1): la MÉTRICA pasa al mes calendario del núcleo mientras
  // la VISTA sigue recortando a 45 días. El payload lo declara para que el
  // front rotule sin adivinar; opcionales porque el espejo demo no las emite.
  ventana_metrica: v.optional(v.string()),
  mes_metrica: v.optional(v.string()),
  vendedores: v.array(v.object({
    vendedor_id: v.string(),
    rol_crm: v.picklist(['vendedor', 'supervisor', 'gerencia']),
    activo: v.boolean(),
    activos: v.number(),
    capital_pen: v.number(),
    capital_usd: v.number(),
    convertidos: v.number(),
    conversion_pct: v.number(),
    sin_tocar: v.number(),
    dias_sin_actividad_max: v.number(),
  })),
  equipos: v.array(v.object({
    supervisor_id: v.string(),
    vendedores: v.number(),
    activos: v.number(),
    capital_pen: v.number(),
    capital_usd: v.number(),
    convertidos: v.number(),
    conversion_pct: v.number(),
    parkeados: v.number(),
  })),
})

export type MetricasVendedoresPayload = v.InferOutput<typeof MetricasVendedoresSchema>

/** Fila de la comparativa de equipos — el shape que ya devuelve comparativaEquipos. */
export interface FilaEquipo {
  supervisor: Miembro
  vendedores: number
  activos: number
  capitalPEN: number
  capitalUSD: number
  convertidos: number
  conversion: number
  parkeados: number
}

export interface MetricasVendedoresOperativas {
  /** Ranking por miembro del roster recibido (capital PEN desc), ceros incluidos. */
  filas: MetricasVendedor[]
  /** Comparativa por supervisor activo (orden del servidor: capital PEN desc). */
  equipos: FilaEquipo[]
  generadoEn: string
  /**
   * Mes ('YYYY-MM-DD') cuando la métrica de conversión/convertidos es el MES
   * CALENDARIO del núcleo (F2.4, D1); null = espejo demo, que sigue midiendo
   * la ventana operativa de 45 días. Los rótulos leen esto, no adivinan.
   */
  mesMetrica: string | null
}

/**
 * Payload del RPC → shape operativo. `roster` decide QUÉ filas se muestran
 * (cada pantalla pasa su subconjunto: los vendedores del supervisor, los de
 * un equipo desplegado…); un miembro sin fila en el payload sale en ceros —
 * igual que hoy con metricasPorVendedor sobre un ámbito sin leads suyos.
 * `equipo` es el roster COMPLETO para nombrar supervisores; una fila del
 * payload sin miembro con quien unirse se descarta (sin nombre no hay fila
 * honesta — el payload no trae nombres por diseño).
 */
export function mapearMetricasVendedores(
  payload: MetricasVendedoresPayload,
  roster: readonly Miembro[],
  equipo: readonly Miembro[],
  derivaDias = 0,
): MetricasVendedoresOperativas {
  // Mismo trato que mapearColaAccion: la foto del RPC congela el único RELOJ
  // del payload (`dias_sin_actividad_max`, el «Última actividad hace X» del
  // supervisor) y sin deriva se queda clavado entre refetches. El llamador la
  // calcula contra su reloj LOCAL. Los contadores no envejecen: son conteos.
  const deriva = Number.isFinite(derivaDias) ? Math.max(0, derivaDias) : 0
  const porId = new Map(payload.vendedores.map((f) => [f.vendedor_id, f]))
  const filas: MetricasVendedor[] = roster
    .map((m) => {
      const f = porId.get(m.perfil_id)
      return {
        m,
        activos: f?.activos ?? 0,
        capitalPEN: f?.capital_pen ?? 0,
        capitalUSD: f?.capital_usd ?? 0,
        convertidos: f?.convertidos ?? 0,
        conversion: f?.conversion_pct ?? 0,
        sinTocar: f?.sin_tocar ?? 0,
        // El 0 de quien no tiene abiertos es un CENTINELA («sin reloj que
        // mirar» — la UI dice 'Sin leads abiertos'), no un instante:
        // envejecerlo inventaría una última actividad que no existe.
        diasSinActividadMax: f != null && f.activos > 0 ? f.dias_sin_actividad_max + deriva : 0,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN || a.m.perfil_id.localeCompare(b.m.perfil_id))
  const porPerfil = new Map(equipo.map((m) => [m.perfil_id, m]))
  const equipos: FilaEquipo[] = payload.equipos.flatMap((e) => {
    const supervisor = porPerfil.get(e.supervisor_id)
    if (!supervisor) return []
    return [{
      supervisor,
      vendedores: e.vendedores,
      activos: e.activos,
      capitalPEN: e.capital_pen,
      capitalUSD: e.capital_usd,
      convertidos: e.convertidos,
      conversion: e.conversion_pct,
      parkeados: e.parkeados,
    }]
  })
  return {
    filas,
    equipos,
    generadoEn: payload.generado_en,
    mesMetrica: payload.ventana_metrica === 'mes_calendario' ? (payload.mes_metrica ?? null) : null,
  }
}

/**
 * Espejo demo sobre el estado VIVO: las mismas funciones que las pantallas
 * usaban hasta F1b, sobre el ámbito recortado a la ventana operativa — así
 * demo y real cuentan convertidos con el MISMO corte de 45 días.
 */
export function metricasVendedoresDesdeAmbito(
  roster: readonly Miembro[],
  equipo: readonly Miembro[],
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  ahoraMs: number,
): MetricasVendedoresOperativas {
  const ventana = leads.filter((l) => enVentanaOperativa(l, ahoraMs))
  return {
    filas: metricasPorVendedor([...roster], ventana, [...actividades], ahoraMs),
    equipos: comparativaEquipos([...equipo], ventana, [...actividades]),
    generadoEn: new Date(ahoraMs).toISOString(),
    // El espejo demo sigue midiendo la ventana de 45 días (deuda N4-N6): no
    // afirma el mes calendario que no calcula.
    mesMetrica: null,
  }
}

/**
 * Ventana de la métrica de conversión, en palabras, para los rótulos de
 * Gestión de equipo (F3, H9/D1). El servidor declara `ventana_metrica:
 * mes_calendario` desde F2.4 y el rótulo nombra ESE mes; el espejo demo (y un
 * servidor previo a F2.4) no lo declaran y conservan la verdad que sí miden:
 * la ventana operativa de 45 días. Un solo texto fijo mentiría en uno de los
 * dos mundos.
 */
export function ventanaConversionEnPalabras(mesMetrica: string | null): string {
  if (mesMetrica == null) return `${VENTANA_CONVERTIDOS_DIAS} días`
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    month: 'long',
    year: 'numeric',
  }).format(new Date(`${mesMetrica}T12:00:00Z`))
}
