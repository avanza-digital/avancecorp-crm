import { useEffect, useEffectEvent, useId, useRef, useState } from 'react'
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
  const resumen = lista.pagina?.resumen ?? (fila && !lista.sinPermiso ? fila : null)
  return <section aria-labelledby={tituloId} className="space-y-3">
    <h4 id={tituloId} ref={titulo} tabIndex={-1} className="font-semibold">Pendientes de {nombre}</h4>
    {resumen && <p><strong>{resumen.tareas_pendientes}</strong> tareas pendientes · <strong>{resumen.tareas_vencidas}</strong> vencidas.
      {lista.pagina ? ' Foto de la consulta de tareas.' : ' Último resumen confirmado del equipo.'}</p>}
    {fila && !lista.sinPermiso && <p className="text-[var(--muted-foreground-strong)]">Primer intento fuera de plazo: {fila.primer_intento_vencido ?? 'no evaluado'}. Datos incompletos: {fila.datos_incompletos ?? 'no evaluado'}.
      {' '}Estas señales corresponden a leads y no se suman como tareas.</p>}
    <div className="flex flex-wrap gap-2" role="group" aria-label="Filtro de tareas">
      <Button className="min-h-11 text-base" variant={!soloVencidas ? 'default' : 'outline'} aria-pressed={!soloVencidas} onClick={() => setSoloVencidas(false)}>Todas</Button>
      <Button className="min-h-11 text-base" variant={soloVencidas ? 'default' : 'outline'} aria-pressed={soloVencidas} onClick={() => setSoloVencidas(true)}>Vencidas</Button>
    </div>
    {lista.cargando && <p role="status">Consultando las tareas de este analista…</p>}
    {lista.error && <div role="alert" className="space-y-2">
      <p>{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas. Se retiraron los datos anteriores.'
        : noInstalada ? 'Detalle de tareas no disponible. La consulta aún no está instalada.'
          : 'No se pudo confirmar la lista de tareas. Esto no significa que esté vacía.'}</p>
      {!lista.sinPermiso && <Button className="min-h-11 text-base" variant="outline" disabled={lista.enVuelo} onClick={() => { void lista.recargar() }}>Reintentar desde el inicio</Button>}
    </div>}
    {lista.pagina && <p className="text-[var(--muted-foreground-strong)]">
      Consulta: {FECHA.format(new Date(lista.pagina.generado_en))} · Lima.
      {lista.error ? ' Datos anteriores; la actualización falló.' : lista.congelada ? ' Actualización automática pausada: hay varias páginas cargadas.' : ' Actualización cada minuto mientras esta pestaña está visible.'}
    </p>}
    {lista.congelada && lista.consultadoDesde && <p className="text-[var(--muted-foreground-strong)]">Primera página consultada: {FECHA.format(new Date(lista.consultadoDesde))}. Las tareas pueden cambiar; actualizar comienza una nueva consulta.</p>}
    {!lista.error && lista.pagina && lista.items.length === 0 && <p>{soloVencidas ? 'No hay tareas vencidas en esta consulta.' : 'Sin tareas pendientes.'}</p>}
    <ul className="divide-y divide-border" aria-label="Lista de tareas pendientes">
      {lista.items.map(tarea => <li key={tarea.id} className="space-y-1 py-3 break-words">
        <p className="font-semibold">{tarea.titulo.trim() || 'Sin título'}</p>
        <p>{TIPO_EVENTO[tarea.tipo] ?? tarea.tipo} · <time dateTime={new Date(tarea.vence_en).toISOString()}>{FECHA.format(new Date(tarea.vence_en))}</time> · Lima</p>
        {tarea.lead_id && tarea.lead_nombre
          ? <Button variant="link" className="min-h-11 h-auto max-w-full whitespace-normal px-0 text-left text-base" onClick={() => abrirLead(tarea.lead_id!)}>{tarea.lead_nombre}</Button>
          : <p className="text-[var(--muted-foreground-strong)]">{tarea.referencia_tipo === 'perfil' ? 'Tarea de perfil' : tarea.referencia_tipo === 'postventa' ? 'Tarea de postventa' : 'Referencia no disponible'}</p>}
      </li>)}
    </ul>
    {lista.pagina && <p role="status">{lista.items.length} tareas cargadas{lista.hayMas ? ' · Hay más por consultar.' : lista.error ? ' · Consulta incompleta.' : ' · Fin de las páginas consultadas.'}</p>}
    <div className="flex flex-wrap gap-2">
      {lista.hayMas && <Button className="min-h-11 text-base" disabled={lista.enVuelo} onClick={() => { void lista.cargarMas() }}>{lista.enVuelo ? 'Consultando…' : 'Cargar más tareas'}</Button>}
      {!lista.sinPermiso && !noInstalada && <Button className="min-h-11 text-base" variant="outline" disabled={lista.enVuelo} onClick={() => { void lista.recargar() }}>Actualizar desde el inicio</Button>}
    </div>
  </section>
}
