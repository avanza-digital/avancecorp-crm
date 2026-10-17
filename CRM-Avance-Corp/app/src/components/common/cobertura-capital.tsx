import { fechaCorteCapital, type CoberturaCapital } from '@/lib/capital-valorado'
import { money, numero } from '@/lib/format'

/** El corte acompaña al importe; los pendientes conservan su moneda original. */
export function CoberturaCapitalAviso({ cobertura, sellado = false, sinCorte = 'Las ventas pendientes se muestran sin puesto hasta completar la valoración.' }: { cobertura: CoberturaCapital; sellado?: boolean; sinCorte?: string }) {
  const pendientes = cobertura.pendientes.cantidad
  return (
    <div className="space-y-2 text-xs leading-relaxed">
      <p className="font-semibold">Capital en soles con TC fijado por venta
        {cobertura.corte ? ` · Corte ${fechaCorteCapital(cobertura.corte)}` : ' · Aún no hay un corte completo'}
        {sellado ? ' · Mes sellado' : ''}
      </p>
      {cobertura.estado === 'atascado' && <p role="alert" className="font-semibold text-amber-900">El cierre sigue pendiente de valoración más de 24 horas después del plazo. El mes permanece abierto.</p>}
      {cobertura.corte === null && <p role="status">{sinCorte}</p>}
      {cobertura.por_incorporar.cantidad > 0 && (
        <p role="status">{numero(cobertura.por_incorporar.cantidad)} operaciones por incorporar al siguiente corte completo. Se conserva la última publicación completa.</p>
      )}
      {pendientes > 0 && (
        <details>
          <summary className="cursor-pointer py-2 font-semibold">{numero(pendientes)} {pendientes === 1 ? 'venta pendiente' : 'ventas pendientes'} de valoración · {money(cobertura.pendientes.pen, 'PEN')} · {money(cobertura.pendientes.usd, 'USD')}</summary>
          <ul aria-label="Ventas pendientes de valoración" className="space-y-2">
            {cobertura.ventas_pendientes.map((venta) => (
              <li key={`${venta.fuente}:${venta.fuente_id}`}>
                {venta.fecha_comercial ? fechaCorteCapital(venta.fecha_comercial) : 'Fecha comercial por acreditar'} · {money(venta.monto, venta.moneda)} · {venta.motivo === 'cotizacion_pendiente' ? 'Cotización pendiente' : venta.motivo === 'fecha_comercial_sin_acreditar' ? 'Revisar fecha comercial' : 'Revisión pendiente'}
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  )
}
