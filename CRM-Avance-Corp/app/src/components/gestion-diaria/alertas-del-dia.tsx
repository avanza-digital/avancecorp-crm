import { useAlertasCRM } from '@/lib/alertas-context'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { hashDe } from '@/lib/router'
import { Button } from '@/components/ui/button'
import { AccionesReconocerAlerta } from './acciones-reconocer-alerta'

/** Lista y campana comparten el mismo libro: ninguna recalcula los pendientes. */
export function AlertasDelDia({ alNavegar }: { alNavegar?: (() => void) | undefined } = {}) {
  const cortes = useGestionDiariaAvisos()
  const estado = useAlertasCRM()
  if (cortes?.error || !cortes?.datos) return <section aria-label="Otros pendientes del equipo" className="space-y-3 text-base">
    <p>{cortes?.error ? 'No pudimos confirmar los otros pendientes del equipo. Esto no significa que no haya avisos.'
      : cortes?.cargando ? 'Consultando otros pendientes del equipo…' : 'Los otros pendientes no están disponibles en esta sesión.'}</p>
    {!!cortes?.error && <Button variant="outline" className="min-h-11 text-base" onClick={estado.reintentar}>Actualizar otros pendientes</Button>}
  </section>
  const alertas = estado.alertas.filter((a) => !a.corte)
  const contexto = cortes.datos.contexto
  return <section aria-labelledby="diarias-encabezado" className="space-y-4 text-base">
    <h3 id="diarias-encabezado" tabIndex={-1} className="text-xl font-semibold text-primary">Otros pendientes del equipo</h3>
    {contexto && <p>Han registrado llamadas {contexto.con_llamadas} de {contexto.analistas} analistas hoy.
      {' '}Este dato aporta contexto; no confirma asistencia ni feriados.</p>}
    {cortes.datos.diarias && cortes.datos.diarias.modo_sla !== 'activo' && <p role="status">Los pendientes de seguimiento necesitan el modo SLA activo.</p>}
    {estado.errores.length > 0 && <div role="alert" className="space-y-2"><p>{estado.errores.join(' ')}</p>
      <Button variant="outline" className="min-h-11 text-base" onClick={estado.reintentar}>Actualizar otros pendientes</Button></div>}
    {estado.cargando && <p role="status">Actualizando otros pendientes…</p>}
    {estado.pospuestas > 0 && <p>{estado.pospuestas} avisos pospuestos. Volverán al vencer el plazo o si empeoran.</p>}
    {alertas.length === 0 ? estado.errores.length === 0 && !estado.cargando && <p>No hay otros avisos visibles con los datos confirmados.</p> : <ul className="divide-y divide-border">
      {alertas.map((a) => <li key={a.id} className="space-y-3 py-3">
        <h4 className="font-semibold">{a.titulo} · {a.valor}</h4>
        <p>{a.detalle}</p>
        {a.reconocimiento && <p>Reconocido: lo estás atendiendo. Reaparecerá si empeora.</p>}
        <div className="flex flex-wrap items-center gap-3">
          <Button variant="outline" className="min-h-11 text-base" onClick={() => { alNavegar?.(); window.location.hash = hashDe(a.destino.vista, a.destino.leadId) }}>{a.destino.etiqueta}</Button>
          {a.miembros && !a.reconocimiento && <AccionesReconocerAlerta alerta={a} destinoFoco="diarias-encabezado" />}
        </div>
      </li>)}
    </ul>}
  </section>
}
