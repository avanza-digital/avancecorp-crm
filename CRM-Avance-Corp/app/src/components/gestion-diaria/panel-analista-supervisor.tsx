import { useLayoutEffect, useRef, useState, type RefObject } from 'react'
import { Title as TituloDialogo } from '@radix-ui/react-dialog'
import { ClipboardList, Maximize2, Minimize2, X, Users } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Tabs } from '@/components/ui/tabs'
import { RegistroActividad } from './registro-actividad'
import { PendientesSupervisor } from './pendientes-supervisor'
import { ResumenAnalista } from './resumen-analista'
import { UltimasGestionesSupervisor } from './ultimas-gestiones-supervisor'
import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import type { PestanaRegistro } from '@/lib/gestion-diaria'
import { cn } from '@/lib/utils'

/**
 * `origen` (revisión Codex del plan, 27/09): una selección AUTOMÁTICA (quien más
 * atención necesita) no abre nunca una ventana ni mueve el foco; la del usuario
 * y la de un aviso, sí siguen la mecánica adaptable de siempre.
 */
export interface SeleccionSupervisor {
  analista: string | null; nombre: string | null; apertura: number; pestana: PestanaRegistro; enfocar: boolean
  origen?: 'automatica' | 'usuario' | 'aviso' | undefined
}
type PestanaPanel = 'resumen' | 'registro' | 'pendientes'

const BOTON_ICONO = 'grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] text-[var(--muted-foreground-strong)] transition-colors hover:bg-muted hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:size-11'

export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, vacio, silencioso = false, conPendientes = true, idsEquipo = null, subtitulo = 'Analista de tu equipo' }: {
  id: string
  seleccion: SeleccionSupervisor | null
  fila: FilaEquipoPresentada | undefined
  dia: string
  minimo: number | undefined
  tituloRef: RefObject<HTMLHeadingElement | null>
  ampliado: boolean
  puedeAmpliar: boolean
  ampliar: () => void
  cerrar: () => void
  oculta: boolean
  limpiar: () => void
  actualizacion: number
  revalidar: () => void
  esHoy: boolean
  ahora: number
  /** El texto del panel sin selección (p. ej., «Nadie necesita atención ahora…»). */
  vacio?: string | undefined
  /** Selección automática: sus cargas y errores no se anuncian (el usuario no la abrió). */
  silencioso?: boolean
  /** Sin pestaña Pendientes cuando la sesión no puede consultarlos (gerencia antes de G4a). */
  conPendientes?: boolean
  /** Alcance del registro del equipo; null = lo que la sesión puede ver (el equipo del supervisor). */
  idsEquipo?: readonly string[] | null
  subtitulo?: string
}) {
  const equipo = seleccion?.analista === null
  const nombre = seleccion && !equipo ? fila?.nombre_completo ?? seleccion.nombre ?? 'Analista' : null
  const titulo = seleccion ? equipo ? 'Registro del equipo' : `Detalle de ${nombre}` : 'Detalle del analista'
  return (
    <section id={id} aria-label={titulo} className="flex min-h-0 min-w-0 flex-1 flex-col overflow-clip rounded-2xl border border-accent/30 bg-card shadow-[0_14px_34px_-18px_rgba(17,30,61,0.35)]">
      <header className="flex shrink-0 items-center gap-3.5 border-b border-accent/15 bg-accent/[0.06] px-5 py-4">
        {nombre !== null ? <Avatar nombre={nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
          : equipo ? <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary"><ClipboardList className="size-4" /></span> : null}
        <div className="min-w-0 flex-1">
          {/* El nombre visible es el del analista; el lector oye «Detalle de …»,
              como el nombre de la región y del diálogo. */}
          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className="rounded-md text-[22px] font-extrabold leading-tight tracking-[-0.015em] text-primary [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
            {/* El espacio va FUERA del texto oculto: dentro se perdía («Detalle deANA»). */}
            {nombre !== null ? <><span className="sr-only">Detalle de</span>{' '}{nombre}</> : titulo}
          </h3></TituloDialogo>
          {nombre !== null && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{subtitulo}</p>}
        </div>
        {seleccion && <div className="flex shrink-0 gap-0.5">
          {puedeAmpliar && <button type="button" className={BOTON_ICONO} aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden className="size-4" /> : <Maximize2 aria-hidden className="size-4" />}</button>}
          <button type="button" className={BOTON_ICONO} aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden className="size-[18px]" /></button>
        </div>}
      </header>
      {!seleccion ? <div className="flex flex-1 flex-col items-center justify-center gap-3 px-8 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
        <Users className="size-9 text-muted-foreground" aria-hidden /><p>{vacio ?? 'Selecciona un analista de la tabla para consultar su día.'}</p></div>
        : <ContenidoSeleccionado key={`${seleccion.analista ?? 'equipo'}:${seleccion.apertura}`} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo} conPendientes={conPendientes} idsEquipo={idsEquipo}
          tituloRef={tituloRef} oculta={oculta} limpiar={limpiar} actualizacion={actualizacion} revalidar={revalidar} esHoy={esHoy} ahora={ahora} silencioso={silencioso} />}
    </section>
  )
}

const FECHA_TITULO = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })

function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, silencioso, conPendientes, idsEquipo }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor; esHoy: boolean; ahora: number; silencioso: boolean; conPendientes: boolean; idsEquipo: readonly string[] | null }) {
  const equipo = seleccion.analista === null
  const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
  const [registro, setRegistro] = useState<{ pestana: PestanaRegistro; apertura: number } | null>(equipo || seleccion.enfocar ? { pestana: seleccion.pestana, apertura: 0 } : null)
  const [pendientes, setPendientes] = useState<{ soloVencidas: boolean; apertura: number; enfocar: boolean } | null>(null)
  const tituloRegistro = useRef<HTMLHeadingElement>(null)
  const cuerpoResumen = useRef<HTMLDivElement>(null)
  const alInicio = () => cuerpoResumen.current?.closest('[role=tabpanel]')?.scrollTo?.({ top: 0 })
  const [focoRegistro, setFocoRegistro] = useState(0)
  useLayoutEffect(() => {
    if (seleccion.enfocar) tituloRef.current?.focus({ preventScroll: true })
  }, [seleccion.enfocar, tituloRef])
  useLayoutEffect(() => {
    if (focoRegistro) tituloRegistro.current?.focus({ preventScroll: true })
  }, [focoRegistro])
  const cambiar = (valor: PestanaPanel) => {
    alInicio()
    setPestana(valor)
    if (valor === 'registro' && !registro) setRegistro({ pestana: 'todo', apertura: 0 })
    if (valor === 'pendientes' && !pendientes) setPendientes({ soloVencidas: false, apertura: 0, enfocar: false })
  }
  const abrirRegistro = (inicial: PestanaRegistro) => {
    alInicio()
    setRegistro((r) => ({ pestana: inicial, apertura: (r?.apertura ?? 0) + 1 }))
    setPestana('registro')
    setFocoRegistro((n) => n + 1)
  }
  const abrirPendientes = (soloVencidas: boolean) => {
    alInicio()
    setPendientes(p => ({ soloVencidas, apertura: (p?.apertura ?? 0) + 1, enfocar: true }))
    setPestana('pendientes')
  }
  const cuerpo = 'min-w-0 px-5 py-4 [overflow-wrap:anywhere]'
  const contenido = <>
    <div ref={cuerpoResumen} className={cn(cuerpo, 'space-y-5')} hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
      {!fila || minimo === undefined ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">El resumen no está disponible. El registro conserva su consulta independiente.</p>
        : <ResumenAnalista fila={fila} dia={dia} minimo={minimo} esHoy={esHoy} ahora={ahora}
          abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={conPendientes ? abrirPendientes : undefined} />}
      {seleccion.analista !== null && <>
        <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} silencioso={silencioso} />
        <div className="space-y-2">
          <button type="button" onClick={() => abrirRegistro('todo')}
            className="flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-accent text-sm font-bold text-accent-foreground transition-colors hover:bg-[var(--accent-press)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
            Ver el registro del día
          </button>
          <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">El registro se consulta al abrirlo y solo muestra actividades cuyos leads siguen visibles para tu sesión; puede diferir de esta foto.</p>
        </div>
      </>}
    </div>
    <div className={cuerpo} hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
      {/* Como el resumen (Miguel, 27/09): un título corto con el día, filtros en
          pastilla y filas limpias; sin la descripción ni controles de pantalla completa. */}
      {registro && <section aria-label="Registro seleccionado" className="space-y-2">
        <h4 ref={tituloRegistro} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
          {esHoy ? 'Actividad de hoy' : `Actividad del ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
        </h4>
        <RegistroActividad compacto encabezadoExterno={tituloRegistro} key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
          analistaIds={seleccion.analista === null ? idsEquipo : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
      </section>}
    </div>
    <div className={cuerpo} hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
      {conPendientes && pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
        analista={seleccion.analista} nombre={fila?.nombre_completo ?? seleccion.nombre ?? 'Analista'} dia={dia} fila={fila}
        visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
        enfocar={pendientes.enfocar} actualizacion={actualizacion} revalidar={revalidar} />}
    </div>
  </>
  return <>
    {oculta && <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 bg-muted px-5 py-1.5 text-[13px]">La selección está fuera de los filtros.
      <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" onClick={limpiar}>Limpiar filtros</Button></div>}
    {/* El cuerpo con scroll es el panel de la pestaña (parada del tabulador):
        así el texto tras el último control se alcanza sin ratón. */}
    {equipo ? <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">{contenido}</div>
      : <Tabs etiqueta="Detalle del analista" variante="subrayado" valor={pestana} onCambio={cambiar}
        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, ...(conPendientes ? [{ valor: 'pendientes' as const, etiqueta: 'Pendientes' }] : [])]}
        className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
        clasePanel="ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2">{contenido}</Tabs>}
  </>
}
