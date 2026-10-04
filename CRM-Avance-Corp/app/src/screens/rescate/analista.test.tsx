// La base del analista con contactos de BASES CARGADAS (F6): la columna «Base» y el selector «Base: Todas · Feria 2025
// (40)» junto al del Mes. Primero el ESTADO DE PRODUCCIÓN: antes de la B10 el servidor no manda `base_nombre` y la hoja
// queda exactamente como hoy (ni columna ni selector).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { FilaBaseGestion } from '@/lib/base-gestion'

let FILAS: FilaBaseGestion[] = []
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'v1', rol: 'vendedor', demo: false } }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ leads: [] }) }))
vi.mock('@/data/crm-queries', () => ({
  useBaseGestion: () => ({ data: FILAS, isPending: false, isError: false, isFetching: false, refetch: vi.fn() }),
}))
vi.mock('@/components/base-gestion/ficha-base', () => ({ FichaBase: () => null }))
vi.mock('@/lib/media', () => ({ useEsMovil: () => false, usePuedeMarcar: () => false }))

const { BaseGestionAnalista } = await import('./analista')

function fila(n: number, sobre: Partial<FilaBaseGestion> = {}): FilaBaseGestion {
  return {
    lead_id: `lead-${n}`, nombre_completo: `LEAD ${n}`, telefono: '+51987654321', distrito: null, origen: 'landing', categoria_interes: null,
    monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde', descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7,
    etapa_maxima: 'contactado', intentos: 1, ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
    rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: 'v1', gestiona: 'ANA', recibido_en: '2026-08-15T15:00:00Z', ...sobre,
  }
}
const encabezados = () => within(screen.getByRole('region', { name: 'Tu base para gestión' })).getAllByRole('columnheader').map((c) => c.textContent)

beforeEach(() => { FILAS = [] })
afterEach(() => vi.clearAllMocks())

describe('F6 · Base en la hoja del analista', () => {
  it('ESTADO DE PRODUCCIÓN (sin `base_nombre`): ni columna «Base» ni selector', () => {
    FILAS = [fila(1), fila(2)]
    render(<BaseGestionAnalista />)
    expect(encabezados()).not.toContain('Base')
    expect(screen.queryByRole('combobox', { name: 'Base' })).toBeNull()
    expect(screen.getByRole('combobox', { name: 'Mes' })).toBeInTheDocument()
  })

  it('con contactos de base: columna junto al Mes y selector «Base: Todas · Feria 2025 (2)» que filtra la hoja', async () => {
    const FERIA = { base_id: 'b-feria', base_nombre: 'Feria 2025', origen: 'base_cargada', motivo_descarte: 'base_cargada', monto_estimado: null }
    FILAS = [fila(1), fila(2, FERIA), fila(3, FERIA)]
    render(<BaseGestionAnalista />)
    expect(encabezados().slice(0, 4)).toEqual(['#', 'Lead', 'Mes', 'Base'])
    const selector = screen.getByRole('combobox', { name: 'Base' })
    expect(within(selector).getAllByRole('option').map((o) => o.textContent)).toEqual(['Todas (3)', 'Feria 2025 (2)', 'Sin base (1)'])
    await userEvent.selectOptions(selector, 'b-feria')
    const hoja = screen.getByRole('region', { name: 'Tu base para gestión' })
    expect(within(hoja).getAllByRole('rowheader').map((r) => r.textContent)).toEqual(['LEAD 2', 'LEAD 3'])
    expect(screen.getByText('De Feria 2025')).toBeInTheDocument()
    expect(within(hoja).getAllByText('Feria 2025')).toHaveLength(2)
  })
})
