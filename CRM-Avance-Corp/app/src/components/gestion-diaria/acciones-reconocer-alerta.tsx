import { useEffect, useRef, useState, type JSX } from 'react'
import { CalendarClock, Check } from 'lucide-react'
import { toast } from 'sonner'
import { CrmApiError } from '@/data/crm-api'
import { Button } from '@/components/ui/button'
import { useAlertasCRM } from '@/lib/alertas-context'
import type { AlertaCRM } from '@/lib/alertas'
import { esFocoHuerfano } from '@/lib/foco'
import { fechaCortaLima } from '@/lib/recordatorios-disponibilidad'
import { presentarCitas } from '@/lib/terminologia'

/** F4: los plazos de posponer que se ofrecen (decisión de Miguel: tope 7
 *  días). El de 7 va con un colchón de 30 minutos BAJO el tope (Codex #2):
 *  el servidor mide «≤ 7 días» con SU reloj de pared, y un cliente
 *  adelantado mandaría un hasta que el trigger rechaza (22023). Si aun así
 *  el reloj local está tan roto que el servidor lo rechaza, el mensaje del
 *  trigger llega al toast tal cual — el fallo se dice, no se disimula. */
const PLAZOS_POSPONER: ReadonlyArray<{ dias: number; etiqueta: string; margenMs: number }> = [
  { dias: 1, etiqueta: 'Mañana', margenMs: 0 },
  { dias: 3, etiqueta: 'En 3 días', margenMs: 0 },
  { dias: 7, etiqueta: 'En 7 días', margenMs: 1_800_000 },
]

/** F4: reconocer («lo estoy atendiendo») atenúa la fila y descuenta la
 *  campana; posponer la oculta hasta la fecha elegida. Solo existe en las
 *  alertas AGRUPADAS del supervisor (las que traen `miembros`).
 *
 *  Foco (a11y F4, los dos bloqueantes del revisor): «Posponer» es un
 *  disclosure REAL — persiste al abrirse (aria-expanded/aria-controls
 *  verdaderos), el foco entra al primer plazo por efecto y vuelve a
 *  «Posponer» al cerrar. Tras un asiento exitoso el bloque entero desaparece
 *  (la fila se atenúa o se va) y el foco aterriza en el contador, como en
 *  F3.1; tras un FALLO, el rescate corre en un efecto cuando `ocupado`
 *  vuelve a false — en el finally el botón aún está disabled y focus()
 *  sobre un control disabled es un no-op (lección de F2). */
export function AccionesReconocerAlerta({ alerta, destinoFoco = 'alertas-contador' }: { alerta: AlertaCRM; destinoFoco?: string }): JSX.Element {
  const { reconocer } = useAlertasCRM()
  const [eligiendoPlazo, setEligiendoPlazo] = useState(false)
  const [ocupado, setOcupado] = useState(false)
  const botonReconocerRef = useRef<HTMLButtonElement | null>(null)
  const botonPosponerRef = useRef<HTMLButtonElement | null>(null)
  const primerPlazoRef = useRef<HTMLButtonElement | null>(null)
  const rescatarFocoRef = useRef<'reconocer' | 'posponer' | null>(null)
  const estuvoAbiertoRef = useRef(false)
  const idPlazos = `plazos-${alerta.id}`

  useEffect(() => {
    if (eligiendoPlazo) {
      estuvoAbiertoRef.current = true
      primerPlazoRef.current?.focus()
      return
    }
    // Solo al CERRAR un disclosure que estuvo abierto (no en el montaje), y
    // solo si el foco quedó huérfano (Cancelar/plazo desmontados con el grupo).
    if (!estuvoAbiertoRef.current) return
    estuvoAbiertoRef.current = false
    if (esFocoHuerfano(botonPosponerRef.current)) botonPosponerRef.current?.focus()
  }, [eligiendoPlazo])

  useEffect(() => {
    if (ocupado || rescatarFocoRef.current == null) return
    const destino = rescatarFocoRef.current === 'reconocer'
      ? botonReconocerRef.current
      : (eligiendoPlazo ? primerPlazoRef.current : botonPosponerRef.current)
    rescatarFocoRef.current = null
    if (esFocoHuerfano(destino)) destino?.focus()
  }, [ocupado, eligiendoPlazo])

  const asentar = async (accion: 'reconocer' | 'posponer', hasta: string | null) => {
    if (ocupado) return
    setOcupado(true)
    try {
      await reconocer(alerta, accion, hasta)
      toast.success(accion === 'reconocer'
        ? 'Reconocida: queda atenuada y reaparece si empeora.'
        : `Pospuesta hasta el ${hasta ? fechaCortaLima(hasta) ?? 'día elegido' : 'día elegido'}.`)
      setEligiendoPlazo(false)
      // El botón que tenía el foco ya no existe: aterrizar en el contador
      // (o el encabezado si la lista quedó vacía), como en F3.1.
      const destino = document.getElementById(destinoFoco)
        ?? document.getElementById('alertas-encabezado')
      destino?.focus()
    } catch (error: unknown) {
      toast.error(error instanceof CrmApiError
        ? presentarCitas(error.message)
        : 'No se pudo asentar el reconocimiento.')
      // Los plazos se QUEDAN abiertos: el supervisor reintenta donde estaba.
      rescatarFocoRef.current = accion
    } finally {
      setOcupado(false)
    }
  }

  return (
    <div className="flex flex-wrap items-center justify-end gap-2">
      <Button
        ref={botonReconocerRef}
        variant="outline"
        size="sm"
        className="min-h-11 text-base"
        disabled={ocupado}
        aria-busy={ocupado}
        onClick={() => { void asentar('reconocer', null) }}
        aria-label={`Reconocer «${presentarCitas(alerta.titulo)}»: la estoy atendiendo`}
      >
        <Check aria-hidden /> Lo estoy atendiendo
      </Button>
      <Button
        ref={botonPosponerRef}
        variant="ghost"
        size="sm"
        className="min-h-11 text-base"
        disabled={ocupado}
        aria-expanded={eligiendoPlazo}
        aria-controls={eligiendoPlazo ? idPlazos : undefined}
        onClick={() => setEligiendoPlazo((abierto) => !abierto)}
        aria-label={`Posponer «${presentarCitas(alerta.titulo)}»`}
      >
        <CalendarClock aria-hidden /> Posponer
      </Button>
      {eligiendoPlazo && (
        <div
          id={idPlazos}
          role="group"
          aria-label={`Posponer «${presentarCitas(alerta.titulo)}» hasta`}
          className="flex flex-wrap items-center justify-end gap-2"
        >
          {PLAZOS_POSPONER.map((plazo, indice) => (
            <Button
              key={plazo.dias}
              ref={indice === 0 ? primerPlazoRef : undefined}
              variant="outline"
              size="sm"
              className="min-h-11 text-base"
              disabled={ocupado}
              onClick={() => {
                void asentar(
                  'posponer',
                  new Date(Date.now() + plazo.dias * 86_400_000 - plazo.margenMs).toISOString(),
                )
              }}
            >
              {plazo.etiqueta}
            </Button>
          ))}
          <Button
            variant="ghost"
            size="sm"
            className="min-h-11 text-base"
            disabled={ocupado}
            onClick={() => setEligiendoPlazo(false)}
            aria-label="Cancelar posposición"
          >
            Cancelar
          </Button>
        </div>
      )}
    </div>
  )
}
