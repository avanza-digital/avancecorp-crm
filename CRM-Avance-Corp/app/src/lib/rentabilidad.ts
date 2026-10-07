// Rentabilidad (R2): helpers puros de la tarjeta de observación.

/** Texto humano para los motivos técnicos que anota el observador. */
export function motivoSinRegla(motivo: string): string {
  if (motivo === 'upgrade_origen_ambiguo') return 'Upgrade sin contrato origen claro'
  if (motivo === 'upgrade_sin_contrato_activo_previo') return 'Upgrade sin contrato activo previo'
  if (motivo.startsWith('resolver:P0409')) return 'Cliente inactivo o contrato origen cerrado'
  if (motivo.startsWith('resolver:22023')) return 'Contrato sin categoría o sin origen'
  if (motivo.startsWith('resolver:')) return 'El núcleo no pudo decidir'
  return motivo
}

export type EstadoSolicitudTasaLib =
  | 'pendiente' | 'aprobada' | 'aprobada_con_tope' | 'rechazada'
  | 'aceptada_por_analista' | 'declinada_por_analista' | 'consumida' | 'vencida'
/** Estados en los que una solicitud sigue viva (puede decidirse, aceptarse o consumirse). */
export const ESTADOS_SOLICITUD_TASA_VIVOS: EstadoSolicitudTasaLib[] = ['pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista']
/** Lo que el analista sigue: las vivas y las rechazadas (tiene que enterarse de un «no», no ver que la solicitud desapareció). */
export const ESTADOS_SOLICITUD_TASA_SEGUIMIENTO: EstadoSolicitudTasaLib[] = [...ESTADOS_SOLICITUD_TASA_VIVOS, 'rechazada']
/** Cuántos días se sigue mostrando un rechazo al analista. */
export const DIAS_RECHAZO_VISIBLE = 7

export interface RangoTasaConSolicitud {
  modo: string
  base: number | null
  minimo: number | null
  maximo: number | null
  solicitud: { vence_en: string; vigente: boolean } | null
}
/**
 * El rango que vale AHORA. El bloque de tasa refresca su reloj cada minuto: entre dos ticks una autorización puede
 * caducar y el formulario seguir creyéndola vigente. Al guardar se pregunta con `Date.now()`; caducada → vuelve a la base.
 */
export function rangoEfectivo(r: RangoTasaConSolicitud, ahora: number = Date.now()): { minimo: number | null; maximo: number | null; caducada: boolean } {
  if (r.modo === 'autorizada' && r.solicitud && (!r.solicitud.vigente || new Date(r.solicitud.vence_en).getTime() <= ahora)) {
    return { minimo: r.minimo, maximo: r.base, caducada: true }
  }
  return { minimo: r.minimo, maximo: r.maximo, caducada: false }
}

export type ReglaTasaLib = 'primera_inversion' | 'heredada_renovacion' | 'heredada_upgrade' | 'historica_legacy' | 'sin_regla'
/** Texto humano de la regla del núcleo. */
export function etiquetaReglaTasa(regla: ReglaTasaLib): string {
  switch (regla) {
    case 'primera_inversion': return 'Primera inversión: tasa base de la política'
    case 'heredada_renovacion': return 'Renovación: hereda la tasa del contrato que renueva'
    case 'heredada_upgrade': return 'Upgrade: tasa de referencia del contrato que amplía'
    case 'historica_legacy': return 'Contrato anterior a la política'
    default: return 'La política no define este caso'
  }
}

export function tasaTxt(n: number): string {
  return `${n.toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}%`
}

export type ModoPoliticaLib = 'observacion' | 'enforcement'
/**
 * Cómo se llama cada modo en la interfaz (una sola redacción para todas las pantallas). Estas dos funciones son el
 * NOMBRE accesible y la descripción del interruptor del candado, así que un modo desconocido se declara como tal en
 * vez de hacerse pasar por «Observación»: si el servidor añade un modo, la pantalla no puede prometer que no bloquea.
 */
export function etiquetaModoPolitica(modo: string): string {
  if (modo === 'enforcement') return 'Candado activo'
  if (modo === 'observacion') return 'Observación'
  return `Modo desconocido (${modo})`
}
/** Qué significa el modo para quien lo lee. */
export function detalleModoPolitica(modo: string): string {
  if (modo === 'enforcement') return 'El servidor verifica el rango de tasa permitido y exige una autorización vigente de Gerencia para superar la tasa base.'
  if (modo === 'observacion') return 'Se registra la tasa sin exigir aprobación de Gerencia. Las solicitudes pendientes no bloquean. Se mantienen el tope configurado y las validaciones de datos.'
  return 'Esta versión del CRM no conoce este modo: consulta con Gerencia antes de dar por hecho qué bloquea.'
}
