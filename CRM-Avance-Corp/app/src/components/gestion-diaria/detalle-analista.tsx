import { useId } from 'react'
import { Button } from '@/components/ui/button'
import { FRANJA_LLAMADAS, barrasPorHora, horaLimaDe } from '@/lib/gestion-diaria-analista'
import { horarioConfirmado, tiempoSinLlamar, type FilaEquipoDiario } from '@/lib/gestion-diaria-equipo'

/** F4.2: explica la foto del servidor; no reconstruye cifras desde el store. */
export function DetalleAnalista({ fila: f, dia, abrirLlamadas }: {
  fila: FilaEquipoDiario
  dia: string
  abrirLlamadas: () => void
}) {
  const id = useId()
  const barras = barrasPorHora(f.marcador)
  const contestadasPorHora = f.marcador.por_hora.reduce((total, h) => total + h.contestadas, 0)
  const fuera = f.marcador.por_hora.filter((h) => h.hora < FRANJA_LLAMADAS.desde || h.hora > FRANJA_LLAMADAS.hasta).toSorted((a, b) => a.hora - b.hora)
  return (
    <div className="space-y-5 pb-3 text-base">
      <dl className="grid gap-x-8 gap-y-3 py-3 sm:grid-cols-2 lg:grid-cols-4">
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
            {/* El conteo es visible además de las barras; no depende de un tooltip ni del color. */}
            {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Región desplazable: necesita foco para recorrer las horas con las flechas. */}
            <div role="region" aria-labelledby={`${id}-horas`} tabIndex={0}
              className="overflow-x-auto rounded focus-visible:outline-2 focus-visible:outline-ring">
              <ol aria-labelledby={`${id}-horas`} className="grid gap-2 pb-2" style={{ gridTemplateColumns: `repeat(${barras.length}, minmax(4.5rem, 1fr))` }}>
                {barras.map((b) => (
                  <li key={b.hora} className="flex flex-col items-center gap-2 tabular-nums">
                    <span className="sr-only">De {b.hora}:00 a {b.hora}:59: {b.llamadas} llamadas, {b.contestadas} contestadas</span>
                    <div aria-hidden className="relative flex h-16 w-full max-w-10 items-end border-b border-border">
                      <span className="w-full rounded-t bg-primary" style={{ height: `${b.llamadas / b.maximo * 100}%` }} />
                      <span className="absolute bottom-0 left-1/4 w-1/2 rounded-t bg-accent" style={{ height: `${b.contestadas / b.maximo * 100}%` }} />
                    </div>
                    <span aria-hidden className="font-semibold text-primary">{b.llamadas} / {b.contestadas}</span>
                    <span aria-hidden className="text-[var(--muted-foreground-strong)]">{String(b.hora).padStart(2, '0')} h</span>
                  </li>
                ))}
              </ol>
            </div>
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
