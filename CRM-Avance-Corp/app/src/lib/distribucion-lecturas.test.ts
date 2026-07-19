import { describe, expect, it } from 'vitest'
import type {
  MetricaDistribucionAnalista,
  MetricasDistribucionLeads,
  RangoDistribucionAnalista,
} from './metricas-distribucion'
import { RANGOS_CAPITAL_PEN } from './metricas-distribucion'
import {
  avisosAtencion,
  candidatosReparto,
  equiposDistribucion,
  fichaAnalista,
  idEquipoDeAnalista,
  ordenarFichas,
  porcentajeLegible,
  presetsPeriodo,
  resumenEquipo,
  sumarDiasIso,
  textoMinutos,
} from './distribucion-lecturas'

function rangosVacios(): RangoDistribucionAnalista[] {
  return RANGOS_CAPITAL_PEN.map((rangoId) => ({
    rango_id: rangoId,
    cartera_actual: { episodios: 0, capital: 0 },
    cohorte: {
      episodios_recibidos: 0,
      leads_unicos_recibidos: 0,
      convertidos: 0,
      descartados: 0,
      leads_unicos_resueltos: 0,
    },
  }))
}

let contadorIds = 0

function analista(
  cambios: Partial<Omit<MetricaDistribucionAnalista, 'capacidad' | 'operacion'>> & {
    capacidad?: Partial<MetricaDistribucionAnalista['capacidad']>
    operacion?: Partial<MetricaDistribucionAnalista['operacion']>
  } = {},
): MetricaDistribucionAnalista {
  contadorIds += 1
  const { capacidad, operacion, ...resto } = cambios
  return {
    analista_id: `00000000-0000-4000-8000-${String(contadorIds).padStart(12, '0')}`,
    nombre: `Analista ${contadorIds}`,
    rol: 'vendedor',
    supervisor_id: null,
    supervisor_nombre: null,
    activo: true,
    disponible_para_recibir: true,
    capacidad: { objetivo: null, carga_activa: 0, carga_pen: 0, carga_usd: 0, ...capacidad },
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
      rangos: rangosVacios(),
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
      ...operacion,
    },
    ...resto,
  }
}

function colaVacia() {
  return {
    cantidad: 0,
    capital: 0,
    rangos: RANGOS_CAPITAL_PEN.map((rangoId) => ({ rango_id: rangoId, cantidad: 0, capital: 0 })),
  }
}

function datos(cambios: {
  analistas?: MetricaDistribucionAnalista[]
  vencidos?: number
  colaAltos?: { cantidad: number; capital: number }
  colaGerencia?: number
  bandejas?: Array<{ id: string; nombre: string; activo?: boolean; carga: number }>
} = {}): MetricasDistribucionLeads {
  const penTotal = colaVacia()
  if (cambios.colaAltos) {
    const alto = penTotal.rangos.find((rango) => rango.rango_id === 'pen_mas_100000')
    if (alto) {
      alto.cantidad = cambios.colaAltos.cantidad
      alto.capital = cambios.colaAltos.capital
    }
    penTotal.cantidad += cambios.colaAltos.cantidad
    penTotal.capital += cambios.colaAltos.capital
  }
  return {
    version: 2,
    generado_en: '2026-07-19T12:00:00Z',
    cohorte: {
      desde_inclusivo: '2026-04-20',
      hasta_inclusivo: '2026-07-18',
      hasta_exclusivo: '2026-07-19',
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
    rangos: RANGOS_CAPITAL_PEN.map((id, indice) => ({
      id,
      orden: indice + 1,
      etiqueta: id,
      desde_exclusivo: null,
      hasta_inclusivo: null,
    })),
    resumen: {
      leads_operativos_actuales: 0,
      asignados_actuales: 0,
      por_repartir_actuales: 0,
      capital_pen_asignado_actual: 0,
      capital_usd_asignado_actual: 0,
      cohorte_episodios: 0,
      cohorte_leads_unicos: 0,
      convertidos_pen: 0,
      descartados_pen: 0,
      sla_global_ciclos_cohorte: 0,
      sla_global_leads_unicos_cohorte: 0,
      sla_global_contactos: 0,
      sla_global_evaluables: 0,
      sla_global_en_24h: 0,
      primer_contacto_global_mediana_minutos: null,
      sla_global_sin_contacto_vencidos_actuales: cambios.vencidos ?? 0,
      reasignaciones_cohorte: 0,
    },
    analistas: cambios.analistas ?? [],
    por_repartir: {
      total: { carga_total: penTotal.cantidad, pen: penTotal, usd: { cantidad: 0, capital: 0 } },
      global: {
        responsabilidad: 'gerencia',
        carga_total: cambios.colaGerencia ?? 0,
        pen: colaVacia(),
        usd: { cantidad: 0, capital: 0 },
      },
      bandejas: (cambios.bandejas ?? []).map((bandeja) => ({
        supervisor_id: bandeja.id,
        supervisor_nombre: bandeja.nombre,
        supervisor_activo: bandeja.activo ?? true,
        carga_total: bandeja.carga,
        pen: colaVacia(),
        usd: { cantidad: 0, capital: 0 },
      })),
    },
    calidad: {
      episodios_aproximados_actuales: 0,
      episodios_aproximados_cohorte: 0,
      episodios_sin_monto_actuales: 0,
      episodios_sin_monto_cohorte: 0,
      ciclos_sla_global_aproximados_cohorte: 0,
    },
  }
}

describe('porcentajeLegible y textoMinutos', () => {
  it('no inventa un 0% sin denominador y formatea minutos por magnitud', () => {
    expect(porcentajeLegible(3, 0)).toBeNull()
    expect(porcentajeLegible(1, 4)).toBe('25%')
    expect(textoMinutos(null)).toBeNull()
    expect(textoMinutos(45)).toBe('45 min')
    expect(textoMinutos(90)).toBe('1.5 h')
    expect(textoMinutos(2880)).toBe('2 d')
  })
})

describe('presetsPeriodo', () => {
  it('calcula atajos inclusivos que terminan hoy en Lima', () => {
    const presets = presetsPeriodo('2026-07-19')
    expect(presets.map((preset) => preset.id)).toEqual([
      'este_mes',
      'ult_30',
      'ult_90',
      'este_anio',
    ])
    expect(presets[0]).toMatchObject({ desde: '2026-07-01', hasta: '2026-07-19' })
    expect(presets[1]).toMatchObject({ desde: '2026-06-20', hasta: '2026-07-19' })
    expect(presets[2]).toMatchObject({ desde: '2026-04-21', hasta: '2026-07-19' })
    expect(presets[3]).toMatchObject({ desde: '2026-01-01', hasta: '2026-07-19' })
  })

  it('cruza meses y años sin desbordar', () => {
    expect(sumarDiasIso('2026-01-01', -1)).toBe('2025-12-31')
    const presets = presetsPeriodo('2026-01-05')
    expect(presets[1]?.desde).toBe('2025-12-07')
  })
})

describe('avisosAtencion', () => {
  it('devuelve vacío cuando no hay nada pendiente', () => {
    expect(avisosAtencion(datos({ analistas: [analista()] }))).toEqual([])
  })

  it('pone lo crítico primero: vencidos de 24 h y montos altos sin asignar', () => {
    const avisos = avisosAtencion(
      datos({
        vencidos: 3,
        colaAltos: { cantidad: 2, capital: 250_000 },
        colaGerencia: 1,
        analistas: [analista({ operacion: { estancados_actual: 2 } })],
      }),
    )
    expect(avisos.map((aviso) => aviso.severidad)).toEqual(['critica', 'critica', 'media', 'media'])
    expect(avisos[0]?.texto).toBe('3 leads llevan más de 24 horas sin primera atención.')
    expect(avisos[1]?.texto).toBe('2 leads de más de S/ 50 mil esperan asignación.')
    expect(avisos[2]?.texto).toBe('1 lead sin responsable espera directamente a Gerencia.')
    expect(avisos[3]?.texto).toBe('2 leads están sin avance según los plazos de su etapa.')
  })

  it('nombra bandejas con pendientes, carteras llenas y al mayor caso sin atender', () => {
    const llena = analista({
      nombre: 'Karla Mendoza',
      capacidad: { objetivo: 15, carga_activa: 15 },
    })
    const conSinTocar = analista({
      nombre: 'Renzo Quispe',
      operacion: { sin_tocar_actual: 6 },
    })
    const otroSinTocar = analista({
      nombre: 'Ana Torres',
      operacion: { sin_tocar_actual: 2 },
    })
    const avisos = avisosAtencion(
      datos({
        analistas: [llena, conSinTocar, otroSinTocar],
        bandejas: [{ id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', nombre: 'César Ruiz', carga: 4 }],
      }),
    )
    expect(avisos.map((aviso) => aviso.texto)).toEqual([
      'La bandeja de César Ruiz tiene 4 leads por asignar.',
      'Karla Mendoza está al tope de su cartera (15 de 15).',
      '8 leads sin atender; el caso mayor es Renzo Quispe con 6.',
    ])
  })

  it('un analista pausado lleno no genera aviso de tope (no recibe de todos modos)', () => {
    const pausadoLleno = analista({
      disponible_para_recibir: false,
      capacidad: { objetivo: 10, carga_activa: 12 },
    })
    expect(avisosAtencion(datos({ analistas: [pausadoLleno] }))).toEqual([])
  })
})

describe('fichaAnalista y ordenarFichas', () => {
  it('deriva cupos, conversión por moneda y "Sin muestra" honesto', () => {
    const ficha = fichaAnalista(
      analista({
        capacidad: { objetivo: 20, carga_activa: 14 },
        pen: {
          cartera_actual: { episodios: 12, capital: 78_000 },
          cohorte: {
            episodios_recibidos: 22,
            leads_unicos_recibidos: 21,
            convertidos: 10,
            descartados: 4,
            ciclos_resueltos: 14,
            leads_unicos_resueltos: 14,
          },
          rangos: rangosVacios(),
        },
        usd_no_segmentado: {
          cartera_actual_episodios: 2,
          cartera_actual_capital: 18_000,
          cohorte_episodios_recibidos: 4,
          cohorte_leads_unicos: 4,
          convertidos: 0,
          descartados: 0,
        },
      }),
    )
    expect(ficha.cuposLibres).toBe(6)
    expect(ficha.uso).toBe(70)
    expect(ficha.recibidosPeriodo).toBe(26)
    expect(ficha.conversionPen).toEqual({ pct: '71.4%', convertidos: 10, resueltos: 14 })
    expect(ficha.conversionUsd).toBeNull()
    expect(ficha.conUsd).toBe(true)
  })

  it('ordena por cupos: con cupo → sin límite → llenos, y pausados siempre al final', () => {
    const conCupo = fichaAnalista(
      analista({ nombre: 'Con Cupo', capacidad: { objetivo: 10, carga_activa: 3 } }),
    )
    const sinLimite = fichaAnalista(analista({ nombre: 'Sin Limite', capacidad: { carga_activa: 1 } }))
    const llena = fichaAnalista(
      analista({ nombre: 'Llena', capacidad: { objetivo: 10, carga_activa: 11 } }),
    )
    const pausado = fichaAnalista(
      analista({
        nombre: 'Pausado',
        disponible_para_recibir: false,
        capacidad: { objetivo: 10, carga_activa: 0 },
      }),
    )
    const orden = ordenarFichas([pausado, llena, sinLimite, conCupo], 'cupos')
    expect(orden.map((ficha) => ficha.analista.nombre)).toEqual([
      'Con Cupo',
      'Sin Limite',
      'Llena',
      'Pausado',
    ])
  })

  it('ordena por cierres dejando "Sin muestra" al final', () => {
    const bueno = fichaAnalista(
      analista({
        nombre: 'Bueno',
        pen: {
          cartera_actual: { episodios: 0, capital: 0 },
          cohorte: {
            episodios_recibidos: 4,
            leads_unicos_recibidos: 4,
            convertidos: 3,
            descartados: 1,
            ciclos_resueltos: 4,
            leads_unicos_resueltos: 4,
          },
          rangos: rangosVacios(),
        },
      }),
    )
    const sinMuestra = fichaAnalista(analista({ nombre: 'Sin Muestra' }))
    const orden = ordenarFichas([sinMuestra, bueno], 'cierres')
    expect(orden.map((ficha) => ficha.analista.nombre)).toEqual(['Bueno', 'Sin Muestra'])
  })
})

describe('equiposDistribucion', () => {
  it('agrupa por supervisor, integra al supervisor con cartera y conserva bandejas sin analistas', () => {
    const supervisorId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    const supervisor = analista({
      analista_id: supervisorId,
      nombre: 'César Ruiz',
      rol: 'supervisor',
    })
    const vendedor = analista({
      supervisor_id: supervisorId,
      supervisor_nombre: 'César Ruiz',
    })
    const resultado = equiposDistribucion(
      datos({
        analistas: [supervisor, vendedor],
        bandejas: [
          { id: supervisorId, nombre: 'César Ruiz', carga: 2 },
          { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', nombre: 'Vacía Sin Equipo', carga: 1 },
        ],
      }),
    )
    expect(resultado).toHaveLength(2)
    const cesar = resultado.find((equipo) => equipo.id === supervisorId)
    expect(cesar?.analistas).toHaveLength(2)
    expect(cesar?.pendientesBandeja).toBe(2)
    const vacia = resultado.find((equipo) => equipo.nombre === 'Vacía Sin Equipo')
    expect(vacia?.analistas).toHaveLength(0)
    expect(vacia?.pendientesBandeja).toBe(1)
  })
})

describe('resumenEquipo e idEquipoDeAnalista', () => {
  it('resume carga, límites, cupos, sin atender y llenos (solo disponibles cuentan como llenos)', () => {
    const fichas = [
      fichaAnalista(analista({ capacidad: { objetivo: 10, carga_activa: 10 } })),
      fichaAnalista(
        analista({
          capacidad: { objetivo: 5, carga_activa: 2 },
          operacion: { sin_tocar_actual: 3 },
        }),
      ),
      fichaAnalista(analista({ capacidad: { carga_activa: 4 } })),
      fichaAnalista(
        analista({
          disponible_para_recibir: false,
          capacidad: { objetivo: 3, carga_activa: 8 },
        }),
      ),
    ]
    expect(resumenEquipo(fichas)).toEqual({
      cargaActiva: 24,
      limiteDefinido: 18,
      cuposLibres: 3,
      sinAtender: 3,
      llenos: 1,
    })
  })

  it('sin ningún límite definido devuelve limiteDefinido null (no un 0 falso)', () => {
    const fichas = [fichaAnalista(analista({ capacidad: { carga_activa: 6 } }))]
    expect(resumenEquipo(fichas)).toMatchObject({ cargaActiva: 6, limiteDefinido: null, cuposLibres: 0 })
  })

  it('un supervisor con cartera pertenece a su propio equipo', () => {
    const supervisor = analista({ rol: 'supervisor' })
    expect(idEquipoDeAnalista(supervisor)).toBe(supervisor.analista_id)
    const vendedor = analista({ supervisor_id: supervisor.analista_id })
    expect(idEquipoDeAnalista(vendedor)).toBe(supervisor.analista_id)
    expect(idEquipoDeAnalista(analista())).toBe('sin-supervisor')
  })
})

describe('candidatosReparto', () => {
  function conRango(
    nombre: string,
    capacidad: { objetivo: number | null; carga: number },
    rango: { activos: number; c: number; d: number; recibidos?: number },
  ): MetricaDistribucionAnalista {
    const rangos = rangosVacios()
    const objetivo = rangos.find((r) => r.rango_id === 'pen_10000_20000')
    if (objetivo) {
      objetivo.cartera_actual = { episodios: rango.activos, capital: rango.activos * 12_000 }
      objetivo.cohorte = {
        episodios_recibidos: rango.recibidos ?? rango.c + rango.d,
        leads_unicos_recibidos: rango.recibidos ?? rango.c + rango.d,
        convertidos: rango.c,
        descartados: rango.d,
        leads_unicos_resueltos: rango.c + rango.d,
      }
    }
    return analista({
      nombre,
      capacidad: { objetivo: capacidad.objetivo, carga_activa: capacidad.carga },
      pen: {
        cartera_actual: { episodios: rango.activos, capital: rango.activos * 12_000 },
        cohorte: {
          episodios_recibidos: rango.recibidos ?? rango.c + rango.d,
          leads_unicos_recibidos: rango.recibidos ?? rango.c + rango.d,
          convertidos: rango.c,
          descartados: rango.d,
          ciclos_resueltos: rango.c + rango.d,
          leads_unicos_resueltos: rango.c + rango.d,
        },
        rangos,
      },
    })
  }

  it('ordena por cupos y desempata equilibrando el rango elegido', () => {
    const holgado = conRango('Holgado', { objetivo: 12, carga: 4 }, { activos: 2, c: 2, d: 2 })
    const igualCupoMenosRango = conRango(
      'Equilibrio',
      { objetivo: 10, carga: 2 },
      { activos: 0, c: 1, d: 1 },
    )
    const sinLimite = conRango('Sin Limite', { objetivo: null, carga: 1 }, { activos: 1, c: 0, d: 0 })
    const llena = conRango('Llena', { objetivo: 8, carga: 8 }, { activos: 3, c: 4, d: 0 })
    const pausada = { ...conRango('Pausada', { objetivo: 10, carga: 0 }, { activos: 0, c: 0, d: 0 }), disponible_para_recibir: false }

    const { candidatos, noReciben } = candidatosReparto(
      datos({ analistas: [llena, sinLimite, holgado, igualCupoMenosRango, pausada] }),
      { moneda: 'PEN', rangoId: 'pen_10000_20000' },
    )

    expect(noReciben).toBe(1)
    expect(candidatos.map((candidato) => candidato.analista.nombre)).toEqual([
      'Equilibrio',
      'Holgado',
      'Sin Limite',
      'Llena',
    ])
    expect(candidatos[1]?.segmento.conversion).toEqual({ pct: '50%', convertidos: 2, resueltos: 4 })
    expect(candidatos[3]?.lleno).toBe(true)
  })

  it('en dólares usa el total USD sin rangos y conserva el "Sin muestra"', () => {
    const conUsd = analista({
      nombre: 'Con USD',
      capacidad: { objetivo: 10, carga_activa: 2 },
      usd_no_segmentado: {
        cartera_actual_episodios: 2,
        cartera_actual_capital: 15_000,
        cohorte_episodios_recibidos: 3,
        cohorte_leads_unicos: 3,
        convertidos: 1,
        descartados: 1,
      },
    })
    const { candidatos } = candidatosReparto(datos({ analistas: [conUsd] }), { moneda: 'USD' })
    expect(candidatos[0]?.segmento).toEqual({
      activos: 2,
      capital: 15_000,
      recibidos: 3,
      conversion: { pct: '50%', convertidos: 1, resueltos: 2 },
    })
  })
})
