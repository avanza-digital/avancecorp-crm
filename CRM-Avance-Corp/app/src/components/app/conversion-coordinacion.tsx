import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import { Lock, Percent } from 'lucide-react'
import { conversionCoordinacion } from '@/data/crm-api'
import { useAhora } from '@/lib/ahora'
import {
  FECHA_MINIMA,
  camposInvalidos,
  hoyLima,
  mesActualLima,
  motivoConsultaInvalida,
  type AnalistaConversionCoordinacion,
  type CarteraConversion,
  type CierresConversion,
  type ConsultaConversion,
  type ConversionCoordinacion as DatosConversion,
} from '@/lib/conversion-coordinacion'
import { porcentajeConversionCanonica } from '@/lib/format'
import { paginar } from '@/lib/paginacion'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'

const POR_PAGINA = 15
/** Tecleando fechas, cada dígito que completa una fecha válida cambiaría la consulta: se espera a que pare. */
const ESPERA_FECHAS_MS = 350

interface EstadoConversion {
  datos: DatosConversion | null
  cargando: boolean
  error: string | null
}

/** Enteros del núcleo tal cual; los aportes llevan el peso (hasta 2 decimales). */
function numero(valor: number): string {
  return valor.toLocaleString('es-PE', { maximumFractionDigits: 2 })
}

/**
 * El «—» es MUDO para NVDA/JAWS (la puntuación por defecto no lo pronuncia): se
 * pinta el símbolo, pero el lector oye el motivo, que es lo que distingue «no
 * hubo llegadas» de «el mes está cerrado» o «no aplica».
 */
function SinDato({ motivo }: { motivo: string }) {
  return (
    <>
      <span aria-hidden="true">—</span>
      <span className="sr-only">{motivo}</span>
    </>
  )
}

const MOTIVO_SELLADO = 'sin desglose: mes cerrado'
const MOTIVO_SIN_LLEGADAS = 'sin llegadas'
const MOTIVO_NO_APLICA = 'no aplica'

/** «setiembre de 2026» a partir de 'YYYY-MM', sin depender de la zona del navegador. */
function nombreDelMes(mes: string): string {
  return new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(`${mes}-01T00:00:00Z`))
}

/** «15 de setiembre de 2026» a partir de 'YYYY-MM-DD'; la cadena tal cual si no es una fecha. */
function fechaLarga(iso: string): string {
  const fecha = new Date(`${iso}T00:00:00Z`)
  return Number.isNaN(fecha.getTime())
    ? iso
    : new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }).format(fecha)
}

function Cifra({ valor, motivo }: { valor: number | null; motivo: string }) {
  return valor == null || !Number.isFinite(valor) ? <SinDato motivo={motivo} /> : <>{numero(valor)}</>
}

function Porcentaje({ valor }: { valor: number | null }) {
  return valor == null || !Number.isFinite(valor)
    ? <SinDato motivo={MOTIVO_SIN_LLEGADAS} />
    : <>{porcentajeConversionCanonica(valor)}</>
}

/** «19 · 2,85»: cuántos y cuánto pesan. El lector oye las dos cifras con su nombre, concordado. */
function CantidadYAporte({ cantidad, aporte, nombre }: { cantidad: number; aporte: number; nombre: { uno: string; varios: string } }) {
  const singular = cantidad === 1
  return (
    <>
      <span aria-hidden="true">{numero(cantidad)} · {numero(aporte)}</span>
      <span className="sr-only">
        {numero(cantidad)} {singular ? nombre.uno : nombre.varios}, {singular ? 'aporta' : 'aportan'} {numero(aporte)}
      </span>
    </>
  )
}

const REFERIDO = { uno: 'referido', varios: 'referidos' }
const RENOVACION = { uno: 'renovación', varios: 'renovaciones' }

/**
 * Las siete celdas de «Cierres» de una fila, en el MISMO orden que la cabecera:
 * formulario, landing, referido, sin peso (oficina y otros), upgrade, renovación
 * y el total ponderado. La fila «sin analista» pasa por aquí con todo a null para
 * que sus celdas nunca se desalineen de la cabecera.
 */
function CeldasCierres({
  cierres,
  cartera,
  numerador,
  bruto,
  ajuste,
  motivo,
}: {
  cierres: CierresConversion | null
  cartera: CarteraConversion | null
  numerador: number | null
  bruto: number | null
  ajuste: number | null
  motivo: string
}) {
  const conAjuste = ajuste != null && ajuste !== 0 && bruto != null
  return (
    <>
      <Td className="text-right tabular-nums">{cierres ? numero(cierres.formulario) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">{cierres ? numero(cierres.landing) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">
        {cierres ? <CantidadYAporte cantidad={cierres.referido} aporte={cierres.referido_aporte} nombre={REFERIDO} /> : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right tabular-nums text-muted-foreground">
        {cierres ? numero(cierres.oficina + cierres.otros) : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right tabular-nums">{cartera ? numero(cartera.upgrade) : <SinDato motivo={motivo} />}</Td>
      <Td className="text-right tabular-nums">
        {cartera ? <CantidadYAporte cantidad={cartera.renovacion} aporte={cartera.renovacion_aporte} nombre={RENOVACION} /> : <SinDato motivo={motivo} />}
      </Td>
      <Td className="text-right font-semibold tabular-nums">
        <Cifra valor={numerador} motivo="sin cierres" />
        {conAjuste ? (
          <span className="block text-xs font-normal text-muted-foreground">
            bruto {numero(bruto)} − ajuste {numero(ajuste)}
          </span>
        ) : null}
      </Td>
    </>
  )
}

function FilaAnalista({ analista, sellado }: { analista: AnalistaConversionCoordinacion; sellado: boolean }) {
  return (
    <tr className="border-b border-border last:border-0">
      <Td className="text-base font-medium">{analista.nombre ?? 'Sin nombre'}</Td>
      <Td className="hidden text-muted-foreground lg:table-cell">
        {analista.supervisor_nombre ?? <SinDato motivo="sin supervisor" />}
      </Td>
      <Td className="text-right tabular-nums">
        {sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={analista.divisor_formulario} motivo={MOTIVO_SIN_LLEGADAS} />}
      </Td>
      <Td className="text-right tabular-nums">
        {sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={analista.divisor_landing} motivo={MOTIVO_SIN_LLEGADAS} />}
      </Td>
      <Td className="text-right text-base font-extrabold tabular-nums text-primary">{numero(analista.divisor)}</Td>
      <CeldasCierres
        cierres={analista.cierres}
        cartera={analista.cartera}
        numerador={analista.numerador}
        bruto={analista.numerador_bruto}
        ajuste={analista.ajuste_pendiente}
        motivo={MOTIVO_SELLADO}
      />
      <Td className="text-right font-semibold tabular-nums"><Porcentaje valor={analista.conversion_pct} /></Td>
    </tr>
  )
}

/**
 * Mes abierto: «117,15 = 90 directos + 2,85 de referidos (19 × 0,15) + 24 de upgrade + 0,45
 * de renovación (3 × 0,15)», y el ajuste aparte (se descuenta por analista, con suelo en
 * cero, así que la empresa no es «bruto − ajuste»). Rango libre: los pesos van por mes de
 * cada episodio, así que se enseña la cantidad sin prometer «n × peso». Mes cerrado: la foto
 * no guarda el bruto, así que se enumeran las partes sin afirmar una igualdad.
 */
function formulaDelNumerador(datos: DatosConversion): string | null {
  const { cierres, cartera, numerador, numerador_bruto: bruto, ajuste_pendiente: ajuste } = datos.empresa
  if (!cierres || !cartera) return null
  const enRango = datos.periodo.modo === 'rango'
  const referidos = `${numero(cierres.referido_aporte)} de referidos (${numero(cierres.referido)}${enRango ? '' : ` × ${numero(datos.peso_referido)}`})`
  const renovacion = `${numero(cartera.renovacion_aporte)} de renovación (${numero(cartera.renovacion)}${enRango ? '' : ` × ${numero(datos.peso_renovacion)}`})`
  const partes = [
    `${numero(cierres.formulario + cierres.landing)} directos (formulario y landing)`,
    referidos,
    `${numero(cartera.upgrade)} de upgrade`,
    renovacion,
  ]
  const sinPeso = `Sin peso: ${numero(cierres.oficina)} de oficina y ${numero(cierres.otros)} de otros orígenes.`
  if (datos.sellado) {
    return `Cierres del mes cerrado: ${partes.join(', ')}. Numerador sellado: ${numero(numerador ?? 0)}. ${sinPeso}`
  }
  const total = bruto ?? numerador ?? 0
  const cola = ajuste != null && ajuste !== 0
    ? ` Ajuste de meses ya pagados: ${numero(ajuste)}, descontado por analista con suelo en cero. Netos: ${numero(numerador ?? 0)}.`
    : ''
  return `Cierres ponderados ${numero(total)} = ${partes.join(' + ')}.${cola} ${sinPeso}`
}

/**
 * Conversión por analista, con ámbito de toda la empresa. El divisor es el del
 * NÚCLEO (la misma cifra que Metas y Ranking): una llegada por lead, por su fecha
 * de alta, en el primer analista que la recibió. No es el reporte de entregas.
 * Los cierres se abren en sus partes con los mismos episodios del núcleo. El
 * navegador no calcula nada: pinta lo que el servidor reconcilió.
 */
export function ConversionCoordinacion() {
  const ahora = useAhora()
  const hoy = useMemo(() => hoyLima(new Date(ahora)), [ahora])
  const mesMaximo = useMemo(() => mesActualLima(new Date(ahora)), [ahora])
  const [modo, setModo] = useState<ConsultaConversion['modo']>('mes')
  const [mes, setMes] = useState(mesMaximo)
  const [desde, setDesde] = useState(`${mesMaximo}-01`)
  const [hasta, setHasta] = useState(hoy)
  const [estado, setEstado] = useState<EstadoConversion>({ datos: null, cargando: true, error: null })
  const [pagina, setPagina] = useState(0)
  const abortRef = useRef<AbortController | null>(null)
  const contenidoRef = useRef<HTMLDivElement>(null)
  const focoPendiente = useRef(false)
  const idAyuda = useId()
  const consulta = useMemo<ConsultaConversion>(
    () => (modo === 'mes' ? { modo: 'mes', mes } : { modo: 'rango', desde, hasta }),
    [modo, mes, desde, hasta],
  )
  // Consulta inválida = estado del formulario (pegado al campo), nunca un fallo de carga.
  const ayuda = motivoConsultaInvalida(consulta, hoy)
  const consultaInvalida = ayuda !== null
  const invalidos = camposInvalidos(consulta, hoy)
  const claveConsulta = JSON.stringify(consulta)

  // Cambiar de mes o de tipo de período consulta al momento; teclear fechas espera a que
  // el usuario pare, para no desmontar la tabla ni anunciar una carga por cada dígito.
  const [claveEstable, setClaveEstable] = useState(claveConsulta)
  useEffect(() => {
    if (claveEstable === claveConsulta) return
    const soloFechas = modo === 'rango' && claveEstable.includes('"modo":"rango"')
    if (!soloFechas) {
      setClaveEstable(claveConsulta)
      return
    }
    const temporizador = setTimeout(() => setClaveEstable(claveConsulta), ESPERA_FECHAS_MS)
    return () => clearTimeout(temporizador)
  }, [claveConsulta, claveEstable, modo])

  const cargar = useCallback(async (conservarError = false) => {
    abortRef.current?.abort()
    const pedida = JSON.parse(claveEstable) as ConsultaConversion
    if (motivoConsultaInvalida(pedida, hoy)) {
      // El error del formulario no borra lo último cargado: la tabla sigue mientras se corrige.
      setEstado((previo) => ({ ...previo, cargando: false }))
      return
    }
    const controlador = new AbortController()
    abortRef.current = controlador
    // Se conserva el error solo al reintentar, para que el botón no se desmonte
    // bajo el foco; la carga se anuncia por el estado persistente.
    setEstado((previo) => ({ datos: null, cargando: true, error: conservarError ? previo.error : null }))
    try {
      const datos = await conversionCoordinacion(pedida, controlador.signal)
      if (controlador.signal.aborted) return
      setEstado({ datos, cargando: false, error: null })
    } catch (error) {
      if (controlador.signal.aborted) return
      setEstado({
        datos: null,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la conversión por analista.',
      })
    }
  }, [claveEstable, hoy])

  useEffect(() => {
    focoPendiente.current = false // un cambio de período cancela el aterrizaje pendiente
    setPagina(0)
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  // El foco aterriza en el contenido cuando React ya lo pintó (no al resolver la
  // promesa: en ese instante el nodo todavía no existe).
  const reintentar = useCallback(() => {
    focoPendiente.current = true
    void cargar(true)
  }, [cargar])

  const datos = estado.datos
  useEffect(() => {
    if (datos && focoPendiente.current) {
      focoPendiente.current = false
      contenidoRef.current?.focus()
    }
  }, [datos])

  const analistas = useMemo(
    () => paginar(datos?.analistas ?? [], pagina, POR_PAGINA),
    [datos?.analistas, pagina],
  )
  const sinAnalista = datos?.sin_analista && datos.sin_analista.divisor > 0 ? datos.sin_analista : null
  const hayFilas = (datos?.analistas.length ?? 0) > 0 || sinAnalista !== null
  // Un mes cerrado puede tener producción solo «fuera del ranking» (supervisores,
  // perfiles fuera del roster): suma al total y no hay fila que enseñar.
  const produccionSinFilas = datos !== null && !hayFilas && datos.empresa.divisor > 0
  const formula = datos ? formulaDelNumerador(datos) : null
  // Lo que se ve es lo último cargado: sus textos van por SU período, no por el control.
  const periodoVisible = datos?.periodo.modo === 'rango' ? 'del período' : 'del mes'
  const tocaSellados = datos?.periodo.cruza_meses_sellados === true

  const etiquetaPeriodo = (d: DatosConversion) => (
    d.periodo.modo === 'mes' && d.periodo.mes_nombre
      ? `${d.periodo.mes_nombre} ${d.periodo.anio}`
      : `del ${fechaLarga(d.periodo.desde)} al ${fechaLarga(d.periodo.hasta)}`
  )
  const mensajeEstado = consultaInvalida
    ? ayuda
    : estado.cargando
      ? (modo === 'mes' ? `Cargando la conversión de ${nombreDelMes(mes)}…` : `Cargando la conversión del ${fechaLarga(desde)} al ${fechaLarga(hasta)}…`)
      : datos
        ? `Conversión ${datos.periodo.modo === 'mes' ? 'de' : ''} ${etiquetaPeriodo(datos)}: ${numero(datos.empresa.divisor)} llegadas, ${
            datos.empresa.conversion_pct == null ? 'sin conversión calculable' : porcentajeConversionCanonica(datos.empresa.conversion_pct)
          }${datos.sellado ? '. Mes cerrado: se muestra la foto del cierre' : ''}${datos.periodo.modo === 'rango' ? '. Rango libre: cifras en vivo' : ''}${
            tocaSellados ? '. Toca meses ya cerrados y puede diferir de su foto' : ''
          }.`
        : estado.error ?? ''

  const chips: Array<{ etiqueta: string; valor: React.ReactNode }> = datos ? [
    { etiqueta: 'Llegadas', valor: numero(datos.empresa.divisor) },
    { etiqueta: 'Formulario', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_formulario} motivo={MOTIVO_SIN_LLEGADAS} /> },
    { etiqueta: 'Landing', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_landing} motivo={MOTIVO_SIN_LLEGADAS} /> },
    { etiqueta: 'Conversión', valor: <Porcentaje valor={datos.empresa.conversion_pct} /> },
    { etiqueta: 'Cierres directos', valor: datos.empresa.cierres ? numero(datos.empresa.cierres.formulario + datos.empresa.cierres.landing) : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Referidos', valor: datos.empresa.cierres ? <CantidadYAporte cantidad={datos.empresa.cierres.referido} aporte={datos.empresa.cierres.referido_aporte} nombre={REFERIDO} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Upgrade', valor: datos.empresa.cartera ? numero(datos.empresa.cartera.upgrade) : <SinDato motivo={MOTIVO_SELLADO} /> },
    { etiqueta: 'Renovación', valor: datos.empresa.cartera ? <CantidadYAporte cantidad={datos.empresa.cartera.renovacion} aporte={datos.empresa.cartera.renovacion_aporte} nombre={RENOVACION} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
  ] : []

  const claseCampo = 'grid gap-1.5 text-xs font-semibold text-foreground'

  return (
    <Card className="overflow-hidden border-primary/15 shadow-[0_18px_45px_-38px_rgba(17,30,61,0.9)]">
      <SectionHead
        icon={Percent}
        title="Conversiones"
        right={estado.cargando ? (
          <span className="text-[11px] font-semibold text-muted-foreground" aria-hidden="true">
            Actualizando…
          </span>
        ) : undefined}
      />
      {/* Un solo estado vivo, SIEMPRE montado: así el lector sí oye cada cambio. */}
      <p role="status" className="sr-only">{mensajeEstado}</p>
      <p className="px-5 pb-3 text-sm text-muted-foreground">
        Llegadas que pesan en la conversión: una por lead, por su fecha de alta, en el primer analista
        que la recibió. Si el lead se reasigna después, no se le resta. Los cierres se abren por origen
        y por cartera con los mismos pesos que Metas y Ranking.
      </p>

      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-border/70 bg-card px-5 py-4">
        <div className="grid gap-1.5">
          <fieldset className="m-0 flex min-w-0 flex-wrap items-end gap-3 border-0 p-0">
            <legend className="sr-only">Período de la conversión</legend>
            <label className={claseCampo}>
              Período
              <Select
                aria-label="Tipo de período"
                value={modo}
                onChange={(event) => setModo(event.target.value === 'rango' ? 'rango' : 'mes')}
                className="w-40"
              >
                <option value="mes">Mes</option>
                <option value="rango">Rango de fechas</option>
              </Select>
            </label>
            {modo === 'mes' ? (
              <label className={claseCampo}>
                Mes
                <Input
                  type="month"
                  aria-label="Mes de conversión"
                  min={FECHA_MINIMA.slice(0, 7)}
                  max={mesMaximo}
                  value={mes}
                  aria-invalid={consultaInvalida || undefined}
                  aria-describedby={consultaInvalida ? idAyuda : undefined}
                  onChange={(event) => setMes(event.target.value)}
                  className="w-44"
                />
              </label>
            ) : (
              <>
                <label className={claseCampo}>
                  Desde
                  <Input
                    type="date"
                    min={FECHA_MINIMA}
                    max={hoy}
                    value={desde}
                    aria-invalid={invalidos.desde || undefined}
                    aria-describedby={consultaInvalida ? idAyuda : undefined}
                    onChange={(event) => setDesde(event.target.value)}
                    className="w-44"
                  />
                </label>
                <label className={claseCampo}>
                  Hasta
                  <Input
                    type="date"
                    min={FECHA_MINIMA}
                    max={hoy}
                    value={hasta}
                    aria-invalid={invalidos.hasta || undefined}
                    aria-describedby={consultaInvalida ? idAyuda : undefined}
                    onChange={(event) => setHasta(event.target.value)}
                    className="w-44"
                  />
                </label>
              </>
            )}
          </fieldset>
          {consultaInvalida ? (
            <p id={idAyuda} className="text-sm font-medium text-destructive">{ayuda}</p>
          ) : modo === 'rango' ? (
            <p className="text-sm text-muted-foreground">
              Rango libre: cifras en vivo, sin ajustes de meses ya pagados ni fotos de cierre. Un mes completo se trata como ese mes.
              {tocaSellados ? (
                <span className="block font-medium text-foreground">
                  Este rango toca meses ya cerrados: se calcula en vivo y puede diferir de la foto del cierre.
                </span>
              ) : null}
            </p>
          ) : null}
        </div>
        {datos?.sellado ? (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-border bg-muted/60 px-2.5 py-1 text-xs font-semibold text-foreground">
            <Lock className="size-3.5" aria-hidden /> Mes cerrado: se muestra la foto del cierre
          </span>
        ) : null}
      </div>

      {estado.error ? (
        <PanelError mensaje={estado.error} onReintentar={reintentar} reintentando={estado.cargando} />
      ) : estado.cargando ? (
        <PanelCargando filas={5} />
      ) : datos ? (
        // Destino programático del foco tras reintentar: fuera del orden de Tab,
        // sin anillo (no es un control), igual que el patrón de Repartir.
        <div ref={contenidoRef} tabIndex={-1} role="region" aria-label={`Conversión ${periodoVisible}`} className="outline-none">
          <div
            role="group"
            aria-label={`Resumen de conversión ${periodoVisible}`}
            className="grid grid-cols-2 border-b border-border/70 bg-primary/[0.025] sm:grid-cols-4"
          >
            {chips.map(({ etiqueta, valor }, indice) => (
              <div
                key={etiqueta}
                className={`px-5 py-3 ${indice % 2 === 1 ? 'border-l border-border/70' : ''} ${indice % 4 !== 0 ? 'sm:border-l sm:border-border/70' : ''} ${indice >= 2 ? 'border-t border-border/70' : ''} ${indice >= 2 && indice < 4 ? 'sm:border-t-0' : ''}`}
              >
                <p className="text-[11px] font-semibold text-muted-foreground">{etiqueta}</p>
                <p className="mt-0.5 text-xl font-extrabold tabular-nums text-primary">{valor}</p>
              </div>
            ))}
          </div>
          {formula ? (
            <p className="border-b border-border/70 px-5 py-2 text-sm text-muted-foreground" data-testid="formula-numerador">
              {formula}
            </p>
          ) : null}

          {!hayFilas ? (
            produccionSinFilas ? (
              <PanelVacio
                icono={Percent}
                titulo="Sin filas por analista en este mes cerrado"
                detalle="La producción quedó fuera del ranking al sellar el mes y se conserva en el total de la empresa."
              />
            ) : (
              <PanelVacio
                icono={Percent}
                titulo={`Sin llegadas en este ${datos.periodo.modo === 'rango' ? 'período' : 'mes'}`}
                detalle="Cuando entren leads por la hoja o la landing aparecerán aquí, en el analista que los recibió primero."
              />
            )
          ) : (
            <>
              <TablaEnvoltura ariaLabel="Conversión por analista">
                {/*
                  Cabecera agrupada en UN solo <thead>. Ninguna subcolumna de un grupo se
                  oculta por ancho: los colSpan son fijos y una celda oculta desalinearía la
                  cabecera del cuerpo; la envoltura desplaza en horizontal si hace falta.
                */}
                <TheadCrm
                  segundaFila={(
                    <>
                      <Th scope="col" className="text-right">Form.</Th>
                      <Th scope="col" className="text-right">Land.</Th>
                      <Th scope="col" className="text-right">Total</Th>
                      <Th scope="col" className="text-right">Form.</Th>
                      <Th scope="col" className="text-right">Land.</Th>
                      <Th scope="col" className="text-right">Referido</Th>
                      <Th scope="col" className="text-right">Sin peso</Th>
                      <Th scope="col" className="text-right">Upgrade</Th>
                      <Th scope="col" className="text-right">Renov.</Th>
                      <Th scope="col" className="text-right">Ponderados</Th>
                    </>
                  )}
                >
                  <Th scope="col" rowSpan={2} className="align-bottom">Analista</Th>
                  <Th scope="col" rowSpan={2} className="hidden align-bottom lg:table-cell">Supervisor</Th>
                  <Th scope="colgroup" colSpan={3} className="text-center">Llegadas</Th>
                  <Th scope="colgroup" colSpan={7} className="text-center">Cierres</Th>
                  <Th scope="col" rowSpan={2} className="text-right align-bottom">Conversión</Th>
                </TheadCrm>
                <tbody>
                  {analistas.visibles.map((analista) => (
                    <FilaAnalista key={analista.analista_id} analista={analista} sellado={datos.sellado} />
                  ))}
                  {sinAnalista && analistas.paginaActual === analistas.paginas - 1 ? (
                    <tr className="border-b border-border last:border-0 bg-muted/30 text-muted-foreground">
                      <Td className="text-base font-medium">Sin analista asignado</Td>
                      <Td className="hidden lg:table-cell"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                      <Td className="text-right tabular-nums"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                      <Td className="text-right tabular-nums"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                      <Td className="text-right text-base font-extrabold tabular-nums">{numero(sinAnalista.divisor)}</Td>
                      <CeldasCierres cierres={null} cartera={null} numerador={sinAnalista.numerador} bruto={null} ajuste={null} motivo={MOTIVO_NO_APLICA} />
                      <Td className="text-right tabular-nums"><SinDato motivo={MOTIVO_NO_APLICA} /></Td>
                    </tr>
                  ) : null}
                </tbody>
              </TablaEnvoltura>
              <div className="border-t border-border px-4 py-2.5">
                <Paginacion
                  paginaActual={analistas.paginaActual}
                  paginas={analistas.paginas}
                  total={datos.analistas.length}
                  onCambio={setPagina}
                  ariaLabel="Paginación de analistas de conversión"
                />
              </div>
            </>
          )}

          <p className="border-t border-border px-5 py-2 text-sm text-muted-foreground">
            Referido y Renov. (renovación) van como «cantidad · aporte al numerador». «Sin peso» son los
            cierres de oficina y de otros orígenes, que no suman. Este conteo es distinto del reporte de
            entregas: aquel cuenta lo entregado por fecha de entrega y deja de sumar la entrega que volvió
            a la bandeja antes de gestionarse.
          </p>
        </div>
      ) : null}
    </Card>
  )
}
