// @vitest-environment node
// Bloque 2.10 (D-38, D-29, D-94) — convertir a un cliente antiguo sin ficha de persona: si el antiguo sigue ACTIVO de otro asesor,
// `crm.preparar_persona_lead_inversion_fn` no escribe nada y responde `P0481` «Contacto no disponible» con el veredicto del alta en
// el DETAIL (`{"estado":"ya_es_cliente","asesor":…}`; `{"estado":"no_contactar"}` con el «No insistir» de D-94). La pantalla de
// conversión lo presenta COMO EN EL ALTA y la edición (D-36): «Esta persona ya es cliente y está a cargo de X.» (o «… de Avance
// Corp.» sin asesor). `no_contactar`, un detalle ilegible y los demás errores (P0409 de conciliación, 42501, PT409) siguen como hoy
// (`respuestaInversionistas`: el mensaje y el código del servidor). Contra un Supabase SIMULADO con msw (contrato HTTP real).
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError, mensajeDeError } from './crm-api'
import { prepararPersonaLeadInversion } from './inversion-solicitud-api'

const LEAD_ID = '3f0c2a5e-8b1d-4c6a-9e2f-7a1b2c3d4e5f'
const PERSONA_ID = '5c073c2a-f22a-4979-8ea4-8921f746ef22'
const RPC = 'http://supabase.test/rest/v1/rpc/preparar_persona_lead_inversion_fn'

const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const p0481 = (details: string | null) =>
  HttpResponse.json({ code: 'P0481', message: 'Contacto no disponible', details, hint: null }, { status: 400 })
const preparar = () => prepararPersonaLeadInversion(LEAD_ID, 'DNI', '45678901', 'CLIENTE ANTIGUO PRUEBA')

async function fallo(p: Promise<unknown>): Promise<CrmApiError> {
  try {
    await p
  } catch (e) {
    if (e instanceof CrmApiError) return e
    throw e
  }
  throw new Error('no falló')
}

describe('prepararPersonaLeadInversion (crm.preparar_persona_lead_inversion_fn) — el P0481 con veredicto (bloque 2.10)', () => {
  it('manda los cuatro argumentos y devuelve la persona preparada (sin cambio)', async () => {
    let cuerpo: unknown = null
    server.use(http.post(RPC, async ({ request }) => {
      cuerpo = await request.json()
      return HttpResponse.json({ inversionista_id: PERSONA_ID, lead_id: LEAD_ID, solicitud_id: null })
    }))
    await expect(preparar()).resolves.toEqual({ inversionista_id: PERSONA_ID, lead_id: LEAD_ID, solicitud_id: null })
    expect(cuerpo).toEqual({ p_lead: LEAD_ID, p_tipo_documento: 'DNI', p_documento: '45678901', p_nombre: 'CLIENTE ANTIGUO PRUEBA' })
  })

  it.each([
    ['ya_es_cliente con su asesor', { estado: 'ya_es_cliente', asesor: 'Ana' }, 'Esta persona ya es cliente y está a cargo de Ana.'],
    ['ya_es_cliente por identidad (via)', { estado: 'ya_es_cliente', asesor: 'Ana', via: 'identidad' },
      'Esta persona ya es cliente y está a cargo de Ana.'],
    ['ya_es_cliente «sin asesor asignado»', { estado: 'ya_es_cliente', asesor: 'sin asesor asignado' },
      'Esta persona ya es cliente de Avance Corp.'],
  ])('%s → el mensaje del alta (y es lo que enseña la pantalla de conversión)', async (_caso, veredicto, mensaje) => {
    server.use(http.post(RPC, () => p0481(JSON.stringify(veredicto))))
    const e = await fallo(preparar())
    expect(e.message).toBe(mensaje)
    expect(e.code).toBe('CONTACTO_NO_DISPONIBLE')
    // `inversion-desde-lead.tsx` enseña `mensajeDeError(e, 'No se pudo verificar la identidad.')`.
    expect(mensajeDeError(e, 'No se pudo verificar la identidad.')).toBe(mensaje)
  })

  it.each([
    ['no_contactar (D-94)', JSON.stringify({ estado: 'no_contactar' })],
    ['estado desconocido', JSON.stringify({ estado: 'ya_es_socio', asesor: 'Ana' })],
    ['ya_es_cliente sin asesor (fuera de contrato)', JSON.stringify({ estado: 'ya_es_cliente' })],
    ['ya_es_cliente con una clave de más', JSON.stringify({ estado: 'ya_es_cliente', asesor: 'Ana', lead_id: LEAD_ID })],
    ['detalle vacío', ''],
    ['sin detalle (null)', null],
    ['detalle que no es JSON', 'Key (dni)=(45678901) ya es de Ana'],
  ])('%s → el texto fijo de hoy: el mensaje y el código del servidor', async (_caso, details) => {
    server.use(http.post(RPC, () => p0481(details)))
    const e = await fallo(preparar())
    expect({ code: e.code, message: e.message }).toEqual({ code: 'P0481', message: 'Contacto no disponible' })
  })

  it.each([
    ['P0409 (requiere conciliación), aun con un veredicto en el detalle', 'P0409', 'La persona requiere conciliación antes de convertir', 400,
      { code: 'P0409', message: 'La persona requiere conciliación antes de convertir' }],
    ['42501 (sin acceso)', '42501', 'permission denied', 403, { code: '42501', message: 'Ya no tienes acceso a esta información.' }],
    ['PT409 (la identidad cambió)', 'PT409', 'La identidad cambió. Vuelve a abrir el lead.', 409,
      { code: 'PT409', message: 'La identidad cambió. Vuelve a abrir el lead.' }],
  ])('un error que no es P0481 sigue igual: %s', async (_caso, code, message, status, esperado) => {
    server.use(http.post(RPC, () => HttpResponse.json(
      { code, message, details: JSON.stringify({ estado: 'ya_es_cliente', asesor: 'Ana' }), hint: null }, { status })))
    const e = await fallo(preparar())
    expect({ code: e.code, message: e.message }).toEqual(esperado)
  })
})
