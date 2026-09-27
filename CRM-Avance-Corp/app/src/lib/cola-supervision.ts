// lib/cola-supervision.ts — cómo lee el SUPERVISOR una fila del seguimiento
// activo (crm.cola_accion_v2_fn) en su pantalla Hoy (27/09/2026).
//
// ACCIONES_SLA habla al analista en imperativo («Contactar al cliente»); el
// supervisor no gestiona el lead, lo revisa con su analista (textoAvisoSla con
// supervision = true). Por eso aquí el bucket se nombra como un ESTADO del
// caso, y el tiempo dice qué significa la fecha de referencia de ese bucket:
// en unos es un plazo (vence / venció), en otros el inicio (desde).
import { DIA_MS, duracionTexto, haceTexto } from './inteligencia'
import { primerNombre } from './format'

/** Estado del caso visto desde supervisión, por bucket del seguimiento. */
export const ESTADO_CASO_SUPERVISION: Record<string, string> = {
  primera_atencion: 'Primera gestión pendiente',
  tarea_vencida: 'Actividad vencida',
  tarea_hoy: 'Actividad para hoy',
  seguimiento: 'Seguimiento pendiente',
  revision_comercial: 'Revisión comercial',
  datos_incompletos: 'Datos incompletos',
  proxima_tarea: 'Próxima actividad',
  por_repartir: 'Sin analista asignado',
}

export function estadoCasoSupervision(bucket: string): string {
  return ESTADO_CASO_SUPERVISION[bucket] ?? 'Revisar oportunidad'
}

// En estos buckets `referencia_en` es un PLAZO (private.sla_operacion_leads):
// el límite de la primera gestión, el vencimiento de la actividad o el límite
// del seguimiento. En los demás es el inicio del caso (creado_en, etapa).
const BUCKETS_CON_PLAZO = new Set(['primera_atencion', 'tarea_vencida', 'tarea_hoy', 'seguimiento', 'proxima_tarea'])

/**
 * «venció hace 2 días» / «vence en 3 horas» / «desde hace 5 días».
 * Sin fecha confirmada lo dice: no se inventa un tiempo (referencia_en es nullable).
 */
export function momentoCaso(bucket: string, referenciaEn: string | null, ahora: number): string {
  const ms = referenciaEn == null ? Number.NaN : Date.parse(referenciaEn)
  if (!Number.isFinite(ms)) return 'sin fecha confirmada'
  const dias = (ahora - ms) / DIA_MS
  if (!BUCKETS_CON_PLAZO.has(bucket)) return `desde ${haceTexto(Math.max(0, dias))}`
  return dias >= 0 ? `venció ${haceTexto(dias)}` : `vence en ${duracionTexto(-dias)}`
}

const capital = (palabra: string) => palabra.charAt(0).toUpperCase() + palabra.slice(1).toLowerCase()

/**
 * Nombre corto de cada persona para chips y columnas estrechas: el primer
 * nombre; si dos lo comparten, se añade lo MÍNIMO que los distingue, por
 * niveles: inicial del último apellido («Karen Z.»), el apellido entero
 * («Karen Zapata») y, si aún chocan, el nombre completo. Dos chips iguales no
 * se pueden elegir. Nombres completos idénticos quedan iguales: ahí la
 * identidad la da el id, no la etiqueta.
 */
export function nombresCortos(nombres: readonly string[]): Map<string, string> {
  const unicos = [...new Set(nombres.map((n) => n.trim()).filter(Boolean))]
  const niveles: Array<(n: string) => string> = [
    (n) => primerNombre(n),
    (n) => {
      const partes = n.split(/\s+/)
      return partes.length > 1 ? `${primerNombre(n)} ${(partes[partes.length - 1] ?? '').charAt(0).toUpperCase()}.` : primerNombre(n)
    },
    (n) => {
      const partes = n.split(/\s+/)
      return partes.length > 1 ? `${primerNombre(n)} ${capital(partes[partes.length - 1] ?? '')}` : primerNombre(n)
    },
    (n) => n.split(/\s+/).map(capital).join(' '),
  ]
  const resultado = new Map<string, string>()
  let pendientes = unicos
  for (const [i, nivel] of niveles.entries()) {
    const etiquetas = new Map(pendientes.map((n) => [n, nivel(n)] as const))
    const cuenta = new Map<string, number>()
    for (const e of etiquetas.values()) cuenta.set(e, (cuenta.get(e) ?? 0) + 1)
    const esUltimo = i === niveles.length - 1
    // Cada nombre se queda en el primer nivel en que su etiqueta ya no choca.
    pendientes = pendientes.filter((n) => {
      const e = etiquetas.get(n) ?? n
      if ((cuenta.get(e) ?? 0) < 2 || esUltimo) {
        resultado.set(n, e)
        return false
      }
      return true
    })
    if (pendientes.length === 0) break
  }
  return resultado
}
