import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  BandejaSchema, DetalleLlamadaSchema, EnlaceV5Schema, MarcaCelularSchema, ResueltasHoySchema,
  accionPrincipal, comoSeResolvio, cuandoFue, estadoPendiente, estadoResuelta, etiquetaMotivoDescarte, haceCuanto,
  lineaPendiente, lineaResultadoGuardado, llegoTarde, numeroLegible, puedeRegistrarCorregido, puedeUnir, resultadosParaUnir,
  retrasoPendiente, textoEnlace,
  type FilaBandeja, type ResueltaHoy, type ResultadoGuardado,
} from './llamadas-celular'

// 05/10/2026 10:58 en Lima (15:58 UTC).
const AHORA = Date.parse('2026-10-05T15:58:00Z')
const fila = (extra: Partial<FilaBandeja> = {}): FilaBandeja => ({
  evento_id: 'e1', recibido_en: '2026-10-05T15:42:11Z', ocurrio_en: '2026-10-05T15:42:00Z', numero: '+51987654322',
  direccion: 'saliente', estado_tecnico: 'conectada', duracion_seg: 95, identificacion: 'identificado',
  atencion: 'requiere_resultado', lead_id: 'l2', lead_nombre: 'MARÍA LÓPEZ', analista_id: 'a1', es_propia: true, ...extra,
})
const resuelta = (extra: Partial<ResueltaHoy> = {}): ResueltaHoy => ({
  evento_id: 'e2', resuelto_en: '2026-10-05T14:04:00.123456+00:00', recibido_en: '2026-10-05T14:00:11Z', ocurrio_en: '2026-10-05T14:00:00Z', numero: '+51911223344',
  atencion: 'registrado', lead_id: 'l15', lead_nombre: 'TERESA', analista_id: 'a1', es_propia: true, etiqueta: 'C1',
  actividad_id: 'act', resultado: 'agendo_reunion', deshecho: false, via: 'al_colgar', motivo_descarte: null,
  motivo_descarte_detalle: null, ...extra,
})

describe('contrato de las puertas de llamadas del celular', () => {
  it('la bandeja valida sus filas; el id de la llamada es opcional (llega con la décima)', () => {
    const ok = v.safeParse(BandejaSchema, { filas: [fila(), { ...fila(), evento_id: 'e9', evento_origen_id: 'C1-1791226934' }], siguiente: null })
    expect(ok.success).toBe(true)
    expect(v.safeParse(BandejaSchema, { filas: [{ ...fila(), atencion: 'otra' }], siguiente: null }).success).toBe(false)
    expect(v.safeParse(BandejaSchema, { filas: [{ ...fila(), identificacion: 'quizas' }], siguiente: null }).success).toBe(false)
    expect(v.safeParse(BandejaSchema, [fila()]).success).toBe(false)
  })

  it('«Qué pasó hoy», la marca y el detalle validan su forma', () => {
    const pagina = v.safeParse(ResueltasHoySchema, {
      filas: [resuelta(), resuelta({ atencion: 'descartado_con_motivo', via: null, resultado: null })],
      siguiente: { resuelto_en: '2026-10-05T14:04:00.123456+00:00', evento_id: 'e2' },
    })
    expect(pagina.success).toBe(true)
    // El cursor sale tal cual: los microsegundos no se pierden.
    expect(pagina.success && pagina.output.siguiente?.resuelto_en).toBe('2026-10-05T14:04:00.123456+00:00')
    expect(v.safeParse(ResueltasHoySchema, { filas: [resuelta({ atencion: 'requiere_resultado' as never })], siguiente: null }).success).toBe(false)
    expect(v.safeParse(ResueltasHoySchema, { filas: [{ ...resuelta(), resuelto_en: undefined }], siguiente: null }).success).toBe(false)
    expect(v.safeParse(ResueltasHoySchema, [resuelta()]).success).toBe(false)
    expect(v.safeParse(MarcaCelularSchema, [{ actividad_id: 'a', evento_id: 'e', etiqueta: 'C1', via: 'pestana' }]).success).toBe(true)
    expect(v.safeParse(MarcaCelularSchema, [{ actividad_id: 'a', evento_id: 'e', etiqueta: 'C1', via: 'adivinada' }]).success).toBe(false)
    const { evento_id: _e, ...sinId } = { ...fila(), calidad: {}, metodo_asociacion: 'exacto', motivo_descarte: null, motivo_descarte_detalle: null, actividad_id: null, efectos_anulados: false }
    expect(v.safeParse(DetalleLlamadaSchema, { evento_id: 'e1', ...sinId }).success).toBe(true)
    // Con la décima el detalle trae el id de origen; sin ella, no (los dos valen).
    expect(v.safeParse(DetalleLlamadaSchema, { evento_id: 'e1', evento_origen_id: 'C1-1791226934', ...sinId }).success).toBe(true)
    expect(v.safeParse(DetalleLlamadaSchema, { evento_id: 'e1', evento_origen_id: 17, ...sinId }).success).toBe(false)
  })

  it('el enlace de la v5: null sin id; los cinco estados; un motivo desconocido tiene texto seguro', () => {
    for (const enlace of [null, { estado: 'enlazado' }, { estado: 'movido' }, { estado: 'repetido' }, { estado: 'pendiente' },
      { estado: 'no_enlazado', motivo: 'resultado_en_uso' }]) {
      expect(v.safeParse(EnlaceV5Schema, enlace).success, JSON.stringify(enlace)).toBe(true)
    }
    expect(v.safeParse(EnlaceV5Schema, { estado: 'no_enlazado', motivo: 'inventado' }).success).toBe(true)
    expect(textoEnlace({ estado: 'no_enlazado', motivo: 'inventado' }, 'hoy')).toContain('no se pudo confirmar el enlace')
    expect(v.safeParse(EnlaceV5Schema, { estado: 'otro' }).success).toBe(false)
  })
})

describe('textos de la pestaña', () => {
  it('cuándo y hace cuánto, en Lima', () => {
    expect(cuandoFue(Date.parse('2026-10-05T15:42:00Z'), AHORA)).toBe('a las 10:42')
    expect(cuandoFue(Date.parse('2026-10-04T23:05:00Z'), AHORA)).toBe('ayer a las 18:05')
    expect(cuandoFue(Date.parse('2026-10-03T23:05:00Z'), AHORA)).toBe('el 03/10 a las 18:05')
    expect(haceCuanto(AHORA - 16 * 60_000, AHORA)).toBe('hace 16 min')
    expect(haceCuanto(AHORA - 2 * 3_600_000, AHORA)).toBe('hace 2 h')
    expect(haceCuanto(AHORA - 30 * 3_600_000, AHORA)).toBe('hace 1 día')
    expect(haceCuanto(AHORA + 60_000, AHORA)).toBe('hace un momento')
  })

  it('el número se lee con espacios; sin número, «número oculto»', () => {
    expect(numeroLegible('+51987654322')).toBe('+51 987 654 322')
    expect(numeroLegible('+12025550123')).toBe('+12025550123')
    expect(numeroLegible(null)).toBe('número oculto')
  })

  it('la línea de una pendiente; la ambigua NO dice cuántos leads (la base no lo guarda)', () => {
    expect(lineaPendiente(fila(), AHORA)).toBe('Llamaste a las 10:42 · hace 16 min · +51 987 654 322')
    expect(lineaPendiente(fila({ identificacion: 'ambiguo', lead_id: null }), AHORA)).toBe('Llamaste a las 10:42 · hace 16 min · más de un lead podría tener este número')
    expect(lineaPendiente(fila({ identificacion: 'sin_identificar', lead_id: null }), AHORA)).toMatch(/ningún lead de tu cartera/)
    expect(lineaPendiente(fila({ ocurrio_en: null }), AHORA)).toBe('Llamaste a las 10:42 · hace 15 min · +51 987 654 322')
  })

  it('qué pide y qué se puede hacer', () => {
    expect(estadoPendiente('requiere_resultado')).toBe('Pide resultado')
    expect(estadoPendiente('por_revisar')).toBe('Por revisar')
    expect(estadoPendiente('requiere_devolucion')).toBe('Devolver la llamada')
    expect(accionPrincipal(fila())).toBe('registrar')
    expect(accionPrincipal(fila({ atencion: 'por_revisar' }))).toBe('registrar')
    expect(accionPrincipal(fila({ identificacion: 'ambiguo', lead_id: null }))).toBe('elegir')
  })

  it('«Registrar el corregido» (P9): solo la propia, registrada, deshecha, con lead y con el id de la llamada', () => {
    const deshecha = resuelta({ deshecho: true, evento_origen_id: 'C1-1791226920' })
    expect(puedeRegistrarCorregido(deshecha)).toBe(true)
    expect(puedeRegistrarCorregido({ ...deshecha, deshecho: false })).toBe(false)
    // De otro analista (lead reasignado): la v5 respondería «celular_ajeno».
    expect(puedeRegistrarCorregido({ ...deshecha, es_propia: false })).toBe(false)
    expect(puedeRegistrarCorregido({ ...deshecha, atencion: 'descartado_con_motivo' })).toBe(false)
    expect(puedeRegistrarCorregido({ ...deshecha, lead_id: null })).toBe(false)
    expect(puedeRegistrarCorregido(resuelta({ deshecho: true }))).toBe(false)
  })

  it('la que llegó tarde y la que lleva horas sin resultado', () => {
    const tarde = fila({ ocurrio_en: '2026-10-04T23:05:00Z', recibido_en: '2026-10-05T12:00:00Z' })
    expect(llegoTarde(tarde)).toBe(true)
    expect(llegoTarde(fila())).toBe(false)
    expect(llegoTarde(fila({ ocurrio_en: null }))).toBe(false)
    expect(retrasoPendiente(tarde, AHORA)).toBe('Lleva 16 h')
    expect(retrasoPendiente(fila(), AHORA)).toBeNull()
  })

  it('lo resuelto: su resultado (y si se deshizo) o su motivo, y cómo', () => {
    expect(estadoResuelta(resuelta())).toBe('Agendó cita')
    expect(estadoResuelta(resuelta({ resultado: 'no_contesto', deshecho: true }))).toBe('No contestó · deshecho')
    expect(estadoResuelta(resuelta({ atencion: 'descartado_con_motivo', motivo_descarte: 'personal' }))).toBe('Descartada · Llamada personal')
    expect(estadoResuelta(resuelta({ atencion: 'descartado_con_motivo', motivo_descarte: 'otro', motivo_descarte_detalle: 'Era mi primo' })))
      .toBe('Descartada · Era mi primo')
    expect(comoSeResolvio(resuelta())).toMatch(/al colgar/)
    expect(comoSeResolvio(resuelta({ via: 'pestana' }))).toMatch(/desde «Llamadas del celular»/)
    expect(comoSeResolvio(resuelta({ via: 'manual' }))).toMatch(/ya estaba guardado/)
    expect(etiquetaMotivoDescarte('otro', '  ')).toBe('Otro motivo')
  })

  it('lo que se dice tras guardar con el id: unida, pendiente o por qué no; solo promete la pestaña si la llamada sigue ahí', () => {
    expect(textoEnlace(null, 'a las 10:42')).toBeNull()
    expect(textoEnlace({ estado: 'enlazado' }, 'a las 10:42')).toBe('Quedó unido a tu llamada del celular a las 10:42.')
    expect(textoEnlace({ estado: 'pendiente' }, 'a las 10:42')).toMatch(/en cuanto llegue su aviso/)
    expect(textoEnlace({ estado: 'no_enlazado', motivo: 'resultado_en_uso' }, 'x')).toMatch(/sigue en «Llamadas del celular»/)
    expect(textoEnlace({ estado: 'no_enlazado', motivo: 'celular_ajeno' }, 'x')).not.toMatch(/sigue en/)
    expect(textoEnlace({ estado: 'no_enlazado', motivo: 'sin_llamada' }, 'x')).toMatch(/no es de un lead de tu cartera/)
  })
})

// Unir a mano (F4.2.4, B7): el espejo de lo que crm.enlazar_llamada_celular acepta.
describe('unir a mano', () => {
  const guardado = (id: string, creado_en: string, extra: Partial<ResultadoGuardado> = {}): ResultadoGuardado => ({
    id, lead_id: 'l2', tipo: 'llamada_no_contestada', creado_en, autor_nombre: 'ANA SOTO',
    metadata: { evento: 'resultado_llamada', resultado: 'no_contesto' }, ...extra,
  })

  it('solo una pendiente identificada con lead se puede unir', () => {
    expect(puedeUnir(fila())).toBe(true)
    expect(puedeUnir(fila({ lead_id: null }))).toBe(false)
    expect(puedeUnir(fila({ identificacion: 'ambiguo', lead_id: null }))).toBe(false)
  })

  it('candidatos: del lead, resultados de llamada vivos, desde 10 min antes de la llamada, sin unir; del más reciente al más viejo', () => {
    // La llamada fue a las 15:42Z: el margen admite desde las 15:32Z.
    const lista = [
      guardado('justo', '2026-10-05T15:33:00Z'),
      guardado('reciente', '2026-10-05T15:50:00Z', { tipo: 'llamada_realizada', metadata: { evento: 'resultado_llamada', resultado: 'agendo_reunion' } }),
      guardado('antes', '2026-10-05T15:31:00Z'),
      guardado('otro-lead', '2026-10-05T15:50:00Z', { lead_id: 'l9' }),
      guardado('nota', '2026-10-05T15:50:00Z', { tipo: 'nota', metadata: undefined }),
      guardado('deshecho', '2026-10-05T15:50:00Z', { metadata: { evento: 'resultado_llamada', resultado: 'no_contesto', deshecho_en: '2026-10-05T15:55:00Z' } }),
      guardado('unido', '2026-10-05T15:50:00Z'),
      guardado('local', '2026-10-05T15:51:00Z', { local: true }),
    ]
    expect(resultadosParaUnir(fila(), lista, new Set(['unido'])).map((r) => r.id)).toEqual(['reciente', 'justo'])
    // El espejo optimista del navegador (id inventado) solo vale en la demo.
    expect(resultadosParaUnir(fila(), lista, new Set(['unido']), { conLocales: true }).map((r) => r.id)).toEqual(['local', 'reciente', 'justo'])
    // Sin hora de la llamada manda la de recepción.
    expect(resultadosParaUnir(fila({ ocurrio_en: null, recibido_en: '2026-10-05T15:45:00Z' }), lista, new Set()).map((r) => r.id)).toEqual(['reciente', 'unido'])
  })

  it('cada candidato dice su resultado, cuándo se guardó y quién', () => {
    expect(lineaResultadoGuardado(guardado('a', '2026-10-05T15:50:00Z'), AHORA)).toBe('No contestó · guardado a las 10:50 · por ANA SOTO')
    expect(lineaResultadoGuardado(guardado('b', '2026-10-04T15:50:00Z', { metadata: { evento: 'resultado_llamada' } }), AHORA))
      .toBe('Resultado de llamada · guardado ayer a las 10:50 · por ANA SOTO')
  })
})
