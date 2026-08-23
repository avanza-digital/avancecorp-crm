/**
 * Botón Guardar con la máquina de estados completa del feedback de guardado
 * (Fase 4 del plan UX): reposo → guardando → guardado → reposo, con rama de
 * error reintentable EN EL MISMO botón — el usuario nunca se queda con la
 * duda de «¿funcionó?» ni tiene que buscar dónde reintentar.
 *
 * Nació en el UI Playground (pieza CRM-01) y aquí está adaptado al tema del
 * CRM: el «guardado» es AZUL institucional (--exito), no verde — el chrome
 * del CRM no usa verde. El resultado viaja además por texto y aria-live:
 * el color nunca es el único portador del estado.
 */
import { useEffect, useRef, useState } from 'react'
import { Check, Loader2, RotateCcw } from 'lucide-react'
import { Button, type ButtonProps } from '@/components/ui/button'
import { cn } from '@/lib/utils'

type EstadoGuardar = 'reposo' | 'guardando' | 'guardado' | 'error'

/** Cuánto luce el «Guardado ✓» antes de volver solo al reposo. */
const MS_VISTO_GUARDADO = 1800

export function BotonGuardar({
  onGuardar,
  etiqueta = 'Guardar cambios',
  size,
  disabled = false,
  className,
}: {
  /** Resuelve = guardado; rechaza = error (el botón ofrece reintentar). */
  onGuardar: () => Promise<void>
  etiqueta?: string
  size?: ButtonProps['size']
  disabled?: boolean
  className?: string
}) {
  const [estado, setEstado] = useState<EstadoGuardar>('reposo')
  // La sacudida vive aparte del estado y se apaga en onAnimationEnd: así un
  // segundo fallo consecutivo vuelve a sacudir (la clase sola no re-anima).
  const [sacudir, setSacudir] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined)

  useEffect(() => () => clearTimeout(timer.current), [])

  async function manejar() {
    if (disabled || estado === 'guardando' || estado === 'guardado') return
    setEstado('guardando')
    try {
      await onGuardar()
      setEstado('guardado')
      timer.current = setTimeout(() => setEstado('reposo'), MS_VISTO_GUARDADO)
    } catch {
      setEstado('error')
      setSacudir(true)
    }
  }

  return (
    <Button
      variant={estado === 'error' ? 'destructive' : 'default'}
      size={size}
      onClick={manejar}
      // disabled REAL solo el externo: un disabled durante guardando/guardado
      // expulsaría el foco del teclado al body y silenciaría el aria-live en
      // algunos lectores. El doble envío lo bloquea el guard de manejar().
      disabled={disabled}
      aria-disabled={disabled || estado === 'guardando' || estado === 'guardado'}
      aria-busy={estado === 'guardando'}
      onAnimationEnd={(e) => {
        // animationend burbujea: el ac-pop del Check también llega aquí.
        if (e.animationName === 'ac-shake') setSacudir(false)
      }}
      className={cn(
        estado === 'guardado' && 'bg-exito hover:bg-exito',
        sacudir && 'ac-shake',
        className,
      )}
    >
      {estado === 'guardando' && <Loader2 className="animate-spin" aria-hidden />}
      {estado === 'guardado' && <Check className="ac-pop" aria-hidden />}
      {estado === 'error' && <RotateCcw aria-hidden />}
      {estado === 'reposo' && etiqueta}
      {estado === 'guardando' && 'Guardando…'}
      {estado === 'guardado' && 'Guardado'}
      {estado === 'error' && 'No se pudo guardar · Reintentar'}
      <span aria-live="polite" className="sr-only">
        {estado === 'guardando' && 'Guardando cambios'}
        {estado === 'guardado' && 'Cambios guardados'}
        {estado === 'error' && 'Error al guardar, reintenta'}
      </span>
    </Button>
  )
}
