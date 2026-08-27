// lib/metricas-conversiones-equipo.ts — contrato del payload de conversión del
// EQUIPO de un supervisor (RPC crm.metricas_conversiones_equipo_fn).
//
// POR QUÉ NO REUTILIZA MetricasConversionesSchema
// -----------------------------------------------
// Es la mitad de front del hallazgo que frenó la migración: el esquema de gerencia
// exige `cohorte`, `produccion`, `embudo`, `origenes` y `categorias` en la raíz —
// los CINCO agregados de toda la empresa que la RPC del supervisor NO calcula a
// propósito, porque calcularlos sería la fuga que se quiere evitar— y, por
// responsable, `contactados`, `reuniones_realizadas`, `capital_pen`, `capital_usd`
// y `tendencia_semanal`. Validar el payload de equipo con ese esquema fallaría
// SIEMPRE y el supervisor vería «las métricas no tienen el formato esperado» en vez
// de su ranking: exactamente la mentira que hoy evita `conversionDisponible={false}`.
//
// Un esquema propio, además, es la lectura correcta del fail-closed: cada payload
// se valida contra lo que SU productor promete, no contra el de otro rol.
//
// SUPERFICIE MÍNIMA A PROPÓSITO. Solo `{vendedor_id, leads, clientes,
// conversion_pct}`, que es todo lo que el ranking de conversión pinta (verificado
// en clasificarRankingConversion y en el componente RankingConversion). Sin capital
// —el dato más sensible del desglose—, sin PII y sin las señales que obligarían a
// leer actividades y tareas.
//
// OJO con la convención AS-BUILT, que es engañosa y se conserva por PARIDAD con
// gerencia: `clientes` NO son los leads convertidos a cliente, son los leads de la
// cohorte CON CONTRATO, y `conversion_pct = 100 * contratos / leads`. Cambiarla
// aquí haría que el mismo vendedor tuviera dos porcentajes distintos según quién
// mire, que es justo el bug que la decisión #10 quiere cerrar.
import * as v from 'valibot'
import type { ConversionEquipoVendedor } from './conversion-equipo'
import {
  estadoConversion,
  type ConversionVendedorAdaptada,
  type ConversionVendedoresAdaptada,
} from './conversion-vendedores'

const ResponsableEquipoSchema = v.object({
  vendedor_id: v.string(),
  leads: v.number(),
  clientes: v.number(),
  // `null` es un valor legítimo: sin muestra no hay porcentaje que afirmar.
  conversion_pct: v.nullable(v.number()),
  // F2.2 («Conversión única»): la cifra del NÚCLEO por responsable — la misma
  // aritmética que HOY/Metas/Conversiones, acreditada a QUIEN CERRÓ (ledger),
  // mientras `clientes` acredita al dueño actual de la ficha. Formas medidas
  // en el payload real de prod (27/08). Opcionales: un servidor previo a F2.2
  // o el espejo demo no las emiten y la pantalla degrada, jamás fabrica ceros.
  nucleo_divisor: v.optional(v.number()),
  nucleo_numerador: v.optional(v.number()),
  nucleo_conversion_pct: v.optional(v.nullable(v.number())),
})

/** Declaración del núcleo que sirvió las cifras (F2.2): base y ponderación. */
const NucleoEquipoSchema = v.object({
  base: v.string(),
  incluye_cartera: v.boolean(),
  peso_referido: v.number(),
  mes_peso: v.string(),
})

/**
 * Sondas del ranking (F2.2): paridad contra el núcleo mensual, lo que queda
 * fuera del roster de vendedores y las dos acreditaciones del mismo hecho
 * (`clientes` = dueño actual vs `nucleo_*` = quien cerró). `cuadra: false` es
 * la señal de F3.4: cifras en revisión, no un número inventado.
 */
const SondasEquipoSchema = v.object({
  cuadra: v.nullable(v.boolean()),
  paridad_nucleo: v.nullable(v.number()),
  paridad_filas: v.number(),
  divisor_fuera_del_roster: v.number(),
  numerador_fuera_del_roster: v.number(),
  cierres_anulados: v.number(),
  clientes_acreditados_a_otro_dueno: v.number(),
})

export const MetricasConversionesEquipoSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  /** Lo decide el SERVIDOR según el rol del actor, no el cliente por su cuenta. */
  alcance: v.picklist(['equipo', 'global']),
  periodo: v.object({ desde: v.string(), hasta: v.string() }),
  responsables: v.array(ResponsableEquipoSchema),
  nucleo: v.optional(NucleoEquipoSchema),
  sondas: v.optional(SondasEquipoSchema),
})

export type MetricasConversionesEquipo = v.InferOutput<typeof MetricasConversionesEquipoSchema>
export type ResponsableEquipo = v.InferOutput<typeof ResponsableEquipoSchema>

/**
 * Une el payload del equipo con las identidades del roster.
 *
 * Hermano de `adaptarConversionVendedores`, con dos diferencias deliberadas:
 *  - no calcula tendencia semanal (el payload no la trae, y el ranking no la usa);
 *  - un payload ausente NO es «todos a cero»: deja a cada vendedor `indisponible`,
 *    que es lo que el clasificador traduce a «fuera del ranking» en vez de a un
 *    0 % que se leería como un hecho.
 */
export function adaptarConversionEquipo(
  datos: MetricasConversionesEquipo | null | undefined,
  equipo: readonly ConversionEquipoVendedor[],
): ConversionVendedoresAdaptada<ResponsableEquipo> {
  const responsables = datos?.responsables
  const detallePorId = new Map((responsables ?? []).map((r) => [r.vendedor_id, r]))
  const identidadPorId = new Map<string, Pick<ConversionEquipoVendedor, 'nombre' | 'supervisorNombre'>>()

  for (const integrante of equipo) {
    if (!integrante.vendedorId || identidadPorId.has(integrante.vendedorId)) continue
    identidadPorId.set(integrante.vendedorId, {
      nombre: integrante.nombre,
      supervisorNombre: integrante.supervisorNombre,
    })
  }

  // Una fila válida de la RPC no desaparece por que su identidad aún no esté en el
  // roster; la etiqueta genérica evita exponer el UUID en pantalla.
  for (const r of responsables ?? []) {
    if (identidadPorId.has(r.vendedor_id)) continue
    identidadPorId.set(r.vendedor_id, {
      nombre: 'Vendedor no identificado',
      supervisorNombre: 'Equipo no disponible',
    })
  }

  // Una respuesta PARCIAL no puede repartir puestos solo entre los que llegaron:
  // o el bloque está completo o no hay ranking. Mismo criterio que gerencia.
  const completos = responsables !== undefined
    && detallePorId.size === responsables.length
    && [...identidadPorId.keys()].every((id) => detallePorId.has(id))

  const vendedores = [...identidadPorId.entries()].map<ConversionVendedorAdaptada<ResponsableEquipo>>(([vendedorId, identidad]) => {
    const detalle = completos ? (detallePorId.get(vendedorId) ?? null) : null
    return {
      vendedorId,
      ...identidad,
      detalle,
      estadoConversion: estadoConversion(detalle),
    }
  })

  return { responsablesDisponibles: completos, vendedores, tendenciaSemanal: null }
}
