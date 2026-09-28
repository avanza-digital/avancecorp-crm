// G4b (27/09/2026): la lista EXACTA de «Citas agendadas» —las citas CREADAS ese día—,
// la misma definición que la cifra. Filas limpias como el registro compacto: a qué hora
// se agendó, el estado, el lead (abre su ficha), el analista cuando el ámbito tiene
// varios y cuándo es la cita. El título lo pone quien la aloja.
import { useEffect, useEffectEvent, type JSX, type RefObject } from 'react'
import { useCitasGestion } from '@/data/gestion-diaria-citas-queries'
import type { AmbitoCitas, EstadoCita } from '@/lib/gestion-diaria-citas'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { usePanelesActions } from '@/lib/store-context'
import { Badge } from '@/components/ui/badge'
import { PanelCargando } from '@/components/common/estado-panel'
import { cn } from '@/lib/utils'
import { BotonVerMasCompacto } from './registro-actividad'
import { FOCO } from './estilos-gestion'

const CUANDO = new Intl.DateTimeFormat('es-PE', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Lima' })
const ESTADO: Record<EstadoCita, { texto: string; color: string }> = {
  pendiente: { texto: 'Pendiente', color: 'var(--primary)' },
  completada: { texto: 'Realizada', color: 'var(--accent-press)' },
  cancelada: { texto: 'Cancelada', color: 'var(--muted-foreground-strong)' },
  no_show: { texto: 'No asistió', color: 'var(--warning-text)' },
  reprogramada: { texto: 'Reprogramada', color: 'var(--muted-foreground-strong)' },
}
const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`

export function CitasAgendadas({ dia, esHoy, ambito, id, mostrarAnalista, visible, actualizacion, revalidar, encabezado }: {
  dia: string
  esHoy: boolean
  ambito: AmbitoCitas
  id: string | null
  /** Con varios analistas en el ámbito, cada fila dice de quién es. */
  mostrarAnalista: boolean
  visible: boolean
  actualizacion: number
  /** Un 42501 retira la vista entera, como en el resto de Gestión Diaria. */
  revalidar: () => void
  /** El título al que vuelve el foco si «Ver más» desaparece con el foco dentro. */
  encabezado: RefObject<HTMLHeadingElement | null>
}): JSX.Element {
  const lista = useCitasGestion(dia, ambito, id, visible, actualizacion)
  const { abrirLead } = usePanelesActions()
  const revocar = useEffectEvent(revalidar)
  useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
  const cuando = esHoy ? 'hoy' : 'ese día'

  if (lista.sinPermiso) {
    return <p role="alert" className="text-[13px] font-semibold text-[var(--destructive-text)]">Ya no tienes autorización para ver estas citas.</p>
  }
  if (lista.error && lista.items.length === 0) {
    return (
      <div role="alert" className="space-y-2 text-[13px]">
        <p className="font-semibold text-primary">No se pudo cargar la lista de citas. Esto no significa que no haya citas.</p>
        <button type="button" onClick={() => void lista.recargar()} aria-disabled={lista.enVuelo}
          className={cn('inline-flex h-9 cursor-pointer items-center rounded-[10px] px-3 text-[13px] font-bold text-[var(--accent-press)] hover:bg-accent/10 aria-disabled:opacity-50', FOCO)}>
          Reintentar
        </button>
      </div>
    )
  }
  const conteo = lista.cargando ? '' : lista.total === 0 ? `Ninguna cita agendada ${cuando}.`
    : `${plural(lista.total ?? lista.items.length, 'cita agendada', 'citas agendadas')} ${cuando}`
  return (
    <div className="space-y-1">
      {/* Montada siempre, también mientras carga: el conteo y el aviso de «la lista cambió»
          se anuncian al cambiar su texto (una región que nace con él no se anuncia). */}
      <p role="status" className="text-[12.5px] text-[var(--muted-foreground-strong)]">
        {lista.cambio && !lista.cargando && <span className="font-semibold text-foreground">La lista cambió; se actualizó. </span>}
        {conteo}
        {!lista.cargando && lista.consultadoEn && lista.total !== 0 && <> · consulta {horaLimaDe(lista.consultadoEn)}</>}
      </p>
      {lista.cargando && <PanelCargando filas={3} />}
      {!lista.cargando && lista.items.length > 0 && (
        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
        <ol role="list" aria-label="Citas agendadas" aria-busy={lista.enVuelo}>
          {lista.items.map((c) => (
            <li key={c.id} className="flex gap-3 border-b border-muted py-2.5">
              <time dateTime={c.creado_en} className="w-10 shrink-0 pt-0.5 text-[13px] font-bold tabular-nums text-foreground/80">
                <span className="sr-only">Agendada a las </span>{horaLimaDe(c.creado_en)}
              </time>
              <div className="min-w-0 flex-1 space-y-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge className="min-h-[22px] py-0 text-[11.5px]" color={ESTADO[c.estado].color}>{ESTADO[c.estado].texto}</Badge>
                  {c.lead_id && c.lead_nombre
                    ? <button type="button" onClick={() => void abrirLead(c.lead_id!)}
                      className={cn('cursor-pointer rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline', FOCO)}>{c.lead_nombre}</button>
                    : <span className="text-sm font-semibold text-[var(--muted-foreground-strong)]">Lead no visible</span>}
                  {mostrarAnalista && <span className="text-[12.5px] font-semibold text-[var(--muted-foreground-strong)]">· {c.vendedor_nombre ?? 'Sin analista'}</span>}
                </div>
                <p className="text-[12.5px] text-foreground/80">Cita: <time dateTime={c.vence_en}>{CUANDO.format(new Date(c.vence_en))}</time></p>
              </div>
            </li>
          ))}
        </ol>
      )}
      {lista.error && lista.items.length > 0 && (
        <p role="alert" className="text-[13px] font-semibold text-[var(--warning-text)]">No se pudo traer la siguiente página. Se conservan las ya consultadas.</p>
      )}
      {(lista.hayMas || (lista.error && lista.items.length > 0)) && (
        <div className="flex justify-center pt-2">
          <BotonVerMasCompacto ocupado={lista.enVuelo} error={Boolean(lista.error)}
            onPulsar={lista.error ? () => void lista.recargar() : () => void lista.cargarMas()}
            alSalirConFoco={() => encabezado.current?.focus({ preventScroll: true })} />
        </div>
      )}
    </div>
  )
}
