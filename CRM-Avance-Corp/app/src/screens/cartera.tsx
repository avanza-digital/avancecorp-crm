import { useEffect, useMemo, useState } from 'react'
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
import { ETAPAS, TERMINALES, ETAPA_INFO, MOTIVOS_DESCARTE, CAT_LABEL, ORIGENES, ORIGENES_HEREDADOS, origenLabel, type Etapa, type Origen, type Procedencia } from '@/lib/tipos'
import { ChipProcedencia } from '@/components/app/procedencia-chip'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { capitalPrincipal } from '@/lib/inteligencia'
import { money, fmtFecha } from '@/lib/format'
import { useCarteraPaginada } from '@/data/use-cartera-paginada'
import { useCierresEstado } from '@/data/crm-queries'
import { estadoDelCierre, indexarCierresEstado } from '@/lib/cierre-estado'
import { ChipAnulado } from '@/components/app/chip-anulado'
import { useValorDiferido } from '@/lib/use-valor-diferido'
import { can } from '@/lib/roles'
import { useAuth } from '@/lib/auth-context'
import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
import { FiltroFechaCartera } from '@/components/common/filtro-fecha-cartera'
import { fechaLima } from '@/lib/agenda-derivada'
import { desplazarFechaDerivaciones } from '@/lib/use-periodo-derivaciones'
import { fechaRecepcionDemo, periodoFechaCartera, rangoFechaCarteraValido, type ModoFechaCartera } from '@/lib/filtro-fecha-cartera'

const MOTIVO_LABEL: Record<string, string> = Object.fromEntries(MOTIVOS_DESCARTE.map((m) => [m.k, m.label]))

type FiltroEtapa = 'todas' | Etapa
/** 'todos' | un origen del catálogo completo (vigentes e históricos). */
type FiltroOrigen = 'todos' | Origen
/** 'todas' | sistema (puente) | manual (registrado por una persona). */
type FiltroProcedencia = 'todas' | Procedencia

/** Texto de la procedencia para el lector de pantalla; undefined si no viaja. */
function descripcionProcedencia(l: { procedencia?: Procedencia | null; cargado_por_nombre?: string | null }): string | undefined {
  if (l.procedencia === 'manual') return `Registro manual${l.cargado_por_nombre ? `, por ${l.cargado_por_nombre}` : ''}`
  if (l.procedencia === 'sistema') return 'Del sistema'
  return undefined
}
/** 'todos' | 'sin_asignar' | perfil_id de un analista del ámbito. */
type FiltroVendedor = string

export function Cartera() {
  const { yo } = useAuth()
  const memoriaGerencia = useConsultaGerencia()
  const desdeRendimiento = yo?.rol === 'gerencia' ? memoriaGerencia?.consulta.gestionAnalista : null
  const { ambito, cierresEstado, conocerLeads } = useCRMData()
  const { abrirLead } = usePanelesActions()
  // Cartera consciente del rol (F1c): SIEMPRE el ámbito, nunca el global.
  const leads = ambito.leads
  const [hoy] = useState(() => fechaLima(Date.now()))
  const [modoFecha, setModoFecha] = useState<ModoFechaCartera>('todas')
  const [rangoFecha, setRangoFecha] = useState(() => ({ desde: desplazarFechaDerivaciones(hoy, -6), hasta: hoy }))
  const periodo = useMemo(() => periodoFechaCartera(modoFecha, rangoFecha, hoy), [modoFecha, rangoFecha, hoy])
  const rangoValido = rangoFechaCarteraValido(periodo, hoy)
  const [q, setQ] = useState('')
  const [fEtapa, setFEtapa] = useState<FiltroEtapa>('todas')
  const [fOrigen, setFOrigen] = useState<FiltroOrigen>('todos')
  const [fProc, setFProc] = useState<FiltroProcedencia>('todas')
  const [fVend, setFVend] = useState<FiltroVendedor>(() => can(yo?.rol, 'filtrarPorVendedor') ? desdeRendimiento?.id ?? 'todos' : 'todos')
  // Columna "Analista" = ver al equipo; filtro por analista = capacidad aparte.
  const verVendedor = can(yo?.rol, 'verEquipo')
  const filtrarVendedor = can(yo?.rol, 'filtrarPorVendedor')
  // Supervisión mide la recepción de SUS analistas, no el ingreso a su bandeja.
  // Se recorta la colección demo completa antes de calcular KPIs o paginar.
  const soloRecibidosEquipo = periodo !== null
  const leadsDeConsulta = useMemo(() => {
    if (!soloRecibidosEquipo) return leads
    const analistas = new Set(ambito.vendedores.map((miembro) => miembro.perfil_id))
    return leads.filter((lead) => lead.vendedor_id != null && analistas.has(lead.vendedor_id))
  }, [soloRecibidosEquipo, leads, ambito.vendedores])

  // F2: la TABLA ya no sale del store. Se pagina por cursor keyset contra el
  // servidor y los tres filtros viajan con la consulta — con keyset, filtrar en
  // el navegador lo ya descargado produce vacíos falsos. El texto se difiere
  // para no lanzar una consulta por tecla.
  const qDiferido = useValorDiferido(q)
  const cartera = useCarteraPaginada(
    leadsDeConsulta,
    useMemo(
      () => ({ etapa: fEtapa, vendedorId: fVend, texto: qDiferido, origen: fOrigen, procedencia: fProc,
        recepcion: periodo }),
      [fEtapa, fVend, qDiferido, fOrigen, fProc, periodo],
    ),
  )
  // Fase 4e: el store conoce lo que la tabla muestra (verbos de escritura por id).
  useEffect(() => { if (yo && !yo.demo) conocerLeads(cartera.leads) }, [yo, conocerLeads, cartera.leads])
  const resumen = rangoValido ? cartera.resumen ?? null : null
  const etiquetaConvertidos = 'Convertidos'
  const detalleConvertidos = 'Dentro de los filtros elegidos'

  // Vista previa: KPIs y distribución de la misma colección filtrada completa.
  // Sin payload (cargando o RPC caída) los tiles dicen «—»: jamás se inventa
  // una cifra contando un array parcial del navegador.
  const { stats, segmentos } = useMemo(() => {
    if (!resumen) {
      const stats: StatChipData[] = [
        { icon: Users, label: 'Total leads', value: '—', tone: 'primary' },
        { icon: TrendingUp, label: 'Capital en juego', value: '—', tone: 'accent' },
        { icon: Activity, label: 'Activos', value: '—', tone: 'default', sub: 'Sin convertir ni descartar' },
        { icon: CheckCircle2, label: etiquetaConvertidos, value: '—', tone: 'primary', sub: detalleConvertidos },
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
      { icon: CheckCircle2, label: etiquetaConvertidos, value: String(resumen.totales.convertidos), tone: 'primary', sub: detalleConvertidos },
    ]
    const porEtapa = new Map(resumen.embudo.map((p) => [p.etapa, p.n]))
    const segmentos: Segment[] = [...ETAPAS, ...TERMINALES].map((e) => ({
      label: e.label,
      value: porEtapa.get(e.k) ?? 0,
      color: e.color,
    }))
    return { stats, segmentos }
  }, [resumen, etiquetaConvertidos, detalleConvertidos])

  const hayFiltro = q.trim() !== '' || fEtapa !== 'todas' || fOrigen !== 'todos' || fProc !== 'todas' || fVend !== 'todos' || modoFecha !== 'todas'

  // El nombre del analista lo resuelve el roster: `crm.leads` guarda el id y la
  // RPC de la página no lo desnormaliza (el store hace lo mismo con su ámbito).
  const nombrePorId = useMemo(
    () => new Map(ambito.vendedores.map((m) => [m.perfil_id, m.nombre_completo])),
    [ambito.vendedores],
  )
  const visibles = useMemo(
    () => (!rangoValido ? [] : cartera.leads).map((l) => ({
      ...l,
      vendedor_nombre: l.vendedor_nombre
        ?? (l.vendedor_id ? nombrePorId.get(l.vendedor_id) ?? null : null),
      // El autor del alta se resuelve con el mismo equipo visible; si no está
      // (alguien fuera del ámbito), el chip dice solo «Manual».
      cargado_por_nombre: l.cargado_por_nombre
        ?? (l.cargado_por ? nombrePorId.get(l.cargado_por) ?? null : null),
    })),
    [cartera.leads, nombrePorId, rangoValido],
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
          <p className="mt-1 text-xs text-muted-foreground">Listado e indicadores del analista seleccionado. El mes de Rendimiento no filtra esta lista; puedes elegir aquí el rango de recepción.</p>
          {fVend !== desdeRendimiento.id && <p role="status" className="mt-1 text-xs">Cambiaste el filtro del listado. La consulta original de Rendimiento se conserva al volver.</p>}
        </div>
        <a href="#/rendimiento" className="inline-flex min-h-11 items-center rounded-lg border border-input px-3 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2" onClick={() => memoriaGerencia?.setConsulta((actual) => ({ ...actual, gestionAnalista: null }))}>Volver a Rendimiento</a>
      </section>}
      {/* Mini-KPIs de la cartera */}
      <StatStrip stats={stats} />
      <p className="text-xs text-muted-foreground">
        Los filtros actualizan juntos el listado, los indicadores y la distribución por etapa.
      </p>


      {/* Distribución por etapa */}
      <Card>
        <SectionHead
          icon={PieChart}
          title="Distribución por etapa"
          right={
            <span className="text-xs text-muted-foreground">
              {resumen ? `${resumen.totales.vivos} ${resumen.totales.vivos === 1 ? 'lead' : 'leads'}` : '—'}
            </span>
          }
        />
        <CardContent className="pt-1">
          <SegmentBar segments={segmentos} />
          <p className="mt-3 text-xs text-muted-foreground">Etapa actual de los mismos leads que aparecen en el listado filtrado.</p>
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
        {/* Origen: los 5 vigentes arriba; los 3 históricos (web, campaña,
            WhatsApp) agrupados aparte para poder consultar leads antiguos sin
            que parezcan opciones de alta. Mismo catálogo que valida la RPC. */}
        <div className="w-[190px]">
          <Select aria-label="Filtrar por origen" value={fOrigen} onChange={(e) => { setFOrigen(e.target.value as FiltroOrigen) }}>
            <option value="todos">Todos los orígenes</option>
            {ORIGENES.map((o) => (
              <option key={o.k} value={o.k}>{o.label}</option>
            ))}
            <optgroup label="Históricos">
              {ORIGENES_HEREDADOS.map((o) => (
                <option key={o.k} value={o.k}>{o.label}</option>
              ))}
            </optgroup>
          </Select>
        </div>
        {/* Procedencia: quién lo metió (puente vs. persona). Es otra pregunta que
            el origen: desde el 01/09 un LANDING puede haberlo cargado un analista. */}
        <div className="w-[190px]">
          <Select aria-label="Filtrar por procedencia" value={fProc} onChange={(e) => { setFProc(e.target.value as FiltroProcedencia) }}>
            <option value="todas">Sistema y manual</option>
            <option value="sistema">Solo del sistema</option>
            <option value="manual">Solo registro manual</option>
          </Select>
        </div>
        <FiltroFechaCartera modo={modoFecha} rango={rangoFecha} hoy={hoy}
          invalido={!rangoValido} onModo={(modo) => {
            setModoFecha(modo)
            if (modo !== 'todas' && fVend === 'sin_asignar') setFVend('todos')
          }} onRango={setRangoFecha} />
        {filtrarVendedor && (
          <div className="w-[210px]">
            <Select aria-label="Filtrar por analista" value={fVend} onChange={(e) => { setFVend(e.target.value) }}>
              <option value="todos">Todos los analistas</option>
              {desdeRendimiento && !ambito.vendedores.some((miembro) => miembro.perfil_id === desdeRendimiento.id) && <option value={desdeRendimiento.id}>{desdeRendimiento.nombre} · fuera del listado actual de analistas</option>}
              {ambito.vendedores.map((m) => (
                <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>
              ))}
              {!soloRecibidosEquipo && <option value="sin_asignar">Sin asignar</option>}
            </Select>
          </div>
        )}
        {/* Con keyset NO existe un "de M": el total lo dice el tile servido, y
            aquí solo se puede afirmar lo que de verdad se ha traído. Decir «12
            de 300» contando un array parcial es justo la mentira que esta fase
            viene a matar. */}
        {hayFiltro && <Button variant="ghost" size="sm" onClick={() => {
          setQ(''); setFEtapa('todas'); setFOrigen('todos'); setFProc('todas'); setFVend('todos'); setModoFecha('todas')
        }}>Limpiar filtros</Button>}
        {rangoValido && !cartera.cargando && (
          <span className="text-xs tabular-nums text-muted-foreground" aria-live="polite">
            {resumen
              ? `${resumen.totales.vivos} ${resumen.totales.vivos === 1 ? 'lead' : 'leads'}${cartera.hayMas ? ` · ${visibles.length} visibles` : ''}`
              : cartera.hayMas
              ? `${visibles.length} cargados`
              : `${visibles.length} ${visibles.length === 1 ? 'resultado' : 'resultados'}`}
          </span>
        )}
      </div>
      {!rangoValido && <p id="error-fechas-cartera" role="alert" className="text-xs text-destructive">
        Completa ambas fechas. La fecha inicial debe ser anterior o igual a la final, y no posterior a hoy.
      </p>}
      {rangoValido && periodo && <p className="text-xs text-muted-foreground" role="status">
        Recibidos del {fmtFecha(`${periodo.desde}T12:00:00-05:00`)} al {fmtFecha(`${periodo.hasta}T12:00:00-05:00`)} · ambos días incluidos · hora de Perú.
        {yo?.rol === 'supervisor' && ' Recepción de los analistas de tu equipo; no incluye pendientes de repartir.'}
        {' Se muestran los leads que siguen dentro de tu cartera visible.'}
      </p>}

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
            titulo={!rangoValido ? 'Revisa el rango de fechas' : 'Sin resultados'}
            detalle={
              !rangoValido ? 'Corrige las fechas para consultar los leads y sus indicadores.' : cartera.error
                ? 'No se pudo cargar la cartera. Usa «Reintentar» en el aviso de arriba.'
                : q.trim()
                  ? `Ningún lead coincide con “${q.trim()}”. Prueba con otro nombre o número.`
                  : hayFiltro
                    ? `Ningún lead coincide con los filtros. Prueba con otras fechas, otra etapa, otro origen${filtrarVendedor ? ' u otro analista' : ''}.`
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
              <Th className={periodo ? '' : 'hidden xl:table-cell'}>{periodo ? 'Recibido' : 'Creado'}</Th>
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
                      // La procedencia también llega al lector de pantalla (como
                      // descripción), sin cambiar el nombre accesible que ya usan
                      // tests y atajos.
                      aria-describedby={descripcionProcedencia(l) ? `procedencia-${l.id}` : undefined}
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
                              <p className="flex items-center gap-1.5 text-[13px] font-semibold">
                                {l.nombre_completo}
                                {/* Procedencia a simple vista, pegada al nombre: lo manual
                                    en azul, lo del sistema en gris silencioso. */}
                                <ChipProcedencia lead={l} />
                                {descripcionProcedencia(l) && (
                                  <span id={`procedencia-${l.id}`} className="sr-only">{descripcionProcedencia(l)}</span>
                                )}
                              </p>
                              <p className="text-xs tabular-nums text-muted-foreground">
                                {l.telefono}
                                {/* El ORIGEN vive aquí como sub-dato del lead (antes se
                                    colaba en la columna Categoría y rompía la comparación
                                    vertical); también sigue en el hover-card. */}
                                <span> · {origenLabel(l.origen)}</span>
                                {l.procedencia === 'manual' && l.cargado_por_nombre && (
                                  <span className="normal-case"> · registrado por {l.cargado_por_nombre}</span>
                                )}
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
                              <span className="text-xs text-muted-foreground">{l.vendedor_nombre}</span>
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
                      <Td className={`text-xs text-muted-foreground ${periodo ? '' : 'hidden xl:table-cell'}`}>
                        {fmtFecha(periodo ? (yo?.demo ? `${fechaRecepcionDemo(l)}T12:00:00-05:00` : l.recibido_en) : l.creado_en)}
                        {periodo && l.recepcion_aproximada && <span title="Fecha estimada a partir del historial disponible"> · aprox.</span>}
                      </Td>
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
      {cartera.hayMas && rangoValido && (
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
          Datos de demostración. Los cambios de esta sesión no modifican leads reales.
        </p>
      )}
    </div>
  )
}
