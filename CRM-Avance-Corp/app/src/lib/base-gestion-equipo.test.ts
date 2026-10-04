// Lógica pura de la vista del supervisor (F4): el filtro por analista (con la bandeja «Sin analista»), la marca
// «No contactar» y la demo del equipo (panel y detalle cuadran con la hoja). El estado en la URL: base-gestion-url.test.ts.
import { describe, expect, it } from 'vitest'
import {
  SIN_DATO,
  SIN_FILTROS,
  demoBaseEquipo,
  depurarFiltros,
  esVetada,
  etiquetaAnalista,
  etiquetaDetalleCifra,
  filtrarBase,
  opcionesFiltro,
  type FilaBaseGestion,
  type FiltrosBase,
} from './base-gestion'
import { fechaLima } from './agenda-derivada'
import type { Lead, Miembro } from './tipos'

function fila(n: number, sobre: Partial<FilaBaseGestion> = {}): FilaBaseGestion {
  return {
    lead_id: `lead-${n}`, nombre_completo: `LEAD ${n}`, telefono: null, distrito: null, origen: 'landing',
    categoria_interes: null, monto_estimado: 1, moneda: 'PEN', motivo_descarte: 'no_responde',
    descartado_en: null, dias_desde_descarte: 1, etapa_maxima: 'contactado', intentos: 0,
    ultimo_resultado: null, ultimo_intento_en: null, proxima_llamada_en: null, rellamada_hoy: false,
    enfriado_hasta: null, ciclo_n: 1, vendedor_id: 'v-b', gestiona: 'BETO', recibido_en: null, ...sobre,
  }
}
const con = (sobre: Partial<FiltrosBase>): FiltrosBase => ({ ...SIN_FILTROS, ...sobre })
const BASE = [
  fila(1, { vendedor_id: 'v-z', gestiona: 'ZOILA' }),
  fila(2),
  fila(3, { vendedor_id: null, gestiona: null }),
  fila(4, { vendedor_id: 'v-a', gestiona: 'ANA' }),
  fila(5),
]

describe('filtro por analista (F4)', () => {
  it('cada analista con su nombre y conteo, por nombre; «Sin analista» (la bandeja) al final', () => {
    const o = opcionesFiltro(BASE)
    expect(o.analista.total).toBe(5)
    expect(o.analista.opciones.map((x) => `${x.etiqueta} (${x.leads})`)).toEqual(['ANA (1)', 'BETO (2)', 'ZOILA (1)', 'Sin analista (1)'])
  })

  it('filtra por analista y por la bandeja; combina con los demás filtros y cuenta sobre ellos', () => {
    expect(filtrarBase(BASE, con({ analista: 'v-b' })).map((f) => f.lead_id)).toEqual(['lead-2', 'lead-5'])
    expect(filtrarBase(BASE, con({ analista: SIN_DATO })).map((f) => f.lead_id)).toEqual(['lead-3'])
    const conMotivo = [...BASE, fila(6, { motivo_descarte: 'sin_fondos' })]
    expect(opcionesFiltro(conMotivo, con({ motivo: 'sin_fondos' })).analista.opciones.map((x) => `${x.etiqueta} (${x.leads})`)).toEqual(['BETO (1)'])
  })

  it('el analista que ya no está en la base vuelve a «Todos»', () => {
    expect(depurarFiltros(BASE, con({ analista: 'v-ausente' }))).toEqual(SIN_FILTROS)
    const f = con({ analista: 'v-a' })
    expect(depurarFiltros(BASE, f)).toBe(f)
  })

  it('el rótulo de quien gestiona: el analista, «Sin analista» o «Analista sin nombre»', () => {
    expect(etiquetaAnalista({ vendedor_id: 'x', gestiona: 'ANA' })).toBe('ANA')
    expect(etiquetaAnalista({ vendedor_id: null, gestiona: null })).toBe('Sin analista')
    expect(etiquetaAnalista({ vendedor_id: 'x', gestiona: null })).toBe('Analista sin nombre')
  })
})

describe('marca y detalle', () => {
  it('solo `no_contactar = true` es un vetado (sin el campo, antes de la B6b, no lo es)', () => {
    expect(esVetada(fila(1, { no_contactar: true }))).toBe(true)
    expect(esVetada(fila(1, { no_contactar: false }))).toBe(false)
    expect(esVetada(fila(1))).toBe(false)
  })

  it('el detalle de un intento se lee con el nombre del resultado; otro texto, tal cual', () => {
    expect(etiquetaDetalleCifra('no_contesto')).toBe('No contestó')
    expect(etiquetaDetalleCifra('Reactivado desde la base')).toBe('Reactivado desde la base')
    expect(etiquetaDetalleCifra(null)).toBeNull()
  })
})

describe('demo del equipo (sin red)', () => {
  const EQUIPO: Miembro[] = [
    { perfil_id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true },
    { perfil_id: 'd-v2', nombre_completo: 'ANALISTA DOS', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true },
    { perfil_id: 'd-v3', nombre_completo: 'ANALISTA TRES', rol_crm: 'vendedor', supervisor_id: 'd-sup2', activo: true },
    { perfil_id: 'd-v4', nombre_completo: 'ANALISTA INACTIVO', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: false },
  ]
  const LEADS = [{ id: 'l-desc', nombre_completo: 'DESCARTADO DEL STORE', telefono: '+51911111111', etapa: 'descartado', origen: 'landing', monto_estimado: 5000, moneda: 'PEN', vendedor_id: 'd-v1', vendedor_nombre: 'ANALISTA UNO', creado_en: '2026-09-01T15:00:00Z' } as Lead]
  // Medianoche y cuarto en Lima: lo «de hoy» tiene que seguir siendo de hoy.
  const AHORA = Date.parse('2026-10-04T05:15:00Z')

  it('Supervisión ve SUS analistas activos; Gerencia, todos', () => {
    expect(demoBaseEquipo(LEADS, EQUIPO, { id: 'd-sup1', rol: 'supervisor' }, AHORA).resumen.map((r) => r.nombre)).toEqual(['ANALISTA DOS', 'ANALISTA UNO'])
    expect(demoBaseEquipo(LEADS, EQUIPO, { id: 'd-ger', rol: 'gerencia' }, AHORA).resumen.map((r) => r.nombre)).toEqual(['ANALISTA DOS', 'ANALISTA TRES', 'ANALISTA UNO'])
    expect(demoBaseEquipo(LEADS, EQUIPO, null, AHORA)).toMatchObject({ filas: [], resumen: [] })
  })

  it('las cifras del panel cuadran con la hoja y con su detalle; los vetados van al final y nunca en «Llamar hoy»', () => {
    const demo = demoBaseEquipo(LEADS, EQUIPO, { id: 'd-ger', rol: 'gerencia' }, AHORA)
    const vivas = demo.filas.filter((f) => !esVetada(f))
    const primerVetado = demo.filas.findIndex(esVetada)
    expect(primerVetado).toBeGreaterThan(0)
    expect(demo.filas.slice(primerVetado).every(esVetada)).toBe(true)
    expect(demo.filas.filter(esVetada).some((f) => f.rellamada_hoy)).toBe(false)
    expect(demo.filas.some((f) => f.lead_id === 'l-desc')).toBe(true)
    expect(demo.filas.some((f) => f.vendedor_id === null)).toBe(true)
    // Ids únicos (la muestra no se repite por analista).
    expect(new Set(demo.filas.map((f) => f.lead_id)).size).toBe(demo.filas.length)
    for (const r of demo.resumen) {
      expect(r.en_base).toBe(vivas.filter((f) => f.vendedor_id === r.vendedor_id).length)
      expect(r.rellamadas_hoy).toBe(vivas.filter((f) => f.vendedor_id === r.vendedor_id && f.rellamada_hoy).length)
      const intentos = demo.detalle(r.vendedor_id, 'intentos_hoy')
      expect(intentos).toHaveLength(r.intentos_hoy)
      expect(intentos.every((d) => fechaLima(Date.parse(d.en)) === fechaLima(AHORA))).toBe(true)
      expect(demo.detalle(r.vendedor_id, 'reactivaciones_mes')).toHaveLength(r.reactivaciones_mes)
    }
    expect(demo.resumen.some((r) => r.intentos_hoy > 0)).toBe(true)
    expect(demo.resumen.some((r) => r.reactivaciones_mes > 0)).toBe(true)
  })
})
