import { describe, expect, it } from 'vitest'
import {
  SENALES_VACIAS,
  combinarSenales,
  fusionarHistorial,
  localesVivas,
  ordenarHistorial,
  senalesDesdeActividades,
} from './historial-lead'
import type { Actividad, TipoActividad } from './tipos'

const act = (id: string, tipo: TipoActividad, creado_en: string, extra: Partial<Actividad> = {}): Actividad => ({
  id,
  lead_id: 'l1',
  tipo,
  detalle: null,
  autor_nombre: 'Prueba',
  creado_en,
  ...extra,
})

describe('senalesDesdeActividades — «alguna vez», no «en esta página»', () => {
  it('sin filas no enciende ninguna señal', () => {
    expect(senalesDesdeActividades([])).toEqual(SENALES_VACIAS)
  })

  it('una reunión realizada enciende reunión Y contacto, y es conversación', () => {
    const s = senalesDesdeActividades([act('a', 'reunion_realizada', '2026-07-01T12:00:00.000Z')])
    expect(s).toEqual({
      tieneReunionRealizada: true,
      tieneContacto: true,
      ultimaConversacionEn: '2026-07-01T12:00:00.000Z',
    })
  })

  it('una llamada no contestada es contacto pero no conversación', () => {
    const s = senalesDesdeActividades([act('a', 'llamada_no_contestada', '2026-07-01T12:00:00.000Z')])
    expect(s).toEqual({ tieneReunionRealizada: false, tieneContacto: true, ultimaConversacionEn: null })
  })

  it('las filas del SISTEMA (cambio de etapa, reasignación) no cuentan como contacto', () => {
    const s = senalesDesdeActividades([
      act('a', 'cambio_etapa', '2026-07-01T12:00:00.000Z'),
      act('b', 'reasignacion', '2026-07-02T12:00:00.000Z'),
      act('c', 'nota', '2026-07-03T12:00:00.000Z'),
    ])
    expect(s.tieneContacto).toBe(false)
  })

  it('la última conversación es la más reciente por fecha, no por posición; una fecha corrupta no cuenta', () => {
    const s = senalesDesdeActividades([
      act('a', 'whatsapp_recibido', '2026-07-05T12:00:00.000Z'),
      act('b', 'llamada_realizada', '2026-07-09T12:00:00.000Z'),
      act('c', 'llamada_realizada', 'no-es-fecha'),
    ])
    expect(s.ultimaConversacionEn).toBe('2026-07-09T12:00:00.000Z')
  })
})

describe('combinarSenales — una señal solo se enciende', () => {
  it('une lo servido con lo local y se queda con la conversación más reciente', () => {
    const servidas = { tieneReunionRealizada: false, tieneContacto: true, ultimaConversacionEn: '2026-07-01T12:00:00.000Z' }
    const locales = { tieneReunionRealizada: true, tieneContacto: false, ultimaConversacionEn: '2026-07-02T12:00:00.000Z' }
    expect(combinarSenales(servidas, locales)).toEqual({
      tieneReunionRealizada: true,
      tieneContacto: true,
      ultimaConversacionEn: '2026-07-02T12:00:00.000Z',
    })
    expect(combinarSenales(locales, servidas).ultimaConversacionEn).toBe('2026-07-02T12:00:00.000Z')
  })

  it('con una sola fuente con conversación, gana esa', () => {
    expect(combinarSenales(SENALES_VACIAS, { ...SENALES_VACIAS, ultimaConversacionEn: '2026-07-02T12:00:00.000Z' }).ultimaConversacionEn)
      .toBe('2026-07-02T12:00:00.000Z')
  })
})

describe('ordenarHistorial — más reciente primero, empates deterministas', () => {
  it('ordena por fecha desc aunque los formatos ISO difieran (servidor con offset, local con Z)', () => {
    const ordenado = ordenarHistorial([
      act('a', 'nota', '2026-09-19T17:46:04.218Z'),
      act('b', 'nota', '2026-09-19T17:50:00.000000+00:00'),
      act('c', 'nota', '2026-09-19T12:00:00+00:00'),
    ])
    expect(ordenado.map((x) => x.id)).toEqual(['b', 'a', 'c'])
  })

  it('a igual creado_en, el cambio de etapa va DELANTE de la gestión que lo provocó', () => {
    const misma = '2026-09-19T17:46:04.218374+00:00'
    const ordenado = ordenarHistorial([
      act('zz-llamada', 'llamada_realizada', misma),
      act('aa-etapa', 'cambio_etapa', misma),
    ])
    expect(ordenado.map((x) => x.tipo)).toEqual(['cambio_etapa', 'llamada_realizada'])
    // …y entre dos del mismo rango, el id decide para que el orden sea estable.
    const empate = ordenarHistorial([act('b', 'nota', misma), act('a', 'nota', misma)])
    expect(empate.map((x) => x.id)).toEqual(['a', 'b'])
  })

  it('no muta la entrada', () => {
    const entrada = [act('a', 'nota', '2026-07-01T12:00:00.000Z'), act('b', 'nota', '2026-07-02T12:00:00.000Z')]
    const copia = [...entrada]
    ordenarHistorial(entrada)
    expect(entrada).toEqual(copia)
  })
})

describe('localesVivas / fusionarHistorial — la fila optimista vive hasta que el servidor la sustituye', () => {
  const local = act('local-1', 'llamada_realizada', '2026-09-19T17:46:04.218Z', { local: true, local_ts: 1_000 })
  const localEtapa = act('local-2', 'cambio_etapa', '2026-09-19T17:46:04.218Z', { local: true, local_ts: 1_000 })
  const servidorVieja = act('srv-0', 'nota', '2026-09-10T10:00:00+00:00')
  const servidorNueva = act('srv-1', 'llamada_realizada', '2026-09-19T17:46:04.218374+00:00')
  const servidorEtapa = act('srv-2', 'cambio_etapa', '2026-09-19T17:46:04.218374+00:00')

  it('sin ninguna lectura del servidor (leidoEn = 0) las locales se pintan', () => {
    expect(localesVivas([local, localEtapa], 0)).toHaveLength(2)
    expect(fusionarHistorial([local, localEtapa], [], 0).map((x) => x.id)).toEqual(['local-2', 'local-1'])
  })

  it('una lectura ANTERIOR a la fila local no la sustituye: se antepone a lo servido', () => {
    const fusion = fusionarHistorial([local, localEtapa], [servidorVieja], 500)
    expect(fusion.map((x) => x.id)).toEqual(['local-2', 'local-1', 'srv-0'])
  })

  it('una lectura POSTERIOR a la fila local la sustituye por la verdad del servidor (sin duplicar)', () => {
    const fusion = fusionarHistorial([local, localEtapa], [servidorEtapa, servidorNueva, servidorVieja], 2_000)
    expect(fusion.map((x) => x.id)).toEqual(['srv-2', 'srv-1', 'srv-0'])
  })

  it('las filas servidas (sin marca local) nunca se filtran, y un id repetido se pinta una sola vez', () => {
    const fusion = fusionarHistorial([servidorVieja], [servidorVieja, servidorNueva], 9_999)
    expect(fusion.map((x) => x.id)).toEqual(['srv-1', 'srv-0'])
  })
})
