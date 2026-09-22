import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { tituloCorte, horaCorte } from '@/lib/gestion-diaria-avisos'
import { Button } from '@/components/ui/button'
import { AccionesCorte } from './acciones-corte'
import { AlertasDelDia } from './alertas-del-dia'

export function AvisosEquipo() {
  const contexto = useGestionDiariaAvisos()
  if (!contexto) return null
  if (contexto.error) return <section role="alert" className="rounded-xl border border-border p-5 text-base">
    <p>No pudimos confirmar los avisos de cortes. Esto no significa que no haya pendientes.</p>
    <Button variant="outline" className="mt-3 min-h-11 text-base" onClick={contexto.recargar}>Actualizar avisos</Button>
  </section>
  if (contexto.cargando) return <p role="status">Consultando los avisos del equipo…</p>
  const datos = contexto.datos
  if (!datos) return null
  return <><section aria-label="Cortes de llamadas del equipo" className="space-y-4 text-base">
    <h3 className="text-xl font-semibold text-primary">Cortes de llamadas</h3>
    {contexto.errorPresentacion != null && <div role="status" className="space-y-3 rounded-xl border border-border p-4">
      <p>No se pudo abrir el aviso emergente. Puedes atender los pendientes desde esta lista.</p>
      <Button variant="outline" className="min-h-11 text-base" onClick={contexto.recargar}>Actualizar avisos</Button>
    </div>}
    {datos.estado_cortes === 'desactivados' ? <p>Los cortes están desactivados para esta jornada.</p>
      : datos.estado_cortes === 'no_laborable' ? <p>Hoy no es jornada de cortes.</p>
        : <>
          {!datos.avisos_habilitados && <p role="status">Gerencia ha pausado los avisos. Los resultados y pendientes siguen visibles.</p>}
          {datos.alertas.length === 0 ? <p>No hay cortes con pendientes al momento de la consulta. Los cortes futuros todavía no se evalúan.</p>
            : datos.alertas.map((aviso) => <article key={aviso.id} className="space-y-4 rounded-xl border border-border bg-card p-5">
              <h4 className="font-semibold">{tituloCorte(aviso)} · {horaCorte(aviso.corte_en)} Lima</h4>
              <ul className="space-y-3">{aviso.miembros.map((m) => <li key={m.analista_id} className="flex flex-wrap items-center justify-between gap-3">
                <p><strong>{m.nombre}</strong>: {m.llamadas} llamadas al corte · mínimo {m.objetivo}
                  {m.llamadas_recuperacion !== null ? ` · ${m.llamadas_recuperacion} llamadas en la ventana de recuperación` : ''}</p>
                <Button variant="outline" className="h-auto min-h-11 max-w-full whitespace-normal text-base" onClick={() => contexto.abrirRegistro(aviso, m.analista_id)}>Ver registro de {m.nombre}</Button>
              </li>)}</ul>
              <AccionesCorte aviso={aviso} />
            </article>)}
        </>}
    <p className="text-[var(--muted-foreground-strong)]">Se revisa cada minuto mientras el CRM está abierto. Reconocer o posponer no borra el resultado del corte.</p>
  </section><AlertasDelDia /></>
}
