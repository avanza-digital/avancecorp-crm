// screens/facturacion.tsx — Facturación: el mes entero, día a día, por
// supervisor y por analista. Pantalla de Gerencia y, desde el 16/09/2026, de
// Supervisión: el supervisor ve el avance de SU equipo (el servidor recorta el
// ámbito a las filas cuyo supervisor de entonces es él, más sus ventas propias;
// aquí no se filtra nada por rol).
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
  MousePointerClick,
  RotateCcw,
  SlidersHorizontal,
  TriangleAlert,
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
import { useFacturacionDeMeses } from '@/data/crm-queries'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useEsEstrecha, useEsTactil } from '@/lib/media'
import { useTipoCambio } from '@/lib/tipo-cambio'
import { rotuloTipoCambio } from '@/lib/capital-unificado'
import { useValorDiferido } from '@/lib/use-valor-diferido'
import { normalizar } from '@/lib/clientes-vista'
import { formatDateLocal } from '@/lib/cronograma'
import { fechaLima } from '@/lib/agenda-derivada'
import { filasFacturacionDemo } from '@/lib/demo-facturacion'
import {
  combinarEnSoles,
  conciliarFiltro,
  construirMallaDeDias,
  desgloseDeCelda,
  diasDelMes,
  diasDelPeriodo,
  diasHabilesHasta,
  equiposDeRoster,
  esDomingo,
  esFinDeSemana,
  ESCALA_FACTURACION,
  etiquetaDiaLargo,
  etiquetaMes,
  etiquetaPeriodo,
  filasComparadas,
  filtrarFilas,
  filtrarRoster,
  filtroInicial,
  filtroVacio,
  letraDia,
  mejorDia,
  mesesQueTocan,
  GRANULARIDADES,
  numeroDia,
  pasoDeEscala,
  periodoDesplazado,
  primerDiaDelMes,
  rosterDeEquipoYFilas,
  TIPO_TODOS,
  TIPOS_FACTURACION,
  totalAfirmable,
  totalesSoloDeDias,
  totalesUnificados,
  valorCelda,
  type FilaFacturacion,
  type FilaFacturacionDia,
  type FiltroFacturacion,
  type Granularidad,
  type MetricaFacturacion,
  type MiembroEquipo,
  type TipoFacturacion,
} from '@/lib/facturacion'
import { money, numero, type Moneda } from '@/lib/format'
import { cn } from '@/lib/utils'

/** Referencia estable: un `[]` nuevo en cada render invalidaría los useMemo. */
const SIN_FILAS: readonly FilaFacturacionDia[] = []

/**
 * Lo que se pinta en la malla. Dos monedas puras y una tercera vista, TOTAL,
 * donde cada celda ya trae las dos juntas convertidas a soles — Miguel,
 * 11/09/2026: «en el tablero quiero ver el total de cada analista por día».
 * TOTAL se formatea en soles porque ES soles: dólares convertidos a tasa real.
 */
const ROTULO_GRANULARIDAD: Record<Granularidad, string> = {
  mes: 'Mes',
  semana: 'Semana',
  dia: 'Día',
}
const ROTULO_ANTERIOR: Record<Granularidad, string> = {
  mes: 'Mes anterior',
  semana: 'Semana anterior',
  dia: 'Día anterior',
}
/** «del mes» / «de la semana» / «del día», para los rótulos que lo necesitan. */
const ROTULO_DEL_TRAMO: Record<Granularidad, string> = {
  mes: 'del mes',
  semana: 'de la semana',
  dia: 'del día',
}

/** Contra qué se compara, dicho en la unidad que se está mirando. */
const ROTULO_TRAMO_ANTERIOR: Record<Granularidad, string> = {
  mes: 'el mismo tramo del mes anterior',
  semana: 'los mismos días de la semana anterior',
  dia: 'el día anterior',
}
const ROTULO_SIGUIENTE: Record<Granularidad, string> = {
  mes: 'Mes siguiente',
  semana: 'Semana siguiente',
  dia: 'Día siguiente',
}

/** Tope de filas que PostgREST devuelve por consulta (supabase/config.toml). */
const LIMITE_FILAS_RPC = 1000

const VISTAS_MONEDA = ['TOTAL', 'PEN', 'USD'] as const
type VistaMoneda = (typeof VISTAS_MONEDA)[number]
const ROTULO_VISTA: Record<VistaMoneda, string> = {
  TOTAL: 'Todo S/',
  PEN: 'Soles',
  USD: 'Dólares',
}
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
  // El punto significa VACÍO. Solo lo merece el cero exacto: un negativo es una
  // cifra y tiene que verse, con su signo.
  if (valor === 0) return '·'
  if (metrica === 'contratos') return String(valor)
  const abs = Math.abs(valor)
  if (abs >= 1_000_000) return `${(valor / 1_000_000).toFixed(1)}M`
  // Por debajo de mil NO se redondea a «0k»: una venta de S/ 400 se leía como
  // cero. Se enseña la cifra entera, que además cabe. (Codex, 11/09/2026.)
  if (abs < 1_000) return String(Math.round(valor))
  return `${Math.round(valor / 1000)}k`
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
  tactil,
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
  /** El puntero primario es un dedo: blancos grandes, sin depender del hover. */
  tactil: boolean
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
            className={cn('shrink-0 accent-[var(--accent)]', tactil ? 'size-6' : 'size-4')}
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
  // EL DÍA DE LIMA, no el del reloj de la máquina. El negocio opera en Perú:
  // con un portátil en otro huso, el 1 de mes la pantalla abría el mes anterior
  // y dejaba el vigente inalcanzable (la flecha «siguiente» se deshabilita
  // contra este mismo valor). También movía el divisor del promedio y decidía
  // mal si el tipo de cambio se pide vigente o congelado.
  // (Auditoría de Codex, 11/09/2026.)
  const hoy = useMemo(() => fechaLima(ahora), [ahora])
  const mesDeHoy = useMemo(() => primerDiaDelMes(hoy), [hoy])
  const idPanel = useId()

  // El ANCLA es un día cualquiera dentro del periodo que se mira; la
  // granularidad decide si eso significa su mes, su semana o él solo. `mes` se
  // deriva del ancla porque la consulta al servidor sigue siendo mensual.
  // Abre SIEMPRE en Mes, también en tablet (Miguel, 14/09/2026: «por default el
  // módulo abra en la vista de MES»). Del 11 al 14/09 abría en Semana cuando la
  // pantalla era estrecha, porque en iPad vertical el mes no cabía (4 días de
  // 30); Miguel prefiere el mes entero y desplazarse de lado. La semana y el
  // día siguen a un toque.
  const esEstrecha = useEsEstrecha()
  const esTactil = useEsTactil()
  const [granularidad, setGranularidad] = useState<Granularidad>('mes')
  const [ancla, setAncla] = useState<string>(() => fechaLima(Date.now()))
  // DÍAS SUELTOS marcados a mano — Miguel, 11/09/2026: «marcar los días sueltos
  // que yo quiera», el 3, el 7 y el 12 aunque no vayan seguidos. Manda sobre el
  // tramo: si hay días marcados, la malla son ESOS y nada más.
  const [diasMarcados, setDiasMarcados] = useState<readonly string[]>([])
  const mes = primerDiaDelMes(ancla)
  const diasDelTramo = useMemo(
    () => diasDelPeriodo(granularidad, ancla),
    [granularidad, ancla],
  )
  // Los marcados se cruzan con el tramo: marcar el 3 y luego irte a otro mes no
  // debe arrastrar un día que ya no está en pantalla.
  const marcadosEnTramo = useMemo(
    () => diasMarcados.filter((d) => diasDelTramo.includes(d)),
    [diasMarcados, diasDelTramo],
  )
  const hayMarcados = marcadosEnTramo.length > 0
  const diasVisibles = diasDelTramo
  // El tramo anterior, aquí arriba: hace falta para saber qué meses pedir.
  const anclaPrevia = periodoDesplazado(granularidad, ancla, -1)
  const diasPrevios = useMemo(
    () => diasDelPeriodo(granularidad, anclaPrevia),
    [granularidad, anclaPrevia],
  )

  // No se navega al futuro: el tope es el periodo que contiene HOY en Lima.
  const sinPeriodoSiguiente = (diasVisibles[diasVisibles.length - 1] ?? ancla) >= hoy
  // Al cambiar de unidad el ancla se conserva, pero si el tramo nuevo cayera en
  // el futuro se trae a hoy: pasar de «mes» a «día» estando en un mes pasado
  // debe dejarte en un día de ESE mes, no en uno que aún no ha ocurrido.
  const alternarDia = (dia: string): void => {
    setDiasMarcados((ds) =>
      ds.includes(dia) ? ds.filter((d) => d !== dia) : [...ds, dia].sort(),
    )
  }
  const moverPeriodo = (delta: number): void => {
    setAncla((a) => periodoDesplazado(granularidad, a, delta))
  }
  const cambiarGranularidad = (g: Granularidad): void => {
    setDiasMarcados([])
    setGranularidad(g)
    setAncla((a) => {
      const ultimo = diasDelPeriodo(g, a).slice(-1)[0] ?? a
      return ultimo > hoy && primerDiaDelMes(a) === mesDeHoy ? hoy : a
    })
  }
  // Abre en TODO (Miguel, 11/09/2026: «el filtro principal debe ser TODOS, y
  // luego si quieren que seleccionen soles o dólares»). El dueño quiere ver el
  // dinero entero de un vistazo; separar monedas es la pregunta de después.
  const [vista, setVista] = useState<VistaMoneda>('TOTAL')
  const [metrica, setMetrica] = useState<MetricaFacturacion>('capital')
  // Abre en TODOS los tipos (Miguel, 14/09/2026: «con el filtro todos los tipos
  // para ver todo el capital»). Del 11 al 14/09 abría en capital nuevo, y una
  // renovación de US$ 10 000 del 10/09 «no salía»: estaba, pero detrás de la
  // perilla. Todo lo de la pantalla sigue a esta perilla: el titular, el
  // ranking y el total del día. (Decisión de Miguel, 11/09/2026: «lo que diga
  // la perilla», para que nunca haya dos cifras distintas a la vez.)
  const [tipo, setTipo] = useState<TipoFacturacion>(TIPO_TODOS)
  const [filtro, setFiltro] = useState<FiltroFacturacion>(filtroInicial)
  const [panelAbierto, setPanelAbierto] = useState(false)
  const [filtrosAbiertos, setFiltrosAbiertos] = useState(false)
  const [busqueda, setBusqueda] = useState('')
  const [cerrados, setCerrados] = useState<readonly string[]>([])
  const [seleccion, setSeleccion] = useState<{ analistaId: string; dia: string | null } | null>(null)

  // Corte del mes en curso: los días que aún no han pasado salen vacíos.
  const corte = mes === mesDeHoy ? hoy : formatDateLocal(new Date(9999, 0, 1))

  // El servidor solo se consulta cuando no hay fixture de prueba ni modo demo.
  // Las consultas cuelgan de `crmQueryKeys.raiz`: el cierre de sesión las borra.
  //
  // Se piden TODOS los meses que tocan el tramo visible y el de comparación. Con
  // mes/semana/día suelen ser uno o dos; un rango a medida puede cruzar varios.
  // Comparten clave de caché con la consulta mensual, así que moverse entre
  // tramos no vuelve a pedir lo que ya está.
  const mesesNecesarios = useMemo(
    () => mesesQueTocan([...diasVisibles, ...diasPrevios]),
    [diasVisibles, diasPrevios],
  )
  const consultas = useFacturacionDeMeses(fuente == null && !esDemo, mesesNecesarios)
  const filasDeMeses = useMemo(
    () => consultas.flatMap((c) => (c.data ?? []) as FilaFacturacionDia[]),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `consultas` es un array nuevo en cada render; su contenido cambia con los datos
    [consultas.map((c) => c.dataUpdatedAt).join('|')],
  )
  const consulta = {
    isPending: consultas.some((c) => c.isPending),
    isError: consultas.some((c) => c.isError),
    isFetching: consultas.some((c) => c.isFetching),
    refetch: () => consultas.forEach((c) => void c.refetch()),
    data: filasDeMeses.length > 0 || consultas.length > 0 ? filasDeMeses : undefined,
    descartadas: consultas.reduce((n, c) => n + ((c.data as { descartadas?: number } | undefined)?.descartadas ?? 0), 0),
    algunaCortada: consultas.some((c) => ((c.data ?? []) as unknown[]).length >= LIMITE_FILAS_RPC),
  }
  const demo = useMemo(
    () => (esDemo && fuente == null ? filasFacturacionDemo(mes, corte) : SIN_FILAS),
    [esDemo, fuente, mes, corte],
  )
  // El roster sale del mes ENTERO, sin filtrar: si saliera de lo ya filtrado,
  // elegir a alguien vaciaría la lista de la que se le acaba de elegir.
  // Lo del TRAMO VISIBLE, sin filtrar por equipo ni analista: si el roster
  // saliera de lo ya filtrado, elegir a alguien vaciaría la lista de la que se
  // le acaba de elegir. Se acota a los días visibles para que el selector no
  // ofrezca a quien solo vendió en el tramo de comparación.
  const diasVisiblesSet = useMemo(() => new Set(diasVisibles), [diasVisibles])
  const todos: readonly FilaFacturacionDia[] = useMemo(() => {
    const base = fuente ?? (esDemo ? demo : filasDeMeses)
    return base.filter((f) => diasVisiblesSet.has(f.dia))
  }, [fuente, esDemo, demo, filasDeMeses, diasVisiblesSet])

  // El organigrama que ya tiene el store (`crm.equipo_visible_fn`, con el mismo
  // alcance que la RLS: Gerencia ve la empresa entera; el supervisor, su
  // subárbol — el mismo recorte que hace la RPC). Se proyecta a la forma
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
  // Una semana puede empezar en el mes anterior. Esas filas ya se están
  // trayendo para la comparación, así que se añaden a la entrada de la malla:
  // `construirMallaDeDias` solo recoge lo que cae en los días visibles, de modo
  // que en la vista de mes no cambia nada.
  // `todos` ya trae todos los meses que toca el tramo, así que la malla recibe
  // lo filtrado tal cual: `construirMallaDeDias` se queda solo con los días
  // visibles. (Antes se concatenaba el mes anterior a mano y con `fuente` o en
  // demo eso DUPLICABA el dinero de la semana.)
  const filasDelTramo = filtradas
  const mallaPen = useMemo(
    () => construirMallaDeDias(filasDelTramo, diasVisibles, mes, 'PEN', tipo, rosterFiltrado),
    [filasDelTramo, diasVisibles, mes, tipo, rosterFiltrado],
  )
  const mallaUsd = useMemo(
    () => construirMallaDeDias(filasDelTramo, diasVisibles, mes, 'USD', tipo, rosterFiltrado),
    [filasDelTramo, diasVisibles, mes, tipo, rosterFiltrado],
  )

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

  // En TOTAL cada celda es soles + dólares × tasa. `combinarEnSoles` devuelve
  // null sin tasa y NO se degrada a solo-soles: una malla entera rotulada
  // «total» que esconda los dólares se lee celda a celda, y nadie comprueba la
  // letra pequeña 31 veces.
  const combinada = useMemo(
    () => (vista === 'TOTAL' ? combinarEnSoles(mallaPen, mallaUsd, tc?.promedio) : null),
    [vista, mallaPen, mallaUsd, tc],
  )
  // La pantalla ABRE en «Todo S/». Si el tipo de cambio no llega, abrir vacía
  // sería el peor arranque posible: se repliega a Soles, la perilla se mueve
  // sola —para no rotular «Todo» sobre una tabla que solo trae soles— y un
  // aviso dice por qué y ofrece reintentar. Mientras la tasa se consulta NO se
  // repliega: sería un salto de cifras a los dos segundos.
  const sinTasaParaTotal = vista === 'TOTAL' && tc === null
  const consultandoTasa = vista === 'TOTAL' && tc === undefined
  const vistaEfectiva: VistaMoneda = sinTasaParaTotal ? 'PEN' : vista
  const totalSinTasa = consultandoTasa
  // La moneda con la que se FORMATEA. En la vista TOTAL son soles, porque el
  // dólar ya viene convertido dentro de cada celda.
  const moneda: Moneda = vistaEfectiva === 'USD' ? 'USD' : 'PEN'
  const mallaBruta =
    vistaEfectiva === 'TOTAL'
      ? (combinada ?? mallaPen)
      : vistaEfectiva === 'PEN'
        ? mallaPen
        : mallaUsd
  // Los días marcados no esconden columnas —si no, no habría forma de marcar un
  // cuarto día—: la tabla se queda entera y lo que se recorta son los TOTALES.
  const malla = hayMarcados ? totalesSoloDeDias(mallaBruta, marcadosEnTramo) : mallaBruta

  // Con días marcados, el titular tiene que hablar de ESOS días: si siguiera
  // diciendo el mes entero habría dos cifras distintas en la misma pantalla.
  const totales = useMemo(
    () =>
      totalesUnificados(
        hayMarcados ? totalesSoloDeDias(mallaPen, marcadosEnTramo) : mallaPen,
        hayMarcados ? totalesSoloDeDias(mallaUsd, marcadosEnTramo) : mallaUsd,
        tc?.promedio,
      ),
    [mallaPen, mallaUsd, tc, hayMarcados, marcadosEnTramo],
  )
  const totalMes = totales.mes.capital
  // La fila aporta cuando HAY DÓLARES: es entonces cuando el equivalente en
  // soles dice algo que el total de arriba no dice. Sin un solo dólar el total
  // unificado sería idéntico al de soles, y un duplicado se come alto de
  // pantalla. Pedía las DOS monedas y eso escondía la fila justo en el caso en
  // que más sirve —un mes o un filtro con ventas SOLO en dólares—, donde la
  // vista en soles marca S/ 0 mientras hay dinero. (Codex, 11/09/2026.)
  const hayDolares = mallaUsd.total.contratos > 0
  // En la vista Total la malla YA trae las dos monedas: el pie combinado sería
  // una segunda copia de la misma cifra.
  const pieCombinado = hayDolares && vistaEfectiva !== 'TOTAL'

  // Mismo tramo del mes anterior — comparar un mes entero contra diez días mentiría.
  // EL TRAMO ANTERIOR, de la misma unidad y del mismo tamaño recorrido.
  //
  // Un mes a medias contra un mes entero mentía (lo cazó la auditoría). Con
  // semana y día la trampa es idéntica: comparar el lunes contra una semana
  // completa, o los tres días que llevas contra los siete de la anterior. Se
  // recorta el tramo anterior a TANTOS DÍAS COMO LLEVE el actual.
  const previo = useMemo(() => {
    const transcurridos = diasVisibles.filter((d) => d <= hoy).length
    // Tramo cerrado (todos sus días ya pasaron): se compara entero contra entero.
    const recorte = transcurridos === 0 || transcurridos >= diasVisibles.length
      ? diasPrevios
      : diasPrevios.slice(0, transcurridos)
    const base: readonly FilaFacturacionDia[] =
      fuente ??
      (esDemo
        ? filasFacturacionDemo(primerDiaDelMes(anclaPrevia), recorte[recorte.length - 1] ?? anclaPrevia)
        : filasDeMeses)
    return construirMallaDeDias(
      filtrarFilas(base, filtro),
      recorte,
      primerDiaDelMes(anclaPrevia),
      moneda,
      tipo,
    )
  }, [
    fuente, esDemo, filasDeMeses, anclaPrevia, diasPrevios,
    diasVisibles, hoy, moneda, tipo, filtro,
  ])

  const totalActual = valorCelda(malla.total, 'capital')
  const totalPrevio = valorCelda(previo.total, 'capital')
  // Con días sueltos elegidos a mano NO hay «tramo anterior» que signifique
  // nada: ¿los tres días previos? ¿los mismos días del mes pasado? Antes que
  // inventar una comparación, se dice que no la hay.
  const delta =
    hayMarcados || totalPrevio <= 0 ? null : ((totalActual - totalPrevio) / totalPrevio) * 100

  // EL TOTAL DE DINERO (Miguel, 11/09/2026: «necesito ver el total de dinero, con
  // el tipo de cambio»). Las dos monedas en una sola cifra, convirtiendo el USD
  // con el mismo motor y la misma tasa real que ya usa el pie de la tabla.
  //
  // Sin dólares en el tramo, el total ES el de soles y no se rotula conversión
  // ninguna. Sin tipo de cambio con dólares presentes NO se inventa un total:
  // se enseña la moneda que se está viendo y se dice que falta la tasa — la
  // misma regla fail-closed del pie.
  const puedeUnificar = hayDolares && totalAfirmable(totalMes)
  const totalFacturado = puedeUnificar
    ? money(totalMes.total ?? 0, 'PEN')
    : money(valorCelda(malla.total, 'capital'), moneda)
  const composicionTotal = !hayDolares
    ? ''
    : puedeUnificar && totalMes.tc != null
      ? `${money(totalMes.pen ?? 0, 'PEN')} + ${money(totalMes.usd ?? 0, 'USD')} al ${rotuloTipoCambio(totalMes.tc, tc?.fuente ?? '')}`
      : tc === undefined
        ? `solo ${ROTULO_VISTA[vistaEfectiva]} — consultando el tipo de cambio…`
        : `solo ${ROTULO_VISTA[vistaEfectiva]} — falta el tipo de cambio para sumar ${money(totalMes.usd ?? 0, 'USD')}`
  const comparacionTotal =
    delta == null
      ? hayMarcados
        ? 'Días elegidos a mano: sin comparación'
        : 'Sin cifra anterior con la que comparar'
      : `${delta >= 0 ? '+' : '−'}${Math.abs(delta).toFixed(1)} % vs. ${ROTULO_TRAMO_ANTERIOR[granularidad]}`


  // Un día que no elegiste no puede ganar el «mejor día», ni contar como día
  // hábil en el promedio de lo que sí elegiste.
  const mallaDeCifras = hayMarcados
    ? { ...malla, dias: marcadosEnTramo, totalPorDia: marcadosEnTramo.map((d) => malla.totalPorDia[malla.dias.indexOf(d)] ?? { capital: 0, contratos: 0 }) }
    : malla
  const mejor = mejorDia(mallaDeCifras, metrica)
  const habiles = hayMarcados
    ? marcadosEnTramo.filter((d) => !esDomingo(d)).length
    : diasHabilesHasta(malla, corte.startsWith('9999') ? (malla.dias.at(-1) ?? mes) : corte)
  const promedio = habiles > 0 ? valorCelda(malla.total, metrica) / habiles : 0

  const maximoAnalista = valorCelda(malla.maxAnalista, metrica)
  const maximoGrupo = valorCelda(malla.maxGrupo, metrica)
  const maximoDia = valorCelda(malla.maxDia, metrica)

  // «Todavía no sé» no es «no hubo ventas»: mientras la primera respuesta no
  // llega, la malla no se pinta vacía.
  const cargando = fuente == null && !esDemo && consulta.isPending
  // ¿Se puede AFIRMAR lo de arriba? La carga y el error protegían solo la malla:
  // los cuatro indicadores seguían calculándose sobre `data ?? []` y decían
  // «S/ 0» y «Todavía sin cierres» mientras la consulta estaba en vuelo o había
  // fallado. Una avería de red no puede parecer un mes sin ventas.
  // (Auditoría de Codex, 11/09/2026.)
  const cifrasFiables = !cargando && !consulta.isError
  const siFiable = (texto: string): string => (cifrasFiables ? texto : '—')
  const motivoSinCifras = cargando
    ? 'Cargando la facturación del mes…'
    : 'No se pudo cargar: la cifra no está disponible'

  // LO QUE NO SE PUDO LEER SE DICE. Antes una fila ilegible desaparecía y solo
  // quedaba en un registro técnico: el total salía más bajo y nadie lo sabía.
  // Y el límite de filas de PostgREST (1000) cortaría un mes grande por el
  // final, en silencio. Hoy no se llega, pero con el doble de equipo sí.
  // (Auditoría de Codex, 11/09/2026.)
  const descartadas = consulta.descartadas
  const puedeEstarCortado = consulta.algunaCortada
  const avisoIncompleto =
    descartadas > 0
      ? `${numero(descartadas)} fila${descartadas === 1 ? '' : 's'} del servidor no se pudo leer, así que estas cifras están incompletas.`
      : puedeEstarCortado
        ? 'El mes llegó al límite de filas del servidor: puede faltar capital del final del mes.'
        : ''

  const reintentar = (): void => {
    void consulta.refetch()
  }

  const comparando = filtro.analistas.length > 0
  const planas = useMemo(() => filasComparadas(malla), [malla])
  // PERSONAS distintas, no filas: desde que un analista puede salir en dos
  // equipos el mismo mes (cambió de equipo), contar filas diría «14 analistas»
  // donde hay 13.
  const cuantosAnalistas = new Set(
    malla.grupos.flatMap((g) => g.analistas.map((a) => a.id)),
  ).size
  const vacia = malla.grupos.length === 0

  const detalle = useMemo(
    () =>
      seleccion == null
        ? []
        : desgloseDeCelda(
            filtradas,
            seleccion.analistaId,
            seleccion.dia,
            tipo,
            vistaEfectiva === 'TOTAL' ? undefined : moneda,
          ),
    [seleccion, filtradas, tipo, vistaEfectiva, moneda],
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
    setDiasMarcados([])
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
    `${etiquetaMes(mes)} · ${ROTULO_VISTA[vistaEfectiva]} · ${ROTULO_TIPO[tipo]} · ${ROTULO_METRICA[metrica]} · ${numero(cuantosAnalistas)} analistas en ${numero(malla.grupos.length)} equipos`,
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
              aria-label={ROTULO_ANTERIOR[granularidad]}
              onClick={() => moverPeriodo(-1)}
            >
              <ChevronLeft aria-hidden />
            </Button>
            <span className="min-w-[15ch] text-center text-sm font-bold tabular-nums first-letter:uppercase">
              {etiquetaPeriodo(granularidad, ancla)}
            </span>
            <Button
              variant="outline"
              size="icon"
              aria-label={ROTULO_SIGUIENTE[granularidad]}
              disabled={sinPeriodoSiguiente}
              onClick={() => moverPeriodo(1)}
            >
              <ChevronRight aria-hidden />
            </Button>
          </div>

          <Interruptor
            etiqueta="Tramo que se mira"
            opciones={GRANULARIDADES}
            valor={granularidad}
            rotulo={ROTULO_GRANULARIDAD}
            onCambio={cambiarGranularidad}
          />
          <Interruptor
            etiqueta="Moneda — en Soles y Dólares nunca se suman; Total S/ convierte a la tasa del día"
            opciones={VISTAS_MONEDA}
            valor={vistaEfectiva}
            rotulo={ROTULO_VISTA}
            onCambio={setVista}
          />
          {/* En tablet la barra se partía en SIETE filas y se comía 200 px de
              alto. Lo secundario —qué se mide, tipo, equipo, analistas— se
              pliega detrás de un botón; el tramo y la moneda, que son lo que se
              toca a diario, se quedan siempre a la vista. */}
          {esEstrecha && (
            <Button
              variant="outline"
              size="sm"
              aria-expanded={filtrosAbiertos}
              onClick={() => setFiltrosAbiertos((v) => !v)}
            >
              <SlidersHorizontal aria-hidden />
              Filtros
              <ChevronDown
                aria-hidden
                className={cn('transition-transform', filtrosAbiertos && 'rotate-180')}
              />
            </Button>
          )}

          <div className={cn('contents', esEstrecha && !filtrosAbiertos && 'hidden')}>
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
          </div>

          {hayMarcados && (
            <Button
              variant="secondary"
              size="sm"
              aria-label="Quitar los días marcados"
              onClick={() => setDiasMarcados([])}
            >
              {marcadosEnTramo.length === 1
                ? '1 día marcado'
                : `${numero(marcadosEnTramo.length)} días marcados`}
              <X aria-hidden />
            </Button>
          )}
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
                              className={cn(
                                'shrink-0 accent-[var(--accent)]',
                                esTactil ? 'size-6' : 'size-3.5',
                              )}
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
            hayMarcados
              ? `${hayDolares ? 'Total facturado' : 'Facturado'} · ${marcadosEnTramo.length === 1 ? '1 día elegido' : `${numero(marcadosEnTramo.length)} días elegidos`}`
              : filtroVacio(filtro)
                ? `${hayDolares ? 'Total facturado' : 'Facturado'} · ${etiquetaPeriodo(granularidad, ancla)}`
                : `${hayDolares ? 'Total facturado' : 'Facturado'} por lo filtrado`
          }
          value={siFiable(totalFacturado)}
          icon={Receipt}
          color="var(--chart-1)"
          sub={
            cifrasFiables
              ? [composicionTotal, comparacionTotal].filter((x) => x !== '').join(' · ')
              : motivoSinCifras
          }
        />
        <KpiCard
          label={tipo === TIPO_TODOS ? 'Contratos cerrados' : `Contratos · ${ROTULO_TIPO[tipo]}`}
          value={siFiable(numero(valorCelda(malla.total, 'contratos')))}
          icon={Users}
          color="var(--chart-4)"
          sub={`En ${ROTULO_VISTA[vistaEfectiva]}, de ${numero(cuantosAnalistas)} analista${cuantosAnalistas === 1 ? '' : 's'} en ${numero(malla.grupos.length)} equipo${malla.grupos.length === 1 ? '' : 's'}`}
          delay={60}
        />
        <KpiCard
          label={
            hayMarcados
              ? 'Mejor día de los elegidos'
              : granularidad === 'dia'
                ? 'Ese día'
                : `Mejor día ${ROTULO_DEL_TRAMO[granularidad]}`
          }
          value={
            !cifrasFiables || mejor == null
              ? '—'
              : metrica === 'capital'
                ? money(mejor.valor, moneda)
                : `${numero(mejor.valor)} contratos`
          }
          icon={TrendingUp}
          color="var(--chart-2)"
          sub={
            !cifrasFiables
              ? motivoSinCifras
              : mejor == null
                ? 'Todavía sin cierres'
                : etiquetaDiaLargo(mejor.dia)
          }
          delay={120}
        />
        <KpiCard
          label="Promedio por día hábil"
          value={siFiable(
            metrica === 'capital'
              ? money(Math.round(promedio), moneda)
              : `${promedio.toFixed(1)} contratos`,
          )}
          icon={CalendarRange}
          color="var(--chart-3)"
          sub={`${numero(habiles)} días hábiles corridos — el domingo no cuenta`}
          delay={180}
        />
      </div>

      {avisoIncompleto !== '' && (
        <div
          role="status"
          className="flex items-start gap-2 rounded-lg border border-[var(--chart-5)]/40 bg-[var(--chart-5)]/10 px-4 py-2.5 text-[13px] font-medium"
        >
          <TriangleAlert aria-hidden className="mt-0.5 size-4 shrink-0 text-[var(--chart-5)]" />
          <span>
            {avisoIncompleto}{' '}
            <button
              type="button"
              onClick={reintentar}
              className="cursor-pointer font-bold underline underline-offset-2"
            >
              Reintentar
            </button>
          </span>
        </div>
      )}

      {/* La malla */}
      <Card className="overflow-hidden p-0">
        <SectionHead
          icon={Receipt}
          title={
            comparando
              ? `Comparando ${numero(filtro.analistas.length)} analista${filtro.analistas.length === 1 ? '' : 's'}, día a día`
              : granularidad === 'dia'
                ? 'Ese día, por equipo y por analista'
                : granularidad === 'semana'
                  ? 'Esa semana, día a día, por equipo y por analista'
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

        {/* VISIBLE. El aviso vivía en el <caption>, que es solo para lectores de
            pantalla: Miguel no encontraba dónde elegir los días porque nada se
            lo decía. Un botón que no se anuncia no existe. */}
        <p className="border-t border-border bg-muted/30 px-4 py-2 text-[12px] font-medium text-muted-foreground-strong">
          <MousePointerClick aria-hidden className="mr-1.5 inline size-3.5 align-[-2px]" />
          {hayMarcados
            ? `Estás viendo ${marcadosEnTramo.length === 1 ? '1 día elegido' : `${numero(marcadosEnTramo.length)} días elegidos`}. Pulsa otro número para añadirlo, o el mismo para quitarlo.`
            : 'Pulsa el número de un día —arriba de la tabla— para elegirlo. Puedes marcar varios, aunque no vayan seguidos.'}
        </p>

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
        ) : totalSinTasa ? (
          // FAIL-CLOSED. La vista Total promete las dos monedas en cada celda;
          // sin tipo de cambio no se pinta una malla de solo-soles bajo ese
          // rótulo. Se dice qué falta y se ofrece volver a intentarlo.
          <div className="flex flex-col items-center gap-3 border-t border-border px-6 py-14 text-center">
            <p className="text-sm font-semibold">No se puede mostrar el total combinado.</p>
            <p className="max-w-md text-[13px] text-muted-foreground">
              {tc === undefined
                ? 'Consultando el tipo de cambio del día…'
                : 'Falta el tipo de cambio para convertir los dólares. Mientras tanto puedes ver Soles y Dólares por separado, que no necesitan tasa.'}
            </p>
            {tc === null && (
              <Button variant="outline" size="sm" onClick={recargarTipoCambio}>
                <RotateCcw aria-hidden /> Reintentar el tipo de cambio
              </Button>
            )}
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
            <div className="ac-scroll overflow-auto border-t border-border focus-visible:outline-2 focus-visible:outline-offset-2" role="region" tabIndex={0} aria-label={`Facturación diaria de ${etiquetaMes(mes)} en ${ROTULO_VISTA[vistaEfectiva]}, ${ROTULO_TIPO[tipo]}`}>
              <table className="border-separate border-spacing-0 bg-card text-sm">
                <caption className="sr-only">
                  {ROTULO_METRICA[metrica]} por día · {etiquetaPeriodo(granularidad, ancla)} ·{' '}
                  {ROTULO_VISTA[vistaEfectiva]} ·{' '}
                  {ROTULO_TIPO[tipo]}.
                  Pulsa el número de un día para elegirlo, y otro, y otro: los totales pasan a
                  ser solo de esos días. Marca la casilla de dos o más analistas para verlos
                  solos y compararlos; activa una celda para ver los contratos de ese día.
                </caption>
                <thead>
                  <tr>
                    <th
                      scope="col"
                      className="sticky left-0 top-0 z-40 w-52 min-w-52 border-b border-r border-border bg-muted px-4 py-2 text-left text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
                    >
                      {comparando ? 'Analistas comparados' : 'Supervisor / analista'}
                    </th>
                    {malla.dias.map((dia) => {
                      const marcado = diasMarcados.includes(dia)
                      return (
                      <th
                        key={dia}
                        scope="col"
                        className={cn(
                          'sticky top-0 z-30 w-13 min-w-13 border-b border-r border-border/60 bg-muted p-0 text-center align-bottom',
                          esFinDeSemana(dia) && 'bg-muted-foreground/15',
                          dia === hoy && 'shadow-[inset_0_3px_0_var(--accent)]',
                          marcado && 'bg-primary text-primary-foreground',
                        )}
                      >
                        <button
                          type="button"
                          aria-pressed={marcado}
                          aria-label={`Marcar el ${etiquetaDiaLargo(dia)}`}
                          title={marcado ? 'Quitar este día' : 'Elegir este día'}
                          onClick={() => alternarDia(dia)}
                          className={cn(
                            'ac-dia-btn w-full cursor-pointer px-0 py-1.5',
                            'focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                            !marcado && 'hover:bg-accent/20',
                          )}
                        >
                          <span
                            className={cn(
                              'block text-[13px] font-bold leading-tight tabular-nums',
                              dia === hoy && !marcado && 'text-accent',
                            )}
                          >
                            {numeroDia(dia)}
                          </span>
                          <span
                            className={cn(
                              'block text-[9px] font-semibold uppercase',
                              marcado ? 'text-primary-foreground/80' : 'text-muted-foreground',
                            )}
                          >
                            {letraDia(dia)}
                          </span>
                          {/* La señal de que el día se puede elegir. Sin esto la
                              cabecera parecía un rótulo y nadie la pulsaba. Late
                              tres veces al entrar y se queda quieto: con 31
                              columnas, un latido infinito sería un tic. */}
                          <span
                            aria-hidden
                            className={cn(
                              'mx-auto mt-0.5 block size-1.5 rounded-full',
                              marcado ? 'bg-primary-foreground' : 'bg-accent',
                              !hayMarcados && 'ac-pista-dia',
                            )}
                          />
                        </button>
                      </th>
                      )
                    })}
                    <th
                      scope="col"
                      className="sticky right-0 top-0 z-40 w-32 min-w-32 border-b border-l border-border bg-muted px-3 py-2 text-right text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
                    >
                      {hayMarcados ? 'Total elegido' : `Total ${ROTULO_DEL_TRAMO[granularidad]}`}
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
                          tactil={esTactil}
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
                                  tactil={esTactil}
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
                  {pieCombinado && (
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
              : `${etiquetaMes(mes)} · ${ROTULO_VISTA[vistaEfectiva]} · ${ROTULO_TIPO[tipo]}`}
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
