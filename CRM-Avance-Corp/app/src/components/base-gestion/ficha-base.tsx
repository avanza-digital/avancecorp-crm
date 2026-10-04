// Ficha de un lead de la base para gestión (F2): una hoja lateral ANCHA en dos columnas (Miguel: «todo en
// horizontal»): a la izquierda los datos y el registro del intento; a la derecha la actividad completa con buscador;
// abajo, en un pie fijo, «No contactar» y «Reactivar». No es el drawer del lead: ese lee del store, cuyo ámbito no
// trae los descartados. Cuando el lead deja la base (agendó cita, reactivado, descansa o «no contactar») la ficha se
// cierra y lo dice; si volvió a la cartera, el aviso ofrece abrir su ficha normal.
// Se ve como la ficha del lead (`lead-drawer.tsx`, Miguel, 03/10): avatar, nombre, chips, botones de contacto,
// sección DATOS con su rejilla, la misma línea de tiempo y el pie «Descartar · Convertir» hecho «No contactar ·
// Reactivar». Maqueta aprobada: `ui-playground/ficha-base-gestion.html` (fuera del repo).
import { useId, useRef, type JSX } from 'react'
import { toast } from 'sonner'
import { X } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Fila } from '@/components/app/fila-dato'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { cn } from '@/lib/utils'
import {
  colorEtapaMaxima,
  etiquetaDiasDescarte,
  etiquetaEtapaMaxima,
  etiquetaMesLead,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  etiquetaOrigen,
  etiquetaUltimoResultado,
  mesDelLead,
  type FilaBaseGestion,
} from '@/lib/base-gestion'
import { AccionesBase } from './acciones-base'
import { HistorialBase } from './historial-base'
import { RegistrarIntentoBase, type DesenlaceIntento } from './intento-base'
import { ContactoBase } from './llamar-base'
import { Intentos, ProximaLlamada } from './piezas-base'

/** Un dato que falta, en gris. */
function SinDato({ children }: { children: string }) {
  return <span className="text-[var(--muted-foreground-strong)]">{children}</span>
}

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
  const ahora = useAhora()
  const id = useId()
  // El formulario del intento: ahí van el foco inicial y el de «Llamar» (sin buscarlo en la página).
  const formulario = useRef<HTMLFormElement>(null)
  /** Un radio del resultado: el elegido, si `elegido` y hay uno; si no, el primero. */
  const radioDelResultado = (elegido = false): HTMLInputElement | null =>
    (elegido ? formulario.current?.querySelector<HTMLInputElement>('input[type="radio"]:checked') : null)
    ?? formulario.current?.querySelector<HTMLInputElement>('input[type="radio"]') ?? null

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

  // En la laptop «Llamar» copia el número: el siguiente paso es decir qué pasó, así que el foco va al resultado
  // (el elegido, si ya hay uno; si no, el primero). El navegador lo trae a la vista al enfocarlo.
  function alLlamar() {
    radioDelResultado(true)?.focus()
  }

  const mes = fila ? mesDelLead(fila) : null

  return (
    <Sheet
      open={fila != null}
      onClose={onCerrar}
      className="w-full max-w-full sm:w-[1120px] sm:max-w-[96vw]"
      // Se abre para registrar: el foco empieza en el primer resultado y los atajos 1–7 funcionan de entrada.
      focoInicial={() => radioDelResultado()}
      {...(focoRespaldo ? { focoRespaldo } : {})}
    >
      {fila && (
        <>
          <SheetHeader className="gap-2.5">
            {/* Escritorio: avatar · nombre y chips · días · cerrar. Celular: el nombre baja a dos líneas y los chips
                ocupan todo el ancho bajo él. */}
            <div className="grid grid-cols-[40px_minmax(0,1fr)_auto_32px] items-start gap-x-3 gap-y-2 sm:gap-y-1.5">
              <Avatar nombre={fila.nombre_completo} className="size-10 sm:row-span-2" />
              <SheetTitle className="min-w-0 pt-1 text-lg leading-tight [overflow-wrap:anywhere] sm:pt-0">{fila.nombre_completo}</SheetTitle>
              <div className="shrink-0 text-right leading-tight">
                <p className="text-sm font-extrabold tabular-nums text-primary">{etiquetaDiasDescarte(fila.dias_desde_descarte)}</p>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Descartado</p>
              </div>
              <button
                type="button"
                onClick={onCerrar}
                aria-label="Cerrar la ficha"
                className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground', FOCO)}
              >
                <X className="size-4" aria-hidden />
              </button>
              <div className="col-span-4 flex flex-wrap items-center gap-1.5 sm:col-span-1 sm:col-start-2 sm:row-start-2">
                {/* Contraste AA con texto de 11 px: el tinte y el punto llevan el color de la etapa, el texto va en el
                    color de lectura (varias etapas —ámbar, gris— no llegan a 4,5:1 sobre su tinte). `.ac-chip` está
                    fuera de @layer, así que una clase `text-*` no le gana: va por `style`. */}
                <Badge color={colorEtapaMaxima(fila.etapa_maxima)} dot style={{ color: 'var(--foreground)' }}>Etapa máxima · {etiquetaEtapaMaxima(fila.etapa_maxima)}</Badge>
                <Badge color="var(--muted-foreground-strong)">{etiquetaOrigen(fila.origen)}</Badge>
                {mes && <Badge color="var(--primary)">{etiquetaMesLead(mes)}</Badge>}
                {/* Un solo hijo: el chip es flex con `gap` y dos piezas sueltas se separarían de más. */}
                <Badge color="var(--muted-foreground-strong)"><span>Descarte · <span>{etiquetaMotivoDescarte(fila.motivo_descarte)}</span></span></Badge>
              </div>
            </div>
            <ContactoBase fila={fila} puedeMarcar={puedeMarcar} onLlamar={alLlamar} />
          </SheetHeader>

          {/* `scroll-pb-28`: al enfocar un campo, el navegador lo deja por encima de la barra fija de «Guardar» (WCAG
              2.4.11, técnica C43). En el celular desplaza el cuerpo; en escritorio, la columna izquierda. */}
          <SheetBody className="grid scroll-pb-28 gap-5 lg:grid-cols-2 lg:overflow-hidden lg:scroll-pb-0">
            <div className="ac-scroll space-y-5 lg:min-h-0 lg:scroll-pb-28 lg:overflow-y-auto lg:pr-1">
              <section aria-labelledby={`${id}-datos`}>
                <h3 id={`${id}-datos`} className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Datos</h3>
                {/* Dos subcolumnas en escritorio, una en el celular; lo largo (último resultado, próxima llamada) a lo ancho. */}
                <dl className="mt-1.5 grid lg:grid-cols-2 lg:gap-x-5">
                  <Fila label="Teléfono">
                    {fila.telefono ? <span className="font-semibold tabular-nums">{telefonoLegible(fila.telefono)}</span> : <SinDato>Sin teléfono</SinDato>}
                  </Fila>
                  <Fila label="Distrito">{fila.distrito ?? <SinDato>Sin distrito</SinDato>}</Fila>
                  <Fila label="Intentos"><Intentos n={fila.intentos} /></Fila>
                  <Fila label="Gestiona">{fila.gestiona ?? <SinDato>Sin asignar</SinDato>}</Fila>
                  <Fila label="Último resultado" className="lg:col-span-2">
                    {fila.ultimo_resultado ? (
                      <>
                        {etiquetaUltimoResultado(fila.ultimo_resultado)}
                        {fila.ultimo_intento_en && <span className="text-[var(--muted-foreground-strong)]"> · {etiquetaMomento(fila.ultimo_intento_en, ahora)}</span>}
                      </>
                    ) : <SinDato>Sin intentos</SinDato>}
                  </Fila>
                  <Fila label="Próxima llamada" className="lg:col-span-2"><ProximaLlamada iso={fila.proxima_llamada_en} ahora={ahora} /></Fila>
                </dl>
              </section>
              <RegistrarIntentoBase key={fila.lead_id} fila={fila} demo={demo} formRef={formulario} onDejaLaBase={(d) => alDejarLaBase(d, fila.lead_id)} />
            </div>
            <HistorialBase leadId={fila.lead_id} />
          </SheetBody>

          <SheetFooter role="group" aria-label="Acciones del lead" className="flex-wrap justify-between">
            <AccionesBase
              fila={fila}
              demo={demo}
              onReactivado={() => void alVolverACartera('Reactivado: el lead volvió a tu cartera como Contactado', fila.lead_id)}
              onNoContactar={() => { onCerrar(); toast.info('Marcado «No contactar»: el lead salió de tu base') }}
            />
          </SheetFooter>
        </>
      )}
    </Sheet>
  )
}
