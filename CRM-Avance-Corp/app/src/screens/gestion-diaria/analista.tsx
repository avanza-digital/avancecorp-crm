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
// DENSIDAD (20/09/2026, queja de los analistas: «demasiada información, muchas
// letras pequeñas»). Lo metodológico, el seguimiento y los descartes viven en
// desplegables con su conteo a la vista. Piso tipográfico 16 px en el cuerpo de
// la cola. Nunca se pliega lo que cambia la decisión de marcar ni un aviso de
// fallo (`role="alert"`).
//
// HORIZONTAL (20/09/2026, Miguel: «esa orientación vertical la odio»). La
// pantalla son DOS paneles hermanos, no una pila:
//   · «Ahora» (izquierda, fijo): el ÚNICO lead que toca, con su nombre grande,
//     el tiempo que le queda EN PALABRAS y la acción primaria — «Llamar».
//     Se queda pegado (`sticky`) mientras la cola se recorre.
//   · «Cola de hoy» (derecha): los cuatro grupos en PESTAÑAS, no apilados; una
//     lista visible a la vez. Cada fila lleva DOS datos —nombre y tiempo— y
//     NINGÚN botón: la fila ES el selector, y quien actúa es el panel «Ahora».
// Un solo rojo: el rojo queda reservado a lo vencido («Se pasó hace 45 min»);
// la severidad se DICE con esas mismas palabras, nunca solo con el color.
// Integración F4 (21/09): conserva el layout local y los arreglos publicados
// de caché parcial, tarea autoritativa, cuatro pestañas, paginación y carreras.
import { useEffect, useId, useMemo, useRef, useState, type JSX, type Ref } from 'react'
import { CalendarClock, ChevronRight, ClipboardList, MoreHorizontal, Phone, RefreshCw, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, type Etapa, type Lead, type Tarea } from '@/lib/tipos'
import { tareaQueCierra } from '@/lib/contacto-tarea'
import { presentarCitas } from '@/lib/terminologia'
import {
  ETIQUETA_NIVEL, barrasPorHora, cuandoLimaDe, detalleDeFila, filasDiariasDemo,
  horaLimaDe, llamadasFueraDeFranja, ordenarColaDiaria, paginaDeFilas, pestanasDiarias, resumenMarcador, textoTasa, tiempoDeFila,
  type Descartado, type DiaAnalista, type FilaDiaria, type GrupoDia,
} from '@/lib/gestion-diaria-analista'
import { useDiaAnalista } from '@/data/gestion-diaria-queries'
import { useColaSlaPagina } from '@/data/sla-operacion-queries'
import { AccionesContacto } from '@/components/app/contacto'
import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Plegable } from '@/components/gestion-diaria/plegable'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
import { ColaDeHoy, FILAS_POR_PAGINA } from '@/components/gestion-diaria/cola-de-hoy'

const LIMITE_COLA = 100
// Verde NO (decisión #3 de Miguel): «Bien» va en navy sobre fondo tenue. Y los
// tokens de TEXTO, no los saturados: el chip `soft` pinta el color puro sobre un
// tinte al 12 %, donde `--warning` da ~3:1 y `--destructive` ~4:1 (index.css).
const COLOR_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  bien: 'var(--primary)',
  atencion: 'var(--warning-text)',
  bajo: 'var(--warning-text)',
}
const TONO_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  bien: 'text-primary',
  atencion: 'text-[var(--warning-text)]',
  bajo: 'text-[var(--warning-text)]',
}
export function GestionDiariaAnalista(): JSX.Element {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { ambito, tareasDe, asegurarLead, obtenerTareaParaRevision } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()

  // TODO el estado vive AQUÍ, por encima de la cascada de carga/error: el hook
  // del día es fail-closed (un refetch fallido devuelve `null`) y, si la
  // pestaña o la persona elegida colgaran del subárbol, un parpadeo de red le
  // borraría al analista dónde estaba.
  const [panel, setPanel] = useState<{ lead: Lead; tarea: Tarea | null } | null>(null)
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  const [elegido, setElegido] = useState<string | null>(null)
  const [pestanaPedida, setPestanaPedida] = useState<GrupoDia | null>(null)
  const [pagina, setPagina] = useState(0)
  // Los leads cuyo resultado se acaba de guardar: siguen en la cola hasta que el
  // servidor conteste, y sin esto «Ahora» volvería a proponer al que ya cerraste.
  // Es un CONJUNTO y no un solo id: registrar dos seguidos antes de que vuelva
  // el primero hacía que el `finally` de uno destapara al otro.
  const [cerrados, setCerrados] = useState<readonly string[]>([])
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>({})
  const abrir = (clave: string) => (v: boolean) => setAbiertos((a) => ({ ...a, [clave]: v }))
  const nombreAhora = useRef<HTMLButtonElement>(null)
  const tituloDescartes = useRef<HTMLElement>(null)
  const tituloActividad = useRef<HTMLElement>(null)
  const panelAhora = useRef<HTMLElement>(null)
  const encabezado = useRef<HTMLHeadingElement>(null)
  // Leads que ya se pidieron al servidor: `asegurarLead` no está deduplicado y
  // la fila elegida se recalcula con el reloj de cada minuto.
  const pedidos = useRef(new Set<string>())
  const [cargandoLead, setCargandoLead] = useState<string | null>(null)
  const [abriendoPanel, setAbriendoPanel] = useState(false)

  const dia = useDiaAnalista(null, null)
  // La cola del día: la misma fuente que «Seguimiento comercial», sin filtros.
  const cola = useColaSlaPagina({ senal: 'todas', etapa: null, analista_id: null }, null, LIMITE_COLA, !yo?.demo)
  const paginaCola = cola.error ? undefined : cola.data
  // La cola y el día son DOS consultas: mientras la cola no ha llegado, decir
  // «no tienes nada pendiente» sería mentir (solo estarían los sin conversación).
  const colaCargando = !yo?.demo && cola.error == null && paginaCola === undefined
  const colaCaida = !yo?.demo && cola.error != null

  const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
  const filas = useMemo<FilaDiaria[]>(() => {
    if (dia.dia === null) return []
    const todas = yo?.demo
      ? filasDiariasDemo(dia.dia.cartera, ahora, dia.dia.dia)
      : ordenarColaDiaria(paginaCola?.items ?? [], dia.dia.cartera)
    return cerrados.length === 0 ? todas : todas.filter((f) => !cerrados.includes(f.lead_id))
  }, [ahora, cerrados, dia.dia, paginaCola?.items, yo?.demo])

  const pestanas = useMemo(() => pestanasDiarias(filas), [filas])
  // El elegido se busca en TODAS las filas, no solo en la pestaña abierta: un
  // refetch puede moverlo de grupo (de «Hoy» a «Vencidas» al dar la hora) y la
  // pantalla no puede perderlo de vista ni dejar un id fantasma guardado.
  const elegida = elegido === null ? null : filas.find((f) => f.lead_id === elegido) ?? null
  // Quién manda sobre la pestaña, en orden: el lead elegido (la pestaña LO
  // SIGUE), luego la que pidió el analista —AUNQUE ESTÉ VACÍA, porque pulsar un
  // grupo y que no se abra es peor que verlo vacío: su conteo ya está a la
  // vista—, y solo si nunca pidió ninguna, la primera con gente. Al registrar
  // un resultado se borra la petición, así que la cola sigue sola al siguiente
  // grupo en vez de dejarte mirando el que acabas de vaciar.
  const activa: GrupoDia = elegida !== null
    ? elegida.grupo
    : pestanaPedida ?? pestanas.find((p) => p.total > 0)?.clave ?? 'primera_atencion'

  const delGrupo = pestanas.find((p) => p.clave === activa)?.filas ?? []
  // La página se deriva del elegido: si lo eligió, se ve; si no, la que pidió.
  const indiceElegida = elegida === null ? -1 : delGrupo.findIndex((f) => f.lead_id === elegida.lead_id)
  const paginaPedida = indiceElegida >= 0 ? Math.floor(indiceElegida / FILAS_POR_PAGINA) : pagina
  const vista = paginaDeFilas(delGrupo, paginaPedida, FILAS_POR_PAGINA)
  // Sin elección explícita, «Ahora» es el primero de la página: el orden del
  // servidor ya dice quién urge más.
  const fila = elegida ?? vista.filas[0] ?? null
  const posicion = fila === null ? 0 : delGrupo.findIndex((f) => f.lead_id === fila.lead_id) + 1

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
    setElegido(f.lead_id)
    requestAnimationFrame(() => {
      panelAhora.current?.scrollIntoView?.({ block: 'nearest' })
      nombreAhora.current?.focus()
    })
  }
  function cambiarPestana(grupo: GrupoDia) {
    setPestanaPedida(grupo)
    setPagina(0)
    setElegido(null)
  }
  /** Se guarda ya acotada: si la lista encoge y vuelve a crecer, no salta sola. */
  function irAPagina(p: number) {
    setPagina(Math.min(Math.max(p, 0), vista.paginas - 1))
  }
  async function abrirPanel() {
    if (fila === null || abriendoPanel) return
    const suyo = leadsPorId.get(fila.lead_id)
    if (suyo === undefined) { void abrirLead(fila.lead_id); return }
    // `tarea_id` viene de la cola del SERVIDOR y es autoritativa: ese id viaja
    // de vuelta para cerrar la tarea. Las tareas del store son una colección
    // PARCIAL igual que los leads, así que no encontrarla ahí no significa que
    // no exista — se pide por id. Caer al cálculo de siempre cerraría otra
    // tarea telefónica, o ninguna (Codex, 20/09).
    const pendientes = tareasDe(suyo.id)
    if (fila.tarea_id !== null) {
      const local = pendientes.find((x) => x.id === fila.tarea_id)
      if (local !== undefined) { setPanel({ lead: suyo, tarea: local }); return }
      setAbriendoPanel(true)
      try {
        const traida = await obtenerTareaParaRevision(suyo.id, fila.tarea_id)
        // Si el servidor tampoco la da, se abre SIN tarea: mejor no cerrar
        // ninguna que cerrar la que no era.
        setPanel({ lead: suyo, tarea: traida })
      } catch {
        setPanel({ lead: suyo, tarea: null })
      } finally {
        setAbriendoPanel(false)
      }
      return
    }
    setPanel({ lead: suyo, tarea: tareaQueCierra(pendientes, 'tel', yo?.id, ahora) ?? null })
  }
  /** Al guardar, «Ahora» pasa al siguiente y el foco vuelve al encabezado. */
  async function alGuardar(leadId: string) {
    setCerrados((c) => (c.includes(leadId) ? c : [...c, leadId]))
    setElegido(null)
    // Registrar es «dame el siguiente»: se suelta la pestaña pedida para que la
    // cola avance sola al grupo que todavía tenga gente.
    setPestanaPedida(null)
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

  /** El marcador de la cabecera abre su propio detalle y lleva el foco allí. */
  function verActividad() {
    setAbiertos((a) => ({ ...a, detalle: true }))
    requestAnimationFrame(() => {
      tituloActividad.current?.focus()
      tituloActividad.current?.scrollIntoView?.({ block: 'nearest' })
    })
  }

  const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
  const filaActiva = colaCargando ? null : fila

  return (
    <div className="mx-auto w-full max-w-[1440px] space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-x-6 gap-y-4">
        <div className="min-w-0 flex-1 basis-80">
          <h2 ref={encabezado} tabIndex={-1} className="text-2xl font-bold leading-tight tracking-tight text-primary sm:text-[28px]">¿A quién llamo ahora?</h2>
          <p className="mt-2 text-base text-[var(--muted-foreground-strong)]">
            {corte ? `Corte ${corte} (Lima)` : 'Sin corte confirmado'} · actualización cada minuto.
          </p>
        </div>
        <div className="flex w-full min-w-0 max-w-full items-center gap-3 sm:w-auto">
          {/* El marcador es CONTEXTO, no trabajo pendiente: una línea en la
              cabecera y el detalle a un clic. Antes era una tarjeta entera
              debajo de la cola, que es donde el analista tiene que mirar. */}
          {dia.dia !== null && (
            <button type="button" onClick={verActividad} aria-expanded={abiertos['detalle'] ?? false} aria-controls={`${id}-actividad`}
              className="flex min-h-11 min-w-0 max-w-full flex-1 items-center gap-3 rounded-xl border border-border bg-card px-4 py-3 text-left transition-colors hover:border-accent/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:flex-none">
              <span className="min-w-0 space-y-1">
                <span className="block text-base text-[var(--muted-foreground-strong)]">Mi actividad</span>
                <span className="block text-base font-semibold tabular-nums text-primary">{resumenMarcador(dia.dia)}</span>
              </span>
              {dia.dia.marcador.nivel !== null && (
                <Badge className="shrink-0 text-base" color={COLOR_NIVEL[dia.dia.marcador.nivel]} dot>{ETIQUETA_NIVEL[dia.dia.marcador.nivel]}</Badge>
              )}
              <ChevronRight aria-hidden className="size-5 shrink-0 text-[var(--muted-foreground-strong)]" />
            </button>
          )}
          <Button variant="outline" size="sm" className="h-11 w-11 shrink-0 text-base sm:w-auto" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
            onClick={() => { if (dia.enVuelo) return; void dia.recargar(); if (!yo?.demo) void cola.refetch() }}>
            <RefreshCw aria-hidden className={dia.enVuelo ? 'motion-safe:animate-spin' : ''} /><span className="sr-only sm:not-sr-only">Actualizar</span>
          </Button>
        </div>
      </header>

      {dia.error != null && dia.dia === null ? (
        <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
      ) : dia.dia === null && dia.cargando ? (
        <PanelCargando filas={6} />
      ) : dia.dia === null ? (
        <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
      ) : (
        <>
          {colaCaida && (
            <p role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3 text-base font-semibold text-[var(--destructive-text)]">
              No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
            </p>
          )}
          {dia.dia.cartera_truncada && (
            <p role="status" className="text-base font-semibold text-[var(--muted-foreground-strong)]">
              Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
            </p>
          )}

          {/* DOS PANELES HERMANOS, no una pila: el que actúa y el que elige. */}
          <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
            <PanelAhora fila={filaActiva} lead={filaActiva ? leadsPorId.get(filaActiva.lead_id) ?? null : null}
              sinConversacionDias={dia.dia.sin_conversacion_dias} ahora={ahora} cargando={colaCargando} colaCaida={colaCaida}
              seccionRef={panelAhora} nombreRef={nombreAhora}
              posicion={posicion} total={delGrupo.length}
              cargandoLead={filaActiva !== null && cargandoLead === filaActiva.lead_id} abriendoPanel={abriendoPanel}
              onRegistrar={() => { if (filaActiva) void abrirPanel() }}
              onAbrirFicha={() => { if (filaActiva) void abrirLead(filaActiva.lead_id) }} />

            <ColaDeHoy
              idBase={id} pestanas={pestanas} activa={activa} onPestana={cambiarPestana}
              pagina={vista.pagina} onPagina={irAPagina}
              elegido={filaActiva?.lead_id ?? null} onElegir={elegir}
              ahora={ahora} cargando={colaCargando} hayMas={paginaCola?.hay_mas === true} colaCaida={colaCaida}
            />
          </div>

          <Actividad id={`${id}-actividad`} dia={dia.dia} abierto={abiertos['detalle'] ?? false} onAbrir={abrir('detalle')} summaryRef={tituloActividad} />
          <Compromisos dia={dia.dia} abierto={abiertos['compromisos'] ?? false} onAbrir={abrir('compromisos')}
            onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
          <Descartados dia={dia.dia} deshaciendo={deshaciendo} onDeshacer={(d) => { void deshacer(d) }}
            abierto={abiertos['descartados'] ?? false} onAbrir={abrir('descartados')} summaryRef={tituloDescartes}
            onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
          {yo?.demo && <p className="text-base text-muted-foreground">Datos de ejemplo: en la sesión real tu día sale del servidor.</p>}
        </>
      )}

      {panel !== null && (
        <RegistrarResultado lead={panel.lead} tarea={panel.tarea} onClose={() => setPanel(null)}
          onGuardado={() => void alGuardar(panel.lead.id)} />
      )}
    </div>
  )
}

/**
 * El panel «Ahora»: UN lead, UNA acción primaria. Se queda pegado arriba
 * mientras la cola se recorre, para que el analista nunca pierda de vista a
 * quién está llamando. Lo secundario —WhatsApp aparte, que trae su propio
 * diálogo de resultado— vive detrás de «···» (ley de Hick).
 */
function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaida, onRegistrar, onAbrirFicha, seccionRef, nombreRef, cargandoLead, abriendoPanel, posicion, total }: {
  fila: FilaDiaria | null
  lead: Lead | null
  sinConversacionDias: number
  ahora: number
  cargando: boolean
  colaCaida: boolean
  cargandoLead: boolean
  abriendoPanel: boolean
  posicion: number
  total: number
  onRegistrar: () => void
  onAbrirFicha: () => void
  seccionRef: Ref<HTMLElement>
  nombreRef: Ref<HTMLButtonElement>
}): JSX.Element {
  const id = useId()
  const etapa = fila === null ? null : ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
  const tiempo = fila === null ? null : tiempoDeFila(fila, ahora)
  return (
    <section ref={seccionRef} aria-labelledby={`${id}-ahora`}
      className="w-full rounded-xl border border-border bg-card shadow-[var(--shadow-card)] lg:sticky lg:top-4 lg:w-[36%] lg:min-w-[320px] lg:max-w-[420px] lg:shrink-0">
      <div className="flex items-center gap-3 rounded-t-xl bg-primary px-6 py-4 text-primary-foreground">
        <Phone aria-hidden className="size-5" />
        <h3 id={`${id}-ahora`} className="text-xl font-semibold">Ahora</h3>
        {fila !== null && total > 0 && <span className="ml-auto text-base tabular-nums text-primary-foreground/80"><span className="sr-only">Contacto </span>{posicion} de {total}<span className="sr-only"> en este grupo</span></span>}
      </div>
      {fila === null ? (
        <p className="p-6 text-base leading-relaxed text-[var(--muted-foreground-strong)]">
          {cargando ? 'Buscando a quién llamar…'
            : colaCaida ? 'No se pudo leer tu cola: no sabemos a quién te toca llamar. Pulsa «Actualizar».'
              : 'Nada pendiente ahora. Cuando entre un lead nuevo aparecerá aquí.'}
        </p>
      ) : (
        <>
          <div className="space-y-4 p-4 sm:p-6">
            <div className="min-w-0 space-y-1">
              <button ref={nombreRef} type="button" onClick={onAbrirFicha}
                aria-label={`Abrir la ficha de ${fila.nombre_completo}`}
                className="inline-flex min-h-11 items-start rounded-md text-left text-xl font-bold leading-7 tracking-tight text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:text-2xl sm:leading-8">
                {fila.nombre_completo}
              </button>
              <p className="text-base text-[var(--muted-foreground-strong)]">{etapa}</p>
            </div>
            <div className="space-y-3 rounded-lg bg-muted/60 p-4">
              {tiempo !== null && (
                <Badge className="self-start text-base" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
              )}
              <p className="text-base leading-relaxed text-[var(--muted-foreground-strong)]">
                {fila.senal === null ? 'Historial no cargado. Ábrelo en la ficha antes de llamar.' : detalleDeFila(fila, sinConversacionDias)}
              </p>
            </div>
          </div>
          <div className="space-y-3 rounded-b-xl border-t border-border bg-muted/30 p-4 sm:px-6">
            {lead !== null && <p className="text-xl font-bold tabular-nums text-primary">{lead.telefono}</p>}
            <div className="flex items-start gap-2">
              {lead !== null ? (
                // `key={lead.id}`: UNA instancia por lead. Antes las acciones
                // vivían dentro de cada fila y se desmontaban con ella; aquí hay
                // una sola caja que cambia de lead, y si el refresco de cada
                // minuto cambiaba el lead con el diálogo de resultado ABIERTO, el
                // resultado se escribía sobre el lead equivocado. La clave fuerza
                // el remontaje: el contacto a medias se cae a la vista, que es
                // reparable — atribuirlo a otra persona, no (hallazgo de Codex).
                <div className="min-w-0 flex-1 [&>div]:flex-col [&>div]:items-stretch [&>div>a]:justify-center [&>div>button]:justify-center" data-accion-panel="si">
                  <AccionesContacto key={lead.id} lead={lead} destacada grande onRegistrarLlamada={onRegistrar} />
                </div>
              ) : (
                <p role="status" className="min-w-0 flex-1 text-base text-[var(--muted-foreground-strong)]">
                  {cargandoLead ? 'Buscando su número…' : 'No se pudo traer su número. Abre la ficha para llamar.'}
                </p>
              )}
              <DropdownMenu
                trigger={
                  <button type="button" data-accion-panel="si"
                    aria-label={`Más acciones para ${fila.nombre_completo}: registrar resultado y ver la ficha`}
                    className="grid size-12 shrink-0 cursor-pointer place-items-center rounded-xl border border-border-strong bg-card text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
                    <MoreHorizontal aria-hidden className="size-5" />
                  </button>
                }>
                <DropdownItem className="min-h-11 text-base" disabled={abriendoPanel} onSelect={() => { if (!abriendoPanel) onRegistrar() }}>Registrar resultado</DropdownItem>
                <DropdownItem className="min-h-11 text-base" onSelect={onAbrirFicha}>Ver la ficha completa</DropdownItem>
              </DropdownMenu>
            </div>
          </div>
        </>
      )}
    </section>
  )
}

/** Una métrica del marcador: etiqueta arriba, número grande, apoyo debajo. */
function Metrica({ etiqueta, valor, valorAccesible, apoyo, tono }: {
  etiqueta: string
  valor: string
  /** Qué debe OÍR un lector de pantalla cuando el valor es un símbolo mudo. */
  valorAccesible?: string | undefined
  apoyo?: string | undefined
  tono?: string | undefined
}): JSX.Element {
  return (
    <li className="min-w-0">
      <p className="text-base font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</p>
      <p className={`text-2xl font-extrabold leading-tight tabular-nums ${tono ?? 'text-foreground'}`}>
        {valorAccesible !== undefined ? (
          <>
            <span aria-hidden="true">{valor}</span>
            <span className="sr-only">{valorAccesible}</span>
          </>
        ) : valor}
      </p>
      {apoyo !== undefined && <p className="mt-0.5 text-base text-[var(--muted-foreground-strong)]">{apoyo}</p>}
    </li>
  )
}

/**
 * «Mi actividad de hoy»: el marcador completo, plegado. Su línea de titulares
 * vive arriba, en la cabecera (`resumenMarcador`), así que aquí no se esconde
 * ningún dato que el analista necesite de un vistazo — solo el detalle: cómo se
 * cuentan las llamadas, primera y última, y el reparto por hora (decisión #8).
 * La decisión #7 se respeta en los dos sitios: el % SIEMPRE con su conteo.
 */
function Actividad({ id: idBloque, dia, abierto, onAbrir, summaryRef }: {
  id: string
  dia: DiaAnalista
  abierto: boolean
  onAbrir: (v: boolean) => void
  summaryRef: Ref<HTMLElement>
}): JSX.Element {
  const id = useId()
  const m = dia.marcador
  const barras = barrasPorHora(m)
  const fuera = llamadasFueraDeFranja(m)
  return (
    <Plegable id={idBloque} titulo="Mi actividad de hoy" resumen="cómo se cuenta y las llamadas por hora" abierto={abierto} onAbrir={onAbrir} summaryRef={summaryRef}>
      <div className="space-y-4">
        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
        <ul role="list" aria-label="Marcador de hoy" className="flex flex-wrap items-start gap-x-10 gap-y-4">
          <Metrica etiqueta="Llamadas" valor={String(m.llamadas)} apoyo={`${m.contestadas} contestadas`} tono="text-primary" />
          <Metrica etiqueta="Tasa de contacto" valor={textoTasa(m)}
            // El «—» de la tasa sin llamadas útiles no lo pronuncia un lector de
            // pantalla: se dice «sin dato» para que no suene a cero.
            {...(m.tasa_contacto_pct === null ? { valorAccesible: 'sin dato' } : {})}
            apoyo={m.nivel === null ? `Se juzga desde ${dia.umbrales.minimo_llamadas_utiles} llamadas útiles` : ETIQUETA_NIVEL[m.nivel]}
            tono={m.nivel === null ? 'text-foreground' : TONO_NIVEL[m.nivel]} />
          <Metrica etiqueta={presentarCitas('Citas agendadas')} valor={String(m.citas_agendadas)} />
        </ul>
        <p className="text-base text-[var(--muted-foreground-strong)]">
          Tocaste {m.leads_tocados} {m.leads_tocados === 1 ? 'lead' : 'leads'}. Llamadas = marcadas + no contestadas.
          No incluye WhatsApp ni citas. Un número errado no entra en la tasa.
          {m.primera_llamada_en !== null && ` Primera ${horaLimaDe(m.primera_llamada_en)}, última ${horaLimaDe(m.ultima_llamada_en)} (Lima).`}
        </p>
        {m.llamadas > 0 ? (
          <div>
            <h4 id={`${id}-horas`} className="text-base font-semibold text-[var(--muted-foreground-strong)]">Llamadas por hora (08–20, Lima)</h4>
            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
            <ul role="list" className="mt-2 flex items-end gap-1.5" aria-labelledby={`${id}-horas`}>
              {barras.map((b) => (
                <li key={b.hora} className="flex min-w-0 flex-1 flex-col items-center gap-1">
                  <span className="w-full rounded-t bg-primary/80" style={{ height: `${Math.round((b.llamadas / b.maximo) * 56) + 2}px` }}
                    aria-hidden />
                  <span className="sr-only">
                    {b.hora}:00 — {b.llamadas} {b.llamadas === 1 ? 'llamada' : 'llamadas'}, {b.contestadas} {b.contestadas === 1 ? 'contestada' : 'contestadas'}
                  </span>
                  <span aria-hidden className="text-base tabular-nums text-[var(--muted-foreground-strong)]">{b.hora}</span>
                </li>
              ))}
            </ul>
            {fuera > 0 && <p className="mt-2 text-base text-[var(--muted-foreground-strong)]">{fuera} fuera de la franja 08–20.</p>}
          </div>
        ) : (
          <p className="text-base text-[var(--muted-foreground-strong)]">Todavía no has marcado hoy.</p>
        )}
      </div>
    </Plegable>
  )
}

/**
 * Compromisos: SOLO de mañana en adelante — el servidor los devuelve desde
 * mañana 00:00 Lima (`gestion_diaria_analista_fn`, `v_manana`), y lo de hoy y
 * lo vencido ya está en la cola de arriba. Por eso se puede plegar sin
 * esconder nada accionable hoy; el conteo queda a la vista en el resumen.
 */
function Compromisos({ dia, abierto, onAbrir, onAbrirFicha }: {
  dia: DiaAnalista
  abierto: boolean
  onAbrir: (v: boolean) => void
  onAbrirFicha: (leadId: string) => void
}): JSX.Element {
  return (
    <Plegable titulo="Mi seguimiento" abierto={abierto} onAbrir={onAbrir}
      resumen={`${dia.compromisos_total} ${dia.compromisos_total === 1 ? 'compromiso' : 'compromisos'} desde mañana`}>
      {dia.compromisos.length === 0 ? (
        <PanelVacio icono={CalendarClock} titulo="Sin compromisos a partir de mañana" detalle="Lo de hoy y lo vencido ya está en tu cola." />
      ) : (
        <>
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ol role="list" aria-label="Mis compromisos" className="divide-y divide-border">
            {dia.compromisos.map((c) => (
              <li key={c.tarea_id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0 last:pb-0">
                <div className="min-w-0">
                  <button type="button" onClick={() => onAbrirFicha(c.lead_id)}
                    className="inline-flex min-h-9 items-center rounded-md text-base font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
                    {c.lead_nombre}
                  </button>
                  <p className="text-base text-[var(--muted-foreground-strong)]">
                    {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
                    {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
                  </p>
                </div>
                <span className="text-base font-semibold tabular-nums text-foreground">{cuandoLimaDe(c.vence_en)}</span>
              </li>
            ))}
          </ol>
          {dia.compromisos_total > dia.compromisos.length && (
            <p className="mt-3 text-base text-[var(--muted-foreground-strong)]">
              Se muestran los {dia.compromisos.length} más próximos de {dia.compromisos_total}. El resto está en Agenda.
            </p>
          )}
        </>
      )}
    </Plegable>
  )
}

function Descartados({ dia, deshaciendo, onDeshacer, onAbrirFicha, abierto, onAbrir, summaryRef }: {
  dia: DiaAnalista
  deshaciendo: string | null
  onDeshacer: (d: Descartado) => void
  onAbrirFicha: (leadId: string) => void
  abierto: boolean
  onAbrir: (v: boolean) => void
  summaryRef: Ref<HTMLElement>
}): JSX.Element | null {
  if (dia.descartados.length === 0) return null
  return (
    <Plegable titulo="Descartados hoy" resumen={`${dia.descartados.length} · se pueden deshacer 24 h`}
      abierto={abierto} onAbrir={onAbrir} summaryRef={summaryRef}>
      <p className="text-base text-[var(--muted-foreground-strong)]">
        Están en el Centro de rescate con su motivo. Puedes deshacer el descarte durante 24 horas; el lead vuelve a tu cartera con un ciclo nuevo.
      </p>
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ol role="list" aria-label="Descartados hoy" className="mt-3 divide-y divide-border">
        {dia.descartados.map((d) => (
          <li key={d.actividad_id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0 last:pb-0">
            <div className="min-w-0">
              <button type="button" onClick={() => onAbrirFicha(d.lead_id)}
                className="inline-flex min-h-9 items-center rounded-md text-base font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
                {d.lead_nombre}
              </button>
              <p className="text-base text-[var(--muted-foreground-strong)]">
                {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
                {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
              </p>
            </div>
            {d.puede_deshacer ? (
              // `aria-disabled` y no `disabled`: deshabilitar el botón enfocado
              // manda el foco al body (regla de la casa, boton-guardar.tsx).
              <Button variant="outline" size="sm" className="h-11 text-base" aria-disabled={deshaciendo !== null}
                aria-label={`Deshacer el descarte de ${d.lead_nombre}`}
                onClick={() => { if (deshaciendo === null) onDeshacer(d) }}>
                <RotateCcw aria-hidden /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
              </Button>
            ) : (
              <span className="text-base text-[var(--muted-foreground-strong)]">Sin deshacer</span>
            )}
          </li>
        ))}
      </ol>
    </Plegable>
  )
}
