import { useCallback, useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { useHistorialTasaCliente } from '@/data/crm-queries'
import { useGestionInversionista, refrescarGestionInversionista, type GestionInversion, type GestionInversionista } from '@/data/gestion-inversionista'
import { useCRMData } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { can } from '@/lib/roles'
import { fechaHora, fmtFecha, money } from '@/lib/format'
import { EMPRESA_NOMBRE } from '@/lib/inversionistas'
import type { ContratoRow } from '@/lib/clientes-tipos'
import { ClienteForm } from './cliente-form'
import { ContratoDetalle } from './contrato-detalle'
import { ContratoCorregir } from './contrato-corregir'
import { CorregirContactoNeutral, CorregirDocumentoNeutral, CorregirInversionCoopac } from './gestion-inversionista-formularios'

type Edicion = null | {tipo:'perfil'; perfil:GestionInversionista['perfiles'][number]}
  | {tipo:'contacto'; datos:GestionInversionista['contacto']}
  | {tipo:'documento'; datos:GestionInversionista['documento']}
  | {tipo:'contrato'; contrato:ContratoRow}
  | {tipo:'coopac'; inversion:GestionInversion & {coopac:NonNullable<GestionInversion['coopac']>}}

function TasasDelContrato({contrato}:{contrato:ContratoRow}) {
  const q=useHistorialTasaCliente(contrato.cliente_id,true)
  const datos=q.isFetchedAfterMount && q.isSuccess ? q.data : null
  if(q.isError)return <PanelError mensaje="No pudimos comprobar las tasas y autorizaciones." reintentando={q.isFetching} onReintentar={()=>void q.refetch()} />
  if(!datos)return <PanelCargando filas={2} />
  const observacion=datos.contratos.find(c=>c.contrato_id===contrato.id)?.observacion
  return <section aria-label="Tasas y autorizaciones" className="space-y-2 rounded-xl border border-border p-3 text-xs">
    <h3 className="font-bold">Tasas y autorizaciones</h3>
    <p>Tasa pactada: {contrato.tasa_anual}% anual.</p>
    {observacion ? <><p>Base de la política al registrar: {observacion.tasa_base}% · Tasa final: {observacion.tasa_final}%.</p>
      {observacion.motivo && <p>{observacion.motivo}</p>}</> : <p className="text-muted-foreground">Sin comparación histórica de tasa registrada.</p>}
    {datos.solicitudes.length===0 ? <p className="text-muted-foreground">Sin solicitudes de tasa visibles para este cliente.</p>
      : <ul className="space-y-2">{datos.solicitudes.map(s=><li key={s.id} className="border-t border-border pt-2">
        <p className="font-semibold">{s.estado.replaceAll('_',' ')} · {s.tasa_solicitada}% solicitada</p>
        <p>{s.motivo}</p>
      </li>)}</ul>}
  </section>
}
function DesgloseInversion({inversion}:{inversion:GestionInversion}) {
  if(!inversion.operaciones.length)return null
  return <section aria-label="Renovaciones y aumentos" className="space-y-3 rounded-xl border border-border p-3 text-xs">
    <h3 className="font-bold">Renovaciones y aumentos</h3>
    {inversion.operaciones.map(o=><div key={o.id} className="space-y-1 border-t border-border pt-2">
      <p className="font-semibold">{o.tipo==='renovacion'?'Renovación':'Aumento'} · {o.numero_origen ?? 'Origen histórico'} → {o.numero_nuevo ?? 'Contrato actual'}</p>
      {!o.desglose_completo ? <p>Desglose histórico pendiente. No se presume capital adicional.</p> : <>
        {o.capital_anterior!==null && <p>Capital del contrato anterior: {money(o.capital_anterior,o.moneda)}</p>}
        {o.capital_renovado!==null && <p>Capital renovado: {money(o.capital_renovado,o.moneda)}</p>}
        {o.capital_adicional!==null && <p>Capital adicional: {money(o.capital_adicional,o.moneda)}</p>}
        <p>{o.elegible_conversion?'Cuenta para conversión según el registro comercial.':'No cuenta como nueva conversión.'}</p>
      </>}
    </div>)}
  </section>
}

export function GestionInversionistaDialogo({actor,persona,fuente=null,onCerrar,onRevocado}:{
  actor:string;persona:string;fuente?:string|null;onCerrar:()=>void;onRevocado:()=>void
}) {
  const {yo}=useAuth()
  const {equipo}=useCRMData()
  const qc=useQueryClient()
  const q=useGestionInversionista(actor,persona,fuente)
  const [edicion,setEdicion]=useState<Edicion>(null)
  const ocupado=useRef(false)
  const notificarEnvio=useCallback((valor:boolean)=>{ocupado.current=valor},[])
  const cerrar=()=>{if(!ocupado.current)onCerrar()}
  const volver=()=>{if(!ocupado.current)setEdicion(null)}
  const alGuardar=()=>{
    ocupado.current=false
    toast.success('Corrección guardada.')
    void refrescarGestionInversionista(qc,actor)
    onCerrar()
  }
  const revocar=useRef(onRevocado);revocar.current=onRevocado
  const revocado=q.error instanceof CrmApiError && ['42501','NO_ENCONTRADO'].includes(q.error.code)
  useEffect(()=>{if(revocado)revocar.current()},[revocado])
  // Las fotos previas solo mantienen el borrador ante una caída; no autorizan
  // escrituras. Una revocación borra el panel y la ficha en el caller.
  const datos=!revocado && q.isFetchedAfterMount ? q.data : null
  const vigente=q.isSuccess && !q.isError && Boolean(datos) && yo?.id===actor
  const i=datos?.inversion
  const analistas=equipo.filter(m=>m.activo).map(m=>({perfil_id:m.perfil_id,nombre_completo:m.nombre_completo}))
  let contenido
  if(!datos) contenido=<><DialogHeader><DialogTitle>{fuente?'Detalle de la inversión':'Datos del cliente'}</DialogTitle></DialogHeader>
    <DialogBody>{q.isError ? <PanelError mensaje={mensajeDeError(q.error,'No pudimos comprobar esta información.')} reintentando={q.isFetching} onReintentar={()=>void q.refetch()} /> : <PanelCargando filas={4} />}</DialogBody>
    <DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button></DialogFooter></>
  else if(edicion?.tipo==='perfil') contenido=<ClienteForm modo="corregir" clienteId={edicion.perfil.id}
    sinLimiteVentana={datos.perfiles.find(p=>p.id===edicion.perfil.id)?.sin_limite===true}
    deshabilitado={!vigente || !datos.perfiles.some(p=>p.id===edicion.perfil.id && p.puede_corregir)}
    onListo={alGuardar} onCerrar={volver} onEnviandoCambio={notificarEnvio} />
  else if(edicion?.tipo==='contacto') contenido=<CorregirContactoNeutral actor={actor} persona={persona} datos={edicion.datos}
    permitido={vigente && datos.contacto.puede_corregir} onCerrar={volver} onGuardado={alGuardar} onEnviando={notificarEnvio} />
  else if(edicion?.tipo==='documento') contenido=<CorregirDocumentoNeutral persona={persona} datos={edicion.datos}
    permitido={vigente && datos.documento.puede_corregir} onCerrar={volver} onGuardado={alGuardar} onEnviando={notificarEnvio} />
  else if(edicion?.tipo==='contrato') contenido=<ContratoCorregir contrato={edicion.contrato} sinLimiteVentana={i?.sin_limite===true}
    deshabilitado={!vigente || !i?.puede_corregir} onGuardado={alGuardar} onCerrar={volver} onEnviandoCambio={notificarEnvio} />
  else if(edicion?.tipo==='coopac') contenido=<CorregirInversionCoopac actor={actor} persona={persona} inversion={edicion.inversion}
    permitido={vigente && i?.puede_corregir===true} onCerrar={volver} onGuardado={alGuardar} onEnviando={notificarEnvio} />
  else if(i?.contrato) contenido=<ContratoDetalle contratoId={i.fuente_id} contratoVigente={i.contrato} onCerrar={cerrar}
    permiteDocumentos={vigente && !can(yo?.rol,'soloLecturaTotal')}
    puedeReasignar={vigente && i.puede_reasignar} analistas={analistas}
    onEnviandoCambio={notificarEnvio} onActualizado={()=>void refrescarGestionInversionista(qc,actor)}
    contenidoAdicional={<>
      <Button variant="outline" disabled={!vigente || !i.puede_corregir} onClick={()=>setEdicion({tipo:'contrato',contrato:i.contrato!})}>Corregir contrato</Button>
      {!i.puede_corregir && <p className="text-xs text-muted-foreground">Corrección bloqueada por el estado, la autoría o la ventana de cinco horas. Administración conserva sus permisos específicos.</p>}
      <TasasDelContrato contrato={i.contrato} /><DesgloseInversion inversion={i} />
    </>} />
  else if(i?.coopac) contenido=<>
    <DialogHeader><DialogTitle>Inversión en {EMPRESA_NOMBRE[i.empresa]}</DialogTitle></DialogHeader>
    <DialogBody className="space-y-3 text-sm">
      <p className="text-xl font-bold">{money(i.coopac.monto,i.coopac.moneda)}</p>
      <dl className="grid grid-cols-2 gap-3 text-xs">
        <div><dt className="text-muted-foreground">Fecha comercial</dt><dd>{fmtFecha(i.coopac.fecha_comercial)}</dd></div>
        <div><dt className="text-muted-foreground">Vencimiento</dt><dd>{fmtFecha(i.coopac.vence_en)}</dd></div>
        <div><dt className="text-muted-foreground">Plazo</dt><dd>{i.coopac.plazo_meses===null?'Sin condición histórica':`${i.coopac.plazo_meses} meses`}</dd></div>
        <div><dt className="text-muted-foreground">Rentabilidad anual</dt><dd>{i.coopac.tasa_anual===null?'Sin condición histórica':`${i.coopac.tasa_anual}%`}</dd></div>
        <div><dt className="text-muted-foreground">Operación</dt><dd>{i.coopac.numero_transaccion}</dd></div>
        <div><dt className="text-muted-foreground">Referencia</dt><dd>{i.coopac.referencia || 'Sin referencia'}</dd></div>
      </dl>
      <div><h3 className="font-semibold">Notas de la operación</h3><p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{i.coopac.nota || 'Sin notas registradas.'}</p></div>
      {i.coopac.anulado_en && <div className="rounded-lg bg-muted p-3"><p>Anulada el {fechaHora(i.coopac.anulado_en)}</p><p>{i.coopac.motivo_anulacion || 'Sin motivo informado'}</p></div>}
      {!i.puede_corregir && <p className="text-xs text-muted-foreground">Solo Gerencia corrige inversiones vigentes de cooperativas.</p>}
    </DialogBody><DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button>
      {yo?.rol==='gerencia' && <Button disabled={!vigente || !i.puede_corregir} onClick={()=>setEdicion({tipo:'coopac',inversion:{...i,coopac:i.coopac!}})}>Corregir inversión</Button>}
    </DialogFooter></>
  else contenido=<>
    <DialogHeader><DialogTitle>Datos y correcciones del cliente</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4 text-sm">
      {datos.perfiles.length ? datos.perfiles.map(p=><section key={p.id} className="space-y-2 rounded-xl border border-border p-3">
        <h3 className="font-semibold">{p.nombre || 'Cliente Avance'}</h3>
        <p className="text-xs text-muted-foreground">Registro original: {fechaHora(p.creado_en)}</p>
        <p>{p.domicilio || 'Sin domicilio registrado.'}</p>
        <Button variant="outline" disabled={!vigente || !p.puede_corregir} onClick={()=>setEdicion({tipo:'perfil',perfil:p})}>Corregir cliente y cuentas bancarias</Button>
        {!p.puede_corregir && <p className="text-xs text-muted-foreground">Corrección bloqueada por permisos o por la ventana de cinco horas.</p>}
      </section>) : <section className="space-y-3">
        <p className="font-semibold">{datos.contacto.nombre_completo}</p><p>{datos.contacto.telefono || 'Sin teléfono.'}</p><p>{datos.contacto.domicilio || 'Sin domicilio registrado.'}</p>
        <Button variant="outline" disabled={!vigente} onClick={()=>setEdicion({tipo:'contacto',datos:datos.contacto})}>Corregir datos de contacto</Button>
        {datos.documento.puede_corregir && <Button variant="outline" disabled={!vigente} onClick={()=>setEdicion({tipo:'documento',datos:datos.documento})}>Corregir documento</Button>}
      </section>}
      <p className="text-xs text-muted-foreground">Documento y correo de acceso mantienen sus autorizaciones administrativas.</p>
    </DialogBody><DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button></DialogFooter></>
  return <Dialog open onClose={cerrar} ariaLabel={fuente?'Detalle y gestión de la inversión':'Datos y correcciones del cliente'} className="w-[620px] max-w-full">
    {datos && q.isError && <div role="status" className="px-5 pt-3 text-sm"><p>No pudimos volver a comprobar los permisos. Conservamos lo escrito; el guardado está bloqueado.</p><Button variant="outline" size="sm" onClick={()=>void q.refetch()}>Reintentar</Button></div>}
    {contenido}
  </Dialog>
}
