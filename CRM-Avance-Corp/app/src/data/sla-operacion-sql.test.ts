import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { ColaSlaPaginaSchema, ConfiguracionSlaV2Schema, EstadosSlaV2Schema } from '@/lib/sla-operacion'
import muestra from './sla-operacion-sql.fixture.json'
import previa from './sla-operacion-previa-sql.fixture.json'

// Respuesta real del banco PostgreSQL 17 con N1/N2/N3, actor y oportunidad
// sintéticos. Vigila el límite SQL/navegador, sin contactar producción.
describe('contratos sobre respuestas reales del banco SQL SLA', () => {
  it('acepta la página emitida por PostgreSQL', () => {
    expect(v.safeParse(ColaSlaPaginaSchema, muestra.cola).success).toBe(true)
  })
  it('acepta el estado emitido por PostgreSQL', () => {
    expect(v.safeParse(EstadosSlaV2Schema, muestra.estado).success).toBe(true)
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
