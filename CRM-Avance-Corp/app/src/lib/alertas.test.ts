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

  it('la tarea vencida dice los minutos (antes: «hace menos de una hora» plano)', () => {
    const fresca = lead({ id: 'fresca' })
    const alertas = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [fresca],
      actividades: [],
      tareas: [tarea({ lead_id: fresca.id, vence_en: haceHoras(0.5) })],
      ahora: AHORA,
    })
    expect(alertas[0]?.detalle).toBe('«Llamar al cliente» venció hace 30 minutos.')

    const recien = derivarAlertasVendedor({
      vendedorId: 'v1',
      leads: [fresca],
      actividades: [],
      tareas: [tarea({ lead_id: fresca.id, vence_en: haceHoras(30 / 3600) })],
      ahora: AHORA,
    })
    expect(recien[0]?.detalle).toBe('«Llamar al cliente» venció hace un momento.')
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

// Una alerta por DECISIÓN, no por registro (2026-08-23): el supervisor recibe
// a lo sumo cuatro grupos — bandeja, nuevos sin responder, plazos vencidos,
// vendedores sin acción — y cada lead cuenta en uno solo.
describe('derivarAlertasSupervisor', () => {
  const enBandeja = (id: string, cambios: Partial<Lead> = {}): Lead => lead({
    id,
    nombre_completo: id,
    vendedor_id: null,
    vendedor_nombre: null,
    asignado_supervisor_id: 's1',
    ...cambios,
  })

  it('agrupa su propia bandeja en UNA alerta ámbar con el total y el más rezagado', () => {
    const ajena = enBandeja('bandeja-ajena', { asignado_supervisor_id: 's2' })
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [
        ajena,
        enBandeja('reciente'),
        enBandeja('rezagado', { creado_en: haceHoras(4 * 24), tenencia_desde: haceHoras(4 * 24) }),
      ],
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })

    expect(alertas).toHaveLength(1)
    expect(alertas[0]).toMatchObject({
      id: 'grupo:por_repartir:s1',
      tipo: 'por_repartir',
      severidad: 'atencion',
      alcance: 'equipo',
      titulo: '2 leads esperando reparto',
      responsableId: 's1',
      valor: 2,
      destino: { vista: 'derivaciones', leadId: null, etiqueta: 'Repartir' },
    })
    // El más rezagado encabeza la lista: es al que hay que repartir primero.
    expect(alertas[0]?.detalle).toBe('rezagado, reciente. El más rezagado espera hace 4 días.')
  })

  it('con un solo lead en bandeja habla en singular y sin lista', () => {
    const [alerta] = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [enBandeja('solo')],
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })
    expect(alerta?.titulo).toBe('1 lead esperando reparto')
    expect(alerta?.valor).toBe(1)
  })

  it('resume los nombres a tres y «N más»', () => {
    const [alerta] = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: ['a', 'b', 'c', 'd', 'e'].map((id) => enBandeja(id)),
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })
    expect(alerta?.detalle).toMatch(/^a, b, c y 2 más\./)
  })

  it('agrupa los plazos vencidos desde 24 horas en una alerta crítica, una vez por lead', () => {
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [
        lead({ id: 'grave', nombre_completo: 'Grave' }),
        lead({ id: 'reciente', nombre_completo: 'Reciente' }),
      ],
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
      id: 'grupo:tarea_vencida:s1',
      tipo: 'tarea_vencida',
      severidad: 'critica',
      titulo: '1 lead con plazo vencido desde ayer',
      detalle: '1 tarea vencida: Grave.',
      valor: 1,
      // A la AGENDA, no a la cola: un lead con la tarea vencida y otra futura
      // tiene plan vivo y la cola no lo lista — el enlace moriría (Codex).
      destino: { vista: 'agenda', leadId: null, etiqueta: 'Abrir en Agenda' },
    })
  })

  it('separa los nuevos sin responder del resto de la cola crítica, solo al completar un día', () => {
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [
        lead({
          id: 'un-dia',
          nombre_completo: 'Un Día',
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

    expect(alertas).toHaveLength(1)
    expect(alertas[0]).toMatchObject({
      id: 'grupo:lead_sin_responder:s1',
      tipo: 'lead_sin_responder',
      severidad: 'critica',
      titulo: '1 lead nuevo sin responder',
      valor: 1,
      destino: { vista: 'hoy', leadId: null },
    })
    // Detalle COMPLETO a propósito: con 24 h justas dentro del grupo, decir
    // «más de un día» sería falso (hallazgo de Codex sobre la redacción).
    expect(alertas[0]?.detalle).toBe('Un Día. Sin primer contacto desde hace un día o más.')
  })

  it('un lead cuenta en un solo grupo: la bandeja gana a la tarea vencida, pero HEREDA su criticidad', () => {
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [enBandeja('parkeado')],
      actividades: [],
      tareas: [tarea({ id: 't', lead_id: 'parkeado', vendedor_id: null, vence_en: haceHoras(30) })],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })
    expect(alertas.map((alerta) => alerta.id)).toEqual(['grupo:por_repartir:s1'])
    // Agrupar nunca rebaja una señal crítica independiente: el parkeado trae
    // una tarea vencida de 30 h y el grupo entero sube a crítica (Codex #1).
    expect(alertas[0]?.severidad).toBe('critica')
  })

  it('con la tarea vencida por DEBAJO de 24 h la bandeja sigue en ámbar', () => {
    const [alerta] = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [enBandeja('parkeado')],
      actividades: [],
      tareas: [tarea({ id: 't', lead_id: 'parkeado', vendedor_id: null, vence_en: haceHoras(23) })],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
    })
    expect(alerta?.severidad).toBe('atencion')
  })

  it('nombres Unicode equivalentes no vuelven inestable el grupo de vendedores (desempate por id)', () => {
    const sinAccion = (vendedorId: string, cantidad: number) => Array.from({ length: cantidad }, (_, i) => lead({
      id: `${vendedorId}-${i}`,
      vendedor_id: vendedorId,
      etapa: 'contactado',
      creado_en: haceHoras(2),
      tenencia_desde: haceHoras(2),
    }))
    // «Ána» precompuesto (v-b) y descompuesto (v-a): localeCompare da 0.
    const roster = [
      vendedor('v-b', { nombre_completo: '\u00c1na' }),
      vendedor('v-a', { nombre_completo: 'A\u0301na' }),
    ]
    const derivar = (entrada: Lead[]) => derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: entrada,
      actividades: [],
      tareas: [],
      vendedores: roster,
      ahora: AHORA,
    })[0]?.detalle
    const a = sinAccion('v-a', 3)
    const b = sinAccion('v-b', 3)
    expect(derivar([...a, ...b])).toBe(derivar([...b, ...a]))
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
        (alerta) => alerta.id === 'grupo:sin_proxima_accion:s1',
      )

      if (severidad == null) {
        expect(agrupada).toBeUndefined()
      } else {
        // Un solo vendedor: conserva su nombre como responsable, como antes.
        expect(agrupada).toMatchObject({
          severidad,
          alcance: 'equipo',
          titulo: `Ana tiene ${valor} leads sin próxima acción`,
          responsableId: 'v1',
          responsable: 'Ana',
          valor,
          destino: { vista: 'equipo', leadId: null },
        })
      }
    },
  )

  it('varios vendedores sin acción van en un grupo ordenado por carga; la severidad es la más alta', () => {
    const sinAccion = (vendedorId: string, cantidad: number) => Array.from({ length: cantidad }, (_, i) => lead({
      id: `${vendedorId}-${i}`,
      vendedor_id: vendedorId,
      etapa: 'contactado',
      creado_en: haceHoras(2),
      tenencia_desde: haceHoras(2),
    }))
    const [alerta] = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [...sinAccion('v1', 3), ...sinAccion('v2', 5)],
      actividades: [],
      tareas: [],
      vendedores: [vendedor('v1'), vendedor('v2', { nombre_completo: 'Bea' })],
      ahora: AHORA,
    })
    expect(alerta).toMatchObject({
      id: 'grupo:sin_proxima_accion:s1',
      severidad: 'critica',
      titulo: '2 vendedores con leads sin próxima acción',
      detalle: 'Bea 5 · Ana 3',
      responsableId: null,
      responsable: null,
      valor: 8,
    })
  })

  it('ignora responsables fuera del roster y conserva un orden estable', () => {
    const propios = [
      lead({ id: 'zeta', nombre_completo: 'Zeta', vendedor_id: 'v1', vendedor_nombre: 'Ana' }),
      lead({ id: 'alfa', nombre_completo: 'Alfa', vendedor_id: 'v1', vendedor_nombre: 'Ana' }),
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
    })

    const propiosInvertidos = [...propios].reverse()
    expect(derivar([fuera, ...propios])).toEqual(derivar([...propiosInvertidos, fuera]))
    expect(derivar([fuera, ...propios]).map((alerta) => alerta.id)).toEqual([
      'grupo:tarea_vencida:s1',
    ])
    expect(derivar([fuera, ...propios])[0]?.valor).toBe(2)
  })

  it('nunca emite más de cuatro alertas y el mismo lead no aparece dos veces', () => {
    const alertas = derivarAlertasSupervisor({
      supervisorId: 's1',
      leads: [
        ...['p1', 'p2', 'p3'].map((id) => enBandeja(id)),
        lead({ id: 'v1-vencida' }),
        lead({ id: 'nuevo', creado_en: haceHoras(30), tenencia_desde: haceHoras(30) }),
        ...Array.from({ length: 4 }, (_, i) => lead({
          id: `sa-${i}`,
          etapa: 'contactado',
          creado_en: haceHoras(2),
          tenencia_desde: haceHoras(2),
        })),
      ],
      actividades: [],
      tareas: [tarea({ id: 't', lead_id: 'v1-vencida', vence_en: haceHoras(30) })],
      vendedores: [vendedor('v1')],
      ahora: AHORA,
      estadosSla: new Map([['nuevo', estadoSlaVencido('nuevo')]]),
    })
    expect(alertas.map((alerta) => alerta.id)).toEqual([
      'grupo:tarea_vencida:s1',
      'grupo:lead_sin_responder:s1',
      'grupo:por_repartir:s1',
      'grupo:sin_proxima_accion:s1',
    ])
    expect(alertas.reduce((suma, alerta) => suma + (alerta.valor ?? 0), 0)).toBe(3 + 1 + 1 + 4)
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
