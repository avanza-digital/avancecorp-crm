import { useState } from 'react'
import { usePanelesActions } from '@/lib/store-context'
import { abrirInversionista } from '@/lib/router'
import { Dialog } from '@/components/ui/dialog'
import { ClienteDetalle } from '@/components/app/cliente-detalle'

export interface SujetoGestion {
  lead_id?: string | null | undefined
  lead_nombre?: string | null | undefined
  sujeto_nombre?: string | undefined
  sujeto_tipo?: 'lead' | 'perfil' | 'inversionista' | undefined
  inversionista_id?: string | null | undefined
  perfil_id?: string | null | undefined
  identidad_visible?: boolean | undefined
}

/** El servidor entrega el destino autorizado; jamás se trata un cliente como lead. */
export function EnlaceSujetoGestion({ sujeto, className }: { sujeto: SujetoGestion; className?: string }) {
  const { abrirLead } = usePanelesActions()
  const [perfil, setPerfil] = useState<string | null>(null)
  const nombre = sujeto.sujeto_nombre ?? sujeto.lead_nombre ?? 'Persona no visible'
  const visible = sujeto.identidad_visible !== false && Boolean(sujeto.lead_id || sujeto.inversionista_id || sujeto.perfil_id)
  return <>
    {visible ? <button type="button" className={className ?? 'rounded-md text-left font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'} onClick={() => {
      if (sujeto.inversionista_id) abrirInversionista(sujeto.inversionista_id)
      else if (sujeto.perfil_id) setPerfil(sujeto.perfil_id)
      else if (sujeto.lead_id) void abrirLead(sujeto.lead_id)
    }}>{nombre}</button> : <span className="text-muted-foreground">{nombre}</span>}
    <Dialog open={perfil !== null && visible} onClose={() => setPerfil(null)} ariaLabel="Ficha del cliente">
      {perfil && visible && <ClienteDetalle clienteId={perfil} onCerrar={() => setPerfil(null)} />}
    </Dialog>
  </>
}
