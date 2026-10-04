// Ficha de un lead de la base para gestión (F2): una hoja lateral ANCHA en dos columnas (Miguel: «todo en
// horizontal»): a la izquierda los datos y el registro del intento; a la derecha la actividad completa con buscador;
// abajo, en un pie fijo, «No contactar» y «Reactivar». No es el drawer del lead: ese lee del store, cuyo ámbito no
// trae los descartados. Cuando el lead deja la base (agendó cita, reactivado, descansa o «no contactar») la ficha se
// cierra y lo dice; si volvió a la cartera, el aviso ofrece abrir su ficha normal.
// Se ve como la ficha del lead (`lead-drawer.tsx`, Miguel, 03/10): avatar, nombre, chips, botones de contacto,
// sección DATOS con su rejilla, la misma línea de tiempo y el pie «Descartar · Convertir» hecho «No contactar ·
// Reactivar». Maqueta aprobada: `ui-playground/ficha-base-gestion.html` (fuera del repo).
// Según el rol (F4, decisión 5 de Miguel, 03/10): para Supervisión y Gerencia (`modo="supervision"`) es de CONSULTA
// —datos e historial—, sin registrar intentos, sin reactivar y sin botones de llamar (eso es del analista; repartir
// sigue en «Descartes del mes»). Si el lead está vetado, muestra la marca (cuándo, motivo, quién) y ofrece «Quitar No
// contactar». La ficha del analista no cambia.
import { useId, useRef, type JSX } from 'react'
import { toast } from 'sonner'
import { X } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Fila } from '@/components/app/fila-dato'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
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
  esVetada,
  mesDelLead,
  type FilaBaseGestion,
} from '@/lib/base-gestion'
import { AccionesBase } from './acciones-base'
import { HistorialBase } from './historial-base'
import { RegistrarIntentoBase, type DesenlaceIntento } from './intento-base'
import { ContactoBase } from './llamar-base'
import { Intentos, ProximaLlamada } from './piezas-base'
import { QuitarNoContactar } from './quitar-no-contactar'

/** Un dato que falta, en gris. */
function SinDato({ children }: { children: string }) {
  return <span className="text-[var(--muted-foreground-strong)]">{children}</span>
}

export function FichaBase({ fila, demo, puedeMarcar, onCerrar, focoRespaldo, modo = 'analista' }: {
  /** La fila abierta; null = cerrada. */
  fila: FilaBaseGestion | null
  demo: boolean
  puedeMarcar: boolean
  onCerrar: () => void
  /** A dónde vuelve el foco si el lead salió de la lista con la ficha abierta (su vecino o la hoja). */
  focoRespaldo?: () => HTMLElement | null
  /** `supervision` (F4): consulta + «Quitar No contactar»; sin registrar intentos ni reactivar. */
  modo?: 'analista' | 'supervision'
}): JSX.Element {
  const consulta = modo === 'supervision'
  const { recargar } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const ahora = useAhora()
  const id = useId()
  // El formulario del intento: ahí van el foco inicial y el de «Llamar» (sin buscarlo en la página).
  const formulario = useRef<HTMLFormElement>(null)
  // Tras «Quitar No contactar» el pie desaparece: el foco va al cerrar de la ficha (siempre está), no se pierde.
  const botonCerrar = useRef<HTMLButtonElement>(null)
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
      // Se abre para registrar: el foco empieza en el primer resultado y los atajos 1–7 funcionan de entrada. En
      // consulta no hay formulario: el foco va al primer control, como en cualquier hoja lateral.
      focoInicial={() => (consulta ? null : radioDelResultado())}
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
                ref={botonCerrar}
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
                {esVetada(fila) && <Badge color="var(--destructive)" style={{ color: 'var(--destructive-text)' }}>No contactar</Badge>}
              </div>
            </div>
            {!consulta && <ContactoBase fila={fila} puedeMarcar={puedeMarcar} onLlamar={alLlamar} />}
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
              {consulta ? (
                <>
                  {esVetada(fila) && <MarcaNoContactar fila={fila} ahora={ahora} />}
                  <p className="rounded-lg border border-border bg-muted/40 px-3 py-2 text-[13px] text-[var(--muted-foreground-strong)]">
                    Ficha de consulta: los intentos y la reactivación los registra {fila.gestiona ?? 'su analista'} desde su base.
                    Para repartir este descarte, usa «Descartes del mes».
                  </p>
                </>
              ) : (
                <RegistrarIntentoBase key={fila.lead_id} fila={fila} demo={demo} formRef={formulario} onDejaLaBase={(d) => alDejarLaBase(d, fila.lead_id)} />
              )}
            </div>
            <HistorialBase leadId={fila.lead_id} />
          </SheetBody>

          {!consulta ? (
            <SheetFooter role="group" aria-label="Acciones del lead" className="flex-wrap justify-between">
              <AccionesBase
                fila={fila}
                demo={demo}
                onReactivado={() => void alVolverACartera('Reactivado: el lead volvió a tu cartera como Contactado', fila.lead_id)}
                onNoContactar={() => { onCerrar(); toast.info('Marcado «No contactar»: el lead salió de tu base') }}
              />
            </SheetFooter>
          ) : esVetada(fila) && (
            <SheetFooter role="group" aria-label="Acciones del lead" className="flex-wrap justify-between">
              <p className="text-[13px] text-[var(--muted-foreground-strong)]">Se levanta para la persona y todos sus leads.</p>
              <QuitarNoContactar
                fila={fila}
                demo={demo}
                focoTrasQuitar={botonCerrar}
                onHecho={(n) => toast.success(n > 1
                  ? `«No contactar» quitado: los ${n} leads de la persona pueden volver a llamarse`
                  : '«No contactar» quitado: el lead puede volver a llamarse')}
              />
            </SheetFooter>
          )}
        </>
      )}
    </Sheet>
  )
}

/** La marca «No contactar» de un lead vetado (consulta de Supervisión y Gerencia): cuándo, motivo y quién; si vino de
 *  otro lead de la persona, se dice. Si además descansa, hasta cuándo. */
function MarcaNoContactar({ fila, ahora }: { fila: FilaBaseGestion; ahora: number }) {
  const id = useId()
  const propia = Boolean(fila.no_contactar_en || fila.no_contactar_motivo || fila.no_contactar_por)
  const hasta = fila.enfriado_hasta ? Date.parse(fila.enfriado_hasta) : Number.NaN
  const descansa = Number.isFinite(hasta) && hasta > ahora ? fechaLima(hasta).split('-').reverse().slice(0, 2).join('/') : null
  return (
    <section aria-labelledby={id} className="rounded-lg border border-destructive/40 bg-destructive/[0.04] px-3 py-2">
      <h3 id={id} className="text-[11px] font-bold uppercase tracking-wide text-[var(--destructive-text)]">No contactar · Ley 29571</h3>
      <dl className="mt-1 grid lg:grid-cols-2 lg:gap-x-5">
        {propia ? (
          <>
            <Fila label="Desde">{fila.no_contactar_en ? etiquetaMomento(fila.no_contactar_en, ahora) : <SinDato>Sin dato</SinDato>}</Fila>
            <Fila label="Marcó">{fila.no_contactar_por ?? <SinDato>Sin dato</SinDato>}</Fila>
            <Fila label="Motivo" className="lg:col-span-2">{fila.no_contactar_motivo ?? <SinDato>Sin motivo</SinDato>}</Fila>
          </>
        ) : (
          <Fila label="Origen" className="lg:col-span-2">La marca viene de otro lead de la misma persona.</Fila>
        )}
        {descansa && <Fila label="Descanso" className="lg:col-span-2">Descansa hasta el {descansa}</Fila>}
      </dl>
    </section>
  )
}
