import { useEffect, useId, useRef, useState } from 'react'
import { CalendarCheck, CheckCircle2, Circle, ClipboardCheck, RefreshCw } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import type { Lead, Tarea } from '@/lib/tipos'
import { fechaSla } from '@/lib/sla-operacion'
import { siguienteDelRecorrido, type RecorridoLead } from '@/lib/recorrido-lead'
import { useRecorridoLeads, type EstadoConsultaRecorrido } from '@/data/recorrido-queries'
import { Button } from '@/components/ui/button'
import { AtenderOficinaDialog, CerrarTareaDialog } from './cerrar-tarea'

/** Sin controles anidados: también se usa dentro de tarjetas/filas pulsables. */
export function RecorridoBreve({ item, estado }: { item: RecorridoLead | undefined; estado: EstadoConsultaRecorrido }) {
  if (estado === 'inactivo' || (item && !item.aplica)) return null
  const texto = estado === 'cargando' ? 'Comprobando asistencia y entrevista…'
    : estado === 'error' || !item ? 'Asistencia y entrevista sin comprobar'
      : siguienteDelRecorrido(item)
  return <span className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground-strong">
    {item?.habilita_conversion ? <CheckCircle2 aria-hidden className="size-3.5 shrink-0" /> : <ClipboardCheck aria-hidden className="size-3.5 shrink-0" />}
    {texto}
  </span>
}

function Hecho({ hecho, ambiguo, children }: { hecho: boolean; ambiguo: boolean; children: string }) {
  const Icono = hecho ? CheckCircle2 : Circle
  return <li className="flex items-center gap-2 text-sm">
    <Icono aria-hidden className="size-4 shrink-0" />
    <span className="flex-1">{children}</span>
    <span className="text-xs font-semibold">{hecho ? 'Registrada' : ambiguo ? 'Sin confirmar' : 'Pendiente'}</span>
  </li>
}

/** Mi día abre la misma ficha; no crea otro formulario ni cambia la cola. */
export function RecorridoEnMiDia({ leadId, onAbrirFicha }: { leadId: string; onAbrirFicha: () => void }) {
  const consulta = useRecorridoLeads([leadId])
  const item = consulta.porLead.get(leadId)
  if (consulta.estado === 'inactivo' || (item && !item.aplica)) return null
  return <div className="rounded-xl border border-border px-3 py-2.5">
    <RecorridoBreve item={item} estado={consulta.estado} />
    <Button type="button" variant="link" size="sm" className="mt-1 px-0 pointer-coarse:min-h-11" onClick={onAbrirFicha}>Ver pasos en la ficha</Button>
  </div>
}

export function RecorridoFicha({ lead, puedeOperar, onAgendar, onAgenda, onHistorial }: {
  lead: Lead; puedeOperar: boolean; onAgendar: () => void; onAgenda: () => void; onHistorial: () => void
}) {
  const { yo } = useAuth()
  const { obtenerTareaParaRevision } = useCRMData()
  const consulta = useRecorridoLeads([lead.id])
  const item = consulta.porLead.get(lead.id)
  const id = useId()
  const [oficina, setOficina] = useState(false)
  const [tarea, setTarea] = useState<Tarea | null>(null)
  const [abriendo, setAbriendo] = useState(false)
  const contexto = `${yo?.id ?? ''}:${yo?.rol ?? ''}:${lead.id}`
  const contextoActual = useRef(contexto)
  contextoActual.current = contexto
  const vivo = useRef(true)
  const envio = useRef(false)
  const encabezado = useRef<HTMLHeadingElement>(null)
  const origen = useRef<HTMLElement | null>(null)
  const focoRetorno = useRef<HTMLElement | null>(null)
  useEffect(() => { vivo.current = true; return () => { vivo.current = false } }, [])
  const permite = puedeOperar && !yo?.demo && !lead.no_contactar && lead.vendedor_id != null
    && (yo?.rol === 'vendedor' || yo?.rol === 'supervisor' || yo?.rol === 'gerencia')
  const permisoActual = useRef(permite)
  permisoActual.current = permite
  function cerrar(guardado = false) {
    // El Dialog común ejecuta UNA restauración cuando retira su trampa.
    // Guardar retira el botón al refrescar los hechos; el encabezado permanece.
    focoRetorno.current = !guardado && origen.current?.isConnected ? origen.current : encabezado.current
    setOficina(false); setTarea(null)
  }

  async function abrirCita() {
    if (!permite || !item?.tarea_pendiente_id || envio.current) return
    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    envio.current = true; setAbriendo(true)
    try {
      const actual = await obtenerTareaParaRevision(lead.id, item.tarea_pendiente_id)
      if (!vivo.current || contextoActual.current !== contexto || !permisoActual.current) return
      if (actual?.tipo === 'reunion' && actual.estado === 'pendiente' && actual.lead_id === lead.id) setTarea(actual)
      else { toast.error('La cita cambió. Actualiza la ficha.'); void consulta.refetch() }
    } catch {
      if (vivo.current && contextoActual.current === contexto) toast.error('No se pudo abrir la cita. Vuelve a intentarlo.')
    } finally {
      envio.current = false
      if (vivo.current && contextoActual.current === contexto) setAbriendo(false)
    }
  }

  // Un refresco fallido nunca desmonta un formulario que ya se está llenando.
  if ((consulta.estado === 'inactivo' || (consulta.estado === 'listo' && item?.aplica === false))
    && !oficina && !tarea) return null
  return <>
    <section aria-labelledby={`${id}-titulo`} className="space-y-2 rounded-xl border border-border bg-muted/30 p-2.5">
      <div className="flex items-center justify-between gap-2">
        <h3 ref={encabezado} tabIndex={-1} id={`${id}-titulo`} className="flex items-center gap-2 rounded-md text-sm font-bold focus-visible:outline-2 focus-visible:outline-ring"><ClipboardCheck aria-hidden className="size-4" />Antes de convertir a cliente</h3>
        <Button type="button" variant="ghost" size="icon" className="size-8 shrink-0 pointer-coarse:size-11" aria-label="Volver a comprobar" title="Volver a comprobar" aria-disabled={consulta.estado === 'cargando'} onClick={() => { if (consulta.estado !== 'cargando') void consulta.refetch() }}><RefreshCw aria-hidden /></Button>
      </div>
      <p role="status" aria-atomic="true" className={consulta.estado === 'listo' && item ? 'sr-only' : 'text-xs text-muted-foreground-strong'}>{consulta.estado === 'cargando'
        ? 'Comprobando asistencia y entrevista…' : consulta.estado === 'listo' && item
          ? siguienteDelRecorrido(item) : 'No se pudo comprobar el recorrido. Puedes continuar registrando tu gestión.'}</p>
      {consulta.estado === 'listo' && item && <>
        {/* Safari conserva la lista bajo el reset de Tailwind. */}
        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
        <ul role="list" className="space-y-1.5" aria-label="Requisitos del ciclo actual">
          <Hecho hecho={item.pasos.asistencia} ambiguo={item.estado === 'ambiguo'}>Asistencia a la cita</Hecho>
          <Hecho hecho={item.pasos.entrevista} ambiguo={item.estado === 'ambiguo'}>Entrevista comercial</Hecho>
        </ul>
        {item.cita_pendiente_en && <p className="text-xs text-muted-foreground-strong">Cita: {fechaSla(item.cita_pendiente_en)}</p>}
        {item.estado === 'ambiguo' && <p className="text-xs text-muted-foreground-strong">El historial disponible no permite confirmar ambos hechos. Revisa lo registrado antes de crear otra cita.</p>}
        {!item.exigible && !item.habilita_conversion && <p className="text-xs text-muted-foreground-strong">Seguimiento informativo: el bloqueo todavía no se aplica a este lead.</p>}
        <div className="flex flex-wrap gap-2">
          {item.pendiente === 'esperar_cita' && <Button type="button" variant="outline" size="sm" className="pointer-coarse:min-h-11" onClick={onAgenda}>Ver cita</Button>}
          {permite && item.tarea_pendiente_id && item.pendiente !== 'esperar_cita' && <Button type="button" variant="outline" size="sm" className="pointer-coarse:min-h-11" aria-disabled={abriendo} onClick={() => void abrirCita()}>
            <CalendarCheck aria-hidden />{abriendo ? 'Abriendo cita…' : 'Registrar resultado de la cita'}
          </Button>}
          {permite && !item.tarea_pendiente_id && !item.habilita_conversion && <Button type="button" variant="outline" size="sm" className="pointer-coarse:min-h-11" onClick={onAgendar}>Agendar cita</Button>}
          {(item.estado === 'ambiguo' || item.pendiente === 'revisar_entrevista') && <Button type="button" variant="outline" size="sm" className="pointer-coarse:min-h-11" onClick={onHistorial}>Revisar historial</Button>}
          {permite && !item.tarea_pendiente_id && !item.habilita_conversion && <Button type="button" variant="outline" size="sm" className="pointer-coarse:min-h-11" onClick={(e) => { origen.current = e.currentTarget; setOficina(true) }}>Llegó sin cita</Button>}
        </div>
      </>}
    </section>
    {oficina && <AtenderOficinaDialog lead={lead} onCerrar={cerrar} onGuardado={() => cerrar(true)} focoAlCerrar={focoRetorno} />}
    <CerrarTareaDialog tarea={tarea} onCerrar={cerrar} onGuardado={() => cerrar(true)} focoAlCerrar={focoRetorno} />
  </>
}
