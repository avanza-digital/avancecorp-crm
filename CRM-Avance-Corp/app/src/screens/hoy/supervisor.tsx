import { SlaOperacionBoundary } from '@/components/app/sla-operacion'
import { useModoSla } from '@/data/sla-operacion-queries'
// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
// ya trae: sus leads + los de sus analistas + parkeados de SU bandeja.
// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
import {
  AlertTriangle,
  ChevronRight,
  Inbox,
  ListChecks,
  Target,
  Users,
  UsersRound,
  Wallet,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
import { AccionesContacto } from '@/components/app/contacto'
import { AgendaEquipoPanel } from './agenda-equipo'
import { useDatosSupervisor } from './datos-supervisor'
import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
import { TresCosas } from './tres-cosas'
import { BUCKET_LABEL, colorMeta, haceTexto } from '@/lib/inteligencia'
import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
import {
  derivarNovedades,
  fotoDeVisita,
  guardarFotoVisita,
  leerFotoVisita,
  resumenNovedades,
  type NovedadesVisita,
} from '@/lib/visita-sin-movimiento'
import { useSplashVisible } from '@/lib/splash-visible'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { moneyK, numero } from '@/lib/format'
import { cn } from '@/lib/utils'
import { hashDe } from '@/lib/router'
import { tresCosasDeHoy } from '@/lib/tres-cosas'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
import { textoConversionOperativa } from '@/lib/metricas-vendedores'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'

// Tope de la cola del equipo: los primeros son la plata (colaDe ya ordena por
// severidad); el resto vive tras "Ver los N pendientes" para que la Agenda del
// equipo (montada debajo) no quede varios pantallazos abajo.
const COLA_VISIBLES = 8

// Pestañas de la cola (2026-08-23, «una cosa se avisa en un solo lugar»):
// «Leads sin movimiento» era una tercera tarjeta sobre los MISMOS leads
// abiertos que la cola, así que un lead con 6 días salía dos veces en el mismo
// pantallazo. Ahora es una pestaña de la misma tarjeta: mismo conteo, mismo
// tope del RPC, un solo lugar. Urgente = severidad crítica y media.
type PestanaCola = 'urgente' | 'sin_movimiento' | 'todo'
const PESTANAS_COLA: ReadonlyArray<{ id: PestanaCola; label: string }> = [
  { id: 'urgente', label: 'Urgente' },
  { id: 'sin_movimiento', label: 'Sin movimiento' },
  { id: 'todo', label: 'Todo' },
]

/** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
function semaforoDias(d: number): string {
  if (d > 5) return SEMAFORO.critico
  if (d >= 2) return SEMAFORO.atencion
  return SEMAFORO.ok
}

export function HoySupervisor(): JSX.Element {
  const modoSla = useModoSla()
  const { ambito, actividades, tareas, equipo } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola — en sesión real
  // esos vencimientos ya llegan resueltos dentro de cola_accion_fn, así que el
  // RPC de estado SLA ni se pide (habilitado = demo).
  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
  // Meta, reparto, agenda y tipo de cambio: derivación COMPARTIDA con el
  // puesto de mando (./datos-supervisor.ts). Aquí queda lo propio del modo
  // legado: la cola cola_accion_fn, sus pestañas y la visita F4.3.
  const {
    resumenOp,
    resumen,
    vendedoresOp,
    rank,
    tc,
    capitalPronostico,
    esperaMasLargaReparto,
    totalPorRepartir,
    detalleReparto,
    etiquetaAccesoReparto,
    cumplimientoMensual,
    filasMeta,
    hayErrorMensual,
    reintentarMensual,
    datosAgenda,
    errorAgenda,
    cargandoAgenda,
    recargarAgenda,
    rezagosAgenda,
  } = useDatosSupervisor()
  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
  const [colaExpandida, setColaExpandida] = useState(false)
  // Pestaña elegida a mano; `null` = automática (la primera con filas), así
  // un supervisor que entra por la mañana aterriza donde hay trabajo.
  const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)

  // cola_accion_fn → cola + estancados + tile "sin responder".
  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
  const cola = colaOp.cola

  // Nombres para los estancados del payload (el servidor no manda nombres de
  // personas): join con el roster completo, una sola vez por render.
  const nombrePorId = useMemo(
    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
    [equipo],
  )

  // Filas y conteos por pestaña. «Todo» cuenta el universo del RPC (`total`),
  // no las filas recortadas por p_limite; «Urgente» solo puede contar lo que
  // llegó. Con estancados al tope, el conteo dice «50+» y no miente.
  const urgentes = useMemo(
    () => (cola?.items ?? []).filter((i) => i.sev !== 'baja'),
    [cola],
  )
  // El conteo de «Urgente» sale de porSev (el resumen COMPLETO del RPC), no de
  // las filas: p_limite recorta items a 100 y con 120 urgentes la pestaña
  // habría dicho 100 mientras «Todo» decía 120 (hallazgo de Codex).
  const urgenteTotal = (cola?.porSev.critica ?? 0) + (cola?.porSev.media ?? 0)
  const conteoPestana: Record<PestanaCola, string> = {
    urgente: String(urgenteTotal),
    sin_movimiento: cola && cola.estancados.length >= TOPE_ESTANCADOS
      ? `${TOPE_ESTANCADOS}+`
      : String(cola?.estancados.length ?? 0),
    todo: String(cola?.total ?? 0),
  }
  const primeraConFilas: PestanaCola = urgentes.length > 0
    ? 'urgente'
    : (cola?.estancados.length ?? 0) > 0
      ? 'sin_movimiento'
      : 'todo'
  const pestana = pestanaElegida ?? primeraConFilas
  const elegirPestana = (siguiente: PestanaCola) => {
    // F4.3: la visita la cierra el USUARIO al irse de la pestaña. Un vaivén
    // automático de `primeraConFilas` (refetch caído que salta a «Todo» y
    // vuelve al recuperarse) no borra las marcas ni fabrica otra visita.
    if (pestana === 'sin_movimiento' && siguiente !== 'sin_movimiento') {
      visitaAnotadaRef.current = null
      setVisitaCongelada(null)
    }
    setPestanaElegida(siguiente)
  }
  // El colapso se reinicia con CUALQUIER cambio de pestaña — también el
  // automático: la cola se refresca cada minuto y sin esto una pestaña recién
  // aparecida heredaba la expansión de la anterior (hasta 100 filas de golpe).
  useEffect(() => {
    setColaExpandida(false)
  }, [pestana])
  // F4.3: qué EMPEORÓ en «Sin movimiento» desde la última visita. TODO se
  // CONGELA en el instante de anotar: la foto anterior Y las marcas derivadas
  // — una marca que aparece «bajo el cursor» porque la cola se refrescó
  // debajo sería ruido, no memoria (la severidad de la tira sí sigue viva).
  // La visita queda anotada en localStorage en ese mismo instante — anotar
  // «al salir» exigiría un unload handler, y perder una anotación solo marca
  // DE MÁS la próxima vez, la dirección segura. La anotación ESPERA a que el
  // payload esté fresco (enVuelo: persistir una cola vieja podría CALLAR una
  // novedad futura) y a que el workspace sea visible (splash: una «visita»
  // que nadie vio también calla). El ref la hace idempotente (StrictMode
  // ejecuta el efecto dos veces) y fiel a la identidad: si `yo` cambiara en
  // caliente se anota de nuevo para el id nuevo.
  const splashVisible = useSplashVisible()
  const [visitaCongelada, setVisitaCongelada] = useState<{
    novedades: NovedadesVisita | null
    recortada: boolean
  } | null>(null)
  const visitaAnotadaRef = useRef<string | null>(null)
  useEffect(() => {
    if (pestana !== 'sin_movimiento' || yo?.id == null || cola == null) return
    if (colaOp.enVuelo || splashVisible) return
    if (visitaAnotadaRef.current === yo.id) return
    visitaAnotadaRef.current = yo.id
    const fotoAnterior = leerFotoVisita(yo.id)
    guardarFotoVisita(yo.id, fotoDeVisita(cola.estancados, Date.now()))
    setVisitaCongelada({
      novedades: derivarNovedades(cola.estancados, fotoAnterior),
      recortada: cola.estancados.length >= TOPE_ESTANCADOS,
    })
  }, [pestana, cola, colaOp.enVuelo, splashVisible, yo?.id])
  const novedadesVisita = visitaCongelada?.novedades ?? null
  const resumenVisita = resumenNovedades(
    novedadesVisita,
    visitaCongelada?.recortada === true ? TOPE_ESTANCADOS : undefined,
  )
  const filasCola = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
  // Total real de la pestaña activa, para que el botón de expandir no prometa
  // menos de lo que existe cuando el RPC recortó las filas.
  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal

  const errorIndicadores = !yo?.demo
    && Boolean(resumenOp.error || (modoSla.legado && colaOp.error) || vendedoresOp.error)
  const reintentarIndicadores = () => {
    if (resumenOp.error) void resumenOp.recargar()
    if (colaOp.error) void colaOp.recargar()
    if (vendedoresOp.error) void vendedoresOp.recargar()
  }

  // ── F3: «Hoy, tres cosas» — el sistema prioriza el día (ley de Tesler). ──
  // Mismas fuentes que ya están en pantalla; sin dato no hay tarjeta.
  const cosas = useMemo(
    () => tresCosasDeHoy({
      cola,
      totalPorRepartir,
      esperaMasLargaReparto,
      vendedoresAgenda: datosAgenda?.vendedores ?? [],
    }),
    [cola, totalPorRepartir, esperaMasLargaReparto, datosAgenda],
  )
  // «Ver →» de la franja: selecciona la pestaña y le LLEVA el foco (el
  // focus() también hace scroll hasta la tarjeta de la cola).
  const irAPestanaCola = (destino: PestanaCola) => {
    elegirPestana(destino)
    requestAnimationFrame(() => {
      document.getElementById(`tab-cola-${destino}`)?.focus()
    })
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {/* ── F3: la franja manda — máximo tres intervenciones, luego consulta ── */}
      {modoSla.legado && <TresCosas cosas={cosas} onIrAPestana={irAPestanaCola} />}

      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {/* F2 (figura-fondo): los KPIs son CONSULTA, no alarma — iconos en
            neutro. Desde F3 TODOS: la urgencia de «Nuevos sin responder»
            vive en la franja, que es su reemplazo. */}
        <KpiCard
          label="Pronóstico de capital abierto"
          // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
          // cumplimiento, y no se convierte a una tasa que aquí no se rotula.
          // Fijar PEN a mano titulaba «S/ 0» a un equipo que vende en dólares.
          value={capitalPronostico ? capitalPronostico.valor : '—'}
          icon={Wallet}
          color={SEMAFORO.neutro}
          sub={
            capitalPronostico?.otra
              ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte`
              : capitalPronostico?.soloDolares
                ? 'Pipeline (USD)'
                : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0
                  ? 'Sin montos estimados — complétalos en cada ficha'
                  : 'Pipeline (PEN) · abiertos con analista'
          }
          delay={0}
        />
        <KpiCard
          label="Leads activos del equipo"
          value={resumen ? String(resumen.totales.asignados) : '—'}
          icon={Users}
          color={SEMAFORO.neutro}
          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
          delay={60}
        />
        {/* Sin payload, los subs NO afirman estados positivos («todos
            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
        <KpiCard
          label="Nuevos sin responder"
          value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
          icon={AlertTriangle}
          color={SEMAFORO.neutro}
          sub={
            cola == null
              ? 'Sin dato por ahora'
              : (cola.porBucket.sin_responder ?? 0) > 0
                ? 'Sin primer contacto'
                : 'Todos los nuevos fueron contactados'
          }
          delay={120}
        />
        <a
          href={hashDe('derivaciones')}
          aria-label={etiquetaAccesoReparto}
          className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          {/* F2: fuera el acento ámbar — la urgencia del reparto vive en la
              campana (grupo) y desde F3 en la franja; el KPI es el conteo. */}
          <KpiCard
            label="Por repartir"
            value={totalPorRepartir == null ? '—' : String(totalPorRepartir)}
            icon={Inbox}
            color={SEMAFORO.neutro}
            sub={detalleReparto}
            delay={180}
          />
        </a>
      </div>

      <AvisoDegradacion
        activo={errorIndicadores}
        queReintenta="de los indicadores del equipo"
        onReintentar={reintentarIndicadores}
      >
        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      <div className="grid gap-4 lg:grid-cols-5">
        <div className="space-y-4 lg:col-span-3">
          {/* ── Cola del equipo (con dueño de cada item) ── */}
          <SlaOperacionBoundary legado={(
          <Card className="overflow-hidden">
            <SectionHead
              icon={ListChecks}
              title="Cola del equipo"
              right={
                cola ? (
                  // Patrón tablist de la casa (ranking-vendedores): aria-selected
                  // + aria-controls, tabindex itinerante y flechas. Sin el
                  // conteo en el nombre accesible el lector de pantalla no
                  // sabría cuál pestaña tiene trabajo.
                  <div role="tablist" aria-label="Filtrar la cola" className="inline-flex rounded-lg bg-muted/60 p-0.5">
                    {PESTANAS_COLA.map((p, indice) => (
                      <button
                        key={p.id}
                        id={`tab-cola-${p.id}`}
                        type="button"
                        role="tab"
                        aria-selected={pestana === p.id}
                        aria-controls="panel-cola"
                        aria-label={`${p.label}: ${conteoPestana[p.id]}`}
                        tabIndex={pestana === p.id ? 0 : -1}
                        onClick={() => elegirPestana(p.id)}
                        onKeyDown={(e) => {
                          // Flechas con vuelta + Home/End (patrón APG completo).
                          const destino = e.key === 'ArrowRight'
                            ? (indice + 1) % PESTANAS_COLA.length
                            : e.key === 'ArrowLeft'
                              ? (indice - 1 + PESTANAS_COLA.length) % PESTANAS_COLA.length
                              : e.key === 'Home'
                                ? 0
                                : e.key === 'End'
                                  ? PESTANAS_COLA.length - 1
                                  : null
                          if (destino == null) return
                          e.preventDefault()
                          const siguiente = PESTANAS_COLA[destino]
                          if (!siguiente) return
                          elegirPestana(siguiente.id)
                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
                        }}
                        className={cn(
                          // Fitts: min-h para un objetivo táctil cómodo.
                          'min-h-7 cursor-pointer rounded-md px-3 py-1.5 text-[11px] font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                          pestana === p.id
                            ? 'bg-card text-foreground shadow-sm'
                            // Gris FUERTE: 11px sobre bg-muted no llega a 4.5:1
                            // con el muted normal (revisor a11y, M1).
                            : 'text-muted-foreground-strong hover:text-foreground',
                        )}
                      >
                        {p.label} <span aria-hidden>{conteoPestana[p.id]}</span>
                      </button>
                    ))}
                  </div>
                ) : (
                  <span className="text-xs text-muted-foreground">—</span>
                )
              }
            />
            {cola == null ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {colaOp.error
                    ? 'La cola del equipo no está disponible en este momento.'
                    : 'Cargando la cola del equipo…'}
                </p>
              </CardContent>
            ) : pestana === 'sin_movimiento' ? (
              // ── Sin movimiento (≥5 días) — bloque estancados del RPC. El tope
              //    de 50 es señal, no listado: con 50 justos la pestaña dice 50+.
              //    tabIndex 0 SOLO en el panel vacío (patrón WAI-ARIA: el panel
              //    sin interactivos debe ser enfocable para que Tab no lo salte). ──
              <div
                id="panel-cola"
                role="tabpanel"
                aria-labelledby="tab-cola-sin_movimiento"
                tabIndex={cola.estancados.length === 0 ? 0 : undefined}
              >
                {cola.estancados.length === 0 ? (
                  <CardContent className="pb-5 pt-0">
                    <p className="text-sm text-muted-foreground">
                      Ningún lead del equipo lleva 5 días o más sin actividad.
                    </p>
                  </CardContent>
                ) : (
                  <>
                    {/* F4.3: el resumen de novedades va ANTES de la lista —
                        es la razón para escanearla. Solo existe si hay algo
                        que decir (el silencio también es información). */}
                    {resumenVisita != null && (
                      <p className="border-t border-border/60 px-5 py-2 text-[11px] font-semibold text-muted-foreground-strong">
                        {resumenVisita}
                      </p>
                    )}
                    <div className="divide-y divide-border/60 border-t border-border/60">
                      {cola.estancados.map((a) => {
                        // F2: la gravedad va UNA vez, en la tira (rojo desde 7
                        // días, ámbar 5–6); el texto queda en gris de contexto.
                        // F4.3: la novedad es CATEGÓRICA, no de severidad —
                        // chip violeta para el que entró; el que cruzó a
                        // crítico ya tiene la tira roja y lo dice el texto.
                        const esNuevo = novedadesVisita?.nuevos.has(a.leadId) === true
                        const cruzoACritico = novedadesVisita?.agravados.has(a.leadId) === true
                        const vendedor = (a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'
                        return (
                          <button
                            key={a.leadId}
                            type="button"
                            onClick={() => abrirLead(a.leadId)}
                            // El label DICTA todo lo visible: el aria-label
                            // pisa el contenido para un SR, así que lleva al
                            // analista (a11y M1: de quién es el lead es parte
                            // de la decisión), los días (la criticidad no
                            // puede vivir solo en la tira de color) y el
                            // literal del chip («nuevo aquí») para que el
                            // dictado por voz también lo alcance (2.5.3).
                            aria-label={`Abrir ficha de ${a.nombre} (${vendedor}), sin actividad ${haceTexto(a.dias)}${
                              esNuevo
                                ? ', nuevo aquí desde tu última visita'
                                : cruzoACritico ? ', crítico desde tu última visita' : ''
                            }`}
                            className="flex w-full cursor-pointer items-center gap-2.5 border-l-[3px] py-2.5 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
                            style={{ borderLeftColor: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
                          >
                            <div className="min-w-0 flex-1 leading-tight">
                              <p className="truncate text-sm font-semibold">
                                {a.nombre}{' '}
                                <span className="text-xs font-medium text-muted-foreground">
                                  ({vendedor})
                                </span>
                              </p>
                              <p className="text-[11px] font-medium text-muted-foreground">
                                Sin actividad {haceTexto(a.dias)}
                                {/* Gris FUERTE (a11y F4.3 #2): es la única
                                    señal textual del cruce y el gris débil a
                                    11px roza el 4.5:1 en hover. */}
                                {cruzoACritico && (
                                  <span className="text-muted-foreground-strong"> · crítico desde tu última visita</span>
                                )}
                              </p>
                            </div>
                            {esNuevo && (
                              <Badge color={SEMAFORO.violeta} variant="outline" className="shrink-0 whitespace-nowrap">
                                Nuevo aquí
                              </Badge>
                            )}
                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                          </button>
                        )
                      })}
                    </div>
                  </>
                )}
              </div>
            ) : filasCola.length === 0 ? (
              <CardContent id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} tabIndex={0} className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {pestana === 'urgente'
                    ? 'Nada urgente — ninguna fila crítica ni media en la cola.'
                    : 'Sin pendientes — el equipo está al día con todos sus leads abiertos.'}
                </p>
              </CardContent>
            ) : (
              <div id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} className="divide-y divide-border/60 border-t border-border/60">
                {/* Fila = div role="button" (no <button>: contiene los links de
                    AccionesContacto y un botón no puede anidar interactivos).
                    F2 (pregnancia): la severidad se dice UNA vez — la tira de
                    3 px. Fuera el punto, el badge de etapa y el azul del monto;
                    la etapa va en texto plano delante del motivo. El pl de
                    17 px compensa los 3 px de la tira: el contenido queda a
                    20 px, alineado con la cabecera (Codex F2). */}
                {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map((i) => {
                  const abrir = () => abrirLead(i.lead.id)
                  return (
                    <div
                      key={i.lead.id}
                      role="button"
                      tabIndex={0}
                      data-sev={i.sev}
                      onClick={abrir}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault()
                          abrir()
                        }
                      }}
                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
                      className="flex w-full cursor-pointer items-center gap-3 border-l-[3px] py-3 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
                      style={{ borderLeftColor: i.sev === 'baja' ? 'transparent' : SEV_COLOR[i.sev] }}
                    >
                      <div className="min-w-0 flex-1 leading-tight">
                        <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
                        <p className="truncate text-xs text-muted-foreground">
                          {BUCKET_LABEL[i.bucket]} · {i.motivo}
                        </p>
                      </div>
                      {i.lead.monto_estimado != null && (
                        <span className="hidden shrink-0 text-xs font-semibold tabular-nums text-muted-foreground sm:inline">
                          {moneyK(i.lead.monto_estimado, i.lead.moneda)}
                        </span>
                      )}
                      {i.lead.vendedor_nombre ? (
                        <span className="flex shrink-0 items-center gap-1.5">
                          <Avatar nombre={i.lead.vendedor_nombre} className="size-6 text-[9px]" />
                          <span className="hidden max-w-[110px] truncate text-xs text-muted-foreground md:inline">
                            {i.lead.vendedor_nombre}
                          </span>
                        </span>
                      ) : (
                        <span className="shrink-0 text-xs font-medium text-muted-foreground">sin asignar</span>
                      )}
                      <AccionesContacto lead={i.lead} compacto />
                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                    </div>
                  )
                })}
                {filasCola.length > COLA_VISIBLES && (
                  <button
                    type="button"
                    onClick={() => setColaExpandida((e) => !e)}
                    aria-expanded={colaExpandida}
                    className="flex w-full cursor-pointer items-center justify-center gap-1 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
                  >
                    <ChevronRight
                      className={cn('size-3.5 shrink-0 transition-transform', colaExpandida && 'rotate-90')}
                      aria-hidden
                    />
                    {colaExpandida
                      ? `Mostrar solo los ${COLA_VISIBLES} más urgentes`
                      // Con más pendientes que el p_limite del RPC, el botón no
                      // puede prometer el total de la pestaña: dice lo que muestra.
                      : totalPestanaActiva > filasCola.length
                        ? `Ver los ${filasCola.length} más urgentes de ${totalPestanaActiva}`
                        : `Ver los ${filasCola.length} pendientes`}
                  </button>
                )}
              </div>
            )}
          </Card>
          )}>
            <Card>
              <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
                <div className="space-y-1">
                  <h2 className="text-sm font-bold">Seguimiento del equipo</h2>
                  <p className="text-xs text-muted-foreground">Prioriza las gestiones y revisa los plazos de cada analista.</p>
                </div>
                <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
                  Abrir seguimiento <ChevronRight className="size-4" aria-hidden />
                </a>
              </CardContent>
            </Card>
          </SlaOperacionBoundary>

          {/* Rentabilidad R3: tus solicitudes de tasa en curso (solo si hay). */}
          <TasasAutorizadasAnalistaPanel />

          {/* ── Agenda del equipo (Fase F — quién registra, cierra y arrastra) ── */}
          <AgendaEquipoPanel
            datos={datosAgenda}
            cargando={cargandoAgenda}
            error={errorAgenda}
            modoDemo={yo?.demo === true}
            onReintentar={recargarAgenda}
            equipo={equipo}
          />
        </div>
        <div className="space-y-4 lg:col-span-2">
          {/* ── Tu equipo hoy (semáforo por analista) ── */}
          <Card className="overflow-hidden">
            <SectionHead
              icon={UsersRound}
              title="Tu equipo hoy"
              right={tc ? (
                <span className="text-xs text-muted-foreground">
                  Capital en proceso · {rotuloTipoCambio(tc.promedio, tc.fuente)}
                </span>
              ) : undefined}
            />
            {rank == null ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">
                  {vendedoresOp.error
                    ? 'El resumen por analista no está disponible en este momento.'
                    : 'Cargando el resumen por analista…'}
                </p>
              </CardContent>
            ) : rank.length === 0 ? (
              <CardContent className="pb-5 pt-0">
                <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
              </CardContent>
            ) : (
              <div className="divide-y divide-border/60 border-t border-border/60">
                {rank.map((r) => {
                  const c = semaforoDias(r.diasSinActividadMax)
                  // Rezago de agenda del miembro (mismos umbrales del panel
                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
                  const rez = rezagosAgenda.get(r.m.perfil_id)
                  // El rezago de agenda TAMBIÉN es señal: sin esto, quien tocó
                  // ayer pero arrastra 10 vencidas quedaba sin ninguna marca
                  // visual (hallazgo IMPORTANTE de Codex sobre F2).
                  const conRezagoAgenda = rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)
                  const colorPunto = r.activos === 0
                    ? SEMAFORO.neutro
                    : c !== SEMAFORO.ok
                      ? c
                      : SEMAFORO.atencion
                  const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
                  return (
                    <div key={r.m.perfil_id} className="px-5 py-3">
                      <div className="flex items-center gap-2.5">
                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
                        <div className="min-w-0 flex-1 leading-tight">
                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
                          <p className="text-[11px] tabular-nums text-muted-foreground">
                            {r.activos} activos · {r.conversion == null
                              ? r.conversionDisponible && r.divisorConversion === 0
                                ? 'sin divisor mensual'
                                : 'dato de conversión no disponible'
                              : `${textoConversionOperativa(r.conversion)} conversión`}
                            {r.operacionesCartera != null && r.operacionesCartera > 0
                              ? ` · ${numero(r.operacionesCartera)} de cartera`
                              : ''}
                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
                          </p>
                        </div>
                        {/* Decisión #10: el total unificado es el número grande y el
                            desglose por moneda va debajo. Sin TC degrada al PEN de
                            siempre — el USD no entra al total sin una tasa real. */}
                        <div className="shrink-0 text-right leading-tight">
                          <p className="text-sm font-extrabold tabular-nums text-foreground">
                            {cap.total != null ? moneyK(cap.total) : '—'}
                          </p>
                          <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
                        </div>
                      </div>
                      <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 gap-y-1 pl-[46px]">
                        {/* F2: el punto solo cuando HAY señal (ámbar 2–5 d,
                            rojo >5 d, neutro sin cartera). Pintar «al día» de
                            azul en cada fila gastaba el color en nada. Sin
                            leads abiertos no hay «al día» que celebrar:
                            `semaforoDias(0)` devolvía azul y un analista sin
                            cartera se pintaba como el que va al corriente. */}
                        {(r.activos === 0 || c !== SEMAFORO.ok || conRezagoAgenda) && (
                          <span
                            data-testid="equipo-semaforo"
                            className="size-2 shrink-0 rounded-full"
                            style={{ background: colorPunto }}
                            aria-hidden
                          />
                        )}
                        <span className="text-[11px] text-muted-foreground">
                          {r.activos === 0
                            ? 'Sin leads abiertos'
                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
                          {/* El rezago va en TEXTO pegado a la persona (aquí se
                              juzga, decisión 1 del 2026-08-23); el único chip
                              es el no-show repetido — uno de los dos rojos del
                              presupuesto de color. */}
                          {rez != null && rez.vencidas > 0
                            && ` · ${rez.vencidas} ${rez.vencidas === 1 ? 'vencida' : 'vencidas'}`}
                          {rez != null && rez.leads_sin_accion > 0
                            && ` · ${rez.leads_sin_accion} sin acción`}
                        </span>
                        {rez != null && rez.no_asistio >= 2 && (
                          <span className="ml-auto">
                            {/* solid: el soft (rojo sobre tinte) da 4.01:1 a 11px
                                y no llega a AA (revisor a11y, M2). */}
                            <Badge color={SEMAFORO.critico} variant="solid">{rez.no_asistio} no asistió</Badge>
                          </span>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </Card>

          {/* ── Cumplimiento confirmado del equipo ── */}
          <Card>
            <SectionHead
              icon={Target}
              title="Cumplimiento del equipo"
              right={<span className="text-xs text-muted-foreground">contratos confirmados · este mes</span>}
            />
            <CardContent className="space-y-4 pb-5 pt-0">
              {filasMeta.map((f) => (
                <div key={f.label}>
                  <div className="mb-1.5 flex items-baseline justify-between gap-2">
                    <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
                    <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
                  </div>
                  {f.nota && (
                    <p className="mb-1 text-[10.5px] tabular-nums text-muted-foreground">{f.nota}</p>
                  )}
                  {f.sinDato ? (
                    <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
                  ) : (
                    <Progress value={f.pct} color={colorMeta(f.pct)} />
                  )}
                </div>
              ))}
              <p className="text-[10.5px] text-muted-foreground">
                El capital en dólares entra al total convertido a tipo de cambio real. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
              </p>
              {hayErrorMensual && (
                <Button variant="ghost" size="sm" onClick={reintentarMensual}>
                  Reintentar
                </Button>
              )}
            </CardContent>
          </Card>

          {/* ── Por empresa: de dónde vino cada sol (Avance vs. COOPAC). Se
               oculta solo si el mes no tiene cierres en cooperativas. ── */}
          <DesglosePorEmpresa
            demo={yo?.demo === true}
            porVendedor={cumplimientoMensual?.porVendedor ?? null}
          />
        </div>
      </div>

      <p className="text-[11px] text-muted-foreground">
        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
      </p>
    </div>
  )
}
