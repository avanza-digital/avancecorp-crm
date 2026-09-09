import { useDatosCitas, corteLima } from './contexto'
import { useState } from 'react'
import { ChevronDown, ChevronRight, Columns3, Info, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Progress } from '@/components/ui/progress'
import { Sheet, SheetHeader, SheetTitle, SheetBody } from '@/components/ui/sheet'
import { numero } from '@/lib/format'
import { citasPorLead, resultadosConLeads, type CitaConLead } from './datos'
import { metaCitas, META_CITAS_POR_LEAD, OBJETIVO_CITAS_POR_LEAD, OBJETIVO_CUMPLIMIENTO } from './metas'
import { Inasistencias } from './inasistencias'

function AyudaMetricas({ abierta, onCerrar }: { abierta: boolean; onCerrar: () => void }) {
  const { corte, depositosDisponibles } = useDatosCitas()
  return <Sheet open={abierta} onClose={onCerrar} className="citas-crm-dialogo">
    <SheetHeader><div className="flex items-start justify-between gap-3"><SheetTitle>Cómo se calculan las métricas</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar ayuda de métricas" onClick={onCerrar}><X aria-hidden /></Button></div></SheetHeader>
    <SheetBody className="space-y-5 text-sm leading-relaxed">
      <section><h3 className="font-semibold">Citas por lead</h3><p>Citas de la consulta ÷ leads distintos con cita. Se cuenta cada lead por su código. No incluye leads sin cita ni mide asistencia.</p></section>
      <section><h3 className="font-semibold">Meta y objetivo</h3><p>3 citas por lead equivalen a 100%. El cumplimiento es el promedio ÷ 3 × 100, calculado antes de redondear. El objetivo de 125% equivale a 3.75 citas por lead de promedio.</p><p className="mt-2">Por ejemplo, 15 citas entre 4 leads son 3.75 citas por lead: 125%. Cada lead tiene citas enteras: 3 citas son 100% y 4 son 133.3%.</p></section>
      <section><h3 className="font-semibold">Leads con 3+ citas</h3><p>Personas que tienen al menos tres citas dentro de la consulta. El promedio del analista y la cantidad de personas que llegan a tres son lecturas diferentes.</p></section>
      <section><h3 className="font-semibold">Filtros y total</h3><p>Las métricas usan el período, responsables, estados y demás filtros activos. Seleccionar una etapa del recorrido solo filtra su tabla de personas. La meta de referencia no se divide automáticamente entre las semanas.</p><p className="mt-2">Un lead con citas de varios analistas cuenta en cada uno y una sola vez en el total. El total se recalcula sobre leads únicos; no suma esas columnas ni promedia los promedios.</p></section>
      <section><h3 className="font-semibold">Recuperación hasta el depósito</h3><p>Cada etapa parte de la anterior: no asistió, reprogramó, asistió a una cita vinculada y luego hizo un depósito confirmado. El porcentaje usa los leads que faltaron al inicio. El seguimiento llega al {corteLima(corte)}, aunque la nueva cita o el depósito queden fuera del período de origen.</p></section>
      <p className="text-muted-foreground-strong">{!depositosDisponibles && 'Depósitos: sin verificación disponible. '}La meta de actividad y el resultado comercial son independientes. Haber depositado no requiere llegar a tres citas ni implica agendar otra para completar el contador.</p>
    </SheetBody>
  </Sheet>
}

export function Resultados({ citas, onAnalista, onDesglose, onDetalle, leadAbierto, onLead }: {
  citas: CitaConLead[]
  onAnalista: (id: string) => void
  onDesglose: (id: string) => void
  onDetalle: (cita: CitaConLead) => void
  leadAbierto: string | null
  onLead: (id: string | null) => void
}) {
  const [columnas, setColumnas] = useState({ repetidos: false, realizadas: false, supervisor: false })
  const [ayuda, setAyuda] = useState(false)
  const filas = resultadosConLeads(citas).map(fila => ({ ...fila, ...metaCitas(citas.filter(cita => cita.analista === fila.id)) }))
  const total = metaCitas(citas)
  return <div className="citas-resultados">
    <Inasistencias citas={citas} onDetalle={onDetalle} leadAbierto={leadAbierto} onLead={onLead} />
    <section className="gi-card citas-analistas" aria-label="Citas por lead y analista">
      <div className="citas-cabecera-seccion">
        <div><h2 className="citas-titulo-seccion">Citas por lead y analista</h2>
          <p className="citas-nota">Meta {META_CITAS_POR_LEAD} = 100% · Objetivo {numero(OBJETIVO_CITAS_POR_LEAD, 2)} = {OBJETIVO_CUMPLIMIENTO}%</p>
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
      {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Región desplazable: el foco habilita consultar sus columnas con las flechas del teclado. */}
      <div className="citas-tabla-scroll" role="region" tabIndex={0} aria-label="Tabla de citas por lead y analista">
        <table className="citas-tabla citas-tabla-compacta citas-tabla-metas w-full text-sm">
          <caption className="sr-only">Resultados por analista de las citas filtradas</caption>
          <thead><tr><th scope="col">Analista</th>{columnas.supervisor && <th scope="col">Supervisor</th>}<th scope="col">Citas / leads</th><th scope="col">Citas por lead</th><th scope="col">Cumplimiento</th><th scope="col">Leads con 3+ citas</th>{columnas.repetidos && <th scope="col">Leads con 2+ citas</th>}{columnas.realizadas && <th scope="col">Realizadas</th>}<th scope="col"><span className="sr-only">Detalle por lead</span></th></tr></thead>
          <tbody>{filas.map(fila => <tr key={fila.id}>
            <th scope="row"><Button variant="link" className="citas-enlace-analista" onClick={() => onAnalista(fila.id)}>{fila.nombre}</Button></th>
            {columnas.supervisor && <td>{fila.supervisor}</td>}
            <td>{fila.citas} / {fila.leads}</td><td className="citas-promedio">{numero(fila.promedio, 2)}</td><td aria-label={fila.cumplimiento === null ? "Sin base" : `${numero(fila.cumplimiento, 1)}%`}><div className="citas-cumplimiento"><strong>{fila.cumplimiento === null ? '—' : numero(fila.cumplimiento, 1) + '%'}</strong><div className="citas-barra-meta" aria-hidden="true"><Progress value={(fila.cumplimiento ?? 0) / OBJETIVO_CUMPLIMIENTO * 100} color="var(--gi-blue)" /><span title="Meta 100%" /></div></div></td><td>{fila.leadsConMeta} de {fila.leads}</td>
            {columnas.repetidos && <td>{fila.repetidos}</td>}{columnas.realizadas && <td>{fila.realizadas}</td>}
            <td><Button variant="ghost" size="icon" aria-label={'Ver detalle por lead de ' + fila.nombre} onClick={() => onDesglose(fila.id)}><ChevronRight aria-hidden /></Button></td>
          </tr>)}</tbody>
          <tfoot><tr><th scope="row">Total de la consulta</th>{columnas.supervisor && <td>—</td>}<td>{total.citas} / {total.leads}</td><td>{numero(total.promedio, 2)}</td><td>{total.cumplimiento === null ? '—' : numero(total.cumplimiento, 1) + '%'}</td><td>{total.leadsConMeta} de {total.leads}</td>{columnas.repetidos && <td>{total.repetidos}</td>}{columnas.realizadas && <td>{citas.filter(cita => cita.estado === 'realizada').length}</td>}<td>—</td></tr></tfoot>
        </table>
      </div>
    </section>
    <AyudaMetricas abierta={ayuda} onCerrar={() => setAyuda(false)} />
  </div>
}

export function DetalleLeads({ analista, citas, onCerrar, onLead }: { analista: string | null; citas: CitaConLead[]; onCerrar: () => void; onLead: (leadId: string, analista: string) => void }) {
  const { nombreAnalista } = useDatosCitas()
  const delAnalista = citas.filter(cita => cita.analista === analista)
  const leads = citasPorLead(delAnalista)
  const resumen = metaCitas(delAnalista)
  return <Sheet open={Boolean(analista)} onClose={onCerrar} className="citas-crm-dialogo w-[540px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div><p className="mb-1 text-xs text-muted-foreground-strong">Citas por lead · filtros actuales</p><SheetTitle>{analista ? nombreAnalista(analista) : 'Detalle por lead'}</SheetTitle></div><Button variant="ghost" size="icon" aria-label="Cerrar detalle por lead" onClick={onCerrar}><X aria-hidden /></Button></div></SheetHeader>
    <SheetBody><p className="mb-2 text-sm"><strong>{delAnalista.length} citas</strong> en <strong>{resumen.leads} leads</strong>: promedio <strong>{numero(resumen.promedio, 2)}</strong> citas por lead.</p>
      <p className="mb-4 text-sm text-muted-foreground-strong">{resumen.cumplimiento === null ? 'Sin base' : numero(resumen.cumplimiento, 1) + '% de cumplimiento'} · {resumen.leadsConMeta} de {resumen.leads} leads con 3+ citas.</p>
      <ul className="divide-y divide-border">{leads.map(lead => <li key={lead.id} className="flex items-center justify-between gap-3 py-4"><div><h3 className="text-sm font-semibold">{lead.nombre}</h3><p className="mt-1 text-xs text-muted-foreground-strong">{lead.id} · {lead.citas.length} {lead.citas.length === 1 ? 'cita' : 'citas'} · {numero(metaCitas(lead.citas).cumplimiento, 1)}%</p></div><Button variant="outline" size="sm" aria-label={'Ver citas de ' + lead.nombre} onClick={() => onLead(lead.id, analista!)}>Ver citas <ChevronRight aria-hidden /></Button></li>)}</ul>
      <p className="mt-4 text-xs text-muted-foreground-strong">Se cuentan citas de los estados seleccionados. La referencia es 3 citas por lead; el objetivo de 125% se supera con cuatro citas en un lead individual.</p>
    </SheetBody>
  </Sheet>
}
