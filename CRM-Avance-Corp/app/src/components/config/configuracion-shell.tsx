import type { ReactNode } from 'react'
import { ArrowLeft, Eye, type LucideIcon } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { SectionHead } from '@/components/common/section-head'
import { hashDe } from '@/lib/router'

export interface EstadoVigencia {
  etiqueta: string
  detalle?: string
  color?: string
}

/** Marco común de los cuatro módulos del panel de gobierno comercial. */
export function ConfiguracionShell({
  icono,
  titulo,
  descripcion,
  estado,
  soloLectura,
  acciones,
  children,
  volverA = 'config',
}: {
  icono: LucideIcon
  titulo: string
  descripcion: string
  estado?: EstadoVigencia | undefined
  soloLectura: boolean
  acciones?: ReactNode | undefined
  children: ReactNode
  volverA?: 'config' | 'config-usuarios'
}) {
  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <a
        href={hashDe(volverA)}
        className="inline-flex items-center gap-1.5 rounded-md px-1 py-1 text-xs font-semibold text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
      >
        <ArrowLeft className="size-4" aria-hidden /> {volverA === 'config' ? 'Configuración' : 'Usuarios y roles'}
      </a>

      <Card>
        <SectionHead
          icon={icono}
          title={titulo}
          right={
            estado ? (
              <Badge color={estado.color ?? 'var(--accent)'} variant="outline">
                {estado.etiqueta}
              </Badge>
            ) : undefined
          }
        />
        <CardContent className="flex flex-col gap-4 pt-0 sm:flex-row sm:items-end sm:justify-between">
          <div className="min-w-0">
            <p className="max-w-3xl text-xs leading-relaxed text-muted-foreground">
              {descripcion}
            </p>
            {estado?.detalle && (
              <p className="mt-2 text-[11px] font-medium text-foreground/70">{estado.detalle}</p>
            )}
          </div>
          {acciones && <div className="flex shrink-0 flex-wrap gap-2">{acciones}</div>}
        </CardContent>
      </Card>

      {soloLectura && (
        <div className="flex items-center gap-2.5 rounded-xl bg-warning/10 px-4 py-3 text-warning ring-1 ring-warning/20">
          <Eye className="size-4 shrink-0" aria-hidden />
          <p className="text-xs font-semibold">
            Solo lectura: puedes auditar esta configuración, pero no modificarla.
          </p>
        </div>
      )}

      {children}
    </div>
  )
}
