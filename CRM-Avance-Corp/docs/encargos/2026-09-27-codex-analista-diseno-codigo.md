ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado), TEST GAPS, REGRESSION RISKS,
RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como hipótesis lo no
demostrado. Omite secciones vacías.

# Encargo: REFUTAR el CÓDIGO del rediseño de «Mi día» del analista — LEVEL 3 en la etapa 3

Segunda y última consulta de esta tarea (la primera fue sobre el PLAN: BLOCK con 6 hallazgos,
todos aceptados e incorporados; ver «Plan v2» abajo). Ahora hay código en dos commits locales:
`160fdd00` (etapas 1 y 2: aspecto y orden, con el diálogo de resultado intacto) y `28cf6438`
(etapa 3: el resultado se registra DENTRO de la tarjeta «Ahora»). Busca fallos reales; si algo
está bien, no lo menciones.

## Qué refutar (prioridad)
1. **Invariante P0 de la etapa 3:** el resultado se escribe SIEMPRE sobre la persona a la que se
   llamó. Revisa `SesionLlamada`, `iniciarSesion`, `abrirRegistro`, `cerrarSesion`, `elegir`,
   `alGuardar` en `analista.tsx` y el orden `onClose` → `onGuardado` de `enviar` en
   `registrar-resultado.tsx`. Casos: laptop (Llamar copia y abre), celular (`tel:` y pregunta al
   volver ≥4 s desde la MISMA instancia de `AccionesContacto`, que debe seguir montada porque la
   tarjeta pinta la sesión con la misma `key`), menú «··· → Registrar resultado», tarea
   autoritativa resuelta por id que llega tarde, refetch de día/cola con el formulario abierto,
   dos guardados rápidos, `sinConfirmar` y reintento, cambio de filtro con sesión, elegir otra
   fila con/sin formulario abierto, lead que desaparece de la cola durante la sesión.
2. **El diálogo de siempre** (ficha del lead, Hoy, colas, composer) NO debe cambiar de contrato
   tras extraer `useRegistroResultado` + `CamposResultado`: props, orden de callbacks, Escape
   (el `Dialog.onClose` ahora mira `c.procesando` en vez del ref `enviando`), atajos acotados al
   `[role=dialog]`, ids de los campos (antes fijos, ahora `useId`).
3. **Contrato de teclado/foco de la tarjeta:** atajos 1–7 solo con el foco dentro y fuera de
   campos; Escape = cerrar sin registrar salvo `procesando`; foco inicial al primer resultado;
   al cancelar el foco vuelve a «Llamar»; al guardar va al nombre del siguiente (`alGuardar`).
4. **Filtro «Todo»** (`FiltroCola` separado de `fila.grupo`), `siguienteTrasGuardar`, y que con
   un GRUPO a la vista la vista siga al elegido si el refresco lo cambia de grupo.
5. Regresiones por el cambio de navegación del contenedor (`gestion-diaria.tsx`), la versión
   `compacto` de `RegistroActividad`, las variantes de `Tabs` y el `Avatar` relleno.
6. Accesibilidad y robustez visual: chips de 11,5 px con tokens de texto, objetivos de 36 px
   (pastillas) y 32 px (paginador), `overflow-clip` en la tarjeta, alto fijo `lg:h-[calc(100svh-7rem)]`.

## Decisiones del dueño (NO son hallazgos)
- Aplicar el diseño «Gestión diaria pantallas» con los colores del CRM (navy #111e3d, azul #2563eb,
  sin verde), menú navy intacto.
- **Escala tipográfica y aire del diseño** (Miguel 27/09: «hay demasiada letra, no está respetando el
  diseño… la proximidad está mal»): sustituye el piso de 16 px del 20/09 en esta pantalla.
- Resultado dentro de «Ahora» (sustituye su decisión del 21/09 de tenerlo tras «···»).
- «Descartados» dentro de «Mi actividad»; 8 filas por página; un solo acceso «Seguimiento completo ›»
  en la cabecera del analista (la vuelta al resumen sigue en la barra de secciones de la cola).

## Plan v2 aprobado (resumen)
A1 piezas comunes · A2 aspecto y orden (diálogo intacto, `FiltroCola`, estados vivos conservados,
«Llamar» fija a la persona, horizontal desde `lg`) · A3 resultado dentro de «Ahora» con sesión
inmutable, contrato de teclado propio y lógica compartida en un hook con dos adaptadores.

## Evidencia de verificación (ejecutada por el PRIMARY)
- `npm run check` (oxlint + typecheck + vitest con cobertura): PASS, 303 archivos, 4.504 pruebas,
  statements 77,48 %. Avisos de lint preexistentes en otros archivos.
- E2E en Docker (etapas 1–2, commit 160fdd00): PASS 43/43 (`gestion-diaria-analista`, `gestion-diaria`,
  `gestion-diaria-resultado`, `gestion-diaria-cola`, `sla-operacion`).
- E2E en modo depuración tras la etapa 3 (`gestion-diaria-analista`, `gestion-diaria-resultado`):
  PASS 15/15. La corrida en Docker de la etapa 3 está pendiente.
- Pruebas unitarias nuevas de la etapa 3 (nombres): «abierto el resultado, un refresco que trae a
  alguien más urgente NO cambia la tarjeta ni la persona»; «abierto el resultado, elegir otra fila no
  cambia de persona: avisa»; «Cerrar sin registrar vuelve a la tarjeta normal de la MISMA persona»;
  «una tarea que llega TARDE de una llamada ya abandonada no abre el resultado»; «tras Llamar,
  cambiar de grupo NO cambia la persona»; tarjeta: 7 resultados en una línea con foco, atajos solo
  dentro, Escape, Escape bloqueado mientras guarda, guardar sobre el lead de la tarjeta con
  `cerrar` antes de `guardado`.


## CÓDIGO (archivos completos tras los dos commits; numeración real)

### `screens/gestion-diaria/analista.tsx`
```tsx
   1  // Gestión Diaria · Fase 3 — «Mi día» del analista. Responde una sola pregunta:
   2  // ¿a quién llamo AHORA? La cola sale de `crm.cola_accion_v2_fn` (la misma del
   3  // mundo SLA) y el resto del día —marcador, compromisos, señales por lead y los
   4  // descartes con su «Deshacer»— de `crm.gestion_diaria_analista_fn`. Aquí no se
   5  // calcula negocio: se ORDENA (`ordenarColaDiaria`, función pura probada) y se
   6  // presenta. Al guardar un resultado, la pantalla salta a la fila siguiente.
   7  //
   8  // «Hoy» NO cambia: sigue siendo «las 3 cosas de ahora» (decisión de Miguel).
   9  // Esta pantalla es la cola COMPLETA del día, y las dos comparten el primer
  10  // ítem: el lead sin primer intento manda en ambas (test compartido).
  11  //
  12  // DISEÑO (27/09/2026, Miguel: «que prevalezca la organización del HTML y lo
  13  // limpio que se ve, con los colores del CRM»). La pantalla cabe entera, sin
  14  // bajar, en un monitor o laptop (desde `lg`):
  15  //   · Cabecera: la pregunta, el corte, la fecha y las dos secciones del módulo.
  16  //   · Franja de 4 cifras: llamadas, contestaron, contacto con su nivel, citas.
  17  //     Reemplaza el botón-resumen «Mi actividad» de la cabecera.
  18  //   · «Ahora» (izquierda), con aire de celular: el ÚNICO lead que toca, su
  19  //     nombre grande, el tiempo que le queda EN PALABRAS y «Llamar».
  20  //   · Tarjeta con pestañas (derecha): «Cola de hoy» (filtros en pastilla, con
  21  //     «Todo» primero), «Mi actividad» (barras por hora, descartes y registro del
  22  //     día) y «Mi seguimiento» (compromisos desde mañana). Lo que antes eran
  23  //     plegables apilados abajo ahora son pestañas: todo en horizontal.
  24  // Densidad: piso de 16 px (queja de los analistas del 20/09/2026). Un solo
  25  // rojo: queda reservado a lo vencido («Se pasó hace 45 min»); la severidad se
  26  // DICE con esas mismas palabras, nunca solo con el color.
  27  // RESULTADO DENTRO DE «AHORA» (etapa 3, 27/09/2026): tras «Llamar», los 7
  28  // resultados y sus pasos aparecen en la misma tarjeta, sin ventana encima. La
  29  // invariante que manda (hallazgo P0 de Codex): el resultado va SIEMPRE a quien
  30  // se llamó. Al pulsar «Llamar» nace una SESIÓN inmutable —la fila, el lead y su
  31  // tarea autoritativa— y la tarjeta, el guardado y el reintento operan solo
  32  // sobre ella, aunque la cola se refresque o cambie de orden; una respuesta
  33  // tardía de una sesión ya cerrada se ignora.
  34  // Integración F4 (21/09): conserva los arreglos publicados de caché parcial,
  35  // tarea autoritativa, paginación y carreras.
  36  import { useEffect, useId, useMemo, useRef, useState, type JSX, type ReactNode, type Ref } from 'react'
  37  import { CalendarClock, ClipboardList, MoreHorizontal, Phone, RefreshCw, RotateCcw } from 'lucide-react'
  38  import { toast } from 'sonner'
  39  import { useAuth } from '@/lib/auth-context'
  40  import { useAhora } from '@/lib/ahora'
  41  import { useCRMData, usePanelesActions } from '@/lib/store-context'
  42  import { ETAPA_INFO, type Etapa, type Lead, type Tarea } from '@/lib/tipos'
  43  import { tareaQueCierra } from '@/lib/contacto-tarea'
  44  import { presentarCitas } from '@/lib/terminologia'
  45  import {
  46    COLOR_NIVEL, ETIQUETA_NIVEL, cuandoLimaDe, detalleDeFila, filasDelFiltro, filasDiariasDemo,
  47    horaLimaDe, ordenarColaDiaria, paginaDeFilas, pestanasDiarias, siguienteTrasGuardar, tiempoDeFila,
  48    type Descartado, type DiaAnalista, type FilaDiaria, type FiltroCola,
  49  } from '@/lib/gestion-diaria-analista'
  50  import { useDiaAnalista } from '@/data/gestion-diaria-queries'
  51  import { useColaSlaPagina } from '@/data/sla-operacion-queries'
  52  import { AccionesContacto } from '@/components/app/contacto'
  53  import { RegistroResultadoTarjeta } from '@/components/gestion-diaria/registrar-resultado'
  54  import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
  55  import { BarrasPorHora } from '@/components/gestion-diaria/barras-por-hora'
  56  import { FranjaCifras, type CifraDelDia } from '@/components/gestion-diaria/franja-cifras'
  57  import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
  58  import { Badge } from '@/components/ui/badge'
  59  import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
  60  import { Tabs } from '@/components/ui/tabs'
  61  import { fechaLima } from '@/lib/agenda-derivada'
  62  import { primerNombre } from '@/lib/format'
  63  import { cn } from '@/lib/utils'
  64  import { ColaDeHoy, FILAS_POR_PAGINA } from '@/components/gestion-diaria/cola-de-hoy'
  65  
  66  const LIMITE_COLA = 100
  67  type VistaDerecha = 'cola' | 'actividad' | 'seguimiento'
  68  
  69  /**
  70   * La llamada en curso: a quién se llamó, fijado al pulsar «Llamar» (antes de
  71   * copiar el número o de salir al marcador). Nada de esto se recalcula con la
  72   * cola: es una foto.
  73   */
  74  interface SesionLlamada {
  75    id: number
  76    fila: FilaDiaria
  77    lead: Lead
  78    /** `undefined` mientras se resuelve la tarea autoritativa; `null` = sin tarea. */
  79    tarea: Tarea | null | undefined
  80    /** El formulario del resultado está a la vista en la tarjeta. */
  81    abierta: boolean
  82  }
  83  const FECHA_LARGA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })
  84  
  85  export function GestionDiariaAnalista({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
  86    const { yo } = useAuth()
  87    const ahora = useAhora()
  88    const { ambito, tareasDe, asegurarLead, obtenerTareaParaRevision } = useCRMData()
  89    const { abrirLead } = usePanelesActions()
  90    const id = useId()
  91  
  92    // TODO el estado vive AQUÍ, por encima de la cascada de carga/error: el hook
  93    // del día es fail-closed (un refetch fallido devuelve `null`) y, si el filtro,
  94    // la pestaña o la persona elegida colgaran del subárbol, un parpadeo de red le
  95    // borraría al analista dónde estaba.
  96    const [sesion, setSesionEstado] = useState<SesionLlamada | null>(null)
  97    // Espejo síncrono de la sesión: las respuestas asíncronas comparan contra él
  98    // para saber si su sesión sigue viva (el estado de React llega un render tarde).
  99    const sesionRef = useRef<SesionLlamada | null>(null)
 100    const contadorSesion = useRef(0)
 101    const setSesion = (s: SesionLlamada | null) => { sesionRef.current = s; setSesionEstado(s) }
 102    const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
 103    const [elegido, setElegido] = useState<string | null>(null)
 104    // El filtro que pidió el analista; `null` = «Todo», el de entrada.
 105    const [filtroPedido, setFiltroPedido] = useState<FiltroCola | null>(null)
 106    const [pagina, setPagina] = useState(0)
 107    const [vistaDerecha, setVistaDerecha] = useState<VistaDerecha>('cola')
 108    // Los leads cuyo resultado se acaba de guardar: siguen en la cola hasta que el
 109    // servidor conteste, y sin esto «Ahora» volvería a proponer al que ya cerraste.
 110    // Es un CONJUNTO y no un solo id: registrar dos seguidos antes de que vuelva
 111    // el primero hacía que el `finally` de uno destapara al otro.
 112    const [cerrados, setCerrados] = useState<readonly string[]>([])
 113    const nombreAhora = useRef<HTMLButtonElement>(null)
 114    const tituloDescartes = useRef<HTMLHeadingElement>(null)
 115    const panelAhora = useRef<HTMLElement>(null)
 116    const encabezado = useRef<HTMLHeadingElement>(null)
 117    // Leads que ya se pidieron al servidor: `asegurarLead` no está deduplicado y
 118    // la fila elegida se recalcula con el reloj de cada minuto.
 119    const pedidos = useRef(new Set<string>())
 120    const [cargandoLead, setCargandoLead] = useState<string | null>(null)
 121    const [abriendoPanel, setAbriendoPanel] = useState(false)
 122  
 123    const dia = useDiaAnalista(null, null)
 124    // La cola del día: la misma fuente que «Seguimiento comercial», sin filtros.
 125    const cola = useColaSlaPagina({ senal: 'todas', etapa: null, analista_id: null }, null, LIMITE_COLA, !yo?.demo)
 126    const paginaCola = cola.error ? undefined : cola.data
 127    // La cola y el día son DOS consultas: mientras la cola no ha llegado, decir
 128    // «no tienes nada pendiente» sería mentir (solo estarían los sin conversación).
 129    const colaCargando = !yo?.demo && cola.error == null && paginaCola === undefined
 130    const colaCaida = !yo?.demo && cola.error != null
 131    const hayMas = paginaCola?.hay_mas === true
 132  
 133    const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
 134    const filas = useMemo<FilaDiaria[]>(() => {
 135      if (dia.dia === null) return []
 136      const todas = yo?.demo
 137        ? filasDiariasDemo(dia.dia.cartera, ahora, dia.dia.dia)
 138        : ordenarColaDiaria(paginaCola?.items ?? [], dia.dia.cartera)
 139      return cerrados.length === 0 ? todas : todas.filter((f) => !cerrados.includes(f.lead_id))
 140    }, [ahora, cerrados, dia.dia, paginaCola?.items, yo?.demo])
 141  
 142    const pestanas = useMemo(() => pestanasDiarias(filas), [filas])
 143    // El elegido se busca en TODAS las filas, no solo en el filtro abierto: un
 144    // refetch puede moverlo de grupo (de «Hoy» a «Vencidas» al dar la hora) y la
 145    // pantalla no puede perderlo de vista ni dejar un id fantasma guardado.
 146    const elegida = elegido === null ? null : filas.find((f) => f.lead_id === elegido) ?? null
 147    // El filtro que manda: el que pidió el analista (o «Todo»). Con un GRUPO a la
 148    // vista, si el refresco mueve al elegido de grupo, la vista LO SIGUE; en
 149    // «Todo» no hace falta: ahí están todos (hallazgo de Codex, 27/09/2026).
 150    const pedido: FiltroCola = filtroPedido ?? 'todo'
 151    const filtro: FiltroCola = elegida !== null && pedido !== 'todo' && elegida.grupo !== pedido ? elegida.grupo : pedido
 152    const lista = filasDelFiltro(pestanas, filtro)
 153    // La página se deriva del elegido: si lo eligió, se ve; si no, la que pidió.
 154    const indiceElegida = elegida === null ? -1 : lista.findIndex((f) => f.lead_id === elegida.lead_id)
 155    const paginaPedida = indiceElegida >= 0 ? Math.floor(indiceElegida / FILAS_POR_PAGINA) : pagina
 156    const vista = paginaDeFilas(lista, paginaPedida, FILAS_POR_PAGINA)
 157    // Sin elección explícita, «Ahora» es el primero de la página: el orden del
 158    // servidor ya dice quién urge más.
 159    const fila = elegida ?? vista.filas[0] ?? null
 160  
 161    // EL TELÉFONO NO VIAJA EN LA COLA. `cola_accion_v2_fn` devuelve del lead solo
 162    // id, nombre, etapa y analista; el número vive en el ámbito del store, que
 163    // desde la Fase 4e «sin topes» ya NO carga todos los leads: los trae por
 164    // demanda. Por eso en «Vencidas» —cuyos leads rara vez están cargados— no
 165    // salía «Llamar» hasta abrir la ficha, que es quien los traía (bug reportado
 166    // en producción el 20/09/2026). Aquí se piden en cuanto se eligen, sin
 167    // obligar al analista a dar un rodeo por la ficha.
 168    useEffect(() => {
 169      const id = fila?.lead_id
 170      if (id === undefined || leadsPorId.has(id) || pedidos.current.has(id)) return
 171      pedidos.current.add(id)
 172      setCargandoLead(id)
 173      let vigente = true
 174      void asegurarLead(id)
 175        .catch(() => {
 176          // Si falló, que se pueda reintentar al volver a elegirlo: si no, el
 177          // lead se quedaría sin número para siempre en esta sesión.
 178          pedidos.current.delete(id)
 179        })
 180        .finally(() => { if (vigente) setCargandoLead((c) => (c === id ? null : c)) })
 181      // Cambiar de fila antes de que conteste no debe dejar el «cargando» pegado
 182      // ni pisar el estado de la fila nueva.
 183      return () => { vigente = false }
 184    }, [asegurarLead, fila?.lead_id, leadsPorId])
 185  
 186    function elegir(f: FilaDiaria) {
 187      const actual = sesionRef.current
 188      if (actual?.abierta) {
 189        toast.info(`Primero guarda o cierra el resultado de ${primerNombre(actual.lead.nombre_completo)}.`)
 190        return
 191      }
 192      // Sin formulario abierto (p. ej. volvió del marcador antes de 4 s), elegir a
 193      // otra persona abandona la llamada fijada.
 194      if (actual !== null) setSesion(null)
 195      setElegido(f.lead_id)
 196      requestAnimationFrame(() => {
 197        panelAhora.current?.scrollIntoView?.({ block: 'nearest' })
 198        nombreAhora.current?.focus()
 199      })
 200    }
 201    function cambiarFiltro(nuevo: FiltroCola) {
 202      setFiltroPedido(nuevo === 'todo' ? null : nuevo)
 203      setPagina(0)
 204      setElegido(null)
 205    }
 206    /** Se guarda ya acotada: si la lista encoge y vuelve a crecer, no salta sola. */
 207    function irAPagina(p: number) {
 208      setPagina(Math.min(Math.max(p, 0), vista.paginas - 1))
 209    }
 210    /**
 211     * Fija la llamada en curso a la persona de la tarjeta. Si ya hay una sesión,
 212     * es ESA (la tarjeta la está mostrando). Sin el lead en el ámbito no hay
 213     * sesión: la tarjeta ofrece la ficha, como siempre.
 214     */
 215    function iniciarSesion(): SesionLlamada | null {
 216      const actual = sesionRef.current
 217      if (actual !== null) return actual
 218      if (filaActiva === null) return null
 219      const suyo = leadsPorId.get(filaActiva.lead_id)
 220      if (suyo === undefined) return null
 221      const nueva: SesionLlamada = { id: ++contadorSesion.current, fila: filaActiva, lead: suyo, tarea: undefined, abierta: false }
 222      setSesion(nueva)
 223      setElegido(filaActiva.lead_id)
 224      return nueva
 225    }
 226    /**
 227     * Abre el resultado en la tarjeta para la sesión en curso. `tarea_id` viene
 228     * de la cola del SERVIDOR y es autoritativa: ese id viaja de vuelta para
 229     * cerrar la tarea. Las tareas del store son una colección PARCIAL igual que
 230     * los leads, así que no encontrarla ahí no significa que no exista — se pide
 231     * por id. Caer al cálculo de siempre cerraría otra tarea telefónica, o
 232     * ninguna (Codex, 20/09).
 233     */
 234    async function abrirRegistro() {
 235      const s = iniciarSesion()
 236      if (s === null) { if (filaActiva) void abrirLead(filaActiva.lead_id); return }
 237      if (s.abierta || abriendoPanel) return
 238      const pendientes = tareasDe(s.lead.id)
 239      let tarea: Tarea | null
 240      if (s.fila.tarea_id !== null) {
 241        const local = pendientes.find((x) => x.id === s.fila.tarea_id)
 242        if (local !== undefined) tarea = local
 243        else {
 244          setAbriendoPanel(true)
 245          try {
 246            // Si el servidor tampoco la da, se abre SIN tarea: mejor no cerrar
 247            // ninguna que cerrar la que no era.
 248            tarea = await obtenerTareaParaRevision(s.lead.id, s.fila.tarea_id)
 249          } catch {
 250            tarea = null
 251          } finally {
 252            setAbriendoPanel(false)
 253          }
 254        }
 255      } else {
 256        tarea = tareaQueCierra(pendientes, 'tel', yo?.id, ahora) ?? null
 257      }
 258      // Una respuesta tardía de una sesión ya cerrada no abre nada.
 259      if (sesionRef.current?.id !== s.id) return
 260      setSesion({ ...s, tarea, abierta: true })
 261    }
 262    /** Cierra la sesión (si sigue siendo la misma) y devuelve el foco a «Llamar». */
 263    function cerrarSesion(id: number) {
 264      if (sesionRef.current?.id !== id) return
 265      setSesion(null)
 266      requestAnimationFrame(() => {
 267        const llamar = panelAhora.current?.querySelector<HTMLElement>('[data-accion-panel] a, [data-accion-panel] button')
 268        ;(llamar ?? nombreAhora.current)?.focus()
 269      })
 270    }
 271    /**
 272     * Al guardar, «Ahora» pasa a la persona que venía DETRÁS en la lista que se
 273     * miraba (`siguienteTrasGuardar`) y el foco vuelve a su nombre. Es una
 274     * persona concreta, no «la primera de la página»: si el servidor tarda en
 275     * sacar al guardado, no se lo vuelve a proponer.
 276     */
 277    async function alGuardar(leadId: string) {
 278      const siguiente = siguienteTrasGuardar(pestanas, filtro, leadId)
 279      setCerrados((c) => (c.includes(leadId) ? c : [...c, leadId]))
 280      setFiltroPedido(siguiente.filtro === 'todo' ? null : siguiente.filtro)
 281      setElegido(siguiente.lead_id)
 282      // Dos cuadros: el diálogo restaura primero su foco. Si quedó suelto o
 283      // en las acciones que acaban de guardar, anunciar el siguiente lead.
 284      requestAnimationFrame(() => requestAnimationFrame(() => {
 285        const activo = document.activeElement
 286        const suelto = activo === null || activo === document.body || activo === document.documentElement
 287          || (activo instanceof HTMLElement && activo.closest('[data-accion-panel]') !== null)
 288        if (suelto) (nombreAhora.current ?? encabezado.current)?.focus()
 289      }))
 290      // `allSettled` y no `all`: si una de las dos lecturas falla, la otra sigue
 291      // su curso y aquí no queda un rechazo sin capturar. Y se destapa SOLO este
 292      // lead, no el de un guardado que todavía esté en vuelo.
 293      await Promise.allSettled([dia.recargar(), ...(yo?.demo ? [] : [cola.refetch()])])
 294      setCerrados((c) => c.filter((x) => x !== leadId))
 295    }
 296    async function deshacer(d: Descartado) {
 297      if (deshaciendo !== null) return
 298      setDeshaciendo(d.actividad_id)
 299      try {
 300        const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
 301        await deshacerResultadoLlamada(d.actividad_id)
 302        // El lead vuelve a la cartera: si estaba tapado por un guardado propio,
 303        // se destapa — pero solo ese, no los de otros guardados en vuelo.
 304        setCerrados((c) => c.filter((x) => x !== d.lead_id))
 305        await dia.recargar()
 306        toast.success(`Deshecho: ${d.lead_nombre} vuelve a tu cartera`)
 307        requestAnimationFrame(() => {
 308          const activo = document.activeElement
 309          if (activo === null || activo === document.body) (tituloDescartes.current ?? encabezado.current)?.focus()
 310        })
 311      } catch (causa) {
 312        const { mensajeDeError } = await import('@/data/crm-api')
 313        toast.error(mensajeDeError(causa, 'No se pudo deshacer el descarte.'))
 314      } finally {
 315        setDeshaciendo(null)
 316      }
 317    }
 318  
 319    const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
 320    const filaActiva = colaCargando ? null : fila
 321    // Lo que pinta la tarjeta: la sesión, si hay una; si no, la fila viva.
 322    const filaTarjeta = sesion?.fila ?? filaActiva
 323    const leadTarjeta = sesion?.lead ?? (filaActiva ? leadsPorId.get(filaActiva.lead_id) ?? null : null)
 324    const posicionTarjeta = filaTarjeta === null ? 0 : lista.findIndex((f) => f.lead_id === filaTarjeta.lead_id) + 1
 325    const fecha = FECHA_LARGA.format(new Date(ahora))
 326    const total = filas.length
 327    const conteoCola = colaCaida ? '?' : hayMas ? `${total}+` : String(total)
 328  
 329    return (
 330      <div className="mx-auto flex w-full max-w-[1440px] flex-col gap-4 lg:h-[calc(100svh-7rem)] lg:min-h-[640px]">
 331        <header className="flex shrink-0 flex-wrap items-end justify-between gap-x-4 gap-y-3">
 332          <div className="min-w-0 flex-1 basis-80">
 333            <h2 ref={encabezado} tabIndex={-1} className="text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary">¿A quién llamo ahora?</h2>
 334            <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">
 335              Llama, guarda el resultado y pasas al siguiente. {corte ? `Corte ${corte}` : 'Sin corte confirmado'} · se actualiza cada minuto.
 336            </p>
 337          </div>
 338          <div className="flex min-w-0 flex-wrap items-center gap-3">
 339            <span className="text-[13px] text-foreground/80 first-letter:uppercase">{fecha}</span>
 340            {accesoSeguimiento}
 341            <button type="button" aria-label="Actualizar" title="Actualizar" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
 342              className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] border border-border bg-card text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
 343              onClick={() => { if (dia.enVuelo) return; void dia.recargar(); if (!yo?.demo) void cola.refetch() }}>
 344              <RefreshCw aria-hidden className={`size-4 ${dia.enVuelo ? 'motion-safe:animate-spin' : ''}`} />
 345            </button>
 346          </div>
 347        </header>
 348  
 349        {dia.error != null && dia.dia === null ? (
 350          <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
 351        ) : dia.dia === null && dia.cargando ? (
 352          <PanelCargando filas={6} />
 353        ) : dia.dia === null ? (
 354          <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
 355        ) : (
 356          <>
 357            {/* Los avisos que cambian la decisión de marcar van FUERA de las
 358                pestañas: se ven siempre, esté abierta la que esté. */}
 359            {colaCaida && (
 360              <p role="alert" className="shrink-0 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
 361                No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
 362              </p>
 363            )}
 364            {dia.dia.cartera_truncada && (
 365              <p role="status" className="shrink-0 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">
 366                Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
 367              </p>
 368            )}
 369  
 370            <FranjaCifras etiqueta="Tu día en cifras" cifras={cifrasDelDia(dia.dia)} className="shrink-0" />
 371  
 372            <div className="flex min-h-0 flex-1 flex-col gap-4 lg:flex-row">
 373              <PanelAhora fila={filaTarjeta} lead={leadTarjeta}
 374                sinConversacionDias={dia.dia.sin_conversacion_dias} ahora={ahora} cargando={colaCargando && sesion === null} colaCaida={colaCaida}
 375                filtroVacio={filaTarjeta === null && total > 0}
 376                seccionRef={panelAhora} nombreRef={nombreAhora}
 377                posicion={posicionTarjeta} total={lista.length}
 378                cargandoLead={filaTarjeta !== null && cargandoLead === filaTarjeta.lead_id} abriendoPanel={abriendoPanel}
 379                // «Llamar» FIJA a la persona: nace la sesión de llamada. Si mientras
 380                // marca (en el celular, con el CRM en segundo plano) entra un lead
 381                // más urgente, la tarjeta no cambia y el resultado va a ESTA persona.
 382                onLlamar={() => { iniciarSesion() }}
 383                onRegistrar={() => { void abrirRegistro() }}
 384                onAbrirFicha={() => { if (filaTarjeta) void abrirLead(filaTarjeta.lead_id) }}
 385                registro={sesion?.abierta ? (() => {
 386                  const { id: idSesion, lead: leadSesion } = sesion
 387                  return <RegistroResultadoTarjeta key={idSesion} lead={leadSesion} tarea={sesion.tarea ?? null}
 388                    onClose={() => cerrarSesion(idSesion)} onGuardado={() => void alGuardar(leadSesion.id)} />
 389                })() : undefined} />
 390  
 391              <section aria-label="Tu cola y tu actividad" className="flex min-h-[520px] min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-border bg-card lg:min-h-0">
 392                <Tabs
 393                  etiqueta="Qué ver"
 394                  variante="subrayado"
 395                  valor={vistaDerecha}
 396                  onCambio={setVistaDerecha}
 397                  pestanas={[
 398                    { valor: 'cola', etiqueta: 'Cola de hoy', extra: `· ${conteoCola}` },
 399                    { valor: 'actividad', etiqueta: 'Mi actividad' },
 400                    { valor: 'seguimiento', etiqueta: 'Mi seguimiento', ...(dia.dia.compromisos_total > 0 ? { extra: `· ${dia.dia.compromisos_total}` } : {}) },
 401                  ]}
 402                  className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-[18px] [&>[role=tablist]]:pt-1.5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm [&>[role=tablist]>[role=tab]>span]:text-sm"
 403                  clasePanel="flex min-h-0 flex-1 flex-col"
 404                >
 405                  {vistaDerecha === 'cola' ? (
 406                    <ColaDeHoy
 407                      idBase={id} pestanas={pestanas} filtro={filtro} onFiltro={cambiarFiltro}
 408                      pagina={vista.pagina} onPagina={irAPagina}
 409                      elegido={filaActiva?.lead_id ?? null} onElegir={elegir}
 410                      ahora={ahora} cargando={colaCargando} hayMas={hayMas} colaCaida={colaCaida}
 411                      sinConversacionDias={dia.dia.sin_conversacion_dias}
 412                    />
 413                  ) : vistaDerecha === 'actividad' ? (
 414                    <MiActividad dia={dia.dia} analistaId={yo?.id ?? null} hoy={fechaLima(ahora)}
 415                      deshaciendo={deshaciendo} onDeshacer={(d) => { void deshacer(d) }} tituloDescartesRef={tituloDescartes}
 416                      onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
 417                  ) : (
 418                    <MiSeguimiento dia={dia.dia} onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
 419                  )}
 420                </Tabs>
 421              </section>
 422            </div>
 423          </>
 424        )}
 425  
 426      </div>
 427    )
 428  }
 429  
 430  /**
 431   * Las 4 cifras de la franja. El % NUNCA va solo (decisión #7): lleva las útiles
 432   * sobre las que se calcula; sin llamadas útiles se dice «—» con su palabra para
 433   * el lector, y sin el mínimo no hay chip de nivel.
 434   */
 435  function cifrasDelDia(dia: DiaAnalista): CifraDelDia[] {
 436    const m = dia.marcador
 437    const utiles = m.utiles === 1 ? '1 útil' : `${m.utiles} útiles`
 438    const minimo = dia.umbrales.minimo_llamadas_utiles
 439    const contacto: CifraDelDia = m.tasa_contacto_pct === null
 440      ? { etiqueta: 'Contacto', valor: '—', valorAccesible: 'sin dato', apoyo: `se juzga desde ${minimo} llamadas útiles` }
 441      : {
 442        etiqueta: 'Contacto',
 443        valor: `${m.tasa_contacto_pct} %`,
 444        apoyo: m.nivel === null
 445          ? `de ${utiles}`
 446          : <Badge className="min-h-[22px] py-0 text-[11.5px]" color={COLOR_NIVEL[m.nivel]}>{ETIQUETA_NIVEL[m.nivel]} · de {utiles}</Badge>,
 447      }
 448    return [
 449      { etiqueta: 'Llamadas', valor: String(m.llamadas), apoyo: 'hoy' },
 450      { etiqueta: 'Contestaron', valor: String(m.contestadas), apoyo: `de ${m.llamadas}` },
 451      contacto,
 452      { etiqueta: presentarCitas('Citas agendadas'), valor: String(m.citas_agendadas), apoyo: 'hoy' },
 453    ]
 454  }
 455  
 456  
 457  /**
 458   * El panel «Ahora»: UN lead, UNA acción primaria, con aire de celular porque es
 459   * el centro de llamadas (diseño del 27/09/2026): cabecera navy con la barrita
 460   * del altavoz, el teléfono grande, «Llamar» redondo y la barra de inicio abajo.
 461   * Lo secundario —ver la ficha, registrar desde el menú— vive detrás de «···»
 462   * (ley de Hick). Escala y medidas: las del diseño (384 px de ancho, radio 32).
 463   */
 464  function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaida, filtroVacio, onLlamar, onRegistrar, onAbrirFicha, seccionRef, nombreRef, cargandoLead, abriendoPanel, posicion, total, registro }: {
 465    fila: FilaDiaria | null
 466    lead: Lead | null
 467    sinConversacionDias: number
 468    ahora: number
 469    cargando: boolean
 470    colaCaida: boolean
 471    /** La lista a la vista está vacía pero la cola no: el vacío es del filtro. */
 472    filtroVacio: boolean
 473    cargandoLead: boolean
 474    abriendoPanel: boolean
 475    posicion: number
 476    total: number
 477    onLlamar: () => void
 478    onRegistrar: () => void
 479    onAbrirFicha: () => void
 480    seccionRef: Ref<HTMLElement>
 481    nombreRef: Ref<HTMLButtonElement>
 482    /** El resultado de la llamada en curso: ocupa el lugar de las acciones. */
 483    registro?: ReactNode
 484  }): JSX.Element {
 485    const id = useId()
 486    const etapa = fila === null ? null : ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
 487    const tiempo = fila === null ? null : tiempoDeFila(fila, ahora)
 488    return (
 489      <div className="flex min-h-0 shrink-0 justify-center lg:w-[430px]">
 490        <section ref={seccionRef} aria-labelledby={`${id}-ahora`}
 491          className="flex w-full max-w-[384px] flex-col overflow-clip rounded-[32px] border border-border-strong bg-card shadow-[0_10px_28px_rgb(17_30_61/0.10)] lg:h-full">
 492          <div className="shrink-0 bg-primary text-primary-foreground">
 493            <span aria-hidden="true" className="mx-auto mt-2.5 block h-[5px] w-14 rounded-full bg-white/30" />
 494            <div className="flex items-center gap-2.5 px-5 pb-3.5 pt-2">
 495              <Phone aria-hidden className="size-[18px]" />
 496              <h3 id={`${id}-ahora`} className="text-[15px] font-extrabold">Ahora</h3>
 497              {fila !== null && posicion > 0 && <span className="ml-auto text-[13px] tabular-nums text-primary-foreground/80"><span className="sr-only">Contacto </span>{posicion} de {total}<span className="sr-only"> en esta lista</span></span>}
 498            </div>
 499          </div>
 500          {fila === null ? (
 501            <p className="flex-1 px-6 py-8 text-center text-sm leading-relaxed text-[var(--muted-foreground-strong)]">
 502              {cargando ? 'Buscando a quién llamar…'
 503                : colaCaida ? 'No se pudo leer tu cola: no sabemos a quién te toca llamar. Pulsa «Actualizar».'
 504                  : filtroVacio ? 'Nada en este filtro. Vuelve a «Todo» para ver a quién llamar.'
 505                    : 'Nada pendiente ahora. Cuando entre un lead nuevo aparecerá aquí.'}
 506            </p>
 507          ) : (
 508            <div className={registro !== undefined
 509              ? 'flex min-h-0 flex-1 flex-col gap-3 pt-4 [&>*:not(section)]:px-[18px]'
 510              : 'ac-scroll flex min-h-0 flex-1 flex-col gap-3.5 overflow-y-auto px-[18px] py-5'}>
 511              <div className="flex min-w-0 flex-col gap-0.5">
 512                <button ref={nombreRef} type="button" onClick={onAbrirFicha}
 513                  aria-label={`Abrir la ficha de ${fila.nombre_completo}`}
 514                  className="self-start rounded-md text-left text-2xl font-extrabold leading-tight tracking-[-0.02em] text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 515                  {fila.nombre_completo}
 516                </button>
 517                <p className="text-[13px] text-[var(--muted-foreground-strong)]">{etapa}</p>
 518              </div>
 519              {registro === undefined && <div className="flex flex-col items-start gap-2 rounded-xl bg-muted/70 px-3.5 py-3">
 520                {tiempo !== null && (
 521                  <Badge className="min-h-[22px] py-0 text-[11.5px]" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
 522                )}
 523                <p className="text-[13px] leading-snug text-foreground/80">
 524                  {fila.senal === null ? 'Historial no cargado. Ábrelo en la ficha antes de llamar.' : detalleDeFila(fila, sinConversacionDias)}
 525                </p>
 526              </div>}
 527              {lead !== null && <p className={cn('text-center font-extrabold tracking-[0.02em] tabular-nums text-primary', registro !== undefined ? 'text-xl' : 'text-2xl')}>{lead.telefono}</p>}
 528              {registro !== undefined ? registro : <div className="relative">
 529                {lead !== null ? (
 530                  // `key={lead.id}`: UNA instancia por lead. Antes las acciones
 531                  // vivían dentro de cada fila y se desmontaban con ella; aquí hay
 532                  // una sola caja que cambia de lead, y si el refresco de cada
 533                  // minuto cambiaba el lead con el diálogo de resultado ABIERTO, el
 534                  // resultado se escribía sobre el lead equivocado. La clave fuerza
 535                  // el remontaje: el contacto a medias se cae a la vista, que es
 536                  // reparable — atribuirlo a otra persona, no (hallazgo de Codex).
 537                  // El envoltorio da la forma del diseño: «Llamar» píldora de 52 px
 538                  // y lo demás de 44, dejando sitio a «···» junto al último.
 539                  <div data-accion-panel="si"
 540                    className="[&>div]:flex-col [&>div]:items-stretch [&>div]:!gap-2.5 [&>div>*]:justify-center [&>div>*]:!rounded-full [&>div>*]:!font-bold [&>div>*:first-child]:!h-[52px] [&>div>*:first-child]:!text-[15px] [&>div>*:not(:first-child)]:!h-11 [&>div>*:not(:first-child)]:!text-[13px] [&>div>*:not(:first-child)]:!font-semibold [&>div>*:not(:first-child)]:mr-[54px] [&_svg]:!size-[18px]">
 541                    <AccionesContacto key={lead.id} lead={lead} destacada onLlamar={onLlamar} onRegistrarLlamada={onRegistrar} />
 542                  </div>
 543                ) : (
 544                  <p role="status" className="min-h-11 pr-[54px] text-[13px] text-[var(--muted-foreground-strong)]">
 545                    {cargandoLead ? 'Buscando su número…' : 'No se pudo traer su número. Abre la ficha para llamar.'}
 546                  </p>
 547                )}
 548                <div className="absolute bottom-0 right-0">
 549                  <DropdownMenu
 550                    trigger={
 551                      <button type="button" data-accion-panel="si"
 552                        aria-label={`Más acciones para ${fila.nombre_completo}: registrar resultado y ver la ficha`}
 553                        className="grid size-11 shrink-0 cursor-pointer place-items-center rounded-full border border-border bg-card text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 554                        <MoreHorizontal aria-hidden className="size-[18px]" />
 555                      </button>
 556                    }>
 557                    <DropdownItem className="min-h-11 text-base" disabled={abriendoPanel} onSelect={() => { if (!abriendoPanel) onRegistrar() }}>Registrar resultado</DropdownItem>
 558                    <DropdownItem className="min-h-11 text-base" onSelect={onAbrirFicha}>Ver la ficha completa</DropdownItem>
 559                  </DropdownMenu>
 560                </div>
 561              </div>}
 562            </div>
 563          )}
 564          {registro === undefined && <p className="shrink-0 border-t border-border px-5 pb-1.5 pt-3 text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
 565            El orden lo pone el servidor: nuevo sin intento primero, luego lo vencido y lo de hoy. Al guardar pasas al siguiente.
 566          </p>}
 567          <span aria-hidden="true" className="mx-auto mb-2 block h-1 w-24 shrink-0 rounded-full bg-border-strong" />
 568        </section>
 569      </div>
 570    )
 571  }
 572  
 573  /**
 574   * «Mi actividad»: lo que el analista YA hizo hoy, en una pestaña y no en
 575   * plegables apilados. Las barras por hora (decisión #8), cómo se cuenta, los
 576   * descartes que aún se pueden deshacer y el registro íntegro del día (antes
 577   * vivía plegado debajo de la pantalla, en el contenedor).
 578   */
 579  function MiActividad({ dia, analistaId, hoy, deshaciendo, onDeshacer, onAbrirFicha, tituloDescartesRef }: {
 580    dia: DiaAnalista
 581    analistaId: string | null
 582    hoy: string
 583    deshaciendo: string | null
 584    onDeshacer: (d: Descartado) => void
 585    onAbrirFicha: (leadId: string) => void
 586    tituloDescartesRef: Ref<HTMLHeadingElement>
 587  }): JSX.Element {
 588    const m = dia.marcador
 589    return (
 590      <div className="ac-scroll min-h-0 flex-1 space-y-6 overflow-y-auto px-[18px] py-4">
 591        <h3 className="sr-only">Mi actividad de hoy</h3>
 592        <div className="space-y-2">
 593          <BarrasPorHora porHora={m.por_hora} titulo="Llamadas por hora" alto={130}
 594            apoyo={m.ultima_llamada_en !== null ? `Primera ${horaLimaDe(m.primera_llamada_en)} · última ${horaLimaDe(m.ultima_llamada_en)}` : undefined} />
 595          <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
 596            Tocaste {m.leads_tocados} {m.leads_tocados === 1 ? 'lead' : 'leads'}. Llamadas = marcadas + no contestadas; no incluye WhatsApp ni citas.
 597            Un número errado no entra en el contacto, y el nivel se juzga desde {dia.umbrales.minimo_llamadas_utiles} llamadas útiles. Tu supervisor ve esto mismo de ti.
 598          </p>
 599        </div>
 600        <Descartados dia={dia} deshaciendo={deshaciendo} onDeshacer={onDeshacer} onAbrirFicha={onAbrirFicha} tituloRef={tituloDescartesRef} />
 601        {analistaId !== null && (
 602          // Versión compacta del registro compartido: supervisor y gerencia
 603          // conservan la suya hasta sus propios planes.
 604          <RegistroActividad dia={hoy} analistaIds={[analistaId]} mostrarAnalista={false} permitirExportar={false} compacto />
 605        )}
 606      </div>
 607    )
 608  }
 609  
 610  /**
 611   * Compromisos: SOLO de mañana en adelante — el servidor los devuelve desde
 612   * mañana 00:00 Lima (`gestion_diaria_analista_fn`, `v_manana`), y lo de hoy y
 613   * lo vencido ya está en la cola.
 614   */
 615  function MiSeguimiento({ dia, onAbrirFicha }: {
 616    dia: DiaAnalista
 617    onAbrirFicha: (leadId: string) => void
 618  }): JSX.Element {
 619    return (
 620      <div className="ac-scroll min-h-0 flex-1 overflow-y-auto px-[18px] py-4">
 621        <h3 className="text-[15px] font-extrabold text-primary">
 622          Mi seguimiento <span className="font-semibold text-[var(--muted-foreground-strong)]">· {dia.compromisos_total} {dia.compromisos_total === 1 ? 'compromiso' : 'compromisos'} desde mañana</span>
 623        </h3>
 624        {dia.compromisos.length === 0 ? (
 625          <PanelVacio icono={CalendarClock} titulo="Sin compromisos a partir de mañana" detalle="Lo de hoy y lo vencido ya está en tu cola." />
 626        ) : (
 627          <>
 628            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 629            <ol role="list" aria-label="Mis compromisos" className="mt-2">
 630              {dia.compromisos.map((c) => (
 631                <li key={c.tarea_id} className="flex flex-wrap items-center justify-between gap-2 border-b border-muted py-2.5">
 632                  <div className="min-w-0">
 633                    <button type="button" onClick={() => onAbrirFicha(c.lead_id)}
 634                      className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 635                      {c.lead_nombre}
 636                    </button>
 637                    <p className="text-xs text-[var(--muted-foreground-strong)]">
 638                      {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
 639                      {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
 640                    </p>
 641                  </div>
 642                  <span className="text-[13px] font-semibold tabular-nums text-foreground/80">{cuandoLimaDe(c.vence_en)}</span>
 643                </li>
 644              ))}
 645            </ol>
 646            {dia.compromisos_total > dia.compromisos.length && (
 647              <p className="mt-3 text-xs text-[var(--muted-foreground-strong)]">
 648                Se muestran los {dia.compromisos.length} más próximos de {dia.compromisos_total}. El resto está en Agenda.
 649              </p>
 650            )}
 651          </>
 652        )}
 653      </div>
 654    )
 655  }
 656  
 657  function Descartados({ dia, deshaciendo, onDeshacer, onAbrirFicha, tituloRef }: {
 658    dia: DiaAnalista
 659    deshaciendo: string | null
 660    onDeshacer: (d: Descartado) => void
 661    onAbrirFicha: (leadId: string) => void
 662    tituloRef: Ref<HTMLHeadingElement>
 663  }): JSX.Element | null {
 664    const id = useId()
 665    if (dia.descartados.length === 0) return null
 666    return (
 667      <section aria-labelledby={`${id}-descartados`} className="space-y-1.5">
 668        <h3 ref={tituloRef} tabIndex={-1} id={`${id}-descartados`} className="text-[15px] font-extrabold text-primary">
 669          Descartados hoy <span className="font-semibold text-[var(--muted-foreground-strong)]">· {dia.descartados.length} · se pueden deshacer 24 h</span>
 670        </h3>
 671        <p className="text-xs text-[var(--muted-foreground-strong)]">
 672          Están en el Centro de rescate con su motivo. Al deshacerlo, el lead vuelve a tu cartera con un ciclo nuevo.
 673        </p>
 674        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 675        <ol role="list" aria-label="Descartados hoy">
 676          {dia.descartados.map((d) => (
 677            <li key={d.actividad_id} className="flex flex-wrap items-center justify-between gap-2 border-b border-muted py-2.5">
 678              <div className="min-w-0">
 679                <button type="button" onClick={() => onAbrirFicha(d.lead_id)}
 680                  className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 681                  {d.lead_nombre}
 682                </button>
 683                <p className="text-xs text-[var(--muted-foreground-strong)]">
 684                  {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
 685                  {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
 686                </p>
 687              </div>
 688              {d.puede_deshacer ? (
 689                // `aria-disabled` y no `disabled`: deshabilitar el botón enfocado
 690                // manda el foco al body (regla de la casa, boton-guardar.tsx).
 691                <button type="button" aria-disabled={deshaciendo !== null}
 692                  aria-label={`Deshacer el descarte de ${d.lead_nombre}`}
 693                  className="inline-flex h-9 cursor-pointer items-center gap-1.5 rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50"
 694                  onClick={() => { if (deshaciendo === null) onDeshacer(d) }}>
 695                  <RotateCcw aria-hidden className="size-4" /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
 696                </button>
 697              ) : (
 698                <span className="text-xs text-[var(--muted-foreground-strong)]">Sin deshacer</span>
 699              )}
 700            </li>
 701          ))}
 702        </ol>
 703      </section>
 704    )
 705  }
```

### `components/gestion-diaria/registrar-resultado.tsx`
```tsx
   1  // Panel «Registrar resultado de la llamada» (Gestión Diaria F2, mockup 5).
   2  // Es la ÚNICA definición del resultado de una llamada en el CRM: lo montan las
   3  // acciones de contacto (colas, Hoy, ficha), el cierre de una tarea de llamada
   4  // y el composer del drawer. Paso 1 = uno de siete resultados (atajos 1–7);
   5  // paso 2 = lo que ese resultado exige (fecha, cita, submotivo o la decisión del
   6  // analista ante un número errado); nota opcional; «Guardar».
   7  //
   8  // DOS PRESENTACIONES, UNA SOLA LÓGICA (27/09/2026, diseño de Gestión Diaria):
   9  // `useRegistroResultado` guarda el estado, las reglas espejo del servidor y el
  10  // envío; `CamposResultado` pinta los dos pasos. `RegistrarResultado` los monta
  11  // en el `Dialog` de siempre (ficha, Hoy, colas, composer: su contrato no
  12  // cambia) y `RegistroResultadoTarjeta` dentro de la tarjeta «Ahora» de «Mi
  13  // día», sin ventana encima. La tarjeta NO finge un diálogo (hallazgo de Codex):
  14  // tiene su propio contrato de teclado —atajos 1–7 solo con el foco dentro de
  15  // ella y fuera de un campo, Escape = «Cerrar sin registrar» salvo mientras
  16  // guarda— y el foco lo maneja quien la monta.
  17  //
  18  // Nada en silencio: el toast enumera lo que ocurrió DE VERDAD (registrado,
  19  // tarea cerrada, etapa, siguiente, descarte, No insistir) y ofrece «Deshacer»
  20  // 15 s, que llama a `crm.deshacer_resultado_llamada` (24 h, solo el autor).
  21  // La regla comercial vive en el servidor (`crm.registrar_llamada_v4`): aquí
  22  // solo se arma la petición y se espeja lo que él rechazaría.
  23  import { useEffect, useId, useMemo, useRef, useState, type JSX, type KeyboardEvent as EventoTeclado, type RefObject } from 'react'
  24  import { toast } from 'sonner'
  25  import { Button } from '@/components/ui/button'
  26  import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
  27  import { Input } from '@/components/ui/input'
  28  import { Label } from '@/components/ui/label'
  29  import { Select } from '@/components/ui/select'
  30  import { RadioGroup, type OpcionRadio } from '@/components/ui/radio-group'
  31  import { Textarea } from '@/components/ui/textarea'
  32  import { CAMPOS_REUNION_VACIOS, CamposReunion, camposTareaDeReunion, type EstadoCamposReunion } from '@/components/app/campos-reunion'
  33  import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
  34  import { fechaLima, horaLima, proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'
  35  import { useAhora } from '@/lib/ahora'
  36  import { useAuth } from '@/lib/auth-context'
  37  import { camposDeSugerencia, isoDeCampos, tituloProximaAccion, type CamposSiguiente } from '@/lib/campos-siguiente'
  38  import { evidenciaNoResponde } from '@/lib/descarte-evidencia'
  39  import { esPlanVivo } from '@/lib/plan-lead'
  40  import { primerNombre } from '@/lib/format'
  41  import { slotHabil, sugerirSiguiente } from '@/lib/motor-siguiente'
  42  import {
  43    INTENTOS_PARA_OFRECER_PERDIDO, RESULTADOS, SUBMOTIVOS, definicionResultado, dentroDeVentanaLegal, etiquetaResultado, tiposSiguientesDeResultado,
  44    type ResultadoLlamada, type SubmotivoLlamada,
  45  } from '@/lib/resultado-llamada'
  46  import { validarReunionOperativa } from '@/lib/reunion-operativa'
  47  import { useCRMData } from '@/lib/store-context'
  48  import type { RegistrarLlamadaInput } from '@/lib/store'
  49  import { presentarCitas } from '@/lib/terminologia'
  50  import { cn } from '@/lib/utils'
  51  import { ETAPA_INFO, TIPOS_TAREA, esTipoTarea, type LeadContactable, type Tarea } from '@/lib/tipos'
  52  
  53  type DecisionNumero = 'segundo_numero' | 'descartar' | 'reintento' | 'solo_registrar'
  54  
  55  export interface RegistrarResultadoProps {
  56    lead: LeadContactable
  57    /** Tarea de LLAMADA pendiente que esta llamada cierra (la elige `tareaQueCierra`). */
  58    tarea?: Tarea | null | undefined
  59    /** Nota precargada (el composer del drawer la trae escrita). */
  60    notaInicial?: string | undefined
  61    onClose: () => void
  62    /** Se llama SOLO cuando el servidor confirmó el resultado (nunca al cancelar
  63     *  ni al quedar «por confirmar»): Gestión Diaria lo usa para saltar a la
  64     *  siguiente fila de la cola del día. `onClose` se dispara igual, ANTES. */
  65    onGuardado?: (() => void) | undefined
  66  }
  67  
  68  const PLANTILLA: Tarea = {
  69    id: 'sugerencia', lead_id: null, tipo: 'llamada', titulo: '', vence_en: new Date(0).toISOString(),
  70    estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: new Date(0).toISOString(),
  71  }
  72  
  73  /** Campos de la siguiente para una fecha objetivo en ms (ya en ventana legal). */
  74  function camposPara(tipo: CamposSiguiente['tipo'], titulo: string, ms: number): CamposSiguiente {
  75    return { tipo, titulo, fecha: fechaLima(ms), hora: horaLima(ms) }
  76  }
  77  
  78  /** Campos donde se ESCRIBE: ahí los dígitos son texto, no atajos. Los radios y
  79   *  casillas (donde cae el foco inicial) sí aceptan los atajos. */
  80  const ES_CAMPO = (el: EventTarget | null): boolean => {
  81    if (!(el instanceof HTMLElement)) return false
  82    if (el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable) return true
  83    return el instanceof HTMLInputElement && !['radio', 'checkbox', 'button', 'submit'].includes(el.type)
  84  }
  85  
  86  /**
  87   * La lógica ÚNICA del resultado de una llamada. `dentro` dice si una tecla
  88   * pertenece a esta presentación (el diálogo o la tarjeta): los atajos de un
  89   * carácter se acotan al componente (WCAG 2.1.4), nunca a cualquier cosa que
  90   * esté en pantalla.
  91   */
  92  function useRegistroResultado(
  93    { lead, tarea, notaInicial, onClose, onGuardado }: RegistrarResultadoProps,
  94    raiz: RefObject<HTMLElement | null>,
  95    dentro: (objetivo: EventTarget | null) => boolean,
  96  ) {
  97    const { registrarLlamada, deshacerResultadoLlamada, tareasDe } = useCRMData()
  98    const { yo } = useAuth()
  99    const ahora = useAhora()
 100    const historial = useActividadesDeLead(lead.id)
 101    const nombre = primerNombre(lead.nombre_completo)
 102    const soyDueno = lead.vendedor_id != null && lead.vendedor_id === yo?.id
 103    const pendientes = tareasDe(lead.id)
 104  
 105    const [resultado, setResultado] = useState<ResultadoLlamada | null>(null)
 106    const [mostrarOpciones, setMostrarOpciones] = useState(true)
 107    const enfocarResultado = useRef(false)
 108    const [submotivo, setSubmotivo] = useState<SubmotivoLlamada | null>(null)
 109    const [decision, setDecision] = useState<DecisionNumero | null>(null)
 110    // ANTI-DUPLICADO (misma regla que el diálogo anterior): si el lead ya tiene
 111    // un plan vivo que esta llamada no cierra, el siguiente intento no se
 112    // propone marcado. El analista puede marcarlo igual.
 113    const otroPlanVivo = pendientes.some((t) => t.id !== tarea?.id && esPlanVivo(t, ahora))
 114    const [agendar, setAgendar] = useState(!otroPlanVivo)
 115    const [perdido, setPerdido] = useState(false)
 116    const [descartarInteres, setDescartarInteres] = useState(false)
 117    const [noInsista, setNoInsista] = useState(false)
 118    const [cierraTarea, setCierraTarea] = useState(true)
 119    const [nota, setNota] = useState(notaInicial ?? '')
 120    const [editados, setEditados] = useState<CamposSiguiente | null>(null)
 121    const [tituloEditado, setTituloEditado] = useState(false)
 122    const [camposReunion, setCamposReunion] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
 123    const [tsEleccion, setTsEleccion] = useState(() => Date.now())
 124    const [procesando, setProcesando] = useState(false)
 125    const [sinConfirmar, setSinConfirmar] = useState<RegistrarLlamadaInput | null>(null)
 126    const enviando = useRef(false)
 127  
 128    const def = resultado ? definicionResultado(resultado) : null
 129    // Intentos sin respuesta ya registrados: al 6.º se ofrece «marcar perdido».
 130    // Un número errado no es «no responde» (mismo criterio que el servidor).
 131    const intentosPrevios = historial.cargando || historial.error
 132      ? null
 133      : evidenciaNoResponde(historial.items.filter((a) => {
 134        const r = a.metadata?.resultado
 135        return r !== 'numero_errado' && r !== 'no_es_la_persona'
 136      })).intentos
 137    const ofrecePerdido = resultado === 'no_contesto' && intentosPrevios !== null && intentosPrevios + 1 >= INTENTOS_PARA_OFRECER_PERDIDO
 138    const tieneSegundoNumero = Boolean(lead.telefono_alternativo)
 139  
 140    const elegir = (r: ResultadoLlamada, desdeAtajo = false) => {
 141      if (enviando.current || sinConfirmar) return
 142      if (desdeAtajo && !mostrarOpciones && r !== resultado) return
 143      enfocarResultado.current = true
 144      setMostrarOpciones(false)
 145      if (r === resultado) return
 146      setResultado(r)
 147      setSubmotivo(null)
 148      setDecision(r === 'numero_errado' || r === 'no_es_la_persona' ? (tieneSegundoNumero ? 'segundo_numero' : null) : null)
 149      setAgendar(!otroPlanVivo)
 150      setPerdido(false)
 151      setDescartarInteres(false)
 152      setNoInsista(false)
 153      setEditados(null)
 154      setTituloEditado(false)
 155      setCamposReunion(CAMPOS_REUNION_VACIOS)
 156      setTsEleccion(Date.now())
 157    }
 158  
 159    // La SUGERENCIA del motor (cadencia D1/D3, alternancia de canal, ventana
 160    // legal) es el punto de partida editable; el analista manda.
 161    const sugerida = useMemo<CamposSiguiente | null>(() => {
 162      if (!def || !soyDueno || lead.no_contactar) return null
 163      if (def.paso === 'submotivo') {
 164        return camposPara('llamada', tituloProximaAccion('llamada', nombre), Date.parse(proximoSlotSugerido(tsEleccion)))
 165      }
 166      if (def.clave === 'no_contesto' || def.clave === 'volver_a_llamar') {
 167        const s = sugerirSiguiente({ tareaTipo: 'llamada', estado: 'completada', resultado: def.tipo, leadNombre: lead.nombre_completo, noContactar: lead.no_contactar ?? null, ahora: tsEleccion })
 168        if (!s) return null
 169        return def.clave === 'volver_a_llamar' ? { ...camposDeSugerencia(s), tipo: 'llamada', titulo: `Volver a llamar a ${nombre}` } : camposDeSugerencia(s)
 170      }
 171      if (def.clave === 'agendo_reunion') {
 172        return camposPara('reunion', `Cita con ${nombre}`, Date.parse(slotHabil(tsEleccion + 24 * 3600 * 1000)))
 173      }
 174      if (def.paso === 'decision_numero') {
 175        if (decision === 'segundo_numero') return camposPara('llamada', `Llamar al 2.º número ${lead.telefono_alternativo ?? ''}`.trim(), Date.parse(slotHabil(tsEleccion + 30 * 60 * 1000)))
 176        if (decision === 'reintento') return camposPara('llamada', `Reintentar con ${nombre}`, Date.parse(slotHabil(tsEleccion + 7 * 24 * 3600 * 1000)))
 177      }
 178      return null
 179    }, [def, decision, lead.nombre_completo, lead.no_contactar, lead.telefono_alternativo, nombre, soyDueno, tsEleccion])
 180    const campos = editados ?? sugerida
 181    const editar = (parche: Partial<CamposSiguiente>) => setEditados({ ...(campos ?? { tipo: 'llamada', titulo: '', fecha: '', hora: '10:00' }), ...parche })
 182  
 183    const descarta = def != null && ((def.paso === 'submotivo' && descartarInteres) || (def.paso === 'decision_numero' && decision === 'descartar') || (def.clave === 'no_contesto' && perdido))
 184    const muestraSiguiente = soyDueno && !noInsista && !lead.no_contactar && !descarta && def != null && (
 185      def.clave === 'volver_a_llamar' || def.clave === 'agendo_reunion'
 186      || def.paso === 'submotivo'
 187      || (def.clave === 'no_contesto' && !perdido)
 188      || (def.paso === 'decision_numero' && (decision === 'segundo_numero' || decision === 'reintento')))
 189    const siguienteOpcional = def?.clave === 'no_contesto' || def?.paso === 'submotivo'
 190    const tiposSiguientes = resultado ? tiposSiguientesDeResultado(resultado) : []
 191    const cancelaria = descarta ? pendientes.filter((t) => t.id !== tarea?.id).length : 0
 192  
 193    // Atajos 1–7: SOLO cuando el foco no está en un campo (teclear «1» en la nota
 194    // no debe cambiar el resultado), sin modificadores y dentro de ESTA
 195    // presentación. Se escucha en el documento porque el foco inicial del diálogo
 196    // queda en su contenedor, fuera de este árbol.
 197    const elegirRef = useRef(elegir)
 198    elegirRef.current = elegir
 199    const dentroRef = useRef(dentro)
 200    dentroRef.current = dentro
 201    useEffect(() => {
 202      if (!enfocarResultado.current || !resultado) return
 203      enfocarResultado.current = false
 204      raiz.current?.querySelector<HTMLInputElement>(`input[name="resultado-llamada"][value="${resultado}"]`)?.focus()
 205    }, [mostrarOpciones, resultado, raiz])
 206    useEffect(() => {
 207      const onKeyDown = (e: globalThis.KeyboardEvent) => {
 208        if (e.altKey || e.ctrlKey || e.metaKey || e.isComposing || ES_CAMPO(e.target)) return
 209        if (!dentroRef.current(e.target)) return
 210        const r = RESULTADOS.find((x) => x.atajo === e.key)
 211        if (!r) return
 212        e.preventDefault()
 213        elegirRef.current(r.clave, true)
 214      }
 215      document.addEventListener('keydown', onKeyDown)
 216      return () => document.removeEventListener('keydown', onKeyDown)
 217    }, [])
 218    useEffect(() => { setNota(notaInicial ?? '') }, [notaInicial])
 219  
 220    const armar = (): RegistrarLlamadaInput | string => {
 221      if (!def) return 'Elige el resultado de la llamada'
 222      const entrada: RegistrarLlamadaInput = { resultado: def.clave, detalle: nota.trim() || null, tarea_id: tarea && cierraTarea ? tarea.id : null }
 223      if (def.paso === 'submotivo') {
 224        if (!submotivo) return def.clave === 'no_interesado' ? 'Indica por qué no le interesa' : 'Indica qué producto pide'
 225        entrada.submotivo = submotivo
 226        entrada.no_insista = noInsista
 227        entrada.descartar = descartarInteres
 228      }
 229      if (def.paso === 'decision_numero') {
 230        if (!decision) return 'Decide qué hacer con este número'
 231        entrada.descartar = decision === 'descartar'
 232      }
 233      if (def.clave === 'no_contesto' && perdido) entrada.descartar = true
 234      const quiereSiguiente = muestraSiguiente && (!siguienteOpcional || agendar)
 235      if (quiereSiguiente) {
 236        if (!campos) return 'Indica la fecha del siguiente paso'
 237        const iso = isoDeCampos(campos)
 238        if (!iso || !campos.titulo.trim()) return 'La siguiente tarea necesita título, fecha y hora válidos'
 239        if (Date.parse(iso) <= Date.now()) return 'La fecha del siguiente paso debe ser futura'
 240        if (!tiposSiguientes.includes(campos.tipo)) return 'Elige un tipo de próxima acción válido para este resultado'
 241        if ((campos.tipo === 'llamada' || campos.tipo === 'whatsapp') && !dentroDeVentanaLegal(iso)) return 'Solo se contacta de lunes a sábado entre 07:00 y 20:00 (Ley 29571)'
 242        if (campos.tipo === 'reunion') {
 243          const reunion = validarReunionOperativa(camposReunion)
 244          if (!reunion.ok) return reunion.error
 245          entrada.siguiente = { tipo: 'reunion', titulo: campos.titulo.trim(), vence_en: iso, ...camposTareaDeReunion(reunion) }
 246        } else {
 247          entrada.siguiente = { tipo: campos.tipo, titulo: campos.titulo.trim(), vence_en: iso }
 248        }
 249      } else if (soyDueno && (def.clave === 'volver_a_llamar' || def.clave === 'agendo_reunion')) {
 250        return def.clave === 'volver_a_llamar' ? 'Indica cuándo volver a llamar' : 'Indica la fecha de la cita'
 251      }
 252      return entrada
 253    }
 254  
 255    const enviar = async (entrada: RegistrarLlamadaInput) => {
 256      if (enviando.current) return
 257      enviando.current = true
 258      setProcesando(true)
 259      try {
 260        const res = registrarLlamada(lead.id, entrada)
 261        if (!res.ok) { toast.error(res.error ?? 'No se pudo registrar la llamada'); return }
 262        const confirmado = await (res.persistido ?? Promise.resolve(true))
 263        if (!confirmado) { setSinConfirmar(entrada); return }
 264        const confirmacion = await (res.confirmacion ?? Promise.resolve(null))
 265        onClose()
 266        onGuardado?.()
 267        const partes = [`Llamada registrada · ${etiquetaResultado(entrada.resultado)}`]
 268        if (entrada.tarea_id && tarea) partes.push(`tarea cerrada («${presentarCitas(tarea.titulo)}»)`)
 269        if (res.avance && !res.descartado) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
 270        if (entrada.siguiente) partes.push(`siguiente ${tareaAEvento({ ...PLANTILLA, tipo: entrada.siguiente.tipo as Tarea['tipo'], titulo: entrada.siguiente.titulo, vence_en: entrada.siguiente.vence_en }, ahora).cuando}`)
 271        if (res.descartado) partes.push('lead descartado (Centro de rescate)')
 272        if (entrada.no_insista) partes.push('No insistir marcado')
 273        const texto = `${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`
 274        if (confirmacion && !entrada.no_insista) {
 275          toast.success(texto, {
 276            duration: 15_000,
 277            action: {
 278              label: 'Deshacer',
 279              onClick: () => {
 280                const r = deshacerResultadoLlamada(confirmacion.actividad_id)
 281                if (!r.ok) { toast.error(r.error ?? 'No se pudo deshacer'); return }
 282                void (r.persistido ?? Promise.resolve(true)).then((ok) => {
 283                  if (ok) toast.success(`Deshecho: ${nombre} vuelve a su etapa y la tarea creada se cancela`)
 284                })
 285              },
 286            },
 287          })
 288        } else {
 289          toast.success(texto)
 290        }
 291      } catch {
 292        setSinConfirmar(entrada)
 293      } finally {
 294        enviando.current = false
 295        setProcesando(false)
 296      }
 297    }
 298  
 299    const guardar = () => {
 300      if (sinConfirmar) return
 301      const entrada = armar()
 302      if (typeof entrada === 'string') { toast.error(entrada); return }
 303      void enviar(entrada)
 304    }
 305    // Con un guardado sin confirmar NO se afirma que no quedó nada: el servidor
 306    // pudo haberlo escrito. Queda en «Guardados por confirmar».
 307    const cerrarSinRegistrar = () => {
 308      if (enviando.current) return
 309      onClose()
 310      if (sinConfirmar) toast.warning('Guardado pendiente de confirmar: verifícalo en «Guardados por confirmar»')
 311      else toast.info('Llamada sin registrar: no quedó en el historial')
 312    }
 313  
 314    const opciones: OpcionRadio<ResultadoLlamada>[] = RESULTADOS.filter((r) => mostrarOpciones || r.clave === resultado).map((r) => ({ valor: r.clave, etiqueta: r.etiqueta, detalle: r.detalle, atajo: r.atajo }))
 315    const opcionesSubmotivo: OpcionRadio<SubmotivoLlamada>[] = def?.paso === 'submotivo'
 316      ? SUBMOTIVOS[def.clave as 'no_interesado' | 'pide_otro_producto'].map((s) => ({ valor: s.clave, etiqueta: s.etiqueta }))
 317      : []
 318    const opcionesDecision: OpcionRadio<DecisionNumero>[] = [
 319      ...(tieneSegundoNumero ? [{ valor: 'segundo_numero' as const, etiqueta: `Llamar al 2.º número (${lead.telefono_alternativo})`, detalle: 'Se agenda para hoy' }] : []),
 320      { valor: 'descartar' as const, etiqueta: 'Descartar por datos inválidos', detalle: 'Sale de tu cartera; puedes deshacerlo desde el aviso al guardar' },
 321      { valor: 'reintento' as const, etiqueta: 'Mantener con reintento a 7 días', detalle: 'Se agenda otra llamada' },
 322      { valor: 'solo_registrar' as const, etiqueta: 'Solo registrar', detalle: 'Sin tarea ni descarte' },
 323    ]
 324  
 325    return {
 326      lead, tarea, nombre, soyDueno, ahora,
 327      resultado, def, mostrarOpciones, setMostrarOpciones, enfocarResultado, elegir,
 328      submotivo, setSubmotivo, decision, setDecision, agendar, setAgendar, perdido, setPerdido,
 329      descartarInteres, setDescartarInteres, noInsista, setNoInsista, cierraTarea, setCierraTarea,
 330      nota, setNota, campos, editar, setTituloEditado, tituloEditado, camposReunion, setCamposReunion,
 331      procesando, sinConfirmar, enviar, guardar, cerrarSinRegistrar,
 332      intentosPrevios, ofrecePerdido, descarta, muestraSiguiente, siguienteOpcional, tiposSiguientes, cancelaria,
 333      opciones, opcionesSubmotivo, opcionesDecision,
 334    }
 335  }
 336  type ControlRegistro = ReturnType<typeof useRegistroResultado>
 337  
 338  /**
 339   * Los dos pasos del resultado, iguales en el diálogo y en la tarjeta. `grande`
 340   * = el diálogo de siempre (piso de 16 px); sin él, la escala del diseño de
 341   * Gestión Diaria que lleva la tarjeta «Ahora» (27/09/2026).
 342   */
 343  function CamposResultado({ c, grande, idBase }: { c: ControlRegistro; grande: boolean; idBase: string }): JSX.Element {
 344    const texto = grande ? 'text-base' : 'text-[13px]'
 345    const ids = { opciones: `${idBase}-opciones`, submotivo: `${idBase}-submotivo`, tipo: `${idBase}-siguiente-tipo`, titulo: `${idBase}-siguiente-titulo`, fecha: `${idBase}-siguiente-fecha`, hora: `${idBase}-siguiente-hora` }
 346    const { def, campos } = c
 347    return (
 348      <fieldset disabled={c.procesando || c.sinConfirmar !== null} className="min-w-0 space-y-3">
 349        <div id={ids.opciones}>
 350          <RadioGroup<ResultadoLlamada> grande={grande} leyenda="Resultado" opciones={grande ? c.opciones : c.opciones.map((o) => ({ ...o, detalle: undefined }))} valor={c.resultado} onCambio={c.elegir} obligatorio nombre="resultado-llamada" descripcion={c.mostrarOpciones ? 'Atajos: las teclas 1 a 7 eligen el resultado.' : 'Para elegir otro, usa «Cambiar resultado».'} />
 351        </div>
 352        {c.resultado && <Button type="button" variant="outline" size={grande ? 'default' : 'sm'} aria-expanded={c.mostrarOpciones} aria-controls={ids.opciones} onClick={() => {
 353          c.enfocarResultado.current = true
 354          c.setMostrarOpciones(!c.mostrarOpciones)
 355        }}>{c.mostrarOpciones ? 'Mantener resultado' : 'Cambiar resultado'}</Button>}
 356  
 357        {def?.paso === 'submotivo' && (
 358          <div className="space-y-3">
 359            <div>
 360              <Label htmlFor={ids.submotivo} className={texto}>{def.clave === 'no_interesado' ? '¿Por qué no le interesa?' : '¿Qué producto pide?'} · obligatorio</Label>
 361              <Select id={ids.submotivo} required value={c.submotivo ?? ''} className={texto} onChange={(e) => {
 362                c.setSubmotivo(c.opcionesSubmotivo.find((s) => s.valor === e.target.value)?.valor ?? null)
 363              }}>
 364                <option value="" disabled>Selecciona un motivo</option>
 365                {c.opcionesSubmotivo.map((s) => <option key={s.valor} value={s.valor}>{s.etiqueta}</option>)}
 366              </Select>
 367            </div>
 368            <label className={cn('flex cursor-pointer items-start gap-2 font-semibold', texto)}>
 369              <input type="checkbox" className="mt-1 size-4 shrink-0 accent-[var(--accent)]" checked={c.descartarInteres} onChange={(e) => c.setDescartarInteres(e.target.checked)} />
 370              <span>Descartar y enviar al Centro de rescate</span>
 371            </label>
 372            {c.descartarInteres && <p className={cn('font-semibold text-foreground/85', texto)}>
 373              {c.nombre} saldrá de tu cartera hacia el Centro de rescate; puedes deshacerlo desde el aviso al guardar (el servidor lo admite 24 h).
 374              {c.cancelaria > 0 && ` Se cancelarán ${c.cancelaria} ${c.cancelaria === 1 ? 'tarea pendiente' : 'tareas pendientes'}.`}
 375            </p>}
 376            <label className={cn('flex cursor-pointer items-start gap-2 font-semibold text-foreground/85', texto)}>
 377              <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.noInsista} onChange={(e) => c.setNoInsista(e.target.checked)} />
 378              <span>Pidió que no lo vuelvan a llamar <span className="font-normal text-[var(--muted-foreground-strong)]">(Ley 29571; esta marca no se puede deshacer desde aquí)</span></span>
 379            </label>
 380            {!c.descartarInteres && <p className={cn('text-muted-foreground', texto)}>El lead se mantiene en tu cartera. Este resultado no lo descarta.</p>}
 381          </div>
 382        )}
 383  
 384        {def?.paso === 'decision_numero' && (
 385          <div className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
 386            <RadioGroup<DecisionNumero> grande={grande} leyenda="¿Qué hacemos con este número?" opciones={c.opcionesDecision} valor={c.decision} onCambio={c.setDecision} obligatorio nombre="decision-numero" descripcion="Esta llamada cuenta como intento, pero no entra en la tasa de contacto." />
 387          </div>
 388        )}
 389  
 390        {c.ofrecePerdido && (
 391          <label className={cn('flex cursor-pointer items-start gap-2 rounded-xl border border-destructive/30 p-2.5 font-semibold text-foreground/85', texto)}>
 392            <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.perdido} onChange={(e) => c.setPerdido(e.target.checked)} />
 393            <span>Marcar perdido: no responde <span className="font-normal text-[var(--muted-foreground-strong)]">(ya van {c.intentosPrevios} intentos sin respuesta; sale de tu cartera; deshacer desde el aviso)</span></span>
 394          </label>
 395        )}
 396  
 397        {c.muestraSiguiente && campos && (
 398          <div className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
 399            {c.siguienteOpcional ? (
 400              <label className={cn('flex cursor-pointer items-start gap-2 font-semibold text-foreground/85', texto)}>
 401                <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.agendar} onChange={(e) => c.setAgendar(e.target.checked)} />
 402                <span>Agendar próxima acción <span className="font-normal text-[var(--muted-foreground-strong)]">(puedes ajustar el tipo, la fecha y la hora)</span></span>
 403              </label>
 404            ) : (
 405              <p className={cn('font-bold text-[var(--muted-foreground-strong)]', texto)}>{campos.tipo === 'reunion' ? 'La cita' : 'Cuándo volver a llamar'}</p>
 406            )}
 407            {(!c.siguienteOpcional || c.agendar) && (
 408              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
 409                <div className="sm:col-span-2">
 410                  <Label htmlFor={ids.tipo} className={texto}>Tipo de próxima acción</Label>
 411                  <Select id={ids.tipo} value={campos.tipo} className={texto} onChange={(e) => {
 412                    const tipo = e.target.value
 413                    if (!esTipoTarea(tipo) || !c.tiposSiguientes.includes(tipo)) return
 414                    c.editar({ tipo, ...(!c.tituloEditado ? { titulo: tituloProximaAccion(tipo, c.nombre) } : {}) })
 415                  }}>
 416                    {TIPOS_TAREA.filter((t) => c.tiposSiguientes.includes(t.k)).map((t) => <option key={t.k} value={t.k}>{t.label}</option>)}
 417                  </Select>
 418                </div>
 419                <div className="sm:col-span-2">
 420                  <Label htmlFor={ids.titulo} className={texto}>Título</Label>
 421                  <Input id={ids.titulo} value={campos.titulo} onChange={(e) => { c.setTituloEditado(true); c.editar({ titulo: e.target.value }) }} className={cn('h-10', texto)} maxLength={200} />
 422                </div>
 423                <div>
 424                  <Label htmlFor={ids.fecha} className={texto}>Fecha</Label>
 425                  <Input id={ids.fecha} type="date" value={campos.fecha} onChange={(e) => c.editar({ fecha: e.target.value })} className={cn('h-10', texto)} />
 426                </div>
 427                <div>
 428                  <Label htmlFor={ids.hora} className={texto}>Hora</Label>
 429                  <Input id={ids.hora} type="time" value={campos.hora} onChange={(e) => c.editar({ hora: e.target.value })} className={cn('h-10', texto)} />
 430                </div>
 431                {(campos.tipo === 'llamada' || campos.tipo === 'whatsapp') && (
 432                  <p className={cn('text-[var(--muted-foreground-strong)] sm:col-span-2', texto)}>Ventana legal: lunes a sábado, 07:00–20:00 (Lima).</p>
 433                )}
 434                {campos.tipo === 'reunion' && (
 435                  <div className="sm:col-span-2"><CamposReunion valor={c.camposReunion} onChange={c.setCamposReunion} /></div>
 436                )}
 437              </div>
 438            )}
 439          </div>
 440        )}
 441  
 442        <p role="status" className={c.noInsista || c.lead.no_contactar ? cn('text-muted-foreground', texto) : 'sr-only'}>
 443          {(c.noInsista || c.lead.no_contactar) ? 'No volver a contactar: no se agendará una próxima acción.' : ''}
 444        </p>
 445  
 446        {def && !c.soyDueno && !c.descarta && !c.noInsista && (
 447          <p className={cn('text-muted-foreground', texto)}>La agenda es del analista dueño del lead: se registra la llamada sin agendar el siguiente paso.</p>
 448        )}
 449  
 450        {c.tarea && (
 451          <label className={cn('flex cursor-pointer items-start gap-2 font-semibold text-foreground/85', texto)}>
 452            <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.cierraTarea} onChange={(e) => c.setCierraTarea(e.target.checked)} />
 453            <span>Cerrar también «{presentarCitas(c.tarea.titulo)}» <span className="font-normal text-muted-foreground">({tareaAEvento(c.tarea, c.ahora).cuando})</span></span>
 454          </label>
 455        )}
 456  
 457        <Textarea aria-label="Nota de la llamada" value={c.nota} onChange={(e) => c.setNota(e.target.value)} placeholder="Nota (opcional)…" className={cn('min-h-[56px]', texto)} />
 458      </fieldset>
 459    )
 460  }
 461  
 462  /** El diálogo de siempre: ficha del lead, Hoy, colas y composer. Contrato intacto. */
 463  export function RegistrarResultado(props: RegistrarResultadoProps): JSX.Element {
 464    const raiz = useRef<HTMLDivElement>(null)
 465    const idBase = useId()
 466    const c = useRegistroResultado(props, raiz, (objetivo) => {
 467      // Solo mientras ESTE diálogo tiene el foco (WCAG 2.1.4), no cualquier modal apilado.
 468      const dialogo = raiz.current?.closest<HTMLElement>('[role="dialog"]')
 469      return Boolean(dialogo) && objetivo instanceof Node && dialogo!.contains(objetivo)
 470    })
 471    return (
 472      <Dialog open onClose={() => { if (!c.procesando) props.onClose() }} ariaLabel="Resultado de la llamada" className="w-[560px] [&_button]:text-base [&_select]:text-base [&_label]:text-base [&_p]:text-base">
 473        {/* Columna flex que hereda la altura del Dialog: sin esto el cuerpo no
 474            obtiene su scroll interno y «Guardar» queda fuera de la pantalla. */}
 475        <div ref={raiz} className="flex min-h-0 flex-1 flex-col">
 476          <DialogHeader>
 477            <DialogTitle className="text-xl">¿Cómo salió la llamada con {c.nombre}?</DialogTitle>
 478            <DialogDescription className="text-base">
 479              Registra el resultado y elige la próxima acción. Se guardan juntos en el historial y la agenda.
 480            </DialogDescription>
 481          </DialogHeader>
 482          <DialogBody className="space-y-3">
 483            <CamposResultado c={c} grande idBase={idBase} />
 484            {c.sinConfirmar && <p role="alert" className="text-base text-destructive">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
 485          </DialogBody>
 486          <DialogFooter>
 487            <Button variant="ghost" size="sm" disabled={c.procesando} onClick={c.cerrarSinRegistrar}>
 488              {c.sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
 489            </Button>
 490            {c.sinConfirmar
 491              ? <Button size="sm" disabled={c.procesando} onClick={() => void c.enviar(c.sinConfirmar!)}>{c.procesando ? 'Confirmando…' : 'Reintentar guardado'}</Button>
 492              : <Button size="sm" disabled={c.procesando || !c.resultado} onClick={c.guardar}>{c.procesando ? 'Guardando…' : 'Guardar'}</Button>}
 493          </DialogFooter>
 494        </div>
 495      </Dialog>
 496    )
 497  }
 498  
 499  /**
 500   * El resultado DENTRO de la tarjeta «Ahora» de «Mi día» (diseño del 27/09/2026):
 501   * sin ventana encima. No finge un diálogo: es una sección con su título, y su
 502   * teclado es propio (atajos 1–7 con el foco dentro; Escape = cerrar sin
 503   * registrar, salvo mientras guarda). Al abrir, el foco va a los resultados.
 504   */
 505  export function RegistroResultadoTarjeta(props: RegistrarResultadoProps): JSX.Element {
 506    const raiz = useRef<HTMLElement>(null)
 507    const idBase = useId()
 508    const c = useRegistroResultado(props, raiz, (objetivo) => objetivo instanceof Node && Boolean(raiz.current?.contains(objetivo)))
 509    useEffect(() => {
 510      raiz.current?.querySelector<HTMLInputElement>('input[name="resultado-llamada"]')?.focus()
 511    }, [])
 512    const alTecla = (e: EventoTeclado<HTMLElement>) => {
 513      if (e.key !== 'Escape' || e.defaultPrevented || c.procesando) return
 514      e.preventDefault()
 515      e.stopPropagation()
 516      c.cerrarSinRegistrar()
 517    }
 518    return (
 519      // oxlint-disable-next-line jsx-a11y/no-noninteractive-element-interactions -- Escape de la sección: el contrato de teclado de la tarjeta (Codex, 27/09).
 520      <section ref={raiz} aria-labelledby={`${idBase}-titulo`} onKeyDown={alTecla} className="flex min-h-0 flex-1 flex-col">
 521        <div className="ac-scroll min-h-0 flex-1 space-y-3 overflow-y-auto px-[18px] pb-3">
 522          <h4 id={`${idBase}-titulo`} className="text-sm font-extrabold text-primary">¿Qué pasó con la llamada?</h4>
 523          <CamposResultado c={c} grande={false} idBase={idBase} />
 524          {c.sinConfirmar && <p role="alert" className="text-[13px] font-semibold text-destructive">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
 525        </div>
 526        {/* Pegado abajo también en el celular, donde la tarjeta no tiene alto fijo
 527            y la página es la que se desplaza: «Guardar» nunca queda fuera de la vista. */}
 528        <div className="sticky bottom-0 z-10 flex shrink-0 items-center justify-between gap-2 border-t border-border bg-card px-[18px] py-3">
 529          <button type="button" disabled={c.procesando} onClick={c.cerrarSinRegistrar}
 530            className="inline-flex h-10 cursor-pointer items-center rounded-[10px] px-2.5 text-[13px] font-bold text-[var(--accent-press)] transition-colors hover:bg-accent/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring disabled:opacity-50">
 531            {c.sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
 532          </button>
 533          {c.sinConfirmar
 534            ? <Button className="h-10 rounded-[10px] bg-accent px-4 text-[13px] font-bold hover:bg-accent-press" disabled={c.procesando} onClick={() => void c.enviar(c.sinConfirmar!)}>{c.procesando ? 'Confirmando…' : 'Reintentar guardado'}</Button>
 535            : <Button className="h-10 rounded-[10px] bg-accent px-4 text-[13px] font-bold hover:bg-accent-press" disabled={c.procesando || !c.resultado} onClick={c.guardar}>{c.procesando ? 'Guardando…' : 'Guardar'}</Button>}
 536        </div>
 537      </section>
 538    )
 539  }
```

### `components/gestion-diaria/cola-de-hoy.tsx`
```tsx
   1  // La cola del día (rediseño del 27/09/2026, diseño de Gestión Diaria con los
   2  // colores del CRM). Filtros en PASTILLA —«Todo» primero y los cuatro grupos—,
   3  // una sola lista a la vista y filas limpias de borde a borde: iniciales,
   4  // nombre, qué toca y el tiempo en palabras. El contexto largo sigue en
   5  // «Ahora»: elegir una fila la lleva allí. Escala y aire: los del diseño.
   6  //
   7  // «Todo» NO es un grupo (hallazgo de Codex): es la cola entera en el orden del
   8  // día. Las pastillas siguen siendo `tab`/`tabpanel` para el lector de pantalla.
   9  //
  10  // La fila es un `<button>` real con `aria-current`, no un `div` con onClick ni
  11  // un `aria-pressed`: esto es una selección única dentro de una lista, y así el
  12  // tabulador y el lector de pantalla la entienden sin inventar teclado propio.
  13  // La elegida se marca con el avatar RELLENO (cambia la forma, no solo el color),
  14  // el nombre en azul y, para el lector, `aria-current` + «Elegido».
  15  import type { JSX } from 'react'
  16  import { ChevronLeft, ChevronRight, PhoneCall } from 'lucide-react'
  17  import { ChipTiempo } from '@/components/gestion-diaria/chip-tiempo'
  18  import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
  19  import { Avatar } from '@/components/ui/avatar'
  20  import { Tabs } from '@/components/ui/tabs'
  21  import { cn } from '@/lib/utils'
  22  import {
  23    FILTRO_TODO, GRUPOS_DIA, detalleDeFila, filasDelFiltro, paginaDeFilas,
  24    type FilaDiaria, type FiltroCola, type GrupoDia,
  25  } from '@/lib/gestion-diaria-analista'
  26  import { hashDe } from '@/lib/router'
  27  
  28  export const FILAS_POR_PAGINA = 8
  29  
  30  export interface PestanaCola {
  31    clave: GrupoDia
  32    etiqueta: string
  33    ayuda: string
  34    total: number
  35    filas: FilaDiaria[]
  36  }
  37  
  38  const ETIQUETA_GRUPO = Object.fromEntries(GRUPOS_DIA.map((g) => [g.clave, g.etiqueta])) as Record<GrupoDia, string>
  39  const BOTON_PAGINA = 'inline-flex h-8 cursor-pointer items-center gap-1 rounded-lg border border-border bg-card px-2.5 text-[13px] font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-45 aria-disabled:hover:bg-card'
  40  
  41  export function ColaDeHoy({
  42    idBase, pestanas, filtro, onFiltro, pagina, onPagina, elegido, onElegir, ahora, cargando, hayMas, colaCaida, sinConversacionDias,
  43  }: {
  44    /** Base de `useId()` de la pantalla: dos instancias no pueden compartir id. */
  45    idBase: string
  46    pestanas: readonly PestanaCola[]
  47    filtro: FiltroCola
  48    onFiltro: (filtro: FiltroCola) => void
  49    pagina: number
  50    onPagina: (pagina: number) => void
  51    elegido: string | null
  52    onElegir: (fila: FilaDiaria) => void
  53    ahora: number
  54    cargando: boolean
  55    /** El servidor dice que hay más de lo que cabe en esta lectura. */
  56    hayMas: boolean
  57    /**
  58     * La cola del servidor no llegó. Los tres primeros grupos SALEN de ella, así
  59     * que sus conteos no son ceros: son desconocidos. Decir «Vencidas (0)» haría
  60     * que el analista se fuera a casa creyendo que no debía nada (Codex, 20/09).
  61     */
  62    colaCaida: boolean
  63    sinConversacionDias: number
  64  }): JSX.Element {
  65    const lista = filasDelFiltro(pestanas, filtro)
  66    const vista = paginaDeFilas(lista, pagina, FILAS_POR_PAGINA)
  67    const sinAnterior = vista.pagina === 0
  68    const sinSiguiente = vista.pagina >= vista.paginas - 1
  69    const vacioTodo = pestanas.every((p) => p.total === 0)
  70    const total = pestanas.reduce((n, p) => n + p.total, 0)
  71    // Con la cola caída, lo que sale de ella no tiene conteo conocido: «?» y no
  72    // «0». Con `hayMas` el conteo es un MÍNIMO.
  73    const conteo = (clave: FiltroCola, n: number) => colaCaida && clave !== 'sin_conversacion' ? '?' : hayMas ? `${n}+` : String(n)
  74    const etiquetaFiltro = filtro === 'todo' ? FILTRO_TODO.etiqueta : ETIQUETA_GRUPO[filtro]
  75    const ayuda = filtro === 'todo' ? 'El orden lo pone el servidor, como en tu Hoy.' : pestanas.find((p) => p.clave === filtro)?.ayuda
  76  
  77    return (
  78      <section aria-labelledby={`${idBase}-cola`} className="relative flex min-h-0 flex-1 flex-col">
  79        <h3 id={`${idBase}-cola`} className="sr-only">Cola de hoy</h3>
  80        {cargando ? (
  81          <div className="p-[18px]"><PanelCargando filas={FILAS_POR_PAGINA} /></div>
  82        ) : vacioTodo && !colaCaida ? (
  83          <PanelVacio
  84            icono={PhoneCall}
  85            titulo="No tienes nada pendiente ahora"
  86            detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana."
  87          />
  88        ) : (
  89          <>
  90            <p className="pointer-events-none absolute right-[18px] top-3 hidden h-9 items-center text-xs text-[var(--muted-foreground-strong)] 2xl:flex">{ayuda}</p>
  91            <Tabs
  92              etiqueta="Grupos de la cola"
  93              variante="pastilla"
  94              valor={filtro}
  95              onCambio={onFiltro}
  96              pestanas={[
  97                { valor: 'todo' as FiltroCola, etiqueta: FILTRO_TODO.etiqueta, extra: conteo('todo', total) },
  98                ...pestanas.map((p) => ({ valor: p.clave as FiltroCola, etiqueta: p.etiqueta, extra: conteo(p.clave, p.total) })),
  99              ]}
 100              className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]]:border-b [&>[role=tablist]]:border-muted [&>[role=tablist]]:px-[18px] [&>[role=tablist]]:py-3 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold [&>[role=tablist]>[role=tab]>span]:text-[12.5px]"
 101              clasePanel="flex min-h-0 flex-1 flex-col"
 102            >
 103              {vista.total === 0 ? (
 104                <p role="status" className="px-[18px] py-7 text-center text-[13px] text-[var(--muted-foreground-strong)]">
 105                  {colaCaida && filtro !== 'sin_conversacion'
 106                    ? 'No se pudo leer esta parte de la cola del servidor. No está vacía: no se sabe. Actualiza para verla.'
 107                    : 'Nada en este grupo. Mira los otros: su número está al lado del nombre.'}
 108                </p>
 109              ) : (
 110                <>
 111                  {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 112                  <ol role="list" aria-label={`${etiquetaFiltro} (${vista.rango})`} className="ac-scroll min-h-0 flex-1 overflow-y-auto">
 113                    {vista.filas.map((fila) => {
 114                      const seleccionada = fila.lead_id === elegido
 115                      const apoyo = filtro === 'todo'
 116                        ? `${ETIQUETA_GRUPO[fila.grupo]} · ${detalleDeFila(fila, sinConversacionDias)}`
 117                        : detalleDeFila(fila, sinConversacionDias)
 118                      return (
 119                        <li key={fila.lead_id} className="border-b border-muted">
 120                          <button
 121                            type="button"
 122                            {...(seleccionada ? { 'aria-current': true as const } : {})}
 123                            onClick={() => onElegir(fila)}
 124                            className={cn(
 125                              'flex w-full min-h-[62px] cursor-pointer items-center gap-3 px-[18px] text-left transition-colors',
 126                              'focus-visible:-outline-offset-2 focus-visible:outline-2 focus-visible:outline-ring',
 127                              seleccionada ? 'bg-accent/[0.06]' : 'hover:bg-muted/50',
 128                            )}
 129                          >
 130                            <Avatar nombre={fila.nombre_completo} color="var(--accent-press)" relleno={seleccionada} />
 131                            <span className="flex min-w-0 flex-1 flex-col gap-px">
 132                              <span className={cn('truncate text-sm font-bold', seleccionada ? 'text-[var(--accent-press)]' : 'text-primary')}>{fila.nombre_completo}</span>
 133                              <span className="truncate text-xs font-medium text-[var(--muted-foreground-strong)]">{apoyo}</span>
 134                            </span>
 135                            {seleccionada && <span className="sr-only">Elegido</span>}
 136                            <ChipTiempo fila={fila} ahora={ahora} className="shrink-0" />
 137                          </button>
 138                        </li>
 139                      )
 140                    })}
 141                  </ol>
 142  
 143                  <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-[18px] py-2.5">
 144                    {/* Se ANUNCIA: al pasar de página cambian las filas y sin esto el
 145                        lector de pantalla no diría nada (WCAG 4.1.3). */}
 146                    <p role="status" aria-live="polite" className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">
 147                      {vista.rango}{hayMas && <> de los cargados · <a className="font-semibold text-primary underline underline-offset-4" href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })}>Ver todas las oportunidades</a></>}
 148                    </p>
 149                    <div className="flex items-center gap-1.5">
 150                      {/* `aria-disabled` y no `disabled`, con la guarda en el handler:
 151                          el botón se deshabilita a sí mismo al pulsarse (última página)
 152                          y un `disabled` sobre el elemento enfocado manda el foco al
 153                          body — la misma regla de la casa que «Deshacer». */}
 154                      <button type="button" className={BOTON_PAGINA} aria-disabled={sinAnterior}
 155                        onClick={() => { if (!sinAnterior) onPagina(vista.pagina - 1) }}><ChevronLeft aria-hidden className="size-4" />Anterior</button>
 156                      <button type="button" className={BOTON_PAGINA} aria-disabled={sinSiguiente}
 157                        onClick={() => { if (!sinSiguiente) onPagina(vista.pagina + 1) }}>Siguiente<ChevronRight aria-hidden className="size-4" /></button>
 158                    </div>
 159                  </div>
 160                </>
 161              )}
 162            </Tabs>
 163          </>
 164        )}
 165      </section>
 166    )
 167  }
```

## DIFFS del resto (ee4d29e1..HEAD)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/app/contacto.tsx b/CRM-Avance-Corp/app/src/components/app/contacto.tsx
index f7a7d068..bc7776dd 100644
--- a/CRM-Avance-Corp/app/src/components/app/contacto.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/contacto.tsx
@@ -85,6 +85,7 @@ export function AccionesContacto({
   grande,
   onGuardado,
   onRegistrarLlamada,
+  onLlamar,
 }: {
   lead: LeadContactable
   compacto?: boolean
@@ -114,6 +115,14 @@ export function AccionesContacto({
   onGuardado?: (() => void) | undefined
   /** «Mi día» resuelve su tarea de servidor y usa el mismo panel desde ambos accesos. */
   onRegistrarLlamada?: (() => void) | undefined
+  /**
+   * Aviso SÍNCRONO de que se pulsó «Llamar», antes de copiar o de salir al
+   * marcador (27/09/2026): «Mi día» fija ahí a la persona, para que un refresco
+   * mientras el analista está en la llamada no cambie la tarjeta ni pierda la
+   * pregunta del resultado al volver. Síncrono a propósito: en iOS un `await`
+   * antes de navegar a `tel:` corta la activación y el marcador no abre.
+   */
+  onLlamar?: (() => void) | undefined
 }): JSX.Element {
   const { yo } = useAuth()
   const escribe = puedeEscribir(yo?.rol)
@@ -220,7 +229,7 @@ export function AccionesContacto({
           href={tel}
           className={CLASE_ACCION}
           aria-label={`Llamar a ${lead.nombre_completo}`}
-          onClick={marcar('tel')}
+          onClick={() => { marcar('tel')(); onLlamar?.() }}
         >
           <Phone /> <span className={labelCls}>Llamar</span>
         </a>
@@ -229,7 +238,7 @@ export function AccionesContacto({
           type="button"
           className={CLASE_ACCION}
           aria-label={`Copiar el número de ${lead.nombre_completo} y registrar la llamada`}
-          onClick={llamar}
+          onClick={() => { onLlamar?.(); void llamar() }}
         >
           <Phone /> <span className={labelCls}>Llamar</span>
         </button>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/barras-por-hora.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/barras-por-hora.tsx
new file mode 100644
index 00000000..e606271a
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/barras-por-hora.tsx
@@ -0,0 +1,70 @@
+// Llamadas por hora, 08–20 Lima (decisión #8 de Miguel): UNA pieza para el
+// analista, el supervisor y gerencia (diseño del 27/09/2026). Cada columna
+// apila lo que contestaron (azul) debajo de lo que no (azul tenue) y lleva su
+// número encima: se lee sin pasar el ratón. Antes eran barras navy macizas con
+// el azul dentro, que no se distinguían.
+//
+// Accesible: el dibujo es decorativo (`aria-hidden`) y el dato viaja en una
+// lista de solo lectura para el lector de pantalla, con las horas que tuvieron
+// llamadas. La escala de letra es la del diseño (Miguel, 27/09/2026).
+import { useId, type JSX } from 'react'
+import { barrasPorHora, llamadasFueraDeFranja, type Marcador } from '@/lib/gestion-diaria-analista'
+import { cn } from '@/lib/utils'
+
+const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
+
+export function BarrasPorHora({ porHora, titulo, apoyo, alto = 110, className }: {
+  porHora: Marcador['por_hora']
+  titulo: string
+  /** Texto a la derecha del título («Última llamada 16:05»). */
+  apoyo?: string | undefined
+  /** Alto del dibujo en px, sin contar números ni horas. */
+  alto?: number | undefined
+  className?: string | undefined
+}): JSX.Element {
+  const id = useId()
+  const barras = barrasPorHora({ por_hora: porHora })
+  const conLlamadas = barras.filter((b) => b.llamadas > 0)
+  const fuera = llamadasFueraDeFranja({ por_hora: porHora })
+  return (
+    <div className={cn('space-y-2', className)}>
+      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
+        <h4 id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">{titulo}</h4>
+        {apoyo !== undefined && <p className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">{apoyo}</p>}
+      </div>
+      {conLlamadas.length === 0 ? (
+        <p className="text-[13px] text-[var(--muted-foreground-strong)]">
+          {fuera > 0 ? `Sin llamadas entre las 08 y las 20; ${plural(fuera, 'llamada', 'llamadas')} fuera de esa franja.` : 'Todavía no hay llamadas hoy.'}
+        </p>
+      ) : (
+        <>
+          <div aria-hidden="true" className="flex items-end gap-1.5" style={{ height: alto + 40 }}>
+            {barras.map((b) => {
+              const noContestadas = Math.round(((b.llamadas - b.contestadas) / b.maximo) * alto)
+              const contestadas = Math.round((b.contestadas / b.maximo) * alto)
+              return (
+                <div key={b.hora} className="flex h-full min-w-0 flex-1 flex-col items-center justify-end">
+                  <span className={cn('mb-[3px] text-[11px] font-bold tabular-nums text-foreground/80', b.llamadas === 0 && 'invisible')}>{b.llamadas}</span>
+                  <span className={cn('w-full max-w-[22px] bg-accent/25', noContestadas > 0 && 'rounded-t')} style={{ height: noContestadas }} />
+                  <span className={cn('w-full max-w-[22px] bg-accent', noContestadas === 0 && contestadas > 0 && 'rounded-t')} style={{ height: contestadas }} />
+                  <span className="mt-[5px] text-[11px] tabular-nums text-[var(--muted-foreground-strong)]">{String(b.hora).padStart(2, '0')}</span>
+                </div>
+              )
+            })}
+          </div>
+          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
+          <ul role="list" aria-labelledby={`${id}-titulo`} className="sr-only">
+            {conLlamadas.map((b) => (
+              <li key={b.hora}>{b.hora}:00 — {plural(b.llamadas, 'llamada', 'llamadas')}, {plural(b.contestadas, 'contestada', 'contestadas')}</li>
+            ))}
+          </ul>
+          <div className="flex flex-wrap items-center gap-x-3.5 gap-y-1 text-xs text-foreground/80">
+            <span className="inline-flex items-center gap-1.5"><span aria-hidden="true" className="size-2.5 rounded-[3px] bg-accent" />Contestaron</span>
+            <span className="inline-flex items-center gap-1.5"><span aria-hidden="true" className="size-2.5 rounded-[3px] bg-accent/25" />No contestaron</span>
+            {fuera > 0 && <span>{plural(fuera, 'llamada', 'llamadas')} fuera de la franja 08–20.</span>}
+          </div>
+        </>
+      )}
+    </div>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/chip-tiempo.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/chip-tiempo.tsx
index fe2bae9c..75ab45c4 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/chip-tiempo.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/chip-tiempo.tsx
@@ -5,8 +5,8 @@
 // 20/09/2026). El estado NO viaja solo en el color — el texto ya lo dice —, así
 // que cumple la regla de la casa por construcción.
 //
-// Tamaño: 16 px, el piso de la pantalla del analista. `Badge` nace a 11 px para
-// los chips de ficha, así que aquí se sube explícitamente; el color va por la
+// Tamaño: el chip del diseño de Gestión Diaria (27/09/2026, Miguel: respetar la
+// escala del diseño): 11,5 px en negrita y 22 px de alto. El color va por la
 // variante «-text» (oscura) porque `soft` pinta sobre un tinte al 12 % y los
 // tonos puros no llegan al contraste de texto (está escrito en `index.css`).
 import type { JSX } from 'react'
@@ -28,7 +28,7 @@ export function ChipTiempo({ fila, ahora, className }: {
   return (
     <Badge
       color={COLOR_TONO[tono]}
-      className={`px-3 py-0.5 text-base font-normal leading-6 ${className ?? ''}`}
+      className={`min-h-[22px] whitespace-nowrap py-0 text-[11.5px] ${className ?? ''}`}
     >
       {texto}
     </Badge>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
new file mode 100644
index 00000000..049ac76e
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
@@ -0,0 +1,62 @@
+// La franja de cifras del día (diseño de Gestión Diaria, 27/09/2026): UNA
+// tarjeta plana con las cifras separadas por rayas finas, la etiqueta en
+// versalitas arriba, el número grande y su apoyo al lado. Nace para «Mi día»
+// del analista y la reusan supervisor y gerencia, así que no sabe de negocio:
+// recibe las cifras ya calculadas por el servidor.
+//
+// Escala y aire: los del diseño (Miguel, 27/09/2026: «que prevalezca el diseño,
+// lo limpio que se ve»). Etiqueta 11 px, número 28 px, apoyo 12 px.
+import type { JSX, ReactNode } from 'react'
+import { cn } from '@/lib/utils'
+
+export interface CifraDelDia {
+  etiqueta: string
+  valor: string
+  /** Lo que debe OÍR un lector de pantalla cuando el valor es un símbolo mudo («—»). */
+  valorAccesible?: string | undefined
+  /** Texto o chip que acompaña al número («de 18», «hoy», el nivel). */
+  apoyo?: ReactNode
+  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy». */
+  tono?: 'normal' | 'alerta' | undefined
+}
+
+// Clases escritas enteras: Tailwind no ve las que se arman con plantillas.
+const COLUMNAS: Record<number, string> = {
+  1: 'sm:grid-cols-1', 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4', 5: 'sm:grid-cols-5', 6: 'sm:grid-cols-6',
+}
+
+export function FranjaCifras({ etiqueta, cifras, className }: {
+  /** Nombre del grupo para el lector de pantalla («Tu día en cifras»). */
+  etiqueta: string
+  cifras: readonly CifraDelDia[]
+  className?: string | undefined
+}): JSX.Element {
+  return (
+    <section aria-label={etiqueta} className={cn('rounded-2xl border border-border bg-card', className)}>
+      <dl className={cn('grid grid-cols-2 gap-y-4 py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
+        {cifras.map((c, i) => (
+          // En el celular son 2 por fila (raya solo en la segunda); desde tablet,
+          // raya a la izquierda de todas menos la primera.
+          <div key={c.etiqueta} className={cn('flex min-w-0 flex-col gap-1 px-5', i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
+            <dt className="text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
+            <dd className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
+              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', c.tono === 'alerta' ? 'text-[var(--destructive-text)]' : 'text-primary')}>
+                {c.valorAccesible !== undefined ? (
+                  <>
+                    <span aria-hidden="true">{c.valor}</span>
+                    <span className="sr-only">{c.valorAccesible}</span>
+                  </>
+                ) : c.valor}
+              </span>
+              {c.apoyo !== undefined && c.apoyo !== null && (
+                typeof c.apoyo === 'string'
+                  ? <span className="text-xs text-[var(--muted-foreground-strong)]">{c.apoyo}</span>
+                  : c.apoyo
+              )}
+            </dd>
+          </div>
+        ))}
+      </dl>
+    </section>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
index 9fcd448a..70c05c73 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
@@ -59,6 +59,13 @@ interface Props {
   onSinPermiso?: (() => void) | undefined
   /** H3: comparte la primera página sin filtro con Últimas gestiones. */
   compartirPrimeraPagina?: boolean
+  /**
+   * «¿Qué hice hoy?» del analista (diseño del 27/09/2026): título corto,
+   * filtros en pastilla y filas limpias, sin la descripción, el filtro de etapa
+   * ni el «Actualizar» propio (la pantalla ya se refresca cada minuto).
+   * Supervisor y gerencia conservan su versión hasta sus propios planes.
+   */
+  compacto?: boolean
 }
 
 export function RegistroActividad(props: Props) {
@@ -68,7 +75,7 @@ export function RegistroActividad(props: Props) {
   return <RegistroDelAmbito key={identidad} {...props} />
 }
 
-function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo = false, permitirExportar, pestanaInicial = 'llamadas', actualizacion = 0, onSinPermiso, compartirPrimeraPagina = false }: Props) {
+function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo = false, permitirExportar, pestanaInicial = 'llamadas', actualizacion = 0, onSinPermiso, compartirPrimeraPagina = false, compacto = false }: Props) {
   const { yo } = useAuth()
   const ahora = useAhora()
   const { equipo, ambito } = useCRMData()
@@ -209,6 +216,50 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
     </>
   )
 
+  const listaCompacta = (
+    <>
+      <p role="status" aria-live="polite" className="sr-only">
+        {visibles.length} {visibles.length === 1 ? 'gestión' : 'gestiones'} cargadas{hayMas ? ' · hay más' : ''}{enVuelo ? ' · actualizando…' : ''}
+      </p>
+      <ol aria-label="Registro de actividad" aria-busy={enVuelo}>
+        {visibles.map((item) => {
+          const tono = tonoDeTipo(item.tipo)
+          const etapaEntonces = item.etapa_en_ese_momento ? ETAPA_INFO[item.etapa_en_ese_momento as Etapa]?.label ?? item.etapa_en_ese_momento : null
+          const etapaActual = ETAPA_INFO[item.lead_etapa as Etapa]?.label ?? item.lead_etapa
+          const resultado = typeof item.metadata['resultado'] === 'string' ? (item.metadata['resultado'] as string) : null
+          return (
+            <li key={item.id} className="flex gap-3 border-b border-muted py-2.5">
+              <time dateTime={item.creado_en} className="w-10 shrink-0 pt-0.5 text-[13px] font-bold tabular-nums text-foreground/80">{horaDeItem(item)}</time>
+              <div className="min-w-0 flex-1 space-y-1">
+                <div className="flex flex-wrap items-center gap-2">
+                  <Badge className="min-h-[22px] py-0 text-[11.5px]" color={TONO[tono]}>{ETIQUETA_CORTA[item.tipo]}</Badge>
+                  {resultado && <Badge className="min-h-[22px] py-0 text-[11.5px]" color="var(--primary)" variant="outline">{resultado.replaceAll('_', ' ')}</Badge>}
+                  <button type="button" onClick={() => void abrirLead(item.lead_id)}
+                    className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
+                    {item.lead_nombre}
+                  </button>
+                </div>
+                {item.detalle && <p className="whitespace-pre-wrap break-words text-[13px] leading-snug text-foreground/80">{item.detalle}</p>}
+                <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">{etapaEntonces ? `${etapaEntonces} entonces · ` : ''}{etapaActual} ahora</p>
+              </div>
+            </li>
+          )
+        })}
+      </ol>
+      {error && visibles.length > 0 && (
+        <p role="alert" className="text-[13px] font-semibold text-[var(--warning-text)]">No se pudo traer la siguiente página. Se conservan las ya consultadas.</p>
+      )}
+      {(hayMas || (error && visibles.length > 0)) && (
+        <div className="flex justify-center pt-2">
+          <button type="button" disabled={enVuelo} onClick={error ? () => void recargar() : verMas}
+            className="inline-flex h-9 cursor-pointer items-center rounded-[10px] px-3 text-[13px] font-bold text-[var(--accent-press)] transition-colors hover:bg-accent/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring disabled:opacity-50">
+            {error ? 'Reintentar' : 'Ver más'}
+          </button>
+        </div>
+      )}
+    </>
+  )
+
   const panel = sinPermiso ? (
     <div role="alert" className="space-y-2 rounded-xl border border-border bg-card p-6 text-base">
       <h4 className="font-semibold text-primary">Ya no tienes autorización para ver este registro</h4>
@@ -227,7 +278,21 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
   ) : visibles.length === 0 ? (
     <PanelVacio tamano="grande" icono={ClipboardList} titulo={pestana === 'todo' && etapa === null ? (esHoy ? 'Todavía no hay actividad hoy' : 'Sin actividad ese día') : 'No hay actividad con estos filtros'}
       detalle={pestana === 'todo' && etapa === null ? 'Ninguna gestión registrada en el ámbito consultado.' : 'Prueba con la pestaña «Todo» u otra etapa. Esto no significa que no haya otras gestiones.'} />
-  ) : lista
+  ) : compacto ? listaCompacta : lista
+
+  if (compacto) {
+    return (
+      <section aria-labelledby={`${id}-titulo`} className="space-y-2">
+        <h3 ref={encabezado} tabIndex={-1} id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">
+          ¿Qué hice hoy?
+        </h3>
+        <Tabs variante="pastilla" etiqueta="Tipo de actividad" pestanas={PESTANAS_REGISTRO} valor={pestana} onCambio={setPestana}
+          className="space-y-2 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold">
+          {panel}
+        </Tabs>
+      </section>
+    )
+  }
 
   return (
     <section aria-labelledby={`${id}-titulo`} className="space-y-4">
diff --git a/CRM-Avance-Corp/app/src/components/ui/avatar.tsx b/CRM-Avance-Corp/app/src/components/ui/avatar.tsx
index b30267fd..19d3d0ef 100644
--- a/CRM-Avance-Corp/app/src/components/ui/avatar.tsx
+++ b/CRM-Avance-Corp/app/src/components/ui/avatar.tsx
@@ -69,11 +69,18 @@ export function Avatar({
   nombre,
   genero,
   color = 'var(--accent)',
+  relleno = false,
   className,
 }: {
   nombre: string | null | undefined
   genero?: Genero | null
   color?: string | undefined
+  /**
+   * Iniciales en blanco sobre el color pleno: marca a la persona ELEGIDA en una
+   * lista (Gestión Diaria, 27/09/2026). Nunca va sola: la fila lo dice también
+   * con `aria-current` y con texto.
+   */
+  relleno?: boolean | undefined
   className?: string | undefined
 }): JSX.Element {
   // Silueta SOLO con género conocido; sin dato (null/ausente) → iniciales.
@@ -100,7 +107,7 @@ export function Avatar({
   return (
     <span
       className={cn(BASE, 'text-[11px] font-bold', className)}
-      style={{ background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
+      style={relleno ? { background: color, color: '#fff' } : { background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
       aria-hidden
     >
       {iniciales(nombre)}
diff --git a/CRM-Avance-Corp/app/src/components/ui/tabs.tsx b/CRM-Avance-Corp/app/src/components/ui/tabs.tsx
index d216efbd..a5f1645a 100644
--- a/CRM-Avance-Corp/app/src/components/ui/tabs.tsx
+++ b/CRM-Avance-Corp/app/src/components/ui/tabs.tsx
@@ -29,6 +29,16 @@ interface TabsProps<V extends string> {
    * usaba esta primitiva: ranking, supervisor, repartir y rentabilidad.
    */
   tamano?: 'normal' | 'grande' | undefined
+  /**
+   * Aspecto del tablist (27/09/2026, diseño de Gestión Diaria). `segmentado`
+   * es el de siempre y el default: nadie que ya lo use cambia. `subrayado`
+   * separa las vistas de una tarjeta con una raya bajo la activa; `pastilla`
+   * pinta filtros redondos con el activo relleno. El patrón APG no cambia:
+   * siguen siendo `tab`/`tabpanel`, para el lector de pantalla y las pruebas.
+   */
+  variante?: 'segmentado' | 'subrayado' | 'pastilla' | undefined
+  /** Clases del `tabpanel` (p. ej. para que herede la altura de la tarjeta). */
+  clasePanel?: string | undefined
 }
 
 const CLASES_TAMANO = {
@@ -36,13 +46,38 @@ const CLASES_TAMANO = {
   grande: { tab: 'min-h-12 px-4 py-2 text-base font-normal', extra: 'text-base' },
 } as const
 
+const CLASES_VARIANTE = {
+  segmentado: {
+    lista: 'flex w-full flex-col rounded-xl bg-muted p-1 min-[380px]:flex-row sm:w-fit',
+    tab: 'flex-1 justify-center rounded-lg sm:flex-none',
+    activa: 'bg-white text-primary shadow-sm',
+    inactiva: 'text-[var(--muted-foreground-strong)] hover:text-primary',
+    extra: 'text-[var(--muted-foreground-strong)]',
+  },
+  subrayado: {
+    lista: 'flex w-full gap-6 overflow-x-auto border-b border-border',
+    tab: '-mb-px shrink-0 justify-center whitespace-nowrap border-b-2 !px-0.5 font-semibold',
+    activa: 'border-accent font-bold text-[var(--accent-press)]',
+    inactiva: 'border-transparent text-[var(--muted-foreground-strong)] hover:text-primary',
+    extra: '',
+  },
+  pastilla: {
+    lista: 'flex w-full flex-wrap gap-2',
+    tab: 'shrink-0 justify-center whitespace-nowrap rounded-full border font-semibold',
+    activa: 'border-accent bg-accent text-accent-foreground',
+    inactiva: 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary',
+    extra: '',
+  },
+} as const
+
 // Ids del tab y del panel de un valor (interno: el panel activo vive dentro del componente).
 function idsDeTab(idBase: string, valor: string): { tab: string; panel: string } {
   return { tab: `${idBase}-tab-${valor}`, panel: `${idBase}-panel-${valor}` }
 }
 
-export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, children, className, tamano = 'normal' }: TabsProps<V>) {
+export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, children, className, tamano = 'normal', variante = 'segmentado', clasePanel }: TabsProps<V>) {
   const medidas = CLASES_TAMANO[tamano]
+  const aspecto = CLASES_VARIANTE[variante]
   const idAuto = useId()
   const base = `tabs${idAuto.replaceAll(':', '')}`
   const valores = pestanas.map((p) => p.valor)
@@ -64,7 +99,7 @@ export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, ch
   const activo = idsDeTab(base, valor)
   return (
     <div className={cn('space-y-3', className)}>
-      <div role="tablist" aria-label={etiqueta} className="flex w-full flex-col rounded-xl bg-muted p-1 min-[380px]:flex-row sm:w-fit">
+      <div role="tablist" aria-label={etiqueta} className={aspecto.lista}>
         {pestanas.map((p) => {
           const ids = idsDeTab(base, p.valor)
           const seleccionada = p.valor === valor
@@ -80,19 +115,20 @@ export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, ch
               onClick={() => onCambio(p.valor)}
               onKeyDown={alTecla}
               className={cn(
-                'inline-flex min-w-0 flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-lg transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:flex-none',
+                'inline-flex min-w-0 cursor-pointer items-center gap-1.5 transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40',
                 medidas.tab,
-                seleccionada ? 'bg-white text-primary shadow-sm' : 'text-[var(--muted-foreground-strong)] hover:text-primary',
+                aspecto.tab,
+                seleccionada ? aspecto.activa : aspecto.inactiva,
               )}
             >
               {p.etiqueta}
-              {p.extra !== undefined && <span className={cn('tabular-nums font-bold text-[var(--muted-foreground-strong)]', medidas.extra)}>{p.extra}</span>}
+              {p.extra !== undefined && <span className={cn('tabular-nums font-bold', aspecto.extra, medidas.extra)}>{p.extra}</span>}
             </button>
           )
         })}
       </div>
       {children !== undefined && (
-        <div role="tabpanel" id={activo.panel} aria-labelledby={activo.tab} tabIndex={0} className="focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">
+        <div role="tabpanel" id={activo.panel} aria-labelledby={activo.tab} tabIndex={0} className={cn('focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40', clasePanel)}>
           {children}
         </div>
       )}
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts
index 4fb7811f..8e2e6088 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts
@@ -289,6 +289,46 @@ export function paginaDeFilas(
   return { filas: visibles, pagina: actual, paginas, rango, total }
 }
 
+/**
+ * El filtro de la cola (diseño del 27/09/2026). «Todo» NO es un grupo de
+ * negocio: es la cola entera en el orden del día (grupo y, dentro, hora). Va
+ * separado de `fila.grupo` a propósito (hallazgo de Codex): si fuera un grupo
+ * más, elegir a alguien desde «Todo» haría saltar la vista a su grupo.
+ */
+export type FiltroCola = 'todo' | GrupoDia
+export const FILTRO_TODO = { clave: 'todo', etiqueta: 'Todo', ayuda: 'Toda tu cola, en el orden del día' } as const
+
+type GruposDelDia = readonly { clave: GrupoDia; filas: readonly FilaDiaria[] }[]
+
+/** Las filas que muestra un filtro; «Todo» las concatena en el orden de `GRUPOS_DIA`. */
+export function filasDelFiltro(pestanas: GruposDelDia, filtro: FiltroCola): FilaDiaria[] {
+  return filtro === 'todo'
+    ? pestanas.flatMap((p) => p.filas)
+    : [...(pestanas.find((p) => p.clave === filtro)?.filas ?? [])]
+}
+
+/**
+ * La regla del «siguiente» al guardar (hallazgo de Codex, 27/09/2026): «Ahora»
+ * pasa a la persona que queda en el MISMO lugar de la lista que se miraba —la
+ * que venía detrás—, o a la última si el guardado era el final. Si esa lista se
+ * queda vacía, sigue con la cola entera. Devuelve una persona CONCRETA, no un
+ * índice: un refresco posterior que devuelva al guardado no lo vuelve a poner
+ * en «Ahora».
+ */
+export function siguienteTrasGuardar(
+  pestanas: GruposDelDia,
+  filtro: FiltroCola,
+  guardado: string,
+): { filtro: FiltroCola; lead_id: string | null } {
+  const lista = filasDelFiltro(pestanas, filtro)
+  const indice = lista.findIndex((f) => f.lead_id === guardado)
+  const resto = lista.filter((f) => f.lead_id !== guardado)
+  if (resto.length > 0) return { filtro, lead_id: resto[Math.min(Math.max(indice, 0), resto.length - 1)]?.lead_id ?? null }
+  if (filtro === 'todo') return { filtro, lead_id: null }
+  const todo = filasDelFiltro(pestanas, 'todo').filter((f) => f.lead_id !== guardado)
+  return { filtro: 'todo', lead_id: todo[0]?.lead_id ?? null }
+}
+
 /** Las filas agrupadas y en orden, para pintar un bloque por grupo. */
 export function agruparDiaria(filas: readonly FilaDiaria[]): { grupo: GrupoDia; filas: FilaDiaria[] }[] {
   return GRUPOS_DIA
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx
index 042a5acd..0db1eddc 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx
@@ -5,9 +5,10 @@
 // fases 4–5 del plan (docs/gestion-diaria/GESTION-DIARIA.md).
 // Fase 3 (20/09/2026): el analista abre con «Mi día» — la cola completa, su
 // marcador, sus compromisos y sus descartes — y conserva el registro debajo.
-// Densidad (20/09/2026): el registro del propio analista («¿Qué hice hoy?») se
-// pliega. Es memoria, no trabajo pendiente: releer el log propio no cambia a
-// quién hay que llamar, y abierto duplicaba el largo de la pantalla.
+// Diseño (27/09/2026): el registro del propio analista («¿Qué hice hoy?») vive
+// ahora DENTRO de «Mi día», en su pestaña «Mi actividad», y la navegación entre
+// «Resumen del día» y «Seguimiento completo» sube a su cabecera (misma ruta y
+// `aria-current` de siempre), como ya hacían supervisor y gerencia.
 import { useState, useSyncExternalStore, type JSX, type ReactNode } from 'react'
 import { useAuth } from '@/lib/auth-context'
 import { useAhora } from '@/lib/ahora'
@@ -16,10 +17,9 @@ import { RegistroActividad } from '@/components/gestion-diaria/registro-activida
 import { GestionDiariaAnalista } from '@/screens/gestion-diaria/analista'
 import { GestionDiariaSupervisor } from '@/screens/gestion-diaria/supervisor'
 import { GestionDiariaGerencia } from '@/screens/gestion-diaria/gerencia'
-import { Plegable } from '@/components/gestion-diaria/plegable'
 import { PanelVacio } from '@/components/common/estado-panel'
 import { Input } from '@/components/ui/input'
-import { CalendarCheck2 } from 'lucide-react'
+import { CalendarCheck2, ChevronRight } from 'lucide-react'
 import { ColaSeguimiento } from '@/components/app/cola-seguimiento'
 import { hashDe, leerHash } from '@/lib/router'
 
@@ -35,18 +35,26 @@ export function GestionDiaria(): JSX.Element {
     return <PanelVacio icono={CalendarCheck2} titulo="Gestión Diaria no está disponible para tu rol" detalle="Este módulo es para analistas, supervisores y gerencia." />
   }
   const cola = leerHash().detalleGestion?.tipo === 'cola'
-  const cabeceraIntegrada = (yo.rol === 'supervisor' || (yo.rol === 'gerencia' && !yo.demo)) && !cola
+  const cabeceraIntegrada = (yo.rol === 'vendedor' || yo.rol === 'supervisor' || (yo.rol === 'gerencia' && !yo.demo)) && !cola
   const enlace = 'inline-flex min-h-11 items-center rounded-lg border px-4 py-2 text-base font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
   const accesoCola = <a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} aria-current={cola ? 'page' : undefined} className={`${enlace} ${cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Seguimiento completo</a>
+  const secciones = <nav aria-label="Secciones de Gestión Diaria" className="flex flex-wrap gap-3">
+    <a href={hashDe('gestion-diaria')} aria-current={!cola ? 'page' : undefined} className={`${enlace} ${!cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Resumen del día</a>
+    {accesoCola}
+  </nav>
+  // El analista lleva a su cabecera un solo botón, como el «Mi Hoy completo ›»
+  // del diseño (27/09/2026): la cabecera no puede pesar más que la pregunta. La
+  // vuelta al resumen sigue en la barra de secciones de la cola, con su
+  // `aria-current`. Supervisor y gerencia conservan su acceso, como hasta ahora.
+  const integrada = yo.rol === 'vendedor'
+    ? <nav aria-label="Secciones de Gestión Diaria"><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} className="inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Seguimiento completo<ChevronRight aria-hidden className="size-4" /></a></nav>
+    : <nav aria-label="Secciones de Gestión Diaria">{accesoCola}</nav>
   return <div key={`${yo.id}:${yo.rol}:${yo.demo}`} className="mx-auto w-full max-w-[1640px] space-y-5">
-    {!cabeceraIntegrada && <nav aria-label="Secciones de Gestión Diaria" className="flex flex-wrap gap-3">
-      <a href={hashDe('gestion-diaria')} aria-current={!cola ? 'page' : undefined} className={`${enlace} ${!cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Resumen del día</a>
-      {accesoCola}
-    </nav>}
+    {!cabeceraIntegrada && secciones}
     {cola ? <>
       <p className="text-base text-[var(--muted-foreground-strong)]">Pendientes actuales de tu ámbito. La fecha del resumen no cambia esta cola.</p>
       <ColaSeguimiento />
-    </> : <ResumenGestionDiaria accesoSeguimiento={cabeceraIntegrada ? <nav aria-label="Secciones de Gestión Diaria">{accesoCola}</nav> : undefined} />}
+    </> : <ResumenGestionDiaria accesoSeguimiento={cabeceraIntegrada ? integrada : undefined} />}
   </div>
 }
 
@@ -66,23 +74,15 @@ function ResumenGestionDiaria({ accesoSeguimiento }: { accesoSeguimiento?: React
   const { yo } = useAuth()
   const hoy = fechaLima(useAhora())
   const [dia, setDia] = useState(hoy)
-  const [registroAbierto, setRegistroAbierto] = useState(false)
   const diaValido = /^\d{4}-\d{2}-\d{2}$/.test(dia) && dia <= hoy ? dia : hoy
 
   if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />
 
   switch (yo.rol) {
     case 'vendedor':
-      // Fase 3: el analista entra a «Mi día» (cola, marcador, compromisos y
-      // descartes). Su registro crudo sigue debajo, plegado.
-      return (
-        <div className="mx-auto w-full max-w-[1440px] space-y-6">
-          <GestionDiariaAnalista />
-          <Plegable titulo="¿Qué hice hoy?" resumen="tu registro del día" abierto={registroAbierto} onAbrir={setRegistroAbierto}>
-            <RegistroActividad dia={hoy} analistaIds={[yo.id]} mostrarAnalista={false} permitirExportar={false} />
-          </Plegable>
-        </div>
-      )
+      // «Mi día»: cola, cifras, compromisos, descartes y su registro del día
+      // (pestaña «Mi actividad»), todo dentro de la misma pantalla.
+      return <GestionDiariaAnalista accesoSeguimiento={accesoSeguimiento} />
     case 'supervisor':
       return <GestionDiariaSupervisor accesoSeguimiento={accesoSeguimiento} />
     case 'gerencia':
```

## PROTOCOLO DEL PROYECTO (.ai/REVIEW_PROTOCOL.md, íntegro)

# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.


## PROTOCOLO GLOBAL (~/.config/ai-collaboration/REVIEW_PROTOCOL.md, íntegro)

# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
