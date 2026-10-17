import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { describe, it, expect, vi } from 'vitest'
import * as v from 'valibot'
vi.mock('@/lib/supabase', () => ({ sb: null }))
import { ConsultaCitasSchema, adaptarGestion, adaptarCitas } from '@/data/citas-gerencia'
import { calcularAvanceCitas } from '@/components/citas/avance'
import { defaults } from '@/components/citas/modelo'
const dir = process.env.CITAS_EVIDENCIA
if (!dir) throw new Error('CITAS_EVIDENCIA requerido: lecturas anónimas de solo lectura, nunca credenciales')
const salida: unknown[] = []
describe('Conciliación completa de la lectura comercial contra SQL independiente', () => {
 for (const mes of ['09', '10']) it(`2026-${mes}: total, cada analista y ausencia de filas perdidas`, () => {
  const evidencia = JSON.parse(readFileSync(`${dir}/real-${mes}.json`, 'utf8'))
  const p = evidencia.payload
  const fechas = new Map(evidencia.fechas.map((c: {lead_id: string; fecha_comercial: string}) => [c.lead_id, c.fecha_comercial]))
  expect(fechas.size).toBe(evidencia.fechas.length)
  p.criterio_depositos = 'fecha_comercial'
  for (const c of [...p.conversiones, ...p.gestion.conversiones]) c.fecha_comercial = fechas.get(c.lead_id) ?? null
  const esperado = evidencia.comercial
  p.testigo.comercial = { ...p.testigo, ...esperado, base_conversion: esperado.personas_entrevistadas,
   conversion_pct: Math.round(10000 * esperado.clientes_vinculados / esperado.personas_entrevistadas) / 100 }
  const datos = v.parse(ConsultaCitasSchema, p)
  const r = calcularAvanceCitas(adaptarGestion(datos)!, adaptarCitas(datos), defaults(`2026-${mes}`), datos.generado_en, 3.5)
  expect(r.total).toMatchObject({entrevistas: esperado.entrevistas, unicas: esperado.personas_entrevistadas,
   clientesPeriodo: esperado.clientes_periodo, clientes: esperado.clientes_vinculados})
  expect(r.testigoCuadra).toBe(true)
  const porAnalista = new Map(esperado.analistas.map((a: {id: string}) => [a.id, a]))
  for (const fila of r.filas) {
   const esperadoFila = porAnalista.get(fila.id) ?? {entrevistas: 0, unicas: 0, clientesPeriodo: 0, clientes: 0}
   expect(fila).toMatchObject(esperadoFila)
  }
  for (const id of porAnalista.keys()) expect(r.filas.some(f => f.id === id)).toBe(true)
  salida.push({ mes: evidencia.mes, corte: datos.generado_en, poblacion: p.gestion.poblacion.length,
   citas: p.citas.length, analistas: r.filas.length, comparadosConActividad: porAnalista.size,
   clientes: r.total.clientesPeriodo, vinculados: r.total.clientes, entrevistas: r.total.entrevistas,
   personas: r.total.unicas, porcentaje: p.testigo.comercial.conversion_pct, testigoCuadra: r.testigoCuadra })
  writeFileSync(`${dir}/conciliacion.json`, JSON.stringify(salida, null, 2)+'\n')
 })
})

for (const caso of ['2026-09', '2026-10', 'cohorte', 'renovacion']) it(`RPC SQL instalada ${caso}: contrato real y cálculo de pantalla`, () => {
 const datos = v.parse(ConsultaCitasSchema, JSON.parse(readFileSync(`${dir}/banco-${caso}.json`, 'utf8')))
 const mes = datos.periodo.desde.slice(0,7)
 const r = calcularAvanceCitas(adaptarGestion(datos)!, adaptarCitas(datos), defaults(mes), datos.generado_en, 3.5)
 expect(r.testigoCuadra).toBe(true)
 expect(r.diferenciasTestigo).toEqual([])
 expect(r.total.clientesPeriodo).toBe(caso === '2026-10' ? 1 : caso === 'renovacion' ? 3 : 4)
})

for (const archivo of readdirSync(dir!).filter(n => /^banco-matriz-\d+\.json$/.test(n))) {
 it(`reglas combinadas ${archivo}: atribución, manuales, cohorte y denominador coinciden`, () => {
  const datos = v.parse(ConsultaCitasSchema, JSON.parse(readFileSync(`${dir}/${archivo}`, 'utf8')))
  const r = calcularAvanceCitas(adaptarGestion(datos)!, adaptarCitas(datos), defaults(datos.periodo.desde.slice(0,7)), datos.generado_en, 3.5)
  expect(r.testigoCuadra).toBe(true)
  expect(r.diferenciasTestigo).toEqual([])
 })
}
