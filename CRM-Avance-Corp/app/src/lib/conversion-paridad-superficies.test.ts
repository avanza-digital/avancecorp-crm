import { createElement, type ReactNode } from 'react'
import { render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
import { PeriodoGerenciaProvider } from '@/components/gerencia/periodo-context'
import { identidadesEquipoConversion } from './conversion-equipo'
import type { ConversionMensual } from './conversion-mensual'
import { adaptarConversionMensual } from './conversion-vendedores'
import { derivarConversionMensual } from './demo-conversion-mensual'
import {
  metricasConversionesDemo,
  metricasReunionesDemo,
} from './demo-inteligencia-comercial'
import { porcentajeConversionCanonica } from './format'
import {
  MetricasVendedoresSchema,
  mapearMetricasVendedores,
  type MetricasVendedoresOperativas,
} from './metricas-vendedores'
import { objetivosCero, type ObjetivosPorRol } from './objetivos'
import type { Miembro, Yo } from './tipos'

const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

const VENDEDOR: Miembro = {
  perfil_id: 'v-1',
  nombre_completo: 'ANA TORRES',
  rol_crm: 'vendedor',
  supervisor_id: 's-1',
  activo: true,
}

const SUPERVISOR: Miembro = {
  perfil_id: 's-1',
  nombre_completo: 'SUPERVISORA UNO',
  rol_crm: 'supervisor',
  supervisor_id: null,
  activo: true,
}

const YO_GERENCIA: Yo = {
  id: 'g-1',
  nombre_completo: 'GERENCIA UNO',
  rol: 'gerencia',
  demo: false,
  puede_contratar: true,
}

const YO_DIRECTORIO: Yo = {
  id: 'd-1',
  nombre_completo: 'DIRECTORIO UNO',
  rol: 'directorio',
  demo: false,
  puede_contratar: false,
}

const IDENTIDADES = identidadesEquipoConversion(
  [VENDEDOR],
  [SUPERVISOR, VENDEDOR],
)

let CONVERSION_UI: ConversionMensual | null = null
let METRICAS_UI: MetricasVendedoresOperativas | null = null
let YO_UI: Yo | null = YO_GERENCIA
let OBJETIVOS_UI: ObjetivosPorRol = objetivosCero('2026-08-01')

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: YO_UI }),
}))

vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: [], vendedores: [VENDEDOR], esGlobal: true },
    equipo: [SUPERVISOR, VENDEDOR],
    actividades: [],
    objetivos: OBJETIVOS_UI,
    objetivosError: false,
    cumplimientoMetas: null,
    cumplimientoMetasError: false,
    recargar: vi.fn(),
  }),
  usePanelesActions: () => ({ abrirLead: vi.fn() }),
}))

vi.mock('@/lib/ahora', () => ({ useAhora: () => AHORA }))

vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/tipo-cambio')>(),
  useTipoCambio: () => ({ tc: null, recargar: vi.fn() }),
}))

vi.mock('@/data/use-resumen-cartera-operativo', () => ({
  useResumenCarteraOperativo: () => ({ resumen: null, error: null, recargar: vi.fn() }),
}))

vi.mock('@/data/use-metricas-vendedores-operativas', () => ({
  useMetricasVendedoresOperativas: () => ({
    metricas: METRICAS_UI,
    error: null,
    recargar: vi.fn(),
  }),
}))

vi.mock('@/data/crm-queries', () => ({
  useConversionMensual: () => ({
    data: CONVERSION_UI ?? undefined,
    error: null,
    isError: false,
    isPending: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
  useMetricasConversiones: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
  useMetricasReuniones: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
  useMetricasDistribucionLeadsV3: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
  useMetricasConversionesEquipo: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: vi.fn(),
  }),
  useActualizarCapacidadLeadsObjetivo: () => ({ mutateAsync: vi.fn() }),
}))

vi.mock('@/data/crm-api', () => ({
  mensajeDeError: (_error: unknown, fallback: string) => fallback,
}))

vi.mock('@/components/gerencia/echart-lazy', () => ({ GerenciaEChart: () => null }))
vi.mock('@/components/gerencia/motion', () => ({
  GerenciaMotion: ({ children }: { children: ReactNode }) => createElement('div', null, children),
}))
vi.mock('@/screens/hoy/aviso-cierre-mes', () => ({ AvisoCierreMesPanel: () => null }))
vi.mock('@/screens/hoy/metas-editor', () => ({ MetasEditor: () => null }))

const { ResumenGerenciaPanel } = await import('@/screens/hoy/resumen-gerencia')
const { HoyGerencia } = await import('@/screens/hoy/gerencia')
const { HoyDirectorio } = await import('@/screens/hoy/directorio')

interface FotoCanonica {
  mensual: ConversionMensual
  gestion: MetricasVendedoresOperativas
  ranking: ReturnType<typeof adaptarConversionMensual>
  cierres: number
  operaciones: number
}

function crearFotoCanonica(enRevision = false): FotoCanonica {
  const noReferidos = Array.from({ length: 8 }, (_, indice) => ({
    leadId: `nr-${indice + 1}`,
    analistaId: VENDEDOR.perfil_id,
    asignadoHaceMeses: 0 as const,
    origen: 'landing' as const,
    ...(indice < 2
      ? { resultado: 'convertido' as const, resultadoHaceMeses: 0 as const }
      : {}),
  }))
  const base = derivarConversionMensual(
    AHORA,
    { alcance: 'global' },
    [...noReferidos, {
      leadId: 'ref-1',
      analistaId: VENDEDOR.perfil_id,
      asignadoHaceMeses: 0,
      origen: 'referido',
      resultado: 'convertido',
      resultadoHaceMeses: 0,
    }],
    [{ analistaId: VENDEDOR.perfil_id, supervisorId: SUPERVISOR.perfil_id }],
  )
  const mensual: ConversionMensual = enRevision
    ? { ...base, cobertura: { ...base.cobertura, cierres_sin_episodio: 1 } }
    : base
  const responsable = mensual.responsables[0]!
  const cierres = responsable.cierres_no_referidos + responsable.cierres_referidos
  const operaciones = responsable.cartera.conversiones_clientes

  const payload = v.parse(MetricasVendedoresSchema, {
    version: 1,
    generado_en: mensual.generado_en,
    ventana_convertidos_dias: 45,
    ventana_metrica: 'mes_calendario',
    mes_metrica: `${mensual.periodo.mes}-01`,
    peso_referido: mensual.ponderacion.referido,
    cobertura_conversion: mensual.cobertura,
    nucleo_total: {
      nucleo_convertidos: mensual.total.cierres_no_referidos
        + mensual.total.cierres_referidos,
      operaciones_cartera: mensual.total.cartera.conversiones_clientes,
      nucleo_divisor: mensual.total.divisor,
      nucleo_numerador: mensual.total.numerador,
      nucleo_conversion_pct: mensual.total.conversion_pct,
    },
    vendedores: [{
      vendedor_id: VENDEDOR.perfil_id,
      rol_crm: 'vendedor',
      activo: true,
      activos: 0,
      capital_pen: 0,
      capital_usd: 0,
      convertidos: cierres,
      conversion_pct: Math.round(responsable.conversion_pct ?? 0),
      nucleo_convertidos: cierres,
      operaciones_cartera: operaciones,
      nucleo_divisor: responsable.divisor,
      nucleo_numerador: responsable.numerador,
      nucleo_conversion_pct: responsable.conversion_pct,
      sin_tocar: 0,
      dias_sin_actividad_max: 0,
    }],
    equipos: [{
      supervisor_id: SUPERVISOR.perfil_id,
      vendedores: 1,
      activos: 0,
      capital_pen: 0,
      capital_usd: 0,
      convertidos: cierres,
      conversion_pct: Math.round(mensual.total.conversion_pct ?? 0),
      nucleo_convertidos: cierres,
      operaciones_cartera: operaciones,
      nucleo_divisor: mensual.total.divisor,
      nucleo_numerador: mensual.total.numerador,
      nucleo_conversion_pct: mensual.total.conversion_pct,
      parkeados: 0,
    }],
  })

  return {
    mensual,
    gestion: mapearMetricasVendedores(payload, [VENDEDOR], [SUPERVISOR, VENDEDOR]),
    ranking: adaptarConversionMensual(mensual, IDENTIDADES),
    cierres,
    operaciones,
  }
}

function montarHoy(mensual: ConversionMensual): ReturnType<typeof render> {
  return render(createElement(ResumenGerenciaPanel, {
    conversiones: metricasConversionesDemo('2026-08-01', '2026-08-15'),
    conversionMensual: mensual,
    reuniones: metricasReunionesDemo('2026-08-01', '2026-08-15'),
    equipo: IDENTIDADES,
    meta: OBJETIVOS_UI.gerencia,
    cumplimiento: null,
    metaMensual: { etiqueta: 'agosto 2026', comparable: true },
    tc: null,
    cargando: false,
    error: null,
    modoDemo: false,
    onReintentar: vi.fn(),
  }))
}

function montarMetas(mensual: ConversionMensual): ReturnType<typeof render> {
  YO_UI = YO_GERENCIA
  CONVERSION_UI = mensual
  return render(createElement(
    PeriodoGerenciaProvider,
    null,
    createElement(HoyGerencia, { seccion: 'metas' }),
  ))
}

function montarDirectorio(metricas: MetricasVendedoresOperativas): ReturnType<typeof render> {
  YO_UI = YO_DIRECTORIO
  METRICAS_UI = metricas
  return render(createElement(HoyDirectorio))
}

function valorPrincipalHoy(container: HTMLElement): HTMLElement {
  const hero = container.querySelector('[data-gi-hero]')
  if (!(hero instanceof HTMLElement)) throw new Error('HOY no renderizó su héroe')
  const rotulo = within(hero).getByText('Conversión del mes')
  const valor = rotulo.nextElementSibling
  if (!(valor instanceof HTMLElement)) throw new Error('HOY no renderizó el valor del héroe')
  return valor
}

function tarjetaMetas(): HTMLElement {
  const tarjeta = screen.getByText('Conversión de la empresa').closest('[data-gi-kpi]')
  if (!(tarjeta instanceof HTMLElement)) throw new Error('Metas no renderizó su tarjeta de conversión')
  return tarjeta
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(AHORA)
  const objetivos = objetivosCero('2026-08-01')
  OBJETIVOS_UI = {
    ...objetivos,
    gerencia: { ...objetivos.gerencia, conversionObjetivo: 50 },
  }
  CONVERSION_UI = null
  METRICAS_UI = null
  YO_UI = YO_GERENCIA
})

afterEach(() => {
  vi.useRealTimers()
})

describe('contrato offline de paridad — HOY/Ranking/Metas/Gestión/Directorio', () => {
  it('atraviesa los consumidores reales y conserva valor, precisión, cierres y cartera', () => {
    const foto = crearFotoCanonica()
    const esperado = '26.88%'

    const hoy = montarHoy(foto.mensual)
    expect(valorPrincipalHoy(hoy.container)).toHaveTextContent(esperado)
    hoy.unmount()

    expect(foto.ranking.vendedores[0]?.detalle?.conversion_pct).toBe(26.88)
    expect(foto.gestion.filas[0]).toMatchObject({
      conversion: 26.88,
      cierresConversion: foto.cierres,
      operacionesCartera: foto.operaciones,
      conversionDisponible: true,
    })

    const metas = montarMetas(foto.mensual)
    expect(tarjetaMetas()).toHaveTextContent(esperado)
    metas.unmount()

    const directorio = montarDirectorio(foto.gestion)
    const filaDirectorio = screen.getByRole('row', { name: /SUPERVISORA UNO/ })
    expect(filaDirectorio).toHaveTextContent(esperado)
    expect(filaDirectorio).not.toHaveTextContent('27%')
    directorio.unmount()

    expect([
      foto.ranking.vendedores[0]?.detalle?.conversion_pct ?? null,
      foto.gestion.filas[0]?.conversion ?? null,
      foto.gestion.equipos[0]?.conversion ?? null,
    ].map(porcentajeConversionCanonica)).toEqual(Array(3).fill(esperado))
  })

  it('propaga la revisión fail-closed por los tres consumidores reales y los dos adaptadores', () => {
    const foto = crearFotoCanonica(true)

    const hoy = montarHoy(foto.mensual)
    expect(valorPrincipalHoy(hoy.container)).toHaveTextContent('—')
    expect(valorPrincipalHoy(hoy.container)).not.toHaveTextContent('26.88%')
    hoy.unmount()

    expect(foto.ranking.vendedores[0]?.detalle?.conversion_pct ?? null).toBeNull()
    expect(foto.gestion.filas[0]).toMatchObject({
      conversion: null,
      cierresConversion: null,
      operacionesCartera: null,
      conversionDisponible: false,
    })

    const metas = montarMetas(foto.mensual)
    expect(tarjetaMetas()).toHaveTextContent('—')
    expect(tarjetaMetas()).not.toHaveTextContent('26.88%')
    metas.unmount()

    const directorio = montarDirectorio(foto.gestion)
    const filaDirectorio = screen.getByRole('row', { name: /SUPERVISORA UNO/ })
    expect(filaDirectorio).toHaveTextContent('Dato no disponible')
    expect(filaDirectorio).not.toHaveTextContent('26.88%')
    directorio.unmount()
  })
})
