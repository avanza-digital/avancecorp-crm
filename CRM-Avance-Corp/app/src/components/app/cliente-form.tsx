// Formulario de CLIENTE del portal dentro del CRM (alta + corregir) — espejo
// del modal #modalCliente del panel del analista (public_html/admin/analista.html
// + js/admin/analista.js), campo por campo y validación por validación.
//
// Flujo del ALTA: la edge crear-cliente crea Auth +
//   perfil y cuentas bancarias en una transacción y manda el correo REAL de
//   bienvenida (clave temporal = documento con ceros a 8), vía crearClientePortal.
//   Antes eran DOS pasos y los bancarios iban en un UPDATE posterior: si ese paso
//   fallaba quedaba un cliente real, con su correo ya enviado, sin cuenta donde
//   cobrar el interés. La regla "al menos una cuenta" ahora la exige el servidor.
// Flujo de CORREGIR: obtenerClienteDetalle precarga TODO. El analista usa UPDATE
//   por RLS con ventana de 5 h; Gerencia usa una RPC con allowlist que preserva
//   la identidad técnica, el rol y el analista responsable. Un rechazo devuelve
//   false o error y JAMÁS se dice "guardado".
//
// La lógica pura (validaciones y catálogo de bancos) vive
// en lib/cliente-form-logica; aquí solo el estado y el pintado.
import { useEffect, useRef, useState } from 'react'
import { Pencil, RotateCcw, UserRoundPlus } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import {
  actualizarClientePortal,
  corregirCorreoClienteAdmin,
  corregirDocumentoClienteAdmin,
  crearClientePortal,
  registrarCuentaCliente,
  mensajeDeError,
  CrmApiError,
} from '@/data/crm-api'
import { useClienteDetalle, useCuentasBancariasCliente } from '@/data/crm-queries'
import { SeccionesBancarias } from '@/components/app/secciones-bancarias'
import { BotonGuardar } from '@/components/app/boton-guardar'
import type { ClienteDetalle, CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import { useVentana } from '@/lib/ventana'
import { useAuth } from '@/lib/auth-context'
import { puedeCorregirCorreoCliente, puedeCorregirDocumentoCliente } from '@/lib/roles'
import {
  SECCION_BANCARIA_VACIA,
  validarClienteForm,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'

// Mensajes de negocio del contrato del traspaso (no cambiarlos a la ligera:
// los E2E y el equipo los reconocen tal cual).
const MSG_VENTANA_VENCIDA =
  'La ventana de corrección venció: los cambios NO se guardaron. Pide el cambio a administración.'

/** Marca «el banner inline ya tiene el mensaje»: el catch no debe pisarlo con
 *  el genérico; solo re-lanza para el estado de error del BotonGuardar. */
class ErrorYaMostrado extends Error {}

const cuentaEnmascarada = (valor: string) => `••••${valor.slice(-4)}`
const origenCuenta = (origen: CuentaBancariaSeleccionable['origen']) => ({
  perfil: 'Perfil migrado', contrato: 'CRM / contrato', portal: 'Ficha de cliente',
})[origen]
const fechaCuenta = (valor: string | null) => valor
  ? new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', dateStyle: 'medium' }).format(new Date(valor))
  : 'Fecha no disponible'


export interface ClienteFormProps {
  modo: 'crear' | 'corregir'
  /** Obligatorio en modo 'corregir' (id de public.perfiles). */
  clienteId?: string
  /** Recibe el id del cliente creado/corregido (para encadenar el contrato). */
  onListo: (id: string) => void
  onCerrar: () => void
  /**
   * Notifica cuando hay un envío en vuelo. El caller DEBE bloquear el cierre del
   * Dialog mientras sea true: Radix cierra con Esc/overlay incondicionalmente, y
   * un cierre a mitad del alta perdería el resultado de una operación que ya
   * está corriendo en el servidor (cuenta creada + correo de bienvenida).
   */
  onEnviandoCambio?: (enviando: boolean) => void
  deshabilitado?: boolean
  sinLimiteVentana?: boolean
}

export function ClienteForm({ modo, clienteId, onListo, onCerrar, onEnviandoCambio, deshabilitado = false, sinLimiteVentana = false }: ClienteFormProps) {
  const esCorregir = modo === 'corregir'
  const { yo } = useAuth()
  const esGerencia = yo?.rol === 'gerencia'
  const puedeRegistrarBanca = !esCorregir || esGerencia
    || ['admin', 'superadmin', 'operaciones', 'analista'].includes(yo?.rol_portal ?? '')
  const puedeCorregirDocumento = esCorregir && puedeCorregirDocumentoCliente(yo)
  // El correo es la CREDENCIAL de acceso, no un dato de contacto: puerta mas
  // estrecha que la del documento (solo superadmin).
  const puedeCorregirCorreo = esCorregir && puedeCorregirCorreoCliente(yo)

  // Identidad
  const [apellidos, setApellidos] = useState('')
  const [nombres, setNombres] = useState('')
  const [tipoDoc, setTipoDoc] = useState<TipoDocumento>('DNI')
  const [documento, setDocumento] = useState('')
  const [motivoDocumento, setMotivoDocumento] = useState('')
  const [motivoCorreo, setMotivoCorreo] = useState('')
  const [telefono, setTelefono] = useState('')
  const [correo, setCorreo] = useState('')
  const [domicilio, setDomicilio] = useState('')
  // En corrección, campos vacíos significan «registrar otra cuenta» opcional.
  const [pen, setPen] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [usd, setUsd] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  // Corregir: detalle cargado (habilita legacy/grandfathering y la cuenta regresiva)
  const [detalle, setDetalle] = useState<ClienteDetalle | null>(null)
  // Envío
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  const ventana = useVentana(esCorregir && !esGerencia && !sinLimiteVentana ? detalle?.creado_en : null)

  // PRECARGA vía caché (clave clienteDetalle(id), staleTime 0): el UPDATE de
  // corregir viaja con el set COMPLETO de campos, así que la precarga es
  // prerequisito del guardado y revalida SIEMPRE al abrir — jamás se siembra
  // el formulario con una copia cacheada que podría estar vieja.
  const qDetalle = useClienteDetalle(clienteId ?? '', esCorregir && !!clienteId)
  const ledgerRemotoHabilitado =
    esCorregir &&
    !!clienteId &&
    qDetalle.isSuccess &&
    !qDetalle.isFetching &&
    qDetalle.isFetchedAfterMount &&
    qDetalle.data.cuentas_bancarias_visibles
  // El ledger muestra todas las cuentas activas; el editor de alta de otra
  // cuenta permanece vacío y escribe únicamente mediante la RPC versionada.
  const qCuentasPen = useCuentasBancariasCliente(clienteId ?? '', 'PEN', ledgerRemotoHabilitado)
  const qCuentasUsd = useCuentasBancariasCliente(clienteId ?? '', 'USD', ledgerRemotoHabilitado)
  // Nunca derivar validaciones ni pintar números desde el `data` vivo de React
  // Query: puede contener una copia sembrada antes de montar el diálogo. Solo
  // promovemos el par PEN/USD cuando AMBAS respuestas terminaron después del
  // mount y para el cliente que sigue abierto.
  const [cuentasConfirmadas, setCuentasConfirmadas] = useState<{
    clienteId: string
    pen: CuentaBancariaSeleccionable[]
    usd: CuentaBancariaSeleccionable[]
  } | null>(null)

  useEffect(() => {
    setCuentasConfirmadas(null)
  }, [clienteId])

  useEffect(() => {
    if (!clienteId || !ledgerRemotoHabilitado) return
    if (!qCuentasPen.isSuccess || qCuentasPen.isFetching || !qCuentasPen.isFetchedAfterMount) return
    if (!qCuentasUsd.isSuccess || qCuentasUsd.isFetching || !qCuentasUsd.isFetchedAfterMount) return
    setCuentasConfirmadas({ clienteId, pen: qCuentasPen.data, usd: qCuentasUsd.data })
  }, [
    clienteId,
    ledgerRemotoHabilitado,
    qCuentasPen.isSuccess,
    qCuentasPen.isFetching,
    qCuentasPen.isFetchedAfterMount,
    qCuentasPen.data,
    qCuentasUsd.isSuccess,
    qCuentasUsd.isFetching,
    qCuentasUsd.isFetchedAfterMount,
    qCuentasUsd.data,
  ])

  useEffect(() => {
    const capacidadRevocada =
      qDetalle.isSuccess &&
      !qDetalle.isFetching &&
      qDetalle.isFetchedAfterMount &&
      !qDetalle.data.cuentas_bancarias_visibles
    if (capacidadRevocada || qCuentasPen.isError || qCuentasUsd.isError) {
      setCuentasConfirmadas(null)
    }
  }, [
    qDetalle.isSuccess,
    qDetalle.isFetching,
    qDetalle.isFetchedAfterMount,
    qDetalle.data,
    qCuentasPen.isError,
    qCuentasUsd.isError,
  ])
  // La identidad se siembra una vez desde una lectura fresca. Los inputs de
  // nueva cuenta quedan vacíos; un refetch no pisa lo que el usuario escribe.
  const sembrado = useRef(false)
  useEffect(() => {
    if (!esCorregir || sembrado.current) return
    if (!qDetalle.isSuccess || qDetalle.isFetching || !qDetalle.isFetchedAfterMount) return
    const d = qDetalle.data
    sembrado.current = true
    // Identidad y contacto compartidos por perfiles; cuentas del ledger aparte.
    setApellidos(d.apellidos ?? '')
    setNombres(d.nombres ?? '')
    setTipoDoc(d.tipo_documento)
    setDocumento(d.dni ?? '')
    setTelefono(d.telefono ?? '')
    setCorreo(d.correo ?? '')
    setDomicilio(d.domicilio ?? '')
    setDetalle(d)
  }, [esCorregir, qDetalle.isSuccess, qDetalle.isFetching, qDetalle.isFetchedAfterMount, qDetalle.data])

  // Derivados del ledger (crm.cuentas_bancarias) — toda cuenta activa es visible.
  const cuentasConfirmadasVigentes =
    cuentasConfirmadas?.clienteId === clienteId ? cuentasConfirmadas : null
  const cuentasLedger =
    esCorregir && ledgerRemotoHabilitado && cuentasConfirmadasVigentes != null
    ? [...cuentasConfirmadasVigentes.pen, ...cuentasConfirmadasVigentes.usd]
    : []
  const cuentasVigentes = cuentasLedger
  // Si falla una moneda, no se habilita el registro bancario a ciegas.
  const avisoLedger =
    esCorregir &&
    detalle != null &&
    ledgerRemotoHabilitado &&
    (qCuentasPen.isError || qCuentasUsd.isError)
  // No validar contra «cero cuentas» mientras las dos monedas aún se están
  // revalidando: sería un falso negativo y tentaría a usar la caché para evitarlo.
  // Un fallo muestra aviso; la identidad puede seguir guardándose sin banca.
  const ledgerPendiente =
    esCorregir &&
    detalle != null &&
    ledgerRemotoHabilitado &&
    cuentasConfirmadasVigentes == null &&
    !qCuentasPen.isError &&
    !qCuentasUsd.isError
  const reintentarCuentasLedger = () => {
    if (qCuentasPen.isError) void qCuentasPen.refetch()
    if (qCuentasUsd.isError) void qCuentasUsd.refetch()
  }

  // El servidor revalida todo dato antes de persistir.
  const errorCarga = !esCorregir
    ? null
    : !clienteId
      ? 'Falta el id del cliente a corregir.'
      : detalle == null && qDetalle.isError
        ? mensajeDeError(qDetalle.error, 'No se pudo cargar el cliente.')
        : null
  const cargando = esCorregir && detalle == null && errorCarga == null

  const guardar = async () => {
    if (deshabilitado) throw new ErrorYaMostrado('Vuelve a comprobar los permisos antes de guardar.')
    if (enviando || ledgerPendiente) return // guards anti doble-submit y contra una validación incompleta
    setError(null)
    const r = validarClienteForm(
      { apellidos, nombres, tipo_documento: tipoDoc, documento, telefono, correo, domicilio, pen, usd },
      esCorregir ? detalle : null,
      // En corrección se pueden guardar identidad/contacto sin agregar cuenta.
      { cuentaEnLedger: esCorregir },
    )
    if (!r.ok) {
      setError(r.error)
      // El rechazo alimenta el estado de error del BotonGuardar; el detalle
      // del motivo ya quedó en el banner inline (setError).
      throw new Error(r.error)
    }
    const c = r.cliente
    const cuentasNuevas = [
      ...([pen.banco, pen.tipo_cuenta, pen.numero_cuenta, pen.cci].some((valor) => valor.trim()) || pen.titular_distinto
        ? [{ moneda: 'PEN' as const, datos: pen }] : []),
      ...([usd.banco, usd.tipo_cuenta, usd.numero_cuenta, usd.cci].some((valor) => valor.trim()) || usd.titular_distinto
        ? [{ moneda: 'USD' as const, datos: usd }] : []),
    ]
    if (esCorregir && cuentasNuevas.length && !puedeRegistrarBanca) {
      const mensaje = 'Solo Analistas, Gerencia o Administración pueden registrar cuentas bancarias.'
      setError(mensaje)
      throw new ErrorYaMostrado(mensaje)
    }
    if (esCorregir && cuentasNuevas.length && (!ledgerRemotoHabilitado || cuentasConfirmadasVigentes == null)) {
      const mensaje = 'Espera a que carguen las cuentas vigentes antes de registrar otra.'
      setError(mensaje)
      throw new ErrorYaMostrado(mensaje)
    }
    const documentoCambio = esCorregir && detalle !== null && (
      c.tipo_documento !== detalle.tipo_documento || c.dni !== (detalle.dni ?? '')
    )
    if (documentoCambio && !puedeCorregirDocumento) {
      const mensaje = 'Solo un usuario administrador puede corregir el documento de un cliente.'
      setError(mensaje)
      throw new ErrorYaMostrado(mensaje)
    }
    const motivoDocumentoLimpio = motivoDocumento.trim()
    if (documentoCambio && (motivoDocumentoLimpio.length < 3 || motivoDocumentoLimpio.length > 500)) {
      const mensaje = 'Indica un motivo de entre 3 y 500 caracteres para corregir el documento.'
      setError(mensaje)
      throw new ErrorYaMostrado(mensaje)
    }
    const correoCambio = esCorregir && detalle !== null
      && c.correo.toLowerCase() !== (detalle.correo ?? '').trim().toLowerCase()
    if (correoCambio && !puedeCorregirCorreo) {
      const mensaje = 'Solo un administrador puede corregir el correo de acceso de un cliente.'
      setError(mensaje)
      throw new ErrorYaMostrado(mensaje)
    }
    const motivoCorreoLimpio = motivoCorreo.trim()
    if (correoCambio && (motivoCorreoLimpio.length < 3 || motivoCorreoLimpio.length > 500)) {
      const mensaje = 'Indica un motivo de entre 3 y 500 caracteres para cambiar el correo de acceso.'
      setError(mensaje)
      throw new ErrorYaMostrado(mensaje)
    }
    setEnviando(true)
    onEnviandoCambio?.(true)
    try {
      if (esCorregir) {
        // Analista: UPDATE directo y ventana RLS de 5 h. Gerencia: RPC acotada
        // sin esa ventana, pero sin capacidad de tocar rol, estado ni analista
        // responsable.
        const guardo = await actualizarClientePortal(
          clienteId as string,
          {
            nombre_completo: c.nombre_completo,
            telefono: c.telefono,
            domicilio: c.domicilio,
            // En un legacy sin separar (ambos vacíos) van null y se conserva su
            // nombre_completo original (rama esLegacySinSeparar de la validación).
            apellidos: c.apellidos,
            nombres: c.nombres,
            actualizado_en: new Date().toISOString(),
          },
          esGerencia,
        )
        if (!guardo) {
          setError(MSG_VENTANA_VENCIDA)
          throw new ErrorYaMostrado(MSG_VENTANA_VENCIDA)
        }
        if (documentoCambio) {
          try {
            await corregirDocumentoClienteAdmin(
              clienteId as string,
              c.tipo_documento,
              c.dni,
              motivoDocumentoLimpio,
            )
          } catch (e) {
            const mensaje = `Los demás datos se guardaron, pero el documento no pudo corregirse: ${mensajeDeError(e, 'No se pudo corregir el documento.')}`
            setError(mensaje)
            throw new ErrorYaMostrado(mensaje)
          }
        }
        if (correoCambio) {
          try {
            await corregirCorreoClienteAdmin(
              clienteId as string,
              c.correo,
              motivoCorreoLimpio,
            )
          } catch (e) {
            const mensaje = `Los demás datos se guardaron, pero el correo de acceso no pudo cambiarse: ${mensajeDeError(e, 'No se pudo corregir el correo.')}`
            setError(mensaje)
            throw new ErrorYaMostrado(mensaje)
          }
        }
        let registradas = 0
        for (const nueva of cuentasNuevas) {
          try {
            await registrarCuentaCliente(clienteId as string, nueva.moneda, nueva.datos)
            registradas++
          } catch (e) {
            const mensaje = registradas
              ? 'Los datos personales y una cuenta se guardaron; la otra requiere reintento. Vuelve a abrir la ficha.'
              : `Los datos personales se guardaron. ${mensajeDeError(e, 'No se pudo registrar la cuenta.')}`
            setError(mensaje)
            throw new ErrorYaMostrado(mensaje)
          }
        }
        toast.success(
          correoCambio
            ? 'Datos corregidos. El cliente entra al portal con su correo nuevo.'
            : 'Datos del cliente corregidos.',
        )
        onListo(clienteId as string)
      } else {
        // La Edge valida los bancarios y crea el perfil y sus cuentas en una
        // transaccion de BD; Auth y el correo se coordinan fuera de ella. Las
        // secciones van CRUDAS: la validación que manda es la del servidor.
        const alta = await crearClientePortal({
          email: c.correo,
          nombre_completo: c.nombre_completo,
          apellidos: c.apellidos ?? '',
          nombres: c.nombres ?? '',
          dni: c.dni,
          telefono: c.telefono,
          domicilio: c.domicilio,
          tipo_documento: c.tipo_documento,
          bancarios: { pen, usd },
        })
        toast.success(`Cliente "${c.nombre_completo}" creado. Ahora crea su contrato.`)
        onListo(alta.userId)
      }
    } catch (e) {
      // Mensajes de la edge/RPC ya vienen en es-PE vía CrmApiError (409 documento
      // duplicado, 400 documento inválido, correo ya registrado, etc.).
      if (!(e instanceof ErrorYaMostrado)) {
        setError(e instanceof CrmApiError ? e.message : 'Ocurrió un error. Inténtalo de nuevo.')
      }
      throw e // re-lanza para que el BotonGuardar muestre «Reintentar»
    } finally {
      setEnviando(false)
      onEnviandoCambio?.(false)
    }
  }

  const encabezado = (
    <DialogHeader>
      <DialogTitle className="flex items-center gap-2">
        {esCorregir
          ? <Pencil className="size-4 text-primary" aria-hidden />
          : <UserRoundPlus className="size-4 text-primary" aria-hidden />}
        {esCorregir ? 'Corregir cliente' : 'Nuevo cliente'}
      </DialogTitle>
      {esCorregir && detalle && !esGerencia && !puedeCorregirDocumento && (
        // Cuenta regresiva visual; la ventana REAL la decide el servidor, por eso
        // el guardado no se bloquea aquí (espejo del portal: el modal no gatea).
        <p className={`text-[11px] font-semibold ${ventana.vigente ? 'text-primary' : 'text-destructive'}`}>
          Ventana de corrección: {sinLimiteVentana ? 'Corrección administrativa' : ventana.texto}
        </p>
      )}
      {esCorregir && detalle && puedeCorregirDocumento && (
        <p className="text-[11px] font-semibold text-primary">
          Corrección administrativa auditada
        </p>
      )}
      {esCorregir && detalle && esGerencia && !puedeCorregirDocumento && (
        <p className="text-[11px] font-semibold text-primary">
          Corrección autorizada por Gerencia
        </p>
      )}
    </DialogHeader>
  )

  // La Edge registra perfil y cuentas en una transacción antes del correo.

  if (esCorregir && cargando) {
    return (
      <>
        {encabezado}
        <DialogBody>
          <p className="py-8 text-center text-sm text-muted-foreground">Cargando cliente…</p>
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" size="sm" onClick={onCerrar}>Cancelar</Button>
        </DialogFooter>
      </>
    )
  }

  // El detalle se revalida primero. Solo la capacidad específica del ledger
  // habilita PEN/USD; si esas consultas ya fallaron en este montaje, también se
  // reintentan para no conservar una degradación muda.
  const reintentarCarga = () => {
    void qDetalle.refetch()
    if (qCuentasPen.isError) void qCuentasPen.refetch()
    if (qCuentasUsd.isError) void qCuentasUsd.refetch()
  }

  if (esCorregir && errorCarga) {
    return (
      <>
        {encabezado}
        <DialogBody className="space-y-3">
          <p role="alert" className="text-xs font-semibold text-destructive">{errorCarga}</p>
        </DialogBody>
        <DialogFooter className="justify-between">
          <Button variant="ghost" size="sm" onClick={onCerrar}>Cerrar</Button>
          <Button variant="outline" size="sm" onClick={reintentarCarga}>
            <RotateCcw /> Reintentar
          </Button>
        </DialogFooter>
      </>
    )
  }

  const reglaDoc = TIPOS_DOCUMENTO[tipoDoc]
  const documentoEditado = esCorregir && detalle !== null && (
    tipoDoc !== detalle.tipo_documento || documento.trim() !== (detalle.dni ?? '')
  )
  // Se compara en minusculas y sin espacios porque asi lo normalizan la RPC y
  // Auth: «  A@B.com » y «a@b.com» son el MISMO correo, y pedir motivo por esa
  // diferencia seria pedirlo por nada.
  const correoEditado = esCorregir && detalle !== null
    && correo.trim().toLowerCase() !== (detalle.correo ?? '').trim().toLowerCase()
  const esLegacySinSeparar = esCorregir && detalle !== null
    && !detalle.apellidos && !detalle.nombres && !!detalle.nombre_completo

  return (
    <>
      {encabezado}
      <DialogBody className="max-h-[65vh] space-y-3 overflow-y-auto">
        {/* Error arriba, como el #modalClienteError del portal. */}
        {error && (
          <p role="alert" className="rounded-lg bg-destructive/10 px-3 py-2 text-xs font-semibold text-destructive">
            {error}
          </p>
        )}

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cf-apellidos">Apellidos *</Label>
            <Input
              id="cf-apellidos"
              value={apellidos}
              onChange={(e) => setApellidos(e.target.value)}
              maxLength={120}
              placeholder="DIAZ HUAYTA"
              style={{ textTransform: 'uppercase' }}
              disabled={enviando}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cf-nombres">Nombres *</Label>
            <Input
              id="cf-nombres"
              value={nombres}
              onChange={(e) => setNombres(e.target.value)}
              maxLength={120}
              placeholder="HUGO GUALBERTO"
              style={{ textTransform: 'uppercase' }}
              disabled={enviando}
            />
          </div>
        </div>
        {esLegacySinSeparar && (
          // Cliente registrado ANTES de la separación apellidos/nombres: se
          // muestra su nombre original para repartirlo a mano (o dejar ambos
          // vacíos y conservarlo tal cual).
          <p className="text-[11px] text-muted-foreground">
            Nombre registrado anteriormente:{' '}
            <b className="text-foreground">{detalle?.nombre_completo}</b>
          </p>
        )}

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cf-tipo-doc">Tipo de documento *</Label>
            {/* Opciones desde la tabla canónica — nunca <option> a mano. */}
            <Select
              id="cf-tipo-doc"
              value={tipoDoc}
              onChange={(e) => setTipoDoc(e.target.value as TipoDocumento)}
              disabled={enviando || (esCorregir && !puedeCorregirDocumento)}
            >
              {TIPOS_DOCUMENTO_K.map((k) => (
                <option key={k} value={k}>{TIPOS_DOCUMENTO[k].etiqueta}</option>
              ))}
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cf-documento">Documento *</Label>
            {/* Tope ÚNICO de 12 (no por tipo) a propósito: un tope de 8 en modo
                DNI truncaba EN SILENCIO un CE pegado, y el truncado validaba. */}
            <Input
              id="cf-documento"
              value={documento}
              onChange={(e) => setDocumento(e.target.value)}
              maxLength={12}
              inputMode={reglaDoc.inputmode}
              placeholder={reglaDoc.placeholder}
              style={{ textTransform: reglaDoc.mayusculas ? 'uppercase' : 'none' }}
              autoComplete="off"
              aria-describedby="cf-documento-hint"
              disabled={enviando || (esCorregir && !puedeCorregirDocumento)}
            />
            <p id="cf-documento-hint" className="text-[10px] text-muted-foreground">
              {esCorregir
                ? puedeCorregirDocumento
                  ? 'Puedes corregirlo como administrador; el motivo quedará registrado en auditoría.'
                  : 'Solo un usuario administrador puede corregirlo.'
                : reglaDoc.regla}
            </p>
          </div>
        </div>

        {puedeCorregirDocumento && documentoEditado && (
          <div className="space-y-1.5">
            <Label htmlFor="cf-documento-motivo">Motivo de la corrección *</Label>
            <Textarea
              id="cf-documento-motivo"
              value={motivoDocumento}
              onChange={(e) => setMotivoDocumento(e.target.value)}
              rows={2}
              minLength={3}
              maxLength={500}
              placeholder="Por qué se corrige el documento"
              disabled={enviando}
            />
            <p className="text-[10px] text-muted-foreground">
              Entre 3 y 500 caracteres. Se guardará en la auditoría administrativa.
            </p>
          </div>
        )}

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cf-telefono">Teléfono</Label>
            <Input
              id="cf-telefono"
              type="tel"
              value={telefono}
              onChange={(e) => setTelefono(e.target.value)}
              maxLength={20}
              disabled={enviando}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cf-correo">
              {esCorregir && !puedeCorregirCorreo
                ? 'Correo electrónico (cuenta de acceso)'
                : 'Correo electrónico *'}
            </Label>
            {/* `readOnly` y NO `disabled` cuando no se puede editar: un campo
                deshabilitado se pinta al 50 % de opacidad —el correo REAL del
                cliente se leia como un texto de ejemplo— y ademas el navegador
                no deja seleccionarlo para copiarlo, que es justo lo que uno
                quiere hacer con la cuenta de acceso de alguien. */}
            <Input
              id="cf-correo"
              type="email"
              value={correo}
              onChange={(e) => setCorreo(e.target.value)}
              aria-describedby="cf-correo-nota"
              readOnly={esCorregir && !puedeCorregirCorreo}
              className={esCorregir && !puedeCorregirCorreo ? 'bg-muted/60' : undefined}
              disabled={enviando}
            />
            {/* La nota vive AQUI, pegada a su campo. Antes se pintaba despues
                del bloque de domicilio y se leia como una segunda nota del
                domicilio; ademas un `disabled` no entra en el orden de
                tabulacion, asi que quien navega con teclado nunca la oia. */}
            {esCorregir && (
              <p id="cf-correo-nota" className="text-[10px] text-muted-foreground">
                {puedeCorregirCorreo
                  ? 'Al guardar, el cliente iniciará sesión con este correo y su misma contraseña. El motivo quedará registrado.'
                  : 'Es la cuenta de acceso del cliente: solo un administrador puede corregirla.'}
              </p>
            )}
          </div>
        </div>

        {puedeCorregirCorreo && correoEditado && (
          <div className="space-y-1.5">
            <Label htmlFor="cf-correo-motivo">Motivo del cambio de correo *</Label>
            <Textarea
              id="cf-correo-motivo"
              value={motivoCorreo}
              onChange={(e) => setMotivoCorreo(e.target.value)}
              rows={2}
              minLength={3}
              maxLength={500}
              placeholder="Por qué se cambia la cuenta de acceso"
              disabled={enviando}
            />
            <p className="text-[10px] text-muted-foreground">
              Entre 3 y 500 caracteres. Se guardará en la auditoría administrativa.
            </p>
          </div>
        )}
        <div className="space-y-1.5">
          <Label htmlFor="cf-domicilio">Domicilio legal completo *</Label>
          <Input
            id="cf-domicilio"
            value={domicilio}
            onChange={(e) => setDomicilio(e.target.value)}
            placeholder="Av./Jr./Calle, número, distrito, provincia y departamento"
            autoComplete="street-address"
            disabled={enviando}
          />
          <p className="text-[10px] text-muted-foreground">
            {esCorregir
              ? 'Se aplicará solo a contratos futuros; no modifica PDFs ya reservados o sellados.'
              : 'Se copiará literalmente en el contrato legal.'}
          </p>
        </div>
        {!esCorregir && (
          // Aviso de la clave temporal, tal cual el portal (c_email_hint).
          <p id="cf-correo-nota" className="text-[11px] text-muted-foreground">
            La clave temporal será el <b className="text-foreground">documento</b> (si tiene menos
            de 8 caracteres se completa con ceros a la izquierda, ej. AB1234 → 00AB1234); en su
            primer ingreso el cliente creará su propia contraseña.
          </p>
        )}

        {ledgerPendiente && (
          <p
            aria-live="polite"
            className="rounded-lg border border-border bg-muted/40 px-3 py-2 text-xs font-semibold text-muted-foreground"
          >
            Validando las cuentas registradas antes de guardar…
          </p>
        )}

        {avisoLedger && (
          <div
            role="status"
            className="flex items-center justify-between gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs font-semibold text-amber-800 dark:text-amber-300"
          >
            <span>
              No se pudieron consultar las cuentas vigentes. Reintenta antes de registrar otra.
            </span>
            <Button type="button" variant="outline" size="sm" onClick={reintentarCuentasLedger}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        )}

        {esCorregir && cuentasConfirmadasVigentes != null && (
          <div className="rounded-lg border border-border bg-muted/40 px-3 py-2 text-[11px] text-muted-foreground">
            <b className="text-foreground">Cuentas vigentes del cliente</b>
            {cuentasVigentes.length ? (
              <ul className="mt-1 list-disc pl-4">
                {cuentasVigentes.map((c) => (
                  <li key={c.cuenta_id ?? `${c.moneda}-${c.cci}`}>
                    {c.moneda} · {c.banco} · {c.tipo_cuenta} · N° {cuentaEnmascarada(c.numero_cuenta)}
                    {' '}· CCI {cuentaEnmascarada(c.cci)} · {origenCuenta(c.origen)} · {fechaCuenta(c.creada_en)}
                  </li>
                ))}
              </ul>
            ) : <p className="mt-1">Sin cuentas bancarias vigentes.</p>}
          </div>
        )}

        {/* Bloque compartido con la conversión de lead (mismo formulario del portal). */}
        <SeccionesBancarias
          idBase="cf"
          pen={pen}
          usd={usd}
          onPen={setPen}
          onUsd={setUsd}
          deshabilitado={enviando || !puedeRegistrarBanca}
          registroOpcional={esCorregir}
        />
        {esCorregir && !puedeRegistrarBanca && (
          <p className="text-[11px] text-muted-foreground">El registro de cuentas está reservado a Analistas, Gerencia y Administración.</p>
        )}
      </DialogBody>
      <DialogFooter className="justify-between">
        <Button variant="ghost" size="sm" onClick={onCerrar} disabled={enviando}>
          Cancelar
        </Button>
        {/* Feedback de guardado completo (Fase 4 del plan UX): Guardando… →
            Guardado ✓ / error con Reintentar. El detalle del fallo sigue en el
            banner inline; guardar() rechaza para alimentar el estado del botón. */}
        <BotonGuardar
          size="sm"
          onGuardar={guardar}
          etiqueta={esCorregir ? 'Guardar corrección' : 'Crear cliente'}
          disabled={ledgerPendiente || deshabilitado}
        />
      </DialogFooter>
    </>
  )
}
