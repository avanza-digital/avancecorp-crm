import { AccesoGestionesClientes } from '@/components/gestion-diaria/resumen-gestiones'
// Gestión diaria del analista. `gestion_diaria_cola_trabajo_fn` decide el
// orden y el avance de la cola completa ANTES de paginar. La actividad vigente
// del día de Lima es la fuente del progreso; el navegador guarda navegación.
// `gestion_diaria_analista_fn` conserva las cifras, actividad y seguimiento.
// Una sesión inmutable fija a quién se llamó hasta confirmar el guardado.
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
// CLIENTES (cola v3, 29/09/2026): una tarea de un cliente de la cartera es una
// fila más, identificada por su clave. No hay lead ni sesión de llamada: su
// resultado se registra con el cierre de tarea de siempre, sobre la tarea que
// el store ya tiene (la del ámbito), y el teléfono solo aparece si la ficha
// autorizada del cliente lo da.
import { useEffect, useId, useMemo, useRef, useState, type JSX, type ReactNode, type Ref, type RefObject } from 'react'
import { CalendarClock, ClipboardList, MoreHorizontal, Phone, RefreshCw, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { usePuedeMarcar } from '@/lib/media'
import { enlaceTel } from '@/lib/telefono'
import { ETAPA_INFO, TIPOS_ACTIVIDAD, TIPOS_TAREA, type Etapa, type Lead, type Tarea, type TipoActividad } from '@/lib/tipos'
import { etiquetaResultado } from '@/lib/resultado-llamada'
import { tareaQueCierra } from '@/lib/contacto-tarea'
import { armarIntencion, cerrarIntencionesDe, intencionDe } from '@/lib/intencion-contacto'
import type { ResueltaHoy } from '@/lib/llamadas-celular'
import { useLlamadasCelular } from '@/data/use-llamadas-celular'
import { LlamadasCelular } from '@/components/gestion-diaria/llamadas-celular'
import { presentarCitas } from '@/lib/terminologia'
import {
  COLOR_NIVEL, ETIQUETA_NIVEL, cuandoLimaDe, detalleDeFila,
  finDelDiaLima, horaLimaDe, pestanasDiarias, tiempoDeFila,
  type Descartado, type DiaAnalista, type FilaCliente, type FilaDiaria, type FilaLead, type FiltroCola,
} from '@/lib/gestion-diaria-analista'
import { useDiaAnalista } from '@/data/gestion-diaria-queries'
import { useColaTrabajo } from '@/data/gestion-diaria-cola-queries'
import { filasTrabajoDemo, paginarTrabajoDemo } from '@/lib/gestion-diaria-cola-demo'
import { leerContextoCola, guardarContextoCola, textoGestion } from '@/lib/gestion-diaria-cola'
import { useContactoInversionista } from '@/data/inversionistas-queries'
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import { abrirInversionista } from '@/lib/router'
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

type VistaDerecha = 'cola' | 'actividad' | 'seguimiento' | 'celular'

/** Un cierre de cliente que acaba de avisar, con lo necesario para decidir qué pasó. */
interface CierreAvisado {
  fila: FilaCliente
  /** El vencimiento de la tarea al abrir el diálogo: si cambia, se reprogramó. */
  venceAntes: string
  /** La fila de detrás en la lista que se miraba, calculada al avisar. */
  siguiente: { filtro: FiltroCola; clave: string | null }
}
/**
 * Cuánto se vigila el store tras el aviso del diálogo. La postventa relee el
 * ámbito ANTES de avisar, así que el cambio llega en el mismo commit o en el
 * siguiente; el margen solo cubre el caso en que React lo aplique más tarde.
 */
const MARGEN_CIERRE_MS = 3000

/**
 * La llamada en curso: a quién se llamó, fijado al pulsar «Llamar» (antes de
 * copiar el número o de salir al marcador). Nada de esto se recalcula con la
 * cola: es una foto.
 */
interface SesionLlamada {
  id: number
  fila: FilaLead
  lead: Lead
  /** `undefined` mientras se resuelve la tarea autoritativa; `null` = sin tarea. */
  tarea: Tarea | null | undefined
  /** El formulario del resultado está a la vista en la tarjeta. */
  abierta: boolean
  siguiente: { filtro: FiltroCola; clave: string | null }
}
const FECHA_LARGA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })

export function GestionDiariaAnalista({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
  const { yo } = useAuth()
  const ahora = useAhora()
  const dia = useDiaAnalista(null, null)
  const { ambito, tareas, tareasDe, asegurarLead, obtenerTareaParaRevision, actividadesDelAmbito } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()
  const hoy = dia.dia?.dia ?? fechaLima(ahora)
  const alcanceNav = `${yo?.id ?? ''}:${hoy}`
  const alcanceGuardado = useRef(alcanceNav)
  const [contextoInicial] = useState(() => leerContextoCola(yo?.id ?? '', hoy))
  const navegacionVigente = alcanceGuardado.current === alcanceNav

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
  // La intención de contacto que abrió la tarjeta es de ESTA pantalla mientras
  // dure la sesión; si la pantalla se va con la sesión viva, se libera para que
  // la cola de llamadas no quede atascada (F1.1.3).
  const actorRef = useRef(yo?.id)
  actorRef.current = yo?.id
  useEffect(() => () => {
    const viva = sesionRef.current
    if (viva) cerrarIntencionesDe(actorRef.current, viva.lead.id)
  }, [])
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  // La CLAVE de la fila elegida (`lead:<uuid>` | `tarea:<uuid>`), no un lead:
  // un cliente puede tener dos tareas en la cola.
  const [elegido, setElegido] = useState<string | null>(contextoInicial.elegido)
  // La tarea de CLIENTE abierta en el diálogo de cierre, con su fila. El ref
  // dice qué diálogo sigue ABIERTO: el diálogo avisa igual al guardar que al
  // cancelar, y puede avisar dos veces; solo el primer aviso cuenta.
  const [cierreCliente, setCierreCliente] = useState<{ fila: FilaCliente; tarea: Tarea } | null>(null)
  const cierreAbierto = useRef<string | null>(null)
  // Un cierre de cliente que acaba de avisar: lo decide el efecto de abajo en
  // cuanto el store refleja lo que se hizo (ver `MARGEN_CIERRE_MS`).
  const [cierreAvisado, setCierreAvisado] = useState<CierreAvisado | null>(null)
  // El filtro que pidió el analista; `null` = «Todo», el de entrada.
  const [filtroPedido, setFiltroPedido] = useState<FiltroCola | null>(contextoInicial.filtro)
  const [pagina, setPagina] = useState(contextoInicial.pagina)
  const [vistaDerecha, setVistaDerecha] = useState<VistaDerecha>('cola')
  // Fuente por actor: demo en memoria o puertas reales con paginación y validación del contrato.
  const celular = useLlamadasCelular()
  const vistaVisible: VistaDerecha = vistaDerecha === 'celular' && !celular ? 'cola' : vistaDerecha
  // «Registrar resultado» desde la pestaña: la MISMA intención que arma el enlace del celular, con la vía «pestana».
  // El receptor de F1 abre la encuesta de siempre (la de «Ahora» si es su lead; si no, la de la ficha).
  const registrarDesdePestana = (fila: { lead_id: string | null; numero: string | null; evento_origen_id?: string | undefined }) => {
    if (!yo?.id || !fila.lead_id) return
    armarIntencion({
      actor: yo.id, leadId: fila.lead_id, canal: 'tel', origen: 'enlace', numero: fila.numero,
      ...(fila.evento_origen_id ? { origenLlamada: fila.evento_origen_id, viaLlamada: 'pestana' as const } : {}),
    })
  }
  // «Registrar el corregido» (hallazgo de P9) con otra encuesta abierta: el coordinador le pegaría el id de la llamada
  // deshecha a esa encuesta si es del mismo lead y no tiene id, y al guardarla se movería el enlace equivocado (revisión
  // de Miguel en el #227, 08/10). Como al elegir otra fila, se pide guardar o cerrar la abierta antes de corregir.
  const corregirDesdePestana = (fila: ResueltaHoy) => {
    const actual = sesionRef.current
    if (actual?.abierta) {
      toast.info(`Primero guarda o cierra el resultado de ${primerNombre(actual.lead.nombre_completo)}.`)
      return
    }
    if (intencionDe(yo?.id)?.abierta) {
      toast.info('Primero guarda o cierra la encuesta que tienes abierta.')
      return
    }
    registrarDesdePestana(fila)
  }
  // Solo cierres de tareas de CLIENTE, hasta que la lectura confirme su salida.
  // Los leads gestionados siguen visibles al final según la respuesta del servidor.
  const [cerrados, setCerrados] = useState<readonly string[]>([])
  const [revisionCola, setRevisionCola] = useState(0)
  const nombreAhora = useRef<HTMLButtonElement>(null)
  const focoPendiente = useRef(false)
  const tituloDescartes = useRef<HTMLHeadingElement>(null)
  const panelAhora = useRef<HTMLElement>(null)
  const encabezado = useRef<HTMLHeadingElement>(null)
  // Leads que ya se pidieron al servidor: `asegurarLead` no está deduplicado y
  // la fila elegida se recalcula con el reloj de cada minuto.
  const pedidos = useRef(new Set<string>())
  const [cargandoLead, setCargandoLead] = useState<string | null>(null)
  const [abriendoPanel, setAbriendoPanel] = useState(false)

  // El último día CONFIRMADO: solo sirve para seguir pintando la llamada en curso
  // si un refresco falla (revisión a11y, 27/09). Las cifras y la cola NO se
  // pintan con él: el día es fail-closed.
  const ultimoDia = useRef<DiaAnalista | null>(null)
  useEffect(() => { if (dia.dia !== null) ultimoDia.current = dia.dia }, [dia.dia])
  const pedidoCola = { filtro: navegacionVigente ? filtroPedido ?? 'todo' : 'todo',
    pagina: navegacionVigente ? pagina : 0, limite: FILAS_POR_PAGINA,
    elegido: navegacionVigente ? elegido : null }
  const cola = useColaTrabajo(pedidoCola, hoy, revisionCola)
  const filasDemo = useMemo(() => yo?.demo && dia.dia
    ? filasTrabajoDemo(dia.dia, tareas, actividadesDelAmbito ?? [], ahora) : [],
  [yo?.demo, dia.dia, tareas, actividadesDelAmbito, ahora])
  const paginaCola = yo?.demo && dia.dia ? paginarTrabajoDemo(filasDemo, pedidoCola, yo.id, hoy, ahora)
    : cola.error ? undefined : cola.data
  const colaCargando = !yo?.demo && cola.error == null && paginaCola === undefined
  const colaCaida = !yo?.demo && cola.error != null

  const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
  const filas = useMemo<FilaDiaria[]>(() => {
    if (dia.dia === null) return []
    const todas = paginaCola?.items ?? []
    return cerrados.length === 0 ? todas : todas.filter((f) => !cerrados.includes(f.clave))
  }, [cerrados, dia.dia, paginaCola?.items])

  const pestanas = useMemo(() => pestanasDiarias(filas), [filas])
  const pedido: FiltroCola = filtroPedido ?? 'todo'
  const filtro: FiltroCola = paginaCola?.filtro ?? pedido
  const lista = filas
  const vista = {
    filas, pagina: paginaCola?.pagina ?? pagina, total: paginaCola?.total ?? 0,
    paginas: Math.max(1, Math.ceil((paginaCola?.total ?? 0) / FILAS_POR_PAGINA)),
  }
  const fila = filas.find((f) => f.clave === paginaCola?.elegido) ?? null

  useEffect(() => {
    if (navegacionVigente) return
    const contexto = leerContextoCola(yo?.id ?? '', hoy)
    const cambioActor = alcanceGuardado.current.split(':')[0] !== (yo?.id ?? '')
    alcanceGuardado.current = alcanceNav
    setFiltroPedido(contexto.filtro); setPagina(contexto.pagina); setElegido(contexto.elegido)
    setCerrados([])
    if (cambioActor) { setSesion(null); pedidos.current.clear() }
  }, [alcanceNav, hoy, navegacionVigente, yo?.id])
  useEffect(() => {
    if (!navegacionVigente || !yo || (!yo.demo && !paginaCola)) return
    guardarContextoCola(yo.id, hoy, { filtro, pagina: vista.pagina, elegido: fila?.clave ?? null })
  }, [fila?.clave, filtro, hoy, navegacionVigente, paginaCola, vista.pagina, yo])
  const proximo = () => ({ filtro, clave: paginaCola?.siguiente ?? null })

  // EL TELÉFONO NO VIAJA EN LA COLA. `cola_accion_v2_fn` devuelve del lead solo
  // id, nombre, etapa y analista; el número vive en el ámbito del store, que
  // desde la Fase 4e «sin topes» ya NO carga todos los leads: los trae por
  // demanda. Por eso en «Vencidas» —cuyos leads rara vez están cargados— no
  // salía «Llamar» hasta abrir la ficha, que es quien los traía (bug reportado
  // en producción el 20/09/2026). Aquí se piden en cuanto se eligen, sin
  // obligar al analista a dar un rodeo por la ficha.
  // Solo los LEADS: una fila de cliente no tiene lead que traer.
  const leadDeFila = fila?.tipo === 'lead' ? fila.lead_id : undefined
  useEffect(() => {
    const id = leadDeFila
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
  }, [asegurarLead, leadDeFila, leadsPorId])

  function elegir(f: FilaDiaria) {
    if (cerrados.includes(f.clave)) return
    const actual = sesionRef.current
    if (actual?.abierta) {
      toast.info(`Primero guarda o cierra el resultado de ${primerNombre(actual.lead.nombre_completo)}.`)
      return
    }
    // Sin formulario abierto (p. ej. volvió del marcador antes de 4 s), elegir a
    // otra persona abandona la llamada fijada.
    if (actual !== null) setSesion(null)
    focoPendiente.current = true
    setElegido(f.clave)
    requestAnimationFrame(() => {
      panelAhora.current?.scrollIntoView?.({ block: 'nearest' })
      nombreAhora.current?.focus()
    })
  }
  function cambiarFiltro(nuevo: FiltroCola) {
    focoPendiente.current = false
    setFiltroPedido(nuevo === 'todo' ? null : nuevo)
    setPagina(0)
    setElegido(null)
  }
  /** Se guarda ya acotada: si la lista encoge y vuelve a crecer, no salta sola. */
  function irAPagina(p: number) {
    focoPendiente.current = false
    setElegido(null)
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
    // La sesión de llamada es solo de LEADS: un cliente no tiene lead.
    if (filaActiva === null || filaActiva.tipo !== 'lead') return null
    const suyo = leadsPorId.get(filaActiva.lead_id)
    if (suyo === undefined) return null
    const nueva: SesionLlamada = { id: ++contadorSesion.current, fila: filaActiva, lead: suyo, tarea: undefined, abierta: false, siguiente: proximo() }
    setSesion(nueva)
    setElegido(filaActiva.clave)
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
    if (s === null) { if (filaActiva?.tipo === 'lead') void abrirLead(filaActiva.lead_id); return }
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
      // H-WA (09/10): la fila puede ser una tarea de WhatsApp o una reunión, y el resultado de una llamada solo cierra
      // una tarea de LLAMADA pendiente (el store y el servidor lo exigen). Se registra sin cerrar ninguna: esa tarea sigue
      // abierta y no se cambia por otra del lead.
      if (tarea !== null && (tarea.tipo !== 'llamada' || tarea.estado !== 'pendiente')) tarea = null
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
    // La intención de contacto que abrió esta tarjeta (un tap en «Llamar» o el
    // enlace del celular) termina aquí: mientras seguía abierta, la siguiente
    // llamada esperaba en la cola en vez de abrirse encima (F1.1.3).
    cerrarIntencionesDe(yo?.id, actual.lead.id)
    setSesion(null)
    setElegido(actual.fila.clave)
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
  async function alGuardar(siguiente = proximo()) {
    setFiltroPedido(siguiente.filtro === 'todo' ? null : siguiente.filtro)
    setElegido(siguiente.clave)
    setPagina(0)
    // Una clave nueva de consulta nace DESPUÉS de confirmar la escritura.
    // Ninguna foto anterior (ni de otro filtro) puede volver a proponer al
    // gestionado. La primera respuesta nueva manda, incluso si hubo deshacer
    // u otra gestión desde la ficha: no queda una máscara de negocio local.
    setRevisionCola((r) => r + 1)
    recogerFocoSuelto()
    await Promise.allSettled([dia.recargar()])
  }

  /**
   * Dos cuadros después (el diálogo restaura primero su foco): si el foco quedó
   * suelto —el botón que lo tenía se desmontó al cambiar de persona— o en las
   * acciones que acaban de guardar, se anuncia a la persona nueva. Si el
   * analista ya se movió a otro sitio, no se le roba el foco.
   */
  function recogerFocoSuelto() {
    focoPendiente.current = true
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const activo = document.activeElement
      const suelto = activo === null || activo === document.body || activo === document.documentElement
        || (activo instanceof HTMLElement && activo.closest('[data-accion-panel]') !== null)
      if (suelto) (nombreAhora.current ?? encabezado.current)?.focus()
    }))
  }
  // Con una página remota lenta, los dos cuadros anteriores enfocan el título.
  // Cuando llega la persona siguiente terminamos el relevo, sin quitarle el
  // foco a quien ya se haya movido a otro control durante la espera.
  useEffect(() => {
    if (!focoPendiente.current || colaCargando || colaCaida || sesion !== null) return
    const cuadro = requestAnimationFrame(() => {
      const activo = document.activeElement
      if (activo === document.body || activo === document.documentElement || activo === encabezado.current) {
        (nombreAhora.current ?? encabezado.current)?.focus()
      }
      focoPendiente.current = false
    })
    return () => cancelAnimationFrame(cuadro)
  }, [colaCargando, colaCaida, fila?.clave, sesion])
  /**
   * «Registrar resultado» de una tarea de CLIENTE: el cierre de tarea de
   * siempre (postventa si es de un inversionista), sobre la tarea del ámbito.
   * La cola no trae la tarea completa y la del store es la misma que ya cierran
   * la Agenda y «Hoy»; si no está, se dice y no se inventa otra.
   */
  function registrarCliente(f: FilaCliente) {
    const tarea = tareas.find((t) => t.id === f.tarea_id && t.estado === 'pendiente' && t.activo)
    if (tarea === undefined) {
      toast.error('No encontramos esta gestión pendiente en tu agenda. Recarga la página para verla.')
      return
    }
    setElegido(f.clave)
    cierreAbierto.current = tarea.id
    setCierreCliente({ fila: f, tarea })
  }
  /**
   * El diálogo de cierre avisa IGUAL al guardar que al cancelar, y puede avisar
   * más de una vez: solo cuenta el primer aviso del diálogo abierto. Lo que se
   * hizo lo dice el STORE en el commit siguiente (efecto de abajo), no una
   * página de la cola: el cierre de una tarea de perfil la marca cerrada en el
   * store antes de avisar (tras confirmarlo el servidor) y el de postventa
   * relee el ámbito antes de avisar (Codex, 29/09/2026: la ausencia en una
   * página no acredita un guardado). El «siguiente» se calcula AQUÍ, con la
   * lista que el analista estaba mirando, como al guardar un lead.
   */
  function alCerrarCliente(abierto: { fila: FilaCliente; tarea: Tarea }) {
    if (cierreAbierto.current !== abierto.tarea.id) return
    cierreAbierto.current = null
    setCierreCliente(null)
    setCierreAvisado({ fila: abierto.fila, venceAntes: abierto.tarea.vence_en,
      siguiente: proximo() })
  }
  // Lo que se hizo lo dice el STORE, y se decide en cuanto lo refleja. No se
  // supone que eso ya esté en el commit del aviso (la postventa relee el ámbito
  // y React puede aplicarlo después): se vigila `tareas` durante un margen
  // corto (Codex, 29/09/2026). Tres salidas:
  //  · la tarea ya no está pendiente, o se reprogramó FUERA de hoy → sale de la
  //    cola del día: se tapa hasta que la cola ya no la traiga, «Ahora» pasa a
  //    la fila de detrás (si el analista no eligió a otra persona mientras) y
  //    el foco no se pierde;
  //  · se reprogramó DENTRO de hoy → sigue en la cola: se relee para su hora;
  //  · no cambia nada en el margen → se canceló: nada que hacer (el diálogo ya
  //    devolvió el foco a «Registrar resultado»).
  // Sin esperas de red antes de cambiar de persona: una relectura tardía no
  // puede pisar una elección posterior.
  const recargarDia = dia.recargar
  const releerCola = cola.refetch
  const demo = yo?.demo === true
  const elegidoAhora = useRef(elegido)
  elegidoAhora.current = elegido
  useEffect(() => {
    if (cierreAvisado === null) return
    const { fila: f, siguiente, venceAntes } = cierreAvisado
    const enStore = tareas.find((t) => t.id === f.tarea_id)
    if (enStore !== undefined && enStore.estado === 'pendiente' && enStore.activo) {
      const vence = Date.parse(enStore.vence_en)
      if (vence === Date.parse(venceAntes)) return
      setCierreAvisado(null)
      if (Number.isFinite(vence) && vence < finDelDiaLima(Date.now())) {
        if (!demo) void releerCola()
        return
      }
    } else {
      setCierreAvisado(null)
    }
    if (!demo) setCerrados((c) => (c.includes(f.clave) ? c : [...c, f.clave]))
    if (elegidoAhora.current === f.clave) {
      setFiltroPedido(siguiente.filtro === 'todo' ? null : siguiente.filtro)
      setElegido(siguiente.clave)
      recogerFocoSuelto()
    }
    if (!demo) void Promise.allSettled([recargarDia(), releerCola()])
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `recogerFocoSuelto` solo lee refs; su identidad nueva en cada render no cambia lo que hace
  }, [cierreAvisado, tareas, demo, recargarDia, releerCola])
  // El margen se cierra solo: pasado ese tiempo sin cambios, fue una cancelación.
  useEffect(() => {
    if (cierreAvisado === null) return
    const vigilado = cierreAvisado
    const t = window.setTimeout(() => setCierreAvisado((c) => (c === vigilado ? null : c)), MARGEN_CIERRE_MS)
    return () => window.clearTimeout(t)
  }, [cierreAvisado])
  // La máscara de un cliente que salió de la cola se retira cuando una lectura
  // VÁLIDA de la cola ya no lo trae; mientras la cola esté caída o vieja, sigue.
  useEffect(() => {
    if (paginaCola === undefined) return
    setCerrados((c) => {
      const quedan = c.filter((x) => paginaCola.items.some((i) => i.clave === x))
      return quedan.length === c.length ? c : quedan
    })
  }, [paginaCola])
  async function deshacer(d: Descartado) {
    if (deshaciendo !== null) return
    setDeshaciendo(d.actividad_id)
    try {
      const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
      await deshacerResultadoLlamada(d.actividad_id)
      await Promise.allSettled([dia.recargar(), ...(yo?.demo ? [] : [cola.refetch()])])
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

  /** La tarea de un cliente tal como la tiene el ámbito (la que cierran Agenda y «Hoy»). */
  function tareaDeCliente(f: FilaCliente): Tarea | null {
    return tareas.find((t) => t.id === f.tarea_id) ?? null
  }
  const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
  const filaActiva = colaCargando ? null : fila
  // Lo que pinta la tarjeta: la sesión, si hay una; si no, la fila viva.
  const filaTarjeta = sesion?.fila ?? filaActiva
  const leadTarjeta = sesion?.lead ?? (filaActiva?.tipo === 'lead' ? leadsPorId.get(filaActiva.lead_id) ?? null : null)
  const posicionLocal = filaTarjeta === null ? -1 : lista.findIndex((f) => f.clave === filaTarjeta.clave)
  const posicionTarjeta = posicionLocal < 0 ? 0 : posicionLocal + 1 + vista.pagina * FILAS_POR_PAGINA
  const fecha = FECHA_LARGA.format(new Date(ahora))
  const total = paginaCola?.totales.todo.total ?? 0
  const conteoCola = colaCaida ? '?' : String(total)

  const tarjetaAhora = (
    <PanelAhora fila={filaTarjeta} lead={leadTarjeta}
      sinConversacionDias={dia.dia?.sin_conversacion_dias ?? ultimoDia.current?.sin_conversacion_dias ?? 0} ahora={ahora} cargando={colaCargando && sesion === null} colaCaida={colaCaida}
      filtroVacio={filaTarjeta === null && total > 0}
      seccionRef={panelAhora} nombreRef={nombreAhora}
      posicion={posicionTarjeta} total={vista.total}
      vueltaCompleta={paginaCola?.vuelta_completa === true && vista.total > 0}
      cargandoLead={filaTarjeta?.tipo === 'lead' && cargandoLead === filaTarjeta.lead_id} abriendoPanel={abriendoPanel}
      // «Llamar» FIJA a la persona: nace la sesión de llamada. Si mientras
      // marca (en el celular, con el CRM en segundo plano) entra un lead
      // más urgente, la tarjeta no cambia y el resultado va a ESTA persona.
      onLlamar={() => { iniciarSesion() }}
      onRegistrar={() => { void abrirRegistro() }}
      onAbrirFicha={() => {
        if (filaTarjeta?.tipo === 'lead') void abrirLead(filaTarjeta.lead_id)
        else if (filaTarjeta?.inversionista_id) abrirInversionista(tareaDeCliente(filaTarjeta)?.inversionista_canonico_id ?? filaTarjeta.inversionista_id)
      }}
      onRegistrarCliente={() => { if (filaTarjeta?.tipo === 'cliente') registrarCliente(filaTarjeta) }}
      tareaCliente={filaTarjeta?.tipo === 'cliente' ? tareaDeCliente(filaTarjeta) : null}
      // Con el foco dentro, «Ahora» deja de cambiar sola: el refresco de cada
      // minuto no puede cambiarle la persona a quien la está leyendo (a11y).
      onEnfoque={() => { if (elegido === null && sesion === null && filaActiva !== null) setElegido(filaActiva.clave) }}
      registro={sesion?.abierta ? (() => {
        const { id: idSesion, lead: leadSesion } = sesion
        return <RegistroResultadoTarjeta key={idSesion} lead={leadSesion} tarea={sesion.tarea ?? null}
          onClose={() => cerrarSesion(idSesion)} onGuardado={() => void alGuardar(sesion.siguiente)} />
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
            <AccesoGestionesClientes dia={hoy} autores={yo ? [yo.id] : null} />
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
                No se pudo leer la cola del servidor. Pulsa «Actualizar» para recuperar tu lugar.
              </p>
            )}


            <FranjaCifras etiqueta="Captación de leads" cifras={cifrasDelDia(dia.dia)} />
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
                panelEnfocable={vistaVisible !== 'cola'}
                valor={vistaVisible}
                onCambio={setVistaDerecha}
                pestanas={[
                  { valor: 'cola', etiqueta: 'Cola de hoy', extra: `· ${conteoCola}` },
                  { valor: 'actividad', etiqueta: 'Mi actividad' },
                  { valor: 'seguimiento', etiqueta: 'Mi seguimiento', ...(dia.dia.compromisos_total > 0 ? { extra: `· ${dia.dia.compromisos_total}` } : {}) },
                  // «Celular» y no «Llamadas del celular»: con cuatro pestañas la barra ya no entra en la tarjeta (medido el
                  // 05/10: 586 px pedidos en 407). El panel conserva el título largo.
                  ...(celular ? [{ valor: 'celular' as const, etiqueta: 'Celular', ...(celular.pendientes.length > 0 ? { extra: `· ${celular.pendientes.length}` } : {}) }] : []),
                ]}
                // Si aun así no entra, la barra se desplaza sin la barra nativa (las flechas del teclado ya cambian de pestaña).
                className={cn('flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:px-[18px] [&>[role=tablist]]:pt-1.5 [&>[role=tablist]]:[scrollbar-width:none] [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm [&>[role=tablist]>[role=tab]>span]:text-sm',
                  celular ? '[&>[role=tablist]]:gap-4' : '[&>[role=tablist]]:gap-[22px]')}
                clasePanel={vistaVisible === 'cola' ? 'flex min-h-0 flex-1 flex-col' : 'ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2'}
              >
                {vistaVisible === 'celular' && celular ? (
                  <LlamadasCelular estadoPendientes={celular.estadoPendientes} estadoResueltas={celular.estadoResueltas} pendientes={celular.pendientes} resueltas={celular.resueltas} ahora={ahora} ocupado={celular.ocupado}
                    busqueda={{ demo: yo?.demo === true, leadsLocales: ambito.leads }}
                    onRegistrar={registrarDesdePestana} onCorregir={corregirDesdePestana} onElegirLead={celular.elegirLead} onDescartar={celular.descartar}
                    onBuscarResultados={celular.buscarResultados} onUnir={celular.unir}
                    onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
                ) : vistaVisible === 'cola' ? (
                  <ColaDeHoy
                    idBase={id} pestanas={pestanas} trabajo={paginaCola && { ...paginaCola, items: paginaCola.items.filter((f) => !cerrados.includes(f.clave)) }} filtro={filtro} onFiltro={cambiarFiltro}
                    pagina={vista.pagina} onPagina={irAPagina}
                    elegido={filaActiva?.clave ?? null} onElegir={elegir}
                    ahora={ahora} cargando={colaCargando} colaCaida={colaCaida}
                    sinConversacionDias={dia.dia.sin_conversacion_dias}
                  />
                ) : vistaVisible === 'actividad' ? (
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
      <CerrarTareaDialog tarea={cierreCliente?.tarea ?? null}
        onCerrar={() => { if (cierreCliente) alCerrarCliente(cierreCliente) }} />
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
function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaida, filtroVacio, vueltaCompleta, onLlamar, onRegistrar, onAbrirFicha, onRegistrarCliente, tareaCliente, onEnfoque, seccionRef, nombreRef, cargandoLead, abriendoPanel, posicion, total, registro }: {
  fila: FilaDiaria | null
  lead: Lead | null
  sinConversacionDias: number
  ahora: number
  cargando: boolean
  colaCaida: boolean
  /** La lista a la vista está vacía pero la cola no: el vacío es del filtro. */
  filtroVacio: boolean
  vueltaCompleta: boolean
  cargandoLead: boolean
  abriendoPanel: boolean
  posicion: number
  total: number
  onLlamar: () => void
  onRegistrar: () => void
  onAbrirFicha: () => void
  /** Fila de CLIENTE: abre el cierre de su tarea. */
  onRegistrarCliente: () => void
  /** Fila de CLIENTE: su tarea en el ámbito, o null si todavía no llegó. */
  tareaCliente: Tarea | null
  /** El foco entró en la tarjeta. */
  onEnfoque: () => void
  seccionRef: RefObject<HTMLElement | null>
  nombreRef: Ref<HTMLButtonElement>
  /** El resultado de la llamada en curso: ocupa el lugar de las acciones. */
  registro?: ReactNode
}): JSX.Element {
  const id = useId()
  const etapa = fila === null || fila.tipo === 'cliente' ? null : ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
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
                : vueltaCompleta ? 'Vuelta completada. Puedes revisar los gestionados en la lista; los reintentos volverán a su hora.'
                : filtroVacio ? 'No hay pendientes en esta página. Puedes revisar una fila o volver a «Todo».'
                  : 'Nada pendiente ahora. Cuando entre un lead nuevo aparecerá aquí.'}
          </p>
        ) : fila.tipo === 'cliente' ? (
          <CuerpoCliente key={fila.clave} fila={fila} tarea={tareaCliente} ahora={ahora} nombreRef={nombreRef}
            onRegistrar={onRegistrarCliente} onAbrirFicha={onAbrirFicha} />
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
              {textoGestion(fila) && <p className="text-xs font-semibold text-[var(--accent-press)]">{textoGestion(fila)}</p>}
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
          Pendientes primero. Al guardar, este lead pasa al final y continúas con el siguiente.
        </p>}
        <span aria-hidden="true" className="mx-auto mb-2 block h-1 w-24 shrink-0 rounded-full bg-border-strong" />
      </section>
    </div>
  )
}

const PILDORA = 'inline-flex h-11 w-full cursor-pointer items-center justify-center gap-2 rounded-full text-sm font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring [&_svg]:size-[18px]'
const PILDORA_PRINCIPAL = cn(PILDORA, 'bg-accent text-white hover:bg-[var(--accent-press)]')
const PILDORA_SECUNDARIA = cn(PILDORA, 'border border-border bg-card text-[13px] font-semibold text-foreground hover:border-border-strong hover:bg-muted')

/**
 * «Ahora» con una tarea de un CLIENTE de la cartera (cola v3). Lo mismo que un
 * lead —quién es, cuánto le queda y qué hacer—, sin lo que un cliente no
 * tiene: etapa, historial de lead y sesión de llamada. El teléfono NO viaja en
 * la cola: sale de la ficha autorizada del cliente, y solo si se le puede
 * contactar. Sin ficha (cliente solo del portal) no se ofrece un enlace falso.
 */
function CuerpoCliente({ fila, tarea, ahora, nombreRef, onRegistrar, onAbrirFicha }: {
  fila: FilaCliente
  tarea: Tarea | null
  ahora: number
  nombreRef: Ref<HTMLButtonElement>
  onRegistrar: () => void
  onAbrirFicha: () => void
}): JSX.Element {
  const { yo } = useAuth()
  // Como el «Llamar» de un lead (`AccionesContacto`): en el celular marca; en
  // la laptop no hay radio, así que copia el número y abre el registro.
  const puedeMarcar = usePuedeMarcar()
  const conFicha = fila.inversionista_id !== null
  const idFicha = !yo || yo.demo || fila.inversionista_id === null ? '' : tarea?.inversionista_canonico_id ?? fila.inversionista_id
  const contacto = useContactoInversionista(yo?.id ?? '', idFicha)
  const tiempo = tiempoDeFila(fila, ahora)
  // Fail-closed: con la relectura caída no se pinta el número guardado de antes.
  const telefono = contacto.error == null && contacto.data?.contactar === true ? contacto.data.telefono : null
  // Una sola fuente para marcar (`lib/telefono`): un número que no sirve no se ofrece.
  const tel = enlaceTel(telefono)
  const tipoTarea = tarea === null ? null : TIPOS_TAREA.find((t) => t.k === tarea.tipo)?.label ?? null
  // El aviso solo habla (región viva) de lo que CAMBIA con la consulta; lo fijo
  // —sin ficha, demo— es texto normal y no repite lo que ya dice el nombre.
  const aviso: { texto: string; vivo: boolean } | null = tel !== null ? null
    : !conFicha ? { texto: 'Su número no está disponible aquí: aún no tiene ficha en tu cartera.', vivo: false }
      : idFicha === '' ? { texto: 'Su número está en su ficha.', vivo: false }
        : contacto.error != null ? { texto: 'No se pudo traer su número. Ábrelo en su ficha.', vivo: true }
          : contacto.data === undefined ? { texto: 'Buscando su número…', vivo: true }
            : contacto.data.contactar === false ? { texto: 'Este cliente no se puede contactar ahora. Revisa su ficha.', vivo: true }
              : { texto: 'Su ficha no tiene un número válido.', vivo: true }
  // El registro se abre YA, sobre esta persona; el portapapeles va detrás y no
  // se espera: si tardara, el analista podría haber elegido a otra y se le
  // abriría el cierre equivocado (Codex, 29/09/2026).
  function copiarYRegistrar(numero: string) {
    onRegistrar()
    const copia = navigator.clipboard?.writeText(numero) ?? Promise.reject(new Error('sin portapapeles'))
    void copia.then(
      () => { toast.success(`Número copiado: ${numero} — márcalo desde tu celular`) },
      () => { toast.info(`Marca ${numero} desde tu celular`) },
    )
  }
  return (
    <div className="ac-scroll flex min-h-0 flex-1 flex-col gap-3.5 overflow-y-auto px-[18px] py-5">
      <div className="flex min-w-0 flex-col gap-0.5">
        <button ref={nombreRef} type="button" onClick={() => { if (conFicha) onAbrirFicha() }}
          aria-disabled={conFicha ? undefined : true}
          aria-label={conFicha ? `Abrir la ficha de ${fila.nombre_completo}` : `${fila.nombre_completo}, sin ficha en tu cartera`}
          className="self-start rounded-md text-left text-2xl font-extrabold leading-tight tracking-[-0.02em] text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:hover:no-underline">
          {fila.nombre_completo}
        </button>
        <p className="text-[13px] text-[var(--muted-foreground-strong)]">Cliente de tu cartera</p>
      </div>
      <div className="flex flex-col items-start gap-2 rounded-xl bg-muted/70 px-3.5 py-3">
        <Badge className="min-h-[22px] py-0 text-[11.5px]" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
        <p className="text-[13px] leading-snug text-foreground/80">
          {tarea === null ? 'No encontramos esta gestión en tu agenda. Recarga la página para verla.'
            : `${tipoTarea ?? 'Gestión'} · ${presentarCitas(tarea.titulo)}`}
        </p>
      </div>
      <div className="sticky bottom-0 mt-auto flex flex-col gap-3 bg-card pt-1">
        {tel !== null && telefono !== null && <p className="text-center text-2xl font-extrabold tracking-[0.02em] tabular-nums text-primary">{telefono}</p>}
        {aviso !== null && (aviso.vivo
          ? <p role="status" className="text-[13px] leading-snug text-[var(--muted-foreground-strong)]">{aviso.texto}</p>
          : <p className="text-[13px] leading-snug text-[var(--muted-foreground-strong)]">{aviso.texto}</p>)}
        <div className="flex flex-col gap-2.5">
          {tel !== null && telefono !== null && (puedeMarcar
            ? <a href={tel} className={PILDORA_PRINCIPAL} aria-label={`Llamar a ${fila.nombre_completo}`}><Phone aria-hidden /> Llamar</a>
            : (
              <button type="button" onClick={() => { copiarYRegistrar(telefono) }} className={PILDORA_PRINCIPAL}
                aria-label={`Llamar a ${fila.nombre_completo}: copia su número y abre el registro`}>
                <Phone aria-hidden /> Llamar
              </button>
            ))}
          <button type="button" onClick={onRegistrar} className={tel !== null ? PILDORA_SECUNDARIA : PILDORA_PRINCIPAL}
            aria-label={`Registrar resultado de ${fila.nombre_completo}`}>
            <ClipboardList aria-hidden /> Registrar resultado
          </button>
          {conFicha && (
            <button type="button" onClick={onAbrirFicha} className={PILDORA_SECUNDARIA} aria-label={`Ver la ficha del cliente ${fila.nombre_completo}`}>
              Ver la ficha del cliente
            </button>
          )}
        </div>
      </div>
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
