// @vitest-environment node
// Contratos de Configuración contra un Supabase simulado con MSW. Se usa el
// cliente supabase-js real para comprobar ruta, schema, cuerpos e interpretación
// de errores PostgREST sin depender de una base ni de la red.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake') }
})

import {
  actualizarJerarquiaUsuario,
  actualizarUsuarioAdministrable,
  asignarRolUsuario,
  crearCandidatoUsuario,
  fijarMembresiaUsuario,
  listarCatalogoUsuariosAdministrables,
  listarEstadoSlaLeads,
  publicarMetas,
  publicarPoliticaSla,
} from './crm-config-api'
import { CrmApiError } from './crm-api'

const BASE = 'http://supabase.test'
const RPC = (fn: string) => `${BASE}/rest/v1/rpc/${fn}`
const EDGE_USUARIOS = `${BASE}/functions/v1/crm-usuarios`

const PERFIL_ID = '10000000-0000-4000-8000-000000000001'
const SUPERVISOR_ID = '10000000-0000-4000-8000-000000000002'
const IDEMPOTENCIA = '10000000-0000-4000-8000-000000000003'
const VERSION_PERFIL = '2026-08-07T18:00:00.000Z'
const VERSION_EQUIPO = '2026-08-07T18:01:00.000Z'

const server = setupServer()

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
  vi.spyOn(globalThis.crypto, 'randomUUID').mockReturnValue(IDEMPOTENCIA)
})

function filaUsuario(indice: number, total: number | string): Record<string, unknown> {
  return {
    perfil_id: `10000000-0000-4000-8000-${String(indice).padStart(12, '0')}`,
    nombre_completo: `USUARIO ${indice}`,
    tipo_documento: 'DNI',
    documento: String(70_000_000 + indice),
    correo: `usuario${indice}@example.test`,
    telefono: null,
    whatsapp: null,
    cargo: null,
    tipo_cuenta: 'solo_crm',
    estado: 'activo',
    rol_crm: 'vendedor',
    supervisor_id: SUPERVISOR_ID,
    activo_crm: true,
    activo_portal: true,
    version_perfil: VERSION_PERFIL,
    version_equipo: VERSION_EQUIPO,
    total,
  }
}

function estadoSlaValido(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    lead_id: '20000000-0000-4000-8000-000000000001',
    ciclo_politica_id: '20000000-0000-4000-8000-000000000002',
    ciclo_politica_version: '3',
    primera_gestion_limite_en: '2026-08-07T18:30:00.000Z',
    primera_gestion_en: null,
    primer_contacto_limite_en: '2026-08-07T19:00:00.000Z',
    primer_contacto_en: null,
    ciclo_aproximado: false,
    asignacion_id: '20000000-0000-4000-8000-000000000003',
    asignacion_politica_id: '20000000-0000-4000-8000-000000000004',
    asignacion_politica_version: '2',
    asignacion_primera_gestion_limite_en: '2026-08-07T18:40:00.000Z',
    asignacion_primera_gestion_en: null,
    asignacion_primer_contacto_limite_en: '2026-08-07T19:10:00.000Z',
    asignacion_primer_contacto_en: null,
    etapa_politica_id: '20000000-0000-4000-8000-000000000005',
    etapa_politica_version: '4',
    etapa: 'contactado',
    etapa_iniciada_en: '2026-08-07T18:10:00.000Z',
    etapa_limite_en: '2026-08-10T18:10:00.000Z',
    etapa_objetivo_minutos: '4320',
    etapa_aproximada: false,
    ...sobre,
  }
}

function publicacionMetasValida(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: '30000000-0000-4000-8000-000000000001',
    periodo: '2026-08-01',
    revision: '5',
    revision_anterior_id: '30000000-0000-4000-8000-000000000002',
    publicada_por: PERFIL_ID,
    publicada_en: '2026-08-07T18:30:00.000Z',
    ...sobre,
  }
}

function publicacionSlaValida(sobre: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: '40000000-0000-4000-8000-000000000001',
    version: '4',
    version_anterior_id: '40000000-0000-4000-8000-000000000002',
    vigente_desde: '2026-08-07T19:00:00.000Z',
    zona_horaria: 'America/Lima',
    tipo_reloj: 'corrido',
    primera_gestion_minutos: '120',
    primer_contacto_minutos: '1440',
    publicada_por: PERFIL_ID,
    publicada_en: '2026-08-07T18:30:00.000Z',
    ...sobre,
  }
}

const INPUT_SLA = {
  expectedVersion: 3,
  vigenteDesde: '2026-08-07T19:00:00.000Z',
  config: {
    zona_horaria: 'America/Lima' as const,
    tipo_reloj: 'corrido' as const,
    primera_gestion_minutos: 120,
    primer_contacto_minutos: 1_440,
    etapas: [
      { etapa: 'nuevo' as const, maximo_minutos: 1_440 },
      { etapa: 'contactado' as const, maximo_minutos: 4_320 },
      { etapa: 'reunion_agendada' as const, maximo_minutos: 7_200 },
      { etapa: 'propuesta_enviada' as const, maximo_minutos: 10_080 },
    ],
  },
}

describe('listarEstadoSlaLeads: contrato estricto de la fotografía viva', () => {
  it('propaga una cancelación como AbortError sin convertirla en fallo de Configuración', async () => {
    const control = new AbortController()
    control.abort()

    await expect(listarEstadoSlaLeads(control.signal)).rejects.toMatchObject({
      name: 'AbortError',
    })
  })

  it('acepta una fila completa, coerciona enteros RPC y consulta el schema crm', async () => {
    let contentProfile: string | null = null
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('estado_sla_leads_fn'), async ({ request }) => {
        contentProfile = request.headers.get('content-profile')
        cuerpo = await request.json()
        return HttpResponse.json([estadoSlaValido()])
      }),
    )

    const estados = await listarEstadoSlaLeads()

    expect(contentProfile).toBe('crm')
    expect(cuerpo).toEqual({})
    expect(estados).toHaveLength(1)
    expect(estados[0]).toMatchObject({
      ciclo_politica_version: 3,
      asignacion_politica_version: 2,
      etapa_politica_version: 4,
      etapa_objetivo_minutos: 4320,
    })
  })

  it('rechaza dos filas para el mismo lead aunque ambas sean válidas por separado', async () => {
    const fila = estadoSlaValido()
    server.use(
      http.post(RPC('estado_sla_leads_fn'), () =>
        HttpResponse.json([fila, { ...fila, etapa: 'propuesta_enviada' }]),
      ),
    )

    await expect(listarEstadoSlaLeads()).rejects.toMatchObject({
      code: 'CONTRATO_CONFIG_INVALIDO',
    })
  })

  it.each([
    [
      'asignación parcial',
      estadoSlaValido({
        asignacion_id: null,
        asignacion_politica_id: '20000000-0000-4000-8000-000000000004',
      }),
    ],
    [
      'etapa parcial',
      estadoSlaValido({ etapa: null, etapa_politica_id: null }),
    ],
    [
      'clave desconocida',
      estadoSlaValido({ umbral_recalculado_en_cliente: true }),
    ],
  ])('rechaza una fotografía incoherente: %s', async (_caso, fila) => {
    server.use(
      http.post(RPC('estado_sla_leads_fn'), () => HttpResponse.json([fila])),
    )

    const promesa = listarEstadoSlaLeads()

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({
      code: 'CONTRATO_CONFIG_INVALIDO',
      message:
        'El servidor devolvió una respuesta incompatible. Actualiza la aplicación e inténtalo otra vez.',
    })
  })
})

describe('publicaciones versionadas: contrato estricto de confirmación', () => {
  it('acepta y normaliza una única revisión de Metas coherente', async () => {
    server.use(
      http.post(RPC('publicar_metas_vendedores'), () =>
        HttpResponse.json([publicacionMetasValida()]),
      ),
    )

    await expect(publicarMetas({
      periodo: '2026-08-01',
      expectedRevision: 4,
      metas: {},
    })).resolves.toMatchObject({ periodo: '2026-08-01', revision: 5 })
  })

  it.each([
    ['array no unitario', []],
    ['shape con clave desconocida', [publicacionMetasValida({ confirmada: true })]],
    ['revisión distinta a la esperada', [publicacionMetasValida({ revision: 8 })]],
  ])('rechaza confirmación de Metas inválida: %s', async (_caso, respuesta) => {
    server.use(
      http.post(RPC('publicar_metas_vendedores'), () => HttpResponse.json(respuesta)),
    )

    await expect(publicarMetas({
      periodo: '2026-08-01',
      expectedRevision: 4,
      metas: {},
    })).rejects.toMatchObject({ code: 'CONTRATO_CONFIG_INVALIDO' })
  })

  it('acepta y normaliza una única versión SLA coherente', async () => {
    server.use(
      http.post(RPC('publicar_politica_sla'), () =>
        HttpResponse.json([publicacionSlaValida()]),
      ),
    )

    await expect(publicarPoliticaSla(INPUT_SLA)).resolves.toMatchObject({
      version: 4,
      primera_gestion_minutos: 120,
      primer_contacto_minutos: 1_440,
    })
  })

  it.each([
    ['array no unitario', [publicacionSlaValida(), publicacionSlaValida()]],
    ['shape incompleto', [publicacionSlaValida({ publicada_por: null })]],
    ['versión distinta a la esperada', [publicacionSlaValida({ version: 7 })]],
    ['umbrales distintos a los publicados', [publicacionSlaValida({ primera_gestion_minutos: 180 })]],
  ])('rechaza confirmación SLA inválida: %s', async (_caso, respuesta) => {
    server.use(
      http.post(RPC('publicar_politica_sla'), () => HttpResponse.json(respuesta)),
    )

    await expect(publicarPoliticaSla(INPUT_SLA)).rejects.toMatchObject({
      code: 'CONTRATO_CONFIG_INVALIDO',
    })
  })
})

describe('errores PostgREST de Configuración', () => {
  it.each([
    [
      'P0409',
      409,
      'CONFLICTO_CONFIG',
      'La configuración cambió en otra sesión. Recarga antes de continuar.',
    ],
    [
      '40001',
      409,
      'CONFLICTO_CONFIG',
      'La configuración cambió en otra sesión. Recarga antes de continuar.',
    ],
    ['42501', 403, 'SIN_PERMISO', 'No tienes permiso para esa acción.'],
  ])('traduce %s a un código y mensaje estables', async (codigoPg, status, code, message) => {
    server.use(
      http.post(RPC('estado_sla_leads_fn'), () =>
        HttpResponse.json(
          { code: codigoPg, message: 'detalle interno que no debe llegar', details: null, hint: null },
          { status },
        ),
      ),
    )

    const promesa = listarEstadoSlaLeads()

    await expect(promesa).rejects.toBeInstanceOf(CrmApiError)
    await expect(promesa).rejects.toMatchObject({ code, message })
  })
})

describe('listarCatalogoUsuariosAdministrables: paginación completa', () => {
  it('recorre todas las páginas de 100 sin ocultar usuarios de páginas posteriores', async () => {
    const cuerpos: unknown[] = []
    server.use(
      http.post(RPC('usuarios_administrables_fn'), async ({ request }) => {
        const cuerpo = (await request.json()) as { p_desde: number }
        cuerpos.push(cuerpo)
        if (cuerpo.p_desde === 0) {
          return HttpResponse.json([filaUsuario(1, '5'), filaUsuario(2, '5')])
        }
        if (cuerpo.p_desde === 2) {
          return HttpResponse.json([filaUsuario(3, '5'), filaUsuario(4, '5')])
        }
        if (cuerpo.p_desde === 4) return HttpResponse.json([filaUsuario(5, '5')])
        return HttpResponse.json([])
      }),
    )

    const usuarios = await listarCatalogoUsuariosAdministrables()

    expect(usuarios.map((usuario) => usuario.nombre_completo)).toEqual([
      'USUARIO 1',
      'USUARIO 2',
      'USUARIO 3',
      'USUARIO 4',
      'USUARIO 5',
    ])
    expect(usuarios.every((usuario) => usuario.total === 5)).toBe(true)
    expect(cuerpos).toEqual([
      // Sin búsqueda, la clave se OMITE (tipos generados + sinIndefinidos):
      // p_busqueda tiene DEFAULT NULL en el catálogo — ausente ≡ null.
      { p_limite: 100, p_desde: 0 },
      { p_limite: 100, p_desde: 2 },
      { p_limite: 100, p_desde: 4 },
    ])
  })
})

describe('mutaciones de usuario: parámetros e idempotencia exactos', () => {
  it('actualiza el perfil con versión esperada y UUID de idempotencia', async () => {
    let cuerpo: unknown = null
    server.use(
      http.post(RPC('actualizar_usuario_administrable_fn'), async ({ request }) => {
        cuerpo = await request.json()
        return HttpResponse.json({
          perfil_id: PERFIL_ID,
          version_perfil: VERSION_PERFIL,
          idempotente: false,
        })
      }),
    )

    const resultado = await actualizarUsuarioAdministrable({
      perfil_id: PERFIL_ID,
      nombre_completo: 'MIGUEL PRUEBA',
      tipo_documento: 'DNI',
      documento: '70000001',
      telefono: '+51999999999',
      whatsapp: null,
      cargo: 'ANALISTA',
      version_perfil: '2026-08-07T17:00:00.000Z',
    })

    expect(cuerpo).toEqual({
      p_perfil_id: PERFIL_ID,
      p_nombre_completo: 'MIGUEL PRUEBA',
      p_tipo_documento: 'DNI',
      p_documento: '70000001',
      p_telefono: '+51999999999',
      p_whatsapp: null,
      p_cargo: 'ANALISTA',
      p_version_perfil: '2026-08-07T17:00:00.000Z',
      p_idempotencia: IDEMPOTENCIA,
    })
    expect(resultado).toEqual({
      perfil_id: PERFIL_ID,
      version_perfil: VERSION_PERFIL,
      idempotente: false,
    })
  })

  it('envía rol, jerarquía y membresía con sus versiones y reemplazo exactos', async () => {
    const cuerpos = new Map<string, unknown>()
    server.use(
      http.post(RPC('asignar_rol_usuario_fn'), async ({ request }) => {
        cuerpos.set('rol', await request.json())
        return HttpResponse.json({
          perfil_id: PERFIL_ID,
          rol_crm: 'vendedor',
          activo_crm: true,
          version_equipo: VERSION_EQUIPO,
          idempotente: false,
        })
      }),
      http.post(RPC('actualizar_jerarquia_usuario_fn'), async ({ request }) => {
        cuerpos.set('jerarquia', await request.json())
        return HttpResponse.json({
          perfil_id: PERFIL_ID,
          supervisor_id: SUPERVISOR_ID,
          version_equipo: VERSION_EQUIPO,
          idempotente: false,
        })
      }),
      http.post(RPC('fijar_membresia_activa_fn'), async ({ request }) => {
        cuerpos.set('membresia', await request.json())
        return HttpResponse.json({
          perfil_id: PERFIL_ID,
          activo_crm: false,
          version_equipo: VERSION_EQUIPO,
          idempotente: false,
        })
      }),
    )

    await asignarRolUsuario({
      perfilId: PERFIL_ID,
      rol: 'vendedor',
      versionEquipo: VERSION_EQUIPO,
    })
    await actualizarJerarquiaUsuario({
      perfilId: PERFIL_ID,
      supervisorId: SUPERVISOR_ID,
      versionEquipo: VERSION_EQUIPO,
    })
    await fijarMembresiaUsuario({
      perfilId: PERFIL_ID,
      activo: false,
      reemplazoId: SUPERVISOR_ID,
      versionEquipo: VERSION_EQUIPO,
    })

    expect(cuerpos.get('rol')).toEqual({
      p_perfil_id: PERFIL_ID,
      p_rol_crm: 'vendedor',
      p_version_equipo: VERSION_EQUIPO,
      p_idempotencia: IDEMPOTENCIA,
    })
    expect(cuerpos.get('jerarquia')).toEqual({
      p_perfil_id: PERFIL_ID,
      p_supervisor_id: SUPERVISOR_ID,
      p_version_equipo: VERSION_EQUIPO,
      p_idempotencia: IDEMPOTENCIA,
    })
    expect(cuerpos.get('membresia')).toEqual({
      p_perfil_id: PERFIL_ID,
      p_activo: false,
      p_reemplazo_id: SUPERVISOR_ID,
      p_version_equipo: VERSION_EQUIPO,
      p_idempotencia: IDEMPOTENCIA,
    })
  })

  it('usa request_id en el alta Edge y preserva nulls explícitos', async () => {
    const cuerpos: unknown[] = []
    server.use(
      http.post(EDGE_USUARIOS, async ({ request }) => {
        const cuerpo = await request.json()
        cuerpos.push(cuerpo)
        return HttpResponse.json({
          estado: 'activo',
          perfil_id: PERFIL_ID,
        })
      }),
    )

    await crearCandidatoUsuario({
      correo: 'qa@example.test',
      nombre_completo: 'USUARIO QA',
      tipo_documento: 'DNI',
      documento: '70000001',
      supervisor_id: SUPERVISOR_ID,
    })

    expect(cuerpos).toEqual([
      {
        accion: 'crear_candidato',
        request_id: IDEMPOTENCIA,
        correo: 'qa@example.test',
        nombre_completo: 'USUARIO QA',
        tipo_documento: 'DNI',
        documento: '70000001',
        supervisor_id: SUPERVISOR_ID,
        telefono: null,
        whatsapp: null,
        cargo: null,
      },
    ])
  })
})
