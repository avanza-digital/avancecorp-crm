import { useRef } from 'react'
import { Bell } from 'lucide-react'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { useAlertasCRM } from '@/lib/alertas-context'
import { presentarCortesJornada } from '@/lib/gestion-diaria-cortes-presentacion'
import { horaCorte } from '@/lib/gestion-diaria-avisos'
import { Button } from '@/components/ui/button'

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
  return <section className="gd-cortes" aria-label="Estado de cortes y avisos">
    <Button variant="ghost" className="min-h-11 shrink-0 text-base" aria-haspopup="dialog" onClick={abrir}>
      <Bell aria-hidden />Cortes y avisos
    </Button>
    <div className="gd-cortes-resumen">
      {estado ? <span>{estado}</span> : cortes.map((c) => <span key={c.clave}>
        <time dateTime={c.instante}>{c.hora}</time> {c.estado}
        {c.bajoMinimo > 0 && <strong> · {c.bajoMinimo} bajo el mínimo</strong>}
      </span>)}
      {avisos?.error ? <span>Avisos no disponibles</span> : avisos?.cargando ? <span>Consultando avisos…</span>
        : avisos?.datos && <>
          {!avisos.datos.avisos_habilitados && <span>Avisos pausados</span>}
          <span>{otros.errores.length ? 'Otros avisos sin confirmar' : ultimoConteo.current === null ? 'Consultando otros avisos…' : `Otros sin reconocer: ${ultimoConteo.current}`}</span>
        </>}
    </div>
    <p className="gd-cortes-consulta">{dia ? `Consulta ${horaCorte(dia.generado_en)} · Lima` : 'Sin consulta confirmada'}</p>
  </section>
}
