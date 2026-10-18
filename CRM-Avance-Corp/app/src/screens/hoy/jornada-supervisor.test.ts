import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { diaEquipoPrueba, filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import { cumplimientoDesdeRpc, CumplimientoMetasV2Schema, objetivosCero } from '@/lib/objetivos'
import { totalEnSoles } from '@/lib/capital-unificado'
import valorado from '@/lib/__fixtures__/capital-valorado/activo.json'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
import type { CitaEjemplo } from '@/components/citas/modelo'
import type { FilaFacturacionDia } from '@/lib/facturacion'
import { avanceCapital, filasMensualesJornada, operacionesConfirmadas, resumirCitasHoy, resumirJornada, resumirResultadosHoy } from './jornada-supervisor'

describe('lectura comercial de la jornada del supervisor', () => {
  it('resultados: conserva todos los tipos, monedas y atribución histórica, y suma operaciones, no filas', () => {
    const fila: FilaFacturacionDia = { dia: '2026-10-18', tipo: 'contrato_nuevo', moneda: 'PEN',
      analistaId: 'a1', analistaNombre: 'Analista trasladado', supervisorId: 's1', supervisorNombre: 'Supervisor', operaciones: 2, capital: 40000 }
    const filas = [fila,
      { ...fila, tipo: 'contrato_renovacion', moneda: 'USD' as const, operaciones: 1, capital: 10000 },
      { ...fila, tipo: 'contrato_upgrade', analistaId: 'a2', operaciones: 1, capital: 5000 },
      { ...fila, tipo: 'cooperativa', analistaId: 'a2', operaciones: 1, capital: 6000 },
      { ...fila, analistaId: 's1', supervisorId: 'gerencia', operaciones: 1, capital: 2000 },
      { ...fila, dia: '2026-10-17', capital: 1000000 },
      { ...fila, dia: '2026-10-19', capital: 1000000 },
      { ...fila, supervisorId: 'sub-supervisor', analistaId: 'a3', operaciones: 1, capital: 10000 },
    ]
    const resultado = resumirResultadosHoy(filas, '2026-10-18')!
    expect(resultado).toMatchObject({ operaciones: 7, pen: 63000, usd: 10000 })
    expect(resultado.analistas).toHaveLength(4)
    expect(resultado.analistas.find(f => f.id === 'a1')).toMatchObject({ operaciones: 3, pen: 40000, usd: 10000 })
    expect(resumirResultadosHoy(null, '2026-10-18')).toBeNull()
    expect(resumirResultadosHoy([], '2026-10-18')).toMatchObject({ operaciones: 0, pen: 0, usd: 0, analistas: [] })
  })
  it('calcula el contacto por suma de llamadas útiles, no por media de porcentajes', () => {
    const base = filaEquipoPrueba()
    const dia = diaEquipoPrueba([
      { ...base, marcador: { ...base.marcador, llamadas: 12, utiles: 10, contestadas: 5 } },
      { ...base, analista_id: 'a2', marcador: { ...base.marcador, llamadas: 90, utiles: 90, contestadas: 9 } },
    ])
    expect(resumirJornada(dia)).toMatchObject({ llamadas: 102, utiles: 100, contestadas: 14, contacto: 14 })
  })
  it('distingue falta de fuente, día vacío y primera gestión sin regla confirmada', () => {
    expect(resumirJornada(null)).toBeNull()
    expect(resumirJornada(diaEquipoPrueba([]))).toMatchObject({ llamadas: 0, contacto: null, muestraSuficiente: false })
    expect(resumirJornada(diaEquipoPrueba([filaEquipoPrueba({ primer_intento_vencido: null })]))?.primeras).toBeNull()
  })
  it('cuenta cada estado de la cita por fecha prevista, incluyendo reprogramadas y canceladas', () => {
    const hoy = '2026-10-18'
    const citas = ['realizada', 'realizada', 'programada', 'vencida', 'no_show', 'cancelada', 'sistema', 'reprogramada']
      .map(estado => ({ fecha: hoy, estado }) as CitaEjemplo)
    citas.push({ fecha: '2026-10-19', estado: 'realizada' } as CitaEjemplo)
    expect(resumirCitasHoy(citas, hoy)).toEqual({ total: 8, realizadas: 2, programadas: 1, vencidas: 1, noAsistio: 1, canceladas: 2, reprogramadas: 1 })
    expect(resumirCitasHoy(null, hoy)).toBeNull()
  })
  it('no compara una cifra parcial en soles contra una meta total, ni convierte una meta ausente en 0%', () => {
    expect(avanceCapital(totalEnSoles(500, 100, null), totalEnSoles(1000, 0, null))).toBeNull()
    expect(avanceCapital(totalEnSoles(500, 0, null), totalEnSoles(0, 0, null))).toBeNull()
    expect(avanceCapital(totalEnSoles(1500, 0, null), totalEnSoles(1000, 0, null))).toEqual({ porcentaje: 150, brecha: 0 })
  })
  it('el capital y las operaciones por persona cuadran con el mismo corte valorado del supervisor, con TC caído', () => {
    const rpc = v.parse(CumplimientoMetasV2Schema, valorado)
    const supervisorId = rpc.vendedores[0]!.supervisor_id!
    const cumplimiento = cumplimientoDesdeRpc(rpc, supervisorId)
    const filas = filasMensualesJornada({ cumplimiento, objetivos: objetivosCero('2026-10-01'), conversion: null, supervisorId, tc: null })
    expect(filas.reduce((s, f) => s + (f.capital.total ?? 0), 0)).toBe(cumplimiento.supervisor!.capitalValorado!.equivalente_pen)
    expect(filas.reduce((s, f) => s + (f.operaciones ?? 0), 0)).toBe(operacionesConfirmadas(cumplimiento.supervisor))
    const movido = structuredClone(cumplimiento)
    movido.porVendedor = {}
    const preservadas = filasMensualesJornada({ cumplimiento: movido, objetivos: objetivosCero(), conversion: null, supervisorId, tc: 99 })
    expect(preservadas.map(f => f.capital.total)).toEqual(filas.map(f => f.capital.total))
  })
  it.each([false, true])('incluye la venta propia del supervisor y conserva el total oficial (valorado=%s)', activo => {
    const rpc = v.parse(CumplimientoMetasV2Schema, valorado)
    const supervisorId = rpc.vendedores[0]!.supervisor_id!
    const detalle = rpc.vendedores[0]!.detalles.map(d => ({ ...d, capital_objetivo: 0, contratos_objetivo: 0 }))
    rpc.fuera_ranking = [{ persona_id: supervisorId, nombre: 'Supervisor con venta propia', rol_crm: 'supervisor', motivo: 'supervisor',
      conversion: null, detalles: detalle,
      cartera: { conversiones_clientes: 0, conversiones_renovacion: 0, conversiones_upgrade: 0, operaciones_renovacion: 0, operaciones_upgrade: 0,
        capital_renovado_pen: 0, capital_renovado_usd: 0, capital_adicional_pen: 0, capital_adicional_usd: 0, renovaciones_sin_desglose: 0 } }]
    if (activo) {
      const persona = structuredClone(rpc.capital_valoracion!.personas[0]!)
      rpc.capital_valoracion!.personas.push({ ...persona, vendedor_id: supervisorId, nombre: 'Supervisor con venta propia', rol_crm: 'supervisor', en_ranking: false, supervisor_id: null })
    } else {
      delete rpc.capital_valoracion
      for (const f of rpc.vendedores) delete f.capital_valorado
    }
    const cumplimiento = cumplimientoDesdeRpc(rpc, supervisorId)
    const filas = filasMensualesJornada({ cumplimiento, objetivos: objetivosCero(rpc.periodo), conversion: null, supervisorId, tc: 3.75 })
    const propia = filas.find(f => f.id === supervisorId)!
    expect(propia).toMatchObject({ nombre: 'Supervisor con venta propia', esSupervisor: true, conversion: null })
    expect(propia.meta.total).toBeNull()
    expect(filas.reduce((s, f) => s + (f.operaciones ?? 0), 0)).toBe(operacionesConfirmadas(cumplimiento.supervisor))
    const esperado = activo ? cumplimiento.supervisor!.capitalValorado!.equivalente_pen
      : cumplimiento.supervisor!.detalles.reduce((s, d) => s + d.capitalReal * (d.moneda === 'USD' ? 3.75 : 1), 0)
    expect(filas.reduce((s, f) => s + (f.capital.total ?? 0), 0)).toBe(esperado)
    // La foto valorada conserva su identidad aunque no figure ya en la lectura viva.
    if (activo) {
      cumplimiento.supervisores = []
      expect(filasMensualesJornada({ cumplimiento, objetivos: objetivosCero(rpc.periodo), conversion: null, supervisorId, tc: null })
        .find(f => f.id === supervisorId)?.capital.total).toBe(propia.capital.total)
    }
  })
  it('sin primer corte no reconstruye capital ni operaciones desde las filas antiguas', () => {
    const rpc = v.parse(CumplimientoMetasV2Schema, valorado)
    const supervisorId = rpc.vendedores[0]!.supervisor_id!
    const cumplimiento = cumplimientoDesdeRpc(rpc, supervisorId)
    cumplimiento.valoracionCapital!.personas = []
    const filas = filasMensualesJornada({ cumplimiento, objetivos: objetivosCero(), conversion: null, supervisorId, tc: 3.5 })
    expect(filas.length).toBeGreaterThan(0)
    expect(filas.every(f => f.capital.total === null && f.operaciones === null)).toBe(true)
  })
  it('una meta de alguien sin fila de conversión no apaga la conversión oficial de los demás', () => {
    const supervisorId = 'd-sup1'
    const conversion = conversionMensualDemo(Date.parse('2026-10-18T17:00:00Z'), { alcance: 'equipo', actorId: supervisorId })
    const objetivos = objetivosCero('2026-10-01')
    objetivos.porVendedor['trasladado'] = { ...objetivos.supervisor, vendedorId: 'trasladado', nombre: 'Analista trasladado', supervisorId, supervisorNombre: 'Equipo' }
    const filas = filasMensualesJornada({ cumplimiento: null, objetivos, conversion, supervisorId, tc: null })
    const fuente = conversion.responsables.find(f => f.divisor > 0)!
    expect(fuente).toBeDefined()
    expect(filas.find(f => f.id === fuente.vendedor_id)).toMatchObject({ conversion: fuente.conversion_pct, recibidos: fuente.divisor })
    expect(filas.find(f => f.id === 'trasladado')).toMatchObject({ conversion: null, recibidos: null })
    expect(filas.find(f => f.id === fuente.vendedor_id)?.capital.total).toBeNull()
    conversion.cobertura = { ...conversion.cobertura, medible: false, motivo_no_medible: 'sin_ledger' }
    const sinCobertura = filasMensualesJornada({ cumplimiento: null, objetivos, conversion, supervisorId, tc: null })
    expect(sinCobertura.every(f => f.conversion === null && f.recibidos === null)).toBe(true)
  })
})
