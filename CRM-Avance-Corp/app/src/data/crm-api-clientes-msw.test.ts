// @vitest-environment node
// Clientes del portal + contratos contra un Supabase SIMULADO con msw (mismo
// patrón que crm-api-msw.test.ts): se verifica el contrato HTTP real — schema
// crm por header, la TRAMPA del PATCH con 0 filas, el shape del embed y el
// cuerpos exactos de las RPC bancarias/contractuales — sin tocar la red.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  actualizarClientePortal,
  actualizarContrato,
  crearContrato,
  crearClientePortal,
  CrmApiError,
  listarClientes,
  listarCuentasBancariasCliente,
  listarMisContratos,
  obtenerClienteDetalle,
  obtenerCronograma,
  obtenerTitulares,
} from './crm-api'

const BASE = 'http://supabase.test'

/** Fila completa de la vista crm.clientes_basicos. */
function filaBasica(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'cli-1',
    nombres: 'MARIA JOSE',
    apellidos: 'QA PRUEBA',
    nombre_completo: 'QA PRUEBA MARIA JOSE',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'qa@correo.pe',
    telefono: '+51999888777',
    asesor_perfil_id: 'analista-1',
    creado_por: 'analista-1',
    activo: true,
    creado_en: '2026-07-15T12:00:00.000Z',
    ...sobre,
  }
}

/** Fila completa de public.perfiles con las 14 bancarias. */
function filaDetalle(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'cli-1',
    nombre_completo: 'QA PRUEBA MARIA JOSE',
    nombres: 'MARIA JOSE',
    apellidos: 'QA PRUEBA',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'qa@correo.pe',
    telefono: '+51999888777',
    asesor_perfil_id: 'analista-1',
    creado_por: 'analista-1',
    creado_en: '2026-07-15T12:00:00.000Z',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '2003001234567',
    cci_usd: '00320030012345678901',
    titular_distinto_usd: true,
    beneficiario_nombre_usd: 'JUANA PEREZ',
    beneficiario_dni_usd: '87654321',
    ...sobre,
  }
}

/** Fila de la vista crm.contratos_cartera (cliente_nombre plano, ámbito server-side). */
function filaContrato(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'ct-1',
    numero_contrato: '2026-01-000123',
    cliente_id: 'cli-1',
    capital: 10000,
    moneda: 'PEN',
    tasa_anual: 15,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2026-07-01',
    fecha_vencimiento: '2027-07-01',
    notas_internas: null,
    creado_por: 'analista-1',
    creado_en: '2026-07-15T12:00:00.000Z',
    cliente_nombre: 'QA PRUEBA MARIA JOSE',
    asesor_perfil_id: 'analista-1',
    ...sobre,
  }
}

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  // registrarError escribe en console.error; se silencia para no ensuciar la
  // salida (restoreMocks:true lo repone tras cada test).
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

describe('listarClientes (vista crm.clientes_basicos)', () => {
  it('viaja al esquema crm (Accept-Profile) y descarta la fila fuera de contrato', async () => {
    let perfil: string | null = null
    let select: string | null = null
    server.use(
      http.get(`${BASE}/rest/v1/clientes_basicos`, ({ request }) => {
        perfil = request.headers.get('accept-profile')
        select = new URL(request.url).searchParams.get('select')
        return HttpResponse.json([
          filaBasica({ id: 'cli-1' }),
          filaBasica({ id: 'cli-zombie', activo: 'yes' }), // boolean corrupto
          filaBasica({ id: 'cli-2', nombre_completo: null }),
        ])
      }),
    )

    const clientes = await listarClientes()

    expect(perfil).toBe('crm')
    // Las columnas de la regla de cartera y la sigla del documento SÍ se piden.
    expect(select).toContain('tipo_documento')
    expect(select).toContain('creado_por')
    expect(clientes.map((c) => c.id)).toEqual(['cli-1', 'cli-2'])
    // nombre_completo nulo degrada a '' (la UI nunca pinta "null").
    expect(clientes[1]?.nombre_completo).toBe('')
  })

  it('un tipo_documento NUEVO no tira la fila: degrada tolerante a DNI', async () => {
    server.use(
      http.get(`${BASE}/rest/v1/clientes_basicos`, () =>
        HttpResponse.json([
          filaBasica({ id: 'cli-ce', tipo_documento: 'CE' }),
          // Si el portal estrena un tipo (o llega null), la LISTA no pierde al
          // cliente — cae al default histórico DNI (el detalle sí es estricto).
          filaBasica({ id: 'cli-nuevo-tipo', tipo_documento: 'RUC' }),
          filaBasica({ id: 'cli-sin-tipo', tipo_documento: null, creado_por: null }),
        ]),
      ),
    )

    const clientes = await listarClientes()

    expect(clientes.map((c) => [c.id, c.tipo_documento])).toEqual([
      ['cli-ce', 'CE'],
      ['cli-nuevo-tipo', 'DNI'],
      ['cli-sin-tipo', 'DNI'],
    ])
    // creado_por sí viaja (regla de cartera por fila en la UI).
    expect(clientes[0]?.creado_por).toBe('analista-1')
    expect(clientes[2]?.creado_por).toBeNull()
  })
})

describe('obtenerClienteDetalle (public.perfiles)', () => {
  it('trae las 14 bancarias + tipo_documento + creado_en/por', async () => {
    server.use(
      http.get(`${BASE}/rest/v1/perfiles`, ({ request }) => {
        const url = new URL(request.url)
        expect(url.searchParams.get('id')).toBe('eq.cli-1')
        return HttpResponse.json([filaDetalle()])
      }),
    )

    const detalle = await obtenerClienteDetalle('cli-1')

    expect(detalle).toMatchObject({
      id: 'cli-1',
      tipo_documento: 'DNI',
      creado_en: '2026-07-15T12:00:00.000Z',
      creado_por: 'analista-1',
      banco: 'BCP',
      cci: '00219112345678901234',
      titular_distinto: false,
      banco_usd: 'Interbank',
      titular_distinto_usd: true,
      beneficiario_nombre_usd: 'JUANA PEREZ',
    })
  })

  it('0 filas (fuera de cartera o inexistente) → NO_ENCONTRADO sin revelar existencia', async () => {
    server.use(http.get(`${BASE}/rest/v1/perfiles`, () => HttpResponse.json([])))

    const promesa = obtenerClienteDetalle('ajeno')

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({ code: 'NO_ENCONTRADO' })
  })
})

describe('actualizarClientePortal (la TRAMPA de la ventana de 5 h)', () => {
  it('Gerencia usa la RPC acotada y no el UPDATE crudo de perfiles', async () => {
    let body: Record<string, unknown> = {}
    let patchCrudo = 0
    server.use(
      http.patch(`${BASE}/rest/v1/perfiles`, () => {
        patchCrudo += 1
        return HttpResponse.json([{ id: 'cli-1' }])
      }),
      http.post(`${BASE}/rest/v1/rpc/actualizar_cliente_gerencia`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json(true)
      }),
    )

    await expect(
      actualizarClientePortal('cli-1', { telefono: '+51911111111' }, true),
    ).resolves.toBe(true)
    expect(body).toEqual({
      p_cliente_id: 'cli-1',
      p_patch: { telefono: '+51911111111' },
    })
    expect(patchCrudo).toBe(0)
  })

  it('ventana vencida: el PATCH responde 200 con [] y la función devuelve false', async () => {
    server.use(
      http.patch(`${BASE}/rest/v1/perfiles`, () =>
        HttpResponse.json([], { status: 200 }), // 0 filas, SIN error: así calla el servidor
      ),
    )

    await expect(actualizarClientePortal('cli-1', { telefono: '+51911111111' })).resolves.toBe(false)
  })

  it('ventana viva: devuelve true y el patch viaja con select(id)', async () => {
    const capturadas: URL[] = []
    server.use(
      http.patch(`${BASE}/rest/v1/perfiles`, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json([{ id: 'cli-1' }])
      }),
    )

    await expect(actualizarClientePortal('cli-1', { banco: 'BCP' })).resolves.toBe(true)
    expect(capturadas[0]?.searchParams.get('id')).toBe('eq.cli-1')
    expect(capturadas[0]?.searchParams.get('select')).toBe('id')
  })

  it('un 23505 de perfiles_dni_cliente_key se traduce a mensaje es-PE', async () => {
    server.use(
      http.patch(`${BASE}/rest/v1/perfiles`, () =>
        HttpResponse.json(
          { code: '23505', message: 'duplicate key', details: 'perfiles_dni_cliente_key' },
          { status: 409 },
        ),
      ),
    )

    await expect(actualizarClientePortal('cli-1', { dni: '99999999' })).rejects.toMatchObject({
      code: 'DUP_DNI_CLIENTE',
      message: 'Ese documento ya pertenece a otro cliente del portal',
    })
  })
})

/** Cuenta en soles mínima válida: el alta exige al menos una (PEN o USD). */
const PEN_OK = {
  banco: 'BCP',
  tipo_cuenta: 'ahorros',
  numero_cuenta: '1912345678901',
  cci: '00219100234567890112',
  titular_distinto: false,
  beneficiario_nombre: '',
  beneficiario_dni: '',
}
const USD_VACIA = {
  banco: '', tipo_cuenta: '', numero_cuenta: '', cci: '',
  titular_distinto: false, beneficiario_nombre: '', beneficiario_dni: '',
}

describe('crearClientePortal (edge crear-cliente)', () => {
  it('feliz: devuelve userId + emailEnviado y manda tipo_documento en el body', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json({ ok: true, user_id: 'u-nuevo', email: 'qa@correo.pe', email_enviado: true })
      }),
    )

    const r = await crearClientePortal({
      email: 'qa@correo.pe',
      nombre_completo: 'QA PRUEBA MARIA JOSE',
      apellidos: 'QA PRUEBA',
      nombres: 'MARIA JOSE',
      dni: '45781234',
      telefono: '+51999888777',
      tipo_documento: 'DNI',
      bancarios: { pen: PEN_OK, usd: USD_VACIA },
    })

    expect(r).toEqual({ userId: 'u-nuevo', emailEnviado: true })
    expect(body).toMatchObject({ email: 'qa@correo.pe', dni: '45781234', tipo_documento: 'DNI' })
    // Sin password el body NO lleva la clave (la edge pone la temporal = documento).
    expect('password' in body).toBe(false)
  })

  it('los bancarios viajan CRUDOS en el body: la validación que manda es la del servidor', async () => {
    // Si el front mandara el patch ya armado, la regla "al menos una cuenta"
    // volvería a depender del navegador — que es justo el agujero que se cerró.
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json({ ok: true, user_id: 'u-nuevo', email_enviado: true })
      }),
    )

    await crearClientePortal({
      email: 'qa@correo.pe',
      nombre_completo: 'QA PRUEBA',
      apellidos: 'QA',
      nombres: 'PRUEBA',
      dni: '45781234',
      tipo_documento: 'DNI',
      bancarios: { pen: PEN_OK, usd: USD_VACIA },
    })

    expect(body.bancarios).toEqual({ pen: PEN_OK, usd: USD_VACIA })
  })

  it('un rechazo bancario de la edge llega como error, no como alta a medias', async () => {
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, () =>
        HttpResponse.json(
          { error: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.' },
          { status: 400 },
        ),
      ),
    )

    await expect(
      crearClientePortal({
        email: 'qa@correo.pe', nombre_completo: 'X', apellidos: 'X', nombres: 'X',
        dni: '45781234', tipo_documento: 'DNI',
        bancarios: { pen: USD_VACIA, usd: USD_VACIA },
      }),
    ).rejects.toMatchObject({
      code: 'ALTA_CLIENTE_FALLIDA',
      message: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    })
  })

  it('rechazo de la edge (409 documento duplicado): expone el mensaje es-PE del servidor', async () => {
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, () =>
        HttpResponse.json({ error: 'Este documento ya está registrado para otro cliente.' }, { status: 409 }),
      ),
    )

    const promesa = crearClientePortal({
      email: 'qa@correo.pe',
      nombre_completo: 'X',
      apellidos: 'X',
      nombres: 'X',
      dni: '45781234',
      tipo_documento: 'DNI',
      bancarios: { pen: PEN_OK, usd: USD_VACIA },
    })

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({
      code: 'ALTA_CLIENTE_FALLIDA',
      message: 'Este documento ya está registrado para otro cliente.',
    })
  })

  it('respuesta sin user_id = fallo explícito (nunca éxito sin id para encadenar el contrato)', async () => {
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, () =>
        HttpResponse.json({ ok: true, email_enviado: true }),
      ),
    )

    await expect(
      crearClientePortal({
        email: 'qa@correo.pe', nombre_completo: 'X', apellidos: 'X', nombres: 'X',
        dni: '45781234', tipo_documento: 'DNI',
        bancarios: { pen: PEN_OK, usd: USD_VACIA },
      }),
    ).rejects.toMatchObject({ code: 'ALTA_SIN_ID' })
  })
})

describe('listarMisContratos (vista crm.contratos_cartera)', () => {
  it('lee la vista con ámbito y normaliza numeric-string a number', async () => {
    server.use(
      http.get(`${BASE}/rest/v1/contratos_cartera`, ({ request }) => {
        const select = new URL(request.url).searchParams.get('select') ?? ''
        // cliente_nombre viene PLANO de la vista (el ámbito lo resolvió el servidor).
        expect(select).toContain('cliente_nombre')
        return HttpResponse.json([
          filaContrato({ capital: '10000.50', tasa_anual: '15.5' }),
          filaContrato({ id: 'ct-2', estado: 'zombie' }), // fuera de contrato → se descarta
        ])
      }),
    )

    const contratos = await listarMisContratos()

    expect(contratos).toHaveLength(1)
    expect(contratos[0]).toMatchObject({
      id: 'ct-1',
      cliente_nombre: 'QA PRUEBA MARIA JOSE',
      capital: 10000.5,
      tasa_anual: 15.5,
      estado: 'activo',
    })
  })
})

describe('obtenerCronograma / obtenerTitulares', () => {
  it('el cronograma llega ordenado por numero_cuota y con montos numéricos', async () => {
    const capturadas: Record<string, unknown>[] = []
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cronograma_contrato_fn`, async ({ request }) => {
        capturadas.push((await request.json()) as Record<string, unknown>)
        return HttpResponse.json([
          {
            id: 'cu-1', numero_cuota: 1, fecha_programada: '2026-08-01',
            monto_programado: '125.00', estado: 'pendiente', tipo: 'cuota',
            fecha_pago_real: null, monto_pagado: null,
          },
        ])
      }),
    )

    const cuotas = await obtenerCronograma('ct-1')

    expect(capturadas[0]?.p_contrato_id).toBe('ct-1') // el orden lo garantiza la fn
    expect(cuotas[0]).toMatchObject({ numero_cuota: 1, monto_programado: 125, monto_pagado: null })
  })

  it('los co-titulares llegan ordenados por orden', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/titulares_contrato_fn`, async ({ request }) => {
        expect(((await request.json()) as Record<string, unknown>).p_contrato_id).toBe('ct-1')
        return HttpResponse.json([
          { nombre_completo: 'JUANA PEREZ', tipo_documento: 'PASAPORTE', documento: 'AB1234', orden: 1 },
        ])
      }),
    )

    const titulares = await obtenerTitulares('ct-1')

    expect(titulares).toEqual([
      { nombre_completo: 'JUANA PEREZ', tipo_documento: 'PASAPORTE', documento: 'AB1234', orden: 1 },
    ])
  })
})

describe('cuentas bancarias y alta atómica de contrato', () => {
  const cuenta = {
    cuenta_id: null,
    moneda: 'PEN',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    origen: 'perfil',
    es_cuenta_perfil: true,
    creada_en: null,
  }

  it('lista por RPC en crm y valida estrictamente cada cuenta', async () => {
    let body: Record<string, unknown> = {}
    let perfil: string | null = null
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        perfil = request.headers.get('content-profile')
        return HttpResponse.json([cuenta])
      }),
    )

    await expect(listarCuentasBancariasCliente('cli-1', 'PEN')).resolves.toEqual([cuenta])
    expect(body).toEqual({ p_cliente_id: 'cli-1', p_moneda: 'PEN' })
    expect(perfil).toBe('crm')
  })

  it('falla cerrado si una fila bancaria llega mutilada', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, () =>
        HttpResponse.json([{ ...cuenta, cci: null }]),
      ),
    )
    await expect(listarCuentasBancariasCliente('cli-1', 'PEN')).rejects.toMatchObject({
      code: 'ROW_CONTRACT',
    })
  })

  it('acepta una cuenta histórica solo con UUID y fecha coherentes', async () => {
    const historica = {
      ...cuenta,
      cuenta_id: '20000000-0000-4000-8000-000000000001',
      origen: 'contrato',
      es_cuenta_perfil: false,
      creada_en: '2026-08-03T20:02:53.000Z',
    }
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, () =>
        HttpResponse.json([historica]),
      ),
    )

    await expect(listarCuentasBancariasCliente('cli-1', 'PEN')).resolves.toEqual([historica])
  })

  it('acepta reutilizar una versión histórica nacida desde el perfil', async () => {
    const versionadaDesdePerfil = {
      ...cuenta,
      cuenta_id: '20000000-0000-4000-8000-000000000002',
      es_cuenta_perfil: false,
      creada_en: '2026-08-03T20:02:53.000Z',
    }
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, () =>
        HttpResponse.json([versionadaDesdePerfil]),
      ),
    )

    await expect(listarCuentasBancariasCliente('cli-1', 'PEN')).resolves.toEqual([
      versionadaDesdePerfil,
    ])
  })

  it.each([
    ['perfil con UUID', { cuenta_id: '20000000-0000-4000-8000-000000000001' }],
    ['perfil con fecha', { creada_en: '2026-08-03T20:02:53.000Z' }],
    ['histórica sin UUID', { origen: 'contrato', es_cuenta_perfil: false }],
    [
      'UUID inválido',
      {
        cuenta_id: 'cb-1',
        origen: 'contrato',
        es_cuenta_perfil: false,
        creada_en: '2026-08-03T20:02:53.000Z',
      },
    ],
    [
      'fecha inválida',
      {
        cuenta_id: '20000000-0000-4000-8000-000000000001',
        origen: 'contrato',
        es_cuenta_perfil: false,
        creada_en: 'ayer',
      },
    ],
    ['slot de perfil con origen contradictorio', { origen: 'contrato' }],
    ['columna inesperada', { inesperada: true }],
  ])('falla cerrado ante %s', async (_caso, parche) => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, () =>
        HttpResponse.json([{ ...cuenta, ...parche }]),
      ),
    )

    await expect(listarCuentasBancariasCliente('cli-1', 'PEN')).rejects.toMatchObject({
      code: 'ROW_CONTRACT',
    })
  })

  it('crearContrato manda la fotografía bancaria a la RPC crm y valida su respuesta', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json({
          id: '10000000-0000-4000-8000-000000000001',
          numero_contrato: '2026-01-000123',
          cuenta_bancaria_id: '20000000-0000-4000-8000-000000000001',
        })
      }),
    )

    const resultado = await crearContrato({
      cliente_id: 'cli-1',
      capital: 10000,
      moneda: 'PEN',
      tasa_anual: 15,
      modalidad: 'mensual',
      tipo_interes: 'simple',
      categoria: 'nuevo',
      fecha_inicio: '2026-08-01',
      fecha_vencimiento: '2027-08-01',
      numero_contrato: '2026-01-000123',
      notas_internas: null,
      cuenta_pago: {
        tipo: 'perfil',
        cuenta_esperada: {
          banco: cuenta.banco,
          tipo_cuenta: cuenta.tipo_cuenta as 'ahorros',
          numero_cuenta: cuenta.numero_cuenta,
          cci: cuenta.cci,
          titular_distinto: false,
          beneficiario_nombre: null,
          beneficiario_dni: null,
        },
      },
    }, [{
      numero_cuota: 1,
      fecha_programada: '2026-09-01',
      monto_programado: 125,
      estado: 'pendiente',
      tipo: 'cuota',
    }])

    expect(resultado.cuenta_bancaria_id).toBe('20000000-0000-4000-8000-000000000001')
    expect(body.p_cuenta).toMatchObject({ tipo: 'perfil', cuenta_esperada: { cci: cuenta.cci } })
  })

  it('no confirma éxito si la RPC omite el id de la cuenta', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta`, () =>
        HttpResponse.json({
          id: '10000000-0000-4000-8000-000000000001',
          numero_contrato: '2026-01-000123',
        }),
      ),
    )
    await expect(crearContrato({
      cliente_id: 'cli-1', capital: 10000, moneda: 'PEN', tasa_anual: 15,
      modalidad: 'mensual', tipo_interes: 'simple', categoria: 'nuevo',
      fecha_inicio: '2026-08-01', fecha_vencimiento: '2027-08-01',
      numero_contrato: '2026-01-000123', cuenta_pago: { tipo: 'existente', cuenta_id: 'cb-1' },
    }, [])).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })
})

describe('actualizarContrato (wrapper crm.actualizar_contrato_con_cuenta)', () => {
  const contratoBase = {
    capital: 12000,
    moneda: 'PEN' as const,
    tasa_anual: 18,
    modalidad: 'mensual' as const,
    tipo_interes: 'simple' as const,
    categoria: 'renovacion' as const,
    fecha_inicio: '2026-07-01',
    fecha_vencimiento: '2027-07-01',
    numero_contrato: '2026-01-000456',
    notas_internas: null,
  }

  it('p_contrato SIEMPRE lleva notas_internas (aunque null) y titulares solo si el caller lo mandó', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/rest/v1/rpc/actualizar_contrato_con_cuenta`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return new HttpResponse(null, { status: 204 }) // RPC void
      }),
    )

    await actualizarContrato('ct-1', contratoBase, [])

    expect(body.p_id).toBe('ct-1')
    const pContrato = body.p_contrato as Record<string, unknown>
    // La clave existe con valor null — si faltara, el servidor BORRA las notas.
    expect('notas_internas' in pContrato).toBe(true)
    expect(pContrato.notas_internas).toBeNull()
    // Sin decisión del caller, titulares NO viaja (ausente = no tocar).
    expect('titulares' in pContrato).toBe(false)
  })

  it('titulares presente (incluso []) SÍ viaja — semántica de reemplazo total', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/rest/v1/rpc/actualizar_contrato_con_cuenta`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return new HttpResponse(null, { status: 204 })
      }),
    )

    await actualizarContrato('ct-1', { ...contratoBase, titulares: [] }, [])

    expect((body.p_contrato as Record<string, unknown>).titulares).toEqual([])
  })

  it('ventana vencida: el RAISE P0001 del servidor llega con su mensaje es-PE', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/actualizar_contrato_con_cuenta`, () =>
        HttpResponse.json(
          { code: 'P0001', message: 'Solo puedes corregir un contrato dentro de las 5 horas de creado', details: null },
          { status: 400 },
        ),
      ),
    )

    await expect(actualizarContrato('ct-1', contratoBase, [])).rejects.toMatchObject({
      code: 'REGLA_SERVIDOR',
      message: 'Solo puedes corregir un contrato dentro de las 5 horas de creado',
    })
  })
})
