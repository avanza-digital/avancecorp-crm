import { useMemo, type CSSProperties, type JSX } from 'react'
import type { EChartsOption } from 'echarts'
import { Inbox, Target, UserRoundCheck, UsersRound } from 'lucide-react'
import { GerenciaEChart } from '@/components/gerencia/echart-lazy'
import { GERENCIA_CHART_COLORS as C } from '@/components/gerencia/chart-theme'
import { numero, porcentajeConversionCanonica } from '@/lib/format'
import type { ConversionEquipoVendedor } from '@/lib/conversion-equipo'
import { rotuloDeLaCifra } from '@/lib/conversion-rotulo'
import {
  totalConversionPublicable,
  type ConversionMensual,
} from '@/lib/conversion-mensual'
import {
  adaptarConversionMensualPorFuente,
  clasificarRankingConversion,
  etiquetaFuentesConversion,
  type AporteConversionRango,
  type ConversionVendedorAdaptada,
  type DetalleConversionMensual,
  type FiltroFuentesConversion,
} from '@/lib/conversion-vendedores'

function pct(valor: number | null): string {
  return porcentajeConversionCanonica(valor)
}

/** Rótulo corto de tarjeta para los estados sin % — jamás un «0 %» inventado. */
function etiquetaEstado(fila: ConversionVendedorAdaptada<DetalleConversionMensual>): string | null {
  switch (fila.estadoConversion) {
    case 'sin_muestra': return 'Sin muestra'
    case 'solo_referidos': return 'Solo referidos'
    case 'solo_arrastre': return 'Solo arrastre'
    case 'indisponible': return 'No disponible'
    default: return null
  }
}

export function EquipoGerenciaPanel({
  conversionMensual,
  conversiones,
  fuenteConversion = null,
  lecturaFuente,
}: {
  /**
   * La conversión mensual ponderada (`crm.conversion_mensual_fn`) — única
   * fuente de los números de este panel. Tri-estado: `undefined` consultando,
   * `null` no disponible; ambos degradan a «—»/«No disponible» (fail-closed),
   * nunca a ceros ni a la fórmula vieja del rango.
   */
  conversionMensual: ConversionMensual | null | undefined
  conversiones: ConversionEquipoVendedor[]
  fuenteConversion?: FiltroFuentesConversion
  lecturaFuente?: AporteConversionRango | null | undefined
}): JSX.Element {
  const adaptada = useMemo(
    () => adaptarConversionMensualPorFuente(
      conversionMensual ?? null,
      conversiones,
      fuenteConversion,
      lecturaFuente,
    ),
    [conversionMensual, conversiones, fuenteConversion, lecturaFuente],
  )
  const ranking = useMemo(
    () => clasificarRankingConversion(adaptada.vendedores),
    [adaptada.vendedores],
  )
  // La gráfica compara %: solo entran los MEDIBLES (solo_arrastre compite en el
  // ranking pero no tiene % que barra pueda representar).
  const medibles = ranking.conPuesto.filter((fila) => fila.detalle.conversion_pct != null)
  // Los agregados del equipo los sirve la RPC — aquí no se divide nada global.
  const total = totalConversionPublicable(conversionMensual)
  const etiquetaFuente = fuenteConversion == null
    ? null
    : etiquetaFuentesConversion(fuenteConversion)
  const base = fuenteConversion == null ? total?.divisor ?? null : lecturaFuente?.divisor ?? null
  const etiquetaBase = fuenteConversion != null
    ? 'Base automática'
    : conversionMensual == null
    ? 'Base del mes'
    : conversionMensual.fuentes.divisor === 'crm.leads.creado_en'
      ? 'Base automática'
      : 'Base histórica'
  const cierres = fuenteConversion == null
    ? total == null ? null : total.cierres_no_referidos + total.cierres_referidos
    : lecturaFuente?.cierres ?? null
  const operaciones = fuenteConversion == null
    ? total?.cartera.conversiones_clientes ?? null
    : lecturaFuente?.operaciones ?? null
  const soloCartera = lecturaFuente?.familia === 'cartera'
  const conversion = fuenteConversion == null
    ? total?.conversion_pct ?? null
    : lecturaFuente?.porcentaje ?? null
  const vendedores = adaptada.vendedores.length
  // La identidad pertenece a la misma población que la conversión: roster
  // vivo hoy o snapshot del mes histórico. Contar supervisores desde el store
  // actual hacía que agosto mezclara la jerarquía de setiembre.
  const supervisores = new Set(
    adaptada.vendedores
      .filter((fila) => fila.supervisorNombre !== 'Sin supervisor'
        && fila.supervisorNombre !== 'Equipo no disponible')
      .map((fila) => fila.supervisorId ?? `nombre:${fila.supervisorNombre}`),
  ).size
  const kpis = [
    { label: 'Analistas', valor: numero(vendedores), icon: UsersRound, color: C.blue },
    { label: 'Supervisores', valor: numero(supervisores), icon: Target, color: C.amber },
    { label: etiquetaBase, valor: base == null ? '—' : numero(base), icon: Inbox, color: C.navy },
    { label: soloCartera ? 'Operaciones' : 'Cierres del mes', valor: (soloCartera ? operaciones : cierres) == null ? '—' : numero((soloCartera ? operaciones : cierres)!), detalle: !soloCartera && operaciones != null && operaciones > 0 ? `+ ${numero(operaciones)} operaciones de cartera` : null, icon: UserRoundCheck, color: C.green },
    // EL RÓTULO. Este panel lee `crm.conversion_mensual_fn` DIRECTAMENTE, así
    // que su cifra es la oficial por construcción: se declara como tal, y se
    // dice cuándo el mes ya está sellado (entonces la cifra es una foto y deja
    // de moverse). Con un filtro de fuente activo, el desglose se calcula en
    // vivo y eso también se dice. `detalle` ya existe en el tile: no cambia el
    // layout.
    { label: fuenteConversion == null ? 'Conversión del mes' : `Aporte de ${etiquetaFuente}`, valor: pct(conversion),
      detalle: rotuloDeLaCifra({
        es_mes_calendario: true, fuente: 'mensual',
        sellado: conversionMensual?.cierre?.cerrado ?? false, ajuste_aplicado: true,
      }, fuenteConversion != null),
      icon: Target, color: C.teal },
  ]

  const opcion = useMemo<EChartsOption>(() => ({
    animationDuration: 600,
    grid: { left: 132, right: 58, top: 8, bottom: 28 },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      valueFormatter: (valor) => porcentajeConversionCanonica(
        typeof valor === 'number' ? valor : null,
      ),
    },
    xAxis: {
      type: 'value',
      min: 0,
      axisLabel: { formatter: '{value}%', color: C.muted, fontFamily: 'IBM Plex Sans' },
      splitLine: { lineStyle: { color: C.grid } },
    },
    yAxis: {
      type: 'category',
      inverse: true,
      data: medibles.map((fila) => fila.nombre),
      axisTick: { show: false },
      axisLine: { show: false },
      axisLabel: { color: C.navy, fontFamily: 'IBM Plex Sans', fontSize: 11, width: 120, overflow: 'truncate' },
    },
    series: [{
      type: 'bar',
      data: medibles.map((fila) => fila.detalle.conversion_pct),
      barMaxWidth: 16,
      itemStyle: { color: C.teal, borderRadius: [0, 8, 8, 0] },
      label: {
        show: true,
        position: 'right',
        formatter: (parametros) => porcentajeConversionCanonica(
          typeof parametros.value === 'number' ? parametros.value : null,
        ),
        color: C.navy,
        fontWeight: 600,
        fontFamily: 'IBM Plex Sans',
      },
    }],
  }), [medibles])

  const grupos = useMemo(() => {
    const mapa = new Map<string, {
      nombre: string
      vendedores: ConversionVendedorAdaptada<DetalleConversionMensual>[]
    }>()
    for (const fila of adaptada.vendedores) {
      const clave = fila.supervisorId ?? `nombre:${fila.supervisorNombre}`
      const grupo = mapa.get(clave)
      if (grupo) grupo.vendedores.push(fila)
      else mapa.set(clave, { nombre: fila.supervisorNombre, vendedores: [fila] })
    }
    return [...mapa.entries()].sort(([, a], [, b]) => a.nombre.localeCompare(b.nombre, 'es'))
  }, [adaptada.vendedores])

  if (adaptada.vendedores.length === 0) {
    return <div className="gi-card py-14 text-center"><UsersRound className="mx-auto size-8 text-[var(--gi-muted)]" /><p className="mt-3 text-sm font-semibold">No hay analistas para mostrar</p></div>
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        {kpis.map(({ label, valor, detalle, icon: Icono, color }) => {
          return <div key={label} data-gi-kpi className="gi-kpi-card" style={{ '--gi-kpi': color } as CSSProperties}><div className="flex justify-between"><p className="gi-label">{label}</p><Icono className="size-4" style={{ color }} /></div><p className="mt-2 text-3xl font-bold tabular-nums">{valor}</p>{detalle && <p className="gi-caption mt-1">{detalle}</p>}</div>
        })}
      </div>

      <p className="gi-caption">
        {fuenteConversion != null
          ? `${etiquetaFuente}: mismo divisor y ponderación del índice comercial.`
          : conversionMensual == null
          ? 'La base mensual no está disponible.'
          : conversionMensual.fuentes.divisor === 'crm.leads.creado_en'
            ? 'Base automática: prospectos recibidos desde Landing/Formulario. No incluye altas manuales ni referidos.'
            : 'Base histórica: conserva la definición de la foto mensual; no equivale a prospectos recibidos.'}
      </p>

      {medibles.length > 0 && (
        <section data-gi-panel className="gi-card p-5">
          <div className="flex items-center justify-between"><h2 className="gi-title">{fuenteConversion == null ? 'Conversión por analista' : `Aporte de ${etiquetaFuente} por analista`}</h2><span className="gi-caption">{numero(medibles.length)} {medibles.length === 1 ? 'analista medible' : 'analistas medibles'} este mes</span></div>
          <GerenciaEChart tipo="barras" option={opcion} ariaLabel={fuenteConversion == null ? 'Conversión por analista' : `Aporte de ${etiquetaFuente} por analista`} className="mt-3 w-full" style={{ height: Math.max(290, medibles.length * 38) }} />
        </section>
      )}

      <div className="space-y-4">
        {grupos.map(([supervisorId, { nombre: supervisor, vendedores: vendedoresGrupo }]) => {
          const grupoDisponible = vendedoresGrupo.every((fila) => fila.detalle != null)
          // F3: el navegador ya no divide el % del grupo (era la última
          // aritmética de conversión que quedaba aquí). El servidor no sirve
          // todavía una cifra por supervisor con el núcleo — hasta que exista,
          // la cabecera enseña los enteros SERVIDOS (cierres y base son
          // sumas de lo que manda la RPC), no un % fabricado.
          const totalBase = grupoDisponible
            ? vendedoresGrupo.reduce((n, fila) => n + (fila.detalle?.divisor ?? 0), 0)
            : null
          const totalCierres = grupoDisponible
            ? vendedoresGrupo.reduce((n, fila) => n + (lecturaFuente?.familia === 'cartera' ? fila.detalle?.operacionesCartera ?? 0 : fila.detalle?.clientes ?? 0), 0)
            : null
          const maximoGrupo = Math.max(1, ...vendedoresGrupo.map((fila) => fila.detalle?.conversion_pct ?? 0))
          return (
            <section key={supervisorId} data-gi-panel className="gi-card overflow-hidden">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--gi-line)] bg-[var(--gi-soft)] px-5 py-4">
                <div><h2 className="gi-title">{supervisor}</h2><p className="gi-caption mt-1">{numero(vendedoresGrupo.length)} {vendedoresGrupo.length === 1 ? 'analista' : 'analistas'}</p></div>
                <div className="text-right"><strong className="text-xl tabular-nums text-[var(--gi-blue)]">{totalCierres == null ? '—' : numero(totalCierres)}</strong><p className="gi-caption">{totalCierres == null || totalBase == null ? 'Datos no disponibles' : `${lecturaFuente?.familia === 'cartera' ? 'operaciones' : 'cierres del mes'} · ${etiquetaBase.toLowerCase()}: ${numero(totalBase)}`}</p></div>
              </div>
              <div className="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
                {vendedoresGrupo.map((fila) => {
                  const conversionFila = fila.detalle?.conversion_pct ?? null
                  return (
                    <div key={fila.vendedorId} className="rounded-xl border border-[var(--gi-line)] bg-white p-4">
                      <div className="flex items-start justify-between gap-3"><div><p className="text-sm font-semibold">{fila.nombre}</p><p className="gi-caption mt-1">{fila.detalle == null ? 'Datos no disponibles' : `${etiquetaBase}: ${numero(fila.detalle.divisor)} · ${numero(lecturaFuente?.familia === 'cartera' ? fila.detalle.operacionesCartera : fila.detalle.clientes)} ${lecturaFuente?.familia === 'cartera' ? 'operaciones' : 'cierres'}${lecturaFuente?.familia !== 'cartera' && fila.detalle.operacionesCartera > 0 ? ` + ${numero(fila.detalle.operacionesCartera)} operaciones` : ''}`}</p></div><strong className="tabular-nums text-[var(--gi-blue)]">{etiquetaEstado(fila) ?? pct(conversionFila)}</strong></div>
                      {/* Barra RELATIVA al máximo del grupo: un 120 % no se disfraza de 100. */}
                      <div className="gi-track mt-3"><div className="gi-fill" style={{ width: `${conversionFila == null ? 0 : (conversionFila / maximoGrupo) * 100}%`, background: C.teal }} /></div>
                    </div>
                  )
                })}
              </div>
            </section>
          )
        })}
      </div>
    </div>
  )
}
