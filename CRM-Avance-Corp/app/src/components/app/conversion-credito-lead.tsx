import { useConversionEstado } from '@/data/crm-queries'
import { fmtFecha } from '@/lib/format'
import { Button } from '@/components/ui/button'

/** Solo se monta para leads reales convertidos. Demo no consulta crédito real. */
export function ConversionCreditoLead({ leadId }: { leadId: string }) {
  const consulta = useConversionEstado(leadId)
  if (consulta.isError) {
    return (
      <div className="mt-1.5 text-[11px] text-muted-foreground" role="status">
        <p>No pudimos consultar el crédito de conversión.</p>
        <Button size="xs" variant="ghost" disabled={consulta.isFetching} onClick={() => void consulta.refetch()}>
          Reintentar consulta de conversión
        </Button>
      </div>
    )
  }
  if (!consulta.data) {
    return <p className="mt-1.5 text-[11px] text-muted-foreground" role="status">Consultando crédito de conversión…</p>
  }
  const estado = consulta.data
  return (
    <div className="mt-1.5 space-y-0.5 text-[11px] text-muted-foreground" aria-label="Crédito de conversión mensual">
      <p>{estado.mensaje}</p>
      {estado.fecha_comercial && <p>Fecha de cierre comercial: {fmtFecha(estado.fecha_comercial)}.</p>}
    </div>
  )
}
