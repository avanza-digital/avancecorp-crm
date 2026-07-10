import { useEffect, useRef, useState } from 'react'

const PREFERS_REDUCED =
  typeof window !== 'undefined' &&
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

/**
 * Cuenta ascendente sobre la parte numérica de un valor, preservando prefijos
 * y sufijos (S/, US$, %, k). Respeta prefers-reduced-motion.
 * Ej: "S/ 127,000" → anima 0 → 127000 manteniendo "S/ " y separadores.
 */
export function AnimatedValue({ value, duration = 700 }: { value: string; duration?: number }) {
  const [text, setText] = useState(value)
  const raf = useRef<number | undefined>(undefined)

  useEffect(() => {
    const m = value.match(/-?[\d.,]+/)
    if (PREFERS_REDUCED || !m) {
      setText(value)
      return
    }
    const target = Number(m[0].replace(/,/g, ''))
    if (!Number.isFinite(target)) {
      setText(value)
      return
    }
    const decimals = (m[0].split('.')[1] ?? '').length
    const start = performance.now()

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3) // easeOutCubic
      const cur = target * eased
      const shown = cur.toLocaleString('es-PE', {
        minimumFractionDigits: decimals,
        maximumFractionDigits: decimals,
      })
      setText(value.replace(/-?[\d.,]+/, shown))
      if (t < 1) raf.current = requestAnimationFrame(tick)
    }
    raf.current = requestAnimationFrame(tick)
    return () => {
      if (raf.current) cancelAnimationFrame(raf.current)
    }
  }, [value, duration])

  return <>{text}</>
}
