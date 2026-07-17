// Formulario de CLIENTE del portal dentro del CRM (alta + corregir) — espejo
// del modal #modalCliente del panel del analista (public_html/admin/analista.html
// + js/admin/analista.js), campo por campo y validación por validación.
//
// Flujo del ALTA (2 pasos, como el portal):
//   1) edge crear-cliente (Auth + perfil + correo REAL de bienvenida; clave
//      temporal = documento con ceros a 8) vía crearClientePortal.
//   2) los BANCARIOS (la edge no los acepta) vía actualizarClientePortal.
//   Si el paso 2 falla: aviso honesto y NO se encadena al contrato.
// Flujo de CORREGIR: obtenerClienteDetalle precarga TODO; el UPDATE va por RLS
//   con ventana de 5 h — si venció, el servidor devuelve 0 filas SIN error →
//   actualizarClientePortal da `false` y JAMÁS se dice "guardado".
//
// La lógica pura (validaciones, catálogo de bancos, patch de 14 bancarias) vive
// en lib/cliente-form-logica; aquí solo el estado y el pintado.
import { useEffect, useState } from 'react'
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
  obtenerClienteDetalle,
  CrmApiError,
} from '@/data/crm-api'
import { SeccionesBancarias } from '@/components/app/secciones-bancarias'
import type { ClienteDetalle } from '@/lib/clientes-tipos'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import { useVentana } from '@/lib/ventana'
import {
  SECCION_BANCARIA_VACIA,
  seccionPenDesdeDetalle,
  seccionUsdDesdeDetalle,
  validarClienteForm,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'

// Mensajes de negocio del contrato del traspaso (no cambiarlos a la ligera:
// los E2E y el equipo los reconocen tal cual).
const MSG_VENTANA_VENCIDA =
  'La ventana de corrección venció: los cambios NO se guardaron. Pide el cambio a administración.'
const MSG_BANCARIOS_NO_GUARDADOS =
  'pero los datos bancarios NO se guardaron — corrígelo ahora (tienes 5 horas).'

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
   * un cierre a mitad del alta de 2 pasos pierde el aviso de "creado sin
   * bancarios" (el cliente ya existe y el correo ya salió).
   */
  onEnviandoCambio?: (enviando: boolean) => void
}

export function ClienteForm({ modo, clienteId, onListo, onCerrar, onEnviandoCambio }: ClienteFormProps) {
  const esCorregir = modo === 'corregir'

  // Identidad
  const [apellidos, setApellidos] = useState('')
  const [nombres, setNombres] = useState('')
  const [tipoDoc, setTipoDoc] = useState<TipoDocumento>('DNI')
  const [documento, setDocumento] = useState('')
  const [telefono, setTelefono] = useState('')
  const [correo, setCorreo] = useState('')
  // Bancarios (PEN = columnas base, USD = sufijo _usd; independientes)
  const [pen, setPen] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [usd, setUsd] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  // Corregir: detalle cargado (habilita legacy/grandfathering y la cuenta regresiva)
  const [detalle, setDetalle] = useState<ClienteDetalle | null>(null)
  const [cargando, setCargando] = useState(esCorregir)
  const [errorCarga, setErrorCarga] = useState<string | null>(null)
  const [intentoCarga, setIntentoCarga] = useState(0)
  // Envío
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  /** Alta con paso 2 fallido: cliente creado SIN bancarios → aviso terminal. */
  const [avisoParcial, setAvisoParcial] = useState<string | null>(null)

  const ventana = useVentana(esCorregir ? detalle?.creado_en : null)

  useEffect(() => {
    if (!esCorregir) return
    if (!clienteId) {
      setCargando(false)
      setErrorCarga('Falta el id del cliente a corregir.')
      return
    }
    let vivo = true
    setCargando(true)
    setErrorCarga(null)
    obtenerClienteDetalle(clienteId)
      .then((d) => {
        if (!vivo) return
        // Precarga TODO (espejo de abrirModalClienteCorregir del portal).
        setApellidos(d.apellidos ?? '')
        setNombres(d.nombres ?? '')
        setTipoDoc(d.tipo_documento)
        setDocumento(d.dni ?? '')
        setTelefono(d.telefono ?? '')
        setCorreo(d.correo ?? '')
        setPen(seccionPenDesdeDetalle(d))
        setUsd(seccionUsdDesdeDetalle(d))
        setDetalle(d)
        setCargando(false)
      })
      .catch((e: unknown) => {
        if (!vivo) return
        setErrorCarga(e instanceof CrmApiError ? e.message : 'No se pudo cargar el cliente.')
        setCargando(false)
      })
    return () => {
      vivo = false
    }
  }, [esCorregir, clienteId, intentoCarga])

  const guardar = async () => {
    if (enviando) return // guard anti doble-submit (además del disabled del botón)
    setError(null)
    const r = validarClienteForm(
      { apellidos, nombres, tipo_documento: tipoDoc, documento, telefono, correo, pen, usd },
      esCorregir ? detalle : null,
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
        // UPDATE directo: la RLS valida dueño + ventana de 5 h. Si venció NO hay
        // error — 0 filas → `false` → jamás decir "guardado".
        const guardo = await actualizarClientePortal(clienteId as string, {
          nombre_completo: c.nombre_completo,
          tipo_documento: c.tipo_documento,
          dni: c.dni,
          telefono: c.telefono,
          // En un legacy sin separar (ambos vacíos) van null y se conserva su
          // nombre_completo original (rama esLegacySinSeparar de la validación).
          apellidos: c.apellidos,
          nombres: c.nombres,
          ...c.bancarios,
          actualizado_en: new Date().toISOString(),
        })
        if (!guardo) {
          setError(MSG_VENTANA_VENCIDA)
          return
        }
        toast.success('Datos del cliente corregidos.')
        onListo(clienteId as string)
      } else {
        // Paso 1: la edge crea la cuenta y manda el correo de bienvenida REAL.
        const alta = await crearClientePortal({
          email: c.correo,
          nombre_completo: c.nombre_completo,
          apellidos: c.apellidos ?? '',
          nombres: c.nombres ?? '',
          dni: c.dni,
          telefono: c.telefono,
          tipo_documento: c.tipo_documento,
        })
        // Paso 2: bancarios por UPDATE (la edge no los acepta). apellidos/nombres
        // van de refuerzo, igual que el portal.
        let bancariosOk = true
        try {
          bancariosOk = await actualizarClientePortal(alta.userId, {
            ...c.bancarios,
            apellidos: c.apellidos,
            nombres: c.nombres,
            actualizado_en: new Date().toISOString(),
          })
        } catch {
          bancariosOk = false
        }
        if (!bancariosOk) {
          // Aviso honesto y SIN encadenar al contrato (no se llama onListo):
          // el cliente existe y el correo salió, pero quedó sin bancarios.
          setAvisoParcial(
            alta.emailEnviado
              ? `Cliente "${c.nombre_completo}" creado y correo enviado, ${MSG_BANCARIOS_NO_GUARDADOS}`
              : `Cliente "${c.nombre_completo}" creado (el correo de bienvenida no se pudo enviar), ${MSG_BANCARIOS_NO_GUARDADOS}`,
          )
          return
        }
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
      {esCorregir && detalle && (
        // Cuenta regresiva visual; la ventana REAL la decide el servidor, por eso
        // el guardado no se bloquea aquí (espejo del portal: el modal no gatea).
        <p className={`text-[11px] font-semibold ${ventana.vigente ? 'text-primary' : 'text-destructive'}`}>
          Ventana de corrección: {ventana.texto}
        </p>
      )}
    </DialogHeader>
  )

  // ── Alta parcial (paso 2 fallido): estado terminal, sin re-submit posible ──
  if (avisoParcial) {
    return (
      <>
        {encabezado}
        <DialogBody className="space-y-3">
          <div
            role="alert"
            className="rounded-xl border border-destructive/40 bg-destructive/10 p-3 text-xs font-semibold text-destructive"
          >
            {avisoParcial}
          </div>
          <p className="text-xs text-muted-foreground">
            El cliente ya existe en el portal y NO se creó su contrato. Complétale los datos
            bancarios desde “Corregir datos” antes de crear el contrato.
          </p>
        </DialogBody>
        <DialogFooter>
          <Button size="sm" onClick={onCerrar}>Entendido</Button>
        </DialogFooter>
      </>
    )
  }

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

  if (esCorregir && errorCarga) {
    return (
      <>
        {encabezado}
        <DialogBody className="space-y-3">
          <p role="alert" className="text-xs font-semibold text-destructive">{errorCarga}</p>
        </DialogBody>
        <DialogFooter className="justify-between">
          <Button variant="ghost" size="sm" onClick={onCerrar}>Cerrar</Button>
          <Button variant="outline" size="sm" onClick={() => setIntentoCarga((n) => n + 1)}>
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
