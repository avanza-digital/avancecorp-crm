// Gestión Diaria · Fase 3 — «Mi día» del analista. Responde una sola pregunta:
// ¿a quién llamo AHORA? La cola sale de `crm.cola_accion_v2_fn` (la misma del
// mundo SLA) y el resto del día —marcador, compromisos, señales por lead y los
// descartes con su «Deshacer»— de `crm.gestion_diaria_analista_fn`. Aquí no se
// calcula negocio: se ORDENA (`ordenarColaDiaria`, función pura probada) y se
// presenta.
//
// DENSIDAD (20/09/2026). Los analistas devolvieron «demasiada información,
// muchas letras pequeñas». La pantalla pasa a DOS paneles en una fila: «Ahora»
// con la persona que toca y su única acción primaria, y la cola en cuatro
// PESTAÑAS con su conteo, de las que solo se ve una lista. El marcador, las
// llamadas por hora, el seguimiento y los descartes se mudan a «Mi actividad»,
// un segundo nivel. Piso tipográfico 16 px en todo: ni un `text-xs`.
//
// «Hoy» NO cambia: sigue siendo «las 3 cosas de ahora» (decisión de Miguel).
// Esta pantalla es la cola COMPLETA del día, y las dos comparten el primer
// ítem: el lead sin primer intento manda en ambas (test compartido).
import { useId, useMemo, useRef, useState, type JSX } from 'react'
import { ArrowLeft, BarChart3, ClipboardList, RefreshCw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import type { Lead, Tarea } from '@/lib/tipos'
import { tareaQueCierra } from '@/lib/contacto-tarea'
import {
  filasDiariasDemo, horaLimaDe, ordenarColaDiaria, paginaDeFilas, pestanasDiarias, textoTasa,
  type Descartado, type FilaDiaria, type GrupoDia,
} from '@/lib/gestion-diaria-analista'
import { useDiaAnalista } from '@/data/gestion-diaria-queries'
import { useColaSlaPagina } from '@/data/sla-operacion-queries'
import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
import { ColaDeHoy, FILAS_POR_PAGINA } from '@/components/gestion-diaria/cola-de-hoy'
import { MiActividad } from '@/components/gestion-diaria/mi-actividad'
import { TarjetaAhora } from '@/components/gestion-diaria/tarjeta-ahora'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'

const LIMITE_COLA = 100

export function GestionDiariaAnalista(): JSX.Element {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { ambito, tareasDe } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()

  // TODO el estado vive AQUÍ, por encima de la cascada de carga/error: el hook
  // del día es fail-closed (un refetch fallido devuelve `null`) y, si la
  // pestaña o la persona elegida colgaran del subárbol, un parpadeo de red le
  // borraría al analista dónde estaba.
  const [panel, setPanel] = useState<{ lead: Lead; tarea: Tarea | null } | null>(null)
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  const [verActividad, setVerActividad] = useState(false)
  const [elegido, setElegido] = useState<string | null>(null)
  const [pestanaPedida, setPestanaPedida] = useState<GrupoDia | null>(null)
  const [pagina, setPagina] = useState(0)
  // El lead cuyo resultado se acaba de guardar: sigue en la cola hasta que el
  // servidor conteste, y sin esto «Ahora» volvería a proponer al que ya cerraste.
  const [recienCerrado, setRecienCerrado] = useState<string | null>(null)
  const encabezado = useRef<HTMLHeadingElement>(null)

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
    return recienCerrado === null ? todas : todas.filter((f) => f.lead_id !== recienCerrado)
  }, [ahora, dia.dia, paginaCola?.items, recienCerrado, yo?.demo])

  const pestanas = useMemo(() => pestanasDiarias(filas), [filas])
  // La pestaña que pidió el analista manda, PERO si su grupo se vacía se cae
  // sola al primero que tenga gente: si no, la pantalla se queda clavada en una
  // pestaña vacía que nadie volvió a pedir.
  const pedidaViva = pestanaPedida !== null && (pestanas.find((p) => p.clave === pestanaPedida)?.total ?? 0) > 0
  const activa: GrupoDia = pedidaViva && pestanaPedida !== null
    ? pestanaPedida
    : pestanas.find((p) => p.total > 0)?.clave ?? 'primera_atencion'

  const delGrupo = pestanas.find((p) => p.clave === activa)?.filas ?? []
  const vista = paginaDeFilas(delGrupo, pagina, FILAS_POR_PAGINA)
  // Sin elección explícita, «Ahora» es el primero de la página: el orden del
  // servidor ya dice quién urge más.
  const fila = delGrupo.find((f) => f.lead_id === elegido) ?? vista.filas[0] ?? null
  const posicion = fila === null ? 0 : delGrupo.findIndex((f) => f.lead_id === fila.lead_id) + 1
  const lead = fila === null ? null : leadsPorId.get(fila.lead_id) ?? null

  function elegir(f: FilaDiaria) {
    setElegido(f.lead_id)
  }
  function cambiarPestana(grupo: GrupoDia) {
    setPestanaPedida(grupo)
    setPagina(0)
    setElegido(null)
  }
  function abrirPanel() {
    if (fila === null) return
    const suyo = leadsPorId.get(fila.lead_id)
    if (suyo === undefined) { void abrirLead(fila.lead_id); return }
    setPanel({ lead: suyo, tarea: tareaQueCierra(tareasDe(suyo.id), 'tel', yo?.id, ahora) ?? null })
  }
  /** Al guardar, «Ahora» pasa al siguiente y el foco vuelve al encabezado. */
  async function alGuardar(leadId: string) {
    setRecienCerrado(leadId)
    setElegido(null)
    // El Dialog devuelve el foco al botón que lo abrió en su propio cuadro; ese
    // botón sigue vivo (está en «Ahora»), así que aquí no se le quita el foco a
    // nadie: solo se recoloca en el encabezado cuando quedó suelto.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const activo = document.activeElement
      if (activo === null || activo === document.body || activo === document.documentElement) encabezado.current?.focus()
    }))
    try {
      await Promise.all([dia.recargar(), cola.refetch()])
    } finally {
      // El servidor ya contestó: si el lead sigue en la cola es porque de verdad
      // sigue pendiente, y entonces debe volver a verse.
      setRecienCerrado(null)
    }
  }
  /**
   * P1 de accesibilidad: el botón que abre o cierra «Mi actividad» se DESMONTA
   * al pulsarlo (las dos ramas del ternario son de tipo distinto), así que el
   * foco caería al `body` y habría que volver a tabular la barra lateral entera.
   * El encabezado ya es focalizable y su texto distingue los dos niveles: mover
   * el foco ahí resuelve el foco Y el anuncio del cambio de vista.
   */
  function cambiarNivel(actividad: boolean) {
    setVerActividad(actividad)
    requestAnimationFrame(() => encabezado.current?.focus())
  }
  async function deshacer(d: Descartado) {
    if (deshaciendo !== null) return
    setDeshaciendo(d.actividad_id)
    try {
      const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
      await deshacerResultadoLlamada(d.actividad_id)
      setRecienCerrado(null)
      await dia.recargar()
      toast.success(`Deshecho: ${d.lead_nombre} vuelve a tu cartera`)
    } catch (causa) {
      const { mensajeDeError } = await import('@/data/crm-api')
      toast.error(mensajeDeError(causa, 'No se pudo deshacer el descarte.'))
    } finally {
      setDeshaciendo(null)
    }
  }

  const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
  const m = dia.dia?.marcador

  return (
    <div className="mx-auto flex w-full max-w-[1640px] flex-col gap-6">
      <header className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          {/* h2 y no h1: el `<h1>` de la vista lo pone el topbar del CRM. */}
          <h2 ref={encabezado} tabIndex={-1} className="text-2xl font-bold leading-8 text-primary">
            {verActividad ? 'Mi actividad de hoy' : '¿A quién llamo ahora?'}
          </h2>
          <p className="mt-1 text-base text-[var(--muted-foreground-strong)]">
            {corte ? `Corte ${corte} (Lima)` : 'Sin corte confirmado'} · se actualiza cada minuto
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          {verActividad ? (
            <>
              <Button variant="outline" className="h-12 text-base font-normal" onClick={() => cambiarNivel(false)}>
                <ArrowLeft aria-hidden /> Volver a mi día
              </Button>
              <Button variant="outline" className="h-12 text-base font-normal" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
                onClick={() => { if (dia.enVuelo) return; void dia.recargar(); void cola.refetch() }}>
                <RefreshCw aria-hidden className={dia.enVuelo ? 'motion-safe:animate-spin' : ''} /> Actualizar
              </Button>
            </>
          ) : (
            <Button variant="outline" className="h-12 gap-4 text-base font-normal" onClick={() => cambiarNivel(true)}>
              <BarChart3 aria-hidden /> Mi actividad
              {m !== undefined && (
                <span className="text-lg font-medium text-foreground">
                  {m.llamadas} {m.llamadas === 1 ? 'llamada' : 'llamadas'} · {textoTasa(m)}
                </span>
              )}
            </Button>
          )}
        </div>
      </header>

      {/* Los avisos viven en el PRIMER nivel y se ven en los dos: si la cola se
          cae mientras el analista mira su actividad, tiene que enterarse. */}
      {colaCaida && (
        <p role="alert" className="text-base font-medium text-[var(--destructive-text)]">
          No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Actualiza para verla completa.
        </p>
      )}
      {dia.dia?.cartera_truncada === true && (
        <p role="status" className="text-base text-[var(--muted-foreground-strong)]">
          Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
        </p>
      )}

      {dia.error != null && dia.dia === null ? (
        <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
      ) : dia.dia === null && dia.cargando ? (
        <PanelCargando filas={6} />
      ) : dia.dia === null ? (
        <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." tamano="grande" />
      ) : verActividad ? (
        <MiActividad dia={dia.dia} deshaciendo={deshaciendo}
          onDeshacer={(d) => { void deshacer(d) }} onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
      ) : (
        <div id={`${id}-dia`} className="flex flex-col gap-6 lg:flex-row lg:items-stretch">
          <TarjetaAhora
            idBase={id}
            fila={fila} lead={lead} ahora={ahora} posicion={posicion} total={delGrupo.length}
            onRegistrar={abrirPanel}
            onAbrirFicha={() => { if (fila !== null) void abrirLead(fila.lead_id) }}
          />
          <ColaDeHoy
            idBase={id}
            pestanas={pestanas} activa={activa} onPestana={cambiarPestana}
            pagina={vista.pagina} onPagina={setPagina}
            elegido={fila?.lead_id ?? null} onElegir={elegir}
            ahora={ahora} cargando={colaCargando} hayMas={paginaCola?.hay_mas === true}
          />
        </div>
      )}

      {yo?.demo && <p className="text-base text-[var(--muted-foreground-strong)]">Datos de ejemplo: en la sesión real tu día sale del servidor.</p>}

      {panel !== null && (
        <RegistrarResultado lead={panel.lead} tarea={panel.tarea} onClose={() => setPanel(null)}
          onGuardado={() => { void alGuardar(panel.lead.id) }} />
      )}
    </div>
  )
}
