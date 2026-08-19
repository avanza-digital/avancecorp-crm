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
import {
  Split,
  Users,
  Wallet,
  Inbox,
  AlertTriangle,
  Search,
  Ban,
  RotateCcw,
  CalendarDays,
  SlidersHorizontal,
} from 'lucide-react'
import { toast } from 'sonner'
import {
  CrmApiError,
  descartarLead,
  deshacerDescarte,
  leadsDescartados,
  leadsPorRepartir,
  repartirLead,
  supervisoresParaReparto,
} from '@/data/crm-api'
import {
  MOTIVOS_DESCARTE,
  CAT_LABEL,
  CATEGORIAS_INTERES,
  origenLabel,
  type CategoriaInteres,
  type ColaLead,
  type LeadDescartado,
  type MotivoDescarte,
  type Origen,
  type SupervisorReparto,
} from '@/lib/tipos'
import { fechaHora, moneyK, numero, type Moneda } from '@/lib/format'
import {
  FILTROS_INICIALES,
  contarFiltrosAvanzados,
  contarMarcados,
  distritosDeCola,
  filtrarYOrdenarCola,
  origenesDeCola,
  type FiltrosCola,
} from '@/lib/cola-reparto'
import { useIngresosRepartoMes } from '@/data/use-ingresos-reparto-mes'
import {
  etiquetaMesReparto,
  etiquetaSemana,
  mesActualLima,
} from '@/lib/ingresos-reparto'
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

/** Cuántas filas se muestran por página local ("Mostrar 20 más"). */
const PAGINA = 20

/**
 * Cada cuánto se le pregunta al servidor si entraron leads nuevos.
 *
 * La cadena que alimenta esta cola tiene dos relojes encadenados: el puente mira
 * el documento de origen cada 15 min y el conector sube las filas de la hoja
 * cada 5. Un lead tarda hasta ~20 min en llegar, así que sondear cada minuto ya
 * hace que la llegada se sienta inmediata; bajar más solo gasta cuota.
 *
 * El sondeo NO pisa la lista: cuenta lo que falta y lo ofrece. Recargar por su
 * cuenta reordenaría las filas bajo el cursor de Rosa justo cuando está
 * eligiendo a quién repartir, y el clic acabaría en el lead equivocado.
 */
const SONDEO_COLA_MS = 60_000

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

/** Etiqueta humana de cada motivo de descarte (fuente única MOTIVOS_DESCARTE). */
const MOTIVO_LABEL: Record<string, string> =
  Object.fromEntries(MOTIVOS_DESCARTE.map((m) => [m.k, m.label]))

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
  cargando: boolean
  error: string | null
}

function useReparto() {
  const [estado, setEstado] = useState<EstadoReparto>({
    cola: [], supervisores: [], cargando: true, error: null,
  })
  const [enviandoId, setEnviandoId] = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)
  // Cuántos leads tiene el servidor que esta pantalla todavía no ha cargado.
  const [nuevosEnServidor, setNuevosEnServidor] = useState(0)
  // Los ids YA cargados. Se compara contra esto y no contra un total, porque un
  // total no distingue «entró uno» de «se fue uno»: con un reparto optimista en
  // vuelo, restar cifras anuncia leads nuevos que no existen.
  const idsCargados = useRef<Set<string>>(new Set())

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado((e) => ({ ...e, cargando: true, error: null }))
    try {
      const [cola, supervisores] = await Promise.all([
        leadsPorRepartir(ctrl.signal),
        supervisoresParaReparto(ctrl.signal),
      ])
      if (ctrl.signal.aborted) return
      idsCargados.current = new Set(cola.map((l) => l.id))
      setNuevosEnServidor(0)
      setEstado({ cola, supervisores, cargando: false, error: null })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((e) => ({
        ...e,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la cola de leads.',
      }))
    }
  }, [])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  /**
   * Sondeo: pregunta por la cola y solo CUENTA lo que no está cargado. Con la
   * pestaña oculta no gasta nada, y al volver a ella pregunta enseguida — es
   * cuando Rosa mira, y esperar al siguiente minuto se notaría.
   *
   * Un sondeo fallido se traga en silencio a propósito: es un extra sobre una
   * pantalla que ya funciona, y un toast de red cada minuto sería ruido puro.
   * Lo que de verdad importa (cargar, repartir, descartar) sí avisa al fallar.
   */
  useEffect(() => {
    const ctrl = new AbortController()
    let corriendo = false

    const sondear = async () => {
      if (corriendo || ctrl.signal.aborted) return
      if (typeof document !== 'undefined' && document.hidden) return
      corriendo = true
      try {
        const fresca = await leadsPorRepartir(ctrl.signal)
        if (ctrl.signal.aborted) return
        setNuevosEnServidor(fresca.filter((l) => !idsCargados.current.has(l.id)).length)
      } catch {
        // Silencio deliberado: ver el comentario de arriba.
      } finally {
        corriendo = false
      }
    }

    const alVolver = () => { if (!document.hidden) void sondear() }
    const id = window.setInterval(() => { void sondear() }, SONDEO_COLA_MS)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      window.clearInterval(id)
      document.removeEventListener('visibilitychange', alVolver)
      ctrl.abort()
    }
  }, [])

  /** Reparte un lead. El servidor manda: si rechaza, la fila NO se mueve. */
  const repartir = useCallback(async (lead: ColaLead, supervisorId: string) => {
    const destino = supervisorId
    setEnviandoId(lead.id)
    try {
      await repartirLead(lead.id, destino)
      // Éxito: la fila sale de la cola y la bandeja destino sube en 1 (el
      // servidor ya lo sabe; esto evita un refetch completo por cada reparto).
      // Sale también del registro del sondeo: ya no está en la cola del
      // servidor, así que dejarlo ahí no cambia la cuenta, pero mantener el
      // registro fiel a lo que hay cargado evita sorpresas si un día se pagina.
      idsCargados.current.delete(lead.id)
      setEstado((e) => ({
        ...e,
        cola: e.cola.filter((l) => l.id !== lead.id),
        supervisores: e.supervisores.map((s) =>
          s.perfil_id === destino ? { ...s, bandeja_pendiente: s.bandeja_pendiente + 1 } : s,
        ),
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
        && ['FUERA_DE_COLA', 'NO_INSISTA', 'REINTENTAR'].includes(error.code)) {
        void cargar()
        refrescarResumenReparto()
      }
    } finally {
      setEnviandoId(null)
    }
  }, [cargar, estado.supervisores])

  /** C1-bis: cierra el lead con motivo. Devuelve si el descarte ENTRÓ (el
   *  llamador decide a dónde va el foco). El deshacer vive en el toast — la
   *  RPC de servidor da 24 h, pero el gesto natural es el arrepentimiento al
   *  tiro; 15 s + closeButton del Toaster dan margen a teclado y lector. */
  const descartar = useCallback(async (lead: ColaLead, motivo: MotivoDescarte): Promise<boolean> => {
    setEnviandoId(lead.id)
    try {
      await descartarLead(lead.id, motivo)
      idsCargados.current.delete(lead.id)
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
      setEnviandoId(null)
    }
  }, [cargar])

  return { ...estado, enviandoId, nuevosEnServidor, recargar: cargar, repartir, descartar }
}

/**
 * Franja que ofrece los leads que entraron mientras Rosa miraba la pantalla.
 * Ofrece, no impone: el botón es suyo (ver SONDEO_COLA_MS).
 *
 * `role="status"` y no `alert`: no hay urgencia ni plazo, la pantalla sigue
 * operable, y un anuncio asertivo cortaría la lectura en curso. La región vive
 * SIEMPRE en el DOM y el texto llega después — es el orden fiable para que un
 * lector de pantalla anuncie el cambio (mismo patrón que AvisoDegradacion).
 */
function AvisoLeadsNuevos({ cuantos, onVer }: { cuantos: number, onVer: () => void }) {
  const frase = cuantos === 1
    ? 'Entró 1 lead nuevo a la cola'
    : `Entraron ${numero(cuantos)} leads nuevos a la cola`
  return (
    <div role="status" aria-label="Leads nuevos en la cola">
      {cuantos > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-accent/20 bg-accent/[0.07] px-4 py-2.5 text-xs text-accent">
          <span className="font-semibold">{frase}</span>
          <button
            type="button"
            aria-label={`Mostrar ${cuantos === 1 ? 'el lead nuevo' : 'los leads nuevos'} en la cola`}
            className="rounded font-semibold text-foreground underline-offset-2 hover:underline focus-visible:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring"
            onClick={onVer}
          >
            Mostrar
          </button>
        </div>
      )}
    </div>
  )
}

/** Franja historica de entradas: informa volumen del negocio, no actividad de Rosa. */
function PanelIngresosMes({ ahora }: { ahora: number }) {
  const mesMaximo = mesActualLima(ahora)
  const [mes, setMes] = useState(mesMaximo)
  const { datos, cargando, error, recargar } = useIngresosRepartoMes(mes)

  const maximoSemanal = useMemo(
    () => Math.max(1, ...(datos?.semanas.map((semana) => semana.total) ?? [0])),
    [datos],
  )

  return (
    <Card className="overflow-hidden" aria-label="Ingresos por semana">
      <SectionHead
        icon={CalendarDays}
        title="Ingresos por semana"
        right={
          <label className="flex items-center gap-2 text-[11px] font-semibold text-muted-foreground">
            <span className="sr-only">Mes de ingresos</span>
            <Input
              type="month"
              value={mes}
              max={mesMaximo}
              onChange={(evento) => {
                const siguiente = evento.target.value
                if (siguiente && siguiente <= mesMaximo) setMes(siguiente)
              }}
              aria-label="Mes de ingresos"
              className="h-8 w-[148px] text-xs"
            />
          </label>
        }
      />

      {cargando ? (
        <PanelCargando filas={2} />
      ) : error ? (
        <div className="px-5 pb-5">
          <AvisoDegradacion
            activo
            queReintenta="del resumen mensual de ingresos"
            onReintentar={() => { void recargar() }}
          >
            {error}
          </AvisoDegradacion>
        </div>
      ) : datos ? (
        <div className="grid gap-4 px-5 pb-5 lg:grid-cols-[190px_minmax(0,1fr)]">
          <div className="rounded-xl bg-primary px-4 py-4 text-primary-foreground">
            <p className="text-xs font-semibold capitalize opacity-75">
              {etiquetaMesReparto(mes)}
            </p>
            <p className="mt-1 text-3xl font-black tabular-nums">{numero(datos.total)}</p>
            <p className="text-xs font-semibold opacity-85">
              {datos.total === 1 ? 'lead ingresado' : 'leads ingresados'}
            </p>
            <p className="mt-3 text-[10px] leading-snug opacity-70">
              Cuenta todos los leads creados, aunque ya hayan sido derivados o descartados.
            </p>
          </div>

          {datos.total === 0 ? (
            <div className="grid min-h-32 place-items-center rounded-xl border border-dashed border-border px-4 text-center text-sm text-muted-foreground">
              No ingresaron leads durante {etiquetaMesReparto(mes)}.
            </div>
          ) : (
            <ol
              className="grid gap-2 sm:grid-cols-2 xl:grid-cols-6"
              aria-label={`Ingresos por semana de ${etiquetaMesReparto(mes)}`}
            >
              {datos.semanas.map((semana) => (
                <li
                  key={`${semana.desde}-${semana.hasta}`}
                  className="rounded-xl border border-border bg-muted/20 px-3 py-3"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-muted-foreground">
                        Semana {semana.numero}
                      </p>
                      <p className="mt-0.5 text-[11px] text-muted-foreground">
                        {etiquetaSemana(semana.desde, semana.hasta)}
                      </p>
                    </div>
                    <p className="text-xl font-black tabular-nums text-primary">{semana.total}</p>
                  </div>
                  <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-border/70" aria-hidden>
                    <div
                      className="h-full rounded-full bg-accent"
                      style={{ width: `${(semana.total / maximoSemanal) * 100}%` }}
                    />
                  </div>
                </li>
              ))}
            </ol>
          )}
        </div>
      ) : null}
    </Card>
  )
}

/** Pestaña "Cola": repartir o descartar los leads nuevos sin dueño. */
function PanelCola() {
  const {
    cola, supervisores, cargando, error, enviandoId, nuevosEnServidor,
    recargar, repartir, descartar,
  } = useReparto()
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
  const [mostrarFiltros, setMostrarFiltros] = useState(false)
  const [visibles, setVisibles] = useState(PAGINA)
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

  /** Cambia un filtro y vuelve a la primera página (evita "Mostrando 40 de 3"). */
  const setFiltro = useCallback((patch: Partial<FiltrosCola>) => {
    setFiltros((f) => ({ ...f, ...patch }))
    setVisibles(PAGINA)
  }, [])

  const marcados = useMemo(() => contarMarcados(cola), [cola])
  const origenes = useMemo(() => origenesDeCola(cola), [cola])
  const distritos = useMemo(() => distritosDeCola(cola), [cola])
  const filtrosAvanzados = contarFiltrosAvanzados(filtros)
  const colaFiltrada = useMemo(
    () => filtrarYOrdenarCola(cola, filtros, ahora),
    [ahora, cola, filtros],
  )
  const colaVisible = colaFiltrada.slice(0, visibles)
  const hayFiltrosActivos = filtros.busqueda.trim() !== ''
    || filtros.soloMarcados || filtros.origen !== '' || filtrosAvanzados > 0

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

      <PanelIngresosMes ahora={ahora} />

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

        {/* Va FUERA del ternario de estado: la cola vacía es justo cuando más
            importa avisar de que ya entró algo. */}
        <AvisoLeadsNuevos cuantos={nuevosEnServidor} onVer={() => void recargar()} />

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
                  onChange={(e) => setFiltro({ origen: e.target.value as Origen | '' })}
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
              <Button
                type="button"
                size="sm"
                variant={filtrosAvanzados > 0 ? 'secondary' : 'outline'}
                aria-expanded={mostrarFiltros}
                aria-controls="filtros-avanzados-reparto"
                onClick={() => setMostrarFiltros((actual) => !actual)}
                className="h-8 shrink-0"
              >
                <SlidersHorizontal className="size-3.5" aria-hidden />
                Más filtros{filtrosAvanzados > 0 ? ` (${filtrosAvanzados})` : ''}
              </Button>
            </div>

            {mostrarFiltros ? (
              <div
                id="filtros-avanzados-reparto"
                className="mx-5 mb-4 grid gap-3 rounded-xl border border-border bg-muted/20 p-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7"
              >
                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Interés
                  <Select
                    value={filtros.categoria}
                    onChange={(evento) => setFiltro({
                      categoria: evento.target.value as CategoriaInteres | '',
                    })}
                    aria-label="Filtrar por categoría de interés"
                  >
                    <option value="">Todos</option>
                    {CATEGORIAS_INTERES.map((categoria) => (
                      <option key={categoria.k} value={categoria.k}>{categoria.label}</option>
                    ))}
                  </Select>
                </label>

                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Moneda
                  <Select
                    value={filtros.moneda}
                    onChange={(evento) => {
                      const moneda = evento.target.value as Moneda | ''
                      setFiltro({
                        moneda,
                        ...(moneda ? {} : { montoMin: '', montoMax: '' }),
                      })
                    }}
                    aria-label="Filtrar por moneda"
                  >
                    <option value="">Todas</option>
                    <option value="PEN">Soles</option>
                    <option value="USD">Dólares</option>
                  </Select>
                </label>

                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Capital desde
                  <Input
                    type="number"
                    min="0"
                    step="100"
                    inputMode="numeric"
                    value={filtros.montoMin}
                    disabled={!filtros.moneda}
                    onChange={(evento) => setFiltro({ montoMin: evento.target.value })}
                    placeholder={filtros.moneda ? '0' : 'Elige moneda'}
                    aria-label="Capital mínimo"
                    className="h-9 text-xs"
                  />
                </label>

                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Capital hasta
                  <Input
                    type="number"
                    min="0"
                    step="100"
                    inputMode="numeric"
                    value={filtros.montoMax}
                    disabled={!filtros.moneda}
                    onChange={(evento) => setFiltro({ montoMax: evento.target.value })}
                    placeholder={filtros.moneda ? 'Sin tope' : 'Elige moneda'}
                    aria-label="Capital máximo"
                    className="h-9 text-xs"
                  />
                </label>

                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Distrito
                  <Select
                    value={filtros.distrito}
                    onChange={(evento) => setFiltro({ distrito: evento.target.value })}
                    aria-label="Filtrar por distrito"
                  >
                    <option value="">Todos</option>
                    {distritos.map((distrito) => (
                      <option key={distrito} value={distrito}>{distrito}</option>
                    ))}
                  </Select>
                </label>

                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Antigüedad
                  <Select
                    value={filtros.antiguedad}
                    onChange={(evento) => setFiltro({
                      antiguedad: evento.target.value as FiltrosCola['antiguedad'],
                    })}
                    aria-label="Filtrar por antigüedad"
                  >
                    <option value="">Cualquier tiempo</option>
                    <option value="hoy">Ingresó hoy</option>
                    <option value="uno_dos">Hace 1–2 días</option>
                    <option value="tres_mas">Hace 3 días o más</option>
                  </Select>
                </label>

                <label className="grid gap-1 text-[11px] font-semibold text-muted-foreground">
                  Comentario
                  <Select
                    value={filtros.comentario}
                    onChange={(evento) => setFiltro({
                      comentario: evento.target.value as FiltrosCola['comentario'],
                    })}
                    aria-label="Filtrar por comentario"
                  >
                    <option value="">Todos</option>
                    <option value="con">Con comentario</option>
                    <option value="sin">Sin comentario</option>
                  </Select>
                </label>

                {filtrosAvanzados > 0 ? (
                  <div className="flex items-end xl:col-span-7">
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      onClick={() => setFiltro({
                        categoria: '',
                        moneda: '',
                        montoMin: '',
                        montoMax: '',
                        distrito: '',
                        antiguedad: '',
                        comentario: '',
                      })}
                    >
                      Limpiar filtros adicionales
                    </Button>
                  </div>
                ) : null}
              </div>
            ) : null}

            {colaFiltrada.length === 0 ? (
              <PanelVacio
                icono={Search}
                titulo="Ningún lead coincide con la búsqueda o los filtros"
                detalle="Prueba con otro texto o restablece los filtros para ver la cola completa."
              >
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => { setFiltros(FILTROS_INICIALES); setVisibles(PAGINA) }}
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
                  const elegido = destino[lead.id] ?? ''
                  const enviando = enviandoId === lead.id
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
                      className="flex flex-col gap-2.5 rounded-xl border border-border p-3 lg:flex-row lg:items-start"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="flex flex-wrap items-center gap-1.5 text-sm font-semibold">
                          <span className="min-w-0 break-words">{lead.nombre_completo}</span>
                          {marcado ? <BadgeCredito /> : null}
                        </p>
                        <dl className="mt-2 grid grid-cols-2 gap-x-3 gap-y-2 rounded-lg bg-muted/30 px-3 py-2 sm:grid-cols-3 lg:grid-cols-6">
                          <div className="min-w-0">
                            <dt className="text-[9px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground">Capital</dt>
                            <dd className="truncate text-xs font-bold text-foreground">
                              {moneyK(lead.monto_estimado, lead.moneda)}
                            </dd>
                          </div>
                          <div className="min-w-0">
                            <dt className="text-[9px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground">Interés</dt>
                            <dd className="truncate text-xs font-semibold text-foreground">
                              {lead.categoria_interes ? CAT_LABEL[lead.categoria_interes] : 'Sin categoría'}
                            </dd>
                          </div>
                          <div className="min-w-0">
                            <dt className="text-[9px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground">Origen</dt>
                            <dd className="truncate text-xs font-semibold text-foreground">{origenLabel(lead.origen)}</dd>
                          </div>
                          <div className="min-w-0">
                            <dt className="text-[9px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground">Distrito</dt>
                            <dd className="break-words text-xs font-semibold leading-snug text-foreground">{lead.distrito || 'Sin distrito'}</dd>
                          </div>
                          <div className="min-w-0">
                            <dt className="text-[9px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground">Ingreso</dt>
                            <dd className="text-xs font-semibold leading-snug text-foreground">{fechaHora(lead.creado_en)}</dd>
                          </div>
                          <div className="min-w-0">
                            <dt className="text-[9px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground">En cola</dt>
                            <dd className={`truncate text-xs font-bold ${dias >= 1 ? 'text-warning-text' : 'text-foreground'}`}>
                              {esperaTxt(dias)}
                            </dd>
                          </div>
                        </dl>
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
                        ) : (
                          <p className="mt-1.5 rounded-md border border-dashed border-border px-2.5 py-1.5 text-[11px] font-medium text-muted-foreground">
                            Sin comentario del cliente.
                          </p>
                        )}
                      </div>
                      {enDescarte ? (
                        <div className="grid grid-cols-2 gap-2 sm:flex sm:items-center lg:w-[380px] lg:shrink-0">
                          <div className="col-span-2 sm:min-w-0 sm:flex-1">
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
                          </div>
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
                        <div className="grid grid-cols-2 gap-2 sm:flex sm:items-center lg:w-[380px] lg:shrink-0">
                          <div className="col-span-2 sm:min-w-0 sm:flex-1">
                            <Select
                              value={elegido}
                              disabled={enviando}
                              onChange={(e) => setDestino((d) => ({ ...d, [lead.id]: e.target.value }))}
                              aria-label={`Asignar ${lead.nombre_completo} a un supervisor`}
                            >
                              <option value="">Asignar a…</option>
                              {supervisores.map((s) => (
                                <option key={s.perfil_id} value={s.perfil_id}>
                                  {s.nombre} ({s.bandeja_pendiente} en bandeja)
                                </option>
                              ))}
                            </Select>
                          </div>
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
                      )}
                    </div>
                  )
                })}
                {colaFiltrada.length > colaVisible.length ? (
                  <div className="flex items-center justify-center gap-3 border-t border-border pt-3">
                    <span className="text-[11px] font-semibold text-muted-foreground">
                      Mostrando {colaVisible.length} de {colaFiltrada.length}
                    </span>
                    <Button size="sm" variant="outline" onClick={() => setVisibles((v) => v + PAGINA)}>
                      Mostrar {PAGINA} más
                    </Button>
                  </div>
                ) : colaFiltrada.length > PAGINA ? (
                  <p className="border-t border-border pt-3 text-center text-[11px] text-muted-foreground">
                    Fin de la cola · {colaFiltrada.length} leads
                  </p>
                ) : null}
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
          {lista.map((lead) => {
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
                      {moneyK(lead.monto_estimado, lead.moneda)}
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
        </div>
      )}
    </Card>
  )
}

export function Repartir() {
  const [tab, setTab] = useState<'cola' | 'descartados'>('cola')
  // Al deshacer desde Descartados el lead vuelve a la cola: forzamos un remonte
  // de la pestaña Cola (key) para que la relea al volver a ella.
  const [colaKey, setColaKey] = useState(0)

  return (
    <div className="space-y-4">
      <div
        role="tablist"
        aria-label="Vistas de la cola de leads"
        className="inline-flex gap-1 rounded-lg border border-border bg-muted/50 p-1"
      >
        {([['cola', 'Cola de nuevos'], ['descartados', 'Descartados']] as const).map(([k, label]) => (
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

      {tab === 'cola' ? (
        <PanelCola key={colaKey} />
      ) : (
        <PanelDescartados
          onCambio={() => { setColaKey((n) => n + 1); refrescarResumenReparto() }}
        />
      )}
    </div>
  )
}
