// Pantalla AGENDA (Fase C del plan v2) — la vista de planificación sobre las
// MISMAS tareas de crm.tareas que alimentan HOY (una sola fuente de verdad).
//
// Dos pestañas, no cuatro vistas: [Hoy] = el día operable (vencidas + hoy, la
// cola real de trabajo) y [Todo] = panorama agrupado por día. Las vistas
// Semana/Mes llegan en Fase D — antes de panorama bonito, operación.
//
// La TARJETA es operable (no un calendario decorativo): abrir ficha,
// hover-card, capital en juego, llamar/WhatsApp (AccionesContacto), cerrar
// con resultado (motor Fase B), reprogramar rápido +1d/+3d/+1sem, y el
// anti no-show de Fase E: recordatorio wa.me que PIDE confirmación + chip
// Confirmada/Sin confirmar en reuniones.
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import {
  AlertTriangle,
  BellRing,
  CalendarClock,
  CalendarDays,
  CircleCheckBig,
  ExternalLink,
  Phone,
  ShieldCheck,
  Users,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { puedeEscribir } from '@/lib/roles'
import { enlaceGoogleCalendar, esDeHoy, tareaAEvento } from '@/lib/agenda-derivada'
import { ameritaRecordatorio, enlaceRecordatorio } from '@/lib/recordatorio'
import { AccionesContacto } from '@/components/app/contacto'
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import { money } from '@/lib/format'
import { TIPO_EVENTO, type Lead, type Tarea } from '@/lib/tipos'
import { cn } from '@/lib/utils'

// ── Mini-KPIs del día ─────────────────────────────────────────────────────────
function statsDe(tareas: Tarea[], ahora: number): StatChipData[] {
  const eventos = tareas.map((t) => tareaAEvento(t, ahora))
  const nBy = (t: string) => eventos.filter((a) => a.tipo === t).length
  return [
    { icon: CalendarDays, label: 'Pendientes', value: String(eventos.length), tone: 'primary', sub: 'en tu agenda' },
    { icon: Users, label: 'Reuniones', value: String(nBy('reunion')), tone: 'accent' },
    { icon: Phone, label: 'Llamadas', value: String(nBy('llamada')), tone: 'accent' },
    { icon: AlertTriangle, label: 'Vencidas', value: String(eventos.filter((a) => a.vencida).length), tone: 'warn' },
  ]
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

/** Reprogramar rápido: los 3 saltos del plan (posponer sin formulario). */
const SALTOS: ReadonlyArray<{ label: string; dias: number }> = [
  { label: '+1d', dias: 1 },
  { label: '+3d', dias: 3 },
  { label: '+1sem', dias: 7 },
]

function TarjetaTarea({
  t,
  lead,
  ahora,
  escribe,
  abrirLead,
  onCerrar,
}: {
  t: Tarea
  lead: Lead | undefined
  ahora: number
  escribe: boolean
  abrirLead: (id: string) => void
  onCerrar: (t: Tarea) => void
}) {
  const { reprogramarTarea, confirmarTarea } = useCRMData()
  const { yo } = useAuth()
  const ev = tareaAEvento(t, ahora)
  const hora = ev.cuando.split(' · ')[1] ?? ''
  const gcal = enlaceGoogleCalendar(t)
  const recordatorio = lead && ameritaRecordatorio(t, ahora) ? enlaceRecordatorio(t, lead, ahora) : null

  const posponer = (dias: number) => {
    const res = reprogramarTarea(t.id, new Date(Date.parse(t.vence_en) + dias * 86_400_000).toISOString())
    if (res.ok) toast.success(`Reprogramada ${dias === 7 ? '+1 semana' : `+${dias} día${dias > 1 ? 's' : ''}`}${yo?.demo ? ' (demo)' : ''}`)
    else toast.error(res.error ?? 'No se pudo reprogramar')
  }

  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${t.titulo}`}
      onClick={() => t.lead_id && abrirLead(t.lead_id)}
      onKeyDown={(e) => {
        if ((e.key === 'Enter' || e.key === ' ') && t.lead_id) {
          e.preventDefault()
          abrirLead(t.lead_id)
        }
      }}
      className="group flex cursor-pointer flex-wrap items-center gap-x-3 gap-y-1.5 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <span className="w-1 self-stretch rounded" style={{ background: ev.color, minHeight: 44 }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          {lead ? (
            <LeadHoverCard lead={lead}>
              <p className="truncate text-sm font-semibold">{t.titulo}</p>
            </LeadHoverCard>
          ) : (
            <p className="truncate text-sm font-semibold">{t.titulo}</p>
          )}
          <Badge color={ev.color} className="text-[10px]">{TIPO_EVENTO[t.tipo] ?? t.tipo}</Badge>
          {t.tipo === 'reunion' && !ev.vencida && (
            t.confirmada_en ? (
              <Badge color="#16a34a" className="text-[10px]">
                <ShieldCheck className="size-3" aria-hidden /> Confirmada
              </Badge>
            ) : (
              <Badge color="#d97706" className="text-[10px]">Sin confirmar</Badge>
            )
          )}
          {t.reprogramaciones > 0 && (
            <span className="text-[10px] font-medium text-muted-foreground">
              movida ×{t.reprogramaciones}
            </span>
          )}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5">
          {lead?.monto_estimado != null && (
            <span className="text-[11px] font-semibold tabular-nums text-muted-foreground">
              {money(lead.monto_estimado, lead.moneda)} en juego
            </span>
          )}
          {escribe && (
            <span className="hidden items-center gap-1 sm:flex">
              {SALTOS.map((s) => (
                <button
                  key={s.label}
                  type="button"
                  title={`Reprogramar ${s.label}`}
                  className="cursor-pointer rounded-md px-1.5 py-0.5 text-[10px] font-bold text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                  onClick={(e) => {
                    e.stopPropagation()
                    posponer(s.dias)
                  }}
                >
                  <CalendarClock className="mr-0.5 inline size-3" aria-hidden />{s.label}
                </button>
              ))}
            </span>
          )}
        </div>
      </div>

      {/* Acciones de canal + anti no-show + cierre — cortan la propagación */}
      <span className="flex shrink-0 items-center gap-1">
        {recordatorio && escribe && (
          <a
            href={recordatorio}
            target="_blank"
            rel="noreferrer"
            title="Recordar por WhatsApp (pide confirmación y menciona el capital)"
            aria-label={`Recordar cita — ${t.titulo}`}
            onClick={(e) => e.stopPropagation()}
            className="grid size-8 place-items-center rounded-lg text-[#16a34a] transition-colors hover:bg-[#16a34a]/10"
          >
            <BellRing className="size-4" aria-hidden />
          </a>
        )}
        {t.tipo === 'reunion' && !t.confirmada_en && !ev.vencida && escribe && (
          <button
            type="button"
            title="El cliente confirmó la cita"
            aria-label={`Marcar confirmada — ${t.titulo}`}
            className="grid size-8 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            onClick={(e) => {
              e.stopPropagation()
              const res = confirmarTarea(t.id)
              if (res.ok) toast.success(`Cita confirmada${yo?.demo ? ' (demo)' : ''}`)
              else toast.error(res.error ?? 'No se pudo confirmar')
            }}
          >
            <ShieldCheck className="size-4" aria-hidden />
          </button>
        )}
        {gcal && (
          <a
            href={gcal}
            target="_blank"
            rel="noreferrer"
            title="Añadir a Google Calendar"
            aria-label={`Añadir a Google Calendar — ${t.titulo}`}
            onClick={(e) => e.stopPropagation()}
            className="grid size-8 place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <ExternalLink className="size-4" aria-hidden />
          </a>
        )}
        {lead && <AccionesContacto lead={lead} compacto soloIcono />}
        {escribe && (
          <button
            type="button"
            title="Cerrar tarea (resultado + siguiente)"
            aria-label={`Cerrar tarea — ${t.titulo}`}
            className="grid size-8 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground"
            onClick={(e) => {
              e.stopPropagation()
              onCerrar(t)
            }}
          >
            <CircleCheckBig className="size-4" aria-hidden />
          </button>
        )}
      </span>

      <span
        className={cn(
          'shrink-0 text-xs font-semibold tabular-nums',
          ev.vencida ? 'text-[#d97706]' : 'text-muted-foreground',
        )}
      >
        {ev.vencida ? ev.cuando : hora || ev.cuando}
      </span>
    </div>
  )
}

export function Agenda() {
  const { ambito, tareas } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  const ahora = useAhora()
  const escribe = puedeEscribir(yo?.rol)
  const [vista, setVista] = useState<'hoy' | 'todo'>('hoy')
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)

  // Ámbito (espejo RLS): solo tareas de leads que el rol puede ver.
  const idsAmbito = useMemo(() => new Set(ambito.leads.map((l) => l.id)), [ambito.leads])
  const leadPorId = (id: string | null): Lead | undefined =>
    id ? ambito.leads.find((l) => l.id === id) : undefined

  const pendientes = useMemo(
    () =>
      tareas
        .filter((t) => t.estado === 'pendiente' && t.activo && t.lead_id && idsAmbito.has(t.lead_id))
        .sort((a, b) => a.vence_en.localeCompare(b.vence_en)),
    [tareas, idsAmbito],
  )
  const stats = useMemo(() => statsDe(pendientes, ahora), [pendientes, ahora])

  // [Hoy] = vencidas + las de hoy (el día operable); [Todo] = panorama por día.
  const delDia = useMemo(
    () => pendientes.filter((t) => {
      const ev = tareaAEvento(t, ahora)
      return ev.vencida || esDeHoy(ev, ahora)
    }),
    [pendientes, ahora],
  )
  const visibles = vista === 'hoy' ? delDia : pendientes
  const grupos = useMemo(() => {
    const out: { dia: string; items: Tarea[] }[] = []
    for (const t of visibles) {
      const dia = tareaAEvento(t, ahora).cuando.split(' · ')[0] ?? 'Sin fecha'
      const g = out.find((x) => x.dia === dia)
      if (g) g.items.push(t)
      else out.push({ dia, items: [t] })
    }
    return out
  }, [visibles, ahora])

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
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

      {/* Selector Hoy / Todo */}
      <div className="flex items-center gap-1.5">
        {(
          [
            { k: 'hoy', label: `Hoy${delDia.length > 0 ? ` · ${delDia.length}` : ''}` },
            { k: 'todo', label: `Todo · ${pendientes.length}` },
          ] as const
        ).map((v) => (
          <button
            key={v.k}
            type="button"
            aria-pressed={vista === v.k}
            onClick={() => setVista(v.k)}
            className={cn(
              'cursor-pointer rounded-full px-3 py-1.5 text-xs font-bold transition-colors',
              vista === v.k ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground',
            )}
          >
            {v.label}
          </button>
        ))}
      </div>

      {/* Vacío accionable */}
      {grupos.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center gap-1.5 py-10 text-center">
            <CalendarDays className="size-8 text-muted-foreground/50" />
            <p className="text-sm font-semibold text-foreground">
              {vista === 'hoy' ? 'Nada pendiente para hoy' : 'Sin tareas pendientes en tu agenda'}
            </p>
            <p className="max-w-md text-xs text-muted-foreground">
              Agenda la próxima acción desde la ficha de un lead — ningún lead activo debería quedarse sin una.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Timeline agrupado por día — tarjetas OPERABLES */}
      {grupos.map((g) => (
        <Card key={g.dia}>
          <SectionHead
            icon={g.dia === 'Vencida' ? AlertTriangle : CalendarDays}
            title={g.dia === 'Vencida' ? 'Vencidas' : g.dia}
            right={
              <Badge color={g.dia === 'Vencida' ? '#d97706' : 'var(--accent)'}>
                {g.items.length} {g.items.length === 1 ? 'tarea' : 'tareas'}
              </Badge>
            }
          />
          <CardContent className="space-y-1 pt-0">
            {g.items.map((t) => (
              <TarjetaTarea
                key={t.id}
                t={t}
                lead={leadPorId(t.lead_id)}
                ahora={ahora}
                escribe={escribe}
                abrirLead={abrirLead}
                onCerrar={setTareaACerrar}
              />
            ))}
          </CardContent>
        </Card>
      ))}

      <p className="text-[11px] text-muted-foreground">
        Muy pronto: vistas por semana y mes. La agenda ya es real: cerrar una tarea registra el resultado en el
        timeline y te propone la siguiente; “Recordar” manda un WhatsApp que pide confirmación de la cita.
      </p>

      <CerrarTareaDialog tarea={tareaACerrar} onCerrar={() => setTareaACerrar(null)} />
    </div>
  )
}