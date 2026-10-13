// Tercera pestaña de «Toda la operación hoy» (F4-e, prototipo aprobado el 06/10): la tabla de equipos con las
// cifras de las llamadas del celular y, al lado, la ficha del equipo elegido. Misma forma que la tabla de
// «Actividad del día» (pastillas que SON los filtros, buscador, tabla semántica con `aria-sort`, filas de 52 px,
// «Toda la operación» al pie) con las columnas del celular. Cada cifra dice qué reloj usa: los rótulos viajan en la
// respuesta y se muestran tal cual. Los porcentajes se calculan aquí de cada par de la misma cohorte (D3).
// Solo lectura: no hay listas por analista para supervisión ni gerencia hasta F6.
import { useId, useRef, useState, type JSX, type ReactNode } from 'react'
import { ArrowDown, ArrowRight, ArrowUp, Check, Search, Smartphone, Users, X } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import {
  FILTROS_CELULAR, detallePendientes, detalleVias, filasEquiposCelular, filtrarOrdenarCelular, motivosAtencion, plural, porcentaje,
  type EquipoCelular, type EstadoCelular, type FilaEquipoCelular, type FiltrosCelular, type OperacionCelularHoy, type OrdenCelular,
} from '@/lib/llamadas-celular-operacion'
import { cn } from '@/lib/utils'
import { BOTON_ICONO, CABECERA_FICHA, CONTROL, FICHA, FOCO, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA, TITULO_FICHA } from './estilos-gestion'

const COLUMNAS: { orden: OrdenCelular; titulo: string; ancho: string; derecha?: boolean }[] = [
  { orden: 'nombre', titulo: 'Equipo', ancho: 'me-col-nombre' }, { orden: 'en_celular', titulo: 'En el celular', ancho: 'w-[100px]', derecha: true },
  { orden: 'con_resultado', titulo: 'Con resultado', ancho: 'w-[108px]', derecha: true }, { orden: 'al_colgar', titulo: 'Al colgar', ancho: 'w-[96px]', derecha: true },
  { orden: 'descartadas', titulo: 'Descartadas', ancho: 'w-[96px]', derecha: true }, { orden: 'sin_resultado', titulo: 'Sin resultado', ancho: 'w-[124px]', derecha: true },
  { orden: 'por_revisar', titulo: 'Por revisar', ancho: 'w-[92px]', derecha: true }, { orden: 'celulares', titulo: 'Celulares', ancho: 'w-[140px]' },
]
const PILDORAS: readonly { valor: EstadoCelular; etiqueta: string }[] = [
  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'sin_resultado', etiqueta: 'Con sin resultado' },
  { valor: 'sin_latido', etiqueta: 'Con celular sin latido' }, { valor: 'por_revisar', etiqueta: 'Con por revisar' },
]
const TITULO_ORDEN: Record<OrdenCelular, string> = {
  nombre: 'equipo', en_celular: 'llamadas en el celular', con_resultado: 'con resultado', al_colgar: 'al colgar',
  descartadas: 'descartadas', sin_resultado: 'sin resultado', por_revisar: 'por revisar', celulares: 'celulares',
}
const SUB = 'block text-[11.5px] font-normal text-[var(--muted-foreground-strong)]'
const nombreEquipo = (f: FilaEquipoCelular) => f.fuera ? f.nombre : `Equipo de ${f.nombre}`
const delEquipo = (f: FilaEquipoCelular) => f.fuera ? `del grupo ${f.nombre}` : `del Equipo de ${f.nombre}`

export function LlamadasCelularGerencia({ datos, estrecho, hora }: { datos: OperacionCelularHoy; estrecho: boolean; hora: string | null }): JSX.Element {
  const id = useId()
  const panelId = `${id}-ficha`
  const raiz = useRef<HTMLDivElement>(null)
  const [filtros, setFiltros] = useState<FiltrosCelular>(FILTROS_CELULAR)
  const [seleccion, setSeleccion] = useState<string | null>(null)
  const [anuncio, setAnuncio] = useState('')
  const filas = filasEquiposCelular(datos)
  const mostradas = filtrarOrdenarCelular(filas, filtros)
  const elegida = seleccion === null ? undefined : filas.find((f) => f.clave === seleccion)
  const conteo = (estado: EstadoCelular) => estado === 'todos' ? filas.length : filas.filter((f) => filtrarOrdenarCelular([f], { ...FILTROS_CELULAR, estado }).length > 0).length
  const ordenar = (orden: OrdenCelular) => {
    const ascendente = filtros.orden === orden ? !filtros.ascendente : orden === 'nombre'
    setFiltros((f) => ({ ...f, orden, ascendente }))
    setAnuncio(`Equipos ordenados por ${TITULO_ORDEN[orden]}, ${ascendente ? 'ascendente' : 'descendente'}.`)
  }
  const total = datos.totales
  // Cerrar la ficha devuelve el foco a la fila que la abrió (sigue montada salvo que la filtren); si no, a la tabla (a11y).
  const cerrar = () => {
    const clave = seleccion
    setSeleccion(null)
    requestAnimationFrame(() => {
      const fila = clave ? raiz.current?.querySelector<HTMLElement>(`tr[data-equipo="${CSS.escape(clave)}"] th button`) : null
      ;(fila ?? raiz.current?.querySelector<HTMLElement>('[role="region"]'))?.focus({ preventScroll: true })
    })
  }
  const irAlDetalle = () => {
    const h = document.getElementById(panelId)?.querySelector<HTMLElement>('h3')
    h?.focus({ preventScroll: true })
    h?.scrollIntoView?.({ block: 'nearest' })
  }
  return (
    <div ref={raiz} className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
      <p role="status" className="sr-only">{anuncio}</p>
      <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
        <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
          <div role="group" aria-label="Resumen de las llamadas del celular" className="flex flex-wrap items-center gap-1.5">
            {PILDORAS.map((p) => {
              const activa = filtros.estado === p.valor
              const n = conteo(p.valor)
              return (
                <button key={p.valor} type="button" aria-pressed={activa} onClick={() => setFiltros((f) => ({ ...f, busqueda: '', estado: p.valor }))}
                  className={cn(PILDORA, activa ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
                  {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
                  {p.valor !== 'todos' && n > 0
                    ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
                    : <span className="font-bold tabular-nums">{n}</span>}
                </button>
              )
            })}
          </div>
          <label className="relative ml-auto min-w-40 max-w-[220px] flex-1"><span className="sr-only">Buscar equipo</span>
            <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar equipo…"
              className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
          </label>
        </div>
        <div className="gm-orden-equipos">
          <label>Ordenar equipos<Select aria-label="Ordenar equipos" value={filtros.orden} onChange={(e) => ordenar(e.target.value as OrdenCelular)}>{COLUMNAS.map((c) => <option key={c.orden} value={c.orden}>{c.titulo}</option>)}</Select></label>
          <button type="button" className={cn(CONTROL, FOCO)} onClick={() => ordenar(filtros.orden)} aria-label={filtros.ascendente ? 'Ascendente. Cambiar a orden descendente' : 'Descendente. Cambiar a orden ascendente'}>{filtros.ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />}{filtros.ascendente ? 'Ascendente' : 'Descendente'}</button>
        </div>
        {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar con el teclado las columnas que no caben. */}
        <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-auto !overflow-x-auto focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring" tabIndex={0} role="region" aria-label="Desplazar tabla de llamadas del celular">
          <table aria-label="Llamadas del celular por equipo" className="me-tabla w-full table-fixed border-separate border-spacing-0 @min-[641px]:min-w-[960px]">
            <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
            <thead className="sticky top-0 z-[1] bg-card">
              <tr>{COLUMNAS.map((c, i) => (
                <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
                  className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS.length - 1 && 'pr-4')}>
                  <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar equipos por ${TITULO_ORDEN[c.orden]}`}
                    className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
                      c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
                    {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
                  </button>
                </th>
              ))}</tr>
            </thead>
            <tbody>
              {mostradas.length === 0 && <tr><td colSpan={COLUMNAS.length} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún equipo coincide con estos filtros.</td></tr>}
              {mostradas.map((f) => {
                const activa = f.clave === seleccion
                return (
                  <tr key={f.clave} data-equipo={f.clave} data-activa={activa}
                    className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
                    <th scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
                      <div className="flex min-h-[52px] items-center gap-2.5">
                        <Avatar nombre={f.nombre} color="var(--accent-press)" relleno={activa} />
                        <div className="min-w-0 flex-1 py-1">
                          <button type="button" aria-label={`Seleccionar ${nombreEquipo(f)}`} aria-current={activa ? 'true' : undefined} aria-controls={panelId}
                            onClick={() => { setSeleccion(f.clave); setAnuncio(`Seleccionado ${nombreEquipo(f)}. Detalle disponible.`) }}
                            className={cn('block min-h-6 max-w-full cursor-pointer rounded-md text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
                              activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{f.nombre}</button>
                          <p className={SUB}>{plural(f.equipo.analistas, 'analista', 'analistas')} · {plural(f.equipo.celulares_vigentes, 'celular', 'celulares')}{f.conAtencion > 0 && <> · <span className="font-semibold text-[var(--warning-text)]">{f.conAtencion} con atención</span></>}</p>
                        </div>
                        {activa && <button type="button" aria-label={`Ir al detalle ${delEquipo(f)}`} onClick={irAlDetalle}
                          className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
                          <ArrowRight aria-hidden className="size-4" />
                        </button>}
                      </div>
                    </th>
                    <CifrasFila e={f.equipo} />
                  </tr>
                )
              })}
            </tbody>
            <tfoot className="sticky bottom-0 z-[1] bg-muted">
              <tr className="[&>*]:border-t [&>*]:border-border">
                <th scope="row" className="py-0 pl-4 pr-2 text-left font-normal">
                  <div className="grid min-h-[52px] grid-cols-[auto_minmax(0,1fr)] content-center items-center gap-x-2.5 py-1 text-sm font-extrabold leading-snug text-primary">
                    <span aria-hidden="true" className="row-span-2 grid size-8 place-items-center rounded-full bg-card"><Users className="size-4" /></span>
                    Toda la operación
                    <p className={SUB}>{plural(datos.analistas.length, 'analista', 'analistas')} · {plural(total.celulares_vigentes, 'celular', 'celulares')}{total.analistas_sin_dato > 0 && <> · {total.analistas_sin_dato} sin dato</>}</p>
                  </div>
                </th>
                <CifrasFila e={{ ...total, analistas: datos.analistas.length }} total />
              </tr>
            </tfoot>
          </table>
        </div>
        <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
          <p><span role="status">{mostradas.length} de {filas.length} equipos</span>{hora && <> · Actualizado {hora}</>}</p>
          <p>Cuenta llamadas a leads detectadas por el celular. No se suma a la cifra del día de «Actividad del día».</p>
        </div>
      </div>
      <FichaEquipoCelular id={panelId} fila={elegida} rotulos={datos.rotulos} cerrar={cerrar} />
    </div>
  )
}

/** «—» en lugar de una cifra (D1: el celular no dio señal), con su frase para el lector de pantalla. */
export const SinDato = (): JSX.Element => <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin dato del celular</span></>

/** Las siete cifras de una fila: las mismas para cada equipo y para «Toda la operación». «—» = sin dato de todos. */
function CifrasFila({ e, total = false }: { e: Omit<EquipoCelular, 'supervisor_id' | 'supervisor_nombre'>; total?: boolean }): JSX.Element {
  const sinDato = e.llamadas_hoy.total === 0 && e.analistas > 0 && e.analistas_sin_dato === e.analistas
  const celda = cn('px-2 text-right text-sm tabular-nums', total ? 'font-extrabold text-primary' : 'font-semibold text-foreground')
  const pct = porcentaje(e.llamadas_hoy.con_resultado, e.llamadas_hoy.total)
  const pendientes = detallePendientes(e.pendientes, false)
  return <>
    <td data-etiqueta="En el celular" className={celda}>{sinDato ? <SinDato /> : e.llamadas_hoy.total}</td>
    <td data-etiqueta="Con resultado" className={celda}>{sinDato ? <SinDato /> : e.llamadas_hoy.con_resultado}{pct !== null && <span className={SUB}>{pct} %</span>}</td>
    <td data-etiqueta="Al colgar" className={celda}>{e.resultados_hoy.al_colgar}{e.resultados_hoy.total > 0 && <span className={SUB}>de {e.resultados_hoy.total}</span>}</td>
    <td data-etiqueta="Descartadas" className={celda}>{e.llamadas_hoy.descartadas}</td>
    <td data-etiqueta="Sin resultado" className={cn(celda, e.pendientes.total > 0 && 'text-[var(--warning-text)]')}>{e.pendientes.total}{pendientes && <span className={SUB}>{pendientes}</span>}</td>
    <td data-etiqueta="Por revisar" className={celda}>{e.por_revisar}</td>
    <td data-etiqueta="Celulares" className={cn('px-2 pr-4 text-sm tabular-nums', total ? 'font-extrabold text-primary' : 'font-semibold text-foreground')}>
      {e.celulares_vigentes}
      <span className={cn(SUB, e.celulares_sin_latido > 0 && 'font-semibold text-[var(--warning-text)]')}>
        {e.celulares_vigentes === 0 ? 'sin celular' : e.celulares_sin_latido > 0 ? `${e.celulares_sin_latido} sin latido` : 'al día'}
      </span>
    </td>
  </>
}

function Cuadro({ etiqueta, valor, nota, alerta = false }: { etiqueta: string; valor: ReactNode; nota: ReactNode; alerta?: boolean }): JSX.Element {
  return (
    <div className="min-w-0 rounded-xl bg-muted/70 px-3.5 py-3">
      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
      <dd className="mt-1 min-w-0">
        <span className={cn('block text-[28px] font-extrabold leading-[1.1] tabular-nums', alerta ? 'text-[var(--warning-text)]' : 'text-primary')}>{valor}</span>
        {nota && <span className="mt-0.5 block text-xs text-[var(--muted-foreground-strong)]">{nota}</span>}
      </dd>
    </div>
  )
}

function FichaEquipoCelular({ id, fila: f, rotulos, cerrar }: { id: string; fila: FilaEquipoCelular | undefined; rotulos: OperacionCelularHoy['rotulos']; cerrar: () => void }): JSX.Element {
  const e = f?.equipo
  const sinDato = e !== undefined && e.llamadas_hoy.total === 0 && e.analistas > 0 && e.analistas_sin_dato === e.analistas
  const pct = e ? porcentaje(e.llamadas_hoy.con_resultado, e.llamadas_hoy.total) : null
  const atencion = f ? f.analistas.map((a) => ({ a, motivos: motivosAtencion(a) })).filter((x) => x.motivos.length > 0) : []
  return (
    <section id={id} aria-label={f ? `Detalle ${delEquipo(f)}` : 'Llamadas del celular'} className={cn(FICHA, 'me-panel-alojamiento')}>
      <header className={CABECERA_FICHA}>
        {f ? <Avatar nombre={f.nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
          : <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary"><Smartphone className="size-4" /></span>}
        <div className="min-w-0 flex-1">
          <h3 tabIndex={-1} className={TITULO_FICHA}>{f ? <><span className="sr-only">{f.fuera ? 'Detalle del grupo' : 'Detalle del Equipo de'}</span>{' '}{f.nombre}</> : 'Llamadas del celular'}</h3>
          {f && e && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">{f.fuera ? '' : 'Equipo de '}{plural(e.analistas, 'analista', 'analistas')} · {plural(e.celulares_vigentes, 'celular', 'celulares')}</p>}
        </div>
        {f && <button type="button" className={BOTON_ICONO} aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden className="size-[18px]" /></button>}
      </header>
      <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">
        {!f || !e ? <div className="flex h-full flex-col items-center justify-center gap-3 px-8 py-10 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
          <Users className="size-9 text-muted-foreground" aria-hidden /><p>Elige un equipo de la tabla para ver sus llamadas del celular.</p></div>
          : <div className="space-y-5 px-5 py-4 [overflow-wrap:anywhere]">
            <dl className="grid grid-cols-2 gap-2.5">
              <Cuadro etiqueta="En el celular" valor={sinDato ? <SinDato /> : e.llamadas_hoy.total} nota={sinDato ? 'ningún celular dio señal' : 'llamadas a leads detectadas hoy'} />
              <Cuadro etiqueta="Con resultado" valor={sinDato ? <SinDato /> : e.llamadas_hoy.con_resultado} nota={sinDato ? 'ningún celular dio señal' : pct === null ? 'de las llamadas de hoy' : `${pct} % de las de hoy`} />
              <Cuadro etiqueta="Resultados hoy" valor={e.resultados_hoy.total} nota={detalleVias(e.resultados_hoy) || 'de llamadas de cualquier día'} />
              <Cuadro etiqueta="Sin resultado" valor={e.pendientes.total} nota={detallePendientes(e.pendientes) || 'ninguna espera resultado'} alerta={e.pendientes.total > 0} />
              <Cuadro etiqueta="Celulares" valor={e.celulares_vigentes} nota={e.celulares_vigentes === 0 ? 'sin celular asignado' : e.celulares_sin_latido > 0 ? `${plural(e.celulares_sin_latido, 'sin latido', 'sin latido')}` : 'todos al día'} alerta={e.celulares_sin_latido > 0} />
              <Cuadro etiqueta="Por revisar" valor={e.por_revisar} nota={e.por_revisar > 0 ? 'ambiguas o de la bolsa' : 'nada por revisar'} />
            </dl>
            <div className="space-y-2">
              <h4 className="text-[13px] font-extrabold text-primary">Necesitan atención</h4>
              {atencion.length === 0 ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">Nadie: todas las llamadas de hoy tienen resultado y los celulares están al día.</p>
                : <ul aria-label="Analistas que necesitan atención" className="space-y-1.5">
                  {atencion.map(({ a, motivos }) => <li key={a.analista_id} className="rounded-xl border border-border bg-card px-3.5 py-2 text-[13px]">
                    <span className="font-bold text-primary">{a.nombre}</span><span className="block text-[12px] text-[var(--muted-foreground-strong)]">{motivos.join(' · ')}</span>
                  </li>)}
                </ul>}
            </div>
            <dl className="space-y-1 text-[12.5px] text-[var(--muted-foreground-strong)]">
              {e.llamadas_hoy.deshechas_sin_corregir > 0 && <div className="flex gap-1"><dt className="font-semibold">Deshechas sin corregir hoy:</dt><dd>{e.llamadas_hoy.deshechas_sin_corregir}</dd></div>}
              {e.llamadas_hoy.cerradas_despues > 0 && <div className="flex gap-1"><dt className="font-semibold">Ya no piden resultado:</dt><dd>{e.llamadas_hoy.cerradas_despues} (el lead se cerró después)</dd></div>}
              {e.llamadas_hoy.descartadas > 0 && <div className="flex gap-1"><dt className="font-semibold">Descartadas hoy:</dt><dd>{e.llamadas_hoy.descartadas}</dd></div>}
              {e.analistas_sin_dato > 0 && <div className="flex gap-1"><dt className="font-semibold">Sin dato del celular:</dt><dd>{plural(e.analistas_sin_dato, 'analista', 'analistas')}</dd></div>}
            </dl>
            <p className="text-[11.5px] leading-relaxed text-[var(--muted-foreground-strong)]">
              <span className="font-semibold">En el celular:</span> {rotulos.llamadas_hoy}. <span className="font-semibold">Resultados hoy:</span> {rotulos.resultados_hoy}. <span className="font-semibold">Sin resultado:</span> {rotulos.pendientes}.
            </p>
          </div>}
      </div>
    </section>
  )
}
