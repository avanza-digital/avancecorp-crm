import { describe, expect, it } from 'vitest'
import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type TresCosasInput } from './tres-cosas'
import type { ColaAccionOperativa } from './cola-accion'
import type { ItemCola } from './inteligencia'
import type { MetricaAgendaVendedor } from './metricas-agenda'

/** Item mínimo de la cola: la franja solo lee bucket y sev. */
function item(bucket: ItemCola['bucket'], sev: ItemCola['sev']): ItemCola {
  return { bucket, sev } as unknown as ItemCola
}

function cola(over: Partial<ColaAccionOperativa> = {}): ColaAccionOperativa {
  return {
    items: [],
    total: 0,
    porBucket: {},
    porSev: {},
    estancados: [],
    generadoEn: '2026-08-23T15:00:00Z',
    ...over,
  }
}

function ven(
  id: string,
  nombre: string,
  over: Partial<MetricaAgendaVendedor> = {},
): MetricaAgendaVendedor {
  return {
    vendedor_id: id,
    nombre,
    rol: 'vendedor',
    activo: true,
    toques: 0,
    toques_por_dia: 0,
    reuniones_realizadas: 0,
    completadas: 0,
    no_asistio: 0,
    canceladas: 0,
    pct_completadas: null,
    tareas_creadas: 0,
    reuniones_agendadas: 0,
    reprogramaciones: 0,
    pendientes: 0,
    vencidas: 0,
    leads_sin_accion: 0,
    ...over,
  }
}

function entrada(over: Partial<TresCosasInput> = {}): TresCosasInput {
  return {
    cola: cola(),
    totalPorRepartir: 0,
    esperaMasLargaReparto: null,
    vendedoresAgenda: [],
    ...over,
  }
}

describe('tresCosasDeHoy', () => {
  it('ESTADO DE PRODUCCIÓN (todo vacío): sin cosas, la franja no existe', () => {
    expect(tresCosasDeHoy(entrada())).toEqual([])
  })

  it('sin datos (cola y resumen null) tampoco inventa tarjetas', () => {
    expect(tresCosasDeHoy(entrada({ cola: null, totalPorRepartir: null }))).toEqual([])
  })

  it('el rojo va primero aunque el ámbar tenga más volumen, y nunca pasa de tres', () => {
    const cosas = tresCosasDeHoy(entrada({
      cola: cola({
        porBucket: { sin_responder: 2 },
        // Con al menos un sin_responder CRÍTICO en los items, la cosa es roja.
        items: [item('sin_responder', 'critica'), item('sin_responder', 'media')],
        estancados: [{ leadId: 'x', nombre: 'X', vendedorId: null, dias: 9 }],
      }),
      totalPorRepartir: 12,
      esperaMasLargaReparto: 4,
      // 4 sin acción: ámbar (con 5 sería crítica y desplazaría al reparto).
      vendedoresAgenda: [ven('v1', 'Ana', { leads_sin_accion: 4, no_asistio: 2 })],
    }))
    // 5 candidatos existen; quedan 3: los dos rojos y el primer ámbar.
    expect(cosas.map((c) => c.id)).toEqual(['sin_responder', 'no_asistio', 'por_repartir'])
    expect(cosas[0]).toMatchObject({
      severidad: 'critica',
      texto: '2 nuevos sin responder',
      destino: { tipo: 'pestana', pestana: 'urgente' },
    })
    expect(cosas[1]?.texto).toBe('Ana: 2 citas sin asistir')
    expect(cosas[2]?.texto).toBe('12 por repartir · el más rezagado hace 4 días')
  })

  it('el conteo del reparto es del servidor; sin detalle local omite la antigüedad', () => {
    const [cosa] = tresCosasDeHoy(entrada({ totalPorRepartir: 7, esperaMasLargaReparto: null }))
    expect(cosa).toMatchObject({
      id: 'por_repartir',
      severidad: 'atencion',
      texto: '7 por repartir',
      destino: { tipo: 'vista', vista: 'derivaciones' },
    })
  })

  it('respeta los umbrales de la campana: 1 no-show y 2 sin acción no son cosas', () => {
    expect(tresCosasDeHoy(entrada({
      vendedoresAgenda: [ven('v1', 'Ana', { no_asistio: 1, leads_sin_accion: 2 })],
    }))).toEqual([])
  })

  it('con varios analistas en el mismo aprieto agrupa y no señala a uno solo', () => {
    const cosas = tresCosasDeHoy(entrada({
      vendedoresAgenda: [
        ven('v1', 'Ana', { leads_sin_accion: 3, no_asistio: 2 }),
        ven('v2', 'Bea', { leads_sin_accion: 5, no_asistio: 3 }),
      ],
    }))
    expect(cosas.map((c) => c.texto)).toEqual([
      '2 analistas con citas sin asistir',
      '2 analistas con leads sin próxima acción',
    ])
  })

  it('los estancados salen como quinta cosa cuando hay hueco, con el peor caso', () => {
    const cosas = tresCosasDeHoy(entrada({
      cola: cola({ estancados: [
        { leadId: 'a', nombre: 'A', vendedorId: 'v1', dias: 9 },
        { leadId: 'b', nombre: 'B', vendedorId: null, dias: 5 },
      ] }),
    }))
    expect(cosas).toHaveLength(1)
    expect(cosas[0]).toMatchObject({
      id: 'sin_movimiento',
      texto: '2 sin movimiento · el peor lleva 9 días',
      destino: { tipo: 'pestana', pestana: 'sin_movimiento' },
    })
  })

  it('singular honesto: «1 nuevo sin responder»', () => {
    const [cosa] = tresCosasDeHoy(entrada({ cola: cola({ porBucket: { sin_responder: 1 } }) }))
    expect(cosa?.texto).toBe('1 nuevo sin responder')
  })

  it('un nuevo FRESCO (sin item crítico) es ámbar: la franja no desalinea al RPC', () => {
    // Codex F3 #1: un nuevo de dos horas es severidad media para el RPC;
    // pintarlo «urgente hoy» contradecía a la cola y a la campana.
    const [cosa] = tresCosasDeHoy(entrada({
      cola: cola({ porBucket: { sin_responder: 1 }, items: [item('sin_responder', 'media')] }),
    }))
    expect(cosa?.severidad).toBe('atencion')
  })

  it('cinco o más sin próxima acción es CRÍTICO — el mismo umbral que la campana', () => {
    const [cosa] = tresCosasDeHoy(entrada({
      vendedoresAgenda: [ven('v1', 'Ana', { leads_sin_accion: 5 })],
    }))
    expect(cosa).toMatchObject({ id: 'sin_accion', severidad: 'critica' })
  })

  it('la fila del PROPIO supervisor y los inactivos no ocupan cupo (Codex F3 #3)', () => {
    expect(tresCosasDeHoy(entrada({
      vendedoresAgenda: [
        ven('s1', 'SUPERVISOR UNO', { rol: 'supervisor', no_asistio: 2, leads_sin_accion: 6 }),
        ven('v9', 'Ex Analista', { activo: false, no_asistio: 3 }),
      ],
    }))).toEqual([])
  })

  it('la agenda genera cosas aunque la cola y el resumen estén caídos (sin dato ≠ sin señal)', () => {
    // Mata el mutante «if (cola == null || totalPorRepartir == null) return []».
    const cosas = tresCosasDeHoy(entrada({
      cola: null,
      totalPorRepartir: null,
      vendedoresAgenda: [ven('v1', 'Ana', { no_asistio: 2 })],
    }))
    expect(cosas.map((c) => c.id)).toEqual(['no_asistio'])
  })

  it('al tope del RPC el conteo de estancados dice «50+», como la pestaña', () => {
    const [cosa] = tresCosasDeHoy(entrada({
      cola: cola({ estancados: Array.from({ length: 50 }, (_, i) => ({
        leadId: `l-${i}`, nombre: `L${i}`, vendedorId: null, dias: 9 - (i % 3),
      })) }),
    }))
    expect(cosa?.texto).toMatch(/^50\+ sin movimiento/)
  })

  // NOTA de mutantes (Codex F3 #5): el desempate por vendedor_id de los sort
  // internos es HOY inobservable desde fuera (con conteos iguales el texto
  // agrupa, y con conteos distintos manda el conteo). Se conserva como
  // defensa estructural y se DICE aquí, según la regla de la casa para los
  // fallos que ningún test puede cazar.
  it('es determinista: el mismo día en otro orden de analistas da las mismas cosas', () => {
    const a = ven('v1', 'Ana', { no_asistio: 2 })
    const b = ven('v2', 'Bea', { no_asistio: 2 })
    expect(tresCosasDeHoy(entrada({ vendedoresAgenda: [a, b] })))
      .toEqual(tresCosasDeHoy(entrada({ vendedoresAgenda: [b, a] })))
  })
})

describe('candidatosDeHoy + seguimiento activo (27/09/2026)', () => {
  it('ESTADO DE PRODUCCIÓN (seguimiento activo, cola legada null): la primera gestión vencida es roja', () => {
    const cosas = tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: 4 }))
    expect(cosas).toEqual([{
      id: 'primera_gestion',
      severidad: 'critica',
      texto: '4 primeras gestiones vencidas',
      accion: 'Ver',
      destino: { tipo: 'vista', vista: 'seguimiento' },
    }])
  })

  it('singular honesto y sin dato no hay tarjeta (null, ausente o cero)', () => {
    expect(tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: 1 }))[0]?.texto)
      .toBe('1 primera gestión vencida')
    expect(tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: null }))).toEqual([])
    expect(tresCosasDeHoy(entrada({ cola: null }))).toEqual([])
    expect(tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: 0 }))).toEqual([])
  })

  it('candidatosDeHoy NO recorta: lo que no entra en la franja queda para «Esta semana»', () => {
    const entradaLlena = entrada({
      cola: null,
      primeraGestionPendiente: 2,
      totalPorRepartir: 3,
      vendedoresAgenda: [ven('v1', 'Ana', { no_asistio: 2, leads_sin_accion: 5 })],
    })
    const todos = candidatosDeHoy(entradaLlena)
    expect(todos.map((c) => c.id)).toEqual(['primera_gestion', 'no_asistio', 'sin_accion', 'por_repartir'])
    expect(tresCosasDeHoy(entradaLlena)).toEqual(todos.slice(0, 3))
  })

  it('la cosa de UN analista trae su dueño; la agrupada no señala a nadie', () => {
    const [sola] = tresCosasDeHoy(entrada({ vendedoresAgenda: [ven('v1', 'Ana', { no_asistio: 2 })] }))
    expect(sola).toMatchObject({ id: 'no_asistio', vendedorId: 'v1' })
    const [accionSola] = tresCosasDeHoy(entrada({ vendedoresAgenda: [ven('v7', 'Eva', { leads_sin_accion: 3 })] }))
    expect(accionSola).toMatchObject({ id: 'sin_accion', vendedorId: 'v7' })
    const agrupadas = tresCosasDeHoy(entrada({
      vendedoresAgenda: [
        ven('v1', 'Ana', { no_asistio: 2, leads_sin_accion: 3 }),
        ven('v2', 'Bea', { no_asistio: 2, leads_sin_accion: 3 }),
      ],
    }))
    for (const cosa of agrupadas) expect(cosa).not.toHaveProperty('vendedorId')
  })
})

describe('partesDeCosa', () => {
  it('separa la cifra inicial del título', () => {
    expect(partesDeCosa('4 primeras gestiones vencidas')).toEqual({ cifra: '4', resto: 'primeras gestiones vencidas' })
    expect(partesDeCosa('50+ sin movimiento · el peor lleva 9 días')).toEqual({ cifra: '50+', resto: 'sin movimiento · el peor lleva 9 días' })
  })

  it('con dueño, la cifra sale de detrás del nombre y el nombre va al final', () => {
    expect(partesDeCosa('KAREN ZAPATA: 2 citas sin asistir')).toEqual({ cifra: '2', resto: 'citas sin asistir · Karen' })
  })

  it('sin número no inventa cifra', () => {
    expect(partesDeCosa('Revisar el equipo')).toEqual({ cifra: null, resto: 'Revisar el equipo' })
  })
})
