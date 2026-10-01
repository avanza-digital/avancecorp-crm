// Potencial del lead: el contrato con `crm.potencial_leads_fn`, el instante
// optimista (que NO predice nada) y los textos de la ficha.
// La regla de caducidad no vive en este módulo: es del servidor, y su espejo
// para la demo se prueba en potencial-demo.test.ts.
// Fechas: los días son de CALENDARIO de Lima ('YYYY-MM-DD'); la suite corre con
// TZ = America/Lima y aun así nada aquí debe depender de la zona del proceso.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import * as potencial from './potencial'
import {
  diaEnPalabras, indexarPotencial, notaPotencial, potencialRecienMarcado, PotencialLeadsSchema, sumarDiasFecha,
  type PotencialLead,
} from './potencial'

const LEAD = '11111111-1111-4111-8111-111111111111'
/** Jueves 1 de octubre de 2026. */
const HOY = '2026-10-01'
const MANANA = '2026-10-02'

function item(sobre: Partial<PotencialLead> = {}): PotencialLead {
  return {
    lead_id: LEAD, nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella',
    marcado_en: '2026-09-29T15:00:00Z', dias_sin_gestion: 1, baja_a: 'tibio', baja_el: '2026-10-06',
    puede_marcar: true, ...sobre,
  }
}
const SIN_MARCA = item({ nivel: null, origen: null, nivel_marcado: null, marcado_en: null, dias_sin_gestion: null, baja_a: null, baja_el: null })

describe('contrato de crm.potencial_leads_fn', () => {
  const payload = { version: 1, habilitada: true, items: [item(), SIN_MARCA] }

  it('acepta el sobre con marcas y con leads sin marca', () => {
    const r = v.safeParse(PotencialLeadsSchema, payload)
    expect(r.success).toBe(true)
    expect(r.success && r.output.items.map((i) => i.nivel)).toEqual(['estrella', null])
  })

  it('una Estrella puede llegar con `baja_a: frio`: el servidor dice el nivel de ESE día', () => {
    const r = v.safeParse(PotencialLeadsSchema, { ...payload, items: [item({ dias_sin_gestion: 9, baja_a: 'frio', baja_el: MANANA })] })
    expect(r.success && r.output.items[0]).toMatchObject({ nivel: 'estrella', baja_a: 'frio', baja_el: MANANA })
  })

  it('una clave nueva del servidor no rompe un bundle viejo', () => {
    const r = v.safeParse(PotencialLeadsSchema, { ...payload, novedad: 1, items: [{ ...item(), sugerencia: 'tibio' }] })
    expect(r.success).toBe(true)
  })

  it.each([
    ['otra versión', { ...payload, version: 2 }],
    ['un nivel desconocido', { ...payload, items: [{ ...item(), nivel: 'caliente' }] }],
    ['un origen desconocido', { ...payload, items: [{ ...item(), origen: 'jev' }] }],
    ['un lead_id que no es uuid', { ...payload, items: [{ ...item(), lead_id: 'l1' }] }],
    ['una fecha de bajada con hora', { ...payload, items: [{ ...item(), baja_el: '2026-10-06T05:10:00Z' }] }],
    ['días negativos', { ...payload, items: [{ ...item(), dias_sin_gestion: -1 }] }],
    ['sin puede_marcar', { ...payload, items: [{ ...item(), puede_marcar: undefined }] }],
    ['nulo', null],
  ])('rechaza %s', (_caso, crudo) => {
    expect(v.safeParse(PotencialLeadsSchema, crudo).success).toBe(false)
  })

  it('indexa por lead', () => {
    expect(indexarPotencial([item()]).get(LEAD)?.nivel).toBe('estrella')
  })
})

describe('instante optimista (sesión real)', () => {
  const ahora = Date.parse('2026-10-01T15:00:00Z')

  it.each(['frio', 'tibio', 'estrella'] as const)('%s recién marcado: el nivel y el reloj a cero; NO predice cuándo ni a qué baja', (nivel) => {
    expect(potencialRecienMarcado({ lead_id: LEAD, puede_marcar: true }, nivel, ahora)).toEqual({
      lead_id: LEAD, nivel, origen: 'manual', nivel_marcado: nivel,
      marcado_en: '2026-10-01T15:00:00.000Z', dias_sin_gestion: 0,
      baja_a: null, baja_el: null, puede_marcar: true,
    })
  })

  it('conserva el permiso que dijo el servidor', () => {
    expect(potencialRecienMarcado({ lead_id: LEAD, puede_marcar: false }, 'tibio', ahora).puede_marcar).toBe(false)
  })

  it('la regla de caducidad NO se copia en este módulo: es del servidor (su espejo es solo de la demo)', () => {
    // Si alguien vuelve a traer el espejo aquí, la sesión real volvería a poder
    // adelantar una fecha que el servidor no dijo.
    for (const nombre of ['fechaDeBajada', 'diasLunesASabado', 'nivelAlBajar']) {
      expect(Object.keys(potencial), nombre).not.toContain(nombre)
    }
  })
})

describe('fechas de calendario', () => {
  it('el día en palabras no depende de la zona del proceso', () => {
    expect(diaEnPalabras('2026-10-11')).toBe('domingo 11 de octubre')
    expect(diaEnPalabras('2026-01-01')).toBe('jueves 1 de enero')
  })

  it('sumar días cruza meses y años', () => {
    expect(sumarDiasFecha('2026-12-31', 1)).toBe('2027-01-01')
    expect(sumarDiasFecha('2026-10-01', -1)).toBe('2026-09-30')
  })
})

describe('nota de la ficha', () => {
  const contexto = { cerrado: false, hoy: HOY }

  it('sin marca: dice quién la cambia solo a quien puede marcar', () => {
    expect(notaPotencial(SIN_MARCA, contexto)).toBe('Sin marcar. La cambian el analista del lead y su supervisor.')
    expect(notaPotencial({ ...SIN_MARCA, puede_marcar: false }, contexto)).toBe('Sin marcar.')
    expect(notaPotencial(SIN_MARCA, { cerrado: true, hoy: HOY })).toBe('Sin marcar.')
  })

  it('lead cerrado con marca: queda congelada', () => {
    expect(notaPotencial(item(), { cerrado: true, hoy: HOY })).toBe('Lead cerrado: la marca ya no cambia.')
  })

  it('bajó sola: de qué nivel a cuál y con cuántos días sin gestión', () => {
    const bajo = item({ nivel: 'tibio', origen: 'caducidad', nivel_marcado: 'estrella', dias_sin_gestion: 6, baja_a: 'frio', baja_el: '2026-10-09' })
    expect(notaPotencial(bajo, contexto)).toBe('Bajó sola de Estrella a Tibio: 6 días sin gestión.')
    expect(notaPotencial({ ...bajo, nivel: 'frio', nivel_marcado: 'tibio', dias_sin_gestion: 10, baja_a: null, baja_el: null }, contexto))
      .toBe('Bajó sola de Tibio a Frío: 10 días sin gestión.')
    expect(notaPotencial({ ...bajo, dias_sin_gestion: 1 }, contexto)).toBe('Bajó sola de Estrella a Tibio: 1 día sin gestión.')
    expect(notaPotencial({ ...bajo, dias_sin_gestion: null }, contexto)).toBe('Bajó sola de Estrella a Tibio.')
  })

  it('frío puesto a mano no baja más', () => {
    expect(notaPotencial(item({ nivel: 'frio', nivel_marcado: 'frio', baja_a: null, baja_el: null }), contexto))
      .toBe('Frío no baja más. Solo cambia si lo cambian el analista o su supervisor.')
  })

  it('cuándo baja: la próxima madrugada, mañana o un día con nombre', () => {
    // Antes de la última pasada de la madrugada, una marca vencida trae `baja_el` = hoy.
    expect(notaPotencial(item({ baja_el: HOY }), contexto)).toBe('Baja a Tibio en la próxima madrugada si no se gestiona.')
    expect(notaPotencial(item({ baja_el: '2026-09-30' }), contexto)).toBe('Baja a Tibio en la próxima madrugada si no se gestiona.')
    expect(notaPotencial(item({ baja_el: MANANA }), contexto)).toBe('Baja a Tibio mañana si no se gestiona.')
    expect(notaPotencial(item({ baja_el: '2026-10-06' }), contexto))
      .toBe('Baja a Tibio el martes 6 de octubre si no se gestiona (cuentan lunes a sábado).')
    expect(notaPotencial(item({ nivel: 'tibio', nivel_marcado: 'tibio', baja_a: 'frio', baja_el: '2026-10-14' }), contexto))
      .toBe('Baja a Frío el miércoles 14 de octubre si no se gestiona (cuentan lunes a sábado).')
  })

  it('a qué nivel baja lo dice el servidor: una Estrella con muchos días puede bajar directo a Frío', () => {
    // Después de la última pasada de la madrugada, una Estrella con 9 días sin
    // gestión llega con `baja_el` = mañana y `baja_a` = el nivel que tendrá ESE día.
    const vencida = item({ dias_sin_gestion: 9, baja_a: 'frio', baja_el: MANANA })
    expect(notaPotencial(vencida, contexto)).toBe('Baja a Frío mañana si no se gestiona.')
    expect(notaPotencial({ ...vencida, baja_el: HOY }, contexto)).toBe('Baja a Frío en la próxima madrugada si no se gestiona.')
    expect(notaPotencial({ ...vencida, baja_el: '2026-10-05' }, contexto))
      .toBe('Baja a Frío el lunes 5 de octubre si no se gestiona (cuentan lunes a sábado).')
    expect(notaPotencial({ ...vencida, baja_el: null }, contexto)).toBe('Baja a Frío si no se gestiona (cuentan lunes a sábado).')
  })

  it('«mañana» cruza el fin de mes', () => {
    expect(notaPotencial(item({ baja_el: '2026-11-01' }), { cerrado: false, hoy: '2026-10-31' })).toBe('Baja a Tibio mañana si no se gestiona.')
  })

  it('si el servidor no manda la fecha o el destino, no los inventa', () => {
    expect(notaPotencial(item({ baja_el: null }), contexto)).toBe('Baja a Tibio si no se gestiona (cuentan lunes a sábado).')
    // Sin `baja_a` (por ejemplo, el instante optimista) no se deduce del nivel.
    expect(notaPotencial(item({ baja_a: null, baja_el: null }), contexto)).toBe('Marcado como Estrella.')
    expect(notaPotencial(item({ nivel: 'tibio', nivel_marcado: 'tibio', baja_a: null, baja_el: '2026-10-06' }), contexto)).toBe('Marcado como Tibio.')
  })
})
