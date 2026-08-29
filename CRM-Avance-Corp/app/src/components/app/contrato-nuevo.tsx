// Formulario de CONTRATO dentro del CRM (paso 2 de la conversión lead→cliente).
// Usa el wrapper atómico de `crm` sobre la RPC del portal + el generador de
// cronograma portado: contrato, cuenta y vínculo se confirman o revierten juntos.
import { useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowRight,
  BadgeCheck,
  Download,
  ExternalLink,
  FileSignature,
  Home,
  LoaderCircle,
  Plus,
  RefreshCw,
} from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { money, fmtFecha, type Moneda } from '@/lib/format'
import { ERROR_MONTO, parseMonto } from '@/lib/numero'
import { completarDomicilioCliente, crearContrato, CrmApiError, type CrearContratoInput } from '@/data/crm-api'
import {
  esCuotaDeInteres,
  formatDateLocal,
  generarCronograma,
  vencimientoDesdePlazo,
  type CategoriaContrato,
  type CuotaCronograma,
  type ModalidadContrato,
  type TipoInteres,
} from '@/lib/cronograma'
import { normalizarTitulares, type TitularBorrador } from '@/lib/titulares'
import { TitularesEditor } from '@/components/app/titulares'
import { CuentaPagoContrato } from '@/components/app/cuenta-pago-contrato'
import { useCuentasBancariasCliente, useDatosLegalesContrato } from '@/data/crm-queries'
import {
  SECCION_BANCARIA_VACIA,
  validarDomicilioLegal,
  type CampoSeccionBancaria,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'
import { CUENTA_NUEVA, claveCuenta, prepararCuentaPago } from '@/lib/cuentas-bancarias-contrato'
import {
  CATEGORIAS_CONTRATO_UI,
  MODALIDADES_UI,
  PLAZOS_BASE,
  PREFIJO_CONTRATO,
  RE_SEIS_DIGITOS,
} from '@/lib/contratos-catalogo'
import {
  archivarContratoPdfConfirmado,
  CONTRATO_DOCUMENTO_DESDE_TEXTO,
  ContratoPdfNoSelladoError,
  descargarArchivoContratoPdf,
  esContratoRegimenAnterior,
  etiquetaEstadoContratoPdf,
  verArchivoContratoPdf,
  type ArchivoContratoPdf,
  type EstadoContratoPdf,
} from '@/lib/contrato-pdf-archivo'
import type { ContratoPdfDatos } from '@/lib/contrato-pdf'
import { archivarContratoPdfDemoHabilitado } from '@/lib/contrato-pdf-demo-loader'
import type { CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'

const PLAZO_PERSONALIZADO = 'personalizado'
const CUENTAS_VACIAS: CuentaBancariaSeleccionable[] = []
let secuenciaContratoDemo = 0

/**
 * La identidad del demo representa una CREACION, no el numero escrito. El
 * numero puede repetirse durante una prueba (y Mi cartera lo rechazara), pero
 * nunca debe apuntar a la misma entrada de cache mientras se valida el flujo.
 */
function crearIdContratoDemo(): string {
  secuenciaContratoDemo += 1
  const semilla = globalThis.crypto?.randomUUID?.() ?? Date.now().toString(36)
  return `demo-${semilla}-${secuenciaContratoDemo.toString(36)}`
}

/** Resumen confirmado que Mi cartera usa únicamente para materializar el demo local. */
export interface ContratoCreadoLocal {
  id: string
  input: CrearContratoInput
  cronograma: CuotaCronograma[]
  pdfDatos: ContratoPdfDatos
}

interface ContratoCreado {
  id: string
  numero: string
  archivo: ArchivoContratoPdf | null
  estadoPdf: EstadoContratoPdf
  archivando: boolean
  errorArchivo: string | null
  local: ContratoCreadoLocal | null
}

const PLAZOS: { v: string; label: string; anioExacto: boolean }[] = [
  ...PLAZOS_BASE.map((p) => ({
    v: String(p.meses),
    label: p.label,
    anioExacto: p.anioExacto,
  })),
  { v: PLAZO_PERSONALIZADO, label: 'Personalizado', anioExacto: false },
]

const ID_CAMPO_CUENTA: Record<CampoSeccionBancaria, string> = {
  banco: 'ct-nueva-banco',
  numero_cuenta: 'ct-nueva-numero',
  tipo_cuenta: 'ct-nueva-tipo',
  cci: 'ct-nueva-cci',
  beneficiario_nombre: 'ct-nueva-benef-nombre',
  beneficiario_dni: 'ct-nueva-benef-doc',
}

function hoyLocal(): string {
  return formatDateLocal(new Date())
}

/**
 * Nombres de campo del servidor en idioma del vendedor. El pre-vuelo legal
 * devuelve claves (nunca valores), y un mensaje que dijera "falta dni" obligaría
 * a traducir mentalmente justo cuando el alta ya se frenó.
 */
const ETIQUETA_CAMPO_LEGAL: Record<string, string> = {
  nombre_completo: 'nombre completo',
  tipo_documento: 'tipo de documento',
  documento: 'número de documento',
  domicilio: 'domicilio legal',
  correo: 'correo',
  telefono: 'celular',
}

function listarCampos(campos: readonly string[]): string {
  const nombres = campos.map((campo) => ETIQUETA_CAMPO_LEGAL[campo] ?? campo)
  if (nombres.length <= 1) return nombres[0] ?? ''
  return `${nombres.slice(0, -1).join(', ')} y ${nombres[nombres.length - 1]}`
}

export interface ContratoNuevoProps {
  clienteId: string
  clienteNombre: string
  montoSugerido?: number | null
  monedaSugerida?: Moneda
  /** Fija el propósito comercial. Renovación nunca se elige libremente: nace
   * desde el contrato anterior; upgrade nace desde la ficha del cliente. */
  categoriaFija?: CategoriaContrato
  renovacionOrigen?: {
    id: string
    numeroContrato: string
    capital: number
    moneda: Moneda
    fechaVencimiento: string
  }
  /** Solo para el recorrido local sin backend: identidad legal ficticia ya conocida. */
  pdfDatosDemo?: Omit<ContratoPdfDatos, 'contrato'> | undefined
  /** Cuentas precargadas: obligatorias para un demo útil y, sobre todo, sin red. */
  cuentasDemo?: Partial<Record<Moneda, CuentaBancariaSeleccionable[]>> | undefined
  /** Validacion sin efectos (el demo la usa para reflejar el UNIQUE del servidor). */
  validarNumero?: (numero: string) => string | null
  /**
   * Equipo comercial para elegir DE QUIÉN es la venta (P-055 Fase 3, decisión 2
   * de Miguel: «cuando registra un administrativo o un supervisor, tiene que
   * seleccionar el analista»). Si no llega, el selector no se dibuja y el
   * servidor aplica su regla: la venta queda a nombre de quien la registra.
   */
  analistas?: { perfil_id: string; nombre_completo: string }[]
  /** A quién apunta el selector al abrir: normalmente quien está registrando. */
  analistaInicial?: string | null
  /** Foto confirmada para que el contenedor pueda tratar Esc/overlay como Finalizar. */
  onConfirmado?: (numero: string, creadoLocal?: ContratoCreadoLocal) => void
  /** Bloquea el cierre externo durante create + archivo y durante cada reintento. */
  onEnviandoCambio?: (enCurso: boolean) => void
  onCreado: (numero: string, creadoLocal?: ContratoCreadoLocal) => void
  onOmitir: () => void
}

export function ContratoNuevo({
  clienteId,
  clienteNombre,
  montoSugerido,
  monedaSugerida,
  categoriaFija,
  renovacionOrigen,
  pdfDatosDemo,
  cuentasDemo,
  validarNumero,
  analistas,
  analistaInicial,
  onConfirmado,
  onEnviandoCambio,
  onCreado,
  onOmitir,
}: ContratoNuevoProps) {
  // De quién es la venta. Arranca en quien registra si esa persona está en la
  // lista; si no está (una administrativa, por ejemplo), arranca vacío y hay que
  // elegir — que es exactamente lo que pide la decisión 2.
  const [analistaCierre, setAnalistaCierre] = useState<string>(() =>
    analistaInicial && (analistas ?? []).some((a) => a.perfil_id === analistaInicial) ? analistaInicial : '',
  )
  const categoriaInicial = renovacionOrigen ? 'renovacion' : (categoriaFija ?? '')
  const [categoria, setCategoria] = useState<CategoriaContrato | ''>(categoriaInicial)
  const [tipoInteres, setTipoInteres] = useState<TipoInteres>('simple')
  const [modalidad, setModalidad] = useState<ModalidadContrato>('mensual')
  const [capital, setCapital] = useState(
    renovacionOrigen ? String(renovacionOrigen.capital) : montoSugerido != null ? String(montoSugerido) : '',
  )
  const [capitalRenovado, setCapitalRenovado] = useState(renovacionOrigen ? String(renovacionOrigen.capital) : '')
  const [capitalAdicional, setCapitalAdicional] = useState(renovacionOrigen ? '0' : '')
  const [moneda, setMoneda] = useState<Moneda>(renovacionOrigen?.moneda ?? monedaSugerida ?? 'PEN')
  const [tasa, setTasa] = useState('15') // default del negocio (espejo del portal)
  const [fechaInicio, setFechaInicio] = useState(hoyLocal())
  const [plazo, setPlazo] = useState<string>('12')
  const [vencManual, setVencManual] = useState('')
  // Solo los 6 dígitos: el prefijo 2026-01- está pintado fijo en el form.
  const [numero, setNumero] = useState('')
  const [notas, setNotas] = useState('')
  // La selección se reinicia al cambiar moneda: jamás se traslada implícitamente
  // una cuenta PEN a USD (o viceversa).
  const [cuentaSeleccionada, setCuentaSeleccionada] = useState('')
  const [cuentaNueva, setCuentaNueva] = useState<SeccionBancariaForm>({
    ...SECCION_BANCARIA_VACIA,
  })
  // Co-titulares (cuentas mancomunadas, máx 5) — filas crudas del editor.
  const [titulares, setTitulares] = useState<TitularBorrador[]>([])
  const [enviando, setEnviando] = useState(false)
  const [creado, setCreado] = useState<ContratoCreado | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [campoCuentaInvalido, setCampoCuentaInvalido] = useState<CampoSeccionBancaria | null>(null)
  const [avisoCuenta, setAvisoCuenta] = useState<string | null>(null)
  const errorRef = useRef<HTMLParagraphElement>(null)
  // Domicilio legal faltante: el PDF se reserva DENTRO de la transacción del
  // alta y lo exige literalmente, así que sin él el contrato entero se revierte.
  // Se pregunta ANTES para convertir ese muro sin nombre en un campo.
  const [domicilio, setDomicilio] = useState('')
  const [guardandoDomicilio, setGuardandoDomicilio] = useState(false)
  const [errorDomicilio, setErrorDomicilio] = useState<string | null>(null)
  const [avisoDomicilio, setAvisoDomicilio] = useState<string | null>(null)
  // El servidor ya confirmó el domicilio en ESTA sesión: manda sobre la
  // consulta, que puede quedarse con una foto vieja si la relectura falla.
  const [domicilioConfirmado, setDomicilioConfirmado] = useState(false)
  const esDemo = pdfDatosDemo != null
  // Sin useQueryClient a propósito. En la app real el provider existe (main.tsx
  // envuelve todo), pero varios arneses de prueba montan este componente suelto
  // y exigirlo los rompía. No hace falta: la ficha del cliente se refresca sola
  // porque useClienteDetalle tiene staleTime: 0 y vuelve a pedir el dato al
  // abrirse, y el pre-vuelo se recarga con su propio refetch.
  const legalesQ = useDatosLegalesContrato(clienteId, !esDemo)
  const cuentasQ = useCuentasBancariasCliente(clienteId, moneda, !esDemo)
  const cuentasDisponibles = esDemo ? (cuentasDemo?.[moneda] ?? CUENTAS_VACIAS) : (cuentasQ.data ?? CUENTAS_VACIAS)
  const cuentasPendientes = esDemo ? false : cuentasQ.isPending
  const cuentasReintentando = esDemo ? false : cuentasQ.isFetching
  const cuentasConError = esDemo ? false : cuentasQ.isError

  // Pre-vuelo legal. Deliberadamente NO bloquea cuando la consulta falla: es un
  // aviso, no la puerta. El servidor sigue siendo el único que decide, y
  // convertir un fallo de red en un contrato imposible sería inventar un muro
  // donde no lo hay. Solo se bloquea cuando el servidor DIJO que falta algo.
  const legales = esDemo ? undefined : legalesQ.data
  // Los nueve datos legales existen para UNA cosa: la fotografía contractual del
  // documento que emite el sistema. Un contrato firmado antes del 19/08 no lleva
  // ese documento —el cliente ya tiene el suyo, del formato anterior—, así que
  // exigirlos ahí es un muro sin nada detrás. Y no es un caso raro: en 30 días se
  // cargaron 214 contratos y solo 6 se firmaron del 19-ago en adelante. El
  // servidor aplica la misma frontera (`private.contrato_documental_regimen`).
  // Sin `creadoEn`: este contrato se esta creando AHORA, asi que el suelo de
  // registro lo cumple por definicion y solo decide la fecha de firma.
  const regimenDocumentalAnterior = esContratoRegimenAnterior(fechaInicio)
  const faltaDomicilio = !regimenDocumentalAnterior && legales?.faltaDomicilio === true && !domicilioConfirmado
  // Huecos que el vendedor NO puede cerrar desde aquí: el alta fallaría seguro,
  // así que se frena con el nombre del dato en vez de dejarle llenar el formulario.
  const otrosFaltantesCliente = (legales?.faltanCliente ?? []).filter((campo) => campo !== 'domicilio')
  const faltantesAnalista = legales?.faltanAnalista ?? []
  const bloqueoLegalAjeno =
    !regimenDocumentalAnterior && (otrosFaltantesCliente.length > 0 || faltantesAnalista.length > 0)
  const textoBloqueoLegalAjeno = [
    otrosFaltantesCliente.length > 0 ? `Al cliente le falta ${listarCampos(otrosFaltantesCliente)}.` : '',
    faltantesAnalista.length > 0 ? `A tu propio perfil le falta ${listarCampos(faltantesAnalista)}.` : '',
  ]
    .filter(Boolean)
    .join(' ')

  const guardarDomicilio = async () => {
    if (guardandoDomicilio) return
    setAvisoDomicilio(null)
    const validado = validarDomicilioLegal(domicilio)
    if (!validado.ok) {
      setErrorDomicilio(validado.error)
      return
    }
    setErrorDomicilio(null)
    setGuardandoDomicilio(true)
    let r: Awaited<ReturnType<typeof completarDomicilioCliente>>
    try {
      r = await completarDomicilioCliente(clienteId, validado.valor)
    } catch (fallo) {
      setErrorDomicilio(
        fallo instanceof CrmApiError ? fallo.message : 'No se pudo guardar el domicilio legal. Reintenta.',
      )
      setGuardandoDomicilio(false)
      return
    }
    // A partir de aquí el servidor YA confirmó: nada de lo que siga puede
    // decirle al vendedor que no se guardó. Antes vivía dentro del mismo try, y
    // una deriva del contrato de respuesta (subir a version 2, una clave nueva)
    // habría pintado toda escritura correcta como un fallo.
    try {
      // 'conservado' = otra sesión lo escribió primero y el servidor lo respetó.
      // Lo tecleado NO se guardó: se borra del campo para que nadie crea que sí,
      // y se dice con todas las letras. El servidor no devuelve el domicilio
      // ganador (sería una vía de lectura de PII para el supervisor), así que se
      // remite a la ficha del cliente, que ya lo enseña a quien puede verlo.
      if (r.accion === 'conservado') {
        setAvisoDomicilio(
          'Otra sesión ya había registrado el domicilio de este cliente y se conservó ese; ' +
            'lo que escribiste aquí NO se guardó. Puedes verlo en la ficha del cliente.',
        )
      } else {
        toast.success('Domicilio legal registrado')
      }
      // El servidor YA confirmó la escritura, así que el hueco está cerrado
      // pase lo que pase con la relectura. Se recuerda aquí porque
      // `refetch()` de TanStack RESUELVE aunque falle y deja `data` con el
      // valor viejo: sin esta marca, un fallo de red dejaría al vendedor
      // bloqueado por un muro que ya no existe, justo después de haberlo
      // derribado. Hallazgo de la auditoría adversaria del 2026-08-19.
      setDomicilioConfirmado(true)
      await legalesQ.refetch()
    } catch {
      /* la relectura es cortesía: el dato ya está guardado y confirmado */
    } finally {
      setGuardandoDomicilio(false)
    }
  }

  // Una revalidación puede retirar/versionar la cuenta elegida desde otra
  // sesión. Se limpia de inmediato; prepararCuentaPago lo vuelve a comprobar al
  // enviar como segunda defensa.
  useEffect(() => {
    if (!cuentaSeleccionada || cuentaSeleccionada === CUENTA_NUEVA) return
    if (!cuentasDisponibles.some((cuenta) => claveCuenta(cuenta) === cuentaSeleccionada)) {
      setCuentaSeleccionada('')
      setAvisoCuenta(
        'La cuenta que habías elegido cambió o ya no está disponible. Revísala y selecciona nuevamente el destino del contrato.',
      )
    }
  }, [cuentaSeleccionada, cuentasDisponibles])

  // Un error describe la fotografía del formulario en el instante del submit.
  // En cuanto cambia cualquier dato deja de ser vigente: retirarlo evita que un
  // lector de pantalla siga anunciando un diagnóstico ya corregido.
  useEffect(() => {
    setError(null)
    setCampoCuentaInvalido(null)
  }, [
    capital,
    capitalAdicional,
    capitalRenovado,
    categoria,
    cuentaNueva,
    cuentaSeleccionada,
    fechaInicio,
    modalidad,
    moneda,
    notas,
    numero,
    plazo,
    tasa,
    tipoInteres,
    titulares,
    vencManual,
  ])

  const esCompuesto = tipoInteres === 'compuesto'
  // parseMonto rechaza separadores de miles ('125,000' NO es 125) — ver lib/numero.
  const renovadoNum = parseMonto(capitalRenovado) ?? NaN
  const adicionalNum = parseMonto(capitalAdicional) ?? NaN
  const esRenovacion = categoria === 'renovacion'
  const capitalNum = esRenovacion ? renovadoNum + adicionalNum : (parseMonto(capital) ?? NaN)
  const tasaNum = parseMonto(tasa) ?? NaN

  // Vencimiento libre: preset o fecha escrita por el analista.
  const fechaVencimiento = useMemo(() => {
    if (plazo === PLAZO_PERSONALIZADO) return vencManual
    if (!fechaInicio) return ''
    return vencimientoDesdePlazo(fechaInicio, parseInt(plazo, 10))
  }, [plazo, vencManual, fechaInicio])

  const cronograma = useMemo(() => {
    // Mismo criterio que guardar(): sin tasa válida (>0 y ≤50) no se previsualiza
    // ni se habilita el botón (evita un cronograma de interés 0 que luego se rechaza).
    if (
      !Number.isFinite(capitalNum) ||
      capitalNum <= 0 ||
      !Number.isFinite(tasaNum) ||
      tasaNum <= 0 ||
      tasaNum > 50 ||
      !fechaInicio ||
      !fechaVencimiento
    ) {
      return []
    }
    return generarCronograma(capitalNum, tasaNum, fechaInicio, fechaVencimiento, modalidad, tipoInteres)
  }, [capitalNum, tasaNum, fechaInicio, fechaVencimiento, modalidad, tipoInteres])

  const totalCronograma = cronograma.reduce((a, c) => a + c.monto_programado, 0)

  // El generador SIEMPRE empuja la fila del RETORNO del capital, así que
  // `cronograma.length` NUNCA es 0 y el guard viejo (length === 0) no podía
  // dispararse jamás: se creaban contratos SIN una sola cuota de interés — p. ej.
  // 6 meses con modalidad anual (la 1ª cuota caería después del vencimiento) o
  // un vencimiento personalizado más corto que un periodo. Lo que hay que exigir
  // es RENDIMIENTO: al menos una cuota de interés y que sume más de 0.
  const cuotasInteres = cronograma.filter(esCuotaDeInteres)
  // Suma de importes numeric(12,2) ya redondeados: solo se compara contra 0.
  const interesProgramado = cuotasInteres.reduce((a, c) => a + c.monto_programado, 0)

  // Motivo ÚNICO de un cronograma que no se puede guardar: lo comparten el guard
  // de guardar() y el aviso de la vista previa (el asesor lo ve ANTES de pulsar).
  // null = cronograma válido.
  const motivoCronograma: string | null =
    cronograma.length === 0
      ? esCompuesto
        ? 'El interés compuesto requiere un plazo en años exactos'
        : 'No se pudo generar el cronograma — revisa las fechas'
      : cuotasInteres.length === 0
        ? 'Este cronograma no tiene NINGUNA cuota de interés: el plazo es más corto que un periodo de la modalidad elegida. Cambia la modalidad de pago o alarga el plazo.'
        : interesProgramado <= 0
          ? 'Las cuotas de interés salen en 0.00 con este capital y esta tasa: el contrato no pagaría rendimiento.'
          : null

  const cambiarTipo = (t: TipoInteres) => {
    setTipoInteres(t)
    if (t === 'compuesto' && !PLAZOS.find((p) => p.v === plazo)?.anioExacto) setPlazo('12')
  }

  const cambiarMoneda = (siguiente: Moneda) => {
    setMoneda(siguiente)
    setCuentaSeleccionada('')
    setCuentaNueva({ ...SECCION_BANCARIA_VACIA })
    setAvisoCuenta(null)
    setError(null)
  }

  const reportarError = (mensaje: string, campoCuenta: CampoSeccionBancaria | null = null) => {
    setError(mensaje)
    setCampoCuentaInvalido(campoCuenta)
    // El mensaje aparece después del evento; el timeout permite que React lo
    // monte antes de enfocar el campo culpable (o el resumen si no hay uno).
    window.setTimeout(() => {
      const destino = campoCuenta ? document.getElementById(ID_CAMPO_CUENTA[campoCuenta]) : errorRef.current
      destino?.focus()
    }, 0)
  }

  const guardar = async () => {
    if (enviando) return // guard anti doble-submit (además del disabled del botón)
    setError(null)
    setCampoCuentaInvalido(null)
    // Segunda defensa del pre-vuelo legal: el disabled del botón es la primera,
    // pero un submit por Enter con el foco en otro campo no lo atraviesa.
    if (faltaDomicilio) {
      reportarError('Falta el domicilio legal del cliente. Complétalo arriba: va escrito en el contrato.')
      return
    }
    if (bloqueoLegalAjeno) {
      reportarError(`${textoBloqueoLegalAjeno} Pídele a Gerencia que lo complete antes de emitir.`)
      return
    }
    // El N° debe ser EXACTAMENTE 6 dígitos (espejo de analista.js:800-805): sin
    // ellos el servidor inventaría la numeración vieja 'AC-2026-XXXX'.
    if (!RE_SEIS_DIGITOS.test(numero)) {
      reportarError(`El N° de contrato debe tener exactamente 6 dígitos (después de ${PREFIJO_CONTRATO}).`)
      return
    }
    const numeroContrato = `${PREFIJO_CONTRATO}${numero}`
    const errorNumero = validarNumero?.(numeroContrato)
    if (errorNumero) {
      reportarError(errorNumero)
      return
    }
    if (!categoria) {
      reportarError('Selecciona la categoría de la inversión (Nuevo, Renovación o Upgrade).')
      return
    }
    if (categoria === 'renovacion') {
      if (!renovacionOrigen) {
        reportarError('Abre la renovación desde el contrato que llegó a su fecha fin.')
        return
      }
      if (renovacionOrigen.fechaVencimiento > hoyLocal()) {
        reportarError(`Este contrato aún no llegó a su fecha fin (${fmtFecha(renovacionOrigen.fechaVencimiento)}).`)
        return
      }
      if (parseMonto(capitalRenovado) == null || !Number.isFinite(renovadoNum) || renovadoNum <= 0) {
        reportarError('El capital renovado debe ser mayor que 0.')
        return
      }
      if (renovadoNum > renovacionOrigen.capital) {
        reportarError(
          'El capital renovado no puede superar el capital del contrato anterior; registra la diferencia como adicional.',
        )
        return
      }
      if (parseMonto(capitalAdicional) == null || !Number.isFinite(adicionalNum) || adicionalNum < 0) {
        reportarError('El capital adicional debe ser 0 o un monto mayor.')
        return
      }
    } else if (capital.trim() && parseMonto(capital) == null) {
      reportarError(ERROR_MONTO)
      return
    }
    if (!Number.isFinite(capitalNum) || capitalNum < 100 || capitalNum > 100_000_000) {
      reportarError('El capital debe estar entre 100 y 100,000,000')
      return
    }
    if (!Number.isFinite(tasaNum) || tasaNum <= 0 || tasaNum > 50) {
      reportarError('La tasa anual debe ser mayor que 0 y hasta 50%')
      return
    }
    if (!fechaVencimiento) {
      reportarError('Falta la fecha de vencimiento')
      return
    }
    // Guard de RENDIMIENTO (no de longitud): sin cuotas de interés no hay contrato.
    if (motivoCronograma) {
      reportarError(motivoCronograma)
      return
    }
    if (cuentasPendientes || cuentasReintentando || cuentasConError) {
      reportarError(
        'No se pudo confirmar la cuenta de pago del contrato. Espera o reintenta la carga antes de crearlo.',
      )
      return
    }
    const cuentaPago = prepararCuentaPago({
      seleccion: cuentaSeleccionada,
      moneda,
      cuentas: cuentasDisponibles,
      nueva: cuentaNueva,
    })
    if (!cuentaPago.ok) {
      reportarError(cuentaPago.error, cuentaPago.campo ?? null)
      return
    }
    // Co-titulares: filas vacías se ignoran; una a medio llenar o duplicada
    // corta el guardado con el mensaje del núcleo (lib/titulares).
    const tit = normalizarTitulares(titulares)
    if (!tit.ok) {
      reportarError(tit.error)
      return
    }
    const input: CrearContratoInput = {
      cliente_id: clienteId,
      capital: capitalNum,
      moneda,
      tasa_anual: tasaNum,
      modalidad: esCompuesto ? 'anual' : modalidad,
      tipo_interes: tipoInteres,
      categoria,
      fecha_inicio: fechaInicio,
      fecha_vencimiento: fechaVencimiento,
      numero_contrato: numeroContrato,
      notas_internas: notas.trim() || null,
      ...(categoria === 'renovacion' && renovacionOrigen
        ? {
            contrato_origen_id: renovacionOrigen.id,
            capital_renovado: renovadoNum,
            capital_adicional: adicionalNum,
          }
        : {}),
      // Viajan DENTRO de p_contrato: crear_contrato ya los persiste (mancomunadas).
      titulares: tit.titulares,
      cuenta_pago: cuentaPago.cuenta,
      ...(analistaCierre ? { analista_cierre_id: analistaCierre } : {}),
    }
    const pdfDatosConfirmados: ContratoPdfDatos | null = pdfDatosDemo
      ? {
          ...pdfDatosDemo,
          contrato: {
            numero: input.numero_contrato ?? `${PREFIJO_CONTRATO}${numero}`,
            capital: input.capital,
            moneda: input.moneda,
            porcentaje: input.tasa_anual,
            fechaInicio: input.fecha_inicio,
            fechaVencimiento: input.fecha_vencimiento,
          },
          cotitulares: tit.titulares.map((titular) => ({
            nombreCompleto: titular.nombre_completo,
            tipoDocumento: titular.tipo_documento,
            documento: titular.documento,
          })),
        }
      : null
    setEnviando(true)
    onEnviandoCambio?.(true)
    try {
      const r = pdfDatosDemo
        ? {
            id: crearIdContratoDemo(),
            numero_contrato: numeroContrato,
            cuenta_bancaria_id: null,
            pdf: { estado: 'pendiente' as const },
          }
        : await crearContrato(input, cronograma)
      toast.success(`Contrato ${r.numero_contrato} creado para ${clienteNombre}`)
      const local: ContratoCreadoLocal | null = pdfDatosConfirmados
        ? {
            id: r.id,
            input: {
              ...input,
              numero_contrato: r.numero_contrato,
              titulares: (input.titulares ?? []).map((titular) => ({
                ...titular,
              })),
              cuenta_pago: { ...input.cuenta_pago },
            },
            cronograma: cronograma.map((cuota) => ({ ...cuota })),
            pdfDatos: {
              ...pdfDatosConfirmados,
              contrato: {
                ...pdfDatosConfirmados.contrato,
                numero: r.numero_contrato,
              },
              titular: { ...pdfDatosConfirmados.titular },
              analista: { ...pdfDatosConfirmados.analista },
              cotitulares:
                pdfDatosConfirmados.cotitulares?.map((titular) => ({
                  ...titular,
                })) ?? [],
            },
          }
        : null
      setCreado({
        id: r.id,
        numero: r.numero_contrato,
        archivo: null,
        estadoPdf: r.pdf.estado,
        archivando: !regimenDocumentalAnterior,
        errorArchivo: null,
        local,
      })
      if (local) onConfirmado?.(r.numero_contrato, local)
      else onConfirmado?.(r.numero_contrato)
      // Régimen anterior: no hay documento que archivar. Intentarlo devolvería
      // `sin_reserva` y pintaría un error rojo sobre un alta que salió perfecta.
      if (regimenDocumentalAnterior) return
      try {
        const archivo = local
          ? await archivarContratoPdfDemoHabilitado(r.id, local.pdfDatos)
          : await archivarContratoPdfConfirmado(r.id)
        setCreado((actual) =>
          actual?.id === r.id
            ? {
                ...actual,
                archivo,
                estadoPdf: 'sellado',
                archivando: false,
                errorArchivo: null,
              }
            : actual,
        )
      } catch (errorPdf) {
        const estadoPdf = errorPdf instanceof ContratoPdfNoSelladoError ? errorPdf.estado : 'pendiente'
        setCreado((actual) =>
          actual?.id === r.id
            ? {
                ...actual,
                estadoPdf,
                archivando: false,
                errorArchivo: local
                  ? 'El contrato demo quedó creado, pero el PDF local no pudo generarse. Puedes reintentar sin crear otro contrato.'
                  : estadoPdf === 'integridad_bloqueada'
                    ? 'El contrato quedó creado con reserva durable, pero el PDF requiere revisión por integridad.'
                    : 'El contrato quedó creado con una reserva PDF durable. Puedes reintentar el sellado sin crear otro contrato.',
              }
            : actual,
        )
      }
    } catch (e) {
      reportarError(e instanceof CrmApiError ? e.message : 'No se pudo crear el contrato')
    } finally {
      setEnviando(false)
      onEnviandoCambio?.(false)
    }
  }

  const reintentarArchivo = async () => {
    if (!creado || creado.archivando) return
    setCreado({ ...creado, archivando: true, errorArchivo: null })
    onEnviandoCambio?.(true)
    try {
      const archivo = creado.local
        ? await archivarContratoPdfDemoHabilitado(creado.id, creado.local.pdfDatos)
        : await archivarContratoPdfConfirmado(creado.id)
      setCreado((actual) =>
        actual?.id === creado.id
          ? {
              ...actual,
              archivo,
              estadoPdf: 'sellado',
              archivando: false,
              errorArchivo: null,
            }
          : actual,
      )
    } catch (errorPdf) {
      const estadoPdf = errorPdf instanceof ContratoPdfNoSelladoError ? errorPdf.estado : creado.estadoPdf
      setCreado((actual) =>
        actual?.id === creado.id
          ? {
              ...actual,
              estadoPdf,
              archivando: false,
              errorArchivo: creado.local
                ? 'El PDF demo sigue pendiente. Puedes reintentar o finalizar la simulación.'
                : estadoPdf === 'integridad_bloqueada'
                  ? 'El PDF está bloqueado por integridad y requiere revisión administrativa.'
                  : 'El job PDF sigue pendiente. Puedes reintentar o finalizar; la reserva permanece visible desde Mi cartera.',
            }
          : actual,
      )
    } finally {
      onEnviandoCambio?.(false)
    }
  }

  if (creado) {
    return (
      <>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <BadgeCheck className="size-5 text-primary" aria-hidden />
            Contrato {creado.numero} creado
          </DialogTitle>
        </DialogHeader>
        <DialogBody className="space-y-4">
          <div className="rounded-xl border border-primary/25 bg-primary/5 p-4">
            <p className="font-semibold text-foreground">El servidor confirmó el contrato de {clienteNombre}.</p>
            {creado.archivando && (
              <p role="status" className="mt-2 flex items-center gap-2 text-sm text-muted-foreground">
                <LoaderCircle className="size-4 animate-spin" aria-hidden />
                Generando y archivando la versión legal…
              </p>
            )}
            {!creado.archivando && !creado.archivo && (
              <p role="status" className="mt-2 text-sm text-muted-foreground">
                {regimenDocumentalAnterior ? (
                  <>
                    Contrato firmado antes del <b>{CONTRATO_DOCUMENTO_DESDE_TEXTO}</b>: queda registrado, y su contrato
                    sigue siendo el del formato anterior. El sistema no emite documento para él.
                  </>
                ) : (
                  <>
                    Estado documental: <b>{etiquetaEstadoContratoPdf(creado.estadoPdf)}</b>.
                  </>
                )}
              </p>
            )}
            {creado.archivo && (
              <p role="status" className="mt-2 text-sm font-semibold text-primary">
                PDF privado archivado correctamente. Las próximas descargas devolverán este mismo archivo.
              </p>
            )}
            {creado.errorArchivo && (
              <p role="alert" className="mt-2 text-sm font-semibold text-destructive">
                {creado.errorArchivo}
              </p>
            )}
          </div>
        </DialogBody>
        <DialogFooter className="flex-wrap">
          {creado.errorArchivo && creado.estadoPdf !== 'integridad_bloqueada' && (
            <Button type="button" variant="outline" onClick={() => void reintentarArchivo()}>
              <RefreshCw aria-hidden />
              Reintentar PDF
            </Button>
          )}
          <Button
            type="button"
            variant="outline"
            disabled={!creado.archivo || creado.archivando}
            onClick={() => {
              if (creado.archivo) verArchivoContratoPdf(creado.archivo)
            }}
          >
            <ExternalLink aria-hidden />
            Ver contrato PDF
          </Button>
          <Button
            type="button"
            disabled={!creado.archivo || creado.archivando}
            onClick={() => {
              if (creado.archivo) descargarArchivoContratoPdf(creado.archivo)
            }}
          >
            <Download aria-hidden />
            Descargar contrato PDF
          </Button>
          <Button
            type="button"
            variant="ghost"
            onClick={() => {
              if (creado.local) onCreado(creado.numero, creado.local)
              else onCreado(creado.numero)
            }}
            disabled={creado.archivando}
          >
            Finalizar
          </Button>
        </DialogFooter>
      </>
    )
  }

  return (
    <form
      className="flex min-h-0 flex-1 flex-col"
      aria-describedby={error ? 'ct-error-resumen' : undefined}
      onSubmit={(evento) => {
        evento.preventDefault()
        void guardar()
      }}
    >
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <FileSignature className="size-4 text-primary" />{' '}
          {categoria === 'renovacion' && renovacionOrigen
            ? `Renovar ${renovacionOrigen.numeroContrato}`
            : categoria === 'upgrade'
              ? `Registrar upgrade de ${clienteNombre}`
              : `Crear contrato de ${clienteNombre}`}
        </DialogTitle>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-3 overflow-y-auto">
        {faltaDomicilio && (
          <section
            aria-labelledby="ct-domicilio-titulo"
            className="space-y-2 rounded-lg border border-amber-500/40 bg-amber-500/10 p-3"
          >
            <h3 id="ct-domicilio-titulo" className="flex items-center gap-2 text-xs font-semibold">
              <Home className="size-4" aria-hidden="true" />
              Falta el domicilio legal de {clienteNombre}
            </h3>
            <p className="text-[11px] leading-relaxed text-muted-foreground">
              Va escrito literalmente en el contrato, así que sin él no se puede emitir. Complétalo aquí y sigue con el
              alta.
            </p>
            <div className="space-y-1.5">
              <Label htmlFor="ct-domicilio">Domicilio legal completo</Label>
              <Input
                id="ct-domicilio"
                value={domicilio}
                onChange={(e) => {
                  setDomicilio(e.target.value)
                  setErrorDomicilio(null)
                }}
                placeholder="Av./Jr./Calle, número, distrito, provincia y departamento"
                autoComplete="street-address"
                aria-invalid={errorDomicilio ? true : undefined}
                aria-describedby={errorDomicilio ? 'ct-domicilio-error' : undefined}
                disabled={guardandoDomicilio || enviando}
              />
            </div>
            {errorDomicilio && (
              <p id="ct-domicilio-error" role="alert" className="text-xs font-semibold text-destructive">
                {errorDomicilio}
              </p>
            )}
            {/* type="button": dentro del <form> del contrato, un submit aquí
                intentaría crear el contrato que este bloque está frenando. */}
            <Button
              type="button"
              size="sm"
              onClick={() => void guardarDomicilio()}
              disabled={guardandoDomicilio || enviando}
            >
              {guardandoDomicilio ? 'Guardando…' : 'Guardar domicilio'}
            </Button>
          </section>
        )}
        {/* FUERA del bloque de arriba a propósito: cuando el servidor responde
            "conservado" el hueco queda cerrado y la sección se desmonta — si el
            aviso viviera dentro, el vendedor nunca llegaría a leer QUÉ domicilio
            ganó, que es justo el que va a salir impreso en el contrato. */}
        {avisoDomicilio && (
          <p
            role="status"
            className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-[11px] font-semibold"
          >
            {avisoDomicilio}
          </p>
        )}
        {bloqueoLegalAjeno && (
          <p
            role="alert"
            className="rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs font-semibold text-destructive"
          >
            {textoBloqueoLegalAjeno} Sin eso el contrato no se puede emitir, y no se corrige desde aquí: pídeselo a
            Gerencia.
          </p>
        )}
        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-categoria">Categoría</Label>
            {categoriaFija || renovacionOrigen ? (
              <div
                id="ct-categoria"
                aria-label="Categoría"
                className="flex h-9 items-center rounded-lg border border-input bg-muted px-3 text-sm font-bold text-foreground"
              >
                {CATEGORIAS_CONTRATO_UI.find((opcion) => opcion.k === categoria)?.label ?? '—'}
              </div>
            ) : (
              <Select
                id="ct-categoria"
                value={categoria}
                onChange={(e) => setCategoria(e.target.value as CategoriaContrato | '')}
                disabled={enviando}
              >
                <option value="" disabled>
                  — Seleccionar —
                </option>
                {CATEGORIAS_CONTRATO_UI.filter((c) => c.k !== 'renovacion').map((c) => (
                  <option key={c.k} value={c.k}>
                    {c.label}
                  </option>
                ))}
              </Select>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-tipo">Tipo de interés</Label>
            <Select
              id="ct-tipo"
              value={tipoInteres}
              onChange={(e) => cambiarTipo(e.target.value as TipoInteres)}
              disabled={enviando}
            >
              <option value="simple">Simple</option>
              <option value="compuesto">Compuesto</option>
            </Select>
          </div>
        </div>

        {analistas && analistas.length > 0 ? (
          <div className="space-y-1.5">
            <Label htmlFor="ct-analista">Analista de la venta</Label>
            <Select
              id="ct-analista"
              value={analistaCierre}
              onChange={(e) => setAnalistaCierre(e.target.value)}
              disabled={enviando}
              aria-describedby="ct-analista-ayuda"
            >
              <option value="">Sin asignar</option>
              {analistas.map((a) => (
                <option key={a.perfil_id} value={a.perfil_id}>
                  {a.nombre_completo}
                </option>
              ))}
            </Select>
            <p id="ct-analista-ayuda" className="text-xs text-muted-foreground">
              De quién es la venta. Si no corresponde a nadie más, déjala a tu nombre.
            </p>
          </div>
        ) : null}

        {esRenovacion && renovacionOrigen ? (
          <section
            aria-label="Puente de capital de la renovación"
            className="rounded-xl border border-primary/25 bg-primary/5 p-3"
          >
            <p className="text-[10px] font-extrabold uppercase tracking-[0.16em] text-primary">
              Puente de capital · {renovacionOrigen.moneda}
            </p>
            <div className="mt-2 grid grid-cols-[minmax(0,1fr)_auto] items-end gap-2 sm:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)_auto_minmax(0,1fr)]">
              <div className="space-y-1">
                <Label htmlFor="ct-capital-anterior">Contrato anterior</Label>
                <Input
                  id="ct-capital-anterior"
                  value={String(renovacionOrigen.capital)}
                  readOnly
                  aria-readonly="true"
                  className="font-bold tabular-nums"
                />
              </div>
              <ArrowRight className="mb-2 size-4 text-muted-foreground" aria-hidden />
              <div className="col-span-2 space-y-1 sm:col-span-1">
                <Label htmlFor="ct-capital-renovado">Capital renovado</Label>
                <Input
                  id="ct-capital-renovado"
                  inputMode="decimal"
                  value={capitalRenovado}
                  onChange={(e) => setCapitalRenovado(e.target.value)}
                  disabled={enviando}
                />
              </div>
              <Plus className="mb-2 hidden size-4 text-muted-foreground sm:block" aria-hidden />
              <div className="col-span-2 space-y-1 sm:col-span-1">
                <Label htmlFor="ct-capital-adicional">Capital adicional</Label>
                <Input
                  id="ct-capital-adicional"
                  inputMode="decimal"
                  value={capitalAdicional}
                  onChange={(e) => setCapitalAdicional(e.target.value)}
                  disabled={enviando}
                />
              </div>
            </div>
            <div className="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-lg bg-card px-3 py-2 ring-1 ring-border">
              <span className="text-xs font-semibold text-muted-foreground">Nuevo contrato</span>
              <span className="text-base font-extrabold tabular-nums text-primary">
                {Number.isFinite(capitalNum) ? money(capitalNum, moneda) : '—'}
              </span>
            </div>
            <p className="mt-2 text-[11px] leading-relaxed text-muted-foreground">
              La renovación suma una conversión por cliente en el mes. El adicional queda separado para su pago y no
              crea otra conversión.
            </p>
          </section>
        ) : (
          <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor="ct-capital">Capital</Label>
              <Input
                id="ct-capital"
                inputMode="decimal"
                value={capital}
                onChange={(e) => setCapital(e.target.value)}
                placeholder="10000"
                disabled={enviando}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ct-moneda">Moneda</Label>
              <Select
                id="ct-moneda"
                value={moneda}
                onChange={(e) => cambiarMoneda(e.target.value as Moneda)}
                disabled={enviando}
              >
                <option value="PEN">Soles (PEN)</option>
                <option value="USD">Dólares (USD)</option>
              </Select>
            </div>
          </div>
        )}

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-tasa">Tasa anual (%)</Label>
            <Input
              id="ct-tasa"
              inputMode="decimal"
              value={tasa}
              onChange={(e) => setTasa(e.target.value)}
              placeholder="18"
              disabled={enviando}
            />
          </div>
          {!esCompuesto && (
            <div className="space-y-1.5">
              <Label htmlFor="ct-modalidad">Modalidad de pago</Label>
              <Select
                id="ct-modalidad"
                value={modalidad}
                onChange={(e) => setModalidad(e.target.value as ModalidadContrato)}
                disabled={enviando}
              >
                {MODALIDADES_UI.map((m) => (
                  <option key={m.k} value={m.k}>
                    {m.label}
                  </option>
                ))}
              </Select>
            </div>
          )}
        </div>

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-inicio">Fecha de inicio</Label>
            <Input
              id="ct-inicio"
              type="date"
              value={fechaInicio}
              onChange={(e) => setFechaInicio(e.target.value)}
              disabled={enviando}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-plazo">Plazo</Label>
            <Select id="ct-plazo" value={plazo} onChange={(e) => setPlazo(e.target.value)} disabled={enviando}>
              {PLAZOS.map((p) => (
                <option key={p.v} value={p.v} disabled={esCompuesto && !p.anioExacto}>
                  {p.label}
                </option>
              ))}
            </Select>
          </div>
        </div>

        {plazo === PLAZO_PERSONALIZADO ? (
          <div className="space-y-1.5">
            <Label htmlFor="ct-venc">Fecha de vencimiento</Label>
            <Input
              id="ct-venc"
              type="date"
              value={vencManual}
              onChange={(e) => setVencManual(e.target.value)}
              disabled={enviando}
            />
          </div>
        ) : (
          fechaVencimiento && (
            <p className="text-[11px] text-muted-foreground">
              Vence el <b className="text-foreground">{fmtFecha(fechaVencimiento)}</b> (calculado del plazo).
            </p>
          )
        )}

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-numero">N° de contrato</Label>
            <div className="flex">
              {/* Prefijo FIJO pintado: imposible de borrar (espejo de analista.html). */}
              <span
                aria-hidden
                className="inline-flex h-9 items-center rounded-l-lg border border-r-0 border-input bg-muted px-2.5 text-sm font-bold tabular-nums text-muted-foreground"
              >
                {PREFIJO_CONTRATO}
              </span>
              <Input
                id="ct-numero"
                className="rounded-l-none"
                inputMode="numeric"
                maxLength={6}
                placeholder="000000"
                autoComplete="off"
                title="Exactamente 6 dígitos"
                value={numero}
                // Solo dígitos, máx 6 — bloquea letras/espacios al teclear o pegar
                // (espejo del listener de k_numero en analista.js:1041-1043).
                onChange={(e) => setNumero(e.target.value.replace(/\D/g, '').slice(0, 6))}
                disabled={enviando}
              />
            </div>
            <p className="text-[11px] text-muted-foreground">
              Escribe los <b className="text-foreground">6 dígitos</b>. El{' '}
              <b className="text-foreground">{PREFIJO_CONTRATO}</b> es fijo.
            </p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-notas">Notas internas (opcional)</Label>
            <Input
              id="ct-notas"
              value={notas}
              maxLength={500}
              onChange={(e) => setNotas(e.target.value)}
              placeholder="—"
              disabled={enviando}
            />
          </div>
        </div>

        <CuentaPagoContrato
          moneda={moneda}
          cuentas={cuentasDisponibles}
          seleccion={cuentaSeleccionada}
          nueva={cuentaNueva}
          cargando={cuentasPendientes}
          error={cuentasConError}
          reintentando={cuentasReintentando}
          deshabilitado={enviando}
          campoNuevaInvalido={campoCuentaInvalido}
          {...(error ? { errorId: 'ct-error-resumen' } : {})}
          onSeleccion={(seleccion) => {
            setCuentaSeleccionada(seleccion)
            setAvisoCuenta(null)
            setError(null)
          }}
          onNueva={setCuentaNueva}
          onReintentar={() => {
            if (!esDemo) void cuentasQ.refetch()
          }}
        />

        {avisoCuenta && (
          <p role="status" className="rounded-lg bg-warning/10 px-3 py-2 text-xs font-semibold text-warning-text">
            {avisoCuenta}
          </p>
        )}

        {/* Co-titulares (cuenta mancomunada) — hasta 5, viajan en p_contrato. */}
        <div className="rounded-xl border border-border p-3">
          <TitularesEditor value={titulares} onChange={setTitulares} disabled={enviando} idPrefix="ct-tit" />
        </div>

        {/* Vista previa del cronograma */}
        <div className="rounded-xl border border-border bg-muted/40 p-3">
          <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Cronograma</p>
          {cronograma.length === 0 ? (
            <p className="mt-1 text-xs text-muted-foreground">
              Completa capital, tasa y fechas para previsualizar el cronograma.
            </p>
          ) : (
            <div className="mt-1.5 space-y-0.5 text-xs">
              <p className="text-foreground">
                <b>{cronograma.length}</b> {cronograma.length === 1 ? 'cuota' : 'cuotas'} · total programado{' '}
                <b className="tabular-nums text-primary">{money(totalCronograma, moneda)}</b>
              </p>
              {/* Se cuentan aparte las de INTERÉS: el total incluye la devolución
                  del capital y por sí solo hace parecer válido un cronograma vacío
                  de rendimiento. */}
              <p className="text-muted-foreground">
                De ellas, <b className="text-foreground">{cuotasInteres.length}</b> de interés por{' '}
                <b className="tabular-nums text-foreground">{money(interesProgramado, moneda)}</b>
              </p>
              <p className="text-muted-foreground">
                Primera: {fmtFecha(cronograma[0]!.fecha_programada)} · Última:{' '}
                {fmtFecha(cronograma[cronograma.length - 1]!.fecha_programada)}
              </p>
              {/* Sin role=alert: se recalcula en CADA tecla (sería ruido para el
                  lector de pantalla); el botón deshabilitado es el freno real. */}
              {motivoCronograma && <p className="font-semibold text-destructive">{motivoCronograma}</p>}
            </div>
          )}
        </div>

        {error && (
          <p
            ref={errorRef}
            id="ct-error-resumen"
            role="alert"
            tabIndex={-1}
            className="rounded-lg bg-destructive/10 px-3 py-2 text-xs font-semibold text-destructive outline-none"
          >
            {error}
          </p>
        )}
      </DialogBody>
      <DialogFooter className="justify-between">
        <Button type="button" variant="ghost" size="sm" onClick={onOmitir} disabled={enviando}>
          {categoriaFija || renovacionOrigen ? 'Cancelar' : 'Omitir por ahora'}
        </Button>
        {/* Se bloquea por el MOTIVO (sin cuotas de interés incluido), no por la
            longitud del cronograma — que nunca es 0 (siempre trae el retorno). */}
        <Button
          type="submit"
          size="sm"
          disabled={
            enviando ||
            motivoCronograma !== null ||
            cuentasPendientes ||
            cuentasReintentando ||
            cuentasConError ||
            !cuentaSeleccionada ||
            // Faltas legales CONFIRMADAS por el servidor. Un fallo de la consulta
            // NO entra aquí a propósito: dejaría sin emitir a quien lo tiene todo.
            faltaDomicilio ||
            bloqueoLegalAjeno
          }
        >
          <BadgeCheck />{' '}
          {enviando
            ? 'Creando…'
            : categoria === 'renovacion'
              ? 'Crear renovación'
              : categoria === 'upgrade'
                ? 'Crear upgrade'
                : 'Crear contrato'}
        </Button>
      </DialogFooter>
    </form>
  )
}
