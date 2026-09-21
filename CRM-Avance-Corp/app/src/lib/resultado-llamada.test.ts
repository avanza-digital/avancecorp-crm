import { describe, expect, it } from 'vitest'
import {
  INTENTOS_PARA_OFRECER_PERDIDO,
  RESULTADOS,
  RESULTADOS_LLAMADA,
  SUBMOTIVOS,
  SUBMOTIVOS_NO_INTERESADO,
  SUBMOTIVOS_PIDE_OTRO_PRODUCTO,
  definicionResultado,
  dentroDeVentanaLegal,
  esLlamadaUtil,
  esResultadoLlamada,
  etiquetaResultado,
  motivoDeDescarte,
  tipoDeResultado,
  tiposSiguientesDeResultado,
} from './resultado-llamada'

// ESPEJO DEL SERVIDOR (migración 20260920005000): el CHECK
// actividades_resultado_llamada_forma y el núcleo private.llamada_registrar
// aceptan EXACTAMENTE estas claves. Si este test cambia, cambia el servidor.
describe('catálogo del resultado de llamada (espejo del servidor)', () => {
  it('fija las 7 claves de resultado en el orden del mockup 5', () => {
    expect([...RESULTADOS_LLAMADA]).toEqual([
      'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
      'numero_errado', 'no_es_la_persona', 'pide_otro_producto',
    ])
    expect(RESULTADOS.map((r) => r.clave)).toEqual([...RESULTADOS_LLAMADA])
    expect(RESULTADOS.map((r) => r.atajo)).toEqual(['1', '2', '3', '4', '5', '6', '7'])
  })

  it('fija los submotivos y el motivo real de descarte al que mapean', () => {
    expect([...SUBMOTIVOS_NO_INTERESADO]).toEqual(['sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir', 'otro'])
    expect([...SUBMOTIVOS_PIDE_OTRO_PRODUCTO]).toEqual(['prestamo', 'credito', 'otro'])
    expect(SUBMOTIVOS.no_interesado.map((s) => [s.clave, s.motivo])).toEqual([
      ['sin_fondos_ahora', 'sin_fondos'], ['ya_invirtio_con_otro', 'competencia'],
      ['desconfianza', 'sin_interes'], ['no_le_interesa_invertir', 'sin_interes'], ['otro', 'sin_interes'],
    ])
    expect(SUBMOTIVOS.pide_otro_producto.every((s) => s.motivo === 'pide_credito')).toBe(true)
  })

  it('mapea resultado → tipo de actividad como el núcleo', () => {
    expect(tipoDeResultado('no_contesto')).toBe('llamada_no_contestada')
    expect(tipoDeResultado('numero_errado')).toBe('llamada_no_contestada')
    expect(tipoDeResultado('no_es_la_persona')).toBe('llamada_no_contestada')
    for (const r of ['volver_a_llamar', 'agendo_reunion', 'no_interesado', 'pide_otro_producto'] as const) {
      expect(tipoDeResultado(r)).toBe('llamada_realizada')
    }
  })

  it('«no le interesa» y «pide otro producto» ofrecen el descarte como decisión separada', () => {
    expect(RESULTADOS.filter((r) => r.descarteOpcional).map((r) => r.clave)).toEqual(['no_interesado', 'pide_otro_producto'])
    expect(motivoDeDescarte('no_interesado', 'sin_fondos_ahora')).toBe('sin_fondos')
    expect(motivoDeDescarte('no_interesado', 'prestamo')).toBeNull()
    expect(motivoDeDescarte('pide_otro_producto', 'credito')).toBe('pide_credito')
    expect(motivoDeDescarte('numero_errado', null)).toBe('datos_invalidos')
    expect(motivoDeDescarte('no_contesto', null)).toBe('no_responde')
    expect(motivoDeDescarte('volver_a_llamar', null)).toBeNull()
  })

  it('ofrece las cuatro acciones de la ficha para seguimiento sin ampliar los otros resultados', () => {
    for (const resultado of ['no_interesado', 'pide_otro_producto'] as const) {
      expect(tiposSiguientesDeResultado(resultado)).toEqual(['llamada', 'whatsapp', 'reunion', 'tarea'])
    }
    expect(tiposSiguientesDeResultado('no_contesto')).toEqual(['llamada', 'whatsapp'])
    expect(tiposSiguientesDeResultado('volver_a_llamar')).toEqual(['llamada'])
    expect(tiposSiguientesDeResultado('agendo_reunion')).toEqual(['reunion'])
    expect(tiposSiguientesDeResultado('numero_errado')).toEqual(['llamada'])
  })

  it('número errado y «no es la persona» no entran en la tasa de contacto', () => {
    expect(esLlamadaUtil('numero_errado')).toBe(false)
    expect(esLlamadaUtil('no_es_la_persona')).toBe(false)
    expect(esLlamadaUtil('no_contesto')).toBe(true)
    // Histórico sin resultado: cuenta (no hay evidencia para excluirlo).
    expect(esLlamadaUtil(null)).toBe(true)
    expect(esLlamadaUtil(undefined)).toBe(true)
  })

  it('habla de «cita», no de reunión, y narra el resultado en corto', () => {
    expect(definicionResultado('agendo_reunion').etiqueta).toBe('Contestó · agendó cita')
    expect(RESULTADOS.some((r) => /reuni/i.test(`${r.etiqueta} ${r.detalle}`))).toBe(false)
    expect(etiquetaResultado('agendo_reunion')).toBe('Agendó cita')
    expect(etiquetaResultado('no_contesto')).toBe('No contestó')
    expect(etiquetaResultado('lo_que_sea')).toBe('lo_que_sea')
    expect(esResultadoLlamada('fax')).toBe(false)
  })

  it('la ventana legal es L–S 07:00–20:00 en reloj de Lima (espejo del núcleo)', () => {
    expect(dentroDeVentanaLegal('2026-09-21T15:00:00.000Z')).toBe(true)   // lunes 10:00 Lima
    expect(dentroDeVentanaLegal('2026-09-21T11:59:00.000Z')).toBe(false)  // lunes 06:59 Lima
    expect(dentroDeVentanaLegal('2026-09-21T12:00:00.000Z')).toBe(true)   // lunes 07:00 Lima
    expect(dentroDeVentanaLegal('2026-09-22T00:59:00.000Z')).toBe(true)   // lunes 19:59 Lima
    expect(dentroDeVentanaLegal('2026-09-22T01:00:00.000Z')).toBe(false)  // lunes 20:00 Lima
    expect(dentroDeVentanaLegal('2026-09-20T15:00:00.000Z')).toBe(false)  // domingo 10:00 Lima
    expect(dentroDeVentanaLegal('2026-09-19T15:00:00.000Z')).toBe(true)   // sábado 10:00 Lima
    expect(dentroDeVentanaLegal('basura')).toBe(false)
  })

  it('ofrece «marcar perdido» recién al sexto intento', () => {
    expect(INTENTOS_PARA_OFRECER_PERDIDO).toBe(6)
  })
})
