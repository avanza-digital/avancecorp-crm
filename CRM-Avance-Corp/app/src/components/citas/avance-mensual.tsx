import { useState } from 'react'
import { ChevronRight, Download, Info, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Sheet, SheetBody, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { money, numero } from '@/lib/format'
import type { Moneda } from '@/lib/format'
import { useDatosCitas } from './contexto'
import { calcularAvanceCitas, type AvanceCitas, type FilaAvanceCitas } from './avance'
import { LeyendaResultados, SenalMetrica } from './senal-resultado'
import type { FiltrosCitas } from './modelo'
import './avance-mensual.css'

const porcentaje = (valor: number | null) => valor === null ? null : valor * 100
const importe = (valor: number | null, moneda: Moneda) => valor === null ? 'Sin base' : money(valor, moneda)

function ColumnasAvance({ fila, resumen, moneda, abrir, parcial }: {
  fila: FilaAvanceCitas | AvanceCitas['total']; resumen: AvanceCitas; moneda: Moneda;
  abrir?: (() => void) | undefined; parcial?: boolean;
}) {
  return <>
    <td>{numero(fila.leads)}</td>
    <td><strong>{numero(fila.citas)}</strong><small>{numero(fila.promedio, 2)} por lead</small></td>
    <td><SenalMetrica valor={fila.cumplimiento} objetivo={100} ritmo={resumen.periodo.ritmo} etiqueta="Avance de citas" abrir={abrir} barra /></td>
    <td><SenalMetrica valor={porcentaje(fila.tasaEntrevistas)} objetivo={resumen.config.entrevistas_porcentaje} etiqueta="Entrevistas" abrir={abrir} /><small>{numero(fila.entrevistas)} entrevistas</small></td>
    <td><SenalMetrica valor={porcentaje(fila.conversion)} objetivo={resumen.config.depositos_porcentaje} etiqueta="Conversión" abrir={abrir} /><small>{numero(fila.clientes)} clientes</small></td>
    <td title={fila.sinImporte ? `${fila.sinImporte} clientes sin importe real comprobable` : `${fila.clientesTicket} clientes con importe en ${moneda}`}>{importe(fila.ticket, moneda)}</td>
    <td className="cm-cierre" title={fila.motivoProyeccion ?? 'Estimación con el ritmo y el ticket del mes'}><strong>{importe(fila.proyeccion, moneda)}</strong><small>{fila.proyeccion === null ? fila.motivoProyeccion : parcial ? 'Estimación parcial' : resumen.periodo.cerrado ? 'Resultado del mes' : 'Estimado al cierre'}</small></td>
  </>
}

function DatosDelAnalista({ fila, resumen, moneda, cerrar, verCitas }: {
  fila: FilaAvanceCitas; resumen: AvanceCitas; moneda: Moneda; cerrar: () => void; verCitas: () => void;
}) {
  const { gestion, onAbrirLead } = useDatosCitas()
  const [mostrar, setMostrar] = useState(false)
  const [soloSin, setSoloSin] = useState(false)
  const [pagina, setPagina] = useState(0)
  const personas = gestion?.avance?.poblacion ?? []
  const ids = new Set([...fila.base.map(p => p.leadId), ...fila.actividad.map(c => c.leadId)])
  const lista = personas.filter(p => ids.has(p.lead_id) && (!soloSin || !fila.actividad.some(c => c.leadId === p.lead_id)))
  const faltantes = Math.max(0, Math.ceil(fila.leads * resumen.config.citas_por_lead) - fila.citas)
  return <>
    <p className="cm-texto">{fila.supervisor} · {fila.manuales} leads de registro manual incluidos en la base.</p>
    <dl className="cm-desglose">
      <div><dt>Avance de citas</dt><dd><SenalMetrica valor={fila.cumplimiento} objetivo={100} ritmo={resumen.periodo.ritmo} etiqueta="Avance de citas" /><small>{faltantes ? `Faltan ${numero(faltantes)} citas para la meta del mes` : fila.leads ? 'Meta mensual alcanzada' : 'Sin base de leads asignados'}</small></dd></div>
      <div><dt>Entrevistas · objetivo {resumen.config.entrevistas_porcentaje}%</dt><dd><SenalMetrica valor={porcentaje(fila.tasaEntrevistas)} objetivo={resumen.config.entrevistas_porcentaje} etiqueta="Entrevistas" /><small>{fila.entrevistas} entrevistas / {numero(fila.baseEntrevistas, 2)} {resumen.config.base_avance === 'meta_proyectada' ? 'citas de meta' : 'citas con resultado'}</small></dd></div>
      <div><dt>Conversión · objetivo {resumen.config.depositos_porcentaje}%</dt><dd><SenalMetrica valor={porcentaje(fila.conversion)} objetivo={resumen.config.depositos_porcentaje} etiqueta="Conversión" /><small>{fila.clientes} clientes / {fila.baseConversion} {resumen.config.base_depositos === 'entrevistas' ? 'entrevistas' : 'personas entrevistadas'}</small></dd></div>
      <div><dt>Ticket del mes</dt><dd>{importe(fila.ticket, moneda)}<small>{importe(fila.capital, moneda)} / {fila.clientesTicket} clientes con importe en {moneda}</small></dd></div>
      <div><dt>Cierre mensual estimado</dt><dd>{importe(fila.proyeccion, moneda)}<small>{fila.motivoProyeccion ?? 'Incluye el capital ya captado; no es un importe adicional.'}</small></dd></div>
    </dl>
    <p className="cm-texto">{fila.entrevistas - fila.unicas} entrevistas adicionales de personas que ya habían asistido. {fila.sinCita.length} leads asignados todavía sin una cita registrada en el mes.</p>
    {fila.clientesFueraCohorte > 0 && <p className="cm-texto">Además tiene {fila.clientesFueraCohorte} clientes sin una entrevista previa atribuida a este analista en la consulta. Se conservan fuera de la tasa para mantener su base comparable.</p>}
    {fila.sinImporte > 0 && <p className="cm-texto">Falta comprobar el importe del mes de {fila.sinImporte} clientes. El ticket y la proyección permanecen sin base hasta disponer de esos importes.</p>}
    {fila.atribucionPendiente > 0 && <p className="cm-texto">{fila.atribucionPendiente} contratos tienen un analista de capital distinto del analista del cierre. Revisa esa atribución para calcular el ticket y la proyección.</p>}
    <div className="cm-acciones"><Button variant="outline" onClick={() => { setMostrar(!mostrar); setPagina(0) }} aria-expanded={mostrar}>{mostrar ? 'Ocultar leads' : 'Ver leads y citas'}</Button><Button variant="ghost" onClick={verCitas}>Abrir bandeja</Button></div>
    {mostrar && <div className="cm-personas">
      <label className="cm-check"><input type="checkbox" checked={soloSin} onChange={e => { setSoloSin(e.target.checked); setPagina(0) }} />Solo leads sin citas</label>
      {lista.slice(pagina * 20, pagina * 20 + 20).map(p => <div className="cm-persona" key={p.lead_id}><span>{p.nombre}<small>{fila.actividad.filter(c => c.leadId === p.lead_id).length} citas{p.registro_manual ? ' · Manual' : ''}</small></span>{onAbrirLead && <Button variant="ghost" size="icon" aria-label={`Abrir ficha de ${p.nombre}`} onClick={() => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(p.lead_id, ''))) }}><ChevronRight aria-hidden /></Button>}</div>)}
      <div className="cm-paginacion"><span>{lista.length ? pagina * 20 + 1 : 0}–{Math.min(lista.length, pagina * 20 + 20)} de {lista.length}</span><Button size="sm" variant="outline" disabled={!pagina} onClick={() => setPagina(pagina - 1)}>Anterior</Button><Button size="sm" variant="outline" disabled={(pagina + 1) * 20 >= lista.length} onClick={() => setPagina(pagina + 1)}>Siguiente</Button></div>
    </div>}
  </>
}

export function AvanceMensualCitas({ filtros, onAnalista }: { filtros: FiltrosCitas; onAnalista: (id: string) => void }) {
  const { gestion, citas, corte, modoDemo } = useDatosCitas()
  const [abierto, setAbierto] = useState<string | null>(null)
  const [ayuda, setAyuda] = useState(false)
  const [exportado, setExportado] = useState('')
  const [moneda, setMoneda] = useState<Moneda>('PEN')
  const resumen = calcularAvanceCitas(gestion!, citas, filtros, corte, moneda)
  const fila = resumen.filas.find(f => f.id === abierto)
  const mes = new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'America/Lima' }).format(new Date(`${filtros.mes}-15T12:00:00-05:00`))
  function exportar() {
    const celda = (valor: unknown) => '"' + String(valor ?? '').replace(/^[\s=+@-]/, m => `'${m}`).replaceAll('"', '""') + '"'
    const cabecera = ['Mes', 'Analista', 'Supervisor', 'Leads asignados', 'Citas registradas', 'Citas por lead', 'Cumplimiento %', 'Entrevistas', 'Entrevistas %', 'Clientes de entrevistas', 'Conversión %', 'Ticket del mes', 'Cierre proyectado', 'Moneda', 'Versión de reglas', 'Datos']
    const filas = resumen.filas.map(f => [filtros.mes, f.nombre, f.supervisor, f.leads, f.citas, f.promedio, f.cumplimiento, f.entrevistas, porcentaje(f.tasaEntrevistas), f.clientes, porcentaje(f.conversion), f.ticket, f.proyeccion, moneda, resumen.version, modoDemo ? 'Ejemplo' : 'CRM'])
    const url = URL.createObjectURL(new Blob(['\uFEFF' + [cabecera, ...filas].map(r => r.map(celda).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8;' }))
    const enlace = document.createElement('a')
    try { enlace.href = url; enlace.download = `citas-avance-${filtros.mes}-${moneda}.csv`; document.body.append(enlace); enlace.click(); setExportado('Avance mensual exportado.') }
    catch { setExportado('No se pudo exportar el avance. Vuelve a intentarlo.') }
    finally { enlace.remove(); window.setTimeout(() => URL.revokeObjectURL(url), 1000) }
  }
  return <section className="cm-panel" aria-labelledby="cm-titulo">
    <div className="cm-cabecera"><div><h2 id="cm-titulo">Avance mensual por analista</h2><p>{mes} · {resumen.config.excluir_manuales_base ? 'Sin altas manuales propias' : 'Leads manuales incluidos'} · importes en {moneda === 'PEN' ? 'soles' : 'dólares'}</p></div><div className="cm-acciones"><Select aria-label="Moneda de los importes reales" value={moneda} onChange={e => setMoneda(e.target.value as Moneda)}><option value="PEN">Soles · PEN</option><option value="USD">Dólares · USD</option></Select><Button size="sm" variant="ghost" onClick={() => setAyuda(true)} aria-label="Cómo se calcula el avance mensual"><Info aria-hidden /></Button><Button size="sm" variant="ghost" onClick={exportar} disabled={!resumen.filas.length}><Download aria-hidden />Exportar avance</Button></div></div>
    {!resumen.reglasListas && <p role="status" className="cm-aviso">Completa y aplica las reglas en el Control de Citas de Superadmin para calcular las tasas y la proyección.</p>}
    {(filtros.semana || filtros.estados.length || filtros.modalidad || filtros.resultado || filtros.seguimiento) && <p className="cm-alcance">La semana y los filtros de estado, modalidad, resultado y seguimiento delimitan el recorrido y la bandeja. Esta tabla conserva el acumulado mensual con su base completa.</p>}
    {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Tabla ancha consultable con flechas del teclado. */}
    <div className="cm-scroll" role="region" tabIndex={0} aria-label="Avance mensual por analista"><table className="cm-tabla">
      <caption className="sr-only">Leads, citas, entrevistas, conversión y proyección mensual. Los indicadores incluyen descripción de su estado.</caption>
      <thead><tr><th scope="col">Analista</th><th scope="col">Leads</th><th scope="col">Citas</th><th scope="col">Avance de citas<small>Meta mensual</small></th><th scope="col">Entrevistas<small>Objetivo {resumen.config.entrevistas_porcentaje}%</small></th><th scope="col">Conversión<small>Objetivo {resumen.config.depositos_porcentaje}%</small></th><th scope="col">Ticket del mes</th><th scope="col">Cierre proyectado</th></tr></thead>
      <tbody>{resumen.filas.map(f => <tr key={f.id}><th scope="row"><button className="cm-nombre" onClick={() => setAbierto(f.id)}><span className="cm-avatar" aria-hidden>{f.nombre.split(' ').slice(0, 2).map(p => p[0]).join('')}</span><span>{f.nombre}<small>{f.supervisor}</small></span><ChevronRight aria-hidden /></button></th><ColumnasAvance fila={f} resumen={resumen} moneda={moneda} abrir={() => setAbierto(f.id)} /></tr>)}</tbody>
      <tfoot><tr><th scope="row">Total del equipo<small>{resumen.total.parciales} de {resumen.total.analistas} con proyección</small></th><ColumnasAvance fila={resumen.total} resumen={resumen} moneda={moneda} parcial={resumen.total.parciales < resumen.total.analistas} /></tr></tfoot>
    </table></div>
    {!resumen.filas.length && <p className="cm-texto">No hay actividad ni leads asignados con estos filtros.</p>}
    <div className="cm-pie"><LeyendaResultados /><button onClick={() => setAyuda(true)} className="cm-ayuda">Cómo se calcula <Info aria-hidden /></button></div>
    <p role="status" className="sr-only">{exportado}</p>
    <Sheet open={Boolean(fila)} onClose={() => setAbierto(null)} className="cm-detalle w-[530px]"><SheetHeader><div className="cm-cabecera"><SheetTitle>{fila?.nombre ?? 'Detalle del analista'}</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar detalle del analista" onClick={() => setAbierto(null)}><X aria-hidden /></Button></div></SheetHeader><SheetBody>{fila && <DatosDelAnalista key={`${fila.id}-${filtros.mes}`} fila={fila} resumen={resumen} moneda={moneda} cerrar={() => setAbierto(null)} verCitas={() => { setAbierto(null); onAnalista(fila.id) }} />}</SheetBody></Sheet>
    <Sheet open={ayuda} onClose={() => setAyuda(false)} className="cm-detalle w-[530px]"><SheetHeader><div className="cm-cabecera"><SheetTitle>Cómo se calcula el avance</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar ayuda del avance" onClick={() => setAyuda(false)}><X aria-hidden /></Button></div></SheetHeader><SheetBody><div className="cm-reglas">
      <section><h3>Citas y base mensual</h3><p>Citas registradas en el CRM durante el mes, aunque su fecha prevista sea posterior. Se comparan con los leads asignados del mes, incluidos quienes aún no tienen cita. La meta se configura internamente en Superadmin.</p></section>
      <section><h3>Entrevistas y conversión</h3><p>Cada cita realizada con registro de entrevista suma una entrevista. {resumen.config.base_avance === 'meta_proyectada' ? 'La tasa compara entrevistas con la meta de citas.' : 'La tasa usa las citas con resultado: realizadas y no asistidas. Las futuras, canceladas y pendientes de resultado quedan fuera del divisor.'}</p><p>La conversión divide clientes vinculados después de una entrevista entre {resumen.config.base_depositos === 'entrevistas' ? 'todas las entrevistas' : 'personas distintas entrevistadas'}. El cliente cuenta una vez; las visitas repetidas se conservan.</p></section>
      <section><h3>Mes y responsable</h3><p>{resumen.config.mes_resultado === 'asignacion' ? 'Los resultados siguen a los leads desde el mes de su primera asignación hasta el corte de seguimiento.' : 'Las entrevistas y conversiones corresponden al mes en que se registraron sus resultados. Las inasistencias usan la fecha prevista de su cita.'} {resumen.config.analista_resultado === 'asignacion' ? 'Se atribuyen al primer analista del ledger de asignación.' : 'Se atribuyen al responsable de la cita y al analista que obtuvo la conversión, conservado en el historial.'}</p><p>Las tasas requieren entrevista previa del mismo responsable. Los cierres sin esa relación se muestran por separado en su detalle. Un lead puede figurar en la base de más de un analista; el total cuenta personas distintas.</p></section>
      <section><h3>Ticket y cierre proyectado</h3><p>El ticket divide el capital real de contratos nuevos de clientes convertidos en el mes entre esos clientes. No utiliza montos estimados ni añade renovaciones. El selector de esta tabla usa la moneda real del contrato. El filtro avanzado de moneda estimada delimita la población comercial. Muestra «Sin base» si faltan importes o su atribución es inconsistente.</p><p>La estimación extiende el ritmo de citas generadas y previstas para este mes hasta su fin, aplica las tasas observadas y descuenta entrevistas repetidas antes de estimar personas. Respeta la población disponible e incluye lo ya captado. El total suma las proyecciones individuales y señala cuando es parcial.</p></section>
      <section><h3>Significado de los colores</h3><p>Azul: meta alcanzada. Ámbar: avance inferior a la meta y de al menos su mitad. Rojo: brecha mayor. Gris: sin base para evaluar. Citas compara además el ritmo con el momento del mes; la marca en la barra indica {numero(resumen.periodo.ritmo, 1)}%.</p><p>El ticket y la proyección conservan tonos neutros porque no tienen una meta monetaria configurada. El recorrido de recuperación usa su propia población.</p></section>
    </div></SheetBody></Sheet>
  </section>
}
