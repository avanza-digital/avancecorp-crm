import { useDatosCitas, horaLima } from './contexto'
import { useState } from 'react'
import { ArrowRight, ChevronRight, TriangleAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { fmtFecha, money, numero } from '@/lib/format'
import { cn } from '@/lib/utils'
import type { CitaConLead, Recuperacion } from './datos'
import { depositosDeInasistencias, montosDepositados } from './depositos'
import { FichaRecorrido } from './ficha-recorrido'

type Grupo = 'todas' | 'reprogramadas' | 'recuperada' | 'sin_reprogramar' | 'depositaron'
const textoMontos = (montos: ReturnType<typeof montosDepositados>) =>
  (['PEN', 'USD'] as const).filter(moneda => montos[moneda] > 0).map(moneda => money(montos[moneda], moneda)).join(' · ')

export function Inasistencias({ citas, onDetalle, leadAbierto, onLead }: {
  citas: CitaConLead[]
  onDetalle: (cita: CitaConLead) => void
  leadAbierto: string | null
  onLead: (id: string | null) => void
}) {
  const { citas: todas, corte, depositos, depositosDisponibles, depositoPorConversion, nombreAnalista, gestion } = useDatosCitas()
  const compacta = Boolean(gestion?.avance)
  const [grupo, setGrupo] = useState<Grupo | null>(() => compacta ? null : 'todas')
  const [pagina, setPagina] = useState(0)
  const flujo = depositosDeInasistencias(citas, depositos, corte, todas)
  const { inasistencias: seguimiento, reprogramadas, recuperadas, sinNueva } = flujo
  // Una misma persona puede tener varios episodios. La ficha debe mostrar el
  // episodio que realmente alcanzó la etapa, igual que el cálculo del flujo.
  const contexto = (fila: Recuperacion) => recuperadas.find(item => item.original.leadId === fila.original.leadId)
    ?? reprogramadas.find(item => item.original.leadId === fila.original.leadId) ?? fila
  const seleccionadas = grupo === 'reprogramadas' ? reprogramadas : grupo === 'recuperada' ? recuperadas
    : grupo === 'sin_reprogramar' ? sinNueva : grupo === 'depositaron'
      ? recuperadas.filter(fila => flujo.leads.some(lead => lead.original.leadId === fila.original.leadId)) : seguimiento
  const visibles = seleccionadas.map(contexto)
  const abierta = seguimiento.find(fila => fila.original.leadId === leadAbierto)
  const depositosAbiertos = flujo.leads.find(lead => lead.original.leadId === leadAbierto)?.depositos ?? []
  const etapas = [
    { id: 'todas', titulo: 'No asistieron', cantidad: seguimiento.length },
    { id: 'reprogramadas', titulo: 'Reprogramaron', cantidad: reprogramadas.length },
    { id: 'recuperada', titulo: compacta ? 'Asistieron después' : 'Asistió', cantidad: recuperadas.length },
    { id: 'depositaron', titulo: compacta ? 'Se hicieron clientes' : 'Depositó', cantidad: depositosDisponibles ? flujo.convertidos : '—' },
  ] as const
  function cambiarGrupo(nuevo: Grupo) { setGrupo(compacta && grupo === nuevo ? null : nuevo); setPagina(0); onLead(null) }
  const actual = Math.min(pagina, Math.max(0, Math.ceil(visibles.length / 8) - 1))
  const filas = compacta ? visibles.slice(actual * 8, actual * 8 + 8) : visibles

  return <section className={cn('gi-card citas-recuperacion', compacta && 'cm-recuperacion')} aria-label="Seguimiento de inasistencias">
    <div className="citas-cabecera-seccion citas-cabecera-recuperacion"><h2 className="citas-titulo-seccion">¿Qué pasó con quienes no asistieron?</h2>
      {flujo.base > 0 && <div className="flex items-center gap-2">
        {!compacta && grupo !== 'todas' && <Button variant="ghost" size="sm" onClick={() => cambiarGrupo('todas')}>Ver las {flujo.base} personas</Button>}
        <Button variant="ghost" size="sm" className={compacta && sinNueva.length ? 'cm-pendientes' : undefined} aria-pressed={grupo === 'sin_reprogramar'} onClick={() => cambiarGrupo(grupo === 'sin_reprogramar' && !compacta ? 'todas' : 'sin_reprogramar')}>{compacta && sinNueva.length > 0 && <TriangleAlert aria-hidden />}{compacta ? `${sinNueva.length} sin nueva cita` : 'Sin nueva cita'}</Button>
      </div>}
    </div>
    <div className="citas-flujo-resumen">
      <div className="citas-flujo" role="group" aria-label="Etapas de recuperación">
        {etapas.map((etapa, indice) => <div className="citas-flujo-etapa" key={etapa.id} data-etapa={indice} data-con-datos={typeof etapa.cantidad === 'number' && etapa.cantidad > 0}>
          <Button variant="ghost" className="citas-paso" aria-label={etapa.titulo + ' ' + etapa.cantidad}
            aria-pressed={grupo === etapa.id} disabled={!flujo.base || (etapa.id === 'depositaron' && !depositosDisponibles)} onClick={() => cambiarGrupo(etapa.id)}>
            <span className="citas-paso-numero">{etapa.cantidad}</span><span>{etapa.titulo}</span>
          </Button>
          {indice < etapas.length - 1 && <ArrowRight aria-hidden className="citas-flecha" />}
        </div>)}
      </div>
      <div className="citas-conversion" aria-label="Conversión de inasistencias a depósito" role="region">
        <p><strong>{!depositosDisponibles || flujo.porcentaje === null ? '—' : numero(flujo.porcentaje, 1) + '%'}</strong> a depósito</p>
        <p className="citas-conversion-base">{!depositosDisponibles ? 'Sin verificar' : flujo.base ? flujo.convertidos + ' de ' + flujo.base + ' leads' : 'Sin base de inasistencias'}
          {textoMontos(flujo.montos) && <span> · {textoMontos(flujo.montos)}</span>}</p>
      </div>
    </div>
    <h3 className="sr-only">Personas del flujo</h3>
    {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El contenedor con desplazamiento horizontal necesita foco para usar las flechas del teclado. */}
    {grupo !== null && (visibles.length ? <div className="citas-tabla-scroll" role="region" tabIndex={0} aria-label="Tabla de personas del flujo">
      <table className="citas-tabla citas-tabla-compacta citas-tabla-flujo w-full text-sm">
        <caption className="sr-only">Personas del flujo de recuperación</caption>
        <thead><tr><th scope="col">Persona</th><th scope="col">Analista</th><th scope="col">Nueva cita</th><th scope="col">Entrevista</th><th scope="col">Depósito del flujo</th><th scope="col"><span className="sr-only">Recorrido</span></th></tr></thead>
        <tbody>{filas.map(fila => {
          const movimientos = flujo.leads.find(lead => lead.original.leadId === fila.original.leadId)?.depositos ?? []
          const asistencia = recuperadas.find(item => item.original.leadId === fila.original.leadId)?.nueva
          return <tr key={fila.original.leadId} className={cn(leadAbierto === fila.original.leadId && 'citas-fila-seleccionada')}>
            <th scope="row"><Button variant="link" className="citas-enlace-persona" aria-haspopup="dialog" onClick={() => onLead(fila.original.leadId)}>{fila.original.nombre}</Button></th>
            <td>{nombreAnalista(fila.original.analista)}</td>
            <td>{fila.nueva ? <span className="whitespace-nowrap">{fmtFecha(fila.nueva.fecha)} · {fila.nueva.hora}</span> : <span className="citas-excepcion">Sin nueva cita</span>}</td>
            <td>{asistencia ? <span className="whitespace-nowrap">{fmtFecha(asistencia.asistioEn!)} · {horaLima(asistencia.asistioEn!)}</span>
              : fila.estado === 'pendiente' ? 'Pendiente' : fila.estado === 'otra_inasistencia' ? 'Volvió a faltar'
                : fila.estado === 'cancelada' ? 'Cita cancelada' : fila.estado === 'sin_resultado' ? 'Sin resultado' : '—'}</td>
            <td>{movimientos.length ? <><span className="whitespace-nowrap">{depositoPorConversion ? 'Convertido a cliente' : textoMontos(montosDepositados(movimientos))}</span><span className="citas-fecha-secundaria">{movimientos.length > 1 ? movimientos.length + ' depósitos · desde ' : ''}{fmtFecha(movimientos[0]!.depositadoEn)}</span></> : '—'}</td>
            <td><Button variant="ghost" size="icon" aria-label={'Ver recorrido de ' + fila.original.nombre} aria-haspopup="dialog" onClick={() => onLead(fila.original.leadId)}><ChevronRight aria-hidden /></Button></td>
          </tr>
        })}</tbody>
      </table>
    </div> : <p className="citas-vacio-flujo">{!flujo.base ? 'No hay inasistencias con estos filtros.' : grupo === 'depositaron' ? 'Ningún lead completó el flujo hasta un depósito confirmado después de asistir.' : grupo === 'sin_reprogramar' ? 'Todas las personas reprogramaron.' : 'No hay personas en esta etapa.'}</p>)}
    {compacta && grupo !== null && <div className="cm-paginacion cm-paginacion-flujo"><span>{visibles.length ? actual * 8 + 1 : 0}–{Math.min(visibles.length, actual * 8 + 8)} de {visibles.length} personas</span><Button size="sm" variant="outline" disabled={!actual} onClick={() => setPagina(actual - 1)}>Anterior</Button><Button size="sm" variant="outline" disabled={(actual + 1) * 8 >= visibles.length} onClick={() => setPagina(actual + 1)}>Siguiente</Button><Button variant="ghost" size="sm" onClick={() => { setGrupo(null); onLead(null) }}>Ocultar personas</Button></div>}
    <p className="citas-nota">{depositoPorConversion ? 'Depositó: conversión a cliente después de asistir. Se muestra la fecha de conversión; se excluyen anulaciones.' : depositosDisponibles ? '—: etapa aún no completada.' : 'La fuente de depósitos aún no está habilitada para esta consulta.'} Fechas e historial al abrir una persona.</p>
    <FichaRecorrido fila={abierta ? contexto(abierta) : null} depositos={depositosAbiertos} citas={citas} onCerrar={() => onLead(null)} onCita={onDetalle} />
  </section>
}
