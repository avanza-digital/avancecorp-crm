import { useEffect, useRef } from 'react'
import { CrmApiError } from '@/data/crm-api'
import { Button } from '@/components/ui/button'

export function ErrorConsultaGerencia({ error, recargar, enVuelo }: { error: unknown; recargar: () => Promise<void>; enVuelo: boolean }) {
  const denegada = error instanceof CrmApiError && error.code === '42501'
  const verificar = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    // Una revocación puede desmontar el control que tenía el foco. No pisar
    // otra interacción que ya haya elegido un destino válido.
    if (denegada && document.activeElement === document.body) verificar.current?.focus({ preventScroll: true })
  }, [denegada])
  return <div role="alert" className="gp-panel space-y-3">
    <p>{denegada ? 'Tu sesión ya no tiene permiso para consultar esta información.' : 'No pudimos confirmar las cifras. Esto no significa que no haya actividad; los datos anteriores se han ocultado.'}</p>
    {denegada ? <Button ref={verificar} variant="outline" className="min-h-11 text-base" onClick={() => window.location.reload()}>Verificar sesión</Button>
      : <Button variant="outline" className="min-h-11 text-base" onClick={() => void recargar()} disabled={enVuelo}>Reintentar</Button>}
  </div>
}
