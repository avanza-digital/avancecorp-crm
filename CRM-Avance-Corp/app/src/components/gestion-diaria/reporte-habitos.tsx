/* oxlint-disable jsx-a11y/no-redundant-roles, jsx-a11y/no-interactive-element-to-noninteractive-role -- Conserva la semántica de tabla en WebKit al apilar celdas. */
/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar las columnas con el teclado. */
// «Hábitos del equipo» con el diseño de Gestión Diaria (G3, 27/09/2026): la misma
// forma que «Actividad del día» y que el supervisor —herramientas arriba, tabla
// protagonista con cabeceras que ordenan, pie con el alcance y ficha al lado con
// borde azul que pasa a ventana por debajo de 1040 px— sin perder nada de lo que
// ya daba: período, búsqueda, equipo, orden, ficha día a día, «Ver pulso y
// registro» y «Cómo leer los hábitos».
import { useId, useRef, useState, type JSX, type ReactNode } from 'react'
import { Title as TituloDialogo } from '@radix-ui/react-dialog'
import { ArrowDown, ArrowRight, ArrowUp, ChevronRight, Info, Maximize2, Minimize2, Search, Users, X } from 'lucide-react'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { cifraPulso, type EquipoPulso } from '@/lib/gestion-diaria-pulso'
import type { HabitosGerencia, PersonaHabitos } from '@/lib/gestion-diaria-habitos'
import { hashDe } from '@/lib/router'
import { cn } from '@/lib/utils'
import { Avatar } from '@/components/ui/avatar'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog, DialogHeader, DialogTitle, DialogBody } from '@/components/ui/dialog'
import { PanelSupervisorAdaptable } from './panel-supervisor-adaptable'
import { BOTON_CABECERA, BOTON_ICONO, CABECERA_FICHA, CONTROL, FICHA, FOCO, TITULO_FICHA } from './estilos-gestion'

const ESTADO_CORTE = { pendiente: 'Aún pendiente', sin_cartera: 'Sin cartera', cumplido: 'A tiempo', recuperado: 'Recuperado', incumplido: 'Incumplido' } as const
function cortesDelDia(d: PersonaHabitos['dias'][number]) {
  if (d.cortes.estado !== 'activo') return d.cortes.estado === 'no_laborable' ? 'No laborable' : 'Desactivados'
  return [d.cortes.primer_corte, d.cortes.segundo_corte].filter((c) => c !== null).map((c, i) => `${i + 1}. ${ESTADO_CORTE[c.estado]}`).join(' · ') || 'Sin cortes programados'
}

type Orden = 'nombre' | 'llamadas' | 'contacto' | 'mediana' | 'cortes'
const COLUMNAS: { orden: Orden; titulo: string; ancho: string; derecha?: boolean }[] = [
  { orden: 'nombre', titulo: 'Analista', ancho: 'me-col-nombre' }, { orden: 'llamadas', titulo: 'Llamadas', ancho: 'w-[84px]', derecha: true },
  { orden: 'contacto', titulo: 'Contacto', ancho: 'w-[104px]', derecha: true }, { orden: 'mediana', titulo: 'Mediana diaria', ancho: 'w-[124px]', derecha: true },
  { orden: 'cortes', titulo: 'Cortes a tiempo', ancho: 'w-[132px]', derecha: true },
]
function valor(p: PersonaHabitos, orden: Exclude<Orden, 'nombre'>) {
  switch (orden) {
    case 'llamadas': return p.resumen.llamadas
    case 'contacto': return p.resumen.tasa_contacto
    case 'mediana': return p.distribucion_contacto.mediana
    case 'cortes': return p.cumplimiento.evaluables ? p.cumplimiento.cumplidos_a_tiempo / p.cumplimiento.evaluables : null
  }
}
const FECHA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
const fecha = (dia: string) => FECHA.format(new Date(`${dia}T12:00:00-05:00`))
const APOYO = 'block text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]'

export function ReporteHabitos({ datos, equipos, estrecho, periodo, alAbrirAnalista }: {
  datos: HabitosGerencia
  equipos: EquipoPulso[]
  /** Contenedor de la operación por debajo de 1040 px: la ficha pasa a ventana. */
  estrecho: boolean
  /** El selector de período: vive en la pantalla (su consulta), se muestra en la barra de la tabla. */
  periodo: ReactNode
  alAbrirAnalista: () => void
}): JSX.Element {
  const [busqueda, setBusqueda] = useState('')
  const [equipo, setEquipo] = useState('todos')
  const [orden, setOrden] = useState<Orden>('nombre')
  const [ascendente, setAscendente] = useState(true)
  const [seleccion, setSeleccion] = useState<string | null>(null)
  const [ampliado, setAmpliado] = useState(false)
  const [info, setInfo] = useState(false)
  const titulo = useRef<HTMLHeadingElement>(null)
  const tabla = useRef<HTMLDivElement>(null)
  const origen = useRef<HTMLElement | null>(null)
  const id = useId()
  const equipoDe = (p: PersonaHabitos) => p.supervisor_id === null ? 'sin-equipo' : equipos.some((e) => e.supervisor_id === p.supervisor_id) ? p.supervisor_id : 'desconocido'
  const nombreEquipo = (p: PersonaHabitos) => {
    if (p.supervisor_id === null) return 'Sin equipo asignado'
    const e = equipos.find((x) => x.supervisor_id === p.supervisor_id)
    return e ? `Equipo de ${e.nombre}` : 'Equipo no disponible'
  }
  const opciones = [...new Set(datos.personas.map(equipoDe))].map((clave) => ({ clave, nombre: nombreEquipo(datos.personas.find((p) => equipoDe(p) === clave)!) }))
  const filas = datos.personas.filter((p) => p.nombre_completo.toLocaleLowerCase('es').includes(busqueda.trim().toLocaleLowerCase('es')) && (equipo === 'todos' || equipoDe(p) === equipo))
    .toSorted((a, b) => {
      const nombre = a.nombre_completo.localeCompare(b.nombre_completo, 'es')
      if (orden === 'nombre') return nombre * (ascendente ? 1 : -1)
      const va = valor(a, orden), vb = valor(b, orden)
      if (va === null || vb === null) return va === vb ? nombre : va === null ? 1 : -1
      return (va - vb) * (ascendente ? 1 : -1) || nombre
    })
  const persona = datos.personas.find((p) => p.analista_id === seleccion)
  const cerrar = () => {
    setSeleccion(null); setAmpliado(false)
    requestAnimationFrame(() => {
      const destino = origen.current?.isConnected ? origen.current : tabla.current
      destino?.focus({ preventScroll: true })
      if (document.activeElement !== destino) tabla.current?.focus({ preventScroll: true })
    })
  }
  const op = datos.operacion
  return <section aria-label="Reporte de hábitos" className="flex min-h-0 flex-1 flex-col">
    <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
      <section aria-label="Comparación de hábitos" className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
        <h3 className="sr-only">Hábitos por analista</h3>
        <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
          {periodo}
          <div className="w-[180px] max-w-full">
            <Select aria-label="Equipo en hábitos" className={cn(CONTROL, 'min-h-0')} value={equipo} onChange={(e) => setEquipo(e.target.value)}>
              <option value="todos">Todos los equipos</option>{opciones.map((e) => <option key={e.clave} value={e.clave}>{e.nombre}</option>)}
            </Select>
          </div>
          <button type="button" className={BOTON_CABECERA} onClick={() => setInfo(true)}><Info aria-hidden className="size-4" />Cómo leer los hábitos</button>
          <label className="relative ml-auto min-w-40 max-w-[220px] flex-1">
            <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input type="search" aria-label="Buscar analista en hábitos" placeholder="Buscar analista…" value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
              className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
          </label>
        </div>
        {persona && !filas.includes(persona) && <p className="shrink-0 bg-muted px-4 py-1.5 text-[13px]">La selección no aparece con los filtros actuales.</p>}
        <div ref={tabla} className={cn('gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-auto focus-visible:!-outline-offset-2', FOCO)} tabIndex={0} role="region" aria-label="Desplazar tabla de hábitos">
          <table role="table" aria-label="Comparación de hábitos por analista" className="me-tabla w-full table-fixed border-separate border-spacing-0 @min-[641px]:min-w-[620px]">
            <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
            <thead role="rowgroup" className="sticky top-0 z-[1] bg-card">
              <tr role="row">{COLUMNAS.map((c, i) => (
                <th role="columnheader" scope="col" key={c.orden} aria-sort={orden === c.orden ? ascendente ? 'ascending' : 'descending' : 'none'}
                  className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS.length - 1 && 'pr-4')}>
                  <button type="button" onClick={() => { setOrden(c.orden); setAscendente(orden === c.orden ? !ascendente : c.orden === 'nombre') }} aria-label={`Ordenar hábitos por ${c.titulo.toLocaleLowerCase('es')}`}
                    className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
                      c.derecha && 'justify-end', orden === c.orden && 'text-primary')}>
                    {c.titulo}{orden === c.orden && (ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
                  </button>
                </th>
              ))}</tr>
            </thead>
            <tbody role="rowgroup">
              {filas.length === 0 && <tr role="row"><td role="cell" colSpan={COLUMNAS.length} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">
                {datos.personas.length ? 'Ningún analista coincide con estos filtros.' : 'No hay analistas activos en el organigrama actual.'}</td></tr>}
              {filas.map((p) => {
                const activa = seleccion === p.analista_id
                return (
                  <tr role="row" key={p.analista_id} data-activa={activa}
                    className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
                    <th role="rowheader" scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
                      <div className="flex min-h-[52px] items-center gap-2.5">
                        <Avatar nombre={p.nombre_completo} color="var(--accent-press)" relleno={activa} />
                        <div className="min-w-0 flex-1 py-1">
                          <button type="button" aria-label={`Ver hábitos de ${p.nombre_completo}`} aria-controls={id} aria-current={activa ? 'true' : undefined}
                            onClick={(e) => { origen.current = e.currentTarget; setSeleccion(p.analista_id) }}
                            className={cn('block max-w-full cursor-pointer rounded-md text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
                              activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{p.nombre_completo}</button>
                          <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">{nombreEquipo(p)}</p>
                        </div>
                        {activa && <button type="button" aria-label={`Ir al detalle de hábitos de ${p.nombre_completo}`} onClick={() => titulo.current?.focus()}
                          className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
                          <ArrowRight aria-hidden className="size-4" />
                        </button>}
                      </div>
                    </th>
                    <td role="cell" data-etiqueta="Llamadas" className="px-2 text-right text-sm font-semibold tabular-nums text-foreground">{p.resumen.llamadas}</td>
                    <td role="cell" data-etiqueta="Contacto" className="px-2 text-right">
                      <span className="block text-sm font-bold tabular-nums text-foreground">{cifraPulso(p.resumen.tasa_contacto, true)}</span>
                      <span className={APOYO}>{p.resumen.contestadas}/{p.resumen.utiles} útiles</span>
                    </td>
                    <td role="cell" data-etiqueta="Mediana diaria" className="px-2 text-right">
                      <span className="block text-sm tabular-nums text-foreground">{cifraPulso(p.distribucion_contacto.mediana, true)}</span>
                      <span className={APOYO}>{p.distribucion_contacto.dias_validos} días con muestra</span>
                    </td>
                    <td role="cell" data-etiqueta="Cortes a tiempo" className="py-2 pl-2 pr-4 text-right text-sm tabular-nums text-foreground">
                      {p.cumplimiento.evaluables ? `${p.cumplimiento.cumplidos_a_tiempo} de ${p.cumplimiento.evaluables}` : <span className="text-[12.5px] text-[var(--muted-foreground-strong)]">Sin cortes evaluables</span>}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        {/* El pie del supervisor: cuántos se ven, el período y la cifra de toda la operación. */}
        <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
          <p><span role="status">{filas.length} de {datos.personas.length} analistas</span> · Del {fecha(datos.desde)} al {fecha(datos.hasta)}, {datos.dias_incluidos} días calendario{datos.dias_incluidos < datos.dias_solicitados ? ' (histórico disponible)' : ''}</p>
          <p>Contacto de la operación: <strong className="font-bold text-foreground">{cifraPulso(op.tasa_contacto, true)}</strong> · {op.contestadas} de {op.utiles} útiles</p>
        </div>
      </section>
      <PanelSupervisorAdaptable modal={Boolean(persona) && (estrecho || ampliado)} cerrar={cerrar} tituloRef={titulo}
        claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
        <section id={id} aria-label="Detalle de hábitos" className={FICHA}>
          <header className={CABECERA_FICHA}>
            {persona ? <Avatar nombre={persona.nombre_completo} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
              : <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary"><Users className="size-4" /></span>}
            <div className="min-w-0 flex-1">
              {/* El diálogo se nombra por este título: solo el nombre de la persona. */}
              <TituloDialogo asChild><h3 ref={titulo} tabIndex={-1} className={TITULO_FICHA}>{persona?.nombre_completo ?? 'Detalle de hábitos'}</h3></TituloDialogo>
              {persona && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{nombreEquipo(persona)}</p>}
            </div>
            {persona && <div className="flex shrink-0 gap-0.5">
              {!estrecho && <button type="button" className={BOTON_ICONO} aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={() => setAmpliado((v) => !v)}>
                {ampliado ? <Minimize2 aria-hidden className="size-4" /> : <Maximize2 aria-hidden className="size-4" />}</button>}
              <button type="button" className={BOTON_ICONO} aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden className="size-[18px]" /></button>
            </div>}
          </header>
          {persona
            ? <div className="me-equipo ac-scroll min-h-0 flex-1 overflow-y-auto"><DetalleHabitos key={persona.analista_id} persona={persona} alAbrirAnalista={alAbrirAnalista} /></div>
            : <div className="flex flex-1 flex-col items-center justify-center gap-3 px-8 py-10 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
              <Users className="size-9 text-muted-foreground" aria-hidden /><p>Elige un analista para ver sus hábitos día a día y compararlos con su equipo.</p></div>}
        </section>
      </PanelSupervisorAdaptable>
    </div>
    <Dialog open={info} onClose={() => setInfo(false)} className="w-[600px]"><DialogHeader><DialogTitle>Cómo leer los hábitos</DialogTitle></DialogHeader><DialogBody><div className="space-y-3 text-[13.5px] leading-relaxed">
      <p>Equipo y cartera de referencia actuales. Los cortes usan la política vigente en cada fecha.</p>
      <p>Estos datos orientan la capacitación; no explican las causas de una pausa.</p>
      <p>La alerta de tasa muy baja sigue apagada. No se ha fijado un umbral.</p>
      <p>La tasa de contacto reúne contestadas y útiles del período; no promedia los porcentajes diarios. La mediana y la mitad central usan sólo días con muestra suficiente.</p>
      <p>Los cortes se ordenan por la proporción cumplida a tiempo entre los evaluables. Los pendientes y sin cartera se muestran en el detalle.</p>
      <button type="button" className={BOTON_CABECERA} onClick={() => setInfo(false)}>Cerrar explicación</button>
    </div></DialogBody></Dialog>
  </section>
}

function Cuadro({ etiqueta, children }: { etiqueta: string; children: ReactNode }): JSX.Element {
  return (
    <div className="min-w-0 rounded-xl bg-muted/70 px-3.5 py-3">
      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
      <dd className="mt-1 min-w-0">{children}</dd>
    </div>
  )
}
const CIFRA = 'block text-[26px] font-extrabold leading-tight tabular-nums text-primary'
const CIFRA_TEXTO = 'block text-[17px] font-extrabold leading-snug text-primary'
const CELDA = 'border-b border-border px-2 py-2 align-top'

/** La ficha de hábitos de una persona: como la del analista en el supervisor, cuadros y detalle día a día. */
function DetalleHabitos({ persona: p, alAbrirAnalista }: { persona: PersonaHabitos; alAbrirAnalista: () => void }): JSX.Element {
  const c = p.cumplimiento
  return <article className="space-y-5 px-5 py-4 text-[13.5px] [overflow-wrap:anywhere]">
    <p className="text-[13px] text-[var(--muted-foreground-strong)]">{p.resumen.llamadas} llamadas en el período</p>
    <dl className="grid grid-cols-2 gap-2.5">
      <Cuadro etiqueta="Contacto personal">
        <span className={CIFRA}>{cifraPulso(p.resumen.tasa_contacto, true)}</span>
        <span className={APOYO}>{p.resumen.contestadas} de {p.resumen.utiles} útiles</span>
      </Cuadro>
      <Cuadro etiqueta="Contacto del equipo">
        <span className={CIFRA}>{cifraPulso(p.equipo.tasa_contacto, true)}</span>
        <span className={APOYO}>{p.equipo.utiles === null ? 'Sin equipo comercial asignado' : `${p.equipo.contestadas} de ${p.equipo.utiles} útiles`}</span>
      </Cuadro>
      <Cuadro etiqueta="Distribución diaria">
        <span className={CIFRA_TEXTO}>{p.distribucion_contacto.dias_validos ? `Mediana ${cifraPulso(p.distribucion_contacto.mediana, true)}` : 'Muestra insuficiente'}</span>
        <span className={APOYO}>{p.distribucion_contacto.dias_validos} días con muestra suficiente</span>
        {p.distribucion_contacto.dias_validos > 0 && <span className={APOYO}>Mitad central: {cifraPulso(p.distribucion_contacto.p25, true)} a {cifraPulso(p.distribucion_contacto.p75, true)}</span>}
      </Cuadro>
      <Cuadro etiqueta="Cortes a tiempo">
        <span className={c.evaluables ? CIFRA : CIFRA_TEXTO}>{c.evaluables ? `${c.cumplidos_a_tiempo} de ${c.evaluables}` : 'Sin cortes evaluables'}</span>
        <span className={APOYO}>{c.recuperados} recuperados · {c.incumplidos} incumplidos</span>
        <span className={APOYO}>{c.pendientes} pendientes · {c.sin_cartera} sin cartera</span>
      </Cuadro>
    </dl>
    <a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: p.analista_id })}
      onClick={(e) => { if (!e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey) alAbrirAnalista() }}
      className={cn('flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-accent text-sm font-bold text-accent-foreground transition-colors hover:bg-[var(--accent-press)]', FOCO)}>
      Ver pulso y registro
    </a>
    <details className="group">
      <summary className={cn('flex min-h-11 cursor-pointer list-none items-center gap-1 rounded-md text-[15px] font-extrabold text-primary [&::-webkit-details-marker]:hidden', FOCO)}>
        <ChevronRight aria-hidden className="size-4 shrink-0 transition-transform group-open:rotate-90" />Ver días de {p.nombre_completo}
      </summary>
      {/* En la ficha (≤ 640 px) cada día es una tarjeta con rótulos, como las tablas del diseño; ampliada, una tabla. */}
      <table role="table" aria-label={`Hábitos diarios de ${p.nombre_completo}`} className="me-tabla gp-dias-habitos mt-2 w-full border-separate border-spacing-0 text-[13px]">
        <thead role="rowgroup"><tr role="row" className="text-left text-[12.5px] text-[var(--muted-foreground-strong)]">
          <th role="columnheader" scope="col" className={cn(CELDA, 'pl-0 font-semibold')}>Día</th><th role="columnheader" scope="col" className={cn(CELDA, 'font-semibold')}>Primera llamada</th>
          <th role="columnheader" scope="col" className={cn(CELDA, 'font-semibold')}>Mayor hueco entre llamadas</th><th role="columnheader" scope="col" className={cn(CELDA, 'font-semibold')}>Contacto</th>
          <th role="columnheader" scope="col" className={cn(CELDA, 'pr-0 font-semibold')}>Cortes</th>
        </tr></thead>
        <tbody role="rowgroup">{p.dias.map((d) => <tr role="row" key={d.dia}>
          <th role="rowheader" scope="row" className={cn(CELDA, 'pl-0 text-left font-bold tabular-nums text-primary')}>{d.dia}</th>
          <td role="cell" data-etiqueta="Primera llamada" className={cn(CELDA, 'tabular-nums')}>{horaLimaDe(d.primera_llamada_en)}{d.llamadas === 0 && <span className={APOYO}>Sin llamadas</span>}</td>
          <td role="cell" data-etiqueta="Mayor hueco" className={CELDA}>{d.jornada.estado === 'no_laborable' ? 'No laborable' : d.jornada.hueco
            ? <><span className="tabular-nums">{cifraPulso(d.jornada.hueco.minutos)} min</span><span className={APOYO}>{horaLimaDe(d.jornada.hueco.desde)}–{horaLimaDe(d.jornada.hueco.hasta)}</span></>
            : d.jornada.estado === 'no_iniciada' ? 'Jornada sin iniciar' : 'Menos de dos llamadas en jornada'}
            {d.jornada.estado !== 'no_laborable' && d.jornada.estado !== 'no_iniciada' && <span className={APOYO}>Desde apertura: {cifraPulso(d.jornada.silencio_inicio_minutos)} min · hasta {horaLimaDe(d.jornada.observado_hasta)}: {cifraPulso(d.jornada.silencio_final_minutos)} min</span>}</td>
          <td role="cell" data-etiqueta="Contacto" className={cn(CELDA, 'tabular-nums')}>{cifraPulso(d.tasa_contacto, true)}<span className={APOYO}>{d.contestadas} de {d.utiles} útiles{d.utiles < d.minimo_llamadas_utiles ? ` · muestra insuficiente (mín. ${d.minimo_llamadas_utiles})` : ''}</span></td>
          <td role="cell" data-etiqueta="Cortes" className={cn(CELDA, 'pr-0')}>{cortesDelDia(d)}</td>
        </tr>)}</tbody>
      </table>
      <p className="mt-3 text-xs leading-relaxed text-[var(--muted-foreground-strong)]">Hora de Lima. El hueco requiere dos llamadas dentro de la jornada: 09–18 h; sábado 09–13 h. Los silencios de apertura y cierre se muestran aparte; el día en curso llega hasta la consulta.</p>
    </details>
  </article>
}
