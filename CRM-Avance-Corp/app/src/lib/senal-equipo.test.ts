import { describe, expect, it } from 'vitest'
import { conteoSemaforoEquipo, lecturaAnalista } from './senal-equipo'

const sinRezago = { no_asistio: 0, leads_sin_accion: 0, vencidas: 0 }

describe('lecturaAnalista', () => {
  it('sin cartera abierta NI señales de agenda es NEUTRO (no hay nada que medir)', () => {
    expect(lecturaAnalista({ activos: 0, diasSinActividadMax: 9 }, sinRezago)).toEqual({ nivel: 'neutro', senales: [] })
    expect(lecturaAnalista({ activos: 0, diasSinActividadMax: 0 }, null)).toEqual({ nivel: 'neutro', senales: [] })
  })

  it('sin cartera abierta la AGENDA sigue mandando: un no-show repetido no desaparece (Codex F1)', () => {
    const l = lecturaAnalista({ activos: 0, diasSinActividadMax: 9 }, { no_asistio: 3, leads_sin_accion: 0, vencidas: 1 })
    expect(l.nivel).toBe('critico')
    // Los días sin actividad no cuentan sin leads abiertos.
    expect(l.senales).toEqual([
      { texto: '3 citas sin asistir', nivel: 'critico' },
      { texto: '1 tarea vencida', nivel: 'atencion' },
    ])
  })

  it('con actividad fresca y sin rezago no hay señal', () => {
    expect(lecturaAnalista({ activos: 4, diasSinActividadMax: 1.5 }, sinRezago)).toEqual({ nivel: null, senales: [] })
  })

  it('un no-show repetido es ROJO en el nivel del analista, no solo en su chip', () => {
    const l = lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, no_asistio: 2 })
    expect(l.nivel).toBe('critico')
    expect(l.senales).toEqual([{ texto: '2 citas sin asistir', nivel: 'critico' }])
  })

  it('una sola cita sin asistir no es patrón', () => {
    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, no_asistio: 1 }).nivel).toBeNull()
  })

  it('sin próxima acción: ámbar desde 1, rojo desde 5 (umbral de la campana)', () => {
    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, leads_sin_accion: 1 }).senales)
      .toEqual([{ texto: '1 lead sin próxima acción', nivel: 'atencion' }])
    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, leads_sin_accion: 4 }).nivel).toBe('atencion')
    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, leads_sin_accion: 5 }).nivel).toBe('critico')
  })

  it('días sin actividad: 2–5 ámbar, más de 5 rojo', () => {
    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 2 }, sinRezago).senales)
      .toEqual([{ texto: 'Un lead sin actividad hace 2 días', nivel: 'atencion' }])
    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 5 }, sinRezago).nivel).toBe('atencion')
    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 6 }, sinRezago).nivel).toBe('critico')
  })

  it('tareas vencidas son ámbar y con singular honesto', () => {
    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 0 }, { ...sinRezago, vencidas: 1 }).senales)
      .toEqual([{ texto: '1 tarea vencida', nivel: 'atencion' }])
  })

  it('la severidad es la PEOR y las rojas van primero', () => {
    const l = lecturaAnalista({ activos: 5, diasSinActividadMax: 3 }, { no_asistio: 0, leads_sin_accion: 6, vencidas: 2 })
    expect(l.nivel).toBe('critico')
    expect(l.senales.map((s) => s.nivel)).toEqual(['critico', 'atencion', 'atencion'])
    expect(l.senales[0]?.texto).toBe('6 leads sin próxima acción')
  })

  it('sin agenda (null) juzga solo los días y no inventa «al día»', () => {
    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 7 }, null)).toEqual({
      nivel: 'critico',
      senales: [{ texto: 'Un lead sin actividad hace 7 días', nivel: 'critico' }],
    })
    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 0 }, undefined).nivel).toBeNull()
  })
})

describe('conteoSemaforoEquipo', () => {
  it('cuenta a cada analista UNA vez, en su peor nivel; neutro y sin señal no cuentan', () => {
    const lecturas = [
      lecturaAnalista({ activos: 3, diasSinActividadMax: 3 }, { no_asistio: 2, leads_sin_accion: 1, vencidas: 1 }),
      lecturaAnalista({ activos: 3, diasSinActividadMax: 3 }, sinRezago),
      lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, sinRezago),
      lecturaAnalista({ activos: 0, diasSinActividadMax: 0 }, null),
    ]
    expect(conteoSemaforoEquipo(lecturas)).toEqual({ rojo: 1, ambar: 1 })
  })
})
