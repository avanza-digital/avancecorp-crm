import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import { ESTADO_RESULTADO_CORTE, presentarCortesJornada } from '@/lib/gestion-diaria-cortes-presentacion'
import { horaCorte } from '@/lib/gestion-diaria-avisos'
import { Button } from '@/components/ui/button'
import { ChevronRight } from 'lucide-react'

export function EstadoCortesEquipo({ consulta, abrirAnalista }: {
  consulta: DiaEquipoHook; abrirAnalista: (id: string) => void
}) {
  const dia = consulta.error ? null : consulta.dia
  if (consulta.error) return <div role="alert" className="space-y-2">
    <p>No pudimos confirmar el estado de los cortes. Los avisos se consultan por separado.</p>
    <Button variant="outline" className="min-h-11 text-base" disabled={consulta.enVuelo} onClick={() => { void consulta.recargar() }}>Actualizar cortes</Button>
  </div>
  if (consulta.cargando) return <p role="status">Consultando el estado de los cortes…</p>
  if (!dia?.cortes) return <p>El detalle de los cortes no está disponible. Esto no confirma que estén desactivados.</p>
  const cortes = dia.cortes
  return <section aria-label="Resultados de los cortes" className="space-y-3">
    <p>{dia.dia} · Lima. Consulta {horaCorte(dia.generado_en)}.</p>
    {cortes.estado === 'desactivados' ? <p>Los cortes están desactivados para esta jornada.</p>
      : cortes.estado === 'no_laborable' ? <p>Hoy no es jornada de cortes.</p>
        : <>
          <p>Jornada de {horaCorte(cortes.inicio_jornada!)} a {horaCorte(cortes.fin_jornada!)}. {cortes.segundo_corte_en ? 'Dos cortes previstos.' : 'Un corte previsto.'}</p>
          {presentarCortesJornada(dia).map((c) => <details key={c.clave} className="gd-resultado-corte">
            <summary><ChevronRight aria-hidden className="gd-corte-indicador" /><span>{c.titulo} · {c.hora}</span><strong>{c.estado}</strong>
              {c.estado !== 'Programado' && <span>{c.bajoMinimo} bajo el mínimo</span>}</summary>
            <div className="space-y-3 px-3 pb-3">
              <p>{c.cumplidos} cumplidos · {c.recuperados} recuperados · {c.sinCartera} sin cartera abierta{c.sinEvaluar ? ` · ${c.sinEvaluar} sin evaluar` : ''}.</p>
              {c.personas.length === 0 ? <p>No hay analistas activos en el equipo consultado.</p> : <ul className="divide-y divide-border">
                {c.personas.map((p) => <li key={p.analista} className="gd-persona-corte">
                  <div><strong>{p.nombre}</strong><p>{ESTADO_RESULTADO_CORTE[p.estado]}
                    {p.llamadas !== null ? ` · ${p.llamadas} llamadas al corte` : ''}
                    {p.objetivo !== null ? ` · mínimo ${p.objetivo}` : ' · mínimo por determinar'}
                    {p.llamadas_recuperacion !== null ? ` · ${p.llamadas_recuperacion} en recuperación` : ''}</p></div>
                  <Button variant="outline" className="min-h-11 whitespace-normal text-base" onClick={() => abrirAnalista(p.analista)}>Ver llamadas de {p.nombre}</Button>
                </li>)}
              </ul>}
            </div>
          </details>)}
          <p className="text-[var(--muted-foreground-strong)]">El mínimo y la recuperación corresponden a la evaluación del corte. Sin cartera abierta no genera aviso de corte.</p>
        </>}
  </section>
}
