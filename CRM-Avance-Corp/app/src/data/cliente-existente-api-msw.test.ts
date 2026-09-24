// @vitest-environment node
// Venta cruzada: el cliente Supabase real contra HTTP simulado. Cada puerta recibe
// exactamente sus argumentos (una sola llave) y la respuesta se valida antes de usarse.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse, type JsonBodyType } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import { CrmApiError } from './crm-api'
import {
  buscarClienteExistente, contratosUpgradeClienteExistente, cuentasClienteExistente, datosLegalesClienteExistente,
  obtenerContextoClienteExistente,
} from './cliente-existente-api'
import { prepararSolicitudInversion } from './inversion-solicitud-api'
import { nuevoIntentoInversion } from '@/lib/inversion-solicitud'

const BASE = 'http://supabase.test/rest/v1/rpc/'
const BUSQUEDA = '11111111-1111-4111-8111-111111111111'
const SOLICITUD = '22222222-2222-4222-8222-222222222222'
const PERSONA = '33333333-3333-4333-8333-333333333333'
const PERFIL = '44444444-4444-4444-8444-444444444444'
const ACTOR = '55555555-5555-4555-8555-555555555555'
const CUENTA = '66666666-6666-4666-8666-666666666666'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

function rpc(nombre: string, responder: (cuerpo: unknown) => JsonBodyType | Response, recibidos: unknown[] = []) {
  server.use(http.post(`${BASE}${nombre}`, async ({ request }) => {
    expect(request.headers.get('content-profile')).toBe('crm')
    const cuerpo = await request.json()
    recibidos.push(cuerpo)
    const r = responder(cuerpo)
    return r instanceof Response ? r : HttpResponse.json(r)
  }))
  return recibidos
}
const encontrado = {
  estado: 'encontrado', busqueda_id: BUSQUEDA, criterio: 'documento',
  cliente: { inversionista_id: PERSONA, nombre: 'VC CLIENTE X', documento_tipo: 'DNI', documento_enmascarado: '•••••021',
    responsable_nombre: 'VC ANALISTA A', empresas: ['avance'], es_mi_cartera: false },
  acciones: { ver_ficha: false, nueva_inversion: true, requiere_documento: false, motivo_codigo: null, motivo_no_operable: null },
}

describe('búsqueda exacta', () => {
  it('manda un solo criterio por búsqueda', async () => {
    const recibidos = rpc('buscar_cliente_existente_fn', () => encontrado)
    await buscarClienteExistente({ tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' })
    await buscarClienteExistente({ tipo: 'telefono', telefono: '987000021' })
    await buscarClienteExistente({ tipo: 'lead', leadId: SOLICITUD })
    expect(recibidos).toEqual([
      { p_tipo_documento: 'DNI', p_documento: '70000021' }, { p_telefono: '987000021' }, { p_lead: SOLICITUD },
    ])
  })
  it('acepta el veredicto sin cliente y el «no operable» reservado sin nombre', async () => {
    rpc('buscar_cliente_existente_fn', () => ({ estado: 'no_encontrado', busqueda_id: BUSQUEDA, criterio: 'telefono' }))
    await expect(buscarClienteExistente({ tipo: 'telefono', telefono: '987000099' })).resolves.toMatchObject({ estado: 'no_encontrado' })
    server.resetHandlers()
    rpc('buscar_cliente_existente_fn', () => ({ estado: 'no_operable', busqueda_id: BUSQUEDA, criterio: 'documento',
      cliente: { es_mi_cartera: false },
      acciones: { ver_ficha: false, nueva_inversion: false, requiere_documento: false, motivo_codigo: 'no_admite',
        motivo_no_operable: 'La persona no admite nuevas inversiones por ahora.' } }))
    const r = await buscarClienteExistente({ tipo: 'documento', tipoDocumento: 'DNI', numero: '70000025' })
    expect(r.estado === 'no_operable' && !('nombre' in r.cliente)).toBe(true)
  })
  it('una respuesta que no cumple el contrato no se usa', async () => {
    rpc('buscar_cliente_existente_fn', () => ({ ...encontrado, estado: 'otro' }))
    await expect(buscarClienteExistente({ tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' }))
      .rejects.toMatchObject({ code: 'RESPUESTA_INCOMPLETA' })
  })
  it('42501 se informa como pérdida de acceso', async () => {
    rpc('buscar_cliente_existente_fn', () => HttpResponse.json({ code: '42501', message: 'Lead no encontrado o fuera de tu ámbito' }, { status: 403 }))
    const e = await buscarClienteExistente({ tipo: 'lead', leadId: SOLICITUD }).catch((x) => x)
    expect(e).toBeInstanceOf(CrmApiError)
    expect(e).toMatchObject({ code: '42501' })
  })
})

describe('lecturas con UNA llave', () => {
  const contexto = {
    solicitud_id: null, documento_tipo: 'DNI',
    persona: { inversionista_id: PERSONA, perfil_id: PERFIL, tiene_acceso_avance: true, nombre: 'VC CLIENTE X', correo: null,
      telefono: null, responsable_id: ACTOR, responsable_nombre: 'VC ANALISTA A' },
    capacidades: { nueva_inversion: true, motivo_codigo: null, motivo_no_operable: null },
  }
  it('el contexto viaja con la búsqueda o con la solicitud, nunca con las dos', async () => {
    const recibidos = rpc('contexto_cliente_existente_fn', () => contexto)
    await obtenerContextoClienteExistente({ busquedaId: BUSQUEDA }, new AbortController().signal)
    await obtenerContextoClienteExistente({ solicitudId: SOLICITUD }, new AbortController().signal)
    expect(recibidos).toEqual([{ p_busqueda: BUSQUEDA }, { p_solicitud: SOLICITUD }])
  })
  it('las cuentas llegan enmascaradas y se eligen como cuenta registrada', async () => {
    const recibidos = rpc('cuentas_cliente_existente_fn', () => [{ cuenta_id: CUENTA, moneda: 'PEN', banco: 'BANCO SINTETICO',
      tipo_cuenta: 'ahorros', numero_enmascarado: '••••4321', cci_enmascarado: '••••8765', titular_distinto: false,
      creada_en: '2026-09-24T10:00:00+00:00' }])
    const cuentas = await cuentasClienteExistente({ busquedaId: BUSQUEDA }, 'PEN')
    expect(recibidos).toEqual([{ p_busqueda: BUSQUEDA, p_moneda: 'PEN' }])
    expect(cuentas).toEqual([{ cuenta_id: CUENTA, moneda: 'PEN', banco: 'BANCO SINTETICO', tipo_cuenta: 'ahorros',
      numero_cuenta: '••••4321', cci: '••••8765', titular_distinto: false, beneficiario_nombre: null, beneficiario_dni: null,
      origen: 'contrato', es_cuenta_perfil: false, creada_en: '2026-09-24T10:00:00+00:00' }])
  })
  it('los datos legales tienen la misma forma que los de siempre', async () => {
    rpc('datos_legales_cliente_existente_fn', () => ({ version: 1, cliente_id: PERFIL, falta_domicilio: false,
      faltan_cliente: [], faltan_analista: ['telefono'] }))
    await expect(datosLegalesClienteExistente({ solicitudId: SOLICITUD })).resolves.toEqual({
      clienteId: PERFIL, faltaDomicilio: false, faltanCliente: [], faltanAnalista: ['telefono'] })
  })
  it('los contratos para el upgrade', async () => {
    const recibidos = rpc('contratos_upgrade_cliente_existente_fn', () => [{ contrato_id: CUENTA, numero_contrato: '2026-01-000123',
      capital: 1500, moneda: 'PEN', tasa_anual: 15, fecha_vencimiento: '2027-09-01' }])
    await expect(contratosUpgradeClienteExistente({ busquedaId: BUSQUEDA })).resolves.toHaveLength(1)
    expect(recibidos).toEqual([{ p_busqueda: BUSQUEDA }])
  })
})

describe('preparar la venta cruzada', () => {
  it('va por su puerta con la búsqueda y el motivo, y luego consulta la solicitud', async () => {
    const datos = { inversionista_id: PERSONA, empresa: 'qorilazo' as const, monto: 3000, moneda: 'PEN' as const }
    const solicitud = { solicitud_id: SOLICITUD, estado: 'preparada', inversion_id: null, inversionista_id: PERSONA,
      inversionista_origen_id: PERSONA, identidad_fusionada: false, responsable_esperado_id: ACTOR, responsable_actual_id: ACTOR,
      requiere_revision_responsable: false, revision_datos: 0, revision_responsable: 0, hash_datos: 'h', necesita_portal: false,
      comprobante_bucket: 'f4-comprobantes', comprobante_ruta: null, resultado: null, puerta: 'cliente_existente', analista_cierre_id: ACTOR }
    const preparar = rpc('preparar_inversion_cliente_existente_fn', () => solicitud)
    rpc('solicitud_inversion_fn', () => solicitud)
    const intento = nuevoIntentoInversion(ACTOR, PERSONA, SOLICITUD, datos, undefined,
      { busqueda_id: BUSQUEDA, motivo: 'El cliente pidió invertir conmigo' })
    const s = await prepararSolicitudInversion(intento)
    expect(preparar).toEqual([{ p_clave: SOLICITUD, p_datos: datos, p_busqueda: BUSQUEDA, p_motivo: 'El cliente pidió invertir conmigo' }])
    expect(s).toMatchObject({ puerta: 'cliente_existente', analista_cierre_id: ACTOR })
  })
})
