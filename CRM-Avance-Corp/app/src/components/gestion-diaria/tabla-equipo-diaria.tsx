import { ArrowDown, ArrowUp, ArrowRight } from 'lucide-react'
import { COLOR_NIVEL, ETIQUETA_NIVEL } from '@/lib/gestion-diaria-analista'
import { presentarAtencion, presentarContacto, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

interface PropsTabla {
  filas: readonly FilaEquipoPresentada[]
  filtros: FiltrosEquipo
  ordenar: (orden: OrdenEquipo) => void
  seleccion: string | null
  seleccionar: (fila: FilaEquipoPresentada) => void
  panelId: string
  irAlDetalle: () => void
  minimo: number
  /** Gerencia dentro de un equipo compara también Pendientes (27/09). */
  conPendientes?: boolean | undefined
}

/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. La
 * usan el supervisor y gerencia dentro de un equipo (27/09): el diseño de Gestión Diaria. */
export function TablaEquipoDiaria(props: PropsTabla) {
  return <TablaSupervisor {...props} />
}

const COLUMNAS_SUPERVISOR: { orden: OrdenEquipo; titulo: string; ancho: string; derecha?: boolean }[] = [
  { orden: 'nombre', titulo: 'Analista', ancho: 'me-col-nombre' }, { orden: 'llamadas', titulo: 'Llamadas', ancho: 'w-[68px]', derecha: true },
  { orden: 'contacto', titulo: 'Contacto', ancho: 'w-[132px]', derecha: true }, { orden: 'citas', titulo: 'Citas', ancho: 'w-[56px]', derecha: true },
  { orden: 'vencidas', titulo: 'Vencidas', ancho: 'w-[72px]', derecha: true }, { orden: 'atencion', titulo: 'Atención', ancho: 'w-[156px]' },
]

const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'

/**
 * La tabla del supervisor con el diseño de Gestión Diaria (27/09). Sigue siendo
 * una tabla semántica con `aria-sort`, el botón de selección con su nombre y la
 * flecha «Ir al detalle»; en un contenedor estrecho (celular, zoom 200 %) las
 * filas se vuelven tarjetas con rótulos (`mi-equipo.css`), sin scroll lateral.
 */
function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo, conPendientes = false }: PropsTabla) {
  const columnas = conPendientes ? COLUMNAS_SUPERVISOR.flatMap((c) => c.orden === 'citas'
    ? [c, { orden: 'pendientes' as const, titulo: 'Pendientes', ancho: 'w-[84px]', derecha: true }] : [c]) : COLUMNAS_SUPERVISOR
  return (
    <div className={cn('gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-y-auto', conPendientes && '!overflow-x-auto')}>
      <table aria-label="Actividad y pendientes por analista" className={cn('me-tabla w-full table-fixed border-separate border-spacing-0', conPendientes && '@min-[641px]:min-w-[760px]')}>
        <colgroup>{columnas.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
        <thead className="sticky top-0 z-[1] bg-card">
          <tr>{columnas.map((c, i) => (
            <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === columnas.length - 1 && 'pr-4')}>
              <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}
                className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
                  c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
                {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
              </button>
            </th>
          ))}</tr>
        </thead>
        <tbody>
          {filas.length === 0 && <tr><td colSpan={columnas.length} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún analista coincide con estos filtros.</td></tr>}
          {filas.map((f) => {
            const activa = f.analista_id === seleccion
            const contacto = presentarContacto(f.marcador, minimo)
            const atencion = presentarAtencion(f)
            return (
              <tr key={f.analista_id} data-analista={f.analista_id} data-activa={activa}
                className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
                <th scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
                  <div className="flex min-h-[52px] items-center gap-2.5">
                    <Avatar nombre={f.nombre_completo} color="var(--accent-press)" relleno={activa} />
                    <button type="button" aria-label={`Seleccionar a ${f.nombre_completo}`} aria-current={activa ? 'true' : undefined}
                      aria-controls={panelId} onClick={() => seleccionar(f)}
                      className={cn('min-w-0 flex-1 cursor-pointer rounded-md py-1 text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
                        activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{f.nombre_completo}</button>
                    {activa && <button type="button" aria-label={`Ir al detalle de ${f.nombre_completo}`} onClick={irAlDetalle}
                      className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
                      <ArrowRight aria-hidden className="size-4" />
                    </button>}
                  </div>
                </th>
                <td data-etiqueta="Llamadas" className="px-2 text-right text-sm font-semibold tabular-nums text-foreground">{f.marcador.llamadas}</td>
                <td data-etiqueta="Contacto" className="px-2 text-right">
                  <span aria-hidden="true" className="inline-flex flex-wrap items-center justify-end gap-x-2 gap-y-0.5">
                    {contacto.estado === 'evaluado' ? <>
                      <span className="text-sm font-bold tabular-nums text-foreground">{contacto.valor}</span>
                      <Badge className="min-h-[22px] py-0 text-[11.5px]" color={COLOR_NIVEL[contacto.nivel!]}>{ETIQUETA_NIVEL[contacto.nivel!]}</Badge>
                    </> : contacto.estado === 'sin_muestra' ? <>
                      <span className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Sin muestra</span>
                      <span className="w-full text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{contacto.detalle}</span>
                    </> : <span className="text-sm text-[var(--muted-foreground-strong)]">—</span>}
                  </span>
                  <span className="sr-only">{contacto.accesible}</span>
                </td>
                <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">{f.marcador.citas_agendadas}</td>
                {conPendientes && <td data-etiqueta="Pendientes" className="px-2 text-right text-sm tabular-nums text-foreground">{f.tareas_pendientes}</td>}
                <td data-etiqueta="Vencidas" className={cn('px-2 text-right text-sm font-semibold tabular-nums', f.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-foreground')}>{f.tareas_vencidas}</td>
                <td data-etiqueta="Atención" className="py-2 pl-4 pr-4 text-[13px]">
                  {atencion.texto === null
                    ? f.gestiones_hoy === 0 ? <span className="text-[var(--muted-foreground-strong)]">Sin registro</span>
                      : <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
                    : <span className="font-semibold" style={{ color: atencion.tono === 'vencido' ? 'var(--destructive-text)' : 'var(--warning-text)' }}>
                      {atencion.texto}{atencion.mas > 0 && <span className="ml-1.5 font-normal text-[var(--muted-foreground-strong)]">+{atencion.mas}</span>}
                    </span>}
                  {atencion.lista.length > 0 && <span className="sr-only">: {atencion.lista.join('; ')}</span>}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
