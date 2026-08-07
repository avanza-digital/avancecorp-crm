import { describe, expect, it } from 'vitest'
import {
  derivarAlertasSupervisor,
  derivarAlertasVendedor,
} from './alertas'
import type { EstadoSlaLead } from './sla-versionado'
import type { Actividad, Lead, Miembro, Tarea } from './tipos'

const HORA_MS = 3_600_000
const DIA_MS = 24 * HORA_MS
const AHORA = Date.UTC(2026, 7, 6, 17)

const haceHoras = (horas: number): string =>
  new Date(AHORA - horas * HORA_MS).toISOString()

const leadBase: Lead = {
  id: 'lead-base',
  nombre_completo: 'Cliente Prueba',
  telefono: '+51999999999',
  etapa: 'nuevo',
  origen: 'referido',
  monto_estimado: 10_000,
  moneda: 'PEN',
  vendedor_id: 'v1',
  vendedor_nombre: 'Ana',
  tenencia_desde: haceHoras(2),
  creado_en: haceHoras(2),
  activo: true,
}

const lead = (cambios: Partial<Lead>): Lead => ({ ...leadBase, ...cambios })

const tarea = (cambios: Partial<Tarea>): Tarea => ({
  id: 'tarea-base',
  lead_id: 'lead-base',
  vendedor_id: 'v1',
  asignado_supervisor_id: null,
  tipo: 'llamada',
  titulo: 'Llamar al cliente',
  vence_en: haceHoras(1),
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: haceHoras(48),
  ...cambios,
})

const actividad = (
  leadId: string,
  cambios: Partial<Actividad> = {},
): Actividad => ({
  id: `act-${leadId}`,
  lead_id: leadId,
  tipo: 'llamada_realizada',
  detalle: null,
  autor_nombre: 'Ana',
  creado_en: haceHoras(1),
  ...cambios,
})

const vendedor = (
  id: string,
  cambios: Partial<Miembro> = {},
): Miembro => ({
  perfil_id: id,
  nombre_completo: id === 'v1' ? 'Ana' : id.toUpperCase(),
  rol_crm: 'vendedor',
  supervisor_id: 's1',
  activo: true,
  ...cambios,
})

const estadoSlaVencido = (leadId: string): EstadoSlaLead => ({
  lead_id: leadId,
  ciclo_politica_id: '00000000-0000-4000-8000-000000000001',
  ciclo_politica_version: 1,
  primera_gestion_limite_en: haceHoras(1),
  primera_gestion_en: null,
  primer_contacto_limite_en: haceHoras(1),
  primer_contacto_en: null,
  ciclo_aproximado: false,
  asignacion_id: '00000000-0000-4000-8000-000000000002',
  asignacion_politica_id: '00000000-0000-4000-8000-000000000001',
  asignacion_politica_version: 1,
  asignacion_primera_gestion_limite_en: haceHoras(1),
  asignacion_primera_gestion_en: null,
  asignacion_primer_contacto_limite_en: haceHoras(1),
  asignacion_primer_contacto_en: null,
  etapa_politica_id: null,
  etapa_politica_version: null,
  etapa: null,
  etapa_iniciada_en: null,
  etapa_limite_en: null,
  etapa_objetivo_minutos: null,
  etapa_aproximada: null,
})

describe('derivarAlertasVendedor', () => {
  it('filtra estrictamente por vendedor y una tarea vencida gana por lead', () => {
    const propia = lead({ id: 'propia' })
    const ajena = lead({ id: 'ajena', vendedor_id: 'v2', vendedor_nombre: 'Bea' })
    const alertas = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [ajena, propia],
      actividades: [],
      tareas: [
        tarea({ id: 'vieja', lead_id: propia.id, vence_en: haceHoras(30) }),
        tarea({ id: 'reciente', lead_id: propia.id, vence_en: haceHoras(2) }),
        tarea({ id: 'ajena', lead_id: ajena.id, vendedor_id: 'v2', vence_en: haceHoras(40) }),
      ],
      ahora: AHORA,
    })

    expect(alertas).toHaveLength(1)
    expect(alertas[0]).toMatchObject({
      id: 'tarea_vencida:propia',
      tipo: 'tarea_vencida',
      severidad: 'critica',
      alcance: 'personal',
      responsableId: 'v1',
      destino: { vista: 'agenda', leadId: 'propia' },
    })
    expect(alertas[0]?.detalle).toContain('hace 1 día')
  })

  it('cambia la tarea de atención a crítica al cumplir 24 horas', () => {
    const antes = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [lead({ id: 'antes' })],
      actividades: [],
      tareas: [tarea({ lead_id: 'antes', vence_en: haceHoras(23.99) })],
      ahora: AHORA,
    })
    const limite = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [lead({ id: 'limite' })],
      actividades: [],
      tareas: [tarea({ lead_id: 'limite', vence_en: haceHoras(24) })],
      ahora: AHORA,
    })

    expect(antes[0]?.severidad).toBe('atencion')
    expect(limite[0]?.severidad).toBe('critica')
  })

  it('nombra sin_responder como lead_sin_responder y enlaza la cartera', () => {
    const alerta = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [lead({
        id: 'sin-respuesta',
        creado_en: haceHoras(2 * 24),
        tenencia_desde: haceHoras(2 * 24),
      })],
      actividades: [],
      tareas: [],
      ahora: AHORA,
      estadosSla: new Map([['sin-respuesta', estadoSlaVencido('sin-respuesta')]]),
    })[0]

    expect(alerta).toMatchObject({
      tipo: 'lead_sin_responder',
      severidad: 'critica',
      titulo: 'Lead sin responder',
      destino: {
        vista: 'cartera',
        leadId: 'sin-respuesta',
        etiqueta: 'Abrir lead',
      },
    })
  })

  it('sin fotografía SLA conserva el aviso pero no fabrica severidad crítica', () => {
    const alerta = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [lead({
        id: 'sin-fotografia',
        creado_en: haceHoras(48),
        tenencia_desde: haceHoras(48),
      })],
      actividades: [],
      tareas: [],
      ahora: AHORA,
    })[0]

    expect(alerta).toMatchObject({
      tipo: 'lead_sin_responder',
      severidad: 'atencion',
    })
  })

  it('usa sin próxima acción cuando la cola todavía no cruza un umbral', () => {
    const alerta = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [lead({ id: 'contactado', etapa: 'contactado' })],
      actividades: [actividad('contactado')],
      tareas: [],
      ahora: AHORA,
    })[0]

    expect(alerta).toMatchObject({
      id: 'sin_proxima_accion:contactado',
      tipo: 'sin_proxima_accion',
      severidad: 'atencion',
      destino: { vista: 'cartera', leadId: 'contactado' },
    })
  })

  it('falla cerrado ante fechas inválidas y no fabrica urgencia', () => {
    const alertas = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [
        lead({ id: 'lead-corrupto', creado_en: 'fecha-invalida' }),
        lead({ id: 'tarea-corrupta' }),
      ],
      actividades: [],
      tareas: [tarea({ lead_id: 'tarea-corrupta', vence_en: 'fecha-invalida' })],
      ahora: AHORA,
    })

    expect(alertas).toEqual([])
  })
})

describe('derivarAlertasSupervisor', () => {
  it('marca individualmente y como crítica solo su propia bandeja por repartir', () => {
    const propia = lead({
      id: 'bandeja-propia',
      vendedor_id: null,
      vendedor_nombre: null,
      asignado_supervisor_id: 's1',
    })
    const ajena = lead({
      id: 'bandeja-ajena',
      vendedor_id: null,
      vendedor_nombre: null,
      asignado_supervisor_id: 's2',
    })
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [ajena, propia],
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })

    expect(alertas).toHaveLength(1)
    expect(alertas[0]).toMatchObject({
      id: 'por_repartir:bandeja-propia',
      tipo: 'por_repartir',
      severidad: 'critica',
      alcance: 'equipo',
      responsableId: 's1',
      destino: { vista: 'hoy', leadId: 'bandeja-propia' },
    })
  })

  it('escala tareas solo desde 24 horas y mantiene una por lead', () => {
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [lead({ id: 'grave' }), lead({ id: 'reciente' })],
      actividades: [],
      tareas: [
        tarea({ id: 'grave-25', lead_id: 'grave', vence_en: haceHoras(25) }),
        tarea({ id: 'grave-48', lead_id: 'grave', vence_en: haceHoras(48) }),
        tarea({ id: 'reciente-23', lead_id: 'reciente', vence_en: haceHoras(23) }),
      ],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })

    expect(alertas).toHaveLength(1)
    expect(alertas[0]).toMatchObject({
      id: 'tarea_vencida:grave',
      tipo: 'tarea_vencida',
      severidad: 'critica',
      responsable: 'Ana',
      destino: { vista: 'agenda', leadId: 'grave' },
    })
    expect(alertas[0]?.valor).toBe(48)
  })

  it('escala la cola crítica al completar un día, pero no antes', () => {
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [
        lead({
          id: 'un-dia',
          creado_en: haceHoras(24),
          tenencia_desde: haceHoras(24),
        }),
        lead({
          id: 'casi',
          creado_en: haceHoras(23.9),
          tenencia_desde: haceHoras(23.9),
        }),
      ],
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
      estadosSla: new Map([['un-dia', estadoSlaVencido('un-dia')]]),
    })

    expect(alertas.map((alerta) => alerta.id)).toEqual([
      'lead_sin_responder:un-dia',
    ])
  })

  it.each([
    [2, null, null],
    [3, 'atencion', 3],
    [5, 'critica', 5],
  ] as const)(
    'agrupa %s leads sin acción con el umbral esperado',
    (cantidad, severidad, valor) => {
      const leads = Array.from({ length: cantidad }, (_, indice) => lead({
        id: `sin-accion-${indice}`,
        etapa: 'contactado',
        creado_en: haceHoras(2),
        tenencia_desde: haceHoras(2),
      }))
      const alertas = derivarAlertasSupervisor({
        supervisorId: 's1',
        leads,
        actividades: [],
        tareas: [],
        vendedores: [vendedor('v1')],
        ahora: AHORA,
      })
      const agrupada = alertas.find(
        (alerta) => alerta.id === 'sin_proxima_accion:vendedor:v1',
      )

      if (severidad == null) {
        expect(agrupada).toBeUndefined()
      } else {
        expect(agrupada).toMatchObject({
          severidad,
          alcance: 'equipo',
          responsableId: 'v1',
          responsable: 'Ana',
          valor,
          destino: { vista: 'equipo', leadId: null },
        })
      }
    },
  )

  it('ignora responsables fuera del roster y conserva un orden estable', () => {
    const propios = [
      lead({ id: 'zeta', vendedor_id: 'v1', vendedor_nombre: 'Ana' }),
      lead({ id: 'alfa', vendedor_id: 'v1', vendedor_nombre: 'Ana' }),
    ]
    const fuera = lead({
      id: 'fuera',
      vendedor_id: 'v2',
      vendedor_nombre: 'Bea',
      creado_en: haceHoras(3 * 24),
      tenencia_desde: haceHoras(3 * 24),
    })
    const tareas = propios.map((actual, indice) => tarea({
      id: `t-${actual.id}`,
      lead_id: actual.id,
      vence_en: haceHoras(30 + indice),
    }))

    const derivar = (entrada: Lead[]) => derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: entrada,
      actividades: [],
      tareas: [...tareas].reverse(),
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    }).map((alerta) => alerta.id)

    const propiosInvertidos = [...propios].reverse()
    expect(derivar([fuera, ...propios])).toEqual(
      derivar([...propiosInvertidos, fuera]),
    )
    expect(derivar([fuera, ...propios])).toEqual([
      'tarea_vencida:alfa',
      'tarea_vencida:zeta',
    ])
  })

  it('no deriva nada con un reloj inválido', () => {
    expect(derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [lead({ id: 'x', creado_en: new Date(AHORA - DIA_MS).toISOString() })],
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1')],
      ahora: Number.NaN,
    })).toEqual([])
  })
})
