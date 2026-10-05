// Textos y espejo demo de la base para gestión: lo que el analista lee en cada fila tiene que decir lo
// mismo que el servidor decidió (días calendario de Lima, tope de intentos, rellamada vencida o de hoy).
import { describe, expect, it } from 'vitest'
import type { Lead } from './tipos'
import {
  estadoRellamada,
  etiquetaDiasDescarte,
  etiquetaEtapaMaxima,
  etiquetaIntentos,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  etiquetaOrigen as etiquetaOrigenBase,
  etiquetaRellamada,
  etiquetaUltimoResultado,
  filasDemoBaseGestion,
  type FilaBaseGestion,
} from './base-gestion'

// Viernes 2 de octubre de 2026, 20:00 en Lima (01:00 UTC del sábado 3): la hora en que el UTC ya es «mañana».
const AHORA = Date.parse('2026-10-03T01:00:00Z')

describe('rellamada en días de Lima', () => {
  it('es de HOY aunque en UTC ya sea el día siguiente', () => {
    expect(estadoRellamada('2026-10-03T02:30:00Z', AHORA)).toBe('hoy') // 21:30 del viernes en Lima
    expect(etiquetaRellamada('2026-10-03T02:30:00Z', AHORA)).toBe('Hoy, 21:30')
  })

  it('marca la vencida con su fecha y la de mañana como «Mañana»', () => {
    expect(estadoRellamada('2026-10-01T15:00:00Z', AHORA)).toBe('vencida')
    expect(etiquetaRellamada('2026-10-01T15:00:00Z', AHORA)).toBe('Vencida: Jue 1 Oct, 10:00')
    expect(etiquetaRellamada('2026-10-03T15:00:00Z', AHORA)).toBe('Mañana, 10:00')
    expect(etiquetaRellamada('2026-10-08T15:00:00Z', AHORA)).toBe('Jue 8 Oct, 10:00')
  })

  it('no inventa una fecha si el servidor manda algo ilegible', () => {
    expect(etiquetaRellamada('no-es-fecha', AHORA)).toBe('Sin fecha')
    expect(etiquetaMomento('no-es-fecha', AHORA)).toBe('Sin fecha')
  })
})

describe('textos de la fila', () => {
  it('cuenta intentos contra el tope y deja pasar los que la rellamada permitió (D12)', () => {
    expect(etiquetaIntentos(0)).toBe('0 de 3')
    expect(etiquetaIntentos(3)).toBe('3 de 3')
    expect(etiquetaIntentos(4)).toBe('4 intentos')
  })

  it('dice los días desde el descarte como se hablan', () => {
    expect(etiquetaDiasDescarte(0)).toBe('Hoy')
    expect(etiquetaDiasDescarte(1)).toBe('Ayer')
    expect(etiquetaDiasDescarte(12)).toBe('Hace 12 días')
    expect(etiquetaDiasDescarte(null)).toBe('Sin fecha')
  })

  it('nombra la etapa máxima, el motivo y el resultado con los rótulos del CRM', () => {
    expect(etiquetaEtapaMaxima('reunion_agendada')).toBe('Cita agendada')
    expect(etiquetaEtapaMaxima('propuesta_enviada')).toBe('Entrevista realizada')
    expect(etiquetaEtapaMaxima('sin_datos')).toBe('Sin historial')
    expect(etiquetaMotivoDescarte('sin_fondos')).toBe('Sin fondos')
    expect(etiquetaMotivoDescarte('motivo_nuevo')).toBe('motivo_nuevo')
    expect(etiquetaMotivoDescarte(null)).toBe('Sin motivo')
    expect(etiquetaUltimoResultado('no_contesto')).toBe('No contestó')
    expect(etiquetaUltimoResultado('volver_a_llamar')).toBe('Volver a llamar')
    expect(etiquetaUltimoResultado(null)).toBe('Sin intentos')
  })

  it('fecha el último intento en Lima: hoy, ayer o el día', () => {
    expect(etiquetaMomento('2026-10-02T23:15:00Z', AHORA)).toBe('Hoy, 18:15')
    expect(etiquetaMomento('2026-10-01T14:00:00Z', AHORA)).toBe('Ayer, 09:00')
    expect(etiquetaMomento('2026-09-28T14:00:00Z', AHORA)).toBe('Lun 28 Sep, 09:00')
  })
})

describe('espejo demo', () => {
  const lead = (sobre: Partial<Lead>): Lead => ({
    id: 'l1', nombre_completo: 'ANA DEMO', telefono: '+51987654321', etapa: 'descartado', origen: 'landing',
    monto_estimado: 10000, moneda: 'PEN', vendedor_id: 'yo', creado_en: '2026-09-01T15:00:00Z',
    actualizado_en: '2026-09-30T15:00:00Z', motivo_descarte: 'no_responde', ...sobre,
  } as Lead)

  // Los leads de MUESTRA (F3) viven solo en la base demo; los del store se reconocen por no llevar el prefijo.
  const delStore = (filas: { lead_id: string }[]) => filas.filter((f) => !f.lead_id.startsWith('demo-base-'))

  it('del store solo trae los descartados vivos del propio analista y nunca los de «no contactar»', () => {
    const filas = filasDemoBaseGestion([
      lead({ id: 'mio' }),
      lead({ id: 'ajeno', vendedor_id: 'otro' }),
      lead({ id: 'vivo', etapa: 'contactado' }),
      lead({ id: 'vetado', no_contactar: true }),
    ], 'yo', AHORA)
    expect(delStore(filas).map((f) => f.lead_id)).toEqual(['mio'])
    expect(filas.find((f) => f.lead_id === 'mio')).toMatchObject({ intentos: 0, etapa_maxima: 'sin_datos', dias_desde_descarte: 2, motivo_descarte: 'no_responde' })
  })

  it('sin analista no fabrica nada (ni siquiera la muestra)', () => {
    expect(filasDemoBaseGestion([lead({ id: 'mio' })], '', AHORA)).toEqual([])
  })

  it('la muestra deja ver «Llamar hoy» (una de hoy y una vencida, en días de Lima) y da variedad a los filtros', () => {
    const filas = filasDemoBaseGestion([lead({ id: 'mio', vendedor_nombre: 'ANALISTA UNO' })], 'yo', AHORA)
    const hoy = filas.filter((f) => f.rellamada_hoy)
    expect(hoy.length).toBeGreaterThanOrEqual(2)
    // 20:00 del viernes en Lima (ya sábado en UTC): la de las 10:00 de HOY sigue siendo de hoy; la de ayer, vencida.
    expect(hoy.map((f) => estadoRellamada(f.proxima_llamada_en ?? '', AHORA)).sort()).toEqual(['hoy', 'vencida'])
    // Una rellamada de otro día NO es de hoy.
    expect(filas.some((f) => f.proxima_llamada_en !== null && !f.rellamada_hoy)).toBe(true)
    expect(new Set(filas.map((f) => f.motivo_descarte)).size).toBeGreaterThanOrEqual(3)
    expect(new Set(filas.map((f) => f.etapa_maxima)).size).toBeGreaterThanOrEqual(3)
    expect(new Set(filas.map((f) => f.ultimo_resultado)).size).toBeGreaterThanOrEqual(3)
    expect(new Set(filas.map((f) => f.recibido_en?.slice(0, 7))).size).toBeGreaterThanOrEqual(2)
    // Son del analista y la ficha dice quién los gestiona.
    expect(filas.every((f) => f.vendedor_id === 'yo' && f.gestiona === 'ANALISTA UNO')).toBe(true)
  })

  it('ordenada como el servidor: rellamadas de hoy → etapa máxima → descarte más reciente', () => {
    const filas = filasDemoBaseGestion([lead({ id: 'mio' })], 'yo', AHORA)
    const rango = { sin_datos: 0, nuevo: 1, contactado: 2, reunion_agendada: 3, propuesta_enviada: 4, convertido: 5 } as const
    const clave = (f: FilaBaseGestion) => [f.rellamada_hoy ? 0 : 1, -rango[f.etapa_maxima], f.dias_desde_descarte ?? Infinity]
    const noDespues = (a: number[], b: number[]): boolean => {
      for (let k = 0; k < a.length; k += 1) if (a[k] !== b[k]) return (a[k] ?? 0) < (b[k] ?? 0)
      return true
    }
    for (let i = 1; i < filas.length; i += 1) {
      const [a, b] = [filas[i - 1], filas[i]] as [FilaBaseGestion, FilaBaseGestion]
      expect(noDespues(clave(a), clave(b)), `${a.lead_id} antes que ${b.lead_id}`).toBe(true)
    }
    expect(filas[0]?.rellamada_hoy).toBe(true)
    expect(filas.at(-1)?.lead_id).toBe('mio') // sin historial y sin rellamada: al final
  })
})

// F5a «Bases cargadas»: la hoja, la ficha y la lista de vetados rotulan el motivo y el origen nuevos sin siglas.
describe('F5a · rótulos de base cargada', () => {
  it('motivo y origen «base_cargada» se leen «Base cargada»', () => {
    expect(etiquetaMotivoDescarte('base_cargada')).toBe('Base cargada')
    expect(etiquetaOrigenBase('base_cargada')).toBe('Base cargada')
  })

  it('ESTADO DE PRODUCCIÓN: los rótulos de siempre no cambian', () => {
    expect(etiquetaMotivoDescarte('sin_fondos')).toBe('Sin fondos')
    expect(etiquetaMotivoDescarte(null)).toBe('Sin motivo')
    expect(etiquetaOrigenBase('oficina')).toBe('Walking')
    expect(etiquetaOrigenBase(null)).toBe('Sin origen')
  })
})
