// Acciones de la ficha de la base (F2): «Reactivar» (vuelve a la cartera como Contactado, ciclo nuevo: D1/D2) y
// «No contactar» (No insista, Ley 29571: el lead sale de la base y nadie puede volver a llamarlo; quitar la marca
// lo decide Supervisión o Gerencia: D5). Las dos confirman en un diálogo. Reactivar es idempotente por
// `p_operacion_id`: el id nace al abrir el diálogo y se reusa en un reintento con la misma nota.
// Bases cargadas (F6, E8 de Miguel): un contacto de archivo puede no tener capital; el pipeline, la cartera y la conversión
// nunca reciben un lead sin capital, así que «Reactivar» lo PIDE (con su moneda) cuando falta. Con capital, nada cambia.
import { useId, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { ArchiveRestore, Ban } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { CrmApiError } from '@/data/crm-api'
import { useMarcarNoContactarBase, useReactivarLeadBase } from '@/data/crm-queries'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import { normalizarCapital } from '@/lib/bases-cargadas'
import type { Moneda } from '@/lib/format'
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
  // En el pie fijo de la ficha, como «Descartar · Convertir» en la del lead (Miguel, 03/10): lo que saca al lead de
  // la base a la izquierda y en rojo; lo que lo devuelve a la cartera a la derecha, como acción principal. Quien lo
  // monta pone el contenedor (`SheetFooter`); los diálogos van en portal y no ocupan sitio en él.
  return (
    <>
      <Button
        type="button"
        variant="outline"
        size="sm"
        // El rojo de TEXTO (--destructive-text): el rojo de relleno no llega a 4,5:1 sobre el tinte del hover.
        className="border-destructive/40 text-[var(--destructive-text)] hover:border-destructive/60 hover:bg-destructive/10"
        onClick={() => setDialogo('no_contactar')}
      >
        <Ban aria-hidden /> No contactar
      </Button>
      <Button type="button" size="sm" onClick={() => setDialogo('reactivar')}>
        <ArchiveRestore aria-hidden /> Reactivar
      </Button>
      <ReactivarDialogo fila={fila} demo={demo} abierto={dialogo === 'reactivar'} onCerrar={() => setDialogo(null)} onHecho={onReactivado} />
      <NoContactarDialogo fila={fila} demo={demo} abierto={dialogo === 'no_contactar'} onCerrar={() => setDialogo(null)} onHecho={onNoContactar} />
    </>
  )
}

function ReactivarDialogo({ fila, demo, abierto, onCerrar, onHecho }: { fila: FilaBaseGestion; demo: boolean; abierto: boolean; onCerrar: () => void; onHecho: () => void }) {
  const id = useId()
  const mutacion = useReactivarLeadBase()
  const [nota, setNota] = useState('')
  // E8: sin capital, el diálogo lo pide (obligatorio) con su moneda; con capital, ni se muestra.
  const pideCapital = fila.monto_estimado === null
  const [capital, setCapital] = useState('')
  const [moneda, setMoneda] = useState<Moneda>(fila.moneda ?? 'PEN')
  const [error, setError] = useState<{ tipo: 'capital' | 'envio'; texto: string } | null>(null)
  // El MISMO contenido reusa su id de operación (un doble clic o un reintento devuelven la respuesta original).
  const envio = useRef<{ id: string; firma: string } | null>(null)
  const cerrar = () => { if (mutacion.isPending) return; setNota(''); setCapital(''); setError(null); envio.current = null; onCerrar() }

  async function confirmar() {
    if (mutacion.isPending) return
    const monto = pideCapital ? normalizarCapital(capital) : null
    if (pideCapital && monto === null) {
      setError({ tipo: 'capital', texto: 'Indica el capital estimado (un número mayor que 0) para reactivarlo: el pipeline no recibe leads sin capital.' })
      return
    }
    if (demo) { toast.info('En la demo no se reactiva'); return }
    setError(null)
    const firma = JSON.stringify([nota.trim(), monto, pideCapital ? moneda : null])
    if (envio.current?.firma !== firma) envio.current = { id: crypto.randomUUID(), firma }
    try {
      await mutacion.mutateAsync({
        operacionId: envio.current.id, leadId: fila.lead_id, nota,
        ...(monto !== null ? { montoEstimado: Number(monto), moneda } : {}),
      })
      setNota(''); setCapital(''); envio.current = null
      onCerrar()
      onHecho()
    } catch (causa: unknown) {
      setError({ tipo: 'envio', texto: causa instanceof CrmApiError ? causa.message : 'No se pudo reactivar. Inténtalo de nuevo.' })
    }
  }
  const describe = `${id}-consecuencia${error ? ` ${id}-error` : ''}`

  return (
    <Dialog open={abierto} onClose={cerrar}>
      <DialogHeader>
        <DialogTitle>¿Reactivar a {fila.nombre_completo}?</DialogTitle>
        <DialogDescription id={`${id}-consecuencia`} className="text-sm">Vuelve a tu cartera como Contactado, con un ciclo nuevo, y sale de tu base.</DialogDescription>
      </DialogHeader>
      <DialogBody>
        {pideCapital && (
          <div className="mb-4 grid grid-cols-[1fr_8rem] gap-3">
            <div>
              <label htmlFor={`${id}-capital`} className="mb-1 block text-sm font-semibold text-foreground">Capital estimado</label>
              <Input
                id={`${id}-capital`}
                inputMode="decimal"
                autoComplete="off"
                required
                value={capital}
                onChange={(e) => { setCapital(e.target.value); if (error?.tipo === 'capital') setError(null) }}
                aria-invalid={error?.tipo === 'capital' || undefined}
                aria-describedby={`${id}-ayuda-capital${error?.tipo === 'capital' ? ` ${id}-error` : ''}`}
                placeholder="Por ejemplo: 20000"
                className="h-10"
              />
            </div>
            <div>
              <label htmlFor={`${id}-moneda`} className="mb-1 block text-sm font-semibold text-foreground">Moneda</label>
              <Select id={`${id}-moneda`} value={moneda} onChange={(e) => setMoneda(e.target.value === 'USD' ? 'USD' : 'PEN')} className="h-10">
                <option value="PEN">Soles (S/)</option>
                <option value="USD">Dólares (US$)</option>
              </Select>
            </div>
            <p id={`${id}-ayuda-capital`} className="col-span-2 text-[13px] text-[var(--muted-foreground-strong)]">
              Este contacto llegó sin capital. Es obligatorio para volver al pipeline.
            </p>
          </div>
        )}
        <label htmlFor={`${id}-nota`} className="mb-1 block text-sm font-semibold text-foreground">Nota <span className="font-normal text-[var(--muted-foreground-strong)]">(opcional)</span></label>
        {/* La consecuencia (sale de tu base) se lee con el campo y con el botón, como en «No contactar» (WCAG 1.3.1). */}
        <textarea
          id={`${id}-nota`}
          rows={3}
          maxLength={1000}
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          aria-describedby={describe}
          className={AREA}
          placeholder="Por qué lo retomas"
        />
        {error && <p id={`${id}-error`} role="alert" className="mt-2 text-sm font-medium text-[var(--destructive-text)]">{error.texto}</p>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="ghost" onClick={cerrar}>Cancelar</Button>
        <Button type="button" aria-disabled={mutacion.isPending || undefined} aria-describedby={describe} onClick={() => void confirmar()}>
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
