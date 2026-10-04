// «Quitar No contactar» (D5, F4): Supervisión y Gerencia levantan la marca desde la ficha de la base, con motivo
// obligatorio (queda en el historial). La puerta (`crm.levantar_no_contactar`, B2) la levanta para la PERSONA y TODOS
// sus leads: el diálogo lo dice antes de confirmar. Supervisión solo puede si la persona entera es de su equipo; si
// no, el servidor responde 42501 y aquí se lee «pídelo a Gerencia». Un choque con otra sesión (40001) pide reintentar.
import { useId, useState, type JSX, type RefObject } from 'react'
import { toast } from 'sonner'
import { ShieldCheck } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { CrmApiError } from '@/data/crm-api'
import { useLevantarNoContactarBase } from '@/data/crm-queries'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import { cn } from '@/lib/utils'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'

const AREA = cn('w-full rounded-lg border border-input bg-background px-3 py-2 text-sm text-foreground placeholder:text-[var(--muted-foreground-strong)] aria-[invalid=true]:border-[var(--destructive-text)]', FOCO)
const MOTIVO_MINIMO = 5

export function QuitarNoContactar({ fila, demo, onHecho, focoTrasQuitar }: {
  fila: FilaBaseGestion
  demo: boolean
  /** Hecho, el botón desaparece (el lead ya no está vetado): el foco va aquí en vez de perderse. */
  focoTrasQuitar?: RefObject<HTMLElement | null> | undefined
  /** Ya se levantó: cuántos leads de la persona dejaron de estar vetados. */
  onHecho: (leadsAfectados: number) => void
}): JSX.Element {
  const id = useId()
  const mutacion = useLevantarNoContactarBase()
  const [abierto, setAbierto] = useState(false)
  const [hecho, setHecho] = useState(false)
  const [motivo, setMotivo] = useState('')
  // Solo el motivo corto marca el campo como inválido; un rechazo del servidor se dice, pero no culpa al campo.
  const [error, setError] = useState<{ tipo: 'motivo' | 'envio'; texto: string } | null>(null)
  const cerrar = () => { if (mutacion.isPending) return; setMotivo(''); setError(null); setAbierto(false) }

  async function confirmar() {
    if (mutacion.isPending) return
    if (motivo.trim().length < MOTIVO_MINIMO) { setError({ tipo: 'motivo', texto: `Escribe el motivo (mínimo ${MOTIVO_MINIMO} caracteres): por ejemplo, «volvió a pedir información por WhatsApp».` }); return }
    if (demo) { toast.info('En la demo no se quita la marca'); return }
    setError(null)
    try {
      const { leadsAfectados } = await mutacion.mutateAsync({ leadId: fila.lead_id, motivo })
      setMotivo('')
      setHecho(true)
      setAbierto(false)
      onHecho(leadsAfectados)
    } catch (causa: unknown) {
      setError({ tipo: 'envio', texto: causa instanceof CrmApiError ? causa.message : 'No se pudo quitar la marca. Inténtalo de nuevo.' })
    }
  }

  return (
    <>
      <Button type="button" variant="outline" size="sm" className="pointer-coarse:h-11" onClick={() => { setHecho(false); setAbierto(true) }}>
        <ShieldCheck aria-hidden /> Quitar «No contactar»
      </Button>
      <Dialog open={abierto} onClose={cerrar} focoAlCerrar={hecho ? focoTrasQuitar : undefined}>
        <DialogHeader>
          <DialogTitle>Quitar «No contactar» a {fila.nombre_completo}</DialogTitle>
          <DialogDescription id={`${id}-consecuencia`} className="text-sm">
            Se levanta para la persona y todos sus leads: el equipo podrá volver a llamarlos. Queda en el historial con tu motivo.
          </DialogDescription>
        </DialogHeader>
        <DialogBody>
          <label htmlFor={`${id}-motivo`} className="mb-1 block text-sm font-semibold text-foreground">Motivo</label>
          <textarea
            id={`${id}-motivo`}
            rows={3}
            maxLength={500}
            required
            value={motivo}
            onChange={(e) => { setMotivo(e.target.value); setError(null) }}
            aria-invalid={error?.tipo === 'motivo' || undefined}
            aria-describedby={`${id}-consecuencia ${id}-ayuda${error ? ` ${id}-error` : ''}`}
            className={AREA}
            placeholder="Por ejemplo: volvió a pedir información por WhatsApp"
          />
          <p id={`${id}-ayuda`} className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">Obligatorio · mínimo {MOTIVO_MINIMO} caracteres · sin números de documento</p>
          {error && <p id={`${id}-error`} role="alert" className="mt-2 text-sm font-medium text-[var(--destructive-text)]">{error.texto}</p>}
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="ghost" className="pointer-coarse:h-11" onClick={cerrar}>Cancelar</Button>
          <Button type="button" className="pointer-coarse:h-11" aria-disabled={mutacion.isPending || undefined} aria-describedby={`${id}-consecuencia`} onClick={() => void confirmar()}>
            {mutacion.isPending ? 'Quitando…' : 'Quitar la marca'}
          </Button>
        </DialogFooter>
      </Dialog>
    </>
  )
}
