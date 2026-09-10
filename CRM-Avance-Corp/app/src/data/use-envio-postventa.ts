import { useRef, useState } from 'react'
import { mensajeDeError } from './crm-api'
import { ejecutarEnvioPostventa } from './postventa-envios'
import { leerEnvioPostventa, type ComandoPostventa, type EnvioPostventa } from '@/lib/postventa-envios'

function leer(actor: string, comando: ComandoPostventa, sujeto: string): {pendiente: EnvioPostventa | null; error: string | null; bloqueado: boolean} {
  try {return {pendiente: leerEnvioPostventa(actor, comando, sujeto), error: null, bloqueado: false}}
  catch {return {pendiente: null, error: 'No se puede leer el envío guardado. Conserva esta sesión para revisarlo.', bloqueado: true}}
}
export function useEnvioPostventa(actor: string, comando: ComandoPostventa, sujeto: string) {
  const [estado, setEstado] = useState(() => leer(actor, comando, sujeto))
  const [ocupado, setOcupado] = useState(false)
  const enviando = useRef(false)
  async function ejecutar(parametros?: Record<string, unknown>): Promise<boolean> {
    if (enviando.current) return false
    enviando.current = true; setOcupado(true)
    try {
      await ejecutarEnvioPostventa(actor, comando, sujeto, parametros)
      setEstado({pendiente: null, error: null, bloqueado: false})
      return true
    } catch (e) {
      const actual = leer(actor, comando, sujeto)
      setEstado({...actual, error: actual.error ?? mensajeDeError(e, 'No se pudo confirmar el envío. Verifica el envío guardado antes de crear otro.')})
      return false
    } finally {enviando.current = false; setOcupado(false)}
  }
  return {...estado, ocupado, ejecutar}
}
