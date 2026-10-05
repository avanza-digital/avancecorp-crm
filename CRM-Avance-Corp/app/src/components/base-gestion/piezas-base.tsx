// Piezas de presentación de un lead de la base que comparten la hoja del analista (F1) y su ficha (F2).
import { cn } from '@/lib/utils'
import {
  MAX_INTENTOS_BASE,
  colorEtapaMaxima,
  estadoRellamada,
  etiquetaEtapaMaxima,
  etiquetaIntentos,
  etiquetaMesLead,
  etiquetaRellamada,
  mesDelLead,
  type EtapaMaxima,
  type FilaBaseGestion,
} from '@/lib/base-gestion'

export function MesDelLead({ fila }: { fila: FilaBaseGestion }) {
  const mes = mesDelLead(fila)
  return mes ? <span>{etiquetaMesLead(mes)}</span> : <span className="text-[var(--muted-foreground-strong)]">Sin fecha</span>
}

/** F6: la base cargada de la que viene el lead («Feria 2025»); sin base, una raya tenue. */
export function BaseDelLead({ fila }: { fila: FilaBaseGestion }) {
  return fila.base_nombre ? <span>{fila.base_nombre}</span> : <span className="text-[var(--muted-foreground-strong)]">—</span>
}

export function EtapaMaximaChip({ etapa }: { etapa: EtapaMaxima }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ background: colorEtapaMaxima(etapa) }} />
      {etiquetaEtapaMaxima(etapa)}
    </span>
  )
}

export function Intentos({ n }: { n: number }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span aria-hidden className="flex gap-1">
        {Array.from({ length: MAX_INTENTOS_BASE }, (_, i) => (
          <span key={i} className={cn('size-2.5 rounded-full', i < n ? 'bg-primary' : 'bg-[var(--border-strong)]')} />
        ))}
      </span>
      <span className="tabular-nums">{etiquetaIntentos(n)}</span>
    </span>
  )
}

export function ProximaLlamada({ iso, ahora }: { iso: string | null; ahora: number }) {
  if (!iso) return <span className="text-[var(--muted-foreground-strong)]">Sin agendar</span>
  const estado = estadoRellamada(iso, ahora)
  const texto = etiquetaRellamada(iso, ahora)
  if (estado === 'futura') return <span className="font-semibold text-[var(--warning-text)]">{texto}</span>
  return (
    <span className="inline-flex rounded bg-destructive/10 px-1.5 py-0.5 font-semibold text-[var(--destructive-text)]">{texto}</span>
  )
}
