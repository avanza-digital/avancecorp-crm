// screens/equipo.tsx — Inteligencia de EQUIPO por rango (F1c).
// Solo la ven supervisor/gerencia/directorio (App.tsx guarda la ruta):
//  - Supervisor: cards densas de SUS vendedores (métricas + semáforo de
//    actividad), bandeja "Por repartir" con acción de asignar y mini-cola.
//  - Gerencia: PRIMERO una tabla comparativa de supervisores (comparativaEquipos)
//    y el detalle por vendedor de UN equipo bajo demanda (fila/botón "Ver
//    equipo" — patrón aprobado de EquiposBajoSupervision en Hoy·Distribución:
//    "el detalle se abre solo cuando hace falta"); también puede repartir.
//  - Directorio: la misma radiografía que gerencia, pero Directorio es SOLO LECTURA (cero
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
import { Select } from '@/components/ui/select'
import { PanelVacio } from '@/components/common/estado-panel'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { AvisoCoberturaConversion } from '@/components/common/aviso-cobertura-conversion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { moneyK, numero } from '@/lib/format'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import { identidadesEquipoConversion } from '@/lib/conversion-equipo'
import { useConversionMensual, useMetricasConversionesEquipo } from '@/data/crm-queries'
import { periodoInicialGerencia, semanticaMetaMensual } from '@/components/gerencia/periodo'
import { RankingVendedoresPanel } from './hoy/ranking-vendedores'
import { useTipoCambio, type TipoCambio } from '@/lib/tipo-cambio'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { origenLabel, type Lead, type Miembro } from '@/lib/tipos'
import {
  diasDesdeReferencia,
  esAbierto,
  haceCortoTexto,
  type ItemCola,
} from '@/lib/inteligencia'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import {
  textoConversionOperativa,
  ventanaConversionEnPalabras,
  type MetricaVendedorOperativa,
} from '@/lib/metricas-vendedores'

// ── Paleta de semáforos y helpers ─────────────────────────────────────────────

const GRIS = SEMAFORO.neutro // neutro (sin señal) — no forma parte del semáforo central

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

// OJO: wording propio de esta pantalla ('hace N d' compacto) — la ABREVIATURA
// es suya; la RESOLUCIÓN es la escala única. Antes 'hace horas' tapaba las
// primeras 24 h y un lead de 4 minutos en la bandeja decía lo mismo que uno
// de 23 horas (el mismo colapso del bug de #/alertas, copiado aquí).
const haceDiasTxt = haceCortoTexto

const TOOLTIP_SIN_TOCAR = 'Leads abiertos sin ninguna actividad registrada'
const TOOLTIP_ULT_ACT = 'Última actividad del lead abierto más abandonado'

// ── Piezas locales compartidas por las dos vistas (sin exportar) ──────────────

/**
 * Chip de capital en proceso. Desde la decisión #10 (Miguel, 2026-08-10) el
 * PROTAGONISTA es el total unificado en soles; el desglose por moneda se conserva
 * en el `sub`. Sin TC degrada al comportamiento anterior —PEN protagonista y USD
 * aparte— porque el USD NO entra al total sin una tasa real: jamás se inventa.
 */
function chipCapitalEnProceso(pen: number, usd: number, tc: TipoCambio | null | undefined): StatChipData {
  const cap = totalEnSoles(pen, usd, tc?.promedio)
  if (cap.estado !== 'convertido' || cap.total == null) {
    return {
      icon: Wallet,
      label: 'Capital en proceso (PEN)',
      value: moneyK(pen),
      tone: 'primary',
      sub: usd > 0 ? `+${moneyK(usd, 'USD')} aparte` : 'Solo soles',
    }
  }
  return {
    icon: Wallet,
    label: 'Capital en proceso (S/)',
    value: moneyK(cap.total),
    tone: 'primary',
    sub: usd > 0 ? `${moneyK(pen)} + ${moneyK(usd, 'USD')}` : 'Solo soles',
  }
}

/**
 * Celda de capital dentro de una TABLA (vista de empresa).
 *
 * Arregla de paso un defecto vivo: cuando el capital en soles era 0 la celda decía
 * «—», de modo que un vendedor con cartera 100 % en dólares aparecía como si no
 * tuviera capital, con su cifra real escondida en la letra chica. Con el total
 * unificado aparece lo que de verdad gestiona (Miguel lo confirmó al cerrar la #10).
 */
function CeldaCapitalTabla({
  pen,
  usd,
  tc,
}: {
  pen: number
  usd: number
  tc: TipoCambio | null | undefined
}): JSX.Element {
  const cap = totalEnSoles(pen, usd, tc?.promedio)
  return (
    <>
      {cap.total != null && cap.total > 0 ? (
        <span className="font-extrabold tabular-nums text-primary">{moneyK(cap.total)}</span>
      ) : (
        <span className="tabular-nums text-muted-foreground">—</span>
      )}
      <DesgloseMonedas pen={pen} usd={usd} tc={cap.tc} compacto />
    </>
  )
}

/**
 * Celda de capital de una fila de equipo: total unificado como número grande y el
 * desglose por moneda debajo. Es la pieza ÚNICA de las dos vistas de esta pantalla.
 *
 * Con el TC consultándose (`undefined`) o caído (`null`) muestra el PEN y lo dice en
 * la etiqueta: es exactamente lo que se veía antes de la decisión #10, así que la
 * degradación no estrena comportamiento, vuelve al conocido.
 */
function CapitalDeFila({
  pen,
  usd,
  tc,
  denso = false,
}: {
  pen: number
  usd: number
  tc: TipoCambio | null | undefined
  denso?: boolean
}): JSX.Element {
  const cap = totalEnSoles(pen, usd, tc?.promedio)
  const unificado = cap.estado === 'convertido' && cap.total != null
  return (
    <MiniDato
      denso={denso}
      label={unificado ? 'Capital (S/)' : 'Capital (PEN)'}
      // `moneyK(null)` imprimiría «S/ 0» — un cero afirmado donde no sabemos nada.
      valor={cap.total != null ? moneyK(cap.total) : '—'}
    >
      <DesgloseMonedas pen={pen} usd={usd} tc={cap.tc} compacto />
    </MiniDato>
  )
}

/**
 * Estado visible de una conversión NULL. Una fila presente con divisor cero y
 * una fila mensual ausente son situaciones distintas y nunca dicen 0 %.
 */
function motivoConversionNula(disponible: boolean, divisor: number | null): string {
  return disponible && divisor === 0 ? 'Sin divisor mensual' : 'Dato no disponible'
}

function EstadoConversionNula({
  className,
  disponible,
  divisor,
}: {
  className: string
  disponible: boolean
  divisor: number | null
}): JSX.Element {
  const motivo = motivoConversionNula(disponible, divisor)
  return (
    <span className={className} title={motivo}>
      <span aria-hidden="true">— · </span>
      <span className="text-[10px] font-normal">{motivo}</span>
    </span>
  )
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
  srDetalle,
  children,
}: {
  label: string
  valor: string
  sub?: string | undefined
  color?: string | undefined
  denso?: boolean
  title?: string
  /** Explicación solo-lector junto al valor (un «—» sin ella es mudo). */
  srDetalle?: string
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
        {srDetalle && <span className="sr-only">{srDetalle}</span>}
        {sub && <span className="ml-1 text-[10px] font-normal tabular-nums text-muted-foreground">{sub}</span>}
      </p>
      {children}
    </div>
  )
}

// ── Card de vendedor (vista del supervisor: ≤6 vendedores, card densa) ────────

function VendedorCard({
  r,
  tc,
  ventanaConversion,
  delay = 0,
}: {
  r: MetricaVendedorOperativa
  tc: TipoCambio | null | undefined
  /** «agosto de 2026» con servidor F2.4 (mes del núcleo) · «45 días» en demo. */
  ventanaConversion: string
  delay?: number
}): JSX.Element {
  const sem = semaforoActividad(r.diasSinActividadMax)
  return (
    <Card className="ac-lift ac-pop h-full p-3" style={{ animationDelay: `${delay}ms` }}>
      {/* Identidad + semáforo de última actividad (peor lead abierto) */}
      <div className="flex items-center gap-2.5">
        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-7 text-[10px]" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] font-semibold">{r.m.nombre_completo}</p>
          <p className="text-[11px] text-muted-foreground">
            {r.cierresConversion == null
              ? 'Cierres no disponibles'
              : `${numero(r.cierresConversion)} ${r.cierresConversion === 1 ? 'cierre' : 'cierres'}`}
            {r.operacionesCartera != null && r.operacionesCartera > 0
              ? ` + ${numero(r.operacionesCartera)} de cartera`
              : ''}
            {' · '}{ventanaConversion}
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

      {/* Números clave — capital unificado con su desglose SIEMPRE debajo */}
      <div className="mt-2 grid grid-cols-3 gap-1.5">
        <MiniDato denso label="Activos" valor={String(r.activos)} />
        <CapitalDeFila denso pen={r.capitalPEN} usd={r.capitalUSD} tc={tc} />
        <MiniDato
          denso
          label="Sin tocar"
          valor={String(r.sinTocar)}
          color={r.sinTocar > 0 ? SEMAFORO.atencion : undefined}
          title={TOOLTIP_SIN_TOCAR}
        />
      </div>

      {/* El porcentaje exacto puede ser NULL o superar 100 por cartera/arrastre.
          Por eso aquí no se usa Progress (su semántica es 0–100): se conserva
          la cifra servida sin un tope visual engañoso. */}
      <div className="mt-2 flex items-center gap-2 text-[11px]">
        <span className="font-semibold text-muted-foreground">Conversión · {ventanaConversion}</span>
        {r.conversion == null ? (
          <span className="ml-auto text-right text-muted-foreground">
            <EstadoConversionNula
              className="font-bold tabular-nums"
              disponible={r.conversionDisponible}
              divisor={r.divisorConversion}
            />
            {r.operacionesCartera != null && r.operacionesCartera > 0
              ? ` · ${numero(r.operacionesCartera)} de cartera`
              : ''}
          </span>
        ) : (
          <span className="ml-auto font-bold tabular-nums">
            {textoConversionOperativa(r.conversion)}
            {r.operacionesCartera != null && r.operacionesCartera > 0
              ? ` · ${numero(r.operacionesCartera)} de cartera`
              : ''}
          </span>
        )}
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

function MiniCola({ items, total, max = 5 }: { items: ItemCola[]; total: number; max?: number }): JSX.Element {
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
      {total > max && (
        <p className="pt-1 text-[11px] text-muted-foreground">
          +{total - max} pendientes más en la cola del equipo.
        </p>
      )}
    </div>
  )
}

// ── Vista SUPERVISOR — su equipo, su bandeja, su cola ─────────────────────────

function EquipoSupervisor(): JSX.Element {
  const {
    ambito,
    actividadesDelAmbito,
    tareas,
    equipo,
    objetivos,
    objetivosError,
    cumplimientoMetas,
    recargar,
  } = useCRMData()
  const { yo } = useAuth()
  // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola (en real esos
  // vencimientos llegan resueltos dentro de cola_accion_fn).
  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividadesDelAmbito, yo?.demo === true)
  // ── F1b: agregados del servidor (o espejo demo vivo) ──
  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividadesDelAmbito)
  const resumen = resumenOp.resumen
  // TC izado UNA vez por pantalla: el hook no pasa por TanStack (no hay cache ni
  // dedupe), así que uno por fila multiplicaría las llamadas a la edge.
  const { tc } = useTipoCambio()
  // ── Ranking de MI equipo (decisión #10) ──
  // Vive AQUÍ y no en «Hoy» porque en producción `FUNCIONES_LEADS_APROBADAS`
  // está en false: un supervisor real NO ve el mundo de leads, así que «Hoy» no
  // existe para él. «Gestión de equipo» sí la ve —no está en VISTAS_LEADS— y es
  // además donde ya mira a su gente.
  const equipoConversion = useMemo(
    () => identidadesEquipoConversion(ambito.vendedores, equipo),
    [ambito.vendedores, equipo],
  )
  const periodoRanking = useMemo(() => periodoInicialGerencia(), [])
  const metaMensual = useMemo(() => {
    const semantica = semanticaMetaMensual(periodoRanking)
    return objetivosError ? { ...semantica, comparable: false, errorCarga: true } : semantica
  }, [objetivosError, periodoRanking])
  // La conversión de MI equipo sale de la MISMA RPC mensual que su tile de
  // «Hoy» (`crm.conversion_mensual_fn`, alcance equipo por rol) — el payload
  // viejo del equipo medía otra pregunta y ya no alimenta este tab. Tri-estado
  // como el TC: undefined = consultando, null = no disponible (fail-closed).
  const periodoConversionMes = `${periodoRanking.hasta.slice(0, 7)}-01`
  const qConversionMensual = useConversionMensual(!yo?.demo, periodoConversionMes)
  // Cosecha por vendedor de MI equipo (F2.2/D2, alcance equipo por rol en el
  // servidor): mismo MES que la mensual del tab. Tri-estado; en demo no se
  // consulta ni se pinta (el espejo demo no la produce — fail-closed).
  const qCosechaEquipo = useMetricasConversionesEquipo(
    !yo?.demo,
    periodoConversionMes,
    periodoRanking.hasta,
  )
  const cosechaEquipo = yo?.demo
    ? undefined
    : qCosechaEquipo.isPending || qCosechaEquipo.isFetching
      ? undefined
      : (qCosechaEquipo.data ?? null)
  const conversionMensualEquipo = yo?.demo
    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
    : qConversionMensual.isPending || qConversionMensual.isFetching
      ? undefined
      : (qConversionMensual.data ?? null)
  const colaOp = useColaAccionOperativa(ambito.leads, actividadesDelAmbito, tareas, estadoSla.indice)
  const cola = colaOp.cola
  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividadesDelAmbito)
  const filas = vendedoresOp.metricas?.filas ?? null
  const ventanaConversion = ventanaConversionEnPalabras(vendedoresOp.metricas?.mesMetrica ?? null)

  const errorIndicadores = !yo?.demo
    && Boolean(resumenOp.error || colaOp.error || vendedoresOp.error)
  const reintentarIndicadores = () => {
    if (resumenOp.error) void resumenOp.recargar()
    if (colaOp.error) void colaOp.recargar()
    if (vendedoresOp.error) void vendedoresOp.recargar()
  }

  const stats: StatChipData[] = [
    { icon: Users, label: 'Mis vendedores', value: String(ambito.vendedores.length), tone: 'accent' },
    resumen
      ? chipCapitalEnProceso(resumen.capital.asignado.pen, resumen.capital.asignado.usd, tc)
      : { icon: Wallet, label: 'Capital en proceso (PEN)', value: '—', tone: 'primary' },
    {
      icon: Activity,
      label: 'Leads activos',
      value: resumen ? String(resumen.totales.asignados) : '—',
      ...(cola ? { sub: `${cola.total} en cola de acción` } : {}),
    },
    resumen
      ? chipPorRepartir(resumen.totales.parkeados, 'Bandeja del equipo')
      : { icon: Inbox, label: 'Por repartir', value: '—', sub: 'Bandeja del equipo' },
  ]

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      <AvisoDegradacion
        activo={errorIndicadores}
        queReintenta="de los indicadores del equipo"
        onReintentar={reintentarIndicadores}
      >
        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      <AvisoCoberturaConversion mensaje={vendedoresOp.metricas?.avisoConversion} />

      {/* Cards de MIS vendedores (orden: capital captado PEN desc) */}
      <Card>
        <SectionHead
          icon={Users}
          title="Mi equipo"
          // El orden lo sigue mandando el servidor por capital PEN: ordenar en
          // cliente por el total desincronizaría con el RPC y —peor— haría que el
          // orden CAMBIARA solo cuando la edge del TC se cae. Se rotula tal cual es.
          right={
            <span className="text-xs text-muted-foreground">
              Orden: capital en proceso (PEN)
              {tc ? ` · ${rotuloTipoCambio(tc.promedio, tc.fuente)}` : ''}
            </span>
          }
        />
        <CardContent className="pt-0">
          {filas == null ? (
            <p className="text-sm text-muted-foreground">
              {vendedoresOp.error
                ? 'El resumen por vendedor no está disponible en este momento.'
                : 'Cargando el resumen por vendedor…'}
            </p>
          ) : filas.length === 0 ? (
            <p className="text-sm text-muted-foreground">No tienes vendedores a cargo todavía.</p>
          ) : (
            <ul
              aria-label="Vendedores de mi equipo"
              className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
            >
              {filas.map((r, i) => (
                <li key={r.m.perfil_id}>
                  <VendedorCard r={r} tc={tc} ventanaConversion={ventanaConversion} delay={i * 60} />
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      {/* El reparto vive en el módulo independiente «Derivar leads». */}
      <Card>
        <SectionHead
          icon={ListTodo}
          title="Cola del equipo"
          right={<span className="text-xs text-muted-foreground">Top 5 por urgencia</span>}
        />
        {cola == null ? (
          <p className="px-5 pb-4 text-sm text-muted-foreground">
            {colaOp.error
              ? 'La cola del equipo no está disponible en este momento.'
              : 'Cargando la cola del equipo…'}
          </p>
        ) : (
          <MiniCola items={cola.items} total={cola.total} />
        )}
      </Card>

      <p className="text-[11px] text-muted-foreground">
        Los números corresponden solo a tu equipo — cada rol ve únicamente lo que le corresponde.
      </p>

      {/* Ranking de MI equipo (decisión #10). Vive en esta pantalla y NO en «Hoy»
          porque en producción FUNCIONES_LEADS_APROBADAS está en false: un
          supervisor real no ve el mundo de leads y «Hoy» no existe para él.
          «Gestión de equipo» sí la ve (no está en VISTAS_LEADS) y es donde ya
          mira a su gente. */}
      <div className="gerencia-inteligencia">
        <RankingVendedoresPanel
          datos={null}
          conversionMensual={conversionMensualEquipo}
          cosecha={cosechaEquipo}
          equipo={equipoConversion}
          metasVendedores={objetivos.porVendedor ?? {}}
          cumplimientoVendedores={cumplimientoMetas?.porVendedor ?? {}}
          metaMensual={metaMensual}
          tc={tc}
          cargando={false}
          // El fallo de la MENSUAL es un error del ranking, no una degradación
          // muda a «indisponible» (exigencia pre-release de Miguel, 2026-08-15).
          error={!yo?.demo && qConversionMensual.isError
            ? 'No se pudo calcular la conversión mensual del equipo.'
            : null}
          onReintentar={() => { void recargar(); if (!yo?.demo) void qConversionMensual.refetch() }}
          titulo="Ranking de mi equipo"
          etiquetaAlcance="Mi equipo"
          tabInicial="capital-total"
        />
      </div>

    </div>
  )
}

// ── Vista GERENCIA / DIRECTORIO — bloques por supervisor ──────────────────────

function EquipoEmpresa({ conAcciones }: { conAcciones: boolean }): JSX.Element {
  const { ambito, actividadesDelAmbito, equipo } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora() // reloj vivo: los "d sin act." refrescan solos
  // Supervisores PRIMERO, detalle por vendedor bajo demanda (patrón aprobado
  // de EquiposBajoSupervision en Hoy·Distribución): qué equipo está abierto.
  const [supervisorSel, setSupervisorSel] = useState<string | null>(null)

  // ── F1b: ranking y comparativa llegan de metricas_vendedores_fn (o del
  // espejo demo vivo). Los chips del StatStrip se derivan del MISMO payload
  // que la tabla (reduce O(supervisores)) para que cuadren SIEMPRE entre sí.
  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividadesDelAmbito)
  const metricas = vendedoresOp.metricas
  const ventanaConversion = ventanaConversionEnPalabras(metricas?.mesMetrica ?? null)
  // TC izado UNA vez por pantalla (ver la nota en EquipoSupervisor).
  const { tc } = useTipoCambio()

  // Roster y bandeja global: puro cliente (la bandeja es una lista operable y
  // sus contadores describen las filas que de verdad pinta).
  const d = useMemo(() => {
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
    // Optgroups de la bandeja: del ROSTER, no de las métricas — repartir debe
    // seguir funcionando aunque el RPC de métricas esté caído.
    const grupos: GrupoVendedores[] = equipo
      .filter((m) => m.rol_crm === 'supervisor' && m.activo)
      .map((sup) => ({ sup, vs: vendedoresPorSupervisor.get(sup.perfil_id) ?? [] }))
      .filter((g) => g.vs.length > 0)
    return { parkeados, vendedoresPorSupervisor, grupos }
  }, [ambito.leads, equipo])

  // Tablero derivado del payload: bloques por supervisor con sus vendedores.
  const tablero = useMemo(() => {
    if (!metricas) return null
    const filas = metricas.equipos
    const bloques = filas.map((f) => {
      const rosterSup = new Set(
        (d.vendedoresPorSupervisor.get(f.supervisor.perfil_id) ?? []).map((m) => m.perfil_id),
      )
      const delEquipo = metricas.filas.filter((r) => rosterSup.has(r.m.perfil_id))
      // Cartera primero (ya vienen por capital PEN desc): los vendedores en
      // cero absoluto van al final — la mirada cae en el capital en juego.
      // OJO: activos=0 con cierres u operaciones de cartera NO es cero. Una
      // renovación/upgrade acreditada debe seguir visible aunque no haya lead.
      const conActividadORevision = delEquipo.filter((r) => (
        r.activos > 0
        || !r.conversionDisponible
        || (r.cierresConversion ?? 0) > 0
        || (r.operacionesCartera != null && r.operacionesCartera > 0)
      ))
      const vendedores = [
        ...conActividadORevision,
        ...delEquipo.filter((r) => !conActividadORevision.includes(r)),
      ]
      // Peor última actividad entre vendedores CON abiertos — alimenta el
      // semáforo de la fila comparativa; null = ningún vendedor con abiertos.
      let peorDias: number | null = null
      for (const r of delEquipo) {
        if (r.activos > 0 && (peorDias == null || r.diasSinActividadMax > peorDias)) peorDias = r.diasSinActividadMax
      }
      return {
        f,
        vendedores,
        peorDias,
        // Un NULL exacto significa «no sabemos», nunca «todo está en cero».
        todoEnCero: delEquipo.length > 0
          && delEquipo.every((r) => (
            r.conversionDisponible
            && r.activos === 0
            && r.cierresConversion === 0
            && r.operacionesCartera === 0
          )),
      }
    })
    return {
      filas,
      bloques,
      capPEN: filas.reduce((a, f) => a + f.capitalPEN, 0),
      capUSD: filas.reduce((a, f) => a + f.capitalUSD, 0),
      activos: filas.reduce((a, f) => a + f.activos, 0),
      // El total canónico incluye producción anónima fuera de roster (F2.6);
      // sumar equipos la perdería silenciosamente porque no puede atribuirse.
      cierresConversion: metricas.totalConversion.cierresConversion,
    }
  }, [metricas, d.vendedoresPorSupervisor])

  const stats: StatChipData[] = [
    {
      icon: ShieldCheck,
      label: 'Equipos',
      value: tablero ? String(tablero.filas.length) : '—',
      tone: 'accent',
      sub: `${ambito.vendedores.length} vendedores en total`,
    },
    tablero
      ? chipCapitalEnProceso(tablero.capPEN, tablero.capUSD, tc)
      : { icon: Wallet, label: 'Capital en proceso (PEN)', value: '—', tone: 'primary' },
    {
      icon: Activity,
      label: 'Leads activos',
      value: tablero ? String(tablero.activos) : '—',
      ...(tablero
        ? {
          sub: tablero.cierresConversion == null
            ? `Cierres no disponibles · ${ventanaConversion}`
            : `${numero(tablero.cierresConversion)} convertidos · ${ventanaConversion}`,
        }
        : {}),
    },
    chipPorRepartir(d.parkeados.length, 'En bandejas de supervisores'),
  ]

  // Con un solo equipo el detalle se abre solo (no hay nada que comparar);
  // si el seleccionado dejó de existir (roster cambió), el find lo descarta.
  const bloques = tablero?.bloques ?? []
  const bloqueSel =
    bloques.find((b) => b.f.supervisor.perfil_id === supervisorSel) ??
    (bloques.length === 1 ? bloques[0] : undefined)

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      {!conAcciones && (
        <p className="text-[11px] text-muted-foreground">
          Vista de auditoría del Directorio — solo lectura, sin acciones de gestión.
        </p>
      )}

      <AvisoDegradacion
        activo={Boolean(vendedoresOp.error) && !yo?.demo}
        queReintenta="de las métricas por equipo"
        onReintentar={() => { void vendedoresOp.recargar() }}
      >
        No se pudieron cargar las métricas por equipo. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      <AvisoCoberturaConversion mensaje={metricas?.avisoConversion} />

      {/* Supervisores PRIMERO: una tabla comparativa (equipo vs equipo en una
         sola pantalla); el detalle por vendedor se abre bajo demanda. */}
      <Card>
        <SectionHead
          icon={ShieldCheck}
          title="Comparativa de equipos"
          right={
            <span className="text-xs text-muted-foreground">
              Orden: capital en proceso (PEN)
              {tc ? ` · ${rotuloTipoCambio(tc.promedio, tc.fuente)}` : ''}
            </span>
          }
        />
        <CardContent className="pt-0">
          <TablaEnvoltura ariaLabel="Comparativa de supervisores">
            <TheadCrm>
              <Th>Supervisor</Th>
              <Th>Últ. actividad</Th>
              <Th className="text-right">Activos</Th>
              <Th className="text-right">Capital PEN</Th>
              <Th>Conversión · {ventanaConversion}</Th>
              <Th className="text-right">Por repartir</Th>
              <Th>
                <span className="sr-only">Detalle del equipo</span>
              </Th>
            </TheadCrm>
            <tbody>
              {tablero == null ? (
                <tr>
                  <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                    {vendedoresOp.error
                      ? 'La comparativa no está disponible en este momento.'
                      : 'Cargando la comparativa de equipos…'}
                  </td>
                </tr>
              ) : bloques.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                    Aún no hay supervisores activos — enrola al equipo para ver la comparativa.
                  </td>
                </tr>
              ) : (
                bloques.map(({ f, peorDias }) => {
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
                        <CeldaCapitalTabla pen={f.capitalPEN} usd={f.capitalUSD} tc={tc} />
                      </Td>
                      <Td>
                        {f.conversion == null ? (
                          <span className="text-xs tabular-nums text-muted-foreground">
                            <EstadoConversionNula
                              className="tabular-nums text-muted-foreground"
                              disponible={f.conversionDisponible}
                              divisor={f.divisorConversion}
                            />
                            {f.operacionesCartera != null && f.operacionesCartera > 0
                              ? ` · ${numero(f.operacionesCartera)} de cartera`
                              : ''}
                          </span>
                        ) : (
                          <span className={`text-xs tabular-nums ${f.conversion > 0 ? 'font-bold' : 'text-muted-foreground'}`}>
                            {textoConversionOperativa(f.conversion)}
                            {f.operacionesCartera != null && f.operacionesCartera > 0
                              ? ` · ${numero(f.operacionesCartera)} de cartera`
                              : ''}
                          </span>
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
          {bloques.length > 1 && bloqueSel == null && (
            <p className="mt-3 text-xs text-muted-foreground">
              El detalle por vendedor se abre solo cuando hace falta — elige un equipo en la tabla.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Detalle del equipo SELECCIONADO: cabecera comparativa + TABLA de sus vendedores */}
      {bloques.filter((b) => b === bloqueSel).map(({ f, vendedores, todoEnCero }) => (
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
            {/* Cabecera del bloque — comparativaEquipos (total unificado + desglose) */}
            <div className="grid grid-cols-2 gap-3 rounded-xl border border-border bg-primary/[0.03] p-3 sm:grid-cols-4">
              <CapitalDeFila pen={f.capitalPEN} usd={f.capitalUSD} tc={tc} />
              <MiniDato label="Activos" valor={String(f.activos)} />
              <MiniDato
                label={`Conversión · ${ventanaConversion}`}
                valor={textoConversionOperativa(f.conversion)}
                sub={[
                  f.conversion == null
                    ? motivoConversionNula(f.conversionDisponible, f.divisorConversion)
                    : null,
                  f.operacionesCartera != null && f.operacionesCartera > 0
                    ? `${numero(f.operacionesCartera)} de cartera`
                    : null,
                ].filter((texto): texto is string => texto != null).join(' · ') || undefined}
                {...(f.conversion == null
                  ? {
                    title: f.conversionDisponible && f.divisorConversion === 0
                      ? 'Sin divisor mensual'
                      : 'Dato no disponible',
                    srDetalle: f.conversionDisponible && f.divisorConversion === 0
                      ? 'Sin divisor mensual'
                      : 'Dato no disponible',
                  }
                  : {})}
              />
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
                  <Th>Conversión · {ventanaConversion}</Th>
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
                          <CeldaCapitalTabla pen={r.capitalPEN} usd={r.capitalUSD} tc={tc} />
                        </Td>
                        <Td
                          className={`text-right tabular-nums ${r.sinTocar > 0 ? 'font-extrabold' : 'text-muted-foreground'}`}
                          style={r.sinTocar > 0 ? { color: SEMAFORO.atencion } : undefined}
                          title={TOOLTIP_SIN_TOCAR}
                        >
                          {r.sinTocar > 0 ? r.sinTocar : '—'}
                        </Td>
                        <Td>
                          {r.conversion == null ? (
                            <span className="text-xs tabular-nums text-muted-foreground">
                              <EstadoConversionNula
                                className="tabular-nums text-muted-foreground"
                                disponible={r.conversionDisponible}
                                divisor={r.divisorConversion}
                              />
                              {r.operacionesCartera != null && r.operacionesCartera > 0
                                ? ` · ${numero(r.operacionesCartera)} de cartera`
                                : ''}
                            </span>
                          ) : (
                            <span className={`text-xs tabular-nums ${r.conversion > 0 ? 'font-bold' : 'text-muted-foreground'}`}>
                              {textoConversionOperativa(r.conversion)}
                              {r.operacionesCartera != null && r.operacionesCartera > 0
                                ? ` · ${numero(r.operacionesCartera)} de cartera`
                                : ''}
                            </span>
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
