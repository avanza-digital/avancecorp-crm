import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { estadoCorte, type AvisoCorte } from '@/lib/gestion-diaria-avisos'
import { mensajeDeError } from '@/data/crm-api'

export function AccionesCorte({ aviso, alConfirmar }: { aviso: AvisoCorte; alConfirmar?: () => void }) {
  const contexto = useGestionDiariaAvisos()
  const [error, setError] = useState<string | null>(null)
  const ejecutar = async (accion: 'reconocer' | 'posponer') => {
    if (!contexto || contexto.ocupada) return
    setError(null)
    try { await contexto.actuar(aviso, accion); alConfirmar?.() }
    catch (e) { setError(mensajeDeError(e, 'No se pudo confirmar la acción. Puedes reintentar.')) }
  }
  return <div className="space-y-2 text-base">
    <p>{estadoCorte(aviso)}</p>
    {aviso.estado !== 'reconocido' && <div className="flex flex-wrap gap-2">
      <Button className="min-h-11 text-base" disabled={!contexto || contexto.ocupada}
        onClick={() => { void ejecutar('reconocer') }}>Lo estoy atendiendo</Button>
      {aviso.puede_posponer && <Button variant="outline" className="min-h-11 text-base" disabled={!contexto || contexto.ocupada}
        onClick={() => { void ejecutar('posponer') }}>Posponer 1 hora</Button>}
    </div>}
    {contexto?.ocupada && <p role="status">Confirmando en el servidor…</p>}
    {error && <p role="alert" className="text-[var(--warning-text)]">{error}</p>}
  </div>
}
