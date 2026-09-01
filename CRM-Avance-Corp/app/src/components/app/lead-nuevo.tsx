// Modal de alta de lead (F1b) — se monta UNA vez en App.tsx y se abre con
// usePanelesActions().abrirNuevoLead(etapa?). En demo trabaja solo en memoria;
// en una sesión real consulta la disponibilidad y espera la RPC transaccional
// confirmada por Supabase antes de anunciar éxito. Doble defensa de escritura: este
// componente ni se renderiza para roles de solo lectura (directorio) y el
// store re-valida cada mutación por su cuenta. El formulario vive DENTRO del
// Dialog (que desmonta al cerrar), así que se resetea solo al reabrirse.
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { BellPlus, Handshake, UserRoundPlus } from 'lucide-react'
import {
  CrmApiError,
  guardarRecordatorioDisponibilidad,
  tomarLeadLibre,
  verificarDisponibilidadLead,
} from '@/data/crm-api'
import { crmQueryKeys } from '@/data/crm-queries'
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
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import {
  contactoTomable,
  presentarDisponibilidadLead,
  presentarResultadoToma,
  tarjetaDisponibilidadLead,
  type ModoToma,
  type TarjetaDisponibilidadLead,
} from '@/lib/disponibilidad-lead'
import {
  aInstanteRevision,
  contactoRecordable,
  fechaCortaLima,
  fechaMaximaRevision,
  fechaMinimaRevision,
  sugerirFechaRevision,
  telefonoLegible,
} from '@/lib/recordatorios-disponibilidad'
import { esFocoHuerfano } from '@/lib/foco'
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

/** F3.1: guardados de recordatorio EN VUELO, por teléfono normalizado y a
 *  nivel de MÓDULO — la operación sobrevive al desmontaje del modal (R4c),
 *  así que un candado de instancia no impide que cerrar y reabrir dispare un
 *  segundo upsert del mismo contacto (ganaría el que aterrice último, no el
 *  último que el analista confirmó). El finally SIEMPRE libera la llave. */
const recordatoriosEnVuelo = new Set<string>()

interface EstadoDisponibilidadFormulario {
  comprobando: boolean
  mensaje: string | null
  bloquea: boolean
  degradado: boolean
  /** Tarjeta §5.2 del plan «lead libre»: datos mínimos del seguimiento activo
   *  o del enfriamiento; null en los estados sin seguimiento que mostrar. */
  tarjeta: TarjetaDisponibilidadLead | null
  /** F2 «Tomar»: veredicto con puerta de toma (en_bolsa/reutilizable) — el
   *  botón solo existe con esto no-nulo Y rol con tomarLeadDirecto. */
  tomable: ModoToma | null
  /** F3 «Recordar»: veredicto ocupado SIN puerta (tomado/enfriamiento) — la
   *  única acción es el recordatorio personal (§5.3). Con la fecha sugerida
   *  del veredicto (regla real solo en enfriamiento). */
  recordable: boolean
  fechaSugerida: string | null
}

const DISPONIBILIDAD_INICIAL: EstadoDisponibilidadFormulario = {
  comprobando: false,
  mensaje: null,
  bloquea: false,
  degradado: false,
  tarjeta: null,
  tomable: null,
  recordable: false,
  fechaSugerida: null,
}

const DISPONIBILIDAD_COMPROBANDO: EstadoDisponibilidadFormulario = {
  comprobando: true,
  mensaje: 'Comprobando disponibilidad…',
  bloquea: false,
  degradado: false,
  tarjeta: null,
  tomable: null,
  recordable: false,
  fechaSugerida: null,
}

const DISPONIBILIDAD_DEGRADADA: EstadoDisponibilidadFormulario = {
  comprobando: false,
  mensaje: 'No pudimos comprobar la disponibilidad. Puedes continuar; un contacto duplicado vivo será rechazado al guardar.',
  bloquea: false,
  degradado: true,
  tarjeta: null,
  tomable: null,
  recordable: false,
  fechaSugerida: null,
}

/** Lo tecleado no alcanza para verificar (la RPC exige un celular) y se DICE.
 *  Callar aquí engañaba: con un DNI en el campo el precheck no corría y el
 *  analista leía el silencio como «libre» (hallazgo de Miguel, 2026-08-17).
 *  `degradado` = mismo ámbar de «no verificado, puedes continuar». */
const DISPONIBILIDAD_SIN_CELULAR: EstadoDisponibilidadFormulario = {
  comprobando: false,
  mensaje: 'Sin verificar: la disponibilidad se comprueba con el CELULAR (9 dígitos, ej. 987 654 321). Un DNI por sí solo no dice si el contacto está libre u ocupado.',
  bloquea: false,
  degradado: true,
  tarjeta: null,
  tomable: null,
  recordable: false,
  fechaSugerida: null,
}

function disponibilidadTecnicaBloqueada(error: unknown): EstadoDisponibilidadFormulario {
  return {
    comprobando: false,
    mensaje: error instanceof CrmApiError && error.code === 'SIN_PERMISO'
      ? 'No tienes permiso para comprobar la disponibilidad de este contacto.'
      : 'La verificación de disponibilidad no está habilitada. Contacta al administrador antes de continuar.',
    bloquea: true,
    degradado: false,
    tarjeta: null,
    tomable: null,
    recordable: false,
    fechaSugerida: null,
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
  const { etapaInicial, telefonoInicial } = usePanelesState()
  const { ambito, crearLead, recargar } = useCRMData()
  const { abrirLead, cerrarPaneles } = usePanelesActions()
  const { yo } = useAuth()
  // F3.1: reloj VIVO para min/max del recordatorio — un modal abierto a las
  // 23:59 no puede seguir ofreciendo el «mañana» de ayer (Date.now() en el
  // render se congelaba hasta el siguiente re-render casual).
  const ahora = useAhora()

  const puedeElegirVendedor = can(yo?.rol, 'reasignar')
  // SOLO analistas del ámbito del rol (espejo del WITH CHECK de leads_insert):
  // supervisor solo puede crear leads asignados dentro de SU equipo.
  const vendedores = ambito.vendedores.filter((m) => m.rol_crm === 'vendedor' && m.activo)
  const etapa = ETAPA_INFO[etapaInicial]

  const [nombre, setNombre] = useState('')
  // El atajo «Verificar disponibilidad» del buscador llega con el teléfono ya
  // tecleado (el formulario se monta al abrir el Dialog, así que el inicial
  // de ESTA apertura es el correcto).
  const [telefono, setTelefono] = useState(telefonoInicial ?? '')
  const [telefonoAlternativo, setTelefonoAlternativo] = useState('')
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
  // F2 «Tomar»: la toma directa tiene su propio en-curso y su propio error —
  // un fallo al tomar NO pisa el veredicto de disponibilidad ya presentado.
  const [tomando, setTomando] = useState(false)
  const [errorToma, setErrorToma] = useState<string | null>(null)
  const tomaEnCursoRef = useRef(false)
  // F3 «Recordar»: la única acción sobre un ocupado sin puerta (§5.3).
  // fechaRevision null = el analista no la tocó (manda la sugerida).
  const queryClient = useQueryClient()
  const [fechaRevision, setFechaRevision] = useState<string | null>(null)
  const [recordando, setRecordando] = useState(false)
  const [recordadoPara, setRecordadoPara] = useState<string | null>(null)
  const [errorRecordatorio, setErrorRecordatorio] = useState<string | null>(null)
  const recordandoRef = useRef(false)
  // F3.1: el teléfono (normalizado) del guardado en vuelo de ESTE montaje —
  // el «Guardando…» del botón se ancla a él para no disfrazar al contacto B
  // mientras viaja el guardado del A (refutación parcial de Codex a R5).
  const recordandoTelefonoRef = useRef<string | null>(null)
  // Rescate de foco del mini-form (a11y F3-A1 — la MISMA regresión que ya se
  // pagó en F2-M2): al pulsar, el botón enfocado se deshabilita y el foco cae
  // a body; al resolver, o se lo lleva la confirmación (éxito) o vuelve al
  // botón (error). Vía efecto: en línea el DOM aún no conmutó.
  const botonRecordarRef = useRef<HTMLButtonElement | null>(null)
  const confirmacionRecordatorioRef = useRef<HTMLParagraphElement | null>(null)
  const rescatarFocoRecordarRef = useRef(false)
  useEffect(() => {
    if (recordando || !rescatarFocoRecordarRef.current) return
    rescatarFocoRecordarRef.current = false
    // El fieldset NO se congela durante el guardado (a diferencia de la toma):
    // si el usuario ya movió el foco a otro CONTROL, robárselo sería peor que
    // no rescatarlo — solo se rescata un foco huérfano (lib/foco.ts).
    if (!esFocoHuerfano(botonRecordarRef.current)) return
    if (recordadoPara) confirmacionRecordatorioRef.current?.focus()
    else botonRecordarRef.current?.focus()
  }, [recordando, recordadoPara])
  // Rescate de foco (revisor a11y F2-M2): cuando el veredicto fresco retira el
  // botón deshabilitado que tenía el foco, este iría a parar a body — se lleva
  // explícitamente al teléfono, lo próximo que el usuario editaría. Vía efecto
  // y no en línea: en la rama del veredicto el fieldset AÚN está congelado por
  // la toma (Codex R2) y focus() sobre un control disabled es un no-op.
  const telefonoRef = useRef<HTMLInputElement | null>(null)
  const rescatarFocoRef = useRef(false)
  // Deps con `disponibilidad` además de `tomando`: con una RPC instantánea
  // React batchea el true→false de tomando en UN commit y el efecto no
  // re-correría; el veredicto siempre produce un objeto nuevo y lo dispara.
  useEffect(() => {
    if (tomando || !rescatarFocoRef.current) return
    rescatarFocoRef.current = false
    telefonoRef.current?.focus()
  }, [tomando, disponibilidad])
  const envioEnCursoRef = useRef(false)
  // F3.1 (auditoría 18/08): el estado del recordatorio pertenece al TELÉFONO,
  // no a la consulta. Este ref guarda el teléfono normalizado del veredicto
  // recordable vigente; solo un teléfono DISTINTO borra fecha/confirmación.
  const contactoRecordableRef = useRef<string | null>(null)
  const secuenciaDisponibilidadRef = useRef(0)
  const controlDisponibilidadRef = useRef<AbortController | null>(null)
  const esperaDisponibilidadRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const montadoRef = useRef(true)

  /** Cancela tanto el debounce como la petición en vuelo e invalida su
   *  respuesta. `telefonoCandidato` es lo que HAY (o va a haber) en el campo:
   *  decide si el estado del recordatorio sobrevive a esta invalidación. */
  const invalidarDisponibilidad = useCallback((telefonoCandidato: string) => {
    secuenciaDisponibilidadRef.current += 1
    if (esperaDisponibilidadRef.current) {
      clearTimeout(esperaDisponibilidadRef.current)
      esperaDisponibilidadRef.current = null
    }
    controlDisponibilidadRef.current?.abort()
    controlDisponibilidadRef.current = null
    if (montadoRef.current) {
      // Un contacto editado es OTRO contacto: el error de la toma anterior
      // ya no habla de lo que hay en pantalla.
      setErrorToma(null)
      // F3.1: pero la fecha elegida y la confirmación de un guardado REAL
      // pertenecen al teléfono, no a la consulta — un blur sin editar o
      // teclear el DNI no pueden borrarlas (y borrarlas invitaba a re-guardar
      // «por si acaso», reprogramando en silencio el recordatorio).
      const candidato = normalizarTelefono(telefonoCandidato)
      if (!candidato || candidato !== contactoRecordableRef.current) {
        contactoRecordableRef.current = null
        setFechaRevision(null)
        setRecordadoPara(null)
        setErrorRecordatorio(null)
      }
    }
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
        tarjeta: tarjetaDisponibilidadLead(resultado),
        tomable: contactoTomable(resultado),
        recordable: contactoRecordable(resultado),
        fechaSugerida: contactoRecordable(resultado)
          ? sugerirFechaRevision(resultado, Date.now())
          : null,
      }
      // F3.1: el veredicto recordable ancla el estado del recordatorio a SU
      // teléfono; deja de serlo (u otro contacto) → el ancla cae.
      contactoRecordableRef.current = siguiente.recordable
        ? normalizarTelefono(telefonoConsulta)
        : null
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
    invalidarDisponibilidad(telefonoConsulta)
    if (yo?.demo) return
    if (!normalizarTelefono(telefonoConsulta)) {
      // Honestidad del precheck: sin celular válido NO hay verificación posible
      // (el servidor la exige por teléfono). Si el analista ya tecleó algo —
      // un número a medias o un DNI en el campo equivocado — callar es mentir.
      if (telefonoConsulta.trim() !== '' || dniConsulta.trim() !== '') {
        setDisponibilidad(DISPONIBILIDAD_SIN_CELULAR)
      }
      return
    }

    const secuenciaProgramada = secuenciaDisponibilidadRef.current
    setDisponibilidad(DISPONIBILIDAD_COMPROBANDO)
    esperaDisponibilidadRef.current = setTimeout(() => {
      esperaDisponibilidadRef.current = null
      if (secuenciaDisponibilidadRef.current !== secuenciaProgramada) return
      void consultarDisponibilidad(telefonoConsulta, dniConsulta)
    }, ESPERA_DISPONIBILIDAD_MS)
  }, [consultarDisponibilidad, invalidarDisponibilidad, yo?.demo])

  // Con teléfono precargado (atajo del buscador) el precheck se dispara solo:
  // el blur que normalmente lo lanza nunca va a ocurrir. Una sola vez por
  // montaje — el ref evita re-disparos si el panel re-renderiza.
  const prefillDisparadoRef = useRef(false)
  useEffect(() => {
    if (prefillDisparadoRef.current || !telefonoInicial) return
    prefillDisparadoRef.current = true
    programarDisponibilidad(telefonoInicial, '')
  }, [telefonoInicial, programarDisponibilidad])

  /**
   * F2 «Tomar lead e iniciar seguimiento» (spec §5.6/§5.7). Mutación real:
   * sin cortesía fail-open. Tres caminos y los tres se DICEN:
   *  · tomado_ok → resincronizar el ámbito (el lead ya es del analista),
   *    confirmar y abrir la ficha (abrirLead cierra este modal solo);
   *  · veredicto fresco → perdió la carrera o el estado cambió: se re-presenta
   *    con la misma maquinaria del precheck (mensaje+tarjeta+tomable) y el
   *    aviso «la disponibilidad acaba de cambiar»;
   *  · error → se muestra bajo el botón SIN tocar el veredicto vigente.
   */
  const manejarTomar = async () => {
    if (tomaEnCursoRef.current) return
    tomaEnCursoRef.current = true
    setTomando(true)
    setErrorToma(null)
    onEnviandoChange(true) // el Dialog no se cierra con una toma en vuelo
    try {
      const dniLimpio = dni.trim()
      const resultado = await tomarLeadLibre(
        telefono,
        /^\d{8}$/.test(dniLimpio) ? dniLimpio : null,
      )
      if (!montadoRef.current) return

      if (resultado.estado === 'tomado_ok') {
        // El orden importa: la ficha lee del store — primero el ámbito ve el
        // lead, después se abre. abrirLead también cierra el panel del alta.
        const resincronizado = await recargar()
        if (!montadoRef.current) return
        toast.success('Lead tomado: ya está en tu cartera con todo su historial')
        if (resincronizado) {
          abrirLead(resultado.lead_id)
        } else {
          // Codex R5: la toma ES real (el servidor confirmó) pero el store
          // conserva la foto vieja — abrir la ficha aquí sería abrir el vacío.
          // Se dice y se cierra: el precheck ya lo mostraría como suyo.
          toast.warning('Tu cartera no se pudo refrescar: recarga la página para abrir el lead.')
          cerrarPaneles()
        }
        return
      }

      const presentacion = presentarResultadoToma(resultado)
      const tomableFresco = contactoTomable(resultado)
      // F3.1: mismo anclado que el precheck — el veredicto fresco de la toma
      // también puede abrir (o cerrar) el mini-form del recordatorio.
      contactoRecordableRef.current = contactoRecordable(resultado)
        ? normalizarTelefono(telefono)
        : null
      setDisponibilidad({
        comprobando: false,
        mensaje: presentacion.mensaje,
        bloquea: presentacion.bloquea,
        degradado: false,
        tarjeta: tarjetaDisponibilidadLead(resultado),
        tomable: tomableFresco,
        recordable: contactoRecordable(resultado),
        fechaSugerida: contactoRecordable(resultado)
          ? sugerirFechaRevision(resultado, Date.now())
          : null,
      })
      // El único desenlace sin aviso vivo era el «libre» fresco (todo se
      // desvanece a la vez y el alta se habilita en silencio): sonner tiene
      // aria-live, con esto los TRES desenlaces de la toma se anuncian.
      if (!presentacion.mensaje) {
        toast.info('La disponibilidad acaba de cambiar: el contacto está libre y puedes crear el lead.')
      }
      // Si el veredicto retiró el botón (que estaba deshabilitado y con el
      // foco), el foco caería a body — el efecto lo lleva al teléfono cuando
      // el fieldset se deshiele (tomando=false, en el finally).
      if (!tomableFresco) rescatarFocoRef.current = true
    } catch (error: unknown) {
      if (!montadoRef.current) return
      setErrorToma(
        error instanceof CrmApiError
          ? error.message
          : 'No se pudo tomar el lead. Inténtalo de nuevo.',
      )
    } finally {
      tomaEnCursoRef.current = false
      if (montadoRef.current) {
        setTomando(false)
        onEnviandoChange(false)
      }
    }
  }

  /**
   * F3 «Recordarme revisar este contacto» (§5.3): guarda (o reprograma — la
   * llave UNIQUE del servidor hace del guardado un upsert) el recordatorio
   * personal. No toca el lead, no reserva nada: solo la campana del analista.
   */
  const manejarRecordar = async () => {
    if (recordandoRef.current) return
    // `??` a propósito: '' significa que el analista VACIÓ la fecha — rellenar
    // con la sugerida en silencio sería guardar algo que él no ve. Se le dice.
    const fecha = fechaRevision ?? disponibilidad.fechaSugerida
    if (!fecha) {
      setErrorRecordatorio('Elige la fecha del recordatorio.')
      return
    }
    // Codex R5: si el analista edita el contacto con el guardado en vuelo, la
    // respuesta tardía hablaría del contacto ANTERIOR — se ancla la secuencia
    // y el teléfono de ESTA petición y la UI solo se toca si siguen vigentes.
    const secuencia = secuenciaDisponibilidadRef.current
    const telefonoPedido = telefono
    const llave = normalizarTelefono(telefonoPedido) ?? telefonoPedido
    if (recordatoriosEnVuelo.has(llave)) {
      // Otro montaje (modal cerrado y reabierto) todavía tiene este contacto
      // viajando: un segundo upsert dejaría ganar al que aterrice último.
      setErrorRecordatorio('Ese contacto ya tiene un guardado en curso. Espera un momento y verifica de nuevo.')
      return
    }
    recordandoRef.current = true
    recordatoriosEnVuelo.add(llave)
    recordandoTelefonoRef.current = llave
    const legible = telefonoLegible(normalizarTelefono(telefonoPedido) ?? telefonoPedido)
    rescatarFocoRecordarRef.current = true
    setRecordando(true)
    setErrorRecordatorio(null)
    try {
      const dniLimpio = dni.trim()
      await guardarRecordatorioDisponibilidad(
        yo?.id ?? '',
        telefonoPedido,
        /^\d{8}$/.test(dniLimpio) ? dniLimpio : null,
        aInstanteRevision(fecha),
      )
      // El guardado ES real aunque el modal ya se haya cerrado o el contacto
      // haya cambiado (Codex R4c): la campana se refresca SIEMPRE, y el toast
      // nombra teléfono y fecha para ser honesto incluso con otro contacto en
      // pantalla (R5 / a11y M1).
      void queryClient.invalidateQueries({ queryKey: crmQueryKeys.recordatoriosDisponibilidad() })
      toast.success(
        `Recordatorio guardado para ${legible}: la campana te avisará el ${
          fechaCortaLima(aInstanteRevision(fecha)) ?? fecha
        }`,
      )
      if (!montadoRef.current || secuenciaDisponibilidadRef.current !== secuencia) return
      setRecordadoPara(fecha)
    } catch (error: unknown) {
      const mensaje = error instanceof CrmApiError
        ? error.message
        : 'No se pudo guardar el recordatorio. Inténtalo de nuevo.'
      if (montadoRef.current && secuenciaDisponibilidadRef.current === secuencia) {
        // a11y M3: el rechazo se ancla al mini-form (inline), no a un toast.
        setErrorRecordatorio(mensaje)
      } else {
        // Fuera de pantalla o contacto cambiado: el toast nombra al afectado.
        toast.error(`${mensaje} (contacto ${legible})`)
      }
    } finally {
      recordatoriosEnVuelo.delete(llave)
      recordandoTelefonoRef.current = null
      recordandoRef.current = false
      if (montadoRef.current) setRecordando(false)
    }
  }

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
        telefono_alternativo: telefonoAlternativo.trim() || null,
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

  const guardandoEsteContacto = recordando
    && recordandoTelefonoRef.current !== null
    && recordandoTelefonoRef.current === normalizarTelefono(telefono)

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
        {/* La toma en vuelo también congela el formulario (Codex R2): editar
            el contacto con la RPC viajando dejaría presentar el veredicto de
            A como si hablara del B recién tecleado. */}
        <fieldset disabled={enviando || tomando} className="contents">
          <DialogBody className="space-y-3.5">
          {errorGeneral && (
            <div
              role="alert"
              // text-destructive-text (#991b1b): 7.1:1 sobre bg-destructive/10
              // (el --destructive puro da 4.1:1 ahí y falla WCAG — el token
              // nació exactamente para esta superficie; revisor a11y F2).
              className="rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs font-medium text-destructive-text"
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
                ref={telefonoRef}
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
                  // El candidato es lo RECIÉN tecleado (el estado aún no conmutó).
                  invalidarDisponibilidad(e.target.value)
                }}
                onBlur={() => programarDisponibilidad(telefono, dni)}
              />
            </Campo>
            {/*
              El segundo número NO participa en la disponibilidad ni en el dedup:
              la identidad del lead es el principal (opción A, 2026-08-26). Por
              eso no lleva `programarDisponibilidad` — consultarlo sugeriría que
              reclama al lead, y no lo hace.
            */}
            <Campo
              label="Teléfono alternativo"
              htmlFor="nl-telefono-alt"
              error={errores.telefono_alternativo}
            >
              <Input
                id="nl-telefono-alt"
                inputMode="tel"
                autoComplete="off"
                placeholder="Otro celular, un fijo o +código de país (opcional)"
                value={telefonoAlternativo}
                aria-invalid={!!errores.telefono_alternativo}
                aria-describedby={errores.telefono_alternativo ? 'nl-telefono_alternativo-error' : undefined}
                className={cn(errores.telefono_alternativo && claseError)}
                onChange={(e) => {
                  setTelefonoAlternativo(e.target.value)
                  limpiarError('telefono_alternativo')
                }}
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
                  // El teléfono NO cambió: la fecha/confirmación del
                  // recordatorio sobreviven a teclear el DNI (F3.1).
                  invalidarDisponibilidad(telefono)
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
                // text-destructive-text: 7.1:1 sobre bg-destructive/10 (el
                // puro daba 4.1:1 y fallaba WCAG en el canal principal de F2).
                disponibilidad.bloquea && 'border-destructive/40 bg-destructive/10 text-destructive-text',
                // text-warning-text (#92400e): la app NO tiene tema oscuro — un
                // dark: aquí seguiría al SO del usuario y dejaría este aviso
                // en ~1.3:1 justo para quien tiene el sistema en oscuro.
                disponibilidad.degradado && 'border-amber-500/40 bg-amber-500/10 text-warning-text',
                disponibilidad.comprobando && 'border-border bg-muted/50 text-muted-foreground',
              )}
            >
              {disponibilidad.mensaje}
            </div>
          )}
          {disponibilidad.tarjeta && (
            // Tarjeta §5.2 (solo lectura): lo mínimo para decidir — estado,
            // analista responsable y fechas. Sin notas ni montos ajenos (privacidad §8).
            <div className="rounded-lg border border-border bg-muted/40 px-3 py-2">
              <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                {disponibilidad.tarjeta.titulo}
              </p>
              {disponibilidad.tarjeta.lineas.length > 0 && (
                <dl className="mt-1 space-y-0.5">
                  {disponibilidad.tarjeta.lineas.map((linea) => (
                    <div key={linea.etiqueta} className="flex justify-between gap-3 text-xs">
                      <dt className="text-muted-foreground">{linea.etiqueta}</dt>
                      <dd className="font-semibold tabular-nums text-foreground">{linea.valor}</dd>
                    </div>
                  ))}
                </dl>
              )}
            </div>
          )}
          {disponibilidad.tomable && can(yo?.rol, 'tomarLeadDirecto') && !yo?.demo && (
            // F2 «Tomar» (spec §5.6): la puerta vive SOLO tras la verificación
            // por contacto y SOLO para el analista (espejo del guard de la
            // RPC — supervisión asigna por el reparto). En demo el precheck ni
            // corre, el !demo es cinturón.
            <div className="space-y-1.5">
              <Button
                type="button"
                variant="accent"
                className="w-full"
                onClick={manejarTomar}
                disabled={tomando || enviando}
                aria-busy={tomando}
                aria-describedby={errorToma ? 'nl-error-toma' : undefined}
              >
                <Handshake /> {tomando ? 'Tomando lead…' : 'Tomar lead e iniciar seguimiento'}
              </Button>
              {errorToma && (
                <p id="nl-error-toma" role="alert" className="text-xs font-medium text-destructive">
                  {errorToma}
                </p>
              )}
            </div>
          )}
          {disponibilidad.recordable && can(yo?.rol, 'tomarLeadDirecto') && !yo?.demo && (
            // F3 «Recordar» (§5.3): la ÚNICA acción sobre un ocupado sin
            // puerta. No reserva, no prioriza, no toca el lead — solo la
            // campana personal. Guardar de nuevo = reprogramar (upsert).
            // Misma capacidad que Tomar: es la antesala de esa puerta y la
            // RLS del servidor ya la restringe a analista.
            recordadoPara ? (
              <div className="rounded-lg border border-border bg-muted/40 px-3 py-2.5">
                {/* a11y A1: el botón que tenía el foco desapareció con este
                    intercambio — la confirmación lo recibe (tabIndex -1).
                    SIN role=status a propósito (F3.1): el foco ya la anuncia y
                    el toast también — tres anuncios eran ruido, no acceso. */}
                <p
                  ref={confirmacionRecordatorioRef}
                  tabIndex={-1}
                  className="text-xs font-medium text-foreground outline-none"
                >
                  Recordatorio guardado: la campana te avisará el{' '}
                  <span className="font-bold">
                    {fechaCortaLima(aInstanteRevision(recordadoPara)) ?? recordadoPara}
                  </span>{' '}
                  para volver a verificar.
                </p>
              </div>
            ) : (
              <div
                role="group"
                aria-labelledby="nl-recordar-titulo"
                aria-describedby="nl-recordar-ayuda"
                className="rounded-lg border border-border bg-muted/40 px-3 py-2.5"
              >
                <p id="nl-recordar-titulo" className="text-xs font-bold text-foreground">
                  ¿Quieres que te lo recuerde?
                </p>
                <p id="nl-recordar-ayuda" className="mt-0.5 text-[11px] text-muted-foreground-strong">
                  Sin reservar nada: solo una nota personal para volver a verificar ese día.
                </p>
                <div className="mt-1.5 flex items-center gap-2">
                  <Label htmlFor="nl-recordar-fecha" className="sr-only">
                    Fecha del recordatorio
                  </Label>
                  <Input
                    id="nl-recordar-fecha"
                    type="date"
                    className={cn('w-40', errorRecordatorio && claseError)}
                    min={fechaMinimaRevision(ahora)}
                    max={fechaMaximaRevision(ahora)}
                    value={fechaRevision ?? disponibilidad.fechaSugerida ?? ''}
                    aria-invalid={!!errorRecordatorio}
                    aria-describedby={errorRecordatorio ? 'nl-recordar-error' : undefined}
                    onChange={(e) => {
                      setFechaRevision(e.target.value)
                      setErrorRecordatorio(null)
                    }}
                  />
                  <Button
                    ref={botonRecordarRef}
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => { void manejarRecordar() }}
                    disabled={recordando || enviando}
                    aria-busy={guardandoEsteContacto}
                  >
                    {/* «Guardando…» SOLO si lo que viaja es ESTE contacto: con
                        el guardado del A en vuelo, el mini-form del B queda
                        deshabilitado pero sin disfrazarse de su operación. */}
                    <BellPlus /> {guardandoEsteContacto ? 'Guardando…' : 'Recordarme revisar'}
                  </Button>
                </div>
                {errorRecordatorio && (
                  <p
                    id="nl-recordar-error"
                    role="alert"
                    className="mt-1 text-[11px] font-medium text-destructive"
                  >
                    {errorRecordatorio}
                  </p>
                )}
              </div>
            )
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
                {/* Decisión de Miguel (2026-09-01): LANDING y FORMULARIO
                    también pueden declararse en el alta manual. Referido
                    conserva su regla especial: solo lo registra el analista,
                    a su propio nombre, porque esa etiqueta mueve su conversión. */}
                {ORIGENES
                  .filter((o) => o.k !== 'referido' || yo?.rol === 'vendedor')
                  .map((o) => (
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
          <Campo label="Analista asignado" htmlFor="nl-vendedor">
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
            {/* Cancelar muere durante la toma (Codex R3): el servidor puede
                COMPROMETER la toma y un desmontaje descartaría el tomado_ok en
                silencio — lead asignado sin que el analista se entere. El
                cierre por Escape/overlay ya lo bloquea onEnviandoChange.
                ⚠️ `|| tomando` aquí es REDUNDANTE a propósito (el fieldset de
                arriba ya congela el Footer): su mutante sobrevive enmascarado
                y se acepta — es defensa por si el Footer saliera del fieldset. */}
            <Button type="button" variant="ghost" onClick={cerrarPaneles} disabled={enviando || tomando}>
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
