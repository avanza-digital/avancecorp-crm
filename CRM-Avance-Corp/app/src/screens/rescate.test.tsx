// «Base para gestión» por rol (F1, 02/10/2026): el analista ve SU base (la pide sin elegir analista: el
// servidor resuelve quién es por la sesión), Supervisión y Gerencia siguen en el Centro de rescate, y la
// lista dice lo que el servidor decidió (orden, «llamar hoy», intentos) con un vacío y un error honestos.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import type { Lead } from '@/lib/tipos'

let YO: { id: string; rol: string; demo: boolean } | null = null
let LEADS: Lead[] = []
const refetch = vi.fn()
let CONSULTA: { data?: FilaBaseGestion[]; isPending: boolean; isError: boolean; isFetching: boolean; refetch: () => void }
const useBaseGestion = vi.fn((_habilitada: boolean, _vendedorId?: string | null) => CONSULTA)
const toastSuccess = vi.fn()

vi.mock('sonner', () => ({ toast: { success: toastSuccess, info: vi.fn(), error: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ leads: LEADS, recargar: async () => true, actividadesDe: () => [] }), usePanelesActions: () => ({ abrirLead: vi.fn() }) }))
// La ficha (F2) tiene sus propias pruebas: aquí basta con saber que se abre desde la hoja.
vi.mock('@/components/base-gestion/ficha-base', () => ({ FichaBase: ({ fila }: { fila: { nombre_completo: string } | null }) => (fila ? <p>Ficha de {fila.nombre_completo}</p> : null) }))
vi.mock('@/data/crm-queries', () => ({ useBaseGestion: (habilitada: boolean, vendedorId?: string | null) => useBaseGestion(habilitada, vendedorId) }))
vi.mock('@/screens/rescate-descartados', () => ({ RescateDescartados: () => <p>Centro de rescate del equipo</p> }))

const { BaseGestion } = await import('./rescate')

function fila(n: number, sobre: Partial<FilaBaseGestion> = {}): FilaBaseGestion {
  return {
    lead_id: `lead-${n}`, nombre_completo: `LEAD BASE ${n}`, telefono: `+5198765432${n}`, distrito: 'Surco', origen: 'landing',
    categoria_interes: null, monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde',
    descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
    ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
    rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: 'analista-a', gestiona: 'ANALISTA A', recibido_en: '2026-08-15T15:00:00Z', ...sobre,
  }
}

beforeEach(() => {
  YO = { id: 'analista-a', rol: 'vendedor', demo: false }
  LEADS = []
  CONSULTA = { data: [], isPending: false, isError: false, isFetching: false, refetch }
})
afterEach(() => vi.clearAllMocks())

describe('despacho por rol', () => {
  it('el analista ve SU base y la pide sin elegir analista (el servidor resuelve quién es)', () => {
    CONSULTA.data = [fila(1)]
    render(<BaseGestion />)
    expect(screen.getByRole('table')).toBeInTheDocument()
    expect(useBaseGestion).toHaveBeenCalledWith(true, undefined)
    expect(screen.queryByText('Centro de rescate del equipo')).toBeNull()
  })

  it.each(['supervisor', 'gerencia'])('%s conserva el Centro de rescate', (rol) => {
    YO = { id: 'jefe', rol, demo: false }
    render(<BaseGestion />)
    expect(screen.getByText('Centro de rescate del equipo')).toBeInTheDocument()
    expect(useBaseGestion).not.toHaveBeenCalled()
  })

  it('otro rol no recibe nada fabricado', () => {
    YO = { id: 'dir', rol: 'directorio', demo: false }
    render(<BaseGestion />)
    expect(screen.getByText('La base para gestión no está disponible para tu rol')).toBeInTheDocument()
    expect(useBaseGestion).not.toHaveBeenCalled()
  })
})

describe('la base del analista', () => {
  it('respeta el orden del servidor, marca lo de hoy y cuenta lo que hay', () => {
    // Mediodía en Lima: la rellamada de las 15:00 es de HOY sin depender de la hora en que corre la prueba.
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-10-02T17:00:00Z'))
    CONSULTA.data = [
      fila(1, { rellamada_hoy: true, proxima_llamada_en: '2026-10-02T20:00:00Z', ultimo_resultado: 'volver_a_llamar', intentos: 2 }),
      fila(2, { etapa_maxima: 'reunion_agendada', intentos: 0, ultimo_resultado: null, ultimo_intento_en: null }),
    ]
    render(<BaseGestion />)
    vi.useRealTimers()
    expect(screen.getByRole('table', { name: /Tus leads descartados/ })).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Tu base para gestión' })).toHaveAttribute('tabindex', '0')
    // La hoja (Miguel, 02/10): número de fila, y el teléfono es el botón de llamar.
    expect(screen.getByRole('columnheader', { name: '#' })).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: 'Teléfono' })).toBeInTheDocument()
    const filas = within(screen.getByRole('table')).getAllByRole('row').slice(1)
    expect(filas.map((f) => within(f).getByRole('rowheader').textContent)).toEqual([
      expect.stringContaining('LEAD BASE 1'), expect.stringContaining('LEAD BASE 2'),
    ])
    const [primera, segunda] = filas as [HTMLElement, HTMLElement]
    expect(within(primera).getByRole('rowheader')).toHaveTextContent('toca llamar hoy')
    expect(within(segunda).getByRole('rowheader')).not.toHaveTextContent('toca llamar hoy')
    expect(within(primera).getByText('Hoy, 15:00')).toBeInTheDocument()
    expect(within(primera).getByText('2 de 3')).toBeInTheDocument()
    expect(within(segunda).getByText('Cita agendada')).toBeInTheDocument()
    expect(within(segunda).getByText('Sin intentos')).toBeInTheDocument()
    expect(within(segunda).getByText('Sin agendar')).toBeInTheDocument()
    const resumen = screen.getByRole('region', { name: 'Resumen de tu base' })
    expect(within(resumen).getByText('En tu base').parentElement).toHaveTextContent('2')
    expect(within(resumen).getByText('Para llamar hoy').parentElement).toHaveTextContent('1')
  })

  it('en la laptop «Llamar» copia el número (un tel: ahí no marca nada)', async () => {
    const writeText = vi.fn(async () => {})
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } })
    CONSULTA.data = [fila(1), fila(2, { telefono: null })]
    render(<BaseGestion />)
    expect(screen.queryByRole('link', { name: /Llamar a/ })).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: 'Llamar a LEAD BASE 1, 987 654 321: copia su número' }))
    expect(writeText).toHaveBeenCalledWith('+51987654321')
    expect(toastSuccess).toHaveBeenCalledWith('Número copiado: 987 654 321 — márcalo desde tu celular')
    expect(screen.getByText('Sin teléfono')).toBeInTheDocument()
  })

  it('un teléfono que no sirve (menos de 7 dígitos) no se ofrece para llamar', () => {
    CONSULTA.data = [fila(1, { telefono: '12345' })]
    render(<BaseGestion />)
    expect(screen.queryByRole('button', { name: /Llamar a/ })).toBeNull()
    expect(screen.getByText('Sin teléfono')).toBeInTheDocument()
  })

  it('en el celular la base es una lista de tarjetas y «Llamar» abre el marcador', () => {
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: () => ({ matches: true, addEventListener: () => {}, removeEventListener: () => {} }),
    })
    try {
      CONSULTA.data = [fila(1)]
      render(<BaseGestion />)
      expect(screen.queryByRole('table')).toBeNull()
      const lista = screen.getByRole('list', { name: 'Tu base para gestión' })
      expect(lista).toHaveAttribute('role', 'list')
      expect(within(lista).getAllByRole('listitem')).toHaveLength(1)
      expect(within(lista).getByText('LEAD BASE 1')).toBeInTheDocument()
      expect(within(lista).getByRole('link', { name: 'Llamar a LEAD BASE 1' })).toHaveAttribute('href', 'tel:+51987654321')
    } finally {
      Reflect.deleteProperty(window, 'matchMedia')
    }
  })

  it('sin descartados dice qué pasa y cuándo vuelven los que descansan', () => {
    render(<BaseGestion />)
    expect(screen.getByText('No tienes leads descartados por gestionar')).toBeInTheDocument()
    expect(screen.getByText(/vuelven solos al terminar sus 30 días/)).toBeInTheDocument()
    expect(screen.queryByRole('table')).toBeNull()
  })

  it('si la carga falla, ofrece reintentar', async () => {
    CONSULTA = { isPending: false, isError: true, isFetching: false, refetch }
    render(<BaseGestion />)
    expect(screen.getByText('No se pudo cargar tu base para gestión.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(refetch).toHaveBeenCalledTimes(1)
  })

  it('si falla el refresco con datos ya cargados, los conserva y avisa en línea', async () => {
    CONSULTA = { data: [fila(1)], isPending: false, isError: true, isFetching: false, refetch }
    render(<BaseGestion />)
    expect(screen.getByRole('table')).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('No pudimos actualizar tu base. Se muestran los últimos datos.')
    expect(screen.queryByText('No se pudo cargar tu base para gestión.')).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(refetch).toHaveBeenCalledTimes(1)
  })

  it('mientras carga por primera vez lo dice (aria-busy) y no pinta una base vacía', () => {
    CONSULTA = { isPending: true, isError: false, isFetching: true, refetch }
    const { container } = render(<BaseGestion />)
    expect(container.querySelector('[aria-busy]')).not.toBeNull()
    expect(screen.queryByText('No tienes leads descartados por gestionar')).toBeNull()
  })

  it('en demo no sale ni un request: la base se arma con los descartados propios del store', () => {
    YO = { id: 'analista-a', rol: 'vendedor', demo: true }
    CONSULTA = { isPending: true, isError: false, isFetching: false, refetch }
    LEADS = [
      { id: 'd1', nombre_completo: 'DEMO PROPIO', telefono: '+51911111111', etapa: 'descartado', origen: 'landing', monto_estimado: 5000, moneda: 'PEN', vendedor_id: 'analista-a', creado_en: '2026-09-01T15:00:00Z' } as Lead,
      { id: 'd2', nombre_completo: 'DEMO AJENO', telefono: '+51922222222', etapa: 'descartado', origen: 'landing', monto_estimado: 5000, moneda: 'PEN', vendedor_id: 'otro', creado_en: '2026-09-01T15:00:00Z' } as Lead,
    ]
    render(<BaseGestion />)
    expect(useBaseGestion).toHaveBeenCalledWith(false, undefined)
    expect(screen.getByText('DEMO PROPIO')).toBeInTheDocument()
    expect(screen.queryByText('DEMO AJENO')).toBeNull()
  })
})

describe('la ficha del lead (F2)', () => {
  it('el nombre del lead abre su ficha; en el celular, «Ver ficha»', async () => {
    CONSULTA.data = [fila(1), fila(2)]
    render(<BaseGestion />)
    await userEvent.click(screen.getByRole('button', { name: 'LEAD BASE 2' }))
    expect(screen.getByText('Ficha de LEAD BASE 2')).toBeInTheDocument()
  })
})

describe('el MES del lead (Miguel, 02/10: «mis leads de enero, de marzo, de agosto»)', () => {
  it('columna «Mes» tras el lead y un selector con el conteo; al elegir un mes, la hoja, el # y las pastillas cuentan solo ese mes', async () => {
    CONSULTA.data = [
      fila(1, { recibido_en: '2026-09-10T15:00:00Z', rellamada_hoy: true, proxima_llamada_en: '2026-10-02T20:00:00Z' }),
      fila(2, { recibido_en: '2026-08-15T15:00:00Z' }),
      // 1 de septiembre a las 02:00 UTC es todavía 31 de agosto en Lima: el mes es el de Lima.
      fila(3, { recibido_en: '2026-09-01T02:00:00Z' }),
    ]
    render(<BaseGestion />)
    const encabezados = screen.getAllByRole('columnheader').map((c) => c.textContent)
    expect(encabezados.slice(0, 3)).toEqual(['#', 'Lead', 'Mes'])
    const selector = screen.getByRole('combobox', { name: 'Mes' })
    expect(within(selector).getAllByRole('option').map((o) => o.textContent)).toEqual([
      'Todos (3)', 'Septiembre 2026 (1)', 'Agosto 2026 (2)',
    ])

    await userEvent.selectOptions(selector, '2026-08')
    const filas = within(screen.getByRole('table')).getAllByRole('row').slice(1)
    expect(filas.map((f) => within(f).getByRole('rowheader').textContent)).toEqual(['LEAD BASE 2', 'LEAD BASE 3'])
    expect(filas.map((f) => f.querySelector('td')?.textContent)).toEqual(['1', '2'])
    expect(within(filas[0] as HTMLElement).getByText('Agosto 2026')).toBeInTheDocument()
    const resumen = screen.getByRole('region', { name: 'Resumen de tu base' })
    // El número exacto (el texto de la pastilla contiene «2026»: un toHaveTextContent('2') no probaría nada).
    expect(within(resumen).getByText('De Agosto 2026').closest('p')?.querySelector('strong')).toHaveTextContent(/^2$/)
    expect(within(resumen).getByText('Para llamar hoy').closest('p')?.querySelector('strong')).toHaveTextContent(/^0$/)
    expect(screen.getByRole('table', { name: /Tus leads descartados de Agosto 2026/ })).toBeInTheDocument()
  })

  it('si el mes elegido se vacía, vuelve a «Todos» y lo olvida: cuando ese mes reaparece, la hoja no se filtra sola', async () => {
    CONSULTA.data = [fila(1, { recibido_en: '2026-09-10T15:00:00Z' }), fila(2, { recibido_en: '2026-08-15T15:00:00Z' })]
    const { rerender } = render(<BaseGestion />)
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Mes' }), '2026-08')
    expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(2)
    CONSULTA = { ...CONSULTA, data: [fila(1, { recibido_en: '2026-09-10T15:00:00Z' })] }
    rerender(<BaseGestion />)
    expect(screen.getByRole('combobox', { name: 'Mes' })).toHaveValue('todos')
    CONSULTA = { ...CONSULTA, data: [fila(1, { recibido_en: '2026-09-10T15:00:00Z' }), fila(2, { recibido_en: '2026-08-15T15:00:00Z' })] }
    rerender(<BaseGestion />)
    expect(screen.getByRole('combobox', { name: 'Mes' })).toHaveValue('todos')
    expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(3)
  })

  it('ESTADO DE PRODUCCIÓN (antes de la B5, el servidor no manda el mes): ni columna ni selector, y la hoja sigue entera', () => {
    CONSULTA.data = [fila(1, { recibido_en: null }), fila(2, { recibido_en: null })]
    render(<BaseGestion />)
    expect(screen.queryByRole('columnheader', { name: 'Mes' })).toBeNull()
    expect(screen.queryByRole('combobox', { name: 'Mes' })).toBeNull()
    expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(3)
    const resumen = screen.getByRole('region', { name: 'Resumen de tu base' })
    expect(within(resumen).getByText('En tu base').parentElement).toHaveTextContent('2')
  })

  it('en el celular la tarjeta dice el mes', () => {
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: () => ({ matches: true, addEventListener: () => {}, removeEventListener: () => {} }),
    })
    try {
      CONSULTA.data = [fila(1, { recibido_en: '2026-08-15T15:00:00Z' })]
      render(<BaseGestion />)
      const tarjeta = screen.getByRole('listitem')
      expect(within(tarjeta).getByText('Mes')).toBeInTheDocument()
      expect(within(tarjeta).getByText('Agosto 2026')).toBeInTheDocument()
    } finally {
      Reflect.deleteProperty(window, 'matchMedia')
    }
  })
})
