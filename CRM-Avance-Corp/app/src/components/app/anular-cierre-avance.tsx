/**
 * Anular un cierre de AVANCE — el freno de gerencia contra un error de gestión o
 * una mala práctica.
 *
 * Regla de Miguel (2026-08-13): «si gerencia anula un cierre tiene que afectar en
 * la conversión sí o sí», con el alcance que él mismo puso: lo que baja «no
 * significa dinero real, solo baja para el analista». Por eso el texto no dice
 * que se devuelva nada ni que el cliente desaparezca — no pasa: el contrato y el
 * cliente siguen intactos, lo único que cambia es a quién se le acredita.
 *
 * Paso de confirmación aparte y motivo obligatorio, igual que en cooperativas:
 * esto le quita mérito a una persona y no puede ser un clic suelto. No se
 * deshace.
 */
import { useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import {
  Dialog,
  DialogBody,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { CrmApiError } from '@/data/crm-api'
import { useAnularCierreAvance } from '@/data/crm-queries'
import { useCRMData } from '@/lib/store-context'
import type { Lead } from '@/lib/tipos'

/** Tope del motivo, espejo del CHECK de `crm.cierres_avance_anulados`. */
const MOTIVO_MAX = 300

export function AnularCierreAvanceDialog({
  lead,
  demo,
  onCerrar,
}: {
  lead: Lead
  demo: boolean
  onCerrar: () => void
}) {
  const { anularCierreAvance, recargar } = useCRMData()
  const anularMut = useAnularCierreAvance()
  const [motivo, setMotivo] = useState('')
  const [error, setError] = useState<string | null>(null)
  /** Separado de `error`: un fallo del servidor NO deja inválido un motivo que
   *  estaba bien escrito, o el usuario lo reescribe sin necesidad. */
  const [motivoInvalido, setMotivoInvalido] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const refMotivo = useRef<HTMLTextAreaElement>(null)

  // El foco va al motivo: es el único campo que hay que llenar, y sin esto solo
  // llega por rebote al tope del diálogo.
  useEffect(() => {
    refMotivo.current?.focus()
  }, [])

  async function confirmar() {
    if (enviando) return
    const limpio = motivo.trim()
    if (!limpio) {
      setMotivoInvalido(true)
      setError('Escribe el motivo de la anulación')
      return
    }
    if (limpio.length > MOTIVO_MAX) {
      setMotivoInvalido(true)
      setError(`El motivo admite como máximo ${MOTIVO_MAX} caracteres`)
      return
    }
    setError(null)
    setMotivoInvalido(false)

    if (demo) {
      const res = anularCierreAvance(lead.id, limpio)
      if (!res.ok) {
        setError(res.error ?? 'No se pudo anular el cierre')
        return
      }
      toast.success('Cierre anulado (demo): ya no cuenta en cuota ni conversión')
      onCerrar()
      return
    }

    setEnviando(true)
    try {
      const res = await anularMut.mutateAsync({ leadId: lead.id, motivo: limpio })
      // El cumplimiento de metas NO vive en TanStack (lo carga el store), así que
      // la invalidación de la mutación no lo alcanza. Sin este `recargar`, la
      // pantalla restaría cifras frescas de un cumplimiento viejo — es el bug que
      // ya se midió al anular en cooperativas.
      await recargar()
      // Se dice lo que DE VERDAD se movió en vez de un «listo» genérico: la RPC
      // devuelve los contratos que dejan de acreditar, y cero contratos con la
      // conversión bajando igual es un resultado correcto (el mérito sale del
      // ledger, el dinero de los contratos) que sin explicar parecería un fallo.
      toast.success(
        res.afectaCuota
          ? `Cierre anulado: ${res.contratosAfectados.length} ${
              res.contratosAfectados.length === 1 ? 'contrato deja' : 'contratos dejan'
            } de contar en la cuota, y baja la conversión`
          : 'Cierre anulado: baja la conversión. No había contrato que descontar de la cuota',
      )
      onCerrar()
    } catch (e) {
      setError(e instanceof CrmApiError ? e.message : 'No se pudo anular el cierre')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <Dialog open onClose={enviando ? () => {} : onCerrar} ariaLabel="Anular el cierre">
      <DialogHeader>
        {/* El nombre accesible del diálogo lo pone el DialogTitle, no el
            `ariaLabel` del componente. */}
        <DialogTitle>Anular el cierre de {lead.nombre_completo}</DialogTitle>
      </DialogHeader>
      <DialogBody className="space-y-3">
        <p className="rounded-xl border border-warning/40 bg-warning/10 p-3 text-xs font-semibold leading-relaxed text-warning-text">
          Este cierre dejará de contar en la cuota y en la conversión de{' '}
          {lead.vendedor_nombre ?? 'su analista'}. El cliente y su contrato NO se
          tocan: solo deja de acreditarse. No se puede deshacer.
        </p>
        <div className="space-y-1.5">
          <Label htmlFor="anular-avance-motivo">Motivo de la anulación</Label>
          <Textarea
            id="anular-avance-motivo"
            ref={refMotivo}
            rows={3}
            maxLength={MOTIVO_MAX}
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            placeholder="Por ejemplo: el cierre se registró con datos que no corresponden"
            disabled={enviando}
            aria-invalid={motivoInvalido}
            aria-describedby={motivoInvalido ? 'anular-avance-motivo-error' : undefined}
          />
        </div>
        {error && (
          <p
            id="anular-avance-motivo-error"
            role="alert"
            className="text-xs font-semibold text-destructive-text"
          >
            {error}
          </p>
        )}
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" size="sm" disabled={enviando} onClick={onCerrar}>
          Volver
        </Button>
        {/* `aria-disabled` y no `disabled`: al deshabilitar de verdad, el foco se
            cae a <body> y Radix NO lo rescata (su MutationObserver solo mira
            nodos ELIMINADOS, y esto es un cambio de atributo). El guard de
            `confirmar` ya es hermético, así que el botón puede seguir siendo
            enfocable sin riesgo de doble envío. */}
        <Button
          variant="destructive"
          size="sm"
          aria-disabled={enviando}
          aria-busy={enviando}
          className={enviando ? 'pointer-events-none opacity-50' : undefined}
          onClick={() => void confirmar()}
        >
          {enviando ? 'Anulando…' : 'Anular cierre'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}
