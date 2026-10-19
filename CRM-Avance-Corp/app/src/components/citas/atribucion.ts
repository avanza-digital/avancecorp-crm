// A quién se atribuye un resultado de citas y qué venta cierra una entrevista.
// Una sola regla para Resultados (`calcularAvanceCitas`) y la Proyección
// (`calcularProyeccion`): «no puede haber data distinta» (Miguel, 19/10/2026).
import type { ControlCitas } from '@/lib/control-citas'
import { entrevistaCompatibleConVenta } from './fecha-comercial'

/**
 * Dueño de un resultado (entrevista o venta): con la regla «asignacion», el
 * analista de origen del lead; si no, el del propio evento (cita o venta).
 */
export const reglaDueno = (regla: ControlCitas['analista_resultado'] | undefined, origenDe: (lead: string) => string | null | undefined) =>
  (lead: string, evento: string | null): string | null => regla === 'asignacion' ? origenDe(lead) ?? null : evento

/** Analistas de la consulta: los elegidos (sin elección, todos) del supervisor elegido (sin él, todos). */
export interface AmbitoAnalistas {
  analistas: ReadonlySet<string> | null
  equipo: string
  supervisorDe: (analista: string) => string | undefined
}
/** Un resultado sin dueño nunca entra en el ámbito. */
export const enAmbito = (id: string | null, ambito: AmbitoAnalistas): boolean => id !== null
  && (!ambito.analistas || ambito.analistas.has(id)) && (!ambito.equipo || ambito.supervisorDe(id) === ambito.equipo)

/**
 * Una venta cierra una entrevista si su fecha comercial no es anterior al día de
 * la entrevista. En la fila de un analista (`fila` = su id) la venta, además,
 * tiene que ser SUYA; en el total (`fila` null) cuenta la colaboración entre los
 * analistas del ámbito, que se recorta antes.
 */
export const ventaCierraEntrevista = (asistioEn: string | undefined, venta: { dueno: string | null; fecha_comercial: string | null }, fila: string | null) =>
  (fila === null || venta.dueno === fila) && entrevistaCompatibleConVenta(asistioEn, venta.fecha_comercial)
