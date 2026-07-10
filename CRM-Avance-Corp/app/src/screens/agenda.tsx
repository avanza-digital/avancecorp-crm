import { useMemo } from 'react'
import { CalendarDays, Users, Phone, AlertTriangle, Clock, NotebookPen } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { AGENDA_DEMO } from '@/lib/demo'
import { useStore } from '@/lib/store'
import { useAuth } from '@/lib/auth'
import { puedeEscribir } from '@/lib/roles'
import { cn } from '@/lib/utils'

type Evento = (typeof AGENDA_DEMO)[number]

// Labels es-PE de los tipos de evento (con tilde — capitalizar la clave daría "Reunion").
const TIPO_EVENTO: Record<string, string> = { reunion: 'Reunión', llamada: 'Llamada', vencimiento: 'Vencimiento' }

// ── Mini-KPIs del día (derivados de los eventos del ámbito) ───────────────────
function statsDe(eventos: Evento[]): StatChipData[] {
  const nBy = (t: string) => eventos.filter((a) => a.tipo === t).length
  return [
    { icon: CalendarDays, label: 'Eventos', value: String(eventos.length), tone: 'primary', sub: 'esta semana' },
    { icon: Users, label: 'Reuniones', value: String(nBy('reunion')), tone: 'accent' },
    { icon: Phone, label: 'Llamadas', value: String(nBy('llamada')), tone: 'accent' },
    { icon: AlertTriangle, label: 'Vencimientos', value: String(nBy('vencimiento')), tone: 'warn' },
  ]
}

// ── Agrupa por etiqueta de día (parte antes de ' · '), preservando orden ──────
function agruparPorDia(eventos: Evento[]): { dia: string; eventos: Evento[] }[] {
  const out: { dia: string; eventos: Evento[] }[] = []
  for (const ev of eventos) {
    const dia = ev.cuando.split(' · ')[0]
    const g = out.find((x) => x.dia === dia)
    if (g) g.eventos.push(ev)
    else out.push({ dia, eventos: [ev] })
  }
  return out
}

// ── Tira decorativa de la semana actual (Lun→Dom), resaltando "hoy" ───────────
const DOW = ['L', 'M', 'M', 'J', 'V', 'S', 'D']
const SEMANA = (() => {
  const now = new Date()
  const hoyIdx = (now.getDay() + 6) % 7 // 0 = lunes
  const lunes = new Date(now)
  lunes.setDate(now.getDate() - hoyIdx)
  return DOW.map((d, i) => {
    const f = new Date(lunes)
    f.setDate(lunes.getDate() + i)
    return { d, num: f.getDate(), hoy: i === hoyIdx }
  })
})()

export function Agenda() {
  const { abrirLead, ambito } = useStore()
  const { yo } = useAuth()
  const escribe = puedeEscribir(yo?.rol)

  // Ámbito (espejo RLS F1c): la agenda solo muestra eventos de leads que el
  // rol puede ver — un vendedor NO ve reuniones de leads ajenos.
  const eventos = useMemo(() => {
    const ids = new Set(ambito.leads.map((l) => l.id))
    return AGENDA_DEMO.filter((ev) => ids.has(ev.lead_id))
  }, [ambito.leads])
  const stats = useMemo(() => statsDe(eventos), [eventos])
  const grupos = useMemo(() => agruparPorDia(eventos), [eventos])

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Mini-KPIs */}
      <StatStrip stats={stats} />

      {/* Tira decorativa: la semana en curso, con "hoy" resaltado */}
      <Card className="ac-pop p-2.5">
        <div className="flex items-stretch gap-1.5">
          {SEMANA.map((c, i) => (
            <div
              key={i}
              className={cn(
                'flex flex-1 flex-col items-center gap-0.5 rounded-lg py-2 transition-colors',
                c.hoy
                  ? 'bg-accent text-accent-foreground shadow-[var(--shadow-card)]'
                  : 'text-muted-foreground hover:bg-muted/60',
              )}
            >
              <span className="text-[10px] font-bold uppercase">{c.d}</span>
              <span className={cn('text-sm font-extrabold tabular-nums', c.hoy ? 'text-accent-foreground' : 'text-foreground')}>
                {c.num}
              </span>
            </div>
          ))}
        </div>
      </Card>

      {/* Vacío: el ámbito del rol no tiene eventos esta semana */}
      {grupos.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center gap-1.5 py-10 text-center">
            <CalendarDays className="size-8 text-muted-foreground/50" />
            <p className="text-sm font-semibold text-foreground">Sin eventos en tu agenda</p>
            <p className="max-w-md text-xs text-muted-foreground">
              Aquí solo aparecen reuniones, llamadas y vencimientos de los leads de tu ámbito.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Timeline agrupado por día */}
      {grupos.map((g) => (
        <Card key={g.dia}>
          <SectionHead
            icon={CalendarDays}
            title={g.dia}
            right={<Badge color="var(--accent)">{g.eventos.length} {g.eventos.length === 1 ? 'evento' : 'eventos'}</Badge>}
          />
          <CardContent className="space-y-1 pt-0">
            {g.eventos.map((ev) => {
              const hora = ev.cuando.split(' · ')[1] ?? ''
              return (
                <div
                  key={ev.id}
                  role="button"
                  tabIndex={0}
                  aria-label={`Abrir ficha — ${ev.titulo}`}
                  onClick={() => abrirLead(ev.lead_id)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault()
                      abrirLead(ev.lead_id)
                    }
                  }}
                  className="group flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                >
                  <span className="w-1 self-stretch rounded" style={{ background: ev.color, minHeight: 44 }} />
                  <div className="min-w-0 flex-1 leading-tight">
                    <p className="truncate text-sm font-semibold">{ev.titulo}</p>
                    <div className="mt-1.5">
                      <Badge color={ev.color} className="text-[10px]">{TIPO_EVENTO[ev.tipo] ?? ev.tipo}</Badge>
                    </div>
                  </div>
                  {escribe && (
                    <Button
                      variant="ghost"
                      size="xs"
                      className="shrink-0 text-muted-foreground hover:text-foreground"
                      aria-label={`Registrar actividad — ${ev.titulo}`}
                      onClick={(e) => {
                        e.stopPropagation()
                        abrirLead(ev.lead_id)
                      }}
                    >
                      <NotebookPen className="size-3.5" />
                      <span className="hidden sm:inline">Registrar actividad</span>
                    </Button>
                  )}
                  {hora && (
                    <span className="flex shrink-0 items-center gap-1.5 text-xs font-semibold tabular-nums text-muted-foreground">
                      <Clock className="size-3.5" />{hora}
                    </span>
                  )}
                </div>
              )
            })}
          </CardContent>
        </Card>
      ))}

      <p className="text-[11px] text-muted-foreground">
        Demo — el calendario completo (Mes/Semana/Día con overlays de SLA y vencimientos de
        propuesta/contrato) se construye en F2 sobre el patrón de VITANOVA.
      </p>
    </div>
  )
}
