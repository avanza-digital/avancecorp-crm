import { useAlertasCRM } from '@/lib/alertas-context'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { hashDe } from '@/lib/router'
import { Button } from '@/components/ui/button'
import { AccionesReconocerAlerta } from './acciones-reconocer-alerta'

/** Lista y campana comparten el mismo libro: ninguna recalcula los pendientes. */
export function AlertasDelDia() {
  const cortes = useGestionDiariaAvisos()
  const estado = useAlertasCRM()
  if (!cortes?.datos?.diarias) return null
  const alertas = estado.alertas.filter((a) => a.diaria)
  const contexto = cortes.datos.contexto!
  return <section aria-labelledby="diarias-encabezado" className="space-y-4 text-base">
    <h3 id="diarias-encabezado" tabIndex={-1} className="text-xl font-semibold text-primary">Otros pendientes del equipo</h3>
    <p>Han registrado llamadas {contexto.con_llamadas} de {contexto.analistas} analistas hoy.
      {' '}Este dato aporta contexto; no confirma asistencia ni feriados.</p>
    {cortes.datos.diarias.modo_sla !== 'activo' && <p role="status">Los pendientes de seguimiento necesitan el modo SLA activo.</p>}
    {estado.errores.length > 0 && <p role="alert">{estado.errores.join(' ')}</p>}
    {estado.pospuestas > 0 && <p>{estado.pospuestas} avisos pospuestos. Volverán al vencer el plazo o si empeoran.</p>}
    {alertas.length === 0 ? <p>No hay otros avisos visibles con los datos confirmados.</p> : <ul className="space-y-3">
      {alertas.map((a) => <li key={a.id} className="space-y-3 rounded-xl border border-border p-5">
        <h4 className="font-semibold">{a.titulo} · {a.valor}</h4>
        <p>{a.detalle}</p>
        {a.reconocimiento && <p>Reconocido: lo estás atendiendo. Reaparecerá si empeora.</p>}
        <div className="flex flex-wrap items-center gap-3">
          <Button variant="outline" className="min-h-11 text-base" onClick={() => { window.location.hash = hashDe(a.destino.vista) }}>{a.destino.etiqueta}</Button>
          {a.miembros && !a.reconocimiento && <AccionesReconocerAlerta alerta={a} destinoFoco="diarias-encabezado" />}
        </div>
      </li>)}
    </ul>}
  </section>
}
