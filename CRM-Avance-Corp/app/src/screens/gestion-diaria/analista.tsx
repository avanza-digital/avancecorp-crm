// Gestión Diaria · Fase 3 — «Mi día» del analista. Responde una sola pregunta:
// ¿a quién llamo AHORA? La cola sale de `crm.cola_accion_v2_fn` (la misma del
// mundo SLA) y el resto del día —marcador, compromisos, señales por lead y los
// descartes con su «Deshacer»— de `crm.gestion_diaria_analista_fn`. Aquí no se
// calcula negocio: se ORDENA (`ordenarColaDiaria`, función pura probada) y se
// presenta. Al guardar un resultado, la pantalla salta a la fila siguiente.
//
// «Hoy» NO cambia: sigue siendo «las 3 cosas de ahora» (decisión de Miguel).
// Esta pantalla es la cola COMPLETA del día, y las dos comparten el primer
// ítem: el lead sin primer intento manda en ambas (test compartido).
//
// DISEÑO (27/09/2026, Miguel: «que prevalezca la organización del HTML y lo
// limpio que se ve, con los colores del CRM»). La pantalla cabe entera, sin
// bajar, en un monitor o laptop (desde `lg`):
//   · Cabecera: la pregunta, el corte, la fecha y las dos secciones del módulo.
//   · Franja de 4 cifras: llamadas, contestaron, contacto con su nivel, citas.
//     Reemplaza el botón-resumen «Mi actividad» de la cabecera.
//   · «Ahora» (izquierda), con aire de celular: el ÚNICO lead que toca, su
//     nombre grande, el tiempo que le queda EN PALABRAS y «Llamar».
//   · Tarjeta con pestañas (derecha): «Cola de hoy» (filtros en pastilla, con
//     «Todo» primero), «Mi actividad» (barras por hora, descartes y registro del
//     día) y «Mi seguimiento» (compromisos desde mañana). Lo que antes eran
//     plegables apilados abajo ahora son pestañas: todo en horizontal.
// Escala: la del diseño (Miguel, 27/09/2026: «hay demasiada letra, no está
// respetando el diseño»), que sustituye el piso de 16 px del 20/09. Un solo
// rojo: queda reservado a lo vencido («Se pasó hace 45 min»); la severidad se
// DICE con esas mismas palabras, nunca solo con el color.
// RESULTADO DENTRO DE «AHORA» (etapa 3, 27/09/2026): tras «Llamar», los 7
// resultados y sus pasos aparecen en la misma tarjeta, sin ventana encima. La
// invariante que manda (hallazgo P0 de Codex): el resultado va SIEMPRE a quien
// se llamó. Al pulsar «Llamar» nace una SESIÓN inmutable —la fila, el lead y su
// tarea autoritativa— y la tarjeta, el guardado y el reintento operan solo
// sobre ella, aunque la cola se refresque o cambie de orden; una respuesta
// tardía de una sesión ya cerrada se ignora.
// Integración F4 (21/09): conserva los arreglos publicados de caché parcial,
// tarea autoritativa, paginación y carreras.
import { useEffect, useId, useMemo, useRef, useState, type JSX, type ReactNode, type Ref, type RefObject } from 'react'
import { CalendarClock, ClipboardList, MoreHorizontal, Phone, RefreshCw, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, TIPOS_ACTIVIDAD, type Etapa, type Lead, type Tarea, type TipoActividad } from '@/lib/tipos'
import { etiquetaResultado } from '@/lib/resultado-llamada'
import { tareaQueCierra } from '@/lib/contacto-tarea'
import { presentarCitas } from '@/lib/terminologia'
import {
  COLOR_NIVEL, ETIQUETA_NIVEL, cuandoLimaDe, detalleDeFila, filasDelFiltro, filasDiariasDemo,
  horaLimaDe, ordenarColaDiaria, paginaDeFilas, pestanasDiarias, siguienteTrasGuardar, tiempoDeFila,
  type Descartado, type DiaAnalista, type FilaDiaria, type FiltroCola,
} from '@/lib/gestion-diaria-analista'
import { useDiaAnalista } from '@/data/gestion-diaria-queries'
import { useColaSlaPagina } from '@/data/sla-operacion-queries'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { haceRelativo, ICONO_ACTIVIDAD } from '@/components/app/actividad-visual'
import { AccionesContacto } from '@/components/app/contacto'
import { RegistroResultadoTarjeta } from '@/components/gestion-diaria/registrar-resultado'
import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
import { BarrasPorHora } from '@/components/gestion-diaria/barras-por-hora'
import { FranjaCifras, type CifraDelDia } from '@/components/gestion-diaria/franja-cifras'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Badge } from '@/components/ui/badge'
import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
import { Tabs } from '@/components/ui/tabs'
import { fechaLima } from '@/lib/agenda-derivada'
import { primerNombre } from '@/lib/format'
import { cn } from '@/lib/utils'
import { ColaDeHoy, FILAS_POR_PAGINA } from '@/components/gestion-diaria/cola-de-hoy'

const LIMITE_COLA = 100
type VistaDerecha = 'cola' | 'actividad' | 'seguimiento'

/**
 * La llamada en curso: a quién se llamó, fijado al pulsar «Llamar» (antes de
 * copiar el número o de salir al marcador). Nada de esto se recalcula con la
 * cola: es una foto.
 */
interface SesionLlamada {
  id: number
  fila: FilaDiaria
  lead: Lead
  /** `undefined` mientras se resuelve la tarea autoritativa; `null` = sin tarea. */
  tarea: Tarea | null | undefined
  /** El formulario del resultado está a la vista en la tarjeta. */
  abierta: boolean
}
const FECHA_LARGA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })

export function GestionDiariaAnalista({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { ambito, tareasDe, asegurarLead, obtenerTareaParaRevision } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()

  // TODO el estado vive AQUÍ, por encima de la cascada de carga/error: el hook
  // del día es fail-closed (un refetch fallido devuelve `null`) y, si el filtro,
  // la pestaña o la persona elegida colgaran del subárbol, un parpadeo de red le
  // borraría al analista dónde estaba.
  const [sesion, setSesionEstado] = useState<SesionLlamada | null>(null)
  // Espejo síncrono de la sesión: las respuestas asíncronas comparan contra él
  // para saber si su sesión sigue viva (el estado de React llega un render tarde).
  const sesionRef = useRef<SesionLlamada | null>(null)
  const contadorSesion = useRef(0)
  const setSesion = (s: SesionLlamada | null) => { sesionRef.current = s; setSesionEstado(s) }
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  const [elegido, setElegido] = useState<string | null>(null)
  // El filtro que pidió el analista; `null` = «Todo», el de entrada.
  const [filtroPedido, setFiltroPedido] = useState<FiltroCola | null>(null)
  const [pagina, setPagina] = useState(0)
  const [vistaDerecha, setVistaDerecha] = useState<VistaDerecha>('cola')
  // Los leads cuyo resultado se acaba de guardar: siguen en la cola hasta que el
  // servidor conteste, y sin esto «Ahora» volvería a proponer al que ya cerraste.
  // Es un CONJUNTO y no un solo id: registrar dos seguidos antes de que vuelva
  // el primero hacía que el `finally` de uno destapara al otro.
  const [cerrados, setCerrados] = useState<readonly string[]>([])
  const nombreAhora = useRef<HTMLButtonElement>(null)
  const tituloDescartes = useRef<HTMLHeadingElement>(null)
  const panelAhora = useRef<HTMLElement>(null)
  const encabezado = useRef<HTMLHeadingElement>(null)
  // Leads que ya se pidieron al servidor: `asegurarLead` no está deduplicado y
  // la fila elegida se recalcula con el reloj de cada minuto.
  const pedidos = useRef(new Set<string>())
  const [cargandoLead, setCargandoLead] = useState<string | null>(null)
  const [abriendoPanel, setAbriendoPanel] = useState(false)

  const dia = useDiaAnalista(null, null)
  // El último día CONFIRMADO: solo sirve para seguir pintando la llamada en curso
  // si un refresco falla (revisión a11y, 27/09). Las cifras y la cola NO se
  // pintan con él: el día es fail-closed.
  const ultimoDia = useRef<DiaAnalista | null>(null)
  useEffect(() => { if (dia.dia !== null) ultimoDia.current = dia.dia }, [dia.dia])
  // La cola del día: la misma fuente que «Seguimiento comercial», sin filtros.
  const cola = useColaSlaPagina({ senal: 'todas', etapa: null, analista_id: null }, null, LIMITE_COLA, !yo?.demo)
  const paginaCola = cola.error ? undefined : cola.data
  // La cola y el día son DOS consultas: mientras la cola no ha llegado, decir
  // «no tienes nada pendiente» sería mentir (solo estarían los sin conversación).
  const colaCargando = !yo?.demo && cola.error == null && paginaCola === undefined
  const colaCaida = !yo?.demo && cola.error != null
  const hayMas = paginaCola?.hay_mas === true

  const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
  const filas = useMemo<FilaDiaria[]>(() => {
    if (dia.dia === null) return []
    const todas = yo?.demo
      ? filasDiariasDemo(dia.dia.cartera, ahora, dia.dia.dia)
      : ordenarColaDiaria(paginaCola?.items ?? [], dia.dia.cartera)
    return cerrados.length === 0 ? todas : todas.filter((f) => !cerrados.includes(f.lead_id))
  }, [ahora, cerrados, dia.dia, paginaCola?.items, yo?.demo])

  const pestanas = useMemo(() => pestanasDiarias(filas), [filas])
  // El elegido se busca en TODAS las filas, no solo en el filtro abierto: un
  // refetch puede moverlo de grupo (de «Hoy» a «Vencidas» al dar la hora) y la
  // pantalla no puede perderlo de vista ni dejar un id fantasma guardado.
  const elegida = elegido === null ? null : filas.find((f) => f.lead_id === elegido) ?? null
  // El filtro que manda: el que pidió el analista (o «Todo»). Con un GRUPO a la
  // vista, si el refresco mueve al elegido de grupo, la vista LO SIGUE; en
  // «Todo» no hace falta: ahí están todos (hallazgo de Codex, 27/09/2026).
  const pedido: FiltroCola = filtroPedido ?? 'todo'
  const filtro: FiltroCola = elegida !== null && pedido !== 'todo' && elegida.grupo !== pedido ? elegida.grupo : pedido
  const lista = filasDelFiltro(pestanas, filtro)
  // La página se deriva del elegido: si lo eligió, se ve; si no, la que pidió.
  const indiceElegida = elegida === null ? -1 : lista.findIndex((f) => f.lead_id === elegida.lead_id)
  const paginaPedida = indiceElegida >= 0 ? Math.floor(indiceElegida / FILAS_POR_PAGINA) : pagina
  const vista = paginaDeFilas(lista, paginaPedida, FILAS_POR_PAGINA)
  // Sin elección explícita, «Ahora» es el primero de la página: el orden del
  // servidor ya dice quién urge más.
  const fila = elegida ?? vista.filas[0] ?? null

  // EL TELÉFONO NO VIAJA EN LA COLA. `cola_accion_v2_fn` devuelve del lead solo
  // id, nombre, etapa y analista; el número vive en el ámbito del store, que
  // desde la Fase 4e «sin topes» ya NO carga todos los leads: los trae por
  // demanda. Por eso en «Vencidas» —cuyos leads rara vez están cargados— no
  // salía «Llamar» hasta abrir la ficha, que es quien los traía (bug reportado
  // en producción el 20/09/2026). Aquí se piden en cuanto se eligen, sin
  // obligar al analista a dar un rodeo por la ficha.
  useEffect(() => {
    const id = fila?.lead_id
    if (id === undefined || leadsPorId.has(id) || pedidos.current.has(id)) return
    pedidos.current.add(id)
    setCargandoLead(id)
    let vigente = true
    void asegurarLead(id)
      .catch(() => {
        // Si falló, que se pueda reintentar al volver a elegirlo: si no, el
        // lead se quedaría sin número para siempre en esta sesión.
        pedidos.current.delete(id)
      })
      .finally(() => { if (vigente) setCargandoLead((c) => (c === id ? null : c)) })
    // Cambiar de fila antes de que conteste no debe dejar el «cargando» pegado
    // ni pisar el estado de la fila nueva.
    return () => { vigente = false }
  }, [asegurarLead, fila?.lead_id, leadsPorId])

  function elegir(f: FilaDiaria) {
    const actual = sesionRef.current
    if (actual?.abierta) {
      toast.info(`Primero guarda o cierra el resultado de ${primerNombre(actual.lead.nombre_completo)}.`)
      return
    }
    // Sin formulario abierto (p. ej. volvió del marcador antes de 4 s), elegir a
    // otra persona abandona la llamada fijada.
    if (actual !== null) setSesion(null)
    setElegido(f.lead_id)
    requestAnimationFrame(() => {
      panelAhora.current?.scrollIntoView?.({ block: 'nearest' })
      nombreAhora.current?.focus()
    })
  }
  function cambiarFiltro(nuevo: FiltroCola) {
    setFiltroPedido(nuevo === 'todo' ? null : nuevo)
    setPagina(0)
    setElegido(null)
  }
  /** Se guarda ya acotada: si la lista encoge y vuelve a crecer, no salta sola. */
  function irAPagina(p: number) {
    setPagina(Math.min(Math.max(p, 0), vista.paginas - 1))
  }
  /**
   * Fija la llamada en curso a la persona de la tarjeta. Si ya hay una sesión,
   * es ESA (la tarjeta la está mostrando). Sin el lead en el ámbito no hay
   * sesión: la tarjeta ofrece la ficha, como siempre.
   */
  function iniciarSesion(): SesionLlamada | null {
    const actual = sesionRef.current
    if (actual !== null) return actual
    if (filaActiva === null) return null
    const suyo = leadsPorId.get(filaActiva.lead_id)
    if (suyo === undefined) return null
    const nueva: SesionLlamada = { id: ++contadorSesion.current, fila: filaActiva, lead: suyo, tarea: undefined, abierta: false }
    setSesion(nueva)
    setElegido(filaActiva.lead_id)
    return nueva
  }
  /**
   * Abre el resultado en la tarjeta para la sesión en curso. `tarea_id` viene
   * de la cola del SERVIDOR y es autoritativa: ese id viaja de vuelta para
   * cerrar la tarea. Las tareas del store son una colección PARCIAL igual que
   * los leads, así que no encontrarla ahí no significa que no exista — se pide
   * por id. Caer al cálculo de siempre cerraría otra tarea telefónica, o
   * ninguna (Codex, 20/09).
   */
  async function abrirRegistro() {
    const s = iniciarSesion()
    if (s === null) { if (filaActiva) void abrirLead(filaActiva.lead_id); return }
    if (s.abierta || abriendoPanel) return
    const pendientes = tareasDe(s.lead.id)
    let tarea: Tarea | null
    if (s.fila.tarea_id !== null) {
      const local = pendientes.find((x) => x.id === s.fila.tarea_id)
      if (local !== undefined) tarea = local
      else {
        setAbriendoPanel(true)
        try {
          // Si el servidor tampoco la da, se abre SIN tarea: mejor no cerrar
          // ninguna que cerrar la que no era.
          tarea = await obtenerTareaParaRevision(s.lead.id, s.fila.tarea_id)
        } catch {
          tarea = null
        } finally {
          setAbriendoPanel(false)
        }
      }
    } else {
      tarea = tareaQueCierra(pendientes, 'tel', yo?.id, ahora) ?? null
    }
    // Una respuesta tardía de una sesión ya cerrada no abre nada.
    if (sesionRef.current?.id !== s.id) return
    setSesion({ ...s, tarea, abierta: true })
  }
  /**
   * Cierra la sesión (si sigue siendo la misma), deja ELEGIDA a la persona de la
   * llamada —aunque mientras tanto se haya mirado otro filtro, la tarjeta vuelve
   * a ella y no a la primera de la lista (Codex, 27/09)— y devuelve el foco a
   * «Llamar». Al guardar, `alGuardar` corre justo después y elige al siguiente.
   */
  function cerrarSesion(id: number) {
    const actual = sesionRef.current
    if (actual?.id !== id) return
    setSesion(null)
    setElegido(actual.fila.lead_id)
    requestAnimationFrame(() => {
      const llamar = panelAhora.current?.querySelector<HTMLElement>('[data-accion-panel] a, [data-accion-panel] button')
      ;(llamar ?? nombreAhora.current)?.focus()
    })
  }
  /**
   * Al guardar, «Ahora» pasa a la persona que venía DETRÁS en la lista que se
   * miraba (`siguienteTrasGuardar`) y el foco vuelve a su nombre. Es una
   * persona concreta, no «la primera de la página»: si el servidor tarda en
   * sacar al guardado, no se lo vuelve a proponer.
   */
  async function alGuardar(leadId: string) {
    const siguiente = siguienteTrasGuardar(pestanas, filtro, leadId)
    setCerrados((c) => (c.includes(leadId) ? c : [...c, leadId]))
    setFiltroPedido(siguiente.filtro === 'todo' ? null : siguiente.filtro)
    setElegido(siguiente.lead_id)
    // Dos cuadros: el diálogo restaura primero su foco. Si quedó suelto o
    // en las acciones que acaban de guardar, anunciar el siguiente lead.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const activo = document.activeElement
      const suelto = activo === null || activo === document.body || activo === document.documentElement
        || (activo instanceof HTMLElement && activo.closest('[data-accion-panel]') !== null)
      if (suelto) (nombreAhora.current ?? encabezado.current)?.focus()
    }))
    // `allSettled` y no `all`: si una de las dos lecturas falla, la otra sigue
    // su curso y aquí no queda un rechazo sin capturar. Y se destapa SOLO este
    // lead, no el de un guardado que todavía esté en vuelo.
    await Promise.allSettled([dia.recargar(), ...(yo?.demo ? [] : [cola.refetch()])])
    setCerrados((c) => c.filter((x) => x !== leadId))
  }
  async function deshacer(d: Descartado) {
    if (deshaciendo !== null) return
    setDeshaciendo(d.actividad_id)
    try {
      const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
      await deshacerResultadoLlamada(d.actividad_id)
      // El lead vuelve a la cartera: si estaba tapado por un guardado propio,
      // se destapa — pero solo ese, no los de otros guardados en vuelo.
      setCerrados((c) => c.filter((x) => x !== d.lead_id))
      await dia.recargar()
      toast.success(`Deshecho: ${d.lead_nombre} vuelve a tu cartera`)
      requestAnimationFrame(() => {
        const activo = document.activeElement
        if (activo === null || activo === document.body) (tituloDescartes.current ?? encabezado.current)?.focus()
      })
    } catch (causa) {
      const { mensajeDeError } = await import('@/data/crm-api')
      toast.error(mensajeDeError(causa, 'No se pudo deshacer el descarte.'))
    } finally {
      setDeshaciendo(null)
    }
  }

  const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
  const filaActiva = colaCargando ? null : fila
  // Lo que pinta la tarjeta: la sesión, si hay una; si no, la fila viva.
  const filaTarjeta = sesion?.fila ?? filaActiva
  const leadTarjeta = sesion?.lead ?? (filaActiva ? leadsPorId.get(filaActiva.lead_id) ?? null : null)
  const posicionTarjeta = filaTarjeta === null ? 0 : lista.findIndex((f) => f.lead_id === filaTarjeta.lead_id) + 1
  const fecha = FECHA_LARGA.format(new Date(ahora))
  const total = filas.length
  const conteoCola = colaCaida ? '?' : hayMas ? `${total}+` : String(total)

  const tarjetaAhora = (
    <PanelAhora fila={filaTarjeta} lead={leadTarjeta}
      sinConversacionDias={dia.dia?.sin_conversacion_dias ?? ultimoDia.current?.sin_conversacion_dias ?? 0} ahora={ahora} cargando={colaCargando && sesion === null} colaCaida={colaCaida}
      filtroVacio={filaTarjeta === null && total > 0}
      seccionRef={panelAhora} nombreRef={nombreAhora}
      posicion={posicionTarjeta} total={lista.length}
      cargandoLead={filaTarjeta !== null && cargandoLead === filaTarjeta.lead_id} abriendoPanel={abriendoPanel}
      // «Llamar» FIJA a la persona: nace la sesión de llamada. Si mientras
      // marca (en el celular, con el CRM en segundo plano) entra un lead
      // más urgente, la tarjeta no cambia y el resultado va a ESTA persona.
      onLlamar={() => { iniciarSesion() }}
      onRegistrar={() => { void abrirRegistro() }}
      onAbrirFicha={() => { if (filaTarjeta) void abrirLead(filaTarjeta.lead_id) }}
      // Con el foco dentro, «Ahora» deja de cambiar sola: el refresco de cada
      // minuto no puede cambiarle la persona a quien la está leyendo (a11y).
      onEnfoque={() => { if (elegido === null && sesion === null && filaActiva !== null) setElegido(filaActiva.lead_id) }}
      registro={sesion?.abierta ? (() => {
        const { id: idSesion, lead: leadSesion } = sesion
        return <RegistroResultadoTarjeta key={idSesion} lead={leadSesion} tarea={sesion.tarea ?? null}
          onClose={() => cerrarSesion(idSesion)} onGuardado={() => void alGuardar(leadSesion.id)} />
      })() : undefined} />
  )

  // Con teléfono en pantalla (el día cargado, o una llamada en curso aunque el
  // día se haya caído), desde `lg` el teléfono ocupa TODO el alto a la
  // izquierda, desde la altura del título, y el título, los avisos, las cifras
  // y las pestañas van a la derecha (Miguel, 27/09: «que el teléfono sea más
  // largo»). El orden del DOM no cambia —título, avisos, cifras, teléfono,
  // pestañas—: el lector de pantalla y el tabulador recorren lo mismo que antes.
  const conTelefono = dia.dia !== null || sesion !== null

  return (
    <div className={cn('mx-auto grid w-full max-w-[1440px] content-start gap-4 lg:h-[calc(100svh-7rem)] lg:min-h-[640px]',
      conTelefono && 'lg:grid-cols-[430px_minmax(0,1fr)] lg:grid-rows-[auto_minmax(0,1fr)]')}>
      <div className={cn('flex min-w-0 flex-col gap-4', conTelefono && 'lg:col-start-2 lg:row-start-1')}>
        {/* El título comparte fila con la fecha y los botones, y el subtítulo va
            debajo a todo el ancho (`order-last`): en la columna derecha no cabían
            lado a lado. El DOM conserva título → subtítulo → botones. */}
        <header className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1.5">
          <h2 ref={encabezado} tabIndex={-1} className="text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary">¿A quién llamo ahora?</h2>
          <p className="order-last basis-full text-[13px] text-[var(--muted-foreground-strong)]">
            Llama, guarda el resultado y pasas al siguiente. {corte ? `Corte ${corte}` : 'Sin corte confirmado'} · se actualiza cada minuto.
          </p>
          <div className="flex min-w-0 flex-wrap items-center gap-3">
            <span className="text-[13px] text-foreground/80 first-letter:uppercase">{fecha}</span>
            {accesoSeguimiento}
            <button type="button" aria-label="Actualizar" title="Actualizar" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
              className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] border border-border bg-card text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
              onClick={() => { if (dia.enVuelo) return; void dia.recargar(); if (!yo?.demo) void cola.refetch() }}>
              <RefreshCw aria-hidden className={`size-4 ${dia.enVuelo ? 'motion-safe:animate-spin' : ''}`} />
            </button>
          </div>
        </header>

        {dia.dia === null && sesion !== null ? (
          // Con una llamada en curso, un refresco fallido (p. ej. al volver del
          // marcador) NO desmonta «Ahora»: se perdería el formulario a medio llenar.
          // Se avisa y se sigue pintando la sesión; lo demás espera a que vuelva.
          <p role="alert" className="shrink-0 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
            No se pudo actualizar tu día. Termina de registrar a {primerNombre(sesion.lead.nombre_completo)}: lo demás vuelve en cuanto se recupere la conexión.
          </p>
        ) : dia.dia !== null && (
          <>
            {/* Los avisos que cambian la decisión de marcar van FUERA de las
                pestañas: se ven siempre, esté abierta la que esté. */}
            {colaCaida && (
              <p role="alert" className="shrink-0 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
                No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
              </p>
            )}
            {dia.dia.cartera_truncada && (
              <p role="status" className="shrink-0 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">
                Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
              </p>
            )}

            <FranjaCifras etiqueta="Tu día en cifras" cifras={cifrasDelDia(dia.dia)} />
          </>
        )}
      </div>

      {!conTelefono ? (
        dia.error != null ? (
          <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
        ) : dia.cargando ? (
          <PanelCargando filas={6} />
        ) : (
          <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
        )
      ) : (
        <>
          {tarjetaAhora}
          {dia.dia !== null && (
            <section aria-label="Tu cola y tu actividad" className="flex min-h-[520px] min-w-0 flex-col overflow-hidden rounded-2xl border border-border bg-card lg:col-start-2 lg:row-start-2 lg:min-h-0">
              <Tabs
                etiqueta="Qué ver"
                variante="subrayado"
                // «Cola de hoy» arranca con controles: su panel no es parada del
                // tabulador. En «Mi actividad» y «Mi seguimiento» el panel ES el
                // contenedor con scroll, alcanzable con el teclado (revisión a11y).
                panelEnfocable={vistaDerecha !== 'cola'}
                valor={vistaDerecha}
                onCambio={setVistaDerecha}
                pestanas={[
                  { valor: 'cola', etiqueta: 'Cola de hoy', extra: `· ${conteoCola}` },
                  { valor: 'actividad', etiqueta: 'Mi actividad' },
                  { valor: 'seguimiento', etiqueta: 'Mi seguimiento', ...(dia.dia.compromisos_total > 0 ? { extra: `· ${dia.dia.compromisos_total}` } : {}) },
                ]}
                className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-[18px] [&>[role=tablist]]:pt-1.5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm [&>[role=tablist]>[role=tab]>span]:text-sm"
                clasePanel={vistaDerecha === 'cola' ? 'flex min-h-0 flex-1 flex-col' : 'ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2'}
              >
                {vistaDerecha === 'cola' ? (
                  <ColaDeHoy
                    idBase={id} pestanas={pestanas} filtro={filtro} onFiltro={cambiarFiltro}
                    pagina={vista.pagina} onPagina={irAPagina}
                    elegido={filaActiva?.lead_id ?? null} onElegir={elegir}
                    ahora={ahora} cargando={colaCargando} hayMas={hayMas} colaCaida={colaCaida}
                    sinConversacionDias={dia.dia.sin_conversacion_dias}
                  />
                ) : vistaDerecha === 'actividad' ? (
                  <MiActividad dia={dia.dia} analistaId={yo?.id ?? null} hoy={fechaLima(ahora)}
                    deshaciendo={deshaciendo} onDeshacer={(d) => { void deshacer(d) }} tituloDescartesRef={tituloDescartes}
                    onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
                ) : (
                  <MiSeguimiento dia={dia.dia} onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
                )}
              </Tabs>
            </section>
          )}
        </>
      )}
    </div>
  )
}

/**
 * Las 4 cifras de la franja. El % NUNCA va solo (decisión #7): lleva las útiles
 * sobre las que se calcula; sin llamadas útiles se dice «—» con su palabra para
 * el lector, y sin el mínimo no hay chip de nivel.
 */
function cifrasDelDia(dia: DiaAnalista): CifraDelDia[] {
  const m = dia.marcador
  const utiles = m.utiles === 1 ? '1 útil' : `${m.utiles} útiles`
  const minimo = dia.umbrales.minimo_llamadas_utiles
  const contacto: CifraDelDia = m.tasa_contacto_pct === null
    ? { etiqueta: 'Contacto', valor: '—', valorAccesible: 'sin dato', apoyo: `se juzga desde ${minimo} llamadas útiles` }
    : {
      etiqueta: 'Contacto',
      valor: `${m.tasa_contacto_pct} %`,
      apoyo: m.nivel === null
        ? `de ${utiles}`
        : <Badge className="min-h-[22px] py-0 text-[11.5px]" color={COLOR_NIVEL[m.nivel]}>{ETIQUETA_NIVEL[m.nivel]} · de {utiles}</Badge>,
    }
  return [
    { etiqueta: 'Llamadas', valor: String(m.llamadas), apoyo: 'hoy' },
    { etiqueta: 'Contestaron', valor: String(m.contestadas), apoyo: `de ${m.llamadas}` },
    contacto,
    { etiqueta: presentarCitas('Citas agendadas'), valor: String(m.citas_agendadas), apoyo: 'hoy' },
  ]
}


/**
 * El panel «Ahora»: UN lead, UNA acción primaria, con aire de celular porque es
 * el centro de llamadas (diseño del 27/09/2026): cabecera navy con la barrita
 * del altavoz, el teléfono grande, «Llamar» redondo y la barra de inicio abajo.
 * Lo secundario —ver la ficha, registrar desde el menú— vive detrás de «···»
 * (ley de Hick). Escala y medidas: las del diseño (384 px de ancho, radio 32).
 */
function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaida, filtroVacio, onLlamar, onRegistrar, onAbrirFicha, onEnfoque, seccionRef, nombreRef, cargandoLead, abriendoPanel, posicion, total, registro }: {
  fila: FilaDiaria | null
  lead: Lead | null
  sinConversacionDias: number
  ahora: number
  cargando: boolean
  colaCaida: boolean
  /** La lista a la vista está vacía pero la cola no: el vacío es del filtro. */
  filtroVacio: boolean
  cargandoLead: boolean
  abriendoPanel: boolean
  posicion: number
  total: number
  onLlamar: () => void
  onRegistrar: () => void
  onAbrirFicha: () => void
  /** El foco entró en la tarjeta. */
  onEnfoque: () => void
  seccionRef: RefObject<HTMLElement | null>
  nombreRef: Ref<HTMLButtonElement>
  /** El resultado de la llamada en curso: ocupa el lugar de las acciones. */
  registro?: ReactNode
}): JSX.Element {
  const id = useId()
  const etapa = fila === null ? null : ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
  const tiempo = fila === null ? null : tiempoDeFila(fila, ahora)
  // `focusin` nativo (burbujea desde cualquier control de la tarjeta): la
  // sección no es un control, así que no lleva manejador de eventos en JSX.
  const seccion = useRef<HTMLElement | null>(null)
  const enfoque = useRef(onEnfoque)
  enfoque.current = onEnfoque
  const enlazarSeccion = (nodo: HTMLElement | null) => {
    seccion.current = nodo
    seccionRef.current = nodo
  }
  useEffect(() => {
    const nodo = seccion.current
    if (nodo === null) return
    const alEntrar = () => enfoque.current()
    nodo.addEventListener('focusin', alEntrar)
    return () => nodo.removeEventListener('focusin', alEntrar)
  }, [])
  return (
    <div className="flex min-h-0 justify-center lg:col-start-1 lg:row-span-2 lg:row-start-1 lg:w-[430px]">
      <section ref={enlazarSeccion} aria-labelledby={`${id}-ahora`}
        className="flex w-full max-w-[384px] flex-col overflow-clip rounded-[32px] border border-border-strong bg-card shadow-[0_10px_28px_rgb(17_30_61/0.10)] lg:h-full">
        <div className="shrink-0 bg-primary text-primary-foreground">
          <span aria-hidden="true" className="mx-auto mt-2.5 block h-[5px] w-14 rounded-full bg-white/30" />
          <div className="flex items-center gap-2.5 px-5 pb-3.5 pt-2">
            <Phone aria-hidden className="size-[18px]" />
            <h3 id={`${id}-ahora`} className="text-[15px] font-extrabold">Ahora</h3>
            {fila !== null && posicion > 0 && <span className="ml-auto text-[13px] tabular-nums text-primary-foreground/80"><span className="sr-only">Contacto</span>{' '}{posicion} de {total}{' '}<span className="sr-only">en esta lista</span></span>}
          </div>
        </div>
        {fila === null ? (
          <p className="grid flex-1 place-items-center px-6 py-8 text-center text-sm leading-relaxed text-[var(--muted-foreground-strong)]">
            {cargando ? 'Buscando a quién llamar…'
              : colaCaida ? 'No se pudo leer tu cola: no sabemos a quién te toca llamar. Pulsa «Actualizar».'
                : filtroVacio ? 'Nada en este filtro. Vuelve a «Todo» para ver a quién llamar.'
                  : 'Nada pendiente ahora. Cuando entre un lead nuevo aparecerá aquí.'}
          </p>
        ) : (
          <div className={registro !== undefined
            ? 'flex min-h-0 flex-1 flex-col gap-3 pt-4 [&>*:not(section)]:px-[18px]'
            : 'ac-scroll flex min-h-0 flex-1 flex-col gap-3.5 overflow-y-auto px-[18px] py-5'}>
            <div className="flex min-w-0 flex-col gap-0.5">
              <button ref={nombreRef} type="button" onClick={onAbrirFicha}
                aria-label={`Abrir la ficha de ${fila.nombre_completo}`}
                className="self-start rounded-md text-left text-2xl font-extrabold leading-tight tracking-[-0.02em] text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
                {fila.nombre_completo}
              </button>
              <p className="text-[13px] text-[var(--muted-foreground-strong)]">{etapa}</p>
            </div>
            {registro === undefined && <div className="flex flex-col items-start gap-2 rounded-xl bg-muted/70 px-3.5 py-3">
              {tiempo !== null && (
                <Badge className="min-h-[22px] py-0 text-[11.5px]" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
              )}
              <p className="text-[13px] leading-snug text-foreground/80">
                {fila.senal === null ? 'Historial no cargado. Ábrelo en la ficha antes de llamar.' : detalleDeFila(fila, sinConversacionDias)}
              </p>
            </div>}
            {registro === undefined && <LoUltimo leadId={fila.lead_id} nombre={fila.nombre_completo} ahora={ahora} onVerTodo={onAbrirFicha} />}
            {registro !== undefined ? (
              <>
                {lead !== null && <p className="text-center text-xl font-extrabold tracking-[0.02em] tabular-nums text-primary">{lead.telefono}</p>}
                {registro}
              </>
            ) : (
            // En reposo, el número y las acciones bajan al PIE, como en una
            // pantalla de llamada: arriba quién es y lo último con él, abajo cómo
            // llamarlo. `sticky`: en una pantalla baja, «Lo último» se desplaza
            // por debajo y «Llamar» nunca se sale de la vista.
            <div className="sticky bottom-0 mt-auto flex flex-col gap-3.5 bg-card pt-1 before:pointer-events-none before:absolute before:inset-x-0 before:-top-5 before:h-5 before:bg-gradient-to-t before:from-card before:to-transparent">
            {lead !== null && <p className="text-center text-2xl font-extrabold tracking-[0.02em] tabular-nums text-primary">{lead.telefono}</p>}
            <div className="relative">
              {lead !== null ? (
                // `key={lead.id}`: UNA instancia por lead. Antes las acciones
                // vivían dentro de cada fila y se desmontaban con ella; aquí hay
                // una sola caja que cambia de lead, y si el refresco de cada
                // minuto cambiaba el lead con el diálogo de resultado ABIERTO, el
                // resultado se escribía sobre el lead equivocado. La clave fuerza
                // el remontaje: el contacto a medias se cae a la vista, que es
                // reparable — atribuirlo a otra persona, no (hallazgo de Codex).
                // El envoltorio da la forma del diseño: píldoras de 44 px —«Llamar»
                // bajó de 52 porque se veía muy grande (Miguel, 27/09)—, dejando
                // sitio a «···» junto a la última.
                <div data-accion-panel="si"
                  className="[&>div]:flex-col [&>div]:items-stretch [&>div]:!gap-2.5 [&>div>*]:justify-center [&>div>*]:!rounded-full [&>div>*]:!font-bold [&>div>*:first-child]:!h-11 [&>div>*:first-child]:!text-sm [&>div>*:not(:first-child)]:!h-11 [&>div>*:not(:first-child)]:!text-[13px] [&>div>*:not(:first-child)]:!font-semibold [&>div>*:not(:first-child)]:mr-[54px] [&_svg]:!size-[18px]">
                  <AccionesContacto key={lead.id} lead={lead} destacada onLlamar={onLlamar} onRegistrarLlamada={onRegistrar} />
                </div>
              ) : (
                <p role="status" className="min-h-11 pr-[54px] text-[13px] text-[var(--muted-foreground-strong)]">
                  {cargandoLead ? 'Buscando su número…' : 'No se pudo traer su número. Abre la ficha para llamar.'}
                </p>
              )}
              <div className="absolute bottom-0 right-0">
                <DropdownMenu
                  trigger={
                    <button type="button" data-accion-panel="si"
                      aria-label={`Más acciones para ${fila.nombre_completo}: registrar resultado y ver la ficha`}
                      className="grid size-11 shrink-0 cursor-pointer place-items-center rounded-full border border-border bg-card text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
                      <MoreHorizontal aria-hidden className="size-[18px]" />
                    </button>
                  }>
                  <DropdownItem className="min-h-11 text-base" disabled={abriendoPanel} onSelect={() => { if (!abriendoPanel) onRegistrar() }}>Registrar resultado</DropdownItem>
                  <DropdownItem className="min-h-11 text-base" onSelect={onAbrirFicha}>Ver la ficha completa</DropdownItem>
                </DropdownMenu>
              </div>
            </div>
            </div>
            )}
          </div>
        )}
        {registro === undefined && <p className="shrink-0 border-t border-border px-5 pb-1.5 pt-3 text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
          El orden lo pone el servidor: nuevo sin intento primero, luego lo vencido y lo de hoy. Al guardar pasas al siguiente.
        </p>}
        <span aria-hidden="true" className="mx-auto mb-2 block h-1 w-24 shrink-0 rounded-full bg-border-strong" />
      </section>
    </div>
  )
}

/** Lo que cuenta como gestión con el lead; los movimientos del sistema (etapas,
 * reasignaciones, conversión) no dicen qué se habló con él. */
const TIPOS_GESTION: ReadonlySet<TipoActividad> = new Set<TipoActividad>(['llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada', 'nota'])
// Dos: caben con las acciones del teléfono (también con «Correo») a 1440×818.
const TOPE_LO_ULTIMO = 2

/**
 * «Lo último con este lead» (Miguel, 27/09): lo que el analista necesita saber
 * ANTES de marcar —qué pasó en las últimas gestiones y qué quedó dicho—, en el
 * aire que dejó el teléfono a todo el alto. Sale del historial POR LEAD que ya
 * usa la ficha (sin consultas nuevas al servidor). Sin historial todavía se dice
 * que está cargando o que falló: nunca «sin gestiones» por no saberlo.
 */
function LoUltimo({ leadId, nombre, ahora, onVerTodo }: { leadId: string; nombre: string; ahora: number; onVerTodo: () => void }): JSX.Element {
  const id = useId()
  const historial = useActividadesDeLead(leadId)
  const gestiones = historial.items.filter((a) => TIPOS_GESTION.has(a.tipo)).slice(0, TOPE_LO_ULTIMO)
  const nota = 'text-[13px] leading-snug text-[var(--muted-foreground-strong)]'
  return (
    <section aria-labelledby={`${id}-titulo`} className="flex flex-col gap-2 pt-1">
      <div className="flex items-center justify-between gap-2">
        <h4 id={`${id}-titulo`} className="text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]">Lo último con este lead</h4>
        <button type="button" onClick={onVerTodo} aria-label={`Ver todo el historial de ${nombre}`}
          className="min-h-6 shrink-0 cursor-pointer rounded-md text-xs font-semibold text-[var(--accent-press)] underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11">
          Ver todo
        </button>
      </div>
      {historial.cargando ? (
        <p className={nota}>Cargando sus últimas gestiones…</p>
      ) : historial.error != null ? (
        <p className={nota}>
          No se pudo cargar su historial.{' '}
          <button type="button" onClick={historial.reintentar} className="cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Reintentar</button>
        </p>
      ) : gestiones.length === 0 ? (
        <p className={nota}>Sin gestiones todavía: esta llamada será la primera.</p>
      ) : (
        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
        <ol role="list" className="flex flex-col gap-2.5">
          {gestiones.map((a) => {
            const Icono = ICONO_ACTIVIDAD[a.tipo]
            const clave = a.metadata?.['resultado']
            const resultado = typeof clave === 'string' ? etiquetaResultado(clave) : null
            return (
              <li key={a.id} className="flex gap-2.5">
                <span aria-hidden="true" className="mt-px grid size-6 shrink-0 place-items-center rounded-full bg-muted text-[var(--muted-foreground-strong)] [&_svg]:size-3.5"><Icono /></span>
                <div className="min-w-0 flex-1">
                  <p className="flex items-baseline justify-between gap-2">
                    <span className="min-w-0 truncate text-[13px] font-bold text-primary">{TIPOS_ACTIVIDAD[a.tipo]}{resultado !== null && ` · ${resultado}`}</span>
                    <span className="shrink-0 text-xs tabular-nums text-[var(--muted-foreground-strong)]">{haceRelativo(a.creado_en, ahora)}</span>
                  </p>
                  {a.detalle && <p className="line-clamp-2 text-[13px] leading-snug text-foreground/80">{presentarCitas(a.detalle)}</p>}
                </div>
              </li>
            )
          })}
        </ol>
      )}
    </section>
  )
}

/**
 * «Mi actividad»: lo que el analista YA hizo hoy, en una pestaña y no en
 * plegables apilados. Las barras por hora (decisión #8), cómo se cuenta, los
 * descartes que aún se pueden deshacer y el registro íntegro del día (antes
 * vivía plegado debajo de la pantalla, en el contenedor).
 */
function MiActividad({ dia, analistaId, hoy, deshaciendo, onDeshacer, onAbrirFicha, tituloDescartesRef }: {
  dia: DiaAnalista
  analistaId: string | null
  hoy: string
  deshaciendo: string | null
  onDeshacer: (d: Descartado) => void
  onAbrirFicha: (leadId: string) => void
  tituloDescartesRef: Ref<HTMLHeadingElement>
}): JSX.Element {
  const m = dia.marcador
  return (
    // El scroll lo pone el tabpanel que la envuelve (alcanzable con teclado).
    <div className="space-y-6 px-[18px] py-4">
      <h3 className="sr-only">Mi actividad de hoy</h3>
      <div className="space-y-2">
        <BarrasPorHora porHora={m.por_hora} titulo="Llamadas por hora" alto={130}
          apoyo={m.ultima_llamada_en !== null ? `Primera ${horaLimaDe(m.primera_llamada_en)} · última ${horaLimaDe(m.ultima_llamada_en)}` : undefined} />
        <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
          Tocaste {m.leads_tocados} {m.leads_tocados === 1 ? 'lead' : 'leads'}. Llamadas = marcadas + no contestadas; no incluye WhatsApp ni citas.
          Un número errado no entra en el contacto, y el nivel se juzga desde {dia.umbrales.minimo_llamadas_utiles} llamadas útiles. Tu supervisor ve esto mismo de ti.
        </p>
      </div>
      <Descartados dia={dia} deshaciendo={deshaciendo} onDeshacer={onDeshacer} onAbrirFicha={onAbrirFicha} tituloRef={tituloDescartesRef} />
      {analistaId !== null && (
        // Versión compacta del registro compartido: supervisor y gerencia
        // conservan la suya hasta sus propios planes.
        <RegistroActividad dia={hoy} analistaIds={[analistaId]} mostrarAnalista={false} permitirExportar={false} compacto />
      )}
    </div>
  )
}

/**
 * Compromisos: SOLO de mañana en adelante — el servidor los devuelve desde
 * mañana 00:00 Lima (`gestion_diaria_analista_fn`, `v_manana`), y lo de hoy y
 * lo vencido ya está en la cola.
 */
function MiSeguimiento({ dia, onAbrirFicha }: {
  dia: DiaAnalista
  onAbrirFicha: (leadId: string) => void
}): JSX.Element {
  return (
    <div className="px-[18px] py-4">
      <h3 className="text-[15px] font-extrabold text-primary">
        Mi seguimiento <span className="font-semibold text-[var(--muted-foreground-strong)]">· {dia.compromisos_total} {dia.compromisos_total === 1 ? 'compromiso' : 'compromisos'} desde mañana</span>
      </h3>
      {dia.compromisos.length === 0 ? (
        <PanelVacio icono={CalendarClock} titulo="Sin compromisos a partir de mañana" detalle="Lo de hoy y lo vencido ya está en tu cola." />
      ) : (
        <>
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ol role="list" aria-label="Mis compromisos" className="mt-2">
            {dia.compromisos.map((c) => (
              <li key={c.tarea_id} className="flex flex-wrap items-center justify-between gap-2 border-b border-muted py-2.5">
                <div className="min-w-0">
                  <button type="button" onClick={() => onAbrirFicha(c.lead_id)}
                    className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
                    {c.lead_nombre}
                  </button>
                  <p className="text-xs text-[var(--muted-foreground-strong)]">
                    {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
                    {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
                  </p>
                </div>
                <span className="text-[13px] font-semibold tabular-nums text-foreground/80">{cuandoLimaDe(c.vence_en)}</span>
              </li>
            ))}
          </ol>
          {dia.compromisos_total > dia.compromisos.length && (
            <p className="mt-3 text-xs text-[var(--muted-foreground-strong)]">
              Se muestran los {dia.compromisos.length} más próximos de {dia.compromisos_total}. El resto está en Agenda.
            </p>
          )}
        </>
      )}
    </div>
  )
}

function Descartados({ dia, deshaciendo, onDeshacer, onAbrirFicha, tituloRef }: {
  dia: DiaAnalista
  deshaciendo: string | null
  onDeshacer: (d: Descartado) => void
  onAbrirFicha: (leadId: string) => void
  tituloRef: Ref<HTMLHeadingElement>
}): JSX.Element | null {
  const id = useId()
  if (dia.descartados.length === 0) return null
  return (
    <section aria-labelledby={`${id}-descartados`} className="space-y-1.5">
      <h3 ref={tituloRef} tabIndex={-1} id={`${id}-descartados`} className="text-[15px] font-extrabold text-primary">
        Descartados hoy <span className="font-semibold text-[var(--muted-foreground-strong)]">· {dia.descartados.length} · se pueden deshacer 24 h</span>
      </h3>
      <p className="text-xs text-[var(--muted-foreground-strong)]">
        Están en el Centro de rescate con su motivo. Al deshacerlo, el lead vuelve a tu cartera con un ciclo nuevo.
      </p>
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ol role="list" aria-label="Descartados hoy">
        {dia.descartados.map((d) => (
          <li key={d.actividad_id} className="flex flex-wrap items-center justify-between gap-2 border-b border-muted py-2.5">
            <div className="min-w-0">
              <button type="button" onClick={() => onAbrirFicha(d.lead_id)}
                className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
                {d.lead_nombre}
              </button>
              <p className="text-xs text-[var(--muted-foreground-strong)]">
                {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
                {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
              </p>
            </div>
            {d.puede_deshacer ? (
              // `aria-disabled` y no `disabled`: deshabilitar el botón enfocado
              // manda el foco al body (regla de la casa, boton-guardar.tsx).
              <button type="button" aria-disabled={deshaciendo !== null}
                aria-label={`Deshacer el descarte de ${d.lead_nombre}`}
                className="inline-flex h-9 cursor-pointer items-center gap-1.5 rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50"
                onClick={() => { if (deshaciendo === null) onDeshacer(d) }}>
                <RotateCcw aria-hidden className="size-4" /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
              </button>
            ) : (
              <span className="text-xs text-[var(--muted-foreground-strong)]">Sin deshacer</span>
            )}
          </li>
        ))}
      </ol>
    </section>
  )
}
