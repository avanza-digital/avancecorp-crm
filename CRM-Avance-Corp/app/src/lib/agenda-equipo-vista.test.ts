// Tests de la vista "Agenda del equipo": resumen del ámbito, colapso de
// filas-cero y agrupación por supervisor (con huérfanos al final). Fixtures
// mínimos sobre el contrato de metricas-agenda — sin red ni React.
import { describe, expect, it } from 'vitest'
import {
  agruparPorEquipo,
  canceladasAsesor,
  canceladasSistema,
  resumenAgenda,
  separarPorActividad,
  SIN_EQUIPO_ID,
  tieneActividad,
} from './agenda-equipo-vista'
import type { MetricaAgendaVendedor } from './metricas-agenda'
import type { Miembro } from './tipos'

/** Miembro del payload con TODO en cero; `extra` enciende solo lo que el caso prueba. */
function ven(
  id: string,
  nombre: string,
  extra: Partial<MetricaAgendaVendedor> = {},
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
    ...extra,
  }
}

function miembro(perfilId: string, supervisorId: string | null, rol: Miembro['rol_crm'] = 'vendedor'): Miembro {
  return {
    perfil_id: perfilId,
    nombre_completo: perfilId.toUpperCase(),
    rol_crm: rol,
    supervisor_id: supervisorId,
    activo: true,
  }
}

describe('canceladasAsesor / canceladasSistema — la separación que pidió Miguel', () => {
  // «separa lo que cancela el sistema y lo que cancela el asesor» (2026-07-26).
  // El total `canceladas` mezclaba dos cosas incomparables: una decisión del
  // asesor sobre su agenda y el trigger que limpia pendientes cuando el lead se
  // convierte o se descarta.
  it('reparte el total en sus dos mitades', () => {
    const v = ven('v1', 'Ana', { canceladas: 5, canceladas_asesor: 2, canceladas_sistema: 3 })
    expect(canceladasAsesor(v)).toBe(2)
    expect(canceladasSistema(v)).toBe(3)
    expect(canceladasAsesor(v) + canceladasSistema(v)).toBe(v.canceladas)
  })

  it('sin desglose (BD sin migrar) TODO cae del lado del asesor, como antes', () => {
    // Degradación deliberada: mandarlas a «sistema» inflaría el % de todo el
    // equipo con datos inventados. El panel no puede cambiar de números por
    // sorpresa mientras la migración y el deploy del front no coinciden.
    const v = ven('v1', 'Ana', { canceladas: 4 })
    expect(canceladasAsesor(v)).toBe(4)
    expect(canceladasSistema(v)).toBe(0)
  })

  it('convertir un lead ya NO le baja el % al vendedor', () => {
    // El sesgo que existía desde 20260719013000: convertir cancela las tareas
    // pendientes del lead, y cada una entraba al denominador. El mejor
    // resultado del embudo empeoraba la nota, y más cuanto mejor planificado
    // estuviera el lead.
    const conVenta = resumenAgenda([
      ven('v1', 'Ana', { completadas: 3, canceladas: 4, canceladas_asesor: 0, canceladas_sistema: 4 }),
    ])
    expect(conVenta.cierres).toBe(3)
    expect(conVenta.pctCompletadas).toBe(100)
  })

  it('pero anular por su cuenta SÍ pesa: el botón no es una salida gratis', () => {
    const conAnuladas = resumenAgenda([
      ven('v1', 'Ana', { completadas: 3, canceladas: 1, canceladas_asesor: 1, canceladas_sistema: 0 }),
    ])
    expect(conAnuladas.cierres).toBe(4)
    expect(conAnuladas.pctCompletadas).toBe(75)
  })
})

describe('resumenAgenda', () => {
  it('suma los totales del ámbito y calcula el % sobre los cierres (completadas + no asistió + canceladas del asesor)', () => {
    const resumen = resumenAgenda([
      ven('v1', 'Ana', { toques: 10, completadas: 3, no_asistio: 1, vencidas: 2, leads_sin_accion: 1 }),
      ven('v2', 'Beto', { toques: 4, completadas: 1, canceladas: 1, no_asistio: 1 }),
    ])
    expect(resumen).toEqual({
      toques: 14,
      completadas: 4,
      cierres: 7,
      pctCompletadas: 57, // 4/7 redondeado
      noAsistio: 2,
      sinAccion: 1,
      vencidas: 2,
    })
  })

  it('deja pctCompletadas en null cuando no hubo cierres que porcentuar', () => {
    const resumen = resumenAgenda([ven('v1', 'Ana', { toques: 8, pendientes: 3 })])
    expect(resumen.pctCompletadas).toBeNull()
    expect(resumen.cierres).toBe(0)
    expect(resumen.toques).toBe(8)
  })

  it('con lista vacía todo queda en cero y sin porcentaje', () => {
    expect(resumenAgenda([])).toEqual({
      toques: 0,
      completadas: 0,
      cierres: 0,
      pctCompletadas: null,
      noAsistio: 0,
      sinAccion: 0,
      vencidas: 0,
    })
  })
})

describe('tieneActividad', () => {
  it('todo en cero → sin actividad (aunque haya derivados residuales)', () => {
    expect(tieneActividad(ven('v1', 'Ana'))).toBe(false)
  })

  it('la carga viva también cuenta: pendientes o leads sin acción sacan al miembro del colapso', () => {
    expect(tieneActividad(ven('v1', 'Ana', { pendientes: 1 }))).toBe(true)
    expect(tieneActividad(ven('v1', 'Ana', { leads_sin_accion: 2 }))).toBe(true)
    expect(tieneActividad(ven('v1', 'Ana', { toques: 1 }))).toBe(true)
  })
})

describe('separarPorActividad', () => {
  it('el rezago (vencidas + sin acción + no asistió) manda: quien acumula va primero, aunque toque menos', () => {
    const { conActividad, sinActividad } = separarPorActividad([
      ven('v1', 'Zoe', { toques: 5 }),
      ven('v2', 'Mia', { toques: 5 }),
      ven('v3', 'Ana', { toques: 9 }),
      ven('v4', 'Bruno', { toques: 2, vencidas: 1, leads_sin_accion: 1 }), // rezago 2
      ven('v5', 'Iván', { toques: 4, no_asistio: 2 }), // rezago 2, más toques
      ven('v6', 'Carla'),
      ven('v7', 'Abel'),
    ])
    // Rezago desc → toques desc → nombre; los todo-en-cero, alfabéticos.
    expect(conActividad.map((v) => v.nombre)).toEqual(['Iván', 'Bruno', 'Ana', 'Mia', 'Zoe'])
    expect(sinActividad.map((v) => v.nombre)).toEqual(['Abel', 'Carla'])
  })
})

describe('agruparPorEquipo', () => {
  const payload = [
    // Orden por nombre, como lo entrega la RPC.
    ven('v-h', 'Hugo Huérfano', { toques: 1 }), // su supervisor no está en el payload
    ven('sup-b', 'Marta Supervisora', { toques: 0 }),
    ven('v-b1', 'Nina Vendedora', { toques: 7, completadas: 2 }),
    ven('sup-a', 'Álvaro Supervisor', { toques: 3, completadas: 1, no_asistio: 1 }),
    ven('v-a1', 'Rita Vendedora', { toques: 12, leads_sin_accion: 2 }),
    ven('v-a2', 'Saúl Vendedor', {}),
    ven('v-x', 'Xime Sin Supervisor', {}), // no aparece en `equipo`
  ].map((v) => (v.vendedor_id.startsWith('sup') ? { ...v, rol: 'supervisor' as const } : v))

  const equipo: Miembro[] = [
    miembro('sup-a', null, 'supervisor'),
    miembro('sup-b', null, 'supervisor'),
    miembro('v-a1', 'sup-a'),
    miembro('v-a2', 'sup-a'),
    miembro('v-b1', 'sup-b'),
    miembro('v-h', 'sup-fantasma'), // supervisor fuera del payload
  ]

  it('arma una sección por supervisor (orden por nombre) y manda huérfanos a «Sin equipo asignado» al final', () => {
    const grupos = agruparPorEquipo(payload, equipo)
    expect(grupos).not.toBeNull()
    expect(grupos!.map((g) => g.nombreEquipo)).toEqual([
      'Álvaro Supervisor',
      'Marta Supervisora',
      'Sin equipo asignado',
    ])
    const [equipoA, equipoB, huerfanos] = grupos!
    // El supervisor con números es una fila más de su sección.
    expect(equipoA!.miembros.map((v) => v.nombre)).toEqual(['Rita Vendedora', 'Álvaro Supervisor'])
    expect(equipoA!.sinActividad.map((v) => v.nombre)).toEqual(['Saúl Vendedor'])
    // La supervisora todo-en-cero cae en la línea de sin actividad de SU sección.
    expect(equipoB!.miembros.map((v) => v.nombre)).toEqual(['Nina Vendedora'])
    expect(equipoB!.sinActividad.map((v) => v.nombre)).toEqual(['Marta Supervisora'])
    // Huérfanos: supervisor fuera del payload o miembro ausente del equipo.
    expect(huerfanos!.id).toBe(SIN_EQUIPO_ID)
    expect(huerfanos!.supervisor).toBeNull()
    expect(huerfanos!.miembros.map((v) => v.nombre)).toEqual(['Hugo Huérfano'])
    expect(huerfanos!.sinActividad.map((v) => v.nombre)).toEqual(['Xime Sin Supervisor'])
  })

  it('agrega los números del equipo completo (supervisor incluido, filas-cero no aportan)', () => {
    const grupos = agruparPorEquipo(payload, equipo)
    const equipoA = grupos![0]!
    expect(equipoA.agregados).toEqual({
      toques: 15, // 12 de Rita + 3 del supervisor
      completadas: 1,
      cierres: 2, // 1 completada + 1 no asistió
      pctCompletadas: 50,
      noAsistio: 1,
      sinAccion: 2,
      vencidas: 0,
    })
  })

  it('modo plano: sin prop equipo, o con 0-1 supervisores en el payload (caso supervisor)', () => {
    expect(agruparPorEquipo(payload)).toBeNull()
    const subarbol = payload.filter((v) => v.rol !== 'supervisor' || v.vendedor_id === 'sup-a')
    expect(agruparPorEquipo(subarbol, equipo)).toBeNull()
    expect(agruparPorEquipo([ven('v1', 'Ana', { toques: 1 })], equipo)).toBeNull()
  })
})
