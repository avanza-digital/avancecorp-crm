// @vitest-environment node
// Bloque 2.16 (D-62, D-69, D-70, D-78) — «Reabrir», «rescatar descartes» y «deshacer un descarte» reconocen al cliente: cuando
// el lead conserva el teléfono, el alternativo o el DNI de un cliente, el servidor no lo devuelve a la cartera y responde
// `P0481` «Contacto no disponible» con el veredicto del alta en el DETAIL (`{"estado":"ya_es_cliente","asesor":…}`, con `"via"`
// si el cliente tiene persona; `{"estado":"no_contactar"}` si su persona está vetada). La pantalla lo presenta COMO EN EL ALTA y
// en la edición (D-36): «Esta persona ya es cliente y está a cargo de X.» (o «… de Avance Corp.» sin asesor), con el mismo código
// (CONTACTO_NO_DISPONIBLE) y el mismo contexto de registro de cada puerta. `no_contactar`, un estado desconocido o un detalle
// vacío/ilegible conservan el texto fijo de hoy; los demás errores no cambian. Contra un Supabase SIMULADO con msw (contrato
// HTTP real). «Tomar un lead libre» no entra: ya devuelve el veredicto como dato (`ResultadoTomaLeadSchema`).
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

import { registrarError } from '@/lib/observabilidad'
import { CrmApiError, deshacerDescarte, reabrirLead, rescatarDescartes } from './crm-api'

const LEAD_ID = '3f0c2a5e-8b1d-4c6a-9e2f-7a1b2c3d4e5f'
const EPISODIO_ID = '9a8b7c6d-5e4f-4a3b-9c2d-1e0f2a3b4c5d'
const ANALISTA_ID = '1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e'
const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const TEXTO_FIJO = 'Ese teléfono o DNI no está disponible para este lead.'

const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

/** Lo que devuelve PostgREST cuando la puerta levanta `P0481` con el veredicto en el DETAIL (`detail = v::text`). */
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

/** Las tres puertas de `crm-api.ts` con su contexto de registro de siempre. */
const PUERTAS: Array<{ puerta: string; rpc: string; contexto: string; llamar: () => Promise<void> }> = [
  { puerta: 'reabrirLead', rpc: 'reabrir_lead_fn', contexto: 'crm.leads.reabrir_fallido', llamar: () => reabrirLead(LEAD_ID) },
  {
    puerta: 'rescatarDescartes', rpc: 'rescatar_descartes', contexto: 'crm.rescate.reparto_fallido',
    llamar: () => rescatarDescartes([EPISODIO_ID], [ANALISTA_ID], true),
  },
  { puerta: 'deshacerDescarte', rpc: 'deshacer_descarte', contexto: 'crm.descarte.deshacer_fallido', llamar: () => deshacerDescarte(LEAD_ID) },
]

/** Lo que medió el VERDE del 2.16 (§5 del informe): el veredicto del alta, con y sin persona, con y sin asesor. */
const PRESENTADOS: Array<[string, Record<string, unknown>, string]> = [
  ['ya_es_cliente con su asesor', { estado: 'ya_es_cliente', asesor: 'Ana' }, 'Esta persona ya es cliente y está a cargo de Ana.'],
  ['ya_es_cliente por identidad (via)', { estado: 'ya_es_cliente', asesor: 'Ana', via: 'identidad' },
    'Esta persona ya es cliente y está a cargo de Ana.'],
  ['ya_es_cliente «sin asesor asignado»', { estado: 'ya_es_cliente', asesor: 'sin asesor asignado' },
    'Esta persona ya es cliente de Avance Corp.'],
]

/** El veto de la persona y los detalles que no cumplen el contrato del veredicto: el texto fijo de hoy. En «rescatar», el
 *  detalle es EXACTAMENTE el veredicto (D-70): con un `lead_id` de más, el esquema estricto no lo presenta. */
const TEXTO_FIJO_DE_HOY: Array<[string, string | null]> = [
  ['no_contactar', JSON.stringify({ estado: 'no_contactar' })],
  ['estado desconocido', JSON.stringify({ estado: 'ya_es_socio', asesor: 'Ana' })],
  ['ya_es_cliente sin asesor (fuera de contrato)', JSON.stringify({ estado: 'ya_es_cliente' })],
  ['ya_es_cliente con un lead_id de más', JSON.stringify({ estado: 'ya_es_cliente', asesor: 'Ana', lead_id: LEAD_ID })],
  ['detalle vacío', ''],
  ['sin detalle (null)', null],
  ['detalle que no es JSON', 'Key (telefono)=(+51911222333) ya es de Ana'],
]

/** Errores que no son P0481 (aunque traigan un veredicto en el detalle): se traducen igual que hoy (`aErrorApi`). */
const OTROS_ERRORES: Array<[string, { code: string; message: string; details: string | null }, number, { code: string; message: string }]> = [
  ['P0002 (ajeno o fuera de la cola)', { code: 'P0002', message: 'Lead no encontrado o fuera de tu ambito', details: null }, 400,
    { code: 'FUERA_DE_COLA', message: 'Lead no encontrado o fuera de tu ambito' }],
  ['P0409 (la persona ya tiene su lead), aun con un veredicto en el detalle', {
    code: 'P0409', message: 'La persona ya es cliente o ya tiene su lead: no se puede reabrir',
    details: JSON.stringify({ estado: 'ya_es_cliente', asesor: 'Ana' }),
  }, 400, { code: 'CONFLICTO', message: 'La persona ya es cliente o ya tiene su lead: no se puede reabrir' }],
  ['P0429 («No insistir»)', { code: 'P0429', message: 'La persona tiene la restricción «No insistir»', details: null }, 400,
    { code: 'NO_INSISTA', message: 'La persona tiene la restricción «No insistir»' }],
  ['22023 (regla de la puerta)', { code: '22023', message: 'Solo se puede deshacer un descarte de las últimas 24 horas', details: null }, 400,
    { code: 'REGLA_SERVIDOR', message: 'Solo se puede deshacer un descarte de las últimas 24 horas' }],
  ['42501 (rol sin permiso)', { code: '42501', message: 'Acceso CRM revocado', details: null }, 403,
    { code: 'SIN_PERMISO', message: 'No tienes permiso para esa acción' }],
  ['PGRST202 (función no publicada)', { code: 'PGRST202', message: 'Could not find the function', details: null }, 404,
    { code: 'POSTGREST_ERROR', message: 'No se pudo guardar el cambio.' }],
]

describe.each(PUERTAS)('$puerta (crm.$rpc) — el P0481 con veredicto (bloque 2.16)', ({ rpc, contexto, llamar }) => {
  it.each(PRESENTADOS)('%s → el mensaje del alta, CONTACTO_NO_DISPONIBLE, registrado en su contexto', async (_caso, veredicto, mensaje) => {
    server.use(http.post(RPC(rpc), () => p0481(JSON.stringify(veredicto))))
    const e = await fallo(llamar())
    expect(e.message).toBe(mensaje)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    // El registro es el de hoy: el contexto de la puerta y solo el código de Postgres (el veredicto no viaja al registro).
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith(contexto, e, { pg: 'P0481' })
  })

  it.each(TEXTO_FIJO_DE_HOY)('%s → el texto fijo de hoy', async (_caso, details) => {
    server.use(http.post(RPC(rpc), () => p0481(details)))
    const e = await fallo(llamar())
    expect(e.message).toBe(TEXTO_FIJO)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith(contexto, e, { pg: 'P0481' })
  })

  it.each(OTROS_ERRORES)('un error que no es P0481 sigue igual: %s', async (_caso, cuerpo, status, esperado) => {
    server.use(http.post(RPC(rpc), () => HttpResponse.json({ ...cuerpo, hint: null }, { status })))
    const e = await fallo(llamar())
    expect({ code: e.code, message: e.message }).toEqual(esperado)
    expect(registrarError).toHaveBeenCalledTimes(1)
    expect(registrarError).toHaveBeenCalledWith(contexto, e, { pg: cuerpo.code })
  })
})
