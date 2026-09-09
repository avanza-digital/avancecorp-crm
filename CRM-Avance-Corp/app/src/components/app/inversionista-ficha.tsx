// La ficha neutral comparte la cabecera, las secciones, la banca y el Sheet
// publicados. Una cooperativa nunca se adapta a un perfil ficticio de Avance.
import { useEffect, useRef, useState } from 'react'
import { CalendarClock, FileText, History, Landmark, Mail, Phone, Plus, UserRound, WalletCards } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SheetBody, SheetFooter } from '@/components/ui/sheet'
import { Paginacion } from '@/components/common/paginacion'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { FichaComercialCabecera, FichaComercialSeccion, FichaComercialSeccionPlegable } from './ficha-comercial'
import { CuentasClienteMoneda, DatoCliente } from './cliente-cuentas-vista'
import { cuentaClienteDesdeRpc } from '@/lib/cliente-cuentas-modelo'
import { useCuentasInversionista, useFichaInversionista } from '@/data/inversionistas-queries'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { EMPRESA_NOMBRE, type FichaInversionista, type InversionFuente, type ResumenEmpresa } from '@/lib/inversionistas'
import type { OperacionInversion } from './inversion-nueva'
import { fechaHora, fmtFecha, money } from '@/lib/format'
import { fechaLima } from '@/lib/agenda-derivada'

export function ResumenEmpresas({totales}: {totales: ResumenEmpresa[]}) {
  return <div className="@container/resumen"><dl className="grid gap-3 @md/resumen:grid-cols-2 @3xl/resumen:grid-cols-3">
    {totales.map(t => <div key={`${t.empresa}:${t.moneda}`} className="min-w-0 border-l-2 border-accent/30 pl-3">
      <dt className="text-xs text-muted-foreground">{EMPRESA_NOMBRE[t.empresa]} · {t.moneda}</dt>
      <dd className="text-lg font-semibold tabular-nums [overflow-wrap:anywhere]">
        {money(t.capital_activo ?? t.capital_registrado, t.moneda)}
      </dd>
      <dd className="text-xs text-muted-foreground">{t.empresa === 'avance' ? 'Capital activo' : 'Capital registrado'} · {t.cantidad} {t.cantidad === 1 ? 'inversión' : 'inversiones'}</dd>
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

function InversionDetalle({inversion, onDocumento, onOperacion, onRecuperarPdf}: {
  inversion: InversionFuente
  onOperacion?: ((operacion: OperacionInversion) => void) | undefined
  onDocumento?: ((inversion: InversionFuente, documentoId: string) => void) | undefined
  onRecuperarPdf?: ((inversion: InversionFuente) => void) | undefined
}) {
  const i = inversion
  return <article className="min-w-0 rounded-lg border border-border bg-card p-3 [overflow-wrap:anywhere]">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div><p className="text-sm font-semibold">{i.numero || 'Inversión registrada'}</p>
        <p className="text-xs text-muted-foreground">{i.estado.replaceAll('_', ' ')}</p></div>
      <p className="text-base font-semibold tabular-nums">{money(i.capital, i.moneda)}</p>
    </div>
    {i.es_demo && <Badge color="amber">Demostración</Badge>}
    <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
      <div><dt className="text-muted-foreground">Fecha comercial</dt><dd>{fmtFecha(i.fecha_comercial)}</dd></div>
      <div><dt className="text-muted-foreground">Vencimiento</dt><dd>{fmtFecha(i.vence_en)}</dd></div>
      {i.fecha_comercial !== i.fecha_imputacion && <div><dt className="text-muted-foreground">Fecha de imputación</dt><dd>{fmtFecha(i.fecha_imputacion)}</dd></div>}
      <div><dt className="text-muted-foreground">Analista de la operación</dt><dd>{i.analista_origen_nombre || 'Sin información'}</dd></div>
      {i.numero_transaccion && <div><dt className="text-muted-foreground">Depósito</dt><dd>{i.numero_transaccion}</dd></div>}
    </dl>
    {i.proxima_cuota && <p className="mt-3 text-xs">Próxima cuota: {fmtFecha(i.proxima_cuota.fecha)} · {money(i.proxima_cuota.monto, i.proxima_cuota.moneda)}</p>}
    {i.estado === 'anulado_comercialmente' && <p className="mt-2 text-xs text-warning-text">Anulación comercial. El capital registrado se conserva.</p>}
    {i.cotitulares.length > 0 && <details className="mt-3 text-xs">
      <summary className="cursor-pointer py-2 font-medium">Titulares del contrato ({i.cotitulares.length})</summary>
      <ul className="space-y-2">{i.cotitulares.map(c => <li key={c.orden}>{c.nombre} · {c.tipo_documento} {c.documento}</li>)}</ul>
    </details>}
    {i.pdf && i.pdf.estado !== 'sellado' && <p className="mt-2 text-xs text-muted-foreground">
      {i.pdf.estado === 'sin_reserva' && !i.pdf.reintentable ? 'Contrato del formato anterior.' : `Documento: ${i.pdf.estado.replaceAll('_', ' ')}.`}
    </p>}
    {i.pdf?.reintentable && onRecuperarPdf && <Button variant="outline" size="sm" className="mt-2" onClick={() => onRecuperarPdf(i)}>Recuperar PDF pendiente</Button>}
    {onOperacion && i.empresa === 'avance' && i.contrato && i.perfil_id && <div className="mt-3 flex flex-wrap gap-2">
      {i.estado === 'activo' && <Button variant="outline" size="sm" onClick={() => onOperacion({tipo: 'upgrade', fuente: i})}>Aumentar inversión</Button>}
      {['activo', 'vencido'].includes(i.estado) && i.vence_en && i.vence_en <= fechaLima(Date.now()) && <Button variant="outline" size="sm" onClick={() => onOperacion({tipo: 'renovacion', fuente: i})}>Renovar contrato</Button>}
    </div>}
    {i.documentos.length > 0 && <div className="mt-3 flex flex-wrap gap-2">{i.documentos.map(d =>
      <Button key={d.id} variant="outline" size="sm" onClick={() => onDocumento?.(i, d.id)} disabled={!onDocumento}>
        <FileText aria-hidden />{d.nombre}
      </Button>)}</div>}
  </article>
}

export function InversionistaFicha({actor, inversionistaId, onCerrar, onRevocado, onNuevaInversion, onDocumento, onOperacion, onRecuperarPdf}: {
  actor: string; inversionistaId: string; onCerrar: () => void; onRevocado: () => void
  onOperacion?: ((operacion: OperacionInversion) => void) | undefined
  onNuevaInversion?: ((ficha: FichaInversionista) => void) | undefined
  onDocumento?: ((inversion: InversionFuente, documentoId: string) => void) | undefined
  onRecuperarPdf?: ((inversion: InversionFuente) => void) | undefined
}) {
  const [paginaInversiones, setPaginaInversiones] = useState(1)
  const [paginaHistorial, setPaginaHistorial] = useState(1)
  const [bancaAbierta, setBancaAbierta] = useState(false)
  const [historialAbierto, setHistorialAbierto] = useState(false)
  const q = useFichaInversionista(actor, inversionistaId, paginaInversiones, paginaHistorial)
  const revocar = useRef(onRevocado)
  revocar.current = onRevocado
  useEffect(() => {if (q.error instanceof CrmApiError && q.error.code === '42501') revocar.current()}, [q.error])
  // Nunca pintar identidad, banca o acciones desde una fotografía de la lista.
  const ficha = q.isFetchedAfterMount && q.isSuccess ? q.data : null
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
  return <>
    <FichaComercialCabecera avatar={<Avatar nombre={p.nombre} />} titulo={p.nombre} onCerrar={onCerrar}
      badges={<><Badge>{p.estado === 'activo' ? 'En gestión' : p.estado}</Badge>
        {p.no_contactar && <Badge color="amber">No contactar</Badge>}
        {!p.documento_verificado && <Badge color="amber">Documento pendiente</Badge>}</>}
      acciones={onNuevaInversion && <div className="space-y-1">
        <Button onClick={() => onNuevaInversion(ficha)} disabled={!ficha.capacidades.nueva_inversion}><Plus aria-hidden />Nueva inversión</Button>
        {!ficha.capacidades.nueva_inversion && <p className="text-xs text-muted-foreground">{ficha.capacidades.motivo_no_operable}</p>}
      </div>} />
    <SheetBody className="space-y-6">
      {ficha.identidad_fusionada && <p role="status" className="text-xs text-muted-foreground">Esta ficha reúne los antecedentes de la identidad unificada.</p>}
      <FichaComercialSeccion icono={UserRound} titulo="Identidad y responsable">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <DatoCliente etiqueta={p.documento_tipo || 'Documento'}>{p.documento || 'Pendiente de completar'}</DatoCliente>
          <DatoCliente etiqueta="Responsable actual">{p.responsable_nombre || 'Sin responsable'}</DatoCliente>
          <DatoCliente etiqueta="Teléfono">{p.telefono || 'Sin teléfono'}</DatoCliente>
          <DatoCliente etiqueta="Correo">{p.correo || 'Sin correo'}</DatoCliente>
        </div>
        {ficha.capacidades.contactar && <div className="flex flex-wrap gap-2">
          {p.telefono && <a className="inline-flex min-h-10 items-center gap-2 text-sm text-accent underline" href={`tel:${p.telefono.replace(/[^+0-9]/g, '')}`}><Phone className="size-4" aria-hidden />Llamar</a>}
          {p.correo && <a className="inline-flex min-h-10 items-center gap-2 text-sm text-accent underline" href={`mailto:${encodeURIComponent(p.correo)}`}><Mail className="size-4" aria-hidden />Escribir</a>}
        </div>}
      </FichaComercialSeccion>
      <FichaComercialSeccion icono={CalendarClock} titulo="Próximas tareas">
        {ficha.tareas.length ? <ul className="space-y-2">{ficha.tareas.map(t => <li key={t.id} className="text-sm [overflow-wrap:anywhere]">
          <p className="font-medium">{t.titulo}</p><p className="text-xs text-muted-foreground">{fechaHora(t.vence_en)}</p>
        </li>)}</ul> : <p className="text-sm text-muted-foreground">No hay tareas pendientes.</p>}
        {ficha.tareas_total > ficha.tareas.length && <p className="text-xs text-muted-foreground">Mostrando {ficha.tareas.length} de {ficha.tareas_total}. Consulta la agenda para ver las demás.</p>}
      </FichaComercialSeccion>
      <FichaComercialSeccion icono={WalletCards} titulo="Inversiones" descripcion={`${ficha.inversiones_total} ${ficha.inversiones_total === 1 ? 'inversión' : 'inversiones'} en esta ficha`}>
        <ResumenEmpresas totales={ficha.totales} />
        {Array.from(grupos, ([k, inversiones]) => <div key={k} className="space-y-2">
          <h4 className="text-sm font-semibold">{EMPRESA_NOMBRE[inversiones[0]!.empresa]} · {inversiones[0]!.moneda}</h4>
          {inversiones.map(i => <InversionDetalle key={i.fuente_id} inversion={i} onDocumento={onDocumento} onRecuperarPdf={onRecuperarPdf} onOperacion={ficha.capacidades.nueva_inversion ? onOperacion : undefined} />)}
        </div>)}
        {ficha.inversiones_total === 0 && <p className="text-sm text-muted-foreground">Todavía no registra inversiones.</p>}
        <Paginacion paginaActual={paginaInversiones - 1} paginas={Math.max(1, Math.ceil(ficha.inversiones_total / 25))}
          total={ficha.inversiones_total} onCambio={n => setPaginaInversiones(n + 1)} ariaLabel="Paginación de inversiones" />
      </FichaComercialSeccion>
      {ficha.capacidades.cuentas_perfil_ids.length > 0 && <FichaComercialSeccionPlegable icono={Landmark}
        titulo="Cuentas de pago Avance" resumen="Cuentas autorizadas para los contratos Avance"
        abierta={bancaAbierta} onAbiertaChange={setBancaAbierta}>
        {bancaAbierta && ficha.capacidades.cuentas_perfil_ids.map(perfil => <CuentasAvance
          key={`${perfil}:${p.responsable_id}`} actor={actor}
          identidad={p.inversionista_id} perfil={perfil} onRevocado={onRevocado} />)}
      </FichaComercialSeccionPlegable>}
      <FichaComercialSeccionPlegable icono={History} titulo="Historial" resumen={`${ficha.historial_total} actividades registradas`}
        abierta={historialAbierto} onAbiertaChange={setHistorialAbierto}>
        <ul className="space-y-3">{ficha.historial.map(h => <li key={`${h.origen}:${h.id}`} className="text-sm [overflow-wrap:anywhere]">
          <p className="font-medium">{h.tipo.replaceAll('_', ' ')}</p><p>{h.detalle}</p>
          <p className="text-xs text-muted-foreground">{fechaHora(h.creado_en)}</p>
        </li>)}</ul>
        {ficha.historial_total === 0 && <p className="text-sm text-muted-foreground">Sin actividades registradas.</p>}
        <Paginacion paginaActual={paginaHistorial - 1} paginas={Math.max(1, Math.ceil(ficha.historial_total / 25))}
          total={ficha.historial_total} onCambio={n => setPaginaHistorial(n + 1)} ariaLabel="Paginación del historial" />
      </FichaComercialSeccionPlegable>
    </SheetBody>
    <SheetFooter><Button variant="outline" onClick={onCerrar}>Cerrar ficha</Button></SheetFooter>
  </>
}
