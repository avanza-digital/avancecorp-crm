// Tests de integración del tablero (Pipeline) — la pantalla de trabajo del
// analista. Fijan dos regresiones que se pagan caras:
//  1) tras arrastrar una card a otra columna el tablero se quedaba MUDO: al
//     cambiar de etapa React desmonta la card de la columna vieja, su
//     `onDragEnd` no llega a correr y el guard del click fantasma se quedaba
//     pegado en true — ningún click volvía a abrir una ficha. Por eso el test
//     NO dispara `dragEnd`: reproduce lo que pasa de verdad, no el caso cómodo.
//  2) el chip de capital cantaba "S/ 0" cuando la cartera está en dólares.
// Se mockean auth y store (sin red, sin providers): aquí se prueba la pantalla.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import type { EtapaActiva, Lead, Miembro } from '@/lib/tipos'

const abrirLead = vi.fn()
const abrirNuevoLead = vi.fn()

let YO: { id: string; rol: string; demo: boolean } | null = null
let LEADS: Lead[] = []
let VENDEDORES: Miembro[] = []
let CIERRES_MES: number | null = null

// Espejo mínimo de `cambiarEtapa`: mueve el lead de columna como haría el store
// real, que es lo que provoca el desmontaje de la card en el drop.
const cambiarEtapa = vi.fn((id: string, etapa: EtapaActiva) => {
  LEADS = LEADS.map((l) => (l.id === id ? { ...l, etapa } : l))
  return { ok: true }
})

vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({
    indice: new Map(),
    cargando: false,
    error: null,
    recargar: vi.fn(),
  }),
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: VENDEDORES, esGlobal: YO?.rol === 'gerencia' },
    actividadesDelAmbito: [],
    cambiarEtapa,
  }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead }),
}))
// F1: el hook operativo se sustituye por el espejo puro sobre los MISMOS leads
// del mock — los chips se prueban con números derivados de verdad, sin red ni
// QueryClientProvider (el shape es el del RPC, validado en resumen-cartera.test).
vi.mock('@/data/use-resumen-cartera-operativo', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useResumenCarteraOperativo: (leads: Lead[]) => ({
      resumen: (() => {
        const resumen = resumenCarteraDesdeAmbito(leads, [], Date.now())
        if (CIERRES_MES != null) resumen.totales.convertidos = CIERRES_MES
        return resumen
      })(),
      cargando: false,
      error: null,
      recargar: vi.fn(),
    }),
  }
})

const { Pipeline } = await import('./pipeline')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    telefono: '999888777',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 12000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    vendedor_nombre: 'ANA TORRES',
    creado_en: new Date().toISOString(),
    activo: true,
    ...over,
  }
}

function montar(leads: Lead[] = [lead()]) {
  YO = { id: 'v-1', rol: 'vendedor', demo: false }
  LEADS = leads
  render(<Pipeline />)
}

/** La card clicable del lead (el kanban la expone como role=button). */
function cardDe(nombre: string): HTMLElement {
  const card = screen.getByText(nombre).closest('[role="button"]')
  if (!(card instanceof HTMLElement)) throw new Error(`Sin card para ${nombre}`)
  return card
}

/** Zona de drop de una columna: el hermano de su cabecera (es un contenedor de
 *  cards, no un control — no tiene rol propio al que agarrarse). */
function zonaDe(columna: string): HTMLElement {
  const zona = screen.getByText(columna).parentElement?.nextElementSibling
  if (!(zona instanceof HTMLElement)) throw new Error(`Sin zona de drop en ${columna}`)
  return zona
}

/** DataTransfer de mentira: jsdom no lo implementa. */
function transferencia() {
  const datos = new Map<string, string>()
  return {
    setData: (tipo: string, valor: string) => void datos.set(tipo, valor),
    getData: (tipo: string) => datos.get(tipo) ?? '',
    effectAllowed: 'none',
    dropEffect: 'none',
  }
}

beforeEach(() => {
  VENDEDORES = []
  CIERRES_MES = null
  abrirLead.mockReset()
  abrirNuevoLead.mockReset()
  cambiarEtapa.mockReset().mockImplementation((id: string, etapa: EtapaActiva) => {
    LEADS = LEADS.map((l) => (l.id === id ? { ...l, etapa } : l))
    return { ok: true }
  })
})

describe('Pipeline · alcance y período de los indicadores', () => {
  it('conserva los cierres mensuales servidos y los totales globales al filtrar columnas', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    VENDEDORES = [
      { perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', activo: true, supervisor_id: null },
      { perfil_id: 'v-2', nombre_completo: 'LUIS LOPEZ', rol_crm: 'vendedor', activo: true, supervisor_id: null },
    ]
    LEADS = [lead(), lead({ id: 'l-2', nombre_completo: 'LEAD LUIS', vendedor_id: 'v-2', vendedor_nombre: 'LUIS LOPEZ' })]
    CIERRES_MES = 8
    render(<Pipeline />)
    const abiertos = screen.getByText('Leads abiertos con analista').closest('[data-slot="card"]') as HTMLElement
    const cierres = screen.getAllByText('Cierres de leads del mes')[0]!.closest('[data-slot="card"]') as HTMLElement

    expect(within(abiertos).getByText('2')).toBeInTheDocument()
    expect(within(cierres).getByText('8')).toBeInTheDocument()
    expect(screen.getByText(/Indicadores de toda la empresa/)).toHaveTextContent('Los filtros sólo cambian las columnas')
    fireEvent.click(screen.getByRole('button', { name: 'ANA' }))

    expect(screen.queryByText('LEAD LUIS')).not.toBeInTheDocument()
    expect(within(abiertos).getByText('2')).toBeInTheDocument()
    expect(within(cierres).getByText('8')).toBeInTheDocument()
    expect(screen.getByText('Mes calendario actual')).toBeInTheDocument()
  })
})

describe('tablero Pipeline · arrastrar y seguir trabajando', () => {
  it('tras soltar una card en otra columna el tablero SIGUE abriendo fichas', async () => {
    montar()
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragOver(zonaDe('Contactado'), { dataTransfer: dt })
    // Sin `dragEnd` a propósito: la card se desmonta al cambiar de columna, así
    // que en el navegador ese evento tampoco llega nunca.
    fireEvent.drop(zonaDe('Contactado'), { dataTransfer: dt })

    expect(cambiarEtapa).toHaveBeenCalledWith('lead-1', 'contactado')
    expect(zonaDe('Contactado')).toContainElement(cardDe('ROSA QUISPE'))
    // Sin card fantasma: el atenuado del arrastre se limpia con el drop.
    expect(cardDe('ROSA QUISPE').className).not.toContain('opacity-40')

    // El click sintético pegado al drop se sigue ignorando (para eso existe el
    // guard: soltar una card no debe abrir su ficha).
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).not.toHaveBeenCalled()

    // Pasada esa ventana el tablero responde otra vez, sin `dragEnd` que valga.
    await act(async () => {
      await new Promise((listo) => setTimeout(listo, 120))
    })
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('un arrastre abortado (dragEnd sin drop) tampoco deja el tablero mudo', async () => {
    montar()
    const dt = transferencia()

    fireEvent.dragStart(cardDe('ROSA QUISPE'), { dataTransfer: dt })
    fireEvent.dragEnd(cardDe('ROSA QUISPE'), { dataTransfer: dt })

    await act(async () => {
      await new Promise((listo) => setTimeout(listo, 120))
    })
    fireEvent.click(cardDe('ROSA QUISPE'))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
    expect(cambiarEtapa).not.toHaveBeenCalled()
  })
})

describe('tablero Pipeline · chip de capital', () => {
  it('con la cartera en dólares la cifra principal es USD, no "S/ 0"', () => {
    montar([lead({ monto_estimado: 30000, moneda: 'USD' })])

    expect(screen.getByText('US$ 30,000')).toBeInTheDocument()
    expect(screen.getByText('USD')).toBeInTheDocument()
    expect(screen.queryByText('S/ 0')).not.toBeInTheDocument()
  })

  it('con las dos monedas muestra las dos y NUNCA las suma', () => {
    montar([
      lead({ monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'lead-2', nombre_completo: 'JUAN PEREZ', monto_estimado: 30000, moneda: 'USD' }),
    ])

    expect(screen.getByText('S/ 12,000')).toBeInTheDocument()
    expect(screen.getByText('PEN · +US$ 30k')).toBeInTheDocument()
    // 42k = la suma prohibida (PEN+USD): no puede existir en ninguna moneda.
    expect(screen.queryByText(/42/)).not.toBeInTheDocument()
  })
})

describe('tablero Pipeline · bandeja compacta', () => {
  it('pagina una etapa sin acumular todas las cards en la columna', () => {
    montar(
      Array.from({ length: 21 }, (_, i) => lead({
        id: `lead-${i + 1}`,
        nombre_completo: `LEAD ${String(i + 1).padStart(2, '0')}`,
      })),
    )

    expect(screen.getByText('1–20 de 21')).toBeInTheDocument()
    expect(cardDe('LEAD 01')).toBeInTheDocument()
    expect(screen.queryByText('LEAD 21')).not.toBeInTheDocument()
    expect(zonaDe('Nuevo').className).toContain('overflow-y-auto')

    fireEvent.click(screen.getByRole('button', { name: 'Ver página siguiente de Nuevo' }))

    expect(screen.getByText('21–21 de 21')).toBeInTheDocument()
    expect(cardDe('LEAD 21')).toBeInTheDocument()
    expect(screen.queryByText('LEAD 01')).not.toBeInTheDocument()
  })
})
