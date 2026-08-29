import * as v from 'valibot'

/**
 * Contrato runtime de `crm.metricas_agenda_fn` (JSON V1) — la fotografía
 * atómica de la agenda del equipo que consume el panel "Agenda del equipo".
 *
 * Igual que en metricas-distribucion: la respuesta se valida COMPLETA y con
 * objetos estrictos — si una migración parcial o un dato corrupto cambia
 * cualquier rama, la pantalla falla cerrada en vez de mezclar métricas con
 * semánticas distintas. El ámbito lo recorta el SERVIDOR (un supervisor ve su
 * subárbol incluyéndose a sí mismo).
 *
 * Qué significa cada métrica del analista:
 * - toques / toques_por_dia: llamadas, WhatsApp y reuniones registradas en el
 *   periodo (las 'nota' NO cuentan como toque).
 * - reuniones_realizadas: reuniones efectivamente registradas en el periodo.
 * - completadas / no_asistio / canceladas / pct_completadas: cierres de tareas
 *   DEL PERIODO, atribuidos por `actualizado_en` (cuándo se cerró, no cuándo
 *   se creó); pct_completadas es null cuando no hubo cierres que porcentuar.
 * - canceladas_asesor / canceladas_sistema: el desglose de `canceladas` (que
 *   sigue siendo el TOTAL). El sentinel legacy `asesor` indica que una persona
 *   anuló la tarea porque ya no
 *   hacía falta; sistema = se canceló sola al convertirse o descartarse el
 *   lead. Las del sistema pesaban en el denominador de pct_completadas hasta
 *   2026-07-26 y eso castigaba al analista justamente por CERRAR la venta
 *   (convertir cancela sus pendientes).
 * - canceladas_ajenas: la parte de `canceladas_asesor` que firmó OTRO (su
 *   supervisor o gerencia), no el analista de la tarea. También queda fuera del
 *   denominador — decisión de Miguel del 2026-07-26: si no tuvo control sobre
 *   esa tarea, no puede bajarle la nota. O sea que el denominador del % es
 *   completadas + no_asistio + (canceladas_asesor − canceladas_ajenas).
 * - tareas_creadas / reuniones_agendadas / reprogramaciones: planificación
 *   registrada dentro del periodo.
 * - pendientes / vencidas / leads_sin_accion: FOTO ACTUAL (no dependen del
 *   periodo) — carga viva de tareas y leads abiertos sin próxima acción.
 */

// `vendedor_id` es uuid en producción, pero el contrato admite texto no vacío
// para que la MISMA validación cubra el fixture demo ('d-v1', 'd-sup1'…).
const IdMiembroSchema = v.pipe(v.string(), v.minLength(1))
const TextoNoVacioSchema = v.pipe(v.string(), v.minLength(1))
const FechaSchema = v.pipe(v.string(), v.isoDate())
const FechaHoraSchema = v.pipe(
  v.string(),
  v.check((valor) => Number.isFinite(Date.parse(valor)), 'Fecha/hora inválida'),
)
const EnteroNoNegativoSchema = v.pipe(v.number(), v.integer(), v.minValue(0))
const NumeroNoNegativoSchema = v.pipe(v.number(), v.finite(), v.minValue(0))

const VendedorAgendaSchema = v.strictObject({
  vendedor_id: IdMiembroSchema,
  nombre: TextoNoVacioSchema,
  rol: v.picklist(['vendedor', 'supervisor']),
  activo: v.boolean(),
  toques: EnteroNoNegativoSchema,
  toques_por_dia: NumeroNoNegativoSchema,
  reuniones_realizadas: EnteroNoNegativoSchema,
  completadas: EnteroNoNegativoSchema,
  no_asistio: EnteroNoNegativoSchema,
  canceladas: EnteroNoNegativoSchema,
  // OPCIONALES A PROPÓSITO, aunque el servidor nuevo SIEMPRE las manda. Este
  // objeto es `strictObject`: una clave que sobra hace fallar la pantalla
  // entera. Declararlas opcionales es lo que permite que la migración y el
  // deploy del front no tengan que ser simultáneos — en cualquiera de los dos
  // órdenes el panel sigue en pie, y con la BD vieja simplemente no hay
  // desglose que pintar. `?? 0` en los consumidores, nunca `!`.
  canceladas_asesor: v.optional(EnteroNoNegativoSchema),
  canceladas_sistema: v.optional(EnteroNoNegativoSchema),
  canceladas_ajenas: v.optional(EnteroNoNegativoSchema),
  pct_completadas: v.nullable(v.number()),
  tareas_creadas: EnteroNoNegativoSchema,
  reuniones_agendadas: EnteroNoNegativoSchema,
  reprogramaciones: EnteroNoNegativoSchema,
  pendientes: EnteroNoNegativoSchema,
  vencidas: EnteroNoNegativoSchema,
  leads_sin_accion: EnteroNoNegativoSchema,
})

export const MetricasAgendaSchema = v.strictObject({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  periodo: v.strictObject({
    desde: FechaSchema,
    hasta: FechaSchema,
    dias: v.pipe(v.number(), v.integer(), v.minValue(1)),
    zona: v.literal('America/Lima'),
  }),
  // El servidor lo entrega ordenado por nombre; el orden no se re-valida aquí
  // (no cambia semántica) pero el panel lo respeta tal cual llega.
  vendedores: v.array(VendedorAgendaSchema),
})

export type MetricaAgendaVendedor = v.InferOutput<typeof VendedorAgendaSchema>
export type MetricasAgenda = v.InferOutput<typeof MetricasAgendaSchema>
