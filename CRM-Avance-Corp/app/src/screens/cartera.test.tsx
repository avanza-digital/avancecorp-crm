// Tests de integración de la pantalla "Cartera" (la tabla de LEADS del ámbito).
// Fijan las dos mentiras que cantaba su chip de capital:
//  1) "S/ 0" cuando el capital del asesor está íntegramente en dólares — la
//     cifra grande debe ser la moneda que de verdad tiene volumen (mismo
//     criterio ya aprobado en Pipeline). PEN y USD JAMÁS se suman.
//  2) el capital sumaba leads DESCARTADOS y CONVERTIDOS, es decir dinero que ya
//     no está en juego (y que en el caso del convertido ya vive como contrato
//     en la otra cartera, duplicado).
// Se mockean auth y store (sin red, sin providers): aquí se prueba la pantalla.
// Los asserts se acotan al CHIP (la tabla repite los mismos montos por fila).
import { describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import type { FiltrosCarteraLocal } from '@/lib/cartera-keyset'
import type { Lead } from '@/lib/tipos'

let YO: { id: string; rol: string; demo: boolean } | null = null
let LEADS: Lead[] = []

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: [], esGlobal: false },
    actividadesDelAmbito: [],
  }),
  usePanelesActions: () => ({ abrirLead: vi.fn() }),
}))
// F1: el hook operativo se sustituye por el espejo puro sobre los MISMOS leads
// del mock — los chips se prueban con números derivados de verdad, sin red ni
// QueryClientProvider (el shape es el del RPC, validado en resumen-cartera.test).
vi.mock('@/data/use-resumen-cartera-operativo', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useResumenCarteraOperativo: (leads: Lead[]) => ({
      resumen: resumenCarteraDesdeAmbito(leads, [], Date.now()),
      cargando: false,
      error: null,
      recargar: vi.fn(),
    }),
  }
})

// F2: la TABLA la sirve `crm.cartera_pagina_fn` por cursor. Aquí se sustituye
// por el MISMO espejo puro que usa el modo demo (`lib/cartera-keyset`), que es
// justo lo que garantiza que demo y real filtren y ordenen igual. Sin este
// mock la pantalla exigiría un QueryClientProvider para probar un chip.
vi.mock('@/data/use-cartera-paginada', async () => {
  const { filtrarCarteraLocal, ordenarCarteraLocal } = await import('@/lib/cartera-keyset')
  return {
    useCarteraPaginada: (leads: Lead[], filtros: FiltrosCarteraLocal) => ({
      leads: ordenarCarteraLocal(filtrarCarteraLocal(leads, filtros)),
      hayMas: false,
      cargando: false,
      cargandoMas: false,
      error: null,
      cargarMas: vi.fn(),
      recargar: vi.fn(),
    }),
  }
})

const { Cartera } = await import('./cartera')

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

function montar(leads: Lead[]) {
  YO = { id: 'v-1', rol: 'vendedor', demo: false }
  LEADS = leads
  render(<Cartera />)
}

/** El mini-KPI completo (Card del StatStrip) a partir de su etiqueta. */
function chipDe(label: string): HTMLElement {
  const chip = screen.getByText(label).closest('[data-slot="card"]')
  if (!(chip instanceof HTMLElement)) throw new Error(`Sin chip "${label}"`)
  return chip
}

describe('Cartera · chip de capital', () => {
  it('con la cartera en dólares la cifra principal es USD, no "S/ 0"', () => {
    montar([lead({ monto_estimado: 30000, moneda: 'USD' })])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('US$ 30,000')).toBeInTheDocument()
    expect(within(chip).getByText('USD')).toBeInTheDocument()
    expect(within(chip).queryByText('S/ 0')).not.toBeInTheDocument()
  })

  it('con las dos monedas muestra las dos y NUNCA las suma', () => {
    montar([
      lead({ monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'lead-2', nombre_completo: 'JUAN PEREZ', monto_estimado: 30000, moneda: 'USD' }),
    ])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('S/ 12,000')).toBeInTheDocument()
    expect(within(chip).getByText('PEN · +US$ 30k')).toBeInTheDocument()
    // 42k = la suma prohibida (PEN+USD): no puede existir en el chip.
    expect(within(chip).queryByText(/42/)).not.toBeInTheDocument()
  })

  it('el capital EXCLUYE descartados y convertidos (solo lo que sigue en juego)', () => {
    montar([
      lead({ monto_estimado: 12000 }),
      lead({ id: 'l-desc', nombre_completo: 'LEAD DESCARTADO', etapa: 'descartado', monto_estimado: 50000 }),
      lead({ id: 'l-conv', nombre_completo: 'LEAD CONVERTIDO', etapa: 'convertido', monto_estimado: 80000 }),
    ])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('S/ 12,000')).toBeInTheDocument()
    // 142,000 = el total viejo (los tres sumados): ya no puede aparecer.
    expect(within(chip).queryByText('S/ 142,000')).not.toBeInTheDocument()
    // El chip dice lo que MIDE; "Capital total" prometía todo el capital.
    expect(screen.queryByText('Capital total')).not.toBeInTheDocument()
    // Los conteos siguen contando TODO el ámbito (lo acotado es el capital).
    expect(within(chipDe('Total leads')).getByText('3')).toBeInTheDocument()
    expect(within(chipDe('Activos')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Convertidos')).getByText('1')).toBeInTheDocument()
  })

  it('un lead inactivo (activo=false) tampoco suma capital', () => {
    montar([
      lead({ monto_estimado: 12000 }),
      lead({ id: 'l-off', nombre_completo: 'LEAD INACTIVO', activo: false, monto_estimado: 99000 }),
    ])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('S/ 12,000')).toBeInTheDocument()
    expect(within(chip).queryByText('S/ 111,000')).not.toBeInTheDocument()
  })
})
