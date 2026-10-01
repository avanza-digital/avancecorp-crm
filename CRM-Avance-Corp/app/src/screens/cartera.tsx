import { useEffect, useMemo, useRef, useState, type Ref } from 'react'
import { Search, Users, TrendingUp, Activity, CheckCircle2, ChevronRight, Inbox, Check, type LucideIcon } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { LeadHoverCard } from '@/components/app/lead-hover-card'
import { SegmentBar, type Segment } from '@/components/common/stat-strip'
import { AnimatedValue } from '@/components/common/animated-value'
import { PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { PanelVacio } from '@/components/common/estado-panel'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ETAPAS, TERMINALES, ETAPA_INFO, MOTIVOS_DESCARTE, CAT_LABEL, ORIGENES, ORIGENES_HEREDADOS, origenLabel, type Etapa, type Origen, type Procedencia } from '@/lib/tipos'
import { ChipProcedencia } from '@/components/app/procedencia-chip'
import { ChipReasignado } from '@/components/app/reasignado-chip'
import { ChipPotencial } from '@/components/app/potencial-chip'
import { idsDescripcion, potencialFila } from '@/components/app/potencial-efectos'
import { usePotencialLeads } from '@/data/potencial-queries'
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
function descripcionProcedencia(l: { procedencia?: Procedencia | null; cargado_por_nombre?: string | null; reasignado?: boolean | null }): string | undefined {
  const alta = l.procedencia === 'manual'
    ? `Registro manual${l.cargado_por_nombre ? `, por ${l.cargado_por_nombre}` : ''}`
    : l.procedencia === 'sistema' ? 'Del sistema' : null
  return [alta, l.reasignado === true ? 'Reasignado' : null].filter(Boolean).join('; ') || undefined
}
/** 'todos' | 'sin_asignar' | perfil_id de un analista del ámbito. */
type FiltroVendedor = string

const TONO_INDICADOR = { primary: 'text-primary', accent: 'text-accent', default: 'text-foreground' } as const

/** Un indicador de la franja de cabecera. Con `filtro` se vuelve botón: la cifra ES el filtro. */
interface IndicadorCartera {
  icon: LucideIcon
  label: string
  value: string
  tone: keyof typeof TONO_INDICADOR
  sub?: string
  /** Segunda línea del subtítulo (lo convertido, debajo del capital en juego).
   *  También es una cifra, así que también se abre (Codex, 28/09). */
  sub2?: { texto: string; alPulsar: () => void }
  /** `ayuda`: qué hace el botón, solo para el lector de pantalla. */
  filtro?: { activo: boolean; habilitado: boolean; alPulsar: () => void; ayuda: string }
}

/** Una etapa de la distribución, con su clave para poder filtrar por ella. */
interface EtapaResumen { k: Etapa; label: string; color: string; n: number }

/** Suma de los convertidos en texto, cada moneda por su lado (PEN y USD JAMÁS se suman). */
function textoConvertido(ganado: { pen: number; usd: number }): string {
  return [ganado.pen > 0 ? money(ganado.pen, 'PEN') : null, ganado.usd > 0 ? money(ganado.usd, 'USD') : null]
    .filter((t): t is string => t != null)
    .join(' · ')
}

/** Mini-KPI de la franja. Mismas escalas de letra que el StatStrip: lo que se
 *  gana es el hueco entre tarjetas, no tamaño de texto. Etiqueta y subtítulo en
 *  el gris FUERTE: sobre el fondo del estado activo o del hover, el gris normal
 *  baja de 4,5:1 (revisor-a11y, 28/09). */
function Indicador({ d, ref }: { d: IndicadorCartera; ref?: Ref<HTMLButtonElement> | undefined }) {
  const Icon = d.icon
  const tenue = 'text-[var(--muted-foreground-strong)]'
  const cuerpo = (
    <>
      <span className={cn('flex items-center gap-1.5 text-[11px] font-semibold', tenue)}>
        <Icon aria-hidden className="size-3.5 shrink-0" />
        <span className="truncate">{d.label}</span>
        {d.filtro?.activo && <Check aria-hidden className="ml-auto size-3.5 shrink-0 text-accent" />}
      </span>
      <span className={cn('mt-1 block text-xl font-extrabold leading-none tracking-tight tabular-nums', TONO_INDICADOR[d.tone])}>
        {/* El «—» no se pronuncia: el lector de pantalla oiría silencio, que es
            indistinguible de un cero. */}
        {d.value === '—'
          ? <><span aria-hidden="true">—</span><span className="sr-only">sin dato</span></>
          : <AnimatedValue value={d.value} />}
      </span>
      {d.sub && <span className={cn('mt-1 block text-[10.5px]', tenue)}>{d.sub}</span>}
      {/* Botón solo si el indicador NO es botón: un botón dentro de otro no
          es HTML válido (hoy la línea solo la lleva el capital, que no filtra). */}
      {d.sub2 && (d.filtro
        ? <span className="block text-[10.5px] font-semibold text-foreground/80">{d.sub2.texto}</span>
        : (
          <button type="button" onClick={d.sub2.alPulsar}
            className="block w-fit cursor-pointer rounded-sm text-left text-[10.5px] font-semibold text-foreground/80 underline-offset-2 transition-colors hover:text-accent hover:underline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-ring">
            {/* Sin la palabra «convertidos»: los E2E buscan la tarjeta «Convertidos»
                por texto, y el capital va antes en el DOM. */}
            {d.sub2.texto}<span className="sr-only"> · abre esa lista en la tabla</span>
          </button>
        ))}
    </>
  )
  const base = 'flex h-full w-full min-w-0 flex-col px-4 py-3 text-left'
  // Cada indicador sigue siendo una Card (aplanada dentro de la franja): los
  // E2E localizan los mini-KPI por su `data-slot="card"`.
  if (!d.filtro) {
    return <Card className="flex min-w-0 rounded-none border-0 shadow-none"><div data-kpi={d.label} className={base}>{cuerpo}</div></Card>
  }
  const { activo, habilitado, alPulsar, ayuda } = d.filtro
  return (
    <Card className="flex min-w-0 rounded-none border-0 shadow-none">
      {/* `aria-disabled` y no `disabled`: mientras llega la consulta nueva el
          botón que se acaba de pulsar no puede perder el foco (WCAG 2.4.3).
          El nombre va fijo en `aria-label`: el número se anima fotograma a
          fotograma y el lector anunciaría cada valor intermedio. */}
      <button
        ref={ref}
        type="button"
        data-kpi={d.label}
        aria-label={`${d.label} ${d.value === '—' ? 'sin dato' : d.value}${d.sub ? ` · ${d.sub}` : ''} · ${ayuda}`}
        aria-pressed={activo}
        aria-disabled={!habilitado || undefined}
        onClick={habilitado ? alPulsar : undefined}
        className={cn(
          base,
          'cursor-pointer transition-colors hover:bg-muted/50 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:hover:bg-transparent',
          activo && 'bg-accent/[0.06] shadow-[inset_0_-2px_0_var(--accent)] hover:bg-accent/[0.06] aria-disabled:hover:bg-accent/[0.06]',
        )}
      >
        {cuerpo}
      </button>
    </Card>
  )
}

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
  const [fReasignados, setFReasignados] = useState(false)
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
      () => ({ etapa: fEtapa, vendedorId: fVend, texto: qDiferido, origen: fOrigen, procedencia: fProc, reasignados: fReasignados,
        recepcion: periodo }),
      [fEtapa, fVend, qDiferido, fOrigen, fProc, fReasignados, periodo],
    ),
  )
  // Fase 4e: el store conoce lo que la tabla muestra (verbos de escritura por id).
  useEffect(() => { if (yo && !yo.demo) conocerLeads(cartera.leads) }, [yo, conocerLeads, cartera.leads])
  const resumen = rangoValido ? cartera.resumen ?? null : null
  // Destinos del foco cuando el control pulsado desaparece (ver pastillas y la
  // línea «Convertido: …»): nunca se deja caer al <body>.
  const refTotal = useRef<HTMLButtonElement>(null)
  const refConvertidos = useRef<HTMLButtonElement>(null)

  // Vista previa: KPIs y distribución de la misma colección filtrada completa.
  // Sin payload (cargando o RPC caída) los tiles dicen «—»: jamás se inventa
  // una cifra contando un array parcial del navegador.
  const { indicadores, etapas } = useMemo(() => {
    // «Total leads» y «Convertidos» SON filtros de etapa (todo número se abre).
    // Una cifra en cero no se abre: sería un filtro vacío a propósito. La
    // excepción es la etapa ya elegida: aunque falte el resumen, lo abierto se
    // puede cerrar.
    const filtroTotal = {
      activo: fEtapa === 'todas', habilitado: resumen != null || fEtapa !== 'todas', alPulsar: () => { setFEtapa('todas') },
      ayuda: 'muestra todas las etapas y conserva los demás filtros',
    }
    const filtroConvertidos = {
      activo: fEtapa === 'convertido',
      habilitado: fEtapa === 'convertido' || (resumen?.totales.convertidos ?? 0) > 0,
      alPulsar: () => { setFEtapa((actual) => (actual === 'convertido' ? 'todas' : 'convertido')) },
      ayuda: 'filtra la tabla por los convertidos; otro clic quita el filtro',
    }
    // Con la etapa «convertido» ya no hay nada en juego: lo que cuenta es lo
    // que se convirtió. Se llama «Capital convertido» y NO «confirmado»: en el
    // CRM «confirmado» es el capital de CONTRATOS del mes, neto de anulaciones;
    // esto es el monto ESTIMADO de los leads convertidos.
    const verConvertido = fEtapa === 'convertido'
    const etiquetaCapital = verConvertido ? 'Capital convertido' : 'Capital en juego'
    if (!resumen) {
      const indicadores: IndicadorCartera[] = [
        { icon: Users, label: 'Total leads', value: '—', tone: 'primary', filtro: filtroTotal },
        { icon: TrendingUp, label: etiquetaCapital, value: '—', tone: 'accent' },
        { icon: Activity, label: 'Activos', value: '—', tone: 'default', sub: 'Sin convertir ni descartar' },
        { icon: CheckCircle2, label: 'Convertidos', value: '—', tone: 'primary', sub: 'Dentro de los filtros elegidos', filtro: filtroConvertidos },
      ]
      return { indicadores, etapas: [] as EtapaResumen[] }
    }
    // El capital en juego se acota a los ABIERTOS (asignados + parkeados: esta
    // es la vista de inventario). El ganado no entra en esa cifra: ya vive como
    // contrato en la cartera de clientes y sumarlo lo duplicaría; va aparte,
    // como «Convertido: …». La cifra grande es la moneda que DE VERDAD tiene
    // volumen (capitalPrincipal) — PEN y USD JAMÁS se suman ni se convierten.
    const ganado = resumen.capital.ganado
    const nConvertidos = resumen.totales.convertidos
    let capital: IndicadorCartera
    if (verConvertido) {
      const convertido = capitalPrincipal(ganado.pen, ganado.usd)
      capital = {
        icon: TrendingUp, label: etiquetaCapital, value: convertido.valor, tone: 'accent',
        sub: `Monto estimado de ${nConvertidos} ${nConvertidos === 1 ? 'convertido' : 'convertidos'}${convertido.otra ? ` · +${convertido.otra}` : ''}`,
      }
    } else {
      const enJuego = capitalPrincipal(
        resumen.capital.asignado.pen + resumen.capital.parkeado.pen,
        resumen.capital.asignado.usd + resumen.capital.parkeado.usd,
      )
      const convertido = textoConvertido(ganado)
      capital = {
        icon: TrendingUp, label: etiquetaCapital, value: enJuego.valor, tone: 'accent',
        sub: fEtapa === 'descartado' ? 'Los descartados no suman capital' : enJuego.sub,
        // Al abrirla, la línea desaparece (con la etapa «convertido» el capital
        // cambia de tarjeta): el foco pasa a «Convertidos», que queda pulsada.
        ...(convertido ? { sub2: { texto: `Convertido: ${convertido}`, alPulsar: () => { setFEtapa('convertido'); refConvertidos.current?.focus() } } } : {}),
      }
    }
    const indicadores: IndicadorCartera[] = [
      { icon: Users, label: 'Total leads', value: String(resumen.totales.vivos), tone: 'primary', filtro: filtroTotal },
      capital,
      { icon: Activity, label: 'Activos', value: String(resumen.totales.abiertos), tone: 'default', sub: 'Sin convertir ni descartar' },
      { icon: CheckCircle2, label: 'Convertidos', value: String(nConvertidos), tone: 'primary', sub: 'Dentro de los filtros elegidos', filtro: filtroConvertidos },
    ]
    const porEtapa = new Map(resumen.embudo.map((p) => [p.etapa, p.n]))
    const etapas: EtapaResumen[] = [...ETAPAS, ...TERMINALES].map((e) => ({
      k: e.k, label: e.label, color: e.color, n: porEtapa.get(e.k) ?? 0,
    }))
    return { indicadores, etapas }
  }, [resumen, fEtapa])
  const segmentos: Segment[] = useMemo(
    () => etapas.map((e) => ({ label: e.label, value: e.n, color: e.color })),
    [etapas],
  )
  // Mientras llega la consulta de la etapa recién pulsada (sesión real: sin
  // resumen hasta que responde), las pastillas NO se desmontan —la pulsada
  // perdería el foco—: se quedan las últimas conocidas, SIN cifra (jamás un
  // número viejo) y sin poder pulsarse (revisor-a11y, 28/09).
  // Se compara por CONTENIDO (firma), no por referencia: un resumen nuevo con
  // las mismas cifras no debe volver a guardar nada (ni entrar en bucle).
  const firmaEtapas = etapas.map((e) => `${e.k}:${e.n}`).join('|')
  const [previas, setPrevias] = useState<{ firma: string; etapas: EtapaResumen[] }>({ firma: '', etapas: [] })
  if (etapas.length > 0 && firmaEtapas !== previas.firma) setPrevias({ firma: firmaEtapas, etapas })
  // Si la consulta nueva FALLA tampoco se desmontan (el foco caería igual): se
  // quedan sin cifra, pero ya se pueden soltar o cambiar (revisor-a11y, 28/09).
  const sinResumen = resumen == null && rangoValido && (cartera.cargando || Boolean(cartera.error))
  const recargando = sinResumen && cartera.cargando
  // Solo se abren las etapas que tienen leads; la activa se queda aunque dé
  // cero, para poder soltarla con otro clic.
  const pildorasEtapa = (sinResumen ? previas.etapas : etapas).filter((e) => e.n > 0 || e.k === fEtapa)

  const hayFiltro = q.trim() !== '' || fEtapa !== 'todas' || fOrigen !== 'todos' || fProc !== 'todas' || fReasignados || fVend !== 'todos' || modoFecha !== 'todas'

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
  // Potencial del lead (Frío · Tibio · Estrella): otra lectura aparte, por los
  // leads en pantalla. Con la bandera apagada no trae nada y no se pinta nada.
  const potencial = usePotencialLeads(useMemo(() => visibles.map((l) => l.id), [visibles]))

  return (
    // Sin tope de ancho: la tabla es la protagonista y en monitores anchos el
    // tope dejaba ~220 px vacíos a cada lado (Miguel, 28/09).
    <div className="space-y-3 ac-rise">
      {desdeRendimiento && <section aria-label="Consulta desde Rendimiento" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card p-4">
        <div className="min-w-0">
          <h2 className="text-sm font-bold">Leads de {desdeRendimiento.nombre}</h2>
          <p className="mt-1 text-xs text-muted-foreground">Listado e indicadores del analista seleccionado. El mes de Rendimiento no filtra esta lista; puedes elegir aquí el rango de recepción.</p>
          {fVend !== desdeRendimiento.id && <p role="status" className="mt-1 text-xs">Cambiaste el filtro del listado. La consulta original de Rendimiento se conserva al volver.</p>}
        </div>
        <a href="#/rendimiento" className="inline-flex min-h-11 items-center rounded-lg border border-input px-3 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2" onClick={() => memoriaGerencia?.setConsulta((actual) => ({ ...actual, gestionAnalista: null }))}>Volver a Rendimiento</a>
      </section>}
      {/* Franja de cabecera: los mini-KPIs y la distribución por etapa en UNA
          sola pieza (antes eran 4 tarjetas medio vacías + una tarjeta entera
          para una barra delgada). Las cifras que se pueden abrir son botones:
          la cifra ES el filtro, mismo patrón que Gestión Diaria. */}
      <section aria-label="Resumen de la cartera" aria-describedby="ayuda-resumen-cartera"
        className="overflow-hidden rounded-xl border border-border bg-card">
        <p id="ayuda-resumen-cartera" className="sr-only">
          Los filtros actualizan juntos el listado, los indicadores y la distribución por etapa.
        </p>
        {/* gap-px sobre fondo de borde: separadores finos que sirven igual en
            2 columnas (móvil) que en 4 (escritorio). */}
        <div className="grid grid-cols-2 gap-px bg-border lg:grid-cols-4">
          {indicadores.map((d) => (
            <Indicador key={d.label} d={d}
              ref={d.label === 'Total leads' ? refTotal : d.label === 'Convertidos' ? refConvertidos : undefined} />
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-border px-4 py-2.5">
          {/* En móvil, una tira horizontal con scroll propio en vez de apilar
              una pastilla por renglón (horizontal, nunca vertical). El p-1 deja
              sitio al contorno de foco, que el scroll recortaría (Codex, 28/09). */}
          <div role="group" aria-label="Distribución por etapa" aria-busy={recargando || undefined}
            className="flex w-full items-center gap-1.5 overflow-x-auto p-1 sm:w-auto sm:flex-wrap sm:overflow-visible sm:p-0">
            <span aria-hidden className="mr-1 shrink-0 text-[11px] font-semibold text-muted-foreground">Por etapa</span>
            {pildorasEtapa.length === 0 ? (
              <span className="text-xs text-muted-foreground">
                {resumen ? 'Sin leads con estos filtros' : <><span aria-hidden="true">—</span><span className="sr-only">sin dato</span></>}
              </span>
            ) : pildorasEtapa.map((e) => {
              const activa = fEtapa === e.k
              return (
                <button key={e.k} type="button" aria-pressed={activa} aria-disabled={recargando || undefined}
                  onClick={recargando ? undefined : () => {
                    setFEtapa(activa ? 'todas' : e.k)
                    // Soltar una etapa en cero la hace desaparecer: el foco va a
                    // «Total leads», que anuncia justo el estado resultante.
                    if (activa && e.n === 0) refTotal.current?.focus()
                  }}
                  className={cn(PILDORA, 'shrink-0 aria-disabled:cursor-default', activa ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
                  {activa
                    ? <Check aria-hidden className="size-3.5" />
                    : <span aria-hidden className="size-2 shrink-0 rounded-full" style={{ background: e.color }} />}
                  {e.label}{' '}
                  <span className="font-bold tabular-nums">
                    {sinResumen
                      ? <><span aria-hidden="true">—</span><span className="sr-only">{recargando ? 'cargando' : 'sin dato'}</span></>
                      : e.n}
                  </span>
                </button>
              )
            })}
          </div>
          {/* La pista es adorno (aria-hidden dentro del componente): el dato
              está en las pastillas de al lado. */}
          <SegmentBar segments={segmentos} legend={false} className="min-w-[160px] flex-1" />
        </div>
      </section>

      {/* Buscador + filtros + contador en UNA fila (el contador a la derecha). */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative w-full sm:w-auto sm:min-w-[220px] sm:max-w-sm sm:flex-1">
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
        <div className="w-[180px]">
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
        <div className="w-[170px]">
          <Select aria-label="Filtrar por procedencia" value={fProc} onChange={(e) => { setFProc(e.target.value as FiltroProcedencia) }}>
            <option value="todas">Sistema y manual</option>
            <option value="sistema">Solo del sistema</option>
            <option value="manual">Solo registro manual</option>
          </Select>
        </div>
        <Button type="button" variant="outline" size="sm"
          aria-label={`Filtrar reasignados: ${resumen?.totales.reasignados ?? 'sin dato'}`}
          aria-pressed={fReasignados}
          aria-disabled={!fReasignados && (resumen?.totales.reasignados ?? 0) <= 0 ? true : undefined}
          onClick={(resumen?.totales.reasignados ?? 0) > 0 || fReasignados
            ? () => setFReasignados((actual) => !actual) : undefined}
          className={cn('gap-1.5 tabular-nums', fReasignados && 'border-accent bg-accent/[0.08] text-accent')}>
          Reasignados <span aria-hidden="true">{resumen?.totales.reasignados ?? '—'}</span>
        </Button>
        <FiltroFechaCartera modo={modoFecha} rango={rangoFecha} hoy={hoy}
          invalido={!rangoValido} onModo={(modo) => {
            setModoFecha(modo)
            if (modo !== 'todas' && fVend === 'sin_asignar') setFVend('todos')
          }} onRango={setRangoFecha} />
        {filtrarVendedor && (
          <div className="w-[190px]">
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
          setQ(''); setFEtapa('todas'); setFOrigen('todos'); setFProc('todas'); setFReasignados(false); setFVend('todos'); setModoFecha('todas')
        }}>Limpiar filtros</Button>}
        {/* La región viva queda SIEMPRE montada y solo cambia su texto: una
            región que aparece ya escrita no se anuncia de forma fiable, y es el
            único aviso del resultado al pulsar una pastilla. */}
        <span className="ml-auto text-xs tabular-nums text-muted-foreground" aria-live="polite">
          {!rangoValido || cartera.cargando ? null : resumen
            ? `${resumen.totales.vivos} ${resumen.totales.vivos === 1 ? 'lead' : 'leads'}${cartera.hayMas ? ` · ${visibles.length} visibles` : ''}`
            : cartera.hayMas
            ? `${visibles.length} cargados`
            : `${visibles.length} ${visibles.length === 1 ? 'resultado' : 'resultados'}`}
        </span>
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
                la operación y el capital en juego. Desde lg, Lead se queda
                con un 30 % (sin partir nombre ni teléfono: nowrap) y el resto
                del ancho se reparte entre las demás columnas en vez de volverse
                un hueco antes de Etapa. */}
            <TheadCrm>
              <Th className="lg:w-[30%]">Lead</Th>
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
                      // La marca de potencial y la procedencia también llegan al
                      // lector de pantalla (como descripción), sin cambiar el nombre
                      // accesible que ya usan tests y atajos.
                      aria-describedby={idsDescripcion(
                        potencial.porLead.get(l.id)?.nivel && `potencial-${l.id}`,
                        descripcionProcedencia(l) && `procedencia-${l.id}`,
                      )}
                      onClick={() => abrirLead(l.id)}
                      onKeyDown={(ev) => {
                        if (ev.key === 'Enter' || ev.key === ' ') {
                          ev.preventDefault()
                          abrirLead(l.id)
                        }
                      }}
                      className="group cursor-pointer border-b border-border/60 transition-colors last:border-0 hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                      {...potencialFila(potencial.porLead.get(l.id))}
                    >
                      <Td className="lg:whitespace-nowrap">
                        <LeadHoverCard lead={l}>
                          <div className="flex items-center gap-2.5">
                            <Avatar nombre={l.nombre_completo} genero={l.genero ?? null} />
                            <div className="leading-tight">
                              {/* text-[13px]: misma densidad de nombre que FilaCliente/
                                  FilaContrato — las tres carteras leen como una familia. */}
                              <p className="flex items-center gap-1.5 text-[13px] font-semibold">
                                {l.nombre_completo}
                                <ChipPotencial id={`potencial-${l.id}`} marca={potencial.porLead.get(l.id)} />
                                {/* Procedencia a simple vista, pegada al nombre: lo manual
                                    en azul, lo del sistema en gris silencioso. */}
                                <ChipProcedencia lead={l} />
                                <ChipReasignado lead={l} />
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
