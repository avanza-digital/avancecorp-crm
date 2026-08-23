// Franja «Hoy, tres cosas» (F3, 2026-08-23) — el puesto de mando del
// supervisor: el sistema absorbe la priorización del día (ley de Tesler) y
// aquí solo llegan DECISIONES, cada una con su acción al lado.
//
// Navy a propósito: es la voz de autoridad/estructura del presupuesto de
// color, no una alarma — los puntos de severidad (rojo/ámbar) son la única
// señal cromática dentro. Sin cosas, la franja NO se pinta: el silencio
// también es información.
import type { JSX } from 'react'
import { SEMAFORO_SOBRE_NAVY } from '@/lib/semaforo'
import { hashDe } from '@/lib/router'
import type { CosaDeHoy, PestanaColaDestino } from '@/lib/tres-cosas'

const COLOR_SEV: Record<CosaDeHoy['severidad'], string> = {
  critica: SEMAFORO_SOBRE_NAVY.critico,
  atencion: SEMAFORO_SOBRE_NAVY.atencion,
}

// La severidad TAMBIÉN en texto (regla de la casa: el color nunca va solo).
// Sin esto, un lector de pantalla oía «3 nuevos sin responder — Ver» sin
// saber si era el rojo de HOY o el ámbar de la semana (a11y F3, A1).
const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = {
  critica: 'urgente hoy',
  atencion: 'esta semana',
}

// Chip entero clicable (Fitts): texto + acción en UN solo objetivo cómodo.
const CLASE_CHIP =
  'flex min-h-9 cursor-pointer items-center gap-2 rounded-lg border border-white/15 bg-white/10 px-3 py-1.5 text-left text-xs font-semibold text-white transition-colors hover:bg-white/20 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-white/60'

function ContenidoCosa({ cosa }: { cosa: CosaDeHoy }): JSX.Element {
  return (
    <>
      <span
        className="size-2 shrink-0 rounded-full"
        style={{ background: COLOR_SEV[cosa.severidad] }}
        aria-hidden
      />
      <span className="min-w-0">{cosa.texto}</span>
      <span className="shrink-0 font-extrabold text-[#9cc0ff]">{cosa.accion} →</span>
    </>
  )
}

export function TresCosas({
  cosas,
  onIrAPestana,
}: {
  cosas: readonly CosaDeHoy[]
  /** Salta a una pestaña de la Cola del equipo (y le lleva el foco). */
  onIrAPestana: (pestana: PestanaColaDestino) => void
}): JSX.Element | null {
  if (cosas.length === 0) return null
  return (
    <section
      aria-label="Hoy, tres cosas"
      className="flex flex-wrap items-center gap-2 rounded-xl bg-primary px-4 py-3"
    >
      <h2 className="mr-1 text-[10px] font-bold uppercase tracking-[0.12em] text-white/60">
        Hoy, tres cosas
      </h2>
      {cosas.map((cosa) => {
        // Capturado ANTES del callback: el narrowing del discriminante no
        // sobrevive dentro del onClick.
        const destino = cosa.destino
        return destino.tipo === 'vista' ? (
          <a
            key={cosa.id}
            href={hashDe(destino.vista)}
            aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto} — ${cosa.accion}`}
            className={CLASE_CHIP}
          >
            <ContenidoCosa cosa={cosa} />
          </a>
        ) : (
          <button
            key={cosa.id}
            type="button"
            onClick={() => onIrAPestana(destino.pestana)}
            aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto} — ${cosa.accion}`}
            className={CLASE_CHIP}
          >
            <ContenidoCosa cosa={cosa} />
          </button>
        )
      })}
    </section>
  )
}
