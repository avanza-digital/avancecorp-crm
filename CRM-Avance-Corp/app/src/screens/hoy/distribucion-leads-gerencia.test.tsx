import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { hoyLimaIso, sumarDiasIso } from '@/lib/distribucion-lecturas'
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
    contactos_asignacion: 5,
    sla_asignacion_evaluables: 4,
    sla_asignacion_en_24h: 3,
    primer_contacto_asignacion_mediana_minutos: 90,
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
    contactos_asignacion: 0,
    sla_asignacion_evaluables: 0,
    sla_asignacion_en_24h: 0,
    primer_contacto_asignacion_mediana_minutos: null,
    transferidos: 0,
    parqueados: 0,
    desactivados: 0,
    sin_tocar_actual: 0,
    estancados_actual: 0,
  },
}

const DATOS: MetricasDistribucionLeads = {
  version: 2,
  generado_en: '2026-07-17T20:00:00Z',
  cohorte: {
    desde_inclusivo: '2026-04-19',
    hasta_inclusivo: '2026-07-17',
    hasta_exclusivo: '2026-07-18',
    criterio: 'episodio_asignado_en',
    criterio_sla_global: 'ciclo_sla_global_iniciado_en',
    politica_pausas: 'SIN_DESCUENTO',
    zona_horaria: 'America/Lima',
  },
  alcances: {
    matriz: 'PEN',
    capacidad: 'TODAS_LAS_MONEDAS',
    montos: 'SEPARADOS_SIN_CONVERSION',
    sla_principal: 'GLOBAL_POR_CICLO',
    sla_operativo: 'POR_EPISODIO_DE_ASIGNACION',
  },
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
    sla_global_ciclos_cohorte: 8,
    sla_global_leads_unicos_cohorte: 7,
    sla_global_contactos: 3,
    sla_global_evaluables: 6,
    sla_global_en_24h: 2,
    primer_contacto_global_mediana_minutos: 180,
    sla_global_sin_contacto_vencidos_actuales: 2,
    reasignaciones_cohorte: 1,
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
    ciclos_sla_global_aproximados_cohorte: 0,
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

function fichaDe(nombre: string): HTMLElement {
  return screen.getByRole('article', { name: `Ficha de ${nombre}` })
}

describe('DistribucionLeadsGerencia', () => {
  it('nivel 1: resumen en lenguaje natural con monedas separadas y avisos de atención', () => {
    montar()

    expect(screen.getByRole('heading', { name: 'Distribución de leads' })).toBeInTheDocument()

    const cierresPorMoneda = screen.getByRole('group', { name: 'Cierres de venta por moneda' })
    expect(within(cierresPorMoneda).getByText('Soles')).toBeInTheDocument()
    expect(within(cierresPorMoneda).getByText('75%')).toBeInTheDocument()
    expect(within(cierresPorMoneda).getByText('3 ventas de 4 leads resueltos')).toBeInTheDocument()
    expect(within(cierresPorMoneda).getByText('Dólares')).toBeInTheDocument()
    expect(within(cierresPorMoneda).getByText('50%')).toBeInTheDocument()
    expect(within(cierresPorMoneda).getByText('1 venta de 2 leads resueltos')).toBeInTheDocument()

    expect(screen.getByText(/2 de 6 leads atendidos a tiempo/)).toBeInTheDocument()
    expect(screen.getByText(/lo habitual: 3 h/)).toBeInTheDocument()

    expect(screen.getByRole('heading', { name: 'Lo que merece tu atención' })).toBeInTheDocument()
    expect(
      screen.getByText('2 leads llevan más de 24 horas sin primera atención.'),
    ).toBeInTheDocument()
    expect(
      screen.getByText('1 lead sin responsable espera directamente a Gerencia.'),
    ).toBeInTheDocument()
    expect(screen.getByText('La bandeja de César Ruiz tiene 1 lead por asignar.')).toBeInTheDocument()
    expect(screen.getByText('Ana Torres tiene 1 lead sin atender.')).toBeInTheDocument()
    expect(
      screen.getByText('2 leads están sin avance según los plazos de su etapa.'),
    ).toBeInTheDocument()
  })

  it('nivel 2: tarjetas por analista con cartera, resultados y quien no recibe al final', () => {
    montar()

    const ana = fichaDe('Ana Torres')
    expect(ana).toHaveTextContent('5 de 20 leads')
    expect(ana).toHaveTextContent('15 cupos libres')
    expect(ana).toHaveTextContent('Recibió 9 leads en el período')
    expect(ana).toHaveTextContent('Cierra el 75% de lo que resuelve en soles (3 de 4)')
    expect(ana).toHaveTextContent('en dólares: 50% (1 de 2)')
    expect(ana).toHaveTextContent('24 h: 75% (3 de 4)')
    expect(ana).toHaveTextContent('1 sin atender')
    expect(ana).toHaveTextContent('2 sin avance')
    expect(ana).toHaveTextContent('S/ 12,000 en soles · US$ 8,000 en dólares')
    expect(ana).toHaveTextContent('Salidas del período: 1 transferido · 0 parqueados')

    const bruno = fichaDe('Bruno Díaz')
    expect(bruno).toHaveTextContent('No recibe por ahora')
    expect(bruno).toHaveTextContent('sin límite definido')
    expect(bruno).toHaveTextContent('Aún sin ventas ni descartes en soles')
    expect(bruno).toHaveTextContent('24 h: aún sin medición')

    // Orden por cupos: quien no recibe va al final, con el criterio declarado.
    const fichas = screen.getAllByRole('article', { name: /^Ficha de/ })
    expect(fichas.map((ficha) => ficha.getAttribute('aria-label'))).toEqual([
      'Ficha de Ana Torres',
      'Ficha de Bruno Díaz',
    ])
    expect(screen.getByText(/quien no recibe leads va al final/i)).toBeInTheDocument()
    expect(screen.getByLabelText('Ordenar por')).toBeInTheDocument()
  })

  it('período: los atajos piden la cohorte de un clic y el personalizado valida fechas', async () => {
    const user = userEvent.setup()
    const onCambiarPeriodo = vi.fn()
    montar({ onCambiarPeriodo })

    const hoy = hoyLimaIso()
    await user.click(screen.getByRole('button', { name: 'Últimos 90 días' }))
    expect(onCambiarPeriodo).toHaveBeenCalledWith(sumarDiasIso(hoy, -89), hoy)

    // Las fechas del fixture no calzan con ningún atajo: el formulario está a mano.
    await user.clear(screen.getByLabelText('Desde'))
    await user.type(screen.getByLabelText('Desde'), '2026-07-18')
    await user.click(screen.getByRole('button', { name: 'Aplicar' }))
    expect(screen.getByRole('alert')).toHaveTextContent('La fecha Desde no puede ser posterior')
    expect(onCambiarPeriodo).toHaveBeenCalledTimes(1)

    await user.clear(screen.getByLabelText('Desde'))
    await user.type(screen.getByLabelText('Desde'), '2026-07-01')
    await user.click(screen.getByRole('button', { name: 'Aplicar' }))
    expect(onCambiarPeriodo).toHaveBeenCalledWith('2026-07-01', '2026-07-17')
  })

  it('edita el límite de cartera desde la tarjeta, solo para quien puede recibir', async () => {
    const user = userEvent.setup()
    const onEditarCapacidad = vi.fn().mockResolvedValue(undefined)
    montar({ onEditarCapacidad })

    expect(
      screen.queryByRole('button', { name: 'Editar límite de cartera de Bruno Díaz' }),
    ).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Editar límite de cartera de Ana Torres' }))

    const input = screen.getByLabelText('Límite de cartera para Ana Torres')
    await user.clear(input)
    await user.type(input, '24')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    await waitFor(() => expect(onEditarCapacidad).toHaveBeenCalledWith('ana-id', 24))
    expect(screen.queryByLabelText('Límite de cartera para Ana Torres')).not.toBeInTheDocument()
  })

  it('rechaza una capacidad fuera del contrato y permite quitar el límite con vacío', async () => {
    const user = userEvent.setup()
    const onEditarCapacidad = vi.fn().mockResolvedValue(undefined)
    montar({ onEditarCapacidad })

    await user.click(screen.getByRole('button', { name: 'Editar límite de cartera de Ana Torres' }))
    const input = screen.getByLabelText('Límite de cartera para Ana Torres')
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

    await user.click(screen.getByRole('button', { name: 'Editar límite de cartera de Ana Torres' }))
    const input = screen.getByLabelText('Límite de cartera para Ana Torres')
    await user.clear(input)
    await user.type(input, '24')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'No se pudo guardar el límite de cartera. Inténtalo otra vez.',
    )
    expect(screen.queryByText(/Failed to fetch/)).not.toBeInTheDocument()
  })

  it('asistente de reparto: candidatos con espacio por monto elegido y dólares sin rangos', async () => {
    const user = userEvent.setup()
    montar()

    const asistente = screen
      .getByRole('heading', { name: '¿Vas a repartir un lead?' })
      .closest('section')
    if (!asistente) throw new Error('No se encontró la sección del asistente')

    // Rango inicial: "Hasta S/ 1 mil" — Ana cierra 1 de 2 y tiene 2 activos allí.
    expect(within(asistente).getByText('Ana Torres')).toBeInTheDocument()
    expect(within(asistente).getByText(/15 cupos libres/)).toBeInTheDocument()
    expect(
      within(asistente).getByText(/Cierra el 50% con este monto \(1 de 2\)/),
    ).toBeInTheDocument()
    expect(within(asistente).getByText(/hoy tiene 2 con este monto/)).toBeInTheDocument()
    // Bruno no recibe: no compite, se informa aparte.
    expect(within(asistente).queryByText('Bruno Díaz')).not.toBeInTheDocument()
    expect(
      within(asistente).getByText(/1 analista no recibe leads por ahora/),
    ).toBeInTheDocument()

    // Otro rango sin historia: honestidad sin porcentajes inventados.
    await user.selectOptions(within(asistente).getByLabelText('Monto del lead'), 'pen_mas_100000')
    expect(within(asistente).getByText(/Sin resultados con este monto aún/)).toBeInTheDocument()

    // Dólares: sin selector de rango y con su propia lectura.
    await user.selectOptions(within(asistente).getByLabelText('Moneda'), 'USD')
    expect(within(asistente).queryByLabelText('Monto del lead')).not.toBeInTheDocument()
    expect(within(asistente).getByText(/aún no tienen rangos aprobados/)).toBeInTheDocument()
    expect(within(asistente).getByText(/Cierra el 50% en dólares \(1 de 2\)/)).toBeInTheDocument()
  })

  it('tabla por rangos bajo demanda: cartera y recibidos juntos, y conversión por monto', async () => {
    const user = userEvent.setup()
    montar()

    expect(
      screen.queryByRole('region', { name: 'Analistas por rango de monto en soles' }),
    ).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Ver tabla completa por rangos' }))

    const region = screen.getByRole('region', { name: 'Analistas por rango de monto en soles' })
    const tablaCarga = within(region).getByRole('table', { name: /carga actual por analista/i })
    for (const [, etiqueta] of RANGOS.slice(0, 7)) {
      expect(
        within(tablaCarga).getByRole('columnheader', { name: new RegExp(etiqueta, 'i') }),
      ).toBeInTheDocument()
    }
    expect(within(tablaCarga).getByTitle(/2 leads activos · S\/\s?1[,.]800/)).toBeInTheDocument()
    const filaAna = within(tablaCarga).getByRole('row', { name: /Ana Torres/ })
    expect(filaAna).toHaveTextContent('recibió 3')

    await user.click(screen.getByRole('button', { name: 'Conversión por monto' }))
    const tablaConversion = within(region).getByRole('table', {
      name: /conversión por analista/i,
    })
    const filaConversion = within(tablaConversion).getByRole('row', { name: /Ana Torres/ })
    expect(within(filaConversion).getByText('1 de 2')).toBeInTheDocument()
    const filaBruno = within(tablaConversion).getByRole('row', { name: /Bruno Díaz/ })
    expect(within(filaBruno).getAllByText('Sin casos')).toHaveLength(7)
  })

  it('separa colas de Gerencia y bandejas, y solo revela sin monto como calidad', () => {
    const datosConCalidad: MetricasDistribucionLeads = {
      ...DATOS,
      calidad: { ...DATOS.calidad, episodios_sin_monto_cohorte: 1 },
    }
    montar({ datos: datosConCalidad })

    expect(screen.getByRole('article', { name: 'Pendientes de Gerencia' })).toBeInTheDocument()
    expect(screen.getByRole('article', { name: 'Pendientes de César Ruiz' })).toBeInTheDocument()
    expect(screen.getByText('Aviso sobre los datos')).toBeInTheDocument()
    expect(screen.getByText(/1 registro no tiene monto/)).toBeInTheDocument()
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
    expect(screen.getByText('No hay datos para mostrar')).toBeInTheDocument()

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

  it('en demo etiqueta los datos como ficticios', () => {
    montar({ modoDemo: true })
    expect(screen.getByText('Datos ficticios de demostración')).toBeInTheDocument()
    expect(
      screen.getByText(/No representan información real de la empresa/),
    ).toBeInTheDocument()
  })
})

describe('DistribucionLeadsGerencia con equipos grandes (2 supervisores × 9 analistas)', () => {
  function analistaGrande(
    indice: number,
    supervisor: { id: string; nombre: string },
  ): AnalistaDistribucionLeads {
    return {
      ...ANA,
      analista_id: `analista-${String(indice).padStart(2, '0')}`,
      nombre: `Vendedor ${String(indice).padStart(2, '0')}`,
      supervisor_id: supervisor.id,
      supervisor_nombre: supervisor.nombre,
      capacidad: {
        objetivo: 10,
        carga_activa: indice % 10,
        carga_pen: indice % 10,
        carga_usd: 0,
      },
    }
  }

  const DATOS_GRANDES: MetricasDistribucionLeads = {
    ...DATOS,
    analistas: [
      ...Array.from({ length: 9 }, (_, i) =>
        analistaGrande(i + 1, { id: 'sup-1', nombre: 'Sofía Uno' })),
      ...Array.from({ length: 9 }, (_, i) =>
        analistaGrande(i + 10, { id: 'sup-2', nombre: 'Marco Dos' })),
    ],
  }

  it('presenta tarjetas de equipo con agregados y recorta el primer vistazo a 6 analistas', async () => {
    const user = userEvent.setup()
    montar({ datos: DATOS_GRANDES })

    const filtro = screen.getByRole('group', { name: 'Filtrar por equipo' })
    const todos = within(filtro).getByRole('button', { name: /Todos los equipos/ })
    expect(todos).toHaveAttribute('aria-pressed', 'true')
    expect(todos).toHaveTextContent('18 analistas')
    const sofia = within(filtro).getByRole('button', { name: /Equipo de Sofía Uno/ })
    expect(sofia).toHaveTextContent('9 analistas')
    expect(sofia).toHaveTextContent('45 de 90 leads · 45 cupos libres')

    expect(screen.getAllByRole('article', { name: /^Ficha de/ })).toHaveLength(6)
    await user.click(screen.getByRole('button', { name: 'Mostrar los 12 analistas restantes' }))
    expect(screen.getAllByRole('article', { name: /^Ficha de/ })).toHaveLength(18)
    expect(screen.getByRole('button', { name: 'Mostrar menos' })).toBeInTheDocument()
  })

  it('al filtrar por un equipo muestra sus 6 primeros y expande los 3 restantes', async () => {
    const user = userEvent.setup()
    montar({ datos: DATOS_GRANDES })

    await user.click(screen.getByRole('button', { name: /Equipo de Sofía Uno/ }))
    expect(screen.getAllByRole('article', { name: /^Ficha de/ })).toHaveLength(6)
    await user.click(screen.getByRole('button', { name: 'Mostrar los 3 analistas restantes' }))
    expect(screen.getAllByRole('article', { name: /^Ficha de/ })).toHaveLength(9)
  })

  it('el asistente lista 5 candidatos y expande el resto bajo demanda', async () => {
    const user = userEvent.setup()
    montar({ datos: DATOS_GRANDES })

    const asistente = screen
      .getByRole('heading', { name: '¿Vas a repartir un lead?' })
      .closest('section')
    if (!asistente) throw new Error('No se encontró la sección del asistente')

    expect(within(asistente).getAllByRole('listitem')).toHaveLength(5)
    await user.click(
      within(asistente).getByRole('button', { name: 'Ver los 13 candidatos restantes' }),
    )
    expect(within(asistente).getAllByRole('listitem')).toHaveLength(18)
    expect(within(asistente).getByRole('button', { name: 'Ver menos' })).toBeInTheDocument()
  })
})
