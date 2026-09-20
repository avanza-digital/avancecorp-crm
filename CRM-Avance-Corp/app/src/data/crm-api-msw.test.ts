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
  TAMANO_PAGINA_HISTORIAL,
  cerrarTarea,
  listarActividadesDeLead,
  listarLeads,
  listarLeadsDelAmbito,
  obtenerLeadDelAmbitoPorId,
  listarResumenCartera,
  listarTareasDelAmbito,
  TAMANO_LOTE_TAREAS,
  listarActividadesRecientes,
  TAMANO_BITACORA_RECIENTES,
  buscarLeadsGlobal,
  TAMANO_BUSQUEDA_GLOBAL,
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

const server = setupServer(http.post('http://supabase.test/rest/v1/rpc/postventa_agenda_fn', () => HttpResponse.json({code: 'PGRST202', message: 'F6 no instalada'}, {status: 404})))

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
  function carteraConCap(cantidad: number, capServidor = 1000) {
    const capturadas: URL[] = []
    // Empates de timestamp atraviesan el borde de página: el ID debe ser el
    // desempate. Son identidades sintéticas, sin datos de producción.
    const filas = Array.from({ length: cantidad }, (_, i) => fila({
      id: `10000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
      actualizado_en: new Date(Date.parse('2026-07-02T12:00:00Z') - Math.floor(i / 750) * 1000).toISOString(),
    }))
    server.use(http.get(RUTA_LEADS, ({ request }) => {
      const url = new URL(request.url); capturadas.push(url)
      expect(request.headers.get('accept-profile')).toBe('crm')
      const criterio = url.searchParams.get('or') ?? ''
      expect(criterio).toContain('etapa.neq.convertido')
      expect(criterio).toContain('convertido_en.gte.')
      const actualizado = /actualizado_en\.lt\."([^"]+)"/.exec(criterio)?.[1]
      const id = /id\.gt\."([^"]+)"/.exec(criterio)?.[1]
      const elegibles = actualizado && id ? filas.filter((f) => String(f.actualizado_en) < actualizado
        || (f.actualizado_en === actualizado && String(f.id) > id)) : filas
      const limite = Number(url.searchParams.get('limit'))
      return HttpResponse.json(elegibles.slice(0, Math.min(limite, capServidor)))
    }))
    return { capturadas, filas }
  }

  it('recupera la fila 1148 de 1157 pese al máximo de 1000 filas de PostgREST', async () => {
    const { capturadas, filas } = carteraConCap(1157)
    const leads = await listarLeadsDelAmbito()
    expect(leads).toHaveLength(1157)
    expect(leads[1147]?.id).toBe(filas[1147]!.id)
    expect(new Set(leads.map((l) => l.id)).size).toBe(1157)
    expect(capturadas).toHaveLength(3)
    expect(capturadas.every((url) => url.searchParams.get('limit') === '500')).toBe(true)
    expect(capturadas.every((url) => url.searchParams.get('order') === 'actualizado_en.desc,id.asc')).toBe(true)
    expect(capturadas.every((url) => !url.searchParams.has('offset'))).toBe(true)
    expect(capturadas[1]?.searchParams.get('or')).toContain(String(filas[499]!.id))
  })
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
  // servidor. Se cuentan las filas CRUDAS recibidas (5000, el puente de la
  // Fase 1 «sin topes»), no las que sobreviven al parse — el recorte ocurre
  // antes de validar.
  it('avisa a observabilidad cuando la respuesta llena el tope de 5000', async () => {
    const { capturadas } = carteraConCap(5150)

    const leads = await listarLeadsDelAmbito()

    expect(leads).toHaveLength(5000)
    expect(capturadas).toHaveLength(10)
    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({
        evento: 'crm_api.tope_alcanzado',
        datos: expect.objectContaining({
          contexto: expect.objectContaining({ lectura: 'leads_del_ambito', tope: 5000 }),
        }),
      }),
    )
  })

  // La alarma de TENDENCIA del puente suena semanas antes del techo: a 4 000
  // filas ya avisa aunque el tope de 5 000 no se haya tocado.
  it('avisa la tendencia a 4000 sin declarar lleno el tope de 5000', async () => {
    carteraConCap(4200)

    const leads = await listarLeadsDelAmbito()

    expect(leads).toHaveLength(4200)
    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({
        evento: 'crm_api.tope_alcanzado',
        datos: expect.objectContaining({
          contexto: expect.objectContaining({ lectura: 'leads_del_ambito_tendencia', tope: 4000 }),
        }),
      }),
    )
    expect(console.error).not.toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({
        datos: expect.objectContaining({
          contexto: expect.objectContaining({ lectura: 'leads_del_ambito', tope: 5000 }),
        }),
      }),
    )
  })

  it('no entrega una cartera parcial si falla una página posterior', async () => {
    let llamadas = 0
    server.use(http.get(RUTA_LEADS, () => ++llamadas === 1
      ? HttpResponse.json(Array.from({ length: 500 }, (_, i) => fila({ id: `l-${i}` })))
      : HttpResponse.json({ code: '42501', message: 'Sin acceso' }, { status: 403 })))
    await expect(listarLeadsDelAmbito()).rejects.toMatchObject({ code: '42501' })
    expect(llamadas).toBe(2)
  })

  it('no duplica una identidad que reaparece tras un cambio concurrente entre lotes', async () => {
    let llamadas = 0
    server.use(http.get(RUTA_LEADS, () => HttpResponse.json(++llamadas === 1
      ? Array.from({ length: 500 }, (_, i) => fila({ id: `l-${i}` }))
      : [fila({ id: 'l-10' }), fila({ id: 'l-500' })])))
    const leads = await listarLeadsDelAmbito()
    expect(leads).toHaveLength(501)
    expect(leads.filter((lead) => lead.id === 'l-10')).toHaveLength(1)
  })

  it('detiene la carga sin pedir otro lote cuando se cancela la sesión', async () => {
    const cancelacion = new AbortController()
    let llamadas = 0
    server.use(http.get(RUTA_LEADS, () => {
      llamadas += 1
      cancelacion.abort()
      return HttpResponse.json(Array.from({ length: 500 }, (_, i) => fila({ id: `l-${i}` })))
    }))
    await expect(listarLeadsDelAmbito(cancelacion.signal)).rejects.toMatchObject({ name: 'AbortError' })
    expect(llamadas).toBe(1)
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

describe('obtenerLeadDelAmbitoPorId (msw)', () => {
  it('lee la ficha completa por ID en crm con activo=true y aplica el mapeador canónico', async () => {
    let pedida: URL | undefined
    server.use(http.get(RUTA_LEADS, ({ request }) => {
      pedida = new URL(request.url)
      expect(request.headers.get('accept-profile')).toBe('crm')
      return HttpResponse.json([fila({ id: 'fuera-del-lote', monto_estimado: '2000.50', nota: 'Detalle completo' })])
    }))
    await expect(obtenerLeadDelAmbitoPorId('fuera-del-lote')).resolves.toMatchObject({ id: 'fuera-del-lote', monto_estimado: 2000.5, nota: 'Detalle completo', telefono: '+51987650000' })
    expect(pedida?.searchParams.get('id')).toBe('eq.fuera-del-lote')
    expect(pedida?.searchParams.get('activo')).toBe('eq.true')
    expect(pedida?.searchParams.get('select')).toContain('telefono,')
    expect(pedida?.searchParams.has('or')).toBe(false)
  })
  it('devuelve null si RLS no devuelve el lead, sin revelar su existencia', async () => {
    server.use(http.get(RUTA_LEADS, () => HttpResponse.json([])))
    await expect(obtenerLeadDelAmbitoPorId('fuera-de-ambito')).resolves.toBeNull()
  })
  it.each([{ monto_estimado: null }, { id: 'otra-fila' }, { activo: false }])('rechaza datos incompletos o de otra identidad: %j', async (cambio) => {
    server.use(http.get(RUTA_LEADS, () => HttpResponse.json([fila(cambio)])))
    await expect(obtenerLeadDelAmbitoPorId('l-api-1')).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
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

describe('listarActividadesRecientes — bitácora del directorio (msw)', () => {
  // Fase 3 «sin topes»: ya no hay lecturas acotadas por un tope en el front
  // (actividades: por lead y por bitácora; tareas: por cursor). Esta es la
  // única lectura nueva y es un feed de tamaño fijo, no una página.
  const RUTA = 'http://supabase.test/rest/v1/rpc/actividades_recientes_fn'
  const filaReciente = (i: number, sobre: Record<string, unknown> = {}) => ({
    id: `77777777-0000-4000-8000-${String(i).padStart(12, '0')}`,
    lead_id: '44444444-4444-4444-8444-444444444444',
    lead_nombre: 'CLIENTE DE PRUEBA',
    tipo: 'llamada_realizada',
    detalle: null,
    autor_nombre: 'ANALISTA PRUEBA',
    creado_en: `2026-09-19T12:0${i}:00+00:00`,
    ...sobre,
  })

  it('pide exactamente el tamaño de la bitácora y devuelve las filas con el lead embebido', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(http.post(RUTA, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      return HttpResponse.json({ version: 1, items: [filaReciente(2), filaReciente(1), filaReciente(0)] })
    }))

    const filas = await listarActividadesRecientes()

    expect(cuerpos).toEqual([{ p_limite: TAMANO_BITACORA_RECIENTES }])
    expect(filas.map((a) => a.id)).toEqual([filaReciente(2).id, filaReciente(1).id, filaReciente(0).id])
    expect(filas[0]).toMatchObject({ lead_nombre: 'CLIENTE DE PRUEBA', autor_nombre: 'ANALISTA PRUEBA' })
  })

  it('una fila fuera de contrato se descarta CONTADA; un lead sin nombre visible se tolera', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({
      version: 1,
      items: [filaReciente(0, { tipo: 'tipo_futuro' }), filaReciente(1, { lead_nombre: null })],
    })))

    const filas = await listarActividadesRecientes()

    expect(filas).toHaveLength(1)
    expect(filas[0]?.lead_nombre).toBeNull()
    expect(console.error).toHaveBeenCalledWith('[ac-crm]', expect.objectContaining({
      evento: 'crm.actividades.recientes_filas_invalidas',
      datos: expect.objectContaining({ contexto: expect.objectContaining({ descartadas: 1, recibidas: 2 }) }),
    }))
  })

  it('más filas de las pedidas o una versión desconocida no se aceptan como bitácora', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({
      version: 1,
      items: Array.from({ length: TAMANO_BITACORA_RECIENTES + 1 }, (_, i) => filaReciente(i)),
    })))
    await expect(listarActividadesRecientes()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })

    server.use(http.post(RUTA, () => HttpResponse.json({ version: 2, items: [] })))
    await expect(listarActividadesRecientes()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('42501 es la denegación de admisión de la puerta, con su propio mensaje', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json(
      { code: '42501', message: 'No autorizado', details: null, hint: null },
      { status: 403 },
    )))

    await expect(listarActividadesRecientes()).rejects.toMatchObject({
      code: '42501',
      message: 'Tu cuenta no tiene acceso a la actividad del CRM.',
    })
  })
})

describe('listarActividadesDeLead — historial por lead con cursor keyset (msw)', () => {
  const RUTA = 'http://supabase.test/rest/v1/rpc/actividades_de_lead_fn'
  const LEAD = '44444444-4444-4444-8444-444444444444'
  const senales = { tiene_reunion_realizada: true, tiene_contacto: true, ultima_conversacion_en: '2026-09-10T10:00:00+00:00' }
  const filaAct = (i: number, sobre: Record<string, unknown> = {}) => ({
    id: `55555555-0000-4000-8000-${String(i).padStart(12, '0')}`,
    lead_id: LEAD,
    tipo: 'llamada_no_contestada',
    detalle: null,
    autor_nombre: 'ANALISTA PRUEBA',
    // Empates de fecha a propósito: el desempate por id es parte del cursor.
    creado_en: new Date(Date.parse('2026-09-19T12:00:00Z') - Math.floor(i / 3) * 60_000).toISOString(),
    ...sobre,
  })

  it('pide limite+1, recorta a la página, avanza desde la última fila CRUDA y traduce las señales', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(http.post(RUTA, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      const filas = Array.from({ length: TAMANO_PAGINA_HISTORIAL + 1 }, (_, i) => filaAct(i))
      return HttpResponse.json({ version: 1, items: filas, senales })
    }))

    const pagina = await listarActividadesDeLead(LEAD, null)

    expect(cuerpos[0]).toEqual({ p_lead_id: LEAD, p_limite: TAMANO_PAGINA_HISTORIAL + 1 })
    expect(pagina.items).toHaveLength(TAMANO_PAGINA_HISTORIAL)
    const ultima = filaAct(TAMANO_PAGINA_HISTORIAL - 1)
    expect(pagina.cursor).toEqual({ creadoEn: ultima.creado_en, id: ultima.id })
    expect(pagina.senales).toEqual({
      tieneReunionRealizada: true,
      tieneContacto: true,
      ultimaConversacionEn: '2026-09-10T10:00:00+00:00',
    })

    await listarActividadesDeLead(LEAD, pagina.cursor)
    expect(cuerpos[1]).toEqual({
      p_lead_id: LEAD,
      p_limite: TAMANO_PAGINA_HISTORIAL + 1,
      p_antes_de: ultima.creado_en,
      p_antes_id: ultima.id,
    })
  })

  it('sin la fila de más no hay más páginas: cursor null', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({ version: 1, items: [filaAct(0), filaAct(1)], senales })))

    const pagina = await listarActividadesDeLead(LEAD, null)

    expect(pagina.items.map((a) => a.id)).toEqual([filaAct(0).id, filaAct(1).id])
    expect(pagina.cursor).toBeNull()
  })

  it('una fila fuera de contrato o de OTRO lead se descarta CONTADA (telemetría), no en silencio', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({
      version: 1,
      items: [filaAct(0), filaAct(1, { tipo: 'tipo_futuro' }), filaAct(2, { lead_id: 'otro-lead' })],
      senales,
    })))

    const pagina = await listarActividadesDeLead(LEAD, null)

    expect(pagina.items.map((a) => a.id)).toEqual([filaAct(0).id])
    expect(console.error).toHaveBeenCalledWith(
      '[ac-crm]',
      expect.objectContaining({
        evento: 'crm.actividades.lead_filas_invalidas',
        datos: expect.objectContaining({ contexto: expect.objectContaining({ descartadas: 2, pagina: 3 }) }),
      }),
    )
  })

  it('42501 es la denegación explícita de la puerta, con su propio mensaje', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json(
      { code: '42501', message: 'Lead fuera de tu cartera', details: null, hint: null },
      { status: 403 },
    )))

    await expect(listarActividadesDeLead(LEAD, null)).rejects.toMatchObject({
      code: '42501',
      message: 'Este lead ya no está en tu cartera.',
    })
  })

  it('un payload sin señales o con versión desconocida no se acepta como historial', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({ version: 2, items: [] })))

    await expect(listarActividadesDeLead(LEAD, null)).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })
})

describe('listarTareasDelAmbito — tareas pendientes por cursor keyset (msw)', () => {
  const RUTA = 'http://supabase.test/rest/v1/rpc/tareas_pendientes_fn'
  const POSTVENTA = 'http://supabase.test/rest/v1/rpc/postventa_agenda_fn'
  const LEAD = '44444444-4444-4444-8444-444444444444'
  const filaTarea = (i: number, sobre: Record<string, unknown> = {}) => ({
    id: `66666666-0000-4000-8000-${String(i).padStart(12, '0')}`,
    lead_id: LEAD, perfil_id: null, vendedor_id: null, asignado_supervisor_id: null,
    tipo: 'llamada', titulo: `Tarea ${i}`, nota: null,
    // Empates de vencimiento a propósito: el desempate por id es parte del cursor.
    vence_en: new Date(Date.parse('2027-01-01T15:00:00Z') + Math.floor(i / 3) * 60_000).toISOString(),
    duracion_min: null, estado: 'pendiente', modalidad_reunion: null, ubicacion_reunion: null,
    enlace_reunion: null, resultado_reunion: null, motivo_no_realizada: null, detalle_cierre_reunion: null,
    confirmada_en: null, reagendada_de: null, reprogramaciones: 0, activo: true,
    creado_en: '2026-09-19T15:00:00+00:00', lead_nombre: 'CLIENTE DE PRUEBA', lead_etapa: 'contactado',
    ...sobre,
  })
  /** Servidor de ensayo: pagina `total` tareas por cursor como lo hace crm.tareas_pendientes_fn. */
  const servidorPaginado = (total: number, cuerpos: Record<string, unknown>[] = []) => {
    const todas = Array.from({ length: total }, (_, i) => filaTarea(i))
    return http.post(RUTA, async ({ request }) => {
      const cuerpo = await request.json() as { p_limite: number; p_despues_de?: string; p_despues_id?: string }
      cuerpos.push(cuerpo)
      const desde = cuerpo.p_despues_de
        ? todas.findIndex((t) => t.vence_en === cuerpo.p_despues_de && t.id === cuerpo.p_despues_id) + 1
        : 0
      return HttpResponse.json({ version: 1, items: todas.slice(desde, desde + cuerpo.p_limite) })
    })
  }
  beforeEach(() => {
    server.use(http.post(POSTVENTA, () => HttpResponse.json([])))
  })

  it('recorre los lotes con el cursor de la última fila cruda y devuelve el ámbito COMPLETO, sin tope', async () => {
    const total = 2 * TAMANO_LOTE_TAREAS + 200
    const cuerpos: Record<string, unknown>[] = []
    server.use(servidorPaginado(total, cuerpos))

    const tareas = await listarTareasDelAmbito()

    expect(tareas.map((t) => t.id)).toEqual(Array.from({ length: total }, (_, i) => filaTarea(i).id))
    const borde1 = filaTarea(TAMANO_LOTE_TAREAS - 1)
    const borde2 = filaTarea(2 * TAMANO_LOTE_TAREAS - 1)
    expect(cuerpos).toEqual([
      { p_limite: TAMANO_LOTE_TAREAS + 1 },
      { p_limite: TAMANO_LOTE_TAREAS + 1, p_despues_de: borde1.vence_en, p_despues_id: borde1.id },
      { p_limite: TAMANO_LOTE_TAREAS + 1, p_despues_de: borde2.vence_en, p_despues_id: borde2.id },
    ])
    expect(tareas[0]).toMatchObject({ lead_nombre: 'CLIENTE DE PRUEBA', lead_etapa: 'contactado' })
    expect(console.error).not.toHaveBeenCalledWith('[ac-crm]', expect.objectContaining({ evento: 'crm_api.tope_alcanzado' }))
  })

  it('justo un lote sin la fila de más termina en una sola petición', async () => {
    const cuerpos: Record<string, unknown>[] = []
    server.use(servidorPaginado(TAMANO_LOTE_TAREAS, cuerpos))

    await expect(listarTareasDelAmbito()).resolves.toHaveLength(TAMANO_LOTE_TAREAS)
    expect(cuerpos).toHaveLength(1)
  })

  it('una tarea repetida entre lotes (los lotes no son una transacción) cuenta una sola vez', async () => {
    let llamada = 0
    server.use(http.post(RUTA, () => {
      llamada += 1
      const items = llamada === 1
        ? Array.from({ length: TAMANO_LOTE_TAREAS + 1 }, (_, i) => filaTarea(i))
        : [filaTarea(TAMANO_LOTE_TAREAS - 1), ...Array.from({ length: 10 }, (_, i) => filaTarea(TAMANO_LOTE_TAREAS + i))]
      return HttpResponse.json({ version: 1, items })
    }))

    const tareas = await listarTareasDelAmbito()

    expect(tareas).toHaveLength(TAMANO_LOTE_TAREAS + 10)
    expect(new Set(tareas.map((t) => t.id)).size).toBe(tareas.length)
  })

  it('la alarma de tendencia suena a 20 000 sin cortar la lectura (20 001 filas llegan enteras)', async () => {
    server.use(servidorPaginado(20_001))

    const tareas = await listarTareasDelAmbito()

    expect(tareas).toHaveLength(20_001)
    expect(console.error).toHaveBeenCalledWith('[ac-crm]', expect.objectContaining({
      evento: 'crm_api.tope_alcanzado',
      datos: expect.objectContaining({ contexto: expect.objectContaining({ lectura: 'tareas_del_ambito_tendencia', tope: 20_000 }) }),
    }))
  })

  it('un servidor que ignora el cursor se corta con ROW_CONTRACT en vez de girar para siempre', async () => {
    const pagina = Array.from({ length: TAMANO_LOTE_TAREAS + 1 }, (_, i) => filaTarea(i))
    server.use(http.post(RUTA, () => HttpResponse.json({ version: 1, items: pagina })))

    await expect(listarTareasDelAmbito()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('un servidor que cicla (A→B→A) se corta: el cursor debe avanzar en sentido estricto', async () => {
    const lote = (desde: number) => Array.from({ length: TAMANO_LOTE_TAREAS + 1 }, (_, i) => filaTarea(desde + i))
    let llamada = 0
    server.use(http.post(RUTA, () => {
      llamada += 1
      return HttpResponse.json({ version: 1, items: llamada % 2 === 1 ? lote(0) : lote(2 * TAMANO_LOTE_TAREAS) })
    }))

    await expect(listarTareasDelAmbito()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
    expect(llamada).toBe(3)
  })

  it('un servidor que retrocede se corta aunque la página sea distinta de la anterior', async () => {
    const lote = (desde: number) => Array.from({ length: TAMANO_LOTE_TAREAS + 1 }, (_, i) => filaTarea(desde + i))
    let llamada = 0
    server.use(http.post(RUTA, () => {
      llamada += 1
      return HttpResponse.json({ version: 1, items: llamada === 1 ? lote(TAMANO_LOTE_TAREAS) : lote(0) })
    }))

    await expect(listarTareasDelAmbito()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
    expect(llamada).toBe(2)
  })

  it('ordena cronológicamente aunque la precisión de los segundos varíe entre filas y rutas', async () => {
    const entero = filaTarea(0, { vence_en: '2027-01-01T15:00:00+00:00' })
    const milesima = filaTarea(1, { vence_en: '2027-01-01T15:00:00.001+00:00' })
    const persona = '33333333-3333-4333-8333-333333333333'
    const neutral = filaTarea(2, {
      vence_en: '2027-01-01T15:00:00.5+00:00', lead_id: null, perfil_id: null,
      inversionista_id: persona, inversionista_canonico_id: persona, postventa_revision: 1,
      postventa_perfil_ids: ['99999999-9999-4999-8999-999999999999'],
    })
    server.use(
      http.post(RUTA, () => HttpResponse.json({ version: 1, items: [milesima, entero] })),
      http.post(POSTVENTA, () => HttpResponse.json([neutral])),
    )

    const tareas = await listarTareasDelAmbito()

    // `localeCompare` habría puesto «.001» delante de «+00:00»; el orden de
    // unidades de código es el cronológico.
    expect(tareas.map((t) => t.id)).toEqual([entero.id, milesima.id, neutral.id])
  })

  it('una fila fuera de contrato se descarta CONTADA y el cursor sigue saliendo de la fila cruda', async () => {
    const cuerpos: Record<string, unknown>[] = []
    let llamada = 0
    server.use(http.post(RUTA, async ({ request }) => {
      cuerpos.push(await request.json() as Record<string, unknown>)
      llamada += 1
      const items = llamada === 1
        ? Array.from({ length: TAMANO_LOTE_TAREAS + 1 }, (_, i) => filaTarea(i, i === TAMANO_LOTE_TAREAS - 1 ? { tipo: 'tipo_futuro' } : {}))
        : [filaTarea(TAMANO_LOTE_TAREAS)]
      return HttpResponse.json({ version: 1, items })
    }))

    const tareas = await listarTareasDelAmbito()

    // 501 crudas en dos lotes, una fuera de contrato: la última fila cruda de
    // la ventana (la inválida) sigue siendo el cursor y la lectura continúa.
    const invalida = filaTarea(TAMANO_LOTE_TAREAS - 1)
    expect(cuerpos[1]).toEqual({ p_limite: TAMANO_LOTE_TAREAS + 1, p_despues_de: invalida.vence_en, p_despues_id: invalida.id })
    expect(tareas).toHaveLength(TAMANO_LOTE_TAREAS)
    expect(console.error).toHaveBeenCalledWith('[ac-crm]', expect.objectContaining({
      evento: 'crm.tareas.filas_invalidas',
      datos: expect.objectContaining({ contexto: expect.objectContaining({ descartadas: 1 }) }),
    }))
  })

  it('un payload con versión desconocida no se acepta como agenda', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json({ version: 2, items: [] })))

    await expect(listarTareasDelAmbito()).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('un rechazo de la puerta viaja con su código', async () => {
    server.use(http.post(RUTA, () => HttpResponse.json(
      { code: '42501', message: 'No autorizado', details: null, hint: null },
      { status: 403 },
    )))

    await expect(listarTareasDelAmbito()).rejects.toMatchObject({ code: '42501', message: 'No se pudo cargar la agenda.' })
  })
})

describe('agenda mixta con postventa instalada (msw)', () => {
  const perfil = '99999999-9999-4999-8999-999999999999'
  const persona = '33333333-3333-4333-8333-333333333333'
  const base = {
    id: '11111111-1111-4111-8111-111111111111', lead_id: null, perfil_id: perfil,
    vendedor_id: null, asignado_supervisor_id: null, tipo: 'llamada', titulo: 'Seguimiento', nota: null,
    vence_en: '2027-01-05T15:00:00.000Z', duracion_min: null, estado: 'pendiente',
    modalidad_reunion: null, ubicacion_reunion: null, enlace_reunion: null, resultado_reunion: null,
    motivo_no_realizada: null, detalle_cierre_reunion: null, confirmada_en: null, reagendada_de: null,
    reprogramaciones: 0, activo: true, creado_en: '2026-09-10T15:00:00.000Z',
  }
  it('combina las dos rutas, conserva el enlace del perfil y ordena por vencimiento', async () => {
    const neutral = {...base, id: '22222222-2222-4222-8222-222222222222', perfil_id: null,
      inversionista_id: persona, inversionista_canonico_id: persona, postventa_revision: 1,
      postventa_perfil_ids: [perfil], vence_en: '2027-01-04T15:00:00.000Z'}
    server.use(http.post('http://supabase.test/rest/v1/rpc/tareas_pendientes_fn', () => HttpResponse.json({ version: 1, items: [base] })),
      http.post('http://supabase.test/rest/v1/rpc/postventa_agenda_fn', () => HttpResponse.json([neutral])))
    await expect(listarTareasDelAmbito()).resolves.toEqual([neutral, base])
  })
  it('una transición apagada devuelve íntegra la agenda anterior', async () => {
    server.use(http.post('http://supabase.test/rest/v1/rpc/tareas_pendientes_fn', () => HttpResponse.json({ version: 1, items: [base] })),
      http.post('http://supabase.test/rest/v1/rpc/postventa_agenda_fn', () => HttpResponse.json([])))
    await expect(listarTareasDelAmbito()).resolves.toEqual([base])
  })
  it.each(['42501', '40001', 'PGRST123'])('no oculta una respuesta fallida %s como agenda completa', async code => {
    server.use(http.post('http://supabase.test/rest/v1/rpc/tareas_pendientes_fn', () => HttpResponse.json({ version: 1, items: [base] })),
      http.post('http://supabase.test/rest/v1/rpc/postventa_agenda_fn', () => HttpResponse.json({code, message: 'Fallo de ensayo'}, {status: 500})))
    await expect(listarTareasDelAmbito()).rejects.toMatchObject({code})
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

describe('buscarLeadsGlobal (msw) — Fase 4a «sin topes»', () => {
  const RUTA_PAGINA = 'http://supabase.test/rest/v1/rpc/cartera_pagina_fn'
  const filaCartera = (sobre: Record<string, unknown> = {}) => fila({ ultimo_contacto_en: null, ...sobre })

  it('pide al servidor el texto normalizado con el tope del desplegable y mapea las filas', async () => {
    let cuerpo: Record<string, unknown> | null = null
    server.use(
      http.post(RUTA_PAGINA, async ({ request }) => {
        cuerpo = (await request.json()) as Record<string, unknown>
        return HttpResponse.json([
          filaCartera({ id: 'l-b-1', nombre_completo: 'Juana Prueba', monto_estimado: '2500.00' }),
          filaCartera({ id: 'l-b-2', nombre_completo: 'Juan Pérez', etapa: 'contactado' }),
        ])
      }),
    )
    const filas = await buscarLeadsGlobal('  jua ')
    expect(cuerpo).toEqual({ p_limite: TAMANO_BUSQUEDA_GLOBAL, p_texto: 'jua' })
    expect(filas.map((l) => [l.id, l.nombre_completo, l.monto_estimado])).toEqual([
      ['l-b-1', 'Juana Prueba', 2500],
      ['l-b-2', 'Juan Pérez', 1000],
    ])
  })

  it('por debajo del mínimo no hay petición y el resultado es vacío', async () => {
    let llamadas = 0
    server.use(http.post(RUTA_PAGINA, () => { llamadas += 1; return HttpResponse.json([]) }))
    await expect(buscarLeadsGlobal('j')).resolves.toEqual([])
    expect(llamadas).toBe(0)
  })

  it('descarta las filas fuera de contrato y conserva las válidas', async () => {
    server.use(http.post(RUTA_PAGINA, () => HttpResponse.json([
      filaCartera({ id: 'l-b-1' }),
      { id: 'rota', nombre_completo: 42 },
    ])))
    const filas = await buscarLeadsGlobal('prueba')
    expect(filas.map((l) => l.id)).toEqual(['l-b-1'])
  })

  it('más filas de las pedidas o ids repetidos → ROW_CONTRACT', async () => {
    server.use(http.post(RUTA_PAGINA, () => HttpResponse.json(
      Array.from({ length: TAMANO_BUSQUEDA_GLOBAL + 1 }, (_, i) => filaCartera({ id: `l-b-${i}` })),
    )))
    await expect(buscarLeadsGlobal('prueba')).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
    server.use(http.post(RUTA_PAGINA, () => HttpResponse.json([filaCartera({ id: 'l-b-1' }), filaCartera({ id: 'l-b-1' })])))
    await expect(buscarLeadsGlobal('prueba')).rejects.toMatchObject({ code: 'ROW_CONTRACT' })
  })

  it('42501 se explica como cuenta sin acceso, no como avería', async () => {
    server.use(http.post(RUTA_PAGINA, () => HttpResponse.json(
      { code: '42501', message: 'No autorizado', details: null, hint: null }, { status: 403 },
    )))
    await expect(buscarLeadsGlobal('prueba')).rejects.toMatchObject({
      code: '42501', message: 'Tu cuenta no tiene acceso a la cartera del CRM.',
    })
  })
})
