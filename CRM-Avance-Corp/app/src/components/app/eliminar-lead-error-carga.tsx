import { useId, useRef, useState } from 'react'
import { LoaderCircle, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { mensajeDeError } from '@/data/crm-api'
import { fmtFecha } from '@/lib/format'
import {
  MOTIVO_ELIMINAR_LEAD_MAX, MOTIVO_ELIMINAR_LEAD_MIN, largoMotivoEliminarLead, motivoEliminarLeadValido,
} from '@/lib/lead-error-carga'
import { origenLabel, type Lead } from '@/lib/tipos'

/** La palabra de la confirmación: exacta y en mayúsculas. */
const PALABRA = 'ELIMINAR'

/**
 * «Eliminar lead (error de carga)» con motivo obligatorio y confirmación escrita.
 * La pantalla solo evita el clic suelto: quién puede y si ESTE lead se puede borrar
 * (contrato, conversión, antigüedad, mes cerrado…) lo decide el servidor, y su
 * mensaje se muestra tal cual. Mientras envía, el diálogo no se cierra.
 */
export function EliminarLeadErrorCarga({ lead, onConfirmar, onCerrar }: {
  lead: Pick<Lead, 'nombre_completo' | 'origen' | 'creado_en'>
  onConfirmar: (motivo: string) => Promise<void>
  onCerrar: () => void
}) {
  const [motivo, setMotivo] = useState('')
  const [palabra, setPalabra] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const enCurso = useRef(false)
  const refMotivo = useRef<HTMLTextAreaElement>(null)
  const id = useId()
  const largo = largoMotivoEliminarLead(motivo)
  const pasado = largo > MOTIVO_ELIMINAR_LEAD_MAX
  const listo = motivoEliminarLeadValido(motivo) && palabra.trim() === PALABRA
  const titulo = 'Eliminar lead (error de carga)'
  const cerrar = () => { if (!enCurso.current) onCerrar() }
  async function eliminar() {
    if (enCurso.current || !listo) return
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      await onConfirmar(motivo.trim())
      onCerrar()
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo eliminar el lead. Reintenta o consulta al administrador.'))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }
  return <Dialog open onClose={cerrar} ariaLabel={titulo} focoInicial={refMotivo}>
    <DialogHeader><DialogTitle>{titulo}</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
        <dt className="text-muted-foreground">Lead</dt>
        <dd className="font-semibold [overflow-wrap:anywhere]">{lead.nombre_completo}</dd>
        <dt className="text-muted-foreground">Origen</dt><dd>{origenLabel(lead.origen)}</dd>
        <dt className="text-muted-foreground">Registrado</dt><dd className="tabular-nums">{fmtFecha(lead.creado_en)}</dd>
      </dl>
      <div id={`${id}-aviso`} className="space-y-2 text-sm">
        <p>Úsalo solo si el lead se cargó por error. Se borrará el lead junto con sus tareas, sus actividades y su historial de asignación.</p>
        <p>Antes de borrarlo se guarda una copia de auditoría con tu motivo y tu nombre. Esta acción no se deshace.</p>
        <p className="text-muted-foreground">Si el lead ya tiene contrato o conversión, se registró hace más de 30 días o es de un mes cerrado, no se podrá eliminar y verás el motivo.</p>
      </div>
      <div className="space-y-2">
        <Label htmlFor={`${id}-motivo`}>Motivo de la eliminación</Label>
        <Textarea ref={refMotivo} id={`${id}-motivo`} rows={3} value={motivo} disabled={enviando}
          placeholder="Por ejemplo: se cargó dos veces el mismo contacto"
          aria-invalid={pasado || undefined}
          aria-describedby={`${id}-aviso ${id}-contador`}
          onChange={e => setMotivo(e.target.value)} />
        <p id={`${id}-contador`} className={pasado ? 'text-sm font-semibold text-destructive-text' : 'text-sm text-muted-foreground'}>
          {largo} de {MOTIVO_ELIMINAR_LEAD_MAX} caracteres · mínimo {MOTIVO_ELIMINAR_LEAD_MIN}
        </p>
        {/* Montada desde el inicio: se anuncia al pasarse del tope, cuando el botón queda inactivo. */}
        <p role="status" className="sr-only">{pasado ? `El motivo pasa de ${MOTIVO_ELIMINAR_LEAD_MAX} caracteres: acórtalo para poder eliminar.` : ''}</p>
      </div>
      <div className="space-y-2">
        <Label htmlFor={`${id}-palabra`}>Escribe {PALABRA} para confirmar</Label>
        <Input id={`${id}-palabra`} value={palabra} disabled={enviando}
          autoComplete="off" autoCapitalize="characters" spellCheck={false} aria-describedby={`${id}-tal-cual`}
          onChange={e => setPalabra(e.target.value)} />
        <p id={`${id}-tal-cual`} className="text-sm text-muted-foreground">Tal cual, en mayúsculas.</p>
      </div>
      {error && <p role="alert" className="text-sm text-destructive-text [overflow-wrap:anywhere]">{error}</p>}
    </DialogBody>
    <DialogFooter className="flex-wrap">
      <Button variant="outline" disabled={enviando} onClick={cerrar}>Cancelar</Button>
      {/* Mientras envía, `aria-disabled` y no `disabled`: deshabilitar de verdad tira el
          foco a <body> y Radix no lo rescata. `enCurso` impide el segundo envío. */}
      <Button variant="destructive" disabled={!listo} aria-disabled={enviando || undefined} aria-busy={enviando || undefined}
        className={enviando ? 'pointer-events-none opacity-50' : undefined} onClick={() => void eliminar()}>
        {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : <Trash2 aria-hidden />}
        {enviando ? 'Eliminando…' : 'Eliminar lead'}
      </Button>
    </DialogFooter>
  </Dialog>
}
