// La conversión mensual ponderada del analista — el CONTRATO del front con
// `crm.conversion_mensual_fn` (migración 20260811154434).
//
// La definición (vault: «Conversion mensual - definicion cerrada», 2026-08-10):
//   divisor   = leads NO referidos que el analista RECIBIÓ en el mes (asignación,
//               hora de Lima); entran abiertos y descartados, nada se cae.
//   numerador = cierres DEL MES: no referidos al 100 % + referidos × el peso
//               vigente (hoy 15 %). Un lead de julio cerrado en agosto suma
//               arriba en agosto y NO abajo.
//
// Decisiones de contrato que NO son estilo:
// - `v.object` (no strict) A PROPÓSITO: una clave nueva del servidor no debe
//   romper bundles viejos. Es lo contrario del cumplimiento (`v.strictObject`,
//   fail-closed) y está decidido así en el plan (§4).
// - `estado` es un `v.picklist` y un picklist SÍ rechaza valores desconocidos
//   aunque el objeto sea laxo: si faltara uno de los CUATRO estados aquí, el
//   payload ENTERO se caería por CONVERSION_MENSUAL_CONTRACT y las pantallas se
//   quedarían sin conversión (mismo tipo de defecto que el `maxValue(100)` que
//   este ciclo corrige en objetivos.ts).
// - `conversion_pct` NO tiene techo. Puede superar 100 con `estado='medible'` y
//   sin ninguna fila enferma (referidos que suman arriba y no abajo, cierres de
//   arrastre). El front NO recorta a 100 ni pinta barras acotadas con él.
// - `fuentes.*` son LITERALES fail-closed: si un servidor viejo (u otra
//   definición) colara otro reloj para el divisor, el parseo rechaza en vez de
//   pintar un número de otra fórmula.
// - `NumeroRpcSchema` en vez de `v.number()` crudo (a diferencia de sus
//   hermanas `metricas-conversiones*.ts`): `numerador` es `numeric` de Postgres
//   y PostgREST puede servirlo como string; el pipe lo normaliza a número.
import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  NumeroRpcSchema,
  UuidSchema,
} from './esquemas-rpc'
import { fmtFecha, numero } from './format'
import { CierreDelMesSchema } from './objetivos'

/** Porcentaje sin techo: la definición supera el 100 % por diseño. */
const PorcentajeSinTechoSchema = v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0)))

/** Mes calendario real. Rechaza ecos imposibles como `2026-13`. */
const MesCalendarioSchema = v.pipe(
  v.string(),
  v.regex(/^\d{4}-(?:0[1-9]|1[0-2])$/),
)

/** Los CUATRO estados que emite el servidor. `indisponible` NO está aquí a
 * propósito: es el quinto estado y lo produce SOLO el cliente (fail-closed de
 * colección incompleta en conversion-vendedores.ts), jamás el payload. */
export const ESTADOS_CONVERSION_MENSUAL = [
  'medible',
  'solo_referidos',
  'solo_arrastre',
  'sin_actividad',
] as const

const EstadoResponsableSchema = v.picklist(ESTADOS_CONVERSION_MENSUAL)

/** Vocabulario CERRADO — espejo del `case` de la migración. Añadir un motivo en
 * el servidor exige añadirlo aquí en el MISMO release. */
export const MotivoNoMedibleSchema = v.nullable(
  v.picklist([
    'sin_ledger',
    'anterior_al_ledger',
    'mes_parcial',
    'sin_supervisor',
    'supervisor_inactivo',
    'supervisor_no_es_supervisor',
  ]),
)

/** Cobertura global del núcleo mensual. Se exporta para que los adaptadores
 * que encadenan esta RPC con otras superficies conserven exactamente el mismo
 * criterio de publicación, incluido el estado provisional y sus sondas. */
export const CoberturaConversionSchema = v.pipe(
  v.object({
    /** false no siempre significa ocultar: `mes_parcial` se muestra provisional. */
    medible: v.boolean(),
    suelo_historico: v.nullable(FechaHoraSchema),
    motivo_no_medible: MotivoNoMedibleSchema,
    divisor_aproximado: EnteroNoNegativoRpcSchema,
    divisor_por_motivo: v.record(v.string(), EnteroNoNegativoRpcSchema),
    /** >0 invalida la publicación exacta: no se sabe a qué fila atribuirlo. */
    cierres_sin_episodio: EnteroNoNegativoRpcSchema,
    fuera_de_roster: v.object({
      analistas: EnteroNoNegativoRpcSchema,
      divisor: EnteroNoNegativoRpcSchema,
      cierres: EnteroNoNegativoRpcSchema,
      numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
    }),
  }),
  v.check(
    (cobertura) => cobertura.medible
      ? cobertura.motivo_no_medible == null
      : cobertura.motivo_no_medible != null,
    'La cobertura mensual contradice su motivo de disponibilidad',
  ),
)

const TramoProcedenciaSchema = v.pipe(
  v.object({
    /** null en el cubo `anteriores` (cierres de más de 11 meses atrás). */
    mes: v.nullable(MesCalendarioSchema),
    mes_nombre: v.string(),
    anio: v.nullable(v.pipe(NumeroRpcSchema, v.integer())),
    cierres: EnteroNoNegativoRpcSchema,
    cierres_referidos: EnteroNoNegativoRpcSchema,
  }),
  v.check(
    (tramo) => tramo.cierres_referidos <= tramo.cierres,
    'La procedencia mensual tiene más cierres referidos que cierres',
  ),
  v.check(
    (tramo) => tramo.mes == null
      ? tramo.anio == null
      : tramo.anio === Number(tramo.mes.slice(0, 4)),
    'La procedencia mensual contradice su año',
  ),
)

const ReferidosResponsableSchema = v.object({
  recibidos: EnteroNoNegativoRpcSchema,
  cerrados: EnteroNoNegativoRpcSchema,
  dados_de_alta: EnteroNoNegativoRpcSchema,
  aporta_pct: PorcentajeSinTechoSchema,
})

/** Un descuento que viene de un mes YA CERRADO: cuándo y por qué. `motivo` es
 * el texto libre de la anulación de gerencia (≤300), no un vocabulario. */
const OrigenAjusteSchema = v.object({
  periodo: MesCalendarioSchema,
  motivo: v.string(),
  numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
})

/**
 * Lo que se le está descontando al analista por cierres anulados de meses ya
 * pagados (20260815003742). Su `numerador` YA llega neto — esto es el PORQUÉ:
 * «un número que baja sin explicación es una llamada a soporte». `optional`
 * porque un `v.object` laxo también falla por clave AUSENTE, y la vuelta
 * atrás de la migración la haría desaparecer.
 *
 * DOS formas, comprobadas EJECUTANDO la función en el banco (2026-08-15):
 *   · mes VIVO:    { pendiente > 0, origenes: [...] }        — deuda por saldar
 *   · mes SELLADO: { aplicado, pendiente: 0, origenes: [] }  — lo ya restado
 * Sin declarar `aplicado`, Valibot lo DESCARTA y la foto de un mes cerrado
 * mostraba la conversión rebajada sin explicación alguna (hallazgo #2 de la
 * revisión adversaria).
 */
const AjusteConversionSchema = v.object({
  pendiente: v.pipe(NumeroRpcSchema, v.minValue(0)),
  aplicado: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0))),
  origenes: v.optional(v.array(OrigenAjusteSchema)),
})

export type AjusteConversion = v.InferOutput<typeof AjusteConversionSchema>

/**
 * Operaciones de cartera del mes acreditadas al analista — el sumando del
 * numerador que NO viene de leads (envoltorio de `20260824231133`; máx. una
 * operación elegible por cliente/mes). Es OBLIGATORIO en el contrato vigente:
 * si falta, no sabemos si hubo cero operaciones o si llegó el núcleo anterior,
 * y convertir esa ausencia en cero sería publicar una explicación falsa.
 */
const CarteraResponsableSchema = v.object({
  conversiones_clientes: EnteroNoNegativoRpcSchema,
  conversiones_renovacion: EnteroNoNegativoRpcSchema,
  conversiones_upgrade: EnteroNoNegativoRpcSchema,
  capital_renovado_pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_renovado_usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_adicional_pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
  capital_adicional_usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
  renovaciones_sin_desglose: EnteroNoNegativoRpcSchema,
})

/** El total agrega además el conteo económico de operaciones por tipo. */
const CarteraTotalSchema = v.object({
  ...CarteraResponsableSchema.entries,
  operaciones_renovacion: EnteroNoNegativoRpcSchema,
  operaciones_upgrade: EnteroNoNegativoRpcSchema,
})

const ResponsableConversionSchema = v.pipe(
  v.object({
    vendedor_id: UuidSchema,
    supervisor_id: v.nullable(UuidSchema),
    divisor: EnteroNoNegativoRpcSchema,
    cierres_no_referidos: EnteroNoNegativoRpcSchema,
    cierres_referidos: EnteroNoNegativoRpcSchema,
    /** Cierres del mes cuyo divisor fue OTRO mes: el sumando que explica un
     * ratio por encima de 100 sin recorrer `procedencia`. */
    cierres_de_arrastre: EnteroNoNegativoRpcSchema,
    numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
    conversion_pct: PorcentajeSinTechoSchema,
    estado: EstadoResponsableSchema,
    procedencia: v.array(TramoProcedenciaSchema),
    referidos: ReferidosResponsableSchema,
    ajuste: v.optional(AjusteConversionSchema),
    cartera: CarteraResponsableSchema,
  }),
  v.check((fila) => {
    if (fila.divisor === 0) return fila.conversion_pct == null
    if (fila.conversion_pct == null) return false
    const calculado = 100 * fila.numerador / fila.divisor
    const tolerancia = 0.005000001
      + Number.EPSILON * Math.max(1, Math.abs(calculado)) * 8
    return Math.abs(fila.conversion_pct - calculado) <= tolerancia
  }, 'La conversión del responsable no corresponde a su numerador y divisor'),
  v.check((fila) => {
    const cierres = fila.cierres_no_referidos + fila.cierres_referidos
    const estadoEsperado = fila.divisor > 0
      ? 'medible'
      : fila.referidos.recibidos > 0
        ? 'solo_referidos'
        : cierres > 0 || fila.cartera.conversiones_clientes > 0
          ? 'solo_arrastre'
          : 'sin_actividad'
    return fila.estado === estadoEsperado
  }, 'El estado del responsable contradice su actividad mensual'),
  v.check((fila) => {
    const cierres = fila.cierres_no_referidos + fila.cierres_referidos
    const cierresProcedencia = fila.procedencia.reduce((total, tramo) => total + tramo.cierres, 0)
    const referidosProcedencia = fila.procedencia.reduce(
      (total, tramo) => total + tramo.cierres_referidos,
      0,
    )
    return fila.referidos.cerrados === fila.cierres_referidos
      && fila.cierres_de_arrastre <= cierres
      && cierresProcedencia === cierres
      && referidosProcedencia === fila.cierres_referidos
  }, 'El desglose de cierres del responsable no cuadra'),
)

const TotalConversionSchema = v.object({
  analistas: EnteroNoNegativoRpcSchema,
  divisor: EnteroNoNegativoRpcSchema,
  cierres_no_referidos: EnteroNoNegativoRpcSchema,
  cierres_referidos: EnteroNoNegativoRpcSchema,
  cierres_de_arrastre: EnteroNoNegativoRpcSchema,
  referidos_recibidos: EnteroNoNegativoRpcSchema,
  numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
  conversion_pct: PorcentajeSinTechoSchema,
  referidos_aporta_pct: PorcentajeSinTechoSchema,
  cartera: CarteraTotalSchema,
})

export const ConversionMensualSchema = v.pipe(
  v.object({
    version: v.literal(1),
    /** Revisión de metas que gobernó esta lectura. Es opcional solo durante el
     * rollout frontend→backend; cuando el servidor la publique, las pantallas la
     * comparan con cumplimiento y cosecha antes de mostrar el ranking. */
    revision: v.optional(EnteroNoNegativoRpcSchema),
    generado_en: FechaHoraSchema,
    /** Lo decide el SERVIDOR, que conoce el recorte; el adaptador exige el eco
     * exacto del alcance que el consumidor declaró esperar. */
    alcance: v.picklist(['propio', 'equipo', 'global']),
    periodo: v.object({
      mes: MesCalendarioSchema,
      mes_nombre: v.string(),
      anio: v.pipe(NumeroRpcSchema, v.integer()),
      zona: v.literal('America/Lima'),
      desde: FechaHoraSchema,
      hasta: FechaHoraSchema,
    }),
    ponderacion: v.object({
      referido: v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(1)),
      fuente: v.literal('crm.conversion_pesos'),
    }),
    // Tokens de versión del contrato, no la fórmula (la migración documenta por
    // qué `numerador` dice `resultado_en` aunque la consulta defienda con
    // coalesce). Cambiarlos exige cambiar servidor y front en el MISMO deploy —
    // que es exactamente lo que este literal existe para impedir por accidente.
    fuentes: v.object({
      divisor: v.literal('crm.lead_asignaciones.asignado_en'),
      numerador: v.literal('crm.lead_asignaciones.resultado_en'),
      referido: v.literal('crm.lead_asignaciones.origen'),
    }),
    cobertura: CoberturaConversionSchema,
    /** Estado del mismo snapshot mensual. Se conserva para impedir que una
     * transición abierto → sellado mezcle esta lectura con cumplimiento. */
    cierre: v.optional(CierreDelMesSchema),
    /** Mismo total que `total.cartera`, también publicado en la raíz por el RPC. */
    cartera: CarteraTotalSchema,
    total: TotalConversionSchema,
    responsables: v.array(ResponsableConversionSchema),
  }),
  v.check((payload) => {
    const [anio, mes] = payload.periodo.mes.split('-').map(Number)
    return payload.periodo.anio === anio
      && Date.parse(payload.periodo.desde) === Date.UTC(anio!, mes! - 1, 1, 5)
      && Date.parse(payload.periodo.hasta) === Date.UTC(anio!, mes!, 1, 5)
  }, 'El período mensual contradice sus límites de America/Lima'),
  v.check((payload) => {
    if (payload.total.divisor === 0) return payload.total.conversion_pct == null
    if (payload.total.conversion_pct == null) return false
    const calculado = 100 * payload.total.numerador / payload.total.divisor
    const tolerancia = 0.005000001
      + Number.EPSILON * Math.max(1, Math.abs(calculado)) * 8
    return Math.abs(payload.total.conversion_pct - calculado) <= tolerancia
  }, 'La conversión total no corresponde a su numerador y divisor'),
  v.check((payload) => {
    if (payload.total.divisor === 0) return payload.total.referidos_aporta_pct == null
    if (payload.total.referidos_aporta_pct == null) return false
    const calculado = 100 * payload.ponderacion.referido
      * payload.total.cierres_referidos / payload.total.divisor
    const tolerancia = 0.005000001
      + Number.EPSILON * Math.max(1, Math.abs(calculado)) * 8
    return Math.abs(payload.total.referidos_aporta_pct - calculado) <= tolerancia
  }, 'El aporte referido total no corresponde a la ponderación declarada'),
  v.check((payload) => payload.responsables.every((fila) => {
    if (fila.divisor === 0) return fila.referidos.aporta_pct == null
    if (fila.referidos.aporta_pct == null) return false
    const calculado = 100 * payload.ponderacion.referido
      * fila.cierres_referidos / fila.divisor
    const tolerancia = 0.005000001
      + Number.EPSILON * Math.max(1, Math.abs(calculado)) * 8
    return Math.abs(fila.referidos.aporta_pct - calculado) <= tolerancia
  }), 'El aporte referido de un responsable no corresponde a la ponderación declarada'),
  v.check((payload) => {
    const ids = new Set(payload.responsables.map((fila) => fila.vendedor_id))
    if (ids.size !== payload.responsables.length) return false

    const fuera = payload.cobertura.fuera_de_roster
    // `total.analistas` cuenta SOLO las filas con derecho a puesto. La
    // produccion fuera del ranking sigue formando parte de las medidas
    // empresariales de abajo, pero no convierte supervisores u otras
    // identidades externas en analistas rankeables.
    const analistasRankeables = payload.responsables.length
    const divisor = payload.responsables.reduce((total, fila) => total + fila.divisor, 0)
      + fuera.divisor
    const cierres = payload.responsables.reduce(
      (total, fila) => total + fila.cierres_no_referidos + fila.cierres_referidos,
      0,
    ) + fuera.cierres
    const numerador = payload.responsables.reduce((total, fila) => total + fila.numerador, 0)
      + fuera.numerador
    const tolerancia = 1e-9 + Number.EPSILON
      * Math.max(1, Math.abs(payload.total.numerador), Math.abs(numerador)) * 16

    return payload.total.analistas === analistasRankeables
      && payload.total.divisor === divisor
      && payload.total.cierres_no_referidos + payload.total.cierres_referidos === cierres
      && Math.abs(payload.total.numerador - numerador) <= tolerancia
  }, 'El total mensual no cuadra con responsables y fuera de roster'),
  v.check((payload) => {
    const motivos = Object.values(payload.cobertura.divisor_por_motivo)
      .reduce((total, cantidad) => total + cantidad, 0)
    const cierres = payload.total.cierres_no_referidos + payload.total.cierres_referidos
    return motivos === payload.total.divisor
      && payload.cobertura.divisor_aproximado <= payload.total.divisor
      && payload.total.cierres_de_arrastre <= cierres
  }, 'Las sondas de cobertura no cuadran con el total mensual'),
  v.check((payload) => Object.entries(payload.cartera).every(
    ([campo, valor]) => payload.total.cartera[campo as keyof typeof payload.cartera] === valor,
  ), 'La cartera raíz contradice la cartera del total'),
  v.check(
    (payload) => payload.alcance !== 'propio' || payload.responsables.length <= 1,
    'El alcance propio no puede contener varios responsables',
  ),
)

export type ConversionMensual = v.InferOutput<typeof ConversionMensualSchema>
export type ResponsableConversionMensual = ConversionMensual['responsables'][number]
export type EstadoResponsableConversion = ResponsableConversionMensual['estado']
export type TramoProcedencia = ResponsableConversionMensual['procedencia'][number]

/**
 * «de agosto 12, de julio 3, de junio 1» — la línea que responde a la pregunta
 * de gerencia: ¿de qué mes venía cada cierre?
 *
 * El mes ya viene NOMBRADO del servidor (array literal en la migración, inmune
 * al locale). El año solo se escribe cuando difiere del año del periodo — «de
 * diciembre 2025 2» — y el cubo de más de 11 meses atrás se rotula «de meses
 * anteriores». Sin cierres devuelve '' y la pantalla decide su vacío.
 */
export function lineaProcedencia(
  procedencia: readonly TramoProcedencia[],
  anioPeriodo: number,
): string {
  return procedencia
    .filter((tramo) => tramo.cierres > 0)
    .map((tramo) => {
      if (tramo.mes === null) return `de meses anteriores ${tramo.cierres}`
      const anio = tramo.anio != null && tramo.anio !== anioPeriodo ? ` ${tramo.anio}` : ''
      return `de ${tramo.mes_nombre}${anio} ${tramo.cierres}`
    })
    .join(', ')
}

/**
 * «20 registrados · 12 cerrados · aporta 2,0 %» — el bloque de referidos.
 *
 * «Registrados» son los RECIBIDOS (decisión D3): con T10 ya no están en el
 * divisor, pero son la población de la que salen los cierres que ponderan.
 * `aporta_pct` viene en PUNTOS de porcentaje y aquí se escribe como «%» porque
 * así lo pidió Miguel (definición cerrada, «expresado en %, no en puntos»).
 * Con divisor 0 (`solo_referidos`) el aporte no existe y el tramo se omite.
 */
export function lineaReferidos(
  referidos: ResponsableConversionMensual['referidos'],
): string {
  const base = `${numero(referidos.recibidos)} registrados · ${numero(referidos.cerrados)} cerrados`
  if (referidos.aporta_pct == null) return base
  // SIEMPRE un decimal («aporta 2.0 %», no «aporta 2 %»): con el 15 % la cifra
  // casi nunca es entera y un «2 %» pelado parecería otra magnitud al lado de
  // un «1.6 %». `numero()` no fuerza decimales mínimos, así que se fija aquí.
  // es-PE usa PUNTO decimal (como el resto del CRM); la coma del vault era prosa.
  const aporta = referidos.aporta_pct.toLocaleString('es-PE', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })
  return `${base} · aporta ${aporta} %`
}

/** Qué hacer con la cifra del mes cuando el servidor dice que no es medible. */
export interface LecturaCobertura {
  /** ¿Se ENSEÑA el porcentaje? */
  mostrar: boolean
  /** Por qué no es definitivo, en la voz del usuario. `null` si lo es. */
  aviso: string | null
}

/**
 * Traduce `cobertura` a una decisión de pantalla.
 *
 * Decisión de Miguel (2026-08-14): **un mes incompleto SE VE**. «No importa que
 * no se tome en cuenta para los pagos, pero necesito verla para verificar que
 * todo esté ok». Es la misma regla que ya fijó para las alertas: la cadencia
 * gobierna los avisos, no lo que se puede consultar.
 *
 * Lo que esto arregla: los cuatro sitios que pintan la conversión colapsaban
 * TRES situaciones distintas en «Sin datos de asignación para este mes», y con
 * `mes_parcial` esa frase es sencillamente falsa — hay recibidos y hay cierres,
 * lo único que pasa es que al mes le faltan los días anteriores al ledger. Un
 * aviso que niega datos que existen es lo que hace desconfiar del sistema
 * entero. Los motivos que SÍ significan «no hay nada» se siguen ocultando: ahí
 * la frase era correcta.
 *
 * ⚠️ Esto decide qué se MUESTRA, no qué se JUZGA. El veredicto «en meta» de
 * Inteligencia Comercial sigue exigiendo un mes medible a propósito: enseñar una
 * cifra provisional es honesto, dictaminar sobre ella no lo sería.
 */
export function lecturaCobertura(
  cobertura: ConversionMensual['cobertura'] | null | undefined,
): LecturaCobertura {
  if (cobertura == null) return { mostrar: false, aviso: null }
  if (cobertura.cierres_sin_episodio > 0) {
    const n = cobertura.cierres_sin_episodio
    return {
      mostrar: false,
      aviso: `Cifras en revisión: ${n} ${n === 1 ? 'cierre no tiene' : 'cierres no tienen'} episodio verificable.`,
    }
  }
  if (cobertura.medible) return { mostrar: true, aviso: null }

  switch (cobertura.motivo_no_medible) {
    case 'mes_parcial':
      return {
        mostrar: true,
        aviso: cobertura.suelo_historico != null
          ? `Provisional: el registro empieza el ${fmtFecha(cobertura.suelo_historico)}`
          : 'Provisional: al mes le faltan días de registro',
      }
    case 'sin_ledger':
      return { mostrar: false, aviso: 'Todavía no hay registro de asignaciones' }
    case 'anterior_al_ledger':
      return { mostrar: false, aviso: 'Mes anterior al registro de asignaciones' }
    // Los motivos de roster (sin supervisor, supervisor inactivo…) no hablan de
    // la ventana sino de quién la mira, y hoy no tienen texto propio. Se quedan
    // como estaban —ocultos— en vez de estrenar una frase inventada aquí.
    default:
      return { mostrar: false, aviso: 'Sin datos de asignación para este mes' }
  }
}

/** Total canónico visible bajo la misma política que filas, ranking y metas.
 * Centralizarlo evita que un consumidor lea `total` crudo mientras las demás
 * superficies ya ocultaron una sonda de integridad rota. */
export function totalConversionPublicable(
  conversion: ConversionMensual | null | undefined,
): ConversionMensual['total'] | null {
  if (conversion == null || !lecturaCobertura(conversion.cobertura).mostrar) return null
  return conversion.total
}

export interface DescuentoArrastre {
  /** Para el chip: «arrastra 1,15 conversiones de anulaciones · julio 2026». */
  etiqueta: string
  /** Para el `title`: cada origen con su mes, su motivo y su cuánto. */
  detalle: string
}

function nombreMes(periodo: string): string {
  const [anio, mes] = periodo.split('-').map(Number)
  if (!anio || !mes || mes < 1 || mes > 12) return periodo
  // En minúscula como el resto de la casa («julio»). CON el año: deudas de
  // julio 2025 y julio 2026 colapsaban en un solo «julio» (hallazgo #8).
  const nombre = new Intl.DateTimeFormat('es-PE', { month: 'long', timeZone: 'UTC' })
    .format(new Date(Date.UTC(anio, mes - 1, 1)))
    .toLocaleLowerCase('es-PE')
  return `${nombre} ${anio}`
}

/** Decimales suficientes para que una deuda real no se pinte como «0»: el
 * servidor admite pesos de 3 decimales y 0.001 con 2 decimales era «−0». */
function numeroDeuda(n: number): string {
  return numero(n, n < 0.01 ? 3 : 2)
}

/**
 * El descuento por anulaciones de meses ya cerrados, listo para pintarse al
 * lado del número que rebaja. `null` = nada que decir: el chip no existe, no
 * es que diga «0». Dos situaciones, dos frases (comprobadas ejecutando):
 *
 * · Mes VIVO (`pendiente > 0`): se afirma la DEUDA («arrastra N…»), no un
 *   «−N». El descuento efectivo del mes es min(deuda, bruto) y el bruto no
 *   viaja: con numerador bruto 1 y deuda 3, el servidor resta 1 y arrastra 2 —
 *   un chip «−3» mentiría sobre el número contiguo (hallazgo #4).
 * · FOTO SELLADA (`aplicado > 0`, pendiente 0): esto SÍ se restó al sellar —
 *   aquí el «−N» es exacto. El servidor vacía `origenes` en la foto: no se
 *   inventan meses.
 */
export function descuentoArrastre(ajuste: AjusteConversion | undefined): DescuentoArrastre | null {
  if (!ajuste) return null
  if (ajuste.pendiente > 0) {
    const origenes = ajuste.origenes ?? []
    // Dedupe por PERIODO (no por nombre): dos anulaciones del mismo mes se
    // nombran una vez; julio 2025 y julio 2026 se nombran las dos.
    const meses = [...new Map(origenes.map((origen) => [origen.periodo, nombreMes(origen.periodo)])).values()]
    const de = meses.length > 0 ? ` · ${meses.join(' y ')}` : ''
    // La unidad concuerda con el TEXTO mostrado, no con el número crudo:
    // 1.004 se pinta «1» y decía «1 conversiones» (observación #8).
    const texto = numeroDeuda(ajuste.pendiente)
    const unidad = texto === '1' ? 'conversión' : 'conversiones'
    return {
      etiqueta: `arrastra ${texto} ${unidad} de anulaciones${de}`,
      detalle: origenes.length > 0
        ? origenes
          .map((origen) => `${nombreMes(origen.periodo)}: ${origen.motivo} (−${numeroDeuda(origen.numerador)})`)
          .join('\n')
        : 'Anulaciones de meses ya cerrados pendientes de saldar.',
    }
  }
  const aplicado = ajuste.aplicado ?? 0
  if (aplicado > 0) {
    const texto = numeroDeuda(aplicado)
    const unidad = texto === '1' ? 'conversión descontada' : 'conversiones descontadas'
    return {
      etiqueta: `−${texto} ${unidad} al cierre`,
      detalle: 'Anulaciones de meses cerrados, descontadas al sellar este mes.',
    }
  }
  return null
}
