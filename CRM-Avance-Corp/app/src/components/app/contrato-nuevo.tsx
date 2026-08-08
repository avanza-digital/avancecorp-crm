// Formulario de CONTRATO dentro del CRM (paso 2 de la conversión lead→cliente).
// Usa el wrapper atómico de `crm` sobre la RPC del portal + el generador de
// cronograma portado: contrato, cuenta y vínculo se confirman o revierten juntos.
import { useEffect, useMemo, useRef, useState } from 'react'
import { BadgeCheck, FileSignature } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { money, fmtFecha, type Moneda } from '@/lib/format'
import { ERROR_MONTO, parseMonto } from '@/lib/numero'
import {
  crearContrato,
  CrmApiError,
  type CrearContratoInput,
} from '@/data/crm-api'
import {
  esCuotaDeInteres,
  formatDateLocal,
  generarCronograma,
  vencimientoDesdePlazo,
  type CategoriaContrato,
  type ModalidadContrato,
  type TipoInteres,
} from '@/lib/cronograma'
import { normalizarTitulares, type TitularBorrador } from '@/lib/titulares'
import { TitularesEditor } from '@/components/app/titulares'
import { CuentaPagoContrato } from '@/components/app/cuenta-pago-contrato'
import { useCuentasBancariasCliente } from '@/data/crm-queries'
import {
  SECCION_BANCARIA_VACIA,
  type CampoSeccionBancaria,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'
import {
  CUENTA_NUEVA,
  claveCuenta,
  prepararCuentaPago,
} from '@/lib/cuentas-bancarias-contrato'
import {
  CATEGORIAS_CONTRATO_UI,
  MODALIDADES_UI,
  PLAZOS_BASE,
  PREFIJO_CONTRATO,
  RE_SEIS_DIGITOS,
} from '@/lib/contratos-catalogo'

const PLAZO_PERSONALIZADO = 'personalizado'

const PLAZOS: { v: string; label: string; anioExacto: boolean }[] = [
  ...PLAZOS_BASE.map((p) => ({ v: String(p.meses), label: p.label, anioExacto: p.anioExacto })),
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

export interface ContratoNuevoProps {
  clienteId: string
  clienteNombre: string
  montoSugerido?: number | null
  monedaSugerida?: Moneda
  onCreado: (numero: string) => void
  onOmitir: () => void
}

export function ContratoNuevo({
  clienteId,
  clienteNombre,
  montoSugerido,
  monedaSugerida,
  onCreado,
  onOmitir,
}: ContratoNuevoProps) {
  // La categoría y los términos vuelven a ser una decisión libre del analista.
  const [categoria, setCategoria] = useState<CategoriaContrato | ''>('')
  const [tipoInteres, setTipoInteres] = useState<TipoInteres>('simple')
  const [modalidad, setModalidad] = useState<ModalidadContrato>('mensual')
  const [capital, setCapital] = useState(montoSugerido != null ? String(montoSugerido) : '')
  const [moneda, setMoneda] = useState<Moneda>(monedaSugerida ?? 'PEN')
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
  const [error, setError] = useState<string | null>(null)
  const [campoCuentaInvalido, setCampoCuentaInvalido] =
    useState<CampoSeccionBancaria | null>(null)
  const [avisoCuenta, setAvisoCuenta] = useState<string | null>(null)
  const errorRef = useRef<HTMLParagraphElement>(null)
  const cuentasQ = useCuentasBancariasCliente(clienteId, moneda)

  // Una revalidación puede retirar/versionar la cuenta elegida desde otra
  // sesión. Se limpia de inmediato; prepararCuentaPago lo vuelve a comprobar al
  // enviar como segunda defensa.
  useEffect(() => {
    if (!cuentaSeleccionada || cuentaSeleccionada === CUENTA_NUEVA || !cuentasQ.data) return
    if (!cuentasQ.data.some((cuenta) => claveCuenta(cuenta) === cuentaSeleccionada)) {
      setCuentaSeleccionada('')
      setAvisoCuenta('La cuenta que habías elegido cambió o ya no está disponible. Revísala y selecciona nuevamente el destino del contrato.')
    }
  }, [cuentaSeleccionada, cuentasQ.data])

  // Un error describe la fotografía del formulario en el instante del submit.
  // En cuanto cambia cualquier dato deja de ser vigente: retirarlo evita que un
  // lector de pantalla siga anunciando un diagnóstico ya corregido.
  useEffect(() => {
    setError(null)
    setCampoCuentaInvalido(null)
  }, [
    capital,
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
  const capitalNum = parseMonto(capital) ?? NaN
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
      !Number.isFinite(capitalNum) || capitalNum <= 0 ||
      !Number.isFinite(tasaNum) || tasaNum <= 0 || tasaNum > 50 ||
      !fechaInicio || !fechaVencimiento
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

  const reportarError = (
    mensaje: string,
    campoCuenta: CampoSeccionBancaria | null = null,
  ) => {
    setError(mensaje)
    setCampoCuentaInvalido(campoCuenta)
    // El mensaje aparece después del evento; el timeout permite que React lo
    // monte antes de enfocar el campo culpable (o el resumen si no hay uno).
    window.setTimeout(() => {
      const destino = campoCuenta
        ? document.getElementById(ID_CAMPO_CUENTA[campoCuenta])
        : errorRef.current
      destino?.focus()
    }, 0)
  }

  const guardar = async () => {
    if (enviando) return // guard anti doble-submit (además del disabled del botón)
    setError(null)
    setCampoCuentaInvalido(null)
    // El N° debe ser EXACTAMENTE 6 dígitos (espejo de analista.js:800-805): sin
    // ellos el servidor inventaría la numeración vieja 'AC-2026-XXXX'.
    if (!RE_SEIS_DIGITOS.test(numero)) {
      reportarError(`El N° de contrato debe tener exactamente 6 dígitos (después de ${PREFIJO_CONTRATO}).`)
      return
    }
    if (capital.trim() && parseMonto(capital) == null) {
      reportarError(ERROR_MONTO)
      return
    }
    if (!categoria) {
      reportarError('Selecciona la categoría de la inversión (Nuevo, Renovación o Upgrade).')
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
    if (cuentasQ.isPending || cuentasQ.isFetching || cuentasQ.isError) {
      reportarError('No se pudo confirmar la cuenta de pago del contrato. Espera o reintenta la carga antes de crearlo.')
      return
    }
    const cuentaPago = prepararCuentaPago({
      seleccion: cuentaSeleccionada,
      moneda,
      cuentas: cuentasQ.data ?? [],
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
      numero_contrato: PREFIJO_CONTRATO + numero,
      notas_internas: notas.trim() || null,
      // Viajan DENTRO de p_contrato: crear_contrato ya los persiste (mancomunadas).
      titulares: tit.titulares,
      cuenta_pago: cuentaPago.cuenta,
    }
    setEnviando(true)
    try {
      const r = await crearContrato(input, cronograma)
      toast.success(`Contrato ${r.numero_contrato} creado para ${clienteNombre}`)
      onCreado(r.numero_contrato)
    } catch (e) {
      reportarError(e instanceof CrmApiError ? e.message : 'No se pudo crear el contrato')
    } finally {
      setEnviando(false)
    }
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
          <FileSignature className="size-4 text-primary" /> Crear contrato de {clienteNombre}
        </DialogTitle>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-3 overflow-y-auto">
        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-categoria">Categoría</Label>
            <Select id="ct-categoria" value={categoria} onChange={(e) => setCategoria(e.target.value as CategoriaContrato | '')} disabled={enviando}>
              <option value="" disabled>— Seleccionar —</option>
              {CATEGORIAS_CONTRATO_UI.map((c) => <option key={c.k} value={c.k}>{c.label}</option>)}
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-tipo">Tipo de interés</Label>
            <Select id="ct-tipo" value={tipoInteres} onChange={(e) => cambiarTipo(e.target.value as TipoInteres)} disabled={enviando}>
              <option value="simple">Simple</option>
              <option value="compuesto">Compuesto</option>
            </Select>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-capital">Capital</Label>
            <Input id="ct-capital" inputMode="decimal" value={capital} onChange={(e) => setCapital(e.target.value)} placeholder="10000" disabled={enviando} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-moneda">Moneda</Label>
            <Select id="ct-moneda" value={moneda} onChange={(e) => cambiarMoneda(e.target.value as Moneda)} disabled={enviando}>
              <option value="PEN">Soles (PEN)</option>
              <option value="USD">Dólares (USD)</option>
            </Select>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-tasa">Tasa anual (%)</Label>
            <Input id="ct-tasa" inputMode="decimal" value={tasa} onChange={(e) => setTasa(e.target.value)} placeholder="18" disabled={enviando} />
          </div>
          {!esCompuesto && (
            <div className="space-y-1.5">
              <Label htmlFor="ct-modalidad">Modalidad de pago</Label>
              <Select id="ct-modalidad" value={modalidad} onChange={(e) => setModalidad(e.target.value as ModalidadContrato)} disabled={enviando}>
                {MODALIDADES_UI.map((m) => <option key={m.k} value={m.k}>{m.label}</option>)}
              </Select>
            </div>
          )}
        </div>

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ct-inicio">Fecha de inicio</Label>
            <Input id="ct-inicio" type="date" value={fechaInicio} onChange={(e) => setFechaInicio(e.target.value)} disabled={enviando} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-plazo">Plazo</Label>
            <Select id="ct-plazo" value={plazo} onChange={(e) => setPlazo(e.target.value)} disabled={enviando}>
              {PLAZOS.map((p) => (
                <option key={p.v} value={p.v} disabled={esCompuesto && !p.anioExacto}>{p.label}</option>
              ))}
            </Select>
          </div>
        </div>

        {plazo === PLAZO_PERSONALIZADO ? (
          <div className="space-y-1.5">
            <Label htmlFor="ct-venc">Fecha de vencimiento</Label>
            <Input id="ct-venc" type="date" value={vencManual} onChange={(e) => setVencManual(e.target.value)} disabled={enviando} />
          </div>
        ) : fechaVencimiento && (
          <p className="text-[11px] text-muted-foreground">
            Vence el <b className="text-foreground">{fmtFecha(fechaVencimiento)}</b> (calculado del plazo).
          </p>
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
              Escribe los <b className="text-foreground">6 dígitos</b>. El <b className="text-foreground">{PREFIJO_CONTRATO}</b> es fijo.
            </p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ct-notas">Notas internas (opcional)</Label>
            <Input id="ct-notas" value={notas} maxLength={500} onChange={(e) => setNotas(e.target.value)} placeholder="—" disabled={enviando} />
          </div>
        </div>

        <CuentaPagoContrato
          moneda={moneda}
          cuentas={cuentasQ.data ?? []}
          seleccion={cuentaSeleccionada}
          nueva={cuentaNueva}
          cargando={cuentasQ.isPending}
          error={cuentasQ.isError}
          reintentando={cuentasQ.isFetching}
          deshabilitado={enviando}
          campoNuevaInvalido={campoCuentaInvalido}
          {...(error ? { errorId: 'ct-error-resumen' } : {})}
          onSeleccion={(seleccion) => {
            setCuentaSeleccionada(seleccion)
            setAvisoCuenta(null)
            setError(null)
          }}
          onNueva={setCuentaNueva}
          onReintentar={() => void cuentasQ.refetch()}
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
            <p className="mt-1 text-xs text-muted-foreground">Completa capital, tasa y fechas para previsualizar el cronograma.</p>
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
                Primera: {fmtFecha(cronograma[0]!.fecha_programada)} · Última: {fmtFecha(cronograma[cronograma.length - 1]!.fecha_programada)}
              </p>
              {/* Sin role=alert: se recalcula en CADA tecla (sería ruido para el
                  lector de pantalla); el botón deshabilitado es el freno real. */}
              {motivoCronograma && (
                <p className="font-semibold text-destructive">{motivoCronograma}</p>
              )}
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
          Omitir por ahora
        </Button>
        {/* Se bloquea por el MOTIVO (sin cuotas de interés incluido), no por la
            longitud del cronograma — que nunca es 0 (siempre trae el retorno). */}
        <Button
          type="submit"
          size="sm"
          disabled={
            enviando
            || motivoCronograma !== null
            || cuentasQ.isPending
            || cuentasQ.isFetching
            || cuentasQ.isError
            || !cuentaSeleccionada
          }
        >
          <BadgeCheck /> {enviando ? 'Creando…' : 'Crear contrato'}
        </Button>
      </DialogFooter>
    </form>
  )
}
