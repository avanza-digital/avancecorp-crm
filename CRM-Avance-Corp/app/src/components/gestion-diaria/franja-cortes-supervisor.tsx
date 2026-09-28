import { useRef } from 'react'
import { Bell } from 'lucide-react'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { useAlertasCRM } from '@/lib/alertas-context'
import { presentarCortesJornada } from '@/lib/gestion-diaria-cortes-presentacion'
import { horaCorte } from '@/lib/gestion-diaria-avisos'

export function FranjaCortesSupervisor({ consulta, abrir }: { consulta: DiaEquipoHook; abrir: () => void }) {
  const avisos = useGestionDiariaAvisos()
  const otros = useAlertasCRM()
  const dia = consulta.error ? null : consulta.dia
  const cortes = presentarCortesJornada(dia)
  const estado = consulta.error ? 'Cortes no disponibles' : consulta.cargando ? 'Consultando cortes…'
    : !dia?.cortes ? 'Sin detalle de cortes' : dia.cortes.estado === 'desactivados' ? 'Cortes desactivados'
      : dia.cortes.estado === 'no_laborable' ? 'Día no laborable' : null
  const ultimoConteo = useRef<number | null>(null)
  if (avisos?.error || !avisos?.datos || otros.errores.length) ultimoConteo.current = null
  else if (!otros.cargando) ultimoConteo.current = otros.alertas.filter((a) => !a.corte && !a.reconocimiento).length
  // Diseño de Gestión Diaria (27/09): una tira fina al pie, mismos estados.
  return <section className="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl border border-border bg-card px-2 py-[3px] text-[13px]" aria-label="Estado de cortes y avisos">
    <button type="button" aria-haspopup="dialog" onClick={abrir}
      className="inline-flex h-9 shrink-0 cursor-pointer items-center gap-1.5 rounded-[10px] px-2.5 font-semibold text-primary transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11">
      <Bell aria-hidden className="size-4" />Cortes y avisos
    </button>
    <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-4 gap-y-0.5 text-[var(--muted-foreground-strong)] [overflow-wrap:anywhere]">
      {estado ? <span>{estado}</span> : cortes.map((c) => <span key={c.clave}>
        <time dateTime={c.instante}>{c.hora}</time> {c.estado}
        {c.bajoMinimo > 0 && <strong className="font-semibold text-[var(--warning-text)]"> · {c.bajoMinimo} bajo el mínimo</strong>}
      </span>)}
      {avisos?.error ? <span>Avisos no disponibles</span> : avisos?.cargando ? <span>Consultando avisos…</span>
        : avisos?.datos && <>
          {!avisos.datos.avisos_habilitados && <span>Avisos pausados</span>}
          <span>{otros.errores.length ? 'Otros avisos sin confirmar' : ultimoConteo.current === null ? 'Consultando otros avisos…' : `Otros sin reconocer: ${ultimoConteo.current}`}</span>
        </>}
    </div>
    <p className="whitespace-nowrap pr-2 text-xs tabular-nums text-[var(--muted-foreground-strong)]">{dia ? `Consulta ${horaCorte(dia.generado_en)} · Lima` : 'Sin consulta confirmada'}</p>
  </section>
}
