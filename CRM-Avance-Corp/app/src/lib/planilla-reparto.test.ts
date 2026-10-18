import { describe, expect, it, vi } from 'vitest'
import { ejecutarReparto, fechasPeriodo, filasPlanilla, filtrarColaPlanilla, periodoInicial, prepararReparto, ventanasFechas } from './planilla-reparto'
import type { ColaLead, DiaAgendaReparto, SupervisorReparto } from './tipos'

const supervisores: SupervisorReparto[] = ['Ana', 'Beto', 'Carla'].map((nombre) => ({ perfil_id: nombre, nombre, activo: true, bandeja_pendiente: 100 }))
const lead = (id: string, creado_en = '2026-10-15T05:00:00Z', origen: ColaLead['origen'] = 'formulario_3'): ColaLead => ({ id, nombre_completo: id, origen, creado_en, moneda: 'PEN', monto_estimado: 0 })
const dia: DiaAgendaReparto = { fecha: '2026-10-14', asignaciones: [], origenes: [
  { origen: 'formulario_3', turno: 'formulario', derivados: 8, fuera_turno: 0, entregas: [{ supervisor_id: 'Ana', supervisor_nombre: 'Ana', supervisor_alias: null, derivados: 8, coincide_turno: true }] },
  { origen: 'landing', turno: 'landing', derivados: 3, fuera_turno: 0, entregas: [{ supervisor_id: 'Baja', supervisor_nombre: 'Baja', supervisor_alias: null, derivados: 3, coincide_turno: true }] },
] }

describe('períodos independientes de la planilla', () => {
  it('la semana es lunes a domingo e incluye hoy', () => {
    expect(fechasPeriodo(periodoInicial('semana', '2026-10-15'))).toEqual(['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17', '2026-10-18'])
    expect(fechasPeriodo(periodoInicial('todas'))).toBeNull()
  })
  it('deduplica días sueltos y separa huecos y ventanas mayores a 14', () => {
    const dias = fechasPeriodo({ ...periodoInicial('dias'), dias: ['2026-10-15', '2026-10-12', '2026-10-15'] })!
    expect(ventanasFechas(dias)).toEqual([['2026-10-12'], ['2026-10-15']])
    expect(ventanasFechas(fechasPeriodo({ ...periodoInicial('rango', '2026-10-01'), hasta: '2026-10-15' })!).map((v) => v.length)).toEqual([14, 1])
  })
  it('rechaza fechas inexistentes, rangos invertidos, vacíos y excesivos', () => {
    for (const periodo of [periodoInicial('dia', '2026-02-30'), { ...periodoInicial('rango', '2026-10-15'), hasta: '2026-10-14' }, { ...periodoInicial('dias'), dias: [] }, { ...periodoInicial('rango', '2025-01-01'), hasta: '2026-10-15' }]) expect(() => fechasPeriodo(periodo)).toThrow()
  })
  it('filtra ingreso por creado_en en Lima, no por campaña ni entregas', () => {
    const cola = [lead('anterior', '2026-10-15T04:59:59Z'), lead('hoy'), lead('otro', undefined, 'landing')]
    expect(filtrarColaPlanilla(cola, ['2026-10-14'], ['formulario_3']).map((l) => l.id)).toEqual(['anterior'])
    expect(filtrarColaPlanilla(cola, null, ['landing'])).toHaveLength(1)
  })
})

describe('entregas, disponibilidad y preparación', () => {
  it('incluye tres activos y un histórico sin confundir stock con entregas', () => {
    const filas = filasPlanilla(supervisores, [dia], ['landing', 'formulario_3'], [])
    expect(filas).toHaveLength(4)
    expect(filas.find((f) => f.id === 'Carla')?.recibidos).toBe(0)
    expect(filas.find((f) => f.id === 'Baja')).toMatchObject({ activo: false, recibidos: 3 })
    expect(filasPlanilla(supervisores, [dia], ['formulario_3'], ['Ana'])).toMatchObject([{ recibidos: 8 }])
    expect(() => filasPlanilla(supervisores, [{ fecha: dia.fecha, asignaciones: [] }], [], [])).toThrow('Falta')
  })
  it('cuenta entregas repetidas y suma los grupos exactos sin sumar sus agregados', () => {
    expect(filasPlanilla(supervisores, [dia, { ...dia, fecha: '2026-10-15' }], ['formulario_3'], ['Ana'])[0]?.recibidos).toBe(16)
  })
  it('fija IDs FIFO una sola vez entre destinos y orígenes', () => {
    const cola = [lead('z'), lead('a'), lead('l', undefined, 'landing')]
    const plan = prepararReparto({ Ana: { formulario_3: '1' }, Carla: { formulario_3: '1', landing: '1' } }, cola, filasPlanilla(supervisores, [], [], []), ['formulario_3', 'landing'])
    expect(plan.map((p) => [p.lead.id, p.supervisorId])).toEqual([['a', 'Ana'], ['z', 'Carla'], ['l', 'Carla']])
    expect(cola).toHaveLength(3)
  })
  it('rechaza exceso agregado, fracciones, destinos inactivos y planes ocultos', () => {
    const filas = filasPlanilla(supervisores, [dia], ['landing', 'formulario_3'], [])
    for (const borrador of [{ Ana: { formulario_3: '1' }, Beto: { formulario_3: '1' } }, { Ana: { formulario_3: '1.5' } }, { Baja: { formulario_3: '1' } }, { Ana: { landing: '1' } }]) expect(() => prepararReparto(borrador, [lead('a')], filas, ['formulario_3'])).toThrow()
    expect(() => prepararReparto({}, [lead('a'), lead('a')], filas, [])).toThrow('repetidos')
  })
  it('se detiene ante resultado incierto y no reintenta ni sustituye leads', async () => {
    const plan = prepararReparto({ Ana: { formulario_3: '4' } }, ['a', 'b', 'c', 'd'].map((id) => lead(id)), filasPlanilla(supervisores, [], [], []), ['formulario_3'])
    const enviar = vi.fn().mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error('Red interrumpida'))
    const progreso = vi.fn()
    const resultado = await ejecutarReparto(plan, enviar, () => true, progreso)
    expect(resultado.confirmadas).toHaveLength(2)
    expect(resultado.interrumpida?.lead.id).toBe('c')
    expect(resultado.pendientes).toBe(1)
    expect(enviar).toHaveBeenCalledTimes(3)
    expect(progreso.mock.calls).toEqual([[1], [2]])
  })
  it('detiene al salir o cambiar de día, y confirma un envío completo', async () => {
    const plan = prepararReparto({ Ana: { formulario_3: '1' } }, [lead('a')], filasPlanilla(supervisores, [], [], []), ['formulario_3'])
    const enviar = vi.fn(async () => {})
    expect(await ejecutarReparto(plan, enviar, () => false, () => {})).toMatchObject({ pendientes: 1, confirmadas: [] })
    expect(enviar).not.toHaveBeenCalled()
    expect(await ejecutarReparto(plan, enviar, () => 'Cambió el día en Lima.', () => {})).toMatchObject({ error: 'Cambió el día en Lima.' })
    expect(await ejecutarReparto(plan, enviar, () => true, () => {})).toMatchObject({ pendientes: 0, error: null, confirmadas: plan })
  })

  it('distingue un rechazo confirmado y asigna FIFO por orden de supervisor, no de edición', async () => {
    const plan = prepararReparto({ Carla: { formulario_3: '1' }, Ana: { formulario_3: '1' } }, [lead('a'), lead('b')], filasPlanilla(supervisores, [], [], []), ['formulario_3'])
    expect(plan[0]).toMatchObject({ supervisorId: 'Ana', lead: { id: 'a' } })
    const rechazo = Object.assign(new Error('El lead salió de la cola'), { code: 'FUERA_DE_COLA' })
    const resultado = await ejecutarReparto(plan, async () => { throw rechazo }, () => true, () => {})
    expect(resultado).toMatchObject({ confirmadas: [], pendientes: 1, rechazada: true })
    expect(resultado.error).toContain('Entrega rechazada')
    expect(resultado.error).not.toContain('Puede haberse registrado')
  })
})
