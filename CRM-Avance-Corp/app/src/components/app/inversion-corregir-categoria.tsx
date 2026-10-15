import { useId, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { mensajeDeError } from '@/data/crm-api'
import { CATEGORIAS_CONTRATO_UI } from '@/lib/contratos-catalogo'
import type { CategoriaContrato } from '@/lib/cronograma'
import type { InversionFuente } from '@/lib/inversionistas'

export type CorregirCategoria = (inversion: InversionFuente, categoria: CategoriaContrato, motivo: string) => Promise<void>

export function InversionCorregirCategoria({inversion, onConfirmar, onCerrar}: {
  inversion: InversionFuente; onConfirmar: CorregirCategoria; onCerrar: () => void
}) {
  const id = useId()
  const actual = CATEGORIAS_CONTRATO_UI.find(c => c.k === inversion.contrato?.categoria)
  const [categoria, setCategoria] = useState<CategoriaContrato | ''>(actual?.k ?? '')
  const [motivo, setMotivo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const enCurso = useRef(false)
  const largo = Array.from(motivo.trim()).length
  const listo = categoria !== '' && categoria !== actual?.k && largo >= 5 && largo <= 300
  async function confirmar() {
    if (enCurso.current || !listo || !categoria) return
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      await onConfirmar(inversion, categoria, motivo.trim())
      onCerrar()
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo corregir la categoría. Vuelve a intentarlo.'))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }
  return <Dialog open onClose={() => {if (!enCurso.current) onCerrar()}} ariaLabel="Corregir categoría de inversión">
    <DialogHeader><DialogTitle>Corregir categoría de inversión</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <p className="text-sm">Contrato {inversion.numero || 'Avance'} · Categoría actual: <strong>{actual?.label ?? 'Sin categoría'}</strong></p>
      <div className="space-y-2">
        <Label htmlFor={`${id}-categoria`}>Categoría correcta</Label>
        <Select id={`${id}-categoria`} value={categoria} disabled={enviando} onChange={e => {
          const elegida = CATEGORIAS_CONTRATO_UI.find(c => c.k === e.target.value)
          setCategoria(elegida?.k ?? '')
        }}>
          {!actual && <option value="">Selecciona una categoría</option>}
          {CATEGORIAS_CONTRATO_UI.map(c => <option key={c.k} value={c.k}>{c.label}</option>)}
        </Select>
      </div>
      <p id={`${id}-efecto`} className="text-sm">La corrección actualizará la clasificación, la conversión y el ranking. Se guardarán tu nombre y el motivo. Los meses sellados no se pueden corregir.</p>
      <div className="space-y-2">
        <Label htmlFor={`${id}-motivo`}>Motivo de la corrección</Label>
        <Textarea id={`${id}-motivo`} rows={3} value={motivo} disabled={enviando}
          placeholder="Por ejemplo: el analista seleccionó Nuevo por error"
          aria-describedby={`${id}-efecto ${id}-contador`} aria-invalid={largo > 300 || undefined}
          onChange={e => setMotivo(e.target.value)} />
        <p id={`${id}-contador`} className="text-xs text-muted-foreground">{largo} de 300 caracteres · mínimo 5</p>
      </div>
      {error && <p role="alert" className="text-sm text-destructive-text">{error}</p>}
    </DialogBody>
    <DialogFooter>
      <Button variant="outline" disabled={enviando} onClick={onCerrar}>Cancelar</Button>
      <Button disabled={!listo} aria-disabled={enviando || undefined} aria-busy={enviando || undefined}
        className={enviando ? 'pointer-events-none opacity-50' : undefined} onClick={() => void confirmar()}>
        {enviando ? 'Guardando…' : 'Guardar corrección'}
      </Button>
    </DialogFooter>
  </Dialog>
}
