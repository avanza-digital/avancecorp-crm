// Formulario de CLIENTE del portal dentro del CRM (alta + corregir) — espejo
// del modal #modalCliente del panel del analista (public_html/admin/analista.html
// + js/admin/analista.js), campo por campo y validación por validación.
//
// Flujo del ALTA (UN paso desde 2026-07-27): la edge crear-cliente crea Auth +
//   perfil CON sus cuentas bancarias en el mismo INSERT y manda el correo REAL de
//   bienvenida (clave temporal = documento con ceros a 8), vía crearClientePortal.
//   Antes eran DOS pasos y los bancarios iban en un UPDATE posterior: si ese paso
//   fallaba quedaba un cliente real, con su correo ya enviado, sin cuenta donde
//   cobrar el interés. La regla "al menos una cuenta" ahora la exige el servidor.
// Flujo de CORREGIR: obtenerClienteDetalle precarga TODO. El analista usa UPDATE
//   por RLS con ventana de 5 h; Gerencia usa una RPC con allowlist que preserva
//   la identidad técnica, el rol y el analista responsable. Un rechazo devuelve
//   false o error y JAMÁS se dice "guardado".
//
// La lógica pura (validaciones, catálogo de bancos, patch de 14 bancarias) vive
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
  hayCuentaEnLedger,
  seccionPenDesdeDetalle,
  seccionUsdDesdeDetalle,
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
}

export function ClienteForm({ modo, clienteId, onListo, onCerrar, onEnviandoCambio }: ClienteFormProps) {
  const esCorregir = modo === 'corregir'
  const { yo } = useAuth()
  const esGerencia = yo?.rol === 'gerencia'
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
  // Bancarios (PEN = columnas base, USD = sufijo _usd; independientes)
  const [pen, setPen] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [usd, setUsd] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  // Corregir: detalle cargado (habilita legacy/grandfathering y la cuenta regresiva)
  const [detalle, setDetalle] = useState<ClienteDetalle | null>(null)
  // Envío
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  const ventana = useVentana(esCorregir && !esGerencia ? detalle?.creado_en : null)

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
  // Las cuentas del LEDGER completan la precarga bancaria: una cuenta
  // registrada al crear un contrato vive SOLO en crm.cuentas_bancarias y las
  // casillas de perfiles no la conocen (regla en precargarSeccionBancaria).
  // Solo alimentan la siembra; el guardado sigue escribiendo las casillas.
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
  // Siembra ÚNICA y solo con datos RECIÉN traídos: isFetchedAfterMount exige un
  // fetch COMPLETADO tras el mount — sin red el refetch queda 'paused' (isFetching
  // false + isSuccess true con la copia cacheada) y sembrar esa copia vieja haría
  // que el UPDATE de set completo pise bancarios corregidos por otra sesión. Un
  // refetch posterior (foco de ventana) no debe pisar lo que el analista edita.
  // Las cuentas del ledger esperan lo mismo, pero su FALLO no bloquea el
  // formulario: degrada a la precarga de siempre (solo casillas del perfil).
  const sembrado = useRef(false)
  useEffect(() => {
    if (!esCorregir || sembrado.current) return
    if (!qDetalle.isSuccess || qDetalle.isFetching || !qDetalle.isFetchedAfterMount) return
    const d = qDetalle.data
    sembrado.current = true
    // Precarga TODO (espejo de abrirModalClienteCorregir del portal). Las
    // casillas bancarias vienen SOLO del perfil: las cuentas del ledger jamás
    // se siembran aquí (se muestran aparte, en solo lectura) porque al guardar
    // irían a perfiles y el fallback perfil_legacy de Pagos las usaría para
    // contratos viejos sin vínculo (veto Codex 2026-08-11 a esa convergencia).
    setApellidos(d.apellidos ?? '')
    setNombres(d.nombres ?? '')
    setTipoDoc(d.tipo_documento)
    setDocumento(d.dni ?? '')
    setTelefono(d.telefono ?? '')
    setCorreo(d.correo ?? '')
    setDomicilio(d.domicilio ?? '')
    // Defensa en profundidad: el servidor redacta las 14 columnas cuando el
    // flag es false, pero el formulario tampoco confía en una combinación
    // incoherente de flag cerrado + valores no nulos.
    setPen(d.banca_visible ? seccionPenDesdeDetalle(d) : SECCION_BANCARIA_VACIA)
    setUsd(d.banca_visible ? seccionUsdDesdeDetalle(d) : SECCION_BANCARIA_VACIA)
    setDetalle(d)
  }, [esCorregir, qDetalle.isSuccess, qDetalle.isFetching, qDetalle.isFetchedAfterMount, qDetalle.data])

  // Derivados del ledger (crm.cuentas_bancarias) — la fuente que la ficha ya
  // usa. NO alimentan las casillas: informan al analista y perdonan la regla
  // «al menos una cuenta» cuando los contratos ya tienen dónde depositar.
  const cuentasConfirmadasVigentes =
    cuentasConfirmadas?.clienteId === clienteId ? cuentasConfirmadas : null
  const cuentasLedger =
    esCorregir && ledgerRemotoHabilitado && cuentasConfirmadasVigentes != null
    ? [...cuentasConfirmadasVigentes.pen, ...cuentasConfirmadasVigentes.usd]
    : []
  const cuentasDeContrato = cuentasLedger.filter((c) => c.origen === 'contrato')
  const ledgerCubre = hayCuentaEnLedger(cuentasLedger)
  // La degradación NO es muda: si el ledger no se pudo leer, el analista lo ve —
  // sin el aviso escribiría a mano una cuenta «que no existía» o chocaría con
  // «Registra al menos una cuenta» sin pista del porqué. Derivado en vivo: un
  // reintento exitoso lo limpia solo.
  const avisoLedger =
    esCorregir &&
    detalle != null &&
    ledgerRemotoHabilitado &&
    (qCuentasPen.isError || qCuentasUsd.isError)
  // No validar contra «cero cuentas» mientras las dos monedas aún se están
  // revalidando: sería un falso negativo y tentaría a usar la caché para evitarlo.
  // Si la RPC falla, el aviso explícito toma el relevo y se permite degradar a
  // las casillas embebidas que ya llegaron autorizadas en el detalle.
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

  // Una vez sembrado, el formulario manda: un fallo de un refetch posterior no
  // lo tumba (el guardado revalida en el servidor de todos modos).
  const errorCarga = !esCorregir
    ? null
    : !clienteId
      ? 'Falta el id del cliente a corregir.'
      : detalle == null && qDetalle.isError
        ? mensajeDeError(qDetalle.error, 'No se pudo cargar el cliente.')
        : null
  const cargando = esCorregir && detalle == null && errorCarga == null

  const guardar = async () => {
    if (enviando || ledgerPendiente) return // guards anti doble-submit y contra una validación incompleta
    setError(null)
    const r = validarClienteForm(
      { apellidos, nombres, tipo_documento: tipoDoc, documento, telefono, correo, domicilio, pen, usd },
      esCorregir ? detalle : null,
      // El ledger perdona la regla «al menos una cuenta» SOLO en corregir: el
      // cliente ya tiene dónde cobrar (cuenta activa vinculada a contrato) y
      // el patch con casillas vacías es idempotente sobre perfiles.
      { cuentaEnLedger: ledgerCubre },
    )
    if (!r.ok) {
      setError(r.error)
      // El rechazo alimenta el estado de error del BotonGuardar; el detalle
      // del motivo ya quedó en el banner inline (setError).
      throw new Error(r.error)
    }
    const c = r.cliente
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
      const mensaje = 'Solo un superadministrador puede corregir el correo de acceso de un cliente.'
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
            ...c.bancarios,
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
        toast.success(
          correoCambio
            ? 'Datos corregidos. El cliente entra al portal con su correo nuevo.'
            : 'Datos del cliente corregidos.',
        )
        onListo(clienteId as string)
      } else {
        // UN SOLO PASO: la edge valida los bancarios, crea la cuenta CON sus
        // cuentas de depósito en el mismo INSERT y manda el correo. Las
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
          Ventana de corrección: {ventana.texto}
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

  // (Ya no existe el estado "alta parcial": la edge escribe las cuentas en el
  //  mismo INSERT del cliente, así que o nace con su cuenta o no nace.)

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
                  ? 'Es la cuenta con la que el cliente entra al portal. Al guardar cambia su acceso; el motivo quedará registrado en auditoría.'
                  : 'Es la cuenta de acceso del cliente: solo un superadministrador puede corregirla.'}
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
              No se pudieron consultar las cuentas registradas en contratos: puede faltar
              información abajo.
            </span>
            <Button type="button" variant="outline" size="sm" onClick={reintentarCuentasLedger}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        )}

        {cuentasDeContrato.length > 0 && (
          // Solo lectura A PROPÓSITO: estas cuentas viven en crm.cuentas_bancarias
          // atadas a SU contrato. Copiarlas a las casillas del perfil las volvería
          // la cuenta de cobro de contratos viejos sin vínculo (fallback
          // perfil_legacy de Pagos) — el backfill por inferencia que está prohibido.
          <div className="rounded-lg border border-border bg-muted/40 px-3 py-2 text-[11px] text-muted-foreground">
            <b className="text-foreground">Cuentas registradas en contratos</b> — se administran
            desde el contrato, no aquí:
            <ul className="mt-1 list-disc pl-4">
              {cuentasDeContrato.map((c) => (
                <li key={c.cuenta_id ?? `${c.moneda}-${c.cci}`}>
                  {c.banco} · {c.tipo_cuenta} · {c.numero_cuenta} —{' '}
                  {c.moneda === 'PEN' ? 'soles' : 'dólares'}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Bloque compartido con la conversión de lead (mismo formulario del portal). */}
        <SeccionesBancarias
          idBase="cf"
          pen={pen}
          usd={usd}
          onPen={setPen}
          onUsd={setUsd}
          deshabilitado={enviando}
        />
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
          disabled={ledgerPendiente}
        />
      </DialogFooter>
    </>
  )
}
