import * as v from 'valibot'

export const COMANDOS_POSTVENTA = ['agendar', 'tarea', 'veto', 'solicitar_retiro', 'revisar_retiro'] as const
export type ComandoPostventa = (typeof COMANDOS_POSTVENTA)[number]
const Uuid = v.pipe(v.string(), v.uuid())
const EnvioSchema = v.object({version: v.literal(1), actor: Uuid, sujeto: Uuid, clave: Uuid,
  comando: v.picklist(COMANDOS_POSTVENTA), parametros: v.record(v.string(), v.unknown()),
  intentos: v.pipe(v.number(), v.integer(), v.minValue(0)),
})
export type EnvioPostventa = v.InferOutput<typeof EnvioSchema>
const PREFIJO = 'crm:f6:envio:'
const llave = (actor: string, comando: ComandoPostventa, sujeto: string) => `${PREFIJO}${actor}:${comando}:${sujeto}`
export function leerEnvioPostventa(actor: string, comando: ComandoPostventa, sujeto: string): EnvioPostventa | null {
  const raw = sessionStorage.getItem(llave(actor, comando, sujeto))
  if (!raw) return null
  try {
    const r = v.safeParse(EnvioSchema, JSON.parse(raw))
    if (r.success && r.output.actor === actor && r.output.comando === comando && r.output.sujeto === sujeto) return r.output
  } catch { /* No mostrar ni registrar contenido local. */ }
  throw new Error('No se pudo leer el envío pendiente. Conserva esta sesión para revisarlo.')
}
export function guardarEnvioPostventa(envio: EnvioPostventa): void {
  const e = v.parse(EnvioSchema, envio)
  sessionStorage.setItem(llave(e.actor, e.comando, e.sujeto), JSON.stringify(e))
}
export function borrarEnvioPostventa(e: Pick<EnvioPostventa, 'actor' | 'comando' | 'sujeto'>): void {
  sessionStorage.removeItem(llave(e.actor, e.comando, e.sujeto))
}
export function limpiarEnviosPostventa(): void {
  try {for (const k of Object.keys(sessionStorage)) if (k.startsWith(PREFIJO)) sessionStorage.removeItem(k)}
  catch { /* El cierre de sesión prevalece sobre almacenamiento bloqueado. */ }
}
