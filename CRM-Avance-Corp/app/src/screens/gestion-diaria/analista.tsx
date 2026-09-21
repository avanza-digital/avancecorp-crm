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
// desplegables con su conteo a la vista. Piso tipográfico 14 px en el cuerpo de
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
import { useId, useMemo, useRef, useState, type JSX, type Ref } from 'react'
import { CalendarClock, ClipboardList, MoreHorizontal, PhoneCall, RefreshCw, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, type Etapa, type Lead, type Tarea } from '@/lib/tipos'
import { tareaQueCierra } from '@/lib/contacto-tarea'
import { presentarCitas } from '@/lib/terminologia'
import {
  ETIQUETA_NIVEL, GRUPOS_DIA, agruparDiaria, barrasPorHora, cuandoLimaDe, detalleDeFila, filasDiariasDemo,
  horaLimaDe, llamadasFueraDeFranja, ordenarColaDiaria, resumenMarcador, textoTasa, tiempoDeFila,
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
import { Tabs } from '@/components/ui/tabs'

const LIMITE_COLA = 100
// Verde NO (decisión #3 de Miguel): «Bien» va en navy sobre fondo tenue. Y los
// tokens de TEXTO, no los saturados: el chip `soft` pinta el color puro sobre un
// tinte al 12 %, donde `--warning` da ~3:1 y `--destructive` ~4:1 (index.css).
const COLOR_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  bien: 'var(--primary)',
  atencion: 'var(--warning-text)',
  bajo: 'var(--destructive-text)',
}
const TONO_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  bien: 'text-primary',
  atencion: 'text-[var(--warning-text)]',
  bajo: 'text-[var(--destructive-text)]',
}
/**
 * «Llamar» a tamaño de panel. `AccionesContacto` es el ÚNICO camino correcto de
 * llamar y de escribir por WhatsApp —lleva la detección de aparato y el diálogo
 * que pregunta el resultado AL VOLVER—, así que no se reescribe aquí: se le
 * suben las medidas desde fuera, igual que ya hace su propio `destacada`.
 * `destacada` no sirve en este panel porque baja a 36 px en `sm`, y aquí la
 * acción primaria tiene que seguir siendo grande en el escritorio.
 */
const ACCIONES_PANEL = [
  '[&>div]:w-full [&>div]:gap-2',
  '[&_a]:!h-12 [&_button]:!h-12 [&_a]:!rounded-xl [&_button]:!rounded-xl',
  '[&_a]:!px-4 [&_button]:!px-4 [&_a]:!text-base [&_button]:!text-base [&_svg]:!size-5',
  '[&>div>*:first-child]:!flex-1 [&>div>*:first-child]:!justify-center',
  '[&>div>*:first-child]:!border-accent [&>div>*:first-child]:!bg-accent [&>div>*:first-child]:!text-white',
].join(' ')

export function GestionDiariaAnalista(): JSX.Element {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { ambito, tareasDe } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()
  const [panel, setPanel] = useState<{ lead: Lead; tarea: Tarea | null } | null>(null)
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  // El estado de los plegables vive AQUÍ, fuera de los subárboles que el
  // refresco puede remontar: lo que el analista abre se queda abierto.
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>({})
  const abrir = (clave: string) => (v: boolean) => setAbiertos((a) => ({ ...a, [clave]: v }))
  // Pestaña y fila elegidas. Las dos son PREFERENCIAS, no la verdad: si el
  // grupo se vacía o el lead sale de la cola en el refresco, se cae al primero
  // que exista en vez de dejar el panel «Ahora» mirando a un fantasma.
  const [grupoElegido, setGrupoElegido] = useState<GrupoDia | null>(null)
  const [leadElegido, setLeadElegido] = useState<string | null>(null)
  const encabezado = useRef<HTMLHeadingElement>(null)
  const nombreAhora = useRef<HTMLButtonElement>(null)
  const tituloDescartes = useRef<HTMLElement>(null)
  const tituloActividad = useRef<HTMLElement>(null)
  const panelAhora = useRef<HTMLElement>(null)

  const dia = useDiaAnalista(null, null)
  // La cola del día: la misma fuente que «Seguimiento comercial», sin filtros.
  const cola = useColaSlaPagina({ senal: 'todas', etapa: null, analista_id: null }, null, LIMITE_COLA, !yo?.demo)
  const paginaCola = cola.error ? undefined : cola.data
  // La cola y el día son DOS consultas: mientras la cola no ha llegado, decir
  // «no tienes nada pendiente» sería mentir (solo estarían los sin conversación).
  const colaCargando = !yo?.demo && cola.error == null && paginaCola === undefined

  const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
  const filas = useMemo<FilaDiaria[]>(() => {
    if (dia.dia === null) return []
    if (yo?.demo) return filasDiariasDemo(dia.dia.cartera, ahora, dia.dia.dia)
    return ordenarColaDiaria(paginaCola?.items ?? [], dia.dia.cartera)
  }, [ahora, dia.dia, paginaCola?.items, yo?.demo])
  const grupos = useMemo(() => agruparDiaria(filas), [filas])
  // El lead elegido se busca en la cola ENTERA, no dentro de la pestaña: si el
  // refresco de cada minuto lo mueve de «Hoy» a «Vencidas», el analista tiene
  // que seguir viendo a la MISMA persona y que la pestaña lo siga a él, no al
  // revés (hallazgo de Codex, 20/09/2026).
  const filaElegida = leadElegido === null ? null : filas.find((f) => f.lead_id === leadElegido) ?? null
  const grupoActivo = filaElegida?.grupo ?? grupos.find((g) => g.grupo === grupoElegido)?.grupo ?? grupos[0]?.grupo ?? null
  const delGrupo = grupos.find((g) => g.grupo === grupoActivo)?.filas ?? []
  // Mientras la cola no llegó, lo único que hay son los `sin_conversacion` de la
  // cartera: señalar a uno de ellos como «Ahora» mandaría a llamar al lead
  // equivocado — el sin primer intento manda, y todavía no ha llegado.
  // «Desconocido» no es «no existe».
  const filaActiva = colaCargando ? null : filaElegida ?? delGrupo[0] ?? null

  function elegir(fila: FilaDiaria) {
    setGrupoElegido(fila.grupo)
    setLeadElegido(fila.lead_id)
    // En una columna (móvil) el panel «Ahora» está ARRIBA de la cola: sin esto
    // el analista toca una fila y no ve que el panel cambió.
    // El foco viaja al panel: el nombre del lead lo anuncia y desde ahí «Llamar»
    // está a UN tabulador. Sin esto había que desandar la lista entera.
    // `scrollIntoView?.()`: no existe en jsdom y no vale la pena que una prueba
    // reviente por una comodidad visual.
    requestAnimationFrame(() => {
      panelAhora.current?.scrollIntoView?.({ block: 'nearest' })
      nombreAhora.current?.focus()
    })
  }
  function abrirPanel(fila: FilaDiaria) {
    const lead = leadsPorId.get(fila.lead_id)
    if (lead === undefined) { void abrirLead(fila.lead_id); return }
    setPanel({ lead, tarea: tareaQueCierra(tareasDe(lead.id), 'tel', yo?.id, ahora) ?? null })
  }
  /** Al guardar, el panel «Ahora» pasa al lead siguiente: se sigue marcando. */
  function saltarASiguiente(leadId: string) {
    const siguiente = filas[filas.findIndex((f) => f.lead_id === leadId) + 1]
    if (siguiente !== undefined) {
      setGrupoElegido(siguiente.grupo)
      setLeadElegido(siguiente.lead_id)
    }
    // DOS cuadros: el Dialog devuelve el foco al botón que lo abrió en SU propio
    // requestAnimationFrame, y un solo cuadro perdía la carrera (o lo pedía con
    // el diálogo aún abierto, y el FocusScope lo arrastraba de vuelta). Y solo
    // se salta si el foco quedó suelto: nunca se le quita al usuario uno útil.
    // El destino es el NOMBRE del panel: al enfocarlo, el lector de pantalla
    // dice a quién toca llamar ahora — que es justo lo que acaba de cambiar.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const destino = siguiente !== undefined ? nombreAhora.current : encabezado.current
      const activo = document.activeElement
      // `closest`: el escudo está en el CONTENEDOR de las acciones, y quien
      // tiene el foco es el <a>/<button> de dentro (hallazgo de Codex).
      const suelto = activo === null || activo === document.body
        || (activo instanceof HTMLElement && activo.closest('[data-accion-panel]') !== null)
      if (destino !== null && suelto) destino.focus()
    }))
  }
  async function deshacer(d: Descartado) {
    if (deshaciendo !== null) return
    setDeshaciendo(d.actividad_id)
    try {
      const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
      await deshacerResultadoLlamada(d.actividad_id)
      await dia.recargar()
      toast.success(`Deshecho: ${d.lead_nombre} vuelve a tu cartera`)
      // El botón que se acaba de pulsar desaparece (`puede_deshacer` pasa a
      // false, o el bloque se desmonta si era el único descarte): sin esto el
      // foco cae al body y el siguiente TAB reinicia la página. Misma
      // disciplina que `saltarASiguiente`: solo si quedó suelto.
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
  const colaCaida = !yo?.demo && (cola.error != null)

  return (
    <div className="mx-auto w-full max-w-[1640px] space-y-4">
      <header className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="min-w-0">
          <h2 ref={encabezado} tabIndex={-1} className="text-2xl font-bold leading-tight text-primary">¿A quién llamo ahora?</h2>
          <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">
            Tu cola del día completa, ordenada por urgencia. {corte ? `Corte ${corte} (Lima)` : 'Sin corte confirmado'} · se actualiza cada minuto.
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {/* El marcador es CONTEXTO, no trabajo pendiente: una línea en la
              cabecera y el detalle a un clic. Antes era una tarjeta entera
              debajo de la cola, que es donde el analista tiene que mirar. */}
          {dia.dia !== null && (
            <button type="button" onClick={verActividad} aria-expanded={abiertos['detalle'] ?? false} aria-controls={`${id}-actividad`}
              className="flex min-h-11 min-w-0 shrink items-center gap-2 rounded-xl border border-border bg-card px-4 text-left transition-colors hover:border-border-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
              <span className="text-sm text-[var(--muted-foreground-strong)]">Mi actividad</span>
              <span className="truncate text-sm font-semibold tabular-nums text-foreground">{resumenMarcador(dia.dia)}</span>
              {dia.dia.marcador.nivel !== null && (
                <Badge className="shrink-0 text-sm" color={COLOR_NIVEL[dia.dia.marcador.nivel]} dot>{ETIQUETA_NIVEL[dia.dia.marcador.nivel]}</Badge>
              )}
            </button>
          )}
          <Button variant="outline" size="sm" className="h-11 text-sm" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
            onClick={() => { if (dia.enVuelo) return; void dia.recargar(); void cola.refetch() }}>
            <RefreshCw aria-hidden className={dia.enVuelo ? 'motion-safe:animate-spin' : ''} /> Actualizar
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
            <p role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm font-semibold text-[var(--destructive-text)]">
              No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
            </p>
          )}
          {dia.dia.cartera_truncada && (
            <p role="status" className="text-sm font-semibold text-[var(--muted-foreground-strong)]">
              Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
            </p>
          )}

          {/* DOS PANELES HERMANOS, no una pila: el que actúa y el que elige. */}
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
            <PanelAhora fila={filaActiva} lead={filaActiva ? leadsPorId.get(filaActiva.lead_id) ?? null : null}
              sinConversacionDias={dia.dia.sin_conversacion_dias} ahora={ahora} cargando={colaCargando} colaCaida={colaCaida}
              seccionRef={panelAhora} nombreRef={nombreAhora}
              onGuardado={() => { if (filaActiva) saltarASiguiente(filaActiva.lead_id) }}
              onRegistrar={() => { if (filaActiva) abrirPanel(filaActiva) }}
              onAbrirFicha={() => { if (filaActiva) void abrirLead(filaActiva.lead_id) }} />

            <section aria-labelledby={`${id}-cola`} className="min-w-0 flex-1 space-y-3 rounded-2xl border border-border bg-card p-4">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <h3 id={`${id}-cola`} className="text-lg font-bold text-primary">Cola de hoy</h3>
                <span className="text-sm text-[var(--muted-foreground-strong)]">
                  {colaCargando ? 'cargando…' : `${filas.length} ${filas.length === 1 ? 'pendiente' : 'pendientes'}, de arriba abajo por urgencia`}
                </span>
              </div>
              {colaCargando ? (
                <PanelCargando filas={4} />
              ) : grupoActivo === null ? (
                // Una cola que NO se pudo leer no es una cola vacía: decir «no
                // tienes nada pendiente» aquí sería afirmar lo que no se sabe.
                colaCaida ? (
                  <PanelVacio icono={PhoneCall} titulo="No se pudo leer tu cola"
                    detalle="No sabemos a quién te toca llamar. Pulsa «Actualizar» para volver a intentarlo." />
                ) : (
                  <PanelVacio icono={PhoneCall} titulo="No tienes nada pendiente ahora"
                    detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana." />
                )
              ) : (
                <Tabs etiqueta="Grupos de la cola" valor={grupoActivo} onCambio={(g) => { setGrupoElegido(g); setLeadElegido(null) }}
                  className="[&_[role=tab]]:text-sm"
                  pestanas={grupos.map((g) => {
                    const meta = GRUPOS_DIA.find((x) => x.clave === g.grupo)!
                    return { valor: g.grupo, etiqueta: `${meta.etiqueta} (${g.filas.length})` }
                  })}>
                  <div className="space-y-2">
                    <p className="text-sm text-[var(--muted-foreground-strong)]">
                      {GRUPOS_DIA.find((g) => g.clave === grupoActivo)?.ayuda}
                    </p>
                    {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
                    <ol role="list" aria-label={`${GRUPOS_DIA.find((g) => g.clave === grupoActivo)?.etiqueta} (${delGrupo.length})`}
                      className="space-y-2">
                      {delGrupo.map((fila) => (
                        <FilaCola key={fila.lead_id} fila={fila} ahora={ahora}
                          activa={fila.lead_id === filaActiva?.lead_id} onElegir={() => elegir(fila)} />
                      ))}
                    </ol>
                  </div>
                </Tabs>
              )}
            </section>
          </div>

          <Actividad id={`${id}-actividad`} dia={dia.dia} abierto={abiertos['detalle'] ?? false} onAbrir={abrir('detalle')} summaryRef={tituloActividad} />
          <Compromisos dia={dia.dia} abierto={abiertos['compromisos'] ?? false} onAbrir={abrir('compromisos')}
            onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
          <Descartados dia={dia.dia} deshaciendo={deshaciendo} onDeshacer={(d) => { void deshacer(d) }}
            abierto={abiertos['descartados'] ?? false} onAbrir={abrir('descartados')} summaryRef={tituloDescartes}
            onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
          {yo?.demo && <p className="text-sm text-muted-foreground">Datos de ejemplo: en la sesión real tu día sale del servidor.</p>}
        </>
      )}

      {panel !== null && (
        <RegistrarResultado lead={panel.lead} tarea={panel.tarea} onClose={() => setPanel(null)}
          onGuardado={() => saltarASiguiente(panel.lead.id)} />
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
function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaida, onRegistrar, onAbrirFicha, onGuardado, seccionRef, nombreRef }: {
  fila: FilaDiaria | null
  lead: Lead | null
  sinConversacionDias: number
  ahora: number
  cargando: boolean
  colaCaida: boolean
  onRegistrar: () => void
  onAbrirFicha: () => void
  onGuardado: () => void
  seccionRef: Ref<HTMLElement>
  nombreRef: Ref<HTMLButtonElement>
}): JSX.Element {
  const id = useId()
  const etapa = fila === null ? null : ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
  const tiempo = fila === null ? null : tiempoDeFila(fila, ahora)
  return (
    <section ref={seccionRef} aria-labelledby={`${id}-ahora`}
      className="flex w-full flex-col gap-3 rounded-2xl border border-border bg-card p-4 lg:sticky lg:top-4 lg:w-[340px] lg:shrink-0">
      <h3 id={`${id}-ahora`} className="text-sm font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]">Ahora</h3>
      {fila === null ? (
        <p className="text-base text-[var(--muted-foreground-strong)]">
          {cargando ? 'Buscando a quién llamar…'
            : colaCaida ? 'No se pudo leer tu cola: no sabemos a quién te toca llamar. Pulsa «Actualizar».'
              : 'Nada pendiente ahora. Cuando entre un lead nuevo aparecerá aquí.'}
        </p>
      ) : (
        <>
          <p className="min-w-0">
            <button ref={nombreRef} type="button" onClick={onAbrirFicha}
              className="inline-flex min-h-11 items-start rounded-md text-left text-xl font-bold leading-tight text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
              {fila.nombre_completo}
            </button>
          </p>
          <p className="text-sm text-[var(--muted-foreground-strong)]">{etapa}</p>
          {tiempo !== null && (
            <Badge className="self-start text-sm" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
          )}
          <p className="text-sm text-[var(--muted-foreground-strong)]">{detalleDeFila(fila, sinConversacionDias)}</p>
          <div className="lg:flex-1" />
          {lead !== null && <p className="text-base font-semibold tabular-nums text-foreground">{lead.telefono}</p>}
          <div className="flex items-start gap-2">
            {lead !== null ? (
              // `key={lead.id}`: UNA instancia por lead. Antes las acciones
              // vivían dentro de cada fila y se desmontaban con ella; aquí hay
              // una sola caja que cambia de lead, y si el refresco de cada
              // minuto cambiaba el lead con el diálogo de resultado ABIERTO, el
              // resultado se escribía sobre el lead equivocado. La clave fuerza
              // el remontaje: el contacto a medias se cae a la vista, que es
              // reparable — atribuirlo a otra persona, no (hallazgo de Codex).
              <div className={`min-w-0 flex-1 ${ACCIONES_PANEL}`} data-accion-panel="si">
                <AccionesContacto key={lead.id} lead={lead} onGuardado={onGuardado} />
              </div>
            ) : (
              <p className="min-w-0 flex-1 text-sm text-[var(--muted-foreground-strong)]">Abre la ficha para llamar</p>
            )}
            <DropdownMenu
              trigger={
                <button type="button" data-accion-panel="si"
                  aria-label={`Más acciones para ${fila.nombre_completo}: registrar resultado y ver la ficha`}
                  className="grid size-12 shrink-0 cursor-pointer place-items-center rounded-xl border border-border-strong bg-card text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
                  <MoreHorizontal aria-hidden className="size-5" />
                </button>
              }>
              <DropdownItem onSelect={onRegistrar}>Registrar resultado</DropdownItem>
              <DropdownItem onSelect={onAbrirFicha}>Ver la ficha completa</DropdownItem>
            </DropdownMenu>
          </div>
        </>
      )}
    </section>
  )
}

/**
 * Una fila de la cola: DOS datos y ningún botón suelto. La fila entera es el
 * selector (`aria-current` dice cuál está en el panel «Ahora»), porque quien
 * actúa es el panel: aquí solo se elige a quién se mira.
 */
function FilaCola({ fila, ahora, activa, onElegir }: {
  fila: FilaDiaria
  ahora: number
  activa: boolean
  onElegir: () => void
}): JSX.Element {
  const tiempo = tiempoDeFila(fila, ahora)
  return (
    <li>
      <button type="button" onClick={onElegir} {...(activa ? { 'aria-current': true as const } : {})}
        className={`flex w-full min-h-16 items-center justify-between gap-3 rounded-xl border px-4 py-3 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40 ${
          activa ? 'border-2 border-primary bg-primary/5' : 'border-border hover:border-border-strong hover:bg-muted/50'}`}>
        <span className="min-w-0 flex-1 truncate text-base font-semibold text-primary">{fila.nombre_completo}</span>
        <Badge className="shrink-0 text-sm" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
      </button>
    </li>
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
      <p className="text-sm font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</p>
      <p className={`text-2xl font-extrabold leading-tight tabular-nums ${tono ?? 'text-foreground'}`}>
        {valorAccesible !== undefined ? (
          <>
            <span aria-hidden="true">{valor}</span>
            <span className="sr-only">{valorAccesible}</span>
          </>
        ) : valor}
      </p>
      {apoyo !== undefined && <p className="mt-0.5 text-sm text-[var(--muted-foreground-strong)]">{apoyo}</p>}
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
        <p className="text-sm text-[var(--muted-foreground-strong)]">
          Tocaste {m.leads_tocados} {m.leads_tocados === 1 ? 'lead' : 'leads'}. Llamadas = marcadas + no contestadas.
          No incluye WhatsApp ni citas. Un número errado no entra en la tasa.
          {m.primera_llamada_en !== null && ` Primera ${horaLimaDe(m.primera_llamada_en)}, última ${horaLimaDe(m.ultima_llamada_en)} (Lima).`}
        </p>
        {m.llamadas > 0 && (
          <div>
            <h4 id={`${id}-horas`} className="text-sm font-semibold text-[var(--muted-foreground-strong)]">Llamadas por hora (08–20, Lima)</h4>
            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
            <ul role="list" className="mt-2 flex items-end gap-1.5" aria-labelledby={`${id}-horas`}>
              {barras.map((b) => (
                <li key={b.hora} className="flex min-w-0 flex-1 flex-col items-center gap-1">
                  <span className="w-full rounded-t bg-primary/80" style={{ height: `${Math.round((b.llamadas / b.maximo) * 56) + 2}px` }}
                    aria-hidden />
                  <span className="sr-only">
                    {b.hora}:00 — {b.llamadas} {b.llamadas === 1 ? 'llamada' : 'llamadas'}, {b.contestadas} {b.contestadas === 1 ? 'contestada' : 'contestadas'}
                  </span>
                  <span aria-hidden className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">{b.hora}</span>
                </li>
              ))}
            </ul>
            {fuera > 0 && <p className="mt-2 text-sm text-[var(--muted-foreground-strong)]">{fuera} fuera de la franja 08–20.</p>}
          </div>
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
                  <p className="text-sm text-[var(--muted-foreground-strong)]">
                    {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
                    {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
                  </p>
                </div>
                <span className="text-sm font-semibold tabular-nums text-foreground">{cuandoLimaDe(c.vence_en)}</span>
              </li>
            ))}
          </ol>
          {dia.compromisos_total > dia.compromisos.length && (
            <p className="mt-3 text-sm text-[var(--muted-foreground-strong)]">
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
      <p className="text-sm text-[var(--muted-foreground-strong)]">
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
              <p className="text-sm text-[var(--muted-foreground-strong)]">
                {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
                {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
              </p>
            </div>
            {d.puede_deshacer ? (
              // `aria-disabled` y no `disabled`: deshabilitar el botón enfocado
              // manda el foco al body (regla de la casa, boton-guardar.tsx).
              <Button variant="outline" size="sm" className="h-11 text-sm" aria-disabled={deshaciendo !== null}
                aria-label={`Deshacer el descarte de ${d.lead_nombre}`}
                onClick={() => { if (deshaciendo === null) onDeshacer(d) }}>
                <RotateCcw aria-hidden /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
              </Button>
            ) : (
              <span className="text-sm text-[var(--muted-foreground-strong)]">Sin deshacer</span>
            )}
          </li>
        ))}
      </ol>
    </Plegable>
  )
}
