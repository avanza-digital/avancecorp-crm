// Preview de LEAD al pasar el mouse sobre su nombre (Cartera, cola de "Hoy", …).
// Lógica comercial: el analista/supervisor dimensiona el lead —etapa, CAPITAL,
// teléfono— sin abrir el drawer; el click sigue abriendo la ficha completa.
// Reusa lo de la casa: silueta por género, money, semáforo de etapa, badges.
// Compacta y anclada DEBAJO del nombre (no lejos, no enorme).
import type { ReactNode } from 'react'
import { HoverCard, HoverCardContent, HoverCardTrigger } from '@/components/ui/hover-card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { money, fmtFecha } from '@/lib/format'
import { CAT_LABEL, ETAPA_INFO, MOTIVOS_DESCARTE, origenLabel, type Lead } from '@/lib/tipos'

function Fila({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="shrink-0 text-[11px] font-semibold text-muted-foreground">{label}</dt>
      <dd className="min-w-0 truncate text-[11px] font-medium text-foreground">{children}</dd>
    </div>
  )
}

export function LeadHoverCard({ lead, children }: { lead: Lead; children: ReactNode }) {
  const info = ETAPA_INFO[lead.etapa]
  const motivo = MOTIVOS_DESCARTE.find((m) => m.k === lead.motivo_descarte)?.label

  return (
    <HoverCard>
      <HoverCardTrigger>{children}</HoverCardTrigger>
      <HoverCardContent side="bottom" align="start" sideOffset={6} className="w-64 border-border-strong bg-secondary p-2.5">
        {/* Identidad + capital (arriba a la derecha, prominente pero compacto) */}
        <div className="flex items-center gap-2">
          <Avatar nombre={lead.nombre_completo} genero={lead.genero ?? null} className="size-8" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[13px] font-bold leading-tight">{lead.nombre_completo}</p>
            <Badge color={info.color} dot className="mt-1 text-[10px]">
              {info.label}
            </Badge>
          </div>
          {lead.monto_estimado != null && (
            <div className="shrink-0 text-right leading-tight">
              <p className="text-sm font-extrabold tabular-nums text-primary">
                {money(lead.monto_estimado, lead.moneda)}
              </p>
              <p className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">
                {lead.etapa === 'convertido' ? 'ganado' : 'en proceso'}
              </p>
            </div>
          )}
        </div>

        {/* Datos compactos */}
        <dl className="mt-2 space-y-1 border-t border-border/60 pt-2">
          <Fila label="Teléfono">
            <span className="tabular-nums">{lead.telefono}</span>
          </Fila>
          <Fila label="Origen">{origenLabel(lead.origen)}</Fila>
          {lead.categoria_interes && <Fila label="Interés">{CAT_LABEL[lead.categoria_interes]}</Fila>}
          <Fila label="Creado">{fmtFecha(lead.creado_en)}</Fila>
          {lead.etapa === 'descartado' && motivo && <Fila label="Descarte">{motivo}</Fila>}
        </dl>
      </HoverCardContent>
    </HoverCard>
  )
}
