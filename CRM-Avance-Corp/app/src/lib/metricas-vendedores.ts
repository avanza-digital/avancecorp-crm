// lib/metricas-vendedores.ts — contrato, mapper y espejo demo de
// crm.metricas_vendedores_fn (F1b). El payload viaja SIN nombres de personas
// (precedente metricas_conversiones_fn): el front une por id con su roster —
// ese join vive aquí, una sola vez. En demo la foto operativa sigue saliendo
// del estado vivo, pero la conversión sale del espejo mensual canónico.
import * as v from 'valibot'
import {
  comparativaEquipos,
  metricasPorVendedor,
  type MetricasVendedor,
} from './inteligencia'
import { enVentanaOperativa, VENTANA_CONVERTIDOS_DIAS } from './resumen-cartera'
import { EnteroNoNegativoRpcSchema, NumeroRpcSchema } from './esquemas-rpc'
import { porcentajeConversionCanonica } from './format'
import type { ConversionMensual } from './conversion-mensual'
import type { Actividad, Lead, Miembro } from './tipos'

/** Mismo redondeo positivo a dos decimales que usa el núcleo mensual. */
const redondearDos = (valor: number): number => (
  Math.round((valor + Number.EPSILON * Math.max(1, Math.abs(valor))) * 100) / 100
)

interface LecturaNucleoExacta {
  nucleo_divisor: number
  nucleo_numerador: number
  nucleo_conversion_pct: number | null
}

function lecturaNucleoCoherente(fila: LecturaNucleoExacta): boolean {
  if (fila.nucleo_divisor === 0) return fila.nucleo_conversion_pct === null
  if (fila.nucleo_conversion_pct == null) return false
  const esperada = redondearDos((100 * fila.nucleo_numerador) / fila.nucleo_divisor)
  return Math.abs(fila.nucleo_conversion_pct - esperada) < 1e-9
}

function idsUnicos<T>(filas: readonly T[], id: (fila: T) => string): boolean {
  return new Set(filas.map(id)).size === filas.length
}

const FilaVendedorSchema = v.pipe(
  v.object({
    vendedor_id: v.string(),
    rol_crm: v.picklist(['vendedor', 'supervisor', 'gerencia']),
    activo: v.boolean(),
    activos: v.number(),
    capital_pen: v.number(),
    capital_usd: v.number(),
    convertidos: v.number(),
    /** Campo entero heredado: se conserva por compatibilidad, pero la UI no
     * lo usa porque redondea y convierte NULL en 0. */
    conversion_pct: v.number(),
    operaciones_cartera: EnteroNoNegativoRpcSchema,
    nucleo_divisor: EnteroNoNegativoRpcSchema,
    nucleo_numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
    nucleo_conversion_pct: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0))),
    sin_tocar: v.number(),
    dias_sin_actividad_max: v.number(),
  }),
  v.check(
    (fila) => lecturaNucleoCoherente(fila),
    'La lectura exacta del vendedor no coincide con divisor y numerador',
  ),
)

const FilaEquipoSchema = v.pipe(
  v.object({
    supervisor_id: v.string(),
    vendedores: v.number(),
    activos: v.number(),
    capital_pen: v.number(),
    capital_usd: v.number(),
    convertidos: v.number(),
    /** Entero heredado: solo compatibilidad con bundles previos. */
    conversion_pct: v.number(),
    operaciones_cartera: EnteroNoNegativoRpcSchema,
    nucleo_divisor: EnteroNoNegativoRpcSchema,
    nucleo_numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
    nucleo_conversion_pct: v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0))),
    parkeados: v.number(),
  }),
  v.check(
    (fila) => lecturaNucleoCoherente(fila),
    'La lectura exacta del equipo no coincide con divisor y numerador',
  ),
)

export const MetricasVendedoresSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  ventana_convertidos_dias: v.number(),
  // F2.4 (decisión D1): la MÉTRICA pasa al mes calendario del núcleo mientras
  // la VISTA sigue recortando a 45 días. El payload lo declara para que el
  // front rotule sin adivinar; opcionales porque el espejo demo no las emite.
  ventana_metrica: v.optional(v.string()),
  mes_metrica: v.optional(v.string()),
  peso_referido: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(1))),
  vendedores: v.pipe(
    v.array(FilaVendedorSchema),
    v.check(
      (filas) => idsUnicos(filas, (fila) => fila.vendedor_id),
      'El payload contiene vendedores duplicados',
    ),
  ),
  equipos: v.pipe(
    v.array(FilaEquipoSchema),
    v.check(
      (filas) => idsUnicos(filas, (fila) => fila.supervisor_id),
      'El payload contiene equipos duplicados',
    ),
  ),
})

export type MetricasVendedoresPayload = v.InferOutput<typeof MetricasVendedoresSchema>

/** Fila de la comparativa de equipos — el shape que ya devuelve comparativaEquipos. */
export interface FilaEquipo {
  supervisor: Miembro
  vendedores: number
  activos: number
  capitalPEN: number
  capitalUSD: number
  convertidos: number
  conversion: number | null
  /** false = no llegó una lectura mensual para este equipo. */
  conversionDisponible: boolean
  operacionesCartera: number | null
  divisorConversion: number | null
  numeradorConversion: number | null
  parkeados: number
}

export interface MetricasVendedoresOperativas {
  /** Ranking por miembro del roster recibido (capital PEN desc), ceros incluidos. */
  filas: MetricaVendedorOperativa[]
  /** Comparativa por supervisor activo (orden del servidor: capital PEN desc). */
  equipos: FilaEquipo[]
  generadoEn: string
  /**
   * Mes ('YYYY-MM-DD') cuando la métrica de conversión/convertidos es el MES
   * CALENDARIO del núcleo (F2.4, D1); null = no hay lectura mensual canónica.
   * Los rótulos leen esto, no adivinan.
   */
  mesMetrica: string | null
}

/**
 * Fila que llega a Gestión de equipo. Separa la foto operativa heredada del
 * porcentaje exacto del núcleo: NULL y >100 son estados válidos, y las
 * operaciones de cartera permanecen visibles como parte del numerador.
 */
export interface MetricaVendedorOperativa extends Omit<MetricasVendedor, 'conversion'> {
  conversion: number | null
  /** Distingue una fila ausente de una fila presente con divisor mensual 0. */
  conversionDisponible: boolean
  /** null = el roster no tuvo fila en la foto RPC; nunca se maquilla como 0. */
  operacionesCartera: number | null
  divisorConversion: number | null
  numeradorConversion: number | null
}

/**
 * Payload del RPC → shape operativo. `roster` decide QUÉ filas se muestran
 * (cada pantalla pasa su subconjunto: los vendedores del supervisor, los de
 * un equipo desplegado…); un miembro sin fila conserva la foto operativa
 * heredada en cero, pero su conversión queda explícitamente indisponible: no
 * se publica 0 % ni se inventa la causa «sin divisor».
 * `equipo` es el roster COMPLETO para nombrar supervisores; una fila del
 * payload sin miembro con quien unirse se descarta (sin nombre no hay fila
 * honesta — el payload no trae nombres por diseño).
 */
export function mapearMetricasVendedores(
  payload: MetricasVendedoresPayload,
  roster: readonly Miembro[],
  equipo: readonly Miembro[],
  derivaDias = 0,
): MetricasVendedoresOperativas {
  // Mismo trato que mapearColaAccion: la foto del RPC congela el único RELOJ
  // del payload (`dias_sin_actividad_max`, el «Última actividad hace X» del
  // supervisor) y sin deriva se queda clavado entre refetches. El llamador la
  // calcula contra su reloj LOCAL. Los contadores no envejecen: son conteos.
  const deriva = Number.isFinite(derivaDias) ? Math.max(0, derivaDias) : 0
  const porId = new Map(payload.vendedores.map((f) => [f.vendedor_id, f]))
  const filas: MetricaVendedorOperativa[] = roster
    .map((m) => {
      const f = porId.get(m.perfil_id)
      return {
        m,
        activos: f?.activos ?? 0,
        capitalPEN: f?.capital_pen ?? 0,
        capitalUSD: f?.capital_usd ?? 0,
        convertidos: f?.convertidos ?? 0,
        // La columna exacta conserva NULL, decimales y >100. El entero
        // `conversion_pct` queda solo como compatibilidad del wire contract.
        conversion: f?.nucleo_conversion_pct ?? null,
        conversionDisponible: f != null,
        operacionesCartera: f?.operaciones_cartera ?? null,
        divisorConversion: f?.nucleo_divisor ?? null,
        numeradorConversion: f?.nucleo_numerador ?? null,
        sinTocar: f?.sin_tocar ?? 0,
        // El 0 de quien no tiene abiertos es un CENTINELA («sin reloj que
        // mirar» — la UI dice 'Sin leads abiertos'), no un instante:
        // envejecerlo inventaría una última actividad que no existe.
        diasSinActividadMax: f != null && f.activos > 0 ? f.dias_sin_actividad_max + deriva : 0,
      }
    })
    .sort((a, b) => b.capitalPEN - a.capitalPEN || a.m.perfil_id.localeCompare(b.m.perfil_id))
  const porPerfil = new Map(equipo.map((m) => [m.perfil_id, m]))
  const equipos: FilaEquipo[] = payload.equipos.flatMap((e) => {
    const supervisor = porPerfil.get(e.supervisor_id)
    if (!supervisor) return []
    return [{
      supervisor,
      vendedores: e.vendedores,
      activos: e.activos,
      capitalPEN: e.capital_pen,
      capitalUSD: e.capital_usd,
      convertidos: e.convertidos,
      // La comparativa usa el mismo núcleo exacto que las filas de vendedor;
      // `conversion_pct` queda únicamente para compatibilidad del wire.
      conversion: e.nucleo_conversion_pct,
      conversionDisponible: true,
      operacionesCartera: e.operaciones_cartera,
      divisorConversion: e.nucleo_divisor,
      numeradorConversion: e.nucleo_numerador,
      parkeados: e.parkeados,
    }]
  })
  return {
    filas,
    equipos,
    generadoEn: payload.generado_en,
    mesMetrica: payload.ventana_metrica === 'mes_calendario' ? (payload.mes_metrica ?? null) : null,
  }
}

/**
 * Espejo demo: la foto operativa (activos/capital/SLA) sigue saliendo del
 * estado vivo recortado a 45 días, pero conversión y cierres salen únicamente
 * del espejo mensual canónico. Sin ese payload, la conversión queda
 * explícitamente indisponible: nunca revive la fórmula local de 45 días.
 */
export function metricasVendedoresDesdeAmbito(
  roster: readonly Miembro[],
  equipo: readonly Miembro[],
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  ahoraMs: number,
  conversionMensual?: ConversionMensual | null,
): MetricasVendedoresOperativas {
  const ventana = leads.filter((l) => enVentanaOperativa(l, ahoraMs))
  const mensualPorVendedor = new Map(
    (conversionMensual?.responsables ?? []).map((fila) => [fila.vendedor_id, fila]),
  )
  const mensualPorSupervisor = new Map<string, ConversionMensual['responsables']>()
  for (const fila of conversionMensual?.responsables ?? []) {
    if (fila.supervisor_id == null) continue
    const actuales = mensualPorSupervisor.get(fila.supervisor_id)
    if (actuales) actuales.push(fila)
    else mensualPorSupervisor.set(fila.supervisor_id, [fila])
  }
  return {
    filas: metricasPorVendedor([...roster], ventana, [...actividades], ahoraMs)
      .map((fila) => {
        const mensual = mensualPorVendedor.get(fila.m.perfil_id)
        return {
          ...fila,
          convertidos: mensual == null
            ? fila.convertidos
            : mensual.cierres_no_referidos + mensual.cierres_referidos,
          conversion: mensual?.conversion_pct ?? null,
          conversionDisponible: mensual != null,
          operacionesCartera: mensual?.cartera.conversiones_clientes ?? null,
          divisorConversion: mensual?.divisor ?? null,
          numeradorConversion: mensual?.numerador ?? null,
        }
      }),
    equipos: comparativaEquipos([...equipo], ventana, [...actividades])
      .map((fila) => {
        const responsables = mensualPorSupervisor.get(fila.supervisor.perfil_id)
        const esperados = new Set(equipo
          .filter((miembro) => (
            miembro.activo
            && miembro.rol_crm === 'vendedor'
            && miembro.supervisor_id === fila.supervisor.perfil_id
          ))
          .map((miembro) => miembro.perfil_id))
        const recibidos = new Set(responsables?.map((responsable) => responsable.vendedor_id) ?? [])
        // Un agregado parcial sería más peligroso que una ausencia: parecería
        // el total del equipo. Exigimos igualdad exacta de conjuntos; duplicados,
        // faltantes y extras dejan la conversión del equipo indisponible.
        const disponible = responsables != null
          && recibidos.size === responsables.length
          && recibidos.size === esperados.size
          && [...esperados].every((id) => recibidos.has(id))
        const canonicos = disponible ? responsables : null
        const divisor = canonicos?.reduce(
          (total, responsable) => total + responsable.divisor,
          0,
        ) ?? null
        const numerador = canonicos == null
          ? null
          : redondearDos(canonicos.reduce(
            (total, responsable) => total + responsable.numerador,
            0,
          ))
        const operacionesCartera = canonicos?.reduce(
          (total, responsable) => total + responsable.cartera.conversiones_clientes,
          0,
        ) ?? null
        const convertidos = canonicos?.reduce(
          (total, responsable) => (
            total + responsable.cierres_no_referidos + responsable.cierres_referidos
          ),
          0,
        )
        return {
          ...fila,
          convertidos: convertidos ?? fila.convertidos,
          conversion: divisor != null && divisor > 0 && numerador != null
            ? redondearDos((100 * numerador) / divisor)
            : null,
          conversionDisponible: disponible,
          operacionesCartera,
          divisorConversion: divisor,
          numeradorConversion: numerador,
        }
      }),
    generadoEn: conversionMensual?.generado_en ?? new Date(ahoraMs).toISOString(),
    mesMetrica: conversionMensual == null ? null : `${conversionMensual.periodo.mes}-01`,
  }
}

/** Texto exacto de la cifra servida; NULL nunca se convierte en `0%`. */
export function textoConversionOperativa(conversion: number | null): string {
  return porcentajeConversionCanonica(conversion)
}

/**
 * Ventana de la métrica de conversión, en palabras, para los rótulos de
 * Gestión de equipo (F3, H9/D1). El servidor declara `ventana_metrica:
 * mes_calendario` desde F2.4 y el rótulo nombra ESE mes. Sin declaración no se
 * atribuye una lectura mensual: la foto operativa heredada conserva su rótulo
 * de 45 días. Un solo texto fijo mentiría en uno de los dos contratos.
 */
export function ventanaConversionEnPalabras(mesMetrica: string | null): string {
  if (mesMetrica == null) return `${VENTANA_CONVERTIDOS_DIAS} días`
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    month: 'long',
    year: 'numeric',
  }).format(new Date(`${mesMetrica}T12:00:00Z`))
}
