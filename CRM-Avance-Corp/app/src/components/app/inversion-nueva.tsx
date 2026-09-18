import { useEffect, useRef, useState, type FormEvent } from 'react'
import { CheckCircle2, Landmark } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { ContratoNuevo } from './contrato-nuevo'
import { CondicionesCoopac } from './condiciones-coopac'
import { condicionesCoopac, type CampoCondicionesCoopac } from '@/lib/coopac-condiciones'
import { fechaLima } from '@/lib/agenda-derivada'
import { useFichaInversionista } from '@/data/inversionistas-queries'
import { descargarDocumentoInversionista } from '@/data/inversionistas-api'
import { CrmApiError, mensajeDeError, prepararPayloadContrato, type CrearContratoInput } from '@/data/crm-api'
import { completarAccesoInversion, confirmarSolicitudInversion, consultarSolicitudInversion, corregirSolicitudInversion,
  prepararSolicitudInversion, revisarResponsableInversion, subirComprobanteInversion } from '@/data/inversion-solicitud-api'
import { contratoDeSolicitud, datosAvanceRevisados, guardarIntentoInversion, leerIntentoInversion,
  limpiarIntentosInversion, nuevoIntentoInversion, mismoContenidoInversion, type ConfirmacionInversion, type DatosInversion,
  type IntentoInversion, type SolicitudInversion } from '@/lib/inversion-solicitud'
import { EMPRESAS_INVERSION, EMPRESA_NOMBRE, type EmpresaInversion, type InversionFuente } from '@/lib/inversionistas'
import { validarDomicilioLegal } from '@/lib/cliente-form-logica'
import { parseMonto, ERROR_MONTO } from '@/lib/numero'
import { fmtFecha, money, type Moneda } from '@/lib/format'
import { INFO_COOPERATIVA, monedaPorDefecto, pideMoneda, type Cooperativa } from '@/lib/cierres-externos'
import { type CuotaCronograma } from '@/lib/cronograma'
import { archivarContratoPdfConfirmado } from '@/lib/contrato-pdf-archivo'

export interface OperacionInversion {tipo: 'upgrade' | 'renovacion' | 'reinversion'; fuente: InversionFuente}
type AltaPortal = NonNullable<DatosInversion['alta_portal']>
const mensajeRecuperacion = 'La solicitud sigue guardada en esta sesión. Consulta su estado antes de volver a enviarla.'

export function InversionNueva({actor, persona, operacion, onCerrar, onRevocado, onConfirmada}: {
  actor: string; persona: string; operacion?: OperacionInversion | undefined
  onCerrar: () => void; onRevocado: () => void; onConfirmada: () => void
}) {
  const [guardado, setGuardado] = useState(() => {
    try {return {intento: leerIntentoInversion(actor, persona), error: null}}
    catch (e) {return {intento: null, error: mensajeDeError(e, 'No se pudo recuperar la solicitud.')}}
  })
  const [intento, setIntento] = useState<IntentoInversion | null>(guardado.intento)
  const [solicitud, setSolicitud] = useState<SolicitudInversion | null>(null)
  const [empresa, setEmpresa] = useState<EmpresaInversion | null>(guardado.intento?.datos.empresa ?? (operacion?.fuente.empresa ?? null))
  const [error, setError] = useState<string | null>(guardado.error)
  const [ocupado, setOcupado] = useState(false)
  const [recuperando, setRecuperando] = useState(guardado.intento !== null)
  const [editar, setEditar] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [archivo, setArchivo] = useState<File | null>(null)
  const [confirmacion, setConfirmacion] = useState<ConfirmacionInversion | null>(null)
  const [perfilCreado, setPerfilCreado] = useState<string | null>(null)
  const [referencia, setReferencia] = useState('')
  const cerro = useRef(false)
  const enCurso = useRef(false)
  const descargaPdf = useRef<AbortController | null>(null)
  const callbacks = useRef({onRevocado, onConfirmada})
  callbacks.current = {onRevocado, onConfirmada}
  const fichaQ = useFichaInversionista(actor, persona, 1, 1)
  const ficha = fichaQ.isFetchedAfterMount && fichaQ.isSuccess ? fichaQ.data : null
  const guardar = (i: IntentoInversion) => {guardarIntentoInversion(i); setIntento(i)}
  const recibir = (s: SolicitudInversion) => {
    if (cerro.current) return
    setSolicitud(s)
    if (s.estado === 'confirmada' && s.resultado) {setConfirmacion(s.resultado); callbacks.current.onConfirmada()}
  }
  useEffect(() => {
    cerro.current = false
    const abort = new AbortController()
    if (guardado.intento) void consultarSolicitudInversion(guardado.intento.clave, abort.signal)
      .then(s => {
        if (!abort.signal.aborted) {
          setSolicitud(s)
          if (s.estado === 'confirmada' && s.resultado) {setConfirmacion(s.resultado); callbacks.current.onConfirmada()}
        }
      }).catch(e => {
        if (abort.signal.aborted) return
        if (e instanceof CrmApiError && e.code === '42501') callbacks.current.onRevocado()
        else setError(mensajeDeError(e, mensajeRecuperacion))
      }).finally(() => {if (!abort.signal.aborted) setRecuperando(false)})
    return () => {cerro.current = true; abort.abort(); descargaPdf.current?.abort()}
  }, [guardado.intento])
  useEffect(() => {
    if (fichaQ.error instanceof CrmApiError && fichaQ.error.code === '42501') callbacks.current.onRevocado()
    else if (fichaQ.isFetchedAfterMount && fichaQ.isSuccess && !fichaQ.data) callbacks.current.onRevocado()
  }, [fichaQ.error, fichaQ.isFetchedAfterMount, fichaQ.isSuccess, fichaQ.data])
  async function ejecutar(trabajo: () => Promise<void>) {
    if (enCurso.current) return
    enCurso.current = true; setOcupado(true); setError(null)
    try {await trabajo()}
    catch (e) {
      if (cerro.current) return
      if (e instanceof CrmApiError && e.code === '42501') callbacks.current.onRevocado()
      else setError(mensajeDeError(e, mensajeRecuperacion))
    } finally {enCurso.current = false; if (!cerro.current) setOcupado(false)}
  }
  async function preparar(datos: DatosInversion, claveSolicitud: string = crypto.randomUUID()) {
    const i = nuevoIntentoInversion(actor, persona, claveSolicitud, datos, operacion?.tipo === 'reinversion' ? operacion.fuente.fuente_id : undefined)
    // Si el navegador no permite guardar la recuperación, no enviamos el alta.
    guardar(i)
    recibir(await prepararSolicitudInversion(i))
  }
  async function revisarDatos(datos: DatosInversion) {
    if (!intento) {await preparar(datos); return}
    if (!solicitud?.datos) throw new Error('Consulta primero la solicitud pendiente.')
    if (mismoContenidoInversion(datos, solicitud.datos)) {setEditar(false); return}
    const motivoEfectivo = solicitud.datos.empresa === 'avance' && !solicitud.datos.contrato?.capital
      ? 'Completar condiciones contractuales después de preparar el acceso Avance' : motivo.trim()
    if (motivoEfectivo.length < 10) throw new Error('Indica un motivo de al menos 10 caracteres, sin datos personales.')
    const i = {...intento, correccion: {clave: crypto.randomUUID(), revision: solicitud.revision_datos, datos, motivo: motivoEfectivo}}
    guardar(i)
    recibir(await corregirSolicitudInversion(i))
    const limpio: IntentoInversion = {...i}; delete limpio.correccion; guardar(limpio)
    setEditar(false); setMotivo('')
  }
  const datos = solicitud?.datos ?? intento?.datos
  const perfil = operacion?.fuente.perfil_id ?? ficha?.persona.perfil_id ?? perfilCreado
  const base: DatosInversion = datos ?? {inversionista_id: ficha?.persona.inversionista_id ?? persona, empresa: empresa ?? 'avance'}
  const puedeOperar = ficha?.capacidades.nueva_inversion === true
  const cerrar = () => {
    if (enCurso.current) return
    if (confirmacion) limpiarIntentosInversion(actor, persona)
    onCerrar()
  }
  const origenReinversion = solicitud?.reinversion_origen_id ?? intento?.reinversion_origen_id ?? (operacion?.tipo === 'reinversion' ? operacion.fuente.fuente_id : null)
  const cabecera = (titulo: string) => <DialogHeader><DialogTitle>{titulo}</DialogTitle>
    {ficha && <p className="text-sm text-muted-foreground [overflow-wrap:anywhere]">{ficha.persona.nombre}</p>}
    {origenReinversion && <p className="text-sm text-muted-foreground">Reinversión vinculada a una inversión anterior{operacion?.fuente.numero ? ` · ${operacion.fuente.numero}` : ''}. Su registro original se conserva.</p>}</DialogHeader>
  const alerta = error && <p role="alert" className="rounded-xl border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive-text [overflow-wrap:anywhere]">{error}</p>
  let cuerpo
  if (!ficha || recuperando) cuerpo = <>{cabecera('Nueva inversión')}<DialogBody>
    {fichaQ.isError ? <PanelError mensaje={mensajeDeError(fichaQ.error, 'No se pudo verificar el acceso.')}
      onReintentar={() => void fichaQ.refetch()} reintentando={fichaQ.isFetching} /> : <PanelCargando />}
  </DialogBody></>
  else if (confirmacion) cuerpo = <>{cabecera('Inversión confirmada')}<DialogBody className="space-y-4">
    <p role="status" className="flex items-center gap-2 font-medium"><CheckCircle2 aria-hidden />La inversión quedó registrada en {EMPRESA_NOMBRE[confirmacion.empresa]}.</p>
    {confirmacion.fuente.numero_contrato && <p>Contrato {confirmacion.fuente.numero_contrato}</p>}
    <p className="text-sm text-muted-foreground">La ficha consultará el saldo y los antecedentes actualizados.</p>
    {confirmacion.empresa === 'avance' && confirmacion.fuente.id && <Button variant="outline" disabled={ocupado} onClick={() => void ejecutar(async () => {
      const abort = new AbortController(); descargaPdf.current?.abort(); descargaPdf.current = abort
      await archivarContratoPdfConfirmado(confirmacion.fuente.id!)
      if (!cerro.current) await descargarDocumentoInversionista(persona, confirmacion.fuente.id!, confirmacion.fuente.id!, abort.signal)
    })}>Preparar / descargar PDF</Button>}
    {alerta}
  </DialogBody></>
  else if (!puedeOperar) cuerpo = <>{cabecera('Nueva inversión')}<DialogBody><p role="status">{ficha.capacidades.motivo_no_operable ?? 'La persona ya no permite nuevas inversiones.'}</p></DialogBody></>
  else if (guardado.error || !empresa) cuerpo = <>{cabecera(guardado.error ? 'Recuperar solicitud' : 'Nueva inversión')}<DialogBody className="space-y-5">
    {guardado.error ? <div className="space-y-3">
      <p className="text-sm">El borrador local no se puede leer. Puedes consultar la solicitud por su referencia.</p>
      <Button variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal" onClick={() => {
        limpiarIntentosInversion(actor, persona); setGuardado({intento: null, error: null}); setError(null); setEmpresa(null)
      }}>Descartar el borrador local ilegible</Button>
      <p className="text-xs text-muted-foreground">Descartarlo no cancela una solicitud que ya esté registrada en el servidor.</p>
    </div> : <><p className="text-sm">Elige la empresa en la que invertirá.</p>
      <div className="grid gap-3 sm:grid-cols-3">{EMPRESAS_INVERSION.map(e => <Button key={e} variant="outline" className="h-20 flex-col" onClick={() => setEmpresa(e)}><Landmark aria-hidden />{EMPRESA_NOMBRE[e]}</Button>)}</div></>}
    <form onSubmit={e => {e.preventDefault(); void ejecutar(async () => {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(referencia)) throw new Error('Introduce la referencia completa de la solicitud.')
      const s = await consultarSolicitudInversion(referencia)
      if (s.inversionista_id !== ficha.persona.inversionista_id || !s.datos) throw new Error('La solicitud no corresponde a esta ficha.')
      const i = nuevoIntentoInversion(actor, persona, s.solicitud_id, s.datos, s.reinversion_origen_id)
      guardar(i); setGuardado({intento: null, error: null}); setEmpresa(s.datos.empresa); recibir(s)
    })}} className="space-y-2 border-t border-border pt-4">
      <Label htmlFor="f5-referencia">Retomar una solicitud por su referencia</Label>
      <Input id="f5-referencia" value={referencia} onChange={e => setReferencia(e.target.value.trim())} autoComplete="off" />
      <Button type="submit" variant="outline" disabled={ocupado || !referencia}>Consultar solicitud</Button>
    </form>{alerta}
  </DialogBody></>
  else if (intento && !solicitud) cuerpo = <>{cabecera('Recuperar solicitud')}<DialogBody className="space-y-4">
    <p className="text-sm">{mensajeRecuperacion}</p>{alerta}
    <Button disabled={ocupado} onClick={() => void ejecutar(async () => {
      try {recibir(await consultarSolicitudInversion(intento.clave))}
      catch (e) {
        if (e instanceof CrmApiError && e.code === 'P0002') recibir(await prepararSolicitudInversion(intento))
        else throw e
      }
    })}>Consultar y recuperar</Button>
  </DialogBody></>
  else if (solicitud?.estado === 'cancelada') cuerpo = <>{cabecera('Solicitud cancelada')}<DialogBody><p>Esta solicitud está cancelada.</p>
    <Button variant="outline" onClick={() => {limpiarIntentosInversion(actor, persona); setIntento(null); setSolicitud(null); setEmpresa(null)}}>Iniciar otra inversión</Button></DialogBody></>
  else if (solicitud?.requiere_revision_responsable) cuerpo = <>{cabecera('Revisar responsable')}<DialogBody className="space-y-3">
    <p>El responsable cambió. Revisa la misma solicitud antes de continuar.</p>
    <p className="font-medium">Responsable actual: {ficha.persona.responsable_nombre ?? 'Sin responsable'}</p>
    <Label htmlFor="f5-motivo-responsable">Motivo de la revisión, sin datos personales</Label>
    <Input id="f5-motivo-responsable" value={motivo} onChange={e => setMotivo(e.target.value)} minLength={10} maxLength={500} />
    <Button disabled={ocupado || motivo.trim().length < 10 || !solicitud.responsable_actual_id} onClick={() => void ejecutar(async () => {
      recibir(await revisarResponsableInversion(solicitud.solicitud_id, solicitud.responsable_actual_id!, solicitud.revision_responsable, motivo))
    })}>Aceptar responsable actual</Button>{alerta}
  </DialogBody></>
  else if (intento?.correccion) cuerpo = <>{cabecera('Actualización pendiente')}<DialogBody className="space-y-4">
    <p className="text-sm">Estos son los datos que enviaste. Recupera esta actualización antes de continuar.</p>
    <ResumenRevision datos={intento.correccion.datos} />
    <Button className="h-auto min-h-10 max-w-full whitespace-normal" disabled={ocupado} onClick={() => void ejecutar(async () => {
      recibir(await corregirSolicitudInversion(intento)); const i = {...intento}; delete i.correccion; guardar(i); setEditar(false)
    })}>Recuperar actualización pendiente</Button>
    <Button variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal" disabled={ocupado} onClick={() => void ejecutar(async () => {
      recibir(await consultarSolicitudInversion(intento.clave)); const i = {...intento}; delete i.correccion; guardar(i); setEditar(false)
    })}>Descartar esta corrección y revisar la versión del servidor</Button>{alerta}
  </DialogBody></>
  else if (empresa === 'avance' && !perfil) cuerpo = <>{cabecera('Acceso Avance')}<DialogBody className="space-y-4">
    <p className="text-sm">Para su primera inversión Avance, completa sus datos de acceso. Después podrás elegir las condiciones y revisar el contrato.</p>
    {!intento ? <AltaAvance nombre={ficha.persona.nombre} correo={ficha.persona.correo ?? ''} telefono={ficha.persona.telefono ?? ''}
      ocupado={ocupado} onContinuar={alta => ejecutar(async () => preparar({...base, alta_portal: alta,
        contrato: {moneda: 'PEN'}, cronograma: [], cuenta: {}}))} />
      : <><p className="text-sm">{datos?.alta_portal?.correo}</p><Button disabled={ocupado} onClick={() => void ejecutar(async () => {
        const r = await completarAccesoInversion(intento)
        setPerfilCreado(r.perfil_id); recibir(await consultarSolicitudInversion(intento.clave)); await fichaQ.refetch()
      })}>{ocupado ? 'Completando acceso…' : 'Completar acceso Avance'}</Button></>}{alerta}
  </DialogBody></>
  else if (empresa === 'avance' && perfil && (!datos?.contrato?.capital || editar || !intento)) {
    const borrador = contratoDeSolicitud(base, perfil)
    const origen = operacion?.fuente
    cuerpo = <>
      {solicitud && borrador && <div className="px-5 pt-4"><Label htmlFor="f5-motivo">Motivo de la actualización, sin datos personales</Label>
        <Input id="f5-motivo" value={motivo} onChange={e => setMotivo(e.target.value)} maxLength={500} /></div>}
      {alerta && <div className="px-5 pt-3">{alerta}</div>}
      <ContratoNuevo key={`${perfil}:${solicitud?.revision_datos ?? 'nuevo'}`} clienteId={perfil} clienteNombre={ficha.persona.nombre}
        categoriaFija={(operacion?.tipo !== 'reinversion' ? operacion?.tipo : undefined) ?? borrador?.categoria ?? 'nuevo'} borrador={borrador}
        {...(origen && operacion?.tipo === 'renovacion' ? {renovacionOrigen: {id: origen.fuente_id, numeroContrato: origen.numero ?? '',
          capital: origen.capital, moneda: origen.moneda, fechaVencimiento: origen.vence_en ?? ''}} : {})}
        {...(origen?.contrato && operacion?.tipo === 'upgrade' ? {contratosActivos: [{id: origen.fuente_id, numero_contrato: origen.numero ?? '',
          capital: origen.capital, moneda: origen.moneda, tasa_anual: origen.contrato.tasa_anual, fecha_vencimiento: origen.vence_en ?? ''}]} : {})}
        analistas={ficha.persona.responsable_id ? [{perfil_id: ficha.persona.responsable_id, nombre_completo: ficha.persona.responsable_nombre ?? 'Responsable actual'}] : []}
        analistaInicial={ficha.persona.responsable_id} onCreado={() => {}} onOmitir={cerrar}
        onRevisar={async (input: CrearContratoInput, cuotas: CuotaCronograma[]) => {
          await ejecutar(async () => {await revisarDatos(datosAvanceRevisados(base, prepararPayloadContrato(input), cuotas, input.cuenta_pago))})
        }} />
    </>
  } else if (empresa !== 'avance' && (!intento || editar)) cuerpo = <>{cabecera(`${operacion?.tipo === 'reinversion' || intento?.reinversion_origen_id ? 'Reinversión' : 'Nueva inversión'} · ${EMPRESA_NOMBRE[empresa]}`)}<DialogBody className="space-y-4">
    <InversionCooperativa datos={base} ocupado={ocupado} correccion={Boolean(solicitud)} motivo={motivo} onMotivo={setMotivo}
      onGuardar={(d, f, id) => ejecutar(async () => {
        setArchivo(f)
        if (intento) await revisarDatos(d)
        else await preparar(d, id)
      })} />{alerta}
  </DialogBody></>
  else cuerpo = <>{cabecera('Revisar inversión')}<DialogBody className="space-y-4">
    <ResumenRevision datos={base} />
    {solicitud?.identidad_fusionada && <p className="text-sm">La identidad fue unificada. Los antecedentes originales se conservan.</p>}
    <p className="text-sm">Responsable actual: {ficha.persona.responsable_nombre}</p>
    {empresa !== 'avance' && <div className="space-y-2">{archivo
      ? <p className="text-sm font-medium">Comprobante PDF, JPG o PNG (hasta 10 MB)</p>
      : <Label htmlFor="f5-comprobante-revision">Comprobante PDF, JPG o PNG (hasta 10 MB)</Label>}
      {!archivo && <Input id="f5-comprobante-revision" type="file" accept="application/pdf,image/jpeg,image/png" disabled={ocupado}
        onChange={e => setArchivo(e.target.files?.[0] ?? null)} />}
      {archivo && <Button variant="outline" size="sm" disabled={ocupado} onClick={() => setArchivo(null)}>Elegir otro comprobante</Button>}
      <p className="text-xs text-muted-foreground [overflow-wrap:anywhere]">{archivo ? `Archivo seleccionado: ${archivo.name}` : 'Si ya se cargó, el servidor comprobará el archivo al confirmar.'}</p></div>}
    <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
      <Button variant="outline" className="min-h-10" disabled={ocupado} onClick={() => {setEditar(true); setError(null)}}>Corregir datos</Button>
      <Button className="min-h-10" disabled={ocupado || !solicitud || solicitud.necesita_portal} onClick={() => void ejecutar(async () => {
        if (!solicitud || !intento) return
        if (archivo && solicitud.comprobante_ruta) await subirComprobanteInversion(solicitud.comprobante_ruta, archivo)
        const resultado = await confirmarSolicitudInversion(solicitud.solicitud_id, solicitud.revision_datos)
        if (!cerro.current) {setConfirmacion(resultado); onConfirmada()}
      })}>{ocupado ? 'Confirmando…' : 'Confirmar inversión'}</Button>
    </div>
    <Button variant="ghost" disabled={ocupado} onClick={() => void ejecutar(async () => {if (intento) recibir(await consultarSolicitudInversion(intento.clave))})}>Actualizar revisión</Button>
    {alerta}
    <p className="text-xs text-muted-foreground [overflow-wrap:anywhere]">Referencia: {intento?.clave}. Revisión {solicitud?.revision_datos}.</p>
  </DialogBody></>
  return <Dialog open onClose={cerrar} ariaLabel="Nueva inversión" className="w-[760px]">
    {cuerpo}
    <DialogFooter><Button variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal" disabled={ocupado} onClick={cerrar}>{confirmacion ? 'Volver a la ficha' : 'Cerrar y continuar después'}</Button></DialogFooter>
  </Dialog>
}

function AltaAvance({nombre, correo, telefono, ocupado, onContinuar}: {
  nombre: string; correo: string; telefono: string; ocupado: boolean; onContinuar: (datos: AltaPortal) => Promise<void>
}) {
  const [datos, setDatos] = useState<AltaPortal>({nombre_completo: nombre, correo, telefono, nombres: '', apellidos: '', domicilio: ''})
  const [error, setError] = useState('')
  const campos = {nombre_completo: 'Nombre completo', nombres: 'Nombres', apellidos: 'Apellidos', correo: 'Correo de acceso Avance', telefono: 'Teléfono', domicilio: 'Domicilio legal'} as const
  return <form className="grid gap-3 sm:grid-cols-2" onSubmit={e => {
    e.preventDefault(); const domicilio = validarDomicilioLegal(datos.domicilio)
    if (!domicilio.ok) {setError(domicilio.error); return}
    setError(''); void onContinuar(datos)
  }}>
    {(Object.keys(campos) as (keyof AltaPortal)[]).map(k => <div key={k} className="min-w-0 space-y-1">
      <Label htmlFor={`f5-alta-${k}`}>{campos[k]}</Label><Input id={`f5-alta-${k}`} type={k === 'correo' ? 'email' : 'text'} required
        value={datos[k]} disabled={ocupado} maxLength={k === 'domicilio' ? 300 : 180}
        onChange={e => setDatos({...datos, [k]: e.target.value})} /></div>)}
    {error && <p role="alert" className="text-sm text-destructive-text sm:col-span-2">{error}</p>}
    <Button type="submit" className="sm:col-span-2" disabled={ocupado}>Revisar acceso Avance</Button>
  </form>
}
function InversionCooperativa({datos, ocupado, correccion, motivo, onMotivo, onGuardar}: {
  datos: DatosInversion; ocupado: boolean; correccion: boolean; motivo: string; onMotivo: (v: string) => void
  onGuardar: (datos: DatosInversion, archivo: File | null, clave: string) => Promise<void>
}) {
  // La cooperativa de esta solicitud. `datos.empresa` ya no puede ser 'avance'
  // aquí (ese camino va a ContratoNuevo), así que sirve de clave del espejo.
  const coop = datos.empresa as Cooperativa
  const [monto, setMonto] = useState(datos.monto?.toString() ?? '')
  // La moneda: se conserva la de una solicitud que se está corrigiendo y, si no
  // hay, la primera que admite esa cooperativa. Solo se PREGUNTA cuando admite
  // más de una (Prodelco desde el 17/09/2026).
  const [moneda, setMoneda] = useState<Moneda>(
    datos.moneda === 'USD' || datos.moneda === 'PEN' ? datos.moneda : monedaPorDefecto(coop),
  )
  const [fecha, setFecha] = useState(datos.fecha_comercial ?? fechaLima(Date.now()))
  const [plazo, setPlazo] = useState(datos.plazo_meses?.toString() ?? '')
  const [tasa, setTasa] = useState(datos.tasa_anual?.toString() ?? '')
  const [deposito, setDeposito] = useState(datos.numero_transaccion ?? '')
  const [referencia, setReferencia] = useState(datos.referencia ?? '')
  const [archivo, setArchivo] = useState<File | null>(null)
  const [error, setError] = useState('')
  const [campoError, setCampoError] = useState<CampoCondicionesCoopac | null>(null)
  const [id] = useState(() => crypto.randomUUID())
  const enviar = (e: FormEvent) => {
    e.preventDefault(); setCampoError(null); const capital = parseMonto(monto)
    if (capital === null || capital <= 0) {setError(ERROR_MONTO); return}
    const condiciones = condicionesCoopac(fecha, plazo, tasa)
    if (!condiciones.ok) {setCampoError(condiciones.campo); setError(condiciones.error); return}
    if (!datos.evidencia && !archivo) {setError('Selecciona el comprobante de depósito.'); return}
    if (archivo && (!['application/pdf','image/jpeg','image/png'].includes(archivo.type) || archivo.size > 10485760 || !archivo.size)) {
      setError('Usa un PDF, JPG o PNG de hasta 10 MB.'); return
    }
    const ext = archivo?.type === 'application/pdf' ? 'pdf' : archivo?.type === 'image/png' ? 'png' : 'jpg'
    const ruta = datos.evidencia?.ruta ?? `${datos.inversionista_id}/${id}/comprobante.${ext}`
    setError(''); void onGuardar({...datos, monto: capital, moneda, fecha_comercial: fecha,
      vence_en: condiciones.venceEn, plazo_meses: condiciones.plazoMeses, tasa_anual: condiciones.tasaAnual,
      numero_transaccion: deposito.trim(), referencia: referencia.trim(), evidencia: {ruta}}, archivo, id)
  }
  return <form onSubmit={enviar} className="space-y-3">
    <div className="grid gap-3 sm:grid-cols-2">
      <div className="min-w-0 space-y-1"><Label htmlFor="f5-monto">Capital en {moneda === 'USD' ? 'dólares' : 'soles'} ({moneda})</Label><Input id="f5-monto" inputMode="decimal" required value={monto} onChange={e => setMonto(e.target.value)} disabled={ocupado} /></div>
      {/* La moneda solo se ofrece si ESTA cooperativa admite más de una: el
          espejo vive en INFO_COOPERATIVA y la regla la manda el catálogo del
          servidor (`crm.empresas.monedas`). */}
      {pideMoneda(coop) && <div className="min-w-0 space-y-1"><Label htmlFor="f5-moneda">Moneda</Label>
        <Select id="f5-moneda" value={moneda} onChange={e => setMoneda(e.target.value as Moneda)} disabled={ocupado}>
          {INFO_COOPERATIVA[coop].monedas.map(m => <option key={m} value={m}>{m === 'PEN' ? 'Soles (S/)' : 'Dólares (US$)'}</option>)}
        </Select></div>}
      <div className="min-w-0 space-y-1"><Label htmlFor="f5-deposito">Número de operación del depósito</Label><Input id="f5-deposito" required maxLength={64} value={deposito} onChange={e => setDeposito(e.target.value)} disabled={ocupado} /></div>
    </div>
    <CondicionesCoopac prefijo="f5" fecha={fecha} plazo={plazo} tasa={tasa} ocupado={ocupado}
      invalido={campoError} errorId="f5-condiciones-error"
      onFecha={v => {setFecha(v); setCampoError(null); setError('')}}
      onPlazo={v => {setPlazo(v); setCampoError(null); setError('')}}
      onTasa={v => {setTasa(v); setCampoError(null); setError('')}} />
    <div className="space-y-1"><Label htmlFor="f5-referencia-externa">Referencia de la inversión</Label><Input id="f5-referencia-externa" required maxLength={64} value={referencia} onChange={e => setReferencia(e.target.value)} disabled={ocupado} /></div>
    <div className="space-y-1"><Label htmlFor="f5-comprobante">Comprobante PDF, JPG o PNG (hasta 10 MB)</Label><Input id="f5-comprobante" type="file" accept="application/pdf,image/jpeg,image/png"
      required={!datos.evidencia} onChange={e => setArchivo(e.target.files?.[0] ?? null)} disabled={ocupado} /></div>
    {correccion && <div className="space-y-1"><Label htmlFor="f5-motivo">Motivo de la corrección, sin datos personales</Label><Input id="f5-motivo" required minLength={10} maxLength={500} value={motivo} onChange={e => onMotivo(e.target.value)} /></div>}
    {error && <p id="f5-condiciones-error" role="alert" className="text-sm text-destructive-text">{error}</p>}
    <Button type="submit" disabled={ocupado}>Revisar inversión</Button>
  </form>
}
function ResumenRevision({datos}: {datos: DatosInversion}) {
  const c = datos.contrato
  const capital = datos.empresa === 'avance' ? Number(c?.capital) : datos.monto
  const moneda = datos.empresa === 'avance' ? c?.moneda : datos.moneda
  return <dl className="grid gap-3 rounded-xl border border-border bg-muted/20 p-4 text-sm sm:grid-cols-2 [overflow-wrap:anywhere]">
    <div><dt className="text-muted-foreground">Empresa</dt><dd className="font-medium">{EMPRESA_NOMBRE[datos.empresa]}</dd></div>
    <div><dt className="text-muted-foreground">Capital</dt><dd className="font-semibold">{capital != null && Number.isFinite(capital) ? money(capital, moneda === 'USD' ? 'USD' : 'PEN') : 'Pendiente de completar'}</dd></div>
    <div><dt className="text-muted-foreground">Fecha comercial</dt><dd>{fmtFecha(String(c?.fecha_inicio ?? datos.fecha_comercial ?? ''))}</dd></div>
    <div><dt className="text-muted-foreground">Vencimiento</dt><dd>{fmtFecha(String(c?.fecha_vencimiento ?? datos.vence_en ?? ''))}</dd></div>
    {datos.empresa === 'avance' ? <><div><dt className="text-muted-foreground">Contrato</dt><dd>{String(c?.numero_contrato ?? '')}</dd></div>
      <div><dt className="text-muted-foreground">Tasa anual</dt><dd>{String(c?.tasa_anual ?? '')}% · {String(c?.modalidad ?? '')} · {String(c?.tipo_interes ?? '')}</dd></div>
      <div><dt className="text-muted-foreground">Operación</dt><dd>{String(c?.categoria ?? '')}</dd></div>
      <div><dt className="text-muted-foreground">Cuenta de pago</dt><dd>{datos.cuenta?.tipo === 'existente' ? 'Cuenta Avance seleccionada' : `${String(datos.cuenta?.banco ?? (datos.cuenta?.cuenta_esperada as Record<string, unknown> | undefined)?.banco ?? '')} · cuenta revisada en el formulario`}</dd></div></>
      : <><div><dt className="text-muted-foreground">Plazo</dt><dd>{datos.plazo_meses ? `${datos.plazo_meses} meses` : 'Sin plazo registrado'}</dd></div>
        <div><dt className="text-muted-foreground">Rentabilidad anual</dt><dd>{datos.tasa_anual != null ? `${datos.tasa_anual}% anual` : 'Sin rentabilidad registrada'}</dd></div>
        <div><dt className="text-muted-foreground">Depósito</dt><dd>{datos.numero_transaccion}</dd></div><div><dt className="text-muted-foreground">Referencia</dt><dd>{datos.referencia}</dd></div></>}
  </dl>
}
