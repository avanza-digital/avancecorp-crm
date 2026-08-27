"use client"

import * as React from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"

import { cn } from "@/lib/utils"

const useIsoLayoutEffect =
  typeof window !== "undefined" ? React.useLayoutEffect : React.useEffect

export interface CoverflowSlide {
  src: string
  alt: string
  title?: string
  subtitle?: string
  meta?: { label: string; value: string }[]
}

export interface CoverflowCarouselProps {
  slides: CoverflowSlide[]
  /** Degrees the first neighbour tilts. */
  rotate?: number
  /** How far the first neighbour recedes, as a fraction of card width. */
  depth?: number
  /** Viewer distance as a multiple of card width — smaller is a wider lens. */
  perspective?: number
  /** Exponent on distance. Below 1 the rake eases off as cards travel out. */
  falloff?: number
  /** Opacity lost per step from the centre. */
  fade?: number
  /** Any CSS length. Everything else is derived from it, so the rake scales. */
  cardWidth?: string
  /** Space between cards, as a fraction of card width. */
  gap?: number
  loop?: boolean
  showCaption?: boolean
  showPagination?: boolean
  showNavigation?: boolean
  /** Use contain for logos and cover for photography. */
  imageFit?: "cover" | "contain"
  /** Names the carousel for assistive tech. */
  label?: string
  className?: string
  cardClassName?: string
  imageClassName?: string
  onSelectedChange?: (index: number, slide: CoverflowSlide) => void
  onSlideClick?: (index: number, slide: CoverflowSlide) => void
}

export function CoverflowCarousel({
  slides,
  rotate = 44,
  depth = 0.6,
  perspective = 3,
  falloff = 0.56,
  fade = 0.1,
  cardWidth = "clamp(148px, 22vw, 260px)",
  gap = 0.05,
  loop = true,
  showCaption = false,
  showPagination = false,
  showNavigation = false,
  imageFit = "cover",
  label = "Carrusel",
  className,
  cardClassName,
  imageClassName,
  onSelectedChange,
  onSlideClick,
}: CoverflowCarouselProps) {
  const count = slides.length

  const frameRef = React.useRef<HTMLDivElement>(null)
  const cardRefs = React.useRef<(HTMLDivElement | null)[]>([])
  /** Fractional card index at the centre. The single source of truth. */
  const posRef = React.useRef(0)
  /** Where the current settle is headed. */
  const targetRef = React.useRef(0)
  const widthRef = React.useRef(0)
  const rafRef = React.useRef<number | null>(null)
  const dragRef = React.useRef<{
    id: number
    x: number
    pos: number
    v: number
    t: number
  } | null>(null)
  const draggedRef = React.useRef(false)

  const [selected, setSelected] = React.useState(0)

  /** Nearest whole card, folded back into 0..count-1. */
  const indexAt = React.useCallback(
    (pos: number) => {
      if (count === 0) return 0
      return ((Math.round(pos) % count) + count) % count
    },
    [count],
  )

  const publishSelected = React.useCallback(
    (index: number) => {
      const slide = slides[index]
      if (!slide) return
      setSelected(index)
      onSelectedChange?.(index, slide)
    },
    [onSelectedChange, slides],
  )

  // Paint straight to the DOM. React only needs the selected whole index.
  const paint = React.useCallback(() => {
    const width = widthRef.current
    if (!width || count === 0) return
    const pitch = width * (1 + gap)
    const pos = posRef.current

    cardRefs.current.forEach((card, index) => {
      if (!card) return

      // Fold the distance into the shorter way round the ring. This creates
      // the loop without cloned cards or DOM shuffling.
      let offset = index - pos
      if (loop) {
        offset = ((offset % count) + count) % count
        if (offset > count / 2) offset -= count
      }

      const distance = Math.abs(offset)
      const ramp = Math.pow(distance, falloff)
      const tilt = Math.min(rotate * ramp, 82) * Math.sign(offset)

      card.style.transform =
        `translateX(calc(-50% + ${offset * pitch}px)) ` +
        `translateZ(${-depth * width * ramp}px) rotateY(${-tilt}deg)`

      // Hide a card before it teleports across the far side of a looping ring.
      const edge = loop ? Math.min(1, Math.max(0, count / 2 - distance)) : 1
      card.style.opacity = String(Math.max(0, 1 - fade * distance) * edge)
      card.style.zIndex = String(100 - Math.round(distance))
      card.setAttribute("aria-hidden", String(index !== indexAt(pos)))
    })
  }, [count, depth, fade, falloff, gap, indexAt, loop, rotate])

  const settle = React.useCallback(
    (target: number) => {
      if (count === 0) return
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
      targetRef.current = target
      publishSelected(indexAt(target))

      const reducedMotion = window.matchMedia(
        "(prefers-reduced-motion: reduce)",
      ).matches
      if (reducedMotion) {
        posRef.current = target
        paint()
        rafRef.current = null
        return
      }

      const step = () => {
        const remaining = target - posRef.current
        if (Math.abs(remaining) < 0.0004) {
          posRef.current = target
          paint()
          rafRef.current = null
          return
        }
        posRef.current += remaining * 0.16
        paint()
        rafRef.current = requestAnimationFrame(step)
      }
      rafRef.current = requestAnimationFrame(step)
    },
    [count, indexAt, paint, publishSelected],
  )

  const clamp = React.useCallback(
    (pos: number) =>
      loop || count === 0 ? pos : Math.max(0, Math.min(count - 1, pos)),
    [count, loop],
  )

  const goTo = React.useCallback(
    (index: number) => {
      if (count === 0) return
      const target = loop
        ? index + Math.round((targetRef.current - index) / count) * count
        : index
      settle(clamp(target))
    },
    [clamp, count, loop, settle],
  )

  const nudge = React.useCallback(
    (by: number) => settle(clamp(Math.round(targetRef.current) + by)),
    [clamp, settle],
  )

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (count === 0) return
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    event.currentTarget.setPointerCapture(event.pointerId)
    targetRef.current = posRef.current
    draggedRef.current = false
    dragRef.current = {
      id: event.pointerId,
      x: event.clientX,
      pos: posRef.current,
      v: 0,
      t: performance.now(),
    }
  }

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.id !== event.pointerId) return

    const pitch = widthRef.current * (1 + gap)
    if (!pitch) return

    const delta = event.clientX - drag.x
    if (Math.abs(delta) > 5) draggedRef.current = true

    const now = performance.now()
    const previous = posRef.current
    posRef.current = clamp(drag.pos - delta / pitch)
    drag.v = ((posRef.current - previous) / Math.max(now - drag.t, 1)) * 1000
    drag.t = now

    const index = indexAt(posRef.current)
    if (index !== selected) publishSelected(index)
    paint()
  }

  const endDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.id !== event.pointerId) return
    dragRef.current = null
    const carried = Math.max(-2, Math.min(2, drag.v * 0.18))
    settle(clamp(Math.round(posRef.current + carried)))
  }

  useIsoLayoutEffect(() => {
    const frame = frameRef.current
    if (!frame || count === 0) return

    const measure = () => {
      const card = cardRefs.current[0]
      if (!card) return
      widthRef.current = card.offsetWidth
      paint()
    }

    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(frame)
    return () => observer.disconnect()
  }, [count, paint])

  React.useEffect(() => {
    if (count === 0) {
      setSelected(0)
      posRef.current = 0
      targetRef.current = 0
      return
    }
    const next = Math.min(selected, count - 1)
    posRef.current = next
    targetRef.current = next
    publishSelected(next)
    requestAnimationFrame(paint)
  }, [count, paint, publishSelected, selected])

  React.useEffect(
    () => () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
    },
    [],
  )

  const active = slides[selected]

  return (
    <div
      className={cn("w-full", className)}
      style={{ ["--cf-card" as string]: cardWidth }}
      role="region"
      aria-roledescription="carousel"
      aria-label={label}
    >
      <div className="relative">
        <div
          ref={frameRef}
          tabIndex={0}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={endDrag}
          onPointerCancel={endDrag}
          onKeyDown={(event) => {
            if (event.key === "ArrowLeft") {
              event.preventDefault()
              nudge(-1)
            } else if (event.key === "ArrowRight") {
              event.preventDefault()
              nudge(1)
            }
          }}
          className="cursor-grab overflow-hidden py-10 outline-none ring-ring focus-visible:ring-2 active:cursor-grabbing"
          style={{
            perspective: `calc(var(--cf-card) * ${perspective})`,
            touchAction: "pan-y",
          }}
        >
          <div
            className="relative select-none"
            style={{
              height: "var(--cf-card)",
              transformStyle: "preserve-3d",
            }}
          >
            {slides.map((slide, index) => (
              <div
                key={slide.src}
                ref={(node) => {
                  cardRefs.current[index] = node
                }}
                role="group"
                aria-roledescription="slide"
                aria-label={`${index + 1} de ${count}`}
                className={cn(
                  "absolute left-1/2 top-0 aspect-square overflow-hidden rounded-2xl bg-muted shadow-xl will-change-transform",
                  onSlideClick &&
                    "cursor-pointer ring-ring focus-visible:ring-2",
                  cardClassName,
                )}
                style={{ width: "var(--cf-card)" }}
                onClick={() => {
                  if (draggedRef.current) {
                    draggedRef.current = false
                    return
                  }
                  const currentSlide = slides[index]
                  if (currentSlide) onSlideClick?.(index, currentSlide)
                }}
              >
                {/* The portal is static-hosted; regular img keeps this primitive framework-neutral. */}
                <img
                  src={slide.src}
                  alt={slide.alt}
                  draggable={false}
                  className={cn(
                    "h-full w-full select-none",
                    imageFit === "contain" ? "object-contain p-6" : "object-cover",
                    imageClassName,
                  )}
                />
              </div>
            ))}
          </div>
        </div>

        {showNavigation && count > 1 && (
          <>
            <button
              type="button"
              aria-label="Aliado anterior"
              onClick={() => nudge(-1)}
              className="absolute left-3 top-1/2 z-[200] grid size-11 -translate-y-1/2 place-items-center rounded-full border border-border bg-background/85 text-foreground shadow-sm backdrop-blur transition hover:bg-background"
            >
              <ChevronLeft className="size-5" />
            </button>
            <button
              type="button"
              aria-label="Aliado siguiente"
              onClick={() => nudge(1)}
              className="absolute right-3 top-1/2 z-[200] grid size-11 -translate-y-1/2 place-items-center rounded-full border border-border bg-background/85 text-foreground shadow-sm backdrop-blur transition hover:bg-background"
            >
              <ChevronRight className="size-5" />
            </button>
          </>
        )}
      </div>

      {showCaption && active?.title && (
        <div
          key={selected}
          className="ac-rise mt-2 flex flex-col items-center px-6 text-center"
          aria-live="polite"
        >
          <p className="text-[15px] font-semibold tracking-tight text-foreground">
            {active.title}
          </p>
          {active.subtitle && (
            <p className="mt-1 text-[13px] text-muted-foreground">
              {active.subtitle}
            </p>
          )}
          {active.meta && active.meta.length > 0 && (
            <dl className="mt-5 w-full max-w-[260px] text-[12px]">
              {active.meta.map((row) => (
                <div
                  key={row.label}
                  className="flex justify-between gap-5 border-b border-border/60 py-[6px] last:border-0"
                >
                  <dt className="text-muted-foreground">{row.label}</dt>
                  <dd className="text-right font-medium text-foreground">
                    {row.value}
                  </dd>
                </div>
              ))}
            </dl>
          )}
        </div>
      )}

      {showPagination && count > 1 && (
        <div className="mt-3 flex items-center justify-center">
          {slides.map((slide, index) => (
            <button
              key={slide.src}
              type="button"
              aria-label={`Ir al aliado ${index + 1}`}
              aria-current={index === selected}
              onClick={() => goTo(index)}
              className="grid size-11 place-items-center rounded-full ring-ring focus-visible:ring-2"
            >
              <span
                className={cn(
                  "block h-2 rounded-full bg-foreground transition-all",
                  index === selected ? "w-5 opacity-100" : "w-2 opacity-30",
                )}
              />
            </button>
          ))}
        </div>
      )}

      {count === 0 && (
        <p className="py-10 text-center text-sm text-muted-foreground">
          No hay aliados para mostrar.
        </p>
      )}
    </div>
  )
}
