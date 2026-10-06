import { ChevronRight, RefreshCw } from 'lucide-react'
import { useAlertasCRM } from '@/lib/alertas-context'
import { alertasActivas, textoActualizacion, VACIO_GERENCIA } from '@/lib/alertas-presentacion'
import { usePeriodoGerencia } from '@/components/gerencia/use-periodo-gerencia'
import { useEstaEnLinea } from '@/lib/conexion'
import { Button } from '@/components/ui/button'
import { hashDe } from '@/lib/router'
import { presentarCitas } from '@/lib/terminologia'

export function PendientesGerenciaMovil() {
  const { alertas, pendientes, pospuestas, cargando, errores, generadoEn, reintentar } = useAlertasCRM()
  const { setPeriodo, setOrigenFiltrado } = usePeriodoGerencia()
  const enLinea = useEstaEnLinea()
  const activas = alertasActivas(alertas)
  const reconocidas = alertas.filter(a => a.reconocimiento != null || a.corte?.estado === 'reconocido').length
  const primeraCarga = cargando && alertas.length === 0
  return <section className="grm-gestion" aria-labelledby="grm-gestion-titulo" aria-busy={cargando}>
    <div className="grm-section-heading">
      <h3 id="grm-gestion-titulo">Pendientes de gestión</h3>
      {!primeraCarga && <a className="grm-ver-todos" href={hashDe('alertas')}>Ver todos <span>({pendientes})</span><ChevronRight size={14} aria-hidden /></a>}
    </div>
    <p className="grm-estado" role="status">{primeraCarga ? 'Cargando pendientes…' : cargando ? 'Actualizando pendientes…' : textoActualizacion(generadoEn)}</p>
    {!enLinea && <p className="grm-error" role="status">Sin conexión. Los avisos pueden estar desactualizados.</p>}
    {errores.length > 0 && <div role="alert" className="grm-error"><strong>Información incompleta</strong><p>{presentarCitas(errores.join(' '))}</p><Button type="button" variant="outline" size="sm" disabled={cargando} onClick={reintentar}><RefreshCw aria-hidden />Reintentar</Button></div>}
    {activas.length > 0 ? <ol className="grm-gestion-lista" aria-label="Pendientes prioritarios">{activas.slice(0, 3).map(a => <li key={a.id}>
      <a className="grm-gestion-aviso" href={hashDe(a.destino.vista, a.destino.leadId)} onClick={() => {
        if (a.destino.periodo) { setPeriodo(a.destino.periodo); setOrigenFiltrado(null) }
      }}>
        <span className={`grm-prioridad grm-prioridad-${a.severidad}`}>{a.severidad === 'critica' ? 'Crítica' : 'Atención'}</span>
        <strong>{presentarCitas(a.titulo)}</strong><p>{presentarCitas(a.detalle)}</p>
        {a.responsable && <small>Responsable: {a.responsable}</small>}
        <span className="grm-abrir-aviso">{a.destino.etiqueta}<ChevronRight size={15} aria-hidden /></span>
      </a>
    </li>)}</ol> : !primeraCarga && errores.length === 0 && <p className="grm-gestion-vacio">{reconocidas + pospuestas > 0 ? 'Sin avisos activos. Los reconocidos o pospuestos no se cuentan como pendientes.' : VACIO_GERENCIA}</p>}
    {(reconocidas > 0 || pospuestas > 0) && <p className="grm-estado">{reconocidas} reconocidas · {pospuestas} pospuestas hasta su fecha</p>}
  </section>
}
