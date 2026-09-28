import { ArrowDown, ArrowUp, ArrowRight } from 'lucide-react'
import { COLOR_NIVEL, ETIQUETA_NIVEL, textoTasa } from '@/lib/gestion-diaria-analista'
import { MOTIVOS_EQUIPO, presentarAtencion, presentarContacto, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
  { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'pendientes', titulo: 'Pendientes' },
  { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'atencion', titulo: 'Atención' },
]

interface PropsTabla {
  filas: readonly FilaEquipoPresentada[]
  filtros: FiltrosEquipo
  ordenar: (orden: OrdenEquipo) => void
  seleccion: string | null
  seleccionar: (fila: FilaEquipoPresentada) => void
  panelId: string
  irAlDetalle: () => void
  minimo: number
  /** `gerencia` (por defecto): la tabla de siempre, con Pendientes. `supervisor`:
   * el diseño de Gestión Diaria (27/09) — iniciales, Citas, atención en palabras.
   * Gerencia no cambia hasta su propio plan (revisión Codex del plan supervisor). */
  contexto?: 'gerencia' | 'supervisor' | undefined
}

/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. */
export function TablaEquipoDiaria({ contexto = 'gerencia', ...props }: PropsTabla) {
  return contexto === 'supervisor' ? <TablaSupervisor {...props} /> : <TablaGerencia {...props} />
}

function TablaGerencia({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: Omit<PropsTabla, 'contexto'>) {
  return (
    <div className="gd-tabla-scroll ac-scroll">
      <table aria-label="Actividad y pendientes por analista" className="gd-tabla">
        <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={`gd-col-${c.orden}`} />)}</colgroup>
        <thead><tr>{COLUMNAS.map((c) => (
          <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}>
            <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}>
              {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}
            </button>
          </th>
        ))}</tr></thead>
        <tbody>
          {filas.length === 0 && <tr><td colSpan={6} className="gd-sin-filas">Ningún analista coincide con estos filtros.</td></tr>}
          {filas.map((f) => {
            const activa = f.analista_id === seleccion
            const sinMuestra = f.marcador.nivel === null
            const contacto = f.marcador.utiles === 0 ? '—' : sinMuestra ? 'Sin muestra' : `${f.marcador.tasa_contacto_pct} %`
            const contextoContacto = f.marcador.utiles === 0 ? 'Sin llamadas útiles' : `${textoTasa(f.marcador)}; ${f.marcador.contestadas} de ${f.marcador.utiles} útiles; mínimo ${minimo}${sinMuestra ? '; sin muestra suficiente' : `; nivel ${ETIQUETA_NIVEL[f.marcador.nivel!]}`}`
            return (
              <tr key={f.analista_id} data-analista={f.analista_id} data-activa={activa}>
                <th scope="row" className="gd-nombre"><div>
                  <button type="button" aria-label={`Seleccionar a ${f.nombre_completo}`} aria-current={activa ? 'true' : undefined}
                    aria-controls={panelId} onClick={() => seleccionar(f)}>{f.nombre_completo}</button>
                  {activa && <button type="button" className="gd-ir-detalle" aria-label={`Ir al detalle de ${f.nombre_completo}`} onClick={irAlDetalle}><ArrowRight aria-hidden /></button>}
                </div></th>
                <td data-etiqueta="Llamadas">{f.marcador.llamadas}</td>
                <td data-etiqueta="Contacto"><span style={f.marcador.nivel ? { color: COLOR_NIVEL[f.marcador.nivel] } : undefined}><span aria-hidden>{contacto}{f.marcador.nivel && <span className="gd-nivel-contacto">{ETIQUETA_NIVEL[f.marcador.nivel]}</span>}</span><span className="sr-only">{contextoContacto}</span></span></td>
                <td data-etiqueta="Pendientes">{f.tareas_pendientes}</td>
                <td data-etiqueta="Vencidas"><span className={f.tareas_vencidas > 0 ? 'text-[var(--danger-text)] font-semibold' : ''}>{f.tareas_vencidas}</span></td>
                <td data-etiqueta="Atención"><span className={f.requiere_atencion ? 'gd-motivos' : 'text-[var(--muted-foreground-strong)]'}>
                  {f.motivos_atencion.length ? `${f.motivos_atencion.length} ${f.motivos_atencion.length === 1 ? 'motivo' : 'motivos'}` : f.gestiones_hoy === 0 ? 'Sin registro' : 'Sin alertas'}
                  {f.motivos_atencion.length > 0 && <span className="sr-only">: {f.motivos_atencion.map((m) => MOTIVOS_EQUIPO[m]).join('; ')}</span>}
                </span></td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
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
function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: Omit<PropsTabla, 'contexto'>) {
  return (
    <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-y-auto">
      <table aria-label="Actividad y pendientes por analista" className="me-tabla w-full table-fixed border-separate border-spacing-0">
        <colgroup>{COLUMNAS_SUPERVISOR.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
        <thead className="sticky top-0 z-[1] bg-card">
          <tr>{COLUMNAS_SUPERVISOR.map((c, i) => (
            <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS_SUPERVISOR.length - 1 && 'pr-4')}>
              <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}
                className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
                  c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
                {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
              </button>
            </th>
          ))}</tr>
        </thead>
        <tbody>
          {filas.length === 0 && <tr><td colSpan={6} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún analista coincide con estos filtros.</td></tr>}
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
