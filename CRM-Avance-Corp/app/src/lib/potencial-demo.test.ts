// Potencial en modo demo. Aquí —y solo aquí— vive el ESPEJO de la regla de
// caducidad: la demo no tiene servidor y la imita. Se prueba el espejo, que las
// marcas sembradas sean COHERENTES con él cualquier día de la semana en que se
// abra la demo (una Estrella sembrada no puede estar ya vencida, una que «bajó
// sola» tiene que tener días para haber bajado) y que marcar reinicie el reloj.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { LEADS_DEMO } from './demo'
import { sumarDiasFecha } from './potencial'
import {
  diasLunesASabado, fechaDeBajada, leerPotencialDemo, marcarPotencialDemo, nivelAlBajar, potencialDemoDe,
  reiniciarPotencialDemo, suscribirPotencialDemo,
} from './potencial-demo'

afterEach(() => { reiniciarPotencialDemo() })

/** Dos semanas seguidas: cubre todos los días de la semana como «hoy». */
const HOYS = Array.from({ length: 14 }, (_, i) => sumarDiasFecha('2026-09-28', i))

describe('espejo demo de la regla de caducidad', () => {
  it('cuenta días completos de lunes a sábado, sin ninguna de las dos puntas', () => {
    // Lunes 5 → domingo 11: martes, miércoles, jueves, viernes y sábado.
    expect(diasLunesASabado('2026-10-05', '2026-10-11')).toBe(5)
    // El domingo de en medio no cuenta.
    expect(diasLunesASabado('2026-10-05', '2026-10-12')).toBe(5)
    expect(diasLunesASabado('2026-10-05', '2026-10-13')).toBe(6)
    // El mismo día y el día siguiente: cero días completos.
    expect(diasLunesASabado('2026-10-05', '2026-10-05')).toBe(0)
    expect(diasLunesASabado('2026-10-05', '2026-10-06')).toBe(0)
  })

  it('Estrella baja tras 5 días completos y Tibio tras 10; Frío no baja', () => {
    // Marcada un lunes: martes a sábado son los 5 días → baja la madrugada del domingo.
    expect(fechaDeBajada('estrella', '2026-10-05')).toBe('2026-10-11')
    // Tibio: martes a sábado (5), domingo fuera, lunes a viernes (5) → sábado 17.
    expect(fechaDeBajada('tibio', '2026-10-05')).toBe('2026-10-17')
    expect(fechaDeBajada('frio', '2026-10-05')).toBeNull()
  })

  it.each(['estrella', 'tibio'] as const)('la fecha de bajada de %s es el PRIMER día que cumple la regla', (nivel) => {
    const limite = nivel === 'estrella' ? 5 : 10
    for (let i = 0; i < 14; i += 1) {
      const reloj = sumarDiasFecha('2026-09-28', i)
      const baja = fechaDeBajada(nivel, reloj)
      expect(baja).not.toBeNull()
      expect(diasLunesASabado(reloj, baja as string)).toBeGreaterThanOrEqual(limite)
      expect(diasLunesASabado(reloj, sumarDiasFecha(baja as string, -1))).toBeLessThan(limite)
    }
  })

  it('a qué nivel baja cada uno al cumplirse su plazo', () => {
    expect([nivelAlBajar('estrella'), nivelAlBajar('tibio'), nivelAlBajar('frio')]).toEqual(['tibio', 'frio', null])
  })
})

describe('marcas sembradas', () => {
  it('todas apuntan a leads ABIERTOS de la demo', () => {
    const abiertos = new Map(LEADS_DEMO.filter((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado').map((l) => [l.id, l]))
    const sembrados = [...leerPotencialDemo().keys()]
    expect(sembrados.length).toBeGreaterThanOrEqual(4)
    for (const id of sembrados) expect(abiertos.has(id), `${id} debe ser un lead abierto de LEADS_DEMO`).toBe(true)
  })

  it('enseña los tres niveles y una marca que bajó sola', () => {
    const items = [...leerPotencialDemo().keys()].map((id) => potencialDemoDe(id, leerPotencialDemo(), { puedeMarcar: true, hoy: '2026-10-01' }))
    expect(new Set(items.map((i) => i.nivel))).toEqual(new Set(['frio', 'tibio', 'estrella']))
    expect(items.some((i) => i.origen === 'caducidad' && i.nivel_marcado === 'estrella' && i.nivel === 'tibio')).toBe(true)
  })

  it.each(HOYS)('son coherentes con la regla si la demo se abre el %s', (hoy) => {
    for (const id of leerPotencialDemo().keys()) {
      const item = potencialDemoDe(id, leerPotencialDemo(), { puedeMarcar: true, hoy })
      const dias = item.dias_sin_gestion ?? 0
      if (item.origen === 'caducidad') {
        // Bajó de Estrella a Tibio: ya pasó los 5 días y aún no llega a los 10.
        expect(dias, id).toBeGreaterThanOrEqual(5)
        expect(dias, id).toBeLessThan(10)
      } else if (item.nivel === 'estrella') {
        expect(dias, id).toBeLessThan(5)
      } else if (item.nivel === 'tibio') {
        expect(dias, id).toBeLessThan(10)
      }
      // Ninguna marca que aún baja está vencida: su fecha es posterior a hoy.
      if (item.baja_el != null) expect(item.baja_el > hoy, `${id}: ${item.baja_el} > ${hoy}`).toBe(true)
      expect(item.baja_a).toBe(item.nivel === 'estrella' ? 'tibio' : item.nivel === 'tibio' ? 'frio' : null)
    }
  })
})

describe('marcar en demo', () => {
  it('un lead sin marca llega como «sin marca», con el permiso de quien pregunta', () => {
    const foto = leerPotencialDemo()
    expect(potencialDemoDe('l15', foto, { puedeMarcar: true, hoy: '2026-10-01' })).toEqual({
      lead_id: 'l15', nivel: null, origen: null, nivel_marcado: null, marcado_en: null,
      dias_sin_gestion: null, baja_a: null, baja_el: null, puede_marcar: true,
    })
    expect(potencialDemoDe('l15', foto, { puedeMarcar: false, hoy: '2026-10-01' }).puede_marcar).toBe(false)
  })

  it('marcar reinicia el reloj, avisa a quien escucha y no muta la foto anterior', () => {
    const antes = leerPotencialDemo()
    const avisar = vi.fn()
    const soltar = suscribirPotencialDemo(avisar)
    // «l16» venía de Estrella a Tibio por días sin gestión: volver a marcarlo lo deja limpio.
    marcarPotencialDemo('l16', 'estrella', Date.parse('2026-10-01T15:00:00Z'))
    expect(avisar).toHaveBeenCalledTimes(1)
    expect(leerPotencialDemo()).not.toBe(antes)
    expect(potencialDemoDe('l16', antes, { puedeMarcar: true, hoy: '2026-10-01' }).origen).toBe('caducidad')
    // En demo SÍ se calcula cuándo baja: aquí el espejo hace de servidor.
    expect(potencialDemoDe('l16', leerPotencialDemo(), { puedeMarcar: true, hoy: '2026-10-01' })).toEqual({
      lead_id: 'l16', nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella', dias_sin_gestion: 0,
      // Jueves 1: viernes 2, sábado 3, lunes 5, martes 6 y miércoles 7 → jueves 8.
      baja_a: 'tibio', baja_el: '2026-10-08', marcado_en: '2026-10-01T15:00:00.000Z', puede_marcar: true,
    })
    soltar()
    marcarPotencialDemo('l15', 'frio')
    expect(avisar).toHaveBeenCalledTimes(1)
  })

  it('la marca puesta en la sesión envejece con los días: su reloj es el día en que se marcó', () => {
    marcarPotencialDemo('l15', 'estrella', Date.parse('2026-10-01T15:00:00Z'))
    // Tres días después (domingo 4): viernes 2 y sábado 3 ya pasaron completos.
    expect(potencialDemoDe('l15', leerPotencialDemo(), { puedeMarcar: true, hoy: '2026-10-04' })).toMatchObject({
      nivel: 'estrella', dias_sin_gestion: 2, baja_el: '2026-10-08',
    })
  })

  it('una marca hecha de madrugada en UTC cuenta en su día de Lima', () => {
    // 03:00 UTC del 2 de octubre = 22:00 del jueves 1 en Lima.
    marcarPotencialDemo('l15', 'estrella', Date.parse('2026-10-02T03:00:00Z'))
    expect(potencialDemoDe('l15', leerPotencialDemo(), { puedeMarcar: true, hoy: '2026-10-01' }).baja_el).toBe('2026-10-08')
  })

  it('reiniciar devuelve las marcas sembradas', () => {
    marcarPotencialDemo('l15', 'estrella')
    expect(leerPotencialDemo().has('l15')).toBe(true)
    reiniciarPotencialDemo()
    expect(leerPotencialDemo().has('l15')).toBe(false)
  })
})
