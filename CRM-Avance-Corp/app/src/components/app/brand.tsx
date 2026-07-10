import { cn } from '@/lib/utils'

// Marca oficial de Avance Corp — SOLO se usan estos assets reales (nada inventado).
// El ícono (barras navy + flecha) vive sobre un tile BLANCO para leerse bien
// tanto en el sidebar navy como en superficies claras.
const ICON = '/brand/avance-icon.png'

/** Tile blanco con el isotipo real. Tamaño por prop (px). */
export function BrandMark({ size = 36, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn(
        'grid shrink-0 place-items-center rounded-xl bg-white ring-1 ring-black/5 shadow-sm',
        className,
      )}
      style={{ width: size, height: size }}
    >
      <img
        src={ICON}
        alt="Avance Corp"
        width={size * 0.72}
        height={size * 0.72}
        className="object-contain"
        style={{ width: size * 0.72, height: size * 0.72 }}
      />
    </span>
  )
}

/**
 * Isotipo + wordmark. `tone`:
 * - 'light' (default): texto oscuro (superficies claras)
 * - 'dark': texto blanco (paneles navy — sidebar/login)
 */
export function BrandLockup({
  size = 36,
  tone = 'light',
  subtitle = 'CRM Comercial',
  className,
}: {
  size?: number
  tone?: 'light' | 'dark'
  subtitle?: string | null
  className?: string
}) {
  const dark = tone === 'dark'
  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <BrandMark size={size} />
      <div className="leading-tight">
        <p className={cn('font-extrabold tracking-tight', dark ? 'text-white' : 'text-primary')}>
          Avance<span className={dark ? 'text-white/70' : 'text-accent'}> Corp</span>
        </p>
        {subtitle && (
          <p
            className={cn(
              'text-[10px] font-semibold uppercase tracking-[0.14em]',
              dark ? 'text-white/55' : 'text-muted-foreground',
            )}
          >
            {subtitle}
          </p>
        )}
      </div>
    </div>
  )
}
