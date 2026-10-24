import { fechaCorteCapital, type CoberturaCapital } from '@/lib/capital-valorado'
import { money, numero } from '@/lib/format'

/** El corte acompaña al importe; los pendientes conservan su moneda original. */
export function CoberturaCapitalAviso({ cobertura, sellado = false, sinCorte = 'Las ventas pendientes se muestran aparte hasta completar su valoración.' }: { cobertura: CoberturaCapital; sellado?: boolean; sinCorte?: string }) {
  const pendientes = cobertura.pendientes.cantidad
  const valoradasPorIncorporar = Math.max(0, cobertura.por_incorporar.cantidad - pendientes)
  const dolaresSinTipoCambio = cobertura.ventas_pendientes
    .filter((venta) => venta.moneda === 'USD' && venta.motivo === 'cotizacion_pendiente')
    .reduce((suma, venta) => suma + Math.round(venta.monto * 100), 0) / 100
  return (
    <div className="space-y-2 text-xs leading-relaxed">
      <p className="font-semibold">Capital en soles con TC fijado por venta
        {cobertura.corte ? ` · Corte ${fechaCorteCapital(cobertura.corte)}` : ' · Aún no se ha publicado un corte'}
        {sellado ? ' · Mes sellado' : ''}
      </p>
      {cobertura.estado === 'atascado' && <p role="alert" className="font-semibold text-amber-900">El cierre sigue pendiente de valoración más de 24 horas después del plazo. El mes permanece abierto.</p>}
      {cobertura.corte === null && <p role="status">{sinCorte}</p>}
      {valoradasPorIncorporar > 0 && (
        <p role="status">{numero(valoradasPorIncorporar)} operaciones ya valoradas se incorporarán en la próxima actualización.</p>
      )}
      {dolaresSinTipoCambio > 0 && <p role="status">{money(dolaresSinTipoCambio, 'USD')} pendiente de tipo de cambio. No incluido en el capital valorado.</p>}
      {pendientes > 0 && (
        <details>
          <summary className="cursor-pointer py-2 font-semibold">{numero(pendientes)} {pendientes === 1 ? 'venta pendiente' : 'ventas pendientes'} de valoración
            {cobertura.pendientes.pen > 0 ? ` · ${money(cobertura.pendientes.pen, 'PEN')}` : ''}
            {cobertura.pendientes.usd > 0 ? ` · ${money(cobertura.pendientes.usd, 'USD')}` : ''}
          </summary>
          <ul aria-label="Ventas pendientes de valoración" className="space-y-2">
            {cobertura.ventas_pendientes.map((venta) => (
              <li key={`${venta.fuente}:${venta.fuente_id}`}>
                {money(venta.monto, venta.moneda)} {venta.motivo === 'cotizacion_pendiente' ? 'pendiente de tipo de cambio' : venta.motivo === 'fecha_comercial_sin_acreditar' ? 'pendiente de acreditar fecha comercial' : 'pendiente de revisión'}
                {' · '}{venta.fuente === 'contrato' ? 'Contrato' : 'Cierre externo'}
                {' · '}{venta.fecha_comercial ? fechaCorteCapital(venta.fecha_comercial) : 'Fecha comercial por acreditar'}
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  )
}
