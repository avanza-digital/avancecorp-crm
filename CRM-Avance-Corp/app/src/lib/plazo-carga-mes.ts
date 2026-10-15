import * as v from 'valibot'
import { COOPERATIVAS, INFO_COOPERATIVA, type Cooperativa } from './cierres-externos'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  FechaSchema,
  NumeroRpcSchema,
  TextoNoVacioSchema,
  UuidSchema,
} from './esquemas-rpc'
import { fmtDiaMes, fmtDiaMesLima, money } from './format'

/**
 * El PLAZO DE CARGA de cada mes, decidido por Gerencia (`crm.plazos_carga_mes_fn`
 * para leer, `crm.fijar_plazo_carga_mes` para ampliar o reabrir). Diseño en
 * `docs/plans/plazo-carga-mes/DISENO.md`.
 *
 * El plazo es el último día INCLUIDO en que una venta de ese mes todavía cuenta
 * como del mes: por defecto el día 10 del mes siguiente; Gerencia puede
 * ampliarlo y, si el mes ya se selló, reabrirlo. Qué se puede hacer con cada
 * mes (ampliar, reabrir o nada, y por qué no) lo decide el SERVIDOR: aquí solo
 * se pinta. La única cuenta del front es comparar dos fechas servidas (el plazo
 * con `hoy`) para no decir «se puede cargar hasta el 10 oct.» el 14 de octubre.
 *
 * Contratos fail-closed (`strictObject`), igual que `cierre-de-mes.ts`: una
 * clave de más o un tipo distinto es otra respuesta, no esta. Las claves son
 * las que la prueba del servidor exige al EJECUTAR las dos funciones
 * (`supabase/scripts/plazo-carga-mes/prueba.sql`, «claves exactas»), no las del
 * ejemplo del diseño: la raíz trae además `generado_en`. `mes_nombre` sale de
 * `private.etiqueta_mes_es` + el año: «setiembre 2026».
 */

const MesSchema = v.pipe(v.string(), v.regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Mes YYYY-MM inválido'))

const DecisionPlazoSchema = v.strictObject({
  ultimo_dia: FechaSchema,
  motivo: TextoNoVacioSchema,
  decidido_por: TextoNoVacioSchema,
  decidido_en: FechaHoraSchema,
})

const ReaperturaSchema = v.strictObject({
  reabierto_en: FechaHoraSchema,
  decidido_por: TextoNoVacioSchema,
})

const MesPlazoCargaSchema = v.strictObject({
  mes: MesSchema,
  mes_nombre: TextoNoVacioSchema,
  sellado: v.boolean(),
  plazo_base_ultimo_dia: FechaSchema,
  plazo_ultimo_dia: FechaSchema,
  ampliado: v.boolean(),
  decision: v.nullable(DecisionPlazoSchema),
  reabrible: v.boolean(),
  motivo_no_reabrible: v.nullable(TextoNoVacioSchema),
  ultima_reapertura: v.nullable(ReaperturaSchema),
})

export const PlazosCargaMesSchema = v.pipe(
  v.strictObject({
    version: v.literal(1),
    generado_en: FechaHoraSchema,
    hoy: FechaSchema,
    zona: v.literal('America/Lima'),
    meses: v.array(MesPlazoCargaSchema),
  }),
  // Un mes repetido no es «dos filas»: es otra respuesta, y pintar dos botones
  // que deciden sobre el mismo mes invitaría a decidir dos veces.
  v.check(
    (datos) => new Set(datos.meses.map((mes) => mes.mes)).size === datos.meses.length,
    'Mes repetido en el plazo de carga',
  ),
)

export type PlazosCargaMes = v.InferOutput<typeof PlazosCargaMesSchema>
export type MesPlazoCarga = PlazosCargaMes['meses'][number]

const VentaDevueltaSchema = v.strictObject({
  cooperativa: TextoNoVacioSchema,
  monto: NumeroRpcSchema,
  moneda: v.picklist(['PEN', 'USD']),
  fecha_comercial: FechaSchema,
  imputada_antes_a: FechaSchema,
})

/** Acuse de `crm.fijar_plazo_carga_mes`. */
export const PlazoCargaFijadoSchema = v.pipe(
  v.strictObject({
    ok: v.literal(true),
    mes: MesSchema,
    ultimo_dia: FechaSchema,
    plazo_hasta: FechaHoraSchema,
    reabierto: v.boolean(),
    reapertura_id: v.nullable(UuidSchema),
    acreditaciones_reevaluadas: EnteroNoNegativoRpcSchema,
    conflictos_identidad: EnteroNoNegativoRpcSchema,
    ventas_devueltas: v.array(VentaDevueltaSchema),
  }),
  // Reabrir deja SIEMPRE su fila de reapertura, y ampliar nunca: un acuse que
  // dice lo uno con la pieza de lo otro no se puede contar a Gerencia.
  v.check((acuse) => acuse.reabierto === (acuse.reapertura_id !== null), 'Reapertura incoherente'),
)

export type PlazoCargaFijado = v.InferOutput<typeof PlazoCargaFijadoSchema>
export type VentaDevuelta = PlazoCargaFijado['ventas_devueltas'][number]

// ── Reglas del formulario (espejo de la puerta; la que cuenta es la del servidor) ──

/** Espejo del CHECK de `crm.plazos_carga_mes.motivo`: entre 5 y 300 caracteres. */
export const MOTIVO_PLAZO_MIN = 5
export const MOTIVO_PLAZO_MAX = 300

/** Caracteres como los cuenta Postgres (`length`): un emoji es uno, no dos unidades UTF-16. */
export function largoMotivoPlazo(motivo: string): number {
  return Array.from(motivo.trim()).length
}

export function motivoPlazoValido(motivo: string): boolean {
  const largo = largoMotivoPlazo(motivo)
  return largo >= MOTIVO_PLAZO_MIN && largo <= MOTIVO_PLAZO_MAX
}

/** Primer día del mes que pide la puerta (`p_periodo`): '2026-09' → '2026-09-01'. */
export function periodoDelMes(mes: string): string {
  return `${mes}-01`
}

/**
 * El primer día que se puede elegir: hoy o el plazo normal, el que sea más
 * tarde. Ninguno de los dos lo calcula el front: los dos vienen del servidor
 * (el plazo nunca queda antes del día 10, decisión de Miguel del 15/08).
 */
export function fechaMinimaPlazo(mes: MesPlazoCarga, hoy: string): string {
  return mes.plazo_base_ultimo_dia > hoy ? mes.plazo_base_ultimo_dia : hoy
}

/** Cierra la frase con punto, sin duplicarlo tras una abreviatura («20 oct.»). */
export function conPunto(frase: string): string {
  return frase.endsWith('.') ? frase : `${frase}.`
}

/** Qué le falta a la fecha elegida, o `null` si la puerta la aceptaría. */
export function errorUltimoDia(valor: string, minimo: string): string | null {
  if (valor === '') return 'Elige el último día para cargar.'
  if (!v.safeParse(FechaSchema, valor).success) return 'La fecha no es válida.'
  if (valor < minimo) return conPunto(`Elige un día desde el ${fmtDiaMes(minimo)}`)
  return null
}

// ── Lo que se pinta de cada mes ──

/** «septiembre 2026» → «Septiembre 2026». Solo la primera letra: el nombre lo pone el servidor. */
export function conMayuscula(texto: string): string {
  return texto.charAt(0).toLocaleUpperCase('es-PE') + texto.slice(1)
}

/** «septiembre 2026» → «septiembre»: para el botón «Reabrir septiembre». */
export function mesSinAnio(mesNombre: string): string {
  return mesNombre.replace(/\s+\d{4}$/, '')
}

export type EstadoPlazo = 'vigente' | 'ultimo_dia' | 'vencido' | 'cerrado'

export function estadoDelPlazo(mes: MesPlazoCarga, hoy: string): EstadoPlazo {
  if (mes.sellado) return 'cerrado'
  if (mes.plazo_ultimo_dia > hoy) return 'vigente'
  return mes.plazo_ultimo_dia === hoy ? 'ultimo_dia' : 'vencido'
}

/** Lo que va detrás del nombre del mes: «se puede cargar hasta el 20 oct.». */
export function lineaDelPlazo(mes: MesPlazoCarga, hoy: string): string {
  const fecha = fmtDiaMes(mes.plazo_ultimo_dia)
  switch (estadoDelPlazo(mes, hoy)) {
    case 'vigente':
      return `se puede cargar hasta el ${fecha}`
    case 'ultimo_dia':
      return `se puede cargar hasta hoy, ${fecha}`
    case 'vencido':
      return `el plazo de carga venció el ${fecha}`
    case 'cerrado':
      return `cerrado · se pudo cargar hasta el ${fecha}`
  }
}

/**
 * Un mes abierto con el plazo vencido sigue recibiendo ventas (el ciclo aún no
 * lo selló), pero su conversión ya no se acredita: sin esta línea, Gerencia ve
 * «abierto» y cree que todo cuenta. Es el estado de septiembre el 14/10.
 */
export const AVISO_PLAZO_VENCIDO = 'Sigue abierto: lo que se cargue ahora suma capital, pero su conversión queda fuera de plazo.'

/** Quién decidió y cuándo: «Ampliado por MIGUEL el 14 oct.», con la reapertura delante si la hubo. */
export function lineaDecision(mes: MesPlazoCarga): string | null {
  const partes: string[] = []
  if (mes.ultima_reapertura) {
    partes.push(`reabierto por ${mes.ultima_reapertura.decidido_por} el ${fmtDiaMesLima(mes.ultima_reapertura.reabierto_en)}`)
  }
  if (mes.decision) {
    partes.push(`${mes.ampliado ? 'ampliado' : 'fijado'} por ${mes.decision.decidido_por} el ${fmtDiaMesLima(mes.decision.decidido_en)}`)
  }
  return partes.length === 0 ? null : conMayuscula(partes.join(' · '))
}

export interface AccionPlazo {
  tipo: 'ampliar' | 'reabrir'
  etiqueta: string
}

/** El botón de la fila. Sellado y no reabrible: ninguno (la fila dice por qué). */
export function accionDelMes(mes: MesPlazoCarga): AccionPlazo | null {
  if (!mes.sellado) return { tipo: 'ampliar', etiqueta: 'Ampliar plazo' }
  if (mes.reabrible) return { tipo: 'reabrir', etiqueta: `Reabrir ${mesSinAnio(mes.mes_nombre)}` }
  return null
}

// ── El resultado de guardar ──

function nombreCooperativa(codigo: string): string {
  return (COOPERATIVAS as readonly string[]).includes(codigo)
    ? INFO_COOPERATIVA[codigo as Cooperativa].nombre
    : codigo.toLocaleUpperCase('es-PE')
}

function lineaVentaDevuelta(venta: VentaDevuelta, mesNombre: string): string {
  return `Venta devuelta a ${mesSinAnio(mesNombre)}: ${nombreCooperativa(venta.cooperativa)} · ${money(venta.monto, venta.moneda)}`
    + ` · del ${fmtDiaMes(venta.fecha_comercial)} (estaba contada el ${fmtDiaMes(venta.imputada_antes_a)}).`
}

export interface ResumenPlazoFijado {
  titulo: string
  lineas: string[]
}

/** El aviso que queda en la tarjeta tras guardar: qué plazo quedó y qué movió. */
export function resumenPlazoFijado(acuse: PlazoCargaFijado, mesNombre: string): ResumenPlazoFijado {
  const nombre = conMayuscula(mesNombre)
  const fecha = fmtDiaMes(acuse.ultimo_dia)
  const revisadas = acuse.acreditaciones_reevaluadas
  const conflictos = acuse.conflictos_identidad
  const lineas = [
    revisadas === 0
      ? 'No había conversiones de este mes que volver a revisar.'
      : revisadas === 1
        ? 'Se volvió a revisar 1 conversión con el plazo nuevo.'
        : `Se volvieron a revisar ${revisadas} conversiones con el plazo nuevo.`,
  ]
  if (conflictos > 0) {
    lineas.push(conflictos === 1
      ? '1 conversión se quedó como estaba: esa persona ya tenía otra conversión acreditada.'
      : `${conflictos} conversiones se quedaron como estaban: esas personas ya tenían otra conversión acreditada.`)
  }
  for (const venta of acuse.ventas_devueltas) lineas.push(lineaVentaDevuelta(venta, mesNombre))
  return {
    titulo: conPunto(acuse.reabierto
      ? `${nombre} reabierto: se puede cargar hasta el ${fecha}`
      : `${nombre}: se puede cargar hasta el ${fecha}`),
    lineas,
  }
}

/** El código estable de un error de la capa de datos (`CrmApiError.code`), sin importar la clase. */
export function codigoDeError(error: unknown): string | null {
  if (typeof error !== 'object' || error === null || !('code' in error)) return null
  return typeof error.code === 'string' ? error.code : null
}

/** La puerta todavía no existe en este servidor (front publicado antes que la migración). */
export const CODIGO_PLAZO_NO_DISPONIBLE = 'NO_DISPONIBLE'
