import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import activo from './__fixtures__/capital-valorado/activo.json'
import pendiente from './__fixtures__/capital-valorado/pendiente.json'
import sellado from './__fixtures__/capital-valorado/sellado.json'
import { CapitalResumenSchema, sumarCapitalValorado } from './capital-valorado'
import { CumplimientoMetasSchema, CumplimientoMetasV2Schema, cumplimientoDesdeRpc } from './objetivos'
import { clasificarRankingCapitalTotal } from './conversion-vendedores'

// Salidas del banco SQL real: verificar-cortes-local.mjs --fixtures.
// Las fuentes son sintéticas; se ejecutan las funciones y el cierre del CRM.
describe('capital aceptado por operación desde octubre', () => {
  it('agrega al equipo el capital fijo propio del supervisor sin añadir meta individual', () => {
    const respuesta = v.parse(CumplimientoMetasV2Schema, activo)
    const persona = respuesta.capital_valoracion!.personas[0]!
    const actor = persona.supervisor_id!
    const antes = cumplimientoDesdeRpc(respuesta, actor)
    respuesta.capital_valoracion!.personas.push({ ...persona, vendedor_id: actor, rol_crm: 'supervisor', en_meta: false, en_ranking: false,
      capital_valorado: { ...persona.capital_valorado, objetivo_pen: 0 } })
    const despues = cumplimientoDesdeRpc(respuesta, actor)
    expect(despues.supervisor?.capitalValorado?.equivalente_pen).toBe(148000)
    expect(despues.supervisor?.conversionObjetivo).toBe(antes.supervisor?.conversionObjetivo)
    expect(despues.supervisor?.capitalValorado?.objetivo_pen).toBe(100000)
  })

  it.each([['abierto', activo, 74000], ['pendiente', pendiente, 74000], ['sellado', sellado, 80000]] as const)(
    'valida la respuesta SQL %s y conserva su total sin consultar una tasa', (_nombre, fixture, total) => {
      const respuesta = v.parse(CumplimientoMetasV2Schema, fixture)
      const mapeado = cumplimientoDesdeRpc(respuesta)
      expect(mapeado.valoracionCapital).toBeDefined()
      const a = clasificarRankingCapitalTotal([], {}, {}, 3.4, mapeado.valoracionCapital)
      const b = clasificarRankingCapitalTotal([], {}, {}, 3.1, mapeado.valoracionCapital)
      expect(a.conPuesto).toEqual(b.conPuesto)
      expect(a.conPuesto[0]?.capitalTotal).toBe(total)
      expect(a.conPuesto[0]?.metaCapital).toBe(100000)
      expect(a.tc).toBeNull()
      expect(v.safeParse(CumplimientoMetasSchema, fixture).success).toBe(false)
    },
  )

  it('mantiene los pendientes fuera de los puestos y conserva la fecha del último corte', () => {
    const respuesta = v.parse(CumplimientoMetasV2Schema, pendiente)
    const valoracion = respuesta.capital_valoracion!
    expect(valoracion.cobertura.estado).toBe('pendiente')
    expect(valoracion.cobertura.pendientes).toEqual({ cantidad: 1, pen: 0, usd: 20000 })
    expect(valoracion.cobertura.ventas_pendientes[0]?.motivo).toBe('cotizacion_pendiente')
    expect(valoracion.personas[0]?.capital_valorado.corte).toBe(valoracion.cobertura.corte)
    const sinCorte = { ...valoracion, corte_id: null, personas: [], cobertura: { ...valoracion.cobertura, corte: null, estado: 'sin_corte' as const } }
    expect(clasificarRankingCapitalTotal([], {}, {}, 3.4, sinCorte).conPuesto).toEqual([])
  })

  it('suma por céntimos solo valoraciones del mismo corte; una fila ausente no se vuelve cero', () => {
    const capital = v.parse(CapitalResumenSchema, activo.capital_valoracion.personas[0]!.capital_valorado)
    expect(sumarCapitalValorado([capital, capital])?.equivalente_pen).toBe(148000)
    expect(sumarCapitalValorado([capital, null])).toBeNull()
    expect(sumarCapitalValorado([capital, undefined])).toBeNull()
    expect(sumarCapitalValorado([capital, { ...capital, corte_id: '10000000-0000-4000-8000-000000000000' }])).toBeNull()
    expect(sumarCapitalValorado([undefined])).toBeUndefined()
  })
})
