import { useState } from 'react'
import { ArrowRight, CalendarClock, ChevronRight, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Sheet, SheetHeader, SheetTitle, SheetBody } from '@/components/ui/sheet'
import { numero, fmtFecha } from '@/lib/format'
import { citasPorLead, resumenLeads, resultadosConLeads, seguimientoInasistencias, type CitaConLead, type EstadoRecuperacion } from './datos'
import { nombreAnalista } from './presentacion'

const RECUPERACION: Record<EstadoRecuperacion, string> = {
  sin_reprogramar: 'Sin nueva cita', pendiente: 'Nueva cita pendiente', recuperada: 'Asistió a la nueva cita',
  otra_inasistencia: 'No asistió de nuevo', cancelada: 'Nueva cita cancelada', sin_resultado: 'Nueva cita sin resultado',
}

function Inasistencias({ citas, onDetalle }: { citas: CitaConLead[]; onDetalle: (cita: CitaConLead) => void }) {
  const [grupo, setGrupo] = useState<'todas' | 'reprogramadas' | 'recuperada' | 'sin_reprogramar'>('todas')
  const seguimiento = seguimientoInasistencias(citas)
  const reprogramadas = seguimiento.filter(fila => fila.nueva)
  const recuperadas = seguimiento.filter(fila => fila.estado === 'recuperada')
  const sinNueva = seguimiento.filter(fila => fila.estado === 'sin_reprogramar')
  const visibles = seguimiento.filter(fila => grupo === 'todas' || (grupo === 'reprogramadas' ? Boolean(fila.nueva) : fila.estado === grupo))
  const etapas = [
    { id: 'todas', titulo: 'No asistieron', cantidad: seguimiento.length },
    { id: 'reprogramadas', titulo: 'Se reprogramaron', cantidad: reprogramadas.length },
    { id: 'recuperada', titulo: 'Asistieron después', cantidad: recuperadas.length },
    { id: 'sin_reprogramar', titulo: 'Sin nueva cita', cantidad: sinNueva.length },
  ] as const
  return <section className="mt-6 border-t border-border pt-5" aria-label="Seguimiento de inasistencias">
    <h3 className="flex items-center gap-2 text-base font-semibold"><CalendarClock aria-hidden className="size-4 text-accent" />¿Qué pasó con quienes no asistieron?</h3>
    <p className="mt-1 text-xs leading-relaxed text-muted-foreground-strong">Parte de las inasistencias de tu consulta y sigue sus citas vinculadas hasta el 7 sep. 2026, 13:00 Lima. La nueva fecha puede estar fuera del mes o semana seleccionados.</p>
    {seguimiento.length === 0 ? <p className="mt-4 rounded-lg bg-muted/50 p-4 text-sm text-muted-foreground-strong">No hay inasistencias con estos filtros. Elige «Todas» o «No asistieron» para revisarlas.</p> : <>
      <div className="my-4 grid grid-cols-2 gap-2 sm:grid-cols-4" role="group" aria-label="Etapas de recuperación">{etapas.map((etapa, indice) => <Button key={etapa.id} variant={grupo === etapa.id ? 'secondary' : 'outline'} className="h-auto justify-start whitespace-normal px-3 py-3 text-left" aria-pressed={grupo === etapa.id} onClick={() => setGrupo(etapa.id)}><span className="text-2xl font-semibold tabular-nums">{etapa.cantidad}</span><span className="text-xs leading-4">{etapa.titulo}</span>{indice < 2 && <ArrowRight aria-hidden className="ml-auto hidden sm:block" />}</Button>)}</div>
      <p className="mb-3 text-sm"><strong>{reprogramadas.length} de {seguimiento.length}</strong> inasistencias tienen una reprogramación vinculada. <strong>{recuperadas.length} de {reprogramadas.length}</strong> terminaron en asistencia.</p>
      <ul className="divide-y divide-border rounded-lg border border-border" aria-label="Detalle de inasistencias">{visibles.map(fila => <li key={fila.original.id} className="grid gap-3 p-3 sm:grid-cols-[minmax(140px,1fr)_1fr_1.2fr] sm:items-center">
        <div><Button variant="link" className="h-auto p-0 text-left" onClick={() => onDetalle(fila.original)}>{fila.original.nombre}</Button><p className="mt-1 text-xs text-muted-foreground-strong">{nombreAnalista(fila.original.analista)}</p></div>
        <div className="text-xs text-muted-foreground-strong"><p>No asistió: {fmtFecha(fila.original.fecha)}</p><p className="mt-1">{fila.nueva ? `Nueva cita: ${fmtFecha(fila.nueva.fecha)} · ${fila.nueva.hora}` : 'Sin reprogramación vinculada'}</p></div>
        <div className="flex items-center justify-between gap-2"><Badge color={fila.estado === 'sin_reprogramar' ? 'var(--warning-text)' : 'var(--primary)'} className="leading-4">{RECUPERACION[fila.estado]}</Badge>{fila.nueva && <Button variant="ghost" size="icon" aria-label={`Ver nueva cita de ${fila.original.nombre}`} onClick={() => onDetalle(fila.nueva!)}><ChevronRight aria-hidden /></Button>}</div>
      </li>)}</ul>
      {visibles.length === 0 && <p className="py-4 text-sm text-muted-foreground-strong">No hay citas en esta etapa.</p>}
      <p className="mt-3 text-xs text-muted-foreground-strong">Cada inasistencia se cuenta una vez. Tener otra cita con el mismo lead no demuestra que se haya reprogramado.</p>
    </>}
  </section>
}

export function Resultados({ citas, onAnalista, onDesglose, onDetalle }: {
  citas: CitaConLead[]; onAnalista: (id: string) => void; onDesglose: (id: string) => void; onDetalle: (cita: CitaConLead) => void
}) {
  const filas = resultadosConLeads(citas)
  const total = resumenLeads(citas)
  return <div className="p-4 sm:p-5">
    <p className="mb-4 text-sm text-muted-foreground-strong"><strong>Promedio = citas ÷ leads distintos con cita.</strong> Usa los filtros activos y la fecha prevista; no incluye leads sin cita ni mide asistencia.</p>
    <div className="hidden overflow-x-auto lg:block"><table className="citas-tabla w-full text-sm"><caption className="sr-only">Resultados por analista de las citas filtradas</caption><thead className="border-y border-border bg-muted/40 text-xs"><tr><th scope="col">Analista</th><th scope="col">Citas</th><th scope="col">Leads con cita</th><th scope="col">Citas por lead</th><th scope="col">Leads con 2+ citas</th><th scope="col">Realizadas</th><th scope="col">Detalle</th></tr></thead><tbody>{filas.map(fila => <tr key={fila.id}><th scope="row"><Button variant="link" className="h-auto p-0" onClick={() => onAnalista(fila.id)}>{fila.nombre}</Button><p className="mt-1 text-xs font-normal">{fila.supervisor}</p></th><td>{fila.total}</td><td>{fila.leads}</td><td className="font-semibold text-accent">{numero(fila.promedio, 2)}</td><td>{fila.repetidos}</td><td>{fila.realizadas}</td><td><Button variant="outline" size="sm" aria-label={`Ver detalle por lead de ${fila.nombre}`} onClick={() => onDesglose(fila.id)}>Por lead <ChevronRight aria-hidden /></Button></td></tr>)}</tbody><tfoot className="border-t border-border font-semibold"><tr><th scope="row">Total de la consulta</th><td>{citas.length}</td><td>{total.leads}</td><td>{numero(total.promedio, 2)}</td><td>{total.repetidos}</td><td>{citas.filter(c => c.estado === 'realizada').length}</td><td>—</td></tr></tfoot></table></div>
    <ul className="grid gap-3 lg:hidden" aria-label="Resultados por analista">{filas.map(fila => <li key={fila.id}><Card className="p-3"><div className="flex items-center justify-between gap-2"><div><Button variant="link" className="h-auto p-0" onClick={() => onAnalista(fila.id)}>{fila.nombre}</Button><p className="mt-1 text-xs text-muted-foreground-strong">{fila.supervisor}</p></div><Button variant="outline" size="sm" aria-label={`Ver detalle por lead de ${fila.nombre}`} onClick={() => onDesglose(fila.id)}>Por lead</Button></div><dl className="mt-3 grid grid-cols-3 gap-3">{[['Citas', fila.total], ['Leads con cita', fila.leads], ['Citas por lead', numero(fila.promedio, 2)]].map(([etiqueta, valor]) => <div key={etiqueta}><dt className="text-xs text-muted-foreground-strong">{etiqueta}</dt><dd className="mt-1 text-lg font-semibold tabular-nums">{valor}</dd></div>)}</dl><p className="mt-3 text-xs text-muted-foreground-strong">{fila.repetidos} leads con 2 o más citas · {fila.realizadas} citas realizadas</p></Card></li>)}</ul>
    <p className="mt-3 text-xs text-muted-foreground-strong">Un lead se identifica por su código. Si tiene citas con varios asesores, cuenta en cada asesor y una sola vez en el total. Las columnas de leads se calculan de nuevo sobre el conjunto; no se suman. El promedio total tampoco es un promedio de los promedios de cada asesor.</p>
    <Inasistencias citas={citas} onDetalle={onDetalle} />
  </div>
}

export function DetalleLeads({ analista, citas, onCerrar, onLead }: { analista: string | null; citas: CitaConLead[]; onCerrar: () => void; onLead: (leadId: string, analista: string) => void }) {
  const delAnalista = citas.filter(cita => cita.analista === analista)
  const leads = citasPorLead(delAnalista)
  const resumen = resumenLeads(delAnalista)
  return <Sheet open={Boolean(analista)} onClose={onCerrar} className="citas-crm-dialogo w-[540px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div><p className="mb-1 text-xs text-muted-foreground-strong">Citas por lead · filtros actuales</p><SheetTitle>{analista ? nombreAnalista(analista) : 'Detalle por lead'}</SheetTitle></div><Button variant="ghost" size="icon" aria-label="Cerrar detalle por lead" onClick={onCerrar}><X aria-hidden /></Button></div></SheetHeader>
    <SheetBody><p className="mb-4 text-sm"><strong>{delAnalista.length} citas</strong> en <strong>{resumen.leads} leads</strong>: promedio <strong>{numero(resumen.promedio, 2)}</strong> citas por lead.</p><ul className="divide-y divide-border">{leads.map(lead => <li key={lead.id} className="flex items-center justify-between gap-3 py-4"><div><h3 className="text-sm font-semibold">{lead.nombre}</h3><p className="mt-1 text-xs text-muted-foreground-strong">{lead.id} · {lead.citas.length} {lead.citas.length === 1 ? 'cita' : 'citas'}</p></div><Button variant="outline" size="sm" aria-label={`Ver citas de ${lead.nombre}`} onClick={() => onLead(lead.id, analista!)}>Ver citas <ChevronRight aria-hidden /></Button></li>)}</ul><p className="mt-4 text-xs text-muted-foreground-strong">Se cuentan citas, aunque estén canceladas o reprogramadas, si esos estados forman parte de tus filtros. Para medir solo las realizadas, selecciona ese estado.</p></SheetBody>
  </Sheet>
}
