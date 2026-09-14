import { useDatosCitas, corteLima } from './contexto'
import { useState } from 'react'
import { ChevronDown, ChevronRight, Columns3, Info, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { Sheet, SheetHeader, SheetTitle, SheetBody } from '@/components/ui/sheet'
import { numero } from '@/lib/format'
import { citasPorLead, type CitaConLead } from './datos'
import { defaults, type FiltrosCitas } from './modelo'
import { metaCitas, baseCitasFiltrada } from './metas'
import { Inasistencias } from './inasistencias'
import { AvanceMensualCitas } from './avance-mensual'

function AyudaMetricas({ abierta, onCerrar }: { abierta: boolean; onCerrar: () => void }) {
  const { corte, depositosDisponibles, depositoPorConversion } = useDatosCitas()
  return <Sheet open={abierta} onClose={onCerrar} className="citas-crm-dialogo">
    <SheetHeader><div className="flex items-start justify-between gap-3"><SheetTitle>Cómo se calculan las métricas</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar ayuda de métricas" onClick={onCerrar}><X aria-hidden /></Button></div></SheetHeader>
    <SheetBody className="space-y-5 text-sm leading-relaxed">
      <section><h3 className="font-semibold">Citas por lead</h3><p>Citas del período ÷ leads distintos asignados en el mes. La base incluye personas que todavía no tienen cita y excluye las registradas manualmente por el propio analista.</p></section>
      <section><h3 className="font-semibold">Cumplimiento</h3><p>Compara la actividad con la meta interna configurada. Llegar al 100% significa alcanzar esa meta; el porcentaje puede superarla. Si falta la base asignada o una regla necesaria, se muestra «—».</p></section>
      <section><h3 className="font-semibold">Filtros y total</h3><p>La semana y los filtros de estado seleccionan las citas; la base asignada y su meta siguen siendo mensuales. Los filtros de persona, origen, moneda y responsable también delimitan la base. Una búsqueda por código de cita puede no identificar un lead de la base: en ese caso no hay porcentaje calculable.</p><p className="mt-2">Un lead asignado a varios analistas cuenta una vez en cada uno y una vez en el total. El total se recalcula; no promedia porcentajes.</p></section>
      <section><h3 className="font-semibold">Recuperación hasta el depósito</h3><p>Cada etapa parte de la anterior: no asistió, reprogramó, asistió a una cita vinculada y luego hizo un depósito confirmado. El porcentaje usa los leads que faltaron al inicio. El seguimiento llega al {corteLima(corte)}, aunque la nueva cita o el depósito queden fuera del período de origen.</p></section>
      {depositoPorConversion && <p>Depositó se acredita al convertir el lead en cliente. Se usa la fecha de conversión del CRM, se cuenta cada lead una vez y se excluyen conversiones anuladas. Esta fecha corresponde al registro comercial; no se atribuye una hora bancaria ni un importe estimado.</p>}
      <p className="text-muted-foreground-strong">{!depositosDisponibles && 'Depósitos: sin verificación disponible. '}La meta de actividad y el resultado comercial son independientes. Haber depositado no exige agendar más citas para completar un contador.</p>
    </SheetBody>
  </Sheet>
}

export function Resultados({ citas, filtros = defaults(), onAnalista, onDesglose, onDetalle, leadAbierto, onLead }: {
  citas: CitaConLead[]
  filtros?: FiltrosCitas
  onAnalista: (id: string) => void
  onDesglose: (id: string) => void
  onDetalle: (cita: CitaConLead) => void
  leadAbierto: string | null
  onLead: (id: string | null) => void
}) {
  const [columnas, setColumnas] = useState({ repetidos: false, realizadas: false, supervisor: false })
  const [ayuda, setAyuda] = useState(false)
  const { gestion, equipo } = useDatosCitas()
  const base = gestion ? baseCitasFiltrada(gestion.asignaciones, filtros) : undefined
  const filas = equipo.filter(p => citas.some(c => c.analista === p.id) || base?.some(l => l.id === p.id)).map(p => {
    const delAnalista = citas.filter(c => c.analista === p.id)
    return { ...p, ...metaCitas(delAnalista, base?.filter(l => l.id === p.id), gestion?.citasPorLead, gestion?.actividadManuales),
      total:delAnalista.length, realizadas:delAnalista.filter(c=>c.estado==='realizada').length,
      repetidos:citasPorLead(delAnalista).filter(l=>l.citas.length>1).length }
  })
  const total = metaCitas(citas, base, gestion?.citasPorLead, gestion?.actividadManuales)
  const manualesSinRegla = gestion && !gestion.actividadManuales && citas.some(c => c.manualPropio)
  return <div className="citas-resultados">
    <Inasistencias citas={citas} onDetalle={onDetalle} leadAbierto={leadAbierto} onLead={onLead} />
    {gestion?.avance ? <AvanceMensualCitas filtros={filtros} onAnalista={onAnalista} /> : <section className="gi-card citas-analistas" aria-label="Citas por lead y analista">
      <div className="citas-cabecera-seccion">
        <div><h2 className="citas-titulo-seccion">Citas por lead y analista</h2>
          <p className="citas-nota">Actividad del período sobre la base asignada del mes</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm" aria-label="Cómo se calculan las métricas" onClick={() => setAyuda(true)}><Info aria-hidden /><span className="hidden 2xl:inline">Cómo se calculan las métricas</span></Button>
          <details className="citas-columnas">
            <summary><Columns3 aria-hidden />Columnas<ChevronDown aria-hidden /></summary>
            <fieldset><legend className="sr-only">Columnas adicionales</legend>
              {([['repetidos', 'Leads con 2+ citas'], ['realizadas', 'Realizadas'], ['supervisor', 'Supervisor']] as const).map(([id, titulo]) =>
                <label key={id}><input type="checkbox" checked={columnas[id]} onChange={evento => setColumnas(actuales => ({ ...actuales, [id]: evento.target.checked }))} />{titulo}</label>)}
            </fieldset>
          </details>
        </div>
      </div>
      {!gestion && <p role="status" className="citas-nota px-4 pb-4">El avance no está disponible: falta la base de leads asignados del mes.</p>}
      {manualesSinRegla && <p role="status" className="citas-nota px-4 pb-4">Falta definir si la actividad de registros manuales aporta al cumplimiento. Las filas afectadas muestran «—».</p>}
      {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Región desplazable: el foco habilita consultar sus columnas con las flechas del teclado. */}
      <div className="citas-tabla-scroll" role="region" tabIndex={0} aria-label="Tabla de citas por lead y analista">
        <table className="citas-tabla citas-tabla-compacta citas-tabla-metas w-full text-sm">
          <caption className="sr-only">Resultados por analista de las citas filtradas</caption>
          <thead><tr><th scope="col">Analista</th>{columnas.supervisor && <th scope="col">Supervisor</th>}<th scope="col">Citas computables</th><th scope="col">Leads asignados</th><th scope="col">Citas por lead</th><th scope="col">Cumplimiento</th>{columnas.repetidos && <th scope="col">Leads con 2+ citas</th>}{columnas.realizadas && <th scope="col">Realizadas</th>}<th scope="col"><span className="sr-only">Detalle por lead</span></th></tr></thead>
          <tbody>{filas.map(fila => <tr key={fila.id}>
            <th scope="row"><Button variant="link" className="citas-enlace-analista" onClick={() => onAnalista(fila.id)}>{fila.nombre}</Button></th>
            {columnas.supervisor && <td>{fila.supervisor}</td>}
            <td>{fila.citas ?? '—'}</td><td>{fila.leads ?? '—'}</td><td className="citas-promedio">{numero(fila.promedio, 2)}</td><td aria-label={fila.cumplimiento === null ? "Sin base" : `${numero(fila.cumplimiento, 1)}%`}><div className="citas-cumplimiento"><strong>{fila.cumplimiento === null ? '—' : numero(fila.cumplimiento, 1) + '%'}</strong><div className="citas-barra-meta" aria-hidden="true"><Progress value={(fila.cumplimiento ?? 0)} color="var(--gi-blue)" /></div></div></td>
            {columnas.repetidos && <td>{fila.repetidos}</td>}{columnas.realizadas && <td>{fila.realizadas}</td>}
            <td><Button variant="ghost" size="icon" aria-label={'Ver detalle por lead de ' + fila.nombre} onClick={() => onDesglose(fila.id)}><ChevronRight aria-hidden /></Button></td>
          </tr>)}</tbody>
          <tfoot><tr><th scope="row">Total de la consulta</th>{columnas.supervisor && <td>—</td>}<td>{total.citas ?? '—'}</td><td>{total.leads ?? '—'}</td><td>{numero(total.promedio, 2)}</td><td>{total.cumplimiento === null ? '—' : numero(total.cumplimiento, 1) + '%'}</td>{columnas.repetidos && <td>{citasPorLead(citas).filter(l=>l.citas.length>1).length}</td>}{columnas.realizadas && <td>{citas.filter(cita => cita.estado === 'realizada').length}</td>}<td>—</td></tr></tfoot>
        </table>
      </div>
    </section>}
    <AyudaMetricas abierta={ayuda} onCerrar={() => setAyuda(false)} />
  </div>
}

export function DetalleLeads({ analista, citas, filtros = defaults(), onCerrar, onLead }: { analista: string | null; citas: CitaConLead[]; filtros?: FiltrosCitas; onCerrar: () => void; onLead: (leadId: string, analista: string) => void }) {
  const { nombreAnalista, gestion, onAbrirLead } = useDatosCitas()
  const delAnalista = citas.filter(cita => cita.analista === analista)
  const base = gestion ? baseCitasFiltrada(gestion.asignaciones, filtros).filter(l => l.id === analista && !l.manualPropio) : undefined
  const conCitas = citasPorLead(delAnalista)
  const leads = [...conCitas, ...(base ?? []).filter(l => !conCitas.some(c => c.id === l.leadId)).map(l => ({id:l.leadId,nombre:l.nombreLead,citas:[] as CitaConLead[]}))]
  const resumen = metaCitas(delAnalista, base, gestion?.citasPorLead, gestion?.actividadManuales)
  return <Sheet open={Boolean(analista)} onClose={onCerrar} className="citas-crm-dialogo w-[540px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div><p className="mb-1 text-xs text-muted-foreground-strong">Citas por lead · filtros actuales</p><SheetTitle>{analista ? nombreAnalista(analista) : 'Detalle por lead'}</SheetTitle></div><Button variant="ghost" size="icon" aria-label="Cerrar detalle por lead" onClick={onCerrar}><X aria-hidden /></Button></div></SheetHeader>
    <SheetBody><p className="mb-2 text-sm"><strong>{delAnalista.length} citas</strong> en <strong>{conCitas.length} leads con cita</strong>. La base del mes contiene <strong>{resumen.leads ?? '—'} leads asignados</strong>.</p>
      <p className="mb-4 text-sm text-muted-foreground-strong">{resumen.cumplimiento === null ? 'Sin base' : numero(resumen.cumplimiento, 1) + '% de cumplimiento'}</p>
      <ul className="divide-y divide-border">{leads.map(lead => <li key={lead.id} className="flex items-center justify-between gap-3 py-4"><div><h3 className="text-sm font-semibold">{lead.nombre}</h3><p className="mt-1 text-xs text-muted-foreground-strong">{lead.id} · {lead.citas.length} {lead.citas.length === 1 ? 'cita' : 'citas'}</p></div>{lead.citas.length ? <Button variant="outline" size="sm" aria-label={'Ver citas de ' + lead.nombre} onClick={() => onLead(lead.id, analista!)}>Ver citas <ChevronRight aria-hidden /></Button> : onAbrirLead ? <Button variant="outline" size="sm" onClick={() => { onCerrar(); onAbrirLead(lead.id, '') }}>Ver ficha</Button> : <span className="text-xs text-muted-foreground-strong">Sin citas</span>}</li>)}</ul>
      <p className="mt-4 text-xs text-muted-foreground-strong">El cumplimiento compara la actividad con la base asignada del mes. Un lead sin cita permanece en esa base; no se exige un número entero de citas a cada persona.</p>
    </SheetBody>
  </Sheet>
}
