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
import { AlertTriangle, ChevronRight, Inbox, ListChecks, Target, Users, UsersRound, Wallet } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
import { AccionesContacto } from '@/components/app/contacto'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
import { estadoCasoSupervision, momentoCaso, nombresCortos } from '@/lib/cola-supervision'
import { conteoSemaforoEquipo, lecturaAnalista, type LecturaAnalista } from '@/lib/senal-equipo'
import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type CosaDeHoy } from '@/lib/tres-cosas'
import { colorMeta, haceTexto } from '@/lib/inteligencia'
import { resumenAgenda } from '@/lib/agenda-equipo-vista'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { textoConversionOperativa } from '@/lib/metricas-vendedores'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import { moneyCompacta, moneyK, numero, porcentajeConversionCanonica, primerNombre } from '@/lib/format'
import { hashDe } from '@/lib/router'
import { cn } from '@/lib/utils'
import { usePanelesActions } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import type { FiltrosSla } from '@/lib/sla-operacion'
import { HoySupervisor } from './supervisor'
import { useDatosSupervisor } from './datos-supervisor'
import { AgendaEquipoPanel } from './agenda-equipo'
import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'

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

// Regla de Miguel (27/09/2026): «para qué quiero saber si no puedo verlo».
// TODO número de esta pantalla se abre y enseña la lista que hay detrás.
const CLASE_CIFRA = 'inline-flex min-h-9 cursor-pointer items-center gap-1 rounded-md px-1 -mx-1 text-left underline-offset-4 decoration-muted-foreground/60 hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
const CLASE_KPI_ENLACE = 'relative block h-full w-full cursor-pointer rounded-xl text-left text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background'

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
const TEXTO_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
  critico: 'En rojo',
  atencion: 'En ámbar',
  neutro: 'Sin cartera abierta',
}

/**
 * Marca del nivel con FORMA además de color (rojo y ámbar se confunden con
 * protanopia): triángulo = rojo, punto lleno = ámbar, aro = neutro.
 */
function MarcaNivel({ nivel }: { nivel: LecturaAnalista['nivel'] }): JSX.Element {
  if (nivel == null) return <span className="size-3 shrink-0" aria-hidden />
  if (nivel === 'critico') {
    return <AlertTriangle data-testid="equipo-semaforo" data-nivel={nivel} className="size-3 shrink-0" style={{ color: SEMAFORO.critico }} aria-hidden />
  }
  return (
    <span
      data-testid="equipo-semaforo"
      data-nivel={nivel}
      className={cn('size-2 shrink-0 rounded-full', nivel === 'neutro' && 'border-2 bg-transparent')}
      style={nivel === 'neutro' ? { borderColor: COLOR_NIVEL.neutro } : { background: COLOR_NIVEL[nivel] }}
      aria-hidden
    />
  )
}

export function HoySupervisorMando(): JSX.Element {
  const modo = useModoSla()
  const { yo } = useAuth()
  if (modo.legado) return <HoySupervisor />
  // Cambiar de identidad o de revisión del seguimiento remonta la pantalla:
  // ningún filtro ni selección sobrevive sobre datos de otra (como
  // SlaOperacionBoundary).
  return <PuestoDeMando key={`${yo?.id ?? ''}|${yo?.rol ?? ''}|${modo.data?.control_revision ?? 'sin-revision'}`} />
}

function PuestoDeMando(): JSX.Element {
  const modo = useModoSla()
  const datos = useDatosSupervisor()
  const { abrirLead } = usePanelesActions()
  const { yo } = useAuth()
  const { ambito, rank, tc, ahora } = datos
  const idPanelCola = useId()

  const [pestana, setPestana] = useState<PestanaMando>('pendientes')
  const [analistaElegido, setAnalistaId] = useState<string | null>(null)
  // Analistas SELECCIONABLES del equipo (no las filas cargadas): los chips no
  // dependen de lo que haya traído la página ni prometen conteos del cliente.
  const analistas = useMemo(
    () => ambito.vendedores
      .filter((m) => m.activo && m.rol_crm === 'vendedor')
      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
    [ambito.vendedores],
  )
  // El filtro vale solo para quien sigue siendo seleccionable: quien sale, se
  // desactiva o cambia de rol no deja la cola filtrada por un id sin chip.
  const analistaId = analistaElegido != null && analistas.some((m) => m.perfil_id === analistaElegido)
    ? analistaElegido
    : null
  const [anuncio, setAnuncio] = useState('')
  const [abriendo, setAbriendo] = useState<string | null>(null)
  const [errorApertura, setErrorApertura] = useState(false)
  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
  const [detalleAbierto, setDetalleAbierto] = useState(false)
  const tituloDetalle = useRef<HTMLSpanElement>(null)
  // Si el detalle se cierra PARA ir a la cola, el foco va a la pestaña (y no
  // vuelve al botón «Detalle», que es lo que Radix haría por defecto).
  const focoTrasDetalle = useRef<HTMLElement | null>(null)
  const [focoALaCola, setFocoALaCola] = useState(false)
  const abrirDetalle = () => {
    setFocoALaCola(false)
    setDetalleAbierto(true)
  }

  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
  // Fail-closed: TanStack conserva la última respuesta tras un refetch
  // fallido; con error, la cola NO se muestra como vigente.
  const pagina = consultaCola.error ? undefined : consultaCola.data
  // Vigente = modo activo Y la MISMA revisión de reglas que el modo: la caché
  // de TanStack no conoce la revisión y, al remontar, podría servir una página
  // calculada con las reglas anteriores mientras refresca.
  const revisionVigente = modo.data?.control_revision
  const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
  const paginaVigente = esVigente(pagina) ? pagina : undefined
  // Las decisiones del día miran a TODO el equipo y a una clave ESTABLE: los
  // `totales` no dependen de la señal (cola_accion_v2_fn filtra por etapa y
  // analista antes de contarlos), así que cambiar de pestaña no deja la
  // banda sin su fuente mientras llega otra respuesta. Con «Para atender
  // ahora» y sin analista, es la misma clave que la cola: TanStack la comparte.
  const consultaEquipo = useColaSlaPagina({ senal: 'pendientes', etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
  const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined

  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
  // Nombres cortos sin ambigüedad para chips y la columna del analista.
  const cortos = useMemo(
    () => nombresCortos([
      ...analistas.map((m) => m.nombre_completo),
      ...(paginaVigente?.items ?? []).map((i) => i.lead.analista_nombre ?? ''),
    ]),
    [analistas, paginaVigente],
  )
  const corto = (nombre: string | null | undefined) => (nombre ? cortos.get(nombre.trim()) ?? primerNombre(nombre) : '')
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
          const plural = (n: number, uno: string, varios: string) => `${numero(n)} ${n === 1 ? uno : varios}`
          return `En 7 días: ${plural(r.no_asistio, 'cita sin asistir', 'citas sin asistir')} · ${plural(r.vencidas, 'tarea vencida', 'tareas vencidas')} · ${plural(r.leads_sin_accion, 'lead sin próxima acción', 'leads sin próxima acción')}.`
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

  // Los errores del mes (meta, cumplimiento, conversión, TC) también se
  // avisan aquí: la franja muestra «—» y el aviso no espera a abrir «Detalle».
  const errorIndicadores = !datos.sesionReal
    ? false
    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error || datos.hayErrorMensual)
  const reintentarIndicadores = () => {
    if (datos.resumenOp.error) void datos.resumenOp.recargar()
    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
    if (datos.hayErrorMensual) datos.reintentarMensual()
  }

  // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
  const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
  const filaCapital = datos.filasMeta[0]
  const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
  const conversionTexto = datos.conversionMensualError || datos.conversionConfirmada == null
    ? '—'
    : porcentajeConversionCanonica(datos.conversionConfirmada)
  const pronostico = datos.capitalPronostico
  // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
  const pronosticoCorto = pronostico && datos.resumen
    ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
    : '—'

  const tituloCola = nombreAnalista ? `Pendientes de ${corto(nombreAnalista)}` : 'Pendientes del equipo'

  return (
    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>

      {modo.activo && (
        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
          <div className="flex items-center justify-between gap-4">
            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} etiquetaReparto={datos.etiquetaAccesoReparto} />}
          </div>
          <AvisoDegradacion activo={fuentesCaidas.length > 0} queReintenta="de las decisiones del día" onReintentar={reintentarDecisiones}>
            Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
          </AvisoDegradacion>
          {/* Sin todas las fuentes no se ORDENA: una tarjeta ámbar no ocupa el
              puesto de una roja que aún no llegó. Con una fuente caída sí se
              muestra lo confirmado, bajo el aviso de que está incompleto. */}
          {!fuentesListas && fuentesCaidas.length === 0 ? (
            <Card>
              <CardContent className="py-4">
                <p role="status" className="text-sm text-muted-foreground">Revisando las decisiones del día…</p>
              </CardContent>
            </Card>
          ) : cosas.length === 0 ? (
            fuentesCaidas.length > 0 ? null : (
              <Card>
                <CardContent className="py-4">
                  <p role="status" className="text-sm text-muted-foreground">Nada que decidir ahora mismo.</p>
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
      <h2 className="sr-only">Pendientes y equipo</h2>
      <div className="grid gap-4 lg:grid-cols-5">
        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
          <SectionHead
            icon={ListChecks}
            title={tituloCola}
            className="flex-wrap gap-y-2"
            right={modo.activo ? (
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
                        'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                        pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
                      )}
                    >
                      {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
                    </button>
                  )
                })}
              </div>
            ) : undefined}
          />
          {!modo.activo ? (
            <CardContent className="pb-5 pt-0">
              <AvisoDegradacion activo={modo.error != null} queReintenta="del seguimiento" onReintentar={() => void modo.refetch()}>
                No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.
              </AvisoDegradacion>
              {modo.error == null && (
                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
              )}
            </CardContent>
          ) : (
            <>
              {analistas.length > 0 && (
                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
                  <button
                    type="button"
                    aria-pressed={analistaId == null}
                    onClick={() => elegirAnalista(null)}
                    className={cn(
                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
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
                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
                      )}
                    >
                      {corto(m.nombre_completo)}
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
                <div className={cn(consultaCola.error && 'border-t border-border/60 px-5 py-4')}>
                  <AvisoDegradacion activo={consultaCola.error != null} queReintenta="de los pendientes del equipo" onReintentar={() => void consultaCola.refetch()}>
                    No se pudo cargar la cola. Los pendientes todavía no están confirmados.
                  </AvisoDegradacion>
                </div>
                {consultaCola.error ? null : !pagina ? (
                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
                ) : !paginaVigente ? (
                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
                    {pagina.modo !== 'activo'
                      ? 'Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.'
                      : 'Actualizando los pendientes con las reglas vigentes…'}
                  </p>
                ) : paginaVigente.items.length === 0 ? (
                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
                    {nombreAnalista ? `${corto(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
                  </p>
                ) : (
                  // oxlint-disable-next-line jsx-a11y/no-redundant-roles
                  <ul role="list" aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
                    {paginaVigente.items.map((item) => {
                      const leadStore = leadPorId.get(item.lead_id)
                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
                      const analistaFila = item.lead.analista_nombre ? corto(item.lead.analista_nombre) : 'Sin analista'
                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
                      const urgente = item.severidad === 'critica'
                      return (
                        <li
                          key={item.lead_id}
                          data-sev={item.severidad}
                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
                          style={{ borderLeftColor: colorTira }}
                        >
                          <button
                            type="button"
                            // aria-disabled y NO disabled: un botón enfocado que se deshabilita
                            // suelta el foco a <body> y la ficha lo devolvía ahí al cerrarse.
                            // La guarda de abrirFicha ya evita el doble envío.
                            aria-disabled={abriendo !== null || undefined}
                            onClick={() => void abrirFicha(item.lead_id)}
                            // El nombre dicta TODO lo visible (dueño, urgencia, estado,
                            // tiempo, monto): un lector de pantalla no puede perder lo que se ve.
                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}${urgente ? ', urgente' : ''}: ${estado}${monto ? `, ${monto}` : ''}`}
                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 aria-disabled:cursor-wait"
                          >
                            {analistaId == null && (
                              <span className="hidden w-[118px] shrink-0 items-center gap-2 sm:flex">
                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
                              </span>
                            )}
                            <span className="min-w-0 flex-1 leading-tight">
                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
                              <span className="flex min-w-0 items-center gap-1 text-xs text-muted-foreground-strong">
                                {urgente && <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />}
                                <span className="truncate">
                                  {analistaId == null && <span className="sm:hidden">{analistaFila} · </span>}
                                  {estado}
                                </span>
                              </span>
                            </span>
                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                          </button>
                          {leadStore && (
                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil), alto Y ancho.
                            <div className="[&_a]:min-h-9 [&_a]:min-w-9 [&_button]:min-h-9 [&_button]:min-w-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_a]:min-w-10 pointer-coarse:[&_button]:min-h-10 pointer-coarse:[&_button]:min-w-10">
                              <AccionesContacto lead={leadStore} compacto />
                            </div>
                          )}
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
                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
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
              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-1 text-xs font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
                Mi equipo hoy <span aria-hidden>→</span>
              </a>
            )}
          />
          {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
                // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
                ? 'Sin alertas en el equipo'
                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
            </p>
          )}
          <div className={cn(datos.errorAgenda && 'mx-5 mb-2')}>
            <AvisoDegradacion activo={datos.errorAgenda != null} queReintenta="de la agenda del equipo" onReintentar={datos.recargarAgenda}>
              La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.
            </AvisoDegradacion>
          </div>
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
            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
            <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
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
                // PEN y USD jamás se suman sin decirlo: el nombre lleva el desglose.
                const desglose = r.capitalUSD > 0
                  ? cap.tc != null
                    ? ` (${moneyK(r.capitalPEN, 'PEN')} más ${moneyK(r.capitalUSD, 'USD')})`
                    : `, más ${moneyK(r.capitalUSD, 'USD')} aparte sin tipo de cambio`
                  : ''
                const nivelTexto = lectura.nivel != null ? `${TEXTO_NIVEL[lectura.nivel]}. ` : ''
                const conversion = r.conversion == null
                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
                  : `${textoConversionOperativa(r.conversion)} conversión`
                return (
                  <li key={id} className="border-b border-border/60 last:border-b-0">
                    <button
                      type="button"
                      aria-expanded={abierto}
                      aria-controls={idDetalle}
                      aria-label={`${r.m.nombre_completo}: ${nivelTexto}${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}${desglose}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
                      onClick={() => elegirAnalista(id)}
                      className={cn(
                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
                        abierto && 'bg-accent/[0.08]',
                      )}
                    >
                      <MarcaNivel nivel={lectura.nivel} />
                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
                      <span className="min-w-0 flex-1 leading-tight">
                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
                      </span>
                      <span className="shrink-0 text-right leading-tight">
                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto tono="fuerte" />
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

      {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
      <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
        <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
        <ul role="list" aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
          <li>
            <a href={hashDe('pipeline')} className={CLASE_CIFRA}>
              <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
              {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
            </a>
          </li>
          <li>
            <a href={hashDe('cartera')} className={CLASE_CIFRA}>
              <strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos
            </a>
          </li>
          <li>
            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
              <strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta
            </button>
          </li>
          <li>
            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
              <strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes
            </button>
          </li>
          <li aria-hidden className="h-[18px] w-px bg-border" />
          <li>
            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
              <strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días
            </button>
          </li>
          <li>
            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
              <strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas
            </button>
          </li>
          <li>
            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
              {agendaResumen && agendaResumen.noAsistio >= 2 && (
                <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
              )}
              <strong
                className="font-extrabold"
                style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
              >
                {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
              </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
            </button>
          </li>
        </ul>
        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={abrirDetalle}>
          Detalle
        </Button>
      </section>

      <Dialog
        open={detalleAbierto}
        onClose={() => setDetalleAbierto(false)}
        focoInicial={tituloDetalle}
        focoAlCerrar={focoALaCola ? focoTrasDetalle : undefined}
        className="w-[1180px] max-h-[88vh] max-w-[94vw]"
      >
        <DialogHeader>
          {/* El foco entra por el título, no en mitad de la rejilla de indicadores. */}
          <DialogTitle><span ref={tituloDetalle} tabIndex={-1} className="outline-none">Detalle del equipo</span></DialogTitle>
          <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
            <a href={hashDe('pipeline')} className={CLASE_KPI_ENLACE}>
            <KpiCard
              label="Pronóstico de capital abierto"
              value={pronostico ? pronostico.valor : '—'}
              icon={Wallet}
              color={SEMAFORO.neutro}
              sub={
                pronostico?.otra
                  ? `En soles · +${pronostico.otra} aparte`
                  : pronostico?.soloDolares
                    ? 'En dólares · abiertos con analista'
                    : datos.resumen && datos.resumen.capital.asignado.pen === 0 && datos.resumen.totales.asignados > 0
                      ? 'Sin montos estimados — complétalos en cada ficha'
                      : 'En soles · abiertos con analista'
              }
            />
            </a>
            <a href={hashDe('cartera')} className={CLASE_KPI_ENLACE}>
            <KpiCard
              label="Leads activos del equipo"
              value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
              icon={Users}
              color={SEMAFORO.neutro}
              sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
              delay={60}
            />
            </a>
            {/* Abre la cola en su pestaña: cierra el detalle y deja el foco en ella. */}
            <button
              type="button"
              className={CLASE_KPI_ENLACE}
              onClick={() => {
                focoTrasDetalle.current = document.getElementById(`${idPanelCola}-tab-primera_atencion`)
                setFocoALaCola(true)
                setDetalleAbierto(false)
                verPrimeraGestion()
              }}
            >
              <KpiCard
                label="Primeras gestiones vencidas"
                value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
                icon={AlertTriangle}
                color={SEMAFORO.neutro}
                sub={primeraGestionPendiente == null
                  ? 'Sin dato por ahora'
                  : primeraGestionPendiente > 0 ? 'Ver cuáles son →' : 'Ninguna vencida'}
                delay={120}
              />
            </button>
            <a
              href={hashDe('derivaciones')}
              aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
              className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            >
              <KpiCard
                label="Por repartir"
                value={datos.totalPorRepartir == null ? '—' : String(datos.totalPorRepartir)}
                icon={Inbox}
                color={SEMAFORO.neutro}
                sub={datos.detalleReparto}
                delay={180}
              />
            </a>
          </div>

          <div className="grid gap-4 lg:grid-cols-5">
            <Card className="lg:col-span-2">
              <SectionHead
                icon={Target}
                title="Cumplimiento del mes"
                right={tc ? <span className="text-xs text-muted-foreground-strong">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined}
              />
              <CardContent className="space-y-4 pb-5 pt-0">
                {datos.filasMeta.map((f) => (
                  <div key={f.label}>
                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
                      <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
                      <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
                    </div>
                    {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
                    {f.sinDato
                      ? <p className="text-[11px] text-muted-foreground-strong">{f.sinDato}</p>
                      : <Progress value={f.pct} color={colorMeta(f.pct)} />}
                  </div>
                ))}
                <p className="text-[11px] text-muted-foreground-strong">
                  El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
                </p>
                <AvisoDegradacion activo={datos.hayErrorMensual} queReintenta="de la meta y el cumplimiento del mes" onReintentar={datos.reintentarMensual}>
                  Parte del cumplimiento del mes no se pudo cargar: se muestra «—» donde falta el dato.
                </AvisoDegradacion>
              </CardContent>
            </Card>
            <div className="min-w-0 lg:col-span-3">
              <AgendaEquipoPanel
                datos={datos.datosAgenda}
                cargando={datos.cargandoAgenda}
                error={datos.errorAgenda}
                modoDemo={yo?.demo === true}
                onReintentar={datos.recargarAgenda}
                equipo={datos.equipo}
              />
            </div>
          </div>

          {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC). */}
          <DesglosePorEmpresa demo={yo?.demo === true} porVendedor={datos.cumplimientoMensual?.porVendedor ?? null} />
          {/* Rentabilidad R3: las solicitudes de tasa propias en curso (solo si hay). */}
          <TasasAutorizadasAnalistaPanel />
          <p className="text-[11px] text-muted-foreground-strong">
            Ves solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
          </p>
        </DialogBody>
        <DialogFooter>
          <Button variant="outline" size="sm" className="min-h-9 pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
        </DialogFooter>
      </Dialog>
    </div>
  )
}

/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
  cosa: CosaDeHoy
  onVerPrimeraGestion: () => void
  etiquetaReparto: string
}): JSX.Element {
  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
  if (cosa.id === 'primera_gestion') {
    return (
      <button type="button" className={clase} aria-label={`Ver en la cola: ${cosa.texto}`} onClick={onVerPrimeraGestion}>
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
      <div className="flex flex-wrap items-center gap-2 py-2 pl-4 pr-3">
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
            <span className="line-clamp-2 break-words text-[15px] font-bold">{resto}</span>
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
function EstaSemana({ cosas, onVerPrimeraGestion, etiquetaReparto }: {
  cosas: CosaDeHoy[]
  onVerPrimeraGestion: () => void
  etiquetaReparto: string
}): JSX.Element {
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
    // Tabular fuera del popover lo cierra: si no, quedaría encima de las
    // tarjetas que reciben el foco a continuación (WCAG 2.4.11).
    const nodo = contenedor.current
    const salida = (e: FocusEvent) => {
      if (e.relatedTarget instanceof Node && !nodo?.contains(e.relatedTarget)) setAbierto(false)
    }
    document.addEventListener('pointerdown', fuera)
    document.addEventListener('keydown', escape)
    nodo?.addEventListener('focusout', salida)
    return () => {
      document.removeEventListener('pointerdown', fuera)
      document.removeEventListener('keydown', escape)
      nodo?.removeEventListener('focusout', salida)
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
        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
      >
        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
        Esta semana · {cosas.length}
        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
      </button>
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ul role="list"
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
            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={etiquetaReparto} />
          </li>
        ))}
      </ul>
    </div>
  )
}
