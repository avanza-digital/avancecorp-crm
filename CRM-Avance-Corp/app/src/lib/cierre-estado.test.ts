// El contrato del front con crm.cierres_estado_fn y —lo que de verdad importa—
// la regla de cuándo se le ofrece a gerencia «Anular el cierre».
//
// El caso que justifica el archivo entero es el de la AUSENCIA: el servidor solo
// manda los leads que tienen algo que decir, así que «no viene» significa «cerró
// en Avance y no está anulado». Si ese default se escribiera en cada pantalla,
// una diría que sí y otra que no sobre el mismo lead.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  CierresEstadoSchema,
  estadoDelCierre,
  indexarCierresEstado,
  normalizarLeadIds,
  puedeAnularCierreAvance,
  type CierreEstado,
} from './cierre-estado'

const LEAD = '41000000-0000-4000-8000-000000001101'
const OTRO = '41000000-0000-4000-8000-000000001102'

const COOP: CierreEstado = {
  lead_id: LEAD,
  canal: 'cooperativa',
  anulado_en: null,
  motivo: null,
}
const AVANCE_ANULADO: CierreEstado = {
  lead_id: LEAD,
  canal: 'avance',
  anulado_en: '2026-08-14T15:04:05.000Z',
  motivo: 'El depósito no existe en el estado de cuenta',
}

describe('CierresEstadoSchema', () => {
  it('acepta el payload del servidor', () => {
    const r = v.safeParse(CierresEstadoSchema, [COOP, AVANCE_ANULADO])
    expect(r.success).toBe(true)
  })

  it('tolera una clave nueva del servidor (un bundle viejo no debe reventar)', () => {
    const r = v.safeParse(CierresEstadoSchema, [{ ...COOP, anulado_por_nombre: 'X' }])
    expect(r.success).toBe(true)
  })

  it('RECHAZA un canal desconocido: cambia qué botón se ofrece', () => {
    const r = v.safeParse(CierresEstadoSchema, [{ ...COOP, canal: 'banco' }])
    expect(r.success).toBe(false)
  })

  it('rechaza un lead_id que no es uuid', () => {
    const r = v.safeParse(CierresEstadoSchema, [{ ...COOP, lead_id: 'x' }])
    expect(r.success).toBe(false)
  })
})

describe('estadoDelCierre — el default de la AUSENCIA', () => {
  it('un lead que no viene es Avance y no está anulado', () => {
    expect(estadoDelCierre(undefined)).toEqual({
      canal: 'avance',
      anulado: false,
      anuladoEn: null,
      motivo: null,
    })
  })

  it('un coop sin anular NO cuenta como anulado', () => {
    expect(estadoDelCierre(COOP).anulado).toBe(false)
    expect(estadoDelCierre(COOP).canal).toBe('cooperativa')
  })

  it('un anulado trae fecha y motivo, que es lo que se pinta', () => {
    const e = estadoDelCierre(AVANCE_ANULADO)
    expect(e.anulado).toBe(true)
    expect(e.motivo).toBe('El depósito no existe en el estado de cuenta')
  })
})

describe('puedeAnularCierreAvance', () => {
  const base = { rol: 'gerencia', etapa: 'convertido', estado: undefined }

  it('gerencia puede anular un convertido de Avance sano', () => {
    expect(puedeAnularCierreAvance(base)).toBe(true)
  })

  it('nadie más puede, aunque vea el lead', () => {
    for (const rol of ['vendedor', 'supervisor', 'coordinador', 'directorio', null, undefined]) {
      expect(puedeAnularCierreAvance({ ...base, rol })).toBe(false)
    }
  })

  it('un lead que no está convertido no tiene cierre que anular', () => {
    for (const etapa of ['nuevo', 'contactado', 'propuesta_enviada', 'descartado']) {
      expect(puedeAnularCierreAvance({ ...base, etapa })).toBe(false)
    }
  })

  // ⚠️ EL CASO DE PRODUCCIÓN. Al 2026-08-14 el ÚNICO lead convertido que hay en
  // producción cerró en cooperativa: si esta condición faltara, el primer y único
  // botón que gerencia vería sería justo el que la RPC rechaza.
  it('un cierre en COOPERATIVA no se anula por aquí', () => {
    expect(puedeAnularCierreAvance({ ...base, estado: COOP })).toBe(false)
  })

  it('un cierre ya anulado no se vuelve a anular (es de una sola dirección)', () => {
    expect(puedeAnularCierreAvance({ ...base, estado: AVANCE_ANULADO })).toBe(false)
  })
})

describe('normalizarLeadIds', () => {
  it('quita duplicados y ordena, para que la clave de caché sea estable', () => {
    expect(normalizarLeadIds([OTRO, LEAD, OTRO])).toEqual([LEAD, OTRO])
  })

  it('dos listas con el mismo contenido en otro orden dan la MISMA clave', () => {
    expect(normalizarLeadIds([LEAD, OTRO])).toEqual(normalizarLeadIds([OTRO, LEAD]))
  })
})

describe('indexarCierresEstado', () => {
  it('cruza por lead y deja fuera a los que no vinieron', () => {
    const mapa = indexarCierresEstado([COOP])
    expect(mapa.get(LEAD)?.canal).toBe('cooperativa')
    expect(mapa.get(OTRO)).toBeUndefined()
  })
})
