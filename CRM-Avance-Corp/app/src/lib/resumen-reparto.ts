// lib/resumen-reparto.ts — contrato y espejo de crm.resumen_reparto_fn (F1b tanda 3).
// El payload jsonb (version:1) es la fuente de los 4 tiles de "Repartir" en sesión
// real: la cola GLOBAL la cuenta el servidor y el navegador solo pinta.
// La semántica es espejo de la migración 20260809144912: MISMO predicado que
// private.leads_por_repartir_implementacion (activo, sin analista NI supervisor,
// las 4 etapas abiertas y no_contactar = false — Ley 29571), USD estricto
// (cualquier otra moneda cae a PEN) y PEN y USD JAMÁS se suman.
//
// A diferencia de lib/resumen-cartera, este espejo NO alimenta la pantalla en
// demo: no existe cola de reparto en los fixtures (todos los LEADS_DEMO tienen
// dueño o supervisor), así que calcularlo daría siempre cero. Vive como contrato
// EJECUTABLE — prueba que el shape del front y el del servidor son el mismo — y
// como generador de payloads en los tests. Ver use-resumen-reparto-operativo.
import * as v from 'valibot'
import { DIA_MS } from './inteligencia'
import type { ColaLead } from './tipos'

export const ResumenRepartoSchema = v.object({
  version: v.literal(1),
  // timestamptz del servidor ("…+00:00") vs ISO del espejo ("…Z"): v.string() a
  // secas a propósito — un validador de formato rechazaría uno de los dos.
  generado_en: v.string(),
  cola: v.object({
    total: v.number(),
    capital: v.object({ pen: v.number(), usd: v.number() }),
    espera_max_dias: v.number(),
    posible_credito: v.number(),
    // `origen` como string libre y NO v.picklist(ORIGENES_K): el safeParse de un
    // payload agregado es TODO-O-NADA, así que un origen nuevo en la base
    // tumbaría los cuatro tiles en vez de degradar una etiqueta.
    por_origen: v.array(v.object({ origen: v.string(), n: v.number() })),
  }),
})

export type ResumenReparto = v.InferOutput<typeof ResumenRepartoSchema>

/**
 * Espejo puro de crm.resumen_reparto_fn sobre una cola YA cargada. `ahoraMs`
 * entra SIEMPRE por parámetro (nunca Date.now() aquí dentro) para que el
 * cálculo sea determinista y testeable, igual que el resto de lib/.
 */
export function resumenRepartoDesdeCola(
  cola: readonly ColaLead[],
  ahoraMs: number,
): ResumenReparto {
  let pen = 0
  let usd = 0
  let posibleCredito = 0
  let esperaMaxDias = 0
  const porOrigen = new Map<string, number>()

  for (const l of cola) {
    const monto = Number.isFinite(l.monto_estimado) ? l.monto_estimado : 0
    // USD estricto — espejo de `filter (where moneda is distinct from 'USD')`.
    if (l.moneda === 'USD') usd += monto
    else pen += monto

    if (l.clasificacion_auto === 'posible_credito') posibleCredito += 1

    // Días ENTEROS de espera, nunca negativos (mismo cálculo que diasEnCola de
    // la pantalla). El servidor hace el floor UNA vez sobre el creado_en más
    // antiguo; como floor es monótona, el máximo de los floors es el mismo valor.
    const desde = Date.parse(l.creado_en)
    if (Number.isFinite(desde)) {
      const dias = Math.max(0, Math.floor((ahoraMs - desde) / DIA_MS))
      if (dias > esperaMaxDias) esperaMaxDias = dias
    }

    porOrigen.set(l.origen, (porOrigen.get(l.origen) ?? 0) + 1)
  }

  return {
    version: 1,
    generado_en: new Date(ahoraMs).toISOString(),
    cola: {
      total: cola.length,
      capital: { pen, usd },
      espera_max_dias: esperaMaxDias,
      posible_credito: posibleCredito,
      // Espejo de `order by x.n desc, x.origen`.
      por_origen: [...porOrigen.entries()]
        .map(([origen, n]) => ({ origen, n }))
        .sort((a, b) => b.n - a.n || a.origen.localeCompare(b.origen)),
    },
  }
}
