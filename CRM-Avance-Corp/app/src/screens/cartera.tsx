import { useMemo, useState } from 'react'
import { Search, Users, TrendingUp, Activity, CheckCircle2, PieChart, ChevronRight, Inbox } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, SegmentBar, type StatChipData, type Segment } from '@/components/common/stat-strip'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { PanelVacio } from '@/components/common/estado-panel'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ETAPAS, TERMINALES, ETAPA_INFO, MOTIVOS_DESCARTE, CAT_LABEL, origenLabel, type Etapa } from '@/lib/tipos'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { capitalPrincipal } from '@/lib/inteligencia'
import { money, fmtFecha } from '@/lib/format'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { useCarteraPaginada } from '@/data/use-cartera-paginada'
import { useCierresEstado } from '@/data/crm-queries'
import { estadoDelCierre, indexarCierresEstado } from '@/lib/cierre-estado'
import { ChipAnulado } from '@/components/app/chip-anulado'
import { useValorDiferido } from '@/lib/use-valor-diferido'
import { can } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'
import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
import { LeadsRecibidosAnalistaCard } from '@/components/app/leads-recibidos-analista'

const MOTIVO_LABEL: Record<string, string> = Object.fromEntries(MOTIVOS_DESCARTE.map((m) => [m.k, m.label]))

type FiltroEtapa = 'todas' | Etapa
/** 'todos' | 'sin_asignar' | perfil_id de un analista del ámbito. */
type FiltroVendedor = string

export function Cartera() {
  const { yo } = useAuth()
  const memoriaGerencia = useConsultaGerencia()
  const desdeRendimiento = yo?.rol === 'gerencia' ? memoriaGerencia?.consulta.gestionAnalista : null
  const { ambito, actividadesDelAmbito, cierresEstado } = useCRMData()
  const { abrirLead } = usePanelesActions()
  // Cartera consciente del rol (F1c): SIEMPRE el ámbito, nunca el global.
  const leads = ambito.leads
  // F1: los KPIs vienen del servidor (RPC resumen_cartera_fn) o del espejo demo
  // vivo — la pantalla ya no cuenta filas.
  const resumenOp = useResumenCarteraOperativo(leads, actividadesDelAmbito)
  const resumen = resumenOp.resumen
  const [q, setQ] = useState('')
  const [fEtapa, setFEtapa] = useState<FiltroEtapa>('todas')
  const [fVend, setFVend] = useState<FiltroVendedor>(() => can(yo?.rol, 'filtrarPorVendedor') ? desdeRendimiento?.id ?? 'todos' : 'todos')
  // Columna "Analista" = ver al equipo; filtro por analista = capacidad aparte.
  const verVendedor = can(yo?.rol, 'verEquipo')
  const filtrarVendedor = can(yo?.rol, 'filtrarPorVendedor')

  // F2: la TABLA ya no sale del store. Se pagina por cursor keyset contra el
  // servidor y los tres filtros viajan con la consulta — con keyset, filtrar en
  // el navegador lo ya descargado produce vacíos falsos. El texto se difiere
  // para no lanzar una consulta por tecla.
  const qDiferido = useValorDiferido(q)
  const cartera = useCarteraPaginada(
    leads,
    useMemo(
      () => ({ etapa: fEtapa, vendedorId: fVend, texto: qDiferido }),
      [fEtapa, fVend, qDiferido],
    ),
  )

  // ── KPIs y distribución del ámbito (no dependen de los filtros) ──
  // Sin payload (cargando o RPC caída) los tiles dicen «—»: jamás se inventa
  // una cifra contando un array parcial del navegador.
  const { stats, segmentos } = useMemo(() => {
    if (!resumen) {
      const stats: StatChipData[] = [
        { icon: Users, label: 'Total leads', value: '—', tone: 'primary' },
        { icon: TrendingUp, label: 'Capital en juego', value: '—', tone: 'accent' },
        { icon: Activity, label: 'Activos', value: '—', tone: 'default', sub: 'Sin convertir ni descartar' },
        { icon: CheckCircle2, label: 'Cierres de leads del mes', value: '—', tone: 'primary', sub: 'Mes calendario actual' },
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
      { icon: CheckCircle2, label: 'Cierres de leads del mes', value: String(resumen.totales.convertidos), tone: 'primary', sub: 'Mes calendario actual' },
    ]
    const porEtapa = new Map(resumen.embudo.map((p) => [p.etapa, p.n]))
    const segmentos: Segment[] = [...ETAPAS, ...TERMINALES].map((e) => ({
      label: e.label,
      value: porEtapa.get(e.k) ?? 0,
      color: e.color,
    }))
    return { stats, segmentos }
  }, [resumen])

  const hayFiltro = q.trim() !== '' || fEtapa !== 'todas' || fVend !== 'todos'

  // El nombre del analista lo resuelve el roster: `crm.leads` guarda el id y la
  // RPC de la página no lo desnormaliza (el store hace lo mismo con su ámbito).
  const nombrePorId = useMemo(
    () => new Map(ambito.vendedores.map((m) => [m.perfil_id, m.nombre_completo])),
    [ambito.vendedores],
  )
  const visibles = useMemo(
    () => cartera.leads.map((l) => ({
      ...l,
      vendedor_nombre: l.vendedor_nombre
        ?? (l.vendedor_id ? nombrePorId.get(l.vendedor_id) ?? null : null),
    })),
    [cartera.leads, nombrePorId],
  )

  // La marca de «cierre anulado». Se pregunta SOLO por los convertidos: son los
  // únicos que pueden tener un cierre que anular, y así el lote no crece con
  // filas que nunca van a responder nada.
  // En real es la ÚNICA vía posible (la tabla de anulaciones no se lee desde la
  // Data API, a propósito); en demo sale derivada del store con la misma forma.
  const idsConvertidos = useMemo(
    () => visibles.filter((l) => l.etapa === 'convertido').map((l) => l.id),
    [visibles],
  )
  const consultaEstado = useCierresEstado(!yo?.demo, idsConvertidos)
  const estadoPorLead = useMemo(
    () => indexarCierresEstado(yo?.demo ? cierresEstado : (consultaEstado.data ?? [])),
    [yo?.demo, cierresEstado, consultaEstado.data],
  )

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {desdeRendimiento && <section aria-label="Consulta desde Rendimiento" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card p-4">
        <div className="min-w-0">
          <h2 className="text-sm font-bold">Leads de {desdeRendimiento.nombre}</h2>
          <p className="mt-1 text-xs text-muted-foreground">Listado actual, con todas las etapas. Los indicadores superiores conservan el ámbito general; el mes de Rendimiento no filtra esta lista.</p>
          {fVend !== desdeRendimiento.id && <p role="status" className="mt-1 text-xs">Cambiaste el filtro del listado. La consulta original de Rendimiento se conserva al volver.</p>}
        </div>
        <a href="#/rendimiento" className="inline-flex min-h-11 items-center rounded-lg border border-input px-3 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2" onClick={() => memoriaGerencia?.setConsulta((actual) => ({ ...actual, gestionAnalista: null }))}>Volver a Rendimiento</a>
      </section>}
      {yo?.rol === 'vendedor' && (
        <LeadsRecibidosAnalistaCard
          analistaId={yo.id}
          demo={yo.demo === true}
          leads={leads}
        />
      )}
      {/* Mini-KPIs de la cartera */}
      <StatStrip stats={stats} />
      <p className="text-xs text-muted-foreground">
        {ambito.esGlobal ? 'Indicadores de toda la empresa.' : 'Indicadores de tu ámbito.'} La búsqueda y los filtros sólo cambian el listado, no los indicadores ni la distribución.
      </p>

      {/* Degradación honesta (precedente objetivosError): la pantalla vive con
          aviso y «—», sin bloquear la tabla, que tiene su propia fuente. */}
      <AvisoDegradacion
        activo={Boolean(resumenOp.error) && !yo?.demo}
        queReintenta="de los indicadores de la cartera"
        onReintentar={() => { void resumenOp.recargar() }}
      >
        No se pudieron cargar los indicadores de la cartera. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

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
          <p className="mt-3 text-xs text-muted-foreground">Inventario actual por etapa. Los convertidos permanecen aquí durante 45 días desde su conversión; no equivalen a los cierres del mes.</p>
        </CardContent>
      </Card>

      {/* Buscador + filtro por etapa (+ analista si el rol puede) */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative w-full max-w-sm">
          <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            aria-label="Buscar en la cartera"
            placeholder="Buscar por nombre, teléfono o DNI…"
            className="pl-9"
            value={q}
            onChange={(e) => { setQ(e.target.value) }}
          />
        </div>
        <div className="w-[190px]">
          <Select aria-label="Filtrar por etapa" value={fEtapa} onChange={(e) => { setFEtapa(e.target.value as FiltroEtapa) }}>
            <option value="todas">Todas las etapas</option>
            {[...ETAPAS, ...TERMINALES].map((e) => (
              <option key={e.k} value={e.k}>{e.label}</option>
            ))}
          </Select>
        </div>
        {filtrarVendedor && (
          <div className="w-[210px]">
            <Select aria-label="Filtrar por analista" value={fVend} onChange={(e) => { setFVend(e.target.value) }}>
              <option value="todos">Todos los analistas</option>
              {desdeRendimiento && !ambito.vendedores.some((miembro) => miembro.perfil_id === desdeRendimiento.id) && <option value={desdeRendimiento.id}>{desdeRendimiento.nombre} · fuera del listado actual de analistas</option>}
              {ambito.vendedores.map((m) => (
                <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>
              ))}
              <option value="sin_asignar">Sin asignar</option>
            </Select>
          </div>
        )}
        {/* Con keyset NO existe un "de M": el total lo dice el tile servido, y
            aquí solo se puede afirmar lo que de verdad se ha traído. Decir «12
            de 300» contando un array parcial es justo la mentira que esta fase
            viene a matar. */}
        {hayFiltro && !cartera.cargando && (
          <span className="text-xs tabular-nums text-muted-foreground" aria-live="polite">
            {cartera.hayMas
              ? `${visibles.length} cargados`
              : `${visibles.length} ${visibles.length === 1 ? 'resultado' : 'resultados'}`}
          </span>
        )}
      </div>

      {/* Degradación de la TABLA: distinta de la de los tiles — aquí lo que
          falta son filas, y con páginas ya cargadas la lista sigue siendo
          operable (incompleta, pero honesta: `hayMas` queda en false y este
          aviso explica por qué). */}
      <AvisoDegradacion
        activo={Boolean(cartera.error)}
        queReintenta="de la lista de leads"
        onReintentar={() => { void cartera.recargar() }}
      >
        {visibles.length > 0
          ? 'No se pudo cargar el resto de la cartera. Lo que ves está completo hasta donde llegó la última página.'
          : 'No se pudo cargar la lista de leads.'}
      </AvisoDegradacion>

      {/* Tabla de cartera */}
      <Card className="overflow-hidden">
        {cartera.cargando ? (
          <PanelVacio
            icono={Inbox}
            titulo="Cargando la cartera…"
            detalle="Trayendo la primera página de leads."
          />
        ) : visibles.length === 0 ? (
          <PanelVacio
            icono={Inbox}
            titulo="Sin resultados"
            detalle={
              cartera.error
                ? 'No se pudo cargar la cartera. Usa «Reintentar» en el aviso de arriba.'
                : q.trim()
                  ? `Ningún lead coincide con “${q.trim()}”. Prueba con otro nombre o número.`
                  : hayFiltro
                    ? `Ningún lead coincide con los filtros. Prueba con otra etapa${filtrarVendedor ? ' u otro analista' : ''}.`
                    : 'Tu cartera todavía no tiene leads.'
            }
          />
        ) : (
          <TablaEnvoltura ariaLabel="Cartera de leads">
            {/* Responsive por PRIORIDAD (mismo patrón de parejas th/td de
                Clientes y Contratos): en angosto cae primero Creado (xl) y
                luego Categoría (lg) — ambos siguen completos en el hover-card
                del lead. Lead, Etapa, Monto y Analista NUNCA se ocultan: son
                la operación y el capital en juego. */}
            <TheadCrm>
              <Th>Lead</Th>
              <Th>Etapa</Th>
              <Th className="text-right">Monto estimado</Th>
              {verVendedor && <Th>Analista</Th>}
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
                          {/* «CIERRE ANULADO» y no «ANULADO» a secas: aquí lo que
                              se lista son leads, y el lead NO está anulado —
                              sigue convertido y el cliente sigue siendo cliente.
                              Lo que dejó de contar es el mérito. */}
                          {l.etapa === 'convertido'
                            && estadoDelCierre(estadoPorLead.get(l.id)).anulado && (
                            <ChipAnulado etiqueta="CIERRE ANULADO" />
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

      {/* «Cargar más» en vez de páginas numeradas: con cursor keyset no existe
          la página 7 — existe "lo siguiente a lo que ya tengo". Ir a una página
          arbitraria exigiría el `count: 'exact'` que esta fase elimina. */}
      {cartera.hayMas && (
        <div className="flex justify-center">
          <Button
            variant="outline"
            onClick={cartera.cargarMas}
            disabled={cartera.cargandoMas}
            aria-busy={cartera.cargandoMas}
          >
            {cartera.cargandoMas ? 'Cargando…' : 'Cargar más leads'}
          </Button>
        </div>
      )}

      {yo?.demo && (
        <p className="text-[11px] text-muted-foreground">
          Cartera de demostración — pronto verás aquí a tus clientes reales, lista para crecer con la operación.
        </p>
      )}
    </div>
  )
}
