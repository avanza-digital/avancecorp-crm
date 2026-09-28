/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar con el teclado las columnas que no caben. */
// Tabla de equipos de «Toda la operación» (diseño de Gestión Diaria, 27/09/2026):
// la protagonista. Misma forma que la del supervisor —pastillas que SON los
// filtros, buscador a la derecha, tabla semántica con `aria-sort`, filas de 52 px,
// botón de selección e «Ir al detalle»— y conserva la comparación de gerencia:
// primer intento, dispersión y, al pie, «Toda la operación» con las cifras que
// antes iban en una franja aparte (Miguel, 27/09: «que quede como lo ve el
// supervisor»). Cada número abre su lista: el número es la lista.
import type { JSX } from 'react'
import { ArrowDown, ArrowRight, ArrowUp, Check, Search, Users } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { COLOR_NIVEL, ETIQUETA_NIVEL, type UmbralesSchema } from '@/lib/gestion-diaria-analista'
import type * as v from 'valibot'
import { Input } from '@/components/ui/input'
import { cifraPulso } from '@/lib/gestion-diaria-pulso'
import { nivelEquipo, nombreEquipo, type EstadoOperacion, type FilaEquipoOperacion, type FiltrosOperacion, type OrdenOperacion } from '@/lib/gestion-diaria-operacion'
import { cn } from '@/lib/utils'
import { CONTROL, FOCO, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from './estilos-gestion'

export type AccionEquipo = 'sin_registro' | 'vencidas' | 'atencion' | 'citas' | 'llamadas'

const COLUMNAS: { orden: OrdenOperacion; titulo: string; ancho: string; derecha?: boolean }[] = [
  { orden: 'nombre', titulo: 'Equipo', ancho: 'me-col-nombre' }, { orden: 'llamadas', titulo: 'Llamadas', ancho: 'w-[72px]', derecha: true },
  { orden: 'contacto', titulo: 'Contacto', ancho: 'w-[96px]', derecha: true }, { orden: 'citas', titulo: 'Citas', ancho: 'w-[56px]', derecha: true },
  { orden: 'vencidas', titulo: 'Vencidas', ancho: 'w-[72px]', derecha: true }, { orden: 'atencion', titulo: 'Atención', ancho: 'w-[116px]' },
  { orden: 'primer_intento', titulo: 'Primer intento', ancho: 'w-[96px]', derecha: true }, { orden: 'dispersion', titulo: 'Dispersión', ancho: 'w-[104px]', derecha: true },
]
const PILDORAS: readonly { valor: EstadoOperacion; etiqueta: string }[] = [
  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'atencion', etiqueta: 'Con atención' }, { valor: 'vencidas', etiqueta: 'Con vencidas' },
]

const ENLACE_CIFRA = cn('cursor-pointer rounded-md font-semibold tabular-nums underline-offset-2 hover:underline pointer-coarse:min-h-11', FOCO)

export function TablaEquiposGerencia({ filas, total, conteos, sinDetalle = 'cargando', umbrales = null, filtros, setFiltros, ordenar, seleccion, seleccionar, accion, totalOperacion, accionTotal, panelId, irAlDetalle }: {
  /** Ya filtradas y ordenadas. */
  filas: FilaEquipoOperacion[]
  total: number
  /** Equipos de cada pastilla; «Con atención» es null sin detalle. */
  conteos: { atencion: number | null; vencidas: number }
  /** Por qué falta el detalle: mientras llega se dice «…»; si falló, «—» y «No disponible». */
  sinDetalle?: 'cargando' | 'error'
  /** Umbrales del servidor para el nivel de contacto (llegan con el detalle). */
  umbrales?: v.InferOutput<typeof UmbralesSchema> | null
  filtros: FiltrosOperacion
  setFiltros: (cambio: (f: FiltrosOperacion) => FiltrosOperacion) => void
  ordenar: (orden: OrdenOperacion) => void
  seleccion: string | null
  seleccionar: (fila: FilaEquipoOperacion, origen: HTMLElement) => void
  accion: (fila: FilaEquipoOperacion, tipo: AccionEquipo, origen: HTMLElement) => void
  /** La fila del pie: las cifras de toda la operación, con sus propias listas. */
  totalOperacion: FilaEquipoOperacion
  accionTotal: (tipo: AccionEquipo, origen: HTMLElement) => void
  panelId: string
  irAlDetalle: () => void
}): JSX.Element {
  const conteo = (p: EstadoOperacion) => p === 'todos' ? total : p === 'vencidas' ? conteos.vencidas : conteos.atencion
  return <>
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
      <div role="group" aria-label="Resumen de la operación" className="flex flex-wrap items-center gap-1.5">
        {PILDORAS.map((p) => {
          const activa = filtros.estado === p.valor
          const n = conteo(p.valor)
          return (
            // Cada cifra es de la operación entera: abrirla limpia la búsqueda (Codex, 27/09).
            <button key={p.valor} type="button" aria-pressed={activa} onClick={() => setFiltros((f) => ({ ...f, busqueda: '', estado: p.valor }))}
              className={cn(PILDORA, activa ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
              {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
              {p.valor === 'atencion' && n !== null && n > 0
                // Ámbar y no rojo, como «Necesitan atención» del supervisor.
                ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
                : <span className="font-bold tabular-nums">{n ?? (sinDetalle === 'error' ? '—' : '…')}</span>}
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
    {/* Las dos últimas columnas desplazan dentro de la tabla, no la página. */}
    <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-auto !overflow-x-auto" tabIndex={0} role="region" aria-label="Desplazar tabla de equipos">
      <table aria-label="Equipos de la operación" className="me-tabla w-full table-fixed border-separate border-spacing-0 @min-[641px]:min-w-[860px]">
        <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
        <thead className="sticky top-0 z-[1] bg-card">
          <tr>{COLUMNAS.map((c, i) => (
            <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS.length - 1 && 'pr-4')}>
              <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar equipos por ${c.titulo.toLocaleLowerCase('es')}`}
                className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
                  c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
                {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
              </button>
            </th>
          ))}</tr>
        </thead>
        <tbody>
          {filas.length === 0 && <tr><td colSpan={COLUMNAS.length} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún equipo coincide con estos filtros.</td></tr>}
          {filas.map((f) => {
            const activa = f.clave === seleccion
            const nombre = nombreEquipo(f)
            const abrir = (tipo: AccionEquipo, origen: HTMLElement) => accion(f, tipo, origen)
            return (
              <tr key={f.clave} data-equipo={f.clave} data-activa={activa}
                className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
                <th scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
                  <div className="flex min-h-[52px] items-center gap-2.5">
                    <Avatar nombre={f.nombre} color="var(--accent-press)" relleno={activa} />
                    <div className="min-w-0 flex-1 py-1">
                      {/* Se ve el nombre del supervisor, como el del analista en su tabla; se oye «Equipo de …». */}
                      <button type="button" aria-label={`Seleccionar ${nombre}`}
                        aria-current={activa ? 'true' : undefined} aria-controls={panelId} onClick={(e) => seleccionar(f, e.currentTarget)}
                        className={cn('block max-w-full cursor-pointer rounded-md text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
                          activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{f.nombre}</button>
                      <Integrantes f={f} en={`en ${nombre}`} abrir={abrir} />
                    </div>
                    {activa && <button type="button" aria-label={`Ir al detalle de ${nombre}`} onClick={irAlDetalle}
                      className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
                      <ArrowRight aria-hidden className="size-4" />
                    </button>}
                  </div>
                </th>
                <CifrasEquipo f={f} del={`del ${nombre}`} en={`en ${nombre}`} abrir={abrir} umbrales={umbrales} sinDetalle={sinDetalle} />
              </tr>
            )
          })}
        </tbody>
        <tfoot className="sticky bottom-0 z-[1] bg-muted">
          <tr className="[&>*]:border-t [&>*]:border-border">
            <th scope="row" className="py-0 pl-4 pr-2 text-left font-normal">
              {/* El nombre va directo en la rejilla: es el rótulo de la fila para el lector. */}
              <div className="grid min-h-[52px] grid-cols-[auto_minmax(0,1fr)] content-center items-center gap-x-2.5 py-1 text-sm font-extrabold leading-snug text-primary">
                <span aria-hidden="true" className="row-span-2 grid size-8 place-items-center rounded-full bg-card"><Users className="size-4" /></span>
                {totalOperacion.nombre}
                <Integrantes f={totalOperacion} en="en toda la operación" abrir={accionTotal} />
              </div>
            </th>
            <CifrasEquipo f={totalOperacion} del="de toda la operación" en="en toda la operación" abrir={accionTotal} umbrales={umbrales} sinDetalle={sinDetalle} total />
          </tr>
        </tfoot>
      </table>
    </div>
  </>
}

function Integrantes({ f, en, abrir }: { f: FilaEquipoOperacion; en: string; abrir: (tipo: AccionEquipo, origen: HTMLElement) => void }): JSX.Element {
  return (
    <p className="text-[11.5px] font-normal text-[var(--muted-foreground-strong)]">
      {f.analistas} {f.analistas === 1 ? 'analista' : 'analistas'}
      {f.sinRegistro > 0 && <> · <button type="button" onClick={(e) => abrir('sin_registro', e.currentTarget)}
        aria-label={`${f.sinRegistro} sin registro ${en}: ver quiénes`} className={ENLACE_CIFRA}>{f.sinRegistro} sin registro</button></>}
    </p>
  )
}

/**
 * Las siete cifras de una fila: las mismas para cada equipo y para «Toda la
 * operación». Las de un equipo abren sus analistas; las del total, los equipos.
 */
function CifrasEquipo({ f, del, en, abrir, umbrales, sinDetalle, total = false }: {
  f: FilaEquipoOperacion; del: string; en: string; abrir: (tipo: AccionEquipo, origen: HTMLElement) => void
  umbrales: v.InferOutput<typeof UmbralesSchema> | null; sinDetalle: 'cargando' | 'error'; total?: boolean
}): JSX.Element {
  const ver = total
    ? { llamadas: 'ver en el registro general', citas: 'ver los equipos ordenados por citas', vencidas: 'ver los equipos con vencidas', atencion: 'ver los equipos con atención' }
    : { llamadas: 'ver en el registro', citas: 'ver por analista', vencidas: 'ver por analista', atencion: 'ver quiénes' }
  return <>
    <td data-etiqueta="Llamadas" className="px-2 text-right text-sm tabular-nums text-foreground">
      {f.llamadas > 0 ? <button type="button" onClick={(e) => abrir('llamadas', e.currentTarget)} aria-label={`${f.llamadas} llamadas ${del}: ${ver.llamadas}`}
        className={cn(ENLACE_CIFRA, 'text-foreground')}>{f.llamadas}</button> : <span className="font-semibold">0</span>}
    </td>
    <td data-etiqueta="Contacto" className="px-2 text-right">
      {f.tasaContacto === null ? <span className="text-sm text-[var(--muted-foreground-strong)]">—</span>
        : <button type="button" onClick={(e) => abrir('llamadas', e.currentTarget)} aria-label={`Contacto ${Math.round(f.tasaContacto)} % ${del}: ver las llamadas y su resultado`}
          className={cn(ENLACE_CIFRA, 'text-sm font-bold text-foreground')}>{Math.round(f.tasaContacto)} %</button>}
      <NivelContacto fila={f} umbrales={umbrales} />
    </td>
    <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">
      {f.citas > 0 ? <button type="button" onClick={(e) => abrir('citas', e.currentTarget)} aria-label={`${f.citas} citas agendadas ${del}: ${ver.citas}`}
        className={cn(ENLACE_CIFRA, 'text-foreground')}>{f.citas}</button> : '0'}
    </td>
    <td data-etiqueta="Vencidas" className="px-2 text-right text-sm tabular-nums">
      {f.vencidas > 0
        ? <button type="button" onClick={(e) => abrir('vencidas', e.currentTarget)} aria-label={`${f.vencidas} tareas vencidas ${en}: ${ver.vencidas}`}
          className={cn(ENLACE_CIFRA, 'text-[var(--destructive-text)]')}>{f.vencidas}</button>
        : <span className="text-foreground">0</span>}
    </td>
    <td data-etiqueta="Atención" className="py-2 pl-4 pr-2 text-[13px]">
      {f.atencion === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">{sinDetalle === 'error' ? '—' : '…'}</span><span className="sr-only">{sinDetalle === 'error' ? 'No disponible' : 'Consultando'}</span></>
        : f.atencion === 0 ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
          : <button type="button" onClick={(e) => abrir('atencion', e.currentTarget)} aria-label={`${f.atencion} ${f.atencion === 1 ? 'analista necesita' : 'analistas necesitan'} atención ${en}: ${ver.atencion}`}
            className={cn(ENLACE_CIFRA, 'text-[var(--warning-text)]')}>{f.atencion} {f.atencion === 1 ? 'analista' : 'analistas'}</button>}
    </td>
    <td data-etiqueta="Primer intento" className="px-2 text-right text-sm tabular-nums text-foreground">
      {f.primerIntento === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Seguimiento no activo</span></> : f.primerIntento}
    </td>
    <td data-etiqueta="Dispersión" className="py-2 pl-2 pr-4 text-right">
      {f.dispersion.personas > 0 && f.dispersion.minimo !== null && f.dispersion.maximo !== null ? <>
        <span className="block text-sm tabular-nums text-foreground">{cifraPulso(Math.round(f.dispersion.minimo))}–{cifraPulso(Math.round(f.dispersion.maximo))} %</span>
        <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">{f.dispersion.personas} con muestra</span>
      </> : <span className="text-[11.5px] text-[var(--muted-foreground-strong)]">Sin muestra</span>}
    </td>
  </>
}

/** El nivel con los umbrales del servidor; sin muestra suficiente se dice con útiles y mínimo. */
function NivelContacto({ fila, umbrales }: { fila: FilaEquipoOperacion; umbrales: v.InferOutput<typeof UmbralesSchema> | null }): JSX.Element | null {
  const nivel = nivelEquipo(fila, umbrales)
  if (nivel.estado === 'evaluado') return <span className="mt-0.5 flex justify-end"><Badge className="min-h-[22px] py-0 text-[11.5px]" color={COLOR_NIVEL[nivel.nivel]}>{ETIQUETA_NIVEL[nivel.nivel]}</Badge></span>
  if (nivel.estado === 'sin_muestra') return <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">Sin muestra<span className="sr-only">: {nivel.utiles} de {nivel.minimo} llamadas útiles necesarias</span></span>
  return <span className="block text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{fila.contestadas}/{fila.utiles} útiles</span>
}
