import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
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
import { inversionistasKeys, useFichaInversionista } from '@/data/inversionistas-queries'
import { refrescarGestionInversionista } from '@/data/gestion-inversionista'
import { descargarDocumentoInversionista } from '@/data/inversionistas-api'
import { CrmApiError, mensajeDeError, prepararPayloadContrato, type CrearContratoInput, type CondicionesTasaLead } from '@/data/crm-api'
import { completarAccesoInversion, confirmarSolicitudInversion, consultarSolicitudInversion, corregirSolicitudInversion,
  prepararSolicitudInversion, revisarResponsableInversion, subirComprobanteInversion, obtenerContextoConversionInversion, enviarBienvenidaInversion, cancelarSolicitudInversion } from '@/data/inversion-solicitud-api'
import { contratoDeSolicitud, datosAvanceRevisados, guardarBorradorAcceso, guardarBorradorCondiciones, guardarIntentoInversion,
  leerBorradorAcceso, leerBorradorCondiciones, leerIntentoInversion, limpiarBorradorAcceso, limpiarBorradorCondiciones,
  limpiarIntentosInversion, nuevoIntentoInversion, mismoContenidoInversion, solicitudCorresponde,
  type ConfirmacionInversion, type DatosBorradorAcceso, type DatosInversion, type IntentoInversion, type OrigenIntento, type SolicitudInversion } from '@/lib/inversion-solicitud'
import { EMPRESAS_INVERSION, EMPRESA_NOMBRE, type EmpresaInversion, type InversionFuente } from '@/lib/inversionistas'
import { obtenerContextoClienteExistente, type LlaveVentaCruzada } from '@/data/cliente-existente-api'
import { useContratosUpgradeVentaCruzada } from '@/data/cliente-existente-queries'
import { validarDomicilioLegal } from '@/lib/cliente-form-logica'
import { CORREO_RE } from '@/lib/validacion'
import { parseMonto, ERROR_MONTO } from '@/lib/numero'
import { fmtFecha, money, type Moneda } from '@/lib/format'
import { INFO_COOPERATIVA, monedaPorDefecto, pideMoneda, type Cooperativa } from '@/lib/cierres-externos'
import { type CuotaCronograma } from '@/lib/cronograma'
import type { TipoDocumento } from '@/lib/documento'
import { archivarContratoPdfConfirmado } from '@/lib/contrato-pdf-archivo'

export interface OperacionInversion {tipo: 'upgrade' | 'renovacion' | 'reinversion'; fuente: InversionFuente}
export interface OrigenLeadInversion {
  id: string; solicitudId: string | null; condiciones?: CondicionesTasaLead | undefined
  monto: number | null; moneda: Moneda; tipoDocumento: TipoDocumento
}
/** Venta cruzada: un cliente de OTRA cartera, hallado por su documento (la búsqueda es la
 * llave hasta preparar; después, la propia solicitud). La venta es de quien la registra. */
export interface OrigenClienteExistente {busquedaId: string}
const MOTIVO_VENTA_MINIMO = 10
type AltaPortal = NonNullable<DatosInversion['alta_portal']>
const mensajeRecuperacion = 'La solicitud sigue guardada en esta sesión. Consulta su estado antes de volver a enviarla.'

export function InversionNueva({actor, persona, operacion, origenLead, origenClienteExistente, onCerrar, onRevocado, onConfirmada}: {
  actor: string; persona: string; operacion?: OperacionInversion | undefined
  origenLead?: OrigenLeadInversion | undefined
  origenClienteExistente?: OrigenClienteExistente | undefined
  onCerrar: () => void; onRevocado: () => void; onConfirmada: () => void
}) {
  // Dónde vive el intento en esta pestaña: la cartera propia, un lead o la venta cruzada.
  // Estable entre renders: es llave de borradores y dependencia de memos.
  const esVentaCruzada = Boolean(origenClienteExistente)
  const origenIntento: OrigenIntento = useMemo(() => origenLead?.id ?? (esVentaCruzada ? {ventaCruzada: true} : undefined),
    [origenLead?.id, esVentaCruzada])
  const [guardado, setGuardado] = useState(() => {
    try {return {intento: leerIntentoInversion(actor, persona, origenIntento), error: null}}
    catch (e) {return {intento: null, error: mensajeDeError(e, 'No se pudo recuperar la solicitud.')}}
  })
  const [intento, setIntento] = useState<IntentoInversion | null>(guardado.intento)
  const [solicitud, setSolicitud] = useState<SolicitudInversion | null>(null)
  const [empresa, setEmpresa] = useState<EmpresaInversion | null>(guardado.intento?.datos.empresa ?? (operacion?.fuente.empresa ?? null))
  const [error, setError] = useState<string | null>(guardado.error)
  const [ocupado, setOcupado] = useState(false)
  const [recuperando, setRecuperando] = useState(guardado.intento !== null || Boolean(origenLead?.solicitudId))
  const [editar, setEditar] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [archivo, setArchivo] = useState<File | null>(null)
  const [confirmacion, setConfirmacion] = useState<ConfirmacionInversion | null>(null)
  const [cancelando, setCancelando] = useState(false)
  const [bienvenida, setBienvenida] = useState<string | null>(null)
  const [perfilCreado, setPerfilCreado] = useState<string | null>(null)
  const [referencia, setReferencia] = useState('')
  const [motivoVenta, setMotivoVenta] = useState(guardado.intento?.venta_cruzada?.motivo ?? '')
  // Sin motivo no se elige empresa; los botones siguen enfocables y lo explican (aria-disabled).
  const faltaMotivo = Boolean(origenClienteExistente) && motivoVenta.trim().length < MOTIVO_VENTA_MINIMO
  const [borradorSinGuardar, setBorradorSinGuardar] = useState(false)
  const [confirmarCierreSinGuardar, setConfirmarCierreSinGuardar] = useState(false)
  const cerro = useRef(false)
  const enCurso = useRef(false)
  const descargaPdf = useRef<AbortController | null>(null)
  const callbacks = useRef({onRevocado, onConfirmada})
  callbacks.current = {onRevocado, onConfirmada}
  const qc = useQueryClient()
  const notificadas = useRef(new Set<string>())
  const carteraQ = useFichaInversionista(actor, origenLead || origenClienteExistente ? '' : persona, 1, 1)
  const conversionQ = useQuery({
    queryKey: [...inversionistasKeys.actor(actor), 'conversion', origenLead?.id, persona],
    queryFn: ({signal}) => obtenerContextoConversionInversion(origenLead!.id, persona, signal),
    enabled: Boolean(origenLead), staleTime: 0, gcTime: 0, retry: false,
    refetchOnMount: 'always', refetchOnWindowFocus: 'always', refetchOnReconnect: 'always', refetchInterval: 15_000,
  })
  // Venta cruzada: la llave es la búsqueda hasta que el servidor devuelve la solicitud, y la
  // solicitud solo mientras está PREPARADA (cerrada ya no abre datos vivos). Cancelada, se
  // vuelve a la búsqueda: si venció, el servidor responde 42501 y se vuelve a buscar. Al
  // recuperar un intento se espera a la solicitud y, confirmada, se deja de consultar.
  const llaveVenta: LlaveVentaCruzada | undefined = !origenClienteExistente ? undefined
    : solicitud?.estado === 'preparada' ? {solicitudId: solicitud.solicitud_id} : {busquedaId: origenClienteExistente.busquedaId}
  const ventaCruzadaQ = useQuery({
    queryKey: [...inversionistasKeys.actor(actor), 'venta-cruzada', persona, llaveVenta?.solicitudId ?? llaveVenta?.busquedaId],
    queryFn: ({signal}) => obtenerContextoClienteExistente(llaveVenta!, signal),
    enabled: Boolean(llaveVenta) && !recuperando && !confirmacion, staleTime: 0, gcTime: 0, retry: false,
    refetchOnMount: 'always', refetchOnWindowFocus: 'always', refetchOnReconnect: 'always', refetchInterval: 15_000,
  })
  const upgradeQ = useContratosUpgradeVentaCruzada(llaveVenta, Boolean(llaveVenta) && !recuperando && !confirmacion)
  const fichaQ = origenClienteExistente ? ventaCruzadaQ : origenLead ? conversionQ : carteraQ
  const revocada = fichaQ.error instanceof CrmApiError && ['42501','PT409'].includes(fichaQ.error.code)
  const ficha = fichaQ.isFetchedAfterMount && !revocada ? fichaQ.data : null
  const verificacionPendiente = fichaQ.isError && Boolean(ficha)
  const guardar = (i: IntentoInversion) => {guardarIntentoInversion(i); setIntento(i)}
  const notificar = (r: ConfirmacionInversion) => {
    if (notificadas.current.has(r.inversion_id)) return
    notificadas.current.add(r.inversion_id)
    void refrescarGestionInversionista(qc, actor)
    callbacks.current.onConfirmada()
  }
  const confirmarBienvenida = async (id: string) => {
    setBienvenida('en_proceso')
    try {const r=await enviarBienvenidaInversion(id); if(!cerro.current)setBienvenida(r.estado)}
    catch {if(!cerro.current)setBienvenida('pendiente')}
  }
  const bienvenidaId = origenLead && confirmacion?.empresa === 'avance' ? intento?.clave : undefined
  useEffect(() => {
    if(bienvenidaId)void confirmarBienvenida(bienvenidaId)
  }, [bienvenidaId])
  const recibir = (s: SolicitudInversion) => {
    if (cerro.current) return
    setSolicitud(s)
    if (s.estado === 'confirmada' && s.resultado) {setConfirmacion(s.resultado); notificar(s.resultado)}
  }
  const recibirRecuperacion = (s: SolicitudInversion) => {
    if (!solicitudCorresponde(s, persona, origenIntento) || !s.datos) {
      throw new Error('La solicitud no corresponde a este origen. Vuelve a abrir la ficha.')
    }
    if (!intento) guardar(nuevoIntentoInversion(actor, persona, s.solicitud_id, s.datos, s.reinversion_origen_id))
    setGuardado(previo => ({...previo, error: null}))
    setError(null)
    setEmpresa(s.datos.empresa)
    if (s.datos.empresa === 'avance' && s.necesita_portal) {
      try {setEditar(Boolean(leerBorradorAcceso(actor, persona, origenIntento, s.solicitud_id)))}
      catch { /* La solicitud del servidor sigue siendo recuperable. */ }
    }
    recibir(s)
  }
  const [recuperarId, setRecuperarId] = useState(guardado.intento?.clave ?? origenLead?.solicitudId)
  useEffect(() => {
    cerro.current = false
    const abort = new AbortController()
    if (recuperarId) void consultarSolicitudInversion(recuperarId, abort.signal)
      .then(s => {
        if (!abort.signal.aborted) {
          recibirRecuperacion(s)
        }
      }).catch(e => {
        if (abort.signal.aborted) return
        if (e instanceof CrmApiError && e.code === '42501') callbacks.current.onRevocado()
        else setError(mensajeDeError(e, mensajeRecuperacion))
      }).finally(() => {if (!abort.signal.aborted) setRecuperando(false)})
    return () => {cerro.current = true; abort.abort(); descargaPdf.current?.abort()}
  // La solicitud es estable por montaje; los callbacks usan refs para evitar
  // que un refresco de la ficha vuelva a reclamar la recuperación.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recuperarId])
  useEffect(() => {
    if (revocada) callbacks.current.onRevocado()
    else if (fichaQ.isFetchedAfterMount && fichaQ.isSuccess && !fichaQ.data) callbacks.current.onRevocado()
  }, [revocada, fichaQ.isFetchedAfterMount, fichaQ.isSuccess, fichaQ.data])
  async function ejecutar(trabajo: () => Promise<void>) {
    if (enCurso.current || verificacionPendiente) return
    enCurso.current = true; setOcupado(true); setError(null)
    try {await trabajo()}
    catch (e) {
      if (cerro.current) return
      if (e instanceof CrmApiError && e.code === '42501') callbacks.current.onRevocado()
      else setError(mensajeDeError(e, mensajeRecuperacion))
    } finally {enCurso.current = false; if (!cerro.current) setOcupado(false)}
  }
  async function preparar(datos: DatosInversion, claveSolicitud: string = crypto.randomUUID()) {
    const i = nuevoIntentoInversion(actor, persona, claveSolicitud, datos, operacion?.tipo === 'reinversion' ? operacion.fuente.fuente_id : undefined,
      origenClienteExistente ? {busqueda_id: origenClienteExistente.busquedaId, motivo: motivoVenta.trim()} : undefined)
    // Si el navegador no permite guardar la recuperación, no enviamos el alta.
    guardar(i)
    limpiarBorradorAcceso(actor, persona, origenIntento)
    setBorradorSinGuardar(false)
    recibir(await prepararSolicitudInversion(i))
  }
  async function revisarDatos(datos: DatosInversion) {
    if (!intento) {await preparar(datos); return}
    if (!solicitud?.datos) throw new Error('Consulta primero la solicitud pendiente.')
    if (mismoContenidoInversion(datos, solicitud.datos)) {
      limpiarBorradorAcceso(actor, persona, origenIntento)
      limpiarBorradorCondiciones(actor, persona, origenIntento)
      setBorradorSinGuardar(false); setEditar(false); return
    }
    const motivoEfectivo = solicitud.datos.empresa === 'avance' && !solicitud.datos.contrato?.capital
      ? 'Completar condiciones contractuales después de preparar el acceso Avance' : motivo.trim()
    if (motivoEfectivo.length < 10) throw new Error('Indica un motivo de al menos 10 caracteres, sin datos personales.')
    const i = {...intento, correccion: {clave: crypto.randomUUID(), revision: solicitud.revision_datos, datos, motivo: motivoEfectivo}}
    guardar(i)
    recibir(await corregirSolicitudInversion(i))
    const limpio: IntentoInversion = {...i}; delete limpio.correccion; guardar(limpio)
    limpiarBorradorAcceso(actor, persona, origenIntento)
    limpiarBorradorCondiciones(actor, persona, origenIntento)
    setBorradorSinGuardar(false)
    setEditar(false); setMotivo('')
  }
  const datos = solicitud?.datos ?? intento?.datos
  const perfil = operacion?.fuente.perfil_id ?? ficha?.persona.perfil_id ?? perfilCreado
  const base: DatosInversion = datos ?? {inversionista_id: ficha?.persona.inversionista_id ?? persona,
    ...(origenLead ? {lead_id: origenLead.id} : {}), empresa: empresa ?? 'avance',
    ...(origenLead && empresa && empresa !== 'avance' ? {
      ...(origenLead.monto != null ? {monto: origenLead.monto} : {}),
      moneda: INFO_COOPERATIVA[empresa].monedas.includes(origenLead.moneda) ? origenLead.moneda : monedaPorDefecto(empresa),
    } : {})}
  const puedeOperar = ficha?.capacidades.nueva_inversion === true
  const borradorCondiciones = useMemo(() => {
    if (!intento || !solicitud || !datos?.alta_portal) return null
    try {return leerBorradorCondiciones(actor, persona, origenIntento, intento.clave, solicitud.revision_datos)}
    catch {return null}
  }, [actor, persona, origenIntento, intento, solicitud, datos?.alta_portal])
  const cerrar = () => {
    if (enCurso.current) return
    if (borradorSinGuardar && !confirmarCierreSinGuardar) {setConfirmarCierreSinGuardar(true); return}
    if (confirmacion) limpiarIntentosInversion(actor, persona, origenIntento)
    onCerrar()
  }
  const estadoBorrador = (sinGuardar: boolean) => {
    setBorradorSinGuardar(sinGuardar)
    setConfirmarCierreSinGuardar(false)
  }
  const origenReinversion = solicitud?.reinversion_origen_id ?? intento?.reinversion_origen_id ?? (operacion?.tipo === 'reinversion' ? operacion.fuente.fuente_id : null)
  const cabecera = (titulo: string) => <DialogHeader><DialogTitle>{titulo}</DialogTitle>
    {ficha && <p className="text-sm text-muted-foreground [overflow-wrap:anywhere]">{ficha.persona.nombre}</p>}
    {origenReinversion && <p className="text-sm text-muted-foreground">Reinversión vinculada a una inversión anterior{operacion?.fuente.numero ? ` · ${operacion.fuente.numero}` : ''}. Su registro original se conserva.</p>}</DialogHeader>
  const alerta = error && <p role="alert" className="rounded-xl border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive-text [overflow-wrap:anywhere]">{error}</p>
  const mostrarPasos = empresa === 'avance' && !confirmacion && (!perfil || Boolean(datos?.alta_portal))
  let cuerpo
  if (!ficha || recuperando) cuerpo = <>{cabecera('Nueva inversión')}<DialogBody>
    {fichaQ.isError ? <PanelError mensaje={mensajeDeError(fichaQ.error, 'No se pudo verificar el acceso.')}
      onReintentar={() => void fichaQ.refetch()} reintentando={fichaQ.isFetching} /> : <PanelCargando />}
  </DialogBody></>
  else if (confirmacion) cuerpo = <>{cabecera('Inversión confirmada')}<DialogBody className="space-y-4">
    <p role="status" className="flex items-center gap-2 font-medium"><CheckCircle2 aria-hidden />La inversión quedó registrada en {EMPRESA_NOMBRE[confirmacion.empresa]}.</p>
    {confirmacion.fuente.numero_contrato && <p>Contrato {confirmacion.fuente.numero_contrato}</p>}
    <p className="text-sm text-muted-foreground">{origenClienteExistente
      ? 'Su responsable la verá en la ficha del cliente, junto con sus otras inversiones.'
      : 'La ficha consultará el saldo y los antecedentes actualizados.'}</p>
    {bienvenida === 'enviada' && <p role="status" className="text-sm">La bienvenida al portal fue enviada.</p>}
    {bienvenida === 'verificar_entrega' && <p role="status" className="text-sm">La inversión está guardada. Gerencia debe verificar si el correo de bienvenida fue entregado antes de volver a enviarlo.</p>}
    {bienvenidaId && (bienvenida === 'pendiente' || bienvenida === 'en_proceso') && <div className="space-y-2">
      <p role="status" className="text-sm">La inversión está guardada. El envío de bienvenida sigue pendiente de confirmación.</p>
      <Button variant="outline" disabled={ocupado} onClick={() => void ejecutar(() => confirmarBienvenida(bienvenidaId))}>Consultar / reintentar bienvenida</Button>
    </div>}
    {confirmacion.empresa === 'avance' && confirmacion.fuente.id && <Button variant="outline" disabled={ocupado} onClick={() => void ejecutar(async () => {
      const abort = new AbortController(); descargaPdf.current?.abort(); descargaPdf.current = abort
      await archivarContratoPdfConfirmado(confirmacion.fuente.id!)
      if (!cerro.current) await descargarDocumentoInversionista(persona, confirmacion.fuente.id!, confirmacion.fuente.id!, abort.signal)
    })}>Preparar / descargar PDF</Button>}
    {alerta}
  </DialogBody></>
  else if (recuperarId && !solicitud && !intento) cuerpo = <>{cabecera('Recuperar solicitud')}<DialogBody className="space-y-4">
    <p className="text-sm">Este lead ya tiene una solicitud. Consulta su estado para continuar.</p>{alerta}
    <Button disabled={ocupado} onClick={() => void ejecutar(async () => {
      recibirRecuperacion(await consultarSolicitudInversion(recuperarId))
    })}>Consultar y recuperar</Button>
  </DialogBody></>
  else if (solicitud?.estado === 'cancelada') cuerpo = <>{cabecera('Solicitud cancelada')}<DialogBody className="space-y-3"><p>Esta solicitud está cancelada. No se registró ninguna inversión.</p>
    <Button variant="outline" disabled={!puedeOperar} onClick={() => {
      limpiarIntentosInversion(actor, persona, origenIntento); setIntento(null); setSolicitud(null); setEmpresa(null)
      setGuardado({intento: null, error: null}); setError(null); setArchivo(null); setEditar(false); setMotivo(''); setRecuperarId(null)
    }}>Iniciar otra inversión</Button></DialogBody></>
  else if (!puedeOperar) cuerpo = <>{cabecera('Nueva inversión')}<DialogBody><p role="status">{ficha.capacidades.motivo_no_operable ?? 'La persona ya no permite nuevas inversiones.'}</p></DialogBody></>
  else if (guardado.error || !empresa) cuerpo = <>{cabecera(guardado.error ? 'Recuperar solicitud' : 'Nueva inversión')}<DialogBody className="space-y-5">
    {guardado.error ? <div className="space-y-3">
      <p className="text-sm">El borrador local no se puede leer. Puedes consultar la solicitud por su referencia.</p>
      <Button variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal" onClick={() => {
        limpiarIntentosInversion(actor, persona, origenIntento); setGuardado({intento: null, error: null}); setError(null); setEmpresa(null)
      }}>Descartar el borrador local ilegible</Button>
      <p className="text-xs text-muted-foreground">Descartarlo no cancela una solicitud que ya esté registrada en el servidor.</p>
    </div> : <>{origenClienteExistente && <div className="space-y-1">
        <p id="f5-venta-aviso" className="text-sm">Registras una inversión de un cliente de otra cartera: quedará a tu nombre y su responsable, {ficha.persona.responsable_nombre ?? 'sin responsable'}, lo verá en su ficha.</p>
        <Label htmlFor="f5-motivo-venta">Motivo de la venta, sin datos personales</Label>
        <Input id="f5-motivo-venta" value={motivoVenta} onChange={e => setMotivoVenta(e.target.value)} minLength={MOTIVO_VENTA_MINIMO} maxLength={500}
          aria-required="true" aria-describedby="f5-venta-aviso f5-motivo-venta-ayuda" />
        <p id="f5-motivo-venta-ayuda" className="text-sm text-muted-foreground">Entre {MOTIVO_VENTA_MINIMO} y 500 caracteres
          {faltaMotivo ? ` (faltan ${MOTIVO_VENTA_MINIMO - motivoVenta.trim().length})` : ''}. Por ejemplo: «El cliente me pidió invertir en la feria».</p>
      </div>}
      <p id="f5-empresa-ayuda" className="text-sm">{faltaMotivo ? 'Escribe primero el motivo de la venta para elegir la empresa.' : 'Elige la empresa en la que invertirá.'}</p>
      <div className="grid gap-3 sm:grid-cols-3">{EMPRESAS_INVERSION.map(e => <Button key={e} variant="outline" className="h-20 flex-col aria-disabled:opacity-50"
        aria-disabled={faltaMotivo || undefined} aria-describedby={origenClienteExistente ? 'f5-empresa-ayuda' : undefined}
        onClick={() => {if (faltaMotivo) document.getElementById('f5-motivo-venta')?.focus(); else setEmpresa(e)}}>
        <Landmark aria-hidden />{EMPRESA_NOMBRE[e]}</Button>)}</div></>}
    <form onSubmit={e => {e.preventDefault(); void ejecutar(async () => {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(referencia)) throw new Error('Introduce la referencia completa de la solicitud.')
      const s = await consultarSolicitudInversion(referencia)
      if (!solicitudCorresponde(s, ficha.persona.inversionista_id, origenIntento) || !s.datos) throw new Error('La solicitud no corresponde a esta ficha.')
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
      try {recibirRecuperacion(await consultarSolicitudInversion(intento.clave))}
      catch (e) {
        if (e instanceof CrmApiError && e.code === 'P0002') recibir(await prepararSolicitudInversion(intento))
        else throw e
      }
    })}>Consultar y recuperar</Button>
  </DialogBody></>
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
      recibir(await corregirSolicitudInversion(intento)); const i = {...intento}; delete i.correccion; guardar(i)
      limpiarBorradorAcceso(actor, persona, origenIntento)
      limpiarBorradorCondiciones(actor, persona, origenIntento); setEditar(false)
    })}>Recuperar actualización pendiente</Button>
    <Button variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal" disabled={ocupado} onClick={() => void ejecutar(async () => {
      recibir(await consultarSolicitudInversion(intento.clave)); const i = {...intento}; delete i.correccion; guardar(i)
      limpiarBorradorAcceso(actor, persona, origenIntento)
      limpiarBorradorCondiciones(actor, persona, origenIntento); setEditar(false)
    })}>Descartar esta corrección y revisar la versión del servidor</Button>{alerta}
  </DialogBody></>
  else if (empresa === 'avance' && !perfil) cuerpo = <>{cabecera('Acceso Avance')}<PasosAcceso actual={1} /><DialogBody className="space-y-4">
    <p className="text-sm">Completa los datos de acceso para su primera inversión Avance. Después elegirás las condiciones y revisarás el contrato.</p>
    {!intento || editar ? <AltaAvance key={intento?.clave ?? 'nuevo'} actor={actor} persona={persona} origen={origenIntento}
      solicitud={intento?.clave ?? null} inicial={datos?.alta_portal} correo={ficha.persona.correo ?? ''}
      telefono={ficha.persona.telefono ?? ''} ocupado={ocupado} onEstadoBorrador={estadoBorrador}
      onContinuar={alta => ejecutar(async () => {
        if (intento) await revisarDatos({...base, alta_portal: alta})
        else await preparar({...base, alta_portal: alta, contrato: {moneda: 'PEN'}, cronograma: [], cuenta: {}})
      })} />
      : <div className="space-y-3">
        <p className="text-sm font-medium">Revisa estos datos antes de crear el acceso del cliente.</p>
        <dl className="grid gap-3 rounded-xl border border-border bg-muted/20 p-4 text-sm [overflow-wrap:anywhere] sm:grid-cols-2">
          <div><dt className="text-muted-foreground">Apellidos y nombres</dt><dd>{datos?.alta_portal?.apellidos} {datos?.alta_portal?.nombres}</dd></div>
          <div><dt className="text-muted-foreground">Correo de acceso Avance</dt><dd className="font-semibold">{datos?.alta_portal?.correo}</dd></div>
          <div className="sm:col-span-2"><dt className="text-muted-foreground">Domicilio legal para el contrato</dt><dd>{datos?.alta_portal?.domicilio}</dd></div>
        </dl>
        <p className="text-xs text-muted-foreground">Confirma que el cliente puede recibir mensajes en ese correo. Puedes corregirlo antes de crear el acceso.</p>
        <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
          <Button variant="outline" disabled={ocupado} onClick={() => setEditar(true)}>Corregir datos de acceso</Button>
          <Button disabled={ocupado} onClick={() => void ejecutar(async () => {
            const r = await completarAccesoInversion(intento)
            setPerfilCreado(r.perfil_id); recibir(await consultarSolicitudInversion(intento.clave)); await fichaQ.refetch()
          })}>{ocupado ? 'Completando acceso…' : 'Completar acceso Avance'}</Button>
        </div>
      </div>}{alerta}
  </DialogBody></>
  else if (empresa === 'avance' && perfil && (!datos?.contrato?.capital || editar || !intento) && origenClienteExistente
    && !upgradeQ.isSuccess) cuerpo = <>{cabecera('Condiciones del contrato')}<DialogBody>
    {/* Sin la lista real de contratos, un upgrade parecería imposible: no se muestra el formulario a medias. */}
    {upgradeQ.isError ? <PanelError mensaje={mensajeDeError(upgradeQ.error, 'No pudimos cargar los contratos del cliente que un upgrade puede ampliar.')}
      onReintentar={() => void upgradeQ.refetch()} reintentando={upgradeQ.isFetching} /> : <PanelCargando />}
  </DialogBody></>
  else if (empresa === 'avance' && perfil && (!datos?.contrato?.capital || editar || !intento)) {
    const borrador = contratoDeSolicitud(base, perfil)
    const origen = operacion?.fuente
    cuerpo = <>
      {solicitud && borrador && <div className="px-5 pt-4"><Label htmlFor="f5-motivo">Motivo de la actualización, sin datos personales</Label>
        <Input id="f5-motivo" value={motivo} onChange={e => setMotivo(e.target.value)} maxLength={500} /></div>}
      {alerta && <div className="px-5 pt-3">{alerta}</div>}
      <ContratoNuevo key={`${perfil}:${solicitud?.revision_datos ?? 'nuevo'}`} clienteId={perfil} clienteNombre={ficha.persona.nombre ?? ''}
        ventaCruzada={llaveVenta}
        indicadorPaso={mostrarPasos ? <PasosAcceso actual={2} /> : undefined}
        borradorLocal={mostrarPasos ? borradorCondiciones : undefined}
        onBorradorLocal={mostrarPasos && intento && solicitud ? condiciones => {
          try {
            guardarBorradorCondiciones(actor, persona, origenIntento, intento.clave, solicitud.revision_datos, condiciones)
            estadoBorrador(false)
          } catch {estadoBorrador(true)}
        } : undefined}
        leadOrigenId={origenLead?.tipoDocumento === 'DNI' ? origenLead.id : undefined} condicionesIniciales={origenLead?.condiciones}
        {...(origenLead ? {montoSugerido: origenLead.monto, monedaSugerida: origenLead.moneda} : {})}
        categoriaFija={(operacion?.tipo !== 'reinversion' ? operacion?.tipo : undefined) ?? borrador?.categoria ?? 'nuevo'} borrador={borrador}
        {...(origen && operacion?.tipo === 'renovacion' ? {renovacionOrigen: {id: origen.fuente_id, numeroContrato: origen.numero ?? '',
          capital: origen.capital, moneda: origen.moneda, fechaVencimiento: origen.vence_en ?? ''}} : {})}
        {...(origen?.contrato && operacion?.tipo === 'upgrade' ? {contratosActivos: [{id: origen.fuente_id, numero_contrato: origen.numero ?? '',
          capital: origen.capital, moneda: origen.moneda, tasa_anual: origen.contrato.tasa_anual, fecha_vencimiento: origen.vence_en ?? ''}]} : {})}
        {...(origenClienteExistente ? {contratosActivos: (upgradeQ.data ?? []).map(c => ({id: c.contrato_id, numero_contrato: c.numero_contrato,
          capital: c.capital, moneda: c.moneda, tasa_anual: c.tasa_anual, fecha_vencimiento: c.fecha_vencimiento}))} : {})}
        analistas={origenClienteExistente ? [{perfil_id: actor, nombre_completo: 'Tú, quien registra la venta'}]
          : ficha.persona.responsable_id ? [{perfil_id: ficha.persona.responsable_id, nombre_completo: ficha.persona.responsable_nombre ?? 'Responsable actual'}] : []}
        analistaInicial={origenClienteExistente ? actor : ficha.persona.responsable_id} onCreado={() => {}} onOmitir={cerrar}
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
  else cuerpo = <>{cabecera('Revisar inversión')}{mostrarPasos && <PasosAcceso actual={3} />}<DialogBody className="space-y-4">
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
        if (!cerro.current) {setConfirmacion(resultado); notificar(resultado)}
      })}>{ocupado ? 'Confirmando…' : 'Confirmar inversión'}</Button>
    </div>
    <Button variant="ghost" disabled={ocupado} onClick={() => void ejecutar(async () => {if (intento) recibir(await consultarSolicitudInversion(intento.clave))})}>Actualizar revisión</Button>
    {alerta}
    <p className="text-xs text-muted-foreground [overflow-wrap:anywhere]">Referencia: {intento?.clave}. Revisión {solicitud?.revision_datos}.</p>
  </DialogBody></>
  return <Dialog open onClose={cerrar} ariaLabel="Nueva inversión" className={empresa === 'avance' && !perfil ? 'w-[620px]' : 'w-[760px]'}>
    {verificacionPendiente && <div className="space-y-2 border-b border-border px-5 py-3">
      <p role="alert" className="text-sm">No pudimos actualizar los permisos. Conservamos tus datos; vuelve a verificarlos para continuar.</p>
      <Button variant="outline" disabled={fichaQ.isFetching} onClick={() => void fichaQ.refetch()}>Verificar y continuar</Button>
    </div>}
    {borradorSinGuardar && <p role="alert" className="border-b border-border px-5 py-2 text-xs text-destructive-text">
      No se están guardando los cambios recientes en esta pestaña. Mantén abierto el formulario o vuelve a intentar.
    </p>}
    <fieldset disabled={verificacionPendiente} className="contents">{cuerpo}</fieldset>
    {solicitud?.estado === 'preparada' && !confirmacion && <div className="space-y-2 border-t border-border px-5 py-3">
      {cancelando ? <>
        <p className="text-sm">Se cancelará esta solicitud para poder elegir otra empresa o moneda. El lead conservará su etapa y los accesos ya completados se conservarán.</p>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" disabled={ocupado || verificacionPendiente} onClick={() => void ejecutar(async () => {
            recibir(await cancelarSolicitudInversion(solicitud.solicitud_id, solicitud.revision_datos)); setCancelando(false)
          })}>Confirmar cancelación</Button>
          <Button variant="ghost" disabled={ocupado} onClick={() => setCancelando(false)}>Conservar solicitud</Button>
        </div>
      </> : <Button variant="ghost" disabled={ocupado || verificacionPendiente} onClick={() => setCancelando(true)}>Cancelar solicitud</Button>}
    </div>}
    {confirmarCierreSinGuardar && <p role="alert" className="border-t border-border px-5 py-2 text-xs text-destructive-text">
      No se pudo guardar lo último que escribiste en esta pestaña. Si cierras, perderás esos cambios.
    </p>}
    <DialogFooter><Button variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal" disabled={ocupado} onClick={cerrar}>
      {confirmacion ? (origenClienteExistente ? 'Cerrar' : 'Volver a la ficha') : confirmarCierreSinGuardar ? 'Cerrar sin guardar' : 'Cerrar y continuar después'}
    </Button></DialogFooter>
  </Dialog>
}

function PasosAcceso({actual}: {actual: 1 | 2 | 3}) {
  const pasos = ['Acceso', 'Condiciones', 'Revisión'] as const
  return <nav aria-label="Progreso de primera inversión Avance" className="border-b border-border px-5 py-3">
    <p className="mb-2 text-xs text-muted-foreground">Paso {actual} de 3</p>
    <ol className="grid grid-cols-3 gap-2">
      {pasos.map((nombre, indice) => {
        const numero = (indice + 1) as 1 | 2 | 3
        return <li key={nombre} aria-current={actual === numero ? 'step' : undefined}
          className={`flex min-w-0 items-center gap-1.5 text-[11px] sm:text-xs ${actual === numero ? 'font-semibold text-foreground' : 'text-muted-foreground'}`}>
          <span aria-hidden="true" className={`flex size-5 shrink-0 items-center justify-center rounded-full text-[10px] ${actual >= numero ? 'bg-primary text-primary-foreground' : 'border border-border'}`}>{numero}</span>
          <span className="truncate">{nombre}</span>
        </li>
      })}
    </ol>
  </nav>
}

function AltaAvance({actor, persona, origen, solicitud, inicial, correo, telefono, ocupado, onEstadoBorrador, onContinuar}: {
  actor: string; persona: string; origen?: OrigenIntento; solicitud: string | null; inicial?: AltaPortal | undefined
  correo: string; telefono: string; ocupado: boolean
  onEstadoBorrador: (sinGuardar: boolean) => void; onContinuar: (datos: AltaPortal) => Promise<void>
}) {
  const [inicio] = useState(() => {
    const base: DatosBorradorAcceso = inicial
      ? {apellidos: inicial.apellidos, nombres: inicial.nombres, correo: inicial.correo,
          telefono: inicial.telefono, domicilio: inicial.domicilio}
      : {apellidos: '', nombres: '', correo, telefono, domicilio: ''}
    try {
      const recuperado = leerBorradorAcceso(actor, persona, origen, solicitud)
      return {datos: recuperado ?? base, estado: recuperado ? 'recuperado' : 'vacio'} as const
    } catch {return {datos: base, estado: 'error'} as const}
  })
  const [datos, setDatos] = useState<DatosBorradorAcceso>(inicio.datos)
  const [estado, setEstado] = useState<'vacio' | 'guardado' | 'recuperado' | 'error'>(inicio.estado)
  const [errores, setErrores] = useState<Partial<Record<keyof DatosBorradorAcceso, string>>>({})
  const cambiar = (campo: keyof DatosBorradorAcceso, valor: string) => {
    const nuevos = {...datos, [campo]: valor}
    setDatos(nuevos)
    setErrores(actual => ({...actual, [campo]: undefined}))
    try {
      guardarBorradorAcceso(actor, persona, origen, solicitud, nuevos)
      setEstado('guardado'); onEstadoBorrador(false)
    } catch {
      setEstado('error'); onEstadoBorrador(true)
    }
  }
  const campo = (nombre: keyof DatosBorradorAcceso, etiqueta: string) => {
    const ayuda = nombre === 'correo' ? 'f5-alta-correo-ayuda' : nombre === 'domicilio' ? 'f5-alta-domicilio-ayuda' : null
    const errorId = errores[nombre] ? `f5-alta-${nombre}-error` : null
    return <div key={nombre} className="min-w-0 space-y-1">
      <Label htmlFor={`f5-alta-${nombre}`}>{etiqueta}</Label>
      <Input id={`f5-alta-${nombre}`} type={nombre === 'correo' ? 'email' : nombre === 'telefono' ? 'tel' : 'text'} required
        autoComplete={{apellidos: 'family-name', nombres: 'given-name', correo: 'email', telefono: 'tel', domicilio: 'street-address'}[nombre]}
        inputMode={nombre === 'correo' ? 'email' : nombre === 'telefono' ? 'tel' : undefined}
        value={datos[nombre]} disabled={ocupado} maxLength={nombre === 'domicilio' ? 300 : 180}
        aria-invalid={Boolean(errores[nombre])} aria-describedby={[ayuda, errorId].filter(Boolean).join(' ') || undefined}
        onChange={e => cambiar(nombre, e.target.value)} />
      {nombre === 'correo' && <p id="f5-alta-correo-ayuda" className="text-xs text-muted-foreground">Con este correo el cliente ingresará a Avance. Confírmalo antes de crear el acceso.</p>}
      {nombre === 'domicilio' && <p id="f5-alta-domicilio-ayuda" className="text-xs text-muted-foreground">Dirección que figurará en el contrato. Incluye calle y número, lote o manzana; distrito y ciudad. Ej.: Av. Javier Prado Este 123, San Isidro, Lima.</p>}
      {errores[nombre] && <p id={errorId!} role="alert" className="text-xs text-destructive-text">{errores[nombre]}</p>}
    </div>
  }
  return <form className="space-y-5" noValidate onSubmit={e => {
    e.preventDefault()
    const nombres = datos.nombres.trim(), apellidos = datos.apellidos.trim()
    const correoValidado = datos.correo.trim(), telefonoValidado = datos.telefono.trim()
    const domicilio = validarDomicilioLegal(datos.domicilio)
    const nuevosErrores: typeof errores = {}
    if (!apellidos) nuevosErrores.apellidos = 'Completa los apellidos del cliente.'
    if (!nombres) nuevosErrores.nombres = 'Completa los nombres del cliente.'
    if (!CORREO_RE.test(correoValidado)) nuevosErrores.correo = 'Escribe un correo de acceso válido.'
    if (!telefonoValidado) nuevosErrores.telefono = 'Completa el teléfono del cliente.'
    if (!domicilio.ok) nuevosErrores.domicilio = domicilio.error
    setErrores(nuevosErrores)
    const primero = Object.keys(nuevosErrores)[0]
    if (primero) {document.getElementById(`f5-alta-${primero}`)?.focus(); return}
    if (!domicilio.ok) return
    void onContinuar({...datos, nombres, apellidos, correo: correoValidado, telefono: telefonoValidado,
      domicilio: domicilio.valor, nombre_completo: `${nombres} ${apellidos}`})
  }}>
    <fieldset className="space-y-2"><legend className="text-sm font-semibold">Identidad</legend>
      <div className="grid gap-3 sm:grid-cols-2">{campo('apellidos', 'Apellidos')}{campo('nombres', 'Nombres')}</div>
    </fieldset>
    <fieldset className="space-y-2"><legend className="text-sm font-semibold">Contacto y acceso</legend>
      <div className="grid gap-3 sm:grid-cols-2">{campo('correo', 'Correo de acceso Avance')}{campo('telefono', 'Teléfono')}</div>
    </fieldset>
    <fieldset className="space-y-2"><legend className="text-sm font-semibold">Domicilio para el contrato</legend>
      {campo('domicilio', 'Domicilio legal')}
    </fieldset>
    {estado === 'error' && <p role="alert" className="text-xs text-destructive-text">No se pudo guardar el borrador en esta pestaña. Conserva el formulario abierto o vuelve a intentar escribir.</p>}
    {estado === 'recuperado' && <p role="status" className="text-xs text-muted-foreground">Recuperamos lo que escribiste en esta pestaña.</p>}
    {estado === 'guardado' && <p role="status" className="text-xs text-muted-foreground">Borrador guardado en esta pestaña. Puedes cerrar y continuar después.</p>}
    <Button type="submit" className="w-full" disabled={ocupado}>Revisar acceso Avance</Button>
  </form>
}
export function InversionCooperativa({datos, ocupado, correccion, motivo, onMotivo, onGuardar}: {
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
        <Select id="f5-moneda" value={moneda} onChange={e => setMoneda(e.target.value as Moneda)} disabled={ocupado || correccion}>
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
export function ResumenRevision({datos}: {datos: DatosInversion}) {
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
