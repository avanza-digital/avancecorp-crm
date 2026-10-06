import { WifiOff } from 'lucide-react'
import { useEstaEnLinea } from '@/lib/conexion'

export function AvisoConexionGerencia() {
  const enLinea = useEstaEnLinea()
  if (enLinea) return null
  return <p className="crm-conexion" role="status"><WifiOff size={16} aria-hidden /><span>Sin conexión. Los datos pueden estar desactualizados; se actualizarán al volver la red.</span></p>
}
