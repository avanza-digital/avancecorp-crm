import { useState } from 'react'
import { ChevronRight, Download, Info, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { money, numero } from '@/lib/format'
import { useTipoCambio } from '@/lib/tipo-cambio'
import { rotuloTipoCambio } from '@/lib/capital-unificado'
import { CoberturaCapitalAviso } from '@/components/common/cobertura-capital'
import { csvAvanceCitas } from './avance-csv'
import { useDatosCitas } from './contexto'
import { calcularAvanceCitas, fechaLocalCitas, periodoAvance, type AvanceCitas, type FilaAvanceCitas, type OperacionesCapital } from './avance'
import { LeyendaResultados, SenalMetrica } from './senal-resultado'
import { MarcaAnalista } from './marca-analista'
import { defaults, type FiltrosCitas } from './modelo'
import './avance-mensual.css'

const porcentaje = (valor: number | null) => valor === null ? null : valor * 100
// Gerencia lee el avance en bruto: citas por lead × 100 frente a la meta configurada
// (Miguel, 16/10/2026: «ver en bruto el 125%», no el 88.4% de esa meta). Valor, meta
// y ritmo se escalan juntos, así que el color y la barra no cambian.
const avanceBruto = (promedio: number | null, resumen: AvanceCitas) => ({
  valor: porcentaje(promedio), objetivo: resumen.config.citas_por_lead * 100,
  ritmo: resumen.periodo.ritmo === null ? null : resumen.periodo.ritmo * resumen.config.citas_por_lead,
})
const importe = (valor: number | null, faltaTc = false, pendiente = false) => valor !== null ? money(valor, 'PEN') : pendiente ? 'Pendiente de valoración' : faltaTc ? 'Pendiente de TC' : 'Sin base'
const ROTULOS_OPERACIONES: Record<keyof OperacionesCapital, [string, string]> = {
  nuevos: ['contrato nuevo', 'contratos nuevos'], upgrades: ['upgrade', 'upgrades'],
  renovaciones: ['renovación', 'renovaciones'], cooperativas: ['cierre en cooperativa', 'cierres en cooperativa'],
}
const desglose = (o: OperacionesCapital) => (Object.keys(ROTULOS_OPERACIONES) as (keyof OperacionesCapital)[])
  .filter(k => o[k] > 0).map(k => `${numero(o[k])} ${ROTULOS_OPERACIONES[k][o[k] === 1 ? 0 : 1]}`).join(' · ') || 'Sin operaciones en el mes'

function ColumnasAvance({ fila, resumen, abrir, parcial }: {
  fila: FilaAvanceCitas | AvanceCitas['total']; resumen: AvanceCitas;
  abrir?: (() => void) | undefined; parcial?: boolean;
}) {
  return <>
    <td>{numero(fila.leads)}</td>
    <td><strong>{numero(fila.citas)}</strong><small>{numero(fila.promedio, 2)} por lead</small></td>
    <td><SenalMetrica {...avanceBruto(fila.promedio, resumen)} etiqueta="Avance de citas" abrir={abrir} barra /></td>
    <td><SenalMetrica valor={porcentaje(fila.tasaEntrevistas)} objetivo={resumen.config.entrevistas_porcentaje} etiqueta="Entrevistas" abrir={abrir} /><small>{numero(fila.entrevistas)} entrevistas</small></td>
    <td>{resumen.testigoCuadra === false ? <strong>En revisión</strong> : <SenalMetrica valor={porcentaje(fila.conversion)} objetivo={resumen.config.depositos_porcentaje} etiqueta="Depósito" abrir={abrir} />}<small>{numero(fila.clientesPeriodo)} clientes</small>{fila.clientesFueraCohorte > 0 && <small>{numero(fila.clientes)} de entrevistas del periodo</small>}</td>
    <td title={fila.motivoTicket ?? `${fila.clientesTicket} clientes únicos con capital en el mes · ${desglose(fila.operaciones)} · todas las monedas convertidas a soles`}>{importe(fila.ticket, fila.faltaTipoCambio, fila.capitalPendiente)}</td>
    <td className="cm-cierre" title={parcial && fila.proyeccion !== null ? 'Suma de los analistas con proyección calculable; los pendientes quedan fuera' : fila.motivoProyeccion ?? 'Estimación con el ritmo y el ticket del mes'}><strong>{resumen.testigoCuadra === false ? 'En revisión' : importe(fila.proyeccion, fila.faltaTipoCambio, fila.capitalPendiente)}</strong><small>{fila.proyeccion === null ? fila.motivoProyeccion : parcial ? 'Estimación parcial' : resumen.periodo.cerrado ? 'Resultado del mes' : 'Estimado al cierre'}</small></td>
  </>
}

function DatosDelAnalista({ fila, resumen, cerrar, verCitas }: {
  fila: FilaAvanceCitas; resumen: AvanceCitas; cerrar: () => void; verCitas: () => void;
}) {
  const { gestion, onAbrirLead } = useDatosCitas()
  const [mostrar, setMostrar] = useState(false)
  const [soloSin, setSoloSin] = useState(false)
  const [pagina, setPagina] = useState(0)
  const personas = gestion?.avance?.poblacion ?? []
  const ids = new Set([...fila.base.map(p => p.leadId), ...fila.actividad.map(c => c.leadId), ...fila.visitas.map(c => c.leadId), ...fila.cierres.map(c => c.lead_id)])
  const sinCita = new Set(fila.sinCita.map(p => p.leadId))
  const lista = personas.filter(p => ids.has(p.lead_id) && (!soloSin || sinCita.has(p.lead_id)))
  const faltantes = Math.max(0, Math.ceil(fila.leads * resumen.config.citas_por_lead) - fila.citas)
  return <>
    <p className="cm-texto">{fila.supervisor} · {fila.manuales} leads de registro manual incluidos en la base.</p>
    <dl className="cm-desglose">
      <div><dt>Avance de citas · meta {numero(resumen.config.citas_por_lead * 100, 1)}%</dt><dd><SenalMetrica {...avanceBruto(fila.promedio, resumen)} etiqueta="Avance de citas" /><small>{faltantes ? `Faltan ${numero(faltantes)} citas para la meta del mes` : fila.leads ? 'Meta mensual alcanzada' : 'Sin base de leads asignados'}</small></dd></div>
      <div><dt>Entrevistas · objetivo {resumen.config.entrevistas_porcentaje}%</dt><dd><SenalMetrica valor={porcentaje(fila.tasaEntrevistas)} objetivo={resumen.config.entrevistas_porcentaje} etiqueta="Entrevistas" /><small>{fila.entrevistas} entrevistas / {numero(fila.baseEntrevistas, 2)} {resumen.config.base_avance === 'meta_proyectada' ? 'citas de meta' : 'citas con resultado'}</small></dd></div>
      <div><dt>Depósito · objetivo {resumen.config.depositos_porcentaje}%</dt><dd>{resumen.testigoCuadra === false ? <strong>En revisión</strong> : <SenalMetrica valor={porcentaje(fila.conversion)} objetivo={resumen.config.depositos_porcentaje} etiqueta="Depósito" />}<small>{fila.clientes} clientes / {fila.baseConversion} {resumen.config.base_depositos === 'entrevistas' ? 'entrevistas' : 'personas entrevistadas'}</small></dd></div>
      <div><dt>Ticket del mes</dt><dd>{importe(fila.ticket, fila.faltaTipoCambio, fila.capitalPendiente)}<small>{importe(fila.capital, fila.faltaTipoCambio, fila.capitalPendiente)} / {fila.clientesTicket} clientes únicos con capital</small><small>{desglose(fila.operaciones)}</small><small>Originales: {money(fila.capitalPen, 'PEN')} · {money(fila.capitalUsd, 'USD')}</small></dd></div>
      <div><dt>Cierre mensual estimado</dt><dd>{resumen.testigoCuadra === false ? 'En revisión' : importe(fila.proyeccion, fila.faltaTipoCambio, fila.capitalPendiente)}<small>{fila.motivoProyeccion ?? 'Incluye el capital ya captado; no es un importe adicional.'}</small></dd></div>
    </dl>
    <p className="cm-texto">{fila.entrevistas - fila.unicas} entrevistas adicionales de personas que ya habían asistido. {fila.sinCita.length} leads asignados todavía sin una cita registrada en el mes.</p>
    {fila.clientesFueraCohorte > 0 && <p className="cm-texto">Consiguió {fila.clientesPeriodo} clientes en el periodo: {fila.clientes} de las personas entrevistadas por este analista en la consulta y {fila.clientesFueraCohorte} de otros cierres. Estos últimos sí cuentan como clientes; la tasa compara únicamente las entrevistas de su base.</p>}
    {fila.faltaTipoCambio && <p className="cm-texto">El ticket y la proyección están pendientes del tipo de cambio. Los importes originales en soles y dólares siguen disponibles.</p>}
    {fila.sinContrato > 0 && <p className="cm-texto">{fila.sinContrato} {fila.sinContrato === 1 ? 'cliente convertido' : 'clientes convertidos'} en el mes todavía sin capital registrado este mes. Cuentan en el indicador de depósito; no entran en el ticket hasta que firmen.</p>}
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
  const periodo = periodoAvance(filtros.mes, corte)
  const fechaCorte = fechaLocalCitas(new Date(periodo.corte).toISOString())
  const valoracion = gestion!.avance!.valoracion
  const requiereTc = !valoracion && gestion!.avance!.capital.some(k => k.moneda === 'USD' && k.monto > 0)
  const { tc, recargar } = useTipoCambio(requiereTc, fechaCorte)
  const mensual = calcularAvanceCitas(gestion!, citas, defaults(filtros.mes), corte, tc?.promedio)
  const resumen = { ...calcularAvanceCitas(gestion!, citas, filtros, corte, tc?.promedio),
    testigoCuadra: mensual.testigoCuadra, diferenciasTestigo: mensual.diferenciasTestigo }
  const hayDolares = resumen.total.capitalUsd > 0
  const fila = resumen.filas.find(f => f.id === abierto)
  const mes = new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'America/Lima' }).format(new Date(`${filtros.mes}-15T12:00:00-05:00`))
  function exportar() {
    if (resumen.testigoCuadra === false) return
    const url = URL.createObjectURL(new Blob([csvAvanceCitas(resumen, filtros.mes, modoDemo ? 'Ejemplo' : 'CRM', tc?.fuente, fechaCorte)], { type: 'text/csv;charset=utf-8;' }))
    const enlace = document.createElement('a')
    try { enlace.href = url; enlace.download = `citas-avance-${filtros.mes}-PEN.csv`; document.body.append(enlace); enlace.click(); setExportado('Avance mensual exportado.') }
    catch { setExportado('No se pudo exportar el avance. Vuelve a intentarlo.') }
    finally { enlace.remove(); window.setTimeout(() => URL.revokeObjectURL(url), 1000) }
  }
  return <section className="cm-panel" aria-labelledby="cm-titulo">
    <div className="cm-cabecera"><div><h2 id="cm-titulo">Avance mensual por analista</h2><p>{mes} · {resumen.config.excluir_manuales_base ? 'Sin altas manuales propias' : 'Leads manuales incluidos'} · ventas por fecha comercial · ticket y proyección en soles</p><p aria-label="Capital del mes por moneda">Capital del mes: <strong>{money(resumen.total.capitalPen, 'PEN')}</strong> · <strong>{money(resumen.total.capitalUsd, 'USD')}</strong>{hayDolares && resumen.tc !== null && <> · {rotuloTipoCambio(resumen.tc, tc!.fuente)}</>}</p></div><div className="cm-acciones"><Button size="sm" variant="ghost" onClick={() => setAyuda(true)} aria-label="Cómo se calcula el avance mensual"><Info aria-hidden /></Button><Button size="sm" variant="ghost" onClick={exportar} disabled={!resumen.filas.length || resumen.testigoCuadra === false}><Download aria-hidden />Exportar avance</Button></div></div>
    {resumen.testigoCuadra === false && <div role="status" className="cm-aviso-testigo rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs text-amber-900">
      <strong>El total de {mes} necesita revisión.</strong>
      <p>La pantalla y el servidor difieren en estos datos:</p>
      <ul>{resumen.diferenciasTestigo.map(d => <li key={d.campo}>{d.campo}: pantalla {String(d.pantalla)} · servidor {String(d.servidor)}.</li>)}</ul>
      <p>El porcentaje de depósito, la proyección y la exportación quedan pendientes hasta conciliar las cifras. Actualiza la consulta; si persiste, informa el mes y las diferencias indicadas.</p>
    </div>}
    {valoracion && <CoberturaCapitalAviso cobertura={valoracion.cobertura} sellado={valoracion.sellado} sinCorte="El ticket y la proyección están pendientes de la primera publicación de capital valorado." />}
    {!valoracion && hayDolares && resumen.tc === null && <div role="status" className="cm-aviso cm-acciones"><span>{tc === undefined ? 'Consultando el tipo de cambio para incluir dólares…' : 'No se pudo obtener el tipo de cambio. El ticket y la proyección con dólares están pendientes.'}</span>{tc !== undefined && <Button size="sm" variant="outline" onClick={recargar}>Reintentar tipo de cambio</Button>}</div>}
    {!resumen.reglasListas && <p role="status" className="cm-aviso">Completa y aplica las reglas en el Control de Citas de Superadmin para calcular las tasas y la proyección.</p>}
    {(filtros.semana || filtros.estados.length || filtros.modalidad || filtros.resultado || filtros.seguimiento) && <p className="cm-alcance">La semana y los filtros de estado, modalidad, resultado y seguimiento delimitan el recorrido y la bandeja. Esta tabla conserva el acumulado mensual con su base completa.</p>}
    {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Tabla ancha consultable con flechas del teclado. */}
    <div className="cm-scroll" role="region" tabIndex={0} aria-label="Avance mensual por analista"><table className="cm-tabla">
      <caption className="sr-only">Leads, citas, entrevistas, depósito y proyección mensual. Los indicadores incluyen descripción de su estado.</caption>
      <thead><tr><th scope="col">Analista</th><th scope="col">Leads</th><th scope="col">Citas</th><th scope="col">Avance de citas<small>Meta {numero(resumen.config.citas_por_lead * 100, 1)}%</small></th><th scope="col">Entrevistas<small>Objetivo {resumen.config.entrevistas_porcentaje}%</small></th><th scope="col">Depósito<small>Objetivo {resumen.config.depositos_porcentaje}%</small></th><th scope="col">Ticket del mes</th><th scope="col">Cierre proyectado</th></tr></thead>
      <tbody>{resumen.filas.map(f => <tr key={f.id}><th scope="row"><button className="cm-nombre" onClick={() => setAbierto(f.id)}><span className="cm-avatar" aria-hidden>{f.nombre.split(' ').slice(0, 2).map(p => p[0]).join('')}</span><span>{f.nombre} <MarcaAnalista estado={f.estado} /><small>{f.supervisor}</small></span><ChevronRight aria-hidden /></button></th><ColumnasAvance fila={f} resumen={resumen} abrir={() => setAbierto(f.id)} /></tr>)}</tbody>
      <tfoot><tr><th scope="row">Total del equipo<small>{resumen.total.parciales} de {resumen.total.analistas} con proyección</small></th><ColumnasAvance fila={resumen.total} resumen={resumen} parcial={resumen.total.parciales < resumen.total.analistas} /></tr></tfoot>
    </table></div>
    {!resumen.filas.length && <p className="cm-texto">No hay actividad ni leads asignados con estos filtros.</p>}
    <div className="cm-pie"><LeyendaResultados /><button onClick={() => setAyuda(true)} className="cm-ayuda">Cómo se calcula <Info aria-hidden /></button></div>
    <p role="status" className="sr-only">{exportado}</p>
    <Sheet open={Boolean(fila)} onClose={() => setAbierto(null)} className="cm-detalle w-[530px]"><SheetHeader><div className="cm-cabecera"><SheetTitle>{fila ? <span className="inline-flex flex-wrap items-center gap-1.5">{fila.nombre}<MarcaAnalista estado={fila.estado} /></span> : 'Detalle del analista'}</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar detalle del analista" onClick={() => setAbierto(null)}><X aria-hidden /></Button></div></SheetHeader><SheetBody>{fila && <DatosDelAnalista key={`${fila.id}-${filtros.mes}`} fila={fila} resumen={resumen} cerrar={() => setAbierto(null)} verCitas={() => { setAbierto(null); onAnalista(fila.id) }} />}</SheetBody></Sheet>
    <Sheet open={ayuda} onClose={() => setAyuda(false)} className="cm-detalle w-[530px]"><SheetHeader><div className="cm-cabecera"><SheetTitle>Cómo se calcula el avance</SheetTitle><Button variant="ghost" size="icon" aria-label="Cerrar ayuda del avance" onClick={() => setAyuda(false)}><X aria-hidden /></Button></div></SheetHeader><SheetBody><div className="cm-reglas">
      <section><h3>Citas y base mensual</h3><p>Citas registradas en el CRM durante el mes, aunque su fecha prevista sea posterior. Se comparan con los leads asignados del mes, incluidos quienes aún no tienen cita. El avance muestra las citas por lead en porcentaje (1.1 citas por lead = 110%) frente a la meta de {numero(resumen.config.citas_por_lead * 100, 1)}%, que se configura en Superadmin.</p></section>
      <section><h3>Entrevistas y depósito</h3><p>Cada cita realizada con registro de entrevista suma una entrevista. {resumen.config.base_avance === 'meta_proyectada' ? 'La tasa compara entrevistas con la meta de citas.' : 'La tasa usa las citas con resultado: realizadas y no asistidas. Las futuras, canceladas y pendientes de resultado quedan fuera del divisor.'}</p><p>Se considera depósito cuando la persona se convierte en cliente. El porcentaje de depósito divide los clientes con una entrevista en la misma fecha comercial o antes entre {resumen.config.base_depositos === 'entrevistas' ? 'todas las entrevistas' : 'personas distintas entrevistadas'}. El cliente cuenta una vez; las visitas repetidas se conservan.</p></section>
      <section><h3>Mes y responsable</h3><p>Las ventas pertenecen al mes de su fecha comercial, aunque se carguen después. La fecha de registro se conserva para auditoría. Como la fecha comercial no tiene hora, una entrevista del mismo día se considera compatible; esto no acredita el orden dentro de ese día.</p><p>{resumen.config.mes_resultado === 'asignacion' ? 'Las entrevistas siguen a los leads desde el mes de su primera asignación hasta el corte de seguimiento.' : 'Las entrevistas corresponden al mes de su asistencia registrada. Las inasistencias usan la fecha prevista de su cita.'} {resumen.config.analista_resultado === 'asignacion' ? 'Se atribuyen al primer analista del ledger de asignación.' : 'Se atribuyen al responsable de la cita y al analista que obtuvo el depósito, conservado en el historial.'}</p><p>La tasa de cada analista compara sus entrevistas. El total reconoce también cuando otro analista del equipo consigue el cierre. Todos los cierres cuentan como clientes del periodo; el detalle distingue cuáles corresponden a las personas entrevistadas en esa consulta.</p><p>Una misma identidad vinculada cuenta como una persona. Los leads duplicados que todavía no tengan un vínculo común se cuentan por separado.</p></section>
      <section><h3>Ticket y cierre proyectado</h3><p>El ticket divide todo el capital real que el analista cierra en el mes entre sus clientes únicos con capital. Cuenta contratos nuevos, upgrades, renovaciones y cierres en cooperativas, tomados del mismo núcleo que Mi cartera y el Ranking y atribuidos al analista que figura allí; no exige que el cliente proceda de un lead convertido. No utiliza montos estimados. Incluye todas las monedas: conserva los totales originales en soles y dólares y {valoracion ? 'suma los equivalentes en soles guardados por operación en el corte publicado.' : 'convierte el capital en dólares a soles con el mismo servicio de tipo de cambio del CRM.'} Divide el total convertido entre clientes únicos, aunque una persona firme varias operaciones o invierta en ambas monedas. {valoracion ? 'Cada venta conserva la tasa de su fecha comercial; una cotización posterior no cambia su aporte. El corte incluye las operaciones valoradas hasta hoy; las ventas pendientes de tipo de cambio se muestran aparte y no entran al ticket ni a la proyección. Las cifras de citas y conversión siguen su consulta actual.' : 'La cotización usa el corte indicado: el cierre del mes histórico o el día de consulta del mes actual.'} Los filtros de persona, origen, registro y moneda estimada acotan el capital a los leads que los cumplen. Un cliente convertido sin capital en el mes no anula el ticket: se informa aparte. Muestra «Sin base» cuando no hay capital cerrado en el mes. {!valoracion && 'Si falta el tipo de cambio, los importes que necesitan convertir dólares quedan pendientes y se puede reintentar; nunca se calcula un promedio incompleto.'}</p><p>La estimación extiende el ritmo de citas generadas y previstas para este mes hasta su fin, aplica las tasas observadas y descuenta entrevistas repetidas antes de estimar personas. Respeta la población disponible e incluye lo ya captado. El total suma las proyecciones individuales y señala cuando es parcial.</p></section>
      <section><h3>Significado de los colores</h3><p>Azul: meta alcanzada. Ámbar: avance inferior a la meta y de al menos su mitad. Rojo: brecha mayor. Gris: sin base para evaluar. Citas compara además el ritmo con el momento del mes; la marca en la barra indica {numero(avanceBruto(null, resumen).ritmo, 1)}%, lo esperado a esta altura del mes.</p><p>El ticket y la proyección conservan tonos neutros porque no tienen una meta monetaria configurada. El recorrido de recuperación usa su propia población.</p></section>
    </div></SheetBody></Sheet>
  </section>
}
