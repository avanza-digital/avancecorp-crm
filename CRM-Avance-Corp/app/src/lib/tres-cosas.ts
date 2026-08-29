// lib/tres-cosas.ts — la franja «Hoy, tres cosas» del supervisor (F3,
// 2026-08-23). Ley de Tesler aplicada: el SISTEMA absorbe la priorización del
// día — qué mirar primero — en vez de dejar que el supervisor escanee cinco
// tarjetas. Máximo TRES intervenciones (Hick/Miller), cada una con su acción.
//
// Reglas de la casa que esta función custodia:
// · Sin dato NO hay tarjeta: un candidato solo existe si su fuente llegó
//   (nada de «—» en la franja; la degradación se avisa en AvisoDegradacion).
// · Presupuesto de color: rojo = interviene HOY (nuevos sin responder,
//   no-show repetido); ámbar = esta semana. El rojo va siempre primero.
// · Espejo de la campana (lib/alertas.ts): mismas DECISIONES y mismos
//   umbrales (no_asistio ≥ 2 · sin acción ≥ 3, crítica ≥ 5). Los CONTEOS
//   pueden diferir a propósito: la campana deduplica lead a lead y trabaja
//   sobre ambito.leads (tope 2000); la franja lee los agregados del RPC
//   (universo completo, foto actual). Misma decisión, lentes distintas —
//   auditado y aceptado (Codex F3 #2).
// · Degradación honesta: con cola null (cargando o error) el candidato NO
//   existe y no se inventa urgencia desde el store local; el fallo se avisa
//   en AvisoDegradacion, que es el canal de errores de la pantalla (F3 #4).
import type { MetricaAgendaVendedor } from './metricas-agenda'
import { haceTexto } from './inteligencia'
import { TOPE_ESTANCADOS, type ColaAccionOperativa } from './cola-accion'

/** Pestaña de la cola a la que salta una cosa (espejo del tablist de HOY). */
export type PestanaColaDestino = 'urgente' | 'sin_movimiento' | 'todo'

export type DestinoCosa =
  | { tipo: 'pestana'; pestana: PestanaColaDestino }
  | { tipo: 'vista'; vista: 'derivaciones' | 'equipo' }

export interface CosaDeHoy {
  id: 'sin_responder' | 'no_asistio' | 'por_repartir' | 'sin_accion' | 'sin_movimiento'
  severidad: 'critica' | 'atencion'
  texto: string
  /** Etiqueta del enlace/botón — siempre hay UNA acción al lado del rojo. */
  accion: string
  destino: DestinoCosa
}

export interface TresCosasInput {
  /** Cola operativa (null = sin dato: ese candidato no existe). */
  cola: ColaAccionOperativa | null
  /** Total autorizado por resumen_cartera_fn (null = sin dato). */
  totalPorRepartir: number | null
  /** Espera observable del parkeado más rezagado, en días (null = sin detalle). */
  esperaMasLargaReparto: number | null
  /** Métricas de agenda por analista (vacío = sin dato o sin rezago). */
  vendedoresAgenda: readonly MetricaAgendaVendedor[]
}

/** Peso del candidato dentro de su severidad (menor = primero). */
const PESO: Record<CosaDeHoy['id'], number> = {
  sin_responder: 0,
  no_asistio: 1,
  por_repartir: 2,
  sin_accion: 3,
  sin_movimiento: 4,
}

const TOPE = 3

/**
 * Deriva las (a lo sumo) tres intervenciones del día del supervisor.
 * Devuelve [] cuando no hay nada que hacer O nada que decir con datos: la
 * franja entera no se pinta — el silencio también es información.
 */
export function tresCosasDeHoy({
  cola,
  totalPorRepartir,
  esperaMasLargaReparto,
  vendedoresAgenda,
}: TresCosasInput): CosaDeHoy[] {
  const cosas: CosaDeHoy[] = []

  // 1 · Nuevos sin responder — la interrupción del día (un lead nuevo se
  //     enfría por horas). Autoridad del CONTEO: el resumen por bucket del
  //     RPC. La SEVERIDAD sale de los items: un nuevo de dos horas es media
  //     para el RPC y pintarlo rojo desalinearía franja, cola y campana
  //     (Codex F3 #1) — rojo solo cuando algún sin_responder ya es crítico.
  const sinResponder = cola?.porBucket.sin_responder ?? 0
  if (cola != null && sinResponder > 0) {
    const hayCritico = cola.items.some(
      (i) => i.bucket === 'sin_responder' && i.sev === 'critica',
    )
    cosas.push({
      id: 'sin_responder',
      severidad: hayCritico ? 'critica' : 'atencion',
      texto: `${sinResponder} ${sinResponder === 1 ? 'nuevo sin responder' : 'nuevos sin responder'}`,
      accion: 'Ver',
      destino: { tipo: 'pestana', pestana: 'urgente' },
    })
  }

  // 2 · No-show repetido — el otro rojo del presupuesto (≥2, umbral de la
  //     campana y de «Tu equipo hoy»). Con varios analistas se agrupa.
  // Solo ANALISTAS activos: el RPC también trae la fila del propio
  // supervisor, y sin este filtro su agenda ocupaba un cupo disfrazada de
  // problema de analista (Codex F3 #3) — mismo corte que la campana.
  const vendedores = vendedoresAgenda.filter((v) => v.rol === 'vendedor' && v.activo)
  const conNoShow = vendedores
    .filter((v) => v.no_asistio >= 2)
    .sort((a, b) => b.no_asistio - a.no_asistio || a.vendedor_id.localeCompare(b.vendedor_id))
  const peorNoShow = conNoShow[0]
  if (peorNoShow != null) {
    cosas.push({
      id: 'no_asistio',
      severidad: 'critica',
      texto: conNoShow.length === 1
        ? `${peorNoShow.nombre}: ${peorNoShow.no_asistio} citas sin asistir`
        : `${conNoShow.length} analistas con citas sin asistir`,
      accion: 'Ver equipo',
      destino: { tipo: 'vista', vista: 'equipo' },
    })
  }

  // 3 · Por repartir — el conteo es SIEMPRE el del servidor; el rezago solo
  //     acompaña si el detalle local llegó (misma regla del KPI compacto).
  if (totalPorRepartir != null && totalPorRepartir > 0) {
    cosas.push({
      id: 'por_repartir',
      severidad: 'atencion',
      texto: `${totalPorRepartir} por repartir`
        + (esperaMasLargaReparto != null ? ` · el más rezagado ${haceTexto(esperaMasLargaReparto)}` : ''),
      accion: 'Repartir',
      destino: { tipo: 'vista', vista: 'derivaciones' },
    })
  }

  // 4 · Analista con más leads sin próxima acción (≥3, umbral de la campana).
  const conSinAccion = vendedores
    .filter((v) => v.leads_sin_accion >= 3)
    .sort((a, b) => b.leads_sin_accion - a.leads_sin_accion || a.vendedor_id.localeCompare(b.vendedor_id))
  const peorSinAccion = conSinAccion[0]
  if (peorSinAccion != null) {
    cosas.push({
      id: 'sin_accion',
      // Desde 5 es crítico — el MISMO umbral que la campana (Codex F3 #1).
      severidad: peorSinAccion.leads_sin_accion >= 5 ? 'critica' : 'atencion',
      texto: conSinAccion.length === 1
        ? `${peorSinAccion.nombre}: ${peorSinAccion.leads_sin_accion} leads sin próxima acción`
        : `${conSinAccion.length} analistas con leads sin próxima acción`,
      accion: 'Ver equipo',
      destino: { tipo: 'vista', vista: 'equipo' },
    })
  }

  // 5 · Sin movimiento — el peor caso del bloque estancados del RPC (≥5 días).
  const peorEstancado = cola?.estancados[0]
  if (cola != null && peorEstancado != null) {
    // Al tope del RPC el conteo dice «50+», igual que la pestaña: con 50
    // justos afirmar «50» sería mentir por omisión (Codex F3 #6).
    const conteoEstancados = cola.estancados.length >= TOPE_ESTANCADOS
      ? `${TOPE_ESTANCADOS}+`
      : String(cola.estancados.length)
    cosas.push({
      id: 'sin_movimiento',
      severidad: 'atencion',
      texto: `${conteoEstancados} sin movimiento · el peor lleva ${haceTexto(peorEstancado.dias).replace('hace ', '')}`,
      accion: 'Ver',
      destino: { tipo: 'pestana', pestana: 'sin_movimiento' },
    })
  }

  // Rojo primero, luego el peso fijo: el orden es una decisión, no un azar.
  return cosas
    .sort((a, b) => (
      (a.severidad === b.severidad ? 0 : a.severidad === 'critica' ? -1 : 1)
      || PESO[a.id] - PESO[b.id]
    ))
    .slice(0, TOPE)
}
