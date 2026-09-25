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
  listarOperacionesCartera,
  obtenerResumenCarteraClientes,
  obtenerClienteDetalle,
  obtenerClienteFichaComercial,
  obtenerCronograma,
  obtenerTitulares,
} from './crm-api'

const BASE = 'http://supabase.test'

function lista(filas: unknown[], total = filas.length, desde = 0) {
  return HttpResponse.json(filas, { headers: {
    'content-range': filas.length ? `${desde}-${desde + filas.length - 1}/${total}` : `*/${total}`,
  } })
}

const META_PRODUCTO = {
  producto_condicion_id: '30000000-0000-4000-8000-000000000001',
  producto_id: '40000000-0000-4000-8000-000000000001',
  producto_revision: 2,
  version_id: '50000000-0000-4000-8000-000000000001',
  version_revision: 3,
  numero_version: 2,
  version_estado: 'publicada',
  version_nombre: 'Plan Base 2026',
} as const

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

/** Fila del contrato de crm.cliente_detalle_fn con las 14 columnas bancarias. */
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
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    asesor_perfil_id: 'analista-1',
    creado_por: 'analista-1',
    creado_en: '2026-07-15T12:00:00.000Z',
    banca_visible: true,
    cuentas_bancarias_visibles: true,
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

/** Proyección mínima de crm.cliente_ficha_fn: identidad y contacto, sin PII bancaria. */
function filaFichaComercial(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  const basica = filaBasica()
  return {
    id: basica.id,
    nombres: basica.nombres,
    apellidos: basica.apellidos,
    nombre_completo: basica.nombre_completo,
    tipo_documento: basica.tipo_documento,
    dni: basica.dni,
    correo: basica.correo,
    telefono: basica.telefono,
    asesor_perfil_id: basica.asesor_perfil_id,
    activo: basica.activo,
    creado_en: basica.creado_en,
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
    fecha_cierre_comercial: '2026-07-01',
    notas_internas: null,
    creado_por: 'analista-1',
    creado_en: '2026-07-15T12:00:00.000Z',
    cliente_nombre: 'QA PRUEBA MARIA JOSE',
    asesor_perfil_id: 'analista-1',
    producto_condicion_id: META_PRODUCTO.producto_condicion_id,
    producto_id: META_PRODUCTO.producto_id,
    producto_codigo: 'RENTA-BASE',
    producto_version_id: META_PRODUCTO.version_id,
    producto_version: META_PRODUCTO.numero_version,
    producto_nombre: META_PRODUCTO.version_nombre,
    producto_version_estado: META_PRODUCTO.version_estado,
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
  it('viaja al esquema crm (Accept-Profile) y exige total exacto', async () => {
    let perfil: string | null = null
    let select: string | null = null
    server.use(
      http.get(`${BASE}/rest/v1/clientes_basicos`, ({ request }) => {
        perfil = request.headers.get('accept-profile')
        select = new URL(request.url).searchParams.get('select')
        expect(request.headers.get('prefer')).toContain('count=exact')
        return lista([
          filaBasica({ id: 'cli-1' }),
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
        lista([
          filaBasica({ id: 'cli-ce', tipo_documento: 'CE' }),
          // Si el portal estrena un tipo (o llega null), la LISTA no pierde al
          // cliente — cae al default histórico DNI (el detalle sí es estricto).
          filaBasica({ id: 'cli-nuevo-tipo', tipo_documento: 'RUC' }),
          filaBasica({
            id: 'cli-sin-tipo',
            tipo_documento: null,
            creado_por: null,
          }),
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

describe('obtenerClienteDetalle (crm.cliente_detalle_fn)', () => {
  it('usa la RPC scopeada y trae las 14 bancarias cuando el servidor las habilita', async () => {
    let lecturasCrudas = 0
    server.use(
      http.get(`${BASE}/rest/v1/perfiles`, () => {
        lecturasCrudas += 1
        return HttpResponse.json([])
      }),
      http.post(`${BASE}/rest/v1/rpc/cliente_detalle_fn`, async ({ request }) => {
        expect(await request.json()).toEqual({ p_cliente_id: 'cli-1' })
        return HttpResponse.json([filaDetalle()])
      }),
    )

    const detalle = await obtenerClienteDetalle('cli-1')

    expect(detalle).toMatchObject({
      id: 'cli-1',
      tipo_documento: 'DNI',
      creado_en: '2026-07-15T12:00:00.000Z',
      creado_por: 'analista-1',
      banca_visible: true,
      cuentas_bancarias_visibles: true,
      domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
      banco: 'BCP',
      cci: '00219112345678901234',
      titular_distinto: false,
      banco_usd: 'Interbank',
      titular_distinto_usd: true,
      beneficiario_nombre_usd: 'JUANA PEREZ',
    })
    expect(lecturasCrudas).toBe(0)
  })

  it('acepta la proyección redactada de Directorio sin inventar datos bancarios', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cliente_detalle_fn`, () =>
        HttpResponse.json([
          filaDetalle({
            banca_visible: false,
            cuentas_bancarias_visibles: false,
            banco: null,
            tipo_cuenta: null,
            numero_cuenta: null,
            cci: null,
            titular_distinto: false,
            beneficiario_nombre: null,
            beneficiario_dni: null,
            banco_usd: null,
            tipo_cuenta_usd: null,
            numero_cuenta_usd: null,
            cci_usd: null,
            titular_distinto_usd: false,
            beneficiario_nombre_usd: null,
            beneficiario_dni_usd: null,
          }),
        ]),
      ),
    )

    const detalle = await obtenerClienteDetalle('cli-1')

    expect(detalle.banca_visible).toBe(false)
    expect(detalle.banco).toBeNull()
    expect(detalle.cci_usd).toBeNull()
  })

  it('0 filas (fuera de cartera o inexistente) → NO_ENCONTRADO sin revelar existencia', async () => {
    server.use(http.post(`${BASE}/rest/v1/rpc/cliente_detalle_fn`, () => HttpResponse.json([])))

    const promesa = obtenerClienteDetalle('ajeno')

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({ code: 'NO_ENCONTRADO' })
  })
})

describe('obtenerClienteFichaComercial (crm.cliente_ficha_fn)', () => {
  it('usa la RPC scopeada y acepta exclusivamente identidad y contacto', async () => {
    let lecturasCrudas = 0
    server.use(
      http.get(`${BASE}/rest/v1/perfiles`, () => {
        lecturasCrudas += 1
        return HttpResponse.json([])
      }),
      http.post(`${BASE}/rest/v1/rpc/cliente_ficha_fn`, async ({ request }) => {
        expect(await request.json()).toEqual({ p_cliente_id: 'cli-1' })
        return HttpResponse.json([filaFichaComercial()])
      }),
    )

    const ficha = await obtenerClienteFichaComercial('cli-1')

    expect(ficha).toEqual(filaFichaComercial())
    expect(ficha).not.toHaveProperty('domicilio')
    expect(ficha).not.toHaveProperty('banco')
    expect(ficha).not.toHaveProperty('creado_por')
    expect(lecturasCrudas).toBe(0)
  })

  it('rechaza una respuesta que amplíe accidentalmente la frontera mínima', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/cliente_ficha_fn`, () =>
        HttpResponse.json([filaFichaComercial({ domicilio: 'NO DEBE VIAJAR' })]),
      ),
    )

    await expect(obtenerClienteFichaComercial('cli-1')).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('0 filas se traduce a NO_ENCONTRADO sin distinguir ajeno de inexistente', async () => {
    server.use(http.post(`${BASE}/rest/v1/rpc/cliente_ficha_fn`, () => HttpResponse.json([])))

    await expect(obtenerClienteFichaComercial('ajeno')).rejects.toMatchObject({ code: 'NO_ENCONTRADO' })
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
      http.post(`${BASE}/rest/v1/rpc/actualizar_cliente_gerencia_con_domicilio`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json(true)
      }),
    )

    await expect(
      actualizarClientePortal(
        'cli-1',
        {
          telefono: '+51911111111',
          domicilio: 'Av. Los Inversionistas 245, San Isidro, Lima',
        },
        true,
      ),
    ).resolves.toBe(true)
    expect(body).toEqual({
      p_cliente_id: 'cli-1',
      p_patch: {
        telefono: '+51911111111',
        domicilio: 'Av. Los Inversionistas 245, San Isidro, Lima',
      },
    })
    expect(patchCrudo).toBe(0)
  })

  it('ventana vencida: el PATCH responde 200 con [] y la función devuelve false', async () => {
    server.use(
      http.patch(
        `${BASE}/rest/v1/perfiles`,
        () => HttpResponse.json([], { status: 200 }), // 0 filas, SIN error: así calla el servidor
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

    await expect(actualizarClientePortal('cli-1', { telefono: '+51911111111' })).resolves.toBe(true)
    expect(capturadas[0]?.searchParams.get('id')).toBe('eq.cli-1')
    expect(capturadas[0]?.searchParams.get('select')).toBe('id')
  })

  it('un 23505 de perfiles_dni_cliente_key se traduce a mensaje es-PE', async () => {
    server.use(
      http.patch(`${BASE}/rest/v1/perfiles`, () =>
        HttpResponse.json(
          {
            code: '23505',
            message: 'duplicate key',
            details: 'perfiles_dni_cliente_key',
          },
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
  banco: '',
  tipo_cuenta: '',
  numero_cuenta: '',
  cci: '',
  titular_distinto: false,
  beneficiario_nombre: '',
  beneficiario_dni: '',
}

describe('crearClientePortal (edge crear-cliente)', () => {
  it('feliz: devuelve userId + emailEnviado y manda tipo_documento en el body', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json({
          ok: true,
          user_id: 'u-nuevo',
          email: 'qa@correo.pe',
          email_enviado: true,
        })
      }),
    )

    const r = await crearClientePortal({
      email: 'qa@correo.pe',
      nombre_completo: 'QA PRUEBA MARIA JOSE',
      apellidos: 'QA PRUEBA',
      nombres: 'MARIA JOSE',
      dni: '45781234',
      telefono: '999111222',
      domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
      tipo_documento: 'DNI',
      bancarios: { pen: PEN_OK, usd: USD_VACIA },
    })

    expect(r).toEqual({ userId: 'u-nuevo', emailEnviado: true })
    expect(body).toMatchObject({
      email: 'qa@correo.pe',
      dni: '45781234',
      domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
      tipo_documento: 'DNI',
    })
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
        return HttpResponse.json({
          ok: true,
          user_id: 'u-nuevo',
          email_enviado: true,
        })
      }),
    )

    await crearClientePortal({
      email: 'qa@correo.pe',
      nombre_completo: 'QA PRUEBA',
      apellidos: 'QA',
      nombres: 'PRUEBA',
      dni: '45781234',
      domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
      tipo_documento: 'DNI',
      bancarios: { pen: PEN_OK, usd: USD_VACIA },
    })

    expect(body.bancarios).toEqual({ pen: PEN_OK, usd: USD_VACIA })
  })

  it('un rechazo bancario de la edge llega como error, no como alta a medias', async () => {
    server.use(
      http.post(`${BASE}/functions/v1/crear-cliente`, () =>
        HttpResponse.json(
          {
            error: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
          },
          { status: 400 },
        ),
      ),
    )

    await expect(
      crearClientePortal({
        email: 'qa@correo.pe',
        nombre_completo: 'X',
        apellidos: 'X',
        nombres: 'X',
        dni: '45781234',
        domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
        tipo_documento: 'DNI',
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
      domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
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
      http.post(`${BASE}/functions/v1/crear-cliente`, () => HttpResponse.json({ ok: true, email_enviado: true })),
    )

    await expect(
      crearClientePortal({
        email: 'qa@correo.pe',
        nombre_completo: 'X',
        apellidos: 'X',
        nombres: 'X',
        dni: '45781234',
        domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
        tipo_documento: 'DNI',
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
        expect(select).toContain('producto_condicion_id')
        expect(select).toContain('producto_version')
        // La pide EXPLÍCITA: es la fecha por la que Mi cartera reparte sus
        // bloques, y sin ella la fila se descarta (abajo se comprueba).
        expect(select).toContain('fecha_cierre_comercial')
        return lista([
          filaContrato({ capital: '10000.50', tasa_anual: '15.5' }),
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
      producto_codigo: 'RENTA-BASE',
      producto_version: 2,
      producto_nombre: 'Plan Base 2026',
    })
  })
})

describe('Cartera: completitud del transporte, nunca éxito parcial', () => {
  it('recorre más de 2.000 clientes aunque el servidor recorte cada página a 73', async () => {
    const filas = Array.from({ length: 2105 }, (_, i) => filaBasica({ id: `cli-${i}` }))
    const offsets: number[] = []
    server.use(http.get(`${BASE}/rest/v1/clientes_basicos`, ({ request }) => {
      const p = new URL(request.url).searchParams
      expect(p.get('order')).toBe('creado_en.desc,id.asc')
      const offset = Number(p.get('offset'))
      offsets.push(offset)
      return lista(filas.slice(offset, offset + 73), filas.length, offset)
    }))
    const recibidos = await listarClientes()
    expect(recibidos).toHaveLength(2105)
    expect(offsets.slice(0, 3)).toEqual([0, 73, 146])
    expect(new Set(recibidos.map((c) => c.id)).size).toBe(2105)
  })

  it.each([
    { activo: 'yes' }, { id: null },
  ])('rechaza todo el listado si una fila de cliente es inválida: %j', async (sobre) => {
    server.use(http.get(`${BASE}/rest/v1/clientes_basicos`, () => lista([
      filaBasica(), filaBasica({ id: 'invalido', ...sobre }),
    ])))
    await expect(listarClientes()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it.each([
    { estado: 'zombie' }, { producto_condicion_id: 'sin-uuid' },
    { fecha_cierre_comercial: undefined }, { capital: 'dinero' }, { capital: '' }, { capital: null },
  ])('no descarta silenciosamente el contrato inválido: %j', async (sobre) => {
    server.use(http.get(`${BASE}/rest/v1/contratos_cartera`, () => lista([
      filaContrato(), filaContrato({ id: 'invalido', ...sobre }),
    ])))
    await expect(listarMisContratos()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it.each(['sin-total', 'total-cambia', 'pagina-vacia', 'fila-repetida'] as const)(
    'rechaza la lectura %s y no entrega la primera página como resultado', async (caso) => {
      let peticiones = 0
      server.use(http.get(`${BASE}/rest/v1/contratos_cartera`, () => {
        peticiones += 1
        if (caso === 'sin-total') return HttpResponse.json([filaContrato()])
        if (peticiones === 1) return lista([filaContrato()], 2)
        if (caso === 'total-cambia') return lista([filaContrato({ id: 'ct-2' })], 3, 1)
        if (caso === 'pagina-vacia') return lista([], 2, 1)
        return lista([filaContrato()], 2, 1)
      }))
      await expect(listarMisContratos()).rejects.toMatchObject({
        code: caso === 'fila-repetida' ? 'ROW_CONTRACT' : 'CARTERA_INCOMPLETA',
      })
    },
  )

  it('una cartera vacía necesita confirmar total cero', async () => {
    server.use(http.get(`${BASE}/rest/v1/clientes_basicos`, () => lista([])))
    await expect(listarClientes()).resolves.toEqual([])
  })

  it('pagina también el ledger de operaciones sin alterar orden ni importes', async () => {
    const operacion = {
      id: 'op-1', cliente_id: 'cli-1', vendedor_id: 'v-1', tipo: 'renovacion',
      contrato_origen_id: 'ct-1', contrato_nuevo_id: 'ct-2', fecha_operacion: '2026-09-01',
      periodo: '2026-09-01', moneda: 'PEN', capital_renovado: '3000', capital_adicional: '1000',
      elegible_conversion: true, desglose_completo: true, fuente: 'flujo_cartera',
      creado_por: 'v-1', creado_en: '2026-09-01T12:00:00Z',
    }
    server.use(http.get(`${BASE}/rest/v1/operaciones_cartera`, ({ request }) => {
      const p = new URL(request.url).searchParams
      expect(p.get('order')).toBe('fecha_operacion.desc,creado_en.desc,id.asc')
      const offset = Number(p.get('offset'))
      return lista([{ ...operacion, id: `op-${offset}` }], 2, offset)
    }))
    const r = await listarOperacionesCartera()
    expect(r).toHaveLength(2)
    expect(r[1]).toMatchObject({ capital_renovado: 3000, capital_adicional: 1000 })
  })

  it('respeta la cancelación antes de iniciar otra descarga', async () => {
    const c = new AbortController()
    c.abort()
    await expect(listarClientes(c.signal)).rejects.toMatchObject({ name: 'AbortError' })
  })
})

describe('resumen de Cartera: salida existente sin calculadora local', () => {
  const respuesta = {
    version: 1, generado_en: '2026-09-04T22:00:00-05:00', zona: 'America/Lima', dias_alarma_renovacion: 30,
    clientes: { en_gestion: 420, de_baja: 0, con_capital: 393, sin_asesor: 4 },
    capital_activo: { pen: 19485413.12, usd: 1075193.33 },
    contratos: { por_estado: { activo: 516, vencido: 1 }, por_vencer_30: 3, por_vencer_30_de_baja: 0 },
  }
  it('devuelve los campos del servidor sin consultar las listas', async () => {
    server.use(http.post(`${BASE}/rest/v1/rpc/resumen_cartera_clientes_fn`, ({ request }) => {
      expect(request.headers.get('content-profile')).toBe('crm')
      return HttpResponse.json(respuesta)
    }))
    await expect(obtenerResumenCarteraClientes()).resolves.toEqual(respuesta)
  })
  it.each([
    null, {}, { ...respuesta, version: 2 }, { ...respuesta, capital_activo: { pen: null, usd: 0 } },
    { ...respuesta, clientes: { ...respuesta.clientes, con_capital: 421 } },
    { ...respuesta, contratos: { ...respuesta.contratos, por_vencer_30_de_baja: 4 } },
  ])('rechaza respuesta no confirmada, sin convertirla en cero: %j', async (body) => {
    server.use(http.post(`${BASE}/rest/v1/rpc/resumen_cartera_clientes_fn`, () => HttpResponse.json(body)))
    await expect(obtenerResumenCarteraClientes()).rejects.toMatchObject({ code: 'RESUMEN_CARTERA_CLIENTES_CONTRACT' })
  })
  it('conserva el fallo de permisos del servidor', async () => {
    server.use(http.post(`${BASE}/rest/v1/rpc/resumen_cartera_clientes_fn`, () =>
      HttpResponse.json({ code: '42501', message: 'No autorizado' }, { status: 403 })))
    await expect(obtenerResumenCarteraClientes()).rejects.toMatchObject({ code: 'SIN_PERMISO' })
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
            id: 'cu-1',
            numero_cuota: 1,
            fecha_programada: '2026-08-01',
            monto_programado: '125.00',
            estado: 'pendiente',
            tipo: 'cuota',
            fecha_pago_real: null,
            monto_pagado: null,
          },
        ])
      }),
    )

    const cuotas = await obtenerCronograma('ct-1')

    expect(capturadas[0]?.p_contrato_id).toBe('ct-1') // el orden lo garantiza la fn
    expect(cuotas[0]).toMatchObject({
      numero_cuota: 1,
      monto_programado: 125,
      monto_pagado: null,
    })
  })

  it('los co-titulares llegan ordenados por orden', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/titulares_contrato_fn`, async ({ request }) => {
        expect(((await request.json()) as Record<string, unknown>).p_contrato_id).toBe('ct-1')
        return HttpResponse.json([
          {
            nombre_completo: 'JUANA PEREZ',
            tipo_documento: 'PASAPORTE',
            documento: 'AB1234',
            orden: 1,
          },
        ])
      }),
    )

    const titulares = await obtenerTitulares('ct-1')

    expect(titulares).toEqual([
      {
        nombre_completo: 'JUANA PEREZ',
        tipo_documento: 'PASAPORTE',
        documento: 'AB1234',
        orden: 1,
      },
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
    server.use(http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, () => HttpResponse.json([historica])))

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
      http.post(`${BASE}/rest/v1/rpc/cuentas_bancarias_cliente_fn`, () => HttpResponse.json([versionadaDesdePerfil])),
    )

    await expect(listarCuentasBancariasCliente('cli-1', 'PEN')).resolves.toEqual([versionadaDesdePerfil])
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

  // REGRESIÓN 2026-08-19 — el incidente del 34.º release.
  //
  // El front exigía `template_version: 'contrato-aep-17-v3'` mientras producción
  // ya emitía v5. Resultado: TODA creación de contrato moría con «El servidor no
  // confirmó completamente el contrato y su cuenta de pago» aunque el contrato SÍ
  // se había creado — y el analista, creyendo que había fallado, lo creaba dos
  // veces. Pasó porque la tolerancia v3-v5 vivía SOLO en el bundle publicado, sin
  // commitear, y al reconstruir desde el commit se perdió.
  //
  // Ninguna prueba lo cazó porque el simulador de abajo devuelve v3 fijo: afirma
  // contra lo que el front PIDE, no contra lo que el servidor MANDA. Esta prueba
  // usa la respuesta REAL copiada de producción (contrato acc0eccf…, 19-ago).
  it('acepta la reserva de PDF tal como la emite producción HOY (plantilla v5)', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () =>
        HttpResponse.json({
          id: 'acc0eccf-7965-4cc4-b7d7-f28b2f5a2b20',
          numero_contrato: '2026-01-007654',
          cuenta_bancaria_id: '20000000-0000-4000-8000-000000000001',
          pdf: {
            contrato_id: 'acc0eccf-7965-4cc4-b7d7-f28b2f5a2b20',
            job_id: '189670d0-a5a6-4334-97ed-5395572811a9',
            estado: 'pendiente',
            storage_bucket: 'contratos-generados',
            storage_path: 'acc0eccf-7965-4cc4-b7d7-f28b2f5a2b20/v2/189670d0-a5a6-4334-97ed-5395572811a9/contrato.pdf',
            nombre_archivo: 'Contrato-2026-01-007654.pdf',
            template_version: 'contrato-aep-17-v5',
            intentos: 0,
            lease_expira_en: null,
            reintentable: true,
            sha256: null,
            bytes: null,
            archivo: null,
          },
        }),
      ),
    )
    const r = await crearContrato(
      {
        cliente_id: '00000000-0000-4000-8000-0000000000c1',
        capital: 10000,
        moneda: 'PEN',
        tasa_anual: 15,
        modalidad: 'mensual',
        tipo_interes: 'simple',
        categoria: 'nuevo',
        fecha_inicio: '2026-08-19',
        fecha_vencimiento: '2027-08-19',
        numero_contrato: '2026-01-007654',
        notas_internas: null,
        cuenta_pago: { tipo: 'perfil' },
      } as never,
      [{ numero_cuota: 1, fecha_programada: '2026-09-19', monto_programado: 125, tipo: 'cuota' }] as never,
    )
    // Que NO lance ya es la prueba: con la plantilla exigida a v3, el parse de
    // Valibot rechaza esta respuesta y crearContrato revienta con ROW_CONTRACT.
    expect(r.numero_contrato).toBe('2026-01-007654')
    expect(r.id).toBe('acc0eccf-7965-4cc4-b7d7-f28b2f5a2b20')
    expect(r.pdf.estado).toBe('pendiente')
  })

  it('crearContrato confirma cuenta y reserva PDF durable en la misma RPC', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json({
          id: '10000000-0000-4000-8000-000000000001',
          numero_contrato: '2026-01-000123',
          cuenta_bancaria_id: '20000000-0000-4000-8000-000000000001',
          pdf: {
            contrato_id: '10000000-0000-4000-8000-000000000001',
            job_id: '30000000-0000-4000-8000-000000000001',
            estado: 'pendiente',
            storage_bucket: 'contratos-generados',
            storage_path: '10000000-0000-4000-8000-000000000001/v2/30000000-0000-4000-8000-000000000001/contrato.pdf',
            nombre_archivo: 'Contrato-2026-01-000123.pdf',
            template_version: 'contrato-aep-17-v3',
            intentos: 0,
            lease_expira_en: null,
            reintentable: true,
            sha256: null,
            bytes: null,
            archivo: null,
          },
        })
      }),
    )

    const resultado = await crearContrato(
      {
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
      },
      [
        {
          numero_cuota: 1,
          fecha_programada: '2026-09-01',
          monto_programado: 125,
          estado: 'pendiente',
          tipo: 'cuota',
        },
      ],
    )

    expect(resultado.cuenta_bancaria_id).toBe('20000000-0000-4000-8000-000000000001')
    expect(resultado.pdf).toMatchObject({
      estado: 'pendiente',
      reintentable: true,
    })
    expect(body.p_cuenta).toMatchObject({
      tipo: 'perfil',
      cuenta_esperada: { cci: cuenta.cci },
    })
  })

  // Hasta el 05/09 estas dos pruebas exigían fallar cerrado si faltaba la cuenta o
  // la reserva PDF. Eso «protegía» DESPUÉS de una escritura irreversible: el
  // contrato ya existía en el servidor y el front decía error, así que el analista
  // lo volvía a crear. Ahora el alta se confirma y lo accesorio se degrada con rastro
  // (ver el bloque «un alta que el servidor confirmó NUNCA se lee como error»).
  it('si la RPC omite el id de la cuenta, el alta se confirma con cuenta_bancaria_id = null', async () => {
    const silencio = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () =>
        HttpResponse.json({
          id: '10000000-0000-4000-8000-000000000001',
          numero_contrato: '2026-01-000123',
          ...META_PRODUCTO,
        }),
      ),
    )
    try {
      const r = await crearContrato(
        {
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
          cuenta_pago: { tipo: 'existente', cuenta_id: 'cb-1' },
        },
        [],
      )
      expect(r.id).toBe('10000000-0000-4000-8000-000000000001')
      expect(r.cuenta_bancaria_id).toBeNull()
      expect(silencio).toHaveBeenCalled()
    } finally {
      silencio.mockRestore()
    }
  })

  it('si la respuesta omite la reserva PDF, el alta se confirma con el documento «pendiente» y reintentable', async () => {
    const silencio = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () =>
        HttpResponse.json({
          id: '10000000-0000-4000-8000-000000000001',
          numero_contrato: '2026-01-000123',
          cuenta_bancaria_id: '20000000-0000-4000-8000-000000000001',
        }),
      ),
    )
    try {
      const r = await crearContrato(
        {
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
          cuenta_pago: { tipo: 'existente', cuenta_id: 'cb-1' },
        },
        [],
      )
      expect(r.pdf).toEqual({
        contrato_id: '10000000-0000-4000-8000-000000000001',
        job_id: null,
        estado: 'pendiente',
        reintentable: true,
      })
      expect(silencio).toHaveBeenCalled()
    } finally {
      silencio.mockRestore()
    }
  })
})

describe('crearContrato — un alta que el servidor confirmó NUNCA se lee como error', () => {
  // 05/09/2026: DIAZ VILLANUEVA quedó con DOS contratos idénticos (2026-01-000025 y
  // 2026-01-000253, 61 s de diferencia). El primer alta salió 200, pero la respuesta
  // traía `pdf.estado = 'sin_reserva'` (contrato firmado el 11/03/2026, régimen
  // documental ANTERIOR: el servidor no emite documento) y el esquema exigía la
  // reserva `pendiente`: el front dijo «El servidor no confirmó completamente el
  // contrato…», el analista cambió el número y lo creó otra vez. Desde el 21/08,
  // 33 altas del régimen anterior pasaron por ese error falso. Regla que fija este
  // bloque: la PRUEBA del alta es `id` + `numero_contrato`; todo lo demás se degrada
  // con rastro, jamás se convierte en error después de una escritura irreversible.
  const ALTA = {
    cliente_id: '4e0c11bc-3fec-492b-a90e-93fd75b36ad4',
    capital: 20000,
    moneda: 'PEN' as const,
    tasa_anual: 15,
    modalidad: 'mensual' as const,
    tipo_interes: 'simple' as const,
    categoria: 'nuevo' as const,
    fecha_inicio: '2026-03-11',
    fecha_vencimiento: '2027-03-11',
    numero_contrato: '2026-01-000025',
    notas_internas: null,
    cuenta_pago: { tipo: 'existente' as const, cuenta_id: '470bfde6-aa80-41ff-904a-705b523cca5c' },
  }
  const CUOTA = [{ numero_cuota: 1, fecha_programada: '2026-04-11', monto_programado: 250, tipo: 'cuota' }] as never

  // Respuesta REAL de producción para un contrato del régimen anterior: lo que
  // devuelve `private.contrato_pdf_estado_base` cuando no hay job (rama
  // `sin_reserva`), unido a lo que devuelve `public.crear_contrato`.
  const RESPUESTA_REGIMEN_ANTERIOR = {
    id: '74b5694f-843d-4b88-be13-5f8fc8e82404',
    numero_contrato: '2026-01-000025',
    operacion_id: null,
    conversion_elegible: null,
    cuenta_bancaria_id: '470bfde6-aa80-41ff-904a-705b523cca5c',
    pdf: {
      contrato_id: '74b5694f-843d-4b88-be13-5f8fc8e82404',
      job_id: null,
      estado: 'sin_reserva',
      storage_bucket: 'contratos-generados',
      storage_path: null,
      nombre_archivo: null,
      template_version: null,
      intentos: 0,
      lease_expira_en: null,
      reintentable: false,
      sha256: null,
      bytes: null,
      archivo: null,
    },
  }

  let consolaError: ReturnType<typeof vi.spyOn>
  beforeEach(() => {
    consolaError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
  })
  afterEach(() => {
    consolaError.mockRestore()
  })

  function responder(cuerpo: Record<string, unknown>) {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () => HttpResponse.json(cuerpo)),
    )
  }

  it('acepta el alta del régimen anterior tal como la emite producción HOY (sin_reserva): el caso de los duplicados del 05/09', async () => {
    responder(RESPUESTA_REGIMEN_ANTERIOR)
    const r = await crearContrato(ALTA, CUOTA)
    expect(r.id).toBe('74b5694f-843d-4b88-be13-5f8fc8e82404')
    expect(r.numero_contrato).toBe('2026-01-000025')
    expect(r.cuenta_bancaria_id).toBe('470bfde6-aa80-41ff-904a-705b523cca5c')
    expect(r.pdf).toEqual({
      contrato_id: '74b5694f-843d-4b88-be13-5f8fc8e82404',
      job_id: null,
      estado: 'sin_reserva',
      reintentable: false,
    })
    expect(r.idempotente).toBe(false)
    // Es la respuesta esperada del servidor, no una degradación: sin rastro de error.
    expect(consolaError).not.toHaveBeenCalled()
  })

  it('una forma DESCONOCIDA del bloque pdf degrada el estado documental con rastro, no el alta', async () => {
    responder({
      id: '74b5694f-843d-4b88-be13-5f8fc8e82404',
      numero_contrato: '2026-01-000025',
      cuenta_bancaria_id: '470bfde6-aa80-41ff-904a-705b523cca5c',
      pdf: { estado: 'plantilla-v9-que-aun-no-existe', job_id: 7 },
    })
    const r = await crearContrato(ALTA, CUOTA)
    expect(r.id).toBe('74b5694f-843d-4b88-be13-5f8fc8e82404')
    // Estado «pendiente y reintentable»: la pantalla vuelve a preguntar a la edge,
    // que es la fuente de verdad del documento. Nunca se inventa un sellado.
    expect(r.pdf).toEqual({
      contrato_id: '74b5694f-843d-4b88-be13-5f8fc8e82404',
      job_id: null,
      estado: 'pendiente',
      reintentable: true,
    })
    expect(consolaError).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(consolaError.mock.calls[0])).toContain('crm.contrato.pdf_respuesta_invalida')
  })

  it('un pdf de OTRO contrato no se acepta como propio: se degrada igual que una forma desconocida', async () => {
    responder({
      ...RESPUESTA_REGIMEN_ANTERIOR,
      pdf: { ...RESPUESTA_REGIMEN_ANTERIOR.pdf, contrato_id: '9597d503-1bff-4853-9c47-1eef5b5d3dfe' },
    })
    const r = await crearContrato(ALTA, CUOTA)
    expect(r.id).toBe('74b5694f-843d-4b88-be13-5f8fc8e82404')
    expect(r.pdf.contrato_id).toBe('74b5694f-843d-4b88-be13-5f8fc8e82404')
    expect(r.pdf.estado).toBe('pendiente')
    expect(consolaError).toHaveBeenCalledTimes(1)
  })

  it('sin cuenta_bancaria_id el alta sigue confirmada: la cuenta queda como no confirmada (null) y con rastro', async () => {
    const { cuenta_bancaria_id: _omitida, ...sinCuenta } = RESPUESTA_REGIMEN_ANTERIOR
    void _omitida
    responder(sinCuenta)
    const r = await crearContrato(ALTA, CUOTA)
    expect(r.id).toBe('74b5694f-843d-4b88-be13-5f8fc8e82404')
    expect(r.cuenta_bancaria_id).toBeNull()
    expect(consolaError).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(consolaError.mock.calls[0])).toContain('crm.contrato.cuenta_no_confirmada')
  })

  it('sin `id` la respuesta NO es un alta: sigue fallando cerrado (no hay prueba de escritura)', async () => {
    responder({ numero_contrato: '2026-01-000025', cuenta_bancaria_id: '470bfde6-aa80-41ff-904a-705b523cca5c' })
    await expect(crearContrato(ALTA, CUOTA)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
    responder({})
    await expect(crearContrato(ALTA, CUOTA)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('un error del servidor (400) sigue siendo error: el 400 de las 16:04:22 fue «El N de contrato ya existe»', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () =>
        HttpResponse.json(
          { code: 'P0001', message: 'El N de contrato 2026-01-000025 ya existe', details: null, hint: null },
          { status: 400 },
        ),
      ),
    )
    await expect(crearContrato(ALTA, CUOTA)).rejects.toBeInstanceOf(CrmApiError)
  })

  it('la clave de idempotencia viaja DENTRO de p_contrato y solo si el caller la mandó', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return HttpResponse.json(RESPUESTA_REGIMEN_ANTERIOR)
      }),
    )
    await crearContrato({ ...ALTA, clave_idempotencia: 'f6a1c2d4-3b5e-4f70-8a91-b2c3d4e5f607' }, CUOTA)
    expect((body.p_contrato as Record<string, unknown>).clave_idempotencia).toBe('f6a1c2d4-3b5e-4f70-8a91-b2c3d4e5f607')
    expect(body).not.toHaveProperty('p_clave_idempotencia')

    await crearContrato(ALTA, CUOTA)
    expect(body.p_contrato).not.toHaveProperty('clave_idempotencia')
  })

  it('un alta repetida por la misma clave se reporta como idempotente (el servidor devolvió la anterior)', async () => {
    responder({ ...RESPUESTA_REGIMEN_ANTERIOR, idempotente: true })
    const r = await crearContrato({ ...ALTA, clave_idempotencia: 'f6a1c2d4-3b5e-4f70-8a91-b2c3d4e5f607' }, CUOTA)
    expect(r.idempotente).toBe(true)
    expect(r.numero_contrato).toBe('2026-01-000025')
  })
})

describe('actualizarContrato (wrapper crm.actualizar_contrato_con_cuenta_pdf_v3)', () => {
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
      http.post(`${BASE}/rest/v1/rpc/actualizar_contrato_con_cuenta_pdf_v3`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return new HttpResponse(null, { status: 204 })
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
      http.post(`${BASE}/rest/v1/rpc/actualizar_contrato_con_cuenta_pdf_v3`, async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return new HttpResponse(null, { status: 204 })
      }),
    )

    await actualizarContrato('ct-1', { ...contratoBase, titulares: [] }, [])

    expect((body.p_contrato as Record<string, unknown>).titulares).toEqual([])
  })

  it('ventana vencida: el RAISE P0001 del servidor llega con su mensaje es-PE', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/actualizar_contrato_con_cuenta_pdf_v3`, () =>
        HttpResponse.json(
          {
            code: 'P0001',
            message: 'Solo puedes corregir un contrato dentro de las 5 horas de creado',
            details: null,
          },
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

describe('crearContrato — los rechazos de idempotencia del servidor llegan con su código propio', () => {
  const ALTA = {
    cliente_id: '4e0c11bc-3fec-492b-a90e-93fd75b36ad4',
    capital: 20000,
    moneda: 'PEN' as const,
    tasa_anual: 15,
    modalidad: 'mensual' as const,
    tipo_interes: 'simple' as const,
    categoria: 'nuevo' as const,
    fecha_inicio: '2026-03-11',
    fecha_vencimiento: '2027-03-11',
    numero_contrato: '2026-01-000253',
    notas_internas: null,
    cuenta_pago: { tipo: 'existente' as const, cuenta_id: '470bfde6-aa80-41ff-904a-705b523cca5c' },
    clave_idempotencia: 'f6a1c2d4-3b5e-4f70-8a91-b2c3d4e5f607',
  }
  function rechazar(message: string, hint: string) {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () =>
        HttpResponse.json({ code: 'P0409', message, details: null, hint }, { status: 400 }),
      ),
    )
  }

  it('misma clave con otros datos → ALTA_YA_CREADA, con el mensaje del servidor (nombra el contrato)', async () => {
    rechazar(
      'Este intento ya creó el contrato 2026-01-000025 con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
      'ALTA_YA_CREADA_CON_OTROS_DATOS',
    )
    await expect(crearContrato(ALTA, [] as never)).rejects.toMatchObject({
      code: 'ALTA_YA_CREADA',
      message: expect.stringContaining('2026-01-000025'),
    })
  })

  it('el contrato del intento fue eliminado después → ALTA_ELIMINADA', async () => {
    rechazar('El contrato de este intento fue eliminado después; vuelve a registrar el alta', 'ALTA_ELIMINADA')
    await expect(crearContrato(ALTA, [] as never)).rejects.toMatchObject({ code: 'ALTA_ELIMINADA' })
  })

  it('Gerencia tiene la eliminación PREPARADA (55000, migración 20260905234500) → CONTRATO_EN_ELIMINACION con un mensaje que no invita a reintentar', async () => {
    server.use(
      http.post(`${BASE}/rest/v1/rpc/crear_contrato_con_cuenta_pdf_v2`, () =>
        HttpResponse.json(
          { code: '55000', message: 'El contrato está en proceso de eliminación', details: null, hint: null },
          { status: 400 },
        ),
      ),
    )
    await expect(crearContrato(ALTA, [] as never)).rejects.toMatchObject({
      code: 'CONTRATO_EN_ELIMINACION',
      message: expect.stringContaining('Gerencia está eliminando'),
    })
  })

  // F2.b [D-15] (06/09): un P0409 desconocido ya no cae en el genérico «No se pudo guardar el
  // cambio.»: se muestra el TEXTO DEL SERVIDOR con el código CONFLICTO (los P0409 de nuestras
  // puertas están en idioma de negocio y sin PII; auditor bloque 4). Lo que este caso protege
  // sigue igual: NO se cuela como idempotencia, así que el modal del alta no libera ni conserva
  // la clave por error (solo reacciona a ALTA_YA_CREADA y ALTA_ELIMINADA).
  it('cualquier otro P0409 NO se cuela como idempotencia (llega como CONFLICTO con el texto del servidor)', async () => {
    rechazar('Otro conflicto cualquiera', '')
    await expect(crearContrato(ALTA, [] as never)).rejects.toMatchObject({
      code: 'CONFLICTO',
      message: 'Otro conflicto cualquiera',
    })
  })
})
