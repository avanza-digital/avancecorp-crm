import { useEffect, useState } from 'react'

/**
 * Cuenta ascendente sobre la parte numérica de un valor, preservando prefijos
 * y sufijos (S/, US$, %, k). Respeta prefers-reduced-motion.
 * Ej: "S/ 127,000" → anima 0 → 127000 manteniendo "S/ " y separadores.
 */
export function AnimatedValue({ value, duration = 700 }: { value: string; duration?: number }) {
  const [display, setDisplay] = useState({ value, text: value })

  useEffect(() => {
    const m = value.match(/-?[\d.,]+/)
    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    if (reduced || !m || !Number.isFinite(duration) || duration <= 0) {
      setDisplay({ value, text: value })
      return
    }
    const target = Number(m[0].replace(/,/g, ''))
    if (!Number.isFinite(target)) {
      setDisplay({ value, text: value })
      return
    }
    const decimals = (m[0].split('.')[1] ?? '').length
    let start: number | undefined
    let raf: number | undefined
    let active = true

    const tick = (now: number) => {
      if (!active) return
      // El timestamp del RAF puede preceder a performance.now() cuando el
      // efecto arranca en ese mismo frame. Ambos extremos usan el reloj del
      // RAF: la animación nunca invierte el signo del dato por tiempo negativo.
      start ??= now
      const t = Math.max(0, Math.min(1, (now - start) / duration))
      if (t === 1) {
        setDisplay({ value, text: value }) // el formato final sigue siendo el recibido
        return
      }
      const eased = 1 - Math.pow(1 - t, 3) // easeOutCubic
      const cur = target * eased
      const shown = cur.toLocaleString('es-PE', {
        minimumFractionDigits: decimals,
        maximumFractionDigits: decimals,
      })
      setDisplay({ value, text: value.replace(/-?[\d.,]+/, shown) })
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => {
      active = false
      if (raf !== undefined) cancelAnimationFrame(raf)
    }
  }, [value, duration])

  // Al cambiar filtro/unidad no se muestra el texto del valor anterior ni
  // siquiera antes de que el efecto nuevo reciba su primer fotograma.
  return <>{display.value === value ? display.text : value}</>
}
