// lib/resumen-cartera.ts — contrato y espejo demo de crm.resumen_cartera_fn (F1).
// El payload jsonb (version:1) es la fuente de los tiles de Cartera/Pipeline en
// sesión real; en demo el MISMO shape se calcula aquí desde el estado vivo del
// store (crear un lead en demo debe mover los tiles — bloqueante del plan F1).
// La semántica es espejo de la migración 20260809043802 (y su reescritura
// 20260809144920): ventana de convertidos de 45 días, USD estricto (cualquier
// otra moneda cae a PEN), parkeado = abierto sin vendedor, y PEN y USD JAMÁS
// se suman.
import * as v from 'valibot'
import {
  TIPOS_CONTACTO_K,
  TERMINALES_K,
  type Actividad,
  type Lead,
} from './tipos'
import { DIA_MS } from './inteligencia'

/**
 * Ventana del ámbito operativo para leads convertidos (decisión de Miguel
 * 2026-08-08, plan F0§5): un convertido con más de 45 días deja de ser lead.
 * La comparten el corte de `listarLeadsDelAmbito`, este espejo demo y la
 * certificación del payload del RPC (`ventana_convertidos_dias`): si el
 * servidor cambiara la ventana, el wrapper falla el contrato en vez de
 * mezclar dos cortes distintos en la misma pantalla.
 */
export const VENTANA_CONVERTIDOS_DIAS = 45
export const VENTANA_CONVERTIDOS_MS = VENTANA_CONVERTIDOS_DIAS * DIA_MS

const CapitalMonedaSchema = v.object({
  pen: v.number(),
  usd: v.number(),
})

/** Orden canónico del embudo en el payload (4 activas + 2 terminales). */
const ETAPAS_EMBUDO = [
  'nuevo',
  'contactado',
  'reunion_agendada',
  'propuesta_enviada',
  'convertido',
  'descartado',
] as const

export const ResumenCarteraSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  ventana_convertidos_dias: v.number(),
  totales: v.object({
    vivos: v.number(),
    abiertos: v.number(),
    asignados: v.number(),
    parkeados: v.number(),
    convertidos: v.number(),
    descartados: v.number(),
    asignados_pen: v.number(),
    asignados_usd: v.number(),
  }),
  capital: v.object({
    asignado: CapitalMonedaSchema,
    parkeado: CapitalMonedaSchema,
    ganado: CapitalMonedaSchema,
  }),
  conversion: v.object({
    convertidos: v.number(),
    base: v.number(),
    pct: v.number(),
  }),
  descartes: v.object({
    total: v.number(),
    sin_motivo: v.number(),
    por_motivo: v.array(v.object({ motivo: v.string(), n: v.number() })),
  }),
  embudo: v.array(v.object({ etapa: v.picklist(ETAPAS_EMBUDO), n: v.number() })),
  sin_tocar: v.number(),
})

export type ResumenCartera = v.InferOutput<typeof ResumenCarteraSchema>

const montoDe = (l: Lead): number =>
  Number.isFinite(l.monto_estimado) ? l.monto_estimado : 0

/** USD estricto: cualquier otra moneda cae a PEN (espejo de capitalPorMoneda). */
const esUsd = (l: Lead): boolean => l.moneda === 'USD'

/**
 * Espejo demo de crm.resumen_cartera_fn sobre el ámbito VIVO de la sesión demo.
 * Recibe el ámbito ya recortado por rol (useCRMData().ambito) y aplica encima
 * las MISMAS reglas del servidor: solo activos, ventana de convertidos y
 * agregados por moneda sin sumar PEN+USD.
 *
 * El sello del cierre usa la MISMA cadena de fallback que cierres-del-mes
 * (`convertido_en ?? actualizado_en ?? creado_en`): en el servidor
 * `convertido_en` existe SIEMPRE (lo pone el trigger en la misma transacción
 * del paso a convertido), así que el fallback solo puede actuar en demo — los
 * fixtures nacieron sin sello — o sobre un espejo optimista local, mundos
 * donde el RPC no participa. Un convertido ilegible (fecha rota) queda fuera,
 * igual que `null >= corte` en SQL.
 */
/**
 * ¿El lead pertenece al ámbito OPERATIVO? Activo y, si es convertido, dentro
 * de la ventana de 45 días (con la cadena de fallback de cierres-del-mes —
 * ver el comentario de resumenCarteraDesdeAmbito). Compartida por TODOS los
 * espejos demo de F1 para que apliquen el mismo corte que el servidor.
 */
export function enVentanaOperativa(l: Lead, ahoraMs: number): boolean {
  if (!l.activo) return false
  if (l.etapa !== 'convertido') return true
  const selloMs = Date.parse(l.convertido_en ?? l.actualizado_en ?? l.creado_en)
  return Number.isFinite(selloMs) && selloMs >= ahoraMs - VENTANA_CONVERTIDOS_MS
}

export function resumenCarteraDesdeAmbito(
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  ahoraMs: number,
): ResumenCartera {
  const ambito = leads.filter((l) => enVentanaOperativa(l, ahoraMs))

  const abiertos = ambito.filter((l) => !TERMINALES_K.has(l.etapa))
  const asignados = abiertos.filter((l) => l.vendedor_id != null)
  const parkeados = abiertos.filter((l) => l.vendedor_id == null)
  const convertidos = ambito.filter((l) => l.etapa === 'convertido')
  const descartados = ambito.filter((l) => l.etapa === 'descartado')

  const suma = (subconjunto: readonly Lead[], usd: boolean): number =>
    subconjunto.reduce((acc, l) => (esUsd(l) === usd ? acc + montoDe(l) : acc), 0)

  // "Sin tocar" = abiertos CON dueño que nadie ha contactado jamás (los 5 tipos
  // de TIPOS_CONTACTO; una `reasignacion` del sistema no es trabajo comercial).
  const leadsContactados = new Set<string>()
  for (const a of actividades) {
    if (TIPOS_CONTACTO_K.has(a.tipo)) leadsContactados.add(a.lead_id)
  }
  const sinTocar = asignados.filter((l) => !leadsContactados.has(l.id)).length

  const porEtapa = new Map<string, number>()
  for (const l of ambito) porEtapa.set(l.etapa, (porEtapa.get(l.etapa) ?? 0) + 1)

  const porMotivo = new Map<string, number>()
  for (const l of descartados) {
    if (l.motivo_descarte != null) {
      porMotivo.set(l.motivo_descarte, (porMotivo.get(l.motivo_descarte) ?? 0) + 1)
    }
  }

  // Espejo de conversionGlobal: base = vivos CON vendedor (terminales incluidos;
  // los parkeados no cuentan porque nadie los trabaja).
  const baseConversion = ambito.filter((l) => l.vendedor_id != null)
  const convertidosConVendedor = convertidos.filter((l) => l.vendedor_id != null)

  return {
    version: 1,
    generado_en: new Date(ahoraMs).toISOString(),
    ventana_convertidos_dias: VENTANA_CONVERTIDOS_DIAS,
    totales: {
      vivos: ambito.length,
      abiertos: abiertos.length,
      asignados: asignados.length,
      parkeados: parkeados.length,
      convertidos: convertidos.length,
      descartados: descartados.length,
      asignados_pen: asignados.filter((l) => !esUsd(l)).length,
      asignados_usd: asignados.filter((l) => esUsd(l)).length,
    },
    capital: {
      asignado: { pen: suma(asignados, false), usd: suma(asignados, true) },
      parkeado: { pen: suma(parkeados, false), usd: suma(parkeados, true) },
      ganado: { pen: suma(convertidos, false), usd: suma(convertidos, true) },
    },
    conversion: {
      convertidos: convertidosConVendedor.length,
      base: baseConversion.length,
      pct: baseConversion.length > 0
        ? Math.round((100 * convertidosConVendedor.length) / baseConversion.length)
        : 0,
    },
    descartes: {
      total: descartados.length,
      sin_motivo: descartados.filter((l) => l.motivo_descarte == null).length,
      por_motivo: [...porMotivo.entries()]
        .map(([motivo, n]) => ({ motivo, n }))
        .sort((a, b) => b.n - a.n || a.motivo.localeCompare(b.motivo)),
    },
    embudo: ETAPAS_EMBUDO.map((etapa) => ({ etapa, n: porEtapa.get(etapa) ?? 0 })),
    sin_tocar: sinTocar,
  }
}
