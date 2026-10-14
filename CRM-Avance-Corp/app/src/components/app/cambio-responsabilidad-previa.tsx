import type { PreviaResponsabilidad } from '@/data/cambio-responsabilidad-api'
import { money, fmtFecha } from '@/lib/format'

export function CambioResponsabilidadPrevia({previa}: {previa: PreviaResponsabilidad}) {
  const cambios = previa.efectos.filter(e => e.anterior !== e.previsto || (previa.accion === 'venta' && e.id === previa.id))
  return <div className="space-y-2 rounded-lg border border-border bg-muted/30 p-3 text-sm" aria-live="polite">
    <p className="font-semibold">{previa.anterior_nombre ?? 'Sin responsable'} → {previa.destino_nombre}</p>
    <p>{previa.aviso}</p>
    {previa.accion !== 'venta' && <p>{previa.leads} leads abiertos · {previa.tareas} tareas pendientes en la ficha.</p>}
    {cambios.length ? <ul className="space-y-2">{cambios.map(e => <li key={`${e.tipo}:${e.id}`}>
      <p className="font-medium">{e.numero ?? 'Operación'} · {money(e.monto, e.moneda)}{e.fecha ? ` · ${fmtFecha(e.fecha)}` : ''}</p>
      <p>Facturación: {e.anterior_nombre ?? 'Sin analista'} → {e.previsto_nombre ?? 'Sin analista'}</p>
    </li>)}</ul> : <p>La atribución de las ventas se conserva.</p>}
    <p className="text-xs text-muted-foreground">Al confirmar se volverá a comprobar este efecto.</p>
  </div>
}
