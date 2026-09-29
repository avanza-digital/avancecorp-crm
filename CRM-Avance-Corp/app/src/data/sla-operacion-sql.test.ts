import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ColaDiaPaginaSchema, ColaSlaPaginaSchema, ConfiguracionSlaV2Schema, EstadosSlaV2Schema, ResumenAvisosSlaSchema } from '@/lib/sla-operacion'
import { ordenarColaDiaria } from '@/lib/gestion-diaria-analista'
import muestra from './sla-operacion-sql.test.fixture.json'
import colaDiaV3 from './sla-operacion-cola-v3-sql.test.fixture.json'
import previa from './sla-operacion-previa-sql.fixture.json'

// Respuesta real del banco PostgreSQL 17 con N1/N2/N3 y avisos, actor y oportunidad
// sintéticos. Vigila el límite SQL/navegador, sin contactar producción.
describe('contratos sobre respuestas reales del banco SQL SLA', () => {
  it('acepta la página emitida por PostgreSQL', () => {
    expect(v.safeParse(ColaSlaPaginaSchema, muestra.cola).success).toBe(true)
  })
  it('acepta el estado emitido por PostgreSQL', () => {
    expect(v.safeParse(EstadosSlaV2Schema, muestra.estado).success).toBe(true)
  })
  it('acepta el resumen emitido por PostgreSQL y concilia sus oportunidades con la cola', () => {
    expect(v.safeParse(ResumenAvisosSlaSchema, muestra.resumen).success).toBe(true)
    expect(muestra.resumen.total_oportunidades).toBe(muestra.cola.total_items)
  })
  it('acepta la configuración emitida por PostgreSQL', () => {
    expect(v.safeParse(ConfiguracionSlaV2Schema, muestra.configuracion).success).toBe(true)
  })
  it('acepta la vista previa de reglas aprobadas antes de publicarlas', () => {
    const resultado = v.safeParse(ConfiguracionSlaV2Schema, previa)
    expect(resultado.success).toBe(true)
    if (resultado.success) expect(resultado.output.inicializacion_aprobada?.disponible).toBe(true)
  })
})

// Respuesta real de `crm.cola_accion_v3_fn` capturada el 29/09/2026 en el banco Docker a
// paridad con producción (migración 20260929004455), con la sesión de un analista del
// banco: sus leads de la ventana SLA y dos tareas de un cliente del portal (una vencida,
// una de hoy) sembradas en una transacción que se deshizo. Datos sintéticos.
describe('contrato de la cola del día v3 sobre la respuesta real del banco SQL', () => {
  it('acepta la página emitida por PostgreSQL, con leads y clientes', () => {
    const resultado = v.safeParse(ColaDiaPaginaSchema, colaDiaV3)
    expect(resultado.success).toBe(true)
    if (!resultado.success) return
    const clientes = resultado.output.items.filter((i) => i.lead_id === null)
    expect(clientes.map((i) => i.bucket)).toEqual(['tarea_vencida', 'tarea_hoy'])
    expect(resultado.output.totales.clientes).toBe(clientes.length)
    // Sin teléfono ni responsable en el payload (decisión del plan v2).
    expect(JSON.stringify(clientes)).not.toMatch(/telefono|responsable_id/)
  })
  it('la v2 NO acepta la página v3 (claves de caché separadas por algo)', () => {
    expect(v.safeParse(ColaSlaPaginaSchema, colaDiaV3).success).toBe(false)
  })
  it('ordena la página real en el día del analista: clientes en «Vencidas» y «Hoy», una fila por tarea', () => {
    const resultado = v.parse(ColaDiaPaginaSchema, colaDiaV3)
    const filas = ordenarColaDiaria(resultado.items, [])
    const clientes = filas.filter((f) => f.tipo === 'cliente')
    expect(clientes.map((f) => [f.grupo, f.nombre_completo])).toEqual([
      ['tarea_vencida', 'CLIENTE BANCARIO DEMO'], ['tarea_hoy', 'CLIENTE BANCARIO DEMO'],
    ])
    expect(new Set(filas.map((f) => f.clave)).size).toBe(filas.length)
  })
})
