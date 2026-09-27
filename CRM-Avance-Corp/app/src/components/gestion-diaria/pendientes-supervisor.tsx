import { useEffect, useEffectEvent, useId, useLayoutEffect, useRef, useState } from 'react'
import { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
import { CrmApiError } from '@/data/crm-api'
import { usePanelesActions } from '@/lib/store-context'
import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import { Button } from '@/components/ui/button'
import { TIPO_EVENTO } from '@/lib/tipos'

const FECHA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })

export function PendientesSupervisor({ analista, nombre, dia, fila, visible, soloVencidasInicial, apertura, enfocar, actualizacion, revalidar }: {
  analista: string; nombre: string; dia: string; fila: FilaEquipoPresentada | undefined; visible: boolean
  soloVencidasInicial: boolean; apertura: number; enfocar: boolean; actualizacion: number; revalidar: () => void
}) {
  const [soloVencidas, setSoloVencidas] = useState(soloVencidasInicial)
  const lista = usePendientesSupervisor(dia, analista, soloVencidas, visible, apertura)
  const { abrirLead } = usePanelesActions()
  const titulo = useRef<HTMLHeadingElement>(null)
  const tituloId = useId()
  const revision = useRef(actualizacion)
  const refrescar = useEffectEvent(() => { void lista.recargar() })
  const revocar = useEffectEvent(revalidar)
  useEffect(() => { if (enfocar) titulo.current?.focus({ preventScroll: true }) }, [enfocar])
  useEffect(() => {
    if (revision.current === actualizacion) return
    revision.current = actualizacion; refrescar()
  }, [actualizacion])
  useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
  const noInstalada = lista.error instanceof CrmApiError && lista.error.code === 'PGRST202'
  // «Cargar más» y «Reintentar» se desmontan al terminar: si el que tenía el
  // foco desaparece, el foco pasa al título (se sigue CADA control, no un conjunto).
  const enfocado = useRef<'cargar' | 'reintentar' | null>(null)
  const recordar = (cual: 'cargar' | 'reintentar') => ({ onFocus: () => { enfocado.current = cual }, onBlur: () => { enfocado.current = null } })
  const cargarVisible = lista.hayMas
  const reintentarVisible = Boolean(lista.error) && !lista.sinPermiso
  useLayoutEffect(() => {
    const cual = enfocado.current
    if (cual === null || (cual === 'cargar' ? cargarVisible : reintentarVisible)) return
    enfocado.current = null
    titulo.current?.focus({ preventScroll: true })
  }, [cargarVisible, reintentarVisible])
  const deshabilitado = 'aria-disabled:cursor-default aria-disabled:opacity-60'
  const resumen = lista.pagina?.resumen ?? (fila && !lista.sinPermiso ? fila : null)
  // Escala del diseño de Gestión Diaria (27/09): 13–15 px y controles compactos que crecen en táctil.
  return <section aria-labelledby={tituloId} className="space-y-3 text-[13.5px]">
    <h4 id={tituloId} ref={titulo} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Pendientes de {nombre}</h4>
    {resumen && <p><strong>{resumen.tareas_pendientes}</strong> tareas pendientes · <strong>{resumen.tareas_vencidas}</strong> vencidas.
      {lista.pagina ? ' Foto de la consulta de tareas.' : ' Último resumen confirmado del equipo.'}</p>}
    {fila && !lista.sinPermiso && <p className="text-[var(--muted-foreground-strong)]">Primer intento fuera de plazo: {fila.primer_intento_vencido ?? 'no evaluado'}. Datos incompletos: {fila.datos_incompletos ?? 'no evaluado'}.
      {' '}Estas señales corresponden a leads y no se suman como tareas.</p>}
    <div className="flex flex-wrap gap-2" role="group" aria-label="Filtro de tareas">
      <Button className="h-9 text-[13px] pointer-coarse:h-11" variant={!soloVencidas ? 'default' : 'outline'} aria-pressed={!soloVencidas} onClick={() => setSoloVencidas(false)}>Todas</Button>
      <Button className="h-9 text-[13px] pointer-coarse:h-11" variant={soloVencidas ? 'default' : 'outline'} aria-pressed={soloVencidas} onClick={() => setSoloVencidas(true)}>Vencidas</Button>
    </div>
    {lista.cargando && <p role="status">Consultando las tareas de este analista…</p>}
    {lista.error && <div role="alert" className="space-y-2">
      <p>{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas. Se retiraron los datos anteriores.'
        : noInstalada ? 'Detalle de tareas no disponible. La consulta aún no está instalada.'
          : 'No se pudo confirmar la lista de tareas. Esto no significa que esté vacía.'}</p>
      {!lista.sinPermiso && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} variant="outline" aria-disabled={lista.enVuelo} {...recordar('reintentar')} onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Reintentar desde el inicio</Button>}
    </div>}
    {lista.pagina && <p className="text-[var(--muted-foreground-strong)]">
      Consulta: {FECHA.format(new Date(lista.pagina.generado_en))} · Lima.
      {lista.error ? ' Datos anteriores; la actualización falló.' : lista.congelada ? ' Actualización automática pausada: hay varias páginas cargadas.' : ' Actualización cada minuto mientras esta pestaña está visible.'}
    </p>}
    {lista.congelada && lista.consultadoDesde && <p className="text-[var(--muted-foreground-strong)]">Primera página consultada: {FECHA.format(new Date(lista.consultadoDesde))}. Las tareas pueden cambiar; actualizar comienza una nueva consulta.</p>}
    {!lista.error && lista.pagina && lista.items.length === 0 && <p>{soloVencidas ? 'No hay tareas vencidas en esta consulta.' : 'Sin tareas pendientes.'}</p>}
    {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
    <ul role="list" className="divide-y divide-border" aria-label="Lista de tareas pendientes">
      {lista.items.map(tarea => <li key={tarea.id} className="space-y-1 py-3 break-words">
        <p className="font-bold text-primary">{tarea.titulo.trim() || 'Sin título'}</p>
        <p>{TIPO_EVENTO[tarea.tipo] ?? tarea.tipo} · <time dateTime={new Date(tarea.vence_en).toISOString()}>{FECHA.format(new Date(tarea.vence_en))}</time> · Lima</p>
        {tarea.lead_id && tarea.lead_nombre
          ? <Button variant="link" className="h-auto min-h-6 max-w-full whitespace-normal px-0 text-left text-[13.5px] pointer-coarse:min-h-11" onClick={() => abrirLead(tarea.lead_id!)}>{tarea.lead_nombre}</Button>
          : <p className="text-[var(--muted-foreground-strong)]">{tarea.referencia_tipo === 'perfil' ? 'Tarea de perfil' : tarea.referencia_tipo === 'postventa' ? 'Tarea de postventa' : 'Referencia no disponible'}</p>}
      </li>)}
    </ul>
    {lista.pagina && <p role="status">{lista.items.length} tareas cargadas{lista.hayMas ? ' · Hay más por consultar.' : lista.error ? ' · Consulta incompleta.' : ' · Fin de las páginas consultadas.'}</p>}
    <div className="flex flex-wrap gap-2">
      {lista.hayMas && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} aria-disabled={lista.enVuelo} {...recordar('cargar')} onClick={() => { if (!lista.enVuelo) void lista.cargarMas() }}>{lista.enVuelo ? 'Consultando…' : 'Cargar más tareas'}</Button>}
      {!lista.sinPermiso && !noInstalada && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} variant="outline" aria-disabled={lista.enVuelo} onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Actualizar desde el inicio</Button>}
    </div>
  </section>
}
