// Acciones de la ficha de la base (F2): «Reactivar» (vuelve a la cartera como Contactado, ciclo nuevo: D1/D2) y
// «No contactar» (No insista, Ley 29571: el lead sale de la base y nadie puede volver a llamarlo; quitar la marca
// lo decide Supervisión o Gerencia: D5). Las dos confirman en un diálogo. Reactivar es idempotente por
// `p_operacion_id`: el id nace al abrir el diálogo y se reusa en un reintento con la misma nota.
import { useId, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { ArchiveRestore, Ban } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { CrmApiError } from '@/data/crm-api'
import { useMarcarNoContactarBase, useReactivarLeadBase } from '@/data/crm-queries'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import { cn } from '@/lib/utils'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'

const AREA = cn('w-full rounded-lg border border-input bg-background px-3 py-2 text-sm text-foreground placeholder:text-[var(--muted-foreground-strong)] aria-[invalid=true]:border-[var(--destructive-text)]', FOCO)
const MOTIVO_MINIMO = 5

export function AccionesBase({ fila, demo, onReactivado, onNoContactar }: {
  fila: FilaBaseGestion
  demo: boolean
  onReactivado: () => void
  onNoContactar: () => void
}): JSX.Element {
  const [dialogo, setDialogo] = useState<'reactivar' | 'no_contactar' | null>(null)
  // En la cabecera de la ficha, a la vista sin desplazarse (Miguel: lo que se usa, arriba y en horizontal).
  return (
    <div role="group" aria-label="Acciones del lead" className="flex flex-wrap items-center gap-2">
      <Button type="button" variant="outline" onClick={() => setDialogo('reactivar')}>
        <ArchiveRestore aria-hidden /> Reactivar
      </Button>
      <Button type="button" variant="outline" className="text-[var(--destructive-text)]" onClick={() => setDialogo('no_contactar')}>
        <Ban aria-hidden /> No contactar
      </Button>
      <ReactivarDialogo fila={fila} demo={demo} abierto={dialogo === 'reactivar'} onCerrar={() => setDialogo(null)} onHecho={onReactivado} />
      <NoContactarDialogo fila={fila} demo={demo} abierto={dialogo === 'no_contactar'} onCerrar={() => setDialogo(null)} onHecho={onNoContactar} />
    </div>
  )
}

function ReactivarDialogo({ fila, demo, abierto, onCerrar, onHecho }: { fila: FilaBaseGestion; demo: boolean; abierto: boolean; onCerrar: () => void; onHecho: () => void }) {
  const id = useId()
  const mutacion = useReactivarLeadBase()
  const [nota, setNota] = useState('')
  const [error, setError] = useState<string | null>(null)
  const envio = useRef<{ id: string; nota: string } | null>(null)
  const cerrar = () => { if (mutacion.isPending) return; setNota(''); setError(null); envio.current = null; onCerrar() }

  async function confirmar() {
    if (mutacion.isPending) return
    if (demo) { toast.info('En la demo no se reactiva'); return }
    setError(null)
    if (envio.current?.nota !== nota.trim()) envio.current = { id: crypto.randomUUID(), nota: nota.trim() }
    try {
      await mutacion.mutateAsync({ operacionId: envio.current.id, leadId: fila.lead_id, nota })
      setNota(''); envio.current = null
      onCerrar()
      onHecho()
    } catch (causa: unknown) {
      setError(causa instanceof CrmApiError ? causa.message : 'No se pudo reactivar. Inténtalo de nuevo.')
    }
  }

  return (
    <Dialog open={abierto} onClose={cerrar}>
      <DialogHeader>
        <DialogTitle>¿Reactivar a {fila.nombre_completo}?</DialogTitle>
        <DialogDescription className="text-sm">Vuelve a tu cartera como Contactado, con un ciclo nuevo, y sale de tu base.</DialogDescription>
      </DialogHeader>
      <DialogBody>
        <label htmlFor={`${id}-nota`} className="mb-1 block text-sm font-semibold text-foreground">Nota <span className="font-normal text-[var(--muted-foreground-strong)]">(opcional)</span></label>
        <textarea id={`${id}-nota`} rows={3} maxLength={1000} value={nota} onChange={(e) => setNota(e.target.value)} className={AREA} placeholder="Por qué lo retomas" />
        {error && <p role="alert" className="mt-2 text-sm font-medium text-[var(--destructive-text)]">{error}</p>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="ghost" onClick={cerrar}>Cancelar</Button>
        <Button type="button" aria-disabled={mutacion.isPending || undefined} onClick={() => void confirmar()}>
          {mutacion.isPending ? 'Reactivando…' : 'Reactivar'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}

function NoContactarDialogo({ fila, demo, abierto, onCerrar, onHecho }: { fila: FilaBaseGestion; demo: boolean; abierto: boolean; onCerrar: () => void; onHecho: () => void }) {
  const id = useId()
  const mutacion = useMarcarNoContactarBase()
  const [motivo, setMotivo] = useState('')
  // Solo el motivo corto marca el campo como inválido; un fallo del servidor se dice, pero no culpa al campo.
  const [error, setError] = useState<{ tipo: 'motivo' | 'envio'; texto: string } | null>(null)
  const cerrar = () => { if (mutacion.isPending) return; setMotivo(''); setError(null); onCerrar() }

  async function confirmar() {
    if (mutacion.isPending) return
    if (motivo.trim().length < MOTIVO_MINIMO) { setError({ tipo: 'motivo', texto: `Escribe el motivo (mínimo ${MOTIVO_MINIMO} caracteres): por ejemplo, «pidió que no lo llamen más».` }); return }
    if (demo) { toast.info('En la demo no se marca'); return }
    setError(null)
    try {
      await mutacion.mutateAsync({ leadId: fila.lead_id, motivo })
      setMotivo('')
      onCerrar()
      onHecho()
    } catch (causa: unknown) {
      setError({ tipo: 'envio', texto: causa instanceof CrmApiError ? causa.message : 'No se pudo marcar. Inténtalo de nuevo.' })
    }
  }

  return (
    <Dialog open={abierto} onClose={cerrar}>
      <DialogHeader>
        <DialogTitle>Marcar «No contactar» a {fila.nombre_completo}</DialogTitle>
        <DialogDescription id={`${id}-consecuencia`} className="text-sm">
          Ley 29571 (No insista): sale de tu base y nadie podrá volver a llamarlo. Solo Supervisión o Gerencia pueden quitar la marca.
        </DialogDescription>
      </DialogHeader>
      <DialogBody>
        <label htmlFor={`${id}-motivo`} className="mb-1 block text-sm font-semibold text-foreground">Motivo</label>
        {/* El foco entra al campo: la consecuencia legal y la regla del motivo se leen con él (WCAG 1.3.1 / 3.3.2). */}
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
          placeholder="Por ejemplo: pidió que no lo llamen más"
        />
        <p id={`${id}-ayuda`} className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">Obligatorio · mínimo {MOTIVO_MINIMO} caracteres</p>
        {error && <p id={`${id}-error`} role="alert" className="mt-2 text-sm font-medium text-[var(--destructive-text)]">{error.texto}</p>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="ghost" onClick={cerrar}>Cancelar</Button>
        <Button type="button" variant="destructive" aria-disabled={mutacion.isPending || undefined} onClick={() => void confirmar()}>
          {mutacion.isPending ? 'Marcando…' : 'Marcar «No contactar»'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}
