import { useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useCitasClientes } from '@/data/gestiones-clientes'
import type { CursorCitas } from '@/lib/gestion-diaria-citas'
import { etiquetaResultadoCliente } from '@/lib/gestion-diaria'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { EnlaceSujetoGestion } from '@/components/gestion-diaria/enlace-sujeto'

const ESTADO = { pendiente: 'Pendiente', completada: 'Entrevista realizada', no_show: 'No asistió', reprogramada: 'Reprogramada', cancelada: 'Cancelada' }
const fecha = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
export function CitasClientes({ mes }: { mes: string }) {
  return <ListaCitasClientes key={mes} mes={mes} />
}
function ListaCitasClientes({ mes }: { mes: string }) {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const [autor, setAutor] = useState('')
  const [cursor, setCursor] = useState<CursorCitas | null>(null)
  const [anio = 0, numeroMes = 0] = mes.split('-').map(Number)
  const hasta = `${mes}-${String(new Date(Date.UTC(anio, numeroMes, 0)).getUTCDate()).padStart(2, '0')}`
  const q = useCitasClientes(`${mes}-01`, hasta, autor ? [autor] : null, cursor)
  if (yo?.demo) return null
  const datos = q.isError || q.isFetching ? null : q.data
  return <section aria-label="Citas de clientes" className="mt-5 space-y-3 rounded-xl border border-border bg-card p-4">
    <header className="flex flex-wrap items-center justify-between gap-3">
      <div><h2 className="text-lg font-bold text-primary">Citas de clientes</h2><p className="text-sm text-muted-foreground">{mes} · según la fecha de la cita. Cada asistencia registrada cuenta como entrevista.</p></div>
      <label className="text-sm">Analista<Select value={autor} onChange={e => { setAutor(e.target.value); setCursor(null) }}>
        <option value="">Todo mi ámbito</option>{ambito.vendedores.filter(a => a.activo).map(a => <option key={a.perfil_id} value={a.perfil_id}>{a.nombre_completo}</option>)}
      </Select></label>
    </header>
    {q.isError ? <div role="alert">No se pudieron cargar las citas de clientes. <Button variant="ghost" onClick={() => void q.refetch()}>Reintentar</Button></div>
      : !datos ? <p role="status">Consultando citas de clientes…</p> : <>
        <p className="text-sm font-semibold">{datos.resumen.total} citas · {datos.resumen.entrevistas} entrevistas · {datos.resumen.pendientes} pendientes · {datos.resumen.no_asistio} no asistieron · {datos.resumen.reprogramadas} reprogramadas · {datos.resumen.canceladas} canceladas</p>
        <ul className="divide-y divide-border">{datos.items.map(c => <li key={c.id} className="flex flex-wrap items-start justify-between gap-3 py-3 text-sm">
          <div className="space-y-1"><EnlaceSujetoGestion sujeto={c} /><p>{c.vendedor_nombre} · <time dateTime={c.vence_en}>{fecha.format(new Date(c.vence_en))}</time></p></div>
          <div className="text-right"><p className="font-semibold">{ESTADO[c.estado]}{c.estado === 'pendiente' && c.confirmada_en ? ' · Confirmada' : ''}</p>
            {c.estado === 'completada' && <p>{etiquetaResultadoCliente(c.resultado_reunion ?? 'sin_clasificar')}</p>}
          </div>
        </li>)}</ul>
        {datos.items.length === 0 && <p className="text-sm text-muted-foreground">No hay citas de clientes en esta página.</p>}
        <div className="flex flex-wrap items-center justify-between gap-2 text-sm"><span>{datos.items.length} citas en esta página</span><div className="flex gap-2">
          {cursor && <Button variant="outline" onClick={() => setCursor(null)}>Primera página</Button>}
          {datos.hay_mas && <Button variant="outline" onClick={() => setCursor(datos.siguiente_cursor)}>Siguiente página</Button>}
        </div></div>
      </>}
  </section>
}
