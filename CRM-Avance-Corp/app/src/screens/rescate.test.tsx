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

/** Las filas de LEADS de la hoja (sin el encabezado ni las bandas de los bloques «Llamar hoy» / «El resto»). */
function filasDeLeads(contenedor: HTMLElement = screen.getByRole('table')): HTMLElement[] {
  return within(contenedor).getAllByRole('row').filter((r) => within(r).queryByRole('rowheader') !== null)
}
const nombres = (filas: HTMLElement[]) => filas.map((f) => within(f).getByRole('button', { name: /^LEAD BASE/ }).textContent?.replace(' — toca llamar hoy', ''))
const numeros = (filas: HTMLElement[]) => filas.map((f) => f.querySelector('td')?.textContent)
/** El número de una pastilla del resumen (exacto: un toHaveTextContent('2') casaría con «2026»). */
const cifra = (etiqueta: string) => within(screen.getByRole('region', { name: 'Resumen de tu base' })).getByText(etiqueta).closest('p, button')?.querySelector('strong')

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
    const filas = filasDeLeads()
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
    expect(screen.getByText('No pudimos actualizar tu base. Se muestran los últimos datos.')).toHaveAttribute('role', 'status')
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

describe('organizar el trabajo (F3): «Llamar hoy» arriba y filtros', () => {
  const SEP = '2026-09-10T15:00:00Z'
  const AGO = '2026-08-15T15:00:00Z'
  // Cinco leads, en el orden en que los manda el servidor: dos para llamar hoy (uno vencido) y tres más.
  const BASE = () => [
    fila(1, { rellamada_hoy: true, proxima_llamada_en: '2026-10-02T20:00:00Z', recibido_en: SEP, motivo_descarte: 'sin_fondos', etapa_maxima: 'reunion_agendada', ultimo_resultado: 'volver_a_llamar', intentos: 2 }),
    fila(2, { rellamada_hoy: true, proxima_llamada_en: '2026-10-01T20:00:00Z', recibido_en: AGO, motivo_descarte: 'no_responde', ultimo_resultado: 'volver_a_llamar', intentos: 1 }),
    fila(3, { recibido_en: AGO, motivo_descarte: 'sin_fondos', etapa_maxima: 'propuesta_enviada' }),
    fila(4, { recibido_en: AGO, motivo_descarte: 'sin_fondos', ultimo_resultado: null, intentos: 0, ultimo_intento_en: null }),
    fila(5, { recibido_en: SEP, motivo_descarte: null, etapa_maxima: 'sin_datos', ultimo_resultado: 'no_interesado', proxima_llamada_en: '2026-10-06T15:00:00Z' }),
  ]
  const opcionesDe = (nombre: string) => within(screen.getByRole('combobox', { name: nombre })).getAllByRole('option').map((o) => o.textContent)
  const bloque = (nombre: RegExp) => screen.getByRole('rowgroup', { name: nombre })

  it('el bloque «Llamar hoy» va primero, con su título y conteo; después «El resto»; el # sigue de un bloque al otro', () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(['Llamar hoy:2', 'El resto:3'])
    expect(nombres(filasDeLeads(bloque(/^Llamar hoy/)))).toEqual(['LEAD BASE 1', 'LEAD BASE 2'])
    expect(nombres(filasDeLeads(bloque(/^El resto/)))).toEqual(['LEAD BASE 3', 'LEAD BASE 4', 'LEAD BASE 5'])
    expect(numeros(filasDeLeads())).toEqual(['1', '2', '3', '4', '5'])
    expect(cifra('En tu base')).toHaveTextContent(/^5$/)
    expect(cifra('Para llamar hoy')).toHaveTextContent(/^2$/)
    expect(cifra('Rellamadas agendadas')).toHaveTextContent(/^1$/)
  })

  it('el orden lo trae el servidor: dentro de cada bloque no se reordena nada', () => {
    // Orden adrede «raro»: el resto llega con la etapa más baja primero y una rellamada de hoy después de otro lead.
    CONSULTA.data = [
      fila(7, { etapa_maxima: 'nuevo' }),
      fila(8, { rellamada_hoy: true, proxima_llamada_en: '2026-10-02T20:00:00Z' }),
      fila(6, { etapa_maxima: 'propuesta_enviada' }),
    ]
    render(<BaseGestion />)
    expect(nombres(filasDeLeads(bloque(/^Llamar hoy/)))).toEqual(['LEAD BASE 8'])
    expect(nombres(filasDeLeads(bloque(/^El resto/)))).toEqual(['LEAD BASE 7', 'LEAD BASE 6'])
  })

  it('el contador de intentos se ve en los dos bloques', () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    expect(within(bloque(/^Llamar hoy/)).getByText('2 de 3')).toBeInTheDocument()
    expect(within(bloque(/^El resto/)).getByText('0 de 3')).toBeInTheDocument()
  })

  it('«Para llamar hoy» se abre: lleva el foco al bloque', async () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    await userEvent.click(screen.getByRole('button', { name: /^Para llamar hoy:\s?2, ver el bloque$/ }))
    expect(screen.getByRole('heading', { name: /^Llamar hoy/ })).toHaveFocus()
  })

  it('filtros combinados con el Mes: cada opción cuenta lo que deja ver, y el #, los bloques y las pastillas cuentan lo filtrado', async () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    expect(opcionesDe('Motivo del descarte')).toEqual(['Todos (5)', 'Sin fondos (3)', 'No responde (1)', 'Sin motivo (1)'])
    expect(opcionesDe('Etapa máxima')).toEqual(['Todos (5)', 'Entrevista realizada (1)', 'Cita agendada (1)', 'Contactado (2)', 'Sin historial (1)'])
    expect(opcionesDe('Último resultado')).toEqual(['Todos (5)', 'No contestó (1)', 'Volver a llamar (2)', 'No le interesa (1)', 'Sin intentos (1)'])
    expect(screen.queryByRole('button', { name: /Quitar filtros/ })).toBeNull()

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Mes' }), '2026-08')
    // Con agosto elegido, el motivo cuenta solo agosto.
    expect(opcionesDe('Motivo del descarte')).toEqual(['Todos (3)', 'Sin fondos (2)', 'No responde (1)'])
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), 'sin_fondos')
    // Y el Mes cuenta con el motivo elegido.
    expect(opcionesDe('Mes')).toEqual(['Todos (3)', 'Septiembre 2026 (1)', 'Agosto 2026 (2)'])
    // Sin rellamadas de hoy en lo filtrado, no hay bloques: la hoja de siempre.
    expect(screen.queryByRole('heading', { name: /^Llamar hoy/ })).toBeNull()
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 3', 'LEAD BASE 4'])
    expect(numeros(filasDeLeads())).toEqual(['1', '2'])
    expect(cifra('Coinciden')).toHaveTextContent(/^2$/)
    expect(cifra('Para llamar hoy')).toHaveTextContent(/^0$/)
    expect(screen.getByText('2 de 5 leads')).toHaveAttribute('role', 'status')
    expect(screen.getByRole('table', { name: /de Agosto 2026, con los filtros elegidos/ })).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: /Quitar filtros/ }))
    expect(filasDeLeads()).toHaveLength(5)
    expect(screen.getByRole('combobox', { name: 'Mes' })).toHaveValue('todos')
    expect(screen.getByRole('combobox', { name: 'Motivo del descarte' })).toHaveValue('todos')
    expect(screen.queryByRole('button', { name: /Quitar filtros/ })).toBeNull()
    // El botón desapareció: el foco va al primer filtro, no a <body>.
    expect(screen.getByRole('combobox', { name: 'Mes' })).toHaveFocus()
    expect(cifra('En tu base')).toHaveTextContent(/^5$/)
  })

  it('los filtros recortan los DOS bloques (y sus conteos)', async () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Etapa máxima' }), 'contactado')
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(['Llamar hoy:1', 'El resto:1'])
    expect(nombres(filasDeLeads(bloque(/^Llamar hoy/)))).toEqual(['LEAD BASE 2'])
    expect(nombres(filasDeLeads(bloque(/^El resto/)))).toEqual(['LEAD BASE 4'])
    expect(numeros(filasDeLeads())).toEqual(['1', '2'])
    // Solo «volver a llamar» (las dos son de hoy): no queda «El resto» que pintar.
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Etapa máxima' }), 'todos')
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Último resultado' }), 'volver_a_llamar')
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(['Llamar hoy:2'])
  })

  it('«Rellamadas agendadas» se abre: filtra la hoja a esas filas y se apaga con «Quitar filtros»', async () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    const agendadas = screen.getByRole('button', { name: /^Rellamadas agendadas:\s?1, ver solo esas$/ })
    expect(agendadas).toHaveAttribute('aria-pressed', 'false')
    await userEvent.click(agendadas)
    expect(screen.getByRole('button', { name: /^Rellamadas agendadas:\s?1, ver solo esas$/ })).toHaveAttribute('aria-pressed', 'true')
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 5'])
    expect(screen.getByText('1 de 5 leads')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: /Quitar filtros/ }))
    expect(filasDeLeads()).toHaveLength(5)
    expect(screen.getByRole('button', { name: /^Rellamadas agendadas:\s?1, ver solo esas$/ })).toHaveAttribute('aria-pressed', 'false')
  })

  it('vacío por filtros (el último lead que coincidía salió al refrescar): dice qué hacer y «Quitar filtros» lo resuelve', async () => {
    CONSULTA.data = BASE()
    const { rerender } = render(<BaseGestion />)
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Mes' }), '2026-08')
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), 'no_responde')
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 2'])
    // LEAD 2 se reactivó; «No responde» y agosto siguen existiendo en la base, pero ya no juntos.
    CONSULTA = { ...CONSULTA, data: [...BASE().filter((f) => f.lead_id !== 'lead-2'), fila(9, { recibido_en: SEP, motivo_descarte: 'no_responde' })] }
    rerender(<BaseGestion />)
    expect(screen.queryByRole('table')).toBeNull()
    expect(screen.getByText('Ningún lead coincide')).toBeInTheDocument()
    expect(screen.getByText('0 de 5 leads')).toBeInTheDocument()
    expect(opcionesDe('Motivo del descarte')).toContain('No responde (0)')
    const quitar = screen.getAllByRole('button', { name: /Quitar filtros/ })
    expect(quitar).toHaveLength(2) // el de la barra y el del vacío
    await userEvent.click(quitar[1] as HTMLElement)
    expect(filasDeLeads()).toHaveLength(5)
    // El panel vacío (y su botón) desaparecen: el foco va al primer filtro, no a <body>.
    expect(screen.getByRole('combobox', { name: 'Mes' })).toHaveFocus()
  })

  it('si el valor elegido sale de la base al refrescar, el filtro vuelve a «Todos» y lo olvida', async () => {
    CONSULTA.data = BASE()
    const { rerender } = render(<BaseGestion />)
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), 'no_responde')
    CONSULTA = { ...CONSULTA, data: BASE().filter((f) => f.lead_id !== 'lead-2') }
    rerender(<BaseGestion />)
    expect(screen.getByRole('combobox', { name: 'Motivo del descarte' })).toHaveValue('todos')
    CONSULTA = { ...CONSULTA, data: BASE() }
    rerender(<BaseGestion />)
    expect(screen.getByRole('combobox', { name: 'Motivo del descarte' })).toHaveValue('todos')
    expect(filasDeLeads()).toHaveLength(5)
  })

  it('en el celular: dos listas con su título, «Llamar hoy» primero, y el contador de intentos en las dos', async () => {
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: () => ({ matches: true, addEventListener: () => {}, removeEventListener: () => {} }),
    })
    try {
      CONSULTA.data = BASE()
      render(<BaseGestion />)
      expect(screen.queryByRole('table')).toBeNull()
      const hoy = screen.getByRole('list', { name: /^Llamar hoy/ })
      const resto = screen.getByRole('list', { name: /^El resto/ })
      expect(within(hoy).getAllByRole('listitem')).toHaveLength(2)
      expect(within(resto).getAllByRole('listitem')).toHaveLength(3)
      expect(hoy.compareDocumentPosition(resto) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
      expect(within(hoy).getByText('2 de 3')).toBeInTheDocument()
      expect(within(resto).getByText('0 de 3')).toBeInTheDocument()
      // Los filtros también están en el celular.
      expect(screen.getByRole('combobox', { name: 'Motivo del descarte' })).toBeInTheDocument()
      // Sin región dentro de la región: el nombre de cada bloque lo llevan su h2 y su lista, no una <section> más.
      expect(screen.getAllByRole('region').map((r) => r.getAttribute('aria-label'))).toEqual(['Resumen de tu base', 'Tu base para gestión'])
      // «Para llamar hoy» también se abre en el celular: el foco va al título del bloque.
      await userEvent.click(screen.getByRole('button', { name: /^Para llamar hoy:\s?2, ver el bloque$/ }))
      expect(screen.getByRole('heading', { name: /^Llamar hoy/ })).toHaveFocus()
    } finally {
      Reflect.deleteProperty(window, 'matchMedia')
    }
  })

  it('en demo se ve el bloque «Llamar hoy» (la muestra trae rellamadas de hoy) sin salir un request', () => {
    YO = { id: 'analista-a', rol: 'vendedor', demo: true }
    CONSULTA = { isPending: true, isError: false, isFetching: false, refetch }
    render(<BaseGestion />)
    expect(useBaseGestion).toHaveBeenCalledWith(false, undefined)
    expect(filasDeLeads(bloque(/^Llamar hoy/)).length).toBeGreaterThanOrEqual(2)
    expect(opcionesDe('Motivo del descarte').length).toBeGreaterThan(3)
  })

  it('el conteo filtrado se anuncia: su región de estado existe VACÍA antes de filtrar y es el MISMO nodo el que recibe el texto', async () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    const barra = screen.getByRole('group', { name: 'Filtrar tu base' })
    const estado = within(barra).getByRole('status')
    expect(estado).toBeEmptyDOMElement()
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), 'sin_fondos')
    expect(within(barra).getByRole('status')).toBe(estado)
    expect(estado).toHaveTextContent(/^3 de 5 leads$/)
  })

  it('el filtro activo se marca con borde y fondo; los anillos quedan SOLO para el foco (se ve el foco aunque esté activo)', async () => {
    CONSULTA.data = BASE()
    render(<BaseGestion />)
    const motivo = screen.getByRole('combobox', { name: 'Motivo del descarte' })
    await userEvent.selectOptions(motivo, 'sin_fondos')
    const clases = motivo.className.split(/\s+/)
    expect(clases).toEqual(expect.arrayContaining(['border-accent', 'bg-accent/[0.06]', 'focus-visible:ring-2', 'focus-visible:ring-accent', 'focus-visible:ring-offset-2']))
    expect(clases.filter((c) => /^ring-/.test(c))).toEqual([])
  })

  it('al APAGAR «Rellamadas agendadas» con su conteo en 0, la pastilla deja de ser botón y el foco va al resumen (no a <body>)', async () => {
    CONSULTA.data = BASE()
    const { rerender } = render(<BaseGestion />)
    await userEvent.click(screen.getByRole('button', { name: /^Rellamadas agendadas:\s?1, ver solo esas$/ }))
    // LEAD 5 (la única agendada) pasa a ser de otro motivo al refrescar: sigue habiendo una agendada en la base (el
    // interruptor no se apaga solo), pero con «Sin motivo» elegido ya no queda ninguna.
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Motivo del descarte' }), '(sin dato)')
    CONSULTA = { ...CONSULTA, data: [...BASE().map((f) => (f.lead_id === 'lead-5' ? { ...f, motivo_descarte: 'otro' } : f)), fila(6, { motivo_descarte: null })] }
    rerender(<BaseGestion />)
    const interruptor = screen.getByRole('button', { name: /^Rellamadas agendadas:\s?0, ver solo esas$/ })
    expect(interruptor).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(interruptor)
    expect(screen.queryByRole('button', { name: /^Rellamadas agendadas/ })).toBeNull()
    expect(screen.getByRole('region', { name: 'Resumen de tu base' })).toHaveFocus()
    expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 6'])
  })

  describe('ESTADO DE PRODUCCIÓN (hoy: nadie registró intentos, ninguna rellamada)', () => {
    it('base con filas, SIN rellamadas de hoy y sin mes: ni bloques ni Mes; los filtros dicen la verdad', () => {
      CONSULTA.data = [
        fila(1, { recibido_en: null, intentos: 0, ultimo_resultado: null, ultimo_intento_en: null, etapa_maxima: 'contactado' }),
        fila(2, { recibido_en: null, intentos: 0, ultimo_resultado: null, ultimo_intento_en: null, etapa_maxima: 'sin_datos', motivo_descarte: 'sin_fondos' }),
      ]
      render(<BaseGestion />)
      expect(screen.queryByRole('heading', { name: /^Llamar hoy/ })).toBeNull()
      expect(screen.queryByRole('heading', { name: /^El resto/ })).toBeNull()
      expect(screen.queryByRole('combobox', { name: 'Mes' })).toBeNull()
      expect(nombres(filasDeLeads())).toEqual(['LEAD BASE 1', 'LEAD BASE 2'])
      expect(numeros(filasDeLeads())).toEqual(['1', '2'])
      expect(opcionesDe('Último resultado')).toEqual(['Todos (2)', 'Sin intentos (2)'])
      expect(opcionesDe('Motivo del descarte')).toEqual(['Todos (2)', 'Sin fondos (1)', 'No responde (1)'])
      // «Para llamar hoy 0» no se abre (no hay nada detrás) y no se inventa un vacío de bloque.
      expect(cifra('Para llamar hoy')).toHaveTextContent(/^0$/)
      expect(screen.queryByRole('button', { name: /^Para llamar hoy/ })).toBeNull()
      expect(screen.queryByRole('button', { name: /^Rellamadas agendadas/ })).toBeNull()
      expect(screen.queryByRole('button', { name: /Quitar filtros/ })).toBeNull()
      expect(screen.getAllByText('0 de 3')).toHaveLength(2)
    })

    it('base vacía: el vacío de siempre, sin filtros que no filtran nada', () => {
      CONSULTA.data = []
      render(<BaseGestion />)
      expect(screen.getByText('No tienes leads descartados por gestionar')).toBeInTheDocument()
      expect(screen.queryByRole('combobox')).toBeNull()
      expect(screen.queryByRole('group', { name: 'Filtrar tu base' })).toBeNull()
      expect(screen.queryByRole('heading', { name: /^Llamar hoy/ })).toBeNull()
      expect(cifra('En tu base')).toHaveTextContent(/^0$/)
    })
  })
})
