import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
const mocks = vi.hoisted(() => ({ rpc: vi.fn(), schema: vi.fn(), abortSignal: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: mocks.schema } }))
import {
  adaptarCitasClientesProyeccion, cargarCitasClientesProyeccion, citasClientesProyeccionCoherentes, CitasClientesProyeccionSchema,
  esRangoDemasiadoGrande, opcionesCitasClientesProyeccion, type CitasClientesProyeccionRpc,
} from './citas-clientes-proyeccion'
import { CrmApiError } from './crm-api'
import { crmQueryKeys } from './crm-queries'

// Payload EJECUTADO en el banco Docker (19/10/2026) por crm.citas_clientes_proyeccion_fn como el
// vendedor sintético V1, F6 encendida: datos inventados. Incluye perfil visible, persona F6
// visible, persona de otra cartera redactada, un perfil enlazado a la persona y el borde 1/10 00:00 Lima.
const PAYLOAD_BANCO = {
  "citas": [
    {
      "id": "00000000-0000-0000-0000-0000000000f4",
      "estado": "pendiente",
      "vence_en": "2026-10-02T10:00:00-05:00",
      "creado_en": "2026-10-01T00:00:00-05:00",
      "perfil_id": "00000000-0000-0000-0000-0000000000c3",
      "sujeto_id": "00000000-0000-0000-0000-0000000000c3",
      "analista_id": "00000000-0000-0000-0000-0000000000e3",
      "sujeto_tipo": "perfil",
      "cancelada_por": null,
      "sujeto_nombre": "CLIENTE PERFIL TRES",
      "supervisor_id": "00000000-0000-0000-0000-0000000000e2",
      "analista_nombre": "VENDEDOR UNO",
      "inversionista_id": null,
      "identidad_persona": "perfil:00000000-0000-0000-0000-0000000000c3",
      "identidad_visible": true,
      "supervisor_nombre": "SUPERVISOR UNO",
      "asistencia_registrada_en": null
    },
    {
      "id": "00000000-0000-0000-0000-0000000000d1",
      "estado": "completada",
      "vence_en": "2026-10-07T10:00:00-05:00",
      "creado_en": "2026-10-05T10:00:00-05:00",
      "perfil_id": "00000000-0000-0000-0000-0000000000c3",
      "sujeto_id": "00000000-0000-0000-0000-0000000000c3",
      "analista_id": "00000000-0000-0000-0000-0000000000e3",
      "sujeto_tipo": "perfil",
      "cancelada_por": null,
      "sujeto_nombre": "CLIENTE PERFIL TRES",
      "supervisor_id": "00000000-0000-0000-0000-0000000000e2",
      "analista_nombre": "VENDEDOR UNO",
      "inversionista_id": null,
      "identidad_persona": "perfil:00000000-0000-0000-0000-0000000000c3",
      "identidad_visible": true,
      "supervisor_nombre": "SUPERVISOR UNO",
      "asistencia_registrada_en": "2026-10-07T11:00:00-05:00"
    },
    {
      "id": "00000000-0000-0000-0000-0000000000d2",
      "estado": "completada",
      "vence_en": "2026-11-05T10:00:00-05:00",
      "creado_en": "2026-10-10T10:00:00-05:00",
      "perfil_id": null,
      "sujeto_id": "00000000-0000-0000-0000-0000000000a1",
      "analista_id": "00000000-0000-0000-0000-0000000000e3",
      "sujeto_tipo": "inversionista",
      "cancelada_por": null,
      "sujeto_nombre": "CLIENTE PERSONA UNO",
      "supervisor_id": "00000000-0000-0000-0000-0000000000e2",
      "analista_nombre": "VENDEDOR UNO",
      "inversionista_id": "00000000-0000-0000-0000-0000000000a1",
      "identidad_persona": "persona:00000000-0000-0000-0000-0000000000a1",
      "identidad_visible": true,
      "supervisor_nombre": "SUPERVISOR UNO",
      "asistencia_registrada_en": "2026-10-11T12:00:00-05:00"
    },
    {
      "id": "00000000-0000-0000-0000-0000000000d4",
      "estado": "no_show",
      "vence_en": "2026-10-14T10:00:00-05:00",
      "creado_en": "2026-10-12T10:00:00-05:00",
      "perfil_id": null,
      "sujeto_id": null,
      "analista_id": "00000000-0000-0000-0000-0000000000e3",
      "sujeto_tipo": "inversionista",
      "cancelada_por": null,
      "sujeto_nombre": "Cliente fuera de tu cartera",
      "supervisor_id": "00000000-0000-0000-0000-0000000000e2",
      "analista_nombre": "VENDEDOR UNO",
      "inversionista_id": null,
      "identidad_persona": "oculta:00000000-0000-0000-0000-0000000000d4",
      "identidad_visible": false,
      "supervisor_nombre": "SUPERVISOR UNO",
      "asistencia_registrada_en": null
    },
    {
      "id": "00000000-0000-0000-0000-0000000000dc",
      "estado": "pendiente",
      "vence_en": "2026-10-18T10:00:00-05:00",
      "creado_en": "2026-10-17T10:00:00-05:00",
      "perfil_id": "00000000-0000-0000-0000-0000000000c1",
      "sujeto_id": "00000000-0000-0000-0000-0000000000c1",
      "analista_id": "00000000-0000-0000-0000-0000000000e3",
      "sujeto_tipo": "perfil",
      "cancelada_por": null,
      "sujeto_nombre": "CLIENTE PERSONA UNO",
      "supervisor_id": "00000000-0000-0000-0000-0000000000e2",
      "analista_nombre": "VENDEDOR UNO",
      "inversionista_id": "00000000-0000-0000-0000-0000000000a1",
      "identidad_persona": "persona:00000000-0000-0000-0000-0000000000a1",
      "identidad_visible": true,
      "supervisor_nombre": "SUPERVISOR UNO",
      "asistencia_registrada_en": null
    }
  ],
  "periodo": {
    "desde": "2026-10-01",
    "hasta": "2026-10-31"
  },
  "version": 1,
  "criterio": "creado_en",
  "generado_en": "2026-10-19T22:31:30.402561+00:00"
} as const

const copia = (): CitasClientesProyeccionRpc => structuredClone(PAYLOAD_BANCO) as unknown as CitasClientesProyeccionRpc
const responder = (data: unknown, error: unknown = null) => mocks.rpc.mockImplementation(() => ({
  then: (resolver: (r: unknown) => unknown) => Promise.resolve({ data, error }).then(resolver),
  abortSignal: (s: AbortSignal) => { mocks.abortSignal(s); return Promise.resolve({ data, error }) },
}))

beforeEach(() => {
  vi.clearAllMocks()
  mocks.schema.mockReturnValue({ rpc: mocks.rpc })
  responder(copia())
})

describe('esquema de la proyección de reuniones con clientes (Fase 0b)', () => {
  it('acepta el payload ejecutado en SQL y conserva sus cinco reuniones', () => {
    const r = v.safeParse(CitasClientesProyeccionSchema, copia())
    expect(r.success).toBe(true)
    expect(r.success && r.output.citas.map(c => c.id.slice(-2))).toEqual(['f4', 'd1', 'd2', 'd4', 'dc'])
    expect(r.success && citasClientesProyeccionCoherentes(r.output, '2026-10-01', '2026-10-31')).toBe(true)
  })

  it('la persona de otra cartera llega redactada y con clave oculta propia de la cita', () => {
    const d4 = copia().citas.find(c => c.id.endsWith('d4'))!
    expect(d4).toMatchObject({ identidad_visible: false, sujeto_id: null, inversionista_id: null, perfil_id: null,
      sujeto_nombre: 'Cliente fuera de tu cartera', identidad_persona: `oculta:${d4.id}` })
  })

  it.each([
    ['nombra a la persona aunque la identidad esté redactada', (d: CitasClientesProyeccionRpc) => {
      d.citas.find(c => c.id.endsWith('d4'))!.identidad_persona = 'persona:00000000-0000-0000-0000-0000000000a2' }],
    ['la clave de persona no sale de la identidad visible', (d: CitasClientesProyeccionRpc) => {
      d.citas.find(c => c.id.endsWith('d2'))!.identidad_persona = 'persona:00000000-0000-0000-0000-0000000000a9' }],
    ['identidad redactada que conserva el id del cliente', (d: CitasClientesProyeccionRpc) => {
      d.citas.find(c => c.id.endsWith('d4'))!.inversionista_id = '00000000-0000-0000-0000-0000000000a2' }],
    ['asistencia en una reunión que no se completó', (d: CitasClientesProyeccionRpc) => {
      d.citas.find(c => c.id.endsWith('d4'))!.asistencia_registrada_en = '2026-10-14T16:00:00Z' }],
    ['estado desconocido', (d: CitasClientesProyeccionRpc) => {
      (d.citas[0] as { estado: string }).estado = 'vencida' }],
    ['otro criterio de fecha', (d: CitasClientesProyeccionRpc) => { (d as { criterio: string }).criterio = 'vence_en' }],
    ['otra versión', (d: CitasClientesProyeccionRpc) => { (d as { version: number }).version = 2 }],
  ])('rechaza el payload: %s', (_caso, romper) => {
    const d = copia(); romper(d)
    expect(v.safeParse(CitasClientesProyeccionSchema, d).success).toBe(false)
  })

  it('la coherencia exige el mismo período, ids únicos y creación dentro del rango en día de Lima', () => {
    const d = copia()
    expect(citasClientesProyeccionCoherentes(d, '2026-10-01', '2026-10-30')).toBe(false)
    // f4 nació el 1/10 a las 00:00 de Lima (05:00 UTC): para Lima es octubre, no septiembre.
    expect(citasClientesProyeccionCoherentes({ ...d, periodo: { desde: '2026-10-02', hasta: '2026-10-31' } }, '2026-10-02', '2026-10-31')).toBe(false)
    expect(citasClientesProyeccionCoherentes({ ...d, citas: [...d.citas, d.citas[0]!] }, '2026-10-01', '2026-10-31')).toBe(false)
    expect(citasClientesProyeccionCoherentes({ ...d, generado_en: '2026-10-05T00:00:00Z' }, '2026-10-01', '2026-10-31')).toBe(false)
  })
})

describe('carga de la proyección de reuniones con clientes', () => {
  it('llama a la puerta del esquema crm con el rango y propaga la cancelación', async () => {
    const control = new AbortController()
    const r = await cargarCitasClientesProyeccion('2026-10-01', '2026-10-31', control.signal)
    expect(mocks.schema).toHaveBeenCalledWith('crm')
    expect(mocks.rpc).toHaveBeenCalledWith('citas_clientes_proyeccion_fn', { p_desde: '2026-10-01', p_hasta: '2026-10-31' })
    expect(mocks.abortSignal).toHaveBeenCalledWith(control.signal)
    expect(r.citas).toHaveLength(5)
  })

  it('no consulta con un rango inválido', async () => {
    await expect(cargarCitasClientesProyeccion('2026-10-31', '2026-10-01')).rejects.toMatchObject({ code: 'CITAS_PERIODO' })
    await expect(cargarCitasClientesProyeccion('octubre', '2026-10-31')).rejects.toMatchObject({ code: 'CITAS_PERIODO' })
    expect(mocks.rpc).not.toHaveBeenCalled()
  })

  it('un servidor sin la puerta (PGRST202) da un mensaje propio, y los demás errores conservan su código', async () => {
    responder(null, { code: 'PGRST202', message: 'not found' })
    await expect(cargarCitasClientesProyeccion('2026-10-01', '2026-10-31')).rejects.toMatchObject({ code: 'PGRST202', message: expect.stringContaining('aún no están habilitadas') })
    responder(null, { code: '42501', message: 'No autorizado para consultar gestiones' })
    await expect(cargarCitasClientesProyeccion('2026-10-01', '2026-10-31')).rejects.toMatchObject({ code: '42501' })
  })

  it('rechaza un payload que no corresponde al rango pedido', async () => {
    await expect(cargarCitasClientesProyeccion('2026-09-01', '2026-09-30')).rejects.toMatchObject({ code: 'CITAS_CONTRATO' })
  })
})

describe('reuniones con clientes como citas de la Proyección', () => {
  it('cada reunión es una cita sin lead, monto ni moneda, con la persona del servidor y el estado de Citas', () => {
    const reuniones = adaptarCitasClientesProyeccion(copia())
    expect(reuniones.map(r => [r.id.slice(-2), r.estado, r.persona.split(':')[0], r.nombre])).toEqual([
      // Pendientes con fecha anterior al corte: «vencida», como en Citas.
      ['f4', 'vencida', 'perfil', 'CLIENTE PERFIL TRES'], ['d1', 'realizada', 'perfil', 'CLIENTE PERFIL TRES'],
      ['d2', 'realizada', 'persona', 'CLIENTE PERSONA UNO'], ['d4', 'no_show', 'oculta', 'Cliente fuera de tu cartera'],
      ['dc', 'vencida', 'persona', 'CLIENTE PERSONA UNO'],
    ])
    const d1 = reuniones.find(r => r.id.endsWith('d1'))!
    expect(d1).toEqual({
      id: '00000000-0000-0000-0000-0000000000d1', leadId: null, moneda: null, monto: null,
      persona: 'perfil:00000000-0000-0000-0000-0000000000c3', nombre: 'CLIENTE PERFIL TRES',
      analista: '00000000-0000-0000-0000-0000000000e3', analistaNombre: 'VENDEDOR UNO',
      supervisor: 'SUPERVISOR UNO', supervisorId: '00000000-0000-0000-0000-0000000000e2',
      fecha: '2026-10-07', hora: '10:00', estado: 'realizada', creadoEn: '2026-10-05T10:00:00-05:00',
      asistioEn: '2026-10-07T11:00:00-05:00',
    })
    // La persona redactada conserva su clave propia y el texto del servidor, sin datos personales.
    expect(reuniones.find(r => r.id.endsWith('d4'))).toMatchObject({ persona: 'oculta:00000000-0000-0000-0000-0000000000d4', nombre: 'Cliente fuera de tu cartera' })
    expect(reuniones.find(r => r.id.endsWith('d4'))).not.toHaveProperty('asistioEn')
  })

  it('mapea todos los estados y los responsables vacíos igual que Citas', () => {
    const d = copia()
    const [f4, d1, d2, d4, dc] = d.citas
    Object.assign(f4!, { vence_en: '2026-10-25T10:00:00-05:00' })
    Object.assign(d1!, { estado: 'cancelada', cancelada_por: 'asesor', asistencia_registrada_en: null })
    Object.assign(d2!, { estado: 'cancelada', cancelada_por: 'sistema', asistencia_registrada_en: null })
    Object.assign(d4!, { estado: 'reprogramada', analista_id: null, analista_nombre: 'Sin analista', supervisor_id: null, supervisor_nombre: 'Sin supervisor' })
    Object.assign(dc!, { estado: 'no_show' })
    const reuniones = adaptarCitasClientesProyeccion(d)
    expect(reuniones.map(r => r.estado)).toEqual(['programada', 'cancelada', 'sistema', 'reprogramada', 'no_show'])
    expect(reuniones[3]).toMatchObject({ analista: 'sin_analista', analistaNombre: 'Sin analista', supervisor: 'Sin supervisor', supervisorId: 'sin_supervisor' })
  })

  it('un rango demasiado grande (54000 o 57014) da un mensaje claro y no se reintenta solo', async () => {
    for (const code of ['54000', '57014']) {
      responder(null, { code, message: 'canceling statement due to statement timeout' })
      const error = await cargarCitasClientesProyeccion('2026-10-01', '2026-10-31').catch((e: unknown) => e)
      expect(error).toMatchObject({ code, message: 'El rango es demasiado grande. Acorta las fechas.' })
      expect(esRangoDemasiadoGrande(error)).toBe(true)
    }
    expect(esRangoDemasiadoGrande(new CrmApiError('No autorizado', '42501'))).toBe(false)
    const { retry, refetchInterval } = opcionesCitasClientesProyeccion({ desde: '2026-10-01', hasta: '2026-10-31' }, 'actor', true)
    expect(refetchInterval({ state: { error: new CrmApiError('x', '57014') } })).toBe(false)
    expect(refetchInterval({ state: { error: null } })).toBe(60_000)
    expect(retry(0, new CrmApiError('x', '54000'))).toBe(false)
    expect(retry(0, new CrmApiError('x', '57014'))).toBe(false)
    expect(retry(0, new CrmApiError('x', '08006'))).toBe(true)
    expect(retry(1, new CrmApiError('x', '08006'))).toBe(false)
    // Codex (19/10): tampoco se vuelve a pedir solo al recuperar el foco ni la conexión.
    const { refetchOnWindowFocus, refetchOnReconnect } = opcionesCitasClientesProyeccion({ desde: '2026-10-01', hasta: '2026-10-31' }, 'actor', true)
    for (const refrescar of [refetchOnWindowFocus, refetchOnReconnect]) {
      expect(refrescar({ state: { error: new CrmApiError('x', '57014') } })).toBe(false)
      expect(refrescar({ state: { error: new CrmApiError('x', '54000') } })).toBe(false)
      expect(refrescar({ state: { error: new CrmApiError('x', '08006') } })).toBe(true)
      expect(refrescar({ state: { error: null } })).toBe(true)
    }
  })

  it('una consulta por rango y actor, bajo el detalle de Citas; sin rango, sin actor o en demostración no consulta', async () => {
    const rango = { desde: '2026-10-01', hasta: '2026-10-19' }
    const opciones = opcionesCitasClientesProyeccion(rango, 'actor', true)
    expect(opciones.queryKey).toEqual([...crmQueryKeys.citasGerenciaPrefijo(), 'clientes-proyeccion', 'actor', '2026-10-01', '2026-10-19'])
    // Foco y conexión refrescan salvo con un rango demasiado grande (ver el caso de 54000/57014).
    expect(opciones).toMatchObject({ enabled: true, staleTime: 30_000, refetchIntervalInBackground: false })
    expect([opciones.refetchOnWindowFocus({ state: { error: null } }), opciones.refetchOnReconnect({ state: { error: null } })]).toEqual([true, true])
    expect(opcionesCitasClientesProyeccion(null, 'actor', true).enabled).toBe(false)
    expect(opcionesCitasClientesProyeccion(rango, null, true).enabled).toBe(false)
    expect(opcionesCitasClientesProyeccion(rango, 'actor', false).enabled).toBe(false)
    responder({ ...copia(), periodo: { desde: '2026-10-01', hasta: '2026-10-19' } })
    await expect(opciones.queryFn({ signal: new AbortController().signal })).resolves.toMatchObject({ periodo: rango })
    expect(mocks.rpc).toHaveBeenCalledWith('citas_clientes_proyeccion_fn', { p_desde: '2026-10-01', p_hasta: '2026-10-19' })
  })
})
