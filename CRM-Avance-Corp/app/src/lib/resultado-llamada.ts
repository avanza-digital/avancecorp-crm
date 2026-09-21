// lib/resultado-llamada.ts — el catálogo del RESULTADO TIPIFICADO de una llamada
// (Gestión Diaria, Fase 2). Espejo del contrato v4 (20260921153654):
// conserva las 7 claves y submotivos de 20260920005000 y el mismo
// mapeo a tipo de actividad y a motivo de descarte. `resultado-llamada.test.ts`
// fija las claves para que el front no invente una que el CHECK del servidor
// rechazaría. Desde v4 el descarte se decide aparte; v3 queda para recibos legacy.
//
// Vocabulario visible: se dice «cita», nunca «reunión» (decisión del 27/08);
// las claves técnicas (`agendo_reunion`, tipo de tarea `reunion`) no cambian.
import type { MotivoDescarte, TipoActividadManual, TipoTarea } from './tipos'

export const RESULTADOS_LLAMADA = [
  'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
  'numero_errado', 'no_es_la_persona', 'pide_otro_producto',
] as const
export type ResultadoLlamada = (typeof RESULTADOS_LLAMADA)[number]

export const SUBMOTIVOS_NO_INTERESADO = [
  'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir', 'otro',
] as const
export const SUBMOTIVOS_PIDE_OTRO_PRODUCTO = ['prestamo', 'credito', 'otro'] as const
export type SubmotivoLlamada =
  | (typeof SUBMOTIVOS_NO_INTERESADO)[number]
  | (typeof SUBMOTIVOS_PIDE_OTRO_PRODUCTO)[number]

/** Qué pide el paso 2 del panel para cada resultado. */
export type PasoDelResultado = 'siguiente_llamada' | 'cita' | 'submotivo' | 'decision_numero' | 'sugerencia'

export interface DefinicionResultado {
  clave: ResultadoLlamada
  /** Etiqueta del mockup 5 («Contestó · agendó cita»). */
  etiqueta: string
  /** Segunda línea: qué pasa al elegirlo. */
  detalle: string
  /** Atajo de teclado 1–7. */
  atajo: string
  /** Tipo de actividad con el que queda en el historial. */
  tipo: TipoActividadManual
  paso: PasoDelResultado
  /** ¿Cuenta como llamada ÚTIL para la tasa de contacto? */
  util: boolean
  /** Ofrece descarte separado del resultado; nunca lo ejecuta por elegirlo. */
  descarteOpcional: boolean
}

export const RESULTADOS: readonly DefinicionResultado[] = [
  { clave: 'no_contesto', etiqueta: 'No contestó', detalle: 'Se propone el siguiente intento', atajo: '1', tipo: 'llamada_no_contestada', paso: 'sugerencia', util: true, descarteOpcional: false },
  { clave: 'volver_a_llamar', etiqueta: 'Contestó · volver a llamar', detalle: 'Se agenda la llamada con fecha y hora', atajo: '2', tipo: 'llamada_realizada', paso: 'siguiente_llamada', util: true, descarteOpcional: false },
  { clave: 'agendo_reunion', etiqueta: 'Contestó · agendó cita', detalle: 'Se agenda la cita con fecha, hora y modalidad', atajo: '3', tipo: 'llamada_realizada', paso: 'cita', util: true, descarteOpcional: false },
  { clave: 'no_interesado', etiqueta: 'Contestó · no le interesa', detalle: 'Registra el motivo y elige la próxima acción', atajo: '4', tipo: 'llamada_realizada', paso: 'submotivo', util: true, descarteOpcional: true },
  { clave: 'numero_errado', etiqueta: 'Número errado', detalle: 'Tú decides: segundo número, descartar o reintentar', atajo: '5', tipo: 'llamada_no_contestada', paso: 'decision_numero', util: false, descarteOpcional: false },
  { clave: 'no_es_la_persona', etiqueta: 'No es la persona', detalle: 'Tú decides: segundo número, descartar o reintentar', atajo: '6', tipo: 'llamada_no_contestada', paso: 'decision_numero', util: false, descarteOpcional: false },
  { clave: 'pide_otro_producto', etiqueta: 'Pide otro producto', detalle: 'Registra qué necesita y elige la próxima acción', atajo: '7', tipo: 'llamada_realizada', paso: 'submotivo', util: true, descarteOpcional: true },
]

/** Espejo del contrato v4; conserva las restricciones de los otros resultados. */
export function tiposSiguientesDeResultado(resultado: ResultadoLlamada): readonly TipoTarea[] {
  if (resultado === 'no_interesado' || resultado === 'pide_otro_producto') return ['llamada', 'whatsapp', 'reunion', 'tarea']
  if (resultado === 'no_contesto') return ['llamada', 'whatsapp']
  return resultado === 'agendo_reunion' ? ['reunion'] : ['llamada']
}

const POR_CLAVE: ReadonlyMap<ResultadoLlamada, DefinicionResultado> = new Map(RESULTADOS.map((r) => [r.clave, r]))

export function definicionResultado(clave: ResultadoLlamada): DefinicionResultado {
  const def = POR_CLAVE.get(clave)
  if (!def) throw new Error(`Resultado de llamada desconocido: ${clave}`)
  return def
}

export const esResultadoLlamada = (v: string): v is ResultadoLlamada =>
  (RESULTADOS_LLAMADA as readonly string[]).includes(v)

/** Tipo de actividad que el servidor escribe para este resultado (espejo del núcleo). */
export function tipoDeResultado(clave: ResultadoLlamada): TipoActividadManual {
  return definicionResultado(clave).tipo
}

/** Etiqueta corta para chips e historial («No contestó», «Agendó cita»…). */
export function etiquetaResultado(clave: string): string {
  if (!esResultadoLlamada(clave)) return clave
  return definicionResultado(clave).etiqueta.replace(/^Contestó · /, (m) => m).replace('Contestó · ', '')
    .replace(/^./, (c) => c.toUpperCase())
}

/** Llamada ÚTIL = entra en la tasa de contacto (número errado y «no es la persona» no). */
export function esLlamadaUtil(clave: string | null | undefined): boolean {
  if (!clave || !esResultadoLlamada(clave)) return true
  return definicionResultado(clave).util
}

export interface DefinicionSubmotivo {
  clave: SubmotivoLlamada
  etiqueta: string
  /** Motivo REAL del catálogo de descarte al que mapea (lo decide el servidor; aquí solo se anuncia). */
  motivo: MotivoDescarte
}

export const SUBMOTIVOS: Readonly<Record<'no_interesado' | 'pide_otro_producto', readonly DefinicionSubmotivo[]>> = {
  no_interesado: [
    { clave: 'sin_fondos_ahora', etiqueta: 'Sin fondos ahora', motivo: 'sin_fondos' },
    { clave: 'ya_invirtio_con_otro', etiqueta: 'Ya invirtió con otro', motivo: 'competencia' },
    { clave: 'desconfianza', etiqueta: 'Desconfianza', motivo: 'sin_interes' },
    { clave: 'no_le_interesa_invertir', etiqueta: 'No le interesa invertir', motivo: 'sin_interes' },
    { clave: 'otro', etiqueta: 'Otro', motivo: 'sin_interes' },
  ],
  pide_otro_producto: [
    { clave: 'prestamo', etiqueta: 'Préstamo', motivo: 'pide_credito' },
    { clave: 'credito', etiqueta: 'Crédito', motivo: 'pide_credito' },
    { clave: 'otro', etiqueta: 'Otro producto', motivo: 'pide_credito' },
  ],
}

/** Motivo de descarte que el servidor asignará a un resultado + submotivo (para el espejo optimista). */
export function motivoDeDescarte(clave: ResultadoLlamada, submotivo: SubmotivoLlamada | null): MotivoDescarte | null {
  if (clave === 'no_interesado' || clave === 'pide_otro_producto') {
    return SUBMOTIVOS[clave].find((s) => s.clave === submotivo)?.motivo ?? null
  }
  if (clave === 'numero_errado' || clave === 'no_es_la_persona') return 'datos_invalidos'
  if (clave === 'no_contesto') return 'no_responde'
  return null
}

/** Ventana legal de contacto (Ley 29571): L–S 07:00–20:00 Lima. Espejo del núcleo. */
export function dentroDeVentanaLegal(iso: string): boolean {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return false
  const partes = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Lima', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(new Date(ms))
  const dia = partes.find((p) => p.type === 'weekday')?.value
  const hora = Number(partes.find((p) => p.type === 'hour')?.value)
  const minuto = Number(partes.find((p) => p.type === 'minute')?.value)
  if (dia === 'Sun') return false
  const minutos = (hora % 24) * 60 + minuto
  return minutos >= 7 * 60 && minutos < 20 * 60
}

/** Mínimo de intentos sin respuesta para ofrecer «marcar perdido: no responde» (mockup 5). */
export const INTENTOS_PARA_OFRECER_PERDIDO = 6
