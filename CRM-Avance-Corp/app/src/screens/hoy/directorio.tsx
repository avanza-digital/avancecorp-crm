// Hoy · DIRECTORIO — auditoría ejecutiva global de SOLO LECTURA (F1c).
// El directorio ve TODA la operación (ambito.esGlobal) pero no ejecuta nada:
// cero botones de acción. Abrir la ficha (modo lectura) sí está permitido,
// igual que los links de contacto tel/wa que viven dentro del drawer.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626
// crítico · convertido/ganado = navy #111e3d.
import { useMemo, type CSSProperties, type JSX } from 'react'
import {
  ArrowRightLeft,
  BadgeCheck,
  CalendarCheck,
  Coins,
  Eye,
  Filter,
  History,
  MessageCircle,
  MessageSquare,
  PhoneCall,
  PhoneMissed,
  ShieldCheck,
  StickyNote,
  Users,
  UsersRound,
  Wallet,
  XCircle,
  type LucideIcon,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { SegmentBar } from '@/components/common/stat-strip'
import { Donut } from '@/components/common/donut'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { diasDesdeReferencia } from '@/lib/inteligencia'
import { SEMAFORO } from '@/lib/semaforo'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { money, moneyK, fmtFecha } from '@/lib/format'
import {
  ETAPAS,
  ETAPA_INFO,
  MOTIVOS_DESCARTE,
  TIPOS_ACTIVIDAD,
  type TipoActividad,
} from '@/lib/tipos'
import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'

// ── Constantes de la vista ────────────────────────────────────────────────────

// Mismo mapa de iconos del timeline del drawer (consistencia visual).
const ICONO_ACTIVIDAD: Record<TipoActividad, LucideIcon> = {
  llamada_realizada: PhoneCall,
  llamada_no_contestada: PhoneMissed,
  whatsapp_enviado: MessageCircle,
  whatsapp_recibido: MessageSquare,
  reunion_realizada: CalendarCheck,
  nota: StickyNote,
  cambio_etapa: ArrowRightLeft,
  reasignacion: Users,
  conversion: BadgeCheck,
}

/** "hace Xh / hace Xd" compacto para la bitácora; fechas raras caen a fmtFecha.
 *  Recibe `ahora` (reloj vivo de useAhora) — NUNCA Date.now() en render. */
function haceCorto(iso: string, ahora: number): string {
  const ms = ahora - new Date(iso).getTime()
  if (!Number.isFinite(ms) || ms < 0) return fmtFecha(iso)
  const h = Math.floor(diasDesdeReferencia(iso, ahora) * 24)
  if (h < 1) return 'hace minutos'
  if (h < 24) return `hace ${h} h`
  return `hace ${Math.floor(h / 24)} d`
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

export function HoyDirectorio(): JSX.Element {
  const { ambito, equipo, actividades } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  const ahora = useAhora()

  // ── F1b: la auditoría ejecutiva se sirve del servidor (o del espejo demo
  // vivo). resumen_cartera_fn → KPIs, embudo, donut y descartes;
  // metricas_vendedores_fn.equipos → comparativa. Ambos comparten la ventana
  // de convertidos de 45 días (certificada por el wrapper). UNA asimetría
  // deliberada y ROTULADA: los descartes son histórico completo (el RPC no los
  // ventanea) mientras los convertidos van a 45 d — la tasa de descarte lo
  // declara en su sub; si molesta en la práctica, el arreglo es un campo
  // `descartes_45d` en el RPC (anotado en el vault), no ocultar el rótulo.
  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
  const resumen = resumenOp.resumen
  const vendedoresOp = useMetricasVendedoresOperativas([], equipo, ambito.leads, actividades)
  const filasEquipos = vendedoresOp.metricas?.equipos ?? null

  const r = useMemo(() => {
    if (!resumen) return null
    const cerrados = resumen.totales.convertidos + resumen.descartes.total
    // Embudo de trabajo: las 4 etapas activas del payload (convertidos y
    // descartados se auditan aparte); el % es presentación pura en cliente.
    const porEtapa = new Map(resumen.embudo.map((p) => [p.etapa, p.n]))
    const etapas = ETAPAS.map((e) => {
      const n = porEtapa.get(e.k) ?? 0
      return {
        etapa: e.k,
        n,
        pctDelTotal: resumen.totales.abiertos > 0
          ? Math.round((n / resumen.totales.abiertos) * 100)
          : 0,
      }
    })
    // Integridad de descartes: el label sale del catálogo del front; un motivo
    // fuera de catálogo se muestra con su clave cruda (no se pierde en silencio).
    const porMotivo = resumen.descartes.por_motivo.map((m) => ({
      k: m.motivo,
      label: MOTIVOS_DESCARTE.find((c) => c.k === m.motivo)?.label ?? m.motivo,
      n: m.n,
    }))
    return {
      cerrados,
      tasaDescarte: cerrados > 0 ? Math.round((resumen.descartes.total / cerrados) * 100) : 0,
      etapas,
      porMotivo,
    }
  }, [resumen])

  // La bitácora sigue en cliente (ninguna RPC F1 sirve un feed de actividad;
  // candidata a F2). Solo copia y ordena para las 8 filas que pinta.
  const recientes = useMemo(
    () => [...actividades].sort((a, b) => b.creado_en.localeCompare(a.creado_en)).slice(0, 8),
    [actividades],
  )

  const leadDe = (id: string) => ambito.leads.find((l) => l.id === id)

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Banner de auditoría — sobrio, sin acciones */}
      <div className="flex items-center gap-3 rounded-xl border border-border bg-primary/[0.04] px-4 py-3">
        <span className="ac-chip grid size-9 shrink-0 place-items-center rounded-lg" style={{ '--c': SEMAFORO.navy } as CSSProperties}>
          <Eye className="size-4" />
        </span>
        <div className="min-w-0">
          <p className="text-sm font-bold tracking-tight text-primary">Modo auditoría</p>
          <p className="text-xs text-muted-foreground">
            Visión integral de la operación comercial, solo lectura
          </p>
        </div>
        <Badge color={SEMAFORO.navy} variant="outline" className="ml-auto hidden sm:inline-flex">
          Directorio
        </Badge>
      </div>

      {Boolean(resumenOp.error || vendedoresOp.error) && !yo?.demo && (
        <div
          role="alert"
          className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/5 px-3 py-2 text-xs text-muted-foreground"
        >
          <span>No se pudieron cargar algunos indicadores de la operación. Se muestran «—» para no inventar cifras.</span>
          <button
            type="button"
            className="font-semibold text-foreground underline-offset-2 hover:underline"
            onClick={() => {
              if (resumenOp.error) void resumenOp.recargar()
              if (vendedoresOp.error) void vendedoresOp.recargar()
            }}
          >
            Reintentar
          </button>
        </div>
      )}

      {/* KPIs ejecutivos — servidos por resumen_cartera_fn; sin dato: «—» */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Capital en proceso"
          value={resumen ? money(resumen.capital.asignado.pen) : '—'}
          icon={Wallet}
          color={SEMAFORO.ok}
          sub={
            resumen && resumen.capital.asignado.usd > 0
              ? `Pipeline activo (PEN) · +${moneyK(resumen.capital.asignado.usd, 'USD')} en dólares`
              : 'Pipeline activo (PEN)'
          }
          delay={0}
        />
        <KpiCard
          label="Capital ganado"
          value={resumen ? money(resumen.capital.ganado.pen) : '—'}
          icon={BadgeCheck}
          color={SEMAFORO.navy}
          sub={
            resumen
              // Rótulo honesto desde el corte de 45 d (F0§5): el convertido
              // viejo ya vive como contrato en la cartera de clientes.
              ? resumen.capital.ganado.usd > 0
                ? `${resumen.totales.convertidos} convertidos · últimos 45 d · +${moneyK(resumen.capital.ganado.usd, 'USD')} en dólares`
                : `${resumen.totales.convertidos} convertidos · últimos 45 d (PEN)`
              : 'Convertidos de los últimos 45 días'
          }
          delay={60}
        />
        <KpiCard
          label="Leads activos"
          value={resumen ? String(resumen.totales.asignados) : '—'}
          icon={Users}
          color={SEMAFORO.violeta}
          sub={
            resumen
              ? resumen.totales.parkeados > 0
                ? `Con vendedor · +${resumen.totales.parkeados} por repartir · ${resumen.totales.vivos} en el ámbito`
                : `De ${resumen.totales.vivos} leads del ámbito operativo`
              : 'Ámbito operativo'
          }
          delay={120}
        />
        {/* Semáforo completo: azul sano <30 · ámbar 30–59 · rojo ≥60 */}
        <KpiCard
          label="Tasa de descarte"
          value={r ? `${r.tasaDescarte}%` : '—'}
          icon={XCircle}
          color={r == null ? SEMAFORO.ok : r.tasaDescarte >= 60 ? SEMAFORO.critico : r.tasaDescarte >= 30 ? SEMAFORO.atencion : SEMAFORO.ok}
          sub={resumen && r ? `${resumen.descartes.total} descartados (histórico) de ${r.cerrados} cierres (convertidos 45 d)` : 'Descartados sobre cierres'}
          delay={180}
        />
      </div>

      {/* Embudo + distribución por moneda */}
      <div className="grid gap-5 lg:grid-cols-5">
        <Card className="lg:col-span-3">
          <SectionHead
            icon={Filter}
            title="Embudo del pipeline"
            right={
              <span className="text-xs text-muted-foreground">
                {resumen ? `${resumen.totales.abiertos} leads abiertos` : '—'}
              </span>
            }
          />
          {/* Misma pieza de la casa (SegmentBar) que "Estado de los leads" en
              Gerencia y "Distribución por etapa" en Cartera — pantallas hermanas
              idénticas, distribución legible de un vistazo. */}
          <CardContent className="space-y-3">
            {r == null ? (
              // Sin payload NO se afirma «no hay leads»: no hay DATO — el
              // mismo contrato de degradación que las demás cards.
              <p className="py-4 text-center text-xs text-muted-foreground">
                {resumenOp.error
                  ? 'El embudo no está disponible en este momento.'
                  : 'Cargando el embudo del pipeline…'}
              </p>
            ) : r.etapas.some((e) => e.n > 0) ? (
              <>
                <SegmentBar
                  segments={r.etapas.map((e) => {
                    const info = ETAPA_INFO[e.etapa]
                    return {
                      label: info.label,
                      value: e.n,
                      color: info.color,
                      valTxt: `${e.n} · ${e.pctDelTotal}%`,
                    }
                  })}
                />
                <p className="pt-1 text-[11px] text-muted-foreground">
                  Solo etapas de trabajo — convertidos y descartados se auditan aparte.
                </p>
              </>
            ) : (
              <p className="py-4 text-center text-xs text-muted-foreground">
                No hay leads abiertos por ahora — cuando ingresen nuevos leads verás aquí su
                distribución por etapa.
              </p>
            )}
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <SectionHead icon={Coins} title="Distribución por moneda" />
          <CardContent>
            <Donut
              size={170}
              slices={[
                { label: 'Soles (PEN)', value: resumen?.totales.asignados_pen ?? 0, color: SEMAFORO.ok },
                { label: 'Dólares (USD)', value: resumen?.totales.asignados_usd ?? 0, color: SEMAFORO.violeta },
              ]}
              centerValue={resumen ? String(resumen.totales.asignados) : '—'}
              centerLabel="leads activos"
            />
            {/* Capitales SIEMPRE por separado — nunca un total PEN+USD.
                Mismo fetch que el tile de arriba: cuadran por construcción. */}
            <div className="mt-4 grid grid-cols-2 gap-2 border-t border-border pt-3 text-center">
              <div>
                <p className="text-sm font-extrabold tabular-nums text-primary">
                  {resumen ? moneyK(resumen.capital.asignado.pen) : '—'}
                </p>
                <p className="text-[11px] text-muted-foreground">Capital activo en soles</p>
              </div>
              <div>
                <p className="text-sm font-extrabold tabular-nums text-primary">
                  {resumen ? moneyK(resumen.capital.asignado.usd, 'USD') : '—'}
                </p>
                <p className="text-[11px] text-muted-foreground">Capital activo en dólares</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Comparativa de equipos — tabla sobria, sin acciones */}
      <Card>
        <SectionHead
          icon={UsersRound}
          title="Comparativa de equipos"
          right={
            <span className="text-xs text-muted-foreground">
              Por supervisor · capital en proceso
            </span>
          }
        />
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[680px] text-sm">
            <thead>
              <tr className="border-b border-border text-left text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                <th className="pb-2 pr-3 font-bold">Equipo</th>
                <th className="pb-2 pr-3 text-right font-bold">Vendedores</th>
                <th className="pb-2 pr-3 text-right font-bold">Activos</th>
                <th className="pb-2 pr-3 text-right font-bold">Capital (PEN)</th>
                <th className="pb-2 pr-3 text-right font-bold">Convertidos (45 d)</th>
                <th className="pb-2 pr-3 text-right font-bold">Conversión</th>
                <th className="pb-2 text-right font-bold">Por repartir</th>
              </tr>
            </thead>
            <tbody>
              {filasEquipos == null && (
                <tr>
                  <td colSpan={7} className="py-4 text-center text-xs text-muted-foreground">
                    {vendedoresOp.error
                      ? 'La comparativa no está disponible en este momento.'
                      : 'Cargando la comparativa de equipos…'}
                  </td>
                </tr>
              )}
              {(filasEquipos ?? []).map((f) => (
                <tr key={f.supervisor.perfil_id} className="border-b border-border/60 last:border-0">
                  <td className="py-2.5 pr-3">
                    <div className="flex items-center gap-2.5">
                      <Avatar nombre={f.supervisor.nombre_completo} color={SEMAFORO.violeta} className="size-7 text-[10px]" />
                      <span className="truncate font-semibold">{f.supervisor.nombre_completo}</span>
                    </div>
                  </td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{f.vendedores}</td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{f.activos}</td>
                  <td className="py-2.5 pr-3 text-right">
                    <span className="font-bold tabular-nums text-primary">{moneyK(f.capitalPEN)}</span>
                    {f.capitalUSD > 0 && (
                      <span className="block text-[11px] tabular-nums text-muted-foreground">
                        +{moneyK(f.capitalUSD, 'USD')}
                      </span>
                    )}
                  </td>
                  <td className="py-2.5 pr-3 text-right">
                    <span className="font-semibold tabular-nums" style={{ color: SEMAFORO.navy }}>{f.convertidos}</span>
                  </td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{f.conversion}%</td>
                  <td className="py-2.5 text-right">
                    {f.parkeados > 0 ? (
                      <Badge color={SEMAFORO.atencion}>{f.parkeados}</Badge>
                    ) : (
                      <span className="tabular-nums text-muted-foreground">0</span>
                    )}
                  </td>
                </tr>
              ))}
              {filasEquipos != null && filasEquipos.length === 0 && (
                <tr>
                  <td colSpan={7} className="py-4 text-center text-xs text-muted-foreground">
                    Sin supervisores activos en el equipo
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          <p className="pt-3 text-[11px] text-muted-foreground">
            Los leads por repartir (parkeados en bandeja del supervisor) no suman al capital
            hasta tener vendedor asignado.
          </p>
        </CardContent>
      </Card>

      {/* Integridad de descartes + actividad reciente */}
      <div className="grid gap-5 lg:grid-cols-2">
        <Card>
          <SectionHead
            icon={ShieldCheck}
            title="Integridad de descartes"
            right={
              resumen == null ? (
                <span className="text-xs text-muted-foreground">—</span>
              ) : resumen.descartes.sin_motivo > 0 ? (
                <Badge color={SEMAFORO.critico} dot>{resumen.descartes.sin_motivo} sin motivo</Badge>
              ) : (
                <Badge color={SEMAFORO.ok} dot>100% con motivo</Badge>
              )
            }
          />
          <CardContent className="space-y-3">
            {resumen == null || r == null ? (
              <p className="py-4 text-center text-xs text-muted-foreground">
                {resumenOp.error
                  ? 'La auditoría de descartes no está disponible en este momento.'
                  : 'Cargando la auditoría de descartes…'}
              </p>
            ) : resumen.descartes.total === 0 ? (
              <p className="py-4 text-center text-xs text-muted-foreground">
                No hay leads descartados en el histórico
              </p>
            ) : (
              <>
                {r.porMotivo.map((m) => {
                  const pct = Math.round((m.n / resumen.descartes.total) * 100)
                  return (
                    <div key={m.k}>
                      <div className="mb-1 flex items-baseline justify-between gap-2 text-sm">
                        <span className="text-foreground/85">{m.label}</span>
                        <span className="tabular-nums text-muted-foreground">
                          <span className="font-bold text-foreground">{m.n}</span> · {pct}%
                        </span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-muted">
                        <div
                          className="h-full rounded-full transition-[width] duration-500 ease-out"
                          style={{ width: `${pct}%`, background: SEMAFORO.atencion }}
                        />
                      </div>
                    </div>
                  )
                })}
                {resumen.descartes.sin_motivo > 0 && (
                  <p className="rounded-lg border px-3 py-2 text-xs font-semibold" style={{ borderColor: `color-mix(in srgb, ${SEMAFORO.critico} 40%, transparent)`, color: SEMAFORO.critico }}>
                    {resumen.descartes.sin_motivo} {resumen.descartes.sin_motivo === 1 ? 'descarte' : 'descartes'} sin motivo
                    registrado — hallazgo de auditoría
                  </p>
                )}
                <p className="pt-1 text-[11px] text-muted-foreground">
                  {resumen.descartes.total} descartes en total — todo descarte debe llevar motivo
                  del catálogo.
                </p>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <SectionHead
            icon={History}
            title="Actividad reciente"
            right={<span className="text-xs text-muted-foreground">Últimas 8 · toda la operación</span>}
          />
          <CardContent className="space-y-1">
            {recientes.length === 0 && (
              <p className="py-4 text-center text-xs text-muted-foreground">
                Aún no hay actividad registrada
              </p>
            )}
            {recientes.map((a) => {
              const Icono = ICONO_ACTIVIDAD[a.tipo]
              const lead = leadDe(a.lead_id)
              return (
                <button
                  key={a.id}
                  type="button"
                  onClick={() => abrirLead(a.lead_id)}
                  title="Abrir ficha (solo lectura)"
                  className="flex w-full cursor-pointer items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-muted"
                >
                  <span className="ac-chip grid size-8 shrink-0 place-items-center rounded-lg" style={{ '--c': a.tipo === 'conversion' ? SEMAFORO.navy : SEMAFORO.ok } as CSSProperties}>
                    <Icono className="size-4" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-semibold">
                      {lead?.nombre_completo ?? 'Lead fuera del ámbito'}
                    </span>
                    <span className="block truncate text-[11.5px] text-muted-foreground">
                      {TIPOS_ACTIVIDAD[a.tipo]} · {a.autor_nombre}
                    </span>
                  </span>
                  <span className="shrink-0 text-[11px] tabular-nums text-muted-foreground">
                    {haceCorto(a.creado_en, ahora)}
                  </span>
                </button>
              )
            })}
          </CardContent>
        </Card>
      </div>

      <p className="text-[11px] text-muted-foreground">
        Auditoría del directorio — ves toda la operación en modo solo lectura; este rol
        no realiza cambios.
      </p>
    </div>
  )
}
