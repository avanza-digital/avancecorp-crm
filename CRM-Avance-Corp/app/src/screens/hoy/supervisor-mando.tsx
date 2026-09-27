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
import { useEffect, useId, useMemo, useRef, useState, type JSX } from 'react'
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
import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type CosaDeHoy } from '@/lib/tres-cosas'
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

// La severidad TAMBIÉN en texto: el color nunca va solo.
const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = { critica: 'Hoy', atencion: 'Esta semana' }
const SEV_TEXTO_COLOR: Record<CosaDeHoy['severidad'], string> = { critica: 'var(--destructive-text)', atencion: 'var(--warning-text)' }
const SEV_BORDE: Record<CosaDeHoy['severidad'], string> = { critica: SEMAFORO.critico, atencion: SEMAFORO.atencion }

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
  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)

  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
  // Fail-closed: TanStack conserva la última respuesta tras un refetch
  // fallido; con error, la cola NO se muestra como vigente.
  const pagina = consultaCola.error ? undefined : consultaCola.data
  const paginaVigente = pagina?.modo === 'activo' ? pagina : undefined
  // Las decisiones del día miran a TODO el equipo: sin filtro por analista.
  // Sin filtro es la MISMA clave que la cola (TanStack la comparte); con
  // filtro es la consulta que la cola tenía antes de filtrar.
  const consultaEquipo = useColaSlaPagina({ senal: pestana, etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
  const paginaEquipoVigente = paginaEquipo?.modo === 'activo' ? paginaEquipo : undefined

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
    // La tarjeta de primera gestión ES esa pestaña: si se va de ella, se cierra.
    if (id !== 'primera_atencion' && decisionAbierta === 'primera_gestion') setDecisionAbierta(null)
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

  // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
  // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
  // y «Nada que decidir» solo se afirma con TODAS las fuentes confirmadas.
  const primeraGestionPendiente = paginaEquipoVigente?.totales.primera_atencion ?? null
  const entradaCosas = {
    cola: null,
    totalPorRepartir: datos.resumenOp.error ? null : datos.totalPorRepartir,
    esperaMasLargaReparto: datos.esperaMasLargaReparto,
    vendedoresAgenda: datos.agendaConfirmada?.vendedores ?? [],
    primeraGestionPendiente,
  }
  const candidatos = candidatosDeHoy(entradaCosas)
  const cosas = tresCosasDeHoy(entradaCosas)
  const estaSemana = candidatos.slice(cosas.length)
  const fuentesCaidas = [
    consultaEquipo.error ? 'el seguimiento' : null,
    datos.errorAgenda ? 'la agenda' : null,
    datos.resumenOp.error ? 'el reparto' : null,
  ].filter((f): f is string => f != null)
  const fuentesListas = paginaEquipoVigente != null
    && datos.agendaConfirmada != null
    && datos.resumen != null
  const reintentarDecisiones = () => {
    if (consultaEquipo.error) void consultaEquipo.refetch()
    if (datos.errorAgenda) datos.recargarAgenda()
    if (datos.resumenOp.error) void datos.resumenOp.recargar()
  }

  const alternarDecision = (cosa: CosaDeHoy) => {
    const abrir = decisionAbierta !== cosa.id
    setDecisionAbierta(abrir ? cosa.id : null)
    if (cosa.id !== 'primera_gestion') return
    // Primera gestión: la cola de abajo pasa a ESA pestaña, para todo el equipo.
    if (abrir) {
      setPestana('primera_atencion')
      setAnalistaId(null)
      setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
    } else if (pestana === 'primera_atencion') {
      setPestana('pendientes')
      setAnuncio('Mostrando los pendientes de todo el equipo')
    }
  }
  const verPrimeraGestion = () => {
    setDecisionAbierta('primera_gestion')
    setPestana('primera_atencion')
    setAnalistaId(null)
    setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
    requestAnimationFrame(() => document.getElementById(`${idPanelCola}-tab-primera_atencion`)?.focus())
  }

  /** Una línea de contexto con datos YA confirmados; sin dato, nada. */
  const contextoDe = (cosa: CosaDeHoy): string | null => {
    switch (cosa.id) {
      case 'primera_gestion':
        return 'Revisa la primera gestión con cada analista: abajo quedan solo esos casos.'
      case 'no_asistio':
      case 'sin_accion': {
        if (cosa.vendedorId != null) {
          const r = rezagosConfirmados.get(cosa.vendedorId)
          if (!r) return null
          return `En 7 días: ${numero(r.no_asistio)} sin asistir · ${numero(r.vencidas)} tareas vencidas · ${numero(r.leads_sin_accion)} sin próxima acción.`
        }
        const nombres = (datos.agendaConfirmada?.vendedores ?? [])
          .filter((v) => v.rol === 'vendedor' && v.activo
            && (cosa.id === 'no_asistio' ? v.no_asistio >= 2 : v.leads_sin_accion >= 3))
          .map((v) => `${primerNombre(v.nombre)} (${cosa.id === 'no_asistio' ? v.no_asistio : v.leads_sin_accion})`)
        return nombres.length > 0 ? nombres.join(' · ') : null
      }
      case 'por_repartir':
        return 'Leads sin analista en tu bandeja. El reparto se hace en Derivar leads.'
      default:
        return null
    }
  }

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

      {modo.activo && (
        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
          <div className="flex items-center justify-between gap-4">
            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} />}
          </div>
          {fuentesCaidas.length > 0 && (
            <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-destructive/30 bg-card px-4 py-2.5">
              <p className="text-xs">
                Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
              </p>
              <Button variant="outline" size="sm" onClick={reintentarDecisiones}>
                <RefreshCw aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {cosas.length === 0 ? (
            fuentesCaidas.length > 0 ? null : (
              <Card>
                <CardContent className="py-4">
                  <p role="status" className="text-sm text-muted-foreground">
                    {fuentesListas ? 'Nada que decidir ahora mismo.' : 'Revisando las decisiones del día…'}
                  </p>
                </CardContent>
              </Card>
            )
          ) : (
            <div className="grid gap-3.5 lg:grid-cols-3">
              {cosas.map((cosa) => (
                <TarjetaDecision
                  key={cosa.id}
                  cosa={cosa}
                  abierta={decisionAbierta === cosa.id}
                  contexto={contextoDe(cosa)}
                  idContexto={`${idPanelCola}-decision-${cosa.id}`}
                  onAlternar={() => alternarDecision(cosa)}
                  onVerPrimeraGestion={verPrimeraGestion}
                  etiquetaReparto={datos.etiquetaAccesoReparto}
                />
              ))}
            </div>
          )}
        </section>
      )}

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

/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
  cosa: CosaDeHoy
  onVerPrimeraGestion: () => void
  etiquetaReparto: string
}): JSX.Element {
  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
  if (cosa.id === 'primera_gestion') {
    return (
      <button type="button" className={clase} aria-label={`Ver las ${cosa.texto} en la cola`} onClick={onVerPrimeraGestion}>
        Ver <ChevronRight className="size-3.5" aria-hidden />
      </button>
    )
  }
  if (cosa.id === 'por_repartir') {
    return (
      <a href={hashDe('derivaciones')} className={clase} aria-label={etiquetaReparto}>
        Repartir <ChevronRight className="size-3.5" aria-hidden />
      </a>
    )
  }
  if (cosa.id === 'no_asistio' || cosa.id === 'sin_accion') {
    // La cola no contiene citas ni leads «sin próxima acción»: filtrarla
    // enseñaría OTROS casos. La decisión se toma viendo el día del equipo.
    const label = cosa.vendedorId != null ? 'Ver su día' : 'Ver el equipo'
    return (
      <a href={hashDe('gestion-diaria')} className={clase} aria-label={`${label}: ${cosa.texto}`}>
        {label} <ChevronRight className="size-3.5" aria-hidden />
      </a>
    )
  }
  // Candidatos del modo legado: aquí no aparecen (la cola legada llega null),
  // pero si algún día lo hicieran, su lugar es el módulo de seguimiento.
  return (
    <a href={hashDe('seguimiento')} className={clase} aria-label={`${cosa.accion}: ${cosa.texto}`}>
      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
    </a>
  )
}

function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVerPrimeraGestion, etiquetaReparto }: {
  cosa: CosaDeHoy
  abierta: boolean
  contexto: string | null
  idContexto: string
  onAlternar: () => void
  onVerPrimeraGestion: () => void
  etiquetaReparto: string
}): JSX.Element {
  const { cifra, resto } = partesDeCosa(cosa.texto)
  return (
    <Card
      data-decision={cosa.id}
      className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
      style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
    >
      <div className="flex items-center gap-2 py-2 pl-4 pr-3">
        <button
          type="button"
          aria-expanded={abierta}
          aria-controls={idContexto}
          aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}`}
          onClick={onAlternar}
          className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 rounded-md text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          {cifra && (
            <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>
          )}
          <span className="min-w-0 flex-1 leading-tight">
            <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
              {SEV_TEXTO[cosa.severidad]}
            </span>
            <span className="block truncate text-[15px] font-bold" title={resto}>{resto}</span>
          </span>
          <ChevronRight
            className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
            aria-hidden
          />
        </button>
        <AccionDecision cosa={cosa} onVerPrimeraGestion={onVerPrimeraGestion} etiquetaReparto={etiquetaReparto} />
      </div>
      <p id={idContexto} hidden={!abierta} className="border-t border-border/60 px-4 py-2.5 text-xs text-muted-foreground-strong">
        {contexto ?? 'Sin más detalle confirmado por ahora.'}
      </p>
    </Card>
  )
}

/** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerPrimeraGestion: () => void }): JSX.Element {
  const [abierto, setAbierto] = useState(false)
  const contenedor = useRef<HTMLDivElement>(null)
  const disparador = useRef<HTMLButtonElement>(null)
  const idLista = useId()
  useEffect(() => {
    if (!abierto) return
    const fuera = (e: PointerEvent) => {
      if (!contenedor.current?.contains(e.target as Node)) setAbierto(false)
    }
    // Esc cierra y devuelve el foco al disparador, esté donde esté el foco
    // dentro de la lista (y también si quedó fuera: el popover no atrapa).
    const escape = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      setAbierto(false)
      if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
    }
    document.addEventListener('pointerdown', fuera)
    document.addEventListener('keydown', escape)
    return () => {
      document.removeEventListener('pointerdown', fuera)
      document.removeEventListener('keydown', escape)
    }
  }, [abierto])
  return (
    <div ref={contenedor} className="relative">
      <button
        ref={disparador}
        type="button"
        aria-expanded={abierto}
        aria-controls={idLista}
        onClick={() => setAbierto((v) => !v)}
        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
      >
        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
        Esta semana · {cosas.length}
        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
      </button>
      <ul
        id={idLista}
        hidden={!abierto}
        aria-label="Decisiones para esta semana"
        className="ac-pop absolute right-0 top-11 z-20 w-[340px] max-w-[90vw] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]"
      >
        {cosas.map((c) => (
          <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_BORDE[c.severidad] }} aria-hidden />
            <span className="min-w-0 flex-1">
              <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
            </span>
            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={`Repartir: ${c.texto}`} />
          </li>
        ))}
      </ul>
    </div>
  )
}
