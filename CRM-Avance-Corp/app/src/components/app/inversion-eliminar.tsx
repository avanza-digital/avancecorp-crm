import { useId, useRef, useState } from 'react'
import { LoaderCircle, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { mensajeDeError } from '@/data/crm-api'
import { money } from '@/lib/format'
import {
  EMPRESA_NOMBRE, MOTIVO_ELIMINACION_MAX, MOTIVO_ELIMINACION_MIN, largoMotivoEliminacion, motivoEliminacionValido,
  type InversionFuente,
} from '@/lib/inversionistas'

/** La palabra de la confirmación: exacta y en mayúsculas. */
const PALABRA_CONFIRMACION = 'ELIMINAR'

/**
 * «Eliminar inversión» con motivo obligatorio y confirmación escrita. La pantalla
 * solo evita el clic suelto: quién puede y si la inversión se puede eliminar
 * (historia propia, conversión de un lead) lo decide el servidor, y su mensaje se
 * muestra tal cual.
 */
export function InversionEliminar({ inversion, onConfirmar, onCerrar }: {
  inversion: InversionFuente
  onConfirmar: (inversion: InversionFuente, motivo: string) => Promise<void>
  onCerrar: () => void
}) {
  const [motivo, setMotivo] = useState('')
  const [confirmacion, setConfirmacion] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const enCurso = useRef(false)
  const id = useId()
  const largo = largoMotivoEliminacion(motivo)
  const excedido = largo > MOTIVO_ELIMINACION_MAX
  const listo = motivoEliminacionValido(motivo) && confirmacion.trim() === PALABRA_CONFIRMACION
  const titulo = `Eliminar inversión ${inversion.numero || `en ${EMPRESA_NOMBRE[inversion.empresa]}`}`
  async function confirmar() {
    if (enCurso.current || !listo) return
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      await onConfirmar(inversion, motivo.trim())
      onCerrar()
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo eliminar la inversión. Reintenta o consulta al administrador.'))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }
  return <Dialog open onClose={() => { if (!enCurso.current) onCerrar() }} ariaLabel={titulo}>
    <DialogHeader><DialogTitle>{titulo}</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
        <dt className="text-muted-foreground">Empresa</dt><dd className="font-semibold">{EMPRESA_NOMBRE[inversion.empresa]}</dd>
        <dt className="text-muted-foreground">Capital</dt><dd className="font-semibold tabular-nums">{money(inversion.capital, inversion.moneda)}</dd>
        <dt className="text-muted-foreground">Referencia</dt><dd className="[overflow-wrap:anywhere]">{inversion.numero || 'Inversión registrada'}</dd>
      </dl>
      <p id={`${id}-aviso`} className="text-sm">La inversión saldrá del capital, de la cartera y de la conversión. Se guardará una copia de auditoría con tu motivo y tu nombre. Esta acción no se deshace.</p>
      {inversion.es_inicial && <p id={`${id}-conversion`} className="text-sm font-semibold text-warning-text">Si es la conversión de un lead, también se anula (solo gerencia).</p>}
      <div className="space-y-2">
        <Label htmlFor={`${id}-motivo`}>Motivo de la eliminación</Label>
        {/* El foco entra aquí: la consecuencia se oye antes de escribir, no solo al recorrer el diálogo. */}
        <Textarea id={`${id}-motivo`} rows={3} value={motivo} disabled={enviando}
          placeholder="Por ejemplo: se registró dos veces por error"
          aria-invalid={excedido || undefined}
          aria-describedby={[`${id}-aviso`, inversion.es_inicial ? `${id}-conversion` : null, `${id}-contador`].filter(Boolean).join(' ')}
          onChange={e => setMotivo(e.target.value)} />
        <p id={`${id}-contador`} className={excedido ? 'text-xs font-semibold text-destructive-text' : 'text-xs text-muted-foreground'}>
          {largo} de {MOTIVO_ELIMINACION_MAX} caracteres · mínimo {MOTIVO_ELIMINACION_MIN}
        </p>
        {/* Montada desde el inicio: se anuncia al pasarse del tope, cuando el botón queda inactivo. */}
        <p role="status" className="sr-only">{excedido ? `El motivo pasa de ${MOTIVO_ELIMINACION_MAX} caracteres: acórtalo para poder eliminar.` : ''}</p>
      </div>
      <div className="space-y-2">
        <Label htmlFor={`${id}-confirmacion`}>Escribe {PALABRA_CONFIRMACION} para confirmar</Label>
        <Input id={`${id}-confirmacion`} value={confirmacion} disabled={enviando}
          autoComplete="off" autoCapitalize="characters" spellCheck={false} aria-describedby={`${id}-mayusculas`}
          onChange={e => setConfirmacion(e.target.value)} />
        <p id={`${id}-mayusculas`} className="text-xs text-muted-foreground">Tal cual, en mayúsculas.</p>
      </div>
      {error && <p role="alert" className="text-sm text-destructive-text">{error}</p>}
    </DialogBody>
    <DialogFooter className="flex-wrap">
      <Button variant="outline" disabled={enviando} onClick={onCerrar}>Cancelar</Button>
      {/* Mientras envía, `aria-disabled` y no `disabled`: deshabilitar de verdad tira el
          foco a <body> y Radix no lo rescata (ver anular-cierre-avance). `enCurso`
          impide el segundo envío. */}
      <Button variant="destructive" disabled={!listo} aria-disabled={enviando || undefined} aria-busy={enviando || undefined}
        className={enviando ? 'pointer-events-none opacity-50' : undefined} onClick={() => void confirmar()}>
        {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : <Trash2 aria-hidden />}
        {enviando ? 'Eliminando…' : 'Eliminar inversión'}
      </Button>
    </DialogFooter>
  </Dialog>
}
