import type { CSSProperties } from 'react'
import {
  Package, Target, Users, Clock, Settings, ChevronRight, Eye, Lock, type LucideIcon,
} from 'lucide-react'
import { Card, CardContent, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import { can, ROL_LABEL } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'

// Áreas de configuración del CRM. Hoy son marcadores de posición: cada una se
// habilita en su fase (F1–F4). El color por sección tinta el chip del ícono y su
// badge de fase (paleta navy/azul de --chart-*, SIN verde).
interface Seccion {
  icon: LucideIcon
  t: string
  d: string
  fase: string
  color: string
}
const SECCIONES: Seccion[] = [
  { icon: Package, t: 'Productos de inversión', d: 'Catálogo Nuevo / Renovación / Upgrade con montos y tasas de referencia', fase: 'Más adelante', color: 'var(--chart-1)' },
  { icon: Users, t: 'Usuarios y jerarquía', d: 'Alta de vendedores con permisos por rol y clave temporal', fase: 'Muy pronto', color: 'var(--chart-2)' },
  { icon: Clock, t: 'Tiempos y SLA', d: 'Umbral de primera respuesta y reglas por etapa', fase: 'Pronto', color: 'var(--chart-3)' },
  { icon: Target, t: 'Metas', d: 'Metas de captación por vendedor y mes', fase: 'Más adelante', color: 'var(--chart-4)' },
]

export function Config() {
  const { yo } = useAuth()
  const edita = can(yo?.rol, 'editarConfiguracion')

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Encabezado de página */}
      <Card>
        <SectionHead
          icon={Settings}
          title="Configuración del CRM"
          right={yo?.rol && <Badge color="var(--accent)" variant="outline">{ROL_LABEL[yo.rol]}</Badge>}
        />
        <CardContent className="pt-0">
          <p className="text-xs text-muted-foreground">
            Áreas de administración del sistema. Se irán habilitando por etapas;
            por ahora son un adelanto de lo que viene.
          </p>
        </CardContent>
      </Card>

      {/* Banner de modo auditoría (solo lectura) */}
      {!edita && (
        <div className="flex items-center gap-2.5 rounded-xl bg-warning/10 px-4 py-3 text-warning ring-1 ring-warning/20">
          <Eye className="size-4 shrink-0" />
          <p className="text-xs font-semibold">
            Modo auditoría: puedes ver la configuración pero no editarla.
          </p>
        </div>
      )}

      {/* Áreas de configuración */}
      <div className="grid gap-4 sm:grid-cols-2">
        {SECCIONES.map((s) => (
          <Card key={s.t} className="ac-lift">
            <CardContent className="flex items-start gap-4 p-5">
              <span
                className="ac-chip grid size-10 shrink-0 place-items-center rounded-xl"
                style={{ '--c': s.color } as CSSProperties}
              >
                <s.icon className="size-5" />
              </span>

              <div className="min-w-0 flex-1">
                <CardTitle className="text-primary">{s.t}</CardTitle>
                <CardDescription className="mt-1">{s.d}</CardDescription>

                <div className="mt-3 flex items-center justify-between gap-2">
                  <Badge color={s.color} variant="outline">Disponible {s.fase.toLowerCase()}</Badge>

                  {edita ? (
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled
                      title={`Esta sección estará disponible ${s.fase.toLowerCase()}`}
                      className="shrink-0 text-muted-foreground"
                    >
                      Abrir <ChevronRight className="size-4" />
                    </Button>
                  ) : (
                    <span
                      className="flex shrink-0 items-center gap-1.5 text-[11px] font-semibold text-muted-foreground"
                      title="Modo auditoría: solo lectura"
                    >
                      <Lock className="size-3.5" /> Solo lectura
                    </span>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
