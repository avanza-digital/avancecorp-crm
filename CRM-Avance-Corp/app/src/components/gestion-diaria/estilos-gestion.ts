// Escala del diseño de Gestión Diaria (27/09/2026) compartida por supervisor y
// gerencia: controles compactos que crecen a 44 px en pantallas táctiles.
export const CONTROL = 'h-9 text-[13px] pointer-coarse:h-11'
export const BOTON_CABECERA = 'inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50 aria-disabled:hover:bg-card pointer-coarse:h-11'
export const BOTON_ICONO = 'grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] text-[var(--muted-foreground-strong)] transition-colors hover:bg-muted hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:size-11'
export const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
/** La ficha protagonista (Miguel, 27/09): borde azul, sombra y cabecera teñida. */
export const FICHA = 'flex min-h-0 min-w-0 flex-1 flex-col overflow-clip rounded-2xl border border-accent/30 bg-card shadow-[0_14px_34px_-18px_rgba(17,30,61,0.35)]'
export const CABECERA_FICHA = 'flex shrink-0 items-center gap-3.5 border-b border-accent/15 bg-accent/[0.06] px-5 py-4'
export const TITULO_FICHA = 'rounded-md text-[22px] font-extrabold leading-tight tracking-[-0.015em] text-primary [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
/** Pastilla de filtro con número (la cifra ES el filtro). */
export const PILDORA = 'inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-full border px-3 text-[13px] font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11'
export const PILDORA_ACTIVA = 'border-accent bg-accent text-accent-foreground'
export const PILDORA_INACTIVA = 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary'
