// Modal de alta de lead (F1b) — se monta UNA vez en App.tsx y se abre con
// usePanelesActions().abrirNuevoLead(etapa?). En demo trabaja solo en memoria;
// en una sesión real consulta la disponibilidad y espera la RPC transaccional
// confirmada por Supabase antes de anunciar éxito. Doble defensa de escritura: este
// componente ni se renderiza para roles de solo lectura (directorio) y el
// store re-valida cada mutación por su cuenta. El formulario vive DENTRO del
// Dialog (que desmonta al cerrar), así que se resetea solo al reabrirse.
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react'
import { toast } from 'sonner'
import { UserRoundPlus } from 'lucide-react'
import { CrmApiError, verificarDisponibilidadLead } from '@/data/crm-api'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { useAuth } from '@/lib/auth-context'
import { presentarDisponibilidadLead } from '@/lib/disponibilidad-lead'
import { can, puedeEscribir } from '@/lib/roles'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import { EDAD_MINIMA, MONTO_ESTIMADO_MAX, edadCumplida, normalizarTelefono } from '@/lib/validacion'
import {
  CATEGORIAS_INTERES,
  ETAPA_INFO,
  GENEROS,
  ORIGENES,
  esGenero,
  esOrigen,
  type CategoriaInteres,
  type Genero,
  type Origen,
} from '@/lib/tipos'
import { SIMBOLO, type Moneda } from '@/lib/format'
import { cn } from '@/lib/utils'

const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const ESPERA_DISPONIBILIDAD_MS = 400
const LIMITE_DISPONIBILIDAD_MS = 5_000

interface EstadoDisponibilidadFormulario {
  comprobando: boolean
  mensaje: string | null
  bloquea: boolean
  degradado: boolean
}

const DISPONIBILIDAD_INICIAL: EstadoDisponibilidadFormulario = {
  comprobando: false,
  mensaje: null,
  bloquea: false,
  degradado: false,
}

const DISPONIBILIDAD_COMPROBANDO: EstadoDisponibilidadFormulario = {
  comprobando: true,
  mensaje: 'Comprobando disponibilidad…',
  bloquea: false,
  degradado: false,
}

const DISPONIBILIDAD_DEGRADADA: EstadoDisponibilidadFormulario = {
  comprobando: false,
  mensaje: 'No pudimos comprobar la disponibilidad. Puedes continuar; un contacto duplicado vivo será rechazado al guardar.',
  bloquea: false,
  degradado: true,
}

function disponibilidadTecnicaBloqueada(error: unknown): EstadoDisponibilidadFormulario {
  return {
    comprobando: false,
    mensaje: error instanceof CrmApiError && error.code === 'SIN_PERMISO'
      ? 'No tienes permiso para comprobar la disponibilidad de este contacto.'
      : 'La verificación de disponibilidad no está habilitada. Contacta al administrador antes de continuar.',
    bloquea: true,
    degradado: false,
  }
}

/** Clases de estado inválido para Input/Select (borde + ring destructive). */
const claseError =
  'border-destructive focus-visible:border-destructive focus-visible:ring-destructive/25'

/** Etiqueta + control + mensaje de error inline (bajo el campo). */
function Campo({
  label,
  htmlFor,
  requerido = false,
  error,
  children,
}: {
  label: string
  htmlFor?: string | undefined
  requerido?: boolean | undefined
  error?: string | undefined
  children: ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>
        {label}
        {requerido && (
          <span aria-hidden className="text-destructive">
            {' '}
            *
          </span>
        )}
      </Label>
      {children}
      {error && (
        <p
          id={htmlFor ? `${htmlFor}-error` : undefined}
          role="alert"
          className="text-[11px] font-medium text-destructive"
        >
          {error}
        </p>
      )}
    </div>
  )
}

export function LeadNuevo() {
  const { nuevoLeadAbierto } = usePanelesState()
  const { cerrarPaneles } = usePanelesActions()
  const { yo } = useAuth()
  const [altaEnCurso, setAltaEnCurso] = useState(false)

  // Guard interno (además del gate externo): directorio jamás ve este modal.
  if (!puedeEscribir(yo?.rol)) return null

  return (
    <Dialog
      open={nuevoLeadAbierto}
      onClose={() => { if (!altaEnCurso) cerrarPaneles() }}
      ariaLabel="Nuevo lead"
    >
      <FormularioNuevoLead onEnviandoChange={setAltaEnCurso} />
    </Dialog>
  )
}

/** Estado y campos del alta. Montado solo mientras el Dialog está abierto. */
function FormularioNuevoLead({
  onEnviandoChange,
}: {
  onEnviandoChange: (enviando: boolean) => void
}) {
  const { etapaInicial } = usePanelesState()
  const { ambito, crearLead } = useCRMData()
  const { abrirLead, cerrarPaneles } = usePanelesActions()
  const { yo } = useAuth()

  const puedeElegirVendedor = can(yo?.rol, 'reasignar')
  // SOLO vendedores del ámbito del rol (espejo del WITH CHECK de leads_insert):
  // supervisor solo puede crear leads asignados dentro de SU equipo.
  const vendedores = ambito.vendedores.filter((m) => m.rol_crm === 'vendedor' && m.activo)
  const etapa = ETAPA_INFO[etapaInicial]

  const [nombre, setNombre] = useState('')
  const [telefono, setTelefono] = useState('')
  const [correo, setCorreo] = useState('')
  const [dni, setDni] = useState('')
  // '' = sin dato. Sin género el avatar cae a iniciales (nunca una silueta
  // inventada), así que dejarlo vacío es una opción legítima, no un error.
  const [genero, setGenero] = useState<Genero | ''>('')
  const [fechaNacimiento, setFechaNacimiento] = useState('')
  const [distrito, setDistrito] = useState('')
  // '' = placeholder "Selecciona…" aún sin elegir; la validación exige un Origen real.
  const [origen, setOrigen] = useState<Origen | ''>('')
  const [monto, setMonto] = useState('')
  const [moneda, setMoneda] = useState<Moneda>('PEN')
  const [categoria, setCategoria] = useState<CategoriaInteres | null>(null)
  const [vendedorId, setVendedorId] = useState('')
  const [nota, setNota] = useState('')
  const [errores, setErrores] = useState<Record<string, string>>({})
  const [errorGeneral, setErrorGeneral] = useState<string | null>(null)
  const [disponibilidad, setDisponibilidad] =
    useState<EstadoDisponibilidadFormulario>(DISPONIBILIDAD_INICIAL)
  const [enviando, setEnviando] = useState(false)
  const envioEnCursoRef = useRef(false)
  const secuenciaDisponibilidadRef = useRef(0)
  const controlDisponibilidadRef = useRef<AbortController | null>(null)
  const esperaDisponibilidadRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const montadoRef = useRef(true)

  /** Cancela tanto el debounce como la petición en vuelo e invalida su respuesta. */
  const invalidarDisponibilidad = useCallback(() => {
    secuenciaDisponibilidadRef.current += 1
    if (esperaDisponibilidadRef.current) {
      clearTimeout(esperaDisponibilidadRef.current)
      esperaDisponibilidadRef.current = null
    }
    controlDisponibilidadRef.current?.abort()
    controlDisponibilidadRef.current = null
    if (montadoRef.current) setDisponibilidad(DISPONIBILIDAD_INICIAL)
  }, [])

  useEffect(() => {
    montadoRef.current = true
    return () => {
      montadoRef.current = false
      onEnviandoChange(false)
      secuenciaDisponibilidadRef.current += 1
      if (esperaDisponibilidadRef.current) clearTimeout(esperaDisponibilidadRef.current)
      controlDisponibilidadRef.current?.abort()
    }
  }, [onEnviandoChange])

  /**
   * Ejecuta el precheck. `null` significa que otra edición invalidó esta
   * respuesta; una caída operativa, en cambio, devuelve el estado degradado y
   * deja continuar porque la RPC transaccional sigue siendo la autoridad final.
   */
  const consultarDisponibilidad = useCallback(async (
    telefonoConsulta: string,
    dniConsulta: string,
  ): Promise<EstadoDisponibilidadFormulario | null> => {
    if (yo?.demo || !normalizarTelefono(telefonoConsulta)) return DISPONIBILIDAD_INICIAL

    if (esperaDisponibilidadRef.current) {
      clearTimeout(esperaDisponibilidadRef.current)
      esperaDisponibilidadRef.current = null
    }
    controlDisponibilidadRef.current?.abort()
    const control = new AbortController()
    controlDisponibilidadRef.current = control
    const secuencia = ++secuenciaDisponibilidadRef.current
    if (montadoRef.current) setDisponibilidad(DISPONIBILIDAD_COMPROBANDO)

    let agotado = false
    const reloj = setTimeout(() => {
      agotado = true
      control.abort()
    }, LIMITE_DISPONIBILIDAD_MS)

    try {
      const resultado = await verificarDisponibilidadLead(
        telefonoConsulta,
        /^\d{8}$/.test(dniConsulta) ? dniConsulta : null,
        control.signal,
      )
      if (!montadoRef.current || secuenciaDisponibilidadRef.current !== secuencia) return null
      const presentacion = presentarDisponibilidadLead(resultado)
      const siguiente: EstadoDisponibilidadFormulario = {
        comprobando: false,
        mensaje: presentacion.mensaje,
        bloquea: presentacion.bloquea,
        degradado: false,
      }
      setDisponibilidad(siguiente)
      return siguiente
    } catch (error: unknown) {
      if (!montadoRef.current || secuenciaDisponibilidadRef.current !== secuencia) return null
      // Un abort provocado por una edición posterior es obsoleto, no una caída
      // de red. El timeout propio sí se presenta como degradación fail-open.
      if (control.signal.aborted && !agotado) return null
      const esFalloOperativo = agotado
        || (error instanceof CrmApiError && error.code === 'DISPONIBILIDAD_RED')
      if (esFalloOperativo) {
        setDisponibilidad(DISPONIBILIDAD_DEGRADADA)
        return DISPONIBILIDAD_DEGRADADA
      }
      // Contrato roto, RPC/esquema ausente, permisos o cualquier fallo no
      // reconocido: fail-closed. Solo red/timeout tiene permiso de degradar.
      const bloqueoTecnico = disponibilidadTecnicaBloqueada(error)
      setDisponibilidad(bloqueoTecnico)
      return bloqueoTecnico
    } finally {
      clearTimeout(reloj)
      if (controlDisponibilidadRef.current === control) controlDisponibilidadRef.current = null
    }
  }, [yo?.demo])

  const programarDisponibilidad = useCallback((telefonoConsulta: string, dniConsulta: string) => {
    invalidarDisponibilidad()
    if (yo?.demo || !normalizarTelefono(telefonoConsulta)) return

    const secuenciaProgramada = secuenciaDisponibilidadRef.current
    setDisponibilidad(DISPONIBILIDAD_COMPROBANDO)
    esperaDisponibilidadRef.current = setTimeout(() => {
      esperaDisponibilidadRef.current = null
      if (secuenciaDisponibilidadRef.current !== secuenciaProgramada) return
      void consultarDisponibilidad(telefonoConsulta, dniConsulta)
    }, ESPERA_DISPONIBILIDAD_MS)
  }, [consultarDisponibilidad, invalidarDisponibilidad, yo?.demo])

  /** Al corregir un campo, su error inline (y el general) desaparecen. */
  const limpiarError = (campo: string) => {
    setErrorGeneral(null)
    setErrores((e) => {
      if (!(campo in e)) return e
      const { [campo]: _omitido, ...resto } = e
      return resto
    })
  }

  /** CampoLead del store → clave del estado local de errores del formulario. */
  const CAMPO_UI: Record<string, string> = {
    nombre_completo: 'nombre',
    telefono: 'telefono',
    dni: 'dni',
    correo: 'correo',
    origen: 'origen',
    monto_estimado: 'monto',
    genero: 'genero',
    fecha_nacimiento: 'fechaNacimiento',
  }

  const enviar = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (envioEnCursoRef.current) return
    const err: Record<string, string> = {}
    if (!nombre.trim()) err.nombre = 'El nombre es obligatorio'
    if (!normalizarTelefono(telefono)) {
      err.telefono = 'Celular peruano inválido — ej.: 987 654 321 o +51 987 654 321'
    }
    if (correo.trim() && !CORREO_RE.test(correo.trim())) err.correo = 'Correo inválido'
    if (dni.trim() && !/^\d{8}$/.test(dni.trim())) {
      err.dni = 'El DNI debe tener exactamente 8 dígitos'
    }
    if (fechaNacimiento && edadCumplida(fechaNacimiento) < EDAD_MINIMA) {
      // El store re-valida lo mismo; esto solo evita el viaje de ida y vuelta.
      err.fechaNacimiento = `El lead debe tener al menos ${EDAD_MINIMA} años`
    }
    if (!origen) err.origen = 'Selecciona el origen'
    const montoNum = Number(monto)
    if (monto.trim() === '' || !Number.isFinite(montoNum) || montoNum <= 0) {
      err.monto = 'Ingresa un capital estimado mayor que 0'
    }
    setErrores(err)
    setErrorGeneral(null)
    // esOrigen narra '' → fuera: si origen está vacío, err.origen ya forzó el return.
    if (Object.keys(err).length > 0 || !esOrigen(origen)) return

    envioEnCursoRef.current = true
    setEnviando(true)
    onEnviandoChange(true)
    try {
      // P-048: se revalida SIN debounce para dar feedback temprano. Esta lectura
      // sigue siendo UX; crear_lead_si_disponible cierra la carrera al guardar.
      if (!yo?.demo) {
        const vigente = await consultarDisponibilidad(telefono, dni)
        if (!vigente || vigente.bloquea) return
      }

      const res = crearLead({
        nombre_completo: nombre.trim(),
        telefono, // el store normaliza a +519########
        correo: correo.trim() || null,
        dni: dni.trim() || null,
        genero: genero || null,
        fecha_nacimiento: fechaNacimiento || null,
        distrito: distrito.trim() || null,
        origen,
        etapa: etapaInicial,
        monto_estimado: montoNum,
        moneda,
        categoria_interes: categoria,
        vendedor_id: puedeElegirVendedor ? vendedorId || null : (yo?.id ?? null),
        nota: nota.trim() || null,
      })
      if (res.ok && res.id) {
        const persistencia = await res.persistido
        if (!montadoRef.current) return
        if (!persistencia.ok) {
          setErrorGeneral(persistencia.error ?? 'No se pudo crear el lead')
          return
        }
        toast.success(`Lead creado${yo?.demo ? ' (demo)' : ''} — ${nombre.trim()}`)
        abrirLead(res.id) // abrirLead ya cierra este modal
        return
      }
      // Errores del store → anclados a su campo por res.campo (código
      // estructurado; jamás adivinando por regex sobre el texto del mensaje).
      const msg = res.error ?? 'No se pudo crear el lead'
      const campoUi = res.campo ? (CAMPO_UI[res.campo] ?? null) : null
      if (campoUi) setErrores({ [campoUi]: msg })
      else setErrorGeneral(msg)
    } finally {
      envioEnCursoRef.current = false
      onEnviandoChange(false)
      if (montadoRef.current) setEnviando(false)
    }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle>Nuevo lead</DialogTitle>
        <DialogDescription className="flex flex-wrap items-center gap-1.5">
          Entrará al pipeline en
          <Badge color={etapa.color} dot>
            {etapa.label}
          </Badge>
        </DialogDescription>
      </DialogHeader>
      <form onSubmit={enviar} noValidate className="flex min-h-0 flex-1 flex-col">
        <fieldset disabled={enviando} className="contents">
          <DialogBody className="space-y-3.5">
          {errorGeneral && (
            <div
              role="alert"
              className="rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs font-medium text-destructive"
            >
              {errorGeneral}
            </div>
          )}
          <Campo label="Nombre completo" htmlFor="nl-nombre" requerido error={errores.nombre}>
            <Input
              id="nl-nombre"
              autoFocus
              autoComplete="off"
              placeholder="Nombres y apellidos"
              value={nombre}
              required
              aria-required="true"
              aria-invalid={!!errores.nombre}
              aria-describedby={errores.nombre ? 'nl-nombre-error' : undefined}
              className={cn(errores.nombre && claseError)}
              onChange={(e) => {
                setNombre(e.target.value)
                limpiarError('nombre')
              }}
            />
          </Campo>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Teléfono" htmlFor="nl-telefono" requerido error={errores.telefono}>
              <Input
                id="nl-telefono"
                type="tel"
                inputMode="tel"
                autoComplete="off"
                placeholder="987 654 321"
                value={telefono}
                required
                aria-required="true"
                aria-invalid={!!errores.telefono || disponibilidad.bloquea}
                aria-describedby={[
                  errores.telefono ? 'nl-telefono-error' : null,
                  disponibilidad.mensaje ? 'nl-disponibilidad' : null,
                ].filter(Boolean).join(' ') || undefined}
                className={cn((errores.telefono || disponibilidad.bloquea) && claseError)}
                onChange={(e) => {
                  setTelefono(e.target.value)
                  limpiarError('telefono')
                  invalidarDisponibilidad()
                }}
                onBlur={() => programarDisponibilidad(telefono, dni)}
              />
            </Campo>
            <Campo label="DNI" htmlFor="nl-dni" error={errores.dni}>
              <Input
                id="nl-dni"
                inputMode="numeric"
                maxLength={8}
                autoComplete="off"
                placeholder="8 dígitos (opcional)"
                value={dni}
                aria-invalid={!!errores.dni || disponibilidad.bloquea}
                aria-describedby={[
                  errores.dni ? 'nl-dni-error' : null,
                  disponibilidad.mensaje ? 'nl-disponibilidad' : null,
                ].filter(Boolean).join(' ') || undefined}
                className={cn((errores.dni || disponibilidad.bloquea) && claseError)}
                onChange={(e) => {
                  const siguienteDni = e.target.value.replace(/\D/g, '')
                  setDni(siguienteDni)
                  limpiarError('dni')
                  invalidarDisponibilidad()
                  if (siguienteDni.length === 8) {
                    programarDisponibilidad(telefono, siguienteDni)
                  }
                }}
              />
            </Campo>
          </div>
          {disponibilidad.mensaje && (
            <div
              id="nl-disponibilidad"
              role={disponibilidad.bloquea ? 'alert' : 'status'}
              className={cn(
                'rounded-lg border px-3 py-2 text-xs font-medium',
                disponibilidad.bloquea && 'border-destructive/40 bg-destructive/10 text-destructive',
                disponibilidad.degradado && 'border-amber-500/40 bg-amber-500/10 text-amber-800 dark:text-amber-300',
                disponibilidad.comprobando && 'border-border bg-muted/50 text-muted-foreground',
              )}
            >
              {disponibilidad.mensaje}
            </div>
          )}
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Género" htmlFor="nl-genero" error={errores.genero}>
              <Select
                id="nl-genero"
                value={genero}
                aria-invalid={!!errores.genero}
                className={cn(errores.genero && claseError)}
                onChange={(e) => {
                  // '' vuelve a "sin dato" a propósito: se puede deshacer la elección.
                  setGenero(esGenero(e.target.value) ? e.target.value : '')
                  limpiarError('genero')
                }}
              >
                <option value="">Sin dato</option>
                {GENEROS.map((g) => (
                  <option key={g.k} value={g.k}>
                    {g.label}
                  </option>
                ))}
              </Select>
            </Campo>
            <Campo
              label="Fecha de nacimiento"
              htmlFor="nl-fecha-nacimiento"
              error={errores.fechaNacimiento}
            >
              <Input
                id="nl-fecha-nacimiento"
                type="date"
                autoComplete="off"
                value={fechaNacimiento}
                aria-invalid={!!errores.fechaNacimiento}
                aria-describedby={errores.fechaNacimiento ? 'nl-fecha-nacimiento-error' : undefined}
                className={cn(errores.fechaNacimiento && claseError)}
                onChange={(e) => {
                  setFechaNacimiento(e.target.value)
                  limpiarError('fechaNacimiento')
                }}
              />
            </Campo>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Correo" htmlFor="nl-correo" error={errores.correo}>
              <Input
                id="nl-correo"
                type="email"
                autoComplete="off"
                placeholder="correo@ejemplo.com"
                value={correo}
                aria-invalid={!!errores.correo}
                className={cn(errores.correo && claseError)}
                onChange={(e) => {
                  setCorreo(e.target.value)
                  limpiarError('correo')
                }}
              />
            </Campo>
            <Campo label="Distrito" htmlFor="nl-distrito">
              <Input
                id="nl-distrito"
                autoComplete="off"
                placeholder="Miraflores"
                value={distrito}
                onChange={(e) => setDistrito(e.target.value)}
              />
            </Campo>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Origen" htmlFor="nl-origen" requerido error={errores.origen}>
              <Select
                id="nl-origen"
                value={origen}
                required
                aria-required="true"
                aria-invalid={!!errores.origen}
                aria-describedby={errores.origen ? 'nl-origen-error' : undefined}
                className={cn(errores.origen && claseError)}
                onChange={(e) => {
                  // Las <option> salen del catálogo ORIGENES; esOrigen hace el narrow a Origen.
                  if (esOrigen(e.target.value)) setOrigen(e.target.value)
                  limpiarError('origen')
                }}
              >
                <option value="" disabled>
                  Selecciona…
                </option>
                {ORIGENES.map((o) => (
                  <option key={o.k} value={o.k}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </Campo>
            <Campo label="Capital estimado" htmlFor="nl-monto" requerido error={errores.monto}>
              <div className="flex gap-2">
                <div className="min-w-0 flex-1">
                  <Input
                    id="nl-monto"
                    type="number"
                    min={0.01}
                    max={MONTO_ESTIMADO_MAX}
                    step="0.01"
                    required
                    aria-required="true"
                    inputMode="decimal"
                    placeholder="Ej. 5000"
                    value={monto}
                    aria-invalid={!!errores.monto}
                    aria-describedby={errores.monto ? 'nl-monto-error' : undefined}
                    className={cn('tabular-nums', errores.monto && claseError)}
                    onChange={(e) => {
                      setMonto(e.target.value)
                      limpiarError('monto')
                    }}
                  />
                </div>
                <div className="w-24 shrink-0">
                  <Select
                    aria-label="Moneda"
                    value={moneda}
                    onChange={(e) => setMoneda(e.target.value as Moneda)}
                  >
                    <option value="PEN">{SIMBOLO.PEN} PEN</option>
                    <option value="USD">{SIMBOLO.USD} USD</option>
                  </Select>
                </div>
              </div>
            </Campo>
          </div>
          <Campo label="Vendedor asignado" htmlFor="nl-vendedor">
            {puedeElegirVendedor ? (
              <Select
                id="nl-vendedor"
                value={vendedorId}
                onChange={(e) => setVendedorId(e.target.value)}
              >
                <option value="">Sin asignar (parkeado)</option>
                {vendedores.map((v) => (
                  <option key={v.perfil_id} value={v.perfil_id}>
                    {v.nombre_completo}
                  </option>
                ))}
              </Select>
            ) : (
              <>
                <Input id="nl-vendedor" value={yo?.nombre_completo ?? ''} disabled readOnly />
                <p className="text-[11px] text-muted-foreground">
                  El lead se te asigna automáticamente.
                </p>
              </>
            )}
          </Campo>
          <div className="space-y-1.5">
            <Label id="nl-categoria-label">
              Categoría de interés{' '}
              <span className="font-normal text-muted-foreground">(opcional)</span>
            </Label>
            <div
              role="group"
              aria-labelledby="nl-categoria-label"
              className="flex flex-wrap gap-2"
            >
              {CATEGORIAS_INTERES.map((c) => {
                const activa = categoria === c.k
                return (
                  <button
                    key={c.k}
                    type="button"
                    aria-pressed={activa}
                    onClick={() => setCategoria(activa ? null : c.k)}
                    className={cn(
                      'cursor-pointer rounded-full border px-3 py-1.5 text-[11px] font-bold leading-none transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30',
                      activa
                        ? 'border-accent bg-accent text-accent-foreground'
                        : 'border-input bg-background text-muted-foreground hover:border-border-strong hover:text-foreground',
                    )}
                  >
                    {c.label}
                  </button>
                )
              })}
            </div>
          </div>
          <Campo label="Nota" htmlFor="nl-nota">
            <Textarea
              id="nl-nota"
              rows={3}
              placeholder="Contexto del lead, próximos pasos… (opcional)"
              value={nota}
              onChange={(e) => setNota(e.target.value)}
            />
          </Campo>
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={cerrarPaneles} disabled={enviando}>
              Cancelar
            </Button>
            <Button
              type="submit"
              disabled={enviando || disponibilidad.bloquea}
              aria-busy={enviando}
            >
              <UserRoundPlus /> {enviando ? 'Creando…' : 'Crear lead'}
            </Button>
          </DialogFooter>
        </fieldset>
      </form>
    </>
  )
}
