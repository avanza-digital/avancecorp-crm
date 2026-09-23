// EL CONTRATO DE LA UNIFICACIÓN, probado en las dos direcciones.
//
// Ola 1 del plan de las doce puertas. Cada puerta unificada añadirá las claves
// que dicen DE DÓNDE salió su cifra. Por la regla de la casa el FRONT ENTRA
// PRIMERO, así que estos esquemas tienen que aceptar las dos formas:
//
//   · SIN las claves  → el servidor de hoy, que aún no las emite
//   · CON las claves  → el servidor de mañana, ya unificado
//
// 🔴 Y no es una cortesía: `CumplimientoMetasSchema` y los de distribución son
// `strictObject`, que RECHAZA EL OBJETO ENTERO ante una clave desconocida. Si
// el servidor entrase primero, esas pantallas se caerían. El auditor lo
// reprodujo el 22/09.
//
// Lo que estas pruebas afirman, y es el corazón del contrato: **la cifra no
// cambia**. El contrato DECLARA de dónde viene el número; no lo recalcula.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { metricasConversionesDemo } from './demo-inteligencia-comercial'
import { MetricasConversionesSchema } from './metricas-conversiones'

const CONTRATO = {
  es_mes_calendario: true,
  fuente: 'mensual' as const,
  sellado: false,
  ajuste_aplicado: true,
}

// El demo no emite bloque `nucleo` (es opcional), así que se le pone uno
// completo: son los campos que `NucleoConversionesSchema` exige hoy.
const NUCLEO = {
  base: 'leads asignados del mes',
  divisor: 1218,
  numerador: 51.65,
  conversion_pct: 4.24,
  cierres_no_referidos: 33,
  cierres_referidos: 6,
  referidos_recibidos: 40,
  referidos_cierran_pct: 15,
  operaciones_cartera: 11.45,
  peso_referido: 0.15,
  mes_peso: '2026-09-01',
  incluye_cartera: true,
}

const conNucleo = (demo: object, extra: Record<string, unknown> = {}) =>
  ({ ...demo, nucleo: { ...NUCLEO, ...extra } })

describe('el contrato de la unificación: el front acepta las dos formas', () => {
  it('SIN las claves (el servidor de hoy) se lee igual que siempre', () => {
    const r = v.safeParse(MetricasConversionesSchema, conNucleo(metricasConversionesDemo('2026-09-01', '2026-09-22')))
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.nucleo?.es_mes_calendario).toBeUndefined()
    expect(r.output.nucleo?.fuente).toBeUndefined()
  })

  it('CON las claves LA CIFRA NO CAMBIA, y ahora se sabe de dónde viene', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-22')
    const sin = v.safeParse(MetricasConversionesSchema, conNucleo(demo))
    const con = v.safeParse(MetricasConversionesSchema, conNucleo(demo, CONTRATO))
    expect(con.success).toBe(true)
    if (!con.success || !sin.success) return
    expect(con.output.nucleo?.divisor).toBe(sin.output.nucleo?.divisor)
    expect(con.output.nucleo?.numerador).toBe(sin.output.nucleo?.numerador)
    expect(con.output.nucleo?.conversion_pct).toBe(sin.output.nucleo?.conversion_pct)
    expect(con.output.nucleo?.fuente).toBe('mensual')
    expect(con.output.nucleo?.sellado).toBe(false)
    expect(con.output.nucleo?.ajuste_aplicado).toBe(true)
  })

  it('`fuente` solo admite los dos valores del contrato, nada inventado', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-22')
    const r = v.safeParse(MetricasConversionesSchema, conNucleo(demo, { ...CONTRATO, fuente: 'inventado' }))
    expect(r.success).toBe(false)
  })

  it('`sellado` puede ser null: «no se delegó, así que no se sabe» ≠ «no está sellado»', () => {
    const demo = metricasConversionesDemo('2026-09-01', '2026-09-22')
    const r = v.safeParse(MetricasConversionesSchema,
      conNucleo(demo, { ...CONTRATO, fuente: 'rango_vivo', sellado: null }))
    expect(r.success).toBe(true)
    if (!r.success) return
    expect(r.output.nucleo?.sellado).toBeNull()
    expect(r.output.nucleo?.fuente).toBe('rango_vivo')
  })

  // El ranking por equipo (`MetricasConversionesEquipoSchema`) recibió el mismo
  // contrato, pero NO se prueba aquí: el repo no tiene un payload válido de esa
  // forma —`conversionEquipoDemo()` devuelve un array de filas de vendedor, no
  // un paquete— y fabricarlo a mano sería probar mi fixture, no el esquema.
  // Su tolerancia queda cubierta por el typecheck y por ser el mismo patrón.
  // 📌 Cuando la Ola 1 toque esa puerta, el ensayo contra producción traerá un
  // payload real y entonces sí se prueba aquí.
})
