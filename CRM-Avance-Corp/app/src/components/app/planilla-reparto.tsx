import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CalendarDays, RefreshCw } from 'lucide-react'
import { cargarPlanilla, type DatosPlanilla } from '@/data/planilla-reparto'
import { repartirLead } from '@/data/crm-api'
import { hoyLimaIso } from '@/lib/distribucion-lecturas'
import { ORIGENES_LECTURA, origenLabel, type OrigenLectura } from '@/lib/tipos'
import { ejecutarReparto, fechasPeriodo, filasPlanilla, filtrarColaPlanilla, periodoInicial, prepararReparto, type BorradorReparto, type EntregaPreparada, type ResultadoReparto } from '@/lib/planilla-reparto'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { SectionHead } from '@/components/common/section-head'
import { TablaEnvoltura, TheadCrm, Th, Td } from '@/components/common/tabla'
import { Paginacion } from '@/components/common/paginacion'
import { paginar } from '@/lib/paginacion'
import { PeriodoPlanillaControl } from './periodo-planilla'

const mensajeError = (error: unknown) => error instanceof Error ? error.message : 'No se pudo consultar el reparto. Actualiza para volver a intentarlo.'
const suma = (valores: number[]) => valores.reduce((total, valor) => total + valor, 0)

export function PlanillaReparto({ activo = true, revision = 0, onCambio, onOcupado }: {
  activo?: boolean; revision?: number; onCambio: () => void; onOcupado: (ocupado: boolean) => void
}) {
  const [ingreso, setIngreso] = useState(() => periodoInicial('todas'))
  const [reparto, setReparto] = useState(() => periodoInicial('semana'))
  const [origenFiltro, setOrigenFiltro] = useState<OrigenLectura[]>([])
  const [supervisorFiltro, setSupervisorFiltro] = useState<string[]>([])
  const [paginaDesglose, setPaginaDesglose] = useState(0)
  const [vista, setVista] = useState('acumulado')
  const [datos, setDatos] = useState<DatosPlanilla | null>(null)
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [errorRevision, setErrorRevision] = useState<string | null>(null)
  const [aviso, setAviso] = useState('')
  const [borrador, setBorrador] = useState<BorradorReparto>({})
  const [revisionLocal, setRevisionLocal] = useState(0)
  const [revisando, setRevisando] = useState(false)
  const [plan, setPlan] = useState<EntregaPreparada[] | null>(null)
  const [fechaPlan, setFechaPlan] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [progreso, setProgreso] = useState(0)
  const [resultado, setResultado] = useState<ResultadoReparto | null>(null)
  const montado = useRef(false)
  const candado = useRef(false)
  const detener = useRef(false)
  const consulta = useRef<AbortController | null>(null)

  const seleccion = useMemo<{ ingreso: string[] | null; reparto: string[]; error: string | null }>(() => {
    try { return { ingreso: fechasPeriodo(ingreso), reparto: fechasPeriodo(reparto) ?? [], error: null } }
    catch (fallo) { return { ingreso: null, reparto: [], error: mensajeError(fallo) } }
  }, [ingreso, reparto])
  const claveFechas = JSON.stringify(seleccion.reparto)
  const ocupado = revisando || enviando
  useEffect(() => { montado.current = true; return () => { montado.current = false; detener.current = true; consulta.current?.abort() } }, [])
  useEffect(() => { onOcupado(ocupado); return () => onOcupado(false) }, [ocupado, onOcupado])
  useEffect(() => {
    if (!enviando) return
    const salir = (evento: BeforeUnloadEvent) => { evento.preventDefault(); evento.returnValue = '' }
    window.addEventListener('beforeunload', salir)
    return () => window.removeEventListener('beforeunload', salir)
  }, [enviando])

  useEffect(() => {
    if (!activo || candado.current) return
    const controlador = new AbortController()
    consulta.current?.abort()
    consulta.current = controlador
    setCargando(true)
    setError(null)
    const fechas = JSON.parse(claveFechas) as string[]
    if (!fechas.length) { setCargando(false); return () => controlador.abort() }
    void cargarPlanilla(fechas, controlador.signal).then((nuevos) => {
      if (!controlador.signal.aborted) setDatos(nuevos)
    }).catch((fallo: unknown) => { if (!controlador.signal.aborted) { setDatos(null); setError(mensajeError(fallo)) } })
      .finally(() => { if (!controlador.signal.aborted) setCargando(false) })
    return () => controlador.abort()
  }, [activo, claveFechas, revision, revisionLocal])

  const limpiarPreparacion = useCallback(() => {
    if (Object.keys(borrador).length) setAviso('Se limpiaron las cantidades preparadas al cambiar los filtros. Los repartos confirmados se conservan.')
    setBorrador({}); setPlan(null); setErrorRevision(null); setPaginaDesglose(0)
  }, [borrador])
  const origenesDisponibles = useMemo(() => {
    const presentes = new Set<string>(['landing', 'formulario', 'formulario_3'])
    datos?.cola.forEach((lead) => presentes.add(lead.origen))
    datos?.dias.forEach((dia) => dia.origenes?.forEach((grupo) => presentes.add(grupo.origen)))
    return ORIGENES_LECTURA.filter(({ k }) => presentes.has(k)).map(({ k }) => k)
  }, [datos])
  const origenes = origenFiltro.length ? origenFiltro : origenesDisponibles
  const filasTodas = useMemo(() => datos ? filasPlanilla(datos.supervisores, datos.dias, origenes, []) : [], [datos, origenes])
  const filas = filasTodas.filter((fila) => !supervisorFiltro.length || supervisorFiltro.includes(fila.id))
  const cola = datos && !seleccion.error ? filtrarColaPlanilla(datos.cola, seleccion.ingreso, origenes) : []
  const disponibilidad = Object.fromEntries(origenes.map((origen) => [origen, cola.filter((lead) => lead.origen === origen).length]))
  const cantidadFila = (id: string) => suma(Object.values(borrador[id] ?? {}).map((texto) => /^\d+$/.test(texto ?? '') && Number.isSafeInteger(Number(texto)) ? Number(texto) : 0))
  const totalPreparado = suma(filas.map((fila) => cantidadFila(fila.id)))
  const incluyeHoy = seleccion.reparto.includes(hoyLimaIso())
  let errorPlan: string | null = null
  try { prepararReparto(borrador, cola, filas, origenes) } catch (fallo) { errorPlan = mensajeError(fallo) }

  const desglose = useMemo(() => vista === 'dias' && datos ? datos.dias.flatMap((dia) => filasPlanilla(datos.supervisores, [dia], origenes, supervisorFiltro).map((fila) => ({ ...fila, fecha: dia.fecha }))) : [], [vista, datos, origenes, supervisorFiltro])
  const pagina = paginar(desglose, paginaDesglose)

  async function revisar() {
    if (candado.current || seleccion.error || !totalPreparado) return
    candado.current = true
    consulta.current?.abort()
    setRevisando(true); setErrorRevision(null); setResultado(null)
    const controlador = new AbortController()
    consulta.current = controlador
    try {
      const actual = await cargarPlanilla(seleccion.reparto, controlador.signal)
      if (!montado.current) return
      setDatos(actual)
      if (!actual.repartoLibre) throw new Error('El reparto libre no está habilitado para tu cuenta. Revisa la configuración de reparto con Gerencia.')
      const destinos = filasPlanilla(actual.supervisores, actual.dias, origenes, supervisorFiltro)
      const preparado = prepararReparto(borrador, filtrarColaPlanilla(actual.cola, seleccion.ingreso, origenes), destinos, origenes)
      if (!preparado.length) throw new Error('Prepara al menos una entrega.')
      setFechaPlan(hoyLimaIso()); setPlan(preparado)
    } catch (fallo) { if (montado.current) setErrorRevision(mensajeError(fallo)) }
    finally { candado.current = false; if (montado.current) { setRevisando(false); setCargando(false) } }
  }

  async function confirmar() {
    if (candado.current || !plan) return
    candado.current = true
    consulta.current?.abort()
    detener.current = false
    setEnviando(true); setProgreso(0)
    try {
      const respuesta = await ejecutarReparto(plan, repartirLead, () => hoyLimaIso() !== fechaPlan ? 'Cambió el día en Lima. Revisa un nuevo reparto para continuar; las entregas confirmadas se conservan.' : montado.current && !detener.current, (cantidad) => { if (montado.current) setProgreso(cantidad) })
      // La cola y el historial se releen incluso si la última respuesta fue incierta.
      onCambio()
      if (montado.current) { setResultado(respuesta); setPlan(null); setBorrador({}); setRevisionLocal((n) => n + 1) }
    } finally { candado.current = false; if (montado.current) setEnviando(false) }
  }

  return <Card>
    <SectionHead icon={CalendarDays} title="Coordinación → supervisores" right={<Button variant="outline" disabled={ocupado || cargando} onClick={() => { setPlan(null); setRevisionLocal((n) => n + 1) }}><RefreshCw className="size-3.5" aria-hidden />Actualizar</Button>} />
    <p className="px-5 pb-4 text-xs text-muted-foreground">Combina orígenes para equilibrar las entregas entre supervisores. Preparar cantidades no asigna leads.</p>
    <fieldset disabled={ocupado || plan !== null} className="min-w-0 space-y-4 border-y border-border bg-muted/20 px-5 py-4">
      <div className="grid gap-4 lg:grid-cols-2">
        <PeriodoPlanillaControl etiqueta="Fecha de ingreso al CRM" valor={ingreso} permitirTodas onCambio={(valor) => { limpiarPreparacion(); setIngreso(valor) }} />
        <PeriodoPlanillaControl etiqueta="Fecha de reparto" valor={reparto} onCambio={(valor) => { limpiarPreparacion(); setReparto(valor) }} />
      </div>
      <div className="flex flex-wrap items-start gap-3">
        <details className="rounded-lg border border-input bg-background px-3 py-2 text-xs"><summary className="cursor-pointer font-semibold">{origenFiltro.length ? `${origenFiltro.length} orígenes seleccionados` : 'Todos los orígenes'}</summary>
          <Button variant="ghost" size="sm" onClick={() => { limpiarPreparacion(); setOrigenFiltro([]) }}>Todos los orígenes</Button>
          <div className="flex flex-wrap gap-3">{origenesDisponibles.map((origen) => <label key={origen} className="flex items-center gap-1.5"><input type="checkbox" checked={origenFiltro.includes(origen)} onChange={(e) => { limpiarPreparacion(); setOrigenFiltro(e.target.checked ? [...origenFiltro, origen] : origenFiltro.filter((o) => o !== origen)) }} />{origenLabel(origen)}</label>)}</div>
        </details>
        <details className="rounded-lg border border-input bg-background px-3 py-2 text-xs"><summary className="cursor-pointer font-semibold">{supervisorFiltro.length ? `${supervisorFiltro.length} supervisores seleccionados` : 'Todos los supervisores'}</summary>
          <Button variant="ghost" size="sm" onClick={() => { limpiarPreparacion(); setSupervisorFiltro([]) }}>Todos los supervisores</Button>
          <div className="flex flex-wrap gap-3">{filasTodas.map((fila) => <label key={fila.id} className="flex items-center gap-1.5"><input type="checkbox" checked={supervisorFiltro.includes(fila.id)} onChange={(e) => { limpiarPreparacion(); setSupervisorFiltro(e.target.checked ? [...supervisorFiltro, fila.id] : supervisorFiltro.filter((id) => id !== fila.id)) }} />{fila.nombre}</label>)}</div>
        </details>
        <div className="w-56 max-w-full"><Select aria-label="Vista de entregas" value={vista} onChange={(e) => setVista(e.target.value)}><option value="acumulado">Acumulado del período</option><option value="dias">Desglose por día</option></Select></div>
      </div>
      <p className="text-[11px] text-muted-foreground">Fechas de Lima. Los pendientes aún no tienen supervisor; ese filtro selecciona destinos y sus entregas, no reduce la cola.</p>
    </fieldset>
    <div className="space-y-4 p-5">
      {aviso ? <p role="status" className="text-xs text-muted-foreground">{aviso}</p> : null}
      {seleccion.error || error ? <p role="alert" className="rounded-lg border border-warning/40 bg-warning/5 p-3 text-sm">{seleccion.error || error}</p> : null}
      {resultado ? <div role="status" className="rounded-lg border border-accent/30 bg-accent/5 p-3 text-sm">
        <p className="font-semibold">{resultado.confirmadas.length} entregas confirmadas · {resultado.pendientes} sin intentar{resultado.interrumpida ? resultado.rechazada ? ' · 1 rechazada' : ' · 1 sin confirmar' : ''}</p>
        {resultado.interrumpida ? <p>{resultado.interrumpida.lead.nombre_completo} → {resultado.interrumpida.supervisorNombre}.</p> : null}
        {resultado.error ? <p>{resultado.error}</p> : <p>{cargando ? 'Actualizando cola y entregas…' : error ? 'La entrega se confirmó; falta actualizar los datos.' : 'Cola y entregas actualizadas.'}</p>}
      </div> : null}
      {cargando ? <p role="status" className="py-5 text-sm text-muted-foreground">Consultando pendientes y entregas…</p> : !seleccion.error && datos && !error ? <>
        {!datos.repartoLibre ? <p className="rounded-lg border border-warning/40 p-3 text-sm">El reparto libre no está habilitado para tu cuenta. Puedes consultar las cantidades; Gerencia administra esta opción.</p> : null}
        <div className="flex flex-wrap gap-x-8 gap-y-3 rounded-lg border border-border bg-muted/20 p-3" aria-label="Resumen de la planilla">
          <div><p className="text-xs text-muted-foreground">Pendientes disponibles</p><p className="text-xl font-bold tabular-nums">{cola.length}</p></div>
          <div><p className="text-xs text-muted-foreground">Entregas en el período</p><p className="text-xl font-bold tabular-nums">{suma(filas.map((fila) => fila.recibidos))}</p></div>
          <div><p className="text-xs text-muted-foreground">Preparados para hoy</p><p className="text-xl font-bold tabular-nums">{totalPreparado}</p></div>
          <div><p className="text-xs text-muted-foreground">Pendientes después del plan</p><p className="text-xl font-bold tabular-nums">{errorPlan ? '—' : cola.length - totalPreparado}</p></div>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">{origenes.map((origen) => <span key={origen} className="rounded-md border border-border px-2 py-1">{origenLabel(origen)}: <strong>{disponibilidad[origen]}</strong> disponibles</span>)}</div>
        <p className="text-xs text-muted-foreground">Entregas del {seleccion.reparto[0]} al {seleccion.reparto.at(-1)}{reparto.modo === 'dias' ? ' (solo los días seleccionados)' : ''}. Se cuenta cada entrada a bandeja, aunque luego pase a un analista.</p>
        <fieldset className="min-w-0" disabled={ocupado || !datos.repartoLibre || plan !== null}>
          <TablaEnvoltura ariaLabel="Planilla de reparto">
            <TheadCrm><Th scope="col">Supervisor</Th><Th scope="col" className="text-right">Recibidos</Th>{origenes.map((origen) => <Th scope="col" key={origen}>{origenLabel(origen)} · enviar</Th>)}<Th scope="col" className="text-right">Por enviar</Th><Th scope="col" className="text-right">{incluyeHoy ? 'Total previsto' : 'Histórico consultado'}</Th></TheadCrm>
            <tbody>{filas.map((fila) => <tr key={fila.id} className="border-b border-border/70">
              <Th scope="row" className="text-left text-xs font-semibold">{fila.nombre}{!fila.activo ? <span className="block text-[11px] font-normal text-muted-foreground">Solo histórico</span> : null}</Th>
              <Td className="text-right tabular-nums">{fila.recibidos}</Td>
              {origenes.map((origen) => <Td key={origen}><Input className="min-w-20 max-w-24 text-right tabular-nums" type="number" min="0" step="1" inputMode="numeric" disabled={!fila.activo} aria-label={`Enviar ${origenLabel(origen)} a ${fila.nombre}`} value={borrador[fila.id]?.[origen] ?? ''} placeholder="0" onChange={(e) => { setAviso(''); setErrorRevision(null); setBorrador((actual) => ({ ...actual, [fila.id]: { ...actual[fila.id], [origen]: e.target.value } })) }} /></Td>)}
              <Td className="text-right tabular-nums">{cantidadFila(fila.id)}</Td><Td className="text-right font-semibold tabular-nums">{fila.recibidos + (incluyeHoy ? cantidadFila(fila.id) : 0)}</Td>
            </tr>)}{!filas.length ? <tr><Td colSpan={origenes.length + 4}>No hay supervisores para estos filtros.</Td></tr> : null}</tbody>
            <tfoot><tr className="bg-muted/30 font-semibold"><Th scope="row" className="text-left">Total seleccionado</Th><Td className="text-right">{suma(filas.map((f) => f.recibidos))}</Td>{origenes.map((origen) => <Td key={origen} className="text-right">{suma(filas.map((f) => Number(borrador[f.id]?.[origen]) || 0))}</Td>)}<Td className="text-right">{totalPreparado}</Td><Td className="text-right">{suma(filas.map((f) => f.recibidos)) + (incluyeHoy ? totalPreparado : 0)}</Td></tr></tfoot>
          </TablaEnvoltura>
        </fieldset>
        {!incluyeHoy ? <p className="text-xs text-muted-foreground">Este período no incluye hoy. Las nuevas entregas se registrarán el {hoyLimaIso()} y no se suman al histórico consultado.</p> : null}
        {errorPlan || errorRevision ? <p role="alert" className="text-sm text-warning-text">{errorRevision || errorPlan}</p> : null}
        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border pt-4"><p className="text-xs text-muted-foreground">Se toman los pendientes más antiguos de cada origen, según los filtros de ingreso.</p><div className="flex flex-wrap gap-2"><Button variant="outline" disabled={ocupado || !totalPreparado} onClick={() => { setBorrador({}); setPlan(null); setErrorRevision(null) }}>Limpiar cantidades</Button><Button disabled={ocupado || !datos.repartoLibre || totalPreparado < 1 || !!errorPlan} onClick={() => void revisar()}>{revisando ? 'Revisando…' : 'Revisar reparto'}</Button></div></div>
        {vista === 'dias' ? <><TablaEnvoltura ariaLabel="Entregas por día"><TheadCrm><Th>Fecha de reparto</Th><Th>Supervisor</Th>{origenes.map((origen) => <Th key={origen}>{origenLabel(origen)}</Th>)}<Th>Total</Th></TheadCrm><tbody>{pagina.visibles.map((fila) => <tr key={`${fila.fecha}:${fila.id}`} className="border-b border-border/70"><Td>{fila.fecha}</Td><Td>{fila.nombre}</Td>{origenes.map((origen) => <Td key={origen}>{fila.porOrigen[origen] ?? 0}</Td>)}<Td>{fila.recibidos}</Td></tr>)}</tbody></TablaEnvoltura><Paginacion paginaActual={pagina.paginaActual} paginas={pagina.paginas} total={desglose.length} onCambio={setPaginaDesglose} ariaLabel="Paginación del desglose diario" /></> : null}
      </> : null}
    </div>
    <Dialog open={plan !== null} onClose={() => { if (!enviando) setPlan(null) }} className="w-[760px]">
      <DialogHeader><DialogTitle>Revisar reparto de hoy</DialogTitle><DialogDescription>{plan?.length ?? 0} leads pendientes. Confirma los destinos antes de repartir; no se mueven leads ya asignados.</DialogDescription></DialogHeader>
      <DialogBody><TablaEnvoltura ariaLabel="Leads preparados"><TheadCrm><Th>Lead</Th><Th>Origen</Th><Th>Supervisor destino</Th></TheadCrm><tbody>{plan?.map((entrega) => <tr key={entrega.lead.id} className="border-b border-border/70"><Td>{entrega.lead.nombre_completo}</Td><Td>{origenLabel(entrega.lead.origen)}</Td><Td>{entrega.supervisorNombre}</Td></tr>)}</tbody></TablaEnvoltura>{enviando ? <p role="status" className="mt-3 text-sm">{progreso} de {plan?.length} entregas confirmadas. Espera a que termine el envío.</p> : null}</DialogBody>
      <DialogFooter>{enviando ? <Button variant="outline" onClick={() => { detener.current = true }}>Detener después de la entrega actual</Button> : <Button variant="outline" onClick={() => setPlan(null)}>Volver a editar</Button>}<Button disabled={enviando} onClick={() => void confirmar()}>{enviando ? 'Repartiendo…' : 'Confirmar reparto'}</Button></DialogFooter>
    </Dialog>
  </Card>
}
