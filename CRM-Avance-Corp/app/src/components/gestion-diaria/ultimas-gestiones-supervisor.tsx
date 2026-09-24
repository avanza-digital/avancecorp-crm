import { useEffect, useEffectEvent, useMemo, useRef } from 'react'
import { useRegistroActividadOperativo } from '@/data/gestion-diaria-queries'
import { CrmApiError } from '@/data/crm-api'
import { usePanelesActions } from '@/lib/store-context'
import { ETIQUETA_CORTA, horaDeItem, type FiltrosRegistro } from '@/lib/gestion-diaria'
import { Button } from '@/components/ui/button'

export function UltimasGestionesSupervisor({ analista, dia, visible, actualizacion, revalidar }: {
  analista: string; dia: string; visible: boolean; actualizacion: number; revalidar: () => void
}) {
  const filtros = useMemo<FiltrosRegistro>(() => ({ dia, analistaIds: [analista], pestana: 'todo', etapa: null }), [dia, analista])
  // Misma clave y tamaño que Registro → Todo, primera página sin filtro.
  const consulta = useRegistroActividadOperativo(filtros, null, 25, visible, true)
  const { abrirLead } = usePanelesActions()
  const revision = useRef(actualizacion)
  const refrescar = useEffectEvent(() => { void consulta.recargar() })
  const revocar = useEffectEvent(revalidar)
  const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  useEffect(() => {
    if (revision.current === actualizacion) return
    revision.current = actualizacion; refrescar()
  }, [actualizacion])
  useEffect(() => { if (sinPermiso) revocar() }, [sinPermiso])
  return <section className="space-y-2 mt-4" aria-label="Últimas gestiones del analista">
    <h4 className="font-semibold">Últimas gestiones</h4>
    {consulta.pagina && <p className="text-[var(--muted-foreground-strong)]">Consulta: {new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(consulta.pagina.generado_en))} · Lima.</p>}
    {consulta.cargando && <p role="status">Consultando las últimas gestiones…</p>}
    {consulta.error ? <div role="alert"><p>No se pudieron confirmar las últimas gestiones.</p>
      {!sinPermiso && <Button className="min-h-11 text-base" variant="outline" onClick={() => { void consulta.recargar() }} disabled={consulta.enVuelo}>Reintentar últimas gestiones</Button>}</div>
      : consulta.pagina && consulta.pagina.items.length === 0 ? <p>No hay gestiones visibles de este analista en el día.</p>
        : <ol>{consulta.pagina?.items.slice(0, 3).map(item => <li key={item.id} className="py-2">
          <p><time dateTime={new Date(item.creado_en).toISOString()}>{horaDeItem(item)}</time> · {ETIQUETA_CORTA[item.tipo]}</p>
          <Button variant="link" className="min-h-11 h-auto max-w-full whitespace-normal px-0 text-left text-base" onClick={() => abrirLead(item.lead_id)}>{item.lead_nombre}</Button>
        </li>)}</ol>}
  </section>
}
