import * as v from 'valibot'
import { EnteroNoNegativoRpcSchema, FechaHoraSchema, FechaSchema, TextoNoVacioSchema } from './esquemas-rpc'
import { fmtFecha } from './format'

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

export interface AvisoCierreMes {
  tono: 'aviso' | 'alarma'
  titulo: string
  detalle: string
}

/**
 * El texto del banner del ciclo, decidido desde el estado que NOMBRA el
 * servidor — el front no deduce fechas ni compara relojes. `null` = nada que
 * decir: sin mes pendiente no hay banner («la cadencia gobierna los avisos»,
 * regla de Miguel). Los tres estados son tres frases distintas a propósito:
 * `hoy` NO es alarma — la ventana abre a las 00:00 y el ciclo corre a las
 * 09:20, y una alarma que suena nueve horas en falso cada día 10 deja de
 * mirarse justo la vez que sí importa.
 */
export function avisoDelCiclo(estado: CierreMesEstadoRpc): AvisoCierreMes | null {
  const pendiente = estado.pendiente
  if (!pendiente) return null
  switch (pendiente.estado) {
    case 'en_ventana':
      return {
        tono: 'aviso',
        titulo: `${pendiente.mes_nombre} se cierra el ${fmtFecha(pendiente.cierra_el)}`,
        detalle: pendiente.dias_para_cierre === 1
          ? 'Queda 1 día de ajuste: anulaciones y correcciones, antes de que sus cifras queden selladas.'
          : `Quedan ${pendiente.dias_para_cierre} días de ajuste: anulaciones y correcciones, antes de que sus cifras queden selladas.`,
      }
    case 'hoy':
      return {
        tono: 'aviso',
        titulo: `${pendiente.mes_nombre} se cierra hoy`,
        // HORARIO, no hecho consumado: el servidor mantiene `hoy` las 24 horas
        // del día del sello, así que a las 15:00 con el cron caído un «desde
        // ese momento quedan selladas» sería falso (hallazgo #7). Si mañana
        // sigue abierto, el estado pasa a `atascado` y ahí sí suena la alarma.
        detalle: 'El ciclo automático pasa a las 09:20 de Lima. Mientras el mes siga abierto se puede ajustar; si mañana no se ha sellado, se marcará atascado.',
      }
    case 'atascado':
      return {
        tono: 'alarma',
        titulo: `El cierre de ${pendiente.mes_nombre} está atascado`,
        detalle: `Debió sellarse el ${fmtFecha(pendiente.cierra_el)} y sigue abierto: el ciclo automático no lo consiguió. Hay que revisar el motivo — el candado impide sellar meses posteriores mientras tanto.`,
      }
  }
}
