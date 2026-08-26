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
//   identidad/rol/asesor. Un rechazo devuelve false o error y JAMÁS se dice
//   "guardado".
//
// La lógica pura (validaciones, catálogo de bancos, patch de 14 bancarias) vive
// en lib/cliente-form-logica; aquí solo el estado y el pintado.
import { useEffect, useRef, useState } from 'react'
import { BadgeCheck, Pencil, RotateCcw, UserRoundPlus } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import {
  actualizarClientePortal,
  crearClientePortal,
  mensajeDeError,
  CrmApiError,
} from '@/data/crm-api'
import { useClienteDetalle, useCuentasBancariasCliente } from '@/data/crm-queries'
import { SeccionesBancarias } from '@/components/app/secciones-bancarias'
import type { ClienteDetalle } from '@/lib/clientes-tipos'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import { useVentana } from '@/lib/ventana'
import { useAuth } from '@/lib/auth-context'
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

  // Identidad
  const [apellidos, setApellidos] = useState('')
  const [nombres, setNombres] = useState('')
  const [tipoDoc, setTipoDoc] = useState<TipoDocumento>('DNI')
  const [documento, setDocumento] = useState('')
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
  // Las cuentas del LEDGER completan la precarga bancaria: una cuenta
  // registrada al crear un contrato vive SOLO en crm.cuentas_bancarias y las
  // casillas de perfiles no la conocen (regla en precargarSeccionBancaria).
  // Solo alimentan la siembra; el guardado sigue escribiendo las casillas.
  const qCuentasPen = useCuentasBancariasCliente(clienteId ?? '', 'PEN', esCorregir && !!clienteId)
  const qCuentasUsd = useCuentasBancariasCliente(clienteId ?? '', 'USD', esCorregir && !!clienteId)
  // Siembra ÚNICA y solo con datos RECIÉN traídos: isFetchedAfterMount exige un
  // fetch COMPLETADO tras el mount — sin red el refetch queda 'paused' (isFetching
  // false + isSuccess true con la copia cacheada) y sembrar esa copia vieja haría
  // que el UPDATE de set completo pise bancarios corregidos por otra sesión. Un
  // refetch posterior (foco de ventana) no debe pisar lo que el asesor edita.
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
    setPen(seccionPenDesdeDetalle(d))
    setUsd(seccionUsdDesdeDetalle(d))
    setDetalle(d)
  }, [esCorregir, qDetalle.isSuccess, qDetalle.isFetching, qDetalle.isFetchedAfterMount, qDetalle.data])

  // Derivados del ledger (crm.cuentas_bancarias) — la fuente que la ficha ya
  // usa. NO alimentan las casillas: informan al asesor y perdonan la regla
  // «al menos una cuenta» cuando los contratos ya tienen dónde depositar.
  const cuentasLedger = esCorregir
    ? [...(qCuentasPen.data ?? []), ...(qCuentasUsd.data ?? [])]
    : []
  const cuentasDeContrato = cuentasLedger.filter((c) => c.origen === 'contrato')
  const ledgerCubre = hayCuentaEnLedger(cuentasLedger)
  // La degradación NO es muda: si el ledger no se pudo leer, el asesor lo ve —
  // sin el aviso escribiría a mano una cuenta «que no existía» o chocaría con
  // «Registra al menos una cuenta» sin pista del porqué. Derivado en vivo: un
  // reintento exitoso lo limpia solo.
  const avisoLedger = esCorregir && detalle != null && (qCuentasPen.isError || qCuentasUsd.isError)
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
    if (enviando) return // guard anti doble-submit (además del disabled del botón)
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
      return
    }
    const c = r.cliente
    setEnviando(true)
    onEnviandoCambio?.(true)
    try {
      if (esCorregir) {
        // Analista: UPDATE directo y ventana RLS de 5 h. Gerencia: RPC acotada
        // sin esa ventana, pero sin capacidad de tocar rol, estado ni asesor.
        const guardo = await actualizarClientePortal(
          clienteId as string,
          {
            nombre_completo: c.nombre_completo,
            tipo_documento: c.tipo_documento,
            dni: c.dni,
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
          return
        }
        toast.success('Datos del cliente corregidos.')
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
      setError(e instanceof CrmApiError ? e.message : 'Ocurrió un error. Inténtalo de nuevo.')
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
      {esCorregir && detalle && !esGerencia && (
        // Cuenta regresiva visual; la ventana REAL la decide el servidor, por eso
        // el guardado no se bloquea aquí (espejo del portal: el modal no gatea).
        <p className={`text-[11px] font-semibold ${ventana.vigente ? 'text-primary' : 'text-destructive'}`}>
          Ventana de corrección: {ventana.texto}
        </p>
      )}
      {esCorregir && detalle && esGerencia && (
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

  // Reintentar repara las TRES consultas, no solo el detalle: si la red
  // parpadeó al abrir, las cuentas del ledger quedaron en un isError que la
  // siembra aceptaría como «listo» y el formulario degradaría en silencio con
  // la red ya sana (hallazgo medio de la verificación multi-lente 2026-08-11).
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

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
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

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="cf-tipo-doc">Tipo de documento *</Label>
            {/* Opciones desde la tabla canónica — nunca <option> a mano. */}
            <Select
              id="cf-tipo-doc"
              value={tipoDoc}
              onChange={(e) => setTipoDoc(e.target.value as TipoDocumento)}
              disabled={enviando}
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
              disabled={enviando}
            />
            <p id="cf-documento-hint" className="text-[10px] text-muted-foreground">{reglaDoc.regla}</p>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
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
            <Label htmlFor="cf-correo">Correo electrónico *</Label>
            <Input
              id="cf-correo"
              type="email"
              value={correo}
              onChange={(e) => setCorreo(e.target.value)}
              aria-describedby="cf-correo-nota"
              disabled={enviando || esCorregir}
            />
          </div>
        </div>
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
        {esCorregir ? (
          // El correo va con el login del cliente: no se edita (espejo portal).
          <p id="cf-correo-nota" className="text-[11px] text-muted-foreground">
            El correo es la <b className="text-foreground">cuenta de acceso</b> del cliente: no se puede editar.
          </p>
        ) : (
          // Aviso de la clave temporal, tal cual el portal (c_email_hint).
          <p id="cf-correo-nota" className="text-[11px] text-muted-foreground">
            La clave temporal será el <b className="text-foreground">documento</b> (si tiene menos
            de 8 caracteres se completa con ceros a la izquierda, ej. AB1234 → 00AB1234); en su
            primer ingreso el cliente creará su propia contraseña.
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
        <Button size="sm" onClick={guardar} disabled={enviando}>
          <BadgeCheck />
          {enviando
            ? (esCorregir ? 'Guardando…' : 'Creando…')
            : (esCorregir ? 'Guardar corrección' : 'Crear cliente')}
        </Button>
      </DialogFooter>
    </>
  )
}
