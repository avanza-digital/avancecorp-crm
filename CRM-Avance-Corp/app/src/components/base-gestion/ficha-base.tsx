// Ficha de un lead de la base para gestión (F2): una hoja lateral ANCHA en dos columnas (Miguel: «todo en
// horizontal»): a la izquierda lo que el analista hace (registrar el intento, reactivar, «no contactar»); a la
// derecha el historial completo con buscador. No es el drawer del lead: ese lee del store, cuyo ámbito no trae los
// descartados. Cuando el lead deja la base (agendó cita, reactivado, descansa o «no contactar») la ficha se cierra
// y lo dice; si volvió a la cartera, el aviso ofrece abrir su ficha normal.
import { type JSX, type ReactNode } from 'react'
import { toast } from 'sonner'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { etiquetaDiasDescarte, etiquetaMotivoDescarte, etiquetaOrigen, type FilaBaseGestion } from '@/lib/base-gestion'
import { AccionesBase } from './acciones-base'
import { HistorialBase } from './historial-base'
import { RegistrarIntentoBase, type DesenlaceIntento } from './intento-base'
import { TelefonoLlamable } from './llamar-base'
import { EtapaMaximaChip, Intentos, MesDelLead, ProximaLlamada } from './piezas-base'

export function FichaBase({ fila, demo, puedeMarcar, onCerrar, focoRespaldo }: {
  /** La fila abierta; null = cerrada. */
  fila: FilaBaseGestion | null
  demo: boolean
  puedeMarcar: boolean
  onCerrar: () => void
  /** A dónde vuelve el foco si el lead salió de la lista con la ficha abierta (su vecino o la hoja). */
  focoRespaldo?: () => HTMLElement | null
}): JSX.Element {
  const { recargar } = useCRMData()
  const { abrirLead } = usePanelesActions()

  // Volvió a la cartera: primero el store lo ve, después se ofrece abrirlo (abrir antes sería abrir el vacío).
  async function alVolverACartera(mensaje: string, leadId: string) {
    onCerrar()
    const resincronizado = await recargar()
    // 12 s, la convención de la casa para un aviso con acción: a 4 s no da tiempo a llegar con el teclado (WCAG 2.2.1).
    if (resincronizado) toast.success(mensaje, { duration: 12_000, action: { label: 'Abrir su ficha', onClick: () => abrirLead(leadId) } })
    else toast.success(`${mensaje}. Recarga la página para verlo en tu cartera.`)
  }

  function alDejarLaBase(desenlace: DesenlaceIntento, leadId: string) {
    if (desenlace.tipo === 'reactivado') { void alVolverACartera(desenlace.mensaje, leadId); return }
    onCerrar()
    toast.info(desenlace.mensaje)
  }

  return (
    <Sheet
      open={fila != null}
      onClose={onCerrar}
      className="w-full max-w-full sm:w-[1120px] sm:max-w-[96vw]"
      // Se abre para registrar: el foco empieza en el primer resultado y los atajos 1–7 funcionan de entrada.
      focoInicial={() => document.querySelector<HTMLInputElement>('[data-slot="sheet"] form input[type="radio"]')}
      {...(focoRespaldo ? { focoRespaldo } : {})}
    >
      {fila && (
        <>
          <SheetHeader className="gap-2">
            {/* Escritorio: nombre · acciones · cerrar en una fila. Celular: nombre y cerrar arriba, acciones debajo a todo el ancho. */}
            <div className="flex flex-wrap items-start gap-x-6 gap-y-3">
              <div className="order-1 min-w-0 flex-1">
                <SheetTitle className="text-xl">{fila.nombre_completo}</SheetTitle>
                <div className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-[var(--muted-foreground-strong)]">
                  <TelefonoLlamable fila={fila} puedeMarcar={puedeMarcar} />
                  {fila.distrito && <span>{fila.distrito}</span>}
                  <span>{etiquetaOrigen(fila.origen)}</span>
                </div>
              </div>
              <div className="order-3 w-full sm:order-2 sm:w-auto">
                <AccionesBase
                  fila={fila}
                  demo={demo}
                  onReactivado={() => void alVolverACartera('Reactivado: el lead volvió a tu cartera como Contactado', fila.lead_id)}
                  onNoContactar={() => { onCerrar(); toast.info('Marcado «No contactar»: el lead salió de tu base') }}
                />
              </div>
              <Button type="button" variant="ghost" size="icon" className="order-2 shrink-0 sm:order-3" onClick={onCerrar} aria-label="Cerrar la ficha">
                <X aria-hidden />
              </Button>
            </div>
            <dl className="mt-1 flex flex-wrap gap-x-6 gap-y-2 text-sm">
              <Dato rotulo="Mes"><MesDelLead fila={fila} /></Dato>
              <Dato rotulo="Motivo del descarte">{etiquetaMotivoDescarte(fila.motivo_descarte)}</Dato>
              <Dato rotulo="Descartado">{etiquetaDiasDescarte(fila.dias_desde_descarte)}</Dato>
              <Dato rotulo="Etapa máxima"><EtapaMaximaChip etapa={fila.etapa_maxima} /></Dato>
              <Dato rotulo="Intentos"><Intentos n={fila.intentos} /></Dato>
              <Dato rotulo="Próxima llamada"><ProximaLlamada iso={fila.proxima_llamada_en} ahora={Date.now()} /></Dato>
            </dl>
          </SheetHeader>
          <SheetBody className="grid gap-5 lg:grid-cols-2 lg:overflow-hidden">
            <div className="ac-scroll lg:overflow-y-auto lg:pr-1">
              <RegistrarIntentoBase key={fila.lead_id} fila={fila} demo={demo} onDejaLaBase={(d) => alDejarLaBase(d, fila.lead_id)} />
            </div>
            <HistorialBase leadId={fila.lead_id} />
          </SheetBody>
        </>
      )}
    </Sheet>
  )
}

function Dato({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">{rotulo}</dt>
      <dd className="text-sm text-foreground">{children}</dd>
    </div>
  )
}
