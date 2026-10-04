// «Gestión de la base» (F4, decisiones de Miguel del 03/10/2026): cómo trabaja la base el equipo.
//  · Arriba, el panel POR ANALISTA (en base · para llamar hoy · intentos de hoy · reactivaciones del mes). Todo número
//    se abre: los dos primeros filtran la hoja por ese analista; los otros dos abren su detalle en una hoja lateral.
//  · Debajo, la HOJA del equipo: la misma de la vista del analista con la columna «Gestiona» fija, el filtro Analista
//    junto a los de F3, el bloque «Llamar hoy» arriba y páginas de 50 con el número de fila continuo. Gerencia
//    (~1 000 filas): UNA carga y todo lo demás en el navegador.
//  · «Ver no contactar» (solo Supervisión y Gerencia) pide también los vetados y los pone en un bloque AL FINAL, con
//    su marca completa (cuándo, motivo, quién), incluso los que descansan.
//  · La ficha es de CONSULTA (datos + historial) y, si el lead está vetado, «Quitar No contactar». No registra intentos
//    ni reactiva: eso es del analista. Repartir sigue en «Descartes del mes».
// Estado de producción (gate de realidad): sin la B6b el servidor no conoce `p_incluir_vetados` ni el detalle de las
// cifras; la lista llega igual (reintento sin el parámetro) y la pantalla no ofrece lo que aún no existe.
import { useEffect, useId, useMemo, useRef, useState, type JSX } from 'react'
import { flushSync } from 'react-dom'
import { ArchiveRestore, Ban, FunnelX, RotateCcw, X } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { useBaseGestionEquipo, useBaseGestionResumen, useBaseGestionResumenDetalle } from '@/data/crm-queries'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { Button } from '@/components/ui/button'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { FichaBase } from '@/components/base-gestion/ficha-base'
import { HojaBase, type BloqueHoja } from '@/components/base-gestion/hoja-base'
import { BarraFiltros, Pastilla } from '@/components/base-gestion/filtros-base'
import { PanelAnalistas } from '@/components/base-gestion/panel-analistas'
import { DetalleCifra, type CifraAbierta } from '@/components/base-gestion/detalle-cifra'
import { HojaVetados } from '@/components/base-gestion/hoja-vetados'
import { useAhora } from '@/lib/ahora'
import { useEsMovil, usePuedeMarcar } from '@/lib/media'
import { POR_PAGINA, paginar } from '@/lib/paginacion'
import { cn } from '@/lib/utils'
import {
  DIAS_DESCANSO_BASE,
  FILTRO_TODOS,
  SIN_FILTROS,
  demoBaseEquipo,
  depurarFiltros,
  esVetada,
  etiquetaMesLead,
  filtrarBase,
  hayFiltros,
  mesesDeLaBase,
  opcionesFiltro,
  separarLlamarHoy,
  tieneRellamadaAgendada,
  type CifraDetalle,
  type DimensionFiltro,
  type FilaDetalleCifra,
  type FilaResumenBase,
  type FiltrosBase,
} from '@/lib/base-gestion'

const BLOQUE_HOY = { titulo: 'Llamar hoy', detalle: 'Rellamadas de hoy y las que se pasaron' }
const BLOQUE_RESTO = { titulo: 'El resto', detalle: 'Primero los que llegaron más lejos en el pipeline' }

export function GestionSupervisor({ analistaInicial, onAnalista }: {
  /** El analista que trae la URL (`vendedor_id` o la clave «sin dato» de la bandeja). */
  analistaInicial: string | null
  /** Avisa el analista elegido en la hoja (para escribirlo en la URL). Estable. */
  onAnalista: (analista: string | null) => void
}): JSX.Element {
  const { yo } = useAuth()
  const { leads, equipo, lead } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const esMovil = useEsMovil()
  const puedeMarcar = usePuedeMarcar()
  const ahora = useAhora()
  // Demo sin red (fail-closed): el espejo sale del store; la sesión real pregunta al servidor.
  const real = yo?.demo !== true
  const [verVetados, setVerVetados] = useState(false)
  const base = useBaseGestionEquipo(real && yo !== null, verVetados)
  const panel = useBaseGestionResumen(real && yo !== null)
  const demo = useMemo(() => (real ? null : demoBaseEquipo(leads, equipo, yo, ahora)), [real, leads, equipo, yo, ahora])

  // ¿El servidor tiene la B6b? Sin ella no hay «Ver no contactar» ni detalle de las cifras (llegan juntos).
  const conB6b = real ? base.data?.conVetados === true : true
  // Encendido el interruptor, mientras llega la lista con los vetados la hoja sigue mostrando la anterior.
  const cargandoVetados = real && verVetados && base.isPlaceholderData
  const filasTodas = useMemo(
    () => (real ? base.data?.filas ?? [] : (demo?.filas ?? []).filter((f) => verVetados || !esVetada(f))),
    [real, base.data, demo, verVetados],
  )
  // Si el servidor resultó no tener la B6b, el interruptor se apaga (y deja de ofrecerse).
  if (verVetados && real && base.data && !base.isPlaceholderData && base.data.conVetados === false) setVerVetados(false)

  const [filtrosElegidos, setFiltros] = useState<FiltrosBase>(() => ({ ...SIN_FILTROS, analista: analistaInicial ?? FILTRO_TODOS }))
  const [pagina, setPagina] = useState(0)
  const [paginaVetados, setPaginaVetados] = useState(0)
  // Un valor elegido que ya no está en la base vuelve a «Todos» y se olvida (F3). Solo con la lista cargada: mientras
  // carga no hay filas y el analista de la URL se perdería.
  const cargada = !real || base.data !== undefined
  const filtros = cargada ? depurarFiltros(filasTodas, filtrosElegidos) : filtrosElegidos
  if (filtros !== filtrosElegidos) setFiltros(filtros)
  const analistaUrl = filtros.analista === FILTRO_TODOS ? null : filtros.analista
  // La URL lleva el analista elegido (sobrevive a recargar la página).
  useEffect(() => { onAnalista(analistaUrl) }, [analistaUrl, onAnalista])

  const [fichaId, setFichaId] = useState<string | null>(null)
  const [cifraAbierta, setCifraAbierta] = useState<CifraAbierta | null>(null)
  const detalle = useBaseGestionResumenDetalle(real && cifraAbierta !== null, cifraAbierta?.vendedorId ?? null, cifraAbierta?.cifra ?? null)

  const vecino = useRef<string | null>(null)
  const fichaDeVetado = useRef(false)
  const regionHoja = useRef<HTMLDivElement>(null)
  const listaTarjetas = useRef<HTMLDivElement>(null)
  const resumen = useRef<HTMLElement>(null)
  const tituloHoy = useRef<HTMLHeadingElement>(null)
  const tituloVetados = useRef<HTMLHeadingElement>(null)
  const tituloPanel = useRef<HTMLHeadingElement>(null)
  const regionPanel = useRef<HTMLDivElement>(null)
  const primerFiltro = useRef<HTMLSelectElement>(null)
  const idPanel = useId()
  const idHoy = useId()
  const idResto = useId()
  const idVetados = useId()

  if (!yo) return <PanelVacio icono={ArchiveRestore} titulo="Sin sesión" detalle="Vuelve a entrar para ver la base para gestión." />
  const ambito = yo.rol === 'gerencia' ? 'de todos los equipos' : 'de tu equipo'

  const resumenPanel: readonly FilaResumenBase[] | undefined = real ? panel.data : demo?.resumen
  const conMes = mesesDeLaBase(filasTodas).length > 0
  const visibles = filtrarBase(filasTodas, filtros)
  const vivas = visibles.filter((f) => !esVetada(f))
  const vetadas = visibles.filter(esVetada)
  const opciones = opcionesFiltro(filasTodas, filtros)
  const { hoy, resto } = separarLlamarHoy(vivas)
  const orden = [...hoy, ...resto]
  const paginado = paginar(orden, pagina)
  const paginadoVetados = paginar(vetadas, paginaVetados)
  const conBloques = hoy.length > 0
  const enPagina = { hoy: paginado.visibles.filter((f) => f.rellamada_hoy), resto: paginado.visibles.filter((f) => !f.rellamada_hoy) }
  const bloques: BloqueHoja[] = conBloques
    ? [
        ...(enPagina.hoy.length > 0 ? [{ id: idHoy, ...BLOQUE_HOY, n: hoy.length, filas: enPagina.hoy, urgente: true, tituloRef: tituloHoy }] : []),
        ...(enPagina.resto.length > 0 ? [{ id: idResto, ...BLOQUE_RESTO, n: resto.length, filas: enPagina.resto }] : []),
      ]
    : [{ id: idResto, ...BLOQUE_RESTO, n: resto.length, filas: paginado.visibles }]
  const filtrando = hayFiltros(filtros)
  const soloAnalista = filtrando && filtros.analista !== FILTRO_TODOS && !hayFiltros({ ...filtros, analista: FILTRO_TODOS })
  const soloMes = filtrando && filtros.mes !== FILTRO_TODOS && !hayFiltros({ ...filtros, mes: FILTRO_TODOS })
  const nombreAnalista = opciones.analista.opciones.find((o) => o.clave === filtros.analista)?.etiqueta ?? ''
  const etiquetaTotal = !filtrando ? 'En la base' : soloAnalista ? `De ${nombreAnalista}` : soloMes ? `De ${etiquetaMesLead(filtros.mes)}` : 'Coinciden'
  const agendadas = vivas.filter(tieneRellamadaAgendada).length
  const recargaFallida = real && base.isError && base.data !== undefined

  // ── Acciones ──────────────────────────────────────────────────────────────────────────────────────────────
  const destinoHoja = (): HTMLElement | null => (esMovil ? listaTarjetas.current : regionHoja.current) ?? resumen.current
  /** Filtra la hoja SOLO por un analista (la cifra del panel cuenta eso) y lleva el foco a lo que se abrió. */
  const verAnalista = (vendedorId: string, a: 'hoja' | 'hoy') => {
    flushSync(() => { setFiltros({ ...SIN_FILTROS, analista: vendedorId }); setPagina(0); setPaginaVetados(0) })
    ;(a === 'hoy' ? tituloHoy.current ?? destinoHoja() : destinoHoja())?.focus()
  }
  const abrirDetalle = (fila: FilaResumenBase, cifra: CifraDetalle) =>
    setCifraAbierta({ vendedorId: fila.vendedor_id, nombre: fila.nombre, cifra, valor: fila[cifra] })
  const cambiarFiltro = (dimension: DimensionFiltro, valor: string) => {
    setFiltros((f) => ({ ...f, [dimension]: valor })); setPagina(0); setPaginaVetados(0)
  }
  const quitarFiltros = () => { setFiltros(SIN_FILTROS); setPagina(0); setPaginaVetados(0); primerFiltro.current?.focus() }
  const alternarAgendadas = () => {
    setFiltros((f) => ({ ...f, agendadas: !f.agendadas })); setPagina(0)
    if (filtros.agendadas && filtrarBase(filasTodas, { ...filtros, agendadas: false }).filter((f) => !esVetada(f) && tieneRellamadaAgendada(f)).length === 0) resumen.current?.focus()
  }
  const irAlBloqueHoy = () => {
    flushSync(() => setPagina(0))
    tituloHoy.current?.focus()
  }
  // Si el lead sale de su lista con la ficha abierta, el foco va a su vecino de ESA lista (la hoja o el bloque de
  // vetados) o, si no queda ninguno, al título de esa lista: nunca a <body> ni lejos de donde estaba.
  const abrirFicha = (leadId: string) => {
    const vetada = vetadas.some((f) => f.lead_id === leadId)
    const lista = vetada ? vetadas : orden
    const i = lista.findIndex((f) => f.lead_id === leadId)
    fichaDeVetado.current = vetada
    vecino.current = i >= 0 ? (lista[i + 1] ?? lista[i - 1])?.lead_id ?? null : null
    setFichaId(leadId)
  }
  const focoRespaldo = (): HTMLElement | null =>
    (vecino.current ? document.querySelector<HTMLElement>(`[data-foco-clave="base-ficha-${vecino.current}"]`) : null)
    ?? (fichaDeVetado.current ? tituloVetados.current : null)
    ?? destinoHoja()
  /** «Reintentar» desaparece si sale bien: el foco va a lo que se recargó, no cae en <body>. */
  const reintentarPanel = async () => {
    if (panel.isFetching) return
    const r = await panel.refetch()
    if (r.isSuccess) requestAnimationFrame(() => tituloPanel.current?.focus())
  }
  const reintentarBase = async () => {
    if (base.isFetching) return
    const r = await base.refetch()
    if (r.isSuccess) requestAnimationFrame(() => resumen.current?.focus())
  }
  const enLaBase = (leadId: string) => filasTodas.some((f) => f.lead_id === leadId)
  const abribleDetalle = (f: FilaDetalleCifra) => enLaBase(f.lead_id) || lead(f.lead_id) !== undefined
  const abrirDesdeDetalle = (f: FilaDetalleCifra) => {
    if (enLaBase(f.lead_id)) setFichaId(f.lead_id)
    else abrirLead(f.lead_id)
  }

  return (
    <div className="space-y-4">
      {/* ── Panel por analista ─────────────────────────────────────────────────────────────────────────────── */}
      {/* Acotado en escritorio: con cuatro cifras, una tabla de lado a lado aleja el número de su analista. Un <div>:
          la región es la propia hoja del panel, nombrada por este título (no se anuncia dos veces). */}
      <div className="space-y-2 lg:max-w-[60rem]">
        <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
          <h2 id={idPanel} ref={tituloPanel} tabIndex={-1} className={cn('rounded text-[15px] font-bold text-primary', FOCO)}>Por analista</h2>
          <p className="text-[13px] text-[var(--muted-foreground-strong)]">
            Hoy y este mes, en hora de Lima.{conB6b ? '' : ' El detalle de intentos y reactivaciones llega con la próxima actualización del servidor.'}
          </p>
        </div>
        {real && panel.isPending ? (
          <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={3} /></div>
        ) : real && panel.isError && panel.data === undefined ? (
          <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-card px-4 py-2.5">
            <p role="alert" className="text-sm text-[var(--muted-foreground-strong)]">No se pudo cargar el panel por analista. La hoja de abajo sigue disponible.</p>
            <Button variant="outline" size="sm" className="pointer-coarse:h-11" aria-disabled={panel.isFetching || undefined} onClick={() => void reintentarPanel()}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        ) : (
          <PanelAnalistas
            idTitulo={idPanel}
            regionRef={regionPanel}
            filas={resumenPanel ?? []}
            esMovil={esMovil}
            conDetalle={conB6b}
            analistaActivo={filtros.analista === FILTRO_TODOS ? null : filtros.analista}
            onVerEnBase={(id) => verAnalista(id, 'hoja')}
            onVerHoy={(id) => verAnalista(id, 'hoy')}
            onDetalle={abrirDetalle}
          />
        )}
      </div>

      {/* ── La hoja del equipo ─────────────────────────────────────────────────────────────────────────────── */}
      {real && base.isPending ? (
        <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={6} /></div>
      ) : real && base.isError && base.data === undefined ? (
        <div className="rounded-lg border border-border bg-card">
          <PanelError mensaje={`No se pudo cargar la base ${ambito}.`} onReintentar={() => void base.refetch()} reintentando={base.isFetching} />
        </div>
      ) : (
        <>
          {/* Sin rellamadas de hoy (el estado de producción) la hoja no tiene bandas: este título la nombra al navegar por encabezados. */}
          <h2 className="sr-only">Leads de la base</h2>
          {/* Siempre montada (una región que nace con texto no se lee): dice qué pasó al encender «Ver no contactar». */}
          <p role="status" className="sr-only">
            {!verVetados ? '' : cargandoVetados ? 'Cargando los leads con «No contactar»…' : `${vetadas.length} ${vetadas.length === 1 ? 'lead' : 'leads'} con «No contactar», al final de la hoja.`}
          </p>
          <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
            <section ref={resumen} tabIndex={-1} aria-label="Resumen de la base" className={cn('flex flex-wrap items-center gap-2 rounded-lg', FOCO)}>
              <Pastilla etiqueta={etiquetaTotal} valor={vivas.length} />
              <Pastilla
                etiqueta="Para llamar hoy"
                valor={hoy.length}
                urgente={hoy.length > 0}
                pista="ver el bloque"
                onAbrir={hoy.length > 0 ? irAlBloqueHoy : undefined}
              />
              <Pastilla
                etiqueta="Rellamadas agendadas"
                valor={agendadas}
                presionada={filtros.agendadas}
                pista="ver solo esas"
                onAbrir={agendadas > 0 || filtros.agendadas ? alternarAgendadas : undefined}
              />
              {verVetados && !cargandoVetados && (
                <Pastilla
                  etiqueta="No contactar"
                  valor={vetadas.length}
                  urgente={vetadas.length > 0}
                  pista="ver el bloque"
                  onAbrir={vetadas.length > 0 ? () => tituloVetados.current?.focus() : undefined}
                />
              )}
              {conB6b && (
                <button
                  type="button"
                  aria-pressed={verVetados}
                  onClick={() => { setVerVetados((v) => !v); setPaginaVetados(0) }}
                  className={cn(
                    'inline-flex cursor-pointer items-center gap-2 rounded-md border px-3 py-1.5 text-sm font-semibold transition-colors pointer-coarse:min-h-11',
                    verVetados ? 'border-destructive/50 bg-destructive/[0.08] text-[var(--destructive-text)]' : 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-[var(--border-strong)] hover:text-foreground',
                    FOCO,
                  )}
                >
                  <Ban className="size-3.5" aria-hidden />
                  Ver no contactar
                  {/* Encendido no se dice solo con color: la X, como en la pastilla presionada. */}
                  {verVetados && <X className="size-3.5" aria-hidden />}
                </button>
              )}
            </section>
            {filasTodas.length > 0 && (
              <BarraFiltros
                conAnalista
                conMes={conMes}
                opciones={opciones}
                filtros={filtros}
                onCambiar={cambiarFiltro}
                onQuitar={quitarFiltros}
                mostrados={visibles.length}
                total={filasTodas.length}
                primerFiltro={primerFiltro}
                etiqueta="Filtrar la base"
              />
            )}
          </div>

          {recargaFallida && (
            <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-card px-4 py-2.5">
              <p role="alert" className="text-sm text-[var(--muted-foreground-strong)]">No pudimos actualizar la base. Se muestran los últimos datos.</p>
              <Button variant="outline" size="sm" className="pointer-coarse:h-11" aria-disabled={base.isFetching || undefined} onClick={() => void reintentarBase()}>
                <RotateCcw aria-hidden /> Reintentar
              </Button>
            </div>
          )}

          {vivas.length === 0 ? (
            <div className="rounded-lg border border-border bg-card">
              {filtrando ? (
                <PanelVacio icono={FunnelX} titulo="Ningún lead por gestionar coincide" detalle="Ningún lead de la base cumple todos los filtros elegidos.">
                  <Button type="button" variant="outline" className="mt-1 h-10 pointer-coarse:h-11" onClick={quitarFiltros}>
                    <X aria-hidden /> Quitar filtros
                  </Button>
                </PanelVacio>
              ) : (
                <PanelVacio
                  icono={ArchiveRestore}
                  titulo={`No hay leads descartados por gestionar ${ambito}`}
                  detalle={`Cuando un analista descarte un lead, aparecerá aquí. Los que están en descanso vuelven solos al terminar sus ${DIAS_DESCANSO_BASE} días.`}
                />
              )}
            </div>
          ) : (
            <div className="space-y-2">
              <HojaBase
                bloques={bloques}
                conBandas={conBloques}
                esMovil={esMovil}
                etiqueta={`Base para gestión ${ambito}`}
                caption={
                  <>
                    Leads descartados {ambito}{soloAnalista ? ` que gestiona ${nombreAnalista}` : ''}{filtrando && !soloAnalista ? ', con los filtros elegidos' : ''}.
                    {conBloques ? ' Primero el bloque «Llamar hoy»; después el resto.' : ''} Página {paginado.paginaActual + 1} de {paginado.paginas}.
                  </>
                }
                conMes={conMes}
                conGestiona
                llamable={false}
                numeroInicial={paginado.paginaActual * POR_PAGINA + 1}
                ahora={ahora}
                puedeMarcar={puedeMarcar}
                onAbrir={abrirFicha}
                regionRef={regionHoja}
                listaRef={listaTarjetas}
              />
              <Paginacion paginaActual={paginado.paginaActual} paginas={paginado.paginas} total={orden.length} onCambio={setPagina} ariaLabel="Páginas de la base" />
            </div>
          )}

          {verVetados && (
            <div className="space-y-2">
              <HojaVetados
                id={idVetados}
                filas={paginadoVetados.visibles}
                numeroInicial={paginadoVetados.paginaActual * POR_PAGINA + 1}
                total={vetadas.length}
                esMovil={esMovil}
                ahora={ahora}
                cargando={cargandoVetados}
                tituloRef={tituloVetados}
                onAbrir={abrirFicha}
              />
              <Paginacion paginaActual={paginadoVetados.paginaActual} paginas={paginadoVetados.paginas} total={vetadas.length} onCambio={setPaginaVetados} ariaLabel="Páginas de «No contactar»" />
            </div>
          )}

          <p className="text-sm text-[var(--muted-foreground-strong)]">
            Aquí se consulta: los intentos y la reactivación los registra el analista desde su base. Para repartir descartes, usa «Descartes del mes».
          </p>
        </>
      )}

      <DetalleCifra
        abierta={cifraAbierta}
        filas={real ? detalle.data : cifraAbierta && demo ? demo.detalle(cifraAbierta.vendedorId, cifraAbierta.cifra) : undefined}
        cargando={real && detalle.isPending}
        error={real && detalle.isError}
        reintentando={real && detalle.isFetching}
        onReintentar={() => void detalle.refetch()}
        ahora={ahora}
        esMovil={esMovil}
        onCerrar={() => setCifraAbierta(null)}
        abrible={abribleDetalle}
        onAbrirLead={abrirDesdeDetalle}
        focoRespaldo={() => regionPanel.current ?? tituloPanel.current}
      />

      <FichaBase
        fila={fichaId ? (filasTodas.find((f) => f.lead_id === fichaId) ?? null) : null}
        demo={!real}
        puedeMarcar={puedeMarcar}
        onCerrar={() => setFichaId(null)}
        focoRespaldo={focoRespaldo}
        modo="supervision"
      />
    </div>
  )
}
