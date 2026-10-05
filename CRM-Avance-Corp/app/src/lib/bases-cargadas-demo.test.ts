// El espejo DEMO de «Bases» (sin red): las mismas puertas, en memoria, con cifras que cuadran entre la hoja, el
// seguimiento y el detalle; cargar, repartir y recoger cambian lo que se ve. Solo para la demo y las capturas.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { crearFuenteDemoBases, reiniciarDemoBases } from './bases-cargadas-demo'
import type { Miembro } from './tipos'

vi.mock('@/lib/supabase', () => ({ sb: null }))

const EQUIPO: Miembro[] = [
  { perfil_id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol_crm: 'vendedor', supervisor_id: 'd-s1', activo: true },
  { perfil_id: 'd-v2', nombre_completo: 'ANALISTA DOS', rol_crm: 'vendedor', supervisor_id: 'd-s1', activo: true },
  { perfil_id: 'd-s1', nombre_completo: 'SUPERVISOR UNO', rol_crm: 'supervisor', supervisor_id: null, activo: true },
]
const fuente = () => crearFuenteDemoBases({ leads: [], equipo: EQUIPO, yo: { id: 'd-s1', rol: 'supervisor', nombre_completo: 'SUPERVISOR UNO' } })

beforeEach(() => { vi.useFakeTimers(); reiniciarDemoBases() })
afterEach(() => vi.useRealTimers())

async function esperar<T>(p: Promise<T>): Promise<T> {
  await vi.runAllTimersAsync()
  return p
}
/** El rechazo de una puerta (se engancha ANTES de correr los relojes: nada queda sin atrapar). */
async function rechazo(p: Promise<unknown>): Promise<unknown> {
  const capturado = p.then(() => null, (e: unknown) => e)
  await vi.runAllTimersAsync()
  return capturado
}

describe('demo de «Bases»', () => {
  it('dos bases de muestra cuyas cifras cuadran con el seguimiento y el detalle', async () => {
    const f = fuente()
    const bases = (await esperar(f.seguimientoBases()))!
    expect(bases.map((b) => b.nombre)).toEqual(['Feria 2025', 'Descartes de julio'])
    const feria = bases[0]!
    expect(feria.total).toBe(feria.sin_repartir + feria.repartidos)
    const porAnalista = (await esperar(f.seguimientoBase(feria.base_id)))!
    expect(porAnalista.reduce((s, a) => s + a.asignados, 0)).toBe(feria.repartidos)
    expect(porAnalista.some((a) => a.sin_tocar_3_dias > 0)).toBe(true)
    expect((await esperar(f.seguimientoBaseDetalle(feria.base_id, null, 'sin_repartir')))!).toHaveLength(feria.sin_repartir)
  })

  it('crear + cargar un lote: veredictos de juguete y la base nueva arriba; el nombre repetido se rechaza', async () => {
    const f = fuente()
    const { base_id } = await esperar(f.crearBase({ operacionId: 'op', nombre: 'Feria Lima', archivoNombre: 'x.csv' }))
    const r = await esperar(f.cargarBaseLote({ operacionId: 'op2', baseId: base_id, filas: [
      { fila: 2, nombre: 'Rosa', telefono: '+51987000001' }, { fila: 3, nombre: 'Cliente', telefono: '+51987000007' },
      { fila: 4, nombre: 'Veto', telefono: '+51987000013' }, { fila: 5, nombre: 'Rosa otra', telefono: '+51987000001' },
    ] }))
    expect(r.filas.map((x) => x.veredicto)).toEqual(['cargada', 'ya_existia', 'no_contactar', 'repetida'])
    expect((await esperar(f.seguimientoBases()))![0]).toMatchObject({ nombre: 'Feria Lima', total: 1, sin_repartir: 1 })
    expect(await rechazo(f.crearBase({ operacionId: 'op3', nombre: 'feria lima', archivoNombre: 'x.csv' }))).toMatchObject({ code: 'NOMBRE_REPETIDO' })
  })

  it('repartir en bloque (todo o nada), individual y recoger lo no tocado', async () => {
    const f = fuente()
    const feria = (await esperar(f.seguimientoBases()))![0]!
    expect(await rechazo(f.repartirBase({ operacionId: 'o', baseId: feria.base_id, reparto: { modo: 'bloque', asignaciones: [{ analista_id: 'd-v1', cantidad: feria.sin_repartir + 1 }] } })))
      .toMatchObject({ code: 'SIN_DISPONIBLES', detalle: feria.sin_repartir })
    await esperar(f.repartirBase({ operacionId: 'o2', baseId: feria.base_id, reparto: { modo: 'bloque', asignaciones: [{ analista_id: 'd-v1', cantidad: 10 }] } }))
    const libre = (await esperar(f.contactosDeBase(feria.base_id, 'sin_repartir')))![0]!
    await esperar(f.repartirBase({ operacionId: 'o3', baseId: feria.base_id, reparto: { modo: 'individual', asignaciones: [{ lead_id: libre.lead_id, analista_id: 'd-v2' }] } }))
    expect((await esperar(f.seguimientoBases()))![0]!.sin_repartir).toBe(feria.sin_repartir - 11)
    const r = await esperar(f.recogerDeBase({ operacionId: 'o4', baseId: feria.base_id, analistaId: 'd-v1' }))
    expect(r.recogidos).toBeGreaterThanOrEqual(10)
    expect((await esperar(f.seguimientoBases()))![0]!.sin_repartir).toBe(feria.sin_repartir - 11 + r.recogidos)
  })
})
