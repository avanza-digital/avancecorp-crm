/* oxlint-disable jsx-a11y/no-redundant-roles -- Los roles conservan la tabla en WebKit cuando el diseño móvil cambia display. */
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { cifraPulso } from '@/lib/gestion-diaria-pulso'
import type { HabitosGerencia, PersonaHabitos } from '@/lib/gestion-diaria-habitos'
import { hashDe } from '@/lib/router'

const ESTADO_CORTE = { pendiente: 'Aún pendiente', sin_cartera: 'Sin cartera', cumplido: 'A tiempo', recuperado: 'Recuperado', incumplido: 'Incumplido' } as const
function cortesDelDia(d: PersonaHabitos['dias'][number]) {
  if (d.cortes.estado !== 'activo') return d.cortes.estado === 'no_laborable' ? 'No laborable' : 'Desactivados'
  return [d.cortes.primer_corte, d.cortes.segundo_corte].filter((c) => c !== null).map((c, i) => `${i + 1}. ${ESTADO_CORTE[c.estado]}`).join(' · ') || 'Sin cortes programados'
}

export function ReporteHabitos({ datos, alAbrirAnalista }: { datos: HabitosGerencia; alAbrirAnalista: () => void }) {
  return <section aria-label="Reporte de hábitos" className="space-y-5">
    <div className="gp-nota">
      <p><strong>{datos.desde} al {datos.hasta}</strong> · {datos.dias_incluidos} días calendario{datos.dias_incluidos < datos.dias_solicitados ? ' (inicio limitado al histórico disponible)' : ''}.</p>
      <p>Contacto de la operación: <strong>{cifraPulso(datos.operacion.tasa_contacto, true)}</strong> · {datos.operacion.contestadas} contestadas de {datos.operacion.utiles} útiles.</p>
      <p>Equipo y cartera de referencia actuales. Los cortes usan la política vigente en cada fecha. Estos datos orientan la capacitación; no explican las causas de una pausa.</p>
      <p>La alerta de tasa muy baja sigue apagada. No se ha fijado un umbral.</p>
    </div>
    {datos.personas.length === 0 && <p>No hay analistas activos en el organigrama actual.</p>}
    {datos.personas.map((p) => <article key={p.analista_id} className="gp-panel">
      <div className="gp-cabecera-fila">
        <h3 className="text-lg font-semibold text-primary"><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: p.analista_id })} onClick={alAbrirAnalista}>{p.nombre_completo}</a></h3>
        <span>{p.resumen.llamadas} llamadas en el período</span>
      </div>
      <dl className="gp-habitos-resumen">
        <div><dt>Contacto personal</dt><dd>{cifraPulso(p.resumen.tasa_contacto, true)}</dd><p>{p.resumen.contestadas} de {p.resumen.utiles} útiles</p></div>
        <div><dt>Contacto del equipo</dt><dd>{cifraPulso(p.equipo.tasa_contacto, true)}</dd><p>{p.equipo.utiles === null ? 'Sin equipo comercial asignado' : `${p.equipo.contestadas} de ${p.equipo.utiles} útiles`}</p></div>
        <div><dt>Distribución diaria</dt><dd>{p.distribucion_contacto.dias_validos ? `Mediana ${cifraPulso(p.distribucion_contacto.mediana, true)}` : 'Muestra insuficiente'}</dd><p>{p.distribucion_contacto.dias_validos} días con muestra suficiente</p>
          {p.distribucion_contacto.dias_validos > 0 && <p>Mitad central: {cifraPulso(p.distribucion_contacto.p25, true)} a {cifraPulso(p.distribucion_contacto.p75, true)}</p>}</div>
        <div><dt>Cortes a tiempo</dt><dd>{p.cumplimiento.evaluables ? `${p.cumplimiento.cumplidos_a_tiempo} de ${p.cumplimiento.evaluables}` : 'Sin cortes evaluables'}</dd><p>{p.cumplimiento.recuperados} recuperados · {p.cumplimiento.incumplidos} incumplidos</p><p>{p.cumplimiento.pendientes} pendientes · {p.cumplimiento.sin_cartera} sin cartera</p></div>
      </dl>
      <details className="gp-dias-habitos">
        <summary>Ver días de {p.nombre_completo}</summary>
        <div className="gp-tabla-scroll"><table role="table" className="gp-tabla" aria-label={`Hábitos diarios de ${p.nombre_completo}`}>
          <thead role="rowgroup"><tr role="row"><th role="columnheader" scope="col">Día</th><th role="columnheader" scope="col">Primera llamada</th><th role="columnheader" scope="col">Mayor hueco entre llamadas</th><th role="columnheader" scope="col">Contacto</th><th role="columnheader" scope="col">Cortes</th></tr></thead>
          <tbody role="rowgroup">{p.dias.map((d) => <tr role="row" key={d.dia}>
            <th role="rowheader" scope="row">{d.dia}</th>
            <td role="cell" data-etiqueta="Primera llamada">{horaLimaDe(d.primera_llamada_en)}{d.llamadas === 0 && <p>Sin llamadas</p>}</td>
            <td role="cell" data-etiqueta="Mayor hueco">{d.jornada.estado === 'no_laborable' ? 'No laborable' : d.jornada.hueco
              ? <>{cifraPulso(d.jornada.hueco.minutos)} min<p>{horaLimaDe(d.jornada.hueco.desde)}–{horaLimaDe(d.jornada.hueco.hasta)}</p></>
              : d.jornada.estado === 'no_iniciada' ? 'Jornada sin iniciar' : 'Menos de dos llamadas en jornada'}
              {d.jornada.estado !== 'no_laborable' && d.jornada.estado !== 'no_iniciada' && <p>Desde apertura: {cifraPulso(d.jornada.silencio_inicio_minutos)} min · hasta {horaLimaDe(d.jornada.observado_hasta)}: {cifraPulso(d.jornada.silencio_final_minutos)} min</p>}</td>
            <td role="cell" data-etiqueta="Contacto">{cifraPulso(d.tasa_contacto, true)}<p>{d.contestadas} de {d.utiles} útiles{d.utiles < d.minimo_llamadas_utiles ? ` · muestra insuficiente (mín. ${d.minimo_llamadas_utiles})` : ''}</p></td>
            <td role="cell" data-etiqueta="Cortes">{cortesDelDia(d)}</td>
          </tr>)}</tbody>
        </table></div>
        <p className="mt-3">Hora de Lima. El hueco requiere dos llamadas dentro de la jornada: 09–18 h; sábado 09–13 h. Los silencios de apertura y cierre se muestran aparte; el día en curso llega hasta la consulta.</p>
      </details>
    </article>)}
  </section>
}
