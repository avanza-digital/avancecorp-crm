import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'
import { agendarPostventa, gestionarTareaPostventa, cambiarVetoPostventa, solicitarRetiroPostventa, revisarRetiroPostventa } from './postventa-api'
import { guardarEnvioPostventa, borrarEnvioPostventa, leerEnvioPostventa, type ComandoPostventa, type EnvioPostventa } from '@/lib/postventa-envios'
import { jsonInversion } from '@/lib/inversion-solicitud'
const Uuid = v.pipe(v.string(), v.uuid())
const datos = v.record(v.string(), v.unknown())

export async function verificarEnvioPostventa(envio: EnvioPostventa): Promise<boolean> {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  await comprobarActor(envio.actor)
  const r = respuestaInversionistas(v.object({registrada: v.boolean()}), await sb.schema('crm').rpc('postventa_operacion_estado_fn', {p_clave: envio.clave, p_actor: envio.actor}))
  if (r.registrada) borrarEnvioPostventa(envio)
  return r.registrada
}
export async function enviarPostventa(guardado: EnvioPostventa): Promise<void> {
  await comprobarActor(guardado.actor)
  const e = {...guardado, intentos: guardado.intentos + 1}
  guardarEnvioPostventa(e) // Si no puede recuperarse, no se envía.
  try {
    switch (e.comando) {
      case 'agendar': {
        const p = v.parse(v.object({p_inversionista: Uuid, p_datos: datos}), e.parametros)
        await agendarPostventa({...p, p_datos: jsonInversion(p.p_datos), p_clave: e.clave, p_actor: e.actor}); break
      }
      case 'tarea': {
        const p = v.parse(v.object({p_tarea: Uuid, p_revision: v.number(), p_accion: v.picklist(['cerrar', 'reprogramar', 'confirmar']), p_datos: datos}), e.parametros)
        await gestionarTareaPostventa({...p, p_datos: jsonInversion(p.p_datos), p_clave: e.clave, p_actor: e.actor}); break
      }
      case 'veto': {
        const p = v.parse(v.object({p_inversionista: Uuid, p_vetar: v.boolean(), p_motivo: v.string()}), e.parametros)
        await cambiarVetoPostventa({...p, p_clave: e.clave, p_actor: e.actor}); break
      }
      case 'solicitar_retiro': {
        const p = v.parse(v.object({p_inversionista: Uuid, p_fuente: Uuid, p_motivo: v.string()}), e.parametros)
        await solicitarRetiroPostventa({...p, p_clave: e.clave, p_actor: e.actor}); break
      }
      case 'revisar_retiro': {
        const p = v.parse(v.object({p_retiro: Uuid, p_revision: v.number(), p_estado: v.string(), p_detalle: v.string()}), e.parametros)
        await revisarRetiroPostventa({...p, p_clave: e.clave, p_actor: e.actor}); break
      }
    }
    borrarEnvioPostventa(e)
  } catch (error) {
    // Solo un primer envío con rechazo SQL explícito prueba que no hubo commit.
    // Después de un corte, ni OFF ni 42501 prueban que el intento anterior falló.
    if (e.intentos === 1 && error instanceof CrmApiError
      && ['22023', '23505', '23514', '23502', '42501', 'P0409', 'P0429', 'PT409', '40001', '0A000'].includes(error.code ?? '')) {
      borrarEnvioPostventa(e)
    }
    throw error
  }
}

async function comprobarActor(actor: string): Promise<void> {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  const {data, error} = await sb.auth.getSession()
  // Comprobación local de pertenencia del borrador; la autorización viva la aplica la RPC.
  if (error || data.session?.user.id !== actor) throw new CrmApiError('La sesión cambió. Vuelve a abrir la ficha con tu cuenta.', 'SESSION_CHANGED')
}
function contenido(valor: unknown): string {
  if (Array.isArray(valor)) return `[${valor.map(contenido).join(',')}]`
  if (valor && typeof valor === 'object') return `{${Object.entries(valor).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${JSON.stringify(k)}:${contenido(v)}`).join(',')}}`
  return JSON.stringify(valor) ?? 'null'
}
const enCurso = new Set<string>()
/** Un solo envío por sujeto: conserva clave y contenido incluso entre formularios. */
export async function ejecutarEnvioPostventa(actor: string, comando: ComandoPostventa, sujeto: string, parametros?: Record<string, unknown>): Promise<void> {
  const llave = `${actor}:${comando}:${sujeto}`
  if (enCurso.has(llave)) throw new Error('Esta gestión ya se está enviando. Espera a que termine.')
  enCurso.add(llave)
  try {
    let envio = leerEnvioPostventa(actor, comando, sujeto)
    if (envio && parametros && contenido(parametros) !== contenido(envio.parametros)) {
      throw new Error('Hay una gestión anterior sin confirmar. Abre su formulario y verifica el envío guardado antes de cambiarla.')
    }
    if (envio && await verificarEnvioPostventa(envio)) return
    if (!envio) {
      if (!parametros) throw new Error('No hay ningún envío pendiente por recuperar.')
      envio = {version: 1, actor, comando, sujeto, clave: crypto.randomUUID(), parametros, intentos: 0}
      guardarEnvioPostventa(envio)
    }
    await enviarPostventa(envio)
  } finally {enCurso.delete(llave)}
}
