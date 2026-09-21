import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { DiaEquipoSchema, filtrarOrdenarEquipo, horarioConfirmado, tiempoSinLlamar, type OrdenEquipo } from './gestion-diaria-equipo'
import { diaEquipoPrueba, filaEquipoPrueba } from './gestion-diaria-equipo.fixture'
import { diaEquipoDesdeDemo } from './gestion-diaria-equipo-demo'
import type { Actividad, Miembro } from './tipos'

describe('Confirmación del desglose horario', () => {
  const m = { ...filaEquipoPrueba().marcador, llamadas: 2, utiles: 2, contestadas: 1, por_hora: [{ hora: 9, llamadas: 2, contestadas: 1 }] }
  it('confirma vacío real y llamadas sólo fuera de 08–20', () => {
    expect(horarioConfirmado(filaEquipoPrueba().marcador)).toBe(true)
    expect(horarioConfirmado(m)).toBe(true)
    expect(horarioConfirmado({ ...m, por_hora: [{ hora: 23, llamadas: 2, contestadas: 1 }] })).toBe(true)
  })
  it('admite contestadas por tipo excluidas de la tasa, sin exceder las llamadas no útiles', () => {
    expect(horarioConfirmado({ ...m, utiles: 1, contestadas: 0 })).toBe(true)
    expect(horarioConfirmado({ ...m, utiles: 2, contestadas: 0 })).toBe(false)
    expect(horarioConfirmado({ ...m, utiles: 1, contestadas: 2 })).toBe(false)
  })
  it.each([
    { llamadas: 3 }, { llamadas: 1 }, { contestadas: 2 }, { contestadas: 0 }, { por_hora: [] },
    { por_hora: [{ hora: 9, llamadas: 1, contestadas: 1 }, { hora: 9, llamadas: 1, contestadas: 0 }] },
    { por_hora: [{ hora: 9, llamadas: -1, contestadas: -1 }] },
    { por_hora: [{ hora: 9, llamadas: 0.5, contestadas: 0.5 }] },
    { por_hora: [{ hora: 9, llamadas: 1, contestadas: 2 }] },
  ])('rechaza totales o filas incoherentes: %j', (cambio) => {
    expect(horarioConfirmado({ ...m, ...cambio })).toBe(false)
  })
})

describe('Equipo diario: contrato autosuficiente', () => {
  it('acepta un equipo sin actividad y un roster vacío', () => {
    expect(v.safeParse(DiaEquipoSchema, diaEquipoPrueba()).success).toBe(true)
    expect(v.safeParse(DiaEquipoSchema, diaEquipoPrueba([])).success).toBe(true)
  })
  it('rechaza duplicados, conteos negativos, resumen inconsistente y señal sin motivo', () => {
    expect(v.safeParse(DiaEquipoSchema, diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba()])).success).toBe(false)
    expect(v.safeParse(DiaEquipoSchema, diaEquipoPrueba([filaEquipoPrueba({ tareas_pendientes: -1 })])).success).toBe(false)
    const d = diaEquipoPrueba(); d.resumen.analistas = 2
    expect(v.safeParse(DiaEquipoSchema, d).success).toBe(false)
    expect(v.safeParse(DiaEquipoSchema, diaEquipoPrueba([filaEquipoPrueba({ requiere_atencion: true })])).success).toBe(false)
  })
  it('rechaza resultados imposibles y no confunde modo observación con cero', () => {
    const d = diaEquipoPrueba(); d.equipo[0]!.marcador.contestadas = 1
    expect(v.safeParse(DiaEquipoSchema, d).success).toBe(false)
    const o = diaEquipoPrueba(); o.modo_sla = 'observacion'
    expect(v.safeParse(DiaEquipoSchema, o).success).toBe(false)
    o.equipo[0]!.primer_intento_vencido = null; o.equipo[0]!.datos_incompletos = null
    expect(v.safeParse(DiaEquipoSchema, o).success).toBe(true)
  })
})

describe('Búsqueda y orden sin modificar la foto del servidor', () => {
  const filas = [filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO', tareas_pendientes: 270,
    tareas_vencidas: 270, motivos_atencion: ['tarea_vencida'], requiere_atencion: true })]
  it('busca sin acentos ni mayúsculas, conserva cero y filtra sólo problemas', () => {
    const f = { busqueda: 'perez', soloProblemas: false, orden: 'atencion' as const, ascendente: false }
    expect(filtrarOrdenarEquipo(filas, f).map((x) => x.analista_id)).toEqual(['a1'])
    expect(filtrarOrdenarEquipo(filas, { ...f, busqueda: '', soloProblemas: true }).map((x) => x.analista_id)).toEqual(['b'])
    expect(filas[0]?.analista_id).toBe('a1')
  })
  it.each<OrdenEquipo>(['nombre', 'llamadas', 'contacto', 'pendientes', 'atencion'])('ordena por %s en las dos direcciones', (orden) => {
    for (const ascendente of [true, false]) expect(filtrarOrdenarEquipo(filas, { busqueda: '', soloProblemas: false, orden, ascendente })).toHaveLength(2)
  })
  it('explica el tiempo sin convertir ausencia de llamadas en cero minutos', () => {
    expect(tiempoSinLlamar(null)).toBe('Sin llamadas hoy')
    expect(tiempoSinLlamar(0)).toBe('Menos de 1 min')
    expect(tiempoSinLlamar(45)).toBe('45 min')
    expect(tiempoSinLlamar(125)).toBe('2 h 5 min')
  })
  it.each([true, false])('deja las muestras insuficientes al final con ascendente=%s', (ascendente) => {
    const base = filaEquipoPrueba().marcador
    const muestra = [
      filaEquipoPrueba({ analista_id: 'pocas', nombre_completo: 'POCAS', marcador: { ...base, llamadas: 2, utiles: 2, contestadas: 2, tasa_contacto_pct: 100 } }),
      filaEquipoPrueba({ analista_id: 'bien', nombre_completo: 'BIEN', marcador: { ...base, llamadas: 10, utiles: 10, contestadas: 7, tasa_contacto_pct: 70, nivel: 'bien' } }),
      filaEquipoPrueba({ analista_id: 'bajo', nombre_completo: 'BAJO', marcador: { ...base, llamadas: 10, utiles: 10, contestadas: 1, tasa_contacto_pct: 10, nivel: 'bajo' } }),
      filaEquipoPrueba({ analista_id: 'cero', nombre_completo: 'CERO' }),
    ]
    expect(filtrarOrdenarEquipo(muestra, { busqueda: '', soloProblemas: false, orden: 'contacto', ascendente })
      .map((f) => f.analista_id)).toEqual([...(ascendente ? ['bajo', 'bien'] : ['bien', 'bajo']), 'cero', 'pocas'])
  })
})

describe('Espejo demo: roster y calendario', () => {
  const equipo: Miembro[] = [
    { perfil_id: 's1', nombre_completo: 'SUPERVISOR', rol_crm: 'supervisor', activo: true },
    { perfil_id: 'a1', nombre_completo: 'ANA', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
    { perfil_id: 'a2', nombre_completo: 'SIN CARTERA', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
    { perfil_id: 'ajeno', nombre_completo: 'OTRO EQUIPO', rol_crm: 'vendedor', supervisor_id: 's2', activo: true },
    { perfil_id: 'baja', nombre_completo: 'INACTIVO', rol_crm: 'vendedor', supervisor_id: 's1', activo: false },
  ]
  it('incluye quien no tiene cartera, excluye ajenos/inactivos y cuenta WhatsApp como actividad', () => {
    const a = { id: 'w', lead_id: 'l', tipo: 'whatsapp_enviado', autor_nombre: 'ANA', creado_en: '2026-09-21T14:30:00Z', detalle: '' } as Actividad
    const d = diaEquipoDesdeDemo('s1', equipo, [], [a], [], Date.parse('2026-09-21T15:00:00Z'), '2026-09-21')
    expect(d.equipo.map((f) => f.analista_id)).toEqual(['a1', 'a2'])
    expect(d.equipo[0]).toMatchObject({ gestiones_hoy: 1, marcador: { llamadas: 0 } })
    expect(d.resumen.sin_actividad).toBe(1)
    expect(v.safeParse(DiaEquipoSchema, d).success).toBe(true)
  })
  it.each([
    ['2026-09-21', '11:00:00', false], ['2026-09-21', '11:00:01', true],
    ['2026-09-21', '18:00:00', false], ['2026-09-26', '12:30:00', true],
    ['2026-09-26', '13:00:00', false], ['2026-09-27', '12:00:00', false],
  ])('inactividad en %s %s: %s', (dia, hora, esperado) => {
    const d = diaEquipoDesdeDemo('s1', equipo, [], [], [], Date.parse(`${dia}T${hora}-05:00`), dia)
    expect(d.equipo[0]?.sin_llamar_2h).toBe(esperado)
  })
})
