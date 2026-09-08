import { useState } from 'react'
import { ArrowRight, CalendarClock, ChevronRight, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Sheet, SheetHeader, SheetTitle, SheetBody } from '@/components/ui/sheet'
import { numero, fmtFecha, money, type Moneda } from '@/lib/format'
import { type CitaConLead, type EstadoRecuperacion } from './datos'
import { depositosDeInasistencias, montosDepositados, type LeadConDeposito } from './depositos'
import { nombreAnalista } from './presentacion'

const RECUPERACION: Record<EstadoRecuperacion, string> = {
  sin_reprogramar: 'Sin nueva cita', pendiente: 'Nueva cita pendiente', recuperada: 'Asistió a la nueva cita',
  otra_inasistencia: 'No asistió de nuevo', cancelada: 'Nueva cita cancelada', sin_resultado: 'Nueva cita sin resultado',
}

function Montos({ montos }: { montos: Record<Moneda, number> }) {
  return <span className="inline-flex flex-wrap gap-x-3 gap-y-1 font-semibold tabular-nums">
    {(['PEN', 'USD'] as const).filter(moneda => montos[moneda] > 0).map(moneda => <span key={moneda}>{money(montos[moneda], moneda)}</span>)}
  </span>
}

function DetalleDepositos({ lead, onCerrar }: { lead: LeadConDeposito | null; onCerrar: () => void }) {
  return <Sheet open={Boolean(lead)} onClose={onCerrar} className="citas-crm-dialogo w-[520px]">
    <SheetHeader><div className="flex items-start justify-between gap-3">
      <div><p className="mb-1 text-xs text-muted-foreground-strong">Depósitos confirmados · ejemplo</p><SheetTitle>Depósitos de {lead?.original.nombre ?? 'un lead'}</SheetTitle></div>
      <Button variant="ghost" size="icon" aria-label="Cerrar depósitos" onClick={onCerrar}><X aria-hidden /></Button>
    </div></SheetHeader>
    {lead && <SheetBody className="space-y-5">
      <p className="text-sm text-muted-foreground-strong">{lead.original.leadId} · {nombreAnalista(lead.original.analista)}</p>
      <ol className="space-y-2 text-sm" aria-label="Recorrido hasta el depósito">
        <li>No asistió: {fmtFecha(lead.original.fecha)} · {lead.original.hora} Lima</li>
        <li>Reprogramó: {fmtFecha(lead.asistencia.reprogramadaEn!)} · {lead.asistencia.reprogramadaEn!.slice(11, 16)} Lima</li>
        <li>Asistió a la nueva cita: {fmtFecha(lead.asistencia.asistioEn!)} · {lead.asistencia.asistioEn!.slice(11, 16)} Lima</li>
      </ol>
      <div className="rounded-lg border border-border bg-muted/30 p-4"><p className="mb-1 text-xs text-muted-foreground-strong">Monto depositado después de asistir</p><Montos montos={montosDepositados(lead.depositos)} /></div>
      <ul className="divide-y divide-border" aria-label="Depósitos confirmados del lead">{lead.depositos.map(deposito => <li key={deposito.id} className="space-y-2 py-4">
        <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">{deposito.id}</h3><Badge color="var(--success-text)">Confirmado</Badge></div>
        <dl className="grid grid-cols-2 gap-3 text-sm">
          <div><dt className="text-xs text-muted-foreground-strong">Monto</dt><dd className="mt-1 font-semibold">{money(deposito.monto, deposito.moneda)}</dd></div>
          <div><dt className="text-xs text-muted-foreground-strong">Fecha de depósito</dt><dd className="mt-1">{fmtFecha(deposito.depositadoEn)}</dd></div>
          <div className="col-span-2"><dt className="text-xs text-muted-foreground-strong">Confirmación</dt><dd className="mt-1">{fmtFecha(deposito.confirmadoEn!)} · {deposito.confirmadoEn!.slice(11, 16)} Lima</dd></div>
        </dl>
      </li>)}</ul>
      <p className="text-xs text-muted-foreground-strong">Un lead cuenta una sola vez aunque tenga varias citas o depósitos. Los movimientos son ficticios; un cierre o un monto estimado no se cuenta como depósito.</p>
    </SheetBody>}
  </Sheet>
}

export function Inasistencias({ citas, onDetalle }: { citas: CitaConLead[]; onDetalle: (cita: CitaConLead) => void }) {
  const [grupo, setGrupo] = useState<'todas' | 'reprogramadas' | 'recuperada' | 'sin_reprogramar' | 'depositaron'>('todas')
  const [leadAbierto, setLeadAbierto] = useState<string | null>(null)
  const depositos = depositosDeInasistencias(citas)
  const { inasistencias: seguimiento, reprogramadas, recuperadas, sinNueva } = depositos
  const visibles = grupo === 'reprogramadas' ? reprogramadas : grupo === 'recuperada' ? recuperadas : grupo === 'sin_reprogramar' ? sinNueva : seguimiento
  const etapas = [
    { id: 'todas', titulo: 'No asistieron', cantidad: seguimiento.length },
    { id: 'reprogramadas', titulo: 'Se reprogramaron', cantidad: reprogramadas.length },
    { id: 'recuperada', titulo: 'Asistieron después', cantidad: recuperadas.length },
    { id: 'depositaron', titulo: 'Leads que depositaron', cantidad: depositos.convertidos },
  ] as const

  return <section className="mt-6 border-t border-border pt-5" aria-label="Seguimiento de inasistencias">
    <h3 className="flex items-center gap-2 text-base font-semibold"><CalendarClock aria-hidden className="size-4 text-accent" />¿Qué pasó con quienes no asistieron?</h3>
    <p className="mt-1 text-xs leading-relaxed text-muted-foreground-strong">Cada paso parte del anterior: leads que faltaron, reprogramaron, asistieron a la nueva cita y después depositaron. Seguimiento hasta el 7 sep. 2026, 13:00 Lima, aunque la nueva cita o el depósito estén fuera del mes o semana seleccionados.</p>
    {seguimiento.length === 0 ? <p className="mt-4 rounded-lg bg-muted/50 p-4 text-sm text-muted-foreground-strong">No hay inasistencias con estos filtros. Elige «Todas» o «No asistieron» para revisarlas.</p> : <>
      <div className="my-4 grid grid-cols-2 gap-2 sm:grid-cols-4" role="group" aria-label="Etapas de recuperación">{etapas.map((etapa, indice) => <Button key={etapa.id} variant={grupo === etapa.id ? 'secondary' : 'outline'} className="h-auto justify-start whitespace-normal px-3 py-3 text-left" aria-pressed={grupo === etapa.id} onClick={() => setGrupo(etapa.id)}>
        <span className="text-2xl font-semibold tabular-nums">{etapa.cantidad}</span><span className="text-xs leading-4">{etapa.titulo}{etapa.id === 'depositaron' && <span className="mt-1 block font-normal text-muted-foreground-strong">Después de asistir</span>}</span>{indice < 3 && <ArrowRight aria-hidden className="ml-auto hidden sm:block" />}
      </Button>)}</div>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2 text-sm"><p>Reprogramaron: <strong>{reprogramadas.length} de {seguimiento.length}</strong>. Asistieron después: <strong>{recuperadas.length} de {reprogramadas.length}</strong>.</p><Button size="sm" variant={grupo === 'sin_reprogramar' ? 'secondary' : 'outline'} aria-pressed={grupo === 'sin_reprogramar'} onClick={() => setGrupo('sin_reprogramar')}>Sin nueva cita {sinNueva.length}</Button></div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-2 rounded-lg border border-border bg-muted/30 px-3 py-2 text-sm" aria-label="Conversión de inasistencias a depósito" role="region">
        <p>Conversión del flujo: <strong>{depositos.convertidos} de {depositos.base}</strong> leads <strong>({numero(depositos.porcentaje, 1)}%)</strong>.</p>
        {depositos.convertidos > 0 && <p className="flex flex-wrap items-center gap-x-3 gap-y-1"><span className="text-xs text-muted-foreground-strong">Monto depositado</span><Montos montos={depositos.montos} /></p>}
      </div>
      {grupo === 'depositaron' ? <>
        <p className="mb-3 text-xs text-muted-foreground-strong">Solo aparecen quienes asistieron a una cita reprogramada vinculada y luego hicieron un depósito confirmado. Se excluyen pendientes y anulados.</p>
        {depositos.leads.length === 0 ? <p className="py-4 text-sm text-muted-foreground-strong">Ningún lead completó el flujo hasta un depósito confirmado después de asistir.</p> : <ul className="divide-y divide-border rounded-lg border border-border" aria-label="Leads que depositaron">{depositos.leads.map(lead => <li key={lead.original.leadId} className="flex flex-wrap items-center justify-between gap-3 p-3">
          <div><h4 className="text-sm font-semibold">{lead.original.nombre}</h4><p className="mt-1 text-xs text-muted-foreground-strong">{nombreAnalista(lead.original.analista)} · No asistió: {fmtFecha(lead.original.fecha)}</p></div>
          <div className="flex flex-wrap items-center gap-3 text-sm"><Montos montos={montosDepositados(lead.depositos)} /><Button variant="outline" size="sm" aria-label={`Ver depósitos de ${lead.original.nombre}`} onClick={() => setLeadAbierto(lead.original.leadId)}>Ver depósitos <ChevronRight aria-hidden /></Button></div>
        </li>)}</ul>}
      </> : <>
        <ul className="divide-y divide-border rounded-lg border border-border" aria-label="Detalle de inasistencias">{visibles.map(fila => <li key={fila.original.id} className="grid gap-3 p-3 sm:grid-cols-[minmax(140px,1fr)_1fr_1.2fr] sm:items-center">
          <div><Button variant="link" className="h-auto p-0 text-left" onClick={() => onDetalle(fila.original)}>{fila.original.nombre}</Button><p className="mt-1 text-xs text-muted-foreground-strong">{nombreAnalista(fila.original.analista)}</p></div>
          <div className="text-xs text-muted-foreground-strong"><p>No asistió: {fmtFecha(fila.original.fecha)}</p><p className="mt-1">{fila.nueva ? `Nueva cita: ${fmtFecha(fila.nueva.fecha)} · ${fila.nueva.hora}` : 'Sin reprogramación vinculada'}</p></div>
          <div className="flex items-center justify-between gap-2"><Badge color={fila.estado === 'sin_reprogramar' ? 'var(--warning-text)' : 'var(--primary)'} className="leading-4">{RECUPERACION[fila.estado]}</Badge>{fila.nueva && <Button variant="ghost" size="icon" aria-label={`Ver nueva cita de ${fila.original.nombre}`} onClick={() => onDetalle(fila.nueva!)}><ChevronRight aria-hidden /></Button>}</div>
        </li>)}</ul>
        {visibles.length === 0 && <p className="py-4 text-sm text-muted-foreground-strong">No hay citas en esta etapa.</p>}
      </>}
      <p className="mt-3 text-xs text-muted-foreground-strong">Cada lead cuenta una vez por etapa. Solo avanza si cumplió el paso anterior. La conversión usa como base los leads que faltaron al inicio; los montos corresponden a los depósitos posteriores a la asistencia.</p>
    </>}
    <DetalleDepositos lead={depositos.leads.find(lead => lead.original.leadId === leadAbierto) ?? null} onCerrar={() => setLeadAbierto(null)} />
  </section>
}
