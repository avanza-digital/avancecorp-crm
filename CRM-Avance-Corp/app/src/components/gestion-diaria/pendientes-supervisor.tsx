// Pendientes del analista en la ficha del supervisor. Como el resumen (Miguel,
// 27/09/2026: «demasiado texto y no se entiende»): dos cuadros que SON el
// filtro (cada número abre su lista), las señales de leads solo si hay algo que
// decir, y filas limpias —hora, tipo, lead y «Vencida»—. Los estados que no se
// pueden confirmar se siguen diciendo, en una línea.
import { useEffect, useEffectEvent, useId, useLayoutEffect, useRef, useState } from 'react'
import { Check } from 'lucide-react'
import { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
import { CrmApiError } from '@/data/crm-api'
import { EnlaceSujetoGestion } from './enlace-sujeto'
import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import { instantePendiente } from '@/lib/gestion-diaria-pendientes'
import { Badge } from '@/components/ui/badge'
import { TIPO_EVENTO } from '@/lib/tipos'
import { cn } from '@/lib/utils'

const HORA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false })
const DIA_MES = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', day: 'numeric', month: 'numeric' })
const DIA_LIMA = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' })
const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const ENLACE = cn('inline-flex h-9 cursor-pointer items-center rounded-[10px] px-3 text-[13px] font-bold text-[var(--accent-press)] transition-colors hover:bg-accent/10 aria-disabled:cursor-default aria-disabled:opacity-50 pointer-coarse:h-11', FOCO)
const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`

type Accion = 'cargar' | 'reintentar' | 'actualizar'

const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es').trim()
/**
 * Las tareas automáticas se titulan «Acción — NOMBRE DEL LEAD»: el lead ya va al lado, no se repite.
 * Solo con la raya «—» y el nombre verificado: completo, o sus primeras palabras si son al menos dos
 * («GLORIA NAVARRO» de «GLORIA NAVARRO IBÁÑEZ»). «Revisar propuesta — A» se queda como está (Codex).
 */
function sinElLead(titulo: string, lead: string | null): string {
  const partes = /^(.+?) — (.+)$/.exec(titulo)
  if (!lead || !partes) return titulo
  const sufijo = normalizar(partes[2]!), nombre = normalizar(lead)
  const esElLead = sufijo === nombre || (sufijo.split(/\s+/).length >= 2 && nombre.startsWith(`${sufijo} `))
  return esElLead ? partes[1]! : titulo
}

export function PendientesSupervisor({ analista, nombre, dia, fila, visible, soloVencidasInicial, apertura, enfocar, actualizacion, revalidar }: {
  analista: string; nombre: string; dia: string; fila: FilaEquipoPresentada | undefined; visible: boolean
  soloVencidasInicial: boolean; apertura: number; enfocar: boolean; actualizacion: number; revalidar: () => void
}) {
  const [soloVencidas, setSoloVencidas] = useState(soloVencidasInicial)
  const lista = usePendientesSupervisor(dia, analista, soloVencidas, visible, apertura)
  const titulo = useRef<HTMLHeadingElement>(null)
  const tituloId = useId()
  const revision = useRef(actualizacion)
  const refrescar = useEffectEvent(() => { void lista.recargar() })
  const revocar = useEffectEvent(revalidar)
  useEffect(() => { if (enfocar) titulo.current?.focus({ preventScroll: true }) }, [enfocar])
  useEffect(() => {
    if (revision.current === actualizacion) return
    revision.current = actualizacion; refrescar()
  }, [actualizacion])
  useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
  const noInstalada = lista.error instanceof CrmApiError && lista.error.code === 'PGRST202'
  // «Ver más», «Reintentar» y «Actualizar» se desmontan al terminar: si el que
  // tenía el foco desaparece, el foco pasa al título (se sigue CADA control).
  const enfocado = useRef<Accion | null>(null)
  const recordar = (cual: Accion) => ({ onFocus: () => { enfocado.current = cual }, onBlur: () => { enfocado.current = null } })
  const cargarVisible = lista.hayMas
  const reintentarVisible = Boolean(lista.error) && !lista.sinPermiso
  const actualizarVisible = lista.congelada && !lista.error
  useLayoutEffect(() => {
    const cual = enfocado.current
    if (cual === null || (cual === 'cargar' ? cargarVisible : cual === 'reintentar' ? reintentarVisible : actualizarVisible)) return
    enfocado.current = null
    titulo.current?.focus({ preventScroll: true })
  }, [cargarVisible, reintentarVisible, actualizarVisible])
  const resumen = lista.pagina?.resumen ?? (fila && !lista.sinPermiso ? fila : null)
  const corte = lista.pagina ? instantePendiente(lista.pagina.pendientes_al) : null
  // Señales de LEADS (no son tareas): solo con número confirmado mayor que cero.
  const senales = fila && !lista.sinPermiso ? [
    fila.primer_intento_vencido ? plural(fila.primer_intento_vencido, 'lead con el primer intento tarde', 'leads con el primer intento tarde') : null,
    fila.datos_incompletos ? plural(fila.datos_incompletos, 'lead con datos por revisar', 'leads con datos por revisar') : null,
  ].filter((s): s is string => s !== null) : []
  const cuadros = [
    { vencidas: false, etiqueta: 'Todas', valor: resumen?.tareas_pendientes },
    { vencidas: true, etiqueta: 'Vencidas', valor: resumen?.tareas_vencidas },
  ]
  return <section aria-labelledby={tituloId} className="space-y-3 text-[13.5px]">
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
      {/* El nombre del analista lo dice la cabecera de la ficha; el lector lo oye aquí también. */}
      <h4 id={tituloId} ref={titulo} tabIndex={-1} className={cn('rounded-md text-[15px] font-extrabold text-primary', FOCO)}>
        Pendientes{' '}<span className="sr-only">de {nombre}</span>
      </h4>
      {lista.pagina && <p className="flex items-center gap-1 text-xs text-[var(--muted-foreground-strong)]">
        Consulta {HORA.format(new Date(lista.pagina.generado_en))}{actualizarVisible ? ' · pausada' : ''}
        {actualizarVisible && <button type="button" className={cn(ENLACE, 'h-7 px-2 text-xs')} aria-disabled={lista.enVuelo} {...recordar('actualizar')}
          onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Actualizar tareas</button>}
      </p>}
    </div>

    <div role="group" aria-label="Filtro de tareas" className="grid grid-cols-2 gap-2.5">
      {cuadros.map((c) => {
        const activo = c.vencidas === soloVencidas
        return (
          <button key={c.etiqueta} type="button" aria-pressed={activo} onClick={() => setSoloVencidas(c.vencidas)}
            className={cn('min-w-0 cursor-pointer rounded-xl border-2 px-3.5 py-3 text-left transition-colors', FOCO,
              activo ? 'border-accent bg-accent/[0.06]' : 'border-transparent bg-muted/70 hover:bg-muted')}>
            <span className="flex items-center gap-1 text-xs font-semibold text-[var(--muted-foreground-strong)]">
              {activo && <Check aria-hidden className="size-3.5 text-[var(--accent-press)]" />}{c.etiqueta}
            </span>
            {c.valor !== undefined && <>{' '}<span className={cn('mt-1 block text-[28px] font-extrabold leading-tight tabular-nums',
              c.vencidas && c.valor > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{c.valor}</span></>}
          </button>
        )
      })}
    </div>

    {senales.length > 0 && (
      // oxlint-disable-next-line jsx-a11y/no-redundant-roles
      <ul role="list" aria-label="Leads por revisar" className="space-y-1 rounded-xl bg-warning/10 px-4 py-2.5 text-[13px] font-semibold text-[var(--warning-text)]">
        {senales.map((s) => <li key={s}>{s}</li>)}
      </ul>
    )}

    {lista.cargando && <p role="status" className="text-[var(--muted-foreground-strong)]">Consultando tareas…</p>}
    {lista.error && <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-muted/70 px-4 py-2.5">
      <p className="font-semibold text-primary">{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas.'
        : noInstalada ? 'Detalle de tareas no disponible.'
          : lista.items.length > 0 ? 'Datos anteriores: no se pudo actualizar.' : 'No se pudo cargar la lista. No significa que esté vacía.'}</p>
      {reintentarVisible && <button type="button" className={ENLACE} aria-disabled={lista.enVuelo} {...recordar('reintentar')}
        onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Reintentar</button>}
    </div>}
    {!lista.error && lista.pagina && lista.items.length === 0 && <p className="text-[var(--muted-foreground-strong)]">{soloVencidas ? 'Sin tareas vencidas.' : 'Sin tareas pendientes.'}</p>}

    {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
    <ul role="list" aria-label="Lista de tareas pendientes">
      {lista.items.map((tarea) => {
        const vence = new Date(tarea.vence_en)
        const instante = instantePendiente(tarea.vence_en)
        const vencida = corte !== null && instante !== null && instante < corte
        const tipo = TIPO_EVENTO[tarea.tipo] ?? tarea.tipo
        const tituloTarea = sinElLead(tarea.titulo.trim(), tarea.lead_nombre) || 'Sin título'
        return (
          <li key={tarea.id} className="flex gap-3 border-b border-muted py-2.5 break-words">
            <time dateTime={vence.toISOString()} className="w-11 shrink-0 pt-0.5 text-[13px] font-bold tabular-nums text-foreground/80">
              {HORA.format(vence)}
              {DIA_LIMA.format(vence) !== dia && <span className="block text-[11.5px] font-semibold text-[var(--muted-foreground-strong)]">{DIA_MES.format(vence)}</span>}
            </time>
            <div className="min-w-0 flex-1 space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <Badge className="min-h-[22px] py-0 text-[11.5px]" color="var(--accent-press)">{tipo}</Badge>
                {vencida && <Badge className="min-h-[22px] py-0 text-[11.5px]" color="var(--destructive-text)">Vencida</Badge>}
                <EnlaceSujetoGestion sujeto={tarea} />
              </div>
              {/* El título solo si dice algo más que el tipo («WhatsApp» / «WhatsApp»). */}
              {normalizar(tituloTarea) !== normalizar(tipo) && <p className="text-[13px] leading-snug text-foreground/80">{tituloTarea}</p>}
            </div>
          </li>
        )
      })}
    </ul>
    {lista.pagina && <p role="status" className="sr-only">{plural(lista.items.length, 'tarea cargada', 'tareas cargadas')}{lista.hayMas ? ' · hay más' : lista.error ? ' · consulta incompleta' : ''}</p>}
    {cargarVisible && <div className="flex justify-center">
      <button type="button" className={ENLACE} aria-disabled={lista.enVuelo} aria-busy={lista.enVuelo || undefined} {...recordar('cargar')}
        onClick={() => { if (!lista.enVuelo) void lista.cargarMas() }}>{lista.enVuelo ? 'Cargando…' : 'Ver más'}</button>
    </div>}
  </section>
}
