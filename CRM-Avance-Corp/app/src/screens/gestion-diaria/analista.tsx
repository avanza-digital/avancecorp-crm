// Gestión Diaria · Fase 3 — «Mi día» del analista. Responde una sola pregunta:
// ¿a quién llamo AHORA? La cola sale de `crm.cola_accion_v2_fn` (la misma del
// mundo SLA) y el resto del día —marcador, compromisos, señales por lead y los
// descartes con su «Deshacer»— de `crm.gestion_diaria_analista_fn`. Aquí no se
// calcula negocio: se ORDENA (`ordenarColaDiaria`, función pura probada) y se
// presenta. Al guardar un resultado, la pantalla salta a la fila siguiente.
//
// «Hoy» NO cambia: sigue siendo «las 3 cosas de ahora» (decisión de Miguel).
// Esta pantalla es la cola COMPLETA del día, y las dos comparten el primer
// ítem: el lead sin primer intento manda en ambas (test compartido).
import { useId, useMemo, useRef, useState, type JSX } from 'react'
import { CalendarClock, ClipboardList, PhoneCall, RefreshCw, RotateCcw, Target, Users } from 'lucide-react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, type Etapa, type Lead, type Tarea } from '@/lib/tipos'
import { tareaQueCierra } from '@/lib/contacto-tarea'
import { presentarCitas } from '@/lib/terminologia'
import {
  ETIQUETA_NIVEL, GRUPOS_DIA, agruparDiaria, barrasPorHora, cuandoLimaDe, detalleDeFila, filasDiariasDemo,
  horaLimaDe, llamadasFueraDeFranja, ordenarColaDiaria, textoTasa,
  type Descartado, type DiaAnalista, type FilaDiaria,
} from '@/lib/gestion-diaria-analista'
import { useDiaAnalista } from '@/data/gestion-diaria-queries'
import { useColaSlaPagina } from '@/data/sla-operacion-queries'
import { AccionesContacto } from '@/components/app/contacto'
import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

const LIMITE_COLA = 100
const COLOR_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  // Verde NO (decisión #3 de Miguel): «Bien» va en navy sobre fondo tenue.
  bien: 'var(--primary)',
  atencion: 'var(--warning)',
  bajo: 'var(--destructive)',
}

export function GestionDiariaAnalista(): JSX.Element {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { ambito, tareasDe } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()
  const [panel, setPanel] = useState<{ lead: Lead; tarea: Tarea | null } | null>(null)
  const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  const encabezado = useRef<HTMLHeadingElement>(null)
  const botones = useRef(new Map<string, HTMLButtonElement>())

  const dia = useDiaAnalista(null, null)
  // La cola del día: la misma fuente que «Seguimiento comercial», sin filtros.
  const cola = useColaSlaPagina({ senal: 'todas', etapa: null, analista_id: null }, null, LIMITE_COLA, !yo?.demo)
  const paginaCola = cola.error ? undefined : cola.data

  const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
  const filas = useMemo<FilaDiaria[]>(() => {
    if (dia.dia === null) return []
    if (yo?.demo) return filasDiariasDemo(dia.dia.cartera, ahora, dia.dia.dia)
    return ordenarColaDiaria(paginaCola?.items ?? [], dia.dia.cartera)
  }, [ahora, dia.dia, paginaCola?.items, yo?.demo])
  const grupos = useMemo(() => agruparDiaria(filas), [filas])

  function abrirPanel(fila: FilaDiaria) {
    const lead = leadsPorId.get(fila.lead_id)
    if (lead === undefined) { void abrirLead(fila.lead_id); return }
    setPanel({ lead, tarea: tareaQueCierra(tareasDe(lead.id), 'tel', yo?.id, ahora) ?? null })
  }
  /** Al guardar, el foco salta a la fila siguiente: el analista sigue marcando. */
  function saltarASiguiente(leadId: string) {
    const indice = filas.findIndex((f) => f.lead_id === leadId)
    const siguiente = filas[indice + 1]
    if (siguiente === undefined) { encabezado.current?.focus(); return }
    // El re-render por la invalidación de la cola llega después del cierre del
    // diálogo: el foco se pide en el siguiente cuadro, cuando la fila ya existe.
    requestAnimationFrame(() => botones.current.get(siguiente.lead_id)?.focus())
  }
  async function deshacer(d: Descartado) {
    if (deshaciendo !== null) return
    setDeshaciendo(d.actividad_id)
    try {
      const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
      await deshacerResultadoLlamada(d.actividad_id)
      await dia.recargar()
      toast.success(`Deshecho: ${d.lead_nombre} vuelve a tu cartera`)
    } catch (causa) {
      const { mensajeDeError } = await import('@/data/crm-api')
      toast.error(mensajeDeError(causa, 'No se pudo deshacer el descarte.'))
    } finally {
      setDeshaciendo(null)
    }
  }

  const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
  const colaCaida = !yo?.demo && (cola.error != null)

  return (
    <div className="mx-auto w-full max-w-[1640px] space-y-6">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 ref={encabezado} tabIndex={-1} className="text-xl font-bold leading-tight text-primary">¿A quién llamo ahora?</h2>
          <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">
            Tu cola del día completa, ordenada por urgencia. {corte ? `Corte ${corte} (Lima)` : 'Sin corte confirmado'} · se actualiza cada minuto.
          </p>
        </div>
        <Button variant="outline" size="sm" disabled={dia.enVuelo} onClick={() => { void dia.recargar(); void cola.refetch() }}>
          <RefreshCw aria-hidden className={dia.enVuelo ? 'motion-safe:animate-spin' : ''} /> Actualizar
        </Button>
      </header>

      {dia.error != null && dia.dia === null ? (
        <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
      ) : dia.dia === null && dia.cargando ? (
        <PanelCargando filas={6} />
      ) : dia.dia === null ? (
        <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
      ) : (
        <>
          <Marcador dia={dia.dia} />

          <section aria-labelledby={`${id}-cola`} className="space-y-4">
            <h3 id={`${id}-cola`} className="text-base font-bold text-primary">
              Tu cola de hoy <span className="text-sm font-semibold text-[var(--muted-foreground-strong)]">· {filas.length} {filas.length === 1 ? 'pendiente' : 'pendientes'}</span>
            </h3>
            {colaCaida && (
              <p role="alert" className="text-xs font-semibold text-destructive">
                No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
              </p>
            )}
            {dia.dia.cartera_truncada && (
              <p role="status" className="text-xs font-semibold text-[var(--muted-foreground-strong)]">
                Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
              </p>
            )}
            {grupos.length === 0 ? (
              <PanelVacio icono={PhoneCall} titulo="No tienes nada pendiente ahora"
                detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana." />
            ) : grupos.map(({ grupo, filas: delGrupo }) => {
              const meta = GRUPOS_DIA.find((g) => g.clave === grupo)!
              return (
                <div key={grupo} className="space-y-2">
                  <div className="flex flex-wrap items-baseline gap-2">
                    <h4 className="text-sm font-bold text-foreground">{meta.etiqueta} · {delGrupo.length}</h4>
                    <span className="text-xs text-[var(--muted-foreground-strong)]">{meta.ayuda}</span>
                  </div>
                  <ol aria-label={`${meta.etiqueta} (${delGrupo.length})`} className="divide-y divide-border rounded-xl border border-border bg-card">
                    {delGrupo.map((fila) => (
                      <FilaCola key={fila.lead_id} fila={fila} lead={leadsPorId.get(fila.lead_id) ?? null}
                        sinConversacionDias={dia.dia!.sin_conversacion_dias}
                        registrarRef={(el) => { if (el) botones.current.set(fila.lead_id, el); else botones.current.delete(fila.lead_id) }}
                        onRegistrar={() => abrirPanel(fila)} onAbrirFicha={() => { void abrirLead(fila.lead_id) }} />
                    ))}
                  </ol>
                </div>
              )
            })}
          </section>

          <Compromisos dia={dia.dia} onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
          <Descartados dia={dia.dia} deshaciendo={deshaciendo} onDeshacer={(d) => { void deshacer(d) }}
            onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
          {yo?.demo && <p className="text-xs text-muted-foreground">Datos de ejemplo: en la sesión real tu día sale del servidor.</p>}
        </>
      )}

      {panel !== null && (
        <RegistrarResultado lead={panel.lead} tarea={panel.tarea} onClose={() => setPanel(null)}
          onGuardado={() => saltarASiguiente(panel.lead.id)} />
      )}
    </div>
  )
}

function Marcador({ dia }: { dia: DiaAnalista }): JSX.Element {
  const m = dia.marcador
  const barras = barrasPorHora(m)
  const fuera = llamadasFueraDeFranja(m)
  const stats: StatChipData[] = [
    { icon: PhoneCall, label: 'Llamadas', value: String(m.llamadas), sub: `${m.contestadas} contestadas`, tone: 'primary' },
    {
      icon: Target, label: 'Tasa de contacto', value: textoTasa(m),
      // El «—» de la tasa sin llamadas útiles no lo pronuncia un lector de
      // pantalla: se dice «sin dato» para que no suene a cero.
      ...(m.tasa_contacto_pct === null ? { valorAccesible: 'sin dato' } : {}),
      sub: m.nivel === null ? `Se juzga desde ${dia.umbrales.minimo_llamadas_utiles} llamadas útiles` : ETIQUETA_NIVEL[m.nivel],
      tone: m.nivel === 'bajo' ? 'bad' : m.nivel === 'atencion' ? 'warn' : 'primary',
    },
    { icon: Users, label: 'Leads tocados', value: String(m.leads_tocados) },
    { icon: CalendarClock, label: presentarCitas('Citas agendadas'), value: String(m.citas_agendadas) },
  ]
  return (
    <section aria-label="Mi marcador de hoy" className="space-y-3">
      <div className="flex flex-wrap items-baseline gap-2">
        <h3 className="text-base font-bold text-primary">Mi marcador de hoy</h3>
        {m.nivel !== null && <Badge color={COLOR_NIVEL[m.nivel]} dot>{ETIQUETA_NIVEL[m.nivel]}</Badge>}
      </div>
      <StatStrip stats={stats} />
      <p className="text-xs text-[var(--muted-foreground-strong)]">
        Llamadas = marcadas + no contestadas. No incluye WhatsApp ni citas. Un número errado no entra en la tasa.
        {m.primera_llamada_en !== null && ` Primera ${horaLimaDe(m.primera_llamada_en)}, última ${horaLimaDe(m.ultima_llamada_en)} (Lima).`}
      </p>
      {m.llamadas > 0 && (
        <div>
          <h4 className="text-xs font-semibold text-[var(--muted-foreground-strong)]">Llamadas por hora (08–20, Lima)</h4>
          <ul className="mt-2 flex items-end gap-1" aria-label="Llamadas por hora">
            {barras.map((b) => (
              <li key={b.hora} className="flex min-w-0 flex-1 flex-col items-center gap-1">
                <span className="w-full rounded-t bg-primary/80" style={{ height: `${Math.round((b.llamadas / b.maximo) * 40) + 2}px` }}
                  aria-hidden />
                <span className="sr-only">{b.hora}:00 — {b.llamadas} llamadas, {b.contestadas} contestadas</span>
                <span aria-hidden className="text-[10px] tabular-nums text-muted-foreground">{b.hora}</span>
              </li>
            ))}
          </ul>
          {fuera > 0 && <p className="mt-1 text-[11px] text-[var(--muted-foreground-strong)]">{fuera} fuera de la franja 08–20.</p>}
        </div>
      )}
    </section>
  )
}

function FilaCola({ fila, lead, sinConversacionDias, onRegistrar, onAbrirFicha, registrarRef }: {
  fila: FilaDiaria
  lead: Lead | null
  sinConversacionDias: number
  onRegistrar: () => void
  onAbrirFicha: () => void
  registrarRef: (el: HTMLButtonElement | null) => void
}): JSX.Element {
  const etapa = ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
  return (
    <li className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
      <div className="min-w-0 space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <button type="button" onClick={onAbrirFicha}
            className="inline-flex min-h-9 items-center rounded-md text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">
            {fila.nombre_completo}
          </button>
          <Badge color={fila.severidad === 'critica' ? 'var(--destructive)' : 'var(--muted-foreground-strong)'} variant="outline">{etapa}</Badge>
          {fila.referencia_en !== null && (
            <span className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">{cuandoLimaDe(fila.referencia_en)}</span>
          )}
        </div>
        <p className="text-xs text-[var(--muted-foreground-strong)]">{detalleDeFila(fila, sinConversacionDias)}</p>
      </div>
      <div className="flex shrink-0 flex-wrap items-center gap-2">
        {lead !== null && <AccionesContacto lead={lead} destacada />}
        <Button ref={registrarRef} variant="accent" size="sm" className="h-11 sm:h-9" onClick={onRegistrar}>
          Registrar resultado
        </Button>
      </div>
    </li>
  )
}

function Compromisos({ dia, onAbrirFicha }: { dia: DiaAnalista; onAbrirFicha: (leadId: string) => void }): JSX.Element {
  const id = useId()
  return (
    <section aria-labelledby={`${id}-titulo`} className="space-y-2">
      <h3 id={`${id}-titulo`} className="text-base font-bold text-primary">
        Mi seguimiento <span className="text-sm font-semibold text-[var(--muted-foreground-strong)]">· {dia.compromisos_total} {dia.compromisos_total === 1 ? 'compromiso' : 'compromisos'}</span>
      </h3>
      {dia.compromisos.length === 0 ? (
        <PanelVacio icono={CalendarClock} titulo="Sin compromisos a partir de mañana" detalle="Lo de hoy y lo vencido ya está en tu cola." />
      ) : (
        <ol aria-label="Mis compromisos" className="divide-y divide-border rounded-xl border border-border bg-card">
          {dia.compromisos.map((c) => (
            <li key={c.tarea_id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5">
              <div className="min-w-0">
                <button type="button" onClick={() => onAbrirFicha(c.lead_id)}
                  className="inline-flex min-h-9 items-center rounded-md text-sm font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">
                  {c.lead_nombre}
                </button>
                <p className="text-xs text-[var(--muted-foreground-strong)]">
                  {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
                  {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
                </p>
              </div>
              <span className="text-xs font-semibold tabular-nums text-foreground">{cuandoLimaDe(c.vence_en)}</span>
            </li>
          ))}
        </ol>
      )}
      {dia.compromisos_total > dia.compromisos.length && (
        <p className="text-xs text-[var(--muted-foreground-strong)]">
          Se muestran los {dia.compromisos.length} más próximos de {dia.compromisos_total}. El resto está en Agenda.
        </p>
      )}
    </section>
  )
}

function Descartados({ dia, deshaciendo, onDeshacer, onAbrirFicha }: {
  dia: DiaAnalista
  deshaciendo: string | null
  onDeshacer: (d: Descartado) => void
  onAbrirFicha: (leadId: string) => void
}): JSX.Element | null {
  const id = useId()
  if (dia.descartados.length === 0) return null
  return (
    <section aria-labelledby={`${id}-titulo`} className="space-y-2">
      <h3 id={`${id}-titulo`} className="text-base font-bold text-primary">Descartados hoy · {dia.descartados.length}</h3>
      <p className="text-xs text-[var(--muted-foreground-strong)]">
        Están en el Centro de rescate con su motivo. Puedes deshacer el descarte durante 24 horas; el lead vuelve a tu cartera con un ciclo nuevo.
      </p>
      <ol aria-label="Descartados hoy" className="divide-y divide-border rounded-xl border border-border bg-card">
        {dia.descartados.map((d) => (
          <li key={d.actividad_id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5">
            <div className="min-w-0">
              <button type="button" onClick={() => onAbrirFicha(d.lead_id)}
                className="inline-flex min-h-9 items-center rounded-md text-sm font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">
                {d.lead_nombre}
              </button>
              <p className="text-xs text-[var(--muted-foreground-strong)]">
                {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
                {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
              </p>
            </div>
            {d.puede_deshacer ? (
              <Button variant="outline" size="sm" disabled={deshaciendo !== null} onClick={() => onDeshacer(d)}>
                <RotateCcw aria-hidden /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
              </Button>
            ) : (
              <span className="text-xs text-muted-foreground">Sin deshacer</span>
            )}
          </li>
        ))}
      </ol>
    </section>
  )
}
