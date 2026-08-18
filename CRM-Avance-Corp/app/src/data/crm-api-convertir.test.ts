import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ConvertirLeadInput } from './crm-api'

const supabase = vi.hoisted(() => ({ invoke: vi.fn() }))

vi.mock('@/lib/supabase', () => ({
  sb: { functions: { invoke: supabase.invoke } },
}))

const { convertirLead } = await import('./crm-api')

const seccionBancariaVacia = {
  banco: '',
  tipo_cuenta: '',
  numero_cuenta: '',
  cci: '',
  titular_distinto: false,
  beneficiario_nombre: '',
  beneficiario_dni: '',
}

const input: ConvertirLeadInput = {
  lead_id: '11111111-1111-4111-8111-111111111111',
  correo: 'cliente@example.com',
  tipo_documento: 'DNI',
  documento: '12345678',
  nombre_completo: 'CLIENTE DE PRUEBA',
  domicilio: 'Av. Prueba 123, Lima',
  bancarios: {
    pen: { ...seccionBancariaVacia },
    usd: { ...seccionBancariaVacia },
  },
}

const respuestaValida = {
  ok: true,
  perfil_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  ya_existia: false,
  domicilio_accion: 'completado',
  email_enviado: true,
}

describe('convertirLead — contrato de respuesta de la Edge', () => {
  beforeEach(() => {
    supabase.invoke.mockReset()
  })

  it('acepta únicamente el contrato exacto y tolera el email_error opcional de la Edge', async () => {
    supabase.invoke.mockResolvedValue({
      data: { ...respuestaValida, email_enviado: false, email_error: 'Resend respondió 503' },
      error: null,
    })

    await expect(convertirLead(input)).resolves.toEqual({
      perfil_id: respuestaValida.perfil_id,
      ya_existia: false,
      domicilio_accion: 'completado',
      email_enviado: false,
    })
    expect(supabase.invoke).toHaveBeenCalledWith('crm-convertir-lead', { body: input })
  })

  it.each([
    ['sin ok', (({ ok: _ok, ...resto }) => resto)(respuestaValida)],
    ['ok distinto de true', { ...respuestaValida, ok: 'true' }],
    ['UUID no canónico', { ...respuestaValida, perfil_id: respuestaValida.perfil_id.toUpperCase() }],
    ['ya_existia no booleano', { ...respuestaValida, ya_existia: 0 }],
    ['email_enviado no booleano', { ...respuestaValida, email_enviado: 'false' }],
    ['domicilio_accion desconocida', { ...respuestaValida, domicilio_accion: 'actualizado' }],
    ['clave inesperada', { ...respuestaValida, perfil: respuestaValida.perfil_id }],
  ])('rechaza una respuesta %s sin coercionarla', async (_caso, data) => {
    supabase.invoke.mockResolvedValue({ data, error: null })

    await expect(convertirLead(input)).rejects.toMatchObject({
      name: 'CrmApiError',
      code: 'RESPUESTA_INVALIDA',
    })
  })
})
