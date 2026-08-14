// El estado del cierre de un lead — el CONTRATO del front con
// `crm.cierres_estado_fn` (migración 20260814100746).
//
// Por qué existe: gerencia ya puede anular un cierre de Avance
// (`crm.anular_cierre_avance`, 20260813235119), pero la tabla donde eso queda
// escrito es deny-by-default con cero policies y cero grants — a propósito. Sin
// esta lectura la anulación sería INVISIBLE en la aplicación: se anularía, la
// pantalla se recargaría igual que antes y el segundo intento moriría con «ese
// cierre ya estaba anulado».
//
// Decisiones de contrato que NO son estilo:
// - `v.object` (no strict), como los demás payloads de RPC: una clave nueva del
//   servidor no debe romper un bundle viejo.
// - `canal` SÍ es picklist: un canal nuevo cambia qué botón se ofrece, y eso no
//   se inventa solo — exige tocar este archivo en el MISMO release.
// - AUSENTE ≠ DESCONOCIDO. El servidor solo manda los leads que tienen algo que
//   decir; un convertido de Avance sano no viaja. Ese default se escribe UNA vez
//   aquí (`estadoDelCierre`) y no en cada pantalla, porque escrito dos veces
//   diverge y la ficha acabaría ofreciendo un botón que la cartera no marca.
import * as v from 'valibot'
import { FechaHoraSchema, UuidSchema } from './esquemas-rpc'

/** Los dos mundos donde un lead puede cerrar. Espejo del `canal` que arma la RPC. */
export const CANALES_CIERRE = ['avance', 'cooperativa'] as const
export type CanalCierre = (typeof CANALES_CIERRE)[number]

export const CierreEstadoSchema = v.object({
  lead_id: UuidSchema,
  canal: v.picklist(CANALES_CIERRE),
  /** null = el cierre existe y NO está anulado (el caso de un coop sano). */
  anulado_en: v.nullable(FechaHoraSchema),
  /** La razón escrita. Obligatoria en el servidor al anular: a quien se le quita
   *  el mérito se le debe una explicación, no un número que baja solo. */
  motivo: v.nullable(v.string()),
})

export const CierresEstadoSchema = v.array(CierreEstadoSchema)

export type CierreEstado = v.InferOutput<typeof CierreEstadoSchema>

/** El tope que impone `crm.cierres_estado_fn`: esto sirve a una página en
 *  pantalla, no a un volcado. Alineado con `p_limite` de `cartera_pagina_fn`. */
export const MAX_LEADS_ESTADO = 200

/**
 * Ids normalizados: sin duplicados y en orden estable.
 *
 * No es cosmética. La clave de caché se deriva de esta lista, y con el array
 * crudo —identidad nueva en cada render, y el mismo lead repetido si aparece dos
 * veces en pantalla— cada render sería una clave distinta y la pantalla pediría
 * lo mismo una y otra vez.
 */
export function normalizarLeadIds(ids: readonly string[]): string[] {
  return [...new Set(ids)].sort()
}

/** Índice por lead, para cruzar contra las filas que hay en pantalla. */
export function indexarCierresEstado(filas: readonly CierreEstado[]): Map<string, CierreEstado> {
  return new Map(filas.map((f) => [f.lead_id, f]))
}

export interface EstadoCierre {
  canal: CanalCierre
  anulado: boolean
  anuladoEn: string | null
  motivo: string | null
}

/**
 * El estado de un lead, con el default explícito.
 *
 * ⚠️ La ausencia significa «cerró en Avance y no está anulado», NO «no se sabe».
 * El servidor omite ese caso a propósito para que el payload no crezca con la
 * operación normal, así que el default es parte del contrato — no una suposición.
 */
export function estadoDelCierre(estado: CierreEstado | undefined): EstadoCierre {
  return {
    canal: estado?.canal ?? 'avance',
    anulado: estado?.anulado_en != null,
    anuladoEn: estado?.anulado_en ?? null,
    motivo: estado?.motivo ?? null,
  }
}

/**
 * ¿Se le puede ofrecer a esta persona «Anular el cierre» de este lead?
 *
 * Las cuatro condiciones, y ninguna es decorativa:
 * - **gerencia**: la RPC devuelve 42501 a cualquier otro rol. Esto es UX, la
 *   seguridad la pone la RLS (ver `lib/roles.ts`).
 * - **convertido**: sin cierre no hay nada que anular.
 * - **canal Avance**: un cierre en COOPERATIVA se anula con su propia RPC, que
 *   además guarda la foto de lo anulado; `crm.anular_cierre_avance` lo rechaza a
 *   propósito. Sin esta condición, el único lead convertido que hoy existe en
 *   producción mostraría justo el botón que no funciona.
 * - **no anulado ya**: la anulación es de una sola dirección.
 */
export function puedeAnularCierreAvance(params: {
  rol: string | null | undefined
  etapa: string
  estado: CierreEstado | undefined
}): boolean {
  if (params.rol !== 'gerencia') return false
  if (params.etapa !== 'convertido') return false
  const { canal, anulado } = estadoDelCierre(params.estado)
  return canal === 'avance' && !anulado
}
