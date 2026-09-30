import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import { Lock, Percent } from 'lucide-react'
import { conversionCoordinacion } from '@/data/crm-api'
import { useAhora } from '@/lib/ahora'
import {
  mesActualLima,
  periodoDesdeMes,
  type AnalistaConversionCoordinacion,
  type ConversionCoordinacion as DatosConversion,
} from '@/lib/conversion-coordinacion'
import { porcentajeConversionCanonica } from '@/lib/format'
import { paginar } from '@/lib/paginacion'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'

const POR_PAGINA = 15

interface EstadoConversion {
  datos: DatosConversion | null
  cargando: boolean
  error: string | null
}

/** Enteros del núcleo tal cual; el numerador lleva el peso del referido (hasta 2 decimales). */
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

/** «setiembre de 2026» a partir de 'YYYY-MM', sin depender de la zona del navegador. */
function nombreDelMes(mes: string): string {
  return new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(`${mes}-01T00:00:00Z`))
}
const MOTIVO_SIN_LLEGADAS = 'sin llegadas'

function Cifra({ valor, motivo }: { valor: number | null; motivo: string }) {
  return valor == null || !Number.isFinite(valor) ? <SinDato motivo={motivo} /> : <>{numero(valor)}</>
}

function Porcentaje({ valor }: { valor: number | null }) {
  return valor == null || !Number.isFinite(valor)
    ? <SinDato motivo={MOTIVO_SIN_LLEGADAS} />
    : <>{porcentajeConversionCanonica(valor)}</>
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
      <Td className="text-right tabular-nums"><Cifra valor={analista.numerador} motivo="sin cierres" /></Td>
      <Td className="text-right font-semibold tabular-nums"><Porcentaje valor={analista.conversion_pct} /></Td>
    </tr>
  )
}

/**
 * Conversión del mes por analista, con ámbito de toda la empresa. El divisor es
 * el del NÚCLEO (la misma cifra que Metas y Ranking): una llegada por lead, por
 * su fecha de alta, en el primer analista que la recibió. No es el reporte de
 * entregas. El navegador no calcula nada: pinta lo que el servidor reconcilió.
 */
export function ConversionCoordinacion() {
  const ahora = useAhora()
  const mesMaximo = useMemo(() => mesActualLima(new Date(ahora)), [ahora])
  const [mes, setMes] = useState(mesMaximo)
  const [estado, setEstado] = useState<EstadoConversion>({ datos: null, cargando: true, error: null })
  const [pagina, setPagina] = useState(0)
  const abortRef = useRef<AbortController | null>(null)
  const contenidoRef = useRef<HTMLDivElement>(null)
  const focoPendiente = useRef(false)
  const idAyudaMes = useId()
  const mesFuturo = periodoDesdeMes(mes) !== null && mes > mesMaximo
  const mesInvalido = periodoDesdeMes(mes) === null || mesFuturo
  const ayudaMes = mesFuturo
    ? `El mes no puede ser futuro: elige ${mesMaximo} o anterior.`
    : 'Elige un mes válido (año y mes) para consultar la conversión.'

  const cargar = useCallback(async (conservarError = false) => {
    abortRef.current?.abort()
    const periodo = periodoDesdeMes(mes)
    if (!periodo || mes > mesMaximo) {
      // Mes inválido: estado del formulario, no un fallo de carga.
      setEstado({ datos: null, cargando: false, error: null })
      return
    }
    const controlador = new AbortController()
    abortRef.current = controlador
    // Se conserva el error mientras se reintenta para que el botón no se
    // desmonte bajo el foco; la carga se anuncia por el estado persistente.
    setEstado((previo) => ({ datos: null, cargando: true, error: conservarError ? previo.error : null }))
    try {
      const datos = await conversionCoordinacion(periodo, controlador.signal)
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
  }, [mes, mesMaximo])

  useEffect(() => {
    focoPendiente.current = false // un cambio de mes cancela el aterrizaje pendiente
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

  const mensajeEstado = mesInvalido
    ? ayudaMes
    : estado.cargando
      ? `Cargando la conversión de ${nombreDelMes(mes)}…`
      : datos
        ? `Conversión de ${datos.periodo.mes_nombre} ${datos.periodo.anio}: ${numero(datos.empresa.divisor)} llegadas, ${
            datos.empresa.conversion_pct == null ? 'sin conversión calculable' : porcentajeConversionCanonica(datos.empresa.conversion_pct)
          }${datos.sellado ? '. Mes cerrado: se muestra la foto del cierre' : ''}.`
        : estado.error ?? ''

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
        que la recibió. Si el lead se reasigna después, no se le resta. Es la misma cifra que ven Metas y Ranking.
      </p>

      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-border/70 bg-card px-5 py-4">
        <div className="grid gap-1.5">
          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Mes
            <Input
              type="month"
              aria-label="Mes de conversión"
              min="2025-01"
              max={mesMaximo}
              value={mes}
              aria-invalid={mesInvalido || undefined}
              aria-describedby={mesInvalido ? idAyudaMes : undefined}
              onChange={(event) => setMes(event.target.value)}
              className="w-44"
            />
          </label>
          {mesInvalido ? (
            <p id={idAyudaMes} className="text-sm font-medium text-destructive">{ayudaMes}</p>
          ) : null}
        </div>
        {datos?.sellado ? (
          <span className="inline-flex items-center gap-1.5 rounded-md border border-border bg-muted/60 px-2.5 py-1 text-xs font-semibold text-foreground">
            <Lock className="size-3.5" aria-hidden /> Mes cerrado: se muestra la foto del cierre
          </span>
        ) : null}
      </div>

      {mesInvalido ? null : estado.error ? (
        <PanelError mensaje={estado.error} onReintentar={reintentar} reintentando={estado.cargando} />
      ) : estado.cargando ? (
        <PanelCargando filas={5} />
      ) : datos ? (
        // Destino programático del foco tras reintentar: fuera del orden de Tab,
        // sin anillo (no es un control), igual que el patrón de Repartir.
        <div ref={contenidoRef} tabIndex={-1} role="region" aria-label="Conversión del mes" className="outline-none">
          <div
            role="group"
            aria-label="Resumen de conversión del mes"
            className="grid grid-cols-2 border-b border-border/70 bg-primary/[0.025] sm:grid-cols-5"
          >
            {([
              { etiqueta: 'Llegadas', tipo: 'numero', valor: datos.empresa.divisor },
              { etiqueta: 'Formulario', tipo: 'origen', valor: datos.empresa.divisor_formulario },
              { etiqueta: 'Landing', tipo: 'origen', valor: datos.empresa.divisor_landing },
              { etiqueta: 'Cierres ponderados', tipo: 'numero', valor: datos.empresa.numerador },
              { etiqueta: 'Conversión', tipo: 'porcentaje', valor: datos.empresa.conversion_pct },
            ] as const).map(({ etiqueta, tipo, valor }, indice) => (
              <div
                key={etiqueta}
                className={`px-5 py-3 ${indice > 0 ? 'sm:border-l sm:border-border/70' : ''} ${indice % 2 === 1 ? 'border-l border-border/70 sm:border-l' : ''} ${indice > 1 ? 'border-t border-border/70 sm:border-t-0' : ''}`}
              >
                <p className="text-[11px] font-semibold text-muted-foreground">{etiqueta}</p>
                <p className="mt-0.5 text-xl font-extrabold tabular-nums text-primary">
                  {tipo === 'numero'
                    ? numero(valor)
                    : tipo === 'porcentaje'
                      ? <Porcentaje valor={valor} />
                      : datos.sellado
                        ? <SinDato motivo={MOTIVO_SELLADO} />
                        : <Cifra valor={valor} motivo={MOTIVO_SIN_LLEGADAS} />}
                </p>
              </div>
            ))}
          </div>

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
                titulo="Sin llegadas en este mes"
                detalle="Cuando entren leads por la hoja o la landing aparecerán aquí, en el analista que los recibió primero."
              />
            )
          ) : (
            <>
              <TablaEnvoltura ariaLabel="Conversión por analista">
                <TheadCrm>
                  <Th>Analista</Th>
                  <Th className="hidden lg:table-cell">Supervisor</Th>
                  <Th className="text-right">Formulario</Th>
                  <Th className="text-right">Landing</Th>
                  <Th className="text-right">Llegadas</Th>
                  <Th className="text-right">Cierres</Th>
                  <Th className="text-right">Conversión</Th>
                </TheadCrm>
                <tbody>
                  {analistas.visibles.map((analista) => (
                    <FilaAnalista key={analista.analista_id} analista={analista} sellado={datos.sellado} />
                  ))}
                  {sinAnalista && analistas.paginaActual === analistas.paginas - 1 ? (
                    <tr className="border-b border-border last:border-0 bg-muted/30">
                      <Td className="text-base font-medium text-muted-foreground">Sin analista asignado</Td>
                      <Td className="hidden lg:table-cell text-muted-foreground"><SinDato motivo="no aplica" /></Td>
                      <Td className="text-right tabular-nums text-muted-foreground"><SinDato motivo="no aplica" /></Td>
                      <Td className="text-right tabular-nums text-muted-foreground"><SinDato motivo="no aplica" /></Td>
                      <Td className="text-right text-base font-extrabold tabular-nums text-muted-foreground">{numero(sinAnalista.divisor)}</Td>
                      <Td className="text-right tabular-nums text-muted-foreground"><Cifra valor={sinAnalista.numerador} motivo="sin cierres" /></Td>
                      <Td className="text-right tabular-nums text-muted-foreground"><SinDato motivo="no aplica" /></Td>
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

          <p className="border-t border-border px-5 py-2 text-xs text-muted-foreground">
            Este conteo es distinto del reporte de entregas: aquel cuenta lo entregado por fecha de entrega
            y deja de sumar la entrega que volvió a la bandeja antes de gestionarse.
          </p>
        </div>
      ) : null}
    </Card>
  )
}
