// Repartir leads (C1/C1-bis) — la única pantalla del coordinador: mueve los
// leads recién nacidos de la cola global a la BANDEJA de un supervisor, o los
// DESCARTA con motivo (segunda malla del filtro de crédito).
//
// Orden comercial (regla de Miguel: lo que genera ingreso, primero): capital en
// juego arriba, la cola como protagonista y en cada fila el monto del lead.
// PEN y USD JAMÁS se suman: se muestran como dos cifras separadas.
//
// Rediseño 2026-07-24 (feedback de Miguel con la cola real de ~55): el COMENTARIO
// del cliente es el dato de decisión y va destacado con fecha y hora de ingreso;
// orden por defecto "más recientes primero" (el último lead entra ARRIBA), con
// el inverso a un clic; búsqueda + filtro por origen + toggle "posible crédito";
// y paginación local de a 20 (nada de scroll infinito). Todo es presentación:
// la RPC sigue entregando FIFO y el contrato con el servidor no cambia.
//
// Estado local con React (sin XState: eso vive solo en auth). La verdad la tiene
// el servidor — cada reparto/descarte pasa por su RPC atómica.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Split, Users, Wallet, Inbox, AlertTriangle, Search, Ban, RotateCcw, CalendarDays } from 'lucide-react'
import { toast } from 'sonner'
import {
  CrmApiError,
  agendaRepartoDiaria,
  descartarLead,
  deshacerDescarte,
  leadsDescartados,
  leadsPorRepartir,
  repartirLead,
  supervisoresParaReparto,
} from '@/data/crm-api'
import {
  MOTIVOS_DESCARTE,
  MOTIVOS_DESCARTE_LECTURA,
  origenLabel,
  type ColaLead,
  type DiaAgendaReparto,
  type LeadDescartado,
  type MotivoDescarte,
  type OrigenLectura,
  type SupervisorReparto,
} from '@/lib/tipos'
import { capitalLead, fechaHora, moneyK } from '@/lib/format'
import {
  FILTROS_INICIALES,
  contarMarcados,
  filtrarYOrdenarCola,
  origenesDeCola,
  type FiltrosCola,
} from '@/lib/cola-reparto'
import { useResumenRepartoOperativo } from '@/data/use-resumen-reparto-operativo'
import { crmQueryKeys } from '@/data/crm-queries'
import { queryClient } from '@/lib/query-client'
import { useAhora } from '@/lib/ahora'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { HistorialDerivaciones } from '@/components/app/historial-derivaciones'
import { PanelDistribucionReparto } from '@/components/app/panel-distribucion-reparto'
import { AgendaRepartoDiaria } from '@/components/app/agenda-reparto-diaria'
import { ConversionCoordinacion } from '@/components/app/conversion-coordinacion'
import { Paginacion } from '@/components/common/paginacion'
import { paginar } from '@/lib/paginacion'
import { hoyLimaIso } from '@/lib/distribucion-lecturas'
import { useAuth } from '@/lib/auth-context'

/** Cuántas filas se muestran por página local. Nunca se acumulan al navegar. */
const PAGINA = 20

/**
 * Los tiles los sirve el servidor (F1b tanda 3), así que tras cada mutación de
 * la cola hay que pedirle la foto nueva. Esta pantalla NO pasa por el store: el
 * puente transitorio de `resincronizarReal` nunca corre para el coordinador
 * (es off-roster y sus mutaciones van directas a la RPC), de modo que la
 * invalidación se hace a mano. Se invalida —y no solo se refetchea— porque el
 * remonte de la pestaña Cola por `colaKey` volvería a servir la foto anterior
 * mientras siga fresca (staleTime 30 s). El singleton de query-client, no
 * useQueryClient: la pantalla se monta en tests sin provider.
 */
function refrescarResumenReparto(): void {
  void queryClient.invalidateQueries({ queryKey: crmQueryKeys.resumenReparto() })
}

/** Etiqueta humana de cada motivo de descarte LEÍDO (incluye los de solo lectura, como «Base cargada»). */
const MOTIVO_LABEL: Record<string, string> =
  Object.fromEntries(MOTIVOS_DESCARTE_LECTURA.map((m) => [m.k, m.label]))

/** Badge "Posible crédito" — mismo en la cola y en descartados (a11y idéntica). */
function BadgeCredito() {
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-full border border-warning/40 bg-warning/10 px-1.5 py-px text-[10px] font-bold uppercase tracking-wide text-warning-text"
      title="El sistema detectó que el comentario menciona préstamo/financiamiento. Es una marca: la decisión de descartar es tuya."
    >
      <AlertTriangle className="size-3" aria-hidden />
      Posible crédito
      <span className="sr-only">
        . Marca automática: el comentario menciona préstamo o financiamiento; la decisión de descartar es tuya.
      </span>
    </span>
  )
}

/** Días transcurridos desde que el lead entró a la cola (para la urgencia). */
function diasEnCola(desde: string, ahora: number): number {
  const t = Date.parse(desde)
  if (!Number.isFinite(t)) return 0
  return Math.max(0, Math.floor((ahora - t) / 86_400_000))
}

function esperaTxt(dias: number): string {
  if (dias <= 0) return 'hoy'
  if (dias === 1) return 'hace 1 día'
  return `hace ${dias} días`
}

interface EstadoReparto {
  cola: ColaLead[]
  supervisores: SupervisorReparto[]
  agendaHoy: DiaAgendaReparto | null
  repartoLibre: boolean
  cargando: boolean
  error: string | null
}

function origenUsaTurno(origen: OrigenLectura): origen is 'landing' | 'formulario' {
  return origen === 'landing' || origen === 'formulario'
}

/** Mantiene visible el contador del turno mientras Rosa sigue en la cola. */
function sumarEntregaLocal(
  agendaHoy: DiaAgendaReparto | null,
  origen: OrigenLectura,
  supervisorId: string,
): DiaAgendaReparto | null {
  if (!agendaHoy || !origenUsaTurno(origen)) return agendaHoy
  return {
    ...agendaHoy,
    asignaciones: agendaHoy.asignaciones.map((asignacion) => asignacion.origen === origen
      ? {
          ...asignacion,
          derivados: asignacion.derivados + 1,
          fuera_turno: (asignacion.fuera_turno ?? 0)
            + (asignacion.supervisor_id === supervisorId ? 0 : 1),
        }
      : asignacion),
  }
}

function useReparto() {
  const [estado, setEstado] = useState<EstadoReparto>({
    cola: [], supervisores: [], agendaHoy: null, repartoLibre: false, cargando: true, error: null,
  })
  const [enviandoIds, setEnviandoIds] = useState<ReadonlySet<string>>(() => new Set())
  const enviandoRef = useRef<Set<string>>(new Set())
  const abortRef = useRef<AbortController | null>(null)
  const permisoAbortRef = useRef<AbortController | null>(null)

  const iniciarEnvio = useCallback((leadId: string): boolean => {
    if (enviandoRef.current.has(leadId)) return false
    permisoAbortRef.current?.abort()
    enviandoRef.current = new Set(enviandoRef.current).add(leadId)
    setEnviandoIds(enviandoRef.current)
    return true
  }, [])

  const terminarEnvio = useCallback((leadId: string) => {
    const siguientes = new Set(enviandoRef.current)
    siguientes.delete(leadId)
    enviandoRef.current = siguientes
    setEnviandoIds(siguientes)
  }, [])

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    permisoAbortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado((e) => ({ ...e, cargando: true, error: null }))
    try {
      const hoy = hoyLimaIso()
      const [cola, supervisores, agenda] = await Promise.all([
        leadsPorRepartir(ctrl.signal),
        supervisoresParaReparto(ctrl.signal),
        agendaRepartoDiaria({ desde: hoy, dias: 1 }, ctrl.signal),
      ])
      if (ctrl.signal.aborted) return
      setEstado({
        cola,
        supervisores,
        agendaHoy: agenda.dias.find((dia) => dia.fecha === hoy) ?? null,
        repartoLibre: agenda.reparto_libre === true,
        cargando: false,
        error: null,
      })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((e) => ({
        ...e,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la cola de leads.',
      }))
    } finally {
      if (abortRef.current === ctrl) abortRef.current = null
    }
  }, [])

  // Volver a la ventana solo refresca el permiso, sin desmontar filas ni
  // sobrescribir selecciones, entregas locales o escrituras en curso.
  const actualizarPermiso = useCallback(async () => {
    if (enviandoRef.current.size || abortRef.current || permisoAbortRef.current) return
    const ctrl = new AbortController()
    permisoAbortRef.current = ctrl
    try {
      const agenda = await agendaRepartoDiaria({ desde: hoyLimaIso(), dias: 1 }, ctrl.signal)
      if (!ctrl.signal.aborted) {
        setEstado((e) => ({ ...e, repartoLibre: agenda.reparto_libre === true }))
      }
    } catch {
      // Conserva la pantalla ante un fallo transitorio. Cada reparto vuelve
      // a comprobar el permiso en el servidor y relee si la regla cambió.
    } finally {
      if (permisoAbortRef.current === ctrl) permisoAbortRef.current = null
    }
  }, [])

  useEffect(() => {
    void cargar()
    let pendiente: ReturnType<typeof setTimeout> | undefined
    const alVolver = () => {
      clearTimeout(pendiente)
      pendiente = setTimeout(() => { void actualizarPermiso() }, 250)
    }
    window.addEventListener('focus', alVolver)
    return () => {
      window.removeEventListener('focus', alVolver)
      clearTimeout(pendiente)
      abortRef.current?.abort()
      permisoAbortRef.current?.abort()
    }
  }, [cargar, actualizarPermiso])

  /** Reparte un lead. El servidor manda: si rechaza, la fila NO se mueve. */
  const repartir = useCallback(async (lead: ColaLead, supervisorId: string) => {
    if (!iniciarEnvio(lead.id)) return
    const destino = supervisorId
    try {
      await repartirLead(lead.id, destino)
      // Éxito: la fila sale de la cola y la bandeja destino sube en 1 (el
      // servidor ya lo sabe; esto evita un refetch completo por cada reparto).
      setEstado((e) => ({
        ...e,
        cola: e.cola.filter((l) => l.id !== lead.id),
        supervisores: e.supervisores.map((s) =>
          s.perfil_id === destino ? { ...s, bandeja_pendiente: s.bandeja_pendiente + 1 } : s,
        ),
        agendaHoy: sumarEntregaLocal(e.agendaHoy, lead.origen, destino),
      }))
      // La lista se corrige sola (arriba), pero los tiles vienen del servidor.
      refrescarResumenReparto()
      const nombre = estado.supervisores.find((s) => s.perfil_id === destino)?.nombre ?? 'la bandeja'
      toast.success(`${lead.nombre_completo} pasó a ${nombre}`)
    } catch (error) {
      const mensaje = error instanceof Error ? error.message : 'No se pudo repartir el lead.'
      toast.error(mensaje)
      // Fuera de cola, veto legal o carrera: la cola local quedó desfasada
      // respecto del servidor → se relee en vez de adivinar.
      if (error instanceof CrmApiError
        && ['FUERA_DE_COLA', 'NO_INSISTA', 'REINTENTAR', 'REGLA_SERVIDOR'].includes(error.code)) {
        void cargar()
        refrescarResumenReparto()
      }
    } finally {
      terminarEnvio(lead.id)
    }
  }, [cargar, estado.supervisores, iniciarEnvio, terminarEnvio])

  /** C1-bis: cierra el lead con motivo. Devuelve si el descarte ENTRÓ (el
   *  llamador decide a dónde va el foco). El deshacer vive en el toast — la
   *  RPC de servidor da 24 h, pero el gesto natural es el arrepentimiento al
   *  tiro; 15 s + closeButton del Toaster dan margen a teclado y lector. */
  const descartar = useCallback(async (lead: ColaLead, motivo: MotivoDescarte): Promise<boolean> => {
    if (!iniciarEnvio(lead.id)) return false
    try {
      await descartarLead(lead.id, motivo)
      setEstado((e) => ({ ...e, cola: e.cola.filter((l) => l.id !== lead.id) }))
      refrescarResumenReparto()
      const label = MOTIVOS_DESCARTE.find((m) => m.k === motivo)?.label ?? motivo
      toast.success(`${lead.nombre_completo} descartado · ${label}`, {
        duration: 15000,
        action: {
          label: 'Deshacer',
          onClick: () => {
            void (async () => {
              try {
                await deshacerDescarte(lead.id)
                toast.success(`${lead.nombre_completo} volvió a la cola`)
              } catch (error) {
                toast.error(error instanceof Error ? error.message : 'No se pudo deshacer.')
              } finally {
                // Con o sin éxito, la verdad la tiene el servidor.
                void cargar()
                refrescarResumenReparto()
              }
            })()
          },
        },
      })
      return true
    } catch (error) {
      const mensaje = error instanceof Error ? error.message : 'No se pudo descartar el lead.'
      toast.error(mensaje)
      if (error instanceof CrmApiError
        && ['FUERA_DE_COLA', 'REINTENTAR'].includes(error.code)) {
        void cargar()
        refrescarResumenReparto()
      }
      return false
    } finally {
      terminarEnvio(lead.id)
    }
  }, [cargar, iniciarEnvio, terminarEnvio])

  return { ...estado, enviandoIds, recargar: cargar, repartir, descartar }
}

/** Pestaña "Cola": repartir o descartar los leads nuevos sin dueño. */
function PanelCola() {
  const { cola, supervisores, agendaHoy, repartoLibre, cargando, error, enviandoIds, recargar, repartir, descartar } = useReparto()
  const { yo } = useAuth()
  const esAdministrador = yo?.rol_portal === 'superadmin'
  const puedeElegirDestino = esAdministrador || repartoLibre
  // Los TILES los cuenta el servidor sobre la cola GLOBAL (F1b tanda 3); las
  // FILAS cargadas siguen gobernando lo que es de la lista: el panel vacío, el
  // «N en espera», el «X de Y», el «Mostrando…», el selector de orígenes y el
  // chip «Posible crédito (N)» —que rotula un filtro LOCAL: un control debe
  // contar exactamente lo que va a filtrar—. Hoy ambos universos coinciden
  // (mismo predicado, la RPC de la cola no tiene tope); cuando F2 la pagine
  // divergirán, y cada cifra ya sabe de quién depende.
  const resumenOp = useResumenRepartoOperativo()
  const resumen = resumenOp.resumen
  const [destino, setDestino] = useState<Record<string, string>>({})
  // C1-bis: filas en "modo descarte" y el motivo elegido en cada una.
  const [descartando, setDescartando] = useState<Record<string, boolean>>({})
  const [motivo, setMotivo] = useState<Record<string, MotivoDescarte | ''>>({})
  // Comentarios expandidos ("Ver todo") por lead.
  const [expandidos, setExpandidos] = useState<Record<string, boolean>>({})
  // Filtros/orden de PRESENTACIÓN (la RPC no cambia) + paginación local.
  const [filtros, setFiltros] = useState<FiltrosCola>(FILTROS_INICIALES)
  const [pagina, setPagina] = useState(0)
  // El conmutador de modo DESTRUYE el control enfocado: sin foco programático,
  // el teclado cae a <body> y hay que retabular toda la página (revisor a11y).
  // NO autoFocus: fuera de un modal es hallazgo (excepción 3 de .oxlintrc.json).
  const refMotivo = useRef(new Map<string, HTMLSelectElement>())
  const refDescartarGhost = useRef(new Map<string, HTMLButtonElement>())
  const refCola = useRef<HTMLDivElement>(null)
  // Reloj VIVO: el tile de espera lo recalcula el servidor cada minuto (el hook
  // reconsulta), así que las filas tienen que envejecer al mismo ritmo o el
  // tile diría «hace 2 días» mientras la fila sigue clavada en «hace 1 día».
  const ahora = useAhora()

  /** Cambia un filtro y vuelve a la primera página. */
  const setFiltro = useCallback((patch: Partial<FiltrosCola>) => {
    setFiltros((f) => ({ ...f, ...patch }))
    setPagina(0)
  }, [])

  const marcados = useMemo(() => contarMarcados(cola), [cola])
  const origenes = useMemo(() => origenesDeCola(cola), [cola])
  const colaFiltrada = useMemo(() => filtrarYOrdenarCola(cola, filtros), [cola, filtros])
  const paginaCola = paginar(colaFiltrada, pagina, PAGINA)
  const colaVisible = paginaCola.visibles
  const hayFiltrosActivos = filtros.busqueda.trim() !== ''
    || filtros.soloMarcados || filtros.origen !== ''

  // Sin resumen (cargando o RPC caído) los cuatro van a «—»: moneyK(null)
  // pintaría «S/ 0», que afirma que NO hay capital cuando lo que pasa es que no
  // se sabe. Prohibido el atajo de volver a contar `cola` si el RPC cae: sería
  // reintroducir justo lo que esta tanda quita.
  // El «—» es MUDO para un lector de pantalla (no se pronuncia con la
  // puntuación por defecto), así que cada tile degradado dice en voz alta si
  // está cargando o si no se sabe — nunca se deja inferir un cero.
  const cargandoResumen = resumenOp.cargando
  const stats = useMemo<StatChipData[]>(() => {
    // Locuciones DENTRO del memo: como objetos nuevos en cada render anularían
    // la memoización de la que cuelgan (aviso de exhaustive-deps).
    type Locucion = Partial<Pick<StatChipData, 'valorAccesible'>>
    const mudo: Locucion = resumen ? {} : { valorAccesible: cargandoResumen ? 'cargando' : 'sin dato' }
    const mudoEspera: Locucion = resumen && resumen.cola.total === 0
      ? { valorAccesible: 'no aplica: la cola está vacía' }
      : mudo
    return [
      {
        icon: Inbox,
        label: 'Por repartir',
        value: resumen ? String(resumen.cola.total) : '—',
        tone: resumen && resumen.cola.total > 0 ? 'accent' : 'default',
        ...mudo,
      },
      {
        icon: Wallet,
        label: 'Capital en juego (PEN)',
        value: resumen ? moneyK(resumen.cola.capital.pen, 'PEN') : '—',
        ...mudo,
      },
      {
        icon: Wallet,
        label: 'Capital en juego (USD)',
        value: resumen ? moneyK(resumen.cola.capital.usd, 'USD') : '—',
        ...mudo,
      },
      {
        icon: Users,
        label: 'Espera más larga',
        value: !resumen || resumen.cola.total === 0 ? '—' : esperaTxt(resumen.cola.espera_max_dias),
        tone: resumen && resumen.cola.espera_max_dias >= 1 ? 'warn' : 'default',
        ...mudoEspera,
      },
    ]
  }, [cargandoResumen, resumen])

  return (
    <div className="space-y-5">
      <StatStrip stats={stats} />

      {agendaHoy ? (
        <Card className="overflow-hidden border-primary/20">
          <SectionHead
            icon={CalendarDays}
            title="Turno de hoy"
            right={(
              <span className="text-[11px] font-semibold text-muted-foreground">
                {puedeElegirDestino ? 'Turno sugerido · reparto libre habilitado' : 'Destino fijado por la agenda'}
              </span>
            )}
          />
          <div className="grid border-t border-border sm:grid-cols-2 sm:divide-x sm:divide-y-0">
            {(['landing', 'formulario'] as const).map((origen) => {
              const asignacion = agendaHoy.asignaciones.find((fila) => fila.origen === origen)
              const total = asignacion?.derivados ?? 0
              return (
                <div key={origen} className="border-b border-border px-5 py-3 last:border-b-0 sm:border-b-0">
                  <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-muted-foreground">
                    {origenLabel(origen)}
                  </p>
                  <p className="mt-0.5 text-sm font-bold text-foreground">
                    {asignacion?.supervisor_nombre ?? 'Turno sin guardar'}
                  </p>
                  <p className="mt-0.5 text-[11px] text-muted-foreground">
                    {total} {total === 1 ? 'entregado' : 'entregados'} hoy por Coordinación
                  </p>
                </div>
              )
            })}
          </div>
        </Card>
      ) : null}

      {/* Los indicadores dicen «—» y la cola sigue siendo repartible, porque
          tiene su propia fuente (leads_por_repartir). En demo el hook ya
          devuelve error null, así que no hace falta guardia extra. */}
      <AvisoDegradacion
        activo={Boolean(resumenOp.error)}
        queReintenta="de los indicadores de la cola"
        onReintentar={() => { void resumenOp.recargar() }}
      >
        No se pudieron cargar los indicadores de la cola. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      <Card className="overflow-hidden">
        <SectionHead
          icon={Split}
          title="Cola de leads nuevos"
          right={
            <span className="text-[11px] font-semibold text-muted-foreground">
              {cola.length > 0
                ? `${hayFiltrosActivos ? `${colaFiltrada.length} de ${cola.length}` : `${cola.length} en espera`} · ${
                  filtros.orden === 'recientes' ? 'más recientes primero' : 'más antiguos primero'}`
                : ''}
            </span>
          }
        />

        {cargando ? (
          <PanelCargando filas={4} />
        ) : error ? (
          <PanelError mensaje={error} onReintentar={() => void recargar()} reintentando={cargando} />
        ) : cola.length === 0 ? (
          <PanelVacio
            icono={Inbox}
            titulo="No hay leads por repartir"
            detalle="Cuando entren leads nuevos por la hoja o la landing aparecerán aquí para asignarlos a un supervisor."
          />
        ) : supervisores.length === 0 ? (
          <PanelVacio
            icono={Users}
            titulo="No hay supervisores activos"
            detalle="Sin una bandeja de destino no se puede repartir. Avisa a gerencia para activar al menos un supervisor."
          />
        ) : (
          <>
            {/* Herramientas de la cola: buscar, ordenar, filtrar. Presentación
                pura — el servidor sigue mandando la cola completa en FIFO. */}
            <div className="flex flex-col gap-2 px-5 pb-3 sm:flex-row sm:items-center">
              <div className="relative flex-1 sm:max-w-[280px]">
                <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <Input
                  value={filtros.busqueda}
                  onChange={(e) => setFiltro({ busqueda: e.target.value })}
                  placeholder="Buscar nombre, distrito o comentario…"
                  aria-label="Buscar en la cola por nombre, distrito o comentario"
                  className="h-8 pl-8 text-xs"
                />
              </div>
              <div className="sm:w-[185px]">
                <Select
                  value={filtros.orden}
                  onChange={(e) => setFiltro({ orden: e.target.value === 'antiguos' ? 'antiguos' : 'recientes' })}
                  aria-label="Ordenar la cola por fecha de ingreso"
                >
                  <option value="recientes">Más recientes primero</option>
                  <option value="antiguos">Más antiguos primero</option>
                </Select>
              </div>
              <div className="sm:w-[170px]">
                <Select
                  value={filtros.origen}
                  onChange={(e) => setFiltro({ origen: e.target.value as OrigenLectura | '' })}
                  aria-label="Filtrar por origen del lead"
                >
                  <option value="">Todos los orígenes</option>
                  {origenes.map((o) => (
                    <option key={o} value={o}>{origenLabel(o)}</option>
                  ))}
                </Select>
              </div>
              {marcados > 0 ? (
                <button
                  type="button"
                  aria-pressed={filtros.soloMarcados}
                  onClick={() => setFiltro({ soloMarcados: !filtros.soloMarcados })}
                  className={`inline-flex h-8 shrink-0 items-center gap-1 rounded-md border px-2.5 text-xs font-semibold transition-colors ${
                    filtros.soloMarcados
                      ? 'border-warning bg-warning/15 text-warning-text'
                      : 'border-border bg-card text-muted-foreground hover:bg-muted'
                  }`}
                >
                  <AlertTriangle className="size-3" aria-hidden />
                  Posible crédito ({marcados})
                </button>
              ) : null}
            </div>

            {colaFiltrada.length === 0 ? (
              <PanelVacio
                icono={Search}
                titulo="Ningún lead coincide con la búsqueda o los filtros"
                detalle="Prueba con otro texto o restablece los filtros para ver la cola completa."
              >
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => { setFiltros(FILTROS_INICIALES); setPagina(0) }}
                >
                  Limpiar filtros
                </Button>
              </PanelVacio>
            ) : (
              <div ref={refCola} tabIndex={-1} className="space-y-2 px-5 pb-5 outline-none">
                {/* tabIndex={-1}: destino PROGRAMÁTICO del foco cuando la fila
                    enfocada desaparece (descarte exitoso); no es alcanzable con
                    Tab, por eso el outline-none aquí es legítimo. */}
                {colaVisible.map((lead) => {
                  const dias = diasEnCola(lead.creado_en, ahora)
                  const usaTurno = origenUsaTurno(lead.origen)
                  const turnoObligatorio = usaTurno && !puedeElegirDestino
                  const asignacionTurno = usaTurno
                    ? agendaHoy?.asignaciones.find((fila) => fila.origen === lead.origen)
                    : undefined
                  const elegido = turnoObligatorio
                    ? asignacionTurno?.supervisor_id ?? ''
                    : destino[lead.id] ?? asignacionTurno?.supervisor_id ?? ''
                  const enviando = enviandoIds.has(lead.id)
                  const marcado = lead.clasificacion_auto === 'posible_credito'
                  const enDescarte = descartando[lead.id] === true
                  const expandido = expandidos[lead.id] === true
                  const comentarioLargo = (lead.comentario ?? '').length > 160
                  // La marca del código PROPONE el motivo; el humano confirma.
                  const motivoElegido = motivo[lead.id] ?? (marcado ? 'pide_credito' : '')
                  return (
                    <div
                      key={lead.id}
                      data-lead-id={lead.id}
                      className="flex flex-col gap-2.5 rounded-xl border border-border p-3 sm:flex-row sm:items-start"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="flex items-center gap-1.5 text-sm font-semibold">
                          <span className="truncate">{lead.nombre_completo}</span>
                          {marcado ? <BadgeCredito /> : null}
                        </p>
                        <p className="truncate text-[11px] text-muted-foreground">
                          {origenLabel(lead.origen)}
                          {' · '}
                          <span className="font-semibold text-foreground">
                            {capitalLead(lead.monto_estimado, lead.moneda, true)}
                          </span>
                          {lead.distrito ? ` · ${lead.distrito}` : ''}
                          {' · entró '}
                          <span className="font-semibold text-foreground">{fechaHora(lead.creado_en)}</span>
                          {dias >= 1 ? (
                            <span className="font-bold text-warning-text">{` · ${esperaTxt(dias)}`}</span>
                          ) : null}
                        </p>
                        {lead.comentario ? (
                          // Lo que escribió el cliente (ya redactado por el servidor):
                          // EL dato con el que Rosa decide repartir o descartar.
                          <div className={`mt-1.5 rounded-md border-l-2 py-1.5 pl-2.5 pr-2 ${
                            marcado ? 'border-warning bg-warning/5' : 'border-accent/40 bg-muted/50'}`}
                          >
                            <p className={`text-[13px] leading-snug text-foreground ${expandido ? '' : 'line-clamp-3'}`}>
                              “{lead.comentario}”
                            </p>
                            {comentarioLargo ? (
                              <button
                                type="button"
                                aria-expanded={expandido}
                                className="mt-0.5 text-[11px] font-semibold text-accent hover:underline"
                                onClick={() => setExpandidos((e2) => ({ ...e2, [lead.id]: !expandido }))}
                              >
                                {expandido ? 'Ver menos' : 'Ver todo el comentario'}
                              </button>
                            ) : null}
                          </div>
                        ) : null}
                      </div>
                      {enDescarte ? (
                        <div className="flex items-center gap-2 sm:w-[380px] sm:shrink-0">
                          <Select
                            ref={(el) => {
                              if (el) refMotivo.current.set(lead.id, el)
                              else refMotivo.current.delete(lead.id)
                            }}
                            value={motivoElegido}
                            disabled={enviando}
                            onChange={(e) => setMotivo((m) => ({ ...m, [lead.id]: e.target.value as MotivoDescarte | '' }))}
                            aria-label={`Motivo para descartar a ${lead.nombre_completo}`}
                          >
                            <option value="">Motivo…</option>
                            {MOTIVOS_DESCARTE.map((m) => (
                              <option key={m.k} value={m.k}>{m.label}</option>
                            ))}
                          </Select>
                          <Button
                            size="sm"
                            variant="destructive"
                            disabled={!motivoElegido || enviando}
                            aria-label={`Descartar a ${lead.nombre_completo}`}
                            onClick={() => {
                              if (!motivoElegido) return
                              // Al terminar el intento la fila vuelve a modo normal (si
                              // reaparece por deshacer/resincronización no debe renacer
                              // en modo descarte) y el foco ATERRIZA donde corresponde:
                              // éxito → la fila ya no existe, va al contenedor de la
                              // cola; fallo → al "Descartar" ghost de la misma fila.
                              void descartar(lead, motivoElegido).then((ok) => {
                                setDescartando((d) => ({ ...d, [lead.id]: false }))
                                requestAnimationFrame(() => {
                                  if (ok) refCola.current?.focus()
                                  else refDescartarGhost.current.get(lead.id)?.focus()
                                })
                              })
                            }}
                          >
                            {enviando ? 'Cerrando…' : 'Descartar'}
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            disabled={enviando}
                            aria-label={`Cancelar el descarte de ${lead.nombre_completo}`}
                            onClick={() => {
                              setDescartando((d) => ({ ...d, [lead.id]: false }))
                              // El botón que tiene el foco se desmonta: devolverlo al
                              // "Descartar" ghost que reaparece en su lugar.
                              requestAnimationFrame(() => refDescartarGhost.current.get(lead.id)?.focus())
                            }}
                          >
                            Cancelar
                          </Button>
                        </div>
                      ) : (
                        <div className="sm:w-[380px] sm:shrink-0">
                          <div className="flex items-center gap-2">
                            <Select
                              value={elegido}
                              disabled={enviando || turnoObligatorio}
                              onChange={(e) => setDestino((d) => ({ ...d, [lead.id]: e.target.value }))}
                              aria-label={`Asignar ${lead.nombre_completo} a un supervisor`}
                            >
                              <option value="">
                                {turnoObligatorio ? 'Guarda el turno de hoy…' : 'Asignar a…'}
                              </option>
                              {elegido && !supervisores.some((s) => s.perfil_id === elegido) ? (
                                <option value={elegido}>{asignacionTurno?.supervisor_nombre ?? 'Supervisora de turno'}</option>
                              ) : null}
                              {supervisores.map((s) => (
                                <option key={s.perfil_id} value={s.perfil_id}>
                                  {s.nombre} ({s.bandeja_pendiente} en bandeja)
                                </option>
                              ))}
                            </Select>
                            <Button
                              size="sm"
                              disabled={!elegido || enviando}
                              aria-label={`Repartir a ${lead.nombre_completo}`}
                              onClick={() => void repartir(lead, elegido)}
                            >
                              {enviando ? 'Enviando…' : 'Repartir'}
                            </Button>
                            <Button
                              ref={(el) => {
                                if (el) refDescartarGhost.current.set(lead.id, el)
                                else refDescartarGhost.current.delete(lead.id)
                              }}
                              size="sm"
                              variant="ghost"
                              disabled={enviando}
                              onClick={() => {
                                setDescartando((d) => ({ ...d, [lead.id]: true }))
                                // El foco sigue al modo: aterriza en el select de motivo
                                // (su aria-label anuncia el cambio al lector de pantalla).
                                requestAnimationFrame(() => refMotivo.current.get(lead.id)?.focus())
                              }}
                              aria-label={`Descartar a ${lead.nombre_completo} de la cola`}
                            >
                              Descartar
                            </Button>
                          </div>
                          {turnoObligatorio ? (
                            <p className={`mt-1.5 text-[11px] font-medium ${elegido ? 'text-muted-foreground' : 'text-warning-text'}`}>
                              {elegido
                                ? `Destino bloqueado por el turno de hoy: ${asignacionTurno?.supervisor_alias ?? asignacionTurno?.supervisor_nombre}.`
                                : 'Guarda primero el turno en Coordinación → supervisores.'}
                            </p>
                          ) : puedeElegirDestino && usaTurno ? (
                            <p className="mt-1.5 text-[11px] font-medium text-muted-foreground">
                              {asignacionTurno?.supervisor_id
                                ? `Turno sugerido: ${asignacionTurno.supervisor_alias ?? asignacionTurno.supervisor_nombre}. Puedes elegir cualquier supervisor activo.`
                                : 'No hay turno guardado. Puedes elegir cualquier supervisor activo.'}
                            </p>
                          ) : null}
                        </div>
                      )}
                    </div>
                  )
                })}
                <div className="border-t border-border pt-3">
                  <Paginacion
                    paginaActual={paginaCola.paginaActual}
                    paginas={paginaCola.paginas}
                    total={colaFiltrada.length}
                    onCambio={setPagina}
                    ariaLabel="Paginación de la cola de leads"
                  />
                </div>
              </div>
            )}
          </>
        )}
      </Card>
    </div>
  )
}

/** Pestaña "Descartados": lo que Rosa cerró en los últimos 30 días. Se monta al
 *  abrir la pestaña (y así siempre trae datos frescos del servidor). El Deshacer
 *  vive aquí toda la ventana de 24 h — no solo en el toast de 15 s de la cola. */
function PanelDescartados({ onCambio }: { onCambio: () => void }) {
  const [lista, setLista] = useState<LeadDescartado[]>([])
  const [pagina, setPagina] = useState(0)
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  const [expandidos, setExpandidos] = useState<Record<string, boolean>>({})
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setCargando(true)
    setError(null)
    try {
      const filas = await leadsDescartados(ctrl.signal)
      if (ctrl.signal.aborted) return
      setLista(filas)
      setPagina(0)
    } catch (e) {
      if (ctrl.signal.aborted) return
      setError(e instanceof Error ? e.message : 'No se pudo cargar la lista de descartados.')
    } finally {
      if (!ctrl.signal.aborted) setCargando(false)
    }
  }, [])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  const deshacer = useCallback(async (lead: LeadDescartado) => {
    setDeshaciendo(lead.id)
    try {
      await deshacerDescarte(lead.id)
      setLista((l) => l.filter((x) => x.id !== lead.id))
      toast.success(`${lead.nombre_completo} volvió a la cola`)
      onCambio() // el lead reabierto reaparece en la cola: que se refresque.
    } catch (e) {
      const mensaje = e instanceof Error ? e.message : 'No se pudo deshacer el descarte.'
      toast.error(mensaje)
      // La ventana venció, otro lo tocó o el lead ya tiene dueño: la lista local
      // quedó desfasada → se relee en vez de adivinar.
      if (e instanceof CrmApiError && ['FUERA_DE_COLA', 'REINTENTAR'].includes(e.code)) {
        void cargar()
      }
    } finally {
      setDeshaciendo(null)
    }
  }, [cargar, onCambio])

  const paginaDescartados = paginar(lista, pagina, PAGINA)

  return (
    <Card className="overflow-hidden">
      <SectionHead
        icon={Ban}
        title="Leads descartados"
        right={
          <span className="text-[11px] font-semibold text-muted-foreground">
            {!cargando && !error && lista.length > 0 ? `${lista.length} · últimos 30 días` : ''}
          </span>
        }
      />
      {cargando ? (
        <PanelCargando filas={3} />
      ) : error ? (
        <PanelError mensaje={error} onReintentar={() => void cargar()} reintentando={cargando} />
      ) : lista.length === 0 ? (
        <PanelVacio
          icono={Ban}
          titulo="No hay leads descartados"
          detalle="Cuando descartes un lead de la cola aparecerá aquí por 30 días. Podrás deshacerlo dentro de las primeras 24 horas."
        />
      ) : (
        <div className="space-y-2 px-5 pb-5">
          {paginaDescartados.visibles.map((lead) => {
            const marcado = lead.clasificacion_auto === 'posible_credito'
            const expandido = expandidos[lead.id] === true
            const comentarioLargo = (lead.comentario ?? '').length > 160
            const deshaciendoEste = deshaciendo === lead.id
            return (
              <div
                key={lead.id}
                data-descartado-id={lead.id}
                className="flex flex-col gap-2.5 rounded-xl border border-border p-3 sm:flex-row sm:items-start"
              >
                <div className="min-w-0 flex-1">
                  <p className="flex flex-wrap items-center gap-1.5 text-sm font-semibold">
                    <span className="truncate">{lead.nombre_completo}</span>
                    {marcado ? <BadgeCredito /> : null}
                    <span className="rounded-full bg-muted px-1.5 py-px text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                      {MOTIVO_LABEL[lead.motivo_descarte ?? ''] ?? lead.motivo_descarte ?? 'Sin motivo'}
                    </span>
                  </p>
                  <p className="truncate text-[11px] text-muted-foreground">
                    {origenLabel(lead.origen)}
                    {' · '}
                    <span className="font-semibold text-foreground">
                      {capitalLead(lead.monto_estimado, lead.moneda, true)}
                    </span>
                    {lead.distrito ? ` · ${lead.distrito}` : ''}
                    {' · descartado '}
                    <span className="font-semibold text-foreground">{fechaHora(lead.descartado_en)}</span>
                    {` por ${lead.es_mio ? 'ti' : lead.descartado_por_nombre}`}
                  </p>
                  {lead.comentario ? (
                    <div className={`mt-1.5 rounded-md border-l-2 py-1.5 pl-2.5 pr-2 ${
                      marcado ? 'border-warning bg-warning/5' : 'border-accent/40 bg-muted/50'}`}
                    >
                      <p className={`text-[13px] leading-snug text-foreground ${expandido ? '' : 'line-clamp-3'}`}>
                        “{lead.comentario}”
                      </p>
                      {comentarioLargo ? (
                        <button
                          type="button"
                          aria-expanded={expandido}
                          className="mt-0.5 text-[11px] font-semibold text-accent hover:underline"
                          onClick={() => setExpandidos((e2) => ({ ...e2, [lead.id]: !expandido }))}
                        >
                          {expandido ? 'Ver menos' : 'Ver todo el comentario'}
                        </button>
                      ) : null}
                    </div>
                  ) : null}
                  {lead.nota_descarte ? (
                    <p className="mt-1 text-[12px] text-muted-foreground">
                      <span className="font-semibold">Nota al descartar:</span> {lead.nota_descarte}
                    </p>
                  ) : null}
                </div>
                <div className="flex items-center gap-2 sm:w-[190px] sm:shrink-0 sm:justify-end">
                  {lead.puede_deshacer ? (
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={deshaciendoEste}
                      aria-label={`Deshacer el descarte de ${lead.nombre_completo}`}
                      onClick={() => void deshacer(lead)}
                    >
                      <RotateCcw className="size-3.5" aria-hidden />
                      {deshaciendoEste ? 'Deshaciendo…' : 'Deshacer'}
                    </Button>
                  ) : (
                    <span className="text-[11px] text-muted-foreground">
                      {lead.es_mio ? 'Ventana de 24 h vencida' : 'Descartado por otra persona'}
                    </span>
                  )}
                </div>
              </div>
            )
          })}
          <div className="border-t border-border pt-3">
            <Paginacion
              paginaActual={paginaDescartados.paginaActual}
              paginas={paginaDescartados.paginas}
              total={lista.length}
              onCambio={setPagina}
              ariaLabel="Paginación de leads descartados"
            />
          </div>
        </div>
      )}
    </Card>
  )
}

export function Repartir() {
  const [tab, setTab] = useState<'coordinacion' | 'panel' | 'conversiones' | 'cola' | 'descartados' | 'historial'>('coordinacion')
  // Al deshacer desde Descartados el lead vuelve a la cola: forzamos un remonte
  // de la pestaña Cola (key) para que la relea al volver a ella.
  const [colaKey, setColaKey] = useState(0)

  return (
    <div className="mx-auto max-w-[1240px] space-y-4">
      <div className="overflow-x-auto pb-1">
        <div
          role="tablist"
          aria-label="Vistas de distribución de leads"
          className="inline-flex min-w-max gap-1 rounded-lg border border-border bg-muted/50 p-1"
        >
          {([
            ['coordinacion', 'Coordinación → supervisores'],
            ['panel', 'Supervisión → analistas'],
            ['conversiones', 'Conversiones'],
            ['cola', 'Cola de nuevos'],
            ['historial', 'Historial'],
            ['descartados', 'Descartados'],
          ] as const).map(([k, label]) => (
            <button
              key={k}
              type="button"
              role="tab"
              aria-selected={tab === k}
              onClick={() => setTab(k)}
              className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                tab === k ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {tab === 'coordinacion' ? <AgendaRepartoDiaria /> : tab === 'panel' ? <PanelDistribucionReparto /> : tab === 'conversiones' ? <ConversionCoordinacion /> : tab === 'cola' ? <PanelCola key={colaKey} /> : tab === 'historial' ? <HistorialDerivaciones /> : (
        <PanelDescartados
          onCambio={() => { setColaKey((n) => n + 1); refrescarResumenReparto() }}
        />
      )}
    </div>
  )
}
