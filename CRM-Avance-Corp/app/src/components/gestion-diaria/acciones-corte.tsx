import { useEffect, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { estadoCorte, type AvisoCorte } from '@/lib/gestion-diaria-avisos'
import { mensajeDeError } from '@/data/crm-api'
import { esFocoHuerfano } from '@/lib/foco'

export function AccionesCorte({ aviso, alConfirmar }: { aviso: AvisoCorte; alConfirmar?: () => void }) {
  const contexto = useGestionDiariaAvisos()
  const [error, setError] = useState<string | null>(null)
  const [enCurso, setEnCurso] = useState(false)
  const estado = useRef<HTMLParagraphElement>(null)
  const origen = useRef<HTMLButtonElement | null>(null)
  const rescatar = useRef(false)
  useEffect(() => {
    if (enCurso || !rescatar.current) return
    rescatar.current = false
    if (esFocoHuerfano(origen.current)) (error ? origen.current : estado.current)?.focus({ preventScroll: true })
  }, [enCurso, error])
  const ejecutar = async (accion: 'reconocer' | 'posponer') => {
    if (!contexto || contexto.ocupada || enCurso) return
    origen.current = document.activeElement instanceof HTMLButtonElement ? document.activeElement : null
    setEnCurso(true)
    setError(null)
    try { await contexto.actuar(aviso, accion); alConfirmar?.() }
    catch (e) { setError(mensajeDeError(e, 'No se pudo confirmar la acción. Puedes reintentar.')) }
    finally { rescatar.current = true; setEnCurso(false) }
  }
  return <div className="space-y-2 text-base">
    <p ref={estado} tabIndex={-1}>{estadoCorte(aviso)}</p>
    {aviso.estado !== 'reconocido' && <div className="flex flex-wrap gap-2">
      <Button className="min-h-11 text-base" disabled={!contexto || contexto.ocupada || enCurso}
        onClick={() => { void ejecutar('reconocer') }}>Lo estoy atendiendo</Button>
      {aviso.puede_posponer && <Button variant="outline" className="min-h-11 text-base" disabled={!contexto || contexto.ocupada || enCurso}
        onClick={() => { void ejecutar('posponer') }}>Posponer 1 hora</Button>}
    </div>}
    {enCurso && <p role="status">Confirmando en el servidor…</p>}
    {error && <p role="alert" className="text-[var(--warning-text)]">{error}</p>}
  </div>
}
