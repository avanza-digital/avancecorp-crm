// Corrección de contrato — espejo del "Corregir" del portal (analista.js:
// abrirModalContratoCorregir + guardarContrato). Reglas que NO se negocian:
//  - Ventana de 5 h: la decide el SERVIDOR (la RPC revalida creado_por → 5 h →
//    cartera y su rechazo llega como P0001); aquí lib/ventana es solo cortesía.
//  - TRAMPA 1: p_contrato SIEMPRE lleva notas_internas (si la clave falta, el
//    servidor las BORRA) → se precargan del contrato y viajan aunque sean null.
//  - TRAMPA 2: 'titulares' presente REEMPLAZA el set completo → se cargan los
//    actuales ANTES de habilitar el guardado; si su carga falló, la clave se
//    OMITE (ausente = el servidor no los toca) y se avisa.
//  - N° de contrato: prefijo FIJO '2026-01-' + 6 dígitos OBLIGATORIOS.
//  - El cronograma se REGENERA con lib/cronograma (mismo generador del preview);
//    el servidor conserva las cuotas ya pagadas.
// Se monta DENTRO de <Dialog> (mismo patrón que ContratoNuevo).
import { useEffect, useMemo, useState } from 'react'
import { FileSignature, Plus, RotateCcw, Save, X } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import {
  CODIGO_PRODUCTO_HISTORICO,
  ProductoContratoSelector } from '@/components/app/producto-contrato-selector'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { ERROR_MONTO, parseMonto } from '@/lib/numero'
import { fmtFecha, money, type Moneda } from '@/lib/format'
import {
  actualizarContrato,
  CrmApiError,
  type ActualizarContratoInput } from '@/data/crm-api'
import { useHistorialTasaCliente, useTitulares } from '@/data/crm-queries'
import { TasaPolitica, type RangoTasaPolitica } from '@/components/app/tasa-politica'
import { rangoEfectivo } from '@/lib/rentabilidad'
import { useProductosSeleccionables } from '@/data/crm-config-queries'
import { validarRangosProducto } from '@/lib/contrato-producto'
import type { ProductoCondicionSeleccion } from '@/lib/productos-inversion'
import {
  esCuotaDeInteres,
  generarCronograma,
  parseDateLocal,
  vencimientoDesdePlazo,
  type CategoriaContrato,
  type ModalidadContrato,
  type TipoInteres,
} from '@/lib/cronograma'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import { normalizarTitulares } from '@/lib/titulares'
import { useVentana } from '@/lib/ventana'
import { MAX_TITULARES, type ContratoRow } from '@/lib/clientes-tipos'
import {
  asegurarContratoPdfActualizado,
  esContratoRegimenAnterior,
} from '@/lib/contrato-pdf-archivo'
import {
  CATEGORIAS_CONTRATO_UI,
  MODALIDADES_UI,
  PLAZOS_BASE,
  PREFIJO_CONTRATO,
  RE_SEIS_DIGITOS,
} from '@/lib/contratos-catalogo'

// Meses calendario entre dos fechas YYYY-MM-DD (espejo de mesesEntre de
// analista.js) — solo para ETIQUETAR el plazo real; nunca decide el vencimiento.
function mesesEntre(inicio: string, fin: string): number {
  const a = parseDateLocal(inicio)
  const b = parseDateLocal(fin)
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth())
}

// Valor centinela del plazo que NO es preset (mismo nombre que en ContratoNuevo).
const PLAZO_PERSONALIZADO = 'personalizado'

/**
 * Preset que reproduce EXACTAMENTE el vencimiento guardado, o undefined si el
 * plazo es personalizado. Contar meses NO basta: un contrato del 15-01 que vence
 * el 20-07 mide "6 meses" contados y sin embargo el preset de 6 daría el 15-07 —
 * elegirlo recortaba el vencimiento pactado en silencio al guardar.
 */
function presetDelVencimiento(inicio: string, vencimiento: string) {
  return PLAZOS_BASE.find((p) => vencimientoDesdePlazo(inicio, p.meses) === vencimiento)
}

/** Fila cruda del editor de co-titulares (se normaliza recién al guardar). */
interface FilaTitular {
  nombre: string
  tipo: TipoDocumento
  documento: string
}

export interface ContratoCorregirProps {
  contrato: ContratoRow
  onGuardado: () => void
  onCerrar: () => void
  onEnviandoCambio?: (enviando: boolean) => void
  sinLimiteVentana?: boolean
  deshabilitado?: boolean
}

export function ContratoCorregir({ contrato, onGuardado, onCerrar, onEnviandoCambio, sinLimiteVentana = false, deshabilitado = false }: ContratoCorregirProps) {
  const ventana = useVentana(contrato.creado_en)
  const [productoCondicionId, setProductoCondicionId] = useState(contrato.producto_condicion_id)
  const [avisoProducto, setAvisoProducto] = useState<string | null>(null)
  const qProductos = useProductosSeleccionables()
  // Una cuenta contractual ya está versionada en la moneda original. Cambiar
  // de moneda exigiría otra operación bancaria; esta corrección solo ofrece
  // condiciones compatibles con la cuenta que ya pertenece al contrato.
  const condicionesCompatibles = useMemo(
    () => (qProductos.data ?? []).filter((item) => item.moneda === contrato.moneda),
    [contrato.moneda, qProductos.data],
  )
  const condicionProducto = condicionesCompatibles.find(
    (item) => item.condicion_id === productoCondicionId) ?? null
  const esCondicionOriginal = productoCondicionId === contrato.producto_condicion_id
  const esSnapshotHistorico =
    esCondicionOriginal && contrato.producto_codigo === CODIGO_PRODUCTO_HISTORICO
  const esVersionCatalogadaNoVigente =
    esCondicionOriginal && !esSnapshotHistorico && condicionProducto == null
  const terminosFijosPorCatalogo = condicionProducto != null

  // Solo los 6 dígitos del formato nuevo; una numeración vieja (AC-2026-XXXX)
  // deja el casillero vacío y obliga a asignar el formato actual al guardar.
  const numeroInicial = new RegExp(`^${PREFIJO_CONTRATO}(\\d{6})$`).exec(contrato.numero_contrato)?.[1] ?? ''
  const esNumeracionVieja = numeroInicial === ''

  const [numero, setNumero] = useState(numeroInicial)
  const [categoria, setCategoria] = useState<CategoriaContrato | ''>(contrato.categoria ?? '')
  const [tipoInteres, setTipoInteres] = useState<TipoInteres>(contrato.tipo_interes)
  const [modalidad, setModalidad] = useState<ModalidadContrato>(contrato.modalidad)
  const [capital, setCapital] = useState(String(contrato.capital))
  const [moneda, setMoneda] = useState<Moneda>(contrato.moneda)
  const [tasa, setTasa] = useState(String(contrato.tasa_anual))
  // Rentabilidad R3: cambiar la tasa exige la autorización de Gerencia (bloque TasaPolitica en modo corrección).
  const [rangoTasa, setRangoTasa] = useState<RangoTasaPolitica | null>(null)
  // El contrato origen de una renovación/upgrade lo conoce el ledger (R2), no la fila del contrato: hace falta para pedir excepción.
  const historialTasa = useHistorialTasaCliente(contrato.cliente_id, true)
  const origenSegunLedger = historialTasa.data?.contratos.find((c) => c.contrato_id === contrato.id)?.observacion?.contrato_origen_id ?? null
  const [fechaInicio, setFechaInicio] = useState(contrato.fecha_inicio)
  // El select muestra el plazo REAL: si ningún preset reproduce el vencimiento
  // guardado, arranca en 'personalizado' (antes caía a '12' y enseñaba "1 año"
  // para un contrato de, p. ej., 18 meses — y al guardar lo recortaba de verdad).
  const presetInicial = presetDelVencimiento(contrato.fecha_inicio, contrato.fecha_vencimiento)
  const [plazo, setPlazo] = useState(presetInicial ? String(presetInicial.meses) : PLAZO_PERSONALIZADO)
  // Se PRESERVA el vencimiento REAL al abrir (espejo del portal): recalcularlo
  // de un plazo no-preset lo pisaría sin querer. Solo cambia si el usuario toca
  // el plazo, la fecha de inicio con un preset elegido, o el vencimiento a mano.
  const [venc, setVenc] = useState(contrato.fecha_vencimiento)
  const [notas, setNotas] = useState(contrato.notas_internas ?? '')
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (esCondicionOriginal || !qProductos.data) return
    if (!condicionesCompatibles.some((item) => item.condicion_id === productoCondicionId)) {
      setProductoCondicionId(contrato.producto_condicion_id)
      setCategoria(contrato.categoria ?? '')
      setTipoInteres(contrato.tipo_interes)
      setModalidad(contrato.modalidad)
      setCapital(String(contrato.capital))
      setMoneda(contrato.moneda)
      setTasa(String(contrato.tasa_anual))
      setFechaInicio(contrato.fecha_inicio)
      setVenc(contrato.fecha_vencimiento)
      const preset = presetDelVencimiento(contrato.fecha_inicio, contrato.fecha_vencimiento)
      setPlazo(preset ? String(preset.meses) : PLAZO_PERSONALIZADO)
      setAvisoProducto('La nueva condición dejó de estar vigente. Se restauró el origen contractual anterior.')
    }
  }, [
    condicionesCompatibles,
    contrato.capital,
    contrato.categoria,
    contrato.fecha_inicio,
    contrato.fecha_vencimiento,
    contrato.modalidad,
    contrato.moneda,
    contrato.producto_condicion_id,
    contrato.tasa_anual,
    contrato.tipo_interes,
    esCondicionOriginal,
    productoCondicionId,
    qProductos.data,
  ])

  // Co-titulares ACTUALES cargados antes de habilitar el guardado (la trampa
  // del reemplazo: la clave presente REEMPLAZA el set completo en el servidor).
  // Van por caché (clave titulares(id)) con staleTime 0: la precarga blinda un
  // UPDATE destructivo y revalida SIEMPRE al abrir — jamás se siembra el editor
  // con la copia que dejó cacheada el detalle. 'error' NO bloquea el resto de
  // la corrección: se omite la clave.
  const qTitulares = useTitulares(contrato.id, true, { staleTime: 0 })
  const [titulares, setTitulares] = useState<FilaTitular[]>([])
  const [sembrado, setSembrado] = useState(false)

  // Siembra ÚNICA y solo con datos RECIÉN traídos: isFetchedAfterMount exige un
  // fetch COMPLETADO tras el mount — sin red el refetch queda 'paused' (isFetching
  // false + isSuccess true con la copia cacheada) y sembrar esa copia vieja haría
  // que el guardado REEMPLACE en el servidor co-titulares corregidos por otra
  // sesión. Un refetch posterior (foco de ventana) no debe pisar la edición.
  useEffect(() => {
    if (sembrado || !qTitulares.isSuccess || qTitulares.isFetching || !qTitulares.isFetchedAfterMount) return
    setTitulares(
      qTitulares.data.map((t) => ({
        nombre: t.nombre_completo,
        tipo: t.tipo_documento,
        documento: t.documento,
      })),
    )
    setSembrado(true)
  }, [sembrado, qTitulares.isSuccess, qTitulares.isFetching, qTitulares.isFetchedAfterMount, qTitulares.data])

  // Una vez sembrado, el editor manda: un fallo de refetch posterior no lo
  // apaga (apagarlo omitiría la clave y descartaría en silencio la edición).
  const estadoTitulares: 'cargando' | 'ok' | 'error' = sembrado ? 'ok' : qTitulares.isError ? 'error' : 'cargando'

  const esCompuesto = tipoInteres === 'compuesto'
  // parseMonto rechaza separadores de miles ('125,000' NO es 125) — ver lib/numero.
  const capitalNum = parseMonto(capital) ?? NaN
  const tasaNum = parseMonto(tasa) ?? NaN

  const esPersonalizado = plazo === PLAZO_PERSONALIZADO
  // Duración REAL en meses (solo para etiquetar la opción 'Personalizado'): el
  // vencimiento exacto se ve al lado, en su propio campo.
  const mesesReales = fechaInicio && venc ? mesesEntre(fechaInicio, venc) : 0

  const cambiarInicio = (v: string) => {
    setFechaInicio(v)
    if (v && condicionProducto) {
      setVenc(vencimientoDesdePlazo(v, condicionProducto.plazo_meses))
      return
    }
    // Con plazo PERSONALIZADO el vencimiento pactado NO se toca: recalcularlo
    // desde un preset inventado (antes, siempre '12') recortaba el contrato en
    // silencio. Se conserva y el aviso de abajo lo dice explícitamente; si debe
    // moverse, el analista lo edita a mano en el campo de vencimiento.
    if (v && !esPersonalizado) setVenc(vencimientoDesdePlazo(v, parseInt(plazo, 10)))
  }
  const cambiarPlazo = (v: string) => {
    setPlazo(v)
    // Pasar a 'personalizado' conserva el vencimiento actual (es justamente el
    // valor que no cabe en ningún preset); elegir un preset sí lo recalcula —
    // pero eso es una decisión EXPLÍCITA del analista y se ve al instante.
    if (fechaInicio && v !== PLAZO_PERSONALIZADO) setVenc(vencimientoDesdePlazo(fechaInicio, parseInt(v, 10)))
  }

  const restaurarTerminosOriginales = () => {
    setCategoria(contrato.categoria ?? '')
    setTipoInteres(contrato.tipo_interes)
    setModalidad(contrato.modalidad)
    setCapital(String(contrato.capital))
    setMoneda(contrato.moneda)
    setTasa(String(contrato.tasa_anual))
    setFechaInicio(contrato.fecha_inicio)
    setVenc(contrato.fecha_vencimiento)
    const preset = presetDelVencimiento(contrato.fecha_inicio, contrato.fecha_vencimiento)
    setPlazo(preset ? String(preset.meses) : PLAZO_PERSONALIZADO)
  }

  const seleccionarProducto = (id: string, condicion: ProductoCondicionSeleccion | null) => {
    setProductoCondicionId(id)
    setAvisoProducto(null)
    if (!condicion) {
      restaurarTerminosOriginales()
      return
    }
    setCategoria(condicion.categoria)
    setTipoInteres(condicion.tipo_interes)
    setModalidad(condicion.modalidad)
    setMoneda(condicion.moneda)
    setPlazo(String(condicion.plazo_meses))
    setVenc(fechaInicio ? vencimientoDesdePlazo(fechaInicio, condicion.plazo_meses) : '')
    const capitalActual = parseMonto(capital)
    if (capitalActual == null || capitalActual < condicion.capital_minimo || capitalActual > condicion.capital_maximo) {
      setCapital(String(condicion.capital_minimo))
    }
    setTasa(String(condicion.tasa_referencia))
  }

  // Mismo generador del preview de ContratoNuevo: lo que se ve es lo que viaja.
  const cronograma = useMemo(() => {
    if (
      !Number.isFinite(capitalNum) ||
      capitalNum <= 0 ||
      !Number.isFinite(tasaNum) ||
      tasaNum <= 0 ||
      tasaNum > 50 ||
      !fechaInicio ||
      !venc
    ) {
      return []
    }
    return generarCronograma(capitalNum, tasaNum, fechaInicio, venc, modalidad, tipoInteres)
  }, [capitalNum, tasaNum, fechaInicio, venc, modalidad, tipoInteres])

  const totalCronograma = cronograma.reduce((a, c) => a + c.monto_programado, 0)

  // Mismo guard de RENDIMIENTO que ContratoNuevo: el generador SIEMPRE empuja la
  // fila del retorno del capital, así que `cronograma.length` nunca es 0 y el
  // guard viejo (length === 0) no podía dispararse — una corrección podía dejar
  // el contrato sin UNA sola cuota de interés (p. ej. bajando el plazo a 6 meses
  // con modalidad anual). Se exige al menos una cuota de interés que sume > 0.
  const cuotasInteres = cronograma.filter(esCuotaDeInteres)
  // Suma de importes numeric(12,2) ya redondeados: solo se compara contra 0.
  const interesProgramado = cuotasInteres.reduce((a, c) => a + c.monto_programado, 0)

  // Motivo ÚNICO (null = válido): lo comparten el guard de guardar() y el aviso
  // de la vista previa, para que el analista lo vea ANTES de pulsar Guardar.
  const motivoCronograma: string | null =
    cronograma.length === 0
      ? esCompuesto
        ? 'El interés compuesto requiere un plazo en años exactos (12, 24, 36, 48 o 60 meses).'
        : 'Las fechas/modalidad no permiten generar un cronograma.'
      : cuotasInteres.length === 0
        ? 'Este cronograma no tiene NINGUNA cuota de interés: el plazo es más corto que un periodo de la modalidad elegida. Cambia la modalidad de pago o alarga el plazo.'
        : interesProgramado <= 0
          ? 'Las cuotas de interés salen en 0.00 con este capital y esta tasa: el contrato no pagaría rendimiento.'
          : null

  // ── Editor de co-titulares ────────────────────────────────────────────────
  const setFila = (i: number, patch: Partial<FilaTitular>) =>
    setTitulares((filas) => filas.map((f, j) => (j === i ? { ...f, ...patch } : f)))
  const agregarFila = () => setTitulares((filas) => [...filas, { nombre: '', tipo: 'DNI', documento: '' }])
  const quitarFila = (i: number) => setTitulares((filas) => filas.filter((_, j) => j !== i))

  const guardar = async () => {
    if (enviando || deshabilitado) return // servidor revalida siempre la autorización
    setError(null)
    if (rangoTasa?.bloqueoContrato) {
      setError(rangoTasa.bloqueoContrato)
      return
    }
    if (!productoCondicionId) {
      setError('El contrato no tiene una condición de producto confirmada.')
      return
    }
    if (
      !esCondicionOriginal &&
      (qProductos.isPending || qProductos.isFetching || qProductos.isError || !condicionProducto)
    ) {
      setError('La nueva condición debe seguir publicada y vigente antes de guardar.')
      return
    }
    // Validaciones espejo de guardarContrato de analista.js (mensajes tal cual).
    if (!RE_SEIS_DIGITOS.test(numero)) {
      setError('El N° de contrato debe tener exactamente 6 dígitos (después de 2026-01-).')
      return
    }
    if (capital.trim() && parseMonto(capital) == null) {
      setError(ERROR_MONTO)
      return
    }
    if (!Number.isFinite(capitalNum) || !capitalNum || !fechaInicio || !venc) {
      setError('Completa capital, fecha de inicio y plazo.')
      return
    }
    if (!Number.isFinite(tasaNum) || tasaNum <= 0 || tasaNum > 50) {
      setError('La tasa anual debe estar entre 0 y 50%.')
      return
    }
    // Rentabilidad: SIEMPRE (también con producto de catálogo): la tasa vigente solo cambia con autorización de Gerencia.
    // La vigencia se comprueba con el reloj de AHORA (el bloque solo refresca el suyo cada minuto): caducada → tasa vigente.
    const rango = rangoTasa ? rangoEfectivo(rangoTasa) : null
    if (rango?.caducada && rango.minimo != null && tasaNum > rango.minimo + 1e-9) {
      setError(`La autorización de Gerencia venció: la tasa se queda en la vigente (${rango.minimo}%). Vuelve a solicitarla si la necesitas.`)
      return
    }
    if (rango && rango.minimo != null && rango.maximo != null
        && (tasaNum < rango.minimo - 1e-9 || tasaNum > rango.maximo + 1e-9)) {
      setError(rango.minimo === rango.maximo
        ? `La tasa vigente del contrato es ${rango.minimo}%. Cambiarla exige la autorización de Gerencia: usa «Solicitar tasa superior».`
        : `La tasa debe estar entre ${rango.minimo}% y ${rango.maximo}% (autorizada por Gerencia).`)
      return
    }
    if (condicionProducto) {
      const errorRango = validarRangosProducto(condicionProducto, {
        capital: capitalNum,
        tasa: tasaNum,
      })
      if (errorRango) {
        setError(errorRango)
        return
      }
    }
    if (capitalNum < 100) {
      setError('El capital debe ser de al menos 100.')
      return
    }
    if (!categoria) {
      setError('Selecciona la categoría de la inversión (Nuevo, Renovación o Upgrade).')
      return
    }
    // Guard de RENDIMIENTO (no de longitud): sin cuotas de interés no se guarda.
    if (motivoCronograma) {
      setError(motivoCronograma)
      return
    }
    // Co-titulares: solo si sus valores ACTUALES cargaron (presente = reemplazar).
    // La normalización es la de lib/titulares (misma fuente que ContratoNuevo:
    // filas vacías se ignoran, error con posición, duplicados rechazados, máx 5).
    const tit =
      estadoTitulares === 'ok'
        ? normalizarTitulares(
            titulares.map((t) => ({
              nombre_completo: t.nombre,
              tipo_documento: t.tipo,
              documento: t.documento,
            })),
          )
        : null
    if (tit && !tit.ok) {
      setError(tit.error)
      return
    }

    const input: ActualizarContratoInput = {
      capital: capitalNum,
      moneda,
      tasa_anual: tasaNum,
      // Una condición catalogada conserva su modalidad exacta; el snapshot
      // legacy mantiene el comportamiento histórico del portal.
      modalidad: condicionProducto ? modalidad : esCompuesto ? 'anual' : modalidad,
      tipo_interes: tipoInteres,
      categoria,
      fecha_inicio: fechaInicio,
      fecha_vencimiento: venc,
      numero_contrato: PREFIJO_CONTRATO + numero,
      // TRAMPA 1: la clave viaja SIEMPRE (aunque sea null) o el servidor la borra.
      notas_internas: notas.trim() || null,
    }
    if (tit?.ok) input.titulares = tit.titulares

    setEnviando(true)
    onEnviandoCambio?.(true)
    try {
      await actualizarContrato(contrato.id, input, cronograma)
      // Un contrato firmado antes del 19/08 no lleva documento del sistema, así
      // que aquí no hay nada que actualizar. Sin este corte el servidor negaría
      // la revisión y el analista leería «el servidor reintentará el PDF» sobre
      // un PDF que no existe ni va a existir.
      // Se mira la fecha que ACABA de guardarse, no la que traía el contrato: si
      // la corrección movió la firma al 19/08 o después, el servidor ya la ve en
      // el régimen nuevo y sí va a reservar la revisión.
      if (esContratoRegimenAnterior(fechaInicio, contrato.creado_en)) {
        toast.success('Contrato corregido.')
        onGuardado()
        return
      }
      // La corrección y la reserva de la revisión son atómicas. El render puede
      // reintentarse aparte sin fingir que la corrección falló después de guardar.
      try {
        const pdf = await asegurarContratoPdfActualizado(contrato.id)
        if (pdf.estado === 'sellado') {
          toast.success('Contrato corregido y PDF actualizado.')
        } else {
          toast.warning('Contrato corregido. El PDF actualizado quedó pendiente de generación.')
        }
      } catch {
        toast.warning('Contrato corregido. El servidor reintentará el PDF actualizado al abrirlo.')
      }
      onGuardado()
    } catch (e) {
      // Los mensajes del servidor (RPC) ya vienen en español y claros — ventana
      // vencida, fuera de cartera, cuotas pagadas — y se muestran TAL CUAL.
      setError(e instanceof CrmApiError ? e.message : 'No se pudo guardar el contrato.')
    } finally {
      setEnviando(false)
      onEnviandoCambio?.(false)
    }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <FileSignature className="size-4 text-primary" aria-hidden />
          Corregir contrato {contrato.numero_contrato}
        </DialogTitle>
        <DialogDescription>
          Cliente: <b className="text-foreground">{contrato.cliente_nombre ?? '—'}</b> · Ventana de corrección:{' '}
          {/* Sin verde en el sistema ("positivo" = azul): vigente accent, vencida destructive. */}
          <span className={`font-semibold tabular-nums ${ventana.vigente ? 'text-accent' : 'text-destructive'}`}>
            {sinLimiteVentana ? 'Corrección administrativa' : ventana.texto}
          </span>
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-3 overflow-y-auto">
        <ProductoContratoSelector
          id="cc-producto"
          value={productoCondicionId}
          condiciones={condicionesCompatibles}
          actual={{
            condicionId: contrato.producto_condicion_id,
            codigo: contrato.producto_codigo,
            nombre: contrato.producto_nombre,
            version: contrato.producto_version,
            estado: contrato.producto_version_estado,
          }}
          cargando={qProductos.isPending}
          error={qProductos.isError}
          reintentando={qProductos.isFetching}
          disabled={enviando}
          onChange={seleccionarProducto}
          onReintentar={() => void qProductos.refetch()}
        />
        {avisoProducto && (
          <p role="status" className="rounded-lg bg-warning/10 px-3 py-2 text-xs font-semibold text-warning-text">
            {avisoProducto}
          </p>
        )}

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-numero">N° de contrato</Label>
            <div className="flex items-center gap-1.5">
              <span className="flex h-9 shrink-0 items-center rounded-lg border border-input bg-muted px-2.5 text-sm font-semibold tabular-nums text-muted-foreground">
                {PREFIJO_CONTRATO}
              </span>
              <Input
                id="cc-numero"
                inputMode="numeric"
                value={numero}
                // Solo dígitos, máx 6 — bloquea letras/espacios al teclear o pegar.
                onChange={(e) => setNumero(e.target.value.replace(/\D/g, '').slice(0, 6))}
                placeholder="000123"
                disabled={enviando}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cc-categoria">Categoría</Label>
            <Select
              id="cc-categoria"
              value={categoria}
              onChange={(e) => setCategoria(e.target.value as CategoriaContrato | '')}
              disabled={enviando || terminosFijosPorCatalogo || esVersionCatalogadaNoVigente}
            >
              <option value="">— Seleccionar —</option>
              {CATEGORIAS_CONTRATO_UI.map((c) => (
                <option key={c.k} value={c.k}>
                  {c.label}
                </option>
              ))}
            </Select>
          </div>
        </div>
        {esNumeracionVieja && (
          <p className="text-[11px] text-warning">
            Este contrato tiene la numeración antigua ({contrato.numero_contrato}): asígnale los 6 dígitos del formato
            actual al guardar.
          </p>
        )}

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-tipo">Tipo de interés</Label>
            <Select
              id="cc-tipo"
              value={tipoInteres}
              onChange={(e) => setTipoInteres(e.target.value as TipoInteres)}
              disabled={enviando || terminosFijosPorCatalogo || esVersionCatalogadaNoVigente}
            >
              <option value="simple">Simple</option>
              <option value="compuesto">Compuesto</option>
            </Select>
          </div>
          {(!esCompuesto || terminosFijosPorCatalogo || esVersionCatalogadaNoVigente) && (
            <div className="space-y-1.5">
              <Label htmlFor="cc-modalidad">Modalidad de pago</Label>
              <Select
                id="cc-modalidad"
                value={modalidad}
                onChange={(e) => setModalidad(e.target.value as ModalidadContrato)}
                disabled={enviando || terminosFijosPorCatalogo || esVersionCatalogadaNoVigente}
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

        <div className="grid grid-cols-2 gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-capital">Capital</Label>
            <Input
              id="cc-capital"
              inputMode="decimal"
              value={capital}
              onChange={(e) => setCapital(e.target.value)}
              disabled={enviando || esVersionCatalogadaNoVigente}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cc-moneda">Moneda</Label>
            <Select id="cc-moneda" value={moneda} disabled>
              <option value="PEN">Soles (PEN)</option>
              <option value="USD">Dólares (USD)</option>
            </Select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          <TasaPolitica
            clienteId={contrato.cliente_id}
            categoria={categoria || contrato.categoria || 'nuevo'}
            contratoOrigenId={origenSegunLedger}
            intencion={{
              capital: Number.isFinite(capitalNum) ? capitalNum : null,
              moneda,
              modalidad: esCompuesto ? 'anual' : modalidad,
              tipo_interes: tipoInteres,
              fecha_inicio: fechaInicio,
              fecha_vencimiento: venc,
              // Misma huella que el candado: la condición de CATÁLOGO elegida, o null. El snapshot legacy NO va: lo
              // sintetiza el servidor al guardar (y crea otro distinto si cambian los términos), así que ni el
              // formulario puede predecirlo ni la autorización podría coincidir con él.
              producto_condicion_id: condicionProducto?.condicion_id ?? null,
            }}
            tasa={tasa}
            onTasaChange={setTasa}
            onRangoChange={setRangoTasa}
            demo={false}
            disabled={enviando || esVersionCatalogadaNoVigente}
            idInput="cc-tasa"
            correccion={{ tasaActual: contrato.tasa_anual, contratoId: contrato.id }}
          >
          <div className="space-y-1.5">
            <Label htmlFor="cc-inicio">Fecha de inicio</Label>
            <Input
              id="cc-inicio"
              type="date"
              value={fechaInicio}
              onChange={(e) => cambiarInicio(e.target.value)}
              disabled={enviando || esVersionCatalogadaNoVigente}
            />
          </div>
          </TasaPolitica>
        </div>

        <div className="grid grid-cols-2 items-end gap-2.5">
          <div className="space-y-1.5">
            <Label htmlFor="cc-plazo">Plazo</Label>
            {terminosFijosPorCatalogo || esVersionCatalogadaNoVigente ? (
              <Input id="cc-plazo" value={`${condicionProducto?.plazo_meses ?? mesesReales} meses`} disabled />
            ) : (
              <Select id="cc-plazo" value={plazo} onChange={(e) => cambiarPlazo(e.target.value)} disabled={enviando}>
                {PLAZOS_BASE.map((p) => (
                  <option key={p.meses} value={String(p.meses)} disabled={esCompuesto && !p.anioExacto}>
                    {p.label}
                  </option>
                ))}
                {/* Solo un snapshot histórico puede conservar un plazo libre. */}
                <option value={PLAZO_PERSONALIZADO} disabled={esCompuesto}>
                  {mesesReales > 0 ? `Personalizado (${mesesReales} meses)` : 'Personalizado'}
                </option>
              </Select>
            )}
          </div>
          {esPersonalizado && !terminosFijosPorCatalogo && !esVersionCatalogadaNoVigente ? (
            <div className="space-y-1.5">
              <Label htmlFor="cc-venc">Fecha de vencimiento</Label>
              <Input
                id="cc-venc"
                type="date"
                value={venc}
                onChange={(e) => setVenc(e.target.value)}
                disabled={enviando}
              />
            </div>
          ) : (
            <p className="pb-2 text-[11px] text-muted-foreground">
              Vence el <b className="text-foreground">{fmtFecha(venc)}</b>
              {/* Con un preset elegido, cambiar inicio/plazo sí recalcula (es explícito). */}
            </p>
          )}
        </div>
        {esPersonalizado && !terminosFijosPorCatalogo && !esVersionCatalogadaNoVigente && (
          <p className="text-[11px] text-muted-foreground">
            Plazo <b className="text-foreground">personalizado</b>: el vencimiento pactado se conserva y NO se recalcula
            al cambiar la fecha de inicio. Si también debe moverse, edítalo aquí arriba.
          </p>
        )}

        <div className="space-y-1.5">
          <Label htmlFor="cc-notas">Notas internas</Label>
          <Textarea
            id="cc-notas"
            value={notas}
            maxLength={500}
            onChange={(e) => setNotas(e.target.value)}
            placeholder="—"
            disabled={enviando}
          />
        </div>

        {/* ── Co-titulares (cuentas mancomunadas, máx 5) ─────────────────────── */}
        <div className="space-y-2 rounded-xl border border-border bg-muted/40 p-3">
          <div className="flex items-center justify-between gap-2">
            <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
              Co-titulares (opcional)
            </p>
            {estadoTitulares === 'ok' && (
              <Button
                type="button"
                variant="ghost"
                size="xs"
                onClick={agregarFila}
                disabled={enviando || titulares.length >= MAX_TITULARES}
              >
                <Plus aria-hidden /> Agregar co-titular
              </Button>
            )}
          </div>
          {estadoTitulares === 'cargando' && (
            <p className="text-xs text-muted-foreground" aria-busy>
              Cargando los co-titulares actuales…
            </p>
          )}
          {estadoTitulares === 'error' && (
            <div className="space-y-2">
              <p className="text-xs font-semibold text-destructive">
                No se pudieron cargar los co-titulares actuales. Se conservarán tal cual están en el servidor; para
                editarlos, reintenta la carga.
              </p>
              <Button variant="outline" size="xs" onClick={() => void qTitulares.refetch()}>
                <RotateCcw aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {estadoTitulares === 'ok' && titulares.length === 0 && (
            <p className="text-xs text-muted-foreground">Sin co-titulares.</p>
          )}
          {estadoTitulares === 'ok' &&
            titulares.map((t, i) => (
              // Índice como key: las filas solo se reordenan al quitar y no llevan
              // estado propio fuera del array (el editor del portal hace lo mismo).
              <div key={i} className="grid grid-cols-[1fr_auto] gap-1.5 sm:grid-cols-[1.4fr_0.9fr_1fr_auto]">
                <Input
                  aria-label={`Nombre del co-titular ${i + 1}`}
                  value={t.nombre}
                  onChange={(e) => setFila(i, { nombre: e.target.value })}
                  placeholder="Nombre completo"
                  disabled={enviando}
                />
                <Select
                  aria-label={`Tipo de documento del co-titular ${i + 1}`}
                  value={t.tipo}
                  onChange={(e) => setFila(i, { tipo: e.target.value as TipoDocumento })}
                  disabled={enviando}
                >
                  {TIPOS_DOCUMENTO_K.map((k) => (
                    <option key={k} value={k}>
                      {TIPOS_DOCUMENTO[k].etiqueta}
                    </option>
                  ))}
                </Select>
                <Input
                  aria-label={`Documento del co-titular ${i + 1}`}
                  inputMode={TIPOS_DOCUMENTO[t.tipo].inputmode}
                  // Tope ÚNICO de 12 (regla de lib/documento): un tope por tipo
                  // truncaría EN SILENCIO un CE pegado en modo DNI.
                  maxLength={12}
                  value={t.documento}
                  onChange={(e) => setFila(i, { documento: e.target.value })}
                  placeholder={TIPOS_DOCUMENTO[t.tipo].placeholder}
                  disabled={enviando}
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label={`Quitar co-titular ${i + 1}`}
                  onClick={() => quitarFila(i)}
                  disabled={enviando}
                >
                  <X aria-hidden />
                </Button>
              </div>
            ))}
        </div>

        {/* ── Vista previa del cronograma que se REGENERARÁ al guardar ───────── */}
        <div className="rounded-xl border border-border bg-muted/40 p-3">
          <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
            Cronograma (se regenera al guardar — las cuotas ya pagadas se conservan)
          </p>
          {cronograma.length === 0 ? (
            <p className="mt-1 text-xs text-muted-foreground">
              {esCompuesto
                ? 'El interés compuesto requiere un plazo en años exactos (12, 24, 36, 48 o 60 meses).'
                : 'Completa capital, tasa y fechas para previsualizar el cronograma.'}
            </p>
          ) : (
            <div className="mt-1.5 space-y-0.5 text-xs">
              <p className="text-foreground">
                <b>{cronograma.length}</b> {cronograma.length === 1 ? 'cuota' : 'cuotas'} · total programado{' '}
                <b className="tabular-nums text-primary">{money(totalCronograma, moneda)}</b>
              </p>
              {/* Las de INTERÉS, contadas aparte: el total incluye la devolución
                  del capital y disfraza un cronograma sin rendimiento. */}
              <p className="text-muted-foreground">
                De ellas, <b className="text-foreground">{cuotasInteres.length}</b> de interés por{' '}
                <b className="tabular-nums text-foreground">{money(interesProgramado, moneda)}</b>
              </p>
              <p className="text-muted-foreground">
                Primera: {fmtFecha(cronograma[0]!.fecha_programada)} · Última:{' '}
                {fmtFecha(cronograma[cronograma.length - 1]!.fecha_programada)}
              </p>
              {/* Sin role=alert: se recalcula en CADA tecla (sería ruido para el
                  lector de pantalla); el mensaje del guard sí lo lleva. */}
              {motivoCronograma && <p className="font-semibold text-destructive">{motivoCronograma}</p>}
            </div>
          )}
        </div>

        {error && (
          <p role="alert" className="text-xs font-semibold text-destructive">
            {error}
          </p>
        )}
      </DialogBody>
      <DialogFooter className="justify-between">
        <Button variant="ghost" size="sm" onClick={onCerrar} disabled={enviando}>
          Cancelar
        </Button>
        <Button
          size="sm"
          onClick={guardar}
          // El disabled por ventana es cortesía visual: la autoridad es la RPC
          // (P0001). Mientras cargan los co-titulares NO se puede guardar — un
          // guardado muy rápido con el editor vacío los borraría (lección del portal).
          disabled={
            enviando || deshabilitado || !!rangoTasa?.bloqueoContrato ||
            estadoTitulares === 'cargando' ||
            (!sinLimiteVentana && !ventana.vigente) ||
            (!esCondicionOriginal &&
              (qProductos.isPending || qProductos.isFetching || qProductos.isError || !condicionProducto))
          }
          title={ventana.vigente ? undefined : 'La ventana de corrección de 5 horas ya venció'}
        >
          <Save aria-hidden /> {enviando ? 'Guardando…' : 'Guardar corrección'}
        </Button>
      </DialogFooter>
    </>
  )
}
