/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar con el teclado las columnas que no caben. */
// Tabla de equipos de «Toda la operación» (diseño de Gestión Diaria, 27/09/2026):
// la protagonista. Misma forma que la del supervisor —tabla semántica con
// `aria-sort`, filas de 52 px, botón de selección e «Ir al detalle»— y conserva
// la comparación de gerencia: buscador, «Con atención», primer intento y
// dispersión (revisión Codex del plan). Los números de cada fila abren el
// equipo con ese filtro u orden: el número es la lista.
import type { JSX } from 'react'
import { ArrowDown, ArrowRight, ArrowUp, Check, Search } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Input } from '@/components/ui/input'
import { cifraPulso } from '@/lib/gestion-diaria-pulso'
import { nombreEquipo, type FilaEquipoOperacion, type FiltrosOperacion, type OrdenOperacion } from '@/lib/gestion-diaria-operacion'
import { cn } from '@/lib/utils'
import { CONTROL, FOCO, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from './estilos-gestion'

export type AccionEquipo = 'sin_registro' | 'vencidas' | 'atencion'

const COLUMNAS: { orden: OrdenOperacion; titulo: string; ancho: string; derecha?: boolean }[] = [
  { orden: 'nombre', titulo: 'Equipo', ancho: 'me-col-nombre' }, { orden: 'llamadas', titulo: 'Llamadas', ancho: 'w-[72px]', derecha: true },
  { orden: 'contacto', titulo: 'Contacto', ancho: 'w-[96px]', derecha: true }, { orden: 'citas', titulo: 'Citas', ancho: 'w-[56px]', derecha: true },
  { orden: 'vencidas', titulo: 'Vencidas', ancho: 'w-[72px]', derecha: true }, { orden: 'atencion', titulo: 'Atención', ancho: 'w-[116px]' },
  { orden: 'primer_intento', titulo: 'Primer intento', ancho: 'w-[96px]', derecha: true }, { orden: 'dispersion', titulo: 'Dispersión', ancho: 'w-[104px]', derecha: true },
]


const ENLACE_CIFRA = cn('cursor-pointer rounded-md font-semibold tabular-nums underline-offset-2 hover:underline pointer-coarse:min-h-11', FOCO)

export function TablaEquiposGerencia({ filas, total, conAtencion, sinDetalle = 'cargando', filtros, setFiltros, ordenar, seleccion, seleccionar, accion, panelId, irAlDetalle }: {
  /** Ya filtradas y ordenadas. */
  filas: FilaEquipoOperacion[]
  total: number
  /** Equipos con atención; null sin detalle. */
  conAtencion: number | null
  /** Por qué falta el detalle: mientras llega se dice «…»; si falló, «—» y «No disponible». */
  sinDetalle?: 'cargando' | 'error'
  filtros: FiltrosOperacion
  setFiltros: (cambio: (f: FiltrosOperacion) => FiltrosOperacion) => void
  ordenar: (orden: OrdenOperacion) => void
  seleccion: string | null
  seleccionar: (fila: FilaEquipoOperacion, origen: HTMLElement) => void
  accion: (fila: FilaEquipoOperacion, tipo: AccionEquipo, origen: HTMLElement) => void
  panelId: string
  irAlDetalle: () => void
}): JSX.Element {
  return <>
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
      <label className="relative min-w-40 max-w-[240px] flex-1"><span className="sr-only">Buscar equipo</span>
        <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar equipo…"
          className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
      </label>
      <button type="button" aria-pressed={filtros.conAtencion} onClick={() => setFiltros((f) => ({ ...f, conAtencion: !f.conAtencion }))}
        className={cn(PILDORA, filtros.conAtencion ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
        {filtros.conAtencion && <Check aria-hidden className="size-3.5" />}Con atención{' '}
        <span className="font-bold tabular-nums">{conAtencion ?? (sinDetalle === 'error' ? '—' : '…')}</span>
      </button>
      <p className="ml-auto text-xs text-[var(--muted-foreground-strong)]"><span role="status">{filas.length} de {total} equipos</span></p>
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
            return (
              <tr key={f.clave} data-equipo={f.clave} data-activa={activa}
                className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
                <th scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
                  <div className="flex min-h-[52px] items-center gap-2.5">
                    <Avatar nombre={f.nombre} color="var(--accent-press)" relleno={activa} />
                    <div className="min-w-0 flex-1 py-1">
                      <button type="button" aria-label={`Seleccionar ${nombre}`}
                        aria-current={activa ? 'true' : undefined} aria-controls={panelId} onClick={(e) => seleccionar(f, e.currentTarget)}
                        className={cn('block max-w-full cursor-pointer rounded-md text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
                          activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{nombre}</button>
                      <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">
                        {f.analistas} {f.analistas === 1 ? 'analista' : 'analistas'}
                        {f.sinRegistro > 0 && <> · <button type="button" onClick={(e) => accion(f, 'sin_registro', e.currentTarget)}
                          aria-label={`${f.sinRegistro} sin registro en ${nombre}: ver quiénes`} className={ENLACE_CIFRA}>{f.sinRegistro} sin registro</button></>}
                      </p>
                    </div>
                    {activa && <button type="button" aria-label={`Ir al detalle de ${nombre}`} onClick={irAlDetalle}
                      className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
                      <ArrowRight aria-hidden className="size-4" />
                    </button>}
                  </div>
                </th>
                <td data-etiqueta="Llamadas" className="px-2 text-right text-sm font-semibold tabular-nums text-foreground">{f.llamadas}</td>
                <td data-etiqueta="Contacto" className="px-2 text-right">
                  <span className="block text-sm font-bold tabular-nums text-foreground">{f.tasaContacto === null ? '—' : `${Math.round(f.tasaContacto)} %`}</span>
                  <span className="block text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{f.contestadas}/{f.utiles} útiles</span>
                </td>
                <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">{f.citas}</td>
                <td data-etiqueta="Vencidas" className="px-2 text-right text-sm tabular-nums">
                  {f.vencidas > 0
                    ? <button type="button" onClick={(e) => accion(f, 'vencidas', e.currentTarget)} aria-label={`${f.vencidas} tareas vencidas en ${nombre}: ver por analista`}
                      className={cn(ENLACE_CIFRA, 'text-[var(--destructive-text)]')}>{f.vencidas}</button>
                    : <span className="text-foreground">0</span>}
                </td>
                <td data-etiqueta="Atención" className="py-2 pl-4 pr-2 text-[13px]">
                  {f.atencion === null ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">{sinDetalle === 'error' ? '—' : '…'}</span><span className="sr-only">{sinDetalle === 'error' ? 'No disponible' : 'Consultando'}</span></>
                    : f.atencion === 0 ? <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
                      : <button type="button" onClick={(e) => accion(f, 'atencion', e.currentTarget)} aria-label={`${f.atencion} ${f.atencion === 1 ? 'analista necesita' : 'analistas necesitan'} atención en ${nombre}: ver quiénes`}
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
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  </>
}

