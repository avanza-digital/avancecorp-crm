// Ventana de corrección de 5 HORAS del portal (espejo de analista.js:231-255).
// La ventana la decide el SERVIDOR (RLS por creado_en); esto es solo la cuenta
// regresiva visual. TRAMPA MORTAL río abajo: si la ventana venció, el UPDATE a
// perfiles NO da error — devuelve 0 filas y se queda callado (por eso crm-api
// pide .select('id') y trata 0 filas como "no se guardó").
import { useEffect, useState } from 'react'

export const VENTANA_MS = 5 * 60 * 60 * 1000

/** Milisegundos que quedan de ventana (negativo = ya venció). */
export function msRestantes(creadoEn: string): number {
  return new Date(creadoEn).getTime() + VENTANA_MS - Date.now()
}

/** ¿La ventana sigue viva? (un timestamp ilegible cuenta como vencida: NaN > 0 es false). */
export function ventanaVigente(creadoEn: string): boolean {
  return msRestantes(creadoEn) > 0
}

/**
 * Texto listo para la UI: 'Quedan 3 h 42 m' | 'Bloqueado' (minutos con dos
 * dígitos, igual que el portal). Sin emojis: el CRM marca el estado con color.
 */
export function textoVentana(creadoEn: string): string {
  const ms = msRestantes(creadoEn)
  if (!(ms > 0)) return 'Bloqueado' // cubre también NaN (fecha ilegible → bloqueado)
  const totalMin = Math.floor(ms / 60_000)
  const h = Math.floor(totalMin / 60)
  const m = totalMin % 60
  return `Quedan ${h} h ${String(m).padStart(2, '0')} m`
}

export interface EstadoVentana {
  ms: number
  vigente: boolean
  texto: string
}

/**
 * Cuenta regresiva viva: re-renderiza cada 15 s (mismo tick que el countdown de
 * analista.js) y se detiene sola al vencer — el último tick pinta 'Bloqueado'.
 * `creadoEn` nulo (fila aún sin cargar) se trata como vencida, sin timer.
 */
export function useVentana(creadoEn: string | null | undefined): EstadoVentana {
  const [, setTick] = useState(0)

  useEffect(() => {
    if (!creadoEn || msRestantes(creadoEn) <= 0) return // ya vencida: nada que refrescar
    const timer = setInterval(() => {
      setTick((t) => t + 1)
      // Tras vencer ya no cambia nada: se corta el intervalo (el render de este
      // tick ya mostró 'Bloqueado').
      if (msRestantes(creadoEn) <= 0) clearInterval(timer)
    }, 15_000)
    return () => clearInterval(timer)
  }, [creadoEn])

  if (!creadoEn) return { ms: 0, vigente: false, texto: 'Bloqueado' }
  const ms = msRestantes(creadoEn)
  return { ms, vigente: ms > 0, texto: textoVentana(creadoEn) }
}
