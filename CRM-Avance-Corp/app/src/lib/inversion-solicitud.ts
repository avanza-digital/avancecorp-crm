import * as v from 'valibot'
import type { CrearContratoInput } from '@/data/crm-api'
import type { Json } from '@/lib/database.types'

const Uuid = v.pipe(v.string(), v.uuid())
const Revision = v.pipe(v.number(), v.integer(), v.minValue(0))
export const DatosInversionSchema = v.object({
  inversionista_id: Uuid,
  empresa: v.picklist(['avance', 'qorilazo', 'prodelco']),
  monto: v.optional(v.number()), moneda: v.optional(v.picklist(['PEN', 'USD'])),
  fecha_comercial: v.optional(v.string()), vence_en: v.optional(v.string()),
  numero_transaccion: v.optional(v.string()), referencia: v.optional(v.string()),
  evidencia: v.optional(v.object({ruta: v.string()})),
  contrato: v.optional(v.record(v.string(), v.unknown())),
  cronograma: v.optional(v.array(v.unknown())),
  cuenta: v.optional(v.record(v.string(), v.unknown())),
  alta_portal: v.optional(v.object({correo: v.string(), nombre_completo: v.string(),
    nombres: v.string(), apellidos: v.string(), telefono: v.string(), domicilio: v.string()})),
})
export type DatosInversion = v.InferOutput<typeof DatosInversionSchema>
// El resultado económico se valida por sus identificadores. Los detalles del PDF
// no convierten una inversión confirmada en un supuesto fallo de creación.
export const ConfirmacionInversionSchema = v.object({
  ok: v.literal(true), solicitud_id: Uuid, inversion_id: Uuid, inversionista_id: Uuid,
  empresa: v.picklist(['avance', 'qorilazo', 'prodelco']),
  fuente: v.looseObject({id: v.optional(Uuid), cierre_id: v.optional(Uuid), numero_contrato: v.optional(v.string())}),
})
export const SolicitudInversionSchema = v.object({
  solicitud_id: Uuid, estado: v.picklist(['preparada', 'confirmada', 'cancelada']),
  inversion_id: v.nullable(Uuid), inversionista_id: Uuid, inversionista_origen_id: Uuid,
  identidad_fusionada: v.boolean(), responsable_esperado_id: v.nullable(Uuid),
  responsable_actual_id: v.nullable(Uuid), requiere_revision_responsable: v.boolean(),
  revision_datos: Revision, revision_responsable: Revision, hash_datos: v.string(),
  necesita_portal: v.boolean(), comprobante_bucket: v.nullable(v.string()), comprobante_ruta: v.nullable(v.string()),
  resultado: v.nullable(ConfirmacionInversionSchema), datos: v.optional(DatosInversionSchema),
})
export type SolicitudInversion = v.InferOutput<typeof SolicitudInversionSchema>
export type ConfirmacionInversion = v.InferOutput<typeof ConfirmacionInversionSchema>

const IntentoSchema = v.object({
  version: v.literal(1), actor: Uuid, persona: Uuid, clave: Uuid, datos: DatosInversionSchema,
  token: v.pipe(v.string(), v.regex(/^[a-f0-9]{48}$/)),
  correccion: v.optional(v.object({clave: Uuid, revision: Revision, datos: DatosInversionSchema, motivo: v.string()})),
})
export type IntentoInversion = v.InferOutput<typeof IntentoSchema>
const PREFIJO = 'crm:f5:solicitud:'
const clave = (actor: string, persona: string) => `${PREFIJO}${actor}:${persona}`

/** Solo en esta sesión del navegador: sobrevive a recarga/cierre de diálogo.
 * El contenido nunca viaja a logs, y se elimina al salir o perder acceso. */
export function guardarIntentoInversion(intento: IntentoInversion): void {
  const validado = v.parse(IntentoSchema, intento)
  sessionStorage.setItem(clave(validado.actor, validado.persona), JSON.stringify(validado))
}
export function leerIntentoInversion(actor: string, persona: string): IntentoInversion | null {
  const raw = sessionStorage.getItem(clave(actor, persona))
  if (!raw) return null
  try {
    const r = v.safeParse(IntentoSchema, JSON.parse(raw))
    if (r.success && r.output.actor === actor && r.output.persona === persona) return r.output
  } catch { /* nunca mostrar el contenido corrupto */ }
  throw new Error('No se pudo leer la solicitud pendiente. Conserva esta sesión y solicita revisión.')
}
export function limpiarIntentosInversion(actor?: string, persona?: string): void {
  const prefijo = actor ? `${PREFIJO}${actor}:${persona ?? ''}` : PREFIJO
  try {for (const k of Object.keys(sessionStorage)) if (k.startsWith(prefijo)) sessionStorage.removeItem(k)}
  catch { /* El bloqueo de almacenamiento no puede impedir cerrar sesión. */ }
}
export function nuevoIntentoInversion(actor: string, persona: string, id: string, datos: DatosInversion): IntentoInversion {
  const bytes = crypto.getRandomValues(new Uint8Array(24))
  return {version: 1, actor, persona, clave: id, datos,
    token: Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')}
}
export const jsonInversion = (datos: unknown): Json => datos as Json

/** JSONB no conserva el orden de claves; el orden de arrays sí es contractual. */
export function mismoContenidoInversion(a: DatosInversion, b: DatosInversion): boolean {
  const ordenar = (dato: unknown): unknown => Array.isArray(dato) ? dato.map(ordenar)
    : dato !== null && typeof dato === 'object'
      ? Object.fromEntries(Object.entries(dato).sort(([x], [y]) => x.localeCompare(y)).map(([k, v]) => [k, ordenar(v)])) : dato
  return JSON.stringify(ordenar(a)) === JSON.stringify(ordenar(b))
}

/** Los datos reservados de Auth y las referencias originales son inmutables. */
export function datosAvanceRevisados(base: DatosInversion, contrato: Record<string, unknown>, cronograma: unknown[], cuenta: unknown): DatosInversion {
  const payload = {...contrato}
  delete payload.clave_idempotencia
  delete payload.cliente_id
  delete payload.analista_cierre_id
  return {...base, contrato: payload, cronograma, cuenta: cuenta as Record<string, unknown>}
}
export function contratoDeSolicitud(datos: DatosInversion, perfil: string): CrearContratoInput | undefined {
  const c = datos.contrato
  if (!c || typeof c.capital !== 'number' || typeof c.fecha_inicio !== 'string' || !datos.cuenta) return undefined
  // Solo consume un contenido del formulario ya validado o releído del servidor;
  // ContratoNuevo y la puerta económica vuelven a validar todos sus campos.
  return {...c, cliente_id: perfil, cuenta_pago: datos.cuenta} as unknown as CrearContratoInput
}
