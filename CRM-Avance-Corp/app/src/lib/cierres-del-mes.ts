// Cierres del MES vigente (Lima) — la definición ÚNICA de "ventas del mes".
//
// POR QUÉ existe este módulo: las metas de `crm.objetivos` son MENSUALES (una
// fila por mes calendario y rol), así que el numerador que se enfrenta a ellas
// tiene que ser del mes también. Contar `etapa === 'convertido'` sobre toda la
// vida del ámbito y compararlo con la cuota del mes hace que el marcador mienta
// hacia arriba de forma PERMANENTE desde el segundo mes de operación — y es la
// cifra con la que se juzga a la fuerza comercial.
//
// El mes de CIERRE sale de `convertido_en`: el sello que pone el trigger
// `trg_leads_cambio_etapa` en la MISMA transacción del paso a `convertido`, y
// que `leads_before_update` restaura desde OLD ante cualquier escritura del
// cliente API. Es inmutable por construcción: nada de lo que haga el asesor
// después puede moverlo.
//
// ANTES salía de `actualizado_en`, apoyado en la premisa de que "un lead
// cerrado ya no se edita". La premisa era FALSA: `store.editarLead` no tenía
// guard de terminal y el bloque <Datos> de la ficha seguía ofreciendo "Editar"
// y "Completar" sobre convertidos. Corregirle el teléfono a un lead ganado en
// agosto lo mudaba al mes de la corrección — un cierre de más en un mes y uno
// de menos en el real, sobre la cifra con la que se juzga a la fuerza
// comercial. (Las dos puertas están cerradas desde 2026-07-26; el sello propio
// hace que ni una tercera pueda mentir.)
//
// FALLBACK a `actualizado_en ?? creado_en` SOLO cuando no hay sello: modo demo,
// una base sin la columna, un optimista local que aún no volvió del servidor —
// y los DESCARTADOS, que no tienen `convertido_en` (su sello propio,
// `descartado_en`, todavía no viaja al navegador). Es el comportamiento viejo,
// el mismo que conservan `lib/series-comerciales` y la RPC
// `crm.metricas_agenda_fn`: los convertidos ya no se mueven; los descartados
// siguen expuestos a esa deriva hasta que se traiga `descartado_en`.
import { fechaLima } from './agenda-derivada'
import { periodoLima } from './objetivos'
import type { Lead } from './tipos'

/**
 * ¿El sello de cierre del lead cae dentro del mes calendario `periodo`
 * ('YYYY-MM-01' de Lima, tal como lo devuelve `periodoLima`)?
 *
 * En Lima SIEMPRE: con la zona del navegador, un cierre del 31 a las 22:00 de
 * Lima visto desde Europa ya sería del mes siguiente y saldría del marcador.
 */
export function cerradoEnPeriodo(lead: Lead, periodo: string): boolean {
  const ms = Date.parse(lead.convertido_en ?? lead.actualizado_en ?? lead.creado_en)
  return Number.isFinite(ms) && `${fechaLima(ms).slice(0, 7)}-01` === periodo
}

export interface CierresDelMes {
  /** Leads convertidos DENTRO del mes vigente — el numerador de la meta. */
  convertidos: number
  /**
   * Resueltos del mes = convertidos + descartados. Es el denominador honesto de
   * la conversión del periodo: un lead que sigue abierto todavía no votó, y
   * meterlo al divisor castiga al equipo por tener pipeline.
   */
  resueltos: number
  /**
   * % de conversión del mes, o `null` cuando NADA se resolvió todavía.
   *
   * `null` ≠ 0: el día 1 del mes nadie ha cerrado ni descartado nada, y pintar
   * "0 %" en rojo crítico acusa de incumplimiento a quien simplemente no tiene
   * dato aún. Quien lo consuma debe tratar el null en neutro.
   */
  conversion: number | null
  /**
   * Convertidos de TODA la vida del ámbito. No alimenta ninguna meta: sirve
   * para decir en voz alta la diferencia cuando la pantalla muestra las dos
   * cifras y si no parecería contradecirse.
   */
  convertidosVida: number
}

/**
 * Cierres del mes vigente sobre los leads del ámbito YA cargados (la RLS del
 * servidor recorta el universo; cada rol mide el suyo).
 *
 * Deliberadamente NO filtra por `vendedor_id`: es el mismo universo que
 * `lib/series-comerciales` y que la meta del vendedor. Un lead descartado antes
 * de tener dueño también consumió un lead del embudo, y excluirlo inflaría la
 * conversión del periodo justo por el lado que conviene.
 */
export function cierresDelMes(leads: Lead[], ahoraMs: number): CierresDelMes {
  const periodo = periodoLima(ahoraMs)
  let convertidos = 0
  let resueltos = 0
  let convertidosVida = 0
  for (const lead of leads) {
    // Borrado suave: un lead desactivado no cuenta en ninguna cifra (mismo
    // criterio que lib/series-comerciales).
    if (!lead.activo) continue
    if (lead.etapa === 'convertido') convertidosVida += 1
    if (lead.etapa !== 'convertido' && lead.etapa !== 'descartado') continue
    if (!cerradoEnPeriodo(lead, periodo)) continue
    resueltos += 1
    if (lead.etapa === 'convertido') convertidos += 1
  }
  return {
    convertidos,
    resueltos,
    conversion: resueltos > 0 ? Math.round((convertidos / resueltos) * 100) : null,
    convertidosVida,
  }
}
