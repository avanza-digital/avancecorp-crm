import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'
import {
  claveRegistroRespuestas, claveRespuestaTasa, conBloqueoRespuestas, crearSonidoRespuesta,
  esRespuestaPropia, guardarRegistroRespuestas, incorporarRespuestas, leerRegistroRespuestas,
  CLAVE_SENAL_SOLICITUD_TASA, intervaloConsultaRespuestas, recibeRespuestasTasa, senalarSolicitudTasaCreada, tituloRespuestaTasa,
} from './respuestas-tasa'

function solicitud(cambios: Partial<SolicitudTasa> = {}): SolicitudTasa {
  return { id: 's-1', es_mia: true, solicitada_por: 'v-1', resuelta_por: 'g-1',
    resuelta_en: '2026-09-11T15:00:00Z', estado: 'aprobada', estado_efectivo: 'aprobada',
    tasa_solicitada: 18, tasa_maxima_autorizada: 18, ...cambios } as SolicitudTasa
}

describe('registro local de respuestas de tasa', () => {
  beforeEach(() => localStorage.clear())

  it('solo analistas y supervisores reciben sus propias decisiones confirmadas', () => {
    expect(recibeRespuestasTasa('vendedor')).toBe(true)
    expect(recibeRespuestasTasa('supervisor')).toBe(true)
    for (const rol of ['gerencia', 'directorio', 'admin', null, undefined]) expect(recibeRespuestasTasa(rol)).toBe(false)
    expect(esRespuestaPropia(solicitud(), 'v-1')).toBe(true)
    for (const cambio of [{ es_mia: false }, { solicitada_por: 'v-2' }, { resuelta_por: null }, { resuelta_en: null }, { resuelta_en: 'no-fecha' }]) {
      expect(esRespuestaPropia(solicitud(cambio), 'v-1')).toBe(false)
    }
  })

  it('la primera carga no anuncia históricos; cada resolución posterior se anuncia una sola vez', () => {
    const primera = incorporarRespuestas(leerRegistroRespuestas('v-1'), [solicitud()], 'v-1')
    expect(primera.nuevas).toEqual([])
    const nueva = solicitud({ id: 's-2', tasa_maxima_autorizada: null, estado: 'rechazada' })
    const segunda = incorporarRespuestas(primera.registro, [solicitud(), nueva, solicitud({ id: 'ajena', solicitada_por: 'v-2' })], 'v-1')
    expect(segunda.nuevas).toEqual([nueva])
    expect(segunda.registro.respuestas[claveRespuestaTasa(nueva)]).toBe(false)
    guardarRegistroRespuestas('v-1', segunda.registro)
    expect(incorporarRespuestas(leerRegistroRespuestas('v-1'), [nueva], 'v-1').nuevas).toEqual([])
    expect(leerRegistroRespuestas('v-2').iniciado).toBe(false)
  })

  it('una bandeja inicialmente vacía captura la primera respuesta y no confunde consumo con otra decisión', () => {
    const inicial = incorporarRespuestas(leerRegistroRespuestas('v-1'), [], 'v-1')
    const s = solicitud()
    const resuelta = incorporarRespuestas(inicial.registro, [s], 'v-1')
    expect(resuelta.nuevas).toEqual([s])
    const consumida = solicitud({ estado: 'consumida', estado_efectivo: 'consumida' })
    expect(incorporarRespuestas(resuelta.registro, [consumida], 'v-1').nuevas).toEqual([])
    expect(tituloRespuestaTasa(consumida)).toContain('aprobada')
    expect(tituloRespuestaTasa(solicitud({ tasa_maxima_autorizada: 16 }))).toContain('tope')
    expect(tituloRespuestaTasa(solicitud({ tasa_maxima_autorizada: null }))).toContain('rechazada')
  })

  it('preserva leído al reencontrar la respuesta después de una carga incompleta', () => {
    const registro = { ...leerRegistroRespuestas('v-1'), iniciado: true }
    const s = solicitud()
    registro.respuestas[claveRespuestaTasa(s)] = true
    const vacia = incorporarRespuestas(registro, [], 'v-1')
    expect(incorporarRespuestas(vacia.registro, [s], 'v-1').nuevas).toHaveLength(0)
    expect(vacia.registro.respuestas[claveRespuestaTasa(s)]).toBe(true)
  })

  it('tolera almacenamiento corrupto y no guarda nombres, motivos o tasas', () => {
    const clave = claveRegistroRespuestas('v-1')
    for (const texto of ['{', 'null', '[]', '{}']) {
      localStorage.setItem(clave, texto)
      expect(leerRegistroRespuestas('v-1').iniciado).toBe(false)
    }
    const resultado = incorporarRespuestas({ ...leerRegistroRespuestas('v-1'), iniciado: true }, [solicitud({ cliente_nombre: 'PERSONA PRIVADA', motivo_resolucion: 'MOTIVO PRIVADO' })], 'v-1')
    guardarRegistroRespuestas('v-1', resultado.registro)
    const texto = localStorage.getItem(clave)!
    expect(texto).not.toMatch(/PERSONA|MOTIVO|tasa_maxima|cliente_nombre/)
    expect(leerRegistroRespuestas('v-1').respuestas).toEqual(resultado.registro.respuestas)
  })

  it('acota la memoria persistente y soporta bloqueo de almacenamiento durante la sesión', () => {
    const registro = { ...leerRegistroRespuestas('v-3'), iniciado: true, respuestas: Object.fromEntries(Array.from({ length: 1100 }, (_, i) => [`s-${i}|2026-09-11T15:00:00Z`, true])) }
    expect(guardarRegistroRespuestas('v-3', registro)).toBe(true)
    expect(Object.keys(leerRegistroRespuestas('v-3').respuestas)).toHaveLength(1000)
    // Storage de jsdom es un proxy: espiar sus métodos en la instancia no
    // garantiza sustituirlos. El global explícito funciona también en Node 24.
    const bloqueado = vi.fn(() => { throw new Error('bloqueado') })
    vi.stubGlobal('localStorage', { setItem: bloqueado, getItem: bloqueado })
    try {
      expect(guardarRegistroRespuestas('v-3', { ...registro, sonido: true })).toBe(false)
      expect(bloqueado).toHaveBeenCalledOnce()
      expect(leerRegistroRespuestas('v-3').sonido).toBe(true)
    } finally { vi.unstubAllGlobals() }
  })

  it('dos pestañas serializan la incorporación y solo una obtiene la alerta', async () => {
    let cola = Promise.resolve<unknown>(undefined)
    vi.stubGlobal('navigator', { locks: { request: (_nombre: string, fn: () => unknown) => { cola = cola.then(fn); return cola } } })
    guardarRegistroRespuestas('v-1', { ...leerRegistroRespuestas('v-1'), iniciado: true })
    const incorporar = () => conBloqueoRespuestas('v-1', () => {
      const r = incorporarRespuestas(leerRegistroRespuestas('v-1'), [solicitud()], 'v-1')
      guardarRegistroRespuestas('v-1', r.registro)
      return r.nuevas.length
    })
    expect(await Promise.all([incorporar(), incorporar()])).toEqual([1, 0])
    vi.unstubAllGlobals()
  })

  it('el audio necesita activación y se cierra al terminar la sesión', async () => {
    const cerrar = vi.fn(async () => {})
    const iniciarTono = vi.fn()
    const contexto = { state: 'suspended', currentTime: 0, destination: {}, resume: vi.fn(async () => { contexto.state = 'running' }), close: cerrar,
      createOscillator: () => ({ type: '', frequency: { value: 0 }, connect: vi.fn(), disconnect: vi.fn(), start: iniciarTono, stop: vi.fn(), onended: null }),
      createGain: () => ({ gain: { setValueAtTime: vi.fn(), linearRampToValueAtTime: vi.fn(), exponentialRampToValueAtTime: vi.fn() }, connect: vi.fn(), disconnect: vi.fn() }) }
    vi.stubGlobal('AudioContext', class { constructor() { return contexto } })
    const sonido = crearSonidoRespuesta()
    expect(sonido.sonar()).toBe(false)
    expect(await sonido.activar()).toBe(true)
    expect(sonido.sonar()).toBe(true)
    expect(iniciarTono).toHaveBeenCalledTimes(2)
    sonido.cerrar()
    expect(cerrar).toHaveBeenCalledOnce()
    expect(sonido.sonar()).toBe(false)
    vi.stubGlobal('AudioContext', class { constructor() { throw new Error('audio no soportado') } })
    expect(await crearSonidoRespuesta().activar()).toBe(false)
    vi.unstubAllGlobals()
  })
})

describe('ritmo de consulta de respuestas', () => {
  const pendiente = (cambios: Partial<SolicitudTasa> = {}) =>
    solicitud({ estado: 'pendiente', estado_efectivo: 'pendiente', resuelta_por: null, resuelta_en: null, ...cambios })

  it('pregunta cada 15 s solo mientras hay una solicitud propia pendiente de Gerencia', () => {
    expect(intervaloConsultaRespuestas([pendiente()], 'v-1')).toBe(15_000)
    expect(intervaloConsultaRespuestas([solicitud(), pendiente()], 'v-1')).toBe(15_000)
  })

  it('con la última consulta fallida vuelve a 15 s aunque no haya pendientes', () => {
    expect(intervaloConsultaRespuestas([], 'v-1', true)).toBe(15_000)
    expect(intervaloConsultaRespuestas([solicitud()], 'v-1', true)).toBe(15_000)
  })

  it('la señal de solicitud creada escribe solo la hora y no revienta sin almacenamiento', () => {
    senalarSolicitudTasaCreada()
    expect(Number(localStorage.getItem(CLAVE_SENAL_SOLICITUD_TASA))).toBeGreaterThan(0)
    const setItem = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('lleno') })
    expect(() => senalarSolicitudTasaCreada()).not.toThrow()
    setItem.mockRestore()
  })

  it('en reposo pregunta cada 2 min: sin datos, sin solicitudes, resueltas, vencidas o ajenas', () => {
    expect(intervaloConsultaRespuestas(undefined, 'v-1')).toBe(120_000)
    expect(intervaloConsultaRespuestas([], 'v-1')).toBe(120_000)
    expect(intervaloConsultaRespuestas([solicitud()], 'v-1')).toBe(120_000)
    expect(intervaloConsultaRespuestas([pendiente({ estado_efectivo: 'vencida' })], 'v-1')).toBe(120_000)
    expect(intervaloConsultaRespuestas([pendiente({ es_mia: false })], 'v-1')).toBe(120_000)
    expect(intervaloConsultaRespuestas([pendiente({ solicitada_por: 'v-2' })], 'v-1')).toBe(120_000)
  })
})
