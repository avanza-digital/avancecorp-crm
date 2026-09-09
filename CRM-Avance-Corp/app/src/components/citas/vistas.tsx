import { useDatosCitas } from './contexto'
import { CalendarDays, ChevronRight, Clock3, Video, MapPin } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { money, fmtFecha, iniciales } from '@/lib/format'
import { ESTADOS, ordenar, type EstadoCita } from './modelo'
import type { CitaConLead as CitaEjemplo } from './datos'
import { siguientePaso, contextoCita } from './presentacion'

const COLORES: Record<EstadoCita, string> = {
  vencida: 'var(--destructive-text)', programada: 'var(--accent-press)', realizada: 'var(--primary)',
  no_show: 'var(--warning-text)', reprogramada: 'var(--accent-press)', cancelada: 'var(--muted-foreground-strong)', sistema: 'var(--muted-foreground-strong)',
}

export function Estado({ cita }: { cita: CitaEjemplo }) {
  return <Badge color={COLORES[cita.estado]} dot className="whitespace-normal leading-4">{ESTADOS[cita.estado].label}</Badge>
}

function Responsable({ cita }: { cita: CitaEjemplo }) {
  const { nombreAnalista } = useDatosCitas()
  return <div className="flex items-center gap-2"><span aria-hidden className="grid size-8 shrink-0 place-items-center rounded-full bg-secondary text-xs font-semibold text-primary">{iniciales(nombreAnalista(cita.analista))}</span><div><p className="font-medium">{nombreAnalista(cita.analista)}</p><p className="mt-1 text-xs text-muted-foreground-strong">{cita.supervisor}</p></div></div>
}

interface PropsCitas { citas: CitaEjemplo[]; onDetalle: (cita: CitaEjemplo) => void }

export function Bandeja({ citas, onDetalle }: PropsCitas) {
  const { modoDemo } = useDatosCitas()
  return <>
    <div className="hidden overflow-x-auto lg:block">
      <table className="citas-tabla w-full min-w-[840px] text-sm">
        <caption className="sr-only">{modoDemo ? 'Citas de ejemplo' : 'Citas'} que coinciden con tus filtros. Fechas y horas de Lima.</caption>
        <thead className="border-y border-border bg-muted/40 text-xs"><tr><th scope="col">Prospecto / origen</th><th scope="col">Fecha prevista</th><th scope="col">Analista / supervisor</th><th scope="col">Estado</th><th scope="col">Siguiente paso</th></tr></thead>
        <tbody>{citas.map(cita => <tr key={cita.id}>
          <td><Button variant="link" className="h-auto justify-start whitespace-normal p-0 text-left" onClick={() => onDetalle(cita)}>{cita.nombre}</Button><p className="mt-1.5 text-xs text-muted-foreground-strong">{cita.id} · {cita.origen}</p></td>
          <td><p className="font-medium">{fmtFecha(cita.fecha)}</p><p className="mt-1 text-xs text-muted-foreground-strong">{cita.hora} · {cita.modalidad}</p></td>
          <td><Responsable cita={cita} /></td>
          <td><Estado cita={cita} /><p className="mt-1.5 max-w-52 text-xs text-muted-foreground-strong">{contextoCita(cita)}</p></td>
          <td><div className="flex items-center justify-between gap-3"><div><p className="font-medium">{siguientePaso(cita)}</p><p className="mt-1 text-xs text-muted-foreground-strong">{money(cita.monto, cita.moneda)} estimados</p></div><Button variant="ghost" size="icon" aria-label={`Ver detalle de ${cita.nombre}`} onClick={() => onDetalle(cita)}><ChevronRight aria-hidden /></Button></div></td>
        </tr>)}</tbody>
      </table>
    </div>
    <ul className="divide-y divide-border lg:hidden" aria-label="Lista de citas">{citas.map(cita => <li key={cita.id} className="space-y-3 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2"><Button variant="link" className="h-auto p-0 text-left" onClick={() => onDetalle(cita)}>{cita.nombre}</Button><Estado cita={cita} /></div>
      <p className="text-xs text-muted-foreground-strong">{fmtFecha(cita.fecha)} · {cita.hora} · {cita.modalidad}</p>
      <Responsable cita={cita} />
      <div className="flex items-center justify-between gap-2 border-t border-border pt-3"><div><p className="text-sm font-semibold">{siguientePaso(cita)}</p><p className="mt-1 text-xs text-muted-foreground-strong">{money(cita.monto, cita.moneda)} · {cita.origen}</p></div><Button variant="outline" size="sm" aria-label={`Ver detalle de ${cita.nombre}`} onClick={() => onDetalle(cita)}>Detalle <ChevronRight aria-hidden /></Button></div>
    </li>)}</ul>
  </>
}

export function Agenda({ citas, onDetalle }: PropsCitas) {
  const { nombreAnalista } = useDatosCitas()
  const dias = new Map<string, CitaEjemplo[]>()
  for (const cita of ordenar(citas, 'fecha')) {
    const filas = dias.get(cita.fecha) ?? []
    filas.push(cita)
    dias.set(cita.fecha, filas)
  }
  return <div className="space-y-6 p-4 sm:p-5">{[...dias].map(([fecha, filas]) => <section key={fecha} aria-label={`Citas del ${fmtFecha(fecha)}`}>
    <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold"><CalendarDays aria-hidden className="size-4 text-accent" />{fmtFecha(fecha)}<span className="font-normal text-muted-foreground-strong">{filas.length} {filas.length === 1 ? 'cita' : 'citas'}</span></h3>
    <ul className="divide-y divide-border rounded-xl border border-border">{filas.map(cita => <li key={cita.id} className="grid gap-3 p-4 sm:grid-cols-[105px_minmax(0,1fr)_auto] sm:items-center">
      <div className="flex items-center gap-2 text-sm font-semibold"><Clock3 aria-hidden className="size-4 text-muted-foreground" />{cita.hora}</div>
      <div><Button variant="link" className="h-auto p-0" onClick={() => onDetalle(cita)}>{cita.nombre}</Button><p className="mt-1 text-sm text-muted-foreground-strong">{nombreAnalista(cita.analista)}</p><p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground-strong">{cita.modalidad === 'Virtual' ? <Video aria-hidden className="size-3.5" /> : <MapPin aria-hidden className="size-3.5" />}{cita.modalidad} · {cita.origen}</p></div>
      <div className="flex items-center justify-between gap-3 sm:flex-col sm:items-end"><Estado cita={cita} /><Button variant="ghost" size="sm" aria-label={`Ver detalle de ${cita.nombre}`} onClick={() => onDetalle(cita)}>Ver cita <ChevronRight aria-hidden /></Button></div>
    </li>)}</ul>
  </section>)}</div>
}
