// screens/equipo.tsx — Inteligencia de EQUIPO por rango (F1c).
// Solo la ven supervisor/gerencia/directorio (App.tsx guarda la ruta):
//  - Supervisor: cards densas de SUS vendedores (métricas + semáforo de
//    actividad), bandeja "Por repartir" con acción de asignar y mini-cola.
//  - Gerencia: PRIMERO una tabla comparativa de supervisores (comparativaEquipos)
//    y el detalle por vendedor de UN equipo bajo demanda (fila/botón "Ver
//    equipo" — patrón aprobado de EquiposBajoSupervision en Hoy·Distribución:
//    "el detalle se abre solo cuando hace falta"); también puede repartir.
//  - Directorio: la misma radiografía que gerencia, SOLO LECTURA (cero
//    botones de acción).
// Los números salen del ámbito jerárquico (useCRMData().ambito) + lib/inteligencia,
// SIEMPRE sobre actividadesDelAmbito (timeline ya recortado por el store — el
// recorte lo garantiza el contrato del store, no la disciplina de esta pantalla).
// Semáforos SIN verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626
// crítico · convertido = navy #111e3d.
import { useMemo, useState, type JSX, type ReactNode } from 'react'
import { Activity, Inbox, ListTodo, ShieldCheck, Users, Wallet } from 'lucide-react'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { Select } from '@/components/ui/select'
import { PanelVacio } from '@/components/common/estado-panel'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
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
  indexarUltimaActividad,
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

const TOOLTIP_SIN_TOCAR = 'Leads abiertos sin ninguna actividad registrada'
const TOOLTIP_ULT_ACT = 'Última actividad del lead abierto más abandonado'

// ── Piezas locales compartidas por las dos vistas (sin exportar) ──────────────

/** Chip de capital en proceso: PEN protagonista, USD aparte — JAMÁS sumados. */
function chipCapitalEnProceso(pen: number, usd: number): StatChipData {
  return {
    icon: Wallet,
    label: 'Capital en proceso (PEN)',
    value: moneyK(pen),
    tone: 'primary',
    sub: usd > 0 ? `+${moneyK(usd, 'USD')} aparte` : 'Solo soles',
  }
}

/** Chip de la bandeja por repartir (ámbar mientras haya pendientes). */
function chipPorRepartir(n: number, sub: string): StatChipData {
  return {
    icon: Inbox,
    label: 'Por repartir',
    value: String(n),
    tone: n > 0 ? 'warn' : 'default',
    sub,
  }
}

/**
 * Label uppercase + número extrabold — el patrón repetido en las cards de
 * vendedor y en la cabecera comparativa de cada bloque. `denso` es la variante
 * de la card compacta (número text-sm); el `sub` (p. ej. el USD) va inline
 * para que el dato ocupe UN renglón; `children` admite la barra de conversión.
 */
function MiniDato({
  label,
  valor,
  sub,
  color,
  denso = false,
  title,
  children,
}: {
  label: string
  valor: string
  sub?: string | undefined
  color?: string | undefined
  denso?: boolean
  title?: string
  children?: ReactNode
}): JSX.Element {
  return (
    <div>
      <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">{label}</p>
      <p
        className={`${denso ? 'text-sm' : 'text-base'} font-extrabold tabular-nums`}
        style={color ? { color } : undefined}
        title={title}
      >
        {valor}
        {sub && <span className="ml-1 text-[10px] font-normal tabular-nums text-muted-foreground">{sub}</span>}
      </p>
      {children}
    </div>
  )
}

// ── Card de vendedor (vista del supervisor: ≤6 vendedores, card densa) ────────

function VendedorCard({ r, delay = 0 }: { r: MetricasVendedor; delay?: number }): JSX.Element {
  const sem = semaforoActividad(r.diasSinActividadMax)
  return (
    <Card className="ac-lift ac-pop h-full p-3" style={{ animationDelay: `${delay}ms` }}>
      {/* Identidad + semáforo de última actividad (peor lead abierto) */}
      <div className="flex items-center gap-2.5">
        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-7 text-[10px]" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] font-semibold">{r.m.nombre_completo}</p>
          <p className="text-[11px] text-muted-foreground">
            {r.convertidos} {r.convertidos === 1 ? 'convertido' : 'convertidos'}
          </p>
        </div>
        {r.activos === 0 ? (
          <Badge color={GRIS} variant="outline">Sin abiertos</Badge>
        ) : (
          <Badge color={sem.color} variant="outline" dot title={TOOLTIP_ULT_ACT}>
            {sem.label}
          </Badge>
        )}
      </div>

      {/* Números clave — capital PEN y USD SIEMPRE por separado */}
      <div className="mt-2 grid grid-cols-3 gap-1.5">
        <MiniDato denso label="Activos" valor={String(r.activos)} />
        <MiniDato
          denso
          label="Capital (PEN)"
          valor={moneyK(r.capitalPEN)}
          sub={r.capitalUSD > 0 ? `+${moneyK(r.capitalUSD, 'USD')}` : undefined}
        />
        <MiniDato
          denso
          label="Sin tocar"
          valor={String(r.sinTocar)}
          color={r.sinTocar > 0 ? SEMAFORO.atencion : undefined}
          title={TOOLTIP_SIN_TOCAR}
        />
      </div>

      {/* Conversión en UN renglón (convertidos / total de sus leads) — navy, sin verde */}
      <div className="mt-2 flex items-center gap-2 text-[11px]">
        <span className="font-semibold text-muted-foreground">Conversión</span>
        <Progress value={r.conversion} color={SEMAFORO.navy} className="h-1 flex-1" />
        <span className="font-bold tabular-nums">{r.conversion}%</span>
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
  const { yo } = useAuth()
  const [sel, setSel] = useState<Record<string, string>>({})

  const bandejaDe = (l: Lead) =>
    equipo.find((m) => m.perfil_id === l.asignado_supervisor_id)?.nombre_completo ?? 'Sin bandeja'

  const asignar = (lead: Lead) => {
    const vid = sel[lead.id]
    if (!vid) return
    const v = (grupos ? grupos.flatMap((g) => g.vs) : vendedores).find((m) => m.perfil_id === vid)
    const r = reasignar(lead.id, vid)
    if (r.ok) {
      // Sufijo "(demo)" unificado con el resto de mutaciones demo (guard yo?.demo).
      toast.success(
        `${lead.nombre_completo} asignado a ${v?.nombre_completo ?? 'vendedor'}${yo?.demo ? ' (demo)' : ''}`,
      )
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
  const { ambito, actividadesDelAmbito, tareas } = useCRMData()
  const ahora = useAhora() // reloj vivo: los "d sin act." refrescan solos

  // Todo el cómputo en UN memo (patrón de Hoy·Supervisor): el índice de última
  // actividad se construye UNA vez y lo comparten cards y cola — con useAhora
  // tickeando por minuto, antes se re-indexaba el timeline en cada render.
  // `ahora` DEBE seguir en las deps para que los "d sin act." refresquen.
  const d = useMemo(() => {
    const indice = indexarUltimaActividad(actividadesDelAmbito)
    const filas = metricasPorVendedor(ambito.vendedores, ambito.leads, actividadesDelAmbito, ahora, indice)
    const parkeados = ambito.leads.filter((l) => esAbierto(l) && l.vendedor_id == null)
    // Fase B: leads con tarea pendiente tienen plan → fuera de la cola por inactividad.
    const conTarea = new Set(
      tareas.filter((x) => x.estado === 'pendiente' && x.activo && x.lead_id).map((x) => x.lead_id as string),
    )
    // colaDe ya no recibe índice: se construye el suyo de CONTACTO (los tipos
    // de índice son indistinguibles y pasarle el de actividad reintroduciría el
    // bug de la `reasignacion` que vaciaba la cola).
    const cola = colaDe(ambito.leads, actividadesDelAmbito, ahora, conTarea)

    // Totales sobre el ámbito completo con vendedor (incluye leads asignados al
    // PROPIO supervisor) — misma base que Hoy·Supervisor; los parkeados no suman.
    const abiertosAsignados = ambito.leads.filter((l) => esAbierto(l) && l.vendedor_id != null)
    const { pen: capitalPEN, usd: capitalUSD } = capitalPorMoneda(abiertosAsignados)
    return { filas, parkeados, cola, capitalPEN, capitalUSD, activos: abiertosAsignados.length }
  }, [ambito, actividadesDelAmbito, tareas, ahora])

  const stats: StatChipData[] = [
    { icon: Users, label: 'Mis vendedores', value: String(ambito.vendedores.length), tone: 'accent' },
    chipCapitalEnProceso(d.capitalPEN, d.capitalUSD),
    { icon: Activity, label: 'Leads activos', value: String(d.activos), sub: `${d.cola.length} en cola de acción` },
    chipPorRepartir(d.parkeados.length, 'Bandeja del equipo'),
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
          {d.filas.length === 0 ? (
            <p className="text-sm text-muted-foreground">No tienes vendedores a cargo todavía.</p>
          ) : (
            <ul
              aria-label="Vendedores de mi equipo"
              className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
            >
              {d.filas.map((r, i) => (
                <li key={r.m.perfil_id}>
                  <VendedorCard r={r} delay={i * 60} />
                </li>
              ))}
            </ul>
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
              d.parkeados.length > 0 ? (
                <Badge color={SEMAFORO.atencion} variant="outline" dot>
                  {d.parkeados.length} en bandeja
                </Badge>
              ) : undefined
            }
          />
          <Bandeja parkeados={d.parkeados} vendedores={ambito.vendedores} ahora={ahora} />
        </Card>
        <Card>
          <SectionHead
            icon={ListTodo}
            title="Cola del equipo"
            right={<span className="text-xs text-muted-foreground">Top 5 por urgencia</span>}
          />
          <MiniCola items={d.cola} />
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
  const { ambito, actividadesDelAmbito, equipo } = useCRMData()
  const ahora = useAhora() // reloj vivo: los "d sin act." refrescan solos
  // Supervisores PRIMERO, detalle por vendedor bajo demanda (patrón aprobado
  // de EquiposBajoSupervision en Hoy·Distribución): qué equipo está abierto.
  const [supervisorSel, setSupervisorSel] = useState<string | null>(null)

  // Un memo para TODO el tablero: el índice de última actividad se construye
  // UNA vez y las métricas de cada bloque se precomputan aquí — antes
  // metricasPorVendedor corría dentro del map del JSX, re-indexando el
  // timeline completo POR SUPERVISOR en cada render (y useAhora tickea por
  // minuto). `ahora` DEBE seguir en deps para que los "d sin act." refresquen.
  const d = useMemo(() => {
    const indice = indexarUltimaActividad(actividadesDelAmbito)
    const filas = comparativaEquipos(equipo, ambito.leads, actividadesDelAmbito)
    const parkeados = ambito.leads.filter((l) => esAbierto(l) && l.vendedor_id == null)

    // Vendedores activos por supervisor en UNA pasada sobre el roster —
    // lo comparten los bloques y los optgroups de la bandeja global.
    const vendedoresPorSupervisor = new Map<string, Miembro[]>()
    for (const m of equipo) {
      if (m.rol_crm !== 'vendedor' || !m.activo || m.supervisor_id == null) continue
      const lista = vendedoresPorSupervisor.get(m.supervisor_id)
      if (lista) lista.push(m)
      else vendedoresPorSupervisor.set(m.supervisor_id, [m])
    }

    const bloques = filas.map((f) => {
      const metricas = metricasPorVendedor(
        vendedoresPorSupervisor.get(f.supervisor.perfil_id) ?? [],
        ambito.leads,
        actividadesDelAmbito,
        ahora,
        indice,
      )
      // Cartera primero (ya vienen por capital PEN desc): los vendedores en
      // cero absoluto van al final — la mirada cae en el capital en juego.
      // OJO: activos=0 con convertidos>0 NO es cero (convirtió toda su cartera).
      const conCartera = metricas.filter((r) => r.activos > 0 || r.convertidos > 0)
      const vendedores = [...conCartera, ...metricas.filter((r) => r.activos === 0 && r.convertidos === 0)]
      // Peor última actividad entre vendedores CON abiertos — alimenta el
      // semáforo de la fila comparativa; null = ningún vendedor con abiertos.
      let peorDias: number | null = null
      for (const r of metricas) {
        if (r.activos > 0 && (peorDias == null || r.diasSinActividadMax > peorDias)) peorDias = r.diasSinActividadMax
      }
      return { f, vendedores, peorDias, todoEnCero: metricas.length > 0 && conCartera.length === 0 }
    })
    const grupos: GrupoVendedores[] = filas
      .map((f) => ({ sup: f.supervisor, vs: vendedoresPorSupervisor.get(f.supervisor.perfil_id) ?? [] }))
      .filter((g) => g.vs.length > 0)

    return {
      filas,
      parkeados,
      bloques,
      grupos,
      capPEN: filas.reduce((a, f) => a + f.capitalPEN, 0),
      capUSD: filas.reduce((a, f) => a + f.capitalUSD, 0),
      activos: filas.reduce((a, f) => a + f.activos, 0),
      convertidos: filas.reduce((a, f) => a + f.convertidos, 0),
    }
  }, [ambito, actividadesDelAmbito, equipo, ahora])

  const stats: StatChipData[] = [
    {
      icon: ShieldCheck,
      label: 'Equipos',
      value: String(d.filas.length),
      tone: 'accent',
      sub: `${ambito.vendedores.length} vendedores en total`,
    },
    chipCapitalEnProceso(d.capPEN, d.capUSD),
    { icon: Activity, label: 'Leads activos', value: String(d.activos), sub: `${d.convertidos} convertidos` },
    chipPorRepartir(d.parkeados.length, 'En bandejas de supervisores'),
  ]

  // Con un solo equipo el detalle se abre solo (no hay nada que comparar);
  // si el seleccionado dejó de existir (roster cambió), el find lo descarta.
  const bloqueSel =
    d.bloques.find((b) => b.f.supervisor.perfil_id === supervisorSel) ??
    (d.bloques.length === 1 ? d.bloques[0] : undefined)

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      {!conAcciones && (
        <p className="text-[11px] text-muted-foreground">
          Vista de auditoría del Directorio — solo lectura, sin acciones de gestión.
        </p>
      )}

      {/* Supervisores PRIMERO: una tabla comparativa (equipo vs equipo en una
         sola pantalla); el detalle por vendedor se abre bajo demanda. */}
      <Card>
        <SectionHead
          icon={ShieldCheck}
          title="Comparativa de equipos"
          right={<span className="text-xs text-muted-foreground">Orden: capital en proceso (PEN)</span>}
        />
        <CardContent className="pt-0">
          <TablaEnvoltura ariaLabel="Comparativa de supervisores">
            <TheadCrm>
              <Th>Supervisor</Th>
              <Th>Últ. actividad</Th>
              <Th className="text-right">Activos</Th>
              <Th className="text-right">Capital PEN</Th>
              <Th>Conversión</Th>
              <Th className="text-right">Por repartir</Th>
              <Th>
                <span className="sr-only">Detalle del equipo</span>
              </Th>
            </TheadCrm>
            <tbody>
              {d.bloques.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                    Aún no hay supervisores activos — enrola al equipo para ver la comparativa.
                  </td>
                </tr>
              ) : (
                d.bloques.map(({ f, peorDias }) => {
                  const abierto = bloqueSel?.f.supervisor.perfil_id === f.supervisor.perfil_id
                  const sem = peorDias != null ? semaforoActividad(peorDias) : null
                  return (
                    <tr
                      key={f.supervisor.perfil_id}
                      onClick={() => setSupervisorSel(abierto ? null : f.supervisor.perfil_id)}
                      className={`cursor-pointer border-b border-border/60 transition-colors last:border-0 hover:bg-muted/40 ${abierto ? 'bg-accent/5' : ''}`}
                    >
                      <Td>
                        <div className="flex items-center gap-2.5">
                          <Avatar nombre={f.supervisor.nombre_completo} className="size-7 text-[10px]" />
                          <div className="min-w-0">
                            <p
                              className="max-w-[220px] truncate text-[13px] font-semibold text-foreground"
                              title={f.supervisor.nombre_completo}
                            >
                              {f.supervisor.nombre_completo}
                            </p>
                            <p className="text-[11px] text-muted-foreground">
                              {f.vendedores} {f.vendedores === 1 ? 'vendedor' : 'vendedores'}
                            </p>
                          </div>
                        </div>
                      </Td>
                      <Td>
                        {sem == null ? (
                          <Badge color={GRIS} variant="outline">Sin abiertos</Badge>
                        ) : (
                          <Badge
                            color={sem.color}
                            variant="outline"
                            dot
                            title="Última actividad del lead abierto más abandonado del equipo"
                          >
                            {sem.label}
                          </Badge>
                        )}
                      </Td>
                      <Td className={`text-right tabular-nums ${f.activos === 0 ? 'text-muted-foreground' : ''}`}>
                        {f.activos}
                      </Td>
                      <Td className="whitespace-nowrap text-right">
                        {f.capitalPEN > 0 ? (
                          <span className="font-extrabold tabular-nums text-primary">{moneyK(f.capitalPEN)}</span>
                        ) : (
                          <span className="tabular-nums text-muted-foreground">—</span>
                        )}
                        {f.capitalUSD > 0 && (
                          <span className="ml-1 text-[10px] tabular-nums text-muted-foreground">
                            +{moneyK(f.capitalUSD, 'USD')}
                          </span>
                        )}
                      </Td>
                      <Td>
                        {f.conversion > 0 ? (
                          <div className="flex items-center gap-2">
                            <Progress value={f.conversion} color={SEMAFORO.navy} className="h-1 w-16" />
                            <span className="text-xs font-bold tabular-nums">{f.conversion}%</span>
                          </div>
                        ) : (
                          <span className="text-xs tabular-nums text-muted-foreground">0%</span>
                        )}
                      </Td>
                      <Td
                        className={`text-right tabular-nums ${f.parkeados > 0 ? 'font-extrabold' : 'text-muted-foreground'}`}
                        style={f.parkeados > 0 ? { color: SEMAFORO.atencion } : undefined}
                      >
                        {f.parkeados > 0 ? f.parkeados : '—'}
                      </Td>
                      <Td className="text-right">
                        <Button
                          size="sm"
                          variant={abierto ? 'default' : 'outline'}
                          onClick={(e) => {
                            e.stopPropagation()
                            setSupervisorSel(abierto ? null : f.supervisor.perfil_id)
                          }}
                        >
                          {abierto ? 'Ocultar' : 'Ver equipo'}
                        </Button>
                      </Td>
                    </tr>
                  )
                })
              )}
            </tbody>
          </TablaEnvoltura>
          {d.bloques.length > 1 && bloqueSel == null && (
            <p className="mt-3 text-xs text-muted-foreground">
              El detalle por vendedor se abre solo cuando hace falta — elige un equipo en la tabla.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Detalle del equipo SELECCIONADO: cabecera comparativa + TABLA de sus vendedores */}
      {d.bloques.filter((b) => b === bloqueSel).map(({ f, vendedores, todoEnCero }) => (
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
              <MiniDato
                label="Capital (PEN)"
                valor={moneyK(f.capitalPEN)}
                sub={f.capitalUSD > 0 ? `+${moneyK(f.capitalUSD, 'USD')}` : undefined}
              />
              <MiniDato label="Activos" valor={String(f.activos)} />
              <MiniDato label="Conversión" valor={`${f.conversion}%`}>
                <Progress value={f.conversion} color={SEMAFORO.navy} className="mt-1.5 h-1.5" />
              </MiniDato>
              <MiniDato
                label="Por repartir"
                valor={String(f.parkeados)}
                color={f.parkeados > 0 ? SEMAFORO.atencion : undefined}
              />
            </div>

            {vendedores.length === 0 ? (
              <p className="text-sm text-muted-foreground">Sin vendedores asignados a este equipo.</p>
            ) : todoEnCero ? (
              /* Equipo entero en cero: la tabla sería un muro de ceros —
                 vacío honesto y accionable (la acción varía por rol). */
              <PanelVacio
                icono={Users}
                titulo="Este equipo aún no tiene leads asignados"
                detalle={
                  conAcciones
                    ? f.parkeados > 0
                      ? `Hay ${f.parkeados} ${f.parkeados === 1 ? 'lead' : 'leads'} en la bandeja de este supervisor — repártelos para poner capital en juego.`
                      : d.parkeados.length > 0
                        ? 'Reparte leads desde la bandeja de la empresa para poner capital en juego.'
                        : 'Cuando entren leads a las bandejas podrás repartirlos entre sus vendedores.'
                    : 'Sin capital en juego ni conversiones todavía — nada que auditar en este equipo.'
                }
              >
                {conAcciones && d.parkeados.length > 0 && (
                  <a
                    href="#por-repartir-empresa"
                    className="text-xs font-semibold text-accent underline-offset-2 hover:underline"
                  >
                    Ir a la bandeja «Por repartir» ↓
                  </a>
                )}
              </PanelVacio>
            ) : (
              /* Tabla comparativa (fila ~33 px): lo que gerencia/directorio
                 necesitan es comparar vendedores columna a columna, no cards. */
              <TablaEnvoltura ariaLabel={`Vendedores del equipo de ${f.supervisor.nombre_completo}`}>
                <TheadCrm>
                  <Th>Vendedor</Th>
                  <Th>Últ. actividad</Th>
                  <Th className="text-right">Activos</Th>
                  <Th className="text-right">Capital PEN</Th>
                  <Th className="text-right">Sin tocar</Th>
                  <Th>Conversión</Th>
                </TheadCrm>
                <tbody>
                  {vendedores.map((r) => {
                    const sem = semaforoActividad(r.diasSinActividadMax)
                    return (
                      <tr
                        key={r.m.perfil_id}
                        className="border-b border-border/60 transition-colors last:border-0 hover:bg-muted/40"
                      >
                        <Td>
                          <p
                            className="max-w-[220px] truncate text-[13px] font-semibold text-foreground"
                            title={r.m.nombre_completo}
                          >
                            {r.m.nombre_completo}
                          </p>
                        </Td>
                        <Td>
                          {r.activos === 0 ? (
                            <Badge color={GRIS} variant="outline">Sin abiertos</Badge>
                          ) : (
                            <Badge color={sem.color} variant="outline" dot title={TOOLTIP_ULT_ACT}>
                              {sem.label}
                            </Badge>
                          )}
                        </Td>
                        {/* Ceros en mudo: extrabold/primary reservado a >0 —
                           lo que tiene capital en juego es lo que debe gritar. */}
                        <Td className={`text-right tabular-nums ${r.activos === 0 ? 'text-muted-foreground' : ''}`}>
                          {r.activos}
                        </Td>
                        <Td className="whitespace-nowrap text-right">
                          {r.capitalPEN > 0 ? (
                            <span className="font-extrabold tabular-nums text-primary">{moneyK(r.capitalPEN)}</span>
                          ) : (
                            <span className="tabular-nums text-muted-foreground">—</span>
                          )}
                          {r.capitalUSD > 0 && (
                            <span className="ml-1 text-[10px] tabular-nums text-muted-foreground">
                              +{moneyK(r.capitalUSD, 'USD')}
                            </span>
                          )}
                        </Td>
                        <Td
                          className={`text-right tabular-nums ${r.sinTocar > 0 ? 'font-extrabold' : 'text-muted-foreground'}`}
                          style={r.sinTocar > 0 ? { color: SEMAFORO.atencion } : undefined}
                          title={TOOLTIP_SIN_TOCAR}
                        >
                          {r.sinTocar > 0 ? r.sinTocar : '—'}
                        </Td>
                        <Td>
                          {r.conversion > 0 ? (
                            <div className="flex items-center gap-2">
                              <Progress value={r.conversion} color={SEMAFORO.navy} className="h-1 w-16" />
                              <span className="text-xs font-bold tabular-nums">{r.conversion}%</span>
                            </div>
                          ) : (
                            <span className="text-xs tabular-nums text-muted-foreground">0%</span>
                          )}
                        </Td>
                      </tr>
                    )
                  })}
                </tbody>
              </TablaEnvoltura>
            )}
          </CardContent>
        </Card>
      ))}

      {/* Bandeja global — SOLO gerencia (directorio no acciona nada);
         el id es el ancla del vacío accionable del bloque todo-en-cero. */}
      {conAcciones && (
        <Card id="por-repartir-empresa" className="scroll-mt-20">
          <SectionHead
            icon={Inbox}
            title="Por repartir (toda la empresa)"
            right={
              d.parkeados.length > 0 ? (
                <Badge color={SEMAFORO.atencion} variant="outline" dot>
                  {d.parkeados.length} en bandejas
                </Badge>
              ) : undefined
            }
          />
          <Bandeja
            parkeados={d.parkeados}
            vendedores={ambito.vendedores}
            grupos={d.grupos}
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
