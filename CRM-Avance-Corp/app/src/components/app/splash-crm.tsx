import { useGSAP } from '@gsap/react'
import gsap from 'gsap'
import CustomEase from 'gsap/CustomEase'
import MotionPathPlugin from 'gsap/MotionPathPlugin'
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { calcularViajeSplash } from './splash-crm-motion'
import './splash-crm.css'

gsap.registerPlugin(useGSAP, CustomEase, MotionPathPlugin)
CustomEase.create('avance-splash', 'M0,0 C0.22,1 0.36,1 1,1')

export type FaseSplashCrm = 'acceso' | 'datos' | 'listo'

const MENSAJES: Record<FaseSplashCrm, string> = {
  acceso: 'Verificando tu acceso…',
  datos: 'Preparando tu espacio de trabajo…',
  listo: 'Tu espacio está listo',
}

function prefiereMovimientoReducido(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function useMovimientoReducido(): boolean {
  const [reducido, setReducido] = useState(prefiereMovimientoReducido)

  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return
    const consulta = window.matchMedia('(prefers-reduced-motion: reduce)')
    const actualizar = () => setReducido(consulta.matches)
    actualizar()

    if (typeof consulta.addEventListener === 'function') {
      consulta.addEventListener('change', actualizar)
      return () => consulta.removeEventListener('change', actualizar)
    }

    consulta.addListener(actualizar)
    return () => consulta.removeListener(actualizar)
  }, [])

  return reducido
}

/**
 * Capa visual del arranque. La fase siempre viene del estado real de Auth/Store:
 * la animación ilustra el avance, pero nunca decide cuándo está listo el CRM.
 */
export function SplashCrm({
  fase,
  onFinalizar,
}: {
  fase: FaseSplashCrm
  onFinalizar?: (() => void) | undefined
}) {
  const raizRef = useRef<HTMLDivElement>(null)
  const isotipoRef = useRef<HTMLDivElement>(null)
  const entradaRef = useRef<gsap.core.Timeline | null>(null)
  const ambienteRef = useRef<gsap.core.Timeline | null>(null)
  const salidaRef = useRef<gsap.core.Timeline | null>(null)
  const finalizadoRef = useRef(false)
  const faseActualRef = useRef(fase)
  const faseAnteriorRef = useRef(fase)
  const reducido = useMovimientoReducido()

  // Los callbacks tardíos de GSAP solo deben observar una fase que React ya
  // comprometió. Escribir el ref durante render permitiría que un render
  // concurrente abortado contaminara la timeline todavía visible.
  useLayoutEffect(() => {
    faseActualRef.current = fase
  }, [fase])

  // Movimiento ambiental independiente. Al vivir en su propio contexto, un
  // cambio de fase no reinicia las auroras ni el destello de progreso.
  useGSAP(
    () => {
      const raiz = raizRef.current
      if (!raiz) return

      const q = gsap.utils.selector(raiz)
      const brilloProgreso = q('.ac-splash__progreso-brillo')
      gsap.set(brilloProgreso, { xPercent: -130 })

      if (reducido) return

      const timeline = gsap.timeline()
      timeline
        .to(
          q('.ac-splash__aurora--uno'),
          {
            xPercent: 8,
            yPercent: 6,
            duration: 4.2,
            ease: 'sine.inOut',
            yoyo: true,
            repeat: -1,
          },
          0,
        )
        .to(
          q('.ac-splash__aurora--dos'),
          {
            xPercent: -7,
            yPercent: -5,
            duration: 5,
            ease: 'sine.inOut',
            yoyo: true,
            repeat: -1,
          },
          0,
        )
        .to(
          brilloProgreso,
          {
            xPercent: 230,
            duration: 1.15,
            ease: 'power1.inOut',
            repeat: -1,
          },
          0,
        )
      ambienteRef.current = timeline

      return () => {
        if (ambienteRef.current === timeline) ambienteRef.current = null
      }
    },
    {
      scope: raizRef,
      dependencies: [reducido],
      revertOnUpdate: true,
    },
  )

  // La presentación de la marca corre una sola vez durante el montaje. Al
  // pasar de acceso a datos el mismo nodo continúa vivo, así que no hay un
  // segundo “flash” ni un reinicio del logo.
  useGSAP(
    () => {
      const raiz = raizRef.current
      const isotipo = isotipoRef.current
      if (!raiz || !isotipo) return

      const q = gsap.utils.selector(raiz)
      const fondo = q('.ac-splash__fondo')
      const marca = q('.ac-splash__marca')
      const lockup = q('.ac-splash__lockup')
      const logo = q('.ac-splash__logo')
      const chispa = q('.ac-splash__chispa')
      const brilloLogo = q('.ac-splash__brillo-logo')
      const estado = q('.ac-splash__estado')
      const progreso = q('.ac-splash__progreso-carga')
      const esAcceso = faseActualRef.current === 'acceso'

      gsap.set(raiz, { autoAlpha: 1 })
      gsap.set(fondo, { autoAlpha: 1, clipPath: 'inset(0% 0% 0% 0%)' })
      gsap.set(isotipo, {
        autoAlpha: 1,
        x: 0,
        y: 0,
        scale: 1,
        rotation: reducido || !esAcceso ? 0 : -4,
        borderRadius: 24,
        transformOrigin: '50% 50%',
      })
      gsap.set(lockup, { autoAlpha: 1, x: 0 })
      gsap.set(logo, {
        clipPath: reducido || !esAcceso ? 'inset(0%)' : 'inset(100% 0% 0% 0%)',
        scale: reducido || !esAcceso ? 1 : 0.9,
        transformOrigin: 'center bottom',
      })
      gsap.set(marca, {
        autoAlpha: reducido || !esAcceso ? 1 : 0,
        y: reducido || !esAcceso ? 0 : 18,
        scale: reducido || !esAcceso ? 1 : 0.94,
      })
      gsap.set(estado, { autoAlpha: 1, y: 0 })
      gsap.set(chispa, { autoAlpha: 0 })
      gsap.set(brilloLogo, { xPercent: -180 })
      gsap.set(progreso, {
        scaleX: esAcceso ? 0.08 : 0.46,
        transformOrigin: 'left center',
      })

      if (reducido) {
        gsap.set(progreso, { scaleX: esAcceso ? 0.46 : 0.9 })
        return
      }

      if (!esAcceso) return

      const timeline = gsap.timeline({ defaults: { ease: 'avance-splash' } })
      entradaRef.current = timeline

      const lado = isotipo.clientWidth || 96
      timeline
        .addLabel('entrada')
        .to(marca, { autoAlpha: 1, y: 0, scale: 1, duration: 0.72 })
        .to(isotipo, { rotation: 0, duration: 0.8 }, 'entrada')
        .to(
          logo,
          { clipPath: 'inset(0% 0% 0% 0%)', scale: 1, duration: 0.68 },
          'entrada+=0.12',
        )
        .to(chispa, { autoAlpha: 1, duration: 0.08 }, 'entrada+=0.48')
        .to(
          chispa,
          {
            motionPath: {
              path: [
                { x: lado * 0.08, y: lado * 0.69 },
                { x: lado * 0.3, y: lado * 0.82 },
                { x: lado * 0.53, y: lado * 0.88 },
                { x: lado * 0.72, y: lado * 0.66 },
                { x: lado * 0.92, y: lado * 0.48 },
              ],
              curviness: 1.35,
            },
            duration: 0.76,
            ease: 'power1.inOut',
          },
          'entrada+=0.48',
        )
        .to(chispa, { autoAlpha: 0, duration: 0.18 }, 'entrada+=1.08')
        .to(brilloLogo, { xPercent: 190, duration: 0.9, ease: 'power2.inOut' }, 'entrada+=0.45')
        .to(progreso, { scaleX: 0.46, duration: 1.2, ease: 'power2.out' }, 'entrada+=0.65')

      return () => {
        if (entradaRef.current === timeline) entradaRef.current = null
      }
    },
    {
      scope: raizRef,
      dependencies: [reducido],
      revertOnUpdate: true,
    },
  )

  // Transiciones reactivas de fase. Este contexto sí se revierte en cada
  // actualización para que una recarga que ocurra durante la salida recupere
  // un lienzo limpio y no herede transforms/opacidades a medio camino.
  useGSAP(
    () => {
      const raiz = raizRef.current
      const isotipo = isotipoRef.current
      if (!raiz || !isotipo) return

      const q = gsap.utils.selector(raiz)
      const progreso = q('.ac-splash__progreso-carga')
      const estado = q('.ac-splash__estado')
      const lockup = q('.ac-splash__lockup')
      const fondo = q('.ac-splash__fondo')
      const marca = q('.ac-splash__marca')
      const logo = q('.ac-splash__logo')
      const chispa = q('.ac-splash__chispa')
      const brilloLogo = q('.ac-splash__brillo-logo')
      const faseAnterior = faseAnteriorRef.current
      faseAnteriorRef.current = fase

      if (fase === 'acceso') {
        ambienteRef.current?.resume()
        finalizadoRef.current = false
        return
      }

      if (fase === 'datos') {
        ambienteRef.current?.resume()
        finalizadoRef.current = false

        // Esta ruta ocurre al reintentar mientras la salida estaba activa. La
        // reversión del contexto quita la timeline anterior y estos valores
        // dejan explícitamente restaurada la splash.
        if (faseAnterior === 'listo') {
          gsap.set(raiz, { autoAlpha: 1 })
          gsap.set(fondo, { autoAlpha: 1, clipPath: 'inset(0% 0% 0% 0%)' })
          gsap.set(marca, { autoAlpha: 1, y: 0, scale: 1 })
          gsap.set(isotipo, {
            autoAlpha: 1,
            x: 0,
            y: 0,
            scale: 1,
            rotation: 0,
            borderRadius: 24,
          })
          gsap.set(lockup, { autoAlpha: 1, x: 0 })
          gsap.set(logo, { clipPath: 'inset(0%)', scale: 1 })
          gsap.set(chispa, { autoAlpha: 0 })
          gsap.set(brilloLogo, { xPercent: -180 })
          gsap.set(estado, { autoAlpha: 1, y: 0 })
        }

        gsap.to(progreso, {
          scaleX: 0.9,
          duration: reducido ? 0 : 0.9,
          ease: 'power1.inOut',
          overwrite: 'auto',
        })
        if (!reducido) {
          gsap.fromTo(
            estado,
            { autoAlpha: 0.72, y: 4 },
            { autoAlpha: 1, y: 0, duration: 0.28, ease: 'power2.out' },
          )
        }
        return
      }

      const finalizar = () => {
        if (faseActualRef.current !== 'listo' || finalizadoRef.current) return
        finalizadoRef.current = true
        onFinalizar?.()
      }

      // El wipe y el viaje ya concentran el trabajo de composición. Congelar
      // las auroras y el brillo conserva su estado visual, evita un salto y
      // libera recursos mientras termina la transición principal.
      ambienteRef.current?.pause()

      // El mínimo visible es mayor que la intro, pero completar antes de matar
      // evita estados parciales incluso en una pestaña ralentizada.
      entradaRef.current?.progress(1).kill()
      entradaRef.current = null
      salidaRef.current?.kill()
      salidaRef.current = null

      gsap.set(raiz, { autoAlpha: 1 })
      gsap.set(fondo, { autoAlpha: 1, clipPath: 'inset(0% 0% 0% 0%)' })
      gsap.set(marca, { autoAlpha: 1, y: 0, scale: 1 })
      gsap.set(isotipo, {
        autoAlpha: 1,
        x: 0,
        y: 0,
        scale: 1,
        rotation: 0,
        borderRadius: 24,
      })
      gsap.set(lockup, { autoAlpha: 1, x: 0 })
      gsap.set(logo, { clipPath: 'inset(0%)', scale: 1 })
      gsap.set(chispa, { autoAlpha: 0 })
      gsap.set(estado, { autoAlpha: 1, y: 0 })
      gsap.set(progreso, { scaleX: 0.9, transformOrigin: 'left center' })

      if (reducido) {
        // Opacidad y no autoAlpha: visibility:hidden sacaría la live region
        // del árbol de accesibilidad en el mismo frame en que React pinta
        // «Tu espacio está listo», y el anuncio podría perderse. El velo
        // transparente no intercepta clics y el desmontaje limpia el nodo.
        gsap.set(raiz, { opacity: 0, pointerEvents: 'none' })
        finalizar()
        return
      }

      // Medición ÚNICA a propósito: un resize/rotación durante los ~0.9 s de
      // salida aterriza el isotipo desviado hasta que su fade lo cubre.
      // Transitorio, se autocorrige al desmontar; re-medir en vivo no paga.
      const destino = document.querySelector<HTMLElement>('[data-splash-destino]')
      const origenRect = isotipo.getBoundingClientRect()
      const destinoRect = destino?.getBoundingClientRect()
      const viaje = calcularViajeSplash(
        origenRect,
        destinoRect,
        destino?.dataset.splashDestinoVisible === 'true',
      )

      const timeline = gsap.timeline({
        defaults: { ease: 'avance-splash' },
        onComplete: finalizar,
      })
      salidaRef.current = timeline
      timeline
        .to(progreso, { scaleX: 1, duration: 0.22, ease: 'power2.out' })
        .addLabel('despejar', '+=0.05')
        // Opacidad y no autoAlpha: el mensaje final debe seguir en el árbol
        // de accesibilidad mientras el lector de pantalla lo anuncia.
        .to(estado, { opacity: 0, y: -4, duration: 0.2 }, 'despejar')
        .to(lockup, { autoAlpha: 0, x: -8, duration: 0.2 }, 'despejar')

      if (viaje) {
        timeline
          .addLabel('revelar', 'despejar+=0.16')
          .to(
            fondo,
            {
              clipPath: 'inset(0% 100% 0% 0%)',
              duration: 0.78,
              ease: 'power3.inOut',
            },
            'revelar',
          )
          .to(
            isotipo,
            {
              x: viaje.x,
              y: viaje.y,
              scale: viaje.scale,
              borderRadius: 10,
              duration: 0.72,
            },
            'revelar',
          )
          .to(
            isotipo,
            { autoAlpha: 0, duration: 0.14, ease: 'power1.out' },
            'revelar+=0.56',
          )
          .to(raiz, { autoAlpha: 0, duration: 0.08 }, 'revelar+=0.7')
      } else {
        // Menú colapsado y móvil: no existe un logo visible al cual viajar.
        // Primero desaparece por completo el isotipo y recién entonces se abre
        // el fondo. Así nunca queda flotando sobre el CRM en el centro.
        timeline
          .to(
            isotipo,
            {
              autoAlpha: 0,
              y: -8,
              scale: 0.72,
              duration: 0.24,
              ease: 'power2.in',
            },
            'despejar+=0.02',
          )
          .addLabel('revelar', 'despejar+=0.26')
          .to(
            fondo,
            {
              clipPath: 'inset(0% 100% 0% 0%)',
              duration: 0.52,
              ease: 'power3.inOut',
            },
            'revelar',
          )
          .to(raiz, { autoAlpha: 0, duration: 0.06 }, 'revelar+=0.46')
      }

      return () => {
        if (salidaRef.current === timeline) salidaRef.current = null
      }
    },
    {
      scope: raizRef,
      dependencies: [fase, onFinalizar, reducido],
      revertOnUpdate: true,
    },
  )

  // Sin aria-busy en el contenedor: un ancestro busy autoriza a los AT a
  // retener los anuncios de la live region que vive dentro, y el estado de
  // carga ya lo comunica el role="status".
  return (
    <div ref={raizRef} className="ac-splash" data-fase={fase}>
      <div className="ac-splash__fondo" aria-hidden>
        <div className="ac-splash__aurora ac-splash__aurora--uno" />
        <div className="ac-splash__aurora ac-splash__aurora--dos" />
        <div className="ac-splash__reticula" />
      </div>

      <div className="ac-splash__marca">
        <div ref={isotipoRef} className="ac-splash__isotipo" aria-hidden>
          <img className="ac-splash__logo" src="/brand/avance-icon.png" alt="" />
          <i className="ac-splash__chispa" />
          <span className="ac-splash__brillo-logo" />
        </div>

        <div className="ac-splash__lockup" aria-hidden>
          <div className="ac-splash__nombre">
            Avance <span>Corp</span>
          </div>
          <div className="ac-splash__subtitulo">CRM Comercial</div>
        </div>
      </div>

      <div className="ac-splash__estado">
        {/* La región viva abarca SOLO el mensaje de fase: con el bloque entero
            como región atómica, cada transición re-anunciaba también la barra
            y el texto legal. */}
        <p role="status">{MENSAJES[fase]}</p>
        <div className="ac-splash__progreso" aria-hidden>
          <span className="ac-splash__progreso-carga">
            <i className="ac-splash__progreso-brillo" />
          </span>
        </div>
        <small>Tu información se mantiene protegida</small>
      </div>
    </div>
  )
}
