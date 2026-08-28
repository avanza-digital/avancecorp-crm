// lib/antiguedad-etapa.ts — ¿desde cuándo está el lead EN SU ETAPA ACTUAL?
//
// El hueco que cubre: `estancados()` y la cola miden INACTIVIDAD ("hace N días
// que nadie lo toca"). Un lead muy trabajado —cuatro llamadas esta semana— pero
// clavado tres semanas en la misma etapa no sale en ninguna señal, y es
// exactamente el que hay que rescatar o cerrar: consume tiempo del asesor y no
// avanza. Son medidas casi OPUESTAS; NO fusionarlas con `estancados`.
//
// ⚠️ POR QUÉ SE PARSEA `detalle` Y NO `metadata`. La columna
// `crm.actividades.metadata` SÍ trae `{etapa_anterior, etapa_nueva}` (la llena
// `private.trg_leads_cambio_etapa`), pero la RPC que alimenta al navegador
// —`actividades_del_ambito_fn`— NO la devuelve, y la frontera Valibot de
// `crm-api.ts` la descartaría igual. Traerla es una migración con DROP+CREATE
// de la RPC (⇒ ACL reemitida) y `gen:types`. `detalle` carga la misma
// información y ya viaja.
//
// Hay que aceptar LOS DOS formatos que existen en producción, porque los emiten
// dos escritores distintos:
//   · servidor  → claves crudas:  "nuevo → contactado"
//   · store/demo → labels es-PE:  "Nuevo → Contactado"  (y el descarte añade
//     un sufijo: "Contactado → Descartado · Motivo: Sin fondos — …")
import { ETAPAS, TERMINALES, type Actividad, type Etapa, type Lead } from './tipos'

/** Label es-PE → clave, para leer los `detalle` que escribe el front. */
const CLAVE_POR_LABEL = new Map<string, Etapa>(
  [
    ...[...ETAPAS, ...TERMINALES].map((e) => [e.label.toLowerCase(), e.k] as const),
    // Compatibilidad con detalles históricos ya persistidos antes del cambio
    // puramente visual de «reunión» a «cita».
    ['reunión agendada', 'reunion_agendada'] as const,
  ],
)
const CLAVES = new Set<string>([...ETAPAS, ...TERMINALES].map((e) => e.k))

/** La etapa DESTINO de un `cambio_etapa`, o null si el detalle no se entiende. */
export function etapaDestino(detalle: string | null | undefined): Etapa | null {
  if (!detalle) return null
  const flecha = detalle.indexOf('→')
  if (flecha < 0) return null
  // El sufijo del descarte (" · Motivo: …") va después; se corta por él.
  const bruto = detalle.slice(flecha + 1).split('·')[0]?.trim().toLowerCase()
  if (!bruto) return null
  if (CLAVES.has(bruto)) return bruto as Etapa
  return CLAVE_POR_LABEL.get(bruto) ?? null
}

/**
 * Instante en que el lead ENTRÓ a su etapa actual, o `null` si no se puede
 * saber (timeline sin el `cambio_etapa` correspondiente).
 *
 * Devuelve null en vez de caer a `creado_en` a propósito: un lead que lleva
 * meses en el CRM y entró a `propuesta_enviada` ayer daría "3 meses en esta
 * etapa", que es falso. Sin dato, no se afirma nada — el consumidor decide.
 */
export function entradaEnEtapa(lead: Lead, acts: readonly Actividad[]): string | null {
  let ultimo: string | null = null
  for (const a of acts) {
    if (a.lead_id !== lead.id || a.tipo !== 'cambio_etapa') continue
    if (etapaDestino(a.detalle) !== lead.etapa) continue
    if (!Number.isFinite(Date.parse(a.creado_en))) continue
    if (ultimo == null || a.creado_en > ultimo) ultimo = a.creado_en
  }
  return ultimo
}
