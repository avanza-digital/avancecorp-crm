import { useRef, type JSX, type ReactNode } from 'react'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { cn } from '@/lib/utils'

gsap.registerPlugin(useGSAP)

export function GerenciaMotion({
  children,
  clave,
  className,
}: {
  children: ReactNode
  clave: string
  className?: string | undefined
}): JSX.Element {
  const alcance = useRef<HTMLDivElement>(null)

  useGSAP(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return

    const timeline = gsap.timeline({ defaults: { ease: 'power2.out' } })
    timeline
      .from('[data-gi-toolbar]', { opacity: 0, y: -8, duration: 0.28 })
      .from('[data-gi-hero]', { opacity: 0, y: 12, duration: 0.36 }, '-=0.12')
      .from(
        '[data-gi-kpi]',
        { opacity: 0, y: 14, duration: 0.32, stagger: 0.045 },
        '-=0.2',
      )
      .from(
        '[data-gi-panel]',
        { opacity: 0, y: 16, duration: 0.38, stagger: 0.055 },
        '-=0.18',
      )
  }, { scope: alcance, dependencies: [clave], revertOnUpdate: true })

  return <div ref={alcance} className={cn('gerencia-inteligencia', className)}>{children}</div>
}
