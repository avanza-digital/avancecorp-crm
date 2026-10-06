import { describe, expect, it } from 'vitest'
import { compararPendientes, instantePendiente, pendientesDesdeDemo, unirPaginasPendientes, validarPaginaPendientes } from './gestion-diaria-pendientes'
import { idPendiente, paginaPendientes, pedidoPendientes, tareaPendiente } from './gestion-diaria-pendientes.fixture'
import type { Tarea } from './tipos'

describe('Contrato estricto de pendientes del supervisor', () => {
  it('acepta vacío confirmado, título vacío, referencias ocultas y las tres anclas', () => {
    expect(validarPaginaPendientes(paginaPendientes([]), pedidoPendientes)).not.toBeNull()
    const items = [tareaPendiente(10, { titulo: '', lead_id: null, lead_nombre: null }),
      tareaPendiente(11, { referencia_tipo: 'perfil', lead_id: null, lead_nombre: null }),
      tareaPendiente(12, { referencia_tipo: 'postventa', lead_id: null, lead_nombre: null })]
    expect(validarPaginaPendientes(paginaPendientes(items), pedidoPendientes)?.items).toHaveLength(3)
  })
  it.each([
    { version: 99 }, { zona: 'UTC' }, { supervisor_id: idPendiente(9) }, { analista_id: idPendiente(9) },
    { solo_vencidas: true }, { limite: 101 }, { generado_en: 'infinity' }, { pendientes_al: '2026-02-30T12:00:00Z' },
    { resumen: { tareas_pendientes: 1, tareas_vencidas: 2 } }, { resumen: { tareas_pendientes: 1.5, tareas_vencidas: 1 } },
    { hay_mas: true }, { items: [] }, { telefono: 'dato no permitido' },
    { items: [tareaPendiente(), tareaPendiente()] }, { items: [tareaPendiente(11), tareaPendiente(10)] },
    { items: [tareaPendiente(10, { vendedor_id: idPendiente(9) })] },
    { items: [tareaPendiente(10, { lead_nombre: null })] },
    { items: [tareaPendiente(10, { lead_nombre: ' ' })] },
    { items: [tareaPendiente(10, { referencia_tipo: 'perfil' })] },
    { items: [tareaPendiente(10, { vence_en: '2026-09-23T99:00:00Z' })] },
  ])('rechaza toda la respuesta dañada, sin descartar filas: %j', cambio => {
    expect(validarPaginaPendientes({ ...paginaPendientes(), ...cambio }, pedidoPendientes)).toBeNull()
  })
  it('valida límite más sonda, cursores coherentes y avance estricto con empate de fecha', () => {
    const items = Array.from({ length: 25 }, (_, i) => tareaPendiente(10 + i))
    const cursor = { despues_de: items[24]!.vence_en, despues_id: items[24]!.id }
    const pagina = paginaPendientes(items, { resumen: { tareas_pendientes: 26, tareas_vencidas: 26 }, hay_mas: true, siguiente_cursor: cursor })
    expect(validarPaginaPendientes(pagina, pedidoPendientes)).not.toBeNull()
    expect(validarPaginaPendientes({ ...pagina, siguiente_cursor: { ...cursor, despues_id: items[0]!.id } }, pedidoPendientes)).toBeNull()
    expect(validarPaginaPendientes(paginaPendientes([tareaPendiente(35)]), { ...pedidoPendientes, cursor })).not.toBeNull()
    expect(validarPaginaPendientes(paginaPendientes([items[24]!]), { ...pedidoPendientes, cursor })).toBeNull()
    expect(validarPaginaPendientes(paginaPendientes(), { ...pedidoPendientes, cursor: { ...cursor, despues_de: 'infinity' } })).toBeNull()
  })
  it('conserva microsegundos y no declara vencida una tarea en el mismo instante', () => {
    expect(instantePendiente('2026-09-23T15:00:00.000002Z')! - instantePendiente('2026-09-23T10:00:00.000001-05:00')!).toBe(1n)
    expect(compararPendientes(tareaPendiente(99), tareaPendiente(1, { vence_en: '2026-09-23T15:00:00.000002Z' }))).toBeLessThan(0)
    const p = paginaPendientes([tareaPendiente(10, { vence_en: '2026-09-23T17:00:00.000001Z' })], { solo_vencidas: true })
    expect(validarPaginaPendientes(p, { ...pedidoPendientes, soloVencidas: true })).toBeNull()
  })
  it('una tarea reprogramada entre páginas aparece una sola vez con su última fecha', () => {
    const nueva = tareaPendiente(10, { vence_en: '2026-09-25T15:00:00Z' })
    expect(unirPaginasPendientes([paginaPendientes([tareaPendiente(10), tareaPendiente(11)]), paginaPendientes([nueva])])).toEqual([tareaPendiente(11), nueva])
  })
  it('demo recorre más de mil tareas, filtra por responsable y no necesita un lead visible', () => {
    const tareas = Array.from({ length: 1007 }, (_, i) => ({ ...tareaPendiente(i + 10), activo: true, reprogramaciones: 0, creado_en: '2026-09-23T12:00:00Z', lead_id: idPendiente(3), perfil_id: null, inversionista_id: null })) as Tarea[]
    tareas.push({ ...tareas[0]!, vendedor_id: idPendiente(9) }, { ...tareas[0]!, activo: false }, { ...tareas[0]!, estado: 'completada' })
    let cursor = null as typeof pedidoPendientes.cursor
    const ids = new Set<string>()
    do {
      const p = pendientesDesdeDemo({ ...pedidoPendientes, cursor }, tareas, [], Date.parse('2026-09-23T17:00:00Z'))
      expect(p.resumen.tareas_pendientes).toBe(1007)
      expect(p.items.every(t => t.lead_id === null && t.lead_nombre === null)).toBe(true)
      p.items.forEach(t => ids.add(t.id)); cursor = p.siguiente_cursor
    } while (cursor)
    expect(ids.size).toBe(1007)
    expect(() => pendientesDesdeDemo(pedidoPendientes, [{ ...tareas[0]!, perfil_id: idPendiente(2) }], [], Date.now())).toThrow('integridad')
  })
})
