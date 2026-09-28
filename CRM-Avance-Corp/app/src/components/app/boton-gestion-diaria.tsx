// Botón «GESTIÓN DIARIA» — la CTA de la esquina superior derecha de «Hoy» del
// analista. Promovida del UI Playground (pieza CRM-02, aprobada por Miguel el
// 28/09/2026): el playground manda en el DISEÑO y el CRM en los PATRONES.
//  · El rótulo es GESTIÓN DIARIA y nada más; el estado lo dicen el color, el
//    teléfono y la barra de avance. El detalle («2 vencidas · 3 pendientes»)
//    queda para el lector de pantalla, en el aria-label.
//  · Tres niveles: urgente (vencidas > 0: ámbar en borde, aura y barra; el
//    teléfono suena fuerte) · activo (solo pendientes: azul, suena suave) ·
//    al día (navy, check, sin barra, quieto).
//  · Aura y brillo insisten solo si hay trabajo y el analista NO ha entrado
//    hoy (`yaVisitoHoy`); el rebote de pelota se detiene al pasar el cursor.
//  · Al hacer clic el teléfono descuelga 420 ms y después se navega (`onIr`).
//    Con prefers-reduced-motion no hay nada que esperar: se navega al instante.
//  · Sin Motion: todo el movimiento vive en boton-gestion-diaria.css. El texto
//    es SIEMPRE blanco: nada de letras ámbar.
import { Check, ChevronRight, Phone } from 'lucide-react'
import { useEffect, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react'
import { hashDe } from '@/lib/router'
import { cn } from '@/lib/utils'
import './boton-gestion-diaria.css'

export interface EstadoGestionDiaria {
  /** Gestiones vencidas (ya pasó su hora). */
  vencidas: number
  /** Gestiones por hacer hoy, sin contar las vencidas. */
  pendientes: number
  /** Gestiones hechas hoy. */
  hechas: number
  /** Si ya entró hoy a Gestión diaria, el aura y el brillo se calman. */
  yaVisitoHoy: boolean
}

type NivelGestionDiaria = 'urgente' | 'activo' | 'aldia'

/** Lo que manda es lo vencido; después lo pendiente; sin nada de eso, al día. */
function nivelDe(estado: Pick<EstadoGestionDiaria, 'vencidas' | 'pendientes'>): NivelGestionDiaria {
  if (estado.vencidas > 0) return 'urgente'
  if (estado.pendientes > 0) return 'activo'
  return 'aldia'
}

/** El botón se llama así y nada más (Miguel, 28/09/2026). */
const ROTULO = 'GESTIÓN DIARIA'

/** Lo que tarda el teléfono en descolgar antes de cambiar de pantalla. */
export const DURACION_DESCOLGAR_MS = 420

/** Cuánto ha de pasar entre dos «pop» seguidos. */
const PAUSA_POP_MS = 350

function contar(n: number, singular: string, plural: string): string {
  return `${n} ${n === 1 ? singular : plural}`
}

/**
 * El detalle para el lector de pantalla; en pantalla NO se escribe:
 * «2 vencidas, 3 pendientes. 4 de 9 gestiones hechas hoy» o «Al día. …».
 * Coma y no «·»: NVDA se salta el punto medio y VoiceOver lo lee «punto medio»
 * (revisión a11y, 28/09/2026).
 */
function detalleAccesible(estado: EstadoGestionDiaria): string {
  const total = estado.hechas + estado.pendientes + estado.vencidas
  const avance = total === 0 ? 'Sin gestiones registradas hoy' : `${estado.hechas} de ${total} gestiones hechas hoy`
  if (nivelDe(estado) === 'aldia') return `Al día. ${avance}`
  const pendientes = contar(estado.pendientes, 'pendiente', 'pendientes')
  const cola = estado.vencidas > 0 ? `${contar(estado.vencidas, 'vencida', 'vencidas')}, ${pendientes}` : pendientes
  return `${cola}. ${avance}`
}

interface Pop {
  sonar: () => void
  /** Libera el AudioContext: el navegador limita cuántos puede haber vivos a la vez. */
  cerrar: () => void
}

/**
 * «Pop» corto sintetizado (Web Audio, sin archivos) al pasar el cursor o
 * enfocar. Sin AudioContext (jsdom, navegadores viejos) devuelve un no-op; con
 * él, como mucho un pop cada 350 ms. El navegador solo deja sonar después de
 * una interacción real (clic o tecla): hasta entonces el contexto queda en
 * pausa y el hover no suena. Cualquier fallo se traga: el botón sigue igual.
 */
function crearPop(): Pop {
  if (typeof AudioContext === 'undefined') return { sonar() {}, cerrar() {} }
  let ctx: AudioContext | null = null
  let ultimo = Number.NEGATIVE_INFINITY
  const tocar = (c: AudioContext) => {
    try {
      const t = c.currentTime
      const osc = c.createOscillator()
      const gain = c.createGain()
      osc.type = 'sine'
      osc.frequency.setValueAtTime(660, t)
      osc.frequency.exponentialRampToValueAtTime(1180, t + 0.09)
      gain.gain.setValueAtTime(0.0001, t)
      gain.gain.exponentialRampToValueAtTime(0.16, t + 0.012)
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.19)
      osc.connect(gain).connect(c.destination)
      osc.start(t)
      osc.stop(t + 0.2)
    } catch {
      /* sin audio: el botón sigue funcionando igual */
    }
  }
  return {
    sonar() {
      const ahora = performance.now()
      if (ahora - ultimo < PAUSA_POP_MS) return
      ultimo = ahora
      try {
        ctx ??= new AudioContext()
        const c = ctx
        // El oscilador solo se programa con el contexto EN MARCHA. Si el
        // navegador lo deja en pausa (aún no hubo gesto del usuario), el pop se
        // descarta: no se encola para sonar tarde. Un `resume()` rechazado se
        // captura aquí y no deja un rechazo suelto.
        const listo = c.state === 'running' ? Promise.resolve() : c.resume()
        listo
          .then(() => {
            if (c.state === 'running') tocar(c)
          })
          .catch(() => {
            /* el navegador no dejó sonar: sin pop */
          })
      } catch {
        /* sin audio: el botón sigue funcionando igual */
      }
    },
    cerrar() {
      const c = ctx
      ctx = null
      if (c === null) return
      try {
        c.close().catch(() => {
          /* ya cerrado */
        })
      } catch {
        /* sin soporte */
      }
    },
  }
}

/** Mismo criterio que el splash: sin matchMedia se asume movimiento reducido. */
function prefiereMovimientoReducido(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

export function BotonGestionDiaria({
  estado,
  onIr,
  sonido = true,
  sinCifras = false,
  className,
}: {
  estado: EstadoGestionDiaria
  /** Navega a Gestión diaria cuando el teléfono terminó de descolgar. Sin él, el enlace navega solo. */
  onIr?: (() => void) | undefined
  /** «Pop» al pasar el cursor o enfocar con teclado. */
  sonido?: boolean
  /** Todavía no hay cifras del día (cargando o RPC caído): navy, teléfono quieto, sin barra ni check. */
  sinCifras?: boolean
  className?: string | undefined
}) {
  const [descolgado, setDescolgado] = useState(false)
  const temporizador = useRef<number | null>(null)
  const pop = useRef<Pop | null>(null)
  // Si la pantalla cambia antes de los 420 ms, el aviso muere con el botón; y
  // el AudioContext se libera (el navegador limita cuántos puede haber vivos).
  useEffect(
    () => () => {
      if (temporizador.current !== null) window.clearTimeout(temporizador.current)
      pop.current?.cerrar()
      pop.current = null
    },
    [],
  )

  const nivel = nivelDe(estado)
  const total = estado.hechas + estado.pendientes + estado.vencidas
  const hayTrabajo = !sinCifras && nivel !== 'aldia'
  const insistir = hayTrabajo && !estado.yaVisitoHoy
  const rebota = hayTrabajo && !descolgado
  const avancePct = total > 0 ? Math.round((estado.hechas / total) * 100) : 100

  const sonar = () => {
    if (!sonido) return
    pop.current ??= crearPop()
    pop.current.sonar()
  }

  const alClic = (e: ReactMouseEvent<HTMLAnchorElement>) => {
    if (!onIr) return
    // Con modificadores manda el navegador (pestaña nueva, etc.): no se secuestra.
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return
    e.preventDefault()
    if (temporizador.current !== null) return // ya está descolgando
    if (prefiereMovimientoReducido()) {
      onIr()
      return
    }
    setDescolgado(true)
    temporizador.current = window.setTimeout(() => {
      temporizador.current = null
      onIr()
      setDescolgado(false)
    }, DURACION_DESCOLGAR_MS)
  }

  return (
    <span
      className={cn(
        'bgd',
        !sinCifras && `bgd--${nivel}`,
        !insistir && 'bgd--calmo',
        rebota && 'bgd--rebota',
        descolgado && 'bgd--descolgado',
        className,
      )}
      data-nivel={sinCifras ? 'sin-cifras' : nivel}
    >
      {/* Piso: la sombra se encoge cuando el botón está en el aire. */}
      <span className="bgd__sombra" aria-hidden />
      <span className="bgd__pelota">
        {insistir && <span className="bgd__aura" aria-hidden />}
        <a
          className="bgd__boton"
          href={hashDe('gestion-diaria')}
          aria-label={`Ir a Gestión diaria. ${sinCifras ? 'Sin cifras del día todavía' : detalleAccesible(estado)}`}
          onMouseEnter={sonar}
          onFocus={sonar}
          onClick={alClic}
        >
          {insistir && <span className="bgd__brillo" aria-hidden />}
          <span className="bgd__telefono" aria-hidden>
            {!sinCifras && nivel === 'aldia' ? <Check size={16} /> : <Phone size={16} />}
          </span>
          <span className="bgd__texto">
            <span className="bgd__rotulo">{ROTULO}</span>
            {hayTrabajo && (
              <span className="bgd__avance">
                <span className="bgd__pista" aria-hidden>
                  <span className="bgd__relleno" style={{ width: `${avancePct}%` }} />
                </span>
                <span className="bgd__cuenta">
                  {estado.hechas} de {total}
                </span>
              </span>
            )}
          </span>
          <span className="bgd__flecha" aria-hidden>
            <ChevronRight size={16} />
          </span>
        </a>
      </span>
    </span>
  )
}
