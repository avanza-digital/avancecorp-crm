import { useDiaLima } from '@/data/crm-queries'
import { useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useResumenGestiones } from '@/data/gestiones-clientes'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { RegistroActividad } from './registro-actividad'

/** Actividad ejecutada por autor. Las metas y razones de captación conservan su población. */
export function ResumenGestionesClientes({ dia, autores = null }: { dia: string; autores?: readonly string[] | null }) {
  const { yo } = useAuth()
  const q = useResumenGestiones(dia, dia, autores)
  const [registro, setRegistro] = useState<{ ids: readonly string[] | null; nombre: string } | null>(null)
  if (yo?.demo) return null
  if (autores?.length === 0) return <p className="text-sm text-muted-foreground">No hay analistas en el equipo seleccionado.</p>
  const datos = q.isError ? null : q.data
  return <section aria-label="Gestión de leads y clientes" className="rounded-xl border border-border bg-card px-4 py-3">
    <div className="flex flex-wrap items-center justify-between gap-2">
      <h3 className="text-base font-bold text-primary">Gestión de leads y clientes · {dia}</h3>
      {datos && <Button variant="ghost" onClick={() => setRegistro({ ids: autores, nombre: 'Registro del día' })}>Ver gestiones</Button>}
    </div>
    {q.isError ? <div role="alert" className="text-sm">No se pudo consultar la gestión de clientes. <Button variant="ghost" onClick={() => void q.refetch()}>Reintentar</Button></div>
      : !datos ? <p role="status" className="text-sm text-muted-foreground">Consultando gestiones…</p>
      : <>
        <div className="overflow-x-auto">
          <table className="w-full text-sm tabular-nums">
            <caption className="sr-only">Gestiones registradas el {dia}, por cartera</caption>
            <thead><tr className="text-right text-muted-foreground"><th scope="col" className="py-2 text-left">Cartera</th><th scope="col">Llamadas</th><th scope="col">Contestadas</th><th scope="col">Entrevistas</th><th scope="col">Gestiones</th></tr></thead>
            <tbody>{(['leads', 'clientes', 'total'] as const).map(grupo => <tr key={grupo} className={grupo === 'total' ? 'border-t border-border font-bold' : ''}>
              <th scope="row" className="py-1.5 text-left">{{ leads: 'Leads', clientes: 'Clientes', total: 'Total' }[grupo]}</th>
              <td className="text-right">{datos.totales[grupo].llamadas}</td><td className="text-right">{datos.totales[grupo].contestadas}</td>
              <td className="text-right">{datos.totales[grupo].entrevistas}</td><td className="text-right">{datos.totales[grupo].gestiones}</td>
            </tr>)}</tbody>
          </table>
        </div>
        {yo?.rol !== 'vendedor' && datos.analistas.length > 0 && <details className="mt-2">
          <summary className="cursor-pointer rounded-md text-sm font-semibold focus-visible:outline-2 focus-visible:outline-ring">Ver actividad por analista</summary>
          <ul className="mt-2 space-y-2">{datos.analistas.map(a => <li key={a.id ?? 'sin-autor'} className="flex flex-wrap items-center justify-between gap-2 text-sm">
            <button type="button" className="rounded-md text-left font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-ring" disabled={!a.id} onClick={() => { if (a.id) setRegistro({ ids: [a.id], nombre: a.nombre }) }}>{a.nombre}</button>
            <span>{a.metricas.total.llamadas} llamadas ({a.metricas.leads.llamadas} leads · {a.metricas.clientes.llamadas} clientes) · {a.metricas.total.entrevistas} entrevistas</span>
          </li>)}</ul>
        </details>}
        <p className="mt-2 text-xs text-muted-foreground">Se atribuye a quien registró la gestión. Las entrevistas corresponden a citas realizadas; los cierres antiguos sin resultado no confirman una llamada contestada.</p>
      </>}
    <Dialog open={Boolean(registro) && !q.isError} onClose={() => setRegistro(null)} ariaLabel="Registro de gestiones">
      <DialogHeader><DialogTitle>{registro?.nombre}</DialogTitle></DialogHeader>
      <DialogBody>{registro && <RegistroActividad dia={dia} analistaIds={registro.ids} mostrarAnalista={yo?.rol !== 'vendedor'} permitirExportar={yo?.rol === 'gerencia'} pestanaInicial="todo" />}</DialogBody>
    </Dialog>
  </section>
}

export function ResumenGestionesHoy() {
  const dia = useDiaLima()
  return <ResumenGestionesClientes dia={dia} />
}

/** La tabla diaria conserva su espacio; el desglose completo se abre a demanda. */
export function AccesoGestionesClientes({ dia, autores = null }: { dia: string; autores?: readonly string[] | null }) {
  const { yo } = useAuth()
  const [abierto, setAbierto] = useState(false)
  if (yo?.demo) return null
  return <>
    <Button variant="ghost" className="h-9 min-h-9 px-3 text-[13px] pointer-coarse:h-11" aria-haspopup="dialog" onClick={() => setAbierto(true)}>Gestión de clientes</Button>
    <Dialog open={abierto} onClose={() => setAbierto(false)}>
      <DialogHeader><DialogTitle>Gestión de leads y clientes</DialogTitle></DialogHeader>
      <DialogBody>{abierto && <ResumenGestionesClientes key={JSON.stringify([dia, autores])} dia={dia} autores={autores} />}</DialogBody>
    </Dialog>
  </>
}
