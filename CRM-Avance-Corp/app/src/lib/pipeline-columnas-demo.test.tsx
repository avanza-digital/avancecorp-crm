// «Gestionado» en modo demo, con el STORE DEMO DE VERDAD (01/10/2026).
//
// `pipeline-columnas.test.ts` prueba la regla con timelines escritos a mano.
// Aquí el timeline lo escribe el store: registrar un intento, reasignar,
// descartar y reabrir. Es lo que ata el espejo a la forma REAL en que el demo
// deja esos hechos — si el store cambiara cómo anota una reasignación o una
// reapertura, la regla dejaría de verlas y esta prueba es la que lo canta.
import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, waitFor } from '@testing-library/react'
import { AuthContext, type AuthContextValue } from './auth-context'
import { DEMO_YO } from './auth-demo'
import { agruparPorColumna, columnaDeLead } from './pipeline-columnas'
import type { Rol } from './roles'
import type { StoreDataApi } from './store'
import { useCRMData } from './store-context'

vi.stubEnv('VITE_ENABLE_DEMO', 'true')
const { StoreProvider } = await import('./store')

function sesionDemo(rol: Rol): AuthContextValue {
  return {
    fase: 'listo',
    yo: { ...DEMO_YO[rol], rol, demo: true, puede_contratar: true },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

async function montarStore(rol: Rol) {
  const ref: { actual: StoreDataApi | null } = { actual: null }
  function Sonda(): null {
    ref.actual = useCRMData()
    return null
  }
  render(
    <AuthContext.Provider value={sesionDemo(rol)}>
      <StoreProvider>
        <Sonda />
      </StoreProvider>
    </AuthContext.Provider>,
  )
  const api = (): StoreDataApi => {
    if (!ref.actual) throw new Error('StoreProvider aún no montado')
    return ref.actual
  }
  await waitFor(() => expect(api().leads).toHaveLength(20))
  /**
   * Una mutación, y un instante después: el store fecha cada actividad con el
   * reloj, y dos hechos en el mismo milisegundo no tienen orden. Una persona
   * nunca registra un intento y reasigna el lead en el mismo milisegundo.
   */
  async function mutar<T>(fn: (a: StoreDataApi) => T): Promise<T> {
    let resultado!: T
    act(() => { resultado = fn(api()) })
    await act(async () => { await new Promise((listo) => setTimeout(listo, 5)) })
    return resultado
  }
  /** La columna del tablero en la que el Pipeline pintaría ese lead ahora mismo. */
  const columna = (id: string) => {
    const lead = api().ambito.leads.find((l) => l.id === id)
    return lead ? columnaDeLead(lead, api().actividadesDelAmbito) : null
  }
  return { api, mutar, columna }
}

describe('columna «Gestionado» sobre el store demo', () => {
  beforeEach(() => window.sessionStorage.clear())
  afterAll(() => vi.unstubAllEnvs())

  it('el fixture ya trae un lead gestionado y deja «Nuevo» lo que nadie ha intentado', async () => {
    const { api, columna } = await montarStore('gerencia')

    // JUAN (l1) tiene una llamada sin respuesta de hoy; su nota no cuenta.
    expect(columna('l1')).toBe('gestionado')
    // TERESA (l15) y OMAR (l18) no tienen ninguna gestión.
    expect(columna('l15')).toBe('nuevo')
    expect(columna('l18')).toBe('nuevo')
    // Los parkeados (sin analista) son «Nuevo» por definición.
    expect(columna('l5')).toBe('nuevo')
    expect(columna('l11')).toBe('nuevo')

    const tablero = agruparPorColumna(api().ambito.leads, api().actividadesDelAmbito)
    expect(tablero.gestionado.map((l) => l.id)).toEqual(['l1'])
    expect(tablero.nuevo.map((l) => l.id).sort()).toEqual(['l11', 'l15', 'l18', 'l5'])
    // Cada lead abierto cae en una sola columna; los cerrados, en ninguna.
    const repartidos = Object.values(tablero).flat()
    expect(new Set(repartidos.map((l) => l.id)).size).toBe(repartidos.length)
    expect(repartidos.every((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado')).toBe(true)
  })

  it.each(['llamada_no_contestada', 'whatsapp_enviado'] as const)(
    'registrar un intento (%s) pasa el lead a «Gestionado» sin cambiarle la etapa',
    async (tipo) => {
      const { api, mutar, columna } = await montarStore('vendedor')
      expect(columna('l15')).toBe('nuevo')

      expect(await mutar((a) => a.registrarActividad('l15', tipo))).toMatchObject({ ok: true })

      expect(api().lead('l15')?.etapa).toBe('nuevo')
      expect(columna('l15')).toBe('gestionado')
    },
  )

  it('una nota no mueve el lead de «Nuevo»', async () => {
    const { mutar, columna } = await montarStore('vendedor')

    expect(await mutar((a) => a.registrarActividad('l15', 'nota', 'Llamar mañana'))).toMatchObject({ ok: true })

    expect(columna('l15')).toBe('nuevo')
  })

  it('una conversación lo saca de las dos: pasa a «Contactado»', async () => {
    const { mutar, columna } = await montarStore('vendedor')

    expect(await mutar((a) => a.registrarActividad('l15', 'llamada_realizada', 'Contestó'))).toMatchObject({ ok: true, avance: 'contactado' })

    expect(columna('l15')).toBe('contactado')
  })

  it('DECISIÓN DE MIGUEL: al reasignarlo vuelve a «Nuevo» hasta que el analista actual lo intente', async () => {
    const { api, mutar, columna } = await montarStore('gerencia')
    expect(columna('l1')).toBe('gestionado')

    expect(await mutar((a) => a.reasignar('l1', 'd-v2'))).toMatchObject({ ok: true })

    expect(api().lead('l1')).toMatchObject({ etapa: 'nuevo', vendedor_id: 'd-v2' })
    expect(columna('l1')).toBe('nuevo')

    expect(await mutar((a) => a.registrarActividad('l1', 'whatsapp_enviado'))).toMatchObject({ ok: true })
    expect(columna('l1')).toBe('gestionado')
  })

  it('parkearlo (sin analista) lo deja en «Nuevo» aunque tenga intentos', async () => {
    const { mutar, columna } = await montarStore('gerencia')

    expect(await mutar((a) => a.reasignar('l1', null))).toMatchObject({ ok: true })

    expect(columna('l1')).toBe('nuevo')
  })

  it('reabrir un descartado reinicia la tenencia: lo intentado antes del descarte no cuenta', async () => {
    const { api, mutar, columna } = await montarStore('vendedor')
    expect(await mutar((a) => a.registrarActividad('l15', 'llamada_no_contestada'))).toMatchObject({ ok: true })
    expect(columna('l15')).toBe('gestionado')

    expect(await mutar((a) => a.descartar('l15', 'sin_interes'))).toMatchObject({ ok: true })
    // Cerrado: fuera del tablero.
    expect(columna('l15')).toBeNull()

    expect(await mutar((a) => a.reabrir('l15'))).toMatchObject({ ok: true })
    expect(api().lead('l15')?.etapa).toBe('nuevo')
    expect(columna('l15')).toBe('nuevo')

    expect(await mutar((a) => a.registrarActividad('l15', 'whatsapp_enviado'))).toMatchObject({ ok: true })
    expect(columna('l15')).toBe('gestionado')
  })

  // Regla del 01/10: un resultado de llamada DESHECHO «no ocurrió». El store
  // demo lo marca con `metadata.deshecho_en`, la misma clave que mira el servidor.
  it('registrar «no contestó» y DESHACERLO devuelve el lead a «Nuevo»', async () => {
    const { api, mutar, columna } = await montarStore('vendedor')
    expect(columna('l15')).toBe('nuevo')

    const registro = await mutar((a) => a.registrarLlamada('l15', { resultado: 'no_contesto' }))
    expect(registro).toMatchObject({ ok: true })
    expect(columna('l15')).toBe('gestionado')

    const confirmacion = await registro.confirmacion
    expect(confirmacion?.actividad_id).toEqual(expect.any(String))
    expect(await mutar((a) => a.deshacerResultadoLlamada(confirmacion!.actividad_id))).toMatchObject({ ok: true })

    expect(api().lead('l15')?.etapa).toBe('nuevo')
    // La llamada sigue en el timeline (marcada), pero ya no es gestión.
    expect(api().actividadesDe('l15').some((a) => a.tipo === 'llamada_no_contestada' && a.metadata?.deshecho_en != null)).toBe(true)
    expect(columna('l15')).toBe('nuevo')
  })

  it('deshacer una llamada no saca al lead de «Gestionado» si le queda otro intento vivo', async () => {
    const { mutar, columna } = await montarStore('vendedor')
    expect(await mutar((a) => a.registrarActividad('l15', 'whatsapp_enviado'))).toMatchObject({ ok: true })
    const registro = await mutar((a) => a.registrarLlamada('l15', { resultado: 'no_contesto' }))
    const confirmacion = await registro.confirmacion

    expect(await mutar((a) => a.deshacerResultadoLlamada(confirmacion!.actividad_id))).toMatchObject({ ok: true })

    expect(columna('l15')).toBe('gestionado')
  })

  // Punto 3 de la revisión: devolver un lead a «Nuevo» NO lo lleva a la
  // columna «Nuevo» si ya tiene gestión en la tenencia vigente. Es la regla.
  it('devolver a `nuevo` un lead ya contactado lo deja en «Gestionado», no en «Nuevo»', async () => {
    const { api, mutar, columna } = await montarStore('vendedor')
    // MARÍA (l2) está en Contactado, con una llamada y un WhatsApp suyos.
    expect(columna('l2')).toBe('contactado')

    expect(await mutar((a) => a.cambiarEtapa('l2', 'nuevo'))).toMatchObject({ ok: true })

    expect(api().lead('l2')?.etapa).toBe('nuevo')
    expect(columna('l2')).toBe('gestionado')
  })
})
