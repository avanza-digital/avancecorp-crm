import { useRef, useState } from 'react'
import { LoaderCircle, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { money } from '@/lib/format'
import type { InversionFuente } from '@/lib/inversionistas'
import { mensajeErrorEliminacionContrato } from '@/lib/contrato-pdf-archivo'

/** Confirmación explícita; el servidor decide si el contrato puede borrarse. */
export function ContratoEliminar({ inversion, onConfirmar, onCerrar }: {
  inversion: InversionFuente
  onConfirmar: (inversion: InversionFuente) => Promise<void>
  onCerrar: () => void
}) {
  const [confirmacion, setConfirmacion] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const enCurso = useRef(false)
  const referencia = inversion.numero || inversion.fuente_id
  async function confirmar() {
    if (enCurso.current || confirmacion.trim() !== referencia) return
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      await onConfirmar(inversion)
      onCerrar()
    } catch (e) {
      setError(mensajeErrorEliminacionContrato(e))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }
  return <Dialog open onClose={() => { if (!enCurso.current) onCerrar() }} ariaLabel={`Eliminar contrato ${referencia}`}>
    <DialogHeader><DialogTitle>Eliminar contrato {referencia}</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <p className="text-sm">Capital: <strong>{money(inversion.capital, inversion.moneda)}</strong>.</p>
      <p className="text-sm">El contrato y su cronograma saldrán de la operación del CRM, incluidos los pagos registrados. Se conservará una copia de auditoría de los datos y sus documentos PDF.</p>
      <p className="text-xs text-muted-foreground">Si el contrato ya figura en la cartera multiempresa, su inversión se archiva y se retira con él, salvo que tenga eventos, solicitudes, ajustes de mes cerrado o vínculos históricos de cotitulares registrados. El servidor comprobará si este contrato se puede eliminar.</p>
      <div className="space-y-2">
        <Label htmlFor="confirmar-eliminacion-contrato">Escribe {referencia} para confirmar</Label>
        <Input id="confirmar-eliminacion-contrato" value={confirmacion} disabled={enviando}
          autoComplete="off" onChange={e => setConfirmacion(e.target.value)} />
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </DialogBody>
    <DialogFooter className="flex-wrap">
      <Button variant="outline" disabled={enviando} onClick={onCerrar}>Cancelar</Button>
      <Button variant="destructive" disabled={enviando || confirmacion.trim() !== referencia} onClick={() => void confirmar()}>
        {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : <Trash2 aria-hidden />}
        {enviando ? 'Eliminando…' : 'Eliminar y conservar auditoría'}
      </Button>
    </DialogFooter>
  </Dialog>
}
