// Suite del ÁMBITO por rol — espejo cliente de la RLS jerárquica (contrato F1c).
// Si esto se rompe, un analista vería leads ajenos: por eso las aserciones son
// contra IDS EXACTOS de los fixtures (lib/demo.ts), no contra conteos sueltos.
// Reparto de los 20 leads demo (ver comentario en demo.ts):
//   d-v1 → l1,l2,l8,l9,l12,l15,l16,l17 · d-v2 → l3,l6,l10,l18,l19 ·
//   d-v3 → l4,l7,l13,l20 · parkeados: l5,l11 → d-sup1 · l14 → d-sup2.
import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, waitFor } from '@testing-library/react'
import { AuthContext, type AuthContextValue } from './auth-context'
import { useCRMData } from './store-context'
import { DEMO_YO } from './auth-demo'
import { ACTIVIDADES_DEMO, LEADS_DEMO } from './demo'
import type { Rol } from './roles'
import type { Yo } from './tipos'
import type { StoreDataApi } from './store'

vi.stubEnv('VITE_ENABLE_DEMO', 'true')
const { StoreProvider } = await import('./store')

// ── Reparto esperado (fuente: lib/demo.ts — si cambia, este test DEBE fallar) ──
const LEADS_V1 = ['l1', 'l2', 'l8', 'l9', 'l12', 'l15', 'l16', 'l17']
const LEADS_V2 = ['l3', 'l6', 'l10', 'l18', 'l19']
const LEADS_V3 = ['l4', 'l7', 'l13', 'l20']
const PARKEADOS_SUP1 = ['l5', 'l11']
const PARKEADOS_SUP2 = ['l14']
const TODOS = [...LEADS_V1, ...LEADS_V2, ...LEADS_V3, ...PARKEADOS_SUP1, ...PARKEADOS_SUP2]

// Actividades de los leads de d-v1 (l15 no tiene, a propósito — señal de cola).
const ACTS_V1 = [
  'act01', // l1
  'act02', 'act03', 'act04', // l2
  'act18', 'act19', 'act20', // l8
  'act21', 'act22', 'act23', // l9
  'act26', 'act27', 'act28', // l12
  'act34', 'act35', // l16
  'act36', 'act37', 'act38', // l17
]

const ordenar = (xs: readonly string[]): string[] => [...xs].sort()
const idsDe = (xs: readonly { id: string }[]): string[] => ordenar(xs.map((x) => x.id))
const vendedoresDe = (xs: readonly { perfil_id: string }[]): string[] =>
  ordenar(xs.map((x) => x.perfil_id))

function sesionCon(yo: Yo | null): AuthContextValue {
  return {
    fase: 'listo',
    yo,
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

const yoDemo = (rol: Rol): Yo => ({ ...DEMO_YO[rol], rol, demo: true, puede_contratar: true })

let apiCapturada: StoreDataApi | null = null

function Sonda() {
  apiCapturada = useCRMData()
  return <output>{apiCapturada.leads.length}</output>
}

/** Monta el store con la sesión dada y espera a que el universo global tenga
 *  `leadsGlobales` leads (20 con fixtures demo, 0 sin sesión demo). */
async function montarStore(yo: Yo | null, leadsGlobales: number): Promise<StoreDataApi> {
  render(
    <AuthContext.Provider value={sesionCon(yo)}>
      <StoreProvider>
        <Sonda />
      </StoreProvider>
    </AuthContext.Provider>,
  )
  await waitFor(() => expect(apiCapturada?.leads).toHaveLength(leadsGlobales))
  const api = apiCapturada
  if (!api) throw new Error('el store no llegó a montar')
  return api
}

/** Siembra sessionStorage con los fixtures pero con l20 soft-borrado
 *  (activo:false) para probar la regla "solo el lector global ve inactivos". */
function sembrarConLeadInactivo(): void {
  const leads = LEADS_DEMO.map((l) => (l.id === 'l20' ? { ...l, activo: false } : l))
  window.sessionStorage.setItem(
    'ac-crm-demo-datos-v2',
    JSON.stringify({ leads, actividades: ACTIVIDADES_DEMO }),
  )
}

describe('ámbito por rol (espejo cliente de la RLS jerárquica)', () => {
  beforeEach(() => {
    window.sessionStorage.clear()
    apiCapturada = null
  })
  afterAll(() => vi.unstubAllEnvs())

  describe('analista (d-v1)', () => {
    it('ve EXACTAMENTE sus 8 leads activos y a nadie más', async () => {
      const { ambito } = await montarStore(yoDemo('vendedor'), 20)

      expect(ambito.leads).toHaveLength(8)
      expect(idsDe(ambito.leads)).toEqual(ordenar(LEADS_V1))
      expect(ambito.esGlobal).toBe(false)
      // Solo él mismo como analista visible/filtrable
      expect(vendedoresDe(ambito.vendedores)).toEqual(['d-v1'])

      // Refuerzo explícito anti-fuga: ni parkeados ni leads de otros analistas
      const visibles = new Set(ambito.leads.map((l) => l.id))
      for (const ajeno of [...PARKEADOS_SUP1, ...PARKEADOS_SUP2, ...LEADS_V2, ...LEADS_V3]) {
        expect(visibles.has(ajeno)).toBe(false)
      }
    })

    it('actividadesDelAmbito trae SOLO el timeline de sus leads (18 de 43)', async () => {
      const api = await montarStore(yoDemo('vendedor'), 20)

      expect(api.actividadesDelAmbito).toHaveLength(18)
      expect(idsDe(api.actividadesDelAmbito)).toEqual(ordenar(ACTS_V1))

      // Ninguna actividad de leads ajenos (l3/l4/l7/l14/l20…)
      const misLeads = new Set(LEADS_V1)
      for (const act of api.actividadesDelAmbito) {
        expect(misLeads.has(act.lead_id)).toBe(true)
      }
    })
  })

  describe('supervisor (d-sup1)', () => {
    it('ve los suyos + d-v1 + d-v2 + parkeados de SU bandeja (15), sin l14 ni nada de d-v3', async () => {
      const { ambito } = await montarStore(yoDemo('supervisor'), 20)

      const esperados = [...LEADS_V1, ...LEADS_V2, ...PARKEADOS_SUP1]
      expect(ambito.leads).toHaveLength(15)
      expect(idsDe(ambito.leads)).toEqual(ordenar(esperados))
      expect(ambito.esGlobal).toBe(false)
      // Sus analistas directos, nada más
      expect(vendedoresDe(ambito.vendedores)).toEqual(['d-v1', 'd-v2'])

      // Anti-fuga: la bandeja de d-sup2 (l14) y el equipo de d-sup2 (d-v3) NO
      const visibles = new Set(ambito.leads.map((l) => l.id))
      for (const ajeno of [...PARKEADOS_SUP2, ...LEADS_V3]) {
        expect(visibles.has(ajeno)).toBe(false)
      }
    })
  })

  describe('gerencia (d-ger)', () => {
    it('ve TODOS los leads activos (20) con ámbito global y los 3 analistas', async () => {
      const { ambito } = await montarStore(yoDemo('gerencia'), 20)

      expect(ambito.leads).toHaveLength(20)
      expect(idsDe(ambito.leads)).toEqual(ordenar(TODOS))
      expect(ambito.esGlobal).toBe(true)
      expect(vendedoresDe(ambito.vendedores)).toEqual(['d-v1', 'd-v2', 'd-v3'])
    })

    it('NO ve leads inactivos (soft-borrados): gerencia no es lector global', async () => {
      sembrarConLeadInactivo() // l20 pasa a activo:false
      const { ambito } = await montarStore(yoDemo('gerencia'), 20)

      expect(ambito.leads).toHaveLength(19)
      expect(idsDe(ambito.leads)).toEqual(ordenar(TODOS.filter((id) => id !== 'l20')))
    })
  })

  describe('directorio (lector global)', () => {
    it('ve TODO con ámbito global, incluidos los 3 analistas', async () => {
      const { ambito } = await montarStore(yoDemo('directorio'), 20)

      expect(ambito.leads).toHaveLength(20)
      expect(idsDe(ambito.leads)).toEqual(ordenar(TODOS))
      expect(ambito.esGlobal).toBe(true)
      expect(vendedoresDe(ambito.vendedores)).toEqual(['d-v1', 'd-v2', 'd-v3'])
    })

    it('ve también los leads inactivos (espejo del lector global de la RLS)', async () => {
      sembrarConLeadInactivo() // l20 pasa a activo:false
      const { ambito } = await montarStore(yoDemo('directorio'), 20)

      expect(ambito.leads).toHaveLength(20)
      const l20 = ambito.leads.find((l) => l.id === 'l20')
      expect(l20).toBeDefined()
      expect(l20?.activo).toBe(false)
    })

    it('actividadesDelAmbito es el timeline completo (las 43)', async () => {
      const api = await montarStore(yoDemo('directorio'), 20)

      expect(api.actividadesDelAmbito).toHaveLength(43)
      expect(idsDe(api.actividadesDelAmbito)).toEqual(idsDe(ACTIVIDADES_DEMO))
    })
  })

  describe('privilegio mínimo (sesión o rol desconocidos)', () => {
    it('sin sesión (yo null) el ámbito queda vacío', async () => {
      const api = await montarStore(null, 0)

      expect(api.ambito.leads).toEqual([])
      expect(api.ambito.vendedores).toEqual([])
      expect(api.ambito.esGlobal).toBe(false)
      expect(api.actividadesDelAmbito).toEqual([])
    })

    it('un rol desconocido degrada a "solo lo propio": con id ajeno no ve NADA', async () => {
      const yoRaro: Yo = {
        id: 'x-fantasma',
        nombre_completo: 'ROL RARO',
        rol: 'auditor' as Rol, // rol fuera del catálogo — simula dato corrupto
        demo: true,
        puede_contratar: true,
      }
      // Los fixtures SÍ cargan (20 en el universo global)…
      const api = await montarStore(yoRaro, 20)

      // …pero el ámbito no le concede ni un lead ni analistas ni globalidad
      expect(api.ambito.leads).toEqual([])
      expect(api.ambito.vendedores).toEqual([])
      expect(api.ambito.esGlobal).toBe(false)
      expect(api.actividadesDelAmbito).toEqual([])
    })
  })
})
