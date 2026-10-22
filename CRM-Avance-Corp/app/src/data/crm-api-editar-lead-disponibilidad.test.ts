// @vitest-environment node
// D-36 (bloque 2.8, ronda 2) — al EDITAR la ficha, el P0481 «Contacto no disponible» del disparador de disponibilidad se
// presenta COMO EN EL ALTA («Esta persona ya es cliente y está a cargo de X.») por las DOS rutas de `editarLeadFn`
// (`crm.editar_lead_fn` y `crm.editar_lead_documento_fn`), contra un Supabase SIMULADO con msw (contrato HTTP real).
// Solo los veredictos cuyo texto no habla de «registrar» ni de «crear»: ya_es_cliente, tomado, en_bolsa y enfriamiento.
// Los demás (no_contactar, reutilizable, error), un estado desconocido o un detalle vacío/ilegible conservan el texto fijo
// de hoy. Mismo código (CONTACTO_NO_DISPONIBLE) y mismo contexto de registro (crm.leads.editar_fallido); los errores que no
// son P0481 no cambian. El ALTA (`insertarLead`) se fija aquí también: comparte con la edición la lectura del veredicto
// y su comportamiento no cambia.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})
// El registro se espía (y no ensucia la consola): el contexto con que se registra el error es parte del contrato.
vi.mock('@/lib/observabilidad', async (importActual) => ({
  ...await importActual<typeof import('@/lib/observabilidad')>(),
  registrarError: vi.fn(),
}))

// Ronda 4 (nota F6 de Codex r2): la presentación del veredicto se espía con su implementación REAL por defecto; una prueba la hace
// lanzar una vez para caracterizar que `presentacionDelP0481` no propaga esa excepción.
vi.mock('@/lib/disponibilidad-lead', async (importActual) => {
  const actual = await importActual<typeof import('@/lib/disponibilidad-lead')>()
  return { ...actual, presentarDisponibilidadLead: vi.fn(actual.presentarDisponibilidadLead) }
})

import { registrarError } from '@/lib/observabilidad'
import { presentarDisponibilidadLead } from '@/lib/disponibilidad-lead'
import { CrmApiError, editarLeadFn, insertarLead } from './crm-api'

const LEAD_ID = '3f0c2a5e-8b1d-4c6a-9e2f-7a1b2c3d4e5f'
const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const TEXTO_FIJO = 'Ese teléfono o DNI no está disponible para este lead.'

const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

/** Lo que devuelve PostgREST cuando el disparador levanta `P0481` con el veredicto en el DETAIL (`detail = v::text`). */
const p0481 = (details: string | null) =>
  HttpResponse.json({ code: 'P0481', message: 'Contacto no disponible', details, hint: null }, { status: 400 })

async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
  try {
    await p
  } catch (e) {
    if (e instanceof CrmApiError) return e
    throw e
  }
  throw new Error('no falló')
}

/** Las dos rutas de la ficha: sin documento (`crm.editar_lead_fn`) y con documento (`crm.editar_lead_documento_fn`, la que
 *  usa la ficha fuera del demo: `lead-drawer.tsx` manda siempre el documento). */
const RUTAS: Array<{ rpc: string; editar: () => Promise<void> }> = [
  {
    rpc: 'editar_lead_fn',
    editar: () => editarLeadFn(LEAD_ID, { telefono: '+51911222333', nota: 'cambio de teléfono' }),
  },
  {
    rpc: 'editar_lead_documento_fn',
    editar: () => editarLeadFn(LEAD_ID, { telefono: '+51911222333', documento: { tipo: 'DNI', numero: '45678901' } }),
  },
]

/** Veredictos que la edición presenta con el texto del alta (D-36): ninguno habla de «registrar» ni de «crear». */
const PRESENTADOS: Array<[string, Record<string, unknown>, string]> = [
  ['ya_es_cliente con su asesor', { estado: 'ya_es_cliente', asesor: 'ANA ANALISTA' },
    'Esta persona ya es cliente y está a cargo de ANA ANALISTA.'],
  ['ya_es_cliente por identidad (via)', { estado: 'ya_es_cliente', asesor: 'ROSA DÍAZ', via: 'identidad' },
    'Esta persona ya es cliente y está a cargo de ROSA DÍAZ.'],
  ['ya_es_cliente «sin asesor asignado»', { estado: 'ya_es_cliente', asesor: 'sin asesor asignado' },
    'Esta persona ya es cliente de Avance Corp.'],
  ['ya_es_cliente «sin asesor asignado» por identidad (respaldo de D-21)',
    { estado: 'ya_es_cliente', asesor: 'sin asesor asignado', via: 'identidad' },
    'Esta persona ya es cliente de Avance Corp.'],
  ['tomado', { estado: 'tomado', vendedor: 'ANA PÉREZ', tenencia_desde: '2026-08-04T12:30:00.000Z' },
    'Este contacto ya está asignado a ANA PÉREZ.'],
  ['tomado sin analista', { estado: 'tomado', vendedor: null, tenencia_desde: null },
    'Este contacto ya está asignado a otro miembro del equipo.'],
  ['en_bolsa', { estado: 'en_bolsa' }, 'Este contacto ya se encuentra en la bolsa de leads.'],
  ['enfriamiento (fecha con el formato de Postgres; en Lima aún es el 10)',
    { estado: 'enfriamiento', motivo_descarte: 'no_responde', disponible_desde: '2026-08-11T04:30:00.123456+00:00', descartado_por: 'SUPERVISOR UNO' },
    'Este contacto está en periodo de enfriamiento por «No responde» hasta el 10 de agosto de 2026.'],
]

/** Veredictos VÁLIDOS cuyo texto del alta no sirve al editar: la edición conserva el texto fijo (el alta, el suyo). */
const NO_SE_PRESENTAN_AL_EDITAR: Array<[string, Record<string, unknown>, string]> = [
  ['no_contactar', { estado: 'no_contactar' },
    'Este contacto está marcado como «No contactar» y no se puede registrar nuevamente.'],
  ['reutilizable', {
    estado: 'reutilizable', motivo_descarte: 'no_responde', descartado_en: '2026-06-01T15:00:00Z',
    quedo_libre_en: '2026-07-01T15:00:00Z', descartado_por: null, ultima_conversacion_en: null,
  }, 'Este contacto tiene un seguimiento anterior que puede retomarse en lugar de crear un duplicado.'],
  ['error', { estado: 'error', detalle: 'telefono_invalido' }, 'Ingresa un teléfono válido para verificar su disponibilidad.'],
  ['libre (fuera de lugar en un rechazo)', { estado: 'libre' }, 'Este contacto no está disponible para un nuevo lead'],
]

/** Detalles que no cumplen el contrato del veredicto: nadie los refleja (ni el alta ni la edición). */
const DETALLES_ILEGIBLES: Array<[string, string | null]> = [
  ['estado desconocido', JSON.stringify({ estado: 'ya_es_socio', asesor: 'ANA ANALISTA' })],
  ['ya_es_cliente sin asesor (fuera de contrato)', JSON.stringify({ estado: 'ya_es_cliente' })],
  ['ya_es_cliente con una clave de más', JSON.stringify({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA', dni: '45678901' })],
  ['detalle vacío', ''],
  ['sin detalle (null)', null],
  ['detalle que no es JSON', 'Key (telefono)=(+51911222333) ya es de ANA ANALISTA'],
  ['JSON que no es un objeto', '"ya_es_cliente"'],
]

/** Errores que no son P0481 (aunque traigan un veredicto en el detalle): la edición los traduce igual que hoy. */
const OTROS_ERRORES: Array<[string, { code: string; message: string; details: string | null }, number, { code: string; message: string }]> = [
  ['P0409 de la puerta del DNI, aun con un veredicto en el detalle', {
    code: 'P0409',
    message: 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este',
    details: JSON.stringify({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA' }),
  }, 400, { code: 'CONFLICTO', message: 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este' }],
  ['23505 del teléfono vivo', {
    code: '23505', message: 'duplicate key value violates unique constraint "uq_leads_telefono_vivo"', details: null,
  }, 409, { code: 'DUP_TELEFONO', message: 'Ese teléfono ya pertenece a otro lead abierto de la empresa' }],
  ['42501 (rol sin permiso)', { code: '42501', message: 'Acceso CRM revocado', details: null }, 403,
    { code: 'SIN_PERMISO', message: 'No tienes permiso para esa acción' }],
  ['P0429 («No insistir»)', { code: 'P0429', message: 'La persona tiene la restricción «No insistir»', details: null }, 400,
    { code: 'NO_INSISTA', message: 'La persona tiene la restricción «No insistir»' }],
  ['55P03 (fila retenida)', { code: '55P03', message: 'canceling statement due to lock timeout', details: null }, 400,
    { code: 'REINTENTAR', message: 'Otro usuario está editando a este cliente ahora mismo. Vuelve a intentarlo.' }],
  ['código desconocido con un veredicto en el detalle', {
    code: 'XX000', message: 'detalle interno', details: JSON.stringify({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA' }),
  }, 500, { code: 'POSTGREST_ERROR', message: 'No se pudo guardar el cambio.' }],
]

describe.each(RUTAS)('editarLeadFn por crm.$rpc — el P0481 con veredicto (D-36)', ({ rpc, editar }) => {
  it.each(PRESENTADOS)('%s → el mensaje del alta, CONTACTO_NO_DISPONIBLE, registrado en crm.leads.editar_fallido',
    async (_caso, veredicto, mensaje) => {
      server.use(http.post(RPC(rpc), () => p0481(JSON.stringify(veredicto))))
      const e = await fallo(editar())
      expect(e.message).toBe(mensaje)
      expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
      // El registro es el de hoy: mismo contexto y solo el código de Postgres (el veredicto no viaja al registro).
      expect(registrarError).toHaveBeenCalledTimes(1)
      expect(registrarError).toHaveBeenCalledWith('crm.leads.editar_fallido', e, { pg: 'P0481' })
    })

  it.each(NO_SE_PRESENTAN_AL_EDITAR)('%s → el texto fijo de hoy, sin el texto del alta', async (_caso, veredicto) => {
    server.use(http.post(RPC(rpc), () => p0481(JSON.stringify(veredicto))))
    const e = await fallo(editar())
    expect(e.message).toBe(TEXTO_FIJO)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith('crm.leads.editar_fallido', e, { pg: 'P0481' })
  })

  it.each(DETALLES_ILEGIBLES)('%s → el texto fijo de hoy, sin volcar el detalle', async (_caso, details) => {
    server.use(http.post(RPC(rpc), () => p0481(details)))
    const e = await fallo(editar())
    expect(e.message).toBe(TEXTO_FIJO)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith('crm.leads.editar_fallido', e, { pg: 'P0481' })
  })

  it.each(OTROS_ERRORES)('un error que no es P0481 sigue igual: %s', async (_caso, cuerpo, status, esperado) => {
    server.use(http.post(RPC(rpc), () => HttpResponse.json({ ...cuerpo, hint: null }, { status })))
    const e = await fallo(editar())
    expect({ code: e.code, message: e.message }).toEqual(esperado)
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith('crm.leads.editar_fallido', e, { pg: cuerpo.code })
  })
})

const ALTA = {
  id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
  nombre_completo: 'CONTACTO DE PRUEBA',
  telefono: '+51911222333',
  origen: 'formulario' as const,
  monto_estimado: 10_000,
  moneda: 'PEN' as const,
}

describe('insertarLead (alta): la lectura del veredicto que comparte con la edición no cambia su comportamiento', () => {
  it.each([...PRESENTADOS, ...NO_SE_PRESENTAN_AL_EDITAR])(
    '%s → su texto de siempre, registrado en crm.leads.creacion_atomica_bloqueada',
    async (_caso, veredicto, mensaje) => {
      server.use(http.post(RPC('crear_lead_si_disponible'), () => p0481(JSON.stringify(veredicto))))
      const e = await fallo(insertarLead(ALTA))
      expect(e.message).toBe(mensaje)
      expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
      expect(registrarError).toHaveBeenCalledTimes(1)
      expect(registrarError).toHaveBeenCalledWith('crm.leads.creacion_atomica_bloqueada', e, { estado: veredicto.estado })
    })

  it.each(DETALLES_ILEGIBLES)('%s → cae al texto fijo de aErrorApi (crm.leads.insert_fallido)', async (_caso, details) => {
    server.use(http.post(RPC('crear_lead_si_disponible'), () => p0481(details)))
    const e = await fallo(insertarLead(ALTA))
    expect(e.message).toBe(TEXTO_FIJO)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith('crm.leads.insert_fallido', e, { pg: 'P0481' })
  })
})

// Ronda 3 del 2.8 (Codex F6): en el ALTA, construir y registrar el bloqueo vive dentro del mismo `try` que leer el veredicto,
// como antes de D-36: si el registro lanza, el alta cae al error genérico de siempre (y lo registra allí) en vez de propagar la
// excepción del registrador. Un registrador que falla SOLO la primera vez distingue los dos comportamientos.
describe('insertarLead (alta): si registrar el bloqueo lanza, cae al error genérico como antes de D-36 (ronda 3)', () => {
  it('el registrador lanza la primera vez → el texto fijo de aErrorApi, registrado después en crm.leads.insert_fallido', async () => {
    vi.mocked(registrarError).mockImplementationOnce(() => {
      throw new Error('el registrador falló')
    })
    server.use(http.post(RPC('crear_lead_si_disponible'), () =>
      p0481(JSON.stringify({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA' }))))
    const e = await fallo(insertarLead(ALTA))
    expect(e.message).toBe(TEXTO_FIJO)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).toHaveBeenCalledTimes(2)
    expect(registrarError).toHaveBeenNthCalledWith(1, 'crm.leads.creacion_atomica_bloqueada', expect.any(CrmApiError), {
      estado: 'ya_es_cliente',
    })
    expect(registrarError).toHaveBeenNthCalledWith(2, 'crm.leads.insert_fallido', e, { pg: 'P0481' })
  })
})

// Ronda 4 del 2.8 (nota F6 de Codex r2): `presentacionDelP0481` no lanza. Fuera de su propio `try` solo queda leer `error.code` (que
// `aErrorInsertarLead` ya lee antes, y que antes de D-36 también se leía fuera del `try`); leer el detalle, validarlo y PRESENTARLO van
// dentro y devuelven `null`. Si la presentación lanza (p. ej. el `TypeError` de un estado no soportado), el alta y las dos rutas de la
// edición caen a su error genérico de siempre, registrado con su contexto, sin propagar la excepción.
const VEREDICTO_VALIDO = JSON.stringify({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA' })
const presentacionQueLanza = () => {
  vi.mocked(presentarDisponibilidadLead).mockImplementationOnce(() => {
    throw new TypeError('Estado de disponibilidad no soportado')
  })
}

describe('presentacionDelP0481 no lanza aunque lance la presentación del veredicto (ronda 4)', () => {
  it('alta: la presentación lanza → el texto fijo de aErrorApi, registrado en crm.leads.insert_fallido', async () => {
    presentacionQueLanza()
    server.use(http.post(RPC('crear_lead_si_disponible'), () => p0481(VEREDICTO_VALIDO)))
    const e = await fallo(insertarLead(ALTA))
    expect(presentarDisponibilidadLead).toHaveBeenCalledTimes(1)
    expect(e.message).toBe(TEXTO_FIJO)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith('crm.leads.insert_fallido', e, { pg: 'P0481' })
  })

  it.each(RUTAS)('edición por crm.$rpc: la presentación lanza → el texto fijo de hoy, registrado en crm.leads.editar_fallido',
    async ({ rpc, editar }) => {
      presentacionQueLanza()
      server.use(http.post(RPC(rpc), () => p0481(VEREDICTO_VALIDO)))
      const e = await fallo(editar())
      expect(presentarDisponibilidadLead).toHaveBeenCalledTimes(1)
      expect(e.message).toBe(TEXTO_FIJO)
      expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
      expect(registrarError).toHaveBeenCalledTimes(1)
      expect(registrarError).toHaveBeenCalledWith('crm.leads.editar_fallido', e, { pg: 'P0481' })
    })

  it('sin la excepción, la misma presentación es la real (el espía no cambia nada)', async () => {
    server.use(http.post(RPC('crear_lead_si_disponible'), () => p0481(VEREDICTO_VALIDO)))
    const e = await fallo(insertarLead(ALTA))
    expect(e.message).toBe('Esta persona ya es cliente y está a cargo de ANA ANALISTA.')
    expect(registrarError).toHaveBeenCalledWith('crm.leads.creacion_atomica_bloqueada', e, { estado: 'ya_es_cliente' })
  })
})
