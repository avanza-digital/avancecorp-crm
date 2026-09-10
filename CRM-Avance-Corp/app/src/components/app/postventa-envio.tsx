import { Button } from '@/components/ui/button'
import type { EnvioPostventa } from '@/lib/postventa-envios'
import type { useEnvioPostventa } from '@/data/use-envio-postventa'

function resumen(e: EnvioPostventa | null): string {
  if (!e) return ''
  const p = e.parametros
  const d = p.p_datos && typeof p.p_datos === 'object' ? p.p_datos as Record<string, unknown> : {}
  const texto = d.titulo ?? d.detalle ?? p.p_motivo ?? p.p_detalle
  return typeof texto === 'string' ? texto.slice(0, 240) : e.comando === 'tarea' && p.p_accion === 'confirmar' ? 'Confirmación de asistencia' : ''
}
export function RecuperacionPostventa({envio, onRecuperar}: {
  envio: ReturnType<typeof useEnvioPostventa>; onRecuperar: () => void
}) {
  const detalle = resumen(envio.pendiente)
  return <div className="space-y-3 rounded-lg border border-border bg-muted/30 p-3">
    <p className="text-sm">Hay un envío guardado. Verificaremos si se registró antes de volver a enviarlo.</p>
    {detalle && <p className="text-sm font-medium [overflow-wrap:anywhere]">{detalle}</p>}
    {envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
    <Button disabled={envio.ocupado} onClick={onRecuperar}>{envio.ocupado ? 'Verificando…' : 'Verificar envío guardado'}</Button>
  </div>
}
