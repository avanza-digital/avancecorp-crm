import { PostventaPersona, type ControlesPostventa } from './postventa-persona'
// La ficha neutral comparte la cabecera, las secciones, la banca y el Sheet
// publicados. Una cooperativa nunca se adapta a un perfil ficticio de Avance.
import { useEffect, useId, useRef, useState } from 'react'
import { CalendarClock, ChevronDown, FileText, History, Landmark, UserRound, WalletCards } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SheetBody, SheetFooter } from '@/components/ui/sheet'
import { Paginacion } from '@/components/common/paginacion'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { FichaComercialCabecera, FichaComercialContacto, FichaComercialContinuidad, FichaComercialHistorial, FichaComercialInversion, FichaComercialSeccion, FichaComercialSeccionPlegable } from './ficha-comercial'
import { CuentasClienteMoneda, DatoCliente, DatoClienteCopiable } from './cliente-cuentas-vista'
import { cuentaClienteDesdeRpc } from '@/lib/cliente-cuentas-modelo'
import { useCuentasInversionista, useFichaInversionista } from '@/data/inversionistas-queries'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { EMPRESA_NOMBRE, type FichaInversionista, type InversionFuente, type ResumenEmpresa } from '@/lib/inversionistas'
import type { OperacionInversion } from './inversion-nueva'
import { fechaHora, fmtFecha, money } from '@/lib/format'
import { fechaLima } from '@/lib/agenda-derivada'
import { CATEGORIA_LABEL, ESTADO_COLOR, ESTADO_CONTRATO_LABEL } from '@/lib/contratos-catalogo'
import { ContratoEliminar } from './contrato-eliminar'

export function ResumenEmpresas({totales}: {totales: ResumenEmpresa[]}) {
  return <div className="@container/resumen"><dl className="grid gap-3 @md/resumen:grid-cols-2 @3xl/resumen:grid-cols-3">
    {totales.map(t => <div key={`${t.empresa}:${t.moneda}`} className="min-w-0 border-l-2 border-accent/30 pl-3">
      <dt className="text-xs text-muted-foreground">{EMPRESA_NOMBRE[t.empresa]} · {t.moneda}</dt>
      <dd className="text-lg font-semibold tabular-nums [overflow-wrap:anywhere]">
        {money(t.capital_activo ?? t.capital_registrado, t.moneda)}
      </dd>
      <dd className="text-xs text-muted-foreground">{t.capital_activo !== null ? 'Capital activo' : 'Capital registrado'} · {t.cantidad} {t.cantidad === 1 ? 'inversión' : 'inversiones'}</dd>
    </div>)}
  </dl></div>
}

function CuentasAvance({actor, identidad, perfil, onRevocado}: {
  actor: string; identidad: string; perfil: string; onRevocado: () => void
}) {
  const pen = useCuentasInversionista(actor, identidad, perfil, 'PEN', true)
  const usd = useCuentasInversionista(actor, identidad, perfil, 'USD', true)
  const error = pen.error ?? usd.error
  const revocar = useRef(onRevocado)
  revocar.current = onRevocado
  useEffect(() => {if (error instanceof CrmApiError && error.code === '42501') revocar.current()}, [error])
  if (error) return <PanelError mensaje={mensajeDeError(error, 'No pudimos comprobar las cuentas.')}
    onReintentar={() => {void pen.refetch(); void usd.refetch()}} reintentando={pen.isFetching || usd.isFetching} />
  if (!pen.isFetchedAfterMount || !usd.isFetchedAfterMount || !pen.isSuccess || !usd.isSuccess) return <PanelCargando filas={2} />
  return <div className="space-y-3">
    <CuentasClienteMoneda moneda="PEN" cuentas={pen.data.map(cuentaClienteDesdeRpc)} uso="pagos" />
    <CuentasClienteMoneda moneda="USD" cuentas={usd.data.map(cuentaClienteDesdeRpc)} uso="pagos" />
  </div>
}

function InversionDetalle({inversion, posicion, onDocumento, onOperacion, onRecuperarPdf, postventa, onRetiro, onEliminar}: {
  posicion: number
  postventa?: boolean | undefined
  onRetiro?: ((inversion: InversionFuente) => void) | undefined
  inversion: InversionFuente
  onOperacion?: ((operacion: OperacionInversion) => void) | undefined
  onDocumento?: ((inversion: InversionFuente, documentoId: string) => void) | undefined
  onRecuperarPdf?: ((inversion: InversionFuente) => void) | undefined
  onEliminar?: ((inversion: InversionFuente) => void) | undefined
}) {
  const i = inversion
  const [abierta, setAbierta] = useState(false)
  const detalleId = useId()
  const referenciaAccesible = i.numero || `registro ${posicion} de ${EMPRESA_NOMBRE[i.empresa]} ${i.moneda} en esta página`
  const estadoContrato = Object.hasOwn(ESTADO_CONTRATO_LABEL, i.estado) ? i.estado as keyof typeof ESTADO_CONTRATO_LABEL : null
  const estado = estadoContrato ? ESTADO_CONTRATO_LABEL[estadoContrato] : i.estado === 'vigente' ? 'Vigente'
    : i.estado === 'anulado_comercialmente' ? 'Anulada comercialmente' : i.estado.replaceAll('_', ' ')
  const color = estadoContrato ? ESTADO_COLOR[estadoContrato] : i.estado === 'vigente' ? 'var(--accent)' : 'var(--muted-foreground)'
  return <FichaComercialInversion
    badges={<>
      <Badge color={color} dot>{estado}</Badge>
      {i.contrato?.categoria && <Badge color="var(--chart-4)">{Object.hasOwn(CATEGORIA_LABEL, i.contrato.categoria)
        ? CATEGORIA_LABEL[i.contrato.categoria as keyof typeof CATEGORIA_LABEL] : i.contrato.categoria}</Badge>}
      {i.es_demo && <Badge color="amber">Demostración</Badge>}
      {i.pdf?.reintentable && <Badge color="amber">PDF pendiente</Badge>}
    </>}
    titulo={i.empresa === 'avance' ? 'Inversión Avance' : `Inversión en ${EMPRESA_NOMBRE[i.empresa]}`}
    referencia={<>{i.numero || 'Inversión registrada'} · Vencimiento: {fmtFecha(i.vence_en)}</>}
    capital={money(i.capital, i.moneda)}
    observacion={<>
      {i.estado === 'anulado_comercialmente' && <p className="mt-2 text-xs text-warning-text">Anulación comercial. El capital registrado se conserva.</p>}
      {i.pdf && i.pdf.estado !== 'sellado' && <p className="mt-2 text-xs text-muted-foreground">
        {i.pdf.estado === 'sin_reserva' && !i.pdf.reintentable ? 'Contrato del formato anterior.' : `Documento: ${i.pdf.estado.replaceAll('_', ' ')}.`}
      </p>}
    </>}
    detalle={<div id={detalleId} hidden={!abierta}>
    <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
      <div><dt className="text-muted-foreground">Fecha comercial</dt><dd>{fmtFecha(i.fecha_comercial)}</dd></div>
      <div><dt className="text-muted-foreground">Vencimiento</dt><dd>{fmtFecha(i.vence_en)}</dd></div>
      {i.condiciones_coopac && <>
        <div><dt className="text-muted-foreground">Plazo</dt><dd>{i.condiciones_coopac.plazo_meses} meses</dd></div>
        <div><dt className="text-muted-foreground">Rentabilidad anual</dt><dd>{i.condiciones_coopac.tasa_anual}% anual</dd></div>
      </>}
      {i.contrato && <div><dt className="text-muted-foreground">Rentabilidad anual</dt><dd>{i.contrato.tasa_anual}% · {i.contrato.modalidad}</dd></div>}
      {i.fecha_comercial !== i.fecha_imputacion && <div><dt className="text-muted-foreground">Fecha de imputación</dt><dd>{fmtFecha(i.fecha_imputacion)}</dd></div>}
      <div><dt className="text-muted-foreground">Analista de la operación</dt><dd>{i.analista_origen_nombre || 'Sin información'}</dd></div>
      {i.numero_transaccion && <div><dt className="text-muted-foreground">Depósito</dt><dd>{i.numero_transaccion}</dd></div>}
    </dl>
    {i.proxima_cuota && <p className="mt-3 text-xs">Próxima cuota: {fmtFecha(i.proxima_cuota.fecha)} · {money(i.proxima_cuota.monto, i.proxima_cuota.moneda)}</p>}
    {i.cotitulares.length > 0 && <details className="mt-3 text-xs">
      <summary className="cursor-pointer py-2 font-medium">Titulares del contrato ({i.cotitulares.length})</summary>
      <ul className="space-y-2">{i.cotitulares.map(c => <li key={c.orden}>{c.nombre} · {c.tipo_documento} {c.documento}</li>)}</ul>
    </details>}

    {i.documentos.length > 0 && <div className="mt-3 flex flex-wrap gap-2">{i.documentos.map(d =>
      <Button key={d.id} variant="outline" size="sm" onClick={() => onDocumento?.(i, d.id)} disabled={!onDocumento}>
        <FileText aria-hidden />{d.nombre}
      </Button>)}</div>}
    </div>}
    acciones={<>
      <Button type="button" variant="outline" size="xs" className="min-h-10" aria-expanded={abierta} aria-controls={detalleId}
        aria-label={`${abierta ? 'Ocultar detalle de' : 'Ver inversión'} ${referenciaAccesible}`}
        onClick={() => setAbierta(!abierta)}>
        <ChevronDown aria-hidden className={abierta ? 'rotate-180' : undefined} /> {abierta ? 'Ocultar detalle' : 'Ver inversión'}
      </Button>
      {i.pdf?.reintentable && onRecuperarPdf && <Button variant="outline" size="xs" className="min-h-10" onClick={() => onRecuperarPdf(i)}>Recuperar PDF pendiente</Button>}
      {onEliminar && i.empresa === 'avance' && i.contrato && <>
        <Button variant="destructive" size="xs" className="min-h-10" disabled={i.inversion_id !== null}
          aria-label={`Eliminar contrato ${referenciaAccesible}`} onClick={() => onEliminar(i)}>Eliminar contrato</Button>
        {i.inversion_id !== null && <p className="text-xs text-muted-foreground">Este contrato se conserva en el historial de inversiones y no se puede eliminar.</p>}
      </>}
    {onOperacion && i.empresa === 'avance' && i.contrato && i.perfil_id && <>
      {i.estado === 'activo' && <Button variant="outline" size="xs" className="min-h-10" onClick={() => onOperacion({tipo: 'upgrade', fuente: i})}>Aumentar inversión</Button>}
      {['activo', 'vencido'].includes(i.estado) && i.vence_en && i.vence_en <= fechaLima(Date.now()) && <Button variant="outline" size="xs" className="min-h-10" onClick={() => onOperacion({tipo: 'renovacion', fuente: i})}>Renovar contrato</Button>}
    </>}
    {postventa && i.empresa !== 'avance' && !i.es_demo && ['vigente', 'activo', 'vencido'].includes(i.estado) && <>
      {onOperacion && <Button variant="outline" size="xs" className="min-h-10" onClick={() => onOperacion({tipo: 'reinversion', fuente: i})}>Reinvertir desde esta inversión</Button>}
      {onRetiro && <Button variant="outline" size="xs" className="min-h-10" onClick={() => onRetiro(i)}>Registrar solicitud de retiro</Button>}
    </>}

    </>}
  />
}

export function InversionistaFicha({actor, inversionistaId, onCerrar, onRevocado, onNuevaInversion, onDocumento, onOperacion, onRecuperarPdf, onEliminar, enfocarInversiones = false}: {
  actor: string; inversionistaId: string; onCerrar: () => void; onRevocado: () => void
  enfocarInversiones?: boolean
  onOperacion?: ((operacion: OperacionInversion) => void) | undefined
  onNuevaInversion?: ((ficha: FichaInversionista) => void) | undefined
  onDocumento?: ((inversion: InversionFuente, documentoId: string) => void) | undefined
  onRecuperarPdf?: ((inversion: InversionFuente) => void) | undefined
  onEliminar?: ((inversion: InversionFuente) => Promise<void>) | undefined
}) {
  const [contratoEliminar, setContratoEliminar] = useState<InversionFuente | null>(null)
  const [retiroElegido, setRetiroElegido] = useState<InversionFuente | null>(null)
  const [paginaInversiones, setPaginaInversiones] = useState(1)
  const [paginaHistorial, setPaginaHistorial] = useState(1)
  const [bancaAbierta, setBancaAbierta] = useState(false)
  const inversionesRef = useRef<HTMLElement>(null)
  const focoAplicado = useRef(false)
  const q = useFichaInversionista(actor, inversionistaId, paginaInversiones, paginaHistorial)
  const revocar = useRef(onRevocado)
  revocar.current = onRevocado
  const clave = `${actor}:${inversionistaId}:${paginaInversiones}:${paginaHistorial}`
  const [confirmada, setConfirmada] = useState<{clave: string; ficha: FichaInversionista} | null>(null)
  const accesoRevocado = q.error instanceof CrmApiError && ['42501', 'NO_ENCONTRADO'].includes(q.error.code)
  useEffect(() => {if (accesoRevocado) revocar.current()}, [accesoRevocado])
  useEffect(() => {
    if (q.isFetchedAfterMount && q.isSuccess && q.data) setConfirmada({clave, ficha: q.data})
  }, [clave, q.data, q.isFetchedAfterMount, q.isSuccess])
  // Reutiliza la regla de frescura de Ficha 360: solo una lectura confirmada
  // DURANTE esta apertura puede sobrevivir a un error transitorio. Actor,
  // persona y páginas forman la clave. Una revocación se oculta de inmediato.
  const ficha = accesoRevocado ? null : q.isFetchedAfterMount && q.isSuccess ? q.data
    : q.isError && confirmada?.clave === clave ? confirmada.ficha : null
  const desactualizada = Boolean(ficha && q.isError)
  useEffect(() => {
    if (!onEliminar || desactualizada || accesoRevocado) setContratoEliminar(null)
  }, [onEliminar, desactualizada, accesoRevocado])
  useEffect(() => {
    if (!enfocarInversiones || focoAplicado.current || !ficha) return
    let segundo = 0
    const primero = requestAnimationFrame(() => {
      segundo = requestAnimationFrame(() => {
        inversionesRef.current?.focus({preventScroll: true})
        inversionesRef.current?.scrollIntoView?.({block: 'nearest'})
        focoAplicado.current = true
      })
    })
    return () => {cancelAnimationFrame(primero); cancelAnimationFrame(segundo)}
  }, [enfocarInversiones, ficha])
  if (!ficha) return <>
    <FichaComercialCabecera avatar={<UserRound aria-hidden />} titulo="Ficha del inversionista" onCerrar={onCerrar} />
    <SheetBody>{q.isError
      ? <PanelError mensaje={mensajeDeError(q.error, 'No pudimos cargar la ficha.')}
        onReintentar={() => void q.refetch()} reintentando={q.isFetching} />
      : <PanelCargando filas={5} />}</SheetBody>
  </>
  const p = ficha.persona
  const grupos = new Map<string, InversionFuente[]>()
  for (const i of ficha.inversiones) {
    const k = `${i.empresa}:${i.moneda}`
    grupos.set(k, [...(grupos.get(k) ?? []), i])
  }
  const siguiente = ficha.tareas[0]
  const vencimiento = ficha.continuidad?.proximo_vencimiento
  const pendiente = Boolean(vencimiento && vencimiento <= fechaLima(Date.now()))
  const variasEmpresas = ficha.totales.some(t => t.empresa !== 'avance')
  const soloActivo = ficha.totales.length > 0 && ficha.totales.every(t => t.capital_activo !== null)
  const contenido = ({acciones, agendar, retiros, aviso}: ControlesPostventa) => <>
    <FichaComercialCabecera avatar={<Avatar nombre={p.nombre} className="size-10 max-[359px]:hidden" />} titulo={p.nombre} onCerrar={onCerrar}
      badges={<><Badge color={p.estado === 'activo' ? 'var(--accent)' : 'var(--muted-foreground)'} dot>{p.estado === 'activo' ? 'Cliente activo' : p.estado === 'inactivo' ? 'Cliente inactivo' : p.estado}</Badge>
        <Badge color="var(--primary)">{p.responsable_nombre ? `Analista · ${p.responsable_nombre}` : 'Sin analista asignado'}</Badge>
        {p.no_contactar && <Badge color="amber">No contactar</Badge>}
        {!p.documento_verificado && <Badge color="amber">Documento pendiente</Badge>}</>}
      resumen={<div className="hidden shrink-0 text-right leading-tight sm:block">
        <p className="text-sm font-extrabold tabular-nums text-primary">{ficha.inversiones_total}</p>
        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{ficha.inversiones_total === 1 ? 'inversión registrada' : 'inversiones registradas'}</p>
      </div>}
      acciones={ficha.capacidades.contactar && <FichaComercialContacto nombre={p.nombre}
        telefono={p.telefono} correo={p.correo} habilitado={!desactualizada} />} />
    <SheetBody className="space-y-6">
      <FichaComercialContinuidad items={[
        {etiqueta: variasEmpresas ? 'Capital por empresa' : soloActivo ? 'Capital vigente' : 'Capital registrado',
          contenido: <div className="space-y-2">{ficha.totales.length === 0 && <span className="text-sm font-bold text-muted-foreground">{ficha.inversiones_total === 0 ? 'Sin inversiones registradas' : 'Capital no disponible'}</span>}{ficha.totales.map(t => <div key={`${t.empresa}:${t.moneda}`}>
            <p className="text-sm font-extrabold tabular-nums text-primary">
              {variasEmpresas && <span className="font-medium">{EMPRESA_NOMBRE[t.empresa]} · </span>}{money(t.capital_activo ?? t.capital_registrado, t.moneda)}
            </p><p className="text-[11px] text-muted-foreground">{t.capital_activo !== null ? 'Capital activo' : 'Capital registrado'} · {t.cantidad} {t.cantidad === 1 ? 'inversión' : 'inversiones'}</p>
          </div>)}</div>,
          ayuda: `${ficha.inversiones_total} ${ficha.inversiones_total === 1 ? 'inversión registrada' : 'inversiones registradas'}`},
        {etiqueta: pendiente ? 'Renovación pendiente' : 'Próximo vencimiento',
          contenido: <span className="text-sm font-extrabold">{vencimiento ? fmtFecha(vencimiento) : 'Sin vencimiento próximo'}</span>,
          ayuda: pendiente ? 'Revisa la continuidad de la inversión con el cliente' : 'Anticipa la siguiente renovación'},
        {etiqueta: 'Siguiente contacto',
          contenido: <span className="text-sm font-extrabold">{siguiente ? fechaHora(siguiente.vence_en) : 'Sin contacto programado'}</span>,
          ayuda: siguiente?.titulo ?? 'Agenda una acción para mantener la relación activa'},
      ]} />
      {desactualizada && <div role="status" className="space-y-2 rounded-xl border border-warning/25 bg-warning/5 p-3 text-sm">
        <p>No pudimos actualizar la ficha. Se conservan los últimos datos confirmados.</p>
        <Button variant="outline" size="sm" disabled={q.isFetching} onClick={() => void q.refetch()}>
          {q.isFetching ? 'Actualizando…' : 'Reintentar actualización'}
        </Button>
      </div>}
      {ficha.identidad_fusionada && <p role="status" className="text-xs text-muted-foreground">Esta ficha reúne los antecedentes de la identidad unificada.</p>}
      <FichaComercialSeccion icono={CalendarClock} titulo="Seguimiento" descripcion="Acciones pendientes para mantener activa la relación.">
        {aviso}
        {ficha.tareas.length ? <ol className="space-y-2">{ficha.tareas.slice(0, 3).map(t => <li key={t.id} className="flex items-start gap-3 rounded-xl border border-border bg-muted/20 px-3 py-2.5">
          <span className="mt-0.5 size-2 shrink-0 rounded-full bg-accent" aria-hidden />
          <div className="min-w-0 flex-1"><p className="line-clamp-2 text-xs font-bold text-foreground">{t.titulo}</p><p className="mt-0.5 text-[11px] font-semibold text-muted-foreground">{fechaHora(t.vence_en)}</p></div>
        </li>)}</ol> : <p className="rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">Sin acciones pendientes.</p>}
        {ficha.tareas_total > Math.min(3, ficha.tareas.length) && <p className="text-center text-[11px] font-semibold text-muted-foreground">Y {ficha.tareas_total - Math.min(3, ficha.tareas.length)} seguimientos más en Agenda.</p>}
        {retiros}
      </FichaComercialSeccion>
      <FichaComercialSeccion icono={WalletCards} titulo="Inversiones y contratos"
        sectionRef={inversionesRef}
        descripcion="Capital, vencimientos y oportunidades para renovar o aumentar la inversión."
        accion={onNuevaInversion && <Button size="xs" className="min-h-10" onClick={() => onNuevaInversion(ficha)}
          disabled={desactualizada || !ficha.capacidades.nueva_inversion}>
          {ficha.inversiones_total ? 'Registrar nueva inversión' : 'Registrar primera inversión'}
        </Button>}>
        {onNuevaInversion && !ficha.capacidades.nueva_inversion && <p className="text-xs text-muted-foreground">{ficha.capacidades.motivo_no_operable}</p>}
        <p className="sr-only">{ficha.inversiones_total} {ficha.inversiones_total === 1 ? 'inversión' : 'inversiones'} en esta ficha</p>
        {Array.from(grupos, ([k, inversiones]) => <div key={k} className="space-y-2">
          <h4 className="text-[11px] font-bold text-muted-foreground">{EMPRESA_NOMBRE[inversiones[0]!.empresa]} · {inversiones[0]!.moneda}</h4>
          <ul className="space-y-2" aria-label={`Inversiones ${EMPRESA_NOMBRE[inversiones[0]!.empresa]} ${inversiones[0]!.moneda}`}>
          {inversiones.map((i, posicion) => <li key={i.fuente_id}><InversionDetalle inversion={i} posicion={posicion + 1} postventa={ficha.capacidades.postventa && !desactualizada}
            onRetiro={setRetiroElegido} onDocumento={ficha.capacidades.documentos && !desactualizada ? onDocumento : undefined}
            onRecuperarPdf={!desactualizada ? onRecuperarPdf : undefined}
            onEliminar={!desactualizada && onEliminar ? setContratoEliminar : undefined}
            onOperacion={ficha.capacidades.nueva_inversion && !desactualizada ? onOperacion : undefined} /></li>)}
          </ul>
        </div>)}
        {ficha.inversiones_total === 0 && <p className="rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">Este cliente todavía no tiene una inversión registrada.</p>}
        <Paginacion paginaActual={paginaInversiones - 1} paginas={Math.max(1, Math.ceil(ficha.inversiones_total / 25))}
          total={ficha.inversiones_total} onCambio={n => setPaginaInversiones(n + 1)} ariaLabel="Paginación de inversiones" />
      </FichaComercialSeccion>
      <FichaComercialSeccion icono={UserRound} titulo="Información del cliente" descripcion="Datos para reconocerlo y contactarlo correctamente." accion={acciones}>
        <div className="grid grid-cols-2 gap-3 rounded-xl border border-border bg-muted/20 p-3 sm:grid-cols-3">
          <DatoCliente etiqueta="Nombres y apellidos">{p.nombre}</DatoCliente>
          <DatoCliente etiqueta={p.documento_tipo || 'Documento'}>{p.documento || 'Pendiente de completar'}</DatoCliente>
          <DatoCliente etiqueta="Responsable actual">{p.responsable_nombre || 'Sin responsable'}</DatoCliente>
          <DatoCliente etiqueta="Teléfono">{p.telefono || 'Sin teléfono'}</DatoCliente>
          <DatoClienteCopiable etiqueta="Correo" valor={p.correo} className="col-span-2" />
          <DatoCliente etiqueta="Registrado el">{fechaHora(p.creado_en)}</DatoCliente>
        </div>
      </FichaComercialSeccion>
      <FichaComercialSeccion icono={History} titulo="Historial de gestiones" descripcion="Contactos, cambios de analista y movimientos de inversión para retomar la relación con contexto.">
        {ficha.historial.length > 0 && <FichaComercialHistorial eventos={ficha.historial.map(h => ({
          id: `${h.origen}:${h.id}`, titulo: h.tipo.charAt(0).toUpperCase() + h.tipo.slice(1).replaceAll('_', ' '),
          detalle: h.detalle, creadoEn: h.creado_en,
          contexto: `${h.origen === 'lead' ? 'Captación' : h.origen === 'postventa' ? 'Postventa' : 'Cliente Avance'}${h.empresa ? ` · ${EMPRESA_NOMBRE[h.empresa]}` : ''}`,
        }))} />}
        {ficha.historial_total === 0 && <p className="rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">Aún no hay gestiones registradas. Los contactos y movimientos de inversión aparecerán aquí.</p>}
        <Paginacion paginaActual={paginaHistorial - 1} paginas={Math.max(1, Math.ceil(ficha.historial_total / 25))}
          total={ficha.historial_total} onCambio={n => setPaginaHistorial(n + 1)} ariaLabel="Paginación del historial" />
      </FichaComercialSeccion>
      {ficha.capacidades.cuentas_perfil_ids.length > 0 && <FichaComercialSeccionPlegable icono={Landmark}
        titulo="Cuentas para recibir pagos" resumen="Cuentas autorizadas para los contratos Avance"
        abierta={bancaAbierta} onAbiertaChange={setBancaAbierta}>
        {bancaAbierta && ficha.capacidades.cuentas_perfil_ids.map(perfil => <CuentasAvance
          key={`${perfil}:${p.responsable_id}`} actor={actor}
          identidad={p.inversionista_id} perfil={perfil} onRevocado={onRevocado} />)}
      </FichaComercialSeccionPlegable>}
    </SheetBody>
    <SheetFooter className="justify-between"><Button variant="outline" className="min-h-11" onClick={onCerrar}>Cerrar</Button>{agendar}</SheetFooter>
    {contratoEliminar && onEliminar && !desactualizada && <ContratoEliminar
      key={contratoEliminar.fuente_id} inversion={contratoEliminar} onConfirmar={onEliminar}
      onCerrar={() => setContratoEliminar(null)} />}
  </>
  return <PostventaPersona actor={actor} ficha={ficha} retiroElegido={retiroElegido}
    deshabilitado={desactualizada} onRetiroCerrado={() => setRetiroElegido(null)}>{contenido}</PostventaPersona>
}
