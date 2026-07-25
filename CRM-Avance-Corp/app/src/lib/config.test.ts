import { describe, expect, it } from 'vitest'
import { CUENTAS_PILOTO_LEADS, FUNCIONES_LEADS_APROBADAS, funcionesLeadsVisibles } from './config'

// La llave que decide qué PINTA el navegador para una cuenta real (decisión de
// Miguel 2026-07-16: el pipeline de leads sale oculto para la fuerza de ventas).
// No tenía cobertura y gobierna producción, así que aquí se fija su contrato.
//
// OJO con el alcance: esto NO es un permiso. El ámbito de datos lo decide la
// RLS (`private.vendedor_ids_visibles`); esta función solo elige qué menús y
// pantallas se dibujan. Lo que se prueba es que la llave general siga CERRADA
// y que el piloto no se derrame a nadie más.

const MIGUEL = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
const OTRO_VENDEDOR = '00000000-0000-4000-8000-0000000000ff'

describe('funcionesLeadsVisibles — la llave del pipeline de leads', () => {
  it('la llave GENERAL sigue cerrada (si esto cambia, es una decisión de Miguel, no un descuido)', () => {
    expect(FUNCIONES_LEADS_APROBADAS).toBe(false)
  })

  it('el demo siempre las ve: es el escaparate del CRM completo', () => {
    expect(funcionesLeadsVisibles(true, 'vendedor')).toBe(true)
    expect(funcionesLeadsVisibles(true, 'supervisor')).toBe(true)
  })

  it('gerencia y directorio las ven (aprobación parcial 2026-07-16)', () => {
    expect(funcionesLeadsVisibles(false, 'gerencia')).toBe(true)
    expect(funcionesLeadsVisibles(false, 'directorio')).toBe(true)
  })

  it('la fuerza de ventas NO las ve — su mundo sigue siendo Clientes/Contratos', () => {
    expect(funcionesLeadsVisibles(false, 'vendedor')).toBe(false)
    expect(funcionesLeadsVisibles(false, 'supervisor')).toBe(false)
    expect(funcionesLeadsVisibles(false, 'coordinador')).toBe(false)
  })

  it('un rol nulo o desconocido tampoco (mínimo privilegio)', () => {
    expect(funcionesLeadsVisibles(false, null)).toBe(false)
    expect(funcionesLeadsVisibles(false, undefined)).toBe(false)
    expect(funcionesLeadsVisibles(false, 'lo-que-sea')).toBe(false)
  })

  describe('piloto en producción (pedido de Miguel 2026-07-25)', () => {
    it('la cuenta del piloto SÍ las ve aunque sea vendedor', () => {
      expect(funcionesLeadsVisibles(false, 'vendedor', MIGUEL)).toBe(true)
    })

    it('NINGUNA otra cuenta se cuela por el piloto', () => {
      expect(funcionesLeadsVisibles(false, 'vendedor', OTRO_VENDEDOR)).toBe(false)
      expect(funcionesLeadsVisibles(false, 'supervisor', OTRO_VENDEDOR)).toBe(false)
      expect(funcionesLeadsVisibles(false, 'vendedor', '')).toBe(false)
      expect(funcionesLeadsVisibles(false, 'vendedor', null)).toBe(false)
      expect(funcionesLeadsVisibles(false, 'vendedor', undefined)).toBe(false)
    })

    it('el piloto tiene EXACTAMENTE una cuenta: si crece, que sea a propósito', () => {
      // Este test es el candado del alcance. Miguel pidió "solo para la cuenta
      // miguel@cacmascapital.com"; abrir una segunda cuenta debe romper aquí y
      // obligar a una decisión explícita, no colarse en un commit cualquiera.
      expect([...CUENTAS_PILOTO_LEADS]).toEqual([MIGUEL])
    })

    it('el piloto no toca el modo demo ni los roles ya aprobados', () => {
      expect(funcionesLeadsVisibles(true, 'vendedor', OTRO_VENDEDOR)).toBe(true)
      expect(funcionesLeadsVisibles(false, 'gerencia', OTRO_VENDEDOR)).toBe(true)
    })
  })
})
