// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
// ya trae: sus leads + los de sus vendedores + parkeados de SU bandeja.
// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
import { useMemo, useState, type JSX } from 'react'
import { toast } from 'sonner'
import {
  AlarmClock,
  AlertTriangle,
  ChevronRight,
  Inbox,
  ListChecks,
  Target,
  UserPlus,
  Users,
  UsersRound,
  Wallet,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Progress } from '@/components/ui/progress'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { AccionesContacto } from '@/components/app/contacto'
import {
  BUCKET_LABEL,
  capitalPorMoneda,
  colaDe,
  colorMeta,
  conversionGlobal,
  diasSinActividad,
  estancados,
  haceTexto,
  indexarUltimaActividad,
  metricasPorVendedor,
} from '@/lib/inteligencia'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { money, moneyK } from '@/lib/format'
import { ETAPA_INFO, origenLabel, type Lead } from '@/lib/tipos'

/** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
function semaforoDias(d: number): string {
  if (d > 5) return SEMAFORO.critico
  if (d >= 2) return SEMAFORO.atencion
  return SEMAFORO.ok
}

export function HoySupervisor(): JSX.Element {
  const { ambito, actividades, reasignar, objetivos } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  // Reloj vivo: tick por minuto y al volver a la pestaña — dependencia del memo
  // para que cola/ranking/alertas SLA se refresquen solos al pasar el tiempo.
  const ahora = useAhora()
  // Vendedor elegido en el select de cada lead parkeado (leadId → perfil_id).
  const [sel, setSel] = useState<Record<string, string>>({})

  const d = useMemo(() => {
    const abiertos = ambito.leads.filter(
      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado',
    )
    const parkeados = abiertos.filter((l) => l.vendedor_id == null)
    const asignados = abiertos.filter((l) => l.vendedor_id != null)
    // Capital en proceso del EQUIPO: solo abiertos CON vendedor. Los parkeados
    // no suman (nadie los trabaja aún) y PEN/USD jamás se mezclan en un total.
    const { pen: capitalPEN, usd: capitalUSD } = capitalPorMoneda(asignados)
    // Índice de última actividad compartido: se calcula UNA vez y se reutiliza
    // en cola/ranking/alertas (y en la bandeja) en lugar de reindexar por llamada.
    const indice = indexarUltimaActividad(actividades)
    const cola = colaDe(ambito.leads, actividades, ahora, indice)
    const sinTocar = cola.filter((i) => i.bucket === 'sin_responder').length
    const rank = metricasPorVendedor(ambito.vendedores, ambito.leads, actividades, ahora, indice)
    const alertas = estancados(ambito.leads, actividades, 5, ahora, indice)
    const vivos = ambito.leads.filter((l) => l.activo)
    const convertidos = vivos.filter((l) => l.etapa === 'convertido').length
    // Conversión de fuente única (lib/inteligencia): misma base que
    // comparativaEquipos — los parkeados no cuentan en el denominador.
    const conversion = conversionGlobal(ambito.leads).pct
    return { abiertos, parkeados, asignados, capitalPEN, capitalUSD, indice, cola, sinTocar, rank, alertas, convertidos, conversion }
  }, [ambito, actividades, ahora])

  const meta = objetivos.supervisor

  /** Asigna un parkeado al vendedor elegido en su select. */
  const asignar = (l: Lead) => {
    const vId = sel[l.id]
    if (!vId) return
    const res = reasignar(l.id, vId)
    if (!res.ok) {
      // Los errores de permiso ya los toastea el store (doble defensa).
      if (res.error && !res.error.startsWith('Sin permiso')) toast.error(res.error)
      return
    }
    const v = ambito.vendedores.find((m) => m.perfil_id === vId)
    toast.success(`${l.nombre_completo} asignado a ${v?.nombre_completo ?? 'vendedor'}${yo?.demo ? ' (demo)' : ''}`)
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* ── KPIs del equipo ── */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Capital en proceso del equipo"
          value={money(d.capitalPEN)}
          icon={Wallet}
          color={SEMAFORO.ok}
          sub={d.capitalUSD > 0 ? `PEN · +${moneyK(d.capitalUSD, 'USD')} aparte` : 'PEN · abiertos con vendedor'}
          delay={0}
        />
        <KpiCard
          label="Leads activos del equipo"
          value={String(d.asignados.length)}
          icon={Users}
          color={SEMAFORO.violeta}
          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'vendedor' : 'vendedores'} a cargo`}
          delay={60}
        />
        <KpiCard
          label="Nuevos sin responder"
          value={String(d.sinTocar)}
          icon={AlertTriangle}
          color={d.sinTocar > 0 ? SEMAFORO.critico : SEMAFORO.ok}
          sub={d.sinTocar > 0 ? 'Nuevos sin primer contacto — urge' : 'Todos los nuevos fueron contactados'}
          delay={120}
        />
        <KpiCard
          label="Por repartir"
          value={String(d.parkeados.length)}
          icon={Inbox}
          color={d.parkeados.length > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
          sub={d.parkeados.length > 0 ? 'En tu bandeja sin vendedor' : 'Bandeja de reparto vacía'}
          delay={180}
        />
      </div>

      {/* ── Bandeja prioritaria: parkeados por repartir ── */}
      {d.parkeados.length > 0 && (
        <Card className="overflow-hidden" style={{ borderColor: `color-mix(in srgb, ${SEMAFORO.atencion} 45%, transparent)` }}>
          <SectionHead
            icon={Inbox}
            title="Por repartir — tu bandeja"
            right={
              <Badge color={SEMAFORO.atencion} dot>
                {d.parkeados.length} {d.parkeados.length === 1 ? 'pendiente' : 'pendientes'}
              </Badge>
            }
          />
          <div className="divide-y divide-border/60 border-t border-border/60">
            {d.parkeados.map((l) => {
              const dias = diasSinActividad(l, actividades, ahora, d.indice)
              return (
                <div key={l.id} className="flex flex-wrap items-center gap-3 px-5 py-3">
                  <button
                    type="button"
                    onClick={() => abrirLead(l.id)}
                    aria-label={`Abrir ficha de ${l.nombre_completo}`}
                    className="flex min-w-0 flex-1 basis-56 cursor-pointer items-center gap-2.5 rounded-lg text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30"
                  >
                    <Avatar nombre={l.nombre_completo} color={SEMAFORO.atencion} />
                    <div className="min-w-0 leading-tight">
                      <p className="truncate text-sm font-semibold">{l.nombre_completo}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {origenLabel(l.origen)} · {l.monto_estimado != null ? money(l.monto_estimado, l.moneda) : 'sin monto'} · sin movimiento {haceTexto(dias)}
                      </p>
                    </div>
                  </button>
                  <Badge color={ETAPA_INFO[l.etapa].color} dot>
                    {ETAPA_INFO[l.etapa].label}
                  </Badge>
                  <div className="flex items-center gap-2">
                    <div className="w-[180px]">
                      <Select
                        aria-label={`Vendedor para ${l.nombre_completo}`}
                        className="h-8 text-xs"
                        value={sel[l.id] ?? ''}
                        onChange={(e) => setSel((s) => ({ ...s, [l.id]: e.target.value }))}
                      >
                        <option value="" disabled>
                          Elegir vendedor…
                        </option>
                        {ambito.vendedores.map((v) => (
                          <option key={v.perfil_id} value={v.perfil_id}>
                            {v.nombre_completo}
                          </option>
                        ))}
                      </Select>
                    </div>
                    <Button size="sm" disabled={!sel[l.id]} onClick={() => asignar(l)}>
                      <UserPlus /> Asignar
                    </Button>
                  </div>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-5">
        <div className="space-y-4 lg:col-span-3">
          {/* ── Cola del equipo (con dueño de cada item) ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={ListChecks}
              title="Cola del equipo"
              right={
                d.cola.length > 0 ? (
                  <Badge color={SEV_COLOR[d.cola[0]!.sev]} dot>
                    {d.cola.length} {d.cola.length === 1 ? 'pendiente' : 'pendientes'}
                  </Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">al día</span>
                )
              }
            />
            {d.cola.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  Sin pendientes — el equipo está al día con todos sus leads abiertos.
                </p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {/* Fila = div role="button" (no <button>: contiene los links de
                    AccionesContacto y un botón no puede anidar interactivos). */}
                {d.cola.map((i) => {
                  const abrir = () => abrirLead(i.lead.id)
                  return (
                    <div
                      key={i.lead.id}
                      role="button"
                      tabIndex={0}
                      onClick={abrir}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault()
                          abrir()
                        }
                      }}
                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
                      className="flex w-full cursor-pointer items-center gap-3 px-5 py-3 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                    >
                      <span
                        className="size-2 shrink-0 rounded-full"
                        style={{ background: SEV_COLOR[i.sev] }}
                        aria-hidden
                      />
                      <div className="min-w-0 flex-1 leading-tight">
                        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                          <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
                          <Badge color={SEV_COLOR[i.sev]}>{BUCKET_LABEL[i.bucket]}</Badge>
                        </div>
                        <p className="truncate text-xs text-muted-foreground">{i.motivo}</p>
                      </div>
                      {i.lead.monto_estimado != null && (
                        <span className="hidden shrink-0 text-xs font-extrabold tabular-nums text-primary sm:inline">
                          {moneyK(i.lead.monto_estimado, i.lead.moneda)}
                        </span>
                      )}
                      {i.lead.vendedor_nombre ? (
                        <span className="flex shrink-0 items-center gap-1.5">
                          <Avatar nombre={i.lead.vendedor_nombre} className="size-6 text-[9px]" />
                          <span className="hidden max-w-[110px] truncate text-xs text-muted-foreground md:inline">
                            {i.lead.vendedor_nombre}
                          </span>
                        </span>
                      ) : (
                        <Badge color={SEMAFORO.atencion}>sin asignar</Badge>
                      )}
                      <AccionesContacto lead={i.lead} compacto />
                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                    </div>
                  )
                })}
              </div>
            )}
          </Card>
        </div>
        <div className="space-y-4 lg:col-span-2">
          {/* ── Tu equipo hoy (semáforo por vendedor) ── */}
          <Card className="overflow-hidden">
            <SectionHead icon={UsersRound} title="Tu equipo hoy" />
            {d.rank.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">Sin vendedores a cargo.</p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {d.rank.map((r) => {
                  const c = semaforoDias(r.diasSinActividadMax)
                  return (
                    <div key={r.m.perfil_id} className="px-5 py-3">
                      <div className="flex items-center gap-2.5">
                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
                        <div className="min-w-0 flex-1 leading-tight">
                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
                          <p className="text-[11px] tabular-nums text-muted-foreground">
                            {r.activos} activos · {r.conversion}% conversión
                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
                          </p>
                        </div>
                        <div className="shrink-0 text-right leading-tight">
                          <p className="text-sm font-extrabold tabular-nums text-primary">
                            {moneyK(r.capitalPEN)}
                          </p>
                          {r.capitalUSD > 0 && (
                            <p className="text-[10.5px] tabular-nums text-muted-foreground">
                              +{moneyK(r.capitalUSD, 'USD')}
                            </p>
                          )}
                        </div>
                      </div>
                      <div className="mt-1.5 flex items-center gap-1.5 pl-[46px]">
                        <span className="size-2 shrink-0 rounded-full" style={{ background: c }} aria-hidden />
                        <span className="text-[11px] text-muted-foreground">
                          {r.activos === 0
                            ? 'Sin leads abiertos'
                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
                        </span>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </Card>

          {/* ── Meta del equipo (objetivo vs actual) ── */}
          <Card>
            <SectionHead
              icon={Target}
              title="Meta del equipo"
              right={<span className="text-xs text-muted-foreground">este mes</span>}
            />
            <CardContent className="space-y-4 pb-5 pt-0">
              {meta.capitalObjetivo <= 0 && meta.ventasObjetivo <= 0 ? (
                <>
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-xs font-semibold text-foreground/80">Capital en proceso (PEN)</span>
                    <span className="text-xs font-bold tabular-nums text-primary">{moneyK(d.capitalPEN)}</span>
                  </div>
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="text-xs font-semibold text-foreground/80">Ventas cerradas</span>
                    <span className="text-xs font-bold tabular-nums text-primary">{d.convertidos}</span>
                  </div>
                  <p className="text-[10.5px] text-muted-foreground">
                    Meta mensual del equipo por definir — cuando la establezcan, verás aquí el avance.
                  </p>
                </>
              ) : (
                <>
                  {[
                    {
                      label: 'Capital en proceso',
                      txt: `${moneyK(d.capitalPEN)} de ${moneyK(meta.capitalObjetivo)}`,
                      pct: meta.capitalObjetivo > 0 ? (d.capitalPEN / meta.capitalObjetivo) * 100 : 0,
                    },
                    {
                      label: 'Ventas cerradas',
                      txt: `${d.convertidos} de ${meta.ventasObjetivo}`,
                      pct: meta.ventasObjetivo > 0 ? (d.convertidos / meta.ventasObjetivo) * 100 : 0,
                    },
                    {
                      label: 'Conversión',
                      txt: `${d.conversion}% de ${meta.conversionObjetivo}%`,
                      pct: meta.conversionObjetivo > 0 ? (d.conversion / meta.conversionObjetivo) * 100 : 0,
                    },
                  ].map((f) => (
                    <div key={f.label}>
                      <div className="mb-1.5 flex items-baseline justify-between gap-2">
                        <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
                        <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
                      </div>
                      <Progress value={f.pct} color={colorMeta(f.pct)} />
                    </div>
                  ))}
                  <p className="text-[10.5px] text-muted-foreground">
                    Meta en PEN — lo captado en USD no entra a este total.
                  </p>
                </>
              )}
            </CardContent>
          </Card>

          {/* ── Alertas SLA (≥5 días sin actividad) ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={AlarmClock}
              title="Alertas SLA"
              right={
                d.alertas.length > 0 ? (
                  <Badge color={SEMAFORO.critico} dot>
                    {d.alertas.length}
                  </Badge>
                ) : (
                  <span className="text-xs text-muted-foreground">sin alertas</span>
                )
              }
            />
            {d.alertas.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  Ningún lead del equipo lleva 5 días o más sin actividad.
                </p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {d.alertas.map((a) => (
                  <button
                    key={a.lead.id}
                    type="button"
                    onClick={() => abrirLead(a.lead.id)}
                    aria-label={`Abrir ficha de ${a.lead.nombre_completo}`}
                    className="flex w-full cursor-pointer items-center gap-2.5 px-5 py-2.5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                  >
                    <div className="min-w-0 flex-1 leading-tight">
                      <p className="truncate text-sm font-semibold">
                        {a.lead.nombre_completo}{' '}
                        <span className="text-xs font-medium text-muted-foreground">
                          ({a.lead.vendedor_nombre ?? 'sin asignar'})
                        </span>
                      </p>
                      <p
                        className="text-[11px] font-semibold"
                        style={{ color: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
                      >
                        Sin actividad {haceTexto(a.dias)}
                      </p>
                    </div>
                    <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                  </button>
                ))}
              </div>
            )}
          </Card>
        </div>
      </div>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
      </p>
    </div>
  )
}
