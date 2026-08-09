import { useMemo, useState } from 'react'
import { Search, Users, TrendingUp, Activity, CheckCircle2, PieChart, ChevronRight, Inbox } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, SegmentBar, type StatChipData, type Segment } from '@/components/common/stat-strip'
import { PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ETAPAS, TERMINALES, ETAPA_INFO, MOTIVOS_DESCARTE, CAT_LABEL, origenLabel, type Etapa } from '@/lib/tipos'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { capitalPrincipal } from '@/lib/inteligencia'
import { money, fmtFecha } from '@/lib/format'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { paginar } from '@/lib/paginacion'
import { can } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'

const MOTIVO_LABEL: Record<string, string> = Object.fromEntries(MOTIVOS_DESCARTE.map((m) => [m.k, m.label]))

type FiltroEtapa = 'todas' | Etapa
/** 'todos' | 'sin_asignar' | perfil_id de un vendedor del ámbito. */
type FiltroVendedor = string

export function Cartera() {
  const { yo } = useAuth()
  const { ambito, actividadesDelAmbito } = useCRMData()
  const { abrirLead } = usePanelesActions()
  // Cartera consciente del rol (F1c): SIEMPRE el ámbito, nunca el global.
  const leads = ambito.leads
  // F1: los KPIs vienen del servidor (RPC resumen_cartera_fn) o del espejo demo
  // vivo — la pantalla ya no cuenta filas. La tabla de abajo sigue sobre el
  // ámbito (eso migra en F2 con keyset).
  const resumenOp = useResumenCarteraOperativo(leads, actividadesDelAmbito)
  const resumen = resumenOp.resumen
  const [q, setQ] = useState('')
  const [fEtapa, setFEtapa] = useState<FiltroEtapa>('todas')
  const [fVend, setFVend] = useState<FiltroVendedor>('todos')
  const [pagina, setPagina] = useState(0)
  // Columna "Vendedor" = ver al equipo; filtro por vendedor = capacidad aparte.
  const verVendedor = can(yo?.rol, 'verEquipo')
  const filtrarVendedor = can(yo?.rol, 'filtrarPorVendedor')

  // ── KPIs y distribución del ámbito (no dependen de los filtros) ──
  // Sin payload (cargando o RPC caída) los tiles dicen «—»: jamás se inventa
  // una cifra contando un array parcial del navegador.
  const { stats, segmentos } = useMemo(() => {
    if (!resumen) {
      const stats: StatChipData[] = [
        { icon: Users, label: 'Total leads', value: '—', tone: 'primary' },
        { icon: TrendingUp, label: 'Capital en juego', value: '—', tone: 'accent' },
        { icon: Activity, label: 'Activos', value: '—', tone: 'default', sub: 'Sin convertir ni descartar' },
        { icon: CheckCircle2, label: 'Convertidos', value: '—', tone: 'primary' },
      ]
      return { stats, segmentos: [] as Segment[] }
    }
    // El capital en juego se acota a los ABIERTOS (asignados + parkeados: esta
    // es la vista de inventario). El ganado no entra: ya vive como contrato en
    // la cartera de clientes y contarlo aquí lo duplicaría. La cifra grande es
    // la moneda que DE VERDAD tiene volumen (capitalPrincipal) — PEN y USD
    // JAMÁS se suman ni se convierten.
    const capital = capitalPrincipal(
      resumen.capital.asignado.pen + resumen.capital.parkeado.pen,
      resumen.capital.asignado.usd + resumen.capital.parkeado.usd,
    )
    const stats: StatChipData[] = [
      { icon: Users, label: 'Total leads', value: String(resumen.totales.vivos), tone: 'primary' },
      {
        icon: TrendingUp,
        label: 'Capital en juego',
        value: capital.valor,
        tone: 'accent',
        sub: capital.sub,
      },
      { icon: Activity, label: 'Activos', value: String(resumen.totales.abiertos), tone: 'default', sub: 'Sin convertir ni descartar' },
      { icon: CheckCircle2, label: 'Convertidos', value: String(resumen.totales.convertidos), tone: 'primary' },
    ]
    const porEtapa = new Map(resumen.embudo.map((p) => [p.etapa, p.n]))
    const segmentos: Segment[] = [...ETAPAS, ...TERMINALES].map((e) => ({
      label: e.label,
      value: porEtapa.get(e.k) ?? 0,
      color: e.color,
    }))
    return { stats, segmentos }
  }, [resumen])

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
  // Paginación compartida (lib/paginacion, testeada): clamp incluido — al
  // filtrar, la página vigente puede dejar de existir y no debe quedar en blanco.
  const { visibles, paginas, paginaActual } = paginar(items, pagina)

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* Mini-KPIs de la cartera */}
      <StatStrip stats={stats} />

      {/* Degradación honesta (precedente objetivosError): la pantalla vive con
          aviso y «—», sin bloquear la tabla, que tiene su propia fuente. */}
      {Boolean(resumenOp.error) && !yo?.demo && (
        <div
          role="alert"
          className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/5 px-3 py-2 text-xs text-muted-foreground"
        >
          <span>No se pudieron cargar los indicadores de la cartera. Se muestran «—» para no inventar cifras.</span>
          <button
            type="button"
            className="font-semibold text-foreground underline-offset-2 hover:underline"
            onClick={() => { void resumenOp.recargar() }}
          >
            Reintentar
          </button>
        </div>
      )}

      {/* Distribución por etapa */}
      <Card>
        <SectionHead
          icon={PieChart}
          title="Distribución por etapa"
          right={
            <span className="text-xs text-muted-foreground">
              {resumen ? `${resumen.totales.vivos} leads` : '—'}
            </span>
          }
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
            aria-label="Buscar en la cartera"
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
          <PanelVacio
            icono={Inbox}
            titulo="Sin resultados"
            detalle={
              q.trim()
                ? `Ningún lead coincide con “${q.trim()}”. Prueba con otro nombre o número.`
                : hayFiltro
                  ? `Ningún lead coincide con los filtros. Prueba con otra etapa${filtrarVendedor ? ' u otro vendedor' : ''}.`
                  : 'Tu cartera todavía no tiene leads.'
            }
          />
        ) : (
          <TablaEnvoltura ariaLabel="Cartera de leads">
            {/* Responsive por PRIORIDAD (mismo patrón de parejas th/td de
                Clientes y Contratos): en angosto cae primero Creado (xl) y
                luego Categoría (lg) — ambos siguen completos en el hover-card
                del lead. Lead, Etapa, Monto y Vendedor NUNCA se ocultan: son
                la operación y el capital en juego. */}
            <TheadCrm>
              <Th>Lead</Th>
              <Th>Etapa</Th>
              <Th className="text-right">Monto estimado</Th>
              {verVendedor && <Th>Vendedor</Th>}
              <Th className="hidden lg:table-cell">Categoría</Th>
              <Th className="hidden xl:table-cell">Creado</Th>
              <Th className="w-8" aria-hidden />
            </TheadCrm>
            <tbody>
              {visibles.map((l) => {
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
                      <Td>
                        <LeadHoverCard lead={l}>
                          <div className="flex items-center gap-2.5">
                            <Avatar nombre={l.nombre_completo} genero={l.genero ?? null} />
                            <div className="leading-tight">
                              {/* text-[13px]: misma densidad de nombre que FilaCliente/
                                  FilaContrato — las tres carteras leen como una familia. */}
                              <p className="text-[13px] font-semibold">{l.nombre_completo}</p>
                              <p className="text-xs tabular-nums text-muted-foreground">
                                {l.telefono}
                                {/* El ORIGEN vive aquí como sub-dato del lead (antes se
                                    colaba en la columna Categoría y rompía la comparación
                                    vertical); también sigue en el hover-card. */}
                                <span> · {origenLabel(l.origen)}</span>
                              </p>
                            </div>
                          </div>
                        </LeadHoverCard>
                      </Td>
                      <Td>
                        <div className="flex flex-col items-start gap-1">
                          <Badge color={e.color} dot>{e.label}</Badge>
                          {l.etapa === 'descartado' && l.motivo_descarte && (
                            <Badge color="var(--muted-foreground)">
                              {MOTIVO_LABEL[l.motivo_descarte] ?? l.motivo_descarte}
                            </Badge>
                          )}
                        </div>
                      </Td>
                      <Td className="text-right font-extrabold tabular-nums text-primary">
                        {l.monto_estimado != null ? money(l.monto_estimado, l.moneda) : '—'}
                      </Td>
                      {verVendedor && (
                        <Td>
                          {l.vendedor_nombre ? (
                            <span className="flex items-center gap-1.5">
                              <Avatar nombre={l.vendedor_nombre} className="size-6 text-[9px]" />
                              <span className="text-xs text-muted-foreground">{l.vendedor_nombre.split(' ')[0]}</span>
                            </span>
                          ) : (
                            <Badge color="var(--warning)">sin asignar</Badge>
                          )}
                        </Td>
                      )}
                      {/* Columna HOMOGÉNEA: solo la categoría de interés (Badge) o un
                          vacío honesto — el origen ya no se disfraza de categoría. */}
                      <Td className="hidden lg:table-cell">
                        {l.categoria_interes ? (
                          <Badge color="var(--chart-4)">{CAT_LABEL[l.categoria_interes]}</Badge>
                        ) : (
                          <span className="text-xs text-muted-foreground">—</span>
                        )}
                      </Td>
                      <Td className="hidden text-xs text-muted-foreground xl:table-cell">{fmtFecha(l.creado_en)}</Td>
                      <Td className="text-right">
                        <ChevronRight className="size-4 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100" />
                      </Td>
                    </tr>
                  )
                })}
              </tbody>
          </TablaEnvoltura>
        )}
      </Card>

      <Paginacion
        paginaActual={paginaActual}
        paginas={paginas}
        total={items.length}
        onCambio={setPagina}
        ariaLabel="Paginación de cartera"
      />

      {yo?.demo && (
        <p className="text-[11px] text-muted-foreground">
          Cartera de demostración — pronto verás aquí a tus clientes reales, lista para crecer con la operación.
        </p>
      )}
    </div>
  )
}
