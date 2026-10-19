import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
const mocks = vi.hoisted(() => ({ rpc: vi.fn(), schema: vi.fn(), abortSignal: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: mocks.schema } }))
import {
  cargarCitasClientesProyeccion, citasClientesProyeccionCoherentes, CitasClientesProyeccionSchema,
  type CitasClientesProyeccionRpc,
} from './citas-clientes-proyeccion'

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
