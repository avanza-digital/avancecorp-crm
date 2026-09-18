import { sb } from '@/lib/supabase'
import type { Database, Json } from '@/lib/database.types'
import type { Tarea } from '@/lib/tipos'
import { CrmApiError } from './crm-api'

type Comando = 'registrar_actividad_v2' | 'cerrar_tarea_v2' | 'cerrar_reunion_v2' |
  'cerrar_reunion_v3' | 'reprogramar_reunion_v2' | 'reprogramar_tarea_v2'
type Argumentos<C extends Comando> = Omit<Database['crm']['Functions'][C]['Args'], 'p_operacion_id'>
type Peticion = { [C in Comando]: [actor: string | null, comando: C, sujeto: string, argumentos: Argumentos<C>, tarea?: Tarea] }[Comando]
interface Intencion {
  operacion: string
  comando: Comando
  sujeto: string
  argumentos: Record<string, Json | undefined>
  huella: string
  incierta?: boolean
  tarea?: Tarea
}
const PREFIJO = 'crm.sla.operacion.v2:'
const EVENTO = 'crm:sla-intenciones-cambiadas'
const COMANDOS = new Set<Comando>(['registrar_actividad_v2', 'cerrar_tarea_v2', 'cerrar_reunion_v2', 'cerrar_reunion_v3', 'reprogramar_reunion_v2', 'reprogramar_tarea_v2'])
const vuelos = new Map<string, Promise<void>>()
const notificar = () => { if (typeof window !== 'undefined') window.dispatchEvent(new Event(EVENTO)) }

// La identidad de la petición se guarda ANTES de enviarla. Una respuesta de
// red perdida conserva el mismo recibo al reintentar, incluso tras recargar.
// Ninguna regla comercial se calcula aquí: la RPC gobierna el resultado.
function clave(actor: string, sujeto: string, comando: Comando): string {
  return `${PREFIJO}${actor}:${comando === 'registrar_actividad_v2' ? 'actividad' : 'tarea'}:${sujeto}`
}

function leer(llave: string): Intencion | null {
  const valor = sessionStorage.getItem(llave)
  if (!valor) return null
  try {
    const dato = JSON.parse(valor) as Intencion
    if (typeof dato.operacion !== 'string' || typeof dato.huella !== 'string' || !COMANDOS.has(dato.comando) ||
      typeof dato.sujeto !== 'string' ||
      typeof dato.argumentos !== 'object' || !dato.argumentos) throw new Error()
    return dato
  } catch {
    // Nunca fabricar otro UUID si se perdió la identidad de un envío previo.
    throw new CrmApiError('No se puede recuperar la confirmación anterior. Recarga y verifica el historial.', 'SLA_RECIBO_INVALIDO')
  }
}

function ordenar(valor: unknown): unknown {
  if (Array.isArray(valor)) return valor.map(ordenar)
  if (valor && typeof valor === 'object') {
    return Object.fromEntries(Object.entries(valor).sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => [k, ordenar(v)]))
  }
  return valor
}

function huella(comando: Comando, args: Record<string, Json | undefined>): string {
  const logicos = { ...args }
  // Son identidades generadas por el cliente, no cambios pedidos por la
  // persona. Al repetir el mismo gesto se recuperan las del primer envío.
  delete logicos.p_nueva_id
  if (logicos.p_siguiente && typeof logicos.p_siguiente === 'object' && !Array.isArray(logicos.p_siguiente)) {
    const siguiente = { ...logicos.p_siguiente }
    delete siguiente.id
    logicos.p_siguiente = siguiente
  }
  return JSON.stringify(ordenar({ comando, argumentos: logicos }))
}

export function tareaConConfirmacionPendiente(actor: string | null, id: string): Tarea | undefined {
  if (!actor) return undefined
  try { return leer(clave(actor, id, 'cerrar_tarea_v2'))?.tarea } catch { return undefined }
}

export function limpiarIntencionesSla(): void {
  vuelos.clear()
  try {
    for (let i = sessionStorage.length - 1; i >= 0; i -= 1) {
      const llave = sessionStorage.key(i)
      if (llave?.startsWith(PREFIJO)) sessionStorage.removeItem(llave)
    }
  } catch { /* Puede estar deshabilitado: en ese caso tampoco se envía nada. */ }
  notificar()
}

export function suscribirPendientesSla(callback: () => void): () => void {
  window.addEventListener(EVENTO, callback)
  return () => window.removeEventListener(EVENTO, callback)
}

export function listarPendientesSla(actor: string | null): Array<{ operacion: string; comando: string; enCurso: boolean }> {
  if (!actor) return []
  const pendientes: Array<{ operacion: string; comando: string; enCurso: boolean }> = []
  try {
    for (let i = 0; i < sessionStorage.length; i += 1) {
      const llave = sessionStorage.key(i)
      if (!llave?.startsWith(`${PREFIJO}${actor}:`)) continue
      const dato = leer(llave)
      if (dato) pendientes.push({ operacion: dato.operacion, comando: dato.comando, enCurso: vuelos.has(llave) })
    }
  } catch { /* El envío original muestra su error de almacenamiento. */ }
  return pendientes
}

// Recuperación explícita tras recargar: reenvía el contenido conservado del
// gesto original. No vuelve a calcular fechas ni crea otra identidad.
export async function confirmarPendienteSla(actor: string | null, operacion: string): Promise<void> {
  if (!actor) throw new CrmApiError('La sesión no está disponible', 'SLA_SIN_SESION')
  for (let i = 0; i < sessionStorage.length; i += 1) {
    const llave = sessionStorage.key(i)
    if (!llave?.startsWith(`${PREFIJO}${actor}:`)) continue
    const dato = leer(llave)
    if (dato?.operacion !== operacion) continue
    // El comando se valida en leer; los parámetros originales conservan el
    // contrato que vuelve a validar la misma RPC, incluido el recibo exacto.
    const peticion = [actor, dato.comando, dato.sujeto, dato.argumentos, dato.tarea] as unknown as Peticion
    return ejecutarComandoSla(...peticion)
  }
  throw new CrmApiError('Esta operación ya no está pendiente. Actualiza la vista para comprobar el resultado.', 'SLA_SIN_PENDIENTE')
}

export async function ejecutarComandoSla(...[actor, comando, sujeto, argumentos, tarea]: Peticion): Promise<void> {
  if (!actor || !sb) throw new CrmApiError('La sesión no está disponible', 'SLA_SIN_SESION')
  const llave = clave(actor, sujeto, comando)
  const firma = huella(comando, argumentos)
  let intencion = leer(llave)
  const eraIncierta = intencion?.incierta === true
  if (intencion && intencion.huella !== firma) {
    throw new CrmApiError('Hay un guardado pendiente de confirmar. Reintenta con los mismos datos antes de cambiarlos.', 'SLA_CONFIRMACION_PENDIENTE')
  }
  if (!intencion) {
    intencion = { operacion: crypto.randomUUID(), comando, sujeto, argumentos, huella: firma, ...(tarea ? { tarea } : {}) }
  }
  const actual = vuelos.get(llave)
  if (actual) return actual
  intencion.incierta = true
  try { sessionStorage.setItem(llave, JSON.stringify(intencion)) } catch {
    throw new CrmApiError('No se pudo preparar el guardado. Habilita el almacenamiento de esta pestaña y reintenta.', 'SLA_ALMACENAMIENTO')
  }
  const enviada = intencion
  const ejecutar = async () => {
    const { data, error } = await sb!.schema('crm').rpc(comando, {
      ...enviada.argumentos, p_operacion_id: enviada.operacion,
    } as Database['crm']['Functions'][Comando]['Args'])
    if (error) {
      // Un SQLSTATE de la transacción significa rollback confirmado. Los
      // fallos de transporte/HTTP sin SQLSTATE mantienen la identidad.
      if (!eraIncierta && /^[0-9A-Z]{5}$/.test(error.code ?? '') && !error.code.startsWith('08')) {
        sessionStorage.removeItem(llave)
        throw new CrmApiError(error.message || 'El servidor rechazó el guardado', error.code)
      }
      throw new CrmApiError('Confirmación pendiente. Reintenta el mismo guardado; no se duplicará.', 'SLA_CONFIRMACION_PENDIENTE')
    }
    const respuesta = data as Record<string, Json> | null
    const leadEsperado = 'p_lead_id' in argumentos ? argumentos.p_lead_id : tarea?.lead_id
    if (!respuesta || respuesta.ok !== true || respuesta.version !== 2 || respuesta.operacion_id !== enviada.operacion ||
      // El servidor nombra el comando del NÚCLEO, sin la versión de la puerta:
      // `cerrar_reunion_v3` confirma `cerrar_reunion`, igual que la v2. Sin
      // contemplar la v3 aquí, un cierre que el servidor SÍ escribió se
      // anunciaría como «no confirmado» y el analista lo repetiría.
      respuesta.comando !== comando.replace(/_v[23]$/, '') || (leadEsperado && respuesta.lead_id !== leadEsperado)) {
      throw new CrmApiError('El servidor no confirmó el guardado. Reintenta con los mismos datos.', 'SLA_CONFIRMACION_PENDIENTE')
    }
    // Solo borrar el recibo que acabamos de confirmar (p. ej. tras un logout).
    if (leer(llave)?.operacion === enviada.operacion) sessionStorage.removeItem(llave)
  }
  const vuelo = ejecutar().catch((causa: unknown) => {
    if (causa instanceof CrmApiError) throw causa
    throw new CrmApiError('Confirmación pendiente. Reintenta el mismo guardado; no se duplicará.', 'SLA_CONFIRMACION_PENDIENTE')
  }).finally(() => { if (vuelos.get(llave) === vuelo) vuelos.delete(llave); notificar() })
  vuelos.set(llave, vuelo)
  notificar()
  return vuelo
}
