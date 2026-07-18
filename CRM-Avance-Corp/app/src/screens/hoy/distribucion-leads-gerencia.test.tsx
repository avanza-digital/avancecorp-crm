import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {
  DistribucionLeadsGerencia,
  type AnalistaDistribucionLeads,
  type DistribucionLeadsGerenciaProps,
  type MetricasDistribucionLeads,
  type RangoAnalistaDistribucion,
  type RangoColaDistribucion,
} from './distribucion-leads-gerencia'

const RANGOS = [
  ['pen_0_1000', 'Hasta S/ 1 mil', 0, 1000],
  ['pen_1000_5000', 'S/ 1 mil a 5 mil', 1000, 5000],
  ['pen_5000_10000', 'S/ 5 mil a 10 mil', 5000, 10000],
  ['pen_10000_20000', 'S/ 10 mil a 20 mil', 10000, 20000],
  ['pen_20000_50000', 'S/ 20 mil a 50 mil', 20000, 50000],
  ['pen_50000_100000', 'S/ 50 mil a 100 mil', 50000, 100000],
  ['pen_mas_100000', 'Más de S/ 100 mil', 100000, null],
  ['sin_monto', 'Sin monto válido', null, null],
] as const

function rangosAnalista(
  destacados: Record<
    string,
    {
      cartera: number
      capital: number
      c: number
      d: number
      recibidos?: number
      leadsUnicos?: number
    }
  > = {},
): RangoAnalistaDistribucion[] {
  return RANGOS.map(([rangoId]) => {
    const dato = destacados[rangoId] ?? { cartera: 0, capital: 0, c: 0, d: 0 }
    return {
      rango_id: rangoId,
      cartera_actual: { episodios: dato.cartera, capital: dato.capital },
      cohorte: {
        episodios_recibidos: dato.recibidos ?? dato.c + dato.d,
        leads_unicos_recibidos: dato.leadsUnicos ?? dato.recibidos ?? dato.c + dato.d,
        convertidos: dato.c,
        descartados: dato.d,
        leads_unicos_resueltos: dato.c + dato.d,
      },
    }
  })
}

function rangosCola(
  destacados: Record<string, { cantidad: number; capital: number }> = {},
): RangoColaDistribucion[] {
  return RANGOS.map(([rangoId]) => ({
    rango_id: rangoId,
    cantidad: destacados[rangoId]?.cantidad ?? 0,
    capital: destacados[rangoId]?.capital ?? 0,
  }))
}

const ANA: AnalistaDistribucionLeads = {
  analista_id: 'ana-id',
  nombre: 'Ana Torres',
  rol: 'vendedor',
  supervisor_id: 'supervisor-id',
  supervisor_nombre: 'César Ruiz',
  activo: true,
  disponible_para_recibir: true,
  capacidad: { objetivo: 20, carga_activa: 5, carga_pen: 4, carga_usd: 1 },
  pen: {
    cartera_actual: { episodios: 4, capital: 12_000 },
    cohorte: {
      episodios_recibidos: 7,
      leads_unicos_recibidos: 7,
      convertidos: 3,
      descartados: 1,
      ciclos_resueltos: 4,
      leads_unicos_resueltos: 4,
    },
    rangos: rangosAnalista({
      pen_0_1000: { cartera: 2, capital: 1800, c: 1, d: 1, recibidos: 3 },
      pen_1000_5000: { cartera: 2, capital: 9000, c: 2, d: 0 },
      pen_5000_10000: { cartera: 0, capital: 0, c: 0, d: 0, recibidos: 2 },
    }),
  },
  usd_no_segmentado: {
    cartera_actual_episodios: 1,
    cartera_actual_capital: 8000,
    cohorte_episodios_recibidos: 2,
    cohorte_leads_unicos: 2,
    convertidos: 1,
    descartados: 1,
  },
  operacion: {
    cohorte_episodios: 7,
    contactos: 5,
    sla_evaluables: 4,
    sla_en_24h: 3,
    primer_contacto_mediana_minutos: 90,
    transferidos: 1,
    parqueados: 0,
    desactivados: 0,
    sin_tocar_actual: 1,
    estancados_actual: 2,
  },
}

const BRUNO: AnalistaDistribucionLeads = {
  ...ANA,
  analista_id: 'bruno-id',
  nombre: 'Bruno Díaz',
  disponible_para_recibir: false,
  capacidad: { objetivo: null, carga_activa: 0, carga_pen: 0, carga_usd: 0 },
  pen: {
    cartera_actual: { episodios: 0, capital: 0 },
    cohorte: {
      episodios_recibidos: 0,
      leads_unicos_recibidos: 0,
      convertidos: 0,
      descartados: 0,
      ciclos_resueltos: 0,
      leads_unicos_resueltos: 0,
    },
    rangos: rangosAnalista(),
  },
  usd_no_segmentado: {
    cartera_actual_episodios: 0,
    cartera_actual_capital: 0,
    cohorte_episodios_recibidos: 0,
    cohorte_leads_unicos: 0,
    convertidos: 0,
    descartados: 0,
  },
  operacion: {
    cohorte_episodios: 0,
    contactos: 0,
    sla_evaluables: 0,
    sla_en_24h: 0,
    primer_contacto_mediana_minutos: null,
    transferidos: 0,
    parqueados: 0,
    desactivados: 0,
    sin_tocar_actual: 0,
    estancados_actual: 0,
  },
}

const DATOS: MetricasDistribucionLeads = {
  version: 1,
  generado_en: '2026-07-17T20:00:00Z',
  cohorte: {
    desde_inclusivo: '2026-04-19',
    hasta_inclusivo: '2026-07-17',
    hasta_exclusivo: '2026-07-18',
    criterio: 'episodio_asignado_en',
    zona_horaria: 'America/Lima',
  },
  alcances: { matriz: 'PEN', capacidad: 'TODAS_LAS_MONEDAS', operacion_sla: 'TODAS_LAS_MONEDAS' },
  rangos: RANGOS.map(([id, etiqueta, desdeExclusivo, hastaInclusivo], indice) => ({
    id,
    orden: indice + 1,
    etiqueta,
    desde_exclusivo: desdeExclusivo,
    hasta_inclusivo: hastaInclusivo,
  })),
  resumen: {
    leads_operativos_actuales: 8,
    asignados_actuales: 5,
    por_repartir_actuales: 2,
    capital_pen_asignado_actual: 12_000,
    capital_usd_asignado_actual: 8000,
    cohorte_episodios: 7,
    cohorte_leads_unicos: 7,
    convertidos_pen: 3,
    descartados_pen: 1,
    sla_evaluables: 4,
    sla_en_24h: 3,
  },
  analistas: [ANA, BRUNO],
  por_repartir: {
    total: {
      carga_total: 2,
      pen: {
        cantidad: 2,
        capital: 6000,
        rangos: rangosCola({
          pen_0_1000: { cantidad: 1, capital: 1000 },
          pen_1000_5000: { cantidad: 1, capital: 5000 },
        }),
      },
      usd: { cantidad: 0, capital: 0 },
    },
    global: {
      responsabilidad: 'gerencia',
      carga_total: 1,
      pen: {
        cantidad: 1,
        capital: 1000,
        rangos: rangosCola({ pen_0_1000: { cantidad: 1, capital: 1000 } }),
      },
      usd: { cantidad: 0, capital: 0 },
    },
    bandejas: [
      {
        supervisor_id: 'supervisor-id',
        supervisor_nombre: 'César Ruiz',
        supervisor_activo: true,
        carga_total: 1,
        pen: {
          cantidad: 1,
          capital: 5000,
          rangos: rangosCola({ pen_1000_5000: { cantidad: 1, capital: 5000 } }),
        },
        usd: { cantidad: 0, capital: 0 },
      },
    ],
  },
  calidad: {
    episodios_aproximados_actuales: 0,
    episodios_aproximados_cohorte: 0,
    episodios_sin_monto_actuales: 0,
    episodios_sin_monto_cohorte: 0,
  },
}

const BASE_PROPS: DistribucionLeadsGerenciaProps = {
  datos: DATOS,
  cargando: false,
  error: null,
  desde: '2026-04-19',
  hasta: '2026-07-17',
  onCambiarPeriodo: vi.fn(),
  onReintentar: vi.fn(),
  onEditarCapacidad: vi.fn(),
}

function montar(cambios: Partial<DistribucionLeadsGerenciaProps> = {}) {
  const props = { ...BASE_PROPS, ...cambios }
  return { ...render(<DistribucionLeadsGerencia {...props} />), props }
}

describe('DistribucionLeadsGerencia', () => {
  it('muestra las 7 bandas PEN con recibidos, cartera, evidencia C/D y muestra explícita', () => {
    montar()

    const matriz = screen.getByRole('table', { name: /distribución PEN por analista/i })
    expect(within(matriz).getAllByText(/BANDA 0[1-7]/)).toHaveLength(7)

    const filaAna = within(matriz).getByRole('row', { name: /Ana Torres/ })
    expect(
      within(filaAna).getByLabelText(
        'Ana Torres, Hasta S/ 1 mil: 3 episodios recibidos, 3 leads únicos; 2 en cartera actual; 1 convertidos; 1 descartados; conversión 50%',
      ),
    ).toBeInTheDocument()
    expect(
      within(filaAna).getByLabelText(
        'Ana Torres, S/ 5 mil a 10 mil: 2 episodios recibidos, 2 leads únicos; 0 en cartera actual; 0 convertidos; 0 descartados; conversión sin muestra',
      ),
    ).toBeInTheDocument()
    expect(within(filaAna).getAllByText('75%')).toHaveLength(2)
    expect(within(filaAna).getByText('1 sin tocar')).toBeInTheDocument()
    expect(within(filaAna).getByText('2 estancados')).toBeInTheDocument()
    expect(within(filaAna).getByText('7 episodios · 7 leads recibidos')).toBeInTheDocument()
    expect(within(filaAna).getByText('4 ciclos · 4 leads resueltos')).toBeInTheDocument()
    expect(within(filaAna).getByText(/Salidas 14[,.]3% · 1\/7/)).toBeInTheDocument()
    expect(within(matriz).getAllByText('Total PEN + USD')).toHaveLength(2)

    const filaBruno = within(matriz).getByRole('row', { name: /Bruno Díaz/ })
    // Siete bandas + conversión total + SLA: ningún vacío se presenta como 0%.
    expect(within(filaBruno).getAllByText('Sin muestra')).toHaveLength(9)
    expect(within(filaBruno).getByText('C 0 · D 0')).toBeInTheDocument()
  })

  it('valida el período antes de pedir una nueva cohorte', async () => {
    const user = userEvent.setup()
    const onCambiarPeriodo = vi.fn()
    montar({ onCambiarPeriodo })

    await user.clear(screen.getByLabelText('Desde'))
    await user.type(screen.getByLabelText('Desde'), '2026-07-18')
    await user.click(screen.getByRole('button', { name: 'Aplicar' }))

    expect(screen.getByRole('alert')).toHaveTextContent('La fecha Desde no puede ser posterior')
    expect(onCambiarPeriodo).not.toHaveBeenCalled()

    await user.clear(screen.getByLabelText('Desde'))
    await user.type(screen.getByLabelText('Desde'), '2026-07-01')
    await user.click(screen.getByRole('button', { name: 'Aplicar' }))

    expect(onCambiarPeriodo).toHaveBeenCalledWith('2026-07-01', '2026-07-17')
  })

  it('edita capacidad inline solo para quien puede recibir leads', async () => {
    const user = userEvent.setup()
    const onEditarCapacidad = vi.fn().mockResolvedValue(undefined)
    montar({ onEditarCapacidad })

    expect(
      screen.queryByRole('button', { name: 'Editar capacidad de Bruno Díaz' }),
    ).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Editar capacidad de Ana Torres' }))

    const input = screen.getByLabelText('Capacidad objetivo para Ana Torres')
    await user.clear(input)
    await user.type(input, '24')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    await waitFor(() => expect(onEditarCapacidad).toHaveBeenCalledWith('ana-id', 24))
    expect(screen.queryByLabelText('Capacidad objetivo para Ana Torres')).not.toBeInTheDocument()
  })

  it('rechaza una capacidad fuera del contrato y permite quitar el objetivo con vacío', async () => {
    const user = userEvent.setup()
    const onEditarCapacidad = vi.fn().mockResolvedValue(undefined)
    montar({ onEditarCapacidad })

    await user.click(screen.getByRole('button', { name: 'Editar capacidad de Ana Torres' }))
    const input = screen.getByLabelText('Capacidad objetivo para Ana Torres')
    await user.clear(input)
    await user.type(input, '1001')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    expect(screen.getByRole('alert')).toHaveTextContent('entero entre 1 y 1000')
    expect(onEditarCapacidad).not.toHaveBeenCalled()

    await user.clear(input)
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(onEditarCapacidad).toHaveBeenCalledWith('ana-id', null))
  })

  it('muestra un error seguro si falla la actualización de capacidad', async () => {
    const user = userEvent.setup()
    const onEditarCapacidad = vi.fn().mockRejectedValue(new Error('Failed to fetch: detalle técnico'))
    montar({ onEditarCapacidad })

    await user.click(screen.getByRole('button', { name: 'Editar capacidad de Ana Torres' }))
    const input = screen.getByLabelText('Capacidad objetivo para Ana Torres')
    await user.clear(input)
    await user.type(input, '24')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'No se pudo guardar la capacidad. Inténtalo otra vez.',
    )
    expect(screen.queryByText(/Failed to fetch/)).not.toBeInTheDocument()
  })

  it('separa USD, muestra las dos clases de cola y solo revela sin monto como calidad', () => {
    const datosConCalidad: MetricasDistribucionLeads = {
      ...DATOS,
      calidad: { ...DATOS.calidad, episodios_sin_monto_cohorte: 1 },
    }
    montar({ datos: datosConCalidad })

    expect(screen.getByRole('heading', { name: 'USD · lectura separada' })).toBeInTheDocument()
    expect(screen.getByRole('article', { name: 'Cola global' })).toBeInTheDocument()
    expect(screen.getByRole('article', { name: 'Bandeja de César Ruiz' })).toBeInTheDocument()
    expect(screen.getByText('Calidad del historial')).toBeInTheDocument()
    expect(screen.getByText(/1 de la cohorte están sin monto válido/)).toBeInTheDocument()
  })

  it('cubre carga, fallo y ausencia honesta de respuesta sin asumir un arreglo', async () => {
    const user = userEvent.setup()
    const onReintentar = vi.fn()
    const { rerender } = montar({ datos: undefined, cargando: true, onReintentar })

    expect(screen.getByRole('status')).toHaveTextContent('Cargando distribución de leads')

    rerender(
      <DistribucionLeadsGerencia
        {...BASE_PROPS}
        datos={undefined}
        cargando={false}
        error={null}
        onReintentar={onReintentar}
      />,
    )
    expect(screen.getByText('Aún no hay una fotografía de distribución')).toBeInTheDocument()

    rerender(
      <DistribucionLeadsGerencia
        {...BASE_PROPS}
        datos={undefined}
        cargando={false}
        error="La consulta no respondió."
        onReintentar={onReintentar}
      />,
    )
    await user.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(onReintentar).toHaveBeenCalledTimes(1)
  })
})
