import { useMemo, useState, type JSX, type ReactNode } from 'react'
import { AlertTriangle, CalendarDays, RefreshCw, Target, Trophy } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import {
  mensajeMetaNoComparable,
  type MetaMensualGerencia,
} from '@/components/gerencia/periodo'
import { money, numero, porcentajeConversionCanonica } from '@/lib/format'
import { totalEnSoles } from '@/lib/capital-unificado'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import { descuentoArrastre, type ConversionMensual } from '@/lib/conversion-mensual'
import { ChipArrastre } from '@/components/common/chip-arrastre'
import {
  adaptarConversionMensual,
  type DetalleConversionMensual,
  clasificarRankingCapitalTotal,
  clasificarRankingConversion,
  type RankingCapitalTotalVendedores,
  type RankingConversionVendedores,
} from '@/lib/conversion-vendedores'
import type { MetricasConversionesEquipo, ResponsableEquipo } from '@/lib/metricas-conversiones-equipo'
import type {
  CumplimientoVendedor,
  ObjetivosPorVendedor,
  ProduccionFueraRanking,
} from '@/lib/objetivos'
import type { TipoCambio } from '@/lib/tipo-cambio'
import { sondasNucleoVerificadas } from '@/lib/sondas-conversion'

interface RankingVendedoresPanelProps {
  /**
   * LA fuente del tab «Conversión» desde la conversión mensual ponderada
   * (`crm.conversion_mensual_fn`) — tri-estado como `tc`:
   * `undefined` = consultando (el tab muestra carga, no afirma nada);
   * `null` = no disponible → fail-closed: todos «No disponible», jamás ceros.
   * El payload viejo (`datos`) ya NO alimenta este tab: mide otra pregunta
   * (el rango elegido, sin ponderar) y mezclar fórmulas bajo un mismo rótulo
   * es la mentira que este cambio elimina.
   */
  conversionMensual: ConversionMensual | null | undefined
  /** Un fallo de conversión solo bloquea SU pestaña. */
  conversionError: string | null
  onReintentarConversion: () => void
  /**
   * Segunda lectura POR COSECHA del ranking (`crm.metricas_conversiones_equipo_fn`,
   * F2.2 — patrón D2: de los leads que cada quien RECIBIÓ en el mes, cuántos
   * cerraron, madurando hasta hoy). Tri-estado como la mensual: `undefined` =
   * consultando o sin pedir (no se pinta nada), `null` = no disponible
   * (fail-closed: tampoco se pinta — jamás un cero fabricado). La cosecha solo
   * se muestra con sondas PRESENTES que confirmen `cuadra=true` y
   * `paridad_nucleo=0`; cualquier media verificación se oculta (F3.4).
   */
  cosecha?: MetricasConversionesEquipo | null | undefined
  cosechaCargando: boolean
  /** Un fallo de cosecha no tapa conversión ni capital. */
  cosechaError: string | null
  onReintentarCosecha: () => void
  equipo: ConversionEquipoVendedor[]
  metasVendedores: ObjetivosPorVendedor
  cumplimientoVendedores: Record<string, CumplimientoVendedor>
  /** Produccion empresarial identificada que no puede recibir un puesto. */
  fueraRanking?: ProduccionFueraRanking[]
  metaMensual: MetaMensualGerencia
  /** Nombre, supervisor y población salen de la foto mensual autoritativa. */
  usarIdentidadSnapshot?: boolean
  /** Un histórico puede seguir abierto o ser ya una foto definitiva. */
  estadoFotoMensual?: 'sellada' | 'abierta'
  /** La foto mensual que fija identidad, metas y capital está en vuelo. */
  fotoMensualCargando?: boolean
  /** Sin esa foto ninguna pestaña puede afirmar la población del mes. */
  fotoMensualError?: string | null
  onReintentarFotoMensual?: () => void
  /** Fallos exclusivos del cálculo de capital solo bloquean ese tab. */
  capitalError: string | null
  onReintentarCapital: () => void
  /**
   * TC USD→PEN resuelto por el servidor (edge crm-tipo-cambio · BCRP).
   * `undefined` = consultando (el tab de capital muestra carga, no degrada);
   * `null` = no disponible → total solo-PEN con US$ rotulado aparte.
   */
  tc: TipoCambio | null | undefined
  /** Encabezado. El supervisor ve «Ranking de mi equipo», no «general». */
  titulo?: string
  /** Chip de alcance: «Equipo completo» en gerencia, «Mi equipo» en supervisión. */
  etiquetaAlcance?: string
  /** Pestaña abierta al montar. */
  tabInicial?: TipoRanking
}

type TipoRanking = 'conversion' | 'capital-total' | 'cosecha'

const MOTIVO_FUERA_RANKING: Record<ProduccionFueraRanking['motivo'], string> = {
  analista_sin_meta: 'Analista sin meta mensual',
  analista_sin_supervisor: 'Analista sin supervisor válido',
  supervisor: 'Producción atribuida a supervisor',
  gerencia: 'Producción atribuida a Gerencia',
  fuera_estructura: 'Responsable fuera de la estructura comercial',
}

/** ids tab↔panel por pestaña: los tres marcos (vivo, carga, error/vacío) los
 * comparten para que `aria-controls` jamás prometa un nodo inexistente. */
const IDS_TAB: Record<TipoRanking, { tab: string; panel: string }> = {
  conversion: { tab: 'tab-ranking-conversion', panel: 'panel-ranking-conversion' },
  'capital-total': { tab: 'tab-ranking-capital-total', panel: 'panel-ranking-capital' },
  cosecha: { tab: 'tab-ranking-cosecha', panel: 'panel-ranking-cosecha' },
}

function pct(valor: number | null): string {
  return porcentajeConversionCanonica(valor)
}

function colorPosicion(indice: number): string {
  if (indice < 3) return C.green
  if (indice === 3) return C.amber
  return C.blue
}

function colorAvance(avance: number | null): string {
  if (avance == null) return C.muted
  if (avance >= 100) return C.green
  if (avance >= 75) return C.teal
  return C.amber
}

function Puesto({ indice }: { indice: number }): JSX.Element {
  return (
    <span
      aria-label={`Puesto ${indice + 1}`}
      className="grid size-9 place-items-center rounded-xl text-xs font-bold tabular-nums text-white"
      style={{ backgroundColor: colorPosicion(indice) }}
    >
      {String(indice + 1).padStart(2, '0')}
    </span>
  )
}

function CargandoRanking(): JSX.Element {
  return (
    <div className="space-y-2 p-4 sm:p-5">
      {Array.from({ length: 8 }, (_, indice) => <Skeleton key={indice} className="h-14 rounded-xl" />)}
    </div>
  )
}

/**
 * Carga DENTRO del tabpanel: mantiene vivo el id que `aria-controls` promete
 * (sin él, el tab activo apunta a un nodo inexistente) y ANUNCIA la consulta —
 * los esqueletos son divs mudos y un lector no recibía ninguna señal.
 */
function CargandoTabpanel({ tab, mensaje }: { tab: TipoRanking; mensaje: string }): JSX.Element {
  return (
    <div
      role="tabpanel"
      id={IDS_TAB[tab].panel}
      aria-labelledby={IDS_TAB[tab].tab}
      aria-busy="true"
    >
      <span className="sr-only">{mensaje}</span>
      <CargandoRanking />
    </div>
  )
}

/**
 * Mantiene VIVO el nodo `tabpanel` que los tabs prometen por `aria-controls`
 * también en ERROR y VACÍO (observación #6): sin él, el tab activo apuntaba a
 * un id inexistente en esas dos ramas (carga y «meta no comparable» ya lo
 * hacían bien).
 */
function TabpanelMarco({ tab, children }: { tab: TipoRanking; children: ReactNode }): JSX.Element {
  return (
    <div
      role="tabpanel"
      id={IDS_TAB[tab].panel}
      aria-labelledby={IDS_TAB[tab].tab}
    >
      {children}
    </div>
  )
}

function ErrorRanking({ error, onReintentar }: { error: string; onReintentar: () => void }): JSX.Element {
  return (
    <div className="m-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3 sm:m-5" role="alert">
      <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
        <AlertTriangle className="size-4" aria-hidden /> {error}
      </span>
      <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
        <RefreshCw aria-hidden /> Reintentar
      </Button>
    </div>
  )
}

/**
 * Línea «por cosecha» de una fila (D2 aplicado al ranking): de los leads que
 * el analista RECIBIÓ en el mes, cuántos ya son clientes. Reescrita en idioma
 * de negocio a pedido de Miguel (27/08): la primera versión («Cosecha: 0 de
 * 41 recibidos (0%) · madura hasta hoy») no la entendía nadie. El matiz de la
 * maduración viaja en el title, no en la línea. Sin fila del payload no se
 * pinta nada: la ausencia no es un cero.
 */
function lineaCosecha(fila: ResponsableEquipo | undefined): string | null {
  if (fila == null) return null
  const pctCosecha = fila.clientes > 0 && fila.conversion_pct != null ? ` (${pct(fila.conversion_pct)})` : ''
  const clientes = fila.clientes === 0
    ? 'ninguno es cliente todavía'
    : fila.clientes === 1
      ? '1 ya es cliente'
      : `${numero(fila.clientes)} ya son clientes`
  return `De sus ${numero(fila.leads)} leads del mes, ${clientes}${pctCosecha}`
}

/**
 * El matiz que la línea corta no carga. Redacción v2 (Miguel, 27/08): la v1
 * («puede seguir subiendo») no decía CUÁL de los dos números sube y parecía
 * contradecir a la conversión del mes. Ahora el tooltip separa los dos
 * relojes: esta línea sigue al LOTE (cierre cuando cierre); el % del mes
 * acredita cada cierre al mes en que ocurrió.
 */
const TITLE_COSECHA = 'Sigue a los leads que el analista recibió este mes: cuántos ya son clientes, cierren cuando cierren. Si uno cierra el mes que viene, esta línea sube — pero ese cierre le contará a la conversión DEL MES QUE VIENE, no a la de este.'

/**
 * Pestaña «Cosecha del lote» (pedido de Miguel, 27/08): la lectura vivía como
 * segunda línea de cada fila del ranking y era RUIDO junto al % oficial — dos
 * relojes en una celda. Ahora tiene su propio apartado: sigue al LOTE del mes
 * (cuántos de los leads recibidos ya son clientes, cierren cuando cierren) y
 * no compite visualmente con la conversión del mes.
 */
function CosechaLote({ cosecha, equipo, enRevision }: {
  cosecha: MetricasConversionesEquipo | null | undefined
  equipo: ConversionEquipoVendedor[]
  enRevision: boolean
}): JSX.Element {
  if (enRevision) {
    return (
      <div className="grid min-h-64 place-items-center px-5 text-center">
        <div className="max-w-md rounded-2xl border border-amber-300/70 bg-amber-50 px-5 py-4">
          <p role="status" className="text-xs font-medium text-amber-900">
            Resultados de los leads del mes en revisión: su verificación interna no está confirmada y se ocultan hasta revisarla.
          </p>
        </div>
      </div>
    )
  }
  if (cosecha == null) {
    return (
      <div className="grid min-h-64 place-items-center px-5 text-center">
        <p className="text-sm font-semibold text-[var(--gi-muted)]">Resultados de los leads del mes no disponibles por ahora.</p>
      </div>
    )
  }

  const detallePorId = new Map(cosecha.responsables.map((fila) => [fila.vendedor_id, fila]))
  // La población ya viene resuelta por el panel. Cosecha solo agrega medidas
  // por ID: una fila extra de la RPC (incluido fuera_de_roster) no puede crear
  // una identidad, y una medida ausente queda explícitamente indisponible.
  const filas = equipo
    .filter((fila): fila is ConversionEquipoVendedor & { vendedorId: string } => fila.vendedorId != null)
    .map((identidad) => ({ identidad, detalle: detallePorId.get(identidad.vendedorId) }))
    .sort((a, b) => {
      if (a.detalle == null && b.detalle != null) return 1
      if (a.detalle != null && b.detalle == null) return -1
      if (a.detalle != null && b.detalle != null) {
        const diferencia = b.detalle.clientes - a.detalle.clientes || b.detalle.leads - a.detalle.leads
        if (diferencia !== 0) return diferencia
      }
      return a.identidad.nombre.localeCompare(b.identidad.nombre, 'es')
        || a.identidad.vendedorId.localeCompare(b.identidad.vendedorId)
    })

  return (
    <div>
      <p className="border-b border-[var(--gi-line)] bg-[#faf9f6] px-4 py-2.5 text-[11px] font-medium text-[var(--gi-muted)] sm:px-5" title={TITLE_COSECHA}>
        Un cierre tardío sube esta lista, pero a la conversión le cuenta en el mes en que cerró — el mes sellado no se mueve.
      </p>
      <ol aria-label="Resultados de los leads del mes por analista" className="divide-y divide-[var(--gi-line)]">
        {filas.map(({ identidad, detalle }) => (
          <li key={identidad.vendedorId} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 px-4 py-3 sm:px-5">
            <span className="min-w-0">
              <strong className="block truncate text-sm text-[var(--gi-navy)]">{identidad.nombre}</strong>
              <span className="block truncate text-[11px] font-medium text-[var(--gi-muted)]">{identidad.supervisorNombre}</span>
            </span>
            <span title={TITLE_COSECHA} className="text-xs font-semibold tabular-nums text-[var(--gi-navy)]">
              {lineaCosecha(detalle) ?? 'Seguimiento no disponible'}
            </span>
          </li>
        ))}
      </ol>
    </div>
  )
}

function RankingConversion({ ranking, etiquetaBase }: {
  ranking: RankingConversionVendedores<DetalleConversionMensual>
  etiquetaBase: string
}): JSX.Element {
  const vendedores = ranking.conPuesto
  const maximo = Math.max(1, ...vendedores.map((fila) => fila.detalle.conversion_pct ?? 0))
  return (
    <div role="tabpanel" id="panel-ranking-conversion" aria-labelledby="tab-ranking-conversion">
      <div className="hidden overflow-x-auto md:block">
        <table aria-label="Ranking de conversión general" className="w-full min-w-[900px] border-collapse text-left">
          <thead className="bg-[#f7f5f1] text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--gi-muted)]">
            <tr>
              <th className="w-20 px-5 py-3" scope="col">Puesto</th>
              <th className="px-3 py-3" scope="col">Analista</th>
              <th className="px-3 py-3" scope="col">Equipo</th>
              <th className="px-3 py-3 text-right" scope="col">{etiquetaBase}</th>
              <th className="px-3 py-3 text-right" scope="col">Cierres</th>
              <th className="px-3 py-3 text-right" scope="col">Conversión</th>
              <th className="min-w-56 px-5 py-3" scope="col">Nivel de conversión</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--gi-line)]">
            {vendedores.map((fila, indice) => {
              const conversion = fila.detalle.conversion_pct
              const ancho = conversion == null ? 0 : (conversion / maximo) * 100
              // Su % ya llega NETO de anulaciones de meses cerrados: el
              // descuento se dice al lado, o el ranking «baja solo».
              const descuento = descuentoArrastre(fila.detalle.ajuste)
              return (
                <tr key={fila.vendedorId} className="transition-colors hover:bg-[#f7f5f1]/70">
                  <td className="px-5 py-3"><Puesto indice={indice} /></td>
                  <th className="max-w-56 px-3 py-3 text-sm font-bold text-[var(--gi-navy)]" scope="row"><span className="block truncate">{fila.nombre}</span></th>
                  <td className="max-w-48 px-3 py-3 text-xs font-medium text-[var(--gi-muted)]"><span className="block truncate">{fila.supervisorNombre}</span></td>
                  <td className="px-3 py-3 text-right text-sm font-semibold tabular-nums">{numero(fila.detalle.leads)}</td>
                  <td className="px-3 py-3 text-right text-sm font-semibold tabular-nums">{numero(fila.detalle.clientes)}</td>
                  <td className="px-3 py-3 text-right text-sm font-bold tabular-nums text-[var(--gi-navy)]">
                    {pct(conversion)}
                    {/* H1 por fila (hallazgo de Grecia): un % positivo con
                        «Cierres 0» necesita decir de dónde salen los puntos —
                        las operaciones de cartera suman arriba sin sumar leads. */}
                    {fila.detalle.operacionesCartera > 0 && (
                      <span className="block text-left text-[10px] font-semibold text-[var(--muted-foreground-strong)]">
                        {numero(fila.detalle.clientes)} {fila.detalle.clientes === 1 ? 'cierre' : 'cierres'} + {numero(fila.detalle.operacionesCartera)} de cartera
                      </span>
                    )}
                    {descuento && (
                      <ChipArrastre descuento={descuento} className="block text-left text-[10px] font-semibold text-[var(--muted-foreground-strong)]" />
                    )}
                  </td>
                  <td
                    className="px-5 py-3"
                    aria-label={fila.estadoConversion === 'solo_arrastre'
                      ? 'Nivel de conversión: solo cierres de arrastre'
                      : `Nivel de conversión ${pct(conversion)}`}
                  >
                    {fila.estadoConversion === 'solo_arrastre'
                      ? <span className="inline-block rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-600">Solo cierres de arrastre</span>
                      : <div className="gi-track h-2" aria-hidden><div className="gi-fill motion-reduce:transition-none" style={{ width: `${ancho}%`, background: colorPosicion(indice) }} /></div>}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      <ol aria-label="Ranking de conversión general" className="divide-y divide-[var(--gi-line)] md:hidden">
        {vendedores.map((fila, indice) => {
          const conversion = fila.detalle.conversion_pct
          const ancho = conversion == null ? 0 : (conversion / maximo) * 100
          const descuento = descuentoArrastre(fila.detalle.ajuste)
          return (
            <li key={fila.vendedorId} className="px-4 py-4">
              <div className="grid grid-cols-[2.25rem_minmax(0,1fr)_auto] items-start gap-3">
                <Puesto indice={indice} />
                <div className="min-w-0"><p className="truncate text-sm font-bold text-[var(--gi-navy)]">{fila.nombre}</p><p className="mt-0.5 truncate text-[11px] font-medium text-[var(--gi-muted)]">{fila.supervisorNombre}</p></div>
                <strong className="text-sm tabular-nums text-[var(--gi-navy)]">{pct(conversion)}</strong>
              </div>
              <div className="ml-12 mt-3 flex items-center justify-between gap-3 text-[11px] font-medium text-[var(--gi-muted)]"><span>{etiquetaBase}: {numero(fila.detalle.divisor)}</span><span>{numero(fila.detalle.clientes)} cierres</span></div>
              {fila.detalle.operacionesCartera > 0 && (
                <p className="ml-12 mt-1 text-[10px] font-semibold text-[var(--muted-foreground-strong)]">
                  {numero(fila.detalle.clientes)} {fila.detalle.clientes === 1 ? 'cierre' : 'cierres'} + {numero(fila.detalle.operacionesCartera)} de cartera
                </p>
              )}
              {descuento && (
                <ChipArrastre descuento={descuento} className="ml-12 mt-1 block text-[11px] font-semibold text-[var(--muted-foreground-strong)]" />
              )}
              {fila.estadoConversion === 'solo_arrastre'
                ? <span className="ml-12 mt-2 inline-block rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-600">Solo cierres de arrastre</span>
                : <div className="gi-track ml-12 mt-2 h-2" aria-hidden><div className="gi-fill motion-reduce:transition-none" style={{ width: `${ancho}%`, background: colorPosicion(indice) }} /></div>}
            </li>
          )
        })}
      </ol>

      {(ranking.sinMuestra.length > 0 || ranking.indisponibles.length > 0) && (
        <section aria-label="Analistas sin posición en conversión" className="border-t border-[var(--gi-line)] bg-[#faf9f6] px-4 py-4 sm:px-5">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--gi-muted)]">Fuera del ranking</h3>
          <ul className="mt-2 grid gap-2 sm:grid-cols-2">
            {ranking.sinMuestra.map((fila) => (
              <li key={fila.vendedorId} className="flex min-w-0 items-center justify-between gap-3 rounded-xl border border-[var(--gi-line)] bg-white px-3 py-2.5">
                <span className="min-w-0"><strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.nombre}</strong><span className="block truncate text-[10px] text-[var(--gi-muted)]">{fila.supervisorNombre}</span></span>
                {/* «Solo recibió referidos» ≠ «Sin muestra»: el primero TRABAJÓ
                    (los referidos no ocupan divisor y suman 15 % al cerrarse);
                    leerlo como inactividad es la confusión que el estado evita. */}
                <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-600">
                  {fila.estadoConversion === 'solo_referidos' ? 'Solo recibió referidos' : 'Sin muestra'}
                </span>
              </li>
            ))}
            {ranking.indisponibles.map((fila) => (
              <li key={fila.vendedorId} className="flex min-w-0 items-center justify-between gap-3 rounded-xl border border-[var(--gi-line)] bg-white px-3 py-2.5">
                <span className="min-w-0"><strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.nombre}</strong><span className="block truncate text-[10px] text-[var(--gi-muted)]">{fila.supervisorNombre}</span></span>
                <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-600">No disponible</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

/**
 * Desglose por moneda bajo el total; sin TC el US$ se declara aparte, jamás
 * dentro. La variante sin TC va en navy (no muted): es el aviso que evita leer
 * el total como si incluyera los dólares — hallazgo a11y de contraste.
 */
// El desglose vive ahora en components/common/desglose-monedas: lo comparten este
// ranking y las filas de equipo desde la decisión #10. Aquí va con `tono="gerencia"`
// porque los tokens --gi-* solo resuelven dentro de .gerencia-inteligencia.

function RankingCapitalTotal({ ranking }: { ranking: RankingCapitalTotalVendedores }): JSX.Element {
  const filas = ranking.conPuesto
  return (
    <div role="tabpanel" id="panel-ranking-capital" aria-labelledby="tab-ranking-capital-total">
      <div className="hidden overflow-x-auto md:block">
        <table aria-label="Ranking de capital total en soles" className="w-full min-w-[900px] border-collapse text-left">
          <thead className="bg-[#f7f5f1] text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--gi-muted)]">
            <tr>
              <th className="w-20 px-5 py-3" scope="col">Puesto</th>
              <th className="px-3 py-3" scope="col">Analista</th>
              <th className="px-3 py-3" scope="col">Equipo</th>
              <th className="px-3 py-3 text-right" scope="col">Capital confirmado (S/)</th>
              <th className="px-3 py-3 text-right" scope="col">Meta (S/)</th>
              <th className="px-3 py-3 text-right" scope="col">Avance</th>
              <th className="min-w-56 px-5 py-3" scope="col">Cumplimiento</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--gi-line)]">
            {filas.map(({ vendedor, capitalPen, capitalUsd, capitalAjustePen, capitalAjusteUsd, contratosAjuste, capitalTotal, metaPen, metaUsd, metaCapital, avance }, indice) => (
              <tr key={vendedor.vendedorId} className="transition-colors hover:bg-[#f7f5f1]/70">
                <td className="px-5 py-3"><Puesto indice={indice} /></td>
                <th className="max-w-56 px-3 py-3 text-sm font-bold text-[var(--gi-navy)]" scope="row"><span className="block truncate">{vendedor.nombre}</span></th>
                <td className="max-w-48 px-3 py-3 text-xs font-medium text-[var(--gi-muted)]"><span className="block truncate">{vendedor.supervisorNombre}</span></td>
                <td className="px-3 py-3 text-right text-sm font-semibold tabular-nums">
                  <span className="block">{money(capitalTotal, 'PEN')}</span>
                  <DesgloseMonedas pen={capitalPen} usd={capitalUsd} tc={ranking.tc} tono="gerencia" />
                  {(capitalAjustePen > 0 || capitalAjusteUsd > 0 || contratosAjuste > 0) && (
                    <span
                      className="mt-1 block text-[10px] font-semibold text-amber-800"
                      title="El capital confirmado ya es neto: estos importes y contratos se descontaron al cerrar el mes."
                    >
                      Neto tras ajuste de cierre
                      {capitalAjustePen > 0 ? ` · −${money(capitalAjustePen, 'PEN')}` : ''}
                      {capitalAjusteUsd > 0 ? ` · −${money(capitalAjusteUsd, 'USD')}` : ''}
                      {contratosAjuste > 0 ? ` · −${numero(contratosAjuste)} ${contratosAjuste === 1 ? 'contrato' : 'contratos'}` : ''}
                    </span>
                  )}
                </td>
                <td className="px-3 py-3 text-right text-sm font-semibold tabular-nums">
                  <span className="block">{money(metaCapital, 'PEN')}</span>
                  <DesgloseMonedas pen={metaPen} usd={metaUsd} tc={ranking.tc} tono="gerencia" />
                </td>
                <td className="px-3 py-3 text-right text-sm font-bold tabular-nums" style={{ color: colorAvance(avance) }}>{pct(avance)}</td>
                <td className="px-5 py-3" aria-label={`Cumplimiento ${pct(avance)}`}>
                  <div className="gi-track h-2" aria-hidden><div className="gi-fill motion-reduce:transition-none" style={{ width: `${Math.min(100, avance ?? 0)}%`, background: colorAvance(avance) }} /></div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <ol aria-label="Ranking de capital total en soles" className="divide-y divide-[var(--gi-line)] md:hidden">
        {filas.map(({ vendedor, capitalPen, capitalUsd, capitalAjustePen, capitalAjusteUsd, contratosAjuste, capitalTotal, metaPen, metaUsd, metaCapital, avance }, indice) => (
          <li key={vendedor.vendedorId} className="px-4 py-4">
            <div className="grid grid-cols-[2.25rem_minmax(0,1fr)_auto] items-start gap-3">
              <Puesto indice={indice} />
              <div className="min-w-0"><p className="truncate text-sm font-bold text-[var(--gi-navy)]">{vendedor.nombre}</p><p className="mt-0.5 truncate text-[11px] font-medium text-[var(--gi-muted)]">{vendedor.supervisorNombre}</p></div>
              <strong className="text-sm tabular-nums" style={{ color: colorAvance(avance) }}>{pct(avance)}</strong>
            </div>
            <div className="ml-12 mt-3 grid grid-cols-2 gap-3 text-[11px] font-medium text-[var(--gi-muted)]">
              <span>Logrado <strong className="block text-xs text-[var(--gi-navy)]">{money(capitalTotal, 'PEN')}</strong><DesgloseMonedas pen={capitalPen} usd={capitalUsd} tc={ranking.tc} tono="gerencia" /></span>
              <span className="text-right">Meta <strong className="block text-xs text-[var(--gi-navy)]">{money(metaCapital, 'PEN')}</strong><DesgloseMonedas pen={metaPen} usd={metaUsd} tc={ranking.tc} tono="gerencia" /></span>
            </div>
            {(capitalAjustePen > 0 || capitalAjusteUsd > 0 || contratosAjuste > 0) && (
              <p
                className="ml-12 mt-1 text-[10px] font-semibold text-amber-800"
                title="El capital confirmado ya es neto: estos importes y contratos se descontaron al cerrar el mes."
              >
                Neto tras ajuste de cierre
                {capitalAjustePen > 0 ? ` · −${money(capitalAjustePen, 'PEN')}` : ''}
                {capitalAjusteUsd > 0 ? ` · −${money(capitalAjusteUsd, 'USD')}` : ''}
                {contratosAjuste > 0 ? ` · −${numero(contratosAjuste)} ${contratosAjuste === 1 ? 'contrato' : 'contratos'}` : ''}
              </p>
            )}
            <div className="gi-track ml-12 mt-2 h-2" aria-hidden><div className="gi-fill motion-reduce:transition-none" style={{ width: `${Math.min(100, avance ?? 0)}%`, background: colorAvance(avance) }} /></div>
          </li>
        ))}
      </ol>

      {(ranking.sinMeta.length > 0 || ranking.indisponibles.length > 0) && (
        <section aria-label="Analistas sin posición en capital" className="border-t border-[var(--gi-line)] bg-[#faf9f6] px-4 py-4 sm:px-5">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--gi-muted)]">Fuera del ranking</h3>
          <ul className="mt-2 grid gap-2 sm:grid-cols-2">
            {ranking.sinMeta.map((fila) => (
              <li key={fila.vendedor.vendedorId} className="flex min-w-0 items-center justify-between gap-3 rounded-xl border border-[var(--gi-line)] bg-white px-3 py-2.5">
                <span className="min-w-0">
                  <strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.vendedor.nombre}</strong>
                  <span className="block truncate text-[10px] text-[var(--gi-muted)]">{money(fila.capitalTotal, 'PEN')} confirmado</span>
                  <DesgloseMonedas pen={fila.capitalPen} usd={fila.capitalUsd} tc={ranking.tc} tono="gerencia" />
                  {(fila.capitalAjustePen > 0 || fila.capitalAjusteUsd > 0 || fila.contratosAjuste > 0) && (
                    <span
                      className="mt-1 block text-[10px] font-semibold text-amber-800"
                      title="El capital confirmado ya es neto: estos importes y contratos se descontaron al cerrar el mes."
                    >
                      Neto tras ajuste de cierre
                      {fila.capitalAjustePen > 0 ? ` · −${money(fila.capitalAjustePen, 'PEN')}` : ''}
                      {fila.capitalAjusteUsd > 0 ? ` · −${money(fila.capitalAjusteUsd, 'USD')}` : ''}
                      {fila.contratosAjuste > 0 ? ` · −${numero(fila.contratosAjuste)} ${fila.contratosAjuste === 1 ? 'contrato' : 'contratos'}` : ''}
                    </span>
                  )}
                </span>
                {/* Una meta 100% US$ sin TC NO es «sin meta»: está pendiente de conversión. */}
                <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-600">{fila.metaUsd > 0 ? 'Meta en US$ · sin TC' : 'Sin meta'}</span>
              </li>
            ))}
            {ranking.indisponibles.map((fila) => (
              <li key={fila.vendedor.vendedorId} className="flex min-w-0 items-center justify-between gap-3 rounded-xl border border-[var(--gi-line)] bg-white px-3 py-2.5">
                <span className="min-w-0"><strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.vendedor.nombre}</strong><span className="block truncate text-[10px] text-[var(--gi-muted)]">Capital no disponible</span></span>
                <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-600">No disponible</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

function ProduccionFueraRankingPanel({
  filas,
  tc,
}: {
  filas: ProduccionFueraRanking[]
  tc: TipoCambio | null | undefined
}): JSX.Element | null {
  if (filas.length === 0) return null

  return (
    <aside
      aria-label="Producción fuera del ranking"
      className="border-t border-[var(--gi-line)] bg-amber-50/45 px-4 py-4 sm:px-5"
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="text-sm font-bold text-[var(--gi-navy)]">Producción fuera del ranking</h3>
          <p className="mt-1 max-w-3xl text-[11px] font-medium leading-relaxed text-[var(--gi-muted)]">
            Suma al resultado total de la empresa, pero no entrega puesto ni altera el orden de los analistas.
          </p>
        </div>
        <span className="rounded-full border border-amber-300 bg-amber-100 px-2.5 py-1 text-[10px] font-bold text-amber-900">
          {numero(filas.length)} {filas.length === 1 ? 'responsable' : 'responsables'} sin puesto
        </span>
      </div>

      <ul className="mt-3 grid gap-2 lg:grid-cols-2">
        {filas.map((fila) => {
          const capitalPen = fila.detalles.reduce((total, detalle) => (
            detalle.moneda === 'PEN' ? total + detalle.capitalReal : total
          ), 0)
          const capitalUsd = fila.detalles.reduce((total, detalle) => (
            detalle.moneda === 'USD' ? total + detalle.capitalReal : total
          ), 0)
          const contratos = fila.detalles.reduce(
            (total, detalle) => total + detalle.contratosReal,
            0,
          )
          const cierres = (fila.conversion?.cierresNoReferidos ?? 0)
            + (fila.conversion?.cierresReferidos ?? 0)
          const capital = totalEnSoles(capitalPen, capitalUsd, tc?.promedio)

          return (
            <li
              key={fila.personaId}
              className="rounded-xl border border-amber-200/80 bg-white px-3 py-3"
            >
              <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
                <span className="min-w-0">
                  <strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.nombre}</strong>
                  <span className="mt-0.5 block text-[10px] font-medium text-[var(--gi-muted)]">
                    {MOTIVO_FUERA_RANKING[fila.motivo]}
                  </span>
                </span>
                <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-700">
                  No suma al ranking
                </span>
              </div>
              <div className="mt-2 flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
                <span>
                  <span className="block text-[10px] font-semibold uppercase tracking-wide text-[var(--gi-muted)]">Capital confirmado</span>
                  <strong className="block text-sm tabular-nums text-[var(--gi-navy)]">{money(capital.total, 'PEN')}</strong>
                  <DesgloseMonedas pen={capitalPen} usd={capitalUsd} tc={capital.tc} tono="gerencia" />
                </span>
                <span className="text-right text-[10px] font-semibold text-[var(--gi-muted)]">
                  {numero(contratos)} {contratos === 1 ? 'contrato' : 'contratos'}
                  <span className="block">
                    {numero(cierres)} {cierres === 1 ? 'cierre de lead' : 'cierres de lead'} · {numero(fila.cartera.conversionesClientes)} {fila.cartera.conversionesClientes === 1 ? 'operación de cartera' : 'operaciones de cartera'}
                  </span>
                </span>
              </div>
            </li>
          )
        })}
      </ul>
    </aside>
  )
}

export function RankingVendedoresPanel({
  conversionMensual,
  conversionError,
  onReintentarConversion,
  cosecha,
  cosechaCargando,
  cosechaError,
  onReintentarCosecha,
  equipo,
  metasVendedores,
  cumplimientoVendedores,
  fueraRanking = [],
  metaMensual,
  usarIdentidadSnapshot = false,
  estadoFotoMensual,
  fotoMensualCargando = false,
  fotoMensualError = null,
  onReintentarFotoMensual,
  capitalError,
  onReintentarCapital,
  tc,
  titulo = 'Ranking general de analistas',
  etiquetaAlcance = 'Equipo completo',
  tabInicial = 'conversion',
}: RankingVendedoresPanelProps): JSX.Element {
  const [tipo, setTipo] = useState<TipoRanking>(tabInicial)
  // Una sola fuente define identidades para las TRES pestañas. En el mes
  // vigente manda el roster vivo; cumplimiento solo aporta meta/capital y no
  // puede reintroducir una baja. En un mes cerrado manda exclusivamente la
  // foto mensual, de modo que un alta posterior tampoco reescribe la historia.
  const equipoRanking = useMemo(() => {
    const porId = new Map<string, ConversionEquipoVendedor>()
    if (!usarIdentidadSnapshot) {
      for (const fila of equipo) {
        if (!fila.vendedorId) continue
        porId.set(fila.vendedorId, fila)
      }
      return [...porId.values()]
    }
    for (const fila of Object.values(cumplimientoVendedores)) {
      porId.set(fila.vendedorId, {
        vendedorId: fila.vendedorId,
        nombre: fila.nombre,
        supervisorId: fila.supervisorId,
        supervisorNombre: fila.supervisorNombre,
        leads: 0,
        contactados: 0,
        reunionesPactadas: 0,
        reunionesRealizadas: 0,
        clientes: 0,
        descartados: 0,
        conversionPct: null,
      })
    }
    return [...porId.values()]
  }, [cumplimientoVendedores, equipo, usarIdentidadSnapshot])
  const idsPoblacion = useMemo(
    () => new Set(equipoRanking.map((fila) => fila.vendedorId).filter((id): id is string => id != null)),
    [equipoRanking],
  )
  // Los núcleos son fuentes de MEDIDAS. Se proyectan al set autoritativo antes
  // de usar los adaptadores existentes, para que ni una respuesta obsoleta ni
  // fuera_de_roster materialicen una persona en pantalla.
  const conversionMensualPoblacion = useMemo(() => (
    conversionMensual == null
      ? conversionMensual
      : {
          ...conversionMensual,
          responsables: conversionMensual.responsables.filter((fila) => idsPoblacion.has(fila.vendedor_id)),
        }
  ), [conversionMensual, idsPoblacion])
  const adaptadaMensual = useMemo(
    () => adaptarConversionMensual(conversionMensualPoblacion ?? null, equipoRanking),
    [conversionMensualPoblacion, equipoRanking],
  )
  const rankingConversion = useMemo(
    () => clasificarRankingConversion(adaptadaMensual.vendedores),
    [adaptadaMensual.vendedores],
  )
  // F3.4 sobre la cosecha: solo dos señales explícitas autorizan la cifra. Un
  // bloque vivo sin sondas, con NULL o con desvío distinto de cero queda
  // oculto; el ranking ponderado no depende de esta segunda lectura.
  const cosechaEnRevision = cosecha != null && !sondasNucleoVerificadas(cosecha.sondas)
  const rankingCapitalTotal = useMemo(
    () => clasificarRankingCapitalTotal(equipoRanking, metasVendedores, cumplimientoVendedores, tc?.promedio ?? null),
    [cumplimientoVendedores, equipoRanking, metasVendedores, tc],
  )
  const totalVendedores = equipoRanking.length
  const poblacionMensualIndisponible = fotoMensualCargando || Boolean(fotoMensualError)
  const errorActivo = fotoMensualError ?? (tipo === 'conversion'
    ? conversionError
    : tipo === 'capital-total'
      ? capitalError
      : cosechaError)
  const reintentarActivo = fotoMensualError
    ? (onReintentarFotoMensual ?? onReintentarCapital)
    : tipo === 'conversion'
      ? onReintentarConversion
      : tipo === 'capital-total'
        ? onReintentarCapital
        : onReintentarCosecha
  const cargandoActivo = fotoMensualCargando || (tipo === 'conversion'
    ? conversionMensual === undefined
    : tipo === 'capital-total'
      ? metaMensual.comparable && tc === undefined
      : cosechaCargando)
  const formulaConversion = conversionMensual == null
    ? 'Conversión ponderada del núcleo comercial'
    : conversionMensual.fuentes.divisor === 'crm.leads.creado_en'
      ? `(Cierres Landing/Formulario + referidos ×${numero(conversionMensual.ponderacion.referido, 2)} + renovaciones ×${numero(conversionMensual.ponderacion.renovacion ?? conversionMensual.ponderacion.referido, 2)} + upgrades) ÷ prospectos automáticos de Landing/Formulario. El prospecto se atribuye al primer analista; el cierre, a quien lo consigue. Altas manuales, referidos y cartera no agregan base.`
      : 'Base histórica del mes: conserva la definición anterior con la que se calculó; no equivale a prospectos recibidos.'

  return (
    <section data-gi-panel className="gi-card overflow-hidden">
      <header className="flex flex-wrap items-start justify-between gap-4 border-b border-[var(--gi-line)] bg-white px-4 py-4 sm:px-5">
        <div>
          <p className="gi-label text-[var(--gi-blue)]">Desempeño comercial</p>
          <h2 className="mt-1 text-xl font-bold tracking-[-.025em] text-[var(--gi-navy)] sm:text-2xl">{titulo}</h2>
          <p className="mt-1 text-xs font-medium text-[var(--gi-muted)]">
            {poblacionMensualIndisponible
              ? '— analistas'
              : `${numero(totalVendedores)} ${totalVendedores === 1 ? 'analista' : 'analistas'}`}
            {' · sin límite fijo de participantes'}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-2 rounded-xl bg-[#f7f5f1] px-3 py-2 text-xs font-semibold text-[var(--gi-navy)]"><Trophy className="size-4 text-[var(--gi-blue)]" aria-hidden />{etiquetaAlcance}</div>
          <div className="flex items-center gap-2 rounded-xl bg-[#f7f5f1] px-3 py-2 text-xs font-semibold text-[var(--gi-navy)]"><CalendarDays className="size-4 text-[var(--gi-blue)]" aria-hidden />Mes calendario · {metaMensual.etiqueta}</div>
          {estadoFotoMensual && (
            <div
              className="rounded-xl bg-[#f7f5f1] px-3 py-2 text-xs font-semibold text-[var(--gi-navy)]"
              title={tipo === 'cosecha'
                ? 'Los leads recibidos ese mes pueden convertirse después; esta lectura sigue actualizándose.'
                : undefined}
            >
              {tipo === 'cosecha'
                ? 'Leads del mes'
                : estadoFotoMensual === 'sellada' ? 'Foto sellada' : 'Mes aún abierto'}
            </div>
          )}
        </div>
      </header>

      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--gi-line)] bg-white px-4 py-3 sm:px-5">
        <div role="tablist" aria-label="Tipo de ranking" className="inline-flex rounded-xl bg-[#f7f5f1] p-1">
          <button id="tab-ranking-conversion" type="button" role="tab" aria-selected={tipo === 'conversion'} aria-controls="panel-ranking-conversion" onClick={() => setTipo('conversion')} className={`rounded-lg px-3 py-2 text-xs font-bold transition-colors ${tipo === 'conversion' ? 'bg-white text-[var(--gi-navy)] shadow-sm' : 'text-[var(--gi-muted)] hover:text-[var(--gi-navy)]'}`}>Conversión general</button>
          <button id="tab-ranking-capital-total" type="button" role="tab" aria-selected={tipo === 'capital-total'} aria-controls="panel-ranking-capital" onClick={() => setTipo('capital-total')} className={`rounded-lg px-3 py-2 text-xs font-bold transition-colors ${tipo === 'capital-total' ? 'bg-white text-[var(--gi-navy)] shadow-sm' : 'text-[var(--gi-muted)] hover:text-[var(--gi-navy)]'}`}>Capital total</button>
          <button id="tab-ranking-cosecha" type="button" role="tab" aria-selected={tipo === 'cosecha'} aria-controls="panel-ranking-cosecha" onClick={() => setTipo('cosecha')} className={`rounded-lg px-3 py-2 text-xs font-bold transition-colors ${tipo === 'cosecha' ? 'bg-white text-[var(--gi-navy)] shadow-sm' : 'text-[var(--gi-muted)] hover:text-[var(--gi-navy)]'}`}>Resultados de los leads del mes</button>
        </div>
        <p className="text-[11px] font-medium text-[var(--gi-muted)]">
          {tipo === 'conversion'
            ? formulaConversion
            : tipo === 'cosecha'
            ? 'De los leads que cada quien recibió este mes, cuántos ya son clientes'
            : tc === undefined
              ? `Contratos confirmados · total en S/ · consultando tipo de cambio… · ${metaMensual.etiqueta}`
              // El rótulo del TC sale del MISMO tc que aplicó la lib (ranking.tc,
              // re-validado finito y > 0): jamás se anuncia un TC que no entró al total.
              : rankingCapitalTotal.tc != null
                ? `Contratos confirmados · total en S/ · TC S/ ${numero(rankingCapitalTotal.tc, 4)} (${tc?.fuente ?? 'BCRP'}) · ${metaMensual.etiqueta}`
                : `Contratos confirmados · S/ · US$ aparte: tipo de cambio no disponible · ${metaMensual.etiqueta}`}
        </p>
      </div>

      {errorActivo ? (
        <TabpanelMarco tab={tipo}><ErrorRanking error={errorActivo} onReintentar={reintentarActivo} /></TabpanelMarco>
      ) : cargandoActivo ? (
        <CargandoTabpanel
          tab={tipo}
          mensaje={fotoMensualCargando
            ? 'Consultando identidad, metas y capital del mes…'
            : tipo === 'conversion'
              ? 'Consultando la conversión del mes…'
              : tipo === 'capital-total'
                ? 'Consultando tipo de cambio…'
                : 'Consultando los resultados de los leads del mes…'}
        />
      ) : totalVendedores === 0 ? (
        <TabpanelMarco tab={tipo}>
          <div className="grid min-h-64 place-items-center px-5 text-center"><div><Target className="mx-auto size-8 text-[var(--gi-muted)]" aria-hidden /><p className="mt-3 text-sm font-semibold">Aún no hay analistas para mostrar</p></div></div>
        </TabpanelMarco>
      ) : tipo === 'conversion' ? (
        <RankingConversion
          ranking={rankingConversion}
          etiquetaBase={conversionMensual?.fuentes.divisor === 'crm.leads.creado_en'
            ? 'Base automática'
            : conversionMensual == null ? 'Base del mes' : 'Base histórica'}
        />
      ) : tipo === 'cosecha' ? (
        <TabpanelMarco tab="cosecha">
          <CosechaLote cosecha={cosecha} equipo={equipoRanking} enRevision={cosechaEnRevision} />
        </TabpanelMarco>
      ) : !metaMensual.comparable ? (
        <div role="tabpanel" id="panel-ranking-capital" aria-labelledby="tab-ranking-capital-total" className="grid min-h-64 place-items-center px-5 text-center">
          <div className="max-w-md rounded-2xl border border-amber-300/70 bg-amber-50 px-5 py-4">
            <p className="text-xs font-bold text-amber-900">Meta mensual · {metaMensual.etiqueta}</p>
            <p role="status" className="mt-2 text-xs font-medium text-amber-900">{mensajeMetaNoComparable(metaMensual)}</p>
          </div>
        </div>
      ) : (
        <>
          {tc === null && (
            // Sin este botón, un fallo AISLADO del TC no tenía vía de recuperación:
            // ErrorRanking solo aparece cuando fallan las conversiones (hallazgo Codex).
            <div className="mx-4 mt-3 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-2.5 sm:mx-5">
              <span className="text-xs font-semibold text-amber-900">
                Tipo de cambio no disponible: el total muestra solo S/ y el US$ va aparte.
              </span>
              <Button type="button" variant="outline" size="sm" onClick={onReintentarCapital}>
                <RefreshCw aria-hidden /> Reintentar tipo de cambio
              </Button>
            </div>
          )}
          <RankingCapitalTotal ranking={rankingCapitalTotal} />
        </>
      )}
      {!fotoMensualCargando && !fotoMensualError && (
        <ProduccionFueraRankingPanel filas={fueraRanking} tc={tc} />
      )}
    </section>
  )
}
