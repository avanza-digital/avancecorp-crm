// Pantalla Facturación: filtros, comparación y — sobre todo — el ESTADO VACÍO.
//
// El gate de realidad del proyecto exige probar la pantalla en el estado que
// tiene producción, no solo con el fixture lleno: hoy la fuente real no existe,
// así que «sin cierres» es el estado que de verdad se va a ver, y es justo la
// rama donde vive el botón que la rescata.
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { FilaFacturacionDia } from '@/lib/facturacion'

// La pantalla recibe las filas por prop, así que ni la sesión ni el servidor
// deciden nada aquí; se doblan para que el componente monte. El camino real
// (RPC + modo demo) lo cubren la matriz de RLS y el oráculo del servidor.
const dobles = vi.hoisted(() => ({
  demo: false,
  // El organigrama que la pantalla lee del store. Por defecto vacío: así los
  // casos que no hablan del roster siguen midiendo solo lo vendido.
  equipo: [] as Array<{
    perfil_id: string
    nombre_completo: string
    rol_crm: string
    supervisor_id: string | null
    activo: boolean
  }>,
  // Tri-estado del tipo de cambio, igual que el hook real: undefined =
  // consultando, null = no disponible, objeto = listo. Por defecto null, que es
  // como se comporta el entorno de prueba (no hay edge).
  tc: null as { promedio: number; fuente: string } | null | undefined,
  /** Argumentos con los que la pantalla pidió el TC, para poder comprobarlos. */
  tcArgs: [] as Array<{ habilitado: boolean; fechaCorte: string | undefined }>,
  recargarTc: 0,
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: { id: 'g1', rol: 'gerencia', demo: dobles.demo } }),
}))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ equipo: dobles.equipo }) }))
vi.mock('@/lib/tipo-cambio', () => ({
  useTipoCambio: (habilitado = true, fechaCorte?: string) => {
    dobles.tcArgs.push({ habilitado, fechaCorte })
    return {
      tc: dobles.tc,
      recargar: () => {
        dobles.recargarTc += 1
      },
    }
  },
  usdAPen: (usd: number, tc: number) => (tc > 0 ? usd * tc : 0),
}))
vi.mock('@/data/crm-queries', () => ({
  useFacturacionDiaria: () => ({ data: undefined, isPending: false, isError: false, isFetching: false, refetch: vi.fn() }),
}))

const { Facturacion } = await import('./facturacion')

/** Jueves 10 de setiembre de 2026, 12:00 en la zona de la máquina. */
const HOY = new Date(2026, 8, 10, 12, 0, 0)

function fila(p: Partial<FilaFacturacionDia> & { id?: string }): FilaFacturacionDia {
  const { id: _id, ...resto } = p
  return {
    dia: '2026-09-02',
    tipo: 'contrato_nuevo',
    moneda: 'PEN',
    analistaId: 'ana',
    analistaNombre: 'Ana Analista',
    supervisorId: 'sup-rosa',
    supervisorNombre: 'Rosa Uno',
    operaciones: 1,
    capital: 50_000,
    ...resto,
  }
}

/** Dos equipos, tres analistas. Solo Carla vende en dólares. */
const FILAS: readonly FilaFacturacionDia[] = [
  fila({ id: '1', dia: '2026-09-02', capital: 300_000 }),
  fila({ id: '2', dia: '2026-09-04', capital: 100_000 }),
  fila({ id: '3', dia: '2026-09-02', capital: 80_000, analistaId: 'beto', analistaNombre: 'Beto Analista' }),
  fila({
    id: '4',
    dia: '2026-09-03',
    capital: 40_000,
    analistaId: 'carla',
    analistaNombre: 'Carla Analista',
    supervisorId: 'sup-sara',
    supervisorNombre: 'Sara Dos',
  }),
  fila({
    id: '5',
    dia: '2026-09-03',
    capital: 7_000,
    moneda: 'USD',
    analistaId: 'carla',
    analistaNombre: 'Carla Analista',
    supervisorId: 'sup-sara',
    supervisorNombre: 'Sara Dos',
  }),
  // Mes anterior: da con qué comparar el KPI de arriba.
  fila({ id: '6', dia: '2026-08-05', capital: 200_000 }),
]

function pintar(filas: readonly FilaFacturacionDia[] = FILAS) {
  return render(<Facturacion filas={filas} />)
}

/** La malla, para no confundir sus botones con los del panel de filtros. */
function malla(): HTMLElement {
  return screen.getByRole('region', { name: /Facturación diaria/ })
}

beforeEach(() => {
  dobles.demo = false
  vi.useFakeTimers({ shouldAdvanceTime: true })
  vi.setSystemTime(HOY)
})

afterEach(() => {
  vi.useRealTimers()
})

describe('lo que se ve al entrar', () => {
  it('con datos REALES no dice que sean de ejemplo', () => {
    // La honestidad va en los dos sentidos: rotular de «ejemplo» cifras que sí
    // son reales es tan falso como lo contrario.
    pintar()
    expect(screen.queryByText('Datos de ejemplo')).not.toBeInTheDocument()
  })

  it('en modo demostración lo avisa ANTES de mostrar nada', () => {
    dobles.demo = true
    pintar()
    expect(screen.getByText('Datos de ejemplo')).toBeVisible()
    expect(screen.getByText(/no corresponden a ninguna venta real/i)).toBeVisible()
  })

  it('agrupa por equipo, con sus analistas dentro y el total del mes', () => {
    pintar()
    expect(screen.getByRole('button', { name: /Rosa Uno/ })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
    // 300 000 + 100 000 + 80 000 = 480 000 en soles, más los 40 000 de Carla.
    expect(within(malla()).getByText('S/ 520,000')).toBeVisible()
  })

  it('los 30 días de setiembre están en la cabecera, con hoy marcado', () => {
    pintar()
    const cabeceras = within(malla()).getAllByRole('columnheader')
    // 1 de nombres + 30 días + 1 de total.
    expect(cabeceras).toHaveLength(32)
  })

  it('la cifra de una celda llega a un lector de pantalla, no solo al ratón', () => {
    pintar()
    // La celda de un equipo NUNCA es un botón: su importe vive en un sr-only.
    expect(within(malla()).getAllByText('S/ 380,000').length).toBeGreaterThan(0)
  })

  it('la región de la malla es alcanzable con el teclado', () => {
    pintar()
    expect(malla()).toHaveAttribute('tabindex', '0')
  })
})

describe('filtrar por equipo', () => {
  it('deja solo ese equipo y lo dice en una etiqueta que se puede quitar', () => {
    pintar()
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-sara' } })

    expect(screen.queryByRole('button', { name: /Rosa Uno/ })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Carla Analista' })).toBeVisible()

    const quitar = screen.getByRole('button', { name: 'Quitar Equipo de Sara Dos' })
    fireEvent.click(quitar)
    expect(screen.getByRole('button', { name: /Rosa Uno/ })).toBeVisible()
  })

  it('el pie deja de hablar de la empresa cuando hay filtro', () => {
    pintar()
    expect(screen.getByText('Total de la empresa')).toBeVisible()
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-sara' } })
    expect(screen.getByText('Total de lo que estás viendo')).toBeVisible()
  })
})

describe('comparar analistas', () => {
  it('marcar dos los deja solos, en plano y con su equipo debajo del nombre', () => {
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    // La malla ya solo muestra a Ana: al segundo se le añade desde el panel,
    // que es lo que dice el pie de la tabla en cuanto entras en comparación.
    expect(screen.getByText(/Para añadir o quitar a alguien, abre/)).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.click(
      within(screen.getByRole('group', { name: /Analistas/ })).getByRole('checkbox', {
        name: 'Comparar a Carla Analista',
      }),
    )

    expect(screen.getByText('Comparando 2 analistas, día a día')).toBeVisible()
    expect(screen.getByText('Equipo de Rosa Uno')).toBeVisible()
    expect(screen.getByText('Equipo de Sara Dos')).toBeVisible()
    // Beto no está marcado: sale de la malla.
    expect(
      screen.queryByRole('button', { name: 'Ver el mes completo de Beto Analista' }),
    ).not.toBeInTheDocument()
    // Y las cabeceras de equipo desaparecen: comparar es una lista plana.
    expect(screen.queryByRole('button', { name: /Rosa Uno/ })).not.toBeInTheDocument()
  })

  it('marcar uno solo lo aísla', () => {
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Beto Analista' }))
    expect(screen.getByText('Comparando 1 analista, día a día')).toBeVisible()
    // Su total del mes y el total del pie pasan a ser la misma cifra.
    expect(within(malla()).getAllByText('S/ 80,000')).toHaveLength(2)
  })

  it('elegir equipo deja caer a los marcados que no son suyos; quitarlo NO', () => {
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.click(
      within(screen.getByRole('group', { name: /Analistas/ })).getByRole('checkbox', {
        name: 'Comparar a Carla Analista',
      }),
    )

    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-rosa' } })
    expect(screen.getByRole('button', { name: 'Quitar Ana Analista' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Quitar Carla Analista' })).not.toBeInTheDocument()

    // Quitar el equipo no cuesta la selección que queda.
    fireEvent.click(screen.getByRole('button', { name: 'Quitar Equipo de Rosa Uno' }))
    expect(screen.getByRole('button', { name: 'Quitar Ana Analista' })).toBeVisible()
  })

  it('el panel ofrece a todo el mundo, pero desactiva a los de otro equipo', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-rosa' } })

    const panel = screen.getByRole('group', { name: /Analistas/ })
    expect(within(panel).getByRole('checkbox', { name: 'Comparar a Ana Analista' })).toBeEnabled()
    expect(within(panel).getByRole('checkbox', { name: 'Comparar a Carla Analista' })).toBeDisabled()
  })

  it('el buscador del panel filtra por nombre sin acentos ni mayúsculas', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.change(screen.getByLabelText('Buscar analista'), { target: { value: 'CARLA' } })

    const panel = screen.getByRole('group', { name: /Analistas/ })
    expect(within(panel).getByRole('checkbox', { name: 'Comparar a Carla Analista' })).toBeVisible()
    expect(
      within(panel).queryByRole('checkbox', { name: 'Comparar a Ana Analista' }),
    ).not.toBeInTheDocument()
  })
})

describe('estado vacío — el que de verdad se ve en producción', () => {
  it('sin ningún cierre lo dice y NO ofrece limpiar nada', () => {
    pintar([])
    expect(screen.getByText('Todavía no hay cierres en este mes.')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Limpiar filtros' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: /Facturación diaria/ })).not.toBeInTheDocument()
  })

  it('preguntar por quien no vendió en esa moneda responde con su fila en cero, no con un callejón', () => {
    pintar()
    // Ana no vende en dólares. ANTES la malla se quedaba sin nada que pintar y
    // había que rescatarla; ahora el cero ES la respuesta a la pregunta.
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))

    expect(screen.queryByText('Ningún cierre coincide con estos filtros.')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Carla Analista' })).not.toBeInTheDocument()
  })
})

describe('el analista que no ha vendido — petición de Miguel del 11/09/2026', () => {
  afterEach(() => {
    dobles.equipo = []
  })

  /** Organigrama del store: dos que ya venden, uno que no, y una baja. */
  function conEquipo(): void {
    dobles.equipo = [
      { perfil_id: 'sup-rosa', nombre_completo: 'Rosa Uno', rol_crm: 'supervisor', supervisor_id: null, activo: true },
      { perfil_id: 'ana', nombre_completo: 'Ana Analista', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: true },
      { perfil_id: 'nuevo', nombre_completo: 'Noe Novato', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: true },
      { perfil_id: 'baja', nombre_completo: 'Bruno Baja', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: false },
    ]
  }

  it('sale en la malla, y su fila está en cero', () => {
    conEquipo()
    pintar()
    const fila = within(malla())
      .getByRole('button', { name: 'Ver el mes completo de Noe Novato' })
      .closest('tr')
    expect(fila).not.toBeNull()
    // La celda vacía no lleva cifra a la vista, pero SÍ la anuncia para quien
    // usa lector: toda su fila dice 'S/ 0' y ni un solo importe con dígito.
    expect(within(fila as HTMLElement).queryByText(/S\/ [1-9]/)).toBeNull()
    expect(within(fila as HTMLElement).getAllByText('S/ 0').length).toBeGreaterThan(1)
  })

  it('se puede filtrar por él, que era justo lo que no se podía', () => {
    conEquipo()
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Noe Novato' }))
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Noe Novato' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Ana Analista' })).not.toBeInTheDocument()
  })

  it('en DEMO no se siembra: el fixture no se mezcla con el organigrama real', () => {
    conEquipo()
    dobles.demo = true
    try {
      pintar()
      expect(screen.queryByRole('button', { name: 'Ver el mes completo de Noe Novato' })).not.toBeInTheDocument()
    } finally {
      dobles.demo = false
    }
  })

  it('un analista dado de baja que no vendió NO aparece', () => {
    conEquipo()
    pintar()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Bruno Baja' })).not.toBeInTheDocument()
  })

  it('el organigrama no reescribe el equipo de una venta ya cerrada', () => {
    // El organigrama dice que Carla está HOY con Rosa; su venta es de cuando
    // estaba con Sara, y el equipo de Sara sigue sumándola. Mover a alguien de
    // equipo no le cambia de sitio el dinero que ya cerró. (El reparto fila a
    // fila se comprueba en el modelo: lib/facturacion.test.ts.)
    dobles.equipo = [
      { perfil_id: 'sup-rosa', nombre_completo: 'Rosa Uno', rol_crm: 'supervisor', supervisor_id: null, activo: true },
      { perfil_id: 'carla', nombre_completo: 'Carla Analista', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: true },
    ]
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Carla Analista' }))
    expect(within(malla()).getByText('Equipo de Sara Dos')).toBeVisible()
    expect(within(malla()).queryByText('Equipo de Rosa Uno')).toBeNull()
  })
})

describe('total del día con las dos monedas — petición de Miguel del 11/09/2026', () => {
  afterEach(() => {
    dobles.tc = null
    dobles.tcArgs = []
    dobles.recargarTc = 0
  })

  it('el mes en curso pide el TC vigente; un mes cerrado lo congela en su último día', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    // HOY es el 10/09/2026: el mes en curso no lleva fecha de corte.
    expect(dobles.tcArgs.at(-1)?.fechaCorte).toBeUndefined()

    dobles.tcArgs = []
    fireEvent.click(screen.getByRole('button', { name: 'Mes anterior' }))
    // Agosto ya cerró: se congela en su último día, así su total no cambia cada
    // mañana. Sin esto, un mes cerrado se recalcularía con la tasa de hoy.
    expect(dobles.tcArgs.at(-1)?.fechaCorte).toBe('2026-08-31')
  })

  it('al pasar la medianoche vuelve a pedir el TC del mes en curso', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    expect(dobles.recargarTc).toBe(0)

    // La clave del hook para el mes en curso no lleva la fecha: una pestaña
    // abierta de un día para otro seguiría convirtiendo con la tasa de ayer
    // mientras la facturación sí se refresca. (Codex, 11/09/2026.)
    act(() => {
      vi.setSystemTime(new Date(2026, 8, 11, 12, 0, 0))
      vi.advanceTimersByTime(600_001)
    })
    expect(dobles.recargarTc).toBe(1)
  })

  it('en un mes cerrado NO recarga al pasar el día: su tasa está congelada', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'Mes anterior' }))
    dobles.recargarTc = 0

    act(() => {
      vi.setSystemTime(new Date(2026, 8, 11, 12, 0, 0))
      vi.advanceTimersByTime(600_001)
    })
    // Agosto ya cerró: recargar su tasa la movería, que es justo lo contrario
    // de congelarla.
    expect(dobles.recargarTc).toBe(0)
  })

  it('en la métrica de contratos suma las dos monedas con cifras, no solo el rótulo', () => {
    dobles.tc = null
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'N.º de contratos' }))
    const pie = within(malla()).getByRole('row', { name: /Total del día/ })
    // El 3 de setiembre tiene un cierre en soles y otro en dólares: son DOS
    // contratos. Se suman tal cual, sin conversión — son cuentas, no dinero.
    expect(within(pie).getAllByText('2 contratos').length).toBeGreaterThanOrEqual(1)
    // Y el mes entero son 5: los 4 en soles más el de dólares.
    expect(within(pie).getByText('5')).toBeInTheDocument()
  })

  it('con tipo de cambio, el pie suma el dólar convertido a soles', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // El mes del fixture: S/ 520,000 en soles y US$ 7,000 en dólares.
    expect(within(pie).getByText('S/ 546,250')).toBeVisible()
    expect(within(malla()).getByText(/TC S\/ 3\.75/)).toBeVisible()
    // Y los días sí llevan cifra: el 3 de setiembre es 40 000 + 7 000 × 3,75.
    expect(within(pie).queryAllByText(/\d/).length).toBeGreaterThan(0)
  })

  it('SIN tipo de cambio calla SOLO los días que tienen dólares', () => {
    dobles.tc = null
    pintar()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // Un día sin un solo dólar tiene su total completo en soles: exigirle tasa
    // pondría un guion sobre una cifra que sí se conoce. (Me lo señaló Codex el
    // 11/09/2026; mi primera versión callaba el mes entero.)
    expect(within(pie).getByText('S/ 380,000')).toBeInTheDocument() // 2/09: 300k + 80k, sin dólares
    // El 3 de setiembre SÍ tiene US$ 7,000, y el mes también: ahí no se afirma.
    expect(within(pie).getAllByText('—')).toHaveLength(2) // el día 3 y el total del mes
    expect(within(pie).queryByText('S/ 520,000')).toBeNull() // el solo-PEN del mes, jamás
    // El motivo sale en el rótulo de la fila Y en el texto accesible del día
    // que se calla: quien use lector no se queda sin la explicación.
    expect(
      within(pie).getAllByText('total no disponible: falta el tipo de cambio').length,
    ).toBeGreaterThanOrEqual(2)
  })

  it('ofrece reintentar cuando el tipo de cambio no llegó', () => {
    dobles.tc = null
    pintar()
    // Una caída del BCRP es transitoria; sin este botón la fila se quedaba en
    // guiones hasta remontar la pantalla. (Codex, 11/09/2026.)
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    expect(within(pie).getByRole('button', { name: /Reintentar/ })).toBeVisible()
  })

  it('con TC no ofrece reintentar: no hay nada que recuperar', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    expect(within(pie).queryByRole('button', { name: /Reintentar/ })).toBeNull()
  })

  it('el importe EXACTO del día se puede consultar, aunque la celda vaya abreviada', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // 3/09: S/ 40,000 + US$ 7,000 × 3,75 = S/ 66,250. La celda pinta «66k»; el
    // importe exacto vive en el texto accesible. Sin esto había que hacer la
    // conversión a mano. (Codex, 11/09/2026.)
    expect(within(pie).getByText('S/ 66,250')).toBeInTheDocument()
  })

  it('si SOLO hay ventas en dólares, la fila NO desaparece: es cuando más sirve', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    // Un mes entero en dólares: la vista en soles marcaría S/ 0 mientras hay
    // dinero, y mi primera versión escondía justo aquí el equivalente.
    pintar([
      fila({ id: 'u1', dia: '2026-09-02', moneda: 'USD', capital: 7_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
    ])
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // Sale dos veces y así debe ser: el día y el total del mes, que con una
    // sola venta son la misma cifra.
    expect(within(pie).getAllByText('S/ 26,250')).toHaveLength(2)
  })

  it('si NO hay un solo dólar, la fila no se pinta: sería un duplicado', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar([
      fila({ id: 'p1', dia: '2026-09-02', moneda: 'PEN', capital: 50_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
    ])
    expect(within(malla()).queryByRole('row', { name: /Total del día en soles/ })).toBeNull()
  })

  it('mientras consulta el TC no dice «no disponible»', () => {
    dobles.tc = undefined
    pintar()
    expect(within(malla()).getByText('consultando el tipo de cambio…')).toBeVisible()
  })

  it('el total en soles NO cambia al cambiar de moneda: es el del día, entero', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    expect(within(within(malla()).getByRole('row', { name: /Total del día en soles/ })).getByText('S/ 546,250')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))
    expect(within(within(malla()).getByRole('row', { name: /Total del día en soles/ })).getByText('S/ 546,250')).toBeVisible()
  })

  it('en contratos se suman las dos monedas, sin conversión que valga', () => {
    dobles.tc = null
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'N.º de contratos' }))
    const pie = within(malla()).getByRole('row', { name: /Total del día/ })
    expect(within(pie).getByText('contratos de ambas monedas')).toBeVisible()
  })
})

describe('moneda y métrica', () => {
  it('cambiar de moneda cambia los números, no quién aparece', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))
    expect(within(malla()).getAllByText('US$ 7,000').length).toBeGreaterThanOrEqual(2)
    // Ana no vendió un solo dólar y aun así conserva su fila: la tabla es el
    // equipo, y las filas no aparecen y desaparecen al tocar un interruptor.
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
  })

  it('el caption dice qué se está midiendo, no siempre «capital»', () => {
    pintar()
    expect(within(malla()).getByText(/^Capital por día/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'N.º de contratos' }))
    expect(within(malla()).getByText(/^N.º de contratos por día/)).toBeInTheDocument()
  })
})

describe('restablecer', () => {
  it('está montado siempre: no desaparece bajo el foco de quien lo pulsa', () => {
    pintar()
    const boton = screen.getByRole('button', { name: 'Restablecer filtros' })
    expect(boton).toBeDisabled()

    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-sara' } })
    expect(boton).toBeEnabled()

    fireEvent.click(boton)
    expect(screen.getByRole('button', { name: 'Restablecer filtros' })).toBeDisabled()
    expect(screen.getByRole('button', { name: /Rosa Uno/ })).toBeVisible()
  })
})
