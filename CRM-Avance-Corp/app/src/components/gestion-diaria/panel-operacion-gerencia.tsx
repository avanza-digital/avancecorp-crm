// Panel de «Toda la operación» (diseño de Gestión Diaria, 27/09/2026): la ficha
// protagonista del equipo —como la del analista en el supervisor—, la lista de
// quienes no tienen registro y el registro (general o del equipo). Las cifras del
// equipo son las del pulso; el detalle solo aporta atención y barras de sus
// analistas activos, y lo dice (revisión Codex del plan).
import { useRef, type JSX, type ReactNode, type RefObject } from 'react'
import { Title as TituloDialogo } from '@radix-ui/react-dialog'
import { CalendarCheck, ChevronRight, ClipboardList, Maximize2, Minimize2, UserX, Users, X } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { cifraPulso, type EquipoPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
import { atencionEquipo, barrasEquipo, delEquipo, nombreEquipo, personasSinRegistro, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
import { presentarAtencion, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import type { PestanaRegistro } from '@/lib/gestion-diaria'
import { cn } from '@/lib/utils'
import { BarrasPorHora } from './barras-por-hora'
import { RegistroActividad } from './registro-actividad'
import { CitasAgendadas } from './citas-agendadas'
import { BOTON_ICONO, CABECERA_FICHA, FICHA, FOCO, TITULO_FICHA } from './estilos-gestion'

export type VistaOperacion =
  | { tipo: 'equipo'; clave: string }
  | { tipo: 'sin_registro' }
  | { tipo: 'registro'; alcance: 'general' | string; pestana: PestanaRegistro; apertura: number }
  /** G4b: la lista exacta de «Citas agendadas» de la operación, de un equipo o de «fuera». */
  | { tipo: 'citas'; ambito: 'operacion' | 'equipo' | 'fuera'; clave: string | null; apertura: number }

export type { PresetEquipo } from '@/lib/gestion-diaria-operacion'

const ENLACE = cn('mt-1.5 inline-flex min-h-6 cursor-pointer items-center gap-0.5 rounded-md text-xs font-semibold text-[var(--accent-press)] hover:underline pointer-coarse:min-h-11', FOCO)
const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`

function Cuadro({ etiqueta, children }: { etiqueta: string; children: ReactNode }): JSX.Element {
  return (
    <div className="min-w-0 rounded-xl bg-muted/70 px-3.5 py-3">
      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
      <dd className="mt-1 min-w-0">{children}</dd>
    </div>
  )
}

export function PanelOperacionGerencia({ id, vista, pulso, detalle, detalleFallido = false, esHoy, tituloRef, ampliado, puedeAmpliar, ampliar, cerrar, abrirVista, entrarEquipo, abrirPersona, actualizacion, revocar }: {
  id: string
  vista: VistaOperacion | null
  pulso: PulsoGerencia
  /** Filas del detalle de la operación; null mientras no llega. */
  detalle: FilaEquipoPresentada[] | null
  /** El detalle falló: atención y barras NO disponibles (no «consultando…» para siempre). */
  detalleFallido?: boolean
  esHoy: boolean
  tituloRef: RefObject<HTMLHeadingElement | null>
  ampliado: boolean
  puedeAmpliar: boolean
  ampliar: () => void
  cerrar: () => void
  abrirVista: (vista: VistaOperacion) => void
  entrarEquipo: (clave: string, preset?: PresetEquipo) => void
  abrirPersona: (analistaId: string) => void
  actualizacion: number
  revocar: () => void
}): JSX.Element {
  const claveEquipo = vista?.tipo === 'equipo' ? vista.clave : vista?.tipo === 'registro' && vista.alcance !== 'general' ? vista.alcance
    : vista?.tipo === 'citas' && vista.ambito !== 'operacion' ? vista.ambito === 'fuera' ? 'fuera' : vista.clave : null
  const equipo = claveEquipo === null ? undefined : pulso.equipos.find((e) => e.clave === claveEquipo)
  // Si el equipo sale de la consulta, el título (y el nombre de la ventana) no queda vacío (a11y, 27/09).
  const nombre = equipo ? nombreEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : 'Equipo no disponible'
  const del = equipo ? delEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre }) : 'del equipo no disponible'
  const titulo = vista === null ? 'Detalle de la operación' : vista.tipo === 'sin_registro' ? 'Sin registro'
    : vista.tipo === 'citas' ? 'Citas agendadas'
      : vista.tipo === 'registro' ? vista.alcance === 'general' ? 'Registro general' : `Registro ${del}` : nombre
  // Como la ficha del supervisor (Miguel, 27/09): un nombre corto arriba y una línea
  // debajo. Se ve el nombre del supervisor; se oye «Detalle del Equipo de …».
  const fuera = equipo?.clave === 'fuera'
  const subtitulo = vista === null ? null : vista.tipo === 'sin_registro'
    ? `${plural(pulso.actual.sin_actividad, 'analista sin ninguna gestión', 'analistas sin ninguna gestión')} ${esHoy ? 'hoy' : 'ese día'}`
    : vista.tipo === 'registro' ? equipo ? nombre : null
      : vista.tipo === 'citas' ? vista.ambito === 'operacion' ? 'Toda la operación' : nombre
        : equipo ? `${fuera ? '' : 'Equipo de '}${plural(equipo.metricas.analistas_activos, 'analista', 'analistas')}` : null
  return (
    <section id={id} aria-label={vista?.tipo === 'equipo' ? `Detalle ${del}` : titulo} className={FICHA}>
      <header className={CABECERA_FICHA}>
        {vista?.tipo === 'equipo' && equipo ? <Avatar nombre={equipo.nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
          : <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary">
            {vista?.tipo === 'sin_registro' ? <UserX className="size-4" /> : vista?.tipo === 'registro' ? <ClipboardList className="size-4" />
              : vista?.tipo === 'citas' ? <CalendarCheck className="size-4" /> : <Users className="size-4" />}
          </span>}
        <div className="min-w-0 flex-1">
          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className={TITULO_FICHA}>
            {vista?.tipo === 'equipo' && equipo ? <><span className="sr-only">{fuera ? 'Detalle del grupo' : 'Detalle del Equipo de'}</span>{' '}{equipo.nombre}</>
              : vista?.tipo === 'registro' && equipo ? <>Registro del equipo<span className="sr-only">: {nombre}</span></>
                : vista?.tipo === 'citas' ? <>Citas agendadas<span className="sr-only">: {subtitulo}</span></> : titulo}
          </h3></TituloDialogo>
          {subtitulo && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{subtitulo}</p>}
        </div>
        {vista && <div className="flex shrink-0 gap-0.5">
          {puedeAmpliar && <button type="button" className={BOTON_ICONO} aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden className="size-4" /> : <Maximize2 aria-hidden className="size-4" />}</button>}
          <button type="button" className={BOTON_ICONO} aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden className="size-[18px]" /></button>
        </div>}
      </header>
      <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">
        {vista === null ? <div className="flex h-full flex-col items-center justify-center gap-3 px-8 py-10 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
          <Users className="size-9 text-muted-foreground" aria-hidden /><p>Elige un equipo de la tabla para ver su día.</p></div>
          : vista.tipo === 'equipo' ? equipo
            ? <FichaEquipo equipo={equipo} del={del} detalle={detalle} detalleFallido={detalleFallido} esHoy={esHoy} abrirVista={abrirVista} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona} />
            : <p role="status" className="px-5 py-4 text-[13px]">Este equipo ya no aparece en la consulta. Elige otro de la tabla.</p>
            : vista.tipo === 'sin_registro' ? <ListaSinRegistro pulso={pulso} esHoy={esHoy} abrirPersona={abrirPersona} />
              : vista.tipo === 'citas' ? <CitasOperacion key={`${vista.ambito}:${vista.clave}:${vista.apertura}`} vista={vista} dia={pulso.dia} esHoy={esHoy} actualizacion={actualizacion} revocar={revocar} />
              : <RegistroOperacion key={`${vista.alcance}:${vista.apertura}`} vista={vista} pulso={pulso} equipo={equipo} esHoy={esHoy} actualizacion={actualizacion} revocar={revocar} abrirGeneral={() => abrirVista({ tipo: 'registro', alcance: 'general', pestana: vista.pestana, apertura: vista.apertura + 1 })} />}
      </div>
    </section>
  )
}

function FichaEquipo({ equipo: e, del, detalle, detalleFallido, esHoy, abrirVista, entrarEquipo, abrirPersona }: {
  equipo: EquipoPulso; del: string; detalle: FilaEquipoPresentada[] | null; detalleFallido: boolean; esHoy: boolean
  abrirVista: (vista: VistaOperacion) => void; entrarEquipo: (clave: string, preset?: PresetEquipo) => void; abrirPersona: (analistaId: string) => void
}): JSX.Element {
  const m = e.metricas
  const atencion = detalle ? atencionEquipo(detalle, e) : null
  const barras = detalle ? barrasEquipo(detalle, e) : undefined
  const llamadas = () => abrirVista({ tipo: 'registro', alcance: e.clave, pestana: 'llamadas', apertura: Date.now() })
  return (
    <div className="space-y-5 px-5 py-4 text-[13.5px]">
      <dl className="grid grid-cols-2 gap-2.5">
        <Cuadro etiqueta="Llamadas">
          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.llamadas}</span>
          <span className="block text-xs text-[var(--muted-foreground-strong)]">{plural(m.contestadas, 'contestó', 'contestaron')}</span>
          <button type="button" onClick={llamadas} aria-label={`Ver llamadas ${del}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
        </Cuadro>
        <Cuadro etiqueta="Contacto">
          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.tasa_contacto === null ? '—' : `${Math.round(m.tasa_contacto)} %`}</span>
          <span className="block text-xs text-[var(--muted-foreground-strong)]">de {plural(m.utiles, 'llamada útil', 'llamadas útiles')}</span>
          <button type="button" onClick={llamadas} aria-label={`Ver llamadas y su resultado ${del}`} className={ENLACE}>Ver llamadas<ChevronRight aria-hidden className="size-3.5" /></button>
        </Cuadro>
        <Cuadro etiqueta="Citas agendadas">
          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{m.citas_agendadas}</span>
          <span className="block text-xs text-[var(--muted-foreground-strong)]">{esHoy ? 'hoy' : 'ese día'}</span>
          <button type="button" onClick={() => abrirVista({ tipo: 'citas', ambito: e.clave === 'fuera' ? 'fuera' : 'equipo', clave: e.clave === 'fuera' ? null : e.clave, apertura: Date.now() })}
            aria-label={`Ver citas agendadas ${del}`} className={ENLACE}>Ver citas<ChevronRight aria-hidden className="size-3.5" /></button>
        </Cuadro>
        <Cuadro etiqueta="Tareas vencidas">
          <span className={cn('block text-[28px] font-extrabold leading-tight tabular-nums', e.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{e.tareas_vencidas}</span>
          <span className="block text-xs text-[var(--muted-foreground-strong)]">siguen pendientes</span>
          <button type="button" onClick={() => entrarEquipo(e.clave, 'vencidas')} aria-label={`Ver por analista las vencidas ${del}`} className={ENLACE}>Ver por analista<ChevronRight aria-hidden className="size-3.5" /></button>
        </Cuadro>
      </dl>

      <div className="space-y-1.5">
        {barras === undefined ? detalleFallido
          ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">Las llamadas por hora no están disponibles: no se pudo consultar el detalle por analista.</p>
          : <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">Consultando las llamadas por hora…</p>
          : barras === null ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">No se pudo confirmar el desglose por hora de todos sus analistas; no se muestran ceros como sustituto.</p>
            : <>
              <BarrasPorHora porHora={barras.porHora} titulo="Llamadas por hora del equipo" apoyo={`de sus ${plural(barras.analistas, 'analista activo', 'analistas activos')}`} />
              {barras.otros > 0 && <p className="text-xs text-[var(--muted-foreground-strong)]">{plural(barras.otros, 'llamada de otros autores no está', 'llamadas de otros autores no están')} en la gráfica.</p>}
            </>}
      </div>

      <div className="space-y-2">
        <h4 className="text-[15px] font-extrabold text-primary">Necesitan atención</h4>
        {atencion === null ? detalleFallido
          ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">No disponible: no se pudo consultar el detalle por analista.</p>
          : <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">Consultando…</p>
          : atencion.length === 0 ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">Nadie del equipo necesita atención ahora.</p>
            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
            : <ul role="list" aria-label="Necesitan atención" className="space-y-1.5">
              {atencion.map((f) => {
                const a = presentarAtencion(f)
                return (
                  <li key={f.analista_id}>
                    <button type="button" onClick={() => abrirPersona(f.analista_id)}
                      className={cn('flex min-h-11 w-full cursor-pointer items-center gap-2 rounded-xl border border-border px-3.5 py-2 text-left transition-colors hover:border-border-strong hover:bg-muted/50', FOCO)}>
                      <span className="min-w-0 flex-1">
                        <span className="text-sm font-bold text-primary [overflow-wrap:anywhere]">{f.nombre_completo}</span>{' '}
                        <span className="text-[13px] font-semibold" style={{ color: a.tono === 'vencido' ? 'var(--destructive-text)' : 'var(--warning-text)' }}>{a.texto}</span>
                        {a.mas > 0 && <span className="ml-1 text-xs text-[var(--muted-foreground-strong)]">+{a.mas}</span>}
                        {a.lista.length > 1 && <span className="sr-only">: {a.lista.join('; ')}</span>}
                      </span>
                      <ChevronRight aria-hidden className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" />
                    </button>
                  </li>
                )
              })}
            </ul>}
      </div>

      <dl className="space-y-1 text-[13px]">
        <div className="flex flex-wrap gap-x-1.5"><dt className="text-[var(--muted-foreground-strong)]">Primer intento tarde:</dt>
          <dd className="font-semibold">{e.primer_intento_vencido === null ? 'seguimiento no activo' : plural(e.primer_intento_vencido, 'lead', 'leads')}</dd></div>
        <div className="flex flex-wrap gap-x-1.5"><dt className="text-[var(--muted-foreground-strong)]">Contacto entre analistas:</dt>
          <dd className="font-semibold">{e.dispersion.personas > 0 && e.dispersion.minimo !== null && e.dispersion.maximo !== null
            ? `${cifraPulso(Math.round(e.dispersion.minimo))} % a ${cifraPulso(Math.round(e.dispersion.maximo))} % (${e.dispersion.personas} con muestra)` : 'muestra insuficiente'}</dd></div>
      </dl>

      <button type="button" onClick={() => entrarEquipo(e.clave)}
        className={cn('flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-accent text-sm font-bold text-accent-foreground transition-colors hover:bg-[var(--accent-press)]', FOCO)}>
        Ver el equipo
      </button>
    </div>
  )
}

function ListaSinRegistro({ pulso, esHoy, abrirPersona }: { pulso: PulsoGerencia; esHoy: boolean; abrirPersona: (analistaId: string) => void }): JSX.Element {
  const personas = personasSinRegistro(pulso)
  return (
    <div className="space-y-3 px-5 py-4 text-[13.5px]">
      {personas.length === 0 ? <p className="text-[var(--muted-foreground-strong)]">Todos los analistas tienen registro {esHoy ? 'hoy' : 'ese día'}.</p>
        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
        : <ul role="list" aria-label="Analistas sin registro" className="space-y-1.5">
          {personas.map((p) => (
            <li key={p.analista_id}>
              <button type="button" onClick={() => abrirPersona(p.analista_id)}
                className={cn('flex min-h-11 w-full cursor-pointer items-center gap-2.5 rounded-xl border border-border px-3.5 py-2 text-left transition-colors hover:border-border-strong hover:bg-muted/50', FOCO)}>
                <Avatar nombre={p.nombre} color="var(--accent-press)" />
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-bold text-primary [overflow-wrap:anywhere]">{p.nombre}</span>
                  <span className="block text-xs text-[var(--muted-foreground-strong)]">{nombreEquipo({ fuera: p.clave === 'fuera', nombre: p.equipo })}</span>
                </span>
                <ChevronRight aria-hidden className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" />
              </button>
            </li>
          ))}
        </ul>}
      <p className="text-xs text-[var(--muted-foreground-strong)]">Sin registro significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p>
    </div>
  )
}

const FECHA_TITULO = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })

/** G4b: la lista exacta de citas agendadas del ámbito elegido; cada fila dice su analista. */
function CitasOperacion({ vista, dia, esHoy, actualizacion, revocar }: {
  vista: Extract<VistaOperacion, { tipo: 'citas' }>; dia: string; esHoy: boolean; actualizacion: number; revocar: () => void
}): JSX.Element {
  const titulo = useRef<HTMLHeadingElement>(null)
  return (
    <section aria-label="Citas seleccionadas" className="space-y-2 px-5 py-4">
      <h4 ref={titulo} tabIndex={-1} className={cn('rounded-md text-[15px] font-extrabold text-primary', FOCO)}>
        {esHoy ? 'Citas agendadas hoy' : `Citas agendadas el ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
      </h4>
      <CitasAgendadas dia={dia} esHoy={esHoy} ambito={vista.ambito} id={vista.ambito === 'equipo' ? vista.clave : null} mostrarAnalista
        visible actualizacion={actualizacion} revalidar={revocar} encabezado={titulo} />
    </section>
  )
}

function RegistroOperacion({ vista, pulso, equipo, esHoy, actualizacion, revocar, abrirGeneral }: {
  vista: Extract<VistaOperacion, { tipo: 'registro' }>; pulso: PulsoGerencia; equipo: EquipoPulso | undefined; esHoy: boolean
  actualizacion: number; revocar: () => void; abrirGeneral: () => void
}): JSX.Element {
  const tituloRegistro = useRef<HTMLHeadingElement>(null)
  // El registro del equipo lleva a todos sus autores con id (activos e inactivos); los sin autor, al general.
  const ids = equipo ? equipo.personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id]) : null
  const sinAutor = equipo?.personas.some((p) => p.analista_id === null) ?? false
  const llamadasSinAutor = equipo?.personas.reduce((n, p) => p.analista_id === null ? n + p.llamadas : n, 0) ?? 0
  return (
    // Como el registro del supervisor (Miguel, 27/09): título corto con el día,
    // filtros en pastilla y filas limpias; gerencia suma equipo y CSV en el mismo tamaño.
    <section aria-label="Registro seleccionado" className="space-y-2 px-5 py-4">
      <h4 ref={tituloRegistro} tabIndex={-1} className={cn('rounded-md text-[15px] font-extrabold text-primary', FOCO)}>
        {esHoy ? 'Actividad de hoy' : `Actividad del ${FECHA_TITULO.format(new Date(`${pulso.dia}T12:00:00-05:00`))}`}
      </h4>
      {vista.alcance === 'general'
        ? <RegistroActividad compacto encabezadoExterno={tituloRegistro} dia={pulso.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
        : ids && ids.length > 0 ? <RegistroActividad compacto encabezadoExterno={tituloRegistro} dia={pulso.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial={vista.pestana} actualizacion={actualizacion} onSinPermiso={revocar} />
          : <p className="text-[13px]">Este equipo no tiene autores con registro propio.</p>}
      {sinAutor && <p className="text-xs text-[var(--muted-foreground-strong)]">{llamadasSinAutor > 0 ? `${plural(llamadasSinAutor, 'llamada sin autor no aparece', 'llamadas sin autor no aparecen')} aquí: ` : 'Los registros sin autor se consultan en el '}
        <button type="button" className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)} onClick={abrirGeneral}>{llamadasSinAutor > 0 ? 'verlas en el registro general' : 'registro general del día'}</button>.</p>}
    </section>
  )
}
