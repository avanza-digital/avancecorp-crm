import { useMemo, type JSX } from 'react'
import {
  AlertTriangle,
  Activity,
  CalendarDays,
  Clock3,
  TrendingUp,
  RefreshCw,
  Target,
} from 'lucide-react'
import { IndicadorGerencia } from '@/components/gerencia/indicador-gerencia'
import { AtencionCitas } from '@/components/gerencia/atencion-citas'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { IndicadorVisual } from '@/components/gerencia/indicador-visual'
import { EvolucionLlegadas } from '@/components/gerencia/evolucion-llegadas'
import { AnalistasVisuales } from '@/components/gerencia/analistas-visuales'
import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import {
  mensajeMetaNoComparable,
  type MetaMensualGerencia,
} from '@/components/gerencia/periodo'
import { fmtFecha, money, moneyCompacta, numero, porcentajeConversionCanonica } from '@/lib/format'
import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
import {
  capitalObjetivo,
  capitalReal,
  metaConversionAplicable,
  type CumplimientoAgregado,
  type ObjetivoComercial,
} from '@/lib/objetivos'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import type { ConversionMensual } from '@/lib/conversion-mensual'
import {
  adaptarConversionMensual,
  adaptarConversionVendedores,
  clasificarRankingConversion,
} from '@/lib/conversion-vendedores'
import type { MetricasConversiones } from '@/lib/metricas-conversiones'
import type { MetricasReuniones } from '@/lib/metricas-reuniones'
import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
import { etiquetaOrigen } from '@/lib/tipos'
import { presentarCitas } from '@/lib/terminologia'
import { sondasNucleoVerificadas } from '@/lib/sondas-conversion'

interface ResumenGerenciaPanelProps {
  conversiones: MetricasConversiones | null | undefined
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`) alimenta
   * metas, «Mejores analistas» y el fallback compatible si un servidor antiguo
   * no trae `conversiones.nucleo`. El héroe real usa el núcleo del rango exacto.
   */
  conversionMensual: ConversionMensual | null | undefined
  reuniones: MetricasReuniones | null | undefined
  /** Población vigente de la RPC por rango. */
  equipo: ConversionEquipoVendedor[]
  /** Foto mensual; puede diferir del roster vigente en un histórico. */
  equipoMensual?: ConversionEquipoVendedor[]
  meta: ObjetivoComercial
  cumplimiento: CumplimientoAgregado | null
  metaMensual: MetaMensualGerencia
  tc: { promedio: number, fuente: string } | null | undefined
  /** Origen del lote aplicado a Cosecha y embudo (null = todos). La conversión
   * canónica del rango y «Avance de metas» permanecen a nivel empresa: el chip
   * lo dice para que las dos aguas no se confundan. */
  origenFiltrado: string | null
  cargando: boolean
  /** Estado exclusivo de `crm.metricas_conversiones_fn` (rango). */
  rangoCargando?: boolean
  /** Carga inicial de conversión + meta/capital mensual; no bloquea el rango. */
  mensualCargando?: boolean
  error: string | null
  modoDemo: boolean
  onReintentar: () => void
}

function pct(valor: number | null): string {
  return porcentajeConversionCanonica(valor)
}

function numeroDisponible(valor: number | null): string {
  return valor == null ? '—' : numero(valor)
}

function ErrorResumen({ error, onReintentar }: { error: string; onReintentar: () => void }): JSX.Element {
  return (
    <div className="gi-card flex flex-wrap items-center justify-between gap-3 p-5" role="alert">
      <span className="flex items-center gap-2 text-sm font-semibold text-destructive">
        <AlertTriangle className="size-4" /> {presentarCitas(error)}
      </span>
      <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
        <RefreshCw /> Reintentar
      </Button>
    </div>
  )
}

export function ResumenGerenciaPanel({
  conversiones,
  conversionMensual,
  reuniones,
  equipo,
  equipoMensual,
  meta,
  cumplimiento,
  metaMensual,
  tc,
  origenFiltrado,
  cargando,
  rangoCargando = false,
  mensualCargando = false,
  error,
  modoDemo,
  onReintentar,
}: ResumenGerenciaPanelProps): JSX.Element {
  const consulta = useConsultaGerencia()
  const clientes = conversiones?.cohorte.contratos ?? null
  const leads = conversiones?.cohorte.leads ?? null
  // El número grande obedece al rango visible y toma el porcentaje YA SERVIDO
  // en `nucleo`; aquí no se divide ni se reconstruye ninguna conversión. La foto
  // mensual sigue alimentando metas y el ranking, que sí son mensuales.
  const origenesVerificados = conversiones?.nucleo != null
    && sondasNucleoVerificadas(conversiones.sondas)
  const nucleoRango = origenesVerificados ? conversiones.nucleo ?? null : null
  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
  const totalMes = totalConversionPublicable(conversionMensual)
  const conversionMes = totalMes?.conversion_pct ?? null
  const cierresMes = totalMes == null ? null : totalMes.cierres_no_referidos + totalMes.cierres_referidos
  const rangoEsperando = rangoCargando && conversiones === undefined
  const usaNucleoRango = conversiones?.nucleo != null || rangoEsperando
  const conversionPrincipal = usaNucleoRango ? nucleoRango?.conversion_pct ?? null : conversionMes
  const conversionPrincipalCargando = usaNucleoRango ? rangoEsperando : mensualCargando
  const etiquetaPeriodoRango = conversiones == null
    ? ''
    : `${fmtFecha(conversiones.periodo.desde)} al ${fmtFecha(conversiones.periodo.hasta)}`
  const reunionesRealizadas = reuniones?.resumen.realizadas ?? null
  const reunionesPactadas = reuniones?.resumen.pactadas ?? null
  const metasComparables = metaMensual.comparable && metaMensual.errorCarga !== true
  const metaConversion = metaConversionAplicable(
    meta.conversionObjetivo,
    metaMensual.errorCarga === true,
  )
  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
  const cumplimientoCapitalPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
  const cumplimientoCapitalUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
  // Capital CONSOLIDADO, no dos barras: la meta se pacta en soles, así que la
  // barra de dólares no podía tener meta y decía «Sin meta» para siempre
  // mientras el capital real en USD no contaba para nada.
  const capitalTotal = totalEnSoles(cumplimientoCapitalPen, cumplimientoCapitalUsd, tc?.promedio)
  const metaTotalCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
  const hayDolares = (cumplimientoCapitalUsd ?? 0) > 0 || metaCapitalUsd > 0
  const tcEnVuelo = tc === undefined && hayDolares
  const tcCaido = tc === null && hayDolares
  // El capital del héroe y del KPI es el CONFIRMADO del mes (cumplimiento de
  // cierres) — la misma fuente y el mismo nombre que Metas y «Avance de metas».
  // Antes leía `produccion.capital_*`, que suma contratos enlazados a un lead
  // vía `crm.leads.contrato_id`: ese enlace jamás se ha escrito (auditoría en
  // producción 27/08: 0 enlaces históricos), así que afirmaba «S/ 0» con
  // S/ 3,7 M cerrados. Decisión de Miguel 27/08: fuente de cierres (opción A).
  const capitalMesTexto = tcEnVuelo
    ? 'Calculando…'
    : capitalTotal.total == null ? '—' : money(capitalTotal.total, 'PEN')
  const capitalMesDetalle = cumplimiento == null
    ? 'Cumplimiento confirmado no disponible'
    : tcEnVuelo
      ? 'Consultando el tipo de cambio para consolidar los dólares…'
      : (cumplimientoCapitalUsd ?? 0) > 0
        ? `${money(cumplimientoCapitalPen ?? 0, 'PEN')} + ${money(cumplimientoCapitalUsd ?? 0, 'USD')}${
          capitalTotal.tc == null
            ? ' · sin tipo de cambio: el total NO incluye los dólares'
            : ` · ${rotuloTipoCambio(capitalTotal.tc, tc?.fuente ?? 'TC del día')}`}`
        : (capitalTotal.total ?? 0) > 0
          ? 'Todo en soles'
          : 'Sin capital confirmado este mes'
  const avanceCapital = metasComparables && !tcEnVuelo
    && (metaTotalCapital.total ?? 0) > 0 && capitalTotal.total != null
    ? Math.max(0, (capitalTotal.total / (metaTotalCapital.total ?? 1)) * 100)
    : null
  // La barra avanza con EL MISMO número que el titular: la conversión del mes
  // servida. Hasta 2026-08-13 medía `cumplimiento.conversionReal`, que es otra
  // fórmula (convertidos/RESUELTOS, sin ponderar referidos ni arrastre): la
  // pantalla enseñaba un porcentaje arriba y avanzaba la meta con otro, y los
  // dos se llamaban «conversión». Un solo número bajo un solo nombre. Si el mes
  // no es medible no hay barra, que es más honesto que una barra de mentira.
  const avanceConversion = metasComparables && metaConversion != null && conversionMes != null
    ? Math.max(0, (conversionMes / metaConversion) * 100)
    : null

  const vendedoresAdaptados = useMemo(
    () => adaptarConversionVendedores(conversiones, equipo),
    [conversiones, equipo],
  )
  const tendenciaEquipo = vendedoresAdaptados.tendenciaSemanal
  const adaptadaMensual = useMemo(
    () => adaptarConversionMensual(conversionMensual ?? null, equipoMensual ?? equipo),
    [conversionMensual, equipo, equipoMensual],
  )
  const rankingMes = useMemo(
    () => clasificarRankingConversion(adaptadaMensual.vendedores),
    [adaptadaMensual.vendedores],
  )
  const origenes = [...(conversiones?.origenes ?? [])]
    .sort((a, b) => (b.conversion_contratos_pct ?? -1) - (a.conversion_contratos_pct ?? -1))
    .slice(0, 5)
  const maxOrigen = Math.max(1, ...origenes.map((fila) => fila.conversion_contratos_pct ?? 0))
  const hayActividadConversiones = [
    conversiones?.cohorte.leads,
    conversiones?.cohorte.asignados,
    conversiones?.cohorte.contactados,
    conversiones?.cohorte.reuniones_agendadas,
    conversiones?.cohorte.reuniones_realizadas,
    conversiones?.cohorte.propuestas,
    conversiones?.cohorte.clientes,
    conversiones?.cohorte.contratos,
    conversiones?.cohorte.descartados,
    conversiones?.produccion.clientes,
    conversiones?.produccion.contratos,
    conversiones?.produccion.capital_pen,
    conversiones?.produccion.capital_usd,
  ].some((valor) => (valor ?? 0) > 0)
  const hayActividadReuniones = [
    reuniones?.resumen.pactadas,
    reuniones?.resumen.debieron_ocurrir,
    reuniones?.resumen.realizadas,
    reuniones?.resumen.no_concretadas,
    reuniones?.resumen.no_show,
    reuniones?.resumen.canceladas,
    reuniones?.resumen.canceladas_sistema,
    reuniones?.resumen.reprogramadas,
    reuniones?.resumen.pendientes_cierre,
    reuniones?.resumen.programadas_futuras,
    reuniones?.conversion.leads_reunidos,
    reuniones?.conversion.clientes,
    reuniones?.conversion.contratos,
    reuniones?.conversion.capital_pen,
    reuniones?.conversion.capital_usd,
  ].some((valor) => (valor ?? 0) > 0)
  const hayMetas = metaCapitalPen > 0
    || metaCapitalUsd > 0
    || meta.conversionObjetivo > 0
  const hayActividadEquipo = vendedoresAdaptados.vendedores.some((fila) => fila.detalle != null && [
    fila.detalle.leads,
    fila.detalle.contactados,
    fila.detalle.reuniones_realizadas,
    fila.detalle.clientes,
    fila.detalle.capital_pen,
    fila.detalle.capital_usd,
  ].some((valor) => valor > 0))
  const hayContenidoResumen = hayActividadConversiones
    || hayActividadReuniones
    || hayMetas
    || hayActividadEquipo
    // Capital confirmado sin actividad de leads (p. ej. solo cierres de
    // cartera): el resumen tiene algo verdadero que enseñar, no es «vacío».
    || (cumplimientoCapitalPen ?? 0) > 0
    || (cumplimientoCapitalUsd ?? 0) > 0
    || (conversiones?.nucleo?.divisor ?? 0) > 0
    || (conversiones?.nucleo?.numerador ?? 0) > 0
    || (conversionMensual?.total.divisor ?? 0) > 0
    || (conversionMensual?.total.numerador ?? 0) > 0
    || metaMensual.errorCarga === true
    || mensualCargando

  if (cargando && !conversiones && !reuniones) {
    return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="h-32 rounded-2xl" />)}</div>
  }
  if (!hayContenidoResumen) {
    if (error) return <ErrorResumen error={error} onReintentar={onReintentar} />
    if (conversiones == null || reuniones == null) {
      return <ErrorResumen error="Datos del resumen no disponibles. No se recibió una lectura completa del rango." onReintentar={onReintentar} />
    }
    return <div className="gi-card py-14 text-center"><Target className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">Aún no hay actividad comercial en este período</p></div>
  }

  return (
    <div className="space-y-4">
      {error && <ErrorResumen error={error} onReintentar={onReintentar} />}
      {tcCaido && (
        <div className="gi-card flex flex-wrap items-center justify-between gap-3 p-5" role="alert">
          <span className="flex items-center gap-2 text-sm font-semibold text-amber-900">
            <AlertTriangle className="size-4" aria-hidden /> Sin tipo de cambio, el total no incluye los dólares.
          </span>
          <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
            <RefreshCw aria-hidden /> Reintentar tipo de cambio
          </Button>
        </div>
      )}
      {origenFiltrado != null && (
        <p role="status" className="rounded-xl border border-[var(--gi-line)] bg-white px-4 py-2.5 text-xs font-semibold text-[var(--gi-navy)]">
          Origen: {etiquetaOrigen(origenFiltrado)} · filtra las llegadas y sus resultados; las citas, la conversión del rango, el capital mensual y las metas muestran toda la empresa.
        </p>
      )}
      <header className="hidden sm:block">
        <h2 className="text-2xl font-bold leading-8 tracking-[-.025em] text-[var(--gi-navy)]">Resultados para supervisar</h2>
        {modoDemo && <span className="sr-only">Datos de ejemplo.</span>}
      </header>
      <div className="gi-resumen-layout">
        <IndicadorVisual className="gi-capital" etiqueta="Capital confirmado del mes" valor={mensualCargando ? 'Calculando…' : capitalMesTexto} tono="capital" icono={TrendingUp}
          contexto={<p>{metaMensual.etiqueta} · {capitalTotal.tc == null ? 'TC no disponible' : `TC S/ ${numero(capitalTotal.tc, 3)}`}</p>}
          barras={[
            { etiqueta: 'Confirmado', texto: mensualCargando ? '…' : capitalTotal.total == null ? '—' : moneyCompacta(capitalTotal.total, 'PEN'), valor: mensualCargando ? null : capitalTotal.total },
            { etiqueta: 'Meta', texto: mensualCargando ? '…' : !metasComparables ? 'No comparable' : metaTotalCapital.total == null ? '—' : moneyCompacta(metaTotalCapital.total, 'PEN'), valor: !metasComparables || mensualCargando ? null : metaTotalCapital.total, color: 'meta' },
          ]}
          pie={<><TrendingUp aria-hidden />{mensualCargando ? 'Consultando capital y meta…' : avanceCapital == null ? !metasComparables ? mensajeMetaNoComparable(metaMensual) : 'Avance no disponible' : `${numero(avanceCapital, 0)}% de la meta mensual`}</>}
          detalle={<p>{mensualCargando ? 'Consultando capital y meta…' : capitalMesDetalle}</p>} cargando={mensualCargando} />
        <IndicadorVisual className="gi-conversion" etiqueta="Conversión del mes" valor={mensualCargando ? 'Calculando…' : pct(conversionMes)} tono="conversion" icono={Target}
          contexto={<p>{metaMensual.etiqueta} · {totalMes == null ? 'Base no disponible' : `${numero(totalMes.divisor)} ${conversionMensual?.fuentes.divisor === 'crm.leads.creado_en' ? 'leads automáticos' : 'registros históricos'}`}</p>}
          barras={[
            { etiqueta: 'Conversión', texto: mensualCargando ? '…' : pct(conversionMes), valor: mensualCargando ? null : conversionMes },
            { etiqueta: 'Meta', texto: mensualCargando ? '…' : !metasComparables ? 'No comparable' : metaConversion == null ? 'Sin meta' : `${numero(metaConversion, 1)}%`, valor: !metasComparables || mensualCargando ? null : metaConversion, color: 'meta' },
          ]}
          pie={<><Activity aria-hidden /><span role="region" aria-label="Cumplimiento de meta de conversión">{mensualCargando ? 'Consultando…' : avanceConversion == null ? !metasComparables ? metaMensual.errorCarga ? 'No disponible' : 'No comparable' : conversionMes == null ? 'Dato no disponible' : 'Sin meta' : <>{numero(cierresMes ?? 0)} cierres · <strong className="font-medium">{numero(avanceConversion, 0)}%</strong> de la meta</>}</span></>}
          detalle={<><p>Mes calendario · {metaMensual.etiqueta}. La conversión mensual conserva su base ponderada.</p>{lecturaConversion.aviso && <p>{lecturaConversion.aviso}</p>}<p>Objetivo mensual: {metaMensual.errorCarga ? 'No disponible' : metaConversion == null ? 'Sin meta' : `${numero(metaConversion, 1)}%`}</p></>} cargando={mensualCargando} />
        <IndicadorVisual className="gi-citas" etiqueta="Citas realizadas" valor={numeroDisponible(reunionesRealizadas)} tono="citas" icono={CalendarDays}
          contexto={<p>{reuniones ? `${fmtFecha(reuniones.periodo.desde)} al ${fmtFecha(reuniones.periodo.hasta)} · fecha prevista` : 'Período de citas no disponible'}</p>}
          barras={[
            { etiqueta: 'Pactadas', texto: numeroDisponible(reunionesPactadas), valor: reunionesPactadas, color: 'meta' },
            { etiqueta: 'Realizadas', texto: numeroDisponible(reunionesRealizadas), valor: reunionesRealizadas, color: 'azul' },
          ]}
          pie={<><Clock3 aria-hidden />Dos conteos; cada uno conserva su base.</>}
          detalle={<p>{reunionesPactadas == null ? 'Dato no disponible' : `${numero(reunionesPactadas)} pactadas`}. El conteo de pactadas y el de realizadas pueden pertenecer a bases distintas.</p>} />
        <div className="gi-resumen-attention"><AtencionCitas datos={reuniones} cargando={cargando} error={error} /></div>
        <div className="gi-resumen-charts">
          <EvolucionLlegadas puntos={tendenciaEquipo} />
          <AnalistasVisuales filas={rankingMes.conPuesto} periodo={metaMensual.etiqueta} baseAutomatica={conversionMensual?.fuentes.divisor === 'crm.leads.creado_en'} cargando={mensualCargando} disponible={adaptadaMensual.responsablesDisponibles}
            onSeleccionar={(id) => { consulta?.setConsulta((actual) => ({ ...actual, analistaId: id, abrirDetalle: true })); window.location.hash = '#/conversiones' }}
            accion={<a href="#/ranking-vendedores" className="gi-text-button inline-flex items-center" aria-label="Ver ranking general de analistas">Ver Ranking</a>} />
        </div>
      </div>
      <details className="gi-disclosure">
        <summary>Entender los resultados del rango y sus bases</summary>
        <div className="space-y-4">
          <IndicadorGerencia etiqueta={usaNucleoRango ? 'Conversión del rango' : 'Conversión del mes'} valor={conversionPrincipalCargando ? 'Calculando…' : pct(conversionPrincipal)} contexto={<>
            <p>{usaNucleoRango ? `Conversión del rango · ${etiquetaPeriodoRango}` : `Mes calendario · ${metaMensual.etiqueta}`}</p>
          <p className="text-xs leading-[18px]">
            {usaNucleoRango
              ? rangoEsperando
                ? 'Todos los orígenes · consultando el núcleo del rango…'
                : nucleoRango == null
                  ? 'Cifras en revisión: falta verificar la conversión del rango.'
                  : `${nucleoRango.base === 'llegada_unica' ? 'Base:' : 'Base histórica ·'} ${numero(nucleoRango.divisor)} ${nucleoRango.base === 'llegada_unica' ? 'leads automáticos' : 'registros en la base histórica'} · ${numero(nucleoRango.cierres_no_referidos)} ${nucleoRango.base === 'llegada_unica' && nucleoRango.cierres_referidos === 0 ? 'cierres' : 'cierres no referidos'}`
                    + (nucleoRango.cierres_referidos > 0 ? ` · ${numero(nucleoRango.cierres_referidos)} cierres referidos` : '')
                    + (nucleoRango.operaciones_cartera > 0 ? ` · ${numero(nucleoRango.operaciones_cartera)} operaciones de cartera` : '')
              : mensualCargando
                ? 'Consultando conversión, capital y meta del mes…'
                : conversionMensual != null && !lecturaConversion.mostrar
                  ? (lecturaConversion.aviso ?? 'Sin base comercial para este mes')
                  : totalMes == null
                    ? 'Conversión del mes no disponible'
                    : `${numero(cierresMes ?? 0)} cierres este mes`
                      + (lecturaConversion.aviso != null ? ` · ${lecturaConversion.aviso}` : '')}
          </p>
          {usaNucleoRango && nucleoRango?.base === 'llegada_unica' && nucleoRango.llegadas != null && (
            <p className="mt-1 text-xs leading-[18px]">{numero(nucleoRango.llegadas)} llegadas únicas: {numero(nucleoRango.divisor)} automáticas · {nucleoRango.altas_manuales == null ? 'altas manuales no disponibles' : `${numero(nucleoRango.altas_manuales)} manuales`} · {numero(nucleoRango.referidos_recibidos)} {nucleoRango.referidos_recibidos === 1 ? 'referido' : 'referidos'}</p>
          )}
          {usaNucleoRango && nucleoRango != null && !nucleoRango.incluye_cartera && (
            <p className="mt-1 text-xs font-semibold text-warning-text">El rango parcial no incluye operaciones de cartera.</p>
          )}
          </>} />

          <p className="text-sm">{numeroDisponible(clientes)} leads cerrados de {numeroDisponible(leads)} llegadas del rango. Esta base difiere de la conversión ponderada.</p>
          <nav aria-label="Profundizar en los reportes" className="flex flex-wrap gap-3">
            {[['#/conversiones', 'Ver Conversiones'], ['#/ranking-vendedores', 'Ver Ranking'], ['#/metas', 'Consultar Metas']].map(([href, texto]) => <a key={href} href={href} className="gi-text-button inline-flex items-center">{texto}</a>)}
          </nav>
        </div>
      </details>
      <details className="gi-disclosure"><summary>Resultados por origen y desglose de metas</summary><div>
        <section data-gi-panel className="gi-card p-5 lg:col-span-2">
          <h2 className="gi-title">Resultados por origen</h2>
          <p className="gi-caption mt-1">De los leads del mes en cada origen, qué porcentaje cerró. No es la conversión ponderada.</p>
          {!origenesVerificados
            ? <p role="status" className="mt-4 rounded-xl border border-amber-300/70 bg-amber-50 px-4 py-3 text-xs font-semibold text-amber-900">Cifras en revisión: los resultados por origen permanecen ocultos.</p>
            : <div className="mt-4 grid gap-3 sm:grid-cols-2">
                {origenes.length > 0
                  ? origenes.map((fila) => (
                      <div key={fila.origen}>
                        <div className="mb-1.5 flex justify-between gap-3 text-xs"><span className="font-medium">{fila.origen}</span><strong>{pct(fila.conversion_contratos_pct)}</strong></div>
                        <div className="gi-track"><div className="gi-fill" style={{ width: `${((fila.conversion_contratos_pct ?? 0) / maxOrigen) * 100}%`, background: C.blue }} /></div>
                      </div>
                    ))
                  : <p className="rounded-xl border border-dashed border-[var(--gi-line)] px-4 py-8 text-center text-xs font-medium text-[var(--gi-muted)] sm:col-span-2">Aún no hay orígenes con leads en este período</p>}
              </div>}
          {origenesVerificados && origenes.some((fila) => fila.fuera_del_divisor_del_nucleo === true) && (
            // D6: el origen Referido queda fuera de la base general de la
            // conversión — su barra mide cierres sobre SUS recibidos.
            <p className="mt-3 text-[11px] leading-relaxed text-[var(--gi-muted)]">
              {origenes.filter((fila) => fila.fuera_del_divisor_del_nucleo === true).map((fila) => fila.origen).join(', ')}: de los recibidos por ese origen, cuánto cerró — queda fuera de la base general de la conversión.
            </p>
          )}
        </section>
        <p className="gi-caption mt-3">Meta mensual · {metaMensual.etiqueta}. {mensualCargando ? 'Consultando capital y meta…' : capitalMesDetalle}</p>
        <a href="#/metas" className="gi-text-button inline-flex items-center">Consultar Metas</a>
      </div></details>
    </div>
  )
}
