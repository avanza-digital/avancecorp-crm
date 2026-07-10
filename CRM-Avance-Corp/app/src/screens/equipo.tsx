// screens/equipo.tsx — Inteligencia de EQUIPO por rango (F1c).
// Solo la ven supervisor/gerencia/directorio (App.tsx guarda la ruta):
//  - Supervisor: cards de SUS vendedores (métricas + semáforo de actividad),
//    bandeja "Por repartir" con acción de asignar y mini-cola del equipo.
//  - Gerencia: un bloque por supervisor (comparativaEquipos como cabecera)
//    con las cards de sus vendedores dentro; también puede repartir.
//  - Directorio: la misma radiografía que gerencia, SOLO LECTURA (cero
//    botones de acción).
// Los números salen del ámbito jerárquico (useCRMData().ambito) + lib/inteligencia.
// Semáforos SIN verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626
// crítico · convertido = navy #111e3d.
import { useState, type JSX } from 'react'
import { Activity, Inbox, ListTodo, ShieldCheck, Users, Wallet } from 'lucide-react'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { moneyK } from '@/lib/format'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { origenLabel, type Lead, type Miembro } from '@/lib/tipos'
import {
  capitalPorMoneda,
  colaDe,
  comparativaEquipos,
  diasDesdeReferencia,
  esAbierto,
  metricasPorVendedor,
  type ItemCola,
  type MetricasVendedor,
} from '@/lib/inteligencia'

// ── Paleta de semáforos y helpers ─────────────────────────────────────────────

const GRIS = '#8b95a7' // neutro (sin señal) — no forma parte del semáforo central

const SEV_UI: Record<ItemCola['sev'], { label: string; color: string }> = {
  critica: { label: 'Crítica', color: SEV_COLOR.critica },
  media: { label: 'Media', color: SEV_COLOR.media },
  baja: { label: 'Baja', color: SEV_COLOR.baja },
}

/** Semáforo de última actividad: azul <2 d · ámbar 2–5 d · rojo >5 d. */
function semaforoActividad(dias: number): { color: string; label: string } {
  const label = dias < 1 ? 'Al día' : `${Math.floor(dias)} d sin act.`
  if (dias < 2) return { color: SEMAFORO.ok, label }
  if (dias <= 5) return { color: SEMAFORO.atencion, label }
  return { color: SEMAFORO.critico, label }
}

// OJO: wording propio de esta pantalla ('hace N d' compacto) — NO es el
// haceTexto central ('hace N días'), no sustituir sin cambiar el texto visible.
const haceDiasTxt = (d: number) => (d < 1 ? 'hace horas' : `hace ${Math.floor(d)} d`)

// ── Card de vendedor (métricas del ámbito) ────────────────────────────────────

function VendedorCard({ r, delay = 0 }: { r: MetricasVendedor; delay?: number }): JSX.Element {
  const sem = semaforoActividad(r.diasSinActividadMax)
  return (
    <Card className="ac-lift ac-pop p-4" style={{ animationDelay: `${delay}ms` }}>
      {/* Identidad + semáforo de última actividad (peor lead abierto) */}
      <div className="flex items-center gap-3">
        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
          <p className="text-[11px] text-muted-foreground">
            {r.convertidos} {r.convertidos === 1 ? 'convertido' : 'convertidos'}
          </p>
        </div>
        {r.activos === 0 ? (
          <Badge color={GRIS} variant="outline">Sin abiertos</Badge>
        ) : (
          <Badge
            color={sem.color}
            variant="outline"
            dot
            title="Última actividad del lead abierto más abandonado"
          >
            {sem.label}
          </Badge>
        )}
      </div>

      {/* Números clave — capital PEN y USD SIEMPRE por separado */}
      <div className="mt-3 grid grid-cols-3 gap-2">
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Activos</p>
          <p className="text-base font-extrabold tabular-nums">{r.activos}</p>
        </div>
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Capital (PEN)</p>
          <p className="text-base font-extrabold tabular-nums">{moneyK(r.capitalPEN)}</p>
          {r.capitalUSD > 0 && (
            <p className="text-[10px] tabular-nums text-muted-foreground">+{moneyK(r.capitalUSD, 'USD')}</p>
          )}
        </div>
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Sin tocar</p>
          <p
            className="text-base font-extrabold tabular-nums"
            style={r.sinTocar > 0 ? { color: SEMAFORO.atencion } : undefined}
            title="Leads abiertos sin ninguna actividad registrada"
          >
            {r.sinTocar}
          </p>
        </div>
      </div>

      {/* Conversión (convertidos / total de sus leads) — navy, sin verde */}
      <div className="mt-3">
        <div className="mb-1 flex items-center justify-between text-[11px]">
          <span className="font-semibold text-muted-foreground">Conversión</span>
          <span className="font-bold tabular-nums">{r.conversion}%</span>
        </div>
        <Progress value={r.conversion} color={SEMAFORO.navy} />
      </div>
    </Card>
  )
}

// ── Bandeja "Por repartir" (asignar → reasignar del store) ────────────────────

interface GrupoVendedores {
  sup: Miembro
  vs: Miembro[]
}

function Bandeja({
  parkeados,
  vendedores,
  grupos,
  mostrarBandeja = false,
  ahora,
}: {
  parkeados: Lead[]
  vendedores: Miembro[] // opciones planas (supervisor: SUS vendedores)
  grupos?: GrupoVendedores[] // opciones agrupadas por equipo (gerencia)
  mostrarBandeja?: boolean // gerencia: mostrar en qué bandeja está el lead
  ahora: number // reloj vivo del padre (useAhora) — antigüedad de los parkeados
}): JSX.Element {
  const { equipo, reasignar } = useCRMData()
  const [sel, setSel] = useState<Record<string, string>>({})

  const bandejaDe = (l: Lead) =>
    equipo.find((m) => m.perfil_id === l.asignado_supervisor_id)?.nombre_completo ?? 'Sin bandeja'

  const asignar = (lead: Lead) => {
    const vid = sel[lead.id]
    if (!vid) return
    const v = (grupos ? grupos.flatMap((g) => g.vs) : vendedores).find((m) => m.perfil_id === vid)
    const r = reasignar(lead.id, vid)
    if (r.ok) {
      toast.success(`${lead.nombre_completo} asignado a ${v?.nombre_completo ?? 'vendedor'}`)
    } else if (r.error && !r.error.startsWith('Sin permiso')) {
      // Los errores de permiso ya los toastea el store (doble defensa).
      toast.error(r.error)
    }
  }

  if (parkeados.length === 0) {
    return (
      <p className="px-5 pb-4 text-sm text-muted-foreground">
        No hay leads por repartir — bandeja limpia.
      </p>
    )
  }

  return (
    <div className="space-y-2 px-5 pb-4">
      {parkeados.map((l) => {
        const d = diasDesdeReferencia(l.creado_en, ahora)
        return (
          <div
            key={l.id}
            className="flex flex-col gap-2.5 rounded-xl border border-border p-3 sm:flex-row sm:items-center"
          >
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">{l.nombre_completo}</p>
              <p className="truncate text-[11px] text-muted-foreground">
                {origenLabel(l.origen)}
                {' · '}
                {l.monto_estimado != null ? moneyK(l.monto_estimado, l.moneda) : 'Sin monto'}
                {' · entró '}
                <span style={d >= 1 ? { color: SEMAFORO.critico, fontWeight: 700 } : undefined}>{haceDiasTxt(d)}</span>
                {mostrarBandeja && <> · Bandeja: {bandejaDe(l)}</>}
              </p>
            </div>
            <div className="flex items-center gap-2 sm:w-[290px] sm:shrink-0">
              <Select
                value={sel[l.id] ?? ''}
                onChange={(e) => setSel((s) => ({ ...s, [l.id]: e.target.value }))}
                aria-label={`Asignar vendedor a ${l.nombre_completo}`}
              >
                <option value="">Asignar a…</option>
                {grupos
                  ? grupos.map((g) => (
                      <optgroup key={g.sup.perfil_id} label={`Equipo de ${g.sup.nombre_completo}`}>
                        {g.vs.map((v) => (
                          <option key={v.perfil_id} value={v.perfil_id}>{v.nombre_completo}</option>
                        ))}
                      </optgroup>
                    ))
                  : vendedores.map((v) => (
                      <option key={v.perfil_id} value={v.perfil_id}>{v.nombre_completo}</option>
                    ))}
              </Select>
              <Button size="sm" disabled={!sel[l.id]} onClick={() => asignar(l)}>
                Asignar
              </Button>
            </div>
          </div>
        )
      })}
    </div>
  )
}

// ── Mini-cola del equipo (top N de colaDe con nombre del vendedor) ────────────

function MiniCola({ items, max = 5 }: { items: ItemCola[]; max?: number }): JSX.Element {
  const { abrirLead } = usePanelesActions()

  if (items.length === 0) {
    return (
      <p className="px-5 pb-4 text-sm text-muted-foreground">
        Sin pendientes en la cola del equipo — todo al día.
      </p>
    )
  }

  const top = items.slice(0, max)
  return (
    <div className="space-y-1.5 px-5 pb-4">
      {top.map((it) => {
        const sev = SEV_UI[it.sev]
        return (
          <button
            key={it.lead.id}
            type="button"
            onClick={() => abrirLead(it.lead.id)}
            title="Abrir la ficha del lead"
            className="flex w-full cursor-pointer items-center gap-2.5 rounded-xl border border-border p-2.5 text-left transition-colors hover:bg-muted/60"
          >
            <span className="size-2 shrink-0 rounded-full" style={{ background: sev.color }} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">
                {it.lead.nombre_completo}
                <span className="font-normal text-muted-foreground">
                  {' · '}
                  {it.lead.vendedor_nombre ?? 'Por repartir'}
                </span>
              </p>
              <p className="truncate text-[11px] text-muted-foreground">{it.motivo}</p>
            </div>
            <Badge color={sev.color} variant="outline">{sev.label}</Badge>
          </button>
        )
      })}
      {items.length > max && (
        <p className="pt-1 text-[11px] text-muted-foreground">
          +{items.length - max} pendientes más en la cola del equipo.
        </p>
      )}
    </div>
  )
}

// ── Vista SUPERVISOR — su equipo, su bandeja, su cola ─────────────────────────

function EquipoSupervisor(): JSX.Element {
  const { ambito, actividades } = useCRMData()
  const ahora = useAhora() // reloj vivo: los "d sin act." refrescan solos

  const filas = metricasPorVendedor(ambito.vendedores, ambito.leads, actividades, ahora)
  const parkeados = ambito.leads.filter((l) => esAbierto(l) && l.vendedor_id == null)
  const cola = colaDe(ambito.leads, actividades, ahora)

  // Totales sobre el ámbito completo con vendedor (incluye leads asignados al
  // PROPIO supervisor) — misma base que Hoy·Supervisor; los parkeados no suman.
  const abiertosAsignados = ambito.leads.filter((l) => esAbierto(l) && l.vendedor_id != null)
  const { pen: capPEN, usd: capUSD } = capitalPorMoneda(abiertosAsignados)
  const activos = abiertosAsignados.length

  const stats: StatChipData[] = [
    { icon: Users, label: 'Mis vendedores', value: String(ambito.vendedores.length), tone: 'accent' },
    {
      icon: Wallet,
      label: 'Capital en proceso (PEN)',
      value: moneyK(capPEN),
      tone: 'primary',
      sub: capUSD > 0 ? `+${moneyK(capUSD, 'USD')} aparte` : 'Solo soles',
    },
    { icon: Activity, label: 'Leads activos', value: String(activos), sub: `${cola.length} en cola de acción` },
    {
      icon: Inbox,
      label: 'Por repartir',
      value: String(parkeados.length),
      tone: parkeados.length > 0 ? 'warn' : 'default',
      sub: 'Bandeja del equipo',
    },
  ]

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      {/* Cards de MIS vendedores (orden: capital captado PEN desc) */}
      <Card>
        <SectionHead
          icon={Users}
          title="Mi equipo"
          right={<span className="text-xs text-muted-foreground">Orden: capital en proceso (PEN)</span>}
        />
        <CardContent className="pt-0">
          {filas.length === 0 ? (
            <p className="text-sm text-muted-foreground">No tienes vendedores a cargo todavía.</p>
          ) : (
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {filas.map((r, i) => (
                <VendedorCard key={r.m.perfil_id} r={r} delay={i * 60} />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Bandeja de parkeados + mini-cola del equipo */}
      <div className="grid gap-5 lg:grid-cols-2">
        <Card>
          <SectionHead
            icon={Inbox}
            title="Por repartir"
            right={
              parkeados.length > 0 ? (
                <Badge color={SEMAFORO.atencion} variant="outline" dot>
                  {parkeados.length} en bandeja
                </Badge>
              ) : undefined
            }
          />
          <Bandeja parkeados={parkeados} vendedores={ambito.vendedores} ahora={ahora} />
        </Card>
        <Card>
          <SectionHead
            icon={ListTodo}
            title="Cola del equipo"
            right={<span className="text-xs text-muted-foreground">Top 5 por urgencia</span>}
          />
          <MiniCola items={cola} />
        </Card>
      </div>

      <p className="text-[11px] text-muted-foreground">
        Los números corresponden solo a tu equipo — cada rol ve únicamente lo que le corresponde.
      </p>
    </div>
  )
}

// ── Vista GERENCIA / DIRECTORIO — bloques por supervisor ──────────────────────

function EquipoEmpresa({ conAcciones }: { conAcciones: boolean }): JSX.Element {
  const { ambito, actividades, equipo } = useCRMData()
  const ahora = useAhora() // reloj vivo: los "d sin act." refrescan solos

  const filas = comparativaEquipos(equipo, ambito.leads, actividades)
  const parkeados = ambito.leads.filter((l) => esAbierto(l) && l.vendedor_id == null)

  const vendedoresDe = (sup: Miembro) =>
    equipo.filter((m) => m.rol_crm === 'vendedor' && m.activo && m.supervisor_id === sup.perfil_id)

  const capPEN = filas.reduce((a, f) => a + f.capitalPEN, 0)
  const capUSD = filas.reduce((a, f) => a + f.capitalUSD, 0)
  const activos = filas.reduce((a, f) => a + f.activos, 0)
  const convertidos = filas.reduce((a, f) => a + f.convertidos, 0)

  const stats: StatChipData[] = [
    {
      icon: ShieldCheck,
      label: 'Equipos',
      value: String(filas.length),
      tone: 'accent',
      sub: `${ambito.vendedores.length} vendedores en total`,
    },
    {
      icon: Wallet,
      label: 'Capital en proceso (PEN)',
      value: moneyK(capPEN),
      tone: 'primary',
      sub: capUSD > 0 ? `+${moneyK(capUSD, 'USD')} aparte` : 'Solo soles',
    },
    { icon: Activity, label: 'Leads activos', value: String(activos), sub: `${convertidos} convertidos` },
    {
      icon: Inbox,
      label: 'Por repartir',
      value: String(parkeados.length),
      tone: parkeados.length > 0 ? 'warn' : 'default',
      sub: 'En bandejas de supervisores',
    },
  ]

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      {!conAcciones && (
        <p className="text-[11px] text-muted-foreground">
          Vista de auditoría del Directorio — solo lectura, sin acciones de gestión.
        </p>
      )}

      {/* Un bloque por supervisor: cabecera comparativa + cards de sus vendedores */}
      {filas.map((f) => {
        const cards = metricasPorVendedor(vendedoresDe(f.supervisor), ambito.leads, actividades, ahora)
        return (
          <Card key={f.supervisor.perfil_id}>
            <SectionHead
              icon={ShieldCheck}
              title={`Equipo de ${f.supervisor.nombre_completo}`}
              right={
                <Badge color={SEMAFORO.violeta}>
                  {f.vendedores} {f.vendedores === 1 ? 'vendedor' : 'vendedores'}
                </Badge>
              }
            />
            <CardContent className="space-y-4 pt-0">
              {/* Cabecera del bloque — comparativaEquipos (PEN y USD separados) */}
              <div className="grid grid-cols-2 gap-3 rounded-xl border border-border bg-primary/[0.03] p-3 sm:grid-cols-4">
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Capital (PEN)</p>
                  <p className="text-base font-extrabold tabular-nums">{moneyK(f.capitalPEN)}</p>
                  {f.capitalUSD > 0 && (
                    <p className="text-[10px] tabular-nums text-muted-foreground">+{moneyK(f.capitalUSD, 'USD')}</p>
                  )}
                </div>
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Activos</p>
                  <p className="text-base font-extrabold tabular-nums">{f.activos}</p>
                </div>
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Conversión</p>
                  <p className="text-base font-extrabold tabular-nums">{f.conversion}%</p>
                  <Progress value={f.conversion} color={SEMAFORO.navy} className="mt-1.5 h-1.5" />
                </div>
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Por repartir</p>
                  <p
                    className="text-base font-extrabold tabular-nums"
                    style={f.parkeados > 0 ? { color: SEMAFORO.atencion } : undefined}
                  >
                    {f.parkeados}
                  </p>
                </div>
              </div>

              {cards.length === 0 ? (
                <p className="text-sm text-muted-foreground">Sin vendedores asignados a este equipo.</p>
              ) : (
                <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                  {cards.map((r, i) => (
                    <VendedorCard key={r.m.perfil_id} r={r} delay={i * 60} />
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        )
      })}

      {/* Bandeja global — SOLO gerencia (directorio no acciona nada) */}
      {conAcciones && (
        <Card>
          <SectionHead
            icon={Inbox}
            title="Por repartir (toda la empresa)"
            right={
              parkeados.length > 0 ? (
                <Badge color={SEMAFORO.atencion} variant="outline" dot>
                  {parkeados.length} en bandejas
                </Badge>
              ) : undefined
            }
          />
          <Bandeja
            parkeados={parkeados}
            vendedores={ambito.vendedores}
            grupos={filas
              .map((f) => ({ sup: f.supervisor, vs: vendedoresDe(f.supervisor) }))
              .filter((g) => g.vs.length > 0)}
            mostrarBandeja
            ahora={ahora}
          />
        </Card>
      )}

      <p className="text-[11px] text-muted-foreground">
        Los números abarcan toda la operación comercial de la empresa.
      </p>
    </div>
  )
}

// ── Wrapper por rol ───────────────────────────────────────────────────────────

export function Equipo(): JSX.Element {
  const { yo } = useAuth()
  switch (yo?.rol) {
    case 'gerencia':
      return <EquipoEmpresa conAcciones />
    case 'directorio':
      // Directorio = solo lectura total: misma radiografía, cero acciones.
      return <EquipoEmpresa conAcciones={false} />
    case 'supervisor':
    default:
      // App.tsx guarda la ruta; un rol raro degrada a la vista de supervisor,
      // cuyo ámbito en el store es el de privilegio mínimo (solo lo propio).
      return <EquipoSupervisor />
  }
}
