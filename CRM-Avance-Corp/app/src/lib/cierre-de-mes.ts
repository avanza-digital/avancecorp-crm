import * as v from 'valibot'
import { EnteroNoNegativoRpcSchema, FechaHoraSchema, FechaSchema, TextoNoVacioSchema } from './esquemas-rpc'

/**
 * El estado de la MAQUINARIA del cierre de mes (`crm.cierre_mes_estado_fn`):
 * cuándo se sella el mes en curso, qué mes está pendiente y si el ciclo
 * automático se atascó. No trae cifras de nadie: es el estado del reloj.
 *
 * ⚠️ NO CONFUNDIR con `cierre-estado.ts`, que es de los CIERRES de VENTA
 * (los tratos). Nombres parecidos ya costaron un despliegue; de ahí el
 * `-de-mes` en el nombre del módulo, igual que el `_mes_` de la función.
 *
 * El contrato es fail-closed (`strictObject`) y sus claves salen de EJECUTAR
 * la función en sus cinco situaciones —no de leer la migración—, con el
 * generador `supabase/scripts/fixture-cierre-mes-estado.sql`. Leer no es
 * ejecutar: así se escaparon 2 de las 4 claves del apagón de metas del
 * 2026-08-15. Ninguna clave es opcional a propósito: el contrato nace CON el
 * servidor ya en producción, y si el servidor retrocediera no perdería claves
 * — desaparecería la función entera.
 */

const MesSchema = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}$/, 'Mes YYYY-MM inválido'))

const MesDelCicloSchema = v.strictObject({
  mes: MesSchema,
  mes_nombre: TextoNoVacioSchema,
  cierra_el: FechaSchema,
})

/**
 * Los TRES estados los nombra el servidor; el front no deduce ninguno.
 * `hoy` existe para que la lectura literal («ya pasó la fecha y sigue
 * abierto») no grite «atascado» las nueve horas que separan la medianoche
 * del cron de las 09:20 — una alarma que suena en falso deja de mirarse.
 */
const PendienteCierreSchema = v.strictObject({
  mes: MesSchema,
  mes_nombre: TextoNoVacioSchema,
  cierra_el: FechaSchema,
  dias_para_cierre: EnteroNoNegativoRpcSchema,
  estado: v.picklist(['en_ventana', 'hoy', 'atascado']),
})

const UltimoCerradoSchema = v.strictObject({
  mes: MesSchema,
  mes_nombre: TextoNoVacioSchema,
  cerrado_en: FechaHoraSchema,
  automatico: v.boolean(),
})

export const CierreMesEstadoSchema = v.strictObject({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  hoy: FechaSchema,
  zona: v.literal('America/Lima'),
  mes_en_curso: MesDelCicloSchema,
  pendiente: v.nullable(PendienteCierreSchema),
  ultimo_cerrado: v.nullable(UltimoCerradoSchema),
})

export type CierreMesEstadoRpc = v.InferOutput<typeof CierreMesEstadoSchema>
export type PendienteCierre = NonNullable<CierreMesEstadoRpc['pendiente']>
export type EstadoPendiente = PendienteCierre['estado']
