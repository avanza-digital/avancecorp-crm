import { useId } from 'react'
import { Button } from '@/components/ui/button'
import { FRANJA_LLAMADAS, barrasPorHora, horaLimaDe } from '@/lib/gestion-diaria-analista'
import { horarioConfirmado, tiempoSinLlamar, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'

/** F4.2: explica la foto del servidor; no reconstruye cifras desde el store. */
export function DetalleAnalista({ fila: f, dia, abrirLlamadas }: {
  fila: FilaEquipoPresentada
  dia: string
  abrirLlamadas: () => void
}) {
  const id = useId()
  const barras = barrasPorHora(f.marcador)
  const contestadasPorHora = f.marcador.por_hora.reduce((total, h) => total + h.contestadas, 0)
  const fuera = f.marcador.por_hora.filter((h) => h.hora < FRANJA_LLAMADAS.desde || h.hora > FRANJA_LLAMADAS.hasta).toSorted((a, b) => a.hora - b.hora)
  return (
    <div className="space-y-5 pb-3 text-base">
      <dl className="gd-metricas-detalle">
        {[
          ['Llamadas útiles', f.marcador.utiles], ['Leads distintos', f.marcador.leads_tocados],
          ['Llamadas por lead', f.llamadas_por_lead ?? '—'], ['Citas pendientes para hoy', f.citas_hoy],
          ['Primera llamada', horaLimaDe(f.marcador.primera_llamada_en)], ['Última llamada', horaLimaDe(f.marcador.ultima_llamada_en)],
          ['Tiempo sin llamar', tiempoSinLlamar(f.minutos_sin_llamar)], ['Última gestión', horaLimaDe(f.ultima_gestion_en)],
        ].map(([titulo, valor]) => <div key={titulo}><dt className="text-[var(--muted-foreground-strong)]">{titulo}</dt><dd className="mt-1 font-semibold tabular-nums">{valor}</dd></div>)}
      </dl>
      <div className="space-y-3 border-t border-border pt-4">
        <h3 id={`${id}-horas`} className="font-semibold text-primary">Llamadas por hora de {f.nombre_completo}</h3>
        <p className="text-[var(--muted-foreground-strong)]">{dia} · Hora de Lima. Llamadas / contestadas en cada hora.</p>
        {!horarioConfirmado(f.marcador) ? (
          <p role="status">No se pudo confirmar el desglose por hora. Consulta las llamadas en el registro; no se muestran ceros como sustituto.</p>
        ) : f.marcador.llamadas === 0 ? (
          <p>No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.</p>
        ) : (
          <>
            <div role="img" aria-label="Llamadas y contestadas de 08 a 20 horas. Cifras completas en el desplegable siguiente.">
              <div aria-hidden className="gd-grafico-horas">
                {barras.map((b) => <div key={b.hora} className="relative flex h-20 items-end border-b border-border">
                  <span className="w-full rounded-t bg-primary" style={{ height: `${b.llamadas / b.maximo * 100}%` }} />
                  <span className="absolute bottom-0 left-1/4 w-1/2 rounded-t bg-accent" style={{ height: `${b.contestadas / b.maximo * 100}%` }} />
                </div>)}
              </div>
              <div aria-hidden className="mt-2 flex justify-between tabular-nums"><span>08 h</span><span>14 h</span><span>20 h</span></div>
            </div>
            <p>Llamadas: azul oscuro · Contestadas: azul</p>
            <details className="gd-cifras-horas">
              <summary>Ver cifras por hora</summary>
              <ol aria-labelledby={`${id}-horas`}>
                {barras.map((b) => <li key={b.hora}>De {b.hora}:00 a {b.hora}:59: {b.llamadas} llamadas, {b.contestadas} contestadas</li>)}
              </ol>
            </details>
            {contestadasPorHora !== f.marcador.contestadas && (
              <p className="text-[var(--muted-foreground-strong)]">Las contestadas por hora incluyen registros de «Número errado» o «No es la persona» que el total de contacto útil excluye.</p>
            )}
            {fuera.length > 0 && (
              <p className="text-[var(--muted-foreground-strong)]">Fuera de la franja 08–20: {fuera.map((h) => `${String(h.hora).padStart(2, '0')} h: ${h.llamadas} ${h.llamadas === 1 ? 'llamada' : 'llamadas'} / ${h.contestadas} ${h.contestadas === 1 ? 'contestada' : 'contestadas'}`).join('; ')}.</p>
            )}
          </>
        )}
        <div className="flex flex-wrap items-center gap-4">
          <Button variant="outline" className="min-h-11 text-base" onClick={abrirLlamadas}
            aria-label={`Ver llamadas del día de ${f.nombre_completo}`}>Ver llamadas del día</Button>
          <p className="max-w-2xl text-[var(--muted-foreground-strong)]">En el registro puedes leer cada resultado y abrir la ficha del lead. Se consulta al abrirlo y sólo muestra actividades cuyos leads siguen visibles para tu sesión; puede diferir de esta foto.</p>
        </div>
      </div>
    </div>
  )
}
