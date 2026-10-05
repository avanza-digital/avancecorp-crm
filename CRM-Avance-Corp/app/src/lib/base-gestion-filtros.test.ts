// Organizar el trabajo de la base (F3): «Llamar hoy» arriba y filtros en el navegador. El servidor manda QUÉ filas y en
// qué ORDEN; aquí solo se separa y se recorta, sin reordenar, y cada opción de un filtro cuenta exactamente lo que el
// analista verá al elegirla.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  FilaBaseGestionSchema,
  FILTRO_TODOS,
  SIN_DATO,
  SIN_FILTROS,
  conBaseCargada,
  depurarFiltros,
  filtrarBase,
  hayFiltros,
  opcionesFiltro,
  separarLlamarHoy,
  tieneRellamadaAgendada,
  type FilaBaseGestion,
  type FiltrosBase,
} from './base-gestion'

function fila(n: number, sobre: Partial<FilaBaseGestion> = {}): FilaBaseGestion {
  return {
    lead_id: `lead-${n}`, nombre_completo: `LEAD ${n}`, telefono: null, distrito: null, origen: 'landing',
    categoria_interes: null, monto_estimado: null, moneda: null, motivo_descarte: 'no_responde',
    descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
    ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
    rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: 'a', gestiona: 'A', recibido_en: '2026-08-15T15:00:00Z', ...sobre,
  }
}

const SEP = '2026-09-10T15:00:00Z'
const AGO = '2026-08-15T15:00:00Z'
// Cinco leads con un poco de todo: dos para llamar hoy (uno vencido), uno sin motivo, uno sin intentos, uno sin mes.
const BASE: FilaBaseGestion[] = [
  fila(1, { rellamada_hoy: true, proxima_llamada_en: '2026-10-02T20:00:00Z', recibido_en: SEP, motivo_descarte: 'sin_fondos', etapa_maxima: 'reunion_agendada', ultimo_resultado: 'volver_a_llamar' }),
  fila(2, { rellamada_hoy: true, proxima_llamada_en: '2026-10-01T20:00:00Z', recibido_en: AGO, motivo_descarte: 'no_responde', ultimo_resultado: 'volver_a_llamar' }),
  fila(3, { recibido_en: AGO, motivo_descarte: 'sin_fondos', etapa_maxima: 'propuesta_enviada' }),
  fila(4, { recibido_en: AGO, motivo_descarte: 'sin_fondos', ultimo_resultado: null, intentos: 0, ultimo_intento_en: null }),
  fila(5, { recibido_en: null, motivo_descarte: null, etapa_maxima: 'sin_datos', ultimo_resultado: 'no_interesado', proxima_llamada_en: '2026-10-06T15:00:00Z' }),
]
const ids = (filas: readonly FilaBaseGestion[]) => filas.map((f) => f.lead_id)
const con = (sobre: Partial<FiltrosBase>): FiltrosBase => ({ ...SIN_FILTROS, ...sobre })
const textos = (o: { opciones: { etiqueta: string; leads: number }[] }) => o.opciones.map((x) => `${x.etiqueta} (${x.leads})`)

describe('separarLlamarHoy', () => {
  it('separa sin reordenar: cada bloque conserva el orden en que llegó del servidor', () => {
    // Orden adrede «raro» (el servidor nunca lo manda así): la pantalla no lo arregla, solo separa.
    const llegada = [fila(7, { etapa_maxima: 'nuevo' }), fila(8, { rellamada_hoy: true }), fila(6, { etapa_maxima: 'propuesta_enviada' }), fila(9, { rellamada_hoy: true })]
    const { hoy, resto } = separarLlamarHoy(llegada)
    expect(ids(hoy)).toEqual(['lead-8', 'lead-9'])
    expect(ids(resto)).toEqual(['lead-7', 'lead-6'])
  })

  it('sin rellamadas de hoy, todo es «el resto»', () => {
    expect(separarLlamarHoy([fila(1), fila(2)]).hoy).toEqual([])
  })
})

describe('filtrarBase', () => {
  it('sin filtros devuelve la base entera, en su orden', () => {
    expect(ids(filtrarBase(BASE, SIN_FILTROS))).toEqual(['lead-1', 'lead-2', 'lead-3', 'lead-4', 'lead-5'])
    expect(hayFiltros(SIN_FILTROS)).toBe(false)
  })

  it('combina el Mes con motivo, etapa y resultado (todos a la vez)', () => {
    expect(ids(filtrarBase(BASE, con({ mes: '2026-08', motivo: 'sin_fondos' })))).toEqual(['lead-3', 'lead-4'])
    expect(ids(filtrarBase(BASE, con({ mes: '2026-08', motivo: 'sin_fondos', etapa: 'contactado' })))).toEqual(['lead-4'])
    expect(ids(filtrarBase(BASE, con({ resultado: 'volver_a_llamar' })))).toEqual(['lead-1', 'lead-2'])
    expect(hayFiltros(con({ etapa: 'contactado' }))).toBe(true)
  })

  it('«sin motivo» y «sin intentos» son opciones de verdad; una fila sin mes solo pasa con «Todos»', () => {
    expect(ids(filtrarBase(BASE, con({ motivo: SIN_DATO })))).toEqual(['lead-5'])
    expect(ids(filtrarBase(BASE, con({ resultado: SIN_DATO })))).toEqual(['lead-4'])
    expect(ids(filtrarBase(BASE, con({ mes: '2026-09' })))).toEqual(['lead-1'])
  })

  it('«agendadas» son las rellamadas de OTRO día (las de hoy y las vencidas van en «Llamar hoy»)', () => {
    expect(BASE.filter(tieneRellamadaAgendada).map((f) => f.lead_id)).toEqual(['lead-5'])
    expect(ids(filtrarBase(BASE, con({ agendadas: true })))).toEqual(['lead-5'])
    expect(hayFiltros(con({ agendadas: true }))).toBe(true)
  })
})

describe('opcionesFiltro', () => {
  it('cada opción con su conteo, en orden ESTABLE: catálogo, etapa más lejana primero y «sin dato» al final', () => {
    const o = opcionesFiltro(BASE)
    expect(o.motivo.total).toBe(5)
    expect(textos(o.motivo)).toEqual(['Sin fondos (3)', 'No responde (1)', 'Sin motivo (1)'])
    expect(textos(o.etapa)).toEqual(['Entrevista realizada (1)', 'Cita agendada (1)', 'Contactado (2)', 'Sin historial (1)'])
    expect(textos(o.resultado)).toEqual(['No contestó (1)', 'Volver a llamar (2)', 'No le interesa (1)', 'Sin intentos (1)'])
    // El mes, del más reciente; la fila sin mes cuenta en «Todos» pero no inventa un mes.
    expect(o.mes.total).toBe(5)
    expect(textos(o.mes)).toEqual(['Septiembre 2026 (1)', 'Agosto 2026 (3)'])
  })

  it('cada filtro cuenta sobre lo que dejan pasar LOS DEMÁS: el número es lo que se verá al elegirlo', () => {
    const o = opcionesFiltro(BASE, con({ mes: '2026-08' }))
    expect(o.motivo.total).toBe(3)
    expect(textos(o.motivo)).toEqual(['Sin fondos (2)', 'No responde (1)'])
    // El propio Mes no se recorta a sí mismo: sigue ofreciendo los otros meses.
    expect(textos(o.mes)).toEqual(['Septiembre 2026 (1)', 'Agosto 2026 (3)'])
    for (const opcion of o.motivo.opciones) {
      expect(filtrarBase(BASE, con({ mes: '2026-08', motivo: opcion.clave }))).toHaveLength(opcion.leads)
    }
  })

  it('la opción elegida se lista aunque los otros filtros la dejen en 0 (el selector no muestra un valor ausente)', () => {
    const o = opcionesFiltro(BASE, con({ mes: '2026-09', motivo: 'no_responde' }))
    expect(textos(o.motivo)).toContain('No responde (0)')
  })

  it('un valor que el catálogo no conoce se muestra tal cual, después de los conocidos', () => {
    const o = opcionesFiltro([fila(1, { motivo_descarte: 'motivo_nuevo' }), fila(2, { motivo_descarte: 'otro' })])
    expect(textos(o.motivo)).toEqual(['Otro (1)', 'motivo_nuevo (1)'])
  })

  it('base vacía: «Todos (0)» y ninguna opción', () => {
    const o = opcionesFiltro([])
    expect(o.motivo).toEqual({ total: 0, opciones: [] })
    expect(o.mes).toEqual({ total: 0, opciones: [] })
  })
})

describe('depurarFiltros (al refrescar la base)', () => {
  it('sin cambios devuelve el MISMO objeto (la pantalla no se repinta en bucle)', () => {
    const f = con({ mes: '2026-08', motivo: 'sin_fondos' })
    expect(depurarFiltros(BASE, f)).toBe(f)
  })

  it('el valor que ya no existe en la base vuelve a «Todos»; el que existe se respeta aunque hoy cuente 0', () => {
    const sinFondos = BASE.filter((x) => x.motivo_descarte !== 'sin_fondos')
    expect(depurarFiltros(sinFondos, con({ motivo: 'sin_fondos', etapa: 'contactado' }))).toEqual(con({ motivo: FILTRO_TODOS, etapa: 'contactado' }))
    // Septiembre + «No responde» no coinciden en ninguna fila, pero los dos valores siguen en la base: se quedan.
    const vacio = con({ mes: '2026-09', motivo: 'no_responde' })
    expect(depurarFiltros(BASE, vacio)).toBe(vacio)
    expect(filtrarBase(BASE, vacio)).toEqual([])
  })

  it('sin ninguna rellamada agendada en la base, «agendadas» se apaga', () => {
    expect(depurarFiltros(BASE.slice(0, 4), con({ agendadas: true }))).toEqual(SIN_FILTROS)
  })
})

// F5a «Bases cargadas»: el contacto de base llega con origen y motivo `base_cargada` y, a veces, sin capital (E8).
describe('F5a · contacto de base cargada en la hoja de la base', () => {
  const DE_BASE = fila(6, { origen: 'base_cargada', motivo_descarte: 'base_cargada', monto_estimado: null, moneda: 'PEN' })

  it('la fila parsea con el contrato de la RPC (origen, motivo y capital vacío)', () => {
    expect(v.safeParse(FilaBaseGestionSchema, DE_BASE).success).toBe(true)
  })

  it('el filtro de motivo lo rotula «Base cargada», después de los elegibles y antes de «sin dato»', () => {
    const motivo = opcionesFiltro([...BASE, DE_BASE]).motivo
    expect(textos(motivo)).toEqual(['Sin fondos (3)', 'No responde (1)', 'Base cargada (1)', 'Sin motivo (1)'])
    expect(ids(filtrarBase([...BASE, DE_BASE], con({ motivo: 'base_cargada' })))).toEqual(['lead-6'])
  })

  it('ESTADO DE PRODUCCIÓN: sin contactos de base, las opciones del motivo son las de siempre', () => {
    expect(textos(opcionesFiltro(BASE).motivo)).toEqual(['Sin fondos (3)', 'No responde (1)', 'Sin motivo (1)'])
  })
})

// F6 «Bases cargadas»: tras la B10, `obtener_base_gestion` añade `base_id` y `base_nombre`; el analista filtra por base.
describe('F6 · el selector «Base» junto al del Mes', () => {
  const FERIA = { base_id: 'b-feria', base_nombre: 'Feria 2025' }
  const CON_BASE = [...BASE.slice(0, 3), fila(6, FERIA), fila(7, FERIA), fila(8, { base_id: 'b-julio', base_nombre: 'Julio' })]

  it('ESTADO DE PRODUCCIÓN (antes de la B10): sin los campos la fila parsea y no hay selector', () => {
    expect(v.safeParse(FilaBaseGestionSchema, fila(1)).success).toBe(true)
    expect(conBaseCargada(BASE)).toBe(false)
    expect(textos(opcionesFiltro(BASE).base)).toEqual(['Sin base (5)'])
  })

  it('con contactos de base: «Feria 2025 (2)», «Julio (1)» y «Sin base»; filtra sin reordenar y se depura', () => {
    expect(v.safeParse(FilaBaseGestionSchema, fila(6, FERIA)).success).toBe(true)
    expect(conBaseCargada(CON_BASE)).toBe(true)
    expect(textos(opcionesFiltro(CON_BASE).base)).toEqual(['Feria 2025 (2)', 'Julio (1)', 'Sin base (3)'])
    expect(ids(filtrarBase(CON_BASE, con({ base: 'b-feria' })))).toEqual(['lead-6', 'lead-7'])
    expect(ids(filtrarBase(CON_BASE, con({ base: SIN_DATO })))).toEqual(['lead-1', 'lead-2', 'lead-3'])
    // Cada filtro cuenta sobre lo que dejan pasar los demás.
    expect(opcionesFiltro(CON_BASE, con({ base: 'b-feria' })).mes.total).toBe(2)
    expect(depurarFiltros(BASE, con({ base: 'b-feria' }))).toEqual(SIN_FILTROS)
    expect(hayFiltros(con({ base: 'b-julio' }))).toBe(true)
  })
})
