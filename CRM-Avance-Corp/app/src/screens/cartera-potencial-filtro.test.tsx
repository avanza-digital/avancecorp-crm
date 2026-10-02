// Tabla de Leads · fila «Por potencial». El hook de datos se sustituye: aquí se
// prueba cuándo existe la fila, qué filtro le pide la pantalla al servidor y
// qué pasa mientras llega la respuesta o cuando el servidor apaga el potencial.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import type { FiltrosCarteraLocal } from '@/lib/cartera-keyset'
import type { Lead } from '@/lib/tipos'
import type { FiltrosCartera, ResumenCarteraFiltrada } from '@/data/crm-api'
import type { ConteosPotencial } from '@/lib/potencial'

/** Lo que devuelve el hook sustituido; cada prueba lo ajusta. */
const mundo = vi.hoisted(() => ({
  conteos: null as ConteosPotencial | null,
  cargando: false,
  error: null as unknown,
  filtros: [] as Array<FiltrosCartera & FiltrosCarteraLocal>,
}))

const LEADS: Lead[] = [
  { id: 'l-1', nombre_completo: 'GLORIA NAVARRO', telefono: '999888771', etapa: 'nuevo', origen: 'landing', monto_estimado: 12000, moneda: 'PEN', vendedor_id: 'v-1', creado_en: '2026-09-30T10:00:00Z', activo: true },
  { id: 'l-2', nombre_completo: 'JUAN PEREZ', telefono: '999888772', etapa: 'contactado', origen: 'landing', monto_estimado: 8000, moneda: 'PEN', vendedor_id: 'v-1', creado_en: '2026-09-29T10:00:00Z', activo: true },
]

vi.mock('sonner', () => ({ toast: { info: vi.fn(), error: vi.fn(), success: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'v-1', rol: 'vendedor', demo: false } }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    conocerLeads: () => {}, asegurarLead: async () => true,
    ambito: { leads: LEADS, vendedores: [{ perfil_id: 'v-1', nombre_completo: 'ANA TORRES' }], esGlobal: false },
    actividadesDelAmbito: [], cierresEstado: [],
  }),
  usePanelesActions: () => ({ abrirLead: vi.fn() }),
}))
vi.mock('@/data/crm-queries', () => ({ useCierresEstado: () => ({ data: [] }) }))
vi.mock('@/components/gerencia/use-consulta-gerencia', () => ({ useConsultaGerencia: () => null }))
vi.mock('@/data/potencial-queries', () => ({ usePotencialLeads: () => ({ habilitada: false, porLead: new Map() }) }))
vi.mock('@/data/use-cartera-paginada', async () => {
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useCarteraPaginada: (leads: Lead[], filtros: FiltrosCartera & FiltrosCarteraLocal) => {
      mundo.filtros.push(filtros)
      const sinResumen = mundo.cargando || mundo.error != null
      const base = resumenCarteraDesdeAmbito(leads, [], Date.now(), false)
      const resumen: ResumenCarteraFiltrada = mundo.conteos
        ? { ...base, potencial: { ...mundo.conteos, filtro: filtros.potencial ?? null } } : base
      return {
        leads: sinResumen ? [] : leads, resumen: sinResumen ? undefined : resumen,
        hayMas: false, cargando: mundo.cargando, cargandoMas: false, error: mundo.error, cargarMas: vi.fn(), recargar: vi.fn(),
      }
    },
  }
})

const { Cartera } = await import('./cartera')
const { CrmApiError } = await import('@/data/crm-api')
const { toast } = await import('sonner')

const CONTEOS: ConteosPotencial = { filtro: null, estrella: 1, tibio: 1, frio: 0, sin_marca: 0 }
const grupo = () => screen.getByRole('group', { name: 'Distribución por potencial' })
const pastilla = (nombre: RegExp) => within(grupo()).getByRole('button', { name: nombre })
const ultimoFiltro = () => mundo.filtros.at(-1)

beforeEach(() => {
  mundo.conteos = null
  mundo.cargando = false
  mundo.error = null
  mundo.filtros.length = 0
  vi.mocked(toast.info).mockClear()
})

describe('Cartera · fila «Por potencial»', () => {
  it('ESTADO con el potencial apagado (el resumen no trae conteos): no hay fila y nada cambia', () => {
    render(<Cartera />)
    expect(screen.queryByRole('group', { name: 'Distribución por potencial' })).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Resumen de la cartera' }))
      .toHaveAccessibleDescription('Los filtros actualizan juntos el listado, los indicadores y la distribución por etapa.')
    expect(ultimoFiltro()).not.toHaveProperty('potencial')
  })

  it('encendido: la fila aparece bajo «Por etapa» con los conteos del servidor', () => {
    mundo.conteos = CONTEOS
    render(<Cartera />)
    expect(within(grupo()).getAllByRole('button').map((b) => b.textContent)).toEqual(['Frío 0', 'Tibio 1', 'Estrella 1', 'Sin marcar 0'])
    expect(screen.getByRole('region', { name: 'Resumen de la cartera' }))
      .toHaveAccessibleDescription('Los filtros actualizan juntos el listado, los indicadores y la distribución por etapa y por potencial.')
    // Sin tocar nada, el filtro no viaja.
    expect(ultimoFiltro()).not.toHaveProperty('potencial')
  })

  it('tocar una pastilla manda el filtro a la consulta; otra lo sustituye; la misma lo quita', () => {
    mundo.conteos = CONTEOS
    render(<Cartera />)
    fireEvent.click(pastilla(/^Tibio 1$/))
    expect(ultimoFiltro()).toMatchObject({ potencial: 'tibio' })
    expect(pastilla(/^Tibio 1$/)).toHaveAttribute('aria-pressed', 'true')
    // Un nivel a la vez.
    fireEvent.click(pastilla(/^Estrella 1$/))
    expect(ultimoFiltro()).toMatchObject({ potencial: 'estrella' })
    expect(pastilla(/^Tibio 1$/)).toHaveAttribute('aria-pressed', 'false')
    fireEvent.click(pastilla(/^Estrella 1$/))
    expect(ultimoFiltro()).not.toHaveProperty('potencial')
  })

  it('se combina con los demás filtros y «Limpiar filtros» lo suelta también', () => {
    mundo.conteos = CONTEOS
    render(<Cartera />)
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'contactado' } })
    fireEvent.click(pastilla(/^Tibio 1$/))
    expect(ultimoFiltro()).toMatchObject({ etapa: 'contactado', potencial: 'tibio' })
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(ultimoFiltro()).toMatchObject({ etapa: 'todas' })
    expect(ultimoFiltro()).not.toHaveProperty('potencial')
    expect(pastilla(/^Tibio 1$/)).toHaveAttribute('aria-pressed', 'false')
  })

  it('mientras llega la consulta nueva la fila NO se desmonta: sin cifras, sin poder pulsarse y con el foco donde estaba', () => {
    mundo.conteos = CONTEOS
    const { rerender } = render(<Cartera />)
    pastilla(/^Tibio 1$/).focus()
    fireEvent.click(pastilla(/^Tibio 1$/))
    mundo.cargando = true
    rerender(<Cartera />)
    const tibio = pastilla(/^Tibio cargando$/)
    expect(tibio).toHaveAttribute('aria-pressed', 'true')
    expect(tibio).toHaveAttribute('aria-disabled', 'true')
    expect(tibio).toHaveFocus()
    expect(grupo()).toHaveAttribute('aria-busy', 'true')
    // Llega la respuesta: vuelven las cifras.
    mundo.cargando = false
    rerender(<Cartera />)
    expect(pastilla(/^Tibio 1$/)).toHaveAttribute('aria-pressed', 'true')
    expect(pastilla(/^Tibio 1$/)).toHaveFocus()
  })

  it('si el servidor apaga el potencial con el filtro puesto: se suelta solo, se avisa por qué y el foco no se pierde', () => {
    mundo.conteos = CONTEOS
    const { rerender } = render(<Cartera />)
    pastilla(/^Tibio 1$/).focus()
    fireEvent.click(pastilla(/^Tibio 1$/))
    expect(ultimoFiltro()).toMatchObject({ potencial: 'tibio' })
    // La consulta filtrada vuelve con el rechazo del servidor.
    mundo.conteos = null
    mundo.error = new CrmApiError('El filtro por potencial no está disponible en este momento.', 'POTENCIAL_APAGADO')
    act(() => { rerender(<Cartera />) })
    expect(ultimoFiltro()).not.toHaveProperty('potencial')
    expect(toast.info).toHaveBeenCalledTimes(1)
    expect(toast.info).toHaveBeenCalledWith('El filtro por potencial ya no está disponible. Se quitó de la lista.')
    // No es una avería de la lista: el aviso genérico de «no se pudo cargar» no aparece.
    expect(screen.queryByText('No se pudo cargar la lista de leads.')).not.toBeInTheDocument()
    // La consulta sin filtro responde sin conteos: la fila se retira y el foco pasa a «Total leads».
    mundo.error = null
    rerender(<Cartera />)
    expect(screen.queryByRole('group', { name: 'Distribución por potencial' })).not.toBeInTheDocument()
    expect(document.querySelector('[data-kpi="Total leads"]')).toHaveFocus()
    expect(toast.info).toHaveBeenCalledTimes(1)
  })

  it('un error cualquiera de la lista sí enseña el aviso de degradación y no toca el filtro', () => {
    mundo.conteos = CONTEOS
    const { rerender } = render(<Cartera />)
    fireEvent.click(pastilla(/^Tibio 1$/))
    mundo.error = new CrmApiError('No se pudo cargar la cartera.', 'PGRST000')
    act(() => { rerender(<Cartera />) })
    expect(screen.getByText('No se pudo cargar la lista de leads.')).toBeInTheDocument()
    expect(ultimoFiltro()).toMatchObject({ potencial: 'tibio' })
    expect(toast.info).not.toHaveBeenCalled()
    // La fila sigue (con las últimas pastillas, sin cifra) y se puede soltar.
    expect(pastilla(/^Tibio sin dato$/)).toHaveAttribute('aria-pressed', 'true')
  })

  it('un resumen que deja de traer conteos retira la fila (el potencial se apagó sin filtro puesto)', () => {
    mundo.conteos = CONTEOS
    const { rerender } = render(<Cartera />)
    expect(grupo()).toBeInTheDocument()
    // El foco estaba en otro control: retirar la fila no lo mueve.
    screen.getByLabelText('Buscar en la cartera').focus()
    mundo.conteos = null
    rerender(<Cartera />)
    expect(screen.queryByRole('group', { name: 'Distribución por potencial' })).not.toBeInTheDocument()
    expect(screen.getByLabelText('Buscar en la cartera')).toHaveFocus()
  })
})
