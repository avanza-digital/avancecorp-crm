import { useMemo, useState, type CSSProperties } from 'react'
import { Search, Users, TrendingUp, Activity, CheckCircle2, PieChart, ChevronRight, Inbox } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, SegmentBar, type StatChipData, type Segment } from '@/components/common/stat-strip'
import { ETAPAS, TERMINALES, ETAPA_INFO, MOTIVOS_DESCARTE, CAT_LABEL, origenLabel, type Etapa } from '@/lib/tipos'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { capitalPorMoneda } from '@/lib/inteligencia'
import { money, moneyK, fmtFecha } from '@/lib/format'
import { can } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'

const MOTIVO_LABEL: Record<string, string> = Object.fromEntries(MOTIVOS_DESCARTE.map((m) => [m.k, m.label]))
const PAGE_SIZE = 50

type FiltroEtapa = 'todas' | Etapa
/** 'todos' | 'sin_asignar' | perfil_id de un vendedor del ámbito. */
type FiltroVendedor = string

export function Cartera() {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const { abrirLead } = usePanelesActions()
  // Cartera consciente del rol (F1c): SIEMPRE el ámbito, nunca el global.
  const leads = ambito.leads
  const [q, setQ] = useState('')
  const [fEtapa, setFEtapa] = useState<FiltroEtapa>('todas')
  const [fVend, setFVend] = useState<FiltroVendedor>('todos')
  const [pagina, setPagina] = useState(0)
  // Columna "Vendedor" = ver al equipo; filtro por vendedor = capacidad aparte.
  const verVendedor = can(yo?.rol, 'verEquipo')
  const filtrarVendedor = can(yo?.rol, 'filtrarPorVendedor')

  // ── KPIs y distribución de la cartera del ámbito (no dependen de los filtros) ──
  const { stats, segmentos } = useMemo(() => {
    // esAbierto (lib/inteligencia): vivo (l.activo) y en etapa de trabajo.
    const activos = leads.filter((l) => l.activo && !['convertido', 'descartado'].includes(l.etapa))
    const convertidos = leads.filter((l) => l.etapa === 'convertido')
    // Los totales NO mezclan monedas: PEN es el principal y USD va aparte.
    const { pen: capitalPEN, usd: capitalUSD } = capitalPorMoneda(leads)
    const stats: StatChipData[] = [
      { icon: Users, label: 'Total leads', value: String(leads.length), tone: 'primary' },
      {
        icon: TrendingUp,
        label: 'Capital total',
        value: money(capitalPEN),
        tone: 'accent',
        sub: capitalUSD > 0 ? `PEN · +${moneyK(capitalUSD, 'USD')}` : 'PEN',
      },
      { icon: Activity, label: 'Activos', value: String(activos.length), tone: 'default', sub: 'Sin convertir ni descartar' },
      { icon: CheckCircle2, label: 'Convertidos', value: String(convertidos.length), tone: 'primary' },
    ]
    const segmentos: Segment[] = [...ETAPAS, ...TERMINALES].map((e) => ({
      label: e.label,
      value: leads.filter((l) => l.etapa === e.k).length,
      color: e.color,
    }))
    return { stats, segmentos }
  }, [leads])

  // ── Filtro: etapa + vendedor + búsqueda por nombre / teléfono / DNI ──
  const items = useMemo(() => {
    const texto = q.trim().toLowerCase()
    const digitos = q.replace(/\D/g, '')
    return leads.filter((l) => {
      if (fEtapa !== 'todas' && l.etapa !== fEtapa) return false
      if (fVend === 'sin_asignar') {
        if (l.vendedor_id != null) return false
      } else if (fVend !== 'todos' && l.vendedor_id !== fVend) {
        return false
      }
      if (!texto) return true
      if (l.nombre_completo.toLowerCase().includes(texto)) return true
      if (digitos.length > 0 && l.telefono.replace(/\D/g, '').includes(digitos)) return true
      if (digitos.length > 0 && (l.dni ?? '').includes(digitos)) return true
      return false
    })
  }, [leads, q, fEtapa, fVend])

  const hayFiltro = q.trim() !== '' || fEtapa !== 'todas' || fVend !== 'todos'
  const paginas = Math.max(1, Math.ceil(items.length / PAGE_SIZE))
  const paginaActual = Math.min(pagina, paginas - 1)
  const itemsPagina = items.slice(paginaActual * PAGE_SIZE, (paginaActual + 1) * PAGE_SIZE)

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* Mini-KPIs de la cartera */}
      <StatStrip stats={stats} />

      {/* Distribución por etapa */}
      <Card>
        <SectionHead
          icon={PieChart}
          title="Distribución por etapa"
          right={<span className="text-xs text-muted-foreground">{leads.length} leads</span>}
        />
        <CardContent className="pt-1">
          <SegmentBar segments={segmentos} />
        </CardContent>
      </Card>

      {/* Buscador + filtro por etapa (+ vendedor si el rol puede) */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative w-full max-w-sm">
          <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Buscar por nombre, teléfono o DNI…"
            className="pl-9"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPagina(0) }}
          />
        </div>
        <div className="w-[190px]">
          <Select aria-label="Filtrar por etapa" value={fEtapa} onChange={(e) => { setFEtapa(e.target.value as FiltroEtapa); setPagina(0) }}>
            <option value="todas">Todas las etapas</option>
            {[...ETAPAS, ...TERMINALES].map((e) => (
              <option key={e.k} value={e.k}>{e.label}</option>
            ))}
          </Select>
        </div>
        {filtrarVendedor && (
          <div className="w-[210px]">
            <Select aria-label="Filtrar por vendedor" value={fVend} onChange={(e) => { setFVend(e.target.value); setPagina(0) }}>
              <option value="todos">Todos los vendedores</option>
              {ambito.vendedores.map((m) => (
                <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>
              ))}
              <option value="sin_asignar">Sin asignar</option>
            </Select>
          </div>
        )}
        {hayFiltro && (
          <span className="text-xs tabular-nums text-muted-foreground">
            {items.length} de {leads.length}
          </span>
        )}
      </div>

      {/* Tabla de cartera */}
      <Card className="overflow-hidden">
        {items.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 px-6 py-16 text-center">
            <span className="ac-chip grid size-11 place-items-center rounded-2xl" style={{ '--c': 'var(--muted-foreground)' } as CSSProperties}>
              <Inbox className="size-5" />
            </span>
            <p className="text-sm font-semibold text-foreground">Sin resultados</p>
            <p className="max-w-xs text-xs text-muted-foreground">
              {q.trim()
                ? `Ningún lead coincide con “${q.trim()}”. Prueba con otro nombre o número.`
                : hayFiltro
                  ? `Ningún lead coincide con los filtros. Prueba con otra etapa${filtrarVendedor ? ' u otro vendedor' : ''}.`
                  : 'Tu cartera todavía no tiene leads.'}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  <th className="px-4 py-3">Lead</th>
                  <th className="px-4 py-3">Etapa</th>
                  <th className="px-4 py-3 text-right">Monto estimado</th>
                  {verVendedor && <th className="px-4 py-3">Vendedor</th>}
                  <th className="px-4 py-3">Categoría</th>
                  <th className="px-4 py-3">Creado</th>
                  <th className="w-8 px-4 py-3" aria-hidden />
                </tr>
              </thead>
              <tbody>
                {itemsPagina.map((l) => {
                  const e = ETAPA_INFO[l.etapa]
                  return (
                    <tr
                      key={l.id}
                      tabIndex={0}
                      // aria-label sobre role="row" (role="button" rompería la semántica de tabla)
                      aria-label={`Abrir ficha de ${l.nombre_completo}`}
                      onClick={() => abrirLead(l.id)}
                      onKeyDown={(ev) => {
                        if (ev.key === 'Enter' || ev.key === ' ') {
                          ev.preventDefault()
                          abrirLead(l.id)
                        }
                      }}
                      className="group cursor-pointer border-b border-border/60 transition-colors last:border-0 hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                    >
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2.5">
                          <Avatar nombre={l.nombre_completo} />
                          <div className="leading-tight">
                            <p className="font-semibold">{l.nombre_completo}</p>
                            <p className="text-xs tabular-nums text-muted-foreground">{l.telefono}</p>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex flex-col items-start gap-1">
                          <Badge color={e.color} dot>{e.label}</Badge>
                          {l.etapa === 'descartado' && l.motivo_descarte && (
                            <Badge color="var(--muted-foreground)">
                              {MOTIVO_LABEL[l.motivo_descarte] ?? l.motivo_descarte}
                            </Badge>
                          )}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-right font-extrabold tabular-nums text-primary">
                        {l.monto_estimado != null ? money(l.monto_estimado, l.moneda) : '—'}
                      </td>
                      {verVendedor && (
                        <td className="px-4 py-3">
                          {l.vendedor_nombre ? (
                            <span className="flex items-center gap-1.5">
                              <Avatar nombre={l.vendedor_nombre} className="size-6 text-[9px]" />
                              <span className="text-xs text-muted-foreground">{l.vendedor_nombre.split(' ')[0]}</span>
                            </span>
                          ) : (
                            <Badge color="var(--warning)">sin asignar</Badge>
                          )}
                        </td>
                      )}
                      <td className="px-4 py-3">
                        {l.categoria_interes ? (
                          <Badge color="var(--chart-4)">{CAT_LABEL[l.categoria_interes]}</Badge>
                        ) : (
                          <span className="text-xs text-muted-foreground">{origenLabel(l.origen)}</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-xs text-muted-foreground">{fmtFecha(l.creado_en)}</td>
                      <td className="px-4 py-3 text-right">
                        <ChevronRight className="size-4 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100" />
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {items.length > PAGE_SIZE && (
        <nav className="flex items-center justify-between gap-3" aria-label="Paginación de cartera">
          <p className="text-xs tabular-nums text-muted-foreground">
            Página {paginaActual + 1} de {paginas} · {items.length} registros
          </p>
          <div className="flex gap-2">
            <button
              type="button"
              className="rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"
              disabled={paginaActual === 0}
              onClick={() => setPagina((p) => Math.max(0, p - 1))}
            >
              Anterior
            </button>
            <button
              type="button"
              className="rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"
              disabled={paginaActual >= paginas - 1}
              onClick={() => setPagina((p) => Math.min(paginas - 1, p + 1))}
            >
              Siguiente
            </button>
          </div>
        </nav>
      )}

      {yo?.demo && (
        <p className="text-[11px] text-muted-foreground">
          Cartera de demostración — pronto verás aquí a tus clientes reales, lista para crecer con la operación.
        </p>
      )}
    </div>
  )
}
