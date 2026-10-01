// Pipeline (kanban) VIVO — F1b: lee y muta el store demo (useCRMData).
// Card clicable → drawer; menú "…" y drag & drop HTML5 para mover de etapa;
// alta por columna. Todo write-gated (rol directorio = solo lectura total).
// F1c: consciente del rol — trabaja SIEMPRE sobre useCRMData().ambito y, para
// supervisor/gerencia/directorio, ofrece pills de filtro por analista
// (+ bandeja "Por repartir" de parkeados). El analista solo ve lo suyo.
// 01/10/2026: las COLUMNAS ya no son las etapas. «Gestionado» (intentado, sin
// contacto) es una vista calculada de la etapa `nuevo`; qué columnas hay y cómo
// se reparten vive en lib/pipeline-columnas, no aquí ni en `ETAPAS`.
import { useEffect, useRef, useState, type CSSProperties, type DragEvent, useMemo } from 'react'
import { Users, TrendingUp, FileText, Target, Plus, MoreHorizontal, ExternalLink, Inbox, Zap } from 'lucide-react'
import { toast } from 'sonner'
import { Card } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import {
  DropdownMenu,
  DropdownItem,
  DropdownLabel,
  DropdownSeparator,
} from '@/components/ui/dropdown-menu'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { CAT_LABEL, ETAPA_INFO, TERMINALES, origenLabel, type EtapaActiva, type Lead } from '@/lib/tipos'
import {
  COLUMNAS_TABLERO,
  agruparPorColumna,
  destinosDeMovimiento,
  etapaAlSoltar,
  type ClaveColumna,
  type ColumnaTablero,
} from '@/lib/pipeline-columnas'
import { capitalPorMoneda, capitalPrincipal, duracionTexto, haceCortoTexto, indexarUltimoContacto } from '@/lib/inteligencia'
import { semaforoEstancamiento, type SemaforoEtapa } from '@/lib/estancamiento'
import { DialogCapitalPropuesta } from '@/components/app/capital-propuesta'
import { moneyK } from '@/lib/format'
import { can, puedeEscribir } from '@/lib/roles'
import { esFocoHuerfano } from '@/lib/foco'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { minutosLegibles } from '@/lib/sla-versionado'
import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
import { useCarteraPaginada, type CarteraPaginada } from '@/data/use-cartera-paginada'
import { useLeadsSinAsignar } from '@/data/crm-queries'
import { ChipPotencial } from '@/components/app/potencial-chip'
import { potencialCarta } from '@/components/app/potencial-efectos'
import { usePotencialLeads } from '@/data/potencial-queries'
import type { PotencialLead } from '@/lib/potencial'

// "hace X" compacto a partir de DÍAS ya calculados (el reloj lo decide
// `semaforoEstancamiento`, para que color y número no puedan divergir).
// 'ayer' y las semanas son wording propio de esta pantalla; lo sub-diario
// delega en la escala única — antes 'hoy' tapaba las primeras 24 h enteras.
function haceDias(dias: number): string {
  const d = Math.floor(dias)
  if (d <= 0) return haceCortoTexto(dias)
  if (d === 1) return 'ayer'
  if (d < 7) return `hace ${d} d`
  return `hace ${Math.floor(d / 7)} sem`
}

// Ventana (ms) durante la que un click se atribuye al arrastre recién soltado y
// no al analista. Solo tiene que cubrir el click sintético que el navegador
// dispara pegado al drop; cualquier click humano llega muchísimo después.
const MS_CLICK_FANTASMA = 60

// Cuánto se espera (ms) a que reaparezca en otra columna la tarjeta que tenía el
// foco. «Nuevo» y «Gestionado» son listas distintas y sus respuestas no llegan
// juntas: la tarjeta puede salir de una antes de entrar en la otra. Pasado el
// plazo se entiende que el lead salió del tablero y el foco ya no se le lleva.
const MS_ESPERA_GEMELA = 5_000

/**
 * Una columna no crece al ritmo de la cartera. El analista trabaja una página
 * corta dentro de la bandeja de esa etapa; los totales del encabezado siguen
 * siendo el panorama completo y los filtros no se pierden al avanzar.
 */
const LEADS_POR_PAGINA = 20
/** En sesión real las columnas no parten de ninguna foto local. */
const SIN_FOTO: readonly Lead[] = []
const PAGINA_INICIAL_POR_COLUMNA = Object.fromEntries(
  COLUMNAS_TABLERO.map((c) => [c.k, 0]),
) as Record<ClaveColumna, number>
const COLUMNA_POR_CLAVE = Object.fromEntries(
  COLUMNAS_TABLERO.map((c) => [c.k, c]),
) as Record<ClaveColumna, ColumnaTablero>

/**
 * Lo que una columna le pide al servidor: su etapa, el analista del filtro y,
 * solo en las dos mitades de `nuevo`, el recorte por gestión. Sale de la
 * definición de la columna para que pantalla y servidor no puedan divergir.
 */
function filtrosDeColumna(k: ClaveColumna, vendedorId: string) {
  const { etapa, gestion } = COLUMNA_POR_CLAVE[k]
  return { etapa, vendedorId, integrada: true, ...(gestion ? { gestion } : {}) }
}

/** Explicación fija de la columna calculada: nadie arrastra leads hasta ella. */
const AYUDA_GESTIONADO = 'Se llena sola al registrar un intento de contacto.'
/**
 * En la bandeja «Por repartir» solo hay leads SIN analista y la gestión exige
 * titular: ahí la columna no puede llenarse, y prometerlo sería mentir.
 */
const AYUDA_SIN_ANALISTA = 'Los leads sin analista se muestran en Nuevo.'

/** Clave ESTABLE de foco de la tarjeta de un lead: la misma en cualquier columna. */
const claveFocoDe = (leadId: string) => `lead-${leadId}`

// Métrica de la fila «Agregar lead». La comparte el hueco de la columna que no
// admite altas, para que los cinco carriles terminen a la misma altura.
const FILA_ALTA = 'mt-1.5 flex w-full shrink-0 items-center justify-center gap-1.5 rounded-lg py-2 text-[11px] font-semibold'

// Pills del filtro por analista (sin verde: activo = azul primario; bandeja = ámbar)
const PILL_BASE =
  'flex cursor-pointer items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-semibold transition-colors'
const pillCls = (activo: boolean) =>
  `${PILL_BASE} ${
    activo
      ? 'border-primary/60 bg-primary/10 text-primary'
      : 'border-border bg-card text-muted-foreground hover:bg-muted hover:text-foreground'
  }`

interface LeadCardProps {
  l: Lead
  nombreVendedor: string | null
  /** Semáforo por ETAPA — lo calcula la pantalla, que es quien tiene el índice
   *  de contacto (construirlo por card sería O(actividades) × O(leads)). */
  semaforo: SemaforoEtapa
  /**
   * Cómo se nombra la etapa en el aviso del plazo. El reloj es el de la etapa
   * GUARDADA: una tarjeta de «Gestionado» sigue midiendo su tiempo en `nuevo`,
   * y decir «en Gestionado» fecharía la espera desde un intento que no la inicia.
   */
  rotuloEtapa: string
  escribe: boolean
  arrastrando: boolean
  /** Marca de potencial del lead (undefined = sin dato o función apagada). */
  potencial: PotencialLead | undefined
  onAbrir: () => void
  onMover: (etapa: EtapaActiva) => void
  onDragStart: (e: DragEvent<HTMLDivElement>) => void
  onDragEnd: () => void
}

function LeadCard({ l, nombreVendedor, semaforo, rotuloEtapa, escribe, arrastrando, potencial, onAbrir, onMover, onDragStart, onDragEnd }: LeadCardProps) {
  // ac-lift (will-change) crea un stacking context por card: mientras el menú
  // está abierto hay que elevar ESTA card o el panel queda bajo la siguiente.
  const [menuAbierto, setMenuAbierto] = useState(false)
  return (
    <Card
      className={`ac-lift cursor-pointer p-3 ${arrastrando ? 'opacity-40' : ''} ${menuAbierto ? 'relative z-30' : ''}`}
      role="button"
      tabIndex={0}
      // Clave ESTABLE de foco: al cambiar de columna la tarjeta es otro nodo.
      // La ficha (Sheet) y el propio tablero la usan para devolver el foco a
      // «la misma tarjeta» aunque el nodo desde el que se abrió ya no exista.
      data-foco-clave={claveFocoDe(l.id)}
      onClick={onAbrir}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onAbrir()
        }
      }}
      draggable={escribe || undefined}
      onDragStart={escribe ? onDragStart : undefined}
      onDragEnd={escribe ? onDragEnd : undefined}
      {...potencialCarta(potencial, arrastrando || menuAbierto)}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="min-w-0 truncate text-sm font-semibold text-foreground">{l.nombre_completo}</p>
        {l.monto_estimado != null && (
          <p className="shrink-0 text-sm font-extrabold tabular-nums text-primary">{moneyK(l.monto_estimado, l.moneda)}</p>
        )}
      </div>
      <div className="mt-2 flex items-center gap-1.5">
        {l.categoria_interes ? (
          <Badge color="var(--chart-4)" className="text-[10px]">Inversión · {CAT_LABEL[l.categoria_interes]}</Badge>
        ) : (
          <Badge color="var(--muted-foreground)" className="text-[10px]">{origenLabel(l.origen)}</Badge>
        )}
        <ChipPotencial marca={potencial} pequeno />
      </div>
      <div className="mt-2.5 flex items-center justify-between border-t border-border pt-2">
        {l.vendedor_id == null ? (
          <Badge color="var(--warning)" className="text-[10px]">sin asignar</Badge>
        ) : nombreVendedor ? (
          <span className="flex items-center gap-1.5">
            <Avatar nombre={nombreVendedor} className="size-5 text-[8px]" />
            <span className="text-[11px] text-muted-foreground">{nombreVendedor.split(' ')[0]}</span>
          </span>
        ) : (
          <span className="text-[11px] text-muted-foreground">Analista asignado</span>
        )}
        <span className="flex items-center gap-1">
          {/* El punto y el número salen del MISMO episodio de etapa sellado en
              BD. Sin fotografía SLA no se inventa color con la política actual. */}
          {semaforo.color && (
            <span
              aria-hidden
              className="size-1.5 shrink-0 rounded-full"
              style={{ backgroundColor: semaforo.color }}
            />
          )}
          <span
            className="text-[11px] tabular-nums"
            style={{ color: semaforo.estancado ? semaforo.color ?? undefined : undefined }}
            title={
              semaforo.objetivoMinutos == null
                ? `Sin fotografía SLA disponible · referencia operativa ${haceDias(semaforo.dias)}`
                // Duración desnuda LARGA: «Lleva ayer en Nuevo» / «Lleva hace
                // 40 min en…» era español roto, y la corta decía «Lleva recién
                // en Nuevo» (Codex). El chip de al lado sí lleva el «hace».
                : `Lleva ${duracionTexto(semaforo.dias)} en ${rotuloEtapa} · plazo sellado ${minutosLegibles(semaforo.objetivoMinutos)} · SLA v${semaforo.politicaVersion ?? '—'}${semaforo.aproximado ? ' (aproximado)' : ''}`
            }
          >
            {haceDias(semaforo.dias)}
          </span>
          {escribe && (
            // stopPropagation (click y keydown): el menú vive dentro de una card
            // clicable e interactiva por teclado — sin esto, Enter/Space sobre el
            // trigger o un ítem abriría la ficha en vez de operar el menú.
            // role=presentation: solo intercepta burbujeo, no es un control.
            // El escudo de teclado frena SOLO Enter y Espacio (las dos teclas
            // que la card escucha). Frenarlas todas dejaba sin flechas, Inicio/
            // Fin y Escape al propio menú, que los escucha en `document`: desde
            // la raíz de React el evento ya no subía.
            <div
              role="presentation"
              onClick={(e) => e.stopPropagation()}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') e.stopPropagation()
              }}
            >
              <DropdownMenu
                onOpenChange={setMenuAbierto}
                trigger={
                  <button
                    type="button"
                    aria-label={`Acciones de ${l.nombre_completo}`}
                    className="grid size-6 cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                  >
                    <MoreHorizontal className="size-3.5" />
                  </button>
                }
              >
                <DropdownItem onSelect={onAbrir}>
                  <ExternalLink /> Abrir ficha
                </DropdownItem>
                <DropdownSeparator />
                <DropdownLabel>Mover a</DropdownLabel>
                {/* Solo destinos reales: ni la etapa en la que ya está ni una
                    columna calculada («Gestionado» no se elige, se llena sola).
                    El grupo da a las opciones el nombre que el rótulo de arriba
                    solo da a la vista: «Mover a». */}
                <div role="group" aria-label="Mover a">
                  {destinosDeMovimiento(l).map((c) => (
                    <DropdownItem key={c.k} onSelect={() => onMover(c.etapa)}>
                      <span className="size-2 shrink-0 rounded-full" style={{ background: c.color }} />
                      {c.label}
                    </DropdownItem>
                  ))}
                </div>
              </DropdownMenu>
            </div>
          )}
        </span>
      </div>
    </Card>
  )
}

export function Pipeline() {
  const { yo } = useAuth()
  const escribe = puedeEscribir(yo?.rol)
  const { ambito, cambiarEtapa, actividadesDelAmbito } = useCRMData()
  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividadesDelAmbito)
  // Índice de CONTACTO REAL (no de cualquier actividad): la `reasignacion` que
  // el sistema escribe al repartir apagaría el semáforo de un lead que nadie
  // ha llamado. Se construye UNA vez por render, no una por card.
  // Fase 3 «sin topes»: en sesión real el arranque ya no baja el registro de
  // actividades; el color y los días de cada card salen de la fotografía SLA
  // (`estado_sla_leads_v2_fn`) y este índice —solo optimistas locales— es el
  // respaldo del «hace X» cuando un lead aún no tiene fotografía. En demo
  // sigue siendo el timeline del fixture.
  const indiceContacto = useMemo(() => indexarUltimoContacto(actividadesDelAmbito), [actividadesDelAmbito])
  const { abrirLead, abrirNuevoLead } = usePanelesActions()
  const ahora = useAhora() // reloj vivo: "hace X" de las cards se refresca solo
  // F1c: el tablero SIEMPRE trabaja sobre el ámbito del rol, nunca el global.
  const leads = ambito.leads
  // Las páginas del servidor traen el id del analista; su nombre se resuelve
  // con el equipo visible, igual que en la lista de Leads.
  const nombrePorId = useMemo(
    () => new Map(ambito.vendedores.map((m) => [m.perfil_id, m.nombre_completo])),
    [ambito.vendedores],
  )

  // ── Filtro por analista (pills) — solo roles con la capacidad y >1 analista ──
  const [fVend, setFVend] = useState<string>('todos') // 'todos' | 'por_repartir' | perfil_id
  const [paginaPorColumna, setPaginaPorColumna] = useState<Record<ClaveColumna, number>>(
    PAGINA_INICIAL_POR_COLUMNA,
  )
  const mostrarFiltro = can(yo?.rol, 'filtrarPorVendedor') && ambito.vendedores.length > 1
  // Fase 4d «sin topes»: en sesión real cada columna es su propia lista
  // servida por `cartera_filtrada_fn` (etapa + analista, cursor keyset y
  // «Cargar más»), y la bandeja «por repartir» viene del servidor; la demo
  // sigue paginando su foto local en el navegador.
  const sesionReal = yo != null && !yo.demo
  const bandejaSinAsignar = useLeadsSinAsignar(sesionReal)
  // Bandeja "por repartir": sin analista asignado y aún en etapa de trabajo.
  const porRepartir = (sesionReal ? (bandejaSinAsignar.data ?? []) : leads).filter(
    (l) => l.vendedor_id == null && !['convertido', 'descartado'].includes(l.etapa),
  )
  // El filtro degrada solo a "Todos" cuando deja de tener sentido (analista
  // fuera del ámbito, o bandeja vacía tras repartir el último parkeado).
  const filtro = !mostrarFiltro
    ? 'todos'
    : fVend === 'por_repartir'
      ? porRepartir.length > 0
        ? fVend
        : 'todos'
      : fVend !== 'todos' && !ambito.vendedores.some((v) => v.perfil_id === fVend)
        ? 'todos'
        : fVend
  // Una lista por columna (orden fijo de hooks): el filtro de analista viaja al
  // servidor con cada etapa. En demo estos hooks no tocan la red ni la foto.
  // «Nuevo» y «Gestionado» piden la MISMA etapa y solo difieren en la gestión:
  // son dos listas, cada una con su caché, su cursor y su total.
  const vendedorFiltro = filtro === 'todos' ? 'todos' : filtro === 'por_repartir' ? 'sin_asignar' : filtro
  const columnaNuevo = useCarteraPaginada(SIN_FOTO, filtrosDeColumna('nuevo', vendedorFiltro))
  const columnaGestionado = useCarteraPaginada(SIN_FOTO, filtrosDeColumna('gestionado', vendedorFiltro))
  const columnaContactado = useCarteraPaginada(SIN_FOTO, filtrosDeColumna('contactado', vendedorFiltro))
  const columnaReunion = useCarteraPaginada(SIN_FOTO, filtrosDeColumna('reunion_agendada', vendedorFiltro))
  const columnaPropuesta = useCarteraPaginada(SIN_FOTO, filtrosDeColumna('propuesta_enviada', vendedorFiltro))
  const columnasServidor: Record<ClaveColumna, CarteraPaginada> = {
    nuevo: columnaNuevo, gestionado: columnaGestionado, contactado: columnaContactado,
    reunion_agendada: columnaReunion, propuesta_enviada: columnaPropuesta,
  }
  // Fase 4e: el store conoce lo que el tablero muestra (los verbos de
  // escritura resuelven el lead por id sin foto inicial).
  const { conocerLeads } = useCRMData()
  const leadsEnTablero = useMemo(
    () => (sesionReal
      ? [...columnaNuevo.leads, ...columnaGestionado.leads, ...columnaContactado.leads, ...columnaReunion.leads, ...columnaPropuesta.leads]
      : []),
    [sesionReal, columnaNuevo.leads, columnaGestionado.leads, columnaContactado.leads, columnaReunion.leads, columnaPropuesta.leads],
  )
  useEffect(() => { conocerLeads(leadsEnTablero) }, [conocerLeads, leadsEnTablero])
  // Potencial del lead: una lectura por las tarjetas del tablero (en demo, por
  // el ámbito entero: ahí las columnas paginan una foto local).
  const potencial = usePotencialLeads(useMemo(
    () => (sesionReal ? leadsEnTablero : ambito.leads).map((l) => l.id),
    [sesionReal, leadsEnTablero, ambito.leads],
  ))
  const buscarEnTablero = (id: string): Lead | undefined =>
    (sesionReal ? leadsEnTablero : ambito.leads).find((x) => x.id === id)
  // Solo las COLUMNAS se filtran; los stats y terminales resumen el ámbito completo.
  const enTablero =
    filtro === 'todos'
      ? leads
      : filtro === 'por_repartir'
        ? leads.filter((l) => l.vendedor_id == null)
        : leads.filter((l) => l.vendedor_id === filtro)
  // Modo demo: el reparto que en real hace el servidor (`p_gestion`) lo calcula
  // aquí la función pura con el timeline del fixture. En real no se toca: el
  // navegador no tiene las gestiones de cada lead ni debe adivinarlas.
  const columnasDemo = sesionReal ? null : agruparPorColumna(enTablero, actividadesDelAmbito)
  /** Los leads de una columna: lo que sirvió el servidor o, en demo, el reparto local. */
  const leadsDeColumna = (k: ClaveColumna): Lead[] => (columnasDemo ? columnasDemo[k] : columnasServidor[k].leads)
  /** Columna en la que el tablero pinta AHORA ese lead (null: ya no está en ninguna). */
  const columnaActualDe = (id: string): ClaveColumna | null =>
    COLUMNAS_TABLERO.find((c) => leadsDeColumna(c.k).some((l) => l.id === id))?.k ?? null

  // Drag & drop HTML5 (solo con permiso de escritura)
  const [dragId, setDragId] = useState<string | null>(null)
  const [colDestino, setColDestino] = useState<ClaveColumna | null>(null)
  const huboDrag = useRef(false) // evita que el click fantasma tras soltar abra la ficha
  const timerClickFantasma = useRef<number | null>(null)
  /** Columna de la que salió la tarjeta en vuelo (para saber si se movió sola). */
  const dragOrigen = useRef<ClaveColumna | null>(null)

  // Limpia el timeout del click fantasma si el tablero se desmonta con un drag en vuelo.
  useEffect(() => () => {
    if (timerClickFantasma.current != null) clearTimeout(timerClickFantasma.current)
  }, [])

  /**
   * Fin del arrastre, en UN solo sitio y con salida garantizada.
   * Se invoca desde el DROP *además* de desde `onDragEnd` porque `onDragEnd` no
   * es de fiar: al soltar, el lead cambia de etapa y React DESMONTA la card de
   * la columna vieja, así que su handler no llega a correr — y ese es el caso
   * NORMAL, no el raro. Confiar solo en él dejaba `huboDrag` en true para
   * siempre (el tablero no volvía a abrir ninguna ficha con un click) y `dragId`
   * pegado, con una card fantasma en opacity-40.
   *
   * Tampoco basta con el DROP: una columna que no recibe la tarjeta no cancela
   * `dragover` y el navegador no dispara `drop` sobre ella. Las dos salidas que
   * no dependen de ningún nodo están justo debajo (`dragOrigen` y el gesto nuevo).
   */
  const terminarArrastre = () => {
    setDragId(null)
    setColDestino(null)
    dragOrigen.current = null
    if (timerClickFantasma.current != null) clearTimeout(timerClickFantasma.current)
    // El click sintético que sigue a soltar cae DENTRO de la ventana → se
    // ignora (que es para lo que existe `huboDrag`); pasada la ventana el guard
    // se levanta pase lo que pase, sin depender de un `dragEnd` que quizá no
    // llegue nunca.
    timerClickFantasma.current = window.setTimeout(() => {
      huboDrag.current = false
      timerClickFantasma.current = null
    }, MS_CLICK_FANTASMA)
  }

  // SALIDA 1 — la tarjeta en vuelo ya no está donde empezó. Pasa sola: tras un
  // intento (o una relectura) salta de «Nuevo» a «Gestionado», o desaparece
  // porque otro la reasignó. Su nodo se desmonta, el `dragEnd` no llega nunca y,
  // si se suelta donde no se recibe, tampoco hay `drop`. El arrastre de ESE nodo
  // ya no puede terminar bien: se cierra aquí, sin esperar a nadie.
  const columnaDelArrastrado = dragId == null ? null : columnaActualDe(dragId)
  useEffect(() => {
    if (dragId != null && dragOrigen.current != null && columnaDelArrastrado !== dragOrigen.current) terminarArrastre()
  })

  // SALIDA 2 — el siguiente gesto del usuario. Mientras dura un arrastre nativo
  // el navegador no entrega `pointerdown` ni teclas a la página: si llega uno,
  // el arrastre terminó aunque nadie avisara. Se limpia AL INSTANTE, también
  // dentro de la ventana del clic fantasma: ese clic es el que llega SIN que
  // nadie haya vuelto a pulsar; uno que trae su `pointerdown` es un gesto nuevo.
  useEffect(() => {
    const cerrar = () => {
      // Sin arrastre abierto ni clic fantasma pendiente no hay nada que cerrar.
      if (!huboDrag.current) return
      if (timerClickFantasma.current != null) clearTimeout(timerClickFantasma.current)
      timerClickFantasma.current = null
      huboDrag.current = false
      dragOrigen.current = null
      setDragId(null)
      setColDestino(null)
    }
    // En captura: corre antes que los manejadores de la tarjeta, así el mismo
    // clic o el mismo Enter que destraba el tablero ya abre la ficha.
    document.addEventListener('pointerdown', cerrar, true)
    document.addEventListener('keydown', cerrar, true)
    return () => {
      document.removeEventListener('pointerdown', cerrar, true)
      document.removeEventListener('keydown', cerrar, true)
    }
  }, [])

  const abrir = (id: string) => {
    if (huboDrag.current) return
    abrirLead(id)
  }

  // ── Foco ────────────────────────────────────────────────────────────────────
  // Una tarjeta que cambia de columna es OTRO nodo. Si tenía el foco, el
  // navegador lo deja en <body> y el siguiente Tab reinicia la página. Se
  // recuerda qué tarjeta lo tiene —su clave y su NODO— y, si ese nodo
  // desaparece, el foco se le devuelve a su gemela.
  const tarjetaConFoco = useRef<{ clave: string; nodo: Element; perdidaEn: number | null } | null>(null)
  useEffect(() => {
    const alEnfocar = (e: FocusEvent) => {
      const nodo = e.target instanceof Element ? e.target.closest('[data-foco-clave]') : null
      const clave = nodo?.getAttribute('data-foco-clave')
      tarjetaConFoco.current = nodo && clave ? { clave, nodo, perdidaEn: null } : null
    }
    // Un `focusout` SIN destino son dos casos que el evento no distingue: el
    // usuario se fue (clic en un hueco) o el nodo se está quitando de la página
    // — Chromium avisa así, con el nodo todavía conectado (medido el 01/10);
    // jsdom no avisa, y otros motores pueden no hacerlo: por eso el rescate no
    // depende de este evento. Se mira al terminar lo que esté corriendo (si es
    // un commit de React, para entonces el nodo ya no está): si la tarjeta sigue
    // en la página y el foco ya no está en ella ni en sus botones, el usuario se
    // fue y no hay nada que rescatar. Si lo conserva es que solo cambió de
    // ventana. Con destino, el `focusin` siguiente decide.
    const alDesenfocar = (e: FocusEvent) => {
      const marca = tarjetaConFoco.current
      if (e.relatedTarget != null || marca == null) return
      queueMicrotask(() => {
        if (tarjetaConFoco.current === marca && marca.nodo.isConnected && !marca.nodo.contains(document.activeElement)) {
          tarjetaConFoco.current = null
        }
      })
    }
    document.addEventListener('focusin', alEnfocar)
    document.addEventListener('focusout', alDesenfocar)
    return () => {
      document.removeEventListener('focusin', alEnfocar)
      document.removeEventListener('focusout', alDesenfocar)
    }
  }, [])
  const tablero = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const marca = tarjetaConFoco.current
    // Mientras su nodo siga en la página no hay nada que rescatar.
    if (marca == null || marca.nodo.isConnected) return
    // Es un RESCATE, no un robo: si el foco ya está en otro control, el usuario
    // siguió su camino.
    if (!esFocoHuerfano()) {
      tarjetaConFoco.current = null
      return
    }
    const ahora = Date.now()
    marca.perdidaEn ??= ahora
    // La tarjeta puede salir de una lista antes de entrar en la otra: se la
    // espera un momento. Pasado el plazo, el lead salió del tablero (cerrado,
    // reasignado) y no hay a quién enfocar.
    if (ahora - marca.perdidaEn > MS_ESPERA_GEMELA) {
      tarjetaConFoco.current = null
      return
    }
    // Nunca con un diálogo abierto: la ficha devuelve el foco ella misma al
    // cerrarse, por la misma clave (ver `components/ui/sheet.tsx`).
    if (document.querySelector('[role="dialog"]')) return
    const gemela = [...(tablero.current?.querySelectorAll<HTMLElement>('[data-foco-clave]') ?? [])]
      .find((nodo) => nodo.getAttribute('data-foco-clave') === marca.clave)
    gemela?.focus()
  })

  // «Reintentar» se desmonta cuando su columna se recupera. Si el foco estaba
  // en él, pasa a la columna (misma idea que `AvisoDegradacion`).
  const nodosDeColumna = useRef(new Map<ClaveColumna, HTMLDivElement>())
  const reintentoConFoco = useRef<ClaveColumna | null>(null)
  useEffect(() => {
    const k = reintentoConFoco.current
    // Mientras la columna siga caída el botón sigue montado: no hay nada que rescatar.
    if (k == null || columnasServidor[k].error != null) return
    reintentoConFoco.current = null
    if (esFocoHuerfano()) nodosDeColumna.current.get(k)?.focus()
  })

  // Pasar a "Entrevista realizada" (clave `propuesta_enviada`) es el ÚNICO
  // momento en que el capital es un
  // HECHO y no una corazonada del primer contacto — y de esa cifra viven el
  // capital en proceso y las metas del mes. Se pregunta ahí, con un campo ya
  // precargado: Enter confirma tal cual.
  const [pidiendoCapital, setPidiendoCapital] = useState<Lead | null>(null)

  const mover = (id: string, etapa: EtapaActiva) => {
    if (etapa === 'propuesta_enviada') {
      const l = buscarEnTablero(id)
      if (l && l.etapa !== 'propuesta_enviada') {
        setPidiendoCapital(l)
        return
      }
    }
    const r = cambiarEtapa(id, etapa)
    if (!r.ok && r.error) toast.error(r.error)
  }

  const alDragStart = (id: string, origen: ClaveColumna) => (e: DragEvent<HTMLDivElement>) => {
    e.dataTransfer.setData('text/plain', id)
    e.dataTransfer.effectAllowed = 'move'
    huboDrag.current = true
    dragOrigen.current = origen
    setDragId(id)
  }

  // ¿Esta columna recibe la tarjeta que se está arrastrando? No, si es una
  // columna calculada («Gestionado») o si el lead ya está en su etapa: «Nuevo» y
  // «Gestionado» son la misma etapa, así que entre ellas no hay nada que mover.
  // Quien no la recibe ni se resalta ni acepta el soltar. Si el tablero ya no
  // tiene el lead a la vista (una lista se refrescó en pleno arrastre), decide
  // el store, como siempre.
  const arrastrado = dragId == null ? undefined : buscarEnTablero(dragId)
  const aceptaSoltar = (col: ColumnaTablero): boolean =>
    escribe && dragId != null && col.esDestino
      && (arrastrado == null || etapaAlSoltar(arrastrado, col) !== null)

  const alDrop = (col: ColumnaTablero) => (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    // Cerrar el arrastre ANTES de mover: `mover` cambia la etapa y con ella
    // desmonta la card de origen (y su `onDragEnd`) en el mismo latido.
    terminarArrastre()
    if (!id) return
    // La regla se vuelve a aplicar aquí, no solo en el `dragOver`: es la que
    // garantiza que soltar donde no toca NO llama al servidor.
    const lead = buscarEnTablero(id)
    const etapa = lead ? etapaAlSoltar(lead, col) : col.esDestino ? col.etapa : null
    if (etapa) mover(id, etapa)
  }

  // ── KPIs del tablero — F1: servidos por resumen_cartera_fn (o espejo demo
  // vivo); la pantalla ya no cuenta filas. Convención (misma que Hoy y Equipo):
  // solo abiertos CON analista — los parkeados van aparte en la pill "Por
  // repartir". La cifra grande del capital es la moneda que DE VERDAD tiene
  // volumen (capitalPrincipal) — PEN y USD JAMÁS se suman ni se convierten.
  // Sin payload (cargando o RPC caída): «—», jamás una cifra inventada.
  const resumenOp = useResumenCarteraOperativo(leads, actividadesDelAmbito)
  const resumen = resumenOp.resumen
  const capital = resumen
    ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd)
    : null
  const propuestas = resumen?.embudo.find((p) => p.etapa === 'propuesta_enviada')?.n
  const stats: StatChipData[] = [
    { icon: Users, label: 'Leads abiertos con analista', value: resumen ? String(resumen.totales.asignados) : '—', tone: 'primary' },
    {
      icon: TrendingUp,
      label: 'Capital en proceso',
      value: capital?.valor ?? '—',
      tone: 'accent',
      // exactOptionalPropertyTypes: sin capital el sub se OMITE, no viaja undefined.
      ...(capital ? { sub: capital.sub } : {}),
    },
    { icon: FileText, label: 'Entrevistas realizadas', value: propuestas != null ? String(propuestas) : '—' },
    { icon: Target, label: 'Cierres de leads del mes', value: resumen ? String(resumen.totales.convertidos) : '—', tone: 'primary', sub: 'Mes calendario actual' },
  ]

  return (
    // Tope de 1 500 px y no los 1 440 de las demás pantallas: cinco columnas de
    // 290 px con sus cuatro huecos de 12 miden 1 498. Con 1 440, en un monitor
    // ancho quedaba un scroll de 58 px solo para terminar de ver la última.
    <div className="mx-auto flex min-h-0 max-w-[1500px] flex-col gap-5 ac-rise md:h-full">
      <StatStrip stats={stats} />
      <p className="shrink-0 text-xs text-muted-foreground">
        {ambito.esGlobal ? 'Indicadores de toda la empresa.' : 'Indicadores de tu ámbito.'} Los filtros sólo cambian las columnas; no estos totales. Las columnas muestran los leads cargados.
      </p>

      <AvisoDegradacion
        activo={Boolean(estadoSla.error) && !yo?.demo}
        queReintenta="de los plazos del reloj SLA"
        onReintentar={estadoSla.recargar}
      >
        No se pudo cargar el reloj SLA. Los plazos se ocultan para no mostrar vencimientos incorrectos.
      </AvisoDegradacion>

      {/* Degradación honesta de los KPIs (precedente objetivosError): el
          tablero sigue operable; solo los chips quedan en «—». */}
      <AvisoDegradacion
        activo={Boolean(resumenOp.error) && !yo?.demo}
        queReintenta="de los indicadores del tablero"
        onReintentar={() => { void resumenOp.recargar() }}
      >
        No se pudieron cargar los indicadores del tablero. Se muestran «—» para no inventar cifras.
      </AvisoDegradacion>

      {/* Filtro por analista — supervisor: su equipo; gerencia/directorio: todos */}
      {mostrarFiltro && (
        <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filtrar tablero por analista">
          <button
            type="button"
            aria-pressed={filtro === 'todos'}
            onClick={() => setFVend('todos')}
            className={pillCls(filtro === 'todos')}
          >
            Todos
          </button>
          {ambito.vendedores.map((v) => (
            <button
              key={v.perfil_id}
              type="button"
              aria-pressed={filtro === v.perfil_id}
              onClick={() => setFVend((f) => (f === v.perfil_id ? 'todos' : v.perfil_id))}
              className={pillCls(filtro === v.perfil_id)}
              title={v.nombre_completo}
            >
              <Avatar nombre={v.nombre_completo} className="size-5 text-[8px]" />
              {v.nombre_completo.split(' ')[0]}
            </button>
          ))}
          {porRepartir.length > 0 && (
            <button
              type="button"
              aria-pressed={filtro === 'por_repartir'}
              onClick={() => setFVend((f) => (f === 'por_repartir' ? 'todos' : 'por_repartir'))}
              className={PILL_BASE}
              style={{
                borderColor: 'color-mix(in srgb, var(--warning) 45%, transparent)',
                color: 'var(--warning)',
                background:
                  filtro === 'por_repartir'
                    ? 'color-mix(in srgb, var(--warning) 12%, transparent)'
                    : 'var(--card)',
              }}
            >
              <Inbox className="size-3.5" />
              Por repartir <span className="tabular-nums">({porRepartir.length})</span>
            </button>
          )}
        </div>
      )}

      {/* Kanban. Las columnas conservan sus 290 px: medido a escala real, por
          debajo de ~283 px la cabecera de «Entrevista realizada» salta a dos
          líneas cuando suma soles y dólares, y cada píxel menos recorta más
          nombres. Así que las cinco caben sin scroll donde hay 1 498 px de
          contenido (monitor ancho) y, en un portátil, el carril se desliza en
          horizontal como ya hacía con cuatro. */}
      <div ref={tablero} className="ac-scroll -mx-1 flex min-h-[28rem] flex-1 gap-3 overflow-x-auto px-1 pb-3 md:min-h-0">
        {COLUMNAS_TABLERO.map((col) => {
          const servida = columnasServidor[col.k]
          // El orden dentro de la columna es el del servidor (`actualizado_en`),
          // y registrar un intento NO toca la fila del lead: la tarjeta entra
          // en «Gestionado» en su posición de siempre, no arriba. Con más de
          // una página puede quedar tras «Cargar más» (el total sí la cuenta).
          // Es el mismo paginado de las demás columnas; el orden lo decide
          // Miguel, no se «arregla» reordenando aquí.
          const enCol = leadsDeColumna(col.k)
          const totalPaginas = sesionReal ? 1 : Math.max(1, Math.ceil(enCol.length / LEADS_POR_PAGINA))
          const pagina = sesionReal ? 0 : Math.min(paginaPorColumna[col.k], totalPaginas - 1)
          const inicio = pagina * LEADS_POR_PAGINA
          const visibles = sesionReal ? enCol : enCol.slice(inicio, inicio + LEADS_POR_PAGINA)
          // Total de la columna: en real lo dice el servidor (totales.vivos del
          // filtro etapa+gestión+analista); el capital se suma sobre lo CARGADO.
          const totalServido = servida.resumen?.totales.vivos
          const totalCol = sesionReal ? (totalServido ?? enCol.length) : enCol.length
          // Mientras el servidor no responde (cargando o caído) no hay total que
          // cantar: «—», jamás un 0 que diga «aquí no hay nadie».
          const sinTotal = sesionReal && totalServido == null
          const fallo = sesionReal && servida.error != null
          // «No se pudo cargar» se reserva para la lista que NUNCA llegó…
          const caida = fallo && totalServido == null
          // …si ya había datos y lo que falla es la relectura, se conservan (las
          // tarjetas, el total o el «vacía») y se dice que no se pudo actualizar.
          const desactualizada = fallo && totalServido != null
          // En «Por repartir» solo hay leads sin analista: la columna calculada
          // no puede llenarse y sus textos no lo prometen.
          const sinAnalista = filtro === 'por_repartir'
          const { pen: totalPEN, usd: totalUSD } = capitalPorMoneda(enCol)
          const totalTxt = [
            totalPEN > 0 ? moneyK(totalPEN) : '',
            totalUSD > 0 ? `+${moneyK(totalUSD, 'USD')}` : '',
          ]
            .filter(Boolean)
            .join(' · ')
          const acepta = aceptaSoltar(col)
          const destino = acepta && colDestino === col.k
          const idTitulo = `pipeline-columna-${col.k}`
          // La explicación de la columna calculada es también su descripción
          // accesible: quien llega con lector de pantalla oye por qué no puede
          // llevar un lead hasta ahí.
          const idAyuda = col.esDestino ? undefined : `pipeline-ayuda-${col.k}`
          const cargandoLista = sesionReal && servida.cargando
          // Los textos nuevos de 11 px van en gris oscuro: el gris de siempre
          // se queda en 4,2:1 sobre el carril, por debajo de lo exigible.
          const vacio = cargandoLista
            ? { texto: 'Cargando leads…', fuerte: false }
            // Una lista caída NO es una columna vacía: decir «sin leads» sobre
            // lo que no se pudo leer sería inventarlo.
            : caida
              ? { texto: 'No se pudo cargar esta columna', fuerte: true }
              : destino
                ? { texto: 'Suelta aquí para mover el lead', fuerte: false }
                : col.esDestino
                  ? { texto: 'Sin leads en esta etapa', fuerte: false }
                  : { texto: sinAnalista ? 'Sin leads en esta columna' : 'Sin leads gestionados por ahora', fuerte: true }
          const textoPie = sesionReal
            ? cargandoLista ? 'Cargando…' : caida ? '' : enCol.length === 0 ? 'Sin leads' : `${enCol.length} de ${totalCol}`
            : enCol.length === 0 ? 'Sin leads' : `${inicio + 1}–${inicio + visibles.length} de ${enCol.length}`
          return (
            <div
              key={col.k}
              ref={(nodo) => {
                if (nodo) nodosDeColumna.current.set(col.k, nodo)
                else nodosDeColumna.current.delete(col.k)
              }}
              role="group"
              // Destino PROGRAMÁTICO del foco (no es parada del tabulador): lo
              // recibe cuando «Reintentar» se desmonta al recuperarse la lista.
              tabIndex={-1}
              aria-labelledby={idTitulo}
              aria-describedby={idAyuda}
              className="flex min-h-0 w-[290px] shrink-0 flex-col rounded-2xl focus-visible:outline-2 focus-visible:outline-ring"
            >
              {/* Cabecera de columna */}
              <div className="mb-2.5 flex items-center gap-2 px-1">
                <span
                  aria-hidden
                  className="size-2.5 shrink-0 rounded-full"
                  style={{ background: col.color, boxShadow: `0 0 0 3px color-mix(in srgb, ${col.color} 20%, transparent)` }}
                />
                <p id={idTitulo} className="text-[13px] font-bold text-foreground">{col.label}</p>
                {/* `relative`: ancla el texto oculto (es `absolute`) a su contador. */}
                <span className="relative grid min-w-5 place-items-center rounded-full bg-muted px-1.5 text-[11px] font-bold tabular-nums text-muted-foreground">
                  {sinTotal ? <span aria-hidden className="text-muted-foreground-strong">—</span> : totalCol}
                  <span className="sr-only">{sinTotal ? 'Total no disponible' : totalCol === 1 ? ' lead' : ' leads'}</span>
                </span>
                <p className="ml-auto text-[11px] font-extrabold tabular-nums" style={{ color: col.color }} title={sesionReal && servida.hayMas ? 'Capital de lo cargado hasta ahora' : undefined}>
                  {totalTxt}{sesionReal && servida.hayMas && totalTxt ? ' ·' : ''}
                </p>
              </div>

              {/* Cards (la columna es zona de drop solo si recibe la tarjeta en vuelo) */}
              <div
                className={`ac-scroll min-h-0 flex-1 space-y-2.5 overflow-y-auto rounded-2xl p-2 transition-colors ${
                  destino ? 'bg-primary/[0.08] ring-2 ring-primary/50' : 'bg-primary/[0.03] ring-1 ring-border/60'
                }`}
                onDragOver={
                  // Sin `preventDefault` el navegador no deja soltar: es lo que
                  // hace que «Gestionado» (y la propia etapa del lead) rechacen
                  // la tarjeta con el cursor de «aquí no», sin resaltarse.
                  acepta
                    ? (e) => {
                        e.preventDefault()
                        e.dataTransfer.dropEffect = 'move'
                        if (colDestino !== col.k) setColDestino(col.k)
                      }
                    : undefined
                }
                onDragLeave={
                  escribe
                    ? (e) => {
                        if (!e.currentTarget.contains(e.relatedTarget as Node)) {
                          setColDestino((c) => (c === col.k ? null : c))
                        }
                      }
                    : undefined
                }
                onDrop={escribe ? alDrop(col) : undefined}
              >
                {!col.esDestino && (
                  // Columna calculada: se dice arriba, donde llega la tarjeta y
                  // donde alguien intentaría soltarla. Texto en gris oscuro (el
                  // color de la columna no da 4,5:1 sobre su propio tinte).
                  <p
                    id={idAyuda}
                    className="flex items-start gap-1.5 rounded-xl px-2.5 py-2 text-sm leading-snug text-balance text-muted-foreground-strong"
                    style={{ background: `color-mix(in srgb, ${col.color} 9%, transparent)` }}
                  >
                    <Zap aria-hidden className="mt-[3px] size-3.5 shrink-0" style={{ color: col.color }} />
                    {sinAnalista ? AYUDA_SIN_ANALISTA : AYUDA_GESTIONADO}
                  </p>
                )}
                {visibles.map((l) => (
                  <LeadCard
                    key={l.id}
                    l={l}
                    nombreVendedor={l.vendedor_id == null ? null : nombrePorId.get(l.vendedor_id) ?? l.vendedor_nombre ?? null}
                    semaforo={semaforoEstancamiento(
                      l,
                      indiceContacto,
                      ahora,
                      estadoSla.indice.get(l.id),
                    )}
                    rotuloEtapa={col.k === 'gestionado' ? `${ETAPA_INFO[l.etapa].label} (ya gestionado)` : ETAPA_INFO[l.etapa].label}
                    escribe={escribe}
                    arrastrando={dragId === l.id}
                    potencial={potencial.porLead.get(l.id)}
                    onAbrir={() => abrir(l.id)}
                    onMover={(etapa) => mover(l.id, etapa)}
                    onDragStart={alDragStart(l.id, col.k)}
                    // Red de seguridad, no el camino principal: cubre el
                    // arrastre ABORTADO (soltar fuera de una columna), el único
                    // en el que la card sigue montada para recibirlo.
                    onDragEnd={terminarArrastre}
                  />
                ))}
                {enCol.length === 0 && (
                  <div className={`rounded-xl border border-dashed border-border px-3 py-6 text-center text-[11px] ${vacio.fuerte ? 'text-muted-foreground-strong' : 'text-muted-foreground'}`}>
                    {vacio.texto}
                  </div>
                )}
              </div>
              <div className="flex shrink-0 items-center gap-1.5 px-1 pt-2">
                {/* Región viva de la columna. Se anuncia ENTERA (`aria-atomic`) y
                    dice de qué columna habla; al caerse la lista no puede
                    quedarse muda: pasar de «Cargando…» a nada no lo anuncia
                    nadie. El recuadro de arriba no es otra región viva (serían
                    dos anuncios del mismo hecho). */}
                <span className="mr-auto text-[10px] font-semibold tabular-nums text-muted-foreground" aria-live="polite" aria-atomic="true">
                  <span className="sr-only">{col.label}: </span>
                  <span>{textoPie}</span>
                  {caida && <span className="sr-only">no se pudo cargar</span>}
                  {desactualizada && <span className="sr-only">, no se pudo actualizar</span>}
                </span>
                {fallo && (
                  <button
                    type="button"
                    onClick={(e) => {
                      // Solo hay foco que rescatar si estaba de verdad AQUÍ (con
                      // ratón puede no estarlo: Safari no enfoca al hacer clic).
                      reintentoConFoco.current = document.activeElement === e.currentTarget ? col.k : null
                      void servida.recargar()
                    }}
                    className="cursor-pointer text-[10px] font-semibold text-destructive-text hover:underline"
                  >
                    {/* El espacio va FUERA del span: dentro, hay cálculos del
                        nombre accesible que lo recortan («Reintentarla columna»). */}
                    {caida ? 'No se pudo cargar' : 'No se pudo actualizar'} · Reintentar{' '}
                    <span className="sr-only">la columna {col.label}</span>
                  </button>
                )}
                {sesionReal && servida.hayMas && (
                  <button
                    type="button"
                    disabled={servida.cargandoMas}
                    onClick={servida.cargarMas}
                    aria-label={`Cargar más leads de ${col.label}`}
                    className="cursor-pointer rounded-lg border border-border bg-card px-2 py-1 text-[10px] font-semibold text-muted-foreground transition-colors hover:text-foreground disabled:cursor-default disabled:opacity-40"
                  >
                    {servida.cargandoMas ? 'Cargando…' : 'Cargar más'}
                  </button>
                )}
                {!sesionReal && totalPaginas > 1 && (
                  <>
                    <button
                      type="button"
                      aria-label={`Ver página anterior de ${col.label}`}
                      disabled={pagina === 0}
                      onClick={() => setPaginaPorColumna((actual) => ({ ...actual, [col.k]: pagina - 1 }))}
                      className="grid size-7 cursor-pointer place-items-center rounded-lg border border-border bg-card text-muted-foreground transition-colors hover:text-foreground disabled:cursor-default disabled:opacity-40"
                    >
                      <span aria-hidden>←</span>
                    </button>
                    <span className="text-[10px] font-bold tabular-nums text-muted-foreground">
                      {pagina + 1}/{totalPaginas}
                    </span>
                    <button
                      type="button"
                      aria-label={`Ver página siguiente de ${col.label}`}
                      disabled={pagina + 1 >= totalPaginas}
                      onClick={() => setPaginaPorColumna((actual) => ({ ...actual, [col.k]: pagina + 1 }))}
                      className="grid size-7 cursor-pointer place-items-center rounded-lg border border-border bg-card text-muted-foreground transition-colors hover:text-foreground disabled:cursor-default disabled:opacity-40"
                    >
                      <span aria-hidden>→</span>
                    </button>
                  </>
                )}
              </div>
              {escribe && (col.esDestino ? (
                <button
                  onClick={() => abrirNuevoLead(col.etapa)}
                  className={`ac-nav-item ${FILA_ALTA} text-muted-foreground hover:bg-muted hover:text-foreground cursor-pointer`}
                >
                  <Plus className="size-3.5" /> Agregar lead
                </button>
              ) : (
                // Aquí no se da de alta: un lead nace «Nuevo». El hueco conserva
                // la altura de la fila para que el carril acabe donde los demás.
                <div aria-hidden className={`${FILA_ALTA} invisible`}>&nbsp;</div>
              ))}
            </div>
          )
        })}
      </div>

      {/* Terminales — H23 (F3): el conteo sale del MISMO resumen SERVIDO que
          el tile «Convertidos» de arriba. El store solo carga una página
          (tope 2000 filas) y su foto podía contradecir al servidor. */}
      <div className="flex shrink-0 flex-wrap items-center gap-3">
        {TERMINALES.map((t) => {
          const n = resumen == null
            ? null
            : t.k === 'convertido'
              ? resumen.totales.convertidos
              : resumen.totales.descartados
          return (
            <div key={t.k} className="ac-chip flex items-center gap-2 rounded-xl px-3 py-2 text-xs font-bold" style={{ '--c': t.color } as CSSProperties}>
              {t.k === 'convertido' ? 'Cierres de leads del mes' : 'Descartados actuales'}
              <span className="tabular-nums">{n == null ? '—' : n}</span>
            </div>
          )
        })}
        <p className="self-center text-[11px] text-muted-foreground">
          {yo?.demo
            ? escribe
              ? 'Demo — arrastra una card a otra columna o usa su menú "⋯" para moverla de etapa. Los cambios viven solo en esta sesión.'
              : 'Demo — tu rol es de solo lectura; los datos viven solo en esta sesión.'
            : escribe
              ? 'Arrastra una card a otra columna o usa su menú "⋯" para moverla de etapa.'
              : 'Tu rol es de solo lectura.'}
        </p>
      </div>
      {pidiendoCapital && (
        <DialogCapitalPropuesta lead={pidiendoCapital} onClose={() => setPidiendoCapital(null)} />
      )}
    </div>
  )
}
