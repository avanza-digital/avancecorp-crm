// Tabla de Leads · potencial del lead. El hook de datos se sustituye: aquí se
// prueba lo que la tabla PINTA en cada mundo —bandera apagada (producción hoy),
// encendida sin marcas (el día que se encienda) y con marcas— y qué leads pide.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { FiltrosCarteraLocal } from '@/lib/cartera-keyset'
import type { Lead } from '@/lib/tipos'
import type { FiltrosCartera } from '@/data/crm-api'
import type { PotencialLead } from '@/lib/potencial'

let LEADS: Lead[] = []
let POTENCIAL: { habilitada: boolean; porLead: Map<string, PotencialLead> } = { habilitada: false, porLead: new Map() }
const PEDIDOS: string[][] = []

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
vi.mock('@/data/use-cartera-paginada', async () => {
  const { filtrarCarteraLocal, ordenarCarteraLocal } = await import('@/lib/cartera-keyset')
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useCarteraPaginada: (leads: Lead[], filtros: FiltrosCartera & FiltrosCarteraLocal) => {
      const filtrados = filtrarCarteraLocal(leads, { ...filtros, recepcionDemo: filtros.recepcion ?? null })
      return {
        leads: ordenarCarteraLocal(filtrados), resumen: resumenCarteraDesdeAmbito(filtrados, [], Date.now(), false),
        hayMas: false, cargando: false, cargandoMas: false, error: null, cargarMas: vi.fn(), recargar: vi.fn(),
      }
    },
  }
})
vi.mock('@/data/potencial-queries', () => ({
  usePotencialLeads: (ids: readonly string[]) => { PEDIDOS.push([...ids]); return POTENCIAL },
}))

const { Cartera } = await import('./cartera')

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
const fila = (nombre: string) => screen.getByRole('row', { name: `Abrir ficha de ${nombre}` })

beforeEach(() => {
  PEDIDOS.length = 0
  LEADS = [
    lead({ id: 'l-estrella', nombre_completo: 'GLORIA NAVARRO', actualizado_en: '2026-09-30T10:00:00Z' }),
    lead({ id: 'l-frio', nombre_completo: 'JUAN PEREZ', etapa: 'contactado', actualizado_en: '2026-09-29T10:00:00Z' }),
    lead({ id: 'l-nada', nombre_completo: 'ROSA QUISPE', actualizado_en: '2026-09-28T10:00:00Z' }),
  ]
})

describe('Cartera · potencial del lead', () => {
  it('ESTADO DE PRODUCCIÓN (potencial apagado): la tabla se ve igual que antes', () => {
    POTENCIAL = { habilitada: false, porLead: new Map() }
    render(<Cartera />)
    expect(screen.getAllByRole('row', { name: /^Abrir ficha de/ })).toHaveLength(3)
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(document.querySelector('[data-potencial]')).toBeNull()
  })

  it('ESTADO DE PRODUCCIÓN (encendido, ningún lead marcado): sin chips ni franjas', () => {
    POTENCIAL = { habilitada: true, porLead: new Map(LEADS.map((l) => [l.id, marca(l.id, null)])) }
    render(<Cartera />)
    expect(screen.getAllByRole('row', { name: /^Abrir ficha de/ })).toHaveLength(3)
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(document.querySelector('[data-potencial]')).toBeNull()
  })

  it('con marcas: chip junto al nombre y franja en la fila; la fila sin marca queda limpia', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([
      ['l-estrella', marca('l-estrella', 'estrella')], ['l-frio', marca('l-frio', 'frio')], ['l-nada', marca('l-nada', null)],
    ]) }
    render(<Cartera />)
    expect(within(fila('GLORIA NAVARRO')).getByTitle('Potencial: Estrella')).toBeInTheDocument()
    expect(fila('GLORIA NAVARRO')).toHaveAttribute('data-potencial', 'estrella')
    expect(within(fila('JUAN PEREZ')).getByTitle('Potencial: Frío')).toBeInTheDocument()
    expect(fila('JUAN PEREZ')).toHaveAttribute('data-potencial', 'frio')
    expect(within(fila('ROSA QUISPE')).queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(fila('ROSA QUISPE')).not.toHaveAttribute('data-potencial')
    // El chip va en la misma línea del nombre.
    const chip = within(fila('GLORIA NAVARRO')).getByTitle('Potencial: Estrella')
    expect(chip.parentElement).toHaveTextContent(/^GLORIA NAVARRO/)
  })

  it('la marca llega al lector de pantalla como DESCRIPCIÓN de la fila, sin tocar su nombre', () => {
    LEADS = [
      lead({ id: 'l-estrella', nombre_completo: 'GLORIA NAVARRO' }),
      // Alta manual: su fila ya llevaba la procedencia como descripción.
      lead({ id: 'l-frio', nombre_completo: 'JUAN PEREZ', procedencia: 'manual', cargado_por_nombre: 'ANA TORRES' }),
      lead({ id: 'l-manual', nombre_completo: 'LUIS RAMOS', procedencia: 'manual', cargado_por_nombre: 'ANA TORRES' }),
      lead({ id: 'l-nada', nombre_completo: 'ROSA QUISPE' }),
    ]
    POTENCIAL = { habilitada: true, porLead: new Map([
      ['l-estrella', marca('l-estrella', 'estrella')], ['l-frio', marca('l-frio', 'frio')],
      ['l-manual', marca('l-manual', null)], ['l-nada', marca('l-nada', null)],
    ]) }
    render(<Cartera />)
    // El nombre accesible no cambia: es el que usan pruebas y atajos.
    expect(fila('GLORIA NAVARRO')).toHaveAccessibleName('Abrir ficha de GLORIA NAVARRO')
    expect(fila('GLORIA NAVARRO')).toHaveAccessibleDescription(/Potencial: Estrella/)
    expect(fila('GLORIA NAVARRO')).toHaveAttribute('aria-describedby', 'potencial-l-estrella')
    // Con procedencia y marca: las dos, la marca primero (como se ve en la fila).
    expect(fila('JUAN PEREZ')).toHaveAttribute('aria-describedby', 'potencial-l-frio procedencia-l-frio')
    expect(fila('JUAN PEREZ')).toHaveAccessibleDescription(/Potencial: Frío.*Registro manual, por ANA TORRES/)
    // Sin marca: solo lo que ya llevaba, o nada.
    expect(fila('LUIS RAMOS')).toHaveAttribute('aria-describedby', 'procedencia-l-manual')
    expect(fila('LUIS RAMOS')).not.toHaveAccessibleDescription(/Potencial/)
    expect(fila('ROSA QUISPE')).not.toHaveAttribute('aria-describedby')
  })

  it('con el potencial apagado la descripción de la fila es la de siempre', () => {
    LEADS = [lead({ id: 'l-manual', nombre_completo: 'LUIS RAMOS', procedencia: 'manual', cargado_por_nombre: 'ANA TORRES' }), lead({ id: 'l-nada' })]
    POTENCIAL = { habilitada: false, porLead: new Map() }
    render(<Cartera />)
    expect(fila('LUIS RAMOS')).toHaveAttribute('aria-describedby', 'procedencia-l-manual')
    expect(fila('ROSA QUISPE')).not.toHaveAttribute('aria-describedby')
  })

  it('pregunta por los leads que la tabla tiene en pantalla, ni uno más', () => {
    POTENCIAL = { habilitada: false, porLead: new Map() }
    render(<Cartera />)
    expect(new Set(PEDIDOS.at(-1))).toEqual(new Set(['l-estrella', 'l-frio', 'l-nada']))
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'contactado' } })
    expect(PEDIDOS.at(-1)).toEqual(['l-frio'])
  })

  it('la fila Estrella sigue al cursor con variables CSS', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([['l-estrella', marca('l-estrella', 'estrella')]]) }
    render(<Cartera />)
    const estrella = fila('GLORIA NAVARRO')
    vi.spyOn(estrella, 'getBoundingClientRect').mockReturnValue({ left: 10, top: 5, width: 900, height: 45 } as DOMRect)
    fireEvent.pointerMove(estrella, { clientX: 110, clientY: 25 })
    expect(estrella.style.getPropertyValue('--pot-mx')).toBe('100px')
    expect(estrella.style.getPropertyValue('--pot-my')).toBe('20px')
  })
})
