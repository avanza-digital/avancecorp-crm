// El store en DEMO: registrarLlamada espeja la llamada con su resultado, el
// avance automático, el descarte con motivo real y la tarea siguiente; y el
// deshacer revierte el descarte, cancela la tarea creada y deja la nota.
import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { proximoSlotSugerido } from '@/lib/agenda-derivada'

vi.stubEnv('VITE_ENABLE_DEMO', 'true')
const { StoreProvider } = await import('./store')

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))

const SESION: AuthContextValue = {
  fase: 'listo',
  yo: { id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol: 'vendedor', demo: true, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined, salir: async () => undefined,
}

async function montar() {
  const hook = renderHook(() => useCRMData(), {
    wrapper: ({ children }) => (
      <AuthContext.Provider value={SESION}>
        <StoreProvider>{children}</StoreProvider>
      </AuthContext.Provider>
    ),
  })
  await waitFor(() => expect(hook.result.current.leads.length).toBeGreaterThan(0))
  return hook
}

const manana = () => proximoSlotSugerido(Date.now())

describe('store demo · registrarLlamada / deshacerResultadoLlamada', () => {
  beforeEach(() => window.sessionStorage.clear())
  afterAll(() => vi.unstubAllEnvs())

  it('«volver a llamar» sobre un lead nuevo: llamada con metadata, avance a contactado y tarea siguiente', async () => {
    const { result } = await montar()
    const lead = result.current.ambito.leads.find((l) => l.etapa === 'nuevo' && l.vendedor_id === 'd-v1')
    expect(lead).toBeDefined()
    let res!: ReturnType<typeof result.current.registrarLlamada>
    act(() => {
      res = result.current.registrarLlamada(lead!.id, { resultado: 'volver_a_llamar', siguiente: { tipo: 'llamada', titulo: 'Volver a llamar', vence_en: manana() } })
    })
    expect(res.ok).toBe(true)
    expect(res.avance).toBe('contactado')
    expect(res.descartado).toBe(false)
    const conf = await res.confirmacion!
    expect(conf?.actividad_id).toBeTruthy()
    const act1 = result.current.actividadesDe(lead!.id).find((a) => a.id === conf!.actividad_id)
    expect(act1?.tipo).toBe('llamada_realizada')
    expect(act1?.metadata).toMatchObject({ evento: 'resultado_llamada', resultado: 'volver_a_llamar', descartado: false })
    expect(result.current.lead(lead!.id)?.etapa).toBe('contactado')
    expect(result.current.tareasDe(lead!.id).some((t) => t.id === conf!.siguiente_id && t.tipo === 'llamada')).toBe(true)
  })

  it('«no le interesa» descarta con el motivo real y el deshacer lo devuelve a su etapa', async () => {
    const { result } = await montar()
    const lead = result.current.ambito.leads.find((l) => l.etapa === 'contactado' && l.vendedor_id === 'd-v1')
    expect(lead).toBeDefined()
    let res!: ReturnType<typeof result.current.registrarLlamada>
    act(() => {
      res = result.current.registrarLlamada(lead!.id, { resultado: 'no_interesado', submotivo: 'ya_invirtio_con_otro', descartar: true })
    })
    expect(res.ok).toBe(true)
    expect(res.descartado).toBe(true)
    expect(result.current.lead(lead!.id)).toMatchObject({ etapa: 'descartado', motivo_descarte: 'competencia' })
    expect(result.current.tareasDe(lead!.id)).toHaveLength(0)
    const conf = await res.confirmacion!
    let deshecho!: ReturnType<typeof result.current.deshacerResultadoLlamada>
    act(() => { deshecho = result.current.deshacerResultadoLlamada(conf!.actividad_id) })
    expect(deshecho.ok).toBe(true)
    expect(result.current.lead(lead!.id)).toMatchObject({ etapa: 'contactado', motivo_descarte: null })
    const acts = result.current.actividadesDe(lead!.id)
    expect(acts.find((a) => a.id === conf!.actividad_id)?.metadata?.deshecho_en).toBeTruthy()
    expect(acts.some((a) => a.tipo === 'nota' && a.metadata?.evento === 'resultado_deshecho')).toBe(true)
    act(() => { deshecho = result.current.deshacerResultadoLlamada(conf!.actividad_id) })
    expect(deshecho.ok).toBe(false)
  })

  it.each(['no_interesado', 'pide_otro_producto'] as const)('%s conserva el lead y agenda sin descartar', async (resultado) => {
    const { result } = await montar()
    const lead = result.current.ambito.leads.find((l) => l.etapa === 'nuevo' && l.vendedor_id === 'd-v1')!
    let res!: ReturnType<typeof result.current.registrarLlamada>
    act(() => {
      res = result.current.registrarLlamada(lead.id, { resultado, submotivo: 'otro', siguiente: { tipo: 'whatsapp', titulo: 'Seguimiento acordado', vence_en: manana() } })
    })
    expect(res.ok).toBe(true)
    expect(res.descartado).toBe(false)
    const confirmacion = await res.confirmacion!
    expect(result.current.lead(lead.id)).toMatchObject({ vendedor_id: 'd-v1', etapa: 'contactado' })
    expect(result.current.tareasDe(lead.id).find((t) => t.id === confirmacion?.siguiente_id)).toMatchObject({ tipo: 'whatsapp', titulo: 'Seguimiento acordado' })
    expect(result.current.actividadesDe(lead.id).find((a) => a.id === confirmacion?.actividad_id)?.metadata).toMatchObject({ resultado, submotivo: 'otro', descartado: false })
  })

  it('no admite agenda junto con descarte o No insistir ni tipos incompatibles', async () => {
    const { result } = await montar()
    const lead = result.current.ambito.leads.find((l) => l.etapa === 'nuevo' && l.vendedor_id === 'd-v1')!
    const siguiente = { tipo: 'whatsapp', titulo: 'Seguimiento', vence_en: manana() }
    const antes = result.current.actividadesDe(lead.id).length
    expect(result.current.registrarLlamada(lead.id, { resultado: 'no_interesado', submotivo: 'otro', descartar: true, siguiente }).ok).toBe(false)
    expect(result.current.registrarLlamada(lead.id, { resultado: 'no_interesado', submotivo: 'otro', no_insista: true, siguiente }).ok).toBe(false)
    expect(result.current.registrarLlamada(lead.id, { resultado: 'numero_errado', siguiente }).ok).toBe(false)
    expect(result.current.actividadesDe(lead.id)).toHaveLength(antes)
    expect(result.current.lead(lead.id)?.etapa).toBe('nuevo')
  })

  it('espeja los rechazos del servidor: submotivo obligatorio, dueño sin fecha, descarte indebido', async () => {
    const { result } = await montar()
    const lead = result.current.ambito.leads.find((l) => l.etapa === 'nuevo' && l.vendedor_id === 'd-v1')!
    expect(result.current.registrarLlamada(lead.id, { resultado: 'no_interesado' }).ok).toBe(false)
    expect(result.current.registrarLlamada(lead.id, { resultado: 'volver_a_llamar' }).ok).toBe(false)
    expect(result.current.registrarLlamada(lead.id, { resultado: 'volver_a_llamar', descartar: true, siguiente: { tipo: 'llamada', titulo: 'x', vence_en: manana() } }).ok).toBe(false)
    expect(result.current.registrarLlamada(lead.id, { resultado: 'no_contesto', no_insista: true }).ok).toBe(false)
    expect(result.current.registrarLlamada(lead.id, { resultado: 'no_contesto', submotivo: 'otro' }).ok).toBe(false)
  })
})
