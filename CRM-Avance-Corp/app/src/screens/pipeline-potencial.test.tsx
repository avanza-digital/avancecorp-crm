// Pipeline · potencial del lead. El hook de datos se sustituye: se prueba lo
// que el tablero PINTA con la bandera apagada (producción hoy), encendida sin
// marcas y con marcas; y que la tarjeta Estrella no estorba al arrastre.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { EtapaActiva, Lead } from '@/lib/tipos'
import type { PotencialLead } from '@/lib/potencial'

let LEADS: Lead[] = []
let DEMO = false
let POTENCIAL: { habilitada: boolean; porLead: Map<string, PotencialLead> } = { habilitada: false, porLead: new Map() }
const PEDIDOS: string[][] = []
const abrirLead = vi.fn()
const cambiarEtapa = vi.fn((id: string, etapa: EtapaActiva) => {
  LEADS = LEADS.map((l) => (l.id === id ? { ...l, etapa } : l))
  return { ok: true }
})

vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'v-1', rol: 'vendedor', demo: DEMO } }) }))
vi.mock('@/data/use-cartera-paginada', () => ({
  // La etapa `nuevo` se pide en dos mitades («Nuevo» y «Gestionado»); estos
  // leads no tienen gestión, así que la mitad `con_gestion` va vacía. Sin esto
  // cada lead `nuevo` saldría en las dos columnas.
  useCarteraPaginada: (_foto: readonly Lead[], f: { etapa?: string; gestion?: string }) => {
    const todos = LEADS.filter((l) => l.activo && f.gestion !== 'con_gestion'
      && (!f.etapa || f.etapa === 'todas' || l.etapa === f.etapa))
    return {
      leads: todos, resumen: { totales: { vivos: todos.length } }, hayMas: false,
      cargando: false, cargandoMas: false, error: null, cargarMas: vi.fn(), recargar: vi.fn(),
    }
  },
}))
vi.mock('@/data/crm-queries', () => ({
  useLeadsSinAsignar: () => ({ data: [], isPending: false, isFetching: false, error: null, refetch: vi.fn() }),
}))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({ indice: new Map(), cargando: false, error: null, recargar: vi.fn() }),
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    conocerLeads: () => {}, asegurarLead: async () => true,
    ambito: { leads: LEADS, vendedores: [], esGlobal: false }, actividadesDelAmbito: [], cambiarEtapa,
  }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead: vi.fn() }),
}))
vi.mock('@/data/use-resumen-cartera-operativo', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useResumenCarteraOperativo: (leads: Lead[]) => ({
      resumen: resumenCarteraDesdeAmbito(leads, [], Date.now()), cargando: false, error: null, recargar: vi.fn(),
    }),
  }
})
vi.mock('@/data/potencial-queries', () => ({
  usePotencialLeads: (ids: readonly string[]) => { PEDIDOS.push([...ids]); return POTENCIAL },
}))

const { Pipeline } = await import('./pipeline')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1', nombre_completo: 'ROSA QUISPE', telefono: '999888777', etapa: 'nuevo', origen: 'landing',
    monto_estimado: 12000, moneda: 'PEN', vendedor_id: 'v-1', vendedor_nombre: 'ANA TORRES',
    creado_en: new Date().toISOString(), activo: true, ...over,
  }
}
function marca(leadId: string, nivel: PotencialLead['nivel']): PotencialLead {
  return {
    lead_id: leadId, nivel, origen: nivel ? 'manual' : null, nivel_marcado: nivel, marcado_en: nivel ? '2026-09-29T15:00:00Z' : null,
    dias_sin_gestion: nivel ? 1 : null, baja_a: null, baja_el: null, puede_marcar: true,
  }
}
function cardDe(nombre: string): HTMLElement {
  const card = screen.getByText(nombre).closest('[role="button"]')
  if (!(card instanceof HTMLElement)) throw new Error(`Sin card para ${nombre}`)
  return card
}
function transferencia() {
  const datos = new Map<string, string>()
  return {
    setData: (tipo: string, valor: string) => void datos.set(tipo, valor),
    getData: (tipo: string) => datos.get(tipo) ?? '',
    effectAllowed: 'none', dropEffect: 'none',
  }
}

beforeEach(() => {
  PEDIDOS.length = 0
  DEMO = false
  abrirLead.mockReset()
  cambiarEtapa.mockClear()
  LEADS = [
    lead({ id: 'l-estrella', nombre_completo: 'GLORIA NAVARRO', etapa: 'propuesta_enviada' }),
    lead({ id: 'l-tibio', nombre_completo: 'MARIA LOPEZ', etapa: 'contactado' }),
    lead({ id: 'l-nada', nombre_completo: 'ROSA QUISPE' }),
  ]
})

describe('Pipeline · potencial del lead', () => {
  it('ESTADO DE PRODUCCIÓN (potencial apagado): las tarjetas se ven igual que antes', () => {
    POTENCIAL = { habilitada: false, porLead: new Map() }
    render(<Pipeline />)
    expect(cardDe('GLORIA NAVARRO')).toBeInTheDocument()
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(document.querySelector('[data-potencial]')).toBeNull()
  })

  it('ESTADO DE PRODUCCIÓN (encendido, ningún lead marcado): sin chips ni franjas', () => {
    POTENCIAL = { habilitada: true, porLead: new Map(LEADS.map((l) => [l.id, marca(l.id, null)])) }
    render(<Pipeline />)
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(document.querySelector('[data-potencial]')).toBeNull()
  })

  it('con marcas: chip pequeño en la tarjeta y franja del nivel', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([
      ['l-estrella', marca('l-estrella', 'estrella')], ['l-tibio', marca('l-tibio', 'tibio')], ['l-nada', marca('l-nada', null)],
    ]) }
    render(<Pipeline />)
    const estrella = cardDe('GLORIA NAVARRO')
    expect(within(estrella).getByTitle('Potencial: Estrella')).toHaveClass('pot-chip--pequeno')
    expect(estrella).toHaveAttribute('data-potencial', 'estrella')
    expect(cardDe('MARIA LOPEZ')).toHaveAttribute('data-potencial', 'tibio')
    expect(within(cardDe('MARIA LOPEZ')).getByTitle('Potencial: Tibio')).toBeInTheDocument()
    expect(cardDe('ROSA QUISPE')).not.toHaveAttribute('data-potencial')
    // La franja y el dorado cuelgan de la tarjeta de la casa (data-slot="card").
    expect(estrella).toHaveAttribute('data-slot', 'card')
  })

  it('pregunta por las tarjetas del tablero (sesión real) o por el ámbito (demo)', () => {
    POTENCIAL = { habilitada: false, porLead: new Map() }
    const { unmount } = render(<Pipeline />)
    expect(new Set(PEDIDOS.at(-1))).toEqual(new Set(['l-estrella', 'l-tibio', 'l-nada']))
    unmount()
    DEMO = true
    LEADS = [...LEADS, lead({ id: 'l-cerrado', nombre_completo: 'LEAD CERRADO', etapa: 'convertido' })]
    render(<Pipeline />)
    expect(new Set(PEDIDOS.at(-1))).toEqual(new Set(['l-estrella', 'l-tibio', 'l-nada', 'l-cerrado']))
  })

  it('la tarjeta Estrella se queda quieta mientras se arrastra y el arrastre sigue funcionando', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([['l-estrella', marca('l-estrella', 'estrella')]]) }
    render(<Pipeline />)
    expect(cardDe('GLORIA NAVARRO')).not.toHaveAttribute('data-pot-quieta')
    const dt = transferencia()
    fireEvent.dragStart(cardDe('GLORIA NAVARRO'), { dataTransfer: dt })
    expect(cardDe('GLORIA NAVARRO')).toHaveAttribute('data-pot-quieta')
    expect(cardDe('GLORIA NAVARRO')).toHaveAttribute('data-potencial', 'estrella')
    const zona = screen.getByText('Contactado').parentElement?.nextElementSibling as HTMLElement
    fireEvent.dragOver(zona, { dataTransfer: dt })
    fireEvent.drop(zona, { dataTransfer: dt })
    expect(cambiarEtapa).toHaveBeenCalledWith('l-estrella', 'contactado')
  })

  it('el clic en una tarjeta con marca sigue abriendo la ficha', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([['l-estrella', marca('l-estrella', 'estrella')]]) }
    render(<Pipeline />)
    fireEvent.pointerDown(cardDe('GLORIA NAVARRO'))
    fireEvent.pointerUp(cardDe('GLORIA NAVARRO'))
    fireEvent.click(cardDe('GLORIA NAVARRO'))
    expect(abrirLead).toHaveBeenCalledWith('l-estrella')
  })
})
