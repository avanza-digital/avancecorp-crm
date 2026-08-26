import { describe, expect, it } from 'vitest'
import { esPreviewDemo, FUNCIONES_LEADS_APROBADAS, funcionesLeadsVisibles, resolverDemoHabilitado } from './config'

describe('escaparate demo', () => {
  it('se habilita únicamente con opt-in en desarrollo o preview', () => {
    expect(resolverDemoHabilitado({ DEV: true, MODE: 'development', VITE_ENABLE_DEMO: 'true' })).toBe(true)
    expect(resolverDemoHabilitado({ DEV: false, MODE: 'preview', VITE_ENABLE_DEMO: 'true' })).toBe(true)
    expect(resolverDemoHabilitado({ DEV: false, MODE: 'production', VITE_ENABLE_DEMO: 'true' })).toBe(false)
    expect(resolverDemoHabilitado({ DEV: true, MODE: 'development' })).toBe(false)
    expect(resolverDemoHabilitado({ DEV: false, MODE: 'preview' })).toBe(false)
    expect(esPreviewDemo({ MODE: 'preview', VITE_ENABLE_DEMO: 'true' })).toBe(true)
    expect(esPreviewDemo({ MODE: 'production', VITE_ENABLE_DEMO: 'true' })).toBe(false)
  })
})

// La llave que decide qué PINTA el navegador para una cuenta real. Nació
// CERRADA (Miguel, 2026-07-16: el pipeline sale oculto para la fuerza de
// ventas) y se ABRIÓ el 2026-08-18, con el circuito de lead libre ya vivo en
// producción. Aquí queda fijado su contrato nuevo.
//
// OJO con el alcance: esto NO es un permiso. El ámbito de datos lo decide la
// RLS (`private.vendedor_ids_visibles`); esta función solo elige qué menús y
// pantallas se dibujan. Lo que se prueba es que la llave siga ABIERTA para
// quien debe y que no se derrame a quien no tiene nada que ver ahí.

describe('funcionesLeadsVisibles — la llave del pipeline de leads', () => {
  it('la llave GENERAL está abierta (si esto cambia, es una decisión de Miguel, no un descuido)', () => {
    expect(FUNCIONES_LEADS_APROBADAS).toBe(true)
  })

  it('el demo siempre las ve: es el escaparate del CRM completo', () => {
    expect(funcionesLeadsVisibles(true, 'vendedor')).toBe(true)
    expect(funcionesLeadsVisibles(true, 'supervisor')).toBe(true)
    expect(funcionesLeadsVisibles(true, 'coordinador')).toBe(true)
  })

  it('gerencia y directorio las ven (aprobación parcial 2026-07-16)', () => {
    expect(funcionesLeadsVisibles(false, 'gerencia')).toBe(true)
    expect(funcionesLeadsVisibles(false, 'directorio')).toBe(true)
  })

  it('la fuerza de ventas YA las ve — es exactamente lo que abrió la llave', () => {
    expect(funcionesLeadsVisibles(false, 'vendedor')).toBe(true)
    expect(funcionesLeadsVisibles(false, 'supervisor')).toBe(true)
  })

  it('el coordinador NO las ve ni con la llave abierta: su mundo es «Repartir leads»', () => {
    // Su ámbito de leads es ∅ (espejo de private.vendedor_ids_visibles). Sin
    // este corte, abrir la llave le regalaba «Hoy» (la única vista de leads sin
    // capacidad exigida) y un buscador de leads que nunca encuentra nada.
    expect(funcionesLeadsVisibles(false, 'coordinador')).toBe(false)
  })

  it('un rol nulo o desconocido tampoco (mínimo privilegio: la lista es cerrada)', () => {
    expect(funcionesLeadsVisibles(false, null)).toBe(false)
    expect(funcionesLeadsVisibles(false, undefined)).toBe(false)
    expect(funcionesLeadsVisibles(false, 'lo-que-sea')).toBe(false)
  })

  it('la llave manda sobre la fuerza de ventas y sobre NADIE más', () => {
    // Candado de alcance: si alguien vuelve a cerrar la llave, los roles ya
    // aprobados en julio no pueden caerse con ella (ni el demo).
    const soloLaLlaveDecide = ['vendedor', 'supervisor'].every(
      (rol) => funcionesLeadsVisibles(false, rol) === FUNCIONES_LEADS_APROBADAS,
    )
    expect(soloLaLlaveDecide).toBe(true)
    expect(funcionesLeadsVisibles(false, 'gerencia')).toBe(true)
    expect(funcionesLeadsVisibles(true, 'coordinador')).toBe(true)
  })
})
