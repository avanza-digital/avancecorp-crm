// screens/facturacion.tsx — Facturación: el mes entero, día a día, por
// supervisor y por analista. Pantalla de Gerencia.
//
// La malla es el diseño: 30 columnas de día × filas de equipo con sus analistas
// anidados. La columna de nombres y la de total quedan congeladas; la cabecera
// de días también, porque a la fila quince nadie recuerda qué día está mirando.
//
// FILTROS: misma gramática que la consulta de Citas — un objeto plano donde
// «sin filtro» es '' o [], controles tontos que emiten PARCHES, etiquetas con ×
// que ya traen calculado su propio parche de retirada, y un botón de
// restablecer. Elegir un equipo NO esconde a los analistas de los demás: los
// deshabilita, para que se vea quién existe y por qué no está disponible.
//
// COMPARAR: marcar dos o más analistas cambia la malla a una lista plana con
// solo ellos, ordenados por capital. El lenguaje visual de comparar en este CRM
// es monocromo a propósito — el color mide MAGNITUD, nunca distingue personas.
//
// FUENTE DE DATOS: `crm.facturacion_diaria_fn`, que lee el núcleo del capital —
// el mismo del que salen Conversiones, Ranking y Metas. El servidor ya agrupó por
// día, ya resolvió el ámbito y ya puso el supervisor de ENTONCES; aquí no se
// recalcula nada, solo se dibuja. En modo demo se sirve un fixture con la MISMA
// forma, rotulado como ejemplo: el demo nunca puede prometer más que producción.
import { useEffect, useId, useMemo, useRef, useState, type CSSProperties, type JSX } from 'react'
import {
  CalendarRange,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Receipt,
  RotateCcw,
  TrendingUp,
  Users,
  X,
} from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Sheet, SheetBody, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { KpiCard } from '@/components/common/kpi-card'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { SectionHead } from '@/components/common/section-head'
import { useFacturacionDiaria } from '@/data/crm-queries'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useTipoCambio } from '@/lib/tipo-cambio'
import { rotuloTipoCambio } from '@/lib/capital-unificado'
import { useValorDiferido } from '@/lib/use-valor-diferido'
import { normalizar } from '@/lib/clientes-vista'
import { formatDateLocal, parseDateLocal } from '@/lib/cronograma'
import { filasFacturacionDemo } from '@/lib/demo-facturacion'
import {
  conciliarFiltro,
  construirMalla,
  desgloseDeCelda,
  diasDelMes,
  diasHabilesHasta,
  equiposDeRoster,
  esFinDeSemana,
  ESCALA_FACTURACION,
  etiquetaDiaLargo,
  etiquetaMes,
  filasComparadas,
  filtrarFilas,
  filtrarRoster,
  filtroInicial,
  filtroVacio,
  letraDia,
  mejorDia,
  mesDesplazado,
  numeroDia,
  pasoDeEscala,
  primerDiaDelMes,
  rosterDeEquipoYFilas,
  TIPO_CAPITAL_NUEVO,
  TIPO_TODOS,
  TIPOS_FACTURACION,
  totalAfirmable,
  totalesUnificados,
  valorCelda,
  type FilaFacturacion,
  type FilaFacturacionDia,
  type FiltroFacturacion,
  type MetricaFacturacion,
  type MiembroEquipo,
  type TipoFacturacion,
} from '@/lib/facturacion'
import { money, numero, type Moneda } from '@/lib/format'
import { cn } from '@/lib/utils'

/** Referencia estable: un `[]` nuevo en cada render invalidaría los useMemo. */
const SIN_FILAS: readonly FilaFacturacionDia[] = []

const MONEDAS: readonly Moneda[] = ['PEN', 'USD']
const ROTULO_MONEDA: Record<Moneda, string> = { PEN: 'Soles', USD: 'Dólares' }
/** Cómo se llama en castellano cada tipo que devuelve el servidor. */
const ROTULO_TIPO: Record<string, string> = {
  contrato_nuevo: 'Capital nuevo',
  contrato_upgrade: 'Upgrade',
  contrato_renovacion: 'Renovación',
  cooperativa: 'Cooperativa',
  [TIPO_TODOS]: 'Todo',
}
/** Cómo se nombra cada tipo en el desplegable y en los rótulos del KPI. */
const ROTULO_TIPO_CORTO: Record<TipoFacturacion, string> = {
  contrato_nuevo: 'Capital nuevo',
  contrato_renovacion: 'Renovaciones',
  contrato_upgrade: 'Upgrades',
  cooperativa: 'Cooperativa',
  [TIPO_TODOS]: 'Todos los tipos',
}

const ROTULO_METRICA: Record<MetricaFacturacion, string> = {
  capital: 'Capital',
  contratos: 'N.º de contratos',
}

/** Cifra que cabe en una celda de 56 px. La exacta vive en el título y en el detalle. */
function compacta(valor: number, metrica: MetricaFacturacion): string {
  if (valor <= 0) return '·'
  if (metrica === 'contratos') return String(valor)
  if (valor >= 1_000_000) return `${(valor / 1_000_000).toFixed(1)}M`
  return `${Math.round(valor / 1000)}k`
}

/** Mismo día de otro mes, recortado al último día si ese mes es más corto. */
function mismoDiaEnMes(mes: string, dia: string): string {
  const d = parseDateLocal(dia).getDate()
  const base = parseDateLocal(mes)
  const ultimo = new Date(base.getFullYear(), base.getMonth() + 1, 0).getDate()
  return formatDateLocal(new Date(base.getFullYear(), base.getMonth(), Math.min(d, ultimo)))
}

/** Interruptor de dos o más opciones — patrón vivo del CRM (aria-pressed en un group). */
function Interruptor<T extends string>({
  etiqueta,
  opciones,
  valor,
  rotulo,
  onCambio,
}: {
  etiqueta: string
  opciones: readonly T[]
  valor: T
  rotulo: Record<T, string>
  onCambio: (v: T) => void
}): JSX.Element {
  return (
    <div role="group" aria-label={etiqueta} className="flex gap-1">
      {opciones.map((o) => (
        <button
          key={o}
          type="button"
          aria-pressed={valor === o}
          onClick={() => onCambio(o)}
          className={cn(
            'min-h-11 rounded-full border px-3 py-0.5 text-[11px] font-bold transition-colors',
            'focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
            valor === o
              ? 'border-transparent bg-primary text-primary-foreground'
              : 'border-border text-muted-foreground-strong hover:bg-muted/60',
          )}
        >
          {rotulo[o]}
        </button>
      ))}
    </div>
  )
}

/**
 * Una celda de la malla.
 *
 * El objetivo táctil mide 52×32 px. No es una excepción: el mínimo AA de la
 * WCAG 2.2 (SC 2.5.8) son 24×24 px — los 44 px son el nivel AAA, y el botón por
 * defecto de la casa ya mide 36. Aun así, NADA se alcanza solo por aquí: el
 * nombre del analista es un botón de tamaño completo que abre su mes entero,
 * contrato por contrato.
 */
function Celda({
  valor,
  maximo,
  metrica,
  moneda,
  titulo,
  finde,
  hoy,
  destacada,
  onAbrir,
}: {
  valor: number
  maximo: number
  metrica: MetricaFacturacion
  moneda: Moneda
  titulo: string
  finde: boolean
  hoy: boolean
  destacada: boolean
  onAbrir?: (() => void) | undefined
}): JSX.Element {
  const paso = pasoDeEscala(valor, maximo)
  const cifra = metrica === 'capital' ? money(valor, moneda) : `${numero(valor)} contratos`
  const texto = `${titulo}: ${cifra}`
  const contenido = (
    <span
      className="flex h-8 items-center justify-center rounded-md text-[11px] font-semibold tabular-nums"
      style={{ background: paso.bg, color: paso.fg } as CSSProperties}
    >
      {compacta(valor, metrica)}
    </span>
  )
  return (
    <td
      className={cn(
        'border-b border-r border-border/60 p-0.5 text-center',
        // El foco no debe quedar bajo las capas pegadas (SC 2.4.11).
        'scroll-ml-52 scroll-mr-32 scroll-mt-12',
        finde && 'bg-muted/45',
        hoy && 'bg-accent/5',
        destacada && 'ring-2 ring-inset ring-primary',
      )}
    >
      {onAbrir && valor > 0 ? (
        <button
          type="button"
          onClick={onAbrir}
          title={texto}
          aria-label={texto}
          className="block w-full cursor-pointer rounded-md transition-transform hover:scale-105 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          {contenido}
        </button>
      ) : (
        // `aria-label` sobre un <span> sin rol NO produce nombre accesible: los
        // navegadores lo descartan. La cifra va en un `sr-only`; el día y la
        // persona ya los aportan las cabeceras de fila y de columna.
        <span title={texto}>
          <span aria-hidden>{contenido}</span>
          <span className="sr-only">{cifra}</span>
        </span>
      )}
    </td>
  )
}

/** Fila de un analista: casilla de comparación + nombre + sus días + su total. */
function FilaAnalista({
  fila,
  subtitulo,
  dias,
  hoy,
  maximo,
  metrica,
  moneda,
  marcado,
  diaAbierto,
  sangria,
  onMarcar,
  onAbrirMes,
  onAbrirCelda,
}: {
  fila: FilaFacturacion
  subtitulo?: string | undefined
  dias: readonly string[]
  hoy: string
  maximo: number
  metrica: MetricaFacturacion
  moneda: Moneda
  marcado: boolean
  diaAbierto: string | null
  sangria: boolean
  onMarcar: () => void
  onAbrirMes: () => void
  onAbrirCelda: (dia: string) => void
}): JSX.Element {
  const fondo = marcado ? 'bg-accent/5' : 'bg-card group-hover:bg-muted'
  return (
    <tr className={cn('group', marcado ? 'bg-accent/5' : 'hover:bg-muted/20')}>
      <th
        scope="row"
        className={cn('sticky left-0 z-10 border-b border-r border-border p-0 text-left', fondo)}
      >
        <div className={cn('flex items-center gap-2', sangria ? 'pl-4' : 'pl-3')}>
          <input
            type="checkbox"
            checked={marcado}
            onChange={onMarcar}
            aria-label={`Comparar a ${fila.nombre}`}
            className="size-4 shrink-0 accent-[var(--accent)]"
          />
          <button
            type="button"
            onClick={onAbrirMes}
            title={`Ver el mes completo de ${fila.nombre}`}
            aria-label={`Ver el mes completo de ${fila.nombre}`}
            className="flex min-h-9 min-w-0 flex-1 items-center gap-2.5 py-1 pr-3 text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          >
            <Avatar nombre={fila.nombre} className="size-7 shrink-0" />
            <span className="min-w-0">
              <span className="block truncate text-[13px] font-semibold">{fila.nombre}</span>
              {subtitulo != null && (
                <span className="block truncate text-[10px] font-medium text-muted-foreground">
                  {subtitulo}
                </span>
              )}
            </span>
          </button>
        </div>
      </th>
      {dias.map((dia, i) => (
        <Celda
          key={dia}
          valor={valorCelda(fila.dias[i], metrica)}
          maximo={maximo}
          metrica={metrica}
          moneda={moneda}
          titulo={`${fila.nombre}, ${etiquetaDiaLargo(dia)}`}
          finde={esFinDeSemana(dia)}
          hoy={dia === hoy}
          destacada={diaAbierto === dia}
          onAbrir={() => onAbrirCelda(dia)}
        />
      ))}
      <td
        className={cn(
          'sticky right-0 z-10 border-b border-l border-border px-3 py-1.5 text-right text-[12px] font-bold tabular-nums',
          fondo,
        )}
      >
        {metrica === 'capital' ? money(fila.total.capital, moneda) : numero(fila.total.contratos)}
      </td>
    </tr>
  )
}

/**
 * `filas` es la COSTURA de la fuente de datos: sin él la pantalla las pide al
 * servidor (o al fixture, en demo), y con él se le dan hechas — por ahí entran
 * las pruebas. La lista puede abarcar varios meses: la malla se queda solo con
 * el que se está mirando.
 */
export function Facturacion({
  filas: fuente,
}: {
  filas?: readonly FilaFacturacionDia[] | undefined
} = {}): JSX.Element {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const esDemo = yo?.demo === true
  const ahora = useAhora(600_000)
  const hoy = useMemo(() => formatDateLocal(new Date(ahora)), [ahora])
  const mesDeHoy = useMemo(() => primerDiaDelMes(hoy), [hoy])
  const idPanel = useId()

  const [mes, setMes] = useState<string>(() => primerDiaDelMes(formatDateLocal(new Date())))
  const [moneda, setMoneda] = useState<Moneda>('PEN')
  const [metrica, setMetrica] = useState<MetricaFacturacion>('capital')
  // Abre en capital nuevo —la captación, que es lo que se mira a diario— pero
  // ahora se puede cambiar. Todo lo de la pantalla sigue a esta perilla: el
  // titular, el ranking y el total del día. (Decisión de Miguel, 11/09/2026:
  // «lo que diga la perilla», para que nunca haya dos cifras distintas a la vez.)
  const [tipo, setTipo] = useState<TipoFacturacion>(TIPO_CAPITAL_NUEVO)
  const [filtro, setFiltro] = useState<FiltroFacturacion>(filtroInicial)
  const [panelAbierto, setPanelAbierto] = useState(false)
  const [busqueda, setBusqueda] = useState('')
  const [cerrados, setCerrados] = useState<readonly string[]>([])
  const [seleccion, setSeleccion] = useState<{ analistaId: string; dia: string | null } | null>(null)

  // Corte del mes en curso: los días que aún no han pasado salen vacíos.
  const corte = mes === mesDeHoy ? hoy : formatDateLocal(new Date(9999, 0, 1))

  // El servidor solo se consulta cuando no hay fixture de prueba ni modo demo.
  // La consulta cuelga de `crmQueryKeys.raiz`: el cierre de sesión la borra.
  const consulta = useFacturacionDiaria(fuente == null && !esDemo, mes)
  const demo = useMemo(
    () => (esDemo && fuente == null ? filasFacturacionDemo(mes, corte) : SIN_FILAS),
    [esDemo, fuente, mes, corte],
  )
  // El roster sale del mes ENTERO, sin filtrar: si saliera de lo ya filtrado,
  // elegir a alguien vaciaría la lista de la que se le acaba de elegir.
  const todos: readonly FilaFacturacionDia[] =
    fuente ?? (esDemo ? demo : (consulta.data ?? SIN_FILAS))

  // El organigrama que ya tiene el store (`crm.equipo_visible_fn`, con el mismo
  // alcance que la RLS: Gerencia ve la empresa entera). Se proyecta a la forma
  // mínima del modelo para que `lib/facturacion.ts` no dependa de los tipos del CRM.
  // En DEMO no se siembra: el fixture trae su propio reparto inventado y el
  // organigrama del store es otro (EQUIPO_DEMO). Mezclarlos pondría dos repartos
  // ajenos en la misma tabla, que parece una avería. El demo enseña MENOS que
  // producción, nunca más — esa es la dirección segura.
  const plantilla = useMemo<MiembroEquipo[]>(
    () =>
      (esDemo ? [] : equipo).map((m) => ({
        id: m.perfil_id,
        nombre: m.nombre_completo,
        rol: m.rol_crm,
        supervisorId: m.supervisor_id ?? null,
        activo: m.activo,
      })),
    [equipo, esDemo],
  )

  const roster = useMemo(() => rosterDeEquipoYFilas(plantilla, todos), [plantilla, todos])
  const equipos = useMemo(() => equiposDeRoster(roster), [roster])

  const filtradas = useMemo(() => filtrarFilas(todos, filtro), [todos, filtro])
  // El roster va filtrado con el MISMO filtro que las ventas: si no, elegir a un
  // analista seguiría pintando a todos los demás en cero.
  const rosterFiltrado = useMemo(() => filtrarRoster(roster, filtro), [roster, filtro])
  // Se construyen las DOS monedas siempre. La tabla de arriba pinta solo la
  // elegida —PEN y USD no se mezclan ahí—, pero el pie necesita ambas para dar
  // el total del día. `construirMalla` es pura y barata: dos pasadas sobre las
  // mismas filas cuestan menos que una consulta de más.
  const mallaPen = useMemo(
    () => construirMalla(filtradas, mes, 'PEN', tipo, rosterFiltrado),
    [filtradas, mes, tipo, rosterFiltrado],
  )
  const mallaUsd = useMemo(
    () => construirMalla(filtradas, mes, 'USD', tipo, rosterFiltrado),
    [filtradas, mes, tipo, rosterFiltrado],
  )
  const malla = moneda === 'PEN' ? mallaPen : mallaUsd

  // Tipo de cambio del MES QUE SE MIRA: un mes cerrado se congela en su último
  // día, así su total no cambia cada mañana. El mes en curso usa el vigente.
  // Izado una sola vez por pantalla (el hook no pasa por TanStack: uno por fila
  // multiplicaría las llamadas a la edge).
  const ultimoDiaDelMes = useMemo(() => {
    const todosLosDias = diasDelMes(mes)
    return todosLosDias[todosLosDias.length - 1] ?? mes
  }, [mes])
  const tipoCambio = useTipoCambio(true, mes === mesDeHoy ? undefined : ultimoDiaDelMes)
  const { tc } = tipoCambio
  const recargarTipoCambio = tipoCambio.recargar
  // El mes en curso pide el TC vigente, y su clave no lleva la fecha: una pestaña
  // abierta de un día para otro seguiría convirtiendo con la tasa de ayer
  // mientras la facturación sí se refresca. Se recarga al cambiar el día, igual
  // que Gestión de equipo. (Lo cazó Codex el 11/09/2026.)
  const diaDelTipoCambioAnterior = useRef(hoy)
  useEffect(() => {
    if (diaDelTipoCambioAnterior.current === hoy) return
    diaDelTipoCambioAnterior.current = hoy
    if (mes === mesDeHoy) recargarTipoCambio()
  }, [hoy, mes, mesDeHoy, recargarTipoCambio])

  const totales = useMemo(
    () => totalesUnificados(mallaPen, mallaUsd, tc?.promedio),
    [mallaPen, mallaUsd, tc],
  )
  const totalMes = totales.mes.capital
  // La fila aporta cuando HAY DÓLARES: es entonces cuando el equivalente en
  // soles dice algo que el total de arriba no dice. Sin un solo dólar el total
  // unificado sería idéntico al de soles, y un duplicado se come alto de
  // pantalla. Pedía las DOS monedas y eso escondía la fila justo en el caso en
  // que más sirve —un mes o un filtro con ventas SOLO en dólares—, donde la
  // vista en soles marca S/ 0 mientras hay dinero. (Codex, 11/09/2026.)
  const hayDolares = mallaUsd.total.contratos > 0

  // Mismo tramo del mes anterior — comparar un mes entero contra diez días mentiría.
  const mesPrevio = mesDesplazado(mes, -1)
  const consultaPrevia = useFacturacionDiaria(fuente == null && !esDemo, mesPrevio)
  const previo = useMemo(() => {
    const abierto = corte.startsWith('9999')
    const corteAnterior = abierto ? mesDesplazado(mes, 0) : mismoDiaEnMes(mesPrevio, corte)
    const base: readonly FilaFacturacionDia[] =
      fuente ??
      (esDemo ? filasFacturacionDemo(mesPrevio, corteAnterior) : (consultaPrevia.data ?? SIN_FILAS))
    return construirMalla(filtrarFilas(base, filtro), mesPrevio, moneda, tipo)
  }, [fuente, esDemo, consultaPrevia.data, mesPrevio, mes, corte, moneda, tipo, filtro])

  const totalActual = valorCelda(malla.total, 'capital')
  const totalPrevio = valorCelda(previo.total, 'capital')
  const delta = totalPrevio > 0 ? ((totalActual - totalPrevio) / totalPrevio) * 100 : null

  const mejor = mejorDia(malla, metrica)
  const habiles = diasHabilesHasta(malla, corte.startsWith('9999') ? (malla.dias.at(-1) ?? mes) : corte)
  const promedio = habiles > 0 ? valorCelda(malla.total, metrica) / habiles : 0

  const maximoAnalista = valorCelda(malla.maxAnalista, metrica)
  const maximoGrupo = valorCelda(malla.maxGrupo, metrica)
  const maximoDia = valorCelda(malla.maxDia, metrica)

  // «Todavía no sé» no es «no hubo ventas»: mientras la primera respuesta no
  // llega, la malla no se pinta vacía.
  const cargando = fuente == null && !esDemo && consulta.isPending
  const reintentar = (): void => {
    void consulta.refetch()
  }

  const comparando = filtro.analistas.length > 0
  const planas = useMemo(() => filasComparadas(malla), [malla])
  const cuantosAnalistas = malla.grupos.reduce((n, g) => n + g.analistas.length, 0)
  const vacia = cuantosAnalistas === 0

  const detalle = useMemo(
    () => (seleccion == null ? [] : desgloseDeCelda(todos, seleccion.analistaId, seleccion.dia, tipo)),
    [seleccion, todos, tipo],
  )

  const operacionesDelDetalle = detalle.reduce((n, f) => n + f.operaciones, 0)

  const nombreSeleccionado =
    roster.find((p) => p.id === seleccion?.analistaId)?.nombre ??
    detalle[0]?.analistaNombre ??
    'Analista'

  /** Los filtros se cambian por PARCHES; la conciliación vive aquí, no en los controles. */
  const cambiarFiltro = (cambios: Partial<FiltroFacturacion>): void => {
    setFiltro((anterior) => conciliarFiltro({ ...anterior, ...cambios }, roster))
    setSeleccion(null)
  }

  const alternarAnalista = (id: string): void => {
    cambiarFiltro({
      analistas: filtro.analistas.includes(id)
        ? filtro.analistas.filter((x) => x !== id)
        : [...filtro.analistas, id],
    })
  }

  const restablecer = (): void => {
    setFiltro(filtroInicial())
    setBusqueda('')
    setSeleccion(null)
  }

  const alternarGrupo = (id: string): void => {
    setCerrados((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
  }

  // Etiquetas de lo aplicado: cada una trae YA CALCULADO el parche que la quita.
  const etiquetas: Array<{ id: string; texto: string; quitar: Partial<FiltroFacturacion> }> = []
  if (filtro.equipo !== '') {
    etiquetas.push({
      id: 'equipo',
      texto: `Equipo de ${equipos.find((e) => e.id === filtro.equipo)?.nombre ?? filtro.equipo}`,
      quitar: { equipo: '' },
    })
  }
  if (filtro.analistas.length > 2) {
    etiquetas.push({
      id: 'analistas',
      texto: `${numero(filtro.analistas.length)} analistas`,
      quitar: { analistas: [] },
    })
  } else {
    for (const id of filtro.analistas) {
      etiquetas.push({
        id: `analista:${id}`,
        texto: roster.find((p) => p.id === id)?.nombre ?? id,
        quitar: { analistas: filtro.analistas.filter((x) => x !== id) },
      })
    }
  }

  // Cinco controles rehacen la malla entera; sin esto, para un lector de
  // pantalla pulsarlos no produce ninguna señal. Diferido como en Citas, para
  // no atropellar al lector mientras se cambia de mes varias veces seguidas.
  const anuncio = useValorDiferido(
    `${etiquetaMes(mes)} · ${ROTULO_MONEDA[moneda]} · ${ROTULO_TIPO[tipo]} · ${ROTULO_METRICA[metrica]} · ${numero(cuantosAnalistas)} analistas en ${numero(malla.grupos.length)} equipos`,
    250,
  )

  const q = normalizar(busqueda.trim())
  const rosterVisible = q === '' ? roster : roster.filter((p) => normalizar(p.nombre).includes(q))
  const elegibles = roster.filter((p) => filtro.equipo === '' || p.supervisorId === filtro.equipo)

  return (
    <div className="space-y-4">
      <p role="status" aria-live="polite" className="sr-only">
        {anuncio}
      </p>

      {esDemo && (
        // Solo en demo. Con datos reales este cartel sería una mentira al revés:
        // diría «ejemplo» de cifras que sí lo son.
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl border border-warning/35 bg-warning/10 px-4 py-2.5">
          <Badge color="var(--warning)" dot>
            Datos de ejemplo
          </Badge>
          <p className="text-xs font-medium text-warning-text">
            Estás en el modo de demostración: estas cifras están inventadas y no corresponden a
            ninguna venta real.
          </p>
        </div>
      )}

      <Card className="p-0">
        {/* Una sola fila: cuándo, en qué moneda, qué se mide y a quién se mira. */}
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 p-2.5">
          <div className="flex items-center gap-1.5">
            <Button
              variant="outline"
              size="icon"
              aria-label="Mes anterior"
              onClick={() => setMes((m) => mesDesplazado(m, -1))}
            >
              <ChevronLeft aria-hidden />
            </Button>
            <span className="min-w-[13ch] text-center text-sm font-bold tabular-nums first-letter:uppercase">
              {etiquetaMes(mes)}
            </span>
            <Button
              variant="outline"
              size="icon"
              aria-label="Mes siguiente"
              disabled={mes >= mesDeHoy}
              onClick={() => setMes((m) => mesDesplazado(m, 1))}
            >
              <ChevronRight aria-hidden />
            </Button>
          </div>

          <Interruptor
            etiqueta="Moneda — los soles y los dólares nunca se suman"
            opciones={MONEDAS}
            valor={moneda}
            rotulo={ROTULO_MONEDA}
            onCambio={setMoneda}
          />
          <Interruptor
            etiqueta="Qué se mide"
            opciones={['capital', 'contratos'] as const}
            valor={metrica}
            rotulo={ROTULO_METRICA}
            onCambio={setMetrica}
          />
          <div className="w-36 shrink-0">
            <Select
              aria-label="Tipo de capital"
              value={tipo}
              onChange={(e) => setTipo(e.target.value as TipoFacturacion)}
            >
              {TIPOS_FACTURACION.map((op) => (
                <option key={op} value={op}>
                  {ROTULO_TIPO_CORTO[op]}
                </option>
              ))}
            </Select>
          </div>

          <span className="h-6 w-px bg-border" aria-hidden />

          <div className="w-44 shrink-0">
            <Select
              aria-label="Equipo"
              value={filtro.equipo}
              onChange={(e) => cambiarFiltro({ equipo: e.target.value })}
            >
              <option value="">Todos los equipos</option>
              {equipos.map((eq) => (
                <option key={eq.id} value={eq.id}>
                  {eq.nombre}
                </option>
              ))}
            </Select>
          </div>

          <Button
            variant="outline"
            size="sm"
            aria-expanded={panelAbierto}
            aria-controls={idPanel}
            onClick={() => setPanelAbierto((v) => !v)}
          >
            <Users aria-hidden />
            Analistas
            {filtro.analistas.length > 0 && (
              <span className="rounded-full bg-accent px-1.5 text-[11px] font-bold tabular-nums text-accent-foreground">
                {filtro.analistas.length}
              </span>
            )}
            <ChevronDown
              aria-hidden
              className={cn('transition-transform', panelAbierto && 'rotate-180')}
            />
          </Button>

          {etiquetas.map((etiqueta) => (
            <Button
              key={etiqueta.id}
              variant="secondary"
              size="sm"
              aria-label={`Quitar ${etiqueta.texto}`}
              onClick={() => cambiarFiltro(etiqueta.quitar)}
            >
              {etiqueta.texto}
              <X aria-hidden />
            </Button>
          ))}

          {/* Montado SIEMPRE, como en citas/filtros.tsx: condicionarlo lo hacía
              desaparecer bajo el foco de quien acababa de pulsarlo. */}
          <Button
            variant="ghost"
            size="icon"
            className="ml-auto"
            aria-label="Restablecer filtros"
            title="Restablecer filtros"
            disabled={filtroVacio(filtro)}
            onClick={restablecer}
          >
            <RotateCcw aria-hidden />
          </Button>
        </div>

        {/* Panel de analistas: elegir uno lo aísla; elegir varios los compara. */}
        <div id={idPanel} hidden={!panelAbierto} className="space-y-2.5 border-t border-border p-2.5">
          <div className="flex flex-wrap items-center gap-2">
            <Input
              type="search"
              className="w-64"
              placeholder="Buscar analista…"
              aria-label="Buscar analista"
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            <Button
              variant="outline"
              size="sm"
              disabled={elegibles.length === 0}
              onClick={() => cambiarFiltro({ analistas: elegibles.map((p) => p.id) })}
            >
              Marcar {filtro.equipo === '' ? 'a todos' : 'al equipo'} ({elegibles.length})
            </Button>
            <Button
              variant="ghost"
              size="sm"
              disabled={filtro.analistas.length === 0}
              onClick={() => cambiarFiltro({ analistas: [] })}
            >
              Ninguno
            </Button>
            <span className="ml-auto text-[11px] font-medium text-muted-foreground-strong">
              Marca a varios para compararlos uno debajo de otro.
            </span>
          </div>

          <fieldset>
            <legend className="sr-only">
              Analistas — puedes elegir varios para compararlos
            </legend>
            {rosterVisible.length === 0 ? (
              <p className="py-2 text-xs text-muted-foreground">
                Ningún analista coincide con «{busqueda.trim()}».
              </p>
            ) : (
              <div className="flex flex-wrap items-start gap-x-4 gap-y-1.5">
                {equipos.map((eq) => {
                  const gente = rosterVisible.filter((p) => p.supervisorId === eq.id)
                  if (gente.length === 0) return null
                  const bloqueado = filtro.equipo !== '' && eq.id !== filtro.equipo
                  return (
                    <div
                      key={eq.id}
                      className={cn(
                        'flex max-w-full flex-wrap items-center gap-1',
                        bloqueado && 'opacity-40',
                      )}
                    >
                      <span className="shrink-0 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                        {eq.nombre}
                      </span>
                      {gente.map((p) => {
                        const activo = filtro.analistas.includes(p.id)
                        return (
                          <label
                            key={p.id}
                            className={cn(
                              'inline-flex min-h-8 items-center gap-1.5 rounded-full border px-2 text-[11.5px] font-semibold',
                              bloqueado ? 'cursor-not-allowed' : 'cursor-pointer',
                              activo && !bloqueado
                                ? 'border-accent/40 bg-accent/10'
                                : 'border-border hover:bg-muted/60',
                            )}
                          >
                            <input
                              type="checkbox"
                              checked={activo}
                              disabled={bloqueado}
                              onChange={() => alternarAnalista(p.id)}
                              aria-label={`Comparar a ${p.nombre}`}
                              className="size-3.5 shrink-0 accent-[var(--accent)]"
                            />
                            {p.nombre}
                          </label>
                        )
                      })}
                    </div>
                  )
                })}
              </div>
            )}
          </fieldset>
        </div>
      </Card>

      {/* Los cuatro números de arriba — siempre sobre lo que se está mirando */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label={
            filtroVacio(filtro) ? `Facturado en ${etiquetaMes(mes)}` : 'Facturado por lo filtrado'
          }
          value={money(valorCelda(malla.total, 'capital'), moneda)}
          icon={Receipt}
          color="var(--chart-1)"
          sub={
            delta == null
              ? 'Sin cifra anterior con la que comparar'
              : `${delta >= 0 ? '+' : '−'}${Math.abs(delta).toFixed(1)} % vs. el mismo tramo de ${etiquetaMes(mesPrevio)}`
          }
        />
        <KpiCard
          label={tipo === TIPO_TODOS ? 'Contratos cerrados' : `Contratos · ${ROTULO_TIPO[tipo]}`}
          value={numero(valorCelda(malla.total, 'contratos'))}
          icon={Users}
          color="var(--chart-4)"
          sub={`En ${moneda}, de ${numero(cuantosAnalistas)} analista${cuantosAnalistas === 1 ? '' : 's'} en ${numero(malla.grupos.length)} equipo${malla.grupos.length === 1 ? '' : 's'}`}
          delay={60}
        />
        <KpiCard
          label="Mejor día del mes"
          value={
            mejor == null
              ? '—'
              : metrica === 'capital'
                ? money(mejor.valor, moneda)
                : `${numero(mejor.valor)} contratos`
          }
          icon={TrendingUp}
          color="var(--chart-2)"
          sub={mejor == null ? 'Todavía sin cierres' : etiquetaDiaLargo(mejor.dia)}
          delay={120}
        />
        <KpiCard
          label="Promedio por día hábil"
          value={
            metrica === 'capital'
              ? money(Math.round(promedio), moneda)
              : `${promedio.toFixed(1)} contratos`
          }
          icon={CalendarRange}
          color="var(--chart-3)"
          sub={`${numero(habiles)} días hábiles corridos — el domingo no cuenta`}
          delay={180}
        />
      </div>

      {/* La malla */}
      <Card className="overflow-hidden p-0">
        <SectionHead
          icon={Receipt}
          title={
            comparando
              ? `Comparando ${numero(filtro.analistas.length)} analista${filtro.analistas.length === 1 ? '' : 's'}, día a día`
              : 'Cada día del mes, por equipo y por analista'
          }
          right={
            <div className="flex items-center gap-2 text-[11px] font-semibold text-muted-foreground-strong">
              <span>menos</span>
              <span className="flex gap-0.5" aria-hidden>
                {ESCALA_FACTURACION.map((paso) => (
                  <span
                    key={paso.bgHex}
                    className="block h-3 w-4 rounded-sm border border-border/60"
                    style={{ background: paso.bg }}
                  />
                ))}
              </span>
              <span>más</span>
            </div>
          }
        />

        {cargando ? (
          // Mientras el servidor responde no se pinta una malla vacía: parecería
          // un mes sin ventas, que es una respuesta distinta de «todavía no sé».
          <div className="border-t border-border p-4">
            <PanelCargando filas={4} onReintentar={reintentar} reintentando={consulta.isFetching} />
          </div>
        ) : consulta.isError ? (
          <div className="border-t border-border">
            <PanelError
              mensaje="No se pudo cargar la facturación de este mes."
              onReintentar={reintentar}
              reintentando={consulta.isFetching}
            />
          </div>
        ) : vacia ? (
          <div className="flex flex-col items-center gap-3 border-t border-border px-6 py-14 text-center">
            <p className="text-sm font-semibold">
              {filtroVacio(filtro)
                ? 'Todavía no hay cierres en este mes.'
                : 'Ningún cierre coincide con estos filtros.'}
            </p>
            {!filtroVacio(filtro) && (
              <Button variant="outline" size="sm" onClick={restablecer}>
                <RotateCcw aria-hidden /> Limpiar filtros
              </Button>
            )}
          </div>
        ) : (
          <>
            {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Malla de 30 columnas: el foco habilita recorrerla con las flechas. Con los grupos colapsados no queda NINGÚN hijo enfocable en el área que se desplaza (las celdas de fila de equipo nunca son botones), así que sin esto los días 15-30 son inalcanzables sin ratón. Mismo patrón que hoy/reuniones-gerencia.tsx. */}
            <div className="ac-scroll overflow-auto border-t border-border focus-visible:outline-2 focus-visible:outline-offset-2" role="region" tabIndex={0} aria-label={`Facturación diaria de ${etiquetaMes(mes)} en ${ROTULO_MONEDA[moneda]}, ${ROTULO_TIPO[tipo]}`}>
              <table className="border-separate border-spacing-0 bg-card text-sm">
                <caption className="sr-only">
                  {ROTULO_METRICA[metrica]} por día · {etiquetaMes(mes)} · {ROTULO_MONEDA[moneda]} ·{' '}
                  {ROTULO_TIPO[tipo]}.
                  Marca la casilla de dos o más analistas para verlos solos y compararlos; activa
                  una celda para ver los contratos de ese día.
                </caption>
                <thead>
                  <tr>
                    <th
                      scope="col"
                      className="sticky left-0 top-0 z-40 w-52 min-w-52 border-b border-r border-border bg-muted px-4 py-2 text-left text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
                    >
                      {comparando ? 'Analistas comparados' : 'Supervisor / analista'}
                    </th>
                    {malla.dias.map((dia) => (
                      <th
                        key={dia}
                        scope="col"
                        className={cn(
                          'sticky top-0 z-30 w-13 min-w-13 border-b border-r border-border/60 bg-muted px-0 py-1.5 text-center align-bottom',
                          esFinDeSemana(dia) && 'bg-muted-foreground/15',
                          dia === hoy && 'shadow-[inset_0_3px_0_var(--accent)]',
                        )}
                      >
                        <span
                          className={cn(
                            'block text-[13px] font-bold leading-tight tabular-nums',
                            dia === hoy && 'text-accent',
                          )}
                        >
                          {numeroDia(dia)}
                        </span>
                        <span className="block text-[9px] font-semibold uppercase text-muted-foreground">
                          {letraDia(dia)}
                        </span>
                      </th>
                    ))}
                    <th
                      scope="col"
                      className="sticky right-0 top-0 z-40 w-32 min-w-32 border-b border-l border-border bg-muted px-3 py-2 text-right text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
                    >
                      Total del mes
                    </th>
                  </tr>
                </thead>

                <tbody>
                  {comparando
                    ? planas.map((fila) => (
                        <FilaAnalista
                          key={fila.id}
                          fila={fila}
                          subtitulo={`Equipo de ${fila.supervisorNombre}`}
                          dias={malla.dias}
                          hoy={hoy}
                          maximo={maximoAnalista}
                          metrica={metrica}
                          moneda={moneda}
                          marcado={filtro.analistas.includes(fila.id)}
                          diaAbierto={seleccion?.analistaId === fila.id ? seleccion.dia : null}
                          sangria={false}
                          onMarcar={() => alternarAnalista(fila.id)}
                          onAbrirMes={() => setSeleccion({ analistaId: fila.id, dia: null })}
                          onAbrirCelda={(dia) => setSeleccion({ analistaId: fila.id, dia })}
                        />
                      ))
                    : malla.grupos.map((grupo) => {
                        const abierto = !cerrados.includes(grupo.id)
                        return [
                          <tr key={grupo.id} className="bg-muted/55">
                            <th
                              scope="row"
                              className="sticky left-0 z-20 border-b border-r border-border bg-muted p-0 text-left"
                            >
                              <button
                                type="button"
                                aria-expanded={abierto}
                                onClick={() => alternarGrupo(grupo.id)}
                                className="flex min-h-9 w-full cursor-pointer items-center gap-2 px-4 py-1.5 text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                              >
                                <ChevronRight
                                  aria-hidden
                                  className={cn(
                                    'size-3.5 shrink-0 text-muted-foreground transition-transform',
                                    abierto && 'rotate-90',
                                  )}
                                />
                                <span className="truncate text-[13px] font-bold">
                                  {grupo.nombre}
                                </span>
                                <span className="ml-auto shrink-0 text-[11px] font-semibold text-muted-foreground">
                                  {grupo.analistas.length}
                                </span>
                              </button>
                            </th>
                            {malla.dias.map((dia, i) => (
                              <Celda
                                key={dia}
                                valor={valorCelda(grupo.dias[i], metrica)}
                                maximo={maximoGrupo}
                                metrica={metrica}
                                moneda={moneda}
                                titulo={`${grupo.nombre}, ${etiquetaDiaLargo(dia)}`}
                                finde={esFinDeSemana(dia)}
                                hoy={dia === hoy}
                                destacada={false}
                              />
                            ))}
                            <td className="sticky right-0 z-20 border-b border-l border-border bg-muted px-3 py-2 text-right text-[13px] font-extrabold tabular-nums">
                              {metrica === 'capital'
                                ? money(grupo.total.capital, moneda)
                                : numero(grupo.total.contratos)}
                            </td>
                          </tr>,
                          ...(abierto
                            ? grupo.analistas.map((a) => (
                                <FilaAnalista
                                  key={a.id}
                                  fila={a}
                                  dias={malla.dias}
                                  hoy={hoy}
                                  maximo={maximoAnalista}
                                  metrica={metrica}
                                  moneda={moneda}
                                  marcado={filtro.analistas.includes(a.id)}
                                  diaAbierto={seleccion?.analistaId === a.id ? seleccion.dia : null}
                                  sangria
                                  onMarcar={() => alternarAnalista(a.id)}
                                  onAbrirMes={() => setSeleccion({ analistaId: a.id, dia: null })}
                                  onAbrirCelda={(dia) => setSeleccion({ analistaId: a.id, dia })}
                                />
                              ))
                            : []),
                        ]
                      })}
                </tbody>

                <tfoot>
                  <tr>
                    <th
                      scope="row"
                      className="sticky left-0 z-20 border-t-2 border-r border-border bg-card px-4 py-2 text-left text-[12px] font-extrabold"
                    >
                      {filtroVacio(filtro) ? 'Total de la empresa' : 'Total de lo que estás viendo'}
                    </th>
                    {malla.dias.map((dia, i) => {
                      const v = valorCelda(malla.totalPorDia[i], metrica)
                      const alto =
                        maximoDia > 0 && v > 0 ? Math.max(3, Math.round((v / maximoDia) * 26)) : 2
                      return (
                        <td
                          key={dia}
                          className={cn(
                            'border-t-2 border-r border-border/60 px-0.5 pb-1.5 pt-1 align-bottom',
                            esFinDeSemana(dia) && 'bg-muted/45',
                          )}
                          title={`${etiquetaDiaLargo(dia)}: ${metrica === 'capital' ? money(v, moneda) : `${numero(v)} contratos`}`}
                        >
                          <span className="block pb-1 text-[9px] font-bold tabular-nums text-muted-foreground-strong">
                            {compacta(v, metrica)}
                          </span>
                          <span
                            aria-hidden
                            className={cn(
                              'mx-auto block w-5 rounded-t-sm',
                              v > 0 ? 'bg-accent' : 'bg-border',
                            )}
                            style={{ height: `${alto}px` }}
                          />
                        </td>
                      )
                    })}
                    <td className="sticky right-0 z-20 border-t-2 border-l border-border bg-card px-3 py-2 text-right text-[13px] font-extrabold tabular-nums">
                      {metrica === 'capital'
                        ? money(malla.total.capital, moneda)
                        : numero(malla.total.contratos)}
                    </td>
                  </tr>

                  {/* El total del día con las DOS monedas. El capital lleva el
                      USD convertido a soles al TC real; si no hay TC, el total
                      es solo-PEN y se dice. Los contratos se suman tal cual. */}
                  {hayDolares && (
                  <tr className="bg-muted/40">
                    <th
                      scope="row"
                      className="sticky left-0 z-20 border-t border-r border-border bg-muted px-4 py-1.5 text-left"
                    >
                      <span className="block text-[12px] font-extrabold">
                        {metrica === 'capital' ? 'Total del día en soles' : 'Total del día'}
                      </span>
                      <span className="block text-[10px] font-medium text-muted-foreground">
                        {metrica !== 'capital'
                          ? 'contratos de ambas monedas'
                          : totalMes.tc != null
                            ? rotuloTipoCambio(totalMes.tc, tc?.fuente ?? '')
                            : tc === undefined
                              ? 'consultando el tipo de cambio…'
                              : 'total no disponible: falta el tipo de cambio'}
                      </span>
                      {/* Una caída del BCRP es transitoria y dejaba la fila en
                          guiones hasta remontar la pantalla: el reintento de
                          arriba solo recarga la facturación. (Codex, 11/09.) */}
                      {metrica === 'capital' && tc === null && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={recargarTipoCambio}
                          className="mt-0.5 h-6 px-1.5 text-[10px] font-semibold"
                        >
                          <RotateCcw aria-hidden className="size-3" /> Reintentar
                        </Button>
                      )}
                    </th>
                    {malla.dias.map((dia, i) => {
                      const unificado = totales.porDia[i]
                      // Sin conversión real no se afirma un total: el solo-PEN
                      // bajo el rótulo «en soles» se leería como si el dólar
                      // estuviera dentro. Mejor un guion honesto.
                      const v =
                        metrica !== 'capital'
                          ? (unificado?.contratos ?? 0)
                          : unificado != null && totalAfirmable(unificado.capital)
                            ? unificado.capital.total
                            : null
                      // La celda va abreviada («66k»), así que el importe EXACTO
                      // tiene que estar en algún sitio consultable: en el title y
                      // en un `sr-only`, como hace `Celda`. Sin esto había que
                      // hacer la conversión a mano para saber el total del día.
                      // (Codex, 11/09/2026.)
                      const exacto =
                        metrica !== 'capital'
                          ? `${numero(v ?? 0)} contratos`
                          : v == null
                            ? 'total no disponible: falta el tipo de cambio'
                            : money(v, 'PEN')
                      const desglose =
                        metrica !== 'capital'
                          ? ''
                          : ` (${money(unificado?.capital.pen ?? 0, 'PEN')} + ${money(unificado?.capital.usd ?? 0, 'USD')})`
                      return (
                        <td
                          key={dia}
                          className={cn(
                            'border-t border-r border-border/60 px-0.5 py-1 text-center',
                            esFinDeSemana(dia) && 'bg-muted/60',
                          )}
                          title={`${etiquetaDiaLargo(dia)}: ${exacto}${desglose}`}
                        >
                          <span className="block text-[9px] font-extrabold tabular-nums" aria-hidden>
                            {v == null ? '—' : compacta(v, metrica)}
                          </span>
                          <span className="sr-only">{exacto}</span>
                        </td>
                      )
                    })}
                    <td className="sticky right-0 z-20 border-t border-l border-border bg-muted px-3 py-1.5 text-right text-[13px] font-extrabold tabular-nums">
                      {metrica !== 'capital'
                        ? numero(totales.mes.contratos)
                        : totalAfirmable(totalMes)
                          ? money(totalMes.total ?? 0, 'PEN')
                          : '—'}
                    </td>
                  </tr>
                  )}
                </tfoot>
              </table>
            </div>
            <p className="border-t border-border px-4 py-2 text-[11px] text-muted-foreground">
              {comparando ? (
                // Al marcar al primero, el resto sale de la malla — es lo que hace
                // un filtro. Aquí se dice dónde está la vuelta, que si no hay que
                // adivinarla.
                <>
                  Estás viendo solo a quienes marcaste. Para añadir o quitar a alguien, abre
                  «Analistas» arriba, o usa las etiquetas con × junto al filtro.
                </>
              ) : (
                <>
                  ↔ Desplaza la malla para ver el mes entero. Los nombres, la cabecera de días y el
                  total quedan fijos. Marca la casilla de un analista para verlo solo, o la de
                  varios para compararlos uno debajo de otro.
                </>
              )}
            </p>
          </>
        )}
      </Card>

      {/* Detalle: inspector NO modal — la malla sigue consultable de fondo. */}
      {/* NO modal a propósito: la malla sigue consultable de fondo mientras se
          salta de celda en celda. Radix nombra el panel con su <SheetTitle>. */}
      <Sheet open={seleccion != null} onClose={() => setSeleccion(null)} modal={false}>
        <SheetHeader>
          <div className="flex items-start justify-between gap-3">
            <SheetTitle>{nombreSeleccionado}</SheetTitle>
            <Button
              variant="ghost"
              size="icon"
              aria-label="Cerrar detalle"
              onClick={() => setSeleccion(null)}
            >
              <X aria-hidden />
            </Button>
          </div>
          <SheetDescription>
            {seleccion?.dia != null
              ? etiquetaDiaLargo(seleccion.dia)
              : `${etiquetaMes(mes)} · ${ROTULO_MONEDA[moneda]} · ${ROTULO_TIPO[tipo]}`}
            {' · '}
            {numero(operacionesDelDetalle)}{' '}
            {operacionesDelDetalle === 1 ? 'operación' : 'operaciones'}
          </SheetDescription>
        </SheetHeader>
        <SheetBody>
          {detalle.length === 0 ? (
            <p className="py-10 text-center text-sm text-muted-foreground">
              Sin cierres que mostrar.
            </p>
          ) : (
            <>
              <ul className="divide-y divide-border">
                {detalle.map((f) => (
                  <li key={`${f.dia}|${f.tipo}|${f.moneda}`} className="flex items-start gap-3 py-3">
                    <div className="min-w-0 flex-1">
                      <p className="text-[13px] font-bold first-letter:uppercase">{etiquetaDiaLargo(f.dia)}</p>
                      <p className="mt-0.5 text-xs text-muted-foreground">
                        {ROTULO_TIPO[f.tipo] ?? f.tipo} · {numero(f.operaciones)}{' '}
                        {f.operaciones === 1 ? 'operación' : 'operaciones'}
                      </p>
                    </div>
                    <div className="shrink-0 text-right">
                      <p className="text-[13px] font-extrabold tabular-nums">
                        {money(f.capital, f.moneda)}
                      </p>
                      <Badge
                        color={f.moneda === 'USD' ? 'var(--chart-2)' : 'var(--accent)'}
                        className="mt-1"
                      >
                        {f.moneda}
                      </Badge>
                    </div>
                  </li>
                ))}
              </ul>
              {/* Honestidad sobre el alcance: el servidor devuelve el mes ya
                  agrupado, así que aquí no hay —ni puede haber— la lista de
                  contratos uno a uno. Prometerla sería inventarla. */}
              <p className="pt-4 text-[11px] leading-relaxed text-muted-foreground">
                Este es el desglose de lo cerrado, no la lista de contratos: el servidor entrega
                el mes ya agrupado por día, tipo y moneda.
              </p>
            </>
          )}
        </SheetBody>
      </Sheet>
    </div>
  )
}
