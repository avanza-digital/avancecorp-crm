// @vitest-environment node
// listarLeads contra un Supabase SIMULADO con msw: se verifica el contrato
// HTTP real (query params PostgREST, header content-range, cuerpo de error)
// sin tocar la red — el cliente supabase-js es el de verdad.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

// El módulo real exige VITE_SUPABASE_URL/ANON_KEY; aquí se sustituye por un
// cliente apuntando al host ficticio que msw intercepta. Solo se exporta lo
// que crm-api usa en runtime (sb) — ClienteCrm es un tipo y se borra.
vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  CrmApiError,
  cerrarTarea,
  listarActividadesDelAmbito,
  listarClientes,
  listarLeads,
  listarLeadsDelAmbito,
  listarMisContratos,
  listarResumenCartera,
  listarTareasDelAmbito,
  reprogramarReunion,
} from './crm-api'
import { resumenCarteraDesdeAmbito } from '@/lib/resumen-cartera'

const RUTA_LEADS = 'http://supabase.test/rest/v1/leads'
const RUTA_CERRAR_TAREA = 'http://supabase.test/rest/v1/rpc/cerrar_tarea'
const RUTA_REPROGRAMAR = 'http://supabase.test/rest/v1/rpc/reprogramar_reunion'
const TAREA_ID = '11111111-1111-4111-8111-111111111111'
const NUEVA_ID = '22222222-2222-4222-8222-222222222222'
const OTRA_ID = '33333333-3333-4333-8333-333333333333'

/** Fila con el shape exacto de LeadRow (todas las columnas del select). */
function fila(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'l-api-1',
    nombre_completo: 'Juan Prueba',
    telefono: '+51987650000',
    correo: null,
    dni: null,
    distrito: null,
    origen: 'landing',
    etapa: 'nuevo',
    motivo_descarte: null,
    monto_estimado: 1000,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: null,
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T12:00:00.000Z',
    convertido_en: null,
    actualizado_en: '2026-07-02T12:00:00.000Z',
    activo: true,
    nota: null,
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

describe('listarLeads (msw)', () => {
  it('mapea la página feliz: filas → Lead, total desde content-range y monto string → number', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          [
            fila({ id: 'l-api-1', monto_estimado: '1500.50' }),
            fila({ id: 'l-api-2', etapa: 'contactado', monto_estimado: 200 }),
          ],
          { headers: { 'content-range': '0-1/2' } },
        ),
      ),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items).toHaveLength(2)
    expect(pagina.items[0]).toMatchObject({
      id: 'l-api-1',
      nombre_completo: 'Juan Prueba',
      origen: 'landing',
      etapa: 'nuevo',
      monto_estimado: 1500.5, // numeric(12,2) serializado como string por PostgREST
      activo: true,
    })
    expect(pagina.items[1]).toMatchObject({ id: 'l-api-2', monto_estimado: 200 })
    expect(pagina).toMatchObject({ pagina: 0, tamano: 50, total: 2, paginas: 1 })
  })

  // La CADENA ENTERA de convertido_en, eslabón por eslabón. Es la tercera vez
  // que este patrón muerde al proyecto (`actualizado_en` y `tenencia_desde` se
  // pedían al servidor, se validaban… y no se copiaban en el mapper, así que
  // llegaban `undefined` al navegador). Un test que solo mire el select o solo
  // el schema no lo habría visto.
  it('convertido_en LLEGA al navegador: se pide en el select Y sale del mapper', async () => {
    const capturadas: URL[] = []
    server.use(
      http.get(RUTA_LEADS, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json(
          [
            fila({ id: 'l-ganado', etapa: 'convertido', convertido_en: '2026-07-09T15:00:00.000Z' }),
            fila({ id: 'l-abierto' }), // sigue abierto: sin sello
          ],
          { headers: { 'content-range': '0-1/2' } },
        )
      }),
    )

    const pagina = await listarLeads({ pagina: 0 })

    // 1) Se PIDE (sin esto PostgREST no la manda y el schema opcional la traga).
    expect(capturadas[0]?.searchParams.get('select')?.split(',')).toContain('convertido_en')
    // 2) Se COPIA (el eslabón que se olvidó dos veces).
    expect(pagina.items[0]?.convertido_en).toBe('2026-07-09T15:00:00.000Z')
    // 3) Un lead sin sello llega como null, nunca undefined.
    expect(pagina.items[1]?.convertido_en).toBeNull()
  })

  it('una base SIN la columna convertido_en no vacía la cartera (opcional a propósito)', async () => {
    server.use(
      http.get(RUTA_LEADS, () => {
        const { convertido_en: _omitida, ...sinColumna } = fila()
        return HttpResponse.json([sinColumna], { headers: { 'content-range': '0-0/1' } })
      }),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items).toHaveLength(1)
    expect(pagina.items[0]?.convertido_en).toBeNull()
  })

  it.each([null, 0, '0'])('descarta una fila sin capital positivo: %s', async (monto) => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json([fila({ monto_estimado: monto })], {
          headers: { 'content-range': '0-0/1' },
        }),
      ),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items).toEqual([])
  })

  it.each(['landing', 'formulario', 'web', 'campania', 'whatsapp'] as const)(
    'acepta el origen activo o histórico %s al leer Supabase',
    async (origen) => {
      server.use(
        http.get(RUTA_LEADS, () =>
          HttpResponse.json([fila({ origen })], { headers: { 'content-range': '0-0/1' } }),
        ),
      )

      const pagina = await listarLeads({ pagina: 0 })

      expect(pagina.items[0]?.origen).toBe(origen)
    },
  )

  it('descarta la fila fuera de contrato (etapa zombie) sin reventar y conserva las válidas', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          [
            fila({ id: 'l-ok-1' }),
            fila({ id: 'l-zombie', etapa: 'zombie' }),
            fila({ id: 'l-ok-2', etapa: 'convertido' }),
          ],
          { headers: { 'content-range': '0-2/3' } },
        ),
      ),
    )

    const pagina = await listarLeads({ pagina: 0 })

    expect(pagina.items.map((l) => l.id)).toEqual(['l-ok-1', 'l-ok-2'])
    // El total sigue siendo el del servidor: la fila inválida se descarta, no se re-cuenta.
    expect(pagina.total).toBe(3)
  })

  it('un error PostgREST (500 con message/code) lanza CrmApiError con el code original', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          { message: 'boom interno', code: 'PGRST123', details: null, hint: null },
          { status: 500 },
        ),
      ),
    )

    const promesa = listarLeads({ pagina: 0 })

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({
      code: 'PGRST123',
      message: 'No se pudo cargar la cartera.',
    })
  })

  it('los filtros viajan como query params PostgREST: etapa=eq.… y vendedor_id=is.null', async () => {
    const capturadas: URL[] = []
    server.use(
      http.get(RUTA_LEADS, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json([], { headers: { 'content-range': '*/0' } })
      }),
    )

    await listarLeads({ pagina: 0, etapa: 'contactado', vendedorId: 'sin_asignar' })

    const url = capturadas[0]
    expect(url?.searchParams.get('etapa')).toBe('eq.contactado')
    expect(url?.searchParams.get('vendedor_id')).toBe('is.null')
    // Sin incluirInactivos, la consulta recorta a activos.
    expect(url?.searchParams.get('activo')).toBe('eq.true')
  })

  it('la búsqueda con caracteres peligrosos llega saneada al parámetro or=', async () => {
    const capturadas: URL[] = []
    server.use(
      http.get(RUTA_LEADS, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json([], { headers: { 'content-range': '*/0' } })
      }),
    )

    await listarLeads({ pagina: 0, texto: 'juan,or(activo' })

    const or = capturadas[0]?.searchParams.get('or')
    expect(or).toBeTruthy()
    // La coma y el paréntesis del usuario se volvieron espacios: solo queda
    // un patrón ILIKE, nunca sintaxis lógica inyectada.
    expect(or).toContain('nombre_completo.ilike.%juan or activo%')
    expect(or).not.toContain('juan,')
    expect(or).not.toContain('or(activo')
  })
})

describe('listarLeadsDelAmbito (msw)', () => {
  it('descarta y registra filas inválidas también en la ruta real del store', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json([
          fila({ id: 'l-ambito-ok' }),
          fila({ id: 'l-ambito-sin-capital', monto_estimado: null }),
        ]),
      ),
    )

    const leads = await listarLeadsDelAmbito()

    expect(leads.map((lead) => lead.id)).toEqual(['l-ambito-ok'])
    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({ evento: 'crm.leads.ambito_filas_invalidas' }),
    )
  })

  // Alarma de topes (F0 escalabilidad): tope lleno = probable recorte MUDO del
  // servidor. Se cuentan las filas CRUDAS recibidas (2000), no las que
  // sobreviven al parse — el recorte ocurre antes de validar.
  it('avisa a observabilidad cuando la respuesta llena el tope de 2000', async () => {
    server.use(
      http.get(RUTA_LEADS, () =>
        HttpResponse.json(
          Array.from({ length: 2000 }, (_, i) => fila({ id: `l-tope-${i}` })),
        ),
      ),
    )

    const leads = await listarLeadsDelAmbito()

    expect(leads).toHaveLength(2000)
    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({
        evento: 'crm_api.tope_alcanzado',
        datos: expect.objectContaining({
          contexto: expect.objectContaining({ lectura: 'leads_del_ambito', tope: 2000 }),
        }),
      }),
    )
  })

  it('NO dispara la alarma de tope por debajo del límite', async () => {
    server.use(
      http.get(RUTA_LEADS, () => HttpResponse.json([fila({ id: 'l-bajo-tope' })])),
    )

    await listarLeadsDelAmbito()

    expect(console.error).not.toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({ evento: 'crm_api.tope_alcanzado' }),
    )
  })

  // Ventana de convertidos (F1): el corte viaja como filtro OR de PostgREST —
  // un convertido con más de 45 días no debe llegar al navegador. El mismo
  // corte lo aplican las RPC de métricas; si este param desaparece, tiles y
  // tabla contarían películas distintas.
  it('pide al servidor la ventana de convertidos de 45 días (etapa.neq OR convertido_en.gte)', async () => {
    const capturadas: URL[] = []
    server.use(
      http.get(RUTA_LEADS, ({ request }) => {
        capturadas.push(new URL(request.url))
        return HttpResponse.json([])
      }),
    )

    const antes = Date.now()
    await listarLeadsDelAmbito()

    const or = capturadas[0]?.searchParams.get('or') ?? ''
    expect(or).toContain('etapa.neq.convertido')
    const sello = /convertido_en\.gte\."([^"]+)"/.exec(or)?.[1]
    expect(sello).toBeTruthy()
    // El corte es "hoy − 45 días" calculado al momento de la llamada.
    const corteMs = Date.parse(sello ?? '')
    expect(Math.abs(corteMs - (antes - 45 * 86_400_000))).toBeLessThan(60_000)
  })
})

describe('listarResumenCartera (msw)', () => {
  const RUTA_RESUMEN = 'http://supabase.test/rest/v1/rpc/resumen_cartera_fn'
  // El espejo demo produce el shape EXACTO del RPC: sirve de payload de prueba
  // sin duplicar el contrato a mano.
  const payloadValido = () => resumenCarteraDesdeAmbito([], [], Date.now())

  it('devuelve el payload validado cuando cumple el contrato version:1', async () => {
    server.use(http.post(RUTA_RESUMEN, () => HttpResponse.json(payloadValido())))

    const resumen = await listarResumenCartera()

    expect(resumen.version).toBe(1)
    expect(resumen.totales.vivos).toBe(0)
    expect(resumen.embudo).toHaveLength(6)
  })

  it('rechaza fail-closed un payload fuera de contrato (sin totales)', async () => {
    const { totales: _omitidos, ...roto } = payloadValido()
    server.use(http.post(RUTA_RESUMEN, () => HttpResponse.json(roto)))

    await expect(listarResumenCartera()).rejects.toMatchObject({
      code: 'RESUMEN_CARTERA_CONTRACT',
    })
  })

  it('rechaza una ventana de convertidos DISTINTA de la del front: dos cortes no pueden convivir', async () => {
    server.use(
      http.post(RUTA_RESUMEN, () =>
        HttpResponse.json({ ...payloadValido(), ventana_convertidos_dias: 60 }),
      ),
    )

    await expect(listarResumenCartera()).rejects.toMatchObject({
      code: 'RESUMEN_CARTERA_CONTRACT',
    })
  })

  it('un error PostgREST se traduce a CrmApiError con su code original', async () => {
    server.use(
      http.post(RUTA_RESUMEN, () =>
        HttpResponse.json(
          { message: 'boom', code: 'PGRST123', details: null, hint: null },
          { status: 500 },
        ),
      ),
    )

    await expect(listarResumenCartera()).rejects.toMatchObject({ code: 'PGRST123' })
  })
})

describe('alarma de topes en el resto de lecturas acotadas (msw)', () => {
  // La alarma cuenta las filas CRUDAS del servidor (el recorte ocurre antes de
  // validar), así que basta responder N objetos vacíos: la lectura devuelve []
  // (filas fuera de contrato) pero el tope SÍ debe avisarse. Cubre que cada
  // call-site pasa su constante correcta.
  it.each([
    ['tareas_del_ambito', 2000, 'GET', 'http://supabase.test/rest/v1/tareas', () => listarTareasDelAmbito()],
    ['clientes_cartera', 2000, 'GET', 'http://supabase.test/rest/v1/clientes_basicos', () => listarClientes()],
    ['contratos_cartera', 2000, 'GET', 'http://supabase.test/rest/v1/contratos_cartera', () => listarMisContratos()],
    ['actividades_del_ambito', 10000, 'POST', 'http://supabase.test/rest/v1/rpc/actividades_del_ambito_fn', () => listarActividadesDelAmbito()],
  ] as const)('avisa cuando %s llena su tope de %i', async (lectura, tope, metodo, ruta, invocar) => {
    const filasVacias = Array.from({ length: tope }, () => ({}))
    server.use(
      metodo === 'GET'
        ? http.get(ruta, () => HttpResponse.json(filasVacias))
        : http.post(ruta, () => HttpResponse.json(filasVacias)),
    )

    await invocar()

    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({
        evento: 'crm_api.tope_alcanzado',
        datos: expect.objectContaining({
          contexto: expect.objectContaining({ lectura, tope }),
        }),
      }),
    )
  })
})

describe('reprogramarReunion (msw)', () => {
  it('conserva el payload exacto y acepta únicamente la confirmación coherente', async () => {
    let payload: unknown
    server.use(
      http.post(RUTA_REPROGRAMAR, async ({ request }) => {
        payload = await request.json()
        return HttpResponse.json({
          ok: true,
          tarea_anterior_id: TAREA_ID,
          tarea_nueva_id: NUEVA_ID,
          reprogramaciones: 1,
        })
      }),
    )

    await expect(reprogramarReunion(TAREA_ID, '2026-08-06T15:00:00.000Z', NUEVA_ID))
      .resolves.toEqual({ tarea_nueva_id: NUEVA_ID })
    expect(payload).toEqual({
      p_tarea_id: TAREA_ID,
      p_vence_en: '2026-08-06T15:00:00.000Z',
      p_nueva_id: NUEVA_ID,
    })
  })

  it.each([
    ['ok no verdadero', { ok: false, tarea_anterior_id: TAREA_ID, tarea_nueva_id: NUEVA_ID, reprogramaciones: 1 }],
    ['id anterior inválido', { ok: true, tarea_anterior_id: 'invalido', tarea_nueva_id: NUEVA_ID, reprogramaciones: 1 }],
    ['id nuevo inválido', { ok: true, tarea_anterior_id: TAREA_ID, tarea_nueva_id: 'invalido', reprogramaciones: 1 }],
    ['id anterior distinto del solicitado', { ok: true, tarea_anterior_id: OTRA_ID, tarea_nueva_id: NUEVA_ID, reprogramaciones: 1 }],
    ['id nuevo distinto del solicitado', { ok: true, tarea_anterior_id: TAREA_ID, tarea_nueva_id: OTRA_ID, reprogramaciones: 1 }],
    ['contador ausente', { ok: true, tarea_anterior_id: TAREA_ID, tarea_nueva_id: NUEVA_ID }],
    ['contador no positivo', { ok: true, tarea_anterior_id: TAREA_ID, tarea_nueva_id: NUEVA_ID, reprogramaciones: 0 }],
    ['contador no entero', { ok: true, tarea_anterior_id: TAREA_ID, tarea_nueva_id: NUEVA_ID, reprogramaciones: 1.5 }],
  ])('rechaza una respuesta fuera de contrato: %s', async (_caso, respuesta) => {
    server.use(http.post(RUTA_REPROGRAMAR, () => HttpResponse.json(respuesta)))

    await expect(reprogramarReunion(TAREA_ID, '2026-08-06T15:00:00.000Z', NUEVA_ID))
      .rejects.toMatchObject({
        code: 'ROW_CONTRACT',
        message: 'La reprogramación respondió fuera del contrato esperado.',
      })
  })

  it('rechaza que la tarea anterior y la nueva sean el mismo UUID', async () => {
    server.use(
      http.post(RUTA_REPROGRAMAR, () => HttpResponse.json({
        ok: true,
        tarea_anterior_id: TAREA_ID,
        tarea_nueva_id: TAREA_ID,
        reprogramaciones: 1,
      })),
    )

    await expect(reprogramarReunion(TAREA_ID, '2026-08-06T15:00:00.000Z', TAREA_ID))
      .rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })
})

describe('cerrarTarea (msw)', () => {
  it('envía la clasificación estructurada de reuniones de cliente sin inventar campos nulos', async () => {
    const payloads: unknown[] = []
    server.use(
      http.post(RUTA_CERRAR_TAREA, async ({ request }) => {
        payloads.push(await request.json())
        return HttpResponse.json({ ok: true, siguiente_id: null })
      }),
    )

    await cerrarTarea({
      tarea_id: TAREA_ID,
      estado: 'completada',
      resultado_tipo: 'reunion_realizada',
      resultado_detalle: 'Solicitó una propuesta',
      resultado_reunion: 'interesado',
      motivo_no_realizada: null,
      siguiente: null,
    })
    await cerrarTarea({
      tarea_id: OTRA_ID,
      estado: 'cancelada',
      resultado_tipo: null,
      resultado_detalle: 'El cliente pidió cancelar',
      resultado_reunion: null,
      motivo_no_realizada: 'cancelada_cliente',
      siguiente: null,
    })

    expect(payloads).toEqual([
      {
        p_tarea_id: TAREA_ID,
        p_estado: 'completada',
        p_resultado_tipo: 'reunion_realizada',
        p_resultado_detalle: 'Solicitó una propuesta',
        p_siguiente: null,
        p_resultado_reunion: 'interesado',
      },
      {
        p_tarea_id: OTRA_ID,
        p_estado: 'cancelada',
        p_resultado_detalle: 'El cliente pidió cancelar',
        p_siguiente: null,
        p_motivo_no_realizada: 'cancelada_cliente',
      },
    ])
  })
})
