import { useId, useRef, useState, type JSX } from 'react'
import { CalendarClock, LoaderCircle, LockOpen, TriangleAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { mensajeDeError } from '@/data/crm-api'
import { fmtFecha } from '@/lib/format'
import {
  MOTIVO_PLAZO_MAX,
  MOTIVO_PLAZO_MIN,
  avisoFechaLejana,
  conMayuscula,
  conPunto,
  errorUltimoDia,
  esFechaLejana,
  fechaMinimaPlazo,
  largoMotivoPlazo,
  lineaDelPlazo,
  mesSinAnio,
  motivoPlazoValido,
  type MesPlazoCarga,
} from '@/lib/plazo-carga-mes'

/**
 * «Ampliar plazo» (mes abierto) o «Reabrir {mes}» (mes sellado y reabrible):
 * la MISMA puerta con una fecha y un motivo. La pantalla solo evita el clic
 * suelto y la fecha imposible; si se puede o no lo decide el servidor, y su
 * mensaje se muestra tal cual (son mensajes de negocio).
 */
export function PlazoCargaDialogo({ mes, hoy, onConfirmar, onCerrar }: {
  mes: MesPlazoCarga
  /** El día de Lima que sirvió el servidor junto con el plazo. */
  hoy: string
  /** Guarda; si rechaza, el diálogo sigue abierto con el mensaje y lo escrito. */
  onConfirmar: (ultimoDia: string, motivo: string) => Promise<void>
  onCerrar: () => void
}): JSX.Element {
  const reabrir = mes.sellado
  const mesCorto = mesSinAnio(mes.mes_nombre)
  const minimo = fechaMinimaPlazo(mes, hoy)
  const [ultimoDia, setUltimoDia] = useState('')
  // Una fecha lejana se confirma aparte (15/10/2026: septiembre quedó hasta 2926 por un error de tipeo). Cambiar la
  // fecha borra la confirmación: se confirma ESA fecha, no cualquiera.
  const [confirmaLejana, setConfirmaLejana] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState('')
  const enCurso = useRef(false)
  const campoFecha = useRef<HTMLInputElement>(null)
  const id = useId()
  const errorFecha = errorUltimoDia(ultimoDia, minimo)
  // Vacío no se marca en rojo: el botón espera y la ayuda ya dice desde cuándo.
  const fechaInvalida = ultimoDia !== '' && errorFecha !== null
  const largo = largoMotivoPlazo(motivo)
  const excedido = largo > MOTIVO_PLAZO_MAX
  const lejana = errorFecha === null && esFechaLejana(ultimoDia, hoy)
  const listo = errorFecha === null && motivoPlazoValido(motivo) && (!lejana || confirmaLejana)
  const titulo = reabrir ? `Reabrir ${mes.mes_nombre}` : `Ampliar el plazo de ${mes.mes_nombre}`
  const accion = reabrir ? `Reabrir ${mesCorto}` : 'Guardar plazo'
  // Lo que dice el anuncio de por qué el botón espera: nombra el botón que hay (revisión a11y, 15/10).
  const verbo = reabrir ? 'reabrir' : 'guardar'

  async function confirmar() {
    if (enCurso.current || !listo) return
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      await onConfirmar(ultimoDia, motivo.trim())
      onCerrar()
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo guardar el plazo de carga. Vuelve a intentarlo.'))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }

  return <Dialog open onClose={() => { if (!enCurso.current) onCerrar() }} ariaLabel={titulo} focoInicial={campoFecha}>
    <DialogHeader><DialogTitle className="text-base">{titulo}</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <p className="text-sm text-foreground">
        <span className="font-semibold">Hoy:</span> {conPunto(`${conMayuscula(mes.mes_nombre)} · ${lineaDelPlazo(mes, hoy)}`)}
      </p>
      {reabrir && (
        <p id={`${id}-reabrir`} className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 p-3 text-sm font-semibold text-warning-text">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
          Se retira el cierre de {mesCorto}; se vuelve a sellar solo al vencer este plazo.
        </p>
      )}
      <div className="space-y-2">
        <Label htmlFor={`${id}-fecha`} className="text-sm">Último día para cargar</Label>
        <Input ref={campoFecha} id={`${id}-fecha`} type="date" min={minimo} value={ultimoDia} disabled={enviando}
          className="h-10 w-48 text-base"
          aria-invalid={fechaInvalida || undefined}
          aria-describedby={[reabrir ? `${id}-reabrir` : null, `${id}-fecha-ayuda`, lejana ? `${id}-lejana` : null].filter(Boolean).join(' ')}
          onChange={(e) => { setUltimoDia(e.target.value); setConfirmaLejana(false) }} />
        <p id={`${id}-fecha-ayuda`} className={fechaInvalida ? 'text-sm font-semibold text-destructive-text' : 'text-sm text-muted-foreground-strong'}>
          {fechaInvalida ? errorFecha : `${conPunto(`Desde el ${fmtFecha(minimo)}`)} Ese día todavía se puede cargar.`}
        </p>
        {lejana && (
          <div className="space-y-2 rounded-lg border border-warning/40 bg-warning/10 p-3">
            <p id={`${id}-lejana`} className="flex items-start gap-2 text-sm font-semibold text-warning-text">
              <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
              {avisoFechaLejana(ultimoDia, mes.mes_nombre)}
            </p>
            <label className="flex cursor-pointer items-start gap-2 text-sm font-semibold text-foreground">
              <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-accent" checked={confirmaLejana}
                aria-required="true"
                disabled={enviando} onChange={(e) => setConfirmaLejana(e.target.checked)} />
              <span>Sí, el {fmtFecha(ultimoDia)} es correcto</span>
            </label>
          </div>
        )}
      </div>
      <div className="space-y-2">
        <Label htmlFor={`${id}-motivo`} className="text-sm">Motivo</Label>
        <Textarea id={`${id}-motivo`} rows={3} value={motivo} disabled={enviando} className="text-base"
          placeholder={`Por ejemplo: los analistas aún cargan ventas de ${mesCorto}`}
          aria-invalid={excedido || undefined}
          aria-describedby={`${id}-contador`}
          onChange={(e) => setMotivo(e.target.value)} />
        <p id={`${id}-contador`} className={excedido ? 'text-sm font-semibold text-destructive-text' : 'text-sm text-muted-foreground-strong'}>
          {largo} de {MOTIVO_PLAZO_MAX} caracteres · mínimo {MOTIVO_PLAZO_MIN}
        </p>
        {/* Montada desde el inicio: anuncia por qué el botón quedó inactivo (fecha antes
            del mínimo, motivo pasado del tope), que de otro modo solo se vería. */}
        <p role="status" className="sr-only">
          {[
            fechaInvalida ? errorFecha : null,
            excedido ? `El motivo pasa de ${MOTIVO_PLAZO_MAX} caracteres: acórtalo para poder ${verbo}.` : null,
            lejana && !confirmaLejana ? `La fecha queda a más de dos meses: confírmala para poder ${verbo}.` : null,
          ].filter(Boolean).join(' ')}
        </p>
      </div>
      {error && <p role="alert" className="text-sm font-semibold text-destructive-text">{error}</p>}
    </DialogBody>
    <DialogFooter className="flex-wrap">
      <Button variant="outline" className="h-10" disabled={enviando} onClick={onCerrar}>Cancelar</Button>
      {/* Mientras envía, `aria-disabled` y no `disabled`: deshabilitar de verdad tira el
          foco a <body> y Radix no lo rescata (ver anular-cierre-avance). `enCurso`
          impide el segundo envío. */}
      <Button className={enviando ? 'pointer-events-none h-10 opacity-50' : 'h-10'} disabled={!listo}
        aria-disabled={enviando || undefined} aria-busy={enviando || undefined} onClick={() => void confirmar()}>
        {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : reabrir ? <LockOpen aria-hidden /> : <CalendarClock aria-hidden />}
        {enviando ? (reabrir ? 'Reabriendo…' : 'Guardando…') : accion}
      </Button>
    </DialogFooter>
  </Dialog>
}
