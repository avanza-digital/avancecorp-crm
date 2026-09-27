// lib/senal-equipo.ts — la lectura de UN analista en «Equipo hoy» (Hoy del
// supervisor, puesto de mando, 27/09/2026). Una sola severidad por persona:
// el punto, la cabecera («N en rojo · N en ámbar») y los chips salen de aquí,
// así nunca se contradicen. El borrador del diseño contaba a una persona en
// rojo Y en ámbar a la vez, y pintaba ámbar un no-show repetido que su chip
// decía rojo (Codex, revisión del plan).
//
// Umbrales de la casa, sin cambios (lib/semaforo.ts, «Tu equipo hoy»):
// · días sin actividad del lead más quieto: 2–5 ámbar · >5 rojo;
// · citas sin asistir: ≥2 rojo (una sola no es patrón);
// · leads sin próxima acción: ≥1 ámbar · ≥5 rojo (umbral de la campana);
// · tareas vencidas: ámbar.
// La severidad del analista es la PEOR de sus señales: nunca se rebaja.
import type { MetricaAgendaVendedor } from './metricas-agenda'
import { haceTexto } from './inteligencia'

export type NivelSenal = 'critico' | 'atencion'

export interface SenalAnalista {
  texto: string
  nivel: NivelSenal
}

export interface LecturaAnalista {
  /** null = sin señal · 'neutro' = sin cartera abierta: no hay nada que medir. */
  nivel: NivelSenal | 'neutro' | null
  /** Rojas primero; dentro de cada nivel, el orden fijo de arriba. */
  senales: SenalAnalista[]
}

export type RezagoAgenda = Pick<MetricaAgendaVendedor, 'no_asistio' | 'leads_sin_accion' | 'vencidas'>

/**
 * `rezago` null = la agenda no llegó (o el analista no tiene fila): solo se
 * juzga lo que hay, sin inventar «al día».
 */
export function lecturaAnalista(
  fila: { activos: number; diasSinActividadMax: number },
  rezago: RezagoAgenda | null | undefined,
): LecturaAnalista {
  if (fila.activos === 0) return { nivel: 'neutro', senales: [] }
  const senales: SenalAnalista[] = []
  if (rezago != null && rezago.no_asistio >= 2) {
    senales.push({ texto: `${rezago.no_asistio} citas sin asistir`, nivel: 'critico' })
  }
  if (rezago != null && rezago.leads_sin_accion > 0) {
    const n = rezago.leads_sin_accion
    senales.push({
      texto: `${n} ${n === 1 ? 'lead' : 'leads'} sin próxima acción`,
      nivel: n >= 5 ? 'critico' : 'atencion',
    })
  }
  const dias = fila.diasSinActividadMax
  if (dias >= 2) {
    senales.push({ texto: `Un lead sin actividad ${haceTexto(dias)}`, nivel: dias > 5 ? 'critico' : 'atencion' })
  }
  if (rezago != null && rezago.vencidas > 0) {
    const n = rezago.vencidas
    senales.push({ texto: `${n} ${n === 1 ? 'tarea vencida' : 'tareas vencidas'}`, nivel: 'atencion' })
  }
  // sort estable: las rojas suben y cada nivel conserva el orden de arriba.
  senales.sort((a, b) => (a.nivel === b.nivel ? 0 : a.nivel === 'critico' ? -1 : 1))
  const nivel = senales.length === 0 ? null : senales[0]?.nivel ?? null
  return { nivel, senales }
}

/** Conteo EXCLUSIVO de la cabecera: cada analista cuenta una sola vez. */
export function conteoSemaforoEquipo(lecturas: readonly LecturaAnalista[]): { rojo: number; ambar: number } {
  let rojo = 0
  let ambar = 0
  for (const l of lecturas) {
    if (l.nivel === 'critico') rojo += 1
    else if (l.nivel === 'atencion') ambar += 1
  }
  return { rojo, ambar }
}
