import { describe, expect, it } from 'vitest'
import type { AsientoReconocimiento } from './reconocimientos-alertas'
import {
  ETIQUETA_TIPO_DESCONOCIDO,
  asientosDemoTrazabilidad,
  derivarCompromisos,
  resumenCompromisos,
} from './trazabilidad-reconocimientos'

const AHORA = Date.UTC(2026, 7, 24, 15)

function asiento(over: Partial<AsientoReconocimiento> = {}): AsientoReconocimiento {
  return {
    id: '00000000-0000-4000-8000-000000000001',
    alerta_id: 'grupo:lead_sin_responder:11111111-1111-4111-8111-111111111111',
    accion: 'reconocer',
    miembros: ['l1', 'l2'],
    severidad: 'critica',
    hasta: null,
    creado_en: new Date(AHORA - 3_600_000).toISOString(),
    secuencia: 1,
    ...over,
  }
}

describe('derivarCompromisos', () => {
  it('presenta el compromiso con su supervisor, etiqueta humana, UNIDAD real y vencimiento del candado', () => {
    const [c] = derivarCompromisos([asiento()], AHORA)
    expect(c).toMatchObject({
      supervisorId: '11111111-1111-4111-8111-111111111111',
      etiqueta: 'Leads nuevos sin responder',
      cuanto: '2 leads',
      accion: 'reconocer',
      severidad: 'critica',
    })
    // Reconocer rige hasta creado_en + 7 días (el candado acotado de F4.1).
    expect(c!.venceEn).toBe(c!.creadoEn + 7 * 86_400_000)
  })

  it('la foto de sin_proxima_accion cuenta ANALISTAS, no leads — y la de tareas, leads', () => {
    const compromisos = derivarCompromisos([
      asiento({ alerta_id: 'grupo:sin_proxima_accion:11111111-1111-4111-8111-111111111111', miembros: ['v1'] }),
      asiento({
        id: '00000000-0000-4000-8000-000000000002',
        alerta_id: 'grupo:tarea_vencida:11111111-1111-4111-8111-111111111111',
        miembros: ['l1', 'l2', 'l3'],
        secuencia: 2,
      }),
    ], AHORA)
    const porEtiqueta = new Map(compromisos.map((c) => [c.etiqueta, c.cuanto]))
    expect(porEtiqueta.get('Leads sin próxima acción')).toBe('1 analista')
    expect(porEtiqueta.get('Leads con plazo vencido')).toBe('3 leads')
  })

  it('en posponer rige el MENOR de: su hasta y el candado de 7 días', () => {
    const creado = AHORA - 3_600_000
    const [corto] = derivarCompromisos([asiento({
      accion: 'posponer',
      hasta: new Date(AHORA + 26 * 3_600_000).toISOString(),
    })], AHORA)
    expect(corto!.venceEn).toBe(AHORA + 26 * 3_600_000)
    // Un hasta más allá del candado (imposible por el trigger, pero el front
    // no confía): gana el candado.
    const [largo] = derivarCompromisos([asiento({
      accion: 'posponer',
      hasta: new Date(creado + 9 * 86_400_000).toISOString(),
    })], AHORA)
    expect(largo!.venceEn).toBe(creado + 7 * 86_400_000)
  })

  it('CINTURÓN contra la caché: lo ya vencido para el reloj local no se lista', () => {
    const compromisos = derivarCompromisos([
      // Posposición que venció hace un minuto (la vista aún no refrescó).
      asiento({ accion: 'posponer', hasta: new Date(AHORA - 60_000).toISOString() }),
      // Reconocimiento cuyo candado de 7 días quedó atrás.
      asiento({
        id: '00000000-0000-4000-8000-000000000002',
        alerta_id: 'grupo:por_repartir:11111111-1111-4111-8111-111111111111',
        creado_en: new Date(AHORA - 8 * 86_400_000).toISOString(),
        secuencia: 2,
      }),
    ], AHORA)
    expect(compromisos).toHaveLength(0)
  })

  it('el último asiento POR alerta manda (secuencia), y ordena del más reciente al más antiguo', () => {
    const compromisos = derivarCompromisos([
      asiento({ id: '00000000-0000-4000-8000-000000000001', secuencia: 1, accion: 'reconocer', creado_en: new Date(AHORA - 7_200_000).toISOString() }),
      asiento({ id: '00000000-0000-4000-8000-000000000002', secuencia: 5, accion: 'posponer', hasta: new Date(AHORA + 3_600_000).toISOString(), creado_en: new Date(AHORA - 3_600_000).toISOString() }),
      asiento({
        id: '00000000-0000-4000-8000-000000000003',
        alerta_id: 'grupo:por_repartir:22222222-2222-4222-8222-222222222222',
        secuencia: 2,
        creado_en: new Date(AHORA - 60_000).toISOString(),
      }),
    ], AHORA)
    expect(compromisos).toHaveLength(2)
    // Más reciente primero; de la alerta repetida sobrevive la secuencia 5.
    expect(compromisos[0]!.etiqueta).toBe('Leads esperando reparto')
    expect(compromisos[1]!.accion).toBe('posponer')
  })

  it('un empate de secuencia (libro corrupto) NO lista esa alerta: nadie sabe qué acción manda', () => {
    const compromisos = derivarCompromisos([
      asiento({ id: '00000000-0000-4000-8000-000000000001', secuencia: 3, accion: 'reconocer' }),
      asiento({ id: '00000000-0000-4000-8000-000000000002', secuencia: 3, accion: 'posponer', hasta: new Date(AHORA + 3_600_000).toISOString() }),
    ], AHORA)
    expect(compromisos).toHaveLength(0)
  })

  it('un alerta_id fuera de catálogo NO se esconde: etiqueta genérica, unidad neutra y fila visible', () => {
    const compromisos = derivarCompromisos([
      asiento({ alerta_id: 'grupo:tipo_nuevo_futuro:33333333-3333-4333-8333-333333333333' }),
      asiento({ id: '00000000-0000-4000-8000-000000000009', alerta_id: 'otra-cosa-rara', secuencia: 2 }),
    ], AHORA)
    expect(compromisos).toHaveLength(2)
    expect(compromisos.every((c) => c.etiqueta === ETIQUETA_TIPO_DESCONOCIDO)).toBe(true)
    expect(compromisos[0]!.cuanto).toBe('2 ítems')
    // El id ilegible no inventa supervisor.
    expect(compromisos.some((c) => c.supervisorId === '')).toBe(true)
  })

  it('acepta los ids del mundo demo (no UUID)', () => {
    const compromisos = derivarCompromisos(asientosDemoTrazabilidad(AHORA), AHORA)
    expect(compromisos).toHaveLength(3)
    expect(compromisos[0]!.supervisorId).toBe('d-sup1')
  })
})

describe('resumenCompromisos', () => {
  it('cuenta compromisos y supervisores distintos — y calla con la lista vacía', () => {
    expect(resumenCompromisos([])).toBeNull()
    const demo = derivarCompromisos(asientosDemoTrazabilidad(AHORA), AHORA)
    expect(resumenCompromisos(demo)).toBe('3 compromisos · 2 supervisores')
    expect(resumenCompromisos(demo.slice(0, 1))).toBe('1 compromiso · 1 supervisor')
  })

  it('un id corrupto (supervisor vacío) no infla el conteo de supervisores', () => {
    const compromisos = derivarCompromisos([
      asiento(),
      asiento({ id: '00000000-0000-4000-8000-000000000009', alerta_id: 'otra-cosa-rara', secuencia: 2 }),
    ], AHORA)
    expect(resumenCompromisos(compromisos)).toBe('2 compromisos · 1 supervisor')
    // Solo filas corruptas: se cuentan los compromisos y no se inventa autor.
    const soloCorrupto = compromisos.filter((c) => c.supervisorId === '')
    expect(resumenCompromisos(soloCorrupto)).toBe('1 compromiso')
  })
})
