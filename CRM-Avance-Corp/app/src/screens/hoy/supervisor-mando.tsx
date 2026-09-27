// Hoy · SUPERVISOR — puesto de mando en UNA pantalla (diseño 2a, 27/09/2026).
// Plan aprobado por Miguel y refutado por Codex: nota del vault «Hoy del
// supervisor - puesto de mando en una pantalla, plan (2026-09-27)».
//
// Producción corre el seguimiento en modo ACTIVO desde el 07/09/2026: la cola
// legada (cola_accion_fn) no se consulta y la pantalla clásica solo enlazaba
// al módulo Seguimiento. Aquí la cola sale de crm.cola_accion_v2_fn —la misma
// del módulo—, filtrada por analista EN EL SERVIDOR: sus `totales` respetan el
// filtro, así que los números cuadran sin contar filas en el navegador.
//
// Modo legado (demo, o seguimiento apagado por gerencia) → la pantalla
// clásica ./supervisor.tsx, que sigue siendo también el rollback de una línea.
// Meta, reparto, agenda y TC: ./datos-supervisor.ts, compartido con ella.
import { useId, useMemo, useState, type JSX } from 'react'
import { ChevronRight, ListChecks, RefreshCw, UsersRound } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import { AccionesContacto } from '@/components/app/contacto'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
import { estadoCasoSupervision, momentoCaso } from '@/lib/cola-supervision'
import { conteoSemaforoEquipo, lecturaAnalista, type LecturaAnalista } from '@/lib/senal-equipo'
import { haceTexto } from '@/lib/inteligencia'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { textoConversionOperativa } from '@/lib/metricas-vendedores'
import { totalEnSoles } from '@/lib/capital-unificado'
import { moneyK, numero, primerNombre } from '@/lib/format'
import { hashDe } from '@/lib/router'
import { cn } from '@/lib/utils'
import { usePanelesActions } from '@/lib/store-context'
import type { FiltrosSla } from '@/lib/sla-operacion'
import { HoySupervisor } from './supervisor'
import { useDatosSupervisor } from './datos-supervisor'

/** Filas de la vista previa: lo demás vive en el módulo Seguimiento. */
const COLA_VISIBLES = 7

type PestanaMando = 'pendientes' | 'primera_atencion' | 'tareas_vencidas' | 'todas'
const PESTANAS: ReadonlyArray<{ id: PestanaMando; label: string }> = [
  { id: 'pendientes', label: 'Para atender ahora' },
  { id: 'primera_atencion', label: 'Primera gestión' },
  { id: 'tareas_vencidas', label: 'Tareas vencidas' },
  { id: 'todas', label: 'Todas' },
]
const VACIO_PESTANA: Record<PestanaMando, string> = {
  pendientes: 'Nada para atender ahora: el equipo no tiene pendientes vencidos.',
  primera_atencion: 'Ninguna primera gestión vencida.',
  tareas_vencidas: 'Ninguna tarea vencida.',
  todas: 'Sin oportunidades con acciones en el seguimiento.',
}

/** Chip de señal: el ámbar suave usa el token de TEXTO (el hex puro no llega a 4.5:1 sobre su tinte). */
function ChipSenal({ texto, nivel }: { texto: string; nivel: 'critico' | 'atencion' }): JSX.Element {
  return nivel === 'critico'
    ? <Badge color={SEMAFORO.critico} variant="solid">{texto}</Badge>
    : <Badge color="var(--warning-text)">{texto}</Badge>
}

const COLOR_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
  critico: SEMAFORO.critico,
  atencion: SEMAFORO.atencion,
  neutro: SEMAFORO.neutro,
}

export function HoySupervisorMando(): JSX.Element {
  const modo = useModoSla()
  if (modo.legado) return <HoySupervisor />
  // Cambiar de revisión del seguimiento remonta la pantalla: ningún filtro ni
  // selección de la revisión anterior sobrevive sobre datos de otra.
  return <PuestoDeMando key={String(modo.data?.control_revision ?? 'sin-revision')} />
}

function PuestoDeMando(): JSX.Element {
  const modo = useModoSla()
  const datos = useDatosSupervisor()
  const { abrirLead } = usePanelesActions()
  const { ambito, rank, tc, ahora } = datos
  const idPanelCola = useId()

  const [pestana, setPestana] = useState<PestanaMando>('pendientes')
  const [analistaId, setAnalistaId] = useState<string | null>(null)
  const [anuncio, setAnuncio] = useState('')
  const [abriendo, setAbriendo] = useState<string | null>(null)
  const [errorApertura, setErrorApertura] = useState(false)

  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
  // Fail-closed: TanStack conserva la última respuesta tras un refetch
  // fallido; con error, la cola NO se muestra como vigente.
  const pagina = consultaCola.error ? undefined : consultaCola.data
  const paginaVigente = pagina?.modo === 'activo' ? pagina : undefined

  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
  // Analistas del equipo (no las filas cargadas): los chips no dependen de
  // lo que haya traído la página y no prometen conteos del lado cliente.
  const analistas = useMemo(
    () => ambito.vendedores
      .filter((m) => m.activo && m.rol_crm === 'vendedor')
      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
    [ambito.vendedores],
  )
  const nombreAnalista = analistaId != null
    ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
    : null

  const elegirAnalista = (id: string | null) => {
    const siguiente = id === analistaId ? null : id
    setAnalistaId(siguiente)
    const nombre = siguiente == null ? null : ambito.vendedores.find((m) => m.perfil_id === siguiente)?.nombre_completo
    setAnuncio(nombre ? `Mostrando los pendientes de ${primerNombre(nombre)}` : 'Mostrando los pendientes de todo el equipo')
  }
  const elegirPestana = (id: PestanaMando) => {
    setPestana(id)
    setErrorApertura(false)
  }

  async function abrirFicha(id: string) {
    if (abriendo) return
    setAbriendo(id)
    setErrorApertura(false)
    try {
      if (await abrirLead(id) === false) setErrorApertura(true)
    } catch {
      setErrorApertura(true)
    } finally {
      setAbriendo(null)
    }
  }

  const conteoPestana = (id: PestanaMando): number | null => {
    if (!paginaVigente) return null
    if (id === 'todas') return pestana === 'todas' ? paginaVigente.total_items : null
    return paginaVigente.totales[id]
  }

  // ── Equipo hoy: UNA lectura por analista alimenta punto, cabecera y chips ──
  const rezagosConfirmados = useMemo(
    () => new Map((datos.agendaConfirmada?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
    [datos.agendaConfirmada],
  )
  const lecturas = useMemo(
    () => new Map((rank ?? []).map((r) => [r.m.perfil_id, lecturaAnalista(r, rezagosConfirmados.get(r.m.perfil_id))] as const)),
    [rank, rezagosConfirmados],
  )
  const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])

  const errorIndicadores = !datos.sesionReal
    ? false
    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error)
  const reintentarIndicadores = () => {
    if (datos.resumenOp.error) void datos.resumenOp.recargar()
    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
  }

  const tituloCola = nombreAnalista ? `Pendientes de ${primerNombre(nombreAnalista)}` : 'Pendientes del equipo'

  return (
    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>

      <AvisoDegradacion
        activo={errorIndicadores}
        queReintenta="de los indicadores del equipo"
        onReintentar={reintentarIndicadores}
      >
        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
      <div className="grid gap-4 lg:grid-cols-5">
        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
          <SectionHead icon={ListChecks} title={tituloCola} />
          {!modo.activo ? (
            <CardContent className="pb-5 pt-0">
              {modo.error ? (
                <div role="alert" className="flex flex-wrap items-center justify-between gap-3">
                  <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
                  <Button variant="outline" size="sm" onClick={() => void modo.refetch()}>
                    <RefreshCw aria-hidden /> Reintentar
                  </Button>
                </div>
              ) : (
                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
              )}
            </CardContent>
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-2 px-5 pb-2.5">
                <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
                  {PESTANAS.map((p, indice) => {
                    const n = conteoPestana(p.id)
                    return (
                      <button
                        key={p.id}
                        id={`${idPanelCola}-tab-${p.id}`}
                        type="button"
                        role="tab"
                        aria-selected={pestana === p.id}
                        aria-controls={`${idPanelCola}-panel`}
                        aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
                        tabIndex={pestana === p.id ? 0 : -1}
                        onClick={() => elegirPestana(p.id)}
                        onKeyDown={(e) => {
                          const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
                            : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
                            : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
                          if (destino == null) return
                          e.preventDefault()
                          const siguiente = PESTANAS[destino]
                          if (!siguiente) return
                          elegirPestana(siguiente.id)
                          document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
                        }}
                        className={cn(
                          'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                          pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
                        )}
                      >
                        {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
                      </button>
                    )
                  })}
                </div>
              </div>

              {analistas.length > 0 && (
                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
                  <button
                    type="button"
                    aria-pressed={analistaId == null}
                    onClick={() => elegirAnalista(null)}
                    className={cn(
                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                      analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
                    )}
                  >
                    Todos
                  </button>
                  {analistas.map((m) => (
                    <button
                      key={m.perfil_id}
                      type="button"
                      aria-pressed={analistaId === m.perfil_id}
                      aria-label={m.nombre_completo}
                      onClick={() => elegirAnalista(m.perfil_id)}
                      className={cn(
                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
                      )}
                    >
                      {primerNombre(m.nombre_completo)}
                    </button>
                  ))}
                </div>
              )}

              {abriendo && <p role="status" className="px-5 pb-2 text-xs text-muted-foreground">Abriendo ficha…</p>}
              {errorApertura && <p role="alert" className="px-5 pb-2 text-xs text-destructive-text">No se pudo abrir la ficha. Vuelve a intentarlo.</p>}

              <div
                id={`${idPanelCola}-panel`}
                role="tabpanel"
                aria-labelledby={`${idPanelCola}-tab-${pestana}`}
                tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
                className="flex flex-1 flex-col"
              >
                {consultaCola.error ? (
                  <div role="alert" className="flex flex-wrap items-center justify-between gap-3 border-t border-border/60 px-5 py-4">
                    <p className="text-sm">No se pudo cargar la cola. Los pendientes todavía no están confirmados.</p>
                    <Button variant="outline" size="sm" onClick={() => void consultaCola.refetch()}>
                      <RefreshCw aria-hidden /> Reintentar
                    </Button>
                  </div>
                ) : !pagina ? (
                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
                ) : !paginaVigente ? (
                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
                    Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.
                  </p>
                ) : paginaVigente.items.length === 0 ? (
                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
                    {nombreAnalista ? `${primerNombre(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
                  </p>
                ) : (
                  <ul aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
                    {paginaVigente.items.map((item) => {
                      const leadStore = leadPorId.get(item.lead_id)
                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
                      const analistaFila = item.lead.analista_nombre ? primerNombre(item.lead.analista_nombre) : 'Sin analista'
                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
                      return (
                        <li
                          key={item.lead_id}
                          data-sev={item.severidad}
                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
                          style={{ borderLeftColor: colorTira }}
                        >
                          <button
                            type="button"
                            disabled={abriendo !== null}
                            onClick={() => void abrirFicha(item.lead_id)}
                            // El nombre dicta TODO lo visible (dueño, estado, tiempo, monto):
                            // un lector de pantalla no puede perder lo que se ve.
                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}: ${estado}${monto ? `, ${monto}` : ''}`}
                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 disabled:cursor-wait"
                          >
                            {analistaId == null && (
                              <span className="flex w-[118px] shrink-0 items-center gap-2">
                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
                              </span>
                            )}
                            <span className="min-w-0 flex-1 leading-tight">
                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
                              <span className="block truncate text-xs text-muted-foreground">{estado}</span>
                            </span>
                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                          </button>
                          {leadStore && <AccionesContacto lead={leadStore} compacto />}
                        </li>
                      )
                    })}
                  </ul>
                )}
                <div className="mt-auto flex items-center justify-between gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
                  <span className="tabular-nums text-muted-foreground-strong">
                    {paginaVigente && paginaVigente.items.length > 0
                      ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
                      : ''}
                  </span>
                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
                    Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
                  </a>
                </div>
              </div>
            </>
          )}
        </Card>

        {/* ── Equipo hoy: tocar a alguien filtra la cola y despliega sus señales ── */}
        <Card className="min-w-0 overflow-hidden lg:col-span-2">
          <SectionHead
            icon={UsersRound}
            title="Equipo hoy"
            right={(
              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center rounded-md px-1 text-xs font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
                Mi equipo hoy →
              </a>
            )}
          />
          {rank != null && rank.length > 0 && (
            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
                ? 'Sin alertas en el equipo'
                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
            </p>
          )}
          {datos.errorAgenda && (
            <div role="alert" className="mx-5 mb-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-warning-text/30 bg-warning-text/5 px-3 py-2">
              <p className="text-xs">La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.</p>
              <Button variant="outline" size="sm" onClick={datos.recargarAgenda}>
                <RefreshCw aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {rank == null ? (
            <CardContent className="pb-5 pt-0">
              <p className="text-sm text-muted-foreground">
                {datos.vendedoresOp.error
                  ? 'El resumen por analista no está disponible en este momento.'
                  : 'Cargando el resumen por analista…'}
              </p>
            </CardContent>
          ) : rank.length === 0 ? (
            <CardContent className="pb-5 pt-0">
              <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
            </CardContent>
          ) : (
            <ul aria-label="Analistas del equipo" className="border-t border-border/60">
              {rank.map((r) => {
                const id = r.m.perfil_id
                const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
                const rezago = rezagosConfirmados.get(id)
                const abierto = analistaId === id
                const principal = lectura.senales[0]?.texto
                  ?? (r.activos === 0
                    ? 'Sin leads abiertos'
                    : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
                const idDetalle = `${idPanelCola}-equipo-${id}`
                const conversion = r.conversion == null
                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
                  : `${textoConversionOperativa(r.conversion)} conversión`
                return (
                  <li key={id} className="border-b border-border/60 last:border-b-0">
                    <button
                      type="button"
                      aria-expanded={abierto}
                      aria-controls={idDetalle}
                      aria-label={`${r.m.nombre_completo}: ${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
                      onClick={() => elegirAnalista(id)}
                      className={cn(
                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
                        abierto && 'bg-accent/[0.08]',
                      )}
                    >
                      {lectura.nivel != null
                        ? <span data-testid="equipo-semaforo" data-nivel={lectura.nivel} className="size-2 shrink-0 rounded-full" style={{ background: COLOR_NIVEL[lectura.nivel] }} aria-hidden />
                        : <span className="size-2 shrink-0" aria-hidden />}
                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
                      <span className="min-w-0 flex-1 leading-tight">
                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
                      </span>
                      <span className="shrink-0 text-right leading-tight">
                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
                      </span>
                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
                    </button>
                    <div id={idDetalle} hidden={!abierto} className="space-y-1.5 px-5 pb-3 pl-[62px]">
                      {lectura.senales.length > 1 && (
                        <div className="flex flex-wrap gap-1.5">
                          {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
                        </div>
                      )}
                      <p className="text-xs tabular-nums text-muted-foreground-strong">
                        {numero(r.activos)} activos · {conversion}
                        {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
                        {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
                      </p>
                      {rezago != null && (
                        <p className="text-xs tabular-nums text-muted-foreground-strong">
                          {rezago.toques > 0
                            ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
                            : 'Sin toques registrados en 7 días'}
                        </p>
                      )}
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </Card>
      </div>
    </div>
  )
}
